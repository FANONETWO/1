extends Node
## 游戏模式（独狼 / 四人小队）验证：倍率、成绩分家、队友入档、结算文案。
##   godot --headless --path . res://tests/mode_test.tscn --quit-after 900

var _fails := 0

func _ready() -> void:
	TestGuard.arm("mode_test", 30.0, get_tree())
	print("mode_test: start")

	# ——— 1. 模式与奖励倍率 ———
	Game.new_game()
	var pc := Character.create_default()
	pc.name = "模式测试"
	Game.set_player(pc)          # 没有角色时存档里不含 player，load_game() 会返回 false
	Game.set_mode(Game.MODE_SOLO)
	_check(Game.mode == Game.MODE_SOLO, "切到独狼模式")
	_check(absf(Game.reward_multiplier() - 1.5) < 0.001, "独狼奖励 ×1.5（实际 %.2f）" % Game.reward_multiplier())
	Game.set_mode(Game.MODE_TEAM)
	_check(Game.mode == Game.MODE_TEAM, "切到四人小队模式")
	_check(absf(Game.reward_multiplier() - 1.0) < 0.001, "团队奖励 ×1.0（实际 %.2f）" % Game.reward_multiplier())
	_check(Game.mode_name() == "四人小队", "模式名 = 四人小队")

	# ——— 2. 成绩按模式分开记 ———
	var k_solo := "r001_apartment@solo"
	var k_team := "r001_apartment@team"
	Game.set_mode(Game.MODE_SOLO)
	_check(Game.best_key("r001_apartment") == k_solo, "独狼的成绩键带 @solo")
	Game.set_mode(Game.MODE_TEAM)
	_check(Game.best_key("r001_apartment") == k_team, "团队的成绩键带 @team")
	# 分别写入，互不覆盖
	Game.best_endings[k_team] = "normal"
	_check(Game.best_ending_of_mode("r001_apartment") == "normal", "团队最佳 = normal")
	Game.set_mode(Game.MODE_SOLO)
	Game.best_endings[k_solo] = "perfect"
	_check(Game.best_ending_of_mode("r001_apartment") == "perfect", "独狼最佳 = perfect（与团队互不干扰）")
	Game.set_mode(Game.MODE_TEAM)
	_check(Game.best_ending_of_mode("r001_apartment") == "normal", "切回团队仍看到自己的记录")

	# ——— 3. 队友：生成 / 入档 / 读档还原 ———
	var allies := Allies.make_allies(3)
	_check(allies.size() == 3, "生成 3 名队友")
	var names := []
	for a in allies:
		names.append(a.name)
	_check(names == ["铁闸", "快刀", "药箱"], "队友是预设三人组（实际 %s）" % str(names))
	# 属性点花费必须刚好 30（阶梯价：1→v 的成本 = 2+3+…+v）
	for a in allies:
		var cost := 0
		for attr in a.attrs:
			var v := int(a.attrs[attr])
			for step in range(2, v + 1):
				cost += step
		_check(cost == 30, "%s 的属性点恰好 30（实际 %d）" % [a.name, cost])

	Game.set_team(allies)
	_check(Game.allies().size() == 3, "set_team 写入 3 名队友")
	Game.save_game()
	var saved_ok := Game.load_game()
	_check(saved_ok, "存档可读回")
	_check(Game.allies().size() == 3, "读档后队友仍在（实际 %d）" % Game.allies().size())
	if Game.allies().size() == 3:
		var c0: Character = Game.allies()[0]
		_check(c0.name == "铁闸" and c0.max_hp() > 0, "读档后队友数据完整（%s HP%d）" % [c0.name, c0.max_hp()])
	_check(Game.mode == Game.MODE_TEAM, "读档后模式仍是团队")

	# ——— 4. 结算文案要写明倍率（透明才不挨骂） ———
	var res_solo: Dictionary = R001Content.settlement("测试者", "perfect", 4, 200, 30, 1845, 1.5, "独狼")
	var body_solo := String(res_solo["body"])
	_check(body_solo.contains("风险溢价 ×1.5"), "独狼结算写明「风险溢价 ×1.5」")
	var res_team: Dictionary = R001Content.settlement("测试者", "perfect", 4, 200, 30, 1230, 1.0, "四人小队")
	var body_team := String(res_team["body"])
	_check(body_team.contains("四人小队") and not body_team.contains("风险溢价"), "团队结算不提溢价")

	# 收尾：把存档恢复成独狼，避免影响其它测试
	Game.set_mode(Game.MODE_SOLO)
	Game.set_team([])
	Game.save_game()

	print("mode_test: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok - " + label)
	else:
		_fails += 1
		printerr("  FAIL - " + label)
