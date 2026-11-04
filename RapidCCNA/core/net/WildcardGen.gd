class_name WildcardGen
extends RefCounted
## Wildcard Workshop items (see RouteGen for the item shape).

const KINDS := ["wc_from_prefix", "last_match", "does_match", "wc_for_range"]

static func _net(rng: RandomNumberGenerator, lo: int, hi: int) -> Array:
	var p := rng.randi_range(lo, hi)
	var ip := IPv4.parse("%d.%d.%d.%d" % [[10, 172, 192][rng.randi() % 3], rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255)])
	return [IPv4.network(ip, p), p]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	var n := _net(rng, 16, 30)
	var net: int = n[0]
	var p: int = n[1]
	var wc := IPv4.wildcard(p)
	var mask_s := IPv4.to_str(IPv4.mask(p))
	var spec := "%s %s" % [IPv4.to_str(net), IPv4.to_str(wc)]
	var rng_s := "%s - %s" % [IPv4.to_str(net), IPv4.to_str(net | wc)]
	var how := "Wildcard = 255.255.255.255 - mask (%s) = %s.\n%s matches %s." % [mask_s, IPv4.to_str(wc), spec, rng_s]
	var item := {"kind": kind, "card_id": "gen.wildcard_workshop." + kind, "explain": how,
		"placeholder": "a.b.c.d"}
	match kind:
		"wc_from_prefix":
			item.prompt = "%s/%d" % [IPv4.to_str(net), p]
			item.question = "What wildcard mask matches this whole subnet?"
			item.answer = IPv4.to_str(wc)
			item.hint = "Subtract each mask octet from 255. /%d = %s." % [p, mask_s]
		"last_match":
			item.prompt = spec
			item.question = "What is the last address this matches?"
			item.answer = IPv4.to_str(net | wc)
			item.hint = "Add the wildcard to the base address, octet by octet."
		"wc_for_range":
			item.prompt = rng_s
			item.question = "Which wildcard mask, with base %s, matches exactly this range?" % IPv4.to_str(net)
			item.answer = IPv4.to_str(wc)
			item.hint = "Wildcard = last address - first address, octet by octet."
		"does_match":
			var inside := rng.randf() < 0.5
			var probe := 0
			if inside:
				probe = net + rng.randi_range(0, wc)
			else:
				# Just outside the range: the neighbouring block, so the boundary matters.
				var size := wc + 1
				probe = (net + size + rng.randi_range(0, wc)) if rng.randf() < 0.5 or net < size else (net - size + rng.randi_range(0, wc))
				probe &= IPv4.ALL
			item.prompt = IPv4.to_str(probe)
			item.question = "Is this address matched by %s?" % spec
			item.choices = ["Yes, it matches", "No"]
			item.answer_index = 0 if ACL.addr_matches(probe, net, wc) else 1
			item.answer = item.choices[item.answer_index]
			item.hint = "Bits where the wildcard is 0 must equal the base address; 1 bits are ignored. Work out the range first."
			item.erase("placeholder")
	return item

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
