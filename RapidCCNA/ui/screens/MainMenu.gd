extends Control

func _ready() -> void:
	var look := Palette.current()
	var col := UI.page(self, true)
	col.custom_minimum_size.x = 560

	var logo := UI.hbox(col, 0)
	var rapid := UI.label(logo, "Rapid", "Display")
	var ccna := UI.label(logo, "CCNA", "Display")
	# Screen readers already hear "RapidCCNA" as the window title; the two-colour logo would read as two words.
	UI.hide_from_screen_readers(rapid)
	UI.hide_from_screen_readers(ccna)
	ccna.add_theme_color_override("font_color", look.accent)
	UI.label(col, "Pass the CCNA 200-301, one concept at a time.", "Muted")

	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)
	var start := UI.button(col, "Start studying", _go_dashboard, true)
	start.custom_minimum_size.x = 320
	var row := UI.hbox(col, 10)
	UI.button(row, "Settings", _go_settings).custom_minimum_size.x = 0   # the look is chosen in Settings
	if OS.get_name() != "Web":   # browsers can't close the tab from the page
		UI.button(row, "Quit", func(): get_tree().quit()).custom_minimum_size.x = 0

	if ContentDB.errors.size() > 0:
		UI.label(col, "Content warnings: %d (see log)" % ContentDB.errors.size(), "Muted").add_theme_color_override("font_color", look.warn)
	UI.center_all(col)
	UI.focus_without_scrolling(start)

func _go_settings() -> void:
	SettingsScreen.return_to = "res://ui/screens/MainMenu.tscn"
	get_tree().change_scene_to_file("res://ui/screens/SettingsScreen.tscn")

func _go_dashboard() -> void:
	get_tree().change_scene_to_file("res://ui/screens/Dashboard.tscn")
