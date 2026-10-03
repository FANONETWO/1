extends Control
## 血统界面截图验证（窗口模式）：
##   godot --path . res://tests/shot_bloodline.tscn --quit-after 700
##
## 演示：激活血族 → 选择技能 → 再激活天使与恶魔（展示 65% 排斥 + 23% 协同）

func _ready() -> void:
	var p := Character.create_default()
	p.name = "测试者"
	p.talent_id = "fighter"
	p.attrs["str"] = 4
	p.hp = p.max_hp()
	p.will = p.max_will()
	Game.new_game()
	Game.set_player(p)
	Game.points = 8000
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://ui/hub.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(1.6).timeout
		var hub := get_tree().current_scene
		if hub == null or not hub.has_method("_open_bloodlines"):
			print("[shot] hub 未就绪")
			get_tree().quit(1)
			return
		hub._open_bloodlines()
		await get_tree().create_timer(0.8).timeout
		var panel: Node = null
		for c in hub.get_children():
			if c is BloodlinePanel:
				panel = c
		if panel == null:
			print("[shot] 血统面板未打开")
			get_tree().quit(1)
			return
		# 激活血族并选一个技能
		panel._activate("vampire")
		await get_tree().create_timer(0.3).timeout
		panel._toggle_skill("vampire", "bloody_body")
		await get_tree().create_timer(0.2).timeout
		# 再激活天使 + 恶魔 → 展示高排斥
		panel._activate("angel")
		panel._activate("demon")
		panel._select_blood("demon")
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://assets/raw/_probe/bloodline_panel.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("[shot] 血统界面已保存：", path)
		print("[shot] 排斥度=", Game.player.bloodline_rejection(), " 协同度=", Game.player.bloodline_synergy())
		get_tree().quit(0)
