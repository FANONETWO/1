class_name Skills
extends RefCounted
## 技能定义（基于 RE25 规则书）。垂直切片取三系代表性技能：
## 生理：肉搏 / 白刃 / 枪械 / 躲藏 / 求生
## 心智：调查 / 医学 / 神秘学
## 互动：交际 / 胁迫 / 掩饰 / 感受
## 技能 0-15 级；0 级惩罚：生理 -1 成功，心智自动失败，互动 -2 成功。
## 附加成功：技能达到 5/7/9/11/13/15 各 +1（至多 6）。

const ALL := ["brawl", "blade", "gun", "hide", "survive", "investigate", "medicine", "occult", "socialize", "intimidate", "bluff", "empathy"]

const PHYSICAL := ["brawl", "blade", "gun", "hide", "survive"]
const MENTAL := ["investigate", "medicine", "occult"]
const SOCIAL := ["socialize", "intimidate", "bluff", "empathy"]

const NAMES := {
	"brawl": "肉搏", "blade": "白刃", "gun": "枪械", "hide": "躲藏", "survive": "求生",
	"investigate": "调查", "medicine": "医学", "occult": "神秘学",
	"socialize": "交际", "intimidate": "胁迫", "bluff": "掩饰", "empathy": "感受",
}

const DESC := {
	"brawl": "徒手格斗与搏击。",
	"blade": "刀剑等近战兵刃。",
	"gun": "枪械射击。",
	"hide": "潜行躲藏与匿踪。",
	"survive": "野外求生、应急与搜寻。",
	"investigate": "搜查现场、发现线索。",
	"medicine": "急救与医疗。",
	"occult": "神秘学知识。",
	"socialize": "人际交往与谈判。",
	"intimidate": "威吓与震慑。",
	"bluff": "说谎与伪装。",
	"empathy": "察言观色。",
}

const CATEGORY := {
	"brawl": "生理", "blade": "生理", "gun": "生理", "hide": "生理", "survive": "生理",
	"investigate": "心智", "medicine": "心智", "occult": "心智",
	"socialize": "互动", "intimidate": "互动", "bluff": "互动", "empathy": "互动",
}

## 附加成功：技能 5/7/9/11/13/15 各 +1。
static func bonus_success(skill_value: int) -> int:
	if skill_value < 5:
		return 0
	return 1 + (skill_value - 5) / 2

## 0 级技能检定惩罚（成功数修正）：生理 -1，心智自动失败，互动 -2。
static func zero_penalty(skill_id: String) -> int:
	match CATEGORY.get(skill_id, "生理"):
		"生理":
			return -1
		"心智":
			return -99  # 视为自动失败
		_:
			return -2

static func name_of(skill_id: String) -> String:
	return NAMES.get(skill_id, skill_id)
