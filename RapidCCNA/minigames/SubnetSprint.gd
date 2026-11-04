extends DrillBase
## Subnet Sprint: given host/prefix, find network, broadcast, host range, mask or host count.

var item: Dictionary
var _answer: LineEdit

func present_item() -> void:
	item = SubnetGen.make_item(rng)
	var p := UI.label(prompt_box, item.prompt, "CodeBig")
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var qn := UI.label(prompt_box, item.question, "H2")
	qn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_answer = answer_input("e.g. 62" if item.kind == "hosts" else "e.g. 10.1.2.0")

func get_response() -> String: return _answer.text
func check(r: String) -> bool: return SubnetGen.check(item, r)
func explain() -> String: return SubnetGen.explain(item)
func hint() -> String: return SubnetGen.hint(item)
func card_id() -> String: return item.card_id
func correct_answer() -> String: return item.answer
func lock_inputs() -> void: _answer.editable = false
