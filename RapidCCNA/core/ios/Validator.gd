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
	if a.has("iface") and _ifaces(d, a.iface).is_empty():
		return _fail("%s has no interface %s" % [d.hostname, a.iface])
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
			if a.has("code") and r.code != a.code:
				return _fail("the route to %s is %s, not %s" % [a.dest, RoutingTable.NAMES.get(r.code, r.code), RoutingTable.NAMES.get(a.code, a.code)])
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
		"stp_mode":
			return _res(d.stp_mode == a.mode, "spanning tree mode is %s" % d.stp_mode)
		"stp_root":
			var res := L2Sim.stp(net, int(a.vlan))
			if res.is_empty():
				return _fail("VLAN %d has no spanning tree" % a.vlan)
			return _res(res.root == d.hostname, "%s is the root bridge for VLAN %d" % [res.root, a.vlan])
		"stp_role":
			var n := Device.canon_iface(a.iface)
			var role := L2Sim.role(net, d.hostname, n, int(a.vlan))
			return _res(role == a.role, "%s %s is %s in VLAN %d" % [d.hostname, Device.short_name(n), role.to_lower() if not role.is_empty() else "not forwarding", a.vlan])
		"portfast":
			for n in _ifaces(d, a.iface):
				var i: Dictionary = d.interfaces[n]
				if not i.portfast:
					return _fail("PortFast isn't enabled on %s" % n)
				if a.get("bpduguard", false) and not i.bpduguard:
					return _fail("BPDU Guard isn't enabled on %s" % n)
			return _ok()
		"etherchannel":
			var ch := L2Sim.channel(net, d.hostname, int(a.group))
			if ch.members.is_empty():
				return _fail("no ports are in channel group %d" % a.group)
			if a.has("protocol") and ch.protocol != a.protocol:
				return _fail("channel group %d uses %s" % [a.group, ch.protocol if ch.protocol != "static" else "mode on (no protocol)"])
			var bundled: Array = ch.members.filter(func(m): return m.flag == "P")
			if bundled.size() < int(a.get("members", 1)):
				var bad: Array = ch.members.filter(func(m): return m.flag != "P")
				return _fail("%d of %d members bundled%s" % [bundled.size(), ch.members.size(), (": " + bad[0].why) if bad.size() > 0 else ""])
			return _res(ch.up, "Port-channel%d is down" % a.group)
		"ospf_rid":
			if d.ospf.is_empty():
				return _fail("OSPF isn't running")
			var rid := OspfSim.router_id(d)
			return _res(rid == a.rid, "router ID is %s" % rid)
		"ospf_enabled":
			var en := OspfSim.enabled(d)
			var n := Device.canon_iface(a.iface)
			if not en.has(n):
				return _fail("OSPF isn't enabled on %s" % n)
			if a.has("area") and str(en[n].area) != str(a.area):
				return _fail("%s is in area %s" % [n, en[n].area])
			return _ok()
		"ospf_passive":
			var en := OspfSim.enabled(d)
			var n := Device.canon_iface(a.iface)
			if not en.has(n):
				return _fail("OSPF isn't enabled on %s" % n)
			return _res(en[n].passive == a.get("passive", true), "%s is %spassive" % [n, "" if en[n].passive else "not "])
		"ospf_neighbor":
			if OspfSim.neighbors(net, d.hostname).any(func(x): return x.name == a.neighbor):
				return _ok()
			for adj in OspfSim.adjacencies(net):
				if (adj.a == d.hostname and adj.b == a.neighbor) or (adj.b == d.hostname and adj.a == a.neighbor):
					return _fail("no adjacency with %s: %s" % [a.neighbor, ", ".join(adj.issues.map(func(k): return OSPF.ISSUE_TEXT[k].to_lower()))])
			return _fail("%s has no OSPF neighbour %s" % [d.hostname, a.neighbor])
		"cdp_run":
			return _res(d.cdp_run == a.get("enabled", true), "CDP is %s globally" % ("on" if d.cdp_run else "off"))
		"lldp_run":
			return _res(d.lldp_run == a.get("enabled", true), "LLDP is %s globally" % ("on" if d.lldp_run else "off"))
		"cdp_iface":
			for n in _ifaces(d, a.iface):
				if d.interfaces[n].cdp != a.get("enabled", true):
					return _fail("CDP is %s on %s" % ["enabled" if d.interfaces[n].cdp else "disabled", n])
			return _ok()
		"lldp_iface":
			for n in _ifaces(d, a.iface):
				var i: Dictionary = d.interfaces[n]
				if a.has("transmit") and i.lldp_tx != a.transmit:
					return _fail("LLDP transmit is %s on %s" % ["on" if i.lldp_tx else "off", n])
				if a.has("receive") and i.lldp_rx != a.receive:
					return _fail("LLDP receive is %s on %s" % ["on" if i.lldp_rx else "off", n])
			return _ok()
		"iface_description":
			var i: Dictionary = d.iface(a.iface)
			var desc: String = i.get("description", "")
			return _res(desc.to_lower().contains(str(a.contains).to_lower()), "%s's description is '%s'" % [Device.short_name(Device.canon_iface(a.iface)), desc])
		"discovers":
			var seen: Array = Discovery.neighbors(net, d.hostname, a.get("protocol", "cdp")).map(func(x): return x.device)
			return _res((a.neighbor in seen) == a.get("present", true), "%s %s %s via %s" % [d.hostname, "sees" if a.neighbor in seen else "doesn't see", a.neighbor, a.get("protocol", "cdp").to_upper()])
	return _fail("unknown check %s" % c.get("check", ""))

static func _ok() -> Dictionary:
	return {"ok": true, "msg": ""}

static func _fail(m: String) -> Dictionary:
	return {"ok": false, "msg": m}

static func _res(ok: bool, m: String) -> Dictionary:
	return _ok() if ok else _fail(m)
