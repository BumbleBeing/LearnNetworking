extends GutTest

func _rng(rng_seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = rng_seed
	return r

func test_subnet_items_are_deterministic_per_seed():
	assert_eq(SubnetGen.make_item(_rng(42)), SubnetGen.make_item(_rng(42)))

func test_subnet_items_are_self_consistent():
	var rng := _rng(1)
	for i in 300:
		var it := SubnetGen.make_item(rng)
		var ip := IPv4.parse(it.ip)
		assert_true(it.prefix >= 16 and it.prefix <= 30)
		assert_ne(ip, IPv4.network(ip, it.prefix), "host must not be the network address")
		assert_ne(ip, IPv4.broadcast(ip, it.prefix), "host must not be the broadcast address")
		assert_true(SubnetGen.check(it, it.answer), "answer checks: %s" % it)
		assert_true(it.card_id.begins_with("gen.subnet_sprint."))
		assert_false(SubnetGen.explain(it).is_empty())

func test_subnet_check_is_lenient_on_format_but_not_value():
	var it := {"kind": "network", "answer": "10.0.0.64"}
	assert_true(SubnetGen.check(it, " 10.0.0.64 "))
	assert_false(SubnetGen.check(it, "10.0.0.65"))
	var hosts := {"kind": "hosts", "answer": "62"}
	assert_true(SubnetGen.check(hosts, "62"))
	assert_false(SubnetGen.check(hosts, "64"))

func test_binary_conversions():
	assert_eq(Binary.to_bin8(192), "11000000")
	assert_eq(Binary.spaced("11000000"), "1100 0000")
	assert_eq(Binary.parse_bin("1100 1000"), 200)
	assert_eq(Binary.parse_bin("102"), -1)
	assert_eq(Binary.parse_bin("111111111"), -1)
	assert_eq(Binary.to_hex(200), "C8")
	assert_eq(Binary.parse_hex("0xc8"), 200)
	assert_eq(Binary.parse_hex("C8"), 200)
	assert_eq(Binary.parse_hex("G1"), -1)
	assert_eq(Binary.parse_dec("256"), -1)
	assert_eq(Binary.parse_dec("007"), 7)

func test_binary_items_check_their_own_answers():
	var rng := _rng(7)
	for i in 200:
		var it := Binary.make_item(rng)
		assert_true(Binary.check(it, it.answer), str(it))
		assert_true(it.value >= 0 and it.value <= 255)

func test_binary_explain_shows_place_values():
	assert_eq(Binary.explain({"value": 192}), "192 = 128 + 64  →  1100 0000  →  1100 0000 = 0xC0")
	assert_string_contains(Binary.explain({"value": 0}), "0 = 0")
