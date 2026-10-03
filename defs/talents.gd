class_name Talents
extends RefCounted
## 建卡天赋（出身专长简化）。每个天赋：+1 技能级数、专属被动。
## 被动在 Character 上实现为 tag，战斗/检定系统读取。

const ALL := {
	"fighter": {
		"id": "fighter", "name": "街头格斗者",
		"desc": "在烂巷子里打出来的身手。肉搏 +1，白刃 +1，近战伤害 +1。",
		"skills": {"brawl": 1, "blade": 1},
		"tags": ["melee_damage_1"],
	},
	"scholar": {
		"id": "scholar", "name": "末世学者",
		"desc": "什么都读一点的图书馆常客。调查 +1，医学 +1，神秘学 +1，知识检定 +1 成功。",
		"skills": {"investigate": 1, "medicine": 1, "occult": 1},
		"tags": ["knowledge_plus_1"],
	},
	"negotiator": {
		"id": "negotiator", "name": "天生话术",
		"desc": "能把死人说出活来。交际 +1，胁迫 +1，掩饰 +1，互动检定 +1 成功。",
		"skills": {"socialize": 1, "intimidate": 1, "bluff": 1},
		"tags": ["social_plus_1"],
	},
	"survivor": {
		"id": "survivor", "name": "老练幸存者",
		"desc": "比任何人都活得久。求生 +1，躲藏 +1，最大生命 +4。",
		"skills": {"survive": 1, "hide": 1},
		"tags": ["hp_plus_4"],
	},
	"gunner": {
		"id": "gunner", "name": "射击俱乐部会员",
		"desc": "枪法还算像样。枪械 +1，远程伤害 +1，手枪弹药 +4。",
		"skills": {"gun": 1},
		"tags": ["ranged_damage_1", "ammo_plus_4"],
	},
}

static func get_def(id: String) -> Dictionary:
	return ALL.get(id, {})
