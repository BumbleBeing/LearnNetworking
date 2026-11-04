class_name QuestionView
extends VBoxContainer
## Renders one question of any non-CLI type, grades it and shows an explanation.
## Keyboard: 1-9 pick choices, Enter submits / continues.

signal answered(result: Dictionary)   # {id, correct, response, ms}
signal continued

var q: Dictionary = {}
var show_feedback := true

var _look: Dictionary
var _get_response: Callable
var _choice_buttons: Array[Button] = []
var _lockables: Array[Control] = []
var _order_items: Array = []
var _order_list: VBoxContainer
var _submit: Button
var _skip: Button
var _notice: Label
var _feedback: VBoxContainer
var _start_ms := 0
var _done := false
var _continued := false
var _lab: LabSession
var _term: Terminal

func setup(question: Dictionary, feedback: bool = true) -> QuestionView:
	q = question
	show_feedback = feedback
	return self

func _ready() -> void:
	_look = Palette.current()
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d := ContentDB.get_domain(q.get("domain", ""))
	UI.label(self, ("%s  ·  %s" % [d.get("name", ""), q.get("subtopic", "")]).to_upper(), "H3")
	UI.label(self, str(q.get("stem", "")), "Stem", true)
	if q.has("exhibit"):
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		add_child(ex)
		UI.label(ex, str(q.exhibit), "Code")
	match q.get("type", ""):
		"mcq_single", "exhibit":
			_build_choices(false)
		"mcq_multi":
			_build_choices(true)
		"fill_in":
			_build_fill_in()
		"drag_match":
			_build_match()
		"drag_order":
			_build_order()
		"subnet_calc":
			_build_fields()
		"cli_task":
			_build_cli()
		_:
			UI.label(self, "Unsupported question type: %s" % q.get("type", "?"), "Muted")
			_get_response = func(): return null
	var row := UI.hbox(self, 12)
	_submit = UI.button(row, "Submit", _on_submit, true)
	_skip = UI.button(row, "I don't know", _on_submit.bind(true))
	_notice = UI.label(row, "", "Muted")
	_notice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_feedback = UI.vbox(self, 8)
	_feedback.visible = false
	_start_ms = Time.get_ticks_msec()

# --- builders ---

func _build_choices(multi: bool) -> void:
	if multi:
		UI.label(self, "Choose %d." % q.answer.size(), "Muted")
	var group: ButtonGroup = null if multi else ButtonGroup.new()
	var box := UI.vbox(self, 8)
	for i in q.choices.size():
		var b := Button.new()
		b.text = "%d.   %s" % [i + 1, q.choices[i]]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "Choice"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE   # digits + Enter drive choices
		box.add_child(b)
		_choice_buttons.append(b)
		_lockables.append(b)
	_get_response = func():
		var sel: Array = []
		for i in _choice_buttons.size():
			if _choice_buttons[i].button_pressed:
				sel.append(i)
		if multi:
			return sel
		return sel[0] if sel.size() > 0 else -1

func _build_fill_in() -> void:
	var le := _line_edit("Type your answer")
	add_child(le)
	le.text_submitted.connect(func(_t): _on_submit())
	_get_response = func(): return le.text
	UI.focus_later(le)

func _build_match() -> void:
	UI.label(self, "Match each item on the left.", "Muted")
	var rights: Array = q.answer.values() + q.get("distractors", [])
	rights.shuffle()
	var opts := {}
	for left in q.answer.keys():
		var row := UI.hbox(self, 12)
		var l := UI.label(row, str(left), "Body")
		l.custom_minimum_size.x = 280
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ob := OptionButton.new()
		ob.add_item("Choose...")
		for r in rights:
			ob.add_item(str(r))
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ob)
		opts[left] = ob
		_lockables.append(ob)
	_get_response = func():
		var d := {}
		for k in opts:
			var i: int = opts[k].selected
			d[k] = opts[k].get_item_text(i) if i > 0 else ""
		return d

func _build_order() -> void:
	UI.label(self, "Put these in order, first at the top.", "Muted")
	_order_items = q.answer.duplicate()
	for attempt in 6:
		_order_items.shuffle()
		if _order_items != q.answer:
			break
	_order_list = UI.vbox(self, 6)
	_render_order()
	_get_response = func(): return _order_items.duplicate()

func _render_order() -> void:
	for c in _order_list.get_children():
		_order_list.remove_child(c)
		c.queue_free()
	for i in _order_items.size():
		var row := UI.hbox(_order_list, 8)
		var item := Button.new()
		item.text = "%d.   %s" % [i + 1, _order_items[i]]
		item.theme_type_variation = "Choice"
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.disabled = _done
		row.add_child(item)
		var up := UI.button(row, "↑", _move.bind(i, -1))
		up.custom_minimum_size.x = 48
		up.disabled = _done or i == 0
		var down := UI.button(row, "↓", _move.bind(i, 1))
		down.custom_minimum_size.x = 48
		down.disabled = _done or i == _order_items.size() - 1

func _move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= _order_items.size():
		return
	var tmp = _order_items[i]
	_order_items[i] = _order_items[j]
	_order_items[j] = tmp
	_render_order()

func _build_fields() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	var inputs := {}
	var order: Array[LineEdit] = []
	for f in q.get("fields", []):
		var l := UI.label(grid, str(f.label), "Body")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var le := _line_edit(str(f.get("placeholder", "")))
		grid.add_child(le)
		inputs[f.key] = le
		order.append(le)
	for i in order.size():
		var next: LineEdit = order[i + 1] if i + 1 < order.size() else null
		order[i].text_submitted.connect(func(_t): next.grab_focus() if next else _on_submit())
	if order.size() > 0:
		UI.focus_later(order[0])
	_get_response = func():
		var d := {}
		for k in inputs:
			d[k] = inputs[k].text
		return d

func _build_cli() -> void:
	var lab: Dictionary = ContentDB.labs.get(q.get("lab", ""), {})
	_lab = LabSession.create(lab)
	if lab.has("topology"):
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		add_child(ex)
		UI.label(ex, lab.topology, "Code")
	var dev: String = _lab.sessions.keys()[0]
	_term = Terminal.new().setup(_lab.sessions[dev], "%s console. Type your commands, then press Submit." % dev)
	_term.custom_minimum_size.y = 300
	add_child(_term)
	_get_response = func(): return {"passed": _lab.all_ok()}

func _line_edit(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size.x = 280
	le.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_lockables.append(le)
	return le

# --- answering ---

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _done:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and show_feedback:
			get_viewport().set_input_as_handled()
			_continue()
		return
	var n: int = event.keycode - KEY_1
	if n >= 0 and n < _choice_buttons.size():
		var b := _choice_buttons[n]
		b.button_pressed = not b.button_pressed if b.button_group == null else true
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not _choice_buttons.is_empty():
		get_viewport().set_input_as_handled()
		_on_submit()

func _on_submit(skip: bool = false) -> void:
	if _done:
		return
	var response = _get_response.call()
	if not skip and _is_blank(response):
		_notice.text = "Answer first, or choose \"I don't know\"."
		return
	_done = true
	var ms := Time.get_ticks_msec() - _start_ms
	var correct := false if skip else Grader.grade(q, response)
	for c in _lockables:
		if c is LineEdit:
			c.editable = false
		elif c is BaseButton:
			c.disabled = true
	if not _order_items.is_empty():
		_render_order()
	if _term:
		_term.lock()
	_submit.visible = false
	_skip.visible = false
	_notice.text = ""
	answered.emit({"id": q.get("id", ""), "correct": correct, "response": response, "ms": ms})
	if show_feedback:
		_show_feedback(correct)
	else:
		_continue()

func _continue() -> void:
	if _continued:
		return
	_continued = true
	continued.emit()

func _is_blank(r: Variant) -> bool:
	if r == null:
		return true
	if r is int:
		return r < 0
	if r is String:
		return r.strip_edges().is_empty()
	if r is Array:
		return r.is_empty()
	if r is Dictionary:
		return r.values().all(func(v): return str(v).strip_edges().is_empty())
	return false

func _show_feedback(correct: bool) -> void:
	var good: Color = _look.good
	var bad: Color = _look.accent2
	var r: int = max(2, int(_look.radius) / 2)
	if not _choice_buttons.is_empty():
		var right: Array = q.answer if q.answer is Array else [q.answer]
		right = right.map(func(x): return int(x))
		for i in _choice_buttons.size():
			var b := _choice_buttons[i]
			var col := Color.TRANSPARENT
			if i in right:
				col = good
			elif b.button_pressed:
				col = bad
			if col.a > 0:
				b.add_theme_stylebox_override("disabled", ThemeFactory.box(Color(col, 0.16), col, r, 2, 16, 12))
	_feedback.visible = true
	var card := UI.card(_feedback)
	var head := UI.label(card, "Correct" if correct else "Not quite", "H2")
	head.add_theme_color_override("font_color", good if correct else bad)
	if not correct:
		UI.label(card, "Answer: " + Grader.answer_text(q), "Body", true)
		if _lab:
			for res in _lab.results():
				if not res.ok and not res.msg.is_empty():
					UI.label(card, "On the device: " + res.msg, "Muted", true)
					break
	UI.label(card, str(q.get("explanation", "")), "Body", true)
	var ref := str(q.get("lesson_ref", ""))
	if ContentDB.lessons.has(ref):
		UI.label(card, "From the lesson: " + ContentDB.lessons[ref].title, "Muted")
	var cont := UI.button(_feedback, "Continue", _continue, true)
	UI.focus_later(cont)
	UI.scroll_into_view(cont)
