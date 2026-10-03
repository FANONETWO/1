extends Control
## 击杀移除回归测试：单位阵亡后必须从地图上消失。
##   godot --headless --path . res://tests/kill_removal_test.tscn --quit-after 900
##
## 背景：此前死亡单位只把 hp 归零，地图节点从不移除，玩家会看到「怪被打死了却不消失」。

func _ready() -> void:
	var p := Character.create_default()
	p.name = "击杀测试"
	p.talent_id = "fighter"
	p.attrs["str"] = 6
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.2).timeout
		var sc := get_tree().current_scene
		# 箱庭制：起点楼梯间无敌人，先切到北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.4).timeout
		var cb: Node = sc.get("_battle")
		if cb == null or cb.get("_cm") == null:
			printerr("kill_removal_test: FAIL（战斗未就绪）")
			get_tree().quit(1)
			return
		var cm = cb.get("_cm")
		var enemy: CombatUnit = null
		for u in cm.units:
			if not u.is_player:
				enemy = u
				break
		if enemy == null:
			printerr("kill_removal_test: FAIL（没有敌人单位）")
			get_tree().quit(1)
			return

		var nodes_before: Dictionary = cb.get("_unit_nodes")
		var had_node := nodes_before.has(enemy.uid)

		# 确定性击杀：把敌人压到 1 血，再走管理器结算（任何命中都致死）
		enemy.hp = 1
		cm.resolve_attack(cm.player_unit, enemy)
		cb._check_over()
		await get_tree().process_frame
		await get_tree().process_frame

		var nodes_after: Dictionary = cb.get("_unit_nodes")
		var gone := not nodes_after.has(enemy.uid)
		print("  ok - 敌人战前有节点=%s，hp=%d" % [str(had_node), enemy.hp])
		print("  ok - 战后节点已移除=%s" % str(gone))
		print("kill_removal_test: %s" % ("PASS" if (had_node and gone) else "FAIL"))
		get_tree().quit(0 if (had_node and gone) else 1)
