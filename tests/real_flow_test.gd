extends Control
## 真实流程清理测试：探索 → 触发战斗 → 击杀 → 返回探索 → 检查尸体是否清理。
## 与 combat_return_test 的区别：这里走**真实**的 _start_combat_with / _check_over / _back，
## 不注入任何模拟数据，用于复现「回到地图上怪还站着」的问题。
##   godot --headless --path . res://tests/real_flow_test.tscn --quit-after 900

func _ready() -> void:
	var p := Character.create_default()
	p.name = "流程测试"
	p.talent_id = "fighter"
	p.attrs["str"] = 6
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.2).timeout
		var sc := get_tree().current_scene
		# 箱庭制：起点楼梯间无敌人，先切到北侧走廊
		sc._load_room("corridor_n", Vector2i.ZERO, "test")
		await get_tree().create_timer(0.2).timeout
		var before: Dictionary = sc.get("_enemy_nodes")
		print("  [1] 战斗前探索敌人：", before.keys())

		sc._start_combat_with("zombie")
		await get_tree().create_timer(1.0).timeout
		# 融合模式：战斗控制器挂在**同一场景**上（不再切换场景）
		var cb: Node = sc.get("_battle")
		if cb == null or cb.get("_cm") == null:
			printerr("real_flow_test: FAIL（战斗未就绪）")
			get_tree().quit(1)
			return
		var cm = cb.get("_cm")
		var uids: Array = []
		for u in cm.units:
			if not u.is_player:
				uids.append(u.uid)
				u.hp = 1
		print("  [2] 战斗内敌人 uid：", uids)
		# 用真实攻击结算逐个击杀（必须走 resolve_attack，才会触发 CombatManager 的胜负判定）
		for i in 24:
			if cm.over:
				break
			var foe: CombatUnit = null
			for u in cm.units:
				if not u.is_player and u.hp > 0:
					foe = u
					break
			if foe == null:
				break
			cm.resolve_attack(cm.player_unit, foe)
			await get_tree().create_timer(0.06).timeout
		cb._check_over()
		var dump: Array = []
		for u in cm.units:
			dump.append("%s(player=%s,hp=%d)" % [u.uid, str(u.is_player), u.hp])
		print("  [2.5] 战斗单位=", dump, " over=", cm.over, " victory=", cm.victory)

		# ——— 融合：战斗结束即在原地继续（不切场景、不重建地图）———
		await get_tree().create_timer(1.6).timeout
		var sc2 := get_tree().current_scene
		var same_scene: bool = sc2 == sc
		var after: Dictionary = sc.get("_enemy_nodes")
		print("  [3] 场景未切换：", same_scene)
		print("  [4] 战斗后探索敌人：", after.keys())
		var stuck: Array = []
		for u in uids:
			if after.has(String(u)):
				stuck.append(u)
		print("  [5] 应消失但仍存在：", stuck)
		var ok: bool = stuck.is_empty() and same_scene and sc.get("_battle") == null
		print("real_flow_test: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
