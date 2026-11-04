extends Node
## User preferences. Persisted separately from progress so a reset doesn't wipe them.

signal changed

const PATH := "user://settings.json"

var exam_date: String = ""        # ISO yyyy-mm-dd, empty = not set
var daily_goal_minutes: int = 60
var font_scale: float = 1.0
var high_contrast: bool = false
var ui_look: String = "noc"         # see ui/theme/Palette.gd
var reduce_motion: bool = false    # stops the animated backdrop
var exam_extra_time: int = 0        # % added to mock exam time (accommodation): 0, 25, 50 or 100

const FONT_SCALES := [0.85, 1.0, 1.15, 1.3, 1.5]
const EXTRA_TIME := [0, 25, 50, 100]

func _ready() -> void:
	load_settings()

func to_dict() -> Dictionary:
	return {
		"exam_date": exam_date,
		"daily_goal_minutes": daily_goal_minutes,
		"font_scale": font_scale,
		"high_contrast": high_contrast,
		"ui_look": ui_look,
		"reduce_motion": reduce_motion,
		"exam_extra_time": exam_extra_time,
	}

func from_dict(d: Dictionary) -> void:
	exam_date = str(d.get("exam_date", exam_date))
	daily_goal_minutes = int(d.get("daily_goal_minutes", daily_goal_minutes))
	font_scale = float(d.get("font_scale", font_scale))
	high_contrast = bool(d.get("high_contrast", high_contrast))
	ui_look = str(d.get("ui_look", ui_look))
	reduce_motion = bool(d.get("reduce_motion", reduce_motion))
	exam_extra_time = int(d.get("exam_extra_time", exam_extra_time))
	if not exam_extra_time in EXTRA_TIME:
		exam_extra_time = 0
	font_scale = clampf(font_scale, FONT_SCALES[0], FONT_SCALES[-1])

func load_settings() -> void:
	var d = JsonIO.read(PATH)
	if d is Dictionary:
		from_dict(d)

func save_settings() -> void:
	JsonIO.write(PATH, to_dict())
	changed.emit()

## Days until exam_date, or -1 if not set / unparseable.
func days_until_exam(today_unix: int = -1) -> int:
	if exam_date.is_empty():
		return -1
	var parts := exam_date.split("-")
	if parts.size() != 3:
		return -1
	var target := Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 0, "minute": 0, "second": 0})
	if today_unix < 0:
		today_unix = int(Time.get_unix_time_from_system())
	return int(ceil((target - today_unix) / 86400.0))
