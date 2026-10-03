extends Control
## 验证副本进度的持久性（唯一状态源 Game.dungeon）：
##   击杀 → 切走 → 切回，尸体必须不在；线索也必须还在。
##   godot --path . res://tests/persist_test.tscn --quit-after 3600

func _ready() -> void:
	var c := Character.create_default()
	c.name = "持久化测试"
	c.talent_id = "fighter"
	c.attrs = {"str": 4, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 4}
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
			print("persist_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var ok := true

		# ——— 1) 击杀持久化 ———
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		var before: int = (sc.get("_enemy_nodes") as Dictionary).size()
		print("[persist] 走廊初始敌人 %d" % before)

		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.5).timeout
		var bt = sc.get("_battle")
		if bt == null:
			print("persist_test: FAIL（战斗未创建）")
			get_tree().quit(1)
			return
		var cm = bt.get("_cm")
		# 走**真实结算路径**打死敌人 —— 直接设 hp=0 不会进 killed_uids
		var foe: CombatUnit = null
		for u in cm.units:
			if not u.is_player and u.hp > 0:
				foe = u
				break
		if foe == null:
			print("persist_test: FAIL（没有敌人）")
			get_tree().quit(1)
			return
		foe.defense = 0
		foe.armor = 0
		var guard := 0
		while foe.hp > 0 and guard < 80:
			guard += 1
			cm.player_unit.hp = 999
			cm.player_unit.char_ref.hp = 999
			cm.resolve_attack(cm.player_unit, foe)
		print("[persist] 目标已击杀 hp=%d ｜ killed_uids=%s" % [foe.hp, str(bt.killed_uids)])
		cm.over = true
		cm.victory = true
		bt._finish(true, false)
		await get_tree().create_timer(1.8).timeout
		print("[persist] _finish 后：killed_uids=%s ｜ _battle=%s ｜ Game.killed=%s" % [
			str(bt.killed_uids) if is_instance_valid(bt) else "(已释放)",
			"null" if sc.get("_battle") == null else "仍在",
			str(Game.dungeon_state("r001_apartment")["killed"].keys())])

		var after_kill: int = (sc.get("_enemy_nodes") as Dictionary).size()
		print("[persist] 战斗胜利后 %d（应 < %d）" % [after_kill, before])
		if after_kill >= before:
			ok = false

		# 切走 → 切回
		sc._load_room("stair_hall", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		var after_back: int = (sc.get("_enemy_nodes") as Dictionary).size()
		print("[persist] 切走再切回后 %d（应 == %d）" % [after_back, after_kill])
		if after_back != after_kill:
			ok = false

		# ——— 2) 线索持久化 ———
		sc._add_clue("test_clue", "这是一条测试线索")
		var n1: int = sc._clue_count()
		sc._load_room("lobby", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		var n2: int = sc._clue_count()
		print("[persist] 线索数：切房间前 %d → 切房间后 %d（应相同）" % [n1, n2])
		if n2 != n1 or n2 < 1:
			ok = false

		# ——— 3) 跨 new_game 会清空（不该把上一局带过来）———
		print("persist_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
