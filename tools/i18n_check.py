#!/usr/bin/env python3
"""Static checks for the trilingual UI strings (assets/i18n/{zh,en,ko}.lua; stdlib only).

Checks:
  * all three languages define exactly the same keys (zh is the source language);
  * every key uses the same placeholders in every language, and placeholders are well formed
    ({name} or the English plural form {name|one|other});
  * every key is referenced from a Lua string literal under assets/ (comments and long strings are
    ignored). A literal followed by ".." counts as a prefix, e.g. i18n.t("act." .. a.id) covers
    every "act.*" key; a string.format-style literal such as "item.%s.name" contributes the part
    before the first "%" as a prefix. A prefix must be lowercase dotted segments ending in a dot
    (act., settings.tab.); anything else is ignored.
    An entry whose line ends with a `-- i18n:keep` comment is exempt from the unused-key check
    only (key parity and placeholders are still checked); use it for keys reserved for upcoming UI.

Usage:
  python3 tools/i18n_check.py [--root .]
"""
import argparse
import re
import sys
from pathlib import Path

LANGS = ("zh", "en", "ko")
SOURCE_LANG = "zh"
I18N_DIR = Path("assets") / "i18n"
SCAN_DIR = Path("assets")

# One table row: ["key"] = "value",  (comments already stripped)
_ENTRY_RE = re.compile(r'^\s*\["((?:\\.|[^"\\])*)"\]\s*=\s*"((?:\\.|[^"\\])*)"\s*,?\s*$')
_LONG_OPEN_RE = re.compile(r"\[(=*)\[")
_CONCAT_RE = re.compile(r"\s*\.\.")
_PREFIX_RE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)*\.$")
_KEEP_RE = re.compile(r"--\s*i18n:keep\s*$")
# A runtime placeholder: {name} or the English plural form {name|one|other}.
_PLACEHOLDER_RE = re.compile(r"\{([A-Za-z0-9_]+)(?:\|([^{}|]*)\|([^{}|]*))?\}")
# Table wrapper: `return {` ... `}`.
_TABLE_OPEN_RE = re.compile(r"^\s*return\s*\{\s*$")
_TABLE_CLOSE_RE = re.compile(r"^\s*\}\s*$")


def unescape_lua_str(s: str) -> str:
    """Decode Lua escapes (\\n, \\t, \\" , \\ddd, \\xNN, \\u{XXXX}) in a quoted string body."""
    out = []
    i, n = 0, len(s)
    simple = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
              "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
    while i < n:
        ch = s[i]
        if ch != "\\" or i + 1 >= n:
            out.append(ch)
            i += 1
            continue
        nxt = s[i + 1]
        if nxt in simple:
            out.append(simple[nxt])
            i += 2
        elif nxt == "x" and i + 3 < n and all(c in "0123456789abcdefABCDEF" for c in s[i + 2:i + 4]):
            out.append(chr(int(s[i + 2:i + 4], 16)))
            i += 4
        elif nxt == "u" and s.startswith("{", i + 2):
            end = s.find("}", i + 3)
            try:
                out.append(chr(int(s[i + 3:end], 16)))
                i = end + 1
            except (ValueError, OverflowError):
                out.append(nxt)
                i += 2
        elif nxt.isdigit():
            j = i + 1
            while j < n and j < i + 4 and s[j].isdigit():
                j += 1
            out.append(chr(int(s[i + 1:j])))
            i = j
        else:
            out.append(nxt)
            i += 2
    return "".join(out)


def strip_lua_comments(src: str) -> str:
    """Blank out Lua comments with spaces, keeping newlines; quoted strings are copied verbatim."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            m = _LONG_OPEN_RE.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, m.end())
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(src[i:j])
            i = j
        elif c == "[" and _LONG_OPEN_RE.match(src, i):
            m = _LONG_OPEN_RE.match(src, i)
            close = "]" + m.group(1) + "]"
            j = src.find(close, m.end())
            j = n if j < 0 else j + len(close)
            out.append(src[i:j])
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def iter_string_literals(src: str):
    """Yield (decoded value, end offset) for quoted Lua string literals; comments and long strings skipped."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            m = _LONG_OPEN_RE.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, m.end())
                i = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            end = min(j + 1, n)
            yield unescape_lua_str(src[i + 1:min(j, n)]), end
            i = end
        elif c == "[" and _LONG_OPEN_RE.match(src, i):
            m = _LONG_OPEN_RE.match(src, i)
            close = "]" + m.group(1) + "]"
            j = src.find(close, m.end())
            i = n if j < 0 else j + len(close)
        else:
            i += 1


def parse_table(path: Path, keep=None):
    """Parse one assets/i18n/<lang>.lua table. Returns (entries, problems).

    If `keep` (a set) is given, keys whose raw line ends with `-- i18n:keep` are added to it."""
    text = path.read_text(encoding="utf-8")
    entries, problems = {}, []
    # Split both views on "\n" only: str.splitlines() also breaks on \x0c, \x85, U+2028 etc., which
    # strip_lua_comments blanks inside comments, so raw and stripped line numbers would drift apart.
    raw_lines = text.split("\n")
    for lineno, line in enumerate(strip_lua_comments(text).split("\n"), 1):
        if not line.strip() or _TABLE_OPEN_RE.match(line) or _TABLE_CLOSE_RE.match(line):
            continue
        m = _ENTRY_RE.match(line)
        if not m:
            problems.append("%d: cannot parse %r" % (lineno, line.strip()[:80]))
            continue
        key, value = unescape_lua_str(m.group(1)), unescape_lua_str(m.group(2))
        if key in entries:
            problems.append("%d: duplicate key %r" % (lineno, key))
        entries[key] = value
        if keep is not None and _KEEP_RE.search(raw_lines[lineno - 1]):
            keep.add(key)
    return entries, problems


def placeholder_signature(text: str):
    """Return ({name: 1|3}, problems); 1 = {name}, 3 = {name|one|other}."""
    sig, problems = {}, []
    for m in _PLACEHOLDER_RE.finditer(text):
        name = m.group(1)
        forms = 1 if m.group(2) is None else 3
        if forms == 3 and not (m.group(2) and m.group(3)):
            problems.append("empty plural branch in %r" % m.group(0))
        if name in sig and sig[name] != forms:
            problems.append("{%s} used both alone and as a plural" % name)
        sig[name] = forms
    rest = _PLACEHOLDER_RE.sub("", text)
    if "{" in rest or "}" in rest:
        problems.append("malformed placeholder in %r" % text)
    return sig, problems


def referenced_keys(root: Path):
    """Return (literal strings, concatenation prefixes) found in Lua under assets/ (i18n tables excluded)."""
    i18n_dir = (root / I18N_DIR).resolve()
    used, prefixes = set(), set()
    for f in sorted((root / SCAN_DIR).rglob("*.lua")):
        try:
            if f.resolve().is_relative_to(i18n_dir):
                continue
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for value, end in iter_string_literals(text):
            used.add(value)
            if _CONCAT_RE.match(text, end) and _PREFIX_RE.match(value):
                prefixes.add(value)
            if "%" in value:
                head = value.split("%", 1)[0]
                if _PREFIX_RE.match(head):
                    prefixes.add(head)
    return used, prefixes


def _fmt_keys(keys, limit=6):
    shown = ", ".join('"%s"' % k for k in keys[:limit])
    return shown + (", ... (%d total)" % len(keys) if len(keys) > limit else "")


def _fmt_placeholders(sig):
    if not sig:
        return "none"
    return ", ".join("{%s|one|other}" % n if forms == 3 else "{%s}" % n
                     for n, forms in sorted(sig.items()))


def check(root: Path) -> list[str]:
    """Return a list of problems (empty when the translation tables are consistent)."""
    root = Path(root)
    i18n_dir = root / I18N_DIR
    rel_dir = I18N_DIR.as_posix()
    if not i18n_dir.is_dir():
        return ["missing directory %s" % rel_dir]

    errors = []
    tables = {}
    keep = set()
    for lang in LANGS:
        path = i18n_dir / (lang + ".lua")
        if not path.is_file():
            errors.append("%s/%s.lua: missing file" % (rel_dir, lang))
            continue
        rel = "%s/%s.lua" % (rel_dir, lang)
        try:
            table, problems = parse_table(path, keep)
        except (OSError, UnicodeDecodeError) as e:
            errors.append("%s: cannot read: %s" % (rel, e))
            continue
        errors.extend("%s: %s" % (rel, p) for p in problems)
        tables[lang] = table

    base = tables.get(SOURCE_LANG)
    if base is not None:
        for lang in LANGS:
            if lang == SOURCE_LANG or lang not in tables:
                continue
            missing = sorted(set(base) - set(tables[lang]))
            extra = sorted(set(tables[lang]) - set(base))
            if missing:
                errors.append("%s: missing %d key(s): %s" % (lang, len(missing), _fmt_keys(missing)))
            if extra:
                errors.append("%s: extra %d key(s): %s" % (lang, len(extra), _fmt_keys(extra)))

    all_keys = set().union(*(set(t) for t in tables.values())) if tables else set()

    for key in sorted(all_keys):
        sigs = {}
        for lang in LANGS:
            if key not in tables.get(lang, {}):
                continue
            sig, problems = placeholder_signature(tables[lang][key])
            errors.extend('%s: "%s": %s' % (lang, key, p) for p in problems)
            sigs[lang] = sig
        expected = sigs.get(SOURCE_LANG)
        if expected is None:
            continue
        for lang, sig in sigs.items():
            if lang != SOURCE_LANG and sig != expected:
                errors.append('%s: "%s": placeholders %s, expected %s (from %s)'
                              % (lang, key, _fmt_placeholders(sig), _fmt_placeholders(expected), SOURCE_LANG))

    used, prefixes = referenced_keys(root)
    for key in sorted(all_keys):
        if key not in used and key not in keep and not any(key.startswith(p) for p in prefixes):
            errors.append('unused key: "%s"' % key)
    return errors


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Check trilingual UI strings")
    ap.add_argument("--root", default=".")
    args = ap.parse_args(argv)
    errors = check(Path(args.root).resolve())
    for e in errors:
        print("i18n check error: " + e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
