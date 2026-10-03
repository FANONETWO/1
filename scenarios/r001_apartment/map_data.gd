class_name R001Map
extends RefCounted
## 「惊变公寓」一层地图数据与布点。
## 地形：'#' 墙 / '.' 地板 / 'D' 门 / 'T' 桌 / 'B' 床 / 'C' 柜 / 'S' 楼梯 / 'E' 安全出口。

## RE2 箱庭式一层：北侧房间群 → 横向主走廊 → 中央大堂 → 南侧出口/楼梯，
## 上下两组门构成**环形动线**（可绕圈、可包抄、可撤退）。
## 地形：'#' 墙 / '.' 地板 / 'D' 门 / 'T' 桌 / 'B' 床 / 'C' 柜 / 'S' 楼梯 / 'E' 安全出口
##       'H' 高地（命中+10） / 'X' 危险区（每回合-2 HP） / 'R' 废墟 / 'F' 森林
const TILES: Array[String] = [
	"####################",
	"#CC.#....HH.#..B...#",
	"#...D.......D......#",
	"#...#.......#..C...#",
	"##D##.......##D#####",
	"#..................#",
	"#...####..####.....#",
	"#...#........#.....#",
	"#...#...X....#..T..#",
	"##D##........##D####",
	"#....D..E....#..S..#",
	"####################",
]

## 出生点：南侧楼梯间（RE2 式：从楼梯进入一层）
const SPAWN := Vector2i(15, 10)

## 敌人布点（初始激活）：走廊遭遇 → 大堂 → 客房 → 守门的尸王
## facing = 视野朝向。敌人只能看到**前方 90° 锥**内的目标 → 从背后接近可以潜行突袭。
const ENEMIES := [
	# ——— 北侧房间群（稀疏，可潜行绕过）———
	{"id": "walker", "pos": Vector2i(1, 2), "facing": Vector2i(1, 0)},
	{"id": "walker", "pos": Vector2i(2, 2), "facing": Vector2i(0, 1)},
	{"id": "cadaver", "pos": Vector2i(3, 1), "facing": Vector2i(0, 1)},
	{"id": "zombie", "pos": Vector2i(9, 1), "facing": Vector2i(0, 1)},
	{"id": "zombie", "pos": Vector2i(10, 1), "facing": Vector2i(0, 1)},
	{"id": "screamer", "pos": Vector2i(16, 1), "facing": Vector2i(0, 1)},
	{"id": "walker", "pos": Vector2i(17, 2), "facing": Vector2i(-1, 0)},
	# ——— 主走廊（横向，视野锥交叉）———
	{"id": "zombie", "pos": Vector2i(5, 5), "facing": Vector2i(0, 1)},
	{"id": "walker", "pos": Vector2i(8, 5), "facing": Vector2i(0, 1)},
	{"id": "crawler", "pos": Vector2i(13, 2), "facing": Vector2i(-1, 0)},
	{"id": "walker", "pos": Vector2i(16, 5), "facing": Vector2i(-1, 0)},
	# ——— 南侧房间群 ———
	{"id": "bloater", "pos": Vector2i(3, 7), "facing": Vector2i(1, 0)},
	{"id": "walker", "pos": Vector2i(3, 8), "facing": Vector2i(1, 0)},
	{"id": "zombie", "pos": Vector2i(11, 7), "facing": Vector2i(0, 1)},
	{"id": "cadaver", "pos": Vector2i(14, 8), "facing": Vector2i(0, 1)},
	{"id": "hound", "pos": Vector2i(17, 8), "facing": Vector2i(-1, 0)},
	# ——— 大堂与出口（密集，守关）———
	{"id": "zombie", "pos": Vector2i(6, 8), "facing": Vector2i(0, 1)},
	{"id": "zombie", "pos": Vector2i(7, 9), "facing": Vector2i(0, -1)},
	{"id": "walker", "pos": Vector2i(9, 8), "facing": Vector2i(0, 1)},
	{"id": "walker", "pos": Vector2i(10, 9), "facing": Vector2i(0, -1)},
	{"id": "crawler", "pos": Vector2i(12, 9), "facing": Vector2i(-1, 0)},
	{"id": "screamer", "pos": Vector2i(16, 10), "facing": Vector2i(-1, 0)},
	# ——— 尸王（前保安队长）守在大堂西侧 ———
	{"id": "brute", "pos": Vector2i(2, 8), "facing": Vector2i(1, 0)},
]

## NPC 布点。id -> {pos, label}
const NPCS := {
	"chen": {"pos": Vector2i(6, 2), "label": "陈叔"},
	"agui": {"pos": Vector2i(15, 8), "label": "疯子阿贵"},
}

## 可调查物。id -> {pos, label}
const SPOTS := {
	"storage_locker": {"pos": Vector2i(2, 1), "label": "储物间柜子"},
	"duty_locker": {"pos": Vector2i(8, 2), "label": "值班室药柜"},
	"duty_desk": {"pos": Vector2i(10, 3), "label": "值班室桌面"},
	"bed_mattress": {"pos": Vector2i(15, 1), "label": "空房床垫"},
	"stairs": {"pos": Vector2i(16, 10), "label": "楼梯间"},
}

## 安全出口：南侧大堂深处（需钥匙）
const EXIT := Vector2i(8, 10)
