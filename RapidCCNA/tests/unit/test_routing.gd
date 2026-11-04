extends GutTest

func _table() -> RoutingTable:
	var rt := RoutingTable.new()
	rt.add(RoutingTable.route("C", "10.0.0.0", 30, "", "GigabitEthernet0/0"))
	rt.add(RoutingTable.route("O", "172.16.0.0", 16, "10.0.0.2", "", 20))
	rt.add(RoutingTable.route("S", "172.16.5.0", 24, "10.0.0.2"))
	rt.add(RoutingTable.route("D", "172.16.5.64", 26, "10.0.0.2", "", 30720))
	rt.add(RoutingTable.route("S", "0.0.0.0", 0, "10.0.0.1"))
	return rt

func test_longest_prefix_match():
	var rt := _table()
	assert_eq(rt.lookup(IPv4.parse("172.16.5.70")).len, 26)
	assert_eq(rt.lookup(IPv4.parse("172.16.5.10")).len, 24)
	assert_eq(rt.lookup(IPv4.parse("172.16.9.9")).len, 16)
	assert_eq(rt.lookup(IPv4.parse("8.8.8.8")).len, 0)
	assert_eq(rt.lookup(IPv4.parse("10.0.0.1")).code, "C")

func test_no_default_drops():
	var rt := RoutingTable.new()
	rt.add(RoutingTable.route("O", "172.16.0.0", 16, "10.0.0.2"))
	assert_true(rt.lookup(IPv4.parse("8.8.8.8")).is_empty())

func test_lowest_ad_then_metric_is_installed():
	var rt := RoutingTable.new()
	rt.add(RoutingTable.route("R", "10.9.0.0", 16, "10.0.0.6", "", 1))
	rt.add(RoutingTable.route("O", "10.9.0.0", 16, "10.0.0.2", "", 50))
	rt.add(RoutingTable.route("S", "10.9.0.0", 16, "10.0.0.10", "", 0, 130))   # floating static
	assert_eq(rt.routes.size(), 1)
	assert_eq(rt.routes[0].code, "O")
	rt.add(RoutingTable.route("O", "10.9.0.0", 16, "10.0.0.14", "", 10))
	assert_eq(rt.routes[0].next_hop, "10.0.0.14", "same AD: lower metric wins")

func test_show_output():
	var out := _table().show()
	assert_string_contains(out, "Gateway of last resort is 10.0.0.1 to network 0.0.0.0")
	assert_string_contains(out, "S*     0.0.0.0/0 [1/0] via 10.0.0.1")
	assert_string_contains(out, "C      10.0.0.0/30 is directly connected, GigabitEthernet0/0")
	assert_string_contains(out, "D      172.16.5.64/26 [90/30720] via 10.0.0.2")

func test_lookup_matches_brute_force():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for t in 30:
		var rt := RoutingTable.new()
		for i in 8:
			var l := rng.randi_range(0, 30)
			rt.add(RoutingTable.route("S", IPv4.to_str(rng.randi_range(0, 0x7FFFFFFF)), l, "10.0.0.2"))
		for k in 20:
			var ip := rng.randi_range(0, 0x7FFFFFFF)
			var best := -1
			for r in rt.routes:
				if IPv4.network(ip, r.len) == r.net:
					best = max(best, r.len)
			var got := rt.lookup(ip)
			assert_eq(got.get("len", -1), best)
