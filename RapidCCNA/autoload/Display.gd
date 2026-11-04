extends Node
## Keeps text readable on small screens (phones, small browser windows).
##
## The UI is designed on a 1280x720 canvas that Godot scales to fit the window.
## On a small screen that shrinks text below readable size, so windows smaller
## than 1280x720 get a smaller logical canvas instead, which scales down less.
## The canvas never goes below MIN_SIZE: every screen's layout is checked there.
## Narrow portrait screens get a prompt to turn the device sideways.

const BASE := Vector2i(1280, 720)
const MIN_SIZE := Vector2i(960, 360)
const PORTRAIT_MAX_WIDTH := 700      # CSS px; wider portrait windows lay out fine

var _overlay: CanvasLayer
var _overlay_dismissed := false

func _ready() -> void:
	get_tree().root.size_changed.connect(apply)
	apply.call_deferred()

## Window size in CSS-like pixels (physical pixels / device pixel ratio).
func css_size() -> Vector2:
	var scale := DisplayServer.screen_get_scale()
	return Vector2(get_tree().root.size) / (scale if scale > 0.0 else 1.0)

## Logical canvas size for a window of `css` pixels.
static func logical_base(css: Vector2) -> Vector2i:
	return Vector2i(clampi(int(css.x), MIN_SIZE.x, BASE.x), clampi(int(css.y), MIN_SIZE.y, BASE.y))

## How many CSS pixels one logical pixel takes (1.0 = crisp 1:1).
static func ui_scale(css: Vector2) -> float:
	var b := logical_base(css)
	return min(css.x / b.x, css.y / b.y)

static func wants_rotation(css: Vector2) -> bool:
	return css.y > css.x and css.x < PORTRAIT_MAX_WIDTH

func apply() -> void:
	var css := css_size()
	if css.x <= 0 or css.y <= 0:
		return
	var root := get_tree().root
	var base := logical_base(css)
	if root.content_scale_size != base:
		root.content_scale_size = base
	_show_rotate_prompt(wants_rotation(css) and not _overlay_dismissed)

func _show_rotate_prompt(show: bool) -> void:
	if not show:
		if _overlay:
			_overlay.queue_free()
			_overlay = null
		return
	if _overlay:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = ThemeFactory.build(Palette.current(), 2.0)
	_overlay.add_child(root)
	var bg := ColorRect.new()
	bg.color = Palette.current().bg_bottom
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := UI.vbox(center, 24)
	v.custom_minimum_size.x = 820
	UI.label(v, "Turn your device sideways", "H1", true)
	UI.label(v, "RapidCCNA is laid out for landscape screens. Rotate your phone, or widen the window.", "Body", true)
	var btn := UI.button(v, "Continue anyway", func():
		_overlay_dismissed = true
		_show_rotate_prompt(false), true)
	btn.custom_minimum_size.x = 420
	UI.center_all(v)
