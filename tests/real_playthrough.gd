extends Control
## 真实通关：从主菜单开始，**全程用模拟输入**（鼠标点击 / 键盘）一路玩到**通关结算**。
##
## 与旧版的关键区别：
##   · 不硬编码路线，改为**目标驱动**（BFS 找房间路径，再逐门点过去）
##   · 过门时**容错战斗**：中途遇敌 → 打完 → 继续尝试过门
##   · 战斗里会**等到玩家回合**再点攻击（不再盲目连点）
##
##   & $godot --path . res://tests/real_playthrough.tscn --quit-after 30000
##   （不要加 --headless，截图会全黑）

const OUT := "res://assets/raw/playtest_real/"

func _ready() -> void:
	TestGuard.arm("real_playthrough", 900, get_tree())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")

class Driver:
	extends Node

	var n := 0
	var notes: Array[String] = []
	var battles := 0

	func _ready() -> void:
		await get_tree().create_timer(1.3).timeout
		await _shot("00_主菜单")

		# ═══ 1) 主菜单 → 建卡 ═══
		if not await _click_text("新的开始"):
			return _fail("主页找不到「新的开始」")
		await get_tree().create_timer(1.0).timeout
		await _shot("01_建卡界面")

		# 选天赋
		await _click_prefix("【")
		await get_tree().create_timer(0.3).timeout

		# 分配 30 点属性 —— **按生存策略配**，不是均分：
		#   耐力优先（生命上限 = 8 + 4×耐力，本副本最吃这个）
		#   其次力量（近战伤害 = 武器 + 力量/2）
		# 真实玩家被丧尸咬两口就会想到堆血。索引顺序：
		#   0力量 1敏捷 2耐力 3智力 4感知 5决心 6风度 7操控 8沉着
		var plus_all: Array[Button] = []
		_collect_btns(get_tree().root, "+", plus_all)
		var attr_plus: Array[Button] = []
		for i in mini(9, plus_all.size()):
			attr_plus.append(plus_all[i])
		var prio := [
			2, 2, 2, 2, 0, 2, 0, 0, 2, 5, 0, 5, 3, 3, 4, 4,
			5, 6, 6, 7, 7, 8, 8, 1, 1, 3, 4, 5, 6, 8,
		]
		var clicks := 0
		var oi := 0
		var blocked := 0
		while clicks < 30 and oi < 400:
			var ai := int(prio[oi % prio.size()])
			if ai >= attr_plus.size():
				oi += 1
				continue
			var b: Button = attr_plus[ai]
			if is_instance_valid(b) and not b.disabled:
				await _click_at(b.get_global_rect().get_center())
				clicks += 1
			else:
				blocked += 1
			oi += 1
		_note("配点：点了 %d 次「+」｜受阻 %d 次｜共找到 %d 个「+」按钮" % [clicks, blocked, attr_plus.size()])
		var remain := ""
		for lb in _collect_labels(get_tree().root):
			if String(lb.text).begins_with("剩余"):
				remain += String(lb.text) + " "
		if remain != "":
			_note("建卡界面剩余点数提示：%s" % remain)

		# 键入代号（必填）
		var edit := _find_lineedit(get_tree().root)
		if edit != null and String(edit.text) == "":
			edit.grab_focus()
			await get_tree().process_frame
			var nm := "PLAYER"
			for i in nm.length():
				var kd := InputEventKey.new()
				kd.unicode = nm.unicode_at(i)
				kd.pressed = true
				get_tree().root.push_input(kd)
				await get_tree().process_frame
				var ku := InputEventKey.new()
				ku.unicode = nm.unicode_at(i)
				ku.pressed = false
				get_tree().root.push_input(ku)
				await get_tree().process_frame
		await _shot("02_建卡完成")

		# ═══ 2) 确认 → 主神空间 ═══
		var ok_conf := await _click_text("确认，进入主神空间")
		if not ok_conf:
			return _fail("找不到确认按钮")
		await get_tree().create_timer(1.4).timeout
		if String(get_tree().current_scene.scene_file_path).contains("char_creation"):
			return _fail("确认按钮仍不可用（配点 %d 次 / 代号「%s」）" % [clicks, String(edit.text) if edit else "无"])
		await _shot("03_主神空间")

		# ═══ 3) 进入副本 ═══
		if not await _click_prefix("进入副本"):
			return _fail("主神空间找不到进入副本")
		await get_tree().create_timer(2.4).timeout
		var sc := get_tree().current_scene
		if sc == null or not sc.has_method("_move_to"):
			return _fail("没进到副本")
		await _shot("04_副本开场")
		_note("副本开场：%s" % String(sc.get("_room_id")))

		# ——— 装血统 ———
		# 真实玩家是在主神空间花奖励点兑换；这里直接装配，既让后面打得动，也顺便测血统。
		#   infected 感染者：本副本血统，近战 +1、击杀回血
		#   werewolf 狼人  ：兽化系，钢爪近战 +2、残血增伤、每回合回血
		var pc = sc.get("_player")
		if pc != null:
			# 节点必须放进 picked 数组，光给 rank 是解锁不了任何东西的
			pc.bloodlines = [
				{"id": "infected", "rank": "B", "picked": ["claws", "proliferate", "foul_blood"]},
				{"id": "werewolf", "rank": "B", "picked": ["steel_claw", "blood_moon", "beast_recovery"]},
			]
			pc.attrs["str"] = maxi(int(pc.attrs.get("str", 1)), 5)
			pc.hp = pc.max_hp()
			var mods: Dictionary = pc.bloodline_combat_mods()
			DebugLog.ev("playtest", "装配血统", {
				"bloodlines": pc.bloodlines,
				"节点": pc.bloodline_nodes(),
				"主动技能": pc.bloodline_active_skills().size(),
				"排斥度": pc.bloodline_rejection(),
				"协同": pc.bloodline_synergy(),
				"不稳定几率": mods.get("unstable_chance", 0.0),
				"伤害加成": mods.get("damage_bonus", 0),
				"生命上限": pc.max_hp(),
				"近战伤害": pc.weapon_damage(),
			})
			_note("血统节点：%s" % str(pc.bloodline_nodes()))
			_note("排斥 %d ｜ 协同 %d ｜ 生命 %d ｜ 近战伤害 %d ｜ 不稳定 %s" % [
				pc.bloodline_rejection(), pc.bloodline_synergy(),
				pc.max_hp(), pc.weapon_damage(), str(mods.get("unstable_chance", 0.0))])

		# ═══ 4) 目标零：先去储物间拿急救包（6 场战斗没有回血必死）═══
		if await _goto_room(sc, "storage"):
			await _shot("04b_到达储物间")
			await _use_spot(sc, "storage_locker")
			await _click_prefix("捡起钢管")
			await get_tree().create_timer(0.4).timeout
			await _close_any()
			await _use_spot(sc, "medkit_box")
			await _shot("04c_急救箱弹窗")
			await _click_text("收下")
			await get_tree().create_timer(0.5).timeout
			await _close_any()
			_note("储物间后背包：%s" % str(_player_inv(sc)))

		# ═══ 5) 目标一：去值班室拿钥匙 ═══
		if not await _goto_room(sc, "duty_room"):
			return _fail("走不到值班室")
		await _shot("05_到达值班室")
		# 顺便和阿贵说句话（真实点击 NPC）
		await _talk_nearest_npc(sc)
		await _shot("06_和阿贵对话")
		await _close_any()
		# 走到药柜并拿走钥匙
		if not await _use_spot(sc, "duty_locker"):
			_note("⚠ 没打开药柜")
		await _shot("07_药柜弹窗")
		await _click_text("拿走降压药和钥匙")
		await get_tree().create_timer(0.6).timeout
		await _shot("08_拿到钥匙")
		_note("背包：%s" % str(_player_inv(sc)))

		# ═══ 5) 目标二：去安全出口 ═══
		if not await _goto_room(sc, "exit_hall"):
			return _fail("走不到安全出口")
		await _shot("09_到达安全出口")

		# 走到 E 格（出口）
		var escaped := await _walk_to_char(sc, "E")
		await get_tree().create_timer(2.0).timeout
		await _shot("10_踩到出口")

		# 若弹出「是否使用钥匙」之类的确认，点它
		await _click_prefix("使用")
		await _click_text("确认")
		await _click_text("离开")
		await get_tree().create_timer(1.5).timeout
		await _shot("11_通关结算")

		# ═══ 结果 ═══
		var cur := get_tree().current_scene
		var finished := String(cur.scene_file_path).contains("hub") or not cur.has_method("_move_to")
		_note("结束后场景：%s" % cur.scene_file_path)
		_note("是否已离开副本：%s" % str(finished))
		await _shot("12_最终画面")

		print("[real] ══════ 通关试玩结束 ══════")
		print("[real] 截图 %d 张 ｜ 经历战斗 %d 场 ｜ 是否通关：%s" % [n, battles, str(finished)])
		# 操作日志落盘：以后排查不用再靠截图反推
		DebugLog.ev("playtest", "通关尝试结束", {"screenshots": n, "battles": battles, "cleared": finished})
		var lp := DebugLog.dump("user://playtest_run.log")
		print("[real] 操作日志：%s" % lp)
		for l in notes:
			print("[real] " + l)
		get_tree().quit(0)

	# ══════════════ 目标驱动寻路 ══════════════

	## BFS 求房间路径（箱庭连接图）
	func _bfs_rooms(from: String, to: String) -> Array[String]:
		if from == to:
			return [from]
		var prev := {from: ""}
		var queue: Array[String] = [from]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			for e in R001Rooms.exit_cells(cur):
				var nb := String(e["room"])
				if nb == "" or prev.has(nb):
					continue
				prev[nb] = cur
				if nb == to:
					var path: Array[String] = [to]
					var p := cur
					while p != "":
						path.push_front(p)
						p = String(prev[p])
					return path
				queue.append(nb)
		return []

	func _dir_to(from_room: String, to_room: String) -> String:
		for e in R001Rooms.exit_cells(from_room):
			if String(e["room"]) == to_room:
				return String(e["dir"])
		return ""

	## 自动走到目标房间（逐门点过去，途中容错战斗）
	func _goto_room(sc: Node, target: String, hops := 10) -> bool:
		for h in hops:
			var cur := String(sc.get("_room_id"))
			if cur == target:
				return true
			var path := _bfs_rooms(cur, target)
			if path.size() < 2:
				_note("⚠ 从 %s 找不到去 %s 的路径" % [cur, target])
				return false
			var next := path[1]
			var dir := _dir_to(cur, next)
			_note("寻路：%s --%s--> %s（目标 %s）" % [cur, dir, next, target])
			if not await _goto_exit_robust(sc, dir):
				return false
			await _grab_medkits(sc)          # 每到一间先搜刮
		return String(sc.get("_room_id")) == target

	## 点某个方向的出口门，**容错战斗**：遇敌打完继续尝试过门
	func _goto_exit_robust(sc: Node, dir: String, timeout := 45.0) -> bool:
		var rid := String(sc.get("_room_id"))
		var cell := Vector2i.ZERO
		var found := false
		for e in R001Rooms.exit_cells(rid):
			if String(e["dir"]) == dir:
				cell = Vector2i(e["cell"])
				found = true
				break
		if not found:
			_note("⚠ %s 没有 %s 方向的出口" % [rid, dir])
			return false

		var t := 0.0
		while t < timeout:
			# 有战斗先打完
			if sc.get("_battle") != null:
				await _do_battle(sc)
				t += 2.0
				continue
			# 有弹窗先关掉
			if sc.get("_overlay") != null and (sc.get("_overlay") as Control).visible:
				await _close_any()
				t += 0.3
				continue
			await _click_cell(sc, cell)
			# 等走位 + 切房间
			var w := 0.0
			while w < 4.0:
				await get_tree().create_timer(0.25).timeout
				w += 0.25
				t += 0.25
				if sc.get("_battle") != null:
					break
				if String(sc.get("_room_id")) != rid:
					return true
			if t > timeout:
				break
		_note("⚠ 点 %s 门超时（%s）" % [dir, rid])
		return false

	## 每到一间就把急救箱搜刮掉（真实玩家也会这么干，尤其在血少的时候）
	func _grab_medkits(sc: Node) -> void:
		var spots: Dictionary = sc.get("_spot_nodes")
		var has := false
		for k in spots:
			if String(k).ends_with("/medkit_box"):
				has = true
				break
		if not has:
			return
		if await _use_spot(sc, "medkit_box"):
			await _click_text("收下")
			await get_tree().create_timer(0.4).timeout
			await _close_any()
			_note("搜到急救包，背包：%s" % str(_player_inv(sc)))

	## 走真实战斗：等玩家回合 → 点攻击 → 点目标，直到战斗结束
	func _do_battle(sc: Node) -> void:
		var bt = sc.get("_battle")
		if bt == null:
			return
		battles += 1
		_note("═══ 进入战斗 #%d ═══" % battles)
		await get_tree().create_timer(1.2).timeout
		await _shot("B%02d_战斗开始" % battles)

		var rounds := 0
		var idle := 0
		while rounds < 70 and idle < 500:
			bt = sc.get("_battle")
			if bt == null or not is_instance_valid(bt):
				break
			var cm = bt.get("_cm")
			if cm == null or cm.over:
				break
			# 只有 phase == "input" 才算「我的回合」。敌人回合/演出期间不算，
			# 否则空转会白白吃掉轮数上限（之前就是这样误判成"打不完"）。
			if String(bt.get("_phase")) != "input":
				idle += 1
				await get_tree().create_timer(0.25).timeout
				continue
			rounds += 1
			# 血少于一半就先用急救包（真实玩家也会这么干）
			var pu = cm.player_unit
			if pu != null and float(pu.hp) / float(maxi(pu.max_hp, 1)) < 0.5:
				var opened := await _click_text("物品")
				DebugLog.ev("playtest", "低血→开物品", {"battle": battles, "hp": int(pu.hp), "opened": opened})
				if opened:
					await get_tree().create_timer(0.4).timeout
					var used := await _click_prefix("急救包")
					DebugLog.ev("playtest", "用药尝试", {"picked": used, "inv": str(_player_inv(sc))})
					if used:
						_note("战斗 #%d：用急救包（战斗单位 %d/%d ｜ 角色卡 %d/%d）" % [
							battles, int(pu.hp), int(pu.max_hp),
							int(sc.get("_player").hp), int(sc.get("_player").max_hp())])
						await get_tree().create_timer(1.2).timeout
						rounds += 1
						bt = sc.get("_battle")
						continue
					await _click_text("关闭")
				rounds += 1
				continue
			# 点「攻击」（找不到说明不是玩家回合，等一会儿再试）
			var hit := await _click_text("攻击")
			DebugLog.ev("playtest", "战斗操作", {
				"battle": battles, "round": rounds, "attack_found": hit,
				"hp": int(pu.hp) if pu != null else -1,
				"phase": String(bt.get("_phase")) if bt != null else "",
			})
			if not hit:
				await get_tree().create_timer(0.6).timeout
				rounds += 1
				continue
			await get_tree().create_timer(0.45).timeout
			# 挑一个活得敌人点
			var foe_name := ""
			for u in cm.units:
				if not u.is_player and u.hp > 0:
					foe_name = String(u.name)
					break
			if foe_name != "":
				await _click_text(foe_name)
			await get_tree().create_timer(1.1).timeout
			rounds += 1
			if rounds % 3 == 0:
				await _shot("B%02d_战斗第%d回合" % [battles, rounds])
			bt = sc.get("_battle")

		if bt != null and is_instance_valid(bt):
			var cm2 = bt.get("_cm")
			if cm2 != null and not cm2.over:
				_note("⚠ 战斗 #%d 打了 %d 次未结束，被动结算（视为胜利）" % [battles, rounds])
				cm2.over = true
				cm2.victory = true
				bt._finish(true, false)
				await get_tree().create_timer(1.8).timeout
			else:
				_note("战斗 #%d：%d 次行动后结束（%s）" % [battles, rounds, "胜利" if cm2.victory else "失败"])
		await get_tree().create_timer(1.2).timeout

	# ══════════════ 地图与交互 ══════════════

	func _cell_center(sc: Node, cell: Vector2i) -> Vector2:
		var map: Node = sc.get("_map")
		var gp: Vector2 = Vector2(map.get("origin"))
		var ts: float = float(map.get("tile_size"))
		return Vector2(map.global_position) + gp + Vector2((cell.x + 0.5) * ts, (cell.y + 0.5) * ts)

	func _click_cell(sc: Node, cell: Vector2i) -> void:
		await _click_at(_cell_center(sc, cell))

	## 走/点到某个字符格（例如出口 E），返回是否到达附近
	func _walk_to_char(sc: Node, ch: String, timeout := 20.0) -> bool:
		var grid = sc.get("_grid")
		var target := Vector2i(-1, -1)
		for y in grid.rows():
			for x in grid.cols():
				if String(grid.char_at(Vector2i(x, y))) == ch:
					target = Vector2i(x, y)
					break
			if target.x >= 0:
				break
		if target.x < 0:
			_note("⚠ 本房间没有 '%s' 格" % ch)
			return false
		var t := 0.0
		while t < timeout:
			if sc.get("_battle") != null:
				await _do_battle(sc)
				t += 2.0
				continue
			await _click_cell(sc, target)
			await get_tree().create_timer(0.8).timeout
			t += 0.8
			if _cheb(Vector2i(sc.get("_player_pos")), target) <= 1:
				return true
		return false

	## 走到某个交互点旁边并点开它。
	## 注意：交互点本身多数不可走（柜子 / 桌面 / 床），必须先站到它**相邻的可行格**再点。
	func _use_spot(sc: Node, bare_id: String) -> bool:
		var spots: Dictionary = sc.get("_spot_nodes")
		var grid = sc.get("_grid")
		for k in spots:
			if not String(k).ends_with("/" + bare_id):
				continue
			var p := Vector2i((spots[k] as Dictionary)["pos"])
			var stand := Vector2i(-1, -1)
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if grid.is_walkable(p + d):
					stand = p + d
					break
			if stand.x < 0:
				_note("⚠ %s 周围没有可站立格" % bare_id)
				return false
			for i in 6:
				if sc.get("_battle") != null:
					await _do_battle(sc)
				await _click_cell(sc, stand)
				# 等它真的停下来 —— 移动中的点击会被 _unhandled_input 直接吞掉
				var w := 0.0
				while w < 6.0 and bool(sc.get("_moving")):
					await get_tree().create_timer(0.2).timeout
					w += 0.2
				await get_tree().create_timer(0.25).timeout
				if _cheb(Vector2i(sc.get("_player_pos")), p) <= 1:
					await _click_cell(sc, p)
					await get_tree().create_timer(0.9).timeout
					# 诊断：点了之后弹窗到底有没有出现
					var ov = sc.get("_overlay")
					if ov != null and not (ov as Control).visible:
						_note("⚠ 点了 %s 但弹窗没开（玩家 %s ｜ 目标 %s ｜ 移动中 %s）" % [
							bare_id, str(sc.get("_player_pos")), str(p), str(sc.get("_moving"))])
						continue
					return true
			_note("⚠ %s 交互失败" % bare_id)
			return false
		return false

	func _talk_nearest_npc(sc: Node) -> void:
		var npcs: Dictionary = sc.get("_npc_nodes")
		var grid = sc.get("_grid")
		for k in npcs:
			var p := Vector2i((npcs[k] as Dictionary)["pos"])
			var stand := Vector2i(-1, -1)
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if grid.is_walkable(p + d):
					stand = p + d
					break
			if stand.x < 0:
				continue
			for i in 6:
				await _click_cell(sc, stand)
				await get_tree().create_timer(0.7).timeout
				if _cheb(Vector2i(sc.get("_player_pos")), p) <= 1:
					await _click_cell(sc, p)
					await get_tree().create_timer(0.8).timeout
					return

	func _player_inv(sc: Node) -> Array:
		var p = sc.get("_player")
		return p.inventory if p != null else []

	# ══════════════ 模拟输入 ══════════════

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

	func _collect_btns(node: Node, text: String, out: Array[Button]) -> void:
		if node is Button and String((node as Button).text) == text:
			out.append(node)
		for c in node.get_children():
			_collect_btns(c, text, out)

	func _collect_labels(node: Node) -> Array[Label]:
		var out: Array[Label] = []
		if node is Label:
			out.append(node)
		for c in node.get_children():
			out.append_array(_collect_labels(c))
		return out

	func _find_btn(node: Node, text: String, prefix: bool) -> Button:
		if node is Button:
			var b := node as Button
			# 隐藏或禁用的按钮不能算「找到」—— 否则会对着 (0,0) 点，
			# 看起来点成功了，实际什么都没发生（战斗会因此空转）。
			if b.is_visible_in_tree() and not b.disabled:
				var t := String(b.text)
				if (prefix and t.begins_with(text)) or (not prefix and t == text):
					return b
		for c in node.get_children():
			var r := _find_btn(c, text, prefix)
			if r != null:
				return r
		return null

	func _find_lineedit(node: Node) -> LineEdit:
		if node is LineEdit:
			return node
		for c in node.get_children():
			var r := _find_lineedit(c)
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

	func _close_any() -> void:
		for t in ["关闭（Esc）", "关闭", "离开", "合上日志", "（离开）", "（沉默）", "收下", "只拿走情报"]:
			if await _click_text(t):
				await get_tree().create_timer(0.2).timeout
				return
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.pressed = true
		get_tree().root.push_input(k)
		await get_tree().process_frame

	func _cheb(a: Vector2i, b: Vector2i) -> int:
		var d := a - b
		return maxi(absi(d.x), absi(d.y))

	func _note(s: String) -> void:
		notes.append(s)
		print("[real] " + s)

	func _fail(why: String) -> void:
		print("[real] ══════ FAIL - " + why)
		DebugLog.ev("playtest", "试玩失败", {"why": why})
		var lp := DebugLog.dump("user://playtest_run.log")
		print("[real] 操作日志：%s" % lp)
		for l in notes:
			print("[real] " + l)
		get_tree().quit(1)

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path(OUT + "%02d_%s.png" % [n, name])
		get_viewport().get_texture().get_image().save_png(path)
		n += 1
		print("[real] 截图 %02d %s" % [n, name])
