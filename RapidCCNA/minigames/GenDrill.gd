extends DrillBase
## Generic drill driven by a generator script (drills.json "generator").
## The generator provides static make_item(rng) -> item and, for typed answers,
## static check(item, response) -> bool. See core/net/RouteGen.gd for the item shape.

var generator: Script
var item: Dictionary

func setup(cfg: Dictionary) -> DrillBase:
	super(cfg)
	generator = load(cfg.get("generator", ""))
	return self

func present_item() -> void:
	item = generator.make_item(rng)
	if item.has("exhibit"):
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		prompt_box.add_child(ex)
		UI.label(ex, item.exhibit, "Code")
	if item.has("prompt"):
		var p := UI.label(prompt_box, item.prompt, "CodeBig" if item.prompt.length() <= 34 else "H2", true)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var q := UI.label(prompt_box, item.question, "H2", true)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if item.has("choices"):
		add_choices(item.choices)
	else:
		var le := answer_input(item.get("placeholder", ""))
		if item.get("wide", false):
			le.custom_minimum_size.x = 760
			le.alignment = HORIZONTAL_ALIGNMENT_LEFT

func check(r: String) -> bool:
	if item.has("choices"):
		return r.is_valid_int() and r.to_int() == int(item.answer_index)
	if generator.has_method("check"):
		return generator.check(item, r)
	return Grader.same_value(item.answer, r)

func correct_choice() -> int: return int(item.get("answer_index", -1))
func card_id() -> String: return item.card_id
func correct_answer() -> String: return item.answer
func hint() -> String: return item.get("hint", "")

func explain() -> String:
	var text: String = item.get("explain", "")
	if generator.has_method("parse_error") and _answer:
		var err: String = generator.parse_error(item, _answer.text)
		if not err.is_empty():
			text = "Your line didn't parse: %s\n\n%s" % [err, text]
	return text

func lock_inputs() -> void:
	if _answer:
		_answer.editable = false
