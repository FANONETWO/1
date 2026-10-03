extends Control
## 战斗节奏测量：自动打完一场普通遭遇，统计回合数与真实耗时。
##   godot --path . res://tests/pace_test.tscn --quit-after 12000

func _ready() -> void:
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
		sc._start_combat_with("zombie")
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
		while not cm.over and guard < 500:
			guard += 1
			if cm.is_player_turn():
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
		get_tree().quit(0)
