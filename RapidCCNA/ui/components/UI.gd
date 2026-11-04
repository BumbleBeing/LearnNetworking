class_name UI
extends RefCounted
## Tiny helpers so screens can be built in code (keeps .tscn diffs trivial in M0).

static func vbox(parent: Node, sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v

static func label(parent: Node, text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * Settings.font_scale))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

static func button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", int(18 * Settings.font_scale))
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

## Full-rect margin container that centres content with a max width.
static func page(root: Control) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color("#10151c") if not Settings.high_contrast else Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	root.add_child(m)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(scroll)
	var v := vbox(scroll, 16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v
