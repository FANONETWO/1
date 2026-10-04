extends Control
## 开局 UI 截图：主菜单 / 建卡 / 主神空间。
##   godot --path . res://tools/dev/shots/shot_menu.tscn --quit-after 900
## ⚠️ 不要加 --headless（会截出全黑图）

func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())
	get_tree().change_scene_to_file.call_deferred("res://ui/main_menu.tscn")

class Driver:
	extends Node

	const OUT := "res://assets/raw/_probe/"

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path(OUT + name))
		print("[shot] " + name)

	func _ready() -> void:
		TestGuard.arm("shot_menu", 60.0, get_tree())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		await get_tree().create_timer(1.6).timeout
		await _shot("ui_main_menu.png")

		# 建卡（推荐配点后，能看到属性/技能/模式都填满的样子）
		get_tree().change_scene_to_file("res://ui/char_creation.tscn")
		await get_tree().create_timer(1.4).timeout
		var cc := get_tree().current_scene
		if cc != null and cc.has_method("_apply_recommended"):
			cc._apply_recommended()
			await get_tree().create_timer(0.4).timeout
		await _shot("ui_char_creation.png")
		# 分步向导：逐页截图（属性 / 技能 / 天赋 / 确认）
		for i in range(1, 5):
			if cc != null and cc.has_method("_goto_step"):
				cc._goto_step(i)
				await get_tree().create_timer(0.5).timeout
				await _shot("ui_step_%d.png" % (i + 1))

		# 主神空间（团队模式，展示队伍与模式）
		Game.new_game()
		var c := Character.create_default()
		c.name = "幸存者"
		c.talent_id = "survivor"
		c.attrs = {"str": 3, "dex": 3, "end": 4, "int": 2, "per": 3, "res": 2, "pre": 2, "man": 1, "com": 2}
		c.skills = {"blade": 3, "hide": 3, "investigate": 3}
		c.weapon = "bat"
		c.hp = c.max_hp()
		c.will = c.max_will()
		Game.set_player(c)
		Game.set_mode(Game.MODE_TEAM)
		Game.set_team(Allies.make_allies(3))
		get_tree().change_scene_to_file("res://ui/hub.tscn")
		await get_tree().create_timer(1.4).timeout
		await _shot("ui_hub.png")

		print("[shot] 开局 UI 截图完成")
		get_tree().quit(0)
