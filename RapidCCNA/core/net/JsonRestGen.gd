class_name JsonRestGen
extends RefCounted
## JSON & REST Inspector items: spot invalid JSON, read values out of nested JSON,
## name JSON data types, CRUD to HTTP verbs, status codes and reading an API request.

const KINDS := ["json_valid", "json_path", "json_type", "http_verb", "status_code", "request"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"json_path": return _json_path(rng)
		"json_type": return _json_type(rng)
		"http_verb": return _http_verb(rng)
		"status_code": return _status_code(rng)
		"request": return _request(rng)
	return _json_valid(rng)

## A device document like a controller API would return.
static func device_doc(rng: RandomNumberGenerator) -> Dictionary:
	var n := rng.randi_range(1, 9)
	var ifs: Array = []
	for i in rng.randi_range(2, 3):
		ifs.append({"name": "GigabitEthernet0/%d" % i, "enabled": rng.randf() < 0.75,
			"ipv4": {"address": "10.%d.%d.1" % [n, i + 1], "prefix": [24, 30, 24][i % 3]}})
	var vlans: Array = []
	for i in rng.randi_range(2, 4):
		vlans.append(10 * (i + 1))
	return {"hostname": "SW%d" % n, "model": "C9300-48P", "uptime_days": rng.randi_range(3, 400),
		"managed": true, "location": null, "vlans": vlans, "interfaces": ifs}

## JSON text with keys in a fixed, readable order (Godot dictionaries keep insertion order).
static func dump(v, indent: String = "") -> String:
	var pad := indent + "  "
	if v is Dictionary:
		if v.is_empty():
			return "{}"
		var parts := PackedStringArray()
		for k in v:
			parts.append("%s\"%s\": %s" % [pad, k, dump(v[k], pad)])
		return "{\n%s\n%s}" % [",\n".join(parts), indent]
	if v is Array:
		if v.all(func(x): return not (x is Dictionary or x is Array)):
			return "[" + ", ".join(v.map(func(x): return dump(x, pad))) + "]"
		var items := PackedStringArray()
		for x in v:
			items.append(pad + dump(x, pad))
		return "[\n%s\n%s]" % [",\n".join(items), indent]
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is String:
		return "\"%s\"" % v
	return str(v)

const DEFECTS := {
	"trailing": "There's a comma after the last item",
	"single": "A string uses single quotes; JSON needs double quotes",
	"unquoted": "A key isn't in double quotes",
	"missing_comma": "A comma is missing between two items",
	"python_bool": "A boolean is written True/False; JSON uses lowercase true/false",
	"comment": "It contains a comment; JSON has no comments",
}
const VALID := "It's valid JSON"

static func _json_valid(rng: RandomNumberGenerator) -> Dictionary:
	var doc := {"hostname": "R%d" % rng.randi_range(1, 9), "enabled": true, "vlans": [10, 20, 30],
		"mgmt": {"ip": "10.0.0.%d" % rng.randi_range(1, 254), "port": 443}}
	var text := dump(doc)
	var defect: String = "" if rng.randf() < 0.25 else DEFECTS.keys()[rng.randi() % DEFECTS.size()]
	match defect:
		"trailing": text = text.replace("\"port\": 443", "\"port\": 443,")
		"single": text = text.replace("\"%s\"" % doc.hostname, "'%s'" % doc.hostname)
		"unquoted": text = text.replace("\"enabled\":", "enabled:")
		"missing_comma": text = text.replace("\"enabled\": true,", "\"enabled\": true")
		"python_bool": text = text.replace("\"enabled\": true", "\"enabled\": True")
		"comment": text = text.replace("\"vlans\"", "// access VLANs\n  \"vlans\"")
	var ans: String = VALID if defect.is_empty() else DEFECTS[defect]
	var wrong: Array = DEFECTS.keys().filter(func(k): return k != defect).map(func(k): return DEFECTS[k])
	GenUtil.shuffle(rng, wrong)
	var choices: Array = [ans] + wrong.slice(0, 3)
	if not defect.is_empty() and not VALID in choices:
		choices[3] = VALID
	GenUtil.shuffle(rng, choices)
	return {"kind": "json_valid", "card_id": "gen.json_rest.json_valid", "exhibit": text,
		"question": "Is this valid JSON?", "choices": choices, "answer_index": choices.find(ans), "answer": ans,
		"hint": "JSON rules: keys and strings in double quotes, commas between items but not after the last, lowercase true/false/null, no comments.",
		"explain": ("Everything follows the rules: double-quoted keys and strings, commas only between items, lowercase true." if defect.is_empty()
			else DEFECTS[defect] + ".") + "\nJSON types: object {}, array [], string \"\", number, true/false, null."}

## Paths into the device document and their values.
static func _paths(doc: Dictionary) -> Array:
	var out: Array = [
		["hostname", doc.hostname], ["uptime_days", str(doc.uptime_days)], ["vlans[1]", str(doc.vlans[1])],
		["interfaces[0].name", doc.interfaces[0].name], ["interfaces[1].ipv4.address", doc.interfaces[1].ipv4.address],
		["interfaces[1].ipv4.prefix", str(doc.interfaces[1].ipv4.prefix)], ["interfaces[0].enabled", "true" if doc.interfaces[0].enabled else "false"],
	]
	return out

static func _json_path(rng: RandomNumberGenerator) -> Dictionary:
	var doc := device_doc(rng)
	if rng.randf() < 0.3:
		return {"kind": "json_path", "card_id": "gen.json_rest.json_path", "exhibit": dump(doc),
			"question": "How many interfaces are in the \"interfaces\" array?", "answer": str(doc.interfaces.size()), "placeholder": "number",
			"hint": "Each { } inside the [ ] of \"interfaces\" is one item.",
			"explain": "\"interfaces\" is an array of %d objects." % doc.interfaces.size()}
	var p: Array = _paths(doc)[rng.randi() % 7]
	return {"kind": "json_path", "card_id": "gen.json_rest.json_path", "exhibit": dump(doc),
		"question": "What is the value of %s? (arrays count from 0)" % p[0], "answer": p[1], "placeholder": "value", "wide": true,
		"hint": "Follow the path one step at a time: a name selects a key in an object, [n] selects the n-th item of an array, counting from 0.",
		"explain": "%s → %s. Array indexes start at 0, so [1] is the second item." % [p[0], p[1]]}

const TYPES := ["Object", "Array", "String", "Number", "Boolean", "Null"]

static func _json_type(rng: RandomNumberGenerator) -> Dictionary:
	var doc := device_doc(rng)
	var cases := [["\"hostname\"", "String", "Text in double quotes is a string."], ["\"uptime_days\"", "Number", "Unquoted digits are a number."],
		["\"managed\"", "Boolean", "true/false (lowercase, no quotes) is a boolean."], ["\"location\"", "Null", "null means no value."],
		["\"vlans\"", "Array", "Square brackets hold an ordered list: an array."], ["\"ipv4\" (inside an interface)", "Object", "Curly braces hold key/value pairs: an object."],
		["\"interfaces\"", "Array", "Square brackets: an array (here, of objects)."]]
	var c: Array = cases[rng.randi() % cases.size()]
	return {"kind": "json_type", "card_id": "gen.json_rest.json_type", "exhibit": dump(doc),
		"question": "What JSON data type is the value of %s?" % c[0], "choices": TYPES, "answer_index": TYPES.find(c[1]), "answer": c[1],
		"hint": "{ } object, [ ] array, \"...\" string, digits number, true/false boolean, null null.",
		"explain": c[2]}

const CRUD := [["Create a new VLAN", "POST"], ["Read the list of interfaces", "GET"], ["Replace a device's whole configuration object", "PUT"],
	["Change only the description of one interface", "PATCH"], ["Remove a static route", "DELETE"], ["Retrieve one device's details", "GET"]]

static func _http_verb(rng: RandomNumberGenerator) -> Dictionary:
	var c: Array = CRUD[rng.randi() % CRUD.size()]
	var choices: Array = ["GET", "POST", "PUT", "PATCH", "DELETE"]
	return {"kind": "http_verb", "card_id": "gen.json_rest.http_verb", "prompt": c[0],
		"question": "Which HTTP method does a REST API use for this?", "choices": choices, "answer_index": choices.find(c[1]), "answer": c[1],
		"hint": "CRUD: Create = POST, Read = GET, Update = PUT (replace) or PATCH (modify part), Delete = DELETE.",
		"explain": "Create → POST, Read → GET, Update → PUT (whole resource) / PATCH (part of it), Delete → DELETE. This is %s." % c[1]}

const CODES := [["200", "OK: the request succeeded"], ["201", "Created: a new resource was made"], ["204", "No Content: success, nothing to return"],
	["400", "Bad Request: the request is malformed"], ["401", "Unauthorized: missing or bad credentials"], ["403", "Forbidden: authenticated but not allowed"],
	["404", "Not Found: the resource doesn't exist"], ["500", "Internal Server Error: the server failed"]]

static func _status_code(rng: RandomNumberGenerator) -> Dictionary:
	var c: Array = CODES[rng.randi() % CODES.size()]
	var others: Array = CODES.filter(func(x): return x[0] != c[0]).map(func(x): return x[1])
	GenUtil.shuffle(rng, others)
	var choices: Array = [c[1]] + others.slice(0, 3)
	GenUtil.shuffle(rng, choices)
	return {"kind": "status_code", "card_id": "gen.json_rest.status_code", "prompt": "HTTP " + c[0],
		"question": "What does this response code mean?", "choices": choices, "answer_index": choices.find(c[1]), "answer": c[1],
		"hint": "2xx success, 3xx redirection, 4xx the client's mistake, 5xx the server's.",
		"explain": "\n".join(CODES.map(func(x): return "%s %s" % x))}

static func _request(rng: RandomNumberGenerator) -> Dictionary:
	var vlan := rng.randi_range(2, 99) * 10
	var host := "10.0.0.%d" % rng.randi_range(2, 254)
	var reqs := [
		["POST", "/api/v1/vlans", "{\"id\": %d, \"name\": \"VOICE\"}" % vlan, "It creates VLAN %d named VOICE" % vlan],
		["GET", "/api/v1/interfaces", "", "It reads the list of interfaces"],
		["DELETE", "/api/v1/vlans/%d" % vlan, "", "It removes VLAN %d" % vlan],
		["PATCH", "/api/v1/interfaces/GigabitEthernet0%%2F1", "{\"description\": \"Uplink\"}", "It changes only Gi0/1's description"],
	]
	var r: Array = reqs[rng.randi() % reqs.size()]
	var token := "eyJhbGciOiJIUzI1NiJ9.%s" % ("%x" % rng.randi()).left(8)
	var lines := PackedStringArray(["%s https://%s%s HTTP/1.1" % [r[0], host, r[1].replace("%%", "%")], "Authorization: Bearer " + token,
		"Accept: application/json"])
	if not r[2].is_empty():
		lines.append("Content-Type: application/json")
		lines.append("")
		lines.append(r[2])
	var all_: Array = reqs.map(func(x): return x[3])
	var ans: String = r[3]
	var choices: Array = [ans] + all_.filter(func(x): return x != ans).slice(0, 2)
	choices.append("It logs in and returns a new token")
	GenUtil.shuffle(rng, choices)
	return {"kind": "request", "card_id": "gen.json_rest.request", "exhibit": "\n".join(lines),
		"question": "What does this API request do?", "choices": choices, "answer_index": choices.find(ans), "answer": ans,
		"hint": "Read the method first, then the URI (which resource), then the body. The Authorization header only proves who you are.",
		"explain": "%s on %s: %s. 'Authorization: Bearer ...' carries a token from an earlier login.%s" % [r[0], r[1].replace("%%2F", "/"),
			"i" + ans.trim_prefix("I"), " Content-Type says the body is JSON." if not r[2].is_empty() else " A GET has no body."]}

static func check(item: Dictionary, response: String) -> bool:
	var r := response.strip_edges().trim_prefix("\"").trim_suffix("\"")
	return Grader.same_value(item.answer, r)
