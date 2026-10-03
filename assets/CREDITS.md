# 素材来源登记（CREDITS）

> 用途：记录每一份 AI 生成 / 第三方素材的来源、许可与可商用性。
> **Steam 上架需在商店页披露 AI 生成素材**，本文件即披露依据，请随素材更新。

## 一、生成方式

| 项 | 内容 |
|---|---|
| 生成工具 | Leonardo.Ai（网页生成页自动化，见 `tools/leonardo-bot/bot.mjs`） |
| 自动化原理 | 复用本机 Chrome + 持久登录态；填提示词 → 点 Generate → 按图片 URL 差集识别新图 → 页面内 fetch 取图 |
| 提示词与参数 | 随批次保存在 `assets/raw/<批次>/manifest.json` |
| 后处理 | `tools/pixelize.py`：最近邻缩放 → 去背景 → 调色板量化（≤24 色） |
| 风格预设 ID | `111dc692-d470-4eec-b791-3475abac4c46` |

## 二、当前素材清单

| 文件 | 类型 | 来源 | 许可 | 可商用 |
|---|---|---|---|---|
| `assets/tiles/w1/floor.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/wall.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/door.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/stairs.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/exit.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/table.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/cabinet.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/tiles/w1/bed.png` | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/sprites/w1/player_idle.png` | 角色 16×24 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/sprites/w1/zombie_idle.png` | 敌人 16×24 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
| `assets/icons/pipe.png` | 道具图标 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |

**尚未生成（免费额度已耗尽，页面提示 out of tokens）**

| 计划文件 | 用途 | 当前降级方案 |
|---|---|---|
| `assets/sprites/w1/crawler_idle.png` | 爬行者 16×24 | 暂用丧尸图 + 绿色调显示 |
| `assets/sprites/w1/brute_idle.png` | 尸王 32×32 | 暂用丧尸图放大 + 红色调显示 |
| 地下车库 / 一层大厅地形 tile | 阶段 2、3 | 阶段 1 的 8 种 tile 已完成 |

> 额度说明：Leonardo 免费档每日额度有限（约 150 tokens），本次批量生成后耗尽。
> 恢复额度或升级付费档后可直接续跑：`node tools/leonardo-bot/bot.mjs gen --batch <批次>.json --out assets/raw/<批次>`（已有素材不会重复生成）。

## 三、许可状态与风险（重要）

- 以上素材由 **Leonardo 免费档**生成，免费档输出**仅限个人 / 非商业用途**。
- **发布（含 Steam 上架、众筹、售卖）之前必须**：
  1. 升级到含商业使用权的付费档**重新生成**，或
  2. 替换为 **CC0** 素材 / 自制素材，并更新本表。
- Steam 商店页需**披露 AI 生成素材**；本文件中的生成日期、提示词与参数即为披露与申诉依据。
- 免费可商用备选来源：**Kenney**、**Pixel Frog**、**Ansimuz**、**0x72**（均为 CC0）。

## 四、登记规范

新增素材时请追加一行，并在 `assets/raw/<批次>/manifest.json` 中保留原始提示词与图片 URL：

```
| assets/tiles/<world>/<name>.png | 地形 tile 16×16 | Leonardo（AI 生成） | 免费档 | ⚠️ 待替换 |
```

---

## 五、战斗立绘（火纹职业卡素材）⚠️ 高风险

> 背景：程序化绘制（Aseprite Lua 几何拼图）试了 4 版均达不到手绘品质，
> 改为直接采用 **[FE-Repo](https://github.com/Klokinator/FE-Repo)** 的职业卡素材
> （本地副本 `D:\1\fe-repo`，共 665 张）。

### 当前在用（4 张）

| 游戏文件 | 角色 | 原始素材 | 作者标签 | 可商用 |
|---|---|---|---|---|
| `assets/sprites/w1/battle/zombie.png` | 丧尸 | Revenant | **{IS}** | ❌ **任天堂资产** |
| `assets/sprites/w1/battle/crawler.png` | 爬行者 | Mauthe Doog | **{IS}** | ❌ 同上 |
| `assets/sprites/w1/battle/brute.png` | 尸王 | Cyclops Axe | **{IS}** | ❌ 同上 |
| `assets/sprites/w1/battle/hero.png` | 主角 | Hero (M) Gerik-Style Sword | {Nuramon} | ⚠️ 需署名 |

### FE-Repo 的授权标签含义

| 标签 | 含义 |
|---|---|
| `{IS}` | Intelligent Systems 官方资产 —— **仅供学习，不可商用** |
| `[F2E]` | Free to Edit —— 可自由修改使用 |
| `[F2U]` | Free to Use —— 可自由使用 |
| `{作者名}` | 社区作者作品 —— 通常**署名后可用**，以作者发布页为准 |
| 无标签 | 需向作者确认 |

### 发布前必须做的事

| 现在用的 | 可商用替代（同为火纹风格、非 IS） |
|---|---|
| `Revenant {IS}` | `Bonewalker (Stalfos) Sword {Uncle Mikey}` / `Lich Entombed {SkidMarc25}` |
| `Mauthe Doog {IS}` | `Mauthe Doog Cerberus {Dellhonne}` |
| `Cyclops Axe {IS}` | `Bael Queen Bael {Seal}` / `Tarvos (M) Elder Centaur {Seal}` |
| 完全免费（全库仅 2 张 F2E） | `Bonewalker Lance {Epicer} [F2E]` |

**结论**：这 4 张立绘**仅限开发与原型阶段使用**。正式发布前必须
① 换成 `[F2E]`/`[F2U]`/CC0 素材，或 ② 自绘 / 委托绘制；
主角卡（Nuramon）在发布时需在 credits 里署名。

### 处理脚本

| 脚本 | 作用 |
|---|---|
| `tools/pixelart/strip_fe_card.py` | 职业卡 → 游戏立绘：切边框 + flood fill 抠背景 + 包围盒裁剪 + 整数倍放大（`--list` 列出可选素材，`--build` 重建当前 4 张） |
| `tools/pixelart/pixelize_for_game.py` | AI 图 → 游戏素材：抠背景 / 缩放 / 降色 16 / 描边 |
| `tools/pixelart/gen_battle_sprites.lua` | Aseprite 程序化生成（**降级方案**，仅作占位） |
| `tools/pixelart/img2img_battle_sprite.py` | ComfyUI 图生图客户端（需本地模型，当前未启用） |

### 参考素材（仅学习，不进入游戏）

`docs/art_reference/` 存放火纹原版战斗动画与职业卡（来自
[fireemblem8u](https://github.com/jiangzhengwenjz/fireemblem8u) 反编译 + FE-Repo），
**只用于研究画法**，不得打包进发布版本。
