extends Control
## 打开角色检视面板并截图；顺带验证装备切换与消耗品使用。
##   godot --path . res://tools/dev/shots/shot_character_panel.tscn --quit-after 1800

func _ready() -> void:
	var c := Character.create_default()
	c.name = "轮回者"
	c.talent_id = "fighter"
	c.attrs = {"str": 4, "dex": 4, "end": 4, "int": 3, "per": 4, "res": 4, "pre": 3, "man": 3, "com": 4}
	c.skills = {"brawl": 4, "blade": 3, "hide": 2, "gun": 1}
	c.weapon = "machete"
	c.armor = "vest_light"
	c.inventory = ["bat", "pistol", "medkit", "tranquilizer", "vest_heavy", "apartment_key"]
	c.hp = c.max_hp() - 3
	c.will = c.max_will() - 1
	c.bloodlines = [{"id": "angel", "rank": "C", "picked": ["holy_ward", "faith"]}]
	Game.new_game()
	Game.set_player(c)
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://scenarios/r001_apartment/scenario.tscn")

class Driver:
	extends Node

	## 面板现在挂在 CanvasLayer 里，需要递归查找
	func _find_panel(node: Node):
		if node is CharacterPanel:
			return node
		for c in node.get_children():
			var r = _find_panel(c)
			if r != null:
				return r
		return null

	func _ready() -> void:
		await get_tree().create_timer(1.2).timeout
		var sc := get_tree().current_scene
		var p: Character = Game.player

		# 1) 装备切换：换上手枪，开山刀应回到背包
		print("[panel] 初始：武器=%s 护甲=%s 背包=%s" % [p.weapon, p.armor, str(p.inventory)])
		sc._show_character()
		await get_tree().create_timer(0.4).timeout
		var cp = _find_panel(sc)
		if cp == null:
			print("[panel] FAIL 面板未创建")
			get_tree().quit(1)
			return
		cp._use_item("pistol", Items.get_def("pistol"))
		print("[panel] 装备手枪后：武器=%s 背包含开山刀=%s" % [p.weapon, str(p.inventory.has("machete"))])
		var ok_weapon: bool = p.weapon == "pistol" and p.inventory.has("machete")

		# 2) 消耗品：急救包回血
		p.hp = 5
		cp._use_item("medkit", Items.get_def("medkit"))
		print("[panel] 用急救包后 HP=%d（应 10）背包含急救包=%s" % [p.hp, str(p.inventory.has("medkit"))])
		var ok_heal: bool = p.hp == 10 and not p.inventory.has("medkit")

		# 3) 护甲：换战术背心
		cp._use_item("vest_heavy", Items.get_def("vest_heavy"))
		print("[panel] 装备战术背心后：护甲=%s 背包含防刺背心=%s" % [p.armor, str(p.inventory.has("vest_light"))])
		var ok_armor: bool = p.armor == "vest_heavy" and p.inventory.has("vest_light")

		# 4) 卸下武器：只回收装备本身，不能把「拳头」当物品塞进背包（曾出现 4 个重复拳头）
		p.weapon = "machete"
		p.inventory.erase("machete")
		var before_n: int = p.inventory.size()
		cp._unequip("weapon")
		var delta: int = p.inventory.size() - before_n
		print("[panel] 卸下武器后：武器=%s 背包增量=%d（应 1）含拳头=%s" % [
			p.weapon, delta, str(p.inventory.has("fists"))])
		var ok_unequip: bool = p.weapon == "fists" and delta == 1 and not p.inventory.has("fists")

		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://assets/raw/_probe/character_panel.png"))
		print("[panel] 已保存 character_panel.png")

		var ok: bool = ok_weapon and ok_heal and ok_armor and ok_unequip
		print("shot_character_panel: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
