extends GutTest
## M5 generators: every item self-consistent and deterministic, plus answer-checking rules.

const GENS := ["res://core/net/Ipv6Gen.gd", "res://core/net/InterfaceGen.gd", "res://core/net/WifiGen.gd",
	"res://core/net/FhrpGen.gd", "res://core/net/ServiceGen.gd"]

func test_items_are_self_consistent():
	for path in GENS:
		var gen: Script = load(path)
		var rng := RandomNumberGenerator.new()
		rng.seed = 23
		var kinds := {}
		for i in 400:
			var it: Dictionary = gen.make_item(rng)
			kinds[it.kind] = true
			for k in ["kind", "card_id", "question", "answer", "hint", "explain"]:
				assert_true(it.has(k), "%s missing %s" % [path, k])
			assert_true(it.card_id.begins_with("gen."), path)
			if it.has("choices"):
				assert_eq(it.choices[int(it.answer_index)], it.answer, "%s %s" % [path, it.kind])
				var uniq := {}
				for c in it.choices:
					uniq[c] = true
				assert_eq(uniq.size(), it.choices.size(), "%s %s duplicate choices" % [path, it.kind])
			else:
				assert_true(gen.check(it, it.answer), "%s %s: %s" % [path, it.kind, it.answer])
				assert_true(gen.check(it, " %s " % it.answer.to_upper()), "%s %s is case-insensitive" % [path, it.kind])
				assert_false(gen.check(it, "999"), "%s %s" % [path, it.kind])
		assert_eq(kinds.size(), gen.KINDS.size(), "%s covers all kinds" % path)

func test_deterministic():
	for path in GENS:
		var gen: Script = load(path)
		var a := RandomNumberGenerator.new()
		a.seed = 4
		var b := RandomNumberGenerator.new()
		b.seed = 4
		for i in 10:
			assert_eq(str(gen.make_item(a)), str(gen.make_item(b)), path)

func test_ipv6_compress_demands_the_shortest_form():
	var it := {"kind": "compress", "answer": "2001:db8::a00:1"}
	assert_true(Ipv6Gen.check(it, "2001:DB8::A00:1"))
	assert_false(Ipv6Gen.check(it, "2001:db8:0:0:0:0:a00:1"), "valid but not compressed")
	assert_string_contains(Ipv6Gen.parse_error(it, "2001:db8:0:0:0:0:a00:1"), "not the shortest form")
	assert_string_contains(Ipv6Gen.parse_error(it, "2001:db8::a::1"), "isn't a valid")

func test_ipv6_prefix_and_eui64_compare_by_value():
	var p := {"kind": "prefix", "answer": "2001:db8:acad:1::/64"}
	assert_true(Ipv6Gen.check(p, "2001:0db8:acad:0001:0:0:0:0/64"))
	assert_false(Ipv6Gen.check(p, "2001:db8:acad:1::/48"), "wrong length")
	var e := {"kind": "eui64", "answer": "2001:db8:1:1:21a:2bff:fe3c:4d5e"}
	assert_true(Ipv6Gen.check(e, "2001:0db8:0001:0001:021A:2BFF:FE3C:4D5E"))

func test_wifi_plan_answer_avoids_every_neighbour():
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for i in 200:
		var it := WifiGen.make_item(rng, "plan")
		var ch: int = it.answer.trim_prefix("Channel ").to_int()
		assert_true(ch in WifiGen.CLEAN)
		assert_false(it.explain.contains("use channels %d" % ch), "answer channel isn't a neighbour's")
	assert_true(WifiGen.overlaps(1, 3))
	assert_false(WifiGen.overlaps(1, 6))

func test_fhrp_rules():
	assert_eq(FhrpGen.elect([{"name": "A", "ip": "10.0.0.2", "priority": 100}, {"name": "B", "ip": "10.0.0.9", "priority": 100}]).name, "B", "tie: highest IP")
	assert_eq(FhrpGen.mac_for("HSRPv1", 10), "0000.0c07.ac0a")
	assert_eq(FhrpGen.mac_for("HSRPv2", 300), "0000.0c9f.f12c")
	assert_eq(FhrpGen.mac_for("VRRP", 1), "0000.5e00.0101")
	assert_true(FhrpGen.check({"kind": "vmac", "answer": "0000.0c07.ac0a"}, "0000.0C07.AC0A"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var it := FhrpGen.make_item(rng, "tracking")
		assert_false(it.explain.contains("not below R2's") and it.answer.contains("takes over"), "explanation agrees with the answer")

func test_service_desk_dscp_and_trap_rules():
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in 300:
		var it := ServiceGen.make_item(rng, "dscp")
		if it.has("prompt") and it.prompt.begins_with("AF") and not it.has("choices"):
			var x: int = it.prompt[2].to_int()
			var y: int = it.prompt[3].to_int()
			assert_eq(it.answer, str(8 * x + 2 * y))
		var t := ServiceGen.make_item(rng, "syslog_trap")
		var sev: int = t.exhibit.split("\n")[3].split("-")[1].to_int()
		var trap: int = ServiceGen.LEVELS.find(t.exhibit.split("\n")[1].trim_prefix("logging trap "))
		assert_eq(t.answer_index, 0 if sev <= trap else 1, t.exhibit)
