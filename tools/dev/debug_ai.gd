extends SceneTree

func _init() -> void:
	var p := Character.create_default()
	p.attrs["str"] = 4
	p.attrs["dex"] = 4
	p.attrs["end"] = 3
	p.attrs["res"] = 3
	p.attrs["com"] = 3
	p.skills["brawl"] = 3
	p.weapon = "bat"
	p.hp = p.max_hp()
	p.will = p.max_will()
	var cm := CombatManager.new()
	cm.start(p, [{"id": "zombie", "pos": Vector2i(12, 12)}], Vector2i(12, 8))
	var z: CombatUnit = cm.units[1]
	var start_pos: Vector2i = z.pos
	print("start_pos=", start_pos, " player=", cm.player_unit.pos, " player_hp=", cm.player_unit.hp, " z.move=", z.move)
	cm.auto_turn(z, func(pos): return false)
	print("after: z.pos=", z.pos, " player_hp=", cm.player_unit.hp, " over=", cm.over, " victory=", cm.victory)
	print("logs: ", cm.logs)
	quit(0)
