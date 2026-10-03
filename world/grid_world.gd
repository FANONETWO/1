class_name GridWorld
extends RefCounted
## 视角无关的方格逻辑层（阶段 A 地基）。
##
## 设计纪律：本类只做规则计算，不涉及任何渲染、像素、等距或镜头概念。
## 渲染层（GridRenderer 及其子类）只读取这里的数据，绝不允许反向影响逻辑。
## 因此「方格俯视」与「等距像素」可以随时互换，而逻辑与测试零改动。
##
## 地形字符：
##   # 墙（不可通行） · . 平地 · D 门 · S 楼梯 · E 出口
##   T 桌 / C 柜 / B 床   —— 掩体：移动消耗 2、防御 +1
##   F 森林（回避 +15） · R 废墟（回避 +10、防御 +1）
##   H 高地（命中 +10） · X 危险区（回避 −10、每回合受伤 2）

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const FLOOR := {
	"name": "平地", "walkable": true, "move_cost": 1,
	"avoid": 0, "defense": 0, "hit_bonus": 0, "damage_per_turn": 0,
}

## 地形表：字符 -> 属性。move_cost ≥ 99 视为不可通行。
const TERRAIN := {
	".": FLOOR,
	"#": {"name": "墙", "walkable": false, "move_cost": 99,
		"avoid": 0, "defense": 0, "hit_bonus": 0, "damage_per_turn": 0},
	"D": {"name": "门", "walkable": true, "move_cost": 1,
		"avoid": 0, "defense": 0, "hit_bonus": 0, "damage_per_turn": 0},
	"S": {"name": "楼梯", "walkable": true, "move_cost": 1,
		"avoid": 0, "defense": 0, "hit_bonus": 0, "damage_per_turn": 0},
	"E": {"name": "出口", "walkable": true, "move_cost": 1,
		"avoid": 0, "defense": 0, "hit_bonus": 0, "damage_per_turn": 0},
	"T": {"name": "桌子", "walkable": true, "move_cost": 2,
		"avoid": 0, "defense": 1, "hit_bonus": 0, "damage_per_turn": 0},
	"B": {"name": "床", "walkable": true, "move_cost": 2,
		"avoid": 0, "defense": 1, "hit_bonus": 0, "damage_per_turn": 0},
	"C": {"name": "柜子", "walkable": true, "move_cost": 2,
		"avoid": 0, "defense": 1, "hit_bonus": 0, "damage_per_turn": 0},
	"F": {"name": "森林", "walkable": true, "move_cost": 2,
		"avoid": 15, "defense": 0, "hit_bonus": 0, "damage_per_turn": 0},
	"R": {"name": "废墟", "walkable": true, "move_cost": 2,
		"avoid": 10, "defense": 1, "hit_bonus": 0, "damage_per_turn": 0},
	"H": {"name": "高地", "walkable": true, "move_cost": 2,
		"avoid": 5, "defense": 0, "hit_bonus": 10, "damage_per_turn": 0},
	"X": {"name": "危险区", "walkable": true, "move_cost": 1,
		"avoid": -10, "defense": 0, "hit_bonus": 0, "damage_per_turn": 2},
}

var rows_data: Array[String] = []

func setup(data: Array[String]) -> void:
	rows_data = data.duplicate()

# ——— 尺寸与查询 ———

func rows() -> int:
	return rows_data.size()

func cols() -> int:
	return rows_data[0].length() if not rows_data.is_empty() else 0

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.y < rows() and pos.x < cols()

func char_at(pos: Vector2i) -> String:
	if not in_bounds(pos):
		return "#"
	return String(rows_data[pos.y][pos.x])

func terrain_at(pos: Vector2i) -> Dictionary:
	return TERRAIN.get(char_at(pos), FLOOR)

func is_walkable(pos: Vector2i) -> bool:
	if not in_bounds(pos):
		return false
	return bool(terrain_at(pos)["walkable"])

func move_cost(pos: Vector2i) -> int:
	if not is_walkable(pos):
		return 99
	return int(terrain_at(pos)["move_cost"])

func avoid_at(pos: Vector2i) -> int:
	return int(terrain_at(pos)["avoid"]) if in_bounds(pos) else 0

func defense_at(pos: Vector2i) -> int:
	return int(terrain_at(pos)["defense"]) if in_bounds(pos) else 0

func hit_bonus_at(pos: Vector2i) -> int:
	return int(terrain_at(pos)["hit_bonus"]) if in_bounds(pos) else 0

func damage_per_turn_at(pos: Vector2i) -> int:
	return int(terrain_at(pos)["damage_per_turn"]) if in_bounds(pos) else 0

func terrain_name_at(pos: Vector2i) -> String:
	return String(terrain_at(pos)["name"])

func all_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rows():
		for x in cols():
			out.append(Vector2i(x, y))
	return out

func neighbors(pos: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		var n: Vector2i = pos + d
		if in_bounds(n):
			out.append(n)
	return out

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# ——— 路径与范围（blocked: Callable(pos) -> bool，用于单位占用等动态阻挡）———

## 最短步数路径（4 方向 BFS），返回不含起点的格子序列；不可达返回空数组。
## blocked 可传 Callable(pos)->bool 表示动态阻挡（单位占用等）；不传则视为无阻挡。
## 注意：GDScript 中 Callable 默认参数为 null，必须用 is_valid() 判定后再调用。
func find_path(start: Vector2i, goal: Vector2i, blocked: Variant = null) -> Array[Vector2i]:
	var has_block := blocked is Callable and (blocked as Callable).is_valid()
	if start == goal:
		return []
	if not is_walkable(goal) or (has_block and bool(blocked.call(goal))):
		return []
	var prev: Dictionary = {}
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			break
		for nxt in neighbors(cur):
			if visited.has(nxt) or not is_walkable(nxt) or (has_block and bool(blocked.call(nxt))):
				continue
			visited[nxt] = true
			prev[nxt] = cur
			queue.append(nxt)
	if not visited.has(goal):
		return []
	var path: Array[Vector2i] = []
	var cur2 := goal
	while cur2 != start:
		path.push_front(cur2)
		cur2 = prev[cur2]
	return path

## 移动范围：以地形移动消耗做 Dijkstra，返回 {格子: 累计消耗}（不含起点）。
func reachable(from: Vector2i, move_points: int, blocked: Variant = null) -> Dictionary:
	var has_block := blocked is Callable and (blocked as Callable).is_valid()
	var cost: Dictionary = {from: 0}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		# 取当前消耗最小的节点（地图规模小，线性扫描足够）
		var best_i := 0
		for i in frontier.size():
			if int(cost[frontier[i]]) < int(cost[frontier[best_i]]):
				best_i = i
		var cur: Vector2i = frontier.pop_at(best_i)
		for nxt in neighbors(cur):
			if not is_walkable(nxt) or (has_block and bool(blocked.call(nxt))):
				continue
			var step := int(cost[cur]) + move_cost(nxt)
			if step > move_points:
				continue
			if not cost.has(nxt) or step < int(cost[nxt]):
				cost[nxt] = step
				frontier.append(nxt)
	cost.erase(from)
	return cost

## 攻击范围：曼哈顿距离在 [min_range, max_range] 内的格子。
func tiles_in_range(from: Vector2i, min_range: int, max_range: int, need_walkable: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(from.y - max_range, from.y + max_range + 1):
		for x in range(from.x - max_range, from.x + max_range + 1):
			var p := Vector2i(x, y)
			if not in_bounds(p):
				continue
			var d := manhattan(from, p)
			if d < min_range or d > max_range:
				continue
			if need_walkable and not is_walkable(p):
				continue
			out.append(p)
	return out

# ——— 校验（供测试与内容管线使用）———

## 返回问题列表；空数组表示地图合法。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if rows_data.is_empty():
		errs.append("地图为空")
		return errs
	var w := rows_data[0].length()
	for i in rows_data.size():
		var line := rows_data[i]
		if line.length() != w:
			errs.append("第 %d 行长度 %d ≠ %d" % [i, line.length(), w])
		for ch in line:
			if not TERRAIN.has(String(ch)):
				errs.append("第 %d 行出现未定义地形字符 '%s'" % [i, ch])
	return errs

## 两点是否连通（注意：不能命名为 is_connected，会与 Object 的信号方法冲突）。
func is_reachable(a: Vector2i, b: Vector2i) -> bool:
	return not find_path(a, b).is_empty() or a == b

# ——— 视线（LOS）———

## 挡视线的地形：墙、柜子（高家具）、森林。
## 桌/床属于**矮掩体**：影响通行与防御，但不挡视线。
const SIGHT_BLOCKERS: Array[String] = ["#", "C", "F"]

func blocks_sight(pos: Vector2i) -> bool:
	return char_at(pos) in SIGHT_BLOCKERS

## 两点之间是否通视（Bresenham 直线；两端点自身不参与遮挡判定）。
## 用途：敌人视野被墙挡住、远程攻击需要通视。
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var guard := 0
	while guard < 512:
		guard += 1
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
		if x0 == x1 and y0 == y1:
			return true          # 已抵达终点
		if blocks_sight(Vector2i(x0, y0)):
			return false
	return false
