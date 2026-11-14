"""Unit tests for the verify-pipeline helpers: ci/smoke.py (env/save-dir/shots-file), ci/verify_steps.py,
tools/ci_verify_summary.py and the job XML. Run: python3 -m unittest discover -s tests/tools -t ."""
import importlib.util
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _load(rel, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SMOKE = _load("ci/smoke.py", "cv_smoke")
VS = _load("ci/verify_steps.py", "cv_vsteps")
SUM = _load("tools/ci_verify_summary.py", "cv_summary")


class SmokeParsing(unittest.TestCase):
    def test_env_pairs(self):
        self.assertEqual(SMOKE.parse_env_pairs(["A=1", "B=x=y", "C="]), {"A": "1", "B": "x=y", "C": ""})
        with self.assertRaises(ValueError):
            SMOKE.parse_env_pairs(["nokey"])
        with self.assertRaises(ValueError):
            SMOKE.parse_env_pairs(["=v"])

    def test_parse_shots(self):
        text = ("# comment\n\n"
                "m2_night_zh|WS_SCENE=m2_demo WS_MODE=cutaway WS_HOUR=21 WS_LANG=zh|\n"
                "plain\n"
                "withargs|A=1|--dev --no-audio\r\n")
        shots = SMOKE.parse_shots(text)
        self.assertEqual([s["name"] for s in shots], ["m2_night_zh", "plain", "withargs"])
        self.assertEqual(shots[0]["env"]["WS_HOUR"], "21")
        self.assertEqual(shots[0]["args"], [])
        self.assertEqual(shots[1], {"name": "plain", "env": {}, "args": []})
        self.assertEqual(shots[2]["args"], ["--dev", "--no-audio"])

    def test_parse_shots_errors(self):
        with self.assertRaises(ValueError):
            SMOKE.parse_shots("a|X=1|\na||\n")  # duplicate
        with self.assertRaises(ValueError):
            SMOKE.parse_shots("a|bad|\n")
        with self.assertRaises(ValueError):
            SMOKE.parse_shots("|A=1|\n")

    def test_safe_name(self):
        self.assertEqual(SMOKE.safe_name("../x y/z"), "x_y_z")

    def test_write_settings(self):
        with tempfile.TemporaryDirectory() as d:
            SMOKE.write_settings(os.path.join(d, "s"), "ko")
            self.assertEqual((Path(d) / "s" / "settings.sav").read_text(),
                             'return { version = 1, lang = "ko" }\n')

    def test_old_cli_still_parses(self):
        a = SMOKE.build_parser().parse_args(["--exe", "e", "--title", "T", "--cwd", ".", "--seconds", "6",
                                             "--shot-at", "3", "--shot", "s.png", "--log", "g.log"])
        self.assertEqual((a.env, a.save_dir, a.lang, a.args, a.shots_file), ([], None, None, "", None))

    def test_new_cli(self):
        a = SMOKE.build_parser().parse_args(["--exe", "e", "--env", "A=1", "--env", "B=2", "--save-dir", "d",
                                             "--lang", "en", "--args=--dev"])
        self.assertEqual(a.env, ["A=1", "B=2"])
        self.assertEqual((a.save_dir, a.lang, a.args), ("d", "en", "--dev"))


class SmokeRun(unittest.TestCase):
    """Drive run_batch/main with a fake exe (python script) that echoes env/args."""

    def _fake_exe(self, d):
        import sys
        p = Path(d) / "fake.py"
        p.write_text("import os,sys\nprint('ARGS', sys.argv[1:])\nprint('SCENE', os.environ.get('WS_SCENE'))\n"
                     "sd = sys.argv[sys.argv.index('--save-dir')+1]\n"
                     "print('SETTINGS', open(os.path.join(sd,'settings.sav')).read().strip())\n")
        if os.name == "nt":
            return None
        w = Path(d) / "fake.sh"
        w.write_text('#!/bin/sh\nexec %s %s "$@"\n' % (sys.executable, p))
        w.chmod(0o755)
        return str(w)

    @unittest.skipIf(os.name == "nt", "fake shell exe")
    def test_batch(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as d:
            exe = self._fake_exe(d)
            shots = Path(d) / "shots.txt"
            shots.write_text("one|WS_SCENE=m2_demo WS_LANG=ko|--dev\ntwo||\n")

            def fake_shot(path, title=None):
                Path(path).write_bytes(b"png")
                return None

            with mock.patch.object(SMOKE, "take_screenshot", fake_shot):
                rc = SMOKE.main(["--exe", exe, "--cwd", d, "--seconds", "0", "--shot-at", "0",
                                 "--shots-file", str(shots), "--out-dir", str(Path(d) / "o"),
                                 "--junit", str(Path(d) / "o.xml")])
            self.assertEqual(rc, 0)
            log1 = (Path(d) / "o" / "one.log").read_text()
            self.assertIn("m2_demo", log1)
            self.assertIn("--dev", log1)
            self.assertIn('lang = "ko"', log1)
            self.assertIn('lang = "zh"', (Path(d) / "o" / "two.log").read_text())  # default language
            self.assertTrue((Path(d) / "o" / "two.png").exists())
            root = ET.parse(str(Path(d) / "o.xml")).getroot()
            self.assertEqual(len(list(root.iter("testcase"))), 2)

    @unittest.skipIf(os.name == "nt", "fake shell exe")
    def test_batch_failure_isolated(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as d:
            exe = self._fake_exe(d)
            shots = Path(d) / "shots.txt"
            shots.write_text("bad||\ngood||\n")
            calls = []

            def fake_shot(path, title=None):
                calls.append(path)
                if len(calls) == 1:
                    return "boom"
                Path(path).write_bytes(b"png")
                return None

            with mock.patch.object(SMOKE, "take_screenshot", fake_shot):
                rc = SMOKE.main(["--exe", exe, "--cwd", d, "--seconds", "0", "--shot-at", "0",
                                 "--shots-file", str(shots), "--out-dir", str(Path(d) / "o"),
                                 "--junit", str(Path(d) / "o.xml")])
            self.assertEqual(rc, 1)
            self.assertEqual(len(calls), 2)  # the second shot still ran
            root = ET.parse(str(Path(d) / "o.xml")).getroot()
            self.assertEqual(root.find("testsuite").get("failures"), "1")


class VerifySteps(unittest.TestCase):
    def test_has_step(self):
        self.assertTrue(VS.has_step('const s = b.step("luatest", "x");', "luatest"))
        self.assertFalse(VS.has_step('const s = b.step("test", "x");', "luatest"))

    def test_select_probes(self):
        with tempfile.TemporaryDirectory() as d:
            pd = Path(d) / "tests" / "probe"
            pd.mkdir(parents=True)
            for n in ("a.lua", "soak_heap.lua", "m2_x.lua"):
                (pd / n).write_text("")
            self.assertEqual(VS.select_probes("", "full", d),
                             ["tests/probe/a.lua", "tests/probe/m2_x.lua", "tests/probe/soak_heap.lua"])
            self.assertEqual(VS.select_probes("", "quick", d), ["tests/probe/a.lua", "tests/probe/m2_x.lua"])
            self.assertEqual(VS.select_probes("tests/probe/m2_*.lua, tests/probe/a.lua", "full", d),
                             ["tests/probe/m2_x.lua", "tests/probe/a.lua"])
            self.assertEqual(VS.select_probes("tests/probe/missing.lua", "full", d), ["tests/probe/missing.lua"])


class Summary(unittest.TestCase):
    def test_summarize(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "windows" / "shots").mkdir(parents=True)
            (Path(d) / "windows" / "shots" / "t.png").write_bytes(b"x")
            (Path(d) / "windows" / "p.xml").write_text(
                '<testsuites><testsuite name="p"><testcase name="ok"/>'
                '<testcase name="bad"><failure message="m"/></testcase></testsuite></testsuites>')
            (Path(d) / "windows" / "junk.xml").write_bytes(b"\xff\xfe<")
            lines, tot = SUM.summarize(d)
            self.assertEqual(tot[:2], [2, 1])
            self.assertTrue(any("FAILED: bad" in l for l in lines))
            self.assertTrue(any("unreadable" in l for l in lines))


class JobFiles(unittest.TestCase):
    def test_job_xml(self):
        root = ET.parse(str(ROOT / "ci" / "jobs" / "winter_survival-verify.xml")).getroot()
        params = [p.find("name").text for p in root.find("properties")[0].find("parameterDefinitions")]
        self.assertEqual(params, ["REF", "PROFILE", "SHOTS", "PROBES", "BALANCE_DAYS"])
        self.assertEqual(root.find(".//scriptPath").text, "ci/Jenkinsfile.verify")
        self.assertEqual(root.find(".//branches//name").text, "${REF}")
        self.assertIn("+refs/ci/*:refs/ci/*", root.find(".//refspec").text)
        self.assertEqual(len(list(root.iter("triggers"))), 1)
        self.assertEqual(len(list(root.find(".//triggers"))), 0)  # no SCM polling

    def test_jenkinsfile_has_no_desktop_drop(self):
        text = (ROOT / "ci" / "Jenkinsfile.verify").read_text()
        self.assertNotIn("Desktop", text)
        self.assertNotIn("pollSCM", text)


if __name__ == "__main__":
    unittest.main()
