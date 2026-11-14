"""验收测试，编码代理不得修改（ci-verify 返工 1，主代理编写；见 docs/CI-PLAN.md §7.6）。
Covers the Codex review findings C1-C6 on the ci-verify branch (2026-11-14).
Run: python3 -m unittest discover -s tests/tools -t ."""
import importlib.util
import os
import re
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _load(rel, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SMOKE = _load("ci/smoke.py", "cvf_smoke")
VS = _load("ci/verify_steps.py", "cvf_vsteps")


class C1JenkinsSourceStage(unittest.TestCase):
    """A failing Linux check must not stop the stash / Windows stage: each runs inside catchError."""

    def test_linux_checks_wrapped_in_catch_error(self):
        text = (ROOT / "ci" / "Jenkinsfile.verify").read_text(encoding="utf-8")
        for cmd in ("python3 tools/assets.py check", "python3 ci/run_pytests.py"):
            pat = r"catchError\s*\([^)]*\)\s*\{\s*sh\s+['\"]" + re.escape(cmd)
            self.assertRegex(text, pat, "%r must run inside its own catchError { }" % cmd)
        source = text[text.index("stage('Source')"):text.index("stage('Windows GPU')")]
        self.assertLess(source.index("run_pytests.py"), source.index("stash name"), "stash must follow the checks")


class C4ProbeSelection(unittest.TestCase):
    """A probe pattern that matches nothing is an error, never a silent 0-probe success."""

    def test_unmatched_glob_raises(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "tests" / "probe").mkdir(parents=True)
            (Path(d) / "tests" / "probe" / "a.lua").write_text("")
            with self.assertRaises(ValueError) as cm:
                VS.select_probes("tests/probe/a.lua, tests/probe/typo_*.lua", "full", d)
            self.assertIn("typo_*.lua", str(cm.exception))

    def test_empty_selection_raises(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "tests" / "probe").mkdir(parents=True)
            with self.assertRaises(ValueError):
                VS.select_probes("", "full", d)


class C5ShotsJUnitXmlSafe(unittest.TestCase):
    def test_control_characters_are_stripped(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "shots.xml")
            err = "suspicious log line:\x00\x01\x1b[31m bad \x0b thing\nsecond line"
            SMOKE.write_shots_junit(out, [("night_zh", 8.0, err), ("title_en", 8.0, None)])
            tree = ET.parse(out)  # must be well-formed XML 1.0
            fail = tree.find(".//testcase[@name='night_zh']/failure")
            self.assertIsNotNone(fail)
            self.assertIn("bad", fail.text)
            self.assertNotRegex(fail.text + fail.get("message"), r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


class C6ShotNamesCaseInsensitive(unittest.TestCase):
    def test_names_differing_only_in_case_are_duplicates(self):
        with self.assertRaises(ValueError):
            SMOKE.parse_shots("night|WS_LANG=zh|\nNIGHT|WS_LANG=en|\n")


FAKE_JAVA = """#!/usr/bin/env bash
printf '%s\\n' "$@" > "$FAKE_ARGS"
echo "Started winter_survival-verify #7"
echo "Finished: ${FAKE_RESULT:-SUCCESS}"
exit 0
"""

FAKE_CURL = """#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift; fi
  shift
done
cp "$FAKE_ZIP" "$out"
exit 0
"""


@unittest.skipIf(shutil.which("bash") is None or shutil.which("git") is None, "needs bash and git")
class CiVerifyScript(unittest.TestCase):
    """Runs a copy of tools/ci_verify.sh in a throwaway git repo with fake java/curl and a fake HOME."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        self.repo = t / "repo"
        (self.repo / "tools").mkdir(parents=True)
        (self.repo / "sub").mkdir()
        for f in ("ci_verify.sh", "ci_verify_summary.py"):
            shutil.copy(ROOT / "tools" / f, self.repo / "tools" / f)
        (self.repo / "sub" / "shots.txt").write_text("a_zh|WS_LANG=zh|\n", encoding="utf-8")
        home = t / "home"
        (home / ".config" / "jenkins").mkdir(parents=True)
        (home / ".config" / "jenkins" / "jenkins-cli.jar").write_text("")
        (home / ".config" / "jenkins" / "ci_auth").write_text("user:token")
        bin_ = t / "bin"
        bin_.mkdir()
        for name, body in (("java", FAKE_JAVA), ("curl", FAKE_CURL)):
            p = bin_ / name
            p.write_text(body)
            p.chmod(p.stat().st_mode | stat.S_IXUSR)
        self.args_file = t / "java_args.txt"
        self.zip = t / "bad.zip"
        self.zip.write_bytes(b"this is not a zip file")
        self.out = t / "out"
        self.env = dict(os.environ, HOME=str(home), PATH=str(bin_) + os.pathsep + os.environ["PATH"],
                        FAKE_ARGS=str(self.args_file), FAKE_ZIP=str(self.zip),
                        GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
                        GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
        git = lambda *a: subprocess.run(["git", *a], cwd=self.repo, env=self.env, check=True,
                                        capture_output=True)
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "-m", "init")

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *args, cwd=None, result="SUCCESS"):
        env = dict(self.env, FAKE_RESULT=result)
        return subprocess.run(["bash", str(self.repo / "tools" / "ci_verify.sh"), "--name", "t1",
                               "--out", str(self.out), "--max-wait", "60", *args],
                              cwd=cwd or self.repo, env=env, capture_output=True, text=True, timeout=120)

    def test_c2_relative_shots_path_from_subdirectory(self):
        r = self.run_script("--shots", "shots.txt", cwd=self.repo / "sub")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        args = self.args_file.read_text().splitlines()
        self.assertIn("SHOTS=a_zh|WS_LANG=zh|", args)

    def test_c3_bad_archive_still_summarises_and_exit_follows_result(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 0, "SUCCESS build must exit 0 even if artifacts fail to unpack\n"
                         + r.stdout + r.stderr)
        self.assertIn("ci_verify summary", r.stdout)
        self.assertRegex(r.stdout + r.stderr, r"(?i)artifact")  # the unpack problem is reported

    def test_c3_failed_build_exits_nonzero(self):
        r = self.run_script(result="FAILURE")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("ci_verify summary", r.stdout)

    def test_snapshot_leaves_index_and_branch_alone(self):
        (self.repo / "new_untracked.txt").write_text("x")
        before = subprocess.run(["git", "status", "--porcelain"], cwd=self.repo, env=self.env,
                                capture_output=True, text=True).stdout
        self.run_script()
        after = subprocess.run(["git", "status", "--porcelain"], cwd=self.repo, env=self.env,
                               capture_output=True, text=True).stdout
        self.assertEqual(before, after)
        tree = subprocess.run(["git", "ls-tree", "-r", "--name-only", "refs/ci/t1"], cwd=self.repo,
                              env=self.env, capture_output=True, text=True).stdout
        self.assertIn("new_untracked.txt", tree)


if __name__ == "__main__":
    unittest.main()
