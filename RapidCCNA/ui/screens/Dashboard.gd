extends Control
## Home screen: exam countdown, streak, today's session, per-domain readiness.

## Screenshot/preview hook: domain_id -> readiness override (0..1). Empty in normal play.
static var preview_readiness: Dictionary = {}

var _exam_input: LineEdit

func _ready() -> void:
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
		UI.label(left, "%s  ·  ~%d min tutorial, then drills and recall" % [d.get("name", ""), int(next.get("minutes", 5))], "Muted", true)
	var go := UI.button(left, "Start session", func(): pass, true)
	go.disabled = true
	go.tooltip_text = "Playable sessions arrive in milestone M1"
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
	UI.center_all(left)

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
