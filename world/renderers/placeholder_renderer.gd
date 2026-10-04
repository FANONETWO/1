class_name PlaceholderRenderer
extends GridRenderer
## 占位渲染器：纯色块地形 + 网格线 + 范围高亮 + 单位圆点。
##
## 目的：在任何美术素材（AI 生成像素 / CC0 素材）到位之前，
## 让完整的玩法与全部自动化测试都能跑通。素材到位后只需换成
## PixelGridRenderer / IsoPixelRenderer，本文件可原样保留用于调试。

const COLORS := {
	".": Color(0.16, 0.17, 0.20),
	"#": Color(0.34, 0.32, 0.40),
	"D": Color(0.38, 0.27, 0.16),
	"S": Color(0.22, 0.26, 0.32),
	"E": Color(0.18, 0.52, 0.34),
	"T": Color(0.36, 0.31, 0.24),
	"B": Color(0.24, 0.24, 0.34),
	"C": Color(0.36, 0.31, 0.24),
	"F": Color(0.13, 0.28, 0.17),
	"R": Color(0.31, 0.27, 0.22),
	"H": Color(0.29, 0.28, 0.19),
	"X": Color(0.36, 0.13, 0.13),
}

const MOVE_TINT := Color(0.25, 0.55, 0.95, 0.35)
const ATTACK_TINT := Color(0.95, 0.25, 0.25, 0.35)
const PATH_TINT := Color(1.0, 0.85, 0.3, 0.55)

var _move: Array[Vector2i] = []
var _attack: Array[Vector2i] = []
var _path: Array[Vector2i] = []
var _watch: Array[Vector2i] = []   # 敌人视野预警层（降级渲染器不区分，留接口）
var _units: Dictionary = {}   # uid -> {pos, color, hp, max_hp}

func show_move_range(cells: Array) -> void:
	_move.assign(cells)
	queue_redraw()

func show_attack_range(cells: Array) -> void:
	_attack.assign(cells)
	queue_redraw()

## 敌人视野预警层：降级渲染器只按同一层画（保证接口一致，不崩）
func show_watch_range(cells: Array) -> void:
	_watch.assign(cells)
	queue_redraw()

func show_path(path: Array) -> void:
	_path.assign(path)
	queue_redraw()

func clear_overlays() -> void:
	_move.clear()
	_attack.clear()
	_watch.clear()
	_path.clear()
	queue_redraw()

func spawn_unit(uid: String, pos: Vector2i, color: Color) -> void:
	_units[uid] = {"pos": pos, "color": color, "hp": 0, "max_hp": 0}
	queue_redraw()

func move_unit(uid: String, pos: Vector2i) -> void:
	if _units.has(uid):
		_units[uid]["pos"] = pos
		queue_redraw()

func set_unit_hp(uid: String, hp: int, max_hp: int) -> void:
	if _units.has(uid):
		_units[uid]["hp"] = hp
		_units[uid]["max_hp"] = max_hp
		queue_redraw()

func despawn_unit(uid: String) -> void:
	_units.erase(uid)
	queue_redraw()

func clear_units() -> void:
	_units.clear()
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	# 地形色块
	for y in grid.rows():
		for x in grid.cols():
			var pos := Vector2i(x, y)
			draw_rect(cell_rect(pos), COLORS.get(grid.char_at(pos), Color.MAGENTA))
	# 网格线
	var line_col := Color(0, 0, 0, 0.25)
	for x in grid.cols() + 1:
		var px := origin.x + x * tile_size
		draw_line(Vector2(px, origin.y), Vector2(px, origin.y + grid.rows() * tile_size), line_col, 1.0)
	for y in grid.rows() + 1:
		var py := origin.y + y * tile_size
		draw_line(Vector2(origin.x, py), Vector2(origin.x + grid.cols() * tile_size, py), line_col, 1.0)
	# 范围覆盖层
	for p in _move:
		draw_rect(cell_rect(p), MOVE_TINT)
	for p in _attack:
		draw_rect(cell_rect(p), ATTACK_TINT)
	for p in _path:
		var c := cell_center(p)
		draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), PATH_TINT)
	# 单位
	for uid in _units:
		var u: Dictionary = _units[uid]
		var c := cell_center(u["pos"])
		draw_circle(c, tile_size * 0.32, u["color"])
		if int(u["max_hp"]) > 0:
			var ratio := clampf(float(u["hp"]) / float(u["max_hp"]), 0.0, 1.0)
			var w := tile_size * 0.7
			var bar := Rect2(c + Vector2(-w * 0.5, -tile_size * 0.45), Vector2(w, 3))
			draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
			draw_rect(Rect2(bar.position, Vector2(w * ratio, 3)), Color(0.35, 0.85, 0.4))
	# 高亮当前选中单位的所在格
	if not _units.is_empty():
		draw_rect(cell_rect(_units.values()[0]["pos"]), Color(1, 1, 1, 0.15))
