extends Control
## 体验层截图：新手引导三页 + 跳过后的 HUD + 迷雾「已探索记忆」+ 换箱庭大字幕。
##   godot --path . res://tests/shot_ux.tscn --quit-after 2400
## ⚠️ 不要加 --headless（会截出全黑图）

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "survivor"
	c.attrs = {"str": 3, "dex": 3, "end": 4, "int": 1, "per": 3, "res": 2, "pre": 2, "man": 1, "com": 2}
	c.skills = {"brawl": 1, "blade": 3, "gun": 2, "hide": 3, "survive": 2, "investigate": 3}
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

	const DIR := "res://assets/raw/_probe/"

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path(DIR + name))
		print("[shot] 已保存 " + name)

	func _ready() -> void:
		TestGuard.arm("shot_ux", 30, get_tree())
		await get_tree().create_timer(1.6).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[shot] 场景未就绪")
			get_tree().quit(1)
			return

		# 1) 进场自动弹出的新手引导（三页）
		await _shot("ux_01_引导第1页.png")
		sc._show_tutorial(1)
		await get_tree().create_timer(0.35).timeout
		await _shot("ux_02_引导第2页.png")
		sc._show_tutorial(2)
		await get_tree().create_timer(0.35).timeout
		await _shot("ux_03_引导第3页.png")

		# 2) 跳过后：HUD 常驻房间名 + 底部日志
		sc.skip_tutorial()
		await get_tree().create_timer(0.6).timeout
		await _shot("ux_04_跳过后的HUD.png")

		# 3) 走到走廊走 4 格 → 迷雾「已探索记忆」（走过的格子留暗轮廓）
		sc._load_room("corridor_n", Vector2i.ZERO, "shot")
		await get_tree().create_timer(0.7).timeout
		var p0: Vector2i = sc.get("_player_pos")
		var grid = sc.get("_grid")
		for dir in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var t: Vector2i = p0 + dir * 4
			if grid.is_walkable(t):
				sc._move_to(t)
				break
		await get_tree().create_timer(2.2).timeout
		await _shot("ux_05_移动后的迷雾记忆.png")

		# 4) 换箱庭 → 中央大字幕（房间辨识度）
		sc._load_room("room_402", Vector2i.ZERO, "shot")
		await get_tree().create_timer(0.45).timeout
		await _shot("ux_06_换房间大字幕.png")

		print("[shot] 体验层 6 张截图完成")
		get_tree().quit(0)
