import importlib.util
import itertools
import json
import shutil
import struct
import tempfile
import unittest
import unittest.mock
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("assets_tool", ROOT / "tools" / "assets.py")
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

try:
    import PIL.Image as PILImage
except ImportError:
    PILImage = None


def write_wav(path, channels=1, rate=48000, frames=100):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * channels * frames)


def _ogg_crc_table():
    t = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
            r &= 0xFFFFFFFF
        t.append(r)
    return t


_CRC = _ogg_crc_table()


def ogg_crc(page: bytes) -> int:
    """Ogg page CRC: poly 0x04c11db7, init 0, no reflection, no final xor, CRC field (bytes 22..25) zeroed."""
    page = page[:22] + b"\0\0\0\0" + page[26:]
    crc = 0
    for b in page:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _CRC[((crc >> 24) & 0xFF) ^ b]
    return crc


def ogg_edit(data: bytes, granule=None, which="last", serial=None, version=None) -> bytes:
    """Rewrite pages of an Ogg file. granule (int) is applied to the last page or to all pages except the first
    (`which` = "last" | "all_after_header" | "all"); the page CRC is recomputed so the file stays valid
    (the parser does not verify CRCs, but fixtures stay well-formed anyway)."""
    pages, pos = [], 0
    while pos < len(data):
        nseg = data[pos + 26]
        end = pos + 27 + nseg + sum(data[pos + 27:pos + 27 + nseg])
        pages.append(bytearray(data[pos:end]))
        pos = end
    for idx, pg in enumerate(pages):
        if granule is not None and (which == "all" or (which == "last" and idx == len(pages) - 1)
                                    or (which == "all_after_header" and idx > 0)):
            pg[6:14] = struct.pack("<q", granule)
        if serial is not None and idx == len(pages) - 1:
            pg[14:18] = struct.pack("<I", serial)
        if version is not None and idx == 0:
            nseg = pg[26]
            pg[27 + nseg + 7:27 + nseg + 11] = struct.pack("<I", version)
        pg[22:26] = struct.pack("<I", ogg_crc(bytes(pg)))
    return b"".join(bytes(p) for p in pages)


class HeaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_wav_ok(self):
        p = self.tmp / "a.wav"
        write_wav(p, 2, 44100, 123)
        self.assertEqual(A.parse_audio_file(p), {"frames": 123, "sample_rate": 44100, "channels": 2})

    def test_wav_truncated_and_garbage(self):
        p = self.tmp / "a.wav"
        write_wav(p, 1, 48000, 100)
        data = p.read_bytes()
        for bad in (data[:10], data[:30], data[:-50], b"", b"garbage" * 20):
            q = self.tmp / "b.wav"
            q.write_bytes(bad)
            with self.assertRaises(A.AssetError):
                A.parse_audio_file(q)

    def test_ogg_seeded(self):
        p = ROOT / "assets" / "audio" / "bgm" / "street_chip.ogg"
        h = A.parse_audio_file(p)
        self.assertEqual((h["sample_rate"], h["channels"]), (48000, 2))
        self.assertEqual(h["frames"], 1228800)

    def test_ogg_truncated_and_garbage(self):
        data = (ROOT / "assets" / "audio" / "bgm" / "street_chip.ogg").read_bytes()
        for bad in (data[:20], data[:100], data[:len(data) // 2], data[:-7], b"", b"OggS" + b"\0" * 10,
                    b"garbage" * 50):
            q = self.tmp / "b.ogg"
            q.write_bytes(bad)
            with self.assertRaises(A.AssetError):
                A.parse_audio_file(q)

    def _street(self):
        return (ROOT / "assets" / "audio" / "bgm" / "street_chip.ogg").read_bytes()

    def _parse(self, data):
        q = self.tmp / "x.ogg"
        q.write_bytes(data)
        return A.parse_audio_file(q)

    def test_ogg_crc_helper_matches_real_file(self):
        data = self._street()
        self.assertEqual(ogg_edit(data), data)  # recomputed CRCs equal the real ones

    def test_ogg_last_page_granule_minus_one_uses_previous(self):
        data = self._street()
        h = self._parse(ogg_edit(data, -1, "last"))
        self.assertGreater(h["frames"], 0)
        self.assertLessEqual(h["frames"], 1228800)

    def test_ogg_all_granules_minus_one(self):
        with self.assertRaises(A.AssetError):
            self._parse(ogg_edit(self._street(), -1, "all_after_header"))
        with self.assertRaises(A.AssetError):
            self._parse(ogg_edit(self._street(), -1, "all"))

    def test_ogg_zero_frames_and_bad_serial_and_version(self):
        for kw in ({"granule": 0, "which": "all"}, {"serial": 12345}, {"version": 1}):
            with self.assertRaises(A.AssetError, msg=str(kw)):
                self._parse(ogg_edit(self._street(), **kw))


class LuaScanTests(unittest.TestCase):
    def test_scan(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        (tmp / "assets" / "scripts").mkdir(parents=True)
        (tmp / "assets" / "scripts" / "x.lua").write_text(
            'audio.sfx("sfx/ui")\naudio.bgm( \'bgm/a\', 2)\naudio.sfx_var("sfx/b", 1)\n'
            '-- audio.sfx("sfx/commented")\naudio.sfx(var)\n')
        got = [(fn, i) for _f, _n, fn, i in A.scan_lua(tmp)]
        self.assertEqual(got, [("sfx", "sfx/ui"), ("bgm", "bgm/a"), ("sfx_var", "sfx/b")])

    def _scan(self, text):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        (tmp / "assets").mkdir()
        (tmp / "assets" / "x.lua").write_text(text)
        return [(n, fn, i) for _f, n, fn, i in A.scan_lua(tmp)]

    def test_block_comments(self):
        got = self._scan('--[[ audio.sfx("sfx/a") ]] audio.sfx("sfx/b")\n'
                         '--[==[\naudio.sfx("sfx/c")\n]]  audio.sfx("sfx/d")\n]==]\naudio.bgm("bgm/e")\n')
        self.assertEqual(got, [(1, "sfx", "sfx/b"), (6, "bgm", "bgm/e")])

    def test_dashes_in_string_do_not_hide_calls(self):
        got = self._scan('local s = "a--b"; audio.sfx("sfx/x") -- audio.sfx("sfx/y")\n'
                         "print('--') audio.sfx('sfx/z')\n")
        self.assertEqual(got, [(1, "sfx", "sfx/x"), (2, "sfx", "sfx/z")])

    def test_trailing_comment_and_long_string(self):
        got = self._scan('x = [[ -- not a comment ]] audio.sfx("sfx/q")\n---[[ line comment\naudio.sfx("sfx/r")\n')
        self.assertEqual(got, [(1, "sfx", "sfx/q"), (3, "sfx", "sfx/r")])


class RepoCopyCase(unittest.TestCase):
    """Operates on a throwaway copy of the project."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = self.tmp / "p"
        for d in ("assets", "assets_src", "tools"):
            shutil.copytree(ROOT / d, self.root / d)

    def errors(self):
        return [m for _g, e, _w in A.run_checks(self.root) for m in e]


class CheckTests(RepoCopyCase):
    def test_clean(self):
        self.assertEqual(self.errors(), [])

    def test_missing_file(self):
        (self.root / "assets/audio/sfx/ui.wav").unlink()
        self.assertTrue(any("sfx/ui" in e for e in self.errors()))

    def test_unknown_lua_id(self):
        (self.root / "assets/scripts/zz.lua").write_text('local audio = require("audio")\naudio.sfx("sfx/nope")\n')
        self.assertTrue(any("sfx/nope" in e for e in self.errors()))

    def test_wrong_kind_lua(self):
        (self.root / "assets/scripts/zz.lua").write_text('audio.bgm("sfx/ui")\n')
        self.assertTrue(any("kind sfx" in e for e in self.errors()))

    def test_bgm_wav(self):
        cat = self.root / "assets/audio/catalog.json"
        c = json.loads(cat.read_text())
        for s in c["sounds"]:
            if s["id"] == "bgm/street_chip":
                s["path"] = "assets/audio/bgm/street_chip.wav"
        cat.write_text(A.render_catalog(c["sounds"]))
        write_wav(self.root / "assets/audio/bgm/street_chip.wav", 2, 48000, 1228800)
        self.assertTrue(any("must be .ogg" in e for e in self.errors()))

    def test_stereo_sfx(self):
        write_wav(self.root / "assets/audio/sfx/ui.wav", 2, 48000, 1044)
        self.assertTrue(any("sfx must be mono" in e for e in self.errors()))


class SyncTests(RepoCopyCase):
    def make_src(self, status="ok", name="build"):
        src = self.tmp / name
        (src / "final").mkdir(parents=True, exist_ok=True)
        assets = []
        for s in json.loads((self.root / "assets/audio/catalog.json").read_text())["sounds"]:
            f = Path("final") / (s["id"] + Path(s["path"]).suffix)
            (src / f).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.root / s["path"], src / f)
            assets.append({"id": s["id"], "status": status, "final": f.as_posix(), "loop": s["loop"],
                           "category": s["category"],
                           "master": {"loop_start": s["loop_start"], "loop_length": s["loop_length"]}})
        (src / "report.json").write_text(json.dumps({"version": 1, "assets": assets}))
        return src

    def test_idempotent(self):
        before = (self.root / "assets/audio/catalog.json").read_text()
        self.assertEqual(A.audio_sync(self.root, self.make_src()), 0)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_text(), before.rstrip("\n") + "\n")

    def test_failed_writes_nothing(self):
        src = self.make_src(status="failed")
        before = (self.root / "assets/audio/catalog.json").read_bytes()
        (self.root / "assets/audio/sfx/stale.wav").write_bytes(b"x")
        self.assertEqual(A.audio_sync(self.root, src), 1)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_bytes(), before)
        self.assertTrue((self.root / "assets/audio/sfx/stale.wav").exists())

    def test_stale_removed(self):
        (self.root / "assets/audio/sfx/stale.wav").write_bytes(b"x")
        self.assertEqual(A.audio_sync(self.root, self.make_src()), 0)
        self.assertFalse((self.root / "assets/audio/sfx/stale.wav").exists())

    # ---- helpers
    def cat(self):
        return json.loads((self.root / "assets/audio/catalog.json").read_text())

    def write_cat(self, obj):
        (self.root / "assets/audio/catalog.json").write_text(json.dumps(obj))

    def edit_report(self, src, fn):
        p = src / "report.json"
        r = json.loads(p.read_text())
        fn(r)
        p.write_text(json.dumps(r))

    def assert_clean_fail(self, src, only=None):
        before = (self.root / "assets/audio/catalog.json").read_bytes()
        try:
            rc = A.audio_sync(self.root, src, only)
        except A.AssetError:
            rc = 1
        self.assertEqual(rc, 1)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_bytes(), before)

    def assert_raises_asset_error(self, src, only=None):
        before = (self.root / "assets/audio/catalog.json").read_bytes()
        with self.assertRaises(A.AssetError):
            A.audio_sync(self.root, src, only)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_bytes(), before)

    # ---- B1
    def test_non_audio_files_survive(self):
        for rel in ("README.md", ".gitkeep", "sfx/notes.txt"):
            (self.root / "assets/audio" / rel).write_text("keep")
        (self.root / "assets/audio/sfx/OLD.WAV").write_bytes(b"x")
        self.assertEqual(A.audio_sync(self.root, self.make_src()), 0)
        for rel in ("README.md", ".gitkeep", "sfx/notes.txt"):
            self.assertTrue((self.root / "assets/audio" / rel).exists(), rel)
        self.assertFalse((self.root / "assets/audio/sfx/OLD.WAV").exists())

    # ---- M1 --only carry-over
    def test_only_carries_other_entries(self):
        before = self.cat()
        src = self.make_src()
        self.assertEqual(A.audio_sync(self.root, src, {"sfx/ui"}), 0)
        self.assertEqual(self.cat(), before)

    def test_only_carry_missing_file(self):
        src = self.make_src()
        (self.root / "assets/audio/bgm/street_chip.ogg").unlink()
        self.assert_clean_fail(src, {"sfx/ui"})

    def test_only_carry_not_in_catalog(self):
        src = self.make_src()
        c = self.cat()
        c["sounds"] = [s for s in c["sounds"] if s["id"] != "bgm/street_chip"]
        self.write_cat(c)
        self.assert_clean_fail(src, {"sfx/ui"})

    def test_only_carry_invalid_entries(self):
        src = self.make_src()
        for bad in ("/etc/evil.wav", "../evil.wav", "assets/audio/../../evil.wav", None):
            c = self.cat()
            for s in c["sounds"]:
                if s["id"] == "bgm/street_chip":
                    if bad is None:
                        del s["path"]
                    else:
                        s["path"] = bad
            self.write_cat(c)
            self.assert_clean_fail(src, {"sfx/ui"})
        self.assertFalse((self.root.parent / "evil.wav").exists())

    def test_only_carry_bad_volume(self):
        src = self.make_src()
        c = self.cat()
        c["sounds"][0]["volume"] = 99
        self.write_cat(c)
        ident = c["sounds"][0]["id"]
        other = next(s["id"] for s in c["sounds"] if s["id"] != ident)
        self.assert_clean_fail(src, {other})

    # ---- M3 malformed shapes
    def test_malformed_report(self):
        src = self.make_src()
        for bad in ([], "x", {"assets": {}}, {"assets": [1]}, {"assets": ["a"]}):
            (src / "report.json").write_text(json.dumps(bad))
            self.assert_raises_asset_error(src)

    def test_malformed_manifest(self):
        src = self.make_src()
        p = self.root / "assets_src/audio.json"
        m = json.loads(p.read_text())
        m["assets"].append("oops")
        p.write_text(json.dumps(m))
        self.assert_raises_asset_error(src)

    def test_malformed_catalog(self):
        src = self.make_src()
        for bad in ([], {"sounds": {}}, {"sounds": [1]}):
            self.write_cat(bad)
            self.assert_raises_asset_error(src)

    def test_catalog_entry_without_id_is_ignored(self):
        # (an old entry without 'path' is covered by test_only_carry_invalid_entries)
        src = self.make_src()
        c = self.cat()
        c["sounds"].append({"foo": 1})
        self.write_cat(c)
        self.assertEqual(A.audio_sync(self.root, src), 0)

    def test_bad_report_fields(self):
        counter = itertools.count()
        cases = [
            ("final", 5), ("final", ["a"]), ("final", "/etc/passwd.wav"), ("final", "../outside.wav"),
            ("final", "final/../../x.wav"), ("loop", "yes"), ("master", [1]), ("category", 7),
        ]
        for key, val in cases:
            s2 = self.make_src(name='b%d' % next(counter))
            self.edit_report(s2, lambda r: r["assets"][0].__setitem__(key, val))
            self.assert_clean_fail(s2)
        for key, val in (("loop_start", "abc"), ("loop_length", "x"), ("loop_start", -5), ("loop_length", None)):
            s2 = self.make_src(name='b%d' % next(counter))

            def fn(r, key=key, val=val):
                for a in r["assets"]:
                    if a["loop"]:
                        a["master"][key] = val
            self.edit_report(s2, fn)
            self.assert_clean_fail(s2)

    def test_final_escape_not_written(self):
        outside = self.tmp / "outside.wav"
        write_wav(outside, 1, 48000, 100)
        src = self.make_src()
        self.edit_report(src, lambda r: r["assets"][0].__setitem__("final", "../outside.wav"))
        self.assert_clean_fail(src)

    # ---- M2 atomicity (OSError mid-copy: AssetError, catalog untouched, no temp files left)
    def test_mid_copy_oserror(self):
        src = self.make_src()
        # change content of two audio files so both need copying
        write_wav(src / "final/sfx/ui.wav", 1, 48000, 500)
        before = (self.root / "assets/audio/catalog.json").read_bytes()
        orig_ui = (self.root / "assets/audio/sfx/ui.wav").read_bytes()
        calls = []
        real = shutil.copyfileobj

        def boom(a, b, *args):
            calls.append(1)
            raise OSError("disk full")
        with unittest.mock.patch.object(A.shutil, "copyfileobj", boom):
            with self.assertRaises(A.AssetError):
                A.audio_sync(self.root, src)
        self.assertTrue(calls)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_bytes(), before)
        self.assertEqual((self.root / "assets/audio/sfx/ui.wav").read_bytes(), orig_ui)
        leftovers = [f for f in (self.root / "assets/audio").rglob("*") if f.name.startswith(".tmp-")]
        self.assertEqual(leftovers, [])
        self.assertIs(A.shutil.copyfileobj, real)

    def test_mid_copy_second_file_fails_catalog_unchanged(self):
        src = self.make_src()
        for s in self.cat()["sounds"]:
            if s["path"].endswith(".wav"):
                write_wav(src / "final" / (s["id"] + ".wav"), 1, 48000, 500)
        before = (self.root / "assets/audio/catalog.json").read_bytes()
        real = shutil.copyfileobj
        n = []

        def flaky(a, b, *args):
            n.append(1)
            if len(n) == 2:
                raise OSError("io error")
            return real(a, b, *args)
        with unittest.mock.patch.object(A.shutil, "copyfileobj", flaky):
            with self.assertRaises(A.AssetError):
                A.audio_sync(self.root, src)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_bytes(), before)
        self.assertEqual([f for f in (self.root / "assets/audio").rglob("*") if f.name.startswith(".tmp-")], [])

    def test_catalog_write_failure_keeps_old(self):
        src = self.make_src()
        write_wav(src / "final/sfx/ui.wav", 1, 48000, 500)
        before = (self.root / "assets/audio/catalog.json").read_bytes()
        with unittest.mock.patch.object(A.os, "replace", side_effect=OSError("nope")):
            with self.assertRaises(A.AssetError):
                A.audio_sync(self.root, src)
        self.assertEqual((self.root / "assets/audio/catalog.json").read_bytes(), before)
        self.assertEqual([f for f in (self.root / "assets/audio").rglob("*") if f.name.startswith(".tmp-")], [])

    # ---- m1 / m3 misc
    def test_id_trailing_newline_rejected(self):
        self.assertEqual(A.validate_entry({**self.cat()["sounds"][0], "id": "sfx/ui\n"})[0][:6], "bad id")
        src = self.make_src()
        p = self.root / "assets_src/audio.json"
        m = json.loads(p.read_text())
        m["assets"][0]["id"] = m["assets"][0]["id"] + "\n"
        p.write_text(json.dumps(m))
        self.assert_clean_fail(src)

    def test_category_validation(self):
        e = dict(self.cat()["sounds"][0])
        e["category"] = None
        self.assertEqual(A.validate_entry(e), [])
        e["category"] = "music"
        self.assertEqual(A.validate_entry(e), [])
        for bad in (5, ["x"], {}, True):
            e["category"] = bad
            self.assertTrue(any("category" in m for m in A.validate_entry(e)))

    def test_check_survives_odd_catalog(self):
        c = self.cat()
        c["sounds"].append({"id": ["x"], "path": 3})
        self.write_cat(c)
        self.assertTrue(self.errors())  # reports errors, no traceback


@unittest.skipIf(PILImage is None, "Pillow not installed")
class ArtTests(RepoCopyCase):
    def set_source(self, source="genai"):
        p = self.root / "assets_src/art.json"
        a = json.loads(p.read_text())
        for e in a["art"]:
            if e["name"] == "char_placeholder":
                e["source"] = source
        p.write_text(json.dumps(a))

    def test_wrong_size(self):
        self.set_source()
        src = self.tmp / "in"
        src.mkdir()
        PILImage.new("RGBA", (64, 64)).save(src / "char_placeholder.png")
        before = (self.root / "assets/sprites/char_placeholder.png").read_bytes()
        self.assertEqual(A.art_import(self.root, src, None), 1)
        self.assertEqual((self.root / "assets/sprites/char_placeholder.png").read_bytes(), before)

    def test_missing_file(self):
        self.set_source()
        src = self.tmp / "in"
        src.mkdir()
        self.assertEqual(A.art_import(self.root, src, None), 1)

    def test_ok_and_palette(self):
        self.set_source()
        src = self.tmp / "in"
        src.mkdir()
        PILImage.new("RGBA", (512, 768), (10, 20, 30, 255)).save(src / "char_placeholder.png")
        self.assertEqual(A.art_import(self.root, src, None), 0)
        self.assertEqual((self.root / "assets/sprites/char_placeholder.png").read_bytes(),
                         (src / "char_placeholder.png").read_bytes())
        # palette in master.json shape (object of lists) rejects off-palette colours
        (self.root / "pal.json").write_text(json.dumps({"a": ["#0A141E"], "b": ["#FFFFFF"]}))
        p = self.root / "assets_src/art.json"
        a = json.loads(p.read_text())
        a["palette"] = "pal.json"
        p.write_text(json.dumps(a))
        self.assertEqual(A.art_import(self.root, src, None), 0)
        (self.root / "pal.json").write_text(json.dumps(["#FFFFFF"]))
        self.assertEqual(A.art_import(self.root, src, None), 1)

    def test_dest_escapes_rejected(self):
        for bad in ("../x.png", "assets/../x.png", "/tmp/x.png", "x.png", "assets/x.txt", "other/x.png",
                    "assets\\x.png", 5, None):
            self.set_source()
            p = self.root / "assets_src/art.json"
            a = json.loads(p.read_text())
            for e in a["art"]:
                if e["name"] == "char_placeholder":
                    e["dest"] = bad
            p.write_text(json.dumps(a))
            src = self.tmp / "in"
            src.mkdir(exist_ok=True)
            PILImage.new("RGBA", (512, 768), (10, 20, 30, 255)).save(src / "char_placeholder.png")
            with self.assertRaises(A.AssetError, msg=repr(bad)):
                A.art_import(self.root, src, None)
            self.assertTrue(any("bad dest" in e for e in self.errors()), repr(bad))
        self.assertFalse((self.root / "x.png").exists())
        self.assertFalse((self.tmp / "x.png").exists())

    def test_hex_trailing_newline_rejected(self):
        (self.root / "pal.json").write_text(json.dumps(["#FFFFFF\n"]))
        a = {"palette": "pal.json"}
        with self.assertRaises(A.AssetError):
            A.load_palette(self.root, a)


if __name__ == "__main__":
    unittest.main()
