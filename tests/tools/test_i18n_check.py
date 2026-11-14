import importlib.util
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


I = _load("i18n_check", ROOT / "tools" / "i18n_check.py")


class RepoCopyCase(unittest.TestCase):
    """Operates on a throwaway copy of assets/."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = self.tmp / "p"
        shutil.copytree(ROOT / "assets", self.root / "assets")

    def path(self, lang):
        return self.root / "assets" / "i18n" / (lang + ".lua")

    def add(self, lang, key, value):
        text = self.path(lang).read_text(encoding="utf-8")
        cut = text.rindex("}")
        self.path(lang).write_text(text[:cut] + '  ["%s"] = "%s",\n' % (key, value) + text[cut:],
                                   encoding="utf-8")

    def remove(self, lang, key):
        p = self.path(lang)
        text = p.read_text(encoding="utf-8")
        new = re.sub(r'^\s*\["%s"\]\s*=.*\n' % re.escape(key), "", text, count=1, flags=re.M)
        self.assertNotEqual(new, text, "key %r not in %s" % (key, lang))
        p.write_text(new, encoding="utf-8")

    def replace_value(self, lang, key, value):
        p = self.path(lang)
        new, n = re.subn(r'^(\s*\["%s"\]\s*=\s*)"(?:[^"\\]|\\.)*"' % re.escape(key),
                         lambda m: m.group(1) + '"' + value + '"', p.read_text(encoding="utf-8"),
                         count=1, flags=re.M)
        self.assertEqual(n, 1)
        p.write_text(new, encoding="utf-8")

    def errors(self):
        return I.check(self.root)


class StringHelperTests(unittest.TestCase):
    def test_unescape(self):
        self.assertEqual(I.unescape_lua_str(r'a\"b\nc\t\\'), 'a"b\nc\t\\')
        self.assertEqual(I.unescape_lua_str(r"\u{4E2D}"), "中")

    def test_literals_skip_comments_and_long_strings(self):
        src = 'local a = "x" -- "y"\n--[[ "z" ]] local b = \'w\'\nlocal c = [["q"]]\n'
        self.assertEqual([s for s, _e in I.iter_string_literals(src)], ["x", "w"])

    def test_placeholder_signature(self):
        self.assertEqual(I.placeholder_signature("a {x} b {n|one|other}")[0], {"x": 1, "n": 3})
        sig, problems = I.placeholder_signature("{x")
        self.assertEqual(sig, {})
        self.assertTrue(problems)


class CheckTests(RepoCopyCase):
    def test_clean(self):
        self.assertEqual(self.errors(), [])

    def test_missing_key(self):
        self.remove("en", "title.load")
        self.assertTrue(any('en: missing 1 key(s): "title.load"' in e for e in self.errors()))

    def test_extra_key(self):
        self.add("ko", "zz.extra", "x")
        self.assertTrue(any('ko: extra 1 key(s): "zz.extra"' in e for e in self.errors()))

    def test_placeholder_mismatch(self):
        self.replace_value("en", "settings.pad.connected", "Gamepad: {pad}")
        errs = self.errors()
        self.assertTrue(any('en: "settings.pad.connected": placeholders {pad}' in e for e in errs), errs)

    def test_missing_placeholder(self):
        self.replace_value("en", "settings.pad.connected", "Gamepad")
        self.assertTrue(any('en: "settings.pad.connected": placeholders none' in e for e in self.errors()))

    def test_malformed_placeholder(self):
        self.replace_value("en", "settings.pad.connected", "Gamepad: {name")
        self.assertTrue(any("malformed placeholder" in e for e in self.errors()))

    def test_plural_forms_match(self):
        for lang, val in (("zh", "手柄 {name|一|多}"), ("en", "Gamepad {name|one|other}"),
                          ("ko", "패드 {name|하나|여럿}")):
            self.replace_value(lang, "settings.pad.connected", val)
        self.assertEqual(self.errors(), [])
        self.replace_value("ko", "settings.pad.connected", "패드 {name}")
        self.assertTrue(any('ko: "settings.pad.connected": placeholders {name}' in e for e in self.errors()))

    def test_unused_key(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.unused", "x")
        self.assertEqual([e for e in self.errors() if "unused" in e], ['unused key: "zz.unused"'])

    def test_dynamic_prefix_counts_as_used(self):
        # rebind.lua calls i18n.t("act." .. a.id), so the whole act.* family is referenced.
        for lang in ("zh", "en", "ko"):
            self.add(lang, "act.zz_custom", "x")
        self.assertEqual(self.errors(), [])

    def test_literal_reference_counts_as_used(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.used", "x")
        (self.root / "assets" / "scripts" / "zz.lua").write_text('local x = i18n.t("zz.used")\n')
        self.assertEqual(self.errors(), [])

    def test_commented_reference_does_not_count(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.commented", "x")
        (self.root / "assets" / "scripts" / "zz.lua").write_text('-- i18n.t("zz.commented")\n')
        self.assertTrue(any('unused key: "zz.commented"' in e for e in self.errors()))

    def _unused(self):
        return [e for e in self.errors() if "unused key" in e]

    def _script(self, src):
        (self.root / "assets" / "scripts" / "zz.lua").write_text(src)

    def test_keep_marker_exempts_only_unused_check(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.kept", "x")
        self.assertTrue(self._unused())
        for lang in ("zh", "en", "ko"):
            p = self.path(lang)
            p.write_text(p.read_text(encoding="utf-8").replace(
                '["zz.kept"] = "x",', '["zz.kept"] = "x",  -- i18n:keep'), encoding="utf-8")
        self.assertEqual(self.errors(), [])
        self.remove("en", "zz.kept")
        errs = self.errors()
        self.assertTrue(any("en: missing" in e and "zz.kept" in e for e in errs))
        self.assertEqual(self._unused(), [])

    def test_empty_and_single_letter_prefixes_do_not_count(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.unused2", "x")
        self._script('local a = "" .. x\nlocal b = "K" .. y\nlocal c = ":" .. z\nlocal d = "{" .. w\n')
        self.assertTrue(any("zz.unused2" in e for e in self._unused()))

    def test_valid_prefix_counts(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.sub.key", "x")
        self._script('local a = i18n.t("zz.sub." .. id)\n')
        self.assertEqual(self._unused(), [])

    def test_string_format_key_counts(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "item.x.name", "x")
        self.assertTrue(any("item.x.name" in e for e in self._unused()))
        self._script('local a = i18n.t(string.format("item.%s.name", id))\n')
        self.assertEqual(self._unused(), [])

    def test_percent_literal_without_prefix_ignored(self):
        for lang in ("zh", "en", "ko"):
            self.add(lang, "zz.unused3", "x")
        self._script('local a = string.format("%d items", n)\n')
        self.assertTrue(any("zz.unused3" in e for e in self._unused()))

    def test_duplicate_key(self):
        self.add("zh", "title.name", "dup")
        self.assertTrue(any("duplicate key" in e for e in self.errors()))

    def test_missing_file(self):
        self.path("ko").unlink()
        self.assertTrue(any("assets/i18n/ko.lua: missing file" in e for e in self.errors()))


class ParseTableLineTests(unittest.TestCase):
    def test_keep_marker_not_shifted_by_unicode_line_separator_in_comment(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        for sep in (" ", "\x0c", "\x85"):
            p = tmp / "t.lua"
            p.write_text('return {\n  -- note%s here\n  ["a.one"] = "x",  -- i18n:keep\n'
                         '  ["a.two"] = "y",\n}\n' % sep, encoding="utf-8")
            keep = set()
            entries, problems = I.parse_table(p, keep)
            self.assertEqual(problems, [], repr(sep))
            self.assertEqual(set(entries), {"a.one", "a.two"}, repr(sep))
            self.assertEqual(keep, {"a.one"}, repr(sep))

    def test_keep_marker_inside_string_value_is_ignored(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        p = tmp / "t.lua"
        p.write_text('return {\n  ["a.one"] = "x -- i18n:keep",\n}\n', encoding="utf-8")
        keep = set()
        I.parse_table(p, keep)
        self.assertEqual(keep, set())


class AssetsIntegrationTests(unittest.TestCase):
    def test_group_is_wired_and_clean(self):
        A = _load("assets_tool_i18n", ROOT / "tools" / "assets.py")
        groups = {name: errs for name, errs, _warns in A.run_checks(ROOT)}
        self.assertIn("i18n", groups)
        self.assertEqual(groups["i18n"], [])


if __name__ == "__main__":
    unittest.main()
