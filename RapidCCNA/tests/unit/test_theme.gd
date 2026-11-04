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

## WCAG 2.1: body text needs 4.5:1 (AA); high contrast aims for 7:1 (AAA).
## Every colour drawn as text on a card is checked: feedback (good/accent2),
## the exam clock warning, muted captions and the primary button label.
const TEXT_KEYS := ["text", "muted", "accent", "accent2", "good", "warn"]

func _check_look(l: Dictionary, min_ratio: float) -> void:
	var panel := Palette.panel_color(l)
	for k in TEXT_KEYS:
		var ratio := Palette.contrast(l[k], panel)
		assert_true(ratio >= min_ratio, "%s%s %s on card: %.2f < %.1f" % [l.name, " (HC)" if l.get("high_contrast", false) else "", k, ratio, min_ratio])
	var btn := Palette.contrast(l.on_accent, l.accent)
	assert_true(btn >= min_ratio, "%s primary button label: %.2f" % [l.name, btn])

func test_every_look_meets_wcag_aa_for_text():
	for n in Palette.names():
		_check_look(Palette.get_look(n), 4.5)

func test_high_contrast_meets_wcag_aaa_and_drops_decoration():
	for n in Palette.names():
		var hc := Palette.high_contrast(Palette.get_look(n))
		_check_look(hc, 7.0)
		assert_true(Palette.contrast(hc.border, Palette.panel_color(hc)) >= 7.0, "%s HC border" % n)
		assert_false(hc.animate, n)
		assert_false(hc.topology, n)
		assert_eq(hc.panel.a, 1.0, "%s HC cards are opaque" % n)
		assert_eq(hc.mono, Palette.get_look(n).mono, "%s keeps its font" % n)

func test_contrast_maths():
	assert_almost_eq(Palette.contrast(Color.BLACK, Color.WHITE), 21.0, 0.01)
	assert_almost_eq(Palette.contrast(Color.WHITE, Color.WHITE), 1.0, 0.001)
	assert_almost_eq(Palette.contrast(Color("#767676"), Color.WHITE), 4.54, 0.01, "the classic AA grey")

func test_night_ops_is_default():
	assert_eq(Palette.DEFAULT, "noc")
	assert_eq(Palette.get_look("").name, "noc")
	var fresh := preload("res://autoload/Settings.gd").new()
	assert_eq(fresh.ui_look, "noc")
	fresh.free()

func test_bundled_inter_is_used():
	var t := ThemeFactory.build(Palette.get_look("noc"))
	assert_eq(t.default_font.resource_path, ThemeFactory.SANS.regular)
	assert_eq(t.get_font("font", "H1").resource_path, ThemeFactory.SANS.bold)
	assert_eq(t.get_font("font", "Button").resource_path, ThemeFactory.SANS.semibold)

func test_mono_look_uses_bundled_jetbrains_mono():
	var t := ThemeFactory.build(Palette.get_look("terminal"))
	assert_eq(t.default_font.resource_path, ThemeFactory.MONO.regular)
	assert_eq(t.get_font("font", "H1").resource_path, ThemeFactory.MONO.bold)
