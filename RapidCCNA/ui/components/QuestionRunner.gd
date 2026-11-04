class_name QuestionRunner
extends VBoxContainer
## Presents a list of question ids one at a time; emits done(results) at the end.

signal done(results: Array)

var feedback := true
var results: Array = []
var _ids: Array = []
var _i := -1
var _progress: Label
var _current: QuestionView

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress = UI.label(self, "", "Muted")

func start(question_ids: Array) -> void:
	_ids = question_ids.filter(func(id): return ContentDB.questions.has(id))
	_i = -1
	results = []
	_next()

func _next() -> void:
	if _current:
		_current.queue_free()
		_current = null
	_i += 1
	if _i >= _ids.size():
		done.emit(results)
		return
	_progress.text = "Question %d of %d" % [_i + 1, _ids.size()]
	_current = QuestionView.new().setup(ContentDB.questions[_ids[_i]], feedback)
	add_child(_current)
	_current.answered.connect(func(r): results.append(r))
	_current.continued.connect(_next, CONNECT_DEFERRED)
