class_name Character
extends RefCounted
## 轮回者角色数据模型。属性/技能/天赋/装备/生命意志/基因锁。

const BASE_HP_PER_END := 4

var name: String = "轮回者"
var attrs: Dictionary = {}        # attr_id -> int
var skills: Dictionary = {}       # skill_id -> int
var talent_id: String = ""
var weapon: String = "fists"
var armor: String = ""
var inventory: Array[String] = []
var ammo: Dictionary = {}         # 武器id -> 剩余弹药
var hp: int = 10
var will: int = 4
var gene_lock_level: int = 0      # 0 未解锁 / 1 一阶
var gene_lock_unlocked: bool = false  # 本次是否已触发过
## 血统：[{"id": "vampire", "rank": "D", "picked": ["blood_sense", "night_affinity"]}]
## **空数组 = 纯人类**，与旧存档完全等价。
var bloodlines: Array = []
## 血统排斥的缓解状态（P3）
var bloodline_suppress: int = 0     # 本场「意志力压制」减免（−10）
var bloodline_tolerance: int = 0    # 「调和手术」永久减免（每次 −20，入档）
var bloodline_stabilizer: int = 0   # 「稳定剂」剩余回合（>0 时额外 −15）

static func create_default() -> Character:
	var c := Character.new()
	for a in Attrs.ALL:
		c.attrs[a] = 1
	for s in Skills.ALL:
		c.skills[s] = 0
	c.name = "轮回者"
	c.weapon = "fists"
	c.refresh()
	return c

func attr(id: String) -> int:
	return int(attrs.get(id, 1)) + bloodline_attr_bonus(id)

func skill(id: String) -> int:
	return int(skills.get(id, 0))

# ——— 派生数值 ———

## 属性重做：生命 = 8 + 4×耐力（原为 4×耐力，加一层"基础体质"）
func max_hp() -> int:
	var v := 8 + attr("end") * BASE_HP_PER_END
	if has_tag("hp_plus_4"):
		v += 4
	return v

## 属性重做：意志力池 = 2×决心（决心独享 —— 让它从废属性变成战斗资源属性）
func max_will() -> int:
	return 2 * attr("res")

# ——— 属性重做：一属性一机制（派生战斗值）———

## 感知 → 暴击率（%）：5 × 感知
func crit_rate() -> int:
	return 5 * attr("per")

## 敏捷 → 移动力（格）：3 + 敏捷/2
func move_range() -> int:
	return 3 + int(attr("dex") / 2)

## 智力 → 战术点（每场可用次数）：智力/2
func tactical_points() -> int:
	return int(attr("int") / 2)

## 风度 → 指挥光环半径（格）：风度/2
func aura_range() -> int:
	return int(attr("pre") / 2)

## 风度 → 光环给队友的命中加成（≥4 时 +2）
func aura_hit_bonus() -> int:
	return 2 if attr("pre") >= 4 else 1

## 操控 → 威慑：相邻敌人命中 −1（操控 ≥4 时 −2）
func intimidate_penalty() -> int:
	return 2 if attr("man") >= 4 else 1

## 沉着 → 处变不惊：每回合首次受击减伤 = 沉着/3
func first_hit_reduction() -> int:
	return int(attr("com") / 3)

## 防御值 = 敏捷 + 躲藏/2（向下取整）+ 护甲 + 基因锁。
func defense() -> int:
	var d := attr("dex") + skill("hide") / 2
	if armor != "":
		var ad: Dictionary = Items.get_def(armor)
		d += int(ad.get("armor", 0))
	if gene_lock_level >= 1:
		d += 1   # 基因锁一阶：防御 +1（RE25 基因锁：一阶提升生存本能）
	return d

func init_flat() -> int:
	return attr("dex") + attr("com")

## 武器信息。
func weapon_def() -> Dictionary:
	var w: Dictionary = Items.get_def(weapon)
	if w.is_empty():
		w = Items.get_def("bat")
	return w

func has_ammo() -> bool:
	var w := weapon_def()
	if w.get("skill", "") != "gun":
		return true
	return ammo_left() > 0

func spend_ammo() -> void:
	var w := weapon_def()
	if w.get("skill", "") != "gun":
		return
	ammo[weapon] = ammo_left() - 1

func ammo_left() -> int:
	var w := weapon_def()
	if w.get("skill", "") != "gun":
		return -1
	if ammo.has(weapon):
		return int(ammo[weapon])
	var base := int(w.get("ammo", 0))
	if has_tag("ammo_plus_4"):
		base += 4
	return base

## 攻击骰池：近战 str + 对应技能；远程 dex + 枪械。
func attack_pool() -> Dictionary:
	var w := weapon_def()
	var skill_id := String(w.get("skill", "brawl"))
	if skill_id == "gun":
		return {"attr": "dex", "skill": "gun", "dp_attr": attr("dex"), "dp_skill": skill(skill_id)}
	return {"attr": "str", "skill": skill_id, "dp_attr": attr("str"), "dp_skill": skill(skill_id)}

## 武器伤害加值（规则书：命中伤害 = 溢出成功数 + 武器伤害）。
## 由 CombatManager.resolve_attack 计入结算，见 systems/combat_manager.gd。
## 武器伤害 = 武器基础 + 主属性/2（近战用力量、远程用感知）
## ——让「感知」除了暴击之外，也真正管住远程输出。
func weapon_damage() -> int:
	var w := weapon_def()
	var base := int(w.get("damage", 1))
	var skill_id := String(w.get("skill", "brawl"))
	var ranged: bool = skill_id == "gun" or int(w.get("range", 1)) > 1
	var scale_attr := "per" if ranged else "str"
	return base + int(attr(scale_attr) / 2)

## 伤害加成（天赋/基因锁；不含武器伤害）。
func damage_bonus(ranged: bool) -> int:
	var db := 0
	if ranged:
		if has_tag("ranged_damage_1"):
			db += 1
	else:
		if has_tag("melee_damage_1"):
			db += 1
	if gene_lock_level >= 1:
		db += 1
	return db

## 检定成功数附加（天赋）。
func check_extra_success(attr_id: String, skill_id: String) -> int:
	var es := 0
	if has_tag("knowledge_plus_1") and Attrs.category_of(attr_id) == "心智":
		es += 1
	if has_tag("social_plus_1") and Attrs.category_of(attr_id) == "互动":
		es += 1
	return es

func has_tag(tag: String) -> bool:
	var t: Dictionary = Talents.get_def(talent_id)
	var tags: Array = t.get("tags", [])
	return tag in tags

# ——— 血统 ———

func has_bloodline(id: String) -> bool:
	for e in bloodlines:
		if String(e.get("id", "")) == id:
			return true
	return false

## 该血统的评级（"" = 未拥有）。
func bloodline_rank(id: String) -> String:
	for e in bloodlines:
		if String(e.get("id", "")) == id:
			return String(e.get("rank", "D"))
	return ""

## 全部已选血统技能的 id。
func bloodline_nodes() -> Array[String]:
	var out: Array[String] = []
	for e in bloodlines:
		for n in e.get("picked", []):
			out.append(String(n))
	return out

func has_bloodline_node(node_id: String) -> bool:
	return bloodline_nodes().has(node_id)

## 已选的血统**主动技能**（供战斗技能栏使用）。
func bloodline_active_skills() -> Array:
	var out: Array = []
	for e in bloodlines:
		var id := String(e.get("id", ""))
		if not Bloodlines.has(id):
			continue
		var max_lv := int(Bloodlines.RANK_LEVEL.get(String(e.get("rank", "D")), 1))
		var picked: Array = e.get("picked", [])
		for r in Bloodlines.RANKS:
			if int(Bloodlines.RANK_LEVEL.get(r, 1)) > max_lv:
				break
			for node in Bloodlines.candidates(id, r):
				if picked.has(String(node.get("id", ""))) and String(node.get("type", "")) == "active":
					out.append(node)
	return out

## 血统属性节点带来的加成（如「血色体质」耐力 +1）。
## 注意：属性节点**不被血脉沸腾/共鸣放大**（整数属性不做百分比缩放）。
func bloodline_attr_bonus(attr_id: String) -> int:
	var total := 0
	for e in bloodlines:
		var id := String(e.get("id", ""))
		if not Bloodlines.has(id):
			continue
		var max_lv := int(Bloodlines.RANK_LEVEL.get(String(e.get("rank", "D")), 1))
		var picked: Array = e.get("picked", [])
		for r in Bloodlines.RANKS:
			if int(Bloodlines.RANK_LEVEL.get(r, 1)) > max_lv:
				break
			for node in Bloodlines.candidates(id, r):
				if not picked.has(String(node.get("id", ""))):
					continue
				if String(node.get("type", "")) == "attr" and String(node.get("attr", "")) == attr_id:
					total += int(node.get("value", 1))
	return total

## 实际排斥度 = 原始排斥 − 本场压制 − 永久调和 − 稳定剂。
## 三种缓解手段能真正把角色从「基因崩溃」边缘拉回来 —— 这就是它们存在的意义。
func bloodline_rejection() -> int:
	var raw := Bloodlines.rejection(bloodlines)
	if raw <= 0:
		return 0
	var cut := bloodline_suppress + bloodline_tolerance
	if bloodline_stabilizer > 0:
		cut += 15
	return maxi(0, raw - cut)

# ——— P3 缓解手段 ———

## 意志力压制：每场一次，花 2 点意志力换 −10 排斥。
func can_suppress_bloodline() -> bool:
	return bloodline_suppress == 0 and bloodline_rejection() >= 10 and will >= 2

func suppress_bloodline() -> bool:
	if not can_suppress_bloodline():
		return false
	will -= 2
	bloodline_suppress = 10
	return true

## 血脉稳定剂：若干回合内额外 −15 排斥。
func use_stabilizer(turns: int = 3) -> void:
	bloodline_stabilizer = turns

## 回合推进（稳定剂计时）。
func tick_bloodline() -> void:
	if bloodline_stabilizer > 0:
		bloodline_stabilizer = maxi(0, bloodline_stabilizer - 1)

## 战斗结束：清空本场临时减免（永久调和保留）。
func clear_battle_bloodline_buffs() -> void:
	bloodline_suppress = 0
	bloodline_stabilizer = 0

## 调和手术成本 = 血统已投入奖励点的 30%。
func tolerance_repair_cost() -> int:
	var invested := 0
	for e in bloodlines:
		var idx := Bloodlines.RANKS.find(String(e.get("rank", "D")))
		for k in range(0, idx + 1):
			invested += Bloodlines.upgrade_cost(Bloodlines.RANKS[k])
	return int(float(invested) * 0.3)

func apply_tolerance_repair() -> void:
	bloodline_tolerance += 20

# ——— P4 高风险与终局 ———

## 基因崩溃：实际排斥度达到 100% 时，角色将在战斗/探索结束时死亡。
func is_gene_collapsed() -> bool:
	return not bloodlines.is_empty() and bloodline_rejection() >= 100

## 已解锁的融合技（排斥 ≥80 且持有对应血统组合）。
func fusion_skill() -> Dictionary:
	if bloodline_rejection() < 80:
		return {}
	return Bloodlines.fusion_of_ids(_bloodline_ids())

func _bloodline_ids() -> Array:
	var out: Array = []
	for e in bloodlines:
		out.append(String(e.get("id", "")))
	return out

func bloodline_synergy() -> int:
	return Bloodlines.synergy(bloodlines)

## 血统对战斗的全部修正（排斥惩罚 + 协同/沸腾加成）。
## 供 CombatManager 读取：hit/damage/defense 为平值修正；
## unstable_chance 为每回合失控概率；node_bonus 用于放大血统技能的数值。
func bloodline_combat_mods() -> Dictionary:
	var mods := {
		"hit": 0, "damage": 0, "defense": 0, "unstable_chance": 0.0,
		"node_bonus": 1.0, "share_skills": false, "combo_unlocked": false,
		"rejection": 0, "synergy": 0,
	}
	if bloodlines.is_empty():
		return mods
	var rj := bloodline_rejection()
	var sy := bloodline_synergy()
	var re := Bloodlines.rejection_effects(rj)
	var se := Bloodlines.synergy_effects(sy)
	mods["hit"] = int(re["hit"])
	mods["damage"] = int(re["damage"])
	mods["defense"] = int(re["defense"])
	mods["unstable_chance"] = float(re["unstable_chance"])
	mods["node_bonus"] = maxf(float(re["node_bonus"]), float(se["node_bonus"]))
	mods["share_skills"] = bool(se["share_skills"])
	mods["combo_unlocked"] = bool(se["combo_unlocked"])
	mods["rejection"] = rj
	mods["synergy"] = sy
	return mods

# ——— 状态 ———

func refresh() -> void:
	hp = mini(hp, max_hp())
	will = mini(will, max_will())

func is_alive() -> bool:
	return hp > 0

## 生命比例（0-1），用于基因锁触发判定。
func hp_ratio() -> float:
	if max_hp() <= 0:
		return 0.0
	return float(hp) / float(max_hp())

## 尝试开启基因锁：HP ≤ 30% 且未解锁。
func try_unlock_gene_lock() -> bool:
	if gene_lock_unlocked or gene_lock_level >= 1:
		return false
	if hp_ratio() > 0.3:
		return false
	gene_lock_level = 1
	gene_lock_unlocked = true
	return true

# ——— 序列化 ———

func to_dict() -> Dictionary:
	return {
		"name": name, "attrs": attrs, "skills": skills, "talent_id": talent_id,
		"weapon": weapon, "armor": armor, "inventory": inventory, "ammo": ammo,
		"hp": hp, "will": will, "gene_lock_level": gene_lock_level,
		"bloodlines": bloodlines,
		"bloodline_tolerance": bloodline_tolerance,
	}

func from_dict(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	name = String(d.get("name", "轮回者"))
	attrs.assign(d.get("attrs", {}))
	skills.assign(d.get("skills", {}))
	talent_id = String(d.get("talent_id", ""))
	weapon = String(d.get("weapon", "fists"))
	armor = String(d.get("armor", ""))
	inventory.assign(d.get("inventory", []))
	ammo.assign(d.get("ammo", {}))
	hp = int(d.get("hp", 10))
	will = int(d.get("will", 4))
	gene_lock_level = int(d.get("gene_lock_level", 0))
	# v2 及更早的存档没有 bloodlines 字段 → 默认空数组（纯人类），行为不变
	var bl: Variant = d.get("bloodlines", [])
	bloodlines = (bl as Array).duplicate() if bl is Array else []
	bloodline_tolerance = int(d.get("bloodline_tolerance", 0))
	# 本场临时减免不入档，读档后重置
	bloodline_suppress = 0
	bloodline_stabilizer = 0
	return attrs.size() > 0
