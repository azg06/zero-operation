class_name GameMode_BR extends GameMode_Portal
## 大逃杀(Battle Royale)完整玩法(纯 GDScript,Godot 4.7)
##
## 流程:lobby(10s 倒计时)→ 飞机航线跳伞 → 搜物资 → 缩圈(随机第一圈 → 逐级内缩)
##       → 最后存活的队伍获胜。全程 100 名参赛者(99 bot + 玩家,25 队 × 4 人)。
## BR 改造(本 Agent 五项):
##   ① menus.br_selected_class 兵种选择(侦察兵禁重生信标,玩家/bot 均禁用)
##   ② 飞机上玩家模型隐藏,跳出显示 + 背伞包/开伞伞面(程序化建模,玩家/bot 均有)
##   ③ 开局仅手枪(玩家 br_strip_inventory;bot 强制 m1911,落地搜物资换枪)
##   ④ 100 人 = 玩家 + 99 bot,25 队 × 4 人(bot.gd _br_same_squad 同队非敌)
##   ⑤ 毒圈第一圈中心每局随机(不再固定 drop_zone;后续缩圈保留随机内缩)
##
## 与并行 Agent 的分工(防御对接):
##   - 地图 Agent:br_valley 的 maps_data extra(loot_points/vehicle_points/drop_zone/zone_bounds)
##     未就绪时本模式程序化生成点(环形散布)并打印报告。
##   - AI Agent(bot.gd / bot_manager.gd 不动):AI 落点决策;本模式负责跳伞物理与状态机。
##     接口:jump_state(actor) / start_jump(actor, target) / plane_pos / plane_vel /
##           loot_snapshot() / pickup_for(actor, loot) / current_zone()
##     默认兜底:飞机起飞后 bot 按 1~6s 错峰自动跳伞(落点随机圈内),AI Agent 可覆盖。
##   - UI Agent:监听 round_started / round_ended / portal_hint / zone_changed / airdrop,
##     读取 br_alive / br_total / zone_center / zone_radius(已在基类声明)。

signal zone_changed(center: Vector3, radius: float)
signal airdrop(pos: Vector3)
signal br_eliminated(name: String, rank: int, killer: String)  # 排名播报(UI Agent 可选监听;portal 契约 player_eliminated 由基类承担)

const BR_TOTAL := 100                # 参赛人数(玩家 + 99 bot;第 100 → 第 1)
const BR_TEAMS := 25                 # 四人队制:25 队 × 4 人(玩家队=0)
const BR_PLAYER_SQUAD := 0           # 玩家队伍号(队友 = squad_id 0 的 3 只 bot)
const BR_PISTOL := "m1911"           # 开局唯一武器(主武器槽清空,落地搜物资换枪)
const ZONE_STAGES := [300.0, 150.0, 60.0]   # 安全区半径递减序列(米)
const ZONE_SHRINK := 90.0            # 每阶段缩圈时长(秒)
const ZONE_HOLD := 30.0              # 每阶段停留时长(秒)
const LOBBY_TIME := 10.0             # 开局倒计时(秒)
const FLIGHT_SPEED := 70.0           # 飞机速度(m/s)
const PLANE_ALT := 600.0             # 航线高度(米)
const ZONE_DMG_START := 2.0          # 圈外初始每秒伤害
const ZONE_DMG_STEP := 2.0           # 每阶段递增(上限 10)
const ZONE_DMG_MAX := 10.0
const PICK_RADIUS := 2.2             # 拾取距离
const LOOT_PER_POINT := 1            # 每物资点物品数(加密后点位 300+,保持实体池可控)
const AIRDROP_TIMES := [200.0, 320.0, 440.0]  # 空投时刻(秒)
const LOOT_REFRESH_TIMES := [240.0, 420.0]    # 物资刷新(中盘/空投后)
const VEH_RESPAWN := 45.0            # 载具重生间隔(秒)
const REPLAY_TIME := 5.0             # 死亡回放时长(击杀者视角,秒)
const LOOT_POOL := 400               # 物资实体对象池大小(初始物资约 316,留出死亡掉落/空投余量)

var phase := "idle"                  # idle | lobby | flight | battle
var phase_t := 0.0
var map_id := ""
var round_winner := ""
var result := {}
var plane_pos := Vector3(0, PLANE_ALT, 0)
var plane_vel := Vector3.ZERO
var drop_zone := Vector3.ZERO

# ---- 地图点(extra 或程序化) ----
var loot_points: Array = []
var vehicle_points: Array = []
var _villages: Array = []      # [BR-FIX] 村庄坐标(锚点聚落偏好用)
var _zone_bounds := 400.0

# ---- 毒圈 ----
var zone_stage := 0
var zone_t := 0.0
var zone_hold_t := 0.0
var zone_shrinking := false
var zone_shrink_t := 0.0
var zone_start_r := 400.0
var zone_target_r := 300.0
var zone_target_c := Vector3.ZERO
var zone_damage := 2.0
var _player_zone_acc := 0.0
var _bot_zone_acc := {}               # [BR-Z] bot 毒圈伤害节流累积(Bot -> 累计 HP,≥8 一跳)
var _zone_hint_t := 0.0
var _zone_ring_in: MeshInstance3D = null
var _zone_ring_out: MeshInstance3D = null
var _zone_ring_mat_in: StandardMaterial3D = null
var _zone_ring_mat_out: StandardMaterial3D = null
var _zone_ring_n: Node3D = null
var _ring_color_t := 0.0               # [PERF] 毒圈颜色节流计时(10Hz)

# ---- 跳伞状态机(物理归本模式;AI 落点决策归 AI Agent) ----
var _bot_jump := {}                  # Bot -> { state, vel, target, t0, off }
var _player_jump := ""               # "" | plane | freefall | chute | landed
var _player_jvel := Vector3.ZERO
var _player_chute := false
var _cam_log_state := ""             # [BR-CAM] 节流日志:上次状态
var _cam_log_mode := ""              # [BR-CAM] 节流日志:上次相机模式(tp/fp)
var _cam_log_t := -99.0              # [BR-CAM] 节流日志:上次打印时刻
# ---- [BR-VIS] 跳伞渲染/空手节流日志(仅状态变化时打印) ----
var _vis_log: Dictionary = {}        # bot -> "hidden"|"shown" 网格显隐
var _wp_log: Dictionary = {}         # bot -> bool 武器显隐
var _player_wp_logged := false       # 玩家 veh_body 空手日志(单次)

# ---- [BR-M] 任务2:跳伞伞具(背伞包 + 开伞伞面)与显隐节流日志 ----
var _player_chute_n: Node3D = null
var _player_chute_canopy: MeshInstance3D = null
var _player_chute_pack: MeshInstance3D = null
var _bot_chutes: Dictionary = {}     # bot -> 伞具节点(挂 bot.mesh 下)
var _chute_log: Dictionary = {}      # bot -> 伞面可见 bool(节流)
var _player_body_log := ""           # "" | hidden | shown(节流)
var _player_chute_log := false       # 伞具节点可见(节流)
var _player_canopy_log := false      # 伞面可见(节流)

# ---- 任务4:四人队制(队伍淘汰/排名/落点锚) ----
var br_alive_teams := BR_TEAMS       # 存活队伍数(HUD 轮询镜像 G.portal)
var br_total_teams := BR_TEAMS
var _team_ranks := {}                # squad_id -> 队伍排名(队内最后一人淘汰时记录)
var _squad_anchors: Array = []       # squad_id -> 跳伞落点锚(同队 4 人落点相近)

# ---- 飞机 ----
var _plane: Node3D = null
var _plane_route := [Vector3.ZERO, Vector3.ZERO]
var _boarded := false
var _flight_t := 0.0

# ---- 物资(池化) ----
var _loot: Array = []                # { holder, kind, id, quality, used, pos, base_y }
var _loot_pool: Array = []
var _loot_mats := {}

# ---- 空投 ----
var _airdrop_times: Array = []
var _airdrop_idx := 0
var _airdrop_crates: Array = []      # { holder, pos, vel, landed }

# ---- 载具 ----
var _veh_at := {}                    # Vehicle -> point_index
var _veh_respawn := {}               # point_index -> 剩余秒
var _veh_defs: Array = []

# ---- 排名/统计 ----
var _eliminated := {}                # actor -> rank
var _player_rank := BR_TOTAL
var _kill_stats := {}                # actor -> kills
var _dmg_stats := {}                 # actor -> damage
var _ended := false
var _last_tick_frame := -1
var _perf_log_t := 0.0  # [PERF] 节流统计日志计时(5s 一拍)

# ---- [BENCH] 热点计时(仅 --bench-collide 启用;默认零开销) ----
var _bench_t := 0.0
var _bench_ready := false


func _bench_report(dt: float) -> void:
	if not _bench_ready:
		_bench_ready = true
		Utils.bench_init()  # 读 --bench-collide/--bench-linear,解除 144 帧封顶
	if not Utils._bench:
		return
	_bench_t += dt
	if _bench_t >= 10.0:
		_bench_t = 0.0
		Utils.bench_report("t=%.0f" % round_time)

# ---- 观战 ----
var _replay_killer = null
var _replay_t := 0.0
var _spec_target = null
var _spec_list: Array = []
var _spec_idx := 0
var _top10_at := -99.0

# ---- [BR-R] 任务:玩家重部署(首次死亡 → 乘小型直升机重返战场 → 跳伞落地复活;二次死亡才定排名) ----
const REDEPLOY_WAIT := 20.0            # 死亡后按 R 重部署的窗口(秒),超时自动
const REDEPLOY_HELO_SPEED := 30.0      # 小直升机飞行速度(m/s)
const REDEPLOY_HELO_ALT := 120.0       # 直升机飞行高度(米)
const BR_HELO_MAX := 3                 # [BR-R] 全员重部署:同时最多在飞直升机架数(性能)
const BR_HELO_CAP := 4                 # [BR-R] 每架直升机载 bot 数(批次,先死先走)
const BR_REDEPLOY_DELAY_MIN := 15.0    # [BR-R] bot 首死 → 重生队列延迟下限(秒)
const BR_REDEPLOY_DELAY_MAX := 30.0    # [BR-R] bot 首死 → 重生队列延迟上限(秒)
var _player_deaths := 0                # 玩家累计阵亡(1=首次 → 重部署;≥2=真淘汰)
var _redeploy := ""                    # "" | waiting | helo
var _redeploy_t := 0.0                 # 等待剩余秒 / 直升机飞行计时
var _helo: Node3D = null               # 小型运输直升机节点
var _helo_start := Vector3.ZERO
var _helo_target := Vector3.ZERO
var _helo_vel := Vector3.ZERO
var _helo_yaw := 0.0
# ---- [BR-R] 全员重部署(含 AI):bot 首死入队 → 直升机批次 → 跳伞复活;二次死亡才真淘汰 ----
var _br_redeploy_queue: Array = []     # 待重生 bot 队列:{ bot, t0, delay }(先死先走)
var _br_helos: Array = []              # 在飞直升机:{ node, bots: Array, target }

# ---- AI 目标点(防 bot.pick_objective 空旗列表崩溃;BR 征服结算已跳过) ----
var _ai_flags: Array = []
var _flag_node: Node3D = null


func _ready() -> void:
	mode_name = "br"
	time_limit = 900.0
	br_total = BR_TOTAL
	_init_loot_mats()


## 节点释放前清理全局引用(PortalManager 对局结束 queue_free 本节点)
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# [PERF] 兜底恢复画质预设(任意退出路径:结算/中断/回菜单)
		if GraphicsQuality != null:
			GraphicsQuality.restore_preset()
		if G != null and G.br == self:
			G.br = null


## 门户提示通道:优先走 PortalManager.hint(main.gd 已接 G.hud.hint),无管理器时直发信号
func _hint(text: String) -> void:
	var pm: Variant = G.get("portal")
	if pm != null and pm.has_method("hint"):
		pm.hint(text)
	else:
		portal_hint.emit(text)


## ==================== 启动 ====================
func start(p_map_id: String = "") -> void:
	_cleanup()
	_ended = false
	started = false
	map_id = p_map_id
	if map_id == "" or not MapsData.M().has(map_id):
		map_id = ""
		for id in MapsData.M():
			if MapsData.M()[id].mode == "br":
				map_id = id
				break
	if map_id == "" or not MapsData.M().has(map_id):
		push_error("[BR] 无可用大逃杀地图(br_valley mode=br 未就绪),已中止开局")
		return
	G.mode = "br"
	G.br = self
	if G.current_map != map_id:
		G.game.setup_map(map_id)
	G.state = "playing"
	if G.input_sys != null:
		G.input_sys.lock()
	_load_map_points()
	_spawn_zone_rings()
	_build_plane()

	# ---- 载具(由本模式负责刷新) ----
	for v in G.vehicles:
		v.dispose()
	G.vehicles = []
	_veh_at.clear()
	_veh_respawn.clear()
	for i in vehicle_points.size():
		_spawn_vehicle_at(i)

	# ---- 玩家部署(菜单流无 deploy 屏;test-play 的 deploy() 会在登机后被吸附回飞机) ----
	# 任务1:BR 开局应用兵种选择屏所选兵种(menus.br_selected_class,缺省 assault)
	if G.player != null:
		var sel_class := "assault"
		if G.menus != null and G.menus.get("br_selected_class") != null:
			sel_class = str(G.menus.br_selected_class)
		if not WeaponsData.C().has(sel_class):
			sel_class = "assault"
		G.player.class_id = sel_class
		G.player.loadout = null
		if not G.player.alive:
			G.game.spawn_actor(G.player)
		if G.player.alive:
			G.player.give_class(sel_class, null)  # 重建枪械/veh_body 兵种外观
		print("[BR-M] 任务1 玩家兵种选择 class=%s(开局应用)" % sel_class)

	# ---- AI:任务4 100 人 = 玩家 + 99 bot(bot_manager.reset(49) → 49+50=99 只) ----
	G.bot_manager.reset(49)
	_create_ai_objectives()
	# 四人队制:bot[0..2] 与玩家同队(队 0),其余 96 只每 4 人一队(队 1..24)
	for i in G.bots.size():
		G.bots[i].squad_id = 0 if i < 3 else 1 + int((i - 3) / 4.0)
	# 25 队落点锚(同队跳伞落点相近;整图随机分布)
	_build_squad_anchors()
	var route_dir: Vector3 = Utils.safe_norm(_plane_route[1] - _plane_route[0], Vector3.FORWARD)
	for i in G.bots.size():
		var b = G.bots[i]
		b.spawn(plane_pos)  # 复用 spawn 初始化(health/aim/ammo);位置由本模式跳伞状态机接管
		_br_arm_bot_pistol(b)  # 任务3:开局只有手枪(主武器槽清空 → m1911)
		var off := Vector3(Utils.rand(-14.0, 14.0), 0.5, Utils.rand(-14.0, 14.0))
		_bot_jump[b] = {
			"state": "plane", "vel": Vector3.ZERO, "t0": 0.0, "off": off,
			"target": _random_land_target(route_dir, b),
		}
		b.vel = Vector3.ZERO
		b.think_t = 1e9  # 登机期间冻结 AI 思考(bot.gd 每帧贴地/索敌,由本模式跳伞物理接管)
		b.respawn_t = 1e9
	print("[BR-M] 任务4 squad 分配:100 人 = 玩家(队0)+99 bot,25 队 × 4 人,同队落点相近")
	print("[BR-M] 任务3 开局武器:玩家+99 bot 全部仅手枪 %s(主武器槽空,落地搜物资)" % BR_PISTOL)

	# ---- 玩家登机 ----
	_board_player()
	phase = "lobby"
	phase_t = LOBBY_TIME
	round_time = 0.0
	zone_stage = 0
	zone_t = 0.0
	zone_damage = ZONE_DMG_START
	# 任务5:毒圈第一圈中心每局随机(整图随机,不再固定 drop_zone;后续缩圈随机内缩保留)
	var zc0 := Vector3(Utils.rand(-_zone_bounds * 0.75, _zone_bounds * 0.75), 0.0,
		Utils.rand(-_zone_bounds * 0.75, _zone_bounds * 0.75))
	zc0.x = clampf(zc0.x, -G.bounds + 20, G.bounds - 20)
	zc0.z = clampf(zc0.z, -G.bounds + 20, G.bounds - 20)
	zone_center = zc0
	zone_target_c = zc0
	zone_radius = _zone_bounds
	zone_hold_t = ZONE_HOLD
	zone_shrinking = false
	br_total = BR_TOTAL
	br_alive = _alive_count()
	br_alive_teams = _alive_teams()
	_airdrop_times = AIRDROP_TIMES.duplicate()
	_airdrop_idx = 0
	_airdrop_crates.clear()
	_spawn_loot()
	started = true
	round_winner = ""
	result = {}
	print("[BR-M] 任务5 毒圈第一圈中心=(%.0f,0,%.0f) 半径=%.0fm 每局随机(不再固定 drop_zone=%s)" % [
		zc0.x, zc0.z, _zone_bounds, str(drop_zone)])
	print("[BR] 大逃杀开局 map=%s 物资点=%d 载具点=%d 阶段=%.0fm→%s" % [
		map_id, loot_points.size(), vehicle_points.size(), _zone_bounds, str(ZONE_STAGES)])
	round_started.emit("br", map_id, br_total)
	if G.hud != null:
		G.hud.banner("大逃杀:100 名参赛者 · 25 队,10 秒后起飞!")
	# [PERF] BR 开局应用优化档(shadows 2048 / SSIL 关 / SSR 关),对局收尾恢复
	if GraphicsQuality != null:
		GraphicsQuality.apply_br_preset()


## ==================== 每帧驱动(幂等:架构 Agent 与 main 兜底可能双接) ====================
func tick(dt: float) -> void:
	if Engine.get_process_frames() == _last_tick_frame:
		return
	_last_tick_frame = Engine.get_process_frames()
	if _ended or not started:
		return
	round_time += dt

	# 玩家登机(部署完成后自动接入;落地后不再重复登机)
	if G.player != null and G.player.alive and _player_jump == "" \
			and (phase == "lobby" or phase == "flight"):
		_board_player()
	# 登机期间强制基础装备(仅保留手枪;test-play 的 deploy() 重配后会再剥离)
	if phase == "lobby" or phase == "flight":
		if G.player != null and G.player.alive and _player_jump == "plane":
			var need_strip := false
			for g in G.player.guns:
				if g.def.kind != "pistol":
					need_strip = true
					break
			if need_strip:
				G.player.br_strip_inventory()

	match phase:
		"lobby":
			phase_t -= dt
			if G.player != null and G.player.alive and _player_jump == "plane":
				G.hud.hint("按 空格 跳伞 · 当前高度 %.0fm" % plane_pos.y)
			if phase_t <= 0.0:
				_begin_flight()
		"flight":
			_update_flight(dt)
		"battle":
			_update_battle(dt)
		_:
			pass

	_update_bot_jumps(dt)
	_update_redeploy(dt)
	_update_bot_redeploy(dt)   # [BR-R] 全员重部署:bot 队列 → 直升机批次 → 跳伞
	_update_plane_visual()
	_update_zone_rings()
	_update_loot_anim(dt)
	_update_airdrops(dt)
	_update_vehicles(dt)
	_update_zone_rings_color(dt)

	# BR HUD 字段镜像到 G.portal(hud.gd 轮询;架构 Agent 已按契约在 PortalManager 预留)
	var pm: Variant = G.get("portal")
	if pm != null:
		pm.br_alive = br_alive
		pm.br_total = br_total
		pm.zone_center = zone_center
		pm.zone_radius = zone_radius
		# 任务4:存活队伍数(新字段动态写入;hud.gd 优先读,缺失回退个人存活数)
		pm.set("br_alive_teams", br_alive_teams)
		pm.set("br_total_teams", br_total_teams)

	# [PERF] BR 远距节流生效统计(5s 一拍,供基准对比)
	_perf_log_t += dt
	if _perf_log_t >= 5.0:
		_perf_log_t = 0.0
		var far_n := 0
		for b in G.bots:
			if b != null and b.alive and b._br_far:
				far_n += 1
		if far_n > 0:
			print("[PERF] BR 远距节流生效 bots=%d/%d think=0.30s" % [far_n, G.bots.size()])

	# [PERF] P1-3:bot 重生压制改为事件驱动(死亡时在 on_player_killed 设 respawn_t=1e9),
	# 不再逐帧扫描 G.bots(死亡 bot 保持尸体,压制 bot_manager 重生)
	# 玩家拾取(落地后常驻)
	if G.player != null and G.player.alive and _player_jump == "landed":
		_update_player_pickup(G.player)

	# [PERF] P1-2:存活数/存活队伍数事件驱动增量维护(淘汰时更新),此处直接读缓存
	_check_winner()

	# [BENCH] 热点计时报告(--bench-collide 参数启用;10s 一拍;默认零开销)
	_bench_report(dt)


## ==================== 阶段:起飞与跳伞 ====================
func _begin_flight() -> void:
	phase = "flight"
	phase_t = 0.0
	_flight_t = 0.0
	print("[PERF] 跳伞隔帧更新生效: 95 伞面物理按 id 错峰 30Hz/只(CPU 减半)")
	for b in _bot_jump.keys():
		var j: Dictionary = _bot_jump[b]
		j["t0"] = 0.0
	plane_pos = _plane_route[0]
	plane_vel = Utils.safe_norm(_plane_route[1] - _plane_route[0], Vector3.FORWARD) * FLIGHT_SPEED
	_update_plane_visual()
	if G.hud != null:
		G.hud.banner("运输机起飞 — 按 空格 跳伞!")
	_hint("运输机已起飞,按 空格 跳伞")


func _update_flight(dt: float) -> void:
	_flight_t += dt
	plane_pos += plane_vel * dt
	if _flight_t > 90.0 or plane_pos.distance_to(_plane_route[1]) < 50.0:
		_end_flight()
		return
	# [BR-FIX] 跳伞时机 = 飞机飞临该队落点锚上空才跳(旧版 1~5s 全员齐跳,99 人全砸在
	# 航线前段 350m 内 —— "所有 NPC 集中在一个地方降落"的根因)。飞机 70m/s 穿越
	# 2180m 航线约 31s,25 队锚沿航线依次触发,落点覆盖全图。
	var rd2 := Vector2(plane_vel.x, plane_vel.z)
	if rd2.length() < 0.1:
		rd2 = Vector2.DOWN
	rd2 = rd2.normalized()
	var perp := Vector2(-rd2.y, rd2.x)
	for b in _bot_jump.keys():
		var j: Dictionary = _bot_jump[b]
		if j["state"] != "plane":
			continue
		var anchor := Vector3.ZERO
		if b.squad_id >= 0 and _squad_anchors.size() > b.squad_id:
			anchor = _squad_anchors[b.squad_id]
		if anchor == Vector3.ZERO:
			continue
		var to_a := Vector2(anchor.x - plane_pos.x, anchor.z - plane_pos.z)
		var along := to_a.dot(rd2)
		var lateral: float = absf(to_a.dot(perp))
		# 正上方 ±90m 内跳;或刚越过锚点(0~-90m)且横偏在滑翔修正范围(<230m)内兜底
		if to_a.length() < 90.0 or (along < 0.0 and along > -90.0 and lateral < 230.0):
			start_jump(b, j["target"])


func _end_flight() -> void:
	# 未跳伞者强制下机(玩家 + bot)
	if G.player != null and _player_jump == "plane":
		start_jump(G.player, Vector3.ZERO)
	for b in _bot_jump.keys():
		var j: Dictionary = _bot_jump[b]
		if j["state"] == "plane":
			start_jump(b, j["target"])
	phase = "battle"
	zone_t = 0.0
	zone_hold_t = ZONE_HOLD
	zone_damage = ZONE_DMG_START
	if G.hud != null:
		G.hud.banner("进入战场 — 毒圈即将收缩,注意安全区!")
	zone_changed.emit(zone_center, zone_radius)


## ==================== 跳伞状态机(玩家 + AI 共用物理) ====================
func jump_state(actor) -> String:
	if actor == null:
		return ""
	if actor is Object and is_same(actor, G.player):
		return _player_jump
	if _bot_jump.has(actor):
		return (_bot_jump[actor] as Dictionary)["state"]
	return ""


func player_jump_active() -> bool:
	return _player_jump == "plane" or _player_jump == "freefall" or _player_jump == "chute"


## AI Agent 接口:提前跳伞(物理与状态机归本模式;落点由调用方决定)
func start_jump(actor, target_pos := Vector3.ZERO) -> void:
	if is_same(actor, G.player):
		if _player_jump == "plane":
			_player_jump = "freefall"
			_player_chute = false
			_player_jvel = plane_vel * 0.65 + Vector3(0, 2.0, 0)
			# [BR-R] 任务1:玩家跳机瞬间,队 0(同队)未跳 bot 同时跳伞(落点=队锚附近,
			# 覆盖 AI 错峰决策:已跳的不受影响,未跳的强制立即下机)
			_player_follow_jump()
		return
	if _bot_jump.has(actor):
		var j: Dictionary = _bot_jump[actor]
		if j["state"] == "plane":
			j["state"] = "freefall"
			j["vel"] = plane_vel * 0.65 + Vector3(Utils.rand(-2.0, 2.0), Utils.rand(1.0, 3.0), Utils.rand(-2.0, 2.0))
			if target_pos != Vector3.ZERO:
				j["target"] = target_pos


## [BR-R] 任务1:队友跟随跳伞 —— 玩家 start_jump(跳机瞬间)触发:
## 同队(squad_id==0 的 3 只 bot,仍处于 plane)全部同时 start_jump;
## 落点优先取各自 _squad_anchors[0] 附近的现成目标(AI 已决策 br_land_target / 开局队锚目标),
## 缺失时按队锚重新生成;与 AI Agent _br_plane_think 的错峰决策冲突时以本处为准(强制同跳)。
func _player_follow_jump() -> void:
	var route_dir: Vector3 = Utils.safe_norm(_plane_route[1] - _plane_route[0], Vector3.FORWARD)
	var n := 0
	for b in _bot_jump.keys():
		if not is_instance_valid(b) or b.squad_id != BR_PLAYER_SQUAD:
			continue
		var j: Dictionary = _bot_jump[b]
		if j["state"] != "plane":
			continue
		var t: Vector3 = Vector3.ZERO
		var blt: Variant = b.get("br_land_target")
		if blt is Vector3 and blt != Vector3.ZERO:
			t = blt  # AI 已决策落点(同公式:队锚 + 15~30m 错位)
		elif j["target"] is Vector3:
			t = j["target"]  # 开局队锚落点
		if t == Vector3.ZERO:
			t = _random_land_target(route_dir, b)
		start_jump(b, t)
		n += 1
	if n > 0:
		print("[BR-R] 任务1 队友跟跳:玩家跳机瞬间 队0 bot 同跳=%d 只(落点=队锚附近,覆盖 AI 错峰)" % n)


## 玩家跳伞(由 player.gd update_player 每帧路由;复用视角/输入)
func update_player_jump(p, dt: float) -> void:
	p.spawn_protect = maxf(0.0, p.spawn_protect - dt)
	var md: Vector2 = G.input_sys.consume_mouse()
	p.apply_look(md.x, md.y)
	p.eye_height = 1.70   # 与 player.gd 站立眼高一致(低于此值第一人称胸口会被 near 裁掉)
	if _player_jump == "plane":
		p.pos = plane_pos + Vector3(0, 0.5, 0)
		p.vel = Vector3.ZERO
		if Input.is_action_just_pressed("jump"):
			start_jump(p)
			AudioSys.step(true)
	elif _player_jump == "freefall" or _player_jump == "chute":
		_player_update_fall_physics(p, dt)
	# 第三人称跳伞:飞机/自由落体/开伞全程侧后方相机 + 全身模型;落地恢复第一人称
	if _player_jump == "landed":
		_restore_player_fp(p)
		_camera_from_player(p, dt)
		_cam_log("landed", "fp")
	else:
		_show_player_jump_body(p)
		_tp_camera_from_player(p, dt)
		_cam_log(_player_jump, "tp")


func _player_update_fall_physics(p, dt: float) -> void:
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var right := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var fwd_in := (1 if Input.is_action_pressed("move_forward") else 0) - (1 if Input.is_action_pressed("move_back") else 0)
	var right_in := (1 if Input.is_action_pressed("move_right") else 0) - (1 if Input.is_action_pressed("move_left") else 0)
	var wish := fwd * fwd_in + right * right_in
	if wish.length_squared() > 0.0:
		wish = wish.normalized()
	var max_h := 4.0 if _player_jump == "freefall" else 6.5
	_player_jvel.x = Utils.damp(_player_jvel.x, wish.x * max_h, 2.0, dt)
	_player_jvel.z = Utils.damp(_player_jvel.z, wish.z * max_h, 2.0, dt)
	if _player_jump == "freefall":
		# 自由落体:重力倍增加速下落(y 向下为负),上限 60 m/s
		_player_jvel.y = maxf(_player_jvel.y - 9.8 * 2.5 * dt, -60.0)
		if Input.is_action_just_pressed("jump"):
			_player_jump = "chute"
			_player_jvel.y = -8.0
			AudioSys.capture(true)
			_hint("降落伞已打开")
	else:
		_player_jvel.y = Utils.damp(_player_jvel.y, -6.2, 3.0, dt)
	var gh: float = G.ground_h.call(p.pos.x, p.pos.z) if G.ground_h.is_valid() else 0.0
	# 安全自动开伞(距地 110m 内)
	if _player_jump == "freefall" and not _player_chute and p.pos.y < gh + 110.0:
		_player_jump = "chute"
		_player_jvel.y = -8.0
	p.pos += _player_jvel * dt
	if p.pos.y <= gh:
		p.pos.y = gh
		p.vel = Vector3.ZERO
		p.on_ground = true
		var no_chute := _player_jump == "freefall"
		_player_jump = "landed"
		_player_jvel = Vector3.ZERO
		if no_chute:
			G.hud.hint("未开伞落地,受到冲击伤害!")
			p.damage(45.0, Vector3.ZERO, null)
		else:
			_hint("已着陆 — 搜集物资,留意毒圈")
		# [BR-R] 重部署跳伞落地 → 复活完成(HP 满/仅手枪),免疫解除
		if _redeploy == "helo":
			_finalize_redeploy(p)


func _camera_from_player(p, dt: float) -> void:
	var cam := G.camera
	cam.global_position = p.pos + Vector3(0, 1.70, 0)   # 同 player.eye_height 站立值
	cam.rotation_order = EULER_ORDER_YXZ
	var wind := sin(G.time * 2.0) * 0.012 if _player_jump == "freefall" else 0.0
	cam.rotation.y = p.yaw + wind
	cam.rotation.x = p.pitch
	cam.rotation.z = 0.0
	if absf(cam.fov - G.settings.fov) > 0.05:
		cam.fov = Utils.damp(cam.fov, G.settings.fov, 18, dt)


## [BR-CAM] 跳伞状态/相机模式节流日志(仅切换时打印,最小间隔 0.25s)
func _cam_log(state: String, mode: String) -> void:
	if _cam_log_state == state and _cam_log_mode == mode:
		return
	if G.time - _cam_log_t < 0.25:
		return
	_cam_log_t = G.time
	_cam_log_state = state
	_cam_log_mode = mode
	var pp: Vector3 = G.player.pos if G.player != null else Vector3.ZERO
	print("[BR-CAM] state=%s mode=%s pos=%.0f,%.0f,%.0f" % [state, mode, pp.x, pp.y, pp.z])


## [BR-VIS] 任务3(玩家):跳伞全程第三人称空手(隐藏 veh_body 的 rig/Weapon_* 节点)
func _hide_veh_body_weapon(vb: Node3D) -> void:
	if vb == null or not vb.has_meta("rig"):
		return
	for c in (vb.get_meta("rig") as Node3D).get_children():
		if c is Node3D and String(c.name).begins_with("Weapon_") and c.visible:
			c.visible = false
			if not _player_wp_logged:
				_player_wp_logged = true
				print("[BR-VIS] player veh_body 空手跳伞(武器节点 %s 隐藏)" % c.name)


## 跳伞第三人称:显示玩家全身模型(veh_body 士兵模型;隐藏第一人称半身与视角模型枪械)
## 任务2:飞机上(plane)隐藏玩家模型 —— 跳出(freefall)瞬间才显示,并全程携带伞具
func _show_player_jump_body(p) -> void:
	var vb: Node3D = p.veh_body
	if vb == null:
		_update_player_chute(p)
		return
	var body_show: bool = _player_jump != "plane"
	if vb.visible != body_show:
		vb.visible = body_show
		var body_st := "shown" if body_show else "hidden"
		if _player_body_log != body_st:
			_player_body_log = body_st
			print("[BR-M] t=%.0f 玩家模型 visible=%s jump=%s" % [round_time, body_show, _player_jump])
	vb.rotation_order = EULER_ORDER_YXZ
	vb.position = p.pos
	vb.rotation = Vector3.ZERO
	vb.rotation.y = p.yaw
	# [BR-VIS] 任务3(玩家):跳伞全程第三人称空手(隐藏 veh_body 武器节点)
	_hide_veh_body_weapon(vb)
	var leg_l: Node3D = vb.get_meta("leg_l") if vb.has_meta("leg_l") else null
	var leg_r: Node3D = vb.get_meta("leg_r") if vb.has_meta("leg_r") else null
	var leg_l_knee: Node3D = vb.get_meta("leg_l_knee") if vb.has_meta("leg_l_knee") else null
	var leg_r_knee: Node3D = vb.get_meta("leg_r_knee") if vb.has_meta("leg_r_knee") else null
	var rig: Node3D = vb.get_meta("rig") if vb.has_meta("rig") else null
	match _player_jump:
		"plane":
			# 机舱内站立(腿微张,臂持枪)
			if leg_l != null:
				leg_l.rotation.x = 0.18
				leg_r.rotation.x = -0.12
				leg_l_knee.rotation.x = 0.1
				leg_r_knee.rotation.x = 0.05
			if rig != null:
				rig.rotation.x = 0.3
		"freefall":
			# 自由落体:身体前倾竖直下落,腿臂张开
			vb.rotation.x = 0.5
			if leg_l != null:
				leg_l.rotation.x = 0.75
				leg_r.rotation.x = -0.55
				leg_l_knee.rotation.x = 0.35
				leg_r_knee.rotation.x = 0.3
			if rig != null:
				rig.rotation.x = 0.7
		"chute":
			# 开伞:直立,腿微屈
			vb.rotation.x = 0.08
			if leg_l != null:
				leg_l.rotation.x = 0.3
				leg_r.rotation.x = 0.3
				leg_l_knee.rotation.x = 0.18
				leg_r_knee.rotation.x = 0.18
			if rig != null:
				rig.rotation.x = 0.25
	# 隐藏第一人称半身(body.visible 由 main.gd 每帧强制,故隐藏其 children)
	var b: Node3D = p.body
	if b != null:
		var up: Node3D = b.get_meta("upper") if b.has_meta("upper") else null
		var bl: Node3D = b.get_meta("leg_l") if b.has_meta("leg_l") else null
		var br2: Node3D = b.get_meta("leg_r") if b.has_meta("leg_r") else null
		if up != null:
			up.visible = false
		if bl != null:
			bl.visible = false
		if br2 != null:
			br2.visible = false
	# 第三人称不显示视角模型枪械(避免悬浮手枪)
	for g in p.guns:
		if g != null and g.group != null and g.group.visible:
			g.holster()
	# 任务2:伞具跟随(背伞包 freefall/chute 可见;伞面仅 chute 打开)
	_update_player_chute(p)


## 落地/对局收尾:恢复第一人称(半身 children + 视角模型枪械;veh_body 交 player.gd 管理)
func _restore_player_fp(p) -> void:
	if p.veh_body != null:
		p.veh_body.visible = false
		# [BR-VIS] 任务3(玩家):恢复 veh_body 武器显示(交还 player.gd/载具逻辑)
		if p.veh_body.has_meta("rig"):
			for c in (p.veh_body.get_meta("rig") as Node3D).get_children():
				if c is Node3D and String(c.name).begins_with("Weapon_"):
					c.visible = true
	_player_wp_logged = false
	# 任务2:落地/收尾移除伞具
	if _player_chute_n != null and is_instance_valid(_player_chute_n):
		_player_chute_n.visible = false
		if _player_chute_log:
			_player_chute_log = false
			print("[BR-M] t=%.0f 玩家伞具 visible=false jump=landed" % round_time)
	_player_canopy_log = false
	_player_body_log = "hidden"
	var b: Node3D = p.body
	if b != null:
		var up: Node3D = b.get_meta("upper") if b.has_meta("upper") else null
		var bl: Node3D = b.get_meta("leg_l") if b.has_meta("leg_l") else null
		var br2: Node3D = b.get_meta("leg_r") if b.has_meta("leg_r") else null
		if up != null:
			up.visible = true
		if bl != null:
			bl.visible = true
		if br2 != null:
			br2.visible = true
	if not p.guns.is_empty():
		p.gun().equip()


## 跳伞第三人称相机(侧后方,参考 main.gd --test-pose 写法;防穿楼射线收束)
func _tp_camera_from_player(p, dt: float) -> void:
	var cam := G.camera
	var off := Vector3(3.0, 2.6, 3.0).rotated(Vector3.UP, p.yaw)
	var eye: Vector3 = p.pos + Vector3(0, 0.9, 0)
	var d: float = off.length()
	var hit = Utils.raycast_world(eye, off.normalized(), d + 0.3)
	if hit != null:
		d = maxf(1.2, float(hit["dist"]) - 0.3)
	cam.global_position = eye + off.normalized() * d
	if _player_jump == "freefall":
		# 自由落体轻微横向漂移(保留原第一人称风感)
		var wind := sin(G.time * 2.0) * 0.08
		cam.global_position += cam.global_transform.basis.x * wind
	cam.look_at(p.pos + Vector3(0, 0.9, 0), Vector3.UP)
	if absf(cam.fov - G.settings.fov) > 0.05:
		cam.fov = Utils.damp(cam.fov, G.settings.fov, 18, dt)


## AI 跳伞物理(每帧覆盖 bot 位置;AI 行为由 bot.gd/AI Agent 决定)
## [PERF] 跳伞无交互:按 bot id 错峰隔帧更新(30Hz/只),隔帧的 dt 累计到下一拍,物理时间精确
var _jump_dt := {}  # Bot -> 累计 dt(隔帧跳过的帧时长)
func _update_bot_jumps(dt: float) -> void:
	var frame := Engine.get_process_frames()
	for b in _bot_jump.keys():
		if not is_instance_valid(b):
			continue
		var jdt: float = float(_jump_dt.get(b, 0.0)) + dt
		if (frame + b.id * 7) % 2 != 0:
			_jump_dt[b] = jdt
			continue
		_jump_dt[b] = 0.0
		var j: Dictionary = _bot_jump[b]
		match j["state"]:
			"plane":
				b.pos = plane_pos + (j["off"] as Vector3)
				b.vel = Vector3.ZERO
				_bot_jump_mesh_plane(b)
			"freefall", "chute":
				var v: Vector3 = j["vel"]
				if j["state"] == "freefall":
					v.y = maxf(v.y - 9.8 * 2.4 * jdt, -58.0)
					# 继承的飞机水平速度快速衰减,防漂出毒圈
					v.x = Utils.damp(v.x, 0.0, 2.5, jdt)
					v.z = Utils.damp(v.z, 0.0, 2.5, jdt)
				else:
					v.y = Utils.damp(v.y, -6.0, 3.0, jdt)
					# 向落点直接滑翔(不依赖阻尼,确保落在安全区内)
					var tx: float = (j["target"] as Vector3).x - b.pos.x
					var tz: float = (j["target"] as Vector3).z - b.pos.z
					var td := Vector2(tx, tz).length()
					if td > 3.0:
						v.x = tx / td * 9.0
						v.z = tz / td * 9.0
					else:
						v.x = Utils.damp(v.x, 0.0, 1.2, jdt)
						v.z = Utils.damp(v.z, 0.0, 1.2, jdt)
				b.pos += v * jdt
				var gh: float = G.ground_h.call(b.pos.x, b.pos.z) if G.ground_h.is_valid() else 0.0
				if j["state"] == "freefall" and b.pos.y < gh + 110.0:
					j["state"] = "chute"
					v.y = -8.0
				if b.pos.y <= gh:
					b.pos.y = gh
					b.vel = Vector3.ZERO
					# [BR-R] 重部署跳伞中的 bot:落地不扣冲击伤害(直升机遇险场景;首跳正常结算)
					if j["state"] == "freefall" and not b.br_redeployed:
						b.health -= 35.0
						if b.health <= 0.0:
							b.health = 0.0
							b.die(null)
					j["state"] = "landed"
					b.think_t = 0.1  # 解冻 AI:落地后由 bot.gd/AI Agent 接管行为
					_restore_bot_visual(b)  # [BR-VIS] 落地:武器恢复显示,网格交还 bot 自身逻辑
					# [BR-R] 重部署跳伞落地 → 复活(HP 满/仅手枪);二次死亡才真淘汰
					if not b.alive and b.br_redeployed:
						_bot_redeploy_on_landed(b)
				j["vel"] = v
				_bot_mesh_pose(b)
				if j["state"] != "landed":
					_bot_jump_mesh_air(b, j["state"] == "chute")
			"landed":
				_bot_jump.erase(b)


## [BR-VIS] 节流日志:网格显隐 / 武器显隐(仅状态变化时打印)
func _vis_log_mesh(b, state: String) -> void:
	if _vis_log.get(b) == state:
		return
	_vis_log[b] = state
	print("[BR-VIS] t=%.0f bot=%d mesh.visible=%s jump_state=%s" % [round_time, b.id, state == "shown", state])


func _vis_log_wp(b, armed: bool) -> void:
	if _wp_log.get(b) == armed:
		return
	_wp_log[b] = armed
	var st: String = (_bot_jump[b] as Dictionary)["state"] if _bot_jump.has(b) else "landed"
	print("[BR-VIS] t=%.0f bot=%d weapon.visible=%s jump_state=%s" % [round_time, b.id, armed, st])


## [BR-VIS] 任务3:bot 武器节点路径 mesh → meta("rig") → Weapon_<weapon_id>
func _bot_weapon_node(b) -> Node3D:
	if b == null or b.mesh == null or not b.mesh.has_meta("rig"):
		return null
	var rig: Node3D = b.mesh.get_meta("rig")
	if rig == null:
		return null
	return rig.get_node_or_null("Weapon_" + b.weapon_id)


## [BR-VIS] 任务3:bot 手中武器显隐控制
func _bot_show_hands(b, armed: bool) -> void:
	var wg := _bot_weapon_node(b)
	if wg == null:
		return
	if wg.visible != armed:
		wg.visible = armed
		_vis_log_wp(b, armed)


## [BR-VIS] 任务3(落地):恢复武器显示;网格可见性交还 bot.gd 自身逻辑
## (死亡落地尸体保持空手 —— die() 已隐藏武器并掉落)
func _restore_bot_visual(b) -> void:
	_bot_chute_set(b, false, false)  # 任务2:落地/死亡移除伞具
	if b.mesh != null and not b.mesh.visible:
		b.mesh.visible = true
		_vis_log_mesh(b, "shown")
	if not b.alive:
		return
	_bot_show_hands(b, true)


func _bot_mesh_pose(b) -> void:
	b.mesh.position = b.pos
	b.mesh.rotation = Vector3.ZERO
	var leg_l: Node3D = b.mesh.get_meta("leg_l") if b.mesh.has_meta("leg_l") else null
	var leg_r: Node3D = b.mesh.get_meta("leg_r") if b.mesh.has_meta("leg_r") else null
	if leg_l != null:
		leg_l.visible = true
		leg_r.visible = true


## [BR-VIS] 任务2:跳伞渲染时机 —— 飞机上(plane)不渲染;跳出(freefall)瞬间才渲染
## [BR-VIS] 任务3:plane/freefall/chute 全程空手(武器节点隐藏)
## [BR-M] 任务2:bot 伞具 —— freefall 背伞包 / chute 伞面打开 / plane 与落地隐藏
## [PERF] P1-3:原独立逐帧 _update_bot_jump_mesh 循环合并进 _update_bot_jumps
## (状态与位置只在物理拍变化,30Hz 更新与逐帧视觉一致;落地由 _restore_bot_visual 恢复)
func _bot_jump_mesh_plane(b) -> void:
	if b.mesh != null and b.mesh.visible:
		b.mesh.visible = false
		_vis_log_mesh(b, "hidden")
	_bot_show_hands(b, false)
	_bot_chute_set(b, false, false)


func _bot_jump_mesh_air(b, chute_open: bool) -> void:
	if b.mesh != null and not b.mesh.visible:
		b.mesh.visible = true
		_vis_log_mesh(b, "shown")
	_bot_show_hands(b, false)
	_bot_chute_set(b, true, chute_open)
	_bot_mesh_pose(b)


## ==================== 毒圈 ====================
func _update_battle(dt: float) -> void:
	zone_t += dt
	if not zone_shrinking:
		zone_hold_t -= dt
		if zone_hold_t <= 0.0:
			if zone_stage < ZONE_STAGES.size():
				_pick_zone_target(ZONE_STAGES[zone_stage])
			else:
				# 决赛圈后持续收缩至 0,逼出最终对决
				_pick_zone_target(0.0)
			_begin_shrink()
	else:
		zone_shrink_t -= dt
		var k := clampf(1.0 - maxf(0.0, zone_shrink_t) / ZONE_SHRINK, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - k, 2.0)
		zone_center = zone_center.lerp(zone_target_c, eased)
		zone_radius = lerpf(zone_start_r, zone_target_r, eased)
		if k >= 1.0:
			zone_shrinking = false
			zone_stage += 1
			zone_hold_t = ZONE_HOLD
			zone_damage = minf(ZONE_DMG_MAX, ZONE_DMG_START + zone_stage * ZONE_DMG_STEP)
			zone_changed.emit(zone_center, zone_radius)
			_hint("毒圈收缩完成 — 当前圈伤 %.0f/s" % zone_damage)
	# 圈外伤害(玩家节流反馈 + AI)
	_apply_zone_damage(dt)


func _pick_zone_target(target_r: float) -> void:
	var nr: float = target_r
	var a := Utils.rand(TAU)
	var r := Utils.rand(0.0, maxf(0.0, zone_radius * 0.6))
	var c := zone_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	c.x = clampf(c.x, -G.bounds, G.bounds)
	c.z = clampf(c.z, -G.bounds, G.bounds)
	zone_target_c = c
	zone_target_r = maxf(0.0, minf(nr, zone_radius * 0.85))
	zone_start_r = zone_radius


func _begin_shrink() -> void:
	zone_shrinking = true
	zone_shrink_t = ZONE_SHRINK
	if G.hud != null:
		G.hud.banner("安全区收缩中 — 圈伤每秒 %.0f" % zone_damage)
	_hint("安全区收缩中,请尽快进圈!")
	zone_changed.emit(zone_center, zone_radius)


func _apply_zone_damage(dt: float) -> void:
	if phase != "battle":
		return
	var dmg: float = zone_damage * dt
	var p = G.player
	if p != null and p.alive:
		# 跳伞途中(飞机/自由落体/开伞)不受圈伤
		if _player_jump == "" or _player_jump == "landed":
			var dz := Vector2(p.pos.x - zone_center.x, p.pos.z - zone_center.z).length()
			if dz > zone_radius:
				_player_zone_acc += dmg
				_zone_hint_t -= dt
				if _zone_hint_t <= 0.0:
					_zone_hint_t = 2.0
					_hint("毒圈伤害!每秒 %.0f,快进安全区" % zone_damage)
				if _player_zone_acc >= 4.0:
					p.damage(_player_zone_acc, Vector3.ZERO, null)
					_player_zone_acc = 0.0
	for b in G.bots:
		if b == null or not b.alive:
			_bot_zone_acc.erase(b)
			continue
		# 跳伞途中(飞机/自由落体/开伞)不受圈伤,落地后按距离结算
		if _bot_jump.has(b) and (_bot_jump[b] as Dictionary)["state"] != "landed":
			_bot_zone_acc.erase(b)
			continue
		var dz2 := Vector2(b.pos.x - zone_center.x, b.pos.z - zone_center.z).length()
		if dz2 > zone_radius:
			# [BR-Z] bot 毒圈伤害节流:原每帧减 health(10/s 下每帧 0.16HP)太碎,
			# 累积 ≥8 一跳(与玩家 4HP 节流同理,减少每帧属性写入)
			_bot_zone_acc[b] = float(_bot_zone_acc.get(b, 0.0)) + dmg
			var acc2 := float(_bot_zone_acc[b])
			if acc2 >= 8.0:
				_bot_zone_acc[b] = 0.0
				b.health -= acc2
				if b.health <= 0.0:
					b.health = 0.0
					b.die(null)
		else:
			_bot_zone_acc.erase(b)


## ==================== 物资系统 ====================
func _init_loot_mats() -> void:
	_loot_mats = {
		"weapon_c": _loot_mat(Color(0.45, 0.5, 0.42)),
		"weapon_r": _loot_mat(Color(0.25, 0.5, 1.0)),
		"weapon_e": _loot_mat(Color(1.0, 0.45, 0.15)),
		"armor": _loot_mat(Color(0.4, 0.55, 0.75)),
		"medkit": _loot_mat(Color(0.95, 0.3, 0.28)),
		"ammo": _loot_mat(Color(0.95, 0.8, 0.3)),
		"airdrop": _loot_mat(Color(0.95, 0.9, 0.6)),
	}


func _loot_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.85
	m.roughness = 0.5
	m.metallic = 0.3
	return m


func _loot_key(kind: String, quality: int) -> String:
	if kind == "weapon":
		return "weapon_c" if quality <= 0 else ("weapon_r" if quality == 1 else "weapon_e")
	return kind


func _spawn_loot() -> void:
	# 先清除旧物资(换局)
	print("[PERF] 物资动画节流生效: %d 实体,>60m 处 0.5s 一拍(近处每帧)" % LOOT_POOL)
	for l in _loot:
		var h = l["holder"]
		if is_instance_valid(h):
			h.visible = false
			_loot_pool.append(h)
	_loot.clear()
	for i in loot_points.size():
		var n: int = LOOT_PER_POINT
		for k in n:
			var kind: String = _roll_kind()
			var wid := ""
			if kind == "weapon":
				wid = _roll_weapon()
			var q: int = _roll_quality()
			var pt: Vector3 = loot_points[i]
			var gh: float = G.ground_h.call(pt.x, pt.z) if G.ground_h.is_valid() else 0.0
			var pos := Vector3(pt.x + Utils.rand(-3.0, 3.0), gh + 0.45, pt.z + Utils.rand(-3.0, 3.0))
			_place_loot(pos, kind, wid, q)


func _place_loot(pos: Vector3, kind: String, wid: String, q: int) -> void:
	var holder: Node3D = _take_holder()
	if holder == null:
		return
	holder.position = pos
	holder.visible = true
	holder.rotation = Vector3(0, Utils.rand(TAU), 0)
	_build_loot_model(holder, kind, wid, q)
	_loot.append({ "holder": holder, "kind": kind, "id": wid, "quality": q,
		"used": false, "pos": pos, "base_y": pos.y })


func _take_holder() -> Node3D:
	if not _loot_pool.is_empty():
		return _loot_pool.pop_back()
	if _loot.size() + _loot_pool.size() >= LOOT_POOL:
		return null
	var h := Node3D.new()
	add_child(h)
	return h


## ==================== [3A 8/10] 物资实体建模(替代发光球) ====================
## 底座品质光环(TorusMesh 发光环) + 实体模型:
## 医疗包=白盒+红十字 / 武器=按枪型组合建模 / 护甲=胸甲 / 弹药=弹药箱
func _build_loot_model(h: Node3D, kind: String, wid: String, q: int) -> void:
	for ch in h.get_children():
		ch.queue_free()
	# 品质光环(发光 TorusMesh,平放地面)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.44
	tm.rings = 8
	tm.ring_segments = 14
	ring.mesh = tm
	ring.material_override = _loot_mats[_loot_key(kind, q)]
	ring.rotation.x = PI / 2.0
	ring.position.y = 0.07
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(ring)
	match kind:
		"medkit":
			_build_loot_medkit(h)
		"weapon":
			_build_loot_weapon(h, wid)
		"armor":
			_build_loot_armor(h)
		"ammo":
			_build_loot_ammo(h)
		"airdrop":
			_build_loot_airdrop(h)


func _build_loot_medkit(h: Node3D) -> void:
	var white := WorldBuilder._std_tex(Color(0.95, 0.95, 0.96), 0.55, "white_metal", 0.1)
	var red := WorldBuilder._std(Color(0.88, 0.14, 0.12), 0.5)
	var box := WorldBuilder._box(0.34, 0.16, 0.24, white)
	box.position.y = 0.26
	h.add_child(box)
	var ch := WorldBuilder._box(0.16, 0.05, 0.05, red)
	ch.position = Vector3(0, 0.32, 0.13)
	h.add_child(ch)
	var cv := WorldBuilder._box(0.05, 0.14, 0.05, red)
	cv.position = Vector3(0, 0.35, 0.13)
	h.add_child(cv)
	var hd := WorldBuilder._box(0.18, 0.04, 0.04, white)
	hd.position = Vector3(0, 0.38, 0)
	h.add_child(hd)


func _build_loot_weapon(h: Node3D, wid: String) -> void:
	# [BR-FIX] 优先真枪 GLB(与玩家/枪手持有的同模,4k-20k 面,PUBG 式地面武器可辨识);
	# 缺 GLB 的 wid 回退程序化盒拼
	var def = WeaponsData.W().get(wid, null)
	var kind: String = def.kind if def != null else "rifle"
	if WeaponModels.has_glb(wid):
		# 改名 g→gg:与下方函数体的 g 同名, 会触发 CONFUSABLE_LOCAL_DECLARATION
		var gg := Node3D.new()
		if WeaponModels.build_from_glb(wid, gg):
			gg.scale = Vector3.ONE * 1.35
			gg.rotation = Vector3(0, Utils.rand(TAU), 0)   # 平躺随机朝向
			gg.position.y = 0.22
			h.add_child(gg)
			return
		gg.queue_free()
	var metal := WorldBuilder._std_tex(Color(0.32, 0.35, 0.4), 0.45, "metal_plate", 0.5)
	var wood := WorldBuilder._std_tex(Color(0.55, 0.4, 0.25), 0.6, "plywood", 0.1)
	var g := Node3D.new()
	var barrel_w := 0.07
	var barrel_l := 0.5
	match kind:
		"pistol":
			barrel_l = 0.22
			var b := WorldBuilder._box(barrel_l, 0.07, 0.06, metal)
			b.position = Vector3(0, 0.24, 0)
			g.add_child(b)
			var grip := WorldBuilder._box(0.07, 0.12, 0.06, wood)
			grip.position = Vector3(0.08, 0.14, 0)
			grip.rotation.x = 0.3
			g.add_child(grip)
		"shotgun":
			barrel_l = 0.48
			barrel_w = 0.09
			var b := WorldBuilder._box(barrel_l, barrel_w, barrel_w, metal)
			b.position = Vector3(0, 0.24, 0)
			g.add_child(b)
			var tube := WorldBuilder._box(0.4, 0.05, 0.05, metal)
			tube.position = Vector3(0, 0.2, 0)
			g.add_child(tube)
			var stock := WorldBuilder._box(0.14, 0.1, 0.07, wood)
			stock.position = Vector3(-0.25, 0.24, 0)
			g.add_child(stock)
		"sniper":
			barrel_l = 0.62
			var b := WorldBuilder._box(barrel_l, 0.07, 0.07, metal)
			b.position = Vector3(0.05, 0.24, 0)
			g.add_child(b)
			var scope := WorldBuilder._cyl(0.035, 0.035, 0.18, 8, metal)
			scope.rotation.x = PI / 2.0
			scope.position = Vector3(0.05, 0.32, 0)
			g.add_child(scope)
			var stock := WorldBuilder._box(0.16, 0.1, 0.07, wood)
			stock.position = Vector3(-0.26, 0.24, 0)
			g.add_child(stock)
		"rpg":
			var tube := WorldBuilder._cyl(0.06, 0.06, 0.55, 10, metal)
			tube.rotation.x = PI / 2.0
			tube.position = Vector3(0, 0.26, 0)
			g.add_child(tube)
			var nose := WorldBuilder._cone(0.06, 0.1, 8, metal)
			nose.rotation.x = PI / 2.0
			nose.position = Vector3(0.3, 0.26, 0)
			g.add_child(nose)
		_:
			var b := WorldBuilder._box(barrel_l, barrel_w, barrel_w, metal)
			b.position = Vector3(0, 0.24, 0)
			g.add_child(b)
			var body := WorldBuilder._box(0.2, 0.11, 0.08, metal)
			body.position = Vector3(-0.1, 0.24, 0)
			g.add_child(body)
			var mag := WorldBuilder._box(0.06, 0.12, 0.05, metal)
			mag.position = Vector3(-0.08, 0.15, 0)
			mag.rotation.x = 0.25
			g.add_child(mag)
			var stock := WorldBuilder._box(0.15, 0.09, 0.07, wood)
			stock.position = Vector3(-0.26, 0.24, 0)
			g.add_child(stock)
	g.rotation.x = PI / 2.0
	g.position.y = 0.2
	h.add_child(g)


func _build_loot_armor(h: Node3D) -> void:
	var plate := WorldBuilder._std_tex(Color(0.4, 0.5, 0.65), 0.6, "metal_plate", 0.3)
	var dark := WorldBuilder._std(Color(0.2, 0.24, 0.3), 0.7)
	var chest := WorldBuilder._box(0.34, 0.3, 0.1, plate)
	chest.position.y = 0.3
	chest.rotation.x = 0.12
	h.add_child(chest)
	var ridge := WorldBuilder._box(0.36, 0.34, 0.05, dark)
	ridge.position.y = 0.32
	ridge.rotation.x = 0.12
	h.add_child(ridge)
	var strap_l := WorldBuilder._box(0.3, 0.05, 0.04, dark)
	strap_l.position = Vector3(0, 0.32, 0.08)
	strap_l.rotation.z = 0.35
	h.add_child(strap_l)
	var strap_r := WorldBuilder._box(0.3, 0.05, 0.04, dark)
	strap_r.position = Vector3(0, 0.32, -0.08)
	strap_r.rotation.z = -0.35
	h.add_child(strap_r)


func _build_loot_ammo(h: Node3D) -> void:
	var olive := WorldBuilder._std_tex(Color(0.5, 0.52, 0.32), 0.7, "corrugated_iron", 0.2)
	var dark := WorldBuilder._std(Color(0.3, 0.32, 0.22), 0.7)
	var box := WorldBuilder._box(0.3, 0.2, 0.24, olive)
	box.position.y = 0.24
	h.add_child(box)
	var stripe := WorldBuilder._box(0.31, 0.05, 0.05, dark)
	stripe.position = Vector3(0, 0.28, 0.13)
	h.add_child(stripe)
	var hd := WorldBuilder._box(0.16, 0.04, 0.04, dark)
	hd.position = Vector3(0, 0.36, 0)
	h.add_child(hd)


## 空投箱(落地后成为可拾取 loot):橄榄绿波纹铁箱体 + 白色标志条
func _build_loot_airdrop(h: Node3D) -> void:
	var olive := WorldBuilder._std_tex(Color(0.42, 0.46, 0.3), 0.7, "corrugated_iron", 0.2)
	var box := WorldBuilder._box(1.3, 0.9, 1.3, olive)
	box.position.y = 0.45
	h.add_child(box)
	var band := WorldBuilder._box(1.32, 0.16, 1.32, WorldBuilder._std(Color(0.9, 0.9, 0.85), 0.6))
	band.position.y = 0.45
	h.add_child(band)
	var crate_top := WorldBuilder._box(1.1, 0.1, 1.1, WorldBuilder._std(Color(0.55, 0.35, 0.2), 0.8))
	crate_top.position.y = 0.95
	h.add_child(crate_top)


func _consume_loot(loot) -> void:
	loot["used"] = true
	loot["holder"].visible = false


func _roll_kind() -> String:
	var r := randf()
	if r < 0.55:
		return "weapon"
	if r < 0.70:
		return "armor"
	if r < 0.85:
		return "medkit"
	return "ammo"


func _roll_weapon() -> String:
	var keys := WeaponsData.W().keys()
	return str(Utils.choice(keys))


func _roll_quality() -> int:
	var r := randf()
	if r < 0.55:
		return 0
	if r < 0.85:
		return 1
	return 2


func _roll_loot_kind() -> String:
	var r := randf()
	if r < 0.65:
		return "weapon"
	if r < 0.82:
		return "armor"
	return "medkit"


## 物资悬浮动画(节流:静态球体无碰撞需求,近处每帧平滑,远处 0.5s 一拍)
## [PERF] 120 物资实体:远处每帧只做距离判断(CPU 近零),0.5s 才更新 transform
var _loot_anim_t := 0.0
func _update_loot_anim(dt: float) -> void:
	_loot_anim_t += dt
	var full := _loot_anim_t >= 0.5
	var p = G.player
	var ppos: Vector3 = p.pos if p != null else Vector3.ZERO
	for l in _loot:
		if l["used"]:
			continue
		var h = l["holder"]
		if full or ppos.distance_to(l["pos"]) < 60.0:
			h.rotation.y += dt * 1.2
			h.position.y = l["base_y"] + sin(G.time * 2.4 + h.rotation.y) * 0.07
	if full:
		_loot_anim_t = 0.0


func _refresh_loot_round() -> void:
	# 已拾取物资在随机空闲物资点重刷一轮(中盘/空投后)
	var free_points := []
	for i in loot_points.size():
		if randf() < 0.55:
			free_points.append(loot_points[i])
	if free_points.is_empty():
		return
	for l in _loot:
		if not l["used"]:
			continue
		var pt: Vector3 = Utils.choice(free_points)
		var kind: String = _roll_loot_kind()
		var wid := _roll_weapon() if kind == "weapon" else ""
		var gh: float = G.ground_h.call(pt.x, pt.z) if G.ground_h.is_valid() else 0.0
		var pos := Vector3(pt.x + Utils.rand(-3.0, 3.0), gh + 0.45, pt.z + Utils.rand(-3.0, 3.0))
		l["kind"] = kind
		l["id"] = wid
		l["quality"] = _roll_quality()
		l["used"] = false
		l["pos"] = pos
		l["base_y"] = pos.y
		l["holder"].position = pos
		l["holder"].visible = true
		_build_loot_model(l["holder"], kind, wid, l["quality"])
	if G.hud != null:
		G.hud.banner("物资刷新 — 搜索补给补充装备!")


## 玩家拾取交互(player.gd 每帧调用;靠近 + 按 E)
func pickup_hint_nearest(p_pos: Vector3, radius: float) -> Variant:
	var best = null
	var best_d := radius * radius
	for l in _loot:
		if l["used"]:
			continue
		var dx := (l["pos"] as Vector3).x - p_pos.x
		var dz := (l["pos"] as Vector3).z - p_pos.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d:
			best_d = d2
			best = l
	if best == null:
		return null
	return { "label": _loot_label(best), "loot": best }


func _loot_label(loot) -> String:
	match loot["kind"]:
		"weapon":
			var def = WeaponsData.W().get(loot["id"])
			var qn: String = ["普通", "稀有", "史诗"][mini(int(loot["quality"]), 2)]
			return "%s(%s)" % [def.cn if def != null else loot["id"], qn]
		"armor":
			return "护甲(减伤 30%)"
		"medkit":
			return "医疗包(+50 HP)"
		"airdrop":
			return "空投物资(史诗装备)"
		_:
			return "弹药补给"


func try_player_pickup(p) -> bool:
	var hit = pickup_hint_nearest(p.pos, PICK_RADIUS)
	if hit == null:
		return false
	var loot = hit["loot"]
	# 空投箱是组合补给,不是单一 kind:必须在这里展开为武器+护甲+医疗包,
	# 不能直接丢给 br_pickup("airdrop")(Player 没有该 kind,导致空投永远捡不起来)。
	if loot["kind"] == "airdrop":
		var aw := str(loot.get("id", ""))
		if aw == "" or not WeaponsData.W().has(aw):
			aw = _roll_weapon()
		if p.br_pickup("weapon", aw, 2):
			p.br_pickup("armor", "", 0)
			p.br_pickup("medkit", "", 0)
			_consume_loot(loot)
			if G.effects != null:
				G.effects.shake(0.08)
			AudioSys.capture(true)
			return true
		return false
	if p.br_pickup(loot["kind"], loot["id"], int(loot["quality"])):
		_consume_loot(loot)
		if G.effects != null:
			G.effects.shake(0.05)
		AudioSys.capture(true)
		return true
	return false


## 品质加成统一实现:伤害 +25%/级,弹匣/备弹按比例小幅提升;
## 绝对值的 +10 发会导致 5 发武器史诗品质变成 25 发。
func _quality_def(d, q: int) -> Variant:
	var c: Variant = Utils.def_copy(d)
	if q <= 0:
		return c
	var base_mag: int = c.mag
	var base_reserve: int = c.reserve
	c.damage = c.damage * (1.0 + 0.25 * q)
	c.mag = maxi(1, int(round(float(base_mag) * (1.0 + 0.15 * q))))
	c.reserve = maxi(0, int(round(float(base_reserve) * (1.0 + 0.2 * q))))
	return c


## AI Agent 接口:让 bot 拾取物资(武器/医疗/弹药即时生效;护甲数据由 AI Agent 记录)
func pickup_for(actor, loot) -> bool:
	if loot == null or loot["used"]:
		return false
	if actor is Object and is_same(actor, G.player):
		return try_player_pickup(actor)
	if not _bot_jump.has(actor) and actor.alive == false:
		return false
	if not (loot is Dictionary):
		return false
	if not loot.has("kind"):
		return false
	match loot["kind"]:
		"airdrop":
			# [3A 8/10] 空投箱:史诗武器 + 护甲 + 医疗包(玩家直接获得,机器人仅换武器)
			if actor is Object and is_same(actor, G.player):
				var aw := str(loot.get("id", ""))
				if aw == "":
					aw = _roll_weapon()
				if actor.br_pickup("weapon", aw, 2):
					actor.br_pickup("armor", "", 0)
					actor.br_pickup("medkit", "", 0)
					_consume_loot(loot)
					return true
				return false
			var aw2 := str(loot.get("id", ""))
			if aw2 == "" or not WeaponsData.W().has(aw2):
				aw2 = _roll_weapon()
			actor.weapon_id = aw2
			actor.def = _quality_def(WeaponsData.W()[aw2], 2)
			actor.ammo = actor.def.mag
			actor.reloading = false
			_consume_loot(loot)
			return true
		"weapon":
			var wid: String = str(loot["id"])
			if not WeaponsData.W().has(wid):
				return false
			actor.weapon_id = wid
			actor.def = _quality_def(WeaponsData.W()[wid], int(loot["quality"]))
			actor.ammo = actor.def.mag
			actor.reloading = false
			_consume_loot(loot)
			return true
		"medkit":
			actor.health = minf(100.0, actor.health + 50.0)
			_consume_loot(loot)
			return true
		"ammo":
			if actor.def != null:
				actor.ammo = actor.def.mag
			_consume_loot(loot)
			return true
		"armor":
			_consume_loot(loot)
			return true
	return false


## AI Agent 接口:物资快照(用于 bot 寻宝决策)
func loot_snapshot() -> Array:
	var out := []
	for l in _loot:
		if l["used"]:
			continue
		out.append({ "pos": l["pos"], "kind": l["kind"], "id": l["id"], "quality": l["quality"] })
	return out


## ==================== 空投 ====================
func _update_airdrops(dt: float) -> void:
	while _airdrop_idx < _airdrop_times.size() and round_time >= float(_airdrop_times[_airdrop_idx]):
		_airdrop_idx += 1
		_trigger_airdrop()
	for i in range(_airdrop_crates.size() - 1, -1, -1):
		var c: Dictionary = _airdrop_crates[i]
		if c["landed"]:
			continue
		var holder: Node3D = c["holder"]
		if not is_instance_valid(holder):
			_airdrop_crates.remove_at(i)
			continue
		c["pos"] = holder.position + Vector3(0, -22.0 * dt, 0)
		var gy: float = G.ground_h.call(c["pos"].x, c["pos"].z) if G.ground_h.is_valid() else 0.0
		if c["pos"].y <= gy + 0.4:
			c["pos"].y = gy + 0.4
			c["landed"] = true
			var chute: Node3D = holder.get_node_or_null("Chute")
			if chute != null:
				chute.visible = false
			_spawn_airdrop_loot(c["pos"], holder)
		holder.position = c["pos"]


func _trigger_airdrop() -> void:
	var a := Utils.rand(TAU)
	var r := Utils.rand(0.0, maxf(40.0, zone_radius * 0.7))
	var pos := zone_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	pos.y = 260.0
	airdrop.emit(pos)
	# 空投箱(程序化:箱体 + 降落伞)
	var holder := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.9, 1.3)
	box.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.45, 0.48, 0.3)
	bmat.roughness = 0.7
	box.material_override = bmat
	holder.add_child(box)
	var chute := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 2.2
	cm.height = 1.2
	chute.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.75, 0.35, 0.2)
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chute.material_override = cmat
	chute.name = "Chute"
	chute.position = Vector3(0, 1.6, 0)
	holder.add_child(chute)
	holder.position = pos
	G.world_root.add_child(holder)
	_airdrop_crates.append({ "holder": holder, "pos": pos, "landed": false })
	if G.hud != null:
		G.hud.banner("空投投放!内含史诗装备")
	_hint("空投已投放 — 地图上有标记,去抢史诗装备!")


func _spawn_airdrop_loot(pos: Vector3, crate_holder: Node3D = null) -> void:
	# [3A 8/10] 空投箱落地即可交互拾取:箱体重建为实体模型(波纹铁贴图 + 标志条)
	# 并注册为 kind=airdrop 的可拾取 loot(玩家 E 拾取 = 史诗武器+护甲+医疗包)
	var holder: Node3D = crate_holder if (crate_holder != null and is_instance_valid(crate_holder)) else _take_holder()
	if holder != null:
		holder.position = pos
		holder.visible = true
		holder.rotation = Vector3(0, Utils.rand(TAU), 0)
		_build_loot_model(holder, "airdrop", "", 2)
		_loot.append({ "holder": holder, "kind": "airdrop", "id": "", "quality": 2,
			"used": false, "pos": pos, "base_y": pos.y })
	# 箱旁散落 3 件装备(供机器人与路过玩家拾取)
	var contents := [["weapon", _roll_weapon(), 2], ["armor", "", 0], ["medkit", "", 0]]
	for i in contents.size():
		var c: Array = contents[i]
		var p := pos + Vector3(Utils.rand(-1.6, 1.6), 0.0, Utils.rand(-1.6, 1.6))
		p.y = (G.ground_h.call(p.x, p.z) if G.ground_h.is_valid() else 0.0) + 0.45
		_place_loot(p, c[0], c[1], c[2])


## ==================== 载具 ====================
func _spawn_vehicle_at(i: int) -> void:
	if i >= vehicle_points.size():
		return
	var pt: Vector3 = vehicle_points[i]
	var gh: float = G.ground_h.call(pt.x, pt.z) if G.ground_h.is_valid() else 0.0
	var vtype: String = _veh_defs[i] if i < _veh_defs.size() else "jeep"
	var v := Vehicle.new(pt.x, gh, Utils.rand(TAU), vtype)
	G.vehicles.append(v)
	G.main.add_child(v)
	_veh_at[v] = i


func _update_vehicles(dt: float) -> void:
	for i in _veh_respawn.keys():
		var t: float = _veh_respawn[i]
		if t > 0.0:
			t -= dt
			if t <= 0.0:
				_spawn_vehicle_at(i)
			else:
				_veh_respawn[i] = t
	for i in range(G.vehicles.size() - 1, -1, -1):
		var v = G.vehicles[i]
		if v == null or v.dead:
			var pi: int = int(_veh_at.get(v, -1))
			if pi >= 0:
				_veh_respawn[pi] = VEH_RESPAWN
			_veh_at.erase(v)
			if v != null:
				v.dispose()
			G.vehicles.remove_at(i)


## ==================== AI 目标点(替代旗帜,防 pick_objective 崩溃) ====================
func _create_ai_objectives() -> void:
	_ai_flags.clear()
	if _flag_node != null and is_instance_valid(_flag_node):
		_flag_node.queue_free()
	_flag_node = Node3D.new()
	_flag_node.name = "BRObjectives"
	G.world_root.add_child(_flag_node)
	# 以物资点/载具点为巡逻目标,确保 bot 在安全区内活动
	var pool: Array = []
	for i in mini(10, loot_points.size()):
		pool.append(loot_points[i])
	for v in vehicle_points:
		pool.append(v)
	for i in mini(pool.size(), 8):
		var pt: Vector3 = pool[i]
		var f := Flag.new("BR%d" % i, pt.x, pt.z)
		f.radius = 30.0
		f.hide_visuals()
		_flag_node.add_child(f)
		_ai_flags.append(f)
		G.flags.append(f)


## ==================== 击杀/排名 ====================
## 契约签名(killer, victim, head)由 game.gd on_kill → G.portal.active 接线
func on_player_killed(killer, victim, head := false) -> void:
	if _ended or victim == null:
		return
	# [PERF] P1-3:重生压制事件驱动(死亡即 1e9;原逐帧扫描 G.bots 兜底)
	victim.respawn_t = 1e9
	# 任务4:同队击杀不计分(玩家杀同队 bot 不算击杀数;bot 同队已免伤,此为兜底)
	if killer != null and killer != victim and not _br_same_squad(killer, victim):
		_kill_stats[killer] = int(_kill_stats.get(killer, 0)) + 1
	if _eliminated.has(victim):
		return  # 幂等:防重复接线/zone 双杀
	var is_p := victim is Object and is_same(victim, G.player)
	# [BR-Z] 毒圈环境击杀判定(killer=null 且死亡位置在安全区外;仅 bot 走此路径)
	var zone_kill: bool = not is_p and killer == null and _is_zone_env_kill(victim)
	# [BR-Z] 玩家重部署途中(直升机/跳伞)被击杀:重部署失败 → 按二次阵亡真淘汰。
	# 原逻辑在此 return 吞掉击杀 → 落地时 _finalize_redeploy 复活(alive=true/HP100)
	# → _player_deaths 未递增、_eliminated 未标记 → 循环重部署;_player_zone_acc 残留
	# → 重部署落地后再被毒圈毒死时状态机错乱(问题①根因之一)
	if is_p and _redeploy_active():
		_cancel_redeploy()
		_player_jump = ""
		_player_zone_acc = 0.0
		print("[BR-Z] 玩家重部署途中阵亡 → 重部署取消,按二次阵亡真淘汰")
	# [HZ-RULE] 按 Battlefield 2042 Hazard Zone(禁区冲突)规则:NPC 阵亡即永久淘汰,
	# 不再免费“首死入队复活一次”。玩家保留一次 Reinforcement Uplink 式重部署机会。
	if not is_p and not victim.br_redeployed:
		victim.br_redeployed = true
		print("[BR-R] bot=%d 阵亡 → 按禁区冲突规则永久淘汰(不再复活)" % victim.id)
	if not is_p:
		print("[BR-R] bot=%d %s → 真淘汰(排名结算)" % [victim.id, ("毒圈首杀[BR-Z] 环境击杀" if zone_kill else "阵亡")])
	# [BR-R] 玩家首次阵亡:不淘汰 → 进入重部署等待(20s 内按 R 或超时自动乘直升机重返战场);
	# 掉落/观战回放照常(尸体留场),但不标记 _eliminated、不记队伍排名 —— 二次阵亡才结算排名
	if is_p and _player_deaths == 0:
		_player_deaths += 1
		_drop_victim_loot(victim)
		_replay_killer = _replay_killer_for(killer)
		player_eliminated.emit(victim, killer, head)
		_begin_redeploy_wait(killer)
		return
	if is_p:
		_player_deaths += 1
		print("[BR-R] 玩家二次阵亡 → 真淘汰,进入排名结算")
	# 任务4:排名按队伍 —— 队内最后一人的淘汰顺序决定该队名次(第 N 队 → 第 N 名)
	var v_sq := _actor_squad(victim)
	_eliminated[victim] = 1
	# [PERF] P1-2:存活计数事件驱动增量维护(原每帧双扫描 + _alive_teams 字典分配;
	# 淘汰幂等由上方 _eliminated.has 守卫保证,此处恰好减一次)
	br_alive -= 1
	var sq_dead := _squad_dead(v_sq)
	if sq_dead:
		br_alive_teams -= 1
	# 击杀掉落:受害者主武器生成可拾取 loot(与 bot.gd:261 视觉掉落并存,拾取以本处 loot 为准)
	_drop_victim_loot(victim)
	if is_p:
		_replay_killer = _replay_killer_for(killer)
	var vname := _actor_display_name(victim)
	var kname := "毒圈"
	if killer != null:
		kname = _actor_display_name(killer)
	# 队淘汰判定:该队最后一人阵亡 → 记录队伍排名(玩家队被淘汰时同步玩家排名)
	var team_rank := 0
	if sq_dead:
		team_rank = br_alive_teams + 1
		if v_sq >= 0:
			_team_ranks[v_sq] = team_rank
		if v_sq == BR_PLAYER_SQUAD:
			_player_rank = team_rank
			print("[BR-R] 玩家二次阵亡 排名确定 = 第 %d 名(队伍 #%d)" % [team_rank, v_sq])
	# portal 契约信号(victim, killer, head)+ 排名播报补充信号
	player_eliminated.emit(victim, killer, head)
	if team_rank > 0:
		br_eliminated.emit(vname, team_rank, kname)
		print("[BR-T] 任务4 队伍 #%d 淘汰 排名=%d 最后=%s(击杀者 %s) 存活队伍=%d/%d" % [
			v_sq, team_rank, vname, kname, br_alive_teams, BR_TEAMS])
	else:
		print("[BR-M] 队员淘汰(队仍存活) %s 被%s淘汰 存活=%d人 %d队" % [
			vname, kname, br_alive, br_alive_teams])


## [BR-Z] 毒圈环境击杀判定:无击杀者(killer=null)且死亡位置在安全区外
## (bot 专用;玩家毒圈首死仍走重部署,B 端此路径由 is_p 前置排除)
func _is_zone_env_kill(v) -> bool:
	if v == null or v.get == null:
		return false
	var p: Variant = v.get("pos")
	if not (p is Vector3):
		return false
	return Vector2(p.x - zone_center.x, p.z - zone_center.z).length() > zone_radius


## [BR-R] 观战回放击杀者引用防护(有效实例/Dictionary 才保留)
func _replay_killer_for(killer) -> Variant:
	if killer != null and (killer is Object and is_instance_valid(killer) or killer is Dictionary):
		return killer
	return null


## actor → 展示名(统一实现 Bot.display_name:玩家"你"/bot 优先 bot_name/name;缺失 "?")
func _actor_display_name(a) -> String:
	return Bot.display_name(a, "?")


## 击杀掉落:受害者当前主武器生成可拾取 loot(bot 走 weapon_id 字段,玩家走 gun().id,
## 玩家死亡同样掉枪——BR 机制);玩家护甲 >0 时顺带掉护甲 loot。
## 掉落球可被 pickup_hint_nearest / pickup_for 拾取;质量 0(普通)。
func _drop_victim_loot(victim) -> void:
	if _ended or victim == null:
		return
	var wid := ""
	var raw_pos: Variant = victim.get("pos")
	var pos: Vector3 = raw_pos if (raw_pos is Vector3) else Vector3.ZERO
	if victim is Object and is_same(victim, G.player):
		var g = victim.gun()
		if g is Dictionary:
			wid = str(g.get("id", ""))
		elif g != null and is_instance_valid(g) and g.get("id") != null:
			wid = str(g.get("id"))
	else:
		var w: Variant = victim.get("weapon_id")
		if w != null:
			wid = str(w)
	var drop_pos := pos + Vector3(0, 0.5, 0)
	# 掉落武器保留受害者武器品质(NPC 拾取过稀有/史诗枪后,阵亡时按原品质掉落)
	var drop_q := 0
	var qv: Variant = victim.get("br_weapon_q")
	if qv != null:
		drop_q = int(qv)
	if wid != "" and WeaponsData.W().has(wid):
		_place_loot(drop_pos, "weapon", wid, drop_q)
		print("[BR-DROP] 生成掉落 loot=weapon id=%s q=%d @%.1f,%.1f,%.1f" % [wid, drop_q, drop_pos.x, drop_pos.y, drop_pos.z])
	# NPC 护甲同样掉出,玩家可 E 拾取
	var armor_val: Variant = victim.get("br_armor")
	if armor_val != null and float(armor_val) > 0.01:
		var bapos := drop_pos + Vector3(0, 0.7, 0)
		_place_loot(bapos, "armor", "", 0)
		print("[BR-DROP] 生成掉落 loot=armor @%.1f,%.1f,%.1f" % [bapos.x, bapos.y, bapos.z])
	# [3A 8/10] 死亡掉落医疗包:受害者(玩家)携带医疗包时掉 1 个
	if victim is Object and is_same(victim, G.player) and int(victim.br_medkits) > 0:
		var mpos := drop_pos + Vector3(0, 0.9, 0)
		_place_loot(mpos, "medkit", "", 0)
		print("[BR-DROP] 生成掉落 loot=medkit @%.1f,%.1f,%.1f" % [mpos.x, mpos.y, mpos.z])


## 伤害登记(架构 Agent 接线:game.gd fire_hitscan/explode → _portal_damage → on_damage)
func on_damage(attacker, victim, amount: float) -> void:
	if amount <= 0.0:
		return
	# 任务4:同队伤害不计(队友间互伤不产生数据)
	if attacker != null and attacker is Object and is_same(attacker, G.player) \
			and not _br_same_squad(attacker, victim):
		_dmg_stats[G.player] = float(_dmg_stats.get(G.player, 0.0)) + amount


## 玩家是否已真淘汰(二次阵亡/重部署途中被击落;死亡屏/观战 UI 查询用)
func is_player_eliminated() -> bool:
	return _player_deaths >= 2 or (G.player != null and _eliminated.has(G.player))


## ==================== 胜负 ====================
## [BR-R] 玩家重部署期间(首次阵亡等待/直升机/跳伞)按存活计:
## "玩家未真死前队伍不算淘汰" —— 二次阵亡才记 _eliminated,队伍才算淘汰
func _redeploy_active() -> bool:
	return _redeploy != "" and not _ended


func _player_in_match() -> bool:
	return G.player != null and (G.player.alive or _redeploy_active())


func _alive_count() -> int:
	var n := 0
	if _player_in_match():
		n += 1
	for b in G.bots:
		# [BR-R] 全员重部署:bot 首死入队/乘机/跳伞途中(未真淘汰)仍计存活;二次死亡才减员
		if b != null and not _eliminated.has(b):
			n += 1
	return n


## 任务4:存活队伍数(同 squad_id 任一成员"未真淘汰"即计;无队 bot 各自成队)
## [BR-R] 全员重部署:重部署中(首死入队/乘机/跳伞)的 bot 按存活计,不导致队伍减员
func _alive_teams() -> int:
	var teams := {}
	if _player_in_match():
		teams[BR_PLAYER_SQUAD] = true
	for b in G.bots:
		if b != null and not _eliminated.has(b):
			teams[_actor_squad(b)] = true
	return teams.size()


func _actor_squad(a) -> int:
	if a == null:
		return -1
	if a is Object and G.player != null and is_same(a, G.player):
		return BR_PLAYER_SQUAD
	var v: Variant = a.get("squad_id")
	return int(v) if v != null else -1


## 队伍是否已无存活成员(在 victim 阵亡之后判定)
## [BR-R] 全员重部署:"真淘汰(二次死亡)才算死" —— 首死入队/乘机/跳伞的 bot 不算减员
func _squad_dead(sq: int) -> bool:
	if sq < 0:
		return true
	for b in G.bots:
		if b != null and not _eliminated.has(b) and _actor_squad(b) == sq:
			return false
	if sq == BR_PLAYER_SQUAD:
		# [BR-R] 玩家重部署期间不算队伍淘汰(未真死)
		return not _player_in_match()
	return true


## BR 同队判定(击杀/伤害统计:同队不互算)
func _br_same_squad(a, b) -> bool:
	var sa := _actor_squad(a)
	var sb := _actor_squad(b)
	return sa >= 0 and sa == sb


func current_zone() -> Dictionary:
	return { "center": zone_center, "radius": zone_radius }


func _check_winner() -> void:
	if _ended or not started:
		return
	var alive_teams := br_alive_teams  # [PERF] P1-2:读事件驱动缓存(原逐帧 _alive_teams 扫描)
	# 任务4:决赛圈播报按队伍
	if alive_teams <= 6 and alive_teams > 1 and G.time - _top10_at > 5.0:
		_top10_at = G.time
		if G.hud != null:
			G.hud.banner("剩 %d 队 — 决赛圈!" % alive_teams)
	if alive_teams <= 1:
		_finish()
		return
	# [BR-Z] 决赛圈(r≤2m)僵局防护:无人物理存活且所有"存活"计数 bot 均在重部署
	# (队列/乘机/跳伞,期间毒圈豁免)→ 毒圈全灭直接结算 —— 修复问题②:
	# 圈最小仍显示两队、玩家不获胜的无限等待(重部署 bot 落地即被毒圈真淘汰)
	if zone_radius <= 2.0 and _final_circle_all_redeploy():
		print("[BR-Z] 决赛圈 r=%.1fm 无人物理存活(剩余 bot 全在重部署) → 毒圈全灭直接结算 存活队伍=%d" % [
			zone_radius, alive_teams])
		_finish()


## [BR-Z] 决赛圈僵局判定:玩家已真淘汰(非重部署中)且所有未淘汰 bot 均处于
## 重部署状态(队列/乘机/跳伞)且无任何物理存活者 → 毒圈会清空全部剩余参赛者
func _final_circle_all_redeploy() -> bool:
	if G.player != null and (G.player.alive or _redeploy_active()):
		return false
	for b in G.bots:
		if b == null or _eliminated.has(b):
			continue
		if b.alive:
			return false
		if not _bot_in_redeploy(b):
			return false
	return true


## [BR-Z] bot 是否处于重部署(队列等待 / 乘机 / 跳伞)
func _bot_in_redeploy(b) -> bool:
	if _bot_jump.has(b) and (_bot_jump[b] as Dictionary)["state"] != "landed":
		return true
	for h in _br_helos:
		if (h["bots"] as Array).has(b):
			return true
	for e in _br_redeploy_queue:
		if e["bot"] == b:
			return true
	return false


func _finish() -> void:
	if _ended:
		return
	_ended = true
	started = false
	# 任务4:最后存活的队伍获胜(胜者 = 该队最后存活者;玩家队获胜即算我方胜)
	# [BR-R] 全员重部署:重部署中(未真淘汰)的 bot 仍可代表本队获胜
	var w = null
	if G.player != null and G.player.alive:
		w = G.player
	if w == null:
		for b in G.bots:
			if b != null and not _eliminated.has(b):
				w = b
				break
	var win: bool = false
	if w != null and (w is Object and is_same(w, G.player)):
		win = true
		_player_rank = 1
	elif w != null and _actor_squad(w) == BR_PLAYER_SQUAD:
		win = true  # 玩家阵亡但同队 bot 吃鸡 → 我方队伍获胜(排名第 1)
		_player_rank = 1
	elif w == null and _redeploy_active():
		# [BR-R] 玩家重部署期间其余队伍全灭 → 我方队伍幸存(排名第 1)
		win = true
		_player_rank = 1
	_cancel_redeploy()  # [BR-R] 对局收尾:取消进行中的重部署(等待/直升机/跳伞)
	_cancel_bot_redeploys()  # [BR-R] 全员重部署:释放 bot 直升机批次与队列
	var wname := _actor_display_name(w) if w != null else "无人存活"
	round_winner = wname
	var kills: int = int(_kill_stats.get(G.player, 0))
	var dmg: float = float(_dmg_stats.get(G.player, 0.0))
	result = {
		"rank": _player_rank,
		"teams": BR_TEAMS,
		"kills": kills,
		"damage": dmg,
		"time": round_time,
		"winner": wname,
		"my_win": win,
		"mvp": _mvp_dict(),
		"table": _table_dict(),
	}
	mvp_changed.emit(result["mvp"])
	print("[BR] 比赛结束 winner=%s 玩家排名=%d(队伍) 击杀=%d 伤害=%.0f 存活队伍=%d/%d" % [
		wname, _player_rank, kills, dmg, _alive_teams(), BR_TEAMS])
	_save_progress(win, kills, _player_rank)
	# [PERF] BR 对局结束:恢复画质预设(兜底由 NOTIFICATION_PREDELETE 再恢复一次)
	if GraphicsQuality != null:
		GraphicsQuality.restore_preset()
	round_ended.emit(result)
	end()


func _mvp_dict() -> Dictionary:
	var best = null
	var best_k := -1
	var best_d := -1.0
	var actors := []
	if G.player != null:
		actors.append(G.player)
	for b in G.bots:
		actors.append(b)
	for a in actors:
		var k: int = int(_kill_stats.get(a, 0))
		var d: float = float(_dmg_stats.get(a, 0.0))
		if k > best_k or (k == best_k and d > best_d):
			best = a
			best_k = k
			best_d = d
	if best == null:
		return { "name": "?", "kills": 0, "deaths": 0, "assists": 0 }
	var deaths: int = int(G.stats["deaths"]) if (best is Object and is_same(best, G.player)) else _bot_deaths(best)
	return { "name": _actor_display_name(best), "kills": best_k, "deaths": deaths, "assists": 0 }


func _bot_deaths(a) -> int:
	var d: Variant = a.get("deaths") if a != null else null
	return int(d) if d != null else 0


func _table_dict() -> Array:
	var rows: Array = []
	for a in _mvp_actors():
		if a == null:
			continue
		var deaths: int = int(G.stats["deaths"]) if (a is Object and is_same(a, G.player)) else _bot_deaths(a)
		rows.append({ "name": _actor_display_name(a), "kills": int(_kill_stats.get(a, 0)), "deaths": deaths })
	rows.sort_custom(func(x, y): return int(x["kills"]) > int(y["kills"]))
	return rows.slice(0, 5)


func _mvp_actors() -> Array:
	var actors := []
	if G.player != null:
		actors.append(G.player)
	for b in G.bots:
		actors.append(b)
	actors.sort_custom(func(a, b):
		var ka := int(_kill_stats.get(a, 0))
		var kb := int(_kill_stats.get(b, 0))
		return ka > kb or (ka == kb and float(_dmg_stats.get(a, 0.0)) > float(_dmg_stats.get(b, 0.0))))
	return actors


## ==================== 奖励/统计存档(user://player_progress.cfg,与 TDM Agent 共用) ====================
func _save_progress(win: bool, kills: int, rank: int) -> void:
	var path := "user://player_progress.cfg"
	var cfg := ConfigFile.new()
	cfg.load(path)
	var total_exp := int(cfg.get_value("progress", "exp", 0))
	var gain: int = (500 if win else 0) + kills * 15 + (100 if rank <= 10 else 0)
	cfg.set_value("progress", "exp", total_exp + gain)
	cfg.set_value("br", "games", int(cfg.get_value("br", "games", 0)) + 1)
	cfg.set_value("br", "wins", int(cfg.get_value("br", "wins", 0)) + (1 if win else 0))
	cfg.set_value("br", "kills", int(cfg.get_value("br", "kills", 0)) + kills)
	cfg.set_value("br", "best_rank", mini(int(cfg.get_value("br", "best_rank", 999)), rank))
	cfg.set_value("br", "last_gain", gain)
	cfg.save(path)
	print("[BR] 经验 +%d(吃鸡+500 / 击杀+15 / 前十+100) 累计=%d" % [gain, total_exp + gain])


## ==================== 观战(死亡回放 5s → 跟随最近存活者,Tab 切换) ====================
## [BR-R] 重部署等待期间(玩家未真死)仍走观战;直升机飞行/跳伞阶段相机由重部署接管
func is_spectating() -> bool:
	return G.player != null and not G.player.alive and G.state == "dead" and _redeploy != "helo"


## [BR-R] 重部署相机接管中(main.gd 死亡相机分支路由:直升机追尾 / 跳伞 TP 相机)
func redeploy_cam_active() -> bool:
	return _redeploy == "helo"


func update_redeploy_camera(dt: float) -> void:
	if _redeploy != "helo":
		return
	# 跳伞阶段相机已由 update_player_jump(_tp_camera_from_player)设置,这里不覆盖
	if _player_jump == "freefall" or _player_jump == "chute":
		return
	_helo_camera(dt)


func update_spectate(dt: float) -> void:
	if G.player == null or G.player.alive:
		return
	if _replay_killer == null or not is_instance_valid(_replay_killer):
		_replay_killer = null
	if _replay_killer != null and _replay_t < REPLAY_TIME:
		_replay_t += dt
		var k = _replay_killer
		var k_alive: bool = k != null and is_instance_valid(k) and k.get("pos") != null and k.get("alive") != false
		if k_alive:
			var kpos: Vector3 = k.pos
			var look: Vector3 = kpos + Vector3(-sin(k.yaw if k.get("yaw") != null else 0.0), 1.2,
				-cos(k.yaw if k.get("yaw") != null else 0.0)) * 6.0
			_cam_look_from(kpos + Vector3(0, 1.5, 0), look)
			if _replay_t >= REPLAY_TIME:
				_rebuild_spec_list()
		else:
			_rebuild_spec_list()
		return
	# 观战模式:跟随最近存活 bot,Tab 切换
	if _spec_target == null or not is_instance_valid(_spec_target) or _spec_target.alive == false:
		_rebuild_spec_list()
	if _spec_list.is_empty():
		return
	if Input.is_action_just_pressed("scoreboard"):
		_spec_idx = (_spec_idx + 1) % _spec_list.size()
		_spec_target = _spec_list[_spec_idx]
	var t = _spec_target
	if t != null and is_instance_valid(t) and t.alive:
		var tpos: Vector3 = t.pos
		var tyaw: float = t.yaw if t.get("yaw") != null else 0.0
		_cam_look_from(tpos + Vector3(0, 1.6, 0), tpos + Vector3(-sin(tyaw), 1.1, -cos(tyaw)) * 6.0)


func _rebuild_spec_list() -> void:
	_spec_list = []
	for b in G.bots:
		if b != null and b.alive:
			_spec_list.append(b)
	_spec_list.sort_custom(func(a, b): return a.pos.distance_to(G.player.pos) < b.pos.distance_to(G.player.pos))
	_spec_idx = 0
	_spec_target = _spec_list[0] if not _spec_list.is_empty() else null


func _cam_look_from(pos: Vector3, look: Vector3) -> void:
	var cam := G.camera
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = G.settings.fov


## ==================== [BR-R] 玩家重部署:状态机 ====================
## 死亡(waiting 20s 按 R 或超时自动) → 小直升机飞行(helo) → 跳伞(freefall/chute,复用跳伞
## 状态机) → 落地复活(landed,HP 满/仅手枪);二次阵亡才真淘汰并结算排名。
## 重部署全程免疫(等待期死亡无伤害结算;飞行/跳伞期 zone 伤害与 bot 伤害均被阻断)。

## 每帧驱动(玩家死亡后进入;等待窗口 / 直升机飞行)
func _update_redeploy(dt: float) -> void:
	if _ended or G.player == null:
		return
	# 死亡屏遮挡观战/直升机画面:重部署全程每帧关闭(引导以 HUD 重部署提示标签为准;
	# game.gd 1.2s 延迟显示死亡屏,若不关会在直升机飞行期盖住画面)
	if _redeploy == "waiting" or _redeploy == "helo":
		if G.hud != null:
			G.hud.hide_screen("death")
	match _redeploy:
		"waiting":
			_redeploy_t -= dt
			var left := maxi(1, int(ceil(_redeploy_t)))
			if G.hud != null and G.hud.has_method("br_redeploy_hint"):
				G.hud.br_redeploy_hint(
					"你已阵亡 · 重新部署机会(乘直升机重返战场) — 按 R 重新部署(%ds 后自动)" % left)
			if Input.is_action_just_pressed("reload"):
				_start_helo_redeploy()
				return
			if _redeploy_t <= 0.0:
				_start_helo_redeploy()
		"helo":
			_update_redeploy_helo(dt)


## 玩家首次阵亡 → 重部署等待(默认观战,20s 选择窗)
func _begin_redeploy_wait(killer) -> void:
	_redeploy = "waiting"
	_redeploy_t = REDEPLOY_WAIT
	_player_jump = ""
	_player_zone_acc = 0.0  # [BR-Z] 清残留节流累积,防重部署落地后瞬间再吃满毒圈伤害
	if G.hud != null:
		G.hud.banner("你已阵亡 · 重新部署机会(乘直升机重返战场)", true)
	_hint("按 R 重新部署(乘小直升机重返战场)")
	var kname := _actor_display_name(killer) if killer != null else "?"
	print("[BR-R] 玩家首次阵亡(击杀者 %s) → 重部署等待 %ds:按 R 或超时自动 → 乘小直升机重返" % [
		kname, int(REDEPLOY_WAIT)])


## 重部署入口(死亡屏按钮 / R 键 / 超时自动;非等待期返回 false 交由原流程)
## [BR-Z] 已真淘汰(二次阵亡/重部署途中被击落)的玩家:绝不再进重部署 —— 消费点击,
## 关闭死亡屏进入观战,修复问题①:重部署落地后二次毒圈死 → 点"重新部署"卡在死亡屏
## (原流程返回 false → main.gd 落 G.game.redeploy() → BR 分支仅打提示、死亡屏不关)
func try_redeploy_player() -> bool:
	if _ended or not started:
		return false
	if _redeploy == "waiting":
		_start_helo_redeploy()
		return true
	if _player_deaths >= 2 or (G.player != null and _eliminated.has(G.player)):
		if G.hud != null:
			G.hud.hide_screen("death")
		_hint("你已阵亡 — 观战模式(Tab 切换视角)")
		return true
	return false


## 等待 → 直升机起飞
func _start_helo_redeploy() -> void:
	if _redeploy != "waiting":
		return
	_redeploy = "helo"
	_redeploy_t = 0.0
	_player_jump = "helo"
	if G.hud != null:
		G.hud.hide_screen("death")
		if G.hud.has_method("br_redeploy_hint"):
			G.hud.br_redeploy_hint("")
	# 起点:安全区外(圈缘外 120m,钳制地图边缘内);目标:安全区中心;高度 120m
	var dir2 := Vector3(Utils.rand(-1.0, 1.0), 0.0, Utils.rand(-1.0, 1.0)).normalized()
	if dir2.length_squared() < 0.001:
		dir2 = Vector3(1.0, 0.0, 0.0)
	var dist0 := minf(zone_radius + 120.0, maxf(40.0, G.bounds - 40.0))
	_helo_start = zone_center + dir2 * dist0
	_helo_start.x = clampf(_helo_start.x, -G.bounds + 30.0, G.bounds - 30.0)
	_helo_start.z = clampf(_helo_start.z, -G.bounds + 30.0, G.bounds - 30.0)
	_helo_start.y = REDEPLOY_HELO_ALT
	_helo_target = Vector3(zone_center.x + Utils.rand(-30.0, 30.0), REDEPLOY_HELO_ALT,
		zone_center.z + Utils.rand(-30.0, 30.0))
	_helo_yaw = atan2(-dir2.x, -dir2.z)
	_build_redeploy_helo()
	if G.input_sys != null:
		G.input_sys.lock()
	print("[BR-R] 直升机起飞 start=%.0f,%.0f,%.0f → target=%.0f,%.0f 速度=%.0fm/s 高度=%.0fm" % [
		_helo_start.x, _helo_start.y, _helo_start.z, _helo_target.x, _helo_target.z,
		REDEPLOY_HELO_SPEED, REDEPLOY_HELO_ALT])


## 直升机飞行:沿航线飞向安全区中心(30m/s,120m 高),到点后玩家跳伞
func _update_redeploy_helo(dt: float) -> void:
	if _helo == null or not is_instance_valid(_helo):
		_cancel_redeploy()
		return
	_redeploy_t += dt
	var to := _helo_target - _helo.position
	to.y = 0.0
	if to.length() > 8.0:
		var dir3 := to.normalized()
		_helo_vel = dir3 * REDEPLOY_HELO_SPEED
		_helo_yaw = atan2(-dir3.x, -dir3.z)
		# 步进钳制到剩余距离,防单帧速度 > 剩余距时来回振荡永不达点
		_helo.position += dir3 * minf(REDEPLOY_HELO_SPEED * dt, to.length())
		_helo.rotation = Vector3(0, _helo_yaw, 0)
		var rotor: Node3D = _helo.get_meta("rotor") if _helo.has_meta("rotor") else null
		if rotor != null:
			rotor.rotation.y += dt * 28.0
		var tail_rotor: Node3D = _helo.get_meta("tail_rotor") if _helo.has_meta("tail_rotor") else null
		if tail_rotor != null:
			tail_rotor.rotation.x += dt * 40.0
		# 玩家乘机(第三人称在机内)
		G.player.pos = _helo.position + Vector3(0, 0.35, 0)
		G.player.vel = Vector3.ZERO
		_update_redeploy_body()
	else:
		_begin_redeploy_jump()


## 到点:玩家跳伞(复用现有跳伞状态机 freefall → chute → landed,带伞)
func _begin_redeploy_jump() -> void:
	if _player_jump != "helo":
		return
	_player_jump = "freefall"
	_player_chute = false
	_player_jvel = _helo_vel * 0.65 + Vector3(0, 2.0, 0)
	G.player.alive = true
	G.player.on_ground = false
	G.player.health = 100.0
	G.player.br_armor = 0.0
	G.player.br_medkits = 0
	G.player.spawn_protect = 8.0  # 跳伞落地前免伤(与毒圈免疫一致;state 仍为 dead 双保险)
	if G.hud != null:
		G.hud.show_screen("hud")
	_hint("跳伞!开伞后控制方向滑翔进圈")
	print("[BR-R] 直升机到点 → 玩家跳伞 freefall 初速=%.0fm/s 携带降落伞" % _helo_vel.length())


## 落地:重部署完成 —— 复活(HP 满 / 仅手枪),免疫解除,直升机飞离(直接消失)
func _finalize_redeploy(p) -> void:
	p.alive = true  # 防御:落地即复活(跳伞阶段已置 true)
	p.on_ground = true
	p.health = 100.0
	p.spawn_protect = 2.0
	_player_zone_acc = 0.0  # [BR-Z] 清残留节流累积,防落地后 1-2s 内吃满伤害暴毙
	p.br_strip_inventory()  # 复用 BR 开局剥离逻辑:仅保留手枪
	_cancel_redeploy()
	G.state = "playing"
	if G.input_sys != null:
		G.input_sys.lock()
	if G.hud != null:
		G.hud.show_screen("hud")
		G.hud.banner("重返战场!搜集物资,存活到最后一队")
	_hint("重返战场 — 乘直升机跳伞落地,继续作战")
	print("[BR-R] 重部署完成 玩家复活 pos=%.0f,%.0f,%.0f HP=100 仅手枪" % [p.pos.x, p.pos.y, p.pos.z])


## 取消/收尾:释放直升机、复位状态(对局结束/清理时调用)
func _cancel_redeploy() -> void:
	if _helo != null and is_instance_valid(_helo):
		_helo.queue_free()
	_helo = null
	_helo_vel = Vector3.ZERO
	_redeploy = ""
	_redeploy_t = 0.0
	if _player_jump == "helo":
		_player_jump = ""
	if G.hud != null and G.hud.has_method("br_redeploy_hint"):
		G.hud.br_redeploy_hint("")


## ==================== [BR-R] 全员重部署(含 AI):bot 队列 → 直升机批次 → 跳伞复活 ====================
## 与玩家同机制:所有 bot 死过一次后可乘直升机重生,二次死亡才真淘汰。
## 死亡(waiting 15-30s 随机,防瞬间满场) → 直升机批次(每架 ≤4 只,同时 ≤3 架,
## 先死先走)从圈外飞向圈内(队锚附近)→ 复用跳伞状态机 freefall/chute → 落地复活
## (HP 满/仅手枪)。重部署全程免疫(等待/乘机是尸体不受伤害;跳伞已免疫)。

## bot 首死入队(15-30s 延迟随机,错峰复活)
func _enqueue_bot_redeploy(b) -> void:
	if _ended:
		return
	var delay := Utils.rand(BR_REDEPLOY_DELAY_MIN, BR_REDEPLOY_DELAY_MAX)
	_br_redeploy_queue.append({ "bot": b, "t0": G.time, "delay": delay })
	print("[BR-R] bot=%d 首次死亡 → 重部署队列(%.0fs 后乘直升机重生) 队#%d 队列=%d" % [
		b.id, delay, _actor_squad(b), _br_redeploy_queue.size()])


## [BR-R] bot 重部署状态(bot.gd 死亡渲染门控):"" 非重部署 / "helo" 乘机 / "freefall"/"chute" 跳伞
func redeploy_state(b) -> String:
	if b == null:
		return ""
	if _bot_jump.has(b):
		var st: String = (_bot_jump[b] as Dictionary)["state"]
		if st == "freefall" or st == "chute":
			return st
	for h in _br_helos:
		if (h["bots"] as Array).has(b):
			return "helo"
	return ""


## 每帧驱动:1) 队列到期 bot 按批次分配直升机(先死先走) 2) 直升机飞行/到点跳伞
func _update_bot_redeploy(dt: float) -> void:
	if _ended or not started:
		return
	# 1) 队列到期 → 分配直升机(每架 BR_HELO_CAP 只,同时最多 BR_HELO_MAX 架)
	# 队列在分配中会收缩:外层用 while + 队首到期扫描(先死先走),不可用固定 range 索引
	while _br_helos.size() < BR_HELO_MAX:
		var lead: Variant = null
		var due_i := -1
		for qi in _br_redeploy_queue.size():
			var e: Dictionary = _br_redeploy_queue[qi]
			var b = e["bot"]
			if b == null or not is_instance_valid(b) or _eliminated.has(b):
				_br_redeploy_queue.remove_at(qi)  # 清理失效条目,重新扫描
				due_i = -2
				break
			if G.time - e["t0"] >= float(e["delay"]):
				lead = b
				due_i = qi
				break
		if due_i == -2:
			continue
		if due_i < 0:
			break  # 无到期:等待
		_br_redeploy_queue.remove_at(due_i)
		var batch: Array = [lead]
		var room: int = BR_HELO_CAP - 1
		# 顺带搭载队尾已到期 bot(批次,防直升机空载飞行;倒序移除索引安全)
		for j in range(_br_redeploy_queue.size() - 1, -1, -1):
			if room <= 0:
				break
			var e2: Dictionary = _br_redeploy_queue[j]
			var b2 = e2["bot"]
			if b2 == null or not is_instance_valid(b2) or _eliminated.has(b2):
				_br_redeploy_queue.remove_at(j)
				continue
			if G.time - e2["t0"] < float(e2["delay"]):
				continue
			_br_redeploy_queue.remove_at(j)
			batch.append(b2)
			room -= 1
		_spawn_bot_helo(batch)
	# 2) 直升机飞行 + 到点全员跳伞
	for i in range(_br_helos.size() - 1, -1, -1):
		_update_bot_helo(_br_helos[i], dt, i)


## 直升机起飞:圈外起点 → 圈内落点(队锚附近),载 ≤BR_HELO_CAP 只 bot
func _spawn_bot_helo(batch: Array) -> void:
	var dir2 := Vector3(Utils.rand(-1.0, 1.0), 0.0, Utils.rand(-1.0, 1.0)).normalized()
	if dir2.length_squared() < 0.001:
		dir2 = Vector3(1.0, 0.0, 0.0)
	var dist0 := minf(zone_radius + 120.0, maxf(40.0, G.bounds - 40.0))
	var helo_start := zone_center + dir2 * dist0
	helo_start.x = clampf(helo_start.x, -G.bounds + 30.0, G.bounds - 30.0)
	helo_start.z = clampf(helo_start.z, -G.bounds + 30.0, G.bounds - 30.0)
	helo_start.y = REDEPLOY_HELO_ALT
	var target := _bot_helo_target(batch[0])
	var node := _build_helo_mesh()
	node.position = helo_start
	node.rotation = Vector3(0, atan2(-dir2.x, -dir2.z), 0)
	G.main.add_child(node)
	_br_helos.append({ "node": node, "bots": batch, "target": target })
	var ids: Array = []
	for b in batch:
		ids.append(str(b.id))
	print("[BR-R] 直升机批次起飞 载 %d 只 bot(%s) → 圈内(%.0f,%.0f) 在飞直升机=%d/%d" % [
		batch.size(), "、".join(ids), target.x, target.z, _br_helos.size(), BR_HELO_MAX])


## 直升机落点:优先本队锚点附近(安全区内 75% 半径),否则圈内随机点
func _bot_helo_target(b) -> Vector3:
	var anchor := Vector3.ZERO
	var sq: int = _actor_squad(b)
	if sq >= 0 and sq < _squad_anchors.size():
		anchor = _squad_anchors[sq]
	var t := Vector3.ZERO
	var in_zone: bool = anchor != Vector3.ZERO \
			and Vector2(anchor.x - zone_center.x, anchor.z - zone_center.z).length() <= zone_radius * 0.75
	if in_zone:
		t = anchor + Vector3(Utils.rand(-25.0, 25.0), 0.0, Utils.rand(-25.0, 25.0))
	else:
		var a := Utils.rand(TAU)
		var r := Utils.rand(0.0, maxf(10.0, zone_radius * 0.6))
		t = zone_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	t.x = clampf(t.x, -G.bounds + 20, G.bounds - 20)
	t.z = clampf(t.z, -G.bounds + 20, G.bounds - 20)
	t.y = REDEPLOY_HELO_ALT
	return t


## 直升机飞行:30m/s 向圈内落点,乘员站位渲染;到点 → 全员跳伞(复用跳伞状态机)
func _update_bot_helo(h: Dictionary, dt: float, idx: int) -> void:
	var node: Node3D = h["node"]
	if node == null or not is_instance_valid(node):
		_br_helos.remove_at(idx)
		return
	var to := (h["target"] as Vector3) - node.position
	to.y = 0.0
	var at := to.length()
	if at > 8.0:
		var dir := to.normalized()
		node.position += dir * minf(REDEPLOY_HELO_SPEED * dt, at)
		var yaw := atan2(-dir.x, -dir.z)
		node.rotation = Vector3(0, yaw, 0)
		var rotor: Node3D = node.get_meta("rotor") if node.has_meta("rotor") else null
		if rotor != null:
			rotor.rotation.y += dt * 28.0
		var tail_rotor: Node3D = node.get_meta("tail_rotor") if node.has_meta("tail_rotor") else null
		if tail_rotor != null:
			tail_rotor.rotation.x += dt * 40.0
		var seat_i := 0
		for b in h["bots"]:
			if not is_instance_valid(b):
				continue
			b.pos = node.position + Vector3(0, 0.35, 0)
			b.vel = Vector3.ZERO
			b.yaw = yaw
			_bot_ride_pose(b, yaw, seat_i)
			seat_i += 1
		return
	# 到点:全员跳伞(跳伞物理/落地复活由 _update_bot_jumps 接管)
	for b in h["bots"]:
		if not is_instance_valid(b) or _eliminated.has(b):
			continue
		var land := _bot_helo_target(b)
		land.y = 0.0
		_bot_jump[b] = {
			"state": "freefall",
			"vel": Vector3(Utils.rand(-1.0, 1.0), 2.0, Utils.rand(-1.0, 1.0)),
			"t0": 0.0, "off": Vector3.ZERO, "target": land,
		}
		print("[BR-R] bot=%d 直升机到点 → 跳伞 落点=%.0f,%.0f(距圈心 %.0fm)" % [
			b.id, land.x, land.z, Vector2(land.x - zone_center.x, land.z - zone_center.z).length()])
	node.queue_free()
	_br_helos.remove_at(idx)


## 直升机内 bot 乘员渲染(站立机舱/空手;死亡动画由 bot.gd redeploy_state 门控跳过)
func _bot_ride_pose(b, yaw: float, _idx: int) -> void:
	if b.mesh == null:
		return
	if not b.mesh.visible:
		b.mesh.visible = true
		_vis_log_mesh(b, "shown")
	b.mesh.rotation_order = EULER_ORDER_YXZ
	b.mesh.rotation = Vector3(0, yaw, 0)
	b.mesh.position = b.pos
	_bot_show_hands(b, false)
	var leg_l: Node3D = b.mesh.get_meta("leg_l") if b.mesh.has_meta("leg_l") else null
	var leg_r: Node3D = b.mesh.get_meta("leg_r") if b.mesh.has_meta("leg_r") else null
	if leg_l != null:
		leg_l.rotation.x = 0.15
		leg_r.rotation.x = -0.1


## 收尾:释放全部 bot 重部署直升机/队列(对局结束/清理时调用)
func _cancel_bot_redeploys() -> void:
	for h in _br_helos:
		var node: Node3D = h["node"]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_br_helos.clear()
	_br_redeploy_queue.clear()


## [BR-R] bot 重部署落地复活:HP 满/仅手枪(复用开局剥装 _br_arm_bot_pistol);
## br_redeployed 保持 true → 二次死亡才真淘汰并结算排名
func _bot_redeploy_on_landed(b) -> void:
	b.alive = true
	b.health = 100.0
	b.ammo = 0
	_br_arm_bot_pistol(b)
	b.target = null
	b.target_visible = false
	b.state = "move"
	b.suppress_t = 0
	b.br_phase = "loot"
	b.br_zone_t = 0.0
	b.nav_goal_set = false
	b._set_aim_base()
	_restore_bot_visual(b)
	print("[BR-R] bot=%d 跳伞重生 pos=%.0f,%.0f,%.0f HP=100 仅手枪(二次死亡才真淘汰)" % [
		b.id, b.pos.x, b.pos.y, b.pos.z])


## [BR-R] 小型运输直升机(程序化,参考 aircraft_models.build_heli 风格,单排座运输型):
## 机身筒体 + 前风挡 + 尾梁 + 垂尾 + 主旋翼(旋转)+ 尾旋翼 + 滑橇起落架
func _build_redeploy_helo() -> void:
	_helo = _build_helo_mesh()
	_helo.position = _helo_start
	_helo.rotation = Vector3(0, _helo_yaw, 0)
	G.main.add_child(_helo)
	print("[BR-R] 小直升机建模 parts=%d 起点=%s" % [_helo.get_child_count(), str(_helo_start)])


## [BR-R] 小直升机网格构建(玩家/bot 重部署共用;位置/朝向由调用方设置)
func _build_helo_mesh() -> Node3D:
	var helo := Node3D.new()
	helo.name = "BRRHelo"
	var body := _vis_mat(Color.html("#6b734d"), 0.55, 0.3)   # 军绿机身
	var dark := _vis_mat(Color.html("#23272b"), 0.7, 0.5)    # 深灰:旋翼/滑橇
	var glass := _vis_mat(Color(0.06, 0.1, 0.15, 0.7), 0.15, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var accent := _vis_mat(Color.html("#a8432e"), 0.55, 0.25)  # 橙红饰带
	# 机身:座舱 + 尾梁 + 垂尾 + 机头饰带
	_vis_add(helo, _vis_box(1.5, 1.3, 3.6, body), 0, 0, 0)
	_vis_add(helo, _vis_box(1.3, 0.7, 1.4, glass), 0, 0.45, -1.7)
	_vis_add(helo, _vis_box(0.55, 0.55, 2.6, body), 0, 0.2, 2.7)
	_vis_add(helo, _vis_box(0.12, 0.9, 0.6, dark), 0, 0.9, 3.9)
	_vis_add(helo, _vis_box(0.9, 0.08, 0.35, accent), 0, 0.15, -1.1)
	# 主旋翼(悬停旋转)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.15, -0.2)
	for k in 2:
		var blade := _vis_box(6.4, 0.05, 0.34, dark)
		blade.rotation.y = k * PI / 2.0
		rotor.add_child(blade)
	_vis_add(helo, _vis_cyl(0.12, 0.16, 0.6, 8, dark), 0, 0.9, -0.2)  # 旋翼轴
	helo.add_child(rotor)
	helo.set_meta("rotor", rotor)
	# 尾旋翼(侧装,绕 X 旋转)
	var tail_rotor := Node3D.new()
	tail_rotor.position = Vector3(0.3, 0.85, 4.0)
	for k in 2:
		var tb := _vis_box(0.05, 1.0, 0.1, dark)
		tb.rotation.x = k * PI / 2.0
		tail_rotor.add_child(tb)
	helo.add_child(tail_rotor)
	helo.set_meta("tail_rotor", tail_rotor)
	# 滑橇起落架
	for s in [-1.0, 1.0]:
		_vis_add(helo, _vis_box(0.08, 0.08, 2.6, dark), s * 0.7, -0.85, -0.2)
		_vis_add(helo, _vis_box(0.08, 0.55, 0.08, dark), s * 0.7, -0.55, -1.2)
		_vis_add(helo, _vis_box(0.08, 0.55, 0.08, dark), s * 0.7, -0.55, 0.8)
	return helo


## [BR-R] 直升机第三人称追尾相机(机尾后上方,参考 _tp_camera_from_player 防穿墙)
func _helo_camera(dt: float) -> void:
	if _helo == null or not is_instance_valid(_helo):
		return
	var cam := G.camera
	var back := Vector3(sin(_helo_yaw), 0.2, cos(_helo_yaw))
	var eye: Vector3 = _helo.position + Vector3(0, 1.2, 0)
	var d := 11.0
	var hit = Utils.raycast_world(eye, back, d + 0.3)
	if hit != null:
		d = maxf(2.0, float(hit["dist"]) - 0.3)
	cam.global_position = eye + back * d
	cam.look_at(_helo.position + Vector3(0, 0.4, 0), Vector3.UP)
	if absf(cam.fov - G.settings.fov) > 0.05:
		cam.fov = Utils.damp(cam.fov, G.settings.fov, 18, dt)


## [BR-R] 直升机内玩家乘员显示(第三人称模型站立于机舱,空手;第一人称半身隐藏)
func _update_redeploy_body() -> void:
	var p = G.player
	if p == null:
		return
	var vb: Node3D = p.veh_body
	if vb != null:
		vb.visible = true
		vb.rotation_order = EULER_ORDER_YXZ
		vb.position = _helo.position + Vector3(0, 0.35, 0)
		vb.rotation = Vector3(0, _helo_yaw, 0)
		var leg_l: Node3D = vb.get_meta("leg_l") if vb.has_meta("leg_l") else null
		var leg_r: Node3D = vb.get_meta("leg_r") if vb.has_meta("leg_r") else null
		if leg_l != null:
			leg_l.rotation.x = 0.15
			leg_r.rotation.x = -0.1
		_hide_veh_body_weapon(vb)
	var b: Node3D = p.body
	if b != null:
		b.visible = false


## ==================== 视觉:飞机 / 毒圈环 ====================
# ---- [BR-VIS] 运输机建模辅助(仿 aircraft_models.gd:cyl/box 原语 + 标准材质) ----
func _vis_mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _vis_box(w: float, h: float, d: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = mat
	return mi


func _vis_cyl(rt: float, rb: float, h: float, segs: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	return mi


func _vis_add(parent: Node3D, mesh: MeshInstance3D, x: float, y: float, z: float) -> MeshInstance3D:
	mesh.position = Vector3(x, y, z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh)
	return mesh


## ==================== 任务2:跳伞伞具(背伞包 + 开伞伞面,程序化建模) ====================
## 伞包:背后小盒(模型原点在脚底,背后 = +z);伞面:锥形宽沿在下(半径 3.4m,相对 1.8m 角色),
## 军绿 + 橙白四瓣条纹(参考飞机建模 _vis_mat/_vis_box/_vis_cyl 风格)。
func _make_chute_kit() -> Node3D:
	var n := Node3D.new()
	n.name = "BRChuteKit"
	var pack_mat := _vis_mat(Color.html("#3e4930"), 0.85, 0.05)   # 军绿伞包
	var lid_mat := _vis_mat(Color.html("#55633f"), 0.8, 0.05)
	var cano_mat := _vis_mat(Color.html("#5d6b45"), 0.7, 0.05)    # 军绿伞面
	var white_mat := _vis_mat(Color(0.92, 0.93, 0.9), 0.7, 0.05)
	var orange_mat := _vis_mat(Color.html("#c97a2e"), 0.7, 0.05)
	# 背伞包(背后小盒):伞绳起点,freefall/chute 全程可见
	var pack := _vis_box(0.32, 0.46, 0.16, pack_mat)
	pack.position = Vector3(0, 0.82, 0.28)
	n.add_child(pack)
	var lid := _vis_box(0.27, 0.05, 0.17, lid_mat)
	lid.position = Vector3(0, 1.06, 0.28)
	n.add_child(lid)
	# 伞面:锥形(伞尖在上、宽沿在下,半径 3.4m)+ 四瓣橙白条纹
	var canopy := _vis_cyl(0.06, 3.4, 1.5, 12, cano_mat)
	canopy.position = Vector3(0, 2.6, 0)
	n.add_child(canopy)
	for i in 4:
		var st := _vis_box(0.08, 0.02, 3.1, white_mat if i % 2 == 0 else orange_mat)
		var ang := PI / 4.0 + i * PI / 2.0
		st.position = Vector3(cos(ang) * 2.05, 2.55, sin(ang) * 2.05)
		st.rotation.y = -ang + PI / 2.0
		st.rotation.x = 0.42
		n.add_child(st)
	n.set_meta("canopy", canopy)
	n.set_meta("pack", pack)
	n.visible = false
	G.main.add_child(n)
	return n


func _ensure_player_chute() -> Node3D:
	if _player_chute_n == null or not is_instance_valid(_player_chute_n):
		_player_chute_n = _make_chute_kit()
		_player_chute_canopy = _player_chute_n.get_meta("canopy")
		_player_chute_pack = _player_chute_n.get_meta("pack")
	return _player_chute_n


## 玩家伞具跟随:飞机上(模型隐藏)整体隐藏;freefall 背伞包;chute 伞面打开;落地隐藏
func _update_player_chute(p) -> void:
	var n := _ensure_player_chute()
	var chute_visible: bool = _player_jump == "freefall" or _player_jump == "chute"
	if n.visible != chute_visible:
		n.visible = chute_visible
		if _player_chute_log != chute_visible:
			_player_chute_log = chute_visible
			print("[BR-M] t=%.0f 玩家伞具 visible=%s jump=%s" % [round_time, chute_visible, _player_jump])
	if not chute_visible:
		return
	n.position = p.pos
	n.rotation = Vector3.ZERO
	n.rotation.y = p.yaw
	var open: bool = _player_jump == "chute"
	if _player_chute_canopy.visible != open:
		_player_chute_canopy.visible = open
		if _player_canopy_log != open:
			_player_canopy_log = open
			print("[BR-M] t=%.0f 玩家伞面 visible=%s jump=%s" % [round_time, open, _player_jump])
	if open:
		_player_chute_canopy.rotation.x = sin(G.time * 1.4) * 0.06  # 开伞微风摆动
		_player_chute_canopy.rotation.z = cos(G.time * 1.2) * 0.06
	else:
		_player_chute_canopy.rotation = Vector3.ZERO


## bot 伞具节点(懒创建,挂 bot.mesh 下;跳伞期间 mesh 旋转为零,局部偏移成立)
func _bot_chute_node(b) -> Node3D:
	if _bot_chutes.has(b):
		return _bot_chutes[b]
	var n := _make_chute_kit()
	if n.get_parent() != null:
		n.get_parent().remove_child(n)  # _make_chute_kit 默认挂 Main;bot 改挂自身 mesh
	b.mesh.add_child(n)
	_bot_chutes[b] = n
	return n


## bot 伞具显隐:show=false 隐藏;open=true → 伞面打开(chute 状态)
func _bot_chute_set(b, show: bool, open: bool) -> void:
	if b == null or b.mesh == null:
		return
	var n: Node3D = _bot_chute_node(b)
	if n.visible != show:
		n.visible = show
	if not show:
		return
	(n.get_meta("pack") as Node3D).visible = true
	var canopy: Node3D = n.get_meta("canopy")
	if canopy.visible != open:
		canopy.visible = open
		if _chute_log.get(b) != open:
			_chute_log[b] = open
			var jst: String = (_bot_jump[b] as Dictionary)["state"] if _bot_jump.has(b) else "landed"
			print("[BR-M] t=%.0f bot=%d 伞面 visible=%s jump=%s" % [round_time, b.id, open, jst])


## [BR-VIS] 任务1:现代运输机(程序化建模,机头朝本地 -Z 与航线一致;尾朝 +Z)
## 机身中轴下沉 y=-0.9(顶部 0.4m):玩家/bot 脚部 0.5m 立于机身上方,不穿模;
## TP 相机偏移 (3.0,2.6,3.0) 位于机身外侧(半径 1.3)/机翼上方,无遮挡。
func _build_plane() -> void:
	_plane = Node3D.new()
	_plane.name = "BRPlane"
	var body := _vis_mat(Color.html("#6b734d"), 0.55, 0.25)   # 军绿机身
	var surf := _vis_mat(Color.html("#8b8f85"), 0.6, 0.3)     # 灰:机翼/尾翼/色带
	var dark := _vis_mat(Color.html("#23272b"), 0.7, 0.5)     # 深灰:引擎短舱
	var glass := _vis_mat(Color(0.06, 0.1, 0.15, 0.75), 0.15, 0.6)  # 座舱/舷窗
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var accent := _vis_mat(Color.html("#a8432e"), 0.55, 0.25) # 尾翼色带点缀
	var ax := -0.9                                            # 机身轴心高度
	# ---- 机身:圆润筒体(24m) + 机头锥 + 尾锥(总长 ≈29.2m) ----
	var fus := _vis_cyl(1.3, 1.3, 24.0, 16, body)
	fus.rotation.x = PI / 2.0
	_vis_add(_plane, fus, 0, ax, 0)
	var nose := _vis_cyl(0.0, 1.15, 2.6, 16, body)
	nose.rotation.x = -PI / 2.0
	_vis_add(_plane, nose, 0, ax, -13.3)
	var tailc := _vis_cyl(0.0, 1.1, 2.6, 16, body)
	tailc.rotation.x = PI / 2.0
	_vis_add(_plane, tailc, 0, ax, 13.3)
	# 座舱风挡(机头上方)
	_vis_add(_plane, _vis_box(1.1, 0.5, 1.9, glass), 0, ax + 1.32, -11.4)
	# ---- 主翼:三段后掠 + 翼尖小翼(半翼展 ≈10.5m) ----
	for s in [-1.0, 1.0]:
		var root := _vis_box(2.6, 0.14, 2.3, surf)
		_vis_add(_plane, root, s * 2.7, -0.25, -1.3)
		var mid := _vis_box(3.8, 0.11, 1.9, surf)
		_vis_add(_plane, mid, s * 6.0, -0.22, -0.6)
		mid.rotation.y = -s * 0.32
		var tip := _vis_box(2.8, 0.09, 1.5, surf)
		_vis_add(_plane, tip, s * 9.2, -0.19, 0.7)
		tip.rotation.y = -s * 0.5
		var wl := _vis_box(0.12, 1.4, 0.9, surf)
		_vis_add(_plane, wl, s * 10.5, 0.35, 1.0)
		wl.rotation.y = -s * 0.5
		wl.rotation.z = s * 0.25
	# ---- 尾翼:垂尾 + 水平尾翼(后掠) ----
	var hst_l := _vis_box(2.8, 0.1, 1.6, surf)
	hst_l.rotation.y = 0.28
	_vis_add(_plane, hst_l, -3.3, 0.4, 11.4)
	var hst_r := _vis_box(2.8, 0.1, 1.6, surf)
	hst_r.rotation.y = -0.28
	_vis_add(_plane, hst_r, 3.3, 0.4, 11.4)
	var fin := _vis_box(0.22, 3.6, 2.0, surf)
	fin.rotation.x = 0.22
	_vis_add(_plane, fin, 0, 2.15, 11.6)
	_vis_add(_plane, _vis_box(0.26, 0.5, 2.05, accent), 0, 3.7, 11.7)
	# 尾翼色带:机身尾部灰带(环绕 4 段)+ 水平尾翼翼尖
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var band := _vis_box(0.4, 1.15, 0.06, surf)
		band.rotation.z = a + PI / 2.0
		_vis_add(_plane, band, cos(a) * 1.33, ax + sin(a) * 1.33, 10.4)
	_vis_add(_plane, _vis_box(0.4, 0.12, 1.4, accent), -5.5, 0.4, 11.8)
	_vis_add(_plane, _vis_box(0.4, 0.12, 1.4, accent), 5.5, 0.4, 11.8)
	# ---- 发动机:翼下 2 台短舱(cyl 短舱 + 进气口 + 喷口 + 挂架) ----
	for s in [-1.0, 1.0]:
		var nac := _vis_cyl(0.42, 0.42, 3.0, 12, dark)
		nac.rotation.x = PI / 2.0
		_vis_add(_plane, nac, s * 4.6, -0.75, -1.6)
		var intake := _vis_cyl(0.47, 0.47, 0.4, 12, dark)
		intake.rotation.x = PI / 2.0
		_vis_add(_plane, intake, s * 4.6, -0.75, -3.3)
		var nozzle := _vis_cyl(0.3, 0.34, 0.5, 10, dark)
		nozzle.rotation.x = PI / 2.0
		_vis_add(_plane, nozzle, s * 4.6, -0.75, 0.15)
		_vis_add(_plane, _vis_box(0.4, 0.55, 0.3, body), s * 4.6, -0.45, -1.6)
	# ---- 舷窗:机身两侧窗列 + 侧身灰色饰带 ----
	for s in [-1.0, 1.0]:
		for i in 12:
			_vis_add(_plane, _vis_box(0.13, 0.32, 0.15, glass), s * 1.28, ax + 0.35,
				-9.2 + i * 1.45)
		_vis_add(_plane, _vis_box(0.03, 0.42, 19.0, surf), s * 1.3, -0.28, 0)
	_plane.visible = false
	G.main.add_child(_plane)
	# [BR-VIS] 构建自检:部件数 > 8 且机身 AABB 长 20-30m(逐网格合并,含子节点变换)
	var bb := AABB()
	for child in _plane.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				bb = bb.merge(child.transform * mi.mesh.get_aabb())
	var parts := _plane.get_child_count()
	var lenm: float = bb.size.z
	print("[BR-VIS] plane built parts=%d aabb=%s len=%.1fm %s" % [
		parts, str(Vector3(round(bb.size.x), round(bb.size.y), round(bb.size.z))), lenm,
		"OK" if (parts > 8 and lenm >= 20.0 and lenm <= 30.0) else "FAIL"])


func _update_plane_visual() -> void:
	if _plane == null:
		return
	_plane.visible = phase == "lobby" or phase == "flight"
	if not _plane.visible:
		return
	_plane.position = plane_pos
	var d := Utils.safe_norm(_plane_route[1] - _plane_route[0], Vector3.FORWARD)
	_plane.rotation.y = atan2(-d.x, -d.z)


func _spawn_zone_rings() -> void:
	if _zone_ring_n != null and is_instance_valid(_zone_ring_n):
		_zone_ring_n.queue_free()
	_zone_ring_n = Node3D.new()
	_zone_ring_n.name = "BRZoneRings"
	G.world_root.add_child(_zone_ring_n)
	var mi := MeshInstance3D.new()
	mi.mesh = Flag.make_ring_mesh(0.96, 1.0, 64)
	_zone_ring_mat_in = StandardMaterial3D.new()
	_zone_ring_mat_in.albedo_color = Color(0.3, 0.75, 1.0, 0.4)
	_zone_ring_mat_in.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_ring_mat_in.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone_ring_mat_in.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = _zone_ring_mat_in
	mi.position.y = 0.1
	_zone_ring_n.add_child(mi)
	_zone_ring_in = mi
	var mo := MeshInstance3D.new()
	mo.mesh = Flag.make_ring_mesh(1.0, 1.08, 64)
	_zone_ring_mat_out = StandardMaterial3D.new()
	_zone_ring_mat_out.albedo_color = Color(1.0, 0.3, 0.25, 0.28)
	_zone_ring_mat_out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_ring_mat_out.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone_ring_mat_out.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mo.material_override = _zone_ring_mat_out
	mo.position.y = 0.05
	_zone_ring_n.add_child(mo)
	_zone_ring_out = mo


func _update_zone_rings() -> void:
	if _zone_ring_n == null or not is_instance_valid(_zone_ring_n):
		return
	var gh: float = G.ground_h.call(zone_center.x, zone_center.z) if G.ground_h.is_valid() else 0.0
	_zone_ring_n.position = Vector3(zone_center.x, gh, zone_center.z)
	var s := maxf(zone_radius, 1.0)
	_zone_ring_in.scale = Vector3(s, 1.0, s)
	_zone_ring_out.scale = Vector3(s, 1.0, s)


func _update_zone_rings_color(dt: float) -> void:
	if _zone_ring_mat_in == null:
		return
	# [PERF] 颜色节流 10Hz:每帧写材质颜色 → 每帧 GPU 状态重绑定;脉冲 6Hz,
	# 10Hz 更新视觉无感,大幅减少驱动层命令流(混合 GPU 机器 TDR/超时风险项)
	_ring_color_t += dt
	if _ring_color_t < 0.1:
		return
	_ring_color_t = 0.0
	# 缩圈期间脉冲提示
	var pulse := 1.0 + (0.12 * sin(G.time * 6.0) if zone_shrinking else 0.0)
	_zone_ring_mat_in.albedo_color = Color(0.3, 0.75, 1.0, 0.35 * pulse)
	_zone_ring_mat_out.albedo_color = Color(1.0, 0.3, 0.25, 0.25 + 0.1 * pulse)


## ==================== 地图点加载(extra 或程序化) ====================
func _load_map_points() -> void:
	loot_points = []
	vehicle_points = []
	var extra: Dictionary = {}
	var T = MapsData.M()[map_id]
	if T.get("extra") is Dictionary:
		extra = T["extra"]
	_villages = (extra.get("villages", []) as Array) if (extra.get("villages") is Array) else []
	_zone_bounds = float(extra.get("zone_bounds", 0.0))
	if _zone_bounds <= 0.0:
		_zone_bounds = maxf(100.0, float(G.bounds))
	# 物资点
	if extra.get("loot_points") is Array and not (extra["loot_points"] as Array).is_empty():
		for p in extra["loot_points"]:
			loot_points.append(_parse_point(p))
	else:
		# 程序化:沿地图环形散布(避中心)
		var n: int = 64
		for i in n:
			var a := TAU * i / float(n) + Utils.rand(-0.18, 0.18)
			var r := Utils.rand(60.0, maxf(80.0, _zone_bounds - 40.0))
			loot_points.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
		print("[BR] maps_data 缺少 loot_points,已程序化环形生成 %d 个" % loot_points.size())
	# 载具点
	_veh_defs = []
	if extra.get("vehicle_points") is Array and not (extra["vehicle_points"] as Array).is_empty():
		for v in extra["vehicle_points"]:
			if v is Dictionary and v.has("type"):
				_veh_defs.append(str(v.get("type", "jeep")))
				vehicle_points.append(_parse_point(v))
			else:
				_veh_defs.append("jeep" if vehicle_points.size() % 2 == 0 else "apc")
				vehicle_points.append(_parse_point(v))
	else:
		var n2: int = 10
		for i in n2:
			var a := TAU * i / float(n2) + Utils.rand(-0.2, 0.2)
			var r := Utils.rand(40.0, maxf(60.0, _zone_bounds - 40.0))
			vehicle_points.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
			_veh_defs.append("jeep" if i % 2 == 0 else "apc")
		print("[BR] maps_data 缺少 vehicle_points,已程序化环形生成 %d 个" % vehicle_points.size())
	# 空投航线中枢(map agent 提供 Rect2 参考区时取中心 + 沿长轴航向)
	var dz: Variant = extra.get("drop_zone", null)
	var route_dir := Vector3(Utils.rand(-1.0, 1.0), 0.0, Utils.rand(-1.0, 1.0)).normalized()
	if dz == null:
		dz = Vector3(Utils.rand(-_zone_bounds * 0.3, _zone_bounds * 0.3), 0.0, Utils.rand(-_zone_bounds * 0.3, _zone_bounds * 0.3))
		print("[BR] maps_data 缺少 drop_zone,已程序化生成 %s" % str(dz))
	if dz is Rect2:
		var rz: Rect2 = dz
		drop_zone = Vector3(rz.position.x + rz.size.x * 0.5, 0.0, rz.position.y + rz.size.y * 0.5)
		# 航线沿参考区长轴(纵向带 → 南北向,横向带 → 东西向)
		route_dir = Vector3(0, 0, 1.0) if rz.size.y > rz.size.x else Vector3(1.0, 0.0, 0.0)
		if Utils.rand(-1.0, 1.0) < 0.0:
			route_dir = -route_dir
	else:
		drop_zone = _parse_point(dz)
	# 航线:穿越空投中枢
	_plane_route[0] = drop_zone + route_dir * (_zone_bounds + 700.0) + Vector3(0, PLANE_ALT, 0)
	_plane_route[1] = drop_zone - route_dir * (_zone_bounds + 700.0) + Vector3(0, PLANE_ALT, 0)
	plane_pos = _plane_route[0]


func _parse_point(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector2:
		return Vector3(v.x, 0.0, v.y)
	if v is Array and (v as Array).size() >= 2:
		var arr: Array = v
		return Vector3(float(arr[0]), float(arr[2]) if arr.size() >= 3 else 0.0, float(arr[1]))
	if v is Dictionary and (v as Dictionary).has("x") and (v as Dictionary).has("z"):
		return Vector3(float(v.get("x", 0.0)), float(v.get("y", 0.0)), float(v.get("z", 0.0)))
	return Vector3.ZERO


func _random_land_target(_route_dir: Vector3, b = null) -> Vector3:
	# 任务4:有队伍 → 队锚 + 每员 15~30m 错位(同队落点相近;bot.gd 落点决策同步此逻辑)
	if b != null and b.squad_id >= 0 and _squad_anchors.size() > b.squad_id:
		var anchor: Vector3 = _squad_anchors[b.squad_id]
		var squad_ang := TAU * float(b.id % 4) / 4.0 + Utils.rand(-0.4, 0.4)
		var squad_rad := Utils.rand(12.0, 30.0)
		var squad_pos := anchor + Vector3(cos(squad_ang) * squad_rad, 0.0, sin(squad_ang) * squad_rad)
		squad_pos.x = clampf(squad_pos.x, -G.bounds, G.bounds)
		squad_pos.z = clampf(squad_pos.z, -G.bounds, G.bounds)
		return squad_pos
	var a := Utils.rand(TAU)
	var r := Utils.rand(60.0, _zone_bounds * 0.85)
	var p := drop_zone + Vector3(cos(a) * r, 0.0, sin(a) * r)
	p.x = clampf(p.x, -G.bounds, G.bounds)
	p.z = clampf(p.z, -G.bounds, G.bounds)
	return p


## 任务3:bot 开局只配手枪(数据层 m1911;隐藏旧主武器模型 → 空手跳伞;
## 落地仍无主武器,拾取物资由 pickup_for 换枪并 _br_swap_weapon_visual 同步外观)
func _br_arm_bot_pistol(b) -> void:
	var old_wid: String = b.weapon_id
	b.weapon_id = BR_PISTOL
	b.def = WeaponsData.W()[BR_PISTOL]
	b.ammo = b.def.mag
	b.br_weapon_q = 0
	if b.mesh != null and b.mesh.has_meta("rig"):
		var rig_b: Node3D = b.mesh.get_meta("rig")
		var old_wg: Node3D = rig_b.get_node_or_null("Weapon_" + old_wid)
		if old_wg != null:
			old_wg.visible = false


## 任务4:25 队跳伞落点锚——网格抖动均匀铺满整图(不再 80% 扎堆在少数物资点)。
## 每队落点与其他队保持 ≥55m 间距,避免数十人挤在同一个村/城区。
func _build_squad_anchors() -> void:
	_squad_anchors.clear()
	var cols := 5
	var rows := 5
	var span := _zone_bounds * 2.0
	var cell_w := span / float(cols)
	var cell_h := span / float(rows)
	for s in BR_TEAMS:
		var ix := s % cols
		var iz := int(s / cols) % rows
		var base := Vector3(-_zone_bounds + cell_w * (float(ix) + 0.5),
			0.0, -_zone_bounds + cell_h * (float(iz) + 0.5))
		var best := base
		var best_score := -1.0
		for try_i in 10:
			var cand := base + Vector3(Utils.rand(-cell_w * 0.35, cell_w * 0.35), 0.0,
				Utils.rand(-cell_h * 0.35, cell_h * 0.35))
			var score := Utils.rand(0.0, 1.0)
			# [BR-FIX] 聚落偏好:锚点落在村庄/城区 45m 内加分(PUBG 式落地即搜房;
			# 旧版 score 纯随机,注释写了"偏好聚落"但从未实现)
			for v in _villages:
				var vd := Vector2((v as Dictionary)["x"] - cand.x, (v as Dictionary)["z"] - cand.z).length()
				if vd < 45.0:
					score += 0.6
					break
			if cand.x > 185.0:
				score += 0.4   # 城市区(东北高密度)
			var ok := true
			for prev in _squad_anchors:
				if Vector2((prev as Vector3).x - cand.x, (prev as Vector3).z - cand.z).length() < 55.0:
					ok = false
					break
			# 避开河道/边界,并偏好落在有物资的聚落 12-40m 边缘(仍保持均匀铺开)
			if absf(cand.x - (-60.0)) < 34.0:
				ok = false
			if absf(cand.x) > G.bounds - 34.0 or absf(cand.z) > G.bounds - 34.0:
				ok = false
			if ok and score > best_score:
				best = cand
				best_score = score
		var pt := best
		pt.x = clampf(pt.x, -G.bounds + 24, G.bounds - 24)
		pt.z = clampf(pt.z, -G.bounds + 24, G.bounds - 24)
		_squad_anchors.append(pt)
	# 打印最小间距供 QA 核对(均匀度诊断)
	var min_d := 1e9
	for a in _squad_anchors.size():
		for b2 in range(a + 1, _squad_anchors.size()):
			min_d = minf(min_d, Vector2((_squad_anchors[a] as Vector3).x - (_squad_anchors[b2] as Vector3).x,
				(_squad_anchors[a] as Vector3).z - (_squad_anchors[b2] as Vector3).z).length())
	print("[BR-M] 25 队落点锚已网格化均匀分布,队间最小间距=%.0fm" % min_d)


## 任务4:bot.gd 落点决策接口 —— 本队落点锚(同队 4 人附近降落)
func squad_anchor(sq: int) -> Vector3:
	if sq >= 0 and sq < _squad_anchors.size():
		return _squad_anchors[sq]
	return Vector3.ZERO


func _board_player() -> void:
	if G.player == null or not G.player.alive or _boarded:
		return
	_boarded = true
	_player_jump = "plane"
	_player_jvel = Vector3.ZERO
	_player_chute = false
	G.player.pos = plane_pos + Vector3(0, 0.5, 0)
	G.player.vel = Vector3.ZERO
	G.player.on_ground = false
	G.player.br_strip_inventory()
	if G.hud != null:
		G.hud.hint("按 空格 跳伞")
	_hint("已登机 — 按 空格 跳伞")


## ==================== 玩家拾取驱动(player.gd 每帧调用) ====================
func _update_player_pickup(p) -> void:
	var hit = pickup_hint_nearest(p.pos, PICK_RADIUS)
	if hit != null:
		G.hud.hint("按 E 拾取 " + str(hit["label"]))
		if Input.is_action_just_pressed("interact"):
			try_player_pickup(p)


## ==================== 收尾/清理 ====================
## 中途离场:不判胜负,按 Hazard Zone 规则结算“演习结束”+ 当前个人/小队排名。
func _finish_aborted() -> void:
	_ended = true
	started = false
	_cancel_redeploy()
	_cancel_bot_redeploys()
	var squad_rank := _player_rank
	var player_rank := _player_rank
	if G.player != null:
		var squad_alive: bool = (G.player.alive and not _eliminated.has(G.player)) or _redeploy_active()
		if squad_alive:
			# 尚在场内:当前排名 = 存活队伍数(倒数第 N 名含义按存活队数显示)
			squad_rank = _alive_teams()
			player_rank = squad_rank
		else:
			var tr: int = int(_team_ranks.get(BR_PLAYER_SQUAD, 0))
			squad_rank = tr if tr > 0 else int(_team_ranks.get(BR_PLAYER_SQUAD, maxi(1, _alive_teams())))
			player_rank = _player_rank if _player_rank > 0 else squad_rank
	var kills: int = int(_kill_stats.get(G.player, 0))
	var dmg: float = float(_dmg_stats.get(G.player, 0.0))
	result = {
		"aborted": true,
		"rank": maxi(1, player_rank),
		"team_rank": maxi(1, squad_rank),
		"teams": BR_TEAMS,
		"kills": kills,
		"damage": dmg,
		"time": round_time,
		"winner": "演习结束",
		"my_win": false,
		"mvp": _mvp_dict(),
		"table": _table_dict(),
	}
	print("[BR] 演习结束(中途离场) 玩家排名=%d 小队排名=%d 击杀=%d 伤害=%.0f" % [
		player_rank, squad_rank, kills, dmg])
	if GraphicsQuality != null:
		GraphicsQuality.restore_preset()
	round_ended.emit(result)


## PortalManager 对局收尾路径 A(本模式 emit round_ended 后由管理器统一 G.state="end"
## 并 queue_free 本节点);此处仅做防御性兜底(无 PortalManager 驱动时自收尾)
func end(result: Dictionary = {}) -> void:
	# 中途离场(主菜单/放弃战斗):按 Hazard Zone 规则生成“演习结束”结果,不判胜负
	if bool(result.get("aborted", false)) and not _ended:
		_finish_aborted()
		return
	if not _ended:
		return
	if G.state != "end" and G.state != "over":
		G.state = "over"
		if G.input_sys != null:
			G.input_sys.unlock()
		if G.hud != null:
			G.hud.hide_screen("hud")
			G.hud.hide_screen("death")
			G.hud.hide_screen("deploy")


func _cleanup() -> void:
	if _plane != null and is_instance_valid(_plane):
		_plane.queue_free()
	_plane = null
	if _zone_ring_n != null and is_instance_valid(_zone_ring_n):
		_zone_ring_n.queue_free()
	_zone_ring_n = null
	for c in _airdrop_crates:
		if is_instance_valid(c["holder"]):
			c["holder"].queue_free()
	_airdrop_crates.clear()
	for l in _loot:
		if is_instance_valid(l["holder"]):
			l["holder"].queue_free()
	_loot.clear()
	for h in _loot_pool:
		if is_instance_valid(h):
			h.queue_free()
	_loot_pool.clear()
	_bot_jump.clear()
	_jump_dt.clear()
	_vis_log.clear()
	_wp_log.clear()
	_player_wp_logged = false
	# 任务2:清理伞具节点
	if _player_chute_n != null and is_instance_valid(_player_chute_n):
		_player_chute_n.queue_free()
	_player_chute_n = null
	_player_chute_canopy = null
	_player_chute_pack = null
	for b in _bot_chutes.keys():
		var cn = _bot_chutes[b]
		if cn != null and is_instance_valid(cn):
			cn.queue_free()
	_bot_chutes.clear()
	_chute_log.clear()
	_player_body_log = ""
	_player_chute_log = false
	_player_canopy_log = false
	# 任务4:清理队伍数据
	_team_ranks.clear()
	_squad_anchors.clear()
	_eliminated.clear()
	_bot_zone_acc.clear()  # [BR-Z] 清理 bot 毒圈伤害节流累积
	_kill_stats.clear()
	_dmg_stats.clear()
	_player_rank = BR_TOTAL
	_replay_killer = null
	_replay_t = 0.0
	_spec_target = null
	_spec_list.clear()
	_boarded = false
	_player_jump = ""
	_player_jvel = Vector3.ZERO
	_player_chute = false
	# [BR-R] 清理重部署状态(直升机节点/等待/阵亡计数)
	_cancel_redeploy()
	_player_deaths = 0
	# [BR-R] 全员重部署:清理 bot 队列/直升机批次
	_cancel_bot_redeploys()
	# 对局收尾:若中途跳伞/死亡残留第三人称状态,恢复第一人称(半身/枪械/veh_body)
	if G.player != null:
		_restore_player_fp(G.player)
	_cam_log_state = ""
	_cam_log_mode = ""
	_last_tick_frame = -1
	_player_zone_acc = 0.0
	# 移除 AI 目标旗(仅本模式创建的那些)
	for f in _ai_flags:
		G.flags.erase(f)
		if is_instance_valid(f):
			f.queue_free()
	_ai_flags.clear()
	if _flag_node != null and is_instance_valid(_flag_node):
		_flag_node.queue_free()
	_flag_node = null
