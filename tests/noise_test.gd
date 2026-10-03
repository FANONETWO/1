extends Control
## 噪音机制验证：噪音跨过阈值 → 从远处刷出敌人；每 5 秒衰减 1。
##   godot --path . res://tests/noise_test.tscn --quit-after 2400

func _ready() -> void:
	var c := Character.create_default()
	c.name = "噪音测试"
	c.talent_id = "fighter"
	c.attrs = {"str": 3, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3}
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

	func _count(sc) -> int:
		return (sc.get("_enemy_nodes") as Dictionary).size()

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("noise_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var base := _count(sc)
		print("[noise] 初始敌人 %d 只，噪音 %d" % [base, int(sc.get("_noise"))])

		# 1) 到 T1：招来 1 只
		sc._add_noise(6, "测试")
		await get_tree().create_timer(0.25).timeout
		var a1 := _count(sc)
		print("[noise] 噪音→6 　敌人 %d（+%d，应 +1）" % [a1, a1 - base])

		# 2) 再到 T2：招来爬行者
		sc._add_noise(7, "测试")
		await get_tree().create_timer(0.25).timeout
		var a2 := _count(sc)
		print("[noise] 噪音→10　敌人 %d（+%d，应 +1）" % [a2, a2 - a1])

		# 3) 到 T3：尸潮 3 只
		sc.set("_noise", 16)
		sc._check_noise_spawn()
		await get_tree().create_timer(0.25).timeout
		var a3 := _count(sc)
		print("[noise] 噪音→16　敌人 %d（+%d，应 +3 尸潮）" % [a3, a3 - a2])

		# 4) 刷出的敌人朝玩家（视野锥应指向玩家方向）
		var nearest := ""
		var nd := 9999
		for uid in sc.get("_enemy_nodes"):
			var e: Dictionary = sc.get("_enemy_nodes")[uid]
			var d: int = absi(Vector2i(e["pos"]).x - Vector2i(sc.get("_player_pos")).x) \
				+ absi(Vector2i(e["pos"]).y - Vector2i(sc.get("_player_pos")).y)
			if d < nd:
				nd = d
				nearest = String(uid)
		print("[noise] 最近敌人 %s，距离 %d" % [nearest, nd])

		# 5) 衰减：直接推进时间轴，验证 _tick_noise 会减噪
		var n0 := int(sc.get("_noise"))
		for i in 6:
			sc._tick_noise(1.0)
		var n1 := int(sc.get("_noise"))
		print("[noise] 衰减：%d → %d（应至少 −1）" % [n0, n1])

		var ok: bool = (a1 == base + 1) and (a2 == a1 + 1) and (a3 == a2 + 3) and (n1 < n0)
		print("noise_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
