extends GutTest
## M5 part 2 simulation: HSRP (stateful preempt and tracking), DHCP server and relay,
## SSH prerequisites, NTP/syslog/SNMP, and renamed devices.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _ls(id: String) -> LabSession:
	return LabSession.create(ContentDB.labs[id])

func _state(ls: LabSession, dev: String) -> String:
	return HsrpSim.status(ls.network, dev, "GigabitEthernet0/0", 1).state

func test_hsrp_needs_preempt_to_take_over_from_a_working_active():
	var ls := _ls("lab.hsrp")
	# No query in between: elections must follow the order of the configuration itself.
	ls.apply("R1", ["interface g0/0", "standby 1 ip 10.1.1.1", "standby 1 priority 110"])
	assert_eq(_state(ls, "R1"), "Standby", "higher priority but no preempt")
	assert_eq(_state(ls, "R2"), "Active")
	ls.apply("R1", ["interface g0/0", "standby 1 preempt"])
	assert_eq(_state(ls, "R1"), "Active")
	assert_true(ls.network.owns("R1", "10.1.1.1"), "the active router answers for the virtual IP")
	assert_false(ls.network.owns("R2", "10.1.1.1"))

func test_hsrp_tracking_hands_over_and_back():
	var ls := _ls("lab.hsrp")
	ls.results()
	ls.apply_solution()
	assert_eq(_state(ls, "R1"), "Active")
	ls.apply("R1", ["interface g0/1", "shutdown"])
	assert_eq(_state(ls, "R2"), "Active", "R1 drops to 90; R2 (100) preempts")
	ls.apply("R1", ["interface g0/1", "no shutdown"])
	assert_eq(_state(ls, "R1"), "Active", "R1 back to 110 and preempts")
	var out := CLISession.new(ls.network.devices["R1"], ls.network).execute("show standby brief")
	assert_string_contains(out, "Gi0/0       1    110 P Active  local           10.1.1.3        10.1.1.1")

func test_hsrp_weak_decrement_is_explained():
	var ls := _ls("lab.hsrp")
	ls.apply("R1", ["interface g0/0", "standby 1 ip 10.1.1.1", "standby 1 priority 110", "standby 1 preempt", "standby 1 track g0/1 10"])
	var r := ls.check_task(ContentDB.labs["lab.hsrp"].tasks[2])
	assert_false(r.ok)
	assert_string_contains(r.msg, "only drops to 100")

func test_dhcp_relay_needs_helper_and_a_route_back():
	var ls := _ls("lab.dhcp")
	ls.apply_solution()
	var l := DhcpSim.lease(ls.network, "PC2")
	assert_true(l.ok, l.get("reason", ""))
	assert_eq(l.ip, "192.168.20.11", "first address after the exclusions")
	assert_eq(DhcpSim.lease(ls.network, "PC1").ip, "192.168.10.11")
	ls.apply("R1", ["no ip route 192.168.20.0 255.255.255.0 10.0.12.2"])
	var broken := DhcpSim.lease(ls.network, "PC2")
	assert_false(broken.ok)
	assert_string_contains(broken.reason, "reply back to the relay address")
	assert_string_contains(CLISession.new(ls.network.devices["R1"], ls.network).execute("show ip dhcp binding"), "192.168.10.11")

func test_dhcp_allocates_above_127_net():
	# Regression: Godot's range() truncates to 32 bits, which broke allocation for 128.0.0.0 and up.
	var ls := _ls("lab.mini_helper")
	ls.apply_solution()
	var l := DhcpSim.lease(ls.network, "PC")
	assert_true(l.ok, l.get("reason", ""))
	assert_eq(l.ip, "192.168.30.2", ".1 is excluded")

func test_ssh_prerequisites_in_ios_order():
	var ls := _ls("lab.ssh")
	var s := CLISession.new(ls.network.devices["R1"], ls.network)
	s.mode = "config"
	assert_string_contains(s.execute("crypto key generate rsa modulus 2048"), "hostname other than Router")
	s.execute("hostname EDGE1")
	assert_string_contains(s.execute("crypto key generate rsa modulus 2048"), "domain-name first")
	s.execute("ip domain name lab.local")
	assert_string_contains(s.execute("ip ssh version 2"), "create RSA keys")
	assert_string_contains(s.execute("crypto key generate rsa modulus 2048"), "EDGE1.lab.local")
	assert_eq(s.execute("ip ssh version 2"), "")
	assert_string_contains(Validator.ssh_ready(ls.network.devices["R1"], 2).msg, "username")
	s.execute("username netadmin privilege 15 secret x")
	assert_string_contains(Validator.ssh_ready(ls.network.devices["R1"], 2).msg, "login local")
	s.execute("line vty 0 4")
	s.execute("login local")
	assert_string_contains(Validator.ssh_ready(ls.network.devices["R1"], 2).msg, "Telnet")
	s.execute("transport input ssh")
	assert_true(Validator.ssh_ready(ls.network.devices["R1"], 2).ok)
	assert_string_contains(s.execute("do show ip ssh"), "SSH Enabled - version 2.0")

func test_logging_ntp_snmp_commands():
	var ls := _ls("lab.mgmt_services")
	var s := CLISession.new(ls.network.devices["R1"], ls.network)
	s.mode = "config"
	s.execute("logging trap 4")
	assert_eq(ls.network.devices["R1"].logging_trap, "warnings", "numbers map to names")
	s.execute("logging trap notif")
	assert_eq(ls.network.devices["R1"].logging_trap, "notifications", "abbreviations work")
	s.execute("ntp server 10.0.99.10")
	assert_string_contains(s.execute("do show ntp associations"), "*~10.0.99.10")
	s.execute("snmp-server community NETMON ro 10")
	var cfg := Show.running_config(ls.network.devices["R1"])
	assert_string_contains(cfg, "snmp-server community NETMON RO 10")
	assert_string_contains(cfg, "ntp server 10.0.99.10")

func test_renamed_device_still_works_with_network_commands():
	# Regression: network lookups used the hostname, so 'hostname X' broke show/ping commands.
	var ls := _ls("lab.discovery")
	var s := CLISession.new(ls.network.devices["SW1"], ls.network)
	s.mode = "config"
	s.execute("hostname CORE-SW")
	assert_string_contains(s.execute("do show cdp neighbors"), "R1")
	var ospf := _ls("lab.ospf")
	ospf.apply_solution()
	var r := CLISession.new(ospf.network.devices["R1"], ospf.network)
	r.mode = "config"
	r.execute("hostname HQ")
	assert_string_contains(r.execute("do ping 192.168.3.1"), "!!!!!")
	assert_string_contains(r.execute("do show ip route"), "192.168.3.0/24 [110/3]")

func test_device_hardening_commands_and_checks():
	var ls := _ls("lab.device_hardening")
	var d: Device = ls.network.devices["R1"]
	assert_string_contains(Validator.run(ls.network, {"device": "R1", "check": "enable_secret", "args": {}}).msg, "enable password")
	ls.apply("R1", ["enable secret S3cret!", "line console 0", "password Con!", "login", "exec-timeout 5 0"])
	assert_true(Validator.run(ls.network, {"device": "R1", "check": "enable_secret", "args": {}}).ok)
	assert_true(Validator.run(ls.network, {"device": "R1", "check": "line_auth", "args": {"line": "console 0", "password": true, "login": "login", "timeout": 5}}).ok)
	var cfg := Show.running_config(d)
	assert_string_contains(cfg, "enable password cisco", "clear text before encryption")
	assert_string_contains(cfg, " exec-timeout 5 0")
	ls.apply("R1", ["service password-encryption"])
	cfg = Show.running_config(d)
	assert_false(cfg.contains("enable password cisco"))
	assert_false(cfg.contains(" password Con!"))
	var vty := Validator.run(ls.network, {"device": "R1", "check": "line_auth", "args": {"line": "vty 0 4", "login": "login local"}})
	assert_string_contains(vty.msg, "isn't configured")
