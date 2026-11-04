extends Control
## Home screen: exam countdown, streak, today's session, per-domain readiness.

var _exam_input: LineEdit

func _ready() -> void:
	Progress.mark_studied()
	Progress.save_game()
	var v := UI.page(self)
	UI.label(v, "Dashboard", 36)

	var days := Settings.days_until_exam()
	var countdown := "Exam date not set" if days < 0 else "%d days until exam" % days
	UI.label(v, "%s  ·  Streak: %d day(s)" % [countdown, Progress.streak_days], 20)

	var row := HBoxContainer.new()
	v.add_child(row)
	_exam_input = LineEdit.new()
	_exam_input.placeholder_text = "Exam date (YYYY-MM-DD)"
	_exam_input.text = Settings.exam_date
	_exam_input.custom_minimum_size.x = 260
	row.add_child(_exam_input)
	var save_btn := Button.new()
	save_btn.text = "Set date"
	save_btn.pressed.connect(_on_set_date)
	row.add_child(save_btn)

	var session := SessionManager.build_daily_session()
	UI.label(v, "Today's session", 26)
	UI.label(v, "Reviews due: %d" % session.reviews.size())
	var next: Dictionary = session.next_unit
	UI.label(v, "Next unit: %s" % (next.get("title", "All units mastered!")))
	UI.label(v, "(Tutorials and drills arrive in milestone M1.)", 14).modulate = Color(1, 1, 1, 0.6)

	UI.label(v, "Readiness by domain", 26)
	for d in ContentDB.domains:
		var line := HBoxContainer.new()
		v.add_child(line)
		var name_l := UI.label(line, "%s (%d%%)" % [d.name, d.weight])
		name_l.custom_minimum_size.x = 380
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = Progress.domain_readiness(d.id)
		bar.custom_minimum_size = Vector2(300, 24)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(bar)

	UI.button(v, "Back", func(): get_tree().change_scene_to_file("res://ui/screens/MainMenu.tscn"))

func _on_set_date() -> void:
	var t := _exam_input.text.strip_edges()
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if t.is_empty() or re.search(t):
		Settings.exam_date = t
		Settings.save_settings()
		get_tree().reload_current_scene()
	else:
		_exam_input.modulate = Color.RED
