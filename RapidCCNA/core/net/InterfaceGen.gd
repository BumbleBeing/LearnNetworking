class_name InterfaceGen
extends RefCounted
## Interface Doctor items: copper cable types, media by distance, autonegotiation
## fallback and diagnosing show interfaces output.

const KINDS := ["cable", "media", "autoneg", "diagnose"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"media": return _media(rng)
		"autoneg": return _autoneg(rng)
		"diagnose": return _diagnose(rng)
	return _cable(rng)

## Devices that transmit on pins 1,2 (MDI: PC, router, AP, server) or 3,6 (MDI-X: switch, hub).
const MDI := {"PC": "MDI", "router": "MDI", "server": "MDI", "access point": "MDI", "switch": "MDI-X", "hub": "MDI-X"}
const CABLES := ["Straight-through", "Crossover", "Rollover (console)", "Single-mode fiber"]

static func _cable(rng: RandomNumberGenerator) -> Dictionary:
	var names: Array = MDI.keys()
	var a: String = names[rng.randi() % names.size()]
	var b: String = names[rng.randi() % names.size()]
	var console := rng.randf() < 0.12
	var ans: String
	var why: String
	var q: String
	if console:
		q = "You connect a laptop's serial/USB adapter to the console port of a %s. Which cable?" % ["router", "switch"][rng.randi() % 2]
		ans = CABLES[2]
		why = "Console ports use a rollover (console) cable: the pins are reversed end to end. It carries management, not Ethernet."
	else:
		q = "Without Auto-MDIX, which copper cable connects a %s to a %s?" % [a, b]
		var same: bool = MDI[a] == MDI[b]
		ans = CABLES[1] if same else CABLES[0]
		why = "A %s is %s and a %s is %s. %s" % [a, MDI[a], b, MDI[b],
			"Like devices (both transmit on the same pins) need a crossover." if same else "Unlike devices use a straight-through cable."]
		why += "\nRouters, PCs, servers and APs transmit on pins 1,2; switches and hubs on 3,6. Auto-MDIX (on most modern ports) fixes either cable automatically."
	return {"kind": "cable", "card_id": "gen.interface_doctor.cable", "question": q, "choices": CABLES,
		"answer_index": CABLES.find(ans), "answer": ans,
		"hint": "Group the ends: PC/router/server/AP vs switch/hub. Same group → crossover. Different → straight-through.",
		"explain": why}

const MEDIA := ["Cat 6 UTP copper", "Multimode fiber", "Single-mode fiber", "Wireless bridge only"]

static func _media(rng: RandomNumberGenerator) -> Dictionary:
	var cases := [
		[rng.randi_range(20, 95), 0, "UTP copper reaches 100 m, and it's the cheapest option."],
		[rng.randi_range(150, 400), 1, "Past 100 m copper won't do. Multimode fiber (LED/VCSEL, wide core) covers a few hundred metres within a campus more cheaply than single-mode."],
		[rng.randi_range(2, 40) * 1000, 2, "Kilometres need single-mode fiber: a narrow core and a laser, good for 10 km and more."],
	]
	var c: Array = cases[rng.randi() % cases.size()]
	var dist := "%d m" % c[0] if c[0] < 1000 else "%d km" % (c[0] / 1000)
	return {"kind": "media", "card_id": "gen.interface_doctor.media",
		"question": "Two switches must be linked at 1 Gbps across %s. What's the most cost-effective cable that works?" % dist,
		"choices": MEDIA, "answer_index": c[1], "answer": MEDIA[c[1]],
		"hint": "UTP: up to 100 m. Multimode fiber: hundreds of metres. Single-mode fiber: kilometres.",
		"explain": c[2]}

const NEG := ["1000 Mbps, full duplex", "100 Mbps, full duplex", "100 Mbps, half duplex", "10 Mbps, half duplex"]

static func _autoneg(rng: RandomNumberGenerator) -> Dictionary:
	var case_ := rng.randi() % 3
	var q: String
	var ans: String
	var why: String
	match case_:
		0:
			q = "SW1 Fa0/1 is set to 'speed 100' and 'duplex full' (autonegotiation off). The PC's 10/100 NIC is left on auto. What does the PC end up using?"
			ans = NEG[2]
			why = "With autonegotiation off at the other end, the PC can still sense the speed (100 Mbps) but can't learn the duplex, so a 10/100 NIC falls back to half duplex. Result: a duplex mismatch (late collisions on the PC, CRC errors and runts on the switch)."
		1:
			q = "Both ends are on auto. SW1's port is 10/100/1000 and the PC's NIC is 10/100. What do they settle on?"
			ans = NEG[1]
			why = "Autonegotiation picks the best common setting: 100 Mbps, full duplex."
		_:
			q = "SW1 Gi0/2 is set to 'speed 10' and 'duplex half'. The PC's NIC is on auto. What does the PC use?"
			ans = NEG[3]
			why = "The PC senses 10 Mbps. Without negotiation it assumes half duplex at 10/100, which happens to match here."
	return {"kind": "autoneg", "card_id": "gen.interface_doctor.autoneg", "question": q, "choices": NEG,
		"answer_index": NEG.find(ans), "answer": ans,
		"hint": "If autonegotiation fails, a port senses the speed. Duplex defaults to half at 10 and 100 Mbps, full at 1000 Mbps.",
		"explain": why}

const DIAG := {
	"admin": "Someone shut the interface down",
	"nolink": "No physical link: cable unplugged, broken or the far end is down",
	"half_here": "Duplex mismatch: this side runs half duplex",
	"half_far": "Duplex mismatch: the far end runs half duplex",
	"cable": "A damaged cable or interference",
	"errdis": "A security feature err-disabled the port",
}

static func _show(name: String, status: String, proto: String, extra: String, duplex: String, speed: String, c: Dictionary) -> String:
	var mac := "0019.e8a1.1c%02d" % name.right(1).to_int()
	return "\n".join([
		"%s is %s, line protocol is %s%s" % [name, status, proto, extra],
		"  Hardware is Fast Ethernet, address is %s (bia %s)" % [mac, mac],
		"  %s, %s, media type is 10/100BaseTX" % [duplex, speed],
		"     %d packets input, %d bytes, 0 no buffer" % [c.pin, c.pin * 112],
		"     %d runts, 0 giants, 0 throttles" % c.runts,
		"     %d input errors, %d CRC, 0 frame, 0 overrun, 0 ignored" % [c.crc + c.runts, c.crc],
		"     %d packets output, %d bytes, 0 underruns" % [c.pout, c.pout * 96],
		"     0 output errors, %d collisions, 1 interface resets" % c.coll,
		"     %d late collision, 0 deferred" % c.late])

static func _diagnose(rng: RandomNumberGenerator) -> Dictionary:
	var key: String = DIAG.keys()[rng.randi() % DIAG.size()]
	var n := rng.randi_range(1, 9)
	var name := "FastEthernet0/%d" % n
	var c := {"pin": rng.randi_range(50000, 900000), "pout": rng.randi_range(50000, 900000), "runts": 0, "crc": 0, "coll": 0, "late": 0}
	var exhibit := ""
	var why := ""
	match key:
		"admin":
			c.pin = 0
			c.pout = 0
			exhibit = _show(name, "administratively down", "down", " (disabled)", "Auto-duplex", "Auto-speed", c)
			why = "'administratively down' always means the shutdown command. Fix: no shutdown."
		"nolink":
			exhibit = _show(name, "down", "down", " (notconnect)", "Auto-duplex", "Auto-speed", c)
			why = "down/down (notconnect) is layer 1: no signal. Check the cable and the device at the other end."
		"half_here":
			c.coll = rng.randi_range(300, 3000)
			c.late = rng.randi_range(40, 400)
			exhibit = _show(name, "up", "up", " (connected)", "Half-duplex", "100Mb/s", c) + "\n\nFar end: Full-duplex, 100Mb/s"
			why = "Late collisions only happen on a half-duplex port whose partner is sending in full duplex. Set both ends to auto (or both to full)."
		"half_far":
			c.runts = rng.randi_range(100, 900)
			c.crc = rng.randi_range(800, 6000)
			exhibit = _show(name, "up", "up", " (connected)", "Full-duplex", "100Mb/s", c) + "\n\nFar end: Half-duplex, 100Mb/s, %d late collisions" % rng.randi_range(40, 400)
			why = "The full-duplex side sees runts and CRC errors (frames the half-duplex side cut off when it 'detected' a collision). The far end is half duplex: make both ends match."
		"cable":
			c.crc = rng.randi_range(800, 6000)
			exhibit = _show(name, "up", "up", " (connected)", "Full-duplex", "100Mb/s", c) + "\n\nFar end: Full-duplex, 100Mb/s, no collisions"
			why = "Rising CRC errors with matching duplex and no collisions point at layer 1: a damaged or too-long cable, or electrical interference near it. Replace or reroute the cable."
		"errdis":
			exhibit = _show(name, "down", "down", " (err-disabled)", "Auto-duplex", "Auto-speed", c) + "\n\n%%PM-4-ERR_DISABLE: psecure-violation error detected on Fa0/%d, putting Fa0/%d in err-disable state" % [n, n]
			why = "err-disabled means a feature shut the port: here a port security violation (BPDU Guard does the same). Remove the cause, then shutdown / no shutdown."
	var others: Array = DIAG.keys().filter(func(k): return k != key)
	GenUtil.shuffle(rng, others)
	var choices: Array = [DIAG[key]] + others.slice(0, 3).map(func(k): return DIAG[k])
	GenUtil.shuffle(rng, choices)
	return {"kind": "diagnose", "card_id": "gen.interface_doctor.diagnose", "exhibit": "SW1#show interfaces %s\n%s" % [Device.short_name(name).to_lower(), exhibit],
		"question": "What's the most likely problem?", "choices": choices,
		"answer_index": choices.find(DIAG[key]), "answer": DIAG[key],
		"hint": "Read the first line (status/protocol and the reason in brackets), then the duplex, then which counters are rising.",
		"explain": why}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
