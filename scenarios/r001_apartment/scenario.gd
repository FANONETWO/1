extends Control
## 「惊变公寓」探索场景：等距地图 + 点击移动 + 交互/对话/检定 + 触发战斗 + 结算。

const MapData := preload("res://scenarios/r001_apartment/map_data.gd")
const Content := preload("res://scenarios/r001_apartment/content.gd")
const Dialogs := preload("res://scenarios/r001_apartment/dialogs.gd")

var _map: GridRenderer
var _grid: GridWorld
var _player_sprite: Node2D
var _party_sprites: Array[Node2D] = []   # 团队模式的跟随队友（探索层不单独寻路）
var _trail: Array[Vector2i] = []         # 玩家走过的格子，队友踩着走
var _battle: Node = null   # 标准回合制战斗界面（BattleScene）
var _entities: Array[Dictionary] = []   # {node, pos, kind}
var _enemy_nodes: Dictionary = {}       # uid -> {node, def_id, hp}

# ——— 箱庭状态（世界 1 采用「单房间级别箱庭」，共 12 间）———
var _room_id := ""                      # 当前箱庭 id
## 已击杀 / 已拾取**不放在本地** —— 统一读写 Game.dungeon（唯一状态源），
## 这样切房间、连打多场、甚至存读档都不会让尸体复活。
const DUNGEON_ID := "r001_apartment"
const BASE_REWARD := 1000               # 副本基础奖励点（结算合计里必须计入）
var _visited: Dictionary = {}           # room_id -> true（仅用于本次会话的文案判断）
var _prev_room := ""                    # 上一间箱庭（撤退时退回这里）
var _room_entered := false              # 是否已经进过任何房间（首次落地不记来路）
var _exit_lock := 0.0                   # 刚切完房间的短暂锁，避免在门口来回弹
var _npc_nodes: Dictionary = {}
var _spot_nodes: Dictionary = {}

var _player_pos: Vector2i
var _player: Character
var _moving := false
const SIGHT := 2               # 敌人视野基准半径（格）；玩家的视野是 6，留出潜行空间
## 按类型细分视野：丧尸视力差但尸犬鼻子灵 —— 玩家要按敌人种类决定怎么绕。
## ⚠️ 数值整体收过一轮：原来丧尸 3 格 + 90° 锥，「看到就开战」时等于没有潜行空间。
const SIGHT_BY_TYPE := {
	"walker": 2, "zombie": 2, "crawler": 3,
	"hound": 4, "screamer": 3, "bloater": 1, "cadaver": 2, "brute": 3,
}
const PATROL_INTERVAL := 1.7   # 巡逻每格耗时（秒）—— 丧尸走得很慢
## 接触距离：曼哈顿 ≤ 1 即「贴上」，只有这时才开战
const CONTACT_DIST := 1
## 追到最后已知位置后，连续几个回合没再看见人就放弃（所以「甩掉它」是可行的）
const CHASE_GIVE_UP := 3

func _sight_range(def_id: String) -> int:
	return int(SIGHT_BY_TYPE.get(def_id, SIGHT))
var _sight_sig := ""           # 视野锥缓存签名（uid + 位置 + 朝向 + 格数），变了才重绘
var _quests: Quests
var _clues: Dictionary = {}
var _combat_points := 0
var _npc_states: Dictionary = {}
var _spot_states: Dictionary = {}

# UI
var _log: RichTextLabel
var _hud_hp: Label
var _hud_will: Label
var _hud_pts: Label
var _hud_quest: Label
var _overlay: Control
var _modal_title: Label
var _modal_body: Label
var _modal_buttons: VBoxContainer
var _dialog_cursor: Dictionary = {}
var _dialog_npc := ""
var _active := false

func _ready() -> void:
	theme = PixelTheme.build()
	# 根节点不拦截鼠标，点击才能落到地图（_unhandled_input）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = Game.player
	if _player == null:
		get_tree().change_scene_to_file.call_deferred("res://ui/main_menu.tscn")
		return
	_quests = Quests.new([&"escape", &"save_chen", &"clear_lobby"])
	_quests.activate_all()
	# 恢复战斗前的探索现场状态
	var alive_uids: Array = []
	if Game.scenario_state.has("explore_state"):
		var es: Dictionary = Game.scenario_state["explore_state"]
		_clues = es.get("clues", {})
		_spot_states = es.get("spot_states", {})
		_npc_states = es.get("npc_states", {})
		var qs: Dictionary = es.get("quests", {})
		for qid in qs:
			_quests.states[String(qid)] = String(qs[qid])
		_combat_points = int(es.get("combat_points", 0))
		alive_uids = es.get("alive_uids", [])
		Game.scenario_state.erase("explore_state")
	_build_ui()
	_build_world()
	# 已击杀的敌人与线索都由 Game.dungeon 统一记录，建场时就会跳过
	# 战斗返回恢复：应用战果、恢复玩家位置
	if Game.scenario_state.has("last_combat"):
		_on_combat_return()
	if Game.scenario_state.has("explore_pos"):
		var ep: Vector2i = Game.scenario_state["explore_pos"]
		if _map.is_walkable(ep):
			_player_pos = ep
			_position_entity(_player_sprite, _player_pos)
			_map.set_highlight(ep, Color(0.4, 0.85, 1.0, 0.35))
			_sort_entities()
	if _player_pos == MapData.SPAWN:
		_log_line(Content.INTRO)
	_refresh_hud()
	AudioManager.play_bgm("explore")
	# 新手引导（试玩报告 C3）：本次副本第一次进入时弹出，之后可用右上「引导」按钮重看
	if not _tutorial_done():
		_show_tutorial(0)

# ——— 世界构建（箱庭制）———

## 一次性：创建地图渲染器与玩家精灵
func _build_world() -> void:
	_grid = GridWorld.new()
	_map = PixelGridRenderer.new()
	_map.bind(_grid)
	_map.origin = Vector2(24, 40)
	add_child(_map)
	move_child(_map, 1)          # 地图插到背景之上、HUD 之下

	# 玩家不挂名字标签：走到地图左上角时它会和 HUD 任务栏叠在一起
	_player_sprite = _make_entity("", Color(0.35, 0.7, 0.9), false, true,
		"res://assets/sprites/w1/player_idle.png")
	_entities.append({"node": _player_sprite, "pos": Vector2i.ZERO, "kind": "player"})

	# 团队模式：队友以「跟随队列」的形式出现在地图上（不单独寻路 —— 箱庭是单房间级，
	# 四个人各自走会互相堵门，迷雾也会碎成四块）。战斗时他们才真正展开成独立单位。
	for a in Game.allies():
		var mate: Character = a
		var sp := _make_entity(String(mate.name), Color(0.5, 0.85, 0.6), false, false,
			"res://assets/sprites/w1/player_idle.png")
		_party_sprites.append(sp)
		_entities.append({"node": sp, "pos": Vector2i.ZERO, "kind": "ally"})

	_load_room(R001Rooms.START_ROOM, Vector2i.ZERO, "")

## 载入（或切换）一个箱庭：换地图 + 重建该间的实体，玩家保留。
## entry_cell 为 ZERO 时用箱庭默认出生点。
func _load_room(room_id: String, entry_cell: Vector2i, from_dir: String = "") -> void:
	var room := R001Rooms.get_room(room_id)
	if room.is_empty():
		push_error("箱庭不存在: " + room_id)
		return
	# 记录来路（撤退时退回这里）；首次落地不算
	if _room_entered and _room_id != room_id:
		_prev_room = _room_id
	_room_entered = true
	_room_id = room_id
	_visited[room_id] = true
	DebugLog.ev("room", "载入箱庭", {"room": room_id, "name": R001Rooms.room_name(room_id), "from": from_dir})
	_noise = 0                    # 换空间 → 噪音重置（你是新来的）
	_noise_decay = 0.0

	# 1) 换地图
	var tiles: Array[String] = []
	for row in room.get("tiles", []):
		tiles.append(String(row))
	_grid.setup(tiles)

	# 2) 清掉上一间的实体（玩家精灵保留）
	_clear_room_entities()

	# 3) 玩家落点
	if entry_cell == Vector2i.ZERO:
		_player_pos = _room_spawn_cell(room_id)
	else:
		_player_pos = entry_cell
	if not _grid.is_walkable(_player_pos):
		_player_pos = _room_spawn_cell(room_id)

	# 4) 本间实体 + 装饰层
	_build_room_entities(room, room_id)
	_build_deco(room_id)

	# 5) 玩家与高亮
	_position_entity(_player_sprite, _player_pos)
	_map.set_highlight(_player_pos, Color(0.4, 0.85, 1.0, 0.35))
	_sort_entities()
	_refresh_hud()
	# 已探索记忆按房间独立（C5）；换房间补一记开门音 + 中央大字幕（C6）
	if _map is PixelGridRenderer:
		(_map as PixelGridRenderer).reset_seen()
	if from_dir != "":
		AudioManager.play("door")
		# 只在真正「换房间」时打大字幕：刚进场那条会和新手引导弹窗叠在一起糊成一团
		_announce_room(room_id)
	# 队友跟着进新房间：先贴在玩家身边，等移动后自然排成队列
	_trail.clear()
	for sp in _party_sprites:
		_position_entity(sp, _player_pos)
	_sort_entities()
	# 不同房间可能有相同坐标 → 强制重算迷雾，否则会沿用上一间的视野
	_fog_at = Vector2i(-99, -99)
	# 换房间必须重算视野锥：_enemy_nodes 刚被重建，缓存签名也要作废。
	# 少了这一步，新房间完全看不到敌人视野（曾经的真 bug：进屋 0 格预警）。
	_sight_sig = ""
	_refresh_sight()
	# 关键：刚落地时上锁，否则若出生点恰是出口格会立刻被弹到隔壁
	_exit_lock = 0.8

	# 6) 文案
	var intro := String(room.get("intro", ""))
	if intro != "":
		if _room_id == R001Rooms.START_ROOM and not _visited.has("_intro_shown"):
			_visited["_intro_shown"] = true
			_log_line(Content.INTRO)
		else:
			_log_line("[color=#8cd8ff]【%s】[/color] %s" % [R001Rooms.room_name(room_id), intro])

func _clear_room_entities() -> void:
	_enemy_nodes.clear()
	_npc_nodes.clear()
	_spot_nodes.clear()
	var keep: Array[Dictionary] = []
	for e in _entities:
		var kind := String(e.get("kind", ""))
		# 玩家与跟队友都要跨房间保留（他们是"跟着你走的人"）
		if kind == "player" or kind == "ally":
			keep.append(e)
			continue
		var n = e.get("node")
		if n != null and is_instance_valid(n):
			n.queue_free()
	_entities = keep

func _build_room_entities(room: Dictionary, room_id: String) -> void:
	# 敌人（已击杀的不会复活）
	for e in room.get("enemies", []):
		var pos: Vector2i = e["pos"]
		var uid := "%s/enemy_%d_%d" % [room_id, pos.x, pos.y]
		if Game.is_killed(DUNGEON_ID, uid):
			continue
		var node := _make_entity(Enemies.name_of(String(e["id"])), Color(0.55, 0.3, 0.25), true, false,
			"res://assets/sprites/w1/zombie_idle.png")
		_enemy_nodes[uid] = {
			"node": node, "def_id": String(e["id"]), "pos": pos, "hp": 0,
			"facing": e.get("facing", Vector2i(0, 1)),
			# 巡逻路线（可选）：沿这些点循环走，面朝行进方向（视野锥跟着转）
			"patrol": e.get("patrol", []),
			"patrol_idx": 0,
			"move_timer": 0.0,
		}
		_entities.append({"node": node, "pos": pos, "kind": "enemy", "uid": uid})

	# NPC
	for n in room.get("npcs", []):
		var nid := String(n.get("id", ""))
		var key := "%s/%s" % [room_id, nid]
		var node := _make_entity(String(n.get("label", nid)), Color(0.5, 0.55, 0.65), false)
		_npc_nodes[key] = {"node": node, "pos": Vector2i(n["pos"]), "label": String(n.get("label", nid)), "def_id": nid}
		_entities.append({"node": node, "pos": Vector2i(n["pos"]), "kind": "npc", "nid": key})

	# 调查点
	for s in room.get("spots", []):
		var sid := String(s.get("id", ""))
		var key := "%s/%s" % [room_id, sid]
		if Game.is_taken(DUNGEON_ID, key):
			continue
		var node := _make_entity(String(s.get("label", sid)), Color(0.8, 0.7, 0.4), false)
		_spot_nodes[key] = {"node": node, "pos": Vector2i(s["pos"]), "label": String(s.get("label", sid)), "def_id": sid}
		_entities.append({"node": node, "pos": Vector2i(s["pos"]), "kind": "spot", "sid": key})

## 箱庭默认出生点：优先取 'S' 楼梯，其次第一块可通行地板
## 按房间语义生成装饰层。固定种子（房间 id）→ 每次进入同一间看到的一样。
func _build_deco(room_id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room_id)
	var density := _deco_density(room_id)
	var items: Array = []
	for y in _grid.rows():
		for x in _grid.cols():
			var p := Vector2i(x, y)
			if _grid.char_at(p) != ".":
				continue                      # 只有地板能放装饰
			if rng.randf() > density:
				continue
			items.append({
				"pos": p,
				"name": _deco_name_for(room_id, rng),
				"off": Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)),
			})
	_map.set_deco(items)

## 房间语义 → 装饰密度（走廊稀疏、储物/客房杂乱）
func _deco_density(room_id: String) -> float:
	match room_id:
		"corridor_n", "corridor_s":
			return 0.05
		"lobby":
			return 0.10
		"storage", "utility", "guest_room":
			return 0.16
		"duty_room":
			return 0.14
		_:
			return 0.10

## 房间语义 → 装饰类型（客房有尸体、储物间多纸箱、杂物间多碎石）
func _deco_name_for(room_id: String, rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	match room_id:
		"guest_room":
			pool = ["blood_pool", "blood_smear", "corpse", "trash_papers", "corpse"]
		"storage":
			pool = ["cardboard", "cardboard", "trash_papers", "rubble_pile"]
		"utility":
			pool = ["rubble_pile", "trash_papers", "water_stain", "glass_shards"]
		"corridor_n", "corridor_s":
			pool = ["glass_shards", "trash_papers", "blood_smear", "water_stain"]
		"lobby":
			pool = ["blood_pool", "blood_smear", "trash_papers", "glass_shards", "corpse"]
		"duty_room":
			pool = ["trash_papers", "glass_shards", "blood_smear", "water_stain"]
		_:
			pool = ["trash_papers", "glass_shards", "water_stain", "blood_smear"]
	return pool[rng.randi() % pool.size()]

func _room_spawn_cell(room_id: String) -> Vector2i:
	var room := R001Rooms.get_room(room_id)
	var tiles: Array = room.get("tiles", [])
	for y in tiles.size():
		var row := String(tiles[y])
		for x in row.length():
			if row[x] == "S":
				return Vector2i(x, y)
	for y in tiles.size():
		var row := String(tiles[y])
		for x in row.length():
			if row[x] == ".":
				return Vector2i(x, y)
	return Vector2i(1, 1)

# ——— 箱庭切换 ———

## 站在出口格上时切到相邻箱庭
func _check_room_exit() -> void:
	if _battle != null or _moving or _exit_lock > 0.0:
		return
	for e in R001Rooms.exit_cells(_room_id):
		if Vector2i(e["cell"]) == _player_pos:
			var target := String(e["room"])
			if target == "" or not R001Rooms.ROOMS.has(target):
				continue
			_exit_lock = 0.8
			_load_room(target, _entry_cell_from(target, _room_id), "go")
			return

## 从目标箱庭里找到「能回到来路」的那一格作为落点
func _entry_cell_from(target_room: String, came_from: String) -> Vector2i:
	for e in R001Rooms.exit_cells(target_room):
		if String(e["room"]) == came_from:
			var c: Vector2i = e["cell"]
			# 落在出口格内侧一格（可通行处），避免立刻被弹回
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var p: Vector2i = c + d
				if _grid.is_walkable(p):
					return p
			return c
	return Vector2i.ZERO

## 地图实体：有像素素材就用 sprite（16×24 放大 3 倍、脚底对齐格底），否则回退为菱形色块。
func _make_entity(label: String, color: Color, hostile: bool, is_player: bool = false, sprite_path: String = "") -> Node2D:
	var n := Node2D.new()
	var top_y := -22.0
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var s := Sprite2D.new()
		s.texture = load(sprite_path)
		s.centered = false
		s.scale = Vector2(3.0, 3.0)     # 16×24 → 48×72
		s.position = Vector2(-24, -48)  # 底边落在格子底部
		n.add_child(s)
		top_y = -74.0
	else:
		var body := Polygon2D.new()
		var w := 26.0
		var h := 16.0
		body.polygon = PackedVector2Array([Vector2(0, -h), Vector2(w, 0), Vector2(0, h), Vector2(-w, 0)])
		body.color = color
		n.add_child(body)
		top_y = -h - 22.0
	# 头顶标签
	var lb := Label.new()
	lb.text = label
	lb.position = Vector2(-40, top_y)
	lb.size = Vector2(80, 18)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 13)
	lb.modulate = Color(1, 1, 1, 0.85)
	lb.visible = label != ""
	n.add_child(lb)
	n.set_meta("name_label", lb)
	_map.add_child(n)
	return n

func _position_entity(node: Node2D, pos: Vector2i) -> void:
	node.position = _map.grid_to_world(pos)

func _sort_entities() -> void:
	var cmp := func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2i = a["pos"]
		var pb: Vector2i = b["pos"]
		return pa.x + pa.y < pb.x + pb.y
	_entities.sort_custom(cmp)
	var idx := 1
	for e in _entities:
		# 关键修复：每个实体都要按自己的格子定位，否则会全部堆在 (0,0)（此前敌人因此不可见）
		var p: Vector2i = _player_pos if String(e.get("kind", "")) == "player" else e["pos"]
		e["pos"] = p
		_position_entity(e["node"], p)
		_map.move_child(e["node"], idx)
		idx += 1

# ——— UI ———

## HUD 按钮工厂：统一挂上点击音效（避免每个按钮各写一遍）
func _hud_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void:
		AudioManager.play("ui_click")
		cb.call())
	return b

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 顶部 HUD
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_top = 8
	top.offset_right = -16
	top.offset_bottom = 36
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 20)
	add_child(top)

	_hud_hp = Label.new()
	_hud_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hud_hp)
	_hud_will = Label.new()
	_hud_will.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hud_will)
	_hud_pts = Label.new()
	_hud_pts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_hud_pts)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	top.add_child(_hud_button("任务", _show_tasks))
	top.add_child(_hud_button("角色", _show_character))
	top.add_child(_hud_button("引导", func() -> void: _show_tutorial(0)))
	top.add_child(_hud_button("规则", _show_rules))

	_hud_quest = Label.new()
	_hud_quest.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_quest.offset_top = 40
	_hud_quest.offset_left = 16
	_hud_quest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_quest.modulate = Color(1, 1, 1, 0.8)
	_hud_quest.add_theme_font_size_override("font_size", 15)
	add_child(_hud_quest)

	# 底部日志
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_panel.offset_left = 16
	log_panel.offset_top = -100
	log_panel.offset_right = -16
	log_panel.offset_bottom = -12
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)
	_log = RichTextLabel.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.bbcode_enabled = true
	log_panel.add_child(_log)

	# 模态层
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	_overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_modal_title = Label.new()
	_modal_title.add_theme_font_size_override("font_size", 20)
	v.add_child(_modal_title)
	_modal_body = Label.new()
	_modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_body.custom_minimum_size = Vector2(520, 0)
	_modal_body.add_theme_font_size_override("font_size", 15)
	v.add_child(_modal_body)
	_modal_buttons = VBoxContainer.new()
	_modal_buttons.add_theme_constant_override("separation", 6)
	v.add_child(_modal_buttons)
	add_child(_overlay)

	EventBus.log_line.connect(_on_log_line)
	EventBus.combat_log.connect(_on_log_line)

## 交互半径（试玩报告 B2：只给 1 格时玩家会以为「点了没反应」）
## 适用于 NPC 对话与调查点（无敌人房间里走过去本来就没风险）
const INTERACT_RANGE := 2

## 新手引导三步（试玩报告 C3：进副本后 30 秒不知道该干嘛）
const TUTORIAL: Array = [
	{
		"title": "引导 1/3 · 怎么走，要做什么",
		"body": "① 左键点【可走的地砖】→ 角色走过去（一格一格走）。\n② 点【敌人 / 柜子 / 桌子 / 床 / NPC】→ 交互（相邻才动手）。\n③ 走到【门口的地砖】→ 进入下一个房间。\n④ 右上角「任务」看目标，「角色」看属性，「规则」查判定公式。\n\n主线：找到安全出口钥匙 → 摸到消防门撤离。",
	},
	{
		"title": "引导 2/3 · 回合制：敌人什么时候转身",
		"body": "你行动一次后，【所有敌人各走一步】—— 这一层是回合制，不是实时。\n\n· 空格 = 结束这一回合（原地等待/观察）。\n· 【亮红格子】= 现在就会被看见：踩进去它就会开始追你。\n· 【暗红格子】= 那个敌人的视野范围：暂时安全，但别在它面前晃。\n· 每个敌人只看【正前方 90°】—— 绕到它背后就是突袭（你抢先手）。\n· 被发现 ≠ 开战：它会朝你走过来，**贴到身上**才打。跑开、绕圈、换房间都能甩掉它。\n· 视野外是黑的，那是迷雾，不是画面坏了。",
	},
	{
		"title": "引导 3/3 · 噪音与黑暗",
		"body": "· 走动、翻柜子、开枪都会产生【噪音】（HUD 右上「噪音」）。\n· 噪音到 6 / 10 / 14 会分别招来 逐尸 / 爬行者 / 尸群 —— 越吵越危险，安静下来会自己衰减。\n· 你只能看清 6 格内、且没有被墙挡住的地方；走过的房间会留下【暗色轮廓】（已探索记忆）。\n· 走廊和大堂的怪物会巡逻转向；【房间里的不会动】（它们困住了）。",
	},
]

var _banner: Label = null      # 换房间时画面中央的大字幕

func _tutorial_done() -> bool:
	return bool(Game.dungeon_state(DUNGEON_ID)["flags"].get("tutorial_done", false))

## 只读查询（常量没法通过 Object.get 读到，测试与 UI 走这两个出口）
func interact_range() -> int:
	return INTERACT_RANGE

func tutorial_pages() -> int:
	return TUTORIAL.size()

func _mark_tutorial_done() -> void:
	Game.dungeon_state(DUNGEON_ID)["flags"]["tutorial_done"] = true

## 跳过新人引导（玩家点「跳过引导」走的就是这里；测试也用它来模拟"老玩家"，
## 否则引导浮层会挡住模拟点击 —— click_test / pace_test 曾因此失败）
func skip_tutorial() -> void:
	_mark_tutorial_done()
	_close_modal()

func _show_tutorial(page: int) -> void:
	AudioManager.play("ui_click")
	if page >= TUTORIAL.size():
		_mark_tutorial_done()
		_close_modal()
		return
	var t: Dictionary = TUTORIAL[page]
	var last := page == TUTORIAL.size() - 1
	var opts: Array = [{
		"label": "开始行动" if last else "下一页",
		"on_press": func() -> void:
			if last:
				_mark_tutorial_done()
			else:
				_show_tutorial(page + 1),
	}]
	if not last:
		opts.append({"label": "跳过引导", "on_press": func() -> void: _mark_tutorial_done()})
	_open_modal(String(t["title"]), String(t["body"]), opts)

## 换房间时在画面中央打一条大字幕（试玩报告 C6：12 个箱庭结构相似，玩家分不清自己进了哪）
func _announce_room(room_id: String) -> void:
	if _banner == null or not is_instance_valid(_banner):
		_banner = Label.new()
		_banner.set_anchors_preset(Control.PRESET_CENTER)
		_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_theme_font_size_override("font_size", 34)
		_banner.modulate = Color(1, 1, 1, 0)
		add_child(_banner)
	_banner.text = R001Rooms.room_name(room_id)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.1)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)

func _show_tasks() -> void:
	var lines: Array[String] = []
	for qid in _quests.defs:
		var d: Dictionary = QuestsDef.get_def(String(qid))
		var st := _quests.status(StringName(qid))
		var mark := "■"
		var text := String(d.get("desc", ""))
		match st:
			"active":
				mark = "▶"
				text = String(d.get("hint_active", text))
			"done":
				mark = "✔"
			"failed":
				mark = "✘"
		lines.append("%s 【%s】%s" % [mark, d.get("name", qid), text])
	_open_modal("任务日志", "\n\n".join(lines), [{"label": "关闭", "on_press": Callable()}])

var _char_layer: CanvasLayer = null      # 角色面板所在的层（必须记引用才关得掉）

func _show_character() -> void:
	# BG3 式角色检视面板（属性 / 派生值 / 装备 / 背包），替代原来的纯文本 modal
	if is_instance_valid(_char_layer):
		return
	var cp := CharacterPanel.new()
	cp.setup(_player)
	# 探索 HUD 画在 CanvasLayer 上，普通 Control 盖不住 → 面板也放进更高的层
	var layer := CanvasLayer.new()
	layer.layer = 200        # 必须高于探索 HUD 所在的 CanvasLayer
	add_child(layer)
	layer.add_child(cp)
	cp.fill_viewport()
	# 关键：必须接 closed 并把层收掉，否则面板永远盖在最上层、之后什么都看不见
	cp.closed.connect(_hide_character)
	_char_layer = layer

func _hide_character() -> void:
	if is_instance_valid(_char_layer):
		_char_layer.queue_free()
	_char_layer = null

func _show_rules() -> void:
	var text := "【检定】掷 D10 骰池（属性+技能），每枚 ≥8 计 1 成功；掷出 10 可追加一骰。\n成功数 ≥ 难度（DC）即成功。\n\n【战斗】每回合 6 行动点：移动 1 格 1 点，攻击 3 点，防御 2 点（+2 防御）。\n攻击伤害 = max(1, 攻击成功数 - 目标防御) + 武器加成。\n\n【意志力】上限 = 决心+沉着。战斗外检定可花费 1 点 +1 成功。\n\n【基因锁】生命 ≤30% 时自动觉醒一阶：攻击成功 +1、伤害 +1、防御 +1。\n首次濒死（生命归零）触发『绝境爆种』：觉醒基因锁并恢复 20% 生命。"
	_open_modal("规则速查", text, [{"label": "关闭", "on_press": Callable()}])

func _open_modal(title: String, body: String, options: Array) -> void:
	_modal_title.text = title
	_modal_body.text = body
	for c in _modal_buttons.get_children():
		c.queue_free()
	for opt in options:
		var b := Button.new()
		b.text = String(opt.get("label", "…"))
		var cb: Callable = opt.get("on_press", Callable())
		b.pressed.connect(func() -> void:
			_overlay.visible = false
			if cb.is_valid():
				cb.call()
		)
		_modal_buttons.add_child(b)
	_overlay.visible = true

func _close_modal() -> void:
	_overlay.visible = false
	_hide_character()        # 角色面板在 CanvasLayer 上，普通 modal 关不掉它

# ——— 输入：点击移动与交互 ———

func _unhandled_input(event: InputEvent) -> void:
	# C 键：随时打开角色检视（BG3 式）
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			# 再按一次关闭（否则玩家会以为游戏卡住了）
			if is_instance_valid(_char_layer):
				_hide_character()
			else:
				_show_character()
			return
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 战斗期间：点击全部交给战斗控制器（同一张地图，不切场景）
		if _battle != null:
			_battle.handle_click(event.position)
			return
		if _overlay.visible or _moving:
			return
		var g := _map.grid_at_point(event.position)
		# 先看这一格上有没有可交互的东西 —— 柜子/桌子/床/楼梯本身**不可走**，
		# 但正因如此才更需要能点它们（否则调查点永远点不响）。
		if _click_entity(g):
			return
		if not _map.is_walkable(g):
			return
		# 点击地面 → 移动
		_move_to(g)

func _click_entity(g: Vector2i) -> bool:
	# 敌人（相邻可战）
	for uid in _enemy_nodes:
		var e: Dictionary = _enemy_nodes[uid]
		if e["pos"] == g:
			if _manhattan(_player_pos, g) <= 1:
				# 在敌人视野之外动手 = 突袭（玩家抢到先手）；已被看到则敌人先手
				var surprise := not _in_enemy_sight(String(uid))
				if surprise:
					_log_line("[color=#ffd75e]你从背后接近 —— 突袭！[/color]")
				else:
					_log_line("[color=#ff8c66]%s 已经看到你了。[/color]" % Enemies.name_of(String(e["def_id"])))
				_start_combat_with(String(e["def_id"]), surprise)
			else:
				AudioManager.play("ui_deny")
				_log_line("你得先靠近它。")
			return true
	# NPC
	for nid in _npc_nodes:
		var n: Dictionary = _npc_nodes[nid]
		if n["pos"] == g:
			_talk_npc(String(nid))
			return true
	# 调查点
	for sid in _spot_nodes:
		var s: Dictionary = _spot_nodes[sid]
		if s["pos"] == g:
			_inspect_spot(String(sid))
			return true
	return false

# ——— 敌人视野与潜行（XCOM 式节奏） ———

## 是否落在朝向的前方 **90° 锥**（±45°）内。判据 |d·f| ≥ |d×f| ⟺ 夹角 ≤ 45°。
## ⚠️ 曾经这里只写 d·f > 0 —— 那是 ±90°（张角 180°），侧后方的敌人也会「看见」你，
## 与教程承诺的「站在它背后 = 突袭」直接矛盾。改判定必须同步 _in_enemy_sight。
func _in_cone(d: Vector2i, f: Vector2i) -> bool:
	var dot := d.x * f.x + d.y * f.y
	if dot <= 0:
		return false
	var crs := d.x * f.y - d.y * f.x
	return absi(dot) >= absi(crs)

## 该敌人视野内的格子（前方 90° 锥 + 半径 + 通视）
func _sight_cells(uid: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _enemy_nodes.has(uid):
		return out
	var e: Dictionary = _enemy_nodes[uid]
	var e_pos: Vector2i = e["pos"]
	var f: Vector2i = e.get("facing", Vector2i(0, 1))
	for y in _grid.rows():
		for x in _grid.cols():
			var p := Vector2i(x, y)
			var d := p - e_pos
			var dist := absi(d.x) + absi(d.y)
			if dist == 0 or dist > _sight_range(String(e["def_id"])):
				continue
			if _in_cone(d, f) and _grid.has_line_of_sight(e_pos, p):
				out.append(p)
	return out

## 指定敌人是否能看到玩家（贴脸必然被发现）
func _in_enemy_sight(uid: String) -> bool:
	if not _enemy_nodes.has(uid):
		return false
	var e: Dictionary = _enemy_nodes[uid]
	var d: Vector2i = _player_pos - (e["pos"] as Vector2i)
	var dist := absi(d.x) + absi(d.y)
	if dist == 0:
		return true          # 同格（踩在身上）必然被发现
	if dist > _sight_range(String(e["def_id"])):
		return false
	var f: Vector2i = e.get("facing", Vector2i(0, 1))
	if not _in_cone(d, f):
		return false
	return _grid.has_line_of_sight(e["pos"], _player_pos)   # 墙/柜子/森林挡住视线

## 刷新场上所有敌人的视野锥。两层：
##   亮红（danger）= 此刻就会看见你的敌人 —— 踩进去立刻接敌
##   暗红（watch） = 其它敌人的视野 —— 提醒「那边有眼睛」，但你暂时是安全的
##
## 缓存签名必须包含**每个敌人的 uid + 位置 + 朝向 + 视野格数**：
## 只比 uid 的话，巡逻兵转身/移动后视野锥会停在原地不动（这曾经是个真 bug）。
func _refresh_sight() -> void:
	if _battle != null:
		return
	var danger: Array[Vector2i] = []
	var watch: Array[Vector2i] = []
	var sig := ""
	for uid in _enemy_nodes:
		var e: Dictionary = _enemy_nodes[uid]
		var cells := _sight_cells(String(uid))
		sig += "%s@%s%s#%d;" % [uid, str(e["pos"]), str(e.get("facing", Vector2i(0, 1))), cells.size()]
		if _in_enemy_sight(String(uid)):
			danger.append_array(cells)
		else:
			watch.append_array(cells)
	if sig == _sight_sig:
		return
	_sight_sig = sig
	_map.show_attack_range(danger)
	_map.show_watch_range(watch)

## 更新「谁发现了你」。
## 被发现只进入**追逐**状态，不等于开战 —— 玩家还有机会跑开、绕圈或换房间。
## 这一步是潜行能成立的关键：看到即开战的话，潜行就变成了踩雷。
func _update_enemy_alert() -> void:
	for uid in _enemy_nodes:
		var e: Dictionary = _enemy_nodes[uid]
		if not _in_enemy_sight(String(uid)):
			continue
		e["last_seen"] = _player_pos
		e["lost_turns"] = 0
		if not bool(e.get("alerted", false)):
			e["alerted"] = true
			_log_line("[color=#ffd75e]%s 发现了你 —— 它在朝你过来！[/color]" % Enemies.name_of(String(e["def_id"])))

## 接触判定：只有**已经发现你**的敌人贴到身上才开战。
## 没发现你的敌人贴着你也没事 —— 那是你绕到它背后准备突袭的机会。
func _check_engagement() -> bool:
	if _battle != null:
		return false
	for uid in _enemy_nodes:
		var e: Dictionary = _enemy_nodes[uid]
		if not bool(e.get("alerted", false)):
			continue
		if _manhattan(e["pos"], _player_pos) <= CONTACT_DIST:
			_log_line("[color=#ff8c66]%s 抓住了你！[/color]" % Enemies.name_of(String(e["def_id"])))
			_start_combat_with(String(e["def_id"]), false)
			return true
	return false

## 该格是否空着（忽略自己）—— 追击寻路要用
func _cell_free_except(p: Vector2i, uid: String) -> bool:
	for k in _enemy_nodes:
		if String(k) == uid:
			continue
		if Vector2i(_enemy_nodes[k]["pos"]) == p:
			return false
	for nid in _npc_nodes:
		if Vector2i(_npc_nodes[nid]["pos"]) == p:
			return false
	return true

## 追击一步：朝玩家（或最后看到他的位置）走一格；贴到身上就开战。
## 追到最后已知位置还看不见人 → 数回合后放弃，回到巡逻 —— 所以「甩掉它」是可行的。
func _chase_step(uid: String, e: Dictionary) -> void:
	var sees := _in_enemy_sight(uid)
	if sees:
		e["last_seen"] = _player_pos
		e["lost_turns"] = 0
	else:
		e["lost_turns"] = int(e.get("lost_turns", 0)) + 1
	var cur: Vector2i = e["pos"]
	# 已经贴上了：交给接触判定，不再移动
	if _manhattan(cur, _player_pos) <= CONTACT_DIST:
		return
	var target: Vector2i = _player_pos if sees else Vector2i(e.get("last_seen", _player_pos))
	if not sees and cur == target and int(e["lost_turns"]) >= CHASE_GIVE_UP:
		e["alerted"] = false
		e["lost_turns"] = 0
		_log_line("[color=#8cd8ff]%s 失去了你的踪迹，重新开始游荡。[/color]" % Enemies.name_of(String(e["def_id"])))
		return
	var path := Pathfind.find(cur, target, func(p: Vector2i) -> bool:
		return not _grid.is_walkable(p) or not _cell_free_except(p, uid))
	if path.size() < 2:
		return
	var nxt: Vector2i = path[1]
	if not _grid.is_walkable(nxt) or not _cell_free_except(nxt, uid):
		return
	e["pos"] = nxt
	e["facing"] = nxt - cur
	_position_entity(e["node"], nxt)
	for ent in _entities:
		if String(ent.get("uid", "")) == uid:
			ent["pos"] = nxt
			break
	_sort_entities()
	_refresh_sight()
	if _manhattan(nxt, _player_pos) <= CONTACT_DIST:
		_log_line("[color=#ff8c66]%s 抓住了你！[/color]" % Enemies.name_of(String(e["def_id"])))
		_start_combat_with(String(e["def_id"]), false)

func _move_to(g: Vector2i) -> void:
	var path := Pathfind.find(_player_pos, g, func(p): return not _map.is_walkable(p))
	if path.is_empty():
		return
	_moving = true
	_map.set_path(path)
	_move_along(path, 0)

func _move_along(path: Array, i: int) -> void:
	if i >= path.size():
		_moving = false
		_map.clear_path()
		_refresh_sight()
		_end_player_turn()          # 玩家行动结束 → 轮到敌人
		return
	var nxt: Vector2i = path[i]
	var step := func() -> void:
		var prev := _player_pos
		_player_pos = nxt
		_update_party_follow(prev)      # 队友踩着玩家刚离开的格子跟上
		AudioManager.play_varied("step", 0.06, {"throttle": 110})
		_refresh_sight()
		_update_enemy_alert()        # 谁看到你了（只标记追逐，不开战）
		if _check_engagement():      # 已经发现你的敌人贴到身上才开战
			_moving = false
			_map.clear_path()
			return
		for e in _entities:
			if e.get("kind", "") == "player":
				e["pos"] = nxt
				break
		_map.set_highlight(nxt, Color(0.4, 0.85, 1.0, 0.35))
		_sort_entities()
		# 踩到出口
		if nxt == MapData.EXIT:
			_try_escape()
			return
		_move_along(path, i + 1)
	var tween := create_tween()
	tween.tween_property(_player_sprite, "position", _map.grid_to_world(nxt) + Vector2(0, 6), 0.12)
	tween.tween_callback(step)

## 队友跟随：踩玩家走过的格子，形成队伍纵列。
## 探索层不让他们单独寻路 —— 箱庭是单房间级，四个人各自走会互相堵门，迷雾也会碎成四块。
func _update_party_follow(from_pos: Vector2i) -> void:
	if _party_sprites.is_empty():
		return
	_trail.push_front(from_pos)
	var want := _party_sprites.size() + 1
	if _trail.size() > want:
		_trail.resize(want)
	for i in _party_sprites.size():
		var p: Vector2i = _trail[i] if i < _trail.size() else from_pos
		_position_entity(_party_sprites[i], p)
		for e in _entities:
			if e.get("node") == _party_sprites[i]:
				e["pos"] = p
				break
	_sort_entities()

func _try_escape() -> void:
	if _player.inventory.has("apartment_key"):
		_finish_scenario("perfect" if _quests.is_done(&"save_chen") and _quests.is_done(&"clear_lobby") and _clue_count() >= 3 else "normal")
	else:
		_log_line("消防门紧锁着。你需要找到安全出口的钥匙。")

# ——— 交互 ———

func _talk_npc(nid: String) -> void:
	if not _npc_nodes.has(nid):
		return
	var e: Dictionary = _npc_nodes[nid]
	var dist := _manhattan(_player_pos, Vector2i(e["pos"]))
	if dist > INTERACT_RANGE:
		AudioManager.play("ui_deny")
		_log_line("太远了（还差 %d 格），走近一点再说话。" % (dist - INTERACT_RANGE))
		return
	AudioManager.play("ui_click")
	# nid 是「房间/裸id」的完整 key；对话表按裸 id 索引，这里必须剥掉前缀
	var bare := String(e.get("def_id", nid))
	if bare == "chen":
		_dialog_cursor = Dialogs.CHEN["start"]
		_dialog_npc = "chen"
	elif bare == "agui":
		_dialog_cursor = Dialogs.AGUI["start"]
		_dialog_npc = "agui"
	else:
		_log_line("他不理会你。")
		return
	_show_dialog()

func _show_dialog() -> void:
	var node: Dictionary = _dialog_cursor
	if node.is_empty() or node.get("text", "") == "":
		_close_modal()
		return
	var options: Array = node.get("options", [])
	var btns: Array = []
	for opt in options:
		var o: Dictionary = opt
		var label := String(o.get("label", "…"))
		# 检查条件
		if o.has("check_has") and not _player.inventory.has(String(o["check_has"])):
			continue
		btns.append({"label": label, "on_press": _dialog_choose.bind(o)})
	if btns.is_empty():
		btns.append({"label": "（离开）", "on_press": Callable()})
	_open_modal(String(_dialog_npc), String(node["text"]), btns)

func _dialog_choose(opt: Dictionary) -> void:
	# 执行动作
	if opt.has("action"):
		_do_dialog_action(String(opt["action"]))
	# 检定选项
	if opt.has("check"):
		var ck: Dictionary = opt["check"]
		var on_result := func(ok: bool) -> void:
			# 缺省回退到 end：即使对话数据漏写 pass/fail 也不会触发「无效键访问」运行时错误
			var next_id := String(opt.get("pass", "end") if ok else opt.get("fail", "end"))
			var node := _dialog_node(next_id)
			if node.is_empty():
				node = _dialog_node("end")
			_dialog_cursor = node
			_show_dialog()
		_run_check_async(ck, on_result)
		return
	if opt.has("next"):
		_dialog_cursor = _dialog_node(String(opt["next"]))
		_show_dialog()
	else:
		_close_modal()

func _dialog_node(id: String) -> Dictionary:
	if _dialog_npc == "chen":
		return Dialogs.CHEN.get(id, {})
	return Dialogs.AGUI.get(id, {})

func _do_dialog_action(action: String) -> void:
	match action:
		"chen_saved":
			_player.inventory.erase("chen_medicine")
			_quests.complete(&"save_chen")
			_log_line("【支线完成】老邻居。陈叔告诉了你尸王的弱点。")
			_add_clue("boss_weakness", Content.CLUES["boss_weakness"])
			_refresh_hud()
		"agui_noise_hint":
			# 借疯子之口教噪音机制 —— 比系统提示自然
			_log_line("[color=#ffd75e]【情报】它们靠声音找人。脚步声、开门声、枪声都会把它们引过来。[/color]")
			_npc_states["agui"] = "talked"
			_refresh_hud()
		"agui_insight":
			# 识破：阿贵夸大了车库里的数量，他其实没下去过
			_flags()["agui_insight"] = true
			_log_line("[color=#8cd8ff]你识破了阿贵的夸大 —— 他没数过，他连车库都没下去过。[/color]")
			_npc_states["agui"] = "talked"
			_refresh_hud()
		"agui_misinformed":
			# 信了假情报：后续会因此多绕路（噪音累积），这是「不可靠叙述者」的代价
			_flags()["agui_misinformed"] = true
			_log_line("[color=#ff8c66]你信了阿贵说的「车库里有二十只」。（这信息未必可靠。）[/color]")
			_npc_states["agui"] = "talked"
			_refresh_hud()

func _inspect_spot(sid: String) -> void:
	if not _spot_nodes.has(sid):
		return
	var sp: Dictionary = _spot_nodes[sid]
	var dist := _manhattan(_player_pos, Vector2i(sp["pos"]))
	if dist > INTERACT_RANGE:
		AudioManager.play("ui_deny")
		_log_line("太远了（还差 %d 格），走近一点再动手。" % (dist - INTERACT_RANGE))
		return
	AudioManager.play("ui_click")
	# 同上：剥掉房间前缀，match 用的才是裸 id
	var bare := String(sp.get("def_id", sid))
	match bare:
		"storage_locker":
			var pick := func() -> void:
				_player.weapon = "bat"
				_log_line("你捡起钢管（近战伤害 +1）。")
				_close_modal()
				_refresh_hud()
			_open_modal("储物间柜子", "柜门虚掩着，里面堆着旧物。一根结实的钢管靠在角落——比你赤手空拳强多了。", [
				{"label": "捡起钢管（近战伤害 +1）", "on_press": pick},
				{"label": "翻找一番（感知+调查 DC 3）", "on_press": _search_storage},
				{"label": "离开", "on_press": Callable()},
			])
		"duty_locker":
			if _player.inventory.has("apartment_key"):
				_open_modal("值班室药柜", "药柜已经被你翻过了。最底层垫着的旧报纸还在，钥匙已经不在了。", [
					{"label": "离开", "on_press": Callable()},
				])
			else:
				var take := func() -> void:
					_player.inventory.append("chen_medicine")
					_player.inventory.append("apartment_key")
					Game.mark_taken(DUNGEON_ID, sid)
					# 旧报纸下面压着的不只是钥匙 —— 还有一张沾血的排班表
					_add_clue("duty_roster", Content.CLUES["duty_roster"])
					_log_line("你拿到了降压药，和一把锈迹斑斑的铁钥匙（安全出口钥匙）。")
					_quests.start(&"escape")
					_refresh_hud()
					_close_modal()
				_open_modal("值班室药柜", "药柜里码着几盒药：降压药、感冒药、过期抗生素。最底层垫着一沓旧报纸，下面似乎压着什么硬东西。", [
					{"label": "拿走降压药和钥匙", "on_press": take},
					{"label": "先不动，离开", "on_press": Callable()},
				])
		"duty_desk":
			if _has_clue("duty_note"):
				_open_modal("值班室桌面", "工作日志还摊开着，最后一行停在写到一半的地方。", [{"label": "离开", "on_press": Callable()}])
			else:
				_add_clue("duty_note", Content.CLUES["duty_note"])
				_open_modal("值班室桌面", "一本摊开的工作日志，最后一行字写到一半就停了：\n\n『22:40 接到上级通知，要求 —— 』\n\n笔尖在纸上按出了一个深深的墨点。\n写字的人没有慌。", [{"label": "合上日志", "on_press": Callable()}])
		"bed_mattress":
			if _has_clue("twenty_shoes"):
				_open_modal("空房床垫", "床垫下空空如也。", [{"label": "离开", "on_press": Callable()}])
			else:
				_add_clue("twenty_shoes", Content.CLUES["twenty_shoes"])
				var take := func() -> void:
					_player.weapon = "machete"
					_log_line("你换上了开山刀（白刃伤害 +2）。")
					_close_modal()
					_refresh_hud()
				_open_modal("空房床垫", "床垫下压着一把开山刀，刃上缠着胶带。\n旁边还码着一双鞋 —— 和别处那些一样，鞋头朝着门外。", [
					{"label": "带走开山刀（白刃伤害 +2）", "on_press": take},
					{"label": "只拿走情报", "on_press": Callable()},
				])
		"medkit_box":
			if Game.is_taken(DUNGEON_ID, sid):
				_open_modal("急救箱", "急救箱已经空了。", [{"label": "离开", "on_press": Callable()}])
			else:
				Game.mark_taken(DUNGEON_ID, sid)
				_player.inventory.append("medkit")
				_log_line("你找到一个急救包（战斗中可用「物品」，恢复 5 点生命）。")
				_open_modal("急救箱", "墙上的急救箱，玻璃碎了。\n里面还剩一个未拆封的急救包。\n（获得：急救包 · 恢复 5 点生命）", [{"label": "收下", "on_press": Callable()}])
				_refresh_hud()
		"seal_912":
			if _has_clue("seal_912"):
				_open_modal("墙上的封条", "封条还贴在那儿。日期是九月十二号。", [{"label": "离开", "on_press": Callable()}])
			else:
				_add_clue("seal_912", Content.CLUES["seal_912"])
				_open_modal("墙上的封条", "墙上贴着一张黄色封条，边角翘起来。\n\n『危险区域　禁止入内』\n落款日期：九月十二日\n\n你摸了摸口袋里的排班表 —— 那是九月十三号的。", [{"label": "（撕下来收好）", "on_press": Callable()}])
		"blood_words":
			if _has_clue("blood_words"):
				_open_modal("门内侧的血字", "那三个字还在。", [{"label": "离开", "on_press": Callable()}])
			else:
				_add_clue("blood_words", Content.CLUES["blood_words"])
				_open_modal("门内侧的血字", "门内侧，有人用手指蘸血写了三个字：\n\n　　别　开　门\n\n字迹往下拖得很长，最后一笔拖了将近一尺。", [{"label": "（沉默）", "on_press": Callable()}])
		"stairs":
			_open_modal("楼梯间", "应急灯惨绿。向上的楼梯被杂物堵死，空气里飘着一股浓重的腐臭。\n楼上，有什么东西在拖行。", [
				{"label": "（还是别上去了）", "on_press": Callable()},
			])
		_:
			_log_line("这里没什么值得看的。")

func _search_storage() -> void:
	var on_result := func(ok: bool) -> void:
		if ok:
			# 储物间翻出的是装备；排班表在药柜，别重复
			_player.inventory.append("vest_light")
			_log_line("你找到一件防刺背心（护甲 +1）。")
			_open_modal("储物间柜子", "柜子底层压着一件旧背心，摸上去里面有硬衬 ——\n保安室淘汰下来的防刺背心。\n（获得：防刺背心）", [{"label": "收下", "on_press": Callable()}])
			_refresh_hud()
		else:
			_open_modal("储物间柜子", "你翻得满头灰，只翻出一堆发霉的旧报纸。", [{"label": "离开", "on_press": Callable()}])
	_run_check_async({"attr": "per", "skill": "investigate", "dc": 3}, on_result)

# ——— 检定 ———

func _run_check_async(ck: Dictionary, done: Callable) -> void:
	var p := _player
	var attr_id := String(ck.get("attr", "per"))
	var skill_id := String(ck.get("skill", ""))
	var dc := int(ck.get("dc", 4))
	var extra := p.check_extra_success(attr_id, skill_id)
	var use_will := false
	# 询问是否投入意志力
	var will_btn := func() -> void:
		if p.will > 0:
			p.will -= 1
			_resolve_check(attr_id, skill_id, dc, extra + 1, done)
		else:
			_resolve_check(attr_id, skill_id, dc, extra, done)
		_refresh_hud()
	var direct_btn := func() -> void:
		_resolve_check(attr_id, skill_id, dc, extra, done)
	_open_modal("检定准备", "%s+%s 检定（难度 %d）\n\n生命 %d/%d　意志 %d/%d\n\n是否投入 1 点意志力（+1 成功）？" % [Attrs.name_of(attr_id), Skills.name_of(skill_id) if skill_id != "" else "无", dc, p.hp, p.max_hp(), p.will, p.max_will()], [
		{"label": "投入意志力", "on_press": will_btn},
		{"label": "直接尝试", "on_press": direct_btn},
	])

func _resolve_check(attr_id: String, skill_id: String, dc: int, extra: int, done: Callable) -> void:
	var p := _player
	var res := DicePool.roll(p.attr(attr_id), p.skill(skill_id), 0, extra, skill_id)
	AudioManager.play("dice")
	var ok := int(res["total"]) >= dc
	var cont := func() -> void:
		_close_modal()
		done.call(ok)
	var detail := "%s+%s：掷 %d 枚骰，骰面成功 %d（附加 %+d）＝ %d　／ 难度 %d" % [
		Attrs.name_of(attr_id), Skills.name_of(skill_id) if skill_id != "" else "无",
		int(res["dice"]), int(res["successes"]), int(res["bonus"]), int(res["total"]), dc,
	]
	if bool(res.get("failed_zero", false)):
		detail += "\n（心智系技能 0 级：无法判定，自动失败。）"
	elif bool(res.get("bonus_void", false)):
		detail += "\n（骰面全数落空——附加成功无法让失败的行动变成成功。）"
	detail += "\n\n" + ("成功！" if ok else "失败……")
	_open_modal("检定结果", detail, [{"label": "继续", "on_press": cont}])

# ——— 战斗 ———

func _start_combat_with(enemy_id: String, surprise: bool = false) -> void:
	if _battle != null:
		return
	# 老周（尸王）战前独白 —— 全副本唯一有台词的敌人。
	# 不做旁白解释：他是保安，他在上班，他一直没下班。
	if enemy_id == "brute":
		_log_line("[color=#c9b8a8]那个东西没有扑过来。它停下来，慢慢转过身。[/color]")
		for line in Content.BOSS_LINES:
			_log_line("[color=#c9b8a8]「%s」[/color]" % line)
	# 遭遇组合：目标敌人 + 附近 1 个存活敌人（都带探索侧 uid，战后据此同步）
	var encounter: Array[Dictionary] = []
	var target_uid := ""
	for uid in _enemy_nodes:
		var e: Dictionary = _enemy_nodes[uid]
		if String(e["def_id"]) == enemy_id:
			encounter.append({"id": enemy_id, "pos": e["pos"], "uid": String(uid)})
			target_uid = String(uid)
			break
	for uid in _enemy_nodes:
		if String(uid) == target_uid:
			continue
		var e: Dictionary = _enemy_nodes[uid]
		encounter.append({"id": String(e["def_id"]), "pos": e["pos"], "uid": String(uid)})
		break
	if encounter.is_empty():
		_log_line("这里没有敌人。")
		return
	# ——— 标准回合制战斗：全屏覆盖（不切场景，探索状态全部保留）———
	# 主角固定在左、怪物在右，不使用地图格子。
	_battle = BattleScene.new()
	add_child(_battle)
	AudioManager.play_bgm("battle")
	_battle.finished.connect(_on_battle_finished)
	_battle._player_pos_hint = _player_pos
	_battle.setup(self, Game.player, encounter, surprise, Game.allies())
	_battle.begin()

## 战斗结束：一切留在原地（这是融合的核心收益）
func _on_battle_finished(victory: bool) -> void:
	if _battle == null:
		return
	var killed: Array = _battle.killed_uids.duplicate()
	var pts: int = _battle.reward_points
	var end_pos: Vector2i = _battle.player_final_pos
	var was_flee := bool(_battle.fled)
	DebugLog.ev("battle_end", "战斗结束", {
		"victory": victory, "flee": was_flee, "kills": killed.size(),
		"points": pts, "hp": int(_player.hp), "room": _room_id,
	})
	_battle.queue_free()
	AudioManager.play_bgm("explore")
	AudioManager.play("ui_confirm" if victory else "ui_deny")
	_battle = null
	_player_pos = end_pos          # 位置连续：停在战斗结束的那一格
	if victory:
		_combat_points += pts
		for uid in killed:
			# 唯一状态源：**先记「已击杀」再移除实体** —— 顺序反了就会漏（上一版的 bug）
			Game.mark_killed(DUNGEON_ID, String(uid))
			if _enemy_nodes.has(String(uid)):
				_remove_enemy(String(uid))
		_log_line("战斗胜利。击杀奖励 +%d 奖励点。" % pts)
		if _enemy_nodes.is_empty():
			_quests.complete(&"clear_lobby")
			_log_line("【任务完成】清道夫。公寓一层安静了下来。")
	else:
		# 区分「脱离」与「战败」：逃跑不该判死。
		# 代价是退回上一间 —— 没能前进，还可能撞上巡逻。
		if was_flee:
			_log_line("[color=#8cd8ff]你退了出来。身后的声音还在，但没追上来。[/color]")
			if _prev_room != "" and _prev_room != _room_id:
				var back := _prev_room
				_load_room(back, Vector2i.ZERO, "flee")
				_log_line("你退回了 %s。" % R001Rooms.room_name(back))
			else:
				_player_pos = _room_spawn_cell(_room_id)
				_position_entity(_player_sprite, _player_pos)
				_refresh_sight()
		else:
			_finish_scenario("death", 0)
	_refresh_hud()

## 战斗返回后调用（combat_scene 通过 scenario_state 传回结果）。
func _on_combat_return() -> void:
	var st: Dictionary = Game.scenario_state.get("last_combat", {})
	Game.scenario_state.erase("last_combat")
	if st.get("victory", false):
		_combat_points += int(st.get("points", 0))
		var killed: Array = st.get("killed", [])
		for uid in killed:
			if _enemy_nodes.has(String(uid)):
				_remove_enemy(String(uid))
		_log_line("战斗胜利。击杀奖励 +%d 奖励点。" % int(st.get("points", 0)))
		if not _enemy_nodes.is_empty():
			# 还有敌人存活 → 清道夫任务未完成
			pass
		else:
			_quests.complete(&"clear_lobby")
			_log_line("【任务完成】清道夫。公寓一层安静了下来。")
		_refresh_hud()
	else:
		_finish_scenario("death", 0)

# ——— 结算 ———

func _finish_scenario(ending: String, kill_points: int = -1) -> void:
	var p := _player
	var quest_pts := 0
	for qid in [&"escape", &"save_chen", &"clear_lobby"]:
		if _quests.is_done(qid):
			quest_pts += int(QuestsDef.get_def(String(qid)).get("reward_points", 0))
	var kill_pts := kill_points if kill_points >= 0 else _combat_points
	var clue_pts := _clue_count() * 5
	# 基础奖励必须计入合计 —— 之前漏了，结算显示「基础 +1,000」但合计只有击杀分
	var subtotal := BASE_REWARD + quest_pts + kill_pts + clue_pts
	# 模式倍率：独狼 ×1.5（风险溢价）。死亡不结算，所以不加倍。
	var mult := Game.reward_multiplier()
	var total := int(round(float(subtotal) * mult)) if ending != "death" else 0
	var res: Dictionary = Content.settlement(p.name, ending, _clue_count(), quest_pts, kill_pts, total, mult, Game.mode_name())
	AudioManager.play_bgm("")
	AudioManager.play("defeat" if ending == "death" else "evac")
	EventBus.scenario_finished.emit(res)
	Game.finish_scenario(res)
	_show_settlement(res)

func _show_settlement(res: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(600, 0)
	overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := Label.new()
	t.text = "结算 · " + String(res["title"])
	t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)
	var b := Label.new()
	b.text = String(res["body"])
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(560, 0)
	b.add_theme_font_size_override("font_size", 15)
	v.add_child(b)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	var back := Button.new()
	back.text = "返回主神空间"
	back.pressed.connect(Game.go_hub)
	btns.add_child(back)
	var retry := Button.new()
	retry.text = "再来一次"
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	btns.add_child(retry)
	add_child(overlay)

# ——— 辅助 ———

## 移除敌人节点并清理实体列表。
func _remove_enemy(uid: String) -> void:
	if not _enemy_nodes.has(uid):
		return
	var e: Dictionary = _enemy_nodes[uid]
	var node: Node = e["node"]
	if node != null and is_instance_valid(node):
		node.queue_free()   # 彻底释放（此前只 remove_child，会留下不可见节点）
	_enemy_nodes.erase(uid)
	_entities = _entities.filter(func(x): return x.get("uid", "") != uid)

# ——— 线索（同样走唯一状态源，切房间/重载都不丢）———

func _flags() -> Dictionary:
	return Game.dungeon_state(DUNGEON_ID)["flags"]

func _has_clue(id: String) -> bool:
	return _flags().has("clue:" + id)

func _clue_count() -> int:
	var n := 0
	for k in _flags():
		if String(k).begins_with("clue:"):
			n += 1
	return n

func _add_clue(id: String, text: String) -> void:
	if _has_clue(id):
		return
	_flags()["clue:" + id] = text
	AudioManager.play("clue")
	DebugLog.ev("clue", "获得线索", {"id": id, "总数": _clue_count()})
	_log_line("[color=#ffd75e]【线索】%s[/color]" % text)
	_refresh_hud()

func _log_line(text: String) -> void:
	if _log:
		_log.append_text(text + "\n\n")

func _on_log_line(text: String) -> void:
	_log_line(text)

# ——— 噪音机制（世界 1 独特机制 · 「丧尸含量」的引擎）———
# 安静时楼层是稀疏的；一吵，整层都会活过来。
# 开枪 +3 / 破门 +2 / 战斗每回合 +1；每 5 秒自然衰减 1。

const NOISE_MAX := 20
const NOISE_DECAY_SEC := 5.0
const NOISE_T1 := 6       # 招来逐尸
const NOISE_T2 := 10      # 招来爬行者
const NOISE_T3 := 14      # 尸潮（3 只）

var _noise := 0
var _noise_decay := 0.0
var _spawned_count := 0

func _add_noise(amount: int, reason: String = "") -> void:
	if amount <= 0 or _battle != null:
		return
	_noise = mini(NOISE_MAX, _noise + amount)
	AudioManager.play("noise", {"throttle": 1500})
	if reason != "":
		_log_line("[color=#ffb3b3]噪音 +%d（%s）　当前 %d[/color]" % [amount, reason, _noise])
	_refresh_hud()
	_check_noise_spawn()

func _tick_noise(delta: float) -> void:
	if _noise <= 0:
		return
	_noise_decay += delta
	if _noise_decay >= NOISE_DECAY_SEC:
		_noise_decay = 0.0
		_noise -= 1
		_refresh_hud()

## 阈值触发：越吵，来的越多
func _check_noise_spawn() -> void:
	if _noise >= NOISE_T3:
		_log_line("[color=#ff5e5e]【尸潮】走廊两头和天花板上同时传来拖行声。[/color]")
		for i in 3:
			_spawn_noise_enemy("walker" if i % 2 == 0 else "zombie")
		_noise = NOISE_T3 - 3          # 触发后回落，避免连续刷
	elif _noise >= NOISE_T2:
		_spawn_noise_enemy("crawler")
		_noise = NOISE_T2 - 3
	elif _noise >= NOISE_T1:
		_spawn_noise_enemy("walker")
		_noise = NOISE_T1 - 3
	_refresh_hud()

## 从离玩家最远的空格刷一只 —— 它们是「顺着声音找过来的」
func _spawn_noise_enemy(id: String) -> void:
	var spot := _noise_spawn_cell()
	if spot == Vector2i(-1, -1):
		return
	var uid := "spawn_%d" % _spawned_count
	_spawned_count += 1
	var node := _make_entity(Enemies.name_of(id), Color(0.55, 0.3, 0.25), true, false,
		"res://assets/sprites/w1/zombie_idle.png")
	# 朝向玩家：它们是冲着你来的
	var d := _player_pos - spot
	var facing := Vector2i.ZERO
	if absi(d.x) >= absi(d.y):
		facing = Vector2i(signi(d.x), 0)
	else:
		facing = Vector2i(0, signi(d.y))
	if facing == Vector2i.ZERO:
		facing = Vector2i(0, 1)
	_enemy_nodes[uid] = {"node": node, "def_id": id, "pos": spot, "hp": 0, "facing": facing}
	_entities.append({"node": node, "pos": spot, "kind": "enemy", "uid": uid})
	_log_line("[color=#ff8c66]%s 被声音引来了。[/color]" % Enemies.name_of(id))

## 选一个「离玩家 ≥6 格、可通行、且没被占用」的格子作为刷怪点
func _noise_spawn_cell() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := -1
	for y in _grid.rows():
		for x in _grid.cols():
			var p := Vector2i(x, y)
			if not _grid.is_walkable(p) or not _cell_free(p):
				continue
			var d := _manhattan(p, _player_pos)
			if d >= 6 and d > best_d:
				best_d = d
				best = p
	return best

func _cell_free(p: Vector2i) -> bool:
	if p == _player_pos:
		return false
	for uid in _enemy_nodes:
		if Vector2i(_enemy_nodes[uid]["pos"]) == p:
			return false
	for nid in _npc_nodes:
		if Vector2i(_npc_nodes[nid]["pos"]) == p:
			return false
	return true

# ——— 战场迷雾 ———
# 只照亮玩家「视野半径内且通视」的格子，其余压暗。
# 墙会挡视线，所以房间里看不见拐角后面 —— 这是恐怖感的主要来源。

const VIEW_RADIUS := 6
var _fog_at := Vector2i(-99, -99)      # 上次算迷雾时玩家在哪

func _refresh_fog() -> void:
	var cells: Array[Vector2i] = []
	for y in _grid.rows():
		for x in _grid.cols():
			var p := Vector2i(x, y)
			if _manhattan(p, _player_pos) > VIEW_RADIUS:
				continue
			if not _grid.has_line_of_sight(_player_pos, p):
				continue
			cells.append(p)
	_map.set_visible_cells(cells, true)
	_fade_entities_by_fog()

## 视野外的实体也要压暗 —— 否则黑暗里的敌人一眼可见，迷雾就白做了。
## 顺便：名字标签只在视野内显示（相邻格名字会互相重叠，且黑了还标名字很出戏）。
func _fade_entities_by_fog() -> void:
	for e in _entities:
		if String(e.get("kind", "")) == "player":
			continue
		var n = e.get("node")
		if n == null or not is_instance_valid(n):
			continue
		var p: Vector2i = e.get("pos", Vector2i.ZERO)
		var lit: bool = _manhattan(p, _player_pos) <= VIEW_RADIUS \
			and _grid.has_line_of_sight(_player_pos, p)
		n.modulate = Color(1, 1, 1, 1) if lit else Color(0.20, 0.22, 0.28, 1)
		if n.has_meta("name_label"):
			var lb = n.get_meta("name_label")
			if lb != null and is_instance_valid(lb):
				lb.visible = lit and String(lb.text) != ""

func _visible_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in _grid.rows():
		for x in _grid.cols():
			var p := Vector2i(x, y)
			if _manhattan(p, _player_pos) <= VIEW_RADIUS and _grid.has_line_of_sight(_player_pos, p):
				cells.append(p)
	return cells

# ——— 回合制：玩家动一回合，敌人再动一回合 ———
# 玩家结束行动 → 每个敌人走一步 → 回到玩家回合。
# 这样「敌人什么时候转身」是能观察、能计算的，潜行才有策略。

var _turn := 1
var _enemy_acting := false

func turn_of() -> int:
	return _turn

## 玩家行动结束 → 敌人回合
func _end_player_turn() -> void:
	if _battle != null or _enemy_acting:
		return
	_enemy_acting = true
	_refresh_hud()
	# 玩家原地不动也可能被转过来的敌人发现
	_update_enemy_alert()
	if _check_engagement():
		_enemy_acting = false
		_refresh_hud()
		return
	await _enemy_turn()
	_turn += 1
	if _noise > 0:
		_noise -= 1                     # 回合制下噪音按回合衰减
	_enemy_acting = false
	_refresh_hud()
	if _battle == null:
		_log_line("[color=#ffd75e]—— 第 %d 回合 · 你的行动 ——[/color]" % _turn)

## 敌人回合：发现你的追过来，没发现的按巡逻路线走（没路线的原地不动）。
func _enemy_turn() -> void:
	var uids: Array = _enemy_nodes.keys()
	for uid in uids:
		if _battle != null:
			return                       # 中途接敌就中断，交给战斗
		if not _enemy_nodes.has(uid):
			continue
		var e: Dictionary = _enemy_nodes[uid]
		if bool(e.get("alerted", false)):
			_chase_step(String(uid), e)  # 追击：朝你（或最后已知位置）走一格，贴上就开战
		else:
			var route: Array = e.get("patrol", [])
			if route.is_empty():
				continue
			_patrol_step(String(uid), e, route)
		_refresh_sight()
		if _battle != null:
			return
		await get_tree().create_timer(0.30).timeout

func _patrol_step(uid: String, e: Dictionary, route: Array) -> void:
	var idx := int(e.get("patrol_idx", 0))
	var target := Vector2i(route[idx % route.size()])
	var cur: Vector2i = e["pos"]
	if cur == target:
		e["patrol_idx"] = (idx + 1) % route.size()
		return
	# 朝目标走一格（4 方向优先走差距大的那轴）
	var d := target - cur
	var step := Vector2i.ZERO
	if absi(d.x) >= absi(d.y):
		step = Vector2i(signi(d.x), 0)
	else:
		step = Vector2i(0, signi(d.y))
	var nxt := cur + step
	if not _grid.is_walkable(nxt) or not _cell_free(nxt):
		e["patrol_idx"] = (idx + 1) % route.size()     # 走不通就换下一个巡逻点
		return
	e["pos"] = nxt
	e["facing"] = step
	_position_entity(e["node"], nxt)
	for ent in _entities:
		if String(ent.get("uid", "")) == uid:
			ent["pos"] = nxt
			break
	_sort_entities()
	_refresh_sight()
	# 巡逻时撞见玩家 → 立刻接敌
	if _in_enemy_sight(uid):
		_check_engagement()

func _process(delta: float) -> void:
	if _exit_lock > 0.0:
		_exit_lock = maxf(0.0, _exit_lock - delta)
	_check_room_exit()
	# 玩家换格才重算迷雾（每帧算太浪费）
	if _player_pos != _fog_at:
		_fog_at = _player_pos
		_refresh_fog()

func _refresh_hud() -> void:
	if not _player:
		return
	_hud_hp.text = "生命 %d/%d" % [_player.hp, _player.max_hp()]
	_hud_will.text = "意志 %d/%d" % [_player.will, _player.max_will()]
	var chased := 0
	for uid in _enemy_nodes:
		if bool(_enemy_nodes[uid].get("alerted", false)):
			chased += 1
	var chase_txt := "" if chased == 0 else "　⚠ %d 个在追你" % chased
	_hud_pts.text = "积分 %d　噪音 %d　回合 %d%s" % [Game.points, _noise, _turn, chase_txt]
	var qs: Array[String] = []
	for qid in _quests.defs:
		if _quests.is_active(StringName(qid)):
			qs.append(String(QuestsDef.get_def(String(qid)).get("name", qid)))
	_hud_quest.text = "【%s】任务：%s" % [R001Rooms.room_name(_room_id), "　|　".join(qs) if not qs.is_empty() else "无"]

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
