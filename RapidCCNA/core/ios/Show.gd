class_name Show
extends RefCounted
## Renders IOS show command output from Device state.

static func vlan_list_str(vlans: Array) -> String:
	var v := vlans.duplicate()
	v.sort()
	var parts := PackedStringArray()
	var i := 0
	while i < v.size():
		var j := i
		while j + 1 < v.size() and v[j + 1] == v[j] + 1:
			j += 1
		parts.append(str(v[i]) if j == i else "%d-%d" % [v[i], v[j]])
		i = j + 1
	return ",".join(parts)

static func _iface_block(d: Device, n: String) -> PackedStringArray:
	var i: Dictionary = d.interfaces[n]
	var b := PackedStringArray(["interface " + n])
	if not i.description.is_empty():
		b.append(" description " + i.description)
	if d.is_switchport(i):
		if i.mode == "trunk":
			if i.native != 1:
				b.append(" switchport trunk native vlan %d" % i.native)
			if i.allowed != "all":
				b.append(" switchport trunk allowed vlan " + i.allowed)
			b.append(" switchport mode trunk")
		else:
			if i.access_vlan != 1:
				b.append(" switchport access vlan %d" % i.access_vlan)
			if i.mode == "access":
				b.append(" switchport mode access")
		if i.nonegotiate:
			b.append(" switchport nonegotiate")
		if i.ps.enabled or i.ps.maximum != 1 or i.ps.sticky or i.ps.violation != "shutdown":
			if i.ps.enabled:
				b.append(" switchport port-security")
			if i.ps.maximum != 1:
				b.append(" switchport port-security maximum %d" % i.ps.maximum)
			if i.ps.violation != "shutdown":
				b.append(" switchport port-security violation " + i.ps.violation)
			if i.ps.sticky:
				b.append(" switchport port-security mac-address sticky")
		for m in i.ps.macs:
			b.append(" switchport port-security mac-address " + m)
		if i.channel_group > 0:
			b.append(" channel-group %d mode %s" % [i.channel_group, i.channel_mode])
		if i.stp_cost > 0:
			b.append(" spanning-tree cost %d" % i.stp_cost)
		if i.portfast:
			b.append(" spanning-tree portfast")
		if i.bpduguard:
			b.append(" spanning-tree bpduguard enable")
	else:
		b.append(" ip address %s %s" % [i.ip, i.mask] if not i.ip.is_empty() else " no ip address")
		if not i.nat.is_empty():
			b.append(" ip nat " + i.nat)
		if not i.acl_in.is_empty():
			b.append(" ip access-group %s in" % i.acl_in)
		if not i.acl_out.is_empty():
			b.append(" ip access-group %s out" % i.acl_out)
		for h in i.helpers:
			b.append(" ip helper-address " + h)
		if i.hsrp_version != 1:
			b.append(" standby version %d" % i.hsrp_version)
		for g in i.hsrp:
			var c: Dictionary = i.hsrp[g]
			if not c.ip.is_empty():
				b.append(" standby %d ip %s" % [int(g), c.ip])
			if int(c.priority) != HsrpSim.DEFAULT_PRIORITY:
				b.append(" standby %d priority %d" % [int(g), int(c.priority)])
			if c.preempt:
				b.append(" standby %d preempt" % int(g))
			for t in c.track:
				b.append(" standby %d track %s %d" % [int(g), t[0], int(t[1])])
		if i.ospf_hello != 10:
			b.append(" ip ospf hello-interval %d" % i.ospf_hello)
		if i.ospf_dead != 4 * i.ospf_hello:
			b.append(" ip ospf dead-interval %d" % i.ospf_dead)
		if i.ospf_priority != 1:
			b.append(" ip ospf priority %d" % i.ospf_priority)
		if i.ospf_cost > 0:
			b.append(" ip ospf cost %d" % i.ospf_cost)
		if not i.ospf_area.is_empty():
			b.append(" ip ospf %d area %s" % [i.ospf_pid, i.ospf_area])
	if not i.cdp:
		b.append(" no cdp enable")
	if not i.lldp_tx:
		b.append(" no lldp transmit")
	if not i.lldp_rx:
		b.append(" no lldp receive")
	if i.shutdown:
		b.append(" shutdown")
	return b

static func running_config(d: Device) -> String:
	var out := PackedStringArray(["Building configuration...", "", "Current configuration:", "!", "hostname " + d.hostname, "!"])
	if d.password_encryption:
		out.append_array(["service password-encryption", "!"])
	if d.log_timestamps:
		out.append_array(["service timestamps log datetime msec", "!"])
	if not d.domain_name.is_empty():
		out.append("ip domain name " + d.domain_name)
	for ex in d.dhcp_excluded:
		out.append("ip dhcp excluded-address %s%s" % [IPv4.to_str(ex[0]), "" if ex[0] == ex[1] else " " + IPv4.to_str(ex[1])])
	for name in d.dhcp_pools:
		var p: Dictionary = d.dhcp_pools[name]
		out.append("ip dhcp pool " + name)
		if not p.network.is_empty():
			out.append(" network %s %s" % [p.network, p.mask])
		if not p.router.is_empty():
			out.append(" default-router " + p.router)
		if not p.dns.is_empty():
			out.append(" dns-server " + p.dns)
	for u in d.users:
		var usr: Dictionary = d.users[u]
		out.append("username %s%s secret 9 $9$nhEmQVczB7dqsO$X.HsgL6x1il0RxkOSSvyQYwucySCt7qFm4v7pqCxkKM" % [u, " privilege %d" % usr.privilege if usr.privilege != 1 else ""])
	if d.ssh_version != 0:
		out.append("ip ssh version %d" % d.ssh_version)
	out.append("!")
	if not d.cdp_run:
		out.append_array(["no cdp run", "!"])
	if d.lldp_run:
		out.append_array(["lldp run", "!"])
	if not d.enable_secret.is_empty():
		out.append_array(["enable secret 5 $1$mERr$hx5rVt7rPNoS4wqbXKX7m0", "!"])
	if d.type == "switch":
		out.append("spanning-tree mode " + d.stp_mode)
		var vl := d.stp_priority.keys()
		vl.sort()
		for v in vl:
			out.append("spanning-tree vlan %d priority %d" % [v, d.stp_priority[v]])
		out.append("!")
	for n in d.iface_order:
		out.append_array(_iface_block(d, n))
		out.append("!")
	if not d.ospf.is_empty():
		out.append("router ospf %d" % int(d.ospf.pid))
		if not d.ospf.router_id.is_empty():
			out.append(" router-id " + d.ospf.router_id)
		if int(d.ospf.ref_bw) != 100:
			out.append(" auto-cost reference-bandwidth %d" % int(d.ospf.ref_bw))
		if d.ospf.passive_default:
			out.append(" passive-interface default")
		for n in d.ospf.passive:
			out.append(" %spassive-interface %s" % ["no " if d.ospf.passive_default else "", n])
		for st in d.ospf.networks:
			out.append(" network %s %s area %s" % [st.net, st.wc, st.area])
		if d.ospf.default_originate:
			out.append(" default-information originate")
		out.append("!")
	if not d.default_gateway.is_empty() and d.type == "switch":
		out.append_array(["ip default-gateway " + d.default_gateway, "!"])
	for name in d.nat_pools:
		var p: Dictionary = d.nat_pools[name]
		out.append("ip nat pool %s %s %s netmask %s" % [name, p.start, p.end, p.mask])
	for r in d.nat_rules:
		if r.iface.is_empty():
			out.append("ip nat inside source list %s pool %s%s" % [r.acl, r.pool, " overload" if r.overload else ""])
		else:
			out.append("ip nat inside source list %s interface %s overload" % [r.acl, r.iface])
	for st in d.nat_static:
		out.append("ip nat inside source static %s %s" % [st.local, st.global])
	for r in d.static_routes:
		var via: String = r.next_hop if r.iface.is_empty() else r.iface
		out.append("ip route %s %s %s%s" % [IPv4.to_str(r.net), IPv4.to_str(IPv4.mask(r.len)), via, " %d" % r.ad if r.ad != 1 else ""])
	out.append("!")
	for name in d.acls:
		var acl: Dictionary = d.acls[name]
		if name.is_valid_int():
			for e in acl.entries:
				out.append("access-list %s %s" % [name, ACL.to_str(e)])
		else:
			out.append("ip access-list %s %s" % ["standard" if acl.standard else "extended", name])
			for e in acl.entries:
				out.append(" " + ACL.to_str(e))
	for h in d.logging_hosts:
		out.append("logging host " + h)
	if d.logging_trap != "informational":
		out.append("logging trap " + d.logging_trap)
	for c in d.snmp_communities:
		var sc: Dictionary = d.snmp_communities[c]
		out.append("snmp-server community %s %s%s" % [c, sc.access.to_upper(), " " + sc.acl if not sc.acl.is_empty() else ""])
	if not d.snmp_location.is_empty():
		out.append("snmp-server location " + d.snmp_location)
	if not d.snmp_contact.is_empty():
		out.append("snmp-server contact " + d.snmp_contact)
	out.append("!")
	for key in d.lines:
		var l: Dictionary = d.lines[key]
		out.append("line " + key)
		if not l.password.is_empty():
			out.append(" password " + ("7 0822455D0A16" if d.password_encryption else l.password))
		if not l.login.is_empty():
			out.append(" " + l.login)
		if not l.transport.is_empty():
			out.append(" transport input " + l.transport)
	out.append("!")
	for ntp in d.ntp_servers:
		out.append("ntp server " + ntp)
	out.append("end")
	return "\n".join(out)

static func running_config_iface(d: Device, n: String) -> String:
	var out := PackedStringArray(["Building configuration...", "", "Current configuration:", "!"])
	out.append_array(_iface_block(d, n))
	out.append("end")
	return "\n".join(out)

static func ip_int_brief(d: Device) -> String:
	var out := PackedStringArray(["%-22s %-15s %-3s %-6s %-21s %s" % ["Interface", "IP-Address", "OK?", "Method", "Status", "Protocol"]])
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		var st := d.status(i)
		out.append("%-22s %-15s YES %-6s %-21s %s" % [n, i.ip if not i.ip.is_empty() else "unassigned", "manual" if not i.ip.is_empty() else "unset", st[0], st[1]])
	return "\n".join(out)

static func vlan_brief(d: Device) -> String:
	var out := PackedStringArray([
		"%-4s %-32s %-9s %s" % ["VLAN", "Name", "Status", "Ports"],
		"---- -------------------------------- --------- -------------------------------"])
	var ids := d.vlans.keys()
	ids.sort()
	for v in ids:
		var ports: Array = []
		for n in d.iface_order:
			var i: Dictionary = d.interfaces[n]
			if i.physical and i.mode != "trunk" and i.access_vlan == v:
				ports.append(Device.short_name(n))
		var chunks: Array = []
		for k in range(0, max(ports.size(), 1), 4):
			chunks.append(", ".join(ports.slice(k, k + 4)))
		out.append("%-4d %-32s %-9s %s" % [v, d.vlans[v], "active", chunks[0] if chunks.size() > 0 else ""])
		for c in chunks.slice(1):
			out.append(" ".repeat(48) + c)
	for extra in [[1002, "fddi-default"], [1003, "token-ring-default"], [1004, "fddinet-default"], [1005, "trnet-default"]]:
		out.append("%-4d %-32s %-9s" % [extra[0], extra[1], "act/unsup"])
	return "\n".join(out)

## Up trunks, except bundled members (they're listed through their port-channel).
static func _lists_as_trunk(d: Device, n: String) -> bool:
	var i: Dictionary = d.interfaces[n]
	if i.mode != "trunk" or not d.is_up(i):
		return false
	return not (i.channel_group > 0 and d.interfaces.has("Port-channel%d" % i.channel_group))

static func trunks(d: Device) -> String:
	var t: Array = d.iface_order.filter(func(n): return _lists_as_trunk(d, n))
	if t.is_empty():
		return ""
	var out := PackedStringArray(["%-12s %-16s %-14s %-13s %s" % ["Port", "Mode", "Encapsulation", "Status", "Native vlan"]])
	for n in t:
		out.append("%-12s %-16s %-14s %-13s %d" % [Device.short_name(n), "on", "802.1q", "trunking", d.interfaces[n].native])
	out.append("")
	out.append("%-12s %s" % ["Port", "Vlans allowed on trunk"])
	for n in t:
		var a: String = d.interfaces[n].allowed
		out.append("%-12s %s" % [Device.short_name(n), "1-4094" if a == "all" else a])
	out.append("")
	out.append("%-12s %s" % ["Port", "Vlans allowed and active in management domain"])
	for n in t:
		var active := d.vlans.keys().filter(func(v): return d.trunk_allows(d.interfaces[n], v))
		out.append("%-12s %s" % [Device.short_name(n), vlan_list_str(active)])
	return "\n".join(out)

static func access_lists(d: Device) -> String:
	var out := PackedStringArray()
	for name in d.acls:
		var acl: Dictionary = d.acls[name]
		out.append("%s IP access list %s" % ["Standard" if acl.standard else "Extended", name])
		for k in acl.entries.size():
			out.append("    %d %s" % [(k + 1) * 10, ACL.to_str(acl.entries[k])])
	return "\n".join(out)

static func nat_translations(d: Device) -> String:
	if d.nat_static.is_empty():
		return ""
	return NAT.show(d.nat_static.map(func(s): return NAT.static_row(s.local, s.global)))

static func port_security(d: Device) -> String:
	var out := PackedStringArray([
		"Secure Port  MaxSecureAddr  CurrentAddr  SecurityViolation  Security Action",
		"                (Count)       (Count)          (Count)",
		"---------------------------------------------------------------------------"])
	for n in d.iface_order:
		var ps: Dictionary = d.interfaces[n].ps
		if ps.enabled:
			out.append("%11s %14d %12d %18d %16s" % [Device.short_name(n), ps.maximum, ps.macs.size(), 0, ps.violation.capitalize()])
	out.append("---------------------------------------------------------------------------")
	return "\n".join(out)

static func port_security_iface(d: Device, n: String) -> String:
	var i: Dictionary = d.interfaces[n]
	var ps: Dictionary = i.ps
	var rows := [
		["Port Security", "Enabled" if ps.enabled else "Disabled"],
		["Port Status", ("Secure-up" if d.is_up(i) else "Secure-down") if ps.enabled else "Secure-down"],
		["Violation Mode", ps.violation.capitalize()],
		["Aging Time", "0 mins"], ["Aging Type", "Absolute"], ["SecureStatic Address Aging", "Disabled"],
		["Maximum MAC Addresses", str(ps.maximum)],
		["Total MAC Addresses", str(ps.macs.size())],
		["Configured MAC Addresses", str(ps.macs.size())],
		["Sticky MAC Addresses", "0"],
		["Last Source Address:Vlan", "0000.0000.0000:0"],
		["Security Violation Count", "0"],
	]
	return "\n".join(rows.map(func(r): return "%-27s: %s" % r))
