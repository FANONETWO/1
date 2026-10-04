extends Control
## 角色创建：姓名 + 九属性购点 + 技能分配 + 天赋选择。

const ATTR_POOL := 30
const SKILL_POOL := 20

var _attrs: Dictionary = {}
var _skills: Dictionary = {}
var _talent := ""
var _attr_points_left := ATTR_POOL
var _skill_points_left := SKILL_POOL
var _attr_rows: Dictionary = {}   # attr_id -> {val, minus, plus}
var _skill_rows: Dictionary = {}
var _name_edit: LineEdit
var _attr_summary: Label
var _skill_summary: Label
var _talent_summary: Label
var _confirm: Button
var _hint: Label                  # 底部状态说明：告诉玩家确认按钮为什么是灰的（E1）
var _mode: StringName = &"solo"   # 游戏模式：solo / team
var _mode_btns: Dictionary = {}   # mode -> Button
var _mode_hint: Label

func _ready() -> void:
	theme = AkTheme.build()
	AudioManager.play_bgm("hub")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 背景：细网格 + 斜向色带（方舟式）
	add_child(AkBackdrop.new())

	# 顶部标题栏：编号 ─ 名称 + 英文标注
	var head := HBoxContainer.new()
	head.position = Vector2(60, 14)
	head.add_theme_constant_override("separation", 12)
	add_child(head)
	head.add_child(AkTheme.dim("01", 26, AkTheme.ACCENT))
	var head_bar := ColorRect.new()
	head_bar.color = AkTheme.ACCENT
	head_bar.custom_minimum_size = Vector2(3, 24)
	head_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(head_bar)
	head.add_child(AkTheme.title("角色创建", 26))
	var head_en := AkTheme.dim(AkTheme.spaced("OPERATOR REGISTRATION", 1), AkTheme.FS_TINY, AkTheme.TEXT_FAINT)
	head_en.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(head_en)

	var head_rule := ColorRect.new()
	head_rule.color = AkTheme.LINE
	head_rule.position = Vector2(60, 48)
	head_rule.size = Vector2(1160, 1)
	add_child(head_rule)
	for a in Attrs.ALL:
		_attrs[a] = 1
	for s in Skills.ALL:
		_skills[s] = 0

	# 代号：方舟式「标签 + 输入框」，左对齐（不居中）
	var name_row := HBoxContainer.new()
	name_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_row.offset_left = 60
	name_row.offset_right = -60
	name_row.offset_top = 60
	name_row.add_theme_constant_override("separation", 12)
	add_child(name_row)
	var name_lb := AkTheme.dim("代号", AkTheme.FS_SMALL, AkTheme.ACCENT)
	name_lb.custom_minimum_size = Vector2(52, 0)
	name_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(name_lb)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "必填 —— 输入你的轮回者代号"
	_name_edit.tooltip_text = "代号是必填项；没填时下方「确认」按钮不会亮"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(_t): _refresh())
	name_row.add_child(_name_edit)

	# 三栏：属性 / 技能 / 天赋
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 60
	cols.offset_right = -60
	cols.offset_top = 102
	cols.offset_bottom = -136
	cols.add_theme_constant_override("separation", 16)
	add_child(cols)

	cols.add_child(_build_attr_col())
	cols.add_child(_build_skill_col())
	cols.add_child(_build_talent_col())

	# 底部按钮
	# 底部按钮：左对齐（方舟风），确认键用琥珀色字并靠右
	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 60
	bottom.offset_right = -60
	bottom.offset_bottom = -24
	bottom.offset_top = -66
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)

	# 游戏模式：独狼（风险溢价 ×1.5）／ 四人小队（带 3 名预设队友，标准奖励）
	var mode_row := HBoxContainer.new()
	mode_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mode_row.offset_left = 60
	mode_row.offset_right = -60
	mode_row.offset_top = -126
	mode_row.offset_bottom = -94
	mode_row.add_theme_constant_override("separation", 12)
	add_child(mode_row)
	mode_row.add_child(AkTheme.dim("模式", AkTheme.FS_SMALL, AkTheme.ACCENT))
	var mode_rule := ColorRect.new()
	mode_rule.color = AkTheme.LINE
	mode_rule.custom_minimum_size = Vector2(1, 20)
	mode_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(mode_rule)
	for spec in [[Game.MODE_SOLO, "独狼（奖励 ×1.5）"], [Game.MODE_TEAM, "四人小队（标准奖励）"]]:
		var mb := Button.new()
		mb.text = String(spec[1])
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(216, 34)
		mb.pressed.connect(_set_mode.bind(spec[0]))
		mode_row.add_child(mb)
		_mode_btns[spec[0]] = mb
	_mode_hint = Label.new()
	_mode_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_mode_hint.offset_left = 60
	_mode_hint.offset_right = -60
	_mode_hint.offset_top = -90
	_mode_hint.offset_bottom = -72
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.add_theme_font_size_override("font_size", 13)
	_mode_hint.modulate = Color(1, 1, 1, 0.72)
	add_child(_mode_hint)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(120, 42)
	back.pressed.connect(func() -> void:
		AudioManager.play("ui_click")
		get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
	bottom.add_child(back)
	var rec := Button.new()
	rec.text = "推荐配点"
	rec.tooltip_text = "一键填入一套「丧尸副本生存向」的属性/技能/天赋，可直接开打"
	rec.pressed.connect(func() -> void:
		AudioManager.play("ui_confirm")
		_apply_recommended())
	rec.custom_minimum_size = Vector2(140, 42)
	bottom.add_child(rec)
	# 右侧留白，让「确认」这个主行动靠右（方舟的确认键永远在右边）
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	_confirm = Button.new()
	_confirm.text = "确认，进入主神空间"
	_confirm.custom_minimum_size = Vector2(280, 42)
	_confirm.add_theme_color_override("font_color", AkTheme.AMBER)
	_confirm.pressed.connect(_confirm_create)
	bottom.add_child(_confirm)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -28
	_hint.offset_bottom = -8
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", AkTheme.OK)
	add_child(_hint)

	_refresh()

# ——— 三栏构建 ———

func _build_attr_col() -> Control:
	var panel := AkFrame.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.cut = 18.0
	panel.add_theme_constant_override("margin_left", 18)
	panel.add_theme_constant_override("margin_right", 18)
	panel.add_theme_constant_override("margin_top", 16)
	panel.add_theme_constant_override("margin_bottom", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	v.add_child(AkTheme.section("01", "属性", "ATTRIBUTES"))
	_attr_summary = AkTheme.dim("购点 %d" % ATTR_POOL, AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
	v.add_child(_attr_summary)
	var rule := ColorRect.new()
	rule.color = AkTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	for a in Attrs.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# 属性说明不再挤在行尾 —— 移进 tooltip，界面立刻干净
		var desc := String(Attrs.DESC.get(a, ""))
		var lb := Label.new()
		lb.text = "%s" % Attrs.name_of(a)
		lb.custom_minimum_size = Vector2(52, 0)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.tooltip_text = desc
		row.add_child(lb)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(30, 24)
		minus.tooltip_text = desc
		AkTheme.compact(minus)
		row.add_child(minus)
		var val := Label.new()
		val.text = "1"
		val.custom_minimum_size = Vector2(26, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 20)
		val.add_theme_color_override("font_color", AkTheme.AMBER)
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(30, 24)
		plus.tooltip_text = desc
		AkTheme.compact(plus)
		row.add_child(plus)
		var bar := StatBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_attr_rows[a] = {"val": val, "minus": minus, "plus": plus, "bar": bar}
		minus.pressed.connect(_attr_change.bind(a, -1))
		plus.pressed.connect(_attr_change.bind(a, 1))
		v.add_child(row)
	return panel

func _build_skill_col() -> Control:
	var panel := AkFrame.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.cut = 18.0
	panel.add_theme_constant_override("margin_left", 18)
	panel.add_theme_constant_override("margin_right", 18)
	panel.add_theme_constant_override("margin_top", 16)
	panel.add_theme_constant_override("margin_bottom", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	v.add_child(AkTheme.section("02", "技能", "SKILLS"))
	_skill_summary = AkTheme.dim("点数 %d" % SKILL_POOL, AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
	v.add_child(_skill_summary)
	var rule := ColorRect.new()
	rule.color = AkTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	for s in Skills.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lb := Label.new()
		lb.text = "%s" % Skills.name_of(s)
		lb.custom_minimum_size = Vector2(52, 0)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lb)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(30, 24)
		AkTheme.compact(minus)
		row.add_child(minus)
		var val := Label.new()
		val.text = "0"
		val.custom_minimum_size = Vector2(26, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 20)
		val.add_theme_color_override("font_color", AkTheme.ACCENT)
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(30, 24)
		AkTheme.compact(plus)
		row.add_child(plus)
		var bar := StatBar.new()
		bar.segments = 5
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_skill_rows[s] = {"val": val, "minus": minus, "plus": plus, "bar": bar}
		minus.pressed.connect(_skill_change.bind(s, -1))
		plus.pressed.connect(_skill_change.bind(s, 1))
		v.add_child(row)
	return panel

func _build_talent_col() -> Control:
	var panel := AkFrame.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.cut = 18.0
	panel.add_theme_constant_override("margin_left", 18)
	panel.add_theme_constant_override("margin_right", 18)
	panel.add_theme_constant_override("margin_top", 16)
	panel.add_theme_constant_override("margin_bottom", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(AkTheme.section("03", "天赋", "TALENT"))
	_talent_summary = AkTheme.dim("未选择", AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
	_talent_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_talent_summary)
	var rule := ColorRect.new()
	rule.color = AkTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	for tid in Talents.ALL:
		var d: Dictionary = Talents.ALL[tid]
		var b := Button.new()
		# ⚠️ 按钮文字保持「【名称】说明」格式：测试与实机脚本按前缀找它
		b.text = "【%s】%s" % [d["name"], d["desc"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", AkTheme.FS_SMALL)
		b.pressed.connect(_on_talent_pressed.bind(String(tid)))
		v.add_child(b)
	return panel

## 段式数值条（方舟风：用格子而不是连续条；属性 6 段、技能 5 段）
class StatBar extends Control:
	var value := 1
	var segments := 6

	func _ready() -> void:
		custom_minimum_size = Vector2(56, 8)
		resized.connect(queue_redraw)

	func set_stat(v: int) -> void:
		value = v
		queue_redraw()

	func _draw() -> void:
		if size.x <= 2.0:
			return
		var seg := size.x / float(maxi(1, segments))
		for i in segments:
			var filled := i < value
			draw_rect(Rect2(float(i) * seg + 1.0, 0.0, maxf(1.0, seg - 2.0), size.y),
				AkTheme.ACCENT if filled else Color(1, 1, 1, 0.07))

# ——— 增减逻辑 ———

func _attr_cost(from: int, to: int) -> int:
	# 升到 to 的成本 = from+1 + ... + to（对应规则书 当前值×1XP）
	var cost := 0
	for v in range(from + 1, to + 1):
		cost += v
	return cost

func _attr_change(a: String, delta: int) -> void:
	var cur := int(_attrs[a])
	var next := cur + delta
	if next < 1 or next > 6:
		return
	if delta > 0:
		var cost := _attr_cost(cur, next)
		if _attr_points_left < cost:
			return
		_attr_points_left -= cost
	else:
		var refund := _attr_cost(next, cur)
		_attr_points_left += refund
	_attrs[a] = next
	_refresh()

func _skill_change(s: String, delta: int) -> void:
	var cur := int(_skills[s])
	var next := cur + delta
	if next < 0 or next > 5:
		return
	if delta > 0:
		if _skill_points_left < 1:
			return
		_skill_points_left -= 1
	else:
		_skill_points_left += 1
	_skills[s] = next
	_refresh()

## 天赋按钮点击（单独一个函数是为了能把 tid 用 bind 传进来，避免 lambda 捕获循环变量的坑）
func _on_talent_pressed(tid: String) -> void:
	AudioManager.play("ui_click")
	_select_talent(tid)

func _select_talent(tid: String) -> void:
	_talent = tid
	_refresh()

# ——— 刷新与确认 ———

func _refresh() -> void:
	for a in _attr_rows:
		var row: Dictionary = _attr_rows[a]
		row["val"].text = str(_attrs[a])
		var v := int(_attrs[a])
		var step := _attr_cost(v, v + 1)
		row["minus"].disabled = v <= 1
		row["plus"].disabled = v >= 6 or step > _attr_points_left
		if row.has("bar"):
			row["bar"].set_stat(v)
		# E3：置灰要给出原因，否则玩家只能瞎猜（悬停即可看到）
		row["minus"].tooltip_text = "已是最低值 1" if v <= 1 else "降 1 级，退还 %d 点" % _attr_cost(v - 1, v)
		if v >= 6:
			row["plus"].tooltip_text = "已是人类上限 6"
		elif step > _attr_points_left:
			row["plus"].tooltip_text = "点数不够：升到 %d 需要 %d 点，你只剩 %d 点" % [v + 1, step, _attr_points_left]
		else:
			row["plus"].tooltip_text = "花 %d 点升到 %d（阶梯价）" % [step, v + 1]
	_attr_summary.text = "剩余 %d 点%s" % [_attr_points_left,
		"（已无法再分配，可直接确认）" if (_attr_points_left > 0 and not _has_affordable_attr()) else ""]
	for s in _skill_rows:
		var row: Dictionary = _skill_rows[s]
		row["val"].text = str(_skills[s])
		var lv := int(_skills[s])
		row["minus"].disabled = lv <= 0
		row["plus"].disabled = lv >= 5 or _skill_points_left < 1
		if row.has("bar"):
			row["bar"].set_stat(lv)
		row["minus"].tooltip_text = "已是最低 0 级" if lv <= 0 else "降 1 级，退还 1 点"
		if lv >= 5:
			row["plus"].tooltip_text = "已是本切片上限 5 级"
		elif _skill_points_left < 1:
			row["plus"].tooltip_text = "技能点已用完"
		else:
			row["plus"].tooltip_text = "花 1 点升到 %d 级" % (lv + 1)
	_skill_summary.text = "剩余 %d 点" % _skill_points_left
	if _talent != "":
		_talent_summary.text = "已选：%s" % String(Talents.get_def(_talent).get("name", _talent))
	else:
		_talent_summary.text = "未选择"
	# 属性购点是**阶梯价**（1→2 花 1 点，2→3 花 2 点…），所以可能剩下买不起任何一级的零头。
	# 旧条件要求「点数必须花到 0」，于是剩 1 点时所有「+」都灰着、确认按钮也灰着 —— 玩家永久卡死。
	# E1：这里把「为什么不能确认」直接写成一句话，玩家不用猜。
	var blocking: Array[String] = []
	if _name_edit.text.strip_edges() == "":
		blocking.append("代号（必填）")
	if _talent == "":
		blocking.append("天赋（选一个出身）")
	if _has_affordable_attr():
		blocking.append("属性点还能再分配（还剩 %d 点）" % _attr_points_left)
	if _hint != null:
		if blocking.is_empty():
			var tail := ""
			if _skill_points_left > 0:
				tail = "　（技能点还剩 %d，可以现在花掉，也可以留到主神空间）" % _skill_points_left
			_hint.text = "一切就绪 —— 可以「确认，进入主神空间」了。" + tail
			_hint.modulate = Color(0.62, 1.0, 0.72)
		else:
			_hint.text = "还不能确认，请先补完：" + "、".join(blocking)
			_hint.modulate = Color(1.0, 0.78, 0.42)
	_confirm.disabled = not blocking.is_empty()
	_confirm.tooltip_text = "" if blocking.is_empty() else _hint.text
	_refresh_mode()

## 是否还有买得起的属性提升
func _has_affordable_attr() -> bool:
	if _attr_points_left <= 0:
		return false
	for a in _attr_rows:
		var v := int(_attrs[a])
		if v < 6 and _attr_cost(v, v + 1) <= _attr_points_left:
			return true
	return false

## E2：一键推荐配点 —— 「丧尸副本生存向」，属性恰好花完 30 点、技能恰好花完 20 点
## （耐力 4 → 生命 24；敏捷 3 → 移动力 4；感知 3 → 暴击 15%；白刃/躲藏/调查 各 3）
const RECOMMENDED_ATTRS := {
	"str": 3, "dex": 3, "end": 4, "int": 1, "per": 3,
	"res": 2, "pre": 2, "man": 1, "com": 2,
}
const RECOMMENDED_SKILLS := {
	"brawl": 1, "blade": 3, "gun": 2, "hide": 3, "survive": 2,
	"investigate": 3, "medicine": 2, "empathy": 2, "socialize": 1, "intimidate": 1,
}
const RECOMMENDED_TALENT := "survivor"

func _attrs_cost_total() -> int:
	var total := 0
	for a in _attrs:
		total += _attr_cost(1, int(_attrs[a]))
	return total

func _skills_total() -> int:
	var total := 0
	for s in _skills:
		total += int(_skills[s])
	return total

func _apply_recommended() -> void:
	for a in Attrs.ALL:
		_attrs[a] = int(RECOMMENDED_ATTRS.get(a, 1))
	_attr_points_left = ATTR_POOL - _attrs_cost_total()
	for s in Skills.ALL:
		_skills[s] = int(RECOMMENDED_SKILLS.get(s, 0))
	_skill_points_left = SKILL_POOL - _skills_total()
	if _talent == "":
		_talent = RECOMMENDED_TALENT
	if _name_edit.text.strip_edges() == "":
		_name_edit.text = "幸存者"
	_refresh()

# ——— 游戏模式 ———

func _set_mode(m: StringName) -> void:
	_mode = Game.MODE_TEAM if m == Game.MODE_TEAM else Game.MODE_SOLO
	_refresh_mode()

func _refresh_mode() -> void:
	for k in _mode_btns:
		(_mode_btns[k] as Button).button_pressed = (StringName(k) == _mode)
	if _mode_hint == null:
		return
	if _mode == Game.MODE_TEAM:
		_mode_hint.text = "四人小队：带 3 名预设队友（铁闸 / 快刀 / 药箱），奖励标准。\n他们速度各不相同 —— 战斗的行动条上你会看到四个人的出手顺序交错。"
	else:
		_mode_hint.text = "独狼：一个人下副本，奖励点 ×1.5（风险溢价 —— 没人替你分摊风险、没人来救你）。"

func _confirm_create() -> void:
	var c := Character.create_default()
	c.name = _name_edit.text.strip_edges()
	for a in _attrs:
		c.attrs[a] = int(_attrs[a])
	for s in _skills:
		c.skills[s] = int(_skills[s])
	c.talent_id = _talent
	# 天赋技能加成
	var td: Dictionary = Talents.get_def(_talent)
	for sid in td.get("skills", {}):
		c.skills[String(sid)] = int(c.skills.get(String(sid), 0)) + int(td["skills"][String(sid)])
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	Game.set_mode(_mode)
	# 团队模式：带 3 名预设队友（铁闸 / 快刀 / 药箱）；独狼：清空队伍
	Game.set_team(Allies.make_allies(3) if _mode == Game.MODE_TEAM else [])
	Game.go_hub()
