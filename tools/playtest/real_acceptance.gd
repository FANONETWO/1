extends Control
## 实机验收：**全程 push_input 真实鼠标输入**，从主菜单一路点到战斗。
##   主菜单 → 建卡（推荐配点 + 选四人小队）→ 主神空间 → 进副本 → 战斗里点「战术 / 抢手」与「攻击」
##   godot --path . res://tools/playtest/real_acceptance.tscn --quit-after 20000
## ⚠️ 不要加 --headless（没有窗口就没有真实点击，截图也会全黑）
## 截图输出：assets/raw/playtest_accept/

func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())

class Driver:
	extends Node

	const OUT := "res://assets/raw/playtest_accept/"
	var n := 0
	var fails: Array[String] = []

	func _ready() -> void:
		TestGuard.arm("real_acceptance", 180.0, get_tree())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		# 实机：从主菜单开始，不跳过任何界面
		# （Driver 挂在 root 上，所以切换当前场景不会把它一起销毁）
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		await get_tree().create_timer(1.5).timeout

		# ——— 0. 主菜单 ———
		await _shot("主菜单")
		if not await _click_text("新的开始"):
			return _fail("主菜单点不到「新的开始」")
		await get_tree().create_timer(1.3).timeout

		# ——— 1. 建卡：推荐配点 → 四人小队 → 确认 ———
		_diag("点完「新的开始」之后")
		if not await _click_text("推荐配点"):
			return _fail("建卡界面点不到「推荐配点」")
		await get_tree().create_timer(0.5).timeout
		await _shot("建卡_推荐配点")
		if not await _click_prefix("四人小队"):
			return _fail("建卡界面点不到「四人小队」模式按钮")
		await get_tree().create_timer(0.4).timeout
		# 注意：建卡界面里模式只是**选中态**，Game.set_mode 要等「确认」时才写 → 这里查按钮状态
		var mode_btn := _find_btn(get_tree().root, "四人小队", true)
		_ok(mode_btn != null and mode_btn.button_pressed, "「四人小队」按钮已选中")
		await _shot("建卡_已选四人小队")
		if not await _click_text("确认，进入主神空间"):
			return _fail("「确认，进入主神空间」不可点（校验没放过）")
		await get_tree().create_timer(1.6).timeout
		_ok(Game.mode == Game.MODE_TEAM, "确认后 Game.mode = team（实际 %s）" % Game.mode)
		_ok(Game.allies().size() == 3, "建卡后队伍有 3 名队友（实际 %d）" % Game.allies().size())

		# ——— 2. 主神空间 ———
		await get_tree().create_timer(0.5).timeout
		await _shot("主神空间")
		var hub_txt := _all_text(get_tree().current_scene)
		_ok(hub_txt.contains("四人小队"), "主神空间显示「四人小队」")
		_ok(hub_txt.contains("铁闸"), "主神空间列出队友「铁闸」")
		if not await _click_prefix("进入副本"):
			return _fail("主神空间点不到「进入副本」")
		await get_tree().create_timer(2.4).timeout

		# ——— 3. 副本：引导 → 跳过 ———
		await _shot("副本_新手引导")
		if not await _click_text("跳过引导"):
			return _fail("引导弹窗点不到「跳过引导」")
		await get_tree().create_timer(0.9).timeout
		await _shot("副本_已跳过引导")
		var sc = get_tree().current_scene
		var mates = sc.get("_party_sprites")
		if mates == null:
			return _fail("场景里没有 _party_sprites（队友跟随没生效？）")
		_ok(mates.size() == 3, "探索层有 3 名跟随队友（实际 %d）" % mates.size())

		# ——— 4. 进战斗（战斗内所有操作都是真实点击）———
		sc._load_room("corridor_n", Vector2i.ZERO, "accept")
		await get_tree().create_timer(0.8).timeout
		sc._start_combat_with("zombie")
		await get_tree().create_timer(2.8).timeout
		var bt = sc.get("_battle")
		if bt == null:
			return _fail("战斗没有创建")
		_ok(bt._cm.player_units().size() == 4,
			"战斗内玩家方 4 人（实际 %d）" % bt._cm.player_units().size())
		var tl = bt.get("_timeline_box")
		# 注意：tl 来自 Object.get() 是 Variant，从它身上取的值不能用 := 推断类型
		var cards: int = 0
		if tl != null:
			cards = int(tl.get_child_count())
		_ok(cards >= 4, "行动条渲染出卡片（%d 张）" % cards)
		await _shot("战斗_行动条")

		# ——— 5. 真实点击「战术」→「抢手」———
		await _wait_input(bt, 25.0)
		var cp0: int = bt._cm.command_points()
		# 指令菜单按钮偶发取到旧坐标（子菜单刚创建那一刻）→ 点完校验是否真的弹出，没弹就重试
		var sub = bt.get("_sub_box")
		var cmd = bt.get("_cmd_box")
		var opened := false
		var tries := 0
		for i in 3:
			tries = i + 1
			if not await _click_text("战术"):
				return _fail("指令菜单里点不到「战术」")
			await get_tree().create_timer(0.45).timeout
			sub = bt.get("_sub_box")
			cmd = bt.get("_cmd_box")
			if sub != null and bool(sub.visible):
				opened = true
				break
			await _wait_input(bt, 6.0)
		print("[accept] 点完「战术」（第 %d 次）：_phase=%s _cmd_box=%s _sub_box=%s 子按钮=%d" % [
			tries, str(bt.get("_phase")),
			str(cmd.visible) if cmd != null else "null",
			str(sub.visible) if sub != null else "null",
			int(sub.get_child_count()) if sub != null else -1])
		_ok(opened, "点「战术」后子菜单弹出来了")
		await _shot("战术菜单")
		if not opened:
			return _fail("战术子菜单始终没弹出来")
		if not await _click_prefix("抢手"):
			return _fail("战术子菜单里点不到「抢手」")
		await get_tree().create_timer(1.6).timeout
		_ok(bt._cm.command_points() == cp0 - 1,
			"「抢手」扣掉 1 点指挥点（%d → %d）" % [cp0, bt._cm.command_points()])
		var nxt: Array = bt._cm.timeline(1)
		if not nxt.is_empty():
			_ok(bool(nxt[0].is_player), "抢手之后下一个出手的是自己人（%s）" % String(nxt[0].name))
		await _shot("抢手之后")

		# ——— 6. 真实点击「攻击」打一轮 ———
		await _wait_input(bt, 25.0)
		if String(bt.get("_phase")) != "input":
			return _fail("等不到玩家回合，攻击没法测")
		var foes: Array = bt._alive_enemies()
		if foes.is_empty():
			return _fail("没有敌人可打")
		var hp_before: int = int(foes[0].hp)
		var foe_name := String(foes[0].name)
		if not await _click_text("攻击"):
			return _fail("指令菜单里点不到「攻击」")
		await get_tree().create_timer(0.5).timeout
		await _shot("选择目标")
		# 子菜单刚出现时按钮坐标偶尔取到旧值 → 点击后校验，没生效就重新开菜单再点
		var hp_after := hp_before
		for attempt in 3:
			if not await _click_prefix(foe_name):
				return _fail("目标列表里点不到 %s" % foe_name)
			await get_tree().create_timer(2.2).timeout
			hp_after = _hp_of(bt, foe_name)
			print("[accept] 第 %d 次攻击 %s：HP %d → %d" % [attempt + 1, foe_name, hp_before, hp_after])
			if hp_after < hp_before or bool(bt.get("_over")):
				break
			await _wait_input(bt, 12.0)
			if String(bt.get("_phase")) == "input":
				await _click_text("攻击")
				await get_tree().create_timer(0.4).timeout
		await _shot("攻击之后")
		_ok(hp_after < hp_before or bool(bt.get("_over")),
			"攻击生效：%s HP %d → %d" % [foe_name, hp_before, hp_after])

		# ——— 汇总 ———
		print("[accept] ══════ 实机验收结束 ══════")
		if fails.is_empty():
			print("[accept] 全部通过 ｜ 截图 %d 张 → %s" % [n, OUT])
			print("real_acceptance: PASS")
			get_tree().quit(0)
		else:
			for f in fails:
				print("[accept] FAIL - " + f)
			print("real_acceptance: FAIL (%d)" % fails.size())
			get_tree().quit(1)

	# ══════════ 断言与工具 ══════════

	func _ok(cond: bool, label: String) -> void:
		if cond:
			print("[accept] ok - " + label)
		else:
			fails.append(label)
			print("[accept] FAIL - " + label)

	## 诊断：当前场景 + 可见且可点的按钮（点击坐标没命中时一眼就能看出场景没切）
	func _diag(tag: String) -> void:
		var cur := get_tree().current_scene
		var sp := "null"
		if cur != null:
			sp = cur.scene_file_path
		var bs: Array[String] = []
		_collect_btns(get_tree().root, bs)
		print("[accept] 诊断(%s) 场景=%s 可点按钮=%s" % [tag, sp, str(bs)])

	func _collect_btns(n: Node, out: Array[String]) -> void:
		if n is Button:
			var b := n as Button
			if b.is_visible_in_tree() and not b.disabled:
				out.append(String(b.text))
		for c in n.get_children():
			_collect_btns(c, out)

	func _fail(why: String) -> void:
		print("[accept] FAIL - " + why)
		print("real_acceptance: FAIL (1)")
		get_tree().quit(1)

	## 等到轮到玩家（_phase == "input"）
	func _wait_input(bt, limit: float) -> void:
		var t := 0.0
		while String(bt.get("_phase")) != "input" and t < limit and not bool(bt.get("_over")):
			await get_tree().create_timer(0.3).timeout
			t += 0.3

	## 按名字取敌人当前血量（敌人被打死就返回 0）
	func _hp_of(bt, foe_name: String) -> int:
		for f in bt._alive_enemies():
			if String(f.name) == foe_name:
				return int(f.hp)
		return 0

	func _all_text(node: Node) -> String:
		var s := ""
		if node is Label:
			s += String((node as Label).text) + "\n"
		elif node is RichTextLabel:
			s += String((node as RichTextLabel).text) + "\n"
		elif node is Button:
			s += String((node as Button).text) + "\n"
		for c in node.get_children():
			s += _all_text(c)
		return s

	func _shot(name: String) -> void:
		n += 1
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path(OUT + "%02d_%s.png" % [n, name]))
		print("[accept] 截图 " + name)

	# ══════════ 真实鼠标输入（与 tools/playtest/real_playthrough.gd 同一套手法）══════════

	func _click_at(p: Vector2) -> void:
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		get_tree().root.push_input(m)
		await get_tree().process_frame
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = p
			e.global_position = p
			get_tree().root.push_input(e)
			await get_tree().process_frame

	func _find_btn(node: Node, text: String, prefix: bool) -> Button:
		if node is Button:
			var b := node as Button
			# 隐藏或禁用的按钮不算「找到」—— 否则会对着 (0,0) 点，看着成功其实什么都没发生
			if b.is_visible_in_tree() and not b.disabled:
				var t := String(b.text)
				if (prefix and t.begins_with(text)) or (not prefix and t == text):
					return b
		for c in node.get_children():
			var r := _find_btn(c, text, prefix)
			if r != null:
				return r
		return null

	func _click_text(text: String) -> bool:
		var b := _find_btn(get_tree().root, text, false)
		if b == null:
			b = _find_btn(get_tree().root, text, true)
		if b == null:
			return false
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await _click_at(b.get_global_rect().get_center())
		await get_tree().create_timer(0.3).timeout
		return true

	func _click_prefix(pfx: String) -> bool:
		var b := _find_btn(get_tree().root, pfx, true)
		if b == null:
			return false
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await _click_at(b.get_global_rect().get_center())
		await get_tree().create_timer(0.3).timeout
		return true
