#!/usr/bin/env python3
"""
fetch_models.py —— 从 hf-mirror（国内镜像）下载图生图所需模型到 ComfyUI 目录

用法：
  python tools/pixelart/fetch_models.py            # 下载全部
  python tools/pixelart/fetch_models.py --check    # 只看缺什么
"""
import argparse
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

# 国内镜像（比 huggingface.co 快很多）
HF = os.environ.get("HF_ENDPOINT", "https://hf-mirror.com")
COMFY = r"D:\1\ComfyUI_windows_portable\ComfyUI"

_ALLOWED_HOSTS = ("hf-mirror.com", "huggingface.co")


def _guard(url):
    """只允许从官方镜像下载（HF_ENDPOINT 可覆盖，但域名必须在白名单内）。"""
    p = urllib.parse.urlparse(url)
    if p.scheme not in ("http", "https") or p.hostname not in _ALLOWED_HOSTS:
        raise ValueError("只允许从官方镜像下载: %s" % url)
    return url


def _guard_dst(dst):
    """落盘路径必须位于 ComfyUI 目录内（防路径穿越）。"""
    root = os.path.realpath(COMFY)
    if not os.path.realpath(dst).startswith(root + os.sep):
        raise ValueError("目标路径必须在 ComfyUI 目录内: %s" % dst)
    return dst

# (repo, 文件名, 目标子目录, 大小参考)
FILES = [
    ("stable-diffusion-v1-5/stable-diffusion-v1-5",
     "v1-5-pruned-emaonly.safetensors", "models/checkpoints", "~4.0 GB"),
    # SD1.5 像素风 LoRA（Redmond 系列，作者公开）
    ("artificialguybr/PixelArtRedmond",
     "PixelArtRedmond15V-Pencil-A.safetensors", "models/loras", "~150 MB"),
    ("artificialguybr/PixelArtRedmond",
     "PixelArtRedmond-Lite64.safetensors", "models/loras", "~150 MB"),
]


def url_of(repo, name):
    return f"{HF}/{repo}/resolve/main/{name}"


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def download(url, dst):
    url = _guard(url)
    # 落盘路径必须位于 ComfyUI 目录内（防路径穿越）
    root = os.path.realpath(COMFY)
    real = os.path.realpath(dst)
    if not real.startswith(root + os.sep):
        raise ValueError("目标路径必须在 ComfyUI 目录内: %s" % dst)
    dst = real
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        total = int(r.headers.get("Content-Length", 0))
        got = 0
        last = 0
        with Path(tmp).open("wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
                pct = (got / total * 100) if total else 0
                if pct - last >= 5:
                    last = pct
                    print(f"      {pct:5.1f}%  {human(got)} / {human(total)}", flush=True)
    os.replace(tmp, dst)
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    if not os.path.isdir(COMFY):
        print("找不到 ComfyUI 目录:", COMFY)
        print("请先等 ComfyUI_windows_portable 解压完成")
        return 1

    todo = []
    for repo, name, sub, size in FILES:
        dst = os.path.join(COMFY, sub.replace("/", os.sep), name)
        exists = os.path.exists(dst)
        mark = "OK  " if exists else "缺  "
        print(f"  {mark}{name}  ({size})  -> {sub}")
        if not exists:
            todo.append((repo, name, dst))

    if args.check:
        return 0
    if not todo:
        print("全部已就位。")
        return 0

    print(f"\n需要下载 {len(todo)} 个文件，镜像: {HF}")
    for repo, name, dst in todo:
        print(f"  下载 {name} ...")
        try:
            n = download(url_of(repo, name), dst)
            print(f"    完成 {human(n)}")
        except Exception as e:
            print(f"    失败: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
