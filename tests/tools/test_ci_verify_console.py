"""验收测试（主代理编写）：Jenkins 控制台日志含非 UTF-8 字节（Windows 代码页输出）时，
tools/ci_verify.sh 仍能解析出构建号和结果（CI 自测 #5 因此没有下载产物）。"""
import stat
import unittest
from pathlib import Path

from tests.tools.test_ci_verify_fix import CiVerifyScript

BINARY_JAVA = r"""#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
printf 'Started winter_survival-verify #7\n'
printf '[2026] \xb9\xd9\xc0\xcc\xb3\xca\xb8\xae \x00 cp949 console bytes\n'
printf 'Finished: %s\n' "${FAKE_RESULT:-SUCCESS}"
exit 0
"""


class BinaryConsoleLog(CiVerifyScript):
    def setUp(self):
        super().setUp()
        java = Path(self.tmp.name) / "bin" / "java"
        java.write_text(BINARY_JAVA)
        java.chmod(java.stat().st_mode | stat.S_IXUSR)

    def test_build_number_and_result_parsed_from_binary_console(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("build: #7 result: SUCCESS", r.stdout)

    def test_failure_parsed_from_binary_console(self):
        r = self.run_script(result="FAILURE")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("result: FAILURE", r.stdout)

    # the inherited tests run again with the binary console; harmless and cheap


if __name__ == "__main__":
    unittest.main()
