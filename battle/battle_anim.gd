class_name BattleAnim
extends CanvasLayer
## 火纹式战斗特写动画层。
##
## 演出流程（约 2 秒，模仿 GBA 火纹的节奏）：
##   淡入 → 双方从两侧滑入对峙 → 攻击者冲刺挥击 → 命中闪光 + 伤害数字 + 受击抖动
##   → 若防守方存活则反击 → 淡出。
##
## 只负责「演出」，不修改任何战斗数值：调用方先把结果算好（命中/伤害/反击），
## 传给 play_fight()，动画结束后调用方再应用数值。
##
## 用法：
##   var anim := BattleAnim.new()
##   add_child(anim)
##   await anim.play_fight({ "hit": true, "damage": 4, ... })
##   anim.queue_free()

signal finished

const LEFT_X := 360.0
const RIGHT_X := 920.0
const GROUND_Y := 540.0
const ZOOM := 6.0          # 16×24 像素 sprite → 96×144

var _root: Control
var _bg: ColorRect
var _flash: ColorRect
var _left: Sprite2D
var _right: Sprite2D
var _left_name: Label
var _right_name: Label
var _left_hp: ColorRect
var _right_hp: ColorRect
var _left_hp_text: Label
var _right_hp_text: Label

const HP_W := 200.0
const HP_H := 14.0

# ——— 入口 ———

func play_fight(ctx: Dictionary) -> void:
	_build(ctx)
	await _fade(0.0, 0.95, 0.22)
	await _intro()
	await _attack_phase(true, ctx)
	if bool(ctx.get("counter", false)):
		await _attack_phase(false, ctx)
	await get_tree().create_timer(0.22).timeout
	await _fade(0.95, 0.0, 0.2)
	finished.emit()

func _build(ctx: Dictionary) -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bg = ColorRect.new()
	_bg.color = Color(0.04, 0.04, 0.07, 0.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)

	# 地面
	var ground := ColorRect.new()
	ground.color = Color(0.16, 0.17, 0.22, 0.95)
	ground.position = Vector2(0, GROUND_Y)
	ground.size = Vector2(1280, 5)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ground)

	# 双方 sprite（放大、右侧镜像）。ctx 用「左/右」语义描述，与“谁是玩家”无关，
	# 因此玩家攻击与敌方攻击复用同一套演出。
	_left = _make_sprite(String(ctx.get("left_tex", "")), Vector2(-260, GROUND_Y), false)
	_right = _make_sprite(String(ctx.get("right_tex", "")), Vector2(1540, GROUND_Y), true)

	# 名字
	_left_name = _make_label(String(ctx.get("left_name", "左")), Vector2(LEFT_X - 130, GROUND_Y + 16), 18, Color(0.85, 0.93, 1.0))
	_right_name = _make_label(String(ctx.get("right_name", "右")), Vector2(RIGHT_X - 130, GROUND_Y + 16), 18, Color(1.0, 0.85, 0.85))

	# HP 条
	_left_hp = _make_hp_bar(Vector2(LEFT_X - HP_W * 0.5, GROUND_Y + 44))
	_right_hp = _make_hp_bar(Vector2(RIGHT_X - HP_W * 0.5, GROUND_Y + 44))
	_left_hp_text = _make_label("", Vector2(LEFT_X - HP_W * 0.5, GROUND_Y + 62), 13, Color(0.9, 0.95, 1.0, 0.85))
	_right_hp_text = _make_label("", Vector2(RIGHT_X - HP_W * 0.5, GROUND_Y + 62), 13, Color(0.9, 0.95, 1.0, 0.85))
	_set_hp(true, int(ctx.get("left_hp", 1)), int(ctx.get("left_max", 1)), false)
	_set_hp(false, int(ctx.get("right_hp", 1)), int(ctx.get("right_max", 1)), false)

	# 全屏闪光
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

func _make_sprite(path: String, pos: Vector2, flip: bool) -> Sprite2D:
	var s := Sprite2D.new()
	if path != "" and ResourceLoader.exists(path):
		s.texture = load(path)
	s.centered = true
	s.scale = Vector2(ZOOM, ZOOM)
	s.flip_h = flip
	s.position = pos
	_root.add_child(s)
	return s

func _make_label(text: String, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.custom_minimum_size = Vector2(HP_W, 0)
	l.size = Vector2(HP_W, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l

func _make_hp_bar(pos: Vector2) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0.10, 0.10, 0.13, 0.95)
	back.position = pos - Vector2(2, 2)
	back.size = Vector2(HP_W + 4, HP_H + 4)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)
	var bar := ColorRect.new()
	bar.color = Color(0.35, 0.85, 0.42)
	bar.position = pos
	bar.size = Vector2(HP_W, HP_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	return bar

# ——— 阶段 ———

func _intro() -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_left, "position:x", LEFT_X, 0.24)
	t.tween_property(_right, "position:x", RIGHT_X, 0.24)
	await t.finished

## is_main：true = 主攻击方出手，false = 防守方反击
## 谁在左边由 ctx["main_left"] 决定（玩家攻击时为 true，敌方攻击时为 false）
func _attack_phase(is_main: bool, ctx: Dictionary) -> void:
	var main_left := bool(ctx.get("main_left", true))
	var atk_is_left := main_left if is_main else (not main_left)
	var atk: Sprite2D = _left if atk_is_left else _right
	var def: Sprite2D = _right if atk_is_left else _left
	var dir := 1.0 if atk_is_left else -1.0
	var hit := bool(ctx.get("hit", true)) if is_main else bool(ctx.get("counter_hit", true))
	var dmg := int(ctx.get("damage", 0)) if is_main else int(ctx.get("counter_damage", 0))
	var crit := bool(ctx.get("crit", false)) if is_main else false

	var rest_x: float = atk.position.x
	# 冲刺 + 挥击（前冲、轻微上挑、回位）
	var dash := create_tween()
	dash.set_parallel(false)
	dash.tween_property(atk, "position:x", rest_x + 150.0 * dir, 0.13)
	dash.parallel().tween_property(atk, "position:y", GROUND_Y - 6.0, 0.13)
	dash.tween_property(atk, "position:x", rest_x + 40.0 * dir, 0.09)
	dash.parallel().tween_property(atk, "position:y", GROUND_Y, 0.09)
	await dash.finished

	if hit:
		var def_is_left := not atk_is_left
		var after_hp := int(ctx.get("left_hp_after", 0)) if def_is_left else int(ctx.get("right_hp_after", 0))
		var max_hp := int(ctx.get("left_max", 1)) if def_is_left else int(ctx.get("right_max", 1))
		_on_hit(def, dmg, crit, def_is_left, after_hp, max_hp)
	else:
		_float_text("MISS", def.position + Vector2(0, -115), Color(0.85, 0.9, 1.0), 40)
		await get_tree().create_timer(0.35).timeout

	# 回位
	var back := create_tween()
	back.set_parallel(true)
	back.tween_property(atk, "position:x", rest_x, 0.12)
	back.tween_property(atk, "position:y", GROUND_Y, 0.12)
	await back.finished
	await get_tree().create_timer(0.18).timeout

func _on_hit(def: Sprite2D, dmg: int, crit: bool, is_left_def: bool, after_hp: int, max_hp: int) -> void:
	# 全屏白闪
	_flash.color = Color(1, 1, 1, 0.42 if crit else 0.28)
	var ft := create_tween()
	ft.tween_property(_flash, "color:a", 0.0, 0.22)
	# 受击过曝
	def.modulate = Color(2.4, 2.4, 2.4)
	var mt := create_tween()
	mt.tween_property(def, "modulate", Color(1, 1, 1), 0.22)
	# 抖动
	var base_x: float = def.position.x
	var sh := create_tween()
	for i in 3:
		sh.tween_property(def, "position:x", base_x + (8.0 if i % 2 == 0 else -8.0), 0.045)
	sh.tween_property(def, "position:x", base_x, 0.045)
	# 伤害数字
	_float_text(str(dmg), def.position + Vector2(0, -115), Color(1.0, 0.85, 0.3) if crit else Color(1, 1, 1), 56 if crit else 44, crit)
	# 血条真实下降（火纹式：命中后条子缩短并变色）
	_set_hp(is_left_def, maxi(after_hp, 0), maxi(max_hp, 1), true)
	await get_tree().create_timer(0.42).timeout

func _float_text(text: String, pos: Vector2, col: Color, size: int, big: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	l.position = pos - Vector2(70, 0)
	l.size = Vector2(140, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", pos.y - 70.0, 0.7)
	t.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	if big:
		t.parallel().tween_property(l, "scale", Vector2(1.35, 1.35), 0.2)
	t.chain().tween_callback(l.queue_free)

## 更新血条（animate = true 时平滑过渡）
func _set_hp(is_left: bool, hp: int, max_hp: int, animate: bool = true) -> void:
	var bar: ColorRect = _left_hp if is_left else _right_hp
	var text: Label = _left_hp_text if is_left else _right_hp_text
	var ratio := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	text.text = "%d / %d" % [maxi(hp, 0), max_hp]
	var target_w := HP_W * ratio
	var col := Color(0.35, 0.85, 0.42) if ratio > 0.5 else (Color(0.95, 0.8, 0.3) if ratio > 0.25 else Color(0.9, 0.35, 0.35))
	bar.color = col
	if animate:
		var t := create_tween()
		t.tween_property(bar, "size:x", target_w, 0.25)
	else:
		bar.size.x = target_w

## 供调用方在演出中途更新血量（例如命中后）
func apply_hp(attacker_hp: int, attacker_max: int, defender_hp: int, defender_max: int) -> void:
	_set_hp(true, attacker_hp, attacker_max, true)
	_set_hp(false, defender_hp, defender_max, true)

func _fade(from_a: float, to_a: float, dur: float) -> void:
	_bg.color.a = from_a
	var t := create_tween()
	t.tween_property(_bg, "color:a", to_a, dur)
	await t.finished
