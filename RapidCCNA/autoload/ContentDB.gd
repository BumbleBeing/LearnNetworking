extends Node
## Loads all curriculum content from res://content. Code never hardcodes curriculum text.

const ROOT := "res://content"

var blueprint: Dictionary = {}
var domains: Array = []            # blueprint domains, in order
var lessons: Dictionary = {}       # id -> lesson dict
var questions: Dictionary = {}     # id -> question dict
var drills: Dictionary = {}        # id -> drill definition (content/drills/drills.json)
var errors: PackedStringArray = []

func _ready() -> void:
	load_all(ROOT)

func load_all(root: String) -> void:
	blueprint = {}
	domains = []
	lessons = {}
	questions = {}
	drills = {}
	errors = PackedStringArray()
	var bp = JsonIO.read(root + "/blueprint.json")
	if not bp is Dictionary:
		errors.append("missing or invalid blueprint.json")
		return
	blueprint = bp
	domains = bp.get("domains", [])
	for path in _json_files(root + "/lessons"):
		var l = JsonIO.read(path)
		if l is Dictionary and l.has("id"):
			_add_unique(lessons, l, path)
		else:
			errors.append("invalid lesson file %s" % path)
	for path in _json_files(root + "/questions"):
		var arr = JsonIO.read(path)
		if not arr is Array:
			errors.append("question file %s must be an array" % path)
			continue
		for q in arr:
			if q is Dictionary and q.has("id"):
				_add_unique(questions, q, path)
			else:
				errors.append("invalid question in %s" % path)
	var dr = JsonIO.read(root + "/drills/drills.json")
	if dr is Array:
		for d in dr:
			if d is Dictionary and d.has("id"):
				_add_unique(drills, d, root + "/drills/drills.json")
	for e in errors:
		push_warning("ContentDB: " + e)

func _add_unique(target: Dictionary, item: Dictionary, path: String) -> void:
	if target.has(item.id):
		errors.append("duplicate id %s in %s" % [item.id, path])
	else:
		target[item.id] = item

func _json_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_json_files(dir_path + "/" + sub))
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(dir_path + "/" + f)
	return out

func get_domain(domain_id: String) -> Dictionary:
	for d in domains:
		if d.id == domain_id:
			return d
	return {}

func lessons_for_domain(domain_id: String) -> Array:
	var out := lessons.values().filter(func(l): return l.get("domain") == domain_id)
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out

func questions_for_domain(domain_id: String) -> Array:
	return questions.values().filter(func(q): return q.get("domain") == domain_id)
