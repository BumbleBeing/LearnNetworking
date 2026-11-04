class_name Terminal
extends VBoxContainer
## An IOS-style console bound to a CLISession. Enter runs, '?' shows help instantly,
## Tab completes, Up/Down walk history. Clicking the console focuses the input.

signal command_run(line: String, output: String)

const MAX_LINES := 800

var session: CLISession
var _scroll: ScrollContainer
var _out: Label
var _prompt: Label
var _input: LineEdit
var _lines := PackedStringArray()
var _hist_i := -1
var _banner := ""

func setup(s: CLISession, banner: String = "") -> Terminal:
	session = s
	_banner = banner
	return self

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Exhibit"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 340
	panel.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _input.grab_focus())
	add_child(panel)
	var v := UI.vbox(panel, 0)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_out = UI.label(_scroll, "", "Code")
	_out.add_theme_font_size_override("font_size", int(14 * Settings.font_scale))
	_out.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox(v, 0)
	_prompt = UI.label(row, "", "Code")
	_prompt.add_theme_font_size_override("font_size", int(14 * Settings.font_scale))
	_input = LineEdit.new()
	_input.flat = true
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_override("font", load(ThemeFactory.MONO.regular))
	_input.add_theme_font_size_override("font_size", int(14 * Settings.font_scale))
	_input.add_theme_constant_override("minimum_character_width", 0)
	for sb in ["normal", "focus", "read_only"]:
		_input.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
	_input.caret_blink = true
	_input.context_menu_enabled = false
	_input.text_submitted.connect(_submit)
	_input.text_changed.connect(_on_changed)
	_input.gui_input.connect(_on_input_key)
	row.add_child(_input)
	if not _banner.is_empty():
		_append(_banner)
	_append("")
	_refresh_prompt()
	UI.focus_later(_input)

func _refresh_prompt() -> void:
	_prompt.text = session.prompt()

func _append(text: String) -> void:
	for l in text.split("\n"):
		_lines.append(l)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_out.text = "\n".join(_lines)
	_scroll_to_end()

func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func run(line: String) -> String:
	_append(session.prompt() + line)
	var out := session.execute(line)
	if not out.is_empty():
		_append(out)
	_refresh_prompt()
	command_run.emit(line, out)
	return out

func _submit(text: String) -> void:
	_hist_i = -1
	_input.text = ""
	run(text)

func _on_changed(t: String) -> void:
	if not t.ends_with("?"):
		return
	_append(session.prompt() + t)
	_append(session.help(t))
	_input.text = t.substr(0, t.length() - 1)
	_input.caret_column = _input.text.length()

func _on_input_key(e: InputEvent) -> void:
	if not e is InputEventKey or not e.pressed:
		return
	match e.keycode:
		KEY_TAB:
			_input.text = session.complete(_input.text)
			_input.caret_column = _input.text.length()
			_input.accept_event()
		KEY_UP, KEY_DOWN:
			var h: Array = session.history
			if h.is_empty():
				return
			if e.keycode == KEY_UP:
				_hist_i = h.size() - 1 if _hist_i < 0 else max(0, _hist_i - 1)
			else:
				_hist_i = -1 if _hist_i < 0 or _hist_i >= h.size() - 1 else _hist_i + 1
			_input.text = "" if _hist_i < 0 else h[_hist_i]
			_input.caret_column = _input.text.length()
			_input.accept_event()

func lock() -> void:
	_input.editable = false
