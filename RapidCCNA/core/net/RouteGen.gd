class_name RouteGen
extends RefCounted
## Route Picker items. Shape shared by all GenDrill generators:
## {kind, card_id, exhibit?, prompt?, question, choices?, answer_index?, answer, placeholder?, hint, explain}

const KINDS := ["next_hop", "next_hop", "ad_select"]
const DROP := "None. The packet is dropped"

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	return _ad_select(rng) if kind == "ad_select" else _next_hop(rng)

static func _rand_in(rng: RandomNumberGenerator, net: int, length: int) -> int:
	var size := 1 << (32 - length)
	return net + rng.randi_range(1, size - 2)

static func _next_hop(rng: RandomNumberGenerator) -> Dictionary:
	var rt := RoutingTable.new()
	var hops := ["10.0.0.2", "10.0.0.6", "10.0.0.10"]
	rt.add(RoutingTable.route("C", "10.0.0.0", 30, "", "GigabitEthernet0/0"))
	rt.add(RoutingTable.route("C", "10.0.0.4", 30, "", "GigabitEthernet0/1"))
	rt.add(RoutingTable.route("C", "10.0.0.8", 30, "", "GigabitEthernet0/2"))
	var lan := IPv4.parse("192.168.%d.0" % rng.randi_range(1, 99))
	rt.add(RoutingTable.route("C", IPv4.to_str(lan), 24, "", "GigabitEthernet0/3"))
	# Nested prefixes: /16 contains /24 contains /26-/28.
	var n16 := IPv4.parse("172.%d.0.0" % rng.randi_range(16, 31))
	var n24 := n16 | (rng.randi_range(0, 255) << 8)
	var deep_len := rng.randi_range(26, 28)
	var n_deep := n24 | (rng.randi_range(0, (1 << (deep_len - 24)) - 1) << (32 - deep_len))
	var codes := ["O", "D", "S", "R"]
	GenUtil.shuffle(rng, codes)
	GenUtil.shuffle(rng, hops)
	rt.add(RoutingTable.route(codes[0], IPv4.to_str(n16), 16, hops[0], "", _metric(codes[0], rng)))
	rt.add(RoutingTable.route(codes[1], IPv4.to_str(n24), 24, hops[1], "", _metric(codes[1], rng)))
	rt.add(RoutingTable.route(codes[2], IPv4.to_str(n_deep), deep_len, hops[2], "", _metric(codes[2], rng)))
	var has_default := rng.randf() < 0.6
	if has_default:
		rt.add(RoutingTable.route("S", "0.0.0.0", 0, hops[rng.randi() % 3]))
	# Destination: pick which route should win.
	var dest := 0
	match rng.randi() % 5:
		0, 1: dest = _rand_in(rng, n_deep, deep_len)
		2:
			dest = _rand_in(rng, n24, 24)
			while IPv4.network(dest, deep_len) == n_deep:
				dest = _rand_in(rng, n24, 24)
		3:
			dest = _rand_in(rng, n16, 16)
			while IPv4.network(dest, 24) == n24:
				dest = _rand_in(rng, n16, 16)
		_:
			dest = IPv4.parse("%d.%d.%d.%d" % [rng.randi_range(11, 99), rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(1, 254)])
	var best := rt.lookup(dest)
	var choices: Array = []
	var options := rt.routes.filter(func(r): return r.code != "L" and r.code != "C" or r.net == lan)
	for r in options:
		choices.append(RoutingTable.prefix_str(r))
	choices.append(DROP)
	var answer_index := choices.size() - 1 if best.is_empty() else choices.find(RoutingTable.prefix_str(best))
	var matched := rt.matches(dest).map(func(r): return RoutingTable.prefix_str(r))
	var explain := "Routes containing %s: %s.\n" % [IPv4.to_str(dest), ", ".join(matched) if matched.size() > 0 else "none"]
	if best.is_empty():
		explain += "No route matches and there is no default route, so the packet is dropped."
	else:
		explain += "The longest prefix wins: %s." % RoutingTable.describe(best)
		if best.len == 0:
			explain += "\nOnly the default route matches."
	return {"kind": "next_hop", "card_id": "gen.route_picker.next_hop", "exhibit": rt.show(),
		"prompt": "Destination " + IPv4.to_str(dest),
		"question": "Which route does R1 use to forward the packet?",
		"choices": choices, "answer_index": answer_index, "answer": choices[answer_index],
		"hint": "List every route whose prefix contains the destination, then pick the longest prefix (biggest /n).",
		"explain": explain}

static func _metric(code: String, rng: RandomNumberGenerator) -> int:
	match code:
		"O": return rng.randi_range(2, 60)
		"D": return rng.randi_range(2816, 40000)
		"R": return rng.randi_range(1, 6)
	return 0

const SOURCES := [
	{"name": "OSPF", "ad": 110, "desc": "OSPF, cost %d"},
	{"name": "EIGRP", "ad": 90, "desc": "EIGRP, metric %d"},
	{"name": "RIP", "ad": 120, "desc": "RIPv2, %d hops"},
	{"name": "Static route", "ad": 1, "desc": "static route"},
	{"name": "Floating static route (AD 130)", "ad": 130, "desc": "static route with AD 130"},
	{"name": "eBGP", "ad": 20, "desc": "eBGP"},
]

static func _ad_select(rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = SOURCES.duplicate()
	GenUtil.shuffle(rng, pool)
	var picked: Array = pool.slice(0, rng.randi_range(3, 4))
	# Keep the plain and floating static out of the same item (confusing, not instructive).
	if picked.any(func(s): return s.ad == 1) and picked.any(func(s): return s.ad == 130):
		picked = picked.filter(func(s): return s.ad != 1)
	var net := "10.%d.0.0/16" % rng.randi_range(1, 250)
	var hops := ["10.0.0.2", "10.0.0.6", "10.0.0.10", "10.0.0.14"]
	var lines := PackedStringArray(["R1 learns %s from:" % net])
	for i in picked.size():
		var s: Dictionary = picked[i]
		var desc: String = s.desc
		if desc.contains("%d"):
			desc = desc % (rng.randi_range(2, 60) if s.name == "OSPF" else rng.randi_range(2816, 40000) if s.name == "EIGRP" else rng.randi_range(1, 6))
		lines.append("  %-34s via %s" % [desc, hops[i]])
	var best: Dictionary = picked[0]
	for s in picked:
		if s.ad < best.ad:
			best = s
	var choices: Array = picked.map(func(s): return s.name)
	var ranking := picked.duplicate()
	ranking.sort_custom(func(a, b): return a.ad < b.ad)
	return {"kind": "ad_select", "card_id": "gen.route_picker.ad_select", "exhibit": "\n".join(lines),
		"question": "Which one is installed in the routing table?",
		"choices": choices, "answer_index": choices.find(best.name), "answer": best.name,
		"hint": "Different protocols' metrics can't be compared. The lowest administrative distance wins.",
		"explain": "Administrative distance: " + ", ".join(ranking.map(func(s): return "%s %d" % [s.name, s.ad])) + ". Lowest wins."}
