#!/usr/bin/env python3
"""
make_battle_bg.py —— 把火纹背景 CG 处理成 1280x720 的战斗背景

火纹 GBA 背景是 256x160 索引色。处理方式：
  · **6 倍整数放大**（像素画必须整数倍）-> 1536x960
  · 居中裁剪到 1280x720
  · 压暗（战斗时让角色与 UI 更突出）

用法：
  python tools/pixelart/make_battle_bg.py
"""
import os
import sys

from PIL import Image, ImageEnhance

REPO = r"D:\1\fe-repo\BGs, Interface Elements\Background CGs"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "backgrounds", "w1")

# (源文件, 输出名, 亮度系数)
PICKS = [
    (os.path.join(REPO, "FE7 BG's", "Ruins Inside Night.png"), "battle_night", 0.62),
    (os.path.join(REPO, "Assorted CGs {Zeldacrafter}", "Burned ruins.png"), "battle_burned", 0.55),
    (os.path.join(REPO, "FE7 BG's", "Ruins Inside.png"), "battle_inside", 0.60),
    (os.path.join(REPO, "FE7 BG's", "Ruins.png"), "battle_ruins", 0.60),
    (os.path.join(REPO, "FE8 BG's", "Ruins.png"), "battle_ruins8", 0.58),
]

TARGET = (1280, 720)
ZOOM = 6


def process(src, name, bright):
    im = Image.open(src).convert("RGBA")
    big = im.resize((im.width * ZOOM, im.height * ZOOM), Image.NEAREST)
    x = max(0, (big.width - TARGET[0]) // 2)
    y = max(0, (big.height - TARGET[1]) // 2)
    crop = big.crop((x, y, x + TARGET[0], y + TARGET[1]))
    rgb = ImageEnhance.Brightness(crop.convert("RGB")).enhance(bright)
    dst = os.path.join(OUT, name + ".png")
    rgb.convert("RGBA").save(dst)
    return im.size, big.size, dst


def main():
    os.makedirs(OUT, exist_ok=True)
    ok = 0
    for src, name, bright in PICKS:
        if not os.path.exists(src):
            print(f"  缺: {os.path.basename(src)}")
            continue
        a, b, dst = process(src, name, bright)
        print(f"  {name:<16} {a} x{ZOOM} -> {b} -> 1280x720（亮度 {bright}）")
        ok += 1
    print(f"完成 {ok} 张 -> {OUT}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
