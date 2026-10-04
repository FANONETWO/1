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

# ——— 行动条（CTB 行动值模型）———
const BASE_AV := 1000.0        # 行动值基数：一次行动后 av += BASE_AV / speed
const TACTIC_PUSH := 220.0     # 指挥点「抢手 / 压制」改变的行动值幅度

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

## allies：团队模式的队友角色卡（槽位 p1..p3）。独狼模式传空数组即可。
func start(player: Character, enemy_list: Array[Dictionary], player_pos: Vector2i, allies: Array = []) -> void:
	units.clear()
	order.clear()
	logs.clear()
	over = false
	victory = false
	fallen.clear()
	first_hit_used.clear()
	round = 1
	player_unit = CombatUnit.from_player(player, 0)
	player_unit.pos = player_pos
	units.append(player_unit)
	# 队友：各自一张角色卡，槽位 p1..p3（联机时这些槽位换成真人输入，见命令层）
	var slot := 1
	for a in allies:
		if a is Character:
			var au := CombatUnit.from_player(a, slot)
			au.pos = player_pos
			units.append(au)
			slot += 1
	for e in enemy_list:
		units.append(CombatUnit.from_enemy(String(e["id"]), e["pos"], String(e.get("uid", ""))))
	order = units.duplicate()
	order.sort_custom(func(a, b): return a.init > b.init)
	turn_index = 0
	_init_timeline()
	# 指挥点汇总为全队共享池（团队模式才有协作加成；独狼 = 自己的智力/2）
	player_unit.tactical = command_points_total()
	_begin_turn(order[0])
	_log("战斗开始。先攻：%s" % _order_names())

func _order_names() -> String:
	var names: Array[String] = []
	for u in order:
		names.append(u.name)
	return "、".join(names)

# ——— 行动条（CTB：行动值越小越先动）———
# 规则：每个单位有一个行动值 av；每次行动后 av += BASE_AV / speed。
# 于是速度高的人「加得少 → 轮得快」，出手更频繁；先攻只影响起手位置。
# 「第几回合」= 所有存活单位里最慢的那个的行动次数 + 1 —— 快的人会在同一回合里多动一次。
# 这套模型对**任意数量**的玩家单位都成立，因此团队模式（4 人）天然可用。

## 初始行动值：速度决定基础间隔，先攻做微调（先攻高者起手更靠前）
func initial_av(u: CombatUnit) -> float:
	return BASE_AV / maxf(1.0, float(u.speed)) - float(u.init)

func _init_timeline() -> void:
	for u in units:
		u.av = initial_av(u)
		u.rounds_taken = 0

## 玩家方存活单位（团队模式会有多个；p0 永远是玩家本人）
func player_units() -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for u in units:
		if u.is_player and u.hp > 0:
			out.append(u)
	return out

func alive_units() -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for u in units:
		if u.hp > 0:
			out.append(u)
	return out

## 时间轴上「下一个出手的人」：行动值最小者；同值时先攻高者优先
func next_in_timeline() -> CombatUnit:
	var best: CombatUnit = null
	var best_av := INF
	for u in alive_units():
		if u.av < best_av - 0.001:
			best_av = u.av
			best = u
		elif absf(u.av - best_av) <= 0.001 and best != null and u.init > best.init:
			best = u
	return best

## 推进时间轴：取下一个出手者，并把它推到下一次出手的位置（null = 无人可动）
func advance_timeline() -> CombatUnit:
	var u := next_in_timeline()
	if u == null:
		return null
	u.rounds_taken += 1
	u.av += BASE_AV / maxf(1.0, float(u.speed))
	return u

## 预测未来 count 次出手顺序（**纯读**，绝不改状态）—— UI 的行动条就画它，
## 而且必须与 advance_timeline() 的实际顺序一致，否则就是在骗玩家。
func timeline(count: int) -> Array[CombatUnit]:
	var alive := alive_units()
	var out: Array[CombatUnit] = []
	if alive.is_empty():
		return out
	var sim := {}
	for u in alive:
		sim[u.uid] = u.av
	for i in count:
		var best: CombatUnit = null
		var best_av := INF
		for u in alive:
			var v: float = sim[u.uid]
			if v < best_av - 0.001:
				best_av = v
				best = u
			elif absf(v - best_av) <= 0.001 and best != null and u.init > best.init:
				best = u
		if best == null:
			break
		out.append(best)
		sim[best.uid] = best_av + BASE_AV / maxf(1.0, float(best.speed))
	return out

## 当前回合数：最慢的存活单位的行动次数 + 1
func round_now() -> int:
	var alive := alive_units()
	if alive.is_empty():
		return round
	var slowest := 999999
	for u in alive:
		slowest = mini(slowest, u.rounds_taken)
	return slowest + 1

# ——— 指挥点（团队共享池 · 智力/2 的战棋出口）———

## 全队共享的指挥点总量：取队内最高智力/2（独狼 = 自己的智力/2，与旧设定一致），
## 团队模式下每人再给 1 点协作加成 —— 人多能打的战术牌更多。
func command_points_total() -> int:
	var best := 0
	var n := 0
	for u in units:
		if not u.is_player:
			continue
		n += 1
		best = maxi(best, u.tactical)
	if n <= 1:
		return best
	return best + n - 1

## 当前剩余指挥点（全队共用，记在 p0 身上）
func command_points() -> int:
	return player_unit.tactical if player_unit != null else 0

## 「抢手」：让某个玩家单位提前出手（消耗 1 指挥点）
func tactic_rush(u: CombatUnit) -> bool:
	if player_unit == null or player_unit.tactical <= 0 or u == null:
		return false
	player_unit.tactical -= 1
	u.av = maxf(0.0, u.av - TACTIC_PUSH)
	_log("【战术·抢手】%s 抢占先机。" % u.name)
	return true

## 「压制」：把目标推后（消耗 1 指挥点）
func tactic_suppress(target: CombatUnit) -> bool:
	if player_unit == null or player_unit.tactical <= 0 or target == null:
		return false
	player_unit.tactical -= 1
	target.av += TACTIC_PUSH
	_log("【战术·压制】%s 被打乱节奏，行动延后。" % target.name)
	return true

# ——— 回合控制 ———

func current() -> CombatUnit:
	return order[turn_index]

func is_player_turn() -> bool:
	return not over and current().is_player

## BattleScene 自管行动队列（不走 end_turn），必须显式告诉 CM「现在轮到谁」。
## 否则 turn_index 永远停在 start() 的初值上，current() / is_player_turn() 会一直是错的
## —— pace_test 曾因此判定「玩家出手 0 次」，UI 侧任何依赖它的判断也都会错。
func set_current(u: CombatUnit) -> void:
	var idx := order.find(u)
	if idx >= 0:
		turn_index = idx

## 单位回合开始（重置 AP 与防御姿态）。BattleScene 每轮到一个人就调一次。
## ⚠️ 此前 BattleScene 从不调用它 → 玩家一回合把 6 点 AP 用完后**再也不恢复**，
## 战斗就变成「站着挨打、怎么也打不动」，这也是试玩报告里「打不过大堂」的真凶之一。
func begin_unit_turn(u: CombatUnit) -> void:
	_begin_turn(u)

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

## 新回合开始：重置「每回合一次」的资源。
## BattleScene 自管回合队列、不走 end_turn/_begin_turn，需在 _start_round 显式调用：
## 处变不惊首击减伤重新可用，各单位的防御姿态过期（+2 由 resolve_attack 按标记计算，
## 不再允许把防御值永久烘进面板）。
func begin_round() -> void:
	first_hit_used.clear()
	for u in units:
		u.defending = false

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
		_ev("item", "用药被拒", {"item": item_id, "reason": "行动点不足", "ap": u.ap})
		return {"ok": false, "reason": "行动点不足"}
	var d: Dictionary = Items.get_def(item_id)
	if d.get("kind", "") != "consumable":
		_ev("item", "用药被拒", {"item": item_id, "reason": "非消耗品"})
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
	_ev("item", "用药", {
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

## 结构化日志：autoload 可能不存在（`-s` 脚本模式）。
## ⚠️ 直接写 `DebugLog.ev(...)` 会让整个脚本**编译失败**（Identifier not found），
## 而 -s 单测的 quit() 在编译失败后永远不会执行 → 进程挂死。
## 这就是 combat_test 曾经「跑不通」的根因，所以这里统一走安全访问。
func _ev(cat: String, msg: String, data: Dictionary = {}) -> void:
	var loop := Engine.get_main_loop()
	if loop == null:
		return
	var root: Node = loop.root
	if root == null:
		return
	var dbg: Node = root.get_node_or_null("/root/DebugLog")
	if dbg != null and dbg.has_method("ev"):
		dbg.ev(cat, msg, data)

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
