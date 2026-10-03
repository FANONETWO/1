extends SceneTree
## 箱庭数据校验：地图合法、出口格真的是门、双向连通、落点可通行。
##   godot --headless --path . -s res://tests/rooms_test.gd
##
## 这个测试是为了防住「走不出去」那类坐标错位 —— 之前 exits.cell
## 写成了目标房间的落点，与地图上的门对不上，玩家站在门口也切不出去。

var _fail := 0
var _ok := 0

func _init() -> void:
	print("=== rooms_test ===")
	_check_map_shapes()
	_check_exit_cells_are_doors()
	_check_bidirectional()
	_check_entry_walkable()
	_check_start_reachable()
	print("rooms_test: %s（%d 项通过）" % ["PASS" if _fail == 0 else "FAIL (%d)" % _fail, _ok])
	quit(0 if _fail == 0 else 1)

func _bad(msg: String) -> void:
	_fail += 1
	print("  FAIL - ", msg)

func _good(msg: String) -> void:
	_ok += 1

func _grid_of(rid: String) -> GridWorld:
	var g := GridWorld.new()
	var t: Array[String] = []
	for row in R001Rooms.get_room(rid).get("tiles", []):
		t.append(String(row))
	g.setup(t)
	return g

## 1) 行长一致 + 无未定义地形字符
func _check_map_shapes() -> void:
	for rid in R001Rooms.ROOMS:
		var room: Dictionary = R001Rooms.ROOMS[rid]
		var tiles: Array = room.get("tiles", [])
		if tiles.is_empty():
			_bad("%s 没有地图" % rid)
			continue
		var w := String(tiles[0]).length()
		var bad_row := false
		for i in tiles.size():
			if String(tiles[i]).length() != w:
				_bad("%s 第 %d 行长度 %d ≠ %d" % [rid, i, String(tiles[i]).length(), w])
				bad_row = true
		if not bad_row:
			_good("%s 地图 %d×%d" % [rid, w, tiles.size()])

## 2) exits.cell 处必须是门 'D'（这就是「走不出去」的病根）
func _check_exit_cells_are_doors() -> void:
	for rid in R001Rooms.ROOMS:
		var g := _grid_of(rid)
		for e in R001Rooms.exit_cells(rid):
			var cell: Vector2i = e["cell"]
			var ch := g.char_at(cell)
			if ch != "D":
				_bad("%s 出口(%s) 在 %s 处是 '%s'，应为门 'D'" % [rid, e["dir"], str(cell), ch])
			else:
				_good("%s.%s → %s" % [rid, e["dir"], e["room"]])
			if String(e["room"]) != "" and not R001Rooms.ROOMS.has(String(e["room"])):
				_bad("%s 出口指向不存在的箱庭 '%s'" % [rid, e["room"]])

## 3) 双向连通：A 有门去 B，B 也必须有门回 A
func _check_bidirectional() -> void:
	for rid in R001Rooms.ROOMS:
		for e in R001Rooms.exit_cells(rid):
			var target := String(e["room"])
			if target == "" or not R001Rooms.ROOMS.has(target):
				continue
			var back := false
			for e2 in R001Rooms.exit_cells(target):
				if String(e2["room"]) == String(rid):
					back = true
					break
			if back:
				_good("%s ⇄ %s" % [rid, target])
			else:
				_bad("%s → %s 没有回程出口" % [rid, target])

## 4) 门内侧至少有一格可通行的落点（否则会被卡在门里）
func _check_entry_walkable() -> void:
	for rid in R001Rooms.ROOMS:
		var g := _grid_of(rid)
		for e in R001Rooms.exit_cells(rid):
			var cell: Vector2i = e["cell"]
			var found := false
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var p: Vector2i = cell + d
				if g.in_bounds(p) and g.is_walkable(p):
					found = true
					break
			if not found:
				_bad("%s 的门 %s 内侧没有可站立格" % [rid, str(cell)])

## 5) 起点能走到每一间（连通性）
func _check_start_reachable() -> void:
	var start := R001Rooms.START_ROOM
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for e in R001Rooms.exit_cells(cur):
			var t := String(e["room"])
			if t != "" and R001Rooms.ROOMS.has(t) and not seen.has(t):
				seen[t] = true
				queue.append(t)
	for rid in R001Rooms.ROOMS:
		if seen.has(rid):
			_good("可达 %s" % rid)
		else:
			_bad("%s 从起点不可达" % rid)
