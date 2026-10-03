class_name BattleController
extends Node
## 战斗控制器（BG3 式融合：与探索**共用同一张地图**，接敌时不再切换场景）。
##
## 由探索场景在接敌时创建并挂载，战斗结束后自行移除。
##   · 复用 CombatManager（回合 / AP / AI / 结算）
##   · 复用 BattleAnim（火纹式战斗特写）
##   · 复用探索场景的 GridWorld 与 PixelGridRenderer —— 地图、地形、单位位置全部连续
##
## 因此：战斗中移动过的位置、被打碎的掩体、掉落的战利品，战斗结束后**仍然在**。

signal finished(victory: bool)

# —— 依赖注入 ——
var _host: Control          # 探索场景（挂载 UI、提供单位节点）
var _map: GridRenderer      # 共用地图渲染器
var _grid: GridWorld        # 共用逻辑层
var _player: Character
var _cm: CombatManager

# —— UI ——
var _ui: Control
var _hud: Label
var _hint: Label
var _log: RichTextLabel
var _btn_attack: Button
var _btn_defend: Button
var _btn_item: Button
var _btn_end: Button
var _btn_skill: Button
var _btn_suppress: Button
var _btn_fusion: Button
var _cmd_menu: PanelContainer = null

# —— 状态 ——
var _unit_nodes: Dictionary = {}      # uid -> 战场节点（复用探索侧节点）
var _unit_home: Dictionary = {}       # uid -> 探索侧原节点（结算时脱掉战斗标签）
var _hp_labels: Dictionary = {}       # uid -> 战斗用血条标签
var _enemy_uids: Array[String] = []
var _mode := "idle"                   # idle / attack / skill
var _pending_skill := ""
var _enemy_turn_running := false
var _blood_uses: Dictionary = {}
var _fusion_used := false
var _surprise := false                # 突袭（潜行先手）：敌方首回合不行动
var _over := false                    # 结算只触发一次

# —— 向探索场景汇报的结果 ——
var killed_uids: Array[String] = []   # 阵亡敌人 uid（探索侧据此移除）
var player_final_pos: Vector2i        # 战斗结束时玩家所在格（位置连续，不重置）
var reward_points := 0

# ——— 生命周期 ———

## enemies: [{"id": "zombie", "pos": Vector2i, "uid": "enemy_5_5"}]
func setup(host: Control, map: GridRenderer, grid: GridWorld, player: Character,
		player_pos: Vector2i, enemies: Array, surprise: bool = false) -> void:
	_host = host
	_map = map
	_grid = grid
	_player = player
	_surprise = surprise
	var list: Array[Dictionary] = []
	for e in enemies:
		list.append({"id": String(e["id"]), "pos": e["pos"]})
		_enemy_uids.append(String(e.get("uid", "")))
	_cm = CombatManager.new()
	_cm.start(_player, list, player_pos)

func begin() -> void:
	_bind_units()
	_build_ui()
	_init_blood_uses()
	_apply_first_strike()      # 先手裁定：突袭 = 玩家抢先；被察觉 = 敌人抢先
	_refresh_hud()
	if _surprise:
		# 突袭：玩家抢到先手
		_log_line("[color=#ffd75e]【突袭】敌人措手不及 —— 你先行动！[/color]")
		_set_hint("突袭成功：你的回合")
		_check_unstable()
	else:
		# 被察觉：敌人先手
		_log_line("[color=#ff8c66]【被察觉】敌人抢先出手！[/color]")
		_start_enemy_sequence()

## 先手裁定。
## 注意：CombatManager.start() 会按先攻值（init）排序决定行动顺序 ——
## 若不干预，「突袭」只是打了句日志，实际仍可能被丧尸抢走先手。
## 这里直接把应该先动的单位挪到先攻序列最前并重置当前行动者。
func _apply_first_strike() -> void:
	if _surprise:
		_move_to_front(_cm.player_unit)
		return
	for u in _cm.order:
		if not u.is_player:
			_move_to_front(u)
			return

func _move_to_front(u: CombatUnit) -> void:
	if u == null or _cm.order.is_empty():
		return
	var idx := _cm.order.find(u)
	if idx < 0:
		return
	_cm.order.remove_at(idx)
	_cm.order.push_front(u)
	_cm.turn_index = 0
	_cm._begin_turn(u)

## 把探索侧的节点接入战斗（不新建单位）
func _bind_units() -> void:
	var store: Dictionary = _host.get("_enemy_nodes")
	var ei := 0
	for u in _cm.units:
		var node: Node2D = null
		if u.is_player:
			node = _host.get("_player_sprite")
		else:
			var key := _enemy_uids[ei] if ei < _enemy_uids.size() else ""
			ei += 1
			if key != "" and store.has(key):
				node = store[key]["node"]
		if node == null:
			continue
		_unit_nodes[u.uid] = node
		_unit_home[u.uid] = node
		# 战斗标签（HP）
		var lb := Label.new()
		lb.add_theme_font_size_override("font_size", 12)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.size = Vector2(100, 16)
		lb.position = Vector2(-50, -70)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(lb)
		_hp_labels[u.uid] = lb

# ——— UI ———

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(_ui)

	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_left = 16
	_hud.offset_top = 52          # 下移，避开探索场景顶部的任务栏
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hud)

	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_left = 16
	_hint.offset_top = 76
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate = Color(1, 1, 1, 0.85)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hint)

	var log_bg := ColorRect.new()
	log_bg.color = Color(0, 0, 0, 0.62)
	log_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	log_bg.offset_left = 10
	log_bg.offset_right = -10
	log_bg.offset_top = -110
	log_bg.offset_bottom = -56
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(log_bg)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_log.offset_left = 18
	_log.offset_right = -18
	_log.offset_top = -106
	_log.offset_bottom = -60
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_log)

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = -48
	bar.offset_bottom = -10
	bar.add_theme_constant_override("separation", 8)
	_ui.add_child(bar)
	_btn_attack = _mk_btn(bar, "攻击", _on_attack_pressed)
	_btn_skill = _mk_btn(bar, "血统技能", _on_blood_skill_pressed)
	_btn_suppress = _mk_btn(bar, "意志压制", _on_suppress_pressed)
	_btn_fusion = _mk_btn(bar, "融合技", _on_fusion_pressed)
	_btn_defend = _mk_btn(bar, "防御", _on_defend_pressed)
	_btn_item = _mk_btn(bar, "物品", _on_item_pressed)
	_btn_end = _mk_btn(bar, "结束回合", _on_end_pressed)

func _mk_btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _log_line(text: String) -> void:
	if _log != null:
		_log.append_text(text + "\n\n")

func _set_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text

# ——— 输入（战斗期间由本控制器接管）———

func handle_click(screen: Vector2) -> bool:
	## 返回 true 表示本次点击已被战斗吞掉（探索不再处理）
	if _cm == null or _cm.over or _enemy_turn_running or not _cm.is_player_turn():
		return true
	if _cmd_menu != null:
		_close_command_menu()
		if _mode == "attack":
			_exit_modes()
		return true
	var g := _map.grid_at_point(screen)
	var target := _unit_at_point(screen)
	if target == null and _map.in_bounds(g):
		target = _unit_at(g)

	if _mode == "attack":
		if target != null and not target.is_player and _in_attack_range(target):
			_exit_modes()
			_do_attack(target)
		else:
			_exit_modes()
			_set_hint("已取消攻击。")
		return true

	if _mode == "skill":
		var nid := _pending_skill
		_exit_modes()
		if nid != "" and _map.in_bounds(g):
			_use_blood_skill_at(nid, g)
		return true

	if target != null and target.is_player:
		_open_command_menu()
		return true
	if target != null:
		_set_hint("先点击自己打开指令菜单，再选择「攻击」。")
		return true
	if _map.in_bounds(g) and _grid.is_walkable(g) and _unit_at(g) == null:
		_do_move(g)
	return true

# ——— 移动与攻击 ———

func _do_move(g: Vector2i) -> void:
	var u := _cm.current()
	var wall := func(p: Vector2i) -> bool:
		return not _grid.is_walkable(p) or (_unit_at(p) != null and not _unit_at(p).is_player)
	var path := Pathfind.find(u.pos, g, wall)
	if path.is_empty():
		_log_line("无法到达。")
		return
	var steps := mini(path.size(), u.move)
	var ok := true
	for i in steps:
		if not _cm.try_move(u, path[i]):
			ok = false
			break
	if ok:
		_sync_positions()
	_refresh_hud()

func _do_attack(target: CombatUnit) -> void:
	var u := _cm.current()
	var before := target.hp
	var res := _cm.try_attack(u, target)
	if not res.get("ok", false):
		_log_line(String(res.get("reason", "无法攻击。")))
		return
	if u.is_player:
		await _play_anim(u, target, res.get("result", {}), before)
	else:
		await _play_anim(u, target, res.get("result", {}), before)
	_exit_modes()
	_dump_logs()
	_refresh_hud()
	_check_over()

func _play_anim(att: CombatUnit, def_: CombatUnit, r: Dictionary, def_hp_before: int) -> void:
	var player_tex := "res://assets/sprites/w1/player_idle.png"
	var enemy_tex := "res://assets/sprites/w1/zombie_idle.png"
	var p_att := att.is_player
	var p_before := att.hp if p_att else def_hp_before
	var p_after := att.hp if p_att else def_.hp
	var p_max := att.max_hp if p_att else def_.max_hp
	var e_before := def_hp_before if p_att else att.hp
	var e_after := def_.hp if p_att else att.hp
	var e_max := def_.max_hp if p_att else att.max_hp
	var anim := BattleAnim.new()
	add_child(anim)
	await anim.play_fight({
		"left_tex": player_tex, "left_name": String(_player.name),
		"right_tex": enemy_tex, "right_name": String(def_.name) if p_att else String(att.name),
		"left_hp": p_before, "left_max": p_max, "left_hp_after": p_after,
		"right_hp": e_before, "right_max": e_max, "right_hp_after": e_after,
		"main_left": p_att,
		"hit": bool(r.get("hit", true)),
		"damage": int(r.get("damage", 0)),
		"crit": false,
		"counter": false,
	})
	anim.queue_free()

# ——— 指令菜单 ———

func _open_command_menu() -> void:
	_close_command_menu()
	var u := _cm.player_unit
	if u == null or u.hp <= 0:
		return
	var rj := _player.bloodline_rejection()
	var sy := _player.bloodline_synergy()
	_cmd_menu = PanelContainer.new()
	_cmd_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_cmd_menu.add_child(v)

	var st := Label.new()
	var st_text := "AP %d/6" % int(u.ap)
	if rj >= 10:
		st_text += "　排斥 %d%%" % rj
	if sy >= 10:
		st_text += "　协同 %d%%" % sy
	st.text = st_text
	st.add_theme_font_size_override("font_size", 12)
	st.modulate = Color(1, 0.9, 0.6) if rj >= 50 else Color(0.85, 0.92, 1.0)
	v.add_child(st)

	var pool: Dictionary = _player.attack_pool()
	var dp := int(pool["dp_attr"]) + int(pool["dp_skill"])
	var atk := _cmd_button(v, "攻击", "AP 3 ｜ 骰池 %d · 期望 %.1f 成功" % [dp, float(dp) * 0.3])
	atk.disabled = int(u.ap) < CombatManager.AP_ATTACK or _attackable_targets().is_empty()
	atk.pressed.connect(_on_attack_pressed)

	if not _player.bloodline_active_skills().is_empty():
		var ready := _blood_ready_count()
		var sb := _cmd_button(v, "血统技能", "%d 个可用 · 威力 ×%.2f" % [ready, _player.bloodline_combat_mods()["node_bonus"]])
		sb.disabled = ready <= 0
		sb.pressed.connect(_on_blood_skill_pressed)

	if rj >= 10:
		var sup := _cmd_button(v, "意志压制", "意志 −2 ｜ 本场排斥 −10%%")
		sup.disabled = not _player.can_suppress_bloodline()
		sup.pressed.connect(_on_suppress_pressed)

	var fusion: Dictionary = _player.fusion_skill()
	if not fusion.is_empty():
		var fb := _cmd_button(v, "融合技", "%s ｜ 每场一次" % String(fusion.get("name", "")))
		fb.disabled = _fusion_used
		fb.pressed.connect(_on_fusion_pressed)

	var df := _cmd_button(v, "防御", "AP 2 ｜ 防御 +2 至下回合")
	df.disabled = int(u.ap) < CombatManager.AP_DEFEND
	df.pressed.connect(_on_defend_pressed)

	var it := _cmd_button(v, "物品", "AP 2 ｜ 消耗品")
	it.disabled = int(u.ap) < CombatManager.AP_ITEM
	it.pressed.connect(_on_item_pressed)

	var wait := _cmd_button(v, "结束回合", "交出剩余 AP %d" % int(u.ap))
	wait.pressed.connect(_on_end_pressed)

	_ui.add_child(_cmd_menu)
	var at := _map.cell_center(u.pos)
	_cmd_menu.position = Vector2(
		clampf(at.x + 30.0, 8.0, 1280.0 - 230.0),
		clampf(at.y - 170.0, 8.0, 720.0 - 340.0),
	)
	_set_hint("AP 制：动作消耗 AP，可连续行动")

func _cmd_button(parent: VBoxContainer, title: String, sub: String) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [title, sub]
	b.custom_minimum_size = Vector2(210, 40)
	b.add_theme_font_size_override("font_size", 13)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(b)
	return b

func _close_command_menu() -> void:
	if _cmd_menu != null and is_instance_valid(_cmd_menu):
		_cmd_menu.queue_free()
	_cmd_menu = null

func _enter_attack_mode() -> void:
	_close_command_menu()
	_mode = "attack"
	var cells: Array[Vector2i] = []
	for t in _attackable_targets():
		cells.append(t.pos)
	_map.show_attack_range(cells)
	_set_hint("点击红色高亮的敌人发动攻击（点其他地方取消）")

func _exit_modes() -> void:
	_mode = "idle"
	_pending_skill = ""
	var empty: Array[Vector2i] = []
	_map.show_attack_range(empty)
	if _cm != null and _cm.is_player_turn():
		_refresh_player_hint()

func _refresh_player_hint() -> void:
	var u := _cm.player_unit
	if u == null:
		return
	if int(u.ap) <= 0:
		_set_hint("AP 已用尽 —— 点击「结束回合」把回合交给敌方")
	else:
		_set_hint("AP %d/6：点击自己打开指令菜单（移动 1 / 攻击 3 / 防御 2 / 物品 2）" % int(u.ap))

# ——— 血统技能 ———

func _init_blood_uses() -> void:
	_blood_uses.clear()
	for node in _player.bloodline_active_skills():
		var nid := String(node.get("id", ""))
		_blood_uses[nid] = int(Bloodlines.active_effect(nid).get("uses", 3))

func _blood_ready_count() -> int:
	var n := 0
	for k in _blood_uses:
		if int(_blood_uses[k]) > 0:
			n += 1
	return n

func _on_blood_skill_pressed() -> void:
	_close_command_menu()
	var opts: Array = []
	for node in _player.bloodline_active_skills():
		var nid := String(node.get("id", ""))
		var left := int(_blood_uses.get(nid, 0))
		if left <= 0:
			continue
		opts.append({
			"label": "%s（%s，剩余 %d）" % [String(node.get("name", nid)), Bloodlines.effect_text(nid), left],
			"on_press": _begin_skill_aim.bind(nid),
		})
	if opts.is_empty():
		_log_line("没有可用的血统技能。")
		return
	_show_choice("血统技能", opts)

func _begin_skill_aim(node_id: String) -> void:
	_close_command_menu()
	var e := Bloodlines.active_effect(node_id)
	var rng := int(e.get("range", 1))
	var nm := Bloodlines.node_name(node_id)
	if rng <= 0:
		_use_blood_skill_at(node_id, _cm.player_unit.pos)
		return
	var me := _cm.player_unit
	_pending_skill = node_id
	_mode = "skill"
	var cells: Array[Vector2i] = []
	if String(e.get("target", "single")) == "aoe":
		for y in _grid.rows():
			for x in _grid.cols():
				var p := Vector2i(x, y)
				if absi(p.x - me.pos.x) + absi(p.y - me.pos.y) <= rng:
					cells.append(p)
	else:
		for u in _cm.units:
			if not u.is_player and u.hp > 0 and absi(me.pos.x - u.pos.x) + absi(me.pos.y - u.pos.y) <= rng:
				cells.append(u.pos)
	_map.show_attack_range(cells)
	var scope := "群体" if String(e.get("target", "single")) == "aoe" else "单体"
	_set_hint("【%s】%s · 射程 %d —— 点击红色格子选定目标" % [nm, scope, rng])

# ——— 兼容旧接口（旧战斗场景的方法名；旧测试与截图脚本仍在用）———

## 自动选择最近的敌人作为目标
func _use_blood_skill(node_id: String) -> void:
	var t := _nearest_enemy()
	_use_blood_skill_at(node_id, t.pos if t != null else _cm.player_unit.pos)

func _on_end_turn_pressed() -> void:
	_on_end_pressed()

## 融合模式下没有“返回探索”这一步（战斗结束即在原地继续）
func _back() -> void:
	pass

## 把单位节点移动到指定格
func _move_node(u: CombatUnit, pos: Vector2i) -> void:
	if _unit_nodes.has(u.uid):
		var node: Node2D = _unit_nodes[u.uid]
		if is_instance_valid(node):
			node.position = _map.grid_to_world(pos)

func _use_blood_skill_at(node_id: String, target_pos: Vector2i) -> void:
	var e := Bloodlines.active_effect(node_id)
	var left := int(_blood_uses.get(node_id, int(e.get("uses", 3))))
	if left <= 0:
		return
	var bonus := float(_player.bloodline_combat_mods()["node_bonus"])
	var power := int(round(float(int(e.get("power", 4))) * bonus))
	var kind := String(e.get("kind", "damage"))
	var is_aoe := String(e.get("target", "single")) == "aoe"
	var radius := int(e.get("radius", 1))
	var nm := Bloodlines.node_name(node_id)
	var scope := "群体" if is_aoe else "单体"

	var victims: Array = []
	for u in _cm.units:
		if u.is_player or u.hp <= 0:
			continue
		var d := absi(u.pos.x - target_pos.x) + absi(u.pos.y - target_pos.y)
		if (is_aoe and d <= radius) or ((not is_aoe) and u.pos == target_pos):
			victims.append(u)

	match kind:
		"heal":
			var before := _player.hp
			_player.hp = mini(_player.max_hp(), _player.hp + power)
			_apply_player_hp()
			_log_line("[color=#8cff9e]【%s】回复 %d 点生命。[/color]" % [nm, _player.hp - before])
		"buff":
			var stat := String(e.get("stat", "defense"))
			if stat == "damage":
				_cm.player_unit.damage_bonus += power
			else:
				_cm.player_unit.defense += power
			_log_line("[color=#8cd8ff]【%s】获得强化（本场有效）。[/color]" % nm)
		"debuff":
			for u in victims:
				u.defense = maxi(0, u.defense - power)
				u.damage_bonus = maxi(0, u.damage_bonus - power)
			_log_line("[color=#ffb3b3]【%s】%s：%d 个敌人被削弱。[/color]" % [nm, scope, victims.size()])
		_:
			for u in victims:
				u.hp -= power
				_cm._check_death(u)
			if kind == "damage_heal" and not victims.is_empty():
				_player.hp = mini(_player.max_hp(), _player.hp + int(e.get("heal", 3)))
				_apply_player_hp()
			if victims.is_empty():
				_log_line("【%s】没有命中任何目标。" % nm)
			else:
				_log_line("[color=#ffd75e]【%s】%s：%d 个敌人各受 %d 点伤害。[/color]" % [nm, scope, victims.size(), power])

	_blood_uses[node_id] = left - 1
	_exit_modes()
	_sync_positions()
	_dump_logs()
	_refresh_hud()
	_check_over()

# ——— 敌方回合 ———

func _on_end_pressed() -> void:
	if _enemy_turn_running:
		return
	_player.tick_bloodline()
	_cm.end_turn()
	_close_command_menu()
	_dump_logs()
	_refresh_hud()
	_check_over()
	if not _cm.over and not _cm.is_player_turn():
		_start_enemy_sequence()

func _start_enemy_sequence() -> void:
	if _enemy_turn_running:
		return
	_enemy_turn_running = true
	_set_hint("敌方回合……")
	_run_enemy_step()

func _run_enemy_step() -> void:
	if _cm.over:
		_enemy_turn_running = false
		_refresh_hud()
		_check_over()
		return
	if _cm.is_player_turn():
		_enemy_turn_running = false
		_set_hint("你的回合：点击自己打开指令菜单")
		_refresh_hud()
		_check_over()
		_check_unstable()
		return
	var enemy := _cm.current()
	var wall := func(p: Vector2i) -> bool:
		return not _grid.is_walkable(p) or (_unit_at(p) != null and not _unit_at(p).is_player)
	var act: Dictionary = _cm.auto_turn(enemy, wall)
	_sync_positions()
	_dump_logs()
	_refresh_hud()
	if bool(act.get("attacked", false)):
		var r: Dictionary = act.get("result", {})
		await _play_anim(act["attacker"], act["target"], r, int(r.get("target_hp_before", 0)))
		_sync_positions()
		_dump_logs()
		_refresh_hud()
	_check_over()
	await get_tree().create_timer(0.5).timeout
	_run_enemy_step()

# ——— 其它动作 ———

func _on_attack_pressed() -> void:
	_close_command_menu()
	_enter_attack_mode()

func _on_defend_pressed() -> void:
	_close_command_menu()
	if _cm.try_defend(_cm.current()):
		_dump_logs()
		_refresh_hud()

func _on_item_pressed() -> void:
	_close_command_menu()
	var inv: Array = []
	for it in _player.inventory:
		if String(Items.get_def(it).get("kind", "")) == "consumable":
			inv.append(it)
	if inv.is_empty():
		_log_line("没有可用的消耗品。")
		return
	var opts: Array = []
	for it in inv:
		opts.append({"label": "%s（%s）" % [Items.name_of(it), _item_text(it)], "on_press": _use_item.bind(it)})
	_show_choice("使用物品", opts)

func _item_text(id: String) -> String:
	var d: Dictionary = Items.get_def(id)
	var parts: Array[String] = []
	if d.has("heal_hp"):
		parts.append("恢复 %d 生命" % int(d["heal_hp"]))
	if d.has("heal_will"):
		parts.append("恢复 %d 意志" % int(d["heal_will"]))
	if d.has("stabilize"):
		parts.append("排斥 −15（%d 回合）" % int(d["stabilize"]))
	return "、".join(parts)

func _use_item(id: String) -> void:
	var res := _cm.try_use_item(_cm.current(), id)
	if not res.get("ok", false):
		_log_line(String(res.get("reason", "无法使用。")))
		return
	var stab := int(Items.get_def(id).get("stabilize", 0))
	if stab > 0:
		var before := _player.bloodline_rejection()
		_player.use_stabilizer(stab)
		_log_line("[color=#7ec8ff]【血脉稳定剂】排斥度 %d%% → %d%%[/color]" % [before, _player.bloodline_rejection()])
	_dump_logs()
	_refresh_hud()
	_check_over()

func _on_suppress_pressed() -> void:
	_close_command_menu()
	if not _player.can_suppress_bloodline():
		_log_line("无法压制：每场一次，需要 2 点意志力且排斥 ≥10%。")
		return
	var before := _player.bloodline_rejection()
	_player.suppress_bloodline()
	_log_line("[color=#7ec8ff]【意志压制】排斥度 %d%% → %d%%[/color]" % [before, _player.bloodline_rejection()])
	_refresh_hud()

func _on_fusion_pressed() -> void:
	_close_command_menu()
	var fusion: Dictionary = _player.fusion_skill()
	if fusion.is_empty() or _fusion_used:
		return
	var target: CombatUnit = _nearest_enemy()
	if target == null:
		return
	_fusion_used = true
	var base := 6 + (2 if _player.gene_lock_level >= 1 else 0)
	var dmg := int(round(float(base) * float(_player.bloodline_combat_mods()["node_bonus"])))
	target.hp -= dmg
	_log_line("[color=#ffb3ff]【融合技·%s】%s 受到 %d 点伤害！[/color]" % [String(fusion.get("name", "")), target.name, dmg])
	_cm._check_death(target)
	_sync_positions()
	_refresh_hud()
	_check_over()

# ——— 辅助 ———

func _sync_positions() -> void:
	for u in _cm.units:
		if _unit_nodes.has(u.uid):
			var node: Node2D = _unit_nodes[u.uid]
			if is_instance_valid(node):
				node.position = _map.grid_to_world(u.pos)
	# 阵亡单位：从战场索引移除并隐藏（节点本体交还探索场景统一清理）
	for u in _cm.fallen:
		if _unit_nodes.has(u.uid):
			var dead: Node2D = _unit_nodes[u.uid]
			if is_instance_valid(dead):
				dead.visible = false
			_unit_nodes.erase(u.uid)
	for uid in _hp_labels:
		var lb: Label = _hp_labels[uid]
		if not is_instance_valid(lb):
			continue
		var u := _find_unit(uid)
		if u != null:
			lb.text = "%s %d/%d" % [u.name, maxi(u.hp, 0), u.max_hp]

func _find_unit(uid: String) -> CombatUnit:
	for u in _cm.units:
		if u.uid == uid:
			return u
	return null

func _unit_at(g: Vector2i) -> CombatUnit:
	for u in _cm.units:
		if u.pos == g and u.hp > 0:
			return u
	return null

func _unit_at_point(screen: Vector2) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := 1e9
	for u in _cm.units:
		if u.hp <= 0 or not _unit_nodes.has(u.uid):
			continue
		var node: Node2D = _unit_nodes[u.uid]
		if not is_instance_valid(node):
			continue
		var rect := Rect2(node.position + Vector2(-24, -48), Vector2(48, 72))
		if rect.has_point(screen):
			var d := screen.distance_to(rect.get_center())
			if d < best_d:
				best_d = d
				best = u
	return best

func _attackable_targets() -> Array:
	var out: Array = []
	var me := _cm.player_unit
	if me == null:
		return out
	var rng := me.ranged_range if me.ranged else me.melee_range
	for u in _cm.units:
		if not u.is_player and u.hp > 0:
			if absi(me.pos.x - u.pos.x) + absi(me.pos.y - u.pos.y) <= rng:
				out.append(u)
	return out

func _in_attack_range(t: CombatUnit) -> bool:
	return _attackable_targets().has(t)

func _nearest_enemy() -> CombatUnit:
	var best: CombatUnit = null
	var bd := 9999
	var me := _cm.player_unit
	for u in _cm.units:
		if not u.is_player and u.hp > 0:
			var d := absi(u.pos.x - me.pos.x) + absi(u.pos.y - me.pos.y)
			if d < bd:
				bd = d
				best = u
	return best

func _apply_player_hp() -> void:
	var pu: CombatUnit = _cm.player_unit
	if pu != null:
		pu.hp = _player.hp

func _show_choice(title: String, opts: Array) -> void:
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ov.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 18)
	v.add_child(t)
	for o in opts:
		var b := Button.new()
		b.text = String(o["label"])
		var cb: Callable = o["on_press"]
		if cb.is_valid():
			b.pressed.connect(func() -> void:
				ov.queue_free()
				cb.call()
			)
		else:
			b.pressed.connect(func() -> void: ov.queue_free())
		v.add_child(b)
	_ui.add_child(ov)

func _dump_logs() -> void:
	## CombatManager 的新日志追加到 UI；这里做一次全量同步（切片规模足够）
	var logs: Array = _cm.logs
	if logs.is_empty():
		return
	if _log.get_paragraph_count() >= logs.size():
		return
	_log.clear()
	for line in logs:
		_log.append_text(String(line) + "\n\n")

func _refresh_hud() -> void:
	var p := _player
	var u := _cm.current()
	var turn_name := "—"
	var ap := 0
	if not _cm.over and u != null:
		turn_name = u.name
		ap = u.ap
	var bl := ""
	var rj := p.bloodline_rejection()
	if rj >= 10:
		var mark := "血脉干扰"
		if rj >= 100:
			mark = "☠基因崩溃"
		elif rj >= 50:
			mark = "⚠失控风险"
		bl = "　|　排斥 %d%%（%s）" % [rj, mark]
	_hud.text = "第 %d 轮　行动者：%s　AP %d/6　|　%s：%d/%d　意志 %d/%d%s" % [
		_cm.round, turn_name, ap, p.name, p.hp, p.max_hp(), p.will, p.max_will(), bl,
	]
	var can := _cm.is_player_turn() and not _cm.over
	_btn_attack.disabled = not can
	_btn_defend.disabled = not can
	_btn_item.disabled = not can
	_btn_end.disabled = not can
	if u != null and int(u.ap) <= 0 and can:
		_btn_end.text = "结束回合（AP 已用尽）"
	else:
		_btn_end.text = "结束回合"
	if _btn_suppress != null:
		_btn_suppress.visible = rj >= 10
		_btn_suppress.disabled = not can or not p.can_suppress_bloodline()
	if _btn_skill != null:
		var ready := _blood_ready_count()
		_btn_skill.visible = not p.bloodline_active_skills().is_empty()
		_btn_skill.text = "血统技能（%d）" % ready
		_btn_skill.disabled = not can or ready <= 0
	if _btn_fusion != null:
		var fu: Dictionary = p.fusion_skill()
		_btn_fusion.visible = not fu.is_empty()
		_btn_fusion.text = "融合技：%s" % String(fu.get("name", "")) if not fu.is_empty() else "融合技"
		_btn_fusion.disabled = not can or _fusion_used

func _check_unstable() -> void:
	var u := _cm.current()
	if u == null or not u.is_player or _cm.over:
		return
	var chance := float(_player.bloodline_combat_mods().get("unstable_chance", 0.0))
	if chance <= 0.0 or randf() >= chance:
		return
	_log_line("[color=#ff6b6b]【血脉失控】两条血脉互相撕扯，你失去了本回合的控制！[/color]")
	u.hp = maxi(0, u.hp - 1)
	_player.hp = u.hp
	_sync_positions()
	_refresh_hud()
	if u.hp <= 0:
		_cm._check_death(u)
		_check_over()
		return
	_on_end_pressed()

func _check_over() -> void:
	_sync_positions()
	if not _cm.over or _over:
		return
	_over = true
	# 清掉战斗标签
	for uid in _hp_labels:
		var lb: Label = _hp_labels[uid]
		if is_instance_valid(lb):
			lb.queue_free()
	_hp_labels.clear()
	if _cm.victory:
		for u in _cm.fallen:
			killed_uids.append(u.uid)
		reward_points = _cm.reward_points()
		player_final_pos = _cm.player_unit.pos if _cm.player_unit != null else Vector2i.ZERO
		_log_line("[color=#ffd75e]战斗胜利。[/color]")
		await get_tree().create_timer(0.8).timeout
		finished.emit(true)
	else:
		player_final_pos = _cm.player_unit.pos if _cm.player_unit != null else Vector2i.ZERO
		finished.emit(false)
