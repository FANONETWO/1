extends Control
## 战斗动画截图验证（窗口模式）：
##   godot --path . res://tools/dev/shots/shot_battle_anim.tscn --quit-after 900
##
## 流程：进入像素切片 → 把玩家挪到丧尸旁边 → 触发攻击 → 在演出中途截图。

func _ready() -> void:
	var p := Character.create_default()
	p.name = "测试者"
	Game.new_game()
	Game.set_player(p)
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://tools/dev/demo/demo_scene.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(2.0).timeout
		var sc := get_tree().current_scene
		if sc == null or not sc.has_method("_try_attack"):
			print("[shot] 场景未就绪")
			get_tree().quit(1)
			return
		# 动态取第一个敌人（避免地图改动后写死的坐标失效）
		var foes: Array = sc.get("enemies")
		if foes.is_empty():
			print("[shot] 场景里没有敌人")
			get_tree().quit(1)
			return
		var foe: Dictionary = foes[0]
		var fpos: Vector2i = foe["pos"]
		sc.player_pos = fpos + Vector2i(1, 0)
		sc.player_sprite.position = sc._anchor(sc.player_pos)
		await get_tree().create_timer(0.4).timeout
		var e: Dictionary = sc._enemy_at(fpos)
		if e.is_empty():
			print("[shot] 附近没有敌人")
			get_tree().quit(1)
			return
		print("[shot] 触发攻击")
		sc._try_attack(e)
		# 冲刺 + 命中演出的瞬间
		await get_tree().create_timer(0.75).timeout
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://assets/raw/_probe/battle_anim.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("[shot] 战斗动画截图已保存：", path)
		get_tree().quit(0)
