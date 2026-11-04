class_name IPv6
extends RefCounted
## IPv6 parsing, RFC 5952 compression, address types and EUI-64.
## Addresses are PackedInt32Array of 8 hextets (empty array = invalid).

static func parse(s: String) -> PackedInt32Array:
	s = s.strip_edges().to_lower()
	var out := PackedInt32Array()
	if s.is_empty() or s.count("::") > 1 or s.contains(":::"):
		return out
	var head: PackedStringArray = []
	var tail: PackedStringArray = []
	if s.contains("::"):
		var halves := s.split("::")
		if not halves[0].is_empty():
			head = halves[0].split(":")
		if not halves[1].is_empty():
			tail = halves[1].split(":")
		if head.size() + tail.size() > 7:
			return out
	else:
		head = s.split(":")
		if head.size() != 8:
			return out
	var groups: Array = []
	for h in head:
		groups.append(h)
	if s.contains("::"):
		for i in 8 - head.size() - tail.size():
			groups.append("0")
	for t in tail:
		groups.append(t)
	for g in groups:
		if g.is_empty() or g.length() > 4 or not g.is_valid_hex_number(false):
			return PackedInt32Array()
		out.append(g.hex_to_int())
	return out

static func is_valid(s: String) -> bool:
	return parse(s).size() == 8

## Full form: 2001:0db8:0000:...
static func expand(s: String) -> String:
	var h := parse(s)
	if h.size() != 8:
		return ""
	return ":".join(Array(h).map(func(x): return "%04x" % x))

## RFC 5952 compressed form.
static func compress_hextets(h: PackedInt32Array) -> String:
	var best_start := -1
	var best_len := 0
	var i := 0
	while i < 8:
		if h[i] == 0:
			var j := i
			while j < 8 and h[j] == 0:
				j += 1
			if j - i > best_len:
				best_start = i
				best_len = j - i
			i = j
		else:
			i += 1
	var parts := Array(h).map(func(x): return "%x" % x)
	if best_len < 2:
		return ":".join(parts)
	var left := ":".join(parts.slice(0, best_start))
	var right := ":".join(parts.slice(best_start + best_len))
	return left + "::" + right

static func compress(s: String) -> String:
	var h := parse(s)
	return compress_hextets(h) if h.size() == 8 else ""

static func address_type(s: String) -> String:
	var h := parse(s)
	if h.size() != 8:
		return "invalid"
	if Array(h).all(func(x): return x == 0):
		return "unspecified"
	if Array(h.slice(0, 7)).all(func(x): return x == 0) and h[7] == 1:
		return "loopback"
	if (h[0] & 0xffc0) == 0xfe80:
		return "link-local"
	if (h[0] & 0xfe00) == 0xfc00:
		return "unique local"
	if (h[0] & 0xff00) == 0xff00:
		return "multicast"
	if (h[0] & 0xe000) == 0x2000:
		return "global unicast"
	return "other"

## Network portion (prefix) of an address, compressed.
static func network(s: String, prefix: int) -> String:
	var h := parse(s)
	if h.size() != 8:
		return ""
	for i in 8:
		var bits := clampi(prefix - i * 16, 0, 16)
		var m := (0xffff << (16 - bits)) & 0xffff if bits > 0 else 0
		h[i] = h[i] & m
	return compress_hextets(h)

## Modified EUI-64 interface ID from a MAC (any common notation), e.g. "021a:2bff:fe3c:4d5e".
static func eui64(mac: String) -> String:
	var hex := ""
	for ch in mac.to_lower():
		if "0123456789abcdef".contains(ch):
			hex += ch
	if hex.length() != 12:
		return ""
	var b: Array = []
	for i in 6:
		b.append(hex.substr(i * 2, 2).hex_to_int())
	b[0] = b[0] ^ 0x02
	var bytes: Array = [b[0], b[1], b[2], 0xff, 0xfe, b[3], b[4], b[5]]
	var groups := PackedStringArray()
	for i in 4:
		groups.append("%x" % ((bytes[i * 2] << 8) | bytes[i * 2 + 1]))
	return ":".join(groups)
