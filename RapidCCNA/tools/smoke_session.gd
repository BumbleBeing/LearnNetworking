extends SceneTree
## End-to-end smoke test: plays a full daily session, then a quick mock exam,
## through real scene changes.
## Usage: godot --headless --path . -s res://tools/smoke_session.gd
## Exit code 0 on success. Uses a throwaway save file. Avoids class_name
## references because -s scripts compile before autoloads are registered.

var fails := 0

func _initialize() -> void:
	var progress = root.get_node("Progress")
	var sm = root.get_node("SessionManager")
	progress.save_path = "user://smoke_save.json"
	progress.reset()
	await process_frame   # autoload _ready() runs after _initialize starts
	progress.reset()
	var unit: Dictionary = sm.next_unit()
	var planned: Array = sm.plan_steps()
	var quiz: Array = planned.filter(func(st): return st.kind == "review" and st.get("title", "") == "Unit quiz")
	var drills: Array = planned.filter(func(st): return st.kind == "drill" and not st.guided)
	var expect_attempts: int = quiz[0].ids.size() if quiz.size() > 0 else drills.size() * 10
	sm.start_daily()
	var guard := 0
	while guard < 400:
		guard += 1
		await process_frame
		var scene = current_scene
		if scene == null:
			continue
		var name: String = scene.name
		if name == "Summary":
			break
		if name == "Tutorial":
			if not scene._recalling:
				scene._go(1)
			else:
				_answer_question(scene)
		elif name == "Review":
			_answer_question(scene)
		elif name == "DrillHost":
			var d = _find(scene, func(n): return n.has_method("next_item") and n.has_method("correct_answer"))
			if d and not d._answered:
				d.autoplay(true)
			elif d:
				d.next_item()
	_check(current_scene != null and current_scene.name == "Summary", "reached summary")
	_check(sm.results.size() == planned.size(), "%d steps completed (got %d)" % [planned.size(), sm.results.size()])
	_check(progress.is_tutorial_done(unit.id), "tutorial of %s marked done" % unit.id)
	_check(progress.attempt_count(unit.id) == expect_attempts, "%d mastery attempts recorded (got %d)" % [expect_attempts, progress.attempt_count(unit.id)])
	_check(root.get_node("SRS").cards.size() > 3, "SRS cards created")
	_check(FileAccess.file_exists("user://smoke_save.json"), "progress saved")
	await _play_quick_mock(progress, sm)
	DirAccess.remove_absolute("user://smoke_save.json")
	print("SMOKE %s" % ("OK" if fails == 0 else "FAILED (%d)" % fails))
	quit(1 if fails > 0 else 0)

func _play_quick_mock(progress, sm) -> void:
	sm.start_mock("quick")
	var n: int = sm.steps[0].ids.size()
	var seen_exam := false
	var guard := 0
	while guard < 600:
		guard += 1
		await process_frame
		var scene = current_scene
		if scene == null:
			continue
		if scene.name == "MockExam":
			seen_exam = true
			if not scene._running and not scene._finished:
				scene._begin()
			else:
				_answer_question(scene)
		elif scene.name == "Summary" and seen_exam:
			break
	_check(seen_exam and current_scene.name == "Summary", "mock exam reached summary")
	_check(n == sm.mock_config("quick").questions, "quick mock has %d questions (got %d)" % [sm.mock_config("quick").questions, n])
	var exam: Dictionary = sm.results[0].get("exam", {}) if sm.results.size() > 0 else {}
	_check(int(exam.get("answered", -1)) == n, "every mock question answered (got %s)" % exam.get("answered", "none"))
	_check(int(exam.get("scaled", 0)) == 300, "all skipped scores 300 (got %s)" % exam.get("scaled", "none"))
	_check(progress.mock_history.size() == 1, "mock recorded in history")

func _answer_question(scene: Node) -> void:
	var qv = _find(scene, func(n): return n.has_method("_on_submit") and n.has_method("_continue"))
	if qv == null:
		return
	if qv._done:
		qv._continue()
	else:
		qv._on_submit(true)   # "I don't know"

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _find(n: Node, pred: Callable) -> Node:
	for c in n.get_children():
		if pred.call(c):
			return c
		var r = _find(c, pred)
		if r:
			return r
	return null
