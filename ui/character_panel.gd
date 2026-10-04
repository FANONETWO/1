class_name CharacterPanel
extends Control
## 角色检视界面（Baldur's Gate 3 式三栏）。
##
##   左栏：立绘 + 身份（名字 / 天赋 / 血统 / 基因锁）
##   中栏：九属性（每项标注它在战棋里的出口）+ 派生面板（生命/暴击/移动/指挥点/光环/威慑/首击减伤）
##   右栏：装备（武器 / 护甲）+ 背包（点击即装备或使用）
##
## 数据源：Character + Attrs（名称与出口说明）+ Items（物品定义）。
## 入口：探索场景按 C，或点「角色」按钮。

signal closed

const PANEL_BG := Color(0.055, 0.065, 0.095, 1.0)
const CARD_BG := Color(0.10, 0.115, 0.155, 0.92)
const LINE := Color(0.30, 0.36, 0.48, 0.85)
const ACCENT := Color(0.62, 0.79, 1.0)
const GOLD := Color(1.0, 0.84, 0.42)
const DIM := Color(0.66, 0.70, 0.78)

var _p: Character
var _left: VBoxContainer
var _mid: VBoxContainer
var _right: VBoxContainer
var _toast: Label
var _toast_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	if _p == null:
		_p = Game.player
	_build()
	_refresh()

## 作为 CanvasLayer 的子节点加入时（用于盖住探索 HUD），需要显式铺满视口
func fill_viewport() -> void:
	var vs := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vs

## 允许外部指定要检视的角色（默认玩家）
func setup(who: Character) -> void:
	_p = who

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast != null:
			_toast.text = ""

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		if (e as InputEventKey).keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
	queue_free()

# ——— 构建 ———

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = PANEL_BG
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var title := Label.new()
	title.text = "角 色 检 视"
	title.add_theme_font_size_override("font_size", 28)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.add_theme_color_override("font_color", GOLD)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 44
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_toast)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28
	row.offset_right = -28
	row.offset_top = 76
	row.offset_bottom = -66
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	_left = _make_column(row, 300)
	_mid = _make_column(row, 0)      # 0 = 自动拉伸
	_right = _make_column(row, 390)

	var close_btn := Button.new()
	close_btn.text = "关闭（Esc）"
	close_btn.custom_minimum_size = Vector2(180, 40)
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	close_btn.offset_left = -90
	close_btn.offset_right = 90
	close_btn.offset_top = -54
	close_btn.offset_bottom = -14
	close_btn.pressed.connect(_close)
	add_child(close_btn)

func _make_column(parent: HBoxContainer, width: int) -> VBoxContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	if width > 0:
		card.custom_minimum_size = Vector2(width, 0)
	else:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	return box

# ——— 刷新 ———

func _refresh() -> void:
	for b in [_left, _mid, _right]:
		for c in b.get_children():
			c.queue_free()
	if _p == null:
		return
	_build_left()
	_build_mid()
	_build_right()

func _toast_msg(msg: String) -> void:
	_toast.text = msg
	_toast_t = 2.0

func _head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 6)
	return s

func _kv(k: String, v: String, vcol: Color = Color.WHITE) -> HBoxContainer:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = k
	a.add_theme_font_size_override("font_size", 14)
	a.add_theme_color_override("font_color", DIM)
	a.custom_minimum_size = Vector2(96, 0)
	h.add_child(a)
	var b := Label.new()
	b.text = v
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", vcol)
	h.add_child(b)
	return h

# ——— 左栏：立绘与身份 ———

func _build_left() -> void:
	_left.add_child(_head("身份"))

	var portrait := TextureRect.new()
	var tex_path := "res://assets/sprites/w1/battle/hero.png"
	if ResourceLoader.exists(tex_path):
		portrait.texture = load(tex_path)
	portrait.custom_minimum_size = Vector2(250, 220)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_left.add_child(portrait)

	_left.add_child(_kv("姓名", _p.name, Color.WHITE))
	var talent: Dictionary = Talents.get_def(_p.talent_id)
	_left.add_child(_kv("天赋", String(talent.get("name", "无"))))
	_left.add_child(_kv("生命", "%d / %d" % [_p.hp, _p.max_hp()], Color(0.55, 0.95, 0.60)))
	_left.add_child(_kv("意志", "%d / %d" % [_p.will, _p.max_will()], Color(0.60, 0.85, 1.0)))
	if _p.gene_lock_level >= 1:
		_left.add_child(_kv("基因锁", "一阶 · 已觉醒", GOLD))

	_left.add_child(_sep())
	_left.add_child(_head("血统"))
	if _p.bloodlines.is_empty():
		var none := Label.new()
		none.text = "尚未激活（可在主神空间兑换）"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", DIM)
		_left.add_child(none)
	else:
		for bl in _p.bloodlines:
			var bid := String(bl.get("id", ""))
			var rank := String(bl.get("rank", "D"))
			var picked: Array = bl.get("picked", [])
			_left.add_child(_kv(Bloodlines.name_of(bid), "%s 级 · %d 技能" % [rank, picked.size()], GOLD))
		var rej := _p.bloodline_rejection()
		var syn := _p.bloodline_synergy()
		_left.add_child(_kv("排斥度", "%d%%（%s）" % [rej, Bloodlines.rejection_tier(rej)],
			Color(1.0, 0.45, 0.45) if rej >= 50 else DIM))
		_left.add_child(_kv("协同度", "%d%%（%s）" % [syn, Bloodlines.synergy_tier(syn)], ACCENT))

# ——— 中栏：属性与派生面板 ———

func _build_mid() -> void:
	_mid.add_child(_head("属性　（括号内为战棋出口）"))
	var total := 0
	for a in Attrs.ALL:
		total += int(_p.attrs.get(a, 0))
	if total <= Attrs.ALL.size():
		var warn := Label.new()
		warn.text = "⚠ 属性尚未分配（当前为初始值 1）。开局建卡时可分配 30 点。"
		warn.add_theme_font_size_override("font_size", 12)
		warn.add_theme_color_override("font_color", GOLD)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mid.add_child(warn)
	for a in Attrs.ALL:
		var v := _p.attr(a)
		var base := int(_p.attrs.get(a, 0))
		var bonus := v - base
		var val_text := "%d" % v
		if bonus != 0:
			val_text += "  (基础 %d %+d)" % [base, bonus]
		var h := _kv(Attrs.name_of(a), val_text, Color.WHITE if bonus == 0 else GOLD)
		h.get_child(0).custom_minimum_size = Vector2(52, 0)
		var desc := Label.new()
		desc.text = String(Attrs.DESC.get(a, ""))
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(desc)
		_mid.add_child(h)

	_mid.add_child(_sep())
	_mid.add_child(_head("战斗面板（派生值）"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	_mid.add_child(grid)
	var derived := [
		["生命上限", str(_p.max_hp()), "8 + 4×耐力"],
		["意志池", str(_p.max_will()), "2×决心"],
		["暴击率", "%d%%" % _p.crit_rate(), "5%×感知"],
		["移动力", str(_p.move_range()), "3 + 敏捷/2"],
		["指挥点", str(_p.command_points_base()), "智力/2 次/场"],
		["光环半径", "%d 格" % _p.aura_range(), "风度/2"],
		["威慑", "−%d 骰" % _p.intimidate_penalty(), "操控≥4 时 −2"],
		["首击减伤", str(_p.first_hit_reduction()), "沉着/3"],
		["先攻", str(_p.init_flat()), "敏捷 + 沉着"],
	]
	for d in derived:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var name_l := Label.new()
		name_l.text = String(d[0])
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", DIM)
		cell.add_child(name_l)
		var val_l := Label.new()
		val_l.text = String(d[1])
		val_l.add_theme_font_size_override("font_size", 17)
		val_l.add_theme_color_override("font_color", ACCENT)
		cell.add_child(val_l)
		var how_l := Label.new()
		how_l.text = String(d[2])
		how_l.add_theme_font_size_override("font_size", 10)
		how_l.add_theme_color_override("font_color", Color(0.45, 0.49, 0.56))
		cell.add_child(how_l)
		grid.add_child(cell)

	_mid.add_child(_sep())
	_mid.add_child(_head("技能"))
	var any := false
	for s in Skills.ALL:
		if _p.skill(s) > 0:
			var h := _kv(Skills.name_of(s), "%d 级" % _p.skill(s))
			h.get_child(0).custom_minimum_size = Vector2(110, 0)
			_mid.add_child(h)
			any = true
	if not any:
		var none := Label.new()
		none.text = "无"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", DIM)
		_mid.add_child(none)

# ——— 右栏：装备与背包 ———

func _build_right() -> void:
	_right.add_child(_head("装备"))
	_right.add_child(_equip_row("武器", _p.weapon))
	_right.add_child(_equip_row("护甲", _p.armor))
	_right.add_child(_sep())
	_right.add_child(_head("背包（点击即装备 / 使用）"))

	var shown := 0
	var seen := {}
	for iid in _p.inventory:
		var key := String(iid)
		if key == "fists":
			continue                     # 拳头是默认空手状态，不属于背包物品
		if seen.has(key):
			continue                     # 同种物品只列一次（堆叠数量后续再做）
		seen[key] = true
		var def: Dictionary = Items.get_def(key)
		if def.is_empty():
			continue
		_right.add_child(_item_button(key, def))
		shown += 1
	if shown == 0:
		var none := Label.new()
		none.text = "空"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", DIM)
		_right.add_child(none)

func _equip_row(slot: String, id: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = slot
	a.add_theme_font_size_override("font_size", 14)
	a.add_theme_color_override("font_color", DIM)
	a.custom_minimum_size = Vector2(52, 0)
	h.add_child(a)
	var b := Label.new()
	b.text = Items.name_of(id) if id != "" else "（空）"
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", GOLD if id != "" else DIM)
	h.add_child(b)
	if id != "":
		var extra := Label.new()
		var d: Dictionary = Items.get_def(id)
		if String(d.get("kind", "")) == "weapon":
			extra.text = "  伤害 %d" % int(d.get("damage", 0))
		elif String(d.get("kind", "")) == "armor":
			extra.text = "  护甲 +%d" % int(d.get("armor", 0))
		extra.add_theme_font_size_override("font_size", 12)
		extra.add_theme_color_override("font_color", DIM)
		h.add_child(extra)
		var off := Button.new()
		off.text = "卸下"
		off.custom_minimum_size = Vector2(56, 26)
		off.add_theme_font_size_override("font_size", 12)
		off.pressed.connect(func(): _unequip(String(d.get("kind", ""))))
		h.add_child(off)
	return h

func _item_button(iid: String, def: Dictionary) -> Button:
	var kind := String(def.get("kind", ""))
	var label := "%s" % String(def.get("name", iid))
	match kind:
		"weapon":
			label += "　[武器 伤害 %d]" % int(def.get("damage", 0))
		"armor":
			label += "　[护甲 +%d]" % int(def.get("armor", 0))
		"consumable":
			label += "　[消耗品]"
		"quest":
			label += "　[剧情物]"
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 13)
	b.tooltip_text = String(def.get("desc", ""))
	b.disabled = kind == "quest"
	b.pressed.connect(func(): _use_item(iid, def))
	return b

# ——— 操作 ———

func _use_item(iid: String, def: Dictionary) -> void:
	var kind := String(def.get("kind", ""))
	match kind:
		"weapon":
			var old := _p.weapon
			_p.weapon = iid
			_p.inventory.erase(iid)
			if old != "" and old != iid:
				_p.inventory.append(old)
			_toast_msg("已装备 %s" % String(def.get("name", iid)))
		"armor":
			var old_a := _p.armor
			_p.armor = iid
			_p.inventory.erase(iid)
			if old_a != "" and old_a != iid:
				_p.inventory.append(old_a)
			_toast_msg("已穿上 %s" % String(def.get("name", iid)))
		"consumable":
			_consume(iid, def)
		_:
			_toast_msg("这个没法直接用。")
	_refresh()

func _consume(iid: String, def: Dictionary) -> void:
	var used := false
	if def.has("heal_hp"):
		var before := _p.hp
		_p.hp = mini(_p.max_hp(), _p.hp + int(def["heal_hp"]))
		_toast_msg("恢复 %d 点生命（%d → %d）" % [int(def["heal_hp"]), before, _p.hp])
		used = true
	if def.has("heal_will"):
		var before_w := _p.will
		_p.will = mini(_p.max_will(), _p.will + int(def["heal_will"]))
		_toast_msg("恢复 %d 点意志（%d → %d）" % [int(def["heal_will"]), before_w, _p.will])
		used = true
	if def.has("stabilize"):
		_p.use_stabilizer(int(def["stabilize"]))
		_toast_msg("血脉稳定：%d 回合内排斥度 −15" % int(def["stabilize"]))
		used = true
	if used:
		_p.inventory.erase(iid)
	else:
		_toast_msg("现在用不上。")

func _unequip(kind: String) -> void:
	# 注意：拳头(fists) 是「空手」的默认状态，不是背包物品 —— 不能塞回背包
	if kind == "weapon" and _p.weapon != "" and _p.weapon != "fists":
		_p.inventory.append(_p.weapon)
		_p.weapon = "fists"
		_toast_msg("已收起武器")
	elif kind == "armor" and _p.armor != "":
		_p.inventory.append(_p.armor)
		_p.armor = ""
		_toast_msg("已脱下护甲")
	_refresh()
