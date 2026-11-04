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

func test_port_security_must_keep_the_defaults():
	var ls := _session("lab.mini_port_security")
	ls.apply("SW1", ["interface fa0/7", "switchport port-security", "switchport port-security maximum 2", "switchport port-security mac-address sticky"])
	assert_false(_ok(ls), "maximum 2 lets a second device in")
	var ls2 := _session("lab.mini_port_security")
	ls2.apply("SW1", ["interface fa0/7", "switchport port-security", "switchport port-security mac-address sticky", "switchport port-security violation restrict"])
	assert_false(_ok(ls2), "restrict keeps the port up")
	var ls3 := _session("lab.mini_port_security")
	ls3.apply("SW1", ["interface fa0/7", "switchport port-security"])
	assert_false(_ok(ls3), "without sticky nothing is saved")

func test_standard_acl_needs_permit_any_and_the_right_place():
	var ls := _session("lab.mini_acl")
	ls.apply("R1", ["access-list 5 deny host 192.168.10.66", "interface g0/1", "ip access-group 5 out"])
	assert_false(_ok(ls), "the implicit deny blocks everyone else")
	var ls2 := _session("lab.mini_acl")
	ls2.apply("R1", ["access-list 5 deny host 192.168.10.66", "access-list 5 permit any", "interface g0/0", "ip access-group 5 in"])
	assert_false(_ok(ls2), "applied at the source side, not near the servers")
	var ls3 := _session("lab.mini_acl")
	ls3.apply("R1", ["access-list 5 permit any", "access-list 5 deny host 192.168.10.66", "interface g0/1", "ip access-group 5 out"])
	assert_false(_ok(ls3), "the deny after 'permit any' is never reached")

func test_static_nat_needs_both_interfaces_marked():
	var ls := _session("lab.mini_static_nat")
	ls.apply("R1", ["ip nat inside source static 192.168.1.20 203.0.113.4", "interface g0/0", "ip nat inside"])
	assert_false(_ok(ls), "outside interface not marked")
	var ls2 := _session("lab.mini_static_nat")
	ls2.apply("R1", ["interface g0/0", "ip nat outside", "interface g0/1", "ip nat inside", "exit", "ip nat inside source static 192.168.1.20 203.0.113.4"])
	assert_false(_ok(ls2), "inside and outside swapped")

func test_ssh_lab_rejects_telnet_and_version_one():
	var ls := _session("lab.mini_ssh")
	ls.apply("R1", ["crypto key generate rsa modulus 2048", "username admin privilege 15 secret x", "line vty 0 4", "login local", "transport input ssh"])
	assert_false(_ok(ls), "version 2 not enforced")
	ls.apply("R1", ["ip ssh version 2", "line vty 0 4", "transport input ssh telnet"])
	assert_false(_ok(ls), "Telnet still allowed")
	ls.apply("R1", ["line vty 0 4", "transport input ssh"])
	assert_true(_ok(ls))

func test_every_new_cli_question_points_at_a_hidden_lab():
	for id in ["q.d1.subnet.cli.001", "q.d2.vlan.cli.002", "q.d2.stp.cli.002", "q.d3.static.cli.002", "q.d3.ospf.cli.002",
			"q.d5.acl.cli.001", "q.d5.ps.cli.001", "q.d4.nat.cli.001", "q.d4.ssh.cli.001"]:
		var q: Dictionary = ContentDB.questions[id]
		assert_eq(q.type, "cli_task", id)
		assert_true(ContentDB.labs[q.lab].get("hidden", false), id)

func test_transport_input_accepts_several_protocols():
	var ls := _session("lab.mini_ssh")
	var d: Device = ls.network.devices["R1"]
	assert_eq(ls.apply("R1", ["line vty 0 4", "transport input telnet ssh"]).size(), 0)
	assert_eq(d.lines["vty 0 4"].transport, "ssh telnet", "stored in a fixed order")
	ls.apply("R1", ["line vty 0 4", "transport input all"])
	assert_eq(d.lines["vty 0 4"].transport, "all")
	assert_gt(ls.apply("R1", ["line vty 0 4", "transport input all ssh"], true).size(), 0, "all can't be combined")
	assert_gt(ls.apply("R1", ["line vty 0 4", "transport input rlogin"], true).size(), 0, "unknown protocol rejected")
	assert_eq(d.lines["vty 0 4"].transport, "all", "a rejected command changes nothing")
