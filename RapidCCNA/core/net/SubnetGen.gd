class_name SubnetGen
extends RefCounted
## Generates Subnet Sprint items with answers, hints and worked solutions.

const KINDS := ["network", "broadcast", "first", "last", "mask", "hosts"]
const QUESTIONS := {
	"network": "What is the network address?",
	"broadcast": "What is the broadcast address?",
	"first": "What is the first usable host address?",
	"last": "What is the last usable host address?",
	"mask": "What is the subnet mask in dotted decimal?",
	"hosts": "How many usable host addresses does this subnet have?",
}

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	# CCNA focus: mostly /24-/30, some /16-/23.
	var prefix := rng.randi_range(24, 30) if rng.randf() < 0.7 else rng.randi_range(16, 23)
	var ip := 0
	while true:
		match rng.randi() % 3:
			0: ip = (10 << 24) | rng.randi_range(0, 0xFFFFFF)
			1: ip = (172 << 24) | (rng.randi_range(16, 31) << 16) | rng.randi_range(0, 0xFFFF)
			_: ip = (192 << 24) | (168 << 16) | rng.randi_range(0, 0xFFFF)
		if ip != IPv4.network(ip, prefix) and ip != IPv4.broadcast(ip, prefix):
			break
	var answer := ""
	match kind:
		"network": answer = IPv4.to_str(IPv4.network(ip, prefix))
		"broadcast": answer = IPv4.to_str(IPv4.broadcast(ip, prefix))
		"first": answer = IPv4.to_str(IPv4.first_host(ip, prefix))
		"last": answer = IPv4.to_str(IPv4.last_host(ip, prefix))
		"mask": answer = IPv4.to_str(IPv4.mask(prefix))
		"hosts": answer = str(IPv4.usable_hosts(prefix))
	return {
		"kind": kind, "ip": IPv4.to_str(ip), "prefix": prefix,
		"prompt": "%s/%d" % [IPv4.to_str(ip), prefix],
		"question": QUESTIONS[kind], "answer": answer,
		"card_id": "gen.subnet_sprint." + kind,
	}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)

static func hint(item: Dictionary) -> String:
	var info := IPv4.block_info(item.prefix)
	if item.kind == "hosts":
		return "Host bits = 32 - %d = %d. Usable = 2^%d - 2." % [item.prefix, 32 - item.prefix, 32 - item.prefix]
	return "/%d: the interesting octet is octet %d, block size %d. Round octet %d down to a multiple of %d." % [
		item.prefix, info.octet + 1, info.block, info.octet + 1, info.block]

static func explain(item: Dictionary) -> String:
	var ip := IPv4.parse(item.ip)
	var p: int = item.prefix
	var info := IPv4.block_info(p)
	var o := IPv4.octet(ip, info.octet)
	var start: int = o - o % info.block
	return "\n".join([
		"/%d → mask %s, block size %d in octet %d" % [p, IPv4.to_str(IPv4.mask(p)), info.block, info.octet + 1],
		"Octet %d is %d, inside the %d-%d block" % [info.octet + 1, o, start, start + info.block - 1],
		"Network %s   Broadcast %s" % [IPv4.to_str(IPv4.network(ip, p)), IPv4.to_str(IPv4.broadcast(ip, p))],
		"Hosts %s - %s (%d usable)" % [IPv4.to_str(IPv4.first_host(ip, p)), IPv4.to_str(IPv4.last_host(ip, p)), IPv4.usable_hosts(p)],
	])
