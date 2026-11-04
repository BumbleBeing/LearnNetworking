extends GutTest
## M6 hidden mini-labs behind cli_task questions: common wrong answers must fail.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _session(id: String) -> LabSession:
	return LabSession.create(ContentDB.labs[id])

func _ok(ls: LabSession) -> bool:
	return ls.all_ok()

func test_floating_route_needs_an_ad_above_ospf():
	var ls := _session("lab.mini_floating")
	assert_eq(ls.network.devices["R1"].routing_table().lookup(IPv4.parse("10.50.1.1")).code, "O", "OSPF route present at start")
	ls.apply("R1", ["ip route 10.50.0.0 255.255.0.0 10.0.13.2"])
	assert_false(_ok(ls), "AD 1 replaces the OSPF route")
	ls.apply("R1", ["no ip route 10.50.0.0 255.255.0.0 10.0.13.2", "ip route 10.50.0.0 255.255.0.0 10.0.13.2 100"])
	assert_false(_ok(ls), "AD 100 still beats OSPF")
	ls.apply("R1", ["no ip route 10.50.0.0 255.255.0.0 10.0.13.2 100", "ip route 10.50.0.0 255.255.0.0 10.0.13.2 111"])
	assert_true(_ok(ls), "any AD above 110 floats")

func test_trunk_must_match_native_and_allowed_list():
	var ls := _session("lab.mini_trunk")
	ls.apply("SW1", ["interface g0/1", "switchport mode trunk", "switchport trunk allowed vlan 10,20,99"])
	assert_false(_ok(ls), "native VLAN still 1")
	ls.apply("SW1", ["interface g0/1", "switchport trunk native vlan 99", "switchport trunk allowed vlan 10,20"])
	assert_false(_ok(ls), "native VLAN 99 left out of the allowed list")
	ls.apply("SW1", ["interface g0/1", "switchport trunk allowed vlan add 99"])
	assert_true(_ok(ls), "'add' completes the list")

func test_portfast_alone_is_not_enough():
	var ls := _session("lab.mini_portfast")
	ls.apply("SW1", ["interface range fa0/1 - 8", "spanning-tree portfast"])
	assert_false(_ok(ls), "BPDU Guard missing")
	ls.apply("SW1", ["interface range fa0/1 - 4", "spanning-tree bpduguard enable"])
	assert_false(_ok(ls), "only half the ports guarded")

func test_passive_interface_on_the_wrong_port_breaks_the_adjacency():
	var ls := _session("lab.mini_ospf_passive")
	ls.apply("R1", ["router ospf 1", "passive-interface g0/0"])
	assert_false(_ok(ls), "passive on the link to R2")
	var ls2 := _session("lab.mini_ospf_passive")
	ls2.apply("R1", ["interface g0/1", "shutdown"])
	assert_false(_ok(ls2), "shutting the LAN stops advertising it")

func test_interface_address_needs_the_right_host_and_no_shutdown():
	var ls := _session("lab.mini_iface_ip")
	ls.apply("R1", ["interface g0/1", "ip address 192.168.50.64 255.255.255.192", "no shutdown"])
	assert_false(_ok(ls), "the network address isn't a host address")
	var ls2 := _session("lab.mini_iface_ip")
	ls2.apply("R1", ["interface g0/1", "ip address 192.168.50.65 255.255.255.192"])
	assert_false(_ok(ls2), "still shut down")
	ls2.apply("R1", ["interface g0/1", "no shutdown"])
	assert_true(_ok(ls2))

func test_every_new_cli_question_points_at_a_hidden_lab():
	for id in ["q.d1.subnet.cli.001", "q.d2.vlan.cli.002", "q.d2.stp.cli.002", "q.d3.static.cli.002", "q.d3.ospf.cli.002"]:
		var q: Dictionary = ContentDB.questions[id]
		assert_eq(q.type, "cli_task", id)
		assert_true(ContentDB.labs[q.lab].get("hidden", false), id)
