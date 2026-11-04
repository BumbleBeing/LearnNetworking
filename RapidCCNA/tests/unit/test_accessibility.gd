extends GutTest
## M7 accessibility: settings, high contrast, reduced motion, extra exam time,
## non-colour answer marking, and the Settings screen at every text size.

var _saved: Dictionary

func before_each():
	_saved = Settings.to_dict()
	ContentDB.load_all(ContentDB.ROOT)

func after_each():
	Settings.from_dict(_saved)
	Settings.high_contrast = bool(_saved.high_contrast)
	Settings.reduce_motion = bool(_saved.reduce_motion)
	Settings.exam_extra_time = int(_saved.exam_extra_time)
	Settings.font_scale = float(_saved.font_scale)

func test_settings_round_trip_and_sanitise():
	Settings.from_dict({"reduce_motion": true, "exam_extra_time": 50, "font_scale": 1.3, "high_contrast": true})
	var d := Settings.to_dict()
	assert_true(d.reduce_motion)
	assert_eq(d.exam_extra_time, 50)
	assert_eq(d.font_scale, 1.3)
	Settings.from_dict({"exam_extra_time": 37, "font_scale": 9.0})
	assert_eq(Settings.exam_extra_time, 0, "only offered amounts are accepted")
	assert_eq(Settings.font_scale, Settings.FONT_SCALES[-1], "text size is clamped")

func test_current_look_applies_high_contrast_and_reduced_motion():
	Settings.ui_look = "noc"
	Settings.high_contrast = false
	Settings.reduce_motion = false
	assert_true(Palette.current().animate)
	Settings.reduce_motion = true
	assert_false(Palette.current().animate, "reduce motion stops the backdrop")
	assert_true(Palette.current().topology, "the network is still drawn, just still")
	Settings.high_contrast = true
	assert_eq(Palette.current().bg_bottom, Color.BLACK)
	Settings.ui_look = "daylight"
	assert_eq(Palette.current().bg_bottom, Color.WHITE, "light looks get a white high-contrast version")

func test_extra_time():
	assert_eq(SessionManager.exam_minutes(120, 0), 120)
	assert_eq(SessionManager.exam_minutes(120, 25), 150)
	assert_eq(SessionManager.exam_minutes(120, 50), 180)
	assert_eq(SessionManager.exam_minutes(36, 25), 45)
	assert_eq(SessionManager.exam_minutes(30, 25), 38, "rounded up to a whole minute")
	Settings.exam_extra_time = 50
	var step := SessionManager.mock_step("quick", 1)
	assert_eq(step.minutes, 54)
	assert_eq(step.extra_time, 50)
	Settings.exam_extra_time = 0
	assert_eq(SessionManager.mock_step("full", 1).minutes, 120)

func test_answered_choices_are_labelled_not_just_coloured():
	var v: QuestionView = QuestionView.new().setup(ContentDB.questions["q.d1.subnet.001"])
	add_child_autofree(v)
	var right := int(v.q.answer)
	var wrong := (right + 1) % v._choice_buttons.size()
	v._choice_buttons[wrong].button_pressed = true
	v._on_submit()
	assert_string_contains(v._choice_buttons[right].text, "(correct answer)")
	assert_string_contains(v._choice_buttons[wrong].text, "(your answer)")
	for i in v._choice_buttons.size():
		if i != right and i != wrong:
			assert_false(v._choice_buttons[i].text.contains("("), "untouched choices stay plain")

func test_drill_choices_are_labelled_too():
	var d: DrillBase = load("res://minigames/GenDrill.gd").new()
	d.setup({"guided": false, "count": 1, "seed": 3, "generator": "res://core/net/RouteGen.gd"})
	add_child_autofree(d)
	var right := d.correct_choice()
	d.choose((right + 1) % d._choices.size())
	assert_string_contains(d._choices[right].text, "(correct answer)")
	assert_string_contains(d._choices[(right + 1) % d._choices.size()].text, "(your answer)")

func test_settings_screen_builds_at_every_text_size_and_contrast():
	for hc in [false, true]:
		for scale in Settings.FONT_SCALES:
			Settings.high_contrast = hc
			Settings.font_scale = scale
			var scene: Control = load("res://ui/screens/SettingsScreen.tscn").instantiate()
			add_child_autofree(scene)
			assert_eq(scene.theme.get_font_size("font_size", "H1"), int(round(40 * scale)), "scale %s" % scale)
			scene.queue_free()

func test_small_windows_get_a_smaller_canvas_but_never_below_the_minimum():
	assert_eq(Display.logical_base(Vector2(1920, 1080)), Display.BASE, "big screens keep the designed canvas")
	assert_eq(Display.logical_base(Vector2(1280, 720)), Display.BASE)
	assert_eq(Display.logical_base(Vector2(1024, 600)), Vector2i(1024, 600), "1:1 on a small laptop or tablet")
	assert_eq(Display.logical_base(Vector2(750, 342)), Display.MIN_SIZE, "phone landscape is clamped to the minimum")
	assert_almost_eq(Display.ui_scale(Vector2(750, 342)), 750.0 / 960.0, 0.001)
	assert_gt(Display.ui_scale(Vector2(750, 342)) * 18, 13.5, "body text stays about 14 px on a phone in landscape")
	assert_almost_eq(Display.ui_scale(Vector2(1920, 1080)), 1.5, 0.001)

func test_rotate_prompt_only_for_narrow_portrait():
	assert_true(Display.wants_rotation(Vector2(390, 664)), "phone portrait")
	assert_false(Display.wants_rotation(Vector2(750, 342)), "phone landscape")
	assert_false(Display.wants_rotation(Vector2(820, 1180)), "tablet portrait is wide enough")
	assert_false(Display.wants_rotation(Vector2(1280, 720)))
