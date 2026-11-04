extends GutTest
## M8 screen readers. Every screen, in every state a learner reaches, is checked the way a
## screen reader meets it: each control has a name that says what it is, and controls on
## one screen can be told apart. Answers, lab progress and exam time are announced.
##
## Godot (4.5+) reports a control's accessibility_name, or a button's own text. A text field's
## placeholder or a dropdown's current value isn't a label, so those need accessibility_name.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func before_each():
	SessionManager.navigate = false

func after_each():
	SessionManager.navigate = true
	SessionManager.steps = []
	SessionManager.index = -1
	SessionManager.results = []
	await wait_process_frames(1)

## What a screen reader announces as the control's name. Godot reads accessibility_name, then
## a button's own text ("Network components: Study unit", "Look: Night Ops"). A text field's
## placeholder or a dropdown's value alone isn't a name.
static func spoken_name(c: Control) -> String:
	var nm := c.accessibility_name.strip_edges()
	if c is OptionButton or c is LineEdit or c is TextEdit or c is Range:
		return nm
	var own: String = c.text.strip_edges() if c is Button else ""
	if nm.is_empty():
		return own
	return nm if own.is_empty() else "%s: %s" % [nm, own]

static func _interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or c is TextEdit or c is Range

## Problems on a screen: unnamed controls, names with no letters or digits, and two
## enabled controls with the same name.
static func audit(root: Node) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for c in _controls(root):
		if not _interactive(c) or not c.is_visible_in_tree() or c is ScrollBar:
			continue
		var nm := spoken_name(c).strip_edges()
		var what := "%s %s" % [c.get_class(), ("'%s'" % c.text) if "text" in c and not str(c.text).is_empty() else c.name]
		if nm.is_empty():
			problems.append("%s has no accessible name" % what)
			continue
		if RegEx.create_from_string("[A-Za-z0-9]").search(nm) == null:
			problems.append("%s is announced as '%s'" % [what, nm])
		var disabled: bool = c is BaseButton and c.disabled
		if not disabled and not c.has_meta("a11y_same_as_another"):
			var key := nm.to_lower()
			if seen.has(key):
				problems.append("two controls are both announced as '%s'" % nm)
			seen[key] = true
		# Tab must reach every enabled control that does something (screen readers follow focus).
		if not disabled and c is BaseButton and c.focus_mode == Control.FOCUS_NONE and not c.has_meta("display_only"):
			problems.append("%s can't be reached with Tab" % what)
	return problems

static func _controls(n: Node, out: Array = []) -> Array:
	if n is Control:
		out.append(n)
	for c in n.get_children():
		_controls(c, out)
	return out

func _open(scene_path: String, steps: Array = []) -> Control:
	SessionManager.steps = steps
	SessionManager.index = 0 if not steps.is_empty() else -1
	SessionManager.results = []
	var s: Control = load(scene_path).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	return s

func _check(root: Node, label: String) -> void:
	var p := audit(root)
	assert_eq(p.size(), 0, "%s:\n  %s" % [label, "\n  ".join(p)])

static func _find(n: Node, pred: Callable) -> Node:
	if pred.call(n):
		return n
	for c in n.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null

# --- Every screen ---------------------------------------------------------------------

func test_menu_dashboard_topics_and_settings():
	for path in ["MainMenu", "Dashboard", "Topics", "SettingsScreen"]:
		var s := await _open("res://ui/screens/%s.tscn" % path)
		_check(s, path)

func test_tutorial_and_lab():
	var lesson: String = ContentDB.lessons.keys()[0]
	_check(await _open("res://ui/screens/Tutorial.tscn", [{"kind": "tutorial", "lesson": lesson}]), "Tutorial")
	for lab_id in ContentDB.labs:
		if ContentDB.labs[lab_id].get("hidden", false):
			continue
		_check(await _open("res://ui/screens/Lab.tscn", [{"kind": "lab", "lab": lab_id}]), lab_id)

func test_every_question_type_before_and_after_answering():
	var by_type := {}
	for q in ContentDB.questions.values():
		by_type[q.type] = by_type.get(q.type, []) + [q.id]
	for t in by_type:
		for id in by_type[t].slice(0, 3):
			var s := await _open("res://ui/screens/Review.tscn", [{"kind": "review", "ids": [id], "title": "Quiz"}])
			_check(s, "%s (%s)" % [id, t])
			var qv: QuestionView = _find(s, func(n): return n is QuestionView)
			qv._on_submit(true)
			await wait_process_frames(1)
			_check(s, "%s (%s) answered" % [id, t])

func test_every_drill_before_and_after_answering():
	for did in ContentDB.drills:
		var s := await _open("res://ui/screens/DrillHost.tscn", [SessionManager.drill_step(did, true, 2)])
		_check(s, did)
		var d: DrillBase = _find(s, func(n): return n is DrillBase)
		d.autoplay(false)
		await wait_process_frames(1)
		_check(s, did + " answered")

func test_mock_exam_and_report():
	var step := SessionManager.mock_step("quick", 5)
	var s := await _open("res://ui/screens/MockExam.tscn", [step])
	_check(s, "exam intro")
	s._begin()
	await wait_process_frames(1)
	_check(s, "exam question")
	SessionManager.results = [{"kind": "exam", "title": "Quick mock exam", "exam": MockExam.score(step.ids, [], ContentDB.questions, ContentDB.domains, 825), "seconds": 60, "timed_out": false}]
	var sum: Control = load("res://ui/screens/Summary.tscn").instantiate()
	add_child_autofree(sum)
	await wait_process_frames(2)
	_check(sum, "exam report")

# --- What gets announced ----------------------------------------------------------------

func _review(id: String) -> Array:
	var s := await _open("res://ui/screens/Review.tscn", [{"kind": "review", "ids": [id], "title": "Quiz"}])
	return [s, _find(s, func(n): return n is QuestionView)]

func test_a_new_question_is_read_out_with_its_number():
	await _review("q.d3.route.003")
	assert_eq(UI.last_announcement, "Question 1 of 1. " + ContentDB.questions["q.d3.route.003"].stem)

func test_feedback_is_read_out_after_answering():
	var r := await _review("q.d3.route.003")
	var qv: QuestionView = r[1]
	qv._on_submit(true)
	var q: Dictionary = ContentDB.questions["q.d3.route.003"]
	assert_true(UI.last_announcement.begins_with("Not quite. Answer: " + Grader.answer_text(q)), UI.last_announcement)
	assert_string_contains(UI.last_announcement, q.explanation)

func test_digit_keys_say_what_they_selected():
	var r := await _review("q.d3.route.003")
	var qv: QuestionView = r[1]
	var ev := InputEventKey.new()
	ev.keycode = KEY_2
	ev.pressed = true
	qv._unhandled_key_input(ev)
	assert_eq(UI.last_announcement, "Selected: " + qv._choice_buttons[1].text)

func test_moving_an_item_keeps_focus_on_it_and_says_where_it_went():
	var r := await _review("q.d3.ospf.008")
	var qv: QuestionView = r[1]
	var first: String = qv._order_items[0]
	qv._move(0, 1)
	await wait_process_frames(2)
	assert_eq(UI.last_announcement, "%s, position 2 of %d" % [first, qv._order_items.size()])
	var focused := get_viewport().gui_get_focus_owner()
	assert_not_null(focused, "focus isn't lost when the list is rebuilt")
	assert_eq(focused.accessibility_name, "Move down: " + first, "focus stays on the arrow just used")
	qv._move(qv._order_items.size() - 2, 1)   # to the bottom: Move down is now disabled
	await wait_process_frames(2)
	var bottom: String = qv._order_items[-1]
	assert_eq(get_viewport().gui_get_focus_owner().accessibility_name, "Move up: " + bottom, "falls back to the other arrow")

func test_drill_items_and_results_are_read_out():
	var s := await _open("res://ui/screens/DrillHost.tscn", [SessionManager.drill_step("subnet_sprint", true, 2)])
	var d: DrillBase = _find(s, func(n): return n is DrillBase)
	assert_true(UI.last_announcement.begins_with("Item 1 / 2. "), UI.last_announcement)
	assert_string_contains(UI.last_announcement, d.prompt_text())
	d.autoplay(false)
	assert_true(UI.last_announcement.begins_with("Not quite. Answer: " + d.correct_answer()), UI.last_announcement)

func test_bit_keys_name_the_bit_and_the_running_total():
	var s := await _open("res://ui/screens/DrillHost.tscn", [SessionManager.drill_step("bit_flipper", true, 30)])
	var d = _find(s, func(n): return n is DrillBase)
	while d._bits.is_empty():   # find a dec-to-bin item (8 toggle bits)
		d.autoplay(true)
		d.next_item()
	var ev := InputEventKey.new()
	ev.keycode = KEY_1
	ev.pressed = true
	d._unhandled_key_input(ev)
	assert_eq(UI.last_announcement, "Bit worth 128 on. Current value: 128")

func test_unguided_bits_dont_give_away_place_values():
	var s := await _open("res://ui/screens/DrillHost.tscn", [SessionManager.drill_step("bit_flipper", false, 30)])
	var d = _find(s, func(n): return n is DrillBase)
	while d._bits.is_empty():
		d.autoplay(true)
		d.next_item()
	assert_eq(d._bits.map(func(b): return b.accessibility_name), ["Bit 1, leftmost", "Bit 2", "Bit 3", "Bit 4", "Bit 5", "Bit 6", "Bit 7", "Bit 8, rightmost"])

func test_lab_progress_and_command_output_are_read_out():
	var s := await _open("res://ui/screens/Lab.tscn", [{"kind": "lab", "lab": "lab.vlans"}])
	var term: Terminal = s._terms.values()[0]
	UI.last_announcement = ""
	term.run("enable")
	assert_eq(UI.last_announcement, "SW1#", "a silent command reads the new prompt")
	term.run("show vlan brief")
	assert_string_contains(UI.last_announcement, "VLAN Name")
	for l in ["configure terminal", "vlan 10", "name SALES", "vlan 20", "name ENGINEERING"]:
		term.run(l)
	assert_eq(UI.last_announcement, "Task 1 done. 1 of %d tasks done." % s.lab.tasks.size())
	assert_eq(s._rows[0][2].text, "Done", "done is said in words, not only by colour")
	assert_eq(s._rows[1][2].text, "")

func test_exam_time_is_spoken_at_set_points_only():
	var step := SessionManager.mock_step("quick", 5)   # 36 minutes
	var s := await _open("res://ui/screens/MockExam.tscn", [step])
	s._begin()
	UI.last_announcement = ""
	s._deadline_ms = Time.get_ticks_msec() + 31 * 60000
	s._process(0.0)
	assert_eq(UI.last_announcement, "", "nothing until a threshold is crossed")
	s._deadline_ms = Time.get_ticks_msec() + 29 * 60000
	s._process(0.0)
	assert_eq(UI.last_announcement, "30 minutes left.")
	UI.last_announcement = ""
	s._process(0.0)
	assert_eq(UI.last_announcement, "", "once only")
	s._deadline_ms = Time.get_ticks_msec() + 50000
	s._process(0.0)
	assert_eq(UI.last_announcement, "1 minute left.", "jumping past several thresholds reads the latest")

func test_tutorial_cards_are_read_out():
	var lesson: String = ContentDB.lessons.keys()[0]
	await _open("res://ui/screens/Tutorial.tscn", [{"kind": "tutorial", "lesson": lesson}])
	var card: Dictionary = ContentDB.lessons[lesson].cards[0]
	assert_true(UI.last_announcement.begins_with("Card 1 of %d. %s." % [ContentDB.lessons[lesson].cards.size(), card.heading]), UI.last_announcement)

func test_button_names_put_their_context_first():
	var s := await _open("res://ui/screens/Topics.tscn")
	var names := _controls(s).filter(func(c): return c is Button and c.visible).map(func(c): return spoken_name(c))
	var unit: String = ContentDB.lessons_for_domain(ContentDB.domains[0].id)[0].title
	assert_has(names, unit + ": Study unit")
	assert_has(names, unit + ": Tutorial")
	assert_has(names, ContentDB.domains[0].name + ": Quiz (20)")

