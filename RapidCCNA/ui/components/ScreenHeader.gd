class_name ScreenHeader
extends RefCounted
## Shared header for session screens: kicker, title, subtitle and an Exit button.

static func build(parent: Node, kicker: String, title: String, subtitle: String = "") -> HBoxContainer:
	var head := UI.hbox(parent, 16)
	var titles := UI.vbox(head, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles, kicker.to_upper(), "H3")
	UI.label(titles, title, "H1", true)
	if not subtitle.is_empty():
		UI.label(titles, subtitle, "Muted", true)
	var step_info := ""
	if SessionManager.steps.size() > 1:
		step_info = "Step %d of %d" % [SessionManager.index + 1, SessionManager.steps.size()]
	if not step_info.is_empty():
		UI.chip(head, step_info).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.button(head, "Exit", func(): SessionManager.abort()).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return head
