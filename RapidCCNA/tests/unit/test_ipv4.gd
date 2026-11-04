extends GutTest

func test_parse_and_format_round_trip():
	for s in ["0.0.0.0", "10.1.2.3", "192.168.1.130", "255.255.255.255"]:
		assert_eq(IPv4.to_str(IPv4.parse(s)), s)

func test_parse_rejects_bad_input():
	for s in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "a.b.c.d", "1.2.3.-4", "1..2.3", "1.2.3.4/24", "+1.2.3.4"]:
		assert_eq(IPv4.parse(s), -1, s)

func test_masks_and_prefixes():
	assert_eq(IPv4.to_str(IPv4.mask(0)), "0.0.0.0")
	assert_eq(IPv4.to_str(IPv4.mask(20)), "255.255.240.0")
	assert_eq(IPv4.to_str(IPv4.mask(32)), "255.255.255.255")
	assert_eq(IPv4.prefix_from_mask(IPv4.parse("255.255.255.224")), 27)
	assert_eq(IPv4.prefix_from_mask(IPv4.parse("255.0.255.0")), -1)
	assert_eq(IPv4.to_str(IPv4.wildcard(26)), "0.0.0.63")

# Fixtures cross-checked with Python's ipaddress module.
const CASES := [
	["192.168.1.130", 26, "192.168.1.128", "192.168.1.191", "192.168.1.129", "192.168.1.190", 62],
	["10.0.0.70", 27, "10.0.0.64", "10.0.0.95", "10.0.0.65", "10.0.0.94", 30],
	["172.16.45.200", 20, "172.16.32.0", "172.16.47.255", "172.16.32.1", "172.16.47.254", 4094],
	["10.250.3.9", 9, "10.128.0.0", "10.255.255.255", "10.128.0.1", "10.255.255.254", 8388606],
	["192.0.2.5", 30, "192.0.2.4", "192.0.2.7", "192.0.2.5", "192.0.2.6", 2],
	["192.0.2.5", 31, "192.0.2.4", "192.0.2.5", "192.0.2.4", "192.0.2.5", 2],
	["192.0.2.5", 32, "192.0.2.5", "192.0.2.5", "192.0.2.5", "192.0.2.5", 1],
]

func test_subnet_math_matches_fixtures():
	for c in CASES:
		var ip := IPv4.parse(c[0])
		var p: int = c[1]
		assert_eq(IPv4.to_str(IPv4.network(ip, p)), c[2], "net %s/%d" % [c[0], p])
		assert_eq(IPv4.to_str(IPv4.broadcast(ip, p)), c[3], "bc %s/%d" % [c[0], p])
		assert_eq(IPv4.to_str(IPv4.first_host(ip, p)), c[4], "first %s/%d" % [c[0], p])
		assert_eq(IPv4.to_str(IPv4.last_host(ip, p)), c[5], "last %s/%d" % [c[0], p])
		assert_eq(IPv4.usable_hosts(p), c[6], "hosts /%d" % p)

func test_block_info():
	assert_eq(IPv4.block_info(26), {"octet": 3, "block": 64})
	assert_eq(IPv4.block_info(20), {"octet": 2, "block": 16})
	assert_eq(IPv4.block_info(24), {"octet": 2, "block": 1})
	assert_eq(IPv4.block_info(8), {"octet": 0, "block": 1})
