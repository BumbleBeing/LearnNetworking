class_name ThemeFactory
extends RefCounted
## Builds a Godot Theme from a Palette look. Type variations used by screens:
## Labels: Display, H1, H2, H3, Big, Muted, ChipText. Buttons: PrimaryButton.
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
	t.set_stylebox("normal", "LineEdit", box(p.input, p.border, max(2, r / 2), 1, 12, 9))
	t.set_stylebox("focus", "LineEdit", box(p.input, p.accent, max(2, r / 2), 2, 12, 9))
	t.set_color("font_color", "LineEdit", p.text)
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
	t.set_stylebox("hover", "PopupMenu", box(Color(p.accent, 0.25), Color.TRANSPARENT, max(2, r / 2), 0, 8, 4))
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
