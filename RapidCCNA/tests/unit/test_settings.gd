extends GutTest

var _orig: String

func before_each():
	_orig = Settings.exam_date

func after_each():
	Settings.exam_date = _orig

func test_days_until_exam_unset():
	Settings.exam_date = ""
	assert_eq(Settings.days_until_exam(), -1)

func test_days_until_exam_counts_days():
	Settings.exam_date = "2026-11-14"
	var today := Time.get_unix_time_from_datetime_string("2026-11-04T00:00:00")
	assert_eq(Settings.days_until_exam(today), 10)

func test_bad_date_returns_minus_one():
	Settings.exam_date = "soon"
	assert_eq(Settings.days_until_exam(), -1)
