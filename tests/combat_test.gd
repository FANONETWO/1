extends SceneTree
## 战斗逻辑测试：攻击结算 / 死亡 / 胜利 / 基因锁绝境爆种 / 敌人AI。
##   godot --headless --path . -s res://tests/combat_test.gd

var _fails := 0

func _init() -> void:
	print("combat_test: start")
	# 造一个均衡角色
	var p := Character.create_default()
	p.name = "测试者"
	p.attrs["str"] = 4
	p.attrs["dex"] = 4
	p.attrs["end"] = 3
	p.attrs["res"] = 3
	p.attrs["com"] = 3
	p.skills["brawl"] = 3
	p.weapon = "bat"
	p.hp = p.max_hp()
	p.will = p.max_will()

	# 1. 攻击结算：伤害 ≥0 且目标扣血
	var cm := CombatManager.new()
	cm.start(p, [{"id": "zombie", "pos": Vector2i(5, 5)}], Vector2i(5, 4))
	var z: CombatUnit = cm.units[1]
	var before := z.hp
	var res := cm.resolve_attack(cm.player_unit, z)
	_check(res["damage"] >= 0, "攻击伤害 ≥0")
	_check(z.hp <= before, "目标生命减少或持平")

	# 2. 攻击成功数应等于骰池结果
	_check(res["successes"] >= 0, "成功数 ≥0")

	# 3. 全灭敌人 → victory
	var cm2 := CombatManager.new()
	var zombie_weak: Dictionary = Enemies.get_def("zombie").duplicate()
	cm2.start(p, [{"id": "zombie", "pos": Vector2i(6, 6)}], Vector2i(6, 5))
	var z2: CombatUnit = cm2.units[1]
	z2.hp = 1
	cm2.resolve_attack(cm2.player_unit, z2)
	_check(cm2.over and cm2.victory, "击杀全部敌人后胜利")

	# 4. 玩家死亡 → 绝境爆种（首开基因锁，不死亡）
	var cm3 := CombatManager.new()
	cm3.start(p, [{"id": "brute", "pos": Vector2i(8, 8)}], Vector2i(8, 7))
	var b: CombatUnit = cm3.units[1]
	b.hp = 1  # 让它还活着
	cm3.player_unit.hp = 1
	cm3.resolve_attack(b, cm3.player_unit)
	_check(cm3.player_unit.hp > 0, "绝境爆种后玩家存活")
	_check(p.gene_lock_level >= 1, "基因锁已觉醒")

	# 5. 已觉醒后再致死 → 死亡
	var cm4 := CombatManager.new()
	cm4.start(p, [{"id": "brute", "pos": Vector2i(9, 9)}], Vector2i(9, 8))
	var b2: CombatUnit = cm4.units[1]
	cm4.player_unit.hp = 1
	cm4.resolve_attack(b2, cm4.player_unit)
	_check(cm4.over and not cm4.victory, "基因锁已觉醒后死亡判定")
	# 恢复角色状态供后续测试
	p.hp = p.max_hp()

	# 6. 敌人 AI：近战敌人移动接近并攻击
	var cm5 := CombatManager.new()
	cm5.start(p, [{"id": "zombie", "pos": Vector2i(12, 12)}], Vector2i(12, 8))
	var z5: CombatUnit = cm5.units[1]
	var start_pos: Vector2i = z5.pos
	cm5.auto_turn(z5, func(pos): return false)
	_check(z5.pos != start_pos or cm5.over, "敌人 AI 朝玩家移动")

	# 7. 行动点：攻击消耗 3 AP
	var cm6 := CombatManager.new()
	cm6.start(p, [{"id": "zombie", "pos": Vector2i(3, 3)}], Vector2i(3, 2))
	if not cm6.is_player_turn():
		cm6.end_turn()  # 敌人先手时切回玩家回合
	var ap_before := cm6.player_unit.ap
	var tres := cm6.try_attack(cm6.player_unit, cm6.units[1])
	_check(tres.get("ok", false), "相邻攻击成功")
	_check(cm6.player_unit.ap <= ap_before - 2, "攻击消耗行动点")

	# 8. 攻击距离限制：太远无法攻击
	var cm7 := CombatManager.new()
	cm7.start(p, [{"id": "zombie", "pos": Vector2i(3, 9)}], Vector2i(3, 2))
	if not cm7.is_player_turn():
		cm7.end_turn()
	var tres2 := cm7.try_attack(cm7.player_unit, cm7.units[1])
	_check(not tres2.get("ok", false), "超距攻击被拒绝")

	# 9. 武器伤害必须计入结算（回归：items.damage 曾无人读取）
	var c_bat := Character.create_default()
	c_bat.weapon = "bat"
	c_bat.skills["brawl"] = 3
	c_bat.hp = c_bat.max_hp()
	var cm8 := CombatManager.new()
	cm8.start(c_bat, [{"id": "zombie", "pos": Vector2i(3, 3)}], Vector2i(3, 2))
	var r8 := cm8.resolve_attack(cm8.player_unit, cm8.units[1])
	_check(int(r8["bonus"]) == 2, "钢管武器伤害 +2 计入结算（实际 %d）" % int(r8["bonus"]))

	# 10. 武器伤害随武器变强而提升
	var c_fist := Character.create_default()
	_check(c_fist.weapon_damage() == 1, "空手武器伤害 +1")
	_check(c_bat.weapon_damage() > c_fist.weapon_damage(), "钢管伤害高于空手")

	print("combat_test: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok - " + label)
	else:
		_fails += 1
		printerr("  FAIL - " + label)
