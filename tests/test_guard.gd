class_name TestGuard
extends RefCounted
## 测试看门狗：给每一次测试运行一个**开始时间戳 + 最大允许时长**。
##
## 为什么必须有它：
##   测试里的 `await` 循环只要有一个条件不成立（例如「等玩家回合」而玩家回合永不到来、
##   等一个永远不会触发的信号），就会**无限等下去** —— 表现为进程不退出、CPU 空转，
##   整批回归被一个测试拖死，而且因为 stdout 被缓冲，连卡在哪都看不到。
##   外部运行器（tools/run_tests.ps1）虽然有进程级超时，但那里只能杀掉进程，
##   拿不到"哪个测试、跑到第几秒、开始于哪个时间戳"这些用来定位的信息。
##
## 用法（每个测试一行，放在 _ready() 最前面）：
##   TestGuard.arm("pace_test", 45.0, get_tree())
##
## 正常结束的测试不受影响（看门狗随进程一起消失）；超时的测试会被打印 FAIL 并 quit(1)，
## 退出码与输出都能被运行器正确识别。

const DEFAULT_LIMIT_SEC := 45.0

## 挂上看门狗。tag 用测试名（会和最终判定行一致），limit_sec 是硬上限秒数。
static func arm(tag: String, limit_sec: float, tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	var w := Watchdog.new()
	w.tag = tag
	w.limit_ms = int(maxf(1.0, limit_sec) * 1000.0)
	w.started_ms = Time.get_ticks_msec()
	w.started_wall = Time.get_datetime_string_from_system(false, true)
	w.name = "TestGuard_" + tag
	tree.root.add_child.call_deferred(w)
	print("[guard] %s 开始 ｜ 起始时间 %s ｜ 上限 %.0f 秒" % [tag, w.started_wall, limit_sec])

## 毫秒 → mm:ss.mmm（相对耗时，便于看"卡在第几秒"）
static func _elapsed_text(ms: int) -> String:
	var total_sec := int(ms / 1000)
	return "%02d:%02d.%03d" % [(total_sec / 60) % 60, total_sec % 60, ms % 1000]

## 看门狗节点：每帧检查是否超过上限
class Watchdog:
	extends Node

	var tag := ""
	var limit_ms := 45000
	var started_ms := 0
	var started_wall := ""
	var _fired := false

	func elapsed() -> float:
		return float(Time.get_ticks_msec() - started_ms) / 1000.0

	## 供测试在长循环里主动查询（想更早地优雅退出时用）
	func expired() -> bool:
		return Time.get_ticks_msec() - started_ms > limit_ms

	func _process(_delta: float) -> void:
		if _fired:
			return
		var used_ms := Time.get_ticks_msec() - started_ms
		if used_ms <= limit_ms:
			return
		_fired = true
		var msg := "[guard] %s 超过时间上限：起始 %s，已运行 %s（上限 %.1f 秒）—— 判定 FAIL 并强制退出" % [
			tag, started_wall, TestGuard._elapsed_text(used_ms), float(limit_ms) / 1000.0]
		printerr(msg)
		print(msg)
		print("%s: FAIL（超时 %s，疑似无限等待）" % [tag, TestGuard._elapsed_text(used_ms)])
		# 即使测试自己也卡在某个 await 里，这里也能把进程收掉
		get_tree().quit(1)
