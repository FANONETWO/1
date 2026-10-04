extends Control
## 潜行视野截图：站在某个敌人背后 3 格（盲区），画面上应同时有
##   亮红 = 此刻会看见你的敌人视野
##   暗红 = 其它敌人的视野（预警）
##   godot --path . res://tools/dev/shots/shot_stealth.tscn --quit-after 1200

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
	Game.set_mode(Game.MODE_SOLO)
	Game.set_team([])
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		TestGuard.arm("shot_stealth", 40.0, get_tree())
		await get_tree().create_timer(1.6).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[shot] 场景未就绪")
			get_tree().quit(1)
			return
		sc.skip_tutorial()
		# 主走廊：多个敌人 + 巡逻路线（起始房间没有敌人，旧脚本就是在这儿崩的）
		sc._load_room("corridor_n", Vector2i.ZERO, "shot")
		await get_tree().create_timer(0.7).timeout

		var enemies: Dictionary = sc.get("_enemy_nodes")
		if enemies.is_empty():
			print("[shot] 本房间没有敌人，换个房间再试")
			get_tree().quit(1)
			return
		var uid := ""
		for k in enemies:
			uid = String(k)
			break
		var e: Dictionary = enemies[uid]
		var facing: Vector2i = e.get("facing", Vector2i(0, 1))
		# 站到它**背后 3 格**：视野锥之外 → 盲区
		var behind: Vector2i = (e["pos"] as Vector2i) - facing * 3
		sc.set("_player_pos", behind)
		sc._position_entity(sc.get("_player_sprite"), behind)
		sc._refresh_fog()
		sc._refresh_sight()
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/stealth.png"))

		var map = sc.get("_map")
		var danger: Array = map.get("_attack")
		var watch: Array = map.get("_watch")
		var sees: bool = sc._in_enemy_sight(uid)
		print("[shot] 目标 %s 朝向 %s ｜ 玩家在 %s" % [String(e["def_id"]), str(facing), str(behind)])
		print("[shot] 亮红 %d 格 · 暗红 %d 格 ｜ 该敌人能看到玩家 = %s" % [danger.size(), watch.size(), str(sees)])
		print("[shot] 已保存 stealth.png")
		get_tree().quit(0)
