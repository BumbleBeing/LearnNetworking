#!/usr/bin/env python3
"""Unit tests for tools/qa_content.py. Run: python3 tools/test_qa_content.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import qa_content as qa  # noqa: E402

LESSONS = {"d1.l": {"id": "d1.l", "subtopics": ["1.1"], "recall": []}}


def q(id="q1", type="mcq_single", stem="Which is right?", choices=None, answer=0, **kw):
    base = {"id": id, "domain": "d1", "subtopic": "1.1", "type": type, "stem": stem,
            "choices": choices if choices is not None else ["alpha", "bravo", "charl", "delta"],
            "answer": answer, "explanation": "A long enough explanation of why alpha is right.", "lesson_ref": "d1.l"}
    base.update(kw)
    return base


def kinds(questions, lessons=LESSONS):
    return sorted({k for _, k, _ in qa.check(questions, lessons)})


class Checks(unittest.TestCase):
    def test_clean_question_passes(self):
        self.assertEqual(kinds([q()]), [])

    def test_choose_count(self):
        self.assertEqual(kinds([q(type="mcq_multi", stem="Which two? (Choose two.)", answer=[0, 1, 2])]), ["choose-count"])
        self.assertEqual(kinds([q(type="mcq_multi", stem="Which are right?", answer=[0, 1])]), ["choose-count"])
        self.assertEqual(kinds([q(stem="Which is right? (Choose two.)")]), ["choose-count"])
        self.assertEqual(kinds([q(stem="How does a router choose a route?")]), [], "'choose a' isn't a count")

    def test_exhibit_reference(self):
        self.assertEqual(kinds([q(stem="Based on the exhibit, which is right?")]), ["exhibit-ref"])
        self.assertEqual(kinds([q(type="exhibit", exhibit="R1#show run")]), ["exhibit-ref"])
        self.assertEqual(kinds([q(type="exhibit", exhibit="x", stem="Based on the exhibit, which?")]), [])

    def test_duplicate_choices_are_case_sensitive(self):
        self.assertEqual(kinds([q(choices=["a", "a", "b", "c"])]), ["dup-choice"])
        self.assertEqual(kinds([q(choices=["True", "true", "b", "c"])]), [], "JSON booleans differ by case on purpose")

    def test_near_duplicates(self):
        a = q(id="q1", stem="What is the default administrative distance of OSPF routes?")
        b = q(id="q2", stem="What is the default administrative distance of OSPF routes ?")
        self.assertEqual(kinds([a, b]), ["near-dup"])
        c = q(id="q3", stem="What is the default administrative distance of OSPF routes?", answer=1)
        self.assertEqual(kinds([a, c]), [], "same stem, different answer: a different question (e.g. other exhibit)")

    def test_lesson_and_recall_links(self):
        self.assertEqual(kinds([q(subtopic="1.2")]), ["lesson-subtopic"])
        lessons = {"d1.l": {"id": "d1.l", "subtopics": ["1.1"], "recall": ["q1"]},
                   "d1.m": {"id": "d1.m", "subtopics": ["1.1"], "recall": []}}
        self.assertEqual(kinds([q(lesson_ref="d1.m")], lessons), ["recall-lesson"])

    def test_positional_and_short_explanations(self):
        self.assertEqual(kinds([q(explanation="The second option is wrong because it uses a wildcard.")]), ["positional"])
        self.assertEqual(kinds([q(explanation="Because.")]), ["short-explanation"])

    def test_fill_in_interface_spellings(self):
        one = q(type="fill_in", choices=None, answer=["ip ospf 1 area 0 g0/1"])
        one.pop("choices")
        self.assertEqual(kinds([one]), ["iface-variants"])
        two = dict(one, answer=["interface g0/1", "interface gigabitethernet0/1"])
        self.assertEqual(kinds([two]), [])


class Stats(unittest.TestCase):
    def test_stand_out_rate(self):
        giveaway = q(choices=["The long, carefully qualified right answer", "short", "brief", "tiny"], answer=0)
        decoy = q(id="q2", choices=["right", "A long and detailed but wrong answer", "brief", "tiny"], answer=0)
        even = q(id="q3", choices=["right one", "wrong one", "wrong two", "wrong thr"], answer=0)
        s = qa.stats([giveaway, decoy, even])
        self.assertEqual(s["standouts"], 2, "the even question has no stand-out choice")
        self.assertEqual(len(s["longest"]), 1)
        self.assertAlmostEqual(s["longest_rate"], 0.5)

    def test_position_share(self):
        s = qa.stats([q(id=f"q{i}", answer=0) for i in range(3)] + [q(id="q9", answer=2)])
        self.assertEqual(s["positions"], {0: 3, 2: 1})
        self.assertAlmostEqual(s["max_position_share"], 0.75)

    def test_shipped_content_passes_strict(self):
        root = Path(__file__).resolve().parent.parent / "content"
        self.assertEqual(qa.main(["qa", str(root), "--strict"]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=1)
