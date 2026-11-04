class_name OSPF
extends RefCounted
## Single-area OSPFv2 logic: router ID, DR/BDR election, interface cost, SPF,
## neighbour requirements and network statement matching. Pure functions.

const AD := 110
const DEFAULT_REF_MBPS := 100

## Router ID: manual router-id, else highest up loopback IP, else highest up interface IP.
## ifaces: [{name, ip, up}] (loopbacks are recognised by name). Returns {rid, reason}.
static func router_id(manual: String, ifaces: Array) -> Dictionary:
	if not manual.is_empty():
		return {"rid": manual, "reason": "configured with the router-id command"}
	var best := {"lo": -1, "phys": -1}
	var src := {"lo": "", "phys": ""}
	for i in ifaces:
		if i.ip.is_empty() or not i.get("up", true):
			continue
		var kind := "lo" if i.name.begins_with("Loopback") else "phys"
		var v := IPv4.parse(i.ip)
		if v > best[kind]:
			best[kind] = v
			src[kind] = i.name
	if best.lo >= 0:
		return {"rid": IPv4.to_str(best.lo), "reason": "no router-id command, so the highest up loopback address (%s)" % src.lo}
	if best.phys >= 0:
		return {"rid": IPv4.to_str(best.phys), "reason": "no router-id or loopback, so the highest up interface address (%s)" % src.phys}
	return {"rid": "", "reason": "no usable address"}

## IOS cost: reference bandwidth / interface bandwidth, truncated, minimum 1.
static func cost(bw_mbps: float, ref_mbps: int = DEFAULT_REF_MBPS) -> int:
	return max(1, int(floor(ref_mbps / bw_mbps + 0.000001)))

static func rid_less(a: String, b: String) -> bool:
	return IPv4.parse(a) < IPv4.parse(b)

## DR/BDR election on one segment (everyone starting together).
## routers: [{name, rid, priority}]. Highest priority, then highest RID; priority 0 never wins.
static func elect(routers: Array) -> Dictionary:
	var eligible := routers.filter(func(r): return int(r.priority) > 0)
	eligible.sort_custom(func(a, b): return int(a.priority) > int(b.priority) or (int(a.priority) == int(b.priority) and rid_less(b.rid, a.rid)))
	return {"dr": eligible[0].name if eligible.size() > 0 else "", "bdr": eligible[1].name if eligible.size() > 1 else ""}

## Does "network <net> <wildcard> area X" enable an interface with this IP?
static func network_matches(net: String, wildcard: String, ip: String) -> bool:
	return ACL.addr_matches(IPv4.parse(ip), IPv4.parse(net), IPv4.parse(wildcard))

## Why two OSPF interfaces on a link won't become neighbours (empty = they will).
## Each side: {rid, ip, mask, area, hello, dead, passive, mtu}. Process ID, cost and priority don't matter.
static func neighbor_issues(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	if a.get("passive", false) or b.get("passive", false):
		out.append("passive")
	var la := IPv4.prefix_from_mask(IPv4.parse(a.mask))
	var lb := IPv4.prefix_from_mask(IPv4.parse(b.mask))
	if la != lb or IPv4.network(IPv4.parse(a.ip), la) != IPv4.network(IPv4.parse(b.ip), lb):
		out.append("subnet")
	if str(a.area) != str(b.area):
		out.append("area")
	if int(a.hello) != int(b.hello) or int(a.dead) != int(b.dead):
		out.append("timers")
	if a.rid == b.rid:
		out.append("rid")
	if int(a.get("mtu", 1500)) != int(b.get("mtu", 1500)):
		out.append("mtu")
	return out

const ISSUE_TEXT := {
	"passive": "One side is a passive interface, so it sends no Hellos",
	"subnet": "The interfaces are in different subnets",
	"area": "The area IDs don't match",
	"timers": "The Hello/Dead timers don't match",
	"rid": "Both routers have the same router ID",
	"mtu": "The interface MTUs don't match (stuck in EXSTART/EXCHANGE)",
	"pid": "The OSPF process IDs are different",
	"cost": "The interface costs are different",
	"priority": "The OSPF priorities are different",
}

## Dijkstra over directed edges [{from, to, cost}]. Returns {dist{}, first{} (sets of first hops), prev{}}.
## Equal-cost paths are kept: first[n] lists every first-hop neighbour on a best path.
static func spf(nodes: Array, edges: Array, src: String) -> Dictionary:
	var inf := 1 << 30
	var dist := {}
	var first := {}
	for n in nodes:
		dist[n] = inf
		first[n] = []
	dist[src] = 0
	var done := {}
	while done.size() < nodes.size():
		var u := ""
		for n in nodes:
			if not done.has(n) and dist[n] < inf and (u.is_empty() or dist[n] < dist[u]):
				u = n
		if u.is_empty():
			break
		done[u] = true
		for e in edges:
			if e.from != u or done.has(e.to):
				continue
			var d: int = dist[u] + int(e.cost)
			var via: Array = [e.to] if u == src else first[u]
			if d < dist[e.to]:
				dist[e.to] = d
				first[e.to] = via.duplicate()
			elif d == dist[e.to]:
				for h in via:
					if not h in first[e.to]:
						first[e.to].append(h)
	return {"dist": dist, "first": first}

## "show ip ospf neighbor". rows: [{rid, pri, state, role, address, iface}]
static func show_neighbors(rows: Array) -> String:
	var out := PackedStringArray(["%-15s %-5s %-15s %-11s %-15s %s" % ["Neighbor ID", "Pri", "State", "Dead Time", "Address", "Interface"]])
	for r in rows:
		out.append("%-15s %3d   %-15s %-11s %-15s %s" % [r.rid, int(r.pri), "%s/%s" % [r.state, "  -" if r.role == "-" else r.role], "00:00:3%d" % (int(r.pri) % 10), r.address, r.iface])
	return "\n".join(out)

## "show ip ospf interface X". side: {ip, mask, area, pid, rid, cost, priority, hello, dead, passive, mtu, state?, nbrs?}
static func show_interface(name: String, side: Dictionary) -> String:
	var state: String = side.get("state", "DR" if int(side.priority) > 0 else "DROTHER")
	var lines := PackedStringArray([
		"%s is up, line protocol is up" % name,
		"  Internet Address %s/%d, Area %s" % [side.ip, IPv4.prefix_from_mask(IPv4.parse(side.mask)), side.area],
		"  Process ID %d, Router ID %s, Network Type %s, Cost: %d" % [int(side.pid), side.rid, "LOOPBACK" if name.begins_with("Loopback") else "BROADCAST", int(side.cost)],
		"  Transmit Delay is 1 sec, State %s, Priority %d" % [state, int(side.priority)],
		"  Timer intervals configured, Hello %d, Dead %d, Wait %d" % [int(side.hello), int(side.dead), int(side.dead)],
	])
	if side.get("passive", false):
		lines.append("    No Hellos (Passive interface)")
	if int(side.get("mtu", 1500)) != 1500:
		lines.append("  IP MTU %d" % int(side.mtu))
	if side.has("nbrs"):
		lines.append("  Neighbor Count is %d, Adjacent neighbor count is %d" % [int(side.nbrs), int(side.nbrs)])
	return "\n".join(lines)
