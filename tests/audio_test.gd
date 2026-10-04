extends Node
## 音频系统验证：素材清单就位、播放 / 节流 / 静音 API、BGM 切换与循环标记。
##   godot --headless --path . res://tests/audio_test.tscn --quit-after 900
##
## 为什么要有这个测试：音频是「可选增强」——素材缺失时必须静默降级而不是崩。
## 这条约定一旦破坏，任何一台没生成音频的机器都会开不了游戏。

func _ready() -> void:
	TestGuard.arm("audio_test", 45, get_tree())
	await get_tree().process_frame
	var fails: Array[String] = []

	# 1) 素材就位情况
	var avail: Dictionary = AudioManager.availability()
	var sfx_ok := 0
	for k in avail["sfx"]:
		if bool(avail["sfx"][k]):
			sfx_ok += 1
		else:
			fails.append("缺失音效 " + String(k))
	var bgm_ok := 0
	for k in avail["bgm"]:
		if bool(avail["bgm"][k]):
			bgm_ok += 1
		else:
			fails.append("缺失 BGM " + String(k))
	print("[audio] 音效 %d/%d，BGM %d/%d" % [sfx_ok, avail["sfx"].size(), bgm_ok, avail["bgm"].size()])

	# 2) 正常播放
	var played: bool = AudioManager.play("hit", {"throttle": 0})
	print("[audio] play(hit) → %s（应 true）" % played)
	if not played:
		fails.append("play 未生效")

	# 3) 节流：极短时间内同名音效只响一次
	var throttled: bool = AudioManager.play("hit", {"throttle": 5000})
	print("[audio] 5s 节流内重播 → %s（应 false）" % throttled)
	if throttled:
		fails.append("节流失效")

	# 4) throttle=0 可强制再播（连打场景）
	var forced: bool = AudioManager.play("hit", {"throttle": 0})
	if not forced:
		fails.append("throttle=0 未生效")

	# 5) 静音应拦截播放
	AudioManager.set_muted(true)
	var when_muted: bool = AudioManager.play("crit", {"throttle": 0})
	AudioManager.set_muted(false)
	print("[audio] 静音时 play → %s（应 false）" % when_muted)
	if when_muted:
		fails.append("静音未拦截")

	# 6) BGM 切换（同名不重启、异名要切）
	AudioManager.play_bgm("battle")
	if AudioManager.current_bgm() != "battle":
		fails.append("BGM 未切到 battle")
	AudioManager.play_bgm("explore")
	print("[audio] BGM 当前 = %s（应 explore）" % AudioManager.current_bgm())
	if AudioManager.current_bgm() != "explore":
		fails.append("BGM 未切到 explore")

	# 7) 缺失资源必须静默返回 false，不能报错
	var ghost: bool = AudioManager.play("__不存在的音效__", {"throttle": 0})
	print("[audio] 播放缺失音效 → %s（应 false，且无报错）" % ghost)
	if ghost:
		fails.append("缺失资源竟然播出声了")

	# 8) 循环装载：BGM 必须在引擎里真的循环（loop_mode 开、loop_end 是有效帧数）
	#    坑：loop_end 单位是「帧」，写 0 会被引擎当作 0 帧边界（不是「到末尾」）→ BGM 会卡住不循环
	var st: AudioStream = AudioManager._stream("res://assets/audio/bgm/explore.wav", true)
	if st is AudioStreamWAV:
		var w: AudioStreamWAV = st
		var frames := int(round(w.get_length() * float(w.mix_rate)))
		print("[audio] explore.wav loop_mode=%d loop_end=%d 总帧数=%d format=%d" % [w.loop_mode, w.loop_end, frames, w.format])
		if w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			fails.append("BGM 未打开循环")
		if w.loop_end <= 0 or w.loop_end > frames + 1:
			fails.append("BGM loop_end 不是有效帧数（当前 %d，总帧 %d）" % [w.loop_end, frames])
	else:
		fails.append("BGM 不是 AudioStreamWAV")

	AudioManager.play_bgm("")
	AudioManager._cache.clear()   # 退出前放开流资源，避免 "resources still in use at exit"

	var ok := fails.is_empty()
	print("audio_test: %s%s" % ["PASS" if ok else "FAIL", "" if ok else " → " + "；".join(fails)])
	get_tree().quit(0 if ok else 1)
