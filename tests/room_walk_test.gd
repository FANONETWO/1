extends Control
## 验证「走到门 → 切房间」真的走得通（数据对了，还要跑一遍真流程）。
##   godot --path . res://tests/room_walk_test.tscn --quit-after 3600

func _ready() -> void:
	TestGuard.arm("room_walk_test", 60, get_tree())
	var c := Character.create_default()
	c.name = "走位测试"
	c.talent_id = "fighter"
	c.attrs = {"str": 3, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3}
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
			print("room_walk_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var cur := String(sc.get("_room_id"))
		print("[walk] 起点：%s（%s）" % [cur, R001Rooms.room_name(cur)])
		var ok := true
		var visited: Array[String] = [cur]

		# 连走 6 步，每步都走「编号最大的那个出口」，尽量遍历不同房间
		for step in 6:
			var exits: Array = R001Rooms.exit_cells(cur)
			if exits.is_empty():
				print("[walk] %s 没有出口 —— 卡死" % cur)
				ok = false
				break
			var e: Dictionary = exits[exits.size() - 1]
			var target := String(e["room"])
			var cell: Vector2i = e["cell"]

			# 把玩家放到门格，解锁，等一帧让 _process 检测到
			sc.set("_player_pos", cell)
			sc.set("_exit_lock", 0.0)
			sc._position_entity(sc.get("_player_sprite"), cell)
			await get_tree().create_timer(0.45).timeout

			var now := String(sc.get("_room_id"))
			var pass_step := now == target
			print("[walk] %-12s --%s--> %-12s 期望 %-12s %s" % [
				cur, String(e["dir"]), now, target, "OK" if pass_step else "FAIL"])
			if not pass_step:
				ok = false
				break
			cur = now
			if not cur in visited:
				visited.append(cur)

		print("[walk] 走过 %d 间：%s" % [visited.size(), ", ".join(visited)])
		print("room_walk_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
