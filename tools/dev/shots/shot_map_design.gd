extends Node2D
## 地图设计方案样例渲染（窗口模式）：
##   godot --path . res://tools/dev/shots/shot_map_design.tscn --quit-after 400
##
## 展示「惊变公寓一层」的重设计：房间语义化 + 环形动线 + 窄口战术位 +
## 掩体线（T/C/B）+ 高地（H，命中+10）+ 危险区（X，每回合−2 HP）。

## RE2 箱庭式一层：北侧三房 → 横向主走廊 → 中央大堂 → 南侧出口/楼梯，
## 左右两个门构成**环形动线**（可绕圈、可包抄、可撤退）。
const MAP_NEW: Array[String] = [
	"####################",
	"#CC.#....HH.#..B...#",
	"#...D.......D......#",
	"#...#.......#..C...#",
	"##D##.......##D#####",
	"#..................#",
	"#...####..####.....#",
	"#...#........#.....#",
	"#...#...X....#..T..#",
	"##D##........##D####",
	"#....D..E....#..S..#",
	"####################",
]

## 房间标注：(名字, 格子坐标, 颜色)
const LABELS := [
	["储物间", Vector2i(1, 1), Color(0.7, 0.85, 1.0)],
	["值班室(高地)", Vector2i(6, 1), Color(0.6, 1.0, 0.7)],
	["客房", Vector2i(13, 1), Color(1.0, 0.9, 0.7)],
	["主走廊", Vector2i(7, 5), Color(1.0, 0.8, 0.5)],
	["大堂 · 中央", Vector2i(2, 7), Color(0.9, 0.8, 1.0)],
	["出口", Vector2i(8, 10), Color(0.6, 1.0, 0.9)],
	["楼梯间", Vector2i(16, 10), Color(0.85, 0.85, 0.95)],
]

func _ready() -> void:
	var grid := GridWorld.new()
	grid.setup(MAP_NEW)
	var r := PixelGridRenderer.new()
	r.bind(grid)
	r.origin = Vector2(24, 30)
	add_child(r)

	for item in LABELS:
		var lb := Label.new()
		lb.text = String(item[0])
		lb.add_theme_font_size_override("font_size", 14)
		lb.modulate = item[2]
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var c: Vector2 = r.cell_center(item[1])
		lb.position = c - Vector2(40, 9)
		lb.size = Vector2(80, 18)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Label 需要 Control 父级：放进一个覆盖层
		if _overlay == null:
			_overlay = Control.new()
			_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_overlay)
		_overlay.add_child(lb)

	# 图例
	_legend()

	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://assets/raw/_probe/map_design_v2.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] 地图设计样例：", path)
	get_tree().quit(0)

var _overlay: Control

func _legend() -> void:
	if _overlay == null:
		_overlay = Control.new()
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overlay)
	var lines := [
		"T/C/B 掩体：移动2 · 防御+1",
		"H 高地：命中+10",
		"X 危险区：每回合-2 HP",
		"R 废墟：回避+10 防御+1",
		"D 门：1格窄口 = 防守点",
	]
	var y := 30.0
	for t in lines:
		var lb := Label.new()
		lb.text = String(t)
		lb.add_theme_font_size_override("font_size", 14)
		lb.modulate = Color(0.9, 0.95, 1.0, 0.9)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.position = Vector2(1010, y)
		lb.size = Vector2(260, 20)
		_overlay.add_child(lb)
		y += 24.0
