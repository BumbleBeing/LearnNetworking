#!/usr/bin/env python3
"""Print the AT-SPI accessibility tree of the running app: what Orca (Linux) reads.

Each line is a role and the name a screen reader announces. "<not registered>" marks a
control the app lists but never made available to screen readers.
Needs pyatspi (Ubuntu: python3-pyatspi; it may need the distribution's python, e.g. python3.12).
Usage: a11y_dump.py [seconds_to_wait_for_the_app]
"""
import sys
import time

import pyatspi


def child(node, i):
    # Objects can be re-registered while we walk; retry before calling one missing.
    for _ in range(6):
        try:
            c = node.getChildAtIndex(i)
            c.getRoleName()
            return c
        except Exception:
            time.sleep(0.3)
    return None


def walk(node, depth, out):
    out.append("%s%s %r" % ("  " * depth, node.getRoleName(), node.name or ""))
    for i in range(node.childCount):
        c = child(node, i)
        if c is None:
            out.append("  " * (depth + 1) + "<not registered>")
        else:
            walk(c, depth + 1, out)


def main(argv):
    deadline = time.time() + float(argv[1] if len(argv) > 1 else 20)
    while time.time() < deadline:
        desk = pyatspi.Registry.getDesktop(0)
        apps = [a for a in (desk.getChildAtIndex(i) for i in range(desk.childCount)) if a is not None]
        if apps:
            out = []
            for a in apps:
                walk(a, 0, out)
            if len(out) > 3:
                print("\n".join(out))
                return 0
        time.sleep(1)
    print("no accessible application found")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
