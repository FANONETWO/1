#!/usr/bin/env python3
"""
gen_deco.py —— 程序化生成地图装饰 sprite（32×32，透明背景）

用途：铺在地板上，消除「每格都一样」的棋盘感。
装饰物是简单图形（血泊 / 纸箱 / 玻璃 / 尸体），程序化比 AI 更可控、风格更统一。

用法：
  python tools/pixelart/gen_deco.py
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "w1", "deco")
S = 32

# 与游戏调色板一致
BLOOD_D = (86, 16, 18, 255)
BLOOD = (122, 22, 24, 255)
BLOOD_L = (156, 34, 32, 255)
CARD = (124, 92, 54, 255)
CARD_L = (156, 120, 72, 255)
CARD_D = (84, 60, 34, 255)
GLASS = (198, 220, 228, 220)
GLASS_L = (238, 248, 252, 240)
PAPER = (206, 202, 188, 255)
PAPER_D = (160, 156, 144, 255)
FLESH = (148, 116, 100, 255)
CLOTH = (62, 66, 88, 255)
CLOTH_D = (42, 46, 62, 255)
WATER = (28, 40, 54, 190)
WATER_L = (44, 62, 80, 170)
RUBBLE = (108, 106, 100, 255)
RUBBLE_L = (140, 138, 130, 255)
RUBBLE_D = (74, 72, 68, 255)


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def blood_pool(seed=1):
    """血泊：交叠椭圆 + 溅点"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    for _ in range(8):
        ex = 16 + random.randint(-7, 7)
        ey = 16 + random.randint(-5, 5)
        rw = random.randint(4, 9)
        rh = random.randint(3, 6)
        d.ellipse([ex - rw, ey - rh, ex + rw, ey + rh], fill=BLOOD_D)
    for _ in range(6):
        ex = 16 + random.randint(-5, 5)
        ey = 16 + random.randint(-4, 4)
        rw = random.randint(2, 5)
        rh = random.randint(2, 4)
        d.ellipse([ex - rw, ey - rh, ex + rw, ey + rh], fill=BLOOD)
    for _ in range(4):
        ex = 16 + random.randint(-3, 3)
        ey = 16 + random.randint(-3, 3)
        rw = random.randint(1, 3)
        d.ellipse([ex - rw, ey - rw, ex + rw, ey + rw], fill=BLOOD_L)
    for _ in range(16):                      # 溅点
        if random.random() < 0.75:
            x = random.randint(1, S - 2)
            y = random.randint(1, S - 2)
            d.point((x, y), fill=BLOOD)
    return im


def blood_smear(seed=2):
    """拖痕：一条弯曲的血迹"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    y = 6
    for x in range(2, S - 2):
        bx = x
        by = int(y + random.uniform(-1.2, 1.2))
        w = random.randint(1, 3)
        d.rectangle([bx, by - w, bx, by + w], fill=BLOOD_D)
        if random.random() < 0.30:
            d.point((bx, by + random.randint(3, 7)), fill=BLOOD)
        if random.random() < 0.10:
            d.rectangle([bx, by - 1, bx + 2, by], fill=BLOOD)
        y += 0.55
        if y > S - 4:
            break
    return im


def cardboard(seed=3):
    """压扁的纸箱"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    x0, y0 = 7 + random.randint(-2, 2), 9 + random.randint(-2, 2)
    x1, y1 = x0 + 18, y0 + 14
    d.rectangle([x0, y0, x1, y1], fill=CARD)
    d.rectangle([x0, y0, x1, y0 + 2], fill=CARD_L)          # 顶面高光
    d.rectangle([x0, y1 - 2, x1, y1], fill=CARD_D)          # 底部暗面
    d.line([x0, y0 + 7, x1, y0 + 7], fill=CARD_D)           # 折痕
    d.line([x0 + 4, y0, x0 + 4, y1], fill=CARD_D)
    d.polygon([(x0, y1), (x0 + 5, y1), (x0 + 2, y1 + 4)], fill=CARD_D)   # 翘角
    return im


def glass_shards(seed=4):
    """碎玻璃"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    for _ in range(18):
        x = random.randint(3, S - 4)
        y = random.randint(3, S - 4)
        sz = random.randint(1, 3)
        col = GLASS_L if random.random() < 0.4 else GLASS
        d.polygon([(x, y - sz), (x + sz, y), (x, y + sz), (x - sz, y)], fill=col)
    for _ in range(6):
        x = random.randint(6, S - 7)
        y = random.randint(6, S - 7)
        d.line([x, y, x + random.randint(2, 4), y + random.randint(2, 4)], fill=GLASS_L)
    return im


def trash_papers(seed=5):
    """纸屑与杂物"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    for _ in range(12):
        x = random.randint(3, S - 6)
        y = random.randint(3, S - 6)
        w = random.randint(2, 5)
        h = random.randint(2, 4)
        col = PAPER if random.random() < 0.7 else PAPER_D
        d.rectangle([x, y, x + w, y + h], fill=col)
    for _ in range(5):
        x = random.randint(5, S - 6)
        y = random.randint(5, S - 6)
        d.line([x, y, x + random.randint(3, 6), y - random.randint(1, 3)], fill=PAPER_D)
    return im


def corpse(seed=6):
    """趴在地上的尸体（俯视）"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    cx, cy = 16, 17
    # 躯干
    d.ellipse([cx - 6, cy - 8, cx + 6, cy + 8], fill=CLOTH)
    d.ellipse([cx - 6, cy - 8, cx + 2, cy + 2], fill=CLOTH_D)
    # 头
    d.ellipse([cx - 4, cy - 13, cx + 4, cy - 6], fill=FLESH)
    d.ellipse([cx - 3, cy - 12, cx + 1, cy - 8], fill=(108, 82, 70, 255))
    # 双臂张开
    d.rectangle([cx - 12, cy - 4, cx - 5, cy - 1], fill=CLOTH)
    d.rectangle([cx + 5, cy - 3, cx + 12, cy], fill=CLOTH)
    d.ellipse([cx - 14, cy - 5, cx - 9, cy], fill=FLESH)
    # 腿
    d.rectangle([cx - 5, cy + 7, cx - 1, cy + 14], fill=CLOTH_D)
    d.rectangle([cx + 1, cy + 7, cx + 5, cy + 13], fill=CLOTH_D)
    # 身下血
    d.ellipse([cx - 8, cy - 2, cx + 8, cy + 12], fill=(70, 14, 16, 200))
    return im


def water_stain(seed=7):
    """水渍"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    for _ in range(9):
        ex = 16 + random.randint(-6, 6)
        ey = 16 + random.randint(-5, 5)
        rw = random.randint(3, 8)
        rh = random.randint(3, 7)
        d.ellipse([ex - rw, ey - rh, ex + rw, ey + rh], fill=WATER)
    for _ in range(4):
        ex = 16 + random.randint(-4, 4)
        ey = 16 + random.randint(-3, 3)
        rw = random.randint(2, 4)
        d.ellipse([ex - rw, ey - rw, ex + rw, ey + rw], fill=WATER_L)
    return im


def rubble_pile(seed=8):
    """碎石堆"""
    random.seed(seed)
    im = new()
    d = ImageDraw.Draw(im)
    for _ in range(14):
        x = random.randint(6, S - 7)
        y = random.randint(8, S - 6)
        w = random.randint(2, 5)
        h = random.randint(2, 4)
        col = RUBBLE if random.random() < 0.6 else (RUBBLE_L if random.random() < 0.5 else RUBBLE_D)
        d.rectangle([x, y, x + w, y + h], fill=col)
        d.point((x, y), fill=RUBBLE_L)
    return im


GENS = {
    "blood_pool": blood_pool,
    "blood_smear": blood_smear,
    "cardboard": cardboard,
    "glass_shards": glass_shards,
    "trash_papers": trash_papers,
    "corpse": corpse,
    "water_stain": water_stain,
    "rubble_pile": rubble_pile,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in GENS.items():
        im = fn()
        im.save(os.path.join(OUT, name + ".png"))
        print(f"  {name:<14} 32x32 -> {name}.png")
    # 拼一张预览
    names = list(GENS.keys())
    S2 = 4
    out = Image.new("RGBA", (len(names) * S * S2 + 10 * (len(names) + 1), S * S2 + 20), (46, 48, 58, 255))
    x = 10
    for n in names:
        im = Image.open(os.path.join(OUT, n + ".png")).resize((S * S2, S * S2), Image.NEAREST)
        out.alpha_composite(im, (x, 10))
        x += S * S2 + 10
    out.save(os.path.join(ROOT, "assets", "raw", "_probe", "deco_sheet.png"))
    print(f"  预览 -> assets/raw/_probe/deco_sheet.png")


if __name__ == "__main__":
    main()
