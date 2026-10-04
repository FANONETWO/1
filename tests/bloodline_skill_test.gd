extends Control
## 血统技能实战验证：御剑 / 符箓 / 治愈之手 是否在战斗中真实生效
##   godot --headless --path . res://tests/bloodline_skill_test.tscn --quit-after 1800

func _ready() -> void:
	TestGuard.arm("bloodline_skill_test", 45, get_tree())
	var c := Character.create_default()
	c.name = "技能测试者"
	c.talent_id = "fighter"
	c.attrs = {"str": 4, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3, "blade": 2}
	c.weapon = "bat"
	c.bloodlines = [
		{"id": "immortal", "rank": "C", "picked": ["spirit_sense", "qi_ward", "flying_sword", "talisman"]},
		{"id": "angel", "rank": "C", "picked": ["holy_ward", "faith", "heal_touch", "judgement"]},
	]
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
		await get_tree().create_timer(1.4).timeout
		var sc := get_tree().current_scene
		# 箱庭制：起点楼梯间无敌人，先切到北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.8).timeout
		var cb: Node = sc.get("_battle")
		if cb == null or cb.get("_cm") == null:
			print("bloodline_skill_test: FAIL（战斗未就绪）")
			get_tree().quit(1)
			return
		var cm = cb.get("_cm")
		var pl := Game.player
		var foe: CombatUnit = null
		for u in cm.units:
			if not u.is_player and u.hp > 0:
				foe = u
				break
		if foe == null:
			print("bloodline_skill_test: FAIL（没有敌人）")
			get_tree().quit(1)
			return

		# 注意：战斗中通常有 2 个敌人，技能打的是「最近的」那个，
		# 所以用敌人总血量衡量，而不是盯住某一个单位。
		var t0 := _enemy_total(cm)
		cb._use_blood_skill("flying_sword")
		var t1 := _enemy_total(cm)
		print("[skill] 御剑：敌人总血量 %d → %d（伤害 %d）" % [t0, t1, t0 - t1])

		pl.hp = 5
		cb._apply_player_hp()
		cb._use_blood_skill("heal_touch")
		print("[skill] 治愈之手：生命 5 → %d" % pl.hp)

		var t2 := _enemy_total(cm)
		cb._use_blood_skill("talisman")
		var t3 := _enemy_total(cm)
		print("[skill] 符箓：敌人总血量 %d → %d（伤害 %d）" % [t2, t3, t2 - t3])

		var uses: Dictionary = cb.get("_blood_uses")
		print("[skill] 剩余次数：", uses)
		for i in 4:
			cb._use_blood_skill("heal_touch")
		print("[skill] 次数耗尽后再用：heal_touch =", int(uses.get("heal_touch", -1)))

		var ok: bool = t1 < t0 and t3 < t2 and pl.hp > 5 and int(uses.get("flying_sword", 0)) == 3
		print("bloodline_skill_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)

	func _enemy_total(cm) -> int:
		var n := 0
		for u in cm.units:
			if not u.is_player:
				n += maxi(0, u.hp)
		return n
