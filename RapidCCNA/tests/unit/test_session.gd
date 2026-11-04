extends GutTest

const NOW := 1_800_000_000
var _orig_path: String

func before_each():
	ContentDB.load_all(ContentDB.ROOT)
	_orig_path = Progress.save_path
	Progress.save_path = "user://test_session_save.json"
	Progress.reset()

func after_each():
	Progress.save_path = _orig_path
	Progress.load_game()

func _kinds(steps: Array) -> Array:
	return steps.map(func(s): return s.kind + (":" + s.drill + (":g" if s.guided else ":u") if s.kind == "drill" else ""))

func test_fresh_profile_gets_tutorial_then_guided_and_unguided_drill():
	var steps := SessionManager.plan_steps(NOW)
	assert_eq(_kinds(steps), ["tutorial", "drill:bit_flipper:g", "drill:bit_flipper:u"])
	assert_eq(steps[0].lesson, "d1.binary_basics")

func test_due_questions_and_generated_cards_come_first():
	SRS.ensure_card("q.d1.subnet.001", NOW - 10)
	SRS.ensure_card("gen.subnet_sprint.broadcast", NOW - 5)
	SRS.ensure_card("gen.subnet_sprint.network", NOW - 5)
	SRS.ensure_card("q.d1.binary.001", NOW + 86400)   # not due
	var steps := SessionManager.plan_steps(NOW)
	assert_eq(steps[0].kind, "review")
	assert_eq(steps[0].ids, ["q.d1.subnet.001"])
	assert_eq(_kinds(steps).slice(1, 2), ["drill:subnet_sprint:u"])
	assert_eq(steps[1].count, SessionManager.REVIEW_DRILL_COUNT)

func test_tutorial_skipped_once_done_and_guided_dropped_after_practice():
	Progress.mark_tutorial_done("d1.binary_basics")
	for i in SessionManager.GUIDED_UNTIL:
		Progress.record_attempt("d1.binary_basics", i % 2 == 0)
	assert_eq(_kinds(SessionManager.plan_steps(NOW)), ["drill:bit_flipper:u"])

func test_mastered_unit_moves_on():
	for i in 20:
		Progress.record_attempt("d1.binary_basics", true)
	var steps := SessionManager.plan_steps(NOW)
	assert_eq(steps[0].lesson, "d1.subnetting_basics")

func test_grade_round_grades_each_card_once():
	SessionManager.grade_round([
		{"card_id": "gen.x.a", "correct": true, "ms": 1},
		{"card_id": "gen.x.a", "correct": true, "ms": 1},
		{"card_id": "gen.x.b", "correct": false, "ms": 1},
	])
	assert_eq(int(SRS.cards["gen.x.a"].reps), 1)
	assert_eq(int(SRS.cards["gen.x.b"].lapses), 1)

func test_quality_for():
	assert_eq(SessionManager.quality_for(true, 1000), 5)
	assert_eq(SessionManager.quality_for(true, 60000), 4)
	assert_eq(SessionManager.quality_for(false, 1000), 1)
