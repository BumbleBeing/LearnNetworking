class_name Grader
extends RefCounted
## Grades question responses. JSON numbers arrive as floats, so indices are int()-ed.

static func norm(s: String) -> String:
	var re := RegEx.create_from_string("\\s+")
	return re.sub(s.strip_edges().to_lower(), " ", true)

## Compares a typed answer: IPs by value, integers by value, otherwise normalised text.
static func same_value(expected: String, given: String) -> bool:
	var e := IPv4.parse(expected)
	if e >= 0:
		return IPv4.parse(given) == e
	var ge := given.strip_edges()
	if expected.is_valid_int():
		return ge.is_valid_int() and ge.to_int() == expected.to_int()
	return norm(expected) == norm(given)

static func grade(q: Dictionary, response: Variant) -> bool:
	match q.get("type", ""):
		"mcq_single", "exhibit":
			return (response is int or response is float) and int(response) == int(q.answer)
		"mcq_multi":
			if not response is Array:
				return false
			var a: Array = q.answer.map(func(x): return int(x))
			var r: Array = response.map(func(x): return int(x))
			a.sort()
			r.sort()
			return a == r
		"fill_in":
			var accepted: Array = q.answer if q.answer is Array else [q.answer]
			for ans in accepted:
				if same_value(str(ans), str(response)):
					return true
			return false
		"drag_match":
			if not response is Dictionary:
				return false
			for k in q.answer:
				if norm(str(response.get(k, ""))) != norm(str(q.answer[k])):
					return false
			return true
		"drag_order":
			if not response is Array or response.size() != q.answer.size():
				return false
			for i in q.answer.size():
				if norm(str(response[i])) != norm(str(q.answer[i])):
					return false
			return true
		"cli_task":
			return response is Dictionary and bool(response.get("passed", false))
		"subnet_calc":
			if not response is Dictionary:
				return false
			for k in q.answer:
				if not same_value(str(q.answer[k]), str(response.get(k, ""))):
					return false
			return true
	return false

## Human-readable correct answer for feedback.
static func answer_text(q: Dictionary) -> String:
	match q.get("type", ""):
		"mcq_single", "exhibit":
			return str(q.choices[int(q.answer)])
		"mcq_multi":
			return ", ".join(q.answer.map(func(i): return str(q.choices[int(i)])))
		"fill_in":
			return str(q.answer[0]) if q.answer is Array else str(q.answer)
		"drag_match":
			return ", ".join(q.answer.keys().map(func(k): return "%s → %s" % [k, q.answer[k]]))
		"drag_order":
			return " → ".join(q.answer)
		"cli_task":
			return str(q.answer)
		"subnet_calc":
			var labels := {}
			for f in q.get("fields", []):
				labels[f.key] = f.label
			return ", ".join(q.answer.keys().map(func(k): return "%s: %s" % [labels.get(k, k), q.answer[k]]))
	return ""

## Human-readable form of a learner's response, for exam reports.
static func response_text(q: Dictionary, response: Variant) -> String:
	if response == null:
		return "Not answered"
	match q.get("type", ""):
		"mcq_single", "exhibit":
			var i := int(response) if (response is int or response is float) else -1
			return str(q.choices[i]) if i >= 0 and i < q.choices.size() else "Skipped"
		"mcq_multi":
			if not response is Array or response.is_empty():
				return "Skipped"
			return ", ".join(response.map(func(i): return str(q.choices[int(i)])))
		"fill_in":
			return "Skipped" if str(response).strip_edges().is_empty() else str(response).strip_edges()
		"drag_match":
			if not response is Dictionary or response.values().all(func(v): return str(v).is_empty()):
				return "Skipped"
			return ", ".join(response.keys().map(func(k): return "%s → %s" % [k, response[k] if str(response[k]) != "" else "?"]))
		"drag_order":
			return " → ".join(response) if response is Array else "Skipped"
		"cli_task":
			return "Configuration did not pass the checks" if response is Dictionary else "Skipped"
		"subnet_calc":
			if not response is Dictionary or response.values().all(func(v): return str(v).strip_edges().is_empty()):
				return "Skipped"
			return ", ".join(response.keys().map(func(k): return "%s: %s" % [k, response[k]]))
	return str(response)
