class_name PixelTheme
extends RefCounted
## 程序化生成的像素风 UI 主题：直角边框、深色底、亮色描边、无圆角。
##
## 用法：在场景根 Control 的 _ready 里 `theme = PixelTheme.build()`，
## Theme 会传播给全部子节点；代码里的 add_theme_font_size_override 仍然生效。
##
## 为什么程序化：项目零外部资源，不需要 .tres 主题文件，也不会被美术管线阻塞。

## 对比度刻意调高一档：深色背景上控件必须"跳出来"，否则界面看不清
const BG := Color(0.15, 0.17, 0.23)
const BG_HOVER := Color(0.26, 0.32, 0.44)
const BG_PRESSED := Color(0.10, 0.12, 0.17)
const BG_DISABLED := Color(0.12, 0.12, 0.15)
const BORDER := Color(0.60, 0.74, 0.95)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.52, 0.55, 0.62)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.9)

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16

	# 按钮：三态 + 禁用 + 焦点
	t.set_stylebox("normal", "Button", _box(BG, BORDER, 2))
	t.set_stylebox("hover", "Button", _box(BG_HOVER, BORDER.lightened(0.25), 2))
	t.set_stylebox("pressed", "Button", _box(BG_PRESSED, BORDER.darkened(0.25), 2))
	t.set_stylebox("disabled", "Button", _box(BG_DISABLED, TEXT_DIM, 2))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BORDER.lightened(0.45), 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", BORDER.lightened(0.3))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", 2)

	# 面板
	t.set_stylebox("panel", "PanelContainer", _box(BG, BORDER.darkened(0.35), 2))
	t.set_stylebox("panel", "Panel", _box(BG, BORDER.darkened(0.35), 2))

	# 文本：加黑色描边，保证压在任意背景上都清晰
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", OUTLINE)
	t.set_constant("outline_size", "Label", 3)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", OUTLINE)
	t.set_constant("outline_size", "RichTextLabel", 2)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)

	# 输入框
	t.set_stylebox("normal", "LineEdit", _box(BG_PRESSED, BORDER, 2))
	t.set_stylebox("focus", "LineEdit", _box(BG_PRESSED, BORDER.lightened(0.35), 2))

	# 容器与滚动条（保持克制，避免抢视觉）
	t.set_stylebox("panel", "TabContainer", _box(BG, BORDER.darkened(0.35), 2))
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)

	return t

## 直角像素风样式盒：无圆角、2px 边框、固定内边距
static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
