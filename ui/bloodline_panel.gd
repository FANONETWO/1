class_name BloodlinePanel
extends Control
## 主神空间 · 血统页（P1）。
##
## 功能：
##   · 激活 D 级血统（800 奖励点）—— **只能从最低级起步**
##   · 按评级选择技能：每级 3–4 个候选，只能选 2 个（S 级选 1 个）
##   · 升级评级（消耗奖励点），升级前必须选满当前级
##   · 实时显示**排斥度**与**协同度**双条及其档位效果，并在激活前预览变化
##
## 规则来源：docs/血统模块设计方案.md

signal closed

const ACTIVATE_COST := 800

var _selected_id: String = ""
var _stat_box: VBoxContainer
var _list_box: VBoxContainer
var _skill_box: VBoxContainer
var _points_label: Label
var _toast: Label
var _toast_timer: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var owned: Array = Game.player.bloodlines
	if not owned.is_empty():
		_selected_id = String(owned[0].get("id", ""))
	_refresh()

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast != null:
			_toast.text = ""

# ——— 构建 ———

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var title := Label.new()
	title.text = "血 统"
	title.add_theme_font_size_override("font_size", 30)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 12
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_stat_box = VBoxContainer.new()
	_stat_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stat_box.offset_left = 60
	_stat_box.offset_right = -60
	_stat_box.offset_top = 54
	_stat_box.add_theme_constant_override("separation", 3)
	add_child(_stat_box)

	var mid := HBoxContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mid.offset_left = 60
	mid.offset_right = -60
	mid.offset_top = 196
	mid.offset_bottom = -76
	mid.add_theme_constant_override("separation", 20)
	add_child(mid)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(330, 0)
	var lv := VBoxContainer.new()
	left_panel.add_child(lv)
	var lt := Label.new()
	lt.text = "血脉"
	lt.add_theme_font_size_override("font_size", 18)
	lv.add_child(lt)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 5)
	scroll.add_child(_list_box)
	mid.add_child(left_panel)

	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rscroll := ScrollContainer.new()
	right_panel.add_child(rscroll)
	_skill_box = VBoxContainer.new()
	_skill_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_box.add_theme_constant_override("separation", 7)
	rscroll.add_child(_skill_box)
	mid.add_child(right_panel)

	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 60
	bottom.offset_right = -60
	bottom.offset_top = -58
	bottom.offset_bottom = -12
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 18)
	bottom.add_child(_points_label)
	_toast = Label.new()
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.modulate = Color(1, 0.82, 0.4)
	bottom.add_child(_toast)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: closed.emit())
	bottom.add_child(close)

# ——— 刷新 ———

func _refresh() -> void:
	if Game.player == null:
		return
	_points_label.text = "奖励点：%d" % Game.points
	_rebuild_stats()
	_rebuild_list()
	_rebuild_skills()

func _rebuild_stats() -> void:
	for c in _stat_box.get_children():
		_stat_box.remove_child(c)
		c.queue_free()
	var owned: Array = Game.player.bloodlines
	var rj := Bloodlines.rejection(owned)
	var sy := Bloodlines.synergy(owned)
	var rti := Bloodlines.rejection_tier(rj)
	var sti := Bloodlines.synergy_tier(sy)
	_stat_box.add_child(_bar_row("排斥度", rj, 100, Color(0.9, 0.32, 0.3), _rejection_tier_name(rti)))
	_stat_box.add_child(_bar_row("协同度", sy, 60, Color(0.35, 0.85, 0.5), _synergy_tier_name(sti)))

	var re := Bloodlines.rejection_effects(rj)
	var se := Bloodlines.synergy_effects(sy)
	if rj >= 10:
		_stat_box.add_child(_hint("血脉干扰：命中 %d / 伤害 %d / 防御 %d" % [re["hit"], re["damage"], re["defense"]]))
	if rj >= 50:
		_stat_box.add_child(_hint("失控风险：每回合 %d%% 概率失控（攻击最近单位）" % int(float(re["unstable_chance"]) * 100.0), Color(1, 0.72, 0.4)))
	if rj >= 100:
		_stat_box.add_child(_hint("⚠ 基因崩溃：战斗或探索结束时角色永久死亡", Color(1, 0.4, 0.4)))
	if sy >= 10:
		_stat_box.add_child(_hint("血脉共鸣：血统技能数值 +%d%%" % int((float(se["node_bonus"]) - 1.0) * 100.0), Color(0.6, 1.0, 0.7)))
	if sy >= 30:
		_stat_box.add_child(_hint("主动技能共享使用次数", Color(0.6, 1.0, 0.7)))
	if sy >= 50:
		_stat_box.add_child(_hint("已解锁协同技", Color(0.6, 1.0, 0.7)))
	# P4：融合技
	var fusion: Dictionary = Game.player.fusion_skill()
	if not fusion.is_empty():
		_stat_box.add_child(_hint("✦ 融合技「%s」—— %s" % [
			String(fusion.get("name", "")), String(fusion.get("desc", "")),
		], Color(1.0, 0.75, 1.0)))
	# P3：调和手术（永久 −20）
	if not owned.is_empty():
		var cost := Game.player.tolerance_repair_cost()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_hint("调和手术：永久 −20%% 排斥（已减免 %d%%）" % Game.player.bloodline_tolerance, Color(0.75, 0.9, 1.0)))
		var rep := Button.new()
		rep.text = "施行（%d 点）" % cost
		rep.disabled = cost <= 0 or Game.points < cost
		rep.pressed.connect(_do_tolerance_repair)
		row.add_child(rep)
		_stat_box.add_child(row)

func _rebuild_list() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	var owned: Array = Game.player.bloodlines
	_list_box.add_child(_section("已拥有（%d）" % owned.size()))
	if owned.is_empty():
		_list_box.add_child(_hint("尚无血脉 —— 你仍是纯人类。"))
	for e in owned:
		var id := String(e.get("id", ""))
		var rank := String(e.get("rank", "D"))
		var b := Button.new()
		b.text = "%s · %s 级" % [Bloodlines.name_of(id), rank]
		b.pressed.connect(_select_blood.bind(id))
		if id == _selected_id:
			b.modulate = Color(1, 0.95, 0.7)
		_list_box.add_child(b)

	var avail: Array[String] = []
	for id in Bloodlines.all_ids():
		if not Game.player.has_bloodline(id):
			avail.append(id)
	if not avail.is_empty():
		_list_box.add_child(_section("可激活（%d 点）" % ACTIVATE_COST))
		var cur := Bloodlines.rejection(owned)
		for id in avail:
			var after := _preview_rejection(id, "D")
			var b := Button.new()
			b.text = "%s（%s）" % [Bloodlines.name_of(id), Bloodlines.family_of(id)]
			b.tooltip_text = "激活后排斥度：%d%% → %d%%" % [cur, after]
			b.pressed.connect(_select_blood.bind(id))
			if id == _selected_id:
				b.modulate = Color(0.85, 0.95, 1.0)
			_list_box.add_child(b)

func _rebuild_skills() -> void:
	for c in _skill_box.get_children():
		_skill_box.remove_child(c)
		c.queue_free()
	if _selected_id == "":
		_skill_box.add_child(_hint("从左侧选择一条血脉查看详情。"))
		return
	var id := _selected_id
	var d := Bloodlines.def_of(id)
	var owned := Game.player.has_bloodline(id)
	var rank := Game.player.bloodline_rank(id) if owned else "D"

	var t := Label.new()
	t.text = "%s · %s · 来源 %s" % [String(d.get("name", id)), String(d.get("family", "")), String(d.get("world", ""))]
	t.add_theme_font_size_override("font_size", 20)
	_skill_box.add_child(t)
	_skill_box.add_child(_hint(String(d.get("intro", ""))))
	var tag_names: Array[String] = []
	for tg in d.get("tags", []):
		tag_names.append(String(Bloodlines.TAG_NAMES.get(String(tg), tg)))
	_skill_box.add_child(_hint("谱系：" + "、".join(tag_names)))

	if not owned:
		_skill_box.add_child(_section("未激活"))
		var cur := Bloodlines.rejection(Game.player.bloodlines)
		var after := _preview_rejection(id, "D")
		_skill_box.add_child(_hint("激活预览：排斥度 %d%% → %d%%" % [cur, after], Color(1, 0.85, 0.5) if after >= 50 else Color(0.8, 0.9, 1.0)))
		var act := Button.new()
		act.text = "激活 %s（%d 点）" % [String(d.get("name", id)), ACTIVATE_COST]
		act.disabled = Game.points < ACTIVATE_COST
		act.pressed.connect(_activate.bind(id))
		_skill_box.add_child(act)
		_skill_box.add_child(_section("D 级候选（激活后从中选 2 个）"))
		for node in Bloodlines.candidates(id, "D"):
			_skill_box.add_child(_hint("· %s —— %s" % [String(node["name"]), String(node["desc"])]))
		return

	var cands := Bloodlines.candidates(id, rank)
	var pick := Bloodlines.pick_count(rank)
	var picked: Array = _entry_of(id).get("picked", [])
	var count := 0
	for node in cands:
		if picked.has(String(node["id"])):
			count += 1
	_skill_box.add_child(_section("%s 级 · %d 选 %d（已选 %d）" % [rank, cands.size(), pick, count]))
	for node in cands:
		var nid := String(node["id"])
		var cb := CheckBox.new()
		cb.text = "%s［%s］—— %s" % [String(node["name"]), _type_name(String(node["type"])), String(node["desc"])]
		cb.button_pressed = picked.has(nid)
		cb.disabled = (not picked.has(nid)) and count >= pick
		cb.pressed.connect(_toggle_skill.bind(id, nid))
		_skill_box.add_child(cb)

	var idx := Bloodlines.RANKS.find(rank)
	if idx >= 0 and idx < Bloodlines.RANKS.size() - 1:
		var next_rank: String = Bloodlines.RANKS[idx + 1]
		var cost := Bloodlines.upgrade_cost(next_rank)
		var up := Button.new()
		up.text = "升级到 %s 级（%d 点）" % [next_rank, cost]
		up.disabled = Game.points < cost or count < pick
		up.pressed.connect(_upgrade.bind(id))
		_skill_box.add_child(up)
		var next_cands := Bloodlines.candidates(id, next_rank)
		_skill_box.add_child(_hint("%s 级将解锁 %d 个候选，可再选 %d 个。" % [next_rank, next_cands.size(), Bloodlines.pick_count(next_rank)]))
		if count < pick:
			_skill_box.add_child(_hint("需先选满 %s 级的 %d 个技能才能升级。" % [rank, pick], Color(1, 0.8, 0.4)))
	else:
		_skill_box.add_child(_section("已达最高评级 S"))

# ——— 操作 ———

## P3：调和手术 —— 花奖励点永久降低排斥。
func _do_tolerance_repair() -> void:
	if Game.player == null:
		return
	var cost := Game.player.tolerance_repair_cost()
	if cost <= 0:
		_toast_msg("没有可调和的负担（尚未拥有血脉）")
		return
	if Game.points < cost:
		_toast_msg("奖励点不足（需要 %d）" % cost)
		return
	Game.points -= cost
	Game.player.apply_tolerance_repair()
	_save()
	_toast_msg("调和手术完成：永久排斥减免 +20%%（当前共 %d%%）" % Game.player.bloodline_tolerance)
	_refresh()

func _select_blood(id: String) -> void:
	_selected_id = id
	_refresh()

func _toggle_skill(blood_id: String, node_id: String) -> void:
	var entry := _entry_of(blood_id)
	if entry.is_empty():
		return
	var rank := String(entry.get("rank", "D"))
	var picked: Array = entry.get("picked", [])
	if picked.has(node_id):
		picked.erase(node_id)
	else:
		var limit := Bloodlines.pick_count(rank)
		var count := 0
		for node in Bloodlines.candidates(blood_id, rank):
			if picked.has(String(node["id"])):
				count += 1
		if count >= limit:
			_toast_msg("%s 级最多选 %d 个技能" % [rank, limit])
			return
		picked.append(node_id)
	entry["picked"] = picked
	_save()
	_refresh()

func _activate(blood_id: String) -> void:
	if Game.player.has_bloodline(blood_id):
		return
	if Game.points < ACTIVATE_COST:
		_toast_msg("奖励点不足（需要 %d）" % ACTIVATE_COST)
		return
	Game.points -= ACTIVATE_COST
	Game.player.bloodlines.append({"id": blood_id, "rank": "D", "picked": []})
	_selected_id = blood_id
	_save()
	_toast_msg("已激活 %s（D 级），请从 D 级候选中选择 2 个技能" % Bloodlines.name_of(blood_id))
	_refresh()

func _upgrade(blood_id: String) -> void:
	var entry := _entry_of(blood_id)
	if entry.is_empty():
		return
	var rank := String(entry.get("rank", "D"))
	var idx := Bloodlines.RANKS.find(rank)
	if idx < 0 or idx >= Bloodlines.RANKS.size() - 1:
		return
	var pick := Bloodlines.pick_count(rank)
	var picked: Array = entry.get("picked", [])
	var count := 0
	for node in Bloodlines.candidates(blood_id, rank):
		if picked.has(String(node["id"])):
			count += 1
	if count < pick:
		_toast_msg("必须先选满 %s 级的 %d 个技能" % [rank, pick])
		return
	var next_rank: String = Bloodlines.RANKS[idx + 1]
	var cost := Bloodlines.upgrade_cost(next_rank)
	if Game.points < cost:
		_toast_msg("奖励点不足（需要 %d）" % cost)
		return
	Game.points -= cost
	entry["rank"] = next_rank
	_save()
	_toast_msg("%s 提升到 %s 级" % [Bloodlines.name_of(blood_id), next_rank])
	_refresh()

# ——— 工具 ———

func _entry_of(blood_id: String) -> Dictionary:
	for e in Game.player.bloodlines:
		if String(e.get("id", "")) == blood_id:
			return e
	return {}

## 若激活/升级该血统，排斥度会变成多少（兑换前预览）。
func _preview_rejection(blood_id: String, rank: String) -> int:
	var tmp: Array = []
	for e in Game.player.bloodlines:
		tmp.append({"id": String(e.get("id", "")), "rank": String(e.get("rank", "D"))})
	tmp.append({"id": blood_id, "rank": rank})
	return Bloodlines.rejection(tmp)

func _save() -> void:
	Game.save_game()
	EventBus.points_changed.emit(Game.points)

func _toast_msg(msg: String) -> void:
	if _toast != null:
		_toast.text = msg
		_toast_timer = 3.0

func _bar_row(title: String, value: int, maxv: int, col: Color, tier: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lb := Label.new()
	lb.text = title
	lb.custom_minimum_size = Vector2(72, 0)
	row.add_child(lb)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(380, 18)
	var back := ColorRect.new()
	back.color = Color(0.12, 0.12, 0.16)
	back.size = Vector2(380, 18)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(back)
	var ratio := clampf(float(value) / float(maxv), 0.0, 1.0)
	var fill := ColorRect.new()
	fill.color = col
	fill.size = Vector2(380.0 * ratio, 18)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	row.add_child(holder)
	var vl := Label.new()
	vl.text = "%d%%" % value
	vl.custom_minimum_size = Vector2(60, 0)
	row.add_child(vl)
	var tl := Label.new()
	tl.text = tier
	tl.modulate = col
	row.add_child(tl)
	return row

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	l.add_theme_font_size_override("font_size", 16)
	l.modulate = Color(1, 0.92, 0.7)
	return l

func _hint(text: String, col: Color = Color(0.85, 0.9, 1.0, 0.75)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = col
	return l

func _type_name(t: String) -> String:
	match t:
		"passive":
			return "被动"
		"active":
			return "主动"
		"attr":
			return "属性"
		"form":
			return "形态"
		"ultimate":
			return "终极"
	return t

func _rejection_tier_name(t: String) -> String:
	match t:
		"interference":
			return "血脉干扰"
		"unstable":
			return "⚠ 失控风险"
		"collapse":
			return "☠ 基因崩溃"
	return "相容"

func _synergy_tier_name(t: String) -> String:
	match t:
		"minor":
			return "微弱共鸣"
		"major":
			return "强力共鸣"
		"synergy":
			return "✦ 协同"
	return "无"
