class_name Network
extends RefCounted
## Devices plus point-to-point links. Forwards packets hop by hop through each
## device's routing table, so ping works only if routes exist in both directions.

var devices: Dictionary = {}   # hostname -> Device
var links: Array = []          # [devA, ifA, devB, ifB]

static func build(lab: Dictionary) -> Network:
	var net := Network.new()
	for def in lab.get("devices", []):
		net.devices[def.name] = Device.create(def)
		net.devices[def.name]._net = weakref(net)
	for l in lab.get("links", []):
		net.links.append([l[0], Device.canon_iface(l[1]), l[2], Device.canon_iface(l[3])])
	return net

func neighbor(dev: String, iface: String) -> Array:
	for l in links:
		if l[0] == dev and l[1] == iface:
			return [l[2], l[3]]
		if l[2] == dev and l[3] == iface:
			return [l[0], l[1]]
	return []

func owns(dev: String, ip: String) -> bool:
	var d: Device = devices[dev]
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		if i.ip == ip and d.is_up(i):
			return true
	return false

## Follows routes from `from` towards dest. Returns {ok, path, reason}.
func forward(from: String, dest: String) -> Dictionary:
	var cur := from
	var path: Array = [from]
	var dest_ip := IPv4.parse(dest)
	for hop in 16:
		if owns(cur, dest):
			return {"ok": true, "path": path, "reason": ""}
		var d: Device = devices[cur]
		var rt := d.routing_table()
		var r := rt.lookup(dest_ip)
		if r.is_empty():
			return {"ok": false, "path": path, "reason": "%s has no route to %s" % [cur, dest]}
		var out_if: String = r.iface
		var target := dest
		if not r.next_hop.is_empty():
			var via := rt.lookup(IPv4.parse(r.next_hop))
			if via.is_empty() or not via.code in ["C", "L"]:
				return {"ok": false, "path": path, "reason": "%s can't reach next hop %s" % [cur, r.next_hop]}
			out_if = via.iface
			target = r.next_hop
		elif r.code == "L":
			return {"ok": true, "path": path, "reason": ""}
		var nb := neighbor(cur, out_if)
		if nb.is_empty():
			return {"ok": false, "path": path, "reason": "nothing is connected to %s %s" % [cur, out_if]}
		var nd: Device = devices[nb[0]]
		var ni: Dictionary = nd.interfaces.get(nb[1], {})
		if ni.is_empty() or not nd.is_up(ni):
			return {"ok": false, "path": path, "reason": "%s %s is down" % [nb[0], nb[1]]}
		# Connected delivery: the neighbour must own the address (no ARP reply otherwise).
		# Static routes to an exit interface rely on proxy ARP, so the neighbour may route onward.
		if r.code == "C" and not owns(nb[0], dest):
			return {"ok": false, "path": path, "reason": "no device answers for %s on %s %s" % [dest, cur, out_if]}
		if target != dest and not owns(nb[0], target):
			return {"ok": false, "path": path, "reason": "next hop %s isn't on the link out of %s" % [target, out_if]}
		cur = nb[0]
		path.append(cur)
	return {"ok": false, "path": path, "reason": "routing loop"}

## Source address for traffic from dev to dest: the exit interface's IP.
func source_ip(dev: String, dest: String) -> String:
	var d: Device = devices[dev]
	var rt := d.routing_table()
	var r := rt.lookup(IPv4.parse(dest))
	if r.is_empty():
		return ""
	var out_if: String = r.iface
	if not r.next_hop.is_empty():
		out_if = rt.lookup(IPv4.parse(r.next_hop)).get("iface", "")
	return d.interfaces.get(out_if, {}).get("ip", "")

func ping_ok(from: String, dest: String) -> Dictionary:
	var there := forward(from, dest)
	if not there.ok:
		return there
	var src := source_ip(from, dest)
	if src.is_empty():
		return there   # pinging own address
	var owner := ""
	for n in devices:
		if owns(n, dest):
			owner = n
	var back := forward(owner, src)
	if not back.ok:
		back.reason = "the reply can't get back: " + back.reason
	return back

func ping(from: String, dest: String) -> String:
	var r := ping_ok(from, dest)
	var marks := "!!!!!" if r.ok else "....."
	var rate := "100 percent (5/5), round-trip min/avg/max = 1/2/4 ms" if r.ok else "0 percent (0/5)"
	return "Type escape sequence to abort.\nSending 5, 100-byte ICMP Echos to %s, timeout is 2 seconds:\n%s\nSuccess rate is %s" % [dest, marks, rate]
