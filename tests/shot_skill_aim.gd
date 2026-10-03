extends Control
## 技能瞄准范围截图：单体（高亮射程内敌人）与群体（高亮射程内所有格）
##   godot --path . res://tests/shot_skill_aim.tscn --quit-after 1100

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
			print("[shot] 战斗场景未就绪")
			get_tree().quit(1)
			return
		var cm = cb.get("_cm")
		# 站到敌人斜后方 2 格：射程内有目标，但不贴脸
		for u in cm.units:
			if not u.is_player and u.hp > 0:
				cm.player_unit.pos = u.pos + Vector2i(2, 1)
				cb._move_node(cm.player_unit, cm.player_unit.pos)
				break
		await get_tree().create_timer(0.5).timeout

		# 单体技能：御剑（射程 5）→ 只高亮射程内的敌人
		cb._begin_skill_aim("flying_sword")
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/aim_single.png"))
		print("[shot] 单体瞄准已保存（御剑 射程 5）")

		# 群体技能：万剑诀（射程 4 / 半径 2）→ 高亮射程内所有格
		cb._begin_skill_aim("myriad_swords")
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/aim_aoe.png"))
		print("[shot] 群体瞄准已保存（万剑诀 射程 4 / 半径 2）")
		get_tree().quit(0)
