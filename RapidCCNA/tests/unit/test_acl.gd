extends GutTest

func _p(line: String, std := false) -> Dictionary:
	var r := ACL.parse_line(line, std)
	assert_true(r.ok, "%s: %s" % [line, r.get("error", "")])
	return r.get("entry", {})

func test_parse_standard_forms():
	var e := _p("access-list 10 permit 192.168.1.0 0.0.0.255")
	assert_true(e.standard)
	assert_eq(ACL.to_str(e), "permit 192.168.1.0 0.0.0.255")
	assert_eq(ACL.to_str(_p("access-list 10 deny host 10.1.1.1")), "deny host 10.1.1.1")
	assert_eq(ACL.to_str(_p("access-list 10 deny 10.1.1.1")), "deny host 10.1.1.1", "standard: no wildcard = host")
	assert_eq(ACL.to_str(_p("access-list 1 permit any")), "permit any")
	assert_true(_p("access-list 1300 permit any").standard, "expanded standard range")

func test_parse_extended_forms():
	var e := _p("access-list 100 permit tcp 10.0.0.0 0.0.0.255 host 172.16.1.10 eq www")
	assert_false(e.standard)
	assert_eq(e.dst_port, 80)
	assert_eq(ACL.to_str(e), "permit tcp 10.0.0.0 0.0.0.255 host 172.16.1.10 eq 80")
	assert_eq(_p("deny udp any any eq domain").dst_port, 53)
	assert_eq(ACL.to_str(_p("access-list 101 permit icmp any any")), "permit icmp any any")
	assert_eq(_p("permit tcp any eq 22 any").src_port, 22)

func test_parse_errors():
	for bad in ["", "allow ip any any", "access-list 100 permit tcp 10.0.0.0 any", "access-list 100 permit gre any any",
			"access-list 100 permit icmp any any eq 80", "access-list 100 permit tcp any any eq nosuch",
			"access-list 10 permit 300.1.1.1", "access-list 100 permit ip any any extra", "access-list x permit any"]:
		assert_false(ACL.parse_line(bad).ok, bad)

func test_evaluate_top_down_and_implicit_deny():
	var acl := [_p("access-list 100 deny tcp 192.168.10.0 0.0.0.255 host 10.1.1.10 eq 22"),
		_p("access-list 100 permit tcp any host 10.1.1.10 eq 22"),
		_p("access-list 100 permit icmp any any")]
	var src := IPv4.parse("192.168.10.5")
	var other := IPv4.parse("192.168.20.5")
	var srv := IPv4.parse("10.1.1.10")
	assert_eq(ACL.first_match(acl, {"proto": "tcp", "src": src, "dst": srv, "dport": 22}), 0)
	assert_eq(ACL.first_match(acl, {"proto": "tcp", "src": other, "dst": srv, "dport": 22}), 1)
	assert_eq(ACL.first_match(acl, {"proto": "icmp", "src": src, "dst": srv}), 2)
	assert_eq(ACL.first_match(acl, {"proto": "udp", "src": src, "dst": srv, "dport": 53}), -1)
	assert_eq(ACL.evaluate(acl, {"proto": "udp", "src": src, "dst": srv, "dport": 53}), "deny")

func test_ip_matches_every_protocol_and_standard_ignores_destination():
	var e := _p("access-list 100 permit ip 10.0.0.0 0.255.255.255 any")
	assert_true(ACL.entry_matches(e, {"proto": "udp", "src": IPv4.parse("10.9.9.9"), "dst": 1, "dport": 53}))
	var s := _p("access-list 5 permit 10.0.0.0 0.255.255.255")
	assert_true(ACL.entry_matches(s, {"proto": "tcp", "src": IPv4.parse("10.1.1.1"), "dst": IPv4.parse("8.8.8.8"), "dport": 80}))

func test_equivalence_ignores_notation():
	var a := _p("access-list 100 permit tcp 10.1.1.0 0.0.0.255 host 172.16.0.5 eq 443")
	assert_true(ACL.equivalent(a, _p("permit tcp 10.1.1.77 0.0.0.255 172.16.0.5 0.0.0.0 eq https")))
	assert_false(ACL.equivalent(a, _p("permit tcp 10.1.1.0 0.0.0.255 host 172.16.0.5 eq 80")))
	assert_false(ACL.equivalent(a, _p("deny tcp 10.1.1.0 0.0.0.255 host 172.16.0.5 eq 443")))
	assert_false(ACL.equivalent(a, _p("permit tcp 10.1.1.0 0.0.0.127 host 172.16.0.5 eq 443")))

func test_wildcard_range_and_show():
	var r := ACL.wc_range(IPv4.parse("10.4.0.0"), IPv4.parse("0.0.3.255"))
	assert_eq(IPv4.to_str(r[1]), "10.4.3.255")
	var out := ACL.show(100, [_p("access-list 100 permit ip any any")])
	assert_eq(out, "Extended IP access list 100\n    10 permit ip any any")
