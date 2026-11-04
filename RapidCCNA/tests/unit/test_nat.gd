extends GutTest

func test_pat_keeps_free_ports_and_moves_clashes():
	var rows := NAT.pat([
		{"local_ip": "192.168.1.10", "local_port": 50000, "out_ip": "203.0.113.5", "out_port": 443},
		{"local_ip": "192.168.1.11", "local_port": 50000, "out_ip": "203.0.113.5", "out_port": 443},
		{"local_ip": "192.168.1.12", "local_port": 1024, "out_ip": "203.0.113.5", "out_port": 80},
	], "198.51.100.2")
	assert_eq(rows[0].inside_global, "198.51.100.2:50000")
	assert_eq(rows[1].inside_global, "198.51.100.2:1024")
	assert_eq(rows[2].inside_global, "198.51.100.2:1025", "1024 already taken")
	assert_eq(rows[1].inside_local, "192.168.1.11:50000")
	assert_eq(rows[0].outside_local, rows[0].outside_global)

func test_show_hides_cell():
	var rows := [NAT.static_row("192.168.1.10", "198.51.100.20")]
	var out := NAT.show(rows, [0, "inside_global"])
	assert_string_contains(out, "Inside global")
	assert_string_contains(out, "???")
	assert_false(out.contains("198.51.100.20"))
