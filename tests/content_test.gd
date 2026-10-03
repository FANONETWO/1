extends SceneTree
## 副本数据完整性测试：地图/布点/定义/对话树。
##   godot --headless --path . -s res://tests/content_test.gd

var _fails := 0

func _init() -> void:
	print("content_test: start")

	# 1. 地图：所有行等长，仅含合法字符
	# 合法字符直接取自地形表，避免以后新增地形（H/X/R/F 等）时测试与实际脱节
	var legal := ""
	for k in GridWorld.TERRAIN.keys():
		legal += String(k)
	var width := -1
	for row in R001Map.TILES:
		if width < 0:
			width = row.length()
		else:
			_check(row.length() == width, "地图行等长（%d）" % row.length())
		for ch in row:
			_check(legal.contains(ch), "合法地形字符 '%s'" % ch)

	# 2. 出生点/敌人/NPC/调查点都在地图内且可走
	var inside := func(pos: Vector2i) -> bool:
		return pos.x >= 0 and pos.y >= 0 and pos.y < R001Map.TILES.size() and pos.x < R001Map.TILES[0].length()
	var walkable := func(pos: Vector2i) -> bool:
		if not inside.call(pos):
			return false
		return String(R001Map.TILES[pos.y][pos.x]) != "#"
	_check(walkable.call(R001Map.SPAWN), "出生点可走")
	for e in R001Map.ENEMIES:
		var pos: Vector2i = e["pos"]
		_check(walkable.call(pos), "敌人 %s 位置可走 (%d,%d)" % [e["id"], pos.x, pos.y])
	for nid in R001Map.NPCS:
		var pos: Vector2i = R001Map.NPCS[nid]["pos"]
		_check(walkable.call(pos), "NPC %s 位置可走" % nid)
	for sid in R001Map.SPOTS:
		var pos: Vector2i = R001Map.SPOTS[sid]["pos"]
		_check(walkable.call(pos), "调查点 %s 位置可走" % sid)

	# 3. 敌人定义完整
	for eid in Enemies.ALL:
		var d: Dictionary = Enemies.ALL[eid]
		_check(d.has("hp") and int(d["hp"]) > 0, "敌人 %s 有生命" % eid)
		_check(d.has("dp_attack") and int(d["dp_attack"]) > 0, "敌人 %s 有攻击骰池" % eid)

	# 4. 物品定义完整
	for iid in Items.ALL:
		var d: Dictionary = Items.ALL[iid]
		_check(d.has("name") and d.has("kind"), "物品 %s 定义完整" % iid)

	# 5. 任务定义完整
	for qid in QuestsDef.ALL:
		var d: Dictionary = QuestsDef.ALL[qid]
		_check(d.has("kind") and d.has("reward_points"), "任务 %s 定义完整" % qid)

	# 6. 天赋定义完整（技能加成指向存在的技能）
	for tid in Talents.ALL:
		var d: Dictionary = Talents.ALL[tid]
		for sid in d.get("skills", {}):
			_check(Skills.ALL.has(String(sid)), "天赋 %s 技能 %s 存在" % [tid, sid])

	# 7. 对话树：next 指向存在的节点
	_check_dialog("陈叔", R001Dialogs.CHEN)
	_check_dialog("阿贵", R001Dialogs.AGUI)

	# 8. 地图可达性：出生点 → 出口 有路径
	var path := Pathfind.find(R001Map.SPAWN, R001Map.EXIT, func(pos): return not _walkable_impl(pos))
	_check(not path.is_empty(), "出生点到出口有路径")

	print("content_test: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

func _walkable_impl(pos: Vector2i) -> bool:
	if pos.y < 0 or pos.y >= R001Map.TILES.size():
		return false
	if pos.x < 0 or pos.x >= R001Map.TILES[0].length():
		return false
	return String(R001Map.TILES[pos.y][pos.x]) != "#"

func _check_dialog(name: String, tree: Dictionary) -> void:
	for nid in tree:
		var node: Dictionary = tree[nid]
		if node.has("options"):
			for opt in node["options"]:
				# 带检定的选项必须同时声明 pass/fail，否则运行时无从决定去向（回归防护）
				if opt.has("check"):
					_check(opt.has("pass") and opt.has("fail"), "对话 %s 节点 %s 检定选项声明 pass/fail" % [name, nid])
				if opt.has("next"):
					_check(tree.has(String(opt["next"])), "对话 %s 节点 %s -> %s 存在" % [name, nid, opt["next"]])
				if opt.has("pass"):
					_check(tree.has(String(opt["pass"])), "对话 %s 节点 %s pass -> %s 存在" % [name, nid, opt["pass"]])
				if opt.has("fail"):
					_check(tree.has(String(opt["fail"])), "对话 %s 节点 %s fail -> %s 存在" % [name, nid, opt["fail"]])

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok - " + label)
	else:
		_fails += 1
		printerr("  FAIL - " + label)
