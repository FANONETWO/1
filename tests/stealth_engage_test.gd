extends Control
## 追逐机制验证（原「看到就开战」已改为「看到 → 追 → 贴上才打」）：
##   1. 站进敌人正面视野 → 它 alerted=true，但**不**立刻开战
##   2. 敌人回合里它朝你走近（距离缩短）
##   3. 贴到身上（曼哈顿 ≤ 1）→ 这时才接敌，且敌人先手
##   godot --headless --path . res://tests/stealth_engage_test.tscn --quit-after 5400

func _ready() -> void:
	TestGuard.arm("stealth_engage_test", 120, get_tree())
	var c := Character.create_default()
	c.name = "追逐测试"
	c.talent_id = "fighter"
	c.attrs = {"str": 4, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3, "blade": 2}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	Game.set_mode(Game.MODE_SOLO)
	Game.set_team([])
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	var fails: Array[String] = []

	func _ok(cond: bool, label: String) -> void:
		if cond:
			print("  ok - " + label)
		else:
			fails.append(label)
			printerr("  FAIL - " + label)

	func _dist(a: Vector2i, b: Vector2i) -> int:
		return absi(a.x - b.x) + absi(a.y - b.y)

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			printerr("  FAIL - 场景未就绪")
			get_tree().quit(1)
			return
		sc.skip_tutorial()
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.3).timeout

		var enemies: Dictionary = sc.get("_enemy_nodes")
		var grid = sc.get("_grid")
		# 找一个「正面 2 格、可站立、视线通畅」的敌人：踩进它视野，但还没贴脸
		var uid := ""
		var front := Vector2i.ZERO
		for k in enemies:
			var e: Dictionary = enemies[k]
			var f: Vector2i = e.get("facing", Vector2i(0, 1))
			var cand: Vector2i = (e["pos"] as Vector2i) + f * 2
			if grid.is_walkable(cand) and grid.has_line_of_sight(e["pos"], cand):
				uid = String(k)
				front = cand
				break
		if uid == "":
			printerr("  FAIL - 找不到视线通畅的敌人")
			get_tree().quit(1)
			return

		sc.set("_player_pos", front)
		sc._position_entity(sc.get("_player_sprite"), front)
		sc._refresh_fog()
		await get_tree().create_timer(0.3).timeout

		# ——— 1) 被发现 ≠ 开战 ———
		var sees: bool = sc._in_enemy_sight(uid)
		sc._update_enemy_alert()
		var alerted: bool = bool((enemies[uid] as Dictionary).get("alerted", false))
		var battle_now = sc.get("_battle")
		print("  · 敌人看到你 = %s ｜ alerted = %s ｜ 当场开战 = %s" % [
			str(sees), str(alerted), str(battle_now != null)])
		_ok(sees, "站在正面视野内：敌人看得见你")
		_ok(alerted, "被发现后进入追逐状态（alerted=true）")
		_ok(battle_now == null, "被发现**不**立刻开战（这是潜行能玩的前提）")

		# ——— 2) 敌人回合里朝你走近 ———
		var d0 := _dist((enemies[uid] as Dictionary)["pos"], sc.get("_player_pos"))
		sc._end_player_turn()
		await get_tree().create_timer(2.4).timeout
		var d1 := _dist((enemies[uid] as Dictionary)["pos"], sc.get("_player_pos"))
		print("  · 追击前后距离：%d → %d" % [d0, d1])
		_ok(d1 < d0 or sc.get("_battle") != null, "敌人回合里朝玩家靠近（%d → %d）" % [d0, d1])

		# ——— 3) 一直推进到贴上 → 这时才开战 ———
		var rounds := 1
		while sc.get("_battle") == null and rounds < 10:
			sc._end_player_turn()
			await get_tree().create_timer(2.4).timeout
			rounds += 1
		var bt = sc.get("_battle")
		var enemy_first: bool = bt != null and not bool(bt.get("_surprise"))
		print("  · 第 %d 回合接敌 = %s ｜ 敌人先手 = %s" % [rounds, str(bt != null), str(enemy_first)])
		_ok(bt != null, "贴上之后才进入战斗")
		_ok(enemy_first, "被追上开战 → 敌人先手（不是突袭）")

		var ok := fails.is_empty()
		print("stealth_engage_test: %s%s" % ["PASS" if ok else "FAIL (%d)" % fails.size(),
			"" if ok else " → " + "；".join(fails)])
		get_tree().quit(0 if ok else 1)
