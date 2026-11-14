import importlib.util
import io
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import unittest.mock
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("new_game_tool", ROOT / "tools" / "new_game.py")
G = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(G)

# Starter tokens are assembled at runtime so this file does not contain the literal tokens the generator
# rewrites (this file is copied into generated projects).
TOK_PKG = "delve" + "_starter"
TOK_EXE = "starter" + "-game"
TOK_TITLE = "Delve" + " Starter"
TOK_DIR = "delve" + "-starter"

# Scratch base for test temp dirs; override with NEW_GAME_TEST_TMP. Falls back to the default temp dir.
SCRATCH_BASE = os.environ.get(
    "NEW_GAME_TEST_TMP",
    "/tmp/claude-1000/-home-smile-user-dev/9b02ef68-c3b7-4c4d-b088-18a720259dc2/scratchpad/k4a",
)


def make_tmp() -> Path:
    try:
        os.makedirs(SCRATCH_BASE, exist_ok=True)
        return Path(tempfile.mkdtemp(dir=SCRATCH_BASE))
    except OSError:
        return Path(tempfile.mkdtemp())


def fx(text: str) -> str:
    """Fill fixture placeholders with the starter tokens."""
    return text.replace("@PKG@", TOK_PKG).replace("@EXE@", TOK_EXE).replace("@TITLE@", TOK_TITLE).replace(
        "@DIR@", TOK_DIR
    )


ZON = fx(
    """.{
    .name = .@PKG@,
    .version = "0.1.0",
    .fingerprint = 0x978ac506d51138f4,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .delve = .{
            .path = "../delve-framework",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "assets",
    },
}
"""
)

BUILD_ZIG = fx('const exe = b.addExecutable(.{ .name = "@EXE@" });\n')

MAIN_ZIG = fx('const title = "@TITLE@";\nconst usage = "usage: @EXE@ [--probe <file.lua>]\\n";\n')

README = fx("# @TITLE@\n\nRun with `@EXE@`, folder @DIR@.\n")


def make_fake_layout(base: Path) -> Path:
    """Create base/delve-framework (a sibling framework) and base/starter (a mini starter). Returns starter root."""
    fw = base / "delve-framework"
    fw.mkdir(parents=True)
    (fw / "build.zig").write_text("// framework\n", encoding="utf-8")

    root = base / "starter"
    files = {
        "build.zig": BUILD_ZIG,
        "build.zig.zon": ZON,
        "README.md": README,
        "src/main.zig": MAIN_ZIG,
        "assets/scripts/out.lua": "-- nested out.lua must be kept\n",
        "assets/out/keep.txt": "nested out dir must be kept\n",
        "assets/out.lua": "-- top-level assets file\n",
        "docs/notes.md": fx("notes for @DIR@\n"),
        "docs/STARTER-PLAN.md": "plan\n",
        "out/o.txt": "top-level out excluded\n",
        "reports/r.txt": "top-level reports excluded\n",
        "src/zig-out/y.txt": "nested zig-out excluded\n",
        "zig-out/bin/x": "bin\n",
        "zig-pkg/p.txt": "pkg\n",
        ".zig-cache/c.txt": "cache\n",
        "__pycache__/m.pyc": "pyc",
        "src/__pycache__/n.txt": "pycache\n",
        ".git/config": "[core]\n",
        ".gitignore": "zig-out/\n",
    }
    for rel, content in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
    # Binary / non-text fixtures (must never be text-replaced).
    (root / "assets/img.png").write_bytes(fx("@EXE@ @TITLE@ @DIR@").encode("utf-8"))
    (root / "assets/nul.txt").write_bytes(fx("@EXE@").encode("utf-8") + b"\x00")
    (root / "assets/bad.txt").write_bytes(b"\xff " + fx("@EXE@").encode("utf-8"))
    return root


def fingerprint_of(zon_text: str) -> int:
    m = re.search(r"\.fingerprint\s*=\s*(0x[0-9a-fA-F]+),", zon_text)
    assert m, zon_text
    return int(m.group(1), 16)


def zon_path_of(zon_text: str) -> str:
    m = re.search(r'\.delve\s*=\s*\.\{\s*\.path\s*=\s*"([^"]*)"', zon_text)
    assert m, zon_text
    return m.group(1)


class NewGameTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = make_tmp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.base = self.tmp / "work"
        self.base.mkdir()
        self.root = make_fake_layout(self.base)
        # CLI entry point (main) uses G.ROOT; point it at the fake starter.
        patcher = unittest.mock.patch.object(G, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_main(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = G.main(argv)
        return code, out.getvalue(), err.getvalue()


class NameValidationTest(NewGameTestBase):
    def test_valid_names(self):
        for name in ["a", "demo", "demo_probe_game", "a1_b2", "a" * 32]:
            G.validate_name(name)

    def test_invalid_names(self):
        for name in ["", "Demo", "1abc", "_abc", "a-b", "a b", "a" * 33, "abc\n", "abc.d", "é"]:
            with self.subTest(name=name), self.assertRaises(G.UsageError):
                G.validate_name(name)

    def test_invalid_name_cli_exit_2_creates_nothing(self):
        dest = self.base / "should-not-exist"
        code, _out, err = self.run_main(["Bad-Name", "--dest", str(dest)])
        self.assertEqual(code, 2)
        self.assertIn("invalid NAME", err)
        self.assertFalse(dest.exists())

    def test_invalid_title_rejected(self):
        for title in ['My "Game"', "back\\slash", "  ", "tab\there"]:
            with self.subTest(title=title), self.assertRaises(G.UsageError):
                G.create_game(self.root, "demo_game", dest=str(self.base / "g"), title=title)
        self.assertFalse((self.base / "g").exists())


class DefaultsTest(NewGameTestBase):
    def test_default_title(self):
        self.assertEqual(G.default_title("demo_probe_game"), "Demo Probe Game")
        self.assertEqual(G.default_title("demo"), "Demo")

    def test_default_dest_is_sibling_with_dashes(self):
        self.assertEqual(G.default_dest(self.root, "demo_probe_game"), self.base / "demo-probe-game")

    def test_default_dest_and_title_used(self):
        result = G.create_game(self.root, "demo_probe_game")
        self.assertEqual(result.dest, (self.base / "demo-probe-game").resolve())
        self.assertEqual(result.title, "Demo Probe Game")
        self.assertIn('const title = "Demo Probe Game";', (result.dest / "src/main.zig").read_text("utf-8"))


class FingerprintTest(NewGameTestBase):
    def test_upper_bits_are_crc32_and_lower_in_range(self):
        for i in range(20):
            result = G.create_game(self.root, "demo_game", dest=str(self.base / f"g{i}"))
            zon = (result.dest / "build.zig.zon").read_text("utf-8")
            fp = fingerprint_of(zon)
            self.assertEqual(fp >> 32, zlib.crc32(b"demo_game"))
            low = fp & 0xFFFFFFFF
            self.assertNotIn(low, (0, 0xFFFFFFFF))
            self.assertRegex(result.fingerprint, r"^0x[0-9a-f]{16}$")
            self.assertEqual(int(result.fingerprint, 16), fp)

    def test_random_bounds(self):
        with unittest.mock.patch.object(G.secrets, "randbelow", return_value=0):
            self.assertEqual(G.make_fingerprint("abc") & 0xFFFFFFFF, 1)
        with unittest.mock.patch.object(G.secrets, "randbelow", return_value=0xFFFFFFFD):
            self.assertEqual(G.make_fingerprint("abc") & 0xFFFFFFFF, 0xFFFFFFFE)

    def test_fingerprint_text_format(self):
        with unittest.mock.patch.object(G.secrets, "randbelow", return_value=0):
            result = G.create_game(self.root, "demo_game", dest=str(self.base / "fp"))
        self.assertEqual(result.fingerprint, f"0x{zlib.crc32(b'demo_game'):08x}00000001")
        zon = (result.dest / "build.zig.zon").read_text("utf-8")
        self.assertIn(f".fingerprint = {result.fingerprint},", zon)


class TokenReplacementTest(NewGameTestBase):
    def setUp(self):
        super().setUp()
        self.result = G.create_game(
            self.root, "demo_probe_game", dest=str(self.base / "demo-out"), title="Demo Probe Title"
        )
        self.dest = self.result.dest

    def test_build_zig(self):
        text = (self.dest / "build.zig").read_text("utf-8")
        self.assertIn('.name = "demo_probe_game"', text)
        self.assertNotIn(TOK_EXE, text)

    def test_build_zig_zon(self):
        text = (self.dest / "build.zig.zon").read_text("utf-8")
        self.assertIn(".name = .demo_probe_game,", text)
        self.assertNotIn(TOK_PKG, text)

    def test_main_zig(self):
        text = (self.dest / "src/main.zig").read_text("utf-8")
        self.assertIn('const title = "Demo Probe Title";', text)
        self.assertIn("usage: demo_probe_game", text)
        self.assertNotIn(TOK_TITLE, text)

    def test_readme(self):
        text = (self.dest / "README.md").read_text("utf-8")
        self.assertIn("# Demo Probe Title", text)
        self.assertIn("demo_probe_game", text)
        self.assertIn("folder demo-out", text)

    def test_binary_nul_and_non_utf8_files_untouched(self):
        self.assertEqual((self.dest / "assets/img.png").read_bytes(), fx("@EXE@ @TITLE@ @DIR@").encode("utf-8"))
        self.assertEqual((self.dest / "assets/nul.txt").read_bytes(), fx("@EXE@").encode("utf-8") + b"\x00")
        self.assertEqual((self.dest / "assets/bad.txt").read_bytes(), b"\xff " + fx("@EXE@").encode("utf-8"))

    def test_text_files_have_no_forbidden_tokens(self):
        for p in self.dest.rglob("*"):
            if not p.is_file() or p.suffix.lower() in G.BINARY_EXTS or p.name in ("nul.txt", "bad.txt"):
                continue
            text = p.read_text("utf-8")
            for t in G.FORBIDDEN_TOKENS:
                self.assertNotIn(t, text, str(p))

    def test_replacement_is_single_pass(self):
        # A title containing a token must not be re-replaced by a later rule.
        r = G.create_game(self.root, "demo_x", dest=str(self.base / "sp"), title=TOK_EXE)
        self.assertIn(f'const title = "{TOK_EXE}";', (r.dest / "src/main.zig").read_text("utf-8"))


class ExcludeTest(NewGameTestBase):
    def test_excludes_and_nested_names_kept(self):
        result = G.create_game(self.root, "demo_game", dest=str(self.base / "ex"))
        d = result.dest
        for rel in [
            ".git",
            ".zig-cache",
            "zig-out",
            "zig-pkg",
            "__pycache__",
            "src/__pycache__",
            "src/zig-out",
            "out",
            "reports",
            "docs/STARTER-PLAN.md",
        ]:
            with self.subTest(rel=rel):
                self.assertFalse((d / rel).exists(), rel)
        self.assertTrue((d / "assets/scripts/out.lua").is_file())
        self.assertTrue((d / "assets/out.lua").is_file())
        self.assertTrue((d / "assets/out/keep.txt").is_file())
        self.assertTrue((d / "docs/notes.md").is_file())
        self.assertTrue((d / ".gitignore").is_file())
        self.assertTrue((d / "build.zig.zon").is_file())

    def test_ignore_function_directly(self):
        ignore = G._make_ignore(self.root)
        self.assertEqual(
            ignore(str(self.root), ["out", "reports", ".git", "out.lua", "src"]), {"out", "reports", ".git"}
        )
        self.assertEqual(ignore(str(self.root / "assets"), ["out", "out.lua"]), set())
        self.assertEqual(
            ignore(str(self.root / "src"), ["zig-out", "x.pyc", "__pycache__"]),
            {"zig-out", "x.pyc", "__pycache__"},
        )


class DestTest(NewGameTestBase):
    def test_nonempty_dest_refused(self):
        dest = self.base / "busy"
        dest.mkdir()
        (dest / "keep.txt").write_text("mine\n", encoding="utf-8")
        code, _out, err = self.run_main(["demo_game", "--dest", str(dest)])
        self.assertEqual(code, 1)
        self.assertIn("not empty", err)
        self.assertEqual((dest / "keep.txt").read_text("utf-8"), "mine\n")
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ["keep.txt"])

    def test_empty_existing_dest_is_used_and_kept(self):
        dest = self.base / "empty"
        dest.mkdir()
        result = G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual(result.dest, dest.resolve())
        self.assertTrue((dest / "build.zig").is_file())

    def test_dest_is_file_refused(self):
        dest = self.base / "afile"
        dest.write_text("x", encoding="utf-8")
        with self.assertRaises(G.NewGameError):
            G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual(dest.read_text("utf-8"), "x")

    def test_dest_inside_starter_refused(self):
        dest = self.root / "nested-game"
        with self.assertRaises(G.UsageError):
            G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertFalse(dest.exists())


class DelvePathTest(NewGameTestBase):
    def test_default_sibling_stays_relative_sibling(self):
        result = G.create_game(self.root, "demo_game", dest=str(self.base / "sib"))
        self.assertEqual(zon_path_of((result.dest / "build.zig.zon").read_text("utf-8")), "../delve-framework")
        self.assertEqual(result.framework, (self.base / "delve-framework").resolve())

    def test_custom_delve_rewrites_relative_path(self):
        fw = self.tmp / "libs" / "fw"
        fw.mkdir(parents=True)
        (fw / "build.zig").write_text("//\n", encoding="utf-8")
        dest = self.tmp / "games" / "g1"
        result = G.create_game(self.root, "demo_game", dest=str(dest), delve=str(fw))
        rel = zon_path_of((result.dest / "build.zig.zon").read_text("utf-8"))
        self.assertEqual(rel, "../../libs/fw")
        self.assertEqual(os.path.normpath(result.dest / rel), str(fw.resolve()))
        self.assertNotIn("\\", rel)

    def test_nonsibling_dest_with_default_framework(self):
        dest = self.tmp / "x" / "deep" / "proj"
        result = G.create_game(self.root, "demo_game", dest=str(dest))
        rel = zon_path_of((result.dest / "build.zig.zon").read_text("utf-8"))
        self.assertEqual(rel, "../../../work/delve-framework")

    def test_missing_framework_is_error_and_creates_nothing(self):
        dest = self.tmp / "nofw"
        code, _out, err = self.run_main(["demo_game", "--dest", str(dest), "--delve", str(self.tmp / "nope")])
        self.assertEqual(code, 1)
        self.assertIn("delve framework not found", err)
        self.assertFalse(dest.exists())

    def test_framework_without_build_zig_is_error(self):
        empty_fw = self.tmp / "emptyfw"
        empty_fw.mkdir()
        with self.assertRaises(G.NewGameError):
            G.create_game(self.root, "demo_game", dest=str(self.tmp / "e2"), delve=str(empty_fw))
        self.assertFalse((self.tmp / "e2").exists())


class CleanupTest(NewGameTestBase):
    def test_failure_after_create_removes_dir(self):
        dest = self.base / "failing"
        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=OSError("boom")):
            code, _out, err = self.run_main(["demo_game", "--dest", str(dest)])
        self.assertEqual(code, 1)
        self.assertIn("boom", err)
        self.assertFalse(dest.exists())

    def test_failure_in_verify_removes_dir(self):
        dest = self.base / "failing2"
        with unittest.mock.patch.object(G, "_verify_no_leftovers", side_effect=G.NewGameError("leftover")):
            with self.assertRaises(G.NewGameError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertFalse(dest.exists())

    def test_failure_with_preexisting_empty_dir_keeps_dir_empty(self):
        dest = self.base / "preexisting"
        dest.mkdir()
        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertTrue(dest.is_dir())
        self.assertEqual(list(dest.iterdir()), [])

    def test_missing_fingerprint_is_clean_error_and_cleans_up(self):
        (self.root / "build.zig.zon").write_text(ZON.replace(".fingerprint = 0x978ac506d51138f4,", ""), "utf-8")
        dest = self.base / "nofp"
        code, _out, err = self.run_main(["demo_game", "--dest", str(dest)])
        self.assertEqual(code, 1)
        self.assertIn(".fingerprint", err)
        self.assertNotIn("Traceback", err)
        self.assertFalse(dest.exists())

    def test_failure_removes_created_parent_dirs_but_not_existing_ones(self):
        parent = self.tmp / "A_parent"
        dest = parent / "child" / "proj"
        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertFalse(parent.exists())
        self.assertTrue(self.tmp.is_dir())


def staging_dirs(parent: Path) -> list[str]:
    return sorted(p.name for p in parent.iterdir() if p.name.startswith(".new_game-"))


class RaceCleanupTest(NewGameTestBase):
    """Another actor writes into the filesystem while we run; we must never delete what we did not create."""

    def write_victim(self, victim: Path) -> None:
        victim.parent.mkdir(parents=True, exist_ok=True)
        victim.write_text("theirs\n", encoding="utf-8")

    def test_race1_preexisting_empty_dest_written_then_generation_fails(self):
        dest = self.base / "r1"
        dest.mkdir()
        victim = dest / "victim.txt"

        def boom(*_a, **_k):
            self.write_victim(victim)
            raise OSError("boom")

        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=boom):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual(victim.read_text("utf-8"), "theirs\n")
        self.assertEqual([p.name for p in dest.iterdir()], ["victim.txt"])
        self.assertEqual(staging_dirs(self.base), [])

    def test_race1b_preexisting_empty_dest_written_then_generation_succeeds(self):
        dest = self.base / "r1b"
        dest.mkdir()
        victim = dest / "victim.txt"
        orig = G._verify_no_leftovers

        def hook(*a, **k):
            orig(*a, **k)
            self.write_victim(victim)

        with unittest.mock.patch.object(G, "_verify_no_leftovers", side_effect=hook):
            with self.assertRaises(G.NewGameError) as cm:
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertIn("no longer empty", str(cm.exception))
        self.assertEqual([p.name for p in dest.iterdir()], ["victim.txt"])
        self.assertEqual(victim.read_text("utf-8"), "theirs\n")
        self.assertEqual(staging_dirs(self.base), [])

    def test_race2_dest_created_by_other_before_commit(self):
        dest = self.base / "r2"
        victim = dest / "victim.txt"
        orig = G._verify_no_leftovers

        def hook(*a, **k):
            orig(*a, **k)
            self.write_victim(victim)

        with unittest.mock.patch.object(G, "_verify_no_leftovers", side_effect=hook):
            with self.assertRaises(G.NewGameError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual([p.name for p in dest.iterdir()], ["victim.txt"])
        self.assertEqual(victim.read_text("utf-8"), "theirs\n")
        self.assertEqual(staging_dirs(self.base), [])

    def test_race3_topmost_ancestor_created_by_other_before_mkdir(self):
        top = self.base / "P"
        dest = top / "mid" / "proj"
        victim = top / "other" / "victim.txt"
        real_mkdir = os.mkdir

        def racing_mkdir(path, *a, **k):
            if Path(path) == top:
                self.write_victim(victim)
            return real_mkdir(path, *a, **k)

        with unittest.mock.patch.object(G.os, "mkdir", side_effect=racing_mkdir):
            with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=OSError("boom")):
                with self.assertRaises(OSError):
                    G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual(victim.read_text("utf-8"), "theirs\n")
        self.assertTrue(top.is_dir())
        # mid was created by us and is removed; P is not ours and stays.
        self.assertFalse((top / "mid").exists())
        self.assertEqual(staging_dirs(top / "mid") if (top / "mid").exists() else [], [])

    def test_failure_removes_created_ancestors_but_keeps_existing(self):
        existing = self.base / "existing"
        existing.mkdir()
        dest = existing / "new" / "proj"
        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertTrue(existing.is_dir())
        self.assertEqual(list(existing.iterdir()), [])

    def test_failure_keeps_foreign_content_in_created_ancestor(self):
        existing = self.base / "existing2"
        existing.mkdir()
        new = existing / "new"
        dest = new / "proj"

        def boom(*_a, **_k):
            self.write_victim(new / "victim.txt")
            raise OSError("boom")

        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=boom):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual((new / "victim.txt").read_text("utf-8"), "theirs\n")
        self.assertEqual([p.name for p in new.iterdir()], ["victim.txt"])

    def test_symlinked_existing_ancestor_stays_intact(self):
        real = self.base / "realdir"
        real.mkdir()
        (real / "keep.txt").write_text("keep\n", encoding="utf-8")
        link = self.base / "link"
        os.symlink(real, link)
        with unittest.mock.patch.object(G, "_rewrite_zon", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(link / "proj"))
        self.assertTrue(link.is_symlink())
        self.assertEqual(sorted(p.name for p in real.iterdir()), ["keep.txt"])

    def test_success_into_preexisting_empty_dest_leaves_no_staging(self):
        dest = self.base / "okempty"
        dest.mkdir()
        G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertTrue((dest / "build.zig.zon").is_file())
        self.assertEqual(staging_dirs(self.base), [])
        self.assertEqual(staging_dirs(dest), [])

    def test_success_into_new_dest_leaves_no_staging(self):
        dest = self.base / "oknew"
        G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertTrue((dest / "build.zig.zon").is_file())
        self.assertEqual(staging_dirs(self.base), [])
        self.assertEqual(staging_dirs(dest), [])
        self.assertEqual(os.stat(dest).st_mode & 0o777, 0o777 & ~self._umask())

    def test_new_dest_mode_follows_umask_not_starter_mode(self):
        os.chmod(self.root, 0o755)
        dest = self.base / "modecheck"
        with unittest.mock.patch.object(G, "_current_umask", return_value=0o002):
            G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual(os.stat(dest).st_mode & 0o777, 0o775)

    def test_failed_move_back_leaves_entries_and_reports_them(self):
        dest = self.base / "stuck"
        dest.mkdir()
        real_rename = os.rename
        state = {"moved": 0}

        def flaky(src, dst, *a, **k):
            src_p, dst_p = Path(src), Path(dst)
            if dst_p.parent == dest:  # move-in
                state["moved"] += 1
                if state["moved"] == 2:
                    raise OSError("boom in")
            elif src_p.parent == dest:  # move-back
                raise OSError("boom back")
            return real_rename(src, dst, *a, **k)

        with unittest.mock.patch.object(G.os, "rename", side_effect=flaky):
            with self.assertRaises(G.NewGameError) as cm:
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertIn("remove them by hand", str(cm.exception))
        left = sorted(os.listdir(dest))
        self.assertEqual(len(left), 1)  # the first moved entry stays in DEST, not deleted
        self.assertIn(left[0], str(cm.exception))
        self.assertEqual(staging_dirs(self.base), [])

    @staticmethod
    def _umask() -> int:
        m = os.umask(0)
        os.umask(m)
        return m

    def test_failure_mid_move_restores_and_keeps_dest_empty(self):
        dest = self.base / "midmove"
        dest.mkdir()
        real_rename = os.rename
        calls = {"n": 0}

        def flaky(src, dst, *a, **k):
            calls["n"] += 1
            if calls["n"] == 3:
                raise OSError("rename boom")
            return real_rename(src, dst, *a, **k)

        with unittest.mock.patch.object(G.os, "rename", side_effect=flaky):
            with self.assertRaises(OSError):
                G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertEqual(list(dest.iterdir()), [])
        self.assertEqual(staging_dirs(self.base), [])


class DestNameTest(NewGameTestBase):
    def test_valid_dest_names(self):
        for name in ["demo-game", "a", "A1", "my.game_v2", "x" * 64, "0lead"]:
            with self.subTest(name=name):
                G.validate_dest_name(name)

    def test_invalid_dest_names(self):
        for name in ["", "-lead", ".hidden", "bad name", "semi;colon", "a$b", "a\"b", "é", "x" * 65, "a\nb"]:
            with self.subTest(name=name), self.assertRaises(G.UsageError):
                G.validate_dest_name(name)

    def test_invalid_dest_name_creates_nothing(self):
        dest = self.base / "bad name"
        with self.assertRaises(G.UsageError):
            G.create_game(self.root, "demo_game", dest=str(dest))
        self.assertFalse(dest.exists())

    def test_invalid_dest_name_cli_exit_2(self):
        dest = self.base / "bad;name"
        code, _out, err = self.run_main(["demo_game", "--dest", str(dest)])
        self.assertEqual(code, 2)
        self.assertIn("invalid DEST directory name", err)
        self.assertIn("[A-Za-z0-9][A-Za-z0-9._-]{0,63}", err)
        self.assertFalse(dest.exists())


class ZigPathTest(NewGameTestBase):
    def test_framework_path_with_unsafe_chars_rejected_before_creating(self):
        for dirname in ['lib"x', "lib\\x", "lib\tx"]:
            with self.subTest(dirname=dirname):
                fw = self.tmp / dirname / "fw"
                fw.mkdir(parents=True)
                (fw / "build.zig").write_text("//\n", encoding="utf-8")
                dest = self.tmp / "games" / "unsafe"
                with self.assertRaises(G.NewGameError) as cm:
                    G.create_game(self.root, "demo_game", dest=str(dest), delve=str(fw))
                self.assertIn("contains a quote, backslash or control character", str(cm.exception))
                self.assertFalse(dest.exists())


class LeftoverCheckTest(NewGameTestBase):
    def test_leftover_dir_token_detected(self):
        tree = self.tmp / "leftover"
        tree.mkdir()
        (tree / "README.md").write_text(f"see {TOK_DIR}\n", encoding="utf-8")
        with self.assertRaises(G.NewGameError) as cm:
            G._verify_no_leftovers(tree, ["demo_game", "Demo Game", "other-dir"])
        self.assertIn(TOK_DIR, str(cm.exception))

    def test_dir_token_allowed_when_basename_contains_it(self):
        tree = self.tmp / "allowed"
        tree.mkdir()
        (tree / "README.md").write_text(f"folder {TOK_DIR}\n", encoding="utf-8")
        G._verify_no_leftovers(tree, ["demo_game", "Demo Game", TOK_DIR])


@unittest.skipUnless(shutil.which("git"), "git not available")
class GitTest(NewGameTestBase):
    def test_git_init_and_initial_commit(self):
        identity = {
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid",
        }
        dest = self.base / "gitgame"
        with unittest.mock.patch.dict(os.environ, identity):
            result = G.create_game(self.root, "demo_game", dest=str(dest), git=True)
        self.assertTrue(result.git_initialized)
        branch = subprocess.run(
            ["git", "-C", str(dest), "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
        self.assertEqual(branch, "main")
        subject = subprocess.run(
            ["git", "-C", str(dest), "log", "-1", "--format=%s"], capture_output=True, text=True
        ).stdout.strip()
        self.assertEqual(subject, f"Initial demo_game from {TOK_DIR} unknown")
        self.assertFalse((dest / ".zig-cache").exists())

    def test_git_failure_keeps_generated_files(self):
        dest = self.base / "gitfail"
        with unittest.mock.patch.object(G, "_git_init_commit", side_effect=G.NewGameError("git commit failed: boom")):
            with self.assertRaises(G.NewGameError) as cm:
                G.create_game(self.root, "demo_game", dest=str(dest), git=True)
        self.assertIn("kept in", str(cm.exception))
        self.assertTrue((dest / "build.zig.zon").is_file())


class SummaryTest(NewGameTestBase):
    def test_cli_success_prints_summary(self):
        dest = self.base / "summary-game"
        code, out, err = self.run_main(["demo_game", "--dest", str(dest), "--title", "Demo Title"])
        self.assertEqual(code, 0, err)
        self.assertIn("Demo Title", out)
        self.assertIn("demo_game", out)
        self.assertIn("0x", out)
        self.assertIn("cd ", out)
        self.assertIn("mise exec -- zig build run", out)


if __name__ == "__main__":
    unittest.main()
