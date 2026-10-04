#!/usr/bin/env node
/**
 * 用 dsh-midi-studio 的渲染引擎（FluidSynth 2.4.6 WASM）生成 BGM。
 *
 * 为什么不走 DSH 插件机制：
 *   那个插件声明 peerDependencies 是 @deepseek-ai/dsh-tools ^0.1.0-rc.6，
 *   与本机 dsh 0.2.0-rc.2 不匹配，安装被版本守卫拒绝（可能崩溃/丢数据）。
 *   但它真正的引擎在 lib/lib/*.js —— 那些模块只依赖 js-synthesizer 与 lamejs，
 *   不 import 任何 DSH API。所以这里直接当普通 JS 库调，绕开插件与版本问题。
 *
 * 前置：
 *   1. dsh-midi-studio 的仓库（含 node_modules）已就位
 *      —— 默认 ~/.dsh/plugins/dsh-midi-studio，可用 MIDI_STUDIO_LIB 覆盖
 *   2. 音色库 GeneralUserGS.sf3 已下载
 *      —— 默认 ~/.dsh-music-studio/soundfonts/，可用 DSH_MUSIC_SOUNDFONT 覆盖
 *
 * 用法：
 *   node tools/music/render_bgm.mjs              # 生成全部曲目
 *   node tools/music/render_bgm.mjs chase        # 只生成指定曲目
 *   node tools/music/render_bgm.mjs --list       # 列出曲目
 *
 * 输出：assets/audio/<曲目>.wav（44100Hz 立体声 16-bit）
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
const OUT_DIR = path.join(PROJECT, 'assets', 'audio');

const LIB = process.env.MIDI_STUDIO_LIB
  ?? path.join(os.homedir(), '.dsh', 'plugins', 'dsh-midi-studio', 'lib', 'lib');
const SOUNDFONT = process.env.DSH_MUSIC_SOUNDFONT
  ?? path.join(os.homedir(), '.dsh-music-studio', 'soundfonts', 'GeneralUserGS.sf3');

// ─────────────────────────── 曲目（惊变公寓） ───────────────────────────
// 音符一律用「拍」表示（四分音符 = 1 拍）；pitch 是 MIDI 音高（60 = 中央 C）。
// 鼓轨用 is_drum（自动落在通道 9），36 = 底鼓、38 = 军鼓、42 = 闭镲。

const gm = { piano: 0, music_box: 10, string_ens: 48, timpani: 47, choir: 52, contrabass: 43 };

/** 在给定拍位铺一段低音线，返回音符数组 */
function bassLine(pattern, step, dur, velocity) {
  return pattern.map((pitch, i) => ({ beat: i * step, dur, pitch, velocity }));
}

const TRACKS = {
  // 主厅：极慢、压抑。低音弦乐铺底，钢琴稀疏点缀，偶发闷鼓。
  apartment_hall: {
    title: '惊变公寓 · 主厅',
    bpm: 68,
    build() {
      const bass = [];
      for (let i = 0; i < 8; i++) {
        const pitch = [45, 45, 43, 41][i % 4];        // A2 A2 G2 F2
        bass.push({ beat: i * 4, dur: 4, pitch, velocity: 56 });
        bass.push({ beat: i * 4 + 2, dur: 2, pitch: pitch + 7, velocity: 42 });
      }
      const piano = [];
      const motif = [76, 79, 81, 79];                  // E5 G5 A5 G5
      for (let i = 0; i < 8; i++) {
        piano.push({ beat: i * 4 + 1, dur: 1.5, pitch: motif[i % 4], velocity: 40 });
        if (i % 2 === 1) {
          piano.push({ beat: i * 4 + 3, dur: 1, pitch: motif[(i + 2) % 4] - 12, velocity: 32 });
        }
      }
      const drum = [];
      for (let i = 0; i < 8; i++) {
        drum.push({ beat: i * 4, dur: 0.5, pitch: 36, velocity: 64 });
        if (i % 4 === 3) drum.push({ beat: i * 4 + 3.5, dur: 0.5, pitch: 38, velocity: 46 });
      }
      return [
        { name: '低音弦乐', program: gm.contrabass, notes: bass },
        { name: '钢琴', program: gm.piano, notes: piano },
        { name: '鼓', is_drum: true, notes: drum },
      ];
    },
  },

  // 追逐：快一倍，鼓点密集，弦乐震音推进，旋律用音乐盒制造失真感。
  chase: {
    title: '惊变公寓 · 追逐',
    bpm: 132,
    build() {
      const bass = [];
      for (let i = 0; i < 32; i++) {
        bass.push({ beat: i * 0.5, dur: 0.5, pitch: [40, 40, 43, 45][i % 4], velocity: 72 });
      }
      const strings = [];
      for (let i = 0; i < 16; i++) {
        strings.push({ beat: i * 1, dur: 1, pitch: [57, 57, 60, 57][i % 4], velocity: 58 });
        strings.push({ beat: i * 1, dur: 1, pitch: [64, 64, 67, 64][i % 4], velocity: 52 });
      }
      const box = [];
      for (let i = 0; i < 16; i++) {
        box.push({ beat: i * 2 + 0.5, dur: 0.5, pitch: [88, 87, 85, 84][i % 4], velocity: 48 });
        if (i % 4 === 2) box.push({ beat: i * 2 + 1.5, dur: 0.25, pitch: 91, velocity: 44 });
      }
      const drum = [];
      for (let i = 0; i < 32; i++) {
        drum.push({ beat: i * 0.5, dur: 0.25, pitch: i % 2 === 0 ? 36 : 42, velocity: i % 2 === 0 ? 92 : 44 });
        if (i % 4 === 2) drum.push({ beat: i * 0.5, dur: 0.25, pitch: 38, velocity: 84 });
      }
      return [
        { name: '低音', program: gm.contrabass, notes: bass },
        { name: '弦乐', program: gm.string_ens, notes: strings },
        { name: '音乐盒', program: gm.music_box, notes: box },
        { name: '鼓', is_drum: true, notes: drum },
      ];
    },
  },
};

// ─────────────────────────── WAV 写出（16-bit 立体声） ───────────────────────────

function writeWav16(filePath, samples, sampleRate) {
  const [L, R] = samples;
  const frames = L.length;
  const dataBytes = frames * 2 * 2;                 // 2 声道 × 16 bit
  const buf = Buffer.alloc(44 + dataBytes);
  buf.write('RIFF', 0, 'ascii');
  buf.writeUInt32LE(36 + dataBytes, 4);
  buf.write('WAVE', 8, 'ascii');
  buf.write('fmt ', 12, 'ascii');
  buf.writeUInt32LE(16, 16);                        // fmt 块长度
  buf.writeUInt16LE(1, 20);                         // PCM
  buf.writeUInt16LE(2, 22);                         // 声道数
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * 2 * 2, 28);        // 字节率
  buf.writeUInt16LE(4, 32);                         // 块对齐
  buf.writeUInt16LE(16, 34);                        // 位深
  buf.write('data', 36, 'ascii');
  buf.writeUInt32LE(dataBytes, 40);
  let off = 44;
  const clamp = (v) => Math.max(-1, Math.min(1, v));
  for (let i = 0; i < frames; i++) {
    buf.writeInt16LE(Math.round(clamp(L[i]) * 32767), off); off += 2;
    buf.writeInt16LE(Math.round(clamp(R[i]) * 32767), off); off += 2;
  }
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, buf);
  return buf.length;
}

// ─────────────────────────── 主流程 ───────────────────────────

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--list')) {
    for (const [k, v] of Object.entries(TRACKS)) console.log(`  ${k.padEnd(18)} ${v.title}  ${v.bpm} BPM`);
    return;
  }
  const wanted = args.filter((a) => !a.startsWith('--'));
  const names = wanted.length ? wanted : Object.keys(TRACKS);
  for (const n of names) {
    if (!TRACKS[n]) {
      console.error(`✗ 没有名为 ${n} 的曲目（用 --list 看全部）`);
      process.exitCode = 1;
      return;
    }
  }

  if (!fs.existsSync(LIB)) { console.error(`✗ 找不到引擎目录：${LIB}\n  设 MIDI_STUDIO_LIB 指向 dsh-midi-studio/lib/lib`); process.exit(1); }
  if (!fs.existsSync(SOUNDFONT)) { console.error(`✗ 找不到音色库：${SOUNDFONT}\n  设 DSH_MUSIC_SOUNDFONT 指向 GeneralUserGS.sf3`); process.exit(1); }

  const load = (f) => import(pathToFileURL(path.join(LIB, f)).href);
  const { composeMidiBuffer } = await load('compose.js');
  const { renderMidi, disposeSynth } = await load('render.js');

  const tmpDir = path.join(os.tmpdir(), 'loop_bgm');
  fs.mkdirSync(tmpDir, { recursive: true });

  for (const name of names) {
    const cfg = TRACKS[name];
    const tracks = cfg.build();
    const midBuf = composeMidiBuffer({ bpm: cfg.bpm, title: cfg.title, tracks });
    const midPath = path.join(tmpDir, `${name}.mid`);
    fs.writeFileSync(midPath, midBuf);

    const res = await renderMidi({
      midiPath: midPath,
      soundfontPath: SOUNDFONT,
      gain: 1.2,
      tailSeconds: 2.5,
      trim: true,
    });

    // 峰值归一到 -1 dB 左右。FluidSynth 出来的原始电平很低（实测主厅峰值只有 0.08），
    // 不归一化的话塞进游戏里几乎听不见。
    const rawPeak = res.peak;
    const [left, right] = res.samples;
    const target = 0.89;
    if (rawPeak > 0.0001) {
      const k = target / rawPeak;
      for (let i = 0; i < left.length; i++) {
        left[i] *= k;
        right[i] *= k;
      }
    }
    const outPath = path.join(OUT_DIR, `${name}.wav`);
    const bytes = writeWav16(outPath, res.samples, res.sampleRate);

    const noteCount = tracks.reduce((a, t) => a + t.notes.length, 0);
    console.log(
      `✓ ${name.padEnd(18)} ${tracks.length} 轨 / ${noteCount} 音 ｜ `
      + `${res.durationSec.toFixed(1)}s ｜ 峰值 ${rawPeak.toFixed(3)} → 归一 ${target} ｜ `
      + `渲染 ${res.renderMs}ms ｜ ${(bytes / 1024 / 1024).toFixed(2)} MB → ${path.relative(PROJECT, outPath)}`,
    );
  }
  disposeSynth();
}

await main();
