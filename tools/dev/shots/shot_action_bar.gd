extends Control
## 行动条 + 团队模式截图：4 人对峙、顶部行动条、共享指挥点。
##   godot --path . res://tools/dev/shots/shot_action_bar.tscn --quit-after 3000
## ⚠️ 不要加 --headless（会截出全黑图）

func _ready() -> void:
	var c := Character.create_default()
	c.name = "队长"
	c.talent_id = "survivor"
	c.attrs = {"str": 3, "dex": 3, "end": 4, "int": 2, "per": 3, "res": 2, "pre": 2, "man": 1, "com": 2}
	c.skills = {"blade": 3, "hide": 3, "investigate": 3}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	Game.set_mode(Game.MODE_TEAM)
	Game.set_team(Allies.make_allies(3))
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/" + name))
		print("[shot] 已保存 " + name)

	func _ready() -> void:
		TestGuard.arm("shot_action_bar", 40.0, get_tree())
		await get_tree().create_timer(1.6).timeout
		var sc := get_tree().current_scene
		sc.skip_tutorial()
		sc._load_room("corridor_n", Vector2i.ZERO, "shot")
		await get_tree().create_timer(0.5).timeout
		sc._start_combat_with("zombie")
		await get_tree().create_timer(2.6).timeout
		await _shot("action_bar_team.png")

		# 打开战术菜单再拍一张（展示指挥点干预）
		var bt = sc.get("_battle")
		if bt != null and String(bt.get("_phase")) == "input":
			bt._on_cmd_tactic()
			await get_tree().create_timer(0.5).timeout
			await _shot("action_bar_tactic.png")

		print("[shot] 行动条截图完成")
		get_tree().quit(0)
