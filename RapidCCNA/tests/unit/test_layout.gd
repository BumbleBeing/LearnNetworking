extends GutTest
## Layout: nothing runs off the side of the window. Every screen is opened with real content
## (every question before and after answering, every lesson card, lab, drill and the exam
## report) at the designed 1280x720 canvas and at the smallest one (960x360, a phone held
## sideways), and no visible control may end past the right edge. Long text has to wrap.

const SIZES := [Vector2i(1280, 720), Vector2i(960, 360)]

var _saved_size: Vector2i

func before_all():
	ContentDB.load_all(ContentDB.ROOT)
	_saved_size = get_tree().root.size

func after_all():
	get_tree().root.size = _saved_size

func before_each():
	SessionManager.navigate = false

func after_each():
	SessionManager.navigate = true
	SessionManager.steps = []
	SessionManager.index = -1
	SessionManager.results = []
	await wait_process_frames(1)

func _set_size(s: Vector2i) -> void:
	get_tree().root.size = s
	await wait_process_frames(2)

## What makes a screen wider than the window. Starts from each outermost control that runs
## past the right edge and follows the child whose minimum width forces it, down to the cause:
## a single control (a label that doesn't wrap) or a row whose items together are too wide.
static func overflow(root: Node) -> PackedStringArray:
	var w: float = root.get_viewport().get_visible_rect().size.x
	var out := PackedStringArray()
	var seen := {}
	for c in root.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or c is ScrollBar or c.size.x <= 0 or _shown_rect(c).end.x <= w + 1:
			continue
		var cause := _widest_cause(c)
		if seen.has(cause):
			continue
		seen[cause] = true
		out.append(_describe(cause, w))
	return out

## The part of c that can be seen: clipped by every ancestor that clips its children (a box
## that scrolls sideways shows a wide diagram without widening the page).
static func _shown_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p:
		if p is Control and p.clip_contents:
			r = r.intersection(p.get_global_rect())
		p = p.get_parent()
	return r

static func _widest_cause(c: Control) -> Control:
	if c is HBoxContainer or c is GridContainer:
		return c   # its children's widths add up
	var widest: Control = null
	for k in c.get_children():
		if k is Control and k.visible and not k is ScrollBar and not k.top_level:
			if widest == null or k.get_combined_minimum_size().x > widest.get_combined_minimum_size().x:
				widest = k
	# Containers pad their children (margins, card padding); stop only when c's own minimum
	# size, not a child, is what makes it wide.
	if widest == null or widest.get_combined_minimum_size().x < c.get_combined_minimum_size().x - 120:
		return c
	return _widest_cause(widest)

static func _describe(c: Control, w: float) -> String:
	var t := ""
	if "text" in c:
		t = " '%s'" % str(c.text).replace("\n", " / ").left(70)
	elif c is HBoxContainer:
		var parts := PackedStringArray()
		for k in c.get_children():
			if k is Control and k.visible:
				parts.append("%s%s %d" % [k.get_class(), (" '%s'" % str(k.text).left(30)) if "text" in k else "", int(k.get_combined_minimum_size().x)])
		t = " [" + ", ".join(parts) + "]"
	return "%s%s needs %d px, window is %d wide" % [c.get_class(), t, int(c.get_combined_minimum_size().x), int(w)]

func _open(scene_path: String, steps: Array = []) -> Control:
	SessionManager.steps = steps
	SessionManager.index = 0 if not steps.is_empty() else -1
	SessionManager.results = []
	var s: Control = load(scene_path).instantiate()
	add_child_autofree(s)
	await wait_process_frames(3)
	return s

## Reports only the first few problems per screen so a failure stays readable.
func _check(root: Node, label: String) -> bool:
	var p := overflow(root)
	if p.is_empty():
		return true
	fail_test("%s at %s:\n  %s" % [label, root.get_viewport().get_visible_rect().size, "\n  ".join(p.slice(0, 4))])
	return false

func test_main_screens():
	for size in SIZES:
		await _set_size(size)
		for path in ["MainMenu", "Dashboard", "Topics", "SettingsScreen"]:
			var s := await _open("res://ui/screens/%s.tscn" % path)
			_check(s, path)
			s.queue_free()
	assert_true(true)

func test_every_question_before_and_after_answering():
	for size in SIZES:
		await _set_size(size)
		var bad := 0
		for id in _every_version():
			if bad >= 5:
				break   # enough to act on
			var s := await _open("res://ui/screens/Review.tscn", [{"kind": "review", "ids": [id], "title": "Quiz"}])
			var ok := _check(s, id)
			var qv: QuestionView = s.find_children("*", "QuestionView", true, false)[0]
			qv._on_submit(true)
			await wait_process_frames(2)
			ok = _check(s, id + " answered") and ok
			bad += 0 if ok else 1
			s.queue_free()
	for id in ContentDB.questions.keys().filter(func(k): return k.contains("~v")):
		ContentDB.questions.erase(id)
	assert_true(true)

## Every question id, plus a stand-in "<id>~vN" for each variant so each version
## is laid out on its own (a review of the real id picks a version at random).
func _every_version() -> Array:
	var out: Array = []
	for id in ContentDB.questions.keys():
		if id.contains("~v"):
			continue
		out.append(id)
		for n in range(1, ContentDB.questions[id].get("variants", []).size() + 1):
			var only := ContentDB.question_version(id, n)
			only.id = "%s~v%d" % [id, n]
			ContentDB.questions[only.id] = only
			out.append(only.id)
	return out

func test_every_lesson_in_tutorial_and_study_overlay():
	for size in SIZES:
		await _set_size(size)
		for lesson_id in ContentDB.lessons:
			var s := await _open("res://ui/screens/Tutorial.tscn", [{"kind": "tutorial", "lesson": lesson_id}])
			for i in ContentDB.lessons[lesson_id].cards.size():
				s._i = i
				s._show_card()
				await wait_process_frames(2)
				if not _check(s, "%s card %d" % [lesson_id, i + 1]):
					break
			s.queue_free()
			var host := Control.new()
			host.theme = ThemeFactory.build(Palette.current(), Settings.font_scale)
			host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child_autofree(host)
			var o := StudyOverlay.open(host, ContentDB.lessons[lesson_id])
			await wait_process_frames(3)
			_check(o, lesson_id + " study overlay")
			host.queue_free()
	assert_true(true)

func test_labs_drills_exam_and_report():
	for size in SIZES:
		await _set_size(size)
		for lab_id in ContentDB.labs:
			if ContentDB.labs[lab_id].get("hidden", false):
				continue
			var s := await _open("res://ui/screens/Lab.tscn", [{"kind": "lab", "lab": lab_id}])
			s._show_solution()
			s._show_hint()
			await wait_process_frames(2)
			_check(s, lab_id + " with hint and solution")
			s.queue_free()
		for did in ContentDB.drills:
			var s := await _open("res://ui/screens/DrillHost.tscn", [SessionManager.drill_step(did, true, 6)])
			var d: DrillBase = s.find_children("*", "DrillBase", true, false)[0]
			for i in 6:   # several items: generators vary in length
				d._show_hint()
				d.autoplay(false)
				await wait_process_frames(2)
				if not _check(s, "%s item %d" % [did, i + 1]):
					break
				d.next_item()
				await wait_process_frames(1)
			s.queue_free()
		var step := SessionManager.mock_step("full", 7)
		var ex := await _open("res://ui/screens/MockExam.tscn", [step])
		_check(ex, "exam intro")
		ex.queue_free()
		# A report where every question was missed: every explanation is shown.
		var results: Array = step.ids.map(func(id): return {"id": id, "correct": false, "response": null, "skipped": true})
		SessionManager.steps = [step]
		SessionManager.index = 0
		SessionManager.results = [{"kind": "exam", "title": "Full mock exam", "seconds": 7200, "timed_out": true,
			"exam": MockExam.score(step.ids, results, ContentDB.questions, ContentDB.domains, 825)}]
		var sum: Control = load("res://ui/screens/Summary.tscn").instantiate()
		add_child_autofree(sum)
		await wait_process_frames(3)
		_check(sum, "exam report")
		sum.queue_free()
	assert_true(true)

# --- Opening screens -----------------------------------------------------------------------

static func _page_scrolls(root: Node) -> Array:
	return root.find_children("*", "ScrollContainer", true, false).filter(func(s): return s.is_visible_in_tree() and s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)

func test_screens_open_at_their_top():
	await _set_size(SIZES[0])
	var step := SessionManager.mock_step("full", 7)
	var cases := [
		["res://ui/screens/Topics.tscn", []],
		["res://ui/screens/SettingsScreen.tscn", []],
		["res://ui/screens/Lab.tscn", [{"kind": "lab", "lab": "lab.stp"}]],   # focuses the terminal, far down
		["res://ui/screens/Tutorial.tscn", [{"kind": "tutorial", "lesson": ContentDB.lessons.keys()[0]}]],
	]
	for c in cases:
		var s := await _open(c[0], c[1])
		await wait_process_frames(3)
		for sc in _page_scrolls(s):
			if c[0].contains("Topics"):
				assert_gt(sc.get_v_scroll_bar().max_value, sc.size.y, "Topics is long enough to scroll")
			assert_eq(sc.scroll_vertical, 0, "%s opens at its top" % c[0])
		s.queue_free()
	var results: Array = step.ids.map(func(id): return {"id": id, "correct": false, "response": null, "skipped": true})
	SessionManager.steps = [step]
	SessionManager.index = 0
	SessionManager.results = [{"kind": "exam", "title": "Full mock exam", "seconds": 7200, "timed_out": false,
		"exam": MockExam.score(step.ids, results, ContentDB.questions, ContentDB.domains, 825)}]
	var sum: Control = load("res://ui/screens/Summary.tscn").instantiate()
	add_child_autofree(sum)
	await wait_process_frames(4)
	for sc in _page_scrolls(sum):
		assert_eq(sc.scroll_vertical, 0, "the exam report opens at its top, not at its Back button")

func test_study_covers_the_screen_and_starts_at_the_top():
	await _set_size(SIZES[0])
	var s := await _open("res://ui/screens/Review.tscn", [{"kind": "review", "ids": ["q.d3.route.003"], "title": "Quiz"}])
	var qv: QuestionView = s.find_children("*", "QuestionView", true, false)[0]
	var o: StudyOverlay = qv._open_study()
	await wait_process_frames(3)
	assert_eq(o.size, get_viewport().get_visible_rect().size, "the overlay fills the window (it was 0x0, so Study seemed to do nothing)")
	for sc in _page_scrolls(o):
		assert_eq(sc.scroll_vertical, 0, "the lesson starts at its first card")
	o.close()

## A button, or a row of buttons taken together (the span of its visible buttons), sits in
## the middle of the window.
func _centred(c: Control) -> void:
	var mid: float = get_viewport().get_visible_rect().size.x / 2.0
	var r := c.get_global_rect()
	var what: String = c.text if c is Button else "row"
	if c is BoxContainer:
		var shown := c.get_children().filter(func(k): return k is Button and k.visible)
		r = shown[0].get_global_rect()
		for k in shown:
			r = r.merge(k.get_global_rect())
		what = " + ".join(shown.map(func(k): return k.text))
	assert_almost_eq(r.get_center().x, mid, 2.0, "'%s' is centred" % what)

func test_bottom_buttons_are_centred():
	await _set_size(SIZES[0])
	var d_host := await _open("res://ui/screens/DrillHost.tscn", [SessionManager.drill_step("subnet_sprint", true, 2)])
	var d: DrillBase = d_host.find_children("*", "DrillBase", true, false)[0]
	_centred(d._submit_btn.get_parent())   # Submit + Hint as a group
	d.autoplay(false)
	await wait_process_frames(2)
	_centred(d._next_btn.get_parent())     # Next + Hint
	d_host.queue_free()
	var ex := await _open("res://ui/screens/MockExam.tscn", [SessionManager.mock_step("quick", 3)])
	_centred(ex.find_children("*", "Button", true, false).filter(func(b): return b.text == "Begin exam")[0])
	ex.queue_free()
	SessionManager.results = [{"kind": "drill", "title": "Subnet Sprint", "items": 2, "correct": 1}]
	var sum: Control = load("res://ui/screens/Summary.tscn").instantiate()
	add_child_autofree(sum)
	await wait_process_frames(3)
	_centred(sum.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Back to"))[-1])

func test_a_long_session_plan_scrolls_inside_its_card():
	var saved_path := Progress.save_path
	Progress.save_path = "user://test_layout_plan.json"
	Progress.reset()
	for d in ContentDB.drills:   # every drill and lab due: one plan line each
		SRS.grade("gen.%s.a" % d, 1, 1_000_000_000)
	for l in ContentDB.labs:
		SRS.grade(l, 1, 1_000_000_000)
	for size in SIZES:
		await _set_size(size)
		var s := await _open("res://ui/screens/Dashboard.tscn")
		await wait_process_frames(2)
		var sc: ScrollContainer = s.find_child("PlanScroll", true, false)
		var content: Control = sc.get_child(0)
		assert_lte(sc.size.y, s.PLAN_MAX_HEIGHT + 1, "the plan stops growing at %s" % size)
		assert_gt(content.size.y, sc.size.y, "and the rest scrolls")
		s.queue_free()
	Progress.save_path = saved_path
	Progress.load_game()

func test_a_short_session_plan_shows_in_full():
	var saved_path := Progress.save_path
	Progress.save_path = "user://test_layout_plan.json"
	Progress.reset()
	var s := await _open("res://ui/screens/Dashboard.tscn")
	await wait_process_frames(2)
	var sc: ScrollContainer = s.find_child("PlanScroll", true, false)
	assert_almost_eq(sc.size.y, sc.get_child(0).size.y, 1.0, "no scrolling needed for a few lines")
	s.queue_free()
	Progress.save_path = saved_path
	Progress.load_game()
