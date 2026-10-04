#!/usr/bin/env node
/**
 * 生成 assets/audio/bgm/ 下的三首 BGM：explore / battle / hub。
 *
 * ── 为什么用 FluidSynth 而不是继续纯数学合成 ──
 * 原管线（tools/audio/gen_audio.py）用正弦/噪声合成，BGM 是"暗色 pad + 低频嗡鸣"。
 * 本次改用 dsh-midi-studio 的 FluidSynth（GeneralUserGS 音源）渲染真实乐器：
 * 低音弦乐、定音鼓、钟琴、合唱 pad —— 这些音色是恐怖片配乐的语汇本身。
 *
 * ── 为什么不走 DSH 插件机制 ──
 * 那个插件声明 peerDependencies @deepseek-ai/dsh-tools ^0.1.0-rc.6，
 * 与本机 dsh 0.2.0-rc.2 不匹配，安装被版本守卫拒绝。但它的引擎在 lib/lib/*.js，
 * 只依赖 js-synthesizer 与 lamejs，不 import 任何 DSH API，
 * 所以这里直接当普通 JS 库调，不装插件、不动 profile、零兼容风险。
 *
 * ── 输出规格（与 assets/audio/README.md、tools/audio/verify_audio.py 对齐）──
 *   22050 Hz / 单声道 / 16-bit PCM / 峰值 -8 dBFS / 16~24 s / 无缝循环
 *
 * ── 无缝循环的做法 ──
 *   1. 渲染「主体 + 尾巴」（尾巴 2.5s 用来收混响与延音）
 *   2. 把尾巴交叉淡化叠回开头：循环回来时听到的是上一轮的延音，而不是硬切
 *   3. 末段微对齐：把 |x[0] - x[-1]| 压到 1 LSB 量级（修正量 < 1e-3，不可闻）
 *   4. 峰值归一到 -8 dBFS
 *
 * ── 基调（依据 docs/剧情大纲_惊变公寓.md）──
 *   类型：密室求生 · 丧尸 · 限时撤离；情绪曲线 惊慌 → 稳住 → 绝境 → 拼命
 *   核心："真正的敌人不是丧尸，是退路"；"主神是冷的，不出面、不解释、不安慰"
 *
 *   explore  屏息与留白（《寂静之地》）：低频嗡鸣不断，pad 走小二度，金属碰响偶发
 *   battle   机械紧迫、无旋律（《28 天后》）：八分音符低音 ostinato + 定音鼓 + 三全音刺入
 *   hub      非人的冷（主神空间）：空五度合唱 pad + 稀疏钟琴，刻意不用弦乐（弦乐有人味）
 *
 * 用法：
 *   node tools/music/render_bgm.mjs              # 全部
 *   node tools/music/render_bgm.mjs battle       # 单首
 *   node tools/music/render_bgm.mjs --list       # 列曲目
 * 环境变量：
 *   MIDI_STUDIO_LIB       dsh-midi-studio 的 lib/lib 目录
 *   DSH_MUSIC_SOUNDFONT   GeneralUserGS.sf3 路径
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
const OUT_DIR = path.join(PROJECT, 'assets', 'audio', 'bgm');

const LIB = process.env.MIDI_STUDIO_LIB
  ?? path.join(os.homedir(), '.dsh', 'plugins', 'dsh-midi-studio', 'lib', 'lib');
const SOUNDFONT = process.env.DSH_MUSIC_SOUNDFONT
  ?? path.join(os.homedir(), '.dsh-music-studio', 'soundfonts', 'GeneralUserGS.sf3');

const SR_OUT = 22050;          // 项目规格
const PEAK_DBFS = -8.0;        // 项目规格（BGM 明显轻于音效）
const TAIL_SEC = 2.5;          // 渲染时多留的尾巴，供交叉淡化消化混响

// ─────────────────────── GM 音色号 ───────────────────────
const GM = {
  piano: 0, celesta: 8, glockenspiel: 9, tubular: 14,
  organ: 19, timpani: 47, strings: 48, strings_slow: 49,
  choir: 52, contrabass: 43, cello: 42, trumpet: 56,
  pad_warm: 89, pad_halo: 94,
};

// ─────────────────────── 三首曲目 ───────────────────────
// 音符一律用「拍」；pitch 是 MIDI 音高（60 = 中央 C）。
// 每首的长度都取整数小节，这样循环点落在乐句边界上（不是随机切断）。

const TRACKS = {

  // ── 探索：屏息。低频不断，但什么都不发生 —— 恐怖来自"还没有发生的事"。
  explore: {
    title: '惊变公寓 · 探索',
    bpm: 60, bars: 5, tailSec: TAIL_SEC,
    note: '低音弦乐长音 + A/Bb 小二度 pad + 偶发金属与钢琴单音',
    build() {
      // 低音：整曲不断（verify 要求不能有 >0.05s 的真空段）
      const drone = [
        { beat: 0, dur: 8, pitch: 38, velocity: 46 },     // D2
        { beat: 8, dur: 8, pitch: 36, velocity: 42 },     // C2
        { beat: 16, dur: 4, pitch: 38, velocity: 46 },    // D2
      ];
      // 小二度 pad：A3 + Bb3 贴在一起，持续的不安
      const pad = [];
      for (let i = 0; i < 2; i++) {
        pad.push({ beat: i * 10, dur: 10, pitch: 57, velocity: 30 });
        pad.push({ beat: i * 10, dur: 10, pitch: 58, velocity: 27 });
      }
      // 金属碰响：像楼里某处的管道，三全音落地
      const bells = [
        { beat: 3, dur: 2.5, pitch: 73, velocity: 40 },
        { beat: 13, dur: 2.5, pitch: 74, velocity: 33 },
      ];
      // 钢琴单音：极稀疏，像楼上有人碰了一下琴键
      const piano = [
        { beat: 5, dur: 1, pitch: 81, velocity: 24 },
        { beat: 15, dur: 1, pitch: 79, velocity: 20 },
      ];
      return [
        { name: '低音弦乐', program: GM.contrabass, notes: drone },
        { name: '暗色 pad', program: GM.strings, notes: pad },
        { name: '金属', program: GM.tubular, notes: bells },
        { name: '钢琴', program: GM.piano, notes: piano },
      ];
    },
  },

  // ── 战斗：机械、紧迫、无旋律。参考《28 天后》的推进感。
  battle: {
    title: '惊变公寓 · 战斗',
    bpm: 150, bars: 12, tailSec: TAIL_SEC,
    note: '八分低音 ostinato + 小二度/三全音 pad + 定音鼓 + 鼓组 + 铜管刺入',
    build() {
      // 八分音符低音 ostinato：C2 / Bb1 交替（不给人喘息的推进）
      const bass = [];
      for (let i = 0; i < 48; i++) {
        bass.push({ beat: i, dur: 0.9, pitch: i % 8 < 4 ? 36 : 34, velocity: 84 });
      }
      // 不谐和 pad：A2 + Bb2 小二度，叠 Eb3 三全音（沿用原设计的恐怖语汇）
      const pad = [];
      for (let i = 0; i < 6; i++) {
        pad.push({ beat: i * 8, dur: 8, pitch: 45, velocity: 50 });
        pad.push({ beat: i * 8, dur: 8, pitch: 46, velocity: 46 });
        pad.push({ beat: i * 8, dur: 8, pitch: 51, velocity: 42 });
      }
      // 定音鼓：每小节一记，像有人在楼上走
      const timp = [];
      for (let i = 0; i < 12; i++) timp.push({ beat: i * 4, dur: 1.5, pitch: 41, velocity: 94 });
      // 鼓组：kick 每拍 + hihat 八分 + snare 反拍
      const drum = [];
      for (let i = 0; i < 48; i++) {
        drum.push({ beat: i, dur: 0.4, pitch: 36, velocity: 94 });
        drum.push({ beat: i, dur: 0.25, pitch: 42, velocity: 48 });
        if (i % 4 === 2) drum.push({ beat: i, dur: 0.4, pitch: 38, velocity: 86 });
      }
      // 铜管刺入：三全音，每 4 小节一次（"这东西来了"）
      const stab = [];
      for (let i = 0; i < 3; i++) stab.push({ beat: i * 16 + 6, dur: 2, pitch: 63, velocity: 70 });
      // 弦乐急促：小二度来回，制造摩擦
      const strings = [];
      for (let i = 0; i < 24; i++) {
        strings.push({ beat: i * 2, dur: 1, pitch: 57, velocity: 54 });
        strings.push({ beat: i * 2 + 1, dur: 1, pitch: 58, velocity: 50 });
      }
      return [
        { name: '低音', program: GM.contrabass, notes: bass },
        { name: '不谐和 pad', program: GM.strings, notes: pad },
        { name: '弦乐', program: GM.cello, notes: strings },
        { name: '定音鼓', program: GM.timpani, notes: timp },
        { name: '铜管', program: GM.trumpet, notes: stab },
        { name: '鼓', is_drum: true, notes: drum },
      ];
    },
  },

  // ── 主神空间：非人的冷。刻意不用弦乐 —— 弦乐有人味，这里不该有。
  hub: {
    title: '主神空间',
    bpm: 48, bars: 4, tailSec: TAIL_SEC,
    note: '空五度合唱 pad + 合成器铺底 + 稀疏钟琴与高频金属；无节奏、无旋律',
    build() {
      // 空五度：C3 + G3（没有三音 = 没有大调小调 = 没有情绪）
      const choir = [];
      for (let i = 0; i < 2; i++) {
        choir.push({ beat: i * 8, dur: 8, pitch: 48, velocity: 38 });
        choir.push({ beat: i * 8, dur: 8, pitch: 55, velocity: 34 });
      }
      // 合成器铺底：比合唱更"非人"，托住整首
      const pad = [
        { beat: 0, dur: 16, pitch: 60, velocity: 28 },
        { beat: 0, dur: 16, pitch: 67, velocity: 24 },
      ];
      // 钟琴：稀疏的高音点，像结算界面在闪
      const bells = [
        { beat: 1, dur: 2, pitch: 84, velocity: 50 },      // C6
        { beat: 6, dur: 2, pitch: 91, velocity: 42 },      // G6
        { beat: 9, dur: 2, pitch: 86, velocity: 46 },      // D6
        { beat: 13, dur: 2, pitch: 96, velocity: 38 },     // C7
      ];
      // 高频金属：极轻的上层 shimmer
      const shimmer = [
        { beat: 4, dur: 3, pitch: 79, velocity: 26 },
        { beat: 12, dur: 3, pitch: 83, velocity: 22 },
      ];
      return [
        { name: '合唱 pad', program: GM.choir, notes: choir },
        { name: '合成 pad', program: GM.pad_warm, notes: pad },
        { name: '钟琴', program: GM.glockenspiel, notes: bells },
        { name: '金属', program: GM.tubular, notes: shimmer },
      ];
    },
  },
};

// ─────────────────────── 音频处理 ───────────────────────

/** 立体声 44100 → 单声道 22050（下混 + 线性插值重采样） */
function toMono(samples, srcSR) {
  const [L, R] = samples;
  const n = Math.floor(L.length * SR_OUT / srcSR);
  const out = new Float32Array(n);
  const ratio = srcSR / SR_OUT;
  for (let i = 0; i < n; i++) {
    const pos = i * ratio;
    const i0 = Math.floor(pos);
    const i1 = Math.min(i0 + 1, L.length - 1);
    const t = pos - i0;
    const l = L[i0] * (1 - t) + L[i1] * t;
    const r = R[i0] * (1 - t) + R[i1] * t;
    out[i] = (l + r) * 0.5;
  }
  return out;
}

/**
 * 把「主体 + 尾巴」变成无缝循环：返回长度恰为主体帧数的数组。
 * 尾巴（混响/延音）交叉淡化叠回开头 —— 循环回来时听到的是上一轮的余响，
 * 而不是被硬切掉的静音。
 */
function crossfadeLoop(mono, bodyFrames, tailFrames) {
  const n = bodyFrames;                          // 循环长度 = 主体帧数（精确，不用渲染总长推）
  const out = new Float32Array(n);
  out.set(mono.subarray(0, n));
  const tail = Math.min(tailFrames, mono.length - n);
  for (let i = 0; i < tail; i++) {
    const w = i / tail;                          // 0 → 1：开头以尾巴为主
    out[i] = out[i] * w + mono[n + i] * (1 - w);
  }
  return out;
}

/**
 * 末段微对齐：把 |x[0] - x[-1]| 压到 1 LSB 量级。
 * 用一段长斜坡（默认 2048 帧 ≈ 93ms）分散修正量，避免在循环点制造曲率突变。
 */
function microAlignLoop(x, rampFrames = 2048) {
  const n = x.length;
  const want = x[0] - x[n - 1];
  if (Math.abs(want) < 1 / 65536) return x;
  const m = Math.min(rampFrames, Math.floor(n / 8));
  for (let i = 0; i < m; i++) {
    const w = (i + 1) / m;                       // 末点权重 1
    x[n - m + i] += want * w * w;                // 平方权重：更平滑地收束
  }
  return x;
}

/** 峰值归一到目标 dBFS；不做限幅（若有削波风险则整体缩） */
function normalizePeakDb(x, dbfs) {
  let pk = 0;
  for (let i = 0; i < x.length; i++) {
    const a = Math.abs(x[i]);
    if (a > pk) pk = a;
  }
  if (pk < 1e-9) return { peak: pk, gain: 1 };
  const target = Math.pow(10, dbfs / 20);
  const k = target / pk;
  for (let i = 0; i < x.length; i++) x[i] *= k;
  return { peak: pk, gain: k };
}

/** 写 16-bit 单声道 WAV */
function writeWav16Mono(filePath, x, sr) {
  const dataBytes = x.length * 2;
  const buf = Buffer.alloc(44 + dataBytes);
  buf.write('RIFF', 0, 'ascii');
  buf.writeUInt32LE(36 + dataBytes, 4);
  buf.write('WAVE', 8, 'ascii');
  buf.write('fmt ', 12, 'ascii');
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);                      // 单声道
  buf.writeUInt32LE(sr, 24);
  buf.writeUInt32LE(sr * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36, 'ascii');
  buf.writeUInt32LE(dataBytes, 40);
  let off = 44;
  for (let i = 0; i < x.length; i++) {
    const v = Math.max(-1, Math.min(1, x[i]));
    buf.writeInt16LE(Math.round(v * 32767), off);
    off += 2;
  }
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, buf);
  return buf.length;
}

// ─────────────────────── 主流程 ───────────────────────

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--list')) {
    for (const [k, v] of Object.entries(TRACKS)) {
      const sec = (v.bars * 4 * 60 / v.bpm).toFixed(1);
      console.log(`  ${k.padEnd(9)} ${sec}s  ${String(v.bpm).padStart(3)} BPM  ${v.title}\n            ${v.note}`);
    }
    return;
  }
  const wanted = args.filter((a) => !a.startsWith('--'));
  const names = wanted.length ? wanted : Object.keys(TRACKS);
  for (const n of names) {
    if (!TRACKS[n]) { console.error(`✗ 没有名为 ${n} 的曲目（--list 看全部）`); process.exitCode = 1; return; }
  }
  if (!fs.existsSync(LIB)) { console.error(`✗ 找不到引擎目录：${LIB}\n  设 MIDI_STUDIO_LIB 指向 dsh-midi-studio/lib/lib`); process.exit(1); }
  if (!fs.existsSync(SOUNDFONT)) { console.error(`✗ 找不到音色库：${SOUNDFONT}\n  设 DSH_MUSIC_SOUNDFONT 指向 GeneralUserGS.sf3`); process.exit(1); }

  const load = (f) => import(pathToFileURL(path.join(LIB, f)).href);
  const { composeMidiBuffer } = await load('compose.js');
  const { renderMidi, disposeSynth, SAMPLE_RATE } = await load('render.js');

  const tmpDir = path.join(os.tmpdir(), 'loop_bgm');
  fs.mkdirSync(tmpDir, { recursive: true });

  for (const name of names) {
    const cfg = TRACKS[name];
    const tracks = cfg.build();
    const bodySec = cfg.bars * 4 * 60 / cfg.bpm;        // 主体时长（整数小节）
    const renderSec = bodySec + (cfg.tailSec ?? TAIL_SEC);

    // 用一段静音把渲染长度撑到 renderSec：在末尾补一个不发声的占位音符不现实，
    // 改为直接按需要的时长渲染 —— renderMidi 会渲染到 MIDI 结束 + tailSeconds，
    // 所以这里靠 tailSeconds 多渲染出混响尾巴。
    // 让每轨的最后一个音越过循环点：交叉淡化得有"尾巴"可叠，
    // 否则持续音正好在循环点结束 → 末尾是静音 → verify 判「连续静音段超标」。
    for (const t of tracks) {
      const notes = t.notes ?? [];
      if (notes.length) notes[notes.length - 1].dur += 8;
    }
    const midBuf = composeMidiBuffer({ bpm: cfg.bpm, title: cfg.title, tracks });
    const midPath = path.join(tmpDir, `${name}.mid`);
    fs.writeFileSync(midPath, midBuf);

    const res = await renderMidi({
      midiPath: midPath,
      soundfontPath: SOUNDFONT,
      gain: 1.2,
      tailSeconds: cfg.tailSec ?? TAIL_SEC,
      trim: false,                                     // 不能裁：裁掉尾巴就没法交叉淡化
    });

    const mono = toMono(res.samples, res.sampleRate ?? SAMPLE_RATE);
    const bodyFrames = Math.round(bodySec * SR_OUT);   // 循环长度
    const tailFrames = Math.min(mono.length - bodyFrames, Math.round((cfg.tailSec ?? TAIL_SEC) * SR_OUT));
    if (tailFrames <= 0) {
      console.error(`✗ ${name}: 渲染长度不足（${mono.length} 帧 ≤ 主体 ${bodyFrames} 帧）`);
      process.exitCode = 1;
      continue;
    }
    let loop = crossfadeLoop(mono, bodyFrames, tailFrames);
    loop = microAlignLoop(loop);
    const { peak, gain } = normalizePeakDb(loop, PEAK_DBFS);

    const outPath = path.join(OUT_DIR, `${name}.wav`);
    const bytes = writeWav16Mono(outPath, loop, SR_OUT);

    // 自检
    const seam = Math.abs(loop[0] - loop[loop.length - 1]) * 32767;
    let pk = 0; let sum = 0;
    for (let i = 0; i < loop.length; i++) { const a = Math.abs(loop[i]); if (a > pk) pk = a; sum += loop[i] * loop[i]; }
    const rms = Math.sqrt(sum / loop.length);
    const pkdb = 20 * Math.log10(Math.max(pk, 1e-9));
    const rmsdb = 20 * Math.log10(Math.max(rms, 1e-9));
    const noteCount = tracks.reduce((a, t) => a + t.notes.length, 0);

    console.log(
      `✓ ${name.padEnd(9)} ${tracks.length} 轨 / ${String(noteCount).padStart(3)} 音 ｜ `
      + `${(loop.length / SR_OUT).toFixed(2)}s ｜ 峰值 ${pkdb.toFixed(2)} dBFS ／ RMS ${rmsdb.toFixed(2)} ｜ `
      + `首尾差 ${seam.toFixed(2)} ｜ 增益 ×${gain.toFixed(2)} ｜ 渲染 ${res.renderMs}ms ｜ `
      + `${(bytes / 1024).toFixed(0)} KB`,
    );
  }
  disposeSynth();
}

await main();
