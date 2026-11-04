extends Control

func _ready() -> void:
	var look := Palette.current()
	var col := UI.page(self, true)
	col.custom_minimum_size.x = 560

	var logo := UI.hbox(col, 0)
	UI.label(logo, "Rapid", "Display")
	var ccna := UI.label(logo, "CCNA", "Display")
	ccna.add_theme_color_override("font_color", look.accent)
	UI.label(col, "Pass the CCNA 200-301, one concept at a time.", "Muted")

	var chips := UI.hbox(col, 8)
	for t in ["6 exam domains", "Spaced repetition", "Timed mock exams"]:
		UI.chip(chips, t)

	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)
	var start := UI.button(col, "Start studying", _go_dashboard, true)
	start.custom_minimum_size.x = 320
	var row := UI.hbox(col, 10)
	UI.label(row, "Look", "Muted").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.look_picker(row)
	UI.button(row, "Quit", func(): get_tree().quit()).custom_minimum_size.x = 0

	if ContentDB.errors.size() > 0:
		UI.label(col, "Content warnings: %d (see log)" % ContentDB.errors.size(), "Muted").add_theme_color_override("font_color", look.warn)
	start.grab_focus()

func _go_dashboard() -> void:
	get_tree().change_scene_to_file("res://ui/screens/Dashboard.tscn")
