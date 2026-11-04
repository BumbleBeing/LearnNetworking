class_name Binary
extends RefCounted
## Octet conversions (decimal / binary / hex) and Bit Flipper item generation.

const PLACE := [128, 64, 32, 16, 8, 4, 2, 1]
const KINDS := ["dec_to_bin", "bin_to_dec", "dec_to_hex", "hex_to_dec"]
const MASK_VALUES := [0, 128, 192, 224, 240, 248, 252, 254, 255]

static func to_bin8(n: int) -> String:
	var s := ""
	for p in PLACE:
		s += "1" if n & p else "0"
	return s

static func spaced(bin8: String) -> String:
	return bin8.substr(0, 4) + " " + bin8.substr(4)

static func to_hex(n: int) -> String:
	return "%02X" % n

## Parsers return -1 when the input is not a valid octet in that base.
static func parse_bin(s: String) -> int:
	s = s.replace(" ", "").strip_edges()
	if s.is_empty() or s.length() > 8 or not s.lstrip("01").is_empty():
		return -1
	var v := 0
	for ch in s:
		v = (v << 1) | (1 if ch == "1" else 0)
	return v

static func parse_dec(s: String) -> int:
	s = s.strip_edges()
	if s.is_empty() or s.length() > 3 or not s.lstrip("0123456789").is_empty():
		return -1
	var v := s.to_int()
	return v if v <= 255 else -1

static func parse_hex(s: String) -> int:
	s = s.strip_edges().to_lower()
	if s.begins_with("0x"):
		s = s.substr(2)
	if s.is_empty() or s.length() > 2 or not s.is_valid_hex_number(false):
		return -1
	return s.hex_to_int()

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	var value: int = MASK_VALUES[rng.randi() % MASK_VALUES.size()] if rng.randf() < 0.4 else rng.randi_range(0, 255)
	var prompt := ""
	var answer := ""
	match kind:
		"dec_to_bin":
			prompt = str(value)
			answer = spaced(to_bin8(value))
		"bin_to_dec":
			prompt = spaced(to_bin8(value))
			answer = str(value)
		"dec_to_hex":
			prompt = str(value)
			answer = "0x" + to_hex(value)
		"hex_to_dec":
			prompt = "0x" + to_hex(value)
			answer = str(value)
	return {"kind": kind, "value": value, "prompt": prompt, "answer": answer, "card_id": "gen.bit_flipper." + kind}

static func check(item: Dictionary, response: String) -> bool:
	match item.kind:
		"dec_to_bin": return parse_bin(response) == item.value
		"dec_to_hex": return parse_hex(response) == item.value
		_: return parse_dec(response) == item.value

static func explain(item: Dictionary) -> String:
	var v: int = item.value
	var parts := PackedStringArray()
	for p in PLACE:
		if v & p:
			parts.append(str(p))
	var sum := " + ".join(parts) if parts.size() > 0 else "0"
	var bin := to_bin8(v)
	return "%d = %s  →  %s  →  %s %s = 0x%s" % [v, sum, spaced(bin), bin.substr(0, 4), bin.substr(4), to_hex(v)]
