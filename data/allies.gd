class_name Allies
extends RefCounted
## 团队模式的预设队友卡（单机由 AI 接管；联机时这三个槽位换成真人输入）。
##
## 设计意图 —— 让「团队 vs 独狼」的差异落在**分工**上，而不是单纯「人多」：
##   p1 铁闸：高耐力高防御，站前排吃伤害（生命上限最高）
##   p2 快刀：高敏捷高感知，行动条上冲得最快、暴击最高，负责先手切入
##   p3 药箱：高智力高决心，指挥点与急救来源，也是团队里「话最少但最能救命」的那个
##
## 属性点遵循建卡的**阶梯价**（1→2 花 1 点，2→3 花 2 点…），每人恰好 30 点、技能 20 点。
## 队友暂时不带血统（留给后续：血统 + 队友的组合会让排斥/失控复杂一大截）。

const PRESETS := [
	{
		"key": "tank", "name": "铁闸",
		"talent": "survivor",           # 最大生命 +4
		"attrs": {"str": 3, "dex": 2, "end": 5, "int": 1, "per": 2, "res": 3, "pre": 1, "man": 1, "com": 2},
		"skills": {"brawl": 4, "blade": 3, "survive": 4, "intimidate": 3, "medicine": 3, "hide": 3},
		"weapon": "bat",
		"note": "近战肉盾，生命上限最高",
	},
	{
		"key": "blade", "name": "快刀",
		"talent": "fighter",            # 近战伤害 +1
		"attrs": {"str": 2, "dex": 5, "end": 2, "int": 2, "per": 3, "res": 3, "pre": 1, "man": 1, "com": 1},
		"skills": {"blade": 4, "gun": 3, "hide": 5, "survive": 3, "investigate": 3, "empathy": 2},
		"weapon": "machete",
		"note": "行动最快、暴击最高，负责先手切入",
	},
	{
		"key": "medic", "name": "药箱",
		"talent": "scholar",            # 知识检定 +1 成功
		"attrs": {"str": 1, "dex": 1, "end": 3, "int": 5, "per": 2, "res": 4, "pre": 1, "man": 1, "com": 1},
		"skills": {"medicine": 5, "investigate": 4, "empathy": 3, "socialize": 3, "occult": 3, "survive": 2},
		"weapon": "bat",
		"note": "指挥点与急救来源",
	},
]

## 按预设造一张队友角色卡（天赋技能加成的算法与建卡界面保持一致）
static func make_character(preset: Dictionary) -> Character:
	var c := Character.create_default()
	c.name = String(preset.get("name", "队友"))
	c.talent_id = String(preset.get("talent", "fighter"))
	var attrs: Dictionary = preset.get("attrs", {})
	for a in attrs:
		c.attrs[String(a)] = int(attrs[a])
	var skills: Dictionary = preset.get("skills", {})
	for s in skills:
		c.skills[String(s)] = int(skills[s])
	var td: Dictionary = Talents.get_def(c.talent_id)
	for sid in td.get("skills", {}):
		c.skills[String(sid)] = int(c.skills.get(String(sid), 0)) + int(td["skills"][String(sid)])
	c.weapon = String(preset.get("weapon", "bat"))
	c.hp = c.max_hp()
	c.will = c.max_will()
	return c

## 造 n 名队友（团队模式 n = 3，即 p1/p2/p3）
static func make_allies(n: int = 3) -> Array:
	var out: Array = []
	for i in mini(n, PRESETS.size()):
		out.append(make_character(PRESETS[i]))
	return out

## 供 UI 显示：一张预设的简介
static func describe(preset: Dictionary) -> String:
	return "%s（%s）" % [String(preset.get("name", "?")), String(preset.get("note", ""))]
