class_name Validator
extends RefCounted
## Checks lab goals against simulated device state (behaviour, not config text).
## A check: {device, check, args}. Returns {ok: bool, msg: String} (msg explains a failure).

static func _ifaces(d: Device, spec: String) -> Array:
	var r := Commands.parse_range(d, spec)
	return r

static func run(net: Network, c: Dictionary) -> Dictionary:
	var d: Device = net.devices.get(c.get("device", ""), null)
	if d == null:
		return _fail("unknown device %s" % c.get("device", ""))
	var a: Dictionary = c.get("args", {})
	match c.get("check", ""):
		"hostname":
			return _res(d.hostname == a.name, "hostname is %s" % d.hostname)
		"vlan_exists":
			if not d.vlans.has(int(a.id)):
				return _fail("VLAN %d doesn't exist" % a.id)
			if a.has("name") and d.vlans[int(a.id)] != a.name:
				return _fail("VLAN %d is named %s, not %s" % [a.id, d.vlans[int(a.id)], a.name])
			return _ok()
		"access_port":
			for n in _ifaces(d, a.iface):
				var i: Dictionary = d.interfaces[n]
				if i.mode != "access":
					return _fail("%s isn't in static access mode" % n)
				if a.has("vlan") and i.access_vlan != int(a.vlan):
					return _fail("%s is in VLAN %d" % [n, i.access_vlan])
			return _ok()
		"trunk_port":
			for n in _ifaces(d, a.iface):
				var i: Dictionary = d.interfaces[n]
				if i.mode != "trunk":
					return _fail("%s isn't a static trunk" % n)
				if a.has("native") and i.native != int(a.native):
					return _fail("%s native VLAN is %d" % [n, i.native])
				if a.has("allowed"):
					var want := Device.parse_vlan_list(a.allowed)
					var have: Array = range(1, 4095) if i.allowed == "all" else Device.parse_vlan_list(i.allowed)
					want.sort()
					have.sort()
					if want != have:
						return _fail("%s allows %s" % [n, "all VLANs" if i.allowed == "all" else i.allowed])
			return _ok()
		"iface_ip":
			var i: Dictionary = d.iface(a.iface)
			return _res(i.get("ip", "") == a.ip and i.get("mask", "") == a.mask, "%s is %s %s" % [a.iface, i.get("ip", "unassigned"), i.get("mask", "")])
		"iface_up":
			for n in _ifaces(d, a.iface):
				if not d.is_up(d.interfaces[n]):
					return _fail("%s is %s" % [n, d.status(d.interfaces[n])[0]])
			return _ok()
		"iface_shutdown":
			for n in _ifaces(d, a.iface):
				if not d.interfaces[n].shutdown:
					return _fail("%s isn't administratively down" % n)
			return _ok()
		"route_to":
			var r := d.routing_table().lookup(IPv4.parse(a.dest))
			if r.is_empty():
				return _fail("no route to %s" % a.dest)
			if a.has("next_hop") and r.next_hop != a.next_hop:
				return _fail("traffic to %s uses %s" % [a.dest, RoutingTable.describe(r)])
			return _ok()
		"static_route":
			var net_i := IPv4.parse(a.net)
			for r in d.static_routes:
				if r.net == net_i and r.len == int(a.len) and (not a.has("next_hop") or r.next_hop == a.next_hop) and (not a.has("ad") or r.ad == int(a.ad)):
					return _ok()
			return _fail("no matching static route for %s/%d" % [a.net, a.len])
		"ping":
			var p := net.ping_ok(c.device, a.to)
			return _res(p.ok, p.get("reason", ""))
		"nat_iface":
			var i: Dictionary = d.iface(a.iface)
			return _res(i.get("nat", "") == a.side, "%s isn't 'ip nat %s'" % [a.iface, a.side])
		"nat_translates":
			var g := d.nat_translate(a.inside)
			return _res(g == a.global, "%s translates to %s" % [a.inside, g if not g.is_empty() else "nothing"])
		"port_security":
			for n in _ifaces(d, a.iface):
				var ps: Dictionary = d.interfaces[n].ps
				if not ps.enabled:
					return _fail("port security isn't enabled on %s" % n)
				if a.has("maximum") and ps.maximum != int(a.maximum):
					return _fail("%s maximum is %d" % [n, ps.maximum])
				if a.has("violation") and ps.violation != a.violation:
					return _fail("%s violation mode is %s" % [n, ps.violation])
				if a.has("sticky") and ps.sticky != a.sticky:
					return _fail("sticky learning isn't enabled on %s" % n)
			return _ok()
		"acl_permits":
			var acl: Dictionary = d.acls.get(str(a.acl), {})
			if acl.is_empty():
				return _fail("ACL %s doesn't exist" % a.acl)
			var v := ACL.evaluate(acl.entries, {"proto": "ip", "src": IPv4.parse(a.src), "dst": 0})
			return _res(v == a.get("action", "permit"), "ACL %s %ss %s" % [a.acl, v, a.src])
		"acl_decides":
			var i: Dictionary = d.iface(a.iface)
			var name: String = i.get("acl_in" if a.get("dir", "in") == "in" else "acl_out", "")
			if name.is_empty() or not d.acls.has(name):
				return _fail("no ACL applied %s on %s" % [a.get("dir", "in"), a.iface])
			var pkt := {"proto": a.proto, "src": IPv4.parse(a.src), "dst": IPv4.parse(a.dst), "dport": int(a.get("dport", -1))}
			var verdict := ACL.evaluate(d.acls[name].entries, pkt)
			return _res(verdict == a.action, "that packet is %sed" % verdict)
	return _fail("unknown check %s" % c.get("check", ""))

static func _ok() -> Dictionary:
	return {"ok": true, "msg": ""}

static func _fail(m: String) -> Dictionary:
	return {"ok": false, "msg": m}

static func _res(ok: bool, m: String) -> Dictionary:
	return _ok() if ok else _fail(m)
