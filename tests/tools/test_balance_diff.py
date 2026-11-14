"""Unit tests for tools/balance_diff.py (P0-PLAN §1.3). Run: python3 -m unittest tests.tools.test_balance_diff"""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("balance_diff", ROOT / "tools" / "balance_diff.py")
BD = importlib.util.module_from_spec(spec)
spec.loader.exec_module(BD)

BASE = {"days": 30, "results": [{"seed": 1, "meals": 497, "checksum": "aaaa"}],
        "determinism": {"ok": True, "a": "aaaa", "b": "aaaa"}, "errors": []}


class BalanceDiff(unittest.TestCase):
    def _files(self, a, b):
        d = tempfile.mkdtemp()
        pa, pb = Path(d) / "a.json", Path(d) / "b.json"
        pa.write_text(json.dumps(a) if not isinstance(a, str) else a)
        pb.write_text(json.dumps(b) if not isinstance(b, str) else b)
        return str(pa), str(pb)

    def test_baseline_file_is_valid(self):
        self.assertEqual(BD.main([str(ROOT / "ci/baselines/balance_p0.json")] * 2 + ["--exact"]), 0)

    def test_checksum_change_allowed_in_summary_mode(self):
        b = json.loads(json.dumps(BASE))
        b["results"][0]["checksum"] = "bbbb"
        b["determinism"].update(a="bbbb", b="bbbb")
        self.assertEqual(BD.main(list(self._files(BASE, b))), 0)
        self.assertEqual(BD.main(list(self._files(BASE, b)) + ["--exact"]), 1)

    def test_value_change_detected(self):
        b = json.loads(json.dumps(BASE))
        b["results"][0]["meals"] = 498
        self.assertEqual(BD.main(list(self._files(BASE, b))), 1)

    def test_determinism_must_hold(self):
        b = json.loads(json.dumps(BASE))
        b["determinism"]["ok"] = False
        self.assertEqual(BD.main(list(self._files(BASE, b))), 1)

    def test_bad_input(self):
        self.assertEqual(BD.main(["/nonexistent", "/nonexistent"]), 2)
        self.assertEqual(BD.main(["only-one"]), 2)


if __name__ == "__main__":
    unittest.main()
