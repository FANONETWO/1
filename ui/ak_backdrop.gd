class_name AkBackdrop
extends Control
## 方舟式背景：近黑底 + 细网格 + 右上斜向色带 + 底部渐隐压暗。
## 纯 _draw、零贴图 —— 和项目「程序化生成、不依赖外部素材」的纪律一致。

@export var grid_step: float = 48.0
@export var show_band: bool = true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	draw_rect(Rect2(0, 0, w, h), AkTheme.BG)
	# 细网格：极低对比，只用来给画面一点「工程图」的质感
	var grid := Color(1, 1, 1, 0.020)
	var x := grid_step
	while x < w:
		draw_line(Vector2(x, 0), Vector2(x, h), grid, 1.0)
		x += grid_step
	var y := grid_step
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), grid, 1.0)
		y += grid_step
	if show_band:
		# 右上斜向色带（45°），只比底色亮一点点
		var pts := PackedVector2Array([
			Vector2(w * 0.54, 0), Vector2(w, 0), Vector2(w, h * 0.62), Vector2(w * 0.80, h * 0.62),
		])
		draw_colored_polygon(pts, Color(0.105, 0.125, 0.15, 0.75))
		var ac := AkTheme.ACCENT
		draw_line(pts[0], pts[3], Color(ac.r, ac.g, ac.b, 0.13), 1.0, true)
	# 顶部压暗
	draw_rect(Rect2(0, 0, w, 56), Color(0, 0, 0, 0.30))
	# 底部渐隐（多层递减 alpha，做出渐变感）
	for i in 14:
		var a := 0.055 * float(14 - i) / 14.0
		draw_rect(Rect2(0, h - 84 + float(i) * 6.0, w, 7), Color(0, 0, 0, a))
