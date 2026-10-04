# UI 设计规范（明日方舟风格）

> 适用：开局流程（主菜单 / 角色创建 / 主神空间）。
> 实现：`ui/ak_theme.gd`（配色与主题）、`ui/ak_frame.gd`（斜切面板）、`ui/ak_backdrop.gd`（网格背景）。
> 战斗与探索层仍是像素风（`ui/pixel_theme.gd`）—— 那是**刻意的**：开局是「主神终端」，进副本才是像素世界。

---

## 一、三条纪律

1. **底色永远近黑**。要区分区域就抬「面板」的亮度，不要把整块刷成灰色
2. **画面上只允许一个强调色在动**（选中 / 悬停 / 焦点），其余保持无彩
3. **圆角一律为 0**。工业感来自直角、斜切与角标；一个圆角就会立刻变成另一种风格

## 二、配色

| 用途 | 常量 | 值 |
|---|---|---|
| 页面底 | `AkTheme.BG` | `#0a0c0e` |
| 主面板 | `AkTheme.PANEL` | `#15191e` |
| 面板（悬停/选中） | `AkTheme.PANEL_HI` | `#1d232a` |
| 凹陷底（输入框/列表） | `AkTheme.PANEL_SUNK` | `#0f1216` |
| 分隔线 | `AkTheme.LINE` | `#262c33` |
| 主文字 | `AkTheme.TEXT` | `#e8edf2` |
| 次要文字 | `AkTheme.TEXT_DIM` | `#8b959e` |
| 弱化文字（编号/标注） | `AkTheme.TEXT_FAINT` | `#565f67` |
| **结构 / 选中** | `AkTheme.ACCENT` | `#19c8ff` 青蓝 |
| **主行动 / 数值** | `AkTheme.AMBER` | `#ffc02e` 琥珀 |
| 危险 | `AkTheme.DANGER` | `#ff4a4a` |

用法约定：
- **青蓝 = 结构**：分区编号、竖线、段式条、「标签」文字、面板角标
- **琥珀 = 主行动与关键数值**：确认键、剩余点数、属性值、奖励点
- **不要**用红绿做装饰，它们只表示危险 / 通过

## 三、几何

| 元素 | 规则 |
|---|---|
| 面板 | `AkFrame`：左上斜切 18px + 四角 L 形标注线（长 22） |
| 斜切 | 只有**大面板**切角；行内小控件（`−` `+`）不切 |
| 角标 | 贴在斜切那一侧，用青蓝 2px |
| 斜纹 | 只有**主标题面板**开 `draw_hatch`，其余关掉（很吵） |
| 背景 | `AkBackdrop`：48px 细网格（alpha 0.02）+ 右上 45° 色带 + 底部渐隐 |
| 间距 | 面板之间 16；面板内边距 18/16；行间距 2（密集列表）|

## 四、排版

- **编号分区**：`01 ｜ 属性　ATTRIBUTES` —— 用 `AkTheme.section("01", "属性", "ATTRIBUTES")`
  - 编号与竖线用青蓝，名称用主文字，英文用 `TEXT_FAINT` 小字（底部对齐）
- **英文标注拉字距**：`AkTheme.spaced("GODSPACE TERMINAL")` —— Godot 的 Label 没有 letter-spacing，只能插空格，但效果最像
- **字号层级**：标题 62 / 分区 24 / 正文 15 / 小字 12 / 标注 10
- **左对齐，不居中**：所有信息左对齐；只有「主行动按钮」靠右
- **不加文字描边**：像素风才需要描边，扁平排版加描边会立刻变成网页游戏观感

## 五、组件用法

```gdscript
# 场景根
theme = AkTheme.build()
add_child(AkBackdrop.new())

# 面板（能装内容）
var panel := AkFrame.new()
panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
panel.cut = 18.0
panel.add_theme_constant_override("margin_left", 18)     # 不设的话内容会贴边
panel.add_theme_constant_override("margin_top", 16)
add_child(panel)
panel.add_child(内容)

# 分区标题
v.add_child(AkTheme.section("01", "属性", "ATTRIBUTES"))

# 行内小按钮 —— 必须调 compact()，否则主题给大按钮留的 pad 会把行撑到 ~50px
var minus := Button.new()
minus.text = "−"
AkTheme.compact(minus)

# 主行动按钮：琥珀色字 + 靠右
confirm.add_theme_color_override("font_color", AkTheme.AMBER)
```

## 六、踩过的坑

1. **行高失控**：`AkTheme.build()` 里给 Button 的内边距（14/8）对行内 `−`/`+` 太大，
   九个属性 + 十二个技能直接溢出屏幕、压住底部模式行 → 行内按钮一律 `AkTheme.compact()`
2. **三栏内容溢出**：`HBoxContainer` 的子节点会被内容撑高并溢出容器（不会自动裁剪）。
   密集列表要么压行高，要么给 `ScrollContainer`
3. **按钮文字不要加编号**：测试与实机脚本按文字找按钮（精确或前缀匹配）。
   编号请放在按钮**左边独立的 Label** 里（见主菜单 `_build_menu`）
4. **改完必跑**：`pwsh -File tools/run_tests.ps1`（34 项，其中 `ui_flow_driver`/`flow_driver` 会真实点这些界面）
