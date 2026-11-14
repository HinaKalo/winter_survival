#!/usr/bin/env python3
"""生成 iso-base 的像素风占位美术（固定随机种子，重复运行结果一致）。

用法（项目根目录）：python3 -I tools/gen_assets.py
输出（相对本脚本的 ../assets/）：
  textures/tiles.png   8 列 x 4 行，每格 32x32，无透明；索引 = row*8+col
  sprites/hero.png     4 列(走路帧) x 4 行(0 下 / 1 左 / 2 右 / 3 上)，每帧 32x48，RGBA
  sprites/slime.png    4 列 x 1 行，每帧 32x32，RGBA
依赖：Pillow（测试于 9.0.1）。
"""
import math
import os
import random

from PIL import Image

SEED = 20260513
OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
)

# ---------------------------------------------------------------- 瓦片
TILE = 32
TILE_COLS = 8
TILE_ROWS = 4
MISSING = (255, 0, 255)  # 洋红：未定义格子的“缺失”标记

# ---------------------------------------------------------------- 精灵
HERO_W, HERO_H = 32, 48
HERO_COLS, HERO_ROWS = 4, 4
SLIME_W, SLIME_H = 32, 32
SLIME_COLS = 4

rng = random.Random(SEED)


def clamp(v):
    return max(0, min(255, int(round(v))))


def jitter(color, amount):
    n = rng.randint(-amount, amount)
    return tuple(clamp(c + n) for c in color)


def shade(color, factor):
    return tuple(clamp(c * factor) for c in color)


# ================================================================ 瓦片绘制

def new_tile():
    return Image.new("RGB", (TILE, TILE), MISSING)


def paint_noise(px, base, amount):
    for y in range(TILE):
        for x in range(TILE):
            px[x, y] = jitter(base, amount)


def add_outline(img):
    """每格加 1px 略暗描边。"""
    px = img.load()
    for i in range(TILE):
        for (x, y) in ((i, 0), (i, TILE - 1), (0, i), (TILE - 1, i)):
            px[x, y] = shade(px[x, y], 0.7)
    return img


def ragged_grass_edge(px, y_top, base_grass, base_dirt):
    """上方为草/雪，下方为泥土，边缘锯齿。"""
    for y in range(TILE):
        for x in range(TILE):
            if y < y_top:
                px[x, y] = jitter(base_grass, 14)
            elif y == y_top and rng.random() < 0.6:
                px[x, y] = jitter(base_grass, 14)
            elif y == y_top + 1 and rng.random() < 0.25:
                px[x, y] = jitter(base_grass, 14)
            else:
                px[x, y] = jitter(base_dirt, 14)


def tile_grass_top():
    img = new_tile()
    px = img.load()
    base = (96, 162, 72)
    paint_noise(px, base, 12)
    for _ in range(90):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        px[x, y] = shade(base, 0.82)
    for _ in range(50):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        px[x, y] = shade(base, 1.18)
    return add_outline(img)


def tile_grass_side():
    img = new_tile()
    ragged_grass_edge(img.load(), 8, (96, 162, 72), (134, 96, 60))
    return add_outline(img)


def tile_dirt_top():
    img = new_tile()
    px = img.load()
    base = (134, 96, 60)
    paint_noise(px, base, 16)
    for _ in range(40):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        px[x, y] = shade(base, 0.7)
    return add_outline(img)


def tile_dirt_side():
    img = new_tile()
    px = img.load()
    paint_noise(px, (126, 90, 56), 16)
    return add_outline(img)


def tile_stone_top():
    img = new_tile()
    px = img.load()
    base = (128, 128, 134)
    paint_noise(px, base, 20)
    for _ in range(60):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        px[x, y] = shade(base, 0.72)
    return add_outline(img)


def tile_stone_side():
    img = new_tile()
    px = img.load()
    base = (116, 116, 122)
    paint_noise(px, base, 14)
    for y in (10, 21):  # 砌缝
        for x in range(TILE):
            px[x, y] = jitter(shade(base, 0.8), 6)
    return add_outline(img)


def tile_water_top():
    img = new_tile()
    px = img.load()
    base = (44, 104, 204)
    light = (150, 200, 255)
    paint_noise(px, base, 6)
    for y0 in (5, 13, 21, 28):  # 波纹
        for x in range(TILE):
            yy = y0 + int(round(1.2 * math.sin(x / 3.0 + y0)))
            if 0 <= yy < TILE and rng.random() < 0.8:
                px[x, yy] = jitter(light, 10)
    return add_outline(img)


def tile_water_side():
    img = new_tile()
    px = img.load()
    base = (34, 82, 170)
    paint_noise(px, base, 6)
    for y in (0, 1):  # 水面高光
        for x in range(TILE):
            px[x, y] = jitter((120, 180, 240), 8)
    return add_outline(img)


def tile_sand_top():
    img = new_tile()
    px = img.load()
    base = (226, 206, 140)
    paint_noise(px, base, 10)
    for _ in range(50):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        px[x, y] = shade(base, 0.88)
    return add_outline(img)


def tile_sand_side():
    img = new_tile()
    px = img.load()
    base = (214, 192, 126)
    paint_noise(px, base, 10)
    for y in range(0, TILE, 8):  # 沉积层理
        for x in range(TILE):
            px[x, y] = jitter(shade(base, 0.92), 4)
    return add_outline(img)


def tile_snow_top():
    img = new_tile()
    px = img.load()
    base = (240, 246, 252)
    paint_noise(px, base, 6)
    for _ in range(40):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        px[x, y] = (210, 222, 236)
    return add_outline(img)


def tile_snow_side():
    img = new_tile()
    # 上方雪层（锯齿边），下方冰冻泥土
    ragged_grass_edge(img.load(), 8, (240, 246, 252), (150, 170, 195))
    return add_outline(img)


def tile_wood_top():
    img = new_tile()
    px = img.load()
    base = (170, 120, 70)
    paint_noise(px, base, 8)
    for y in range(0, TILE, 8):  # 木板接缝
        for x in range(TILE):
            px[x, y] = shade(base, 0.7)
    return add_outline(img)


def tile_wood_side():
    img = new_tile()
    px = img.load()
    base = (150, 104, 60)
    paint_noise(px, base, 8)
    for x in range(0, TILE, 8):  # 竖直木板缝
        for y in range(TILE):
            px[x, y] = shade(base, 0.7)
    return add_outline(img)


TILE_FUNCS = [
    tile_grass_top,   # 0
    tile_grass_side,  # 1
    tile_dirt_top,    # 2
    tile_dirt_side,   # 3
    tile_stone_top,   # 4
    tile_stone_side,  # 5
    tile_water_top,   # 6
    tile_water_side,  # 7
    tile_sand_top,    # 8
    tile_sand_side,   # 9
    tile_snow_top,    # 10
    tile_snow_side,   # 11
    tile_wood_top,    # 12
    tile_wood_side,   # 13
]


def make_tiles():
    atlas = Image.new("RGB", (TILE_COLS * TILE, TILE_ROWS * TILE), MISSING)
    for idx, fn in enumerate(TILE_FUNCS):
        col, row = idx % TILE_COLS, idx // TILE_COLS
        atlas.paste(fn(), (col * TILE, row * TILE))
    return atlas


# ================================================================ 英雄精灵

SKIN = (240, 200, 160)
SKIN_SHADE = (214, 168, 128)
HAIR = (92, 56, 30)
EYE = (24, 20, 32)
SHIRT = (66, 128, 220)
SHIRT_DARK = (46, 92, 170)
PANTS = (52, 52, 96)
BOOT = (42, 26, 20)
BELT = (70, 46, 28)
OUTLINE = (28, 22, 30)
TRANSPARENT = (0, 0, 0, 0)

HERO_DIR_DOWN, HERO_DIR_LEFT, HERO_DIR_RIGHT, HERO_DIR_UP = 0, 1, 2, 3
# 身体上下浮动（像素）；走路帧 1、3 身体上抬 1px
HERO_BOB = (0, -1, 0, -1)
# 腿：(x0, x1, 底行)；底行 47 = 贴住帧底边，抬起的腿底行 45
HERO_LEGS = (
    [(12, 15, 47), (16, 19, 47)],  # 站立
    [(11, 14, 47), (16, 19, 45)],  # 左腿迈出
    [(12, 15, 47), (16, 19, 47)],  # 站立
    [(12, 15, 45), (17, 20, 47)],  # 右腿迈出
)


def hero_frame(direction, frame):
    img = Image.new("RGBA", (HERO_W, HERO_H), TRANSPARENT)
    px = img.load()
    b = HERO_BOB[frame]

    def put(x, y, c):
        if 0 <= x < HERO_W and 0 <= y < HERO_H:
            px[x, y] = c + (255,)

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                put(x, y, c)

    # 腿（先画，身体盖在上面；腿顶从 30 开始避免与躯干之间出现缝隙）
    for (x0, x1, bottom) in HERO_LEGS[frame]:
        rect(x0, 30, x1, bottom - 4, PANTS)
        rect(x0, bottom - 3, x1, bottom, BOOT)

    # 手臂与躯干
    rect(8, 19 + b, 10, 27 + b, SHIRT)
    rect(21, 19 + b, 23, 27 + b, SHIRT)
    rect(8, 28 + b, 10, 29 + b, SKIN)
    rect(21, 28 + b, 23, 29 + b, SKIN)
    rect(11, 18 + b, 20, 30 + b, SHIRT)
    rect(11, 18 + b, 11, 30 + b, SHIRT_DARK)
    rect(11, 28 + b, 20, 28 + b, BELT)

    # 头部：底色为肤色，再按朝向画头发与五官
    top = 6 + b
    rect(10, top, 21, 17 + b, SKIN)
    if direction == HERO_DIR_DOWN:  # 面向镜头：刘海 + 双眼 + 嘴
        rect(10, top, 21, top + 2, HAIR)
        rect(10, top + 3, 11, top + 5, HAIR)
        rect(20, top + 3, 21, top + 5, HAIR)
        rect(13, top + 7, 13, top + 8, EYE)
        rect(18, top + 7, 18, top + 8, EYE)
        rect(15, top + 10, 16, top + 10, SKIN_SHADE)
    elif direction == HERO_DIR_UP:  # 背对镜头：整个头都是头发
        rect(10, top, 21, 17 + b, HAIR)
    elif direction == HERO_DIR_LEFT:  # 朝左：单眼侧脸，后脑在右
        rect(10, top, 21, top + 2, HAIR)
        rect(18, top + 3, 21, 17 + b, HAIR)
        rect(12, top + 7, 12, top + 8, EYE)
        put(10, top + 8, SKIN_SHADE)
    elif direction == HERO_DIR_RIGHT:  # 朝右：单眼侧脸，后脑在左
        rect(10, top, 21, top + 2, HAIR)
        rect(10, top + 3, 13, 17 + b, HAIR)
        rect(19, top + 7, 19, top + 8, EYE)
        put(21, top + 8, SKIN_SHADE)

    # 外描边：所有透明像素中与不透明像素四邻接者画描边（先收集再写，避免级联）
    outline_pixels = []
    for y in range(HERO_H):
        for x in range(HERO_W):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < HERO_W and 0 <= ny < HERO_H and px[nx, ny][3] != 0:
                    outline_pixels.append((x, y))
                    break
    for (x, y) in outline_pixels:
        px[x, y] = OUTLINE + (255,)
    return img


def make_hero():
    sheet = Image.new("RGBA", (HERO_COLS * HERO_W, HERO_ROWS * HERO_H), TRANSPARENT)
    for direction in range(HERO_ROWS):
        for frame in range(HERO_COLS):
            sheet.paste(hero_frame(direction, frame), (frame * HERO_W, direction * HERO_H))
    return sheet


# ================================================================ 史莱姆

SLIME_BASE = (92, 204, 96)
SLIME_DARK = (40, 124, 56)
SLIME_LIGHT = (176, 240, 160)
SLIME_EYE = (24, 20, 32)
# 挤压弹跳：(宽, 高)。底部始终贴住帧底边
SLIME_SHAPES = [(22, 19), (28, 14), (18, 24), (25, 16)]


def slime_frame(frame):
    img = Image.new("RGBA", (SLIME_W, SLIME_H), TRANSPARENT)
    px = img.load()
    w, h = SLIME_SHAPES[frame]
    cx = 15.5 + 0.5  # 像素中心坐标系：水平中心位于 16.0
    cy = SLIME_H - h / 2.0  # 底边 = SLIME_H
    rx, ry = w / 2.0, h / 2.0

    def inside(x, y):
        nx = (x + 0.5 - cx) / rx
        ny = (y + 0.5 - cy) / ry
        return nx * nx + ny * ny <= 1.0

    for y in range(SLIME_H):
        for x in range(SLIME_W):
            if not inside(x, y):
                continue
            nx = (x + 0.5 - cx) / rx
            ny = (y + 0.5 - cy) / ry
            if nx < -0.35 and ny < -0.2:
                c = SLIME_LIGHT
            elif ny > 0.45:
                c = shade(SLIME_BASE, 0.85)
            else:
                c = SLIME_BASE
            px[x, y] = tuple(clamp(v) for v in c) + (255,)

    # 描边：内部像素若四邻有外部像素则画暗色描边
    for y in range(SLIME_H):
        for x in range(SLIME_W):
            if not inside(x, y):
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx_, ny_ = x + dx, y + dy
                if not (0 <= nx_ < SLIME_W and 0 <= ny_ < SLIME_H) or not inside(nx_, ny_):
                    px[x, y] = SLIME_DARK + (255,)
                    break

    # 双眼：关于水平中线 15.5 对称，位于躯干上半部
    eye_top = int(round(cy - h * 0.1))
    left_x = int(round(15.5 - w * 0.17))
    right_x = 31 - left_x
    for ex in (left_x, right_x):
        for ey in (eye_top, eye_top + 1):
            px[ex, ey] = SLIME_EYE + (255,)
    return img


def make_slime():
    sheet = Image.new("RGBA", (SLIME_COLS * SLIME_W, SLIME_H), TRANSPARENT)
    for frame in range(SLIME_COLS):
        sheet.paste(slime_frame(frame), (frame * SLIME_W, 0))
    return sheet


# ================================================================ 入口

def main():
    os.makedirs(os.path.join(OUT_DIR, "textures"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "sprites"), exist_ok=True)

    tiles_path = os.path.join(OUT_DIR, "textures", "tiles.png")
    hero_path = os.path.join(OUT_DIR, "sprites", "hero.png")
    slime_path = os.path.join(OUT_DIR, "sprites", "slime.png")

    make_tiles().save(tiles_path)
    make_hero().save(hero_path)
    make_slime().save(slime_path)

    for path in (tiles_path, hero_path, slime_path):
        print(f"wrote {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
