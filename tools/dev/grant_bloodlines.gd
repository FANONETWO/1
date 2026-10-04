extends Control
## 给存档装上一套测试血统，供实战试玩「技能打怪」：
##   godot --headless --path . res://tools/dev/grant_bloodlines.tscn --quit-after 300
##
## 配置：仙体系 C + 天使 C
##   · 排斥 0%（神圣/生命/精神 与 神圣/秩序/精神 完全相容）
##   · 协同 60%（封顶）→ 血统技能威力 ×1.35
##   · 3 个主动技能：御剑（单体 7）· 符箓（单体 5）· 治愈之手（回血 7）

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {
		"str": 4, "dex": 3, "end": 3,
		"int": 3, "per": 3, "res": 3,
		"pre": 2, "man": 2, "com": 2,
	}
	c.skills = {
		"brawl": 3, "blade": 2, "gun": 1, "hide": 1, "survival": 1,
		"investigate": 2, "medicine": 1, "occult": 1,
		"social": 1, "intimidate": 1, "subterfuge": 1, "empathy": 1,
	}
	c.weapon = "bat"
	# 每条血统都已选满当前评级（升级的前置要求）
	c.bloodlines = [
		{"id": "immortal", "rank": "C", "picked": [
			"spirit_sense", "qi_ward",        # D 级 2 选 2
			"flying_sword", "talisman",       # C 级 2 选 2（主动技能）
		]},
		{"id": "angel", "rank": "C", "picked": [
			"holy_ward", "faith",             # D 级
			"heal_touch", "judgement",        # C 级（主动 + 被动）
		]},
	]
	c.inventory = ["medkit", "tranquilizer", "blood_stabilizer", "blood_stabilizer"]
	c.hp = c.max_hp()
	c.will = c.max_will()

	Game.new_game()
	Game.set_player(c)
	Game.points = 8000
	Game.save_game()

	print("[grant] 血统 =", c.bloodlines)
	print("[grant] 排斥度 %d%%（%s）｜协同度 %d%%（%s）｜技能加成 ×%.2f" % [
		c.bloodline_rejection(), Bloodlines.rejection_tier(c.bloodline_rejection()),
		c.bloodline_synergy(), Bloodlines.synergy_tier(c.bloodline_synergy()),
		c.bloodline_combat_mods()["node_bonus"],
	])
	print("[grant] 属性校验：耐力 %d（含血统加成 %d）→ 生命 %d ｜意志 %d" % [
		c.attr("end"), c.bloodline_attr_bonus("end"), c.max_hp(), c.max_will(),
	])
	var skills := c.bloodline_active_skills()
	print("[grant] 主动技能 %d 个：" % skills.size())
	for n in skills:
		print("   · %s —— %s" % [String(n["name"]), Bloodlines.effect_text(String(n["id"]))])
	print("[grant] 奖励点 %d ｜背包 %s" % [Game.points, str(c.inventory)])
	get_tree().quit(0)
