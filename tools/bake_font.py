#!/usr/bin/env python3
"""Offline bitmap font baker for Thirty Below (WSFN v1 format).

Scans assets/i18n/*.lua for all used codepoints (+ ASCII 32..126 and extra_chars),
renders glyphs deterministically into PNG atlases + WSFN binary .fnt metric files.

Usage:
  python3 tools/bake_font.py [--config assets_src/fonts.json] [--root .]
  python3 tools/bake_font.py --check [--config assets_src/fonts.json] [--root .]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HEADER_STRUCT = struct.Struct("<4sHHHHHHII8x")
GLYPH_STRUCT = struct.Struct("<IHHBBbbB3x")
MAGIC = b"WSFN"
VERSION = 1

STRING_RE = re.compile(r'"((?:\\.|[^"\\])*)"|\'((?:\\.|[^\'\\])*)\'')


def unescape_lua_str(s: str) -> str:
    out = []
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == "\\" and i + 1 < n:
            nxt = s[i + 1]
            if nxt == "n":
                out.append("\n")
                i += 2
            elif nxt == "t":
                out.append("\t")
                i += 2
            elif nxt == "r":
                out.append("\r")
                i += 2
            elif nxt in ("\\", '"', "'"):
                out.append(nxt)
                i += 2
            elif nxt == "u" and i + 2 < n and s[i + 2] == "{":
                end = s.find("}", i + 3)
                if end != -1:
                    try:
                        out.append(chr(int(s[i + 3 : end], 16)))
                        i = end + 1
                        continue
                    except ValueError:
                        pass
                out.append(ch)
                i += 1
            else:
                out.append(nxt)
                i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def collect_codepoints(i18n_dir: Path, extra_chars: str) -> list[int]:
    cps: set[int] = set(range(32, 127))
    for ch in extra_chars:
        if ord(ch) >= 32:
            cps.add(ord(ch))
    if i18n_dir.is_dir():
        for lua_file in sorted(i18n_dir.glob("*.lua")):
            text = lua_file.read_text(encoding="utf-8")
            for line in text.splitlines():
                # Strip single-line comments outside strings roughly
                stripped = line.lstrip()
                if stripped.startswith("--"):
                    continue
                for m in STRING_RE.finditer(line):
                    raw = m.group(1) if m.group(1) is not None else m.group(2)
                    val = unescape_lua_str(raw)
                    for ch in val:
                        cp = ord(ch)
                        if cp >= 32:
                            cps.add(cp)
    return sorted(cps)


def load_font_chain(sources: list[str], px: int) -> list[ImageFont.FreeTypeFont]:
    loaded = []
    for src in sources:
        if os.path.isfile(src):
            try:
                loaded.append(ImageFont.truetype(src, px))
            except OSError:
                pass
    if not loaded:
        raise RuntimeError(f"No usable font found in sources: {sources}")
    return loaded


def pick_font_for_cp(fonts: list[ImageFont.FreeTypeFont], cp: int) -> ImageFont.FreeTypeFont:
    ch = chr(cp)
    for f in fonts:
        try:
            mask = f.getmask(ch)
            if mask.size[0] > 0 and mask.size[1] > 0:
                return f
        except Exception:
            pass
    return fonts[0]


def render_glyph(font: ImageFont.FreeTypeFont, cp: int, ascent: int):
    ch = chr(cp)
    # Use getbbox + getlength for accurate metrics
    bbox = font.getbbox(ch)
    adv_f = font.getlength(ch)
    advance = max(0, min(255, int(round(adv_f))))

    if bbox is None or cp == 32:
        return None, 0, 0, max(1, advance) if cp == 32 else advance

    left, top, right, bottom = bbox
    w = max(0, right - left)
    h = max(0, bottom - top)
    if w == 0 or h == 0:
        return None, 0, 0, advance

    # Clamp to u8
    w_clamped = min(255, w)
    h_clamped = min(255, h)

    # Render onto temporary L image
    pad = 2
    tmp = Image.new("L", (w + pad * 2, h + pad * 2), 0)
    draw = ImageDraw.Draw(tmp)
    draw.text((pad - left, pad - top), ch, font=font, fill=255)
    cropped = tmp.crop((pad, pad, pad + w_clamped, pad + h_clamped))

    # Build RGBA white + alpha
    rgba = Image.new("RGBA", (w_clamped, h_clamped), (255, 255, 255, 0))
    rgba.putalpha(cropped)

    xoff = max(-128, min(127, int(round(left))))
    yoff = max(-128, min(127, int(round(top))))
    return rgba, xoff, yoff, advance


def pack_atlas(items: list[tuple[int, Image.Image | None, int, int, int]]):
    # Try atlas sizes starting from 256x256 up to 2048x2048
    pad = 1
    for size in (256, 512, 1024, 2048):
        x, y, row_h = pad, pad, 0
        placed = []
        ok = True
        for cp, img, xoff, yoff, adv in items:
            if img is None:
                placed.append((cp, 0, 0, 0, 0, xoff, yoff, adv, None))
                continue
            gw, gh = img.size
            if x + gw + pad > size:
                x = pad
                y += row_h + pad
                row_h = 0
            if y + gh + pad > size:
                ok = False
                break
            placed.append((cp, x, y, gw, gh, xoff, yoff, adv, img))
            x += gw + pad
            if gh > row_h:
                row_h = gh
        if ok:
            return size, size, placed
    raise RuntimeError("Glyphs do not fit in 2048x2048 atlas")


def bake_one(entry: dict, sources: list[str], cps: list[int], out_dir: Path, fallback_cp: int):
    name = entry["name"]
    px = int(entry["px"])
    fonts = load_font_chain(sources, px)
    primary = fonts[0]
    try:
        ascent_m, descent_m = primary.getmetrics()
        ascent = max(1, min(65535, int(ascent_m)))
        line_height = max(px, min(65535, int(ascent_m + descent_m)))
    except Exception:
        ascent = px
        line_height = int(round(px * 1.35))

    items = []
    for cp in cps:
        f = pick_font_for_cp(fonts, cp)
        img, xoff, yoff, adv = render_glyph(f, cp, ascent)
        items.append((cp, img, xoff, yoff, adv))

    atlas_w, atlas_h, placed = pack_atlas(items)
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (255, 255, 255, 0))

    glyph_bytes = bytearray()
    for cp, gx, gy, gw, gh, xoff, yoff, adv, img in placed:
        if img is not None:
            atlas.paste(img, (gx, gy))
        glyph_bytes.extend(GLYPH_STRUCT.pack(cp, gx, gy, gw, gh, xoff, yoff, adv))

    out_dir.mkdir(parents=True, exist_ok=True)
    png_path = out_dir / f"{name}.png"
    fnt_path = out_dir / f"{name}.fnt"

    atlas.save(png_path, format="PNG", optimize=False, compress_level=6)
    header = HEADER_STRUCT.pack(
        MAGIC,
        VERSION,
        px,
        line_height,
        ascent,
        atlas_w,
        atlas_h,
        len(placed),
        fallback_cp,
    )
    fnt_path.write_bytes(header + glyph_bytes)
    return len(placed), atlas_w, atlas_h


def parse_fnt_cps(fnt_path: Path) -> set[int]:
    data = fnt_path.read_bytes()
    if len(data) < HEADER_STRUCT.size:
        raise ValueError(f"{fnt_path}: header too short")
    magic, version, _px, _lh, _asc, aw, ah, count, _fb = HEADER_STRUCT.unpack_from(data, 0)
    if magic != MAGIC or version != VERSION:
        raise ValueError(f"{fnt_path}: bad magic/version")
    expected = HEADER_STRUCT.size + count * GLYPH_STRUCT.size
    if len(data) != expected:
        raise ValueError(f"{fnt_path}: length {len(data)} != {expected}")
    cps = set()
    prev = -1
    for i in range(count):
        cp, x, y, w, h, _xo, _yo, _adv = GLYPH_STRUCT.unpack_from(
            data, HEADER_STRUCT.size + i * GLYPH_STRUCT.size
        )
        if cp <= prev:
            raise ValueError(f"{fnt_path}: unsorted codepoints")
        prev = cp
        if x + w > aw or y + h > ah:
            raise ValueError(f"{fnt_path}: glyph out of bounds")
        cps.add(cp)
    return cps


def check_fonts(cfg: dict, root: Path) -> list[str]:
    errors = []
    i18n_dir = root / cfg["i18n_dir"]
    out_dir = root / cfg["out_dir"]
    cps = set(collect_codepoints(i18n_dir, cfg.get("extra_chars", "")))

    for entry in cfg["fonts"]:
        name = entry["name"]
        fnt_path = out_dir / f"{name}.fnt"
        png_path = out_dir / f"{name}.png"
        if not fnt_path.is_file():
            errors.append(f"missing font metrics: {fnt_path}")
            continue
        if not png_path.is_file():
            errors.append(f"missing font atlas: {png_path}")
            continue
        try:
            have_cps = parse_fnt_cps(fnt_path)
        except ValueError as e:
            errors.append(str(e))
            continue
        missing = sorted(cps - have_cps)
        if missing:
            sample = ", ".join(f"U+{c:04X}({chr(c)})" for c in missing[:5])
            errors.append(f"{name}.fnt missing {len(missing)} glyph(s): {sample}")
    return errors


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Bake bitmap fonts for Winter Survival")
    ap.add_argument("--config", default="assets_src/fonts.json")
    ap.add_argument("--root", default=".")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)

    root = Path(args.root).resolve()
    cfg = json.loads((root / args.config).read_text(encoding="utf-8"))

    if args.check:
        errs = check_fonts(cfg, root)
        if errs:
            for e in errs:
                print(f"font check error: {e}", file=sys.stderr)
            return 1
        return 0

    i18n_dir = root / cfg["i18n_dir"]
    out_dir = root / cfg["out_dir"]
    cps = collect_codepoints(i18n_dir, cfg.get("extra_chars", ""))
    sources = cfg["sources"]
    fallback_cp = int(cfg.get("fallback_cp", 63))

    for entry in cfg["fonts"]:
        n, aw, ah = bake_one(entry, sources, cps, out_dir, fallback_cp)
        print(f"baked {entry['name']} ({entry['px']}px): {n} glyphs -> {aw}x{ah}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
