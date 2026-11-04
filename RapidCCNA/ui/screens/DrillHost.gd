extends Control
## Hosts a mini-game (DrillBase subclass) for the current drill step and records results.

var step: Dictionary
var def: Dictionary

func _ready() -> void:
	step = SessionManager.current_step()
	def = ContentDB.drills.get(step.get("drill", ""), {})
	var v := UI.page(self)
	var mode := "Guided" if step.get("guided", true) else "Unguided"
	ScreenHeader.build(v, "Drill  ·  " + mode, def.get("title", "Drill"), def.get("description", ""))
	if def.is_empty() or not ResourceLoader.exists(def.get("script", "")):
		UI.label(v, "Drill not found.", "Muted")
		return
	var drill: DrillBase = load(def.script).new()
	drill.setup({"guided": step.get("guided", true), "count": step.get("count", 10),
		"target_seconds": def.get("target_seconds", 30), "generator": def.get("generator", "")})
	drill.finished.connect(_on_finished)
	v.add_child(drill)

func _on_finished(summary: Dictionary) -> void:
	SessionManager.grade_round(summary.results)
	if not step.get("guided", true):
		for r in summary.results:
			Progress.record_attempt(def.unit, r.correct)
	var s := summary.duplicate()
	s.erase("results")
	s["title"] = def.title
	SessionManager.step_done(s)
