extends GutTest
## CDP and LLDP in the simulator: who sees whom, per-port and global controls, show output.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _ls() -> LabSession:
	return LabSession.create(ContentDB.labs["lab.discovery"])

func _names(ls: LabSession, proto: String) -> Array:
	var n: Array = Discovery.neighbors(ls.network, "SW1", proto).map(func(x): return x.device)
	n.sort()
	return n

func test_cdp_sees_only_cisco_neighbours_by_default():
	var ls := _ls()
	assert_eq(_names(ls, "cdp"), ["R1", "SW2"])
	assert_eq(_names(ls, "lldp"), [], "LLDP is off by default")
	var out := CLISession.new(ls.network.devices["SW1"], ls.network).execute("show cdp neighbors")
	assert_string_contains(out, "R1               Gig 0/2")
	assert_string_contains(out, "Gig 0/0/0")

func test_lldp_needs_run_and_respects_transmit_receive():
	var ls := _ls()
	ls.apply("SW1", ["lldp run"])
	assert_eq(_names(ls, "lldp"), ["AP-LOBBY", "KIOSK", "PHONE-114"], "Cisco R1/SW2 don't run LLDP")
	ls.apply("SW1", ["interface fa0/7", "no lldp receive"])
	assert_false("AP-LOBBY" in _names(ls, "lldp"))
	var s := CLISession.new(ls.network.devices["SW1"], ls.network)
	assert_string_contains(s.execute("show lldp neighbors"), "PHONE-114")
	assert_string_contains(s.execute("show lldp neighbors"), "T")

func test_cdp_controls_and_running_config():
	var ls := _ls()
	ls.apply("SW1", ["interface g0/2", "no cdp enable"])
	assert_eq(_names(ls, "cdp"), ["SW2"])
	ls.apply("SW1", ["no cdp run"])
	assert_eq(_names(ls, "cdp"), [])
	var s := CLISession.new(ls.network.devices["SW1"], ls.network)
	assert_eq(s.execute("show cdp neighbors"), "% CDP is not enabled")
	var cfg := Show.running_config(ls.network.devices["SW1"])
	assert_string_contains(cfg, "no cdp run")
	assert_string_contains(cfg, " no cdp enable")

func test_cdp_detail_shows_address_and_shut_port_hides_neighbour():
	var ls := _ls()
	var s := CLISession.new(ls.network.devices["SW1"], ls.network)
	assert_string_contains(s.execute("show cdp neighbors detail"), "IP address: 10.0.0.1")
	ls.apply("R1", ["interface g0/0/0", "shutdown"])
	assert_false("R1" in _names(ls, "cdp"))
