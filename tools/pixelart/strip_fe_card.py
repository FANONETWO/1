#!/usr/bin/env python3
"""
strip_fe_card.py —— 把 FE-Repo 的职业卡（Class Card）处理成游戏可用的战斗立绘

FE-Repo 的 Class Card 是 80x72 的「卡牌」：四周有金色/青色的花纹边框，
底色是一种绿色。本脚本做四件事：

  1. 内缩切掉花纹边框（默认 8px）
  2. **flood fill 抠背景**：只抠「连通到图像边缘」的背景色，
     主体内部的相似颜色不受影响（这点比全局色差抠图可靠得多）
  3. 自动包围盒裁剪到主体
  4. **整数倍放大**（像素画必须整数倍，否则像素不均匀）

默认从 `D:\\1\\fe-repo\\Class Cards` 取素材，输出到游戏目录。

用法：
  python tools/pixelart/strip_fe_card.py --list          # 列出可用的怪物卡
  python tools/pixelart/strip_fe_card.py --build         # 生成当前在用的 4 张
  python tools/pixelart/strip_fe_card.py ^
      --src "Monsters - Basic Types/Lich Entombed {SkidMarc25}.png" --name zombie
"""
import argparse
import glob
import os
import sys
from collections import deque

from PIL import Image

REPO = r"D:\1\fe-repo\Class Cards"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "assets", "sprites", "w1", "battle")

# (相对 REPO 的路径, 输出名, 是否水平翻转)
BUILD_SET = [
    (os.path.join("Monsters - Basic Types", "Revenant {IS}.png"), "zombie", False),
    (os.path.join("Monsters - Basic Types", "Mauthe Doog {IS}.png"), "crawler", False),
    (os.path.join("Monsters - Basic Types", "Cyclops Axe {IS}.png"), "brute", False),
    (os.path.join("Infantry - (Swd) Mercenaries and Heroes",
                  "Hero (M) Gerik-Style Sword {Nuramon}.png"), "hero", True),
]


def strip_card(src, inset=8, tol=38, scale=4, flip=False):
    im = Image.open(src).convert("RGBA")
    if inset:
        w0, h0 = im.size
        im = im.crop((inset, inset, w0 - inset, h0 - inset))
    w, h = im.size
    px = im.load()

    # 四角采样出边框外的底色
    refs = [px[0, 0][:3], px[w - 1, 0][:3], px[0, h - 1][:3], px[w - 1, h - 1][:3]]

    def near(c):
        return any(abs(c[0] - r[0]) <= tol and abs(c[1] - r[1]) <= tol
                   and abs(c[2] - r[2]) <= tol for r in refs)

    # 从四条边向内 flood fill
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not seen[y][x] and near(px[x, y][:3]):
                seen[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y][x] and near(px[x, y][:3]):
                seen[y][x] = True
                q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and near(px[nx, ny][:3]):
                seen[ny][nx] = True
                q.append((nx, ny))

    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im


def cmd_list():
    for sub in ("Monsters - Basic Types", "Monsters - Dragons and Special"):
        d = os.path.join(REPO, sub)
        if not os.path.isdir(d):
            continue
        print(f"--- {sub} ---")
        for f in sorted(os.listdir(d)):
            if f.endswith(".png"):
                tag = "  [IS-官方·不可商用]" if "{IS}" in f else ""
                print(f"  {f}{tag}")


def cmd_build():
    os.makedirs(OUT, exist_ok=True)
    for rel, name, flip in BUILD_SET:
        src = os.path.join(REPO, rel)
        if not os.path.exists(src):
            print(f"  缺: {rel}")
            continue
        im = strip_card(src, flip=flip)
        dst = os.path.join(OUT, name + ".png")
        im.save(dst)
        note = "（已翻转，面朝右）" if flip else ""
        print(f"  {name:<8} <- {os.path.basename(rel)}  ->  {im.size[0]}x{im.size[1]} {note}")


def cmd_one(args):
    src = args.src if os.path.isabs(args.src) else os.path.join(REPO, args.src)
    if not os.path.exists(src):
        print("找不到:", src)
        return 1
    os.makedirs(OUT, exist_ok=True)
    im = strip_card(src, inset=args.inset, tol=args.tol, scale=args.scale, flip=args.flip)
    dst = os.path.join(OUT, args.name + ".png")
    im.save(dst)
    print(f"  {args.name} -> {dst}  {im.size[0]}x{im.size[1]}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--src")
    ap.add_argument("--name")
    ap.add_argument("--inset", type=int, default=8)
    ap.add_argument("--tol", type=int, default=38)
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--flip", action="store_true")
    args = ap.parse_args()

    if args.list:
        cmd_list()
        return 0
    if args.build:
        cmd_build()
        return 0
    if args.src and args.name:
        return cmd_one(args)
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
