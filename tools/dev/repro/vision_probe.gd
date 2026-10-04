extends Control
## 视野系统取证：敌人巡逻转向后，画面上显示的视野锥有没有跟着变。
##   godot --headless --path . res://tools/dev/repro/vision_probe.tscn --quit-after 5400
##
## 输出三个关键量：
##   1. 每个敌人的 pos / facing / 视野格数
##   2. renderer 里实际显示的格子数（_attack）
##   3. _sight_uid —— _refresh_sight() 的缓存键（只按 uid 记 → 转向不重绘）

func _ready() -> void:
	var c := Character.create_default()
	c.name = "取证"
	c.talent_id = "survivor"
	c.attrs = {"str": 3, "dex": 3, "end": 4, "int": 2, "per": 3, "res": 2, "pre": 2, "man": 1, "com": 2}
	c.skills = {"blade": 3, "hide": 3, "investigate": 3}
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	Game.set_mode(Game.MODE_SOLO)
	Game.set_team([])
	get_tree().root.add_child.call_deferred(Driver.new())
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		TestGuard.arm("vision_probe", 90.0, get_tree())
		await get_tree().create_timer(1.8).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[probe] FAIL 场景未就绪")
			get_tree().quit(1)
			return
		sc.skip_tutorial()
		# 主走廊：有带巡逻路线的敌人，能观察到转向
		sc._load_room("corridor_n", Vector2i.ZERO, "probe")
		await get_tree().create_timer(0.8).timeout
		_probe(sc, "初始")

		for i in 3:
			sc._end_player_turn()
			await get_tree().create_timer(2.2).timeout
			_probe(sc, "第 %d 回合敌人行动后" % (i + 1))

		print("[probe] ══════ 取证结束 ══════")
		get_tree().quit(0)

	func _probe(sc, tag: String) -> void:
		var enemies: Dictionary = sc.get("_enemy_nodes")
		var map = sc.get("_map")
		var danger: Array = map.get("_attack") if map != null else []
		var watch: Array = map.get("_watch") if map != null else []
		# 格子数可能巧合相同（朝向翻转后格数往往不变），所以再算一个集合指纹
		var h := 0
		var all: Array = danger.duplicate()
		all.append_array(watch)
		for p in all:
			h = (h * 31 + int(p.x) * 7 + int(p.y)) % 99991
		print("[probe] ── %s ｜ 亮红 %d 格 · 暗红 %d 格 指纹=%d ｜ 缓存sig=%s ｜ 已接敌=%s" % [
			tag, danger.size(), watch.size(), h, str(sc.get("_sight_sig")), str(sc.get("_battle") != null)])
		var seen_any := false
		for uid in enemies:
			var e: Dictionary = enemies[uid]
			var cells: Array = sc._sight_cells(String(uid))
			var facing: Vector2i = e.get("facing", Vector2i(0, 1))
			var sees: bool = sc._in_enemy_sight(String(uid))
			print("      %-14s pos=%-9s facing=%-9s 视野格=%2d  看见玩家=%s" % [
				String(uid), str(e["pos"]), str(facing), cells.size(), str(sees)])
			if not cells.is_empty():
				seen_any = true
		if not seen_any:
			print("      （本房间没有会显示视野格的敌人）")
