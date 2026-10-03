extends Control
## 高频连拍技能特效：触发一次玩家攻击，每 0.06s 截一帧。
##   godot --path . res://tests/shot_skill_fx.tscn --quit-after 2400

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {"str": 5, "dex": 4, "end": 4, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 4, "blade": 3}
	c.weapon = "machete"
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
		sc._start_combat_with("zombie", true)
		await get_tree().create_timer(0.9).timeout
		var bt = sc.get("_battle")
		if bt == null:
			print("[fx] 战斗未创建")
			get_tree().quit(1)
			return
		var foes: Array = bt._alive_enemies()
		if foes.is_empty():
			print("[fx] 没有敌人")
			get_tree().quit(1)
			return
		print("[fx] 触发一次攻击，开始高频连拍（每 0.06s）")
		bt._do_player_attack(foes[0])
		for i in 12:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("res://assets/raw/_probe/fx_%02d.png" % i))
			await get_tree().create_timer(0.06).timeout
		print("[fx] 连拍 12 帧完成")
		get_tree().quit(0)
