extends Node
## 全局状态：轮回者数据、奖励点、世界进度、队伍、通关记录与存档。
## 存档路径 user://save.json；存档带版本号，旧档自动迁移。
##
## v1：单副本（r001_apartment）时代的扁平字段。
## v2：引入 world_progress（每界阶段/通关/结局/线索/机制状态）、xp、team、rested。

const SAVE_PATH := "user://save.json"
## v1：单副本扁平字段。v2：world_progress / xp / team。v3：游戏模式 + 成绩按模式分开。
const SAVE_VERSION := 3

# ——— 游戏模式 ———
## solo = 独狼：一个人下副本，奖励点 ×1.5 —— 这是**风险溢价**（没有队友分摊风险、
##        没有救援、失控了没人拦），不是「单机补偿」，结算面板要写明白。
## team = 四人小队：标准奖励 + 三张预设队友卡（单机由 AI 接管；联机时这些槽位换成真人）。
const MODE_SOLO := &"solo"
const MODE_TEAM := &"team"
const TEAM_MAX := 4                # 含玩家本人
const SOLO_REWARD_MULT := 1.5

var player: Character = null          # 轮回者（建卡后生成）
var points: int = 0                   # 奖励点（分数）
var xp: int = 0                       # 经验值（规则书：1XP = 100 分）
var upgrades: Array[String] = []      # 已兑换强化 id
var cleared: Array[String] = []       # 已通关副本 id（v1 兼容字段）
var best_endings: Dictionary = {}     # 副本id -> 结局id（v1 兼容字段）
var mode: StringName = MODE_SOLO      # 游戏模式：solo / team（建卡时选，入存档）
var team: Array = []                  # 队伍：玩家以外的队友（Character 对象，团队模式 1~3 人）
var rested: bool = false              # 本次回到主神空间后是否已免费休整
var player_dead: bool = false         # P4：基因崩溃导致角色永久阵亡
var migrated_from: int = 0            # 本次读档来自哪个旧版本（0 表示无需迁移）
var pending_scenario_id: StringName = &""  # 主神空间 -> 世界 传递
var scenario_state: Dictionary = {}   # 当前世界内的临时进度（结算后清理）

# ——— 副本进度（唯一状态源）———
# 只记录「发生了什么」，界面显示全部由它派生，避免状态散落导致尸体复活：
#   killed : "room/uid"  -> true   已击杀的敌人
#   taken  : "room/spot" -> true   已调查/已拾取的交互点
#   flags  : 名称 -> 值             任务与对话标记
#   room / pos                     当前所在箱庭与格子
var dungeon: Dictionary = {}          # scenario_id -> 上面那份进度

## 取（必要时创建）某副本的进度表 —— 所有状态读写的唯一入口
func dungeon_state(scenario_id: String) -> Dictionary:
	if not dungeon.has(scenario_id):
		dungeon[scenario_id] = {"killed": {}, "taken": {}, "flags": {}, "room": "", "pos": [0, 0]}
	var d: Dictionary = dungeon[scenario_id]
	for k in ["killed", "taken", "flags"]:
		if not d.has(k):
			d[k] = {}
	return d

## 标记敌人已死（唯一写入点）
func mark_killed(scenario_id: String, uid: String) -> void:
	dungeon_state(scenario_id)["killed"][uid] = true

func is_killed(scenario_id: String, uid: String) -> bool:
	return dungeon_state(scenario_id)["killed"].has(uid)

## 标记交互点已用（唯一写入点）
func mark_taken(scenario_id: String, key: String) -> void:
	dungeon_state(scenario_id)["taken"][key] = true

func is_taken(scenario_id: String, key: String) -> bool:
	return dungeon_state(scenario_id)["taken"].has(key)

## 记录玩家当前所在的箱庭与格子（存档用）
func set_dungeon_pos(scenario_id: String, room: String, pos: Vector2i) -> void:
	var d := dungeon_state(scenario_id)
	d["room"] = room
	d["pos"] = [pos.x, pos.y]

## 副本结束（结算/通关）时清空进度
func clear_dungeon(scenario_id: String) -> void:
	dungeon.erase(scenario_id)
var world_progress: Dictionary = {}   # world_id -> {stage, cleared, best_ending, clues, mechanics}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## 只读存档中的阵亡标记（不改变内存状态），供主菜单显示用。
func peek_player_dead() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return false
	return bool((data as Dictionary).get("player_dead", false))

func new_game() -> void:
	player = null
	points = 0
	xp = 0
	upgrades = []
	cleared = []
	best_endings = {}
	team = []
	rested = false
	player_dead = false
	migrated_from = 0
	pending_scenario_id = &""
	scenario_state = {}
	dungeon = {}   # 新轮回不得继承上一轮的副本进度（击杀/拾取/旗标），否则新角色开局即"已通关"
	world_progress = {}
	save_game()

## 建卡完成后调用：写入角色并初始化。
func set_player(c: Character) -> void:
	player = c
	save_game()

# ——— 游戏模式 ———

func set_mode(m: StringName) -> void:
	mode = MODE_TEAM if m == MODE_TEAM else MODE_SOLO
	save_game()

func is_team() -> bool:
	return mode == MODE_TEAM

func mode_name() -> String:
	return "四人小队" if is_team() else "独狼"

## 奖励倍率：独狼 ×1.5（风险溢价：没人替你分摊风险）
func reward_multiplier() -> float:
	return SOLO_REWARD_MULT if mode == MODE_SOLO else 1.0

## 成绩要**按模式分开记**：否则独狼的 ×1.5 会永久污染团队榜，
## 团队玩家再怎么打也追不上，榜就废了。
func best_key(scenario_id: String) -> String:
	return "%s@%s" % [scenario_id, mode]

## 该副本在当前模式下的最佳结局
func best_ending_of_mode(scenario_id: String) -> String:
	return String(best_endings.get(best_key(scenario_id), ""))

## 队友（Character 对象数组；独狼为空）
func allies() -> Array:
	return team

func set_team(list: Array) -> void:
	team = []
	for c in list:
		if c is Character:
			team.append(c)
	save_game()

func finish_scenario(result: Dictionary) -> void:
	points += int(result.get("points", 0))
	var sid := String(result.get("scenario_id", ""))
	var wid := world_id_of(sid)
	if sid != "" and bool(result.get("cleared", false)) and not cleared.has(sid):
		cleared.append(sid)
	var eid := String(result.get("ending_id", ""))
	if sid != "" and eid != "":
		var bk := best_key(sid)
		if not best_endings.has(bk) or _ending_rank(eid) > _ending_rank(String(best_endings[bk])):
			best_endings[bk] = eid
	# 同步世界进度（v2 结构）
	if wid != "":
		var st := world_state(wid)
		if bool(result.get("cleared", false)):
			st["cleared"] = true
		if eid != "" and _ending_rank(eid) >= _ending_rank(String(st.get("best_ending", ""))):
			st["best_ending"] = eid
	rested = false   # 回到主神空间，休整次数重置
	save_game()
	EventBus.points_changed.emit(points)

func _ending_rank(eid: String) -> int:
	match eid:
		"perfect":
			return 3
		"normal":
			return 2
		_:
			return 0

# ——— 世界进度 ———

## 旧 id 到新世界 id 的映射（兼容 v1 的单副本记录）。
func world_id_of(scenario_id: String) -> String:
	match scenario_id:
		"r001_apartment":
			return "w1_apartment"
		_:
			return scenario_id

## 取（必要时创建）某世界的进度状态。
func world_state(world_id: String) -> Dictionary:
	if not world_progress.has(world_id):
		world_progress[world_id] = {
			"stage": 0, "cleared": false, "best_ending": "",
			"clues": [], "mechanics": {},
		}
	return world_progress[world_id]

func set_world_stage(world_id: String, stage: int) -> void:
	world_state(world_id)["stage"] = stage

func world_stage(world_id: String) -> int:
	return int(world_state(world_id).get("stage", 0))

func is_world_cleared(world_id: String) -> bool:
	return bool(world_state(world_id).get("cleared", false))

func best_ending_of(world_id: String) -> String:
	return String(world_state(world_id).get("best_ending", ""))

## 主神空间休整：恢复生命与意志力（对应规则书「每场影片后停 10 天」）。
func rest_full() -> void:
	if player == null:
		return
	player.hp = player.max_hp()
	player.will = player.max_will()
	rested = true
	save_game()

# ——— 存档 ———

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"points": points,
		"xp": xp,
		"upgrades": upgrades,
		"cleared": cleared,
		"best_endings": best_endings,
		"mode": String(mode),
		"team": team.map(func(c): return (c as Character).to_dict() if c is Character else {}),
		"rested": rested,
		"player_dead": player_dead,
		"world_progress": world_progress,
		"dungeon": dungeon,
	}
	if player != null:
		data["player"] = player.to_dict()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return false
	var version := int(data.get("version", 1))
	points = int(data.get("points", 0))
	xp = int(data.get("xp", 0))
	upgrades.assign(data.get("upgrades", []))
	cleared.assign(data.get("cleared", []))
	best_endings = data.get("best_endings", {})
	mode = StringName(String(data.get("mode", "solo")))
	# 队友：入档是 dict，出档还原成 Character（团队模式 1~3 人）
	team = []
	for td in data.get("team", []):
		if not (td is Dictionary) or (td as Dictionary).is_empty():
			continue
		var tc := Character.new()
		if tc.from_dict(td):
			team.append(tc)
	rested = bool(data.get("rested", false))
	player_dead = bool(data.get("player_dead", false))
	world_progress = data.get("world_progress", {})
	dungeon = data.get("dungeon", {})
	if version < SAVE_VERSION:
		migrated_from = version
		_migrate(version)
	if data.has("player"):
		player = Character.new()
		if not player.from_dict(data["player"]):
			player = null
			return false
	return player != null

## 旧档迁移：把 v1 的单副本记录折算成 w1_apartment 的世界进度。
func _migrate(from_version: int) -> void:
	if from_version < 2:
		var st := world_state("w1_apartment")
		if cleared.has("r001_apartment"):
			st["cleared"] = true
		if best_endings.has("r001_apartment") and String(st.get("best_ending", "")) == "":
			st["best_ending"] = String(best_endings["r001_apartment"])
	if from_version < 3:
		# v2 及以前没有「模式」概念，那时的成绩都属于独狼时代 → 键名补上 @solo。
		# 注意这段必须放在 v2 迁移**之后**：v2 的检查用的还是旧键名。
		var migrated := {}
		for k in best_endings:
			var key := String(k)
			migrated[key if key.contains("@") else "%s@%s" % [key, MODE_SOLO]] = best_endings[k]
		best_endings = migrated

func go_hub() -> void:
	get_tree().change_scene_to_file("res://ui/hub.tscn")
