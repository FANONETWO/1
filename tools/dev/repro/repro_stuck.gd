extends Control
## 复现「用技能后卡住」：用符箓 → 结束回合 → 观察敌人回合是否推进
##   godot --headless --path . res://tools/dev/repro/repro_stuck.tscn --quit-after 2000

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
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
		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.8).timeout
		var cb := get_tree().current_scene
		if cb == null or cb.get("_cm") == null:
			print("[repro] 战斗场景未就绪")
			get_tree().quit(1)
			return
		var cm = cb.get("_cm")
		_dump(cb, cm, "0 初始")

		var foe: CombatUnit = null
		for u in cm.units:
			if not u.is_player and u.hp > 0:
				foe = u
				break
		if foe == null:
			print("[repro] 没有敌人")
			get_tree().quit(1)
			return

		cb._use_blood_skill_at("talisman", foe.pos)
		await get_tree().create_timer(0.5).timeout
		_dump(cb, cm, "1 用符箓后")

		cb._on_end_turn_pressed()
		await get_tree().create_timer(0.5).timeout
		_dump(cb, cm, "2 结束回合后")

		for i in 8:
			await get_tree().create_timer(0.5).timeout
			_dump(cb, cm, "3 t=%.1fs" % (float(i + 1) * 0.5))

		print("[repro] 结束")
		get_tree().quit(0)

	func _dump(cb, cm, tag: String) -> void:
		var cur: CombatUnit = cm.current()
		print("[repro] %s ｜ 玩家回合=%s 敌人回合运行=%s 行动者=%s over=%s 玩家HP=%d" % [
			tag,
			str(cm.is_player_turn()),
			str(cb.get("_enemy_turn_running")),
			cur.name if cur != null else "无",
			str(cm.over),
			Game.player.hp,
		])
