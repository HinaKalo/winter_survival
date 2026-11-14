#!/usr/bin/env python3
"""Print a compact summary of the JUnit XML files and screenshots under a ci_verify output dir.

  ci_verify_summary.py OUT_DIR

Stdlib only. Always exits 0 (the verdict is the Jenkins build result, not this summary).
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def summarize(out_dir):
    """Returns (lines, counts) where counts = (tests, failures, errors, skipped)."""
    out = Path(out_dir)
    lines, tot = [], [0, 0, 0, 0]
    for xml in sorted(out.rglob("*.xml")):
        try:
            root = ET.parse(str(xml)).getroot()
        except Exception as e:  # noqa: BLE001 - any unreadable XML
            lines.append("  %s: unreadable (%s)" % (xml.relative_to(out), e))
            continue
        suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
        for s in suites:
            cases = list(s.iter("testcase"))
            bad = []
            for c in cases:
                if c.find("failure") is not None or c.find("error") is not None:
                    bad.append(c.get("name") or "?")
            skipped = sum(1 for c in cases if c.find("skipped") is not None)
            t, f = len(cases), len(bad)
            tot[0] += t
            tot[1] += f
            tot[3] += skipped
            lines.append("  %-28s %4d tests, %d failed%s  [%s]" % (
                s.get("name") or xml.stem, t, f, ", %d skipped" % skipped if skipped else "",
                xml.relative_to(out).as_posix()))
            for n in bad[:20]:
                lines.append("      FAILED: " + n)
            if len(bad) > 20:
                lines.append("      ... %d more" % (len(bad) - 20))
    return lines, tot


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    out = Path(argv[1])
    lines, tot = summarize(out)
    print("JUnit suites:")
    print("\n".join(lines) if lines else "  (none found)")
    print("TOTAL: %d tests, %d failed, %d skipped" % (tot[0], tot[1], tot[3]))
    shots = sorted(out.rglob("shots/*.png"))
    print("Screenshots:" + ("" if shots else " (none)"))
    for s in shots:
        print("  " + str(s))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
