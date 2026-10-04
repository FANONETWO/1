extends Control
## 战斗场景「像素化」截图验证（窗口模式）：
##   godot --path . res://tools/dev/shots/shot_combat.tscn --quit-after 500
##
## 流程：建卡 → 进入探索场景 → 触发一场战斗 → 截图战斗画面。

func _ready() -> void:
	var p := Character.create_default()
	p.name = "测试者"
	p.attrs["str"] = 4
	p.attrs["dex"] = 4
	p.attrs["end"] = 3
	p.skills["brawl"] = 3
	p.talent_id = "fighter"
	p.weapon = "bat"
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	var d := ShotDriver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class ShotDriver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.6).timeout
		var sc := get_tree().current_scene
		if sc != null and sc.has_method("_start_combat_with"):
			print("[shot] 触发战斗")
			sc._start_combat_with("zombie")
		await get_tree().create_timer(2.2).timeout
		var cb := get_tree().current_scene
		if cb != null and cb.get("_cm") != null:
			var cm = cb.get("_cm")
			if cm.is_player_turn() and cm.units.size() > 1:
				var target = cm.units[1]
				# 先把玩家挪到敌人旁边，否则会因距离判定失败
				cm.player_unit.pos = target.pos + Vector2i(1, 0)
				print("[shot] 触发攻击（验证火纹动画）")
				cb._try_attack(target)
		await get_tree().create_timer(0.85).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://assets/raw/_probe/combat_pixel.png")
		img.save_png(path)
		print("[shot] 战斗场景截图已保存：", path)
		get_tree().quit(0)
