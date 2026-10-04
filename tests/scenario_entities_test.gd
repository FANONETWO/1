extends Control
## 副本实体定位回归测试
##   godot --headless --path . res://tests/scenario_entities_test.tscn --quit-after 600
##
## 背景：曾经有个「看不见的 bug」——敌人/NPC/调查点的坐标从未被设置，全部堆在 (0,0)，
## 玩家在地图上只看到自己、看不到怪。逻辑测试完全覆盖不到这类问题，
## 所以这里专门校验：每个实体节点的实际坐标是否等于它所在格子的世界坐标。

func _ready() -> void:
	TestGuard.arm("scenario_entities_test", 45, get_tree())
	var p := Character.create_default()
	p.name = "定位测试"
	p.talent_id = "fighter"
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
		if sc == null:
			printerr("scenario_entities_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		# 箱庭制：起点楼梯间是安全区，先切到有敌人的北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		var entities: Array = sc.get("_entities")
		var fails := 0
		var kinds := {}
		for e in entities:
			var node: Node2D = e["node"]
			var pos: Vector2i = e["pos"]
			var expect: Vector2 = sc._map.grid_to_world(pos)
			var k := String(e["kind"])
			kinds[k] = int(kinds.get(k, 0)) + 1
			if node.position.distance_to(expect) > 1.0:
				fails += 1
				printerr("  FAIL - %s 位置错误：实际 %s，期望 %s（格子 %s）" % [k, node.position, expect, pos])
		print("  ok - 实体总数 %d：%s" % [entities.size(), str(kinds)])
		var enemies := int(kinds.get("enemy", 0))
		if enemies <= 0:
			fails += 1
			printerr("  FAIL - 敌人数量为 0")
		else:
			print("  ok - 敌人已就位（%d 个）" % enemies)
		print("scenario_entities_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		get_tree().quit(1 if fails > 0 else 0)
