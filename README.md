# 轮回回廊 —— 无限流 CRPG 垂直切片

> 原「无终回廊」规则怪谈 demo 已整体重置。现在是对标博德之门 / 开拓者 / 行商浪人的**无限流题材 CRPG 垂直切片**，以《无限恐怖》《惊悚乐园》《轮回乐园》《玩家凶猛》为题材蓝本，系统参考五本无限流 TRPG 规则书（见文末"规则出处"）。

引擎：Godot 4.7（GL Compatibility，无外部美术资源，UI 与地图全部代码构建）
项目根：`D:\1\infinite_loop`

---

## 一、怎么运行

1. 打开 Steam 中的 **Godot Engine**（v4.7.2）。
2. 项目管理器 → 导入 → 选择 `D:\1\infinite_loop\project.godot`。
3. 打开项目后按 **F5**（或右上角 ▶ 运行）。
4. 游戏流程：主菜单 → 新的开始 → 建卡 → 主神空间 → 进入副本「惊变公寓」→ 通关结算返回主神空间。

> 存档位于 `user://save.json`（Windows 下为 `%APPDATA%\Godot\app_userdata\轮回回廊\save.json`）。主神空间可重置存档。

## 二、玩法流程（垂直切片内容）

1. **建卡**：9 属性 27 点购点（属性 1→6，成本 = 当前值累加）＋ 12 技能 20 点（1 点/级，0→5）＋ 5 选 1 天赋 ＋ 代号起名。
2. **主神空间**：查看档案、最佳评价、奖励点；D 级商店兑换属性/技能/装备/补给。
3. **副本「惊变公寓」**（约 20 分钟一局）：
   - 开场白由轮回手表派发任务；20×12 等距地图点击移动。
   - 主线「活着离开」：找到安全出口钥匙 → 踩出口撤离。
   - 支线「老邻居」：把降压药交给陈叔 402 → 获得尸王弱点。
   - 支线「清道夫」：击杀尸王。
   - 探索：调查点（武器/钥匙/日志/线索）、NPC 对话树、D10 检定（可投入意志力）。
   - 战斗：AP 行动点回合制，点击敌人攻击 / 点击地面移动 / 防御姿态 / 使用物品 / 结束回合。
   - 结算：3 结局（完美撤离 / 惊险撤离 / 陨落），奖励 = 任务 + 击杀 + 线索×5。

## 三、系统设计（来自 RE25 规则书的垂直切片简化）

| 模块 | 规则 |
|---|---|
| 检定 | D10 骰池，DP = 属性 + 技能；每枚骰 ≥8 计 1 成功，掷 10 追加一骰（递归加骰链）；成功数 ≥ 难度(DC) 即通过 |
| 附加成功 | 属性 ≥6 每 +5 得 1 附加成功；技能达 5/7/9/11/13/15 各 +1 |
| 技能短板 | 心智系 0 级自动失败；生理系 0 级 −1 成功；互动系 0 级 −2 成功 |
| 意志力 | 上限 = 决心 + 沉着；战斗外检定可花费 1 点 +1 成功 |
| 属性 | 九属性三系：力量/敏捷/耐力 / 智力/感知/决心 / 风度/操控/沉着；常人 2、极限 5、超凡 6 |
| 技能 | 生理（肉搏/白刃/枪械/躲藏/求生）＋ 心智（调查/医学/神秘学）＋ 互动（交际/胁迫/掩饰/感受） |
| 战斗 | 每回合 6 AP：移动 1 格 1 AP、攻击 3 AP、防御姿态 2 AP（+2 防御）、用物品 2 AP |
| 伤害 | 伤害 = max(1, 攻击成功数 − 目标防御) + 武器加成 − 目标护甲 |
| 先攻 | d10 + 敏捷 + 沉着 |
| 生命/意志 | 生命 = 耐力×4 + 天赋修正；意志 = 决心 + 沉着 |
| 基因锁 | 生命 ≤30% 自动觉醒一阶（攻击成功 +1、伤害 +1）；**首次生命归零触发『绝境爆种』**（觉醒基因锁并恢复 20% 生命）；已觉醒后再归零则真正死亡 |
| 主神空间 | 奖励点货币；D 级兑换（属性/技能/装备）；副本卡；最佳评价记录 |

## 四、验证清单（已全部通过）

| 测试 | 命令 | 结果 |
|---|---|---|
| 骰池单测 | `godot --headless --path . -s res://tests/dice_test.gd` | PASS（6 断言） |
| 战斗单测 | `godot --headless --path . -s res://tests/combat_test.gd` | PASS（14 断言，连跑 10 次稳定） |
| 数据单测 | `godot --headless --path . -s res://tests/content_test.gd` | PASS（地图/布点/定义/对话树/寻路） |
| 玩法端到端 | `godot --headless --path . res://tests/flow_driver.tscn --quit-after 2400` | PASS（探索→战斗→返回→撤离→结算） |
| UI 端到端 | `godot --headless --path . res://tests/ui_flow_driver.tscn --quit-after 2400` | PASS（主菜单→建卡→主神空间→副本） |
| 点击链路 | `godot --headless --path . res://tests/click_test.tscn --quit-after 1200` | PASS（分发不拦截+点击移动 (2,2)→(5,2)） |
| 实体定位 | `godot --headless --path . res://tests/scenario_entities_test.tscn --quit-after 600` | PASS（12 个实体：玩家/4 敌人/2 NPC/5 调查点全部按格子就位） |
| 击杀清理 | `godot --headless --path . res://tests/kill_removal_test.tscn --quit-after 900` | PASS（阵亡单位节点被移除） |
| 战斗返回 | `godot --headless --path . res://tests/combat_return_test.tscn --quit-after 600` | PASS（战后探索地图上的尸体被清理） |
| 真实流程 | `godot --headless --path . res://tests/real_flow_test.tscn --quit-after 900` | PASS（探索→战斗→击杀→返回，全链路） |
| 血统模块 | `godot --headless --path . -s res://tests/bloodline_test.gd` | PASS（八系数据自检、排斥/协同计算、角色集成、存档兼容） |
| 血统战斗 | `godot --headless --path . -s res://tests/bloodline_combat_test.gd` | PASS（120 回合采样：排斥惩罚真实作用于输出与承伤） |
| 血统缓解 | `godot --headless --path . -s res://tests/bloodline_mitigation_test.gd` | PASS（意志压制 / 稳定剂 / 调和手术 / 融合技 / 基因崩溃） |
| 血统实战 | `godot --headless --path . res://tests/bloodline_live_test.tscn --quit-after 2400` | PASS（带高排斥血统进副本实战，失控真实触发） |
| 属性重做 | `godot --headless --path . -s res://tests/attr_redesign_test.gd` | PASS（9 属性战斗出口：暴击/首击减伤/威慑/意志） |
| 墙体视线 | `godot --headless --path . -s res://tests/los_test.gd` | PASS（墙/柜/树挡视线，门桌床不挡） |
| 箱庭数据 | `godot --headless --path . -s res://tests/rooms_test.gd` | PASS（62 项：行长/出口是门/双向连通/落点可走/全图可达） |
| 箱庭走位 | `godot --headless --path . res://tests/room_walk_test.tscn --quit-after 3600` | PASS（走到门格真的切房间，且能走回来） |
| 潜行 | `godot --headless --path . res://tests/stealth_test.tscn --quit-after 2400` | PASS（站背后不被发现） |
| 潜行接敌 | `godot --headless --path . res://tests/stealth_engage_test.tscn --quit-after 2400` | PASS（视野锥内被发现并进战斗） |
| 噪音 | `godot --headless --path . res://tests/noise_test.tscn --quit-after 2400` | PASS（阈值 6/10/14 召唤，按回合衰减） |
| 巡逻 | `godot --headless --path . res://tests/patrol_test.tscn --quit-after 3600` | PASS（会走/会转向/不穿墙/无路线者静止/视野分层） |
| 副本进度 | `godot --headless --path . res://tests/persist_test.tscn --quit-after 3600` | PASS（击杀与线索跨房间、跨战斗、跨存档不丢） |
| 逃跑 | `godot --headless --path . res://tests/flee_test.tscn --quit-after 3600` | PASS（逃跑退回上一间不判死；真战败仍结算） |
| 场景独立加载 | main_menu / hub / char_creation | 无脚本错误 |

> Godot 可执行文件示例：`"D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"`

## 五、代码结构

```
autoload/  event_bus.gd（信号总线）、game.gd（全局状态+存档 user://save.json）
defs/      attrs / skills / items / talents / enemies / quests_def / upgrades
           bloodlines.gd（八系血统 × D→S 五级 × 16 技能池；排斥/协同/融合技/主动技能效果）
systems/   dice_pool.gd（D10 骰池）、character.gd（角色+血统）、combat.gd（CombatUnit）
           combat_manager.gd（回合 / AP / AI / 结算）、quests.gd
world/     grid_world.gd（方格逻辑：12 种地形 / BFS / 移动与攻击范围）
           renderers/  grid_renderer.gd（渲染接口）、pixel_grid_renderer.gd（像素渲染）、
                       placeholder_renderer.gd（色块占位）
worlds/    registry.gd / world_def.gd（五界注册表 + 自动校验）
combat/    combat_scene.gd（战场 / 指令菜单 / 血统技能 / AP 制）
           battle_anim.gd（火纹式战斗特写）
scenarios/r001_apartment/  map_data（RE2 箱庭地图）/ dialogs / content / scenario.gd
ui/        hub.gd（主神空间）、char_creation.gd（建卡）、bloodline_panel.gd（血统页）、pixel_theme.gd
demo/      demo_scene.gd（独立试炼场：敌人 AI 追击 + 撤离结算）
tools/     make_tiles.py（程序化生成地板/墙/门）、pixelize.py、leonardo-bot/（AI 生图流水线）
tests/     26 项自动化测试（单测 10 + 场景流程 16）；另有 shot_*/repro_* 调试截图脚本
```

> 注：旧的 `world/iso_map.gd`（等距渲染）与 `systems/pathfinding.gd`（BFS）已被
> `GridWorld` 完全取代，已于本次梳理中删除。

## 六、规则出处（参考规则书，已解压至 D:\1\rules_ref\）

| 规则书 | 目录 | 引用章节 |
|---|---|---|
| 无限恐怖 2.5RE V1.04 | `rules_ref\re25` | 核心规则 / 属性概述 / 技能概述 / 战斗开始 / 基因锁规则 / 主神空间、经验值 / 专长概述（本切片系统蓝本） |
| 雪版无限恐怖 TRPG 2.3 | `rules_ref\snow23` | 题材与兑换框架参考 |
| 无限恐怖 FX v1.40 | `rules_ref\fx140` | 检定风格参考 |
| 无限流 TRPG 圈版 1.04 | `rules_ref\circle104` | 副本/任务设计参考 |
| 无限 TRPG 核心规则 RM 正式版 | `rules_ref\rmcore` | 主神空间结构参考 |

> 注：本切片为可运行的垂直验证，规则已做精简（如属性封顶 6、技能封顶 5、单副本），数值与完整规则书有出入，扩展时可按上述章节还原完整规则。

---

## 七、像素化改造与新架构（v0.2）

### 7.1 架构分层：逻辑与渲染解耦

```
worlds/                       世界注册表（五界数据 + 自动校验）
  registry.gd                   Worlds.all() / get_world(id) / validate_all()
  world_def.gd                  世界定义：阶段/任务/结算/机制，含地图布点校验
world/
  grid_world.gd                 方格逻辑层（视角无关）：12 种地形、BFS 寻路、
                                Dijkstra 移动范围、攻击范围、地图校验
  renderers/
    grid_renderer.gd            渲染器接口（只读逻辑层，绝不参与规则计算）
    placeholder_renderer.gd     色块占位（素材未就位也能完整跑通）
    pixel_grid_renderer.gd      16×16 像素 tile 渲染（当前使用）
```

**关键约束**：逻辑层不包含任何渲染 / 像素 / 视角概念。想换火纹式方格或博德之门式等距观感，只需替换渲染器，**逻辑与测试零改动**。

### 7.2 像素可玩切片

**完整流程已像素化**：探索场景（`scenario.tscn`）与战斗场景（`combat_scene.tscn`）都已从等距 `IsoMap`
切换到 `GridWorld + PixelGridRenderer`。实现方式是渲染器提供一层「IsoMap 兼容接口」
（`grid_to_world` / `grid_at_point` / `is_walkable` / `set_highlight` / `set_path` …），
因此旧场景代码**只改了构造地图的三行**，其余逻辑与全部端到端测试零改动。

```bash
# 完整体验（全像素风）：主菜单 → 新的开始 → 建卡 → 主神空间 → 进入副本
# 战斗中点击敌人，即播放火纹式战斗特写（冲刺 / 命中闪光 / 伤害数字 / 血条下降）
godot --path .

# demo/demo_scene.tscn 仍有价值：它是「敌人 AI 追击 + 探索拾取 + 撤离结算」的独立试炼场，
# 保留给开发调试（已不再占用主菜单入口，避免与主流程重复）
godot --path . res://demo/demo_scene.tscn
```

| 操作 | 效果 |
|---|---|
| 左键点格子 | 移动（每回合 4 格，蓝色高亮为可达范围） |
| 左键点敌人 | 相邻时攻击（命中 75%，敌人会反击） |
| 左键点交互点 | 拾取物品 / 获得线索（需相邻） |
| 空格 | 结束回合，敌人 AI 行动 |
| R / ESC | 重开 / 退出 |

主线：找到「安全出口钥匙」→ 走到安全出口撤离 → 三档结算（完美撤离 / 惊险撤离 / 陨落）。

### 7.3 AI 像素素材流水线

| 环节 | 工具 | 说明 |
|---|---|---|
| 生成 | `tools/leonardo-bot/bot.mjs` | 复用本机 Chrome + 持久登录态：填提示词 → 点生成 → 按 URL 差集识别新图 → 页面内 fetch 取图 |
| 后处理 | `tools/pixelize.py` | 最近邻缩放 + 去背景 + 调色板量化 → 16×16 / 16×24 真像素 |
| 规格 | `docs/素材生成方案.md` | 每张图的规格 / 提示词 / 参数 / 后处理 / 验收 / 许可 |
| 登记 | `assets/CREDITS.md` | 素材来源与许可（Steam 上架需披露 AI 素材） |

登录态存于 `.secrets/`（已 gitignore）；AI 原图存于 `assets/raw/`（已 gitignore），只有处理后的成品进入 `assets/tiles|sprites|icons`。

### 7.4 新增测试

| 测试 | 命令 | 覆盖 |
|---|---|---|
| 地基单测 | `godot --headless --path . -s res://tests/world_test.gd` | 方格逻辑、移动 / 攻击范围、五界数据校验、渲染器接口 |

完整回归清单见第四节。
