#!/usr/bin/env python3
"""Pilot Art Generator (A2 & A3): generates wasteland-palette char_marcus.png (512x768) and tiles.png (512x512)."""
from pathlib import Path
import importlib.util
import json
import random
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent.parent.parent
PALETTE_PATH = ROOT / "assets_src" / "palette" / "wasteland.json"
ASSETS = ROOT / "assets"


def hex_rgba(h: str, a: int = 255) -> tuple[int, int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def load_palette() -> dict[str, list[tuple[int, int, int, int]]]:
    raw = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    return {k: [hex_rgba(c) for c in v] for k, v in raw.items()}


def add_1px_outline(cell: Image.Image, outline_col: tuple[int, int, int, int]) -> Image.Image:
    w, h = cell.size
    src = cell.load()
    out = cell.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                        dst[x, y] = outline_col
                        break
    return out


def draw_survivor_frame(pal: dict, facing: int, action: str, fidx: int) -> Image.Image:
    """Render one 64x96 survivor frame at 2px pixel scale (32x48 logical grid upscaled 2x) for crispness."""
    lw, lh = 32, 48
    img = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    out0 = pal["outline"][0]
    out1 = pal["outline"][1]
    parka_dark, parka_mid, parka_hi, parka_lit = pal["cloth_a"]
    pants_dark, pants_mid = pal["concrete"][1], pal["concrete"][2]
    skin_sh, skin_mid, skin_hi = pal["skin_a"][0], pal["skin_a"][1], pal["skin_a"][2]
    scarf_dark, scarf_mid, scarf_hi = pal["rust"][1], pal["rust"][3], pal["fire"][2]
    pack_dark, pack_mid, pack_hi = pal["wood"][1], pal["wood"][2], pal["wood"][3]
    fur_mid, fur_hi = pal["snow"][1], pal["snow"][2]

    # Animation offsets
    bob = 0
    leg_l_dx, leg_r_dx = 0, 0
    leg_l_dy, leg_r_dy = 0, 0
    arm_swing = 0
    crouch_dy = 0
    tilt_x = 0

    if action == "idle":
        bob = 1 if (fidx % 2 == 1) else 0
    elif action == "walk":
        cycle = [(-2, 0, 2, -1, 2), (-1, -1, 1, 0, 1), (2, -1, -2, 0, -2), (1, 0, -1, -1, -1)]
        leg_l_dx, leg_l_dy, leg_r_dx, leg_r_dy, arm_swing = cycle[fidx % 4]
        bob = -1 if (fidx % 2 == 1) else 0
    elif action == "crouch":
        crouch_dy = 6
    elif action == "attack":
        arm_swing = [2, 5, 3][fidx % 3]
        tilt_x = 1 if fidx == 1 else 0
    elif action == "interact":
        arm_swing = 3
        crouch_dy = 2 if (fidx % 2 == 1) else 0
    elif action == "hurt":
        tilt_x = -2
    elif action == "dead":
        # Lying down pose
        d.rectangle((6, 36, 26, 43), fill=parka_mid)
        d.rectangle((6, 36, 14, 41), fill=parka_hi)
        d.rectangle((20, 37, 26, 42), fill=pants_mid)
        d.rectangle((7, 35, 11, 39), fill=scarf_mid)
        big = img.resize((64, 96), Image.NEAREST)
        return add_1px_outline(big, out0)

    cx = 16 + tilt_x
    base_y = 43 + bob

    # Direction helpers: 0=SE (front-right), 1=SW (front-left), 2=NE (back-right)
    face_front = facing in (0, 1)
    dir_sign = 1 if facing in (0, 2) else -1

    # Backpack (protrudes 2-3px behind)
    bp_x = cx - dir_sign * 5
    bp_y = 20 + bob + crouch_dy
    if facing == 2:
        # Back view: backpack prominent in center-back
        d.rectangle((cx - 5, bp_y, cx + 4, bp_y + 11), fill=pack_mid)
        d.rectangle((cx - 4, bp_y + 1, cx + 3, bp_y + 3), fill=pack_hi)
        d.rectangle((cx - 5, bp_y + 8, cx + 4, bp_y + 11), fill=pack_dark)
    else:
        d.rectangle((min(bp_x - 2, bp_x + 2), bp_y + 1, max(bp_x - 2, bp_x + 2), bp_y + 10), fill=pack_dark)
        d.rectangle((bp_x - 1, bp_y + 2, bp_x + 1, bp_y + 8), fill=pack_mid)

    # Legs & boots
    ly = 33 + crouch_dy
    d.rectangle((cx - 4 + leg_l_dx, ly + leg_l_dy, cx - 1 + leg_l_dx, base_y - 2 + leg_l_dy), fill=pants_mid)
    d.rectangle((cx - 4 + leg_l_dx, base_y - 2 + leg_l_dy, cx - 1 + leg_l_dx, base_y + leg_l_dy), fill=out1)
    d.rectangle((cx + 1 + leg_r_dx, ly + leg_r_dy, cx + 4 + leg_r_dx, base_y - 2 + leg_r_dy), fill=pants_dark)
    d.rectangle((cx + 1 + leg_r_dx, base_y - 2 + leg_r_dy, cx + 4 + leg_r_dx, base_y + leg_r_dy), fill=out1)

    # Torso (parka)
    ty = 20 + bob + crouch_dy
    d.rectangle((cx - 5, ty, cx + 5, ly + 1), fill=parka_mid)
    d.rectangle((cx - 5, ty, cx - 2, ly), fill=parka_hi)
    d.rectangle((cx + 2, ty + 2, cx + 5, ly + 1), fill=parka_dark)
    # Fur hem
    d.rectangle((cx - 5, ly, cx + 5, ly + 1), fill=fur_mid)

    # Scarf
    d.rectangle((cx - 4, ty - 1, cx + 4, ty + 2), fill=scarf_mid)
    d.rectangle((cx - 3, ty - 1, cx, ty + 1), fill=scarf_hi)
    # Scarf tail
    d.rectangle((cx - dir_sign * 4, ty + 2, cx - dir_sign * 2, ty + 5), fill=scarf_dark)

    # Front arm
    ax = cx + dir_sign * 4 + (arm_swing * dir_sign // 2)
    ay = ty + 2
    d.rectangle((ax - 1, ay, ax + 2, ay + 8), fill=parka_lit if dir_sign < 0 else parka_mid)
    d.rectangle((ax - 1, ay + 7, ax + 1, ay + 9), fill=skin_mid if face_front else out1)

    # Head + fur-trimmed hood
    hy = 10 + bob + crouch_dy
    d.rectangle((cx - 4, hy, cx + 4, hy + 9), fill=parka_mid)
    d.rectangle((cx - 4, hy, cx - 1, hy + 4), fill=parka_hi)
    if face_front:
        fx0 = cx - 2 if facing == 1 else cx - 1
        d.rectangle((fx0, hy + 2, fx0 + 4, hy + 8), fill=skin_mid)
        d.rectangle((fx0, hy + 2, fx0 + 2, hy + 5), fill=skin_hi)
        # Eyes
        ex = fx0 + (1 if facing == 1 else 2)
        d.point((ex, hy + 5), fill=out0)
        d.point((ex + 2, hy + 5), fill=out0)
        # Hood fur rim
        d.rectangle((cx - 4, hy + 1, cx + 4, hy + 2), fill=fur_hi)
    else:
        # Back of hood
        d.rectangle((cx - 3, hy + 1, cx + 3, hy + 7), fill=parka_dark)
        d.rectangle((cx - 4, hy + 1, cx + 4, hy + 2), fill=fur_mid)

    big = img.resize((64, 96), Image.NEAREST)
    return add_1px_outline(big, out0)


def make_char_marcus(pal: dict) -> Image.Image:
    sheet = Image.new("RGBA", (512, 768), (0, 0, 0, 0))
    # 3 facings (SE=0->rows 0..1, SW=1->rows 2..3, NE=2->rows 4..5)
    # 16 actions slots per facing:
    # 0..1 idle, 2..5 walk, 6..7 crouch, 8..10 attack, 11..12 interact, 13 hurt, 14..15 dead
    actions = [
        ("idle", 0), ("idle", 1),
        ("walk", 0), ("walk", 1), ("walk", 2), ("walk", 3),
        ("crouch", 0), ("crouch", 1),
        ("attack", 0), ("attack", 1), ("attack", 2),
        ("interact", 0), ("interact", 1),
        ("hurt", 0),
        ("dead", 0), ("dead", 1),
    ]
    for facing_idx, row_base in ((0, 0), (1, 2), (2, 4)):
        for i, (act, fidx) in enumerate(actions):
            slot = row_base * 8 + i
            col = slot % 8
            row = slot // 8
            cell = draw_survivor_frame(pal, facing_idx, act, fidx)
            sheet.paste(cell, (col * 64, row * 96))
    return sheet


def fill_cell(sheet: Image.Image, idx: int, draw_fn):
    col = idx % 8
    row = idx // 8
    cell = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw_fn(cell, ImageDraw.Draw(cell))
    sheet.paste(cell, (col * 64, row * 64))


def placeholder_atlas() -> Image.Image:
    """The full P1 placeholder atlas (tools/gen_m2_placeholders.py); pilot cells are pasted over it."""
    spec = importlib.util.spec_from_file_location("gen_m2_placeholders", ROOT / "tools" / "gen_m2_placeholders.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.make_tiles().convert("RGBA")


def make_tiles(pal: dict) -> Image.Image:
    rng = random.Random(20260514)
    # Start from the complete placeholder atlas so cells the pilot does not draw stay visible.
    sheet = placeholder_atlas()

    def solid_noise(base_col, speckles):
        def _fn(cell, d):
            d.rectangle((0, 0, 63, 63), fill=base_col)
            px = cell.load()
            for col, count in speckles:
                for _ in range(count):
                    x, y = rng.randrange(0, 64, 2), rng.randrange(0, 64, 2)
                    px[x, y] = col
                    px[x + 1, y] = col
        return _fn

    # 0,1,2: snow, snow_drift, snow_packed
    fill_cell(sheet, 0, solid_noise(pal["snow"][3], [(pal["snow"][2], 24), (pal["snow"][4], 18)]))
    fill_cell(sheet, 1, solid_noise(pal["snow"][2], [(pal["snow"][1], 28), (pal["snow"][3], 24)]))
    fill_cell(sheet, 2, solid_noise(pal["snow"][1], [(pal["snow"][0], 26), (pal["snow"][2], 20)]))
    # 3: ice
    def draw_ice(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["ice"][2])
        for k in range(0, 64, 16):
            d.line((k, 0, k + 14, 28), fill=pal["ice"][4], width=1)
            d.line((k + 4, 32, k + 18, 60), fill=pal["ice"][1], width=1)
    fill_cell(sheet, 3, draw_ice)

    # 4,5: asphalt & asphalt_line
    fill_cell(sheet, 4, solid_noise(pal["concrete"][1], [(pal["concrete"][0], 40), (pal["concrete"][2], 28)]))
    def draw_asphalt_line(cell, d):
        solid_noise(pal["concrete"][1], [(pal["concrete"][0], 35), (pal["concrete"][2], 25)])(cell, d)
        d.rectangle((10, 28, 53, 35), fill=pal["snow"][3])
    fill_cell(sheet, 5, draw_asphalt_line)

    # 6: sidewalk
    def draw_sidewalk(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["concrete"][3])
        d.line((0, 31, 63, 31), fill=pal["concrete"][2], width=2)
        d.line((31, 0, 31, 63), fill=pal["concrete"][2], width=2)
    fill_cell(sheet, 6, draw_sidewalk)

    # 8,10,12,15: indoor wood, carpet, tile, concrete_floor
    def draw_planks(base, line_col, hi_col):
        def _fn(cell, d):
            d.rectangle((0, 0, 63, 63), fill=base)
            for y in range(0, 64, 16):
                d.line((0, y, 63, y), fill=line_col, width=2)
                d.line((0, y + 2, 63, y + 2), fill=hi_col, width=1)
                jx = ((y * 3) + 20) % 48 + 8
                d.line((jx, y, jx, y + 15), fill=line_col, width=2)
        return _fn

    fill_cell(sheet, 8, draw_planks(pal["wood"][2], pal["wood"][0], pal["wood"][3]))
    fill_cell(sheet, 10, solid_noise(pal["cloth_a"][1], [(pal["cloth_a"][0], 50), (pal["cloth_a"][2], 30)]))
    def draw_tile_floor(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["concrete"][4])
        for y in range(0, 64, 16):
            d.line((0, y, 63, y), fill=pal["concrete"][3], width=1)
        for x in range(0, 64, 16):
            d.line((x, 0, x, 63), fill=pal["concrete"][3], width=1)
    fill_cell(sheet, 12, draw_tile_floor)
    fill_cell(sheet, 15, solid_noise(pal["concrete"][2], [(pal["concrete"][1], 32), (pal["concrete"][3], 24)]))

    # 24: brick wall side
    def draw_brick(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["rust"][2])
        for row, y in enumerate(range(0, 64, 12)):
            d.line((0, y, 63, y), fill=pal["rust"][0], width=2)
            off = 12 if (row % 2 == 1) else 0
            for x in range(off, 64, 24):
                d.line((x, y, x, min(63, y + 11)), fill=pal["rust"][0], width=2)
    fill_cell(sheet, 24, draw_brick)

    # 26: siding wall side
    fill_cell(sheet, 26, draw_planks(pal["cloth_a"][2], pal["cloth_a"][0], pal["cloth_a"][3]))
    # 28: concrete wall side
    fill_cell(sheet, 28, solid_noise(pal["concrete"][2], [(pal["concrete"][1], 30), (pal["concrete"][3], 20)]))
    # 32: plaster wall side
    fill_cell(sheet, 32, solid_noise(pal["snow"][1], [(pal["dead"][3], 22), (pal["snow"][0], 16)]))

    # 40: door_closed, 42: door_open, 43: window
    def draw_door_closed(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["wood"][1])
        d.rectangle((8, 6, 55, 63), fill=pal["wood"][2], outline=pal["outline"][0], width=2)
        d.rectangle((14, 12, 49, 32), outline=pal["wood"][0], width=2)
        d.rectangle((14, 38, 49, 58), outline=pal["wood"][0], width=2)
        d.rectangle((44, 33, 49, 37), fill=pal["fire"][3])
    fill_cell(sheet, 40, draw_door_closed)
    fill_cell(sheet, 42, lambda c, d: d.rectangle((0, 0, 63, 63), fill=pal["outline"][1]))

    def draw_window(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["concrete"][2])
        d.rectangle((8, 10, 55, 52), fill=pal["ice"][3], outline=pal["outline"][0], width=2)
        d.line((31, 10, 31, 52), fill=pal["wood"][1], width=2)
        d.line((8, 31, 55, 31), fill=pal["wood"][1], width=2)
        d.line((12, 16, 24, 28), fill=pal["ice"][4], width=2)
    fill_cell(sheet, 43, draw_window)

    # 48..54: side faces
    fill_cell(sheet, 48, solid_noise(pal["snow"][1], [(pal["snow"][0], 20)]))
    fill_cell(sheet, 49, solid_noise(pal["ice"][1], [(pal["ice"][0], 20)]))
    fill_cell(sheet, 50, solid_noise(pal["concrete"][1], [(pal["concrete"][0], 20)]))
    fill_cell(sheet, 52, solid_noise(pal["wood"][1], [(pal["wood"][0], 20)]))
    fill_cell(sheet, 54, solid_noise(pal["concrete"][1], [(pal["concrete"][2], 20)]))

    # 57: roof_snow
    def draw_roof_snow(cell, d):
        d.rectangle((0, 0, 63, 63), fill=pal["snow"][2])
        for y in range(0, 64, 16):
            d.line((0, y, 63, y), fill=pal["snow"][1], width=2)
        d.line((0, 0, 63, 0), fill=pal["snow"][4], width=2)
    fill_cell(sheet, 57, draw_roof_snow)

    # 60, 61: side_cap (lintel / wall_cap)
    fill_cell(sheet, 60, draw_brick)
    fill_cell(sheet, 61, draw_planks(pal["wood"][1], pal["wood"][0], pal["wood"][2]))

    # Cells the pilot does not draw (41, 53, 56, 62, 63, ...) keep their placeholder art.
    return sheet


def main():
    pal = load_palette()
    (ASSETS / "sprites").mkdir(parents=True, exist_ok=True)
    (ASSETS / "textures").mkdir(parents=True, exist_ok=True)
    make_char_marcus(pal).save(ASSETS / "sprites" / "char_marcus.png")
    make_tiles(pal).save(ASSETS / "textures" / "tiles.png")
    print("Generated pilot char_marcus.png and palette-quantized tiles.png.")


if __name__ == "__main__":
    main()
