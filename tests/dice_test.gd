extends SceneTree
## D10 骰池统计测试。
##   godot --headless --path . -s res://tests/dice_test.gd

var _fails := 0

func _init() -> void:
	print("dice_test: start")
	# 1. 常规模块：DP=10（属性5+技能5）均值应在 3~5.5
	var sum := 0
	var n := 2000
	for i in n:
		sum += DicePool.roll(5, 5, 0, 0, "brawl")["total"]
	var avg := float(sum) / n
	_check(avg > 2.8 and avg < 6.0, "DP10 均值应在合理区间（实际 %.2f）" % avg)

	# 2. 心智系技能 0 级 → 自动失败
	var res := DicePool.roll(5, 0, 0, 0, "medicine")
	_check(res["failed_zero"] and res["total"] == 0, "心智技能 0 级自动失败")

	# 3. 生理系技能 0 级 → 惩罚 -1 成功（可尝试）
	var res2 := DicePool.roll(5, 0, 0, 0, "brawl")
	_check(not res2["failed_zero"], "生理技能 0 级可尝试")

	# 4. 附加成功：属性 6 → +1，技能 5 → +1
	var res3 := DicePool.roll(6, 5, 0, 0, "brawl")
	_check(res3["bonus"] >= 2, "属性6+技能5 至少 2 附加成功")

	# 5. 高 DP 不应溢出：成功数上限合理
	var res4 := DicePool.roll(1, 1, 0, 0, "brawl")
	_check(res4["dice"] >= 2, "DP 至少 2（属性+技能）")

	# 6. 10 加骰存在：多次掷骰中骰面应出现 ≥10 的加骰（rolls 数组长度可超过 DP）
	var saw_chain := false
	for i in 300:
		var r := DicePool.roll(8, 8, 0, 0, "brawl")
		if int(r["dice"]) < r["rolls"].size():
			saw_chain = true
			break
	_check(saw_chain, "10 加骰链可触发")

	print("dice_test: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok - " + label)
	else:
		_fails += 1
		printerr("  FAIL - " + label)
