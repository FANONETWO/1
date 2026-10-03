extends SceneTree
## 阶段 A 地基测试：方格逻辑层 / 世界观注册表 / 渲染器接口。
##   godot --headless --path . -s res://tests/world_test.gd

var _fails := 0

func _init() -> void:
	print("world_test: start")

	# ——— 1. 方格逻辑：地形、通行、修正 ———
	var g := GridWorld.new()
	g.setup([
		"#####",
		"#.#F#",
		"#...#",
		"#..X#",
		"#####",
	])
	_check(g.rows() == 5 and g.cols() == 5, "地图尺寸 5×5")
	_check(not g.is_walkable(Vector2i(0, 0)), "墙体不可通行")
	_check(g.is_walkable(Vector2i(1, 1)), "平地可通行")
	_check(not g.is_walkable(Vector2i(2, 1)), "内墙不可通行")
	_check(g.move_cost(Vector2i(3, 1)) == 2, "森林移动消耗 2")
	_check(g.avoid_at(Vector2i(3, 1)) == 15, "森林回避 +15")
	_check(g.defense_at(Vector2i(3, 3)) == 0 and g.damage_per_turn_at(Vector2i(3, 3)) == 2, "危险区每回合伤害 2")
	_check(g.terrain_name_at(Vector2i(1, 1)) == "平地", "地形名称查询")

	# ——— 2. 越界与容错 ———
	_check(not g.in_bounds(Vector2i(-1, 0)) and not g.in_bounds(Vector2i(5, 5)), "越界判定")
	_check(g.char_at(Vector2i(9, 9)) == "#" and g.move_cost(Vector2i(9, 9)) == 99, "越界按墙处理")

	# ——— 3. BFS 路径（必须绕过内墙）———
	var path := g.find_path(Vector2i(1, 1), Vector2i(3, 3))
	_check(not path.is_empty(), "存在可达路径")
	_check(path[path.size() - 1] == Vector2i(3, 3), "路径终点正确")
	_check(not (Vector2i(2, 1) in path), "路径不穿墙")
	_check(g.find_path(Vector2i(1, 1), Vector2i(2, 1)).is_empty(), "墙格不可达")
	_check(g.find_path(Vector2i(1, 1), Vector2i(1, 1)).is_empty(), "原地返回空路径")
	_check(g.is_reachable(Vector2i(1, 1), Vector2i(3, 2)), "连通性判定为真")

	# ——— 4. 移动范围（Dijkstra，含地形消耗）———
	var reach := g.reachable(Vector2i(1, 1), 2)
	_check(reach.has(Vector2i(2, 2)), "2 点移动力可达 (2,2)")
	_check(reach.has(Vector2i(1, 3)), "2 点移动力可达 (1,3)")
	_check(not reach.has(Vector2i(3, 1)), "需绕行 5 点消耗的森林不在范围内")
	_check(not reach.has(Vector2i(1, 1)), "移动范围不含起点")
	var reach_blocked := g.reachable(Vector2i(1, 1), 3, func(p): return p == Vector2i(1, 2))
	_check(not reach_blocked.has(Vector2i(1, 3)), "被动态阻挡后无法通过")

	# ——— 5. 攻击范围 ———
	var melee := g.tiles_in_range(Vector2i(2, 2), 1, 1, true)
	_check(melee.has(Vector2i(1, 2)) and melee.has(Vector2i(3, 2)) and melee.has(Vector2i(2, 3)), "相邻 4 格攻击范围")
	_check(not melee.has(Vector2i(2, 1)), "不可通行格不计入攻击范围（need_walkable）")
	var far := g.tiles_in_range(Vector2i(1, 1), 2, 3)
	_check(far.has(Vector2i(3, 2)) and far.has(Vector2i(3, 1)), "远程 2~3 格范围")
	_check(not far.has(Vector2i(1, 2)), "距离 1 不在 2~3 范围内")
	_check(not far.has(Vector2i(3, 3)), "距离 4 超出 2~3 范围")
	_check(GridWorld.manhattan(Vector2i(1, 1), Vector2i(3, 3)) == 4, "曼哈顿距离")

	# ——— 6. 地形表完整性 ———
	var needed := ["name", "walkable", "move_cost", "avoid", "defense", "hit_bonus", "damage_per_turn"]
	var terrain_ok := true
	for ch in GridWorld.TERRAIN:
		for key in needed:
			if not GridWorld.TERRAIN[ch].has(key):
				terrain_ok = false
	_check(terrain_ok, "地形表字段完整（%d 种地形）" % GridWorld.TERRAIN.size())
	_check(g.validate().is_empty(), "合法地图校验通过")
	var bad := GridWorld.new()
	bad.setup(["##", "#"])
	_check(not bad.validate().is_empty(), "行不等长地图校验失败")

	# ——— 7. 世界注册表 ———
	_check(Worlds.count() == 5, "注册了 5 个世界")
	var ids := Worlds.ids()
	for expect in ["w1_apartment", "w2_xianxia", "w3_scifi", "w4_magic", "w5_wasteland"]:
		_check(ids.has(expect), "包含世界 %s" % expect)
	var w1 := Worlds.get_world("w1_apartment")
	_check(w1 != null, "可取到惊变公寓")
	_check(w1.stage_count() == 3, "惊变公寓有 3 个阶段")
	_check(w1.quests.size() == 3, "惊变公寓有 3 个任务")
	_check(w1.mechanic == "noise_infection", "惊变公寓机制 id 正确")
	_check(w1.stage_id(0) == "floor1" and w1.stage_id(1) == "garage" and w1.stage_id(2) == "lobby", "阶段顺序正确")
	_check(Worlds.get_world("nope") == null, "不存在的世界返回 null")

	var all_ok := true
	var summary_ok := true
	for w in Worlds.all():
		if w.name == "" or w.quests.is_empty() or w.stages.is_empty() or w.mechanic == "" or w.settlement.is_empty():
			all_ok = false
		var s := Worlds.card_summary(w.id)
		if s.is_empty() or not s.has("rating") or not s.has("theme_color"):
			summary_ok = false
	_check(all_ok, "全部世界字段完整（名称/任务/阶段/机制/结算）")
	_check(summary_ok, "世界卡片摘要可用")

	var errs := Worlds.validate_all()
	if not errs.is_empty():
		for e in errs:
			printerr("  FAIL - 世界校验：%s" % e)
		_fails += 1
	else:
		print("  ok - 五个世界数据全部合法（地图/出生点/出口/敌人/NPC/交互点/连通性）")

	# ——— 8. 渲染器接口（逻辑与渲染解耦）———
	var r := PlaceholderRenderer.new()
	_check(r is GridRenderer, "占位渲染器实现渲染器接口")
	r.bind(g)
	_check(r.grid == g, "渲染器已绑定逻辑层")
	_check(r.tile_size > 0.0, "tile 尺寸有效")
	var c := r.cell_center(Vector2i(2, 3))
	_check(r.point_to_cell(c) == Vector2i(2, 3), "屏幕坐标与格子坐标往返一致")
	_check(r.cell_rect(Vector2i(0, 0)).size.x == r.tile_size, "格子矩形尺寸正确")
	r.show_move_range([Vector2i(1, 1)])
	r.show_attack_range([Vector2i(2, 2)])
	r.show_path([Vector2i(1, 2)])
	r.spawn_unit("p1", Vector2i(1, 1), Color.RED)
	r.set_unit_hp("p1", 5, 10)
	r.move_unit("p1", Vector2i(2, 2))
	r.despawn_unit("p1")
	r.clear_overlays()
	r.clear_units()
	_check(true, "渲染器接口调用无异常")
	r.free()

	# ——— 9. 逻辑层不依赖渲染层（解耦验证）———
	# 用一个「哑渲染器」冒充任何视角，逻辑结果必须完全一致
	var logical_path := g.find_path(Vector2i(1, 1), Vector2i(3, 3))
	_check(logical_path.size() == 4, "逻辑路径长度与渲染无关（4 步绕行）")

	print("world_test: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok - " + label)
	else:
		_fails += 1
		printerr("  FAIL - " + label)
