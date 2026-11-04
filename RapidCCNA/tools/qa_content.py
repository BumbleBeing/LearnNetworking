#!/usr/bin/env python3
"""Content QA for RapidCCNA questions: problems the schema validator can't see.

Checks that make a question unfair or confusing (errors, fail CI):
  - choose-count: an mcq_multi stem's "(Choose N)" must match its answer count,
    and single-answer stems mustn't say "choose two"
  - exhibit-ref: stems that mention "the exhibit" need one, and exhibit
    questions should refer to it
  - dup-choice: two identical choices in one question
  - near-dup: two questions with almost the same stem and the same answer
  - lesson-subtopic: the question's subtopic isn't covered by its lesson_ref
  - recall-lesson: a lesson's recall question belongs to another lesson
  - positional: the explanation refers to a choice by position, which breaks
    if choices are reordered
  - iface-variants: a fill-in answer with an interface name accepts only one
    spelling of it (g0/1 vs gigabitethernet0/1)
  - short-explanation: explanations under 40 characters teach nothing

Statistics that reveal answer-key giveaways (warnings, with CI thresholds):
  - when one choice is clearly the longest (20% longer than every other), how
    often it is the right answer. "Pick the long one" should be no better
    than chance (about 1 in 4); the limit is 40%
  - how evenly correct answers are spread over positions

Usage: python3 tools/qa_content.py [content_dir] [--strict]
  --strict also fails if the longest-answer rate or the position spread
  is outside the thresholds below.
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

CLEAR = 1.2               # a choice "stands out" when it is at least 20% longer than every other choice
LONGEST_MAX = 0.40        # when one choice stands out by length, it may be the key at most 40% of the time
POSITION_MAX_SHARE = 0.35  # no single position holds more than 35% of correct answers (4 choices)
NEAR_DUP = 0.85            # stem token-set similarity that counts as a near duplicate
WORDS = {"two": 2, "three": 3, "four": 4, "2": 2, "3": 3, "4": 4}
IFACE = re.compile(r"\b(g|gi|gig|gigabitethernet|fa|fastethernet|f)(\d+/\d+(?:/\d+)?)\b", re.I)


def tokens(text):
    return set(re.findall(r"[a-z0-9./:]+", text.lower()))


def jaccard(a, b):
    return len(a & b) / len(a | b) if a and b else 0.0


def load(root):
    questions, lessons = [], {}
    for p in sorted((root / "questions").rglob("*.json")):
        questions += json.loads(p.read_text(encoding="utf-8"))
    for p in sorted((root / "lessons").rglob("*.json")):
        lesson = json.loads(p.read_text(encoding="utf-8"))
        lessons[lesson["id"]] = lesson
    return questions, lessons


def check(questions, lessons):
    errors = []

    def err(q, kind, msg):
        errors.append((q["id"], kind, msg))

    by_id = {q["id"]: q for q in questions}
    for q in questions:
        stem, t = q["stem"], q["type"]
        m = re.search(r"\bchoose (two|three|four|2|3|4)\b", stem, re.I)
        if t == "mcq_multi":
            n = len(q["answer"])
            if m and WORDS.get(m.group(1).lower()) != n:
                err(q, "choose-count", f"stem says choose {m.group(1)} but {n} answers are keyed")
            if not m and not re.search(r"\b(two|three|four)\b", stem, re.I):
                err(q, "choose-count", f"multi-select stem doesn't say how many to pick ({n})")
        elif m:
            err(q, "choose-count", f"single-answer question says 'choose {m.group(1)}'")
        mentions = re.search(r"\bexhibit\b", stem, re.I)
        if mentions and "exhibit" not in q:
            err(q, "exhibit-ref", "stem mentions an exhibit but there is none")
        if t == "exhibit" and not mentions:
            err(q, "exhibit-ref", "exhibit question doesn't refer to the exhibit")
        choices = q.get("choices", [])
        if len({c.strip() for c in choices}) != len(choices):   # case matters: True vs true
            err(q, "dup-choice", "two choices are identical")
        ref = q.get("lesson_ref")
        if ref in lessons and q["subtopic"] not in lessons[ref]["subtopics"]:
            err(q, "lesson-subtopic", f"subtopic {q['subtopic']} isn't covered by {ref} {lessons[ref]['subtopics']}")
        if re.search(r"\b(first|second|third|fourth|last) (option|choice|answer)\b", q["explanation"], re.I):
            err(q, "positional", "explanation refers to a choice by position")
        if len(q["explanation"].strip()) < 40:
            err(q, "short-explanation", f"explanation is only {len(q['explanation'].strip())} characters")
        if t == "fill_in":
            accepted = q["answer"] if isinstance(q["answer"], list) else [q["answer"]]
            forms = {m.group(1).lower() for a in accepted for m in IFACE.finditer(a)}
            if forms and len(forms) < 2:
                err(q, "iface-variants", f"accepts only '{forms.pop()}' interface spelling")

    for lid, lesson in lessons.items():
        for qid in lesson.get("recall", []):
            if qid in by_id and by_id[qid].get("lesson_ref") != lid:
                err(by_id[qid], "recall-lesson", f"recall question of {lid} belongs to {by_id[qid].get('lesson_ref')}")

    keyed = defaultdict(list)
    for q in questions:
        keyed[(q["domain"], q["type"])].append((q, tokens(q["stem"])))
    for group in keyed.values():
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                (a, ta), (b, tb) = group[i], group[j]
                if jaccard(ta, tb) >= NEAR_DUP and json.dumps(a["answer"]) == json.dumps(b["answer"]) \
                        and a.get("exhibit") == b.get("exhibit"):
                    err(b, "near-dup", f"almost the same as {a['id']}")
    return errors


def clearly_longest(choices):
    """Index of the choice at least CLEAR times longer than every other one, or None."""
    for i, c in enumerate(choices):
        if all(len(c) >= CLEAR * len(o) for j, o in enumerate(choices) if j != i):
            return i
    return None


def stats(questions):
    single = [q for q in questions if q["type"] in ("mcq_single", "exhibit")]
    standouts = [(q, clearly_longest(q["choices"])) for q in single]
    standouts = [(q, i) for q, i in standouts if i is not None]
    longest = [q for q, i in standouts if i == q["answer"]]
    positions = Counter(q["answer"] for q in single if len(q["choices"]) == 4)
    total4 = sum(positions.values())
    return {
        "single": len(single),
        "standouts": len(standouts),
        "longest": longest,
        "longest_rate": len(longest) / len(standouts) if standouts else 0.0,
        "positions": dict(sorted(positions.items())),
        "max_position_share": max(positions.values()) / total4 if total4 else 0.0,
    }


def main(argv):
    strict = "--strict" in argv
    args = [a for a in argv[1:] if not a.startswith("--")]
    root = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "content"
    questions, lessons = load(root)
    errors = check(questions, lessons)
    for qid, kind, msg in sorted(errors, key=lambda e: (e[1], e[0])):
        print(f"ERROR {kind:18} {qid}: {msg}")
    s = stats(questions)
    print(f"{len(questions)} questions, {s['single']} single-answer")
    print(f"one choice is clearly longest in {s['standouts']} questions; it's the right answer in {len(s['longest'])} "
          f"({s['longest_rate']:.0%}; chance is about 25%, limit {LONGEST_MAX:.0%})")
    print(f"correct positions (4-choice): {s['positions']}, largest share {s['max_position_share']:.0%} (limit {POSITION_MAX_SHARE:.0%})")
    failed = bool(errors)
    if strict and s["longest_rate"] > LONGEST_MAX:
        print("FAIL longest-answer rate is too high: the longest choice gives the answer away")
        failed = True
    if strict and s["max_position_share"] > POSITION_MAX_SHARE:
        print("FAIL correct answers cluster in one position")
        failed = True
    print("FAIL" if failed else "OK", f"{len(errors)} error(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
