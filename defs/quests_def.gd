class_name QuestsDef
extends RefCounted
## 任务定义。kind: main 主线 / side 支线。
## 状态机：not_started -> active -> done / failed（由 Quests 管理器维护）。

const ALL := {
	"escape": {
		"id": "escape", "kind": "main", "name": "活着离开",
		"desc": "在尸潮吞没整栋楼之前，找到一楼安全出口的钥匙并离开公寓。",
		"hint_active": "找到公寓一层的安全出口钥匙，前往大门撤离。",
		"reward_points": 20,
	},
	"save_chen": {
		"id": "save_chen", "kind": "side", "name": "老邻居",
		"desc": "402 的陈叔把自己锁在屋里。如果你能拿到他需要的降压药，他会告诉你一些事。",
		"hint_active": "在值班室药柜找到降压药，交给陈叔。",
		"reward_points": 10,
	},
	"clear_lobby": {
		"id": "clear_lobby", "kind": "side", "name": "清道夫",
		"desc": "尸王堵住了大门。要撤离，就得先解决它。",
		"hint_active": "击败盘踞在大厅的尸王。",
		"reward_points": 25,
	},
}

static func get_def(id: String) -> Dictionary:
	return ALL.get(id, {})
