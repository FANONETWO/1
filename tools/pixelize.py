#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""AI 概念图 -> 真像素素材 后处理管线（《轮回回廊》素材流水线）。

把 AI（Leonardo / Pollinations / PixelLab 等）生成的「像素风格插画」转换成游戏
可直接使用的像素素材：去背景 -> 最近邻缩放 -> alpha 二值化 -> 调色板量化。

用法：
    python tools/pixelize.py --in raw.png --out assets/tiles/w1/floor.png --size 16
    python tools/pixelize.py --in raw.png --out assets/sprites/w1/player_idle.png --size 16x24 --colors 24
    python tools/pixelize.py --in assets/raw/w1 --out assets/tiles/w1 --size 16      # 批量目录
    # 加 --preview 8 会额外输出一张最近邻放大 8 倍的预览图，便于人工检查

硬性约定（像素画铁律）：
- 缩放一律 NEAREST，禁止双线性（否则像素糊成一片）
- alpha 二值化：像素画不应有半透明边缘
- 量化色数默认 24（本作规格：单图 ≤24 色）
"""
import argparse
import os

from PIL import Image

IMG_EXT = (".png", ".jpg", ".jpeg", ".webp", ".bmp")


def _close(a, b, tol):
    return all(abs(int(a[i]) - int(b[i])) <= tol for i in range(3))


def _dominant_corner_color(im):
    """取四角像素中的众数作为背景色（AI 出图常是纯色或渐变背景）。"""
    w, h = im.size
    px = im.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    best, best_n = corners[0], -1
    for c in corners:
        n = sum(1 for d in corners if _close(c, d, 24))
        if n > best_n:
            best, best_n = c, n
    return best


def strip_background(im, tol=30):
    """把与背景色相近的像素置为透明。"""
    im = im.convert("RGBA")
    bg = _dominant_corner_color(im)
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and _close((r, g, b), bg, tol):
                px[x, y] = (r, g, b, 0)
    return im


def quantize_rgba(im, colors):
    """对 RGB 通道做调色板量化，alpha 保持二值。"""
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v >= 128 else 0)
    rgb = Image.merge("RGB", (r, g, b))
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
    return Image.merge("RGBA", (q.split()[0], q.split()[1], q.split()[2], a))


def pixelize_one(src, dst, size, colors, do_strip, tol, preview=0):
    im = Image.open(src)
    fmt = im.format or "?"
    orig = im.size
    im = im.convert("RGBA")
    if do_strip:
        im = strip_background(im, tol)
    target = size if isinstance(size, tuple) else (size, size)
    im = im.resize(target, Image.NEAREST)
    im = quantize_rgba(im, colors)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    im.save(dst, "PNG")
    if preview > 0:
        pv = im.resize((target[0] * preview, target[1] * preview), Image.NEAREST)
        base, ext = os.path.splitext(dst)
        pv.save(base + "_preview" + ext, "PNG")
    n_colors = len(im.convert("RGB").getcolors(maxcolors=1 << 20) or [])
    return {"format": fmt, "orig": orig, "size": target, "colors": n_colors, "dst": dst}


def parse_size(s):
    s = str(s).lower()
    if "x" in s:
        a, b = s.split("x")
        return (int(a), int(b))
    return int(s)


def main():
    ap = argparse.ArgumentParser(description="AI 概念图 -> 真像素素材")
    ap.add_argument("--in", dest="src", required=True, help="输入图片或目录")
    ap.add_argument("--out", dest="dst", required=True, help="输出图片或目录")
    ap.add_argument("--size", default="16", help="目标尺寸，如 16 或 16x24")
    ap.add_argument("--colors", type=int, default=24, help="量化色数（默认 24）")
    ap.add_argument("--no-strip-bg", action="store_true", help="不去背景")
    ap.add_argument("--tol", type=int, default=30, help="去背景容差（默认 30）")
    ap.add_argument("--preview", type=int, default=0, help="额外输出最近邻放大 N 倍的预览图")
    args = ap.parse_args()

    size = parse_size(args.size)
    do_strip = not args.no_strip_bg

    if os.path.isdir(args.src):
        os.makedirs(args.dst, exist_ok=True)
        files = sorted(f for f in os.listdir(args.src) if f.lower().endswith(IMG_EXT))
        for f in files:
            out = os.path.join(args.dst, os.path.splitext(f)[0] + ".png")
            r = pixelize_one(os.path.join(args.src, f), out, size, args.colors, do_strip, args.tol, args.preview)
            print("[ok] %-5s %-12s -> %-9s %2d色  %s" % (r["format"], r["orig"], r["size"], r["colors"], r["dst"]))
        print("完成：%d 张" % len(files))
    else:
        r = pixelize_one(args.src, args.dst, size, args.colors, do_strip, args.tol, args.preview)
        print("[ok] 源格式=%s 原尺寸=%s -> 输出=%s 实际色数=%d" % (r["format"], r["orig"], r["size"], r["colors"]))
        print("     输出=%s" % r["dst"])


if __name__ == "__main__":
    main()
