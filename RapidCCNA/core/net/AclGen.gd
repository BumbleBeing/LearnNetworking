class_name AclGen
extends RefCounted
## ACL Gatekeeper items: predict which ACE a packet hits, or write an ACE from a requirement.

const KINDS := ["predict", "predict", "write"]
const IMPLICIT := "Implicit deny (no line matches)"
const SERVICES := [["tcp", 22, "SSH"], ["tcp", 23, "Telnet"], ["tcp", 80, "HTTP"], ["tcp", 443, "HTTPS"], ["udp", 53, "DNS"], ["icmp", -1, "ping"]]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	return _write(rng) if kind == "write" else _predict(rng)

static func _e(line: String) -> Dictionary:
	return ACL.parse_line(line).entry

static func _predict(rng: RandomNumberGenerator) -> Dictionary:
	var a := "192.168.%d.0" % rng.randi_range(10, 49)
	var b := "192.168.%d.0" % rng.randi_range(50, 99)
	var server := "10.1.1.%d" % rng.randi_range(10, 30)
	var bad_host := b.trim_suffix(".0") + ".%d" % rng.randi_range(2, 200)
	var pool := [
		"access-list 100 deny tcp %s 0.0.0.255 host %s eq 22" % [a, server],
		"access-list 100 permit tcp %s 0.0.0.255 host %s eq 80" % [a, server],
		"access-list 100 permit tcp any host %s eq 443" % server,
		"access-list 100 deny ip host %s any" % bad_host,
		"access-list 100 permit ip %s 0.0.0.255 any" % b,
		"access-list 100 permit udp any host %s eq 53" % server,
		"access-list 100 deny icmp any host %s" % server,
		"access-list 100 permit icmp %s 0.0.0.255 any" % a,
	]
	GenUtil.shuffle(rng, pool)
	var entries: Array = pool.slice(0, rng.randi_range(3, 5)).map(func(l): return _e(l))
	var src_net := IPv4.parse([a, b][rng.randi() % 2])
	var src := src_net + rng.randi_range(2, 200)
	if rng.randf() < 0.2:
		src = IPv4.parse(bad_host)
	var svc: Array = SERVICES[rng.randi() % SERVICES.size()]
	var dst := IPv4.parse(server) if rng.randf() < 0.75 else IPv4.parse("203.0.113.%d" % rng.randi_range(1, 254))
	var pkt := {"proto": svc[0], "src": src, "dst": dst, "sport": rng.randi_range(49152, 65000), "dport": svc[1]}
	var hit := ACL.first_match(entries, pkt)
	var choices: Array = []
	for i in entries.size():
		choices.append("%d  %s" % [(i + 1) * 10, ACL.to_str(entries[i])])
	choices.append(IMPLICIT)
	var answer_index := choices.size() - 1 if hit < 0 else hit
	var pkt_s := ""
	if svc[0] == "icmp":
		pkt_s = "ICMP echo  %s → %s" % [IPv4.to_str(src), IPv4.to_str(dst)]
	else:
		pkt_s = "%s  %s:%d → %s:%d  (%s)" % [svc[0].to_upper(), IPv4.to_str(src), pkt.sport, IPv4.to_str(dst), svc[1], svc[2]]
	var verdict := "denied" if hit < 0 or entries[hit].action == "deny" else "permitted"
	var why := ""
	for i in entries.size():
		if i == hit:
			why += "Line %d matches, so the packet is %s and later lines are ignored." % [(i + 1) * 10, verdict]
			break
		why += "Line %d: %s.\n" % [(i + 1) * 10, _miss_reason(entries[i], pkt)]
	if hit < 0:
		why += "Nothing matched, so the implicit deny at the end drops it."
	return {"kind": "predict", "card_id": "gen.acl_gatekeeper.predict",
		"exhibit": ACL.show(100, entries) + "\n\nApplied inbound on the interface facing the 192.168 networks.",
		"prompt": pkt_s, "question": "Which line decides this packet?",
		"choices": choices, "answer_index": answer_index, "answer": choices[answer_index],
		"hint": "ACLs are read top-down; the first line where protocol, source, destination and port all match wins.",
		"explain": why}

static func _miss_reason(e: Dictionary, pkt: Dictionary) -> String:
	if e.proto != "ip" and e.proto != pkt.proto:
		return "protocol is %s, not %s" % [pkt.proto, e.proto]
	if not ACL.addr_matches(pkt.src, e.src, e.src_wc):
		return "source %s isn't %s" % [IPv4.to_str(pkt.src), ACL.addr_str(e.src, e.src_wc)]
	if not ACL.addr_matches(pkt.dst, e.dst, e.dst_wc):
		return "destination %s isn't %s" % [IPv4.to_str(pkt.dst), ACL.addr_str(e.dst, e.dst_wc)]
	return "port %d isn't %d" % [pkt.get("dport", -1), e.dst_port]

static func _write(rng: RandomNumberGenerator) -> Dictionary:
	var p := rng.randi_range(24, 28)
	var net := IPv4.network(IPv4.parse("10.%d.%d.%d" % [rng.randi_range(1, 99), rng.randi_range(0, 255), rng.randi_range(0, 255)]), p)
	var host := "172.16.%d.%d" % [rng.randi_range(0, 31), rng.randi_range(2, 250)]
	var svc: Array = SERVICES.slice(0, 5)[rng.randi() % 5]
	var templates := [
		["Permit %s (%s %d) from %s/%d to the server %s." % [svc[2], svc[0].to_upper(), svc[1], IPv4.to_str(net), p, host],
			"permit %s %s %s host %s eq %d" % [svc[0], IPv4.to_str(net), IPv4.to_str(IPv4.wildcard(p)), host, svc[1]], false],
		["Deny %s (%s %d) from any source to host %s." % [svc[2], svc[0].to_upper(), svc[1], host],
			"deny %s any host %s eq %d" % [svc[0], host, svc[1]], false],
		["Deny all IP traffic from %s/%d to any destination." % [IPv4.to_str(net), p],
			"deny ip %s %s any" % [IPv4.to_str(net), IPv4.to_str(IPv4.wildcard(p))], false],
		["Standard ACL 10: permit the subnet %s/%d." % [IPv4.to_str(net), p],
			"permit %s %s" % [IPv4.to_str(net), IPv4.to_str(IPv4.wildcard(p))], true],
		["Standard ACL 10: deny the single host %s." % host,
			"deny host %s" % host, true],
	]
	var t: Array = templates[rng.randi() % templates.size()]
	var expected: Dictionary = ACL.parse_line(t[1], t[2]).entry
	return {"kind": "write", "card_id": "gen.acl_gatekeeper.write", "standard": t[2],
		"prompt": "Extended ACL 100" if not t[2] else "Standard ACL 10",
		"question": t[0], "answer": ACL.to_str(expected), "expected": expected,
		"placeholder": "permit tcp ... " if not t[2] else "permit ...", "wide": true,
		"hint": ("Standard: permit|deny <source> [wildcard]" if t[2]
			else "Extended: permit|deny <protocol> <source> <wildcard> <destination> [eq <port>]. Use 'host' or 'any' where they fit."),
		"explain": "One correct answer: %s\nhost X = X 0.0.0.0, any = 0.0.0.0 255.255.255.255, wildcard = inverse of the mask." % ACL.to_str(expected)}

static func check(item: Dictionary, response: String) -> bool:
	if item.kind != "write":
		return false
	var r := ACL.parse_line(response, item.standard)
	return r.ok and ACL.equivalent(item.expected, r.entry)

## Explains why a typed ACE was rejected (shown as feedback detail).
static func parse_error(item: Dictionary, response: String) -> String:
	var r := ACL.parse_line(response, item.get("standard", false))
	return "" if r.ok else r.error
