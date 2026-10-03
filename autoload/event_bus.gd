extends Node
## 全局信号总线：场景间解耦通信。

signal log_line(text: String)                    # 探索/战斗叙事日志
signal combat_log(text: String)                  # 战斗日志（带颜色标记）
signal quest_updated(quest_id: StringName)       # 任务状态变化
signal clue_found(clue_id: StringName, text: String)
signal points_changed(points: int)               # 积分变化（主神空间刷新）
signal player_hp_changed(hp: int, max_hp: int)
signal player_will_changed(will: int, max_will: int)
signal gene_lock_unlocked(level: int)            # 基因锁开启
signal scenario_finished(result: Dictionary)     # 副本结算
signal screen_flash(text: String, color: Color)  # 中央大字提示
