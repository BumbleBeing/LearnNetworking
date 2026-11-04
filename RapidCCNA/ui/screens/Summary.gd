extends Control
## End-of-session results.

func _ready() -> void:
	var look := Palette.current()
	var v := UI.page(self)
	var is_exam := SessionManager.results.any(func(r): return r.has("exam"))
	var dest: String = SessionManager.origin
	var top := UI.hbox(v, 16)
	var head := UI.vbox(top, 2)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(head, "Exam complete" if is_exam else "Session complete", "H1")
	UI.label(head, SessionManager.title, "Muted")
	if is_exam:   # the report is long; offer a way out at the top too
		var top_back := UI.button(top, "Back to " + dest, _back)
		top_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top_back.set_meta("a11y_same_as_another", true)   # same action as the button at the bottom
	var items := 0
	var correct := 0
	for r in SessionManager.results:
		items += int(r.get("items", 0))
		correct += int(r.get("correct", 0))
	var stats := UI.hbox(v, 16)
	UI.stat(stats, str(items), "items answered", look.accent)
	UI.stat(stats, "%d%%" % (int(round(100.0 * correct / items)) if items > 0 else 0), "accuracy", look.good)
	UI.stat(stats, str(Progress.streak_days), "day streak", look.warn)
	UI.stat(stats, str(SRS.due_cards(int(Time.get_unix_time_from_system()) + 86400).size()), "due by tomorrow", look.accent2)
	for r in SessionManager.results:
		if r.has("exam"):
			ExamReport.build(v, r)
	var list := UI.card(v, "What you did")
	for r in SessionManager.results:
		var row := UI.hbox(list, 12)
		var title := str(r.get("title", r.kind))
		if r.kind == "drill":
			title += "  (guided)" if r.get("guided", false) else "  (unguided)"
		UI.label(row, title, "Body").size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var detail := "%d / %d" % [int(r.get("correct", 0)), int(r.get("items", 0))]
		if r.has("avg_ms") and int(r.items) > 0:
			detail += "   ·   %.1fs avg" % (r.avg_ms / 1000.0)
		UI.label(row, detail, "Muted")
	if SessionManager.results.is_empty():
		UI.label(list, "Nothing completed.", "Muted")
	var back := UI.button(v, "Back to " + dest, _back, true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.focus_later(back)

func _back() -> void:
	get_tree().change_scene_to_file(SessionManager.SCENES[SessionManager.origin])
