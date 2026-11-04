extends Control
## Lesson cards (Back/Next, arrow keys) followed by a quick recall check.

var lesson: Dictionary = {}
var _i := 0
var _body: VBoxContainer
var _nav: HBoxContainer
var _back: Button
var _next: Button
var _dots: HBoxContainer
var _look: Dictionary
var _recalling := false

func _ready() -> void:
	_look = Palette.current()
	var step := SessionManager.current_step()
	lesson = ContentDB.lessons.get(step.get("lesson", ""), {})
	var v := UI.page(self)
	var d := ContentDB.get_domain(lesson.get("domain", ""))
	ScreenHeader.build(v, "Tutorial  ·  " + d.get("name", ""), lesson.get("title", "Missing lesson"),
		"About %d minutes, then a %d-question recall check" % [int(lesson.get("minutes", 5)), lesson.get("recall", []).size()])
	_body = UI.card(v)
	_body.custom_minimum_size.y = 300
	_nav = UI.hbox(v, 12)
	_back = UI.button(_nav, "Back", _go.bind(-1))
	_dots = UI.hbox(_nav, 8)
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next = UI.button(_nav, "Next", _go.bind(1), true)
	if lesson.is_empty():
		SessionManager.step_done({"items": 0, "correct": 0})
		return
	_show_card()

func _unhandled_key_input(event: InputEvent) -> void:
	if _recalling or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_RIGHT:
		_go(1)
	elif event.keycode == KEY_LEFT:
		_go(-1)

func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

func _show_card() -> void:
	var cards: Array = lesson.cards
	var card: Dictionary = cards[_i]
	_clear_body()
	UI.label(_body, "Card %d of %d" % [_i + 1, cards.size()], "H3")
	UI.label(_body, card.get("heading", ""), "H2", true)
	UI.label(_body, card.get("body", ""), "Body", true)
	if card.has("example"):
		var ex := PanelContainer.new()
		ex.theme_type_variation = "Exhibit"
		_body.add_child(ex)
		UI.label(ex, str(card.example), "Code")
	for c in _dots.get_children():
		_dots.remove_child(c)
		c.queue_free()
	for k in cards.size():
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(28 if k == _i else 10, 10)
		dot.add_theme_stylebox_override("panel", ThemeFactory.box(_look.accent if k <= _i else _look.track, Color.TRANSPARENT, 999, 0, 0, 0))
		_dots.add_child(dot)
	_back.disabled = _i == 0
	_next.text = "Start recall check" if _i == cards.size() - 1 else "Next"
	_next.grab_focus()

func _go(d: int) -> void:
	var n: int = lesson.cards.size()
	if d > 0 and _i == n - 1:
		_start_recall()
		return
	_i = clampi(_i + d, 0, n - 1)
	_show_card()

func _start_recall() -> void:
	_recalling = true
	_nav.visible = false
	_clear_body()
	UI.label(_body, "Recall check", "H3")
	var runner := QuestionRunner.new()
	_body.add_child(runner)
	runner.done.connect(_on_recall_done)
	runner.start(lesson.get("recall", []))

func _on_recall_done(results: Array) -> void:
	for r in results:
		SRS.grade(r.id, SessionManager.quality_for(r.correct, r.ms))
	Progress.mark_tutorial_done(lesson.id)
	SessionManager.step_done({"title": lesson.title, "items": results.size(),
		"correct": results.filter(func(r): return r.correct).size()})
