extends Control
## UI 像素主题截图验证：主菜单 + 主神空间（窗口模式）
##   godot --path . res://tests/shot_ui.tscn --quit-after 600

func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")

class Driver:
	extends Node

	func _ready() -> void:
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		_shot("res://assets/raw/_probe/ui_menu.png")

		var p := Character.create_default()
		p.name = "测试者"
		p.talent_id = "fighter"
		p.attrs["str"] = 4
		p.attrs["dex"] = 4
		p.hp = p.max_hp()
		p.will = p.max_will()
		Game.new_game()
		Game.set_player(p)
		get_tree().change_scene_to_file("res://ui/hub.tscn")
		await get_tree().create_timer(2.2).timeout
		await RenderingServer.frame_post_draw
		_shot("res://assets/raw/_probe/ui_hub.png")
		get_tree().quit(0)

	func _shot(path: String) -> void:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(path))
		print("[shot] ", path)
