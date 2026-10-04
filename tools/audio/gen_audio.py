# -*- coding: utf-8 -*-
"""
无限流 CRPG《惊变公寓》—— 程序化音频资产生成器
================================================================================

【设计意图】
本项目此前完全没有音频（全仓库零 AudioStream 引用），试玩反馈把"全无音效与 BGM"列为
最劝退的问题之一。外购 / 下载素材存在版权与网络依赖风险，因此本脚本用**纯数学合成**
的方式一次性产出整套 19 个交互 / 战斗音效 + 3 首可无缝循环的 BGM，全部资产零第三方版权、
零外部素材、零网络访问。

【技术约束】
* 只依赖标准库 + numpy。WAV 由标准库 ``wave`` 手写 16-bit PCM，不引入 soundfile / pydub。
* 单声道 22050 Hz / 16-bit —— 像素风 CRPG 的体量与听感足够，整套压在 3 MB 以内。
* 幂等：不使用任何随时间 / 环境变化的值，所有随机数来自固定 seed 的
  ``np.random.default_rng``，因此同一份代码必然产出**逐字节相同**的 WAV。
* 归一化：sfx 峰值 ≈ -3 dBFS（操作反馈要清楚）；BGM 峰值 ≈ -8 dBFS（明确比音效轻，
  避免盖住命中 / 点击一类的关键反馈）。

【BGM 无缝循环的做法 —— 本脚本的核心难点】
循环点"啪"的爆音有两种来源：(a) 首尾样本值跳变；(b) 波形斜率不连续。这里用三重保险：
 1. **频率栅格化**（``Grid.f``）：所有持续性振荡器与 LFO 的频率都被吸附到 ``k * SR / N``
    （k 为整数），即每个分音在循环长度内恰好完成整数个周期。于是把序列做循环延拓后，
    波形天然连续，连斜率都连续。
 2. **事件内嵌**（``event_env``）：所有脉冲 / 噪声 / 金属碰响 / 钟声等非周期事件都完整
    落在循环内部，包络在首尾严格为 0，绝不跨越循环缝合线。
 3. **尾部微对齐**（``loop_fix``）：最后把 ``x[0]`` 与 ``x[-1]`` 的残差用一段极小的对称
    斜坡抹平（修正量通常 < 1e-3，不可闻），使首尾样本严格相等。
另外 BGM 全程使用 ``circ_fir``（FFT 循环卷积）做滤波，避免线性卷积在循环边界产生瞬态。

【各音效的合成方法速查】
  ui_click   带通噪声"嗒" + 1.15 kHz 与 2.6 kHz 极短正弦 → 清脆电子点击
  ui_confirm 1046.5 / 1568 Hz 两声正弦（含 2、3 次谐波）上行 → 确认
  ui_deny    225→178 Hz 软化方波（tanh 限幅）低通 → 低沉"嘟"
  hit        95→42 Hz 扫频正弦钝击 + 带通噪声爆 + tanh 饱和
  miss       6 个带通频带的白噪声按三角权重随时间交叉淡化 → 风声扫过（高频→低频）
  crit       hit 音色叠加 5 个非谐和比例高频分音 + 环调制 → 金属亮音
  hurt       低通噪声闷响 + 下滑 sub + 声带脉冲串过三组共振峰带通 → 人声感闷哼
  die        0.62 s 下滑呻吟（脉冲串 + 颤音 + 共振峰）+ 0.62 s 处落地闷响
  heal       C5-E5-G5-C6 柔和正弦琶音（错开进入 + 轻微空气噪声）
  skill      指数上扫正弦（基频 + 五度）加 FM + 上扬带通噪声 whoosh
  bloodline  6.5 Hz 门控的 55/82.5/27.5 Hz 脉冲低音 + 锯齿波失真上扫 78→430 Hz + 爆发
  dice       5 记固定种子随机分布的骰子"喀哒" + 0.56 s 一记落定
  step       1.7 kHz 低通噪声脉冲 + 极轻 110 Hz 低频 body
  door       频率抖动的正弦簇 + 摩擦带通噪声构成门轴吱呀，0.66 s 处"咔哒"
  pickup     1318.5 / 1975.5 Hz 两记短促上行叮
  clue       F5 → B5（增四度）→ G#5 三音 + 三段衰减延迟拷贝的简易混响 → 神秘感
  noise      远处嘶叫（脉冲串 + 共振峰 + 低通衰减高频）+ 0.52 / 0.70 s 两下心跳
  evac       C 大调五音上行琶音 + 2093 Hz 明亮顶点铃音
  defeat     A 小调五音下行琶音 + 失谐 detune + 低通变暗 + 55 Hz 压迫低音

【BGM —— 已迁出本脚本】
  三首 BGM（explore / battle / hub）现在由 tools/music/render_bgm.mjs 生成：
  改用 FluidSynth 真实音源（低音弦乐 / 定音鼓 / 钟琴 / 合唱 pad），
  素材是 MIDI 乐谱而不是波形合成，才对得上本副本的恐怖片配乐语汇。
  本脚本从此只负责 19 个音效；BGM 的验收仍由 tools/audio/verify_audio.py 覆盖。

运行： python tools/audio/gen_audio.py
================================================================================
"""

import hashlib
import math
import os
import sys
import wave

import numpy as np

# ---------------------------------------------------------------------------
# 全局常量
# ---------------------------------------------------------------------------
SR = 22050                     # 采样率（Hz），单声道
SFX_PEAK_DBFS = -3.0           # 音效峰值目标
BGM_PEAK_DBFS = -8.0           # BGM 峰值目标（明显更轻）

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
BGM_DIR = os.path.join(ROOT, "assets", "audio", "bgm")

# (文件名, 设计时长秒) —— 全部落在 0.10~0.90 s 区间内
SFX_SPECS = [
    ("ui_click", 0.12),
    ("ui_confirm", 0.32),
    ("ui_deny", 0.24),
    ("hit", 0.30),
    ("miss", 0.34),
    ("crit", 0.48),
    ("hurt", 0.36),
    ("die", 0.86),
    ("heal", 0.55),
    ("skill", 0.48),
    ("bloodline", 0.88),
    ("dice", 0.78),
    ("step", 0.12),
    ("door", 0.84),
    ("pickup", 0.22),
    ("clue", 0.72),
    ("noise", 0.88),
    ("evac", 0.86),
    ("defeat", 0.88),
]

# BGM 不再由本脚本生成 —— 见 tools/music/render_bgm.mjs（FluidSynth 真实音源）。
# 下面三个 bgm_* 合成函数与其 BUILDER 映射刻意留着：一是作为旧版听感的对照，
# 二是万一要回退纯数学合成时有据可查。它们已不被 main() 调用。
BGM_NAMES = ["explore", "battle", "hub"]


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------
def nsamp(dur):
    """时长（秒）→ 样本数。"""
    return int(round(dur * SR))


def tt(n):
    """n 个样本的时间轴（秒）。"""
    return np.arange(n, dtype=np.float64) / SR


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def lin_to_db(x):
    return 20.0 * math.log10(max(abs(float(x)), 1e-12))


def normalize_peak(x, dbfs):
    """把峰值归一到指定 dBFS。"""
    m = float(np.max(np.abs(x)))
    if m < 1e-12:
        raise ValueError("信号为静音，无法归一化")
    return x * (db_to_lin(dbfs) / m)


def fade(x, ms=3.0):
    """首尾线性淡入淡出，消除截断爆音。返回新数组。"""
    y = np.array(x, dtype=np.float64, copy=True)
    n = min(int(ms * SR / 1000.0), len(y) // 2)
    if n >= 2:
        w = np.linspace(0.0, 1.0, n)
        y[:n] *= w
        y[-n:] *= w[::-1]
    return y


def env_perc(t, attack, decay, power=1.0):
    """打击 / 拨弦类包络：attack 线性上升，之后按 power 次幂的指数衰减。"""
    a = max(float(attack), 1e-6)
    d = max(float(decay), 1e-6)
    rise = np.minimum(t / a, 1.0)
    fall = np.exp(-np.maximum(t - a, 0.0) / d)
    return rise * (fall ** float(power))


def phase_sweep(f0, f1, t, kind="exp"):
    """相位连续的扫频，返回瞬时相位（弧度）。"""
    T = float(t[-1]) if len(t) > 1 else 1.0
    f0 = max(float(f0), 1e-6)
    f1 = max(float(f1), 1e-6)
    if abs(f1 - f0) < 1e-9 or T <= 0.0:
        return 2.0 * np.pi * f0 * t
    if kind == "exp":
        k = math.log(f1 / f0) / T
        return 2.0 * np.pi * f0 * (np.exp(k * t) - 1.0) / k
    return 2.0 * np.pi * (f0 * t + (f1 - f0) * t * t / (2.0 * T))


def osc_sweep(f0, f1, t, kind="exp"):
    return np.sin(phase_sweep(f0, f1, t, kind))


# ---------------------------------------------------------------------------
# FIR 滤波（窗函数法设计 + 卷积）
#   sfx 用线性卷积 apply_fir；BGM 用 circ_fir（FFT 循环卷积），
#   后者不会在循环边界引入"缺少过去/未来样本"的瞬态。
# ---------------------------------------------------------------------------
def _window(taps):
    return np.hamming(taps)


def fir_lowpass(cutoff, taps=81):
    n = np.arange(taps, dtype=np.float64) - (taps - 1) / 2.0
    fc = float(cutoff) / SR
    h = 2.0 * fc * np.sinc(2.0 * fc * n) * _window(taps)
    s = h.sum()
    if abs(s) > 1e-12:
        h = h / s
    return h


def fir_highpass(cutoff, taps=81):
    h = fir_lowpass(cutoff, taps)
    h = -h
    h[(taps - 1) // 2] += 1.0
    return h


def fir_bandpass(lo, hi, taps=81):
    n = np.arange(taps, dtype=np.float64) - (taps - 1) / 2.0
    f1, f2 = float(lo) / SR, float(hi) / SR
    h = (2.0 * f2 * np.sinc(2.0 * f2 * n) - 2.0 * f1 * np.sinc(2.0 * f1 * n)) * _window(taps)
    s = np.abs(h).sum()
    if s > 1e-12:
        h = h / s
    return h


def apply_fir(x, h):
    """线性相位 FIR，输出与输入等长（用于音效，端点由 fade 处理）。"""
    y = np.convolve(np.asarray(x, dtype=np.float64), h, mode="full")
    d = (len(h) - 1) // 2
    y = y[d:d + len(x)]
    if len(y) < len(x):
        y = np.concatenate([y, np.zeros(len(x) - len(y))])
    return y


def circ_fir(x, h):
    """FFT 循环卷积（用于 BGM，保持循环连续性）。"""
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    if len(h) >= n:
        return apply_fir(x, h)
    H = np.fft.rfft(np.concatenate([h, np.zeros(n - len(h))]))
    return np.fft.irfft(np.fft.rfft(x) * H, n)


def swept_band_noise(n, bands, rng, taps=81):
    """把白噪声分别过多个带通，再按三角权重在时间轴上交叉淡化 → 频带随时间"扫过"。

    bands 从高频到低频给出，即得到高频→低频的呼啸感。
    """
    out = np.zeros(n)
    m = len(bands)
    if m == 1:
        return apply_fir(rng.standard_normal(n), fir_bandpass(bands[0][0], bands[0][1], taps))
    u = np.linspace(0.0, 1.0, n)
    for i, (lo, hi) in enumerate(bands):
        c = i / (m - 1.0)
        w = np.maximum(0.0, 1.0 - np.abs(u - c) * (m - 1.0))
        if not np.any(w > 1e-6):
            continue
        out += apply_fir(rng.standard_normal(n), fir_bandpass(lo, hi, taps)) * w
    return out


def metal_click(tl, base, ratios, rng, decay, detune_phase=0.0):
    """非谐和比例正弦簇 → 金属 / 玻璃质的碰响。"""
    y = np.zeros_like(tl)
    for i, r in enumerate(ratios):
        y += (0.62 ** i) * np.sin(2.0 * np.pi * base * r * tl + detune_phase * r + i * 0.7)
    y *= np.exp(-tl / max(decay, 1e-4))
    y *= np.minimum(tl / 0.002, 1.0)
    return y


def event_env(tl, ln, decay, attack_ms=2.0, tail_ms=12.0):
    """事件包络：起音归零 + 指数衰减 + 尾窗归零（保证事件绝不跨越 BGM 循环缝）。"""
    na = max(int(attack_ms * SR / 1000.0), 1)
    nz = max(int(tail_ms * SR / 1000.0), 1)
    rise = np.minimum(tl / (na / SR), 1.0)
    fall = np.exp(-tl / max(decay, 1e-4))
    tail = np.clip((ln - tl) / (nz / SR), 0.0, 1.0)
    return rise * fall * tail


# ---------------------------------------------------------------------------
# BGM 频率栅格：把频率吸附到 k * SR / N，保证循环长度内整数个周期
# ---------------------------------------------------------------------------
class Grid(object):
    def __init__(self, n):
        self.n = n

    def f(self, freq):
        k = int(round(float(freq) * self.n / SR))
        return max(1, k) * SR / self.n


def loop_fix(x):
    """把 |x[0] - x[-1]| 抹平到 0：首尾各做一半的极小对称斜坡修正，直流互相抵消。"""
    y = np.array(x, dtype=np.float64, copy=True)
    d = float(y[-1] - y[0])
    if abs(d) < 1e-15:
        return y
    k = min(2048, len(y) // 4)
    if k < 4:
        return y
    ramp = np.linspace(0.0, 1.0, k)
    y[:k] += (d / 2.0) * (1.0 - ramp)   # 头部：x[0] 抬 d/2
    y[-k:] -= (d / 2.0) * ramp          # 尾部：x[-1] 落 d/2
    return y


# ===========================================================================
# 音效合成（每个函数返回浮点波形，之后统一归一化 / 量化）
# ===========================================================================
def sfx_ui_click(dur, rng):
    """界面点击：短促清脆的电子"嗒"。"""
    n = nsamp(dur)
    t = tt(n)
    body = np.sin(2.0 * np.pi * 1150.0 * t) * np.exp(-t / 0.018)
    tick = np.sin(2.0 * np.pi * 2600.0 * t) * np.exp(-t / 0.005)
    box = np.sin(2.0 * np.pi * 780.0 * t) * np.exp(-t / 0.030) * 0.30
    click = apply_fir(rng.standard_normal(n), fir_bandpass(1500.0, 7000.0, 61))
    click = click * np.exp(-t / 0.0025) * 0.45
    return fade(0.90 * body + 0.50 * tick + box + click, 2.5)


def sfx_ui_confirm(dur, rng):
    """确认 / 购点成功：上行两声。"""
    n = nsamp(dur)
    y = np.zeros(n)
    for i, (f, st) in enumerate([(1046.50, 0.0), (1567.98, 0.13)]):
        s = int(st * SR)
        tl = tt(n - s)
        e = env_perc(tl, 0.004, 0.095, power=1.1)
        v = (np.sin(2.0 * np.pi * f * tl)
             + 0.30 * np.sin(4.0 * np.pi * f * tl)
             + 0.12 * np.sin(6.0 * np.pi * f * tl))
        y[s:] += v * e * (0.88 if i == 0 else 1.0)
    return fade(y, 3.0)


def sfx_ui_deny(dur, rng):
    """操作非法 / 不可点：低沉短"嘟"。"""
    n = nsamp(dur)
    t = tt(n)
    ph = phase_sweep(225.0, 178.0, t, "exp")
    soft_sq = np.tanh(np.sign(np.sin(ph)) * 1.6)
    e = env_perc(t, 0.006, 0.110)
    y = apply_fir(soft_sq * e, fir_lowpass(1400.0, 61))
    y += 0.25 * np.sin(ph) * e
    return fade(y, 3.0)


def _hit_core(n, t, rng, thump_hi=95.0, thump_lo=42.0):
    ph = phase_sweep(thump_hi, thump_lo, t, "exp")
    thump = np.sin(ph) * np.exp(-t / 0.055) + 0.5 * np.sin(2.0 * ph) * np.exp(-t / 0.030)
    nz = apply_fir(rng.standard_normal(n), fir_bandpass(700.0, 4500.0, 81))
    nz = nz * np.exp(-t / 0.028) * np.minimum(t / 0.0008, 1.0)
    return 1.0 * thump + 0.75 * nz


def sfx_hit(dur, rng):
    """命中：钝击 + 短噪声爆。"""
    n = nsamp(dur)
    t = tt(n)
    y = _hit_core(n, t, rng)
    return fade(np.tanh(y * 1.35) * 0.85, 2.5)


def sfx_miss(dur, rng):
    """挥空 / 未命中：风声呼啸，低频扫过。"""
    n = nsamp(dur)
    t = tt(n)
    bands = [(2500.0, 6000.0), (1400.0, 3600.0), (800.0, 2200.0),
             (450.0, 1200.0), (260.0, 700.0), (150.0, 420.0)]
    nz = swept_band_noise(n, bands, rng, taps=81)
    sweep = np.sin(phase_sweep(420.0, 130.0, t, "exp")) * 0.28
    e = np.sin(np.pi * t / t[-1]) ** 1.6          # 中间最响
    y = apply_fir((nz + sweep) * e, fir_lowpass(7000.0, 61))
    return fade(y, 5.0)


def sfx_crit(dur, rng):
    """暴击：命中音 + 金属亮音。"""
    n = nsamp(dur)
    t = tt(n)
    core = sfx_hit(0.30, rng)
    y = np.zeros(n)
    m = min(n, len(core))
    y[:m] = core[:m]
    # 非谐和比例的高频簇 → 金属感
    met = np.zeros(n)
    for i, (r, ph0) in enumerate([(1.00, 0.3), (1.73, 1.1), (2.41, 2.2), (3.17, 3.9), (4.09, 5.1)]):
        f = 2100.0 * r
        met += (0.62 ** i) * np.sin(2.0 * np.pi * f * t + ph0) * np.exp(-t / max(0.32 - i * 0.045, 0.05))
    met *= (0.75 + 0.25 * np.sin(2.0 * np.pi * 137.0 * t))   # 环调制增金属味
    y += 0.62 * met
    y += 0.30 * np.sin(2.0 * np.pi * 5200.0 * t) * np.exp(-t / 0.012)
    return fade(y, 3.0)


def sfx_hurt(dur, rng):
    """我方受伤：闷响 + 短促人声感的低频。"""
    n = nsamp(dur)
    t = tt(n)
    thud = apply_fir(rng.standard_normal(n), fir_lowpass(320.0, 81)) * np.exp(-t / 0.05)
    sub = np.sin(phase_sweep(120.0, 78.0, t, "exp")) * np.exp(-t / 0.075)
    # 声带脉冲串 + 三组共振峰 → 人声"哼"感
    f0 = 155.0 * np.exp(-t * 1.1) + 95.0
    phv = 2.0 * np.pi * np.cumsum(f0) / SR
    glot = np.sign(np.sin(phv)) * 0.55 + np.sin(2.0 * phv) * 0.30
    voice = glot * env_perc(t, 0.012, 0.10)
    form = (apply_fir(voice, fir_bandpass(380.0, 900.0, 101)) * 1.00
            + apply_fir(voice, fir_bandpass(900.0, 1800.0, 101)) * 0.70
            + apply_fir(voice, fir_bandpass(2200.0, 3200.0, 101)) * 0.35)
    y = 0.80 * thud + 0.90 * sub + 1.10 * form
    return fade(np.tanh(y * 1.2) * 0.85, 3.0)


def sfx_die(dur, rng):
    """敌人倒下：拖长下滑的呻吟感合成音 + 落地闷响。"""
    n = nsamp(dur)
    y = np.zeros(n)
    nd = int(0.62 * SR)
    td = tt(nd)
    f0 = 190.0 * np.exp(-td * 0.9) + 78.0
    vib = 1.0 + 0.035 * np.sin(2.0 * np.pi * 5.4 * td) * np.minimum(td / 0.08, 1.0)
    ph = 2.0 * np.pi * np.cumsum(f0 * vib) / SR
    glot = np.sign(np.sin(ph)) * 0.55 + np.sin(2.0 * ph) * 0.30 + np.sin(3.0 * ph) * 0.12
    voice = glot * env_perc(td, 0.06, 0.42, power=1.3)
    groan = (apply_fir(voice, fir_bandpass(300.0, 780.0, 101)) * 1.00
             + apply_fir(voice, fir_bandpass(780.0, 1500.0, 101)) * 0.62
             + apply_fir(voice, fir_bandpass(1800.0, 2600.0, 101)) * 0.30)
    groan = apply_fir(groan, fir_lowpass(3000.0, 61))          # 更闷、更远
    y[:nd] += groan
    # 落地闷响
    p = int(0.62 * SR)
    ln = n - p
    tl = tt(ln)
    thud = np.sin(2.0 * np.pi * (70.0 * np.exp(-tl * 6.0) + 38.0) * tl) * np.exp(-tl / 0.10)
    nz = apply_fir(rng.standard_normal(ln), fir_lowpass(900.0, 81)) * np.exp(-tl / 0.05)
    y[p:] += 0.95 * thud + 0.40 * nz
    return fade(np.tanh(y * 1.15) * 0.85, 3.0)


def sfx_heal(dur, rng):
    """治疗 / 用药：上行的柔和正弦琶音。"""
    n = nsamp(dur)
    t = tt(n)
    y = np.zeros(n)
    for f, st in [(523.25, 0.0), (659.25, 0.11), (783.99, 0.22), (1046.50, 0.33)]:
        s = int(st * SR)
        tl = tt(n - s)
        e = env_perc(tl, 0.035, 0.30, power=1.2)
        v = (np.sin(2.0 * np.pi * f * tl)
             + 0.22 * np.sin(4.0 * np.pi * f * tl)
             + 0.06 * np.sin(6.0 * np.pi * f * tl))
        y[s:] += v * e * 0.90
    air = apply_fir(rng.standard_normal(n), fir_bandpass(3000.0, 8000.0, 81))
    y += air * 0.05 * np.exp(-np.maximum(t - 0.05, 0.0) / 0.35)
    return fade(y, 5.0)


def sfx_skill(dur, rng):
    """技能发动：上扬能量波。"""
    n = nsamp(dur)
    t = tt(n)
    ph1 = phase_sweep(180.0, 1700.0, t, "exp")
    ph2 = phase_sweep(270.0, 2560.0, t, "exp")
    fm = np.sin(2.0 * np.pi * 11.0 * t) * 0.6
    v = (np.sin(ph1 + fm) * 0.90
         + np.sin(ph2 + fm * 0.5) * 0.55
         + np.sin(ph1 * 0.5) * 0.30)
    e = env_perc(t, 0.020, 0.24, power=1.2)
    bands = [(300.0, 900.0), (600.0, 1800.0), (1200.0, 3500.0), (2400.0, 6500.0), (4000.0, 9000.0)]
    nz = swept_band_noise(n, bands, rng, taps=81) * env_perc(t, 0.05, 0.22, power=1.1)
    y = v * e + 0.42 * nz
    return fade(np.tanh(y * 1.1) * 0.90, 3.0)


def sfx_bloodline(dur, rng):
    """血统 / 基因锁觉醒：低沉脉冲 + 失真上扫，要压迫感。"""
    n = nsamp(dur)
    t = tt(n)
    # 6.5 Hz 门控的低频脉冲
    gate = (0.5 + 0.5 * np.sin(2.0 * np.pi * 6.5 * t - np.pi / 2.0)) ** 2.2
    pulse = (np.sin(2.0 * np.pi * 55.0 * t)
             + 0.50 * np.sin(2.0 * np.pi * 82.5 * t)
             + 0.35 * np.sin(2.0 * np.pi * 27.5 * t)) * gate
    # 锯齿波失真上扫
    ph = phase_sweep(78.0, 430.0, t, "exp")
    saw = 2.0 * (ph / (2.0 * np.pi) - np.floor(ph / (2.0 * np.pi) + 0.5))
    drive = 3.0 + 5.0 * np.minimum(t / max(t[-1] * 0.8, 1e-6), 1.0)
    dist = apply_fir(np.tanh(saw * drive), fir_lowpass(2600.0, 61))
    # 末段爆发
    late = np.clip((t - 0.62) / 0.04, 0.0, 1.0)
    boom = np.sin(2.0 * np.pi * 42.0 * t) * np.exp(-np.maximum(t - 0.62, 0.0) / 0.16) * late
    e1 = np.minimum(t / 0.12, 1.0)
    e2 = np.minimum(np.maximum(t - 0.30, 0.0) / 0.06, 1.0)
    y = pulse * e1 + 0.55 * dist * e2 + 0.85 * boom
    y *= np.exp(-np.maximum(t - 0.74, 0.0) / 0.20)
    return fade(np.tanh(y * 1.25) * 0.90, 4.0)


def sfx_dice(dur, rng):
    """D10 骰池检定：几粒骰子滚动 + 一记落定。"""
    n = nsamp(dur)
    t = tt(n)
    y = np.zeros(n)
    for tm in np.sort(rng.uniform(0.02, 0.48, 7)):
        s = int(tm * SR)
        ln = n - s
        tl = tt(ln)
        e = np.exp(-tl / (0.010 + rng.uniform(0.0, 0.006)))
        clack = apply_fir(rng.standard_normal(ln), fir_bandpass(1200.0, 6500.0, 61))
        clack += np.sin(2.0 * np.pi * rng.uniform(700.0, 1400.0) * tl) * 0.5
        y[s:] += clack * e * rng.uniform(0.72, 1.05)
    # 落定
    s = int(0.56 * SR)
    ln = n - s
    tl = tt(ln)
    settle = apply_fir(rng.standard_normal(ln), fir_bandpass(900.0, 5200.0, 71)) * np.exp(-tl / 0.020)
    settle += np.sin(2.0 * np.pi * 150.0 * tl) * np.exp(-tl / 0.05) * 0.70
    y[s:] += settle * 1.20
    # 骰子在桌面滚动的极轻摩擦层：听感更真实，同时避免喀哒之间出现数字绝对静音段
    roll = apply_fir(rng.standard_normal(n), fir_bandpass(300.0, 1800.0, 61))
    roll *= (0.25 + 0.75 * np.exp(-t / 0.35)) * (0.60 + 0.40 * np.abs(np.sin(2.0 * np.pi * 7.3 * t)))
    y += roll * 0.08
    return fade(y, 2.5)


def sfx_step(dur, rng):
    """脚步：很轻的噪声脉冲。"""
    n = nsamp(dur)
    t = tt(n)
    nz = apply_fir(rng.standard_normal(n), fir_lowpass(1700.0, 81)) * env_perc(t, 0.003, 0.045)
    body = np.sin(2.0 * np.pi * 110.0 * t) * np.exp(-t / 0.03) * 0.5
    return fade(nz + body, 2.0)


def sfx_door(dur, rng):
    """开门 / 切换房间：门轴吱呀 + 咔哒。"""
    n = nsamp(dur)
    t = tt(n)
    # 吱呀：频率抖动的正弦簇 + 摩擦噪声
    wob = 1.0 + 0.18 * np.sin(2.0 * np.pi * 1.7 * t) + 0.09 * np.sin(2.0 * np.pi * 4.3 * t + 1.0)
    ph = 2.0 * np.pi * np.cumsum(1900.0 * wob) / SR
    creak = np.sin(ph) * 0.60 + np.sin(2.0 * ph) * 0.25 + np.sin(3.0 * ph) * 0.12
    fric = apply_fir(rng.standard_normal(n), fir_bandpass(1200.0, 4200.0, 81))
    fric *= (0.4 + 0.6 * np.abs(np.sin(2.0 * np.pi * 2.6 * t)))
    ecr = np.minimum(t / 0.05, 1.0) * np.exp(-np.maximum(t - 0.05, 0.0) / 0.30)
    y = (creak * 0.5 + fric * 0.7) * ecr
    # 咔哒
    p = int(0.66 * SR)
    ln = n - p
    tl = tt(ln)
    clack = apply_fir(rng.standard_normal(ln), fir_bandpass(1500.0, 7000.0, 71)) * np.exp(-tl / 0.008)
    clack += np.sin(2.0 * np.pi * 190.0 * tl) * np.exp(-tl / 0.04) * 0.65
    y[p:] += clack * 1.15
    return fade(np.tanh(y * 1.15) * 0.90, 3.0)


def sfx_pickup(dur, rng):
    """拾取物品：短促上行叮。"""
    n = nsamp(dur)
    y = np.zeros(n)
    for f, st, a in [(1318.51, 0.0, 0.85), (1975.53, 0.055, 1.0)]:
        s = int(st * SR)
        tl = tt(n - s)
        e = env_perc(tl, 0.003, 0.055)
        v = np.sin(2.0 * np.pi * f * tl) + 0.25 * np.sin(4.0 * np.pi * f * tl)
        y[s:] += v * e * a
    return fade(y, 2.5)


def sfx_clue(dur, rng):
    """发现线索：神秘的两音三音提示（增四度音程 + 简易混响）。"""
    n = nsamp(dur)
    y = np.zeros(n)
    for f, st, a, dc in [(698.46, 0.00, 0.90, 0.16),
                         (987.77, 0.16, 1.00, 0.20),
                         (830.61, 0.34, 0.85, 0.34)]:
        s = int(st * SR)
        tl = tt(n - s)
        e = env_perc(tl, 0.020, dc, power=1.3)
        v = (np.sin(2.0 * np.pi * f * tl)
             + 0.30 * np.sin(4.0 * np.pi * f * tl)
             + 0.10 * np.sin(6.02 * np.pi * f * tl))
        y[s:] += v * e * a
    dry = y.copy()
    for dly, g in [(0.085, 0.30), (0.145, 0.20), (0.225, 0.13)]:
        s = int(dly * SR)
        y[s:] += dry[:n - s] * g * 0.6
    return fade(y, 5.0)


def sfx_noise(dur, rng):
    """噪音警戒：丧尸被吸引 —— 远处嘶叫 + 心跳两下。"""
    n = nsamp(dur)
    t = tt(n)
    y = np.zeros(n)
    nd = int(0.46 * SR)
    td = tt(nd)
    f0 = 168.0 * np.exp(-td * 0.7) + 112.0
    vib = 1.0 + 0.05 * np.sin(2.0 * np.pi * 4.6 * td)
    ph = 2.0 * np.pi * np.cumsum(f0 * vib) / SR
    glot = np.sign(np.sin(ph)) * 0.50 + np.sin(2.0 * ph) * 0.30 + np.sin(3.0 * ph) * 0.15
    e = env_perc(td, 0.05, 0.20, power=1.2)
    voice = glot * e
    hiss = apply_fir(rng.standard_normal(nd), fir_bandpass(700.0, 2400.0, 81)) * e * 0.55
    groan = (apply_fir(voice, fir_bandpass(250.0, 700.0, 101)) * 0.90
             + apply_fir(voice, fir_bandpass(700.0, 1400.0, 101)) * 0.55)
    groan = apply_fir(groan, fir_lowpass(2200.0, 61))
    y[:nd] += groan + hiss
    for p0, a in [(0.52, 1.0), (0.70, 0.82)]:
        p = int(p0 * SR)
        ln = n - p
        tl = tt(ln)
        beat = (np.sin(2.0 * np.pi * 58.0 * tl) * np.exp(-tl / 0.045)
                + 0.55 * np.sin(2.0 * np.pi * 33.0 * tl) * np.exp(-tl / 0.070))
        nzl = apply_fir(rng.standard_normal(ln), fir_lowpass(260.0, 61)) * np.exp(-tl / 0.03) * 0.4
        y[p:] += (beat + nzl) * a * 0.95
    # 远处环境底噪（极轻的风声 / 嗡鸣）：让嘶叫与心跳之间的过渡自然，
    # 同时避免出现数字绝对静音段
    amb = apply_fir(rng.standard_normal(n), fir_bandpass(60.0, 400.0, 81))
    amb *= (0.55 + 0.45 * np.sin(2.0 * np.pi * 0.7 * t)) * np.exp(-t / 1.2)
    y += amb * 0.045
    return fade(np.tanh(y * 1.1) * 0.90, 4.0)


def sfx_evac(dur, rng):
    """撤离成功：明亮上行和弦。"""
    n = nsamp(dur)
    t = tt(n)
    y = np.zeros(n)
    for f, st in [(523.25, 0.00), (659.25, 0.06), (783.99, 0.12), (1046.50, 0.18), (1318.51, 0.24)]:
        s = int(st * SR)
        tl = tt(n - s)
        e = env_perc(tl, 0.012, 0.42, power=1.15)
        v = (np.sin(2.0 * np.pi * f * tl)
             + 0.32 * np.sin(4.0 * np.pi * f * tl)
             + 0.14 * np.sin(6.0 * np.pi * f * tl)
             + 0.06 * np.sin(8.0 * np.pi * f * tl))
        y[s:] += v * e * 0.80
    late = np.clip((t - 0.26) / 0.01, 0.0, 1.0)
    y += np.sin(2.0 * np.pi * 2093.0 * t) * np.exp(-np.maximum(t - 0.26, 0.0) / 0.30) * late * 0.35
    return fade(y, 5.0)


def sfx_defeat(dur, rng):
    """战败：下行的暗淡和弦。"""
    n = nsamp(dur)
    t = tt(n)
    y = np.zeros(n)
    for f, st in [(440.00, 0.00), (349.23, 0.10), (293.66, 0.20), (220.00, 0.30), (174.61, 0.40)]:
        s = int(st * SR)
        tl = tt(n - s)
        e = env_perc(tl, 0.030, 0.34, power=1.2)
        v = (np.sin(2.0 * np.pi * f * tl)
             + 0.70 * np.sin(2.0 * np.pi * f * 1.006 * tl)   # 失谐 → 不祥
             + 0.35 * np.sin(2.0 * np.pi * f * 0.5 * tl)
             + 0.12 * np.sin(4.0 * np.pi * f * tl))
        y[s:] += v * e * 0.55
    y = apply_fir(y, fir_lowpass(2600.0, 61))               # 变暗淡
    late = np.clip((t - 0.30) / 0.02, 0.0, 1.0)
    y += np.sin(2.0 * np.pi * 55.0 * t) * np.exp(-np.maximum(t - 0.30, 0.0) / 0.35) * late * 0.50
    return fade(y, 6.0)


SFX_BUILDERS = {
    "ui_click": sfx_ui_click,
    "ui_confirm": sfx_ui_confirm,
    "ui_deny": sfx_ui_deny,
    "hit": sfx_hit,
    "miss": sfx_miss,
    "crit": sfx_crit,
    "hurt": sfx_hurt,
    "die": sfx_die,
    "heal": sfx_heal,
    "skill": sfx_skill,
    "bloodline": sfx_bloodline,
    "dice": sfx_dice,
    "step": sfx_step,
    "door": sfx_door,
    "pickup": sfx_pickup,
    "clue": sfx_clue,
    "noise": sfx_noise,
    "evac": sfx_evac,
    "defeat": sfx_defeat,
}


# ===========================================================================
# BGM 合成
# ===========================================================================
def bgm_explore(dur, rng):
    """探索：阴冷、稀疏、低频嗡鸣 + 偶尔的金属碰响，音量克制。"""
    n = nsamp(dur)
    t = tt(n)
    g = Grid(n)
    y = np.zeros(n)
    # 低频嗡鸣（整数周期分音 + 整数周期 LFO）
    for f, a, ph in [(38.0, 0.90, 0.0), (57.0, 0.45, 0.7), (76.0, 0.28, 1.9), (114.0, 0.14, 2.6)]:
        lfo = 0.62 + 0.38 * np.sin(2.0 * np.pi * g.f(0.05) * t + ph)
        y += a * np.sin(2.0 * np.pi * g.f(f) * t + ph * 0.5) * lfo
    # A 小调暗色 pad
    for f, a, ph in [(110.0, 0.22, 0.0), (130.81, 0.16, 1.2), (164.81, 0.14, 2.4), (220.0, 0.09, 3.1)]:
        lfo = 0.50 + 0.50 * np.sin(2.0 * np.pi * g.f(0.05) * t + ph)
        y += a * np.sin(2.0 * np.pi * g.f(f) * t + ph) * lfo
    # 稀疏的金属碰响（全部内嵌，不跨循环缝）
    for tm in [0.80, 4.20, 7.10, 10.60, 13.30, 16.90]:
        s = int(tm * SR)
        ln = min(int(1.0 * SR), n - s)
        tl = tt(ln)
        base = float(rng.uniform(620.0, 1150.0))
        met = metal_click(tl, base, [1.0, 1.43, 1.92, 2.68, 3.35, 4.12], rng,
                          float(rng.uniform(0.10, 0.22)), float(rng.uniform(0.0, 6.28)))
        met *= event_env(tl, ln, 0.30, attack_ms=1.5, tail_ms=20.0)
        y[s:s + ln] += met * float(rng.uniform(0.055, 0.10))
    # 远处的高频"滴"
    for tm in [2.60, 9.40, 15.20]:
        s = int(tm * SR)
        ln = min(int(0.5 * SR), n - s)
        tl = tt(ln)
        f = g.f(float(rng.choice([1567.98, 2093.00, 2637.02])))
        d = np.sin(2.0 * np.pi * f * tl) * event_env(tl, ln, 0.09, attack_ms=4.0, tail_ms=15.0)
        y[s:s + ln] += d * 0.055
    y = circ_fir(y, fir_lowpass(6000.0, 61))
    return loop_fix(y)


def bgm_battle(dur, rng):
    """战斗：快节奏、紧张、脉冲低音与不和谐音程。"""
    n = nsamp(dur)
    t = tt(n)
    g = Grid(n)
    y = np.zeros(n)
    beats = 40                      # 18 s / 40 拍 ≈ 133 BPM，拍长恰为整数样本
    bl = n // beats
    # 不和谐持续层：A2 + Bb2（小二度）+ Eb3（三全音）
    for f, a, ph in [(110.0, 0.26, 0.0), (116.54, 0.20, 0.9), (155.56, 0.16, 2.1), (220.0, 0.10, 3.3)]:
        lfo = 0.55 + 0.45 * np.sin(2.0 * np.pi * g.f(0.1111) * t + ph)
        y += a * np.sin(2.0 * np.pi * g.f(f) * t + ph) * lfo
    # 脉冲低音（每拍一个，衰减在循环内结束）
    for i in range(beats):
        s = i * bl
        ln = min(int(0.32 * SR), n - s)
        tl = tt(ln)
        ph = 2.0 * np.pi * np.cumsum(72.0 * np.exp(-tl * 14.0) + 46.0) / SR
        b = np.sin(ph) * np.exp(-tl / 0.075) + 0.45 * np.sin(2.0 * ph) * np.exp(-tl / 0.040)
        y[s:s + ln] += b * event_env(tl, ln, 0.30, attack_ms=1.0, tail_ms=18.0) * 0.60
    # hihat（八分音符）
    for i in range(beats * 2):
        s = int(round(i * bl / 2.0))
        if s >= n:
            break
        ln = min(int(0.06 * SR), n - s)
        tl = tt(ln)
        hh = apply_fir(rng.standard_normal(ln), fir_highpass(6500.0, 41)) * np.exp(-tl / 0.008)
        hh *= np.minimum(tl / 0.0004, 1.0)
        y[s:s + ln] += hh * (0.20 if i % 2 == 0 else 0.13)
    # snare（每两拍的后半拍）
    for i in range(0, beats, 2):
        s = i * bl + bl // 2
        if s >= n:
            break
        ln = min(int(0.20 * SR), n - s)
        tl = tt(ln)
        sn = apply_fir(rng.standard_normal(ln), fir_bandpass(900.0, 5000.0, 61)) * np.exp(-tl / 0.045)
        sn += np.sin(2.0 * np.pi * 180.0 * tl) * np.exp(-tl / 0.05) * 0.5
        sn *= np.minimum(tl / 0.0006, 1.0)
        y[s:s + ln] += sn * 0.32
    # 高音紧张动机：三全音音型，失真锯齿
    motif = [440.0, 622.25, 523.25]
    for bar in range(0, beats, 2):
        for j in range(3):
            s = bar * bl + int(j * bl * 0.20)
            if s >= n:
                break
            ln = min(int(0.16 * SR), n - s)
            tl = tt(ln)
            f = motif[(bar // 2 + j) % 3]
            saw = 2.0 * (f * tl - np.floor(f * tl + 0.5))
            v = np.tanh(saw * 2.6) * 0.5 + np.sin(2.0 * np.pi * f * tl) * 0.4
            e = env_perc(tl, 0.004, 0.055)
            y[s:s + ln] += v * e * event_env(tl, ln, 0.09, attack_ms=1.5, tail_ms=15.0) * 0.18
    y = circ_fir(y, fir_lowpass(9500.0, 61))
    return loop_fix(y)


def bgm_hub(dur, rng):
    """主神空间：冷科幻、空灵、缓慢的正弦铺底 + 干净的高音点。"""
    n = nsamp(dur)
    t = tt(n)
    g = Grid(n)
    y = np.zeros(n)
    # Cmaj7#11 正弦铺底，各声部不同周期的整数周期 LFO
    chords = [(130.81, 0.26, 0.0, 5.0), (196.00, 0.20, 1.1, 4.0), (246.94, 0.17, 2.2, 3.0),
              (293.66, 0.13, 3.3, 2.5), (369.99, 0.09, 4.4, 2.0), (523.25, 0.06, 5.5, 1.6)]
    for f, a, ph, cyc in chords:
        lfo = 0.42 + 0.58 * (0.5 + 0.5 * np.sin(2.0 * np.pi * g.f(cyc / dur) * t + ph))
        v = (np.sin(2.0 * np.pi * g.f(f) * t + ph)
             + 0.45 * np.sin(2.0 * np.pi * g.f(f * 1.003) * t + ph * 1.7))
        y += a * v * lfo
    # 干净的高音点（每 2.75 s 一个，最后一个在 19.25 s，衰减在循环内结束）
    tones = [1567.98, 2093.00, 2637.02, 3135.96]
    for i in range(8):
        s = int(i * 2.75 * SR)
        ln = min(int(1.6 * SR), n - s)
        if ln <= 0:
            break
        tl = tt(ln)
        f = g.f(tones[i % 4])
        env = event_env(tl, ln, 0.42, attack_ms=6.0, tail_ms=25.0)
        bell = (np.sin(2.0 * np.pi * f * tl)
                + 0.32 * np.sin(2.0 * np.pi * f * 2.01 * tl)
                + 0.14 * np.sin(2.0 * np.pi * f * 3.03 * tl))
        y[s:s + ln] += bell * env * 0.15
    # 极轻的高频 shimmer（用整数周期正弦簇代替噪声，保证循环无缝）
    for i, (f, a, ph) in enumerate([(5230.0, 0.030, 0.3), (6180.0, 0.024, 1.4),
                                    (7410.0, 0.020, 2.5), (8290.0, 0.016, 3.6)]):
        lfo = 0.5 + 0.5 * np.sin(2.0 * np.pi * g.f((2.0 + i) / dur) * t + ph)
        y += a * np.sin(2.0 * np.pi * g.f(f) * t + ph) * lfo
    y = circ_fir(y, fir_lowpass(9500.0, 61))
    return loop_fix(y)


BGM_BUILDERS = {
    "explore": bgm_explore,
    "battle": bgm_battle,
    "hub": bgm_hub,
}


# ===========================================================================
# 写盘
# ===========================================================================
def to_int16(x):
    q = np.round(np.clip(x, -1.0, 1.0) * 32767.0)
    return np.clip(q, -32767.0, 32767.0).astype("<i2")


def write_wav(path, x):
    q = to_int16(x)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(q.tobytes())
    return q


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


# ===========================================================================
# 自检
# ===========================================================================
def analyze(path):
    with wave.open(path, "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        fr = w.getframerate()
        nf = w.getnframes()
        raw = w.readframes(nf)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    rms = float(np.sqrt(np.mean(x * x))) if len(x) else 0.0
    info = {
        "path": path,
        "name": os.path.basename(path),
        "channels": nch,
        "sampwidth": sw,
        "rate": fr,
        "frames": nf,
        "dur": nf / float(fr),
        "peak_i": peak,
        "peak_db": lin_to_db(peak / 32767.0) if peak > 0 else -999.0,
        "rms_db": lin_to_db(rms / 32767.0) if rms > 0 else -999.0,
        "clipped": bool(np.any(np.abs(x) >= 32767.0)),
        "dc": float(np.mean(x)) / 32767.0,
        "std": float(np.std(x)) / 32767.0,
        "first": int(x[0]) if len(x) else 0,
        "last": int(x[-1]) if len(x) else 0,
        "size": os.path.getsize(path),
    }
    return info


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(BGM_DIR, exist_ok=True)

    print("=" * 78)
    print("程序化音频生成 —— 无限流 CRPG《惊变公寓》")
    print("输出根目录：%s" % ROOT)
    print("=" * 78)

    written = []
    pending = []          # 先全部合成到内存，最后一次写盘：任一步失败都不会留下半新半旧的文件
    for i, (name, dur) in enumerate(SFX_SPECS):
        rng = np.random.default_rng(0x5F00 + i * 977)     # 固定种子 → 幂等
        x = SFX_BUILDERS[name](dur, rng)
        x = normalize_peak(x, SFX_PEAK_DBFS)
        pending.append((os.path.join(SFX_DIR, name + ".wav"), x, "sfx", name))

    # BGM 不在这里生成：它由 tools/music/render_bgm.mjs 用 FluidSynth 渲染。
    # 只做存在性提示，免得有人以为本脚本还能产出整套资产。
    for name in BGM_NAMES:
        if not os.path.exists(os.path.join(BGM_DIR, name + ".wav")):
            print("  [提示] bgm/%s.wav 不存在，请运行：node tools/music/render_bgm.mjs" % name)

    for path, x, kind, name in pending:
        write_wav(path, x)
        written.append(path)
        print("  [%s] %-16s %.3f s" % (kind, name + ".wav", len(x) / SR))

    # ---------------- 自检 ----------------
    print()
    print("=" * 78)
    print("自检报告")
    print("=" * 78)
    hdr = "%-18s %-6s %9s %11s %11s %8s %10s" % ("文件名", "类型", "时长(s)", "峰值(dBFS)", "RMS(dBFS)", "削波", "大小(KB)")
    print(hdr)
    print("-" * 78)

    sfx_infos, bgm_infos = [], []
    for p in written:
        info = analyze(p)
        is_bgm = os.path.basename(os.path.dirname(p)) == "bgm"
        info["kind"] = "bgm" if is_bgm else "sfx"
        (bgm_infos if is_bgm else sfx_infos).append(info)
        print("%-18s %-6s %9.3f %11.2f %11.2f %8s %10.1f" % (
            info["name"], info["kind"], info["dur"], info["peak_db"], info["rms_db"],
            "是!!" if info["clipped"] else "否", info["size"] / 1024.0))

    total = sum(i["size"] for i in sfx_infos + bgm_infos)
    print("-" * 78)
    print("assets/audio 目录总大小：%.2f MB（%d 字节）—— 上限 12 MB"
          % (total / 1048576.0, total))

    print()
    print("BGM：已迁到 tools/music/render_bgm.mjs；无缝循环检验见 tools/audio/verify_audio.py")

    # 断言
    print()
    print("断言：")
    errors = []

    for info in sfx_infos:
        if not (0.08 <= info["dur"] <= 1.00):
            errors.append("%s 时长 %.3f s 越界（要求 0.08~1.00）" % (info["name"], info["dur"]))
        if abs(info["peak_db"] - SFX_PEAK_DBFS) > 2.0:
            errors.append("%s 峰值 %.2f dBFS 偏离目标 %.1f 超过 ±2 dB" % (info["name"], info["peak_db"], SFX_PEAK_DBFS))
    # BGM 由 render_bgm.mjs 生成，本脚本不再校验它（交给 tools/audio/verify_audio.py）。

    for info in sfx_infos + bgm_infos:
        if info["channels"] != 1 or info["sampwidth"] != 2 or info["rate"] != SR:
            errors.append("%s 格式不是 单声道/16-bit/%d Hz" % (info["name"], SR))
        if info["std"] < 1e-4:
            errors.append("%s 疑似静音（std=%.3e）" % (info["name"], info["std"]))
        if abs(info["dc"]) > 0.01:
            errors.append("%s 存在直流偏置（dc=%.4f）" % (info["name"], info["dc"]))
        if info["clipped"]:
            errors.append("%s 出现削波（样本达到 ±32767）" % info["name"])
        if info["peak_i"] < 0.01 * 32767.0:
            errors.append("%s 峰值过低，疑似静音" % info["name"])

    if total > 12 * 1024 * 1024:
        errors.append("总大小 %.2f MB 超过 12 MB" % (total / 1048576.0))

    if errors:
        print("  ✗ 未通过：")
        for e in errors:
            print("    - " + e)
        print("=" * 78)
        return 1

    print("  ✓ sfx 数量 %d 个，时长全部落在 0.08~1.00 s" % len(sfx_infos))
    print("  ✓ 峰值全部在目标 ±2 dB 内（sfx %.1f dBFS）" % SFX_PEAK_DBFS)
    print("  ✓ 无静音、无直流、无削波")
    print("  ✓ BGM 不在本脚本职责内：见 tools/music/render_bgm.mjs")
    print("  ✓ 总大小 %.2f MB ≤ 12 MB" % (total / 1048576.0))
    print("=" * 78)
    print("全部自检通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
