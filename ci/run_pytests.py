#!/usr/bin/env python3
"""Run the Python unit tests (`python3 -m unittest discover -s tests/tools -t .`) and write JUnit XML.

  run_pytests.py --junit reports/linux/unit_py.xml [--start-dir tests/tools]

Stdlib only. Prints the normal unittest output; exits 1 on any failure or error.
"""
import argparse
import os
import re
import sys
import time
import traceback
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUITE = "python-unit"


class JUnitResult(unittest.TextTestResult):
    """TextTestResult that also records one entry per test for the JUnit report."""

    def __init__(self, stream, descriptions, verbosity):
        super().__init__(stream, descriptions, verbosity)
        self.records = []  # (test id, status, seconds, message)
        self._t0 = 0.0

    def startTest(self, test):
        super().startTest(test)
        self._t0 = time.time()

    def _rec(self, test, status, message=""):
        self.records.append((test.id(), status, time.time() - self._t0, message))

    @staticmethod
    def _tb(err):
        return "".join(traceback.format_exception(*err))

    def addSuccess(self, test):
        super().addSuccess(test)
        self._rec(test, "pass")

    def addError(self, test, err):
        super().addError(test, err)
        self._rec(test, "error", self._tb(err))

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self._rec(test, "failure", self._tb(err))

    def addSubTest(self, test, subtest, err):
        # Passing subtests are covered by the parent's addSuccess (unittest only calls that when no subtest
        # failed); a failing subtest suppresses it, so each non-passing subtest is recorded here.
        super().addSubTest(test, subtest, err)
        if err is not None:
            status = "failure" if issubclass(err[0], test.failureException) else "error"
            self._rec(subtest, status, self._tb(err))

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self._rec(test, "skipped", str(reason))

    def addExpectedFailure(self, test, err):
        super().addExpectedFailure(test, err)
        self._rec(test, "pass")

    def addUnexpectedSuccess(self, test):
        super().addUnexpectedSuccess(test)
        self._rec(test, "failure", "unexpected success")


def write_junit(path, records, seconds):
    """Write records [(test id, status, seconds, message)] as a JUnit testsuite."""
    counts = {"failure": 0, "error": 0, "skipped": 0}
    for _id, status, _s, _m in records:
        if status in counts:
            counts[status] += 1
    suite = ET.Element("testsuite", name=SUITE, tests=str(len(records)), failures=str(counts["failure"]),
                       errors=str(counts["error"]), skipped=str(counts["skipped"]), time="%.3f" % seconds)
    for test_id, status, secs, msg in records:
        # subtest ids look like "mod.Cls.test_x (k=1.5)": split off the description before the dots
        base, sp, desc = test_id.partition(" ")
        cls, _, name = base.rpartition(".")
        name = name + sp + desc
        tc = ET.SubElement(suite, "testcase", classname=_xml_safe(cls or SUITE), name=_xml_safe(name or test_id),
                           time="%.3f" % secs)
        if status == "failure":
            ET.SubElement(tc, "failure", message="failed").text = _xml_safe(msg)
        elif status == "error":
            ET.SubElement(tc, "error", message="error").text = _xml_safe(msg)
        elif status == "skipped":
            ET.SubElement(tc, "skipped", message=_xml_safe(msg))
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(str(p), encoding="utf-8", xml_declaration=True)


_XML_BAD = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]")


def _xml_safe(s):
    """Drop characters XML 1.0 cannot carry (a raw control char in a traceback would break the junit step)."""
    return _XML_BAD.sub("", s or "")


def run(start_dir, junit):
    """Discover and run tests under start_dir (top level = repo root). Returns 0 if all passed."""
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    t0 = time.time()
    suite = unittest.TestLoader().discover(start_dir=str(start_dir), top_level_dir=str(ROOT))
    runner = unittest.TextTestRunner(resultclass=JUnitResult, verbosity=2, stream=sys.stdout)
    result = runner.run(suite)
    write_junit(junit, result.records, time.time() - t0)
    print("run_pytests: %d test(s), %d failure(s), %d error(s) -> %s"
          % (result.testsRun, len(result.failures), len(result.errors), junit))
    return 0 if result.wasSuccessful() else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="Python unit tests with JUnit output")
    ap.add_argument("--junit", required=True)
    ap.add_argument("--start-dir", default=str(ROOT / "tests" / "tools"))
    a = ap.parse_args(argv)
    start = Path(a.start_dir)
    if not start.is_absolute():
        start = Path.cwd() / start
    return run(start, a.junit)


if __name__ == "__main__":
    sys.exit(main())
