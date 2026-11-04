class_name StpGen
extends RefCounted
## Spanning Tree Solver items: root bridge election, bridge priority, root ports,
## port roles, the blocked port and root path cost on small generated topologies.

const KINDS := ["root_bridge", "bid", "root_port", "port_role", "blocked", "path_cost"]
const SPEEDS := [100, 1000, 1000, 10000]
const SHAPES := ["triangle", "square", "parallel"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"root_bridge": return _root_bridge(rng)
		"bid": return _bid(rng)
		"root_port": return _root_port(rng)
		"port_role": return _port_role(rng)
		"blocked": return _blocked(rng)
	return _path_cost(rng)

static func _hex4(rng: RandomNumberGenerator) -> String:
	return "%04x" % rng.randi_range(0, 0xffff)

static func rand_mac(rng: RandomNumberGenerator) -> String:
	return "00%02x.%s.%s" % [rng.randi_range(0x10, 0xff), _hex4(rng), _hex4(rng)]

## n switches with distinct MACs; priorities often tie so the MAC tiebreak matters.
static func make_switches(rng: RandomNumberGenerator, n: int, vlan: int) -> Array:
	var bases := [32768, 32768, 32768, 28672, 24576]
	var out: Array = []
	var macs := {}
	for i in n:
		var mac := rand_mac(rng)
		while macs.has(mac):
			mac = rand_mac(rng)
		macs[mac] = true
		out.append({"name": "SW%d" % (i + 1), "priority": STP.bridge_priority(bases[rng.randi() % bases.size()], vlan), "mac": mac})
	return out

static func _link(a: String, ap: String, b: String, bp: String, mbps: int) -> Dictionary:
	return {"a": a, "ap": ap, "b": b, "bp": bp, "mbps": mbps, "cost": STP.cost_for(mbps)}

## A topology: {shape, switches, links, vlan}.
static func make_topology(rng: RandomNumberGenerator, shape: String = "") -> Dictionary:
	if shape.is_empty():
		shape = SHAPES[rng.randi() % SHAPES.size()]
	var vlan: int = [1, 10, 20, 30][rng.randi() % 4]
	var sp := func(): return SPEEDS[rng.randi() % SPEEDS.size()]
	var links: Array = []
	var n := 3
	match shape:
		"triangle":
			links = [_link("SW1", "Gi0/1", "SW2", "Gi0/1", sp.call()), _link("SW1", "Gi0/2", "SW3", "Gi0/1", sp.call()),
				_link("SW2", "Gi0/2", "SW3", "Gi0/2", sp.call())]
		"square":
			n = 4
			links = [_link("SW1", "Gi0/1", "SW2", "Gi0/1", sp.call()), _link("SW1", "Gi0/2", "SW3", "Gi0/2", sp.call()),
				_link("SW2", "Gi0/2", "SW4", "Gi0/2", sp.call()), _link("SW3", "Gi0/1", "SW4", "Gi0/1", sp.call())]
		_:
			n = 2
			var s: int = sp.call()
			var crossed := rng.randf() < 0.6
			links = [_link("SW1", "Gi0/1", "SW2", "Gi0/2" if crossed else "Gi0/1", s),
				_link("SW1", "Gi0/2", "SW2", "Gi0/1" if crossed else "Gi0/2", s)]
	return {"shape": shape, "switches": make_switches(rng, n, vlan), "links": links, "vlan": vlan}

static func _lbl(mbps: int) -> String:
	return "%dG" % (mbps / 1000) if mbps >= 1000 else "%dM" % mbps

static func _dash(text: String, width: int) -> String:
	var left := (width - text.length()) / 2
	return "─".repeat(left) + text + "─".repeat(width - text.length() - left)

static func diagram(t: Dictionary) -> String:
	var L: Array = t.links.map(func(l): return _lbl(l.mbps))
	match t.shape:
		"triangle":
			return "\n".join([
				" ".repeat(14) + "SW1",
				"       Gi0/1 /   \\ Gi0/2",
				"%11s /     \\ %s" % [L[0], L[1]],
				"     Gi0/1 /       \\ Gi0/1",
				"        SW2 ─────── SW3",
				"      Gi0/2 %s Gi0/2" % _dash(" %s " % L[2], 7).replace("─", " ")])
		"square":
			return "\n".join([
				"SW1 Gi0/1 %s Gi0/1 SW2" % _dash(" %s " % L[0], 11),
				"Gi0/2" + " ".repeat(21) + "Gi0/2",
				"  │ " + L[1].rpad(24) + "│ " + L[2],
				"Gi0/2" + " ".repeat(21) + "Gi0/2",
				"SW3 Gi0/1 %s Gi0/1 SW4" % _dash(" %s " % L[3], 11)])
	return "\n".join([
		"SW1 %s %s %s SW2" % [t.links[0].ap, _dash(" %s " % L[0], 11), t.links[0].bp],
		"    %s %s %s" % [t.links[1].ap, _dash(" %s " % L[1], 11), t.links[1].bp]])

## Topology exhibit: diagram, link list (costs optional) and bridge IDs.
static func exhibit(t: Dictionary, with_costs: bool = true) -> String:
	var out := PackedStringArray([diagram(t), ""])
	for l in t.links:
		var c := "  cost %d" % l.cost if with_costs else ""
		out.append("%s %s ── %s %s   %s%s" % [l.a, l.ap, l.b, l.bp, STP.speed_str(l.mbps), c])
	out.append("")
	out.append(bridge_table(t.switches, t.vlan))
	return "\n".join(out)

static func bridge_table(switches: Array, vlan: int) -> String:
	var out := PackedStringArray(["Bridge  Priority  MAC address      (VLAN %d)" % vlan])
	for s in switches:
		out.append("%-7s %-9d %s" % [s.name, int(s.priority), s.mac])
	return "\n".join(out)

static func summary(t: Dictionary, res: Dictionary) -> String:
	var root: Dictionary = res.by_name[res.root]
	var out := PackedStringArray(["Root bridge: %s (lowest bridge ID %s)." % [res.root, STP.bid_str(root)]])
	for s in t.switches:
		if s.name == res.root:
			continue
		out.append("%s: root port %s, root path cost %d." % [s.name, res.root_port.get(s.name, "?"), res.cost[s.name]])
	var alt := STP.blocked(res)
	out.append("Blocked (alternate): %s. Every other non-root port is designated." % (", ".join(alt) if alt.size() > 0 else "none"))
	return "\n".join(out)

static func _root_bridge(rng: RandomNumberGenerator) -> Dictionary:
	var vlan: int = [1, 10, 20][rng.randi() % 3]
	var sws := make_switches(rng, 4, vlan)
	if rng.randf() < 0.6:
		# Force a priority tie for the lowest value so the MAC decides.
		var low: int = sws.map(func(s): return int(s.priority)).min()
		sws[rng.randi() % 4].priority = low
		sws[rng.randi() % 4].priority = low
	var res := STP.solve(sws, [])
	var choices: Array = sws.map(func(s): return s.name)
	var low_p: int = sws.map(func(s): return int(s.priority)).min()
	var tied := sws.filter(func(s): return int(s.priority) == low_p)
	var why := "Lowest priority %d wins." % low_p
	if tied.size() > 1:
		why = "%s tie on priority %d, so the lowest MAC address wins: %s." % [" and ".join(tied.map(func(s): return s.name)), low_p, res.by_name[res.root].mac]
	return {"kind": "root_bridge", "card_id": "gen.stp_solver.root_bridge", "exhibit": bridge_table(sws, vlan),
		"question": "Which switch becomes the root bridge?", "choices": choices,
		"answer_index": choices.find(res.root), "answer": res.root,
		"hint": "Compare bridge IDs: lowest priority wins; if priorities tie, lowest MAC address wins.",
		"explain": why + " Higher-is-better never applies to STP bridge IDs."}

static func _bid(rng: RandomNumberGenerator) -> Dictionary:
	var vlan: int = rng.randi_range(2, 99)
	var base: int = 4096 * rng.randi_range(1, 14)
	var sw := "SW%d" % rng.randi_range(1, 4)
	if rng.randf() < 0.5:
		return {"kind": "bid", "card_id": "gen.stp_solver.bid",
			"exhibit": "%s(config)#spanning-tree vlan %d priority %d" % [sw, vlan, base],
			"question": "What bridge priority does %s advertise in VLAN %d?" % [sw, vlan],
			"answer": str(base + vlan), "placeholder": "number",
			"hint": "PVST+ adds the VLAN number (the extended system ID) to the configured priority.",
			"explain": "%d (configured) + %d (sys-id-ext = VLAN) = %d." % [base, vlan, base + vlan]}
	return {"kind": "bid", "card_id": "gen.stp_solver.bid",
		"exhibit": "%s#show spanning-tree vlan %d\n  Bridge ID  Priority    %d" % [sw, vlan, base + vlan],
		"question": "Which priority value was configured on %s for VLAN %d?" % [sw, vlan],
		"answer": str(base), "placeholder": "multiple of 4096",
		"hint": "Subtract the extended system ID (the VLAN number). Configured priorities are multiples of 4096.",
		"explain": "%d - %d (VLAN) = %d, which is %d x 4096." % [base + vlan, vlan, base, base / 4096]}

static func _root_port(rng: RandomNumberGenerator) -> Dictionary:
	var t := make_topology(rng)
	var res := STP.solve(t.switches, t.links)
	var non_root: Array = t.switches.filter(func(s): return s.name != res.root).map(func(s): return s.name)
	var sw: String = non_root[rng.randi() % non_root.size()]
	var choices: Array = []
	for l in t.links:
		if l.a == sw:
			choices.append(l.ap)
		if l.b == sw:
			choices.append(l.bp)
	choices.sort()
	var ans: String = res.root_port[sw]
	return {"kind": "root_port", "card_id": "gen.stp_solver.root_port", "exhibit": exhibit(t),
		"question": "Which port is %s's root port?" % sw, "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Find the root bridge first. Then add up port costs towards it; ties go to the lowest neighbour bridge ID, then the lowest neighbour port ID.",
		"explain": "Root bridge: %s.\nRoot path cost from each of %s's ports:\n%s" % [res.root, sw, res.why[sw]]}

static func _port_role(rng: RandomNumberGenerator) -> Dictionary:
	var t := make_topology(rng, ["triangle", "square"][rng.randi() % 2])
	var res := STP.solve(t.switches, t.links)
	var keys: Array = res.roles.keys()
	keys.sort()
	# Bias towards the interesting ports: alternate and non-root designated ones.
	var key: String = keys[rng.randi() % keys.size()]
	if rng.randf() < 0.4:
		key = STP.blocked(res)[0]
	var role: String = res.roles[key]
	var choices: Array = ["Root", "Designated", "Alternate (blocking)"]
	var ans: String = choices[STP.ROLES.find(role)]
	return {"kind": "port_role", "card_id": "gen.stp_solver.port_role", "exhibit": exhibit(t),
		"question": "What is the Rapid PVST+ role of %s?" % key, "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Every non-root switch has one root port. On each link, the end closer to the root (then lower bridge ID) is designated. What's left blocks.",
		"explain": summary(t, res)}

static func _blocked(rng: RandomNumberGenerator) -> Dictionary:
	var t := make_topology(rng)
	var res := STP.solve(t.switches, t.links)
	var choices: Array = []
	for l in t.links:
		choices.append("%s %s" % [l.a, l.ap])
		choices.append("%s %s" % [l.b, l.bp])
	choices.sort()
	var ans: String = STP.blocked(res)[0]
	return {"kind": "blocked", "card_id": "gen.stp_solver.blocked", "exhibit": exhibit(t),
		"question": "Which port does spanning tree block?", "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Mark the root bridge's ports designated and each switch's root port. On the remaining link, the switch with the worse cost (or higher bridge ID) blocks.",
		"explain": summary(t, res)}

static func _path_cost(rng: RandomNumberGenerator) -> Dictionary:
	var t := make_topology(rng, ["triangle", "square"][rng.randi() % 2])
	var res := STP.solve(t.switches, t.links)
	var non_root: Array = t.switches.filter(func(s): return s.name != res.root).map(func(s): return s.name)
	var sw: String = non_root[rng.randi() % non_root.size()]
	return {"kind": "path_cost", "card_id": "gen.stp_solver.path_cost", "exhibit": exhibit(t, false),
		"question": "What is %s's root path cost?" % sw, "answer": str(res.cost[sw]), "placeholder": "number",
		"hint": "Default costs: 10 Gbps = 2, 1 Gbps = 4, 100 Mbps = 19, 10 Mbps = 100. Take the cheapest total path to the root bridge.",
		"explain": "Root bridge: %s.\n%s" % [res.root, res.why[sw]]}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
