extends Control
## 团队模式战斗端到端：4 人上阵、队友 AI 会出手、行动条列出多人、指挥点共享。
##   godot --headless --path . res://tests/team_battle_test.tscn --quit-after 3600

func _ready() -> void:
	var c := Character.create_default()
	c.name = "队长"
	c.talent_id = "survivor"
	c.attrs = {"str": 3, "dex": 3, "end": 4, "int": 2, "per": 3, "res": 2, "pre": 2, "man": 1, "com": 2}
	c.skills = {"blade": 3, "hide": 3, "investigate": 3}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	Game.set_mode(Game.MODE_TEAM)
	Game.set_team(Allies.make_allies(3))
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		TestGuard.arm("team_battle_test", 60.0, get_tree())
		await get_tree().create_timer(1.6).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("team_battle_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		sc.skip_tutorial()
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.4).timeout
		sc._start_combat_with("zombie")
		await get_tree().create_timer(2.2).timeout

		var bt = sc.get("_battle")
		if bt == null:
			print("team_battle_test: FAIL（战斗未创建）")
			get_tree().quit(1)
			return
		var cm = bt.get("_cm")
		var fails: Array[String] = []

		# 1) 玩家方 4 个单位
		var punits: Array = cm.player_units()
		var names: Array = []
		for u in punits:
			names.append(u.name)
		print("[team] 玩家方 %d 人：%s" % [punits.size(), str(names)])
		if punits.size() != 4:
			fails.append("团队模式玩家方不是 4 人（%d）" % punits.size())

		# 2) 行动条卡片
		var tl = bt.get("_timeline_box")
		var cards := 0
		if tl != null:
			cards = tl.get_child_count()
		print("[team] 行动条卡片 %d 张" % cards)
		if cards < 4:
			fails.append("行动条卡片太少（%d）" % cards)

		# 3) 推进战斗：轮到玩家（p0）就自动攻击，让时间轴一直往前走
		var t := 0.0
		while t < 30.0 and not cm.over:
			if String(bt.get("_phase")) == "input":
				var foes: Array = bt._alive_enemies()
				if not foes.is_empty():
					bt._do_player_attack(foes[0])
				else:
					bt._on_end_turn_pressed()
			await get_tree().create_timer(0.35).timeout
			t += 0.35
		print("[team] 推进 %.1f 秒后：over=%s victory=%s" % [t, str(cm.over), str(cm.victory)])

		# 4) 队友确实出过手（AI 接管生效）
		var acted := 0
		for u in cm.units:
			if u.is_player and u.slot != 0 and u.rounds_taken > 0:
				acted += 1
		print("[team] 出手过的队友数量 %d" % acted)
		if acted < 1:
			fails.append("没有任何队友出过手（AI 没接管？）")

		# 5) 共享指挥点 > 独狼时代的个人值
		var cp: int = cm.command_points()
		print("[team] 共享指挥点 %d（队长智力 2 → 个人只有 1）" % cp)
		if cp < 2:
			fails.append("团队指挥点没有协作加成（%d）" % cp)

		# 6) 行动条的预测与实际一致（抽查一次）
		var pred: Array = []
		var future: Array = cm.timeline(4)
		for u in future:
			pred.append(u.uid)
		var real: Array = []
		for i in 4:
			var nu: CombatUnit = cm.advance_timeline()
			if nu == null:
				break
			real.append(nu.uid)
		if pred != real:
			fails.append("行动条预测与实际不一致")

		var ok := fails.is_empty()
		print("team_battle_test: %s%s" % ["PASS" if ok else "FAIL", "" if ok else " → " + "；".join(fails)])
		get_tree().quit(0 if ok else 1)
