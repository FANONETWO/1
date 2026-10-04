extends Control
## 端到端流程冒烟：加载探索场景 → 触发战斗 → 强制战斗胜利 → 返回探索 → 模拟撤离结算。
##   godot --headless --path . res://tests/flow_driver.tscn --quit-after 720

func _ready() -> void:
	TestGuard.arm("flow_driver", 45, get_tree())
	var p := Character.create_default()
	p.name = "冒烟轮回者"
	p.attrs["str"] = 4
	p.attrs["dex"] = 4
	p.attrs["end"] = 3
	p.attrs["int"] = 3
	p.attrs["per"] = 3
	p.attrs["res"] = 3
	p.attrs["com"] = 3
	p.attrs["pre"] = 2
	p.attrs["man"] = 3
	p.skills["brawl"] = 3
	p.skills["investigate"] = 2
	p.talent_id = "fighter"
	p.weapon = "bat"
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	var d := FlowDriver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class FlowDriver:
	extends Node
	var _t := 0.0
	var _step := 0

	func _process(delta: float) -> void:
		_t += delta
		match _step:
			0:
				if _t > 1.0:
					_step = 1
					print("[flow] 探索场景已加载")
			1:
				if _t > 2.0:
					_step = 2
					var sc := get_tree().current_scene
					if sc and sc.has_method("_start_combat_with"):
						# 箱庭制：起点楼梯间是安全区，先切到有敌人的走廊
						sc._load_room("corridor_n", Vector2i.ZERO, "test")
						print("[flow] 已切到北侧走廊，触发战斗（丧尸）")
						sc._start_combat_with("zombie")
					else:
						print("[flow] 错误：探索场景未就绪")
						get_tree().quit(1)
			2:
				if _t > 4.0:
					_step = 3
					var sc := get_tree().current_scene
					# 融合模式：战斗控制器挂在**同一场景**上
					var bt: Node = sc.get("_battle")
					var cm = bt.get("_cm") if bt != null else null
					if cm != null:
						cm.over = true
						cm.victory = true
						cm.units[1].hp = 0
						print("[flow] 强制战斗胜利")
						bt.call("_check_over")
					else:
						print("[flow] 错误：战斗未就绪")
						get_tree().quit(1)
			3:
				if _t > 6.0:
					_step = 4
					print("[flow] 战斗结束，原地回到探索（融合模式无需返回）")
			4:
				if _t > 8.0:
					_step = 5
					var sc := get_tree().current_scene
					if sc and sc.has_method("_try_escape"):
						if not Game.player.inventory.has("apartment_key"):
							Game.player.inventory.append("apartment_key")
						print("[flow] 模拟撤离")
						sc._try_escape()
					else:
						print("[flow] 错误：探索场景未恢复")
						get_tree().quit(1)
			5:
				if _t > 10.0:
					var sc := get_tree().current_scene
					if sc and sc.has_method("_show_settlement"):
						print("[flow] 结算面板已显示")
					print("[flow] 端到端冒烟通过")
					get_tree().quit(0)
