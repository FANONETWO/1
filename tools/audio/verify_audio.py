# -*- coding: utf-8 -*-
"""独立验收脚本（不 import gen_audio，完全另写一份读取逻辑，用于交叉复核）。

用法：
    python tools/audio/verify_audio.py

检查项：格式 / 时长 / 峰值 / 削波 / 静音 / 直流 / 振幅起伏 /
        BGM 循环点连续性（首尾样本差 + 一阶二阶差分）/ 目录总体积。
任一项不通过时以非 0 退出码结束。
"""
import math
import os
import sys
import wave

import numpy as np

SR_EXPECT = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO_ROOT = os.path.join(ROOT, "assets", "audio")
SFX_DIR = os.path.join(AUDIO_ROOT, "sfx")
BGM_DIR = os.path.join(AUDIO_ROOT, "bgm")

SFX_NAMES = ["ui_click", "ui_confirm", "ui_deny", "hit", "miss", "crit", "hurt", "die",
             "heal", "skill", "bloodline", "dice", "step", "door", "pickup", "clue",
             "noise", "evac", "defeat"]
BGM_NAMES = ["explore", "battle", "hub"]

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, sw, fr, nf = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(nf)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    return ch, sw, fr, x


def db(v):
    return 20.0 * math.log10(max(abs(v), 1e-12))


def dir_size(path):
    t = 0
    for root, _, files in os.walk(path):
        for f in files:
            t += os.path.getsize(os.path.join(root, f))
    return t


errors = []
rows = []

print("=" * 100)
print("【1】逐文件参数表（独立读取，非生成脚本自报）")
print("=" * 100)
print("%-16s %-5s %8s %6s %4s %11s %11s %8s %10s %9s" % (
    "文件名", "类型", "时长s", "声道", "位深", "峰值dBFS", "RMSdBFS", "削波", "大小KB", "峰值计数"))
print("-" * 100)

for kind, names, d in (("sfx", SFX_NAMES, SFX_DIR), ("bgm", BGM_NAMES, BGM_DIR)):
    for nm in names:
        p = os.path.join(d, nm + ".wav")
        if not os.path.exists(p):
            errors.append("缺失文件：%s" % p)
            continue
        ch, sw, fr, x = read_wav(p)
        pk = float(np.max(np.abs(x)))
        rms = float(np.sqrt(np.mean(x * x)))
        clipped = bool(np.any(np.abs(x) >= 32767))
        dur = len(x) / float(fr)
        size = os.path.getsize(p)
        rows.append(dict(kind=kind, name=nm, dur=dur, ch=ch, sw=sw, fr=fr, pk=pk,
                         pkdb=db(pk / 32767.0), rmsdb=db(rms / 32767.0),
                         clip=clipped, size=size, x=x, first=int(x[0]), last=int(x[-1])))
        print("%-16s %-5s %8.3f %6d %4d %11.2f %11.2f %8s %10.2f %9d" % (
            nm + ".wav", kind, dur, ch, sw * 8, db(pk / 32767.0), db(rms / 32767.0),
            "是" if clipped else "否", size / 1024.0, int(pk)))

# ---------------- 断言 1：格式 / 时长 / 峰值 ----------------
print()
print("=" * 100)
print("【2】格式 / 时长 / 峰值断言")
print("=" * 100)
for r in rows:
    if (r["ch"], r["sw"], r["fr"]) != (1, 2, SR_EXPECT):
        errors.append("%s 格式错误：%d 声道 / %d 字节 / %d Hz" % (r["name"], r["ch"], r["sw"], r["fr"]))
    if r["kind"] == "sfx":
        if not (0.08 <= r["dur"] <= 1.00):
            errors.append("%s 时长 %.3f 不在 0.08~1.00 s" % (r["name"], r["dur"]))
        if not (0.10 <= r["dur"] <= 0.90 + 1e-9):
            print("  (提示) %s 时长 %.3f 超出交付文档建议的 0.10~0.90 区间" % (r["name"], r["dur"]))
        if abs(r["pkdb"] - (-3.0)) > 2.0:
            errors.append("%s 峰值 %.2f dBFS 偏离 -3 超过 ±2 dB" % (r["name"], r["pkdb"]))
    else:
        if not (16.0 <= r["dur"] <= 24.0):
            errors.append("%s 时长 %.3f 不在 16~24 s" % (r["name"], r["dur"]))
        if abs(r["pkdb"] - (-8.0)) > 2.0:
            errors.append("%s 峰值 %.2f dBFS 偏离 -8 超过 ±2 dB" % (r["name"], r["pkdb"]))
    if r["clip"]:
        errors.append("%s 削波" % r["name"])
print("  格式（单声道/16-bit/22050 Hz）：%s" % ("全部通过" if not errors else "见错误列表"))
print("  sfx 时长区间：%.3f ~ %.3f s" % (min(r["dur"] for r in rows if r["kind"] == "sfx"),
                                        max(r["dur"] for r in rows if r["kind"] == "sfx")))
print("  bgm 时长区间：%.3f ~ %.3f s" % (min(r["dur"] for r in rows if r["kind"] == "bgm"),
                                        max(r["dur"] for r in rows if r["kind"] == "bgm")))
print("  sfx 峰值区间：%.2f ~ %.2f dBFS" % (min(r["pkdb"] for r in rows if r["kind"] == "sfx"),
                                          max(r["pkdb"] for r in rows if r["kind"] == "sfx")))
print("  bgm 峰值区间：%.2f ~ %.2f dBFS" % (min(r["pkdb"] for r in rows if r["kind"] == "bgm"),
                                          max(r["pkdb"] for r in rows if r["kind"] == "bgm")))

# ---------------- 断言 2：非静音 / 非纯直流 / 有实际振幅变化 ----------------
print()
print("=" * 100)
print("【3】非静音 / 非直流 / 振幅变化断言")
print("=" * 100)
print("%-16s %10s %10s %10s %12s %10s" % ("文件名", "std", "DC偏移", "零样本占比", "最长全零段s", "5ms窗RMS极差dB"))
print("-" * 100)
for r in rows:
    x = r["x"]
    xf = x / 32767.0
    std = float(np.std(xf))
    dc = float(np.mean(xf))
    zero_ratio = float(np.mean(np.abs(x) < 1e-9))
    # 最长连续全零段
    nz = np.abs(x) < 1e-9
    longest = cur = 0
    for v in nz:
        cur = cur + 1 if v else 0
        longest = max(longest, cur)
    # 5 ms 滑窗 RMS 的极差（是否有实际振幅起伏）
    win = int(0.005 * r["fr"])
    if len(x) >= win and win > 1:
        c = np.convolve(xf * xf, np.ones(win) / win, mode="valid")
        env = np.sqrt(np.maximum(c, 1e-30))
        spread = 20.0 * math.log10(max(env.max(), 1e-12) / max(env.min(), 1e-12))
    else:
        spread = float("nan")
    print("%-16s %10.5f %10.6f %10.4f %12.4f %10.1f" % (
        r["name"], std, dc, zero_ratio, longest / r["fr"], spread))
    r["std"] = std
    r["dc"] = dc
    if std < 1e-4:
        errors.append("%s 疑似静音 std=%.3e" % (r["name"], std))
    if abs(dc) > 0.01:
        errors.append("%s 直流偏置过大 dc=%.4f" % (r["name"], dc))
    if zero_ratio > 0.5:
        errors.append("%s 超过一半样本为 0" % r["name"])
    if longest / r["fr"] > 0.05:
        errors.append("%s 存在 %.3f s 的连续静音段" % (r["name"], longest / r["fr"]))
    if not (spread > 6.0):
        errors.append("%s 振幅包络变化不足（5ms RMS 极差仅 %.1f dB）" % (r["name"], spread))

# ---------------- 断言 3：BGM 首尾连续性（值 + 一阶/二阶差分） ----------------
print()
print("=" * 100)
print("【4】BGM 无缝循环检验（首尾样本差 + 循环点斜率/曲率是否落在内部正常范围内）")
print("=" * 100)
print("%-12s %10s %10s %12s %14s %16s %10s" % (
    "文件", "first", "last", "|diff|", "内部差分p99", "接缝差分/内部p99", "判定"))
print("-" * 100)
for r in rows:
    if r["kind"] != "bgm":
        continue
    x = r["x"]
    d_seam = abs(float(x[0] - x[-1]))
    d_inner = np.abs(np.diff(x))
    p99 = float(np.percentile(d_inner, 99))
    p999 = float(np.percentile(d_inner, 99.9))
    ratio = d_seam / max(p99, 1e-9)
    # 二阶：循环点的曲率
    d2_seam = abs(float((x[1] - x[0]) - (x[-1] - x[-2])))
    d2_inner = np.abs(np.diff(x, n=2))
    p99_2 = float(np.percentile(d2_inner, 99))
    # 拼接听感检查：把 [-2000:] 与 [:2000] 拼起来，看能量是否异常
    joined = np.concatenate([x[-4000:], x[:4000]])
    w = int(0.003 * r["fr"])
    e = np.sqrt(np.convolve((joined / 32767.0) ** 2, np.ones(w) / w, mode="valid"))
    seam_e = e[len(e) // 2]
    ok = (d_seam <= p99) and (d2_seam <= max(p99_2, 1.0))
    print("%-12s %10d %10d %12.1f %14.1f %16.4f %10s" % (
        r["name"], r["first"], r["last"], d_seam, p99, ratio, "OK" if ok else "!!"))
    print("            二阶差分：接缝 %.1f / 内部p99 %.1f   拼接点RMS %.6f（整段RMS %.6f）" % (
        d2_seam, p99_2, seam_e, float(np.sqrt(np.mean((x / 32767.0) ** 2)))))
    r["seam"] = d_seam
    r["seam2"] = d2_seam
    r["p99_2"] = p99_2
    if d_seam > 4:
        errors.append("%s |first-last|=%d 偏大" % (r["name"], d_seam))
    if d2_seam > max(p99_2, 1.0):
        errors.append("%s 循环点曲率突变（%.1f > 内部 p99 %.1f），可能有咔哒声" % (r["name"], d2_seam, p99_2))

# ---------------- 断言 4：总体积 ----------------
print()
print("=" * 100)
print("【5】体积")
print("=" * 100)
total = dir_size(AUDIO_ROOT)
wav_total = sum(r["size"] for r in rows)
print("  assets/audio 目录总计：%d 字节 = %.3f MB（%.3f MiB）" % (total, total / 1e6, total / 1048576.0))
print("  其中 WAV 合计：%d 字节 = %.3f MB" % (wav_total, wav_total / 1e6))
print("  上限 12 MB → 余量 %.3f MB" % (12.0 - total / 1e6))
if total > 12 * 1024 * 1024:
    errors.append("总大小 %.3f MB 超过 12 MB" % (total / 1048576.0))

# ---------------- 附加：频谱特征，确认音色确实不同 ----------------
print()
print("=" * 100)
print("【6】附加：频谱质心与主频（确认各音效音色确实不同，不是同一份噪声）")
print("=" * 100)
print("%-16s %12s %12s %14s" % ("文件名", "谱质心Hz", "主频Hz", "-10dB带宽Hz"))
print("-" * 100)
cent = {}
for r in rows:
    x = r["x"] / 32767.0
    n = len(x)
    win = np.hanning(n)
    X = np.abs(np.fft.rfft(x * win))
    freqs = np.fft.rfftfreq(n, 1.0 / r["fr"])
    p = X ** 2
    c = float(np.sum(freqs * p) / max(np.sum(p), 1e-12))
    fpk = float(freqs[int(np.argmax(X))])
    thr = X.max() / math.sqrt(10.0)      # -10 dB（功率 1/10）
    idx = np.where(X >= thr)[0]
    bw = float(freqs[idx[-1]] - freqs[idx[0]]) if len(idx) > 1 else 0.0
    cent[r["name"]] = c
    print("%-16s %12.1f %12.1f %14.1f" % (r["name"], c, fpk, bw))

print()
print("=" * 100)
if errors:
    print("验收结果：✗ 存在 %d 项问题" % len(errors))
    for e in errors:
        print("  - " + e)
    sys.exit(1)
print("验收结果：✓ 全部通过（格式 / 时长 / 峰值 / 非静音 / 非直流 / 振幅变化 / 循环无缝 / 体积）")
print("=" * 100)
