extends GutTest
## Integration: build real UI nodes, answer them programmatically, check signals.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func _view(id: String) -> QuestionView:
	var v: QuestionView = QuestionView.new().setup(ContentDB.questions[id])
	add_child_autofree(v)
	return v

func test_every_question_renders_and_grades_correct_answer():
	for id in ContentDB.questions:
		var v := _view(id)
		watch_signals(v)
		var q: Dictionary = v.q
		if q.type == "cli_task":
			assert_eq(v._lab.apply_solution().size(), 0, id)
			v._on_submit()
			assert_true(get_signal_parameters(v, "answered")[0].correct, id)
			continue
		v._get_response = func():
			if q.type in ["mcq_single", "exhibit"]:
				return int(q.answer)
			if q.type == "fill_in" and q.answer is Array:
				return q.answer[0]
			return q.answer
		v._on_submit()
		assert_signal_emitted(v, "answered", id)
		var res: Dictionary = get_signal_parameters(v, "answered")[0]
		assert_true(res.correct, id)
		assert_true(v._feedback.visible, id)

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
	v._choice_buttons[0].button_pressed = true
	v._choice_buttons[2].button_pressed = true
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
