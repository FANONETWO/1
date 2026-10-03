class_name R001Rooms
extends RefCounted
## 「惊变公寓」箱庭数据（单房间级别 · 共 12 间）。
##
## ——— 契约（重要）———
##   exits[方向] = { "room": 目标箱庭, "cell": **本房间**的出口格 }
##   玩家站到 cell 上 → 切到 room；落点由 _entry_cell_from() 在目标房间里反查
##   （找到「能回到来路」的那扇门，落在它内侧一格）
##
##   因此：**cell 必须与地图上的 'D' 门位置一致**，否则走不出去。
##
## ——— 连接图 ———
##              402 ── guest
##               │       │
##   storage ── 北走廊 ── duty_room
##               │
##             大堂 ── 南走廊 ── empty / utility
##               │
##            安全出口
##
## 地形字符：# 墙 / . 地板 / D 门 / T 桌 / B 床 / C 柜 / S 楼梯 / E 出口 / X 危险区

const ROOMS := {
	# ═══════════ 起点：楼梯间（安全，无敌人） ═══════════
	"stair_hall": {
		"name": "楼梯间",
		"intro": "楼梯被卷帘门封死了，焊口还是新的。只有一条路：往里。",
		"tiles": [
			"##########",
			"#S.......#",
			"#........#",
			"#...T....#",
			"#........#",
			"#........#",
			"#####D####",
		],
		"enemies": [],
		"npcs": [],
		"spots": [{"id": "stairs", "pos": Vector2i(1, 1), "label": "被封的楼梯"}],
		"exits": {"south": {"room": "corridor_n", "cell": Vector2i(5, 6)}},
	},

	# ═══════════ 北侧走廊（横向主干 · 6 个出口） ═══════════
	"corridor_n": {
		"name": "北侧走廊",
		"intro": "应急灯每隔三米一盏，绿光，够你看清地面。地上的拖痕是湿的。",
		"tiles": [
			"####D###############",
			"#D................D#",
			"#..................#",
			"#..................#",
			"####D####D####D#####",
		],
		"enemies": [
			{"id": "zombie", "pos": Vector2i(7, 2), "facing": Vector2i(1, 0),
				"patrol": [Vector2i(4, 2), Vector2i(13, 2)]},
			{"id": "walker", "pos": Vector2i(14, 3), "facing": Vector2i(-1, 0),
				"patrol": [Vector2i(10, 3), Vector2i(17, 3)]},
		],
		"npcs": [],
		"spots": [],
		"exits": {
			"north": {"room": "stair_hall", "cell": Vector2i(4, 0)},
			"west": {"room": "storage", "cell": Vector2i(1, 1)},
			"east": {"room": "duty_room", "cell": Vector2i(18, 1)},
			"door_402": {"room": "room_402", "cell": Vector2i(4, 4)},
			"lobby": {"room": "lobby", "cell": Vector2i(9, 4)},
			"guest": {"room": "guest_room", "cell": Vector2i(14, 4)},
		},
	},

	# ═══════════ 储物间（钢管 · 门朝东） ═══════════
	"storage": {
		"name": "储物间",
		"intro": "柜子倒了一地，地上全是碎玻璃。墙角靠着一根钢管。",
		"tiles": [
			"#########",
			"#CC.....#",
			"#.......#",
			"#...T...#",
			"#.......#",
			"#.......D",
		],
		"enemies": [
			{"id": "walker", "pos": Vector2i(6, 2), "facing": Vector2i(-1, 0),
				"patrol": [Vector2i(2, 2), Vector2i(6, 4)]},
		],
		"npcs": [],
		"spots": [
			{"id": "storage_locker", "pos": Vector2i(1, 1), "label": "储物柜"},
			{"id": "medkit_box", "pos": Vector2i(7, 4), "label": "急救箱"},
		],
		"exits": {"east": {"room": "corridor_n", "cell": Vector2i(8, 5)}},
	},

	# ═══════════ 值班室（钥匙 + 日志 + 阿贵 · 门朝西） ═══════════
	"duty_room": {
		"name": "值班室",
		"intro": "日光灯在闪。一个穿制服的人趴在桌上，手还按在键盘上。",
		"tiles": [
			"##########",
			"D........#",
			"#C...T...#",
			"#........#",
			"#...T....#",
			"##########",
		],
		"enemies": [],
		"npcs": [{"id": "agui", "pos": Vector2i(7, 3), "label": "疯子阿贵"}],
		"spots": [
			{"id": "duty_locker", "pos": Vector2i(1, 2), "label": "药柜"},
			{"id": "duty_desk", "pos": Vector2i(5, 2), "label": "值班桌面"},
			{"id": "medkit_box", "pos": Vector2i(8, 4), "label": "急救箱"},
		],
		"exits": {"west": {"room": "corridor_n", "cell": Vector2i(0, 1)}},
	},

	# ═══════════ 402 室（陈叔 · 门朝北） ═══════════
	"room_402": {
		"name": "402 室",
		"intro": "门是防盗门，三道锁全锁着。门缝下透出一线光 —— 里面有人。",
		"tiles": [
			"####D####",
			"#.......#",
			"#..B....#",
			"#.......#",
			"#...T...#",
			"#########",
		],
		"enemies": [],
		"npcs": [{"id": "chen", "pos": Vector2i(4, 3), "label": "陈叔"}],
		"spots": [],
		"exits": {"north": {"room": "corridor_n", "cell": Vector2i(4, 0)}},
	},

	# ═══════════ 客房（伏尸 · 门朝北） ═══════════
	"guest_room": {
		"name": "客房",
		"intro": "床垫散在地上，其中一具「尸体」的姿势，和别人不太一样。",
		"tiles": [
			"####D####",
			"#.......#",
			"#..B.B..#",
			"#.......#",
			"#.......#",
			"#########",
		],
		"enemies": [
			{"id": "cadaver", "pos": Vector2i(3, 2), "facing": Vector2i(0, 1)},
			{"id": "walker", "pos": Vector2i(6, 3), "facing": Vector2i(-1, 0)},
		],
		"npcs": [],
		"spots": [
			{"id": "bed_mattress", "pos": Vector2i(6, 2), "label": "床垫"},
			{"id": "medkit_box", "pos": Vector2i(7, 4), "label": "急救箱"},
		],
		"exits": {"north": {"room": "corridor_n", "cell": Vector2i(4, 0)}},
	},

	# ═══════════ 中央大堂（密度最高 · 3 个出口） ═══════════
	"lobby": {
		"name": "中央大堂",
		"intro": "空间一下子开阔了。两侧的房间里传来拖行声，不止一处。",
		"tiles": [
			"#####D######",
			"#..........#",
			"#..........#",
			"D....X.....D",
			"#..........#",
			"#..........#",
			"############",
		],
		"enemies": [
			{"id": "zombie", "pos": Vector2i(3, 2), "facing": Vector2i(1, 0),
				"patrol": [Vector2i(2, 2), Vector2i(8, 2)]},
			{"id": "walker", "pos": Vector2i(8, 3), "facing": Vector2i(-1, 0),
				"patrol": [Vector2i(8, 3), Vector2i(8, 5), Vector2i(3, 5)]},
			{"id": "screamer", "pos": Vector2i(5, 4), "facing": Vector2i(0, -1)},
		],
		"npcs": [],
		"spots": [],
		"exits": {
			"north": {"room": "corridor_n", "cell": Vector2i(5, 0)},
			"west": {"room": "corridor_s", "cell": Vector2i(0, 3)},
			"east": {"room": "exit_hall", "cell": Vector2i(11, 3)},
		},
	},

	# ═══════════ 南侧走廊（门朝东接大堂） ═══════════
	"corridor_s": {
		"name": "南侧走廊",
		"intro": "比北侧窄。天花板上有一道很长的抓痕，从走廊这头拖到那头。",
		"tiles": [
			"####################",
			"#..................D",
			"#..................#",
			"####D########D######",
		],
		"enemies": [
			{"id": "crawler", "pos": Vector2i(6, 1), "facing": Vector2i(1, 0),
				"patrol": [Vector2i(3, 1), Vector2i(15, 1)]},
			{"id": "hound", "pos": Vector2i(15, 2), "facing": Vector2i(-1, 0),
				"patrol": [Vector2i(11, 2), Vector2i(18, 2)]},
		],
		"npcs": [],
		"spots": [],
		"exits": {
			"east": {"room": "lobby", "cell": Vector2i(19, 1)},
			"empty": {"room": "empty_room", "cell": Vector2i(4, 3)},
			"utility": {"room": "utility", "cell": Vector2i(13, 3)},
		},
	},

	# ═══════════ 空房（床垫 → 护甲 · 门朝北） ═══════════
	"empty_room": {
		"name": "空房",
		"intro": "家具都搬空了，只剩一张床垫。床垫下面鼓着一块。",
		"tiles": [
			"####D####",
			"#.......#",
			"#...B...#",
			"#.......#",
			"#.......#",
			"#########",
		],
		"enemies": [
			{"id": "walker", "pos": Vector2i(2, 3), "facing": Vector2i(1, 0),
				"patrol": [Vector2i(2, 3), Vector2i(6, 3)]},
		],
		"npcs": [],
		"spots": [],
		"exits": {"north": {"room": "corridor_s", "cell": Vector2i(4, 0)}},
	},

	# ═══════════ 杂物间（膨胀者 · 门朝北） ═══════════
	"utility": {
		"name": "杂物间",
		"intro": "拖把、水桶、一具涨得不成样子的东西。它走得很慢 —— 但你别在它旁边开枪。",
		"tiles": [
			"####D####",
			"#C.....C#",
			"#.......#",
			"#...R...#",
			"#.......#",
			"#########",
		],
		"enemies": [
			{"id": "bloater", "pos": Vector2i(4, 2), "facing": Vector2i(0, 1)},
		],
		"npcs": [],
		"spots": [{"id": "seal_912", "pos": Vector2i(7, 4), "label": "墙上的封条"}],
		"exits": {"north": {"room": "corridor_s", "cell": Vector2i(4, 0)}},
	},

	# ═══════════ 安全出口（需钥匙 · 门朝西） ═══════════
	"exit_hall": {
		"name": "安全出口",
		"intro": "消防门就在前面。门内侧有人写过字 —— 已经干成褐色了。",
		"tiles": [
			"##########",
			"D........#",
			"#........#",
			"#...E....#",
			"#........#",
			"##########",
		],
		"enemies": [
			{"id": "zombie", "pos": Vector2i(6, 3), "facing": Vector2i(-1, 0),
				"patrol": [Vector2i(3, 3), Vector2i(7, 2)]},
		],
		"npcs": [],
		"spots": [{"id": "blood_words", "pos": Vector2i(8, 2), "label": "门内侧的血字"}],
		"exits": {"west": {"room": "lobby", "cell": Vector2i(0, 1)}},
	},
}

## 起始箱庭
const START_ROOM := "stair_hall"

static func get_room(id: String) -> Dictionary:
	return ROOMS.get(id, {})

static func room_name(id: String) -> String:
	return String(get_room(id).get("name", id))

## 列出本箱庭的所有出口：返回 [{dir, room, cell}]，cell 是**本房间**要站的格
static func exit_cells(room_id: String) -> Array:
	var out: Array = []
	var r := get_room(room_id)
	var ex: Dictionary = r.get("exits", {})
	for dir in ex:
		var e: Dictionary = ex[dir]
		out.append({
			"dir": String(dir),
			"room": String(e.get("room", "")),
			"cell": Vector2i(e.get("cell", Vector2i.ZERO)),
		})
	return out
