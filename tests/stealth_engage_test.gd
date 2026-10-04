extends Control
## 被察觉验证（只测一件事）：站在敌人**正面视野**内 → 自动接敌 → **敌人先手**。
##   godot --headless --path . res://tests/stealth_engage_test.tscn --quit-after 1800

func _ready() -> void:
	TestGuard.arm("stealth_engage_test", 45, get_tree())
	var c := Character.create_default()
	c.name = "察觉测试"
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
			print("stealth_engage_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		# 箱庭制：起点楼梯间是安全区，先切到有敌人的北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		var enemies: Dictionary = sc.get("_enemy_nodes")
		var grid = sc.get("_grid")
		# 找一个「正面 2 格、可站立、且视线不被墙挡住」的敌人。
		# （LOS 接入后不能再硬编码 uid —— 有的敌人正面恰好隔着墙）
		var uid := ""
		var front := Vector2i.ZERO
		var facing := Vector2i.ZERO
		for k in enemies:
			var e: Dictionary = enemies[k]
			var f: Vector2i = e.get("facing", Vector2i(0, 1))
			var cand: Vector2i = (e["pos"] as Vector2i) + f * 2
			if grid.is_walkable(cand) and grid.has_line_of_sight(e["pos"], cand):
				uid = String(k)
				front = cand
				facing = f
				break
		if uid == "":
			print("stealth_engage_test: FAIL（找不到视线通畅的敌人）")
			get_tree().quit(1)
			return
		var e: Dictionary = enemies[uid]
		sc.set("_player_pos", front)
		sc._position_entity(sc.get("_player_sprite"), front)
		await get_tree().create_timer(0.3).timeout

		var sees: bool = sc._in_enemy_sight(uid)
		print("[engage] 目标 %s 朝向 %s ｜ 玩家在正面 %s ｜ 敌人看到玩家 = %s（应 true）" % [
			String(e["def_id"]), str(facing), str(front), str(sees),
		])
		var engaged: bool = sc._check_engagement()
		await get_tree().create_timer(0.7).timeout
		var bt = sc.get("_battle")
		var enemy_first: bool = bt != null and not bool(bt.get("_surprise"))
		print("[engage] 自动接敌 = %s ｜ 敌人先手 = %s（应 true）" % [str(engaged), str(enemy_first)])
		var ok: bool = sees and engaged and enemy_first
		print("stealth_engage_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
