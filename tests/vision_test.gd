extends Control
## 敌人视野与预警回归测试 —— 守四个**真实存在过**的 bug：
##   A. 换房间后不刷新视野锥（进屋 0 格预警，等于没有潜行信息）
##   B. 缓存只比 uid → 敌人转身/移动后视野锥冻结在旧位置
##   C. 只画「离玩家最近」一个敌人 → 其它敌人的视野完全没有预警
##   D. 锥形判定是 180°（注释与教程都写「正前方 90°」）
##   godot --headless --path . res://tests/vision_test.tscn --quit-after 3600

var _fails := 0

func _ready() -> void:
	var c := Character.create_default()
	c.name = "视野测试"
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

	var fails: Array[String] = []

	func _ok(cond: bool, label: String) -> void:
		if cond:
			print("  ok - " + label)
		else:
			fails.append(label)
			printerr("  FAIL - " + label)

	## 显示格子的集合指纹（格数会巧合相同，指纹不会）
	func _fp(danger: Array, watch: Array) -> int:
		var h := 0
		var all: Array = danger.duplicate()
		all.append_array(watch)
		all.sort()
		for p in all:
			h = (h * 31 + int(p.x) * 7 + int(p.y)) % 99991
		return h

	func _ready() -> void:
		TestGuard.arm("vision_test", 90.0, get_tree())
		await get_tree().create_timer(1.8).timeout
		var sc := get_tree().current_scene
		if sc == null:
			printerr("  FAIL - 场景未就绪")
			get_tree().quit(1)
			return
		sc.skip_tutorial()

		# ——— D. 锥形：正前方 90°（±45°）———
		var right := Vector2i(1, 0)
		_ok(sc._in_cone(Vector2i(1, 0), right), "正前方在锥内")
		_ok(sc._in_cone(Vector2i(2, 0), right), "正前方远处在锥内")
		_ok(sc._in_cone(Vector2i(1, 1), right), "45° 斜前在锥内（边界）")
		_ok(not sc._in_cone(Vector2i(1, 2), right), "63° 斜前不在锥内（旧实现 180° 会误判为可见）")
		_ok(not sc._in_cone(Vector2i(0, 1), right), "正侧面不在锥内")
		_ok(not sc._in_cone(Vector2i(-1, 1), right), "斜后方不在锥内（背后突袭的前提）")
		_ok(not sc._in_cone(Vector2i(-1, 0), right), "正后方不在锥内")

		# ——— A + C. 进屋就有预警，且覆盖所有敌人的视野 ———
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.7).timeout
		var map = sc.get("_map")
		var danger: Array = map.get("_attack")
		var watch: Array = map.get("_watch")
		var shown_total: int = danger.size() + watch.size()
		_ok(shown_total > 0, "A：进屋后立刻画出视野预警（%d 格）" % shown_total)

		var union := {}
		var enemy_count := 0
		for uid in sc.get("_enemy_nodes"):
			enemy_count += 1
			for p in sc._sight_cells(String(uid)):
				union[p] = true
		var shown := {}
		for p in danger:
			shown[p] = true
		for p in watch:
			shown[p] = true
		print("  · 本房间敌人 %d 个 ｜ 视野并集 %d 格 ｜ 画面显示 %d 格" % [
			enemy_count, union.size(), shown.size()])
		_ok(enemy_count >= 2, "C：本房间至少两个敌人（实际 %d）" % enemy_count)
		_ok(shown.size() == union.size(),
			"C：预警覆盖**全部**敌人的视野（显示 %d / 实际 %d）" % [shown.size(), union.size()])

		# ——— B. 敌人行动后视野锥跟着重绘 ———
		var before := _fp(danger, watch)
		sc._end_player_turn()
		await get_tree().create_timer(2.4).timeout
		var danger2: Array = map.get("_attack")
		var watch2: Array = map.get("_watch")
		var after := _fp(danger2, watch2)
		print("  · 敌人行动一回合后：指纹 %d → %d" % [before, after])
		_ok(before != after, "B：敌人移动/转向后视野锥重绘（不再冻结）")
		if sc.get("_battle") == null:
			_ok(danger2.size() + watch2.size() > 0, "B：重绘后仍有视野格（%d）" % (danger2.size() + watch2.size()))
		else:
			print("  · （本回合已被发现，进入战斗，跳过二次断言）")

		var ok := fails.is_empty()
		print("vision_test: %s%s" % ["PASS" if ok else "FAIL (%d)" % fails.size(),
			"" if ok else " → " + "；".join(fails)])
		get_tree().quit(0 if ok else 1)
