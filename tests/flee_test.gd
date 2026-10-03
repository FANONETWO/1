extends Control
## 验证「逃跑 ≠ 战败」：按逃跑应退回上一间箱庭，而不是直接判死。
##   godot --path . res://tests/flee_test.tscn --quit-after 3600

func _ready() -> void:
	var c := Character.create_default()
	c.name = "逃跑测试"
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
			print("flee_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var ok := true

		# 先进北走廊，再进大堂 —— 这样「来路」是走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		sc._load_room("lobby", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		print("[flee] 当前 %s ｜ 来路 %s" % [String(sc.get("_room_id")), String(sc.get("_prev_room"))])

		# 开战
		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.5).timeout
		var bt = sc.get("_battle")
		if bt == null:
			print("flee_test: FAIL（战斗未创建）")
			get_tree().quit(1)
			return

		# 按「逃跑」
		bt._finish(false, true)
		await get_tree().create_timer(1.8).timeout

		var after := String(sc.get("_room_id"))
		var still_here := get_tree().current_scene == sc
		print("[flee] 逃跑后：房间 %s（应 corridor_n）｜ 场景仍在探索 %s（应 true）" % [after, str(still_here)])

		if not still_here:
			print("[flee] FAIL 逃跑把玩家判死并切走了场景")
			ok = false
		if after != "corridor_n":
			print("[flee] FAIL 逃跑没有退回上一间")
			ok = false

		# 再验证「真战败」仍然判死（不能把两者混为一谈）
		sc._load_room("lobby", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		sc._start_combat_with("walker")
		await get_tree().create_timer(1.4).timeout
		var bt2 = sc.get("_battle")
		if bt2 != null:
			# 判死是「在同一场景上弹结算面板」，不是切场景 —— 抓事件才准
			var settled := [false]
			EventBus.scenario_finished.connect(func(_r): settled[0] = true)
			bt2._finish(false, false)          # 非逃跑的战败
			await get_tree().create_timer(2.2).timeout
			print("[flee] 真战败后触发结算 %s（应 true）" % str(settled[0]))
			if not settled[0]:
				print("[flee] FAIL 战败没有结算")
				ok = false
		else:
			print("[flee] 跳过战败验证（第二场未开起来）")

		print("flee_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
