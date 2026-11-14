#!/usr/bin/env python3
"""Convert a `zig build probe` log into a JUnit XML report (stdlib only, Python 3.10+).

  probe_junit.py --log probe.log --junit reports/windows/probe.xml [--suite probe]

Input lines (Delve logs contain NUL bytes and may have CRLF endings; both are tolerated):
  PROBE PASS <name> / PROBE FAIL <name>   one testcase per check
  PROBE info <msg>                        suite system-out
  PROBE done: ... after <s>s              suite time (optional)
  PROBE SUMMARY <passed>/<total> passed   required; must agree with the PASS/FAIL lines

Exit 0 when the log is a complete probe run (SUMMARY present, at least one check, counts agree),
even if some checks FAILED: those become JUnit failures and the probe's own exit code gates the build.
Exit 1 when the run is incomplete or unusable (no SUMMARY, 0 checks, count mismatch, unreadable log).
The XML is written in every case; incomplete runs get an extra failing "probe output" testcase.
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Anchored: only a line that starts with "PROBE " (after stripping NUL and whitespace) is a probe line.
# "PROBE info ... PROBE PASS x" is an info line, not a check.
CHECK_RE = re.compile(r"PROBE (PASS|FAIL) (.*)$")
INFO_RE = re.compile(r"PROBE info (.*)$")
SUMMARY_RE = re.compile(r"PROBE SUMMARY (\d+)/(\d+) passed\b")
DONE_RE = re.compile(r"PROBE done: .*? after (\d+(?:\.\d+)?)s")
# characters that are not allowed in XML 1.0 (and would make Jenkins' parser reject the file)
_XML_BAD = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f￾￿]")


def _xml_safe(s: str) -> str:
    return _XML_BAD.sub("", s)


def parse_log(text: str) -> dict:
    """Parse probe output text. Returns {checks: [(ok, name)], infos: [str], summaries: [(p, t)], seconds: float|None}."""
    text = text.replace("\x00", "")
    checks, infos, summaries, seconds = [], [], [], None
    for raw in text.splitlines():
        line = raw.strip()
        m = CHECK_RE.match(line)
        if m:
            checks.append((m.group(1) == "PASS", m.group(2).rstrip()))
            continue
        m = INFO_RE.match(line)
        if m:
            infos.append(m.group(1).rstrip())
            continue
        m = SUMMARY_RE.match(line)
        if m:
            summaries.append((int(m.group(1)), int(m.group(2))))
            continue
        m = DONE_RE.match(line)
        if m:
            seconds = float(m.group(1))
    return {"checks": checks, "infos": infos, "summaries": summaries, "seconds": seconds}


def problems(parsed: dict) -> list:
    """Reasons the run cannot be trusted as a complete probe run (empty list = complete)."""
    out = []
    checks = parsed["checks"]
    if not parsed["summaries"]:
        out.append("no 'PROBE SUMMARY' line: the probe did not finish")
    elif len(parsed["summaries"]) > 1:
        out.append("%d 'PROBE SUMMARY' lines (expected exactly one)" % len(parsed["summaries"]))
    if not checks:
        out.append("0 checks recorded")
    if parsed["summaries"] and checks:
        passed, total = parsed["summaries"][-1]
        got_passed = sum(1 for ok, _ in checks if ok)
        if total != len(checks) or passed != got_passed:
            out.append("SUMMARY says %d/%d passed but log has %d/%d PASS lines"
                       % (passed, total, got_passed, len(checks)))
    return out


def build_report(parsed: dict, suite: str = "probe", extra_problems=()) -> tuple:
    """Return (ElementTree root, problem list) for a parsed log."""
    probs = list(extra_problems) + problems(parsed)
    checks = parsed["checks"]
    tests = len(checks) + (1 if probs else 0)
    failures = sum(1 for ok, _ in checks if not ok) + (1 if probs else 0)
    root = ET.Element("testsuite", name=_xml_safe(suite), tests=str(tests), failures=str(failures),
                      errors="0", skipped="0", time="%.3f" % (parsed["seconds"] or 0.0))
    for ok, name in checks:
        tc = ET.SubElement(root, "testcase", classname=_xml_safe(suite), name=_xml_safe(name))
        if not ok:
            ET.SubElement(tc, "failure", message="PROBE FAIL")
    if probs:
        tc = ET.SubElement(root, "testcase", classname=_xml_safe(suite), name="probe output")
        f = ET.SubElement(tc, "failure", message="%d problem(s)" % len(probs))
        f.text = _xml_safe("\n".join(probs))
    if parsed["infos"]:
        ET.SubElement(root, "system-out").text = _xml_safe("\n".join(parsed["infos"]))
    return root, probs


def convert(log_path, junit_path, suite: str = "probe") -> int:
    """Read log_path, write JUnit XML to junit_path. Returns 0 for a complete run, 1 otherwise."""
    read_error = None
    try:
        text = Path(log_path).read_bytes().decode("utf-8", "replace")
    except OSError as e:
        text = ""
        read_error = "cannot read probe log %s: %s" % (log_path, e)
    parsed = parse_log(text)
    root, probs = build_report(parsed, suite, [read_error] if read_error else [])
    jp = Path(junit_path)
    jp.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(str(jp), encoding="utf-8", xml_declaration=True)
    for p in probs:
        print("probe_junit: ERROR: " + p, file=sys.stderr)
    n = len(parsed["checks"])
    bad = sum(1 for ok, _ in parsed["checks"] if not ok)
    print("probe_junit: %d check(s), %d failed -> %s" % (n, bad, jp))
    return 1 if probs else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="PROBE log -> JUnit XML")
    ap.add_argument("--log", required=True)
    ap.add_argument("--junit", required=True)
    ap.add_argument("--suite", default="probe")
    a = ap.parse_args(argv)
    return convert(a.log, a.junit, a.suite)


if __name__ == "__main__":
    sys.exit(main())
