extends SceneTree
## P3 缓解手段 + P4 融合技/基因崩溃 专项测试：
##   godot --headless --path . -s res://tests/bloodline_mitigation_test.gd

var _pass := 0
var _fail := 0

func _init() -> void:
	print("=== bloodline_mitigation_test ===")
	_test_suppress()
	_test_stabilizer()
	_test_tolerance()
	_test_fusion()
	_test_collapse()
	print("bloodline_mitigation_test: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _eq(got: Variant, want: Variant, label: String) -> void:
	_check(got == want, "%s（期望 %s，实际 %s）" % [label, str(want), str(got)])

## 天使 + 恶魔：D 级 = 65%，S 级 = 100%
func _angel_demon(rank: String) -> Character:
	var c := Character.create_default()
	c.bloodlines = [
		{"id": "angel", "rank": rank, "picked": []},
		{"id": "demon", "rank": rank, "picked": []},
	]
	c.will = 4
	c.hp = 20
	return c

# ——— P3.1 意志力压制 ———

func _test_suppress() -> void:
	var c := _angel_demon("D")
	_eq(c.bloodline_rejection(), 65, "基线排斥 65%")
	_check(c.can_suppress_bloodline(), "满足压制条件（排斥 ≥10 且意志 ≥2）")
	_check(c.suppress_bloodline(), "发动意志压制成功")
	_eq(c.bloodline_rejection(), 55, "压制后排斥 55%（−10）")
	_eq(c.will, 2, "消耗 2 点意志力")
	_check(not c.can_suppress_bloodline(), "每场只能压制一次")

	# 排斥不足 10% 时不可压制
	var clean := Character.create_default()
	clean.bloodlines = [{"id": "angel", "rank": "D", "picked": []}, {"id": "immortal", "rank": "D", "picked": []}]
	_eq(clean.bloodline_rejection(), 0, "相容搭配排斥 0")
	_check(not clean.can_suppress_bloodline(), "排斥 0 时无需压制")

# ——— P3.2 血脉稳定剂 ———

func _test_stabilizer() -> void:
	var c := _angel_demon("D")
	c.suppress_bloodline()
	_eq(c.bloodline_rejection(), 55, "仅压制时 55%")
	c.use_stabilizer(3)
	_eq(c.bloodline_rejection(), 40, "压制 + 稳定剂 = 40%（额外 −15）")
	c.tick_bloodline()
	c.tick_bloodline()
	_eq(c.bloodline_stabilizer, 1, "稳定剂计时 3 → 1")
	_eq(c.bloodline_rejection(), 40, "计时中排斥保持 40%")
	c.tick_bloodline()
	_eq(c.bloodline_stabilizer, 0, "稳定剂到期")
	_eq(c.bloodline_rejection(), 55, "到期后回到 55%（压制仍在）")

# ——— P3.3 调和手术（永久） ———

func _test_tolerance() -> void:
	var c := _angel_demon("S")
	_eq(c.bloodline_rejection(), 100, "S 级双血统排斥 100%")
	var cost := c.tolerance_repair_cost()
	_check(cost > 0, "调和手术成本 > 0（%d 点）" % cost)
	c.apply_tolerance_repair()
	_eq(c.bloodline_tolerance, 20, "永久减免 +20")
	_eq(c.bloodline_rejection(), 80, "排斥 100 → 80%")
	_check(not c.is_gene_collapsed(), "调和后脱离基因崩溃")
	c.apply_tolerance_repair()
	_eq(c.bloodline_rejection(), 60, "第二次调和 → 60%")

# ——— P4.1 融合技 ———

func _test_fusion() -> void:
	var s := _angel_demon("S")
	_eq(s.bloodline_rejection(), 100, "S 级排斥 100%（≥80 门槛）")
	var f := s.fusion_skill()
	_check(not f.is_empty(), "解锁融合技")
	_eq(String(f.get("name", "")), "堕天裁决", "天使+恶魔 的融合技")

	var d := _angel_demon("D")
	_eq(d.bloodline_rejection(), 65, "D 级排斥 65%（<80）")
	_check(d.fusion_skill().is_empty(), "排斥 65% 时未解锁融合技")

	var ai := Character.create_default()
	ai.bloodlines = [
		{"id": "angel", "rank": "S", "picked": []},
		{"id": "immortal", "rank": "S", "picked": []},
	]
	_eq(ai.bloodline_rejection(), 0, "天使+仙体排斥 0")
	_check(ai.fusion_skill().is_empty(), "无对应组合时不给融合技")

# ——— P4.2 基因崩溃 ———

func _test_collapse() -> void:
	var clean := Character.create_default()
	_check(not clean.is_gene_collapsed(), "纯人类不会基因崩溃")

	var d := _angel_demon("D")
	_check(not d.is_gene_collapsed(), "排斥 65% 不崩溃")

	var s := _angel_demon("S")
	_check(s.is_gene_collapsed(), "排斥 100% → 基因崩溃")

	# 永久减免入档、临时减免不入档
	s.apply_tolerance_repair()
	s.suppress_bloodline()
	var dict := s.to_dict()
	var s2 := Character.create_default()
	_check(s2.from_dict(dict), "读档成功")
	_eq(s2.bloodline_tolerance, 20, "永久调和减免已入档")
	_eq(s2.bloodline_suppress, 0, "本场压制不入档（读档重置）")
	_eq(s2.bloodline_rejection(), 80, "读档后排斥 80%（含永久减免）")

	# 战斗结束清空临时减免
	s2.suppress_bloodline()
	_eq(s2.bloodline_rejection(), 70, "压制后 70%")
	s2.clear_battle_bloodline_buffs()
	_eq(s2.bloodline_suppress, 0, "战斗结束清空压制")
	_eq(s2.bloodline_rejection(), 80, "清空后回到 80%")
