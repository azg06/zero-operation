class_name Bot extends Node3D
## AI 士兵(对应 ai.js 的 Bot 类)

const NAMES_US := ["幽灵", "猎鹰", "毒蛇", "雷神", "铁壁", "夜鹰", "风暴", "游侠", "幻影", "战马", "雪豹", "苍狼"]
const NAMES_RU := ["伊万", "熊罴", "红狼", "寒鸦", "钢牙", "夜枭", "黑鲨", "秃鹫", "雪狐", "战熊", "灰狼", "毒蜂"]

static var BOT_ID := 0

var id := 0
var team := "us"
var bot_name := ""
var class_id := "assault"
var weapon_id := "m4"
var def                          # WeaponDef
var mesh: Node3D = null
var hb: Dictionary = {}
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var health := 100.0
var alive := false
var respawn_t := 0.0
var think_t := 0.0
var objective = null             # 目标旗帜
var obj_offset := Vector3.ZERO
var target = null                # 当前敌人(Player/Bot/Vehicle/Aircraft)
var target_visible := false
var last_seen_pos := Vector3.ZERO
var burst_left := 0
var fire_t := 0.0
var react_t := 0.0               # 反应时间
var strafe_dir := 1
var strafe_t := 0.0
var avoid_dir := 0.0
var suppress_t := 0.0            # 被压制
var hb_t := 0.0                  # 血条显示
var death_t := 0.0
var spotted := 0.0               # 被探测标记
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var kills := 0
var deaths := 0
var prone := false
var prone_amt := 0.0
var rig_pitch := 0.0
var can_drive := false
var vehicle = null
var vehicle_goal = null
var drive_stuck := 0.0
var unstuck_t := 0.0
var unstuck_n := 0
var rag = null                   # 布娃娃参数
var squad_id := -1
# ---- 四人小队(战役队友) ----
var follow: Node = null          # 跟随目标(战役为玩家);非战役模式保持 null
var squad_slot := -1             # 编队槽位(0=左后 / 1=右后 / 2=正后)
var downed := false              # 我方队友倒地(hp<=0,可被救治,不触发击杀播报)
var downed_t := 0.0              # 倒地持续时长(超时自动撤离)
var walk_t := 0.0
var last_fired_t := -99.0
var _last_attacker_def = null
var _last_hit_head := false
# ---- 射线错峰缓存(性能:避障/驾驶射线每 3 帧一次) ----
var _avoid_cache := Vector2.ZERO
var _avoid_ok := false
var _drv_hit := false
var _drv_fl := 99.0
var _drv_fr := 99.0
# ---- 兵种职责 ----
var duty_goal = null               # 职责目标点(工程跟车/支援跟随/侦察侧翼)
var heal_ot := 0.0                 # 突击兵自疗剩余时间
var rpg_cd := 0.0                  # 工程兵 RPG 冷却
var smoke_cd := 0.0                # 烟雾弹冷却
var ability_cd := 0.0              # 信标/C5/补给包冷却
var mark_t := 0.0                  # 侦察兵标记计时
# ---- 3A 行为状态机:待命/移动/交火/追击/撤退/占领 ----
var state := "move"
var state_t := 0.0
var flee_until := 0.0              # 撤退结束时间戳
var cover_pos := Vector3.ZERO      # 掩体站点位
var cover_valid := false
var cover_until := 0.0             # 掩体信息有效期
var cover_scan_cd := 0.0           # 掩体扫描节流
var last_attacker = null
var last_attacker_pos := Vector3.ZERO
var hit_t := 0.0
# ---- 人化射击精度 ----
var skill := 0.8                   # 0.45~1.1 技能系数(管理器平衡)
var aim_err := 0.01                # 当前瞄准误差(弧度,受击/新目标跳变后收敛)
var aim_base := 0.01               # 稳定瞄准误差(兵种/武器/技能决定)
var aim_settle := 0.0              # 瞄准稳定时间(收敛用)
var fire_mode := "auto"            # semi 单发 / burst 点射 / auto 连发(距离决定)
var ammo := 30
var reloading := false
var reload_t := 0.0
# ---- 感知系统 ----
var hear_t := 0.0                  # 听到声响的持续计时
var suspect_pos := Vector3.ZERO    # 可疑区域(先观察再开火)
var suspect_t := 0.0
var target_by_hearing := false
var _last_seen_t := -99.0          # 最近一次目击/听觉时间戳
# ---- 小队战术 ----
var overwatch := false             # 覆盖手(机枪/狙:殿后压制掩护队友推进)
var assaulting := false            # 正在集体攻点
var assault_angle := 0.0           # 攻点分配的角度位(围点)
var flank_side := 1                # 侧翼方向
var _assault_flag = null           # 本次围攻的目标旗(变化时重排)
var _buddy_goal := Vector3.ZERO    # 班组推进缓存(think 期计算,避免每帧 O(n))
var _buddy_ok := false
# ---- 姿态 ----
var crouch := false
var crouch_amt := 0.0
# ---- 性能节流 ----
var _far_zone := false             # 附近无战事:低频思考/缩短索敌
var _think_every := 0.14
# ---- 战场噪音静态日志(听觉感知;cap 48 条环形丢弃) ----
static var _noise_log: Array = []
var _crew_pose := ""                # 乘员姿态日志状态:"" / "seat" / "hidden"(仅状态变化时打印)


## 战场噪音广播:队友/敌方开火、爆炸落点写入静态日志,供所有 bot 错峰读取
static func report_noise(x: float, z: float, loud: float, p_team: String, t: float) -> void:
	if _noise_log.size() >= 48:
		_noise_log.remove_at(0)
	_noise_log.append({ "x": x, "z": z, "t": t, "loud": loud, "team": p_team })


func _init(p_team: String) -> void:
	id = BOT_ID
	BOT_ID += 1
	team = p_team
	bot_name = (Utils.choice(NAMES_US) if team == "us" else Utils.choice(NAMES_RU)) + "-" + str(Utils.rand_int(10, 99))
	name = bot_name  # 节点名即士兵名(killfeed 通过 get("name") 读取)
	class_id = Utils.choice(WeaponsData.C().keys())
	# 武器按兵种定位分配(各司其职)
	match class_id:
		"assault":
			weapon_id = Utils.choice(["m4", "ak", "scar", "aug"] if team == "us" else ["ak", "ak", "scar", "aug"])
		"engineer":
			weapon_id = Utils.choice(["m249", "pkm", "rpd"] if team == "us" else ["pkm", "rpd", "rpd"])
		"support":
			weapon_id = Utils.choice(["mp5", "ump", "p90"])
		"recon":
			weapon_id = Utils.choice(["awm", "m24", "m24"] if team == "us" else ["svd", "svd", "m24"])
		_:
			weapon_id = "m4"
	def = WeaponsData.W()[weapon_id]
	mesh = SoldierModel.build_soldier(team, weapon_id, class_id)
	hb = SoldierModel.make_health_bar()
	mesh.add_child(hb["sprite"])
	add_child(mesh)
	think_t = (id % 9) * 0.016 + Utils.rand(0, 0.03)  # 错峰首 tick


func spawn(p_pos: Vector3) -> void:
	_release_vehicle()
	pos = p_pos
	pos.x += Utils.rand(-2, 2)
	pos.z += Utils.rand(-2, 2)
	pos = Utils.move_collide(pos, 0.38, 1.75)
	health = 100
	alive = true
	downed = false
	downed_t = 0
	target = null
	burst_left = 0
	spotted = 0
	prone = false
	prone_amt = 0
	# ---- 3A 状态重置 ----
	state = "move"
	state_t = 0
	flee_until = 0
	cover_valid = false
	last_attacker = null
	last_attacker_pos = pos
	hear_t = 0
	suspect_t = 0
	suspect_pos = Vector3.ZERO
	target_by_hearing = false
	_last_seen_t = -99.0
	assaulting = false
	overwatch = false
	crouch = false
	crouch_amt = 0
	ammo = def.mag
	reloading = false
	reload_t = 0
	suppress_t = 0
	_set_aim_base()  # 按当前技能系数重置瞄准误差基线
	mesh.visible = true
	var leg_l: Node3D = mesh.get_meta("leg_l")
	var leg_r: Node3D = mesh.get_meta("leg_r")
	if leg_l != null:
		leg_l.visible = true
		leg_r.visible = true
	mesh.rotation = Vector3.ZERO
	mesh.position = pos
	# 重生恢复手中枪显示(死亡时隐藏并掉落)
	var rig_s: Node3D = mesh.get_meta("rig")
	if rig_s != null:
		var wg := rig_s.get_node_or_null("Weapon_" + weapon_id)
		if wg != null:
			wg.visible = true
	pick_objective(true)


func die(attacker) -> void:
	alive = false
	deaths += 1
	death_t = 0
	(hb["sprite"] as Sprite3D).visible = false
	# 乘员死亡载具受损失控:死亡瞬间仍持有载具 → 车损 25%(残车保留,可被接管)
	# 若载具已毁(殉爆场景 v.dead)则不重复扣损
	var v_crew = vehicle
	if v_crew != null and not v_crew.dead:
		v_crew.hp = maxf(1, v_crew.hp - v_crew.def["hp"] * 0.25)
		print("[CREW] bot=%d 乘员死亡载具受损失控 type=%s hp=%.0f" % [id, v_crew.type, v_crew.hp])
	_release_vehicle()
	# 布娃娃激活时掉落手中武器,尸体手中枪隐藏
	G.effects.spawn_dropped_weapon(weapon_id, pos + Vector3(0, 1.1, 0))
	var rig_d: Node3D = mesh.get_meta("rig")
	if rig_d != null:
		var wg := rig_d.get_node_or_null("Weapon_" + weapon_id)
		if wg != null:
			wg.visible = false
	# ---- 布娃娃:沿受力方向倒下,四肢随机甩动 ----
	var ax := 0.0
	var az := -1.0
	if attacker != null and attacker.get("pos") != null:
		var apos: Vector3 = attacker.get("pos")
		ax = pos.x - apos.x
		az = pos.z - apos.z
		var l: float = maxf(Vector2(ax, az).length(), 0.001)
		ax /= l
		az /= l
	var ca := cos(yaw)
	var sa := sin(yaw)
	var lx: float = ax * ca - az * sa
	var lz: float = ax * sa + az * ca
	rag = {
		"rx": clampf(lz * 1.55, -1.7, 1.7),
		"rz": clampf(-lx * 1.55, -1.7, 1.7),
		"f1": Utils.rand(7, 11), "f2": Utils.rand(7, 11), "f3": Utils.rand(6, 10), "f4": Utils.rand(6, 10),
		"a1": Utils.rand(0.5, 1.0), "a2": Utils.rand(0.5, 1.0), "a3": Utils.rand(0.3, 0.8), "a4": Utils.rand(0.4, 0.9),
		"p1": Utils.rand(6.3), "p2": Utils.rand(6.3), "p3": Utils.rand(6.3), "p4": Utils.rand(6.3),
	}
	G.game.on_kill(attacker, self, _last_attacker_def, _last_hit_head)


## ==================== 四人小队(战役队友) ====================
## 是否处于编队跟随(同队且带 follow;非战役模式 follow=null → 恒 false)
func _is_following() -> bool:
	return follow != null and is_instance_valid(follow) and follow.team == team


## 编队槽位偏移(玩家局部坐标:x=右, z=前):左后 / 右后 / 正后
func formation_offset() -> Vector2:
	match squad_slot:
		0:
			return Vector2(-2.4, 5.2)
		1:
			return Vector2(2.4, 5.2)
		_:
			return Vector2(0.0, 6.5)


## 编队目标位(世界坐标):按跟随者朝向展开,含碰撞推挤与地形贴合
func formation_pos() -> Vector3:
	var f = follow
	if f == null or not is_instance_valid(f):
		return pos
	var o := formation_offset()
	var fyaw: float = f.yaw
	var ca := cos(fyaw)
	var sa := sin(fyaw)
	var right := Vector3(ca, 0, -sa)
	var fwd := Vector3(-sa, 0, -ca)
	var fp := Vector3(f.pos.x + right.x * o.x + fwd.x * o.y, f.pos.y, f.pos.z + right.z * o.x + fwd.z * o.y)
	if G.ground_h.is_valid():
		fp.y = G.ground_h.call(fp.x, fp.z)
	fp = Utils.move_collide(fp, 0.38, 1.75)
	return fp


## 我方队友倒地:停止行为、平躺姿态;不触发击杀播报/不掉枪(可被玩家救治)
func _go_down(attacker) -> void:
	alive = false
	downed = true
	downed_t = 0
	death_t = 0
	target = null
	target_visible = false
	suppress_t = 0
	flee_until = 0
	cover_valid = false
	last_attacker = attacker
	last_attacker_pos = attacker.get("pos") if (attacker != null and attacker.get("pos") != null) else pos
	(hb["sprite"] as Sprite3D).visible = false
	_release_vehicle()
	# 手中枪收起(尸体不掉落武器)
	var rig_d: Node3D = mesh.get_meta("rig")
	if rig_d != null:
		var wg := rig_d.get_node_or_null("Weapon_" + weapon_id)
		if wg != null:
			wg.visible = false


## 玩家救治复活:回血起身、武器归位、恢复编队
func revive(p_pos: Vector3) -> void:
	pos = Utils.move_collide(p_pos, 0.38, 1.75)
	if G.ground_h.is_valid():
		pos.y = G.ground_h.call(pos.x, pos.z)
	health = 100
	alive = true
	downed = false
	downed_t = 0
	death_t = 0
	state = "move"
	state_t = 0
	flee_until = 0
	cover_valid = false
	last_attacker = null
	suppress_t = 0
	crouch = false
	crouch_amt = 0
	prone = false
	prone_amt = 0
	ammo = def.mag
	reloading = false
	reload_t = 0
	mesh.rotation_order = EULER_ORDER_YXZ
	mesh.rotation = Vector3.ZERO
	mesh.position = pos
	mesh.visible = true
	var leg_l: Node3D = mesh.get_meta("leg_l")
	var leg_r: Node3D = mesh.get_meta("leg_r")
	if leg_l != null:
		leg_l.visible = true
		leg_r.visible = true
	var rig_s: Node3D = mesh.get_meta("rig")
	if rig_s != null:
		var wg := rig_s.get_node_or_null("Weapon_" + weapon_id)
		if wg != null:
			wg.visible = true
	update_health_bar()
	(hb["sprite"] as Sprite3D).visible = true
	pick_objective(true)


func _release_vehicle() -> void:
	if vehicle != null:
		if vehicle.driver == self:
			vehicle.driver = null
		vehicle.ai_input = null
		vehicle = null
	vehicle_goal = null
	drive_stuck = 0
	_crew_pose = ""


func take_damage(amount: float, attacker, head: bool, from_def) -> void:
	if not alive:
		return
	health -= amount
	_last_attacker_def = from_def
	_last_hit_head = head
	# 压制:被击中后压制加深(抑制还击,驱赶向掩体)
	suppress_t = maxf(suppress_t, 1.0 + Utils.rand(0.2, 0.7))
	hit_t = 1.0
	hb_t = 4
	update_health_bar()
	# 受击反应:记住火力来源,受击瞬间丢失准星
	# (有效攻击者:存活 Bot/玩家,或空中载具 Dictionary 飞行员 — 无 alive 字段)
	if attacker != null and attacker.get("pos") != null \
			and (attacker.get("alive") == true or attacker.get("air") == true):
		target = attacker
		last_seen_pos = attacker.get("pos")
		last_attacker = attacker
		last_attacker_pos = attacker.get("pos")
		_last_seen_t = G.time
		target_visible = Utils.los_clear(eye_pos(), attacker.get("pos") + Vector3(0, 1.3, 0))
		aim_err = minf(aim_err * 2.6 + 0.025, 0.11)  # 受击丢准星
		aim_settle = 0
		react_t = minf(react_t, 0.3)
		# 战术撤退:未处于掩体且未被压得动弹不得 → 立刻找掩体
		if not _in_cover() and state != "flee":
			_enter_flee(Utils.rand(1.0, 1.8))
	elif attacker != null and attacker.get("pos") != null:
		last_attacker_pos = attacker.get("pos")
	# 爆炸巨响:广播到战场噪音(听觉感知),爆炸伤害同样压制
	if from_def is Dictionary and from_def.get("name") == "爆炸物":
		var nx := pos.x
		var nz := pos.z
		if attacker != null and attacker.get("pos") != null:
			var ap: Vector3 = attacker.get("pos")
			nx = ap.x
			nz = ap.z
		Bot.report_noise(nx, nz, 2.5, "neutral", G.time)
		if attacker != null and attacker.get("alive") != true and target == null:
			suspect_pos = Vector3(nx, 0, nz)
			suspect_t = maxf(suspect_t, 1.2)
			_last_seen_t = G.time
	if health <= 0:
		health = 0
		# 我方小队队友:hp<=0 → 倒地(可救治),不走死亡流程(不播报/不掉枪/不重生)
		if follow != null and follow.team == team:
			_go_down(attacker)
		else:
			die(attacker)


func update_health_bar() -> void:
	SoldierModel.update_health_bar(hb, health, team)


func pick_objective(force := false) -> void:
	# 编队跟随:不参与旗帜目标(战役队友只跟玩家+交火)
	if _is_following():
		objective = null
		return
	if not force and objective != null and randf() < 0.7:
		return
	# ---- 小队协同:45% 跟随小队成员的目标 ----
	if squad_id >= 0 and randf() < 0.45:
		var sq = null
		for s in G.squads:
			if s["id"] == squad_id:
				sq = s
				break
		if sq != null:
			var mates := []
			for m in sq["members"]:
				if m != self and m.alive and m.objective != null:
					if G.mode != "breakthrough" or G.bt == null or m.objective.sector == G.bt["sector"]:
						mates.append(m)
			if not mates.is_empty():
				var mate_obj: Flag = (Utils.choice(mates) as Bot).objective
				objective = mate_obj
				var m_a := Utils.rand(TAU)
				var m_r := Utils.rand(0, mate_obj.radius * 0.8)
				obj_offset = Vector3(cos(m_a) * m_r, 0, sin(m_a) * m_r)
				return
	# ---- 突破模式 ----
	if G.mode == "breakthrough" and G.bt != null:
		var sec_flags := []
		for f in G.flags:
			if f.sector == G.bt["sector"]:
				sec_flags.append(f)
		if sec_flags.is_empty():
			return
		var bt_obj = null
		if team == "us":
			var pool2 := []
			for f in sec_flags:
				if f.owner_team != "us":
					pool2.append(f)
			bt_obj = Utils.choice(pool2) if not pool2.is_empty() else Utils.choice(sec_flags)
		else:
			var pool3 := []
			for f in sec_flags:
				if f.owner_team != "ru":
					pool3.append(f)
			if not pool3.is_empty() and randf() < 0.65:
				bt_obj = Utils.choice(pool3)
			else:
				var best_d := INF
				for f in sec_flags:
					var d := Utils.dist_2d(pos.x, pos.z, f.pos.x, f.pos.z) + Utils.rand(0, 30)
					if d < best_d:
						best_d = d
						bt_obj = f
		objective = bt_obj
		var bt_a := Utils.rand(TAU)
		var bt_r := Utils.rand(0, bt_obj.radius * 0.7) if team == "us" else Utils.rand(3, bt_obj.radius + 9)
		obj_offset = Vector3(cos(bt_a) * bt_r, 0, sin(bt_a) * bt_r)
		return
	# 优先:非己方旗帜;35% 概率随机选旗
	var candidates := []
	for f in G.flags:
		if f.owner_team != team:
			candidates.append(f)
	var pool := candidates if not candidates.is_empty() else G.flags
	var best = null
	if randf() < 0.35:
		best = Utils.choice(pool)
	else:
		var best_d := INF
		for f in pool:
			var d := Utils.dist_2d(pos.x, pos.z, f.pos.x, f.pos.z) + Utils.rand(0, 40)
			if d < best_d:
				best_d = d
				best = f
	objective = best
	var a := Utils.rand(TAU)
	var r := Utils.rand(0, best.radius * 0.7)
	obj_offset = Vector3(cos(a) * r, 0, sin(a) * r)


## 寻找可见敌人(含敌方有人载具)
## reacq:追踪中重获目标 → 放宽视锥(侧身走位时仍能跟住);初始索敌严格视锥(约 77°)
func acquire_target(reacq := false):
	var best = null
	var best_d := 75.0 if not _far_zone else 55.0  # 索敌半径(战事稀疏区减半)
	var best_score := -1e9
	# 被压制:感知退化(视锥收窄、距离变短),这正是压制战术的收益
	var fov_half := 1.35 if suppress_t <= 0.9 else 1.0
	if reacq:
		fov_half = 1.9
	var eye := eye_pos()
	for b in G.bots:
		if not b.alive or b.team == team or b.vehicle != null:
			continue
		var d: float = pos.distance_to(b.pos)
		if d < best_d:
			# 视锥检测:近距周边视觉豁免,远处必须在前方视锥内
			if d > 9.0 and not _in_fov(b.pos, fov_half):
				continue
			var target_pos = b.pos + Vector3(0, 1.4, 0)
			if Utils.los_clear(eye, target_pos):
				if class_id == "recon":
					# 击杀优先级:侦察 4 > 支援 3 > 突击 2 > 工程 1
					var pri: int = { "recon": 4, "support": 3, "assault": 2, "engineer": 1 }.get(b.class_id, 2)
					var score: float = pri * 50.0 - d
					if score > best_score:
						best_score = score
						best = b
						best_d = d
				else:
					best = b
					best_d = d
	if G.player != null and G.player.alive and G.player.vehicle == null and G.player.team != team:
		var d2: float = pos.distance_to(G.player.pos)
		if d2 < best_d and (d2 <= 9.0 or _in_fov(G.player.pos, fov_half)):
			if Utils.los_clear(eye, G.player.pos + Vector3(0, 1.4, 0)):
				best = G.player
				best_d = d2
	# 敌方有人载具(威胁大,更远距离也会优先接战;体积大,视锥放宽)
	for v in G.vehicles:
		if v.dead or v.driver == null or v.driver.team == team:
			continue
		var d3: float = pos.distance_to(v.pos)
		if d3 < best_d + 30:
			if d3 <= 15.0 or _in_fov(v.pos, fov_half + 0.3):
				if Utils.los_clear(pos + Vector3(0, 1.5, 0), v.pos + Vector3(0, 1.2, 0)):
					best = v
					best_d = d3
	# 敌方空中载具
	for a in G.aircraft:
		if a.dead or a.team == team:
			continue
		var d4: float = pos.distance_to(a.pos)
		if d4 < best_d + 45:
			if Utils.los_clear(pos + Vector3(0, 1.5, 0), a.pos):
				best = a
				best_d = d4
	return best


func eye_pos() -> Vector3:
	var h := 1.5
	if prone:
		h = 0.5
	elif crouch:
		h = 0.95
	return pos + Vector3(0, h, 0)


## 视锥判断:目标世界角与当前朝向的夹角
func _in_fov(p: Vector3, fov_half: float) -> bool:
	var ang := atan2(-(p.x - pos.x), -(p.z - pos.z))
	var dy := ang - yaw
	while dy > PI:
		dy -= TAU
	while dy < -PI:
		dy += TAU
	return absf(dy) < fov_half


## ==================== 听觉感知(战场噪音) ====================
func _hear_battlefield() -> void:
	hear_t = maxf(0, hear_t - _think_every)
	# 0) 清理残留:换图后旧地图噪音坐标已失效,超出当前地图范围直接丢弃
	var lim := G.bounds + 300.0
	if lim > 0.0:
		for i in range(Bot._noise_log.size() - 1, -1, -1):
			var nn = Bot._noise_log[i]
			if absf(nn.x) > lim or absf(nn.z) > lim:
				Bot._noise_log.remove_at(i)
	# 1) 静态噪音日志:任何 bot 开火 / 爆炸(距离衰减)
	for n in Bot._noise_log:
		if n.team == team:
			continue
		var d := Utils.dist_2d(pos.x, pos.z, n.x, n.z)
		if d < 55.0 * n.loud and G.time - n.t < 0.6:
			_heard_signal(n.x, n.z, n.loud)
	# 2) 玩家枪口(最近射击时间窗内 → 正在开火;全自动 rpm 下 fire_timer≈0.067~0.1,不可用固定阈值)
	var p = G.player
	if p != null and p.alive and p.team != team and p.vehicle == null:
		var g = p.gun()
		if g != null and G.time - g.last_shot_t < 0.6:
			_heard_signal(p.pos.x, p.pos.z, 1.0)


## 听到声响:记录可疑位置(带定位误差),先观察后行动,不做透视锁敌
func _heard_signal(x: float, z: float, loud: float) -> void:
	hear_t = 1.2
	var err_m := 2.0 + loud * 2.0
	var hx := x + Utils.rand(-err_m, err_m)
	var hz := z + Utils.rand(-err_m, err_m)
	last_seen_pos = Vector3(hx, 0, hz)
	_last_seen_t = G.time
	suspect_pos = last_seen_pos
	if target == null:
		suspect_t = maxf(suspect_t, 0.7)
	target_by_hearing = true


## ==================== 掩体战术 ====================
func _in_cover() -> bool:
	return cover_valid and pos.distance_to(cover_pos) < 1.8


## 受击/换弹/被压制时进入撤退:逃向最近掩体,掩体后蹲伏
func _enter_flee(dur: float) -> void:
	state = "flee"
	state_t = 0
	flee_until = G.time + dur
	if cover_scan_cd <= 0:
		_find_cover()
		cover_scan_cd = 0.6


## 找掩体:优先沿攻击方向射线找静态碰撞盒/可破坏物(油桶木箱),兜底扫描近处碰撞盒
func _find_cover() -> void:
	cover_valid = false
	var threat := last_attacker_pos
	var att_alive: bool = last_attacker != null and (last_attacker.get("alive") == true or last_attacker.get("air") == true)
	if not att_alive:
		if suspect_t > 0:
			threat = suspect_pos
		elif objective != null:
			threat = objective.pos
		else:
			threat = pos + Vector3(12, 0, 0)
	var d_t := pos.distance_to(threat)
	if d_t < 3.0:
		return
	var eye := eye_pos()
	var dir := Utils.safe_norm(threat - eye, Vector3.FORWARD)
	# 1) 可破坏物掩体(油桶/木箱/棚屋)
	for ds in G.destructibles:
		if ds.dead:
			continue
		var dp: Vector3 = ds.pos
		var dr: float = ds.radius
		var hd := Utils.ray_sphere(eye, dir, dp, dr + 0.3, d_t - 0.5)
		if hd >= 0:
			var away := Utils.safe_norm(pos - dp, Vector3.BACK)
			var cand2: Vector3 = dp + away * (dr + 1.4)
			cand2.y = G.ground_h.call(cand2.x, cand2.z) if G.ground_h.is_valid() else eye.y
			cand2 = Utils.move_collide(cand2, 0.38, 1.75)
			var dc := Utils.dist_2d(pos.x, pos.z, cand2.x, cand2.z)
			if dc > 2.0 and dc < 16.0 and not Utils.los_clear(threat + Vector3(0, 1.2, 0), cand2 + Vector3(0, 1.2, 0)):
				cover_pos = cand2
				cover_valid = true
				cover_until = G.time + 4.0
				return
	# 2) 静态碰撞盒:站在命中面旁,与攻击者隔墙
	var hit = Utils.raycast_world(eye, dir, d_t - 0.5)
	if hit is Dictionary:
		var n: Vector3 = hit["normal"]
		var cand := (hit["point"] as Vector3) + n * 1.35
		cand.y = G.ground_h.call(cand.x, cand.z) if G.ground_h.is_valid() else eye.y
		cand = Utils.move_collide(cand, 0.38, 1.75)
		var d_c := Utils.dist_2d(pos.x, pos.z, cand.x, cand.z)
		if d_c > 2.0 and d_c < 18.0:
			if not Utils.los_clear(threat + Vector3(0, 1.3, 0), cand + Vector3(0, 1.3, 0)):
				cover_pos = cand
				cover_valid = true
				cover_until = G.time + 4.0
				return
	# 3) 兜底:扫描近处位于"我与威胁之间"的碰撞盒,站其我侧
	var best_v: Variant = null
	var best_score2 := 1e9
	for i in G.colliders.size():
		var b: AABB = G.colliders[i]
		var c: Vector3 = b.get_center()
		var dc2 := Utils.dist_2d(pos.x, pos.z, c.x, c.z)
		if dc2 > 20.0:
			continue
		var to_t := Vector3(threat.x - pos.x, 0, threat.z - pos.z)
		var to_c := Vector3(c.x - pos.x, 0, c.z - pos.z)
		var dt2 := to_t.length()
		if dt2 < 1e-4:
			continue
		if to_c.dot(to_t) / dt2 < 0.0:
			continue
		var away2 := Utils.safe_norm(Vector3(pos.x - threat.x, 0, pos.z - threat.z), Vector3.BACK)
		var cand3 := c + away2 * 1.5
		cand3.y = G.ground_h.call(cand3.x, cand3.z) if G.ground_h.is_valid() else pos.y
		var d_c3 := Utils.dist_2d(pos.x, pos.z, cand3.x, cand3.z)
		if d_c3 > 1.5 and d_c3 < 16.0:
			if not Utils.los_clear(cand3 + Vector3(0, 1.0, 0), threat + Vector3(0, 1.3, 0)):
				var score := d_c3 * 1.2 + dc2 * 0.1
				if score < best_score2:
					best_score2 = score
					best_v = cand3
	if best_v != null:
		cover_pos = best_v
		cover_valid = true
		cover_until = G.time + 4.0


## ==================== 射击模式与换弹 ====================
## 距离决定射击模式:近→连发,中→点射,远→单发;狙击永远单发,机枪永远连发(压制)
func _choose_fire_mode() -> void:
	var d := pos.distance_to(last_seen_pos)
	match def.kind:
		"sniper":
			fire_mode = "semi"
		"lmg":
			fire_mode = "auto"
		"smg":
			fire_mode = "auto" if d < 15 else "burst"
		_:
			fire_mode = "auto" if d < 14 else ("burst" if d < 28 else "semi")


func _next_burst() -> int:
	match fire_mode:
		"semi":
			return 1
		"burst":
			return Utils.rand_int(2, 4)
		_:
			return Utils.rand_int(8, 13) if def.kind == "lmg" else Utils.rand_int(4, 7)


func _next_pause() -> float:
	match fire_mode:
		"semi":
			return Utils.rand(1.2, 2.2) if def.kind == "sniper" else Utils.rand(0.45, 0.8)
		"burst":
			return Utils.rand(0.35, 0.7)
		_:
			return Utils.rand(0.25, 0.5) if def.kind == "lmg" else Utils.rand(0.3, 0.65)


func _start_reload() -> void:
	if reloading or ammo >= def.mag:
		return
	reloading = true
	reload_t = def.reload_time
	burst_left = 0
	# 换弹找掩护:目标可见且未在掩体 → 退入掩体再换
	if target != null and target_visible and not _in_cover() and state != "flee":
		_enter_flee(1.0)


## 兵种/武器决定稳定瞄准误差基数(技能越高越稳)
func _set_aim_base() -> void:
	match def.kind:
		"sniper":
			aim_base = 0.004 + (1.0 - skill) * 0.006
		"lmg":
			aim_base = 0.012 + (1.0 - skill) * 0.01
		"smg":
			aim_base = 0.014 + (1.0 - skill) * 0.012
		"shotgun":
			aim_base = 0.02 + (1.0 - skill) * 0.01
		_:
			aim_base = 0.009 + (1.0 - skill) * 0.011
	aim_err = aim_base
	aim_settle = 0


## ==================== 小队战术(班组协同) ====================
func _my_squad() -> Variant:
	for s in G.squads:
		if s["id"] == squad_id:
			return s
	return null


## 攻点计划:围点分配角度位 + 侧翼方向;机枪/狙殿后压制
func _set_assault_plan(f) -> void:
	_assault_flag = f
	var sq: Variant = _my_squad()
	var idx := 0
	var alive_n := 1
	if sq != null:
		alive_n = 0
		var mem: Array = sq["members"]
		for m in mem:
			if m.alive:
				alive_n += 1
		for i in mem.size():
			if is_same(mem[i], self):
				idx = i
	assault_angle = TAU * (idx % maxi(alive_n, 1)) / maxi(alive_n, 1) + Utils.rand(-0.45, 0.45)
	flank_side = 1 if idx % 2 == 0 else -1


## 占点节奏:对敌方据点且小队≥2人时,全体集中进攻;确定一名覆盖手殿后压制
func _assault_tick() -> void:
	assaulting = false
	overwatch = false
	if objective == null:
		_assault_flag = null
		return
	var f = objective
	var owner_team_id = f.get("owner_team")
	var enemy_held: bool = owner_team_id != null and owner_team_id != "" and owner_team_id != team
	var d_obj := Utils.dist_2d(pos.x, pos.z, f.pos.x, f.pos.z)
	if not enemy_held or d_obj > 70:
		_assault_flag = null
		return
	var sq: Variant = _my_squad()
	if sq == null:
		# 无小队(动态补员):照常攻点但不搞配合
		assaulting = true
		if not Utils.same_actor(f, _assault_flag):
			_set_assault_plan(f)
		return
	var mem2: Array = sq["members"]
	var alive_n := 0
	for m in mem2:
		if m.alive:
			alive_n += 1
	if alive_n < 2:
		return  # 小队不满员:各自为战
	assaulting = true
	# 覆盖手:小队中第一把机枪(工程)或狙(侦察);没有则最后一员殿后
	var ow = null
	for m in mem2:
		if m.alive and m.class_id in ["engineer", "recon"]:
			ow = m
			break
	if ow == null:
		for m in mem2:
			if m.alive:
				ow = m
	overwatch = is_same(ow, self)
	if not Utils.same_actor(f, _assault_flag):
		_set_assault_plan(f)


## 状态机决策(think 期执行):撤退 > 交火 > 编队跟随 > 追击 > 攻点 > 移动 > 待命
func _think_state() -> void:
	state_t += _think_every
	# 编队跟随:不参与占点/职责/登车(专注跟随+交火)
	if _is_following():
		assaulting = false
		overwatch = false
		duty_goal = null
		vehicle_goal = null
	# 掩体信息过期清理
	if cover_valid and G.time > cover_until:
		cover_valid = false
	# 撤退结束
	if state == "flee" and G.time >= flee_until:
		if target != null and target_visible:
			state = "engage"
		elif _is_following():
			state = "follow"
		elif _has_lead():
			state = "chase"
		else:
			state = "move"
	# 目标完全丢失(目视超时且无声音线索)
	if target != null and not target_visible and hear_t <= 0 and G.time - _last_seen_t > 3.5:
		target = null
		target_by_hearing = false
		aim_settle = 0
	# 状态选择
	if state == "flee" and G.time < flee_until:
		pass
	elif target != null and target_visible:
		state = "engage"
	elif _is_following():
		state = "follow"
	elif _has_lead():
		state = "chase"
	elif assaulting:
		state = "assault"
	elif vehicle_goal != null or duty_goal != null or objective != null:
		state = "move"
	else:
		state = "idle"
	# 掩体后蹲伏:受压制/换弹/近距交火
	_decide_crouch()


func _has_lead() -> bool:
	return hear_t > 0 or G.time - _last_seen_t < 3.5


## 蹲伏决策(掩体后蹲、换弹蹲)
func _decide_crouch() -> void:
	var want := false
	if prone:
		want = false
	elif reloading and target != null and target_visible:
		want = true
	elif _in_cover() and (suppress_t > 0 or (target != null and target_visible and pos.distance_to(last_seen_pos) < 30)):
		want = true
	crouch = want


## 性能节流:战事稀疏区 → 低频思考+短索敌;人多 → 整体降频(错峰 tick)
func _update_perf_lod() -> void:
	_far_zone = true
	for b in G.bots:
		if b.alive and b.team != team and b.pos.distance_to(pos) < 70:
			_far_zone = false
			break
	if _far_zone and G.player != null and G.player.alive and G.player.team != team \
			and G.player.pos.distance_to(pos) < 70:
		_far_zone = false
	var n := G.bots.size()
	_think_every = 0.26 if _far_zone else (0.18 if n > 26 else 0.14)


## 班组推进缓存:向 8m 外最近队友适度靠拢(think 期算一次,避免每帧 O(n))
func _compute_buddy() -> void:
	_buddy_ok = false
	var buddy = null
	var bd := 30.0
	for b in G.bots:
		if b == self or not b.alive or b.team != team or b.vehicle != null:
			continue
		var d3: float = b.pos.distance_to(pos)
		if d3 < bd and d3 > 8:
			buddy = b
			bd = d3
	if buddy != null:
		_buddy_goal = buddy.pos
		_buddy_ok = true


## 趴下决策
func _decide_prone() -> void:
	if target == null:
		prone = false
		return
	var d := Utils.dist_2d(pos.x, pos.z, last_seen_pos.x, last_seen_pos.z)
	if d < 10:
		prone = false
		return
	if def.kind == "sniper" and d > 35:
		prone = true
		return
	if suppress_t > 0.6 and d > 18:
		prone = true
		return
	if G.mode == "breakthrough" and team == "ru" and objective != null \
			and Utils.dist_2d(pos.x, pos.z, objective.pos.x, objective.pos.z) < 18 and d > 16:
		prone = true
		return
	prone = false


## ---------- 驾驶载具 ----------
func _exit_vehicle() -> void:
	var v = vehicle
	_release_vehicle()
	state = "move"
	cover_valid = false
	mesh.visible = true
	var leg_l: Node3D = mesh.get_meta("leg_l")
	var leg_r: Node3D = mesh.get_meta("leg_r")
	if leg_l != null:
		leg_l.visible = true
		leg_r.visible = true
	if v != null:
		pos = Vector3(v.pos.x + 2.4, v.pos.y, v.pos.z)
		pos = Utils.move_collide(pos, 0.38, 1.75)


## 驾驶兜底目标:objective 为空(如战役队友 follow 模式不参与占点)时,
## 选择合理去向避免向心空驶(地图中心 Vector3.ZERO 常为敌方基地):
## 1) 编队跟随(战役队友):跟随玩家当前位置;
## 2) 否则取最近己方/中立据点(突破模式限当前区域,不去敌方据点送);
## 3) 无据点可去:以载具当前位置为圆心小半径绕行巡逻(方位随 id+时间缓变,错峰且无循环)
func _drive_fallback_goal(v) -> Vector3:
	if _is_following():
		return Vector3(follow.pos.x, 0, follow.pos.z)
	var best: Flag = null
	var best_d := INF
	for f in G.flags:
		if not is_instance_valid(f):
			continue
		if G.mode == "breakthrough" and G.bt != null and f.sector != G.bt["sector"]:
			continue
		if f.owner_team != null and f.owner_team != team:
			continue  # 敌方据点:不兜底过去送
		var d := Utils.dist_2d(v.pos.x, v.pos.z, f.pos.x, f.pos.z)
		if d < best_d:
			best_d = d
			best = f
	if best != null:
		return Vector3(best.pos.x, 0, best.pos.z)
	# 无据点:绕当前位置小半径巡逻(方位随时间缓变,不构成脚本循环)
	var a := G.time * 0.25 + float(id) * 1.7
	return Vector3(v.pos.x + cos(a) * 22.0, 0, v.pos.z + sin(a) * 22.0)


func _drive(dt: float) -> void:
	var v = vehicle
	if v == null or v.dead or v.driver != self:
		_release_vehicle()
		mesh.visible = true
		return
	pos = v.pos
	think_t -= dt
	spotted = maxf(0, spotted - dt)
	hb_t -= dt
	if hb_t <= 0:
		(hb["sprite"] as Sprite3D).visible = false
	# 车长索敌
	if think_t <= 0:
		think_t = 0.18
		var seen = acquire_target(true)  # 驾驶:视锥放宽(车长观察四周)
		if seen != null:
			target = seen
			last_seen_pos = seen.pos
		elif target != null and randf() < 0.3:
			target = null
		if target == null:
			pick_objective()
	# 驶向目标点:objective 为空/失效时用兜底目标(见 _drive_fallback_goal),
	# 绝不放空驶向地图中心(Vector3.ZERO 直指敌方基地方向)
	var goal: Vector3
	if objective != null and is_instance_valid(objective):
		goal = Vector3(objective.pos.x, 0, objective.pos.z)
	else:
		goal = _drive_fallback_goal(v)
	var dx = goal.x - v.pos.x
	var dz = goal.z - v.pos.z
	var dist := Vector2(dx, dz).length()
	# 吉普车:抵达目标附近下车步战
	if v.type == "jeep" and dist < 15:
		_exit_vehicle()
		return
	var desired_yaw := atan2(-dx, -dz)
	var dy = desired_yaw - v.yaw
	while dy > PI:
		dy -= TAU
	while dy < -PI:
		dy += TAU
	var fwd := -0.55 if absf(dy) > 2.2 else (1.0 if dist > 10 else 0.1)
	var steer := clampf(dy * 1.6, -1, 1)
	# 前方避障(主射线 + 双侧须,错峰每 3 帧探测一次,中间帧用缓存)
	var dir := Vector3(-sin(v.yaw), 0, -cos(v.yaw))
	if (Engine.get_process_frames() + id * 7) % 3 == 0:
		var origin := Vector3(v.pos.x, v.pos.y + 1.0, v.pos.z)
		var look := 8 + absf(v.speed) * 0.7
		_drv_hit = Utils.raycast_world(origin, dir, look) != null
		_drv_fl = 99.0
		_drv_fr = 99.0
		for sgn_v in [1.0, -1.0]:
			var a = sgn_v * 0.55
			var ca := cos(a)
			var sa := sin(a)
			var nx: float = dir.x * ca - dir.z * sa
			var nz: float = dir.x * sa + dir.z * ca
			var h = Utils.raycast_world(origin, Vector3(nx, 0, nz), look * 0.7)
			if sgn_v > 0:
				_drv_fl = h["dist"] if h != null else 99.0
			else:
				_drv_fr = h["dist"] if h != null else 99.0
	var hit_f := _drv_hit
	var free_l := _drv_fl
	var free_r := _drv_fr
	if hit_f:
		steer = 1.0 if free_l > free_r else -1.0
		if absf(dy) < 1.2:
			fwd = minf(fwd, 0.35)
	else:
		if free_l < 4 and free_r > 6:
			steer -= 0.4
		elif free_r < 4 and free_l > 6:
			steer += 0.4
	# 车队间距:前方有车则减速并侧绕
	for ov in G.vehicles:
		if ov == v or ov.dead:
			continue
		var odx = ov.pos.x - v.pos.x
		var odz = ov.pos.z - v.pos.z
		var od := Vector2(odx, odz).length()
		if od < 11 and (odx * dir.x + odz * dir.z) > 0:
			if fwd > 0.2:
				fwd = minf(fwd, 0.15)
			steer += -0.35 if (dir.x * odz - dir.z * odx) > 0 else 0.35
			break
	# 炮塔瞄准与开火
	var turret_yaw: float = v.turret_yaw
	var turret_pitch := 0.0
	var fire := false
	if v.has_turret() and target != null:
		var t = target
		var tpos: Vector3 = t.get("pos")
		var ty := atan2(-(tpos.x - v.pos.x), -(tpos.z - v.pos.z))
		var rel = ty - v.yaw
		while rel > PI:
			rel -= TAU
		while rel < -PI:
			rel += TAU
		turret_yaw = clampf(rel, -2.6, 2.6)
		var d_h := Vector2(tpos.x - v.pos.x, tpos.z - v.pos.z).length()
		turret_pitch = clampf(atan2((tpos.y + 1.1) - (v.pos.y + 2.2), d_h), -0.14, 1.22 if v.type == "aa" else 0.32)
		if absf(rel - v.turret_yaw) < 0.1 and v.cannon_t <= 0 and d_h < 150:
			fire = true
	v.ai_input = { "fwd": fwd, "steer": steer, "turret_yaw": turret_yaw, "turret_pitch": turret_pitch, "fire": fire }
	# 卡死:低速难行累计 → 倒车脱困 1.4s,连续 3 次失败才弃车
	if absf(v.speed) < 0.4 and fwd > 0.3 and unstuck_t <= 0:
		drive_stuck += dt
		if drive_stuck > 1.6:
			drive_stuck = 0
			unstuck_t = 1.4
			unstuck_n += 1
			if unstuck_n >= 3:
				unstuck_n = 0
				_exit_vehicle()
				return
	else:
		drive_stuck = 0
	if unstuck_t > 0:
		unstuck_t -= dt
		v.ai_input["fwd"] = -0.85
		v.ai_input["steer"] = -steer
	# ---- 乘员模型:jeep 敞篷坐姿 / 坦克·步战·防空封闭装甲乘员保持隐藏 ----
	if v.type == "jeep":
		# 臀部落座(模型原点在脚底,座椅面高约 1.08,下沉 1.32 防站穿车顶)
		var seat: Vector3 = v.seat_world()
		mesh.visible = true
		mesh.rotation_order = EULER_ORDER_YXZ
		mesh.position = Vector3(seat.x, seat.y - 1.32, seat.z)
		mesh.rotation = Vector3(0, v.yaw, 0)
		var leg_l: Node3D = mesh.get_meta("leg_l")
		var leg_r: Node3D = mesh.get_meta("leg_r")
		if leg_l != null:
			leg_l.visible = true
			leg_r.visible = true
			leg_l.rotation.x = 1.35
			leg_r.rotation.x = 1.35
			var leg_l_knee: Node3D = mesh.get_meta("leg_l_knee")
			var leg_r_knee: Node3D = mesh.get_meta("leg_r_knee")
			if leg_l_knee != null:
				leg_l_knee.rotation.x = -1.35
				leg_r_knee.rotation.x = -1.35
		var rig: Node3D = mesh.get_meta("rig")
		if rig != null:
			rig.rotation.x = 0.1
		if _crew_pose != "seat":
			_crew_pose = "seat"
			print("[CREW] bot=%d 驾驶中 jeep 坐姿 seat=%s" % [id, seat])
	else:
		# 坦克/步战/防空:封闭装甲乘员不可见(登车已隐藏,驾驶中保持,不出现舱盖探身)
		mesh.visible = false
		if _crew_pose != "hidden":
			_crew_pose = "hidden"
			print("[CREW] bot=%d 驾驶中 %s 封闭装甲乘员隐藏" % [id, v.type])


func update_bot(dt: float) -> void:
	# 我方队友倒地:平躺姿态、停止一切行为(由战役控制器救治/撤离)
	if downed:
		downed_t += dt
		vel = Vector3.ZERO
		mesh.rotation_order = EULER_ORDER_YXZ
		mesh.rotation.x = -PI / 2
		mesh.rotation.z = 0
		mesh.position = pos
		return
	# 战役过场(开场/结算):小队队友原地待命(显隐由战役控制器控制)
	if _is_following():
		var cm = G.get("campaign")
		if cm != null and cm.has_method("is_cutscene") and cm.is_cutscene():
			vel = Vector3.ZERO
			mesh.rotation_order = EULER_ORDER_YXZ
			mesh.position = pos
			mesh.rotation.y = yaw
			(hb["sprite"] as Sprite3D).visible = false
			return
	# 死亡动画(布娃娃)
	if not alive:
		death_t += dt
		var r = rag
		var t1 := 0.55
		var k := minf(death_t / t1, 1.0)
		var death_ease := 1 - pow(1 - k, 2.4)
		if r != null:
			mesh.rotation.x = r["rx"] * death_ease
			mesh.rotation.z = r["rz"] * death_ease
			var decay := exp(-death_t * 2.6)
			var w := death_t
			var d_upper: Node3D = mesh.get_meta("upper")
			if d_upper != null:
				d_upper.rotation.y = sin(w * r["f3"] + r["p3"]) * r["a3"] * 0.7 * decay
				d_upper.rotation.x = sin(w * r["f4"] + r["p4"]) * r["a4"] * 0.4 * decay
			var d_leg_l: Node3D = mesh.get_meta("leg_l")
			var d_leg_l_knee: Node3D = mesh.get_meta("leg_l_knee")
			var d_leg_r: Node3D = mesh.get_meta("leg_r")
			var d_leg_r_knee: Node3D = mesh.get_meta("leg_r_knee")
			if d_leg_l != null:
				d_leg_l.rotation.x = sin(w * r["f1"] + r["p1"]) * r["a1"] * decay
				d_leg_r.rotation.x = sin(w * r["f2"] + r["p2"]) * r["a2"] * decay
				d_leg_l_knee.rotation.x = -absf(sin(w * r["f2"] + r["p3"])) * r["a2"] * decay
				d_leg_r_knee.rotation.x = -absf(sin(w * r["f1"] + r["p4"])) * r["a1"] * decay
			# 落地瞬间一次小弹跳
			mesh.position.y = pos.y + maxf(0, sin(k * PI * 2.2)) * (1 - k) * 0.2
		else:
			mesh.rotation.x = -PI / 2 * k
		# 3.5s 后下沉消失
		if death_t > 3.5:
			mesh.position.y = pos.y - (death_t - 3.5) * 0.6
			if death_t > 4.5:
				mesh.visible = false
		return

	# 驾驶中:由载具逻辑接管
	if vehicle != null:
		_drive(dt)
		return

	think_t -= dt
	fire_t -= dt
	react_t -= dt
	suppress_t = maxf(0, suppress_t - dt)
	spotted = maxf(0, spotted - dt)
	hb_t -= dt
	if hb_t <= 0:
		(hb["sprite"] as Sprite3D).visible = false

	# ---- 思考(错峰 tick:每个 bot 的 think 周期按 id 错开,多人时降频) ----
	if think_t <= 0:
		think_t = _think_every + Utils.rand(0, 0.025)
		# 听觉感知(战场噪音)
		_hear_battlefield()
		_update_perf_lod()
		var was_engaging: bool = target != null and target_visible
		var seen = acquire_target(was_engaging)
		if seen != null:
			if not Utils.same_actor(target, seen):
				# 人化反应:新目标 350~800ms;刚丢而复得 150~450ms
				react_t = Utils.rand(0.35, 0.8) if not was_engaging else Utils.rand(0.15, 0.45)
				aim_settle = 0
				aim_err = aim_base * Utils.rand(2.2, 3.2)  # 刚瞄准:误差大,随稳定收敛
				suspect_t = Utils.rand(0.35, 1.1)          # 先观察再开火(防透视锁敌)
				_choose_fire_mode()
			target = seen
			target_visible = true
			target_by_hearing = false
			last_seen_pos = seen.pos
			_last_seen_t = G.time
			# 战术协作:向附近队友共享目标(集火);覆盖手共享更远(掩护推进)
			var share_r := 70.0 if overwatch else 40.0
			for b in G.bots:
				if b == self or not b.alive or b.team != team or b.target != null or b.vehicle != null:
					continue
				if b.pos.distance_to(pos) < share_r:
					b.target = seen
					b.last_seen_pos = seen.pos
					b._last_seen_t = G.time
					if b.react_t > 0.4:
						b.react_t = Utils.rand(0.3, 0.6)
		else:
			target_visible = false
		# 编队跟随:不接旗帜目标
		if target == null and not _is_following():
			pick_objective()
		# 占点节奏:小队集中攻点
		_assault_tick()
		_think_state()
		_decide_prone()
		_class_duty_search()
		_compute_buddy()
		# 战术换弹:安全时低弹量提前换
		if not reloading and ammo > 0 and ammo <= def.mag * 0.3 and (target == null or not target_visible):
			_start_reload()
		# 驾驶员找车:附近有无人载具则前往登车
		if can_drive and target == null and vehicle_goal == null:
			for v in G.vehicles:
				if v.dead or v.driver != null:
					continue
				if v.pos.distance_to(pos) < 90:
					vehicle_goal = v
					break
		# 卡死检测
		if pos.distance_to(last_pos) < 0.15:
			stuck_t += _think_every
			if stuck_t > 0.8:
				avoid_dir = Utils.choice([-1.2, 1.2])
				stuck_t = 0
				pick_objective(true)
		else:
			stuck_t = 0
		last_pos = pos

	# ---- 兵种职责:每帧递增计时(不触发 O(n) 搜索) ----
	heal_ot = maxf(0, heal_ot - dt)
	rpg_cd = maxf(0, rpg_cd - dt)
	smoke_cd = maxf(0, smoke_cd - dt)
	ability_cd = maxf(0, ability_cd - dt)
	mark_t = maxf(0, mark_t - dt)
	# 突击兵治疗(每帧平滑,不依赖搜索周期)
	if class_id == "assault":
		_duty_assault_tick(dt)
	# 换弹计时
	if reloading:
		reload_t -= dt
		if reload_t <= 0:
			reload_t = 0
			ammo = def.mag
			reloading = false
	# 受击/观察/掩体扫描计时
	hit_t = maxf(0, hit_t - dt)
	suspect_t = maxf(0, suspect_t - dt)
	cover_scan_cd = maxf(0, cover_scan_cd - dt)

	# ---- 移动(状态机驱动) ----
	var move_x := 0.0
	var move_z := 0.0
	var speed := 4.3
	var goal_x := 0.0
	var goal_z := 0.0
	var engaging: bool = target != null and target_visible
	match state:
		"flee":
			# 撤退:逃向掩体;无掩体则远离火力来源
			if cover_valid:
				goal_x = cover_pos.x
				goal_z = cover_pos.z
				speed = 5.2
				if pos.distance_to(cover_pos) < 1.3:
					cover_until = G.time + Utils.rand(1.5, 3.0)
					state = "engage" if (target != null and target_visible) else ("chase" if _has_lead() else "move")
			else:
				var away := Utils.safe_norm(pos - last_attacker_pos, Vector3.BACK)
				goal_x = pos.x + away.x * 18.0
				goal_z = pos.z + away.z * 18.0
				speed = 5.2
		"chase":
			# 追击:前往最后目击/听到的位置查探
			goal_x = last_seen_pos.x
			goal_z = last_seen_pos.z
			speed = 5.0
			var d6 := Utils.dist_2d(pos.x, pos.z, goal_x, goal_z)
			if d6 < 2.0:
				state = "engage" if target_visible else "move"
			elif hear_t <= 0 and G.time - _last_seen_t > 4.0:
				state = "move"
		"engage":
			# 交火:接近理想交战距离 + 环绕走位(蹲伏/趴下时不开大位移)
			if prone and engaging:
				pass  # 趴下射击:原地不动
			else:
				goal_x = last_seen_pos.x
				goal_z = last_seen_pos.z
				var d := Utils.dist_2d(pos.x, pos.z, goal_x, goal_z)
				strafe_t -= dt
				if strafe_t <= 0:
					strafe_t = Utils.rand(0.7, 1.6)
					strafe_dir = Utils.choice([-1, 1])
				var to_x := goal_x - pos.x
				var to_z := goal_z - pos.z
				var inv: float = 1.0 / (Vector2(to_x, to_z).length() + 1e-6)
				var ideal := 45.0 if def.kind == "sniper" else (8.0 if def.kind == "shotgun" else 20.0)
				var approach := clampf((d - ideal) / 8.0, -1, 1)
				move_x = to_x * inv * approach + (-to_z * inv) * strafe_dir * 0.8
				move_z = to_z * inv * approach + (to_x * inv) * strafe_dir * 0.8
				speed = 3.4
		"assault":
			# 占点:围点站位 / 覆盖手殿后 / 侧翼包抄
			var f = objective
			var to_f := Vector2(f.pos.x - pos.x, f.pos.z - pos.z)
			var d_obj := to_f.length()
			var r2: float = f.radius * 0.7
			if overwatch:
				# 覆盖手:推进到 34m 内后架枪原地,持续提供掩护火力
				if d_obj > 42:
					goal_x = f.pos.x + cos(assault_angle) * (r2 + 14.0)
					goal_z = f.pos.z + sin(assault_angle) * (r2 + 14.0)
					speed = 4.2
				else:
					goal_x = pos.x
					goal_z = pos.z
					speed = 0.8
			else:
				# 侧翼包抄:距旗 28m 外先走偏侧路线,再切入点位
				if d_obj > 28.0:
					var perp := Vector2(-to_f.y, to_f.x).normalized() * 13.0 * flank_side
					goal_x = f.pos.x + perp.x
					goal_z = f.pos.z + perp.y
				else:
					goal_x = f.pos.x + cos(assault_angle) * r2
					goal_z = f.pos.z + sin(assault_angle) * r2
				speed = 4.8
		"follow":
			# 编队跟随:向玩家编队位移动(复用下方避障/碰撞);玩家跑远快速跟上;到位停步
			var fp := formation_pos()
			var dx := fp.x - pos.x
			var dz := fp.z - pos.z
			var d := Vector2(dx, dz).length()
			var pd := 0.0
			if follow != null and is_instance_valid(follow):
				pd = pos.distance_to(follow.pos)
			if d > 1.4:
				move_x = dx / d
				move_z = dz / d
				speed = 5.6 if pd > 18.0 else 4.6
			else:
				speed = 0.0  # 到位:停步警戒(不环绕)
		"move":
			if vehicle_goal != null:
				# 前往载具登车
				var v = vehicle_goal
				if v.dead or v.driver != null:
					vehicle_goal = null
				else:
					goal_x = v.pos.x
					goal_z = v.pos.z
					var to_x2 := goal_x - pos.x
					var to_z2 := goal_z - pos.z
					var d2 := Vector2(to_x2, to_z2).length()
					if d2 < 3.0:
						# 登车
						vehicle_goal = null
						v.driver = self
						vehicle = v
						mesh.visible = false
						(hb["sprite"] as Sprite3D).visible = false
						_crew_pose = ""
						print("[CREW] bot=%d 登车 type=%s 乘员隐藏" % [id, v.type])
						return
					move_x = to_x2 / d2
					move_z = to_z2 / d2
					speed = 4.6
			elif duty_goal != null:
				# 兵种职责移动(工程跟车/支援跟随/侦察侧翼)
				goal_x = duty_goal.x
				goal_z = duty_goal.z
				var to_x5 := goal_x - pos.x
				var to_z5 := goal_z - pos.z
				var d5 := Vector2(to_x5, to_z5).length()
				if d5 > 1.2:
					move_x = to_x5 / d5
					move_z = to_z5 / d5
				speed = 4.4
			elif objective != null:
				goal_x = objective.pos.x + obj_offset.x
				goal_z = objective.pos.z + obj_offset.z
				# 战术协作:班组推进,向 8m 外最近队友适度靠拢(think 期缓存,无每帧 O(n))
				if _buddy_ok:
					goal_x = goal_x * 0.7 + _buddy_goal.x * 0.3
					goal_z = goal_z * 0.7 + _buddy_goal.z * 0.3
				var to_x3 := goal_x - pos.x
				var to_z3 := goal_z - pos.z
				var d4 := Vector2(to_x3, to_z3).length()
				if d4 > 1.5:
					move_x = to_x3 / d4
					move_z = to_z3 / d4
				else:
					pick_objective(true)
				speed = 4.6
		_:
			pass  # idle:原地警戒
	# 蹲伏限速
	if crouch and state != "flee":
		speed = minf(speed, 2.2)
	# 避障:前方探测(错峰每 3 帧一次,中间帧用缓存方向)
	if move_x != 0 or move_z != 0:
		var ml := Vector2(move_x, move_z).length()
		move_x /= ml
		move_z /= ml
		if (Engine.get_process_frames() + id * 7) % 3 == 0 or not _avoid_ok:
			var origin := Vector3(pos.x, pos.y + 0.9, pos.z)
			var hit = Utils.raycast_world(origin, Vector3(move_x, 0, move_z), 2.2)
			_avoid_ok = true
			if hit != null:
				var turned := false
				for a in [0.6, -0.6, 1.2, -1.2]:
					var ca := cos(a + avoid_dir)
					var sa := sin(a + avoid_dir)
					var nx: float = move_x * ca - move_z * sa
					var nz: float = move_x * sa + move_z * ca
					if Utils.raycast_world(origin, Vector3(nx, 0, nz), 2.2) == null:
						move_x = nx
						move_z = nz
						turned = true
						break
				if not turned:
					move_x = -move_x
					move_z = -move_z
			_avoid_cache = Vector2(move_x, move_z)
		else:
			move_x = _avoid_cache.x
			move_z = _avoid_cache.y
		vel.x = Utils.damp(vel.x, move_x * speed, 8, dt)
		vel.z = Utils.damp(vel.z, move_z * speed, 8, dt)
	else:
		vel.x = Utils.damp(vel.x, 0, 10, dt)
		vel.z = Utils.damp(vel.z, 0, 10, dt)
	pos.x += vel.x * dt
	pos.z += vel.z * dt
	pos = Utils.move_collide(pos, 0.38, 1.75)
	# 载具实体碰撞
	pos = Vehicle.vehicle_collide(pos, 0.38)
	# 地形贴合
	if G.ground_h.is_valid():
		pos.y = G.ground_h.call(pos.x, pos.z)

	# ---- 朝向 ----
	var want_yaw := yaw
	if target != null:
		want_yaw = atan2(-(last_seen_pos.x - pos.x), -(last_seen_pos.z - pos.z))
	elif _is_following():
		want_yaw = atan2(-(follow.pos.x - pos.x), -(follow.pos.z - pos.z))
	elif Vector2(vel.x, vel.z).length() > 0.5:
		want_yaw = atan2(-vel.x, -vel.z)
	var dy = want_yaw - yaw
	while dy > PI:
		dy -= TAU
	while dy < -PI:
		dy += TAU
	yaw += clampf(dy, -3.2 * dt, 3.2 * dt)

	# ---- 射击(人化开火模型) ----
	var h_speed := Vector2(vel.x, vel.z).length()
	# 瞄准稳定:交火中误差随时间向基准收敛(受击/新目标的跳变逐渐恢复)
	if state == "engage" or (state == "chase" and target_visible):
		aim_settle += dt
		aim_err = Utils.damp(aim_err, aim_base, 2.2, dt)
	var hold_fire := false
	if class_id == "recon" and target != null:
		# 侦察兵隐蔽优先:未暴露 + 目标较远 + 自身安全 → 不开枪
		var td: float = pos.distance_to(last_seen_pos)
		hold_fire = spotted <= 0 and td > 42 and health > 55
	if reloading:
		hold_fire = true  # 换弹中
	if suspect_t > 0:
		hold_fire = true  # 可疑区域先观察再开火(防透视锁敌)
	if suppress_t > 0 and not _in_cover():
		hold_fire = true  # 被压制且未进掩体:停止还击
	if state == "flee":
		hold_fire = true  # 撤退中不还击
	if engaging and react_t <= 0 and absf(dy) < 0.35 and not hold_fire:
		var fired_rocket := false
		# 工程兵:对载具/飞机发射 RPG(制导反载具核心;弹速 55 > 玩家 48,反装甲/防空需更远射程)
		if class_id == "engineer" and rpg_cd <= 0 and target != null:
			var tdef = target.get("def")
			var is_veh: bool = (tdef is Dictionary and tdef.get("radius") != null) or target.get("air") == true
			if is_veh:
				var origin := eye_pos()
				var aim: Vector3 = target.get("pos") + Vector3(0, 1.2, 0)
				var tvel = target.get("vel")
				if tvel != null:
					# 制导火箭:提前量仅作初瞄,飞行中持续转向修正(距/40 保守过瞄,由引导收敛)
					aim += (tvel as Vector3) * (pos.distance_to(target.get("pos")) / 40.0)
				# 第 5 参 target 启用制导:Vehicle/Aircraft 均提供 pos/dead,目标死亡自动解除制导转直坠
				G.effects.spawn_rocket(self, { "cn": "RPG-7", "damage": 120.0, "splash": 6.5, "speed": 55.0 }, origin, (aim - origin).normalized(), target)
				AudioSys.rpg_fire(pos)
				Bot.report_noise(pos.x, pos.z, 3.0, team, G.time)  # 火箭巨响广播
				rpg_cd = 3.6
				fired_rocket = true
		if not fired_rocket:
			# 狙击手:必须站稳才开枪
			if def.kind == "sniper" and h_speed > 1.0:
				pass
			else:
				if ammo <= 0:
					_start_reload()
				elif burst_left <= 0 and fire_t <= 0:
					burst_left = _next_burst()
					fire_t = 0.05
				if burst_left > 0 and fire_t <= 0:
					burst_left -= 1
					ammo -= 1
					fire_t = 60.0 / def.rpm
					shoot_at(target)
				if burst_left <= 0:
					fire_t = maxf(fire_t, _next_pause())

	# ---- 同步模型 ----
	mesh.rotation_order = EULER_ORDER_YXZ
	mesh.position = pos
	mesh.rotation.y = yaw
	# 趴下:身体伏地,交战时上半身抬起举枪射击;蹲姿:整体压低
	prone_amt = Utils.damp(prone_amt, 1.0 if prone else 0.0, 7, dt)
	crouch_amt = Utils.damp(crouch_amt, 1.0 if (crouch and not prone) else 0.0, 9, dt)
	mesh.rotation.x = -1.5 * prone_amt
	var upper: Node3D = mesh.get_meta("upper")
	if upper != null:
		var raise := 0.82 if (prone and engaging) else 0.1
		upper.rotation.x = Utils.damp(upper.rotation.x, raise * prone_amt, 8, dt)
		upper.rotation.y = Utils.damp(upper.rotation.y, 0, 8, dt)
	# ---- 腿部行走动画(膝关节) ----
	h_speed = Vector2(vel.x, vel.z).length()
	walk_t += h_speed * dt * 1.9
	var speed_k := minf(h_speed / 4.0, 1.0)
	var swing := sin(walk_t) * speed_k * 0.62
	var pk := 1 - prone_amt
	var leg_l: Node3D = mesh.get_meta("leg_l")
	var leg_l_knee: Node3D = mesh.get_meta("leg_l_knee")
	var leg_r: Node3D = mesh.get_meta("leg_r")
	var leg_r_knee: Node3D = mesh.get_meta("leg_r_knee")
	if leg_l != null:
		leg_l.rotation.x = Utils.damp(leg_l.rotation.x, swing * pk + 0.1 * prone_amt, 14, dt)
		leg_r.rotation.x = Utils.damp(leg_r.rotation.x, -swing * pk + 0.1 * prone_amt, 14, dt)
		leg_l_knee.rotation.x = Utils.damp(leg_l_knee.rotation.x, -maxf(0, sin(walk_t - 2.0)) * speed_k * 1.05 * pk, 12, dt)
		leg_r_knee.rotation.x = Utils.damp(leg_r_knee.rotation.x, -maxf(0, sin(walk_t - 2.0 + PI)) * speed_k * 1.05 * pk, 12, dt)
	# ---- 战术持枪姿态 ----
	var rig: Node3D = mesh.get_meta("rig")
	if rig != null:
		var want := 0.0
		if prone_amt > 0.4:
			want = -0.12
		elif crouch_amt > 0.4:
			want = 0.34  # 蹲姿:端枪齐腰
		elif engaging:
			var dyy := (last_seen_pos.y + 1.2) - (pos.y + 1.35)
			var dh := Vector2(last_seen_pos.x - pos.x, last_seen_pos.z - pos.z).length()
			want = clampf(-atan2(dyy, dh), -0.35, 0.35)
		elif h_speed > 2.5:
			want = 0.52  # 奔跑低姿持枪
		else:
			want = 0.16  # 警戒持枪
		rig_pitch = Utils.damp(rig_pitch, want, 8, dt)
		rig.rotation.x = rig_pitch
	# 身体随步伐轻微起伏(趴下贴地,蹲姿压低)
	mesh.position.y = pos.y + absf(sin(walk_t)) * 0.035 * speed_k * pk + 0.08 * prone_amt - 0.52 * crouch_amt


func shoot_at(p_target) -> void:
	var tdef = p_target.get("def")
	var is_veh: bool = tdef is Dictionary and tdef.get("radius") != null
	var is_air: bool = p_target.get("air") == true
	var origin := Vector3(pos.x, pos.y + (0.62 if prone else (0.85 if crouch else 1.32)), pos.z)
	# 瞄准点:目标胸口/载具中心(空中载具直接瞄准机体),简单提前量
	var aim_h := 0.0 if is_air else (1.2 if is_veh else 1.15)
	var tpos: Vector3 = p_target.get("pos")
	var aim := Vector3(tpos.x, tpos.y + aim_h, tpos.z)
	var tvel = p_target.get("vel")
	if tvel != null:
		aim += (tvel as Vector3) * (pos.distance_to(tpos) / 400.0)
	var dir := Utils.safe_norm(aim - origin, -G.camera.global_transform.basis.z if G.camera != null else Vector3.FORWARD)
	# ---- 人化精度模型:稳定误差(准星收敛) × 距离衰减 + 移动/压制惩罚,上下限钳制 ----
	var dist := pos.distance_to(tpos)
	var err := aim_err * (1.0 + dist / 60.0)
	var h_speed2 := Vector2(vel.x, vel.z).length()
	if h_speed2 > 1.2:
		err *= 2.4  # 移动射击精度惩罚
	if suppress_t > 0:
		err *= 1.6  # 被压制抬不起枪
	if crouch:
		err *= 0.8  # 蹲姿更稳
	if prone:
		err *= 0.7  # 趴下射击最稳
	# 命中率上下限钳制:近距不至于打不中,远距不至于锁头(平衡过强/过弱)
	err = clampf(err, 0.0045, 0.09)
	if def.kind == "sniper":
		err = clampf(err, 0.002, 0.032)
	var a := Utils.rand(TAU)
	var r := sqrt(randf()) * err
	var up := Vector3(0, 1, 0)
	var right := Utils.safe_norm(dir.cross(up), Vector3.RIGHT)
	var up2 := right.cross(dir)
	dir = (dir + right * (cos(a) * r) + up2 * (sin(a) * r)).normalized()
	last_fired_t = G.time
	# 枪声广播:战场噪音(听觉感知),机枪/狙更响
	Bot.report_noise(pos.x, pos.z, 1.3 if def.kind in ["sniper", "lmg"] else 1.0, team, G.time)
	# 弹道:下坠补偿瞄准 + 穿透链 + 部位倍率(内部结算到 fire_hitscan)
	Utils.ballistic_fire(self, def, origin, dir, origin)
	AudioSys.shoot_weapon(weapon_id, def.kind, pos, false)
	G.effects.muzzle(origin, dir, def.kind == "sniper")


## ==================== 兵种职责(各司其职) ====================
## 换装:每局由管理器按兵种分布分配武器(侦察/突击/机枪等),重建外观模型
func apply_loadout(p_class: String, p_weapon: String) -> void:
	class_id = p_class
	weapon_id = p_weapon
	def = WeaponsData.W()[weapon_id]
	var spr := hb["sprite"] as Sprite3D
	mesh.remove_child(spr)
	var old := mesh
	mesh = SoldierModel.build_soldier(team, weapon_id, class_id)
	mesh.add_child(spr)
	add_child(mesh)
	old.queue_free()
	_set_aim_base()


func _class_duty_search() -> void:
	duty_goal = null
	match class_id:
		"assault": _duty_assault()
		"engineer": _duty_engineer(0.14)
		"support": _duty_support()
		"recon": _duty_recon()


## 突击兵:自疗 + 烟雾推进 + C5 反工事
func _duty_assault() -> void:
	if health < 45 and target == null and heal_ot <= 0:
		heal_ot = 2.5
	if objective != null and smoke_cd <= 0 and G.mode == "conquest":
		var f = objective
		if f.get("owner_team") != null and f.owner_team != team and f.owner_team != "":
			var d := Utils.dist_2d(pos.x, pos.z, f.pos.x, f.pos.z)
			if d < 32 and d > 8:
				var dir: Vector3 = (f.pos - pos).normalized()
				G.effects.spawn_smoke_grenade(self, pos + Vector3(0, 1.3, 0) + dir * 1.2, dir)
				smoke_cd = 12.0
	# C5:贴近敌方载具/工事时放置(12m 内)
	if ability_cd <= 0 and target != null:
		var tdef = target.get("def")
		if tdef is Dictionary and tdef.get("radius") != null:
			var d3 := pos.distance_to(target.get("pos"))
			if d3 < 12:
				G.game.spawn_c5(self)
				ability_cd = 14.0


func _duty_assault_tick(dt: float) -> void:
	if heal_ot > 0:
		health = minf(100, health + 16 * dt)


## 工程兵:跟随己方载具 + 维修受损载具
func _duty_engineer(dt: float) -> void:
	var engaging: bool = target != null and target_visible
	if engaging:
		return
	# 找最近己方(有人驾驶或中立)载具
	var best_v = null
	var best_d := 60.0
	for v in G.vehicles:
		if v.dead:
			continue
		var vt = v.team()
		if vt != null and vt != team:
			continue
		var d: float = pos.distance_to(v.pos)
		if d < best_d:
			best_v = v
			best_d = d
	if best_v == null:
		return
	# 受损载具:优先靠近维修(4.5m 内持续修复)
	if best_v.hp < best_v.def["hp"] and best_d < 45:
		if best_d > 4.2:
			duty_goal = best_v.pos
		else:
			best_v.hp = minf(best_v.def["hp"], best_v.hp + 40 * dt)
			duty_goal = pos  # 原地维修
	elif best_d > 12:
		# 未受损但远离载具活动区:跟上
		duty_goal = best_v.pos


## 支援兵:跟随小队后方 + 投放补给
func _duty_support() -> void:
	# 跟随最近的突击兵,保持 6-9m 距离
	var best_a = null
	var best_d := 40.0
	for b in G.bots:
		if b == self or not b.alive or b.team != team or b.vehicle != null or b.class_id != "assault":
			continue
		var d: float = b.pos.distance_to(pos)
		if d < best_d:
			best_a = b
			best_d = d
	if best_a != null and (best_d > 9 or best_d < 5) and target == null:
		duty_goal = best_a.pos + (pos - best_a.pos).normalized() * 7.0
	# 投放补给箱:附近有受伤/缺弹队友
	if ability_cd <= 0:
		var need := false
		for b in G.bots:
			if not b.alive or b.team != team or b.vehicle != null:
				continue
			if b.pos.distance_to(pos) < 13 and b.health < 68:
				need = true
				break
		if (G.player != null and G.player.alive and G.player.team == team
				and G.player.pos.distance_to(pos) < 13 and G.player.health < 68):
			need = true
		if need:
			G.game.spawn_ammo_pack(self)
			ability_cd = 20.0
	# 低血撤退封烟
	if health < 35 and target != null and smoke_cd <= 0:
		G.effects.spawn_smoke_grenade(self, pos + Vector3(0, 1.3, 0), Vector3(0, 0.3, 0))
		smoke_cd = 14.0


## 侦察兵:侧翼站位 + 周期标记 + 部署重生信标
func _duty_recon() -> void:
	# 周期标记:6 秒一次,标记最近可见敌人(全队共享情报)
	if mark_t <= 0:
		mark_t = 6.0
		var best = null
		var best_d := 90.0
		for b in G.bots:
			if not b.alive or b.team == team or b.spotted > 0:
				continue
			var d: float = pos.distance_to(b.pos)
			if d < best_d and Utils.los_clear(eye_pos(), b.pos + Vector3(0, 1.3, 0)):
				best = b
				best_d = d
		if best != null:
			best.spotted = 9
			for b2 in G.bots:
				if b2 != self and b2.alive and b2.team == team and b2.pos.distance_to(pos) < 40:
					b2.last_seen_pos = best.pos
	# 部署重生信标:靠近敌方目标点侧翼(12-26m)且周边无敌
	if ability_cd <= 0 and objective != null:
		var d := Utils.dist_2d(pos.x, pos.z, objective.pos.x, objective.pos.z)
		if d > 10 and d < 30:
			var enemy_near := false
			for b in G.bots:
				if b.alive and b.team != team and b.pos.distance_to(pos) < 14:
					enemy_near = true
					break
			if not enemy_near:
				G.game.spawn_beacon(self)
				ability_cd = 45.0
	# 侧翼站位:目标点侧向偏移(避免正面)
	if target == null and objective != null:
		var to_obj := Vector3(objective.pos.x - pos.x, 0, objective.pos.z - pos.z)
		var side := Vector3(-to_obj.z, 0, to_obj.x).normalized() * 16
		var mid: Vector3 = pos.lerp(objective.pos, 0.45)
		duty_goal = mid + side
