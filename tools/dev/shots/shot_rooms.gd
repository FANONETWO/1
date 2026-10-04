extends Control
## 依次载入几个箱庭并截图，用于检查箱庭制的外观。
##   godot --path . res://tools/dev/shots/shot_rooms.tscn --quit-after 3600

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {"str": 3, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3}
	c.weapon = "bat"
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
			print("shot_rooms: FAIL（场景未就绪）")
			get_tree().quit(1)
			return
		var rooms := ["stair_hall", "corridor_n", "duty_room", "storage", "lobby",
			"room_402", "utility", "guest_room", "empty_room"]
		for rid in rooms:
			sc._load_room(String(rid), Vector2i.ZERO, "shot")
			await get_tree().create_timer(0.45).timeout
			await RenderingServer.frame_post_draw
			var path := ProjectSettings.globalize_path("res://assets/raw/_probe/room_%s.png" % rid)
			get_viewport().get_texture().get_image().save_png(path)
			var foes: int = (sc.get("_enemy_nodes") as Dictionary).size()
			var spots: int = (sc.get("_spot_nodes") as Dictionary).size()
			var npcs: int = (sc.get("_npc_nodes") as Dictionary).size()
			print("[rooms] %-12s 敌人 %d ｜ 交互点 %d ｜ NPC %d" % [String(rid), foes, spots, npcs])
		print("[rooms] 完成 7 张截图")
		get_tree().quit(0)
