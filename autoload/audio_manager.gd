extends Node
## 音频管理器（autoload）：全局音效与 BGM 的唯一播放入口。
##
## 设计约定（与项目「素材未就位也能完整跑通」的原则一致）：
## 1. **资源缺失绝不报错**：某个 wav 不存在时静默跳过，只在 DebugLog 里记一次，
##    因此音频资产是「可选的增强」而不是「启动依赖」。
## 2. **音效池**：固定 12 个 AudioStreamPlayer 轮转复用，避免连打时反复 new。
## 3. **节流**：同名音效在极短时间内重复触发会被丢弃（脚步、连击、血条刷新会刷屏）。
## 4. **M 键静音**，音量与静音状态存在 `user://settings.cfg`。
##
## 素材规格见 `assets/audio/README.md`；重新生成见 `tools/audio/gen_audio.py`。

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"
const SETTINGS_PATH := "user://settings.cfg"
const POOL_SIZE := 12
const DEFAULT_THROTTLE_MS := 35

signal mute_changed(is_muted: bool)
signal bgm_changed(name: String)

## 音效名 → 文件名（写死清单，保证调用处拼错时立刻暴露为「缺失」而不是静默无声）
const SFX_NAMES: Array[String] = [
	"ui_click", "ui_confirm", "ui_deny",
	"hit", "miss", "crit", "hurt", "die",
	"heal", "skill", "bloodline", "dice",
	"step", "door", "pickup", "clue",
	"noise", "evac", "defeat",
]
const BGM_NAMES: Array[String] = ["explore", "battle", "hub"]

var sfx_volume: float = 0.9      # 音效总音量（0~1）
var bgm_volume: float = 0.5      # BGM 总音量（0~1）
var muted: bool = false

var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _bgm: AudioStreamPlayer
var _cache: Dictionary = {}       # path -> AudioStream（含循环设置）
var _missing: Dictionary = {}     # path -> true（只记一次日志）
var _last_ms: Dictionary = {}     # 音效名 -> 上次播放时刻（节流）
var _current_bgm := ""
var _bgm_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	add_child(_bgm)
	_load_settings()
	_apply_mute()
	# 全局按钮音效：新加入场景树的按钮自动获得「嗒」声，
	# 无需在每个界面手动接线（手写过的那些也安全：35ms 节流会把重复的那次吞掉）。
	if get_tree() != null:
		get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_on_any_button):
		(n as BaseButton).pressed.connect(_on_any_button)

func _on_any_button() -> void:
	play("ui_click")

# ——— 对外 API ———

## 播放音效。opts: {pitch, gain, throttle}（throttle 单位毫秒，0 表示不限）
## 返回是否真的播出去了（静音 / 资源缺失 / 被节流都为 false —— 测试据此断言）。
func play(sfx: String, opts: Dictionary = {}) -> bool:
	if muted:
		return false
	var stream := _stream(SFX_DIR + sfx + ".wav", false)
	if stream == null:
		return false
	var throttle := int(opts.get("throttle", DEFAULT_THROTTLE_MS))
	var now := Time.get_ticks_msec()
	if throttle > 0 and _last_ms.has(sfx) and now - int(_last_ms[sfx]) < throttle:
		return false
	_last_ms[sfx] = now
	var p := _next_player()
	p.stream = stream
	p.volume_db = _db(sfx_volume * float(opts.get("gain", 1.0)))
	p.pitch_scale = maxf(0.05, float(opts.get("pitch", 1.0)))
	p.play()
	return true

## 我的脚步/攻击这类需要轻微随机化的场合：每次音高在 ±range 内浮动
func play_varied(sfx: String, pitch_range: float = 0.08, opts: Dictionary = {}) -> bool:
	var o := opts.duplicate()
	o["pitch"] = 1.0 + randf_range(-pitch_range, pitch_range)
	return play(sfx, o)

## 切换 BGM（同名不重启；name 为空则停止）
func play_bgm(bgm: String, fade := 0.5) -> void:
	if bgm == _current_bgm:
		return
	_current_bgm = bgm
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if bgm == "":
		_bgm.stop()
		bgm_changed.emit("")
		return
	var stream := _stream(BGM_DIR + bgm + ".wav", true)
	if stream == null:
		return
	_bgm.stop()
	_bgm.stream = stream
	if muted:
		bgm_changed.emit(bgm)
		return
	_bgm.volume_db = -60.0
	_bgm.play()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm, "volume_db", _db(bgm_volume), maxf(0.0, fade))
	bgm_changed.emit(bgm)

func stop_bgm() -> void:
	play_bgm("")

func current_bgm() -> String:
	return _current_bgm

## 静音开关（M 键）。静音时 BGM 暂停，取消静音后自动恢复。
func set_muted(v: bool) -> void:
	if muted == v:
		return
	muted = v
	_apply_mute()
	_save_settings()
	mute_changed.emit(muted)

func toggle_mute() -> bool:
	set_muted(not muted)
	return muted

func _apply_mute() -> void:
	# 直接静音主总线：所有播放器（含未来新增）一并生效
	AudioServer.set_bus_mute(0, muted)
	if muted:
		_bgm.stop()
	elif _current_bgm != "":
		var name := _current_bgm
		_current_bgm = ""
		play_bgm(name, 0.2)

# ——— 诊断（测试与调试用） ———

## 音频资产就位情况：{"sfx": {name: bool}, "bgm": {name: bool}}
func availability() -> Dictionary:
	var sfx := {}
	for n in SFX_NAMES:
		sfx[n] = ResourceLoader.exists(SFX_DIR + n + ".wav")
	var bgm := {}
	for n in BGM_NAMES:
		bgm[n] = ResourceLoader.exists(BGM_DIR + n + ".wav")
	return {"sfx": sfx, "bgm": bgm}

func ready_count() -> int:
	var a := availability()
	var c := 0
	for k in a["sfx"]:
		if bool(a["sfx"][k]):
			c += 1
	for k in a["bgm"]:
		if bool(a["bgm"][k]):
			c += 1
	return c

func missing_names() -> Array[String]:
	var out: Array[String] = []
	var a := availability()
	for k in a["sfx"]:
		if not bool(a["sfx"][k]):
			out.append("sfx/" + String(k))
	for k in a["bgm"]:
		if not bool(a["bgm"][k]):
			out.append("bgm/" + String(k))
	return out

# ——— 内部 ———

func _next_player() -> AudioStreamPlayer:
	# 优先找空闲播放器，全都忙则覆盖最旧的那一个（比 new 更可控）
	for i in POOL_SIZE:
		var idx := (_pool_i + i) % POOL_SIZE
		if not _pool[idx].playing:
			_pool_i = (idx + 1) % POOL_SIZE
			return _pool[idx]
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	return p

func _stream(path: String, loop: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
			DebugLog.ev("audio", "音频素材缺失，已静默跳过", {"path": path})
		return null
	var res: Resource = load(path)
	if not (res is AudioStream):
		return null
	var s: AudioStream = res
	if loop and s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# 兜底：导入器没配循环时手动补。
		# 注意 loop_end 的单位是「帧」，**写 0 会被引擎当成 0 帧边界**（不会自动取到末尾），
		# 所以这里显式按 get_length()×mix_rate 算帧数。
		# 正常路径是 assets/audio/bgm/*.wav.import 里 edit/loop_mode=1，不走这里。
		var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = maxi(1, int(round(w.get_length() * float(w.mix_rate))))
		s = w
	_cache[path] = s
	return s

func _db(linear: float) -> float:
	if linear <= 0.0001:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	bgm_volume = clampf(float(cf.get_value("audio", "bgm_volume", bgm_volume)), 0.0, 1.0)
	muted = bool(cf.get_value("audio", "muted", false))

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)   # 保留其它设置（例如将来加的画面选项）
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("audio", "bgm_volume", bgm_volume)
	cf.set_value("audio", "muted", muted)
	cf.save(SETTINGS_PATH)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_M:
			var m := toggle_mute()
			DebugLog.ev("audio", "静音切换", {"muted": m})
