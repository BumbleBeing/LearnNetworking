extends Node
## Player profile: mastery attempts, streak, SRS state. Saved as versioned JSON.

signal saved

const SAVE_VERSION := 1
const MASTERY_WINDOW := 20
const MASTERY_THRESHOLD := 0.85

var save_path := "user://save.json"
var attempts: Dictionary = {}     # unit_id -> Array[bool], last MASTERY_WINDOW unguided results
var streak_days: int = 0
var last_study_day: String = ""   # yyyy-mm-dd
var total_minutes: float = 0.0
var tutorials_done: Dictionary = {}  # lesson_id -> unix time completed

func _ready() -> void:
	load_game()

func reset() -> void:
	attempts = {}
	streak_days = 0
	last_study_day = ""
	total_minutes = 0.0
	tutorials_done = {}
	SRS.reset()

func record_attempt(unit_id: String, correct: bool) -> void:
	var arr: Array = attempts.get(unit_id, [])
	arr.append(correct)
	while arr.size() > MASTERY_WINDOW:
		arr.pop_front()
	attempts[unit_id] = arr

func accuracy(unit_id: String) -> float:
	var arr: Array = attempts.get(unit_id, [])
	if arr.is_empty():
		return 0.0
	return float(arr.count(true)) / arr.size()

func attempt_count(unit_id: String) -> int:
	return attempts.get(unit_id, []).size()

func mark_tutorial_done(lesson_id: String) -> void:
	tutorials_done[lesson_id] = int(Time.get_unix_time_from_system())

func is_tutorial_done(lesson_id: String) -> bool:
	return tutorials_done.has(lesson_id)

func is_mastered(unit_id: String) -> bool:
	var arr: Array = attempts.get(unit_id, [])
	return arr.size() >= MASTERY_WINDOW and accuracy(unit_id) >= MASTERY_THRESHOLD

## Call when the player studies; `today` is yyyy-mm-dd.
func mark_studied(today: String = "") -> void:
	if today.is_empty():
		today = Time.get_date_string_from_system()
	if today == last_study_day:
		return
	if not last_study_day.is_empty() and _day_diff(last_study_day, today) == 1:
		streak_days += 1
	else:
		streak_days = 1
	last_study_day = today

## Mean accuracy over a domain's units (0..1).
func domain_readiness(domain_id: String) -> float:
	var units := ContentDB.lessons_for_domain(domain_id)
	if units.is_empty():
		return 0.0
	var total := 0.0
	for u in units:
		total += accuracy(u.id)
	return total / units.size()

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"attempts": attempts,
		"streak_days": streak_days,
		"last_study_day": last_study_day,
		"total_minutes": total_minutes,
		"tutorials_done": tutorials_done,
		"srs": SRS.to_dict(),
	}

func from_dict(d: Dictionary) -> void:
	d = _migrate(d)
	attempts = d.get("attempts", {})
	streak_days = int(d.get("streak_days", 0))
	last_study_day = str(d.get("last_study_day", ""))
	total_minutes = float(d.get("total_minutes", 0.0))
	tutorials_done = d.get("tutorials_done", {})
	SRS.from_dict(d.get("srs", {}))

func save_game() -> bool:
	var ok := JsonIO.write(save_path, to_dict())
	if ok:
		saved.emit()
	return ok

func load_game() -> void:
	reset()
	var d = JsonIO.read(save_path)
	if d is Dictionary:
		from_dict(d)

## Upgrade older save formats here as SAVE_VERSION grows.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		push_warning("Save is from a newer version (%d); loading best-effort" % v)
	return d

static func _day_diff(a: String, b: String) -> int:
	var ta := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var tb := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round((tb - ta) / 86400.0))
