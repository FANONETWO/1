extends SceneTree
## 血统模块单元测试：
##   godot --headless --path . -s res://tests/bloodline_test.gd
##
## 覆盖：数据自检、对立/互补对称性、排斥度、协同度、档位映射、效果表。

var _pass := 0
var _fail := 0

func _init() -> void:
	print("=== bloodline_test ===")
	_test_data()
	_test_relations()
	_test_rejection()
	_test_synergy()
	_test_tiers()
	_test_character_integration()
	print("bloodline_test: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
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

# ——— 1. 数据自检 ———

func _test_data() -> void:
	var problems := Bloodlines.validate()
	_check(problems.is_empty(), "八系血统数据自检通过（%d 个问题）" % problems.size())
	for p in problems:
		print("    ! ", p)

	_eq(Bloodlines.all_ids().size(), 8, "共 8 系血统")
	_eq(Bloodlines.tags_of("vampire"), ["undeath", "chaos", "matter"], "血族谱系标签")
	_eq(Bloodlines.tags_of("angel"), ["holy", "order", "spirit"], "天使谱系标签")
	_eq(Bloodlines.tags_of("demon"), ["evil", "chaos", "spirit"], "恶魔谱系标签")

	# 每级候选数与可选数
	for r in Bloodlines.RANKS:
		var want := int(Bloodlines.RANK_CANDIDATES[r])
		_eq(Bloodlines.candidates("vampire", r).size(), want, "血族 %s 级候选数" % r)
	_eq(Bloodlines.pick_count("D"), 2, "D 级可选 2 个")
	_eq(Bloodlines.pick_count("S"), 1, "S 级可选 1 个")

	# 技能树全貌：16 个候选、9 个可选
	var total_cand := 0
	var total_pick := 0
	for r in Bloodlines.RANKS:
		total_cand += Bloodlines.candidates("vampire", r).size()
		total_pick += Bloodlines.pick_count(r)
	_eq(total_cand, 16, "血族五级共 16 个候选技能")
	_eq(total_pick, 9, "血族满级共 9 个技能位")

	# 升级成本递增
	_check(Bloodlines.upgrade_cost("C") < Bloodlines.upgrade_cost("B"), "升级成本递增（C < B）")
	_check(Bloodlines.upgrade_cost("B") < Bloodlines.upgrade_cost("A"), "升级成本递增（B < A）")

# ——— 2. 对立 / 互补关系 ———

func _test_relations() -> void:
	_eq(Bloodlines.opposed_strength(["holy"], ["evil"]), 30, "神圣 ↔ 邪恶 对立强度 30")
	_eq(Bloodlines.opposed_strength(["life"], ["undeath"]), 25, "生命 ↔ 不死 对立强度 25")
	_eq(Bloodlines.opposed_strength(["order"], ["chaos"]), 20, "秩序 ↔ 混沌 对立强度 20")
	_eq(Bloodlines.opposed_strength(["holy"], ["life"]), 0, "神圣与生命不对立")
	_eq(Bloodlines.opposed_strength([], []), 0, "空标签无对立")

	_eq(Bloodlines.synergy_pairs(["holy"], ["life"]), 1, "神圣与生命互补")
	_eq(Bloodlines.synergy_pairs(["holy"], ["spirit"]), 1, "神圣与精神互补")
	_eq(Bloodlines.synergy_pairs(["holy"], ["evil"]), 0, "神圣与邪恶不互补")
	_eq(Bloodlines.shared_tags(["holy", "order"], ["holy", "life"]), 1, "同源标签计数")

	# 对称性（显式再测一遍，validate 已覆盖）
	var sym_ok := true
	for t in Bloodlines.TAGS:
		for p in Bloodlines.SYNERGY[t]:
			if not Bloodlines.SYNERGY[p].has(t):
				sym_ok = false
	_check(sym_ok, "互补关系完全对称")

# ——— 3. 排斥度 ———

func _test_rejection() -> void:
	_eq(Bloodlines.rejection([]), 0, "无血统 → 排斥 0")
	_eq(Bloodlines.rejection([{"id": "vampire", "rank": "D"}]), 0, "单血统 → 排斥 0")

	# 天使 + 恶魔：神圣↔邪恶 30 + 秩序↔混沌 20 = 50；×1.3 = 65
	var td := [{"id": "angel", "rank": "D"}, {"id": "demon", "rank": "D"}]
	_eq(Bloodlines.rejection(td), 65, "天使+恶魔（双双 D）排斥 65%")

	# 升到 C：50 × (1 + 0.15×4) = 80
	var tc := [{"id": "angel", "rank": "C"}, {"id": "demon", "rank": "C"}]
	_eq(Bloodlines.rejection(tc), 80, "天使+恶魔（双双 C）排斥 80%（升级推高）")

	# 升到 S：50 × (1 + 0.15×10) = 125 → 封顶 100
	var ts := [{"id": "angel", "rank": "S"}, {"id": "demon", "rank": "S"}]
	_eq(Bloodlines.rejection(ts), 100, "天使+恶魔（双双 S）排斥封顶 100%（基因崩溃）")

	# 天堂组合：零排斥
	_eq(Bloodlines.rejection([{"id": "angel", "rank": "D"}, {"id": "immortal", "rank": "D"}]), 0, "天使+仙体 → 排斥 0")

	# 矛盾血脉：血族 + 狼人，25 × 1.3 = 32.5 → 33
	_eq(Bloodlines.rejection([{"id": "vampire", "rank": "D"}, {"id": "werewolf", "rank": "D"}]), 33, "血族+狼人 排斥 33%")

	# 三血统累加（天使 + 恶魔 + 血族）
	var three := [
		{"id": "angel", "rank": "D"},
		{"id": "demon", "rank": "D"},
		{"id": "vampire", "rank": "D"},
	]
	_check(Bloodlines.rejection(three) > 65, "三血统排斥高于两血统（%d）" % Bloodlines.rejection(three))

# ——— 4. 协同度 ———

func _test_synergy() -> void:
	_eq(Bloodlines.synergy([]), 0, "无血统 → 协同 0")
	_eq(Bloodlines.synergy([{"id": "vampire", "rank": "D"}]), 0, "单血统 → 协同 0")

	# 天堂组合：3 对互补 × 15 × 1.2 + 2 同源 × 5 = 64 → 封顶 60
	var heaven := [{"id": "angel", "rank": "D"}, {"id": "immortal", "rank": "D"}]
	_eq(Bloodlines.synergy(heaven), 60, "天使+仙体 协同 60%（封顶）")

	# 天使 + 恶魔：1 对互补 × 15 × 1.2 + 1 同源 × 5 = 23
	var evil := [{"id": "angel", "rank": "D"}, {"id": "demon", "rank": "D"}]
	_eq(Bloodlines.synergy(evil), 23, "天使+恶魔 协同 23%（同为精神系，有一点共鸣）")

	# 矛盾血脉：血族 + 狼人 = 2 对互补 × 15 × 1.2 + 1 同源 × 5 = 41
	var contra := [{"id": "vampire", "rank": "D"}, {"id": "werewolf", "rank": "D"}]
	_eq(Bloodlines.synergy(contra), 41, "血族+狼人 协同 41%（矛盾血脉：既排斥又协同）")

	# 兼容搭配（义体 + 仙体）：理性↔精神 1 对，无同源
	var mixed := [{"id": "cyber", "rank": "D"}, {"id": "immortal", "rank": "D"}]
	_eq(Bloodlines.synergy(mixed), 18, "义体+仙体 协同 18%")

# ——— 5. 档位与效果 ———

func _test_tiers() -> void:
	_eq(Bloodlines.rejection_tier(0), "none", "排斥 0 → 相容")
	_eq(Bloodlines.rejection_tier(10), "interference", "排斥 10 → 血脉干扰")
	_eq(Bloodlines.rejection_tier(49), "interference", "排斥 49 → 仍是干扰")
	_eq(Bloodlines.rejection_tier(50), "unstable", "排斥 50 → 失控风险")
	_eq(Bloodlines.rejection_tier(100), "collapse", "排斥 100 → 基因崩溃")

	_eq(Bloodlines.synergy_tier(0), "none", "协同 0 → 无")
	_eq(Bloodlines.synergy_tier(10), "minor", "协同 10 → 微弱共鸣")
	_eq(Bloodlines.synergy_tier(30), "major", "协同 30 → 强力共鸣")
	_eq(Bloodlines.synergy_tier(50), "synergy", "协同 50 → 解锁协同技")

	var r10 := Bloodlines.rejection_effects(10)
	_eq(r10["hit"], -10, "干扰档：命中 −10")
	_eq(r10["damage"], -1, "干扰档：伤害 −1（骰池系统标定）")
	_eq(r10["defense"], -1, "干扰档：防御 −1")
	_eq(r10["unstable_chance"], 0.0, "干扰档：无失控")

	var r50 := Bloodlines.rejection_effects(50)
	_eq(r50["unstable_chance"], 0.5, "失控档：50% 失控概率")
	_eq(r50["node_bonus"], 1.2, "失控档：血脉沸腾 +20%")

	var r80 := Bloodlines.rejection_effects(80)
	_eq(r80["node_bonus"], 1.35, "80% 档：血脉沸腾 +35%")

	var s30 := Bloodlines.synergy_effects(30)
	_eq(s30["share_skills"], true, "协同 ≥30：主动技能共享次数")
	_eq(s30["combo_unlocked"], false, "协同 30：尚未解锁协同技")

	var s50 := Bloodlines.synergy_effects(50)
	_eq(s50["combo_unlocked"], true, "协同 ≥50：解锁协同技")
	_eq(s50["node_bonus"], 1.35, "协同 ≥50：节点效果 +35%")

	# 实际搭配的端到端读数
	var pair := [{"id": "vampire", "rank": "B"}, {"id": "werewolf", "rank": "B"}]
	var rj := Bloodlines.rejection(pair)
	var sy := Bloodlines.synergy(pair)
	print("  info - 血族 B + 狼人 B：排斥 %d%%（%s），协同 %d%%（%s）" % [
		rj, Bloodlines.rejection_tier(rj), sy, Bloodlines.synergy_tier(sy),
	])
	_check(rj > 33 and sy > 41, "评级提升会同时放大排斥与协同")

# ——— 6. 角色集成 ———

func _test_character_integration() -> void:
	var c := Character.create_default()
	var base_end := c.attr("end")

	# 纯人类：一切为零，行为与旧版本完全一致
	_eq(c.bloodline_attr_bonus("end"), 0, "纯人类无血统属性加成")
	_eq(c.bloodline_combat_mods()["rejection"], 0, "纯人类排斥 0")
	_eq(c.bloodline_combat_mods()["node_bonus"], 1.0, "纯人类无节点加成")

	# 血族 D 级，选了「血色体质」（耐力 +1）+「鲜血感知」
	c.bloodlines = [{"id": "vampire", "rank": "D", "picked": ["bloody_body", "blood_sense"]}]
	_eq(c.bloodline_attr_bonus("end"), 1, "血色体质提供耐力 +1")
	_eq(c.attr("end"), base_end + 1, "attr() 已计入血统加成")
	_check(c.has_bloodline_node("blood_sense"), "拥有「鲜血感知」")
	_check(not c.has_bloodline_node("blood_drain"), "未选中的技能不算拥有")
	_eq(c.bloodline_rank("vampire"), "D", "血统评级读取正确")

	# 前置校验：D 级不能选 C 级技能
	c.bloodlines = [{"id": "vampire", "rank": "D", "picked": ["blood_drain"]}]
	_eq(c.bloodline_attr_bonus("end"), 0, "D 级选 C 级技能无效（越级保护）")

	# 天使 + 恶魔双双 S：排斥 100%，惩罚真实进入战斗修正
	c.bloodlines = [
		{"id": "angel", "rank": "S", "picked": []},
		{"id": "demon", "rank": "S", "picked": []},
	]
	var mods := c.bloodline_combat_mods()
	_eq(mods["rejection"], 100, "天使+恶魔双双 S → 排斥 100%")
	_eq(mods["hit"], -10, "排斥惩罚进入战斗修正（命中 −10）")
	_eq(mods["damage"], -1, "排斥惩罚进入战斗修正（伤害 −1）")
	_check(float(mods["unstable_chance"]) >= 0.9, "失控概率 ≥90%")
	_eq(Bloodlines.rejection_tier(int(mods["rejection"])), "collapse", "已达基因崩溃档")

	# 存档往返（含 v2 旧档缺字段的兼容）
	var d := c.to_dict()
	var c2 := Character.create_default()
	_check(c2.from_dict(d), "存档读取成功")
	_eq(c2.bloodlines.size(), 2, "血统在存档中往返保留")
	_eq(c2.bloodline_rejection(), 100, "读档后排斥度一致")

	var legacy := d.duplicate()
	legacy.erase("bloodlines")
	var c3 := Character.create_default()
	_check(c3.from_dict(legacy), "旧存档（无 bloodlines 字段）可读取")
	_eq(c3.bloodlines.size(), 0, "旧存档默认纯人类")
	_eq(c3.bloodline_rejection(), 0, "旧存档排斥 0（向后兼容）")

