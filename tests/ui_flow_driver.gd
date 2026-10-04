extends Control
## UI 全链冒烟：主菜单 → 新开始 → 建卡(填名字/分配点/选天赋/确认) → 主神空间 → 进入副本。
##   godot --headless --path . res://tests/ui_flow_driver.tscn --quit-after 2400

func _ready() -> void:
	TestGuard.arm("ui_flow_driver", 45, get_tree())
	var d := UiFlow.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://ui/main_menu.tscn")

class UiFlow:
	extends Node
	var _t := 0.0
	var _step := 0

	func _process(delta: float) -> void:
		_t += delta
		match _step:
			0:
				if _t > 1.0:
					_step = 1
					var sc := get_tree().current_scene
					var found := false
					for b in _find_buttons(sc):
						if b.text == "新的开始":
							b.pressed.emit()
							found = true
							print("[ui] 点击「新的开始」")
							break
					if not found:
						print("[ui] 错误：主菜单缺少「新的开始」")
						get_tree().quit(1)
			1:
				if _t > 2.5:
					_step = 2
					var sc := get_tree().current_scene
					if sc == null or not sc.get("_name_edit"):
						print("[ui] 错误：未进入建卡场景")
						get_tree().quit(1)
						return
					sc._name_edit.text = "测试者"
					# 分配属性：力3 敏3 耐3 智3 感3 决3 沉3 风2 操2（1→3 各花5，共 40 超了）
					# 用推荐的均衡模板：每项都点到 3 需要 5*9=45 > 27，改轻量：
					# str/dex/end/int/per/res/com = 3，pre/man = 2 → 5*7 + 2*2 = 39 仍超
					# 直接驱动按钮逻辑：逐项 +1 直到 27 点用完
					var order: Array[String] = ["str", "dex", "end", "int", "per", "res", "com", "pre", "man"]
					var guard := 0
					while int(sc._attr_points_left) > 0 and guard < 200:
						guard += 1
						for a in order:
							if int(sc._attr_points_left) <= 0:
								break
							if int(sc._attrs[a]) < 6 and sc._attr_cost(int(sc._attrs[a]), int(sc._attrs[a]) + 1) <= int(sc._attr_points_left):
								sc._attr_change(a, 1)
					# 技能：肉搏3 调查2 交际1 求生1 躲藏1 = 8 点（留 12 点不强制用完）
					sc._skill_change("brawl", 3)
					sc._skill_change("investigate", 2)
					sc._skill_change("socialize", 1)
					sc._skill_change("survive", 1)
					sc._skill_change("hide", 1)
					sc._select_talent("fighter")
					print("[ui] 建卡：属性余 %d 技能余 %d" % [int(sc._attr_points_left), int(sc._skill_points_left)])
					sc._confirm_create()
			2:
				if _t > 4.0:
					_step = 3
					var sc := get_tree().current_scene
					if sc == null or not sc.has_method("_enter_scenario"):
						print("[ui] 错误：未进入主神空间（scene=%s）" % (sc.name if sc else "null"))
						get_tree().quit(1)
						return
					print("[ui] 主神空间就绪，奖励点=%d" % Game.points)
					sc._enter_scenario()
			3:
				if _t > 6.0:
					var sc := get_tree().current_scene
					if sc == null or not sc.has_method("_try_escape"):
						print("[ui] 错误：未进入副本场景")
						get_tree().quit(1)
						return
					print("[ui] 副本场景就绪：%s" % sc.name)
					print("[ui] UI 全链冒烟通过")
					get_tree().quit(0)

	func _find_buttons(node: Node, out: Array = []) -> Array:
		if node is Button:
			out.append(node)
		for c in node.get_children():
			_find_buttons(c, out)
		return out
