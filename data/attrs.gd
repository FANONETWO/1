class_name Attrs
extends RefCounted
## 九属性三系定义（基于 RE25 规则书）：
## 生理：力量 STR / 敏捷 DEX / 耐力 END
## 心智：智力 INT / 感知 PER / 决心 RES
## 互动：风度 PRE / 操控 MAN / 沉着 COM
## 标度：2=现代人类平均，5=人类极限，6+=超凡。
## 附加成功：属性达到 6 获得 1 个附加成功，每 +5 再加一个。

const PHYSICAL := ["str", "dex", "end"]
const MENTAL := ["int", "per", "res"]
const SOCIAL := ["pre", "man", "com"]
const ALL := ["str", "dex", "end", "int", "per", "res", "pre", "man", "com"]

const NAMES := {
	"str": "力量", "dex": "敏捷", "end": "耐力",
	"int": "智力", "per": "感知", "res": "决心",
	"pre": "风度", "man": "操控", "com": "沉着",
}

## 属性重做：每条描述都写明它**在战棋里的出口**，避免玩家投了废属性。
const DESC := {
	"str": "爆发力与负重。近战伤害 = 武器 + 力量/2。",
	"dex": "协调与反应。移动力 = 3 + 敏捷/2；决定防御与先攻。",
	"end": "健康与抵抗力。生命上限 = 8 + 4×耐力。",
	"int": "逻辑与记忆。战术点 = 智力/2：每场可「看穿弱点」若干次。",
	"per": "洞察与直觉。暴击率 = 5%×感知；远程伤害吃感知。",
	"res": "精神的强度。意志力池 = 2×决心，是战斗内可支配的资源。",
	"pre": "气质与存在感。指挥光环：风度/2 格内的队友命中 +1。",
	"man": "言行感染力。威慑：敌人的骰池 −1（操控≥4 时 −2）。",
	"com": "压力下的镇定。先攻 + 沉着；每回合首次受击减伤 沉着/3。",
}

## 附加成功：属性达到 6 获得 1 个，每 +5 再加一个。
static func bonus_success(attr_value: int) -> int:
	if attr_value < 6:
		return 0
	return 1 + (attr_value - 6) / 5

static func category_of(attr: String) -> String:
	if attr in PHYSICAL:
		return "生理"
	if attr in MENTAL:
		return "心智"
	return "互动"

## 属性名（中文），未知返回原名。
static func name_of(attr: String) -> String:
	return NAMES.get(attr, attr)
