extends Node
## Opens one screen in a realistic state so tools/a11y_tree.sh can dump what a screen reader
## sees there. Run: godot --path . res://tools/a11y_tour.tscn -- <screen> [answer]
## <screen>: main, dashboard, topics, settings, tutorial, lab, exam, a drill id
## (e.g. bit_flipper) or a question id (e.g. q.d3.route.003). "answer" skips the question
## so its feedback shows.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var screen: String = args[0] if args.size() > 0 else "main"
	# Stay alive across scene changes: a placeholder becomes the scene that change_scene frees.
	var placeholder := Node.new()
	get_tree().root.add_child.call_deferred(placeholder)
	await get_tree().process_frame
	get_tree().current_scene = placeholder
	match screen:
		"main", "dashboard", "topics", "settings":
			var file: String = {"main": "MainMenu", "dashboard": "Dashboard", "topics": "Topics", "settings": "SettingsScreen"}[screen]
			get_tree().change_scene_to_file("res://ui/screens/%s.tscn" % file)
		"tutorial":
			SessionManager.start_tutorial(ContentDB.lessons.keys()[0])
		"lab":
			SessionManager.start_lab("lab.vlans")
		"exam":
			SessionManager.start_mock("quick")
		_:
			if ContentDB.drills.has(screen):
				SessionManager.start_drill(screen, true)
			else:
				SessionManager.start([{"kind": "review", "ids": [screen], "title": "Quiz"}], "Quiz")
	if args.size() > 1 and args[1] == "answer":
		await get_tree().create_timer(1.5).timeout
		var qv := get_tree().current_scene.find_children("*", "QuestionView", true, false)
		if not qv.is_empty():
			qv[0]._on_submit(true)
