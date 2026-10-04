class_name Bloodlines
extends RefCounted
## 血统模块数据层与关系计算。
##
## 三项核心规则（详见 docs/血统模块设计方案.md）：
##   1. 血统 = 一棵技能树，评级 D→C→B→A→S；**兑换只能从 D 级起步**。
##   2. 每级解锁 3–4 个候选技能，但只能选 2 个（S 级选 1 个）→ 同级 build 必然分化。
##   3. 谱系标签之间存在「对立（排斥）/ 互补（协同）/ 同源（共鸣）」三种关系。
##
## 本类只做数据与纯计算，不依赖场景，可直接单元测试。

# ——— 谱系标签 ———

const TAGS: Array[String] = [
	"holy", "evil", "life", "undeath", "order",
	"chaos", "matter", "spirit", "beast", "reason",
]

const TAG_NAMES := {
	"holy": "神圣", "evil": "邪恶", "life": "生命", "undeath": "不死",
	"order": "秩序", "chaos": "混沌", "matter": "物质", "spirit": "精神",
	"beast": "兽性", "reason": "理性",
}

## 对立标签（对称）。互为对立的标签产生排斥。
const OPPOSED := {
	"holy": "evil", "evil": "holy",
	"life": "undeath", "undeath": "life",
	"order": "chaos", "chaos": "order",
	"matter": "spirit", "spirit": "matter",
	"beast": "reason", "reason": "beast",
}

## 对立强度（键为该标签与其对立标签之间的强度）。
const OPPOSE_WEIGHT := {
	"holy": 30, "evil": 30,
	"life": 25, "undeath": 25,
	"order": 20, "chaos": 20,
	"matter": 15, "spirit": 15,
	"beast": 15, "reason": 15,
}

## 互补标签（对称，每个标签 2 个）。互为互补的标签产生协同。
const SYNERGY := {
	"holy": ["life", "spirit"],
	"evil": ["undeath", "chaos"],
	"life": ["holy", "beast"],
	"undeath": ["evil", "matter"],
	"order": ["reason", "matter"],
	"chaos": ["evil", "beast"],
	"matter": ["undeath", "order"],
	"spirit": ["holy", "reason"],
	"beast": ["life", "chaos"],
	"reason": ["order", "spirit"],
}

# ——— 评级 ———

const RANKS: Array[String] = ["D", "C", "B", "A", "S"]
const RANK_LEVEL := {"D": 1, "C": 2, "B": 3, "A": 4, "S": 5}
## 升级差价（从上一级升到该级所需奖励点）。
const RANK_UPGRADE_COST := {"D": 800, "C": 1600, "B": 4800, "A": 14400, "S": 43200}
## 每级可选技能数。
const RANK_PICK := {"D": 2, "C": 2, "B": 2, "A": 2, "S": 1}
## 每级候选技能数（用于数据自检）。
const RANK_CANDIDATES := {"D": 3, "C": 4, "B": 4, "A": 3, "S": 2}

# ——— 八系血统定义 ———
# 每系：tags（谱系标签）+ ranks（D→S 的候选技能，技能 type 见 NODE_TYPES）

const NODE_TYPES := ["passive", "active", "attr", "form", "ultimate"]

const DEFS := {
	# ======== w1 惊变公寓：感染系 —— 入门血统，廉价、毒、变异 ========
	"infected": {
		"name": "感染者", "family": "感染系", "world": "w1_apartment",
		"tags": ["undeath", "chaos", "beast"],
		"intro": "尸毒在血管里改写你，痛觉最先消失。",
		"ranks": {
			"D": [
				{"id": "pain_dull", "name": "痛觉迟钝", "type": "passive", "desc": "受到的伤害 −1"},
				{"id": "infection_sniff", "name": "感染嗅探", "type": "passive", "desc": "探测 3 格内的生物"},
				{"id": "mutant_body", "name": "变异体质", "type": "attr", "attr": "end", "value": 1, "desc": "耐力 +1"},
			],
			"C": [
				{"id": "bite", "name": "撕咬", "type": "active", "desc": "近战命中后附加中毒（每回合 −1 HP，可叠 3 层）"},
				{"id": "scuttle", "name": "疾走", "type": "passive", "desc": "移动力 +1"},
				{"id": "foul_blood", "name": "腐血", "type": "passive", "desc": "近战攻击你的敌人受 1 点伤害"},
				{"id": "proliferate", "name": "增殖", "type": "passive", "desc": "击杀后回复 2 HP"},
			],
			"B": [
				{"id": "toxic_cloud", "name": "毒云", "type": "active", "desc": "范围中毒（2 格内敌人每回合 −1 HP，3 回合）"},
				{"id": "plague_body", "name": "疫体", "type": "passive", "desc": "免疫中毒与疾病"},
				{"id": "regrow", "name": "再生组织", "type": "passive", "desc": "每回合回复 1 HP"},
				{"id": "claws", "name": "尖爪", "type": "passive", "desc": "近战伤害 +1"},
			],
			"A": [
				{"id": "mutant_form", "name": "变异形态", "type": "form", "desc": "3 回合内 力量 +2 / 防御 +2"},
				{"id": "hive_sense", "name": "巢穴感知", "type": "passive", "desc": "视野 +2，探测 8 格内的生物"},
				{"id": "spore_burst", "name": "孢子爆发", "type": "active", "desc": "范围内敌人受 3 伤害并被感染"},
			],
			"S": [
				{"id": "hive_mind", "name": "母巢意志", "type": "ultimate", "desc": "每场 1 次：召唤 2 只感染体为你作战"},
				{"id": "plague_incarnate", "name": "万疫之躯", "type": "ultimate", "desc": "死亡时以 40% 生命复生（每副本 1 次）"},
			],
		},
	},

	# ======== w2 仙侠：仙体系 —— 灵力、御物、克制阴邪 ========
	"immortal": {
		"name": "仙体", "family": "仙体系", "world": "w2_xianxia",
		"tags": ["holy", "life", "spirit"],
		"intro": "灵根既种，凡骨渐轻。",
		"ranks": {
			"D": [
				{"id": "spirit_sense", "name": "灵觉", "type": "passive", "desc": "识破潜行与幻术"},
				{"id": "qi_ward", "name": "御气", "type": "passive", "desc": "受到远程伤害 −1"},
				{"id": "spirit_root", "name": "灵根", "type": "attr", "attr": "int", "value": 1, "desc": "智力 +1"},
			],
			"C": [
				{"id": "flying_sword", "name": "御剑", "type": "active", "desc": "5 格直线穿刺，伤害 = 智力 + 2"},
				{"id": "light_body", "name": "轻身", "type": "passive", "desc": "回避 +5"},
				{"id": "breathing", "name": "吐纳", "type": "passive", "desc": "每回合回复 1 点意志力"},
				{"id": "talisman", "name": "符箓", "type": "active", "desc": "对单体造成 3 点无视防御的伤害（每场 2 次）"},
			],
			"B": [
				{"id": "aura_shield", "name": "护体灵光", "type": "active", "desc": "3 回合内防御 +3"},
				{"id": "sword_heart", "name": "剑心", "type": "passive", "desc": "暴击率 +10%"},
				{"id": "evil_bane", "name": "破邪", "type": "passive", "desc": "对不死/邪恶系敌人伤害 +2"},
				{"id": "qi_surge", "name": "灵力充盈", "type": "passive", "desc": "意志力上限 +2"},
			],
			"A": [
				{"id": "demon_form", "name": "妖化", "type": "form", "desc": "3 回合内 力量 +3 / 防御 −2 / 命中 +10"},
				{"id": "myriad_swords", "name": "万剑诀", "type": "active", "desc": "范围内所有敌人受 4 伤害"},
				{"id": "golden_body", "name": "金身", "type": "active", "desc": "免疫一次致命伤害（每场 1 次）"},
			],
			"S": [
				{"id": "sword_immortal", "name": "剑仙", "type": "ultimate", "desc": "每场 1 次：一次攻击必定命中且必定暴击"},
				{"id": "undying_body", "name": "不灭金身", "type": "ultimate", "desc": "生命归零时以 50% 生命复活（每副本 1 次）"},
			],
		},
	},

	# ======== w3 科幻：义体系 —— 模块、抗性、火控 ========
	"cyber": {
		"name": "义体", "family": "义体系", "world": "w3_scifi",
		"tags": ["reason", "order", "matter"],
		"intro": "血肉廉价，钢铁才是可靠的。",
		"ranks": {
			"D": [
				{"id": "neural_link", "name": "神经直连", "type": "passive", "desc": "命中 +5"},
				{"id": "armor_plating", "name": "装甲镀层", "type": "passive", "desc": "防御 +1"},
				{"id": "tactical_chip", "name": "战术芯片", "type": "attr", "attr": "int", "value": 1, "desc": "智力 +1"},
			],
			"C": [
				{"id": "suppression", "name": "火力压制", "type": "active", "desc": "范围内敌人命中 −5，持续 2 回合"},
				{"id": "mobile_frame", "name": "机动装甲", "type": "passive", "desc": "移动力 +1"},
				{"id": "thermal", "name": "热成像", "type": "passive", "desc": "无视黑暗与烟雾的命中惩罚"},
				{"id": "self_repair", "name": "自我修复", "type": "passive", "desc": "每回合回复 2 HP（战斗内）"},
			],
			"B": [
				{"id": "target_lock", "name": "目标锁定", "type": "passive", "desc": "暴击率 +15%"},
				{"id": "composite", "name": "复合装甲", "type": "passive", "desc": "防御 +2"},
				{"id": "overload", "name": "过载", "type": "active", "desc": "本回合伤害 +3（每场 3 次）"},
				{"id": "backup_power", "name": "备用电源", "type": "passive", "desc": "免疫一次失控或眩晕（每场 1 次）"},
			],
			"A": [
				{"id": "tactical_overdrive", "name": "战术超载", "type": "form", "desc": "3 回合内 命中 +15 / 伤害 +3"},
				{"id": "drone", "name": "无人机僚机", "type": "active", "desc": "召唤 1 架无人机（每场 1 次）"},
				{"id": "emp", "name": "电磁脉冲", "type": "active", "desc": "范围内机械/义体敌人眩晕 2 回合"},
			],
			"S": [
				{"id": "upload", "name": "意识上传", "type": "ultimate", "desc": "死亡时以 50% 生命重建躯体（每副本 1 次）"},
				{"id": "skynet", "name": "天网", "type": "ultimate", "desc": "每场 1 次：全队命中 +10、暴击 +10%，持续 3 回合"},
			],
		},
	},

	# ======== w4 魔法：不死系（血族） ========
	"vampire": {
		"name": "血族", "family": "不死系", "world": "w4_magic",
		"tags": ["undeath", "chaos", "matter"],
		"intro": "第一次饮血之后，你就再也尝不出面包的味道。",
		"ranks": {
			"D": [
				{"id": "blood_sense", "name": "鲜血感知", "type": "passive", "desc": "探测 4 格内的生物"},
				{"id": "night_affinity", "name": "夜之亲和", "type": "passive", "desc": "黑暗地形命中 +5、回避 +5"},
				{"id": "bloody_body", "name": "血色体质", "type": "attr", "attr": "end", "value": 1, "desc": "耐力 +1"},
			],
			"C": [
				{"id": "blood_strength", "name": "血之蛮力", "type": "passive", "desc": "近战伤害 +1"},
				{"id": "blood_drain", "name": "汲血", "type": "active", "desc": "命中后回复 3 HP（每场 3 次）"},
				{"id": "swift_shadow", "name": "疾影", "type": "passive", "desc": "移动力 +1"},
				{"id": "bat_step", "name": "蝠步", "type": "active", "desc": "本回合可穿墙移动 2 格（每场 2 次）"},
			],
			"B": [
				{"id": "blood_rage", "name": "血怒", "type": "passive", "desc": "生命 <50% 时伤害 +2"},
				{"id": "iron_blood", "name": "钢铁血脉", "type": "attr", "attr": "end", "value": 1, "desc": "耐力 +1、防御 +1"},
				{"id": "whirl", "name": "回旋", "type": "passive", "desc": "击杀后可再移动 1 格"},
				{"id": "venom_fang", "name": "毒牙", "type": "passive", "desc": "命中附加流血（每回合 −1 HP，2 回合）"},
			],
			"A": [
				{"id": "blood_awaken", "name": "血之觉醒", "type": "form", "desc": "3 回合内 力量 +2 / 敏捷 +2，结束眩晕 1 回合"},
				{"id": "dark_form", "name": "黑暗形态", "type": "form", "desc": "3 回合内 防御 +3、每回合回 2 HP，移动 −1"},
				{"id": "bat_swarm", "name": "蝙蝠群", "type": "active", "desc": "召唤 2 只蝙蝠牵制敌人（每场 1 次）"},
			],
			"S": [
				{"id": "blood_river", "name": "始祖·血河", "type": "ultimate", "desc": "每场 1 次：范围吸血（伤害 = 力量×2，回复 50%）"},
				{"id": "immortal_blood", "name": "始祖·不朽", "type": "ultimate", "desc": "生命归零时以 30% 生命复活（每副本 1 次）"},
			],
		},
	},

	# ======== w5 废土：兽化系（狼人） ========
	"werewolf": {
		"name": "狼人", "family": "兽化系", "world": "w5_wasteland",
		"tags": ["beast", "life", "matter"],
		"intro": "月圆之夜，你听见自己骨头里传来低吼。",
		"ranks": {
			"D": [
				{"id": "wild_instinct", "name": "野性直觉", "type": "passive", "desc": "先攻 +2"},
				{"id": "thick_hide", "name": "厚皮", "type": "passive", "desc": "防御 +1"},
				{"id": "blood_scent", "name": "嗅血", "type": "passive", "desc": "探测 4 格内的受伤生物"},
			],
			"C": [
				{"id": "frenzy", "name": "狂化", "type": "active", "desc": "3 回合内伤害 +2、防御 −2"},
				{"id": "pounce", "name": "扑击", "type": "active", "desc": "冲锋（移动 +2）并对目标额外造成 2 伤害"},
				{"id": "rend", "name": "撕裂", "type": "passive", "desc": "命中附加流血（每回合 −1 HP，2 回合）"},
				{"id": "swift", "name": "迅捷", "type": "passive", "desc": "移动力 +1"},
			],
			"B": [
				{"id": "blood_moon", "name": "血月", "type": "passive", "desc": "生命 <50% 时伤害 +3"},
				{"id": "steel_claw", "name": "钢爪", "type": "passive", "desc": "近战伤害 +2"},
				{"id": "beast_recovery", "name": "兽性恢复", "type": "passive", "desc": "每回合回复 2 HP"},
				{"id": "roar", "name": "咆哮", "type": "active", "desc": "相邻敌人命中 −2，持续 2 回合"},
			],
			"A": [
				{"id": "wolf_king_form", "name": "狼王形态", "type": "form", "desc": "3 回合内 力量 +3 / 敏捷 +2"},
				{"id": "call_pack", "name": "群体召唤", "type": "active", "desc": "召唤 1 只狼（每场 1 次）"},
				{"id": "tireless", "name": "不倦", "type": "passive", "desc": "免疫疲劳与减速"},
			],
			"S": [
				{"id": "wildlord", "name": "荒野之主", "type": "ultimate", "desc": "每场 1 次：全场敌人恐惧（命中 −5，2 回合）"},
				{"id": "king_of_beasts", "name": "万兽之王", "type": "ultimate", "desc": "每场 1 次：召唤兽群，持续 3 回合协同作战"},
			],
		},
	},

	# ======== w4 隐藏：神圣系（天使） ========
	"angel": {
		"name": "天使", "family": "神圣系", "world": "w4_magic",
		"tags": ["holy", "order", "spirit"],
		"intro": "光落进你眼里的时候，你听见了不属于人间的合唱。",
		"ranks": {
			"D": [
				{"id": "holy_ward", "name": "圣光护体", "type": "passive", "desc": "防御 +1"},
				{"id": "detect_evil", "name": "感知邪恶", "type": "passive", "desc": "探测 6 格内的邪恶/不死系生物"},
				{"id": "faith", "name": "信仰", "type": "attr", "attr": "res", "value": 1, "desc": "决心 +1"},
			],
			"C": [
				{"id": "heal_touch", "name": "治愈之手", "type": "active", "desc": "治疗自己或相邻队友 4 HP（每场 3 次）"},
				{"id": "judgement", "name": "审判", "type": "passive", "desc": "对邪恶/不死系敌人伤害 +2"},
				{"id": "sanctuary", "name": "庇护", "type": "active", "desc": "给相邻队友 +2 防御，持续 2 回合"},
				{"id": "grace", "name": "神恩", "type": "passive", "desc": "每回合回复 1 点意志力"},
			],
			"B": [
				{"id": "holy_smite", "name": "神圣冲击", "type": "active", "desc": "范围内邪恶/不死系敌人受 4 伤害"},
				{"id": "unbroken_will", "name": "不落之志", "type": "passive", "desc": "免疫一次恐惧或失控（每场 1 次）"},
				{"id": "radiance", "name": "光辉", "type": "passive", "desc": "指挥光环：2 格内队友命中 +5"},
				{"id": "purify", "name": "净化", "type": "active", "desc": "解除自己或队友的所有负面状态"},
			],
			"A": [
				{"id": "angel_form", "name": "天使形态", "type": "form", "desc": "3 回合内 全属性 +1，可飞越障碍"},
				{"id": "divine_verdict", "name": "圣裁", "type": "active", "desc": "对邪恶/不死系敌人必定命中（每场 2 次）"},
				{"id": "oath_guard", "name": "守护誓约", "type": "active", "desc": "替 2 格内的队友承受伤害，持续 2 回合"},
			],
			"S": [
				{"id": "archangel", "name": "大天使", "type": "ultimate", "desc": "每场 1 次：全队回复 50% 生命并清除负面"},
				{"id": "oracle", "name": "神谕", "type": "ultimate", "desc": "每场 1 次：本回合全队攻击必定命中"},
			],
		},
	},

	# ======== w4 隐藏：恶魔系 ========
	"demon": {
		"name": "恶魔", "family": "恶魔系", "world": "w4_magic",
		"tags": ["evil", "chaos", "spirit"],
		"intro": "契约签下的那一刻，你才发现签名用的是自己的血。",
		"ranks": {
			"D": [
				{"id": "corrupt_touch", "name": "腐化之触", "type": "passive", "desc": "命中后目标防御 −1（可叠 2 层）"},
				{"id": "dark_sight", "name": "黑暗视觉", "type": "passive", "desc": "无视黑暗带来的命中惩罚"},
				{"id": "demon_body", "name": "恶魔体质", "type": "attr", "attr": "end", "value": 1, "desc": "耐力 +1"},
			],
			"C": [
				{"id": "abyss_whisper", "name": "深渊低语", "type": "active", "desc": "让 1 个敌人本回合攻击它最近的同伴（每场 2 次）"},
				{"id": "pain_gift", "name": "痛苦馈赠", "type": "passive", "desc": "受到近战伤害时反弹 2 点"},
				{"id": "pact", "name": "契约", "type": "active", "desc": "消耗 3 HP，本回合伤害 +4"},
				{"id": "decay", "name": "腐化", "type": "passive", "desc": "命中附加腐蚀（每回合 −1 HP，3 回合）"},
			],
			"B": [
				{"id": "blood_sacrifice", "name": "血祭", "type": "active", "desc": "消耗 5 HP，造成 8 点伤害（每场 2 次）"},
				{"id": "fear_aura", "name": "恐惧光环", "type": "passive", "desc": "相邻敌人命中 −2"},
				{"id": "demon_wing", "name": "恶魔之翼", "type": "passive", "desc": "移动力 +2"},
				{"id": "soul_eater", "name": "噬魂", "type": "passive", "desc": "击杀后回复 2 点意志力"},
			],
			"A": [
				{"id": "demon_form", "name": "恶魔形态", "type": "form", "desc": "3 回合内 伤害 +4 / 防御 −2"},
				{"id": "hellfire", "name": "地狱火", "type": "active", "desc": "范围内敌人受 5 伤害并灼烧（2 回合）"},
				{"id": "soul_chain", "name": "灵魂枷锁", "type": "active", "desc": "定身 1 个敌人 2 回合"},
			],
			"S": [
				{"id": "abyss_lord", "name": "深渊领主", "type": "ultimate", "desc": "每场 1 次：召唤 1 只恶魔为你作战"},
				{"id": "fallen", "name": "堕天", "type": "ultimate", "desc": "每场 1 次：3 回合内伤害 ×2，结束后受 50% 反伤"},
			],
		},
	},

	# ======== 终局隐藏：神性系（外神） ========
	"outer": {
		"name": "外神眷属", "family": "神性系", "world": "hidden",
		"tags": ["chaos", "spirit"],
		"intro": "你看见了不该看的东西，而它回看了你一眼。",
		"ranks": {
			"D": [
				{"id": "whisper", "name": "低语", "type": "attr", "attr": "per", "value": 1, "desc": "感知 +1"},
				{"id": "gaze", "name": "注视", "type": "passive", "desc": "相邻敌人命中 −1"},
				{"id": "aberration", "name": "异化", "type": "attr", "attr": "end", "value": 1, "desc": "耐力 +1"},
			],
			"C": [
				{"id": "tendril", "name": "触手", "type": "active", "desc": "3 格内单体造成 3 伤害并拉近 1 格"},
				{"id": "mad_echo", "name": "疯狂回响", "type": "passive", "desc": "相邻敌人意志检定 −1"},
				{"id": "void_step", "name": "虚空行走", "type": "active", "desc": "穿墙移动 1 格（每场 3 次）"},
				{"id": "sanity_anchor", "name": "理智锚", "type": "passive", "desc": "免疫一次精神攻击（每场 1 次）"},
			],
			"B": [
				{"id": "warp", "name": "空间扭曲", "type": "active", "desc": "瞬移 3 格（每场 2 次）"},
				{"id": "reality_erode", "name": "现实侵蚀", "type": "active", "desc": "范围内敌人受 4 伤害且防御 −1"},
				{"id": "unnamable", "name": "不可名状", "type": "passive", "desc": "指挥光环：2 格内敌人命中 −10"},
				{"id": "devour", "name": "吞噬", "type": "passive", "desc": "击杀后回复 3 HP"},
			],
			"A": [
				{"id": "avatar_form", "name": "化身容器", "type": "form", "desc": "3 回合内全属性 +2，每回合 −1 意志力"},
				{"id": "dominate", "name": "支配", "type": "active", "desc": "控制 1 个敌人 1 回合（每场 1 次）"},
				{"id": "madness_wave", "name": "狂乱波", "type": "active", "desc": "范围内敌人互相攻击 1 次"},
			],
			"S": [
				{"id": "outer_avatar", "name": "外神化身", "type": "ultimate", "desc": "每场 1 次：全场敌人命中 −5、防御 −3，持续 3 回合"},
				{"id": "final_whisper", "name": "终末低语", "type": "ultimate", "desc": "每副本 1 次：即死判定（对非 Boss 直接击杀）"},
			],
		},
	},
}

# ——— 融合技（排斥 ≥80% 时解锁） ———

## 键为两条血统 id 的拼接（查询时两种顺序都会尝试）。
const FUSION := {
	"angel+demon": {"name": "堕天裁决", "desc": "范围敌人受 神圣＋邪恶 双属性伤害，自身回复伤害的 30%"},
	"vampire+werewolf": {"name": "血月狂猎", "desc": "3 回合内移动 +3，每次击杀刷新行动"},
	"infected+cyber": {"name": "机械疫病", "desc": "命中使命中者感染，其死亡时爆炸并扩散"},
	"angel+immortal": {"name": "圣辉剑域", "desc": "范围内敌人受伤并被标记，队友对其命中 +10（2 回合）"},
	"vampire+cyber": {"name": "永夜机骸", "desc": "3 回合内义体过载不耗能量、血族再生翻倍"},
	"infected+werewolf": {"name": "疫兽狂潮", "desc": "变身期间命中附加感染，被感染者死亡时爆出小感染体"},
	"immortal+cyber": {"name": "灵枢机巧", "desc": "御剑可穿墙，每次击杀返还 1 点意志力"},
}

## 按持有血统查找融合技（无则返回空字典）。
static func fusion_of_ids(ids: Array) -> Dictionary:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := String(ids[i])
			var b := String(ids[j])
			if FUSION.has(a + "+" + b):
				return FUSION[a + "+" + b]
			if FUSION.has(b + "+" + a):
				return FUSION[b + "+" + a]
	return {}

# ——— 主动技能效果表（战斗技能栏使用） ———

## kind:   damage 伤害 / heal 治疗 / buff 强化 / debuff 削弱
## target: single 单体 / aoe 群体
## range:  施法距离（格）；0 = 对自身施放（无需选目标）
## radius: 群体技能的影响半径（仅 aoe 使用）
## uses:   每场使用次数
const ACTIVE_DEFAULT := {"kind": "damage", "target": "single", "range": 1, "radius": 1, "power": 4, "uses": 3}

const ACTIVE_EFFECTS := {
	# 感染系
	"bite": {"kind": "damage", "target": "single", "range": 1, "power": 4, "uses": 4},
	"toxic_cloud": {"kind": "damage", "target": "aoe", "range": 3, "radius": 1, "power": 3, "uses": 2},
	"spore_burst": {"kind": "damage", "target": "aoe", "range": 3, "radius": 2, "power": 4, "uses": 1},
	# 仙体系
	"flying_sword": {"kind": "damage", "target": "single", "range": 5, "power": 5, "uses": 4},
	"talisman": {"kind": "damage", "target": "single", "range": 4, "power": 4, "uses": 2},
	"aura_shield": {"kind": "buff", "target": "single", "range": 0, "power": 3, "stat": "defense", "uses": 1},
	"myriad_swords": {"kind": "damage", "target": "aoe", "range": 4, "radius": 2, "power": 5, "uses": 1},
	"golden_body": {"kind": "buff", "target": "single", "range": 0, "power": 3, "stat": "defense", "uses": 1},
	# 义体系
	"suppression": {"kind": "debuff", "target": "aoe", "range": 5, "radius": 2, "power": 2, "stat": "hit", "uses": 2},
	"overload": {"kind": "buff", "target": "single", "range": 0, "power": 3, "stat": "damage", "uses": 3},
	"drone": {"kind": "damage", "target": "single", "range": 4, "power": 4, "uses": 1},
	"emp": {"kind": "debuff", "target": "aoe", "range": 3, "radius": 2, "power": 2, "stat": "stun", "uses": 1},
	# 血族
	"blood_drain": {"kind": "damage_heal", "target": "single", "range": 1, "power": 4, "heal": 3, "uses": 3},
	"bat_step": {"kind": "damage", "target": "single", "range": 2, "power": 3, "uses": 2},
	"bat_swarm": {"kind": "damage", "target": "single", "range": 4, "power": 5, "uses": 1},
	# 狼人
	"frenzy": {"kind": "buff", "target": "single", "range": 0, "power": 2, "stat": "damage", "uses": 1},
	"pounce": {"kind": "damage", "target": "single", "range": 3, "power": 5, "uses": 3},
	"roar": {"kind": "debuff", "target": "aoe", "range": 2, "radius": 1, "power": 2, "stat": "hit", "uses": 2},
	"call_pack": {"kind": "damage", "target": "single", "range": 0, "power": 4, "uses": 1},
	# 天使
	"heal_touch": {"kind": "heal", "target": "single", "range": 2, "power": 5, "uses": 3},
	"sanctuary": {"kind": "buff", "target": "single", "range": 2, "power": 2, "stat": "defense", "uses": 2},
	"holy_smite": {"kind": "damage", "target": "aoe", "range": 3, "radius": 1, "power": 4, "uses": 2},
	"purify": {"kind": "heal", "target": "single", "range": 0, "power": 3, "uses": 2},
	"divine_verdict": {"kind": "damage", "target": "single", "range": 3, "power": 6, "uses": 2},
	"oath_guard": {"kind": "buff", "target": "single", "range": 2, "power": 3, "stat": "defense", "uses": 1},
	# 恶魔
	"abyss_whisper": {"kind": "debuff", "target": "single", "range": 4, "power": 2, "stat": "hit", "uses": 2},
	"pact": {"kind": "buff", "target": "single", "range": 0, "power": 4, "stat": "damage", "uses": 3},
	"blood_sacrifice": {"kind": "damage", "target": "single", "range": 1, "power": 7, "uses": 2},
	"hellfire": {"kind": "damage", "target": "aoe", "range": 4, "radius": 2, "power": 5, "uses": 2},
	"soul_chain": {"kind": "debuff", "target": "single", "range": 4, "power": 2, "stat": "stun", "uses": 1},
	# 外神
	"tendril": {"kind": "damage", "target": "single", "range": 3, "power": 4, "uses": 3},
	"void_step": {"kind": "damage", "target": "single", "range": 2, "power": 3, "uses": 3},
	"warp": {"kind": "damage", "target": "single", "range": 0, "power": 3, "uses": 2},
	"reality_erode": {"kind": "damage", "target": "aoe", "range": 3, "radius": 2, "power": 4, "uses": 2},
	"dominate": {"kind": "debuff", "target": "single", "range": 4, "power": 2, "stat": "hit", "uses": 1},
	"madness_wave": {"kind": "damage", "target": "aoe", "range": 3, "radius": 2, "power": 3, "uses": 1},
}

## 取主动技能效果（未定义则回落到默认）。
static func active_effect(node_id: String) -> Dictionary:
	var out := ACTIVE_DEFAULT.duplicate()
	var e: Dictionary = ACTIVE_EFFECTS.get(node_id, {})
	out.merge(e, true)
	return out

## 按技能 id 找名字（跨全部血统）。
static func node_name(node_id: String) -> String:
	for id in all_ids():
		for r in RANKS:
			for node in candidates(id, r):
				if String(node.get("id", "")) == node_id:
					return String(node.get("name", node_id))
	return node_id

## 效果的中文简述（用于技能菜单，标注 单体/群体 与射程）。
static func effect_text(node_id: String) -> String:
	var e := active_effect(node_id)
	var kind := String(e.get("kind", "damage"))
	var power := int(e.get("power", 0))
	var scope := "群体" if String(e.get("target", "single")) == "aoe" else "单体"
	var rng := int(e.get("range", 1))
	var where := "自身" if rng <= 0 else ("射程 %d" % rng)
	match kind:
		"damage":
			return "%s %d 伤害 · %s" % [scope, power, where]
		"damage_heal":
			return "%s %d 伤害 + 回复 %d · %s" % [scope, power, int(e.get("heal", 0)), where]
		"heal":
			return "治疗 %d · %s" % [power, where]
		"buff":
			var stat := "防御" if String(e.get("stat", "defense")) == "defense" else "伤害"
			return "%s +%d（本场）· %s" % [stat, power, where]
		"debuff":
			return "%s 削弱 %d · %s" % [scope, power, where]
	return kind

## 该技能是否是群体技能。
static func is_aoe(node_id: String) -> bool:
	return String(active_effect(node_id).get("target", "single")) == "aoe"

## 该技能的施法距离。
static func skill_range(node_id: String) -> int:
	return int(active_effect(node_id).get("range", 1))

# ——— 查询 ———

static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for k in DEFS:
		out.append(String(k))
	return out

static func has(id: String) -> bool:
	return DEFS.has(id)

static func def_of(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func name_of(id: String) -> String:
	return String(def_of(id).get("name", id))

static func family_of(id: String) -> String:
	return String(def_of(id).get("family", ""))

static func world_of(id: String) -> String:
	return String(def_of(id).get("world", ""))

static func tags_of(id: String) -> Array:
	return def_of(id).get("tags", [])

static func rank_of(entry: Dictionary) -> String:
	var r := String(entry.get("rank", "D"))
	return r if RANK_LEVEL.has(r) else "D"

static func level_of(entry: Dictionary) -> int:
	return int(RANK_LEVEL.get(rank_of(entry), 1))

## 某系某级的候选技能列表。
static func candidates(id: String, rank: String) -> Array:
	var ranks: Dictionary = def_of(id).get("ranks", {})
	return ranks.get(rank, [])

## 每级可选数量。
static func pick_count(rank: String) -> int:
	return int(RANK_PICK.get(rank, 2))

## 升级到目标评级所需奖励点（从 D 起累计不含在内，仅差价）。
static func upgrade_cost(to_rank: String) -> int:
	return int(RANK_UPGRADE_COST.get(to_rank, 0))

# ——— 关系计算（纯函数） ———

## 两个标签集合之间的对立强度之和。
static func opposed_strength(tags_a: Array, tags_b: Array) -> int:
	var total := 0
	for a in tags_a:
		var foe := String(OPPOSED.get(String(a), ""))
		if foe != "" and tags_b.has(foe):
			total += int(OPPOSE_WEIGHT.get(String(a), 0))
	return total

## 两个标签集合之间的互补对数（单向遍历 a，避免重复计数）。
static func synergy_pairs(tags_a: Array, tags_b: Array) -> int:
	var n := 0
	for a in tags_a:
		var partners: Array = SYNERGY.get(String(a), [])
		for b in tags_b:
			if partners.has(String(b)):
				n += 1
	return n

## 同源标签数（交集大小）。
static func shared_tags(tags_a: Array, tags_b: Array) -> int:
	var n := 0
	for t in tags_a:
		if tags_b.has(t):
			n += 1
	return n

## 排斥度：Σ[对立强度 × (1 + 0.15 × (等级和))]，封顶 100。
## owned 形如 [{"id": "vampire", "rank": "D"}, ...]
static func rejection(owned: Array) -> int:
	var total := 0.0
	for i in owned.size():
		for j in range(i + 1, owned.size()):
			var a: Dictionary = owned[i]
			var b: Dictionary = owned[j]
			var strength := opposed_strength(tags_of(String(a.get("id", ""))), tags_of(String(b.get("id", ""))))
			if strength <= 0:
				continue
			var lv := float(level_of(a) + level_of(b))
			total += float(strength) * (1.0 + 0.15 * lv)
	return int(minf(100.0, roundf(total)))

## 协同度：Σ[互补对数 × 15 × (1 + 0.1 × 等级和)] + 同源数 × 5，封顶 60。
static func synergy(owned: Array) -> int:
	var total := 0.0
	for i in owned.size():
		for j in range(i + 1, owned.size()):
			var a: Dictionary = owned[i]
			var b: Dictionary = owned[j]
			var ta := tags_of(String(a.get("id", "")))
			var tb := tags_of(String(b.get("id", "")))
			var lv := float(level_of(a) + level_of(b))
			total += float(synergy_pairs(ta, tb)) * 15.0 * (1.0 + 0.1 * lv)
			total += float(shared_tags(ta, tb)) * 5.0
	return int(minf(60.0, roundf(total)))

# ——— 档位与效果 ———

static func rejection_tier(v: int) -> String:
	if v >= 100:
		return "collapse"
	if v >= 50:
		return "unstable"
	if v >= 10:
		return "interference"
	return "none"

static func synergy_tier(v: int) -> String:
	if v >= 50:
		return "synergy"
	if v >= 30:
		return "major"
	if v >= 10:
		return "minor"
	return "none"

## 排斥度的具体效果（供战斗系统读取）。
static func rejection_effects(v: int) -> Dictionary:
	var e := {"hit": 0, "damage": 0, "defense": 0, "unstable_chance": 0.0, "node_bonus": 1.0}
	if v >= 10:
		# 标定说明：本作战斗是**骰池系统**（伤害基数 2–5），而非火纹式百分比。
		# 因此 -10 命中 ≈ -1 个成功（每 10 点命中 ≈ 1 成功）；
		# 伤害若按 -2 会直接把基础伤害打到 0，故定为 -1。
		e["hit"] = -10
		e["damage"] = -1
		e["defense"] = -1
	if v >= 50:
		e["unstable_chance"] = clampf(float(v) / 100.0, 0.0, 0.95)
		e["node_bonus"] = 1.2   # 血脉沸腾：节点效果 +20%
	if v >= 80:
		e["node_bonus"] = 1.35  # +35%，并解锁融合技（由玩法层判断）
	return e

## 协同度的具体效果。
static func synergy_effects(v: int) -> Dictionary:
	var e := {"node_bonus": 1.0, "share_skills": false, "combo_unlocked": false}
	if v >= 10:
		e["node_bonus"] = 1.1
	if v >= 30:
		e["node_bonus"] = 1.2
		e["share_skills"] = true
	if v >= 50:
		e["node_bonus"] = 1.35
		e["combo_unlocked"] = true
	return e

# ——— 数据自检 ———

## 返回问题列表（空数组 = 数据健康）。
static func validate() -> Array[String]:
	var problems: Array[String] = []
	# 1. 对立表对称
	for t in TAGS:
		var foe := String(OPPOSED.get(t, ""))
		if foe == "":
			problems.append("标签 %s 缺少对立标签" % t)
		elif String(OPPOSED.get(foe, "")) != t:
			problems.append("对立关系不对称：%s ↔ %s" % [t, foe])
	# 2. 互补表对称
	for t in TAGS:
		var partners: Array = SYNERGY.get(t, [])
		if partners.size() != 2:
			problems.append("标签 %s 的互补数应为 2，实际 %d" % [t, partners.size()])
		for p in partners:
			var back: Array = SYNERGY.get(String(p), [])
			if not back.has(t):
				problems.append("互补关系不对称：%s → %s" % [t, p])
	# 3. 八系数据完整性
	for id in all_ids():
		var d := def_of(id)
		if d.get("tags", []).is_empty():
			problems.append("血统 %s 缺少谱系标签" % id)
		for t in d.get("tags", []):
			if not TAGS.has(t):
				problems.append("血统 %s 含未知标签 %s" % [id, t])
		var ranks: Dictionary = d.get("ranks", {})
		for r in RANKS:
			var list: Array = ranks.get(r, [])
			var want := int(RANK_CANDIDATES.get(r, 0))
			if list.size() != want:
				problems.append("血统 %s 的 %s 级候选数应为 %d，实际 %d" % [id, r, want, list.size()])
			for node in list:
				for key in ["id", "name", "type", "desc"]:
					if not node.has(key):
						problems.append("血统 %s %s 级节点缺少字段 %s" % [id, r, key])
				if not NODE_TYPES.has(String(node.get("type", ""))):
					problems.append("血统 %s %s 级节点 %s 类型非法" % [id, r, node.get("id", "?")])
			if int(RANK_PICK.get(r, 0)) > list.size():
				problems.append("血统 %s 的 %s 级可选数超过候选数" % [id, r])
	return problems
