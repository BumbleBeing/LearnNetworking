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

func test_daily_plan_stays_in_exam_area_order():
	# Nothing outside the first unmastered unit (d1) is planned, even though later areas have content.
	var steps := SessionManager.plan_steps(NOW)
	for s in steps:
		var unit: String = s.get("lesson", s.get("unit", ""))
		if s.kind == "lab":
			unit = ContentDB.labs[s.lab].get("unit", "")
		assert_true(unit.begins_with("d1."), "step outside d1: %s" % str(s))

func test_unit_steps_on_demand_include_finished_labs():
	var unit: Dictionary = ContentDB.lessons["d2.vlans_trunks"]
	Progress.mark_tutorial_done(unit.id)
	Progress.mark_lab_done("lab.vlans")
	assert_eq(SessionManager.unit_steps(unit, false), [], "daily plan leaves finished labs to SRS")
	var on_demand := SessionManager.unit_steps(unit, true)
	assert_eq(on_demand.size(), 1)
	assert_eq(on_demand[0].lab, "lab.vlans")

func test_unit_steps_for_drill_unit():
	var unit: Dictionary = ContentDB.lessons["d3.routing_table"]
	var kinds := _kinds(SessionManager.unit_steps(unit, true))
	assert_eq(kinds, ["tutorial", "drill:route_picker:g", "drill:route_picker:u"])

func test_quiz_ids_come_from_one_area():
	var ids := SessionManager.quiz_ids("d5")
	assert_gt(ids.size(), 3)
	for id in ids:
		assert_eq(ContentDB.questions[id].domain, "d5")
	assert_eq(SessionManager.quiz_ids("d6"), [])
