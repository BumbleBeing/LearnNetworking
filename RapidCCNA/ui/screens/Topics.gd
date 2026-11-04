extends Control
## Free training: every exam area, unit, drill and lab, startable on demand.

func _ready() -> void:
	SessionManager.origin = "topics"
	var look := Palette.current()
	var v := UI.page(self)
	var head := UI.hbox(v, 16)
	var titles := UI.vbox(head, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles, "Topics", "H1")
	UI.label(titles, "Train on any subject. Your daily session still follows the exam areas in order.", "Muted", true)
	var back := UI.button(head, "Dashboard", func(): get_tree().change_scene_to_file(SessionManager.SCENES.dashboard))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	for i in ContentDB.domains.size():
		var d: Dictionary = ContentDB.domains[i]
		var color: Color = look.domains[i % look.domains.size()]
		var card := UI.card(v)
		var dh := UI.hbox(card, 12)
		var dot := ColorRect.new()
		dot.color = color
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dh.add_child(dot)
		var dt := UI.vbox(dh, 0)
		dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(dt, d.name, "H2")
		UI.label(dt, "%d%% of the exam  ·  readiness %d%%" % [int(d.weight), int(round(Progress.domain_readiness(d.id) * 100))], "Muted")
		var nq := ContentDB.questions_for_domain(d.id).size()
		var quiz := UI.button(dh, "Quiz (%d)" % min(nq, SessionManager.MAX_REVIEWS), SessionManager.start_quiz.bind(d.id))
		quiz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		quiz.disabled = nq == 0
		UI.bar(card, Progress.domain_readiness(d.id), color, 6)

		var units := ContentDB.lessons_for_domain(d.id)
		if units.is_empty():
			UI.label(card, "Units for this exam area arrive in a later milestone.", "Muted")
		for u in units:
			_unit_row(card, u)

func _unit_row(parent: Node, u: Dictionary) -> void:
	var row := UI.hbox(parent, 12)
	var info := UI.vbox(row, 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(info, u.title, "Body")
	var bits := PackedStringArray()
	bits.append("Tutorial done" if Progress.is_tutorial_done(u.id) else "Not started")
	var n := Progress.attempt_count(u.id)
	if n > 0:
		bits.append("%d%% over last %d" % [int(round(Progress.accuracy(u.id) * 100)), n])
	if Progress.is_mastered(u.id):
		bits.append("Mastered")
	UI.label(info, "  ·  ".join(bits), "Muted")
	var extras := UI.hbox(info, 8)
	for did in u.get("drills", []):
		var dd: Dictionary = ContentDB.drills.get(did, {})
		if dd.is_empty():
			continue
		UI.label(extras, dd.title, "Muted").size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for mode in [["Guided", true], ["Unguided", false]]:
			var b := UI.button(extras, mode[0], SessionManager.start_drill.bind(did, mode[1]))
			b.custom_minimum_size.x = 104
	for lid in u.get("labs", []):
		var lab: Dictionary = ContentDB.labs.get(lid, {})
		if lab.is_empty():
			continue
		var lb := UI.button(extras, "Lab" + (" ✓" if Progress.is_lab_done(lid) else ""), SessionManager.start_lab.bind(lid))
		lb.custom_minimum_size.x = 90
		lb.tooltip_text = lab.title
	for btn in [["Study unit", SessionManager.start_unit.bind(u.id), true], ["Tutorial", SessionManager.start_tutorial.bind(u.id), false]]:
		var b2 := UI.button(row, btn[0], btn[1], btn[2])
		b2.custom_minimum_size.x = 130
		b2.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
