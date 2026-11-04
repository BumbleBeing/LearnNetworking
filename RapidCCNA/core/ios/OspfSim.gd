class_name OspfSim
extends RefCounted
## OSPF across a lab Network: enabled interfaces, router IDs, adjacencies (with the real
## neighbour requirements), DR/BDR, SPF and the resulting O routes.

## OSPF-enabled interfaces of a device: {iface: {area, passive, cost, ip, mask}}.
static func enabled(d: Device) -> Dictionary:
	var out := {}
	if d.ospf.is_empty():
		return out
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		if i.ip.is_empty() or not d.is_up(i):
			continue
		var area := ""
		if not i.ospf_area.is_empty():
			area = i.ospf_area
		else:
			for st in d.ospf.networks:
				if OSPF.network_matches(st.net, st.wc, i.ip):
					area = str(st.area)
					break
		if area.is_empty():
			continue
		var passive: bool = (n in d.ospf.passive) != d.ospf.passive_default
		out[n] = {"area": area, "passive": passive, "cost": cost(d, n), "ip": i.ip, "mask": i.mask}
	return out

static func cost(d: Device, n: String) -> int:
	var i: Dictionary = d.interfaces[n]
	if i.ospf_cost > 0:
		return i.ospf_cost
	return OSPF.cost(d.bandwidth(n), int(d.ospf.get("ref_bw", OSPF.DEFAULT_REF_MBPS)))

static func router_id(d: Device) -> String:
	var ifs: Array = []
	for n in d.iface_order:
		var i: Dictionary = d.interfaces[n]
		ifs.append({"name": n, "ip": i.ip, "up": d.is_up(i)})
	return OSPF.router_id(d.ospf.get("router_id", ""), ifs).rid

## Every adjacency attempt on the network: [{a, ai, b, bi, ok, issues, dr, bdr}].
static func adjacencies(net: Network) -> Array:
	var out: Array = []
	var en := {}
	var rid := {}
	for name in net.devices:
		var d: Device = net.devices[name]
		en[name] = enabled(d)
		if not d.ospf.is_empty():
			rid[name] = router_id(d)
	for l in net.links:
		if not en.has(l[0]) or not en.has(l[2]) or not en[l[0]].has(l[1]) or not en[l[2]].has(l[3]):
			continue
		var da: Device = net.devices[l[0]]
		var db: Device = net.devices[l[2]]
		var side := func(d: Device, n: String, nm: String) -> Dictionary:
			var i: Dictionary = d.interfaces[n]
			var e: Dictionary = en[nm][n]
			return {"rid": rid[nm], "ip": i.ip, "mask": i.mask, "area": e.area, "hello": i.ospf_hello, "dead": i.ospf_dead,
				"passive": e.passive, "mtu": 1500, "priority": i.ospf_priority, "name": nm}
		var a: Dictionary = side.call(da, l[1], l[0])
		var b: Dictionary = side.call(db, l[3], l[2])
		var issues := OSPF.neighbor_issues(a, b)
		var el := OSPF.elect([a, b])
		out.append({"a": l[0], "ai": l[1], "b": l[2], "bi": l[3], "ok": issues.is_empty(), "issues": issues,
			"dr": el.dr, "bdr": el.bdr, "a_side": a, "b_side": b})
	return out

## Full neighbours of a device: [{rid, pri, state, role, address, iface}].
static func neighbors(net: Network, dev: String) -> Array:
	var out: Array = []
	for adj in adjacencies(net):
		if not adj.ok:
			continue
		var me_a: bool = adj.a == dev
		if not me_a and adj.b != dev:
			continue
		var peer: Dictionary = adj.b_side if me_a else adj.a_side
		var role := "DR" if adj.dr == peer.name else "BDR" if adj.bdr == peer.name else "DROTHER"
		out.append({"rid": peer.rid, "pri": peer.priority, "state": "FULL", "role": role, "address": peer.ip,
			"iface": adj.ai if me_a else adj.bi, "name": peer.name})
	return out

## O routes for a device (connected networks excluded).
static func routes(net: Network, dev: String) -> Array:
	var adj := adjacencies(net).filter(func(a): return a.ok)
	var nodes: Array = []
	for name in net.devices:
		if not net.devices[name].ospf.is_empty():
			nodes.append(name)
	if not dev in nodes:
		return []
	var edges: Array = []
	for a in adj:
		edges.append({"from": a.a, "to": a.b, "cost": cost(net.devices[a.a], a.ai), "via_ip": a.b_side.ip, "out": a.ai})
		edges.append({"from": a.b, "to": a.a, "cost": cost(net.devices[a.b], a.bi), "via_ip": a.a_side.ip, "out": a.bi})
	var res := OSPF.spf(nodes, edges, dev)
	var me: Device = net.devices[dev]
	var mine := {}
	for n in enabled(me):
		var i: Dictionary = me.interfaces[n]
		mine["%d/%d" % [IPv4.network(IPv4.parse(i.ip), IPv4.prefix_from_mask(IPv4.parse(i.mask))), IPv4.prefix_from_mask(IPv4.parse(i.mask))]] = true
	var best := {}   # "net/len" -> {metric, owner}
	for name in nodes:
		if name == dev or res.dist[name] >= 1 << 30:
			continue
		var d: Device = net.devices[name]
		var en := enabled(d)
		for n in en:
			var i: Dictionary = d.interfaces[n]
			# Loopbacks are advertised as host routes.
			var plen: int = 32 if n.begins_with("Loopback") else IPv4.prefix_from_mask(IPv4.parse(i.mask))
			var netw := IPv4.network(IPv4.parse(i.ip), plen)
			var key := "%d/%d" % [netw, plen]
			if mine.has(key):
				continue
			var metric: int = res.dist[name] + int(en[n].cost)
			if not best.has(key) or metric < best[key].metric:
				best[key] = {"metric": metric, "owner": name, "net": netw, "len": plen}
		if d.ospf.get("default_originate", false):
			var has_default := d.routing_table(false).routes.any(func(r): return r.len == 0)
			if has_default and not best.has("0/0"):
				best["0/0"] = {"metric": 1, "owner": name, "net": 0, "len": 0, "ext": "E2"}
	var out: Array = []
	for key in best:
		var b: Dictionary = best[key]
		var first: Array = res.first[b.owner]
		first.sort()
		var hop: String = first[0]
		var e: Array = edges.filter(func(x): return x.from == dev and x.to == hop)
		e.sort_custom(func(x, y): return x.cost < y.cost)
		var r := RoutingTable.route("O", IPv4.to_str(b.net), b.len, e[0].via_ip, e[0].out, b.metric)
		if b.has("ext"):
			r.ext = b.ext
		out.append(r)
	return out

static func show_neighbors(net: Network, dev: String) -> String:
	return OSPF.show_neighbors(neighbors(net, dev))

static func show_iface_brief(net: Network, dev: String) -> String:
	var d: Device = net.devices[dev]
	var en := enabled(d)
	var nbrs := neighbors(net, dev)
	var out := PackedStringArray(["%-10s %-5s %-15s %-18s %-5s %-6s %s" % ["Interface", "PID", "Area", "IP Address/Mask", "Cost", "State", "Nbrs F/C"]])
	for n in en:
		var e: Dictionary = en[n]
		var cnt := nbrs.filter(func(x): return x.iface == n).size()
		var state := "LOOP" if n.begins_with("Loopback") else "DR"   # alone on a segment = DR
		for adj in adjacencies(net):
			if adj.ok and ((adj.a == dev and adj.ai == n) or (adj.b == dev and adj.bi == n)):
				state = "DR" if adj.dr == dev else "BDR" if adj.bdr == dev else "DROTH"
		out.append("%-10s %-5d %-15s %-18s %-5d %-6s %d/%d" % [Device.short_name(n), int(d.ospf.pid), e.area,
			"%s/%d" % [e.ip, IPv4.prefix_from_mask(IPv4.parse(e.mask))], e.cost, state, cnt, cnt])
	return "\n".join(out)

static func show_protocols(net: Network, dev: String) -> String:
	var d: Device = net.devices[dev]
	if d.ospf.is_empty():
		return ""
	var out := PackedStringArray(['Routing Protocol is "ospf %d"' % int(d.ospf.pid),
		"  Outgoing update filter list for all interfaces is not set",
		"  Router ID %s" % router_id(d),
		"  Number of areas in this router is 1. 1 normal 0 stub 0 nssa",
		"  Maximum path: 4",
		"  Routing for Networks:"])
	for st in d.ospf.networks:
		out.append("    %s %s area %s" % [st.net, st.wc, st.area])
	var passive: Array = d.iface_order.filter(func(n): return (n in d.ospf.passive) != d.ospf.passive_default and not d.interfaces[n].ip.is_empty())
	if passive.size() > 0:
		out.append("  Passive Interface(s):")
		for n in passive:
			out.append("    " + n)
	out.append("  Routing Information Sources:")
	out.append("    Gateway         Distance      Last Update")
	for nb in neighbors(net, dev):
		out.append("    %-15s %-13d 00:01:12" % [nb.rid, 110])
	out.append("  Distance: (default is 110)")
	out.append("  Reference bandwidth unit is %d mbps" % int(d.ospf.get("ref_bw", 100)))
	return "\n".join(out)

static func show_iface(net: Network, dev: String, n: String) -> String:
	var d: Device = net.devices[dev]
	var en := enabled(d)
	if not en.has(n):
		return "%%OSPF: OSPF not enabled on %s" % n
	var i: Dictionary = d.interfaces[n]
	var state := "LOOPBACK" if n.begins_with("Loopback") else "DR"
	var nb := 0
	for adj in adjacencies(net):
		if adj.ok and ((adj.a == dev and adj.ai == n) or (adj.b == dev and adj.bi == n)):
			nb += 1
			state = "DR" if adj.dr == dev else "BDR" if adj.bdr == dev else "DROTHER"
	return OSPF.show_interface(n, {"ip": i.ip, "mask": i.mask, "area": en[n].area, "pid": d.ospf.pid, "rid": router_id(d),
		"cost": en[n].cost, "priority": i.ospf_priority, "hello": i.ospf_hello, "dead": i.ospf_dead,
		"passive": en[n].passive, "state": state, "nbrs": nb})
