extends Control
## 试玩：模拟玩家走完整流程并全程截图（我自己的"眼睛"）。
##   & $godot --path . res://tests/playthrough.tscn --quit-after 7200
## 注意：**不要加 --headless**，否则截图全黑。

const OUT := "res://assets/raw/playtest/"

var _n := 0

func _ready() -> void:
	var c := Character.create_default()
	c.name = "试玩员"
	c.talent_id = "fighter"
	c.attrs = {"str": 3, "dex": 3, "end": 3, "int": 3, "per": 3, "res": 3, "pre": 2, "man": 2, "com": 2}
	c.skills = {"brawl": 3}
	c.weapon = "bat"
	c.hp = c.max_hp()
	c.will = c.max_will()
	Game.new_game()
	Game.set_player(c)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	var sc: Node = null
	var n := 0
	var log_lines: Array[String] = []

	func _ready() -> void:
		await get_tree().create_timer(1.6).timeout
		sc = get_tree().current_scene
		if sc == null:
			print("[play] FAIL 场景未就绪")
			get_tree().quit(1)
			return
		print("[play] ===== 开始试玩 =====")

		# ——— 1) 起点与主神简报 ———
		await _shot("01_开场楼梯间")

		# ——— 2) 逐间走一遍（这是玩家最基础的行为：探索）———
		for rid in R001Rooms.ROOMS:
			sc._load_room(String(rid), Vector2i.ZERO, "play")
			await get_tree().create_timer(0.45).timeout
			var foes: int = (sc.get("_enemy_nodes") as Dictionary).size()
			var sp: int = (sc.get("_spot_nodes") as Dictionary).size()
			var np: int = (sc.get("_npc_nodes") as Dictionary).size()
			_note("房间 %s：敌人 %d ｜ 交互点 %d ｜ NPC %d" % [String(rid), foes, sp, np])
			await _shot("02_%s" % String(rid))

		# ——— 3) 对话：陈叔 ———
		sc._load_room("room_402", Vector2i.ZERO, "play")
		await get_tree().create_timer(0.4).timeout
		sc._talk_npc("room_402/chen")
		await get_tree().create_timer(0.5).timeout
		await _shot("03_对话_陈叔")
		sc._close_modal()
		await get_tree().create_timer(0.3).timeout

		# ——— 4) 对话：阿贵 ———
		sc._load_room("duty_room", Vector2i.ZERO, "play")
		await get_tree().create_timer(0.4).timeout
		sc._talk_npc("duty_room/agui")
		await get_tree().create_timer(0.5).timeout
		await _shot("04_对话_阿贵")
		sc._close_modal()
		await get_tree().create_timer(0.3).timeout

		# ——— 5) 调查交互点 ———
		for key in ["duty_room/duty_locker", "duty_room/duty_desk", "storage/storage_locker"]:
			sc._load_room(String(key).split("/")[0], Vector2i.ZERO, "play")
			await get_tree().create_timer(0.4).timeout
			sc._inspect_spot(String(key))
			await get_tree().create_timer(0.5).timeout
			await _shot("05_调查_%s" % String(key).replace("/", "_"))
			sc._close_modal()
			await get_tree().create_timer(0.25).timeout

		# ——— 6) 角色面板 ———
		sc._load_room("corridor_n", Vector2i.ZERO, "play")
		await get_tree().create_timer(0.4).timeout
		if sc.has_method("_show_character"):
			sc._show_character()
			await get_tree().create_timer(0.6).timeout
			await _shot("06_角色面板")
			sc._close_modal()
			await get_tree().create_timer(0.3).timeout

		# ——— 7) 打一场真实战斗，全程截图 ———
		sc._load_room("corridor_n", Vector2i.ZERO, "play")
		await get_tree().create_timer(0.4).timeout
		sc._start_combat_with("zombie")
		await get_tree().create_timer(2.4).timeout
		await _shot("07_战斗开场")
		var bt = sc.get("_battle")
		if bt != null:
			var cm = bt.get("_cm")
			_note("战斗单位：%d 个" % (cm.units as Array).size())
			# 打几个回合（真的走攻击流程）
			for i in 3:
				if cm.over:
					break
				var foe = null
				for u in cm.units:
					if not u.is_player and u.hp > 0:
						foe = u
						break
				if foe == null:
					break
				cm.player_unit.hp = 999
				cm.resolve_attack(cm.player_unit, foe)
				await get_tree().create_timer(0.5).timeout
				await _shot("07b_攻击第%d次" % (i + 1))
			# 打开血统技能菜单看看
			if bt.has_method("_open_will_menu"):
				bt._open_will_menu()
				await get_tree().create_timer(0.5).timeout
				await _shot("08_战斗_意志菜单")
			cm.over = true
			cm.victory = true
			bt._finish(true, false)
			await get_tree().create_timer(2.0).timeout
			await _shot("09_战斗结算后回到探索")

		# ——— 8) 逃跑测试 ———
		sc._load_room("lobby", Vector2i.ZERO, "play")
		await get_tree().create_timer(0.4).timeout
		sc._start_combat_with("walker")
		await get_tree().create_timer(2.2).timeout
		var bt2 = sc.get("_battle")
		if bt2 != null:
			bt2._finish(false, true)
			await get_tree().create_timer(2.0).timeout
			_note("逃跑后所在房间：%s" % String(sc.get("_room_id")))
			await _shot("10_逃跑之后")

		# ——— 9) 结局面板 ———
		sc._finish_scenario("normal", -1)
		await get_tree().create_timer(1.2).timeout
		await _shot("11_结算面板")

		print("[play] ===== 试玩结束，共 %d 张截图 =====" % n)
		for l in log_lines:
			print("[play] " + l)
		get_tree().quit(0)

	func _note(s: String) -> void:
		log_lines.append(s)
		print("[play] " + s)

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path(OUT + "%02d_%s.png" % [n, name])
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		n += 1
		print("[play] 截图 %02d %s" % [n, name])
