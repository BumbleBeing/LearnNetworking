extends Control

func _ready() -> void:
	var v := UI.page(self)
	UI.label(v, "RapidCCNA", 48)
	UI.label(v, "CCNA 200-301 bootcamp", 20)
	var start := UI.button(v, "Start studying", _go_dashboard)
	UI.button(v, "Quit", func(): get_tree().quit())
	if ContentDB.errors.size() > 0:
		UI.label(v, "Content warnings: %d (see log)" % ContentDB.errors.size(), 14).modulate = Color.ORANGE
	start.grab_focus()

func _go_dashboard() -> void:
	get_tree().change_scene_to_file("res://ui/screens/Dashboard.tscn")
