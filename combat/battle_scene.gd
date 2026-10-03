class_name BattleScene
extends Control
## 标准回合制战斗界面（JRPG 式）：**主角固定在左，怪物在右**，不使用地图格子。
##
## 由探索场景在接敌时创建（全屏覆盖、不切换场景），战斗结束后自行移除。
## 复用：CombatManager（伤害结算 / 死亡 / 奖励）、血统系统（排斥 / 技能 / 失控 / 融合技）。
##
## 回合规则：每回合每个单位行动一次（不消耗行动点），顺序按先攻值；
## 玩家的「攻击 / 血统技能 / 物品 / 防御 / 逃跑」各占一次行动。

signal finished(victory: bool)

const VW := 1280.0
const VH := 720.0
const GROUND := 480.0          # 角色脚底基准线
const PLAYER_X := 300.0
const ENEMY_X := 900.0
const FIGHTER_W := 256.0
const FIGHTER_H := 224.0

# —— 依赖 ——
var _host: Control
var _player: Character
var _cm: CombatManager
var _enemy_defs: Array = []    # [{"id", "pos", "uid"}]

# —— 状态 ——
var _round := 0
var _queue: Array[CombatUnit] = []
var _qi := 0
var _phase := "idle"           # idle / input / anim / over
var _surprise := false
var _defending := false
var _blood_uses: Dictionary = {}
var _fusion_used := false
var killed_uids: Array[String] = []     # 阵亡敌人 uid（探索场景据此移除尸体）
var fled := false                       # 本次是「脱离」而非「战败」——探索侧据此不判死
var player_final_pos := Vector2i.ZERO
var reward_points := 0
var _over := false

# —— UI ——
var _bg: Control
var _floor: ColorRect
var _log: RichTextLabel
var _turn_label: Label
var _cmd_box: PanelContainer
var _sub_box: VBoxContainer
var _player_root: Control
var _player_hp_fill: ColorRect
var _player_hp_text: Label
var _player_will_text: Label
var _slots: Array = []         # [{"root","fill","text","unit","name_label"}]
var _target_mark: Label
var _fx: Control
var _flee_success := false
var _player_pos_hint := Vector2i.ZERO   # 战斗结束后玩家的落点（由探索场景注入）

# ——— 构建 ———

func setup(host: Control, player: Character, enemies: Array, surprise: bool) -> void:
	_host = host
	_player = player
	_surprise = surprise
	_enemy_defs = enemies.duplicate(true)
	var list: Array[Dictionary] = []
	for e in _enemy_defs:
		# uid 必须原样传下去：探索层靠它把「已击杀」记进唯一状态源
		list.append({"id": String(e["id"]), "pos": e["pos"], "uid": String(e.get("uid", ""))})
	_cm = CombatManager.new()
	_cm.start(_player, list, Vector2i.ZERO)

func begin() -> void:
	_build_ui()
	_init_blood_uses()
	_surprise_first_strike()
	_refresh_all()
	start_idle_breath(_player_root)
	for s in _slots:
		start_idle_breath(s["root"])
	if _surprise:
		_log_line("[color=#ffd75e]【突袭】敌人措手不及 —— 你先行动！[/color]")
	_log_line("[color=#9fe3ff]面板　生命 %d　意志 %d　暴击 %d%%　移动 %d　战术点 %d　光环 %d格[/color]" % [
		_player.max_hp(), _player.max_will(), _player.crit_rate(),
		_player.move_range(), _player.tactical_points(), _player.aura_range()])
	_start_round()

## 先手裁定：突袭时把玩家放到行动队列最前
func _surprise_first_strike() -> void:
	if not _surprise:
		return
	var pu := _cm.player_unit
	_cm.order.sort_custom(func(a, b): return a.init > b.init)
	var idx := _cm.order.find(pu)
	if idx > 0:
		_cm.order.remove_at(idx)
		_cm.order.push_front(pu)

# ——— UI 构建 ———

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg = Control.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 天空 → 远景 → 地面（像素风三段落）
	var sky := ColorRect.new()
	sky.color = Color(0.09, 0.10, 0.17)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(sky)
	var far := ColorRect.new()
	far.color = Color(0.14, 0.15, 0.21)
	far.offset_left = 0
	far.offset_right = VW
	far.offset_top = GROUND - 70
	far.offset_bottom = GROUND + 8
	far.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(far)
	var horizon := ColorRect.new()
	horizon.color = Color(0.30, 0.34, 0.45, 0.55)
	horizon.offset_left = 0
	horizon.offset_right = VW
	horizon.offset_top = GROUND + 6
	horizon.offset_bottom = GROUND + 8
	horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(horizon)
	_floor = ColorRect.new()
	_floor.color = Color(0.16, 0.15, 0.18)
	_floor.offset_left = 0
	_floor.offset_right = VW
	_floor.offset_top = GROUND
	_floor.offset_bottom = VH
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_floor)
	# 地面上的网格线（景深感）
	# 战斗背景（火纹 BG，已处理成 1280×720）；插到最底层覆盖上方的降级色块
	var bg_path := "res://assets/backgrounds/w1/battle_night.png"
	if ResourceLoader.exists(bg_path):
		var bgtex := TextureRect.new()
		bgtex.texture = load(bg_path)
		bgtex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bgtex.stretch_mode = TextureRect.STRETCH_SCALE
		bgtex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bgtex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bgtex.modulate = Color(0.60, 0.60, 0.70)   # 压暗，让角色与 UI 突出
		_bg.add_child(bgtex)   # 最后加入 -> 盖住降级色块；_bg 整体在角色之下

	for i in 9:
		var ln := ColorRect.new()
		ln.color = Color(1, 1, 1, 0.05 + float(i) * 0.012)
		ln.offset_left = 0
		ln.offset_right = VW
		ln.offset_top = GROUND + 6 + i * 26
		ln.offset_bottom = GROUND + 7 + i * 26
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg.add_child(ln)

	# 回合标签
	_turn_label = Label.new()
	_turn_label.position = Vector2(28, 20)
	_turn_label.add_theme_font_size_override("font_size", 22)
	add_child(_turn_label)

	# 主角（左）
	_player_root = _make_fighter(PIXEL_PLAYER, String(_player.name), Color(0.45, 0.95, 0.6))
	_player_root.position = Vector2(PLAYER_X - FIGHTER_W / 2.0, GROUND - FIGHTER_H)
	add_child(_player_root)
	_player_hp_fill = _player_root.get_meta("fill")
	_player_hp_text = _player_root.get_meta("hptext")
	_player_will_text = _player_root.get_meta("will")

	# 敌人（右，纵向排列）
	_build_enemy_slots()

	# 目标指示箭头
	_target_mark = Label.new()
	_target_mark.text = "▼"
	_target_mark.add_theme_font_size_override("font_size", 30)
	_target_mark.modulate = Color(1, 0.85, 0.3)
	_target_mark.visible = false
	add_child(_target_mark)

	# 战斗日志
	var log_bg := ColorRect.new()
	log_bg.color = Color(0, 0, 0, 0.55)
	log_bg.offset_left = 20
	log_bg.offset_right = VW - 20
	log_bg.offset_top = VH - 158
	log_bg.offset_bottom = VH - 84
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_bg)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.offset_left = 34
	_log.offset_right = VW - 34
	_log.offset_top = VH - 152
	_log.offset_bottom = VH - 88
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)

	# 指令面板
	_cmd_box = PanelContainer.new()
	_cmd_box.position = Vector2(24, VH - 88)
	_cmd_box.visible = false
	add_child(_cmd_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_cmd_box.add_child(row)
	for spec in [
		["攻击", _on_cmd_attack],
		["血统技能", _on_cmd_skill],
		["物品", _on_cmd_item],
		["防御", _on_cmd_defend],
		["意志", _on_cmd_will],
		["快进", func(): toggle_speed()],
		["逃跑", _on_cmd_flee],
	]:
		var b := Button.new()
		b.text = String(spec[0])
		b.custom_minimum_size = Vector2(130, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(spec[1])
		row.add_child(b)

	# 子菜单（技能 / 物品 / 选目标）
	_sub_box = VBoxContainer.new()
	# 居中偏下：原来放在 (24, VH-300)，正好压在主角立绘、名字和血条上
	_sub_box.position = Vector2(VW * 0.5 - 160.0, VH - 372.0)
	_sub_box.add_theme_constant_override("separation", 6)
	_sub_box.visible = false
	add_child(_sub_box)

	# 特效层
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

## 战斗立绘（64×96，由 tools/pixelart/gen_battle_sprites.lua 程序化生成）
const PIXEL_PLAYER := "res://assets/sprites/w1/battle/hero.png"
const PIXEL_ZOMBIE := "res://assets/sprites/w1/battle/zombie.png"
const PIXEL_CRAWLER := "res://assets/sprites/w1/battle/crawler.png"
const PIXEL_BRUTE := "res://assets/sprites/w1/battle/brute.png"

## 造一个「战斗单位」视觉：立绘 + 名字 + HP 条
func _make_fighter(tex_path: String, title: String, hp_color: Color) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FIGHTER_W, FIGHTER_H + 60)

	var tex := TextureRect.new()
	if ResourceLoader.exists(tex_path):
		tex.texture = load(tex_path)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.position = Vector2(0, 0)
	tex.size = Vector2(FIGHTER_W, FIGHTER_H)
	root.add_child(tex)

	var nm := Label.new()
	nm.text = title
	nm.position = Vector2(0, FIGHTER_H)
	nm.size = Vector2(FIGHTER_W, 22)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 17)
	root.add_child(nm)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.75)
	bar_bg.position = Vector2(10, FIGHTER_H + 26)
	bar_bg.size = Vector2(180, 14)
	root.add_child(bar_bg)
	var fill := ColorRect.new()
	fill.color = hp_color
	fill.position = Vector2(11, FIGHTER_H + 27)
	fill.size = Vector2(178, 12)
	root.add_child(fill)

	var hpt := Label.new()
	hpt.position = Vector2(0, FIGHTER_H + 42)
	hpt.size = Vector2(FIGHTER_W, 20)
	hpt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hpt.add_theme_font_size_override("font_size", 15)
	root.add_child(hpt)

	var will := Label.new()
	will.position = Vector2(0, FIGHTER_H + 60)
	will.size = Vector2(FIGHTER_W, 20)
	will.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	will.modulate = Color(0.75, 0.85, 1.0)
	will.add_theme_font_size_override("font_size", 14)
	root.add_child(will)

	root.set_meta("fill", fill)
	root.set_meta("hptext", hpt)
	root.set_meta("will", will)
	root.set_meta("tex", tex)
	return root

func _build_enemy_slots() -> void:
	_slots.clear()
	var alive: Array = []
	for u in _cm.units:
		if not u.is_player:
			alive.append(u)
	var n := alive.size()
	for i in n:
		var u: CombatUnit = alive[i]
		var def_id := "zombie"
		if i < _enemy_defs.size():
			def_id = String(_enemy_defs[i]["id"])
		var tex_path := PIXEL_ZOMBIE
		if def_id == "crawler":
			tex_path = PIXEL_CRAWLER
		elif def_id == "brute":
			tex_path = PIXEL_BRUTE
		var root := _make_fighter(tex_path, u.name, Color(0.9, 0.35, 0.35))
		# 右侧纵向排布
		var x := ENEMY_X - FIGHTER_W / 2.0 - float(i) * 96.0
		var y := GROUND - FIGHTER_H - float(i) * 46.0
		root.position = Vector2(x, y)
		add_child(root)
		_slots.append({
			"root": root, "fill": root.get_meta("fill"), "text": root.get_meta("hptext"),
			"unit": u, "def_id": def_id,
		})

# ——— 回合流 ———

func _start_round() -> void:
	if _over:
		return
	_round += 1
	_turn_label.text = "第 %d 回合" % _round
	_defending = false
	_queue.clear()
	var sorted := _cm.order.duplicate()
	sorted.sort_custom(func(a, b): return a.init > b.init)
	for u in sorted:
		_queue.append(u)
	_qi = 0
	DebugLog.ev("turn", "新回合", {
		"round": _round, "order": _cm.order.size(), "queue": _queue.size(),
		"has_player": _queue.any(func(x): return x.is_player),
	})
	_refresh_all()
	_log_line("[color=#8cd8ff]—— 第 %d 回合 ——[/color]" % _round)
	_next_actor()

func _next_actor() -> void:
	if _check_over():
		return
	DebugLog.ev("turn", "取下一个行动者", {"qi": _qi, "queue": _queue.size(), "round": _round})
	if _qi >= _queue.size():
		_start_round()
		return
	var u: CombatUnit = _queue[_qi]
	_qi += 1
	if u.hp <= 0:
		_next_actor()
		return
	_refresh_all()
	if u.is_player:
		_phase = "input"
		_check_unstable_before_input()
	else:
		_phase = "anim"
		_enemy_act(u)

func _enemy_act(u: CombatUnit) -> void:
	DebugLog.ev("turn", "敌人行动开始", {"who": u.name, "hp": u.hp})
	await _wait(0.45)
	if _over:
		return
	var target := _cm.player_unit
	var res := _cm.resolve_attack(u, target)
	DebugLog.ev("turn", "敌人行动结算", {"who": u.name, "target_hp": target.hp, "res": res})
	await _play_strike(u, target, res)
	DebugLog.ev("turn", "敌人演出结束", {"who": u.name})
	# 战斗单位是权威，直接同步回角色卡。
	# 原来写的是 mini(_player.hp, target.hp) —— 取较小值会把吃药回的血夹回旧值，
	# 表现就是「连吃四个急救包血还在掉」。
	_apply_player_hp()
	_refresh_all()
	if target.hp <= 0:
		_finish(false)
		return
	await _wait(0.35)
	_next_actor()

## 玩家行动完成 → 下一个
func _advance() -> void:
	_sub_box.visible = false
	_cmd_box.visible = false
	_refresh_all()
	await _wait(0.25)
	_next_actor()

# ——— 玩家指令 ———

func _show_commands() -> void:
	_cmd_box.visible = true
	_sub_box.visible = false

func _clear_sub() -> void:
	for c in _sub_box.get_children():
		c.queue_free()
	_sub_box.visible = false

func _add_sub_button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.disabled = disabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_sub_box.add_child(b)
	return b

func _alive_enemies() -> Array:
	var out: Array = []
	for u in _cm.units:
		if not u.is_player and u.hp > 0:
			out.append(u)
	return out

func _on_cmd_attack() -> void:
	var foes := _alive_enemies()
	if foes.is_empty():
		_next_actor()
		return
	_clear_sub()
	_pick_target("攻击谁？", foes, func(t: CombatUnit) -> void:
		_do_player_attack(t)
	)

func _pick_target(title: String, foes: Array, cb: Callable) -> void:
	_sub_box.visible = true
	var tip := Label.new()
	tip.text = title
	tip.add_theme_font_size_override("font_size", 15)
	_sub_box.add_child(tip)
	for f in foes:
		_add_sub_button("%s  HP %d/%d" % [f.name, maxi(f.hp, 0), f.max_hp], func() -> void:
			_clear_sub()
			cb.call(f)
		)

func _do_player_attack(target: CombatUnit) -> void:
	_phase = "anim"
	_cmd_box.visible = false
	_clear_sub()
	var res := _cm.resolve_attack(_cm.player_unit, target)
	await _play_strike(_cm.player_unit, target, res)
	_refresh_all()
	await _wait(0.35)
	_advance()

func _on_cmd_skill() -> void:
	_clear_sub()
	var pl := _player
	var skills := pl.bloodline_active_skills()
	if skills.is_empty():
		_log_line("没有血统技能。")
		return
	_sub_box.visible = true
	var tip := Label.new()
	tip.text = "使用血统技能"
	tip.add_theme_font_size_override("font_size", 15)
	_sub_box.add_child(tip)
	for node in skills:
		var nid := String(node.get("id", ""))
		var left := int(_blood_uses.get(nid, 0))
		_add_sub_button("%s（%s，剩余 %d）" % [String(node.get("name", nid)), Bloodlines.effect_text(nid), left],
			func() -> void: _use_skill(nid), left <= 0)

func _use_skill(node_id: String) -> void:
	_clear_sub()
	_cmd_box.visible = false
	var e := Bloodlines.active_effect(node_id)
	var kind := String(e.get("kind", "damage"))
	# 伤害/削弱类需要选目标
	if kind == "damage" or kind == "damage_heal" or kind == "debuff":
		if String(e.get("target", "single")) == "aoe":
			_execute_skill(node_id, null)
		else:
			var foes := _alive_enemies()
			if foes.is_empty():
				_next_actor()
				return
			_pick_target("对谁使用？", foes, func(t: CombatUnit) -> void:
				_execute_skill(node_id, t)
			)
	else:
		_execute_skill(node_id, null)

func _execute_skill(node_id: String, target: CombatUnit) -> void:
	_phase = "anim"
	_clear_sub()
	_cmd_box.visible = false
	var pl := _player
	var e := Bloodlines.active_effect(node_id)
	var left := int(_blood_uses.get(node_id, int(e.get("uses", 3))))
	if left <= 0:
		_next_actor()
		return
	var bonus := float(pl.bloodline_combat_mods()["node_bonus"])
	var power := int(round(float(int(e.get("power", 4))) * bonus))
	var kind := String(e.get("kind", "damage"))
	var is_aoe := String(e.get("target", "single")) == "aoe"
	var nm := Bloodlines.node_name(node_id)
	var scope := "群体" if is_aoe else "单体"

	var victims: Array = []
	if kind == "damage" or kind == "damage_heal" or kind == "debuff":
		if is_aoe or target == null:
			victims = _alive_enemies()
		else:
			victims = [target]

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
			_log_line("[color=#ffb3b3]【%s】%s：%d 个敌人被削弱。[/color]" % [nm, scope, victims.size()])
		_:
			# 先结算数据，再播放演出（数据优先于表现，也避免异步导致测试/逻辑读到旧值）
			for u in victims:
				u.hp -= power
				if u.hp <= 0:
					_cm._check_death(u)
			for u in victims:
				_play_skill_hit(u, power)
			if kind == "damage_heal" and not victims.is_empty():
				pl.hp = mini(pl.max_hp(), pl.hp + int(e.get("heal", 3)))
				_apply_player_hp()
			if victims.is_empty():
				_log_line("【%s】没有目标。[/color]" % nm)
			else:
				_log_line("[color=#ffd75e]【%s】%s：%d 个敌人各受 %d 点伤害。[/color]" % [nm, scope, victims.size(), power])

	_blood_uses[node_id] = left - 1
	_refresh_all()
	await _wait(0.35)
	_advance()

func _on_cmd_item() -> void:
	_clear_sub()
	var inv: Array = []
	for it in _player.inventory:
		if String(Items.get_def(it).get("kind", "")) == "consumable":
			inv.append(it)
	if inv.is_empty():
		_log_line("没有可用的消耗品。")
		return
	_sub_box.visible = true
	var tip := Label.new()
	tip.text = "使用物品"
	tip.add_theme_font_size_override("font_size", 15)
	_sub_box.add_child(tip)
	for it in inv:
		_add_sub_button("%s（%s）" % [Items.name_of(it), _item_text(it)], func() -> void:
			_use_item(String(it))
		)

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
	_clear_sub()
	_cmd_box.visible = false
	var res := _cm.try_use_item(_cm.player_unit, id)
	if not res.get("ok", false):
		_log_line(String(res.get("reason", "无法使用。")))
		_advance()
		return
	_apply_player_hp()
	var stab := int(Items.get_def(id).get("stabilize", 0))
	if stab > 0:
		var before := _player.bloodline_rejection()
		_player.use_stabilizer(stab)
		_log_line("[color=#7ec8ff]【血脉稳定剂】排斥度 %d%% → %d%%[/color]" % [before, _player.bloodline_rejection()])
	_refresh_all()
	_advance()

## 属性重做·意志力：消耗 1 点意志（上限 = 2×决心），每回合限 1 次
func _on_cmd_will() -> void:
	_clear_sub()
	_cmd_box.visible = false
	if _player.will <= 0:
		_log_line("[color=#ffb3b3]意志力已耗尽（上限 = 2×决心）。[/color]")
		_advance()
		return
	_show_will_menu()

func _show_will_menu() -> void:
	_clear_sub()
	_sub_box.visible = true
	var title := Label.new()
	title.text = "意志力 %d/%d（每回合限 1 次）" % [_player.will, _player.max_will()]
	title.add_theme_font_size_override("font_size", 16)
	_sub_box.add_child(title)
	_add_sub_button("专注　下次攻击 +1 成功", func(): _apply_will("focus"))
	_add_sub_button("固守　本回合防御 +2", func(): _apply_will("guard"))
	_add_sub_button("闪避　抵消下一次命中", func(): _apply_will("dodge"))
	_add_sub_button("返回", func():
		_clear_sub()
		_show_commands())

func _apply_will(kind: String) -> void:
	_clear_sub()
	if _player.will <= 0:
		_advance()
		return
	_player.will -= 1
	var pu := _cm.player_unit
	match kind:
		"focus":
			pu.will_focus = true
			_log_line("[color=#9fe3ff]意志「专注」：下一次攻击 +1 成功。[/color]")
		"guard":
			_defending = true
			pu.defense += 2
			_log_line("[color=#9fe3ff]意志「固守」：本回合防御 +2。[/color]")
		"dodge":
			pu.will_dodge = true
			_log_line("[color=#9fe3ff]意志「闪避」：将抵消下一次命中。[/color]")
	_refresh_all()
	_advance()

func _on_cmd_defend() -> void:
	_clear_sub()
	_cmd_box.visible = false
	_defending = true
	_cm.player_unit.defense += 2
	_log_line("[color=#8cd8ff]你摆出防御姿态（防御 +2，直到下回合）。[/color]")
	_advance()

func _on_cmd_flee() -> void:
	_clear_sub()
	_cmd_box.visible = false
	var roll := DicePool.roll(_player.attr("dex"), _player.skill("subterfuge"))
	if int(roll.get("successes", 0)) > 0:
		_log_line("[color=#ffd75e]你成功脱离了战斗。[/color]")
		await _wait(0.8)
		_flee_success = true
		_finish(false, true)
	else:
		_log_line("[color=#ff8c66]逃跑失败！[/color]")
		_advance()

# ——— 演出 ———

func _node_of(u: CombatUnit) -> Control:
	if u.is_player:
		return _player_root
	for s in _slots:
		if s["unit"] == u:
			return s["root"]
	return null

func _play_strike(att: CombatUnit, target: CombatUnit, res: Dictionary) -> void:
	var an := _node_of(att)
	var tn := _node_of(target)
	if an == null or tn == null:
		return
	var dir := 1.0 if att.is_player else -1.0
	await anim_attack(an, dir)
	var dmg := int(res.get("damage", 0))
	var hit := bool(res.get("hit", true))
	if not hit:
		_spawn_text(tn.position + Vector2(60, 40), "MISS", Color(0.8, 0.8, 0.8))
		_log_line("%s 没有击中 %s。" % [att.name, target.name])
		return
	# 命中停顿 + 斩击 + 后仰闪红 + 屏幕震动
	await _hit_stop(0.06)
	fx_slash(tn.position + Vector2(60, 40), Color(1, 1, 1))
	_shake(9.0, 0.20)
	await anim_hurt(tn, dir)
	var crit: bool = int(res.get("successes", 0)) >= 4
	_spawn_text(tn.position + Vector2(60, 30), "-%d" % dmg,
		Color(1.0, 0.9, 0.3) if crit else Color(1, 0.4, 0.4))
	if crit:
		_spawn_text(tn.position + Vector2(36, 4), "CRIT!", Color(1.0, 0.85, 0.2))
	_log_line("%s 攻击 %s：成功 %d → %d 点伤害。" % [
		att.name, target.name, int(res.get("successes", 0)), dmg,
	])
	if target.hp <= 0:
		_log_line("[color=#ffb3b3]%s 倒下了。[/color]" % target.name)
		await anim_die(tn)

func _play_skill_hit(target: CombatUnit, power: int) -> void:
	var tn := _node_of(target)
	if tn == null:
		return
	fx_sword_aura(tn.position + Vector2(60, 50))
	await _hit_stop(0.05)
	var tw := create_tween()
	tw.tween_property(tn, "modulate", Color(1.6, 1.2, 2.2), 0.10)
	tw.tween_property(tn, "modulate", Color(1, 1, 1), 0.18)
	await tw.finished
	_spawn_text(tn.position + Vector2(60, 30), "-%d" % power, Color(1, 0.75, 0.35))

func _fade_out(n: Control) -> void:
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", 0.0, 0.35)
	await tw.finished
	n.visible = false

## 演出速度倍率：1.0 = 正常，2.5 = 快进。等待与动画都按它缩放。
var _speed := 1.0

## 可调速的等待（替代直接 create_timer，让「快进」能整体压缩演出）
func _wait(sec: float) -> void:
	var d := sec / maxf(0.05, _speed)
	if d > 0.001:
		await get_tree().create_timer(d).timeout

## 切换快进：1x ⇄ 2.5x
func toggle_speed() -> void:
	_speed = 2.5 if _speed < 2.0 else 1.0
	_log_line("[color=#9fe3ff]演出速度 → %.1fx[/color]" % _speed)

## 受击屏幕震动（打击感的关键）
func _shake(strength: float = 8.0, dur: float = 0.2) -> void:
	var base := position
	var steps := 5
	var tw := create_tween()
	for i in steps:
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tw.tween_property(self, "position", base + off, dur / float(steps))
	tw.tween_property(self, "position", base, dur / float(steps))

# ——— 帧动画（程序化：对静态立绘做变换，做出火纹式的一招一式）———
# 注意：只对**立绘**（TextureRect）做变换，名字与血条保持不动。

func _sprite_of(node: Control) -> Control:
	if node == null:
		return null
	if node.has_meta("tex"):
		return node.get_meta("tex")
	return node

## 待机呼吸：缓慢起伏，让角色"活着"而不是贴图
func start_idle_breath(node: Control) -> void:
	var s := _sprite_of(node)
	if s == null:
		return
	var home_y := s.position.y
	var tw := create_tween().set_loops()
	tw.tween_property(s, "position:y", home_y - 4.0, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "position:y", home_y, 1.0).set_trans(Tween.TRANS_SINE)

## 攻击：预备后拉 → 突进 → 挥击停顿 → 归位
func anim_attack(node: Control, dir: float) -> void:
	var s := _sprite_of(node)
	if s == null:
		return
	var home := s.position
	var f := 1.0 / maxf(0.05, _speed)
	var tw := create_tween()
	tw.tween_property(s, "position", home - Vector2(16.0 * dir, 0), 0.12 * f)
	tw.tween_property(s, "position", home + Vector2(86.0 * dir, -8.0), 0.10 * f)
	tw.tween_property(s, "position", home + Vector2(62.0 * dir, 0), 0.09 * f)
	await tw.finished
	var tw2 := create_tween()
	tw2.tween_property(s, "position", home, 0.20 * f).set_trans(Tween.TRANS_QUAD)

## 受击：向后顿挫 + 闪红
func anim_hurt(node: Control, dir: float) -> void:
	var s := _sprite_of(node)
	if s == null:
		return
	var home := s.position
	var f := 1.0 / maxf(0.05, _speed)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position", home - Vector2(20.0 * dir, 0), 0.07 * f)
	tw.tween_property(s, "modulate", Color(2.4, 0.65, 0.65), 0.07 * f)
	tw.chain().tween_property(s, "position", home, 0.16 * f)
	tw.chain().tween_property(s, "modulate", Color(1, 1, 1), 0.16 * f)
	await tw.finished

## 施法：上浮 + 轻微放大
func anim_cast(node: Control) -> void:
	var s := _sprite_of(node)
	if s == null:
		return
	var home := s.position
	var tw := create_tween()
	tw.tween_property(s, "position", home - Vector2(0, 16), 0.16)
	tw.parallel().tween_property(s, "scale", Vector2(1.06, 1.06), 0.16)
	tw.tween_property(s, "position", home, 0.22)
	tw.parallel().tween_property(s, "scale", Vector2(1, 1), 0.22)
	await tw.finished

## 倒下：旋转 + 淡出
func anim_die(node: Control) -> void:
	var s := _sprite_of(node)
	if s == null:
		return
	s.pivot_offset = Vector2(s.size.x * 0.5, s.size.y)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "rotation", deg_to_rad(76.0), 0.45).set_trans(Tween.TRANS_BACK)
	tw.tween_property(s, "modulate:a", 0.0, 0.55)
	await tw.finished
	s.visible = false

# ——— 技能特效（程序化绘制，不依赖外部素材）———

## 命中停顿：极短地冻结时间，制造打击感（用真实时间等待，避免被 time_scale 拖住）
func _hit_stop(dur: float = 0.07) -> void:
	Engine.time_scale = 0.04
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0

## 斩击：一道白光横划而过
func fx_slash(at: Vector2, color: Color = Color(1, 1, 1)) -> void:
	var ln := ColorRect.new()
	ln.color = color
	ln.size = Vector2(4, 7)
	ln.position = at + Vector2(-70, -20)
	_fx.add_child(ln)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ln, "size:x", 170.0, 0.14)
	tw.tween_property(ln, "modulate:a", 0.0, 0.30).set_delay(0.10)
	tw.tween_callback(ln.queue_free).set_delay(0.34)
	await _wait(0.20)

## 符箓：三张符纸自上落下后炸开
func fx_talisman(at: Vector2) -> void:
	for i in 3:
		var t := ColorRect.new()
		t.color = Color(1.0, 0.86, 0.32)
		t.size = Vector2(15, 21)
		t.position = at + Vector2(-34 + i * 24, -150)
		_fx.add_child(t)
		var tw := create_tween()
		tw.tween_property(t, "position:y", at.y - 10, 0.30).set_delay(i * 0.05)
		tw.tween_property(t, "modulate:a", 0.0, 0.14)
		tw.tween_callback(t.queue_free)
	await _wait(0.30)
	fx_burst(at, Color(1.0, 0.9, 0.45))

## 治疗：上升的绿光点
func fx_heal(at: Vector2) -> void:
	for i in 12:
		var dot := ColorRect.new()
		dot.color = Color(0.42, 1.0, 0.52, 0.95)
		dot.size = Vector2(4, 4)
		dot.position = at + Vector2(randf_range(-46, 46), randf_range(-10, 30))
		_fx.add_child(dot)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dot, "position:y", dot.position.y - 120.0, 0.62)
		tw.tween_property(dot, "modulate:a", 0.0, 0.62)
		tw.tween_callback(dot.queue_free)
	await _wait(0.32)

## 扩散光环（群体技能 / 融合技 / 施法）
func fx_burst(at: Vector2, color: Color = Color(1.0, 0.85, 0.40)) -> void:
	var ring := ColorRect.new()
	ring.color = color
	ring.size = Vector2(24, 24)
	ring.position = at + Vector2(-12, -12)
	_fx.add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "size", Vector2(270, 270), 0.34)
	tw.tween_property(ring, "position", at + Vector2(-135, -135), 0.34)
	tw.tween_property(ring, "modulate:a", 0.0, 0.34)
	tw.tween_callback(ring.queue_free)
	await _wait(0.34)

## 剑气：多道斜光（御剑类）
func fx_sword_aura(at: Vector2) -> void:
	fx_slash(at + Vector2(0, -30), Color(0.72, 0.88, 1.0))
	fx_slash(at + Vector2(0, 20), Color(0.86, 0.94, 1.0))
	await _wait(0.10)
	fx_burst(at, Color(0.65, 0.85, 1.0))

func _spawn_text(at: Vector2, text: String, color: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = at
	lb.add_theme_font_size_override("font_size", 26)
	lb.modulate = color
	_fx.add_child(lb)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "position", at + Vector2(0, -46), 0.7)
	tw.tween_property(lb, "modulate:a", 0.0, 0.7)
	await tw.finished
	lb.queue_free()

# ——— 辅助 ———

func _log_line(text: String) -> void:
	if _log != null:
		_log.append_text(text + "\n")

func _apply_player_hp() -> void:
	# 战斗单位才是权威 —— 攻击结算改的是 CombatUnit.hp，这里要把它同步**回**角色卡。
	# 方向写反的后果：吃药加的血会被旧的 Character.hp 当场覆盖，
	# 表现为「连吃四个急救包，血反而越来越少」。
	var pu := _cm.player_unit
	if pu != null:
		_player.hp = pu.hp
		DebugLog.ev("hp_sync", "战斗单位 → 角色卡", {"unit": pu.hp, "char": _player.hp, "max": pu.max_hp})

func _refresh_all() -> void:
	var pu := _cm.player_unit
	if pu != null:
		_player_hp_text.text = "%d / %d" % [maxi(_player.hp, 0), _player.max_hp()]
		var ratio := 0.0
		if _player.max_hp() > 0:
			ratio = clampf(float(_player.hp) / float(_player.max_hp()), 0.0, 1.0)
		var want := Vector2(178.0 * ratio, 12)
		if absf(_player_hp_fill.size.x - want.x) > 0.5:
			var twp := create_tween()
			twp.tween_property(_player_hp_fill, "size", want, 0.22)
		_player_will_text.text = "意志 %d/%d" % [_player.will, _player.max_will()]
		if _player_root.has_meta("tex"):
			var tex: TextureRect = _player_root.get_meta("tex")
			tex.modulate = Color(1, 1, 1) if _phase != "anim" else Color(1.2, 1.2, 1.2)
	for s in _slots:
		var u: CombatUnit = s["unit"]
		var ratio2 := 0.0
		if u.max_hp > 0:
			ratio2 = clampf(float(maxi(u.hp, 0)) / float(u.max_hp), 0.0, 1.0)
		var want2 := Vector2(178.0 * ratio2, 12)
		if absf(s["fill"].size.x - want2.x) > 0.5:
			var twp2 := create_tween()
			twp2.tween_property(s["fill"], "size", want2, 0.22)
		s["text"].text = "%d / %d" % [maxi(u.hp, 0), u.max_hp]
		if u.hp <= 0:
			s["root"].visible = false

func _init_blood_uses() -> void:
	_blood_uses.clear()
	for node in _player.bloodline_active_skills():
		var nid := String(node.get("id", ""))
		_blood_uses[nid] = int(Bloodlines.active_effect(nid).get("uses", 3))

## 玩家行动前判定血脉失控
func _check_unstable_before_input() -> void:
	var chance := float(_player.bloodline_combat_mods().get("unstable_chance", 0.0))
	if chance <= 0.0 or randf() >= chance:
		_show_commands()
		return
	_log_line("[color=#ff6b6b]【血脉失控】两条血脉互相撕扯，你失去了本回合的控制！[/color]")
	var pu := _cm.player_unit
	pu.hp = maxi(0, pu.hp - 1)
	_player.hp = pu.hp
	_refresh_all()
	if pu.hp <= 0:
		_finish(false)
		return
	await _wait(0.6)
	_next_actor()

func _check_over() -> bool:
	if _over:
		return true
	if _cm.player_unit != null and _cm.player_unit.hp <= 0:
		_finish(false)
		return true
	if _alive_enemies().is_empty():
		_finish(true)
		return true
	return false

func _finish(victory: bool, is_fleeing := false) -> void:
	if _over:
		return
	_over = true
	fled = is_fleeing
	_phase = "over"
	_cmd_box.visible = false
	_clear_sub()
	for u in _cm.fallen:
		killed_uids.append(u.uid)
	reward_points = _cm.reward_points()
	player_final_pos = _player_pos_hint
	if victory:
		_log_line("[color=#ffd75e]—— 战斗胜利 ——[/color]")
		await _wait(1.0)
	elif is_fleeing:
		_log_line("[color=#8cd8ff]—— 你脱离了战斗 ——[/color]")
		await _wait(0.6)
	else:
		_log_line("[color=#ff6b6b]—— 你倒下了 ——[/color]")
		await _wait(1.0)
	finished.emit(victory)

# ——— 兼容旧测试 / 旧截图脚本的接口 ———
# 旧战斗场景（格子制）暴露过这些名字，旧测试仍在用；这里只做转发，不影响新流程。

## compat: uid -> 立绘节点
var _unit_nodes: Dictionary:
	get:
		var d: Dictionary = {}
		if _cm == null:
			return d
		for u in _cm.units:
			var n := _node_of(u)
			if n != null:
				d[u.uid] = n
		return d

## compat: 结束当前行动
func _on_end_turn_pressed() -> void:
	_advance()

## compat: 对第一个存活敌人释放技能
func _use_blood_skill(node_id: String) -> void:
	var foes := _alive_enemies()
	_execute_skill(node_id, foes[0] if not foes.is_empty() else null)

func _use_blood_skill_at(node_id: String, _pos: Vector2i) -> void:
	_use_blood_skill(node_id)

func _open_command_menu() -> void:
	_show_commands()

func _begin_skill_aim(node_id: String) -> void:
	_use_blood_skill(node_id)

func _exit_modes() -> void:
	pass

func _back() -> void:
	pass
