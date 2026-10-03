#!/usr/bin/env python3
"""
pixelize_for_game.py —— 把 AI 生成的图处理成游戏可用的像素立绘

AI（图生图）产出的是「伪像素」：分辨率高、颜色上千、带背景。
本脚本把它变成游戏能直接用的素材：

  1. 抠背景（按四角估色 + 容差；也支持 --bg 指定）
  2. 裁剪到主体包围盒（去空白边）
  3. 等比缩放到目标尺寸（LANCZOS 降采样 → NEAREST 定尺寸）
  4. 降色到 N 色（中位切分 + 固定调色板映射）
  5. 加 1px 深色描边（火纹风格的关键）
  6. 输出 PNG + 调色板报告

用法：
  python tools/pixelart/pixelize_for_game.py in.png hero --size 64x96 --colors 16
  python tools/pixelart/pixelize_for_game.py in.png zombie --size 64x96 --colors 16 --no-outline
"""
import argparse
import collections
import os
import sys

from PIL import Image


def parse_size(s):
    w, h = s.lower().split("x")
    return int(w), int(h)


def estimate_bg(im):
    """取四角与四边中点最常见的颜色作为背景色估计"""
    w, h = im.size
    pts = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2),
           (w // 2, 1), (w // 2, h - 2), (1, h // 2), (w - 2, h // 2)]
    px = im.load()
    cnt = collections.Counter()
    for x, y in pts:
        cnt[px[x, y][:3]] += 1
    return cnt.most_common(1)[0][0]


def remove_bg(im, bg, tol=30):
    """把接近 bg 的像素设为全透明（含边缘羽化一步）"""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    br, bgc, bb = bg
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r - br) <= tol and abs(g - bgc) <= tol and abs(b - bb) <= tol:
                px[x, y] = (0, 0, 0, 0)
    return im


def autocrop(im, pad=1):
    bbox = im.getbbox()
    if not bbox:
        return im
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad); y1 = min(im.height, y1 + pad)
    return im.crop((x0, y0, x1, y1))


def fit_into(im, size):
    """等比缩放到能放进目标框，再居中贴到 size 画布上"""
    tw, th = size
    scale = min(tw / im.width, th / im.height)
    nw = max(1, int(round(im.width * scale)))
    nh = max(1, int(round(im.height * scale)))
    # 先 LANCZOS 平滑降采样（保留形体），再由调用方做 NEAREST 定尺
    small = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.alpha_composite(small, ((tw - nw) // 2, th - nh))   # 底部对齐（脚踩地）
    return canvas


def quantize(im, colors):
    """降色：alpha 二值化（像素画不需要半透明），RGB 中位切分到 N 色"""
    alpha = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    rgb = im.convert("RGB")
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE)
    out = q.convert("RGBA")
    out.putalpha(alpha)
    return out


def add_outline(im, ink=(38, 34, 44, 255)):
    """给不透明区域外沿加 1px 描边（火纹风格）"""
    w, h = im.size
    src = im.load()
    opaque = [[src[x, y][3] > 0 for x in range(w)] for y in range(h)]
    out = im.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if opaque[y][x]:
                continue
            near = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and opaque[ny][nx]:
                    near = True
                    break
            if near:
                dst[x, y] = ink
    return out


def report(im, label):
    cnt = collections.Counter(
        p for p in im.convert("RGBA").getdata() if p[3] > 0)
    print(f"  {label}: {im.size[0]}x{im.size[1]}, 不透明 {sum(cnt.values())} px, {len(cnt)} 色")
    for c, n in cnt.most_common(8):
        print(f"      {c} x{n}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("name", help="输出名（不带扩展名）")
    ap.add_argument("--out", default="assets/sprites/w1/battle")
    ap.add_argument("--size", default="64x96")
    ap.add_argument("--colors", type=int, default=16)
    ap.add_argument("--tol", type=int, default=30, help="抠背景容差")
    ap.add_argument("--bg", default="", help="手动指定背景色 r,g,b")
    ap.add_argument("--no-outline", action="store_true")
    ap.add_argument("--no-bg", action="store_true", help="不抠背景（图已透明）")
    args = ap.parse_args()

    if not os.path.exists(args.src):
        print("找不到输入图:", args.src)
        return 1

    size = parse_size(args.size)
    im = Image.open(args.src).convert("RGBA")

    if not args.no_bg:
        if args.bg:
            bg = tuple(int(v) for v in args.bg.split(","))[:3]
        else:
            bg = estimate_bg(im)
        im = remove_bg(im, bg, args.tol)
        print(f"  抠背景: {bg} (tol={args.tol})")

    im = autocrop(im)
    im = fit_into(im, size)
    im = quantize(im, args.colors)
    if not args.no_outline:
        im = add_outline(im)

    os.makedirs(args.out, exist_ok=True)
    dst = os.path.join(args.out, args.name + ".png")
    im.save(dst)
    print("  输出:", dst)
    report(im, args.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
