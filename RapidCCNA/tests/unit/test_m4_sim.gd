extends GutTest
## M4 IOS simulation: OSPF, EtherChannel and spanning tree commands, show output and
## network-wide behaviour (adjacencies, SPF, bundling, re-convergence).

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _lab(id: String) -> LabSession:
	return LabSession.create(ContentDB.labs[id])

func _run(s: CLISession, lines: Array) -> String:
	var out := ""
	for l in lines:
		out = s.execute(l)
	return out

func _cli(ls: LabSession, dev: String) -> CLISession:
	var s := CLISession.new(ls.network.devices[dev], ls.network)
	s.mode = "priv"
	return s

func test_ospf_abbreviations_and_router_mode():
	var ls := _lab("lab.mini_ospf")
	var s := _cli(ls, "R1")
	_run(s, ["conf t", "router os 1"])
	assert_eq(s.prompt(), "R1(config-router)#")
	assert_eq(_run(s, ["net 10.0.0.0 0.0.0.3 a 0"]), "")
	assert_string_contains(s.execute("?"), "passive-interface")
	assert_string_contains(_run(s, ["do sh ip ospf nei"]), "FULL/")
	assert_true(ls.all_ok())
	_run(s, ["exit"])
	assert_eq(s.prompt(), "R1(config)#")

func test_interface_mode_ospf_and_timers():
	var ls := _lab("lab.mini_ospf")
	var s := _cli(ls, "R1")
	_run(s, ["conf t", "interface g0/0", "ip ospf 1 area 0"])
	assert_eq(s.prompt(), "R1(config-if)#", "stays in interface mode")
	assert_true(ls.all_ok(), "ip ospf <pid> area <id> enables OSPF without a network statement")
	_run(s, ["ip ospf hello-interval 5"])
	var i: Dictionary = ls.network.devices["R1"].interfaces["GigabitEthernet0/0"]
	assert_eq(i.ospf_dead, 20, "Dead follows 4 x Hello")
	assert_false(ls.all_ok(), "timer mismatch drops the adjacency")
	assert_string_contains(Validator.run(ls.network, {"device": "R1", "check": "ospf_neighbor", "args": {"neighbor": "R2"}}).msg, "hello/dead")
	assert_string_contains(Show.running_config(ls.network.devices["R1"]), " ip ospf hello-interval 5")

func test_passive_interface_default_with_exception():
	var ls := _lab("lab.mini_ospf")
	var s := _cli(ls, "R1")
	_run(s, ["conf t", "router ospf 1", "network 10.0.0.0 0.0.0.3 area 0", "passive-interface default"])
	assert_false(ls.all_ok(), "passive everywhere: no neighbours")
	_run(s, ["no passive-interface g0/0"])
	assert_true(ls.all_ok())
	assert_string_contains(Show.running_config(ls.network.devices["R1"]), " no passive-interface GigabitEthernet0/0")

func test_ospf_routes_withdraw_when_link_fails():
	var ls := _lab("lab.ospf")
	ls.apply_solution()
	var r1: Device = ls.network.devices["R1"]
	assert_eq(r1.routing_table().lookup(IPv4.parse("192.168.3.1")).code, "O")
	assert_eq(r1.routing_table().lookup(IPv4.parse("3.3.3.3")).len, 32, "loopbacks are advertised as /32")
	var only_o := _cli(ls, "R1").execute("show ip route ospf")
	assert_string_contains(only_o, "O      192.168.3.0/24 [110/3] via 10.0.12.2")
	assert_false(only_o.contains("is directly connected"), "connected routes are filtered out")
	ls.apply("R2", ["interface g0/0", "shutdown"])
	assert_eq(OspfSim.neighbors(ls.network, "R1").size(), 0)
	assert_eq(r1.routing_table().lookup(IPv4.parse("192.168.3.1")).code, "S", "falls back to the static default")

func test_ospf_cost_reference_bandwidth_and_show():
	var ls := _lab("lab.ospf")
	ls.apply_solution()
	var s := _cli(ls, "R1")
	assert_string_contains(_run(s, ["conf t", "router ospf 1", "auto-cost reference-bandwidth 10000"]), "Reference bandwidth is changed")
	assert_eq(OspfSim.enabled(ls.network.devices["R1"])["GigabitEthernet0/0"].cost, 10)
	assert_string_contains(_run(s, ["end", "show ip ospf interface brief"]), "10.0.12.1/30")
	assert_string_contains(s.execute("show ip ospf interface g0/0"), "Cost: 10")
	assert_string_contains(s.execute("show ip protocols"), "Reference bandwidth unit is 10000 mbps")
	assert_string_contains(_cli(ls, "R3").execute("show ip route"), "O*E2")

func test_channel_group_abbreviation_protocol_mismatch_and_suspend():
	var ls := _lab("lab.etherchannel")
	var s := _cli(ls, "SW1")
	assert_string_contains(_run(s, ["conf t", "int g0/1", "channel-group 1 mode act"]), "Creating a port-channel interface Port-channel 1")
	assert_eq(ls.network.devices["SW1"].interfaces["GigabitEthernet0/1"].channel_mode, "active")
	assert_string_contains(_run(s, ["int g0/2", "channel-group 1 mode desirable"]), "protocol mismatch")
	_run(s, ["channel-group 1 mode active"])
	assert_eq(L2Sim.channel(ls.network, "SW1", 1).members.map(func(m): return m.flag), ["P", "P"])
	_run(s, ["switchport mode trunk"])
	var c := L2Sim.channel(ls.network, "SW1", 1)
	assert_eq(c.members[1].flag, "s", "a member that differs from the port-channel is suspended")
	assert_string_contains(_run(s, ["end", "show etherchannel summary"]), "Gi0/2(s)")
	assert_eq(Commands.parse_range(ls.network.devices["SW1"], "po1"), ["Port-channel1"])

func test_stp_root_primary_and_priority_rules():
	var ls := _lab("lab.stp")
	var s := _cli(ls, "SW2")
	assert_eq(L2Sim.stp(ls.network, 10).root, "SW3", "lowest MAC wins with default priorities")
	assert_string_contains(_run(s, ["conf t", "spanning-tree vlan 10 priority 100"]), "increments of 4096")
	ls.apply("SW3", ["spanning-tree vlan 10 priority 20480"])
	_run(s, ["spanning-tree vlan 10 root primary"])
	assert_eq(ls.network.devices["SW2"].stp_priority[10], 16384, "4096 below the current root")
	assert_eq(L2Sim.stp(ls.network, 10).root, "SW2")

func test_stp_reconverges_when_root_port_fails():
	var ls := _lab("lab.stp")
	ls.apply_solution()
	# VLAN 10: SW1 root. SW3 reaches it directly on Gi0/1; its Gi0/2 link to SW2 blocks.
	assert_eq(L2Sim.role(ls.network, "SW3", "GigabitEthernet0/1", 10), "Root")
	assert_eq(L2Sim.role(ls.network, "SW3", "GigabitEthernet0/2", 10), "Alternate")
	ls.apply("SW1", ["interface g0/2", "shutdown"])
	assert_eq(L2Sim.role(ls.network, "SW3", "GigabitEthernet0/2", 10), "Root", "the alternate port takes over")
	var out := _cli(ls, "SW3").execute("show spanning-tree vlan 10")
	assert_string_contains(out, "Gi0/2               Root FWD")
	assert_string_contains(_cli(ls, "SW1").execute("show spanning-tree vlan 10"), "P2p Edge")

func test_stp_runs_over_a_port_channel():
	var ls := _lab("lab.etherchannel")
	ls.apply_solution()
	var res := L2Sim.stp(ls.network, 10)
	assert_eq(res.roles.size(), 2, "the bundle is one logical link: %s" % res.roles)
	assert_true(res.roles.has("SW1 Port-channel1"))
	assert_false(STP.blocked(res).size() > 0, "nothing blocks across a bundle")
