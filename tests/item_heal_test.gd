extends Control
## 守住「医疗包必须真的回血」。
##
## 曾经的真 bug：BattleScene._apply_player_hp() 把 Character.hp 覆盖到 CombatUnit.hp
## （方向写反），导致 try_use_item 加的血被当场盖掉 —— 表现是"连吃四个急救包血还在掉"。
## 这个测试在**真实战斗场景**里点「物品 → 急救包」，断言玩家血量确实上升。
##
##   & $godot --path . res://tests/item_heal_test.tscn --quit-after 3600

func _ready() -> void:
	TestGuard.arm("item_heal_test", 45, get_tree())
	var c := Character.create_default()
	c.name = "用药测试"
	c.talent_id = "fighter"
	# 耐力堆高一点，免得被打死干扰观察
	c.attrs = {"str": 2, "dex": 2, "end": 3, "int": 1, "per": 1, "res": 1, "pre": 1, "man": 1, "com": 1}
	c.skills = {"brawl": 2}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	c.inventory.append("medkit")
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
			print("item_heal_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return

		# 进走廊开战
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		sc._start_combat_with("walker")
		await get_tree().create_timer(1.5).timeout
		var bt = sc.get("_battle")
		if bt == null:
			print("item_heal_test: FAIL（战斗未创建）")
			get_tree().quit(1)
			return

		var cm = bt.get("_cm")
		var pu = cm.player_unit
		# 先把血打低，再吃药，观察是否真的回升
		var low := maxi(2, pu.max_hp / 3)
		pu.hp = low
		sc.get("_player").hp = low
		pu.ap = 6                      # 给足行动点，否则用药会被拒（行动点不足）
		bt._apply_player_hp()
		await get_tree().create_timer(0.3).timeout

		var before_unit: int = int(pu.hp)
		var before_char: int = int(sc.get("_player").hp)
		var res: Dictionary = cm.try_use_item(pu, "medkit")
		bt._apply_player_hp()
		await get_tree().create_timer(0.3).timeout

		var after_unit: int = int(pu.hp)
		var after_char: int = int(sc.get("_player").hp)
		print("[heal] 用药前：战斗单位 %d ／ 角色卡 %d" % [before_unit, before_char])
		print("[heal] 用药后：战斗单位 %d ／ 角色卡 %d" % [after_unit, after_char])
		print("[heal] 返回：%s" % str(res))

		var ok := true
		if not res.get("ok", false):
			print("[heal] FAIL 用药被拒绝")
			ok = false
		if after_unit <= before_unit:
			print("[heal] FAIL 战斗单位血量没有上升（%d → %d）" % [before_unit, after_unit])
			ok = false
		if after_char <= before_char:
			print("[heal] FAIL 角色卡血量没有上升（%d → %d）—— _apply_player_hp 方向可能又反了" % [before_char, after_char])
			ok = false
		if after_unit != after_char:
			print("[heal] FAIL 两处血量不同步（%d vs %d）" % [after_unit, after_char])
			ok = false

		print("item_heal_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
