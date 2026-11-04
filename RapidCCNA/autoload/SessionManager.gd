extends Node
## Plans and runs study sessions. A session is a list of steps; each screen
## calls step_done() when finished and SessionManager moves to the next scene.
##
## Step kinds:
##   {kind:"review",   ids:[question ids]}
##   {kind:"tutorial", lesson:id}
##   {kind:"drill",    drill:id, guided:bool, count:int, unit:id}

const MAX_REVIEWS := 20
const REVIEW_DRILL_COUNT := 5
const UNIT_DRILL_COUNT := 10
const GUIDED_UNTIL := 10          # guided rounds until this many unguided attempts
const FAST_MS := 15000

const SCENES := {
	"review": "res://ui/screens/Review.tscn",
	"tutorial": "res://ui/screens/Tutorial.tscn",
	"drill": "res://ui/screens/DrillHost.tscn",
	"summary": "res://ui/screens/Summary.tscn",
	"dashboard": "res://ui/screens/Dashboard.tscn",
}

var steps: Array = []
var index := -1
var results: Array = []
var title := ""
var _start_ms := 0

## Kept for the dashboard header.
func build_daily_session(now: int = -1) -> Dictionary:
	var reviews := SRS.due_cards(now).filter(func(id): return ContentDB.questions.has(id))
	return {"reviews": reviews.slice(0, MAX_REVIEWS), "next_unit": next_unit(), "steps": plan_steps(now)}

## First unmastered lesson in blueprint domain order, or {} if all mastered.
func next_unit() -> Dictionary:
	for d in ContentDB.domains:
		for l in ContentDB.lessons_for_domain(d.id):
			if not Progress.is_mastered(l.id):
				return l
	return {}

func plan_steps(now: int = -1) -> Array:
	var out: Array = []
	var due := SRS.due_cards(now)
	var q_ids := due.filter(func(id): return ContentDB.questions.has(id)).slice(0, MAX_REVIEWS)
	if q_ids.size() > 0:
		out.append({"kind": "review", "ids": q_ids})
	var review_drills: Array = []
	for id in due:
		var parts: PackedStringArray = id.split(".")
		if parts.size() >= 2 and parts[0] == "gen" and ContentDB.drills.has(parts[1]) and not parts[1] in review_drills:
			review_drills.append(parts[1])
	for d in review_drills:
		out.append(drill_step(d, false, REVIEW_DRILL_COUNT))
	var unit := next_unit()
	if not unit.is_empty():
		if not Progress.is_tutorial_done(unit.id):
			out.append({"kind": "tutorial", "lesson": unit.id})
		for d in unit.get("drills", []):
			if not ContentDB.drills.has(d):
				continue
			if Progress.attempt_count(unit.id) < GUIDED_UNTIL:
				out.append(drill_step(d, true, UNIT_DRILL_COUNT))
			out.append(drill_step(d, false, UNIT_DRILL_COUNT))
	return out

func drill_step(drill_id: String, guided: bool, count: int) -> Dictionary:
	return {"kind": "drill", "drill": drill_id, "guided": guided, "count": count,
		"unit": ContentDB.drills[drill_id].get("unit", "")}

## Human-readable one-liner for a step.
func describe(step: Dictionary) -> String:
	match step.kind:
		"review":
			return "Review %d due question(s)" % step.ids.size()
		"tutorial":
			return "Tutorial: %s" % ContentDB.lessons.get(step.lesson, {}).get("title", step.lesson)
		"drill":
			return "%s (%s, %d items)" % [ContentDB.drills[step.drill].title, "guided" if step.guided else "unguided", step.count]
	return step.kind

# --- running ---

func start(new_steps: Array, session_title: String) -> void:
	steps = new_steps
	title = session_title
	index = -1
	results = []
	_start_ms = Time.get_ticks_msec()
	advance()

func start_daily() -> void:
	start(plan_steps(), "Daily session")

func start_drill(drill_id: String, guided: bool) -> void:
	start([drill_step(drill_id, guided, UNIT_DRILL_COUNT)], "Practice: " + ContentDB.drills[drill_id].title)

func current_step() -> Dictionary:
	return steps[index] if index >= 0 and index < steps.size() else {}

func step_done(summary: Dictionary) -> void:
	var r := current_step().duplicate()
	r.merge(summary, true)
	results.append(r)
	Progress.save_game()
	advance()

func advance() -> void:
	index += 1
	if index >= steps.size():
		_finish()
	else:
		_go(SCENES[steps[index].kind])

## Leave mid-session; keeps what was completed.
func abort() -> void:
	if results.is_empty():
		steps = []
		_go(SCENES.dashboard)
	else:
		_finish()

func _finish() -> void:
	Progress.total_minutes += (Time.get_ticks_msec() - _start_ms) / 60000.0
	Progress.mark_studied()
	Progress.save_game()
	_go(SCENES.summary)

func _go(path: String) -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(path)

# --- grading helpers shared by screens ---

## SM-2 quality for a single answer.
func quality_for(correct: bool, ms: int) -> int:
	if not correct:
		return 1
	return 5 if ms < FAST_MS else 4

## Grade generated-drill cards once per round (not per item) so a 10-item round
## doesn't inflate intervals. Quality comes from per-card accuracy.
func grade_round(round_results: Array) -> void:
	var by_card := {}
	for r in round_results:
		var c: Array = by_card.get(r.card_id, [0, 0])
		c[0] += 1 if r.correct else 0
		c[1] += 1
		by_card[r.card_id] = c
	for id in by_card:
		var acc: float = float(by_card[id][0]) / by_card[id][1]
		var q := 5 if acc >= 1.0 else 4 if acc >= 0.8 else 3 if acc >= 0.6 else 1
		SRS.grade(id, q)
