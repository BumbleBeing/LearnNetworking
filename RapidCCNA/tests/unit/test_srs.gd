extends GutTest

const T0 := 1_700_000_000
const DAY := 86400

func before_each():
	SRS.reset()

func test_new_card_is_due_immediately():
	SRS.ensure_card("a", T0)
	assert_eq(SRS.due_cards(T0), ["a"])

func test_success_intervals_grow_1_3_then_ease():
	var c = SRS.grade("a", 5, T0)
	assert_eq(c.interval_days, 1.0)
	assert_eq(c.due, T0 + DAY)
	c = SRS.grade("a", 5, T0 + DAY)
	assert_eq(c.interval_days, 3.0)
	c = SRS.grade("a", 5, T0 + 4 * DAY)
	assert_gt(c.interval_days, 3.0 * 2.5 - 1)

func test_failure_resets_and_relearns_in_10_minutes():
	SRS.grade("a", 5, T0)
	var c = SRS.grade("a", 1, T0 + DAY)
	assert_eq(c.reps, 0)
	assert_eq(c.lapses, 1)
	assert_eq(c.due, T0 + DAY + 600)

func test_ease_never_below_minimum():
	for i in 20:
		SRS.grade("a", 0, T0 + i)
	assert_almost_eq(SRS.cards["a"].ease, SRS.MIN_EASE, 0.0001)

func test_due_cards_sorted_most_overdue_first():
	SRS.ensure_card("late", T0 + 100)
	SRS.ensure_card("early", T0)
	SRS.ensure_card("future", T0 + 10 * DAY)
	assert_eq(SRS.due_cards(T0 + 200), ["early", "late"])
