class_name Items
extends RefCounted
## 物品定义。kind: weapon 武器 / armor 护甲 / consumable 消耗品 / quest 剧情物。
## 武器伤害遵循规则书「攻击成功数即伤害」：命中伤害 = 溢出成功数 + weapon.damage。

const ALL := {
	"fists": {
		"id": "fists", "name": "拳头", "kind": "weapon", "skill": "brawl",
		"damage": 1, "range": 1, "desc": "轮回者最初的武器。",
	},
	"bat": {
		"id": "bat", "name": "钢管", "kind": "weapon", "skill": "brawl",
		"damage": 2, "range": 1, "desc": "不知谁留在楼梯间的钢管。挥起来很趁手。",
	},
	"machete": {
		"id": "machete", "name": "开山刀", "kind": "weapon", "skill": "blade",
		"damage": 3, "range": 1, "desc": "消防柜里翻出来的长刀，刀刃有缺口但够利。",
	},
	"pistol": {
		"id": "pistol", "name": "手枪", "kind": "weapon", "skill": "gun",
		"damage": 3, "range": 4, "ammo": 12, "desc": "小区保安的佩枪。枪声会引来更多东西。",
	},
	"vest_light": {
		"id": "vest_light", "name": "防刺背心", "kind": "armor",
		"armor": 1, "desc": "保安室翻出的旧背心，能挡一点抓咬。",
	},
	"vest_heavy": {
		"id": "vest_heavy", "name": "战术背心", "kind": "armor",
		"armor": 2, "desc": "更厚实的防护，行动略显笨重。",
	},
	"medkit": {
		"id": "medkit", "name": "急救包", "kind": "consumable",
		"heal_hp": 8, "desc": "纱布、碘伏和两针肾上腺素。恢复 8 点生命。",
	},
	"tranquilizer": {
		"id": "tranquilizer", "name": "镇定剂", "kind": "consumable",
		"heal_will": 3, "desc": "让人冷静下来的针剂。恢复 3 点意志力。",
	},
	"blood_stabilizer": {
		"id": "blood_stabilizer", "name": "血脉稳定剂", "kind": "consumable",
		"stabilize": 3, "desc": "压制血脉冲突的针剂。3 回合内排斥度 −15（P3 缓解手段）。",
	},
	"apartment_key": {
		"id": "apartment_key", "name": "安全出口钥匙", "kind": "quest",
		"desc": "锈迹斑斑的铁钥匙，能打开公寓楼一层安全门。",
	},
	"chen_medicine": {
		"id": "chen_medicine", "name": "降压药", "kind": "quest",
		"desc": "陈叔要的降压药，在值班室药柜里找到的。",
	},
}

static func get_def(id: String) -> Dictionary:
	return ALL.get(id, {})

static func name_of(id: String) -> String:
	var d: Dictionary = ALL.get(id, {})
	return String(d.get("name", id))
