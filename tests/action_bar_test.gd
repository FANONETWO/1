extends SceneTree
## 行动条（CTB 行动值）与指挥点验证。
##   godot --headless --path . -s res://tests/action_bar_test.gd
##
## 这个测试守的是三件事：
##   1. 速度真的能换出手次数（否则「行动条」只是装饰）
##   2. UI 画的预测顺序 与 实际出手顺序 一致（不一致就是在骗玩家）
##   3. 指挥点干预真的能改变顺序，且会正确扣点、用尽后拒绝

var _fails := 0

func _init() -> void:
	TestGuard.arm("action_bar_test", 20.0, self)
	print("action_bar_test: start")

	var p := Character.create_default()
	p.name = "速度测试"
	p.attrs["dex"] = 5
	p.attrs["com"] = 4
	p.attrs["int"] = 6
	p.hp = p.max_hp()
	p.will = p.max_will()

	# ——— 1. 速度派生 ———
	var cm := CombatManager.new()
	cm.start(p, [{"id": "walker", "pos": Vector2i(1, 0)}, {"id": "hound", "pos": Vector2i(2, 0)}], Vector2i(0, 0))
	var pu := cm.player_unit
	_check(pu.speed == 5 + 4 / 2 + 2, "玩家速度 = 敏捷 + 沉着/2 + 2（实际 %d，应为 9）" % pu.speed)
	var walker := cm.units[1]
	var hound := cm.units[2]
	_check(walker.speed < pu.speed, "逐尸速度(%d) 低于玩家(%d)" % [walker.speed, pu.speed])
	_check(hound.speed > walker.speed, "尸犬速度(%d) 高于逐尸(%d)" % [hound.speed, walker.speed])
	_check(absf(pu.av - cm.initial_av(pu)) < 0.01,
		"初始行动值 = BASE_AV/speed − 先攻（%.1f）" % pu.av)

	# ——— 2. timeline() 是纯读，且与实际顺序一致 ———
	var before := {}
	for u in cm.units:
		before[u.uid] = u.av
	var predicted: Array = []
	for u in cm.timeline(6):
		predicted.append(u.uid)
	var after := {}
	for u in cm.units:
		after[u.uid] = u.av
	_check(before == after, "timeline() 不修改任何状态（纯预测）")
	var actual: Array = []
	for i in 6:
		var u := cm.advance_timeline()
		if u == null:
			break
		actual.append(u.uid)
	_check(predicted == actual,
		"预测顺序与实际出手顺序一致\n    预测 %s\n    实际 %s" % [str(predicted), str(actual)])

	# ——— 3. 速度换出手次数 ———
	var cm2 := CombatManager.new()
	cm2.start(p, [{"id": "walker", "pos": Vector2i(1, 0)}], Vector2i(0, 0))
	var counts := {}
	for u in cm2.units:
		counts[u.uid] = 0
	for i in 40:
		var u := cm2.advance_timeline()
		if u == null:
			break
		counts[u.uid] = int(counts[u.uid]) + 1
	var pc := int(counts[cm2.player_unit.uid])
	var wc := int(counts[cm2.units[1].uid])
	_check(pc > wc, "40 次推进中速度快的出手更多（玩家 %d 次 vs 逐尸 %d 次）" % [pc, wc])

	# ——— 4. 回合数 = 最慢者的行动次数 + 1 ———
	var cm3 := CombatManager.new()
	cm3.start(p, [{"id": "walker", "pos": Vector2i(1, 0)}], Vector2i(0, 0))
	_check(cm3.round_now() == 1, "开局是第 1 回合")
	# 注意：不能假设「推进 N 次 = 全员各出手一次」—— 速度快的人会在同一回合里多动。
	# 正确做法是一直推进，直到最慢的那个人也出手过。
	var steps := 0
	while cm3.round_now() == 1 and steps < 60:
		cm3.advance_timeline()
		steps += 1
	_check(cm3.round_now() == 2,
		"最慢的人也出手后进入第 2 回合（推进 %d 次，实际第 %d 回合）" % [steps, cm3.round_now()])
	var pt := cm3.player_unit.rounds_taken
	var wt := cm3.units[1].rounds_taken
	_check(pt > wt, "速度快的玩家在同一回合里多动（玩家 %d 次 vs 逐尸 %d 次）" % [pt, wt])

	# ——— 5. 指挥点干预 ———
	var cm4 := CombatManager.new()
	cm4.start(p, [{"id": "walker", "pos": Vector2i(1, 0)}], Vector2i(0, 0))
	var pu4 := cm4.player_unit
	var cp0 := cm4.command_points()
	_check(cp0 == 3, "独狼指挥点 = 智力/2（智力 6 → 实际 %d）" % cp0)
	var av_before := pu4.av
	var ok1 := cm4.tactic_rush(pu4)
	_check(ok1 and pu4.av < av_before, "「抢手」让自己行动值变小（%.1f → %.1f）" % [av_before, pu4.av])
	_check(cm4.command_points() == cp0 - 1, "「抢手」扣 1 点指挥点（剩 %d）" % cm4.command_points())
	var foe := cm4.units[1]
	var fav := foe.av
	var ok2 := cm4.tactic_suppress(foe)
	_check(ok2 and foe.av > fav, "「压制」让敌人行动值变大（%.1f → %.1f）" % [fav, foe.av])
	while cm4.command_points() > 0:
		cm4.tactic_rush(pu4)
	_check(not cm4.tactic_rush(pu4), "指挥点耗尽后「抢手」被拒绝")
	_check(not cm4.tactic_suppress(foe), "指挥点耗尽后「压制」被拒绝")

	# ——— 6. 团队模式：多玩家单位与共享指挥点 ———
	var allies := Allies.make_allies(3)
	_check(allies.size() == 3, "队友预设生成 3 人（实际 %d）" % allies.size())
	var cm5 := CombatManager.new()
	cm5.start(p, [{"id": "walker", "pos": Vector2i(1, 0)}], Vector2i(0, 0), allies)
	var punits := cm5.player_units()
	_check(punits.size() == 4, "团队模式玩家方 4 个单位（实际 %d）" % punits.size())
	var ids := []
	var speeds := {}
	for u in punits:
		ids.append(u.uid)
		speeds[u.speed] = true
	_check(ids == ["player", "p1", "p2", "p3"], "槽位 id 稳定为 player/p1/p2/p3（实际 %s）" % str(ids))
	_check(speeds.size() >= 3, "四名队员速度互不相同，行动条会交错（%d 种速度）" % speeds.size())
	var team_cp := cm5.command_points()
	_check(team_cp > cp0, "团队指挥点(%d) 高于独狼(%d)" % [team_cp, cp0])
	# 团队的时间轴里应该能看到多个自己人
	var seen_players := 0
	for u in cm5.timeline(8):
		if u.is_player:
			seen_players += 1
	_check(seen_players >= 2, "未来 8 次出手里有多个玩家单位（实际 %d）" % seen_players)

	print("action_bar_test: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok - " + label)
	else:
		_fails += 1
		printerr("  FAIL - " + label)
