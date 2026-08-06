class_name Game extends Node
## 征服/突破模式核心逻辑(对应 game.js):命中判定 / 爆炸 / 旗帜占领 / 兵力值 / 击杀

var drain_t := 0.0
var arty = null                        # 炮火支援 { pos, shells, interval, t }
var nv_spot_t := 0.0                   # 夜视仪索敌计时(每 0.3s 刷新标记)
var _bt_oob := {}                      # 突破模式越界遣返 { actor -> 剩余宽限秒 }
const BT_OOB_PLAYER := 2.8             # 玩家越界宽限(秒)
const BT_OOB_BOT := 0.9                # AI 越界宽限(秒)


## def 字段访问(兼容 WeaponDef / Dictionary / null)
static func dget(def, key: String, default = null):
	if def == null:
		return default
	if def is Dictionary:
		return def.get(key, default)
	var v = def.get(key)
	return default if v == null else v


## 安全判断是否为玩家(actor 可能是 Node 或 Dictionary 飞行员)
static func is_player(actor) -> bool:
	return actor is Object and is_same(actor, G.player)


## 战役过场(开场/结算)期间玩家无敌
func in_cutscene() -> bool:
	return G.mode == "campaign" and G.campaign != null and G.campaign.is_cutscene()


static func _hitscan_actor(actor, shooter, s_team, origin: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	if actor is Object and shooter is Object and is_same(actor, shooter):
		return {}
	if actor.team == s_team:
		return {}
	if actor.alive == false:
		return {}
	if actor.get("vehicle") != null:
		return {}
	var hf := 1.0
	if is_same(actor, G.player):
		hf = 0.3 if actor.prone else (0.72 if actor.crouched else 1.0)
	else:
		hf = 0.32 if actor.prone else 1.0
	var head_pos := Vector3(actor.pos.x, actor.pos.y + 1.56 * hf, actor.pos.z)
	var d := Utils.ray_sphere(origin, dir, head_pos, 0.21, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "head": true }
	var chest_pos := Vector3(actor.pos.x, actor.pos.y + 1.05 * hf, actor.pos.z)
	d = Utils.ray_sphere(origin, dir, chest_pos, 0.42, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "head": false }
	var pelvis_pos := Vector3(actor.pos.x, actor.pos.y + 0.5 * hf, actor.pos.z)
	d = Utils.ray_sphere(origin, dir, pelvis_pos, 0.38, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "head": false }
	return {}


## ============ 地图构建(选图即时生效) ============
func setup_map(map_id: String) -> void:
	WorldBuilder.build_world(G.world_root, map_id)
	GraphicsQuality.reapply()  # 环境被重建,重挂画质预设(SSIL/SSR/glow 等)
	for v in G.vehicles:
		v.dispose()
	G.vehicles = []
	# 载具(战役模式纯净:不生成任何可驾驶载具;空中单位见下方征服分支)
	if G.mode != "campaign":
		for s in G.vehicle_spawns:
			G.vehicles.append(Vehicle.new(s["x"], s["z"], s["yaw"], s.get("type", "jeep")))
	for v in G.vehicles:
		G.main.add_child(v)
	# 清理旧部署物
	for d in G.deployables:
		if is_instance_valid(d["mesh"]):
			d["mesh"].queue_free()
	G.deployables = []
	for f in G.flags:
		f.owner_team = null
		f.progress = 0
		f.locked = false
		f.contested = false
	# 旗帜/部署物已随世界重建:部署界面点选的原点位(旗帜对象/信标网格)已失效,清空防悬空引用
	if G.hud != null:
		if G.hud.spawn_point != null and not (G.hud.spawn_point is Dictionary):
			G.hud.spawn_point = null  # 旧 Flag 实例已随 world_group 销毁
		elif G.hud.spawn_point != null and G.hud.spawn_point is Dictionary:
			if G.hud.spawn_point.get("kind") == "beacon":
				G.hud.spawn_point = null  # 信标网格已销毁
	# 突破模式:全部目标点初始由防守方控制,仅当前区域可争夺
	# 防御:build_world 已对无效 map_id 安全返回,此处键访问前置校验防中途中止
	if not MapsData.M().has(map_id):
		push_error("[GAME] setup_map 收到无效地图 id: \"%s\",跳过突破/征服装配" % map_id)
		return
	var T = MapsData.M()[map_id]
	if G.mode == "breakthrough" and T.mode == "breakthrough":
		for f in G.flags:
			f.owner_team = "ru"
			f.progress = -100
		G.bt = { "sector": 0, "total": T.sectors.size() }
		_bt_oob.clear()
		# 未解锁的区域整体封锁(旗帜置灰 / 不可部署 / 闯入即遣返)
		for f in G.flags:
			f.zone_locked = f.sector > 0
	# 空中单位(仅征服模式)
	for a in G.aircraft:
		a.dispose()
	G.aircraft = []
	G.lock_target = null  # 旧机体已销毁,锁定引用一并清除
	if G.mode == "conquest":
		G.aircraft.append(Aircraft.new("us", "heli"))
		G.aircraft.append(Aircraft.new("us", "jet"))
		G.aircraft.append(Aircraft.new("ru", "heli"))
		G.aircraft.append(Aircraft.new("ru", "jet"))
	for a in G.aircraft:
		G.main.add_child(a)


## ============ 开局/部署 ============
func start_match(mode := "conquest") -> void:
	var cm = G.get("campaign")
	if cm != null:
		cm.abort()  # 切回任意模式前终止战役残留状态
	if G.hud != null:
		G.hud.clear_campaign_ui()  # 清战役 UI 残留(目标/字幕/点名卡/箭头)
	if mode == "campaign":
		_start_campaign()
		return
	G.mode = mode
	var pool := []
	for id in MapsData.M():
		var m = MapsData.M()[id]
		if (m.mode if m.mode != "" else "conquest") == mode:
			pool.append(id)
	var sel: String = G.sel_maps.get(mode, "random")
	# 防御:地图池为空(非法模式/无匹配地图)时中止开局,防 Utils.choice 返回 Nil 赋给 String
	if pool.is_empty():
		push_error("[GAME] 无可用地图(mode=%s),已中止开局" % mode)
		return
	var map_id: String = Utils.choice(pool) if sel == "random" else sel
	# 防御:选中的地图 id 不存在时中止开局,防 MapsData.M()[id] 键访问错误
	if not MapsData.M().has(map_id):
		push_error("[GAME] 未知地图 id \"%s\",已中止开局" % map_id)
		return
	setup_map(map_id)
	G.time = 0
	G.stats = { "kills": 0, "deaths": 0 }
	G.streak = 0
	G.streak_uav = false
	G.streak_arty = false
	arty = null
	if mode == "breakthrough":
		# 突破模式:进攻方(玩家方)兵力有限,防守方无限
		# 新对局默认玩家为进攻方(世界攻防方向固定 us=进攻 / ru=防守,玩家只选自己的阵营)
		G.bt_player_side = "att"
		G.player.team = "us"
		G.tickets = { "us": 250, "ru": INF }
	else:
		G.tickets = { "us": 400, "ru": 400 }
		G.bt = null
	G.state = "deploy"
	G.bot_manager.reset(11)
	G.hud.spawn_point = null
	G.hud.spawn_mate = null
	G.hud.hide_screen("death")
	G.hud.show_deploy(false)
	AudioSys.start_ambient()


## ============ 战役模式:章节地图 + 玩家自动部署 + 战役控制器接管 ============
func _start_campaign() -> void:
	G.mode = "campaign"
	var ch := _campaign_chapter()
	# 兜底装配:main 未创建 Campaign 节点时由 game 自行创建(与菜单子智能体约定不冲突)
	var cm = G.get("campaign")
	# 防御:旧实例已失效(悬空引用)时置空重建,绝不 add_child 到已释放节点
	if cm != null and not is_instance_valid(cm):
		G.set("campaign", null)
		cm = null
	if cm == null:
		cm = Campaign.new()
		G.main.add_child(cm)
		G.set("campaign", cm)
	setup_map(ch["map"])
	G.time = 0
	G.stats = { "kills": 0, "deaths": 0 }
	G.streak = 0
	G.streak_uav = false
	G.streak_arty = false
	arty = null
	G.bt = null
	G.tickets = { "us": INF, "ru": INF }  # 战役胜负由章节目标决定,不受票数影响
	G.player.team = "us"
	G.state = "playing"  # 战役不进入部署界面,直接开打
	G.bot_manager.reset(0)  # 战役敌人由战役控制器生成
	G.hud.spawn_point = null
	G.hud.spawn_mate = null
	G.hud.hide_screen("death")
	G.hud.hide_screen("deploy")
	AudioSys.start_ambient()
	cm.start_chapter(ch["id"])
	deploy("assault", { "primary": "m4", "secondary": "m1911", "shotgun": "m1014" })
	# 章节出生点朝向(覆盖 spawn 默认朝向)
	G.player.pos = ch["start_pos"]
	G.player.yaw = float(ch.get("start_yaw", 0.0))
	G.player.pitch = 0.0


## 从 G.campaign_pending_id(菜单子智能体设置)读取章节,缺省 c1
func _campaign_chapter() -> Dictionary:
	var pending: String = str(G.get("campaign_pending_id"))
	for c in CampaignData.chapters():
		if c["id"] == pending:
			return c
	return CampaignData.chapters()[0]


## 突破模式部署界面选边:att → 进攻方(us),def → 防守方(ru);只改变玩家阵营,不动世界攻防方向
func set_bt_side(side: String) -> void:
	if side != "att" and side != "def":
		return
	G.bt_player_side = side
	G.player.team = "us" if side == "att" else "ru"
	# 小队跟随玩家阵营
	for s in G.squads:
		if s["team"] == G.player.team:
			G.player_squad = s
			break


func deploy(class_id: String, loadout) -> void:
	G.player.class_id = class_id
	G.player.loadout = loadout
	# 战役模式:固定出生点(章节起始/最近完成据点),跳过部署界面选点
	if G.mode == "campaign":
		var cm = G.get("campaign")
		var rp: Vector3 = cm.respawn_point() if cm != null else Vector3(0, 0, -130)
		G.player.spawn(rp)
		G.hud.hide_screen("deploy")
		G.hud.hide_screen("death")
		G.hud.show_screen("hud")
		G.state = "playing"
		G.input_sys.lock()
		AudioSys.deploy_sting()
		if cm != null:
			cm.apply_cutscene_state()  # 过场中:重新隐藏玩家模型 + 无敌(deploy 重置了它们)
		G.hud.banner(cm.objective_text() if cm != null and cm.running else "战役进行中")
		return
	# 小队部署:优先部署在选中小队成员身旁
	var sm = G.hud.spawn_mate
	var sp = G.hud.spawn_point
	# 悬空引用防护(换图后旧旗帜实例已销毁)
	if sp != null and not (sp is Dictionary) and not is_instance_valid(sp):
		sp = null
		G.hud.spawn_point = null
	if sm != null and sm.alive and sm.vehicle == null:
		var a := Utils.rand(TAU)
		var r := Utils.rand(2.5, 5)
		var px = sm.pos.x + cos(a) * r
		var pz = sm.pos.z + sin(a) * r
		G.player.spawn(Vector3(px, G.ground_h.call(px, pz) if G.ground_h.is_valid() else 0.0, pz))
	elif sp != null and sp is Dictionary and sp.get("kind") == "beacon" and sp["team"] == G.player.team \
			and (G.mode != "breakthrough" or G.bt == null \
				or ((sp["pos"].z >= bt_rear_z()) if G.player.team == "ru" else (sp["pos"].z <= bt_front_z()))):
		# 重生信标部署(侦察兵部署点)
		var a3 := Utils.rand(TAU)
		var r3 := Utils.rand(2, 4)
		var px3 = sp["pos"].x + cos(a3) * r3
		var pz3 = sp["pos"].z + sin(a3) * r3
		G.player.spawn(Vector3(px3, G.ground_h.call(px3, pz3) if G.ground_h.is_valid() else 0.0, pz3))
	elif sp != null and sp.owner_team == G.player.team \
			and (G.mode != "breakthrough" or G.bt == null or sp.sector <= G.bt["sector"]):
		var a2 := Utils.rand(TAU)
		var r2 := Utils.rand(6, 12)
		var px2 = sp.pos.x + cos(a2) * r2
		var pz2 = sp.pos.z + sin(a2) * r2
		G.player.spawn(Vector3(px2, G.ground_h.call(px2, pz2) if G.ground_h.is_valid() else 0.0, pz2))
	else:
		spawn_actor(G.player)
	G.hud.hide_screen("deploy")
	G.hud.hide_screen("death")
	G.hud.show_screen("hud")
	G.state = "playing"
	G.input_sys.lock()
	AudioSys.deploy_sting()
	if G.mode == "breakthrough":
		G.hud.banner("突破敌军防线,夺取全部区域!进攻方兵力有限!" if G.bt_player_side == "att" else "坚守防线,消灭进攻方!防守方兵力无限!")
	else:
		G.hud.banner("夺取并守住旗帜!")


func redeploy() -> void:
	G.hud.hide_screen("death")
	if G.mode == "campaign":
		# 战役:不进部署屏,直接在最近据点重生(线性关卡无部署系统)
		var cm = G.get("campaign")
		var rp: Vector3 = cm.respawn_point() if cm != null else Vector3.ZERO
		G.player.spawn(rp)
		G.hud.hide_screen("deploy")
		G.hud.show_screen("hud")
		G.state = "playing"
		G.input_sys.lock()
		return
	G.hud.show_deploy(true)  # 重部署不允许换图
	G.state = "deploy"


## 选择出生点:突破模式按前线出生线;征服模式己方旗帜 > 基地
func spawn_actor(actor) -> void:
	var team: String = actor.team
	var pos = Vector3.ZERO
	# 重生信标优先(侦察兵部署的隐蔽重生点,40% 概率使用)
	var beacons := []
	for d in G.deployables:
		if d["kind"] == "beacon" and d["team"] == team:
			if G.mode == "breakthrough" and G.bt != null:
				var bz2: float = d["pos"].z
				if (bz2 < bt_rear_z()) if team == "ru" else (bz2 > bt_front_z()):
					continue
			beacons.append(d["pos"])
	if not beacons.is_empty() and randf() < 0.4:
		pos = Utils.choice(beacons)
	elif G.mode == "breakthrough" and G.bt_spawns != null and G.bt != null:
		var sec: int = mini(G.bt["sector"], G.bt_spawns["att"].size() - 1)
		var arr: Array = G.bt_spawns["att"][sec] if team == "us" else G.bt_spawns["def"][sec]
		pos = Utils.choice(arr)
	else:
		var owned := []
		for f in G.flags:
			if f.owner_team == team:
				owned.append(f)
		if not owned.is_empty() and randf() < 0.75:
			var f: Flag = Utils.choice(owned)
			var a := Utils.rand(TAU)
			pos = Vector3(f.pos.x + cos(a) * Utils.rand(8, 14), 0, f.pos.z + sin(a) * Utils.rand(8, 14))
		else:
			pos = Utils.choice(G.spawns[team])
	actor.spawn(pos)


## ============ 命中判定(射击游戏核心) ============
func fire_hitscan(shooter, def, origin: Vector3, dir: Vector3, muzzle_pos: Vector3) -> void:
	var max_dist := 300.0
	# 1. 墙体
	var wall = Utils.raycast_world(origin, dir, max_dist)
	var best_dist: float = wall["dist"] if wall != null else max_dist
	# 2. 角色(敌方)
	var hit_actor = null
	var hit_head := false
	var s_team = dget(shooter, "team")
	for b in G.bots:
		var hit: Dictionary = _hitscan_actor(b, shooter, s_team, origin, dir, best_dist)
		if not hit.is_empty():
			best_dist = hit["dist"]
			hit_actor = hit["actor"]
			hit_head = hit["head"]
	if G.player != null and s_team != G.player.team:
		var phit: Dictionary = _hitscan_actor(G.player, shooter, s_team, origin, dir, best_dist)
		if not phit.is_empty():
			best_dist = phit["dist"]
			hit_actor = phit["actor"]
			hit_head = phit["head"]

	# 3. 载具(可被子弹/机炮击伤;不打己方有人载具)
	var hit_vehicle = null
	for v in G.vehicles:
		if v.dead:
			continue
		if v.driver != null and s_team != null and v.driver.team == s_team:
			continue
		var v_pos := Vector3(v.pos.x, v.pos.y + 1.2, v.pos.z)
		var d := Utils.ray_sphere(origin, dir, v_pos, v.def["radius"] + 0.35, best_dist)
		if d >= 0:
			best_dist = d
			hit_vehicle = v
			hit_actor = null
	# 4. 空中载具(直升机/战斗机)
	for a in G.aircraft:
		if a.dead:
			continue
		if s_team != null and a.team == s_team:
			continue
		var d2 := Utils.ray_sphere(origin, dir, a.pos, a.radius, best_dist)
		if d2 >= 0:
			best_dist = d2
			hit_vehicle = a
			hit_actor = null
	# 5. 可破坏物(油桶/木箱/棚屋,子弹可击毁)
	var hit_ds = null
	for ds in G.destructibles:
		if ds.dead:
			continue
		var d3 := Utils.ray_sphere(origin, dir, ds.pos, ds.radius, best_dist)
		if d3 >= 0:
			best_dist = d3
			hit_ds = ds
			hit_actor = null
			hit_vehicle = null

	var end: Vector3 = origin + dir * best_dist
	# 曳光弹(从枪口出发)
	G.effects.tracer(muzzle_pos, end, dget(def, "tracer", Color(1, 0.85, 0.63)))

	# 压制效果(BF):敌方子弹掠过玩家附近
	if G.player.alive and s_team != G.player.team and hit_actor != G.player:
		var to_p: Vector3 = G.camera.global_position - origin
		var t := to_p.dot(dir)
		if t > 0 and t < best_dist:
			var closest := (to_p - dir * t).length()
			if closest < 2.5:
				G.player.suppression = minf(1, G.player.suppression + 0.22)
				G.effects.shake(0.08)

	if hit_actor != null:
		# 距离衰减
		var rng: Array = dget(def, "rng", [50.0, 100.0, 0.5])
		var falloff := 1.0
		if best_dist <= rng[0]:
			falloff = 1.0
		elif best_dist >= rng[1]:
			falloff = rng[2]
		else:
			falloff = 1 - (1 - rng[2]) * (best_dist - rng[0]) / (rng[1] - rng[0])
		var dmg: float = dget(def, "damage", 25.0) * falloff * (dget(def, "head_mult", 2.0) if hit_head else 1.0)
		var is_player_shooter: bool = shooter is Object and is_same(shooter, G.player)
		if hit_actor == G.player:
			# 过场期间玩家无敌
			if in_cutscene():
				return
			# AI 对玩家伤害按 bot skill 加权(0.7~1.0):新兵(0.45)约 0.7,精英(1.1)约 1.0
			var ai_mult: float = 0.7 + 0.3 * clampf((float(Game.dget(shooter, "skill", 0.8)) - 0.45) / 0.65, 0.0, 1.0)
			G.player.damage(dmg * ai_mult, dget(shooter, "pos", Vector3.ZERO), shooter, def)
		else:
			G.effects.blood(end, dir)
			hit_actor.take_damage(dmg, shooter, hit_head, def)
		if is_player_shooter and hit_actor != G.player:
			var killed: bool = hit_actor.alive == false
			G.hud.show_hitmarker(killed, hit_head)
			if killed:
				AudioSys.kill_confirm(hit_head)
			else:
				AudioSys.hit(hit_head)
	elif hit_vehicle != null:
		# 载具中弹:按武器载具系数削减
		var rng2: Array = dget(def, "rng", [50.0, 100.0, 0.5])
		var falloff2 := 1.0
		if best_dist <= rng2[0]:
			falloff2 = 1.0
		elif best_dist >= rng2[1]:
			falloff2 = rng2[2]
		else:
			falloff2 = 1 - (1 - rng2[2]) * (best_dist - rng2[0]) / (rng2[1] - rng2[0])
		hit_vehicle.damage(dget(def, "damage", 25.0) * dget(def, "veh_dmg", 0.5) * falloff2, shooter)
		G.effects.impact(end, -dir)
		if is_player(shooter):
			G.hud.show_hitmarker(hit_vehicle.dead, false)
			if hit_vehicle.dead:
				G.hud.banner("摧毁敌方 " + dget(hit_vehicle.def, "vehicle_name", dget(hit_vehicle.def, "cn", "载具")) + "!")
				AudioSys.kill_confirm(false)
			else:
				AudioSys.hit(false)
	elif hit_ds != null:
		# 可破坏物中弹
		hit_ds.damage(dget(def, "damage", 25.0), shooter)
		G.effects.impact(end, -dir)
	elif wall != null:
		G.effects.impact(end, wall["normal"])


## ============ 重生信标(侦察兵:小队隐蔽重生点,持续 90 秒) ============
## 部署物出生点前导(四类部署物共用):朝向(玩家=相机朝向,AI=yaw)→ 前方 dist 米 → 贴地抬升 lift
func _deploy_front_pos(p_owner, dist: float, lift: float) -> Vector3:
	var fwd: Vector3
	if p_owner == G.player:
		fwd = -G.camera.global_transform.basis.z
	else:
		fwd = Vector3(-sin(p_owner.yaw if p_owner.get("yaw") != null else 0.0), 0, -cos(p_owner.yaw if p_owner.get("yaw") != null else 0.0))
	fwd.y = 0
	fwd = fwd.normalized()
	var pos: Vector3 = p_owner.pos + fwd * dist
	pos.y = (G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0) + lift
	return pos


func spawn_beacon(p_owner) -> void:
	var pos: Vector3 = _deploy_front_pos(p_owner, 1.5, 0.0)
	var g := Node3D.new()
	# 信标杆
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.05
	pm.height = 1.1
	pole.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color.html("#2a3040")
	pmat.roughness = 0.5
	pmat.metallic = 0.6
	pole.material_override = pmat
	pole.position.y = 0.55
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(pole)
	# 顶部呼吸灯
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.07
	lm.height = 0.14
	lamp.mesh = lm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 阵营区分:敌军道具整体红色
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	lamp_mat.albedo_color = Color(1, 0.2, 0.15) if en else Color(0.2, 1, 0.5)
	lamp.material_override = lamp_mat
	lamp.position.y = 1.15
	g.add_child(lamp)
	g.position = pos
	G.world_root.add_child(g)
	G.deployables.append({ "kind": "beacon", "mesh": g, "lamp_mat": lamp_mat,
		"team": p_owner.team, "en": en, "owner": p_owner, "pos": pos, "life": 90.0, "tick": 0.0, "t": 0.0, "arm": 0.0 })
	AudioSys.reload(1)
	if p_owner == G.player:
		G.hud.hint("重生信标已部署:小队可在此重生(90 秒)")


## ============ C5 炸药(突击兵:定时 4 秒,大威力反工事/载具) ============
func spawn_c5(p_owner) -> void:
	var pos: Vector3 = _deploy_front_pos(p_owner, 1.3, 0.05)
	var g := Node3D.new()
	var blk := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.1, 0.2)
	blk.mesh = bm
	var bmat := StandardMaterial3D.new()
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	bmat.albedo_color = Color.html("#7a3020") if en else Color.html("#c8b060")
	bmat.roughness = 0.7
	bmat.emission_enabled = en
	bmat.emission = Color(1, 0.15, 0.1)
	bmat.emission_energy_multiplier = 0.35 if en else 0.0
	blk.material_override = bmat
	blk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(blk)
	# 顶部引爆灯(闪烁)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.02
	lm.height = 0.04
	lamp.mesh = lm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1, 0.2, 0.1)
	lamp.material_override = lamp_mat
	lamp.position.y = 0.08
	g.add_child(lamp)
	g.position = pos
	G.world_root.add_child(g)
	G.deployables.append({ "kind": "c5", "mesh": g, "lamp_mat": lamp_mat,
		"team": p_owner.team, "owner": p_owner, "pos": pos, "life": 4.0, "tick": 0.0, "t": 0.0, "arm": 0.0 })
	AudioSys.reload(0)
	if p_owner == G.player:
		G.hud.hint("C5 已放置:4 秒后引爆")


## ============ 反坦克地雷(全员可部署:敌方载具靠近引爆) ============
func spawn_at_mine(p_owner) -> void:
	var pos: Vector3 = _deploy_front_pos(p_owner, 1.2, 0.03)
	var g := Node3D.new()
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.19
	cm.height = 0.07
	cm.radial_segments = 12
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	dm.albedo_color = Color.html("#4a1614") if en else Color.html("#2e3328")
	dm.roughness = 0.6
	dm.metallic = 0.4
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(disc)
	# 顶部识别灯(武装后闪红)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.025
	lm.height = 0.05
	lamp.mesh = lm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(0.4, 0.4, 0.4)
	lamp.material_override = lamp_mat
	lamp.position.y = 0.06
	g.add_child(lamp)
	g.position = pos
	G.world_root.add_child(g)
	G.deployables.append({ "kind": "atmine", "mesh": g, "lamp_mat": lamp_mat,
		"team": p_owner.team, "owner": p_owner, "pos": pos, "life": 90.0, "tick": 0.0, "t": 0.0, "arm": 1.5 })
	AudioSys.reload(0)
	if p_owner == G.player:
		G.hud.hint("反坦克地雷已部署:敌方载具靠近即爆")


## ============ 工程兵弹药包(部署物:补给弹药 + 恢复生命) ============
func spawn_ammo_pack(p_owner) -> void:
	var pos: Vector3 = _deploy_front_pos(p_owner, 1.4, 0.0)
	# 建模:弹药箱(程序化)
	var g := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.25, 0.3)
	box.mesh = bm
	var box_mat := StandardMaterial3D.new()
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	box_mat.albedo_color = Color.html("#5a2418") if en else Color.html("#4a5a3a")
	box_mat.roughness = 0.75
	box_mat.metallic = 0.1
	box.material_override = box_mat
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(box)
	var ring := MeshInstance3D.new()
	ring.mesh = Flag.make_ring_mesh(4.2, 4.5, 40)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1, 0.28, 0.2, 0.35) if en else Color(0.62, 0.88, 0.54, 0.35)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	ring.position.y = 0.06
	g.add_child(ring)
	g.position = pos
	G.world_root.add_child(g)
	G.deployables.append({ "kind": "ammopack", "mesh": g, "ring_mat": ring_mat,
		"team": p_owner.team, "pos": pos, "life": 30.0, "tick": 0.0, "t": 0.0 })
	AudioSys.reload(1)
	if p_owner == G.player:
		G.hud.hint("弹药包已部署:圈内友军持续补给弹药并恢复生命")


func _update_deployables(dt: float) -> void:
	for i in range(G.deployables.size() - 1, -1, -1):
		var d: Dictionary = G.deployables[i]
		d["life"] -= dt
		d["tick"] -= dt
		d["t"] += dt
		if d["kind"] == "atmine":
			# 反坦克地雷:武装倒计时 → 识别灯转红;敌方载具进入 2.6m 引爆
			if d["arm"] > 0:
				d["arm"] -= dt
				if d["arm"] <= 0:
					(d["lamp_mat"] as StandardMaterial3D).albedo_color = Color(1, 0.15, 0.1)
			else:
				(d["lamp_mat"] as StandardMaterial3D).albedo_color = Color(1, 0.15, 0.1).lerp(Color(0.5, 0.05, 0.05), 0.5 + sin(d["t"] * 6) * 0.5)
				var boom := false
				for v in G.vehicles:
					if v.dead:
						continue
					var vt = v.team()
					if vt == null or vt == d["team"]:
						continue  # 只炸敌方驾驶的载具
					var rr: float = v.def["radius"] + 0.6
					if Vector2(v.pos.x - d["pos"].x, v.pos.z - d["pos"].z).length_squared() < rr * rr:
						boom = true
						break
				if boom:
					if is_instance_valid(d["mesh"]):
						d["mesh"].queue_free()
					G.deployables.remove_at(i)
					explode(d["pos"], 5.5, 230, d["owner"])
					continue
			if d["life"] <= 0:
				if is_instance_valid(d["mesh"]):
					d["mesh"].queue_free()
				G.deployables.remove_at(i)
			continue
		if d["kind"] == "c5":
			# C5:定时引爆(灯闪烁加速)
			(d["lamp_mat"] as StandardMaterial3D).albedo_color = Color(1, 0.2, 0.1).lerp(Color(1, 1, 0.6), 0.5 + sin(d["t"] * (6 + d["t"] * 4)) * 0.5)
			if d["life"] <= 0:
				if is_instance_valid(d["mesh"]):
					d["mesh"].queue_free()
				G.deployables.remove_at(i)
				explode(d["pos"], 7.0, 250, d["owner"])
			continue
		if d["kind"] == "beacon":
			# 重生信标:呼吸灯(按阵营色脉动,敌军红/友军绿);到期移除
			var bcol: Color = Color(1, 0.2, 0.15) if bool(d.get("en", false)) else Color(0.2, 1, 0.5)
			(d["lamp_mat"] as StandardMaterial3D).albedo_color = bcol.lerp(bcol * 0.35, 0.5 + sin(d["t"] * 3) * 0.5)
			if d["life"] <= 0:
				if is_instance_valid(d["mesh"]):
					d["mesh"].queue_free()
				G.deployables.remove_at(i)
			continue
		(d["ring_mat"] as StandardMaterial3D).albedo_color.a = 0.22 + sin(d["t"] * 4) * 0.13
		if d["tick"] <= 0:
			d["tick"] = 1.0
			# 友军 AI:恢复生命
			for b in G.bots:
				if b.alive and b.team == d["team"] and b.pos.distance_to(d["pos"]) < 5:
					b.health = minf(100, b.health + 14)
					if b.hb_t > 0:
						b.update_health_bar()
			# 玩家:弹药补给 + 生命恢复
			var p = G.player
			if p != null and p.alive and p.team == d["team"] and p.pos.distance_to(d["pos"]) < 5:
				p.heal(14)
				var resupplied := false
				for gun in p.guns:
					if gun.reserve < gun.def.reserve:
						gun.reserve = mini(gun.def.reserve, gun.reserve + int(ceil(gun.def.reserve * 0.2)))
						resupplied = true
				if p.grenades < 2:
					p.grenades += 1
					resupplied = true
				G.hud.hint("弹药包:弹药补给 + 生命恢复中…" if resupplied else "弹药包:生命恢复中…")
		if d["life"] <= 0:
			if is_instance_valid(d["mesh"]):
				d["mesh"].queue_free()
			G.deployables.remove_at(i)


## ============ 爆炸 ============
func explode(pos: Vector3, radius: float, max_dmg: float, attacker) -> void:
	G.effects.explosion(pos, radius)
	var a_team = dget(attacker, "team")
	for b in G.bots:
		if not b.alive:
			continue
		var d: float = b.pos.distance_to(pos)
		if d < radius:
			var is_self: bool = attacker is Object and is_same(b, attacker)
			var dmg: float = max_dmg * (1 - d / radius) * (0.5 if is_self else 1.0)
			if b.team != a_team or is_self:
				b.take_damage(dmg, attacker, false, { "name": "爆炸物", "cn": "爆炸物" })
	# 玩家(过场期间无敌)
	if G.player != null and G.player.alive and not in_cutscene():
		var d2: float = G.player.pos.distance_to(pos)
		if d2 < radius:
			var is_self2: bool = attacker is Object and is_same(G.player, attacker)
			var dmg2: float = max_dmg * (1 - d2 / radius) * (0.5 if is_self2 else 1.0)
			G.player.damage(dmg2, pos, attacker)
	# 载具受爆炸伤害(3 倍)
	for v in G.vehicles:
		if v.dead:
			continue
		var d3: float = v.pos.distance_to(pos)
		if d3 < radius + 1.5:
			v.damage(max_dmg * 3 * (1 - d3 / (radius + 1.5)), attacker)
	# 空中载具受爆炸伤害(2 倍)
	for a in G.aircraft:
		if a.dead:
			continue
		var d4: float = a.pos.distance_to(pos)
		if d4 < radius + 2:
			a.damage(max_dmg * 2 * (1 - d4 / (radius + 2)), attacker)
	# 可破坏建筑受爆炸伤害(2.5 倍)
	for s in G.destructibles:
		if s.dead:
			continue
		var d5: float = s.pos.distance_to(pos)
		if d5 < radius + s.radius:
			s.damage(max_dmg * 2.5 * (1 - d5 / (radius + s.radius)), attacker)


## ============ 击杀 ============
func on_kill(killer, victim, def, head: bool) -> void:
	if victim == null:
		return
	var v_team = victim.team
	# 兵力值(突破模式防守方兵力无限,不扣减)
	if v_team == "us":
		G.tickets["us"] -= 1
	elif not is_inf(G.tickets["ru"]):
		G.tickets["ru"] -= 1
	# 记分
	if is_player(killer):
		G.stats["kills"] += 1
		# 连杀奖励(COD):战役模式禁用(线性关卡无连杀支援)
		if G.mode != "campaign":
			G.streak += 1
			if G.streak == 3 and not G.streak_uav:
				G.streak_uav = true
				G.hud.banner("连杀 3 — UAV 就绪,按 4 呼叫")
				AudioSys.capture(true)
			if G.streak == 5 and not G.streak_arty:
				G.streak_arty = true
				G.hud.banner("连杀 5 — 炮火支援就绪,按 5 呼叫")
				AudioSys.capture(true)
	if killer != null and killer.get("kills") != null and not is_player(killer):
		killer.set("kills", killer.get("kills") + 1)
	if victim == G.player:
		G.stats["deaths"] += 1
	# 播报
	var k_name := "战场"
	var k_team = v_team
	if killer != null:
		if is_player(killer):
			k_name = "你"
		else:
			k_name = killer.get("name") if killer.get("name") != null else "战场"
		k_team = dget(killer, "team", v_team)
	var v_name: String = "你" if is_player(victim) else victim.get("name")
	var w_name: String = dget(def, "cn", dget(def, "name", "爆炸物"))
	G.hud.add_killfeed(k_name, k_team, v_name, v_team, w_name, head, is_player(killer) or is_player(victim))
	# 战役模式:玩家击杀敌人 → 战役控制器计数
	var cm = G.get("campaign")
	if cm != null and cm.running and is_player(killer):
		cm.on_player_kill(victim)
	check_end()


func on_player_death(attacker) -> void:
	G.state = "dead"
	G.streak = 0  # 连杀清零
	G.input_sys.unlock()
	# 战役模式:阵亡计数(达上限判负)
	var cm = G.get("campaign")
	if cm != null and cm.running:
		cm.on_player_death()
	var k_name := "战场"
	if attacker != null:
		if is_player(attacker):
			k_name = "你自己"
		else:
			var prefix := "敌军" if dget(attacker, "team") != G.player.team else "友军"
			k_name = prefix + " · " + str(attacker.get("name") if attacker.get("name") != null else "?")
	get_tree().create_timer(1.2).timeout.connect(func():
		if G.state == "dead":
			G.hud.show_death("被 " + k_name + " 击杀"))
	G.hud.hide_screen("hud")
	on_kill(attacker, G.player, G.player._killed_by_def, false)


## ============ 连杀奖励 ============
func call_uav() -> void:
	if G.mode == "campaign":
		return
	if not G.streak_uav or G.state != "playing":
		return
	G.streak_uav = false
	for b in G.bots:
		if b.team != G.player.team and b.alive:
			b.spotted = 25
	G.hud.banner("UAV 侦察机上线:敌人已显示在小地图")
	AudioSys.capture(true)


func call_artillery() -> void:
	if G.mode == "campaign":
		return
	if not G.streak_arty or G.state != "playing":
		return
	G.streak_arty = false
	# 打击点:准星所指 80m 内,否则 B 点
	var dir: Vector3 = -G.camera.global_transform.basis.z
	var hit = Utils.raycast_world(G.camera.global_position, dir, 80)
	var pos: Vector3
	if hit != null:
		pos = hit["point"]
	elif G.flags.size() > 1:
		pos = G.flags[1].pos
	else:
		pos = Vector3.ZERO
	arty = { "pos": pos, "shells": 14, "interval": 0.0, "t": 0.0 }
	G.hud.banner("炮火支援已呼叫,注意隐蔽!")
	AudioSys.rpg_fire(pos)


func spot_enemies(radius: float, duration: float) -> void:
	var n := 0
	for b in G.bots:
		if b.team != G.player.team and b.alive and b.pos.distance_to(G.player.pos) < radius:
			b.spotted = duration
			n += 1
	if n == 0:
		G.hud.hint("探测器:附近没有敌人")


## 夜视仪索敌驱动:侦察兵夜间地图激活时,每 0.3s 标记所有存活敌方 bot(阵营对比,不硬编码 us)
func _update_night_vision(dt: float) -> void:
	var p = G.player
	if p == null or not p.night_vision or not p.alive:
		nv_spot_t = 0.0
		return
	nv_spot_t += dt
	if nv_spot_t < 0.3:
		return
	nv_spot_t = 0.0
	for b in G.bots:
		if b.alive and b.team != p.team:
			b.spotted = 2.0


## ============ 旗帜与兵力 ============
func update_game(dt: float) -> void:
	if G.state != "playing" and G.state != "dead":
		return
	G.time += dt

	if G.mode == "breakthrough":
		_update_breakthrough(dt)
		_update_bt_zones(dt)
	else:
		_update_conquest(dt)

	# ---- 部署物(工程兵弹药包) ----
	_update_deployables(dt)

	# ---- 炮火支援弹幕 ----
	if arty != null:
		arty["t"] += dt
		arty["interval"] -= dt
		if arty["interval"] <= 0 and arty["shells"] > 0:
			arty["interval"] = 0.45
			arty["shells"] -= 1
			var px: float = arty["pos"].x + Utils.rand(-14, 14)
			var pz: float = arty["pos"].z + Utils.rand(-14, 14)
			var py: float = G.ground_h.call(px, pz) if G.ground_h.is_valid() else 0.0
			explode(Vector3(px, py + 0.3, pz), 7, 95, G.player)
		if arty["shells"] <= 0:
			arty = null
	check_end()
	_update_night_vision(dt)


## 征服模式:旗帜占领 + 多数旗帜流血
func _update_conquest(dt: float) -> void:
	if G.mode == "campaign":
		return  # 战役模式:旗帜系统不参与胜负
	for f in G.flags:
		_update_flag_capture(f, dt, "占领")

	# ---- 多数旗帜流血 ----
	var us_flags := 0
	var ru_flags := 0
	for f in G.flags:
		if f.owner_team == "us":
			us_flags += 1
		elif f.owner_team == "ru":
			ru_flags += 1
	drain_t += dt
	if drain_t >= 1.6:
		drain_t = 0
		if us_flags > ru_flags and us_flags >= 2:
			G.tickets["ru"] -= (us_flags - ru_flags)
		elif ru_flags > us_flags and ru_flags >= 2:
			G.tickets["us"] -= (ru_flags - us_flags)


## 突破模式:仅当前区域可争夺;同时控制全区目标 → 突破,兵力 +100,推进下一区域
func _update_breakthrough(dt: float) -> void:
	if G.mode == "campaign":
		return  # 战役模式:由战役控制器推进
	if G.bt == null:
		return
	var sec: int = G.bt["sector"]
	var sec_flags := []
	for f in G.flags:
		if f.sector == sec:
			sec_flags.append(f)
	for f in sec_flags:
		if not f.locked:
			_update_flag_capture(f, dt, "夺取")
	# 区域突破判定
	if not sec_flags.is_empty() and sec_flags.all(func(f): return f.owner_team == "us"):
		for f in sec_flags:
			f.locked = true
			f.progress = 100
			f.contested = false
		G.bt["sector"] += 1
		G.tickets["us"] += 100
		if G.bt["sector"] >= G.bt["total"]:
			end_match(true)
			return
		# 下一区域解锁(封锁解除,可部署可进入)
		for f in G.flags:
			if f.sector == G.bt["sector"]:
				f.zone_locked = false
				f.contested = false
		G.hud.banner("区域已突破!兵力值 +100 — 向第 " + str(G.bt["sector"] + 1) + "/" + str(G.bt["total"]) + " 区域推进!")
		AudioSys.capture(true)
		# 攻守双方重新规划目标
		for b in G.bots:
			b.pick_objective(true)


## ============ 突破模式:区域封锁(未解锁区域禁止进入/部署) ============
## 前沿封锁线:当前区域与下一区域之间的分界线(双方都不可越过)
func bt_front_z() -> float:
	if G.bt == null:
		return G.world_size - 8.0
	var sec: int = G.bt["sector"]
	var mx := -INF
	var mn := INF
	for f in G.flags:
		if f.sector == sec:
			mx = maxf(mx, f.pos.z)
		elif f.sector == sec + 1:
			mn = minf(mn, f.pos.z)
	if is_inf(mn):
		# 最后区域:前沿止于防守方基地之前,进攻方不能冲进对方出生点
		return (mx + (G.world_size - 16.0)) / 2.0
	return (mx + mn) / 2.0


## 后撤封锁线:防守方不得进入已攻陷区域(进攻方可以自由回到后方)
func bt_rear_z() -> float:
	if G.bt == null:
		return -(G.world_size - 8.0)
	var sec: int = G.bt["sector"]
	var mx := -INF
	var mn := INF
	for f in G.flags:
		if f.sector == sec - 1:
			mx = maxf(mx, f.pos.z)
		elif f.sector == sec:
			mn = minf(mn, f.pos.z)
	if is_inf(mx):
		# 第一区域:后撤线止于进攻方基地之前,防守方不能冲进对方出生点
		return (mn + (-(G.world_size - 16.0))) / 2.0
	return (mx + mn) / 2.0


## 是否越界:进攻方不可越过前沿;防守方不可越过前沿,也不可退回已攻陷区域
func _bt_is_oob(team: String, z: float) -> bool:
	if team == "us":
		return z > bt_front_z()
	return z < bt_rear_z()


## 越界遣返目标点:双方各自当前区域的出生线
func _bt_kick_pos(team: String) -> Vector3:
	if G.bt != null and G.bt_spawns != null:
		var sec: int = mini(G.bt["sector"], G.bt_spawns["att"].size() - 1)
		var arr: Array = G.bt_spawns["att"][sec] if team == "us" else G.bt_spawns["def"][sec]
		if not arr.is_empty():
			return Utils.choice(arr)
	# 兜底:双方基地
	var bz: float = (G.world_size - 16.0) if team == "ru" else -(G.world_size - 16.0)
	return Vector3(0, 0, bz)


## 将越界者遣返回己方战线(载具一并拉回)
func _bt_kick(actor) -> void:
	var target := _bt_kick_pos(actor.team)
	var v = actor.get("vehicle") if actor.get("vehicle") != null else null
	if v != null and is_instance_valid(v) and not v.dead:
		v.pos = target
		v.speed = 0.0
		v.steer = 0.0
		v.mesh.position = target
		actor.pos = target
	else:
		actor.pos = target
		actor.vel = Vector3.ZERO
	if actor == G.player:
		G.hud.hint("已返回战线 — 前方区域尚未开放!")


## 每帧检查:进入封锁区域的玩家/AI 先警告,宽限结束后遣返
func _update_bt_zones(dt: float) -> void:
	if G.mode != "breakthrough" or G.bt == null or G.bt_spawns == null:
		_bt_oob.clear()
		return
	if G.state != "playing":
		_bt_oob.clear()
		return
	var actors: Array = []
	if G.player != null and G.player.alive:
		actors.append(G.player)
	for b in G.bots:
		if b.alive:
			actors.append(b)
	for a in actors:
		var oob: bool = _bt_is_oob(a.team, a.pos.z)
		if not oob:
			if _bt_oob.has(a):
				_bt_oob.erase(a)
			continue
		var t: float = _bt_oob.get(a, 0.0)
		if t <= 0.0:
			t = BT_OOB_PLAYER if a == G.player else BT_OOB_BOT
			if a == G.player:
				G.hud.hint("前方区域尚未开放,即将返回战线!")
		t -= dt
		if t <= 0.0:
			_bt_oob.erase(a)
			_bt_kick(a)
		else:
			_bt_oob[a] = t


## 点位易主 → 在该点位附近部署一辆载具
func _on_point_captured(f: Flag, team: String) -> void:
	if f.veh_slot != null and not f.veh_slot.dead:
		return  # 车位载具仍存活,不重复生成
	# 清理被击毁的旧车位残骸
	if f.veh_slot != null and f.veh_slot.dead:
		f.veh_slot.dispose()
		G.vehicles.erase(f.veh_slot)
		f.veh_slot = null
	# 沿点位环边找落点
	var idx := G.flags.find(f)
	var type = ["apc", "jeep", "aa", "apc", "jeep", "tank"][((0 if idx < 0 else idx) + (2 if team == "ru" else 0)) % 6]
	for tries in 6:
		var a := Utils.rand(TAU)
		var r := Utils.rand(9, 15)
		var px := f.pos.x + cos(a) * r
		var pz := f.pos.z + sin(a) * r
		var blocked := false
		for v in G.vehicles:
			if not v.dead and Vector2(v.pos.x - px, v.pos.z - pz).length() < 5:
				blocked = true
				break
		if blocked:
			continue
		var v := Vehicle.new(px, pz, Utils.rand(TAU), type)
		G.vehicles.append(v)
		G.main.add_child(v)
		f.veh_slot = v
		if team == G.player.team:
			G.hud.hint(f.id + " 点已部署 " + v.def["vehicle_name"])
		return


## 单旗帜占领逻辑(两模式共用)
func _update_flag_capture(f: Flag, dt: float, verb: String) -> void:
	var us := 0
	var ru := 0
	for b in G.bots:
		if not b.alive:
			continue
		if Utils.dist_2d(b.pos.x, b.pos.z, f.pos.x, f.pos.z) < f.radius:
			if b.team == "us":
				us += 1
			else:
				ru += 1
	if G.player.alive and Utils.dist_2d(G.player.pos.x, G.player.pos.z, f.pos.x, f.pos.z) < f.radius:
		if G.player.team == "us":
			us += 1
		else:
			ru += 1
	f.contested = us > 0 and ru > 0
	var prev_owner = f.owner_team
	if us > 0 and ru == 0:
		f.progress = minf(100, f.progress + dt * 22 * mini(us, 3))
	elif ru > 0 and us == 0:
		f.progress = maxf(-100, f.progress - dt * 22 * mini(ru, 3))
	# 归属判定(播报/音效按玩家阵营)
	var my_team: String = G.player.team if G.player != null else "us"
	if f.progress >= 100 and f.owner_team != "us":
		f.owner_team = "us"
		if prev_owner != "us":
			G.hud.banner(("友军" if my_team == "us" else "敌军") + verb + "了 " + f.id + " 点!")
			AudioSys.capture(my_team == "us")
			_on_point_captured(f, "us")
	elif f.progress <= -100 and f.owner_team != "ru":
		f.owner_team = "ru"
		if prev_owner != "ru":
			G.hud.banner(("友军" if my_team == "ru" else "敌军") + ("夺回" if verb == "夺取" else "占领") + "了 " + f.id + " 点!", true)
			AudioSys.capture(my_team == "ru")
			_on_point_captured(f, "ru")
	# 中立化:进度回到 0 附近时清除敌方所有权
	if f.owner_team == "ru" and f.progress > 0:
		f.owner_team = null
	if f.owner_team == "us" and f.progress < 0:
		f.owner_team = null


func check_end() -> void:
	if G.state == "over":
		return
	if G.mode == "campaign":
		return  # 战役胜负由 campaign 控制器负责(避免票数/旗帜提前结束)
	if G.mode == "breakthrough":
		# 进攻方兵力耗尽 → 防守方获胜;全区域攻陷在 _update_breakthrough 中判定
		if G.tickets["us"] <= 0:
			end_match(false)
		return
	if G.tickets["ru"] <= 0:
		end_match(true)
	elif G.tickets["us"] <= 0:
		end_match(false)


func end_match(win: bool) -> void:
	G.state = "over"
	G.input_sys.unlock()
	G.hud.hide_screen("hud")
	G.hud.hide_screen("death")
	G.hud.hide_screen("deploy")
	# 突破模式 win 是世界侧语义(us=进攻方胜利);防守方玩家的胜负取反
	var my_win: bool = win if G.bt_player_side == "att" else not win
	G.hud.show_end(my_win)
	if my_win:
		AudioSys.win()
	else:
		AudioSys.lose()
