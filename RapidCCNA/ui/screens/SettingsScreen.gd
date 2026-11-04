class_name SettingsScreen
extends Control
## Accessibility and display settings. Each change is saved and applied at once
## (the screen rebuilds with the new theme), so the preview shows the result.

## Scene to go back to; set by the screen that opens this one.
static var return_to := "res://ui/screens/MainMenu.tscn"

func _ready() -> void:
	var v := UI.page(self)
	var head := UI.hbox(v, 16)
	var titles := UI.vbox(head, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles, "Settings", "H1")
	UI.label(titles, "Display and accessibility. Changes apply straight away.", "Muted", true)
	var back := UI.button(head, "Back", _back)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var display := UI.card(v, "Display")
	var size_opt := OptionButton.new()
	size_opt.accessibility_name = "Text size"
	for i in Settings.FONT_SCALES.size():
		size_opt.add_item("%d%%" % int(round(Settings.FONT_SCALES[i] * 100)), i)
		if is_equal_approx(Settings.FONT_SCALES[i], Settings.font_scale):
			size_opt.select(i)
	size_opt.item_selected.connect(func(i): _apply("font_scale", Settings.FONT_SCALES[i]))
	_row(display, "Text size", "Scales every screen, including the command-line terminal.", size_opt)
	_row(display, "Look", "Colour scheme and background.", UI.look_picker(display))
	_row(display, "High contrast", "Black or white backgrounds, solid borders and stronger colours (7:1 contrast or more). Works with any look.",
		_toggle("High contrast", Settings.high_contrast, func(on): _apply("high_contrast", on)))
	_row(display, "Reduce motion", "Stops the moving packets in the background.",
		_toggle("Reduce motion", Settings.reduce_motion, func(on): _apply("reduce_motion", on)))

	var exam := UI.card(v, "Mock exam")
	var extra_opt := OptionButton.new()
	extra_opt.accessibility_name = "Mock exam extra time"
	for i in Settings.EXTRA_TIME.size():
		var pct: int = Settings.EXTRA_TIME[i]
		extra_opt.add_item("None" if pct == 0 else "+%d%%" % pct, i)
		if pct == Settings.exam_extra_time:
			extra_opt.select(i)
	extra_opt.item_selected.connect(func(i): _apply("exam_extra_time", Settings.EXTRA_TIME[i]))
	var full := SessionManager.mock_config("full")
	_row(exam, "Extra time", "For learners with an exam accommodation. A full mock becomes %d minutes with +25%%, %d with +50%%. (Extra time on the real exam is arranged with Pearson VUE.)" % [
		MockExam.exam_minutes(full.minutes, 25), MockExam.exam_minutes(full.minutes, 50)], extra_opt)

	var preview := UI.card(v, "Preview")
	_preview(preview)
	UI.focus_later(size_opt)

func _row(parent: Node, title: String, desc: String, control: Control) -> void:
	var row := UI.hbox(parent, 16)
	var info := UI.vbox(row, 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(info, title, "Body")
	UI.label(info, desc, "Muted", true)
	if control.get_parent():
		control.get_parent().remove_child(control)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.custom_minimum_size.x = max(control.custom_minimum_size.x, 160)
	row.add_child(control)

## A switch read as e.g. "High contrast, switch, off"; its visible On/Off text is for sighted users.
func _toggle(title: String, on: bool, changed: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.accessibility_name = title
	c.button_pressed = on
	c.text = "On" if on else "Off"
	c.toggled.connect(changed)
	return c

func _preview(parent: Node) -> void:
	var look := Palette.current()
	UI.label(parent, "Which protocol is connectionless?", "Stem", true)
	for i in 2:
		var b := Button.new()
		b.text = "%d.   %s" % [i + 1, ["UDP", "TCP"][i]]
		b.theme_type_variation = "Choice"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		parent.add_child(b)
		UI.mark_choice(b, i == 0)
	var row := UI.hbox(parent, 16)
	UI.label(row, "Correct", "H2").add_theme_color_override("font_color", look.good)
	UI.label(row, "Not quite", "H2").add_theme_color_override("font_color", look.accent2)
	UI.label(row, "0:04:59", "H2").add_theme_color_override("font_color", look.warn)
	UI.label(parent, "Muted text looks like this.", "Muted", true)

func _apply(key: String, value) -> void:
	Settings.set(key, value)
	Settings.save_settings()
	if is_inside_tree():
		get_tree().reload_current_scene()

func _back() -> void:
	get_tree().change_scene_to_file(return_to)
