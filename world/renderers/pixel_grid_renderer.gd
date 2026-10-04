class_name PixelGridRenderer
extends GridRenderer
## 像素渲染器：用真实像素 tile 绘制方格地图（16×16 素材 × 整数倍放大）。
##
## 职责边界与 GridRenderer 一致：只读 GridWorld 的地形字符，不参与任何规则计算。
## 素材缺失时自动回退为色块，因此美术未铺满时游戏仍可完整运行。
##
## 素材规格：assets/tiles/<world>/*.png，16×16、无抗锯齿、≤24 色。
## 像素风关键：项目设置 default_texture_filter = Nearest + 整数倍缩放。

const TILE_SRC := 16      # 素材原始边长（像素）
const ZOOM := 3           # 屏幕放大倍数 → 每格 48px

## 地形字符 -> 素材路径（与 GridWorld.TERRAIN 的字符一一对应）
var tile_paths: Dictionary = {
	".": "res://assets/tiles/w1/floor.png",
	"#": "res://assets/tiles/w1/wall.png",
	"D": "res://assets/tiles/w1/door.png",
	"S": "res://assets/tiles/w1/stairs.png",
	"E": "res://assets/tiles/w1/exit.png",
	"T": "res://assets/tiles/w1/table.png",
	"B": "res://assets/tiles/w1/bed.png",
	"C": "res://assets/tiles/w1/cabinet.png",
}

const FALLBACK := {
	".": Color(0.16, 0.17, 0.20),
	"#": Color(0.34, 0.32, 0.40),
	"D": Color(0.38, 0.27, 0.16),
	"S": Color(0.22, 0.26, 0.32),
	"E": Color(0.18, 0.52, 0.34),
	"T": Color(0.36, 0.31, 0.24),
	"B": Color(0.24, 0.24, 0.34),
	"C": Color(0.36, 0.31, 0.24),
	"F": Color(0.16, 0.30, 0.20),
	"R": Color(0.30, 0.28, 0.26),
	"H": Color(0.42, 0.36, 0.20),
	"X": Color(0.42, 0.16, 0.14),
}

var _tex: Dictionary = {}          # 地形字符 -> Texture2D
var _missing: Array[String] = []   # 缺失素材的地形字符（供诊断）
var _move: Array[Vector2i] = []    # 可移动范围高亮
var _attack: Array[Vector2i] = []  # 可攻击范围高亮 / 会立刻发现你的敌人视野
var _watch: Array[Vector2i] = []   # 敌人视野「预警层」：暗红，提醒那边有眼睛但暂时安全
var _path: Array[Vector2i] = []    # 路径预览
var _deco: Array = []              # 装饰层：[{pos, name, off}]，铺在地板之上、覆盖层之下
var _deco_tex: Dictionary = {}     # 装饰名 -> Texture2D
var _visible: Dictionary = {}      # 视野内的格子（战场迷雾）：不在其中的压暗
var _seen: Dictionary = {}         # 已探索记忆（C5）：去过的地方留暗色轮廓，未去过的更黑
var _fog_on := false               # 迷雾开关

const DECO_NAMES: Array[String] = [
	"blood_pool", "blood_smear", "cardboard", "glass_shards",
	"trash_papers", "corpse", "water_stain", "rubble_pile",
]

const MOVE_TINT := Color(0.25, 0.55, 0.95, 0.38)
const ATTACK_TINT := Color(0.95, 0.25, 0.25, 0.38)
## 预警层比危险层暗一档：看得见「有眼睛」，但不会和「会被发现」的格子混淆
const WATCH_TINT := Color(0.72, 0.22, 0.28, 0.20)
const PATH_TINT := Color(1.0, 0.85, 0.3, 0.6)

# ——— 覆盖层（GridRenderer 接口实现）———

func show_move_range(cells: Array) -> void:
	_move.assign(cells)
	queue_redraw()

func show_attack_range(cells: Array) -> void:
	_attack.assign(cells)
	queue_redraw()

## 敌人视野预警层（暗红）：只有「那边有眼睛」的信息量，不代表会被发现
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
	_highlight = {}
	queue_redraw()

func _ready() -> void:
	tile_size = float(TILE_SRC * ZOOM)
	_load_textures()
	_load_deco_textures()

func _load_deco_textures() -> void:
	_deco_tex.clear()
	for n in DECO_NAMES:
		var p := "res://assets/sprites/w1/deco/%s.png" % n
		if ResourceLoader.exists(p):
			var r: Resource = load(p)
			if r is Texture2D:
				_deco_tex[n] = r

## 设置装饰层（场景载入箱庭时调用）。items: [{pos:Vector2i, name:String, off:Vector2}]
func set_deco(items: Array) -> void:
	_deco = items
	queue_redraw()

func deco_count() -> int:
	return _deco.size()

## 战场迷雾：只有这些格子保持明亮，其余压暗（恐怖感的主要来源）
## 同时把这些格子记进「已探索记忆」—— 走过的房间回头还能看见暗色轮廓，不至于迷路。
func set_visible_cells(cells: Array, enable: bool = true) -> void:
	_visible.clear()
	for p in cells:
		var v := Vector2i(p)
		_visible[v] = true
		_seen[v] = true
	_fog_on = enable
	queue_redraw()

## 清空已探索记忆（切换箱庭时调用：每个房间的记忆互相独立）
func reset_seen() -> void:
	_seen.clear()
	queue_redraw()

## 已记住的格子数（供测试与诊断）
func seen_count() -> int:
	return _seen.size()

## 某格是否已被探索过
func is_seen(p: Vector2i) -> bool:
	return _seen.has(p)

func fog_enabled() -> bool:
	return _fog_on

func _load_textures() -> void:
	_tex.clear()
	_missing.clear()
	for ch in tile_paths:
		var p := String(tile_paths[ch])
		if ResourceLoader.exists(p):
			var res: Resource = load(p)
			if res is Texture2D:
				_tex[ch] = res
				continue
		_missing.append(String(ch))

## 素材就绪情况（供测试与诊断）
func loaded_count() -> int:
	return _tex.size()

func missing_chars() -> Array[String]:
	return _missing.duplicate()

func _draw() -> void:
	if grid == null:
		return
	for y in grid.rows():
		for x in grid.cols():
			var pos := Vector2i(x, y)
			var ch := grid.char_at(pos)
			var rect := cell_rect(pos)
			if _tex.has(ch):
				draw_texture_rect(_tex[ch], rect, false)
			else:
				draw_rect(rect, FALLBACK.get(ch, Color.MAGENTA))
	# 装饰层：地板上的血迹 / 纸箱 / 碎玻璃 —— 消除「每格都一样」的棋盘感。
	# 画在 tile 之上、范围高亮之下；略小于格子并带随机偏移，避免整齐得像贴纸。
	for d in _deco:
		var tex: Texture2D = _deco_tex.get(String(d.get("name", "")), null)
		if tex == null:
			continue
		var r := cell_rect(Vector2i(d["pos"]))
		var s := tile_size * 0.94
		var off: Vector2 = d.get("off", Vector2.ZERO)
		var rc := Rect2(r.position + Vector2((tile_size - s) * 0.5, (tile_size - s) * 0.5) + off,
			Vector2(s, s))
		draw_texture_rect(tex, rc, false)

	# 极细网格线，帮助辨认可走格（像素风下保持克制）
	var line_col := Color(0, 0, 0, 0.18)
	for x in grid.cols() + 1:
		var px := origin.x + x * tile_size
		draw_line(Vector2(px, origin.y), Vector2(px, origin.y + grid.rows() * tile_size), line_col, 1.0)
	for y in grid.rows() + 1:
		var py := origin.y + y * tile_size
		draw_line(Vector2(origin.x, py), Vector2(origin.x + grid.cols() * tile_size, py), line_col, 1.0)
	# 覆盖层：移动范围 / 攻击范围 / 路径 / 单格高亮
	for p in _move:
		draw_rect(cell_rect(p), MOVE_TINT)
	# 预警层（暗红）留在迷雾**之下**：只有你看得见的区域才给提示，恐怖感不破
	for p in _watch:
		draw_rect(cell_rect(p), WATCH_TINT)
	for p in _path:
		var c := cell_center(p)
		var s := tile_size * 0.18
		draw_rect(Rect2(c - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), PATH_TINT)
	if not _highlight.is_empty():
		draw_rect(cell_rect(_highlight["pos"]), _highlight["color"], false, 3.0)

	# 战场迷雾：视野外的格子压暗。画在最上层，遮住地形与装饰。
	# 分两档（C5 已探索记忆）：去过的地方只压暗一点、留下可辨认的轮廓；从没去过的是近乎全黑。
	if _fog_on and grid != null:
		for y in grid.rows():
			for x in grid.cols():
				var p := Vector2i(x, y)
				if _visible.has(p):
					continue
				if _seen.has(p):
					draw_rect(cell_rect(p), Color(0.02, 0.03, 0.06, 0.56))
				else:
					draw_rect(cell_rect(p), Color(0.02, 0.03, 0.06, 0.88))

	# 危险层（亮红）画在迷雾**之上** —— 必须穿透黑暗：
	# 让玩家「在看不见的地方被发现」是纯粹的挫败感，不是难度。
	# 预警层（暗红）则相反，留给黑暗保留恐怖感。
	for p in _attack:
		draw_rect(cell_rect(p), ATTACK_TINT)
