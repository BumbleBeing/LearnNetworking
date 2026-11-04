class_name Discovery
extends RefCounted
## CDP and LLDP across a lab Network: who each device sees on which port.

const CDP_HOLD := 180
const LLDP_HOLD := 120
## CDP capability letters → LLDP capability codes.
const LLDP_CAP := {"R": "R", "S": "B", "H": "S", "P": "T", "W": "W"}

static func _link_up(d: Device, n: String) -> bool:
	var i: Dictionary = d.interfaces.get(n, {})
	return not i.is_empty() and not i.shutdown and i.link

## Neighbours a device learns. protocol: "cdp" or "lldp".
## Returns [{device, local, remote, platform, capability, address}].
static func neighbors(net: Network, dev: String, protocol: String) -> Array:
	var me: Device = net.devices[dev]
	var out: Array = []
	for n in me.iface_order:
		var nb := net.neighbor(dev, n)
		if nb.is_empty() or not _link_up(me, n):
			continue
		var peer: Device = net.devices[nb[0]]
		if not _link_up(peer, nb[1]):
			continue
		var mi: Dictionary = me.interfaces[n]
		var pi: Dictionary = peer.interfaces[nb[1]]
		var heard := false
		if protocol == "cdp":
			heard = me.cdp_run and mi.cdp and peer.cdp_run and pi.cdp
		else:
			heard = me.lldp_run and mi.lldp_rx and peer.lldp_run and pi.lldp_tx
		if heard:
			out.append({"device": peer.hostname, "local": n, "remote": nb[1], "platform": peer.platform,
				"capability": peer.capability, "address": _address(peer, nb[1])})
	return out

## The address a device advertises: the IP of the sending port, else its first IP (such as a management SVI).
static func _address(d: Device, port: String) -> String:
	if not d.interfaces[port].ip.is_empty():
		return d.interfaces[port].ip
	for n in d.iface_order:
		if not d.interfaces[n].ip.is_empty():
			return d.interfaces[n].ip
	return ""

## "Gig 0/1" style used in show cdp neighbors.
static func cdp_port(n: String) -> String:
	for full in Device.SHORT:
		if n.begins_with(full):
			return full.substr(0, 3) + " " + n.substr(full.length())
	return n

static func show_cdp(d: Device) -> String:
	if not d.cdp_run:
		return "% CDP is not enabled"
	return "Global CDP information:\n\tSending CDP packets every 60 seconds\n\tSending a holdtime value of 180 seconds\n\tSending CDPv2 advertisements is  enabled"

static func show_cdp_neighbors(net: Network, dev: String) -> String:
	if not net.devices[dev].cdp_run:
		return "% CDP is not enabled"
	var out := PackedStringArray([
		"Capability Codes: R - Router, T - Trans Bridge, B - Source Route Bridge",
		"                  S - Switch, H - Host, I - IGMP, r - Repeater, P - Phone,",
		"                  D - Remote, C - CVTA, M - Two-port Mac Relay", "",
		"Device ID        Local Intrfce     Holdtme    Capability  Platform  Port ID"])
	var nbrs := neighbors(net, dev, "cdp")
	for nb in nbrs:
		out.append("%-16s %-17s %-10d %-11s %-9s %s" % [nb.device, cdp_port(nb.local), CDP_HOLD - 17, nb.capability, nb.platform, cdp_port(nb.remote)])
	out.append("")
	out.append("Total cdp entries displayed : %d" % nbrs.size())
	return "\n".join(out)

static func show_cdp_detail(net: Network, dev: String) -> String:
	if not net.devices[dev].cdp_run:
		return "% CDP is not enabled"
	var blocks := PackedStringArray()
	for nb in neighbors(net, dev, "cdp"):
		var b := PackedStringArray(["-------------------------", "Device ID: " + nb.device, "Entry address(es): "])
		if not nb.address.is_empty():
			b.append("  IP address: " + nb.address)
		b.append("Platform: cisco %s,  Capabilities: %s" % [nb.platform, _cap_words(nb.capability)])
		b.append("Interface: %s,  Port ID (outgoing port): %s" % [nb.local, nb.remote])
		b.append("Holdtime : %d sec" % (CDP_HOLD - 17))
		b.append("")
		b.append("Version :")
		b.append("Cisco IOS Software, %s Software, Version 15.2(7)E" % nb.platform)
		b.append("")
		b.append("advertisement version: 2")
		b.append("Duplex: full")
		blocks.append("\n".join(b))
	blocks.append("\nTotal cdp entries displayed : %d" % neighbors(net, dev, "cdp").size())
	return "\n".join(blocks)

static func _cap_words(cap: String) -> String:
	var words := {"R": "Router", "S": "Switch", "B": "Source-Route-Bridge", "I": "IGMP", "H": "Host", "P": "Phone", "W": "Access-Point"}
	return " ".join(Array(cap.split(" ", false)).map(func(c): return words.get(c, c)))

static func show_lldp(d: Device) -> String:
	if not d.lldp_run:
		return "% LLDP is not enabled"
	return "Global LLDP Information:\n    Status: ACTIVE\n    LLDP advertisements are sent every 30 seconds\n    LLDP hold time advertised is 120 seconds\n    LLDP interface reinitialisation delay is 2 seconds"

static func show_lldp_neighbors(net: Network, dev: String) -> String:
	if not net.devices[dev].lldp_run:
		return "% LLDP is not enabled"
	var out := PackedStringArray(["Capability codes:",
		"    (R) Router, (B) Bridge, (T) Telephone, (C) DOCSIS Cable Device",
		"    (W) WLAN Access Point, (P) Repeater, (S) Station, (O) Other", "",
		"Device ID           Local Intf     Hold-time  Capability      Port ID"])
	var nbrs := neighbors(net, dev, "lldp")
	for nb in nbrs:
		var caps := PackedStringArray()
		for c in nb.capability.split(" ", false):
			if LLDP_CAP.has(c) and not LLDP_CAP[c] in caps:
				caps.append(LLDP_CAP[c])
		out.append("%-19s %-14s %-10d %-15s %s" % [nb.device, Device.short_name(nb.local), LLDP_HOLD, ",".join(caps), Device.short_name(nb.remote)])
	out.append("")
	out.append("Total entries displayed: %d" % nbrs.size())
	return "\n".join(out)
