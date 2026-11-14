#!/usr/bin/env python3
"""Asset pipeline CLI for the Delve starter (Python 3.10+, stdlib only; Pillow only for art import checks).

Usage (from anywhere; the project root is the parent of tools/):
  python3 tools/assets.py placeholder
  python3 tools/assets.py audio build [--pixel-hero DIR] [--only ID...] [--out DIR]
  python3 tools/assets.py audio sync --from DIR
  python3 tools/assets.py art import --from DIR [--only NAME...]
  python3 tools/assets.py check [--junit FILE]

art.json `palette`: null, or a path (relative to the project root) to a JSON file that is either a list of
"#RRGGBB" strings or an object whose values are lists of such strings (pixel-hero-demo palette/master.json).
"""
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Always use ID_RE.fullmatch (never match + "$": "$" also matches before a trailing newline).
ID_RE = re.compile(r"(sfx|bgm)/[a-z0-9_]+(/[a-z0-9_]+)*")
HEX_RE = re.compile(r"#?[0-9a-fA-F]{6}")
ART_NAME_RE = re.compile(r"[A-Za-z0-9_-]+")
ART_SOURCES = ("placeholder", "genai", "pixelflow", "manual")
# Only a complete literal argument counts: audio.sfx("sfx/" .. n) is dynamic and not checked.
LUA_CALL_RE = re.compile(r"""\baudio\s*\.\s*(sfx_var|sfx|bgm)\s*\(\s*(["'])([^"'\n]*)\2\s*[,)]""")


class AssetError(Exception):
    """A clean, user-facing error."""


# ------------------------------------------------------------------ header parsers

def parse_wav(data: bytes) -> dict:
    """Return {frames, sample_rate, channels} from a RIFF/WAVE PCM file, or raise AssetError."""
    if len(data) < 12 or data[0:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise AssetError("not a RIFF/WAVE file")
    pos = 12
    fmt = None
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        body = pos + 8
        if cid == b"fmt ":
            if size < 16 or body + 16 > len(data):
                raise AssetError("truncated WAV fmt chunk")
            tag, ch, rate, _br, align, bits = struct.unpack_from("<HHIIHH", data, body)
            fmt = (tag, ch, rate, align, bits)
        elif cid == b"data":
            if fmt is None:
                raise AssetError("WAV data chunk before fmt chunk")
            if body + size > len(data):
                raise AssetError("truncated WAV: data chunk extends past end of file")
            tag, ch, rate, align, bits = fmt
            if tag not in (1, 3, 0xFFFE):
                raise AssetError("unsupported WAV format tag %d" % tag)
            if ch < 1 or align < 1 or rate < 1:
                raise AssetError("invalid WAV fmt chunk")
            return {"frames": size // align, "sample_rate": rate, "channels": ch}
        pos = body + size + (size & 1)
    raise AssetError("WAV has no %s chunk" % ("data" if fmt else "fmt/data"))


def parse_ogg(data: bytes) -> dict:
    """Return {frames, sample_rate, channels} from an Ogg Vorbis file, or raise AssetError.

    frames = granule position of the last page whose granule is not -1 (-1 means "no packet finishes on this page").
    The page CRC is deliberately NOT verified (only structure is checked), so the parser does not depend on it.
    """
    pos = 0
    info = None
    serial = None
    last_gp = None
    pages = 0
    n = len(data)
    while pos < n:
        if pos + 27 > n or data[pos:pos + 4] != b"OggS":
            raise AssetError("not an Ogg file" if pages == 0 else "corrupt or truncated Ogg page at byte %d" % pos)
        nseg = data[pos + 26]
        if pos + 27 + nseg > n:
            raise AssetError("truncated Ogg page header")
        body_len = sum(data[pos + 27:pos + 27 + nseg])
        end = pos + 27 + nseg + body_len
        if end > n:
            raise AssetError("truncated Ogg file (page extends past end)")
        gp = struct.unpack_from("<q", data, pos + 6)[0]
        ser = struct.unpack_from("<I", data, pos + 14)[0]
        if pages == 0:
            serial = ser
            body = data[pos + 27 + nseg:end]
            if len(body) < 30 or body[0:7] != b"\x01vorbis":
                raise AssetError("first Ogg packet is not a Vorbis identification header")
            if struct.unpack_from("<I", body, 7)[0] != 0:
                raise AssetError("unsupported Vorbis version")
            ch = body[11]
            rate = struct.unpack_from("<I", body, 12)[0]
            if ch < 1 or rate < 1:
                raise AssetError("invalid Vorbis identification header")
            info = (ch, rate)
        elif ser != serial:
            raise AssetError("Ogg page at byte %d has a different stream serial (multiplexed/chained files "
                             "are not supported)" % pos)
        if gp < -1:
            raise AssetError("invalid Ogg granule position %d at byte %d" % (gp, pos))
        if gp != -1:
            last_gp = gp
        pos = end
        pages += 1
    if info is None:
        raise AssetError("empty file")
    if last_gp is None:
        raise AssetError("Ogg has no page with a granule position (truncated?)")
    if last_gp == 0:
        raise AssetError("Ogg has zero frames")
    return {"frames": last_gp, "sample_rate": info[1], "channels": info[0]}


def parse_audio_file(path: Path) -> dict:
    ext = path.suffix.lower()
    try:
        data = path.read_bytes()
    except OSError as e:
        raise AssetError("cannot read %s: %s" % (path, e))
    try:
        if ext == ".wav":
            return parse_wav(data)
        if ext == ".ogg":
            return parse_ogg(data)
    except AssetError as e:
        raise AssetError("%s: %s" % (path.name, e))
    except (struct.error, IndexError) as e:
        raise AssetError("%s: malformed header (%s)" % (path.name, e))
    raise AssetError("%s: unsupported extension %r" % (path.name, ext))


def png_size(path: Path):
    """(w, h) from the PNG IHDR without Pillow; raises AssetError."""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
    except OSError as e:
        raise AssetError("cannot read %s: %s" % (path, e))
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise AssetError("%s: not a valid PNG" % path.name)
    return struct.unpack(">II", head[16:24])


# ------------------------------------------------------------------ catalog helpers

def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as e:
        raise AssetError("cannot read %s: %s" % (path, e))
    except ValueError as e:
        raise AssetError("invalid JSON in %s: %s" % (path, e))


def validate_entry(e) -> list:
    """Contract validation of one catalog row (header-independent). Returns a list of problems."""
    errs = []
    if not isinstance(e, dict):
        return ["entry is not an object"]
    i = e.get("id")
    if not isinstance(i, str) or not ID_RE.fullmatch(i):
        errs.append("bad id %r" % (i,))
        i = None
    kind = e.get("kind")
    if kind not in ("sfx", "bgm"):
        errs.append("kind must be sfx or bgm")
    elif i and kind != i.split("/")[0]:
        errs.append("kind %s does not match id prefix" % kind)
    p = e.get("path")
    if not isinstance(p, str) or not p.startswith("assets/audio/") or ".." in p or "\\" in p or "\n" in p \
            or "//" in p or not p.endswith((".wav", ".ogg")):
        errs.append("bad path %r" % (p,))
    c = e.get("category")
    if c is not None and not isinstance(c, str):
        errs.append("category must be a string or null")
    if not isinstance(e.get("loop"), bool):
        errs.append("loop must be boolean")
    for k in ("loop_start", "loop_length", "frames", "sample_rate", "channels"):
        v = e.get(k)
        if not isinstance(v, int) or isinstance(v, bool) or v < 0:
            errs.append("%s must be a non-negative integer" % k)
    v = e.get("volume")
    if not isinstance(v, (int, float)) or isinstance(v, bool) or not (0 <= v <= 4):
        errs.append("volume must be in 0..4")
    return errs


def render_catalog(entries: list) -> str:
    return json.dumps({"version": 1, "sounds": sorted(entries, key=lambda e: e["id"])}, indent=2) + "\n"


def load_manifest(root: Path) -> list:
    m = load_json(root / "assets_src" / "audio.json")
    assets = m.get("assets") if isinstance(m, dict) else None
    if not isinstance(assets, list):
        raise AssetError("assets_src/audio.json: missing 'assets' list")
    for a in assets:
        if not isinstance(a, dict):
            raise AssetError("assets_src/audio.json: 'assets' entry is not an object: %r" % (a,))
    return assets


def load_catalog_sounds(cat_path: Path) -> list:
    """Parse catalog.json shape only: an object whose 'sounds' is a list of objects."""
    cat = load_json(cat_path)
    if not isinstance(cat, dict):
        raise AssetError("%s: not a JSON object" % cat_path.name)
    sounds = cat.get("sounds", [])
    if not isinstance(sounds, list) or not all(isinstance(s, dict) for s in sounds):
        raise AssetError("%s: 'sounds' must be a list of objects" % cat_path.name)
    return sounds


def _as_int(v, what: str) -> int:
    if isinstance(v, bool) or not isinstance(v, (int, float)) or (isinstance(v, float) and not v.is_integer()) \
            or v < 0:
        raise AssetError("%s must be a non-negative integer, got %r" % (what, v))
    return int(v)


def _install(dest: Path, write) -> None:
    """Atomically create/replace dest: write(fileobj) into a temp file next to it, then os.replace.
    Raises AssetError on OSError; the temp file is always cleaned up on failure."""
    tmp = None
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(dest.parent), prefix=".tmp-", suffix=".part")
        with os.fdopen(fd, "wb") as f:
            write(f)
        os.chmod(tmp, 0o644)
        os.replace(tmp, dest)
        tmp = None
    except OSError as e:
        raise AssetError("cannot write %s: %s" % (dest, e))
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def _copy_into(src: Path, dest: Path) -> None:
    def w(f):
        with open(src, "rb") as fi:
            shutil.copyfileobj(fi, f)
    try:
        _install(dest, w)
    except AssetError:
        raise
    except OSError as e:  # reading src failed outside _install's handling
        raise AssetError("cannot copy %s: %s" % (src, e))


def _inside(path: Path, base: Path) -> bool:
    try:
        return path.resolve().is_relative_to(base.resolve())
    except (OSError, RuntimeError):
        return False


# ------------------------------------------------------------------ audio sync / build

def audio_sync(root: Path, src: Path, only=None) -> int:
    """`only` (used by `audio build --only`): sync just these ids and carry the other existing entries over.

    Order: validate everything (nothing written on problems) -> copy audio files -> write catalog -> remove stale.
    """
    report = load_json(src / "report.json")
    if not isinstance(report, dict):
        raise AssetError("report.json: not a JSON object")
    rassets = report.get("assets")
    if not isinstance(rassets, list) or not all(isinstance(e, dict) for e in rassets):
        raise AssetError("report.json: 'assets' must be a list of objects")
    by_id = {e["id"]: e for e in rassets if isinstance(e.get("id"), str)}
    manifest = load_manifest(root)
    audio_dir = root / "assets" / "audio"
    cat_path = audio_dir / "catalog.json"
    old_vol, old_entries = {}, {}
    if cat_path.exists():
        for s in load_catalog_sounds(cat_path):
            if isinstance(s.get("id"), str):
                old_vol[s["id"]] = s.get("volume", 1.0)
                old_entries[s["id"]] = s

    problems, plan, entries = [], [], []
    if only is not None:
        known = {a.get("id") for a in manifest if isinstance(a, dict) and isinstance(a.get("id"), str)}
        for oid in sorted(only - known):
            problems.append("--only %s: not in assets_src/audio.json" % oid)
    for a in manifest:
        aid = a.get("id")
        if not isinstance(aid, str) or not ID_RE.fullmatch(aid):
            problems.append("manifest: bad id %r" % (aid,))
            continue
        if only is not None and aid not in only:
            old = old_entries.get(aid)
            if old is None:
                problems.append("%s: not selected by --only and not in existing catalog" % aid)
                continue
            bad = validate_entry(old)
            if not bad and old.get("id") != aid:
                bad = ["id mismatch"]
            if not bad and old["path"] != "assets/audio/%s%s" % (aid, Path(old["path"]).suffix):
                bad = ["path %r does not match id" % old["path"]]
            if not bad:
                if not (root / old["path"]).is_file() or not _inside(root / old["path"], audio_dir):
                    bad = ["file %s missing or outside assets/audio" % old["path"]]
            if bad:
                problems.append("%s: existing catalog entry cannot be carried over: %s" % (aid, "; ".join(bad)))
                continue
            entries.append(old)
            plan.append((None, root / old["path"]))
            continue
        r = by_id.get(aid)
        if r is None:
            problems.append("%s: not in report" % aid)
            continue
        if r.get("status") != "ok":
            problems.append("%s: status %s (%s)" % (aid, r.get("status"), r.get("error")))
            continue
        final = r.get("final")
        if final is None or final == "":
            problems.append("%s: report entry has no 'final'" % aid)
            continue
        if not isinstance(final, str) or "\0" in final:
            problems.append("%s: report 'final' must be a string path, got %r" % (aid, final))
            continue
        fpath = src / final
        if not _inside(fpath, src):
            problems.append("%s: report 'final' %r escapes the report directory" % (aid, final))
            continue
        ext = fpath.suffix.lower()
        if ext not in (".wav", ".ogg"):
            problems.append("%s: unsupported extension %s" % (aid, ext))
            continue
        if not fpath.is_file():
            problems.append("%s: missing file %s" % (aid, fpath))
            continue
        try:
            hdr = parse_audio_file(fpath)
        except AssetError as e:
            problems.append("%s: %s" % (aid, e))
            continue
        loop = r.get("loop", a.get("loop", False))
        if not isinstance(loop, bool):
            problems.append("%s: 'loop' must be a boolean, got %r" % (aid, loop))
            continue
        master = r.get("master")
        if master is None:
            master = {}
        if not isinstance(master, dict):
            problems.append("%s: report 'master' must be an object" % aid)
            continue
        ls = ll = 0
        if loop:
            try:
                ls = _as_int(master.get("loop_start", 0), "master.loop_start")
                ll = _as_int(master.get("loop_length", hdr["frames"]), "master.loop_length")
            except AssetError as e:
                problems.append("%s: %s" % (aid, e))
                continue
        dest_rel = "assets/audio/%s%s" % (aid, ext)
        entry = {
            "id": aid, "path": dest_rel, "kind": aid.split("/")[0],
            "category": r.get("category", a.get("category")), "loop": loop,
            "loop_start": ls, "loop_length": ll, "frames": hdr["frames"],
            "sample_rate": hdr["sample_rate"], "channels": hdr["channels"],
            "volume": old_vol.get(aid, 1.0),
        }
        bad = validate_entry(entry)
        if bad:
            problems.append("%s: %s" % (aid, "; ".join(bad)))
            continue
        plan.append((fpath, root / dest_rel))
        entries.append(entry)
    if problems:
        print("audio sync failed; nothing written:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 1

    # 1. audio files (atomic per file)
    copied = 0
    for s, d in plan:
        if s is None:
            continue
        try:
            same = d.is_file() and d.read_bytes() == s.read_bytes()
        except OSError as e:
            raise AssetError("cannot read %s or %s: %s" % (s, d, e))
        if not same:
            _copy_into(s, d)
            copied += 1
    # 2. catalog (atomic), written only after every audio file is in place
    text = render_catalog(entries)
    try:
        cur = cat_path.read_text(encoding="utf-8") if cat_path.exists() else None
    except (OSError, ValueError) as e:
        raise AssetError("cannot read %s: %s" % (cat_path, e))
    if cur != text:
        _install(cat_path, lambda f: f.write(text.encode("utf-8")))
    # 3. stale audio files (only .wav/.ogg; README, .gitkeep etc. are left alone), last of all
    keep = {d.resolve() for _s, d in plan}
    removed = 0
    try:
        for f in sorted(audio_dir.rglob("*")):
            if f.is_file() and f.suffix.lower() in (".wav", ".ogg") and f.resolve() not in keep:
                f.unlink()
                removed += 1
                parent = f.parent
                while parent != audio_dir and parent.is_dir() and not any(parent.iterdir()):
                    parent.rmdir()
                    parent = parent.parent
    except OSError as e:
        raise AssetError("cannot remove stale audio files: %s" % e)
    print("audio sync: %d sounds, %d files copied, %d stale removed" % (len(entries), copied, removed))
    return 0


def audio_build(root: Path, args) -> int:
    ph = Path(args.pixel_hero or os.environ.get("PIXEL_HERO_DEMO") or (root.parent / "pixel-hero-demo"))
    if not (ph / "audio" / "build.py").is_file():
        print("pixel-hero-demo not found at %s (use --pixel-hero or PIXEL_HERO_DEMO)" % ph, file=sys.stderr)
        return 1
    out = Path(args.out) if args.out else root / "out" / "audio"
    if not out.is_absolute():
        out = Path.cwd() / out
    cmd = [sys.executable, "-m", "audio.build", str(out), "--manifest", str(root / "assets_src" / "audio.json"),
           "--check", "--skip-missing"]
    if args.only:
        cmd += ["--only", *args.only]
    print("+ (cd %s) %s" % (ph, " ".join(cmd)))
    rc = subprocess.call(cmd, cwd=str(ph))
    if rc != 0:
        print("audio.build exited with %d" % rc, file=sys.stderr)
        return rc
    return audio_sync(root, out, set(args.only) if args.only else None)


# ------------------------------------------------------------------ art

def load_art(root: Path) -> dict:
    a = load_json(root / "assets_src" / "art.json")
    if not isinstance(a, dict) or a.get("version") != 1 or not isinstance(a.get("art"), list):
        raise AssetError("assets_src/art.json: expected {version: 1, art: [...]}")
    for e in a["art"]:
        if not isinstance(e, dict):
            raise AssetError("art.json: entry is not an object")
        for k in ("name", "dest", "size", "frame", "source"):
            if k not in e:
                raise AssetError("art.json: entry %r missing %r" % (e.get("name"), k))
        if not isinstance(e["name"], str) or not ART_NAME_RE.fullmatch(e["name"]):
            raise AssetError("art.json: bad name %r (allowed: letters, digits, _ and -)" % (e["name"],))
        d = e["dest"]
        parts = d.split("/") if isinstance(d, str) else []
        if not isinstance(d, str) or d.startswith("/") or "\\" in d or "\0" in d or not d.endswith(".png") \
                or len(parts) < 2 or parts[0] != "assets" or any(x in ("", ".", "..") for x in parts):
            raise AssetError("art.json: %s: bad dest %r (must be a relative path under assets/ ending in .png, "
                             "no '..')" % (e["name"], d))
        if e["source"] not in ART_SOURCES:
            raise AssetError("art.json: %s: bad source %r" % (e["name"], e["source"]))
        for k in ("size", "frame"):
            v = e[k]
            if not (isinstance(v, list) and len(v) == 2 and all(isinstance(x, int) and x > 0 for x in v)):
                raise AssetError("art.json: %s: %s must be [w, h]" % (e["name"], k))
    return a


def load_palette(root: Path, art: dict):
    p = art.get("palette")
    if not p:
        return None
    if not isinstance(p, str):
        raise AssetError("art.json: palette must be null or a path string")
    data = load_json(root / p)
    if isinstance(data, dict):
        vals = []
        for v in data.values():
            if isinstance(v, list):
                vals.extend(v)
            else:
                vals.append(v)
        data = vals
    if not isinstance(data, list):
        raise AssetError("palette %s: expected a list of hex colours" % p)
    out = set()
    for h in data:
        if not isinstance(h, str) or not HEX_RE.fullmatch(h):
            raise AssetError("palette %s: bad colour %r" % (p, h))
        h = h.lstrip("#")
        out.add((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    return out


def check_png(path: Path, entry: dict, palette) -> tuple:
    """Full image check (needs Pillow). Returns (errors, warnings)."""
    try:
        from PIL import Image
    except ImportError:
        raise AssetError("Pillow is required for art import (pip install Pillow)")
    errs, warns = [], []
    try:
        im = Image.open(path)
        im.load()
    except Exception as e:
        return ["%s: cannot read image: %s" % (path.name, e)], warns
    w, h = im.size
    if [w, h] != list(entry["size"]):
        errs.append("%s: size %dx%d, expected %dx%d" % (path.name, w, h, *entry["size"]))
    fw, fh = entry["frame"]
    if w % fw or h % fh:
        errs.append("%s: size %dx%d not divisible by frame %dx%d" % (path.name, w, h, fw, fh))
    if im.mode != "RGBA":
        errs.append("%s: mode is %s, expected RGBA" % (path.name, im.mode))
        return errs, warns
    px = im.getdata()
    semi = sum(1 for p in px if 0 < p[3] < 255)
    if semi:
        warns.append("%s: %d semi-transparent pixels (alpha cutoff is 0.5)" % (path.name, semi))
    if palette is not None:
        off = {p[:3] for p in px if p[3] == 255} - palette
        if off:
            errs.append("%s: %d colours not in palette, e.g. %s" % (
                path.name, len(off), ", ".join("#%02X%02X%02X" % c for c in sorted(off)[:3])))
    return errs, warns


def art_import(root: Path, src: Path, only) -> int:
    art = load_art(root)
    palette = load_palette(root, art)
    names = {e["name"] for e in art["art"]}
    for n in only or []:
        if n not in names:
            raise AssetError("unknown art name %r" % n)
    todo = [e for e in art["art"] if e["source"] in ("genai", "pixelflow") and (not only or e["name"] in only)]
    if not todo:
        print("art import: nothing to import (no genai/pixelflow entries selected)")
        return 0
    errors, plan = [], []
    for e in todo:
        f = src / ("%s.png" % e["name"])
        if not f.is_file():
            errors.append("%s: missing %s" % (e["name"], f))
            continue
        errs, warns = check_png(f, e, palette)
        for w in warns:
            print("warning: " + w, file=sys.stderr)
        errors += errs
        if not errs:
            if not _inside((root / e["dest"]).parent, root):
                errors.append("%s: dest %s resolves outside the project" % (e["name"], e["dest"]))
                continue
            plan.append((f, root / e["dest"]))
    if errors:
        print("art import failed; nothing copied:", file=sys.stderr)
        for m in errors:
            print("  - " + m, file=sys.stderr)
        return 1
    for f, d in plan:
        _copy_into(f, d)
        print("art import: %s -> %s" % (f.name, d.relative_to(root)))
    return 0


# ------------------------------------------------------------------ check

_LONG_OPEN_RE = re.compile(r"\[(=*)\[")


def strip_lua_comments(src: str) -> str:
    """Blank out Lua comments (-- line, --[[ ]] / --[==[ ]==] block) with spaces, keeping newlines so line numbers
    stay valid. String literals (quoted, with escapes, and [[long]] strings) are copied verbatim, so a "--" inside a
    string does not start a comment."""
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
        elif c == '"' or c == "'":
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


def scan_lua(root: Path):
    """Yield (relpath, line, fn, id) for string-literal audio.sfx/sfx_var/bgm calls (comments ignored)."""
    for f in sorted((root / "assets").rglob("*.lua")):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        text = strip_lua_comments(text)
        for m in LUA_CALL_RE.finditer(text):
            yield f.relative_to(root).as_posix(), text.count("\n", 0, m.start()) + 1, m.group(1), m.group(3)


def run_checks(root: Path) -> list:
    """Return [(group, [errors], [warnings])]."""
    groups = []
    cat_path = root / "assets" / "audio" / "catalog.json"
    errs, warns = [], []
    sounds = []
    try:
        cat = load_json(cat_path)
        if not isinstance(cat, dict) or cat.get("version") != 1 or not isinstance(cat.get("sounds"), list):
            errs.append("catalog.json: expected {version: 1, sounds: [...]}")
        else:
            sounds = cat["sounds"]
    except AssetError as e:
        errs.append(str(e))
    ids = [s.get("id") if isinstance(s, dict) else None for s in sounds]
    if ids != sorted(ids, key=lambda x: str(x)):
        errs.append("catalog.json: sounds not sorted by id")
    seen = set()
    for s in sounds:
        for p in validate_entry(s):
            errs.append("%s: %s" % (s.get("id") if isinstance(s, dict) else "?", p))
        i = s.get("id") if isinstance(s, dict) else None
        if isinstance(i, str):
            if i in seen:
                errs.append("%s: duplicate id" % i)
            seen.add(i)
    groups.append(("catalog contract", errs, warns))

    errs, warns = [], []
    for s in sounds:
        if validate_entry(s):
            continue
        i, p = s["id"], root / s["path"]
        if not p.is_file():
            errs.append("%s: file missing: %s" % (i, s["path"]))
            continue
        try:
            h = parse_audio_file(p)
        except AssetError as e:
            errs.append("%s: %s" % (i, e))
            continue
        for k in ("frames", "sample_rate", "channels"):
            if h[k] != s[k]:
                errs.append("%s: catalog %s=%s but file has %s" % (i, k, s[k], h[k]))
        if h["sample_rate"] != 48000:
            errs.append("%s: sample rate %d, want 48000" % (i, h["sample_rate"]))
        if s["kind"] == "sfx" and h["channels"] != 1:
            errs.append("%s: sfx must be mono, has %d channels" % (i, h["channels"]))
        if s["kind"] == "bgm":
            if h["channels"] != 2:
                errs.append("%s: bgm must be stereo, has %d channels" % (i, h["channels"]))
            if not s["path"].endswith(".ogg"):
                errs.append("%s: bgm must be .ogg" % i)
        if s["loop"] and s["loop_start"] + s["loop_length"] > s["frames"]:
            errs.append("%s: loop region exceeds frames" % i)
    groups.append(("audio files", errs, warns))

    errs, warns = [], []
    try:
        manifest_ids = {a.get("id") for a in load_manifest(root) if isinstance(a.get("id"), str)}
        cat_ids = {i for i in ids if isinstance(i, str) and i}
        for i in sorted(manifest_ids - cat_ids):
            errs.append("%s: in assets_src/audio.json but not in catalog" % i)
        for i in sorted(cat_ids - manifest_ids):
            errs.append("%s: in catalog but not in assets_src/audio.json" % i)
    except AssetError as e:
        errs.append(str(e))
    groups.append(("manifest vs catalog", errs, warns))

    errs, warns = [], []
    try:
        for e in load_art(root)["art"]:
            p = root / e["dest"]
            if not p.is_file():
                errs.append("%s: missing %s" % (e["name"], e["dest"]))
                continue
            try:
                w, h = png_size(p)
            except AssetError as ex:
                errs.append("%s: %s" % (e["name"], ex))
                continue
            if [w, h] != e["size"]:
                errs.append("%s: size %dx%d, art.json says %dx%d" % (e["name"], w, h, *e["size"]))
            if w % e["frame"][0] or h % e["frame"][1]:
                errs.append("%s: size not divisible by frame" % e["name"])
    except AssetError as ex:
        errs.append(str(ex))
    groups.append(("art manifest", errs, warns))

    errs, warns = [], []
    kinds = {s["id"]: s["kind"] for s in sounds if isinstance(s, dict) and isinstance(s.get("id"), str)
             and isinstance(s.get("kind"), str)}
    for rel, n, fn, i in scan_lua(root):
        want = "bgm" if fn == "bgm" else "sfx"
        if i not in kinds:
            errs.append("%s:%d: audio.%s(%r): unknown id" % (rel, n, fn, i))
        elif kinds[i] != want:
            errs.append("%s:%d: audio.%s(%r): id is kind %s" % (rel, n, fn, i, kinds[i]))
    groups.append(("lua audio ids", errs, warns))

    errs, warns = [], []
    fonts_cfg_path = root / "assets_src" / "fonts.json"
    if fonts_cfg_path.is_file():
        try:
            import bake_font as _bf
            fcfg = json.loads(fonts_cfg_path.read_text(encoding="utf-8"))
            errs.extend(_bf.check_fonts(fcfg, root))
        except Exception as ex:
            errs.append(f"font check failed: {ex}")
    groups.append(("fonts", errs, warns))
    return groups


def write_junit(path: Path, groups, seconds: float):
    suite = ET.Element("testsuite", name="assets", tests=str(len(groups)),
                       failures=str(sum(1 for _g, e, _w in groups if e)), time="%.3f" % seconds)
    for name, errs, warns in groups:
        tc = ET.SubElement(suite, "testcase", classname="assets", name=name)
        if errs:
            f = ET.SubElement(tc, "failure", message="%d error(s)" % len(errs))
            f.text = "\n".join(errs)
        if warns:
            ET.SubElement(tc, "system-out").text = "\n".join(warns)
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(str(path), encoding="utf-8", xml_declaration=True)


def cmd_check(root: Path, junit) -> int:
    t0 = time.time()
    groups = run_checks(root)
    bad = 0
    for name, errs, warns in groups:
        print("%s %s" % ("FAIL" if errs else "ok  ", name))
        for m in errs:
            print("    error: " + m)
        for m in warns:
            print("    warning: " + m)
        bad += len(errs)
    if junit:
        write_junit(Path(junit), groups, time.time() - t0)
    print("check: %d error(s)" % bad)
    return 1 if bad else 0


# ------------------------------------------------------------------ main

def main(argv=None, root: Path = ROOT) -> int:
    ap = argparse.ArgumentParser(prog="assets.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("placeholder", help="run tools/gen_m2_placeholders.py")
    au = sub.add_parser("audio").add_subparsers(dest="sub", required=True)
    b = au.add_parser("build")
    b.add_argument("--pixel-hero")
    b.add_argument("--only", nargs="+", metavar="ID")
    b.add_argument("--out")
    s = au.add_parser("sync")
    s.add_argument("--from", dest="src", required=True)
    ar = sub.add_parser("art").add_subparsers(dest="sub", required=True)
    i = ar.add_parser("import")
    i.add_argument("--from", dest="src", required=True)
    i.add_argument("--only", nargs="+", metavar="NAME")
    c = sub.add_parser("check")
    c.add_argument("--junit")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "placeholder":
            return subprocess.call([sys.executable, "-I", str(root / "tools" / "gen_m2_placeholders.py")])
        if args.cmd == "audio" and args.sub == "build":
            return audio_build(root, args)
        if args.cmd == "audio" and args.sub == "sync":
            return audio_sync(root, Path(args.src))
        if args.cmd == "art":
            return art_import(root, Path(args.src), args.only)
        if args.cmd == "check":
            return cmd_check(root, args.junit)
    except AssetError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    except OSError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
