---
name: godot-playtest
description: "让 AI 像真实玩家一样玩 Godot 游戏并找出 bug：用 push_input 模拟鼠标键盘（从主菜单一路点到通关，不用任何内部跳转方法）、逐帧截图、用 read_image 真正看图、用 DebugLog 做结构化断言。特别适用于验收玩法流程、发现 UI 遮挡/点击无效/画面冻结这类只有真玩才能暴露的问题。当用户说'试玩''像玩家一样玩''走一遍完整流程''验收一下''测测通关'，或需要用截图+日志定位交互问题时，使用本 skill。"
argument-hint: "[目标流程 | 游戏场景路径]"
version: "1.0.0"
user-invocable: true
---

# godot-playtest.skill

> **核心认知**：AI 看不到 GUI 窗口。所以"以玩家身份试玩"的正确形态是
> **脚本化模拟输入 → 截图 → 用 `read_image` 真的看图 → 用日志断言**。
>
> **最大的教训**：本项目两次漏掉严重 bug，都是因为"用内部方法直接跳转"而不是真点击 ——
> 内部跳转绕过了输入分发层，而 bug 恰恰就在那一层。
>
> **最神的一招**：**对比两张截图的 sha256**。如果明明过了两个不同状态、哈希却完全相同，
> 说明**画面根本没更新** —— 靠这招定位过一个"打开面板后整个游戏冻结"的阻塞级 bug。

---

## 触发条件

- 用户说「试玩」「像玩家一样玩」「走一遍完整流程」「测测能不能通关」「验收」
- 需要验证**交互链路**（点格子移动、点按钮、点 NPC）
- 需要发现**只有真玩才会暴露**的问题：UI 遮挡、点击落空、画面卡住、状态不同步

---

## 第一原则：不要用内部方法跳转

| ❌ 错误做法 | ✅ 正确做法 |
|---|---|
| 直接调 `scene._load_room("lobby")` | **点击地图上通往 lobby 的那扇门格** |
| 直接调 `scene._start_combat_with("zombie")` | **走到敌人旁边并点击它** |
| 直接调 `scene._inspect_spot("key")` | **走到交互点旁边并点击它** |
| 直接调 `bt._finish(true)` | **点击「攻击」直到战斗自然结束** |
| `scene.get("_player").hp = 999` | **用游戏内的道具/机制** |

**为什么**：bug 几乎都在"输入分发 → 状态更新"这条链路上。
用内部方法等于**把被测代码路径整体跳过**，测了个假的。

> 实测案例：`_unhandled_input` 里 `is_walkable(g)` 检查挡在 `_click_entity(g)` 之前，
> 导致**所有不可走格上的交互点（柜子/桌子/床）永远点不响**。
> 内部跳转测试永远发现不了这个 —— 因为旧脚本直接调 `_inspect_spot()`。

---

## 模拟输入的核心代码

```gdscript
## 模拟一次真实鼠标左键点击
func _click_at(p: Vector2) -> void:
    var m := InputEventMouseMotion.new()
    m.position = p
    m.global_position = p
    get_tree().root.push_input(m)
    await get_tree().process_frame
    for pressed in [true, false]:
        var e := InputEventMouseButton.new()
        e.button_index = MOUSE_BUTTON_LEFT
        e.pressed = pressed
        e.position = p
        e.global_position = p
        get_tree().root.push_input(e)
        await get_tree().process_frame

## 模拟键入文本（用于输入框）
func _type(edit: LineEdit, text: String) -> void:
    edit.grab_focus()
    await get_tree().process_frame
    for i in text.length():
        for pressed in [true, false]:
            var k := InputEventKey.new()
            k.unicode = text.unicode_at(i)
            k.pressed = pressed
            get_tree().root.push_input(k)
            await get_tree().process_frame

## 截图（★ 绝不能加 --headless，否则全黑）
func _shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    img.save_png(ProjectSettings.globalize_path("res://assets/raw/playtest/%s.png" % name))
```

---

## 找控件并点击的四个坑

```gdscript
func _find_btn(node: Node, text: String, prefix: bool) -> Button:
    if node is Button:
        var b := node as Button
        # ① 隐藏或禁用的按钮不能算「找到」！
        #    否则会对着 (0,0) 点，看起来成功了其实什么都没发生，流程会静默空转。
        if b.is_visible_in_tree() and not b.disabled:
            var t := String(b.text)
            if (prefix and t.begins_with(text)) or (not prefix and t == text):
                return b
    for c in node.get_children():
        var r := _find_btn(c, text, prefix)
        if r != null:
            return r
    return null

func _click_text(text: String) -> bool:
    var b := _find_btn(get_tree().root, text, false)
    if b == null:
        b = _find_btn(get_tree().root, text, true)   # ② 先精确再前缀
    if b == null:
        return false
    # ③ 动态创建的按钮要等布局落定，否则 get_global_rect() 是旧值，点击会落空
    await RenderingServer.frame_post_draw
    await get_tree().process_frame
    await _click_at(b.get_global_rect().get_center())
    await get_tree().create_timer(0.3).timeout
    return true
```

**④ 点击不可走格上的物件**：交互点本身通常是柜子/桌子（不可走），
要先走到它**相邻的可行格**，再点它：

```gdscript
# 找到交互点旁边能站的格子
var stand := Vector2i(-1, -1)
for d in [Vector2i(0,1), Vector2i(0,-1), Vector2i(1,0), Vector2i(-1,0)]:
    if grid.is_walkable(pos + d):
        stand = pos + d
        break
```

---

## 等"移动结束"再操作

很多游戏的输入处理里有 `if _overlay.visible or _moving: return` —— **移动中的点击会被直接吞掉**。

```gdscript
await _click_cell(sc, target)
var t := 0.0
while t < 6.0 and bool(sc.get("_moving")):     # 等它真的停下来
    await get_tree().create_timer(0.2).timeout
    t += 0.2
await get_tree().create_timer(0.25).timeout    # 再留一点余量
```

---

## 战斗循环：只在自己的回合计数

**不要**盲目连点。要判断"现在是不是我的回合"，否则敌人回合期间的空转
会白白吃掉轮数上限（曾因此误判成"战斗打不完"）：

```gdscript
var rounds := 0
var idle := 0
while rounds < 70 and idle < 500:
    var bt = sc.get("_battle")
    if bt == null or not is_instance_valid(bt): break
    var cm = bt.get("_cm")
    if cm == null or cm.over: break
    # ★ 关键：只有 input 阶段才算我的回合
    if String(bt.get("_phase")) != "input":
        idle += 1
        await get_tree().create_timer(0.25).timeout
        continue
    rounds += 1
    await _click_text("攻击")
    await get_tree().create_timer(0.45).timeout
    # 弹目标菜单 → 点第一个活着的敌人
    var foe := ""
    for u in cm.units:
        if not u.is_player and u.hp > 0: foe = String(u.name); break
    if foe != "": await _click_text(foe)
    await get_tree().create_timer(1.1).timeout
```

---

## 用日志代替"盯截图"

**不要**靠人工逐张看截图找问题。给关键路径埋结构化日志，跑完直接读：

```gdscript
DebugLog.ev("item", "用药", {"item": "medkit", "hp": [before, after], "max_hp": pu.max_hp})
DebugLog.dump("user://playtest_run.log")     # 落盘
```

```powershell
# 读日志（Windows 上是 UTF-8，PowerShell 默认按 GBK 读会乱码）
Get-Content "$env:APPDATA\Godot\app_userdata\<项目名>\playtest_run.log" -Encoding UTF8 |
  Select-String "item|battle_end"
```

> **实测价值**：一行 `hp:[6,14]` 就说清了"吃药到底有没有回血"，
> 而在此之前靠看二十多张截图，**反而漏掉了"连吃四个急救包血还在掉"这个极明显的 bug**。

---

## 截图验收：对比 sha256

```powershell
Get-ChildItem "assets\raw\playtest" | Get-FileHash -Algorithm SHA256 |
  Sort-Object Hash | Format-Table Hash, Path -AutoSize
```

**两张不同状态的截图哈希相同 → 画面根本没更新。**
这是发现"面板盖住一切""渲染冻结""脚本卡死"最快的手段。

---

## 运行方式

```powershell
$godot = "<Godot 可执行文件>"
# ★ 不要加 --headless（截图会全黑）
# ★ --quit-after 单位是帧，跑完整流程要给足（60fps 下 300000 ≈ 83 分钟）
& $godot --path . res://tests/real_playthrough.tscn --quit-after 300000
```

**动工前先杀掉可能占着窗口的旧进程**：
```powershell
Get-Process -Name "*godot*" -ErrorAction SilentlyContinue | Stop-Process -Force
```

---

## 常见坑速查

| 现象 | 原因 | 解法 |
|---|---|---|
| 截图全黑 | 加了 `--headless` | 去掉该参数 |
| 点了按钮没反应 | 按钮隐藏/禁用时也被 `_find_btn` 找到 | 检查 `is_visible_in_tree()` 和 `disabled` |
| 点击落空 | 动态按钮布局未定就取了 rect | 先 `await RenderingServer.frame_post_draw` |
| 移动中的点击无效 | 被 `if _moving: return` 吞掉 | 等 `_moving` 变 false 再点 |
| 日志跑一半没了 | `--quit-after` 太小被强杀 | 加大该值 |
| 战斗"打不完" | 在敌人回合空转吃掉了轮数 | 只在 `phase == "input"` 时计数 |
| 界面卡在建卡/某一步 | 按钮是灰的（缺必填项） | 检查有没有未填字段、点数没分完 |
| 日志中文乱码 | PowerShell 按 GBK 读 UTF-8 | `Get-Content -Encoding UTF8` |
