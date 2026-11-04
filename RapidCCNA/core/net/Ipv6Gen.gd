class_name Ipv6Gen
extends RefCounted
## IPv6 Workshop items: compress (RFC 5952), expand, address type, /64 prefix and EUI-64.

const KINDS := ["compress", "expand", "type", "prefix", "eui64"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"expand": return _expand(rng)
		"type": return _type(rng)
		"prefix": return _prefix(rng)
		"eui64": return _eui64(rng)
	return _compress(rng)

## A global unicast 2001:db8::/32 address with zero runs and leading zeros worth compressing.
static func rand_global(rng: RandomNumberGenerator) -> PackedInt32Array:
	var h := PackedInt32Array([0x2001, 0x0db8, 0, 0, 0, 0, 0, 0])
	h[2] = [0, rng.randi_range(1, 0xff), rng.randi_range(0x100, 0xffff), 0xacad][rng.randi() % 4]
	h[3] = [0, 0, rng.randi_range(1, 0xf), rng.randi_range(0x10, 0xfff)][rng.randi() % 4]
	for i in range(4, 8):
		var roll := rng.randf()
		h[i] = 0 if roll < 0.45 else rng.randi_range(1, 0xff) if roll < 0.7 else rng.randi_range(0x100, 0xffff)
	if Array(h).slice(2).all(func(x): return x == 0):
		h[7] = rng.randi_range(1, 0xff)
	return h

static func full(h: PackedInt32Array) -> String:
	return ":".join(Array(h).map(func(x): return "%04x" % x))

static func _steps(h: PackedInt32Array) -> String:
	var no_lead := ":".join(Array(h).map(func(x): return "%x" % x))
	var short := IPv6.compress_hextets(h)
	var last := "Longest 0 run → ::  %s" % short if short.contains("::") else "No run of two or more zero groups, so no ::  %s" % short
	return "Full:            %s\nDrop leading 0s: %s\n%s" % [full(h), no_lead, last]

static func _compress(rng: RandomNumberGenerator) -> Dictionary:
	var h := rand_global(rng)
	var ans := IPv6.compress_hextets(h)
	return {"kind": "compress", "card_id": "gen.ipv6_workshop.compress", "prompt": full(h),
		"question": "Write this address in its shortest form.", "answer": ans, "placeholder": "e.g. 2001:db8::1", "wide": true,
		"hint": "Drop leading zeros in every group, then replace the longest run of all-zero groups (two or more) with :: (once only; the first run if two tie).",
		"explain": _steps(h)}

static func _expand(rng: RandomNumberGenerator) -> Dictionary:
	var h := rand_global(rng)
	return {"kind": "expand", "card_id": "gen.ipv6_workshop.expand", "prompt": IPv6.compress_hextets(h),
		"question": "Write this address in full: all 8 groups of 4 hex digits.", "answer": full(h), "placeholder": "xxxx:xxxx:...", "wide": true,
		"hint": "Count the groups that are shown; :: stands for however many all-zero groups make 8 in total. Pad every group to 4 digits.",
		"explain": _expand_steps(h)}

static func _expand_steps(h: PackedInt32Array) -> String:
	var short := IPv6.compress_hextets(h)
	if not short.contains("::"):
		return "No :: here, so just pad each group to 4 digits:\n%s" % full(h)
	var shown := short.replace("::", ":").split(":", false).size()
	return "%s shows %d group(s), so :: stands for %d all-zero groups.\n%s" % [short, shown, 8 - shown, full(h)]

const TYPE_CHOICES := ["Global unicast", "Unique local", "Link-local", "Multicast", "Loopback", "Unspecified"]

static func _type(rng: RandomNumberGenerator) -> Dictionary:
	var samples := [
		[IPv6.compress_hextets(rand_global(rng)), "Global unicast", "2000::/3 (first group 2xxx or 3xxx) is global unicast: routable on the internet."],
		["2%03x:%x::%x" % [rng.randi_range(0x400, 0xfff), rng.randi_range(1, 0xffff), rng.randi_range(1, 0xff)], "Global unicast", "Anything in 2000::/3 is global unicast."],
		["fd%02x:%x:%x::%x" % [rng.randi_range(0, 0xff), rng.randi_range(1, 0xffff), rng.randi_range(1, 0xff), rng.randi_range(1, 0xff)], "Unique local", "FC00::/7 (in practice FDxx) is unique local: private, like RFC 1918 in IPv4."],
		["fe80::%x:%xff:fe%02x:%x" % [rng.randi_range(0x200, 0xfff), rng.randi_range(0x10, 0xff), rng.randi_range(0, 0xff), rng.randi_range(0x100, 0xffff)], "Link-local", "FE80::/10 is link-local: auto-generated on every IPv6 interface and never routed."],
		["ff02::%x" % [1, 2, 5, 6, 9][rng.randi() % 5], "Multicast", "FF00::/8 is multicast. FF02:: means link-local scope (ff02::1 all nodes, ff02::2 all routers, ff02::5/6 OSPF)."],
		["ff02::1:ff%02x:%x" % [rng.randi_range(0, 0xff), rng.randi_range(0x100, 0xffff)], "Multicast", "FF02::1:FF00:0/104 is the solicited-node multicast range used by Neighbor Discovery."],
		["::1", "Loopback", "::1 is the loopback address, like 127.0.0.1."],
		["::", "Unspecified", ":: (all zeros) is the unspecified address, used as a source before an address is assigned."],
	]
	var s: Array = samples[rng.randi() % samples.size()]
	return {"kind": "type", "card_id": "gen.ipv6_workshop.type", "prompt": s[0],
		"question": "What type of IPv6 address is this?", "choices": TYPE_CHOICES,
		"answer_index": TYPE_CHOICES.find(s[1]), "answer": s[1],
		"hint": "Look at the first group: 2/3 = global, FD/FC = unique local, FE80 = link-local, FF = multicast.",
		"explain": s[2]}

static func _prefix(rng: RandomNumberGenerator) -> Dictionary:
	var h := rand_global(rng)
	for i in range(4, 8):
		if h[i] == 0:
			h[i] = rng.randi_range(1, 0xffff)
	var plen: int = [64, 64, 64, 48, 56][rng.randi() % 5]
	var addr := IPv6.compress_hextets(h)
	var net := IPv6.network(addr, plen)
	@warning_ignore("integer_division")
	return {"kind": "prefix", "card_id": "gen.ipv6_workshop.prefix", "prompt": "%s/%d" % [addr, plen],
		"question": "What is the network prefix?", "answer": "%s/%d" % [net, plen], "placeholder": "e.g. 2001:db8:1:1::/64", "wide": true,
		"plen": plen,
		"hint": "/64 keeps the first 4 groups; /48 the first 3; /56 the first 3 groups plus the first two hex digits of the 4th. Zero the rest.",
		"explain": "/%d = the first %d bits (%s).\n%s → %s/%d" % [plen, plen,
			"%d groups" % (plen / 16) if plen % 16 == 0 else "%d groups + %d bits" % [plen / 16, plen % 16], full(h), net, plen]}

static func _eui64(rng: RandomNumberGenerator) -> Dictionary:
	var b: Array = []
	for i in 6:
		b.append(rng.randi_range(0, 0xff))
	b[0] = b[0] & 0xfc   # a universal unicast MAC, so the U/L bit flip turns it on
	var mac := "%02x%02x.%02x%02x.%02x%02x" % b
	var iid := IPv6.eui64(mac)
	var pfx := "2001:db8:%x:%x" % [rng.randi_range(1, 0xffff), rng.randi_range(1, 0xff)]
	var addr := IPv6.compress("%s:%s" % [pfx, iid])
	var mac_split := "%02x%02x%02x | %02x%02x%02x" % b
	return {"kind": "eui64", "card_id": "gen.ipv6_workshop.eui64",
		"exhibit": "interface g0/0\n ipv6 address %s::/64 eui-64\n\nG0/0 MAC address: %s" % [pfx, mac],
		"question": "What IPv6 address does G0/0 get?", "answer": addr, "placeholder": "e.g. 2001:db8:1:1:...", "wide": true,
		"hint": "Split the MAC in half, insert FFFE in the middle, then flip the 7th bit of the first byte (0x02).",
		"explain": "MAC halves: %s\nInsert FFFE: %02x%02x:%02xff:fe%02x:%02x%02x\nFlip bit 7 of %02x → %02x: %s\nAddress: %s" % [
			mac_split, b[0], b[1], b[2], b[3], b[4], b[5], b[0], b[0] ^ 2, iid, addr]}

## Typed answers: compress must be exactly RFC 5952; expand must be the full form; others compare by value.
static func check(item: Dictionary, response: String) -> bool:
	var r := response.strip_edges().to_lower()
	match item.kind:
		"compress":
			return r == item.answer
		"expand":
			return r == item.answer
		"prefix":
			var parts := r.split("/")
			var want: PackedStringArray = item.answer.split("/")
			if parts.size() == 1:
				return IPv6.parse(parts[0]) == IPv6.parse(want[0]) and IPv6.is_valid(parts[0])
			return parts.size() == 2 and parts[1] == want[1] and IPv6.is_valid(parts[0]) and IPv6.parse(parts[0]) == IPv6.parse(want[0])
		"eui64":
			return IPv6.is_valid(r) and IPv6.parse(r) == IPv6.parse(item.answer)
	return Grader.same_value(item.answer, response)

## Why a typed answer is wrong in a way worth naming (shown above the worked solution).
static func parse_error(item: Dictionary, response: String) -> String:
	var r := response.strip_edges().to_lower()
	if r.is_empty() or item.kind == "type":
		return ""
	var addr := r.split("/")[0]
	if not IPv6.is_valid(addr):
		return "that isn't a valid IPv6 address (8 groups, at most one ::)."
	if item.kind == "compress" and IPv6.parse(addr) == IPv6.parse(item.answer):
		return "it's the same address, but not the shortest form (leading zeros removed, longest zero run as ::)."
	if item.kind == "expand" and IPv6.parse(addr) == IPv6.parse(item.answer):
		return "it's the same address, but the full form needs all 8 groups with 4 digits each."
	return ""
