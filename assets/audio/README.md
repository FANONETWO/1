# `assets/audio` —— 程序化合成音频资产

> 本目录下**全部 22 个 WAV 文件**分两条管线生成：
>
> | 资产 | 生成器 | 版权 |
> |---|---|---|
> | 19 个音效 `sfx/*.wav` | [`tools/audio/gen_audio.py`](../../tools/audio/gen_audio.py) 纯数学合成 | **无第三方版权**，可商用 |
> | 3 首 BGM `bgm/*.wav` | [`tools/music/render_bgm.mjs`](../../tools/music/render_bgm.mjs)：MIDI 乐谱 → FluidSynth + GeneralUser GS 渲染 | 许可允许商用，**但音色库有一处残余溯源风险** |
>
> BGM 不是 AI 生成，因此**无需 Steam AI 披露**；但它引入了音色库来源问题，
> 已在 [`assets/CREDITS.md`](../CREDITS.md) 第六节如实登记（含两条替代方案）。
> 音效部分仍与 `CREDITS.md` 中登记的 AI 图片素材（Leonardo）性质不同，不需要登记。

---

## 一、规格

| 项 | 值 |
|---|---|
| 采样率 | 22050 Hz |
| 位深 | 16-bit PCM（有符号小端） |
| 声道 | 单声道 |
| 音效峰值 | −3 dBFS |
| BGM 峰值 | −8 dBFS |
| 音效时长 | 0.12 ~ 0.88 s |
| BGM 时长 | 20.00 / 19.20 / 20.00 s（均可无缝循环）|
| 目录总大小 | 约 3.7 MB（音效 441 KB + BGM 2.5 MB）|
| 量化抖动（dither） | 未添加（16-bit 量化噪声约 −93 dBFS，可忽略） |

---

## 二、如何重新生成

```powershell
# 音效（19 个）
& "C:\Users\zh\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" `
  D:\1\infinite_loop\tools\audio\gen_audio.py

# BGM（3 首）—— 需要 node；具体前置见 tools/music/render_bgm.mjs 头部注释
node D:\1\infinite_loop\tools\music\render_bgm.mjs
```

> `gen_audio.py` **不再生成也不再触碰 BGM**（它只负责 19 个音效），
> 因此重跑它不会覆盖 `bgm/` 里的曲子。

脚本特性：

* **幂等**：重复运行覆盖同名文件，相同代码产出**逐字节完全相同**的 WAV
  （所有随机数来自固定 seed 的 `np.random.default_rng`）。
* **原子**：先把 22 个波形全部合成到内存，最后统一写盘；任何一步失败都不会留下半新半旧的文件。
* **自检**：运行结束会打印逐文件时长 / 峰值 / RMS / 削波 / 体积，并断言全部硬性指标；
  任一断言失败时以非 0 退出码结束。
* 只读 `assets/audio/` 与 `tools/audio/`，不触碰仓库其他文件。

---

## 三、文件清单与用途

### 音效 `assets/audio/sfx/`

| 文件 | 用途（建议接线时机） | 时长 s | 峰值 dBFS | RMS dBFS | 大小 KB |
|---|---|---|---|---|---|
| `ui_click.wav` | 界面点击（按钮 / 切换页签） | 0.120 | −3.00 | −20.51 | 5.21 |
| `ui_confirm.wav` | 确认、购点成功（上行两声） | 0.320 | −3.00 | −14.03 | 13.82 |
| `ui_deny.wav` | 操作非法 / 不可点（低沉短"嘟"） | 0.240 | −3.00 | −10.28 | 10.38 |
| `hit.wav` | 我方攻击命中（钝击 + 噪声爆） | 0.300 | −3.00 | −14.97 | 12.96 |
| `miss.wav` | 挥空 / 未命中（风声下扫） | 0.340 | −3.00 | −17.15 | 14.69 |
| `crit.wav` | 暴击（命中音 + 金属亮音） | 0.480 | −3.00 | −19.70 | 20.71 |
| `hurt.wav` | 我方受伤（闷响 + 人声感低频） | 0.360 | −3.00 | −14.56 | 15.55 |
| `die.wav` | 敌人倒下（下滑呻吟 + 落地闷响） | 0.860 | −3.00 | −14.51 | 37.08 |
| `heal.wav` | 治疗 / 用药（上行柔和琶音） | 0.550 | −3.00 | −11.97 | 23.73 |
| `skill.wav` | 技能发动（上扬能量波） | 0.480 | −3.00 | −12.26 | 20.71 |
| `bloodline.wav` | 血统 / 基因锁觉醒（脉冲 + 失真上扫） | 0.880 | −3.00 | −9.13 | 37.94 |
| `dice.wav` | D10 骰池检定（7 记骰子滚动 + 落定） | 0.780 | −3.00 | −23.83 | 33.63 |
| `step.wav` | 脚步（很轻的噪声脉冲） | 0.120 | −3.00 | −18.88 | 5.21 |
| `door.wav` | 开门 / 切换房间（门轴吱呀 + 咔哒） | 0.840 | −3.00 | −17.51 | 36.22 |
| `pickup.wav` | 拾取物品（短促上行叮） | 0.220 | −3.00 | −15.04 | 9.52 |
| `clue.wav` | 发现线索（增四度神秘三音 + 简易混响） | 0.720 | −3.00 | −14.03 | 31.05 |
| `noise.wav` | 噪音警戒（远处嘶叫 + 心跳两下） | 0.880 | −3.00 | −16.26 | 37.94 |
| `evac.wav` | 撤离成功（明亮上行和弦） | 0.860 | −3.00 | −17.02 | 37.08 |
| `defeat.wav` | 战败（下行暗淡和弦） | 0.880 | −3.00 | −14.28 | 37.94 |

### BGM `assets/audio/bgm/`

| 文件 | 用途与基调（依据 `docs/剧情大纲_惊变公寓.md`）| 时长 s | 峰值 dBFS | RMS dBFS | 大小 KB |
|---|---|---|---|---|---|
| `explore.wav` | **探索 · 屏息**（参考《寂静之地》）：低音弦乐长音不断 + A/Bb 小二度弦乐 pad + 偶发金属碰响与钢琴单音。**什么都不会发生** —— 恐怖来自"还没有发生的事" | 20.00 | −8.00 | −20.37 | 861 |
| `battle.wav` | **战斗 · 机械紧迫**（参考《28 天后》）：八分音符低音 ostinato + A2/Bb2 小二度与 Eb3 三全音 pad + 定音鼓 + 鼓组 + 铜管三全音刺入。**没有旋律，只有推进** | 19.20 | −8.00 | −24.41 | 827 |
| `hub.wav` | **主神空间 · 非人的冷**：空五度合唱 pad + 合成器铺底 + 稀疏钟琴，无节奏无旋律。**刻意不用弦乐** —— 弦乐有人味，主神不该有 | 20.00 | −8.00 | −24.18 | 861 |

---

## 四、合成方法摘要

### 音效

| 文件 | 合成方法 |
|---|---|
| `ui_click` | 带通（1.5–7 kHz）噪声"嗒" + 1.15 kHz / 2.6 kHz 极短正弦 + 780 Hz 盒感 |
| `ui_confirm` | 1046.5 → 1568 Hz 两声正弦（叠加 2、3 次谐波），错开 0.13 s |
| `ui_deny` | 225 → 178 Hz 软化方波（`tanh` 限幅）过 1.4 kHz 低通 |
| `hit` | 95 → 42 Hz 指数扫频正弦钝击 + 带通（0.7–4.5 kHz）噪声爆，末端 `tanh` 饱和 |
| `miss` | 白噪声分 6 个带通频带（2.5–6 k → 150–420 Hz），按三角权重随时间交叉淡化 → 下扫呼啸 |
| `crit` | `hit` 音色叠加 5 个非谐和比例高频分音（2100 × 1.00/1.73/2.41/3.17/4.09）+ 137 Hz 环调制 |
| `hurt` | 320 Hz 低通噪声闷响 + 120 → 78 Hz 下滑 sub + 声带脉冲串过三组共振峰带通（380–900 / 900–1800 / 2200–3200 Hz） |
| `die` | 0.62 s 下滑呻吟（基频 190 → 78 Hz、5.4 Hz 颤音、三组共振峰）+ 0.62 s 处 70 → 38 Hz 落地闷响 |
| `heal` | C5-E5-G5-C6 柔和正弦琶音（错开 0.11 s）+ 微弱空气噪声 |
| `skill` | 180 → 1700 Hz 与 270 → 2560 Hz 指数上扫正弦（加 11 Hz FM）+ 上扬带通噪声 whoosh |
| `bloodline` | 6.5 Hz 门控的 55/82.5/27.5 Hz 脉冲低音 + 锯齿波 78 → 430 Hz 失真上扫（`tanh` drive 3→8）+ 0.62 s 爆发 |
| `dice` | 固定种子随机的 7 记骰子"喀哒"（带通噪声脉冲）+ 0.56 s 一记落定 + 桌面滚动摩擦底 |
| `step` | 1.7 kHz 低通噪声脉冲 + 极轻 110 Hz 低频 body |
| `door` | 频率抖动（1.7 Hz + 4.3 Hz）的正弦簇 + 摩擦带通噪声构成门轴吱呀，0.66 s 处"咔哒" |
| `pickup` | 1318.5 → 1975.5 Hz 两记短促上行叮 |
| `clue` | F5 → B5（增四度）→ G#5 三音，叠加 3 段衰减延迟拷贝做简易混响 |
| `noise` | 0.46 s 远处嘶叫（脉冲串 + 颤音 + 共振峰 + 低通变闷）+ 0.52 / 0.70 s 两下心跳（58 + 33 Hz）+ 环境底噪 |
| `evac` | C 大调五音上行琶音 + 0.26 s 处 2093 Hz 明亮顶点铃音 |
| `defeat` | A 小调五音下行琶音 + 1.006 倍失谐 detune + 2.6 kHz 低通变暗 + 0.30 s 处 55 Hz 压迫低音 |

### BGM 无缝循环的实现（关键）

三首 BGM 走的是**渲染 + 交叉淡化**路线（不再是波形合成，因此下面第一节的"频率栅格化"对它不适用）：

1. **越界持续音**：每轨的最后一个音在渲染前自动延长 8 拍，**跨过循环点** ——
   否则持续音正好在循环点收尾，接缝处会留下一段静音（这一条是被验收脚本抓出来的）。
2. **尾巴交叉淡化**：渲染时多留 2.5 s 混响尾巴，再把这段尾巴**淡化叠回开头**。
   循环回来时先听到上一轮的余响，而不是被硬切掉的干声。
3. **末段微对齐**：用一段 2048 帧（≈93 ms）平方权重斜坡把 `|x[0] − x[-1]|` 压到 0，
   长斜坡是为了避免在循环点制造曲率突变。

> **实测结果**（`tools/audio/verify_audio.py`）：三首 BGM 的 `|x[0] − x[-1]|` 均为 **0**（16-bit 计数）；
> 接缝二阶差分分别 106 / 108 / 245，远低于各自内部 p99（667 / 1198 / 1722）；
> 拼接点 RMS 与整段 RMS 同量级（0.071 / 0.029 / 0.063 vs 0.096 / 0.060 / 0.062）。

---

## 五、在 Godot 里接线

本项目的唯一播放入口是 autoload `AudioManager`（见 `autoload/audio_manager.gd`，已注册在 `project.godot`）。
它按 `SFX_DIR + 名字 + ".wav"` / `BGM_DIR + 名字 + ".wav"` 加载，
其 `SFX_NAMES` 清单与本目录实际文件名**已核对为 19/19 + 3/3 完全一致**。

```gdscript
AudioManager.play("hit")
AudioManager.play("dice", {"throttle": 0})
AudioManager.play_bgm("battle", 0.6)
```

### ⚠️ 关于 BGM 循环：请显式设置 `loop_end`

WAV 文件格式本身不携带循环标记，Godot 也不会自动识别，必须在运行时打开循环。
`AudioManager._stream()` 已经这样做了：

```gdscript
var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
w.loop_mode = AudioStreamWAV.LOOP_FORWARD
w.loop_begin = 0
w.loop_end = 0            # ← 这里建议改成显式帧数
```

**建议把 `w.loop_end = 0` 改为显式帧数**，原因：

* Godot 官方文档对 `AudioStreamWAV.loop_end` 的说明只有
  "The loop end point (in number of samples, relative to the beginning of the stream)"，
  **并未声明 `0` 代表"到流末尾"**（[类参考](https://docs.godotengine.org/en/4.1/classes/class_audiostreamwav.html)）。
* 引擎源码 `scene/resources/audio_stream_wav.cpp` 的混音函数里，`loop_end` 被**直接**当作循环边界：
  `end_limit = (loop_mode != LOOP_DISABLED) ? (loop_end << MIX_FRAC_BITS) : ...`，
  运行路径上没有"若为 0 则取长度"的兜底分支。
* 而**导入器**表达"循环到末尾"用的是 **`-1`**（`if (loop_end < 0) loop_end = CLAMP(loop_end + frames, ...)`），
  说明 `0` 与"末尾"在本引擎里并不是同一含义。

因此显式给出帧数最稳妥：

```gdscript
var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
w.loop_mode = AudioStreamWAV.LOOP_FORWARD
w.loop_begin = 0
var bytes_per_frame := 1 if w.format == AudioStreamWAV.FORMAT_8_BITS else 2
if w.stereo:
    bytes_per_frame *= 2
w.loop_end = w.data.size() / bytes_per_frame
```

这三首 BGM 本身**在样本层面已经是无缝的**（见第四节），只要循环区间是 `[0, 帧数)`，接缝处就不会有爆音。

> 若不走 `AudioManager`、直接用 `AudioStreamPlayer` 播 BGM，则同样需要自己打开循环，
> 或在导入面板里把 Loop Mode 设为 `Forward`（对应 `.import` 里的 `edit/loop_mode=1`，
> 并把 `edit/loop_end` 留作 `-1`）。

### ⚠️ 关于导入压缩：Godot 默认会用 QOA 有损压缩

Godot 的 WAV 导入器默认 `compress/mode=2`，即 **Quite OK Audio（QOA）有损压缩**
（源码 `editor/import/resource_importer_wav.cpp`：
`ImportOption(..., "PCM (Uncompressed),IMA ADPCM,Quite OK Audio"), 2)`）。
本项目 22 个 WAV 当前就都是 `compress/mode=2`。

* 对**音效**没有影响，QOA 的听感接近无损，而且省了体积。
* 对 **BGM 的循环点**存在理论风险：QOA 是有损 + 分块编码的，
  解码后的 `x[0]` 与 `x[-1]` 不再严格相等，循环缝合处可能出现轻微咔哒。
  **我没有 Godot 可执行文件，无法在本机实测这一点。**

**若试玩时发现 BGM 循环点有咔哒**，把 3 首 BGM 改成无损即可
（导入面板把 Compress Mode 设为 `PCM (Uncompressed)`，或直接改 `.import` 里的
`compress/mode=0` 后重新导入）。代价是 BGM 从约 700 KB 回到 2.53 MB —— 对单机游戏可以接受。

```ini
; assets/audio/bgm/explore.wav.import
[params]
compress/mode=0        ; 0=PCM 无损  1=IMA ADPCM  2=Quite OK Audio（默认）
edit/loop_mode=0       ; 循环交给 AudioManager 在运行时打开
```

建议在导入设置里保持 16-bit 无损（不要勾选 `force/8_bit`），22050 Hz 的 WAV 体积已经很小。

---

## 六、已知限制（诚实说明）

1. **本次验证是"数值 + 频谱目检"，不是真耳试听。** 生成环境无法播放声音，
   所有结论基于客观指标（时长 / 峰值 / RMS / 削波 / 循环点差分 / 频谱图形态）
   与逐文件频谱图的人工目检。**上线前请务必用耳朵过一遍**，尤其确认
   `hurt` / `die` / `noise` 的"人声感"是否符合预期。
2. **人声是共振峰建模的合成近似，不是真人录音。** `hurt` / `die` / `noise` 里的呻吟、
   嘶叫由声带脉冲串 + 带通共振峰模拟，听感是"合成器模拟人声"，
   不是写实音效。若需要写实感，得换成真实采样（会引入版权问题）。
3. **音效之间的 RMS 响度跨度约 15 dB**（`bloodline` −9.1 dBFS 到 `dice` −23.8 dBFS）。
   这是"峰值统一 −3 dBFS"下必然的结果：持续音（血统觉醒）的 RMS 天然远高于稀疏瞬态
   （骰子、点击）。**若在游戏里觉得某个音效偏轻或偏响，建议在音频总线上做 per-bus 调整，
   而不是重新归一化峰值**，否则会破坏整套音效的峰值一致性。
4. **`dice.wav` 的 RMS 最低（−23.8 dBFS）**，因为它本质是 7 个短瞬态 + 大量间隙。
   这是骰子音色的自然属性（稀疏 = 低 RMS），不是缺陷；但它是本套中最"需要靠总线补音量"的一个。
5. **采样率上限 22050 Hz** 是需求指定的，Nyquist 频率 11.025 kHz，高频内容受限
   （例如 `crit` 的金属泛音、`door` 的摩擦噪声在 11 kHz 以上被截断）。
   对像素风 CRPG 足够，但不适合做电影级音效。
6. **未加 dither。** 16-bit 量化噪声约 −93 dBFS，远低于可闻阈值，且加抖动会让
   短暂音段出现非零底噪，故省略。
7. **`assets/CREDITS.md` 未改动**（按要求避免与他人改动冲突）。本目录的音频无版权风险，
   无需登记；如需登记，可自行追加一行说明来源为 `tools/audio/gen_audio.py` 程序化合成。
8. **引擎内验证情况已更新。** 现在本机有 Godot，
   "22 个文件能否被引擎加载 / 文件名是否与 `AudioManager.SFX_NAMES`、`BGM_NAMES` 逐字一致"
   已由 `tests/audio_test.tscn` 在**引擎内实测**。
   仍未实测的是 **BGM 循环点的听感**与 **QOA 压缩对循环点的实际影响**（见下一条）。
9. **导入设置我一个字也没改。** `assets/audio/**/*.import` 是 Godot 编辑器生成的，
   当前为 `compress/mode=2`（QOA 有损，引擎默认）+ `edit/loop_mode=0`。
   是否改成无损属于资产流水线决策，请在试听后决定（见第五节）。

---

## 七、复现验证

`tools/audio/gen_audio.py` 运行时会自动完成全部硬性指标断言。
**独立复核**（不复用生成脚本代码，另写一份读取逻辑）用：

```powershell
& "C:\Users\zh\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" `
  D:\1\infinite_loop\tools\audio\verify_audio.py
```

检查项：

* 格式为单声道 / 16-bit / 22050 Hz；
* sfx 时长 ∈ [0.08, 1.00] s，BGM ∈ [16, 24] s；
* 峰值在目标 ±2 dB 内（sfx −3、BGM −8）；
* 无削波（无样本达到 ±32767）、无静音（std > 1e-4）、无直流（|DC| < 0.01）、存在实际振幅起伏；
* BGM `|x[0] − x[-1]|` 很小，且循环点一阶 / 二阶差分不超过信号内部差分的 p99；
* `assets/audio` 总大小 ≤ 12 MB；
* 连续运行两次，22 个文件的 sha256 完全一致（幂等）。
