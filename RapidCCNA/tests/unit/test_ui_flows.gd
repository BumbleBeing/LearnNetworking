extends GutTest
## Integration: build real UI nodes, answer them programmatically, check signals.

func after_each():
	# Removed nodes are queue_free()d, which happens at the end of the frame. Let it pass
	# so GUT's orphan count reports real leaks, not nodes already on their way out.
	await wait_process_frames(1)

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _view(id: String) -> QuestionView:
	var v: QuestionView = QuestionView.new().setup(ContentDB.questions[id])
	add_child_autofree(v)
	return v

func test_every_question_renders_and_grades_correct_answer():
	for id in ContentDB.questions:
		for n in ContentDB.questions[id].get("variants", []).size() + 1:
			_render_and_grade(id, n)

## Shows one version of a question, answers it with its own key and expects "correct".
func _render_and_grade(id: String, version: int) -> void:
	var v: QuestionView = QuestionView.new().setup(ContentDB.question_version(id, version))
	add_child_autofree(v)
	watch_signals(v)
	var q: Dictionary = v.q
	var label := "%s v%d" % [id, version]
	if q.type == "cli_task":
		assert_eq(v._lab.apply_solution().size(), 0, label)
		v._on_submit()
		assert_true(get_signal_parameters(v, "answered")[0].correct, label)
		return
	v._get_response = func():
		if q.type in ["mcq_single", "exhibit"]:
			return int(q.answer)
		if q.type == "fill_in" and q.answer is Array:
			return q.answer[0]
		return q.answer
	v._on_submit()
	assert_signal_emitted(v, "answered", label)
	var res: Dictionary = get_signal_parameters(v, "answered")[0]
	assert_true(res.correct, label)
	assert_true(v._feedback.visible, label)

func test_cli_task_terminal_drives_device():
	var v := _view("q.d3.static.cli.001")
	watch_signals(v)
	v._term.run("enable")
	v._term.run("configure terminal")
	v._term.run("ip route 0.0.0.0 0.0.0.0 10.0.0.9")
	v._on_submit()
	assert_false(get_signal_parameters(v, "answered")[0].correct, "wrong next hop")
	var v2 := _view("q.d3.static.cli.001")
	watch_signals(v2)
	for l in ["en", "conf t", "ip route 0.0.0.0 0.0.0.0 10.0.0.2"]:
		v2._term.run(l)
	v2._on_submit()
	assert_true(get_signal_parameters(v2, "answered")[0].correct)

func test_blank_answer_is_blocked_but_skip_counts_as_wrong():
	var v := _view("q.d1.subnet.001")
	watch_signals(v)
	v._on_submit()
	assert_signal_not_emitted(v, "answered")
	v._on_submit(true)
	assert_signal_emitted(v, "answered")
	assert_false(get_signal_parameters(v, "answered")[0].correct)

func test_choice_buttons_select_and_grade():
	var v := _view("q.d1.tcpudp.001")
	watch_signals(v)
	v.choice_button(0).button_pressed = true
	v.choice_button(2).button_pressed = true
	v._on_submit()
	assert_true(get_signal_parameters(v, "answered")[0].correct)

func test_order_moves():
	var v := _view("q.d1.tcpudp.002")
	v._order_items = ["B", "A", "C"]
	v._move(1, -1)
	assert_eq(v._order_items, ["A", "B", "C"])
	v._move(0, -1)
	assert_eq(v._order_items, ["A", "B", "C"], "moving past the top is a no-op")

func test_continue_emits_once():
	var v := _view("q.d1.subnet.005")
	watch_signals(v)
	v._on_submit(true)
	v._continue()
	v._continue()
	assert_signal_emit_count(v, "continued", 1)

func _play(def: Dictionary, answer_right: bool) -> Dictionary:
	var d: DrillBase = load(def.script).new()
	d.setup({"guided": true, "count": 4, "seed": 99, "generator": def.get("generator", "")})
	add_child_autofree(d)
	watch_signals(d)
	for i in 4:
		d.autoplay(answer_right)
		assert_true(d._answered, "%s item %d answered" % [def.id, i])
		assert_false(d.explain().is_empty(), def.id)
		d.next_item()
	assert_signal_emitted(d, "finished", def.id)
	return get_signal_parameters(d, "finished")[0]

func test_every_drill_plays_a_full_round():
	for def in ContentDB.drills.values():
		var s := _play(def, true)
		assert_eq(s.items, 4, def.id)
		assert_eq(s.correct, 4, def.id)
		var w := _play(def, false)
		assert_eq(w.correct, 0, "%s wrong answers" % def.id)

func test_choice_drill_marks_choices_and_keys_work():
	var d: DrillBase = load("res://minigames/GenDrill.gd").new()
	d.setup({"guided": false, "count": 2, "seed": 1, "generator": "res://core/net/RouteGen.gd"})
	add_child_autofree(d)
	assert_gt(d._choices.size(), 1)
	var ev := InputEventKey.new()
	ev.keycode = KEY_1
	ev.pressed = true
	d._unhandled_key_input(ev)
	assert_true(d._answered, "pressing 1 answers")
	assert_true(d._choices[0].disabled)
	assert_false(d._hint_btn.visible, "no hints in unguided mode")

func test_choices_are_shuffled_but_graded_by_content():
	var orders := {}
	for i in 30:
		var v := _view("q.d1.subnet.001")
		orders[str(v._choice_order)] = true
		watch_signals(v)
		v.choice_button(int(v.q.answer)).button_pressed = true
		v._on_submit()
		assert_true(get_signal_parameters(v, "answered")[0].correct)
		assert_eq(get_signal_parameters(v, "answered")[0].response, int(v.q.answer), "response keeps the content's index")
		assert_string_contains(v._choice_buttons[0].text, "1.", "numbers follow screen position")
	assert_gt(orders.size(), 1, "the order changes between showings")

func test_digit_picks_by_screen_position():
	var v := _view("q.d1.subnet.001")
	var two := InputEventKey.new()
	two.keycode = KEY_2
	two.pressed = true
	v._unhandled_key_input(two)
	assert_true(v._choice_buttons[1].button_pressed)

func test_text_inputs_are_centred():
	for t in ["fill_in", "subnet_calc"]:
		var id: String = ContentDB.questions.keys().filter(func(k): return ContentDB.questions[k].type == t)[0]
		var v := _view(id)
		var box: Control = v.find_children("*", "LineEdit", true, false)[0] if t == "fill_in" else v.find_children("*", "GridContainer", true, false)[0]
		assert_eq(box.size_flags_horizontal, Control.SIZE_SHRINK_CENTER, t)

# --- Question variants ---

const VQ := {"id": "q.test.variant", "domain": "d1", "subtopic": "1.6", "type": "mcq_single", "lesson_ref": "d1.subnetting_basics",
	"stem": "Network address of 192.168.1.130/26?", "choices": ["192.168.1.0", "192.168.1.64", "192.168.1.128", "192.168.1.192"],
	"answer": 2, "explanation": "130 rounds down to 128.",
	"variants": [{"stem": "Network address of 192.168.1.70/26?", "answer": 1, "explanation": "70 rounds down to 64."}]}

func test_question_version_merges_a_variant_over_the_original():
	ContentDB.questions[VQ.id] = VQ.duplicate(true)
	var v1 := ContentDB.question_version(VQ.id, 1)
	assert_eq(v1.stem, "Network address of 192.168.1.70/26?")
	assert_eq(v1.answer, 1)
	assert_eq(v1.choices, VQ.choices, "unchanged fields come from the original")
	assert_eq(v1.id, VQ.id, "every version shares the original's id and review card")
	assert_false(v1.has("variants"))
	assert_eq(ContentDB.question_version(VQ.id, 0).stem, VQ.stem)
	assert_eq(ContentDB.question_version(VQ.id, 5).variant, 0, "an unknown version falls back to the original")
	ContentDB.questions.erase(VQ.id)

func test_pick_version_reaches_every_version():
	ContentDB.questions[VQ.id] = VQ.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 40:
		seen[ContentDB.pick_version(VQ.id, rng).variant] = true
	assert_eq(seen.keys().size(), 2)
	ContentDB.questions.erase(VQ.id)

func test_answers_record_the_version_shown_and_grade_against_it():
	ContentDB.questions[VQ.id] = VQ.duplicate(true)
	var v := QuestionView.new().setup(ContentDB.question_version(VQ.id, 1))
	add_child_autofree(v)
	watch_signals(v)
	v.choice_button(1).button_pressed = true
	v._on_submit()
	var r: Dictionary = get_signal_parameters(v, "answered")[0]
	assert_true(r.correct, "graded against the variant's answer")
	assert_eq(r.variant, 1)
	var report := MockExam.score([VQ.id], [{"id": VQ.id, "variant": 1, "correct": false, "response": 0}], ContentDB.questions, ContentDB.domains, 825)
	assert_eq(report.missed[0].variant, 1, "the exam report knows which version was missed")
	ContentDB.questions.erase(VQ.id)
