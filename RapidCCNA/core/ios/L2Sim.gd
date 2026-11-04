class_name L2Sim
extends RefCounted
## Layer 2 protocols across a lab Network: EtherChannel bundling and per-VLAN spanning tree.

const DEFAULT_PRIORITY := 32768

## Switchport settings that must match the port-channel for a member to bundle.
static func _settings(i: Dictionary) -> Dictionary:
	return {"mode": i.mode, "vlan": i.access_vlan if i.mode != "trunk" else 0,
		"native": i.native if i.mode == "trunk" else 0, "allowed": i.allowed if i.mode == "trunk" else ""}

## State of channel group g on a device:
## {exists, up, protocol, members: [{port, flag, why}]} with flags P (bundled), s, I, D.
static func channel(net: Network, dev: String, g: int) -> Dictionary:
	var d: Device = net.devices[dev]
	var po: Dictionary = d.interfaces.get("Port-channel%d" % g, {})
	var out := {"exists": not po.is_empty(), "up": false, "protocol": "", "members": []}
	for n in d.members(g):
		var i: Dictionary = d.interfaces[n]
		out.protocol = EtherChannel.protocol_of(i.channel_mode)
		var m := {"port": n, "flag": "P", "why": ""}
		var nb := net.neighbor(dev, n)
		if i.shutdown or not i.link or nb.is_empty():
			m.flag = "D"
			m.why = "%s is down" % n
		else:
			var pd: Device = net.devices[nb[0]]
			var pi: Dictionary = pd.interfaces.get(nb[1], {})
			if pi.is_empty() or pi.shutdown:
				m.flag = "D"
				m.why = "%s %s is down" % [nb[0], nb[1]]
			elif pi.channel_group == 0:
				m.flag = "I" if i.channel_mode != "on" else "D"
				m.why = "%s %s isn't in a channel group" % [nb[0], nb[1]]
			else:
				var neg := EtherChannel.negotiate(i.channel_mode, pi.channel_mode)
				if not neg.forms:
					m.flag = "I" if i.channel_mode != "on" else "D"
					m.why = neg.reason
				elif not po.is_empty() and _settings(i) != _settings(po):
					m.flag = "s"
					m.why = "%s's switchport settings don't match Port-channel%d" % [n, g]
		out.members.append(m)
	out.up = out.exists and not po.get("shutdown", false) and out.members.any(func(m): return m.flag == "P")
	return out

static func show_summary(net: Network, dev: String) -> String:
	var d: Device = net.devices[dev]
	var groups: Array = []
	var seen := {}
	for n in d.iface_order:
		var g: int = d.interfaces[n].channel_group
		if g > 0 and not seen.has(g):
			seen[g] = true
			var c := channel(net, dev, g)
			groups.append({"group": g, "protocol": c.protocol if c.protocol != "static" else "-", "layer": "S", "up": c.up,
				"members": c.members.map(func(m): return {"port": Device.short_name(m.port), "flag": m.flag})})
	return EtherChannel.show_summary(groups)

## Logical L2 port a physical port belongs to (its port-channel when bundled), or "" if it doesn't forward.
static func _logical(net: Network, d: Device, n: String) -> String:
	var i: Dictionary = d.interfaces[n]
	if i.channel_group > 0:
		var c := channel(net, d.key, i.channel_group)
		var mine: Array = c.members.filter(func(m): return m.port == n)
		if mine.size() > 0 and mine[0].flag == "P":
			return "Port-channel%d" % i.channel_group
		return "" if mine.size() > 0 and mine[0].flag in ["s", "D"] else n
	return n

static func carries(d: Device, i: Dictionary, vlan: int) -> bool:
	return d.trunk_allows(i, vlan) or (i.mode != "trunk" and i.access_vlan == vlan)

static func port_cost(d: Device, n: String) -> int:
	var i: Dictionary = d.interfaces[n]
	if i.stp_cost > 0:
		return i.stp_cost
	if n.begins_with("Port-channel"):
		var m: Array = d.members(n.substr(12).to_int())
		var bw := 0.0
		for x in m:
			bw += d.bandwidth(x)
		return 3 if bw >= 2000 else STP.cost_for(int(bw)) if bw > 0 else 4
	return STP.cost_for(int(d.bandwidth(n)))

static func port_id(d: Device, n: String) -> int:
	return STP.port_id(128, "x%d" % (d.iface_order.find(n) + 1))

static func bridge(d: Device, vlan: int) -> Dictionary:
	return {"name": d.key, "priority": STP.bridge_priority(int(d.stp_priority.get(vlan, DEFAULT_PRIORITY)), vlan), "mac": d.mac}

## Spanning tree for a VLAN over every switch: STP.solve() result plus per-switch port lists.
static func stp(net: Network, vlan: int) -> Dictionary:
	var switches: Array = []
	for name in net.devices:
		var d: Device = net.devices[name]
		if d.type == "switch" and d.vlans.has(vlan):
			switches.append(bridge(d, vlan))
	var names := {}
	for s in switches:
		names[s.name] = true
	var links: Array = []
	var seen := {}
	for l in net.links:
		if not names.has(l[0]) or not names.has(l[2]):
			continue
		var da: Device = net.devices[l[0]]
		var db: Device = net.devices[l[2]]
		var la := _logical(net, da, l[1])
		var lb := _logical(net, db, l[3])
		if la.is_empty() or lb.is_empty():
			continue
		var ia: Dictionary = da.interfaces[la]
		var ib: Dictionary = db.interfaces[lb]
		if not da.is_up(ia) or not db.is_up(ib) or not carries(da, ia, vlan) or not carries(db, ib, vlan):
			continue
		var key := "%s %s|%s %s" % [l[0], la, l[2], lb]
		if seen.has(key):
			continue   # another member of the same bundle
		seen[key] = true
		links.append({"a": l[0], "ap": la, "b": l[2], "bp": lb, "a_cost": port_cost(da, la), "b_cost": port_cost(db, lb),
			"a_pid": port_id(da, la), "b_pid": port_id(db, lb)})
	if switches.is_empty():
		return {}
	return STP.solve(switches, links)

## Role of a port in a VLAN ("" if the port isn't forwarding in that VLAN at all).
static func role(net: Network, dev: String, port: String, vlan: int) -> String:
	var d: Device = net.devices[dev]
	var res := stp(net, vlan)
	if res.is_empty() or not d.interfaces.has(port):
		return ""
	var lp := _logical(net, d, port)
	if lp.is_empty() or not d.is_up(d.interfaces[lp]) or not carries(d, d.interfaces[lp], vlan):
		return ""
	return res.roles.get("%s %s" % [dev, Device.short_name(lp)], res.roles.get("%s %s" % [dev, lp], "Designated"))

static func show_vlan(net: Network, dev: String, vlan: int) -> String:
	var d: Device = net.devices[dev]
	var res := stp(net, vlan)
	if res.is_empty() or not res.by_name.has(dev):
		return "Spanning tree instance(s) for vlan %d does not exist." % vlan
	var ports: Array = []
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		if not d.is_switchport(i) or _logical(net, d, n) != n or not d.is_up(i) or not carries(d, i, vlan):
			continue
		ports.append({"port": Device.short_name(n), "cost": port_cost(d, n), "pid": port_id(d, n), "type": "P2p Edge" if i.portfast else "P2p"})
	# STP.show() keys roles by "<switch> <port>" with the port as named in links (full names here).
	var short_roles := {}
	for k in res.roles:
		var parts: PackedStringArray = k.split(" ")
		short_roles["%s %s" % [parts[0], Device.short_name(parts[1])]] = res.roles[k]
	var rp := {}
	for sw in res.root_port:
		rp[sw] = Device.short_name(res.root_port[sw])
	var view := res.duplicate()
	view.roles = short_roles
	view.root_port = rp
	var text := STP.show(view, dev, vlan, ports)
	var proto := "rstp" if d.stp_mode == "rapid-pvst" else "ieee"
	return text.replace("protocol rstp", "protocol " + proto)

static func show_all(net: Network, dev: String) -> String:
	var d: Device = net.devices[dev]
	var ids := d.vlans.keys()
	ids.sort()
	var out := PackedStringArray()
	for v in ids:
		var t := show_vlan(net, dev, v)
		var has_ports := d.iface_order.any(func(n): return d.is_switchport(d.interfaces[n]) and d.is_up(d.interfaces[n]) and carries(d, d.interfaces[n], v))
		if has_ports and not t.begins_with("Spanning tree instance"):
			out.append(t)
	return "\n\n".join(out) if out.size() > 0 else "No spanning tree instance exists."
