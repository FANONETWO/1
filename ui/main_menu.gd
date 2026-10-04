extends Control
## 主菜单（明日方舟风格）：左侧标识与竖排菜单，右侧影片情报。
## 排版纪律：一切靠绝对定位 + 细线 + 留白分区，不用居中堆叠（那是网页游戏的观感）。
##
## ⚠️ 按钮**文字本身**不要加编号或前后缀：
##    实机脚本与 ui_flow_driver 都按文字找按钮（精确或前缀匹配），
##    编号请放到按钮左边的独立 Label 里。

const VW := 1280.0
const VH := 720.0

func _ready() -> void:
	theme = AkTheme.build()
	AudioManager.play_bgm("hub")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	add_child(AkBackdrop.new())

	_build_corner_mark()
	_build_title()
	_build_menu()
	_build_intel()
	_build_footer()

# ——— 左上角标识 ———

func _build_corner_mark() -> void:
	var ac := Label.new()
	ac.text = AkTheme.spaced("REINCARNATION CORRIDOR", 1)
	ac.add_theme_font_size_override("font_size", AkTheme.FS_TINY)
	ac.add_theme_color_override("font_color", AkTheme.ACCENT)
	ac.position = Vector2(78, 38)
	add_child(ac)

	var rule := ColorRect.new()
	rule.color = AkTheme.LINE_HI
	rule.position = Vector2(80, 58)
	rule.size = Vector2(236, 1)
	add_child(rule)

	var cn := AkTheme.dim("无限流 · 主神空间终端", AkTheme.FS_SMALL, AkTheme.TEXT_FAINT)
	cn.position = Vector2(80, 66)
	add_child(cn)

# ——— 主标题（斜切面板 + 右上斜纹）———

func _build_title() -> void:
	var head := AkFrame.new()
	head.draw_hatch = true
	head.position = Vector2(76, 148)
	head.size = Vector2(596, 208)
	add_child(head)

	var eb := AkTheme.dim("无限流题材 ｜ 单机回合制 CRPG", AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
	eb.position = Vector2(110, 176)
	add_child(eb)

	var big := Label.new()
	big.text = "轮回回廊"
	big.add_theme_font_size_override("font_size", AkTheme.FS_TITLE)
	big.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	big.position = Vector2(104, 196)
	add_child(big)

	var en := AkTheme.dim(AkTheme.spaced("REINCARNATION CORRIDOR", 1), AkTheme.FS_TINY, AkTheme.TEXT_FAINT)
	en.position = Vector2(110, 280)
	add_child(en)

	var bar := ColorRect.new()
	bar.color = AkTheme.ACCENT
	bar.position = Vector2(110, 302)
	bar.size = Vector2(56, 2)
	add_child(bar)

	var desc := AkTheme.dim("深夜的公寓楼。走廊里有东西在拖行，楼上的人一直没下班，出口锁着。",
		AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
	desc.position = Vector2(110, 318)
	add_child(desc)

# ——— 竖排菜单 ———

func _build_menu() -> void:
	var dead := Game.peek_player_dead()
	var entries := [
		{"no": "01", "text": "新的开始", "cb": func() -> void:
			AudioManager.play("ui_confirm")
			get_tree().change_scene_to_file("res://ui/char_creation.tscn")},
		{"no": "02", "text": "继续", "cb": func() -> void:
			AudioManager.play("ui_confirm")
			if Game.load_game():
				Game.go_hub()},
		{"no": "03", "text": "退出", "cb": func() -> void:
			AudioManager.play("ui_click")
			get_tree().quit()},
	]
	var y := 404.0
	for e in entries:
		var row := HBoxContainer.new()
		row.position = Vector2(78, y)
		row.add_theme_constant_override("separation", 0)
		add_child(row)

		var num := Label.new()
		num.text = String(e["no"])
		num.add_theme_font_size_override("font_size", AkTheme.FS_SMALL)
		num.add_theme_color_override("font_color", AkTheme.TEXT_FAINT)
		num.custom_minimum_size = Vector2(46, 54)
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(num)

		var b := Button.new()
		# 继续：P4 基因崩溃导致角色永久阵亡后不能再用旧档
		if String(e["text"]) == "继续" and dead:
			b.text = "继续（角色已阵亡）"
		else:
			b.text = String(e["text"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(430, 54)
		b.add_theme_font_size_override("font_size", AkTheme.FS_H2)
		if String(e["text"]) == "继续":
			b.disabled = not Game.has_save() or dead
			var b_ref := b
			b.pressed.connect(func() -> void:
				AudioManager.play("ui_confirm")
				if Game.load_game():
					Game.go_hub()
				else:
					b_ref.disabled = true)
		else:
			b.pressed.connect(e["cb"])
		row.add_child(b)
		y += 62.0

# ——— 右侧：第一场影片情报 ———

func _build_intel() -> void:
	var side := AkFrame.new()
	side.accent_color = AkTheme.LINE_HI
	side.position = Vector2(726, 148)
	side.size = Vector2(478, 350)
	add_child(side)

	var tag := AkTheme.dim("待派发影片", AkTheme.FS_SMALL, AkTheme.TEXT_FAINT)
	tag.position = Vector2(756, 174)
	add_child(tag)

	var name_lb := Label.new()
	name_lb.text = "惊变公寓"
	name_lb.add_theme_font_size_override("font_size", 34)
	name_lb.add_theme_color_override("font_color", Color.WHITE)
	name_lb.position = Vector2(754, 196)
	add_child(name_lb)

	var diff := AkTheme.dim("难度  D      存活率  12%", AkTheme.FS_SMALL, AkTheme.AMBER)
	diff.position = Vector2(758, 240)
	add_child(diff)

	var rule := ColorRect.new()
	rule.color = AkTheme.LINE
	rule.position = Vector2(756, 266)
	rule.size = Vector2(418, 1)
	add_child(rule)

	var lines := [
		["主线", "天亮前离开公寓楼"],
		["支线", "救援 / 调查 / 清剿"],
		["时限", "06:00"],
	]
	var ly := 280.0
	for l in lines:
		var k := AkTheme.dim(String(l[0]), AkTheme.FS_SMALL, AkTheme.ACCENT)
		k.position = Vector2(758, ly)
		k.custom_minimum_size = Vector2(60, 0)
		add_child(k)
		var v := AkTheme.dim(String(l[1]), AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
		v.position = Vector2(818, ly)
		add_child(v)
		ly += 26.0

	var rule2 := ColorRect.new()
	rule2.color = AkTheme.LINE
	rule2.position = Vector2(756, 372)
	rule2.size = Vector2(418, 1)
	add_child(rule2)

	var sys_tag := AkTheme.dim("系统特性", AkTheme.FS_SMALL, AkTheme.TEXT_FAINT)
	sys_tag.position = Vector2(756, 384)
	add_child(sys_tag)

	var sys := AkTheme.dim("D10 骰池检定 · 行动点回合制 · 行动条（CTB）\n血统系统 · 迷雾潜行 · 独狼 / 四人小队", AkTheme.FS_SMALL, AkTheme.TEXT_DIM)
	sys.position = Vector2(758, 406)
	add_child(sys)

	var ver := AkTheme.dim("垂直切片  v0.4      构建  Godot 4.7.2", AkTheme.FS_TINY, AkTheme.TEXT_FAINT)
	ver.position = Vector2(758, 466)
	add_child(ver)

# ——— 页脚 ———

func _build_footer() -> void:
	var line := ColorRect.new()
	line.color = AkTheme.LINE
	line.position = Vector2(78, VH - 58)
	line.size = Vector2(VW - 156, 1)
	add_child(line)

	var hint := AkTheme.dim("第一场影片：「惊变公寓」——活下来，找到钥匙，离开。",
		AkTheme.FS_SMALL, AkTheme.TEXT_FAINT)
	hint.position = Vector2(80, VH - 48)
	add_child(hint)

	var tip := AkTheme.dim("M 键静音", AkTheme.FS_TINY, AkTheme.TEXT_FAINT)
	tip.position = Vector2(VW - 158, VH - 44)
	add_child(tip)
