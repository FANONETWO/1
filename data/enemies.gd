class_name Enemies
extends RefCounted
## 敌人定义。用与轮回者相同的属性/技能 + 战斗数值描述。
## dp_attack: 攻击骰池；defense: 防御值；hp: 生命；init: 先攻加值。
##
## ——— 丧尸世界的威胁分层 ———
##   walker   逐尸    弱、慢，但**永远成群** —— 尸潮的主力，靠数量压人
##   zombie   丧尸    标准个体，独行或两三只
##   crawler  爬行者  天花板上的速度威胁，逼你不能背对走廊
##   hound    尸犬    最快的追猎者，车库与长走廊
##   screamer 嘶叫者  它不咬人 —— 它叫。一次尖叫把整层楼的都招来
##   bloater  膨胀者  慢、厚，**死在这里会污染这里的空气**
##   cadaver  伏尸    躺在地上装尸体，走到跟前才动 —— 心理威胁
##   brute    尸王    前保安队长，Boss

const ALL := {
	"walker": {
		"id": "walker", "name": "逐尸",
		"desc": "半张脸没了，走得很慢。一只不可怕 —— 可怕的是它们从不单独出现。",
		"dp_attack": 3, "damage_bonus": 0, "defense": 2, "hp": 6, "init": 1,
		"move": 2, "melee": true, "reward": 3,
		"tags": ["undead", "horde"],
	},
	"zombie": {
		"id": "zombie", "name": "丧尸",
		"desc": "曾是这栋楼的住户。皮肤灰败，指甲发黑，闻到活人的气味就扑上来。",
		"dp_attack": 5, "damage_bonus": 1, "defense": 3, "hp": 12, "init": 3,
		"move": 3, "melee": true, "reward": 8,
		"tags": ["undead"],
	},
	"crawler": {
		"id": "crawler", "name": "爬行者",
		"desc": "四肢扭曲地伏在走廊天花板上，速度快得不像话。",
		"dp_attack": 4, "damage_bonus": 2, "defense": 2, "hp": 8, "init": 6,
		"move": 5, "melee": true, "reward": 6,
		"tags": ["undead", "fast"],
	},
	"hound": {
		"id": "hound", "name": "尸犬",
		"desc": "谁家的狗已经看不出来了。它跑起来没有声音，只有爪子刮地的动静。",
		"dp_attack": 5, "damage_bonus": 2, "defense": 3, "hp": 10, "init": 8,
		"move": 6, "melee": true, "reward": 9,
		"tags": ["undead", "fast"],
	},
	"screamer": {
		"id": "screamer", "name": "嘶叫者",
		"desc": "它的喉咙烂穿了，可它还在叫。它自己不咬人 —— 它把会咬人的都叫来。",
		"dp_attack": 3, "damage_bonus": 0, "defense": 2, "hp": 10, "init": 4,
		"move": 3, "melee": true, "reward": 12,
		"tags": ["undead", "caller"],
	},
	"bloater": {
		"id": "bloater", "name": "膨胀者",
		"desc": "肚子涨得像要裂开。它走得很慢，但你最好别在它旁边开枪。",
		"dp_attack": 4, "damage_bonus": 3, "defense": 5, "hp": 18, "init": 1,
		"move": 2, "melee": true, "reward": 15,
		"tags": ["undead", "toxic"],
	},
	"cadaver": {
		"id": "cadaver", "name": "伏尸",
		"desc": "它躺在地上一动不动，和旁边的尸体没有区别。你在它旁边站了三秒，它才睁眼。",
		"dp_attack": 6, "damage_bonus": 2, "defense": 4, "hp": 14, "init": 5,
		"move": 3, "melee": true, "reward": 12,
		"tags": ["undead", "ambush"],
	},
	"brute": {
		"id": "brute", "name": "尸王",
		"desc": "三米高的臃肿巨尸，胸口嵌着半块防盗门。它曾是这座楼的看门人。",
		"dp_attack": 7, "damage_bonus": 4, "defense": 4, "hp": 34, "init": 2,
		"move": 2, "melee": true, "reward": 40, "boss": true,
		"tags": ["undead", "boss"],
	},
}

static func get_def(id: String) -> Dictionary:
	return ALL.get(id, {})

static func name_of(id: String) -> String:
	var d: Dictionary = ALL.get(id, {})
	return String(d.get("name", id))

## 是否属于「尸潮」类型（会被噪音大量召唤）
static func is_horde(id: String) -> bool:
	return "horde" in get_def(id).get("tags", [])
