"""Unit tests for the stdlib CI helpers in ci/: probe_junit, smoke (title option), run_pytests, zig_steps.

Run from the repo root: python3 -m unittest discover -s tests/tools -t .
"""
import contextlib
import importlib.util
import inspect
import io
import os
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
CI = ROOT / "ci"


def _load(name):
    spec = importlib.util.spec_from_file_location("ci_" + name, CI / (name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


PJ = _load("probe_junit")
SMOKE = _load("smoke")
RP = _load("run_pytests")
ZS = _load("zig_steps")

# NUL bytes, CRLF endings, an info line and a failing check, as they come out of Delve on Windows.
MIXED_LOG = (
    "\x00\x00PROBE info audio playback enabled: false\r\n"
    "PROBE PASS lua script running (no Lua error)\r\n"
    "PROBE PASS keyboard D/A moves hero\x00\r\n"
    "PROBE FAIL mouse click pathfinds hero to target tile\r\n"
    "PROBE info hero moved 2.10 units\r\n"
    "PROBE done: 2/3 checks passed after 4.20s\r\n"
    "PROBE SUMMARY 2/3 passed\r\n"
)

GOOD_LOG = "".join("PROBE PASS check %d\n" % i for i in range(19)) + "PROBE SUMMARY 19/19 passed\n"


@contextlib.contextmanager
def quiet():
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        yield


class ProbeParseTest(unittest.TestCase):
    def test_parse_tolerates_nul_and_crlf(self):
        parsed = PJ.parse_log(MIXED_LOG)
        self.assertEqual(parsed["checks"], [
            (True, "lua script running (no Lua error)"),
            (True, "keyboard D/A moves hero"),
            (False, "mouse click pathfinds hero to target tile"),
        ])
        self.assertEqual(parsed["infos"], ["audio playback enabled: false", "hero moved 2.10 units"])
        self.assertEqual(parsed["summaries"], [(2, 3)])
        self.assertAlmostEqual(parsed["seconds"], 4.2)
        self.assertEqual(PJ.problems(parsed), [])

    def test_no_summary_is_a_problem(self):
        parsed = PJ.parse_log("PROBE PASS a\nPROBE PASS b\n")
        probs = PJ.problems(parsed)
        self.assertTrue(any("no 'PROBE SUMMARY'" in p for p in probs), probs)

    def test_zero_checks_is_a_problem(self):
        parsed = PJ.parse_log("PROBE SUMMARY 0/0 passed\n")
        self.assertIn("0 checks recorded", PJ.problems(parsed))

    def test_summary_mismatch_is_a_problem(self):
        parsed = PJ.parse_log("PROBE PASS a\nPROBE PASS b\nPROBE SUMMARY 3/3 passed\n")
        probs = PJ.problems(parsed)
        self.assertTrue(any("SUMMARY says 3/3" in p for p in probs), probs)

    def test_duplicate_summary_is_a_problem(self):
        parsed = PJ.parse_log("PROBE PASS a\nPROBE SUMMARY 1/1 passed\nPROBE SUMMARY 1/1 passed\n")
        self.assertTrue(any("2 'PROBE SUMMARY'" in p for p in PJ.problems(parsed)))

    def test_done_line_and_fail_lines_are_not_counted_as_checks(self):
        parsed = PJ.parse_log(MIXED_LOG)
        self.assertEqual(len(parsed["checks"]), 3)

    def test_only_lines_starting_with_probe_count(self):
        log = (
            "PROBE info audio ok PROBE PASS not a check\n"
            "noise PROBE PASS not a check either\n"
            "  \x00PROBE PASS indented after NUL and spaces\r\n"
            "PROBE FAIL real failure\n"
            "PROBE SUMMARY 1/2 passed\n"
        )
        parsed = PJ.parse_log(log)
        self.assertEqual(parsed["checks"], [(True, "indented after NUL and spaces"), (False, "real failure")])
        self.assertEqual(parsed["infos"], ["audio ok PROBE PASS not a check"])
        self.assertEqual(parsed["summaries"], [(1, 2)])
        self.assertEqual(PJ.problems(parsed), [])


class ProbeJUnitTest(unittest.TestCase):
    def test_failure_counts_in_root(self):
        root, probs = PJ.build_report(PJ.parse_log(MIXED_LOG))
        self.assertEqual(probs, [])
        self.assertEqual(root.get("tests"), "3")
        self.assertEqual(root.get("failures"), "1")
        self.assertEqual(root.get("time"), "4.200")
        cases = root.findall("testcase")
        self.assertEqual(len(cases), 3)
        self.assertEqual(len(cases[2].findall("failure")), 1)
        self.assertIsNotNone(root.find("system-out"))

    def test_incomplete_run_adds_probe_output_failure(self):
        root, probs = PJ.build_report(PJ.parse_log(""))
        self.assertTrue(probs)
        self.assertEqual(root.get("tests"), "1")
        self.assertEqual(root.get("failures"), "1")
        self.assertEqual(root.find("testcase").get("name"), "probe output")

    def test_names_are_xml_escaped_and_control_chars_removed(self):
        log = 'PROBE PASS a <b> & "c"\x01\nPROBE SUMMARY 1/1 passed\n'
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "probe.xml")
            logp = os.path.join(d, "probe.log")
            Path(logp).write_text(log, encoding="utf-8")
            with quiet():
                rc = PJ.convert(logp, out)
            self.assertEqual(rc, 0)
            tc = ET.parse(out).getroot().find("testcase")
            self.assertEqual(tc.get("name"), 'a <b> & "c"')

    def test_convert_roundtrip_with_nul_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            logp = os.path.join(d, "probe.log")
            Path(logp).write_bytes(MIXED_LOG.encode("utf-8"))
            out = os.path.join(d, "sub", "probe.xml")
            with quiet():
                rc = PJ.convert(logp, out)
            self.assertEqual(rc, 0)
            root = ET.parse(out).getroot()
            self.assertEqual(root.get("tests"), "3")
            self.assertEqual(root.get("failures"), "1")

    def test_convert_missing_log_fails_but_writes_xml(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "probe.xml")
            with quiet():
                rc = PJ.convert(os.path.join(d, "nope.log"), out)
            self.assertEqual(rc, 1)
            root = ET.parse(out).getroot()
            self.assertEqual(root.get("failures"), "1")

    def test_convert_without_summary_exits_1(self):
        with tempfile.TemporaryDirectory() as d:
            logp = os.path.join(d, "probe.log")
            Path(logp).write_text("PROBE PASS only\n", encoding="utf-8")
            with quiet():
                rc = PJ.convert(logp, os.path.join(d, "probe.xml"))
            self.assertEqual(rc, 1)

    def test_convert_forbidden_quad_warning_exits_1(self):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        log = d / "p.log"
        log.write_text("PROBE PASS a\nwarning: iso: chunk quad budget (10000) exceeded, remaining quads skipped\n"
                       "PROBE SUMMARY 1/1 passed\n", encoding="utf-8")
        self.assertEqual(PJ.convert(log, d / "p.xml"), 1)

    def test_convert_with_failed_checks_still_exits_0(self):
        # a complete run with failing checks is a valid report; the probe's exit code gates the build
        with tempfile.TemporaryDirectory() as d:
            logp = os.path.join(d, "probe.log")
            Path(logp).write_text("PROBE FAIL x\nPROBE SUMMARY 0/1 passed\n", encoding="utf-8")
            with quiet():
                rc = PJ.convert(logp, os.path.join(d, "probe.xml"))
            self.assertEqual(rc, 0)


class SmokeTitleTest(unittest.TestCase):
    BASE = ["--exe", "game.exe", "--shot", "shot.png", "--log", "game.log"]

    def test_title_defaults_to_starter_title(self):
        args = SMOKE.build_parser().parse_args(self.BASE)
        self.assertEqual(args.title, "Thirty Below")
        self.assertEqual(SMOKE.DEFAULT_TITLE, "Thirty Below")

    def test_title_option_overrides_default(self):
        args = SMOKE.build_parser().parse_args(self.BASE + ["--title", "Other Game"])
        self.assertEqual(args.title, "Other Game")

    def test_title_is_not_a_module_global_any_more(self):
        self.assertFalse(hasattr(SMOKE, "WINDOW_TITLE"))

    def test_take_screenshot_and_run_game_take_title(self):
        for fn in (SMOKE.take_screenshot, SMOKE.run_game):
            params = inspect.signature(fn).parameters
            self.assertIn("title", params, fn.__name__)
            self.assertEqual(params["title"].default, "Thirty Below", fn.__name__)

    def test_main_passes_title_to_run_game(self):
        captured = {}

        def fake_run_game(exe, cwd, seconds, shot_at, shot, log, timeout, title=None):
            captured["title"] = title
            return None, 0, None, 0.0

        with tempfile.TemporaryDirectory() as d:
            argv = ["--exe", "game.exe", "--shot", os.path.join(d, "s.png"), "--log", os.path.join(d, "g.log"),
                    "--title", "Custom"]
            with mock.patch.object(SMOKE, "run_game", fake_run_game), quiet():
                SMOKE.main(argv)
        self.assertEqual(captured["title"], "Custom")


class RunPytestsJUnitTest(unittest.TestCase):
    def test_write_junit_counts_and_names(self):
        records = [
            ("tests.tools.test_x.Cls.test_ok", "pass", 0.01, ""),
            ("tests.tools.test_x.Cls.test_bad", "failure", 0.02, "Traceback...\nAssertionError"),
            ("tests.tools.test_x.Cls.test_err", "error", 0.0, "Traceback..."),
            ("tests.tools.test_x.Cls.test_skip", "skipped", 0.0, "no PIL"),
        ]
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "sub", "unit.xml")
            RP.write_junit(out, records, 1.5)
            root = ET.parse(out).getroot()
        self.assertEqual(root.get("tests"), "4")
        self.assertEqual(root.get("failures"), "1")
        self.assertEqual(root.get("errors"), "1")
        self.assertEqual(root.get("skipped"), "1")
        cases = root.findall("testcase")
        self.assertEqual(cases[0].get("classname"), "tests.tools.test_x.Cls")
        self.assertEqual(cases[0].get("name"), "test_ok")
        self.assertIsNotNone(cases[1].find("failure"))
        self.assertIsNotNone(cases[2].find("error"))
        self.assertIsNotNone(cases[3].find("skipped"))


class RunPytestsSubTestTest(unittest.TestCase):
    """Subtests must reach the JUnit XML: a failing subtest used to vanish (tests=0 failures=0)."""

    @staticmethod
    def _run(body):
        # Case is defined locally so that discovery of this module does not pick it up.
        class Case(unittest.TestCase):
            def test_sub(self):
                body(self)

        result = RP.JUnitResult(io.StringIO(), True, 0)
        unittest.TestSuite([Case("test_sub")]).run(result)
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "unit.xml")
            RP.write_junit(out, result.records, 0.1)
            root = ET.parse(out).getroot()
        return result, root

    def test_one_failing_subtest_gives_failures_1(self):
        def body(tc):
            for i in range(3):
                with tc.subTest(i=i):
                    tc.assertNotEqual(i, 1)

        result, root = self._run(body)
        self.assertFalse(result.wasSuccessful())
        self.assertEqual(root.get("tests"), "1")
        self.assertEqual(root.get("failures"), "1")
        self.assertEqual(root.get("errors"), "0")
        cases = root.findall("testcase")
        self.assertIsNotNone(cases[0].find("failure"))
        self.assertIn("(i=1)", cases[0].get("name"))

    def test_erroring_subtest_gives_errors_1(self):
        def body(tc):
            for i in range(2):
                with tc.subTest(i=i):
                    if i == 1:
                        raise RuntimeError("boom")

        result, root = self._run(body)
        self.assertFalse(result.wasSuccessful())
        self.assertEqual(root.get("tests"), "1")
        self.assertEqual(root.get("failures"), "0")
        self.assertEqual(root.get("errors"), "1")
        self.assertIsNotNone(root.find("testcase").find("error"))

    def test_all_subtests_passing_records_one_success(self):
        def body(tc):
            for i in range(3):
                with tc.subTest(i=i):
                    tc.assertGreaterEqual(i, 0)

        result, root = self._run(body)
        self.assertTrue(result.wasSuccessful())
        self.assertGreaterEqual(int(root.get("tests")), 1)
        self.assertEqual(root.get("failures"), "0")
        self.assertEqual(root.get("errors"), "0")


class ZigStepsProbeTest(unittest.TestCase):
    def _run(self, fake_step):
        with tempfile.TemporaryDirectory() as d:
            calls = []

            def wrapped(zig, args, log, timeout=None):
                calls.append(args)
                return fake_step(log)

            with mock.patch.object(ZS, "step", wrapped), quiet():
                rc = ZS.run_probe("zig", d)
            xml_exists = os.path.isfile(os.path.join(d, "probe.xml"))
            return rc, calls, xml_exists

    def test_probe_command_and_success(self):
        def fake(log):
            Path(log).write_text(GOOD_LOG, encoding="utf-8")
            return 0

        rc, calls, xml_exists = self._run(fake)
        self.assertEqual(rc, 0)
        self.assertEqual(calls, [["build", "probe", "-Dbackend=headless"]])
        self.assertTrue(xml_exists)

    def test_incomplete_probe_log_fails(self):
        def fake(log):
            Path(log).write_text("PROBE PASS only\n", encoding="utf-8")
            return 0

        rc, _calls, xml_exists = self._run(fake)
        self.assertEqual(rc, 1)
        self.assertTrue(xml_exists)

    def test_nonzero_probe_exit_fails_even_with_good_log(self):
        def fake(log):
            Path(log).write_text(GOOD_LOG, encoding="utf-8")
            return 1

        rc, _calls, _xml = self._run(fake)
        self.assertEqual(rc, 1)

    def test_timeout_still_writes_log_and_xml(self):
        partial = b"PROBE PASS lua script running (no Lua error)\n"

        def fake_run(*args, **kwargs):
            raise subprocess.TimeoutExpired(args[0], kwargs["timeout"], output=partial)

        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(ZS.subprocess, "run", fake_run), quiet():
                rc = ZS.run_probe("zig", d, timeout=7)
            log = Path(d, "probe.log").read_text(encoding="utf-8")
            root = ET.parse(os.path.join(d, "probe.xml")).getroot()
        self.assertEqual(rc, 1)
        self.assertIn("PROBE PASS lua script running", log)
        self.assertIn("TIMEOUT after 7 s", log)
        self.assertEqual(root.get("failures"), "1")
        self.assertIn("probe output", [tc.get("name") for tc in root.findall("testcase")])

    def test_step_timeout_returns_124(self):
        def fake_run(*args, **kwargs):
            raise subprocess.TimeoutExpired(args[0], kwargs["timeout"])

        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "build.log")
            with mock.patch.object(ZS.subprocess, "run", fake_run), quiet():
                rc = ZS.step("zig", ["build"], log, timeout=3)
            text = Path(log).read_text(encoding="utf-8")
        self.assertEqual(rc, ZS.TIMEOUT_RC)
        self.assertIn("TIMEOUT after 3 s", text)

    def test_spawn_failure_still_writes_log_and_xml(self):
        def fake_run(*args, **kwargs):
            raise FileNotFoundError(2, "No such file", "zig")

        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(ZS.subprocess, "run", fake_run), quiet():
                rc = ZS.run_probe("zig", d)
            log = Path(d, "probe.log").read_text(encoding="utf-8")
            xml_exists = os.path.isfile(os.path.join(d, "probe.xml"))
        self.assertEqual(rc, 1)
        self.assertIn("ERROR: cannot run zig", log)
        self.assertTrue(xml_exists)


if __name__ == "__main__":
    unittest.main()
