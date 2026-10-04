extends Control
## 指令菜单截图（火纹式入口 + 本作 AP / D10 骰池 / 血脉状态）
##   godot --path . res://tools/dev/shots/shot_cmd_menu.tscn --quit-after 900

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
	c.inventory = ["medkit", "blood_stabilizer"]
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
		# 挪到敌人旁边，让「攻击」指令可用
		for u in cm.units:
			if not u.is_player and u.hp > 0:
				cm.player_unit.pos = u.pos + Vector2i(1, 0)
				cb._move_node(cm.player_unit, cm.player_unit.pos)
				break
		await get_tree().create_timer(0.5).timeout
		cb._open_command_menu()
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://assets/raw/_probe/cmd_menu.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("[shot] 指令菜单已保存：", path)
		print("[shot] 菜单项数 =", cb.get("_cmd_menu").get_child(0).get_child_count())
		get_tree().quit(0)
