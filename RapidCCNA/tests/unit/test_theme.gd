extends GutTest

const REQUIRED := ["title", "bg_top", "bg_bottom", "panel", "border", "text", "muted",
	"accent", "accent2", "good", "warn", "on_accent", "button", "button_hover", "input",
	"track", "chip", "line", "node", "radius", "pattern", "topology", "animate", "mono", "domains"]

func test_every_look_has_required_keys_and_six_domain_colors():
	for n in Palette.names():
		var look := Palette.get_look(n)
		for k in REQUIRED:
			assert_true(look.has(k), "%s missing %s" % [n, k])
		assert_eq(look.domains.size(), 6, n)
		assert_true(look.accent is Color, n)

func test_unknown_look_falls_back_to_default():
	assert_eq(Palette.get_look("nope").name, Palette.DEFAULT)

func test_theme_builds_with_variations_for_every_look():
	for n in Palette.names():
		var t := ThemeFactory.build(Palette.get_look(n))
		assert_true(t.has_stylebox("panel", "Card"), n)
		assert_true(t.has_stylebox("normal", "PrimaryButton"), n)
		assert_true(t.has_font_size("font_size", "H1"), n)

func test_font_scale_applies():
	var big := ThemeFactory.build(Palette.get_look("noc"), 1.5)
	assert_eq(big.get_font_size("font_size", "H1"), 60)

func test_text_contrast_on_cards_is_readable():
	# WCAG-style relative luminance contrast between text and panel colour (opaque approx).
	for n in Palette.names():
		var l := Palette.get_look(n)
		var panel: Color = l.bg_bottom.lerp(Color(l.panel, 1.0), l.panel.a)
		assert_gt(_contrast(l.text, panel), 7.0, "%s text contrast" % n)
		assert_gt(_contrast(l.muted, panel), 3.0, "%s muted contrast" % n)

func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
