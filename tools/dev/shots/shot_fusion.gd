extends Control
## 融合战斗验证 + 截图：接敌时**场景不切换**，地图/位置/UI 全部连续。
##   godot --path . res://tools/dev/shots/shot_fusion.tscn --quit-after 1200

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
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[shot] 场景未就绪")
			get_tree().quit(1)
			return
		var scene_before := String(sc.name)
		var enemies: Dictionary = sc.get("_enemy_nodes")
		var ppos: Vector2i = sc.get("_player_pos")

		# 找一个最近的敌人，把玩家挪到它旁边（模拟探索阶段走过去）
		var best_uid := ""
		var best_d := 9999
		var best_pos := Vector2i.ZERO
		for uid in enemies:
			var e: Dictionary = enemies[uid]
			var ep: Vector2i = e["pos"]
			var dd: int = absi(ep.x - ppos.x) + absi(ep.y - ppos.y)
			if dd < best_d:
				best_d = dd
				best_uid = String(uid)
				best_pos = ep
		sc.set("_player_pos", best_pos + Vector2i(1, 0))
		sc._position_entity(sc.get("_player_sprite"), best_pos + Vector2i(1, 0))
		await get_tree().create_timer(0.4).timeout

		print("[shot] 接敌前：场景=%s 玩家格=%s 敌人数=%d" % [scene_before, str(sc.get("_player_pos")), enemies.size()])

		# ——— 融合战斗：不切场景 ———
		sc._start_combat_with("zombie")
		# 等敌方回合的战斗特写播完，回到玩家回合再截图
		await get_tree().create_timer(3.2).timeout
		var scene_after := String(get_tree().current_scene.name)
		var battle = sc.get("_battle")
		print("[shot] 接敌后：场景=%s（应相同）｜战斗控制器=%s" % [scene_after, str(battle != null)])

		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/fusion_battle.png"))
		print("[shot] 已保存 fusion_battle.png")

		# 指令菜单（战斗 UI 叠加在探索地图上）
		if battle != null:
			battle._open_command_menu()
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path("res://assets/raw/_probe/fusion_menu.png"))
			print("[shot] 已保存 fusion_menu.png（指令菜单）")

		var ok := scene_before == scene_after and battle != null
		print("shot_fusion: %s" % ("PASS（场景未切换）" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
