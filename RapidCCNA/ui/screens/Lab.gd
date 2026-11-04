extends Control
## CLI lab: topology, live-checked task list, one terminal per editable device.

var lab: Dictionary = {}
var ls: LabSession
var _look: Dictionary
var _rows: Array = []        # [dot, text, detail]
var _hint_label: Label
var _solution_box: VBoxContainer
var _status: Label
var _finish: Button
var _terms: Dictionary = {}
var _hints := 0
var _solution_shown := false

var _was_done := {}          # task index -> done at the last refresh
var _announce_progress := false

func _ready() -> void:
	_look = Palette.current()
	lab = ContentDB.labs.get(SessionManager.current_step().get("lab", ""), {})
	var v := UI.page(self)
	var d := ContentDB.get_domain(lab.get("domain", ""))
	ScreenHeader.build(v, "Lab  ·  " + d.get("name", ""), lab.get("title", "Missing lab"), lab.get("description", ""))
	if lab.is_empty():
		return
	ls = LabSession.create(lab)
	var main := UI.hbox(v, 16)
	var tasks := UI.card(main, "Tasks", 1.0)
	for t in lab.tasks:
		var row := UI.hbox(tasks, 10)
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var col := UI.vbox(row, 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var text := UI.label(col, t.text, "Body", true)
		var detail := UI.label(col, "", "Muted", true)
		_rows.append([dot, text, detail])
	var btns := UI.hbox(tasks, 10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.button(btns, "Hint", _show_hint).custom_minimum_size.x = 120
	UI.button(btns, "Show solution", _show_solution).custom_minimum_size.x = 160
	_hint_label = UI.label(tasks, "", "Muted", true)
	_solution_box = UI.vbox(tasks, 6)
	UI.label(tasks, "Tips: ? lists options, Tab completes, ↑/↓ recalls commands, 'do show ...' works in config mode.", "Muted", true)

	var console := UI.card(main, "", 2.0)
	var names := ls.sessions.keys()
	if names.size() > 1:
		var tabs := UI.hbox(console, 8)
		var group := ButtonGroup.new()
		for n in names:
			var b := UI.button(tabs, n, _show_term.bind(n))
			b.toggle_mode = true
			b.button_group = group
			b.custom_minimum_size.x = 90
			b.button_pressed = n == names[0]
	for n in names:
		var term := Terminal.new().setup(ls.sessions[n], "%s console. Type enable to begin; ? lists what you can type." % n)
		console.add_child(term)
		term.command_run.connect(func(_l, _o): _refresh())
		term.visible = n == names[0]
		_terms[n] = term

	# Status + Finish right under the tasks and console. Built in place rather than moved there:
	# a node moved in the frame it's created drops out of Godot 4.7's screen-reader tree.
	var foot := UI.hbox(v, 24)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	_status = UI.label(foot, "", "H2")
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_finish = UI.button(foot, "Finish lab", _on_finish)
	if lab.has("topology"):
		var topo := UI.card(v, "Topology")
		UI.diagram(topo, lab.topology)
	_refresh()

func _show_term(n: String) -> void:
	for k in _terms:
		_terms[k].visible = k == n
	UI.focus_later(_terms[n]._input)

func _refresh() -> void:
	var results := ls.results()
	var done := 0
	var newly_done := PackedStringArray()
	for i in results.size():
		var ok: bool = results[i].ok
		done += 1 if ok else 0
		var row: Array = _rows[i]
		row[0].add_theme_stylebox_override("panel", ThemeFactory.box(_look.good if ok else _look.track, Color.TRANSPARENT, 999, 0, 0, 0))
		row[1].add_theme_color_override("font_color", _look.muted if ok else _look.text)
		# Said in words, not only by colour (and screen readers read it after the task).
		row[2].text = "Done" if ok else ""
		if ok and not _was_done.get(i, false):
			newly_done.append("Task %d done." % (i + 1))
		_was_done[i] = ok
	_status.text = "%d of %d tasks done" % [done, results.size()]
	if done == results.size():
		_status.text = "All tasks complete" + ("" if not _solution_shown else " (solution shown)")
		_status.add_theme_color_override("font_color", _look.good)
		_finish.theme_type_variation = "PrimaryButton"
		UI.focus_later(_finish)
	if not newly_done.is_empty() and _announce_progress:
		UI.announce(" ".join(newly_done) + " " + _status.text + ".")
	_announce_progress = true   # not for tasks a lab starts with already done

func _show_hint() -> void:
	var results := ls.results()
	for i in results.size():
		if not results[i].ok:
			_hints += 1
			var why: String = results[i].msg
			_hint_label.text = "Task %d: %s%s" % [i + 1, lab.tasks[i].get("hint", ""), ("\nRight now: " + why) if not why.is_empty() else ""]
			UI.announce(_hint_label.text)
			return
	_hint_label.text = "Everything is done. Press Finish lab."
	UI.announce(_hint_label.text)

func _show_solution() -> void:
	_solution_shown = true
	for c in _solution_box.get_children():
		c.queue_free()
	for dev in lab.get("solution", {}):
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		_solution_box.add_child(ex)
		UI.label(ex, "%s:\n%s" % [dev, "\n".join(lab.solution[dev])], "Code", true)

func _on_finish() -> void:
	var results := ls.results()
	var total := results.size()
	var done := results.filter(func(r): return r.ok).size()
	SRS.grade(lab.id, SessionManager.lab_quality(done, total, _hints, _solution_shown))
	var clean := done == total and not _solution_shown
	if clean:
		Progress.mark_lab_done(lab.id)
	if lab.has("unit"):
		Progress.record_attempt(lab.unit, clean)
	SessionManager.step_done({"title": lab.title, "items": total, "correct": 0 if _solution_shown else done})
