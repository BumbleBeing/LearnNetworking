extends GutTest
## IOS CLI behaviour: modes, abbreviations, errors, help, completion and handlers.

func _switch() -> CLISession:
	var ifs: Array = []
	for i in range(1, 9):
		ifs.append({"name": "fa0/%d" % i})
	ifs.append({"name": "g0/1"})
	return CLISession.new(Device.create({"name": "SW1", "type": "switch", "interfaces": ifs}))

func _router() -> CLISession:
	return CLISession.new(Device.create({"name": "R1", "type": "router", "interfaces": [{"name": "g0/0"}, {"name": "g0/1", "link": false}]}))

func _run(s: CLISession, lines: Array) -> String:
	var out := ""
	for l in lines:
		out = s.execute(l)
	return out

func test_canonical_interface_names():
	assert_eq(Device.canon_iface("g0/0"), "GigabitEthernet0/0")
	assert_eq(Device.canon_iface("Gi 0/1"), "GigabitEthernet0/1")
	assert_eq(Device.canon_iface("fa0/24"), "FastEthernet0/24")
	assert_eq(Device.canon_iface("lo0"), "Loopback0")
	assert_eq(Device.canon_iface("vlan 10"), "Vlan10")
	assert_eq(Device.canon_iface("s0/0/0"), "Serial0/0/0")
	assert_eq(Device.canon_iface("x0/1"), "")
	assert_eq(Device.canon_iface("g"), "")

func test_modes_and_prompts():
	var s := _router()
	assert_eq(s.prompt(), "R1>")
	_run(s, ["en"])
	assert_eq(s.prompt(), "R1#")
	assert_string_contains(s.execute("conf t"), "Enter configuration commands")
	assert_eq(s.prompt(), "R1(config)#")
	_run(s, ["int g0/0"])
	assert_eq(s.prompt(), "R1(config-if)#")
	_run(s, ["exit"])
	assert_eq(s.prompt(), "R1(config)#")
	_run(s, ["int g0/0", "end"])
	assert_eq(s.prompt(), "R1#")
	_run(s, ["disable"])
	assert_eq(s.prompt(), "R1>")

func test_config_commands_need_config_mode():
	var s := _router()
	assert_string_contains(s.execute("conf t"), "Invalid input", "user mode can't configure")
	_run(s, ["en"])
	assert_string_contains(s.execute("hostname X"), "Invalid input")

func test_errors_point_at_bad_token():
	var s := _router()
	_run(s, ["en", "conf t", "int g0/0"])
	var out := s.execute("ip adress 10.0.0.1 255.255.255.0")
	var caret := out.split("\n")[0]
	assert_eq(caret.length() - 1, "R1(config-if)#ip ".length(), "caret under 'adress'")
	assert_eq(s.execute("ip address"), "% Incomplete command.")
	assert_string_contains(s.execute("s"), "Ambiguous command")

func test_hostname_and_global_commands_from_submode():
	var s := _router()
	_run(s, ["en", "conf t", "int g0/0", "hostname EDGE"])
	assert_eq(s.prompt(), "EDGE(config)#", "global command from (config-if) drops back to (config)")

func test_do_runs_exec_commands():
	var s := _router()
	_run(s, ["en", "conf t"])
	assert_string_contains(s.execute("do sh ip int br"), "GigabitEthernet0/0")
	assert_eq(s.prompt(), "R1(config)#")

func test_interface_ip_and_state_messages():
	var s := _router()
	_run(s, ["en", "conf t", "int g0/0", "ip add 10.0.0.1 255.255.255.252"])
	assert_string_contains(s.execute("no shut"), "changed state to up")
	assert_eq(s.execute("ip address 10.0.0.0 255.255.255.252"), "Bad mask /30 for address 10.0.0.0")
	_run(s, ["int g0/1"])
	assert_string_contains(s.execute("ip address 10.0.0.2 255.255.255.0"), "overlaps with GigabitEthernet0/0")
	assert_eq(s.execute("no shutdown"), "", "no cable: no up message")
	var brief := s.execute("do show ip interface brief")
	assert_string_contains(brief, "GigabitEthernet0/0     10.0.0.1        YES manual up")
	assert_string_contains(brief, "GigabitEthernet0/1     unassigned      YES unset  down")

func test_switch_rejects_ip_on_physical_port_and_dynamic_port_security():
	var s := _switch()
	_run(s, ["en", "conf t", "int fa0/1"])
	assert_string_contains(s.execute("ip address 10.0.0.1 255.255.255.0"), "Invalid input")
	assert_eq(s.execute("switchport port-security"), "Command rejected: FastEthernet0/1 is a dynamic port.")
	_run(s, ["sw mode access"])
	assert_eq(s.execute("switchport port-security"), "")

func test_access_vlan_created_on_demand_and_vlan_brief():
	var s := _switch()
	_run(s, ["en", "conf t", "int range fa0/1 - 3", "sw mode acc"])
	assert_eq(s.execute("sw acc vlan 30"), "% Access VLAN does not exist. Creating vlan 30")
	var brief := s.execute("do sh vlan br")
	assert_string_contains(brief, "30   VLAN0030")
	assert_string_contains(brief, "Fa0/1, Fa0/2, Fa0/3")

func test_trunk_allowed_add_and_remove():
	var s := _switch()
	_run(s, ["en", "conf t", "int g0/1", "sw mode trunk", "sw trunk allowed vlan 10,20", "sw trunk allowed vlan add 30-32", "sw trunk allowed vlan remove 20"])
	assert_eq(s.device.interfaces["GigabitEthernet0/1"].allowed, "10,30-32")
	assert_string_contains(s.execute("do show interfaces trunk"), "10,30-32")

func test_interface_range_parsing():
	var d := _switch().device
	assert_eq(Commands.parse_range(d, "fa0/1 - 3, fa0/7").size(), 4)
	assert_eq(Commands.parse_range(d, "fa0/1-8").size(), 8)
	assert_eq(Commands.parse_range(d, "fa0/1 - 30"), [], "ports that don't exist")
	assert_eq(Commands.parse_range(d, "fa0/5 - 2"), [])

func test_help_and_completion():
	var s := _router()
	_run(s, ["en"])
	assert_string_contains(s.help("sh?"), "show")
	var h := s.help("show ip ?")
	assert_string_contains(h, "route")
	assert_string_contains(h, "interface")
	assert_eq(s.complete("sh ip int b"), "sh ip int brief ")
	assert_eq(s.complete("conf"), "configure ")
	_run(s, ["conf t"])
	assert_string_contains(s.help("ip route ?"), "A.B.C.D")
	assert_string_contains(s.help("hostname R2 ?"), "<cr>")

func test_static_routes_and_validation():
	var s := _router()
	_run(s, ["en", "conf t", "int g0/0", "ip add 10.0.0.1 255.255.255.252", "no shut", "exit"])
	assert_eq(s.execute("ip route 192.168.3.1 255.255.255.0 10.0.0.2"), "%Inconsistent address and mask")
	_run(s, ["ip route 192.168.3.0 255.255.255.0 10.0.0.2", "ip route 172.16.0.0 255.255.0.0 10.9.9.9"])
	var rt := s.device.routing_table()
	assert_eq(rt.lookup(IPv4.parse("192.168.3.5")).next_hop, "10.0.0.2")
	assert_true(rt.lookup(IPv4.parse("172.16.1.1")).is_empty(), "unreachable next hop: not installed")
	assert_string_contains(s.execute("do show ip route"), "S      192.168.3.0/24 [1/0] via 10.0.0.2")

func test_acl_commands():
	var s := _router()
	_run(s, ["en", "conf t", "access-list 10 permit 192.168.1.0 0.0.0.255", "ip access-list extended WEB", "permit tcp any host 10.1.1.1 eq 443", "deny ip any any"])
	assert_eq(s.prompt(), "R1(config-ext-nacl)#")
	assert_string_contains(s.execute("permit tcp any"), "Invalid input")
	var out := s.execute("do show access-lists")
	assert_string_contains(out, "Standard IP access list 10")
	assert_string_contains(out, "Extended IP access list WEB\n    10 permit tcp any host 10.1.1.1 eq 443\n    20 deny ip any any")
	assert_string_contains(s.execute("access-list 300 permit any"), "Invalid input")

func test_running_config_reflects_state():
	var s := _router()
	_run(s, ["en", "conf t", "hostname EDGE", "int g0/0", "description uplink", "ip add 10.0.0.1 255.255.255.0", "ip nat outside", "no shut", "end"])
	var run := s.execute("show run")
	assert_string_contains(run, "hostname EDGE")
	assert_string_contains(run, "interface GigabitEthernet0/0\n description uplink\n ip address 10.0.0.1 255.255.255.0\n ip nat outside\n!")
	assert_string_contains(run, "interface GigabitEthernet0/1\n no ip address\n shutdown")
