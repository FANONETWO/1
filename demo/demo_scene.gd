extends Node2D
## 「惊变公寓」像素垂直切片 —— 可玩 Demo（阶段 1 地图）
##
## 运行：
##   godot --path . res://demo/demo_scene.tscn
##
## 操作：
##   左键点格子    移动（每回合 4 格，蓝色高亮为可达范围）
##   左键点敌人    相邻时攻击（命中 75%，敌人会反击）
##   左键点交互点  走到旁边后点击：拾取物品 / 获得线索
##   空格          结束回合（敌人行动）
##   R             重开
##   ESC           退出
##
## 主线：拿到「安全出口钥匙」→ 走到出口格撤离 → 三档结算。
## 本场景跑在**新架构**上：方格逻辑层（GridWorld：BFS / Dijkstra 移动范围 / 地形修正）
## + 像素渲染器（PixelGridRenderer）。战斗数值为切片简化版，后续接规则引擎。

const CELL := 48.0
const MOVES_PER_TURN := 4
const PLAYER_TEX := "res://assets/sprites/w1/player_idle.png"

## 敌人类型：素材、战斗数值与 AI 行为（切片简化数值，后续接规则引擎）
const ENEMY_STATS := {
	"zombie": {
		"name": "丧尸", "sprite": "res://assets/sprites/w1/zombie_idle.png", "zoom": 3.0,
		"hp": 8, "atk_min": 1, "atk_max": 3, "hit": 0.62, "chase": 7, "boss": false,
	},
	"crawler": {
		"name": "爬行者", "sprite": "res://assets/sprites/w1/crawler_idle.png", "zoom": 3.0,
		"fallback": "res://assets/sprites/w1/zombie_idle.png", "fallback_zoom": 3.0,
		"tint": Color(0.72, 1.0, 0.72),
		"hp": 6, "atk_min": 1, "atk_max": 2, "hit": 0.72, "chase": 10, "boss": false,
	},
	"brute": {
		"name": "尸王", "sprite": "res://assets/sprites/w1/brute_idle.png", "zoom": 2.0,
		"fallback": "res://assets/sprites/w1/zombie_idle.png", "fallback_zoom": 4.5,
		"tint": Color(1.0, 0.65, 0.65),
		"hp": 20, "atk_min": 2, "atk_max": 5, "hit": 0.66, "chase": 5, "boss": true,
	},
}

# ——— 交互点内容（坐标来自世界定义的 spots）———
const SPOT_DEF := {
	"storage_locker": {
		"label": "储物间柜子", "text": "柜门虚掩着，一根结实的钢管靠在角落。",
		"item": "钢管", "atk": 1,
	},
	"bed_mattress": {
		"label": "空房床垫", "text": "床垫下藏着一把开山刀，刃上贴着胶带。",
		"item": "开山刀", "atk": 2,
	},
	"duty_locker": {
		"label": "值班室药柜", "text": "最底层垫着一沓旧报纸——钥匙就压在下面，旁边还有一盒降压药。",
		"item": "安全出口钥匙", "key": true,
	},
	"duty_desk": {
		"label": "值班室桌面", "text": "摊开的工作日志：『9.14 凌晨，老张在大厅被咬。钥匙要藏好。』",
		"clue": "值班日志",
	},
	"stairs": {
		"label": "楼梯间", "text": "应急灯惨绿，向上的楼梯被杂物堵死。楼上有什么在拖行。",
	},
}

# ——— 状态 ———
var grid: GridWorld
var renderer: PixelGridRenderer
var player_sprite: Sprite2D
var player_pos := Vector2i(2, 2)
var player_hp := 14
var player_max_hp := 14
var player_atk := 3
var moves_left := MOVES_PER_TURN
var enemies: Array[Dictionary] = []
var exit_pos := Vector2i(14, 10)
var items: Array[String] = []
var clues: Array[String] = []
var kills := 0
var quest := "find_key"          # find_key → escape → done
var moving := false
var busy := false
var game_over := false
var _spot_taken: Dictionary = {}
var _spot_nodes: Dictionary = {}

var _lbl_quest: Label
var _lbl_hp: Label
var _lbl_bag: Label
var _lbl_log: Label
var _lbl_stats: Label
var _lbl_hint: Label
var _overlay: Control
var _log_lines: Array[String] = []

func _ready() -> void:
	var world := Worlds.get_world("w1_apartment")
	if world == null:
		push_error("[demo] 找不到世界 w1_apartment")
		get_tree().quit(1)
		return
	var stage: Dictionary = world.stage(0)
	grid = world.make_grid(0)
	exit_pos = stage.get("exit", Vector2i(14, 10))

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	bg_layer.add_child(bg)

	renderer = PixelGridRenderer.new()
	renderer.bind(grid)
	renderer.origin = Vector2(24, 36)   # 下移一点，给顶部 HUD 留空间
	add_child(renderer)

	# 敌人
	for e in stage.get("enemies", []):
		_spawn_enemy(e["pos"], String(e.get("id", "zombie")))
	# 交互点标记
	for sid in stage.get("spots", {}):
		var p: Vector2i = stage["spots"][sid]["pos"]
		_spot_nodes[String(sid)] = _add_marker(p, Color(0.95, 0.82, 0.35, 0.85), 13.0)
	# NPC 占位
	for nid in stage.get("npcs", {}):
		_add_marker(stage["npcs"][nid]["pos"], Color(0.55, 0.72, 0.95, 0.9), 15.0)

	player_pos = stage.get("spawn", Vector2i(2, 2))
	player_sprite = _add_sprite(PLAYER_TEX, player_pos)

	_build_hud()
	_log("你在一间陌生公寓里醒来。找钥匙，离开这里。")
	_refresh_range()
	_refresh_hud()
	_capture_shot()

# ——— 输入 ———

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if moving or busy:
			return
		_on_click(renderer.point_to_cell(event.position))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_SPACE:
				if not moving and not busy:
					_end_player_turn()

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or grid == null or _lbl_hint == null:
		return
	var g := renderer.point_to_cell(event.position)
	if not grid.in_bounds(g):
		return
	var extra := ""
	if not grid.is_walkable(g):
		extra = " · 不可通行"
	else:
		extra = " · 移动消耗 %d" % grid.move_cost(g)
	if g == exit_pos:
		extra = " · 安全出口"
	_lbl_hint.text = "(%d,%d) %s%s" % [g.x, g.y, grid.terrain_name_at(g), extra]

func _on_click(g: Vector2i) -> void:
	if not grid.in_bounds(g):
		return
	# 1) 点敌人 → 攻击
	var e: Dictionary = _enemy_at(g)
	if not e.is_empty():
		_try_attack(e)
		return
	# 2) 点交互点 → 交互（需相邻）
	for sid in _spot_nodes:
		if _spot_pos(String(sid)) == g:
			_try_interact(String(sid))
			return
	# 3) 点地面 → 移动（踩到出口则尝试撤离）
	if not grid.is_walkable(g):
		return
	_try_move(g)

# ——— 移动 ———

func _try_move(g: Vector2i) -> void:
	if g == player_pos:
		return
	if moves_left <= 0:
		_log("本回合移动力用完了，按空格结束回合。")
		return
	var path := grid.find_path(player_pos, g, Callable(self, "_is_blocked"))
	if path.is_empty():
		_log("走不过去。")
		return
	var steps := mini(path.size(), moves_left)
	moving = true
	renderer.show_path(path.slice(0, steps))
	var walked := 0
	for i in steps:
		await _step_player(path[i])
		walked += 1
		if path[i] == exit_pos:
			break
	moving = false
	moves_left -= walked
	renderer.clear_overlays()
	_refresh_range()
	_refresh_hud()
	if player_pos == exit_pos:
		_try_escape()
	elif moves_left <= 0 and not game_over:
		_log("移动力耗尽，按空格结束回合。")

func _step_player(to: Vector2i) -> void:
	var from := player_pos
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(player_sprite, "position", _anchor(to), 0.10)
	tween.tween_property(player_sprite, "position:y", _anchor(to).y - 3.0, 0.05).set_delay(0.05)
	await tween.finished
	player_sprite.position = _anchor(to)
	player_pos = to
	# 踩到危险地形（辐射/火场）扣血
	var dmg := grid.damage_per_turn_at(to)
	if dmg > 0:
		player_hp = maxi(0, player_hp - dmg)
		_log("脚下是 %s，你受到 %d 点伤害。" % [grid.terrain_name_at(to), dmg])
		_refresh_hud()
		if player_hp <= 0:
			_settle(false)

func _refresh_range() -> void:
	var cells: Array[Vector2i] = []
	if moves_left > 0:
		for p in grid.reachable(player_pos, moves_left, Callable(self, "_is_blocked")).keys():
			cells.append(p)
	renderer.show_move_range(cells)

# ——— 敌人 ———

func _spawn_enemy(pos: Vector2i, kind: String) -> void:
	var st: Dictionary = ENEMY_STATS.get(kind, ENEMY_STATS["zombie"])
	# 专属素材缺失时回退到基础丧尸图 + 色调区分（素材未就位时仍可辨认）
	var path := String(st["sprite"])
	var zoom := float(st["zoom"])
	if not ResourceLoader.exists(path):
		path = String(st.get("fallback", "res://assets/sprites/w1/zombie_idle.png"))
		zoom = float(st.get("fallback_zoom", zoom))
	var node := _add_sprite(path, pos, zoom)
	if node != null and st.has("tint"):
		node.modulate = st["tint"]
	var hp := int(st["hp"])
	enemies.append({
		"node": node, "pos": pos, "hp": hp, "max_hp": hp,
		"alive": true, "kind": kind, "stats": st,
	})

## 返回该格的敌人字典；没有敌人时返回空字典（避免 Variant 类型推断）
func _enemy_at(p: Vector2i) -> Dictionary:
	for e in enemies:
		if e["alive"] and e["pos"] == p:
			return e
	return {}

func _is_blocked(p: Vector2i) -> bool:
	for e in enemies:
		if e["alive"] and e["pos"] == p:
			return true
	return false

func _end_player_turn() -> void:
	if busy or moving or game_over:
		return
	moves_left = MOVES_PER_TURN
	_enemy_phase()

func _enemy_phase() -> void:
	busy = true
	_log("—— 敌方回合 ——")
	for e in enemies:
		if game_over:
			break
		if not e["alive"]:
			continue
		var st: Dictionary = e["stats"]
		var d := _manhattan(e["pos"], player_pos)
		if d <= 1:
			await _enemy_attack(e)
		elif d <= int(st["chase"]):
			var step := _step_toward(e["pos"], player_pos)
			if step != e["pos"]:
				e["pos"] = step
				var t := create_tween()
				t.tween_property(e["node"], "position", _unit_anchor(step, e["node"]), 0.16)
				await t.finished
	busy = false
	if not game_over:
		_refresh_range()
		_refresh_hud()

## 朝目标走一格（选择能缩短距离、可通行且未被占用的邻格）
func _step_toward(from: Vector2i, target: Vector2i) -> Vector2i:
	var best := from
	var best_d := _manhattan(from, target)
	for d in GridWorld.DIRS:
		var cand: Vector2i = from + d
		if not grid.is_walkable(cand) or _is_blocked(cand) or cand == player_pos:
			continue
		if grid.damage_per_turn_at(cand) > 0:
			continue
		var cd := _manhattan(cand, target)
		if cd < best_d:
			best = cand
			best_d = cd
	return best

func _enemy_attack(e: Dictionary) -> void:
	var st: Dictionary = e["stats"]
	var nm := String(st["name"])
	if randf() < float(st["hit"]):
		var dmg := randi_range(int(st["atk_min"]), int(st["atk_max"]))
		player_hp = maxi(0, player_hp - dmg)
		_log("%s 击中了你！受到 %d 点伤害。" % [nm, dmg])
		_flash(player_sprite, Color(1, 0.4, 0.4))
		_refresh_hud()
		if player_hp <= 0:
			_settle(false)
			return
	else:
		_log("%s 扑了个空。" % nm)
	await get_tree().create_timer(0.5).timeout

# ——— 战斗 ———

func _try_attack(e: Dictionary) -> void:
	if _manhattan(player_pos, e["pos"]) > 1:
		_log("得先走到它旁边才能攻击。")
		return
	busy = true
	var st: Dictionary = e["stats"]
	var nm := String(st["name"])

	# 1) 先算好本次交锋的全部结果（战斗动画只负责演出，不改数值）
	var hit := randf() < 0.75
	var dmg := randi_range(player_atk, player_atk + 2) if hit else 0
	var crit := hit and randf() < 0.15
	if crit:
		dmg = int(round(float(dmg) * 1.6))
	var ehp_before := int(e["hp"])
	var ehp_after := maxi(0, ehp_before - dmg)
	var enemy_dies := ehp_after <= 0
	var counter := not enemy_dies
	var counter_hit := counter and randf() < 0.6
	var counter_dmg := randi_range(int(st["atk_min"]), int(st["atk_max"])) if counter_hit else 0
	var php_after := maxi(0, player_hp - counter_dmg)

	# 2) 火纹式战斗特写
	var enemy_tex := String(st["sprite"])
	if not ResourceLoader.exists(enemy_tex):
		enemy_tex = String(st.get("fallback", "res://assets/sprites/w1/zombie_idle.png"))
	var anim := BattleAnim.new()
	add_child(anim)
	await anim.play_fight({
		"left_tex": PLAYER_TEX, "left_name": "轮回者",
		"right_tex": enemy_tex, "right_name": nm,
		"left_hp": player_hp, "left_max": player_max_hp, "left_hp_after": php_after,
		"right_hp": ehp_before, "right_max": int(e["max_hp"]), "right_hp_after": ehp_after,
		"main_left": true,
		"hit": hit, "damage": dmg, "crit": crit,
		"counter": counter, "counter_hit": counter_hit, "counter_damage": counter_dmg,
	})
	anim.queue_free()

	# 3) 应用结果
	if hit:
		_log("你击中%s，造成 %d 点伤害%s。" % [nm, dmg, "（暴击！）" if crit else ""])
	else:
		_log("你的攻击落空了。")

	if enemy_dies:
		e["hp"] = 0
		e["alive"] = false
		kills += 1
		if e["node"] != null:
			e["node"].queue_free()
		_log("%s 倒下了。（击杀 %d）" % [nm, kills])
	else:
		e["hp"] = ehp_after
		if e["node"] != null:
			e["node"].modulate = _enemy_tint(e)
		if counter_hit:
			player_hp = php_after
			_log("%s 反击，你受到 %d 点伤害。" % [nm, counter_dmg])
		else:
			_log("%s 的反击落空了。" % nm)

	busy = false
	_refresh_hud()
	if player_hp <= 0:
		_settle(false)
		return
	_end_player_turn()

# ——— 交互 ———

func _spot_pos(sid: String) -> Vector2i:
	var stage: Dictionary = Worlds.get_world("w1_apartment").stage(0)
	var spots: Dictionary = stage.get("spots", {})
	if spots.has(sid):
		return spots[sid]["pos"]
	return Vector2i(-1, -1)

func _try_interact(sid: String) -> void:
	if _spot_taken.has(sid):
		_log("%s：这里已经搜过了。" % SPOT_DEF.get(sid, {}).get("label", "这里"))
		return
	if _manhattan(player_pos, _spot_pos(sid)) > 1:
		_log("太远了，先走过去。")
		return
	var def: Dictionary = SPOT_DEF.get(sid, {})
	_spot_taken[sid] = true
	if _spot_nodes.has(sid) and _spot_nodes[sid] != null:
		_spot_nodes[sid].color = Color(0.5, 0.5, 0.5, 0.4)
	_log(String(def.get("text", "这里没什么值得看的。")))
	if def.has("item"):
		items.append(String(def["item"]))
		_log("获得物品：%s" % def["item"])
	if int(def.get("atk", 0)) > 0:
		player_atk += int(def["atk"])
		_log("攻击力提升到 %d。" % player_atk)
	if def.has("clue"):
		clues.append(String(def["clue"]))
		_log("【线索】%s" % def["clue"])
	if bool(def.get("key", false)):
		quest = "escape"
		_log("【任务更新】拿到钥匙了——去安全出口撤离！")
	_refresh_hud()

func _try_escape() -> void:
	if items.has("安全出口钥匙"):
		_settle(true)
	else:
		_log("消防门紧锁着。你需要找到安全出口的钥匙。")

# ——— 结算 ———

func _settle(win: bool) -> void:
	if game_over:
		return
	game_over = true
	busy = true
	var perfect := win and kills >= 2 and clues.size() >= 1
	var title := "陨落" if not win else ("完美撤离" if perfect else "惊险撤离")
	var body := ""
	if not win:
		body = "你的意识沉入黑暗。\n再次睁眼时，你回到主神空间的白色穹顶下。\n\n本次奖励清零。"
	else:
		var pts := 20 + kills * 8 + clues.size() * 5
		body = "你撞开消防门，冲进夜色。\n\n奖励点：%d（撤离 20 ＋ 击杀 %d×8 ＋ 线索 %d×5）\n剩余生命：%d/%d　物品：%s" % [
			pts, kills, clues.size(), player_hp, player_max_hp,
			("、".join(items) if not items.is_empty() else "无"),
		]
	_show_overlay(title, body)
	_log("【结算】%s" % title)

func _show_overlay(title: String, body: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 0)
	_overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := Label.new()
	t.text = "结算 · " + title
	t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(480, 0)
	v.add_child(b)
	var hint := Label.new()
	hint.text = "按 R 重开　·　ESC 退出"
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)

# ——— 表现辅助 ———

func _add_sprite(path: String, pos: Vector2i, zoom: float = 3.0) -> Sprite2D:
	if not ResourceLoader.exists(path):
		_add_marker(pos, Color(0.9, 0.3, 0.3, 0.9), 16.0)
		return null
	var tex: Texture2D = load(path)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2(zoom, zoom)
	s.position = _anchor_with(pos, tex, zoom)
	add_child(s)
	return s

func _anchor(pos: Vector2i) -> Vector2:
	var tex: Texture2D = player_sprite.texture if player_sprite != null else null
	return _anchor_with(pos, tex, 3.0)

## 任意单位的锚点：按各自纹理与缩放计算（Boss 尺寸与缩放都不同）
func _unit_anchor(pos: Vector2i, node: Sprite2D) -> Vector2:
	if node == null or node.texture == null:
		return _anchor(pos)
	return _anchor_with(pos, node.texture, node.scale.x)

func _anchor_with(pos: Vector2i, tex: Texture2D, zoom: float) -> Vector2:
	var w := tex.get_width() * zoom if tex != null else CELL * 0.5
	var h := tex.get_height() * zoom if tex != null else CELL
	return Vector2(
		renderer.origin.x + pos.x * CELL + CELL * 0.5 - w * 0.5,
		renderer.origin.y + pos.y * CELL + CELL - h
	)

func _add_marker(pos: Vector2i, color: Color, size: float) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(0, -size), Vector2(size, 0), Vector2(0, size), Vector2(-size, 0)])
	p.color = color
	p.position = Vector2(renderer.origin.x + pos.x * CELL + CELL * 0.5, renderer.origin.y + pos.y * CELL + CELL * 0.5)
	add_child(p)
	return p

func _flash(node: Sprite2D, color: Color, base: Color = Color(1, 1, 1)) -> void:
	if node == null:
		return
	node.modulate = color
	var t := create_tween()
	t.tween_property(node, "modulate", base, 0.3)

## 敌人当前应有的色调：基础色调 + 按剩余生命变暗（受伤反馈）
func _enemy_tint(e: Dictionary) -> Color:
	var base: Color = e["stats"].get("tint", Color(1, 1, 1))
	var ratio := float(e["hp"]) / maxf(1.0, float(e["max_hp"]))
	return base.darkened(clampf(1.0 - ratio, 0.0, 1.0) * 0.45)

func _capture_shot() -> void:
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://assets/raw/_probe/demo_shot.png"))
	print("[demo] 截图已保存 demo_shot.png")

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# ——— HUD ———

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	# HUD 统一放右上角空白区，避免遮挡地图；底部留给叙事日志
	var top_bg := ColorRect.new()
	top_bg.color = Color(0, 0, 0, 0.6)
	top_bg.position = Vector2(984, 6)
	top_bg.size = Vector2(290, 182)
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(top_bg)

	var log_bg := ColorRect.new()
	log_bg.color = Color(0, 0, 0, 0.62)
	log_bg.position = Vector2(10, 618)
	log_bg.size = Vector2(1010, 96)
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(log_bg)

	_lbl_quest = _mk_label(cl, 16, Vector2(992, 12), Color(1, 0.92, 0.7))
	_lbl_hp = _mk_label(cl, 13, Vector2(992, 62), Color(1, 1, 1))
	_lbl_bag = _mk_label(cl, 13, Vector2(992, 100), Color(0.8, 0.9, 1.0, 0.9))
	_lbl_stats = _mk_label(cl, 13, Vector2(992, 122), Color(1, 1, 1, 0.7))

	var help := _mk_label(cl, 12, Vector2(992, 148), Color(1, 1, 1, 0.5))
	help.text = "左键：移动 / 攻击 / 交互\n空格：结束回合　R：重开　ESC：退出"

	_lbl_hint = _mk_label(cl, 13, Vector2(992, 208), Color(0.75, 0.85, 1.0, 0.9))

	_lbl_log = _mk_label(cl, 14, Vector2(22, 626), Color(0.92, 0.95, 1.0, 0.95))
	_lbl_log.size = Vector2(980, 84)

func _mk_label(parent: Node, size: int, pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.position = pos
	l.modulate = col
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(268, 0)
	parent.add_child(l)
	return l

func _log(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > 4:
		_log_lines.pop_front()
	if _lbl_log != null:
		_lbl_log.text = "\n".join(_log_lines)

func _refresh_hud() -> void:
	if _lbl_hp == null:
		return
	var bar := ""
	var filled := int(round(float(player_hp) / float(player_max_hp) * 10.0))
	for i in 10:
		bar += "█" if i < filled else "░"
	_lbl_hp.text = "生命 %s %d/%d　攻击 %d　移动力 %d/%d" % [bar, player_hp, player_max_hp, player_atk, moves_left, MOVES_PER_TURN]
	_lbl_bag.text = "物品：%s" % ("、".join(items) if not items.is_empty() else "空")
	_lbl_stats.text = "击杀 %d　线索 %d　丧尸存活 %d" % [kills, clues.size(), _alive_enemies()]
	_lbl_quest.text = "【主线】找到安全出口钥匙" if quest == "find_key" else "【主线】前往安全出口撤离（左下角绿格）"

func _alive_enemies() -> int:
	var n := 0
	for e in enemies:
		if e["alive"]:
			n += 1
	return n
