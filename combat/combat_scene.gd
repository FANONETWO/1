extends Control
## 战斗场景：等距战场 + AP 回合制 + 敌人 AI + 结算返回。

const MapData := preload("res://scenarios/r001_apartment/map_data.gd")

var _cm: CombatManager
var _map: GridRenderer
var _grid: GridWorld
var _unit_nodes: Dictionary = {}   # uid -> {node, unit, label}
var _enemy_turn_running := false
var _log: RichTextLabel
var _hud: Label
var _btn_attack: Button
var _btn_defend: Button
var _btn_item: Button
var _btn_end: Button
var _btn_suppress: Button     # P3 意志力压制
var _btn_fusion: Button       # P4 融合技
var _btn_skill: Button        # 血统主动技能
var _fusion_used := false     # 融合技每场一次
var _blood_uses: Dictionary = {}   # 技能 id -> 本场剩余次数
var _mode := "idle"                # idle / attack / skill（指令与瞄准模式）
var _pending_skill := ""           # 瞄准中的血统技能 id
var _cmd_menu: PanelContainer = null   # 指令菜单（点击自己弹出）
var _action_label: Label

func _ready() -> void:
	theme = PixelTheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	var pending: Dictionary = Game.scenario_state.get("pending_combat", {})
	var enemies: Array[Dictionary] = []
	for e in pending.get("enemies", []):
		enemies.append(e)
	var ppos: Vector2i = pending.get("player_pos", Vector2i(4, 2))
	Game.scenario_state.erase("pending_combat")
	_cm = CombatManager.new()
	_cm.start(Game.player, enemies, ppos)
	_build_battlefield()
	_init_blood_uses()
	_refresh_hud()
	_log_line("战斗开始！")
	if _cm.is_player_turn():
		_set_action_hint("你的回合：点击地面移动，点击敌人攻击")
		_check_unstable()
	else:
		_start_enemy_sequence()

# ——— 构建 ———

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_hud = Label.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_top = 8
	_hud.offset_left = 16
	_hud.add_theme_font_size_override("font_size", 17)
	add_child(_hud)

	_action_label = Label.new()
	_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_action_label.offset_top = 36
	_action_label.offset_left = 16
	_action_label.modulate = Color(1, 1, 1, 0.7)
	_action_label.add_theme_font_size_override("font_size", 14)
	add_child(_action_label)

	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_panel.offset_left = 16
	log_panel.offset_top = -100
	log_panel.offset_right = -16
	log_panel.offset_bottom = -44
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)
	_log = RichTextLabel.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	log_panel.add_child(_log)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_bottom = -8
	bar.offset_top = -38
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	_btn_attack = Button.new()
	_btn_attack.text = "攻击"
	_btn_attack.disabled = true
	_btn_attack.pressed.connect(_on_attack_pressed)
	bar.add_child(_btn_attack)
	_btn_defend = Button.new()
	_btn_defend.text = "防御"
	_btn_defend.pressed.connect(_on_defend_pressed)
	bar.add_child(_btn_defend)
	_btn_item = Button.new()
	_btn_item.text = "使用物品"
	_btn_item.pressed.connect(_on_item_pressed)
	bar.add_child(_btn_item)
	_btn_skill = Button.new()
	_btn_skill.text = "血统技能"
	_btn_skill.pressed.connect(_on_blood_skill_pressed)
	bar.add_child(_btn_skill)
	_btn_suppress = Button.new()
	_btn_suppress.text = "意志压制"
	_btn_suppress.tooltip_text = "花 2 点意志力，本场排斥度 −10（每场一次）"
	_btn_suppress.pressed.connect(_on_suppress_pressed)
	bar.add_child(_btn_suppress)
	_btn_fusion = Button.new()
	_btn_fusion.text = "融合技"
	_btn_fusion.pressed.connect(_on_fusion_pressed)
	bar.add_child(_btn_fusion)
	_btn_end = Button.new()
	_btn_end.text = "结束回合"
	_btn_end.pressed.connect(_on_end_turn_pressed)
	bar.add_child(_btn_end)

func _build_battlefield() -> void:
	_grid = GridWorld.new()
	_grid.setup(MapData.TILES)
	_map = PixelGridRenderer.new()
	_map.bind(_grid)
	_map.origin = Vector2(24, 40)
	add_child(_map)
	# 地图插到背景之上、HUD 之下
	move_child(_map, 1)
	for u in _cm.units:
		var node := _make_unit_node(u)
		_map.add_child(node)
		_unit_nodes[u.uid] = {"node": node, "unit": u}
	_sort_units()

func _make_unit_node(u: CombatUnit) -> Node2D:
	var n := Node2D.new()
	var sprite_path := "res://assets/sprites/w1/player_idle.png" if u.is_player else "res://assets/sprites/w1/zombie_idle.png"
	if ResourceLoader.exists(sprite_path):
		var s := Sprite2D.new()
		s.texture = load(sprite_path)
		s.centered = false
		s.scale = Vector2(3.0, 3.0)     # 16×24 → 48×72
		s.position = Vector2(-24, -48)  # 底边落在格子底部
		n.add_child(s)
	else:
		var color := Color(0.35, 0.7, 0.9) if u.is_player else Color(0.6, 0.28, 0.22)
		var body := Polygon2D.new()
		body.polygon = PackedVector2Array([Vector2(0, -16), Vector2(26, 0), Vector2(0, 16), Vector2(-26, 0)])
		body.color = color
		n.add_child(body)
	var lb := Label.new()
	lb.text = "%s %d/%d" % [u.name, u.hp, u.max_hp]
	lb.position = Vector2(-50, -70)
	lb.size = Vector2(100, 16)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 12)
	n.add_child(lb)
	n.position = _map.grid_to_world(u.pos)
	return n

func _sort_units() -> void:
	var list: Array = []
	for uid in _unit_nodes:
		list.append(_unit_nodes[uid])
	list.sort_custom(func(a, b):
		var pa: Vector2i = a["unit"].pos
		var pb: Vector2i = b["unit"].pos
		return pa.x + pa.y < pb.x + pb.y
	)
	var idx := 1
	for e in list:
		_map.move_child(e["node"], idx)
		idx += 1

# ——— 输入 ———

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _cm.is_player_turn() or _enemy_turn_running or _cm.over:
			return
		# 指令菜单打开时，点击空白处先关掉菜单（火纹式：右键取消的手感）
		if _cmd_menu != null:
			_close_command_menu()
			if _mode == "attack":
				_exit_modes()
			return
		var g := _map.grid_at_point(event.position)
		# 优先按**单位的可见 sprite 范围**判定（像素单位比格子高，头部会伸进上一格），
		# 否则会出现「点角色头部却被当成点了上一格地板」的错判。
		var target := _unit_at_point(event.position)
		if target == null and _map.in_bounds(g):
			target = _unit_at(g)
		if target == null and not _map.in_bounds(g):
			return

		# ① 攻击选择模式：点红色高亮的敌人执行攻击，点别处取消
		if _mode == "attack":
			if target != null and not target.is_player and _in_attack_range(target):
				_exit_modes()
				_try_attack(target)
			else:
				_exit_modes()
				_set_action_hint("已取消攻击。")
			return

		# ①' 技能瞄准模式：点红色格子确定目标（单体=敌人格，群体=落点）
		if _mode == "skill":
			var nid := _pending_skill
			_exit_modes()
			if nid != "":
				_use_blood_skill_at(nid, g)
			return

		# ② 点击自己 → 弹出指令菜单（攻击 / 血统技能 / 物品 / 待机）
		if target != null and target.is_player:
			_open_command_menu()
			return

		# ③ 点击敌人 → 提示先选自己（不再直接攻击）
		if target != null and not target.is_player:
			_set_action_hint("先点击自己打开指令菜单，再选择「攻击」。")
			return

		# ④ 点击地面 → 移动
		if _map.is_walkable(g) and _unit_at(g) == null:
			_try_move(g)

# ——— 火纹式指令菜单 ———

## 指令菜单（点击自己弹出）。
##
## 与火纹的区别（本作特色）：
##   · 我们是 **AP 制**：每个动作标注 AP 消耗，动作后**不结束回合**，可以连续行动；
##   · 攻击项显示 **D10 骰池与期望成功数**（骰池系统，而非火纹的命中率）；
##   · 血脉状态（排斥/协同）常驻显示，并带出「血统技能 / 意志压制 / 融合技」三项专属指令。
func _open_command_menu() -> void:
	_close_command_menu()
	var u := _cm.player_unit
	if u == null or u.hp <= 0:
		return
	var pl := Game.player
	var rj := pl.bloodline_rejection()
	var sy := pl.bloodline_synergy()

	_cmd_menu = PanelContainer.new()
	_cmd_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_cmd_menu.add_child(v)

	# —— 状态行：AP + 血脉状态（本作核心张力，常驻可见）——
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

	# —— 攻击：显示 D10 骰池与期望成功（骰池系统特色）——
	var pool: Dictionary = pl.attack_pool()
	var dp := int(pool["dp_attr"]) + int(pool["dp_skill"])
	var expect := float(dp) * 0.3
	var foes := _attackable_targets()
	var atk := _cmd_button(v, "攻击", "AP %d ｜ 骰池 %d · 期望 %.1f 成功" % [CombatManager.AP_ATTACK, dp, expect])
	atk.disabled = int(u.ap) < CombatManager.AP_ATTACK or foes.is_empty()
	if foes.is_empty():
		atk.tooltip_text = "射程内没有敌人"
	atk.pressed.connect(_enter_attack_mode)

	# —— 血统技能（专属）——
	var skills := pl.bloodline_active_skills()
	if not skills.is_empty():
		var ready := _blood_ready_count()
		var sb := _cmd_button(v, "血统技能", "AP 0 ｜ %d 个可用 · 威力 ×%.2f" % [ready, pl.bloodline_combat_mods()["node_bonus"]])
		sb.disabled = ready <= 0
		sb.pressed.connect(func() -> void:
			_close_command_menu()
			_on_blood_skill_pressed()
		)

	# —— 意志压制（仅排斥 ≥10 时出现）——
	if rj >= 10:
		var sup := _cmd_button(v, "意志压制", "意志 −2 ｜ 本场排斥 −10%%")
		sup.disabled = not pl.can_suppress_bloodline()
		sup.pressed.connect(func() -> void:
			_close_command_menu()
			_on_suppress_pressed()
		)

	# —— 融合技（仅解锁时出现）——
	var fusion: Dictionary = pl.fusion_skill()
	if not fusion.is_empty():
		var fb := _cmd_button(v, "融合技", "%s ｜ 每场一次" % String(fusion.get("name", "")))
		fb.disabled = _fusion_used or int(u.ap) <= 0
		fb.pressed.connect(func() -> void:
			_close_command_menu()
			_on_fusion_pressed()
		)

	# —— 防御 ——
	var df := _cmd_button(v, "防御", "AP %d ｜ 防御 +2 至下回合" % CombatManager.AP_DEFEND)
	df.disabled = int(u.ap) < CombatManager.AP_DEFEND
	df.pressed.connect(func() -> void:
		_close_command_menu()
		_on_defend_pressed()
	)

	# —— 物品 ——
	var it := _cmd_button(v, "物品", "AP %d ｜ 急救包 / 镇定剂 / 稳定剂" % CombatManager.AP_ITEM)
	it.disabled = int(u.ap) < CombatManager.AP_ITEM
	it.pressed.connect(func() -> void:
		_close_command_menu()
		_on_item_pressed()
	)

	# —— 结束回合（主动交出剩余 AP，而不是火纹式"动作后自动待机"）——
	var wait := _cmd_button(v, "结束回合", "交出剩余 AP %d" % int(u.ap))
	wait.pressed.connect(func() -> void:
		_close_command_menu()
		_on_end_turn_pressed()
	)

	add_child(_cmd_menu)
	# 限制在屏幕内
	var at := _map.cell_center(u.pos)
	_cmd_menu.position = Vector2(
		clampf(at.x + 30.0, 8.0, 1280.0 - 230.0),
		clampf(at.y - 170.0, 8.0, 720.0 - 340.0),
	)
	_set_action_hint("AP 制：动作消耗 AP，可连续行动；AP 用尽或点「结束回合」交出回合")

## 指令按钮（主标题 + 副信息两行）
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

## 进入攻击选择模式：高亮射程内的敌人
func _enter_attack_mode() -> void:
	_close_command_menu()
	_mode = "attack"
	var cells: Array[Vector2i] = []
	for t in _attackable_targets():
		cells.append(t.pos)
	_map.show_attack_range(cells)
	_set_action_hint("点击红色高亮的敌人发动攻击（点其他地方取消）")

func _exit_modes() -> void:
	_mode = "idle"
	_pending_skill = ""
	var empty: Array[Vector2i] = []
	_map.show_attack_range(empty)
	# 只在玩家回合里刷新提示，避免敌方回合显示「你的回合」
	if _cm != null and _cm.is_player_turn():
		_refresh_player_hint()

## 玩家回合的提示：AP 用尽时明确告诉玩家该做什么（避免"卡住"的错觉）
func _refresh_player_hint() -> void:
	var u := _cm.player_unit
	if u == null:
		return
	if int(u.ap) <= 0:
		_set_action_hint("AP 已用尽 —— 点击「结束回合」把回合交给敌方")
	else:
		_set_action_hint("AP %d/6：点击自己打开指令菜单（移动 1 / 攻击 3 / 防御 2 / 物品 2）" % int(u.ap))

## 射程内的敌人
func _attackable_targets() -> Array:
	var out: Array = []
	var me := _cm.player_unit
	if me == null:
		return out
	var rng := me.ranged_range if me.ranged else me.melee_range
	for u in _cm.units:
		if not u.is_player and u.hp > 0:
			var d := absi(me.pos.x - u.pos.x) + absi(me.pos.y - u.pos.y)
			if d <= rng:
				out.append(u)
	return out

func _in_attack_range(t: CombatUnit) -> bool:
	return _attackable_targets().has(t)

## 按**屏幕像素**找单位：优先命中 sprite 的实际可见矩形。
## 像素单位高 72px（比 48px 的格子高），头部会伸进上一格 ——
## 只看格子会导致「点角色头部却被当成点了上一格的地板」。
func _unit_at_point(screen: Vector2) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := 1e9
	for uid in _unit_nodes:
		var u: CombatUnit = _unit_nodes[uid]["unit"]
		if u.hp <= 0:
			continue
		var node: Node2D = _unit_nodes[uid]["node"]
		if node == null:
			continue
		var rect := Rect2(node.position + Vector2(-24, -48), Vector2(48, 72))
		if rect.has_point(screen):
			var d := screen.distance_to(rect.get_center())
			if d < best_d:
				best_d = d
				best = u
	return best

func _unit_at(g: Vector2i) -> CombatUnit:
	for uid in _unit_nodes:
		var u: CombatUnit = _unit_nodes[uid]["unit"]
		if u.pos == g and u.hp > 0:
			return u
	return null

func _try_move(g: Vector2i) -> void:
	var u := _cm.current()
	if not u.is_player:
		return
	var wall := func(p: Vector2i) -> bool:
		return not _map.is_walkable(p) or (_unit_at(p) != null and _unit_at(p) != u)
	var path := Pathfind.find(u.pos, g, wall)
	if path.is_empty():
		_log_line("无法到达。")
		return
	# 限速：只走 move 步
	var steps := mini(path.size(), u.move)
	var ok := true
	for i in steps:
		if not _cm.try_move(u, path[i]):
			ok = false
			break
	if ok:
		_move_node(u, path[steps - 1])
	_refresh_hud()

func _try_attack(target: CombatUnit) -> void:
	var u := _cm.current()
	var defender_hp_before := target.hp
	var res := _cm.try_attack(u, target)
	if not res.get("ok", false):
		_log_line(String(res.get("reason", "无法攻击。")))
		return
	# 火纹式战斗特写：数值已由 CombatManager 结算，动画只负责演出
	await _play_battle_anim(u, target, res.get("result", {}), defender_hp_before)
	_move_node(u, u.pos)
	_exit_modes()
	_dump_logs()
	_refresh_hud()
	_check_over()

## 播放战斗特写。约定：玩家固定站左边、敌人固定站右边（火纹视角），
## main_left 表示「主攻击方是不是玩家」——因此玩家攻击与敌方攻击共用同一套演出。
func _play_battle_anim(att: CombatUnit, def_: CombatUnit, r: Dictionary, def_hp_before: int, allow_counter: bool = false) -> void:
	var player_tex := "res://assets/sprites/w1/player_idle.png"
	var enemy_tex := "res://assets/sprites/w1/zombie_idle.png"
	var player_is_attacker := att.is_player

	var p_before := att.hp if player_is_attacker else def_hp_before
	var p_after := att.hp if player_is_attacker else def_.hp
	var p_max := att.max_hp if player_is_attacker else def_.max_hp
	var e_before := def_hp_before if player_is_attacker else att.hp
	var e_after := def_.hp if player_is_attacker else att.hp
	var e_max := def_.max_hp if player_is_attacker else att.max_hp
	var p_name := String(Game.player.name) if Game.player != null else "轮回者"
	var e_name := String(def_.name) if player_is_attacker else String(att.name)

	var anim := BattleAnim.new()
	add_child(anim)
	await anim.play_fight({
		"left_tex": player_tex, "left_name": p_name,
		"right_tex": enemy_tex, "right_name": e_name,
		"left_hp": p_before, "left_max": p_max, "left_hp_after": p_after,
		"right_hp": e_before, "right_max": e_max, "right_hp_after": e_after,
		"main_left": player_is_attacker,
		"hit": bool(r.get("hit", true)),
		"damage": int(r.get("damage", 0)),
		"crit": false,
		"counter": allow_counter,
	})
	anim.queue_free()

func _move_node(u: CombatUnit, target: Vector2i) -> void:
	if _unit_nodes.has(u.uid):
		var node: Node2D = _unit_nodes[u.uid]["node"]
		node.position = _map.grid_to_world(target)
	_sort_units()
	_map.queue_redraw()

func _on_attack_pressed() -> void:
	# 底部按钮与指令菜单里的「攻击」等效：都进入攻击选择模式
	_enter_attack_mode()

func _on_defend_pressed() -> void:
	var u := _cm.current()
	if _cm.try_defend(u):
		_dump_logs()
		_refresh_hud()

func _on_item_pressed() -> void:
	var inv: Array[String] = []
	for it in Game.player.inventory:
		var d: Dictionary = Items.get_def(it)
		if d.get("kind", "") == "consumable":
			inv.append(it)
	if inv.is_empty():
		_log_line("没有可用的消耗品。")
		return
	_show_item_menu(inv)

func _show_item_menu(inv: Array) -> void:
	var opts: Array = []
	for it in inv:
		opts.append({"label": "%s（%s）" % [Items.name_of(it), _item_effect_text(it)], "on_press": _use_item.bind(it)})
	opts.append({"label": "取消", "on_press": Callable()})
	_show_menu("使用物品", opts)

func _item_effect_text(id: String) -> String:
	var d: Dictionary = Items.get_def(id)
	var parts: Array[String] = []
	if d.has("heal_hp"):
		parts.append("恢复 %d 生命" % int(d["heal_hp"]))
	if d.has("heal_will"):
		parts.append("恢复 %d 意志" % int(d["heal_will"]))
	return "、".join(parts)

func _show_menu(title: String, opts: Array) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.name = "ItemMenu"
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 18)
	v.add_child(t)
	for o in opts:
		var b := Button.new()
		b.text = String(o.get("label", "…"))
		var cb: Callable = o.get("on_press", Callable())
		b.pressed.connect(func() -> void:
			overlay.queue_free()
			if cb.is_valid():
				cb.call()
		)
		v.add_child(b)
	add_child(overlay)

func _use_item(id: String) -> void:
	var u := _cm.current()
	var res := _cm.try_use_item(u, id)
	if not res.get("ok", false):
		_log_line(String(res.get("reason", "无法使用。")))
		return
	# P3：血脉稳定剂 —— 3 回合内排斥度额外 −15
	var d: Dictionary = Items.get_def(id)
	var stab := int(d.get("stabilize", 0))
	if stab > 0:
		var before := Game.player.bloodline_rejection()
		Game.player.use_stabilizer(stab)
		_log_line("[color=#7ec8ff]【血脉稳定剂】排斥度 %d%% → %d%%（持续 %d 回合）[/color]" % [
			before, Game.player.bloodline_rejection(), stab,
		])
	_dump_logs()
	_refresh_hud()
	_check_over()

func _on_end_turn_pressed() -> void:
	if _enemy_turn_running:
		return
	# P3：回合推进（血脉稳定剂计时）
	Game.player.tick_bloodline()
	_cm.end_turn()
	_dump_logs()
	_refresh_hud()
	_check_over()
	if not _cm.over and not _cm.is_player_turn():
		_start_enemy_sequence()

# ——— 敌人回合 ———

func _start_enemy_sequence() -> void:
	if _enemy_turn_running:
		return
	_enemy_turn_running = true
	_set_action_hint("敌方回合……")
	_run_enemy_step()

func _run_enemy_step() -> void:
	if _cm.over:
		_enemy_turn_running = false
		_refresh_hud()
		_check_over()
		return
	if _cm.is_player_turn():
		_enemy_turn_running = false
		_set_action_hint("你的回合：点击地面移动，点击敌人攻击")
		_refresh_hud()
		_check_over()
		_check_unstable()
		return
	var enemy := _cm.current()
	var wall := func(p: Vector2i) -> bool:
		return not _map.is_walkable(p) or (_unit_at(p) != null and not _unit_at(p).is_player)
	var act: Dictionary = _cm.auto_turn(enemy, wall)
	# 更新位置显示
	if _unit_nodes.has(enemy.uid):
		var node: Node2D = _unit_nodes[enemy.uid]["node"]
		node.position = _map.grid_to_world(enemy.pos)
	_sort_units()
	_dump_logs()
	_refresh_hud()
	# 敌方攻击同样播放战斗特写（此前只有日志，玩家看不到演出）
	if bool(act.get("attacked", false)):
		var r: Dictionary = act.get("result", {})
		await _play_battle_anim(act["attacker"], act["target"], r, int(r.get("target_hp_before", 0)))
		_sort_units()
		_dump_logs()
		_refresh_hud()
	_check_over()
	# 0.6s 后下一步
	await get_tree().create_timer(0.55).timeout
	_run_enemy_step()

# ——— 结算 ———

## 血统排斥：玩家回合开始时的失控判定。
## 失控 → 本回合失去控制（跳过行动）+ 血脉反噬 1 点伤害。
## （队伍系统上线后，失控将改为「攻击最近的单位」，可能打到自己人。）
func _check_unstable() -> void:
	var u := _cm.current()
	if u == null or not u.is_player or u.char_ref == null or _cm.over:
		return
	var mods: Dictionary = u.char_ref.bloodline_combat_mods()
	var chance := float(mods.get("unstable_chance", 0.0))
	if chance <= 0.0 or randf() >= chance:
		return
	_log_line("[color=#ff6b6b]【血脉失控】两条血脉互相撕扯，你失去了本回合的控制！[/color]")
	_cm._log("【血脉失控】%s 失去本回合控制，血脉反噬 1 点伤害。" % u.name)
	u.hp = maxi(0, u.hp - 1)
	if u.char_ref != null:
		u.char_ref.hp = u.hp
	_dump_logs()
	_refresh_hud()
	if u.hp <= 0:
		_cm._check_death(u)
		_check_over()
		return
	_on_end_turn_pressed()

## 同步单位显示：已阵亡（hp<=0）的单位从地图上移除。
## 修复：此前死亡单位会一直留在战场上（"怪被打死了却不消失"）。
func _sync_unit_nodes() -> void:
	var dead: Array = []
	for uid in _unit_nodes:
		var u: CombatUnit = _unit_nodes[uid]["unit"]
		if u.hp <= 0:
			var node: Node2D = _unit_nodes[uid]["node"]
			if node != null and is_instance_valid(node):
				node.queue_free()
			dead.append(uid)
	for uid in dead:
		_unit_nodes.erase(uid)

func _check_over() -> void:
	_sync_unit_nodes()
	if not _cm.over:
		return
	# P4：基因崩溃 —— 排斥 100% 的角色在战斗结束时死亡（优先级高于胜负判定）
	if Game.player.is_gene_collapsed():
		_gene_collapse()
		return
	if _cm.victory:
		var pts := _cm.reward_points()
		# 阵亡单位已从 units 移出，必须从 fallen 名册收集，否则探索地图上的尸体不会被清理
		var killed: Array[String] = []
		for u in _cm.fallen:
			killed.append(u.uid)
		for u in _cm.units:
			if not u.is_player and u.hp <= 0:
				killed.append(u.uid)
		Game.scenario_state["last_combat"] = {"victory": true, "points": pts, "killed": killed}
		Game.scenario_state.erase("pending_combat")
		_show_end("战斗胜利", "敌人全部倒下。\n击杀奖励 +%d 奖励点。" % pts, "返回探索")
	else:
		Game.scenario_state["last_combat"] = {"victory": false, "points": 0, "killed": []}
		_show_end("战斗失败", "你倒在了血泊里。\n（生命归零时将触发基因锁绝境爆种——若已觉醒，则真正死亡）", "返回")

func _show_end(title: String, body: String, btn_text: String) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(480, 0)
	overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	var btn := Button.new()
	btn.text = btn_text
	btn.pressed.connect(_back)
	v.add_child(btn)
	add_child(overlay)

## 血统主动技能：初始化本场剩余次数
func _init_blood_uses() -> void:
	_blood_uses.clear()
	for node in Game.player.bloodline_active_skills():
		var nid := String(node.get("id", ""))
		_blood_uses[nid] = int(Bloodlines.active_effect(nid).get("uses", 3))

## 本场仍可使用的血统技能数
func _blood_ready_count() -> int:
	var n := 0
	for k in _blood_uses:
		if int(_blood_uses[k]) > 0:
			n += 1
	return n

## 血统技能菜单
func _on_blood_skill_pressed() -> void:
	var pl := Game.player
	var opts: Array = []
	for node in pl.bloodline_active_skills():
		var nid := String(node.get("id", ""))
		var left := int(_blood_uses.get(nid, 0))
		if left <= 0:
			continue
		opts.append({
			"label": "%s（%s，剩余 %d）" % [String(node.get("name", nid)), Bloodlines.effect_text(nid), left],
			"on_press": _begin_skill_aim.bind(nid),
		})
	if opts.is_empty():
		_log_line("没有可用的血统技能（次数已耗尽，或尚未选主动技能）。")
		return
	opts.append({"label": "取消", "on_press": Callable()})
	_show_menu("血统技能", opts)

## 释放血统技能（兼容入口：自动选择最近的敌人作为目标）
func _use_blood_skill(node_id: String) -> void:
	var t := _nearest_enemy()
	var at := t.pos if t != null else _cm.player_unit.pos
	_use_blood_skill_at(node_id, at)

## 在指定格子释放血统技能。
## 单体技能：只影响该格上的敌人；群体技能：影响该格 radius 内的所有敌人。
func _use_blood_skill_at(node_id: String, target_pos: Vector2i) -> void:
	var pl := Game.player
	var e := Bloodlines.active_effect(node_id)
	var left := int(_blood_uses.get(node_id, int(e.get("uses", 3))))
	if left <= 0:
		_log_line("【%s】本场已无剩余次数。" % Bloodlines.node_name(node_id))
		return
	var bonus := float(pl.bloodline_combat_mods()["node_bonus"])
	var power := int(round(float(int(e.get("power", 4))) * bonus))
	var kind := String(e.get("kind", "damage"))
	var is_aoe := String(e.get("target", "single")) == "aoe"
	var radius := int(e.get("radius", 1))
	var nm := Bloodlines.node_name(node_id)
	var scope := "群体" if is_aoe else "单体"

	# —— 收集受影响的目标 ——
	var victims: Array = []
	for u in _cm.units:
		if u.is_player or u.hp <= 0:
			continue
		var d := _manhattan(u.pos, target_pos)
		if (is_aoe and d <= radius) or ((not is_aoe) and u.pos == target_pos):
			victims.append(u)

	match kind:
		"heal":
			var before := pl.hp
			pl.hp = mini(pl.max_hp(), pl.hp + power)
			_apply_player_hp()
			_log_line("[color=#8cff9e]【%s】回复 %d 点生命（%d → %d）。[/color]" % [nm, pl.hp - before, before, pl.hp])
		"buff":
			var stat := String(e.get("stat", "defense"))
			if stat == "damage":
				_cm.player_unit.damage_bonus += power
				_log_line("[color=#8cd8ff]【%s】伤害 +%d（本场有效）。[/color]" % [nm, power])
			else:
				_cm.player_unit.defense += power
				_log_line("[color=#8cd8ff]【%s】防御 +%d（本场有效）。[/color]" % [nm, power])
		"debuff":
			for u in victims:
				u.defense = maxi(0, u.defense - power)
				u.damage_bonus = maxi(0, u.damage_bonus - power)
			_log_line("[color=#ffb3b3]【%s】%s：%d 个敌人防御与伤害各 −%d。[/color]" % [nm, scope, victims.size(), power])
		_:
			# damage / damage_heal
			for u in victims:
				u.hp -= power
				_cm._check_death(u)
			if victims.is_empty():
				_log_line("【%s】没有命中任何目标。" % nm)
			elif kind == "damage_heal":
				var heal := int(e.get("heal", 3))
				pl.hp = mini(pl.max_hp(), pl.hp + heal)
				_apply_player_hp()
				_log_line("[color=#ffd75e]【%s】%s：%d 个敌人各受 %d 伤害，你回复 %d 生命。[/color]" % [
					nm, scope, victims.size(), power, heal,
				])
			else:
				_log_line("[color=#ffd75e]【%s】%s：%d 个敌人各受 %d 点伤害。[/color]" % [nm, scope, victims.size(), power])

	_blood_uses[node_id] = left - 1
	_exit_modes()
	_sync_unit_nodes()
	_dump_logs()
	_refresh_hud()
	_check_over()

## 进入技能瞄准模式：用**红色格子**显示该技能的打击范围
##   · 单体技能 → 高亮射程内的敌人格
##   · 群体技能 → 高亮射程内所有格（任选一格作为落点，命中该格半径内的敌人）
##   · 射程 0（自身技能）→ 直接施放，不需要瞄准
func _begin_skill_aim(node_id: String) -> void:
	_close_command_menu()
	var e := Bloodlines.active_effect(node_id)
	var rng := int(e.get("range", 1))
	var nm := Bloodlines.node_name(node_id)
	if rng <= 0:
		_use_blood_skill_at(node_id, _cm.player_unit.pos)
		return
	var me := _cm.player_unit
	if me == null:
		return
	_pending_skill = node_id
	_mode = "skill"
	var cells: Array[Vector2i] = []
	if String(e.get("target", "single")) == "aoe":
		cells = _tiles_in_skill_range(me.pos, rng)
	else:
		for u in _cm.units:
			if not u.is_player and u.hp > 0 and _manhattan(me.pos, u.pos) <= rng:
				cells.append(u.pos)
	_map.show_attack_range(cells)
	var scope := "群体" if String(e.get("target", "single")) == "aoe" else "单体"
	if cells.is_empty():
		_set_action_hint("【%s】%s · 射程 %d —— 范围内没有目标（点其他地方取消）" % [nm, scope, rng])
	else:
		_set_action_hint("【%s】%s · 射程 %d —— 点击红色格子选定目标（点其他地方取消）" % [nm, scope, rng])

## 施法距离内的所有格子
func _tiles_in_skill_range(center: Vector2i, rng: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var grid: GridWorld = _map.grid
	if grid == null:
		return out
	for y in grid.rows():
		for x in grid.cols():
			var p := Vector2i(x, y)
			if _manhattan(center, p) <= rng:
				out.append(p)
	return out

## 曼哈顿距离
func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## 最近的存活敌人
func _nearest_enemy() -> CombatUnit:
	var best: CombatUnit = null
	var bd := 9999
	var me: CombatUnit = _cm.player_unit
	for u in _cm.units:
		if not u.is_player and u.hp > 0:
			var d := absi(u.pos.x - me.pos.x) + absi(u.pos.y - me.pos.y)
			if d < bd:
				bd = d
				best = u
	return best

## 把角色生命同步到战场单位
func _apply_player_hp() -> void:
	var pu: CombatUnit = _cm.player_unit
	if pu != null:
		pu.hp = Game.player.hp

## P3：意志力压制（每场一次，排斥 −10）
func _on_suppress_pressed() -> void:
	var pl := Game.player
	if not pl.can_suppress_bloodline():
		_log_line("无法压制：每场一次，需要 2 点意志力且排斥度 ≥10%。")
		return
	var before := pl.bloodline_rejection()
	pl.suppress_bloodline()
	_log_line("[color=#7ec8ff]【意志压制】你强行压住血脉的嘶吼。排斥度 %d%% → %d%%[/color]" % [
		before, pl.bloodline_rejection(),
	])
	_refresh_hud()

## P4：融合技（排斥 ≥80% 解锁，每场一次）
func _on_fusion_pressed() -> void:
	var pl := Game.player
	var fusion: Dictionary = pl.fusion_skill()
	if fusion.is_empty():
		_log_line("尚未解锁融合技（需排斥度 ≥80% 且持有对应的血脉组合）。")
		return
	if _fusion_used:
		_log_line("融合技本场已使用。")
		return
	var target: CombatUnit = null
	for u in _cm.units:
		if not u.is_player and u.hp > 0:
			target = u
			break
	if target == null:
		return
	_fusion_used = true
	var base := 6 + (2 if pl.gene_lock_level >= 1 else 0)
	var dmg := int(round(float(base) * float(pl.bloodline_combat_mods()["node_bonus"])))
	target.hp -= dmg
	_log_line("[color=#ffb3ff]【融合技·%s】血脉冲撞！%s 受到 %d 点伤害。[/color]" % [
		String(fusion.get("name", "")), target.name, dmg,
	])
	_cm._check_death(target)
	_move_node(target, target.pos)
	_refresh_hud()
	_check_over()

## P4：基因崩溃（排斥 100%）—— 角色永久死亡
func _gene_collapse() -> void:
	Game.player_dead = true
	Game.player.hp = 0
	Game.save_game()
	_show_end("基因崩溃",
		"两条血脉终于撕开了你的身体。\n你的基因在排斥中崩解 —— 轮回到此为止。",
		"回到主菜单")

func _back() -> void:
	# 基因崩溃：角色永久死亡 → 直接回主菜单（不再回到副本）
	if Game.player_dead:
		Game.scenario_state.erase("pending_combat")
		Game.scenario_state.erase("explore_state")
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return
	# 战斗结束：清空本场排斥缓解（永久调和保留）
	Game.player.clear_battle_bloodline_buffs()
	get_tree().change_scene_to_file("res://scenarios/r001_apartment/scenario.tscn")

# ——— 辅助 ———

func _refresh_hud() -> void:
	var p := Game.player
	var u := _cm.current()
	var turn_name := "—"
	var ap := 0
	if not _cm.over and u != null:
		turn_name = u.name
		ap = u.ap
	# P3/P4：血统排斥状态
	var bl_text := ""
	var rj := p.bloodline_rejection()
	if rj >= 10:
		var mark := "血脉干扰"
		if rj >= 100:
			mark = "☠基因崩溃"
		elif rj >= 50:
			mark = "⚠失控风险"
		bl_text = "　|　排斥 %d%%（%s）" % [rj, mark]
	_hud.text = "第 %d 轮　行动者：%s　AP %d/6　|　%s：%d/%d　意志 %d/%d　|　基因锁：%s%s" % [
		_cm.round, turn_name, ap, p.name, p.hp, p.max_hp(), p.will, p.max_will(),
		"一阶" if p.gene_lock_level >= 1 else "未觉醒", bl_text,
	]
	# 按钮状态
	var can_act := _cm.is_player_turn()
	_btn_attack.disabled = not can_act
	_btn_defend.disabled = not can_act
	_btn_item.disabled = not can_act
	_btn_end.disabled = not can_act
	# AP 用尽时把「结束回合」写成明确指引
	if can_act and u != null and int(u.ap) <= 0:
		_btn_end.text = "结束回合（AP 已用尽）"
	else:
		_btn_end.text = "结束回合"
	if can_act:
		_refresh_player_hint()
	# P3/P4：血统相关按钮
	if _btn_suppress != null:
		_btn_suppress.visible = rj >= 10
		_btn_suppress.disabled = not can_act or not p.can_suppress_bloodline()
	if _btn_fusion != null:
		var fusion: Dictionary = p.fusion_skill()
		_btn_fusion.visible = not fusion.is_empty()
		_btn_fusion.text = "融合技：%s" % String(fusion.get("name", "")) if not fusion.is_empty() else "融合技"
		_btn_fusion.disabled = not can_act or _fusion_used
	if _btn_skill != null:
		var skills := p.bloodline_active_skills()
		var ready := _blood_ready_count()
		_btn_skill.visible = not skills.is_empty()
		_btn_skill.text = "血统技能（%d）" % ready
		_btn_skill.disabled = not can_act or ready <= 0

func _set_action_hint(text: String) -> void:
	_action_label.text = text

func _dump_logs() -> void:
	for line in _cm.logs:
		_log.append_text(line + "\n")
	_cm.logs.clear()

func _log_line(text: String) -> void:
	_log.append_text(text + "\n")
