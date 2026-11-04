class_name STP
extends RefCounted
## Spanning tree (802.1D / Rapid PVST+) on point-to-point links. Pure logic.
## A switch: {name, priority (full bridge priority, sys-id-ext included), mac}.
## A link: {a, ap, b, bp, cost} plus optional a_cost/b_cost overrides and
## a_pid/b_pid port IDs (priority * 4096 + number; default 128.<last number of the port name>).

## Default (short) port costs by speed in Mbps.
const COST := {10: 100, 100: 19, 1000: 4, 10000: 2}
const ROLES := ["Root", "Designated", "Alternate"]

static func cost_for(mbps: int) -> int:
	return COST.get(mbps, 4)

static func speed_str(mbps: int) -> String:
	return "%d Gbps" % (mbps / 1000) if mbps >= 1000 else "%d Mbps" % mbps

## Bridge priority as advertised: configured priority + VLAN (extended system ID).
static func bridge_priority(base: int, vlan: int) -> int:
	return base + vlan

static func valid_base_priority(p: int) -> bool:
	return p >= 0 and p <= 61440 and p % 4096 == 0

static func mac_key(mac: String) -> String:
	return mac.to_lower().replace(".", "").replace(":", "").replace("-", "")

## Is bridge a's ID lower (better) than b's? Priority first, then MAC.
static func bid_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.priority) != int(b.priority):
		return int(a.priority) < int(b.priority)
	return mac_key(a.mac) < mac_key(b.mac)

static func bid_str(s: Dictionary) -> String:
	return "%d %s" % [int(s.priority), s.mac]

static func port_number(port: String) -> int:
	var i := port.length()
	while i > 0 and port[i - 1].is_valid_int():
		i -= 1
	return port.substr(i).to_int()

static func port_id(pri: int, port: String) -> int:
	return pri * 4096 + port_number(port)

static func pid_str(pid: int) -> String:
	return "%d.%d" % [pid / 4096, pid % 4096]

## Ends of every link as seen from each switch: {switch: [{port, peer, peer_port, cost, pid, peer_pid}]}.
static func _ends(switches: Array, links: Array) -> Dictionary:
	var out := {}
	for s in switches:
		out[s.name] = []
	for l in links:
		var c := int(l.get("cost", 4))
		var a_pid := int(l.get("a_pid", port_id(128, l.ap)))
		var b_pid := int(l.get("b_pid", port_id(128, l.bp)))
		out[l.a].append({"port": l.ap, "peer": l.b, "peer_port": l.bp, "cost": int(l.get("a_cost", c)), "pid": a_pid, "peer_pid": b_pid})
		out[l.b].append({"port": l.bp, "peer": l.a, "peer_port": l.ap, "cost": int(l.get("b_cost", c)), "pid": b_pid, "peer_pid": a_pid})
	return out

## Converged spanning tree. Returns:
## {root, by_name, cost{sw}, root_port{sw: port}, roles{"SW Port": role}, why{sw: text}}
static func solve(switches: Array, links: Array) -> Dictionary:
	var by_name := {}
	for s in switches:
		by_name[s.name] = s
	var root: Dictionary = switches[0]
	for s in switches:
		if bid_less(s, root):
			root = s
	var ends := _ends(switches, links)
	# Root path cost: shortest path where each hop adds the receiving port's cost.
	var cost := {}
	for s in switches:
		cost[s.name] = 1 << 30
	cost[root.name] = 0
	for _i in switches.size():
		for sw in ends:
			for e in ends[sw]:
				if cost[e.peer] + e.cost < cost[sw]:
					cost[sw] = cost[e.peer] + e.cost
	var root_port := {}
	var why := {}
	for sw in ends:
		if sw == root.name:
			continue
		var best := {}
		for e in ends[sw]:
			if cost[e.peer] >= 1 << 30:
				continue
			if best.is_empty() or _rp_better(e, best, cost, by_name):
				best = e
		if best.is_empty():
			continue
		root_port[sw] = best.port
		why[sw] = _rp_reason(sw, best, ends[sw], cost, by_name)
	var roles := {}
	for l in links:
		var a_key := "%s %s" % [l.a, l.ap]
		var b_key := "%s %s" % [l.b, l.bp]
		var a_pid := int(l.get("a_pid", port_id(128, l.ap)))
		var b_pid := int(l.get("b_pid", port_id(128, l.bp)))
		var a_wins := _desig_better([cost[l.a], by_name[l.a], a_pid], [cost[l.b], by_name[l.b], b_pid])
		var d_key := a_key if a_wins else b_key
		var o_sw: String = l.b if a_wins else l.a
		var o_port: String = l.bp if a_wins else l.ap
		roles[d_key] = "Designated"
		roles["%s %s" % [o_sw, o_port]] = "Root" if root_port.get(o_sw, "") == o_port else "Alternate"
	return {"root": root.name, "by_name": by_name, "cost": cost, "root_port": root_port, "roles": roles, "why": why}

static func _rp_better(e: Dictionary, best: Dictionary, cost: Dictionary, by_name: Dictionary) -> bool:
	var ce: int = cost[e.peer] + e.cost
	var cb: int = cost[best.peer] + best.cost
	if ce != cb:
		return ce < cb
	if e.peer != best.peer:
		return bid_less(by_name[e.peer], by_name[best.peer])
	if e.peer_pid != best.peer_pid:
		return e.peer_pid < best.peer_pid
	return e.pid < best.pid

## Designated port on a segment: lowest root cost, then lowest bridge ID, then lowest port ID.
static func _desig_better(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1].name != b[1].name:
		return bid_less(a[1], b[1])
	return a[2] < b[2]

static func _rp_reason(sw: String, best: Dictionary, all: Array, cost: Dictionary, by_name: Dictionary) -> String:
	var lines := PackedStringArray()
	for e in all:
		if cost[e.peer] >= 1 << 30:
			continue
		lines.append("  %s %s: %d (%s) + %d = %d" % [sw, e.port, cost[e.peer], e.peer, e.cost, cost[e.peer] + e.cost])
	var c: int = cost[best.peer] + best.cost
	var tied := all.filter(func(e): return cost[e.peer] + e.cost == c)
	var tb := "lowest root path cost"
	if tied.size() > 1:
		var peers := {}
		for e in tied:
			peers[e.peer] = true
		if peers.size() > 1:
			tb = "costs tie, so the lowest neighbour bridge ID wins (%s)" % best.peer
		else:
			tb = "cost and neighbour tie, so the lowest neighbour port ID wins (%s %s, %s)" % [best.peer, best.peer_port, pid_str(best.peer_pid)]
	return "%s\n  → %s is the root port: %s." % ["\n".join(lines), best.port, tb]

## Ports a switch blocks (Alternate role).
static func blocked(res: Dictionary) -> Array:
	var out: Array = res.roles.keys().filter(func(k): return res.roles[k] == "Alternate")
	out.sort()
	return out

## "show spanning-tree vlan N" for one switch.
static func show(res: Dictionary, sw: String, vlan: int, ports: Array) -> String:
	var me: Dictionary = res.by_name[sw]
	var root: Dictionary = res.by_name[res.root]
	var out := PackedStringArray(["VLAN%04d" % vlan, "  Spanning tree enabled protocol rstp"])
	out.append("  Root ID    Priority    %d" % int(root.priority))
	out.append("             Address     %s" % root.mac)
	if sw == res.root:
		out.append("             This bridge is the root")
	else:
		out.append("             Cost        %d" % res.cost[sw])
		out.append("             Port        %s" % res.root_port.get(sw, ""))
	out.append("")
	out.append("  Bridge ID  Priority    %d  (priority %d sys-id-ext %d)" % [int(me.priority), int(me.priority) - vlan, vlan])
	out.append("             Address     %s" % me.mac)
	out.append("")
	out.append("Interface           Role Sts Cost      Prio.Nbr Type")
	out.append("------------------- ---- --- --------- -------- --------------------------------")
	for p in ports:
		var role: String = res.roles.get("%s %s" % [sw, p.port], "Designated")
		var sts := "BLK" if role == "Alternate" else "FWD"
		out.append("%-19s %-4s %-3s %-9d %-8s %s" % [p.port, role.substr(0, 4), sts, int(p.cost), pid_str(int(p.pid)), p.get("type", "P2p")])
	return "\n".join(out)
