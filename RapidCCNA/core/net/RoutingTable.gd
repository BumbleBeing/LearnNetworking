class_name RoutingTable
extends RefCounted
## A router's RIB: candidate routes per prefix, best one installed by administrative
## distance then metric; forwarding by longest-prefix match. Renders "show ip route".

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
	var best := {}
	for r in candidates:
		var key := "%d/%d" % [r.net, r.len]
		if not best.has(key) or _better(r, best[key]):
			best[key] = r
	routes = best.values()
	routes.sort_custom(func(a, b): return a.net < b.net or (a.net == b.net and a.len < b.len))

static func _better(a: Dictionary, b: Dictionary) -> bool:
	return a.ad < b.ad or (a.ad == b.ad and a.metric < b.metric)

## Installed routes whose prefix contains ip.
func matches(ip: int) -> Array:
	return routes.filter(func(r): return IPv4.network(ip, r.len) == r.net)

## Longest-prefix match, or {} if the packet would be dropped.
func lookup(ip: int) -> Dictionary:
	var best := {}
	for r in matches(ip):
		if best.is_empty() or r.len > best.len:
			best = r
	return best

static func prefix_str(r: Dictionary) -> String:
	return "%s/%d" % [IPv4.to_str(r.net), r.len]

static func describe(r: Dictionary) -> String:
	if r.code in ["C", "L"]:
		return "%s, directly connected (%s)" % [prefix_str(r), r.iface]
	return "%s via %s (%s, AD %d)" % [prefix_str(r), r.next_hop, NAMES.get(r.code, r.code), r.ad]

func show() -> String:
	var lines := PackedStringArray()
	lines.append("Codes: L - local, C - connected, S - static, R - RIP, O - OSPF,")
	lines.append("       D - EIGRP, B - BGP, * - candidate default")
	lines.append("")
	var default := routes.filter(func(r): return r.len == 0)
	if default.is_empty():
		lines.append("Gateway of last resort is not set")
	else:
		lines.append("Gateway of last resort is %s to network 0.0.0.0" % default[0].next_hop)
	lines.append("")
	for r in routes:
		var code: String = r.code + ("*" if r.len == 0 else "")
		var body := ""
		if r.code in ["C", "L"]:
			body = "%s is directly connected, %s" % [prefix_str(r), r.iface]
		else:
			body = "%s [%d/%d] via %s" % [prefix_str(r), r.ad, r.metric, r.next_hop]
			if not r.iface.is_empty():
				body += ", " + r.iface
		lines.append("%-6s %s" % [code, body])
	return "\n".join(lines)
