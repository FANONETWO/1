extends Control
## 验证点击输入处理链路：分发不拦截 + 移动逻辑。
## 说明：headless 下窗口为 64x64、canvas_items 缩放 20x，push_input 的坐标映射与真实窗口（1280x720, 1:1）不同，
## 因此分两部分验证：
##   1) 分发链：push_input 注入事件能到达 _unhandled_input（坐标被放大无妨）＝ 根节点/背景不再拦截；
##   2) 移动逻辑：直接调用 _unhandled_input 用正确 canvas 坐标，玩家应移动。
##   godot --headless --path . res://tests/click_test.tscn --quit-after 1200

func _ready() -> void:
	TestGuard.arm("click_test", 45, get_tree())
	var p := Character.create_default()
	p.name = "点击测试"
	p.attrs["str"] = 4
	p.attrs["dex"] = 4
	p.attrs["end"] = 3
	p.skills["brawl"] = 3
	p.weapon = "bat"
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	var d := ClickDriver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class ClickDriver:
	extends Node
	var _t := 0.0
	var _step := 0
	var _before := Vector2i.ZERO
	var _chain_ok := false

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			# 事件到达未处理阶段 = 根节点/背景不再拦截（mouse_filter 修复生效）
			_chain_ok = true

	func _process(delta: float) -> void:
		_t += delta
		match _step:
			0:
				if _t > 1.0:
					_step = 1
					var sc = get_tree().current_scene
					# 引导浮层是模态的，会拦住点击 → 先按「跳过引导」处理，模拟老玩家
					sc.skip_tutorial()
					_before = sc._player_pos
					# 1) 分发链：push_input 注入（坐标在 headless 下被放大，不影响"是否到达"的判断）
					var ev0 := InputEventMouseButton.new()
					ev0.position = Vector2(100, 100)
					ev0.button_index = MOUSE_BUTTON_LEFT
					ev0.pressed = true
					get_tree().root.push_input(ev0)
					print("[click] 分发链注入完成 可达=%s" % str(_chain_ok))
			1:
				if _t > 2.0:
					_step = 2
					if not _chain_ok:
						print("[click] 错误：事件未到达 _unhandled_input（输入仍被拦截）")
						get_tree().quit(1)
					var sc = get_tree().current_scene
					# 2) 移动逻辑：直接调用 _unhandled_input（正确 canvas 坐标）
					var target: Vector2i = _before + Vector2i(3, 0)
					var ev := InputEventMouseButton.new()
					ev.position = sc._map.grid_to_world(target) + Vector2(0, 6)
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = true
					sc._unhandled_input(ev)
					print("[click] 注入目标=%s 原位置=%s" % [str(target), str(_before)])
			2:
				if _t > 3.5:
					var sc = get_tree().current_scene
					var now: Vector2i = sc._player_pos
					print("[click] 玩家当前位置=%s" % str(now))
					if now != _before:
						print("[click] 点击链路通过（分发不拦截+移动逻辑）")
						get_tree().quit(0)
					else:
						print("[click] 错误：点击后玩家未移动")
						get_tree().quit(1)
