extends Control
## 连拍战斗画面，验证帧动画（静图看不出"动"，必须连拍成序列）。
##   godot --path . res://tests/shot_anim_frames.tscn --quit-after 2400

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {"str": 5, "dex": 4, "end": 4, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 4, "blade": 2}
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
			print("[anim] 战斗未创建")
			get_tree().quit(1)
			return
		print("[anim] 开始连拍（每 0.22s 一帧，共 8 帧）")
		for i in 8:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("res://assets/raw/_probe/anim_%d.png" % i))
			await get_tree().create_timer(0.22).timeout
		print("[anim] 完成 8 帧")
		get_tree().quit(0)
