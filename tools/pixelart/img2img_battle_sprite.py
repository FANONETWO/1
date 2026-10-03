#!/usr/bin/env python3
"""
img2img_battle_sprite.py —— 用 ComfyUI 做「图生图」产出战斗立绘

思路：以火纹原版素材（docs/art_reference/ref_*.png，结构最专业）作为**结构参考**，
用低去噪强度（denoise 0.5~0.7）让模型**保留构图**、只重绘材质与细节，
从而得到「火纹味」但**不复制原像素**的原创立绘。

流程：
  1. 连接 ComfyUI（默认 127.0.0.1:8188）
  2. 上传参考图
  3. 提交 img2img workflow（SD1.5 + 像素 LoRA）
  4. 取回结果 → 调 pixelize_for_game.py 降色 + 描边

用法：
  python tools/pixelart/img2img_battle_sprite.py \
      --ref docs/art_reference/ref_revenant.png \
      --prompt "pixel art sprite, rotting zombie, 3/4 side view, fire emblem gba style, 16 colors, white background" \
      --name zombie --denoise 0.62 --steps 26

  # 批量
  python tools/pixelart/img2img_battle_sprite.py --batch
"""
import argparse
import base64
import json
import os
import random
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOST = "http://127.0.0.1:8188"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def local_guard(url):
    """仅允许访问本机 ComfyUI（取图 URL 会拼上响应返回的字段，防 SSRF）。"""
    p = urllib.parse.urlparse(url)
    if p.scheme != "http" or p.hostname not in ("127.0.0.1", "localhost"):
        raise ValueError("只允许访问本机 ComfyUI: %s" % url)
    return url


def http_json(url, payload=None, timeout=60):
    url = local_guard(url)
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
    return json.loads(body) if body else {}


def server_alive():
    try:
        http_json(HOST + "/system_stats", timeout=5)
        return True
    except Exception:
        return False


def upload_image(path):
    """POST /upload/image（multipart）"""
    boundary = "----dsboundary" + str(random.randint(10 ** 8, 10 ** 9))
    with open(path, "rb") as f:
        content = f.read()
    name = os.path.basename(path)
    parts = []
    parts.append(("--" + boundary).encode())
    parts.append(b'Content-Disposition: form-data; name="image"; filename="%s"' % name.encode())
    parts.append(b"Content-Type: image/png")
    parts.append(b"")
    parts.append(content)
    parts.append(("--" + boundary).encode())
    parts.append(b'Content-Disposition: form-data; name="overwrite"')
    parts.append(b"")
    parts.append(b"true")
    parts.append(("--" + boundary + "--").encode())
    parts.append(b"")
    body = b"\r\n".join(parts)
    req = urllib.request.Request(local_guard(HOST + "/upload/image"), data=body,
                                 headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode())


def build_workflow(ref_name, prompt, negative, denoise, steps, cfg, seed, ckpt, lora):
    """构造 img2img workflow（ComfyUI API 格式）"""
    wf = {
        "1": {"class_type": "CheckpointLoaderSimple",
              "inputs": {"ckpt_name": ckpt}},
        "2": {"class_type": "LoadImage",
              "inputs": {"image": ref_name, "upload": "image"}},
        "3": {"class_type": "VAEEncode",
              "inputs": {"pixels": ["2", 0], "vae": ["1", 2]}},
        "4": {"class_type": "CLIPTextEncode",
              "inputs": {"text": prompt, "clip": ["1", 1]}},
        "5": {"class_type": "CLIPTextEncode",
              "inputs": {"text": negative, "clip": ["1", 1]}},
        "6": {"class_type": "KSampler",
              "inputs": {
                  "model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0],
                  "latent_image": ["3", 0], "seed": seed, "steps": steps, "cfg": cfg,
                  "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": denoise}},
        "7": {"class_type": "VAEDecode",
              "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage",
              "inputs": {"images": ["7", 0], "filename_prefix": "battle"}},
    }
    # 有 LoRA 就插入到模型链上
    if lora:
        wf["9"] = {"class_type": "LoraLoader",
                   "inputs": {"model": ["1", 0], "clip": ["1", 1],
                              "lora_name": lora, "strength_model": 0.85, "strength_clip": 0.85}}
        wf["4"]["inputs"]["clip"] = ["9", 1]
        wf["5"]["inputs"]["clip"] = ["9", 1]
        wf["6"]["inputs"]["model"] = ["9", 0]
    return wf


def run_one(args, ref_path, name, prompt):
    up = upload_image(ref_path)
    ref_name = up.get("name", os.path.basename(ref_path))
    print(f"  上传参考图 -> {ref_name}")

    wf = build_workflow(ref_name, prompt, args.negative, args.denoise,
                        args.steps, args.cfg, args.seed, args.ckpt, args.lora)
    res = http_json(HOST + "/prompt", {"prompt": wf})
    pid = res.get("prompt_id")
    print(f"  已提交 prompt_id={pid}")

    # 轮询
    for _ in range(600):
        time.sleep(1.0)
        hist = http_json(f"{HOST}/history/{pid}")
        if pid in hist:
            outs = hist[pid].get("outputs", {})
            for node in outs.values():
                for img in node.get("images", []):
                    q = urllib.parse.urlencode({
                        "filename": img["filename"],
                        "subfolder": img.get("subfolder", ""),
                        "type": img.get("type", "output")})
                    raw = urllib.request.urlopen(local_guard(f"{HOST}/view?{q}"), timeout=120).read()
                    outdir = os.path.join(ROOT, "assets", "raw", "ai")
                    os.makedirs(outdir, exist_ok=True)
                    safe_name = os.path.basename(str(name)).replace("/", "_").replace("\\", "_") or "ref"
                    raw_path = os.path.join(outdir, f"{safe_name}_raw.png")
                    Path(raw_path).write_bytes(raw)
                    print(f"  原图 -> {raw_path}")
                    return raw_path
            return None
    print("  超时")
    return None


BATCH = [
    # (参考图, 输出名, 提示词)
    ("docs/art_reference/ref_revenant.png", "zombie",
     "pixel art sprite of a rotting zombie, 3/4 side view facing left, fire emblem gba style, "
     "16 colors, dark outline, white background, full body, game asset"),
    ("docs/art_reference/ref_mauthe_doog.png", "crawler",
     "pixel art sprite of a four legged undead hound, side view facing left, fire emblem gba style, "
     "16 colors, dark outline, white background, full body, game asset"),
    ("docs/art_reference/ref_cyclops.png", "brute",
     "pixel art sprite of a huge one eyed undead ogre, 3/4 side view facing left, fire emblem gba style, "
     "16 colors, dark outline, white background, full body, game asset"),
    ("assets/sprites/w1/battle/hero.png", "hero",
     "pixel art sprite of a young survivor in a blue coat holding a steel pipe, 3/4 side view facing right, "
     "fire emblem gba style, 16 colors, dark outline, white background, full body, game asset"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref")
    ap.add_argument("--prompt")
    ap.add_argument("--name")
    ap.add_argument("--negative", default="blurry, realistic, 3d render, photo, text, watermark, multiple characters, extra limbs")
    ap.add_argument("--denoise", type=float, default=0.62)
    ap.add_argument("--steps", type=int, default=26)
    ap.add_argument("--cfg", type=float, default=7.0)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--ckpt", default="v1-5-pruned-emaonly.safetensors")
    ap.add_argument("--lora", default="")
    ap.add_argument("--batch", action="store_true")
    args = ap.parse_args()

    if not server_alive():
        print("ComfyUI 未在运行（默认 127.0.0.1:8188）。先启动：")
        print(r"  D:\1\ComfyUI_windows_portable\run_nvidia_gpu.bat")
        return 1

    if args.batch:
        for ref, name, prompt in BATCH:
            p = os.path.join(ROOT, ref)
            if not os.path.exists(p):
                print("  跳过（找不到）:", ref)
                continue
            print(f"=== {name} ===")
            run_one(args, p, name, prompt)
        return 0

    if not (args.ref and args.name and args.prompt):
        print("需要 --ref --name --prompt（或用 --batch）")
        return 1
    run_one(args, os.path.join(ROOT, args.ref), args.name, args.prompt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
