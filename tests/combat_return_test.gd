extends Control
## 战斗返回清理回归测试：战斗结束后，被击杀的敌人必须从探索地图上消失。
##   godot --headless --path . res://tests/combat_return_test.tscn --quit-after 600

func _ready() -> void:
	var p := Character.create_default()
	p.name = "回归测试"
	p.talent_id = "fighter"
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	# 模拟「刚打完一场战斗，击杀了 (5,5) 的丧尸」返回探索
	Game.scenario_state["last_combat"] = {
		"victory": true, "points": 15, "killed": ["enemy_5_5"],
	}
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.2).timeout
		var sc := get_tree().current_scene
		if sc == null:
			printerr("combat_return_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		# 箱庭制：先切到有敌人的北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		var nodes: Dictionary = sc.get("_enemy_nodes")
		var gone := not nodes.has("enemy_5_5")
		var total := nodes.size()
		var entities: Array = sc.get("_entities")
		var enemy_entities := 0
		for e in entities:
			if String(e.get("kind", "")) == "enemy":
				enemy_entities += 1
		print("  ok - 击败的 enemy_5_5 已移除=%s，剩余敌人节点=%d，剩余敌人实体=%d" % [str(gone), total, enemy_entities])
		var ok := gone and total == 2 and enemy_entities == 2
		print("combat_return_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
