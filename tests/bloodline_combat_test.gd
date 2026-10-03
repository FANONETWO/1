extends SceneTree
## 血统排斥的战斗效果验证（P2 验收）：
##   godot --headless --path . -s res://tests/bloodline_combat_test.gd
##
## 通过大量采样比较「纯人类」与「高排斥角色」的实际战斗数值：
##   · 高排斥角色的输出更低（命中 −10 → −2 成功、伤害 −2）
##   · 高排斥角色挨打更疼（防御 −1）
##   · 排斥度 100% 时失控概率 ≥90%

var _pass := 0
var _fail := 0

func _init() -> void:
	print("=== bloodline_combat_test ===")
	_test_combat_penalty()
	_test_no_bloodline_neutral()
	print("bloodline_combat_test: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _make(clean: bool) -> Character:
	var c := Character.create_default()
	c.attrs["str"] = 4
	c.skills["brawl"] = 3
	c.hp = 999
	if not clean:
		c.bloodlines = [
			{"id": "angel", "rank": "S", "picked": []},
			{"id": "demon", "rank": "S", "picked": []},
		]
	return c

## 玩家攻击敌人：累计伤害
func _dealt(ch: Character, rounds: int) -> int:
	var total := 0
	for i in rounds:
		var cm := CombatManager.new()
		cm.start(ch, [{"id": "zombie", "pos": Vector2i(1, 1)}], Vector2i(0, 1))
		var p: CombatUnit = cm.units[0]
		var e: CombatUnit = cm.units[1]
		e.hp = 9999
		var r := cm.resolve_attack(p, e)
		total += int(r["damage"])
	return total

## 敌人攻击玩家：累计受到的伤害
func _taken(ch: Character, rounds: int) -> int:
	var total := 0
	for i in rounds:
		var cm := CombatManager.new()
		cm.start(ch, [{"id": "zombie", "pos": Vector2i(1, 1)}], Vector2i(0, 1))
		var p: CombatUnit = cm.units[0]
		var e: CombatUnit = cm.units[1]
		p.hp = 9999
		var r := cm.resolve_attack(e, p)
		total += int(r["damage"])
	return total

func _test_no_bloodline_neutral() -> void:
	var c := _make(true)
	var mods := c.bloodline_combat_mods()
	_check(int(mods["hit"]) == 0 and int(mods["damage"]) == 0 and int(mods["defense"]) == 0,
		"纯人类：战斗修正全为 0（不影响既有数值）")
	_check(float(mods["unstable_chance"]) == 0.0, "纯人类：无失控风险")

func _test_combat_penalty() -> void:
	const ROUNDS := 300
	var clean := _make(true)
	var tainted := _make(false)

	var mods := tainted.bloodline_combat_mods()
	_check(int(mods["rejection"]) == 100, "高排斥角色排斥度 = 100%")
	_check(float(mods["unstable_chance"]) >= 0.9, "失控概率 ≥90%")
	_check(int(mods["node_bonus"] * 100.0) == 135, "血脉沸腾：血统技能 +35%")

	var dmg_clean := _dealt(clean, ROUNDS)
	var dmg_tainted := _dealt(tainted, ROUNDS)
	print("  info - %d 回合总输出：纯人类 %d ｜ 高排斥 %d" % [ROUNDS, dmg_clean, dmg_tainted])
	_check(dmg_tainted < dmg_clean, "高排斥角色输出更低（命中与伤害双惩罚）")
	# 理论比值：高排斥 = (1 + 力量/2 + 武器 − 1) / (1 + 力量/2 + 武器) ≈ 0.8，
	# 叠加暴击方差后取 0.88 作阈值，避免单局运气造成假失败。
	_check(float(dmg_tainted) < float(dmg_clean) * 0.88, "输出降幅明显（低于纯人类的 88%）")

	var take_clean := _taken(clean, ROUNDS)
	var take_tainted := _taken(tainted, ROUNDS)
	print("  info - %d 回合总承伤：纯人类 %d ｜ 高排斥 %d" % [ROUNDS, take_clean, take_tainted])
	_check(take_tainted > take_clean, "高排斥角色挨打更疼（防御 −1）")
