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

# ——— 行动条（CTB 行动值模型）———
var speed: int = 5           # 行动速度：越高，每次行动后加的行动值越少 → 出手越频繁
var av: float = 0.0          # 行动值（Action Value）：越小越先行动
var rounds_taken: int = 0    # 自己行动过几次；「第几回合」= 所有存活单位里最慢的那个 + 1
var tactical: int = 0        # 指挥点（玩家方共享池；独狼时就是自己的智力/2）
var slot: int = -1           # 玩家方槽位 0..3（敌人为 -1）—— 团队模式的稳定 id，不要用数组下标

var char_ref: Character = null   # 玩家单位引用（用于天赋/基因锁）

## p_slot：玩家方槽位。p0 = 玩家本人（uid 保持 "player" 以兼容旧逻辑），p1..p3 = 队友。
static func from_player(c: Character, p_slot: int = 0) -> CombatUnit:
	var u := CombatUnit.new()
	u.uid = "player" if p_slot == 0 else "p%d" % p_slot
	u.slot = p_slot
	u.name = c.name
	u.is_player = true
	u.char_ref = c
	u.hp = c.hp
	u.max_hp = c.max_hp()
	# 玩家护甲已在 Character.defense() 中折算，不再重复写入 armor（避免双重减伤）
	u.defense = c.defense()
	u.init = DicePool.roll_initiative(c.attr("dex"), c.attr("com"))
	u.move = 4
	# 行动条：速度 = 敏捷为主 + 沉着为辅 + 2 基数（常人落在 5~7）。
	# 这样敏捷从「只管移动力与防御」升级为出手频率，沉着也不只是先攻。
	u.speed = c.attr("dex") + int(c.attr("com") / 2) + 2
	# 指挥点：智力/2（属性重做方案里「看穿弱点」的战棋出口），由 CombatManager 汇总为共享池
	u.tactical = int(c.attr("int") / 2)
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
	# 行动条：数据表 speed 优先；缺省由先攻折算（敌人 init 3~8 → speed 4~7）
	u.speed = int(d.get("speed", 3 + int(d.get("init", 3)) / 2))
	u.dp_attack = int(d.get("dp_attack", 5))
	u.damage_bonus = int(d.get("damage_bonus", 1))
	u.move = int(d.get("move", 3))
	u.melee_range = 1
	u.armor = int(d.get("armor", 0))   # 敌人护甲（数据表可选字段，缺省 0）
	u.reward = int(d.get("reward", 5))
	u.boss = bool(d.get("boss", false))
	u.tags.assign(d.get("tags", []))
	return u
