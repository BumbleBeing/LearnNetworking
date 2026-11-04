class_name HsrpSim
extends RefCounted
## HSRP across a lab Network. Elections are stateful (Network.hsrp_state remembers the
## active router per group), so preempt and interface tracking behave as on real routers:
## a better router takes over from a working active router only if it has preempt.

const DEFAULT_PRIORITY := 100

static func vmac(group: int, version: int) -> String:
	if version == 2:
		return "0000.0c9f.f%03x" % group
	return "0000.0c07.ac%02x" % group

## Priority after tracked-interface decrements.
static func effective_priority(d: Device, cfg: Dictionary) -> int:
	var p: int = cfg.priority
	for t in cfg.track:
		var ti: Dictionary = d.interfaces.get(t[0], {})
		if ti.is_empty() or not d.is_up(ti):
			p -= int(t[1])
	return p

## Every HSRP group on the network: key "group|subnet" -> [{dev, iface, ip, cfg, priority, up}].
static func groups(net: Network) -> Dictionary:
	var out := {}
	for name in net.devices:
		var d: Device = net.devices[name]
		for n in d.iface_order:
			var i: Dictionary = d.interfaces[n]
			if i.hsrp.is_empty() or i.ip.is_empty():
				continue
			var plen := IPv4.prefix_from_mask(IPv4.parse(i.mask))
			for g in i.hsrp:
				var key := "%d|%s/%d" % [int(g), IPv4.to_str(IPv4.network(IPv4.parse(i.ip), plen)), plen]
				if not out.has(key):
					out[key] = []
				var cfg: Dictionary = i.hsrp[g]
				out[key].append({"dev": name, "iface": n, "ip": i.ip, "cfg": cfg, "group": int(g),
					"priority": effective_priority(d, cfg), "up": d.is_up(i), "version": i.hsrp_version})
	return out

static func _better(a: Dictionary, b: Dictionary) -> bool:
	return a.priority > b.priority or (a.priority == b.priority and IPv4.parse(a.ip) > IPv4.parse(b.ip))

## {active, standby, vip, members} for one group key, updating the remembered active router.
static func state(net: Network, key: String) -> Dictionary:
	var members: Array = groups(net).get(key, [])
	var live: Array = members.filter(func(m): return m.up)
	var vip := ""
	for m in members:
		if not m.cfg.ip.is_empty():
			vip = m.cfg.ip
			break
	var out := {"active": "", "standby": "", "vip": vip, "members": members}
	if live.is_empty() or vip.is_empty():
		net.hsrp_state.erase(key)
		return out
	var best: Dictionary = live[0]
	for m in live:
		if _better(m, best):
			best = m
	var cur: Dictionary = {}
	for m in live:
		if m.dev == net.hsrp_state.get(key, ""):
			cur = m
	if cur.is_empty() or (best.dev != cur.dev and best.cfg.preempt and _better(best, cur)):
		cur = best
	net.hsrp_state[key] = cur.dev
	out.active = cur.dev
	var others: Array = live.filter(func(m): return m.dev != cur.dev)
	if others.size() > 0:
		var sb: Dictionary = others[0]
		for m in others:
			if _better(m, sb):
				sb = m
		out.standby = sb.dev
	return out

## Advances every group's election. Called after each CLI command, so elections follow the
## order things happen in (as on real routers), not the order anyone looks at them.
static func settle(net: Network) -> void:
	for key in groups(net):
		state(net, key)
	for key in net.hsrp_state.keys():
		if not groups(net).has(key):
			net.hsrp_state.erase(key)

## Is this device the active router for a virtual IP (so it answers for it)?
static func owns_vip(net: Network, dev: String, ip: String) -> bool:
	for key in groups(net):
		var st := state(net, key)
		if st.vip == ip and st.active == dev:
			return true
	return false

static func _member(net: Network, dev: String, iface: String, group: int) -> Dictionary:
	for key in groups(net):
		for m in groups(net)[key]:
			if m.dev == dev and m.iface == iface and m.group == group:
				var st := state(net, key)
				var r: Dictionary = m.duplicate()
				r.state = "Active" if st.active == dev else "Standby" if st.standby == dev else ("Listen" if m.up else "Init")
				r.st = st
				r.key = key
				return r
	return {}

## {state, vip, active, standby} for one interface/group ("" state if not configured).
static func status(net: Network, dev: String, iface: String, group: int) -> Dictionary:
	return _member(net, dev, iface, group)

static func _who(net: Network, key: String, who: String, dev: String) -> String:
	if who.is_empty():
		return "unknown"
	if who == dev:
		return "local"
	for m in groups(net)[key]:
		if m.dev == who:
			return m.ip
	return "unknown"

static func show_brief(net: Network, dev: String) -> String:
	var d: Device = net.devices[dev]
	var out := PackedStringArray(["                     P indicates configured to preempt.", "                     |",
		"Interface   Grp  Pri P State   Active          Standby         Virtual IP"])
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		for g in i.hsrp:
			var m := _member(net, dev, n, int(g))
			if m.is_empty():
				continue
			out.append("%-11s %-4d %-3d %s %-7s %-15s %-15s %s" % [Device.short_name(n), int(g), m.priority, "P" if m.cfg.preempt else " ",
				m.state, _who(net, m.key, m.st.active, dev), _who(net, m.key, m.st.standby, dev), m.st.vip if not m.st.vip.is_empty() else "unknown"])
	return "\n".join(out)

static func show_detail(net: Network, dev: String) -> String:
	var d: Device = net.devices[dev]
	var blocks := PackedStringArray()
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		for g in i.hsrp:
			var m := _member(net, dev, n, int(g))
			if m.is_empty():
				continue
			var b := PackedStringArray(["%s - Group %d%s" % [n, int(g), " (version 2)" if i.hsrp_version == 2 else ""],
				"  State is " + m.state,
				"  Virtual IP address is " + (m.st.vip if not m.st.vip.is_empty() else "unknown"),
				"  Active virtual MAC address is " + vmac(int(g), i.hsrp_version),
				"  Hello time 3 sec, hold time 10 sec",
				"  Preemption " + ("enabled" if m.cfg.preempt else "disabled"),
				"  Active router is " + _who(net, m.key, m.st.active, dev),
				"  Standby router is " + _who(net, m.key, m.st.standby, dev),
				"  Priority %d (configured %d)" % [m.priority, int(m.cfg.priority)]])
			for t in m.cfg.track:
				var ti: Dictionary = d.interfaces.get(t[0], {})
				b.append("    Track interface %s state %s decrement %d" % [t[0], "Up" if not ti.is_empty() and d.is_up(ti) else "Down", int(t[1])])
			blocks.append("\n".join(b))
	return "\n".join(blocks)
