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
var _hint: Label          # 底部状态说明：告诉玩家确认按钮为什么是灰的（E1）

func _ready() -> void:
	theme = PixelTheme.build()
	AudioManager.play_bgm("hub")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "建立轮回者"
	title.add_theme_font_size_override("font_size", 30)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 18
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	for a in Attrs.ALL:
		_attrs[a] = 1
	for s in Skills.ALL:
		_skills[s] = 0

	# 名字
	var name_row := HBoxContainer.new()
	name_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_row.offset_left = 200
	name_row.offset_right = -200
	name_row.offset_top = 64
	name_row.add_theme_constant_override("separation", 10)
	add_child(name_row)
	var name_lb := Label.new()
	name_lb.text = "代号： *"
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
	cols.offset_top = 104
	cols.offset_bottom = -70
	cols.add_theme_constant_override("separation", 24)
	add_child(cols)

	cols.add_child(_build_attr_col())
	cols.add_child(_build_skill_col())
	cols.add_child(_build_talent_col())

	# 底部按钮
	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 200
	bottom.offset_right = -200
	bottom.offset_bottom = -14
	bottom.offset_top = -56
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 20)
	add_child(bottom)
	var back := Button.new()
	back.text = "返回"
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
	bottom.add_child(rec)
	_confirm = Button.new()
	_confirm.text = "确认，进入主神空间"
	_confirm.pressed.connect(_confirm_create)
	bottom.add_child(_confirm)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -50
	_hint.offset_bottom = -26
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	add_child(_hint)

	_refresh()

# ——— 三栏构建 ———

func _build_attr_col() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var t := Label.new()
	t.text = "属性（购点 %d）" % ATTR_POOL
	t.add_theme_font_size_override("font_size", 18)
	v.add_child(t)
	_attr_summary = Label.new()
	_attr_summary.modulate = Color(1, 1, 1, 0.7)
	_attr_summary.add_theme_font_size_override("font_size", 13)
	v.add_child(_attr_summary)
	for a in Attrs.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lb := Label.new()
		lb.text = "%s" % Attrs.name_of(a)
		lb.custom_minimum_size = Vector2(56, 0)
		row.add_child(lb)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(34, 28)
		row.add_child(minus)
		var val := Label.new()
		val.text = "1"
		val.custom_minimum_size = Vector2(32, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 20)
		val.modulate = Color(1.0, 0.88, 0.45)   # 关键数值用暖色强调
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 28)
		row.add_child(plus)
		var hint := Label.new()
		hint.text = Attrs.DESC.get(a, "")
		hint.modulate = Color(1, 1, 1, 0.68)
		hint.add_theme_font_size_override("font_size", 11)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
		_attr_rows[a] = {"val": val, "minus": minus, "plus": plus}
		minus.pressed.connect(_attr_change.bind(a, -1))
		plus.pressed.connect(_attr_change.bind(a, 1))
		v.add_child(row)
	return panel

func _build_skill_col() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	var t := Label.new()
	t.text = "技能（点数 %d）" % SKILL_POOL
	t.add_theme_font_size_override("font_size", 18)
	v.add_child(t)
	_skill_summary = Label.new()
	_skill_summary.modulate = Color(1, 1, 1, 0.7)
	_skill_summary.add_theme_font_size_override("font_size", 13)
	v.add_child(_skill_summary)
	for s in Skills.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lb := Label.new()
		lb.text = "%s" % Skills.name_of(s)
		lb.custom_minimum_size = Vector2(60, 0)
		row.add_child(lb)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(30, 26)
		row.add_child(minus)
		var val := Label.new()
		val.text = "0"
		val.custom_minimum_size = Vector2(26, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 18)
		val.modulate = Color(0.75, 0.92, 1.0)   # 技能等级用冷色强调
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(30, 26)
		row.add_child(plus)
		_skill_rows[s] = {"val": val, "minus": minus, "plus": plus}
		minus.pressed.connect(_skill_change.bind(s, -1))
		plus.pressed.connect(_skill_change.bind(s, 1))
		v.add_child(row)
	return panel

func _build_talent_col() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var t := Label.new()
	t.text = "天赋（出身）"
	t.add_theme_font_size_override("font_size", 18)
	v.add_child(t)
	_talent_summary = Label.new()
	_talent_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talent_summary.modulate = Color(1, 1, 1, 0.7)
	_talent_summary.add_theme_font_size_override("font_size", 13)
	v.add_child(_talent_summary)
	for tid in Talents.ALL:
		var d: Dictionary = Talents.ALL[tid]
		var b := Button.new()
		b.text = "【%s】%s" % [d["name"], d["desc"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 46)
		b.pressed.connect(_on_talent_pressed.bind(String(tid)))
		v.add_child(b)
	return panel

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
	Game.go_hub()
