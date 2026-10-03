class_name CombatManager
extends RefCounted
## 回合制战斗管理器（纯逻辑，不依赖场景，可单测）。
## AP 行动点：移动 1 格 1 AP / 攻击 3 AP / 使用道具 2 AP / 防御姿态 2 AP。
## 攻击结算（规则书「成功数即伤害」）：攻击成功数 - 目标防御 = 溢出成功数，
## 伤害 = max(1, 溢出成功数) + 攻击者伤害加成 - 目标护甲吸收。
## 基因锁：玩家生命 ≤30% 自动开锁（+1 攻击成功 / +1 伤害 / +1 防御）；
## 若首次致死（hp≤0 且未开锁）触发「绝境爆种」：开锁 + 回 20% 生命。

const AP_MOVE := 1
const AP_ATTACK := 3
const AP_ITEM := 2
const AP_DEFEND := 2

var units: Array[CombatUnit] = []
var order: Array[CombatUnit] = []
var first_hit_used: Dictionary = {}   # 属性重做·处变不惊：本回合已触发首击减伤的单位
var turn_index: int = 0
var round: int = 1
var over: bool = false
var victory: bool = false
## 阵亡名册：单位死亡时会从 units 中移除，但战后结算（清理尸体、计算击杀积分）
## 仍然需要它们，所以在这里留一份引用。
var fallen: Array[CombatUnit] = []
var logs: Array[String] = []
var player_unit: CombatUnit

func start(player: Character, enemy_list: Array[Dictionary], player_pos: Vector2i) -> void:
	units.clear()
	order.clear()
	logs.clear()
	over = false
	victory = false
	fallen.clear()
	first_hit_used.clear()
	round = 1
	player_unit = CombatUnit.from_player(player)
	player_unit.pos = player_pos
	units.append(player_unit)
	for e in enemy_list:
		units.append(CombatUnit.from_enemy(String(e["id"]), e["pos"], String(e.get("uid", ""))))
	order = units.duplicate()
	order.sort_custom(func(a, b): return a.init > b.init)
	turn_index = 0
	_begin_turn(order[0])
	_log("战斗开始。先攻：%s" % _order_names())

func _order_names() -> String:
	var names: Array[String] = []
	for u in order:
		names.append(u.name)
	return "、".join(names)

# ——— 回合控制 ———

func current() -> CombatUnit:
	return order[turn_index]

func is_player_turn() -> bool:
	return not over and current().is_player

func _begin_turn(u: CombatUnit) -> void:
	u.ap = u.max_ap
	u.defending = false
	first_hit_used.erase(u.uid)   # 属性重做·处变不惊：新回合重新获得首击减伤

func end_turn() -> void:
	var cur := current()
	cur.ap = 0
	turn_index = (turn_index + 1) % order.size()
	if turn_index == 0:
		round += 1
	_begin_turn(current())
	if not current().is_player:
		# 敌人回合自动行动（由 UI 延迟调用 auto_turn）
		pass

## 敌人 AI：朝最近玩家单位贪心移动，进入攻击范围后攻击。
## wall_at: Callable(pos)->bool 判断格子不可走（墙或其他单位）。
## 返回 {attacked: bool, result: Dictionary, attacker, target}，供场景层播放战斗演出
## （此前返回 void，这正是「敌方攻击没有动画」的原因）。
func auto_turn(enemy: CombatUnit, wall_at: Callable) -> Dictionary:
	if over:
		return {"attacked": false}
	_log("%s 的回合。" % enemy.name)
	var target := _nearest_player(enemy)
	if target == null:
		end_turn()
		return {"attacked": false}
	# 移动：贪心逼近
	var steps := 0
	while steps < enemy.move:
		var dist := _manhattan(enemy.pos, target.pos)
		if dist <= (enemy.ranged_range if enemy.ranged else enemy.melee_range):
			break
		var best := enemy.pos
		var best_dist := dist
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for d in dirs:
			var cand: Vector2i = enemy.pos + d
			if cand == target.pos or wall_at.call(cand):
				continue
			var cd := _manhattan(cand, target.pos)
			if cd < best_dist:
				best = cand
				best_dist = cd
		if best == enemy.pos:
			break
		enemy.pos = best
		steps += 1
	# 攻击
	var dist2 := _manhattan(enemy.pos, target.pos)
	var info := {"attacked": false}
	if dist2 <= (enemy.ranged_range if enemy.ranged else enemy.melee_range):
		var r := resolve_attack(enemy, target)
		info = {"attacked": true, "result": r, "attacker": enemy, "target": target}
	end_turn()
	return info

func _nearest_player(u: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := 99999
	for x in units:
		if x.is_player and x.hp > 0:
			var d := _manhattan(u.pos, x.pos)
			if d < best_d:
				best_d = d
				best = x
	return best

# ——— 玩家动作 ———

## 移动：曼哈顿距离 ≤ 移动力即可（地图可达性由场景校验）。
func try_move(u: CombatUnit, target: Vector2i) -> bool:
	if u.ap < AP_MOVE:
		return false
	var dist := _manhattan(u.pos, target)
	if dist <= 0:
		return false
	if dist > u.move:
		return false
	u.ap -= dist * AP_MOVE
	u.pos = target
	_log("%s 移动到 (%d,%d)。" % [u.name, target.x, target.y])
	return true

func try_attack(att: CombatUnit, def_: CombatUnit) -> Dictionary:
	if att.ap < AP_ATTACK:
		return {"ok": false, "reason": "行动点不足"}
	var dist := _manhattan(att.pos, def_.pos)
	var reach := att.ranged_range if att.ranged else att.melee_range
	if dist > reach:
		return {"ok": false, "reason": "距离太远"}
	if att.ranged:
		if att.is_player and not att.char_ref.has_ammo():
			return {"ok": false, "reason": "没有弹药"}
		if att.is_player:
			att.char_ref.spend_ammo()
	att.ap -= AP_ATTACK
	var res := resolve_attack(att, def_)
	return {"ok": true, "result": res}

func try_defend(u: CombatUnit) -> bool:
	if u.ap < AP_DEFEND:
		return false
	u.ap -= AP_DEFEND
	u.defending = true
	_log("%s 采取防御姿态（+2 防御）。" % u.name)
	return true

func try_use_item(u: CombatUnit, item_id: String) -> Dictionary:
	if u.ap < AP_ITEM:
		DebugLog.ev("item", "用药被拒", {"item": item_id, "reason": "行动点不足", "ap": u.ap})
		return {"ok": false, "reason": "行动点不足"}
	var d: Dictionary = Items.get_def(item_id)
	if d.get("kind", "") != "consumable":
		DebugLog.ev("item", "用药被拒", {"item": item_id, "reason": "非消耗品"})
		return {"ok": false, "reason": "无法使用"}
	u.ap -= AP_ITEM
	var hp_before := u.hp
	var will_before := u.char_ref.will if u.is_player and u.char_ref != null else 0
	var effect := ""
	if d.has("heal_hp"):
		var healed := mini(int(d["heal_hp"]), u.max_hp - u.hp)
		u.hp += healed
		effect = "恢复 %d 点生命" % healed
	if d.has("heal_will"):
		var w := mini(int(d["heal_will"]), u.char_ref.max_will() - u.char_ref.will) if u.is_player else 0
		if u.is_player:
			u.char_ref.will += w
			effect = ("恢复 %d 点意志力" % w) if effect == "" else (effect + "，%d 点意志力" % w)
	if u.is_player:
		u.char_ref.inventory.erase(item_id)
	_log("%s 使用了 %s（%s）。" % [u.name, Items.name_of(item_id), effect])
	DebugLog.ev("item", "用药", {
		"item": item_id, "hp": [hp_before, u.hp], "max_hp": u.max_hp,
		"will": [will_before, u.char_ref.will if u.is_player and u.char_ref != null else 0],
		"effect": effect,
	})
	return {"ok": true, "effect": effect}

# ——— 攻击结算 ———

func resolve_attack(att: CombatUnit, def_: CombatUnit) -> Dictionary:
	var is_p := att.is_player
	var s := 0
	var roll_info := {}
	if is_p:
		var pool: Dictionary = att.char_ref.attack_pool()
		var extra := att.char_ref.check_extra_success(String(pool["attr"]), String(pool["skill"]))
		if att.char_ref.gene_lock_level >= 1:
			extra += 1
		if att.will_focus:          # 属性重做·意志「专注」：本次攻击 +1 成功
			extra += 1
			att.will_focus = false
		roll_info = DicePool.roll(int(pool["dp_attr"]), int(pool["dp_skill"]), 0, extra, String(pool["skill"]))
		s = int(roll_info["total"])
	else:
		# 属性重做·威慑：玩家「操控」削减敌人的**骰池**（−1~2 枚），而不是直接扣成功数
		var dp_penalty := 0
		if def_.is_player and def_.char_ref != null:
			dp_penalty = def_.char_ref.intimidate_penalty()
		roll_info = DicePool.roll(maxi(1, att.dp_attack - dp_penalty), 0, 0, 0, "")
		s = int(roll_info["total"])

	# 血统排斥：我方「血脉干扰」命中 −10 → 换算为 −1 个成功（每 10 点命中 ≈ 1 个成功）
	if is_p and att.char_ref != null:
		var att_mods: Dictionary = att.char_ref.bloodline_combat_mods()
		s = maxi(0, s + int(int(att_mods["hit"]) / 10))
	var hp_before := def_.hp
	# 血统排斥：防守方若是玩家，其防御同样受「血脉干扰」影响
	var def_bl := 0
	if def_.is_player and def_.char_ref != null:
		def_bl = int(def_.char_ref.bloodline_combat_mods()["defense"])
	var target_def := def_.defense + (2 if def_.defending else 0) + def_bl
	var overflow := maxi(0, s - target_def)
	# 结算加值 = 武器伤害 + 天赋/基因锁加成（玩家）+ 血统修正；敌人直接取自身 damage_bonus
	var dmg_bonus := (att.char_ref.weapon_damage() + att.char_ref.damage_bonus(att.ranged)) if is_p else att.damage_bonus
	var bl_dmg := 0
	if is_p and att.char_ref != null:
		bl_dmg = int(att.char_ref.bloodline_combat_mods()["damage"])
	# 属性重做·意志「闪避」：抵消一次命中
	if def_.will_dodge:
		def_.will_dodge = false
		_log("%s 以意志「闪避」化解了这一击。" % def_.name)
		return {"attacker": att, "target": def_, "successes": s, "damage": 0, "hit": false, "crit": false,
			"overflow": 0, "bonus": 0, "target_hp_before": hp_before, "dodged": true}
	var dmg := maxi(1, overflow) + dmg_bonus - def_.armor + bl_dmg
	# 属性重做·暴击：玩家「感知」决定暴击率（5%×感知），暴击伤害 ×2
	var crit := false
	if is_p and att.char_ref != null:
		var cr := att.char_ref.crit_rate()
		if cr > 0 and randf() * 100.0 < float(cr):
			crit = true
			dmg *= 2
	# 属性重做·处变不惊：防守方每回合首次受击减伤「沉着/3」
	var first_reduction := 0
	if def_.is_player and def_.char_ref != null and not first_hit_used.has(def_.uid):
		first_reduction = def_.char_ref.first_hit_reduction()
		if first_reduction > 0:
			first_hit_used[def_.uid] = true
	dmg = maxi(0, dmg - first_reduction)
	if def_.is_player:
		def_.hp -= dmg
		if def_.char_ref != null:
			def_.char_ref.hp = def_.hp
	else:
		def_.hp -= dmg

	var weapon_name := ""
	if is_p:
		weapon_name = "（%s）" % Items.name_of(att.char_ref.weapon)
	_log("%s%s 攻击 %s：骰池 %d，成功 %d，目标防御 %d → 溢出 %d ＋加值 %d − 护甲 %d%s ＝ %d 点伤害。" % [
		att.name, weapon_name, def_.name, int(roll_info["dice"]), s, target_def, overflow, dmg_bonus, def_.armor,
		"　【暴击！】" if crit else "", dmg,
	])
	var hit := dmg > 0
	_check_death(def_)
	return {"attacker": att, "target": def_, "successes": s, "damage": dmg, "hit": hit, "crit": crit,
		"overflow": overflow, "bonus": dmg_bonus, "target_hp_before": hp_before}

func _check_death(u: CombatUnit) -> void:
	if u.hp > 0:
		return
	if u.is_player and u.char_ref != null and u.char_ref.gene_lock_level == 0:
		# 绝境爆种：首开基因锁，回 20% 生命
		u.char_ref.gene_lock_level = 1
		u.char_ref.gene_lock_unlocked = true
		var revive := maxi(1, u.max_hp / 5)
		u.hp = revive
		u.char_ref.hp = revive
		_log("【基因锁 · 一阶】%s 濒死之际，血脉深处的锁轰然碎裂！生命恢复 %d，攻击/防御获得强化！" % [u.name, revive])
		_safe_emit_gene_lock()
		return
	u.hp = 0
	_log("%s 倒下了。" % u.name)
	if u.is_player:
		if u.char_ref != null:
			u.char_ref.hp = 0
		over = true
		victory = false
	else:
		fallen.append(u)
		units.erase(u)
		order.erase(u)
		if turn_index >= order.size():
			turn_index = 0
		_check_victory()

func _check_victory() -> void:
	var enemies_alive := 0
	for u in units:
		if not u.is_player:
			enemies_alive += 1
	if enemies_alive == 0:
		over = true
		victory = true

## 战斗奖励（击杀积分合计）。必须包含已阵亡单位——它们已从 units 移出（见 fallen），
## 否则击杀奖励会少算（这是与"尸体不清理"同源的 bug）。
func reward_points() -> int:
	var total := 0
	for u in units:
		if not u.is_player:
			total += u.reward
	for u in fallen:
		if not u.is_player:
			total += u.reward
	return total

func _log(text: String) -> void:
	logs.append(text)

## autoload 可能不存在（-s 脚本模式），安全发射。
func _safe_emit_gene_lock() -> void:
	var loop := Engine.get_main_loop()
	if loop == null:
		return
	var root: Node = loop.root
	if root == null:
		return
	var eb: Node = root.get_node_or_null("/root/EventBus")
	if eb != null and eb.has_signal("gene_lock_unlocked"):
		eb.emit_signal("gene_lock_unlocked", 1)

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
