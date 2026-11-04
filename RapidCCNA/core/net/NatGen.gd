class_name NatGen
extends RefCounted
## NAT Translator items: NAT address terms, NAT type from config, PAT behaviour, reading the table.

const KINDS := ["terms", "nat_type", "pat_port", "table"]
const TERMS := {
	"inside_local": "inside local", "inside_global": "inside global",
	"outside_local": "outside local", "outside_global": "outside global",
}

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"nat_type": return _nat_type(rng)
		"pat_port": return _pat_port(rng)
		"table": return _table(rng)
	return _terms(rng)

static func _scenario(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"pc": "192.168.%d.%d" % [rng.randi_range(1, 50), rng.randi_range(10, 200)],
		"server": "203.0.113.%d" % rng.randi_range(10, 250),
		"outside_if": "198.51.100.%d" % (rng.randi_range(0, 60) * 4 + 2),
		"static_global": "198.51.100.%d" % rng.randi_range(130, 250),
	}

static func _terms(rng: RandomNumberGenerator) -> Dictionary:
	var s := _scenario(rng)
	var static_nat := rng.randf() < 0.4
	var global: String = s.static_global if static_nat else s.outside_if
	var cfg := ""
	if static_nat:
		cfg = "ip nat inside source static %s %s" % [s.pc, s.static_global]
	else:
		cfg = "access-list 1 permit 192.168.0.0 0.0.255.255\nip nat inside source list 1 interface GigabitEthernet0/1 overload"
	var exhibit := "PC %s (inside) browses to web server %s (outside).\nR1 Gi0/1 (ip nat outside): %s\n\n%s" % [s.pc, s.server, s.outside_if, cfg]
	var term: String = TERMS.keys()[rng.randi() % 4]
	var values := {"inside_local": s.pc, "inside_global": global, "outside_local": s.server, "outside_global": s.server}
	return {"kind": "terms", "card_id": "gen.nat_translator.terms", "exhibit": exhibit,
		"question": "What is the %s address?" % TERMS[term], "answer": values[term], "placeholder": "a.b.c.d",
		"hint": "Inside/outside = whose device it is. Local/global = which side of the router you're looking from (local = as seen inside).",
		"explain": "Inside local %s (the PC's real address)\nInside global %s (the PC after translation)\nOutside local = outside global = %s (the server isn't translated)" % [s.pc, global, s.server]}

static func _nat_type(rng: RandomNumberGenerator) -> Dictionary:
	var s := _scenario(rng)
	var configs := [
		["Static NAT", "ip nat inside source static %s %s" % [s.pc, s.static_global],
			"'static' maps one inside local address permanently to one inside global address."],
		["Dynamic NAT (pool)", "ip nat pool PUB 198.51.100.129 198.51.100.140 netmask 255.255.255.0\nip nat inside source list 1 pool PUB",
			"A pool without 'overload' gives each inside host its own global address, one at a time, until the pool runs out."],
		["PAT (NAT overload)", "ip nat inside source list 1 interface GigabitEthernet0/1 overload",
			"'overload' means many inside hosts share one global address, told apart by port number."],
		["PAT (NAT overload)", "ip nat pool PUB 198.51.100.129 198.51.100.129 netmask 255.255.255.0\nip nat inside source list 1 pool PUB overload",
			"'overload' turns a pool into PAT: hosts share the pool address(es) using different ports."],
	]
	var c: Array = configs[rng.randi() % configs.size()]
	var choices := ["Static NAT", "Dynamic NAT (pool)", "PAT (NAT overload)"]
	return {"kind": "nat_type", "card_id": "gen.nat_translator.nat_type",
		"exhibit": "access-list 1 permit 192.168.0.0 0.0.255.255\n" + c[1] if c[0] != "Static NAT" else c[1],
		"question": "Which type of NAT does this configure?", "choices": choices,
		"answer_index": choices.find(c[0]), "answer": c[0],
		"hint": "Look for the keywords: 'static', 'pool', 'overload'.", "explain": c[2]}

static func _pat_port(rng: RandomNumberGenerator) -> Dictionary:
	var s := _scenario(rng)
	var port := rng.randi_range(49152, 60000)
	var pc2: String = s.pc.substr(0, s.pc.rfind(".")) + ".%d" % rng.randi_range(201, 250)
	var rows := NAT.pat([{"local_ip": s.pc, "local_port": port, "out_ip": s.server, "out_port": 443}], s.outside_if)
	var choices := [
		"It's translated to %s using a different source port" % s.outside_if,
		"It's translated to %s:%d, the same as PC1" % [s.outside_if, port],
		"It's dropped until PC1's session ends",
		"It gets a different inside global address",
	]
	return {"kind": "pat_port", "card_id": "gen.nat_translator.pat_port",
		"exhibit": "R1: ip nat inside source list 1 interface Gi0/1 overload   (Gi0/1 = %s)\n\n%s" % [s.outside_if, NAT.show(rows)],
		"question": "PC2 (%s) now also opens a connection to %s:443 from source port %d. What does PAT do?" % [pc2, s.server, port],
		"choices": choices, "answer_index": 0, "answer": choices[0],
		"hint": "PAT tells flows apart by the inside global IP + port pair; two flows can't share one.",
		"explain": "%s:%d is already taken by PC1, so R1 gives PC2's flow another free port on the same address. Thousands of hosts can share one public IP this way." % [s.outside_if, port]}

static func _table(rng: RandomNumberGenerator) -> Dictionary:
	var s := _scenario(rng)
	var base: String = s.pc.substr(0, s.pc.rfind("."))
	var flows: Array = []
	var hosts := [s.pc, base + ".%d" % rng.randi_range(201, 230), base + ".%d" % rng.randi_range(231, 250)]
	var svcs := [["tcp", 443], ["tcp", 80], ["udp", 53]]
	for i in 3:
		var svc: Array = svcs[rng.randi() % 3]
		flows.append({"proto": svc[0], "local_ip": hosts[i], "local_port": rng.randi_range(49152, 60000), "out_ip": s.server, "out_port": svc[1]})
	var rows := NAT.pat(flows, s.outside_if)
	var r := rng.randi_range(0, 2)
	var col: String = ["inside_global", "inside_global", "inside_local", "outside_global"][rng.randi() % 4]
	var lines := PackedStringArray()
	for i in 3:
		lines.append("PC%d %s opens %s port %d → %s:%d" % [i + 1, hosts[i], flows[i].proto.to_upper(), flows[i].local_port, s.server, flows[i].out_port])
	return {"kind": "table", "card_id": "gen.nat_translator.table",
		"exhibit": "\n".join(lines) + "\nR1 does PAT on Gi0/1 (%s).\n\n" % s.outside_if + NAT.show(rows, [r, col]),
		"question": "What belongs in the ??? cell (%s)?" % TERMS[col], "answer": rows[r][col], "placeholder": "ip:port",
		"hint": "Inside local = the PC's own ip:port. Inside global = the router's outside address with the PAT port. Outside global = the server.",
		"explain": "Row %d: inside local %s → inside global %s, talking to %s." % [r + 1, rows[r].inside_local, rows[r].inside_global, rows[r].outside_global]}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.norm(response).replace(" ", "") == Grader.norm(item.answer) or Grader.same_value(item.answer, response)
