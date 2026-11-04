class_name Palette
extends RefCounted
## Visual "looks" for the UI. Each look is a flat dictionary of colours and style flags
## consumed by ThemeFactory (widgets) and Backdrop (animated background).

const DEFAULT := "noc"
const ORDER := ["noc", "blueprint", "terminal", "daylight"]

static func _raw() -> Dictionary:
	return {
		"noc": {
			"title": "Night Ops",
			"bg_top": "#0a0f1f", "bg_bottom": "#141c3a",
			"panel": "#17213fd6", "border": "#2b3a6b", "border_w": 1, "shadow": "#00000080",
			"text": "#e8eeff", "muted": "#8d9ac2",
			"accent": "#4cc9f0", "accent2": "#f72585", "good": "#4ade80", "warn": "#fbbf24",
			"on_accent": "#06121f", "button": "#1c2850", "button_hover": "#24336a",
			"input": "#0e1530", "track": "#0e1530", "chip": "#1a2550",
			"line": "#4cc9f026", "node": "#4cc9f070",
			"radius": 14, "pattern": "none", "topology": true, "node_style": "circle",
			"animate": true, "mono": false,
			"domains": ["#4cc9f0", "#a78bfa", "#f72585", "#fbbf24", "#4ade80", "#fb923c"],
		},
		"blueprint": {
			"title": "Blueprint",
			"bg_top": "#0c3a68", "bg_bottom": "#082a4d",
			"panel": "#0b3560e0", "border": "#7fb8e0", "border_w": 1, "shadow": "#00000040",
			"text": "#f2f8ff", "muted": "#a6c8e6",
			"accent": "#ffd166", "accent2": "#ef476f", "good": "#06d6a0", "warn": "#ffd166",
			"on_accent": "#1a1300", "button": "#0f4475", "button_hover": "#155690",
			"input": "#072645", "track": "#072645", "chip": "#0f4475",
			"line": "#cfe8ff38", "node": "#cfe8ff80",
			"radius": 4, "pattern": "grid", "topology": true, "node_style": "square",
			"animate": true, "mono": false,
			"domains": ["#ffd166", "#06d6a0", "#8ecae6", "#ef476f", "#f4a261", "#c77dff"],
		},
		"terminal": {
			"title": "Phosphor",
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
			"title": "Daylight",
			"bg_top": "#f4f7fb", "bg_bottom": "#e3e9f3",
			"panel": "#ffffff", "border": "#dbe3ee", "border_w": 1, "shadow": "#1b243324",
			"text": "#182233", "muted": "#5d6b82",
			"accent": "#3a5bff", "accent2": "#ff6b3d", "good": "#16a34a", "warn": "#f59e0b",
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

static func current() -> Dictionary:
	return get_look(Settings.ui_look)
