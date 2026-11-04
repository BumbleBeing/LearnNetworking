class_name ThemeFactory
extends RefCounted
## Builds a Godot Theme from a Palette look. Type variations used by screens:
## Labels: Display, H1, H2, H3, Big, Muted, ChipText. Buttons: PrimaryButton.
## Rich text (UI.rich): RichStem, RichBody, RichH1, RichH2, RichMuted, RichChoice, RichCode.
## Panels: Card, Chip.

const SANS := {
	"regular": "res://assets/fonts/Inter-Regular.ttf",
	"semibold": "res://assets/fonts/Inter-SemiBold.ttf",
	"bold": "res://assets/fonts/Inter-Bold.ttf",
}
const MONO := {
	"regular": "res://assets/fonts/JetBrainsMono-Regular.ttf",
	"semibold": "res://assets/fonts/JetBrainsMono-SemiBold.ttf",
	"bold": "res://assets/fonts/JetBrainsMono-Bold.ttf",
}

static func box(bg: Color, border: Color, radius: int, bw: int = 1, pad_x: int = 12, pad_y: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s

static func build(p: Dictionary, scale: float = 1.0) -> Theme:
	var t := Theme.new()
	var r: int = p.radius
	@warning_ignore("integer_division")
	var r_small: int = max(2, r / 2)   # inputs, choices and exhibits: half the button radius
	var sz := func(n: int) -> int: return int(round(n * scale))

	# Bundled OFL fonts: Inter for most looks, JetBrains Mono for mono looks.
	var fam: Dictionary = MONO if p.mono else SANS
	var base: Font = load(fam.regular)
	var semibold: Font = load(fam.semibold)
	var bold: Font = load(fam.bold)
	t.default_font = base
	t.default_font_size = sz.call(17)

	# Labels
	t.set_color("font_color", "Label", p.text)
	for v in [["Display", 68, true, p.text], ["H1", 40, true, p.text], ["H2", 24, true, p.text],
			["H3", 14, true, p.muted], ["Big", 44, true, p.accent], ["Muted", 15, false, p.muted],
			["ChipText", 13, true, p.text]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], sz.call(v[1]))
		t.set_color("font_color", v[0], v[3])
		if v[2]:
			t.set_font("font", v[0], semibold if v[0] in ["H3", "ChipText"] else bold)

	# Body text, code and exhibits
	for v in [["Stem", 20], ["Body", 18]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], sz.call(v[1]))
		t.set_color("font_color", v[0], p.text)
		t.set_constant("line_spacing", v[0], 4)
	var code_font: Font = load(MONO.regular)
	var code_bold: Font = load(MONO.bold)
	t.set_type_variation("Code", "Label")
	t.set_font("font", "Code", code_font)
	t.set_font_size("font_size", "Code", sz.call(15))
	t.set_color("font_color", "Code", p.text)
	t.set_constant("line_spacing", "Code", 3)
	t.set_type_variation("CodeBig", "Label")
	t.set_font("font", "CodeBig", code_bold)
	t.set_font_size("font_size", "CodeBig", sz.call(38))
	t.set_color("font_color", "CodeBig", p.text)
	# Rich text: lesson cards, question stems, choices and explanations. Same sizes as the
	# Label variations above; acronyms in them get the look's acronym colour and a tooltip.
	t.set_color("default_color", "RichTextLabel", p.text)
	t.set_font("normal_font", "RichTextLabel", base)
	t.set_font_size("normal_font_size", "RichTextLabel", sz.call(17))
	for v in [["RichStem", 20, base, p.text, 4], ["RichBody", 18, base, p.text, 4], ["RichH1", 40, bold, p.text, 0],
			["RichH2", 24, bold, p.text, 0], ["RichMuted", 15, base, p.muted, 0], ["RichChoice", 17, base, p.text, 0],
			["RichCode", 15, code_font, p.text, 3]]:
		t.set_type_variation(v[0], "RichTextLabel")
		t.set_font("normal_font", v[0], v[2])
		t.set_font_size("normal_font_size", v[0], sz.call(v[1]))
		t.set_color("default_color", v[0], v[3])
		t.set_constant("line_separation", v[0], v[4])
	t.set_stylebox("panel", "TooltipPanel", box(Color(p.panel, 1.0), p.acronym, r_small, 1, 10, 6))
	t.set_color("font_color", "TooltipLabel", p.text)
	t.set_font_size("font_size", "TooltipLabel", sz.call(15))
	t.set_type_variation("Exhibit", "PanelContainer")
	t.set_stylebox("panel", "Exhibit", box(p.input, p.border, r_small, 1, 16, 12))

	# Buttons
	t.set_font("font", "Button", semibold)
	t.set_font_size("font_size", "Button", sz.call(16))
	t.set_stylebox("normal", "Button", box(p.button, p.border, r, 1, 20, 11))
	t.set_stylebox("hover", "Button", box(p.button_hover, p.accent, r, 1, 20, 11))
	t.set_stylebox("pressed", "Button", box(p.accent.darkened(0.15), p.accent, r, 1, 20, 11))
	t.set_stylebox("disabled", "Button", box(Color(p.button, p.button.a * 0.5), Color(p.border, 0.5), r, 1, 20, 11))
	var focus := box(Color.TRANSPARENT, p.accent, r + 2, 2)
	focus.draw_center = false
	focus.set_expand_margin_all(3)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", p.text)
	t.set_color("font_hover_color", "Button", p.text)
	t.set_color("font_focus_color", "Button", p.text)
	t.set_color("font_pressed_color", "Button", p.on_accent)
	t.set_color("font_hover_pressed_color", "Button", p.on_accent)
	t.set_color("font_disabled_color", "Button", Color(p.muted, 0.7))

	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(p.accent, p.accent, r, 1, 26, 13))
	t.set_stylebox("hover", "PrimaryButton", box(p.accent.lightened(0.15), p.accent.lightened(0.15), r, 1, 26, 13))
	t.set_stylebox("pressed", "PrimaryButton", box(p.accent.darkened(0.15), p.accent, r, 1, 26, 13))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(p.accent, 0.35), Color(p.accent, 0.35), r, 1, 26, 13))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", p.on_accent)
	t.set_color("font_disabled_color", "PrimaryButton", Color(p.on_accent, 0.6))
	t.set_font_size("font_size", "PrimaryButton", sz.call(18))
	t.set_font("font", "PrimaryButton", semibold)
	t.set_font("font", "OptionButton", semibold)
	t.set_font_size("font_size", "OptionButton", sz.call(16))

	# Answer choices and bit toggles (toggle buttons)
	t.set_type_variation("Choice", "Button")
	t.set_stylebox("normal", "Choice", box(p.input, p.border, r_small, 1, 16, 12))
	t.set_stylebox("hover", "Choice", box(p.button_hover, p.accent, r_small, 1, 16, 12))
	t.set_stylebox("pressed", "Choice", box(Color(p.accent, 0.18), p.accent, r_small, 2, 16, 12))
	t.set_stylebox("hover_pressed", "Choice", box(Color(p.accent, 0.24), p.accent, r_small, 2, 16, 12))
	t.set_stylebox("disabled", "Choice", box(p.input, Color(p.border, 0.6), r_small, 1, 16, 12))
	t.set_font("font", "Choice", base)
	t.set_font_size("font_size", "Choice", sz.call(17))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		t.set_color(c, "Choice", p.text)
	t.set_type_variation("Bit", "Button")
	t.set_stylebox("normal", "Bit", box(p.input, p.border, r_small, 1, 8, 8))
	t.set_stylebox("hover", "Bit", box(p.button_hover, p.accent, r_small, 1, 8, 8))
	t.set_stylebox("pressed", "Bit", box(p.accent, p.accent, r_small, 1, 8, 8))
	t.set_stylebox("hover_pressed", "Bit", box(p.accent.lightened(0.1), p.accent, r_small, 1, 8, 8))
	t.set_stylebox("disabled", "Bit", box(p.input, Color(p.border, 0.6), r_small, 1, 8, 8))
	t.set_font("font", "Bit", code_bold)
	t.set_font_size("font_size", "Bit", sz.call(28))
	t.set_color("font_color", "Bit", p.muted)
	t.set_color("font_hover_color", "Bit", p.text)
	t.set_color("font_focus_color", "Bit", p.text)
	t.set_color("font_disabled_color", "Bit", p.muted)
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Bit", p.on_accent)

	# Panels
	t.set_type_variation("Card", "PanelContainer")
	var card := box(p.panel, p.border, r, p.border_w, 24, 20)
	card.shadow_color = p.shadow
	card.shadow_size = 14
	card.shadow_offset = Vector2(0, 5)
	t.set_stylebox("panel", "Card", card)
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(p.chip, p.border, 999, 1, 14, 5))

	# Inputs
	t.set_stylebox("normal", "LineEdit", box(p.input, p.border, r_small, 1, 12, 9))
	t.set_stylebox("focus", "LineEdit", box(p.input, p.accent, r_small, 2, 12, 9))
	t.set_stylebox("read_only", "LineEdit", box(Color(p.input, p.input.a * 0.6), Color(p.border, 0.6), r_small, 1, 12, 9))
	t.set_color("font_color", "LineEdit", p.text)
	t.set_color("font_uneditable_color", "LineEdit", Color(p.text, 0.75))
	t.set_color("font_placeholder_color", "LineEdit", Color(p.muted, 0.8))
	t.set_color("caret_color", "LineEdit", p.accent)
	t.set_color("selection_color", "LineEdit", Color(p.accent, 0.35))

	# Progress bars (fill colour usually overridden per bar)
	t.set_stylebox("background", "ProgressBar", box(p.track, Color.TRANSPARENT, 999, 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(p.accent, Color.TRANSPARENT, 999, 0, 0, 0))
	t.set_color("font_color", "ProgressBar", p.text)

	# Popups (OptionButton menus)
	var popup := box(Color(p.panel, 1.0), p.border, r, 1, 8, 8)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color(p.accent, 0.25), Color.TRANSPARENT, r_small, 0, 8, 4))
	t.set_color("font_color", "PopupMenu", p.text)
	t.set_color("font_hover_color", "PopupMenu", p.text)

	# Scrollbars (ScrollContainer gets no background so the backdrop shows through)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var track := box(Color.TRANSPARENT, Color.TRANSPARENT, 999, 0, 4, 4)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", box(Color(p.muted, 0.35), Color.TRANSPARENT, 999, 0, 4, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(p.muted, 0.6), Color.TRANSPARENT, 999, 0, 4, 4))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(p.accent, Color.TRANSPARENT, 999, 0, 4, 4))
	return t
