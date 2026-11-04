class_name EtherChannelGen
extends RefCounted
## Channel Builder items: does the channel form, the matching mode, why a member is
## suspended, and reading show etherchannel summary.

const KINDS := ["forms", "partner_mode", "mismatch", "summary"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"partner_mode": return _partner_mode(rng)
		"mismatch": return _mismatch(rng)
		"summary": return _summary(rng)
	return _forms(rng)

static func _ports(rng: RandomNumberGenerator) -> Array:
	var first := rng.randi_range(1, 3)
	return ["Gi0/%d" % first, "Gi0/%d" % (first + 1)]

static func _forms(rng: RandomNumberGenerator) -> Dictionary:
	var a: String = EtherChannel.MODES[rng.randi() % 5]
	var b: String = EtherChannel.MODES[rng.randi() % 5]
	# Same-protocol pairs are the instructive ones; keep cross-protocol pairs a minority.
	if rng.randf() < 0.6:
		var fam: Array = [EtherChannel.LACP, EtherChannel.PAGP, ["on"]][rng.randi() % 3]
		a = fam[rng.randi() % fam.size()]
		b = fam[rng.randi() % fam.size()]
	var n := EtherChannel.negotiate(a, b)
	var p := _ports(rng)
	var g := rng.randi_range(1, 6)
	var choices: Array = ["Yes, using LACP", "Yes, using PAgP", "Yes, statically (no negotiation protocol)", "No, the channel doesn't form"]
	var ans: String = choices[3]
	if n.forms:
		ans = choices[["LACP", "PAgP", "static"].find(n.protocol)]
	return {"kind": "forms", "card_id": "gen.channel_builder.forms",
		"exhibit": "SW1(config)#interface range %s - %s\nSW1(config-if-range)#channel-group %d mode %s\n\nSW2(config)#interface range %s - %s\nSW2(config-if-range)#channel-group %d mode %s" % [
			p[0], p[1].substr(4), g, a, p[0], p[1].substr(4), g, b],
		"question": "Does the EtherChannel come up?", "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "LACP: active/passive. PAgP: desirable/auto. 'on' only pairs with 'on'. At least one side must actively negotiate.",
		"explain": n.reason}

static func _partner_mode(rng: RandomNumberGenerator) -> Dictionary:
	var mine: String = ["passive", "auto", "on"][rng.randi() % 3]
	var want: String = {"passive": "active", "auto": "desirable", "on": "on"}[mine]
	var choices: Array = EtherChannel.MODES.duplicate()
	var proto := EtherChannel.protocol_of(mine)
	return {"kind": "partner_mode", "card_id": "gen.channel_builder.partner_mode",
		"exhibit": "SW1: channel-group 1 mode %s" % mine,
		"question": "Which mode on SW2 brings the channel up?", "choices": choices,
		"answer_index": choices.find(want), "answer": want,
		"hint": "A passive end (passive / auto) needs an active partner of the same protocol. 'on' needs 'on'.",
		"explain": "%s is %s; %s. %s" % [mine, proto if proto != "static" else "static (no protocol)",
			"it only works with 'on'" if mine == "on" else "only %s starts %s negotiation" % [want, proto],
			"" if mine == "on" else "%s + %s would sit waiting for each other." % [mine, mine]]}

static func _mismatch(rng: RandomNumberGenerator) -> Dictionary:
	var p := _ports(rng)
	var trunk := rng.randf() < 0.5
	var base := {"name": p[0], "speed": "auto", "duplex": "auto", "mode": "trunk" if trunk else "access",
		"vlan": 10, "native": 99, "allowed": "10,20,99"}
	var other := base.duplicate()
	other.name = p[1]
	var attrs: Array = ["speed", "duplex", "mode", "native", "allowed"] if trunk else ["speed", "duplex", "mode", "vlan"]
	var attr: String = attrs[rng.randi() % attrs.size()]
	match attr:
		"speed": other.speed = "100"
		"duplex": other.duplex = "half"
		"mode": other.mode = "access" if trunk else "trunk"
		"vlan": other.vlan = 20
		"native": other.native = 1
		"allowed": other.allowed = "10,20"
	var cfg := func(port: Dictionary, desc: String) -> String:
		var l := PackedStringArray(["interface " + port.name, " description " + desc])
		if port.mode == "trunk":
			if port.native != 1:
				l.append(" switchport trunk native vlan %d" % port.native)
			l.append(" switchport trunk allowed vlan " + port.allowed)
			l.append(" switchport mode trunk")
		else:
			l.append(" switchport access vlan %d" % port.vlan)
			l.append(" switchport mode access")
		if port.speed != "auto":
			l.append(" speed " + port.speed)
		if port.duplex != "auto":
			l.append(" duplex " + port.duplex)
		l.append(" channel-group 1 mode active")
		return "\n".join(l)
	var issues := EtherChannel.member_issues([base, other])
	var texts := {"speed": "The speed is different", "duplex": "The duplex is different",
		"mode": "One port is access and the other is trunk", "vlan": "The access VLAN is different",
		"native": "The native VLAN is different", "allowed": "The allowed VLAN list is different"}
	var pool: Array = attrs.filter(func(x): return x != attr).map(func(x): return texts[x])
	GenUtil.shuffle(rng, pool)
	var choices: Array = [texts[attr], "The descriptions are different"] + pool.slice(0, 2)
	GenUtil.shuffle(rng, choices)
	return {"kind": "mismatch", "card_id": "gen.channel_builder.mismatch",
		"exhibit": "%s\n!\n%s\n\nSW1#show etherchannel summary | include Po1\n1      Po1(SU)       LACP        %s(P)    %s(s)" % [
			cfg.call(base, "uplink A"), cfg.call(other, "uplink B"), p[0], p[1]],
		"question": "Why is %s suspended?" % p[1], "choices": choices,
		"answer_index": choices.find(texts[attr]), "answer": texts[attr],
		"hint": "Members must match on speed, duplex, switchport mode and VLANs (access VLAN, or native and allowed list on trunks). Descriptions don't matter.",
		"explain": "%s: %s is '%s', but the bundle uses '%s'. Mismatched members are suspended (s) until they match." % [
			issues[0].port, EtherChannel.ATTRS[issues[0].attr], issues[0].have, issues[0].want]}

static func _summary(rng: RandomNumberGenerator) -> Dictionary:
	var proto: String = ["LACP", "PAgP", "-"][rng.randi() % 3]
	var flags: Array = ["P", "P", "s", "I", "D"]
	if proto == "-":
		flags = ["P", "P", "s", "D"]
	var members: Array = []
	var first := rng.randi_range(1, 3)
	for i in 4:
		members.append({"port": "Gi0/%d" % (first + i), "flag": flags[rng.randi() % flags.size()]})
	members[rng.randi() % 4].flag = "P"
	var up := members.any(func(m): return m.flag == "P")
	var text := EtherChannel.show_summary([{"group": 1, "protocol": proto, "layer": "S", "up": up, "members": members}])
	var m: Dictionary = members[rng.randi() % 4]
	var choices: Array = EtherChannel.FLAG_TEXT.values()
	var ans: String = EtherChannel.FLAG_TEXT[m.flag]
	return {"kind": "summary", "card_id": "gen.channel_builder.summary", "exhibit": text,
		"question": "What is the state of %s?" % m.port, "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Read the letter in brackets after each port against the Flags legend.",
		"explain": "%s(%s): %s. Po1(S%s) = layer 2 port-channel, %s." % [m.port, m.flag, ans, "U" if up else "D", "in use" if up else "down"]}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
