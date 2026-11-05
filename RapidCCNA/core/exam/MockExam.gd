class_name MockExam
extends RefCounted
## Builds and scores timed mock exams. Pure logic: the question bank and the
## blueprint domains come in as plain data, so tests can drive it directly.
##
## Selection: each domain gets seats in proportion to its blueprint weight
## (largest remainder, so the seats always add up to the exam length). Within a
## domain, questions are dealt round-robin across its subtopics so one big
## subtopic can't crowd out the rest. Questions from the previous mock are only
## used once fresh ones run out. CLI tasks are capped because they take longer.
##
## Scoring: Cisco doesn't publish its scaling, so the score is a linear map of
## the weighted fraction correct onto 300-1000 (825 to pass is about 75%).
## Unanswered questions count as wrong.

const SCALE_MIN := 300
const SCALE_MAX := 1000
const CLI_SHARE := 0.05       # at most 5% CLI tasks (min 1)

## Seats per domain id, proportional to weight; sums to n.
static func allocate(domains: Array, n: int) -> Dictionary:
	var total_w := 0.0
	for d in domains:
		total_w += float(d.weight)
	var seats := {}
	var rema: Array = []
	var used := 0
	for i in domains.size():
		var exact := n * float(domains[i].weight) / total_w if total_w > 0 else 0.0
		seats[domains[i].id] = int(floor(exact))
		used += seats[domains[i].id]
		rema.append([exact - floor(exact), i])
	# Largest remainder first; ties go to the earlier domain (blueprint order).
	rema.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for k in n - used:
		seats[domains[rema[k % rema.size()][1]].id] += 1
	return seats

static func max_cli(n: int) -> int:
	return max(1, int(floor(n * CLI_SHARE)))

## Question ids for one exam, in random order. `questions` is an array of
## question dicts; `avoid` holds ids to use only when nothing fresh is left.
## If a domain is short of questions, its spare seats go to the other domains.
static func build(questions: Array, domains: Array, n: int, rng: RandomNumberGenerator, avoid: Array = []) -> Array:
	var avoid_set := {}
	for id in avoid:
		avoid_set[id] = true
	var by_domain := {}
	for q in questions:
		var list: Array = by_domain.get(q.get("domain", ""), [])
		list.append(q)
		by_domain[q.get("domain", "")] = list
	var seats := allocate(domains, n)
	var cli_left := [max_cli(n)]
	var picked: Array = []
	var leftovers := {}
	var short := 0
	for d in domains:
		var queue := _deal(by_domain.get(d.id, []), rng, avoid_set)
		var take := _take(queue, int(seats[d.id]), cli_left)
		picked.append_array(take.ids)
		short += int(seats[d.id]) - take.ids.size()
		leftovers[d.id] = take.rest
	# Hand unfilled seats to domains with spare questions, heaviest weight first.
	var by_weight := domains.duplicate()
	by_weight.sort_custom(func(a, b): return float(a.weight) > float(b.weight))
	while short > 0:
		var gave := false
		for d in by_weight:
			if short == 0:
				break
			var take := _take(leftovers[d.id], 1, cli_left)
			leftovers[d.id] = take.rest
			if take.ids.size() > 0:
				picked.append_array(take.ids)
				short -= 1
				gave = true
		if not gave:
			break
	_shuffle(picked, rng)
	return picked

## Orders a domain's questions for dealing: subtopics in random order, one
## question from each in turn; fresh questions before avoided ones.
static func _deal(qs: Array, rng: RandomNumberGenerator, avoid_set: Dictionary) -> Array:
	var groups := {}
	for q in qs:
		var g: Array = groups.get(q.get("subtopic", ""), [])
		g.append(q)
		groups[q.get("subtopic", "")] = g
	var keys: Array = groups.keys()
	keys.sort()
	_shuffle(keys, rng)
	var fresh := []
	var stale := []
	for k in keys:
		var g: Array = groups[k]
		_shuffle(g, rng)
		fresh.append(g.filter(func(q): return not avoid_set.has(q.id)))
		stale.append(g.filter(func(q): return avoid_set.has(q.id)))
	return _round_robin(fresh) + _round_robin(stale)

static func _round_robin(groups: Array) -> Array:
	var out: Array = []
	var i := 0
	var more := true
	while more:
		more = false
		for g in groups:
			if i < g.size():
				out.append(g[i])
				more = true
		i += 1
	return out

## Takes up to `count` questions off the front of `queue`, skipping CLI tasks
## once the shared cap (`cli_left[0]`) is spent. Returns {ids, rest}.
static func _take(queue: Array, count: int, cli_left: Array) -> Dictionary:
	var ids: Array = []
	var rest: Array = []
	for q in queue:
		if ids.size() >= count:
			rest.append(q)
		elif q.get("type", "") == "cli_task":
			if cli_left[0] > 0:
				cli_left[0] -= 1
				ids.append(q.id)
		else:
			ids.append(q.id)
	return {"ids": ids, "rest": rest}

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

## Scores an exam. `ids` is every question on the exam; `results` the answered
## ones ({id, correct, response?}); `qdb` maps id -> question dict.
## Returns {total, answered, correct, fraction, scaled, passed, pass_scaled,
## by_domain: {id: {correct, total}}, missed: [{id, variant, response, answered, skipped}]}.
static func score(ids: Array, results: Array, qdb: Dictionary, domains: Array, pass_scaled: int) -> Dictionary:
	var by_id := {}
	for r in results:
		by_id[r.id] = r
	var by_domain := {}
	for d in domains:
		by_domain[d.id] = {"correct": 0, "total": 0}
	var correct := 0
	var missed: Array = []
	for id in ids:
		var dom: String = qdb.get(id, {}).get("domain", "")
		if not by_domain.has(dom):
			by_domain[dom] = {"correct": 0, "total": 0}
		by_domain[dom].total += 1
		var r: Dictionary = by_id.get(id, {})
		if r.get("correct", false):
			correct += 1
			by_domain[dom].correct += 1
		else:
			missed.append({"id": id, "variant": int(r.get("variant", 0)), "response": r.get("response"), "answered": not r.is_empty(), "skipped": r.get("skipped", false)})
	var fraction := weighted_fraction(by_domain, domains)
	var scaled := scale(fraction)
	return {"total": ids.size(), "answered": by_id.size(), "correct": correct, "fraction": fraction,
		"scaled": scaled, "passed": scaled >= pass_scaled, "pass_scaled": pass_scaled,
		"by_domain": by_domain, "missed": missed}

## Each domain's fraction correct weighted by its blueprint weight; domains with
## no questions on this exam are left out.
static func weighted_fraction(by_domain: Dictionary, domains: Array) -> float:
	var num := 0.0
	var den := 0.0
	for d in domains:
		var s: Dictionary = by_domain.get(d.id, {})
		if int(s.get("total", 0)) > 0:
			num += float(d.weight) * float(s.correct) / float(s.total)
			den += float(d.weight)
	return num / den if den > 0 else 0.0

static func scale(fraction: float) -> int:
	return SCALE_MIN + int(round((SCALE_MAX - SCALE_MIN) * clampf(fraction, 0.0, 1.0)))

## Exam length with an extra-time accommodation (percent), rounded up to a minute.
static func exam_minutes(minutes: int, extra_percent: int) -> int:
	return int(ceil(minutes * (100 + extra_percent) / 100.0))

## "1:59:07" / "4:05" countdown text.
@warning_ignore_start("integer_division")
static func clock(seconds: int) -> String:
	seconds = max(0, seconds)
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%d:%02d" % [m, s]
@warning_ignore_restore("integer_division")
