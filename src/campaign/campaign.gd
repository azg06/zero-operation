class_name Campaign extends Node
## 战役模式控制器(零度行动):章节目标状态机 + 敌军波次刷兵 + 台词广播
## 由 main 创建并 add_child;G.campaign = 实例(game.gd 兜底装配)
## 台词通过 dialogue_requested 信号发出(HUD 监听显示),不直接调用 G.hud

signal chapter_finished(win: bool)
signal dialogue_requested(name: String, text: String, dur: float)
signal cutscene_card_requested(text: String, dur: float)   # 大字卡:开场标题卡 / 目标点名卡 / 任务完成卡

var chapter_id := ""
var running := false
var done := false
var objective_index := 0

var _data: Dictionary = {}
var _objective: Dictionary = {}
var _phase := "idle"                # idle | intro | briefing | combat | outro | epilogue
var _briefing_i := 0
var _briefing_t := 0.0
var _epilogue_i := 0
var _epilogue_t := 0.0
var _kill_count := 0
var _destroy_count := 0
var _destroy_targets: Array = []
var _hold_time := 0.0
var _spawned := 0
var _wave_t := 0.0
var _deaths := 0
var _boss = null                # 当前 BOSS bot 实例(实例比对,不依赖动态属性)
var _boss_done := false
var _respawn_pos := Vector3.ZERO
# ---- 卡死兜底:当前目标无进展超时(120s)重刷敌军 + 提示 ----
var _stall_t := 0.0        # 无进展累计时长
var _stall_prog := 0.0     # 进展基准(kill 数 / destroy 数 / hold 秒 / boss 血量)
const _STALL_TIMEOUT := 120.0
# ---- 线性关卡化:封锁带 + 路线引导 ----
var _blocker_colliders: Array[AABB] = []   # 本关注册的封锁碰撞体(移除时按值从 G.colliders 删除)
var _blocker_root = null                   # 封锁带视觉件容器(G.world_root 下)
var _path: Array = []                      # 路点列表(启动点到首目标区,封锁后走廊内)
var _path_i := 0                           # 当前路点索引
var _path_marks: Array = []                # 路点光柱节点(与 _path 一一对应)
# ---- 过场(cutscene)状态 ----
var _title_card := ""           # 开场标题卡文案
var _flyover: Array = []        # 航点 [{pos, look, dur}]
var _fly_seg := 0               # 当前飞行段
var _fly_t := 0.0               # 段内进度
var _fly_done := false          # 航点播完
var _intro: Array = []          # intro 台词 [{name, text}]
var _intro_t := 0.0             # 台词播完后的缓冲计时
var _intro_line_i := 0
var _intro_line_t := 0.0        # 台词逐条间隔
var _outro: Array = []          # outro 台词
var _outro_i := 0
var _outro_t := 0.0
var _orb_t := 0.0               # outro 环视相机相位
var _player_hidden := false     # 过场中隐藏玩家视角模型
var _title_t := 0.0             # 标题卡延迟发送计时(HUD 懒连接在首帧完成)
var _title_sent := false
var _cs: Dictionary = {}        # cutscene 数据(数据子智能体提供,缺失为空)

const _CN_NUM := ["一", "二", "三", "四", "五", "六"]

# ---- 四人小队(战役队友) ----
const _REVIVE_TIME := 3.0        # 玩家救治读条时长(秒)
const _AUTO_REVIVE_TIME := 12.0  # 队友倒地后自动复活(自救)时长(秒)
const _SQUAD_DEFAULTS := [
	{ "id": "linxue", "name": "林雪", "role": "support", "weapon": "mp5", "skill": 0.88 },
	{ "id": "laozhou", "name": "老周", "role": "recon", "weapon": "m24", "skill": 0.95 },
	{ "id": "tiezhu", "name": "铁柱", "role": "engineer", "weapon": "pkm", "skill": 0.85 },
]
var _squad: Array = []          # 3 名友军 Bot 引用(林雪/老周/铁柱)
var _squad_gone: Array = []     # 已撤离队友姓名(HUD 状态展示用;现为自动复活,恒空)
var _revive_bot = null          # 正在救治的队友(Bot 引用)
var _revive_t := 0.0            # 救治读条进度
# ---- 目标区域提示 / 金色信标 / 里程碑台词 / 完成镜头 / 章末转场 ----
var _zone_in := false           # 玩家是否处于当前目标区域(进入/离开轻提示去抖)
var _hold_in := false           # hold 区首次进入台词去抖
var _beacon = null              # 目标点金色脉冲信标(Node3D,挂 G.world_root)
var _mid_said := false          # 本章 kill 里程碑台词(进度 50%)是否已触发
var _mid_pool: Array = []       # mid_lines 随机池(已播出的移出,防连播重复)
var _cam_moment_t := 0.0        # 目标完成镜头计时(0.8s 轻微拉近+震)
var _cam_moment_pos := Vector3.ZERO
var _outro_fade := false        # 章末转场:已发 fade_out 黑屏
var _outro_fade_t := 0.0
var _fail_fade := false         # 阵亡判负:已发 fade_out 黑屏
var _fail_fade_t := 0.0
var pending_transition := ""    # "fade_in"/"fade_out":HUD 轮询消费(懒连接不丢信号)
const _CAM_MOMENT_DUR := 0.8
const _CAM_MOMENT_PUSH := 0.55  # 完成镜头相机拉近量(米)
const _CAM_MOMENT_FOV := 2.5    # 完成镜头 fov 微缩量(度)
# ---- interact 交互目标(按住 E 读条):进度/视觉件/延迟生效 ----
var _interact_t := 0.0            # 读条进度(秒)
var _interact_visual = null       # 交互点视觉件容器(G.world_root 下,仿 _destroy_targets 管理)
var _interact_survivor = null     # revive_survivor 幸存者人形引用(完成时随视觉件清理)
var _interact_was_in := false     # 是否已在交互半径内(首次进入播提示音去抖)
var _interact_apply_kind := ""    # 完成后延迟生效的 kind(arm 小爆炸 0.5s 后引爆)
var _interact_apply_t := 0.0      # 延迟生效计时
var _interact_apply_pos := Vector3.ZERO

const _INTERACT_TIME := 3.0       # interact 默认读条时长(秒)
const _INTERACT_RADIUS := 4.0     # interact 默认交互半径(米)


## ============ 对外接口(契约) ============
func start_chapter(id: String) -> void:
	_data = {}
	for c in CampaignData.chapters():
		if c["id"] == id:
			_data = c
			break
	if _data.is_empty():
		_data = CampaignData.chapters()[0]
	# 数据自愈:kill 目标合计 > 敌总数 → 提升 enemy_total(防"总敌数 < kill 目标数"永久卡死)
	var need_kills := 0
	for o in _data.get("objectives", []):
		if str(o.get("type", "")) == "kill":
			need_kills += int(o.get("count", 0))
	if int(_data.get("enemy_total", 30)) < need_kills + 6:
		_data["enemy_total"] = need_kills + 6
	chapter_id = _data["id"]
	objective_index = 0
	_kill_count = 0
	_destroy_count = 0
	_free_destroy_targets()
	_clear_interact_visual()   # 换章清理交互点视觉件(幂等)
	_clear_beacon()            # 换章清理目标点信标(幂等)
	_interact_t = 0.0
	_interact_apply_t = 0.0
	_hold_time = 0.0
	_spawned = 0
	_wave_t = 2.0
	_deaths = 0
	_boss = null
	_boss_done = false
	_stall_t = 0.0
	_stall_prog = 0.0
	_zone_in = false
	_hold_in = false
	_mid_said = false
	_mid_pool = []
	_cam_moment_t = 0.0
	_outro_fade = false
	_outro_fade_t = 0.0
	_fail_fade = false
	_fail_fade_t = 0.0
	pending_transition = "fade_in"   # 重试/下一章:开场淡入(由 HUD 轮询消费)
	_objective = _data["objectives"][0]
	_respawn_pos = _data.get("start_pos", Vector3.ZERO)
	_briefing_i = 0
	_briefing_t = 0.8
	_epilogue_i = 0
	_epilogue_t = 0.0
	# ---- 过场数据(兼容旧数据:cutscene 缺失时回退 briefing/epilogue 流程) ----
	var cs: Dictionary = _data.get("cutscene", {})
	if not (cs is Dictionary) or cs.is_empty():
		cs = {}
	_cs = cs
	_title_card = str(cs.get("title_card", _data.get("title_card", chapter_title())))
	_flyover = cs.get("flyover", _data.get("flyover", []))
	if not (_flyover is Array):
		_flyover = []
	_fly_seg = 0
	_fly_t = 0.0
	_fly_done = _flyover.is_empty()
	_intro = cs.get("intro", _data.get("intro", []))
	if not (_intro is Array):
		_intro = []
	_intro_t = 0.0
	_intro_line_i = 0
	_intro_line_t = 1.0
	_outro = cs.get("outro", _data.get("outro", []))
	if not (_outro is Array):
		_outro = []
	if _outro.is_empty():
		_outro = _data.get("epilogue", [])
	_outro_i = 0
	_outro_t = 0.0
	_orb_t = 0.0
	_hide_player_model(true)
	_title_t = 0.12   # 延迟 0.12s 发送标题卡(等 HUD 首帧懒连接,防信号丢失)
	_title_sent = false
	# ---- 线性关卡化:生成封锁带碰撞+视觉件,装配路线引导 ----
	_clear_blockers()
	_spawn_blockers()
	_path = _data.get("path", [])
	if not (_path is Array):
		_path = []
	_path_i = 0
	_spawn_path_marks()
	# 有 cutscene 数据(title_card/flyover/intro 任一)→ 开场过场;否则旧 briefing 流程
	if not cs.is_empty() or not _intro.is_empty() or not _flyover.is_empty():
		_phase = "intro"
		_set_player_invincible(true)
	else:
		_phase = "briefing"
	done = false
	running = true
	# ---- 四人小队:生成 3 名友军(开场过场隐形,combat 显示) ----
	_spawn_squad()
	# 初始波次:同屏上限的 60%(立即开火的热开场)
	var cap: int = int(_data.get("enemy_cap", 10))
	for i in int(ceil(cap * 0.6)):
		if _spawned >= int(_data.get("enemy_total", 30)):
			break
		_spawn_enemy()


func update(dt: float) -> void:
	if not running:
		return
	_update_camera_moment(dt)   # 目标完成镜头:轻微拉近+fov 微缩(在玩家相机更新后执行,不打架)
	match _phase:
		"intro":
			_update_intro(dt)
		"briefing":
			_briefing_t -= dt
			if _briefing_t <= 0 and _briefing_i < _data["briefing"].size():
				var l: Dictionary = _data["briefing"][_briefing_i]
				_say(l["name"], l["text"], 4.0)
				_briefing_i += 1
				_briefing_t = 3.4
			elif _briefing_i >= _data["briefing"].size() and _briefing_t <= -1.6:
				_enter_combat()
		"combat":
			_update_waves(dt)
			_update_path(dt)
			_update_objective(dt)
			_update_squad(dt)
			_update_zone_hint()
			_update_beacon(dt)
		"outro":
			_update_outro(dt)
		"epilogue":
			_epilogue_t -= dt
			if _epilogue_t <= 0 and _epilogue_i < _data["epilogue"].size():
				var l: Dictionary = _data["epilogue"][_epilogue_i]
				_say(l["name"], l["text"], 4.5)
				_epilogue_i += 1
				_epilogue_t = 4.4
			elif _epilogue_i >= _data["epilogue"].size() and _epilogue_t <= -2.0:
				running = false
				done = true
				chapter_finished.emit(true)
	# ---- 阵亡判负转场:黑屏淡入后延迟发 chapter_finished(false) ----
	if _fail_fade:
		_fail_fade_t -= dt
		if _fail_fade_t <= 0 and not done:
			running = false
			done = true
			chapter_finished.emit(false)
	# ---- 延迟生效的 interact 效果(arm 装药完成 0.5s 后小爆炸) ----
	if _interact_apply_t > 0.0:
		_interact_apply_t -= dt
		if _interact_apply_t <= 0.0:
			_apply_delayed_interact()


## ============ 过场(开场 intro / 结算 outro) ============
## 过场中:main 停止玩家相机更新,由本控制器直接接管 G.camera
func is_cutscene() -> bool:
	return running and (_phase == "intro" or _phase == "outro")


## 玩家部署后由 game.gd 调用:过场中重新隐藏视角模型/恢复无敌
## (deploy → spawn 会重新装配武器并重置 spawn_protect,覆盖过场状态)
func apply_cutscene_state() -> void:
	if is_cutscene():
		_hide_player_model(true)
		_set_player_invincible(true)


## 当前目标的导航坐标(kill 目标无方向,返回 ZERO → HUD 不显示箭头)
func objective_pos() -> Vector3:
	if not running or _objective.is_empty() or _phase != "combat":
		return Vector3.ZERO
	if str(_objective.get("type", "")) == "kill":
		return Vector3.ZERO
	var p = _objective.get("pos")
	return p if p is Vector3 else Vector3.ZERO


## 线性关卡化·HUD 路线指向(优先级:目标坐标 > 下一路点 > 下一目标坐标 > ZERO)
## kill 等无坐标目标在路点耗尽前指向路点光柱,耗尽后指向下一个带坐标的目标区域
func route_target() -> Vector3:
	if not running or _phase != "combat" or _data.is_empty():
		return Vector3.ZERO
	if not _objective.is_empty():
		var p = _objective.get("pos")
		if p is Vector3:
			return p
	if _path_i < _path.size():
		return _path[_path_i]
	var next := objective_index + 1
	var objs: Array = _data.get("objectives", [])
	if next < objs.size():
		var np = objs[next].get("pos")
		if np is Vector3:
			return np
	return Vector3.ZERO


## 开场:航点飞行(两段间 smoothstep 插值,look 用 look_at)+ intro 台词并行 + 跳过
func _update_intro(dt: float) -> void:
	# 标题卡:延迟到 HUD 懒连接完成后再发(防信号丢失)
	if not _title_sent:
		_title_t -= dt
		if _title_t <= 0:
			_title_sent = true
			cutscene_card_requested.emit(_title_card, 3.2)
	# 航点飞行
	if not _fly_done:
		_fly_t += dt
		var n := _flyover.size()
		while _fly_seg < n:
			var dur: float = maxf(float(_flyover[_fly_seg].get("dur", 4.0)), 0.1)
			if _fly_t < dur:
				break
			_fly_t -= dur
			_fly_seg += 1
		if _fly_seg >= n:
			_fly_done = true
		else:
			_apply_fly_camera(dt, _fly_seg)
	# intro 台词逐条字幕(与飞行并行,按台词 dur 定节奏)
	_intro_line_t -= dt
	if _intro_line_t <= 0 and _intro_line_i < _intro.size():
		var l: Dictionary = _intro[_intro_line_i]
		var ld: float = float(l.get("dur", 4.0))
		_say(str(l.get("name", "陈振国上校")), str(l.get("text", "")), ld)
		_intro_line_i += 1
		_intro_line_t = ld * 0.95
	# 台词播完后的缓冲计时(与飞行完成共同门控)
	if _intro_line_i >= _intro.size():
		_intro_t -= dt
	# 跳过:空格 / 开火 / ADS
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("fire") \
			or Input.is_action_just_pressed("ads"):
		_enter_combat()
		return
	if _fly_done and _intro_line_i >= _intro.size() and _intro_t <= -0.9:
		_enter_combat()


func _apply_fly_camera(dt: float, seg: int) -> void:
	var cam: Camera3D = G.camera
	if cam == null:
		return
	var n := _flyover.size()
	var a: Dictionary = _flyover[seg]
	var from: Vector3 = a.get("pos", Vector3.ZERO)
	var from_look: Vector3 = a.get("look", Vector3(0, 0, 0))
	if seg + 1 < n:
		var dur: float = maxf(float(a.get("dur", 4.0)), 0.1)
		var u := clampf(_fly_t / dur, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)   # smoothstep 缓入缓出
		var b: Dictionary = _flyover[seg + 1]
		cam.global_position = from.lerp(b.get("pos", from), e)
		_safe_look(cam, from_look.lerp(b.get("look", from_look), e))
	else:
		# 末段悬停
		cam.global_position = from
		_safe_look(cam, from_look)
	cam.rotation.z = 0
	if absf(cam.fov - G.settings.fov) > 0.5:
		cam.fov = Utils.damp(cam.fov, G.settings.fov, 8.0, dt)


## look_at 共线守卫(目标与 up 共线时跳过,消除 WARNING)
func _safe_look(cam: Camera3D, target: Vector3) -> void:
	var d: Vector3 = target - cam.global_position
	if d.length() < 0.001:
		return
	if absf(d.normalized().dot(Vector3.UP)) > 0.9999:
		return
	cam.look_at(target, Vector3.UP)


## 进入战斗:交还玩家(相机由 player.update_player 从 yaw/pitch 自然接管)
func _enter_combat() -> void:
	if _phase == "combat":
		return
	_phase = "combat"
	_fly_done = true
	_hide_player_model(false)
	_set_player_invincible(false)
	_objective = _data["objectives"][0]
	_on_objective_active(_objective)
	# 四人小队:combat 开始显示队友
	for b in _squad:
		if is_instance_valid(b):
			b.mesh.visible = true


## HUD 懒连接补齐:战斗中补发当前目标点名卡(开场跳过时首卡可能丢信号)
func request_objective_card() -> void:
	if _phase == "combat" and objective_index < int(_data.get("objectives", []).size()):
		cutscene_card_requested.emit(_objective_name(objective_index), 2.0)


## 结算:outro 台词 + "任务完成"卡 + 环视相机;播完后 fade 黑 → 发 chapter_finished(结算屏)
func _update_outro(dt: float) -> void:
	_orb_t += dt
	_update_outro_camera(dt)
	_outro_t -= dt
	if _outro_t <= 0 and _outro_i < _outro.size():
		var l: Dictionary = _outro[_outro_i]
		var ld: float = float(l.get("dur", 4.5))
		_say(str(l.get("name", "陈振国上校")), str(l.get("text", "")), ld)
		_outro_i += 1
		_outro_t = ld * 0.95
	elif _outro_i >= _outro.size() and _outro_t <= -2.0:
		if not _outro_fade:
			_outro_fade = true
			_outro_fade_t = 1.0      # 0.5s 黑屏淡入 + 0.5s 停留,再切结算屏
			pending_transition = "fade_out"
		else:
			_outro_fade_t -= dt
			if _outro_fade_t <= 0:
				running = false
				done = true
				_hide_player_model(false)
				_set_player_invincible(false)
				chapter_finished.emit(true)


func _update_outro_camera(dt: float) -> void:
	var cam: Camera3D = G.camera
	if cam == null:
		return
	var base: Vector3 = G.player.pos if (G.player != null and G.player.alive) else Vector3.ZERO
	var a := _orb_t * 0.28
	cam.global_position = Vector3(base.x + sin(a) * 8.5, base.y + 6.0, base.z + cos(a) * 8.5)
	_safe_look(cam, Vector3(base.x, base.y + 1.6, base.z))
	cam.rotation.z = 0
	if absf(cam.fov - G.settings.fov) > 0.5:
		cam.fov = Utils.damp(cam.fov, G.settings.fov, 8.0, dt)


## 点名卡文案:cutscene.objective_names[i] > 章节级 objective_names[i] > 目标级 name > desc
func _objective_name(i: int) -> String:
	var arr = _cs.get("objective_names", _data.get("objective_names", []))
	if arr is Array and i < arr.size() and str(arr[i]) != "":
		return str(arr[i])
	var o: Dictionary = _data["objectives"][i] if i < _data["objectives"].size() else {}
	return str(o.get("name", o.get("desc", "")))


## 过场隐藏/恢复玩家视角模型(下半身由 main 在过场期间跳过覆盖)
## 只切换"已装备"枪械的可见性:收枪状态的枪模停在视角相机原点(0,0,0),
## 若全量强制显示会在屏幕正中叠出一团建模(战役"头上那团"的根因)
func _hide_player_model(hide: bool) -> void:
	_player_hidden = hide
	var p = G.player
	if p == null:
		return
	for g in p.guns:
		if g != null and g.group != null:
			g.group.visible = g.equipped and not hide
	if p.body != null:
		p.body.visible = not hide


## 过场无敌:利用 spawn_protect 防护(update_player 过场不跑,不会衰减)
func _set_player_invincible(inv: bool) -> void:
	var p = G.player
	if p == null:
		return
	p.spawn_protect = INF if inv else minf(p.spawn_protect, 2.0)


## 玩家击杀敌人(含 BOSS)时由 game.gd 调用
func on_player_kill(enemy) -> void:
	if not running:
		return
	if enemy is Object and _boss != null and is_same(enemy, _boss):
		_boss_done = true
	else:
		_kill_count += 1


## 破坏物被摧毁时由 world_builder.gd 调用(只认本关目标破坏物)
func on_destructible_destroyed(ds) -> void:
	if not running or ds == null:
		return
	if ds.get_meta("campaign_obj", -1) == objective_index \
			and ds.get_meta("campaign_counted", false) == false:
		ds.set_meta("campaign_counted", true)
		_destroy_count += 1


## 玩家阵亡时由 game.gd 调用;达上限判负
func on_player_death() -> void:
	if not running:
		return
	_deaths += 1
	var limit: int = int(_data.get("player_deaths_limit", 5))
	if _deaths >= limit:
		if not _fail_fade:
			_fail_fade = true
			_fail_fade_t = 1.0      # 0.5s 黑屏淡入 + 停留,再发判负(结算屏)
			pending_transition = "fade_out"
			_say("陈振国上校", "雪豹小队损失过大,任务中止!全体撤离战区,重新整备后再战。", 4.5)
	else:
		_say("曹锐", "别慌,我还能上。剩余部署次数:" + str(limit - _deaths), 2.5)


func objective_text() -> String:
	if not running or _data.is_empty():
		return chapter_title()
	if _objective.is_empty():
		return chapter_title()
	var d: String = "《" + str(_data.get("cn", "")) + "》 " + str(_objective.get("desc", ""))
	match str(_objective.get("type", "")):
		"kill":
			d += "  （已消灭 " + str(_kill_count) + "/" + str(_objective.get("count", 0)) + "）"
		"destroy":
			d += "  " + str(_destroy_count) + "/" + str(_objective.get("count", 0))
		"hold":
			var hold_t: float = float(_objective.get("time", 0))
			d += "  （已坚守 " + str(int(_hold_time)) + "/" + str(int(hold_t)) + " 秒,离开区域暂停）"
		"boss":
			d += "  " + ("已击毙" if _boss_done else "目标存活")
		"interact":
			var i_time: float = float(_objective.get("time", _INTERACT_TIME))
			d += "  （按住 E 进行中 " + str(int(clampf(_interact_t / maxf(i_time, 0.001), 0.0, 1.0) * 100.0)) + "%）"
	return d


## 玩家受击伤害系数(c1-c2 减负 0.8,其余 1.0)。供 game.gd 伤害结算接入;
## game.gd 当前不可改,实际减负由 _enemy_skill_range()(c1-c2 敌兵 skill ≤0.7)+ 数量下调达成
func player_damage_mult() -> float:
	return 0.8 if (chapter_id == "c1" or chapter_id == "c2") else 1.0


## 章节敌方 skill 生成范围(随章递增;c1-c2 封顶 0.7 实现第一章专属减负)
func _enemy_skill_range() -> Vector2:
	match chapter_id:
		"c1":
			return Vector2(0.45, 0.68)
		"c2":
			return Vector2(0.5, 0.7)
		"c3":
			return Vector2(0.55, 0.85)
		"c4":
			return Vector2(0.6, 0.9)
		"c5":
			return Vector2(0.7, 1.0)
		"c6":
			return Vector2(0.75, 1.05)
	return Vector2(0.6, 0.9)


## 波次补兵间隔(秒)范围:c1 更宽松 7-10s,后期 5-8s
func _wave_interval() -> Vector2:
	return Vector2(7.0, 10.0) if chapter_id == "c1" else Vector2(5.0, 8.0)


## 玩家是否处于当前目标区域(HUD 进入/离开轻提示轮询;仅 combat + 有坐标目标)
func zone_in() -> bool:
	return _zone_in and _phase == "combat" and not _objective.is_empty()


## hold 目标且玩家在区域内:返回"坚守中…剩余 X 秒"(HUD 持久提示),否则空串
func zone_status() -> String:
	if _phase != "combat" or _objective.is_empty() or str(_objective.get("type", "")) != "hold":
		return ""
	var posv: Variant = _objective.get("pos")
	if not (posv is Vector3) or G.player == null or not G.player.alive:
		return ""
	var rad: float = float(_objective.get("radius", 16.0))
	if Vector2(G.player.pos.x - posv.x, G.player.pos.z - posv.z).length() > rad:
		return ""
	var total: float = float(_objective.get("time", 0.0))
	return "坚守中… 剩余 " + str(maxi(0, int(ceil(total - _hold_time)))) + " 秒"


## HUD 每帧轮询的转场请求(start_chapter/章末/判负置位,轮询消费防懒连接丢信号)
func consume_pending_transition() -> String:
	var s := pending_transition
	pending_transition = ""
	return s


func chapter_title() -> String:
	if _data.is_empty():
		return "战役模式"
	var num: String = "一"
	for i in _CN_NUM.size():
		if _data["id"] == "c" + str(i + 1):
			num = _CN_NUM[i]
			break
	return "第" + num + "章 " + str(_data.get("cn", "")) + " — " + str(_data.get("title", ""))


func chapter_briefing() -> Array:
	return _data.get("briefing", [])


func is_last_objective() -> bool:
	return not _data.is_empty() and objective_index >= int(_data["objectives"].size()) - 1


## 供 game.gd 重部署使用:最近完成的据点(开局为章节出生点)
func respawn_point() -> Vector3:
	return _respawn_pos


## 回到主菜单/换模式时由 game.gd 调用,防止残留 running 状态误触钩子
func abort() -> void:
	running = false
	done = false
	_phase = "idle"
	_hide_player_model(false)
	_set_player_invincible(false)
	_free_destroy_targets()
	_clear_interact_visual()   # 中止清理交互点视觉件(防残留)
	_clear_beacon()            # 中止清理目标点信标(防残留)
	_interact_t = 0.0
	_interact_apply_kind = ""
	_interact_apply_t = 0.0
	_fail_fade = false
	_fail_fade_t = 0.0
	pending_transition = ""    # 中止转场请求(回菜单不留黑屏)
	_clear_blockers()   # 移除封锁带碰撞+视觉件、路点光柱(防残留)
	_clear_squad()      # 清理四人小队(移除 G.bots + queue_free)


## 释放爆破目标残留网格(换图/重试时清理,防幽灵残留)
func _free_destroy_targets() -> void:
	for ds in _destroy_targets:
		if ds.group != null and is_instance_valid(ds.group):
			ds.group.queue_free()
	_destroy_targets.clear()


## ============ 线性关卡化:封锁带(碰撞 AABB + 视觉障碍) ============
## 按章节 blockers 生成 y∈[0,h] 的碰撞体(加入 G.colliders,玩家/AI 推挤与射线避障均生效)
## 视觉件:沿封锁带长轴铺 4 段灰色混凝土/瓦砾块(不进 G.colliders,碰撞以 AABB 为准)
func _spawn_blockers() -> void:
	var list: Array = _data.get("blockers", [])
	if not (list is Array) or list.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "CampaignBlockers"
	for b in list:
		var bx: float = float(b.get("x", 0.0))
		var bz: float = float(b.get("z", 0.0))
		var bw: float = maxf(float(b.get("w", 4.0)), 1.0)
		var bd: float = maxf(float(b.get("d", 4.0)), 1.0)
		var bh: float = maxf(float(b.get("h", 3.0)), 1.0)
		var kind := str(b.get("kind", "wall"))
		var coll := AABB(Vector3(bx - bw / 2.0, 0.0, bz - bd / 2.0), Vector3(bw, bh, bd))
		G.colliders.append(coll)
		_blocker_colliders.append(coll)
		_add_blocker_visual(holder, bx, bz, bw, bd, bh, kind)
	_blocker_root = holder
	G.world_root.add_child(holder)
	Utils.rebuild_collider_grid()  # 碰撞网格重建,射线/视线/避障立即识别封锁


## 封锁带视觉:沿长轴 4 段半埋混凝土块(低配:2-4 段 + 灰色材质,不重复注册碰撞)
func _add_blocker_visual(holder: Node3D, bx: float, bz: float, bw: float, bd: float,
		bh: float, kind: String) -> void:
	var horiz := bw >= bd
	var length := maxf(bw, bd)
	var thick := clampf(minf(bw, bd) * 0.5, 0.9, 1.8)
	var seg_n := 4
	var seg := length / float(seg_n)
	var h: float = bh
	var mats: Array
	match kind:
		"barrier":
			h = minf(bh, 1.15)
			mats = [WorldBuilder._std(Color(0.42, 0.44, 0.46), 0.9)]
		"rubble":
			h = minf(bh, 2.2)
			mats = [WorldBuilder._std(Color(0.45, 0.47, 0.5), 1.0), WorldBuilder._std(Color(0.4, 0.42, 0.45), 1.0)]
		_:
			mats = [WorldBuilder._std_tex(Color(0.55, 0.56, 0.58), 0.95, "rough_concrete")]
	for i in seg_n:
		var m: MeshInstance3D
		if horiz:
			m = WorldBuilder._box(seg - 0.35, h, thick, mats[i % mats.size()])
			m.position = Vector3(bx - length / 2.0 + (i + 0.5) * seg, h / 2.0 - 0.1, bz)
		else:
			m = WorldBuilder._box(thick, h, seg - 0.35, mats[i % mats.size()])
			m.position = Vector3(bx, h / 2.0 - 0.1, bz - length / 2.0 + (i + 0.5) * seg)
		if kind == "rubble":
			m.rotation.z = Utils.rand(-0.09, 0.09)   # 瓦砾块轻微歪斜
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(m)


## 移除本章封锁:从 G.colliders 按值删除碰撞体 + queue_free 视觉件(abort/换章时调用,幂等)
func _clear_blockers() -> void:
	if not _blocker_colliders.is_empty():
		for c in _blocker_colliders:
			G.colliders.erase(c)
		_blocker_colliders.clear()
		Utils.rebuild_collider_grid()
	if _blocker_root != null and is_instance_valid(_blocker_root):
		_blocker_root.queue_free()
	_blocker_root = null
	for m in _path_marks:
		if is_instance_valid(m):
			m.queue_free()
	_path_marks.clear()


## ============ 线性关卡化:路线引导(路点 + 垂直光柱) ============
## 每个路点生成"发光细柱 + 点光源 + 黄标",可透视看到前方指引;玩家到达 12m 内自动推进
func _spawn_path_marks() -> void:
	for wp in _path:
		if not (wp is Vector3):
			continue
		var g := Node3D.new()
		g.position = Vector3(wp.x, 0.0, wp.z)
		var pillar := WorldBuilder._cyl(0.16, 0.16, 7.0, 8,
			WorldBuilder._basic(Color(1, 0.85, 0.25, 0.6), true))
		pillar.position.y = 3.5
		g.add_child(pillar)
		var glow := Sprite3D.new()
		glow.texture = TerrainTextures.glow_texture()
		glow.pixel_size = 6.0 / 64.0
		glow.position.y = 4.2
		glow.modulate = Color(1, 0.85, 0.25, 0.9)
		g.add_child(glow)
		var light := OmniLight3D.new()
		light.light_color = Color(1, 0.85, 0.25)
		light.light_energy = 1.6
		light.omni_range = 10.0
		light.position.y = 3.5
		g.add_child(light)
		G.world_root.add_child(g)
		_path_marks.append(g)


## 每帧推进路点:仅当当前目标无坐标(kill)且玩家进入路点 12m 范围;到达的光柱熄灭
func _update_path(_dt: float) -> void:
	if _path.is_empty():
		return
	if not _objective.is_empty() and _objective.get("pos") is Vector3:
		return   # 有坐标目标:指示器直指目标,不消费路点
	if _path_i >= _path.size():
		return
	# 当前路点光柱呼吸脉动(引导感)
	var m = _path_marks[_path_i] if _path_i < _path_marks.size() else null
	if m != null and is_instance_valid(m):
		m.scale = Vector3.ONE * (1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.005))
	if G.player != null and G.player.alive:
		var wp: Vector3 = _path[_path_i]
		if Utils.dist_2d(G.player.pos.x, G.player.pos.z, wp.x, wp.z) <= 12.0:
			_reach_path_point(_path_i)
			_path_i += 1


func _reach_path_point(i: int) -> void:
	if i < _path_marks.size() and is_instance_valid(_path_marks[i]):
		_path_marks[i].visible = false


## ============ 四人小队(战役队友) ============
## 生成 3 名友军 bot:follow=玩家、编队槽位 0/1/2、respawn_t=INF(防 bot_manager 重生)
## 数据取自章节 squad 字段(缺省 _SQUAD_DEFAULTS);出生在玩家编队位,开场过场隐形
func _spawn_squad() -> void:
	_clear_squad()
	var cfg_v: Variant = _data.get("squad", [])
	var cfg: Array = cfg_v if cfg_v is Array and not (cfg_v as Array).is_empty() else _SQUAD_DEFAULTS
	var base: Vector3 = _data.get("start_pos", Vector3(0, 0, -130))
	var byaw: float = float(_data.get("start_yaw", 0.0))
	var ca := cos(byaw)
	var sa := sin(byaw)
	var right := Vector3(ca, 0, -sa)
	var fwd := Vector3(-sa, 0, -ca)
	for i in cfg.size():
		var c: Dictionary = cfg[i]
		var b := Bot.new("us")
		b.apply_loadout(str(c.get("role", "support")), str(c.get("weapon", "mp5")))
		b.bot_name = str(c.get("name", "队员" + str(i + 1)))
		b.name = b.bot_name
		b.skill = clampf(float(c.get("skill", 0.85)), 0.8, 0.95)
		b.respawn_t = INF            # 不自动重生:倒地走救治/撤离流程
		b.follow = G.player
		b.squad_slot = i
		# 出生在玩家附近编队位(起步距离 3-5m)
		var o: Vector2 = b.formation_offset()
		var sp := Vector3(base.x + right.x * o.x * 0.7 + fwd.x * o.y * 0.7,
				base.y, base.z + right.z * o.x * 0.7 + fwd.z * o.y * 0.7)
		if G.ground_h.is_valid():
			sp.y = G.ground_h.call(sp.x, sp.z)
		sp = Utils.move_collide(sp, 0.38, 1.75)
		b.spawn(sp)
		b.mesh.visible = false       # 开场过场隐形,combat 开始显示
		G.bots.append(b)
		G.main.add_child(b)
		_squad.append(b)


## 清理四人小队(换章/abort/重试时调用,幂等):从 G.bots 移除 + queue_free
func _clear_squad() -> void:
	for b in _squad:
		if is_instance_valid(b):
			G.bots.erase(b)
			b.queue_free()
	_squad.clear()
	_squad_gone.clear()
	_revive_bot = null
	_revive_t = 0.0


## 每帧小队逻辑(combat 阶段):倒地 12s 自动复活(自救);玩家 3m 内按住 E 救治(3s 读条,更快)
func _update_squad(dt: float) -> void:
	if _phase != "combat":
		return
	var p = G.player
	# 1) 倒地 12s:自动复活(不再撤离;玩家救治只是更快)
	for b in _squad:
		if b.downed and b.downed_t >= _AUTO_REVIVE_TIME:
			b.revive(b.pos)
			_say(b.bot_name, "缓过来了,别管我,继续打!", 2.5)
	# 2) 救治:队友倒地 + 玩家 3m 内按住 E → 读条 3s 复活
	_revive_bot = null
	if p == null or not p.alive or p.vehicle != null:
		_revive_t = 0.0
		return
	var cand = null
	for b in _squad:
		if b.downed and Vector2(p.pos.x - b.pos.x, p.pos.z - b.pos.z).length() < 3.0:
			cand = b
			break
	if cand == null:
		_revive_t = 0.0
		return
	_revive_bot = cand
	if Input.is_action_pressed("interact"):
		_revive_t += dt
		if _revive_t >= _REVIVE_TIME:
			_revive_t = 0.0
			cand.revive(cand.pos)
			_say(cand.bot_name, "谢了,我还能打。", 2.5)
	else:
		_revive_t = 0.0


## HUD 小队状态栏数据:[{name,hp,max_hp,downed,gone}](按章节 squad 配置顺序)
func get_squad_info() -> Array:
	if _squad.is_empty() and _squad_gone.is_empty():
		return []
	var cfg_v: Variant = _data.get("squad", [])
	var cfg: Array = cfg_v if cfg_v is Array and not (cfg_v as Array).is_empty() else _SQUAD_DEFAULTS
	var out: Array = []
	for c in cfg:
		var nm: String = str(c.get("name", ""))
		var info := { "name": nm, "hp": 0.0, "max_hp": 100.0, "downed": false, "gone": false,
				"self_dur": _AUTO_REVIVE_TIME, "self_left": 0.0 }
		var found := false
		for b in _squad:
			if b.bot_name == nm:
				found = true
				info["hp"] = b.health
				info["downed"] = b.downed
				info["self_left"] = maxf(0.0, _AUTO_REVIVE_TIME - b.downed_t) if b.downed else 0.0
				break
		if not found and nm in _squad_gone:
			info["gone"] = true
		out.append(info)
	return out


## HUD 救治读条数据:{name,t,dur};无救治目标返回空字典
func get_revive_info() -> Dictionary:
	if _revive_bot == null or not is_instance_valid(_revive_bot):
		return {}
	return { "name": _revive_bot.bot_name, "t": _revive_t, "dur": _REVIVE_TIME }


## ============ 内部逻辑 ============
func _say(p_name: String, text: String, dur: float) -> void:
	dialogue_requested.emit(p_name, text, dur)


func _on_objective_active(obj: Dictionary) -> void:
	_say("任务", "新目标:" + str(obj.get("desc", "")), 3.5)
	cutscene_card_requested.emit(_objective_name(objective_index), 2.0)  # 目标点名卡
	_stall_t = 0.0
	_stall_prog = _objective_progress()
	_zone_in = false
	_hold_in = false
	_interact_was_in = false
	# 有坐标的目标:生成金色脉冲信标(区别于路线光柱,指明"要去/要做的地方")
	var bpos: Variant = obj.get("pos")
	if bpos is Vector3:
		_spawn_beacon(bpos)
	if str(obj.get("type", "")) == "destroy":
		var n: int = int(obj.get("count", 1))
		var base: Vector3 = obj.get("pos", Vector3.ZERO)
		var spread: float = float(obj.get("spread", 8.0))
		for i in n:
			var a := TAU * i / float(n) + Utils.rand(-0.35, 0.35)
			var r := spread * Utils.rand(0.6, 1.3)
			_spawn_destructible(Vector3(base.x + cos(a) * r, 0, base.z + sin(a) * r))
	elif str(obj.get("type", "")) == "boss":
		_spawn_boss(obj.get("pos", Vector3(0, 0, 80)))
	elif str(obj.get("type", "")) == "interact":
		_interact_t = 0.0
		_spawn_interact_visual(obj.get("pos", Vector3.ZERO), str(obj.get("kind", "arm")))


## 目标区域进入/离开状态(供 HUD 轻提示轮询):仅 combat + 有坐标目标
func _update_zone_hint() -> void:
	if _phase != "combat" or _objective.is_empty():
		_zone_in = false
		return
	var posv: Variant = _objective.get("pos")
	if not (posv is Vector3):
		_zone_in = false
		return
	var p = G.player
	if p == null or not p.alive:
		return
	var rad: float = float(_objective.get("radius", 16.0))
	_zone_in = Vector2(p.pos.x - posv.x, p.pos.z - posv.z).length() <= rad


## 目标点金色脉冲信标:发光柱 + 旋转光环 + 点光(区别于黄色路线光柱,指明"要去/要做的地方")
func _spawn_beacon(pos: Vector3) -> void:
	_clear_beacon()
	var g := Node3D.new()
	g.position = Vector3(pos.x, G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0, pos.z)
	var gold := Color(1, 0.85, 0.3)
	var pillar := WorldBuilder._cyl(0.2, 0.2, 6.5, 8, WorldBuilder._basic(Color(gold, 0.5), true))
	pillar.position.y = 3.25
	g.add_child(pillar)
	var ring := Node3D.new()
	ring.position.y = 3.6
	for i in 8:
		var a := TAU * i / 8.0
		var blk := WorldBuilder._box(0.16, 0.16, 0.5, WorldBuilder._basic(Color(gold, 0.9), true))
		blk.position = Vector3(cos(a) * 1.1, 0, sin(a) * 1.1)
		ring.add_child(blk)
	g.add_child(ring)
	g.set_meta("beacon_ring", ring)
	var glow := Sprite3D.new()
	glow.texture = TerrainTextures.glow_texture()
	glow.pixel_size = 7.0 / 64.0
	glow.position.y = 4.8
	glow.modulate = Color(gold, 0.9)
	g.add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = gold
	light.light_energy = 1.4
	light.omni_range = 12.0
	light.position.y = 3.4
	g.add_child(light)
	G.world_root.add_child(g)
	_beacon = g


## 移除目标点信标(完成/换章/abort,幂等)
func _clear_beacon() -> void:
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.queue_free()
	_beacon = null


## 信标呼吸脉动 + 光环旋转
func _update_beacon(_dt: float) -> void:
	if _beacon == null or not is_instance_valid(_beacon):
		return
	var t := Time.get_ticks_msec() * 0.001
	_beacon.scale = Vector3.ONE * (1.0 + 0.12 * sin(t * 4.0))
	if _beacon.has_meta("beacon_ring"):
		(_beacon.get_meta("beacon_ring") as Node3D).rotation.y = t * 1.6


## kill 里程碑台词:本章 mid_lines 随机一条(不连播重复)
func _play_mid_line() -> void:
	if _mid_pool.is_empty():
		var arr: Variant = _data.get("mid_lines", [])
		if arr is Array and not arr.is_empty():
			_mid_pool = arr.duplicate()
	if _mid_pool.is_empty():
		return
	var i := Utils.rand_int(0, _mid_pool.size() - 1)
	var l: Dictionary = _mid_pool[i]
	_mid_pool.remove_at(i)
	_say(str(l.get("name", "陈振国上校")), str(l.get("text", "")), float(l.get("dur", 3.0)))


## hold/reach/interact 完成台词:本章 finish_lines 随机一条
func _play_finish_line() -> void:
	var arr: Variant = _data.get("finish_lines", [])
	if not (arr is Array) or arr.is_empty():
		return
	var l: Dictionary = arr[Utils.rand_int(0, arr.size() - 1)]
	_say(str(l.get("name", "曹锐")), str(l.get("text", "")), float(l.get("dur", 3.0)))


## 关键目标完成镜头:0.8s 轻微拉近 + 震动(在玩家相机更新后叠加,不打架)
func _trigger_camera_moment(pos: Vector3) -> void:
	if G.effects != null:
		G.effects.shake(0.15)
	_cam_moment_t = _CAM_MOMENT_DUR
	_cam_moment_pos = pos


func _update_camera_moment(dt: float) -> void:
	if _cam_moment_t <= 0.0:
		return
	_cam_moment_t -= dt
	var cam: Camera3D = G.camera
	if cam == null:
		return
	var k := clampf(1.0 - _cam_moment_t / _CAM_MOMENT_DUR, 0.0, 1.0)
	var amp := sin(k * PI)   # 0 → 1 → 0(推进再收回)
	var to: Vector3 = _cam_moment_pos - cam.global_position
	if to.length() > 0.2:
		cam.global_position += to.normalized() * (_CAM_MOMENT_PUSH * amp)
	cam.fov += _CAM_MOMENT_FOV * amp


func _update_objective(dt: float) -> void:
	var t: String = str(_objective.get("type", ""))
	match t:
		"kill":
			var need: int = int(_objective.get("count", 0))
			# 击杀里程碑:进度 ≥50% 时小队随机无线电台词(每章一次)
			if not _mid_said and need > 0 and _kill_count >= int(ceil(need * 0.5)):
				_mid_said = true
				_play_mid_line()
			if _kill_count >= need:
				_complete_objective()
		"destroy":
			if _destroy_count >= int(_objective.get("count", 0)):
				_complete_objective()
		"hold":
			var in_r := false
			if G.player != null and G.player.alive:
				var pos: Vector3 = _objective.get("pos", Vector3.ZERO)
				in_r = Vector2(G.player.pos.x - pos.x, G.player.pos.z - pos.z).length() < float(_objective.get("radius", 16))
			if in_r:
				if not _hold_in:
					_hold_in = true
					_say("曹锐", "开始坚守,把他们挡在区域外!", 2.5)
				_hold_time += dt
				if _hold_time >= float(_objective.get("time", 0)):
					_complete_objective()
			else:
				_hold_in = false
			# 离开区域:暂停计时(保留进度,不回零)
		"reach":
			if G.player != null and G.player.alive:
				var pos2: Vector3 = _objective.get("pos", Vector3.ZERO)
				if Vector2(G.player.pos.x - pos2.x, G.player.pos.z - pos2.z).length() < float(_objective.get("radius", 14)):
					_say("曹锐", "已抵达" + str(_objective.get("loc", "目标区域")) + "。", 2.5)
					_complete_objective()
		"interact":
			_update_interact(dt)
		"boss":
			# 阵亡即完成(含被爆炸等非玩家手段击杀的重刷兜底);存活且被玩家击杀走 on_player_kill
			if _boss_done or (_boss != null and not _boss.alive):
				_complete_objective()
	_update_stall(dt)


## 当前目标进展归一值(与 _stall_prog 比对判定"有无进展")
func _objective_progress() -> float:
	match str(_objective.get("type", "")):
		"kill":
			return float(_kill_count)
		"destroy":
			return float(_destroy_count)
		"hold":
			return _hold_time
		"boss":
			return _boss.health if (_boss != null and _boss.alive) else 0.0
		"interact":
			return _interact_t
	return 0.0


## 卡死兜底:当前目标 120s 无进展(击杀/破坏/hold 读秒/到达/boss 均无变化)
## → 播提示 + 玩家附近 40-60m 重刷 2-4 敌(boss 目标:阵亡或卡死时玩家附近重刷 BOSS)
## 保证任何数据/逻辑疏漏都不会永久卡住剧情
func _update_stall(dt: float) -> void:
	if _phase != "combat":
		return
	var prog := _objective_progress()
	if not is_equal_approx(prog, _stall_prog):
		_stall_prog = prog
		_stall_t = 0.0
		return
	_stall_t += dt
	if _stall_t < _STALL_TIMEOUT:
		return
	_stall_t = 0.0
	_say("陈振国上校", "目标区域附近有敌军阻碍,清除后推进!", 3.5)
	if str(_objective.get("type", "")) == "boss" and not _boss_done \
			and (_boss == null or not _boss.alive or _boss_blocked()):
		if _boss != null and is_instance_valid(_boss) and _boss.alive:
			# 旧 BOSS 被墙体隔断无法接近:移除防双 BOSS 同场
			G.bots.erase(_boss)
			_boss.queue_free()
		var bp := _pick_rescue_pos(30.0, 46.0, 12.0)
		if bp != Vector3.ZERO:
			_spawn_boss(bp)
		return
	var n := Utils.rand_int(2, 4)
	for i in n:
		var p := _pick_rescue_pos(40.0, 60.0, 15.0)
		if p != Vector3.ZERO:
			_spawn_enemy_at(p)


## boss 是否被墙体/封锁带隔断(无法接近玩家 → 需要重刷)
func _boss_blocked() -> bool:
	if _boss == null or G.player == null:
		return false
	var eye: Vector3 = G.player.pos + Vector3(0, 1.6, 0)
	var dir: Vector3 = _boss.pos - eye
	var d := dir.length()
	if d > 90.0:
		return true
	dir /= d
	var hit = Utils.raycast_world(eye, dir, d - 0.5)
	return hit is Dictionary and hit.get("box") is AABB


func _complete_objective() -> void:
	var ot := str(_objective.get("type", ""))
	var obj := _objective
	_say("任务", "目标完成:" + str(obj.get("desc", "")), 3.0)
	# 关键目标(hold/reach/interact)完成:章节完成台词 + 轻微拉近镜头 + 震动
	if ot == "hold" or ot == "reach" or ot == "interact":
		_play_finish_line()
		var cp: Variant = obj.get("pos")
		_trigger_camera_moment(cp if cp is Vector3 else (G.player.pos if G.player != null else Vector3.ZERO))
	_clear_beacon()      # 目标完成:信标消失
	_zone_in = false
	_hold_in = false
	_clear_interact_visual()   # 交互目标完成:视觉件随完成清理(breach 淡出由 _apply_interact_effect 处理)
	if _objective.get("pos") is Vector3:
		_respawn_pos = _objective["pos"]
	objective_index += 1
	if objective_index >= int(_data["objectives"].size()):
		# 全部目标完成 → 结算过场:环视相机 + outro 台词 + 任务完成卡
		_phase = "outro"
		_outro_i = 0
		_outro_t = 1.2
		_orb_t = 0.0
		_outro_fade = false
		_outro_fade_t = 0.0
		_hide_player_model(true)
		_set_player_invincible(true)
		cutscene_card_requested.emit("任务完成", 3.0)
	else:
		_objective = _data["objectives"][objective_index]
		_on_objective_active(_objective)


## ============ interact 交互目标(按住 E 读条) ============
## 玩家在 pos 半径(默认 4m)内按住 E 持续 time 秒(默认 3s) → 完成并推进下一目标
## 松开 E / 离开半径 / 进入载具 → 进度清零;卡死兜底由 _update_stall 覆盖(进度无变化 120s 触发)
func _update_interact(dt: float) -> void:
	var p = G.player
	var inside := false
	if p != null and p.alive and p.vehicle == null:
		var pos: Vector3 = _objective.get("pos", Vector3.ZERO)
		inside = Vector2(p.pos.x - pos.x, p.pos.z - pos.z).length() \
				< float(_objective.get("radius", _INTERACT_RADIUS))
	if inside and not _interact_was_in:
		_interact_was_in = true
		AudioSys.ui()   # 首次进入交互半径:提示音(与 HUD 交互提示同步)
	elif not inside:
		_interact_was_in = false
	if not inside:
		_interact_t = 0.0
		return
	# 救治与交互互斥:附近有倒地队友需救治时,交互读条暂停(防双读条)
	if _revive_bot != null and _revive_bot.downed:
		_interact_t = 0.0
		return
	if Input.is_action_pressed("interact"):
		_interact_t += dt
		if _interact_t >= float(_objective.get("time", _INTERACT_TIME)):
			_interact_t = 0.0
			_apply_interact_effect(str(_objective.get("kind", "arm")))
			_complete_objective()
	else:
		_interact_t = 0.0


## interact 完成效果(kind 区分):arm=延迟 0.5s 小爆炸;defuse=冒烟+成功音;
## breach=门框视觉件淡出+破门音;radio=台词+刷 2-4 敌;supply=弹药医疗回满;
## revive_survivor=幸存者模型随视觉件清理+台词
func _apply_interact_effect(kind: String) -> void:
	var pos: Vector3 = _objective.get("pos", Vector3.ZERO)
	match kind:
		"arm":
			_interact_apply_kind = "arm"
			_interact_apply_t = 0.5
			_interact_apply_pos = pos
		"defuse":
			_smoke_puff(pos)
			_say("铁柱", "雷管拆除了,可以安全通过。", 2.8)
			AudioSys.capture(true)
		"breach":
			_say("铁柱", "破门,进!", 1.8)
			AudioSys.explosion(pos)
			_smoke_puff(pos)
			var holder = _interact_visual
			if holder != null and is_instance_valid(holder):
				_interact_visual = null   # 交接给淡出 tween,防 _clear_interact_visual 提前释放
				_interact_survivor = null
				var tw: Tween = holder.create_tween()
				tw.tween_property(holder, "scale", Vector3(1.06, 0.02, 1.06), 0.3)
				tw.tween_callback(holder.queue_free)
		"radio":
			_say("苏雅", "指挥部收到。电台已接通,工兵组 2 分钟内到——等等,有脚步声,小心!", 3.6)
			AudioSys.capture(true)
			_spawn_interact_ambush(pos)
		"supply":
			var p = G.player
			if p != null:
				p.heal(100.0)
				p.resupply()
			_say("林雪", "弹药和医疗包都补满了,打回去!", 2.8)
			AudioSys.capture(true)
		"revive_survivor":
			_say("孟海", "……谢谢,兄弟。情报在我身上,带我出去。", 3.2)
			AudioSys.capture(true)
		_:
			pass


## arm 装药完成 0.5s 后:目标点小爆炸 + 烟雾 + 爆炸音(延迟到完成判定后生效)
func _apply_delayed_interact() -> void:
	var kind := _interact_apply_kind
	_interact_apply_kind = ""
	_interact_apply_t = 0.0
	if kind != "arm":
		return
	var pos := _interact_apply_pos
	G.effects.explosion(pos, 3.2)
	_say("任务", "引爆完成!", 2.0)
	_smoke_puff(pos)


## 交互点冒烟(defuse 拆雷成功 / breach 破门尘土 / arm 引爆烟尘)
func _smoke_puff(pos: Vector3) -> void:
	var gy: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	for i in 10:
		G.effects.smoke_spawn(pos.x + Utils.rand(-1.2, 1.2), gy + Utils.rand(0.4, 1.6),
			pos.z + Utils.rand(-1.2, 1.2), Utils.rand(-0.6, 0.6), Utils.rand(0.8, 2.2),
			Utils.rand(-0.6, 0.6), Utils.rand(1.6, 2.6), 0.55, 0.56, 0.5, -0.05, Utils.rand(1.4, 2.4))


## radio 呼叫引来增援:目标点附近 9-18m 刷 2-4 名敌人(盒体视线互通,不刷在墙内)
func _spawn_interact_ambush(center: Vector3) -> void:
	var n := Utils.rand_int(2, 4)
	var spawned_n := 0
	for tries in 12:
		if spawned_n >= n:
			break
		var a := Utils.rand(TAU)
		var r := Utils.rand(9.0, 18.0)
		var px := clampf(center.x + cos(a) * r, -G.bounds + 5, G.bounds - 5)
		var pz := clampf(center.z + sin(a) * r, -G.bounds + 5, G.bounds - 5)
		var pos := Vector3(px, G.ground_h.call(px, pz) if G.ground_h.is_valid() else 0.0, pz)
		pos = Utils.move_collide(pos, 0.38, 1.75)
		if Utils.dist_2d(pos.x, pos.z, center.x, center.z) > 7.0 and _box_los_clear(center, pos):
			_spawn_enemy_at(pos)
			spawned_n += 1


## interact 目标激活时生成视觉件(挂 G.world_root,随完成/abort 清理,仿 _destroy_targets 管理)
## arm/defuse=金属箱+顶红灯;breach=双立柱+横梁门框;radio=长杆+天线;
## supply=军绿箱+发光;revive_survivor=简易人形(躯干/头/双臂/腿)
func _spawn_interact_visual(pos: Vector3, kind: String) -> void:
	_clear_interact_visual()
	var g := Node3D.new()
	g.position = Vector3(pos.x, G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0, pos.z)
	var metal := WorldBuilder._std(Color(0.32, 0.34, 0.36), 0.6)
	var dark := WorldBuilder._std(Color(0.2, 0.21, 0.23), 0.8)
	var olive := WorldBuilder._std(Color(0.32, 0.38, 0.2), 0.9)
	match kind:
		"arm", "defuse":
			var box := WorldBuilder._box(1.1, 0.7, 1.1, metal)
			box.position.y = 0.35
			box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			g.add_child(box)
			var lamp := WorldBuilder._box(0.22, 0.18, 0.22, WorldBuilder._std(Color(1, 0.12, 0.06), 0.5))
			lamp.position.y = 0.78
			g.add_child(lamp)
		"breach":
			var pillar_mat := WorldBuilder._std_tex(Color(0.6, 0.58, 0.52), 0.95, "rough_concrete")
			for side in [-1.0, 1.0]:
				var pillar := WorldBuilder._box(0.5, 2.6, 0.5, pillar_mat)
				pillar.position = Vector3(0.9 * side, 1.3, 0)
				pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				g.add_child(pillar)
			var lintel := WorldBuilder._box(2.6, 0.4, 0.6, pillar_mat)
			lintel.position = Vector3(0, 2.7, 0)
			lintel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			g.add_child(lintel)
		"radio":
			var pole := WorldBuilder._cyl(0.09, 0.09, 3.4, 8, dark)
			pole.position.y = 1.7
			g.add_child(pole)
			var antenna := WorldBuilder._cyl(0.05, 0.05, 1.6, 6, dark)
			antenna.position.y = 4.3
			g.add_child(antenna)
			var head := WorldBuilder._box(0.16, 0.14, 0.14, WorldBuilder._std(Color(0.5, 0.85, 1), 0.4))
			head.position.y = 5.1
			g.add_child(head)
		"supply":
			var crate := WorldBuilder._box(1.3, 0.8, 1.3, olive)
			crate.position.y = 0.4
			crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			g.add_child(crate)
			var glow := Sprite3D.new()
			glow.texture = TerrainTextures.glow_texture()
			glow.pixel_size = 5.0 / 64.0
			glow.position.y = 1.1
			glow.modulate = Color(0.55, 1, 0.5, 0.85)
			g.add_child(glow)
		"revive_survivor":
			_interact_survivor = g
			var cloth := WorldBuilder._std(Color(0.5, 0.53, 0.45), 0.95)
			var skin := WorldBuilder._std(Color(0.85, 0.7, 0.6), 0.9)
			var torso := WorldBuilder._box(0.5, 0.7, 0.3, cloth)
			torso.position.y = 1.15
			torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			g.add_child(torso)
			var head := WorldBuilder._box(0.3, 0.3, 0.3, skin)
			head.position.y = 1.7
			g.add_child(head)
			for side in [-1.0, 1.0]:
				var arm := WorldBuilder._box(0.12, 0.7, 0.12, cloth)
				arm.position = Vector3(0.34 * side, 1.15, 0)
				g.add_child(arm)
			var legs := WorldBuilder._box(0.44, 0.7, 0.26, dark)
			legs.position.y = 0.35
			g.add_child(legs)
		_:
			var box2 := WorldBuilder._box(1.1, 0.7, 1.1, metal)
			box2.position.y = 0.35
			g.add_child(box2)
	G.world_root.add_child(g)
	_interact_visual = g


## 清理交互点视觉件(完成/abort/换章时调用,幂等;breach 淡出 tween 已接管的不重复释放)
func _clear_interact_visual() -> void:
	if _interact_visual != null and is_instance_valid(_interact_visual):
		_interact_visual.queue_free()
	_interact_visual = null
	_interact_survivor = null


## HUD 交互读条数据:{label,t,dur};玩家不在半径内或非 interact 目标返回空字典(提示隐藏)
func get_interact_info() -> Dictionary:
	if _phase != "combat" or _objective.is_empty() or str(_objective.get("type", "")) != "interact":
		return {}
	var p = G.player
	if p == null or not p.alive or p.vehicle != null:
		return {}
	var pos: Vector3 = _objective.get("pos", Vector3.ZERO)
	if Vector2(p.pos.x - pos.x, p.pos.z - pos.z).length() \
			>= float(_objective.get("radius", _INTERACT_RADIUS)):
		return {}
	return {
		"label": str(_objective.get("label", "交互")),
		"t": _interact_t,
		"dur": float(_objective.get("time", _INTERACT_TIME)),
	}


## 波次刷兵:存活数 < 上限时每 6-9s 补兵,直到 enemy_total 耗尽
func _update_waves(dt: float) -> void:
	var cap: int = int(_data.get("enemy_cap", 10))
	var total: int = int(_data.get("enemy_total", 30))
	if _spawned >= total:
		return
	var alive := 0
	for b in G.bots:
		if b.team == "ru" and b.alive:
			alive += 1
	_wave_t -= dt
	if alive < cap and _wave_t <= 0:
		var wr := _wave_interval()
		_wave_t = Utils.rand(wr.x, wr.y)
		var n := 2 if alive < int(cap * 0.5) else 1
		for i in n:
			if _spawned >= total:
				break
			_spawn_enemy()


func _spawn_enemy() -> void:
	_spawn_enemy_at(_pick_spawn_pos())


func _spawn_enemy_at(pos: Vector3) -> void:
	var b := Bot.new("ru")
	var cid: String = Utils.choice(BotManager.CLASS_POOL)
	b.apply_loadout(cid, Utils.choice(BotManager.WEAPONS[cid]["ru"]))
	var sr := _enemy_skill_range()
	b.skill = Utils.rand(sr.x, sr.y)   # 敌兵 skill 按章节梯度(c1-c2 上限 0.7 减负)
	b.respawn_t = INF  # 战役敌人不自动重生(总量有限),由战役控制器补兵
	G.bots.append(b)
	G.main.add_child(b)
	b.spawn(pos)
	_spawned += 1


## 玩家 45-90m 外随机安全位(越界夹取,碰撞推挤防穿墙)
## 关键:候选点必须与玩家"盒体视线互通"(不被封锁带/建筑墙隔断)——
## 封锁带后的大片封闭区不会刷兵,杜绝"敌人生成在墙内出不来 → 杀不够"卡死
func _pick_spawn_pos() -> Vector3:
	var base: Vector3 = _respawn_pos
	if G.player != null and G.player.alive:
		base = G.player.pos
	for tries in 16:
		var a := Utils.rand(TAU)
		var r := Utils.rand(45.0, 90.0)
		var px := clampf(base.x + cos(a) * r, -G.bounds + 5, G.bounds - 5)
		var pz := clampf(base.z + sin(a) * r, -G.bounds + 5, G.bounds - 5)
		if Utils.dist_2d(px, pz, base.x, base.z) < 32.0:
			continue
		var pos := Vector3(px, G.ground_h.call(px, pz) if G.ground_h.is_valid() else 0.0, pz)
		pos = Utils.move_collide(pos, 0.38, 1.75)
		if Utils.dist_2d(pos.x, pos.z, base.x, base.z) > 34.0 and _box_los_clear(base, pos):
			return pos
	# 定向兜底:朝目标/路点方向 45-60m 内找盒体视线互通的点位(线性走廊内必能命中)
	var aim := Vector3.ZERO
	if _objective.get("pos") is Vector3:
		aim = _objective["pos"]
	elif _path_i < _path.size():
		aim = _path[_path_i]
	elif G.player != null:
		aim = G.player.pos + Vector3(0, 0, -60)
	var to_aim := Vector2(aim.x - base.x, aim.z - base.z)
	if to_aim.length() < 1.0:
		to_aim = Vector2(0, -1)
	to_aim = to_aim.normalized()
	for tries in 8:
		var r2 := Utils.rand(45.0, 60.0)
		var ang := atan2(to_aim.y, to_aim.x) + Utils.rand(-0.9, 0.9)
		var px2 := clampf(base.x + cos(ang) * r2, -G.bounds + 5, G.bounds - 5)
		var pz2 := clampf(base.z + sin(ang) * r2, -G.bounds + 5, G.bounds - 5)
		var pos2 := Vector3(px2, G.ground_h.call(px2, pz2) if G.ground_h.is_valid() else 0.0, pz2)
		pos2 = Utils.move_collide(pos2, 0.38, 1.75)
		if Utils.dist_2d(pos2.x, pos2.z, base.x, base.z) > 34.0 and _box_los_clear(base, pos2):
			return pos2
	# 最终兜底:朝基地方向偏移 50m,采地面高并按边界夹取(防悬空/越界;仍有兵可刷)
	var fx: float = clampf(base.x + 50.0, -G.bounds + 5, G.bounds - 5)
	var fz: float = clampf(base.z, -G.bounds + 5, G.bounds - 5)
	return Vector3(fx, G.ground_h.call(fx, fz) if G.ground_h.is_valid() else 0.0, fz)


## 超时兜底刷兵位:玩家附近 min_d-max_d 环形、盒体视线互通、不压目标点半径(留 obj_clear 余量)
## 失败返回 Vector3.ZERO(调用方跳过该次刷兵)
func _pick_rescue_pos(min_d: float, max_d: float, obj_clear: float) -> Vector3:
	var base: Vector3 = G.player.pos if (G.player != null and G.player.alive) else _respawn_pos
	var op: Vector3 = _objective.get("pos") if _objective.get("pos") is Vector3 else Vector3.ZERO
	var orad: float = float(_objective.get("radius", 0.0))
	for tries in 14:
		var a := Utils.rand(TAU)
		var r := Utils.rand(min_d, max_d)
		var px := clampf(base.x + cos(a) * r, -G.bounds + 5, G.bounds - 5)
		var pz := clampf(base.z + sin(a) * r, -G.bounds + 5, G.bounds - 5)
		var pos := Vector3(px, G.ground_h.call(px, pz) if G.ground_h.is_valid() else 0.0, pz)
		pos = Utils.move_collide(pos, 0.38, 1.75)
		if Utils.dist_2d(pos.x, pos.z, base.x, base.z) < min_d * 0.7:
			continue
		if op != Vector3.ZERO and Utils.dist_2d(pos.x, pos.z, op.x, op.z) < orad + obj_clear:
			continue
		if _box_los_clear(base, pos):
			return pos
	return Vector3.ZERO


## 盒体视线互通判定:玩家→候选点 射线只允许被地形阻挡,被碰撞盒(AABB)阻挡视为隔断
## (封锁带/建筑墙后 = 敌军到不了玩家,拒绝;山丘地形不拒绝,避免过度拦截刷兵)
func _box_los_clear(a: Vector3, b: Vector3) -> bool:
	var eye: Vector3 = a + Vector3(0, 1.4, 0)
	var dir: Vector3 = b + Vector3(0, 0.8, 0) - eye
	var d := dir.length()
	if d < 1.0:
		return false
	dir /= d
	var hit = Utils.raycast_world(eye, dir, d + 0.4)
	return not (hit is Dictionary and hit.get("box") is AABB)


## 爆破目标:程序化红色发光木箱破坏物(物理可打爆,与地图破坏物同体系)
func _spawn_destructible(pos: Vector3) -> void:
	var ds := WorldBuilder.Destructible.new()
	ds.kind = "crate"
	var g := Node3D.new()
	var mat := WorldBuilder._std_tex(Color.WHITE, 0.85, "plywood")
	mat.albedo_color = Color(1, 0.72, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.2, 0.08)
	mat.emission_energy_multiplier = 0.9
	var box := WorldBuilder._box(1.5, 1.5, 1.5, mat)
	box.position.y = 0.75
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(box)
	g.position = Vector3(pos.x, G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0, pos.z)
	var coll := AABB(Vector3(pos.x - 0.75, 0, pos.z - 0.75), Vector3(1.5, 1.5, 1.5))
	G.colliders.append(coll)
	G.world_root.add_child(g)
	ds.group = g
	ds.collider = coll
	ds.pos = Vector3(pos.x, 0.75, pos.z)
	ds.hp = 160.0
	ds.radius = 1.2
	ds.set_meta("campaign_obj", objective_index)
	ds.set_meta("campaign_counted", false)
	G.destructibles.append(ds)
	_destroy_targets.append(ds)


## 最终章 BOSS:高血量精英(800 HP),玩家击杀即完成任务
func _spawn_boss(pos: Vector3) -> void:
	var b := Bot.new("ru")
	b.apply_loadout("assault", "ak")
	b.bot_name = "白狼"
	b.skill = 1.05
	b.respawn_t = INF
	_boss = b
	G.bots.append(b)
	G.main.add_child(b)
	b.spawn(pos)
	b.health = 800.0
	b.update_health_bar()
	_say("陈振国上校", "目标确认——佣兵团首领「白狼」现身!击毙他,战争就结束了!", 4.5)
