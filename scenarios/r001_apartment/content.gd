class_name R001Content
extends RefCounted
## 「惊变公寓」副本配置：开场、线索、结局结算。
##
## 剧情依据：docs/剧情大纲_惊变公寓.md v3（恐怖片结构 · 类型参考片单）
## 写作纪律：主神是冷的（只给任务与结算，不解释、不安慰）；真相靠物证不靠 NPC 讲述。

const ID := &"r001_apartment"
const TITLE := "惊变公寓"

## 开场＝主神任务简报（玩家进副本第一眼看到的东西）
const INTRO := "深夜。你在一间陌生公寓的楼梯间睁开眼，是被冷醒的。\n腕上的手环亮着红光，不是时间 —— 是一行字。\n\n【副本】惊变公寓\n【难度】D\n【目标】天亮前离开公寓楼\n【时限】06:00\n【奖励】基础 1,000　＋支线　＋线索\n【备注】本副本历史存活率 12%\n\n远处有什么东西在拖行，很慢，一下，一下。你握紧了手边那根钢管。"

## 线索：id -> 物证文本（收集 ≥3 条影响结局评级）
## 「转」的伏笔藏在 duty_note 与 blood_words 里：笔迹很稳，是**有意**留下来的。
const CLUES := {
	"duty_roster": "沾血的排班表。九月十三号的夜班，四个名字，前三个被人用指甲划烂了，最后一个还在 ——「周建国」。表格边角有半个血手印，手指的方向朝着大门。",

	"duty_note": "写了一半的工作日志。最后一页只有一行字，写到一半停了：\n「22:40 接到上级通知，要求 —— 」\n笔尖在纸上按出了一个深深的墨点。写字的人没有慌。",

	"twenty_shoes": "二十来双鞋，摆得很整齐，像是有人让他们脱下来的。鞋头都朝着同一个方向：通往外面的方向。旁边还有叠好的防化服和空弹壳。",

	"seal_912": "黄色封条，印着「危险区域 禁止入内」，落款日期是**九月十二日**。而你手里的排班表是九月十三号的。\n封条比出事早一天。",

	"blood_words": "门内侧，有人用手指蘸血写了三个字：「别开门」。字迹往下拖得很长，最后一笔拖了将近一尺。",

	"boss_weakness": "陈叔说的：大厅里那个东西，以前是这儿的保安，姓周。他左边胳膊不行 —— 那是旧伤，变异之后也没长好。",
}

const ENDING_NAMES := {
	"perfect": "完美撤离",
	"normal": "惊险撤离",
	"death": "陨落",
	"timeout": "超时",
}

## 老周（尸王）战前独白：全副本唯一有台词的敌人。
## 不做旁白解释 —— 他是保安，他在上班，他一直没下班。
const BOSS_LINES := [
	"请……",
	"回到……",
	"室内……",
]

## 结算：按结局与实绩生成奖励与文案。主神只报结果，不评价。
## mode_mult / mode_name：独狼的 ×1.5 是**风险溢价**（没有队友分摊风险），
## 必须在结算里写明白 —— 否则团队玩家会以为自己的努力被折价了。
static func settlement(player_name: String, ending_id: String, clues_found: int, quest_rewards: int, kill_rewards: int, total_points: int, mode_mult: float = 1.0, mode_name: String = "独狼") -> Dictionary:
	var title := String(ENDING_NAMES.get(ending_id, ending_id))
	var mode_line := "\n【模式】%s" % mode_name
	if mode_mult > 1.001:
		mode_line += "　风险溢价 ×%.1f" % mode_mult
	var body := ""
	var cleared := false
	match ending_id:
		"perfect":
			cleared = true
			body = "你推开消防门。外面天开始亮了。\n街道很空，几辆军车停在路口，车灯还亮着，一个人都没有。\n\n母亲抱着孩子从门里出来，站在路中间，回头看了一眼那栋楼。\n她问你：「外面那些人……是来救我们的吗？」\n（你没有回答。）\n\n【任务完成】\n存活率 12%%\n基础 +1,000　支线 +%d　击杀 +%d　线索 +%d\n合计 +%d 点%s" % [quest_rewards, kill_rewards, clues_found * 5, total_points, mode_line]
		"normal":
			cleared = true
			body = "你一个人从消防梯绕了出来。\n身后那栋楼的灯还亮着 —— 四楼的窗亮着。\n\n【任务完成】\n存活率 12%%\n基础 +1,000　支线 +%d　击杀 +%d　线索 +%d\n合计 +%d 点%s" % [quest_rewards, kill_rewards, clues_found * 5, total_points, mode_line]
		"death":
			cleared = false
			body = "视野变黑。\n\n【任务失败】\n轮回者已回收。\n评价：D\n是否重来？"
		"timeout":
			cleared = false
			body = "手环震了一下。\n「时限已到。」\n然后整栋楼的灯，一起灭了。\n\n【任务失败 · 超时】\n轮回者已回收。"
		_:
			cleared = false
			body = "任务中止。"
	return {
		"scenario_id": String(ID),
		"ending_id": ending_id,
		"title": title,
		"body": body,
		"points": total_points,
		"cleared": cleared,
	}
