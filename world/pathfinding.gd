class_name Pathfind
extends RefCounted
## BFS 寻路（兼容外壳）。
##
## 背景：本文件在「地图重构」时曾被误删（因为搜索词用的是 Pathfinding，漏了 Pathfind）。
## 实际寻路逻辑现在统一在 `GridWorld.find_path`，这里只保留一层薄封装，
## 让既有调用点（如 content_test 的「出生点→出口可达性」校验）继续可用。

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## BFS 最短路径。
## blocked: Callable(pos) -> bool，返回 true 表示该格不可通行。
## 返回从 start 到 goal 的路径（**不含 start**，含 goal）；不可达时返回空数组。
static func find(start: Vector2i, goal: Vector2i, blocked: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal:
		return out
	var frontier: Array[Vector2i] = [start]
	var came: Dictionary = {start: start}
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if came.has(nxt):
				continue
			if blocked.is_valid() and bool(blocked.call(nxt)):
				continue
			came[nxt] = cur
			if nxt == goal:
				frontier.clear()
				break
			frontier.append(nxt)
	if not came.has(goal):
		return out
	var node: Vector2i = goal
	while node != start:
		out.push_front(node)
		node = came[node]
	return out
