extends GutTest

func test_mcq_single_handles_json_floats():
	var q := {"type": "mcq_single", "choices": ["a", "b"], "answer": 1.0}
	assert_true(Grader.grade(q, 1))
	assert_false(Grader.grade(q, 0))
	assert_false(Grader.grade(q, -1))
	assert_eq(Grader.answer_text(q), "b")

func test_mcq_multi_is_order_insensitive():
	var q := {"type": "mcq_multi", "choices": ["a", "b", "c"], "answer": [2.0, 0.0]}
	assert_true(Grader.grade(q, [0, 2]))
	assert_false(Grader.grade(q, [0]))
	assert_false(Grader.grade(q, [0, 1, 2]))

func test_fill_in_accepts_alternatives_and_normalises():
	var q := {"type": "fill_in", "answer": ["11111000", "1111 1000"]}
	assert_true(Grader.grade(q, "1111   1000 "))
	assert_true(Grader.grade(q, "11111000"))
	assert_false(Grader.grade(q, "11110000"))
	var n := {"type": "fill_in", "answer": "14"}
	assert_true(Grader.grade(n, " 14"))
	assert_false(Grader.grade(n, "14 hosts"))

func test_drag_match():
	var q := {"type": "drag_match", "answer": {"A": "/25", "B": "/26"}}
	assert_true(Grader.grade(q, {"A": "/25", "B": "/26"}))
	assert_false(Grader.grade(q, {"A": "/26", "B": "/25"}))
	assert_false(Grader.grade(q, {"A": "/25"}))

func test_drag_order():
	var q := {"type": "drag_order", "answer": ["SYN", "SYN-ACK", "ACK"]}
	assert_true(Grader.grade(q, ["SYN", "SYN-ACK", "ACK"]))
	assert_false(Grader.grade(q, ["SYN-ACK", "SYN", "ACK"]))

func test_subnet_calc_compares_values():
	var q := {"type": "subnet_calc", "answer": {"network": "172.16.32.0", "hosts": "4094"},
		"fields": [{"key": "network", "label": "Network"}, {"key": "hosts", "label": "Hosts"}]}
	assert_true(Grader.grade(q, {"network": "172.16.32.0 ", "hosts": "4094"}))
	assert_false(Grader.grade(q, {"network": "172.16.32.1", "hosts": "4094"}))
	assert_eq(Grader.answer_text(q), "Network: 172.16.32.0, Hosts: 4094")

func test_cli_task():
	var q := {"type": "cli_task", "answer": "ip route 0.0.0.0 0.0.0.0 10.0.0.2"}
	assert_true(Grader.grade(q, {"passed": true}))
	assert_false(Grader.grade(q, {"passed": false}))
	assert_false(Grader.grade(q, "ip route 0.0.0.0 0.0.0.0 10.0.0.2"))

func test_every_shipped_question_accepts_its_own_answer():
	ContentDB.load_all(ContentDB.ROOT)
	for q in ContentDB.questions.values():
		var resp = q.answer
		if q.type in ["mcq_single", "exhibit"]:
			resp = int(q.answer)
		elif q.type == "fill_in" and q.answer is Array:
			resp = q.answer[0]
		elif q.type == "cli_task":
			resp = {"passed": true}
		assert_true(Grader.grade(q, resp), q.id)
		assert_false(Grader.answer_text(q).is_empty(), q.id)
