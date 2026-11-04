extends GutTest

func after_all():
	ContentDB.load_all(ContentDB.ROOT)

func test_shipped_content_loads_without_errors():
	ContentDB.load_all(ContentDB.ROOT)
	assert_eq(ContentDB.errors.size(), 0, str(ContentDB.errors))
	assert_eq(ContentDB.domains.size(), 6)

func test_domain_weights_sum_to_100():
	ContentDB.load_all(ContentDB.ROOT)
	var total := 0
	for d in ContentDB.domains:
		total += int(d.weight)
	assert_eq(total, 100)

func test_lookup_helpers():
	ContentDB.load_all(ContentDB.ROOT)
	assert_eq(ContentDB.get_domain("d3").name, "IP Connectivity")
	assert_gt(ContentDB.lessons_for_domain("d1").size(), 0)
	assert_gt(ContentDB.questions_for_domain("d1").size(), 0)

func test_bad_content_reports_duplicates_and_junk():
	ContentDB.load_all("res://tests/fixtures/bad_content")
	var joined := "\n".join(ContentDB.errors)
	assert_string_contains(joined, "duplicate id dup")
	assert_string_contains(joined, "invalid question")
	assert_eq(ContentDB.questions.size(), 1)

func test_session_manager_suggests_first_unmastered_unit():
	ContentDB.load_all(ContentDB.ROOT)
	var s = SessionManager.build_daily_session()
	assert_true(s.has("reviews"))
	assert_eq(s.next_unit.get("id"), "d1.subnetting_basics")
