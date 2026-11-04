class_name EtherChannel
extends RefCounted
## EtherChannel negotiation (LACP, PAgP, static on) and member consistency. Pure logic.

const MODES := ["active", "passive", "desirable", "auto", "on"]
const LACP := ["active", "passive"]
const PAGP := ["desirable", "auto"]

static func protocol_of(mode: String) -> String:
	if mode in LACP:
		return "LACP"
	if mode in PAGP:
		return "PAgP"
	return "static" if mode == "on" else ""

## Do two ends with these channel-group modes form a channel? {forms, protocol, reason}
static func negotiate(a: String, b: String) -> Dictionary:
	var pa := protocol_of(a)
	var pb := protocol_of(b)
	if pa == "static" or pb == "static":
		if pa == pb:
			return {"forms": true, "protocol": "static", "reason": "Both ends are 'on': the channel is forced up with no negotiation protocol."}
		return {"forms": false, "protocol": "", "reason": "'on' doesn't negotiate, so it only works with 'on' at the other end."}
	if pa != pb:
		return {"forms": false, "protocol": "", "reason": "%s (%s) and %s (%s) are different protocols; they can't negotiate with each other." % [a, pa, b, pb]}
	var passive_mode: String = "passive" if pa == "LACP" else "auto"
	if a == passive_mode and b == passive_mode:
		return {"forms": false, "protocol": "", "reason": "Both ends are %s: each waits for the other to start, so nothing is negotiated." % passive_mode}
	return {"forms": true, "protocol": pa, "reason": "%s + %s: at least one end actively negotiates %s." % [a, b, pa]}

const ATTRS := {
	"speed": "speed", "duplex": "duplex", "mode": "switchport mode",
	"vlan": "access VLAN", "native": "trunk native VLAN", "allowed": "trunk allowed VLANs",
}

## Settings that must match on every member port. ports: [{name, speed, duplex, mode, vlan, native, allowed}].
## Returns [{port, attr, have, want}] for each port that differs from the first one.
static func member_issues(ports: Array) -> Array:
	var out: Array = []
	if ports.is_empty():
		return out
	var ref: Dictionary = ports[0]
	for p in ports.slice(1):
		for k in ATTRS:
			if k in ["vlan"] and ref.get("mode", "") == "trunk":
				continue
			if k in ["native", "allowed"] and ref.get("mode", "") != "trunk":
				continue
			if str(p.get(k, "")) != str(ref.get(k, "")):
				out.append({"port": p.name, "attr": k, "have": str(p.get(k, "")), "want": str(ref.get(k, ""))})
	return out

const FLAG_TEXT := {
	"P": "Bundled in the port-channel", "s": "Suspended (its settings don't match the bundle)",
	"I": "Stand-alone (no channel negotiated, so it forwards as a normal port)", "D": "Down",
}

## "show etherchannel summary". groups: [{group, protocol, layer ("S"/"R"), up, members: [{port, flag}]}]
static func show_summary(groups: Array) -> String:
	var out := PackedStringArray([
		"Flags:  D - down        P - bundled in port-channel",
		"        I - stand-alone s - suspended",
		"        H - Hot-standby (LACP only)",
		"        R - Layer3      S - Layer2",
		"        U - in use      N - not in use, no aggregation",
		"",
		"Number of channel-groups in use: %d" % groups.size(),
		"Number of aggregators:           %d" % groups.size(),
		"",
		"Group  Port-channel  Protocol    Ports",
		"------+-------------+-----------+-----------------------------------------------"])
	for g in groups:
		var po := "Po%d(%s%s)" % [int(g.group), g.get("layer", "S"), "U" if g.up else "D"]
		var proto: String = g.protocol if g.protocol in ["LACP", "PAgP"] else "-"
		var ports := PackedStringArray()
		for m in g.members:
			ports.append(("%s(%s)" % [m.port, m.flag]).rpad(12))
		out.append("%-6d %-13s %-11s %s" % [int(g.group), po, proto, "".join(ports).strip_edges()])
	return "\n".join(out)
