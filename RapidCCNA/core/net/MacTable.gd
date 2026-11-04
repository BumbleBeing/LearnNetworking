class_name MacTable
extends RefCounted
## A switch's MAC address table: learn source addresses per VLAN, then forward,
## flood or filter each frame. Pure logic.

const BROADCAST := "ffff.ffff.ffff"

var ports: Dictionary = {}     # port -> {vlan:int} (access) or {trunk:true}; insertion order = port order
var entries: Dictionary = {}   # "vlan|mac" -> {mac, vlan, port}

static func create(port_defs: Dictionary) -> MacTable:
	var t := MacTable.new()
	t.ports = port_defs
	return t

func is_trunk(p: String) -> bool:
	return ports[p].get("trunk", false)

func carries(p: String, vlan: int) -> bool:
	return is_trunk(p) or int(ports[p].get("vlan", 1)) == vlan

## Port a MAC is known on in a VLAN, or "".
func lookup(mac: String, vlan: int) -> String:
	return entries.get("%d|%s" % [vlan, mac.to_lower()], {}).get("port", "")

func learn(mac: String, vlan: int, port: String) -> void:
	entries["%d|%s" % [vlan, mac.to_lower()]] = {"mac": mac.to_lower(), "vlan": vlan, "port": port}

## Processes one frame. vlan is taken from the access port (or given for tagged frames on a trunk).
## Returns {action: forward|flood|filter, out: [ports], vlan, learned: bool, moved_from: String}.
func receive(in_port: String, src: String, dst: String, vlan: int = -1) -> Dictionary:
	if not is_trunk(in_port):
		vlan = int(ports[in_port].get("vlan", 1))
	var before := lookup(src, vlan)
	learn(src, vlan, in_port)
	var res := {"vlan": vlan, "learned": before != in_port, "moved_from": before if not before.is_empty() and before != in_port else ""}
	var known := "" if dst.to_lower() == BROADCAST else lookup(dst, vlan)
	if known.is_empty():
		res.action = "flood"
		res.out = ports.keys().filter(func(p): return p != in_port and carries(p, vlan))
	elif known == in_port:
		res.action = "filter"
		res.out = []
	else:
		res.action = "forward"
		res.out = [known]
	return res

## "show mac address-table" (dynamic entries).
func show() -> String:
	var rows: Array = entries.values()
	var order: Array = ports.keys()
	rows.sort_custom(func(a, b): return a.vlan < b.vlan or (a.vlan == b.vlan and order.find(a.port) < order.find(b.port)))
	var out := PackedStringArray(["          Mac Address Table", "-------------------------------------------", "",
		"Vlan    Mac Address       Type        Ports", "----    -----------       --------    -----"])
	for r in rows:
		out.append("%4d    %-17s %-11s %s" % [r.vlan, r.mac, "DYNAMIC", r.port])
	out.append("Total Mac Addresses for this criterion: %d" % rows.size())
	return "\n".join(out)
