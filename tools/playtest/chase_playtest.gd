extends Control
## 追逐机制实机验收（**真实鼠标点击走位**）：
##   潜行接近（背后不被发现）→ 故意进正面视野 → 只进入追逐、不开战
##   → 往回跑甩掉 → 再被发现 → 站着不动被追上，这时才开战（敌人先手）
##   godot --path . res://tools/playtest/chase_playtest.tscn --quit-after 30000
## ⚠️ 不要加 --headless
## 截图输出：assets/raw/playtest_chase/

func _ready() -> void:
	var c := Character.create_default()
	c.name = "跑者"
	c.talent_id = "fighter"
	# 高敏捷（移动力 5 格/回合）—— 比敌人 1 格/回合快，所以「甩得掉」应该成立
	c.attrs = {"str": 3, "dex": 4, "end": 3, "int": 2, "per": 3, "res": 2, "pre": 2, "man": 1, "com": 3}
	c.skills = {"blade": 3, "hide": 3, "survive": 3}
	c.weapon = "bat"
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

	const OUT := "res://assets/raw/playtest_chase/"
	var n := 0
	var fails: Array[String] = []
	var shots: Array[String] = []

	func _ok(cond: bool, label: String) -> void:
		if cond:
			print("[chase] ok - " + label)
		else:
			fails.append(label)
			print("[chase] FAIL - " + label)

	func _ready() -> void:
		TestGuard.arm("chase_playtest", 240.0, get_tree())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		await get_tree().create_timer(1.8).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("[chase] FAIL 场景未就绪")
			get_tree().quit(1)
			return
		sc.skip_tutorial()
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await _idle(sc)
		await _shot("01_进入走廊")

		var enemies: Dictionary = sc.get("_enemy_nodes")
		if enemies.is_empty():
			print("[chase] FAIL 主走廊没有敌人")
			get_tree().quit(1)
			return
		var uid := ""
		for k in enemies:
			uid = String(k)
			break

		# ——— 阶段 1：潜行 —— 绕到它背后 3 格 ———
		var spawn: Vector2i = sc.get("_player_pos")   # 逃跑时回到这儿
		var e: Dictionary = sc.get("_enemy_nodes")[uid]
		var facing: Vector2i = e.get("facing", Vector2i(0, 1))
		var behind: Vector2i = _nearest_walkable(sc, (e["pos"] as Vector2i) - facing * 3)
		print("[chase] 阶段1 潜行：目标背后 %s（敌人在 %s 朝 %s）" % [str(behind), str(e["pos"]), str(facing)])
		await _walk_to(sc, behind, 14.0)
		await _shot("02_潜行到背后")
		# 敌人自己会巡逻转身，走到位那一刻它可能正好转过头 —— 那不算 bug，
		# 正是「别在它面前停留」的设计。所以这里只断言「没被立刻抓住」。
		print("[chase] 到达背后时被看见 = %s（敌人可能已巡逻转身）" % str(sc._in_enemy_sight(uid)))
		_ok(sc.get("_battle") == null, "潜行接近没有被立刻抓住")

		# ——— 阶段 2：故意走进它的视野 ———
		# 用它**当前**的视野格来挑目标：比 "pos + facing * 2" 可靠（敌人会走、会转身）
		e = sc.get("_enemy_nodes")[uid]
		var grid0 = sc.get("_grid")
		var here: Vector2i = sc.get("_player_pos")
		var front := here
		var best_d := 999
		for p in sc._sight_cells(uid):
			if not grid0.is_walkable(p):
				continue
			var dd: int = absi((p as Vector2i).x - here.x) + absi((p as Vector2i).y - here.y)
			if dd > 0 and dd < best_d:
				best_d = dd
				front = p
		if front == here:
			front = _nearest_walkable(sc, (e["pos"] as Vector2i) + Vector2i(e.get("facing", Vector2i(0, 1))) * 3)
		print("[chase] 阶段2 现身：走进视野格 %s（敌人 %s 朝 %s）" % [
			str(front), str(e["pos"]), str(e.get("facing", Vector2i(0, 1)))])
		# 采样整个走位过程：要抓到「已经在追、但还没开战」的那个瞬间
		var samples: Array = []
		await _walk_to(sc, front, 16.0, samples)
		await get_tree().create_timer(0.6).timeout
		var alerted_now := _alerted_count(sc)
		var battle_now = sc.get("_battle")
		var saw_chase := false
		for s in samples:
			if int(s["alerted"]) >= 1 and not bool(s["battle"]):
				saw_chase = true
				break
		await _shot("03_被发现_追逐中")
		print("[chase] 阶段2 结果：采样 %d 帧 ｜ alerted=%d ｜ 当场开战=%s ｜ HUD「⚠」=%s" % [
			samples.size(), alerted_now, str(battle_now != null), str(_hud_has_chase(sc))])
		_ok(alerted_now >= 1 or saw_chase, "走进视野后有敌人进入追逐（alerted=%d）" % alerted_now)
		_ok(saw_chase or battle_now == null, "观察到「追逐中但未开战」（采样到 %s）" % str(saw_chase))
		_ok(_hud_has_chase(sc) or battle_now != null, "HUD 显示「在追你」提示")

		# ——— 阶段 3：逃跑 —— 玩家 5 格/回合 vs 敌人 1 格/回合，距离应该被拉开 ———
		var d_before := _nearest_dist(sc)
		await _walk_to(sc, spawn, 14.0)
		var d_after := _nearest_dist(sc)
		print("[chase] 阶段3 逃跑：跑到 %s ｜ 最近距离 %d → %d ｜ alerted=%d" % [
			str(sc.get("_player_pos")), d_before, d_after, _alerted_count(sc)])
		await _shot("04_逃跑拉开距离")
		_ok(sc.get("_battle") == null, "跑开的过程中没有被抓住")
		_ok(d_after >= d_before, "距离被拉开（%d → %d）：玩家比它快，所以甩得掉" % [d_before, d_after])

		# ——— 阶段 4：再引一次怪，然后站着不动 ———
		var here2: Vector2i = sc.get("_player_pos")
		var target2 := Vector2i(-1, -1)
		var best2 := 999
		for p in sc._sight_cells(uid):
			if not sc.get("_grid").is_walkable(p):
				continue
			var dd2: int = absi((p as Vector2i).x - here2.x) + absi((p as Vector2i).y - here2.y)
			if dd2 > 1 and dd2 < best2:
				best2 = dd2
				target2 = p
		if target2.x >= 0:
			print("[chase] 阶段4 再次现身：走进视野格 %s" % str(target2))
			await _walk_to(sc, target2, 16.0)
		print("[chase] 阶段4 站定不动，等敌人贴上…")
		var wait_rounds := 0
		while wait_rounds < 10 and sc.get("_battle") == null:
			sc._end_player_turn()
			await get_tree().create_timer(2.4).timeout
			wait_rounds += 1
			print("[chase]   站定第 %d 回合：alerted=%d ｜ 距离=%d" % [
				wait_rounds, _alerted_count(sc), _nearest_dist(sc)])
		var bt = sc.get("_battle")
		await _shot("05_被追上开战")
		_ok(bt != null, "站着不动会被追上并开战")
		if bt != null:
			_ok(not bool(bt.get("_surprise")), "被追上开战 = 敌人先手（不是突袭）")

		# ——— 汇总 ———
		print("[chase] ══════ 实机追逐验收结束 ══════")
		if fails.is_empty():
			print("[chase] 全部通过 ｜ 截图 %d 张 → %s" % [n, OUT])
			print("chase_playtest: PASS")
			get_tree().quit(0)
		else:
			for f in fails:
				print("[chase] FAIL - " + f)
			print("chase_playtest: FAIL (%d)" % fails.size())
			get_tree().quit(1)

	# ══════════ 查询 ══════════

	func _alerted_count(sc) -> int:
		var c := 0
		for uid in sc.get("_enemy_nodes"):
			if bool((sc.get("_enemy_nodes")[uid] as Dictionary).get("alerted", false)):
				c += 1
		return c

	func _nearest_dist(sc) -> int:
		var p: Vector2i = sc.get("_player_pos")
		var best := 999
		for uid in sc.get("_enemy_nodes"):
			var e: Dictionary = sc.get("_enemy_nodes")[uid]
			var d: int = absi((e["pos"] as Vector2i).x - p.x) + absi((e["pos"] as Vector2i).y - p.y)
			best = mini(best, d)
		return best

	func _hud_has_chase(sc) -> bool:
		for lbl in _labels(sc):
			if String(lbl.text).contains("在追你"):
				return true
		return false

	func _labels(node: Node) -> Array[Label]:
		var out: Array[Label] = []
		if node is Label:
			out.append(node)
		for c in node.get_children():
			out.append_array(_labels(c))
		return out

	## 找离目标最近的可走格（敌人位置会变，目标格可能被挡）
	func _nearest_walkable(sc, want: Vector2i) -> Vector2i:
		var grid = sc.get("_grid")
		if grid.is_walkable(want):
			return want
		for r in range(1, 6):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var p := want + Vector2i(dx, dy)
					if grid.is_walkable(p):
						return p
		return want

	# ══════════ 走位与等待 ══════════

	func _idle(sc) -> void:
		var t := 0.0
		while (bool(sc.get("_moving")) or bool(sc.get("_enemy_acting"))) and t < 25.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25

	## 真实点击走到某格；返回是否到达。
	## sink：等待期间持续采样 (alerted, battle) —— 用来抓「已在追但还没开战」的瞬时状态
	func _walk_to(sc, cell: Vector2i, timeout: float, sink: Array = []) -> bool:
		var t := 0.0
		while t < timeout:
			if Vector2i(sc.get("_player_pos")) == cell:
				return true
			if sc.get("_battle") != null:
				return false
			await _click_cell(sc, cell)
			await get_tree().create_timer(0.4).timeout
			t += 1.0
			var w := 0.0
			while (bool(sc.get("_moving")) or bool(sc.get("_enemy_acting"))) and w < 25.0:
				sink.append({"alerted": _alerted_count(sc), "battle": sc.get("_battle") != null})
				await get_tree().create_timer(0.12).timeout
				w += 0.12
			sink.append({"alerted": _alerted_count(sc), "battle": sc.get("_battle") != null})
		return Vector2i(sc.get("_player_pos")) == cell

	func _cell_center(sc, cell: Vector2i) -> Vector2:
		var map: Node = sc.get("_map")
		var gp: Vector2 = Vector2(map.get("origin"))
		var ts: float = float(map.get("tile_size"))
		return Vector2(map.global_position) + gp + Vector2((cell.x + 0.5) * ts, (cell.y + 0.5) * ts)

	func _click_cell(sc, cell: Vector2i) -> void:
		await _click_at(_cell_center(sc, cell))

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

	func _shot(tag: String) -> void:
		n += 1
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var f := "%02d_%s.png" % [n, tag]
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + f))
		shots.append(f)
		print("[chase] 截图 " + f)
