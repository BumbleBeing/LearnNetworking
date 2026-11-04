extends GutTest
## Mock exam: weighted selection, scoring, history and the exam screen.

const DOMAINS := [
	{"id": "a", "weight": 20}, {"id": "b", "weight": 20}, {"id": "c", "weight": 25},
	{"id": "d", "weight": 10}, {"id": "e", "weight": 15}, {"id": "f", "weight": 10},
]
var _orig_path: String

func before_each():
	ContentDB.load_all(ContentDB.ROOT)
	_orig_path = Progress.save_path
	Progress.save_path = "user://test_mock_save.json"
	Progress.reset()
	SessionManager.navigate = false

func after_each():
	SessionManager.navigate = true
	if FileAccess.file_exists("user://test_mock_save.json"):
		DirAccess.remove_absolute("user://test_mock_save.json")
	Progress.save_path = _orig_path
	Progress.load_game()
	# Removed nodes are queue_free()d, which happens at the end of the frame. Let it pass
	# so GUT's orphan count reports real leaks, not nodes already on their way out.
	await wait_process_frames(1)

func _rng(rng_seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = rng_seed
	return r

## n questions per domain, spread over `subs` subtopics.
func _bank(n: int, subs: int = 3) -> Array:
	var out: Array = []
	for d in DOMAINS:
		for i in n:
			out.append({"id": "%s.%d" % [d.id, i], "domain": d.id, "subtopic": "%s.s%d" % [d.id, i % subs], "type": "mcq_single"})
	return out

func _count(ids: Array, bank: Array, key: String) -> Dictionary:
	var by_id := {}
	for q in bank:
		by_id[q.id] = q
	var c := {}
	for id in ids:
		var k: String = by_id[id][key]
		c[k] = int(c.get(k, 0)) + 1
	return c

func test_allocation_follows_weights_and_sums_to_n():
	assert_eq(MockExam.allocate(DOMAINS, 100), {"a": 20, "b": 20, "c": 25, "d": 10, "e": 15, "f": 10})
	var q := MockExam.allocate(DOMAINS, 30)
	assert_eq(q, {"a": 6, "b": 6, "c": 8, "d": 3, "e": 4, "f": 3}, "30 x weights = 6, 6, 7.5, 3, 4.5, 3; .5s go in blueprint order")
	for n in [1, 7, 30, 61, 100]:
		var total := 0
		for v in MockExam.allocate(DOMAINS, n).values():
			total += v
		assert_eq(total, n, "n=%d" % n)

func test_build_is_weighted_unique_and_repeatable():
	var bank := _bank(40)
	var ids := MockExam.build(bank, DOMAINS, 100, _rng(7))
	assert_eq(ids.size(), 100)
	assert_eq(_unique(ids).size(), 100, "no repeats")
	assert_eq(_count(ids, bank, "domain"), {"a": 20, "b": 20, "c": 25, "d": 10, "e": 15, "f": 10})
	assert_eq(MockExam.build(bank, DOMAINS, 100, _rng(7)), ids, "same seed, same exam")
	assert_ne(MockExam.build(bank, DOMAINS, 100, _rng(8)), ids)

func test_build_spreads_a_domain_across_its_subtopics():
	var bank: Array = []
	for i in 30:   # one subtopic with 27 questions, two with 2 and 1
		bank.append({"id": "c.%d" % i, "domain": "c", "subtopic": "big" if i < 27 else ("s1" if i < 29 else "s2"), "type": "mcq_single"})
	var ids := MockExam.build(bank, [{"id": "c", "weight": 100}], 6, _rng(1))
	var subs := _count(ids, bank, "subtopic")
	assert_eq(subs.get("s1", 0), 2, "small subtopics are used up before the big one repeats")
	assert_eq(subs.get("s2", 0), 1)
	assert_eq(subs.get("big", 0), 3)

func test_build_prefers_questions_not_on_the_last_exam():
	var bank := _bank(20)
	var first := MockExam.build(bank, DOMAINS, 30, _rng(3))
	var second := MockExam.build(bank, DOMAINS, 30, _rng(4), first)
	for id in second:
		assert_false(id in first, "%s repeated although fresh questions were left" % id)
	var third := MockExam.build(_bank(5), DOMAINS, 30, _rng(5), MockExam.build(_bank(5), DOMAINS, 30, _rng(6)))
	assert_eq(third.size(), 30, "repeats are allowed once fresh questions run out")

func test_build_caps_cli_tasks():
	var bank: Array = []
	for d in DOMAINS:
		for i in 60:   # every 4th is a CLI task; plenty of others to fill each domain
			bank.append({"id": "%s.%d" % [d.id, i], "domain": d.id, "subtopic": "s%d" % i, "type": "cli_task" if i % 4 == 0 else "mcq_single"})
	var ids := MockExam.build(bank, DOMAINS, 100, _rng(2))
	assert_eq(ids.size(), 100)
	assert_eq(int(_count(ids, bank, "type").get("cli_task", 0)), MockExam.max_cli(100))
	assert_eq(MockExam.max_cli(30), 1)

func test_short_domain_hands_seats_to_others():
	var bank := _bank(40).filter(func(q): return q.domain != "d" or int(q.id.split(".")[1]) < 4)
	var ids := MockExam.build(bank, DOMAINS, 100, _rng(9))
	assert_eq(ids.size(), 100, "still a full exam")
	assert_eq(_count(ids, bank, "domain").d, 4)
	assert_eq(MockExam.build(_bank(2), DOMAINS, 100, _rng(9)).size(), 12, "a tiny bank gives what it has")

func test_score_weights_domains_and_counts_unanswered_as_wrong():
	var qdb := {}
	for q in _bank(10):
		qdb[q.id] = q
	var ids := ["a.0", "a.1", "c.0", "c.1", "c.2", "c.3"]
	var results := [
		{"id": "a.0", "correct": true}, {"id": "a.1", "correct": true},
		{"id": "c.0", "correct": true}, {"id": "c.1", "correct": false, "response": 2, "skipped": false},
		{"id": "c.2", "correct": false, "response": -1, "skipped": true},
	]
	var rep := MockExam.score(ids, results, qdb, DOMAINS, 825)
	assert_eq(rep.correct, 3)
	assert_eq(rep.answered, 5)
	assert_eq(rep.by_domain.a, {"correct": 2, "total": 2})
	assert_eq(rep.by_domain.c, {"correct": 1, "total": 4})
	assert_eq(rep.by_domain.f, {"correct": 0, "total": 0})
	# a: 20 x 1.0, c: 25 x 0.25 -> 26.25 / 45
	assert_almost_eq(rep.fraction, 26.25 / 45.0, 0.0001)
	assert_eq(rep.scaled, 300 + int(round(700 * 26.25 / 45.0)))
	assert_false(rep.passed)
	assert_eq(rep.missed.map(func(m): return m.id), ["c.1", "c.2", "c.3"])
	assert_true(rep.missed[1].skipped)
	assert_false(rep.missed[2].answered, "c.3 never reached")

func test_scale_and_pass_mark():
	assert_eq(MockExam.scale(0.0), 300)
	assert_eq(MockExam.scale(1.0), 1000)
	assert_eq(MockExam.scale(0.75), 825, "75% is the pass mark")
	assert_eq(MockExam.scale(1.5), 1000)
	var qdb := {"a.0": {"id": "a.0", "domain": "a"}}
	assert_true(MockExam.score(["a.0"], [{"id": "a.0", "correct": true}], qdb, DOMAINS, 825).passed)

func test_clock():
	assert_eq(MockExam.clock(7200), "2:00:00")
	assert_eq(MockExam.clock(3599), "59:59")
	assert_eq(MockExam.clock(65), "1:05")
	assert_eq(MockExam.clock(-3), "0:00")

func test_shipped_bank_fills_a_full_and_quick_mock():
	for kind in ["full", "quick"]:
		var step := SessionManager.mock_step(kind, 11)
		var cfg := SessionManager.mock_config(kind)
		assert_eq(step.ids.size(), cfg.questions, kind)
		assert_eq(_unique(step.ids).size(), cfg.questions, kind)
		var per := {}
		for id in step.ids:
			var d: String = ContentDB.questions[id].domain
			per[d] = int(per.get(d, 0)) + 1
		assert_eq(per, MockExam.allocate(ContentDB.domains, cfg.questions), "%s follows blueprint weights" % kind)
	assert_eq(SessionManager.mock_config("full").minutes, 120)
	assert_eq(SessionManager.mock_config("full").questions, 100)

func test_record_mock_history_and_save_round_trip():
	var qdb := {"a.0": {"id": "a.0", "domain": "a"}, "a.1": {"id": "a.1", "domain": "a"}}
	var rep := MockExam.score(["a.0", "a.1"], [{"id": "a.0", "correct": true}], qdb, DOMAINS, 825)
	Progress.record_mock(rep, "Quick mock exam", 600, ["a.0", "a.1"], 1_800_000_000)
	assert_eq(Progress.best_mock_score(), 650)
	assert_true(Progress.save_game())
	Progress.reset()
	assert_eq(Progress.mock_history.size(), 0)
	Progress.load_game()
	assert_eq(Progress.mock_history.size(), 1)
	assert_eq(int(Progress.mock_history[0].scaled), 650)
	assert_eq(Progress.last_mock_ids, ["a.0", "a.1"])
	for i in Progress.MOCK_HISTORY_MAX + 5:
		Progress.record_mock(rep, "x", 1, [])
	assert_eq(Progress.mock_history.size(), Progress.MOCK_HISTORY_MAX, "history is capped")

func test_version_1_save_migrates():
	var d := Progress.to_dict()
	d.version = 1
	d.erase("mock_history")
	d.erase("last_mock_ids")
	Progress.from_dict(d)
	assert_eq(Progress.mock_history, [])
	assert_eq(Progress.best_mock_score(), -1)

func test_response_text():
	var mc := {"type": "mcq_single", "choices": ["x", "y"]}
	assert_eq(Grader.response_text(mc, 1), "y")
	assert_eq(Grader.response_text(mc, -1), "Skipped")
	assert_eq(Grader.response_text(mc, null), "Not answered")
	assert_eq(Grader.response_text({"type": "mcq_multi", "choices": ["x", "y", "z"]}, [0, 2]), "x, z")
	assert_eq(Grader.response_text({"type": "fill_in"}, " 110 "), "110")
	assert_eq(Grader.response_text({"type": "drag_order"}, ["A", "B"]), "A → B")
	assert_eq(Grader.response_text({"type": "drag_match"}, {"k": "v", "j": ""}), "k → v, j → ?")
	for id in ContentDB.questions:   # never crashes on a real question's own answer
		var q: Dictionary = ContentDB.questions[id]
		assert_false(Grader.response_text(q, q.answer if q.type != "cli_task" else {"passed": false}).is_empty(), id)

func test_exam_screen_runs_scores_and_records():
	SessionManager.steps = [{"kind": "exam", "ids": ["q.d1.subnet.005", "q.d3.route.002", "q.d4.qos.001"],
		"minutes": 2, "label": "Quick mock exam", "pass_scaled": 825}]
	SessionManager.index = 0
	SessionManager.results = []
	var scene: Control = load("res://ui/screens/MockExam.tscn").instantiate()
	add_child_autofree(scene)
	assert_false(scene._running, "waits on the intro")
	scene._begin()
	assert_true(scene._running)
	assert_almost_eq(scene.seconds_left(), 120, 1)
	var qv: QuestionView = scene._runner._current
	assert_false(qv.show_feedback, "no feedback during the exam")
	qv._get_response = func(): return "14"
	qv._on_submit()
	await wait_process_frames(2)
	scene._runner._current._on_submit(true)   # skip the second
	await wait_process_frames(2)
	scene._on_end()
	assert_false(scene._finished, "first press only asks to confirm")
	scene._on_end()
	assert_true(scene._finished)
	var r: Dictionary = SessionManager.results[0]
	assert_eq(r.exam.total, 3)
	assert_eq(r.exam.correct, 1)
	assert_eq(r.exam.answered, 2)
	assert_eq(Progress.mock_history.size(), 1)
	assert_true(SRS.has_card("q.d1.subnet.005"))
	assert_false(SRS.has_card("q.d4.qos.001"), "an unseen question isn't graded")

func test_exam_ends_when_time_runs_out():
	SessionManager.steps = [{"kind": "exam", "ids": ["q.d1.subnet.005", "q.d3.route.002"], "minutes": 1, "label": "Quick mock exam", "pass_scaled": 825}]
	SessionManager.index = 0
	SessionManager.results = []
	var scene: Control = load("res://ui/screens/MockExam.tscn").instantiate()
	add_child_autofree(scene)
	scene._begin()
	scene._deadline_ms = Time.get_ticks_msec() - 1
	scene._process(0.0)
	assert_true(scene._finished)
	assert_true(SessionManager.results[0].timed_out)
	assert_eq(SessionManager.results[0].exam.answered, 0)

func test_exam_report_renders_for_a_real_mock():
	var step := SessionManager.mock_step("quick", 3)
	var results: Array = []
	for i in step.ids.size():
		var q: Dictionary = ContentDB.questions[step.ids[i]]
		results.append({"id": q.id, "correct": i % 3 == 0, "response": q.answer if i % 3 == 0 else null, "skipped": i % 3 == 1})
	var rep := MockExam.score(step.ids, results.slice(0, 25), ContentDB.questions, ContentDB.domains, 825)
	var box := VBoxContainer.new()
	add_child_autofree(box)
	ExamReport.build(box, {"title": "Quick mock exam", "exam": rep, "seconds": 900, "timed_out": true})
	assert_eq(box.get_child_count(), 3, "score, areas, missed")
	assert_false(ExamReport.weakest_domain(rep).is_empty())

func _unique(a: Array) -> Array:
	var seen := {}
	for x in a:
		seen[x] = true
	return seen.keys()
