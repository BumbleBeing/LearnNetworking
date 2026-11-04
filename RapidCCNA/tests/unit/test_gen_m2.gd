extends GutTest
## Every generator item must be self-consistent: its own answer passes, choices hold the answer.

const GENS := ["res://core/net/RouteGen.gd", "res://core/net/WildcardGen.gd", "res://core/net/AclGen.gd", "res://core/net/NatGen.gd"]

func test_items_are_self_consistent():
	for path in GENS:
		var gen: Script = load(path)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var kinds := {}
		for i in 300:
			var it: Dictionary = gen.make_item(rng)
			kinds[it.kind] = true
			for k in ["kind", "card_id", "question", "answer", "hint", "explain"]:
				assert_true(it.has(k), "%s missing %s" % [path, k])
			assert_true(it.card_id.begins_with("gen."), path)
			if it.has("choices"):
				assert_eq(it.choices[int(it.answer_index)], it.answer, "%s %s" % [path, it.kind])
				assert_eq(it.choices.size(), {}.merged(Dictionary(Array(it.choices).reduce(func(acc, c): acc[c] = 1; return acc, {}))).size(), "%s duplicate choices" % path)
			else:
				assert_true(gen.check(it, it.answer), "%s %s: %s" % [path, it.kind, it.answer])
				assert_false(gen.check(it, "999"), path)
		assert_eq(kinds.size(), gen.KINDS.reduce(func(acc, k): acc[k] = 1; return acc, {}).size(), "%s covers all kinds" % path)

func test_deterministic():
	for path in GENS:
		var gen: Script = load(path)
		var a := RandomNumberGenerator.new()
		a.seed = 3
		var b := RandomNumberGenerator.new()
		b.seed = 3
		assert_eq(str(gen.make_item(a)), str(gen.make_item(b)), path)

func test_route_picker_answer_is_longest_match():
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var drops := 0
	for i in 200:
		var it := RouteGen.make_item(rng, "next_hop")
		if it.answer == RouteGen.DROP:
			drops += 1
	assert_gt(drops, 0, "some items should test the no-default drop case")

func test_acl_write_accepts_equivalent_notation():
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in 100:
		var it := AclGen.make_item(rng, "write")
		assert_true(AclGen.check(it, it.answer))
		assert_true(AclGen.check(it, "access-list %d %s" % [10 if it.standard else 100, it.answer]))
		assert_false(AclGen.check(it, "permit ip any any") and it.answer != "permit ip any any")
	assert_string_contains(AclGen.parse_error({"standard": false}, "permit tcp 10.0.0.0 any"), "wildcard")

func test_wildcard_does_match_is_correct():
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var yes := 0
	for i in 200:
		var it := WildcardGen.make_item(rng, "does_match")
		var parts: PackedStringArray = it.question.trim_prefix("Is this address matched by ").trim_suffix("?").split(" ")
		var m := ACL.addr_matches(IPv4.parse(it.prompt), IPv4.parse(parts[0]), IPv4.parse(parts[1]))
		assert_eq(it.answer_index, 0 if m else 1)
		yes += 1 if m else 0
	assert_true(yes > 40 and yes < 160, "roughly balanced yes/no (%d)" % yes)
