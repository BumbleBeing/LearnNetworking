extends Control
## Spaced-repetition review of due questions.

func _ready() -> void:
	var step := SessionManager.current_step()
	var v := UI.page(self)
	ScreenHeader.build(v, "Review", "Due for review", "Questions you studied before, scheduled so you see them just before you'd forget.")
	var body := UI.card(v)
	var runner := QuestionRunner.new()
	body.add_child(runner)
	runner.done.connect(_on_done)
	runner.start(step.get("ids", []))

func _on_done(results: Array) -> void:
	for r in results:
		SRS.grade(r.id, SessionManager.quality_for(r.correct, r.ms))
		var ref := str(ContentDB.questions.get(r.id, {}).get("lesson_ref", ""))
		if not ref.is_empty():
			Progress.record_attempt(ref, r.correct)
	SessionManager.step_done({"title": "Review", "items": results.size(),
		"correct": results.filter(func(r): return r.correct).size()})
