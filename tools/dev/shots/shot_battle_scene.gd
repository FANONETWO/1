extends Control
## 标准回合制战斗界面截图（主角在左、怪物在右）
##   godot --path . res://tools/dev/shots/shot_battle_scene.tscn --quit-after 1500

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
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[shot] 场景未就绪")
			get_tree().quit(1)
			return
		sc._start_combat_with("zombie", true)
		await get_tree().create_timer(1.4).timeout

		var bt = sc.get("_battle")
		if bt == null:
			print("[shot] 战斗未创建")
			get_tree().quit(1)
			return
		print("[shot] 战斗界面 = %s ｜ 回合 %d ｜ 阶段 %s" % [
			bt.get_class(), int(bt.get("_round")), String(bt.get("_phase")),
		])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/battle_scene.png"))
		print("[shot] 已保存 battle_scene.png（含指令菜单）")

		# 打开血统技能子菜单再截一张
		bt._on_cmd_skill()
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/battle_skill.png"))
		print("[shot] 已保存 battle_skill.png（血统技能列表）")
		get_tree().quit(0)
