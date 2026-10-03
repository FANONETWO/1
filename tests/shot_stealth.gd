extends Control
## 潜行视野截图：站在敌人视野锥之外（背后），红色格是它的视野范围。
##   godot --path . res://tests/shot_stealth.tscn --quit-after 1200

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {"str": 4, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3, "blade": 2}
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

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[shot] 场景未就绪")
			get_tree().quit(1)
			return
		var enemies: Dictionary = sc.get("_enemy_nodes")
		var uid := "enemy_5_5"
		if not enemies.has(uid):
			for k in enemies:
				uid = String(k)
				break
		var e: Dictionary = enemies[uid]
		var facing: Vector2i = e.get("facing", Vector2i(0, 1))
		# 站到敌人**背后 3 格**：视野锥之外 → 盲区
		var behind: Vector2i = (e["pos"] as Vector2i) - facing * 3
		sc.set("_player_pos", behind)
		sc._position_entity(sc.get("_player_sprite"), behind)
		sc._refresh_sight()
		await get_tree().create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/stealth.png"))
		var sees: bool = sc._in_enemy_sight(uid)
		print("[shot] 目标 %s 朝向 %s ｜ 玩家在 %s ｜ 敌人能看到 = %s" % [
			String(e["def_id"]), str(facing), str(behind), str(sees),
		])
		print("[shot] 已保存 stealth.png")
		get_tree().quit(0 if not sees else 1)
