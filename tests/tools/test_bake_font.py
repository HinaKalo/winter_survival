import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import bake_font


class TestBakeFont(unittest.TestCase):
    def _setup_tmp(self, tmp_path: Path):
        (tmp_path / "assets" / "i18n").mkdir(parents=True)
        (tmp_path / "assets_src").mkdir(parents=True)
        (tmp_path / "assets" / "i18n" / "zh.lua").write_text(
            'return { title = "零下三十", ok = "确定" }\n', encoding="utf-8"
        )
        (tmp_path / "assets" / "i18n" / "en.lua").write_text(
            'return { title = "Thirty Below", ok = "OK" }\n', encoding="utf-8"
        )
        (tmp_path / "assets" / "i18n" / "ko.lua").write_text(
            'return { title = "영하 삼십", ok = "확인" }\n', encoding="utf-8"
        )
        cfg = {
            "i18n_dir": "assets/i18n",
            "out_dir": "assets/fonts",
            "fallback_cp": 63,
            "extra_chars": "…",
            "sources": [
                "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            ],
            "fonts": [{"name": "test_16", "px": 16}],
        }
        (tmp_path / "assets_src" / "fonts.json").write_text(
            json.dumps(cfg), encoding="utf-8"
        )

    def test_bake_deterministic_and_check(self):
        with tempfile.TemporaryDirectory() as td:
            tmp_path = Path(td)
            self._setup_tmp(tmp_path)

            rc = bake_font.main(["--root", str(tmp_path)])
            self.assertEqual(rc, 0)

            fnt1 = (tmp_path / "assets" / "fonts" / "test_16.fnt").read_bytes()
            png1 = (tmp_path / "assets" / "fonts" / "test_16.png").read_bytes()

            self.assertEqual(bake_font.main(["--root", str(tmp_path), "--check"]), 0)

            self.assertEqual(bake_font.main(["--root", str(tmp_path)]), 0)
            fnt2 = (tmp_path / "assets" / "fonts" / "test_16.fnt").read_bytes()
            png2 = (tmp_path / "assets" / "fonts" / "test_16.png").read_bytes()
            self.assertEqual(fnt1, fnt2)
            self.assertEqual(png1, png2)

            (tmp_path / "assets" / "i18n" / "zh.lua").write_text(
                'return { title = "零下三十", extra = "雪" }\n', encoding="utf-8"
            )
            self.assertEqual(bake_font.main(["--root", str(tmp_path), "--check"]), 1)


if __name__ == "__main__":
    unittest.main()
