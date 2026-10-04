extends Control
## 体验层验证（对应试玩报告 C3 / C5 / B2 的修复）：
##   1. 首次进副本自动弹出新手引导；标记完成后不再弹
##   2. NPC 交互半径放宽到 2 格：3 格外明确拒绝且不开对话，1 格内可正常交谈
##   3. 迷雾「已探索记忆」：看过的格子留下记忆，可单独清空（换箱庭时调用）
##   godot --headless --path . res://tests/ux_test.tscn --quit-after 900

func _ready() -> void:
	TestGuard.arm("ux_test", 45, get_tree())
	var c := Character.create_default()
	c.name = "体验测试"
	c.talent_id = "survivor"
	c.attrs = {"str": 3, "dex": 3, "end": 3, "int": 2, "per": 3, "res": 2, "pre": 2, "man": 2, "com": 2}
	c.skills = {"blade": 3, "hide": 2, "investigate": 2}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	get_tree().root.add_child.call_deferred(Driver.new())
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("ux_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var fails: Array[String] = []

		# ——— 1. 新手引导 ———
		var shown: bool = bool(sc.get("_overlay").visible)
		var title := String(sc.get("_modal_title").text)
		print("[ux] 进场自动弹引导 = %s，标题=%s" % [shown, title])
		if not shown or not title.contains("引导"):
			fails.append("首次进场没有弹出新手引导")
		sc._mark_tutorial_done()
		sc._close_modal()
		if not bool(sc._tutorial_done()):
			fails.append("引导完成标记没写进存档状态")
		var tut_page_count: int = int(sc.tutorial_pages())
		print("[ux] 引导页数 = %d（应 ≥3）" % tut_page_count)
		if tut_page_count < 3:
			fails.append("引导页数不足")

		# ——— 2. NPC 交互半径 ———
		var radius: int = int(sc.interact_range())
		print("[ux] 交互半径 = %d（应为 2）" % radius)
		if radius != 2:
			fails.append("交互半径不是 2")
		# 起始房间是楼梯间（没有 NPC），先切到有 NPC 的箱庭
		for rid in R001Rooms.ROOMS:
			var npc_list: Array = R001Rooms.ROOMS[rid].get("npcs", [])
			if not npc_list.is_empty():
				sc._load_room(String(rid), Vector2i.ZERO, "")
				break
		await get_tree().create_timer(0.4).timeout
		var npcs: Dictionary = sc.get("_npc_nodes")
		if npcs.is_empty():
			fails.append("场景里没有 NPC，无法验证交互距离")
		else:
			var uid := String(npcs.keys()[0])
			var npos: Vector2i = Vector2i((npcs[uid] as Dictionary)["pos"])
			# 放远到 3 格
			var far := npos + Vector2i(3, 0)
			sc.set("_player_pos", far)
			sc._close_modal()
			sc._talk_npc(uid)
			var opened_far: bool = bool(sc.get("_overlay").visible)
			print("[ux] 距离 3 格点 NPC：开对话=%s（应 false）" % opened_far)
			if opened_far:
				fails.append("3 格外仍然打开了对话")
			# 走近到 1 格
			var near := npos + Vector2i(1, 0)
			if not bool(sc.get("_grid").is_walkable(near)):
				near = npos + Vector2i(-1, 0)
			if not bool(sc.get("_grid").is_walkable(near)):
				near = npos + Vector2i(0, 1)
			sc.set("_player_pos", near)
			sc._close_modal()
			sc._talk_npc(uid)
			var opened_near: bool = bool(sc.get("_overlay").visible)
			print("[ux] 距离 1 格点 NPC（%s）：开对话=%s（应 true）" % [uid, opened_near])
			if not opened_near:
				fails.append("相邻仍然打不开对话")
			sc._close_modal()

		# ——— 3. 迷雾已探索记忆 ———
		var renderer: PixelGridRenderer = sc.get("_map") as PixelGridRenderer
		var seen0 := renderer.seen_count()
		renderer.reset_seen()
		var seen1 := renderer.seen_count()
		sc._refresh_fog()
		var seen2 := renderer.seen_count()
		print("[ux] 已探索记忆：进场 %d 格 → 清空后 %d → 重算后 %d" % [seen0, seen1, seen2])
		if seen0 <= 0:
			fails.append("进场后没有任何已探索记忆")
		if seen1 != 0:
			fails.append("reset_seen 没有清空记忆")
		if seen2 <= 0:
			fails.append("重算视野后记忆没有重建")

		var ok := fails.is_empty()
		print("ux_test: %s%s" % ["PASS" if ok else "FAIL", "" if ok else " → " + "；".join(fails)])
		get_tree().quit(0 if ok else 1)
