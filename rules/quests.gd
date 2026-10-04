class_name Quests
extends RefCounted
## 任务管理器（纯逻辑）。状态：not_started / active / done / failed。

var states: Dictionary = {}  # quest_id -> status
var defs: Dictionary = {}

func _init(quest_ids: Array[StringName]) -> void:
	for qid in quest_ids:
		defs[String(qid)] = QuestsDef.get_def(String(qid))

func start(id: StringName) -> void:
	states[String(id)] = "active"
	_safe_emit(String(id))

func activate_all() -> void:
	for qid in defs:
		if not states.has(qid):
			states[qid] = "active"
			_safe_emit(String(qid))

func status(id: StringName) -> String:
	return String(states.get(String(id), "not_started"))

func is_active(id: StringName) -> bool:
	return status(id) == "active"

func is_done(id: StringName) -> bool:
	return status(id) == "done"

func complete(id: StringName) -> void:
	states[String(id)] = "done"
	_safe_emit(String(id))

func fail(id: StringName) -> void:
	states[String(id)] = "failed"
	_safe_emit(String(id))

func _safe_emit(qid: String) -> void:
	var loop := Engine.get_main_loop()
	if loop == null:
		return
	var root: Node = loop.root
	if root == null:
		return
	var eb: Node = root.get_node_or_null("/root/EventBus")
	if eb != null and eb.has_signal("quest_updated"):
		eb.emit_signal("quest_updated", StringName(qid))

func active_list() -> Array[String]:
	var out: Array[String] = []
	for qid in defs:
		if is_active(StringName(qid)):
			out.append(qid)
	return out

func to_dict() -> Dictionary:
	return states.duplicate()

func from_dict(d: Dictionary) -> void:
	states.assign(d)
