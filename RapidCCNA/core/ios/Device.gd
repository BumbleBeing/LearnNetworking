class_name Device
extends RefCounted
## Configuration state of one simulated device (router, switch or end host).

const TYPES := {"gigabitethernet": "GigabitEthernet", "fastethernet": "FastEthernet", "ethernet": "Ethernet",
	"tengigabitethernet": "TenGigabitEthernet", "serial": "Serial", "vlan": "Vlan", "loopback": "Loopback",
	"port-channel": "Port-channel"}
const SHORT := {"TenGigabitEthernet": "Te", "GigabitEthernet": "Gi", "FastEthernet": "Fa", "Ethernet": "Et", "Serial": "Se",
	"Vlan": "Vl", "Loopback": "Lo", "Port-channel": "Po"}
## Interface bandwidth in Mbps by type (OSPF and STP costs).
const BANDWIDTH := {"TenGigabitEthernet": 10000.0, "GigabitEthernet": 1000.0, "FastEthernet": 100.0, "Ethernet": 10.0,
	"Serial": 1.544, "Loopback": 8000000.0, "Vlan": 1000.0}

var hostname := "Router"
var type := "router"            # router | switch | host
var interfaces: Dictionary = {} # canonical name -> interface dict
var iface_order: Array = []
var vlans: Dictionary = {1: "default"}
var static_routes: Array = []   # {net:int, len:int, next_hop:String, iface:String, ad:int}
var acls: Dictionary = {}       # name -> {standard:bool, entries:Array}
var nat_static: Array = []      # {local, global}
var nat_pools: Dictionary = {}  # name -> {start, end, mask}
var nat_rules: Array = []       # {acl, pool, iface, overload}
var default_gateway := ""
var enable_secret := ""
var password_encryption := false
var lines: Dictionary = {}      # "vty 0 4" / "console 0" -> {password, login, transport}
var mac := ""                   # base MAC (bridge ID)
var stp_mode := "pvst"          # pvst | rapid-pvst
var stp_priority: Dictionary = {}   # vlan -> configured base priority (default 32768)
var ospf: Dictionary = {}       # {} = not running; see Commands.h_router_ospf
var cdp_run := true             # CDP on globally (Cisco default); hosts don't run it
var lldp_run := false           # LLDP off globally (Cisco default)
var platform := ""              # shown by CDP/LLDP
var capability := ""            # CDP capability letters, e.g. "R B S I"
var _net: WeakRef               # the Network this device belongs to (weak: avoids a reference cycle)

static func create(def: Dictionary) -> Device:
	var d := Device.new()
	d.type = def.get("type", "router")
	d.hostname = def.get("name", "Router")
	for i in def.get("interfaces", []):
		var n := canon_iface(i.name)
		d.add_interface(n, i.get("link", true))
		if i.has("ip"):
			d.interfaces[n].ip = i.ip
			d.interfaces[n].mask = i.mask
		if i.has("shutdown"):
			d.interfaces[n].shutdown = i.shutdown
	d.default_gateway = def.get("gateway", "")
	d.cdp_run = def.get("cdp", d.type != "host")
	d.lldp_run = def.get("lldp", false)
	d.platform = def.get("platform", {"router": "ISR4321", "switch": "WS-C2960X", "host": "Host"}.get(d.type, ""))
	d.capability = def.get("capability", {"router": "R B S I", "switch": "S I", "host": "H"}.get(d.type, ""))
	d.mac = def.get("mac", "00%s.%s.%s" % [("%06x" % (d.hostname.hash() & 0xffffff)).substr(0, 2),
		("%06x" % (d.hostname.hash() & 0xffffff)).substr(2, 4), "%04x" % ((d.hostname.hash() >> 8) & 0xffff)])
	return d

func network():
	return _net.get_ref() if _net else null

## Canonical interface name from any common abbreviation, or "" if invalid.
## "g0/0", "gi 0/0", "GigabitEthernet0/0", "fa0/1", "lo0", "vlan 10", "s0/0/0".
static func canon_iface(text: String) -> String:
	var t := text.replace(" ", "").to_lower()
	var i := 0
	while i < t.length() and not t[i].is_valid_int():
		i += 1
	var prefix := t.substr(0, i)
	var rest := t.substr(i)
	if prefix.is_empty() or rest.is_empty() or not rest.lstrip("0123456789/.").is_empty():
		return ""
	var found := ""
	for k in TYPES:
		if k.begins_with(prefix):
			if not found.is_empty():
				return ""   # ambiguous
			found = k
	return "" if found.is_empty() else TYPES[found] + rest

static func short_name(n: String) -> String:
	for full in SHORT:
		if n.begins_with(full):
			return SHORT[full] + n.substr(full.length())
	return n

func add_interface(n: String, link: bool = true) -> Dictionary:
	if interfaces.has(n):
		return interfaces[n]
	var virtual := n.begins_with("Vlan") or n.begins_with("Loopback") or n.begins_with("Port-channel")
	interfaces[n] = {"name": n, "ip": "", "mask": "", "link": link or n.begins_with("Loopback"),
		"shutdown": (type == "router" and not n.begins_with("Loopback")) or n.begins_with("Vlan"),
		"physical": not virtual, "description": "", "mode": "", "access_vlan": 1, "native": 1,
		"allowed": "all", "nonegotiate": false, "nat": "", "acl_in": "", "acl_out": "",
		"ps": {"enabled": false, "maximum": 1, "violation": "shutdown", "sticky": false, "macs": []},
		"channel_group": 0, "channel_mode": "", "portfast": false, "bpduguard": false, "stp_cost": 0,
		"ospf_cost": 0, "ospf_priority": 1, "ospf_hello": 10, "ospf_dead": 40, "ospf_area": "", "ospf_pid": 0,
		"cdp": true, "lldp_tx": true, "lldp_rx": true}
	iface_order.append(n)
	return interfaces[n]

func iface(n: String) -> Dictionary:
	return interfaces.get(canon_iface(n), {})

func is_switchport(i: Dictionary) -> bool:
	return type == "switch" and (i.physical or i.name.begins_with("Port-channel"))

func bandwidth(n: String) -> float:
	for t in BANDWIDTH:
		if n.begins_with(t):
			return BANDWIDTH[t]
	return 1000.0

## Member ports of channel group g.
func members(g: int) -> Array:
	return iface_order.filter(func(n): return interfaces[n].channel_group == g)

func is_up(i: Dictionary) -> bool:
	if i.name.begins_with("Port-channel"):
		if i.shutdown:
			return false
		var net = network()
		return net != null and L2Sim.channel(net, hostname, i.name.substr(12).to_int()).up
	if i.shutdown or not i.link:
		return false
	if i.name.begins_with("Vlan"):
		# An SVI is up when its VLAN exists and some up port carries it.
		var vid: int = i.name.substr(4).to_int()
		if not vlans.has(vid):
			return false
		return interfaces.values().any(func(p): return is_switchport(p) and is_up(p) and (p.mode == "trunk" or p.access_vlan == vid))
	return true

## [status, protocol] as shown by show ip interface brief.
func status(i: Dictionary) -> Array:
	if i.shutdown:
		return ["administratively down", "down"]
	return ["up", "up"] if is_up(i) else ["down", "down"]

## Is the switchport carrying VLAN vid as a trunk?
func trunk_allows(i: Dictionary, vid: int) -> bool:
	return i.mode == "trunk" and (i.allowed == "all" or vid in parse_vlan_list(i.allowed))

static func parse_vlan_list(s: String) -> Array:
	var out: Array = []
	for part in s.replace(" ", "").split(",", false):
		if part.contains("-"):
			var ab := part.split("-")
			if ab.size() == 2 and ab[0].is_valid_int() and ab[1].is_valid_int():
				for v in range(ab[0].to_int(), ab[1].to_int() + 1):
					out.append(v)
		elif part.is_valid_int():
			out.append(part.to_int())
	return out

## Connected, local and resolvable static routes (plus a default for hosts), then OSPF.
func routing_table(with_ospf: bool = true) -> RoutingTable:
	var rt := RoutingTable.new()
	for n in iface_order:
		var i: Dictionary = interfaces[n]
		if i.ip.is_empty() or not is_up(i):
			continue
		var p := IPv4.prefix_from_mask(IPv4.parse(i.mask))
		rt.add(RoutingTable.route("C", i.ip, p, "", n))
		rt.add(RoutingTable.route("L", i.ip, 32, "", n))
	var connected := RoutingTable.new()
	connected.candidates = rt.candidates.duplicate()
	connected._rebuild()
	for r in static_routes:
		if not r.iface.is_empty():
			if interfaces.has(r.iface) and is_up(interfaces[r.iface]):
				rt.add(RoutingTable.route("S", IPv4.to_str(r.net), r.len, "", r.iface, 0, r.ad))
		elif not connected.lookup(IPv4.parse(r.next_hop)).is_empty():
			rt.add(RoutingTable.route("S", IPv4.to_str(r.net), r.len, r.next_hop, "", 0, r.ad))
	if type == "host" and not default_gateway.is_empty() and not connected.lookup(IPv4.parse(default_gateway)).is_empty():
		rt.add(RoutingTable.route("S", "0.0.0.0", 0, default_gateway))
	var net = network()
	if with_ospf and not ospf.is_empty() and net != null:
		for r in OspfSim.routes(net, hostname):
			rt.add(r)
	return rt

## Which inside global address would NAT give this inside local address? "" = not translated.
func nat_translate(inside_ip: String) -> String:
	if not interfaces.values().any(func(i): return i.nat == "inside") or not interfaces.values().any(func(i): return i.nat == "outside"):
		return ""
	for s in nat_static:
		if s.local == inside_ip:
			return s.global
	var ip := IPv4.parse(inside_ip)
	for r in nat_rules:
		var acl: Dictionary = acls.get(r.acl, {})
		if acl.is_empty():
			continue
		if ACL.evaluate(acl.entries, {"proto": "ip", "src": ip, "dst": 0}) != "permit":
			continue
		if not r.iface.is_empty():
			var oi: Dictionary = interfaces.get(r.iface, {})
			return oi.get("ip", "") if r.overload else ""
		if nat_pools.has(r.pool):
			return nat_pools[r.pool].start
	return ""
