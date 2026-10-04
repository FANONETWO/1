class_name AkTheme
extends RefCounted
## 明日方舟风格的 UI 主题：冷色近黑底、全直角、细线分隔、青蓝主色 + 琥珀强调。
## 它靠**排版层级、留白与几何切角**拉开信息层次，而不是靠圆角、渐变和投影。
##
## 用法与 PixelTheme 一致：场景根 Control 的 _ready 里 `theme = AkTheme.build()`。
##
## 三条纪律（改这个文件时请守住）：
##   1. 底色永远近黑。要区分区域就抬 **面板** 的亮度，不要把整块刷灰
##   2. 画面上只允许一个强调色在「动」（选中 / 悬停 / 焦点），其余保持无彩
##   3. 圆角一律为 0。工业感来自直角、斜切与角标，圆角会立刻变成另一种风格

# ——— 配色 ———
const BG := Color("0a0c0e")            # 页面底
const BG_DEEP := Color("06080a")       # 更深的角落（暗角）
const PANEL := Color("15191e")         # 主面板
const PANEL_HI := Color("1d232a")      # 悬停 / 选中面板
const PANEL_SUNK := Color("0f1216")    # 凹陷区（列表底、输入框）
const LINE := Color("262c33")          # 常规分隔线
const LINE_HI := Color("3a444e")       # 强调分隔线
const TEXT := Color("e8edf2")          # 主文字
const TEXT_DIM := Color("8b959e")      # 次要文字
const TEXT_FAINT := Color("565f67")    # 弱化文字（标注、编号）
const ACCENT := Color("19c8ff")        # 青蓝：结构 / 选中
const AMBER := Color("ffc02e")         # 琥珀：开始 / 确认
const DANGER := Color("ff4a4a")        # 危险 / 阵亡
const OK := Color("4ad991")            # 通过 / 健康

# ——— 字号层级 ———
const FS_TITLE := 62
const FS_H1 := 24
const FS_H2 := 19
const FS_BODY := 15
const FS_SMALL := 12
const FS_TINY := 10

## 等距拉字距（Godot 的 Label 没有 letter-spacing，只能手工插空格）
## 用在英文标注上，是「方舟味」最容易出效果的一招
static func spaced(s: String, gap: int = 1) -> String:
	var pad := " ".repeat(maxi(1, gap))
	var out := ""
	for i in s.length():
		out += s[i]
		if i < s.length() - 1:
			out += pad
	return out

## 通用面板样式：直角 + 单像素描边
static func box(fill: Color, border: Color, border_w: int = 1,
		pad_h: int = 14, pad_v: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb

## 只有左侧一条粗边（做「选项条」用；StyleBoxFlat 只能单色边框，所以左侧单独加粗）
static func box_left_bar(fill: Color, border: Color, bar_color: Color) -> StyleBoxFlat:
	var sb := box(fill, border, 1)
	sb.border_width_left = 4
	# StyleBoxFlat 的边框是单色 → 左粗边会跟其余边同色，所以真正的高亮条
	# 交给 ui/ak_bar.gd 那个自绘控件去画，这里只负责「左边留出位置」
	sb.bg_color = fill
	sb.border_color = border
	return sb

## 行内小按钮（属性/技能的 − +）：把内边距压到最小。
## 不这么做的话，主题里给大按钮留的 pad（14/8）会把每一行撑到 ~50px 高，
## 九个属性加十二个技能直接溢出屏幕、压住底部模式行。
static func compact(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(PANEL, LINE, 1, 8, 2))
	b.add_theme_stylebox_override("hover", box(PANEL_HI, ACCENT, 1, 8, 2))
	b.add_theme_stylebox_override("pressed", box(PANEL_SUNK, AMBER, 1, 8, 2))
	b.add_theme_stylebox_override("disabled", box(Color("111417"), Color("1e2429"), 1, 8, 2))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), ACCENT, 1, 8, 2))

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_BODY

	# ——— 按钮：直角、细边；悬停时抬底色并点亮边框 ———
	t.set_stylebox("normal", "Button", box(PANEL, LINE, 1, 14, 8))
	t.set_stylebox("hover", "Button", box(PANEL_HI, ACCENT, 1, 14, 8))
	t.set_stylebox("pressed", "Button", box(PANEL_SUNK, AMBER, 1, 14, 8))
	t.set_stylebox("disabled", "Button", box(Color("111417"), Color("1e2429"), 1, 14, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 1, 14, 8))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_color("font_focus_color", "Button", TEXT)
	# 不描边：方舟是扁平排版风，黑色描边会立刻变成「网页游戏」
	t.set_constant("outline_size", "Button", 0)

	# ——— 面板 ———
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 1))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 1))

	# ——— 文字：同样不描边（对比度靠底色保证） ———
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 0)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("outline_size", "RichTextLabel", 0)

	# ——— 输入框：凹陷底 + 细线，焦点时青蓝 ———
	t.set_stylebox("normal", "LineEdit", box(PANEL_SUNK, LINE, 1, 10, 8))
	t.set_stylebox("focus", "LineEdit", box(PANEL_SUNK, ACCENT, 1, 10, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)

	# ——— 滚动条：细长条，不要圆头 ———
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color("10131700")
	groove.set_corner_radius_all(0)
	t.set_stylebox("scroll", "VScrollBar", groove)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color("3a444e")
	grabber.set_corner_radius_all(0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	var grabber_hi := StyleBoxFlat.new()
	grabber_hi.bg_color = ACCENT
	grabber_hi.set_corner_radius_all(0)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber_hi)

	# ——— 分隔 ———
	var sep := StyleBoxFlat.new()
	sep.bg_color = LINE
	sep.set_corner_radius_all(0)
	sep.content_margin_top = 0
	sep.content_margin_bottom = 0
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)

	return t

# ——— 排版小工具（各界面共用，避免每处都写一遍 override）———

static func title(text: String, size: int = FS_H1, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func dim(text: String, size: int = FS_SMALL,
		color: Color = TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## 分区标题：`01 ── 装备档案`（方舟最典型的一处排版）
static func section(index: String, name: String, en: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var num := dim(index, FS_H2, ACCENT)
	row.add_child(num)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(3, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var nm := title(name, FS_H2)
	row.add_child(nm)
	if en != "":
		var e := dim(spaced(en, 1), FS_TINY, TEXT_FAINT)
		e.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(e)
	return row
