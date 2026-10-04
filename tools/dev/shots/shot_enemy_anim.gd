extends Control
## 敌方攻击动画验证（窗口模式）：
##   godot --path . res://tools/dev/shots/shot_enemy_anim.tscn --quit-after 2000
##
## 关键：敌方是否先手是随机的，所以不能用固定延时截图。
## 这里每 0.15s 采样一次，只在「战斗特写层存在」的那一帧保存，必然抓到演出。

func _ready() -> void:
	var p := Character.create_default()
	p.name = "测试者"
	p.talent_id = "fighter"
	p.attrs["str"] = 4
	p.attrs["end"] = 3
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
		await get_tree().create_timer(1.6).timeout
		var sc := get_tree().current_scene
		if sc != null and sc.has_method("_start_combat_with"):
			print("[shot] 触发战斗")
			sc._start_combat_with("zombie")
		# 进入战斗后把玩家挪到敌人旁边，确保敌人一定会打过来
		await get_tree().create_timer(0.9).timeout
		var cb0 := get_tree().current_scene
		if cb0 != null and cb0.get("_cm") != null:
			var cm0 = cb0.get("_cm")
			for u in cm0.units:
				if not u.is_player and u.hp > 0:
					cm0.player_unit.pos = u.pos + Vector2i(1, 0)
					cb0._move_node(cm0.player_unit, cm0.player_unit.pos)
					break
			if cm0.is_player_turn():
				cb0._on_end_turn_pressed()
			else:
				cb0._start_enemy_sequence()
		for i in 26:
			await get_tree().create_timer(0.15).timeout
			var cb := get_tree().current_scene
			if _has_battle_anim(cb):
				var a := ProjectSettings.globalize_path("res://assets/raw/_probe/enemy_anim_a.png")
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(a)
				await get_tree().create_timer(0.55).timeout
				await RenderingServer.frame_post_draw
				var b := ProjectSettings.globalize_path("res://assets/raw/_probe/enemy_anim_b.png")
				get_viewport().get_texture().get_image().save_png(b)
				print("[shot] 已保存两张演出帧（第 %d 次采样）" % i)
				get_tree().quit(0)
				return
		print("[shot] 未抓到演出帧")
		get_tree().quit(1)

	func _has_battle_anim(node: Node) -> bool:
		if node == null:
			return false
		for c in node.get_children():
			if c is BattleAnim:
				return true
		return false
