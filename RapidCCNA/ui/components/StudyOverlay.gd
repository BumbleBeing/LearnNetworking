class_name StudyOverlay
extends Control
## The whole lesson a question comes from, shown over the current screen when the learner
## presses Study. Closing it (either Back button or Esc) returns to the question exactly as
## it was left, so nothing typed or selected is lost.

signal closed

## How many overlays are open; the question underneath ignores its shortcut keys meanwhile.
static var _open_count := 0

var lesson: Dictionary = {}
var _back: Button
var _closing := false

static func is_open() -> bool:
	return _open_count > 0

## Shows `lesson_dict` above the screen that `from` is on and returns the overlay.
static func open(from: Control, lesson_dict: Dictionary) -> StudyOverlay:
	var o := StudyOverlay.new()
	o.lesson = lesson_dict
	# Attach to the screen itself (the outermost control with a theme), so a scene change frees it.
	var host: Node = from
	var n: Node = from
	while n != null:
		if n is Control and (n as Control).theme != null:
			host = n
		n = n.get_parent()
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(o)
	host.add_child(layer)
	return o

func _enter_tree() -> void:
	_open_count += 1

func _exit_tree() -> void:
	_open_count = maxi(0, _open_count - 1)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind can be clicked while studying
	var v := UI.page(self)
	var head := UI.hbox(v, 16)
	var titles := UI.vbox(head, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d := ContentDB.get_domain(lesson.get("domain", ""))
	UI.label(titles, ("Study  ·  " + str(d.get("name", ""))).to_upper(), "H3")
	UI.rich(titles, str(lesson.get("title", "Lesson")), "H1")
	UI.label(titles, "The lesson behind this question. Go back when you're ready to answer.", "Muted", true)
	_back = UI.button(head, "Back to the question", close, true)
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cards: Array = lesson.get("cards", [])
	for i in cards.size():
		var c := UI.card(v)
		UI.label(c, "Card %d of %d" % [i + 1, cards.size()], "H3")
		UI.lesson_card(c, cards[i])
	var bottom := UI.button(v, "Back to the question", close)
	bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.set_meta("a11y_same_as_another", true)   # same job as the button at the top
	UI.focus_later(_back)
	UI.announce("Studying %s, %d cards. Press Escape to go back to the question." % [lesson.get("title", "the lesson"), cards.size()])

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	# Swallow every key, so digits and Enter don't answer the question underneath.
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		close()

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.get_parent().remove_child(layer)
		layer.queue_free()
	else:
		queue_free()
