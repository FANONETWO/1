extends Control
## 战斗规则回归（对应 2026-10-03 审查发现的静默 bug）：
##   1) 防御/固守不得把 +2 永久烘进防御值（改为姿态标记，begin_round 还原）
##   2) 处变不惊首击减伤每回合重置（begin_round 清 first_hit_used）
##   3) 意志力每回合限用一次（菜单文案早已如此声明）
##   4) 远程武器消耗弹药；空弹匣不能攻击
##   5) 逃跑检定技能 id 必须真实存在（hide），且按 total 判定
##
##   godot --path . res://tests/battle_rules_test.tscn --quit-after 3600

func _ready() -> void:
	var c := Character.create_default()
	c.name = "战斗规则测试"
	c.talent_id = "fighter"
	c.attrs = {"str": 3, "dex": 3, "end": 3, "int": 1, "per": 1, "res": 2, "pre": 1, "man": 1, "com": 2}
	c.skills = {"brawl": 2, "gun": 2, "hide": 1}
	c.weapon = "pistol"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.5).timeout
		var sc := get_tree().current_scene
		if sc == null:
			print("battle_rules_test: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var ok := true

		# ——— 5a) 技能 id 口径（静态，先于战斗）———
		if not Skills.ALL.has("hide"):
			print("[rules] FAIL Skills.ALL 缺少 hide（逃跑检定用）")
			ok = false
		if Skills.ALL.has("subterfuge"):
			print("[rules] FAIL Skills.ALL 不应含 subterfuge（历史误用 id）")
			ok = false

		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.35).timeout
		sc._start_combat_with("walker")
		await get_tree().create_timer(1.5).timeout
		var bt = sc.get("_battle")
		if bt == null:
			print("battle_rules_test: FAIL（战斗未创建）")
			get_tree().quit(1)
			return
		var cm = bt.get("_cm")
		var pu = cm.player_unit
		var pl = sc.get("_player")

		# ——— 1) 防御不得污染防御值 ———
		var base_def: int = pu.defense
		bt._on_cmd_defend()
		if pu.defense != base_def:
			print("[rules] FAIL 防御指令改了 defense 数值（%d → %d）—— 永久叠防回归" % [base_def, pu.defense])
			ok = false
		else:
			print("[rules] OK  防御指令不改变 defense 数值（%d）" % base_def)
		if not bool(pu.defending):
			print("[rules] FAIL 防御指令未置位姿态标记")
			ok = false
		else:
			print("[rules] OK  防御指令置位姿态标记")

		# ——— 2) begin_round：姿态过期 + 首击减伤重置 ———
		cm.first_hit_used[pu.uid] = true
		cm.begin_round()
		var restored: bool = not bool(pu.defending) and not cm.first_hit_used.has(pu.uid)
		if restored:
			print("[rules] OK  begin_round 还原姿态并重置首击减伤")
		else:
			print("[rules] FAIL begin_round 未还原（defending=%s first_hit=%s）" % [str(pu.defending), str(cm.first_hit_used)])
			ok = false

		# ——— 3) 意志每回合限一次 ———
		var will0: int = pl.will
		bt._on_cmd_will()
		bt._apply_will("guard")
		if pl.will != will0 - 1:
			print("[rules] FAIL 第一次意志未正确消耗（%d → %d）" % [will0, pl.will])
			ok = false
		bt._on_cmd_will()
		if pl.will != will0 - 1:
			print("[rules] FAIL 同回合第二次意志未被拒绝（%d → %d）" % [will0 - 1, pl.will])
			ok = false
		else:
			print("[rules] OK  同回合第二次意志被拒绝（意志 %d）" % pl.will)

		# ——— 4) 弹药 ———
		var foe: CombatUnit = null
		for u in cm.units:
			if not u.is_player and u.hp > 0:
				foe = u
				break
		if foe == null:
			print("battle_rules_test: FAIL（没有敌人）")
			get_tree().quit(1)
			return
		var hp0: int = foe.hp
		pl.ammo = {"pistol": 0}
		bt._do_player_attack(foe)
		if foe.hp != hp0:
			print("[rules] FAIL 空弹匣仍造成伤害（敌人 %d → %d）" % [hp0, foe.hp])
			ok = false
		else:
			print("[rules] OK  空弹匣攻击无效")
		pl.ammo = {"pistol": 1}
		bt._do_player_attack(foe)
		if pl.ammo_left() != 0:
			print("[rules] FAIL 射击未消耗弹药（剩余 %d）" % pl.ammo_left())
			ok = false
		if foe.hp >= hp0:
			print("[rules] FAIL 有弹药射击未造成伤害（敌人 %d → %d）" % [hp0, foe.hp])
			ok = false
		if pl.ammo_left() == 0 and foe.hp < hp0:
			print("[rules] OK  射击消耗 1 发弹药并命中（敌人 %d → %d）" % [hp0, foe.hp])

		print("battle_rules_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
