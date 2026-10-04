"""程序化生成地板与墙的像素 tile（RE2 警察局风格）。

设计要点（解决"地板和墙分不清"）：
  · 地板：**平坦、明亮、低对比**——瓷砖缝 + 稀疏污渍，视觉上"空"，不抢注意力
  · 墙：  **厚重、暗、高对比**——受光顶边 + 阴影底边 + 错位砖缝，一眼看出是实体

规格：16×16、RGBA、≤16 色、无抗锯齿（全部硬边像素），符合项目像素规格。

用法：
    python tools/make_tiles.py --out assets/tiles/w1
"""

import argparse
import os
import random

from PIL import Image

# ——— 调色板（刻意拉开明度差：地板 ~105，墙 ~48） ———
FLOOR_BASE = (108, 112, 122)
FLOOR_GROUT = (86, 90, 100)
FLOOR_STAIN = (94, 98, 108)

WALL_BASE = (46, 50, 62)
WALL_TOP = (84, 90, 108)
WALL_BOTTOM = (24, 26, 34)
WALL_LINE = (36, 39, 48)

DOOR_BASE = (92, 62, 34)
DOOR_EDGE = (64, 42, 22)
DOOR_KNOB = (208, 176, 96)


def make_floor(size=16, seed=7):
    """地板：瓷砖缝（每 8px）+ 稀疏污渍，整体保持明亮平坦。"""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size), FLOOR_BASE + (255,))
    px = img.load()
    for y in range(size):
        for x in range(size):
            if x % 8 == 0 or y % 8 == 0:
                px[x, y] = FLOOR_GROUT + (255,)
    # 污渍：只落在瓷砖内部，避免破坏缝线
    for _ in range(size * size // 7):
        x, y = rnd.randrange(1, size), rnd.randrange(1, size)
        if x % 8 != 0 and y % 8 != 0 and px[x, y][:3] == FLOOR_BASE:
            px[x, y] = FLOOR_STAIN + (255,)
    return img


def make_wall(size=16, seed=11):
    """墙：受光顶边 + 阴影底边 + 错位砖缝，制造厚度感。"""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size), WALL_BASE + (255,))
    px = img.load()
    for y in range(size):
        for x in range(size):
            if y < 2:
                px[x, y] = WALL_TOP + (255,)
            elif y >= size - 3:
                px[x, y] = WALL_BOTTOM + (255,)
            elif y % 8 == 0:
                px[x, y] = WALL_LINE + (255,)
            elif (y // 8) % 2 == 0 and x % 8 == 0:
                px[x, y] = WALL_LINE + (255,)
            elif (y // 8) % 2 == 1 and x % 8 == 4:
                px[x, y] = WALL_LINE + (255,)
    # 少量风化点
    for _ in range(size // 2):
        x, y = rnd.randrange(2, size - 3), rnd.randrange(2, size - 3)
        if px[x, y][:3] == WALL_BASE:
            px[x, y] = (56, 60, 74, 255)
    return img


def make_door(size=16):
    """门：木色 + 门框暗边 + 金色门把，横向可读。"""
    img = Image.new("RGBA", (size, size), DOOR_BASE + (255,))
    px = img.load()
    for y in range(size):
        for x in range(size):
            if x < 1 or x >= size - 1 or y < 1 or y >= size - 1:
                px[x, y] = DOOR_EDGE + (255,)
            elif x % 5 == 0:
                px[x, y] = DOOR_EDGE + (255,)
    px[size - 4, size // 2] = DOOR_KNOB + (255,)
    px[size - 5, size // 2] = DOOR_KNOB + (255,)
    return img


def color_count(img):
    return len(img.convert("RGBA").getcolors(maxcolors=1 << 24) or [])


def save(img, path):
    img.save(path)
    print("  %-28s %d 色" % (os.path.basename(path), color_count(img)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/tiles/w1")
    ap.add_argument("--size", type=int, default=16)
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    print("生成像素 tile（%d×%d）：" % (args.size, args.size))
    save(make_floor(args.size), os.path.join(out, "floor.png"))
    save(make_wall(args.size), os.path.join(out, "wall.png"))
    save(make_door(args.size), os.path.join(out, "door.png"))
    print("完成 →", out)


if __name__ == "__main__":
    main()
