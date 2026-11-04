extends DrillBase
## Bit Flipper: decimal <-> binary <-> hex for single octets.
## dec_to_bin uses 8 toggle bits (keys 1-8 flip them); other kinds take typed input.

var item: Dictionary
var _answer: LineEdit
var _bits: Array[Button] = []
var _total: Label

const TITLES := {
	"dec_to_bin": "Set the bits to make this number",
	"bin_to_dec": "Convert to decimal",
	"dec_to_hex": "Convert to hex",
	"hex_to_dec": "Convert to decimal",
}

func present_item() -> void:
	item = Binary.make_item(rng)
	_bits.clear()
	_answer = null
	var p := UI.label(prompt_box, item.prompt, "CodeBig")
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := UI.label(prompt_box, TITLES[item.kind], "H2")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if item.kind == "dec_to_bin":
		_build_bits()
	else:
		_answer = answer_input("e.g. 0xC0" if item.kind == "dec_to_hex" else "0-255")

func _build_bits() -> void:
	var row := UI.hbox(answer_box, 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 8:
		var col := UI.vbox(row, 4)
		var b := Button.new()
		b.text = "0"
		b.toggle_mode = true
		b.theme_type_variation = "Bit"
		b.custom_minimum_size = Vector2(56, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(func(on): b.text = "1" if on else "0"; _update_total())
		col.add_child(b)
		_bits.append(b)
		if guided:
			var pl := UI.label(col, str(Binary.PLACE[i]), "Muted")
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == 3:
			var gap := Control.new()
			gap.custom_minimum_size.x = 10
			row.add_child(gap)
	_total = UI.label(answer_box, "", "Muted")
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_total()
	UI.label(answer_box, "Click bits or press 1-8, then Enter.", "Muted").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.focus_later(_submit_btn)

func _update_total() -> void:
	if _total == null or not guided:
		return
	_total.text = "Current value: %d" % Binary.parse_bin(get_response())

func _unhandled_key_input(event: InputEvent) -> void:
	if _bits.is_empty() or _answered or not event is InputEventKey or not event.pressed or event.echo:
		return
	var n: int = event.keycode - KEY_1
	if n >= 0 and n < 8:
		_bits[n].button_pressed = not _bits[n].button_pressed
		get_viewport().set_input_as_handled()

func get_response() -> String:
	if not _bits.is_empty():
		var s := ""
		for b in _bits:
			s += "1" if b.button_pressed else "0"
		return s
	return _answer.text if _answer else ""

func check(r: String) -> bool: return Binary.check(item, r)
func explain() -> String: return Binary.explain(item)
func card_id() -> String: return item.card_id
func correct_answer() -> String: return item.answer

func hint() -> String:
	match item.kind:
		"dec_to_bin":
			return "Go left to right: if the place value fits in what's left, set the bit and subtract."
		"bin_to_dec":
			return "Add the place values (128 64 32 16 8 4 2 1) of every 1 bit."
		"dec_to_hex":
			return "Write the binary, split it into two 4-bit halves; each half is one hex digit (10-15 = A-F)."
		_:
			return "First hex digit x 16 + second digit. A=10 ... F=15."

func lock_inputs() -> void:
	for b in _bits:
		b.disabled = true
	if _answer:
		_answer.editable = false
