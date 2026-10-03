extends Control
## 探索场景「像素化」截图验证（必须窗口模式运行，headless 无纹理）：
##   godot --path . res://tests/shot_scenario.tscn --quit-after 300
##
## 用途：确认 scenario.gd 换用 GridWorld + PixelGridRenderer 后的实际观感，
## 并作为「完整流程像素化」的验收依据。

func _ready() -> void:
	var p := Character.create_default()
	p.name = "测试者"
	p.attrs["str"] = 4
	p.attrs["dex"] = 4
	p.attrs["end"] = 3
	p.attrs["per"] = 3
	p.skills["brawl"] = 3
	p.skills["investigate"] = 2
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
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://assets/raw/_probe/scenario_pixel.png")
		img.save_png(path)
		print("[shot] 探索场景截图已保存：", path)
		get_tree().quit(0)
