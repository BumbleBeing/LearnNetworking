class_name MacGen
extends RefCounted
## Frame Forwarder items: forward / flood / filter decisions, the exact ports a frame
## leaves on, source learning and reading show mac address-table (VLAN-aware).

const KINDS := ["action", "ports_out", "learn", "read_table"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"ports_out": return _ports_out(rng)
		"learn": return _learn(rng)
		"read_table": return _read_table(rng)
	return _action(rng)

## Six access ports in VLANs 10/20 (both always used) plus a Gi0/1 trunk; one PC per access port.
static func make_switch(rng: RandomNumberGenerator) -> Dictionary:
	var defs := {}
	var pcs: Array = []
	var vlans: Array = [10, 20, 10, 20]
	for i in 2:
		vlans.append([10, 20][rng.randi() % 2])
	GenUtil.shuffle(rng, vlans)
	var used := {}
	for i in 6:
		var port := "Fa0/%d" % (i + 1)
		defs[port] = {"vlan": vlans[i]}
		var tail := rng.randi_range(0x1000, 0xfffe)
		while used.has(tail):
			tail = rng.randi_range(0x1000, 0xfffe)
		used[tail] = true
		pcs.append({"name": "PC%d" % (i + 1), "port": port, "vlan": vlans[i], "mac": "0050.7966.%04x" % tail})
	defs["Gi0/1"] = {"trunk": true}
	return {"table": MacTable.create(defs), "pcs": pcs}

static func legend(pcs: Array) -> String:
	var out := PackedStringArray(["Host  Port   VLAN  MAC address", "----  -----  ----  --------------"])
	for p in pcs:
		out.append("%-5s %-6s %-5d %s" % [p.name, p.port, p.vlan, p.mac])
	out.append("Gi0/1 is an 802.1Q trunk to SW2 (all VLANs allowed).")
	return "\n".join(out)

static func _other_same_vlan(rng: RandomNumberGenerator, pcs: Array, pc: Dictionary) -> Dictionary:
	var same := pcs.filter(func(p): return p.vlan == pc.vlan and p.name != pc.name)
	return same[rng.randi() % same.size()]

static func _warm(rng: RandomNumberGenerator, sw: Dictionary, n: int) -> Array:
	var learned: Array = []
	var pcs: Array = sw.pcs.duplicate()
	GenUtil.shuffle(rng, pcs)
	for p in pcs.slice(0, n):
		sw.table.learn(p.mac, p.vlan, p.port)
		learned.append(p)
	return learned

static func _action(rng: RandomNumberGenerator) -> Dictionary:
	var sw := make_switch(rng)
	var learned := _warm(rng, sw, rng.randi_range(2, 5))
	var t: MacTable = sw.table
	var src: Dictionary = sw.pcs[rng.randi() % 6]
	var dst := _other_same_vlan(rng, sw.pcs, src)
	var dst_mac: String = dst.mac
	var in_port: String = src.port
	var roll := rng.randf()
	var what := "%s (%s) sends a frame to %s (%s)" % [src.name, src.mac, dst.name, dst.mac]
	if roll < 0.2:
		dst_mac = MacTable.BROADCAST
		what = "%s (%s) sends a broadcast (ffff.ffff.ffff)" % [src.name, src.mac]
	elif roll < 0.35:
		# A frame for a host learned on the same port (e.g. through a hub or a phone): filtered.
		t.learn(dst.mac, src.vlan, src.port)
		what = "A frame from %s (%s) to %s arrives on %s" % [src.name, src.mac, dst.mac, src.port]
	var table_before := t.show()
	var r := t.receive(in_port, src.mac, dst_mac)
	var choices: Array = [
		"Forwards it out %s only" % (r.out[0] if r.action == "forward" else dst.port),
		"Floods it out every other port in VLAN %d, including the trunk" % r.vlan,
		"Floods it out every port except %s, in every VLAN" % in_port,
		"Filters it: the destination is on the port it arrived on",
	]
	var ans: String = choices[{"forward": 0, "flood": 1, "filter": 3}[r.action]]
	var why: String = {"forward": "%s is in the table for VLAN %d on %s, so it's forwarded out that port only." % [dst_mac, r.vlan, r.out[0] if r.out.size() > 0 else ""],
		"flood": ("Broadcasts are always flooded" if dst_mac == MacTable.BROADCAST else "%s isn't in the table for VLAN %d (unknown unicast)" % [dst_mac, r.vlan]) + ", so it's flooded out every port in VLAN %d except the one it came in on: %s." % [r.vlan, ", ".join(r.out)],
		"filter": "The table maps %s to %s, the port the frame arrived on, so the switch drops it." % [dst_mac, in_port]}[r.action]
	return {"kind": "action", "card_id": "gen.frame_forwarder.action",
		"exhibit": "%s\n\nSW1#show mac address-table\n%s" % [legend(sw.pcs), table_before],
		"question": what + ". What does SW1 do?", "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Look the destination MAC up in the table for the frame's VLAN. Known → one port. Unknown or broadcast → flood within the VLAN. Same port → filter.",
		"explain": why + "\nSW1 also learns (or refreshes) %s on %s." % [src.mac, in_port]}

## Parses a typed port list ("fa0/2, fa0/4 gi0/1", "none") into canonical short names.
static func parse_ports(text: String) -> Array:
	var t := text.strip_edges().to_lower()
	if t in ["none", "-", "no ports", "nothing"]:
		return []
	var out: Array = []
	for tok in t.replace(",", " ").replace(";", " ").split(" ", false):
		var c := Device.canon_iface(tok)
		if c.is_empty():
			return ["?"]
		out.append(Device.short_name(c))
	out.sort()
	return out

static func _ports_out(rng: RandomNumberGenerator) -> Dictionary:
	var sw := make_switch(rng)
	var t: MacTable = sw.table
	var src: Dictionary = sw.pcs[rng.randi() % 6]
	var dst := _other_same_vlan(rng, sw.pcs, src)
	# A short conversation from an empty table; ask about the last frame.
	var frames: Array = [[src, dst]]
	if rng.randf() < 0.6:
		frames.append([dst, src])
	if rng.randf() < 0.5:
		var third: Dictionary = sw.pcs[rng.randi() % 6]
		frames.append([third, _other_same_vlan(rng, sw.pcs, third)])
	var lines := PackedStringArray()
	var r := {}
	for i in frames.size():
		var f: Array = frames[i]
		lines.append("%d. %s → %s" % [i + 1, f[0].name, f[1].name])
		r = t.receive(f[0].port, f[0].mac, f[1].mac)
	var ans: String = ", ".join(r.out) if r.out.size() > 0 else "none"
	var last: Array = frames[-1]
	return {"kind": "ports_out", "card_id": "gen.frame_forwarder.ports_out",
		"exhibit": "%s\n\nSW1's MAC table starts empty. These unicast frames are sent in order:\n%s" % [legend(sw.pcs), "\n".join(lines)],
		"question": "Out of which ports does SW1 send frame %d? (list them, or 'none')" % frames.size(),
		"answer": ans, "placeholder": "e.g. fa0/2, gi0/1", "wide": true,
		"hint": "Track what SW1 has learned from the source addresses of earlier frames. Unknown destinations flood within the VLAN, including the trunk.",
		"explain": "Frame %d (%s → %s, VLAN %d): %s.\nTable afterwards:\n%s" % [frames.size(), last[0].name, last[1].name, r.vlan,
			"%s was already learned, so it goes out %s only" % [last[1].name, r.out[0]] if r.action == "forward" else "%s hasn't sent anything yet, so the frame floods out %s" % [last[1].name, ans],
			t.show()]}

static func _learn(rng: RandomNumberGenerator) -> Dictionary:
	var sw := make_switch(rng)
	var t: MacTable = sw.table
	var src: Dictionary = sw.pcs[rng.randi() % 6]
	var dst := _other_same_vlan(rng, sw.pcs, src)
	var moved := rng.randf() < 0.35
	var in_port: String = src.port
	if moved:
		# The host was learned on its old port and has since moved to a free one.
		t.learn(src.mac, src.vlan, src.port)
		in_port = "Fa0/%d" % rng.randi_range(7, 12)
		t.ports[in_port] = {"vlan": src.vlan}
	var before := t.show()
	t.receive(in_port, src.mac, dst.mac)
	var choices: Array = [
		"%s on %s" % [src.mac, in_port],
		"%s on %s" % [dst.mac, in_port],
		"%s on %s" % [dst.mac, dst.port],
		"Nothing; switches learn only from replies",
	]
	if moved:
		choices[3] = "%s stays on %s" % [src.mac, src.port]
	var ans: String = choices[0]
	var choices_shuffled := choices.duplicate()
	GenUtil.shuffle(rng, choices_shuffled)
	return {"kind": "learn", "card_id": "gen.frame_forwarder.learn",
		"exhibit": "SW1#show mac address-table\n%s\n\nA frame from %s to %s arrives on %s (VLAN %d)." % [before, src.mac, dst.mac, in_port, src.vlan],
		"question": "What does SW1 learn from this frame?", "choices": choices_shuffled,
		"answer_index": choices_shuffled.find(ans), "answer": ans,
		"hint": "Switches learn the SOURCE MAC address and the port it arrived on.",
		"explain": "Source %s, ingress %s → table entry %s on %s.%s" % [src.mac, in_port, src.mac, in_port,
			" The old entry on %s is replaced: the host moved." % src.port if moved else ""]}

static func _read_table(rng: RandomNumberGenerator) -> Dictionary:
	var sw := make_switch(rng)
	var t: MacTable = sw.table
	_warm(rng, sw, 4)
	# Hosts behind the trunk, learned on Gi0/1.
	var remote: Array = []
	for i in 3:
		var r := {"name": "PC%d" % (7 + i), "vlan": [10, 20][rng.randi() % 2], "mac": "000c.29%02x.%04x" % [rng.randi_range(0x10, 0xff), rng.randi_range(0x1000, 0xffff)]}
		t.learn(r.mac, r.vlan, "Gi0/1")
		remote.append(r)
	var target: Dictionary = (sw.pcs + remote)[rng.randi() % 9]
	var vlan: int = target.vlan
	var trick := rng.randf() < 0.3
	if trick:
		vlan = 30 - target.vlan   # the other VLAN: 10 <-> 20
	var known := t.lookup(target.mac, vlan)
	var anywhere := t.lookup(target.mac, target.vlan)
	var choices: Array = ["Fa0/1", "Fa0/2", "Fa0/3", "Fa0/4", "Fa0/5", "Fa0/6", "Gi0/1"]
	var flood := "Floods it (no entry for that MAC in VLAN %d)" % vlan
	var keep: Array = [known] if not known.is_empty() else []
	var others := choices.filter(func(c): return c != known)
	GenUtil.shuffle(rng, others)
	choices = keep + others.slice(0, 3 - keep.size() + (1 if known.is_empty() else 0))
	choices.sort()
	choices.append(flood)
	var ans: String = known if not known.is_empty() else flood
	return {"kind": "read_table", "card_id": "gen.frame_forwarder.read_table",
		"exhibit": "SW1#show mac address-table\n" + t.show(),
		"question": "A frame for %s arrives on a port in VLAN %d. Where does SW1 send it?" % [target.mac, vlan], "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Entries are per VLAN: look for the MAC address in the frame's VLAN only.",
		"explain": ("VLAN %d has %s on %s.%s" % [vlan, target.mac, known, " Many MACs on one port (like Gi0/1 here) usually means another switch is behind it." if known == "Gi0/1" else ""]) if not known.is_empty()
			else ("%s is only known in VLAN %d. A lookup in VLAN %d misses, so the frame is flooded in VLAN %d." % [target.mac, target.vlan, vlan, vlan] if not anywhere.is_empty()
			else "%s isn't in the table (that host hasn't sent anything yet), so the frame is flooded in VLAN %d." % [target.mac, vlan])}

static func check(item: Dictionary, response: String) -> bool:
	if item.kind == "ports_out":
		return parse_ports(response) == parse_ports(item.answer)
	return Grader.same_value(item.answer, response)
