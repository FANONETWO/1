extends SceneTree
## 属性重做验证：九属性各有一个战斗出口。
##   godot --headless --path . -s res://tests/attr_redesign_test.gd

var _ok := 0
var _fail := 0

func _init() -> void:
	seed(20260101)          # 固定随机序列：采样类断言不再偶发误判
	print("=== attr_redesign_test ===")
	_test_derived()
	_test_damage_scaling()
	_test_combat_effects()
	print("attr_redesign_test: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, label: String) -> void:
	if cond:
		_ok += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _mk(overrides: Dictionary = {}) -> Character:
	var c := Character.create_default()
	var base := {"str": 2, "dex": 2, "end": 2, "int": 2, "per": 2, "res": 2, "pre": 2, "man": 2, "com": 2}
	for k in overrides:
		base[k] = int(overrides[k])
	c.attrs = base
	c.hp = c.max_hp()
	c.will = c.max_will()
	return c

# ——— 1. 派生值公式 ———

func _test_derived() -> void:
	var c := _mk({"end": 4, "res": 3, "per": 5, "dex": 5, "int": 4, "pre": 4, "man": 4, "com": 6})
	_check(c.max_hp() == 8 + 4 * 4, "生命 = 8 + 4×耐力 → %d" % c.max_hp())
	_check(c.max_will() == 2 * 3, "意志 = 2×决心 → %d" % c.max_will())
	_check(c.crit_rate() == 25, "暴击率 = 5×感知 → %d%%" % c.crit_rate())
	_check(c.move_range() == 3 + 2, "移动力 = 3+敏捷/2 → %d" % c.move_range())
	_check(c.tactical_points() == 2, "战术点 = 智力/2 → %d" % c.tactical_points())
	_check(c.aura_range() == 2, "光环半径 = 风度/2 → %d" % c.aura_range())
	_check(c.aura_hit_bonus() == 2, "光环命中加成（风度≥4）→ +%d" % c.aura_hit_bonus())
	_check(c.intimidate_penalty() == 2, "威慑（操控≥4）→ −%d 命中" % c.intimidate_penalty())
	_check(c.first_hit_reduction() == 2, "首击减伤 = 沉着/3 → %d" % c.first_hit_reduction())

	# 低属性时取小值
	var w := _mk({"pre": 2, "man": 2, "com": 2, "per": 1})
	_check(w.aura_hit_bonus() == 1, "光环加成（风度<4）→ +1")
	_check(w.intimidate_penalty() == 1, "威慑（操控<4）→ −1")
	_check(w.first_hit_reduction() == 0, "首击减伤（沉着 2）→ 0")

# ——— 2. 伤害随主属性成长 ———

func _test_damage_scaling() -> void:
	var weak := _mk({"str": 2, "per": 2})
	weak.weapon = "bat"          # 基础伤害 2
	_check(weak.weapon_damage() == 3, "弱小角色近战伤害 = 2+1 → %d" % weak.weapon_damage())

	var strong := _mk({"str": 6, "per": 2})
	strong.weapon = "bat"
	_check(strong.weapon_damage() == 5, "强壮角色近战伤害 = 2+3 → %d" % strong.weapon_damage())

	var gunner := _mk({"str": 2, "per": 6})
	gunner.weapon = "pistol"     # 基础伤害 3，远程吃感知
	_check(gunner.weapon_damage() == 6, "远程伤害吃感知 = 3+3 → %d" % gunner.weapon_damage())

# ——— 3. 战斗内：暴击 / 首击减伤 / 威慑 ———

func _test_combat_effects() -> void:
	# 暴击采样：感知 4 → 20%
	var c := _mk({"str": 3, "dex": 2, "end": 5, "per": 4, "com": 2})
	var cm := CombatManager.new()
	cm.start(c, [{"id": "zombie", "pos": Vector2i.ZERO}], Vector2i.ZERO)
	var crits := 0
	var trials := 300
	for i in trials:
		var foe: CombatUnit = cm.units[1]
		foe.hp = 999
		var r := cm.resolve_attack(cm.player_unit, foe)
		if bool(r.get("crit", false)):
			crits += 1
	var rate := float(crits) / float(trials) * 100.0
	_check(absf(rate - 20.0) < 8.0, "暴击采样 %.0f%%（配置 20%%，%d 次）" % [rate, trials])

	# 首击减伤：同一回合内只生效一次
	var c2 := _mk({"end": 5, "com": 9})      # 减伤 = 3
	_check(c2.first_hit_reduction() == 3, "沉着 9 → 首击减伤 3")
	var cm2 := CombatManager.new()
	cm2.start(c2, [{"id": "zombie", "pos": Vector2i.ZERO}], Vector2i.ZERO)
	var foe2: CombatUnit = cm2.units[1]
	foe2.dp_attack = 99                     # 保证必中
	cm2.player_unit.hp = 999
	cm2.resolve_attack(foe2, cm2.player_unit)
	_check(cm2.first_hit_used.has(cm2.player_unit.uid), "首次受击后「首击减伤」标记已用")
	cm2.resolve_attack(foe2, cm2.player_unit)
	_check(cm2.first_hit_used.has(cm2.player_unit.uid), "第二次受击不再重复减伤（标记保持）")
	cm2._begin_turn(cm2.player_unit)
	_check(not cm2.first_hit_used.has(cm2.player_unit.uid), "新回合恢复首击减伤")

	# 威慑：操控 6 → 敌人骰池 −2。用「有/无威慑」对比，避免单组采样的方差误判。
	var c3 := _mk({"man": 6, "end": 5})
	_check(c3.intimidate_penalty() == 2, "操控 6 → 威慑 −2")
	var avg_no := _avg_enemy_successes(2)
	var avg_yes := _avg_enemy_successes(6)
	_check(avg_yes < avg_no - 0.25,
		"威慑生效：敌人平均成功 %.2f → %.2f（骰池 5→3）" % [avg_no, avg_yes])

## 采样：指定「操控」时，敌人（骰池固定 5）对玩家攻击的平均成功数
func _avg_enemy_successes(man: int, trials: int = 400) -> float:
	var c := _mk({"man": man, "end": 5})
	var cm := CombatManager.new()
	cm.start(c, [{"id": "zombie", "pos": Vector2i.ZERO}], Vector2i.ZERO)
	var foe: CombatUnit = cm.units[1]
	foe.dp_attack = 5
	var total := 0
	for i in trials:
		cm.player_unit.hp = 9999
		cm.first_hit_used.clear()      # 排除首击减伤干扰
		var r := cm.resolve_attack(foe, cm.player_unit)
		total += int(r["successes"])
	return float(total) / float(trials)
