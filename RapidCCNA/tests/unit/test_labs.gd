extends GutTest
## Every shipped lab: tasks start incomplete, the model solution parses cleanly and
## completes every task. Plus network forwarding and validator behaviour.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func test_every_lab_is_solvable_and_starts_unsolved():
	assert_gt(ContentDB.labs.size(), 3)
	for lab in ContentDB.labs.values():
		var ls := LabSession.create(lab)
		var before := ls.results()
		assert_false(before.all(func(r): return r.ok), "%s should start unsolved" % lab.id)
		var errs := ls.apply_solution()
		assert_eq(errs.size(), 0, "%s solution errors: %s" % [lab.id, errs])
		var after := ls.results()
		for i in after.size():
			assert_true(after[i].ok, "%s task %d: %s" % [lab.id, i + 1, after[i].msg])

func test_lab_startup_configs_have_no_errors():
	for lab in ContentDB.labs.values():
		var net := Network.build(lab)
		for dd in lab.devices:
			if dd.has("config"):
				var ls := LabSession.new()
				ls.network = net
				assert_eq(ls.apply(dd.name, dd.config).size(), 0, "%s %s startup config" % [lab.id, dd.name])

func test_ping_needs_routes_both_ways():
	var lab: Dictionary = ContentDB.labs["lab.static_routes"]
	var ls := LabSession.create(lab)
	ls.apply("R1", ["interface g0/0", "ip address 10.0.12.1 255.255.255.252", "no shutdown"])
	var p := ls.network.ping_ok("R1", "192.168.3.1")
	assert_false(p.ok)
	assert_string_contains(p.reason, "R1 has no route")
	ls.apply("R1", ["ip route 192.168.3.0 255.255.255.0 10.0.12.2"])
	assert_true(ls.network.ping_ok("R1", "192.168.3.1").ok)
	# Break the return path: R3 loses its default route.
	ls.apply("R3", ["no ip route 0.0.0.0 0.0.0.0 10.0.23.1"])
	var back := ls.network.ping_ok("R1", "192.168.3.1")
	assert_false(back.ok)
	assert_string_contains(back.reason, "reply")
	assert_string_contains(ls.network.ping("R1", "192.168.3.1"), "Success rate is 0 percent")

func test_floating_static_takes_over_when_primary_fails():
	var ls := LabSession.create(ContentDB.labs["lab.static_routes"])
	ls.apply_solution()
	assert_eq(ls.network.devices["R1"].routing_table().lookup(IPv4.parse("192.168.3.9")).next_hop, "10.0.12.2")
	ls.apply("R1", ["interface g0/0", "shutdown"])
	assert_eq(ls.network.devices["R1"].routing_table().lookup(IPv4.parse("192.168.3.9")).next_hop, "10.0.13.2")
	assert_true(ls.network.ping_ok("R1", "192.168.3.1").ok, "backup path works")

func test_nat_translation_semantics():
	var ls := LabSession.create(ContentDB.labs["lab.nat_pat"])
	var d: Device = ls.network.devices["R1"]
	ls.apply("R1", ["access-list 1 permit 192.168.1.0 0.0.0.255", "ip nat inside source list 1 interface g0/1 overload"])
	assert_eq(d.nat_translate("192.168.1.50"), "", "no inside/outside interfaces yet")
	ls.apply("R1", ["interface g0/0", "ip nat inside", "interface g0/1", "ip nat outside"])
	assert_eq(d.nat_translate("192.168.1.50"), "203.0.113.2")
	assert_eq(d.nat_translate("10.0.0.5"), "", "not permitted by ACL 1")
	ls.apply("R1", ["ip nat inside source static 192.168.1.10 203.0.113.5"])
	assert_eq(d.nat_translate("192.168.1.10"), "203.0.113.5")
	assert_string_contains(Show.nat_translations(d), "203.0.113.5")

func test_validator_explains_failures():
	var ls := LabSession.create(ContentDB.labs["lab.vlans"])
	ls.apply("SW1", ["vlan 10", "name sales"])
	var r := ls.check_task(ContentDB.labs["lab.vlans"].tasks[0])
	assert_false(r.ok)
	assert_string_contains(r.msg, "named sales, not SALES")
