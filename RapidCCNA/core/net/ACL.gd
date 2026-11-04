class_name ACL
extends RefCounted
## IOS access-list entries: parse, evaluate top-down with implicit deny, compare, render.
## Entry: {action, proto, src, src_wc, src_port, dst, dst_wc, dst_port, standard}
## Ports are -1 when not specified. Packet: {proto, src, dst, sport, dport} (ints).

const ANY_WC := 0xFFFFFFFF
const PORTS := {"ftp-data": 20, "ftp": 21, "ssh": 22, "telnet": 23, "smtp": 25, "domain": 53,
	"tftp": 69, "www": 80, "http": 80, "pop3": 110, "ntp": 123, "snmp": 161, "https": 443, "syslog": 514}
const PROTOS := ["ip", "tcp", "udp", "icmp"]

static func is_standard_number(n: int) -> bool:
	return (n >= 1 and n <= 99) or (n >= 1300 and n <= 1999)

## Parses one ACE. Accepts "access-list N ..." or a bare named-ACL style line.
## Returns {ok: true, entry} or {ok: false, error}.
static func parse_line(line: String, standard_default: bool = false) -> Dictionary:
	var t := Array(line.strip_edges().to_lower().split(" ", false))
	var standard := standard_default
	if t.size() >= 2 and t[0] == "access-list":
		if not t[1].is_valid_int():
			return _err("access-list needs a number")
		standard = is_standard_number(t[1].to_int())
		t = t.slice(2)
	if t.is_empty() or not t[0] in ["permit", "deny"]:
		return _err("must start with permit or deny")
	var e := {"action": t[0], "proto": "ip", "src": 0, "src_wc": ANY_WC, "src_port": -1,
		"dst": 0, "dst_wc": ANY_WC, "dst_port": -1, "standard": standard}
	var i := 1
	if standard:
		if i >= t.size():
			return _err("missing source")
		var a := _addr(t, i, true)
		if not a.ok:
			return a
		e.src = a.addr
		e.src_wc = a.wc
		i = a.next
	else:
		if i >= t.size() or not t[i] in PROTOS:
			return _err("extended ACEs need a protocol: ip, tcp, udp or icmp")
		e.proto = t[i]
		i += 1
		var s := _addr(t, i, false)
		if not s.ok:
			return s
		e.src = s.addr
		e.src_wc = s.wc
		i = s.next
		if i < t.size() and t[i] == "eq":
			var p := _port(t, i, e.proto)
			if not p.ok:
				return p
			e.src_port = p.port
			i = p.next
		var d := _addr(t, i, false)
		if not d.ok:
			return d
		e.dst = d.addr
		e.dst_wc = d.wc
		i = d.next
		if i < t.size() and t[i] == "eq":
			var p2 := _port(t, i, e.proto)
			if not p2.ok:
				return p2
			e.dst_port = p2.port
			i = p2.next
	if i < t.size():
		return _err("unexpected '%s'" % t[i])
	return {"ok": true, "entry": e}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}

## any | host A | A W (W optional only in standard ACLs, meaning host).
static func _addr(t: Array, i: int, standard: bool) -> Dictionary:
	if i >= t.size():
		return _err("missing address")
	if t[i] == "any":
		return {"ok": true, "addr": 0, "wc": ANY_WC, "next": i + 1}
	if t[i] == "host":
		var h := IPv4.parse(t[i + 1]) if i + 1 < t.size() else -1
		if h < 0:
			return _err("'host' needs an IP address")
		return {"ok": true, "addr": h, "wc": 0, "next": i + 2}
	var a := IPv4.parse(t[i])
	if a < 0:
		return _err("'%s' is not an address" % t[i])
	var w := IPv4.parse(t[i + 1]) if i + 1 < t.size() else -1
	if w < 0:
		if standard:
			return {"ok": true, "addr": a, "wc": 0, "next": i + 1}
		return _err("address %s needs a wildcard mask" % t[i])
	return {"ok": true, "addr": a, "wc": w, "next": i + 2}

static func _port(t: Array, i: int, proto: String) -> Dictionary:
	if not proto in ["tcp", "udp"]:
		return _err("ports only apply to tcp or udp")
	if i + 1 >= t.size():
		return _err("'eq' needs a port")
	var p: String = t[i + 1]
	var n := p.to_int() if p.is_valid_int() else int(PORTS.get(p, -1))
	if n < 0 or n > 65535:
		return _err("unknown port '%s'" % p)
	return {"ok": true, "port": n, "next": i + 2}

static func addr_matches(ip: int, addr: int, wc: int) -> bool:
	var care := ~wc & ANY_WC
	return (ip & care) == (addr & care)

static func entry_matches(e: Dictionary, pkt: Dictionary) -> bool:
	if e.proto != "ip" and e.proto != pkt.proto:
		return false
	if not addr_matches(pkt.src, e.src, e.src_wc):
		return false
	if e.standard:
		return true
	if not addr_matches(pkt.dst, e.dst, e.dst_wc):
		return false
	if e.src_port >= 0 and pkt.get("sport", -1) != e.src_port:
		return false
	if e.dst_port >= 0 and pkt.get("dport", -1) != e.dst_port:
		return false
	return true

## Index of the first matching entry, or -1 (implicit deny).
static func first_match(entries: Array, pkt: Dictionary) -> int:
	for i in entries.size():
		if entry_matches(entries[i], pkt):
			return i
	return -1

static func evaluate(entries: Array, pkt: Dictionary) -> String:
	var i := first_match(entries, pkt)
	return "deny" if i < 0 else entries[i].action

## Same behaviour, ignoring how it was written (host vs 0.0.0.0, port names, host bits).
static func equivalent(a: Dictionary, b: Dictionary) -> bool:
	for k in ["action", "proto", "src_wc", "dst_wc", "src_port", "dst_port"]:
		if a[k] != b[k]:
			return false
	var sc: int = ~a.src_wc & ANY_WC
	var dc: int = ~a.dst_wc & ANY_WC
	if (a.src & sc) != (b.src & sc):
		return false
	return a.standard or (a.dst & dc) == (b.dst & dc)

static func addr_str(addr: int, wc: int) -> String:
	if wc == ANY_WC:
		return "any"
	if wc == 0:
		return "host " + IPv4.to_str(addr)
	return "%s %s" % [IPv4.to_str(addr & (~wc & ANY_WC)), IPv4.to_str(wc)]

static func to_str(e: Dictionary) -> String:
	if e.standard:
		return "%s %s" % [e.action, addr_str(e.src, e.src_wc)]
	var s := "%s %s %s" % [e.action, e.proto, addr_str(e.src, e.src_wc)]
	if e.src_port >= 0:
		s += " eq %d" % e.src_port
	s += " " + addr_str(e.dst, e.dst_wc)
	if e.dst_port >= 0:
		s += " eq %d" % e.dst_port
	return s

## "show access-lists" style listing with sequence numbers 10, 20, ...
static func show(number: int, entries: Array) -> String:
	var kind := "Standard" if is_standard_number(number) else "Extended"
	var lines := PackedStringArray(["%s IP access list %d" % [kind, number]])
	for i in entries.size():
		lines.append("    %d %s" % [(i + 1) * 10, to_str(entries[i])])
	return "\n".join(lines)

## First and last address matched by addr/wc (contiguous wildcards).
static func wc_range(addr: int, wc: int) -> Array:
	var first := addr & (~wc & ANY_WC)
	return [first, first | wc]
