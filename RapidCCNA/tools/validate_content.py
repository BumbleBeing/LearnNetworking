#!/usr/bin/env python3
"""Validate RapidCCNA content: schema, unique ids, answer keys, cross-references, coverage.

Usage: python3 tools/validate_content.py [content_dir] [--min-per-subtopic N] [--min-total N]
Exit code 0 = valid, 1 = errors found.
"""
import json
import sys
from pathlib import Path

QUESTION_TYPES = {"mcq_single", "mcq_multi", "drag_match", "drag_order",
                  "fill_in", "subnet_calc", "cli_task", "exhibit"}
LAB_CHECKS = {"hostname", "vlan_exists", "access_port", "trunk_port", "iface_ip", "iface_up", "iface_shutdown",
              "route_to", "static_route", "ping", "nat_iface", "nat_translates", "port_security",
              "acl_permits", "acl_decides", "stp_mode", "stp_root", "stp_role", "portfast", "etherchannel",
              "ospf_rid", "ospf_enabled", "ospf_passive", "ospf_neighbor", "cdp_run", "lldp_run", "cdp_iface",
              "lldp_iface", "iface_description", "discovers", "ssh_ready", "local_user", "ntp_server", "logging_host",
              "snmp_community", "dhcp_lease", "hsrp", "rsa_key", "ssh_version",
              "enable_secret", "password_encryption", "line_auth"}
QUESTION_REQUIRED = {"id", "domain", "subtopic", "type", "stem", "answer", "explanation"}
LESSON_REQUIRED = {"id", "domain", "subtopics", "title", "cards"}


def load(path, errors):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        errors.append(f"{path}: {e}")
        return None


def check_answer(q, where, errors):
    t, ans, choices = q["type"], q["answer"], q.get("choices")
    if t in ("mcq_single", "mcq_multi", "exhibit") and not isinstance(choices, list):
        errors.append(f"{where}: {t} needs a 'choices' list")
        return
    if t in ("mcq_single", "exhibit"):
        if not isinstance(ans, int) or not 0 <= ans < len(choices):
            errors.append(f"{where}: answer index out of range")
        if t == "exhibit" and not isinstance(q.get("exhibit"), str):
            errors.append(f"{where}: exhibit question needs an 'exhibit' string")
    elif t == "mcq_multi":
        if (not isinstance(ans, list) or len(ans) < 2 or len(set(ans)) != len(ans)
                or any(not isinstance(a, int) or not 0 <= a < len(choices) for a in ans)):
            errors.append(f"{where}: mcq_multi answer must be >=2 unique valid indices")
    elif t == "fill_in":
        accepted = ans if isinstance(ans, list) else [ans]
        if not accepted or any(not isinstance(a, str) or not a.strip() for a in accepted):
            errors.append(f"{where}: fill_in answer must be a string or list of strings")
    elif t == "drag_match":
        if not isinstance(ans, dict) or len(ans) < 2:
            errors.append(f"{where}: drag_match answer must map >=2 left items to right items")
        if not isinstance(q.get("distractors", []), list):
            errors.append(f"{where}: distractors must be a list")
    elif t == "drag_order":
        if not isinstance(ans, list) or len(ans) < 2 or len(set(ans)) != len(ans):
            errors.append(f"{where}: drag_order answer must be >=2 unique items in order")
    elif t == "subnet_calc":
        fields = q.get("fields")
        if not isinstance(fields, list) or not isinstance(ans, dict):
            errors.append(f"{where}: subnet_calc needs 'fields' list and 'answer' object")
        elif {f.get("key") for f in fields} != set(ans):
            errors.append(f"{where}: subnet_calc field keys must match answer keys")


def allocate(domains, n):
    """Seats per domain by weight, largest remainder (mirrors core/exam/MockExam.gd)."""
    total = sum(d.get("weight", 0) for d in domains) or 1
    exact = [n * d.get("weight", 0) / total for d in domains]
    seats = [int(x) for x in exact]
    order = sorted(range(len(domains)), key=lambda i: (-(exact[i] - seats[i]), i))
    for k in range(n - sum(seats)):
        seats[order[k % len(order)]] += 1
    return {d["id"]: s for d, s in zip(domains, seats)}


def validate(root: Path, min_per_subtopic: int = 0, min_total: int = 0):
    errors = []
    bp = load(root / "blueprint.json", errors)
    if not isinstance(bp, dict):
        return errors + ["blueprint.json missing or invalid"]
    domains = {d["id"]: d for d in bp.get("domains", [])}
    subtopics = {s["id"]: d_id for d_id, d in domains.items() for s in d.get("subtopics", [])}
    total_weight = sum(d.get("weight", 0) for d in domains.values())
    if total_weight != 100:
        errors.append(f"blueprint: domain weights sum to {total_weight}, expected 100")

    ids = {}
    lessons, questions = {}, {}

    def register(item_id, where):
        if item_id in ids:
            errors.append(f"{where}: duplicate id {item_id} (also in {ids[item_id]})")
        ids[item_id] = where

    for path in sorted((root / "lessons").rglob("*.json")):
        lesson = load(path, errors)
        if not isinstance(lesson, dict):
            continue
        missing = LESSON_REQUIRED - lesson.keys()
        if missing:
            errors.append(f"{path}: missing {sorted(missing)}")
            continue
        register(lesson["id"], str(path))
        lessons[lesson["id"]] = (lesson, path)
        if lesson["domain"] not in domains:
            errors.append(f"{path}: unknown domain {lesson['domain']}")
        for st in lesson["subtopics"]:
            if subtopics.get(st) != lesson["domain"]:
                errors.append(f"{path}: subtopic {st} not in domain {lesson['domain']}")
        if not 3 <= len(lesson["cards"]) <= 8:
            errors.append(f"{path}: lessons need 3-8 cards, has {len(lesson['cards'])}")

    for path in sorted((root / "questions").rglob("*.json")):
        arr = load(path, errors)
        if not isinstance(arr, list):
            errors.append(f"{path}: must be a JSON array")
            continue
        for i, q in enumerate(arr):
            where = f"{path}[{i}]"
            if not isinstance(q, dict):
                errors.append(f"{where}: not an object")
                continue
            missing = QUESTION_REQUIRED - q.keys()
            if missing:
                errors.append(f"{where}: missing {sorted(missing)}")
                continue
            where = f"{path}:{q['id']}"
            register(q["id"], where)
            questions[q["id"]] = q
            if q["type"] not in QUESTION_TYPES:
                errors.append(f"{where}: unknown type {q['type']}")
                continue
            if q["domain"] not in domains:
                errors.append(f"{where}: unknown domain {q['domain']}")
            if subtopics.get(q["subtopic"]) != q["domain"]:
                errors.append(f"{where}: subtopic {q['subtopic']} not in domain {q['domain']}")
            check_answer(q, where, errors)

    drills = {}
    drills_path = root / "drills" / "drills.json"
    if drills_path.exists():
        arr = load(drills_path, errors)
        for d in arr if isinstance(arr, list) else []:
            missing = {"id", "title", "domain", "unit", "script"} - d.keys()
            if missing:
                errors.append(f"{drills_path}: drill missing {sorted(missing)}")
                continue
            register(d["id"], str(drills_path))
            drills[d["id"]] = d
            script = root.parent / d["script"].replace("res://", "")
            if not script.exists():
                errors.append(f"drill {d['id']}: script {d['script']} not found")
            gen = d.get("generator")
            if gen and not (root.parent / gen.replace("res://", "")).exists():
                errors.append(f"drill {d['id']}: generator {gen} not found")
    for d in drills.values():
        if d["unit"] not in lessons:
            errors.append(f"drill {d['id']}: unit {d['unit']} does not exist")
    for lid, (lesson, path) in lessons.items():
        for did in lesson.get("drills", []):
            if did not in drills:
                errors.append(f"{path}: drill {did} does not exist")

    labs = {}
    for path in sorted((root / "labs").rglob("*.json")) if (root / "labs").exists() else []:
        lab = load(path, errors)
        if not isinstance(lab, dict):
            continue
        missing = {"id", "title", "devices", "tasks", "solution"} - lab.keys()
        if missing:
            errors.append(f"{path}: missing {sorted(missing)}")
            continue
        register(lab["id"], str(path))
        labs[lab["id"]] = lab
        names = {d.get("name") for d in lab["devices"]}
        if not any(d.get("editable") for d in lab["devices"]):
            errors.append(f"{path}: needs at least one editable device")
        for link in lab.get("links", []):
            if len(link) != 4 or link[0] not in names or link[2] not in names:
                errors.append(f"{path}: bad link {link}")
        for t in lab["tasks"]:
            if not t.get("text") or not t.get("checks"):
                errors.append(f"{path}: every task needs text and checks")
            for c in t.get("checks", []):
                if c.get("check") not in LAB_CHECKS:
                    errors.append(f"{path}: unknown check {c.get('check')}")
                if c.get("device") not in names:
                    errors.append(f"{path}: check on unknown device {c.get('device')}")
        for dev in lab["solution"]:
            if dev not in names:
                errors.append(f"{path}: solution for unknown device {dev}")
        if not lab.get("hidden") and lab.get("unit") not in lessons:
            errors.append(f"{path}: unit {lab.get('unit')} does not exist")
    for lid, (lesson, path) in lessons.items():
        for lab_id in lesson.get("labs", []):
            if lab_id not in labs:
                errors.append(f"{path}: lab {lab_id} does not exist")
    for q in questions.values():
        if q["type"] == "cli_task" and q.get("lab") not in labs:
            errors.append(f"question {q['id']}: lab {q.get('lab')} does not exist")

    for q in questions.values():
        ref = q.get("lesson_ref")
        if ref and ref not in lessons:
            errors.append(f"question {q['id']}: lesson_ref {ref} does not exist")
    for lid, (lesson, path) in lessons.items():
        for qid in lesson.get("recall", []):
            if qid not in questions:
                errors.append(f"{path}: recall question {qid} does not exist")

    mock = bp.get("mock", {})
    for kind, cfg in (("full", mock), ("quick", mock.get("quick", {}))):
        n = cfg.get("questions")
        if not isinstance(n, int) or n <= 0 or not isinstance(cfg.get("minutes"), int):
            errors.append(f"blueprint: mock {kind} needs integer questions and minutes")
            continue
        for d_id, seats in allocate(list(domains.values()), n).items():
            have = sum(1 for q in questions.values() if q["domain"] == d_id and q["type"] != "cli_task")
            if have < seats:
                errors.append(f"mock {kind}: domain {d_id} needs {seats} questions (not counting CLI tasks), has {have}")

    if min_total and len(questions) < min_total:
        errors.append(f"coverage: {len(questions)} questions, need at least {min_total}")

    if min_per_subtopic:
        counts = {st: 0 for st in subtopics}
        for q in questions.values():
            if q["subtopic"] in counts:
                counts[q["subtopic"]] += 1
        for st, n in counts.items():
            if n < min_per_subtopic:
                errors.append(f"coverage: subtopic {st} has {n} questions, need {min_per_subtopic}")
    return errors


def main(argv):
    args, opts = [], {"--min-per-subtopic": 0, "--min-total": 0}
    it = iter(argv[1:])
    for a in it:
        if a in opts:
            opts[a] = int(next(it))
        elif a.startswith("--"):
            print(f"unknown option {a}")
            return 2
        else:
            args.append(a)
    root = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "content"
    errors = validate(root, opts["--min-per-subtopic"], opts["--min-total"])
    for e in errors:
        print("ERROR", e)
    print(f"{'FAIL' if errors else 'OK'}: {len(errors)} error(s) in {root}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
