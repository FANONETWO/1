extends Control
## 角色创建（分步向导）：01 基础资料 → 02 属性 → 03 技能 → 04 天赋 → 05 确认
##
## 为什么分步：一屏塞三栏太挤 —— 九个属性 + 十二个技能 + 五个天赋同屏时，
## 每行只能压到极限、说明文字只能塞进 tooltip。分步之后每一步都给足留白，
## 说明也重新回到画面上（悬停才看得到说明，等于没有说明）。
##
## ⚠️ 按钮文字不要改：测试与实机脚本按文字找按钮
##    「返回」「推荐配点」「独狼（奖励 ×1.5）」「四人小队（标准奖励）」「确认，进入主神空间」

const ATTR_POOL := 30
const SKILL_POOL := 20

# ——— 向导状态 ———
var _step := 0
var _steps := [
	["01", "基础资料", "代号与游戏模式"],
	["02", "属性", "九属性购点，阶梯价"],
	["03", "技能", "二十点技能点"],
	["04", "天赋", "选一个出身"],
	["05", "确认", "复核并进入主神空间"],
]
var _step_pages: Array[Control] = []
var _step_btns: Array[Button] = []
var _content_box: AkFrame
var _step_title: Label
var _prev_btn: Button
var _next_btn: Button
var _summary: RichTextLabel

# ——— 数据 ———
var _attrs: Dictionary = {}
var _skills: Dictionary = {}
var _attr_points_left := ATTR_POOL
var _skill_points_left := SKILL_POOL
var _talent := ""
var _mode: StringName = &"solo"
var _mode_btns: Dictionary = {}
var _mode_hint: Label

# ——— 控件引用（_refresh 会用到）———
var _name_edit: LineEdit
var _hint: Label
var _confirm: Button
var _attr_rows: Dictionary = {}    # attr_id -> {val, minus, plus, bar}
var _skill_rows: Dictionary = {}
var _attr_summary: Label
var _skill_summary: Label
var _talent_summary: Label

func _ready() -> void:
	theme = AkTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(AkBackdrop.new())

	# 顶栏
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
	head_rule.position = Vector2(60, 52)
	head_rule.size = Vector2(1160, 1)
	add_child(head_rule)

	# 左侧：步骤列表
	var side := VBoxContainer.new()
	side.position = Vector2(60, 78)
	side.custom_minimum_size = Vector2(250, 0)
	side.add_theme_constant_override("separation", 6)
	add_child(side)
	side.add_child(AkTheme.dim("步骤", AkTheme.FS_SMALL, AkTheme.TEXT_FAINT))
	for i in _steps.size():
		var b := Button.new()
		b.text = "%s　%s" % [_steps[i][0], _steps[i][1]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(250, 48)
		b.add_theme_font_size_override("font_size", AkTheme.FS_BODY)
		b.pressed.connect(_goto_step.bind(i))
		side.add_child(b)
		_step_btns.append(b)

	# 右侧：当前步骤内容（一次只做一件事）
	_content_box = AkFrame.new()
	_content_box.position = Vector2(336, 78)
	_content_box.size = Vector2(884, 500)
	_content_box.cut = 20.0
	_content_box.add_theme_constant_override("margin_left", 28)
	_content_box.add_theme_constant_override("margin_right", 28)
	_content_box.add_theme_constant_override("margin_top", 22)
	_content_box.add_theme_constant_override("margin_bottom", 22)
	add_child(_content_box)

	_build_basic_page()
	_build_attr_page()
	_build_skill_page()
	_build_talent_page()
	_build_summary_page()

	# 底部：左次要 / 右主行动
	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 60
	bottom.offset_right = -60
	bottom.offset_top = -68
	bottom.offset_bottom = -26
	bottom.add_theme_constant_override("separation", 10)
	add_child(bottom)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(110, 42)
	back.pressed.connect(func() -> void:
		AudioManager.play("ui_click")
		get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
	bottom.add_child(back)

	var rec := Button.new()
	rec.text = "推荐配点"
	rec.custom_minimum_size = Vector2(130, 42)
	rec.tooltip_text = "一键填入一套「丧尸副本生存向」的属性/技能/天赋，可直接开打"
	rec.pressed.connect(func() -> void:
		AudioManager.play("ui_confirm")
		_apply_recommended())
	bottom.add_child(rec)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)

	_prev_btn = Button.new()
	_prev_btn.text = "← 上一步"
	_prev_btn.custom_minimum_size = Vector2(120, 42)
	_prev_btn.pressed.connect(func() -> void: _goto_step(_step - 1))
	bottom.add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.text = "下一步 →"
	_next_btn.custom_minimum_size = Vector2(120, 42)
	_next_btn.pressed.connect(func() -> void: _goto_step(_step + 1))
	bottom.add_child(_next_btn)

	_confirm = Button.new()
	_confirm.text = "确认，进入主神空间"
	_confirm.custom_minimum_size = Vector2(260, 42)
	_confirm.add_theme_color_override("font_color", AkTheme.AMBER)
	_confirm.pressed.connect(_confirm_create)
	bottom.add_child(_confirm)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 60
	_hint.offset_right = -60
	_hint.offset_top = -22
	_hint.offset_bottom = -4
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.add_theme_font_size_override("font_size", 12)
	add_child(_hint)

	for a in Attrs.ALL:
		_attrs[a] = 1
	for s in Skills.ALL:
		_skills[s] = 0

	_apply_step()
	_refresh()

# ——— 向导骨架 ———

func _goto_step(i: int) -> void:
	var next := clampi(i, 0, _step_pages.size() - 1)
	if next == _step:
		return
	AudioManager.play("ui_click")
	_step = next
	_apply_step()

func _apply_step() -> void:
	for i in _step_pages.size():
		_step_pages[i].visible = (i == _step)
	for i in _step_btns.size():
		var on := (i == _step)
		_step_btns[i].button_pressed = on
		_step_btns[i].add_theme_color_override("font_color", AkTheme.AMBER if on else AkTheme.TEXT_DIM)
	if _step_title != null:
		# 右上角显示进度（分区标题里已经有「05 ｜ 确认」了，别再重复一遍）
		_step_title.text = "第 %d / %d 步" % [_step + 1, _step_pages.size()]
	if _prev_btn != null:
		_prev_btn.disabled = _step <= 0
	if _next_btn != null:
		_next_btn.disabled = _step >= _step_pages.size() - 1

## 造一个空白页（显隐切换，不销毁重建 —— 这样 _refresh 里的控件引用始终有效）
func _make_page() -> VBoxContainer:
	var p := VBoxContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 4
	p.offset_right = -4
	p.offset_top = 4
	p.offset_bottom = -4
	p.add_theme_constant_override("separation", 10)
	p.visible = false
	_content_box.add_child(p)
	_step_pages.append(p)
	return p

func _hline() -> ColorRect:
	var r := ColorRect.new()
	r.color = AkTheme.LINE
	r.custom_minimum_size = Vector2(0, 1)
	return r

## 带大数字与说明的分区头：左标题 + 右数值
func _page_head(index: String, name: String, en: String, right: Label) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(AkTheme.section(index, name, en))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(right)
	return head

# ——— 01 基础资料 ———

func _build_basic_page() -> void:
	var p := _make_page()

	var eyebrow := AkTheme.dim("先报个名字 —— 主神只认代号，不认你是谁。", AkTheme.FS_BODY, AkTheme.TEXT_DIM)
	p.add_child(eyebrow)

	var name_lb := AkTheme.dim("代号（必填）", AkTheme.FS_SMALL, AkTheme.ACCENT)
	p.add_child(name_lb)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "输入你的轮回者代号"
	_name_edit.tooltip_text = "必填；没填时下方「确认」按钮不会亮"
	_name_edit.custom_minimum_size = Vector2(0, 46)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_changed.connect(func(_t): _refresh())
	p.add_child(_name_edit)

	p.add_child(_hline())
	p.add_child(AkTheme.section("01", "游戏模式", "MODE"))
	_mode_hint = AkTheme.dim("", AkTheme.FS_BODY, AkTheme.TEXT_DIM)
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_mode_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for spec in [[Game.MODE_SOLO, "独狼（奖励 ×1.5）"], [Game.MODE_TEAM, "四人小队（标准奖励）"]]:
		var mb := Button.new()
		mb.text = String(spec[1])
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(280, 56)
		mb.add_theme_font_size_override("font_size", AkTheme.FS_BODY)
		mb.pressed.connect(_set_mode.bind(spec[0]))
		row.add_child(mb)
		_mode_btns[spec[0]] = mb
	p.add_child(row)

	var tail := AkTheme.dim("模式只影响出战人数与结算倍率，随时可以在主神空间重开新档。",
		AkTheme.FS_SMALL, AkTheme.TEXT_FAINT)
	p.add_child(tail)

# ——— 02 属性 ———

func _build_attr_page() -> void:
	var p := _make_page()
	_attr_summary = AkTheme.dim("剩余 %d 点" % ATTR_POOL, AkTheme.FS_H1, AkTheme.AMBER)
	p.add_child(_page_head("02", "属性", "ATTRIBUTES", _attr_summary))
	p.add_child(_hline())
	for a in Attrs.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, 44)
		var lb := Label.new()
		lb.text = Attrs.name_of(a)
		lb.custom_minimum_size = Vector2(66, 0)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 17)
		row.add_child(lb)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(34, 30)
		AkTheme.compact(minus)
		row.add_child(minus)
		var val := Label.new()
		val.text = "1"
		val.custom_minimum_size = Vector2(34, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 24)
		val.add_theme_color_override("font_color", AkTheme.AMBER)
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 30)
		AkTheme.compact(plus)
		row.add_child(plus)
		var bar := StatBar.new()
		bar.custom_minimum_size = Vector2(168, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		# 说明回到画面上（分步之后有空间了）
		var desc := AkTheme.dim(String(Attrs.DESC.get(a, "")), AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(desc)
		_attr_rows[a] = {"val": val, "minus": minus, "plus": plus, "bar": bar}
		minus.pressed.connect(_attr_change.bind(a, -1))
		plus.pressed.connect(_attr_change.bind(a, 1))
		p.add_child(row)

# ——— 03 技能 ———

func _build_skill_page() -> void:
	var p := _make_page()
	_skill_summary = AkTheme.dim("剩余 %d 点" % SKILL_POOL, AkTheme.FS_H1, AkTheme.ACCENT)
	p.add_child(_page_head("03", "技能", "SKILLS", _skill_summary))
	p.add_child(_hline())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 32)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	cols.add_child(right)

	var half := int(ceil(float(Skills.ALL.size()) / 2.0))
	for i in Skills.ALL.size():
		# Skills.ALL 的元素是 Variant，不能用 := 推断类型
		var s: String = String(Skills.ALL[i])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.custom_minimum_size = Vector2(0, 44)
		var lb := Label.new()
		lb.text = Skills.name_of(s)
		lb.custom_minimum_size = Vector2(62, 0)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 16)
		row.add_child(lb)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(34, 30)
		AkTheme.compact(minus)
		row.add_child(minus)
		var val := Label.new()
		val.text = "0"
		val.custom_minimum_size = Vector2(32, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 22)
		val.add_theme_color_override("font_color", AkTheme.ACCENT)
		row.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 30)
		AkTheme.compact(plus)
		row.add_child(plus)
		var bar := StatBar.new()
		bar.segments = 5
		bar.custom_minimum_size = Vector2(110, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_skill_rows[s] = {"val": val, "minus": minus, "plus": plus, "bar": bar}
		minus.pressed.connect(_skill_change.bind(s, -1))
		plus.pressed.connect(_skill_change.bind(s, 1))
		if i < half:
			left.add_child(row)
		else:
			right.add_child(row)

# ——— 04 天赋 ———

func _build_talent_page() -> void:
	var p := _make_page()
	_talent_summary = AkTheme.dim("未选择", AkTheme.FS_H1, AkTheme.TEXT_DIM)
	p.add_child(_page_head("04", "天赋", "TALENT", _talent_summary))
	p.add_child(_hline())
	for tid in Talents.ALL:
		var d: Dictionary = Talents.ALL[tid]
		var b := Button.new()
		# ⚠️ 按钮文字保持「【名称】说明」格式：测试与实机脚本按前缀找它
		b.text = "【%s】%s" % [d["name"], d["desc"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 62)
		b.add_theme_font_size_override("font_size", AkTheme.FS_BODY)
		b.pressed.connect(_on_talent_pressed.bind(String(tid)))
		p.add_child(b)

# ——— 05 确认 ———

func _build_summary_page() -> void:
	var p := _make_page()
	_step_title = AkTheme.dim("", AkTheme.FS_H2, AkTheme.TEXT_DIM)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(AkTheme.section("05", "确认", "CONFIRM"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_step_title)
	p.add_child(head)
	p.add_child(_hline())
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.add_theme_font_size_override("normal_font_size", 16)
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(_summary)

# ——— 段式数值条（方舟风：用格子而不是连续条）———

class StatBar extends Control:
	var value := 1
	var segments := 6

	func _ready() -> void:
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
		"（已无法再分配）" if (_attr_points_left > 0 and not _has_affordable_attr()) else ""]
	_attr_summary.add_theme_color_override("font_color", AkTheme.AMBER)
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
		_talent_summary.text = String(Talents.get_def(_talent).get("name", _talent))
		_talent_summary.add_theme_color_override("font_color", AkTheme.AMBER)
	else:
		_talent_summary.text = "未选择"
		_talent_summary.add_theme_color_override("font_color", AkTheme.TEXT_DIM)

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
	if _summary != null:
		_summary.text = _summary_text()
	_refresh_mode()

## 05 确认页的汇总文本
func _summary_text() -> String:
	var nm := _name_edit.text.strip_edges()
	var at: Array[String] = []
	for a in Attrs.ALL:
		at.append("%s %d" % [Attrs.name_of(a), int(_attrs[a])])
	var sk: Array[String] = []
	for s in Skills.ALL:
		if int(_skills[s]) > 0:
			sk.append("%s %d" % [Skills.name_of(s), int(_skills[s])])
	var tn := "（未选）" if _talent == "" else String(Talents.get_def(_talent).get("name", _talent))
	var mode_txt := "四人小队（标准奖励）" if _mode == Game.MODE_TEAM else "独狼（奖励 ×1.5）"
	if _mode == Game.MODE_TEAM:
		var names: Array[String] = []
		for preset in Allies.PRESETS:
			names.append(String(preset.get("name", "?")))
		mode_txt += "　队友：" + " / ".join(names)
	var out: Array[String] = []
	out.append("[color=#19c8ff]代号[/color]　%s" % ("（还没填）" if nm == "" else nm))
	out.append("[color=#19c8ff]模式[/color]　%s" % mode_txt)
	out.append("[color=#19c8ff]天赋[/color]　%s" % tn)
	out.append("")
	out.append("[color=#19c8ff]属性[/color]　" + "　".join(at))
	out.append("[color=#19c8ff]技能[/color]　" + ("、".join(sk) if not sk.is_empty() else "（未分配）"))
	out.append("")
	out.append("[color=#5a636b]确认无误后点右下角「确认，进入主神空间」。[/color]")
	return "\n".join(out)

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
	if _summary != null:
		_summary.text = _summary_text()

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
