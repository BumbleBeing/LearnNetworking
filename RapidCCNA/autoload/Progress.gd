extends Node
## Player profile: mastery attempts, streak, SRS state. Saved as versioned JSON.

signal saved

const SAVE_VERSION := 2
const MASTERY_WINDOW := 20
const MASTERY_THRESHOLD := 0.85
const MOCK_HISTORY_MAX := 30

var save_path := "user://save.json"
var attempts: Dictionary = {}     # unit_id -> Array[bool], last MASTERY_WINDOW unguided results
var streak_days: int = 0
var last_study_day: String = ""   # yyyy-mm-dd
var total_minutes: float = 0.0
var tutorials_done: Dictionary = {}  # lesson_id -> unix time completed
var labs_done: Dictionary = {}       # lab_id -> unix time first completed
var mock_history: Array = []         # oldest first: {when, label, total, correct, scaled, passed, seconds, by_domain}
var last_mock_ids: Array = []        # questions on the latest mock; the next one prefers others

func _ready() -> void:
	load_game()

func reset() -> void:
	attempts = {}
	streak_days = 0
	last_study_day = ""
	total_minutes = 0.0
	tutorials_done = {}
	labs_done = {}
	mock_history = []
	last_mock_ids = []
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

func mark_lab_done(lab_id: String) -> void:
	if not labs_done.has(lab_id):
		labs_done[lab_id] = int(Time.get_unix_time_from_system())

func is_lab_done(lab_id: String) -> bool:
	return labs_done.has(lab_id)

## Stores a finished mock exam (a MockExam.score report plus label/seconds).
func record_mock(report: Dictionary, label: String, seconds: int, ids: Array, when: int = -1) -> void:
	if when < 0:
		when = int(Time.get_unix_time_from_system())
	mock_history.append({"when": when, "label": label, "total": int(report.total), "correct": int(report.correct),
		"scaled": int(report.scaled), "passed": bool(report.passed), "seconds": seconds,
		"by_domain": report.by_domain.duplicate(true)})
	while mock_history.size() > MOCK_HISTORY_MAX:
		mock_history.pop_front()
	last_mock_ids = ids.duplicate()

## Highest scaled score so far, or -1.
func best_mock_score() -> int:
	var best := -1
	for m in mock_history:
		best = max(best, int(m.scaled))
	return best

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
		"labs_done": labs_done,
		"mock_history": mock_history,
		"last_mock_ids": last_mock_ids,
		"srs": SRS.to_dict(),
	}

func from_dict(d: Dictionary) -> void:
	d = _migrate(d)
	attempts = d.get("attempts", {})
	streak_days = int(d.get("streak_days", 0))
	last_study_day = str(d.get("last_study_day", ""))
	total_minutes = float(d.get("total_minutes", 0.0))
	tutorials_done = d.get("tutorials_done", {})
	labs_done = d.get("labs_done", {})
	mock_history = d.get("mock_history", [])
	last_mock_ids = d.get("last_mock_ids", [])
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
	if v < 2:
		d["mock_history"] = []      # v2 adds mock exams
		d["last_mock_ids"] = []
	return d

static func _day_diff(a: String, b: String) -> int:
	var ta := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var tb := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round((tb - ta) / 86400.0))
