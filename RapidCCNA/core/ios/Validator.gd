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
		return _fail("%s has no interface %s" % [d.key, a.iface])
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
			return _res(res.root == d.key, "%s is the root bridge for VLAN %d" % [res.root, a.vlan])
		"stp_role":
			var n := Device.canon_iface(a.iface)
			var role := L2Sim.role(net, d.key, n, int(a.vlan))
			return _res(role == a.role, "%s %s is %s in VLAN %d" % [d.key, Device.short_name(n), role.to_lower() if not role.is_empty() else "not forwarding", a.vlan])
		"portfast":
			for n in _ifaces(d, a.iface):
				var i: Dictionary = d.interfaces[n]
				if not i.portfast:
					return _fail("PortFast isn't enabled on %s" % n)
				if a.get("bpduguard", false) and not i.bpduguard:
					return _fail("BPDU Guard isn't enabled on %s" % n)
			return _ok()
		"etherchannel":
			var ch := L2Sim.channel(net, d.key, int(a.group))
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
			if OspfSim.neighbors(net, d.key).any(func(x): return x.name == a.neighbor):
				return _ok()
			for adj in OspfSim.adjacencies(net):
				if (adj.a == d.key and adj.b == a.neighbor) or (adj.b == d.key and adj.a == a.neighbor):
					return _fail("no adjacency with %s: %s" % [a.neighbor, ", ".join(adj.issues.map(func(k): return OSPF.ISSUE_TEXT[k].to_lower()))])
			return _fail("%s has no OSPF neighbour %s" % [d.key, a.neighbor])
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
			var seen: Array = Discovery.neighbors(net, d.key, a.get("protocol", "cdp")).map(func(x): return x.device)
			return _res((a.neighbor in seen) == a.get("present", true), "%s %s %s via %s" % [d.key, "sees" if a.neighbor in seen else "doesn't see", a.neighbor, a.get("protocol", "cdp").to_upper()])
		"ssh_ready":
			return ssh_ready(d, int(a.get("version", 0)))
		"local_user":
			if not d.users.has(a.name):
				return _fail("there's no local user %s" % a.name)
			return _res(not a.has("privilege") or d.users[a.name].privilege == int(a.privilege), "%s has privilege %d" % [a.name, d.users[a.name].privilege])
		"ntp_server":
			if not a.ip in d.ntp_servers:
				return _fail("%s isn't configured as an NTP server" % a.ip)
			var p := net.ping_ok(d.key, a.ip)
			return _res(p.ok, "NTP server %s is unreachable: %s" % [a.ip, p.reason])
		"logging_host":
			if not a.ip in d.logging_hosts:
				return _fail("logs aren't sent to %s" % a.ip)
			if a.has("trap") and d.logging_trap != a.trap:
				return _fail("the trap level is %s" % d.logging_trap)
			if a.get("timestamps", false) and not d.log_timestamps:
				return _fail("log messages have no date/time timestamps")
			return _ok()
		"snmp_community":
			if not d.snmp_communities.has(a.name):
				return _fail("there's no SNMP community %s" % a.name)
			var sc: Dictionary = d.snmp_communities[a.name]
			if a.has("access") and sc.access != a.access:
				return _fail("community %s is %s" % [a.name, sc.access.to_upper()])
			return _res(not a.has("acl") or sc.acl == str(a.acl), "community %s is %s" % [a.name, "not limited by an ACL" if sc.acl.is_empty() else "limited by ACL " + sc.acl])
		"dhcp_lease":
			var l := DhcpSim.lease(net, d.key)
			if not l.ok:
				return _fail(d.key + " gets no address: " + l.reason)
			if a.has("subnet"):
				var parts: PackedStringArray = str(a.subnet).split("/")
				if IPv4.network(IPv4.parse(l.ip), parts[1].to_int()) != IPv4.parse(parts[0]):
					return _fail("%s got %s, outside %s" % [d.key, l.ip, a.subnet])
			if a.has("not_below") and IPv4.parse(l.ip) < IPv4.parse(a.not_below):
				return _fail("%s got %s, which should have been excluded" % [d.key, l.ip])
			if a.has("gateway") and l.gateway != a.gateway:
				return _fail("%s's default gateway is %s" % [d.key, l.gateway if not l.gateway.is_empty() else "missing"])
			if a.has("dns") and l.dns != a.dns:
				return _fail("%s's DNS server is %s" % [d.key, l.dns if not l.dns.is_empty() else "missing"])
			return _ok()
		"hsrp":
			var st := HsrpSim.status(net, d.key, Device.canon_iface(a.iface), int(a.group))
			if st.is_empty():
				return _fail("HSRP group %d isn't configured on %s" % [a.group, a.iface])
			if a.has("vip") and st.st.vip != a.vip:
				return _fail("group %d's virtual IP is %s" % [a.group, st.st.vip if not st.st.vip.is_empty() else "not set"])
			if a.has("state") and st.state != a.state:
				return _fail("%s is %s in group %d" % [d.key, st.state, a.group])
			if a.has("preempt") and st.cfg.preempt != a.preempt:
				return _fail("preempt is %s on %s" % ["on" if st.cfg.preempt else "off", d.key])
			if a.has("track"):
				var tracked: Array = st.cfg.track.filter(func(t): return t[0] == Device.canon_iface(a.track))
				if tracked.is_empty():
					return _fail("%s doesn't track %s" % [d.key, a.track])
				var after: int = int(st.cfg.priority) - int(tracked[0][1])
				if a.has("track_below") and after >= int(a.track_below):
					return _fail("if %s fails, the priority only drops to %d, not below %d" % [a.track, after, a.track_below])
			return _ok()
		"enable_secret":
			if d.enable_secret.is_empty():
				return _fail("there's no enable secret" + (" (an enable password is only stored with weak or no encryption)" if not d.enable_password.is_empty() else ""))
			return _ok()
		"password_encryption":
			return _res(d.password_encryption, "line passwords are stored in clear text (service password-encryption is off)")
		"line_auth":
			var l: Dictionary = d.lines.get(a.line, {})
			if l.is_empty():
				return _fail("line %s isn't configured" % a.line)
			if a.get("password", false) and l.password.is_empty():
				return _fail("line %s has no password" % a.line)
			if a.has("login") and l.login != a.login:
				return _fail("line %s uses %s" % [a.line, "no login check" if l.login.is_empty() else "'%s'" % l.login])
			if a.has("transport") and l.transport != a.transport:
				return _fail("line %s allows %s" % [a.line, "every transport (Telnet included)" if l.transport.is_empty() else l.transport])
			if a.has("timeout") and l.get("timeout", -1) != int(a.timeout):
				return _fail("line %s's exec-timeout is %s" % [a.line, "the default (10 minutes)" if l.get("timeout", -1) < 0 else "%d minutes" % l.timeout])
			return _ok()
		"ssh_version":
			if d.ssh_version == int(a.version):
				return _ok()
			return _fail("SSH accepts versions 1 and 2 (1.99); version 2 isn't enforced" if d.ssh_version == 0 else "SSH version %d is enforced" % d.ssh_version)
		"rsa_key":
			if d.rsa_bits == 0:
				return _fail("there's no RSA key pair")
			return _res(d.rsa_bits >= int(a.get("min_bits", 768)), "the RSA key is only %d bits" % d.rsa_bits)
	return _fail("unknown check %s" % c.get("check", ""))

static func _ok() -> Dictionary:
	return {"ok": true, "msg": ""}

static func _fail(m: String) -> Dictionary:
	return {"ok": false, "msg": m}

static func _res(ok: bool, m: String) -> Dictionary:
	return _ok() if ok else _fail(m)

## Can you SSH into this device? The first missing piece explains why not.
static func ssh_ready(d: Device, version: int = 0) -> Dictionary:
	if d.hostname in ["Router", "Switch"]:
		return _fail("the hostname is still the default")
	if d.domain_name.is_empty():
		return _fail("there's no ip domain name, so no RSA key can be generated")
	if d.rsa_bits == 0:
		return _fail("no RSA key pair: crypto key generate rsa")
	if version == 2 and d.ssh_version != 2:
		return _fail("SSH version 2 isn't enforced (ip ssh version 2)")
	if d.users.is_empty():
		return _fail("there's no local username to log in with")
	var vty: Array = d.lines.keys().filter(func(k): return k.begins_with("vty 0"))
	if vty.is_empty():
		return _fail("the VTY lines aren't configured")
	for k in vty:
		var l: Dictionary = d.lines[k]
		if l.login != "login local":
			return _fail("line %s doesn't use 'login local'" % k)
		if l.transport != "ssh":
			return _fail("line %s allows %s" % [k, "Telnet as well as SSH (transport input isn't ssh)" if l.transport.is_empty() else "transport input " + l.transport])
	return _ok()
