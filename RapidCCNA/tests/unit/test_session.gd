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

## Masters every unit that comes before `unit_id` in the daily order.
func _master_before(unit_id: String) -> void:
	for d in ContentDB.domains:
		for l in ContentDB.lessons_for_domain(d.id):
			if l.id == unit_id:
				return
			for i in Progress.MASTERY_WINDOW:
				Progress.record_attempt(l.id, true)

func test_fresh_profile_starts_with_first_unit_and_a_unit_quiz():
	var steps := SessionManager.plan_steps(NOW)
	assert_eq(steps[0].lesson, "d1.components", "blueprint order: 1.1 first")
	assert_eq(_kinds(steps), ["tutorial", "review"], "a unit without drills ends with a unit quiz")
	assert_eq(steps[1].title, "Unit quiz")
	for id in steps[1].ids:
		assert_eq(ContentDB.questions[id].lesson_ref, "d1.components")
		assert_false(id in ContentDB.lessons["d1.components"].recall, "recall questions were just asked in the tutorial")

func test_unit_quiz_after_tutorial_uses_all_unit_questions_and_skips_due_ones():
	Progress.mark_tutorial_done("d1.components")
	SRS.ensure_card("q.d1.comp.001", NOW - 10)
	var steps := SessionManager.plan_steps(NOW)
	assert_eq(_kinds(steps), ["review", "review"])
	assert_eq(steps[0].ids, ["q.d1.comp.001"])
	var n := ContentDB.questions.values().filter(func(q): return q.get("lesson_ref") == "d1.components").size()
	assert_eq(steps[1].ids.size(), min(n - 1, SessionManager.UNIT_QUIZ_MAX))
	assert_false("q.d1.comp.001" in steps[1].ids, "already in today's review")
	assert_string_contains(SessionManager.describe(steps[1]), "Unit quiz: Network components")

func test_lab_only_units_get_a_unit_quiz_too():
	var steps := SessionManager.unit_steps(ContentDB.lessons["d2.vlans_trunks"], true)
	assert_eq(steps.map(func(s): return s.kind), ["tutorial", "lab", "review"])

func test_binary_unit_gets_tutorial_then_guided_and_unguided_drill():
	_master_before("d1.binary_basics")
	var steps := SessionManager.plan_steps(NOW)
	assert_eq(_kinds(steps), ["tutorial", "drill:bit_flipper:g", "drill:bit_flipper:u"], "units with drills get no unit quiz")
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
	_master_before("d1.binary_basics")
	Progress.mark_tutorial_done("d1.binary_basics")
	for i in SessionManager.GUIDED_UNTIL:
		Progress.record_attempt("d1.binary_basics", i % 2 == 0)
	assert_eq(_kinds(SessionManager.plan_steps(NOW)), ["drill:bit_flipper:u"])

func test_mastered_unit_moves_on():
	_master_before("d1.binary_basics")
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
	var daily := SessionManager.unit_steps(unit, false)
	assert_eq(daily.map(func(st): return st.kind), ["review"], "daily plan leaves finished labs to SRS; the unit quiz remains")
	var on_demand := SessionManager.unit_steps(unit, true)
	assert_eq(on_demand.map(func(st): return st.kind), ["lab", "review"])
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
