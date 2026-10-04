class_name WorldDef
extends RefCounted
## 单个世界的纯数据定义（阶段 A 地基）。
##
## 一个世界 = 若干阶段（stage）+ 任务 + 结算文案 + 独特机制 id + 主题色。
## scenario.gd 只按这份数据渲染与执行，不再硬编码任何具体世界的内容。
##
## 结构：
## {
##   id, name, genre, rating, theme_color, intro, mechanic,
##   quests: [ {id, kind, name, desc, hint_active, reward_points} ],
##   stages: [ {id, title, tiles:[String], spawn:Vector2i, exit:Vector2i,
##              objective, enemies:[{id,pos}], npcs:{}, spots:{}, transition:{} } ],
##   settlement: { perfect/normal/death: {title, body} }
## }

var id: String = ""
var name: String = ""
var genre: String = ""
var rating: String = "D"
var theme_color: Color = Color(0.6, 0.6, 0.7)
var intro: String = ""
var mechanic: String = ""              # systems/mechanics/<id>.gd，空字符串表示无独特机制
var quests: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var settlement: Dictionary = {}

static func create(d: Dictionary) -> WorldDef:
	var w := WorldDef.new()
	w.id = String(d.get("id", ""))
	w.name = String(d.get("name", ""))
	w.genre = String(d.get("genre", ""))
	w.rating = String(d.get("rating", "D"))
	w.theme_color = d.get("theme_color", Color(0.6, 0.6, 0.7))
	w.intro = String(d.get("intro", ""))
	w.mechanic = String(d.get("mechanic", ""))
	w.quests.assign(d.get("quests", []))
	w.stages.assign(d.get("stages", []))
	w.settlement = d.get("settlement", {})
	return w

func stage_count() -> int:
	return stages.size()

## 取阶段数据；越界返回空字典。
func stage(index: int) -> Dictionary:
	if index < 0 or index >= stages.size():
		return {}
	return stages[index]

func stage_id(index: int) -> String:
	return String(stage(index).get("id", ""))

func quest_ids() -> Array[String]:
	var out: Array[String] = []
	for q in quests:
		out.append(String(q.get("id", "")))
	return out

## 建立该世界首个阶段的地图逻辑层。
func make_grid(stage_index: int = 0) -> GridWorld:
	var g := GridWorld.new()
	var s := stage(stage_index)
	g.setup(s.get("tiles", []))
	return g

## 校验世界定义，返回问题列表（空数组表示合法）。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == "":
		errs.append("世界 id 为空")
	if name == "":
		errs.append("%s：世界名称为空" % id)
	if stages.is_empty():
		errs.append("%s：没有任何阶段" % id)
	if quests.is_empty():
		errs.append("%s：没有任何任务" % id)
	if settlement.is_empty():
		errs.append("%s：缺少结算文案" % id)

	# 任务 id 唯一
	var seen_q := {}
	for q in quests:
		var qid := String(q.get("id", ""))
		if qid == "":
			errs.append("%s：存在无 id 的任务" % id)
		elif seen_q.has(qid):
			errs.append("%s：任务 id 重复 %s" % [id, qid])
		seen_q[qid] = true

	# 阶段：地图合法、出生点/出口可走、敌人/NPC/交互点在地图内且可走
	var seen_s := {}
	for i in stages.size():
		var s: Dictionary = stages[i]
		var sid := String(s.get("id", ""))
		if sid == "":
			errs.append("%s：阶段 %d 缺少 id" % [id, i])
		elif seen_s.has(sid):
			errs.append("%s：阶段 id 重复 %s" % [id, sid])
		seen_s[sid] = true

		var grid := make_grid(i)
		for e in grid.validate():
			errs.append("%s/%s：%s" % [id, sid, e])

		var spawn: Vector2i = s.get("spawn", Vector2i(-1, -1))
		if not grid.is_walkable(spawn):
			errs.append("%s/%s：出生点 %s 不可通行" % [id, sid, str(spawn)])
		if s.has("exit"):
			var ex: Vector2i = s.get("exit")
			if not grid.is_walkable(ex):
				errs.append("%s/%s：出口 %s 不可通行" % [id, sid, str(ex)])
			elif not grid.is_reachable(spawn, ex):
				errs.append("%s/%s：出生点到出口不连通" % [id, sid])

		for e in s.get("enemies", []):
			var p: Vector2i = e.get("pos", Vector2i(-1, -1))
			if not grid.is_walkable(p):
				errs.append("%s/%s：敌人 %s 位置 %s 不可通行" % [id, sid, String(e.get("id", "?")), str(p)])

		var npcs: Dictionary = s.get("npcs", {})
		for nid in npcs:
			var p: Vector2i = npcs[nid].get("pos", Vector2i(-1, -1))
			if not grid.is_walkable(p):
				errs.append("%s/%s：NPC %s 位置 %s 不可通行" % [id, sid, nid, str(p)])

		var spots: Dictionary = s.get("spots", {})
		for sid2 in spots:
			var p: Vector2i = spots[sid2].get("pos", Vector2i(-1, -1))
			if not grid.is_walkable(p):
				errs.append("%s/%s：交互点 %s 位置 %s 不可通行" % [id, sid, sid2, str(p)])

	return errs
