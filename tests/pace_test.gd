extends Control
## 战斗节奏测量：自动打完一场普通遭遇，统计回合数与真实耗时。
##   godot --path . res://tests/pace_test.tscn --quit-after 12000

func _ready() -> void:
	TestGuard.arm("pace_test", 45, get_tree())
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {"str": 4, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3, "blade": 2}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		sc.skip_tutorial()
		# 起始房间（楼梯间）没有敌人 → 先切到有普通丧尸的箱庭，否则战斗根本不会创建
		var pick_room := ""
		var pick_id := ""
		for rid in R001Rooms.ROOMS:
			for e in R001Rooms.ROOMS[rid].get("enemies", []):
				if String(e.get("id", "")) == "zombie":
					pick_room = String(rid)
					pick_id = "zombie"
					break
			if pick_id != "":
				break
		if pick_id == "":
			print("[pace] 找不到带普通丧尸的箱庭，跳过")
			get_tree().quit(0)
			return
		sc._load_room(pick_room, Vector2i.ZERO, "")
		await get_tree().create_timer(0.4).timeout
		sc._start_combat_with(pick_id)
		await get_tree().create_timer(1.0).timeout
		var bt = sc.get("_battle")
		if bt == null:
			print("[pace] 战斗未创建")
			get_tree().quit(1)
			return
		var cm = bt.get("_cm")
		var max_hp: int = cm.player_unit.max_hp
		var foe_hp: int = 0
		for u in cm.units:
			if not u.is_player:
				foe_hp += u.max_hp
		print("[pace] 开局：玩家 HP %d ｜ 敌人总 HP %d ｜ 玩家单次伤害约 %d" % [
			max_hp, foe_hp, cm.player_unit.char_ref.weapon_damage() if cm.player_unit.char_ref else 0])

		var t0 := Time.get_ticks_msec()
		var guard := 0
		# 测量型测试必须有界：120 × 0.3s ≈ 36 秒。
		# （原来写 500 步 = 150 秒，一旦这局打不完就会把整批回归拖到超时）
		var guard_max := 120
		var player_turns := 0     # 玩家真正轮到行动的次数 —— 用来区分「打不动」和「根本轮不到玩家」
		var sync_ok := true       # 战斗 UI 轮的到玩家时，CM 的 is_player_turn() 也必须为 true
		while not cm.over and guard < guard_max:
			guard += 1
			# 以 UI 的真状态 `_phase == "input"` 为准（CM 的 turn_index 由 set_current 同步）
			if String(bt.get("_phase")) == "input":
				player_turns += 1
				if not cm.is_player_turn():
					sync_ok = false
				var foes: Array = bt._alive_enemies()
				if not foes.is_empty():
					bt._do_player_attack(foes[0])
			await get_tree().create_timer(0.3).timeout
		var ms := Time.get_ticks_msec() - t0

		# 统计：每个单位的平均出手次数（近似回合轮数）
		print("[pace] 结果：over=%s victory=%s" % [str(cm.over), str(cm.victory)])
		print("[pace] 回合计数 round=%d ｜ 循环步数=%d" % [int(cm.round), guard])
		print("[pace] 真实耗时 %.1f 秒（含所有动画与停顿）" % (float(ms) / 1000.0))
		print("[pace] 玩家剩余 HP %d / %d" % [cm.player_unit.hp, max_hp])
		# 给出「一轮 = 所有单位各出手一次」的估算
		var units_n: int = cm.units.size()
		print("[pace] 单位数 %d → 每轮约 %.1f 秒" % [
			units_n, (float(ms) / 1000.0) / maxf(1.0, float(cm.round))])
		if not cm.over:
			print("[pace] 注意：%d 步（约 %.0f 秒）内未分出胜负 —— 玩家出手 %d 次" % [
				guard_max, float(ms) / 1000.0, player_turns])
		if not sync_ok:
			print("[pace] FAIL：UI 轮到玩家时 cm.is_player_turn() 仍为 false（回合同步失效）")
			get_tree().quit(1)
			return
		print("pace_test: PASS（%d 回合 / %.1f 秒 / 玩家出手 %d 次）" % [
			int(cm.round), float(ms) / 1000.0, player_turns])
		get_tree().quit(0)
