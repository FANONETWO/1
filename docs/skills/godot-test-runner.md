---
name: godot-test-runner
description: "在 Godot 4 项目里跑测试与语法验证的固定姿势：区分 `-s`（无 autoload）与 `.tscn`（有 autoload）两种模式、拉取代码后注册 class_name、定位 Parse Error 行号、批量跑全量回归。当用户要跑测试、验证改动、报 'Identifier not found'、'Parse Error'、'Compilation failed'、'Failed to load script'，或改完 GDScript 需要确认没破坏其他功能时，使用本 skill。"
argument-hint: "[测试名 | 症状描述 | 全量]"
version: "1.0.0"
user-invocable: true
---

# godot-test-runner.skill

> Godot 项目跑测试时最容易浪费时间的三个坑：
> ① 分不清 `-s` 和 `.tscn` 两种模式（导致满屏 `Identifier not found`）；
> ② 拉取新代码后没注册 `class_name`；
> ③ Parse Error 只报错不给行号，不知道去哪改。

---

## 触发条件

- 用户说「跑测试」「验证一下」「回归」「测试红了」
- 报错出现：`Identifier not found`、`Parse Error`、`Compilation failed`、
  `Failed to load script`、`Invalid call. Nonexistent function`
- **改完 GDScript 代码后**（默认就该跑一遍再交付）

---

## 第一步：永远先做编译 + 注册

```powershell
& $godot --headless --path . --editor --quit
```

**为什么必须先做**：
`class_name` 的注册信息存在 `.godot/` 里，而它按规范被 `.gitignore` 排除。
**刚 pull 下来的仓库、或新增了 `class_name` 的脚本，不跑这一步就会报
`Identifier not found: Game` 之类的一堆错。**

---

## 第二步：选对模式（这是最关键的一步）

| 模式 | 命令 | autoload 是否可用 | 适用 |
|---|---|---|---|
| **脚本模式** | `-s res://tests/x.gd` | ❌ **没有** | 纯逻辑单测（不碰 `Game`/`EventBus`/`DebugLog`） |
| **场景模式** | `res://tests/x.tscn --quit-after N` | ✅ 有 | 涉及全局单例、场景树、异步的场景测试 |

```powershell
# 单测（脚本 extend SceneTree）
& $godot --headless --path . -s res://tests/dice_test.gd

# 场景测试（脚本 extend Control，挂 .tscn）
& $godot --headless --path . res://tests/flow_driver.tscn --quit-after 6000
```

**判断口诀**：脚本里出现 `Game` / `EventBus` / `DebugLog` / `get_tree()` → **必须走 `.tscn`**。

> `--quit-after N` 的单位是**帧**（60fps 下 6000 ≈ 100 秒）。
> 跑得慢的试玩脚本要给足，否则会被强杀、日志戛然而止 —— 极易误判成"卡死"。

---

## 第三步：定位 Parse Error

`--editor --quit` **不打印** Parse Error。要看行号，用下面任一方式：

```powershell
# 方式 A：直接加载，错误会带 at: 行号
& $godot --headless --path . "res://tests/flow_driver.tscn" --quit-after 300 2>&1 |
  Select-String "Parse|scenario.gd:|at:" | Select-Object -First 8

# 方式 B：只做语法检查
& $godot --headless --path . --check-only --script "res://path/to/script.gd"
```

**典型 Parse Error 及成因**：

| 报错 | 成因 |
|---|---|
| `Cannot get index "xxx" from "{...}"` | **常量字典的键不存在** —— 重写数据表后忘了同步引用方（编译期就检查） |
| `Cannot infer the type of "x"` | 从 Variant（如 `cm.player_unit`）取值，必须显式写 `var x: int = int(...)` |
| `Too few arguments for "max()"` | GDScript 无 `Vector2i.max()`，要用 `maxi(absi(d.x), absi(d.y))` |
| `Invalid operands "Vector2i" and "int"` | 同上，`Vector2i` 不支持直接比较 |
| `Identifier not found: Game` | 用了 `-s` 模式，或没注册 class_name |

---

## 第四步：批量跑全量回归

```powershell
$godot = "D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
Set-Location <项目根>

Write-Output "=== 单测（-s 模式）==="
foreach ($t in @("dice_test","combat_test","content_test","world_test","bloodline_test",
                 "bloodline_combat_test","bloodline_mitigation_test","attr_redesign_test",
                 "los_test","rooms_test")) {
  $r = & $godot --headless --path . -s "res://tests/$t.gd" 2>&1 |
       Select-String "PASS|FAIL" | Select-Object -Last 1
  Write-Output "  $t -> $r"
}

Write-Output "=== 场景测试（.tscn 模式）==="
foreach ($t in @("flow_driver","ui_flow_driver","real_flow_test","stealth_test",
                 "stealth_engage_test","kill_removal_test","combat_return_test",
                 "click_test","scenario_entities_test","bloodline_skill_test",
                 "bloodline_live_test","noise_test","room_walk_test","persist_test",
                 "patrol_test","flee_test","item_heal_test")) {
  $r = & $godot --headless --path . "res://tests/$t.tscn" --quit-after 6000 2>&1 |
       Select-String "通过|PASS|FAIL|SCRIPT ERROR" | Select-Object -Last 1
  Write-Output "  $t -> $r"
}
```

---

## 写新测试时的约定

- **单测**：`extends SceneTree`，在 `_init()` 里跑完就 `quit()`
- **场景测**：`extends Control`，配一个同名 `.tscn`；用 `change_scene_to_file` 进目标场景，
  再 `add_child` 一个 `Driver`（`extends Node`）来跑异步流程
- **观察点要稳定**：涉及随机的地方用 `seed(20260101)` 固定，或用"有 vs 无"的对照比较，
  **不要断言绝对值**（骰池项目里最容易写出 flaky 测试）

---

## 常见坑速查

| 现象 | 原因 | 解法 |
|---|---|---|
| `Identifier not found: Game` | 用了 `-s` 模式 | 改用 `.tscn` 场景模式 |
| 满屏 `Identifier not found` | class_name 未注册 | `--editor --quit` 跑一次 |
| 只报 `Failed to load script` 无行号 | `--editor --quit` 不打印细节 | 用「第三步」的方式 A/B |
| 日志跑到一半就没了 | `--quit-after` 太小被强杀 | 加大该值（单位是帧） |
| `Cannot get index` | 常量字典缺键 | 搜引用方，同步数据表 |
| 测试偶尔红偶尔绿 | 断言依赖随机数 | 固定 seed 或改用对照比较 |
