class_name CombatUnit
extends RefCounted
## 战斗单位：轮回者或敌人，含战场格坐标与战斗数值。

var uid: String
var name: String
var is_player: bool
var pos: Vector2i
var hp: int
var max_hp: int
var defense: int
var armor: int = 0          # 额外伤害吸收（敌人）
var init: int
var ap: int = 0
var max_ap: int = 6
var dp_attack: int = 0      # 敌人攻击骰池
var damage_bonus: int = 0
var move: int = 4           # 每回合可移动格数
var melee_range: int = 1
var ranged: bool = false
var ranged_range: int = 1
var reward: int = 0
var boss: bool = false
var tags: Array[String] = []
var defending: bool = false
# 属性重做·意志力用法（每回合限 1 次，消耗 1 点意志）
var will_focus: bool = false    # 专注：下次攻击 +1 成功
var will_dodge: bool = false    # 闪避：抵消一次命中
var has_acted: bool = false      # 本场战斗是否已行动过（首轮未行动者处于措手不及）

var char_ref: Character = null   # 玩家单位引用（用于天赋/基因锁）

static func from_player(c: Character) -> CombatUnit:
	var u := CombatUnit.new()
	u.uid = "player"
	u.name = c.name
	u.is_player = true
	u.char_ref = c
	u.hp = c.hp
	u.max_hp = c.max_hp()
	# 玩家护甲已在 Character.defense() 中折算，不再重复写入 armor（避免双重减伤）
	u.defense = c.defense()
	u.init = DicePool.roll_initiative(c.attr("dex"), c.attr("com"))
	u.move = 4
	var w := c.weapon_def()
	if w.get("skill", "") == "gun":
		u.ranged = true
		u.ranged_range = int(w.get("range", 4))
	else:
		u.melee_range = 1
	return u

## uid_override：让战斗单位的 uid 与**探索层的 uid 完全一致**。
## 否则「已击杀」表里存的 key 对不上，切回房间尸体会复活。
static func from_enemy(eid: String, pos: Vector2i, uid_override: String = "") -> CombatUnit:
	var d: Dictionary = Enemies.get_def(eid)
	var u := CombatUnit.new()
	u.uid = uid_override if uid_override != "" else "enemy_%d_%d" % [pos.x, pos.y]
	u.name = String(d.get("name", eid))
	u.is_player = false
	u.pos = pos
	u.hp = int(d.get("hp", 10))
	u.max_hp = u.hp
	u.defense = int(d.get("defense", 3))
	u.init = DicePool.roll_initiative(int(d.get("init", 3)), 0)
	u.dp_attack = int(d.get("dp_attack", 5))
	u.damage_bonus = int(d.get("damage_bonus", 1))
	u.move = int(d.get("move", 3))
	u.melee_range = 1
	u.armor = int(d.get("armor", 0))   # 敌人护甲（数据表可选字段，缺省 0）
	u.reward = int(d.get("reward", 5))
	u.boss = bool(d.get("boss", false))
	u.tags.assign(d.get("tags", []))
	return u
