class_name DicePool
extends RefCounted
## D10 骰池检定（基于 RE25 核心规则）：
## 1) DP = 属性 + 技能 + 调整值
## 2) 掷 DP 枚 D10，骰面 ≥8 计 1 个成功（8/9/10 成功）
## 3) 10 加骰：掷出 10 得 1 成功并再掷一枚（递归），加骰结果仍按 ≥8 计、10 继续加骰
## 4) 附加成功：属性 ≥6 每 +5 加 1；技能 5/7/9/... 各 +1；天赋等来源
## 5) 技能 0 级惩罚：生理 -1 成功，心智自动失败，互动 -2 成功
## 6) 与 DC 比较：总成功数 ≥ DC 即通过

## rng：留出的**权威随机源**接口。
## 单机与测试传 null（走全局随机）；联机时由主机传入同一个 RandomNumberGenerator，
## 或干脆由主机掷骰后广播结果 —— 否则两端骰面不一致，判定会当场打架。
static func roll(attr_value: int, skill_value: int, extra_dice: int = 0, extra_success: int = 0, skill_id: String = "", rng: RandomNumberGenerator = null) -> Dictionary:
	# 心智系技能 0 级：无法判定，自动失败
	if skill_id != "" and skill_value <= 0 and Skills.CATEGORY.get(skill_id, "") == "心智":
		return {"total": 0, "dice": 0, "rolls": [], "successes": 0, "bonus": 0, "bonus_void": false, "failed_zero": true}

	var dp := maxi(1, attr_value + skill_value + extra_dice)
	var successes := 0
	var rolls: Array[int] = []
	for i in dp:
		successes += _roll_stream(rolls, rng)

	var bonus := 0
	# 技能 0 级惩罚
	if skill_id != "" and skill_value <= 0:
		bonus += Skills.zero_penalty(skill_id)
	# 附加成功
	bonus += Attrs.bonus_success(attr_value)
	bonus += Skills.bonus_success(skill_value)
	bonus += extra_success

	# 附加成功只能锦上添花：掷骰成功数为 0 时，再多附加成功也无法让行动成功。
	# 依据 re25《核心规则》「附加成功的使用」。
	var gated := successes <= 0
	var total := 0 if gated else maxi(0, successes + bonus)
	return {
		"total": total, "dice": dp, "rolls": rolls,
		"successes": successes, "bonus": bonus,
		"bonus_void": gated and bonus > 0,
		"failed_zero": false,
	}

## 掷一个骰流：≥8 成功；10 则递归加骰。
static func _roll_stream(rolls: Array, rng: RandomNumberGenerator = null) -> int:
	var v := _d10(rng)
	rolls.append(v)
	var s := 1 if v >= 8 else 0
	if v == 10:
		s += _roll_stream(rolls, rng)
	return s

## 单骰 D10：有权威随机源就用它，否则走全局随机
static func _d10(rng: RandomNumberGenerator = null) -> int:
	if rng != null:
		return rng.randi_range(1, 10)
	return randi_range(1, 10)

## 先攻判定：d10 + 敏捷 + 沉着 + 额外加值（规则书先攻由骰池决定，切片简化单骰）。
static func roll_initiative(dex_value: int, com_value: int, flat_bonus: int = 0, rng: RandomNumberGenerator = null) -> int:
	return _d10(rng) + dex_value + com_value + flat_bonus
