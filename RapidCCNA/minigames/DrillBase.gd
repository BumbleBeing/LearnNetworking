class_name DrillBase
extends VBoxContainer
## Base for mini-games: item loop, timer, streak, hint (guided only), feedback.
## Subclasses implement present_item(), get_response(), check(), explain(),
## hint(), card_id(), correct_answer() and optionally lock_inputs().

signal finished(summary: Dictionary)

var guided := true
var count := 10
var target_ms := 30000
var rng := RandomNumberGenerator.new()
var look: Dictionary
var results: Array = []
var index := 0
var streak := 0

var prompt_box: VBoxContainer
var answer_box: VBoxContainer
var _item_chip: Label
var _streak_chip: Label
var _timer_label: Label
var _feedback: VBoxContainer
var _hint_btn: Button
var _submit_btn: Button
var _next_btn: Button
var _item_start := 0
var _answered := false
var _answer: LineEdit            # set by answer_input()
var _choices: Array[Button] = [] # set by add_choices()
var _choice_index := -1

func setup(cfg: Dictionary) -> DrillBase:
	guided = bool(cfg.get("guided", true))
	count = int(cfg.get("count", 10))
	target_ms = int(cfg.get("target_seconds", 30)) * 1000
	if cfg.has("seed"):
		rng.seed = int(cfg.seed)
	else:
		rng.randomize()
	return self

func _ready() -> void:
	look = Palette.current()
	add_theme_constant_override("separation", 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status := UI.hbox(self, 10)
	_item_chip = UI.chip(status, "").get_child(0)
	_streak_chip = UI.chip(status, "").get_child(0)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(spacer)
	_timer_label = UI.label(status, "", "H2")
	var card := UI.card(self)
	card.add_theme_constant_override("separation", 18)
	prompt_box = UI.vbox(card, 6)
	answer_box = UI.vbox(card, 10)
	_feedback = UI.vbox(card, 6)
	var row := UI.hbox(self, 12)
	_submit_btn = UI.button(row, "Submit", submit, true)
	_next_btn = UI.button(row, "Next", next_item, true)
	_hint_btn = UI.button(row, "Hint", _show_hint)
	_hint_btn.visible = guided
	next_item()

func _process(_delta: float) -> void:
	if _answered or _timer_label == null:
		return
	var ms := Time.get_ticks_msec() - _item_start
	_timer_label.text = "%.1fs" % (ms / 1000.0)
	_timer_label.add_theme_color_override("font_color", look.warn if ms > target_ms else look.muted)

func next_item() -> void:
	index += 1
	if index > count:
		finished.emit(summary())
		return
	_answered = false
	for box in [prompt_box, answer_box, _feedback]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_item_chip.text = "Item %d / %d" % [index, count]
	_streak_chip.text = "Streak %d" % streak
	_submit_btn.visible = true
	_next_btn.visible = false
	_hint_btn.disabled = false
	_answer = null
	_choices.clear()
	_choice_index = -1
	present_item()
	_submit_btn.visible = _choices.is_empty()   # choices answer on click
	_item_start = Time.get_ticks_msec()
	UI.announce("%s. %s" % [_item_chip.text, prompt_text()])

## The item's prompt as plain text (every label in prompt_box), for screen readers.
func prompt_text() -> String:
	var parts := PackedStringArray()
	for l in prompt_box.find_children("*", "Label", true, false):
		if not l.text.strip_edges().is_empty():
			parts.append(l.text.strip_edges())
	return ". ".join(parts)

func submit() -> void:
	if _answered:
		return
	var response := get_response()
	if response.strip_edges().is_empty():
		return
	_answered = true
	var ms := Time.get_ticks_msec() - _item_start
	var ok := check(response)
	results.append({"card_id": card_id(), "correct": ok, "ms": ms})
	streak = streak + 1 if ok else 0
	_streak_chip.text = "Streak %d" % streak
	lock_inputs()
	_mark_choices()
	var head := UI.label(_feedback, ("Correct  ·  %.1fs" % (ms / 1000.0)) if ok else "Not quite. Answer: " + correct_answer(), "H2", true)
	head.add_theme_color_override("font_color", look.good if ok else look.accent2)
	# Learning first: always show the worked solution after a miss; in guided mode after every item.
	if not ok or guided:
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		_feedback.add_child(ex)
		UI.label(ex, explain(), "Code")
	_submit_btn.visible = false
	_hint_btn.disabled = true
	_next_btn.visible = true
	_next_btn.text = "Finish" if index >= count else "Next"
	_next_btn.grab_focus()
	UI.scroll_into_view(_next_btn)
	UI.announce(head.text + (". " + explain() if not ok or guided else ""))

func _show_hint() -> void:
	_hint_btn.disabled = true
	UI.label(_feedback, "Hint: " + hint(), "Muted", true)
	UI.announce("Hint: " + hint())

func summary() -> Dictionary:
	var n := results.size()
	var c := results.filter(func(r): return r.correct).size()
	var total_ms := 0
	for r in results:
		total_ms += int(r.ms)
	@warning_ignore("integer_division")
	return {"items": n, "correct": c, "accuracy": float(c) / n if n > 0 else 0.0,
		"avg_ms": total_ms / n if n > 0 else 0, "results": results, "guided": guided}

## Helper: a LineEdit wired to submit on Enter.
func answer_input(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size.x = 320
	le.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.add_theme_font_size_override("font_size", 22)
	le.accessibility_name = "Your answer"   # the question itself is announced with each item
	le.text_submitted.connect(func(_t): submit())
	answer_box.add_child(le)
	UI.focus_later(le)
	_answer = le
	return le

## Helper: clickable choices; clicking (or pressing 1-9) answers immediately.
func add_choices(options: Array) -> void:
	var box := UI.vbox(answer_box, 8)
	for i in options.size():
		var b := Button.new()
		b.text = "%d.   %s" % [i + 1, options[i]]
		b.theme_type_variation = "Choice"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL   # 1-9 still work; Tab reaches them for screen readers
		b.pressed.connect(choose.bind(i))
		box.add_child(b)
		_choices.append(b)

func choose(i: int) -> void:
	if _answered or i < 0 or i >= _choices.size():
		return
	_choice_index = i
	submit()

## Index of the correct choice for choice items (override), -1 otherwise.
func correct_choice() -> int:
	return -1

func _mark_choices() -> void:
	if _choices.is_empty():
		return
	for i in _choices.size():
		_choices[i].disabled = true
		if i == correct_choice():
			UI.mark_choice(_choices[i], true)
		elif i == _choice_index:
			UI.mark_choice(_choices[i], false)

func _unhandled_key_input(event: InputEvent) -> void:
	if _choices.is_empty() or _answered or not event is InputEventKey or not event.pressed or event.echo:
		return
	var n: int = event.keycode - KEY_1
	if n >= 0 and n < _choices.size():
		get_viewport().set_input_as_handled()
		choose(n)

## Answers the current item programmatically (tests, smoke runs, screenshots).
func autoplay(correct: bool) -> void:
	if not _choices.is_empty():
		var c := correct_choice()
		choose(c if correct else (c + 1) % _choices.size())
		return
	if _answer:
		_answer.text = correct_answer() if correct else "999"
	submit()

# --- virtuals ---
func present_item() -> void: pass
func get_response() -> String:
	if not _choices.is_empty():
		return str(_choice_index) if _choice_index >= 0 else ""
	return _answer.text if _answer else ""
func check(_response: String) -> bool: return false
func explain() -> String: return ""
func hint() -> String: return ""
func card_id() -> String: return ""
func correct_answer() -> String: return ""
func lock_inputs() -> void: pass
