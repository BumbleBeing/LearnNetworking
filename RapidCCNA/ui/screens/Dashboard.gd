extends Control
## Home screen: exam countdown, streak, today's session, per-domain readiness.

## Screenshot/preview hook: domain_id -> readiness override (0..1). Empty in normal play.
static var preview_readiness: Dictionary = {}

var _exam_input: LineEdit

func _ready() -> void:
	SessionManager.origin = "dashboard"
	Progress.mark_studied()
	Progress.save_game()
	var look := Palette.current()
	var v := UI.page(self)

	# Header
	var head := UI.hbox(v, 16)
	var titles := UI.vbox(head, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles, "Dashboard", "H1")
	UI.label(titles, "CCNA 200-301 bootcamp  ·  12-week plan", "Muted")
	UI.look_picker(head).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var settings := UI.button(head, "Settings", func():
		SettingsScreen.return_to = "res://ui/screens/Dashboard.tscn"
		get_tree().change_scene_to_file("res://ui/screens/SettingsScreen.tscn"))
	settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings.custom_minimum_size.x = 0
	UI.button(head, "Main menu", func(): get_tree().change_scene_to_file("res://ui/screens/MainMenu.tscn")).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Stat tiles
	var session := SessionManager.build_daily_session()
	var days := Settings.days_until_exam()
	var stats := UI.hbox(v, 16)
	UI.stat(stats, "--" if days < 0 else str(days), "days until exam", look.accent)
	UI.stat(stats, str(Progress.streak_days), "day streak", look.warn)
	UI.stat(stats, str(session.reviews.size()), "reviews due", look.accent2)
	UI.stat(stats, "%d%%" % int(round(_overall_readiness() * 100)), "weighted readiness", look.good)

	# Session + readiness
	var main := UI.hbox(v, 16)
	var left := UI.card(main, "Today's session", 1.0)
	var next: Dictionary = session.next_unit
	UI.label(left, next.get("title", "All units mastered!"), "H2", true)
	if not next.is_empty():
		var d := ContentDB.get_domain(next.domain)
		UI.label(left, d.get("name", ""), "Muted", true)
	var plan: Array = session.steps
	var plan_box := UI.vbox(left, 2)
	for st in plan:
		UI.label(plan_box, "•  " + SessionManager.describe(st), "Body", true)
	var go := UI.button(left, "Start session", SessionManager.start_daily, true)
	if plan.is_empty():
		go.disabled = true
		UI.label(plan_box, "Nothing due. Browse topics below to train on anything.", "Muted", true)
	UI.focus_later(go)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	left.add_child(spacer)
	UI.label(left, "EXAM DATE", "H3")
	var row := UI.hbox(left, 8)
	_exam_input = LineEdit.new()
	_exam_input.placeholder_text = "YYYY-MM-DD"
	_exam_input.text = Settings.exam_date
	_exam_input.custom_minimum_size.x = 180
	row.add_child(_exam_input)
	var set_btn := UI.button(row, "Set", _on_set_date)
	set_btn.custom_minimum_size.x = 0

	var right := UI.card(main, "Readiness by domain", 1.3)
	for i in ContentDB.domains.size():
		var d: Dictionary = ContentDB.domains[i]
		var color: Color = look.domains[i % look.domains.size()]
		var line := UI.hbox(right, 10)
		var dot := ColorRect.new()
		dot.color = color
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dot)
		var name_l := UI.label(line, d.name)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var r := _readiness(d.id)
		UI.label(line, "%d%%  ·  w%d" % [int(round(r * 100)), int(d.weight)], "Muted")
		UI.bar(right, r, color, 8)

	# Mock exams
	var mock := UI.card(v, "Mock exam")
	var mrow := UI.hbox(mock, 12)
	var minfo := UI.vbox(mrow, 2)
	minfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var full := SessionManager.mock_config("full")
	UI.label(minfo, "A timed exam weighted like the real CCNA, with no feedback until the end. Scored out of 1000; %d passes." % full.pass_scaled, "Body", true)
	UI.label(minfo, mock_history_line(), "Muted", true)
	var quick := SessionManager.mock_config("quick")
	var mbtns := UI.vbox(mrow, 8)
	mbtns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.button(mbtns, "Full exam  ·  %dq / %d min" % [full.questions, full.minutes], SessionManager.start_mock.bind("full")).custom_minimum_size.x = 260
	UI.button(mbtns, "Quick exam  ·  %dq / %d min" % [quick.questions, quick.minutes], SessionManager.start_mock.bind("quick")).custom_minimum_size.x = 260

	# Free training: the daily plan follows exam-area order; anything can be studied on demand.
	var train := UI.card(v, "Train any topic")
	var trow := UI.hbox(train, 12)
	var tinfo := UI.vbox(trow, 2)
	tinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(tinfo, "Today's session follows the exam areas in order. To jump ahead or revisit something, pick any unit, drill, lab or exam-area quiz.", "Body", true)
	UI.label(tinfo, "%d units  ·  %d drills  ·  %d labs  ·  %d questions" % [ContentDB.lessons.size(), ContentDB.drills.size(),
		ContentDB.labs.values().filter(func(l): return not l.get("hidden", false)).size(), ContentDB.questions.size()], "Muted")
	var browse := UI.button(trow, "Browse topics", func(): get_tree().change_scene_to_file(SessionManager.SCENES.topics))
	browse.size_flags_vertical = Control.SIZE_SHRINK_CENTER

## "Last: 812 (not yet), 2026-11-03  ·  best 870  ·  3 taken", or a first-time hint.
static func mock_history_line() -> String:
	var h: Array = Progress.mock_history
	if h.is_empty():
		return "No mock exams yet. A quick exam is a good first check."
	var last: Dictionary = h[-1]
	var date := Time.get_date_string_from_unix_time(int(last.when))
	return "Last: %d (%s), %s  ·  best %d  ·  %d taken" % [int(last.scaled), "pass" if last.passed else "not yet", date,
		Progress.best_mock_score(), h.size()]

func _readiness(domain_id: String) -> float:
	if preview_readiness.has(domain_id):
		return preview_readiness[domain_id]
	return Progress.domain_readiness(domain_id)

func _overall_readiness() -> float:
	var total := 0.0
	for d in ContentDB.domains:
		total += _readiness(d.id) * float(d.weight) / 100.0
	return total

func _on_set_date() -> void:
	var t := _exam_input.text.strip_edges()
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if t.is_empty() or re.search(t):
		Settings.exam_date = t
		Settings.save_settings()
		get_tree().reload_current_scene()
	else:
		_exam_input.add_theme_color_override("font_color", Color.RED)
