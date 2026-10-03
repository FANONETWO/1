#!/usr/bin/env python3
"""
gen_tiles.py —— 程序化生成 16×16 地形 tile（公寓楼）

为什么要程序化：AI 在 16×16 这个尺寸上只会产出噪点（现有 floor/wall 就是证据），
而 tile 恰恰是**规则几何 + 有限调色板**，程序化能精确控制砖缝、错缝、明暗层次。

设计原则：
  · 墙与地板**必须一眼区分**（墙暗 35%、有砖块结构、地板是地砖）
  · 每个 tile 都要能平铺（边缘图案对齐）
  · 固定种子 → 每次生成一致
  · 调色板 ≤16 色，三阶明暗（亮/中/暗）

用法：
  python tools/pixelart/gen_tiles.py
"""
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "tiles", "w1")
S = 16


# ——— 调色板（每个地形三阶明暗）———

# 地板：冷灰地砖
FLOOR_HI = (108, 112, 122, 255)
FLOOR = (88, 92, 102, 255)
FLOOR_LO = (68, 72, 82, 255)
FLOOR_LINE = (52, 56, 66, 255)

# 墙：深灰蓝水泥砖（比地板整体暗 ~35%，一眼区分）
WALL_HI = (78, 82, 96, 255)
WALL = (60, 64, 76, 255)
WALL_LO = (42, 46, 58, 255)
WALL_MORTAR = (28, 32, 42, 255)

# 木门 / 木桌
WOOD_HI = (162, 122, 74, 255)
WOOD = (128, 94, 56, 255)
WOOD_LO = (96, 68, 38, 255)
METAL_HI = (186, 192, 202, 255)

# 床
SHEET_HI = (226, 226, 220, 255)
SHEET = (196, 196, 190, 255)
SHEET_LO = (158, 158, 152, 255)

# 柜
CAB_HI = (140, 146, 158, 255)
CAB = (112, 118, 130, 255)
CAB_LO = (84, 90, 102, 255)

# 楼梯
STEP_HI = (124, 128, 138, 255)
STEP = (96, 100, 110, 255)
STEP_LO = (68, 72, 82, 255)

# 出口（绿）
EXIT_HI = (78, 190, 130, 255)
EXIT = (44, 142, 92, 255)
EXIT_LO = (24, 96, 62, 255)


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def _noise(px, x, y, base, hi, lo, rng, amount=0.22):
    """在底色上加一层像素噪点，让平面不至于死板"""
    r = rng.random()
    if r < amount * 0.5:
        px[x, y] = hi
    elif r < amount:
        px[x, y] = lo
    else:
        px[x, y] = base


def floor_tile(seed=11):
    """地砖：8×8 方格 + 砖缝 + 污渍"""
    rng = random.Random(seed)
    im = new()
    px = im.load()
    for y in range(S):
        for x in range(S):
            on_seam = (x % 8 == 0) or (y % 8 == 0)
            if on_seam:
                px[x, y] = FLOOR_LINE
            else:
                # 每块砖内部有轻微渐变：靠缝处略暗
                edge = (x % 8 in (1, 7)) or (y % 8 in (1, 7))
                _noise(px, x, y, FLOOR_LO if edge else FLOOR, FLOOR_HI, FLOOR_LO, rng, 0.18)
    # 几处深色污渍
    for _ in range(3):
        cx, cy = rng.randrange(2, 14), rng.randrange(2, 14)
        px[cx, cy] = FLOOR_LINE
        px[min(cx + 1, 15), cy] = FLOOR_LO
    return im


def floor_dirty_tile(seed=12):
    """脏地板：地砖 + 明显污渍（走廊/杂物间用）"""
    im = floor_tile(seed)
    rng = random.Random(seed + 100)
    px = im.load()
    for _ in range(14):
        cx, cy = rng.randrange(1, 15), rng.randrange(1, 15)
        if (cx % 8 == 0) or (cy % 8 == 0):
            continue
        px[cx, cy] = FLOOR_LINE if rng.random() < 0.5 else (60, 56, 52, 255)
    return im


def wall_tile(seed=21):
    """砖墙：8×4 错缝砖块 + 勾缝（整体比地板暗，一眼区分）"""
    rng = random.Random(seed)
    im = new()
    px = im.load()
    BH, BW = 4, 8          # 砖高 / 砖宽
    MORTAR = 1
    for y in range(S):
        row = y // BH
        off = (BW // 2) if (row % 2) else 0        # 错缝
        for x in range(S):
            bx = (x + off) % BW
            by = y % BH
            if by < MORTAR or bx < MORTAR:
                px[x, y] = WALL_MORTAR
            else:
                # 砖面：上亮下暗，做出凸起感
                if by == 1:
                    _noise(px, x, y, WALL_HI, WALL_HI, WALL, rng, 0.15)
                elif by == BH - 1:
                    px[x, y] = WALL_LO
                else:
                    _noise(px, x, y, WALL, WALL_HI, WALL_LO, rng, 0.20)
    return im


def door_tile(seed=31):
    """木门：门框 + 门板纹理 + 门把手"""
    im = new()
    px = im.load()
    for y in range(S):
        for x in range(S):
            if x in (0, 15) or y == 0:
                px[x, y] = WOOD_LO            # 门框
            elif x in (2, 13):
                px[x, y] = WOOD_LO            # 门板缝
            else:
                # 木纹：竖向明暗条
                px[x, y] = WOOD_HI if (x % 4 == 1) else WOOD
    # 门把手
    px[12, 8] = METAL_HI
    px[12, 9] = METAL_HI
    px[11, 8] = (140, 146, 156, 255)
    return im


def table_tile(seed=41):
    """木桌：桌面 + 桌腿投影"""
    im = new()
    px = im.load()
    for y in range(S):
        for x in range(S):
            if 2 <= x <= 13 and 2 <= y <= 12:
                if y <= 3:
                    px[x, y] = WOOD_HI
                elif y >= 11:
                    px[x, y] = WOOD_LO
                else:
                    px[x, y] = WOOD
            else:
                px[x, y] = (0, 0, 0, 0)
    # 桌腿
    px[4, 13] = WOOD_LO
    px[11, 13] = WOOD_LO
    return im


def bed_tile(seed=51):
    """床：床垫 + 枕头 + 床架"""
    im = new()
    px = im.load()
    for y in range(S):
        for x in range(S):
            if 1 <= x <= 14 and 2 <= y <= 14:
                px[x, y] = SHEET
            else:
                px[x, y] = SHEET_LO
    for y in range(3, 7):                     # 枕头
        for x in range(3, 13):
            px[x, y] = SHEET_HI
    for x in range(1, 15):                    # 床架下沿
        px[x, 14] = (96, 78, 62, 255)
    for y in range(3, 13):                    # 床单折痕
        px[8, y] = SHEET_LO
    return im


def cabinet_tile(seed=61):
    """金属柜：三层抽屉 + 把手"""
    im = new()
    px = im.load()
    for y in range(S):
        for x in range(S):
            if x == 0 or x == 15 or y == 0 or y == 15:
                px[x, y] = CAB_LO
            else:
                px[x, y] = CAB
    for y in (5, 10):                         # 抽屉分隔
        for x in range(1, 15):
            px[x, y] = CAB_LO
    for y in (2, 7, 12):                      # 把手
        for x in range(6, 10):
            px[x, y] = CAB_HI
    return im


def stairs_tile(seed=71):
    """楼梯：四级台阶，上亮下暗"""
    im = new()
    px = im.load()
    for y in range(S):
        step = y // 4
        for x in range(S):
            if y % 4 == 0:
                px[x, y] = STEP_LO            # 台阶前沿
            elif y % 4 == 1:
                px[x, y] = STEP_HI if step < 2 else STEP_HI
            else:
                px[x, y] = STEP_LO if step > 1 else STEP
    return im


def exit_tile(seed=81):
    """安全出口：绿门 + 门缝光"""
    im = new()
    px = im.load()
    for y in range(S):
        for x in range(S):
            if x in (0, 15) or y == 0:
                px[x, y] = EXIT_LO
            elif x in (7, 8):
                px[x, y] = EXIT_HI            # 门缝
            elif y >= 11:
                px[x, y] = EXIT_LO
            else:
                px[x, y] = EXIT
    for y in range(2, 6):                     # 出口标志
        for x in range(4, 12):
            px[x, y] = EXIT_HI if (x + y) % 2 == 0 else EXIT
    return im


# 地形字符 -> 生成器
TILES = {
    "floor": floor_tile,
    "floor_dirty": floor_dirty_tile,
    "wall": wall_tile,
    "door": door_tile,
    "table": table_tile,
    "bed": bed_tile,
    "cabinet": cabinet_tile,
    "stairs": stairs_tile,
    "exit": exit_tile,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for name, fn in TILES.items():
        im = fn()
        im.save(os.path.join(OUT, name + ".png"))
        made.append(name)
        print(f"  {name:<13} 16x16 -> {name}.png")

    # 预览：每行 12 个平铺，看接缝是否连续
    Z = 8
    cols = 12
    rows = len(made)
    prev = Image.new("RGBA", (cols * S * Z, rows * S * Z), (30, 32, 40, 255))
    for r, name in enumerate(made):
        t = Image.open(os.path.join(OUT, name + ".png"))
        for c in range(cols):
            prev.alpha_composite(t.resize((S * Z, S * Z), Image.NEAREST), (c * S * Z, r * S * Z))
    prev.save(os.path.join(ROOT, "assets", "raw", "_probe", "tiles_sheet.png"))
    print(f"  预览 -> assets/raw/_probe/tiles_sheet.png（{cols} 个平铺，检查接缝）")


if __name__ == "__main__":
    main()
