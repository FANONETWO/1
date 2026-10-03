extends Node
## 运行期**操作日志**（autoload: DebugLog）
##
## 为什么需要它：在这之前，游戏只有底部那个给玩家看的"事件日志"，
## 排查问题只能靠截图反推 —— 又慢又容易漏（比如"连吃四个急救包血还在掉"
## 这种一眼可见的异常，是靠人工盯数十张截图才发现的）。
##
## 用法：
##   DebugLog.ev("battle", "用药回血", {"item": "medkit", "hp": [7, 15]})
##   DebugLog.count("battle")            # 某类事件发生次数
##   DebugLog.find("heal")               # 找出包含关键词的行
##   DebugLog.dump("user://run.log")     # 落盘，供脚本/CI 读取
##
## 纪律：**只记录事实，不记录判断**；数值一律带上（前后值、成功数、DC）。
## 键名用英文，值可以是任意类型。

var enabled := true
var echo_to_console := true        # 同时在 stdout 打印（便于 --headless 抓取）

var _lines: Array[String] = []
var _seq := 0

func ev(tag: String, msg: String, data: Dictionary = {}) -> void:
	_seq += 1
	var line := "%04d [%s] %s" % [_seq, tag, msg]
	if not data.is_empty():
		line += "  " + JSON.stringify(data)
	_lines.append(line)
	if echo_to_console or enabled:
		print("[LOG] " + line)

## 某类事件的出现次数
func count(tag: String) -> int:
	var n := 0
	var pfx := "[%s]" % tag
	for l in _lines:
		if l.contains(pfx):
			n += 1
	return n

## 包含关键词的所有行
func find(keyword: String) -> Array[String]:
	var out: Array[String] = []
	for l in _lines:
		if l.contains(keyword):
			out.append(l)
	return out

func has(keyword: String) -> bool:
	return not find(keyword).is_empty()

func all_lines() -> Array[String]:
	return _lines.duplicate()

func clear() -> void:
	_lines.clear()
	_seq = 0

## 落盘（user:// 或绝对路径）
func dump(path := "user://run.log") -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("\n".join(_lines))
	return ProjectSettings.globalize_path(path)

## 断言辅助：返回失败原因，空字符串表示通过
func expect(cond: bool, why: String) -> String:
	if cond:
		return ""
	ev("ASSERT_FAIL", why)
	return why
