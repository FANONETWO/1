extends Control
## 点击判定复现：分别点击「自己 / 自己上下一格 / 空地 / 地图外」，
## 打印命中的格子、是否弹出菜单、玩家是否移动。
##   godot --headless --path . res://tests/repro_click.tscn --quit-after 1600

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
		await get_tree().create_timer(1.4).timeout
		var sc := get_tree().current_scene
		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.8).timeout
		var cb := get_tree().current_scene
		if cb == null or cb.get("_cm") == null:
			print("[test] 战斗场景未就绪")
			get_tree().quit(1)
			return
		var cm = cb.get("_cm")
		var map = cb.get("_map")
		var start: Vector2i = cm.player_unit.pos
		var center: Vector2 = map.cell_center(start)
		print("[test] 玩家格 = %s，屏幕中心 = %s" % [str(start), str(center)])

		var cases: Array = [
			["自己所在格", center],
			["自己上方一格", center + Vector2(0, -48)],
			["自己下方一格", center + Vector2(0, 48)],
			["右侧 5 格外", center + Vector2(240, 0)],
			["地图外右下", Vector2(1240, 700)],
		]
		for item in cases:
			cb._close_command_menu()
			cb._exit_modes()
			await get_tree().create_timer(0.2).timeout
			# 复原玩家位置，保证每次测试起点一致
			cm.player_unit.pos = start
			cb._move_node(cm.player_unit, start)
			await get_tree().create_timer(0.2).timeout

			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = item[1]
			cb._unhandled_input(ev)
			await get_tree().create_timer(0.3).timeout

			var g: Vector2i = map.grid_at_point(item[1])
			var unit_there: CombatUnit = cb._unit_at(g)
			print("[test] 点「%s」屏幕%s → 格%s（%s）菜单=%s 玩家格=%s" % [
				String(item[0]), str(item[1]), str(g),
				unit_there.name if unit_there != null else "无单位",
				str(cb.get("_cmd_menu") != null), str(cm.player_unit.pos),
			])
		get_tree().quit(0)
