extends GutTest

func test_parse_valid_and_invalid():
	for s in ["::", "::1", "2001:db8::1", "fe80::1:2", "2001:0db8:0000:0000:0000:ff00:0042:8329", "1:2:3:4:5:6:7::"]:
		assert_true(IPv6.is_valid(s), s)
	for s in ["", ":::", "1::2::3", "2001:db8:::1", "12345::1", "g::1", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7", "2001:db8::1:", ":1::2"]:
		assert_false(IPv6.is_valid(s), s)

func test_expand():
	assert_eq(IPv6.expand("2001:db8::1"), "2001:0db8:0000:0000:0000:0000:0000:0001")
	assert_eq(IPv6.expand("::"), "0000:0000:0000:0000:0000:0000:0000:0000")

# RFC 5952 examples, cross-checked with Python's ipaddress.
func test_compress_rfc5952():
	assert_eq(IPv6.compress("2001:0db8:0000:0000:0000:ff00:0042:8329"), "2001:db8::ff00:42:8329")
	assert_eq(IPv6.compress("2001:db8:0:0:1:0:0:1"), "2001:db8::1:0:0:1")   # first of equal runs
	assert_eq(IPv6.compress("2001:db8:0:1:1:1:1:1"), "2001:db8:0:1:1:1:1:1") # single 0 stays
	assert_eq(IPv6.compress("2001:0:0:1:0:0:0:1"), "2001:0:0:1::1")         # longest run
	assert_eq(IPv6.compress("FE80:0000:0000:0000:0202:B3FF:FE1E:8329"), "fe80::202:b3ff:fe1e:8329")
	assert_eq(IPv6.compress("0:0:0:0:0:0:0:1"), "::1")
	assert_eq(IPv6.compress("0:0:0:0:0:0:0:0"), "::")
	assert_eq(IPv6.compress("1:0:0:0:0:0:0:0"), "1::")

func test_types():
	assert_eq(IPv6.address_type("2001:db8::1"), "global unicast")
	assert_eq(IPv6.address_type("fe80::1"), "link-local")
	assert_eq(IPv6.address_type("febf::1"), "link-local")
	assert_eq(IPv6.address_type("fd00::1"), "unique local")
	assert_eq(IPv6.address_type("ff02::1"), "multicast")
	assert_eq(IPv6.address_type("::1"), "loopback")
	assert_eq(IPv6.address_type("::"), "unspecified")

func test_network_and_eui64():
	assert_eq(IPv6.network("2001:db8:acad:1:abcd::1", 64), "2001:db8:acad:1::")
	assert_eq(IPv6.network("2001:db8:acad:1fff::1", 52), "2001:db8:acad:1000::")
	assert_eq(IPv6.eui64("00:1A:2B:3C:4D:5E"), "21a:2bff:fe3c:4d5e")
	assert_eq(IPv6.eui64("0200.0000.0001"), "0:ff:fe00:1")
	assert_eq(IPv6.eui64("bad"), "")
