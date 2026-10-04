class_name GridRenderer
extends Node2D
## 渲染层接口（阶段 A 地基）。
##
## 职责边界：只**读取**逻辑层（GridWorld）的数据并画出来，绝不参与规则计算。
## 子类可自由替换，逻辑与测试零改动：
##   PlaceholderRenderer —— 色块占位（素材未就位也能完整跑通玩法）
##   PixelGridRenderer   —— 16×16 像素 tile（火纹式方格俯视观感）
##   IsoPixelRenderer    —— 等距像素（博德之门 / 开拓者式观感）

## 占位期用 32px 方便观察；接入像素素材后改为 16px + 320×180 基准视口。
var tile_size: float = 32.0
var origin: Vector2 = Vector2(24, 24)
var grid: GridWorld = null

func bind(g: GridWorld) -> void:
	grid = g
	queue_redraw()

func cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(pos.x, pos.y) * tile_size, Vector2(tile_size, tile_size))

func cell_center(pos: Vector2i) -> Vector2:
	return origin + Vector2(pos.x * tile_size + tile_size * 0.5, pos.y * tile_size + tile_size * 0.5)

func point_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / tile_size), floori((p.y - origin.y) / tile_size))

# ——— 兼容旧 IsoMap 接口：既有场景只需替换「构造地图」的几行即可平滑迁移 ———

var _highlight: Dictionary = {}   # {"pos": Vector2i, "color": Color}

## 格子中心世界坐标（IsoMap 旧名）
func grid_to_world(pos: Vector2i) -> Vector2:
	return cell_center(pos)

## 屏幕坐标 → 格子（IsoMap 旧名）
func grid_at_point(screen: Vector2) -> Vector2i:
	return point_to_cell(screen)

func is_walkable(pos: Vector2i) -> bool:
	return grid != null and grid.is_walkable(pos)

func in_bounds(pos: Vector2i) -> bool:
	return grid != null and grid.in_bounds(pos)

func char_at(pos: Vector2i) -> String:
	return grid.char_at(pos) if grid != null else "#"

## 单格高亮（IsoMap 旧名）
func set_highlight(pos: Vector2i, color: Color) -> void:
	_highlight = {"pos": pos, "color": color}
	queue_redraw()

func clear_highlight() -> void:
	_highlight = {}
	queue_redraw()

## 路径预览（IsoMap 旧名，转发到覆盖层）
func set_path(path: Array[Vector2i]) -> void:
	show_path(path)

func clear_path() -> void:
	var empty: Array[Vector2i] = []
	show_path(empty)

# ——— 覆盖层（子类实现）———

func show_move_range(_cells: Array) -> void:
	pass

func show_attack_range(_cells: Array) -> void:
	pass

## 敌人视野「预警层」（暗色）：表示「那边有眼睛，但暂时没看见你」
func show_watch_range(_cells: Array) -> void:
	pass

func show_path(_path: Array) -> void:
	pass

func clear_overlays() -> void:
	pass

# ——— 单位（子类实现）———

func spawn_unit(_uid: String, _pos: Vector2i, _color: Color) -> void:
	pass

func move_unit(_uid: String, _pos: Vector2i) -> void:
	pass

func set_unit_hp(_uid: String, _hp: int, _max_hp: int) -> void:
	pass

func despawn_unit(_uid: String) -> void:
	pass

func clear_units() -> void:
	pass
