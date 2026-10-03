extends Control
## 主菜单：新的开始 / 继续 / 退出。

func _ready() -> void:
	theme = PixelTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	add_child(v)

	var title := Label.new()
	title.text = "轮 回 回 廊"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "无限流 · CRPG 垂直切片"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.55)
	v.add_child(sub)
	v.add_child(_spacer(10))
	var sub2 := Label.new()
	sub2.text = "D10 骰池检定 · 行动点回合制 · 基因锁 · 主神空间"
	sub2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub2.modulate = Color(1, 1, 1, 0.35)
	sub2.add_theme_font_size_override("font_size", 13)
	v.add_child(sub2)

	v.add_child(_spacer(26))

	var new_btn := Button.new()
	new_btn.text = "新的开始"
	new_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://ui/char_creation.tscn")
	)
	v.add_child(new_btn)
	var cont := Button.new()
	# P4：基因崩溃导致角色永久阵亡后，不能再用旧档继续
	var dead := Game.peek_player_dead()
	cont.text = "继续" if not dead else "继续（角色已阵亡）"
	cont.disabled = not Game.has_save() or dead
	cont.pressed.connect(func() -> void:
		if Game.load_game():
			Game.go_hub()
		else:
			cont.disabled = true
	)
	v.add_child(cont)
	var quit := Button.new()
	quit.text = "退出"
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)

	var hint := Label.new()
	hint.text = "第一场影片：「惊变公寓」——活下来，找到钥匙，离开。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.4)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -56
	hint.offset_bottom = -30
	add_child(hint)

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
