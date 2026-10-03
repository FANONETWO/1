extends Node2D
## 地图像素预览：用 PixelGridRenderer 渲染「惊变公寓」阶段 1，截图后退出。
##
## 必须用窗口模式运行（headless 下 viewport 没有可读纹理）：
##   godot --path . res://tests/map_preview.tscn --quit-after 300
##
## 用途：在真实像素素材下检查地图观感、单位尺寸与配色是否协调。

const OUT_PATH := "res://assets/raw/_probe/map_preview_w1.png"
const CELL := 48.0   # 与 PixelGridRenderer 的 16 × 3 保持一致

func _ready() -> void:
	var world := Worlds.get_world("w1_apartment")
	if world == null:
		push_error("[preview] 找不到世界 w1_apartment")
		get_tree().quit(1)
		return
	var stage: Dictionary = world.stage(0)
	var grid := world.make_grid(0)

	# 1) 地形
	var renderer := PixelGridRenderer.new()
	renderer.bind(grid)
	add_child(renderer)

	# 2) 交互点与 NPC 标记（在地形之上、单位之下）
	for sid in stage.get("spots", {}):
		_add_marker(stage["spots"][sid]["pos"], Color(0.95, 0.82, 0.35, 0.9), 12.0)
	for nid in stage.get("npcs", {}):
		_add_marker(stage["npcs"][nid]["pos"], Color(0.55, 0.72, 0.95, 0.9), 14.0)

	# 3) 单位
	_add_sprite("res://assets/sprites/w1/zombie_idle.png", grid, Vector2i(4, 2))
	_add_sprite("res://assets/sprites/w1/zombie_idle.png", grid, Vector2i(2, 7))
	_add_sprite("res://assets/sprites/w1/player_idle.png", grid, stage.get("spawn", Vector2i(2, 2)))

	# 4) 截图（等两帧让纹理与绘制就绪）
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(OUT_PATH)
	img.save_png(abs_path)
	print("[preview] 已保存 ", abs_path, " 尺寸=", img.get_size(), " 素材已载=", renderer.loaded_count(), " 缺失=", renderer.missing_chars())
	get_tree().quit(0)

## 用 16×24 的像素 sprite 站在格子上（脚底对齐格底）
func _add_sprite(path: String, _grid: GridWorld, pos: Vector2i) -> void:
	if not ResourceLoader.exists(path):
		_add_marker(pos, Color(0.9, 0.3, 0.3, 0.9), 16.0)
		return
	var tex: Texture2D = load(path)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2(3.0, 3.0)   # 16×24 → 48×72
	s.position = Vector2(
		pos.x * CELL + CELL * 0.5 - tex.get_width() * 1.5,
		pos.y * CELL + CELL - tex.get_height() * 3.0
	)
	add_child(s)

func _add_marker(pos: Vector2i, color: Color, size: float) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(0, -size), Vector2(size, 0), Vector2(0, size), Vector2(-size, 0),
	])
	p.color = color
	p.position = Vector2(pos.x * CELL + CELL * 0.5, pos.y * CELL + CELL * 0.5)
	add_child(p)
