extends Node
## Spaced repetition scheduler (SM-2 variant). Cards are keyed by content id.
## Card state: {ease, interval_days, reps, lapses, due (unix), last (unix)}

const MIN_EASE := 1.3
const DEFAULT_EASE := 2.5
const DAY := 86400

var cards: Dictionary = {}

func reset() -> void:
	cards = {}

func has_card(id: String) -> bool:
	return cards.has(id)

func ensure_card(id: String, now: int = -1) -> Dictionary:
	if not cards.has(id):
		if now < 0:
			now = _now()
		cards[id] = {"ease": DEFAULT_EASE, "interval_days": 0.0, "reps": 0, "lapses": 0, "due": now, "last": 0}
	return cards[id]

## quality: 0-5 (SM-2). <3 is a failed recall.
func grade(id: String, quality: int, now: int = -1) -> Dictionary:
	if now < 0:
		now = _now()
	quality = clampi(quality, 0, 5)
	var c := ensure_card(id, now)
	if quality < 3:
		c.reps = 0
		c.lapses += 1
		c.interval_days = 0.0   # relearn: due again in 10 minutes
		c.due = now + 600
	else:
		c.reps += 1
		if c.reps == 1:
			c.interval_days = 1.0
		elif c.reps == 2:
			c.interval_days = 3.0
		else:
			c.interval_days = round(c.interval_days * c.ease)
		c.due = now + int(c.interval_days * DAY)
	c.ease = max(MIN_EASE, c.ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
	c.last = now
	return c

## Ids of cards due at `now`, most overdue first.
func due_cards(now: int = -1) -> Array:
	if now < 0:
		now = _now()
	var ids := cards.keys().filter(func(k): return cards[k].due <= now)
	ids.sort_custom(func(a, b): return cards[a].due < cards[b].due)
	return ids

func to_dict() -> Dictionary:
	return cards.duplicate(true)

func from_dict(d: Dictionary) -> void:
	cards = d.duplicate(true)

func _now() -> int:
	return int(Time.get_unix_time_from_system())
