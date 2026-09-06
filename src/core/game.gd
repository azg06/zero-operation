class_name Game extends Node
## 征服/突破模式核心逻辑(对应 game.js):命中判定 / 爆炸 / 旗帜占领 / 兵力值 / 击杀

var drain_t := 0.0
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
	# BR 自由混战:同 squad 为友(玩家=队 0),其余皆敌 —— 阵营 team 字段在 BR 下不用于敌我
	if G.mode == "br":
		if Bot.br_same_squad(shooter, actor):
			return {}
	elif actor.team == s_team:
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
	# 实时 3D 部署中换图:先释放旧环境的状态(去雾/遮挡),世界重建后重新应用
	var dep_was_active: bool = G.deployment != null and G.deployment.active
	if dep_was_active:
		G.deployment._setup_view_cleanup(false)
	var _t0 := Time.get_ticks_msec()
	WorldBuilder.build_world(G.world_root, map_id)
	print("[PERF] build_world(%s) 耗时 %d ms" % [map_id, Time.get_ticks_msec() - _t0])
	GraphicsQuality.reapply()  # 环境被重建,重挂画质预设(SSIL/SSR/glow 等)
	if dep_was_active:
		G.deployment._setup_view_cleanup(true)
	for v in G.vehicles:
		v.dispose()
	G.vehicles = []
	# 载具(战役模式纯净:不生成任何可驾驶载具;空中单位见下方征服分支)
	if G.mode != "campaign":
		for s in G.vehicle_spawns:
			var ptype: String = str(s.get("type", "jeep"))
			var vdef: Dictionary = Vehicle.TYPES().get(ptype, Vehicle.TYPES()["jeep"])
			var spawn_p: Vector3 = Vehicle.safe_spawn_pos(Vector3(float(s["x"]), 0.0, float(s["z"])), float(vdef["radius"]))
			G.vehicles.append(Vehicle.new(spawn_p.x, spawn_p.z, float(s["yaw"]), ptype))
	for v in G.vehicles:
		G.main.add_child(v)
	# 清理旧部署物(掩体需连带回收碰撞体,否则新地图会残留隐形墙)
	var had_cover := false
	for d in G.deployables:
		if d.get("kind") == "cover" and d.get("coll") != null:
			G.colliders.erase(d["coll"])
			had_cover = true
		if is_instance_valid(d["mesh"]):
			d["mesh"].queue_free()
	G.deployables = []
	if had_cover:
		Utils.rebuild_collider_grid()
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
		# 小队部署点(选中的队友 bot 实例)同随 bot_manager 重建失效,一并清理防悬空引用
		if G.hud.spawn_mate != null and G.hud.spawn_mate is Object and not is_instance_valid(G.hud.spawn_mate):
			G.hud.spawn_mate = null
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
## 普通玩家流程走异步加载体验;命令行测试/验证流程保持同步,保证自动化结果可复现。
func start_match(mode := "conquest") -> void:
	if OS.get_cmdline_user_args().is_empty():
		_start_match_async(mode)
	else:
		_start_match_sync(mode)


## 异步开局:先展示战术加载/简报层,让 UI 渲染一帧后再执行重型构建,
## 构建完成后不做多余停留,立即交给部署界面。
func _start_match_async(mode := "conquest") -> void:
	var map_id := _pick_match_map(mode)
	if map_id == "":
		return
	if G.menus != null and G.menus.has_method("briefing_setup"):
		G.menus.briefing_setup(map_id, mode)
	await get_tree().process_frame
	_start_match_sync(mode)
	if G.menus != null and G.menus.has_method("finish_loading"):
		G.menus.finish_loading()


## 选出本模式可用地图;返回 "" 表示中止。
func _pick_match_map(mode: String) -> String:
	var pool := []
	for id in MapsData.M():
		var m = MapsData.M()[id]
		if mode == "tdm":
			if m.mode == "tdm" or m.tdm_ok:
				pool.append(id)
		elif (m.mode if m.mode != "" else "conquest") == mode:
			pool.append(id)
	if pool.is_empty():
		push_error("[GAME] 无可用地图(mode=%s),已中止开局" % mode)
		return ""
	var sel: String = G.sel_maps.get(mode, "random")
	var map_id: String = Utils.choice(pool) if sel == "random" else sel
	if not MapsData.M().has(map_id):
		push_error("[GAME] 未知地图 id \"%s\",已中止开局" % map_id)
		return ""
	return map_id


func _start_match_sync(mode := "conquest") -> void:
	var cm = G.get("campaign")
	if cm != null:
		cm.abort()  # 切回任意模式前终止战役残留状态
	# 开局/换模式:退出任何残留的实时 3D 部署状态(如对局结束瞬间死亡)
	if G.deployment != null and G.deployment.active:
		G.deployment.exit()
	if G.hud != null:
		G.hud.clear_campaign_ui()  # 清战役 UI 残留(目标/字幕/点名卡/箭头)
	if mode == "campaign":
		_start_campaign()
		return
	if mode == "tdm" or mode == "br":
		# 门户模式(团队死斗/大逃杀):由 Portal 接管,跳过征服/突破专属初始化
		_start_portal(mode)
		return
	G.mode = mode
	var map_id := _pick_match_map(mode)
	if map_id == "":
		return
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在加载地图", 0.18, map_id.to_upper() + " · 地形与区块构建")
	setup_map(map_id)
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在加载场景", 0.40, "载具、旗帜与战场环境已挂载")
	G.time = 0
	G.stats = { "kills": 0, "deaths": 0 }
	G.streak = 0
	if mode == "breakthrough":
		# 突破模式:进攻方(玩家方)兵力有限,防守方无限
		# 新对局默认玩家为进攻方(世界攻防方向固定 us=进攻 / ru=防守,玩家只选自己的阵营)
		# [BALANCE] 进攻方初始兵力 250→320(+28%):进攻方伤亡天然高于防守方,加码弥补
		G.bt_player_side = "att"
		G.player.team = "us"
		G.tickets = { "us": 320, "ru": INF }
	else:
		G.tickets = { "us": 400, "ru": 400 }
		G.bt = null
	G.state = "deploy"
	# [BALANCE 8/10] 突破模式:防守方(ru)兵力 11→8(削弱 25%),进攻方 11 保持;
	# 地图拉大(360→420)后出生区外推,配合封锁线 45m 出生点保护,消除"出门团灭"
	# [BALANCE] 进攻方人数 23→25,防守方 20→19:进攻方多两人,弥补攻方推进损耗
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在加载作战单位", 0.62, "步兵小队与战场 AI 正在部署")
	G.bot_manager.reset(25, -6 if mode == "breakthrough" else 1)
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在配发武器", 0.78, "玩家装备与小队配置同步")
	G.hud.spawn_point = null
	G.hud.spawn_mate = null
	G.hud.hide_screen("death")
	# 开局即进入实时 3D 战场部署(兵种/武器栏与战场同屏一体);异常兜底退回旧式部署屏
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在初始化战场", 0.92, "实时战术部署镜头就绪")
	if G.deployment == null or not G.deployment.enter_match_deploy():
		G.hud.show_deploy(false)
	AudioSys.start_ambient()


## 门户模式(TDM/BR)开局:地图池过滤与 conquest 一致(mode 字段匹配),
## 不建旗/不设 tickets/不进入部署屏——对局由 PortalManager 模式控制器接管
const PORTAL_BOT_COUNTS := { "tdm": 11, "br": 5 }  # 每队 AI 数(模式可按需调整)


func _start_portal(mode: String) -> void:
	G.mode = mode
	var pool := []
	for id in MapsData.M():
		var m = MapsData.M()[id]
		if mode == "tdm":
			# TDM 地图池:tdm 专属图(tdm_city)+ tdm_ok 主题图(5 张:city/desert/snow/bt_jungle/bt_harbor;
			# 夜战 bt_peak 无 tdm_ok 标记,自动排除)
			if m.mode == "tdm" or m.tdm_ok:
				pool.append(id)
		elif (m.mode if m.mode != "" else "conquest") == mode:
			pool.append(id)
	if mode == "tdm":
		print("[TDM] 地图池(%d张): %s" % [pool.size(), pool])
	var sel: String = G.sel_maps.get(mode, "random")
	# 防御:地图池为空(地图 Agent 尚未提供 tdm/br 地图)时中止开局,不崩溃
	if pool.is_empty():
		push_error("[GAME] 无可用地图(mode=%s),已中止开局" % mode)
		return
	var map_id: String = Utils.choice(pool) if sel == "random" else sel
	if not MapsData.M().has(map_id):
		push_error("[GAME] 未知地图 id \"%s\",已中止开局" % map_id)
		return
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在加载地图", 0.25, map_id.to_upper() + " · 门户模式区域构建")
	setup_map(map_id)
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在加载作战单位", 0.62, "小队与模式规则同步")
	G.time = 0
	G.stats = { "kills": 0, "deaths": 0 }
	G.streak = 0
	G.bt = null
	G.state = "playing"  # 门户模式不进部署屏,出生/重生由模式控制器安排
	G.bot_manager.reset(PORTAL_BOT_COUNTS.get(mode, 5))
	G.hud.spawn_point = null
	G.hud.spawn_mate = null
	G.hud.hide_screen("death")
	G.hud.hide_screen("deploy")
	AudioSys.start_ambient()
	if G.portal == null:
		push_error("[GAME] PortalManager 未装配,门户模式无法启动")
		return
	G.portal.start_mode(mode, map_id)
	# 菜单流无 deploy 屏:玩家出生由模式控制器完成,补 HUD 显示 + 鼠标捕获
	# (与 _start_campaign → deploy() 的契约一致;BR 内部已 lock 此处幂等,
	#  TDM 出生路径原缺 → 首局无 UI/鼠标不捕获,死亡复活后才补齐)
	if G.player != null and G.player.alive:
		G.hud.show_screen("hud")
		G.input_sys.lock()


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
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在加载地图", 0.30, String(ch["map"]).to_upper() + " · 战役区域构建")
	setup_map(ch["map"])
	if G.menus != null and G.menus.has_method("set_loading_stage"):
		G.menus.set_loading_stage("正在初始化战场", 0.75, "战役目标与过场状态同步")
	G.time = 0
	G.stats = { "kills": 0, "deaths": 0 }
	G.streak = 0
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


func deploy(class_id: String, loadout, force_pos: Variant = null) -> void:
	# 直接部署入口(测试/兜底):先退出任何活跃的实时 3D 部署态,防止部署层与战斗相机互相覆盖
	if G.deployment != null and G.deployment.active:
		G.deployment.exit()
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
	# 载具部署(实时 3D 部署系统):直接在指定位置生成
	if force_pos != null:
		G.player.spawn(force_pos)
	else:
		# 小队部署:优先部署在选中小队成员身旁
		var sm = G.hud.spawn_mate
		var sp = G.hud.spawn_point
		# 悬空引用防护(换图后旧旗帜实例已销毁)
		if sp != null and not (sp is Dictionary) and not is_instance_valid(sp):
			sp = null
			G.hud.spawn_point = null
		# 悬空引用防护(换图/重开对局后旧队友 bot 实例已销毁;与 spawn_point 同级别)
		if sm != null and not is_instance_valid(sm):
			sm = null
			G.hud.spawn_mate = null
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
	elif G.mode != "tdm" and G.mode != "br":
		G.hud.banner("夺取并守住旗帜!")  # 门户模式横幅由模式控制器/UI 负责


func redeploy() -> void:
	# 大逃杀:无重生机制,死亡后进入观战(死亡界面"重生"按钮兜底提示)
	if G.mode == "br":
		G.hud.hint("大逃杀:阵亡后进入观战模式(按 Tab 切换视角)")
		return
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
	elif G.mode == "breakthrough" and G.bt != null:
		var bt_pts: Array = bt_deploy_spawn_points(team)
		pos = Utils.choice(bt_pts) if not bt_pts.is_empty() else Utils.choice(G.spawns[team])
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
## [PERF] P0-3:球探针前先做射线 XZ 投影预过滤(命中段外/侧偏必不中者直接跳过)
func fire_hitscan(shooter, def, origin: Vector3, dir: Vector3, muzzle_pos: Vector3, pre: Dictionary = {}) -> void:
	var _bt0 := Time.get_ticks_usec() if (Utils._bench or Utils._bfire_on) else 0
	# [PERF] pre 非空→复用 ballistic_fire 已算出的命中(免二次全量扫描);空→完整扫描
	var hit: Dictionary = pre if not pre.is_empty() else _scan_hitscan(shooter, origin, dir)
	var best_dist: float = hit["dist"]
	var hit_actor = hit.get("actor")
	var hit_head: bool = hit.get("head", false)
	var hit_vehicle = hit.get("vehicle")
	var hit_ds = hit.get("ds")
	var wall = hit.get("wall")
	var hit_dep = hit.get("deployable")
	# ballistic_fire 的 pre 不含部署物:单独补扫,避免枪线穿过医疗箱/信标却只打墙
	if not pre.is_empty() and hit_dep == null:
		var dep_hit2 := _scan_deployable_hit(shooter, origin, dir, best_dist)
		if dep_hit2.get("dep") != null and float(dep_hit2["dist"]) < best_dist:
			best_dist = float(dep_hit2["dist"])
			hit_dep = dep_hit2["dep"]
			hit["dist"] = best_dist
			hit_actor = null
			hit_vehicle = null
			hit_ds = null
	# BR 下玩家可被任何非队友攻击(team 字段不参与判定);常规模式按阵营
	var can_hit_player: bool = dget(shooter, "team") != G.player.team
	if G.mode == "br":
		can_hit_player = not Bot.br_same_squad(shooter, G.player)

	var end: Vector3 = origin + dir * best_dist
	# 曳光弹(从枪口出发)
	G.effects.tracer(muzzle_pos, end, dget(def, "tracer", Color(1, 0.85, 0.63)))

	# 压制效果(BF):敌方子弹掠过玩家附近
	if G.player.alive and can_hit_player and hit_actor != G.player:
		var to_p: Vector3 = G.camera.global_position - origin
		var t := to_p.dot(dir)
		if t > 0 and t < best_dist:
			var closest := (to_p - dir * t).length()
			if closest < 2.5:
				G.player.suppression = minf(1, G.player.suppression + 0.22)
				G.effects.shake(0.08)

	if hit_dep != null:
		# 敌方兵种道具中弹:按武器伤害扣血,击毁后移除
		_damage_deployable(hit_dep, dget(def, "damage", 25.0), shooter, end, -dir)
		if is_player(shooter):
			G.hud.show_hitmarker(false, false)
			AudioSys.hit(false)
	elif hit_actor != null:
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
		# 门户模式伤害登记(助攻判定;模式未实现 on_damage 时跳过)
		_portal_damage(shooter, hit_actor, dmg)
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
	if Utils._bench:
		Utils._bench_fh_t += Time.get_ticks_usec() - _bt0
		Utils._bench_fh_n += 1
	if Utils._bfire_on:
		Utils._bfire_tick("hit", _bt0)


## 扫描弹道上的敌方兵种道具(医疗/补给箱、重生信标、C5、地雷)。
func _scan_deployable_hit(shooter, origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var best: Dictionary = { "dist": max_dist, "dep": null }
	var s_team = dget(shooter, "team")
	for dep in G.deployables:
		if not dep.has("hp"):
			continue
		if s_team != null and dep.get("team") == s_team:
			continue
		var dpos: Vector3 = dep["pos"]
		var drad := 0.45
		var dy := 0.35
		if dep["kind"] == "ammopack" or dep["kind"] == "medpack":
			drad = 0.72
			dy = 0.25
		elif dep["kind"] == "beacon":
			drad = 0.52
			dy = 0.62
		elif dep["kind"] == "cover":
			continue   # 掩体是实体墙:子弹打在碰撞体上,不做球体命中(靠爆炸摧毁)
		var dd := Utils.ray_sphere(origin, dir, dpos + Vector3(0, dy, 0), drad, best["dist"])
		if dd >= 0.0 and dd < float(best["dist"]):
			best = { "dist": dd, "dep": dep }
	return best


## 武器命中敌方兵种道具:扣血并在击毁时销毁
func _damage_deployable(dep: Dictionary, dmg: float, _shooter, hit_pos: Vector3, normal: Vector3) -> void:
	dep["hp"] = float(dep.get("hp", 50.0)) - dmg
	G.effects.impact(hit_pos, normal)
	if float(dep["hp"]) <= 0.0:
		var mesh = dep.get("mesh")
		if mesh != null and is_instance_valid(mesh):
			mesh.queue_free()
		G.effects.explosion(dep["pos"], 2.0)
		G.deployables.erase(dep)


## [PERF] hitscan 几何扫描(从 fire_hitscan 拆出):返回 {dist, actor, head, vehicle, ds, wall, deployable}
## 供 fire_hitscan 与 ballistic_fire 复用,消除每发子弹的双重全量扫描
func _scan_hitscan(shooter, origin: Vector3, dir: Vector3) -> Dictionary:
	var max_dist := 300.0
	# 1. 墙体
	var wall = Utils.raycast_world(origin, dir, max_dist)
	var best_dist: float = wall["dist"] if wall != null else max_dist
	# 1.5 敌方兵种道具(医疗/补给箱、重生信标、C5、地雷):可被枪械直接破坏
	var dep_hit := _scan_deployable_hit(shooter, origin, dir, best_dist)
	var hit_dep = dep_hit.get("dep")
	if dep_hit.get("dist", best_dist) < best_dist:
		best_dist = float(dep_hit["dist"])
	# 2. 角色(敌方)
	var hit_actor = null
	var hit_head := false
	var hit_vehicle = null
	var hit_ds = null
	var s_team = dget(shooter, "team")
	var thr := 0.43 * 0.43  # 最大探针半径 0.42(胸)+FP 余量
	for b in G.bots:
		# [PERF] 径向粗筛:径向≥当前最近命中距必被遮挡,免 ray_xz_miss 静态调用
		var _bx: float = b.pos.x - origin.x
		var _bz: float = b.pos.z - origin.z
		if _bx * _bx + _bz * _bz >= best_dist * best_dist:
			continue
		var miss := -1.0 if Utils._bench_linear else Utils.ray_xz_miss(origin, dir, b.pos.x, b.pos.z, best_dist)
		if miss < 0.0 or miss <= thr:
			var h: Dictionary = _hitscan_actor(b, shooter, s_team, origin, dir, best_dist)
			if not h.is_empty():
				best_dist = h["dist"]
				hit_actor = h["actor"]
				hit_head = h["head"]
	# BR 下玩家可被任何非队友攻击(team 字段不参与判定);常规模式按阵营
	var can_hit_player: bool = s_team != G.player.team
	if G.mode == "br":
		can_hit_player = not Bot.br_same_squad(shooter, G.player)
	if G.player != null and can_hit_player:
		var phit: Dictionary = _hitscan_actor(G.player, shooter, s_team, origin, dir, best_dist)
		if not phit.is_empty():
			best_dist = phit["dist"]
			hit_actor = phit["actor"]
			hit_head = phit["head"]

	# 3. 载具(可被子弹/机炮击伤;不打己方有人载具)
	for v in G.vehicles:
		if v.dead:
			continue
		if v.driver != null and s_team != null and v.driver.team == s_team:
			continue
		var rv: float = v.def["radius"] + 0.35
		var _vx: float = v.pos.x - origin.x
		var _vz: float = v.pos.z - origin.z
		if _vx * _vx + _vz * _vz >= best_dist * best_dist:
			continue
		var mv := -1.0 if Utils._bench_linear else Utils.ray_xz_miss(origin, dir, v.pos.x, v.pos.z, best_dist)
		if mv < 0.0 or mv <= rv * rv:
			var v_pos := Vector3(v.pos.x, v.pos.y + 1.2, v.pos.z)
			var d := Utils.ray_sphere(origin, dir, v_pos, rv, best_dist)
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
		var _ax2: float = a.pos.x - origin.x
		var _az2: float = a.pos.z - origin.z
		if _ax2 * _ax2 + _az2 * _az2 >= best_dist * best_dist:
			continue
		var ma := -1.0 if Utils._bench_linear else Utils.ray_xz_miss(origin, dir, a.pos.x, a.pos.z, best_dist)
		if ma < 0.0 or ma <= a.radius * a.radius:
			var d2 := Utils.ray_sphere(origin, dir, a.pos, a.radius, best_dist)
			if d2 >= 0:
				best_dist = d2
				hit_vehicle = a
				hit_actor = null
	# 5. 可破坏物(油桶/木箱/棚屋,子弹可击毁)
	for ds in G.destructibles:
		if ds.dead:
			continue
		# 粗筛参考点用盒近面:ds.pos 是盒中心(沿射线投影 > 盒面 best 会被误杀——油箱打不坏回归)
		var _cc: Vector3 = ds.collider.get_center()
		var _hx: float = ds.collider.size.x * 0.5
		var _hz: float = ds.collider.size.z * 0.5
		var _nfx: float = _cc.x - dir.x * _hx
		var _nfz: float = _cc.z - dir.z * _hz
		var _dx: float = _nfx - origin.x
		var _dz: float = _nfz - origin.z
		if _dx * _dx + _dz * _dz >= best_dist * best_dist:
			continue
		var md := -1.0 if Utils._bench_linear else Utils.ray_xz_miss(origin, dir, _nfx, _nfz, best_dist)
		if md < 0.0 or md <= ds.radius * ds.radius:
			# 用真实碰撞盒判定(球半径可能小于盒半对角,球面判定会漏——战役油箱等打不坏)
			var d3 := Utils.ray_box(origin, dir, ds.collider, best_dist)
			if d3 >= 0:
				best_dist = d3
				hit_ds = ds
				hit_actor = null
				hit_vehicle = null
	return { "dist": best_dist, "actor": hit_actor, "head": hit_head, "vehicle": hit_vehicle, "ds": hit_ds, "wall": wall, "deployable": hit_dep }


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
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	# 高科技雷达重生信标:三脚底座 + 设备舱 + 旋转相控阵天线 + 顶部状态灯
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color.html("#202632")
	dark_mat.roughness = 0.45
	dark_mat.metallic = 0.65
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color.html("#5c6874")
	metal_mat.roughness = 0.35
	metal_mat.metallic = 0.8
	var base := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.17
	bcm.bottom_radius = 0.24
	bcm.height = 0.10
	bcm.radial_segments = 12
	base.mesh = bcm
	base.material_override = dark_mat
	base.position.y = 0.05
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(base)
	for i in 3:
		var a := float(i) * TAU / 3.0
		var leg := MeshInstance3D.new()
		var lcm := CylinderMesh.new()
		lcm.top_radius = 0.012
		lcm.bottom_radius = 0.016
		lcm.height = 0.18
		leg.mesh = lcm
		leg.material_override = metal_mat
		leg.position = Vector3(cos(a) * 0.13, 0.10, sin(a) * 0.13)
		leg.rotation.z = cos(a) * 0.45
		leg.rotation.x = -sin(a) * 0.45
		g.add_child(leg)
	var mast := MeshInstance3D.new()
	var mcm := CylinderMesh.new()
	mcm.top_radius = 0.024
	mcm.bottom_radius = 0.032
	mcm.height = 0.72
	mast.mesh = mcm
	mast.material_override = metal_mat
	mast.position.y = 0.48
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(mast)
	var body := MeshInstance3D.new()
	var bodm := BoxMesh.new()
	bodm.size = Vector3(0.34, 0.30, 0.26)
	body.mesh = bodm
	body.material_override = dark_mat
	body.position.y = 0.88
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(body)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 0.88, 0)
	var panel := MeshInstance3D.new()
	var pnl := BoxMesh.new()
	pnl.size = Vector3(0.52, 0.025, 0.16)
	panel.mesh = pnl
	panel.material_override = metal_mat
	rotor.add_child(panel)
	var panel2 := panel.duplicate() as MeshInstance3D
	panel2.rotation.y = PI / 2.0
	rotor.add_child(panel2)
	g.add_child(rotor)
	var antenna := MeshInstance3D.new()
	var ant := CylinderMesh.new()
	ant.top_radius = 0.004
	ant.bottom_radius = 0.007
	ant.height = 0.26
	antenna.mesh = ant
	antenna.material_override = metal_mat
	antenna.position.y = 1.12
	g.add_child(antenna)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.06
	lm.height = 0.12
	lamp.mesh = lm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1, 0.2, 0.15) if en else Color(0.2, 1, 0.5)
	lamp.material_override = lamp_mat
	lamp.position.y = 1.26
	g.add_child(lamp)
	g.position = pos
	G.world_root.add_child(g)
	G.deployables.append({ "kind": "beacon", "mesh": g, "lamp_mat": lamp_mat, "rotor": rotor,
		"team": p_owner.team, "en": en, "owner": p_owner, "pos": pos, "life": 90.0, "tick": 0.0, "t": 0.0, "arm": 0.0, "hp": 80.0 })
	AudioSys.reload(1)
	if p_owner == G.player:
		G.hud.hint("重生信标已部署:小队可在此重生(90 秒)")
		G.hud.event("◆", "SQUAD SPAWN READY", "重生信标已部署 · 小队可在此重生", Color(0.16, 0.78, 0.86))


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
		"team": p_owner.team, "owner": p_owner, "pos": pos, "life": 4.0, "tick": 0.0, "t": 0.0, "arm": 0.0, "hp": 40.0 })
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
		"team": p_owner.team, "owner": p_owner, "pos": pos, "life": 90.0, "tick": 0.0, "t": 0.0, "arm": 1.5, "hp": 50.0 })
	AudioSys.reload(0)
	if p_owner == G.player:
		G.hud.hint("反坦克地雷已部署:敌方载具靠近即爆")


## ============ 支援兵补给包(医疗包=只治疗 / 弹药包=只补弹,两种功能不再合一) ============
func spawn_med_pack(p_owner) -> void:
	_spawn_supply_pack(p_owner, "medpack")


func spawn_ammo_pack(p_owner) -> void:
	_spawn_supply_pack(p_owner, "ammopack")


func _spawn_supply_pack(p_owner, kind: String) -> void:
	var med: bool = kind == "medpack"
	var pos: Vector3 = _deploy_front_pos(p_owner, 1.4, 0.0)
	# 建模:补给箱(箱体 + 提手 + 医疗十字/弹药双横标 + 指示灯 + 补给圈)
	var g := Node3D.new()
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.78, 0.46, 0.56)
	box.mesh = bm
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color.html("#5a2418") if en else (Color.html("#3f5540") if med else Color.html("#5a4a22"))
	box_mat.roughness = 0.75
	box_mat.metallic = 0.1
	box.material_override = box_mat
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(box)
	# 顶部提手
	var handle := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.16, 0.05, 0.30)
	handle.mesh = hbm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color.html("#2c3338")
	hmat.roughness = 0.4
	hmat.metallic = 0.7
	handle.material_override = hmat
	handle.position.y = 0.28
	g.add_child(handle)
	# 正面标识:医疗包=白十字 / 弹药包=琥珀双横条
	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.95, 0.97, 1.0) if med else Color(1.0, 0.84, 0.32)
	cross_mat.roughness = 0.5
	var cv := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.10, 0.34, 0.02) if med else Vector3(0.34, 0.08, 0.02)
	cv.mesh = cbm
	cv.material_override = cross_mat
	cv.position = Vector3(0.36, 0.12, 0.29) if med else Vector3(0.36, 0.01, 0.29)
	g.add_child(cv)
	var ch := MeshInstance3D.new()
	var chm := BoxMesh.new()
	chm.size = Vector3(0.34, 0.10, 0.02) if med else Vector3(0.34, 0.08, 0.02)
	ch.mesh = chm
	ch.material_override = cross_mat
	ch.position = Vector3(0.36, 0.12, 0.29) if med else Vector3(0.36, 0.19, 0.29)
	g.add_child(ch)
	# 顶部状态灯
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.035
	lm.height = 0.07
	lamp.mesh = lm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1, 0.22, 0.16) if en else Color(0.3, 1, 0.55)
	lamp.material_override = lamp_mat
	lamp.position.y = 0.33
	g.add_child(lamp)
	var ring := MeshInstance3D.new()
	ring.mesh = Flag.make_ring_mesh(6.2, 6.5, 48)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1, 0.28, 0.2, 0.35) if en else (Color(0.62, 0.88, 0.54, 0.35) if med else Color(1.0, 0.82, 0.35, 0.35))
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	ring.position.y = 0.06
	g.add_child(ring)
	g.position = pos
	G.world_root.add_child(g)
	G.deployables.append({ "kind": kind, "mesh": g, "ring_mat": ring_mat, "lamp_mat": lamp_mat,
		"team": p_owner.team, "pos": pos, "life": 30.0, "tick": 0.0, "t": 0.0, "hp": 100.0 })
	AudioSys.reload(1)
	if p_owner == G.player:
		G.hud.hint("医疗包已部署:圈内友军持续恢复生命(不补弹)" if med
			else "弹药包已部署:圈内友军持续补充弹药与手雷(不回血)")


## ============ 工程兵掩体制造器(部署物:半身高装甲掩体,真实碰撞体可挡枪) ============
## 返回 false = 位置不合法(贴墙/悬空/已有掩体),调用方不扣技能次数。
## 掩体高 1.15m(半身高):蹲下完全掩护,站起可越顶射击;碰撞体入 G.colliders,
## 玩家/AI/子弹/视线全部按静态墙体处理(与战役封锁带同一套机制)。
func spawn_cover(p_owner) -> bool:
	var pos: Vector3 = _deploy_front_pos(p_owner, 2.0, 0.0)
	var yaw: float = float(p_owner.yaw)
	# 合法性:前方需要足够空地(不许怼在墙里),且不与已有掩体重叠
	if Utils.raycast_world(p_owner.pos + Vector3(0, 1.0, 0),
			Vector3(-sin(yaw), 0, -cos(yaw)), 2.4) != null:
		if p_owner == G.player:
			G.hud.hint("前方空间不足,无法架设掩体")
		return false
	for d in G.deployables:
		if d["kind"] == "cover" and Vector2(d["pos"].x - pos.x, d["pos"].z - pos.z).length() < 1.6:
			if p_owner == G.player:
				G.hud.hint("此处已有掩体")
			return false
	var W := 1.9        # 掩体宽度
	var H := 1.15       # 半身高
	var T := 0.34       # 厚度
	var en: bool = p_owner.team != (G.player.team if G.player != null else "us")
	var g := Node3D.new()
	# 主装甲板 + 上沿加强条 + 两侧支腿 + 沙袋垛(视觉分层,不额外注册碰撞)
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color.html("#4a3a24") if en else Color.html("#3d4a35")
	plate_mat.roughness = 0.85
	plate_mat.metallic = 0.25
	var plate := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(W, H, T * 0.55)
	plate.mesh = pbm
	plate.material_override = plate_mat
	plate.position = Vector3(0, H * 0.5, 0)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(plate)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color.html("#2b3036")
	rail_mat.roughness = 0.5
	rail_mat.metallic = 0.6
	var rail := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(W + 0.06, 0.1, T * 0.8)
	rail.mesh = rbm
	rail.material_override = rail_mat
	rail.position = Vector3(0, H + 0.04, 0)
	g.add_child(rail)
	# 沙袋垛(前侧三段,给掩体体积感)
	var bag_mat := StandardMaterial3D.new()
	bag_mat.albedo_color = Color.html("#6b5a3c") if not en else Color.html("#6b4a3c")
	bag_mat.roughness = 0.95
	for bi in 3:
		var bag := MeshInstance3D.new()
		var bagm := BoxMesh.new()
		bagm.size = Vector3(W / 3.0 - 0.06, 0.28, T * 0.9)
		bag.mesh = bagm
		bag.material_override = bag_mat
		bag.position = Vector3(-W / 3.0 + float(bi) * (W / 3.0), 0.15, -T * 0.32)
		bag.rotation.z = Utils.rand(-0.05, 0.05)
		g.add_child(bag)
	# 支腿
	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lbm := BoxMesh.new()
		lbm.size = Vector3(0.08, H * 0.9, T)
		leg.mesh = lbm
		leg.material_override = rail_mat
		leg.position = Vector3(sx * (W * 0.5 - 0.06), H * 0.45, T * 0.28)
		g.add_child(leg)
	# 阵营识别灯
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.032
	lm.height = 0.064
	lamp.mesh = lm
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1, 0.25, 0.18) if en else Color(0.35, 1, 0.6)
	lamp.material_override = lamp_mat
	lamp.position = Vector3(W * 0.5 - 0.12, H + 0.1, 0)
	g.add_child(lamp)
	g.position = pos
	g.rotation.y = yaw
	G.world_root.add_child(g)
	# 碰撞体:按世界轴对齐的 AABB 包住旋转后的板面(略放宽,保证挡枪不漏)
	var hw: float = absf(cos(yaw)) * W * 0.5 + absf(sin(yaw)) * T * 0.5
	var hd: float = absf(sin(yaw)) * W * 0.5 + absf(cos(yaw)) * T * 0.5
	var coll := AABB(Vector3(pos.x - hw, pos.y, pos.z - hd), Vector3(hw * 2.0, H, hd * 2.0))
	G.colliders.append(coll)
	Utils.rebuild_collider_grid()   # 射线/视线/避障立即识别新掩体
	G.deployables.append({ "kind": "cover", "mesh": g, "lamp_mat": lamp_mat, "coll": coll,
		"team": p_owner.team, "owner": p_owner, "pos": pos, "life": 150.0, "tick": 0.0, "t": 0.0, "hp": 320.0 })
	AudioSys.reload(0)
	if p_owner == G.player:
		G.hud.hint("装甲掩体已架设:蹲下完全掩护,站起越顶射击")
	return true


## 掩体移除:碰撞体按值出栈并重建网格,视觉件销毁(与战役封锁带清理同一套流程)
func _remove_cover(d: Dictionary) -> void:
	var coll = d.get("coll")
	if coll != null:
		G.colliders.erase(coll)
		Utils.rebuild_collider_grid()
	var mesh = d.get("mesh")
	if mesh != null and is_instance_valid(mesh):
		mesh.queue_free()
	G.effects.explosion(d["pos"] + Vector3(0, 0.5, 0), 1.6)


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
			# 重生信标:雷达天线持续旋转,呼吸灯(按阵营色脉动,敌军红/友军绿);到期移除
			var bcol: Color = Color(1, 0.2, 0.15) if bool(d.get("en", false)) else Color(0.2, 1, 0.5)
			(d["lamp_mat"] as StandardMaterial3D).albedo_color = bcol.lerp(bcol * 0.35, 0.5 + sin(d["t"] * 3) * 0.5)
			var rotor = d.get("rotor")
			if rotor != null and is_instance_valid(rotor):
				rotor.rotation.y += dt * 2.6
			if d["life"] <= 0:
				if is_instance_valid(d["mesh"]):
					d["mesh"].queue_free()
				G.deployables.remove_at(i)
			continue
		if d["kind"] == "cover":
			# 掩体:静态障碍(碰撞体已注册进 G.colliders),到期或被击毁时连同碰撞体一起移除
			if float(d.get("hp", 1.0)) <= 0.0 or d["life"] <= 0:
				_remove_cover(d)
				G.deployables.remove_at(i)
			continue
		(d["ring_mat"] as StandardMaterial3D).albedo_color.a = 0.22 + sin(d["t"] * 4) * 0.13
		var alamp = d.get("lamp_mat")
		if alamp != null:
			(alamp as StandardMaterial3D).albedo_color.a = 0.75 + sin(d["t"] * 5) * 0.25
		if d["tick"] <= 0:
			d["tick"] = 1.0
			var is_med: bool = d["kind"] == "medpack"
			# 友军 AI:医疗包恢复生命;弹药包为附近 AI 补充当前弹匣(两者功能分离)
			if is_med:
				for b in G.bots:
					if b.alive and b.team == d["team"] and b.pos.distance_to(d["pos"]) < 6.5:
						b.health = minf(100, b.health + 14)
						if b.hb_t > 0:
							b.update_health_bar()
			else:
				for b in G.bots:
					if b.alive and b.team == d["team"] and b.pos.distance_to(d["pos"]) < 6.5 \
							and b.ammo < b.def.mag:
						b.ammo = mini(b.def.mag, b.ammo + maxi(1, int(ceil(float(b.def.mag) * 0.22))))
			# 玩家:医疗包只治疗 / 弹药包只补弹(两种功能不合一)
			var p = G.player
			if p != null and p.alive and p.team == d["team"] and p.pos.distance_to(d["pos"]) < 6.5:
				if is_med:
					if p.health < 100.0:
						p.heal(14)
						G.hud.hint("医疗包:生命恢复中…")
				else:
					var resupplied := false
					for gun in p.guns:
						if gun.reserve < gun.def.reserve:
							gun.reserve = mini(gun.def.reserve, gun.reserve + int(ceil(gun.def.reserve * 0.2)))
							resupplied = true
					if p.grenades < 2:
						p.grenades += 1
						resupplied = true
					if resupplied:
						G.hud.hint("弹药包:弹药补给中…")
		if d["life"] <= 0:
			if is_instance_valid(d["mesh"]):
				d["mesh"].queue_free()
			G.deployables.remove_at(i)


## ============ 爆炸 ============
func explode(pos: Vector3, radius: float, max_dmg: float, attacker) -> void:
	G.effects.explosion(pos, radius)
	var a_team = dget(attacker, "team")
	# 部署掩体:爆炸是唯一能拆掉它的手段(子弹打在实体碰撞体上)
	for ci in range(G.deployables.size() - 1, -1, -1):
		var dep: Dictionary = G.deployables[ci]
		if dep.get("kind") != "cover":
			continue
		var dc: float = dep["pos"].distance_to(pos)
		if dc < radius + 1.2:
			dep["hp"] = float(dep.get("hp", 320.0)) - max_dmg * (1.0 - dc / (radius + 1.2))
			if float(dep["hp"]) <= 0.0:
				_remove_cover(dep)
				G.deployables.remove_at(ci)
	for b in G.bots:
		if not b.alive:
			continue
		var d: float = b.pos.distance_to(pos)
		if d < radius:
			var is_self: bool = attacker is Object and is_same(b, attacker)
			var dmg: float = max_dmg * (1 - d / radius) * (0.5 if is_self else 1.0)
			# BR:同 squad 免伤(自己手雷例外);常规模式按阵营
			var can_hurt: bool = b.team != a_team or is_self
			if G.mode == "br":
				can_hurt = is_self or not Bot.br_same_squad(attacker, b)
			if can_hurt:
				b.take_damage(dmg, attacker, false, { "name": "爆炸物", "cn": "爆炸物" })
				_portal_damage(attacker, b, dmg)
	# 玩家(过场期间无敌)
	if G.player != null and G.player.alive and not in_cutscene():
		var d2: float = G.player.pos.distance_to(pos)
		if d2 < radius:
			var is_self2: bool = attacker is Object and is_same(G.player, attacker)
			# BR:队友手雷不伤玩家(自己手雷照常 0.5 倍)
			var friendly_splash: bool = not is_self2 and G.mode == "br" and Bot.br_same_squad(attacker, G.player)
			if not friendly_splash:
				var dmg2: float = max_dmg * (1 - d2 / radius) * (0.5 if is_self2 else 1.0)
				G.player.damage(dmg2, pos, attacker)
				_portal_damage(attacker, G.player, dmg2)
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
## 门户模式伤害登记(bot.take_damage / player.damage 的等价拦截点,供模式助攻判定;
## 模式控制器未实现 on_damage 时自动跳过)
func _portal_damage(attacker, victim, amount: float) -> void:
	var pm = G.portal
	if pm == null or pm.active == null:
		return
	if pm.active.has_method("on_damage"):
		pm.active.on_damage(attacker, victim, amount)


func on_kill(killer, victim, def, head: bool) -> void:
	if victim == null:
		return
	var v_team = victim.team
	# 门户模式(TDM/BR):胜负由模式控制器判定,不扣减征服兵力票
	var pm = G.portal
	var in_portal: bool = pm != null and pm.active != null
	# 开局 3D 部署(state=deploy)期间 AI 已实时交战,但兵力值/胜负判定须等对局正式开始
	var in_match: bool = G.state == "playing" or G.state == "dead"
	# 实时 3D 战场部署(征服/突破):玩家死亡后进入部署观察/选择出生点期间,
	# 世界仍在实时交战;此时 NPC/玩家死亡也必须正常扣票,不能因为 state=deploy 跳过。
	var battlefield_live: bool = G.deployment != null and G.deployment.active
	if G.state == "deploy" and battlefield_live:
		in_match = true
	if not in_portal and in_match:
		# 兵力值(突破模式防守方兵力无限,不扣减)
		# [BALANCE 24v24] 击杀扣票 1→0.5:48 人局击杀频率翻倍,扣票减半抵消,
		# 保证 400 票对局时长与 12v12 时代一致,避免敌方兵力过快耗尽
		if v_team == "us":
			G.tickets["us"] -= 0.5
		elif not is_inf(G.tickets["ru"]):
			G.tickets["ru"] -= 0.5
	# 记分
	if is_player(killer):
		G.stats["kills"] += 1
	# 连杀奖励已全局取消(原:连杀 3 → UAV、连杀 5 → 炮火支援;征服/突破/门户/战争故事全模式不再授予)
	# G.streak 仍累计供连杀指示展示;UAV/炮火入口(按键 4/5)与状态位已随清理移除
	if G.mode != "campaign":
		G.streak += 1
	if killer != null and killer.get("kills") != null and not is_player(killer):
		killer.set("kills", killer.get("kills") + 1)
	if victim == G.player:
		G.stats["deaths"] += 1
	# 播报
	var k_name := "战场"
	var k_team = v_team
	if killer != null:
		k_name = Bot.display_name(killer, "战场")
		k_team = dget(killer, "team", v_team)
	var v_name: String = Bot.display_name(victim, "")
	var w_name: String = dget(def, "cn", dget(def, "name", "爆炸物"))
	G.hud.add_killfeed(k_name, k_team, v_name, v_team, w_name, head, is_player(killer) or is_player(victim))
	# 门户模式(TDM/BR):击杀事件转发给模式控制器(GameMode_Portal 契约:
	# on_player_killed(killer, victim, head);玩家阵亡经 on_player_death 汇入)
	if in_portal:
		pm.active.on_player_killed(killer, victim, head)
	# 战役模式:玩家击杀敌人 → 战役控制器计数
	var cm = G.get("campaign")
	if cm != null and cm.running and is_player(killer):
		cm.on_player_kill(victim)
	check_end()


func on_player_death(attacker) -> void:
	G.state = "dead"
	G.streak = 0  # 连杀清零
	G.input_sys.unlock()
	# 实时 3D 战场部署(征服/突破):死亡即进入高空观察部署模式,世界继续实时运行
	if G.deployment != null and (G.mode == "conquest" or G.mode == "breakthrough"):
		G.deployment.enter()
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
			k_name = prefix + " · " + Bot.display_name(attacker, "?")
	get_tree().create_timer(1.2).timeout.connect(func():
		if G.state == "dead":
			if G.deployment != null and G.deployment.active:
				# 实时 3D 部署:死亡信息并入顶部提示(死亡面板让位于同屏装备栏)
				G.hud.hint("被 " + k_name + " 击杀 · 左键拖动地图选择部署点")
			else:
				G.hud.show_death("被 " + k_name + " 击杀"))
	G.hud.hide_screen("hud")
	on_kill(attacker, G.player, G.player._killed_by_def, false)


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
		# 开局 3D 部署(state=deploy):战场实时运行但不动时间/兵力 —— 仅占点与部署物
		# (AI 已实时交战并夺旗,玩家可部署到实时变化的占领点)
		if G.state == "deploy" and G.deployment != null and G.deployment.active:
			for f in G.flags:
				if f != null and not f.locked and not f.zone_locked:
					_update_flag_capture(f, dt, "占领")
			_update_deployables(dt)
		return
	G.time += dt

	# 门户模式(TDM/BR):游戏逻辑由 Portal 模式控制器驱动(跳过旗帜/票数体系)
	var pm = G.portal
	if pm != null and pm.active != null:
		pm.active.tick(dt)
		_update_deployables(dt)
		_update_night_vision(dt)
		return

	if G.mode == "breakthrough":
		_update_breakthrough(dt)
		_update_bt_zones(dt)
	else:
		_update_conquest(dt)

	# ---- 部署物(工程兵弹药包) ----
	_update_deployables(dt)
	check_end()
	_update_night_vision(dt)


## 征服模式:旗帜占领 + 多数旗帜流血
func _update_conquest(dt: float) -> void:
	if G.mode == "campaign" or G.mode == "br":
		return  # 战役模式:旗帜系统不参与胜负;大逃杀:胜负由 BR 模式判定(旗帜仅作 AI 目标点)
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
	# [BALANCE 24v24] 流血间隔 1.6→2.4s:48 人局点差流血同样翻倍,放缓维持对局时长
	if drain_t >= 2.4:
		drain_t = 0
		if us_flags > ru_flags and us_flags >= 2:
			G.tickets["ru"] -= (us_flags - ru_flags)
		elif ru_flags > us_flags and ru_flags >= 2:
			G.tickets["us"] -= (ru_flags - us_flags)


## 突破模式:仅当前区域可争夺;同时控制全区目标 → 突破,兵力 +120,推进下一区域
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
		G.tickets["us"] += 120  # [BALANCE] 区域突破奖励 100→120(进攻方持续投入的回报)
		if G.bt["sector"] >= G.bt["total"]:
			end_match(true)
			return
		# 下一区域解锁(封锁解除,可部署可进入)
		for f in G.flags:
			if f.sector == G.bt["sector"]:
				f.zone_locked = false
				f.contested = false
		G.hud.banner("区域已突破!兵力值 +120 — 向第 " + str(G.bt["sector"] + 1) + "/" + str(G.bt["total"]) + " 区域推进!")
		G.hud.event("◈", "SECTOR BREACHED",
			"区域 " + str(G.bt["sector"] + 1) + "/" + str(G.bt["total"]) + " 已突破 · 兵力 +120",
			Color(0.05, 0.62, 0.6))
		AudioSys.capture(true)
		# 攻守双方重新规划目标
		for b in G.bots:
			b.pick_objective(true)



## ============ 突破模式:动态部署点规则 ============
## 3 个区域 + 双方基地,按当前交战区域推进:
##   sector 0(第一区域):攻方只能在我方基地,守方只在第二区域 A 点
##   sector 1(第二区域):攻方可在第一区域 A/B,守方只在第三区域 A/B
##   sector 2(第三区域):攻方只在第二区域 A 点,守方只在守方基地
## 这些规则同时用于 AI 出生、玩家 3D 部署与 2D 部署地图。


func _bt_flag_points(sector: int, id_filter := "") -> Array:
	var pts: Array = []
	for f in G.flags:
		if f == null or not is_instance_valid(f):
			continue
		if f.sector != sector:
			continue
		if id_filter != "" and f.id != id_filter:
			continue
		pts.append(f.pos)
	return pts


func bt_deploy_spawn_points(team: String) -> Array:
	if G.mode != "breakthrough" or G.bt == null:
		return G.spawns.get(team, [])
	var sec: int = G.bt["sector"]
	if team == "us":
		# 已占领的点都可以作为友方部署点(战地式:占点即可在该点重生)
		var owned_pts: Array = []
		for f in G.flags:
			if f != null and is_instance_valid(f) and f.owner_team == "us":
				owned_pts.append(f.pos)
		if not owned_pts.is_empty():
			return owned_pts
		match sec:
			0:
				return G.spawns.get("us", [])
			1:
				return _bt_flag_points(0)
			2:
				return _bt_flag_points(1, "A")
	else:
		match sec:
			0:
				return _bt_flag_points(1, "A")
			1:
				return _bt_flag_points(2)
			2:
				return G.spawns.get("ru", [])
	return G.spawns.get(team, [])


## 部署点合法性(玩家 3D/2D 部署 UI 共用)
func bt_deploy_allowed(team: String, kind: String, ref: Variant) -> bool:
	if G.mode != "breakthrough" or G.bt == null:
		return true
	var sec: int = G.bt["sector"]
	match kind:
		"base":
			if team == "us":
				return sec == 0
			return sec == 2
		"flag":
			var f = ref
			if f == null or not is_instance_valid(f):
				return false
			if team == "us":
				# 战地规则:只要友方已占领该点,就可以在该点部署
				if f.owner_team == "us":
					return true
				match sec:
					0:
						return false
					1:
						return f.sector == 0
					2:
						return f.sector == 1 and f.id == "A"
			else:
				match sec:
					0:
						return f.sector == 1 and f.id == "A"
					1:
						return f.sector == 2
					2:
						return false
	return true

## ============ 突破模式:区域封锁(未解锁区域禁止进入/部署) ============
## 前沿封锁线:当前区域与下一区域之间的分界线(双方都不可越过)
## [BALANCE 8/10] 最后区域前沿止于防守方基地前 45m(原公式允许进攻方冲进防守方出生点)
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
		return mx + 45.0
	return (mx + mn) / 2.0


## 后撤封锁线:防守方不得进入已攻陷区域(进攻方可以自由回到后方)
## [BALANCE 8/10] 第一区域后撤线止于进攻方基地前 45m(原公式允许防守方 AI 冲进进攻方出生点)
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
		return mn - 45.0
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
			G.hud.event("▲", "SECTOR " + f.id + " CAPTURED",
				("友军" if my_team == "us" else "敌军") + verb + "了 " + f.id + " 点",
				Color(0.05, 0.62, 0.6))
			AudioSys.capture(my_team == "us")
			_on_point_captured(f, "us")
	elif f.progress <= -100 and f.owner_team != "ru":
		f.owner_team = "ru"
		if prev_owner != "ru":
			G.hud.banner(("友军" if my_team == "ru" else "敌军") + ("夺回" if verb == "夺取" else "占领") + "了 " + f.id + " 点!", true)
			G.hud.event("▼", "SECTOR " + f.id + " LOST",
				("敌军" if my_team == "us" else "友军") + "占领了 " + f.id + " 点",
				Color(1.0, 0.55, 0.22))
			AudioSys.capture(my_team == "ru")
			_on_point_captured(f, "ru")
	# 中立化:进度回到 0 附近时清除敌方所有权
	if f.owner_team == "ru" and f.progress > 0:
		f.owner_team = null
	if f.owner_team == "us" and f.progress < 0:
		f.owner_team = null


func check_end() -> void:
	if G.state == "over" or G.state == "end":
		return
	# 开局 3D 部署(state=deploy)期间不判胜负(对局尚未正式开始);
	# 但玩家死亡后的实时部署观察/选点期间战场仍实时运行,票数耗尽应正常结算。
	if G.state != "playing" and G.state != "dead":
		var battle_live: bool = G.deployment != null and G.deployment.active
		if not (G.state == "deploy" and battle_live):
			return
	if G.mode == "campaign":
		return  # 战役胜负由 campaign 控制器负责(避免票数/旗帜提前结束)
	if G.mode == "tdm" or G.mode == "br":
		return  # 门户模式胜负由模式控制器判定(经 G.portal.end_match 收尾)
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
	# 对局结束:立即退出部署观察层(结算屏接管)
	if G.deployment != null and G.deployment.active:
		G.deployment.exit()
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
