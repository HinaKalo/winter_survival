"""验收测试（主代理编写，编码代理不得修改）：P0-PLAN §9.1 Q13。

verify 任务把下列文件复制进 --log-dir（Jenkins 归档 reports/windows/**，ci_verify.sh 下载到 <out>/windows/）：
  out/balance/report.json        -> <log-dir>/balance/report.json
  tests/fixtures/*.sav           -> <log-dir>/fixtures/<name>.sav
  tests/fixtures/manifest.lua    -> <log-dir>/fixtures/manifest.lua
不存在的文件跳过、不报错；任何步骤失败时也照样收集（便于排查）。
接口：ci/verify_steps.py 的 collect_outputs(root, log_dir) -> 已复制文件的相对路径列表（相对 log_dir，正斜杠，排序）；
main() 在返回前（成功或失败）以 root="." 调用它。
Run: python3 -m unittest tests.tools.test_ci_archive
"""
import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _load():
    spec = importlib.util.spec_from_file_location("cv_vsteps_archive", ROOT / "ci" / "verify_steps.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


VS = _load()


def _project(d, with_outputs=True):
    p = Path(d)
    (p / "tests" / "probe").mkdir(parents=True)
    (p / "tests" / "probe" / "a.lua").write_text("")
    (p / "build.zig").write_text('b.step("balance", "x");\n')
    if with_outputs:
        (p / "out" / "balance").mkdir(parents=True)
        (p / "out" / "balance" / "report.json").write_bytes(b'{"determinism":{"ok":true}}\n')
        fx = p / "tests" / "fixtures"
        fx.mkdir(parents=True)
        (fx / "day1_0600.sav").write_bytes(b"\x00\x01sav-a")
        (fx / "day3_1900.sav").write_bytes(b"\x00\x02sav-b")
        (fx / "manifest.lua").write_text("return {}\n")
        (fx / "make.lua").write_text("-- not collected\n")
    return p


def _fake_zig(d, rc):
    z = Path(d) / "fakezig"
    z.write_text("#!/bin/sh\necho 'PROBE PASS fake'\necho 'PROBE SUMMARY 1/1 passed'\nexit %d\n" % rc)
    z.chmod(z.stat().st_mode | stat.S_IXUSR)
    return str(z)


EXPECTED = ["balance/report.json", "fixtures/day1_0600.sav", "fixtures/day3_1900.sav", "fixtures/manifest.lua"]


class CollectOutputs(unittest.TestCase):
    def test_copies_balance_report_and_fixtures(self):
        with tempfile.TemporaryDirectory() as d:
            p = _project(d)
            logs = p / "reports" / "windows"
            got = VS.collect_outputs(str(p), str(logs))
            self.assertEqual(got, EXPECTED)
            self.assertEqual((logs / "balance" / "report.json").read_bytes(), b'{"determinism":{"ok":true}}\n')
            self.assertEqual((logs / "fixtures" / "day1_0600.sav").read_bytes(), b"\x00\x01sav-a")
            self.assertFalse((logs / "fixtures" / "make.lua").exists())

    def test_missing_outputs_are_skipped(self):
        with tempfile.TemporaryDirectory() as d:
            p = _project(d, with_outputs=False)
            logs = p / "reports" / "windows"
            self.assertEqual(VS.collect_outputs(str(p), str(logs)), [])


@unittest.skipIf(os.name == "nt", "fake zig is a shell script")
class MainCollects(unittest.TestCase):
    def _run(self, rc):
        with tempfile.TemporaryDirectory() as d:
            p = _project(d)
            zig = _fake_zig(d, rc)
            old = os.getcwd()
            os.chdir(p)
            try:
                ret = VS.main(["--zig", zig, "--log-dir", "reports/windows", "--profile", "full",
                               "--probes", "tests/probe/a.lua"])
            finally:
                os.chdir(old)
            files = sorted(str(f.relative_to(p / "reports" / "windows")).replace(os.sep, "/")
                           for f in (p / "reports" / "windows").rglob("*")
                           if f.is_file() and f.parent.name in ("balance", "fixtures"))
            return ret, files

    def test_main_collects_on_success(self):
        ret, files = self._run(0)
        self.assertEqual(ret, 0)
        self.assertEqual(files, EXPECTED)

    def test_main_collects_on_failure(self):
        ret, files = self._run(1)
        self.assertEqual(ret, 1)
        self.assertEqual(files, EXPECTED)


if __name__ == "__main__":
    unittest.main()
