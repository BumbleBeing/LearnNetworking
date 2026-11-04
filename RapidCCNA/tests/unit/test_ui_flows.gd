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

func _play(script_path: String, answer_right: bool) -> Dictionary:
	var d: DrillBase = load(script_path).new()
	d.setup({"guided": true, "count": 4, "seed": 99})
	add_child_autofree(d)
	watch_signals(d)
	for i in 4:
		var ans: String = d.correct_answer()
		if d.has_method("_build_bits") and not d._bits.is_empty():
			var bits := Binary.to_bin8(d.item.value if answer_right else (d.item.value ^ 1))
			for k in 8:
				d._bits[k].button_pressed = bits[k] == "1"
		elif d._answer:
			d._answer.text = ans if answer_right else "999"
		d.submit()
		d.next_item()
	assert_signal_emitted(d, "finished")
	return get_signal_parameters(d, "finished")[0]

func test_subnet_sprint_full_round():
	var s := _play("res://minigames/SubnetSprint.gd", true)
	assert_eq(s.items, 4)
	assert_eq(s.correct, 4)
	var w := _play("res://minigames/SubnetSprint.gd", false)
	assert_eq(w.correct, 0)

func test_bit_flipper_full_round():
	var s := _play("res://minigames/BitFlipper.gd", true)
	assert_eq(s.items, 4)
	assert_eq(s.correct, 4)
	var w := _play("res://minigames/BitFlipper.gd", false)
	assert_eq(w.correct, 0)
