class_name AIDirector extends Node
## 战场 AI 指挥层:定期(4s)分析全局局势 → 给每支小队分配战术任务。
## 任务种类:
##   capture    夺旗:前往占领敌方/中立据点
##   reinforce  支援:敌方据点正在争夺且我方占优 → 集中攻点
##   defend     回防:己方据点正被围攻/争夺 → 优先防守
##   hold       驻守:己方据点已安全 → 留守防守位(部分小队)
##   advance    推进:无争夺任务时 → 向最近的敌方据点推进
## 决策依据:旗归属/争夺状态/旗附近双方人数/小队存活数。
## 防扎堆:同一旗帜同一时刻最多 2 队执行同一类进攻任务,其余队分散。

const TICK := 4.0
var _t := 0.0


func _process(dt: float) -> void:
	if G.mode != "conquest" and G.mode != "breakthrough":
		return
	# 实时 3D 战场部署(征服/突破):玩家死亡观察期间战场指挥持续运转(战局实时推进)
	var battlefield_live: bool = G.deployment != null and G.deployment.active
	if G.state != "playing" and not battlefield_live:
		return
	if G.squads.is_empty():
		return
	_t -= dt
	if _t > 0:
		return
	_t = TICK
	_direct()


## 战场分析 + 任务分配
func _direct() -> void:
	var stats := []
	for f in G.flags:
		if f == null or not is_instance_valid(f) or f.locked == true:
			continue
		var us_n := 0
		var ru_n := 0
		for b in G.bots:
			if not b.alive or b.vehicle != null:
				continue
			var d: float = Utils.dist_2d(b.pos.x, b.pos.z, f.pos.x, f.pos.z)
			if d > 55.0:
				continue
			if b.team == "us":
				us_n += 1
			else:
				ru_n += 1
		var contested: bool = f.contested == true
		stats.append({ "flag": f, "us": us_n, "ru": ru_n, "contested": contested,
			"progress": float(f.progress), "owner": f.owner_team })
	var tasks := {}
	var assigned := {}   # flag_id -> 已分配进攻任务的小队数
	for team in ["us", "ru"]:
		for s in G.squads:
			if s["team"] != team:
				continue
			var alive_n := 0
			for m in s["members"]:
				if m.alive:
					alive_n += 1
			if alive_n == 0:
				continue
			var task := _pick_task(s, team, stats, assigned)
			tasks[s["id"]] = task
			for m in s["members"]:
				if m.alive:
					m.ai_task = task
	G.ai_tasks = tasks


## 单队任务选择:回防 > 支援攻点 > 夺旗 > 推进 > 驻守
func _pick_task(s, team: String, stats: Array, assigned: Dictionary) -> Dictionary:
	var my_flags: Array = []
	var en_flags: Array = []
	for st in stats:
		if st["owner"] == team:
			my_flags.append(st)
		elif st["owner"] != "" and st["owner"] != null:
			en_flags.append(st)
	# 1) 己方旗被围攻(敌方人多 / 被敌方争夺中) → 回防(全队优先)
	var best_def = null
	var best_def_prio := -1.0
	for st in my_flags:
		var en_n: int = st["ru"] if team == "us" else st["us"]
		var own_n: int = st["us"] if team == "us" else st["ru"]
		var prio: float = 0.0
		if st["contested"]:
			prio += 2.0
		if st["progress"] > 0.0:
			prio += 1.5
		if en_n > own_n:
			prio += en_n - own_n
		if prio > best_def_prio:
			best_def_prio = prio
			best_def = st
	if best_def != null and best_def_prio >= 1.0:
		return { "kind": "defend", "flag": best_def["flag"] }
	# 2) 敌方旗正在争夺 → 支援攻点(最多 2 队同旗)
	var best_att = null
	var best_att_prio := -1.0
	for st in en_flags:
		var en_n: int = st["ru"] if team == "us" else st["us"]
		var own_n: int = st["us"] if team == "us" else st["ru"]
		var prio: float = 0.0
		if st["contested"]:
			prio += 2.0
		if own_n > en_n:
			prio += 1.0
		if prio > best_att_prio:
			best_att_prio = prio
			best_att = st
	if best_att != null and best_att_prio >= 1.0 and _assign_ok(best_att, team, assigned, 2):
		_mark(best_att, team, assigned)
		return { "kind": "reinforce", "flag": best_att["flag"] }
	# 3) 无人争夺的非己方旗 → 夺旗(每旗最多 1 队;小队近的优先)
	var best_cap = null
	var best_cap_d := INF
	for st in en_flags:
		if st["contested"]:
			continue
		if not _assign_ok(st, team, assigned, 1):
			continue
		var d: float = Utils.dist_2d(s["members"][0].pos.x, s["members"][0].pos.z, st["flag"].pos.x, st["flag"].pos.z)
		if d < best_cap_d:
			best_cap_d = d
			best_cap = st
	if best_cap != null:
		_mark(best_cap, team, assigned)
		return { "kind": "capture", "flag": best_cap["flag"] }
	# 4) 敌方旗(即使已被其他队分配) → 推进(允许少量重复,2 队上限)
	var best_adv = null
	var best_adv_d := INF
	for st in en_flags:
		if not _assign_ok(st, team, assigned, 2):
			continue
		var d: float = Utils.dist_2d(s["members"][0].pos.x, s["members"][0].pos.z, st["flag"].pos.x, st["flag"].pos.z)
		if d < best_adv_d:
			best_adv_d = d
			best_adv = st
	if best_adv != null:
		_mark(best_adv, team, assigned)
		return { "kind": "advance", "flag": best_adv["flag"] }
	# 5) 兜底:最近的己方旗驻守
	var best_hold = null
	var best_hold_d := INF
	for st in my_flags:
		var d: float = Utils.dist_2d(s["members"][0].pos.x, s["members"][0].pos.z, st["flag"].pos.x, st["flag"].pos.z)
		if d < best_hold_d:
			best_hold_d = d
			best_hold = st
	if best_hold != null:
		return { "kind": "hold", "flag": best_hold["flag"] }
	return { "kind": "hold", "flag": null }


func _assign_ok(st: Dictionary, team: String, assigned: Dictionary, limit: int) -> bool:
	var key: String = str(st["flag"])
	return not assigned.has(key) or int(assigned[key]) < limit


func _mark(st: Dictionary, team: String, assigned: Dictionary) -> void:
	var key: String = str(st["flag"])
	assigned[key] = int(assigned.get(key, 0)) + 1
