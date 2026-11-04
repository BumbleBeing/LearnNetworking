class_name RoutingTable
extends RefCounted
## A router's RIB: candidate routes per prefix, the best installed by administrative
## distance then metric; forwarding by longest-prefix match. Renders "show ip route".
## Equal-cost routes from the same source are all installed (ECMP), like IOS.

const AD := {"C": 0, "L": 0, "S": 1, "B": 20, "D": 90, "O": 110, "R": 120}
const NAMES := {"C": "connected", "L": "local", "S": "static", "B": "BGP", "D": "EIGRP", "O": "OSPF", "R": "RIP"}

var candidates: Array = []
var routes: Array = []   # installed, sorted

## Build a route dict. ad < 0 uses the protocol default.
static func route(code: String, net: String, length: int, next_hop: String = "", iface: String = "", metric: int = 0, ad: int = -1) -> Dictionary:
	return {"code": code, "net": IPv4.network(IPv4.parse(net), length), "len": length,
		"ad": AD.get(code, 255) if ad < 0 else ad, "metric": metric, "next_hop": next_hop, "iface": iface}

func add(r: Dictionary) -> void:
	candidates.append(r)
	_rebuild()

func _rebuild() -> void:
	var best := {}   # "net/len" -> installed routes (several when they tie)
	for r in candidates:
		var key := "%d/%d" % [r.net, r.len]
		if not best.has(key) or _better(r, best[key][0]):
			best[key] = [r]
		elif _ties(r, best[key][0]) and not best[key].any(func(x): return x.next_hop == r.next_hop and x.iface == r.iface):
			best[key].append(r)
	routes = []
	for key in best:
		routes.append_array(best[key])
	routes.sort_custom(_order)

static func _better(a: Dictionary, b: Dictionary) -> bool:
	return a.ad < b.ad or (a.ad == b.ad and a.metric < b.metric)

## Equal-cost paths: same source, distance and metric. Connected routes never share a prefix.
static func _ties(a: Dictionary, b: Dictionary) -> bool:
	return a.code == b.code and a.ad == b.ad and a.metric == b.metric and not a.code in ["C", "L"]

## By prefix, then equal-cost paths by next hop, so lookup() is repeatable.
static func _order(a: Dictionary, b: Dictionary) -> bool:
	if a.net != b.net or a.len != b.len:
		return a.net < b.net or (a.net == b.net and a.len < b.len)
	if a.next_hop != b.next_hop:
		return IPv4.parse(a.next_hop) < IPv4.parse(b.next_hop)
	return a.iface < b.iface

## Installed routes whose prefix contains ip.
func matches(ip: int) -> Array:
	return routes.filter(func(r): return IPv4.network(ip, r.len) == r.net)

## Longest-prefix match, or {} if the packet would be dropped. With equal-cost paths this is
## the first (lowest next hop); IOS would share the traffic between them.
func lookup(ip: int) -> Dictionary:
	var best := {}
	for r in matches(ip):
		if best.is_empty() or r.len > best.len:
			best = r
	return best

## Every equal-cost path for the prefix lookup() picks.
func paths(ip: int) -> Array:
	var best := lookup(ip)
	if best.is_empty():
		return []
	return routes.filter(func(r): return r.net == best.net and r.len == best.len)

static func prefix_str(r: Dictionary) -> String:
	return "%s/%d" % [IPv4.to_str(r.net), r.len]

static func describe(r: Dictionary) -> String:
	if r.code in ["C", "L"]:
		return "%s, directly connected (%s)" % [prefix_str(r), r.iface]
	return "%s via %s (%s, AD %d)" % [prefix_str(r), r.next_hop, NAMES.get(r.code, r.code), r.ad]

func show() -> String:
	var lines := PackedStringArray()
	lines.append("Codes: L - local, C - connected, S - static, R - RIP, O - OSPF,")
	lines.append("       D - EIGRP, B - BGP, E2 - OSPF external type 2, * - candidate default")
	lines.append("")
	var default := routes.filter(func(r): return r.len == 0)
	if default.is_empty():
		lines.append("Gateway of last resort is not set")
	else:
		lines.append("Gateway of last resort is %s to network 0.0.0.0" % default[0].next_hop)
	lines.append("")
	var prev := {}
	for r in routes:
		var code: String = r.code + ("*" if r.len == 0 else "") + r.get("ext", "")
		var body := ""
		if r.code in ["C", "L"]:
			body = "%s is directly connected, %s" % [prefix_str(r), r.iface]
		else:
			body = "[%d/%d] via %s" % [r.ad, r.metric, r.next_hop]
			if not r.iface.is_empty():
				body += ", " + r.iface
			if not prev.is_empty() and prev.net == r.net and prev.len == r.len:
				# Another equal-cost path: IOS lines it up under the first one's [AD/metric].
				lines.append(" ".repeat(7 + prefix_str(r).length() + 1) + body)
				prev = r
				continue
			body = "%s %s" % [prefix_str(r), body]
		lines.append("%-6s %s" % [code, body])
		prev = r
	return "\n".join(lines)
