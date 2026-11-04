extends Control
## Timed mock exam. Like the real exam: no feedback, no going back, and the
## score comes at the end on the 300-1000 scale. Time-out ends the exam;
## anything unanswered counts as wrong.

const WARN_SECONDS := 300

var _step: Dictionary
var _ids: Array = []
var _minutes := 0
var _start_ms := 0
var _deadline_ms := 0
var _running := false
var _finished := false
var _confirming := false
var _clock: Label
var _end_btn: Button
var _body: VBoxContainer
var _runner: QuestionRunner

func _ready() -> void:
	_step = SessionManager.current_step()
	_ids = _step.get("ids", [])
	_minutes = int(_step.get("minutes", 120))
	var v := UI.page(self)
	var head := UI.hbox(v, 16)
	var titles := UI.vbox(head, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles, "MOCK EXAM", "H3")
	UI.label(titles, str(_step.get("label", "Mock exam")), "H1", true)
	UI.label(titles, "%d questions  ·  %d minutes  ·  pass mark %d" % [_ids.size(), _minutes, int(_step.get("pass_scaled", 825))], "Muted", true)
	var timer := UI.vbox(head, 0)
	timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.label(timer, "TIME LEFT", "H3").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock = UI.label(timer, MockExam.clock(_minutes * 60), "H1")
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.custom_minimum_size.x = 170
	_end_btn = UI.button(head, "Exit", _on_end)
	_end_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_body = UI.card(v)
	_intro()

func _intro() -> void:
	UI.label(_body, "Before you start", "H2")
	for line in [
		"Questions are drawn from every exam area in proportion to the CCNA 200-301 weights, spread across their subtopics.",
		"You won't see whether an answer is right until the end, and you can't go back to an earlier question.",
		"\"Skip\" moves on and counts the question as wrong. Questions left when the time runs out count as wrong too.",
		"Your score uses Cisco's 300-1000 scale. %d passes, which is about %d%% correct." % [int(_step.get("pass_scaled", 825)),
			int(round(100.0 * (int(_step.get("pass_scaled", 825)) - MockExam.SCALE_MIN) / (MockExam.SCALE_MAX - MockExam.SCALE_MIN)))],
		"Every answer feeds your spaced-repetition schedule, and the report lists each miss with its explanation.",
	]:
		UI.label(_body, "•  " + line, "Body", true)
	var split := UI.vbox(_body, 4)
	UI.label(split, "THIS EXAM", "H3")
	var counts := {}
	for id in _ids:
		var dom: String = ContentDB.questions.get(id, {}).get("domain", "")
		counts[dom] = int(counts.get(dom, 0)) + 1
	for d in ContentDB.domains:
		UI.label(split, "%s: %d questions (%d%% of the exam)" % [d.name, int(counts.get(d.id, 0)), int(d.weight)], "Muted")
	var go := UI.button(_body, "Begin exam", _begin, true)
	go.disabled = _ids.is_empty()
	UI.focus_later(go)

func _begin() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_runner = QuestionRunner.new()
	_runner.feedback = false
	_body.add_child(_runner)
	_runner.done.connect(func(_r): _finish(false))
	_start_ms = Time.get_ticks_msec()
	_deadline_ms = _start_ms + _minutes * 60000
	_running = true
	_end_btn.text = "End exam"
	_runner.start(_ids)

func seconds_left() -> int:
	return int(ceil((_deadline_ms - Time.get_ticks_msec()) / 1000.0))

func _process(_delta: float) -> void:
	if not _running:
		return
	var left := seconds_left()
	_clock.text = MockExam.clock(left)
	if left <= WARN_SECONDS:
		_clock.add_theme_color_override("font_color", Palette.current().warn)
	if left <= 0:
		_finish(true)

func _on_end() -> void:
	if not _running:
		SessionManager.abort()
		return
	if not _confirming:
		_confirming = true
		_end_btn.text = "Confirm: end now"
		return
	_finish(false)

func _finish(timed_out: bool) -> void:
	if _finished:
		return
	_finished = true
	_running = false
	var results: Array = _runner.results.duplicate() if _runner else []
	var seconds: int = min(_minutes * 60, int((Time.get_ticks_msec() - _start_ms) / 1000.0))
	var report := MockExam.score(_ids, results, ContentDB.questions, ContentDB.domains, int(_step.get("pass_scaled", 825)))
	for r in results:
		SRS.grade(r.id, SessionManager.quality_for(r.correct, r.ms))
		var ref := str(ContentDB.questions.get(r.id, {}).get("lesson_ref", ""))
		if not ref.is_empty():
			Progress.record_attempt(ref, r.correct)
	var label := str(_step.get("label", "Mock exam"))
	Progress.record_mock(report, label, seconds, _ids)
	SessionManager.step_done({"title": label, "items": report.total, "correct": report.correct,
		"exam": report, "seconds": seconds, "timed_out": timed_out})
