extends SceneTree
## End-to-end smoke test: plays a full daily session through real scene changes.
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
	_check(sm.results.size() == 3, "3 steps completed (got %d)" % sm.results.size())
	_check(progress.is_tutorial_done("d1.binary_basics"), "tutorial marked done")
	_check(progress.attempt_count("d1.binary_basics") == 10, "10 unguided attempts recorded")
	_check(root.get_node("SRS").has_card("gen.bit_flipper.dec_to_bin") or root.get_node("SRS").cards.size() > 3, "SRS cards created")
	_check(FileAccess.file_exists("user://smoke_save.json"), "progress saved")
	DirAccess.remove_absolute("user://smoke_save.json")
	print("SMOKE %s" % ("OK" if fails == 0 else "FAILED (%d)" % fails))
	quit(1 if fails > 0 else 0)

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
