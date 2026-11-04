extends GutTest
## M8 IOS simulation: "show | include/exclude/begin/section/count", OSPF router IDs that
## change only after "clear ip ospf process", and equal-cost paths (ECMP).

const OSPF_ALL := ["router ospf 1", "network 0.0.0.0 255.255.255.255 area 0"]

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _run(s: CLISession, lines: Array) -> String:
	var out := ""
	for l in lines:
		out = s.execute(l)
	return out

func _cli(ls: LabSession, dev: String) -> CLISession:
	var s := CLISession.new(ls.network.devices[dev], ls.network)
	s.mode = "priv"
	return s

func _router(dev_name: String, ifaces: Array, config: Array = OSPF_ALL) -> Dictionary:
	return {"name": dev_name, "type": "router", "editable": true, "interfaces": ifaces, "config": config}

func _if(n: String, ip: String, mask: String = "255.255.255.252") -> Dictionary:
	return {"name": n, "ip": ip, "mask": mask, "shutdown": false}

## R1 reaches R4's LAN through R2 or R3 at the same cost.
##   R1 g0/0 -- g0/0 R2 g0/1 -- g0/0 R4 g0/2 (192.168.4.0/24)
##   R1 g0/1 -- g0/0 R3 g0/1 -- g0/1 R4
func _square() -> LabSession:
	return LabSession.create({"id": "test.square", "devices": [
		_router("R1", [_if("g0/0", "10.0.12.1"), _if("g0/1", "10.0.13.1")]),
		_router("R2", [_if("g0/0", "10.0.12.2"), _if("g0/1", "10.0.24.1")]),
		_router("R3", [_if("g0/0", "10.0.13.2"), _if("g0/1", "10.0.34.1")]),
		_router("R4", [_if("g0/0", "10.0.24.2"), _if("g0/1", "10.0.34.2"), _if("g0/2", "192.168.4.1", "255.255.255.0")]),
	], "links": [["R1", "g0/0", "R2", "g0/0"], ["R1", "g0/1", "R3", "g0/0"], ["R2", "g0/1", "R4", "g0/0"], ["R3", "g0/1", "R4", "g0/1"]]})

# --- Output modifiers -----------------------------------------------------------------

func test_include_exclude_and_abbreviations():
	var ls := _square()
	var s := _cli(ls, "R1")
	assert_eq(s.execute("show running-config | include hostname"), "hostname R1")
	assert_eq(s.execute("sh run | i hostname"), "hostname R1", "sh run | i")
	assert_eq(s.execute("sh run | i Hostname"), "", "regular expressions are case-sensitive, like IOS")
	var brief := s.execute("show ip interface brief | exclude unassigned")
	assert_string_contains(brief, "10.0.12.1")
	assert_false(brief.contains("unassigned"))
	assert_eq(s.execute("show ip int brief | include ^Gig").split("\n").size(), 2, "anchored regex")
	assert_eq(s.history.back(), "show ip int brief | include ^Gig", "history keeps the whole line once")

func test_begin_section_and_count():
	var ls := _square()
	var s := _cli(ls, "R1")
	var sec := s.execute("show running-config | section router ospf")
	assert_true(sec.begins_with("router ospf 1"), sec)
	assert_string_contains(sec, " network 0.0.0.0 255.255.255.255 area 0")
	assert_false(sec.contains("interface"), "only the matching block")
	var from := s.execute("show run | begin router ospf")
	assert_true(from.begins_with("router ospf 1"), from)
	assert_eq(s.execute("show ip route | count via"), "Number of lines which match regexp = %d" % s.execute("show ip route | include via").split("\n").size())

func test_pipe_from_config_mode_and_errors():
	var ls := _square()
	var s := _cli(ls, "R1")
	_run(s, ["conf t", "interface g0/0"])
	assert_eq(s.execute("do show run | i hostname"), "hostname R1", "do show works with a pipe")
	assert_eq(s.prompt(), "R1(config-if)#")
	_run(s, ["end"])
	assert_string_contains(s.execute("ping 10.0.12.2 | include !"), "% Invalid input", "only show commands take a pipe")
	var bad := s.execute("show run | frobnicate x")
	assert_string_contains(bad, "% Invalid input")
	assert_eq(bad.find("^"), s.prompt().length() + "show run | ".length(), "caret under the bad modifier")
	assert_eq(s.execute("show run | include"), "% Incomplete command.")
	assert_eq(s.execute("show run |"), "% Incomplete command.")

func test_pipe_help_and_completion():
	var ls := _square()
	var s := _cli(ls, "R1")
	var mods := s.help("show running-config | ?")
	for k in ["begin", "count", "exclude", "include", "section"]:
		assert_string_contains(mods, k)
	assert_string_contains(s.help("show running-config ?"), "Output modifiers", "'|' is offered once the show command is complete")
	assert_false(s.help("configure ?").contains("Output modifiers"))
	assert_eq(s.help("show run | inc?"), "include")
	assert_string_contains(s.help("show run | include ?"), "Regular Expression")
	assert_eq(s.complete("show run | sec"), "show run | section ")

# --- Router ID ------------------------------------------------------------------------

func test_new_loopback_does_not_change_a_running_router_id():
	var ls := _square()
	var s := _cli(ls, "R1")
	var r1: Device = ls.network.devices["R1"]
	assert_eq(OspfSim.router_id(r1), "10.0.13.1", "highest interface address at boot")
	_run(s, ["conf t", "interface loopback 0", "ip address 1.1.1.1 255.255.255.255", "end"])
	assert_eq(OspfSim.router_id(r1), "10.0.13.1", "a new loopback waits for a process restart")
	assert_string_contains(s.execute("show ip protocols"), "Router ID 10.0.13.1")
	assert_string_contains(s.execute("clear ip ospf process"), "Reset ALL OSPF processes")
	assert_eq(OspfSim.router_id(r1), "1.1.1.1", "clear ip ospf process picks the loopback")
	assert_eq(ls.network.devices["R2"].routing_table().paths(IPv4.parse("10.0.13.1")).size(), 1, "the network re-converges")

func test_router_id_command_waits_for_clear_when_neighbours_are_up():
	var ls := _square()
	var s := _cli(ls, "R1")
	var r1: Device = ls.network.devices["R1"]
	var out := _run(s, ["conf t", "router ospf 1", "router-id 9.9.9.9"])
	assert_eq(out, '% OSPF: Reload or use "clear ip ospf process" command, for this to take effect')
	assert_eq(OspfSim.router_id(r1), "10.0.13.1", "the old ID stays while neighbours are up")
	assert_string_contains(Show.running_config(r1), " router-id 9.9.9.9", "but the command is in the config")
	_run(s, ["do clear ip ospf process"])
	assert_eq(OspfSim.router_id(r1), "9.9.9.9")
	assert_string_contains(_cli(ls, "R2").execute("show ip ospf neighbor"), "9.9.9.9")
	assert_eq(_run(s, ["no router-id"]), '% OSPF: Reload or use "clear ip ospf process" command, for this to take effect')

func test_router_id_applies_at_once_without_neighbours():
	var ls := LabSession.create({"id": "test.alone", "devices": [_router("R1", [_if("g0/0", "10.0.0.1")], [])], "links": []})
	var s := _cli(ls, "R1")
	var r1: Device = ls.network.devices["R1"]
	assert_eq(_run(s, ["conf t", "router ospf 1"]), "")
	assert_eq(OspfSim.router_id(r1), "10.0.0.1", "the process starts with the interface address")
	assert_eq(_run(s, ["router-id 1.1.1.1"]), "", "no neighbours yet, so no warning")
	assert_eq(OspfSim.router_id(r1), "1.1.1.1")
	_run(s, ["exit", "no router ospf 1", "router ospf 1"])
	assert_eq(OspfSim.router_id(r1), "10.0.0.1", "a new process picks its ID again")

func test_startup_configs_load_like_a_boot():
	# R1's router-id line comes after its network statement, and R2 is configured before R1.
	# On a real router the whole startup config is read before OSPF starts.
	var ls := LabSession.create({"id": "test.boot", "devices": [
		_router("R2", [_if("g0/0", "10.0.0.2")]),
		_router("R1", [_if("g0/0", "10.0.0.1")], OSPF_ALL + ["router-id 1.1.1.1"]),
	], "links": [["R1", "g0/0", "R2", "g0/0"]]})
	assert_eq(OspfSim.router_id(ls.network.devices["R1"]), "1.1.1.1")
	assert_string_contains(_cli(ls, "R2").execute("show ip ospf neighbor"), "1.1.1.1")

func test_ospf_lab_solution_still_sets_the_router_id():
	var ls := LabSession.create(ContentDB.labs["lab.ospf"])
	assert_eq(ls.apply_solution().size(), 0)
	assert_true(ls.all_ok(), "router-id straight after 'router ospf 1' applies, as there are no neighbours yet")

# --- Equal-cost paths -----------------------------------------------------------------

func test_equal_cost_ospf_paths_are_all_installed():
	var ls := _square()
	var rt: RoutingTable = ls.network.devices["R1"].routing_table()
	var paths := rt.paths(IPv4.parse("192.168.4.10"))
	assert_eq(paths.map(func(r): return r.next_hop), ["10.0.12.2", "10.0.13.2"])
	assert_eq(paths.map(func(r): return r.metric), [3, 3])
	assert_eq(rt.lookup(IPv4.parse("192.168.4.10")).next_hop, "10.0.12.2", "forwarding picks one path repeatably")
	assert_eq(rt.paths(IPv4.parse("10.0.24.1")).size(), 1, "the R2-R4 link is closer through R2")

func test_show_ip_route_lists_each_path():
	var ls := _square()
	var s := _cli(ls, "R1")
	var lines := s.execute("show ip route").split("\n")
	var at := Array(lines).find("O      192.168.4.0/24 [110/3] via 10.0.12.2, GigabitEthernet0/0")
	assert_gt(at, 0, "\n".join(lines))
	var second := lines[at + 1]
	assert_eq(second.strip_edges(), "[110/3] via 10.0.13.2, GigabitEthernet0/1")
	assert_eq(second.find("["), lines[at].find("["), "the second path lines up under the first")
	var ospf_only := s.execute("show ip route ospf")
	assert_string_contains(ospf_only, "[110/3] via 10.0.13.2", "show ip route ospf keeps the extra path")
	assert_false(ospf_only.contains("directly connected"))

func test_unequal_costs_install_one_path():
	var ls := _square()
	_run(_cli(ls, "R1"), ["conf t", "interface g0/1", "ip ospf cost 5"])
	var paths: Array = ls.network.devices["R1"].routing_table().paths(IPv4.parse("192.168.4.10"))
	assert_eq(paths.map(func(r): return r.next_hop), ["10.0.12.2"])

func test_at_most_four_ospf_paths():
	# R1 reaches R6's LAN through five routers at the same cost.
	var devs: Array = []
	var links: Array = []
	var r1_ifs: Array = []
	var r6_ifs: Array = [_if("g0/9", "192.168.6.1", "255.255.255.0")]
	for i in 5:
		var mid := "M%d" % i
		r1_ifs.append(_if("g0/%d" % i, "10.1.%d.1" % i))
		r6_ifs.append(_if("g0/%d" % i, "10.2.%d.2" % i))
		devs.append(_router(mid, [_if("g0/0", "10.1.%d.2" % i), _if("g0/1", "10.2.%d.1" % i)]))
		links.append(["R1", "g0/%d" % i, mid, "g0/0"])
		links.append([mid, "g0/1", "R6", "g0/%d" % i])
	devs.append(_router("R1", r1_ifs))
	devs.append(_router("R6", r6_ifs))
	var ls := LabSession.create({"id": "test.fan", "devices": devs, "links": links})
	var paths: Array = ls.network.devices["R1"].routing_table().paths(IPv4.parse("192.168.6.1"))
	assert_eq(paths.size(), OspfSim.MAX_PATHS, "IOS installs 4 equal-cost OSPF paths by default")
	assert_eq(paths[0].next_hop, "10.1.0.2")

func test_equal_static_routes_load_share_but_a_floating_one_waits():
	var ls := _square()
	var s := _cli(ls, "R1")
	_run(s, ["conf t", "ip route 172.16.0.0 255.255.0.0 10.0.13.2", "ip route 172.16.0.0 255.255.0.0 10.0.12.2"])
	var rt: RoutingTable = ls.network.devices["R1"].routing_table()
	assert_eq(rt.paths(IPv4.parse("172.16.1.1")).map(func(r): return r.next_hop), ["10.0.12.2", "10.0.13.2"])
	_run(s, ["no ip route 172.16.0.0 255.255.0.0 10.0.12.2", "ip route 172.16.0.0 255.255.0.0 10.0.12.2 200"])
	rt = ls.network.devices["R1"].routing_table()
	assert_eq(rt.paths(IPv4.parse("172.16.1.1")).map(func(r): return r.next_hop), ["10.0.13.2"], "AD 200 is a backup, not a second path")

func test_route_to_check_accepts_any_equal_path():
	var ls := _square()
	for hop in ["10.0.12.2", "10.0.13.2"]:
		assert_true(Validator.run(ls.network, {"device": "R1", "check": "route_to", "args": {"dest": "192.168.4.1", "next_hop": hop}}).ok, hop)
	assert_true(Validator.run(ls.network, {"device": "R1", "check": "route_to", "args": {"dest": "192.168.4.1", "paths": 2}}).ok)
	var one := Validator.run(ls.network, {"device": "R1", "check": "route_to", "args": {"dest": "10.0.24.1", "paths": 2}})
	assert_false(one.ok)
	assert_string_contains(one.msg, "1 path(s)")
