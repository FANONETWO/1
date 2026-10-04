class_name Worlds
extends RefCounted
## 世界注册表（阶段 A 地基）：所有可进入世界的**唯一入口**。
##
## 主神空间卡片、场景加载、战斗场地、数据校验都从这里取数据，
## 不再硬编码任何具体副本——这是「五界自由进入」的架构基础。
##
## 注意：世界 2–5 目前是**骨架数据**（1 个阶段、占位敌人、待填充文案），
## 目的是先把注册表与校验跑通；内容按路线图逐界填充。

const R001Map := preload("res://scenarios/r001_apartment/map_data.gd")

# ——— 各世界骨架地图（12×8）———

const MAP_XIANXIA: Array[String] = [
	"############",
	"#F........F#",
	"#..........#",
	"#...R..R...#",
	"#..........#",
	"#F........F#",
	"#..........#",
	"############",
]

const MAP_SCIFI: Array[String] = [
	"############",
	"#C........C#",
	"#..........#",
	"#..X....X..#",
	"#..........#",
	"#C........C#",
	"#..........#",
	"############",
]

const MAP_MAGIC: Array[String] = [
	"############",
	"#F..T...F..#",
	"#..........#",
	"#..T....T..#",
	"#..........#",
	"#F..T...F..#",
	"#..........#",
	"############",
]

const MAP_WASTE: Array[String] = [
	"############",
	"#R........R#",
	"#..........#",
	"#..XX...X..#",
	"#..........#",
	"#R...T....R#",
	"#..........#",
	"############",
]

# ——— 车库与大厅（惊变公寓阶段 2 / 3）———

const MAP_GARAGE: Array[String] = [
	"####################",
	"#R.......#........R#",
	"#........#.........#",
	"#..R.....#....R....#",
	"#........D.........#",
	"#........#.........#",
	"#..XX....#....T....#",
	"#........#.........#",
	"#........D.........#",
	"#........#.........#",
	"#...R....#....R....#",
	"#........#....S....#",
	"#........#.........#",
	"####################",
]

const MAP_LOBBY: Array[String] = [
	"################",
	"#..............#",
	"#..R........R..#",
	"#..............#",
	"#....T....T....#",
	"#..............#",
	"#..............#",
	"#..T........T..#",
	"#..............#",
	"#.......EE.....#",
	"#..............#",
	"################",
]

static var _DATA: Array[Dictionary] = [
	# ————————————————— 世界 1 · 惊变公寓（完整三阶段，迁移自现有 r001）—————————————————
	{
		"id": "w1_apartment",
		"name": "惊变公寓",
		"genre": "恐怖 · 生化",
		"rating": "D",
		"theme_color": Color(0.45, 0.55, 0.72),
		"mechanic": "noise_infection",
		"intro": "深夜，你在一间陌生公寓的走廊里睁开眼。\n腕上的轮回手表闪着红光——\n『新人生成完毕。任务发布：\n【主线】在尸潮吞没公寓前，找到安全出口钥匙并撤离。\n【支线】救援、调查，尽你所能。\n死亡即回归，失败扣除全部奖励。祝你好运。』\n\n远处传来拖沓的脚步声，和某种啃食的声响。",
		"quests": [
			{"id": "escape", "kind": "main", "name": "活着离开",
				"desc": "在尸潮吞没整栋楼之前，找到一楼安全出口的钥匙并离开公寓。",
				"hint_active": "找到公寓一层的安全出口钥匙，前往大门撤离。", "reward_points": 20},
			{"id": "save_chen", "kind": "side", "name": "老邻居",
				"desc": "402 的陈叔把自己锁在屋里。如果你能拿到他需要的降压药，他会告诉你一些事。",
				"hint_active": "在值班室药柜找到降压药，交给陈叔。", "reward_points": 10},
			{"id": "clear_lobby", "kind": "side", "name": "清道夫",
				"desc": "尸王堵住了大门。要撤离，就得先解决它。",
				"hint_active": "击败盘踞在大厅的尸王。", "reward_points": 25},
		],
		"stages": [
			{
				"id": "floor1", "title": "公寓一层",
				"tiles": R001Map.TILES, "spawn": R001Map.SPAWN, "exit": R001Map.EXIT,
				"objective": "拿到安全出口钥匙",
				"enemies": R001Map.ENEMIES, "npcs": R001Map.NPCS, "spots": R001Map.SPOTS,
				"transition": {"condition": "has_item:apartment_key", "next": "garage",
					"text": "钥匙到手的瞬间，整栋楼的灯闪了一下。楼梯间的封条被人从里面撕开了——车库方向传来金属摩擦声。"},
			},
			{
				"id": "garage", "title": "地下车库",
				"tiles": MAP_GARAGE, "spawn": Vector2i(1, 1), "exit": Vector2i(14, 11),
				"objective": "搜索车库，找到通往大厅的楼梯",
				"enemies": [
					{"id": "crawler", "pos": Vector2i(3, 6)},
					{"id": "crawler", "pos": Vector2i(16, 3)},
					{"id": "zombie", "pos": Vector2i(6, 10)},
					{"id": "zombie", "pos": Vector2i(13, 6)},
				],
				"npcs": {},
				"spots": {
					"freezer": {"pos": Vector2i(3, 11), "label": "冰柜（血清）"},
					"breaker": {"pos": Vector2i(16, 9), "label": "配电箱"},
				},
				"transition": {"condition": "stage_clear", "next": "lobby",
					"text": "楼梯间的应急灯亮了。上面就是大厅——以及堵在消防门前的那个巨影。"},
			},
			{
				"id": "lobby", "title": "一层大厅",
				"tiles": MAP_LOBBY, "spawn": Vector2i(1, 1), "exit": Vector2i(8, 9),
				"objective": "击败尸王，撞开消防门撤离",
				"enemies": [
					{"id": "brute", "pos": Vector2i(8, 3)},
					{"id": "zombie", "pos": Vector2i(3, 8)},
					{"id": "zombie", "pos": Vector2i(13, 8)},
				],
				"npcs": {},
				"spots": {},
				"transition": {},
			},
		],
		"settlement": {
			"perfect": {"title": "完美撤离",
				"body": "你带着所有能带走的人与真相，撞开消防门冲进了夜色。\n身后，公寓楼在火光与嘶吼中坍塌。"},
			"normal": {"title": "惊险撤离",
				"body": "你抢在尸潮合拢前逃出了公寓。大门在身后轰然关上，里面传来无数双手挠门的声音。"},
			"death": {"title": "陨落",
				"body": "你的意识沉入黑暗。\n再次睁眼时，你回到主神空间的白色穹顶下。"},
		},
	},

	# ————————————————— 世界 2 · 剑影仙途（骨架）—————————————————
	{
		"id": "w2_xianxia",
		"name": "剑影仙途",
		"genre": "仙侠 · 修真",
		"rating": "C",
		"theme_color": Color(0.42, 0.72, 0.58),
		"mechanic": "spirit_arts",
		"intro": "灵气自山门倒灌而下，云海被染成血色。\n『轮回者，青云剑宗山门告急。魔道血祭已成，剑冢剑胎若落入其手，此界将开血河。』",
		"quests": [
			{"id": "hold_gate", "kind": "main", "name": "剑影仙途",
				"desc": "阻止魔道血祭，夺回镇派剑胎。",
				"hint_active": "御敌于山门，寻找通往剑冢的路。", "reward_points": 35},
			{"id": "save_elder", "kind": "side", "name": "传功长老",
				"desc": "传功长老被困在剑冢深处，救他可得功法进阶。",
				"hint_active": "在剑冢秘境中找到被困的长老。", "reward_points": 15},
		],
		"stages": [
			{
				"id": "gate", "title": "山门石阶（骨架）",
				"tiles": MAP_XIANXIA, "spawn": Vector2i(1, 1), "exit": Vector2i(10, 6),
				"objective": "守住山门，寻找剑冢入口",
				"enemies": [
					{"id": "zombie", "pos": Vector2i(5, 3)},
					{"id": "crawler", "pos": Vector2i(8, 5)},
				],
				"npcs": {"elder": {"pos": Vector2i(9, 1), "label": "传功长老"}},
				"spots": {"stele": {"pos": Vector2i(4, 5), "label": "断剑石碑"}},
				"transition": {},
			},
		],
		"settlement": {
			"perfect": {"title": "剑胎归位", "body": "（待内容填充）"},
			"normal": {"title": "全身而退", "body": "（待内容填充）"},
			"death": {"title": "身死道消", "body": "（待内容填充）"},
		},
	},

	# ————————————————— 世界 3 · 零号协议（骨架）—————————————————
	{
		"id": "w3_scifi",
		"name": "零号协议",
		"genre": "科幻 · 赛博",
		"rating": "C",
		"theme_color": Color(0.30, 0.68, 0.80),
		"mechanic": "shield_intrusion",
		"intro": "轨道空间站『零号』的警报已经响了四十小时。\n『主控 AI 判定人类为污染源，清洗协议启动。轮回者，切断它。』",
		"quests": [
			{"id": "shut_ai", "kind": "main", "name": "零号协议",
				"desc": "关停失控的主控 AI，夺取逃生舱。",
				"hint_active": "恢复供电，前往数据中心。", "reward_points": 35},
			{"id": "save_engineer", "kind": "side", "name": "幸存工程师",
				"desc": "被困工程师掌握入侵权限。",
				"hint_active": "在居住舱找到被困的工程师。", "reward_points": 15},
		],
		"stages": [
			{
				"id": "hab", "title": "居住舱（骨架）",
				"tiles": MAP_SCIFI, "spawn": Vector2i(1, 1), "exit": Vector2i(10, 6),
				"objective": "恢复应急供电",
				"enemies": [
					{"id": "zombie", "pos": Vector2i(5, 3)},
					{"id": "crawler", "pos": Vector2i(8, 5)},
				],
				"npcs": {"engineer": {"pos": Vector2i(9, 1), "label": "工程师"}},
				"spots": {"terminal": {"pos": Vector2i(4, 5), "label": "维修终端"}},
				"transition": {},
			},
		],
		"settlement": {
			"perfect": {"title": "协议终止", "body": "（待内容填充）"},
			"normal": {"title": "弃船而生", "body": "（待内容填充）"},
			"death": {"title": "真空葬", "body": "（待内容填充）"},
		},
	},

	# ————————————————— 世界 4 · 黑月学院（骨架）—————————————————
	{
		"id": "w4_magic",
		"name": "黑月学院",
		"genre": "魔幻 · 学院",
		"rating": "B",
		"theme_color": Color(0.58, 0.42, 0.78),
		"mechanic": "element_cast",
		"intro": "黑月悬于学院尖塔之上，禁书库的封印正在剥落。\n『师生已被禁咒扭曲。轮回者，封印裂隙——顺便，把院长带回来。』",
		"quests": [
			{"id": "seal_rift", "kind": "main", "name": "封印黑月",
				"desc": "穿过回廊与禁书库，封印黑月裂隙。",
				"hint_active": "前往禁书库，寻找第一处裂隙。", "reward_points": 40},
			{"id": "save_students", "kind": "side", "name": "魔化学徒",
				"desc": "被禁咒扭曲的学徒或许还能救回来。",
				"hint_active": "在不杀死学徒的前提下制服他们。", "reward_points": 20},
		],
		"stages": [
			{
				"id": "corridor", "title": "学院回廊（骨架）",
				"tiles": MAP_MAGIC, "spawn": Vector2i(1, 1), "exit": Vector2i(10, 6),
				"objective": "穿过回廊，进入禁书库",
				"enemies": [
					{"id": "zombie", "pos": Vector2i(5, 3)},
					{"id": "crawler", "pos": Vector2i(8, 5)},
				],
				"npcs": {"apprentice": {"pos": Vector2i(9, 1), "label": "魔化学徒"}},
				"spots": {"shelf": {"pos": Vector2i(4, 5), "label": "倒塌的书架"}},
				"transition": {},
			},
		],
		"settlement": {
			"perfect": {"title": "黑月封印", "body": "（待内容填充）"},
			"normal": {"title": "逃离学院", "body": "（待内容填充）"},
			"death": {"title": "化为禁咒", "body": "（待内容填充）"},
		},
	},

	# ————————————————— 世界 5 · 灰烬公路（骨架）—————————————————
	{
		"id": "w5_wasteland",
		"name": "灰烬公路",
		"genre": "废土 · 末世",
		"rating": "B",
		"theme_color": Color(0.66, 0.56, 0.34),
		"mechanic": "radiation_durability",
		"intro": "核战三年后，灰烬公路只剩风、沙与辐射计数器。\n『幸存者营地的装甲车抛锚了。轮回者，把车修好，带他们过去。』",
		"quests": [
			{"id": "fix_convoy", "kind": "main", "name": "灰烬公路",
				"desc": "修好装甲车，护送幸存者穿越辐射区。",
				"hint_active": "在加油站搜集燃油与零件。", "reward_points": 40},
			{"id": "purify_water", "kind": "side", "name": "净水",
				"desc": "营地的净水快见底了。",
				"hint_active": "回收三罐净水。", "reward_points": 20},
		],
		"stages": [
			{
				"id": "station", "title": "废弃加油站（骨架）",
				"tiles": MAP_WASTE, "spawn": Vector2i(1, 1), "exit": Vector2i(10, 6),
				"objective": "搜集燃油与零件",
				"enemies": [
					{"id": "zombie", "pos": Vector2i(5, 3)},
					{"id": "crawler", "pos": Vector2i(8, 5)},
				],
				"npcs": {"survivor": {"pos": Vector2i(9, 1), "label": "幸存者"}},
				"spots": {"ruin": {"pos": Vector2i(4, 5), "label": "塌陷的便利店"}},
				"transition": {},
			},
		],
		"settlement": {
			"perfect": {"title": "公路尽头", "body": "（待内容填充）"},
			"normal": {"title": "活着穿越", "body": "（待内容填充）"},
			"death": {"title": "倒在灰烬里", "body": "（待内容填充）"},
		},
	},
]

# ——— 查询接口 ———

static func all() -> Array[WorldDef]:
	var out: Array[WorldDef] = []
	for d in _DATA:
		out.append(WorldDef.create(d))
	return out

static func ids() -> Array[String]:
	var out: Array[String] = []
	for d in _DATA:
		out.append(String(d.get("id", "")))
	return out

static func count() -> int:
	return _DATA.size()

## 取世界定义；不存在返回 null。
static func get_world(id: String) -> WorldDef:
	for d in _DATA:
		if String(d.get("id", "")) == id:
			return WorldDef.create(d)
	return null

static func has(id: String) -> bool:
	return get_world(id) != null

## 卡片摘要（主神空间用），不含地图等重数据。
static func card_summary(id: String) -> Dictionary:
	var w := get_world(id)
	if w == null:
		return {}
	return {
		"id": w.id, "name": w.name, "genre": w.genre, "rating": w.rating,
		"theme_color": w.theme_color, "stages": w.stage_count(),
		"quests": w.quests.size(), "mechanic": w.mechanic,
	}

## 校验全部世界；返回问题列表（空数组表示全部合法）。
static func validate_all() -> Array[String]:
	var errs: Array[String] = []
	var seen := {}
	for d in _DATA:
		var w := WorldDef.create(d)
		if w.id == "":
			errs.append("存在无 id 的世界定义")
			continue
		if seen.has(w.id):
			errs.append("世界 id 重复：%s" % w.id)
		seen[w.id] = true
		errs.append_array(w.validate())
	return errs
