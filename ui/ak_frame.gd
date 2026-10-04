class_name AkFrame
extends MarginContainer
## 方舟式框架：左上斜切 + 四角标注线 + 可选斜纹。
## 继承 MarginContainer —— 既能当纯装饰垫底，也能直接当面板装内容
## （装内容时记得设 margin_* 常量，否则内容会贴着边框）。
##
## 用法：
##   var f := AkFrame.new()
##   f.set_anchors_preset(Control.PRESET_FULL_RECT)   # 或给 size
##   add_child(f)
##   f.add_child(内容)

@export var fill_color: Color = AkTheme.PANEL:
	set(v):
		fill_color = v
		queue_redraw()
@export var border_color: Color = AkTheme.LINE:
	set(v):
		border_color = v
		queue_redraw()
@export var accent_color: Color = AkTheme.ACCENT:
	set(v):
		accent_color = v
		queue_redraw()
## 左上斜切边长（0 = 切角关闭，用于小控件）
@export var cut: float = 18.0:
	set(v):
		cut = v
		queue_redraw()
@export var draw_brackets: bool = true:
	set(v):
		draw_brackets = v
		queue_redraw()
## 右上角斜纹装饰（大标题面板用，平级面板不要开，否则很吵）
@export var draw_hatch: bool = false:
	set(v):
		draw_hatch = v
		queue_redraw()
@export var bracket_len: float = 22.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	var c := minf(cut, minf(w, h) * 0.5)
	var pts := PackedVector2Array([
		Vector2(c, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h), Vector2(0.0, c),
	])
	draw_colored_polygon(pts, fill_color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border_color, 1.0, true)
	# 斜切那一笔用强调色描出来 —— 整块面板的「精神」就在这一条斜线上
	if c > 0.0:
		draw_line(Vector2(0.0, c), Vector2(c, 0.0), accent_color, 1.6, true)
	if draw_hatch:
		var hcol := Color(accent_color.r, accent_color.g, accent_color.b, 0.30)
		for i in 7:
			var hx := w - 96.0 + float(i) * 10.0
			draw_line(Vector2(hx, 0.0), Vector2(hx + 18.0, 18.0), hcol, 2.0, true)
	if not draw_brackets:
		return
	var bl := bracket_len
	var col := accent_color
	# 左上（贴着斜切）
	draw_line(Vector2(c + 5, 0.0), Vector2(c + 5 + bl, 0.0), col, 2.0, true)
	draw_line(Vector2(c, 5.0), Vector2(c, 5.0 + bl), col, 2.0, true)
	# 右上
	draw_line(Vector2(w - 5 - bl, 0.0), Vector2(w - 5, 0.0), col, 2.0, true)
	draw_line(Vector2(w - 1.5, 5.0), Vector2(w - 1.5, 5.0 + bl), col, 2.0, true)
	# 左下
	draw_line(Vector2(5.0, h - 1.5), Vector2(5.0 + bl, h - 1.5), col, 2.0, true)
	draw_line(Vector2(0.0, h - 5 - bl), Vector2(0.0, h - 5), col, 2.0, true)
	# 右下
	draw_line(Vector2(w - 5 - bl, h - 1.5), Vector2(w - 5, h - 1.5), col, 2.0, true)
	draw_line(Vector2(w - 1.5, h - 5 - bl), Vector2(w - 1.5, h - 5), col, 2.0, true)
