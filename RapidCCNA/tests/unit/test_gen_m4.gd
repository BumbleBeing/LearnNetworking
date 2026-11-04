extends GutTest
## M4 generators (STP, OSPF, EtherChannel, MAC table): every item self-consistent and deterministic.

const GENS := ["res://core/net/StpGen.gd", "res://core/net/OspfGen.gd", "res://core/net/EtherChannelGen.gd", "res://core/net/MacGen.gd"]

func test_items_are_self_consistent():
	for path in GENS:
		var gen: Script = load(path)
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		var kinds := {}
		for i in 400:
			var it: Dictionary = gen.make_item(rng)
			kinds[it.kind] = true
			for k in ["kind", "card_id", "question", "answer", "hint", "explain"]:
				assert_true(it.has(k), "%s missing %s" % [path, k])
			assert_true(it.card_id.begins_with("gen."), path)
			assert_false(str(it.explain).is_empty(), "%s %s explain" % [path, it.kind])
			if it.has("choices"):
				assert_between(int(it.answer_index), 0, it.choices.size() - 1, "%s %s answer index" % [path, it.kind])
				assert_eq(it.choices[int(it.answer_index)], it.answer, "%s %s" % [path, it.kind])
				var uniq := {}
				for c in it.choices:
					uniq[c] = true
				assert_eq(uniq.size(), it.choices.size(), "%s %s duplicate choices: %s" % [path, it.kind, it.choices])
			else:
				assert_true(gen.check(it, it.answer), "%s %s: %s" % [path, it.kind, it.answer])
				assert_false(gen.check(it, "999"), "%s %s" % [path, it.kind])
		assert_eq(kinds.size(), gen.KINDS.size(), "%s covers all kinds" % path)

func test_deterministic():
	for path in GENS:
		var gen: Script = load(path)
		var a := RandomNumberGenerator.new()
		a.seed = 9
		var b := RandomNumberGenerator.new()
		b.seed = 9
		for i in 10:
			assert_eq(str(gen.make_item(a)), str(gen.make_item(b)), path)

func test_stp_topologies_block_exactly_one_port():
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in 300:
		var t := StpGen.make_topology(rng)
		var res := STP.solve(t.switches, t.links)
		assert_eq(STP.blocked(res).size(), 1, "%s: %s" % [t.shape, res.roles])
		assert_eq(res.root_port.size(), t.switches.size() - 1)
		for sw in res.root_port:
			assert_eq(res.roles["%s %s" % [sw, res.root_port[sw]]], "Root")

func test_ports_out_answer_parsing_is_lenient():
	var it := {"kind": "ports_out", "answer": "Fa0/2, Fa0/4, Gi0/1"}
	assert_true(MacGen.check(it, "gi0/1 fa0/4, FastEthernet0/2"))
	assert_false(MacGen.check(it, "fa0/2, fa0/4"))
	assert_true(MacGen.check({"kind": "ports_out", "answer": "none"}, "None"))
	assert_false(MacGen.check({"kind": "ports_out", "answer": "none"}, "fa0/1"))
