#!/usr/bin/env python3
"""Fail if lesson or question text uses an acronym that core/Glossary.gd doesn't explain.

The game colours every glossary acronym and shows its full name on hover, so a new
acronym in the content needs a glossary entry too. A word counts as an acronym when it
has two or more capital letters and no lower-case ones (OSPF, WPA2), plus an optional
plural s. Device names, CLI keywords and hex groups are allowed below.

Usage: python3 tools/check_acronyms.py [project_dir]
"""
import json
import re
import sys
from pathlib import Path

# Not acronyms: device and object names, HTTP methods, IOS output words, hex groups.
ALLOWED = {
    "SW1", "SW2", "SW3", "PC1", "PC2", "R1", "R2", "R3", "HR", "SALES", "ENGINEERING", "BLOCK", "NETMON",
    "GET", "PUT", "POST", "PATCH", "DELETE", "OK", "AND", "TWO", "ONLY",
    "FULL", "DOWN", "BROADCAST", "EXSTART", "EXCHANGE", "LINK", "UPDOWN", "NATIVE", "MISMATCH", "CONFIG",
    "SEC", "DEBUG", "IPACCESSLOGP", "SYS", "SU", "EXEC", "XE", "CL", "AAAA",
    "OFFER", "DHCPOFFER", "DHCPACK", "DISCOVER", "REQUEST", "ACK",
    "CA", "CD",   # only in CSMA/CA and CSMA/CD, which the glossary covers as one term
}
HEX = re.compile(r"^[0-9A-F]{2,4}$|^[0-9A-F]*X+[0-9A-FY]*$")
WORD = re.compile(r"(?<![A-Za-z0-9])([A-Z][A-Z0-9]*[A-Z][A-Z0-9]*)s?(?![A-Za-z0-9])")


def glossary(root):
    src = (root / "core" / "Glossary.gd").read_text(encoding="utf-8")
    return set(re.findall(r'^\t"([^"]+)": "', src, re.M))


def texts(root):
    for p in sorted((root / "content" / "lessons").rglob("*.json")):
        lesson = json.loads(p.read_text(encoding="utf-8"))
        yield lesson["id"], lesson["title"]
        for c in lesson["cards"]:
            yield lesson["id"], c.get("heading", "")
            yield lesson["id"], c.get("body", "")
    for p in sorted((root / "content" / "questions").glob("*.json")):
        for q in json.loads(p.read_text(encoding="utf-8")):
            for t in [q.get("stem", ""), q.get("explanation", "")] + [str(c) for c in q.get("choices", [])]:
                yield q["id"], t


def main(argv):
    root = Path(argv[1] if len(argv) > 1 else Path(__file__).resolve().parent.parent)
    terms = glossary(root)
    missing = {}
    for where, text in texts(root):
        for m in WORD.finditer(text):
            w = m.group(1)
            if w in terms or w in ALLOWED or HEX.match(w) or any(t.startswith(w) and not t[len(w):].isalnum() for t in terms):
                continue
            missing.setdefault(w, where)
    for w, where in sorted(missing.items()):
        print(f"{where}: '{w}' isn't in core/Glossary.gd (add it, or to ALLOWED in this script if it isn't an acronym)")
    print(f"{len(terms)} glossary terms, {len(missing)} missing")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
