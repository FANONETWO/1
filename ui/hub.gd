extends Control
## 主神空间：角色摘要 + 副本卡 + D 级兑换商店 + 存档。

const R001Content := preload("res://scenarios/r001_apartment/content.gd")

const SCENARIO_TITLE := "惊变公寓"
const SCENARIO_DESC := "深夜公寓，尸潮将起。\n主线：找到钥匙撤离。\n支线：救援、调查、清剿。\n评价与奖励取决于你带走多少真相与人性。"

var _pts_label: Label
var _char_label: RichTextLabel
var _store_vbox: VBoxContainer
var _best_label: Label

func _ready() -> void:
	theme = PixelTheme.build()
	AudioManager.play_bgm("hub")
	if Game.player == null:
		get_tree().change_scene_to_file.call_deferred("res://ui/main_menu.tscn")
		return
	_build()
	_refresh()
	EventBus.points_changed.connect(func(_p): _refresh())

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "主 神 空 间"
	title.add_theme_font_size_override("font_size", 32)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 16
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_pts_label = Label.new()
	_pts_label.add_theme_font_size_override("font_size", 18)
	_pts_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pts_label.offset_top = 62
	_pts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pts_label)

	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 50
	cols.offset_right = -50
	cols.offset_top = 96
	cols.offset_bottom = -64
	cols.add_theme_constant_override("separation", 24)
	add_child(cols)

	# 左：角色
	cols.add_child(_build_char_col())
	# 中：副本
	cols.add_child(_build_scenario_col())
	# 右：商店（滚动）
	cols.add_child(_build_store_col())

	# 底部
	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 50
	bottom.offset_right = -50
	bottom.offset_bottom = -12
	bottom.offset_top = -50
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)
	var back := Button.new()
	back.text = "返回标题"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
	bottom.add_child(back)
	var blast := Button.new()
	blast.text = "血统"
	blast.pressed.connect(_open_bloodlines)
	bottom.add_child(blast)
	var reset := Button.new()
	reset.text = "重置存档"
	reset.pressed.connect(_confirm_reset)
	bottom.add_child(reset)
	var enter := Button.new()
	enter.text = "进入副本：惊变公寓"
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.pressed.connect(_enter_scenario)
	bottom.add_child(enter)

func _open_bloodlines() -> void:
	var panel := BloodlinePanel.new()
	add_child(panel)
	panel.closed.connect(func() -> void:
		panel.queue_free()
		_refresh()
	)

func _build_char_col() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := Label.new()
	t.text = "轮回者档案"
	t.add_theme_font_size_override("font_size", 20)
	v.add_child(t)
	_char_label = RichTextLabel.new()
	_char_label.bbcode_enabled = true
	_char_label.fit_content = true
	_char_label.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(_char_label)
	var info := Label.new()
	info.text = "提示：基因锁在生命 ≤30% 时自动觉醒。\n首次生命归零会『绝境爆种』一次。"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.modulate = Color(1, 1, 1, 0.5)
	info.add_theme_font_size_override("font_size", 12)
	v.add_child(info)
	return panel

func _build_scenario_col() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := Label.new()
	t.text = "待派发影片"
	t.add_theme_font_size_override("font_size", 20)
	v.add_child(t)
	var card := Label.new()
	card.text = "【%s】" % SCENARIO_TITLE
	card.add_theme_font_size_override("font_size", 24)
	v.add_child(card)
	var desc := Label.new()
	desc.text = SCENARIO_DESC
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(1, 1, 1, 0.75)
	v.add_child(desc)
	var best := Label.new()
	best.name = "BestEnding"
	best.modulate = Color(1, 0.85, 0.4)
	_best_label = best
	v.add_child(best)
	var hint := Label.new()
	hint.text = "评价：\n【完美撤离】撤离+救陈叔+清尸王+线索≥3\n【惊险撤离】活着离开\n【陨落】任务失败"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.add_theme_font_size_override("font_size", 12)
	v.add_child(hint)
	return panel

func _build_store_col() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var t := Label.new()
	t.text = "D 级兑换（奖励点）"
	t.add_theme_font_size_override("font_size", 20)
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_store_vbox = VBoxContainer.new()
	_store_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(_store_vbox)
	return panel

func _refresh() -> void:
	var p := Game.player
	_pts_label.text = "奖励点：%d" % Game.points
	var lines: Array[String] = []
	lines.append("[b]%s[/b]　%s" % [p.name, Talents.get_def(p.talent_id).get("name", "")])
	lines.append("生命 %d/%d　意志 %d/%d" % [p.hp, p.max_hp(), p.will, p.max_will()])
	var at: Array[String] = []
	for a in Attrs.ALL:
		at.append("%s%d" % [Attrs.name_of(a), p.attr(a)])
	lines.append("[color=#9ecbff]" + "　".join(at) + "[/color]")
	var sk: Array[String] = []
	for s in Skills.ALL:
		if p.skill(s) > 0:
			sk.append("%s%d" % [Skills.name_of(s), p.skill(s)])
	lines.append("技能：" + ("、".join(sk) if not sk.is_empty() else "无"))
	var inv: Array[String] = []
	for it in p.inventory:
		inv.append(Items.name_of(it))
	lines.append("背包：%s" % ("、".join(inv) if not inv.is_empty() else "空"))
	lines.append("武器：%s　护甲：%s" % [Items.name_of(p.weapon) if p.weapon != "" else "无", Items.name_of(p.armor) if p.armor != "" else "无"])
	if p.gene_lock_level >= 1:
		lines.append("[color=#ff7a5e]基因锁 · 一阶（已觉醒）[/color]")
	# 游戏模式与队伍（团队模式的队友在这里露脸）
	var mode_txt := "[color=#ffd75e]模式：%s[/color]" % Game.mode_name()
	if not Game.is_team():
		mode_txt += "　[color=#ffb3b3]奖励 ×%.1f（风险溢价）[/color]" % Game.reward_multiplier()
	lines.append(mode_txt)
	var mates := Game.allies()
	if mates.is_empty():
		lines.append("[color=#9fe3ff]队伍：独狼[/color]")
	else:
		lines.append("[color=#9fe3ff]队伍（%d 人）[/color]" % (mates.size() + 1))
		for a in mates:
			var mc: Character = a
			lines.append("　· %s　生命 %d/%d　速度 %d" % [
				mc.name, mc.hp, mc.max_hp(), mc.attr("dex") + int(mc.attr("com") / 2) + 2])
	_char_label.text = "\n".join(lines)

	if _best_label:
		var sid := "r001_apartment"
		# 成绩按模式分开看：独狼的 ×1.5 不会污染团队榜
		var eid := Game.best_ending_of_mode(sid)
		if eid != "":
			_best_label.text = "最佳评价（%s）：%s" % [Game.mode_name(), String(R001Content.ENDING_NAMES.get(eid, eid))]
		else:
			_best_label.text = "尚未通关（%s）" % Game.mode_name()

	# 商店重建
	for c in _store_vbox.get_children():
		c.queue_free()
	_store_vbox.add_child(_section_label("属性强化（+1）"))
	for a in Attrs.ALL:
		var cost := Upgrades.attr_cost(p.attr(a))
		var b := Button.new()
		b.text = "%s %d → %d　（%d 分）" % [Attrs.name_of(a), p.attr(a), p.attr(a) + 1, cost]
		b.disabled = p.attr(a) >= 6 or Game.points < cost
		b.pressed.connect(_buy_attr.bind(a, cost))
		_store_vbox.add_child(b)
	_store_vbox.add_child(_section_label("技能强化（+1）"))
	for s in Skills.ALL:
		var cost := Upgrades.skill_cost(p.skill(s))
		var b := Button.new()
		b.text = "%s %d → %d　（%d 分）" % [Skills.name_of(s), p.skill(s), p.skill(s) + 1, cost]
		b.disabled = p.skill(s) >= 5 or Game.points < cost
		b.pressed.connect(_buy_skill.bind(s, cost))
		_store_vbox.add_child(b)
	_store_vbox.add_child(_section_label("装备与补给"))
	for item in Upgrades.ITEMS_FOR_SALE:
		var iid := String(item["id"])
		var cost := int(item["cost"])
		var d: Dictionary = Items.get_def(iid)
		var own := iid in p.inventory or p.weapon == iid or p.armor == iid
		var b := Button.new()
		b.text = "%s　（%d 分）%s" % [String(d.get("name", iid)), cost, "— 已拥有" if own else ""]
		b.disabled = own or Game.points < cost
		b.pressed.connect(_buy_item.bind(iid, cost))
		_store_vbox.add_child(b)

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = "— " + text + " —"
	l.modulate = Color(1, 0.9, 0.6)
	l.add_theme_font_size_override("font_size", 14)
	return l

func _buy_attr(a: String, cost: int) -> void:
	if Game.points < cost:
		return
	Game.points -= cost
	# 只加基础值：attr() 含血统属性加成，直接回写会把加成重复烘进基础属性且不可逆
	Game.player.attrs[a] = int(Game.player.attrs.get(a, 1)) + 1
	Game.player.refresh()
	Game.save_game()
	_refresh()

func _buy_skill(s: String, cost: int) -> void:
	if Game.points < cost:
		return
	Game.points -= cost
	Game.player.skills[s] = Game.player.skill(s) + 1
	Game.save_game()
	_refresh()

func _buy_item(iid: String, cost: int) -> void:
	if Game.points < cost:
		return
	Game.points -= cost
	var d: Dictionary = Items.get_def(iid)
	match String(d.get("kind", "")):
		"weapon":
			Game.player.weapon = iid
		"armor":
			Game.player.armor = iid
		_:
			Game.player.inventory.append(iid)
	Game.save_game()
	_refresh()

func _enter_scenario() -> void:
	Game.pending_scenario_id = &"r001_apartment"
	Game.scenario_state = {}
	get_tree().change_scene_to_file("res://scenarios/r001_apartment/scenario.tscn")

func _confirm_reset() -> void:
	if has_meta("reset_armed"):
		remove_meta("reset_armed")
		Game.new_game()
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	else:
		set_meta("reset_armed", true)
		_pts_label.text = "奖励点：%d　（再点一次「重置存档」确认）" % Game.points
