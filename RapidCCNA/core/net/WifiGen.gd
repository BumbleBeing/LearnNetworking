class_name WifiGen
extends RefCounted
## Wi-Fi Channel Planner items: picking a non-overlapping 2.4 GHz channel for a new AP,
## channel overlap, bands, 802.11 standards and WLAN terms.

const KINDS := ["plan", "overlap", "band", "standard", "terms"]
const CLEAN := [1, 6, 11]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"overlap": return _overlap(rng)
		"band": return _band(rng)
		"standard": return _standard(rng)
		"terms": return _terms(rng)
	return _plan(rng)

## 2.4 GHz channels are 5 MHz apart and ~22 MHz wide: they overlap unless 5 or more apart.
static func overlaps(a: int, b: int) -> bool:
	return absi(a - b) < 5

## A 3x3 floor of AP cells; the centre (or an edge cell) is new. Neighbours use exactly two of 1/6/11.
static func _plan(rng: RandomNumberGenerator) -> Dictionary:
	var free: int = CLEAN[rng.randi() % 3]
	var used: Array = CLEAN.filter(func(c): return c != free)
	var grid: Array = []
	for r in 3:
		grid.append([0, 0, 0])
	# Fill every cell; the target's 4-neighbours draw only from `used`, and both values appear.
	var tr := 1
	var tc := rng.randi_range(0, 2)
	var nbrs: Array = []
	for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
		var r: int = tr + d[0]
		var c: int = tc + d[1]
		if r >= 0 and r < 3 and c >= 0 and c < 3:
			nbrs.append([r, c])
	for k in nbrs.size():
		grid[nbrs[k][0]][nbrs[k][1]] = used[k % 2]
	for r in 3:
		for c in 3:
			if grid[r][c] == 0 and not (r == tr and c == tc):
				grid[r][c] = CLEAN[rng.randi() % 3]
	var lines := PackedStringArray(["┌───────┬───────┬───────┐"])
	for r in 3:
		var row := "│"
		for c in 3:
			var label := "  NEW  " if r == tr and c == tc else (" ch %-2d " % grid[r][c]).rpad(7)
			row += label + "│"
		lines.append(row)
		lines.append("├───────┼───────┼───────┤" if r < 2 else "└───────┴───────┴───────┘")
	var choices: Array = ["Channel 1", "Channel 6", "Channel 11", "Channel 3"]
	var ans := "Channel %d" % free
	var nb_ch: Array = []
	for p in nbrs:
		if not grid[p[0]][p[1]] in nb_ch:
			nb_ch.append(grid[p[0]][p[1]])
	nb_ch.sort()
	return {"kind": "plan", "card_id": "gen.wifi_planner.plan",
		"exhibit": "2.4 GHz access points on one floor (each square is one AP's cell):\n" + "\n".join(lines),
		"question": "Which channel should the NEW access point use?", "choices": choices,
		"answer_index": choices.find(ans), "answer": ans,
		"hint": "Only 1, 6 and 11 don't overlap in 2.4 GHz. Pick the one no directly adjacent cell uses.",
		"explain": "The cells touching NEW use channels %s, so channel %d avoids co-channel and adjacent-channel interference. Channel 3 overlaps both 1 and 6." % [
			" and ".join(nb_ch.map(func(x): return str(x))), free]}

static func _overlap(rng: RandomNumberGenerator) -> Dictionary:
	var a := rng.randi_range(1, 11)
	var b := rng.randi_range(1, 11)
	while b == a:
		b = rng.randi_range(1, 11)
	if rng.randf() < 0.4:
		b = clampi(a + [5, -5, 6, 4, -4][rng.randi() % 5], 1, 11)
		if b == a:
			b = 11 if a < 6 else 1
	var lo: int = min(a, b)
	var hi: int = max(a, b)
	var ov := overlaps(lo, hi)
	var choices: Array = ["Yes, they overlap", "No, they don't overlap"]
	return {"kind": "overlap", "card_id": "gen.wifi_planner.overlap",
		"question": "In the 2.4 GHz band, do channels %d and %d overlap?" % [lo, hi], "choices": choices,
		"answer_index": 0 if ov else 1, "answer": choices[0 if ov else 1],
		"hint": "Channel centres are 5 MHz apart and each channel is about 22 MHz wide: channels need to be 5 apart to stay clear.",
		"explain": "Channels %d and %d are %d apart (%d MHz between centres). %s" % [lo, hi, hi - lo, (hi - lo) * 5,
			"They overlap: less than 5 channels apart." if ov else "They don't overlap: 5 or more channels apart, like 1, 6 and 11."]}

const BAND_FACTS := [
	["has only three non-overlapping 20 MHz channels", "2.4 GHz"],
	["travels further and passes through walls better", "2.4 GHz"],
	["shares its spectrum with microwave ovens and Bluetooth", "2.4 GHz"],
	["offers many more non-overlapping channels", "5 GHz"],
	["is used by 802.11a and 802.11ac", "5 GHz"],
	["is used by 802.11b and 802.11g", "2.4 GHz"],
	["can be used by 802.11n and 802.11ax", "Both 2.4 and 5 GHz"],
	["covers a smaller area per AP at the same power", "5 GHz"],
]

static func _band(rng: RandomNumberGenerator) -> Dictionary:
	var f: Array = BAND_FACTS[rng.randi() % BAND_FACTS.size()]
	var choices: Array = ["2.4 GHz", "5 GHz", "Both 2.4 and 5 GHz"]
	return {"kind": "band", "card_id": "gen.wifi_planner.band",
		"question": "Which band %s?" % f[0], "choices": choices, "answer_index": choices.find(f[1]), "answer": f[1],
		"hint": "2.4 GHz: longer range, 3 clean channels, crowded. 5 GHz: shorter range, many channels.",
		"explain": "%s %s. In short: 2.4 GHz reaches further but is crowded with 3 usable channels; 5 GHz has many channels but shorter range." % [f[1], f[0]]}

const STANDARDS := [
	["802.11b", "2.4 GHz", "11 Mbps"], ["802.11a", "5 GHz", "54 Mbps"], ["802.11g", "2.4 GHz", "54 Mbps"],
	["802.11n (Wi-Fi 4)", "2.4 and 5 GHz", "600 Mbps"], ["802.11ac (Wi-Fi 5)", "5 GHz", "6.93 Gbps"],
	["802.11ax (Wi-Fi 6/6E)", "2.4, 5 and 6 GHz", "9.6 Gbps"],
]

static func _standard(rng: RandomNumberGenerator) -> Dictionary:
	var s: Array = STANDARDS[rng.randi() % STANDARDS.size()]
	var choices: Array = ["2.4 GHz", "5 GHz", "2.4 and 5 GHz", "2.4, 5 and 6 GHz"]
	return {"kind": "standard", "card_id": "gen.wifi_planner.standard",
		"question": "Which frequency band(s) does %s use?" % s[0], "choices": choices,
		"answer_index": choices.find(s[1]), "answer": s[1],
		"hint": "b/g = 2.4, a/ac = 5, n = both, ax = 2.4/5 (and 6 GHz as Wi-Fi 6E).",
		"explain": "\n".join(STANDARDS.map(func(x): return "%-22s %-18s up to %s" % x))}

const TERMS := {
	"SSID": "The network name that clients see and join",
	"BSSID": "The MAC address that identifies one AP's radio for a WLAN",
	"BSS": "One AP and the clients associated with it",
	"ESS": "Several APs sharing an SSID so clients can roam between them",
	"IBSS (ad hoc)": "Clients talking directly to each other with no AP",
	"Repeater": "An AP that rebroadcasts another AP's signal to extend coverage",
}

static func _terms(rng: RandomNumberGenerator) -> Dictionary:
	var keys: Array = TERMS.keys()
	var k: String = keys[rng.randi() % keys.size()]
	var others := keys.filter(func(x): return x != k)
	GenUtil.shuffle(rng, others)
	var choices: Array = [k] + others.slice(0, 3)
	GenUtil.shuffle(rng, choices)
	return {"kind": "terms", "card_id": "gen.wifi_planner.terms", "prompt": TERMS[k],
		"question": "Which term is this?", "choices": choices,
		"answer_index": choices.find(k), "answer": k,
		"hint": "SSID = name, BSSID = an AP radio's MAC, BSS = one AP's cell, ESS = many APs, one SSID.",
		"explain": "\n".join(keys.map(func(x): return "%-14s %s" % [x, TERMS[x]]))}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
