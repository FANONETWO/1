extends SceneTree
## 视线（LOS）测试：墙 / 柜子 / 森林挡视线；门与矮掩体（桌床）不挡。
##   godot --headless --path . -s res://tests/los_test.gd

var _ok := 0
var _fail := 0

func _init() -> void:
	print("=== los_test ===")
	_test_grid_los()
	_test_scenario_sight()
	print("los_test: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, label: String) -> void:
	if cond:
		_ok += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _test_grid_los() -> void:
	var g := GridWorld.new()
	g.setup([
		"#######",
		"#.....#",
		"#..#..#",
		"#.....#",
		"#C...F#",
		"#.....#",
		"#######",
	])
	_check(g.has_line_of_sight(Vector2i(1, 1), Vector2i(5, 1)), "同排空旷 → 通视")
	_check(not g.has_line_of_sight(Vector2i(1, 2), Vector2i(5, 2)), "中间隔墙(3,2) → 不通视")
	_check(not g.has_line_of_sight(Vector2i(2, 2), Vector2i(4, 2)), "紧贴墙两侧 → 不通视")
	_check(not g.has_line_of_sight(Vector2i(0, 4), Vector2i(2, 4)), "柜子挡视线")
	_check(not g.has_line_of_sight(Vector2i(4, 4), Vector2i(6, 4)), "森林挡视线")

	_check(g.blocks_sight(Vector2i(3, 2)), "墙 blocks_sight = true")
	_check(not g.blocks_sight(Vector2i(1, 1)), "地板 blocks_sight = false")
	_check(g.blocks_sight(Vector2i(1, 4)), "柜子 blocks_sight = true")

	# 门与矮掩体不挡
	var g2 := GridWorld.new()
	g2.setup([
		"#####",
		"#.D.#",
		"#.T.#",
		"#####",
	])
	_check(g2.has_line_of_sight(Vector2i(1, 1), Vector2i(3, 1)), "门不挡视线")
	_check(g2.has_line_of_sight(Vector2i(1, 2), Vector2i(3, 2)), "桌子（矮掩体）不挡视线")
	_check(not g2.blocks_sight(Vector2i(2, 1)), "门 blocks_sight = false")

	# 斜线穿墙
	var g3 := GridWorld.new()
	g3.setup([
		"#####",
		"#...#",
		"#.#.#",
		"#...#",
		"#####",
	])
	_check(not g3.has_line_of_sight(Vector2i(1, 1), Vector2i(3, 3)), "斜线被中央墙挡住")
	_check(g3.has_line_of_sight(Vector2i(1, 1), Vector2i(3, 1)), "斜线受阻但横向仍通视")

## 端到端：用真实地图验证「敌人在墙内看不到墙外的玩家」
func _test_scenario_sight() -> void:
	var grid := GridWorld.new()
	grid.setup(R001Map.TILES)
	# 地图里 (1,1) 与 (12,1) 同在北侧房间带，但中间有 '#'（第 3 行 x=4 处）
	# 直接取一对被墙隔开、直线距离在视野内的格子
	var a := Vector2i(3, 8)      # X 危险区附近（南侧房间内）
	var b := Vector2i(14, 8)     # 同排，右半侧房间内
	var blocked_mid := false
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var px := int(round(a.x + (b.x - a.x) * t))
		var py := int(round(a.y + (b.y - a.y) * t))
		if grid.blocks_sight(Vector2i(px, py)):
			blocked_mid = true
	_check(blocked_mid, "真实地图：a→b 之间存在遮挡地形")
	_check(not grid.has_line_of_sight(a, b), "真实地图：隔着墙 → 不通视")

	# 主走廊（第 5 行全程无遮挡）应当通视
	_check(grid.blocks_sight(Vector2i(6, 6)), "(6,6) 本身是墙 —— 前一条选点修正依据")
	_check(grid.has_line_of_sight(Vector2i(2, 5), Vector2i(17, 5)), "主走廊横穿 → 通视")
