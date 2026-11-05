class_name ExamReport
extends RefCounted
## Mock exam results: scaled score, pass/fail, per-domain breakdown and a
## review of every missed question with its explanation.

## `r` is a session result for an exam step: {title, exam: MockExam.score report, seconds, timed_out}.
static func build(parent: Node, r: Dictionary) -> void:
	var look := Palette.current()
	var rep: Dictionary = r.exam
	var passed: bool = rep.passed
	var top := UI.card(parent, str(r.get("title", "Mock exam")))
	var row := UI.hbox(top, 24)
	var score := UI.vbox(row, 0)
	var big := UI.label(score, str(rep.scaled), "Big")
	big.add_theme_color_override("font_color", look.good if passed else look.accent2)
	UI.label(score, "of 1000", "Muted")
	var info := UI.vbox(row, 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var verdict := UI.label(info, "Pass" if passed else "Not yet: %d to go" % (int(rep.pass_scaled) - int(rep.scaled)), "H2")
	verdict.add_theme_color_override("font_color", look.good if passed else look.accent2)
	UI.label(info, "Pass mark %d  ·  %d of %d correct  ·  %d answered  ·  %s used%s" % [int(rep.pass_scaled), int(rep.correct),
		int(rep.total), int(rep.answered), MockExam.clock(int(r.get("seconds", 0))), "  ·  time ran out" if r.get("timed_out", false) else ""], "Muted", true)
	var weak := weakest_domain(rep)
	if not weak.is_empty():
		UI.label(info, "Focus next: %s. Use its quiz and units in Topics." % weak.name, "Body", true)

	var dom_card := UI.card(parent, "By exam area")
	for i in ContentDB.domains.size():
		var d: Dictionary = ContentDB.domains[i]
		var s: Dictionary = rep.by_domain.get(d.id, {"correct": 0, "total": 0})
		var color: Color = look.domains[i % look.domains.size()]
		var line := UI.hbox(dom_card, 10)
		UI.label(line, d.name).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pct: float = float(s.correct) / s.total if int(s.total) > 0 else 0.0
		UI.label(line, "%d / %d  ·  %d%%  ·  w%d" % [int(s.correct), int(s.total), int(round(pct * 100)), int(d.weight)], "Muted")
		UI.bar(dom_card, pct, color, 8, "%s score" % d.name)

	var missed: Array = rep.missed
	var miss_card := UI.card(parent, "Missed questions (%d)" % missed.size())
	if missed.is_empty():
		UI.label(miss_card, "None. Every question was right.", "Muted")
	for m in missed:
		if not ContentDB.questions.has(m.id):
			continue
		var q: Dictionary = ContentDB.question_version(m.id, int(m.get("variant", 0)))   # the version that was shown
		var item := UI.vbox(miss_card, 4)
		var d := ContentDB.get_domain(q.get("domain", ""))
		UI.label(item, ("%s  ·  %s" % [d.get("name", ""), q.get("subtopic", "")]).to_upper(), "H3")
		UI.label(item, str(q.stem), "Body", true)
		if q.has("exhibit"):
			var ex := PanelContainer.new()
			ex.theme_type_variation = "Exhibit"
			item.add_child(ex)
			UI.label(ex, str(q.exhibit), "Code", true)
		var yours := "Not answered (time ran out)" if not m.answered else "Skipped" if m.get("skipped", false) else Grader.response_text(q, m.response)
		UI.label(item, "Your answer: " + yours, "Muted", true).add_theme_color_override("font_color", look.accent2)
		UI.label(item, "Correct answer: " + Grader.answer_text(q), "Body", true).add_theme_color_override("font_color", look.good)
		UI.label(item, str(q.get("explanation", "")), "Body", true)
		var ref := str(q.get("lesson_ref", ""))
		if ContentDB.lessons.has(ref):
			UI.label(item, "From the lesson: " + ContentDB.lessons[ref].title, "Muted")
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		item.add_child(gap)

## The domain with the largest weighted shortfall (weight x fraction missed), or {}.
static func weakest_domain(rep: Dictionary) -> Dictionary:
	var worst := {}
	var worst_loss := 0.0
	for d in ContentDB.domains:
		var s: Dictionary = rep.by_domain.get(d.id, {})
		if int(s.get("total", 0)) == 0:
			continue
		var loss: float = float(d.weight) * (1.0 - float(s.correct) / s.total)
		if loss > worst_loss:
			worst_loss = loss
			worst = d
	return worst
