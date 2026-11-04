class_name Palette
extends RefCounted
## Visual "looks" for the UI. Each look is a flat dictionary of colours and style flags
## consumed by ThemeFactory (widgets) and Backdrop (animated background).

const DEFAULT := "noc"
const ORDER := ["noc", "blueprint", "terminal", "daylight"]

static func _raw() -> Dictionary:
	return {
		"noc": {
			"title": "Night Ops", "acronym": "#c9b8ff",
			"bg_top": "#0a0f1f", "bg_bottom": "#141c3a",
			"panel": "#17213fd6", "border": "#2b3a6b", "border_w": 1, "shadow": "#00000080",
			"text": "#e8eeff", "muted": "#8d9ac2",
			"accent": "#4cc9f0", "accent2": "#ff5ca8", "good": "#4ade80", "warn": "#fbbf24",
			"on_accent": "#06121f", "button": "#1c2850", "button_hover": "#24336a",
			"input": "#0e1530", "track": "#0e1530", "chip": "#1a2550",
			"line": "#4cc9f026", "node": "#4cc9f070",
			"radius": 14, "pattern": "none", "topology": true, "node_style": "circle",
			"animate": true, "mono": false,
			"domains": ["#4cc9f0", "#a78bfa", "#f72585", "#fbbf24", "#4ade80", "#fb923c"],
		},
		"blueprint": {
			"title": "Blueprint", "acronym": "#8ff0c8",
			"bg_top": "#0c3a68", "bg_bottom": "#082a4d",
			"panel": "#0b3560e0", "border": "#7fb8e0", "border_w": 1, "shadow": "#00000040",
			"text": "#f2f8ff", "muted": "#a6c8e6",
			"accent": "#ffd166", "accent2": "#ff8aa0", "good": "#06d6a0", "warn": "#ffd166",
			"on_accent": "#1a1300", "button": "#0f4475", "button_hover": "#155690",
			"input": "#072645", "track": "#072645", "chip": "#0f4475",
			"line": "#cfe8ff38", "node": "#cfe8ff80",
			"radius": 4, "pattern": "grid", "topology": true, "node_style": "square",
			"animate": true, "mono": false,
			"domains": ["#ffd166", "#06d6a0", "#8ecae6", "#ef476f", "#f4a261", "#c77dff"],
		},
		"terminal": {
			"title": "Phosphor", "acronym": "#6ee7f9",
			"bg_top": "#030806", "bg_bottom": "#081610",
			"panel": "#0a170ee8", "border": "#1f6b35", "border_w": 1, "shadow": "#00000000",
			"text": "#c4ffbf", "muted": "#5fa868",
			"accent": "#39ff6a", "accent2": "#ffb000", "good": "#39ff6a", "warn": "#ffb000",
			"on_accent": "#021006", "button": "#0d2414", "button_hover": "#12361d",
			"input": "#04100a", "track": "#0d2414", "chip": "#0d2414",
			"line": "#39ff6a1c", "node": "#39ff6a50",
			"radius": 2, "pattern": "scanlines", "topology": true, "node_style": "square",
			"animate": true, "mono": true,
			"domains": ["#39ff6a", "#7dffb0", "#ffb000", "#ffd866", "#5ce1e6", "#ff6b6b"],
		},
		"daylight": {
			"title": "Daylight", "acronym": "#7c3aed",
			"bg_top": "#f4f7fb", "bg_bottom": "#e3e9f3",
			"panel": "#ffffff", "border": "#dbe3ee", "border_w": 1, "shadow": "#1b243324",
			"text": "#182233", "muted": "#5d6b82",
			"accent": "#3a5bff", "accent2": "#c2410c", "good": "#15803d", "warn": "#b45309",
			"on_accent": "#ffffff", "button": "#ffffff", "button_hover": "#eef2ff",
			"input": "#f7f9fc", "track": "#e8edf5", "chip": "#eef2ff",
			"line": "#3a5bff1a", "node": "#3a5bff40",
			"radius": 16, "pattern": "dots", "topology": true, "node_style": "circle",
			"animate": false, "mono": false,
			"domains": ["#3a5bff", "#8b5cf6", "#ec4899", "#f59e0b", "#10b981", "#f97316"],
		},
	}

static func names() -> Array:
	return ORDER

## Returns the look with colour strings converted to Color.
static func get_look(look_name: String) -> Dictionary:
	var raw: Dictionary = _raw()
	var src: Dictionary = raw.get(look_name, raw[DEFAULT])
	var out := {"name": look_name if raw.has(look_name) else DEFAULT}
	for k in src:
		var val = src[k]
		if val is String and val.begins_with("#"):
			out[k] = Color(val)
		elif k == "domains":
			out[k] = val.map(func(c): return Color(c))
		else:
			out[k] = val
	return out

## The look the player chose, with their accessibility settings applied.
static func current() -> Dictionary:
	var look := get_look(Settings.ui_look)
	if Settings.high_contrast:
		look = high_contrast(look)
	if Settings.reduce_motion:
		look.animate = false
	return look

## High-contrast version of a look: pure black (or white, for light looks)
## surfaces, solid borders, no backdrop, and every text colour at 7:1 or more
## (WCAG AAA). Fonts and corner radius stay, so the look is still recognisable.
static func high_contrast(look: Dictionary) -> Dictionary:
	var out := look.duplicate()
	var dark := luminance(look.bg_bottom) < 0.5
	var c := {
		"bg_top": "#000000", "bg_bottom": "#000000", "panel": "#000000", "border": "#ffffff", "shadow": "#00000000",
		"text": "#ffffff", "muted": "#e6e6e6", "accent": "#7dd3fc", "accent2": "#ff9ecb", "good": "#86efac",
		"warn": "#fde68a", "acronym": "#f0abfc", "on_accent": "#000000", "button": "#000000", "button_hover": "#262626",
		"input": "#000000", "track": "#404040", "chip": "#000000", "line": "#00000000", "node": "#00000000",
	} if dark else {
		"bg_top": "#ffffff", "bg_bottom": "#ffffff", "panel": "#ffffff", "border": "#000000", "shadow": "#00000000",
		"text": "#000000", "muted": "#1a1a1a", "accent": "#0033cc", "accent2": "#b00020", "good": "#006400",
		"warn": "#7a4a00", "acronym": "#6b21a8", "on_accent": "#ffffff", "button": "#ffffff", "button_hover": "#e6e6e6",
		"input": "#ffffff", "track": "#bfbfbf", "chip": "#ffffff", "line": "#00000000", "node": "#00000000",
	}
	for k in c:
		out[k] = Color(c[k])
	out.border_w = 2
	out.pattern = "none"
	out.topology = false
	out.animate = false
	out.high_contrast = true
	return out

## The card colour as seen on screen (panels can be translucent).
static func panel_color(look: Dictionary) -> Color:
	return look.bg_bottom.lerp(Color(look.panel, 1.0), look.panel.a)

## WCAG 2 relative luminance (0 black .. 1 white).
static func luminance(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

## WCAG contrast ratio between two opaque colours (1..21).
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
