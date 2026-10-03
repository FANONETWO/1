extends Control
## 全场景巡检：依次加载 5 个主要场景并截图，用于快速定位显示/报错问题。
##   godot --path . res://tests/shot_tour.tscn --quit-after 1800

func _ready() -> void:
	var t := Tour.new()
	get_tree().root.add_child.call_deferred(t)

class Tour:
	extends Node

	var scenes := [
		["res://main_menu.tscn", "tour_1_menu"],
		["res://ui/char_creation.tscn", "tour_2_create"],
		["res://ui/hub.tscn", "tour_3_hub"],
		["res://scenarios/r001_apartment/scenario.tscn", "tour_4_scenario"],
		["res://demo/demo_scene.tscn", "tour_5_demo"],
	]

	func _ready() -> void:
		var p := Character.create_default()
		p.name = "巡检者"
		p.talent_id = "fighter"
		p.attrs["str"] = 4
		p.attrs["dex"] = 4
		p.attrs["end"] = 3
		p.skills["brawl"] = 3
		p.weapon = "bat"
		p.hp = p.max_hp()
		p.will = p.max_will()
		Game.new_game()
		Game.set_player(p)

		for s in scenes:
			get_tree().change_scene_to_file(String(s[0]))
			await get_tree().create_timer(1.9).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var out := ProjectSettings.globalize_path("res://assets/raw/_probe/%s.png" % String(s[1]))
			img.save_png(out)
			print("[tour] ", s[1], " <- ", s[0])
		print("[tour] 巡检完成")
		get_tree().quit(0)
