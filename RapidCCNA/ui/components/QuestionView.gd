class_name QuestionView
extends VBoxContainer
## Renders one question of any non-CLI type, grades it and shows an explanation.
## Keyboard: 1-9 pick choices, Enter submits / continues.

signal answered(result: Dictionary)   # {id, correct, response, ms, skipped}
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
var _study: Button
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
	UI.rich(self, str(q.get("stem", "")), "Stem")
	if q.has("exhibit"):
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		add_child(ex)
		UI.rich(ex, str(q.exhibit), "Code", false)
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
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_submit = UI.button(row, "Submit", _on_submit, true)
	_skip = UI.button(row, "I don't know" if show_feedback else "Skip", _on_submit.bind(true))
	# Study reopens the question's lesson. Not in mock exams (no feedback), like the real exam.
	if show_feedback and ContentDB.lessons.has(_lesson_ref()):
		_study = UI.button(row, "Study", _open_study)
		_study.tooltip_text = "Read the lesson: " + str(ContentDB.lessons[_lesson_ref()].get("title", ""))
	_notice = UI.label(self, "", "Muted")
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.visible = false
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
		# Digits + Enter still work; Tab reaches each choice too, so screen readers can.
		b.focus_mode = Control.FOCUS_ALL
		box.add_child(b)
		UI.rich_button(b)
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
	le.accessibility_name = "Your answer"
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
		var l := UI.rich(row, str(left), "Body", false)
		l.custom_minimum_size.x = 280
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ob := OptionButton.new()
		ob.accessibility_name = str(left)   # read as "HSRP: Choose..." then "HSRP: <pick>"
		ob.add_item("Choose...")
		for r in rights:
			ob.add_item(str(r))
			ob.set_item_tooltip(ob.item_count - 1, Glossary.tooltip(str(r)))
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

## focus_at/focus_dir: after a move, keep keyboard focus on the moved item's arrow.
func _render_order(focus_at: int = -1, focus_dir: int = 0) -> void:
	for c in _order_list.get_children():
		_order_list.remove_child(c)
		c.queue_free()
	var n := _order_items.size()
	for i in n:
		var row := UI.hbox(_order_list, 8)
		var item := Button.new()
		item.text = "%d.   %s" % [i + 1, _order_items[i]]
		item.theme_type_variation = "Choice"
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.disabled = _done
		row.add_child(item)
		UI.rich_button(item)
		item.focus_mode = Control.FOCUS_NONE   # the item itself does nothing; its arrows move it
		item.set_meta("display_only", true)
		var up := UI.button(row, "↑", _move.bind(i, -1))
		up.custom_minimum_size.x = 48
		up.disabled = _done or i == 0
		up.accessibility_name = "Move up: %s" % _order_items[i]
		var down := UI.button(row, "↓", _move.bind(i, 1))
		down.custom_minimum_size.x = 48
		down.disabled = _done or i == n - 1
		down.accessibility_name = "Move down: %s" % _order_items[i]
		if i == focus_at:
			# At the top or bottom the arrow just used is disabled, so use the other one.
			var target := up if focus_dir < 0 else down
			if target.disabled:
				target = down if target == up else up
			UI.focus_later(target)

func _move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= _order_items.size():
		return
	var tmp = _order_items[i]
	_order_items[i] = _order_items[j]
	_order_items[j] = tmp
	_render_order(j, d)
	UI.announce("%s, position %d of %d" % [_order_items[j], j + 1, _order_items.size()])

func _build_fields() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	var inputs := {}
	var order: Array[LineEdit] = []
	for f in q.get("fields", []):
		var l := UI.rich(grid, str(f.label), "Body", false)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var le := _line_edit(str(f.get("placeholder", "")))
		le.accessibility_name = str(f.label)
		grid.add_child(le)
		inputs[f.key] = le
		order.append(le)
	for i in order.size():
		var next: LineEdit = order[i + 1] if i + 1 < order.size() else null
		order[i].text_submitted.connect(func(_t):
			if next:
				next.grab_focus()
			else:
				_on_submit())
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
		UI.rich(ex, str(lab.topology), "Code", false)
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
	if not event is InputEventKey or not event.pressed or event.echo or StudyOverlay.is_open():
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
		UI.announce(("Selected: " if b.button_pressed else "Cleared: ") + b.text)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not _choice_buttons.is_empty():
		get_viewport().set_input_as_handled()
		_on_submit()

func _on_submit(skip: bool = false) -> void:
	if _done:
		return
	var response = _get_response.call()
	if not skip and _is_blank(response):
		_notice.text = "Answer first, or choose \"I don't know\"."
		_notice.visible = true
		UI.announce(_notice.text)
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
	_skip.visible = false   # Study stays, to read up on the answer
	_notice.text = ""
	_notice.visible = false
	answered.emit({"id": q.get("id", ""), "correct": correct, "response": response, "ms": ms, "skipped": skip})
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
	if not _choice_buttons.is_empty():
		var right: Array = q.answer if q.answer is Array else [q.answer]
		right = right.map(func(x): return int(x))
		for i in _choice_buttons.size():
			if i in right:
				UI.mark_choice(_choice_buttons[i], true)
			elif _choice_buttons[i].button_pressed:
				UI.mark_choice(_choice_buttons[i], false)
	_feedback.visible = true
	var card := UI.card(_feedback)
	var head := UI.label(card, "Correct" if correct else "Not quite", "H2")
	head.add_theme_color_override("font_color", good if correct else bad)
	if not correct:
		UI.rich(card, "Answer: " + Grader.answer_text(q), "Body")
		if _lab:
			for res in _lab.results():
				if not res.ok and not res.msg.is_empty():
					UI.rich(card, "On the device: " + res.msg, "Muted")
					break
	UI.rich(card, str(q.get("explanation", "")), "Body")
	var ref := _lesson_ref()
	if ContentDB.lessons.has(ref):
		UI.rich(card, "From the lesson: " + ContentDB.lessons[ref].title, "Muted")
	var cont := UI.button(_feedback, "Continue", _continue, true)
	UI.focus_later(cont)
	UI.scroll_into_view(cont)
	# Focus jumps to Continue, so read the result out: verdict, the right answer, why.
	var spoken := PackedStringArray(["Correct." if correct else "Not quite."])
	if not correct:
		spoken.append("Answer: %s." % Grader.answer_text(q))
	spoken.append(str(q.get("explanation", "")))
	UI.announce(" ".join(spoken))

# --- studying ---

func _lesson_ref() -> String:
	return str(q.get("lesson_ref", ""))

## Opens the lesson over the screen; the question waits underneath, unchanged.
func _open_study() -> StudyOverlay:
	var o := StudyOverlay.open(self, ContentDB.lessons.get(_lesson_ref(), {}))
	o.closed.connect(func():
		if is_instance_valid(_study):
			UI.focus_later(_study))
	return o
