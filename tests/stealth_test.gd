extends Control
## 潜行突袭验证（只测一件事）：从敌人视野盲区（背后）接近 → 点击敌人 → **玩家抢到先手**。
##   godot --headless --path . res://tests/stealth_test.tscn --quit-after 1800

func _ready() -> void:
	TestGuard.arm("stealth_test", 45, get_tree())
	var c := Character.create_default()
	c.name = "潜行测试"
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
		if sc == null:
			print("stealth_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		# 箱庭制：先切到有敌人的北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		var enemies: Dictionary = sc.get("_enemy_nodes")
		if enemies.is_empty():
			print("stealth_test: FAIL（走廊里没有敌人）")
			get_tree().quit(1)
			return
		var uid := String(enemies.keys()[0])
		var e: Dictionary = enemies[uid]
		var facing: Vector2i = e.get("facing", Vector2i(0, 1))
		# 站到敌人**背后一格**（视野盲区）
		var behind: Vector2i = (e["pos"] as Vector2i) - facing
		sc.set("_player_pos", behind)
		sc._position_entity(sc.get("_player_sprite"), behind)
		await get_tree().create_timer(0.3).timeout

		var sees: bool = sc._in_enemy_sight(uid)
		print("[stealth] 目标 %s 朝向 %s ｜ 玩家在背后 %s ｜ 敌人看到玩家 = %s（应 false）" % [
			String(e["def_id"]), str(facing), str(behind), str(sees),
		])
		if sees:
			print("stealth_test: FAIL（背后不该被看到）")
			get_tree().quit(1)
			return

		# 主动出手 → 突袭，玩家先手
		sc._start_combat_with(String(e["def_id"]), true)
		await get_tree().create_timer(1.5).timeout
		var bt = sc.get("_battle")
		var cm = bt.get("_cm") if bt != null else null
		var player_first: bool = cm != null and cm.is_player_turn()
		print("[stealth] 突袭后玩家先手 = %s（应 true）｜surprise=%s" % [
			str(player_first), str(bt.get("_surprise")) if bt != null else "无",
		])
		var ok: bool = (not sees) and player_first
		print("stealth_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
