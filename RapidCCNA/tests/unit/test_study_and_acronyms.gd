extends GutTest
## Acronym highlighting (Glossary + UI.rich), the Study button under each question and
## the simplified main menu.

func before_all():
	ContentDB.load_all(ContentDB.ROOT)

func after_each():
	await wait_process_frames(1)

# --- Glossary ---------------------------------------------------------------------------

func test_finds_whole_word_acronyms_plurals_and_longest_match():
	assert_eq(Glossary.find("OSPF elects a DR and a BDR on each VLAN"), ["OSPF", "DR", "BDR", "VLAN"])
	assert_eq(Glossary.find("Three VLANs and two APs"), ["VLAN", "AP"], "a plural s still counts")
	assert_eq(Glossary.find("IPsec, IPv6 and PoE+ beat IP and PoE"), ["IPsec", "IPv6", "PoE+", "IP", "PoE"])
	assert_eq(Glossary.find("CSMA/CA in the air"), ["CSMA/CA"])
	assert_eq(Glossary.find("macOS, ospf and SW1 aren't acronyms"), [], "case-sensitive, whole words only")

func test_bbcode_colours_acronyms_with_a_hint_and_escapes_brackets():
	var b := Glossary.bbcode("[110/20] via OSPF", Color("#ff0000"))
	assert_eq(b, "[lb]110/20[rb] via [color=#ff0000][hint=Open Shortest Path First]OSPF[/hint][/color]")
	assert_eq(Glossary.bbcode("no acronyms here", Color.WHITE), "no acronyms here")

func test_tooltip_lists_each_acronym_once():
	assert_eq(Glossary.tooltip("TCP or UDP? TCP."), "TCP: Transmission Control Protocol\nUDP: User Datagram Protocol")
	assert_eq(Glossary.tooltip("nothing"), "")

func test_every_term_has_a_usable_expansion():
	for t in Glossary.TERMS:
		var full: String = Glossary.TERMS[t]
		assert_false(full.strip_edges().is_empty(), t)
		assert_false(full.contains("[") or full.contains("]"), "%s: brackets would break the hint tag" % t)

func test_rich_text_shows_plain_text_and_colours_acronyms():
	var box := VBoxContainer.new()
	add_child_autofree(box)
	var r := UI.rich(box, "Hosts use DHCP [option 43].", "Body")
	assert_eq(r.get_parsed_text(), "Hosts use DHCP [option 43].")
	assert_string_contains(r.text, "[hint=Dynamic Host Configuration Protocol]DHCP[/hint]")
	assert_string_contains(r.text, "[color=#%s]" % Palette.current().acronym.to_html(false))

func test_choice_buttons_keep_their_text_and_explain_acronyms():
	var v: QuestionView = QuestionView.new().setup(ContentDB.questions["q.d3.route.003"])
	add_child_autofree(v)
	var with_acronym: Button = null
	for b in v._choice_buttons:
		if not Glossary.find(b.text).is_empty():
			with_acronym = b
	assert_not_null(with_acronym, "a choice names a routing protocol")
	assert_true(with_acronym.has_meta("rich_text"))
	assert_eq(with_acronym.tooltip_text, Glossary.tooltip(with_acronym.text))
	var right := int(v.q.answer)
	v._choice_buttons[right].button_pressed = true
	v._on_submit()
	var copy: RichTextLabel = v._choice_buttons[right].get_meta("rich_text", null)
	if copy:
		assert_string_contains(copy.get_parsed_text(), "(correct answer)", "the coloured copy follows the label")

# --- Question buttons and Study ---------------------------------------------------------

func _view(id: String, feedback: bool = true) -> QuestionView:
	var v: QuestionView = QuestionView.new().setup(ContentDB.questions[id], feedback)
	add_child_autofree(v)
	return v

func test_submit_idk_and_study_are_centred_in_one_row():
	var v := _view("q.d1.subnet.001")
	var row := v._submit.get_parent() as HBoxContainer
	assert_eq(row.alignment, BoxContainer.ALIGNMENT_CENTER)
	assert_eq(v._skip.get_parent(), row)
	assert_not_null(v._study)
	assert_eq(v._study.get_parent(), row)
	assert_eq(v._study.text, "Study")
	assert_false(v._notice.get_parent() == row, "the notice doesn't push the buttons off centre")

func test_no_study_button_in_mock_exams():
	var v := _view("q.d1.subnet.001", false)
	assert_null(v._study)

func test_every_question_can_open_its_lesson():
	for id in ContentDB.questions:
		assert_true(ContentDB.lessons.has(str(ContentDB.questions[id].get("lesson_ref", ""))), id)

func test_study_shows_the_lesson_and_returns_to_the_question_unchanged():
	var v := _view("q.d1.tcpudp.001")
	watch_signals(v)
	v._choice_buttons[0].button_pressed = true
	var o := v._open_study()
	await wait_process_frames(2)
	assert_true(StudyOverlay.is_open())
	assert_eq(o.lesson.id, "d1.tcp_udp")
	var shown := PackedStringArray()
	for r in o.find_children("*", "RichTextLabel", true, false):
		shown.append(r.get_parsed_text())
	for card in o.lesson.cards:
		assert_true(card.heading in shown, "card '%s' is shown" % card.heading)
	# Keys go to the overlay, not the question underneath.
	var two := InputEventKey.new()
	two.keycode = KEY_2
	two.pressed = true
	v._unhandled_key_input(two)
	assert_false(v._choice_buttons[1].button_pressed, "digits don't pick answers while studying")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	o._unhandled_key_input(esc)
	await wait_process_frames(2)
	assert_false(StudyOverlay.is_open())
	assert_true(v._choice_buttons[0].button_pressed, "the answer in progress is kept")
	assert_signal_not_emitted(v, "answered")
	assert_true(v._study.visible)

func test_study_stays_after_answering():
	var v := _view("q.d1.subnet.005")
	v._on_submit(true)
	assert_false(v._submit.visible)
	assert_false(v._skip.visible)
	assert_true(v._study.visible)

# --- Main menu --------------------------------------------------------------------------

func test_main_menu_has_no_chips_or_look_picker():
	var s: Control = load("res://ui/screens/MainMenu.tscn").instantiate()
	add_child_autofree(s)
	await wait_process_frames(1)
	var chips := s.find_children("*", "PanelContainer", true, false).filter(func(p): return p.theme_type_variation == "Chip")
	assert_eq(chips.size(), 0, "no feature chips")
	assert_eq(s.find_children("*", "OptionButton", true, false).size(), 0, "the look is picked in Settings")
	for l in s.find_children("*", "Label", true, false):
		assert_ne(l.text, "Look")
