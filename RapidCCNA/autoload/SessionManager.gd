extends Node
## Builds the Daily Session: due SRS reviews first, then the next unmastered unit.
## M0: produces the plan only; screens that run it arrive in M1.

const MAX_REVIEWS := 40

func build_daily_session(now: int = -1) -> Dictionary:
	var reviews := SRS.due_cards(now).slice(0, MAX_REVIEWS)
	return {
		"reviews": reviews,
		"next_unit": next_unit(),
	}

## First unmastered lesson in blueprint domain order, or {} if all mastered.
func next_unit() -> Dictionary:
	for d in ContentDB.domains:
		for l in ContentDB.lessons_for_domain(d.id):
			if not Progress.is_mastered(l.id):
				return l
	return {}
