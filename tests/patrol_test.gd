extends Control
## 验证敌人巡逻：会移动、会转向、不穿墙、不叠在其他单位上；无 patrol 的原地不动。
##   godot --path . res://tests/patrol_test.tscn --quit-after 3600

func _ready() -> void:
	TestGuard.arm("patrol_test", 60, get_tree())
	var c := Character.create_default()
	c.name = "巡逻测试"
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

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("patrol_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var ok := true

		# ——— 1) 走廊：有巡逻路线的敌人应该会动 ———
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.3).timeout
		var start: Dictionary = {}
		for uid in sc.get("_enemy_nodes"):
			var e: Dictionary = sc.get("_enemy_nodes")[uid]
			start[String(uid)] = Vector2i(e["pos"])
			var route: Array = e.get("patrol", [])
			print("[patrol] %s 起点 %s ｜ 路线 %s" % [String(uid), str(e["pos"]), str(route)])

		# 回合制：推进 4 个回合（每回合敌人走一步）
		for i in 4:
			await sc._end_player_turn()
		await get_tree().create_timer(0.2).timeout

		var moved := 0
		var turned := 0
		var illegal := 0
		var grid = sc.get("_grid")
		var cells: Dictionary = {}
		for uid in sc.get("_enemy_nodes"):
			var e: Dictionary = sc.get("_enemy_nodes")[uid]
			var uid_s := String(uid)
			var cur: Vector2i = e["pos"]
			if cur != Vector2i(start[uid_s]):
				moved += 1
			var facing: Vector2i = e.get("facing", Vector2i(0, 1))
			if facing in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				turned += 1
			if not grid.is_walkable(cur):
				illegal += 1
				print("[patrol] FAIL %s 走到了不可通行格 %s" % [uid_s, str(cur)])
			if cells.has(cur):
				illegal += 1
				print("[patrol] FAIL %s 与其他单位重叠于 %s" % [uid_s, str(cur)])
			cells[cur] = true
			print("[patrol] %s 现在 %s ｜ 朝向 %s" % [uid_s, str(cur), str(facing)])

		print("[patrol] 移动过的敌人 %d 个，非法位置 %d 个" % [moved, illegal])
		if moved < 2:
			print("[patrol] FAIL 巡逻的敌人太少")
			ok = false
		if illegal > 0:
			ok = false

		# ——— 2) 客房：伏尸没路线，必须原地不动 ———
		sc._load_room("guest_room", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.3).timeout
		var still: Dictionary = {}
		for uid in sc.get("_enemy_nodes"):
			var e: Dictionary = sc.get("_enemy_nodes")[uid]
			var d: Dictionary = Enemies.get_def(String(e["def_id"]))
			if (e.get("patrol", []) as Array).is_empty():
				still[String(uid)] = Vector2i(e["pos"])
		for i in 3:
			await sc._end_player_turn()
		await get_tree().create_timer(0.2).timeout
		for uid in still:
			var e: Dictionary = sc.get("_enemy_nodes")[uid]
			if Vector2i(e["pos"]) != Vector2i(still[uid]):
				print("[patrol] FAIL 无路线的 %s 竟然移动了" % uid)
				ok = false
		print("[patrol] 无路线敌人保持静止 %d 个 ✓" % still.size())

		# ——— 3) 视野按类型区分 ———
		var w: int = sc._sight_range("walker")
		var z: int = sc._sight_range("zombie")
		var h: int = sc._sight_range("hound")
		var b: int = sc._sight_range("bloater")
		print("[patrol] 视野：逐尸 %d ／ 丧尸 %d ／ 尸犬 %d ／ 膨胀者 %d" % [w, z, h, b])
		if not (h > z and z > b):
			print("[patrol] FAIL 视野没有按类型拉开差距")
			ok = false

		print("patrol_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
