#!/usr/bin/env python3
"""Generate M2 final-size placeholder tiles, character sheet, door leaf, and props."""
from pathlib import Path
import random
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

# 3x5 bitmap font for cell/frame numbers
FONT_3X5 = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "010", "010"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
}


def draw_num(img: Image.Image, x0: int, y0: int, text: str, fg=(255, 255, 255, 255), bg=(16, 16, 20, 220)):
    px = img.load()
    w, h = img.size
    tw = len(text) * 4 + 1
    for yy in range(y0, min(h, y0 + 7)):
        for xx in range(x0, min(w, x0 + tw)):
            px[xx, yy] = bg
    cx = x0 + 1
    for ch in text:
        pat = FONT_3X5.get(ch, FONT_3X5["0"])
        for r, row in enumerate(pat):
            for c, bit in enumerate(row):
                if bit == "1" and 0 <= cx + c < w and 0 <= y0 + 1 + r < h:
                    px[cx + c, y0 + 1 + r] = fg
        cx += 4


def make_tiles() -> Image.Image:
    rng = random.Random(20260514)
    img = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    row_colors = [
        (196, 212, 224),  # 0: outdoor top (snow/ice/asphalt)
        (124, 96, 72),    # 1: indoor top (wood/carpet/tile)
        (110, 108, 104),  # 2: misc top
        (140, 74, 60),    # 3: exterior wall side
        (158, 152, 140),  # 4: interior wall side
        (108, 86, 66),    # 5: doors/windows
        (132, 138, 146),  # 6: foundation/eaves/fence
        (92, 80, 76),     # 7: roof & side_cap
    ]
    overrides = {
        0: (218, 228, 236), 1: (204, 216, 226), 2: (184, 198, 210), 3: (136, 186, 212),
        4: (68, 72, 78), 5: (78, 82, 88), 6: (146, 150, 154), 7: (94, 78, 62),
        8: (132, 94, 62), 10: (82, 98, 118), 11: (58, 84, 72), 12: (210, 214, 218),
        15: (116, 120, 124), 24: (148, 66, 54), 26: (142, 132, 114), 28: (122, 126, 130),
        40: (118, 78, 46), 41: (92, 100, 108), 42: (24, 24, 28), 43: (118, 168, 196),
        60: (162, 154, 142), 61: (138, 140, 144),
    }

    for idx in range(64):
        col = idx % 8
        row = idx // 8
        ox, oy = col * 64, row * 64
        if idx in (62, 63):
            cell = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            d = ImageDraw.Draw(cell)
            if idx == 62:
                d.ellipse((18, 20, 44, 42), fill=(138, 24, 24, 220))
                d.ellipse((36, 36, 50, 48), fill=(112, 18, 18, 200))
            else:
                d.ellipse((20, 16, 28, 30), fill=(48, 58, 72, 180))
                d.ellipse((34, 32, 42, 46), fill=(48, 58, 72, 180))
            draw_num(cell, 2, 2, str(idx))
            img.paste(cell, (ox, oy))
            continue

        base = overrides.get(idx, tuple(max(30, min(230, c + (col - 3) * 8)) for c in row_colors[row]))
        cell = Image.new("RGBA", (64, 64), base + (255,))
        px = cell.load()
        for y in range(64):
            for x in range(64):
                n = rng.randint(-6, 6)
                r = max(0, min(255, base[0] + n))
                g = max(0, min(255, base[1] + n))
                b = max(0, min(255, base[2] + n))
                if row in (3, 4) and (y % 16 == 0 or ((x + (y // 16) * 16) % 32 == 0)):
                    r, g, b = int(r * 0.8), int(g * 0.8), int(b * 0.8)
                elif idx == 60 and y < 4:
                    r, g, b = 220, 226, 232
                elif idx == 61 and 4 <= y <= 14:
                    r, g, b = 176, 178, 182
                elif x in (0, 63) or y in (0, 63):
                    r, g, b = int(r * 0.85), int(g * 0.85), int(b * 0.85)
                px[x, y] = (r, g, b, 255)
        if idx in (40, 41, 42, 43, 44, 45, 46):
            d = ImageDraw.Draw(cell)
            d.rectangle((14, 10, 50, 60), outline=(30, 28, 32, 255), width=2)
            if idx == 40:
                d.rectangle((42, 34, 46, 38), fill=(210, 140, 60, 255))
            elif idx == 43:
                d.rectangle((18, 14, 46, 42), fill=(156, 208, 232, 255))
        draw_num(cell, 2, 2, str(idx))
        img.paste(cell, (ox, oy))
    return img


def make_char_placeholder() -> Image.Image:
    img = Image.new("RGBA", (512, 768), (0, 0, 0, 0))
    for row in range(8):
        is_ne = row >= 4
        local_row = row % 4
        for col in range(8):
            if local_row == 3 and col >= 4:
                continue  # empty transparent frames
            frame_idx = row * 8 + col
            cell = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
            d = ImageDraw.Draw(cell)

            # Action pose offsets
            bob = 1 if (col % 2 == 1) else 0
            crouch = 8 if (local_row == 1 and col < 6) else 0
            down_pose = (local_row == 3 and col in (2, 3))
            coat = (182, 92, 62, 255) if not is_ne else (120, 142, 168, 255)
            outline = (24, 22, 26, 255)
            skin = (224, 186, 158, 255)

            if down_pose:
                # Lying horizontal at bottom anchor (32, 95)
                d.rectangle((14, 78, 50, 94), fill=coat, outline=outline)
                d.ellipse((12, 76, 24, 88), fill=skin, outline=outline)
            else:
                stride = 0
                if local_row in (0, 1) and col < 6:
                    stride = (-4, -2, 0, 4, 2, 0)[col]
                top_y = 26 + bob + crouch
                # Shadow / foot anchor marker at (32, 95)
                d.ellipse((22, 90, 42, 95), fill=(20, 24, 30, 140))
                # Legs
                d.rectangle((25 + stride, 70, 30 + stride, 94), fill=(58, 66, 78, 255), outline=outline)
                d.rectangle((34 - stride, 70, 39 - stride, 94), fill=(48, 54, 66, 255), outline=outline)
                # Torso
                d.rectangle((22, top_y + 18, 42, 72), fill=coat, outline=outline)
                # Backpack on NE (back facing) or visor on SE (front facing)
                if is_ne:
                    d.rectangle((18, top_y + 20, 26, top_y + 40), fill=(86, 74, 62, 255), outline=outline)
                # Head
                d.ellipse((24, top_y, 40, top_y + 18), fill=skin, outline=outline)
                if not is_ne:
                    d.rectangle((33, top_y + 6, 39, top_y + 9), fill=(28, 32, 40, 255))
                # Arm swing / attack / aim
                arm_dx = 6 if (local_row == 2 and col >= 4) or (local_row == 3 and col < 2) else -stride // 2
                d.rectangle((36, top_y + 22, 44 + arm_dx, top_y + 38), fill=coat, outline=outline)

            draw_num(cell, 2, 2, str(frame_idx))
            img.paste(cell, (col * 64, row * 96))
    return img


def make_door_leaf() -> Image.Image:
    img = Image.new("RGBA", (32, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((4, 2, 28, 63), fill=(128, 86, 52, 255), outline=(28, 22, 18, 255), width=2)
    d.rectangle((8, 8, 24, 28), outline=(92, 60, 36, 255))
    d.rectangle((8, 34, 24, 56), outline=(92, 60, 36, 255))
    d.rectangle((22, 30, 25, 34), fill=(214, 152, 72, 255))
    return img


def make_prop(w: int, h: int, frames: int, color: tuple[int, int, int], label: str) -> Image.Image:
    img = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for f in range(frames):
        ox = f * w
        shade = max(30, min(230, color[0] + f * 18)), max(30, min(230, color[1] + f * 10)), color[2]
        d.rectangle((ox + 3, 4, ox + w - 4, h - 2), fill=shade + (255,), outline=(24, 22, 26, 255), width=2)
        draw_num(img, ox + 4, 6, str(f))
    return img


def main():
    (ASSETS / "textures").mkdir(parents=True, exist_ok=True)
    (ASSETS / "sprites" / "props").mkdir(parents=True, exist_ok=True)

    make_tiles().save(ASSETS / "textures" / "tiles.png")
    make_char_placeholder().save(ASSETS / "sprites" / "char_placeholder.png")
    make_door_leaf().save(ASSETS / "sprites" / "door_leaf.png")

    props = [
        ("fac_stove.png", 64, 64, 3, (96, 88, 84)),
        ("furn_table.png", 64, 64, 2, (132, 92, 58)),
        ("furn_bed.png", 64, 64, 3, (112, 128, 146)),
        ("cont_crate.png", 32, 32, 3, (146, 108, 64)),
        ("out_tree_dead.png", 64, 96, 2, (92, 76, 62)),
        ("out_car.png", 96, 64, 3, (88, 108, 124)),
        ("out_streetlight.png", 32, 96, 2, (108, 114, 120)),
    ]
    for name, w, h, n, col in props:
        make_prop(w, h, n, col, name).save(ASSETS / "sprites" / "props" / name)
    print("Generated M2 placeholders successfully.")


if __name__ == "__main__":
    main()
