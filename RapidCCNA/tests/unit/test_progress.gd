extends GutTest

const TEST_SAVE := "user://test_save.json"
var _orig_path: String

func before_each():
	_orig_path = Progress.save_path
	Progress.save_path = TEST_SAVE
	Progress.reset()

func after_each():
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)
	Progress.save_path = _orig_path
	Progress.load_game()

func test_mastery_needs_full_window_at_85_percent():
	for i in 19:
		Progress.record_attempt("u", true)
	assert_false(Progress.is_mastered("u"), "19 attempts is not enough")
	Progress.record_attempt("u", true)
	assert_true(Progress.is_mastered("u"))

func test_mastery_window_is_rolling():
	for i in 20:
		Progress.record_attempt("u", false)
	for i in 17:
		Progress.record_attempt("u", true)
	assert_eq(Progress.attempts["u"].size(), 20)
	assert_almost_eq(Progress.accuracy("u"), 0.85, 0.001)
	assert_true(Progress.is_mastered("u"))

func test_streak_counts_consecutive_days_and_resets_on_gap():
	Progress.mark_studied("2026-11-01")
	Progress.mark_studied("2026-11-02")
	Progress.mark_studied("2026-11-02")
	assert_eq(Progress.streak_days, 2)
	Progress.mark_studied("2026-11-05")
	assert_eq(Progress.streak_days, 1)

func test_save_and_load_round_trip_includes_srs():
	Progress.record_attempt("u", true)
	Progress.mark_studied("2026-11-01")
	SRS.grade("q1", 4, 1_700_000_000)
	assert_true(Progress.save_game())
	Progress.reset()
	assert_eq(SRS.cards.size(), 0)
	Progress.load_game()
	assert_eq(Progress.attempts["u"], [true])
	assert_eq(Progress.last_study_day, "2026-11-01")
	assert_true(SRS.has_card("q1"))
	assert_eq(int(SRS.cards["q1"].reps), 1)

func test_load_with_no_save_gives_fresh_profile():
	Progress.load_game()
	assert_eq(Progress.streak_days, 0)
	assert_eq(Progress.attempts.size(), 0)

func test_completed_round_trips_through_save():
	Progress.mark_unit_completed("u")
	assert_true(Progress.save_game())
	Progress.reset()
	assert_false(Progress.is_completed("u"))
	Progress.load_game()
	assert_true(Progress.is_completed("u"))

func test_v2_saves_infer_completed_units():
	var mastered: Array = []
	for i in 20:
		mastered.append(true)
	Progress.from_dict({"version": 2,
		"attempts": {"mastered": mastered, "round_done": [true, false, true, true, true, true, true, true, true, true],
			"started": [true, true, true], "no_tutorial": [true, true, true, true, true, true, true, true, true, true]},
		"tutorials_done": {"round_done": 1, "started": 1}})
	assert_true(Progress.is_completed("mastered"))
	assert_true(Progress.is_completed("round_done"), "tutorial done and 10 attempts")
	assert_false(Progress.is_completed("started"), "too few attempts")
	assert_false(Progress.is_completed("no_tutorial"), "tutorial never done")
