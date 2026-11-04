class_name UI
extends RefCounted
## Helpers for building themed screens in code. Styling comes from ThemeFactory,
## so screens only pick type variations (H1, Muted, Card, PrimaryButton...).

## Sets up theme + backdrop on `root` and returns the content container.
## centered=true gives a centred column (menus); otherwise a scrolling page.
static func page(root: Control, centered: bool = false) -> VBoxContainer:
	var look := Palette.current()
	root.theme = ThemeFactory.build(look, Settings.font_scale)
	var bd := Backdrop.new()
	bd.look = look
	root.add_child(bd)
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 40)
	root.add_child(m)
	var v: VBoxContainer
	if centered:
		var c := CenterContainer.new()
		m.add_child(c)
		v = vbox(c, 18)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		m.add_child(scroll)
		v = vbox(scroll, 20)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

static func vbox(parent: Node, sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v

static func hbox(parent: Node, sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h

## wrap=true only for labels inside vertical containers; wrapping labels in an
## HBox collapse to zero width.
static func label(parent: Node, text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	parent.add_child(l)
	return l

static func button(parent: Node, text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "PrimaryButton" if primary else ""
	b.custom_minimum_size = Vector2(200, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

## A themed card; returns its inner VBox. stretch>0 makes it expand in an HBox.
static func card(parent: Node, title: String = "", stretch: float = 0.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Card"
	if stretch > 0.0:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = stretch
	parent.add_child(panel)
	var v := vbox(panel, 12)
	if not title.is_empty():
		label(v, title.to_upper(), "H3")
	return v

static func chip(parent: Node, text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Chip"
	parent.add_child(panel)
	label(panel, text, "ChipText")
	return panel

## Big-number stat tile.
static func stat(parent: Node, value: String, caption: String, color: Color) -> VBoxContainer:
	var v := card(parent, "", 1.0)
	v.add_theme_constant_override("separation", 0)
	var big := label(v, value, "Big")
	big.add_theme_color_override("font_color", color)
	label(v, caption, "Muted")
	center_all(v)
	return v

static func bar(parent: Node, value: float, color: Color, height: int = 10) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = 1.0
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size.y = height
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("fill", ThemeFactory.box(color, Color.TRANSPARENT, 999, 0, 0, 0))
	parent.add_child(b)
	return b

## Dropdown that switches the UI look and reloads the current scene.
static func look_picker(parent: Node) -> OptionButton:
	var opt := OptionButton.new()
	var names := Palette.names()
	for i in names.size():
		opt.add_item(Palette.get_look(names[i]).title, i)
		if names[i] == Settings.ui_look:
			opt.select(i)
	opt.item_selected.connect(func(i):
		Settings.ui_look = names[i]
		Settings.save_settings()
		opt.get_tree().reload_current_scene())
	parent.add_child(opt)
	return opt

## Centre-aligns everything under `node`: labels' text, buttons/inputs (shrink to
## centre) and nested box rows. Call after the subtree is built.
static func center_all(node: Node) -> void:
	for c in node.get_children():
		if c is Label:
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif c is BoxContainer:
			c.alignment = BoxContainer.ALIGNMENT_CENTER
			if c is HBoxContainer:
				c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			center_all(c)
		elif c is Button or c is LineEdit or c is PanelContainer:
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			if c is PanelContainer:
				center_all(c)

## Focus a control on the next frame, if it still exists and is in the tree.
static func focus_later(c: Control) -> void:
	var ref: WeakRef = weakref(c)
	(func():
		var n = ref.get_ref()
		if n and n.is_inside_tree() and n.is_visible_in_tree():
			n.grab_focus()).call_deferred()

## Scroll the nearest ScrollContainer so `c` is visible (after layout settles).
static func scroll_into_view(c: Control) -> void:
	var ref: WeakRef = weakref(c)
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	var n = ref.get_ref()
	if n == null or not n.is_inside_tree():
		return
	var p = n.get_parent()
	while p and not p is ScrollContainer:
		p = p.get_parent()
	if p:
		p.ensure_control_visible(n)
