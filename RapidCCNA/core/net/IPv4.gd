class_name IPv4
extends RefCounted
## IPv4 address math on 32-bit ints. Pure functions; no UI.

const ALL := 0xFFFFFFFF

## Dotted-decimal string -> int, or -1 if invalid.
static func parse(s: String) -> int:
	var parts := s.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var v := 0
	for p in parts:
		if p.is_empty() or p.length() > 3 or not p.lstrip("0123456789").is_empty():
			return -1
		var n := p.to_int()
		if n > 255:
			return -1
		v = (v << 8) | n
	return v

static func to_str(v: int) -> String:
	return "%d.%d.%d.%d" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]

static func mask(prefix: int) -> int:
	if prefix <= 0:
		return 0
	return (ALL << (32 - prefix)) & ALL

## Contiguous mask -> prefix length, or -1 if not a valid mask.
static func prefix_from_mask(m: int) -> int:
	for p in range(0, 33):
		if mask(p) == m:
			return p
	return -1

static func wildcard(prefix: int) -> int:
	return ~mask(prefix) & ALL

static func network(ip: int, prefix: int) -> int:
	return ip & mask(prefix)

static func broadcast(ip: int, prefix: int) -> int:
	return network(ip, prefix) | wildcard(prefix)

static func first_host(ip: int, prefix: int) -> int:
	if prefix >= 31:
		return network(ip, prefix)
	return network(ip, prefix) + 1

static func last_host(ip: int, prefix: int) -> int:
	if prefix >= 31:
		return broadcast(ip, prefix)
	return broadcast(ip, prefix) - 1

## Usable hosts; /31 = 2 (RFC 3021 point-to-point), /32 = 1.
static func usable_hosts(prefix: int) -> int:
	if prefix == 32:
		return 1
	if prefix == 31:
		return 2
	return (1 << (32 - prefix)) - 2

## The "interesting" octet (0-based) and the block size within it.
static func block_info(prefix: int) -> Dictionary:
	var idx := clampi((prefix - 1) / 8, 0, 3)
	var mask_octet := (mask(prefix) >> (8 * (3 - idx))) & 255
	return {"octet": idx, "block": 256 - mask_octet}

static func octet(ip: int, idx: int) -> int:
	return (ip >> (8 * (3 - idx))) & 255
