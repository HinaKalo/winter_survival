# 验收测试，编码代理不得修改（M2-fix，主代理编写；见 docs/M2-PLAN.md §6）。
# F2: every atlas cell referenced by assets/scripts/data/tiles.lua must have visible pixels, both in the
#     committed atlas and in what tools/art/chargen/gen_pilot.py generates (it must start from the full
#     placeholder atlas and replace only the pilot cells).
# F6: every `--script <path>` launch documented outside tests/ must name a script that defines the
#     global lifecycle hooks (_init / _update), otherwise the documented command shows nothing.
import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TILES_LUA = ROOT / "assets" / "scripts" / "data" / "tiles.lua"
ATLAS = ROOT / "assets" / "textures" / "tiles.png"
CELL = 64
COLS = 8
MIN_VISIBLE = 0.5  # fraction of a referenced cell that must be non-transparent

try:
    import PIL.Image as PILImage
except ImportError:  # pragma: no cover
    PILImage = None


def referenced_cells():
    """Atlas slots used by data/tiles.lua: integer literals among def()'s first four arguments plus the
    WALLS / DOORS slot tables (looked up through variables in the def() calls)."""
    src = TILES_LUA.read_text(encoding="utf-8")
    cells = set()
    for args in re.findall(r"\bdef\(([^)]*)\)", src):
        for a in args.split(",")[:4]:
            a = a.strip()
            if re.fullmatch(r"\d+", a):
                cells.add(int(a))
    for table in ("WALLS", "DOORS"):
        m = re.search(table + r"\s*=\s*\{([^}]*)\}", src)
        if m:
            cells.update(int(v) for v in re.findall(r"=\s*(\d+)", m.group(1)))
    return sorted(cells)


def visible_fraction(img, cell):
    x0, y0 = (cell % COLS) * CELL, (cell // COLS) * CELL
    alpha = img.crop((x0, y0, x0 + CELL, y0 + CELL)).getchannel("A")
    return sum(1 for a in alpha.getdata() if a > 0) / (CELL * CELL)


@unittest.skipIf(PILImage is None, "Pillow not installed")
class AtlasCellsTest(unittest.TestCase):
    def test_reference_parser_sees_known_slots(self):
        cells = referenced_cells()
        for c in (0, 24, 40, 41, 42, 43, 53, 56, 60, 61):
            self.assertIn(c, cells)

    def test_committed_atlas_has_every_referenced_cell(self):
        img = PILImage.open(ATLAS).convert("RGBA")
        empty = [c for c in referenced_cells() if visible_fraction(img, c) < MIN_VISIBLE]
        self.assertEqual(empty, [], f"transparent atlas cells used by tiles.lua: {empty}")

    def test_pilot_generator_keeps_every_referenced_cell(self):
        spec = importlib.util.spec_from_file_location("gen_pilot", ROOT / "tools" / "art" / "chargen" / "gen_pilot.py")
        gp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gp)
        img = gp.make_tiles(gp.load_palette()).convert("RGBA")
        self.assertEqual(img.size, (CELL * COLS, CELL * COLS))
        empty = [c for c in referenced_cells() if visible_fraction(img, c) < MIN_VISIBLE]
        self.assertEqual(empty, [], f"gen_pilot.make_tiles leaves referenced cells transparent: {empty}")


DOC_GLOBS = ("README.md", "docs/*.md", "tools/*.sh", "tools/*.py", "ci/*", "build.zig")
SCRIPT_RE = re.compile(r"--script[ =]+([A-Za-z0-9_./-]+\.lua)")


class ScriptEntryTest(unittest.TestCase):
    def documented_scripts(self):
        found = {}
        for pattern in DOC_GLOBS:
            for f in ROOT.glob(pattern):
                if not f.is_file():
                    continue
                for path in SCRIPT_RE.findall(f.read_text(encoding="utf-8", errors="replace")):
                    if path.startswith("tests/") or path in ("x.lua", "path.lua"):
                        continue  # test entry points run under --probe; placeholders in usage text
                    found.setdefault(path, []).append(f.relative_to(ROOT).as_posix())
        return found

    def test_documented_script_entries_are_runnable(self):
        bad = []
        for path, where in sorted(self.documented_scripts().items()):
            target = ROOT / path
            if not target.is_file():
                bad.append(f"{path} (missing; cited in {where})")
                continue
            src = target.read_text(encoding="utf-8")
            if not re.search(r"^\s*function\s+_init\s*\(", src, re.M) or not re.search(r"^\s*function\s+_update\s*\(", src, re.M):
                bad.append(f"{path} (no global _init/_update; cited in {where})")
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
