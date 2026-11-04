class_name FhrpGen
extends RefCounted
## HSRP Election items: who becomes active, preempt timelines, interface tracking,
## virtual MAC addresses and HSRP/VRRP/GLBP differences.

const KINDS := ["election", "preempt", "tracking", "vmac", "compare"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"preempt": return _preempt(rng)
		"tracking": return _tracking(rng)
		"vmac": return _vmac(rng)
		"compare": return _compare(rng)
	return _election(rng)

## Active router when everyone starts together: highest priority, then highest interface IP.
static func elect(routers: Array) -> Dictionary:
	var best: Dictionary = routers[0]
	for r in routers:
		if r.priority > best.priority or (r.priority == best.priority and IPv4.parse(r.ip) > IPv4.parse(best.ip)):
			best = r
	return best

static func _routers(rng: RandomNumberGenerator, n: int) -> Array:
	var subnet := rng.randi_range(1, 200)
	var hosts: Array = []
	while hosts.size() < n:
		var h := rng.randi_range(2, 254)
		if not h in hosts:
			hosts.append(h)
	var out: Array = []
	for i in n:
		out.append({"name": "R%d" % (i + 1), "ip": "10.%d.1.%d" % [subnet, hosts[i]], "priority": [100, 100, 100, 110, 90, 150][rng.randi() % 6]})
	return out

static func _election(rng: RandomNumberGenerator) -> Dictionary:
	var rs := _routers(rng, rng.randi_range(2, 3))
	if rng.randf() < 0.5:
		for r in rs:
			r.priority = 100   # all default: the IP decides
	var w := elect(rs)
	var lines := PackedStringArray(["Router  Gi0/0 address   HSRP priority", "------  -------------   -------------"])
	for r in rs:
		lines.append("%-7s %-15s %d%s" % [r.name, r.ip, r.priority, " (default)" if r.priority == 100 else ""])
	var tie := rs.filter(func(r): return r.priority == w.priority).size() > 1
	var choices: Array = rs.map(func(r): return r.name)
	return {"kind": "election", "card_id": "gen.hsrp_election.election",
		"exhibit": "All routers are in HSRP group 1 (virtual IP %s.1) and boot at the same time.\n\n%s" % [w.ip.substr(0, w.ip.rfind(".")), "\n".join(lines)],
		"question": "Which router becomes active?", "choices": choices, "answer_index": choices.find(w.name), "answer": w.name,
		"hint": "Highest priority wins (default 100). If priorities tie, the highest interface IP address wins.",
		"explain": ("Priorities tie at %d, so the highest interface IP wins: %s (%s)." if tie else "Highest priority wins: %s with %d.") % (
			[w.priority, w.name, w.ip] if tie else [w.name, w.priority])}

static func _preempt(rng: RandomNumberGenerator) -> Dictionary:
	var p_old: int = [100, 100, 105][rng.randi() % 3]
	var p_new: int = p_old + [5, 10, 50][rng.randi() % 3]
	var pre := rng.randf() < 0.5
	var choices: Array = ["R1 stays active", "R2 takes over as active"]
	var ans: String = choices[1] if pre else choices[0]
	return {"kind": "preempt", "card_id": "gen.hsrp_election.preempt",
		"exhibit": "R1: standby 1 priority %d       (active, running for an hour)\nR2: standby 1 priority %d%s\n\nR2 is rebooted and comes back up." % [p_old, p_new, "\nR2: standby 1 preempt" if pre else "        (preempt not configured)"],
		"question": "What happens once R2 is back?", "choices": choices, "answer_index": choices.find(ans), "answer": ans,
		"hint": "Without preempt, HSRP never takes the active role from a working active router, even with a higher priority.",
		"explain": ("R2 has the higher priority (%d > %d) and preempt, so it takes over." % [p_new, p_old]) if pre
			else "R2 has the higher priority (%d > %d) but no preempt, so it becomes standby and R1 stays active until it fails." % [p_new, p_old]}

static func _tracking(rng: RandomNumberGenerator) -> Dictionary:
	var p1: int = [110, 120, 150][rng.randi() % 3]
	var dec: int = [10, 20, 30, 60][rng.randi() % 4]
	var p2: int = [100, 100, 105][rng.randi() % 3]
	var pre2 := rng.randf() < 0.7
	if p1 - dec == p2:
		dec += 10   # avoid an exact tie: the outcome would hinge on interface addresses
	var eff := p1 - dec
	var takes := eff < p2 and pre2
	var choices: Array = ["R1 stays active", "R2 takes over as active"]
	var ans: String = choices[1] if takes else choices[0]
	var why := ""
	if eff >= p2:
		why = "R1 drops to %d - %d = %d, still not below R2's %d, so R1 stays active." % [p1, dec, eff, p2]
	elif not pre2:
		why = "R1 drops to %d, below R2's %d, but R2 has no preempt, so it doesn't take over." % [eff, p2]
	else:
		why = "R1 drops to %d - %d = %d, below R2's %d, and R2 has preempt, so R2 takes over." % [p1, dec, eff, p2]
	return {"kind": "tracking", "card_id": "gen.hsrp_election.tracking",
		"exhibit": "R1 (active):\n interface g0/0\n  standby 1 priority %d\n  standby 1 preempt\n  standby 1 track g0/1 %d\n\nR2:\n interface g0/0\n  standby 1 priority %d%s\n\nR1's uplink Gi0/1 goes down." % [p1, dec, p2, "\n  standby 1 preempt" if pre2 else ""],
		"question": "What happens?", "choices": choices, "answer_index": choices.find(ans), "answer": ans,
		"hint": "Subtract the decrement from R1's priority. R2 only takes over if R1 is now lower AND R2 has preempt.",
		"explain": why}

static func mac_for(proto: String, group: int) -> String:
	match proto:
		"HSRPv2": return HsrpSim.vmac(group, 2)
		"VRRP": return "0000.5e00.01%02x" % group
	return HsrpSim.vmac(group, 1)

static func _vmac(rng: RandomNumberGenerator) -> Dictionary:
	var proto: String = ["HSRPv1", "HSRPv1", "HSRPv2", "VRRP"][rng.randi() % 4]
	var group := rng.randi_range(1, 255)
	var mac := mac_for(proto, group)
	var rule: String = {"HSRPv1": "0000.0c07.acXX (XX = group in hex)", "HSRPv2": "0000.0c9f.fXXX (XXX = group in hex)", "VRRP": "0000.5e00.01XX (XX = group in hex)"}[proto]
	if rng.randf() < 0.5:
		return {"kind": "vmac", "card_id": "gen.hsrp_election.vmac", "prompt": "%s group %d" % [proto, group],
			"question": "What is the virtual MAC address?", "answer": mac, "placeholder": "xxxx.xxxx.xxxx", "wide": true,
			"hint": "HSRPv1 0000.0c07.acXX, HSRPv2 0000.0c9f.fXXX, VRRP 0000.5e00.01XX, with the group number in hex.",
			"explain": "%s: %s. Group %d = 0x%x → %s" % [proto, rule, group, group, mac]}
	return {"kind": "vmac", "card_id": "gen.hsrp_election.vmac", "prompt": mac,
		"question": "Which group number does this %s virtual MAC belong to?" % proto, "answer": str(group), "placeholder": "group number",
		"hint": "The last hex digits are the group number. Convert them to decimal.",
		"explain": "%s: %s. 0x%x = %d." % [proto, rule, group, group]}

const FACTS := [
	["Cisco proprietary; one active and one standby router", "HSRP"],
	["Open standard (RFC 5798); the roles are master and backup", "VRRP"],
	["Load-balances one virtual IP across several routers", "GLBP"],
	["Uses an AVG that hands out virtual MACs to AVFs", "GLBP"],
	["Preemption is on by default", "VRRP"],
	["Preemption is off by default", "HSRP"],
	["The virtual IP may be a real router's own interface address", "VRRP"],
]

static func _compare(rng: RandomNumberGenerator) -> Dictionary:
	var f: Array = FACTS[rng.randi() % FACTS.size()]
	var choices: Array = ["HSRP", "VRRP", "GLBP"]
	return {"kind": "compare", "card_id": "gen.hsrp_election.compare", "prompt": f[0],
		"question": "Which first hop redundancy protocol is this?", "choices": choices,
		"answer_index": choices.find(f[1]), "answer": f[1],
		"hint": "HSRP: Cisco, active/standby. VRRP: open standard, master/backup. GLBP: Cisco, load balancing.",
		"explain": "HSRP: Cisco, active/standby, preempt off by default.\nVRRP: open standard, master/backup, preempt on by default, can use a real interface IP.\nGLBP: Cisco, one AVG and up to four AVFs share the load."}

static func check(item: Dictionary, response: String) -> bool:
	if item.kind == "vmac" and item.answer.contains("."):
		var norm := func(m: String) -> String: return m.to_lower().replace(".", "").replace(":", "").replace("-", "").strip_edges()
		return norm.call(response) == norm.call(item.answer)
	return Grader.same_value(item.answer, response)
