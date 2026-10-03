class_name Upgrades
extends RefCounted
## 主神空间兑换（垂直切片：D 级）。
## 三种类别：attr 属性强化 / skill 技能强化 / item 物品。
## 属性成本 = 当前值 × 80 分（对应规则书 当前值×1XP，1XP≈100分，切片取整）。
## 技能成本 = 0→1 为 90 分，之后每级 60 分（简化）。

const ATTR_BASE_COST := 80
const SKILL_FIRST_COST := 90
const SKILL_LEVEL_COST := 60

const ITEMS_FOR_SALE := [
	{"id": "bat", "cost": 80},
	{"id": "machete", "cost": 140},
	{"id": "pistol", "cost": 200},
	{"id": "vest_light", "cost": 100},
	{"id": "vest_heavy", "cost": 180},
	{"id": "medkit", "cost": 50},
	{"id": "tranquilizer", "cost": 40},
	{"id": "blood_stabilizer", "cost": 200},
]

static func attr_cost(current: int) -> int:
	return current * ATTR_BASE_COST

static func skill_cost(current: int) -> int:
	if current <= 0:
		return SKILL_FIRST_COST
	return SKILL_LEVEL_COST
