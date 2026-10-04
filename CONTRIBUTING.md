# 协作指南（CONTRIBUTING）

> 项目：**轮回回廊** · Godot 4.7.2 · GDScript
> 目标：让新加入的人 **30 分钟内**能跑起来、改得动、测得出。

---

## 一、环境准备

| 项 | 版本 / 路径 |
|---|---|
| 引擎 | **Godot 4.7.2**（GL Compatibility） |
| 渲染 | 1280×720，Nearest 过滤（像素风，不要改） |
| 编辑器 | 建议 VS Code + `godot-tools` 插件（可选） |

**首次拉取后必须做一次**（否则全局 `class_name` 不注册，会报一堆 "Identifier not found"）：

```bash
godot --headless --path . --editor --quit
```

**注意**：Godot 会生成 `.godot/` 缓存目录，它已在 `.gitignore` 里，**不要提交**。

---

## 二、跑起来

```bash
# 启动游戏
godot --path .

# 跑单测（纯逻辑，无 autoload）
godot --headless --path . -s res://tests/dice_test.gd

# 跑场景测试（有 autoload，必须用 .tscn）
godot --headless --path . res://tests/flow_driver.tscn --quit-after 6000
```

> **重要区别**：`-s xxx.gd` 模式**没有 autoload**，脚本里用到 `Game` / `EventBus` / `DebugLog`
> 就会编译失败。这类脚本必须走 `.tscn` 场景模式。

---

## 三、提交前必须做的三件事

1. **编译检查**：`godot --headless --path . --editor --quit`（看有没有 Parse Error）
2. **跑全量测试**（见下）
3. **如果是美术/场景改动，截一张图**

```bash
# 全量回归（31 项）：推荐直接用运行器 —— 每个测试带时间戳与硬上限，
# 某个测试卡住会被标成 TIMEOUT 并杀掉，而不是把整批回归拖死
#   pwsh -File tools/run_tests.ps1              # 全部 31 项
#   pwsh -File tools/run_tests.ps1 -UnitsOnly   # 只跑 10 项纯逻辑单测
#   pwsh -File tools/run_tests.ps1 -ScenesOnly  # 只跑 21 项场景/流程测试
# 下面是不用运行器时的手写等价写法（仅单测部分）：
for t in dice_test combat_test content_test world_test bloodline_test \
		 bloodline_combat_test bloodline_mitigation_test attr_redesign_test \
		 los_test rooms_test; do
  godot --headless --path . -s res://tests/$t.gd
done
# 场景类见 README.md 的验证清单
```

**验收底线：全绿才能提交。** 这个仓库的测试就是我们的回归网 ——
别人改坏了，测试会立刻告诉你，而不是等玩家发现。

> **新测试的硬性要求**：`_ready()` 的第一行必须调用
> `TestGuard.arm("xxx_test", 45.0, get_tree())`。
> 它给每次测试运行一个**墙钟时间戳 + 硬上限**；超时会打印 FAIL 并 `quit(1)`，
> 即使测试自己卡在某个 `await` 里也能把进程收掉。
> （教训：一个没有上限的等待循环曾让整批回归永远跑不完，而且因为输出被缓冲，连错在哪都看不到。）

---

## 四、操作日志（排查问题请用它，不要靠截图猜）

游戏内置结构化运行日志 `DebugLog`：

```gdscript
DebugLog.ev("battle", "战斗结束", {"victory": true, "hp": 16, "kills": 2})
DebugLog.count("battle")        # 某类事件次数
DebugLog.find("用药")            # 含关键词的行
DebugLog.dump("user://run.log") # 落盘
```

**纪律**：**只记录事实，不记录判断**；数值一律带前后值。
排查问题时先读日志，别一上来就截图 —— 截图无法 grep 也无法断言。

---

## 五、分支与提交

- 主分支 `main` **保护**，不直接推
- 功能分支：`feat/xxx`、`fix/xxx`、`art/xxx`、`docs/xxx`
- 提交信息用**中文或英文都行，但要能看懂改了什么**：

```
feat(battle): 血统节点接入近战伤害
fix(ui): 角色面板关闭后未释放 CanvasLayer，导致画面冻结
docs(readme): 补全测试清单
art(tiles): 重绘地砖与砖墙，平铺无缝
```

- **一个 PR 只做一件事**。顺手改的无关代码会让 review 和回滚都变难。

---

## 六、⚠️ Godot 协作的四个大坑

### 1. `.tscn` 场景文件冲突几乎无法手工合并
**约定：一个场景文件同一时间只有一个人改。**
需要并行时，把新功能做成**独立场景**再挂进去，而不是两个人改同一个 `.tscn`。

### 2. `project.godot` 是最容易冲突的文件
（autoload、输入映射、显示设置都在里面）
**约定：只由一个人（项目负责人）改。** 其他人要加 autoload 就提需求。

### 3. 二进制资源必须走 LFS
`git lfs install` 之后再 clone。否则每次改图都往历史里塞一份完整文件，
仓库会迅速膨胀到几百 MB。

### 4. 美术资源注意授权
`assets/CREDITS.md` 里记着来源。**带 `{IS}` 标记的是任天堂素材，原型阶段可用，不能随成品发布。**
新增素材请**同时更新 CREDITS**，写清来源与授权。

---

## 七、建议的分工边界（按写入范围切开）

这个项目的结构天然适合按**目录**分工，互相几乎不碰：

| 方向 | 写入范围 | 说明 |
|---|---|---|
| **战斗** | `combat/` `systems/combat*.gd` | 回合制、技能、血统战斗效果 |
| **探索/箱庭** | `scenarios/r001_apartment/` | 房间数据、交互、剧情钩子 |
| **UI** | `ui/` | 主菜单、建卡、主神空间、角色面板 |
| **美术** | `assets/` `tools/pixelart/` | tile、立绘、装饰、音效 |
| **数值/内容** | `defs/` `content.gd` | 属性、技能、敌人、物品、线索 |
| **测试** | `tests/` | 每人负责自己模块的测试 |

**冲突最少的做法：先开 issue 说清"我要动哪个目录"，再开工。**

---

## 八、常用调试脚本

```bash
# 逐房间截图（快，用内部跳转）
godot --path . res://tests/shot_rooms.tscn --quit-after 4800

# 真实输入全流程试玩（从主菜单一路点到通关，零内部跳转）
godot --path . res://tests/real_playthrough.tscn --quit-after 300000
```

> 截图脚本**不要加 `--headless`**，否则截出来全黑。

---

## 九、文档在哪

| 文件 | 内容 |
|---|---|
| `README.md` | 项目概览、目录结构、测试清单 |
| `docs/游戏策划案.md` | 总体设计 |
| `docs/剧情大纲_惊变公寓.md` | 剧情结构（起承转合、参考片单） |
| `docs/剧情细节_惊变公寓.md` | 文案包（对话、线索、结局） |
| `docs/属性重设计方案.md` | 九属性与战棋出口 |
| `docs/血统模块设计方案.md` | 血统系统 |
| `docs/试玩报告_第1轮.md` | 玩家视角的问题清单 |
| `docs/协作规范_联合开发.md` | **本文档的详细版** |
