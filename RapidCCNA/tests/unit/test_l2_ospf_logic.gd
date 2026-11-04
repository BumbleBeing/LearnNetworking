extends GutTest
## Pure M4 logic: STP elections and roles, OSPF rules, EtherChannel negotiation, MAC learning.

func _sw(sw_name: String, pri: int, mac: String) -> Dictionary:
	return {"name": sw_name, "priority": pri, "mac": mac}

func _l(a: String, ap: String, b: String, bp: String, cost: int = 4) -> Dictionary:
	return {"a": a, "ap": ap, "b": b, "bp": bp, "cost": cost}

func test_root_bridge_lowest_priority_then_mac():
	var sws := [_sw("SW1", 32769, "0000.0000.0003"), _sw("SW2", 32769, "0000.0000.0001"), _sw("SW3", 28673, "ffff.0000.0000")]
	assert_eq(STP.solve(sws, []).root, "SW3")
	sws[2].priority = 32769
	assert_eq(STP.solve(sws, []).root, "SW2", "MAC breaks the tie")

func test_triangle_roles():
	# SW1 root. SW2-SW3 link: SW2 has the lower bridge ID, so SW3's end blocks.
	var sws := [_sw("SW1", 4097, "0000.0000.0009"), _sw("SW2", 32769, "0000.0000.0001"), _sw("SW3", 32769, "0000.0000.0002")]
	var links := [_l("SW1", "Gi0/1", "SW2", "Gi0/1"), _l("SW1", "Gi0/2", "SW3", "Gi0/1"), _l("SW2", "Gi0/2", "SW3", "Gi0/2")]
	var r := STP.solve(sws, links)
	assert_eq(r.root, "SW1")
	assert_eq(r.root_port, {"SW2": "Gi0/1", "SW3": "Gi0/1"})
	assert_eq(r.roles["SW2 Gi0/2"], "Designated")
	assert_eq(r.roles["SW3 Gi0/2"], "Alternate")
	assert_eq(r.cost["SW3"], 4)

func test_cheaper_indirect_path_wins():
	var sws := [_sw("SW1", 4097, "0000.0000.0009"), _sw("SW2", 32769, "0000.0000.0001"), _sw("SW3", 32769, "0000.0000.0002")]
	var links := [_l("SW1", "Gi0/1", "SW2", "Gi0/1", 2), _l("SW1", "Gi0/2", "SW3", "Gi0/1", 19), _l("SW2", "Gi0/2", "SW3", "Gi0/2", 2)]
	var r := STP.solve(sws, links)
	assert_eq(r.root_port["SW3"], "Gi0/2")
	assert_eq(r.cost["SW3"], 4)
	assert_eq(r.roles["SW3 Gi0/1"], "Alternate")

func test_parallel_links_use_neighbour_port_id():
	var sws := [_sw("SW1", 4097, "0000.0000.0001"), _sw("SW2", 32769, "0000.0000.0002")]
	var links := [_l("SW1", "Gi0/1", "SW2", "Gi0/2"), _l("SW1", "Gi0/2", "SW2", "Gi0/1")]
	var r := STP.solve(sws, links)
	assert_eq(r.root_port["SW2"], "Gi0/2", "connected to the root's lower port ID")
	assert_string_contains(r.why["SW2"], "neighbour port ID")

func test_bridge_priority_and_costs():
	assert_eq(STP.bridge_priority(24576, 10), 24586)
	assert_true(STP.valid_base_priority(4096))
	assert_false(STP.valid_base_priority(1000))
	assert_eq(STP.cost_for(100), 19)
	assert_eq(STP.cost_for(10000), 2)

func test_ospf_router_id_order():
	var ifs := [{"name": "GigabitEthernet0/0", "ip": "192.168.1.1", "up": true}, {"name": "Loopback0", "ip": "10.0.0.1", "up": true}]
	assert_eq(OSPF.router_id("", ifs).rid, "10.0.0.1")
	assert_eq(OSPF.router_id("9.9.9.9", ifs).rid, "9.9.9.9")
	ifs[1].up = false
	assert_eq(OSPF.router_id("", ifs).rid, "192.168.1.1")

func test_ospf_cost_and_election():
	assert_eq(OSPF.cost(1000), 1)
	assert_eq(OSPF.cost(1000, 10000), 10)
	assert_eq(OSPF.cost(1.544), 64)
	assert_eq(OSPF.cost(10), 10)
	var e := OSPF.elect([{"name": "A", "rid": "4.4.4.4", "priority": 1}, {"name": "B", "rid": "9.9.9.9", "priority": 0},
		{"name": "C", "rid": "1.1.1.1", "priority": 5}, {"name": "D", "rid": "3.3.3.3", "priority": 1}])
	assert_eq(e.dr, "C")
	assert_eq(e.bdr, "A")

func test_ospf_neighbor_issues():
	var a := {"rid": "1.1.1.1", "ip": "10.0.0.1", "mask": "255.255.255.252", "area": 0, "hello": 10, "dead": 40}
	var b := {"rid": "2.2.2.2", "ip": "10.0.0.2", "mask": "255.255.255.252", "area": 0, "hello": 10, "dead": 40}
	assert_eq(OSPF.neighbor_issues(a, b), [])
	b.area = 1
	assert_eq(OSPF.neighbor_issues(a, b), ["area"])
	b.area = 0
	b.ip = "10.0.0.6"
	assert_eq(OSPF.neighbor_issues(a, b), ["subnet"])

func test_ospf_spf_keeps_equal_cost_paths():
	var edges := []
	for l in [["A", "B", 1], ["A", "C", 1], ["B", "D", 1], ["C", "D", 1]]:
		edges.append({"from": l[0], "to": l[1], "cost": l[2]})
		edges.append({"from": l[1], "to": l[0], "cost": l[2]})
	var r := OSPF.spf(["A", "B", "C", "D"], edges, "A")
	assert_eq(r.dist["D"], 2)
	var f: Array = r.first["D"]
	f.sort()
	assert_eq(f, ["B", "C"])
	assert_true(OSPF.network_matches("10.1.0.0", "0.0.3.255", "10.1.3.1"))
	assert_false(OSPF.network_matches("10.1.0.0", "0.0.3.255", "10.1.4.1"))

func test_etherchannel_negotiation_table():
	var cases := [["active", "passive", "LACP"], ["active", "active", "LACP"], ["passive", "passive", ""],
		["desirable", "auto", "PAgP"], ["auto", "auto", ""], ["on", "on", "static"], ["on", "active", ""], ["active", "desirable", ""]]
	for c in cases:
		var n := EtherChannel.negotiate(c[0], c[1])
		assert_eq(n.forms, c[2] != "", "%s + %s" % [c[0], c[1]])
		assert_eq(n.protocol, c[2], "%s + %s" % [c[0], c[1]])
	var issues := EtherChannel.member_issues([{"name": "Gi0/1", "mode": "trunk", "native": 99, "allowed": "10,20", "vlan": 1},
		{"name": "Gi0/2", "mode": "trunk", "native": 99, "allowed": "10", "vlan": 5}])
	assert_eq(issues.size(), 1, "access VLAN ignored on trunks")
	assert_eq(issues[0].attr, "allowed")

func test_mac_table_learn_flood_forward_filter():
	var t := MacTable.create({"Fa0/1": {"vlan": 10}, "Fa0/2": {"vlan": 10}, "Fa0/3": {"vlan": 20}, "Gi0/1": {"trunk": true}})
	var r := t.receive("Fa0/1", "aaaa.aaaa.0001", "aaaa.aaaa.0002")
	assert_eq(r.action, "flood")
	assert_eq(r.out, ["Fa0/2", "Gi0/1"], "VLAN 20 port excluded, trunk included")
	r = t.receive("Fa0/2", "aaaa.aaaa.0002", "aaaa.aaaa.0001")
	assert_eq(r.action, "forward")
	assert_eq(r.out, ["Fa0/1"])
	r = t.receive("Fa0/3", "aaaa.aaaa.0003", "aaaa.aaaa.0001")
	assert_eq(r.action, "flood", "learned in VLAN 10 only")
	t.learn("aaaa.aaaa.0009", 10, "Fa0/1")
	assert_eq(t.receive("Fa0/1", "aaaa.aaaa.0001", "aaaa.aaaa.0009").action, "filter")
	r = t.receive("Fa0/2", "aaaa.aaaa.0001", MacTable.BROADCAST)
	assert_eq(r.moved_from, "Fa0/1")
	assert_eq(t.lookup("aaaa.aaaa.0001", 10), "Fa0/2")
	assert_string_contains(t.show(), "aaaa.aaaa.0003")
