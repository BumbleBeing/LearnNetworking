class_name OspfGen
extends RefCounted
## OSPF Navigator items: router ID, DR/BDR election, neighbour problems, interface
## cost, shortest path, network statements and the neighbour table.

const KINDS := ["router_id", "dr_bdr", "neighbor", "cost", "spf", "network_stmt", "neighbor_table"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"router_id": return _router_id(rng)
		"dr_bdr": return _dr_bdr(rng)
		"neighbor": return _neighbor(rng)
		"cost": return _cost(rng)
		"spf": return _spf(rng)
		"network_stmt": return _network_stmt(rng)
	return _neighbor_table(rng)

## A private address: 10.x.x.x, 172.16-31.x.x or 192.168.x.x.
static func _ip(rng: RandomNumberGenerator, a: int = 10) -> String:
	match a:
		172: return "172.%d.%d.%d" % [rng.randi_range(16, 31), rng.randi_range(0, 254), rng.randi_range(1, 254)]
		192: return "192.168.%d.%d" % [rng.randi_range(0, 254), rng.randi_range(1, 254)]
	return "10.%d.%d.%d" % [rng.randi_range(0, 254), rng.randi_range(0, 254), rng.randi_range(1, 254)]

## A readable router ID: N.N.N.N or 192.168.x.y.
static func _rid(rng: RandomNumberGenerator) -> String:
	var n := rng.randi_range(1, 9)
	return "%d.%d.%d.%d" % [n, n, n, n] if rng.randf() < 0.6 else "192.168.%d.%d" % [rng.randi_range(1, 20), rng.randi_range(1, 254)]

static func _router_id(rng: RandomNumberGenerator) -> Dictionary:
	var ifaces: Array = [
		{"name": "GigabitEthernet0/0", "ip": _ip(rng, 10), "up": true},
		{"name": "GigabitEthernet0/1", "ip": _ip(rng, 172), "up": true},
		{"name": "GigabitEthernet0/2", "ip": _ip(rng, 192), "up": rng.randf() < 0.5},
	]
	if rng.randf() < 0.6:
		var n := rng.randi_range(1, 9)
		ifaces.append({"name": "Loopback0", "ip": "%d.%d.%d.%d" % [n, n, n, n] if rng.randf() < 0.5 else "10.255.%d.1" % rng.randi_range(0, 254), "up": true})
	var manual := ""
	if rng.randf() < 0.3:
		manual = _rid(rng)
	var res := OSPF.router_id(manual, ifaces)
	var lines := PackedStringArray(["%-22s %-15s %s" % ["Interface", "IP-Address", "Status"]])
	for i in ifaces:
		lines.append("%-22s %-15s %s" % [i.name, i.ip, "up" if i.up else "administratively down"])
	lines.append("")
	lines.append("router ospf 1")
	if not manual.is_empty():
		lines.append(" router-id " + manual)
	lines.append(" network 0.0.0.0 255.255.255.255 area 0")
	return {"kind": "router_id", "card_id": "gen.ospf_navigator.router_id", "exhibit": "\n".join(lines),
		"question": "What is R1's OSPF router ID?", "answer": res.rid, "placeholder": "a.b.c.d",
		"hint": "Order: router-id command, then the highest up loopback, then the highest up physical interface. Down interfaces don't count.",
		"explain": "%s: %s." % [res.rid, res.reason]}

static func _dr_bdr(rng: RandomNumberGenerator) -> Dictionary:
	var routers: Array = []
	var seen := {}
	for i in 4:
		var rid := _rid(rng)
		while seen.has(rid):
			rid = _rid(rng)
		seen[rid] = true
		routers.append({"name": "R%d" % (i + 1), "rid": rid, "priority": [1, 1, 1, 0, 10, 255][rng.randi() % 6]})
	if routers.all(func(r): return r.priority == 0):
		routers[0].priority = 1
	var res := OSPF.elect(routers)
	var want_dr: bool = rng.randf() < 0.6 or res.bdr.is_empty()
	var lines := PackedStringArray(["Router  OSPF priority  Router ID", "------  -------------  ---------"])
	for r in routers:
		lines.append("%-7s %-14d %s" % [r.name, r.priority, r.rid])
	var choices: Array = routers.map(func(r): return r.name)
	var ans: String = res.dr if want_dr else res.bdr
	var order := routers.filter(func(r): return r.priority > 0)
	order.sort_custom(func(a, b): return a.priority > b.priority or (a.priority == b.priority and OSPF.rid_less(b.rid, a.rid)))
	return {"kind": "dr_bdr", "card_id": "gen.ospf_navigator.dr_bdr",
		"exhibit": "Four routers share one Ethernet segment and start OSPF at the same time.\n\n" + "\n".join(lines),
		"question": "Which router becomes the %s?" % ("DR" if want_dr else "BDR"), "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Highest priority wins, then highest router ID. Priority 0 means the router never becomes DR or BDR.",
		"explain": "Ranking (priority, then RID): %s. DR = %s, BDR = %s.%s" % [
			" > ".join(order.map(func(r): return "%s (%d, %s)" % [r.name, r.priority, r.rid])), res.dr, res.bdr,
			"\nPriority 0 routers are excluded." if routers.any(func(r): return r.priority == 0) else ""]}

static func _ospf_if(name: String, side: Dictionary) -> String:
	var lines := PackedStringArray([
		"%s is up, line protocol is up" % name,
		"  Internet Address %s/%d, Area %s" % [side.ip, IPv4.prefix_from_mask(IPv4.parse(side.mask)), side.area],
		"  Process ID %d, Router ID %s, Network Type BROADCAST, Cost: %d" % [side.pid, side.rid, side.cost],
		"  Transmit Delay is 1 sec, State %s, Priority %d" % ["DR" if side.priority > 0 else "DROTHER", side.priority],
		"  Timer intervals configured, Hello %d, Dead %d, Wait %d" % [side.hello, side.dead, side.dead],
	])
	if side.passive:
		lines.append("    No Hellos (Passive interface)")
	if side.mtu != 1500:
		lines.append("  IP MTU %d" % side.mtu)
	return "\n".join(lines)

static func _neighbor(rng: RandomNumberGenerator) -> Dictionary:
	var net := "10.%d.%d.0" % [rng.randi_range(0, 99), rng.randi_range(0, 250)]
	var base := IPv4.parse(net)
	var a := {"rid": "1.1.1.1", "ip": IPv4.to_str(base + 1), "mask": "255.255.255.252", "area": 0, "hello": 10, "dead": 40,
		"passive": false, "mtu": 1500, "pid": 1, "cost": 1, "priority": 1}
	var b := a.duplicate()
	b.rid = "2.2.2.2"
	b.ip = IPv4.to_str(base + 2)
	# Harmless differences that make good distractors.
	if rng.randf() < 0.6:
		b.pid = rng.randi_range(2, 100)
	if rng.randf() < 0.5:
		b.cost = [10, 64, 100][rng.randi() % 3]
	if rng.randf() < 0.4:
		b.priority = [0, 5, 100][rng.randi() % 3]
	var issue: String = ["area", "timers", "subnet", "rid", "passive", "mtu"][rng.randi() % 6]
	match issue:
		"area": b.area = [1, 2, 10][rng.randi() % 3]
		"timers":
			b.hello = 5
			b.dead = 20
		"subnet": b.ip = IPv4.to_str(base + 6)
		"rid": b.rid = a.rid
		"passive": b.passive = true
		"mtu": b.mtu = 1400
	var found := OSPF.neighbor_issues(a, b)
	var pool: Array = ["area", "timers", "subnet", "rid", "passive", "mtu"].filter(func(x): return x != issue)
	var harmless: Array = []
	if b.pid != a.pid:
		harmless.append("pid")
	if b.cost != a.cost:
		harmless.append("cost")
	if b.priority != a.priority:
		harmless.append("priority")
	GenUtil.shuffle(rng, pool)
	var wrong: Array = harmless + pool
	var choices: Array = [OSPF.ISSUE_TEXT[issue]] + wrong.slice(0, 3).map(func(k): return OSPF.ISSUE_TEXT[k])
	GenUtil.shuffle(rng, choices)
	var note := ""
	if harmless.size() > 0:
		note = "\nThe %s differ, but that never stops an adjacency: those values are local to each router." % " and ".join(harmless.map(func(k): return {"pid": "process IDs", "cost": "costs", "priority": "priorities"}[k]))
	return {"kind": "neighbor", "card_id": "gen.ospf_navigator.neighbor",
		"exhibit": "R1#show ip ospf interface g0/0\n%s\n\nR2#show ip ospf interface g0/0\n%s" % [_ospf_if("GigabitEthernet0/0", a), _ospf_if("GigabitEthernet0/0", b)],
		"question": "R1 and R2 don't become OSPF neighbours. Why?", "choices": choices,
		"answer_index": choices.find(OSPF.ISSUE_TEXT[issue]), "answer": OSPF.ISSUE_TEXT[issue],
		"hint": "Must match: subnet/mask, area, Hello/Dead timers, MTU (and authentication). Must differ: router IDs. Must not be passive.",
		"explain": "%s.%s" % [OSPF.ISSUE_TEXT[found[0]], note]}

static func _cost(rng: RandomNumberGenerator) -> Dictionary:
	var opts := [
		["FastEthernet0/0", 100.0, "100 Mbps"], ["GigabitEthernet0/0", 1000.0, "1 Gbps"],
		["Ethernet0/0", 10.0, "10 Mbps"], ["Serial0/0/0", 1.544, "1544 kbps"], ["TenGigabitEthernet0/0", 10000.0, "10 Gbps"],
	]
	var o: Array = opts[rng.randi() % opts.size()]
	var ref: int = [100, 100, 1000, 10000][rng.randi() % 4]
	var c := OSPF.cost(o[1], ref)
	var cfg := "router ospf 1\n auto-cost reference-bandwidth %d" % ref if ref != 100 else "router ospf 1\n (reference bandwidth left at the default)"
	return {"kind": "cost", "card_id": "gen.ospf_navigator.cost",
		"exhibit": "%s  bandwidth %s\n\n%s" % [o[0], o[2], cfg],
		"question": "What OSPF cost does %s get?" % o[0], "answer": str(c), "placeholder": "number",
		"hint": "Cost = reference bandwidth ÷ interface bandwidth (default reference 100 Mbps), rounded down, minimum 1.",
		"explain": "%d Mbps ÷ %s = %s → cost %d.%s" % [ref, o[2], str(snapped(ref / o[1], 0.01)), c,
			"\nWith the default reference, every link of 100 Mbps or faster costs 1. That's why 'auto-cost reference-bandwidth' is raised on modern networks." if ref == 100 and o[1] >= 100 else ""]}

## Square R1-R2-R4-R3 with an optional R2-R3 diagonal. Destination: R4's LAN (cost 1).
static func _spf(rng: RandomNumberGenerator) -> Dictionary:
	var costs := [1, 2, 5, 10, 10, 20, 64]
	var c := func(): return costs[rng.randi() % costs.size()]
	var links: Array = [["R1", "R2", c.call()], ["R1", "R3", c.call()], ["R2", "R4", c.call()], ["R3", "R4", c.call()]]
	var diag := rng.randf() < 0.4
	if diag:
		links.append(["R2", "R3", c.call()])
	var edges: Array = []
	for l in links:
		edges.append({"from": l[0], "to": l[1], "cost": l[2]})
		edges.append({"from": l[1], "to": l[0], "cost": l[2]})
	var res := OSPF.spf(["R1", "R2", "R3", "R4"], edges, "R1")
	var total: int = res.dist["R4"] + 1
	var lan := "10.4.%d.0/24" % rng.randi_range(0, 250)
	var diagram := PackedStringArray([
		"R1 ─%s─ R2" % _c(links[0][2]),
		"│" + " ".repeat(13) + "│",
		str(links[1][2]).rpad(5) + ("╱ %d" % links[4][2] if diag else "").rpad(9) + str(links[2][2]),
		"│" + " ".repeat(13) + "│",
		"R3 ─%s─ R4 ── LAN %s (cost 1)" % [_c(links[3][2]), lan]])
	var paths := _paths(links, diag)
	var explain := "\n".join(paths.map(func(p): return "  %s: %s = %d" % [" → ".join(p[0]), " + ".join(p[1].map(func(x): return str(x))), p[2]]))
	var exhibit := "\n".join(diagram) + "\n\nLink costs are the same in both directions."
	var first: Array = res.first["R4"]
	first.sort()
	if rng.randf() < 0.5:
		return {"kind": "spf", "card_id": "gen.ospf_navigator.spf", "exhibit": exhibit,
			"question": "What is R1's total OSPF cost to %s?" % lan, "answer": str(total), "placeholder": "number",
			"hint": "Add the outgoing interface costs along each path (including R4's LAN interface) and take the lowest.",
			"explain": "Paths from R1 to R4 (then + 1 for the LAN):\n%s\nBest: %d + 1 = %d." % [explain, res.dist["R4"], total]}
	var choices: Array = ["R2", "R3", "Both R2 and R3 (equal-cost load balancing)"]
	var ans: String = choices[2] if first.size() > 1 else first[0]
	return {"kind": "spf", "card_id": "gen.ospf_navigator.spf", "exhibit": exhibit,
		"question": "Which next hop does R1 use for %s?" % lan, "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Total each path's cost; the lowest wins. Equal costs are all installed (up to 4 by default).",
		"explain": "Paths from R1 to R4:\n%s\nLowest total: %d via %s." % [explain, res.dist["R4"], " and ".join(first)]}

static func _c(n: int) -> String:
	return StpGen._dash(" %d " % n, 8)

static func _paths(links: Array, diag: bool) -> Array:
	var w := {}
	for l in links:
		w[l[0] + l[1]] = l[2]
		w[l[1] + l[0]] = l[2]
	var cands: Array = [["R1", "R2", "R4"], ["R1", "R3", "R4"]]
	if diag:
		cands.append_array([["R1", "R2", "R3", "R4"], ["R1", "R3", "R2", "R4"]])
	var out: Array = []
	for p in cands:
		var parts: Array = []
		for i in p.size() - 1:
			parts.append(w[p[i] + p[i + 1]])
		out.append([p, parts, parts.reduce(func(a, x): return a + x, 0)])
	return out

static func _network_stmt(rng: RandomNumberGenerator) -> Dictionary:
	var x := rng.randi_range(1, 200)
	var ifaces: Array = [
		["Gi0/0", "10.%d.1.1" % x], ["Gi0/1", "10.%d.2.1" % x], ["Gi0/2", "10.%d.130.1" % x], ["Lo0", "172.16.%d.1" % x],
	]
	var stmts := [
		["10.%d.0.0" % x, "0.0.255.255"], ["10.%d.0.0" % x, "0.0.3.255"], ["10.%d.2.0" % x, "0.0.0.255"],
		["10.%d.128.0" % x, "0.0.127.255"], ["0.0.0.0", "255.255.255.255"], ["10.%d.1.1" % x, "0.0.0.0"],
		["10.0.0.0", "0.255.255.255"],
	]
	var s: Array = stmts[rng.randi() % stmts.size()]
	var hit: Array = ifaces.filter(func(i): return OSPF.network_matches(s[0], s[1], i[1])).map(func(i): return i[0])
	var as_text := func(arr: Array) -> String: return ", ".join(arr) if arr.size() > 0 else "None of them"
	var right: String = as_text.call(hit)
	var opts := {right: true}
	var all_names: Array = ifaces.map(func(i): return i[0])
	var cands: Array = [all_names, all_names.slice(0, 3), [all_names[0]], [all_names[1]], all_names.slice(0, 2), [all_names[2], all_names[3]], []]
	GenUtil.shuffle(rng, cands)
	for cnd in cands:
		if opts.size() >= 4:
			break
		opts[as_text.call(cnd)] = true
	var choices: Array = opts.keys()
	GenUtil.shuffle(rng, choices)
	var lines := PackedStringArray()
	for i in ifaces:
		lines.append("%-6s %s" % [i[0], i[1]])
	var range_ := ACL.wc_range(IPv4.parse(s[0]), IPv4.parse(s[1]))
	return {"kind": "network_stmt", "card_id": "gen.ospf_navigator.network_stmt",
		"exhibit": "\n".join(lines) + "\n\nrouter ospf 1\n network %s %s area 0" % [s[0], s[1]],
		"question": "Which interfaces does this network statement put into area 0?", "choices": choices,
		"answer_index": choices.find(right), "answer": right,
		"hint": "It's a wildcard match on the interface IP, like an ACL: 0 bits must match, 1 bits are ignored.",
		"explain": "%s %s matches %s to %s.\nMatched: %s." % [s[0], s[1], IPv4.to_str(range_[0]), IPv4.to_str(range_[1]), right]}

static func _neighbor_table(rng: RandomNumberGenerator) -> Dictionary:
	var me_role: String = ["DROTHER", "BDR"][rng.randi() % 2]
	var roles: Array = ["DR", "DROTHER", "DROTHER"] if me_role == "BDR" else ["DR", "BDR", "DROTHER"]
	GenUtil.shuffle(rng, roles)
	var rows: Array = []
	var seen := {}
	for i in 3:
		var rid := _rid(rng)
		while seen.has(rid):
			rid = _rid(rng)
		seen[rid] = true
		var full: bool = me_role != "DROTHER" or roles[i] != "DROTHER"
		rows.append({"rid": rid, "pri": 1, "state": "FULL" if full else "2WAY", "role": roles[i],
			"address": "10.0.0.%d" % (i + 2), "iface": "GigabitEthernet0/0"})
	var exhibit := "R1 (%s)#show ip ospf neighbor\n\n%s" % [me_role, OSPF.show_neighbors(rows)]
	var dr: Dictionary = rows.filter(func(r): return r.role == "DR")[0]
	var two_way := rows.filter(func(r): return r.state == "2WAY")
	if two_way.size() > 0 and rng.randf() < 0.6:
		var choices: Array = [
			"Nothing: DROTHERs stay in 2WAY with each other and go FULL only with the DR and BDR",
			"The area IDs don't match", "The Hello timers don't match", "The MTUs don't match",
		]
		return {"kind": "neighbor_table", "card_id": "gen.ospf_navigator.neighbor_table", "exhibit": exhibit,
			"question": "R1 is 2WAY/DROTHER with %s. What's wrong?" % two_way[0].rid, "choices": choices,
			"answer_index": 0, "answer": choices[0],
			"hint": "On a multi-access segment, which neighbours does a DROTHER fully exchange its database with?",
			"explain": "2WAY between two DROTHERs is normal and stable. Mismatched area or timers would stop the neighbour appearing at all; an MTU mismatch shows EXSTART/EXCHANGE."}
	return {"kind": "neighbor_table", "card_id": "gen.ospf_navigator.neighbor_table", "exhibit": exhibit,
		"question": "What is the router ID of the DR on this segment?", "answer": dr.rid, "placeholder": "a.b.c.d",
		"hint": "The State column reads state/role of each neighbour.",
		"explain": "%s shows FULL/DR. The column after the slash is the neighbour's role on the segment." % dr.rid}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
