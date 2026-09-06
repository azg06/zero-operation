class_name WeaponReloadController extends RefCounted
## 模块化武器换弹控制器
##
## 状态机:
##   Reload Start     → 准备阶段(枪械下沉/内倾,非持枪手接近弹匣/弹鼓/供弹盖)
##   Magazine Remove  → 释放/拔出弹匣,弹匣带惯性离开,随后世界掉落
##   Magazine Insert  → 非持枪手从屏外取新弹匣,连续路径返回并推入
##   Drum Reload      → 解锁 → 摘下旧弹鼓 → 取新鼓 → 对位插入 → 固定/锁定
##   Belt Reload      → 开供弹盖 → 抽旧链/旧箱 → 取新箱 → 弹链入槽 → 关盖闭锁
##   Chamber Action   → 按枪械结构执行拉机柄/空挂释放/套筒/泵动/枪栓循环
##   Reload Finish    → 惯性恢复持枪姿态
##   Reload Cancel    → 任何原因中止:按当前进度自然 Blend,绝不瞬移
##   Reload Interrupt → 开火/ADS/冲刺/切枪等外部状态按阶段决策
##
## 控制器只读写 Gun 暴露的动画件引用与 pose 输出,所有动作参数来自 ReloadProfiles。

enum State { IDLE, ACTIVE, CANCEL, FINISH }
enum Stage { PREPARE, REMOVE, FETCH, INSERT, CHAMBER, RECOVER }
enum TubeStage { REACH, PUSH, RETURN }

const GRIP_DOWN := Vector3(0.0, -0.035, 0.012)
const GRIP_SIDE := Vector3(0.0, -0.04, 0.02)
const GRIP_DRUM := Vector3(-0.02, -0.03, 0.02)
const GRIP_BELT := Vector3(-0.01, -0.035, 0.018)
const GRIP_TOP := Vector3(0.0, -0.055, 0.015)
const GRIP_PISTOL := Vector3(0.0, -0.045, 0.015)

const HAND_GRIP_ROT := Vector3(-0.7, 0.25, PI - 0.38)
const HAND_REST_ROT := Vector3(0.1, 0.0, PI - 0.15)
const HAND_REVOLVER_GRIP_ROT := Vector3(-0.34, 0.16, PI - 0.3)


var _gun_ref: WeakRef = null
var player = null
var group: Node3D = null
var cfg: Dictionary = {}

var state := State.IDLE
var stage: int = Stage.PREPARE
var tube_stage := TubeStage.REACH
var phase_names: Array = []
var phase_durs: Array = []
var active := false
var committed := false
var ammo_committed := false
var insert_swapped := false
var _stage_event_done := false
var started_empty := false
var old_mag_dropped := false
var old_mag_stowed := false
var chamber_started := false

var time := 0.0
var total := 1.0
var stage_time := 0.0
var stage_dur := 0.2
var stage_p := 0.0
var cancel_t := 0.0
var finish_t := 0.0
var finish_dur := 0.22

# 霰弹枪逐发装填
var shells_needed := 0
var shells_loaded := 0
var _pump_wait := 0.0
var _bolt_wait := 0.0
var tube_first_chambered := false

# [9/10] 左轮装填
var revolver_mode := "single"          # single / quick
var revolver_quick := false
var revolver_eject_done := false
var revolver_loader_done := false
var revolver_load_count := 0
var revolver_open := 0.0               # 当前弹巢开合量 0~1(平滑)
var revolver_spin_wait := 0.0
var revolver_target_shell := -1
var revolver_cycle_idx := 0

# 当前阶段动态记录的抓握点
var hand_after_remove := Vector3.ZERO
var insert_start := Vector3.ZERO
var insert_start_rot := Vector3.ZERO
var _insert_slap_t := -1.0
var _chamber_hand_start := Vector3.ZERO

# 平滑姿态输出(Gun 每帧叠加到基础持枪姿态上)
var pose_pos := Vector3.ZERO
var pose_rot := Vector3.ZERO
var impulse_pos := Vector3.ZERO
var impulse_rot := Vector3.ZERO

# 动画件引用
var mag: Node3D = null
var bolt: Node3D = null
var slide: MeshInstance3D = null
var pump: Node3D = null
var rocket: Node3D = null
var breech: Node3D = null       # 中折式榴弹发射器可下折膛体(仅 GL 提供)
var left_hand: Node3D = null
var right_hand: Node3D = null
# 弹链机枪专用动画件
var cover: Node3D = null
var cover_latch: Node3D = null
var belt: Node3D = null
var new_belt: Node3D = null
var feed_port: Node3D = null

# 基准变换
var mag_base := Vector3.ZERO
var mag_base_rot := Vector3.ZERO
var hand_rest := Vector3.ZERO
var hand_rest_rot := Vector3.ZERO
var hand_pocket := Vector3.ZERO
var hand_grip_anchor := Vector3.ZERO
var right_base := Vector3.ZERO
var right_rot_base := Vector3.ZERO
var bolt_base := Vector3.ZERO
var slide_base := Vector3.ZERO
var slide_base_z := 0.0
var pump_base := Vector3.ZERO
var rocket_base := Vector3.ZERO
var breech_base_rot := Vector3.ZERO   # 膛体闭锁基准角
var breech_open := 0.0                # 当前开膛量 0~1(平滑)
var _breech_snd_open := false
var _breech_snd_close := false
var cover_base := Vector3.ZERO
var belt_base := Vector3.ZERO
var belt_base_rot := Vector3.ZERO
# [9/10] 左轮动画件
var revolver_crane: Node3D = null
var revolver_cylinder: Node3D = null
var revolver_hammer: Node3D = null
var revolver_shells: Array = []
var revolver_crane_base := Vector3.ZERO
var revolver_cyl_base := Vector3.ZERO
var revolver_cyl_pos_base := Vector3.ZERO

# 霰弹枪可见弹壳(逐发装填视觉)
var shell_mesh: MeshInstance3D = null
# 左轮快速装弹器(独立视觉,装填完成后隐藏)
var speedloader_mesh: Node3D = null
# 战术换弹用“新弹匣/新弹鼓/新弹链箱”独立视觉:旧供弹具还在枪上时,新供弹具已在手上
var new_mag: Node3D = null
# 火箭筒装填用“新导弹筒”独立视觉
var new_rocket: Node3D = null


func _init(g: Gun) -> void:
	# 控制器只弱引用 Gun:Gun 强持有控制器,避免 RefCounted 循环引用导致切枪/拾枪内存泄漏
	_gun_ref = weakref(g)
	player = g.player
	group = g.group
	cfg = ReloadProfiles.profile_for(g.id, g.def)
	_capture_rig()
	_build_shell()
	_build_new_mag()
	_build_speedloader()


## 解析弱引用;Gun 存活期间调用,方法执行过程中不会被释放
func _g() -> Gun:
	return _gun_ref.get_ref() as Gun


func _capture_rig() -> void:
	mag = _g()._mag
	bolt = _g()._bolt
	slide = _g()._slide
	pump = _g()._pump
	rocket = _g()._rocket
	left_hand = _g()._left_hand
	right_hand = _g()._right_hand
	if group != null:
		if group.has_meta("cover"):
			cover = group.get_meta("cover")
		if group.has_meta("cover_latch"):
			cover_latch = group.get_meta("cover_latch")
		if group.has_meta("feed_port"):
			feed_port = group.get_meta("feed_port")
		if group.has_meta("breech"):
			breech = group.get_meta("breech")
			breech_base_rot = breech.rotation
	if mag != null:
		mag_base = mag.position
		mag_base_rot = mag.rotation
		belt = mag.get_node_or_null("BeltTail")
	if belt == null and group != null and group.has_meta("belt"):
		belt = group.get_meta("belt")
	if bolt != null:
		bolt_base = bolt.position
	if slide != null:
		slide_base = slide.position
		slide_base_z = slide.position.z
	if pump != null:
		pump_base = pump.position
	if group != null and group.has_meta("crane"):
		revolver_crane = group.get_meta("crane")
		revolver_crane_base = revolver_crane.rotation
	if group != null and group.has_meta("cylinder"):
		revolver_cylinder = group.get_meta("cylinder")
		revolver_cyl_base = revolver_cylinder.rotation
		revolver_cyl_pos_base = revolver_cylinder.position
	if group != null and group.has_meta("hammer"):
		revolver_hammer = group.get_meta("hammer")
	if group != null and group.has_meta("chamber_shells"):
		revolver_shells = group.get_meta("chamber_shells")
	if rocket != null:
		rocket_base = rocket.position
	if cover != null:
		cover_base = cover.rotation
	if belt != null:
		belt_base = belt.position
		belt_base_rot = belt.rotation
	if left_hand != null:
		hand_rest = left_hand.position
		hand_rest_rot = left_hand.rotation
	if right_hand != null:
		right_base = right_hand.position
		right_rot_base = right_hand.rotation
	hand_pocket = _g().hand_l2
	hand_grip_anchor = _mag_grip_pos(mag_base)
	# 插入路径起点必须在首次换弹前就绪:FETCH 阶段会先读取 insert_start,
	# 若等 INSERT 阶段才赋值,首轮换弹会从原点附近瞬移到弹匣井下方(弹匣/手抽搐)。
	var ins := _mag_insert_start()
	insert_start = ins.get("pos", mag_base)
	insert_start_rot = ins.get("rot", Vector3.ZERO)


func _build_shell() -> void:
	if shell_mesh != null or group == null:
		return
	var is_revolver: bool = _g().def.get("revolver") == true
	if _g().def.pellets <= 1 and not is_revolver:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	if is_revolver:
		cm.top_radius = 0.005
		cm.bottom_radius = 0.005
		cm.height = 0.032
		cm.radial_segments = 10
	else:
		cm.top_radius = 0.011
		cm.bottom_radius = 0.011
		cm.height = 0.055
		cm.radial_segments = 10
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.62, 0.22) if is_revolver else Color(0.75, 0.18, 0.15)
	mat.metallic = 0.75
	mat.roughness = 0.3
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	if is_revolver:
		mi.rotation.x = PI / 2.0
	group.add_child(mi)
	shell_mesh = mi


## 左轮快速装弹器:圆形弹托 + 与弹巢容量一致的弹头簇,握在手中随装填路径运动。
func _build_speedloader() -> void:
	if speedloader_mesh != null or group == null:
		return
	if not _g().def.get("revolver") == true:
		return
	var root := Node3D.new()
	root.name = "RevolverSpeedloader"
	var cap: int = maxi(5, _g().mag_cap)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.3, 0.34)
	mat.metallic = 0.45
	mat.roughness = 0.55
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.014
	hm.bottom_radius = 0.014
	hm.height = 0.02
	hm.radial_segments = 14
	hub.mesh = hm
	hub.material_override = mat
	hub.rotation.x = PI / 2.0
	root.add_child(hub)
	for i in cap:
		var rd := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.0045
		rm.bottom_radius = 0.0045
		rm.height = 0.03
		rm.radial_segments = 8
		rd.mesh = rm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.78, 0.6, 0.2)
		bmat.metallic = 0.8
		bmat.roughness = 0.28
		rd.material_override = bmat
		rd.rotation.x = PI / 2.0
		var ang := float(i) * TAU / float(cap)
		rd.position = Vector3(sin(ang) * 0.0135, cos(ang) * 0.0135, -0.012)
		root.add_child(rd)
	root.visible = false
	WeaponModels.set_shadow_recursive(root, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	group.add_child(root)
	speedloader_mesh = root


func _build_new_mag() -> void:
	if _g().def.pellets > 1:
		return
	if new_mag == null and mag != null:
		# mag 可能是 GLB 场景实例节点(且被 hoist 动过子树),直接 duplicate 会
		# 打穿实例缓存 —— 统一走 pack→instantiate 的安全复制
		var dup := WeaponModels.safe_duplicate(mag) as Node3D
		if dup != null:
			dup.name = "NewMagReload"
			dup.visible = false
			group.add_child(dup)
			WeaponModels.set_shadow_recursive(dup, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			new_mag = dup
			new_belt = dup.get_node_or_null("BeltTail")
	if new_rocket == null and rocket != null:
		var rdup := WeaponModels.safe_duplicate(rocket) as Node3D
		if rdup != null:
			rdup.name = "NewRocketReload"
			rdup.visible = false
			# 与原弹药件同父:火箭筒挂 group,榴弹挂可下折膛体
			# (否则装填动画会在错误的坐标系里飞)
			var rhost := rocket.get_parent() as Node3D
			(rhost if rhost != null else group).add_child(rdup)
			WeaponModels.set_shadow_recursive(rdup, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			new_rocket = rdup


# ============================================================
# 对外接口(Gun 调用)
# ============================================================

func start() -> bool:
	if state == State.ACTIVE:
		return false
	if _g().ammo >= _g().mag_cap or _g().reserve <= 0:
		return false
	reset_motion(false)
	if _g().def.get("revolver") == true:
		_start_revolver()
	elif _g().def.pellets > 1:
		_start_tube()
	else:
		_start_mag()
	state = State.ACTIVE
	active = true
	committed = false
	started_empty = _g().ammo == 0
	old_mag_dropped = false
	old_mag_stowed = false
	chamber_started = false
	time = 0.0
	_g().reloading = true
	_g().reload_t = 0.0
	return true


func update(dt: float) -> void:
	if group == null or not is_instance_valid(group):
		return
	match state:
		State.ACTIVE:
			_update_active(dt)
		State.CANCEL:
			_update_cancel(dt)
		State.FINISH:
			_update_finish(dt)
		State.IDLE:
			_update_idle(dt)
	_follow_auxiliary_hands(dt)
	_update_mag_slap(dt)
	_update_breech_hinge(dt)


## 插匣拍实动画。
## 曾经绑在 INSERT 阶段的生命周期里:当弹匣轨迹拖到 p>=0.88 才提交时,
## slap 刚起手阶段就切走了,抬起的弹匣(CHAMBER/RECOVER 没人管)永远停在
## +slap 的残差上。现在作为独立动画挂在主 update —— 无论阶段怎么切都
## 完整播完并保证归位,这是"拍匣"这种瞬时动作的正确挂法。
func _update_mag_slap(dt: float) -> void:
	if _insert_slap_t < 0.0 or mag == null or not is_instance_valid(mag):
		return
	_insert_slap_t += dt
	var dur := 0.09
	if _insert_slap_t >= dur:
		# 播完强制归位:消掉浮点残差,也兜底任何中途切阶段的场景
		mag.position = mag_base
		mag.rotation = mag_base_rot
		_insert_slap_t = -1.0
		return
	var s := sin(clampf(_insert_slap_t / dur, 0.0, 1.0) * PI)
	var slap: float = float(cfg.get("slap", 0.018))
	match String(cfg.get("mag", "down")):
		"side":
			mag.position.x += s * slap * 0.4
		"top":
			mag.position.y -= s * slap * 0.8
		"p90":
			# P90 压尾入扣:最后一下把弹匣后部向下拍实
			mag.position.y -= s * slap
			mag.rotation.x = maxf(0.0, mag.rotation.x - s * slap * 0.4)
		_:
			mag.position.y += s * slap
	if left_hand != null and state == State.ACTIVE \
			and stage < phase_names.size() and String(phase_names[stage]) == "insert":
		# 手跟随只属于 INSERT 阶段;其他阶段的手由各自的阶段逻辑接管
		left_hand.position = mag.position + _grip_offset()


## QA 诊断:当前换弹阶段名("" = 空闲)
func phase_name() -> String:
	if state != State.ACTIVE or stage >= phase_names.size():
		return ""
	return String(phase_names[stage])


## 中折式榴弹发射器:膛体绕铰链下折(开膛 → 装填 → 合膛闭锁)。
## 只对提供 breech 元数据的武器生效(M320),其它武器完全不进入这段逻辑。
## 开膛量由换弹阶段驱动:prepare 打开 → remove/fetch 保持全开 → insert 后半段闭锁。
func _update_breech_hinge(dt: float) -> void:
	if breech == null or not is_instance_valid(breech):
		return
	var want := 0.0
	if state == State.ACTIVE and stage < phase_names.size():
		match String(phase_names[stage]):
			"prepare":
				want = _ez(stage_p)
			"remove", "fetch":
				want = 1.0
			"insert":
				want = 1.0 - _ez(clampf((stage_p - 0.55) / 0.45, 0.0, 1.0))
			_:
				want = 0.0
	breech_open = Utils.damp(breech_open, want, 15.0, dt)
	# 负角 = 枪管向下折开(绕 X 正角会把枪口抬起,中折式必须朝下)
	breech.rotation = breech_base_rot + Vector3(-breech_open * float(cfg.get("breech_hinge", 0.62)), 0.0, 0.0)
	# 开膛/闭锁机械音:各自只触发一次,一个换弹循环结束后复位
	if breech_open > 0.3 and not _breech_snd_open:
		_breech_snd_open = true
		AudioSys.reload_action("cover_open", 1.08)
	if _breech_snd_open and not _breech_snd_close and want <= 0.01 and breech_open < 0.12:
		_breech_snd_close = true
		AudioSys.reload_action("cover_close", 1.12)
		_impulse(0.010, 0.7)
		_camera_kick(0.6, 0.4)
	if state != State.ACTIVE and breech_open < 0.02:
		_breech_snd_open = false
		_breech_snd_close = false


func cancel(reason := "fire") -> void:
	if state == State.IDLE:
		_g().reloading = false
		return
	# 枪机/泵动循环动画不能因取消瞬移,由 Gun 的 bolt_t/pump_t 自然收尾
	if shell_mesh != null:
		shell_mesh.visible = false
	if speedloader_mesh != null:
		speedloader_mesh.visible = false
	if new_mag != null:
		new_mag.visible = false
	if new_rocket != null:
		new_rocket.visible = false
	if state == State.CANCEL:
		return
	if reason == "fire":
		# 只有弹匣仍在(早期取消)或新弹匣已推入(committed)才会被 try_fire 允许
		_restore_mag_if_valid()
	active = false
	_g().reloading = false
	_g().reload_t = time
	state = State.CANCEL
	cancel_t = 0.0
	stage = Stage.RECOVER


func is_busy_cycle() -> bool:
	if _g().pump_t > 0.0 or _g().semi_t > 0.0 or _g().bolt_t > 0.0 or _g().cylinder_t > 0.0:
		return true
	return _pump_wait > 0.0 or _bolt_wait > 0.0 or revolver_spin_wait > 0.0


## 是否还在播放换弹/取消/收尾动画:用于 ADS 状态下禁止换弹未播完就开火。
func is_animating() -> bool:
	return state == State.ACTIVE or state == State.CANCEL or state == State.FINISH


func can_fire_interrupt() -> bool:
	if not active:
		return true
	# 泵动/拉栓循环尚未收尾:枪械不在可击发状态
	if is_busy_cycle():
		return false
	# 换弹期间按住右键(ADS):不允许提前开火打断,必须等换弹动画完整播完。
	# 腰射状态仍保留 COD 式“早期/入匣后”可打断逻辑。
	if _g().ads_held or _g().ads_amount > 0.35:
		return false
	# 左轮弹巢未关闭时物理上无法击发;闭锁末段/恢复阶段允许开火打断并保留已装弹
	if _g().def.get("revolver") == true:
		return _g().ammo > 0 and revolver_open < 0.22
	if _g().def.pellets > 1:
		return _g().ammo > 0
	if committed:
		return true
	# 空仓换弹且新供弹具未闭锁:没有可发射的弹药,不允许打断
	if _g().ammo <= 0:
		return false
	# 战术换弹的早期阶段:旧供弹具仍在枪上,允许打断并立即开火
	var early: float = float(cfg.get("cancel_time", 0.45))
	if stage < phase_names.size():
		var nm := String(phase_names[stage])
		if nm == "prepare":
			return true
		if nm in ["unlock", "cover_open"]:
			return true
		if nm in ["remove", "belt_out"] and stage_p < early and not old_mag_dropped:
			return true
	else:
		return true
	return false


func can_ads_interrupt() -> bool:
	return true


func reset_motion(snap := true) -> void:
	active = false
	state = State.IDLE
	stage = Stage.PREPARE
	tube_stage = TubeStage.REACH
	committed = false
	ammo_committed = false
	insert_swapped = false
	_stage_event_done = false
	old_mag_dropped = false
	old_mag_stowed = false
	chamber_started = false
	tube_first_chambered = false
	time = 0.0
	stage_time = 0.0
	cancel_t = 0.0
	finish_t = 0.0
	_pump_wait = 0.0
	_bolt_wait = 0.0
	revolver_spin_wait = 0.0
	revolver_eject_done = false
	revolver_loader_done = false
	revolver_load_count = 0
	revolver_target_shell = -1
	_insert_slap_t = -1.0
	_chamber_hand_start = hand_grip_anchor
	if snap:
		pose_pos = Vector3.ZERO
		pose_rot = Vector3.ZERO
		impulse_pos = Vector3.ZERO
		impulse_rot = Vector3.ZERO
	if shell_mesh != null:
		shell_mesh.visible = false
	if speedloader_mesh != null:
		speedloader_mesh.visible = false
	if new_mag != null:
		new_mag.visible = false
	if new_rocket != null:
		new_rocket.visible = false
	_g().grip_amt = 0.0
	if snap:
		_g().reloading = false
		_snap_rig_to_base()


func reset() -> void:
	reset_motion(true)


func on_holster() -> void:
	if active or state == State.ACTIVE or state == State.FINISH:
		cancel("holster")
	# 不 snap:holster Tween 从当前姿态开始;只确保收起途中供弹具可见,reset 交给下次 equip()
	if mag != null:
		mag.visible = true
	if belt != null:
		belt.visible = true
	if new_mag != null:
		new_mag.visible = false
	if new_belt != null:
		new_belt.visible = false
	if new_rocket != null:
		new_rocket.visible = false
	if speedloader_mesh != null:
		speedloader_mesh.visible = false
	if cover != null:
		cover.visible = true
	if rocket != null:
		rocket.visible = true


# ============================================================
# 启动逻辑
# ============================================================

func _start_mag() -> void:
	var tac: bool = _g().ammo > 0
	var base_time: float = float(cfg.get("tac_time", 0.0)) if tac else float(cfg.get("empty_time", 0.0))
	if base_time <= 0.0:
		base_time = _g().def.reload_time * (0.78 if tac else 1.0)
	base_time = maxf(0.2, base_time * _g()._reload_mult / maxf(0.1, float(cfg.get("anim_speed", 1.0))))
	total = base_time
	var flow := _flow()
	var names: Array
	var weights: Array
	match flow:
		"drum":
			if tac:
				# 战术换弹:旧弹鼓收入携行具,换上新鼓,旧鼓不丢
				names = ["unlock", "remove", "stow", "fetch", "insert", "lock", "recover"]
				weights = [0.11, 0.14, 0.12, 0.19, 0.17, 0.11, 0.16]
			else:
				# 弹鼓:解锁 → 抓取摘下 → 取新鼓 → 对位插入 → 固定/锁定 → 恢复
				names = ["unlock", "remove", "fetch", "insert", "lock", "recover"]
				weights = (cfg.get("drum_weights", [0.13, 0.18, 0.25, 0.18, 0.12, 0.14]) as Array).duplicate()
		"belt":
			if tac:
				# 战术换弹:开盖后把旧弹链箱收入携行具,换新箱,旧箱保留
				names = ["cover_open", "belt_out", "stow", "fetch", "belt_in", "cover_close", "recover"]
				weights = [0.13, 0.14, 0.11, 0.19, 0.15, 0.11, 0.17]
			else:
				# 弹链:开供弹盖 → 抽出旧链/旧箱 → 取新箱 → 新链入槽 → 关盖锁定 → 恢复
				names = ["cover_open", "belt_out", "fetch", "belt_in", "cover_close", "recover"]
				weights = (cfg.get("belt_weights", [0.17, 0.18, 0.24, 0.17, 0.13, 0.11]) as Array).duplicate()
		_:
			if tac and _flow() == "mag" and not _g().def.projectile and String(cfg.get("mag", "down")) != "none":
				# 战术换弹保留旧弹匣:拔下 → 收入胸前弹袋 → 取新匣 → 插入,不再把旧匣丢地上
				names = ["prepare", "remove", "stow", "fetch", "insert", "recover"]
				weights = (cfg.get("tac_weights", [0.13, 0.16, 0.16, 0.22, 0.18, 0.15]) as Array).duplicate()
			else:
				names = ["prepare", "remove", "fetch", "insert", "recover"]
				weights = (cfg.get("tac_weights", []) if tac else cfg.get("empty_weights", [])).duplicate()
			if weights.is_empty():
				weights = [0.16, 0.2, 0.32, 0.18, 0.14]
			if not tac and String(cfg.get("chamber_style", "pull")) != "none":
				names.insert(4, "chamber")
	# 弹鼓/弹链机枪空仓换弹在闭锁/锁定后追加拉机柄上膛阶段
	if flow in ["drum", "belt"] and not tac and String(cfg.get("chamber_style", "pull")) != "none":
		names.insert(names.size() - 1, "charge")
		weights.insert(weights.size() - 1, float(cfg.get("charge_weight", 0.14)))
	# 防御:配置错误时补权重
	while weights.size() < names.size():
		weights.append(0.1)
	while weights.size() > names.size():
		weights.remove_at(weights.size() - 1)
	_build_phases(names, weights, base_time)
	# 栓动狙刚开火后的拉栓循环先收尾,再开始卸弹;右手跟栓,左手保持护木
	if String(cfg.get("chamber_style", "pull")) == "bolt_cycle" and _g().bolt_t > 0.0:
		_bolt_wait = maxf(0.0, 0.85 - _g().bolt_t)


func _start_tube() -> void:
	var base_shell: float = float(cfg.get("shell_time", 0.7))
	# 战术换弹(膛内仍有弹)只补管式弹仓,节奏比空仓(含首壳上膛泵动)更快
	if _g().ammo > 0 and float(cfg.get("tac_shell_time", base_shell)) > 0.0:
		base_shell = float(cfg.get("tac_shell_time", base_shell))
	var shell_time: float = maxf(0.3, base_shell * _g()._reload_mult / maxf(0.1, float(cfg.get("anim_speed", 1.0))))
	shells_needed = mini(_g().mag_cap - _g().ammo, _g().reserve)
	shells_loaded = 0
	tube_first_chambered = false
	total = float(shells_needed) * shell_time
	var tube_weights_v: Array = cfg.get("tube_weights", [0.32, 0.3, 0.38])
	var weights := tube_weights_v.duplicate()
	_build_phases(["reach", "push", "return"], weights, shell_time)
	# 刚开火后的泵动/半自动枪机循环先自然收尾,再开始逐发装填;避免动作重叠
	var pump_dur_wait: float = float(cfg.get("pump_dur", 0.45))
	_pump_wait = 0.0
	if _g().pump_t > 0.0:
		_pump_wait = maxf(0.0, pump_dur_wait - _g().pump_t)
	elif _g().semi_t > 0.0:
		_pump_wait = maxf(0.0, 0.24 - _g().semi_t)
	if _pump_wait <= 0.0:
		AudioSys.reload_action(String(cfg.get("shell_grab_snd", "shell_grab")))


# ============================================================
# [9/10] 左轮手枪:快速装弹器 / 逐发装填(实际弹巢状态同步)
# ============================================================
func _start_revolver() -> void:
	_g()._normalize_revolver_chambers()
	revolver_quick = _g().ammo == 0
	revolver_mode = "quick" if revolver_quick else "single"
	revolver_eject_done = false
	revolver_loader_done = false
	revolver_load_count = 0
	revolver_target_shell = -1
	revolver_cycle_idx = 0
	revolver_open = 0.0
	revolver_spin_wait = 0.0
	if _g().cylinder_t > 0.0:
		revolver_spin_wait = maxf(0.0, 0.16 - _g().cylinder_t)
	if _g().hammer_t > 0.0:
		revolver_spin_wait = maxf(revolver_spin_wait, 0.22 - _g().hammer_t)
	var mult: float = _g()._reload_mult / maxf(0.1, float(cfg.get("anim_speed", 1.0)))
	var names: Array = []
	var durs: Array = []
	if revolver_quick:
		var total: float = maxf(0.8, float(cfg.get("quick_time", 2.0)) * mult)
		var qw: Array = (cfg.get("quick_weights", [0.16, 0.15, 0.20, 0.18, 0.16, 0.15]) as Array).duplicate()
		var wsum := 0.0
		for w in qw:
			wsum += float(w)
		names = ["rv_open", "rv_eject", "rv_fetch_loader", "rv_load_loader", "rv_close", "rv_recover"]
		for w in qw:
			durs.append(total * float(w) / maxf(wsum, 0.0001))
		revolver_load_count = mini(_g().mag_cap, _g().ammo + _g().reserve)
	else:
		var need := mini(_g().mag_cap - _g().ammo, _g().reserve)
		shells_needed = need
		shells_loaded = 0
		var open_t := clampf(float(cfg.get("single_time", 3.0)) * mult * 0.14, 0.32, 0.5)
		var eject_t := clampf(float(cfg.get("single_time", 3.0)) * mult * 0.12, 0.24, 0.42)
		var close_t := clampf(float(cfg.get("single_time", 3.0)) * mult * 0.16, 0.32, 0.5)
		var recover_t := 0.24
		var remain := maxf(0.05, float(cfg.get("single_time", 3.0)) * mult - open_t - eject_t - close_t - recover_t)
		var cycle_t := maxf(0.46, remain / float(maxi(1, need)))
		names = ["rv_open", "rv_eject"]
		durs = [open_t, eject_t]
		for i in need:
			names.append("rv_reach")
			names.append("rv_insert")
			names.append("rv_return")
			durs.append(cycle_t * 0.24)
			durs.append(cycle_t * 0.42)
			durs.append(cycle_t * 0.34)
		names.append("rv_close")
		names.append("rv_recover")
		durs.append(close_t)
		durs.append(recover_t)
	# 直接展开阶段,不做循环特殊推进;阶段时长就是真实换弹节奏
	phase_names = names
	phase_durs = durs
	var ttl := 0.0
	for d in phase_durs:
		ttl += float(d)
	total = ttl
	stage = 0
	stage_time = 0.0
	stage_dur = float(phase_durs[0]) if phase_durs.size() > 0 else 0.2
	stage_p = 0.0
	_on_stage_enter(0)


## 快速/逐发模式切换:弹巢尚未甩出前按 B 可切换(装填方式不冲突)。
func toggle_revolver_mode() -> bool:
	if not active or not _g().def.get("revolver") == true:
		return false
	if stage >= phase_names.size():
		return false
	var nm := String(phase_names[stage])
	if nm not in ["rv_open", "rv_eject"]:
		return false
	revolver_quick = not revolver_quick
	var keep_open := revolver_open
	_start_revolver()
	revolver_open = keep_open
	return true


func _finish_revolver() -> void:
	active = false
	_g().reloading = false
	_g().reload_t = time
	state = State.FINISH
	finish_t = 0.0
	finish_dur = float(cfg.get("finish_dur", 0.26))
	if revolver_hammer != null and _g().hammer_t <= 0.0:
		_g().hammer_t = 0.0001
		AudioSys.weapon_mech(String(cfg.get("cock_snd", "revolver_hammer")), float(cfg.get("mech_pitch", 1.0)))


func _revolver_want_open() -> float:
	if state == State.IDLE or state == State.CANCEL:
		return 0.0
	if stage >= phase_names.size():
		return 0.0
	var nm := String(phase_names[stage])
	match nm:
		"rv_open":
			return _ez(stage_p)
		"rv_eject", "rv_fetch_loader", "rv_load_loader", "rv_reach", "rv_insert", "rv_return":
			return 1.0
		"rv_close":
			return 1.0 - _ez(stage_p)
	return 0.0


func _revolver_cyl_center() -> Vector3:
	if revolver_crane == null or revolver_cylinder == null:
		return Vector3(0.0, 0.03, -0.08)
	return revolver_crane.transform * revolver_cylinder.position


func _revolver_chamber_pos(idx: int) -> Vector3:
	if revolver_crane == null or revolver_cylinder == null:
		return Vector3(0.0, 0.015, -0.06)
	if idx < 0 or idx >= revolver_shells.size() or not revolver_shells[idx] is Node3D:
		return _revolver_cyl_center()
	var shell: Node3D = revolver_shells[idx] as Node3D
	return revolver_crane.transform * (revolver_cylinder.transform * shell.position)


func _next_empty_chamber() -> int:
	var arr: Array = _g()._chamber_loaded
	var n: int = arr.size()
	if n <= 0:
		return -1
	var start: int = _g()._chamber_index
	for step in n:
		var idx := (start + step) % n
		if arr[idx] != true:
			return idx
	return -1


func _commit_revolver_round() -> void:
	var idx := revolver_target_shell
	if idx < 0:
		idx = _next_empty_chamber()
		revolver_target_shell = idx
	if idx < 0 or idx >= _g()._chamber_loaded.size() or shells_loaded >= shells_needed:
		return
	_g()._chamber_loaded[idx] = true
	_g().ammo = mini(_g().ammo + 1, _g().mag_cap)
	_g().reserve = maxi(0, _g().reserve - 1)
	_g()._sync_revolver_chambers()
	shells_loaded += 1
	revolver_load_count += 1
	revolver_target_shell = -1
	AudioSys.weapon_mech(String(cfg.get("insert_snd", "revolver_insert_" + _g().id)), float(cfg.get("mech_pitch", 1.0)))
	_impulse(float(cfg.get("insert_impact", 0.006)), 0.7)
	_camera_kick(0.65, 0.45)


func _commit_revolver_speedloader() -> void:
	if revolver_loader_done:
		return
	revolver_loader_done = true
	# 快速换弹:甩出时已把剩余实弹归还备弹;这里一次性压入全新弹巢
	var take := mini(_g().mag_cap, _g().reserve)
	var start_idx: int = _g()._chamber_index
	for i in _g()._chamber_loaded.size():
		_g()._chamber_loaded[i] = false
	for i in take:
		_g()._chamber_loaded[(start_idx + i) % _g()._chamber_loaded.size()] = true
	_g().ammo = take
	_g().reserve = maxi(0, _g().reserve - take)
	_g()._sync_revolver_chambers()
	shells_loaded = take
	revolver_load_count = take
	AudioSys.weapon_mech(String(cfg.get("insert_snd", "revolver_insert_" + _g().id)), float(cfg.get("mech_pitch", 1.0)))
	_impulse(float(cfg.get("insert_impact", 0.009)), 0.9)
	_camera_kick(0.9, 0.55)


func _commit_revolver_eject() -> void:
	if revolver_eject_done:
		return
	revolver_eject_done = true
	if revolver_quick:
		var live := _g().ammo
		_g().reserve += live
		_g().ammo = 0
		for i in _g()._chamber_loaded.size():
			_g()._chamber_loaded[i] = false
		_g()._sync_revolver_chambers()
	# 弹巢甩空时用现有效果系统抛出几枚铜壳(不新建粒子/物体,复用 casing 池)
	if G.effects != null and G.camera != null:
		for i in 3:
			G.effects.casing(_g().muzzle_world_main(), G.camera.global_transform.basis, 3, 0.8 + i * 0.12)
	_impulse(0.005, 0.55)
	_camera_kick(0.5, 0.4)


func _update_revolver(dt: float, _env: float) -> void:
	if stage >= phase_names.size():
		return
	var nm := String(phase_names[stage])
	var p := stage_p
	# 弹巢开合:所有阶段共用平滑插值,取消/换枪时也由 _recover_anim_parts 连续关闭
	var want := _revolver_want_open()
	revolver_open = Utils.damp(revolver_open, want, 14.0, dt)
	# 弹巢保持与枪身平行,直接向左侧(-X)平移滚出;铰链节点本身不再绕 Y 旋转
	if revolver_cylinder != null:
		var open_dist := 0.052
		revolver_cylinder.position = revolver_cyl_pos_base + Vector3(
			-open_dist * revolver_open,
			-0.004 * revolver_open,
			0.008 * revolver_open)
	if revolver_crane != null:
		revolver_crane.rotation = revolver_crane_base
	# 甩出弹巢/压入装弹时的枪身倾斜(叠加在换弹总姿态上,不会瞬移)
	if nm in ["rv_eject"]:
		pose_rot.x += sin(p * PI) * 0.14
		pose_rot.z += sin(p * PI) * 0.05
	elif nm in ["rv_insert", "rv_load_loader"]:
		pose_rot.x += 0.05
	if left_hand == null:
		return
	var cyl_pos: Vector3 = _revolver_cyl_center()
	var support := cyl_pos + Vector3(0.0, -0.035, 0.035)
	match nm:
		"rv_open":
			# 左手离开护木,抓住弹巢后缘把弹巢向左侧拨出(手部缩到 0.88 并留出安全间隙)
			var e := _ez(p)
			var arc := Vector3(-sin(e * PI) * 0.03, sin(e * PI) * 0.012, 0.0)
			left_hand.position = hand_rest.lerp(cyl_pos + Vector3(0.0, -0.022, 0.045), e) + arc
		"rv_eject":
			# 右手保持握把,左手拍退壳杆/弹巢前缘,弹出全部空壳(或快速换弹清膛)
			left_hand.position = support + Vector3(sin(p * PI) * 0.018, 0.0, sin(p * PI) * 0.012)
			if p >= 0.55:
				_commit_revolver_eject()
		"rv_fetch_loader":
			var pocket := _chest_pocket()
			if p < 0.4:
				var e := _ez(p / 0.4)
				left_hand.position = support.lerp(pocket, e) + Vector3(-sin(e * PI) * 0.04, 0.0, -sin(e * PI) * 0.03)
			else:
				var e := _ez((p - 0.4) / 0.6)
				left_hand.position = pocket.lerp(cyl_pos + Vector3(0.0, 0.0, 0.045), e) + Vector3(-sin(e * PI) * 0.03, 0.0, -sin(e * PI) * 0.03)
				if speedloader_mesh != null and e > 0.06:
					speedloader_mesh.visible = true
					speedloader_mesh.position = left_hand.position + Vector3(0.0, 0.012, -0.01)
					speedloader_mesh.rotation = Vector3(0.0, 0.0, e * 0.4)
		"rv_load_loader":
			var target := _revolver_cyl_center() + Vector3(0.0, 0.016, 0.055)
			var e := _ez(p)
			left_hand.position = (support + Vector3(0.0, 0.1, 0.06)).lerp(target, e)
			if speedloader_mesh != null:
				speedloader_mesh.visible = not revolver_loader_done
				speedloader_mesh.position = left_hand.position + Vector3(0.0, 0.012, -0.01)
				speedloader_mesh.rotation = Vector3(0.0, 0.0, 0.4 * (1.0 - e))
			if p >= 0.55:
				_commit_revolver_speedloader()
		"rv_reach":
			# 逐发:从弹药袋取出一发,手指/弹头一起回到空膛位置
			var pocket := _chest_pocket()
			var e := _ez(p)
			left_hand.position = support.lerp(pocket, e) + Vector3(-sin(e * PI) * 0.04, 0.0, -sin(e * PI) * 0.03)
			if shell_mesh != null:
				if p >= 0.42:
					shell_mesh.visible = true
					shell_mesh.position = left_hand.position + Vector3(0.0, 0.014, -0.012)
		"rv_insert":
			if revolver_target_shell < 0:
				revolver_target_shell = _next_empty_chamber()
			var chamber: Vector3 = _revolver_chamber_pos(revolver_target_shell)
			var target := chamber + Vector3(0.0, 0.014, 0.045)
			var e := _ez(p)
			left_hand.position = (_chest_pocket() + Vector3(0.0, 0.04, 0.02)).lerp(target, e) + Vector3(-sin(e * PI) * 0.025, 0.0, -sin(e * PI) * 0.02)
			if shell_mesh != null:
				shell_mesh.visible = p < 0.62
				shell_mesh.position = left_hand.position + Vector3(0.0, 0.012, -0.01)
			if p >= 0.62:
				_commit_revolver_round()
				if shell_mesh != null:
					shell_mesh.visible = false
		"rv_return":
			left_hand.position = support.lerp(hand_rest, _ez(p))
			if shell_mesh != null:
				shell_mesh.visible = false
		"rv_close":
			# 左手把弹巢推回枪身,闭锁后拇指扳下击锤(hammer_t 在 _finish_revolver 触发)
			var e := _ez(p)
			left_hand.position = (cyl_pos + Vector3(0.0, -0.022, 0.05)).lerp(hand_rest, e) + Vector3(sin(e * PI) * 0.025, 0.0, 0.0)
		"rv_recover":
			_recover_hands(dt)
	_update_hand_rotation(dt)


func _build_phases(names: Array, weights: Array, duration: float) -> void:
	phase_names = names
	phase_durs.clear()
	var wsum := 0.0
	for w in weights:
		wsum += float(w)
	if wsum <= 0.0001:
		wsum = 1.0
	for w in weights:
		phase_durs.append(duration * float(w) / wsum)
	stage = Stage.PREPARE
	stage_time = 0.0
	stage_dur = float(phase_durs[0]) if phase_durs.size() > 0 else 0.2
	stage_p = 0.0
	_on_stage_enter(0)


# ============================================================
# 主更新
# ============================================================

func _update_active(dt: float) -> void:
	# 霰弹枪:等待开火后的泵动循环收尾,期间枪机/左手同步,不推进装填阶段
	if _g().def.pellets > 1 and _pump_wait > 0.0:
		_pump_wait -= dt
		_g().reload_t = time
		_update_pose(0.0, dt)
		_update_camera(0.0, dt)
		_recover_hands(dt)
		if _pump_wait <= 0.0:
			AudioSys.reload_action(String(cfg.get("shell_grab_snd", "shell_grab")))
		return
	# 左轮:等待开火后的换膛/击锤动画收尾,再开弹巢
	if _g().def.get("revolver") == true and revolver_spin_wait > 0.0:
		revolver_spin_wait -= dt
		_g().reload_t = time
		_update_pose(0.0, dt)
		_update_camera(0.0, dt)
		_recover_hands(dt)
		return
	# 栓动狙:等待拉栓循环收尾,右手跟栓完成后才开始卸弹
	if _bolt_wait > 0.0:
		_bolt_wait -= dt
		_g().reload_t = time
		_update_pose(0.0, dt)
		_update_camera(0.0, dt)
		_recover_hands(dt)
		return
	time += dt
	stage_time += dt
	stage_p = clampf(stage_time / maxf(stage_dur, 0.0001), 0.0, 1.0)
	_g().reload_t = time
	var env := _pose_envelope()
	_update_pose(env, dt)
	_update_camera(env, dt)
	if _g().def.get("revolver") == true:
		_update_revolver(dt, env)
	elif _g().def.pellets > 1:
		_update_tube(dt, env)
	else:
		_update_mag_reload(dt, env)
	# 阶段推进
	if state == State.ACTIVE and stage_p >= 1.0:
		_next_stage()


func _next_stage() -> void:
	# 左轮阶段已按快速/逐发流程静态展开:直接顺序推进,循环轮次就包含在 phase_names 中
	if _g().def.get("revolver") == true:
		var ridx := stage + 1
		if ridx >= phase_names.size():
			_finish_revolver()
			return
		stage = ridx
		stage_time = 0.0
		stage_dur = float(phase_durs[ridx])
		stage_p = 0.0
		_on_stage_enter(ridx)
		return
	if _g().def.pellets > 1:
		var tube_idx := stage + 1
		if tube_idx < phase_names.size():
			stage = (tube_idx as Stage)
			stage_time = 0.0
			stage_dur = float(phase_durs[tube_idx])
			stage_p = 0.0
			_on_stage_enter(tube_idx)
		else:
			_tube_next_cycle()
		return
	var idx := stage + 1
	if idx >= phase_names.size():
		_finish_reload()
		return
	stage = (idx as Stage)
	stage_time = 0.0
	stage_dur = float(phase_durs[idx])
	stage_p = 0.0
	_on_stage_enter(idx)


func _on_stage_enter(idx: int) -> void:
	var nm: String = String(phase_names[idx])
	var flow := _flow()
	var pitch := float(cfg.get("mech_pitch", 1.0))
	_stage_event_done = false
	match nm:
		"rv_open":
			AudioSys.weapon_mech(String(cfg.get("open_snd", "revolver_open")), pitch)
		"rv_eject":
			AudioSys.weapon_mech(String(cfg.get("eject_snd", "revolver_eject")), pitch)
		"rv_fetch_loader":
			AudioSys.weapon_mech(String(cfg.get("loader_snd", "revolver_loader")), pitch)
		"rv_load_loader":
			pass
		"rv_reach":
			revolver_target_shell = _next_empty_chamber()
			AudioSys.weapon_mech(String(cfg.get("round_snd", "revolver_round")), pitch)
		"rv_insert":
			pass
		"rv_return":
			pass
		"rv_close":
			AudioSys.weapon_mech(String(cfg.get("close_snd", "revolver_close")), pitch)
		"unlock":
			# 手已抓住弹鼓锁扣,开始解锁(音效在阶段开始,鼓身抖动在 update 中)
			AudioSys.mech("drum_unlock", pitch)
		"remove":
			if flow == "drum":
				AudioSys.mech("drum_detach", pitch)
			elif _g().def.projectile:
				# RPG:抽出/抛掉空筒
				AudioSys.reload_action("rocket_remove", pitch)
			else:
				# 手已接触到弹匣/释放钮,开始卸弹:按枪族使用不同拔弹匣采样
				AudioSys.reload_action(String(cfg.get("mag_out_snd", "mag_out")), pitch)
		"stow":
			# 战术换弹:旧供弹具收入携行具(弹匣/弹鼓/弹链箱各自用对应取物声)
			var stow_snd: String = "belt_pouch" if flow == "belt" else ("drum_pouch" if flow == "drum" else String(cfg.get("pouch_snd", "ammo_pouch")))
			AudioSys.reload_action(stow_snd, pitch * 0.94)
		"cover_open":
			AudioSys.mech(_belt_action("cover_open"), pitch)
		"belt_out":
			AudioSys.mech(_belt_action("belt_out"), pitch)
		"fetch":
			# 从胸挂/弹袋取新供弹具:弹匣/弹鼓/弹链箱使用不同的取物声
			if flow == "drum":
				AudioSys.reload_action("drum_pouch", pitch)
			elif flow == "belt":
				AudioSys.reload_action("belt_pouch", pitch)
			else:
				AudioSys.reload_action(String(cfg.get("pouch_snd", "ammo_pouch")), pitch)
			if flow == "mag":
				if mag != null and not old_mag_dropped and cfg.get("mag", "down") != "none":
					_drop_old_mag()
				if rocket != null and _g().def.projectile:
					# 旧导弹筒已在 REMOVE 阶段滑出并隐藏,这里保持隐藏
					rocket.visible = false
			hand_after_remove = left_hand.position if left_hand != null else hand_grip_anchor
			# FETCH 后半段直接使用 insert_start 规划手/弹匣路径,阶段开始时必须更新。
			var ins := _mag_insert_start()
			if flow == "drum":
				ins = _drum_insert_start()
			elif flow == "belt":
				ins = _belt_insert_start()
			elif _g().def.projectile:
				ins = _rocket_insert_start()
			insert_start = ins.get("pos", mag_base)
			insert_start_rot = ins.get("rot", Vector3.ZERO)
		"insert":
			insert_swapped = false
			if flow == "mag":
				if mag != null and cfg.get("mag", "down") != "none":
					mag.visible = true
				if rocket != null and not _g().def.projectile:
					rocket.visible = true
				if _g().def.projectile:
					insert_start = _rocket_insert_start().get("pos", rocket_base)
					insert_start_rot = _rocket_insert_start().get("rot", Vector3.ZERO)
				else:
					insert_start = _mag_insert_start().get("pos", mag_base)
					insert_start_rot = _mag_insert_start().get("rot", Vector3.ZERO)
					if cfg.get("mag", "down") == "none":
						# 无实体弹匣(如 M24 内置弹仓):新弹药直接由手送到装填口
						insert_start = _g()._hand_l1
						insert_start_rot = Vector3.ZERO
			else:
				# 弹鼓插入:新鼓从手上出现,旧鼓已掉落/隐藏,鼓体沿对位 → 推入路径运动
				if new_mag != null:
					new_mag.visible = true
					new_mag.position = insert_start
					new_mag.rotation = insert_start_rot
		"belt_in":
			insert_swapped = false
			if new_mag != null:
				new_mag.visible = true
				new_mag.position = insert_start
				new_mag.rotation = insert_start_rot
			if new_belt != null:
				new_belt.visible = true
				new_belt.position = belt_base + Vector3(_side_sign() * 0.07, 0.012, 0.012)
				new_belt.rotation = belt_base_rot + Vector3(0.0, 0.0, _side_sign() * 0.35)
				_set_belt_fill(new_belt, _planned_belt_fill())
		"lock":
			# 弹鼓锁闭事件在 update 中达到 seal_point 时触发
			pass
		"cover_close":
			AudioSys.mech(_belt_action("cover_close"), pitch)
			# 供弹盖闭合后的机械闭锁在 update 中达到 seal_point 时触发
		"chamber", "charge":
			_chamber_hand_start = left_hand.position if left_hand != null else hand_grip_anchor
			_start_chamber()
		"recover":
			pass


func _update_mag_reload(dt: float, _env: float) -> void:
	# 注意:战术换弹的 phase_names 没有 chamber,阶段索引不能直接当 Stage 枚举用,
	# 必须按阶段名分发,否则战术换弹会把第 4 阶段误判成 CHAMBER 并触发拉栓。
	if stage >= phase_names.size():
		return
	var nm := String(phase_names[stage])
	var flow := _flow()
	match nm:
		"prepare":
			if _g().def.projectile:
				_update_rocket_prepare()
			else:
				_update_mag_prepare()
		"unlock":
			_update_drum_unlock()
		"remove":
			match flow:
				"drum":
					_update_drum_remove()
				"belt":
					_update_belt_out()
				_:
					if _g().def.projectile:
						_update_rocket_remove()
					else:
						_update_mag_remove()
		"stow":
			_update_mag_stow()
		"cover_open":
			_update_cover_open()
		"belt_out":
			_update_belt_out()
		"fetch":
			match flow:
				"drum":
					_update_drum_fetch()
				"belt":
					_update_belt_fetch()
				_:
					if _g().def.projectile:
						_update_rocket_fetch()
					else:
						_update_mag_fetch()
		"insert":
			match flow:
				"drum":
					_update_drum_insert(dt)
				"belt":
					_update_belt_in(dt)
				_:
					if _g().def.projectile:
						_update_rocket_insert()
					else:
						_update_mag_insert(dt)
		"belt_in":
			_update_belt_in(dt)
		"lock":
			_update_drum_lock(dt)
		"cover_close":
			_update_cover_close(dt)
		"chamber", "charge":
			_update_chamber(dt)
		"recover":
			_recover_hands(dt)
	_update_hand_rotation(dt)


# ============================================================
# 霰弹枪管式弹仓逐发装填
# ============================================================

func _tube_stage_from_idx(idx: int) -> void:
	if idx <= 0:
		tube_stage = TubeStage.REACH
	elif idx == 1:
		tube_stage = TubeStage.PUSH
	else:
		tube_stage = TubeStage.RETURN


func _update_tube(dt: float, _env: float) -> void:
	_tube_stage_from_idx(stage)
	_update_tube_hand(dt)
	if shell_mesh != null:
		_update_tube_shell()
	match tube_stage:
		TubeStage.PUSH:
			if stage_p >= float(cfg.get("insert_commit", 0.52)) and not committed:
				_commit_shell()
		TubeStage.RETURN:
			pass
	_update_hand_rotation(dt)


func _tube_next_cycle() -> void:
	stage = (0 as Stage)
	stage_time = 0.0
	stage_p = 0.0
	stage_dur = float(phase_durs[0]) if phase_durs.size() > 0 else 0.2
	tube_stage = TubeStage.REACH
	committed = false
	AudioSys.reload_action(String(cfg.get("shell_grab_snd", "shell_grab")))
	if shell_mesh != null:
		shell_mesh.visible = false


func _update_tube_hand(_dt: float) -> void:
	if left_hand == null:
		return
	var port: Vector3 = _g()._hand_l1 if _g()._hand_l1 != Vector3.ZERO else Vector3(0.0, -0.05, 0.14)
	var a := hand_rest
	var b := port
	var p := stage_p
	match tube_stage:
		TubeStage.REACH:
			var e := _ez(p)
			var arc := sin(e * PI) * float(cfg.get("hand_arc", 0.07))
			left_hand.position = a.lerp(b, e) + Vector3(arc, 0.0, -arc * 0.4)
		TubeStage.PUSH:
			var s := sin(p * PI)
			left_hand.position = b + Vector3(s * 0.012, s * 0.022, s * 0.008)
		TubeStage.RETURN:
			var e := _ez(p)
			left_hand.position = b.lerp(a, e)


func _update_tube_shell() -> void:
	var h := left_hand.position if left_hand != null else hand_rest
	var p := stage_p
	match tube_stage:
		TubeStage.REACH:
			if p < 0.42:
				shell_mesh.visible = false
			else:
				shell_mesh.visible = true
				var e := _ez((p - 0.42) / 0.58)
				shell_mesh.position = h + Vector3(0.0, 0.018 + e * 0.012, -0.015)
		TubeStage.PUSH:
			shell_mesh.visible = not committed
			var s := sin(p * PI)
			shell_mesh.position = h + Vector3(0.0, 0.018 - s * 0.01, -0.015 + s * 0.012)
		TubeStage.RETURN:
			shell_mesh.visible = false


func _commit_shell() -> void:
	if shells_loaded >= shells_needed:
		return
	committed = true
	if shell_mesh != null:
		shell_mesh.visible = false
	shells_loaded += 1
	_g().ammo = mini(_g().ammo + 1, _g().mag_cap)
	_g().reserve = maxi(0, _g().reserve - 1)
	AudioSys.reload_action(String(cfg.get("shell_insert_snd", "shell_insert")))
	_impulse(float(cfg.get("insert_impact", 0.008)) * 0.8, 0.7)
	_camera_kick(0.7, 0.5)
	# 空仓逐发装填:第一发入膛后泵动枪上膛、半自动枪机自动回位,然后才继续补管式弹仓
	if started_empty and shells_loaded == 1 and not tube_first_chambered:
		tube_first_chambered = true
		if _g()._pump != null and _g().def.get("pump_action") == true:
			_g()._start_pump_cycle()
			var pump_dur: float = float(cfg.get("pump_dur", 0.45))
			_pump_wait = maxf(_pump_wait, pump_dur)
		elif _g()._bolt != null:
			_g()._start_semi_auto_cycle()
			_pump_wait = maxf(_pump_wait, 0.24)
	if shells_loaded >= shells_needed:
		_finish_tube()


func _finish_tube() -> void:
	active = false
	_g().reloading = false
	if shell_mesh != null:
		shell_mesh.visible = false
	state = State.FINISH
	finish_t = 0.0
	finish_dur = float(cfg.get("finish_dur", 0.26))
	# 第一发已在 _commit_shell 触发真实泵动;这里只为仍缺泵动的空仓换弹补一次
	if started_empty and pump != null and not tube_first_chambered and _g().pump_t <= 0.0:
		_g()._start_pump_cycle()
		finish_dur = 0.55
		_camera_kick(1.0, 0.8)
		_impulse(float(cfg.get("chamber_impact", 0.014)), 1.0)
		AudioSys.weapon_mech("pump_finish_" + _g().id, 1.0)
	elif started_empty and pump != null and tube_first_chambered:
		# 让首壳泵动完整播完再回正,避免换弹结束瞬间跳变
		finish_dur = maxf(finish_dur, float(cfg.get("pump_dur", 0.45)) + 0.1)
	elif started_empty and pump == null and _g()._bolt != null and tube_first_chambered:
		# 半自动霰弹枪:等自动枪机循环收尾
		finish_dur = maxf(finish_dur, 0.34)
	elif started_empty and pump == null:
		_camera_kick(0.6, 0.4)


# ============================================================
# 弹匣武器的六个阶段
# ============================================================

func _update_mag_prepare() -> void:
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		mag.rotation = mag_base_rot
	if left_hand == null:
		return
	var e := _ez(stage_p)
	# 换弹开始:左手先抓住旧弹匣
	var grip := hand_grip_anchor
	left_hand.position = hand_rest.lerp(grip, e)


func _update_mag_remove() -> void:
	var p := stage_p
	if _tac_retain_active():
		_update_tac_retain_remove(p)
		return
	if mag != null:
		var pose := _mag_remove_pose(p)
		mag.position = pose.get("pos", mag_base)
		mag.rotation = pose.get("rot", Vector3.ZERO)
		if p >= float(cfg.get("drop_point", 0.62)) and not old_mag_dropped:
			_drop_old_mag()
	if left_hand != null:
		if old_mag_dropped:
			# 手腕随弹匣惯性继续走一小段,不出现“弹匣一脱手手就停住”
			var tail := clampf((p - float(cfg.get("drop_point", 0.62))) / (1.0 - float(cfg.get("drop_point", 0.62))), 0.0, 1.0)
			left_hand.position = hand_after_remove.lerp(hand_after_remove + Vector3(0.0, -0.045, 0.018), _ez(tail))
		elif mag != null:
			left_hand.position = mag.position + _grip_offset()
	hand_after_remove = left_hand.position if left_hand != null else hand_grip_anchor


## 战术换弹保留弹匣:拔下旧匣后向胸前弹袋移动,旧匣始终在手里,不触发掉落
func _update_tac_retain_remove(p: float) -> void:
	if mag != null:
		var pose := _mag_remove_pose(p)
		var pos: Vector3 = pose.get("pos", mag_base)
		var rot: Vector3 = pose.get("rot", Vector3.ZERO)
		# 保留路径:拔出距离略短,旋转略小,避免和接下来的“收入弹袋”动作跳变
		var e := _ez(p)
		pos = mag_base.lerp(pos, 0.82)
		rot *= 0.8
		pos += Vector3(-e * 0.012, -e * 0.01, e * 0.012)
		mag.position = pos
		mag.rotation = rot
	if left_hand != null:
		if mag != null:
			left_hand.position = mag.position + _grip_offset()
		hand_after_remove = left_hand.position


## 战术换弹保留弹匣:手与旧匣一起进入胸前弹袋,进袋后隐藏(弹匣被保留,不是丢地)
func _update_mag_stow() -> void:
	var p := stage_p
	var e := _ez(p)
	var sb: Vector3 = cfg.get("stow_bias", Vector3.ZERO)
	var pocket := _chest_pocket() + sb
	var start := hand_after_remove
	var stow_arc: float = float(cfg.get("stow_arc", 0.07))
	if left_hand != null:
		var arc := sin(e * PI) * stow_arc
		left_hand.position = start.lerp(pocket, e) + Vector3(-arc, arc * 0.4, -arc * 0.3)
		if mag != null and not old_mag_stowed:
			mag.position = left_hand.position - _grip_offset()
			mag.rotation = mag.rotation.lerp(mag_base_rot * 0.4, 1.0 - exp(-12.0 * 0.016))
	if mag != null and not old_mag_stowed and p >= float(cfg.get("drop_point", 0.55)):
		old_mag_stowed = true
		old_mag_dropped = true
		hand_after_remove = left_hand.position if left_hand != null else pocket
		mag.visible = false
		_g().grip_amt = 0.15


## 当前是否处于“战术换弹保留旧弹匣”流程(阶段表里包含 stow)
func _tac_retain_active() -> bool:
	return not started_empty and phase_names.has("stow")


## COD 战术换弹:新弹匣从腰间上提到弹匣井下方,把旧弹匣从弹匣井“顶掉”后直接推入
func _update_tac_mag_remove(p: float) -> void:
	if left_hand == null:
		return
	var pocket := _chest_pocket()
	var ins_start: Vector3 = _mag_insert_start().get("pos", mag_base)
	var target := ins_start + _grip_offset()
	var e := _ez(p)
	var arc := sin(e * PI) * float(cfg.get("hand_arc", 0.09))
	# 左手从左侧腰间向右下方走到弹匣井下方插入位,弧线向左,避免向右甩弹匣
	left_hand.position = pocket.lerp(target, e) + Vector3(-arc, 0.0, -arc * 0.5)
	if mag != null:
		# 旧弹匣保持在弹匣井内,直到被新匣“顶掉”
		mag.position = mag_base
		mag.rotation = mag_base_rot
		mag.visible = true
		var tac_drop := 0.55
		if p >= tac_drop and not old_mag_dropped:
			_drop_old_mag()
	if new_mag != null:
		# 新弹匣从手上独立出现,和枪上的旧弹匣同时可见,形成真正的“顶匣”视觉
		new_mag.visible = true
		new_mag.position = left_hand.position - _grip_offset()
		new_mag.rotation = _mag_insert_start().get("rot", Vector3.ZERO) * _ez(p)
	hand_after_remove = left_hand.position


func _update_mag_fetch() -> void:
	if left_hand == null:
		return
	var p := stage_p
	var pocket: Vector3 = _chest_pocket()
	var fetch_start := hand_after_remove
	var fetch_arc: float = float(cfg.get("fetch_arc", 0.09))
	if p < 0.42:
		# 旧弹匣脱手后手收回胸口/屏外,随后从胸口取出新弹匣
		var e := _ez(p / 0.42)
		var arc := sin(e * PI) * fetch_arc * 0.8
		left_hand.position = fetch_start.lerp(pocket, e) + Vector3(-arc, 0.0, -arc * 0.5)
		if mag != null:
			mag.visible = false
	else:
		var e := _ez((p - 0.42) / 0.58)
		var target := insert_start + _grip_offset()
		var arc := sin(e * PI) * fetch_arc
		left_hand.position = pocket.lerp(target, e) + Vector3(-arc, 0.0, -arc * 0.5)
		# 新弹匣从屏外跟着手回来:出现、移动、旋转都是连续的
		if mag != null and e > 0.06:
			mag.visible = true
			mag.position = left_hand.position - _grip_offset()
			mag.rotation = insert_start_rot * _ez(e)


func _update_mag_insert(dt: float) -> void:
	var p := stage_p
	var commit_frac: float = float(cfg.get("insert_commit", 0.52))
	var contact: float = float(cfg.get("insert_contact", 0.30))
	if new_mag != null:
		new_mag.visible = false
	if mag != null:
		var pose := _mag_insert_pose(p)
		mag.position = pose.get("pos", mag_base)
		mag.rotation = pose.get("rot", Vector3.ZERO)
		mag.visible = true
	if left_hand != null:
		if p < contact:
			# 手托弹匣底部移动;弹匣还未接触弹匣井,只能沿手部路径走
			if mag != null:
				left_hand.position = mag.position + _grip_offset()
		else:
			# 接触后手继续推入,产生短促冲击位移
			if mag != null:
				left_hand.position = mag.position + _grip_offset() + Vector3(0.0, sin(p * PI) * 0.004, 0.0)
	if not committed:
		var gap: float = float(cfg.get("commit_gap", 0.028))
		var near_enough: bool = false
		if mag != null:
			near_enough = mag.position.distance_to(mag_base) <= gap
		else:
			near_enough = p >= commit_frac
		if near_enough or p >= 0.88:
			_commit_mag()
	# 拍实(slap)动画已上移到主循环 _update_mag_slap:它必须跨阶段完整播完,
	# 不能随 INSERT 结束被截断(截断就是 m4 弹匣停在 +0.019 的根因)。


func _commit_mag() -> void:
	committed = true
	_insert_slap_t = 0.0
	# 弹匣余弹归还备弹,再取走整匣(总数守恒)
	_g().reserve += _g().ammo
	var take := mini(_g().mag_cap, _g().reserve)
	_g().ammo = take
	_g().reserve -= take
	if _g().def.projectile:
		# 抛射物装填音:默认导弹筒入膛;榴弹发射器由 profile 覆写为逐发塞弹声
		AudioSys.reload_action(String(cfg.get("load_snd", "rocket_load")))
	else:
		AudioSys.reload_action(String(cfg.get("mag_in_snd", "mag_in")))
	var slap: float = float(cfg.get("slap", 0.018))
	var imp: float = float(cfg.get("insert_impact", 0.009))
	_impulse(imp + slap * 0.25, 0.8)
	_camera_kick(0.75, 0.5)


# ============================================================
# 弹鼓轻机枪专用流程(解锁 → 摘下 → 取新鼓 → 对位插入 → 锁定)
# ============================================================

func _flow() -> String:
	return String(cfg.get("reload_flow", "mag"))


func _mech_pitch() -> float:
	return float(cfg.get("mech_pitch", 1.0))


## 弹链动作采样名:重机枪组追加 _heavy,轻机枪组使用基础采样
func _belt_action(base: String) -> String:
	if String(cfg.get("belt_snd_set", "light")) == "heavy":
		return base + "_heavy"
	return base


# ============================================================
# 反载具导弹装填(卸旧导弹筒 → 取新导弹筒 → 前口对位 → 推入锁定)
# ============================================================

## 弹药件所在父空间 → 枪身(group)空间。
## 火箭筒的 rocket 直挂 group,榴弹发射器的榴弹挂在可下折膛体下:
## 手部锚点必须换算到 group 空间,否则手会偏到铰链偏移+旋转之外。
func _rocket_to_group(p: Vector3) -> Vector3:
	if rocket == null:
		return p
	var host := rocket.get_parent() as Node3D
	if host == null or host == group:
		return p
	return host.transform * p


func _rocket_grip_pos() -> Vector3:
	return _rocket_to_group(rocket_base) + Vector3(0.0, -0.040, -0.08)


## 枪身(group)空间 → 弹药件父空间(_rocket_to_group 的逆):
## 让新弹药件跟着手走时,把手的 group 坐标换算回它自己的父空间。
func _group_to_rocket(p: Vector3) -> Vector3:
	if rocket == null:
		return p
	var host := rocket.get_parent() as Node3D
	if host == null or host == group:
		return p
	return host.transform.affine_inverse() * p


func _rocket_remove_pose(p: float) -> Dictionary:
	var e := _ez(p)
	# 旧导弹筒从前口滑出,再随重力轻微下沉;缩短前伸距离,保证前臂长度自然
	return {
		"pos": rocket_base + Vector3(0.0, -e * 0.05, -e * 0.14),
		"rot": Vector3(e * 0.10, 0.0, 0.0),
	}


func _update_rocket_prepare() -> void:
	if rocket != null:
		rocket.visible = true
		rocket.position = rocket_base
		rocket.rotation = Vector3.ZERO
	if left_hand != null:
		var grip := _rocket_grip_pos()
		var e := _ez(stage_p)
		left_hand.position = hand_rest.lerp(grip, e) + Vector3(sin(e * PI) * 0.02, -sin(e * PI) * 0.01, 0.0)


func _update_rocket_remove() -> void:
	var p := stage_p
	if rocket != null:
		var pose := _rocket_remove_pose(p)
		rocket.position = pose.get("pos", rocket_base)
		rocket.rotation = pose.get("rot", Vector3.ZERO)
		if p >= float(cfg.get("drop_point", 0.62)) and not old_mag_dropped:
			old_mag_dropped = true
			rocket.visible = false
			_impulse(0.005, 0.5)
			_camera_kick(0.5, 0.35)
	if left_hand != null:
		if old_mag_dropped:
			var tail := clampf((p - float(cfg.get("drop_point", 0.62))) / (1.0 - float(cfg.get("drop_point", 0.62))), 0.0, 1.0)
			left_hand.position = hand_after_remove.lerp(hand_after_remove + Vector3(0.0, -0.04, -0.02), _ez(tail))
		elif rocket != null:
			left_hand.position = _rocket_to_group(rocket.position) + Vector3(0.0, -0.040, -0.08)
	hand_after_remove = left_hand.position if left_hand != null else _rocket_grip_pos()


func _rocket_insert_start() -> Dictionary:
	# 默认(火箭筒):新弹筒从前口斜下方推入。
	# 榴弹发射器由 profile 覆写 insert_offset 为「后上方」——中折式是从弹膛后端塞弹。
	var off: Vector3 = cfg.get("insert_offset", Vector3(0.0, -0.055, -0.22))
	return {
		"pos": rocket_base + off,
		"rot": Vector3(0.10, 0.0, 0.0),
	}


func _update_rocket_fetch() -> void:
	if left_hand == null:
		return
	var p := stage_p
	var pocket := _chest_pocket()
	var fetch_start := hand_after_remove
	if p < 0.42:
		var e := _ez(p / 0.42)
		var arc := sin(e * PI) * 0.07
		left_hand.position = fetch_start.lerp(pocket, e) + Vector3(-arc, 0.0, -arc * 0.45)
	else:
		var e := _ez((p - 0.42) / 0.58)
		var target := _rocket_to_group(insert_start) + Vector3(0.0, -0.040, -0.08)
		var arc := sin(e * PI) * float(cfg.get("hand_arc", 0.09))
		var hand_pos := pocket.lerp(target, e) + Vector3(-arc, 0.0, -arc * 0.45)
		left_hand.position = hand_pos
		# 新弹药件在「摸到胸挂」那一刻就握在手里,随手一路带到装填口。
		# (原先固定摆在装填口 → 手还在半路,弹药看上去是凭空变出来的)
		if new_rocket != null:
			new_rocket.visible = true
			new_rocket.position = _group_to_rocket(hand_pos - Vector3(0.0, -0.040, -0.08))
			new_rocket.rotation = insert_start_rot * _ez(e)


func _update_rocket_insert() -> void:
	var p := stage_p
	if new_rocket != null and not insert_swapped:
		var e := _ez(p)
		var pos: Vector3 = insert_start.lerp(rocket_base, e)
		var rot: Vector3 = insert_start_rot * (1.0 - e)
		new_rocket.position = pos
		new_rocket.rotation = rot
		new_rocket.visible = true
	if left_hand != null and new_rocket != null and not insert_swapped:
		left_hand.position = _rocket_to_group(new_rocket.position) + Vector3(0.0, -0.040, -0.08)
		if p >= 0.25:
			left_hand.position += Vector3(0.0, sin(p * PI) * 0.004, 0.0)
	if not committed and (p >= 0.82 or (new_rocket != null and new_rocket.position.distance_to(rocket_base) <= 0.012)):
		_commit_mag()
	if committed and new_rocket != null and p >= 0.90 and not insert_swapped:
		insert_swapped = true
		new_rocket.visible = false
		if rocket != null:
			rocket.visible = true
			rocket.position = rocket_base
			rocket.rotation = Vector3.ZERO


## 供弹具在枪械哪一侧:由模型 mag 节点的实际 x 坐标决定,保证手与弹鼓/弹链箱同侧。
func _side_sign() -> float:
	return -1.0 if mag_base.x < 0.0 else 1.0


func _update_drum_unlock() -> void:
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		# 解锁:先抓住鼓体,手腕带鼓面做短促扭转,表示按下/旋开锁扣
		var wig := sin(stage_p * PI) * 0.04
		mag.rotation = mag_base_rot + Vector3(wig * 0.3, wig * 0.5, wig)
	if left_hand != null:
		var grip := _mag_grip_pos(mag_base)
		var e := _ez(stage_p)
		# 从护木向左侧弹鼓绕行,避免手臂直线穿过机匣
		left_hand.position = hand_rest.lerp(grip, e) + Vector3(_side_sign() * sin(e * PI) * 0.045, -sin(e * PI) * 0.015, 0.0)
	if stage_p >= 0.72 and not _stage_event_done:
		_stage_event_done = true
		_impulse(0.004, 0.45)
		_camera_kick(0.4, 0.3)


func _drum_remove_pose(p: float) -> Dictionary:
	var e := _ez(p)
	var side := _side_sign()
	# 先向挂载侧横移脱出接口,再随重力下沉,鼓面逐渐翻转
	var sag := sin(e * PI) * 0.02
	return {
		"pos": mag_base + Vector3(side * e * 0.12, -e * 0.075, sag),
		"rot": Vector3(sin(e * PI) * 0.04, e * 0.1, side * e * 0.6),
	}


func _update_drum_remove() -> void:
	var p := stage_p
	var retain := _tac_retain_active()
	if mag != null:
		var pose := _drum_remove_pose(p)
		mag.position = pose.get("pos", mag_base)
		mag.rotation = pose.get("rot", Vector3.ZERO)
		if p >= float(cfg.get("drop_point", 0.62)) and not old_mag_dropped and not retain:
			_drop_old_mag()
			_impulse(0.005, 0.5)
			_camera_kick(0.5, 0.35)
	if left_hand != null:
		if old_mag_dropped:
			var tail := clampf((p - float(cfg.get("drop_point", 0.62))) / (1.0 - float(cfg.get("drop_point", 0.62))), 0.0, 1.0)
			left_hand.position = hand_after_remove.lerp(hand_after_remove + Vector3(_side_sign() * 0.035, -0.045, 0.018), _ez(tail))
		elif mag != null:
			left_hand.position = _grip_on(mag)
	hand_after_remove = left_hand.position if left_hand != null else hand_grip_anchor


func _update_drum_fetch() -> void:
	if left_hand == null:
		return
	var p := stage_p
	var pocket := _chest_pocket()
	var fetch_start := hand_after_remove
	var side := _side_sign()
	if p < 0.42:
		var e := _ez(p / 0.42)
		var arc := sin(e * PI) * 0.07
		left_hand.position = fetch_start.lerp(pocket, e) + Vector3(side * arc * 0.5, 0.0, -arc * 0.45)
	else:
		var e := _ez((p - 0.42) / 0.58)
		var target := insert_start + _grip_offset()
		var arc := sin(e * PI) * float(cfg.get("hand_arc", 0.09))
		var hand_pos := pocket.lerp(target, e) + Vector3(side * arc * 0.55, 0.0, -arc * 0.45)
		left_hand.position = hand_pos
		if new_mag != null and e > 0.05:
			new_mag.visible = true
			new_mag.position = left_hand.position - _grip_offset()
			new_mag.rotation = insert_start_rot * _ez(e)
		# 接近插入起点时,手部逐渐贴合弹鼓实际旋转后的抓握点,消除阶段切换跳变
		if new_mag != null and e > 0.85:
			left_hand.position = hand_pos.lerp(_grip_on(new_mag), _ez((e - 0.85) / 0.15))


func _drum_insert_start() -> Dictionary:
	var side := _side_sign()
	return {
		"pos": mag_base + Vector3(side * 0.12, -0.075, 0.02),
		"rot": Vector3(0.0, 0.12, side * 0.55),
	}


func _drum_insert_pose(p: float) -> Dictionary:
	var start_pose := _drum_insert_start()
	var side := _side_sign()
	var align := mag_base + Vector3(side * 0.02, -0.012, 0.015)
	var align_rot := Vector3(0.0, 0.04, side * 0.18)
	var start_pos: Vector3 = start_pose.get("pos", mag_base)
	var start_rot: Vector3 = start_pose.get("rot", Vector3.ZERO)
	if p < 0.5:
		# 对位:鼓面先转正并贴近接口
		var e_align := _ez(p / 0.5)
		return { "pos": start_pos.lerp(align, e_align), "rot": start_rot.lerp(align_rot, e_align) }
	# 插入:沿接口轴向稳定推到底
	var e_push := _ez((p - 0.5) / 0.5)
	return { "pos": align.lerp(mag_base, e_push), "rot": align_rot * (1.0 - e_push) }


func _update_drum_insert(_dt: float) -> void:
	var p := stage_p
	if new_mag != null:
		var pose := _drum_insert_pose(p)
		new_mag.position = pose.get("pos", mag_base)
		new_mag.rotation = pose.get("rot", Vector3.ZERO)
		new_mag.visible = true
	if left_hand != null and new_mag != null:
		var contact := float(cfg.get("insert_contact", 0.30))
		if p < contact:
			left_hand.position = _grip_on(new_mag)
		else:
			left_hand.position = _grip_on(new_mag) + Vector3(0.0, sin(p * PI) * 0.004, 0.0)
	if not ammo_committed and p >= float(cfg.get("drum_commit", 0.58)):
		_commit_special_ammo("drum")
	if p >= float(cfg.get("swap_point", 0.88)) and not insert_swapped:
		_swap_new_mag()


func _update_drum_lock(_dt: float) -> void:
	var p := stage_p
	var side := _side_sign()
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		# 锁定:鼓体做一次短促扭转后归零,呈现“旋入固定/锁定”收尾,且与插入末态无跳变
		mag.rotation = mag_base_rot + Vector3(0.0, 0.0, side * sin(p * PI) * 0.03)
	if left_hand != null:
		var grip := _mag_grip_pos(mag_base)
		left_hand.position = grip + Vector3(sin(p * PI) * 0.008, 0.0, 0.0)
	if p >= float(cfg.get("seal_point", 0.68)):
		_seal_special("drum")


# ============================================================
# 弹链轻机枪专用流程(开盖 → 抽旧链/旧箱 → 取新箱 → 新链入槽 → 关盖闭锁)
# ============================================================

func _cover_latch_pos() -> Vector3:
	if cover != null and is_instance_valid(cover) and cover_latch != null:
		return cover.transform * cover_latch.position
	return Vector3(0.0, 0.08, -0.18)


func _update_cover_open() -> void:
	var p := stage_p
	# 开盖阶段旧弹链箱/弹链必须保持装填姿态:清掉上次中断可能残留的位移
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		mag.rotation = mag_base_rot
	if belt != null:
		belt.position = belt_base
		belt.rotation = belt_base_rot
		# 旧弹链按当前剩余弹药显示真实链节长度;空仓时受弹机内无残链
		_set_belt_fill(belt, float(_g().ammo) / maxf(1.0, float(_g().mag_cap)))
	if cover != null:
		var open_at := float(cfg.get("cover_open_at", 0.10))
		var span := maxf(float(cfg.get("cover_open_span", 0.74)), 0.01)
		var k := _ez(clampf((p - open_at) / span, 0.0, 1.0))
		cover.rotation = cover_base + Vector3(float(cfg.get("cover_angle", 0.85)) * k, 0.0, 0.0)
	if left_hand != null:
		var latch := _cover_latch_pos()
		if p < 0.18:
			# 先伸手抓住供弹盖锁扣:从弹链箱同侧绕出弧线,避免直穿机匣
			var e := _ez(p / 0.18)
			var arc := Vector3(_side_sign() * sin(e * PI) * 0.04, sin(e * PI) * 0.025, 0.0)
			left_hand.position = hand_rest.lerp(latch + Vector3(0.0, -0.02, 0.0), e) + arc
		elif started_empty and p >= 0.55:
			# 空仓换弹的标志性动作:开盖后拨一下受弹口,确认没有滞留空链节/断链
			# (实机操作规范,用户明确要求)。战术换弹膛内仍有弹,跳过检查直接拆箱。
			var hold := latch + Vector3(0.0, -0.025, 0.0)
			var port := Vector3(0.0, -0.01, -0.16)
			if group != null and group.has_meta("feed_port"):
				var fp: Node3D = group.get_meta("feed_port")
				port = fp.position if fp != null else port
			var chk := _ez(clampf((p - 0.55) / 0.30, 0.0, 1.0))
			left_hand.position = hold.lerp(port + Vector3(_side_sign() * 0.03, -0.02, 0.0), chk) \
				+ Vector3(0.0, 0.0, sin(chk * PI) * 0.012)
			if p > 0.72 and not _stage_event_done:
				_stage_event_done = true
				AudioSys.reload_action("mag_out", 1.18)
		else:
			# 抓扣随供弹盖一起抬起,手腕与机盖保持真实联动
			left_hand.position = latch + Vector3(0.0, -0.025, 0.0)
	if p >= 0.86 and not _stage_event_done:
		_stage_event_done = true
		_impulse(0.003, 0.4)
		_camera_kick(0.45, 0.35)


func _belt_remove_pose(p: float) -> Dictionary:
	var e := _ez(p)
	var side := _side_sign()
	return {
		"pos": mag_base + Vector3(side * e * 0.15, -e * 0.055, sin(e * PI) * 0.03),
		"rot": Vector3(e * 0.08, e * 0.05, side * e * 0.35),
	}


func _update_belt_out() -> void:
	var p := stage_p
	var retain := _tac_retain_active()
	# 前 22% 时间用于手从供弹盖锁扣移到弹链箱提手;箱体在此之后才开始脱出,
	# 保证“先抓稳再拆”,不会出现手瞬移或弹链箱自己飞走。
	var move_p := clampf((p - 0.22) / 0.78, 0.0, 1.0)
	if mag != null:
		var pose := _belt_remove_pose(move_p)
		mag.position = pose.get("pos", mag_base)
		mag.rotation = pose.get("rot", Vector3.ZERO)
		# 旧弹链随箱体抽出时自然下坠,链节仍保持与箱口连接
		if belt != null:
			var e := _ez(move_p)
			belt.position = belt_base + Vector3(_side_sign() * 0.012, -sin(e * PI) * 0.018, 0.01 * e)
		if move_p >= float(cfg.get("drop_point", 0.62)) and not old_mag_dropped and not retain:
			_drop_old_mag()
			_impulse(0.006, 0.55)
			_camera_kick(0.55, 0.4)
	if left_hand != null:
		if old_mag_dropped:
			var dp := float(cfg.get("drop_point", 0.62))
			var tail := clampf((move_p - dp) / (1.0 - dp), 0.0, 1.0)
			left_hand.position = hand_after_remove.lerp(hand_after_remove + Vector3(_side_sign() * 0.035, -0.045, 0.018), _ez(tail))
		elif p < 0.28 and mag != null:
			var from := _cover_latch_pos() + Vector3(0.0, -0.02, 0.0)
			left_hand.position = from.lerp(_grip_on(mag), _ez(p / 0.28))
		elif mag != null:
			left_hand.position = _grip_on(mag)
	hand_after_remove = left_hand.position if left_hand != null else hand_grip_anchor


func _update_belt_fetch() -> void:
	if left_hand == null:
		return
	var p := stage_p
	var pocket := _chest_pocket()
	var fetch_start := hand_after_remove
	var side := _side_sign()
	if p < 0.42:
		var e := _ez(p / 0.42)
		var arc := sin(e * PI) * 0.07
		left_hand.position = fetch_start.lerp(pocket, e) + Vector3(side * arc * 0.5, 0.0, -arc * 0.45)
	else:
		var e := _ez((p - 0.42) / 0.58)
		var target := insert_start + _grip_offset()
		var arc := sin(e * PI) * float(cfg.get("hand_arc", 0.09))
		var hand_pos := pocket.lerp(target, e) + Vector3(side * arc * 0.55, 0.0, -arc * 0.45)
		left_hand.position = hand_pos
		if new_mag != null and e > 0.05:
			new_mag.visible = true
			new_mag.position = left_hand.position - _grip_offset()
			new_mag.rotation = insert_start_rot * _ez(e)
		if new_belt != null and e > 0.05:
			new_belt.visible = true
			new_belt.position = belt_base + Vector3(side * 0.07, 0.012, 0.012)
			new_belt.rotation = belt_base_rot + Vector3(0.0, 0.0, side * 0.35)
			_set_belt_fill(new_belt, _planned_belt_fill())
		# 接近插入起点时,手部逐渐贴合弹链箱实际旋转后的抓握点,消除阶段切换跳变
		if new_mag != null and e > 0.85:
			left_hand.position = hand_pos.lerp(_grip_on(new_mag), _ez((e - 0.85) / 0.15))


func _belt_insert_start() -> Dictionary:
	var side := _side_sign()
	return {
		"pos": mag_base + Vector3(side * 0.16, -0.08, 0.02),
		"rot": Vector3(0.08, 0.08, side * 0.4),
	}


func _belt_insert_pose(p: float) -> Dictionary:
	var start_pose := _belt_insert_start()
	var side := _side_sign()
	var align := mag_base + Vector3(side * 0.015, -0.01, 0.015)
	var align_rot := Vector3(0.0, 0.02, side * 0.12)
	var start_pos: Vector3 = start_pose.get("pos", mag_base)
	var start_rot: Vector3 = start_pose.get("rot", Vector3.ZERO)
	if p < 0.45:
		var e_align := _ez(p / 0.45)
		return { "pos": start_pos.lerp(align, e_align), "rot": start_rot.lerp(align_rot, e_align) }
	var e_push := _ez((p - 0.45) / 0.55)
	return { "pos": align.lerp(mag_base, e_push), "rot": align_rot * (1.0 - e_push) }


func _update_belt_in(_dt: float) -> void:
	var p := stage_p
	var side := _side_sign()
	if new_mag != null:
		var pose := _belt_insert_pose(p)
		new_mag.position = pose.get("pos", mag_base)
		new_mag.rotation = pose.get("rot", Vector3.ZERO)
		new_mag.visible = true
	# 弹链入槽关键表现:箱体先对位,弹链尾随后从外侧滑入供弹口,
	# 链节保持连续,不出现“弹链凭空消失/瞬移进机匣”。
	if new_belt != null:
		var e := _ez(p)
		new_belt.position = belt_base + Vector3(side * 0.07 * (1.0 - e), 0.012 * (1.0 - e), 0.012 * (1.0 - e))
		new_belt.rotation = belt_base_rot + Vector3(0.0, 0.0, side * 0.35 * (1.0 - e))
	if left_hand != null and new_mag != null:
		var contact := float(cfg.get("insert_contact", 0.30))
		if p < contact:
			left_hand.position = _grip_on(new_mag)
		else:
			left_hand.position = _grip_on(new_mag) + Vector3(0.0, sin(p * PI) * 0.004, 0.0)
	if not ammo_committed and p >= float(cfg.get("belt_commit", 0.58)):
		_commit_special_ammo("belt")
	if p >= float(cfg.get("swap_point", 0.88)) and not insert_swapped:
		_swap_new_mag()


func _update_cover_close(dt: float) -> void:
	var p := stage_p
	if cover != null:
		var close_at := float(cfg.get("cover_close_at", 0.08))
		var span := maxf(float(cfg.get("cover_close_span", 0.76)), 0.01)
		var k := _ez(clampf((p - close_at) / span, 0.0, 1.0))
		cover.rotation = cover_base + Vector3(float(cfg.get("cover_angle", 1.05)) * (1.0 - k), 0.0, 0.0)
	if left_hand != null:
		var latch := _cover_latch_pos()
		if p < 0.16:
			left_hand.position = left_hand.position.lerp(latch + Vector3(0.0, -0.02, 0.0), 1.0 - exp(-12.0 * dt))
		else:
			# 手压着供弹盖锁扣下落,闭锁瞬间有明确的“拍实”位移
			left_hand.position = latch + Vector3(0.0, -0.025, sin(p * PI) * 0.006)
	if p >= float(cfg.get("cover_seal", 0.82)):
		_seal_special("belt")


# ============================================================
# 弹鼓/弹链通用:供弹具入位后的弹药同步与闭锁
# ============================================================

## 供弹具到达“合理换弹节点”才更新弹药:余弹先归还备弹,再扣除整鼓/整箱。
func _commit_special_ammo(kind: String) -> void:
	if ammo_committed:
		return
	ammo_committed = true
	_g().reserve += _g().ammo
	var take := mini(_g().mag_cap, _g().reserve)
	_g().ammo = take
	_g().reserve -= take
	# 机械音效与弹药更新严格同帧:入鼓/弹链入槽
	var pitch := _mech_pitch()
	if kind == "drum":
		AudioSys.mech("drum_insert", pitch)
	else:
		AudioSys.mech(_belt_action("belt_in"), pitch)
	var imp: float = float(cfg.get("insert_impact", 0.012))
	_impulse(imp, 0.85)
	_camera_kick(0.8, 0.55)


## 弹鼓锁定 / 供弹盖闭锁:此时换弹才真正完成,允许开火打断并保留新弹药。
func _seal_special(kind: String) -> void:
	if _stage_event_done:
		return
	_stage_event_done = true
	if not ammo_committed:
		_commit_special_ammo(kind)
	committed = true
	var pitch := _mech_pitch()
	if kind == "drum":
		AudioSys.mech("drum_lock", pitch)
	else:
		AudioSys.mech(_belt_action("belt_lock"), pitch)
	var imp: float = float(cfg.get("insert_impact", 0.012))
	_impulse(imp * 0.8, 0.9)
	_camera_kick(0.75, 0.5)


## 新供弹具完全入位:隐藏手中的复制体,恢复枪上实体供弹具(含弹链尾)。
func _swap_new_mag() -> void:
	if insert_swapped:
		return
	insert_swapped = true
	if new_mag != null:
		new_mag.visible = false
	if new_belt != null:
		new_belt.visible = false
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		mag.rotation = mag_base_rot
	if belt != null:
		belt.visible = true
		belt.position = belt_base
		belt.rotation = belt_base_rot
		_set_belt_fill(belt, float(_g().ammo) / maxf(1.0, float(_g().mag_cap)))


func _chamber_curve(p: float) -> float:
	# COD 式枪机操作:快拉 → 短暂保持 → 干净送回,避免正弦对称造成的"机械摆"
	if p < 0.32:
		return _ez(p / 0.32)
	if p < 0.56:
		return 1.0
	return 1.0 - _ez((p - 0.56) / 0.44)


func _update_chamber(dt: float) -> void:
	var p := stage_p
	var amp: float = float(cfg.get("chamber_amp", 0.045))
	var curve := _chamber_curve(p)
	match String(cfg.get("chamber_style", "pull")):
		"ar_release":
			# AR 系空仓:左手拍左侧空挂释放钮,枪机自行复进(不拉拉机柄)
			if left_hand != null:
				var tap := Vector3(-0.026, -0.032, -0.05)
				var e := _ez(minf(p * 1.5, 1.0))
				left_hand.position = _chamber_hand_start.lerp(tap, e) + Vector3(0.0, sin(e * PI) * 0.012, 0.0)
				if p > 0.45:
					left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-11.0 * dt))
		"bullpup_tap":
			# AUG/FAMAS 空仓:左手绕到枪托后部拍空挂释放钮,枪身轻微前冲
			if left_hand != null:
				var tap := (bolt.position + Vector3(-0.022, 0.02, 0.04)) if bolt != null else Vector3(-0.022, -0.04, 0.18)
				var e := _ez(minf(p * 1.5, 1.0))
				left_hand.position = _chamber_hand_start.lerp(tap, e) + Vector3(sin(e * PI) * 0.015, 0.0, 0.0)
				if p > 0.42:
					left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-11.0 * dt))
		"hk_slap":
			# MP5 空仓:H&K 经典拍拉机柄,左手向下拍击前部拉机柄后收回
			if bolt != null:
				bolt.position.z = bolt_base.z + curve * amp
			if left_hand != null and bolt != null:
				var side := 1.0 if bolt_base.x >= 0.0 else -1.0
				var target := bolt.position + Vector3(side * 0.02, 0.055, 0.0)
				var e := _ez(minf(p * 1.4, 1.0))
				left_hand.position = _chamber_hand_start.lerp(target, e) + Vector3(0.0, -sin(e * PI) * 0.018, 0.0)
				if p > 0.58:
					left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-11.0 * dt))
		"g3_pull":
			# G3 空仓:左手抓住左前折叠拉机柄,向后长拉再送开
			if bolt != null:
				bolt.position.z = bolt_base.z + curve * amp * 1.15
			if left_hand != null and bolt != null:
				var side := 1.0 if bolt_base.x >= 0.0 else -1.0
				var target := bolt.position + Vector3(side * 0.018, 0.025, 0.0)
				var e := _ez(minf(p * 1.3, 1.0))
				left_hand.position = _chamber_hand_start.lerp(target, e) + Vector3(0.0, sin(e * PI) * 0.01, 0.0)
				if p > 0.56:
					left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-10.0 * dt))
		"right_tap":
			# M14/M1A/SKS/FAL 空仓:右手短暂离开握把,拍右侧枪机柄后回握把
			if right_hand != null:
				var tap := (bolt.position + Vector3(0.022, 0.022, 0.01)) if bolt != null else Vector3(0.024, -0.03, 0.02)
				var e := _ez(minf(p * 1.5, 1.0))
				right_hand.position = right_base.lerp(tap, e) + Vector3(0.0, sin(e * PI) * 0.012, 0.0)
				if p > 0.46:
					right_hand.position = right_hand.position.lerp(right_base, 1.0 - exp(-11.0 * dt))
			if left_hand != null:
				left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-9.0 * dt))
		"p90_charge":
			# P90 空仓:左手抓左后侧拉机柄向后拉,再松手复位(双侧拉机柄随枪机一起动)
			if bolt != null:
				bolt.position.z = bolt_base.z + curve * amp * 1.25
			if left_hand != null and bolt != null:
				var side := 1.0 if bolt_base.x >= 0.0 else -1.0
				var target := bolt.position + Vector3(side * 0.02, 0.02, 0.0)
				var e := _ez(minf(p * 1.4, 1.0))
				left_hand.position = _chamber_hand_start.lerp(target, e) + Vector3(0.0, sin(e * PI) * 0.01, 0.0)
				if p > 0.52:
					left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-11.0 * dt))
		"pull", "pull_heavy", "pull_ak", "release":
			if bolt != null:
				bolt.position = bolt_base + Vector3(0.0, 0.0, curve * amp)
				var side := 1.0 if bolt_base.x >= 0.0 else -1.0
				if side > 0.0:
					# 右侧拉机柄:右手离握把抓柄,跟随"快拉 → 保持 → 送回"
					if p < 0.74 and right_hand != null:
						right_hand.position = bolt.position + Vector3(side * 0.018, 0.02, 0.0)
						right_hand.rotation = right_rot_base + Vector3(-0.5, 0.2, 0.0)
					elif right_hand != null:
						right_hand.position = right_hand.position.lerp(right_base, 1.0 - exp(-11.0 * dt))
				else:
					# 左侧拉机柄(MP5/SCAR/UMP 等):左手离护木抓柄,右手始终握把
					if p < 0.74 and left_hand != null:
						left_hand.position = bolt.position + Vector3(side * 0.018, 0.02, 0.0)
						_rot_slerp(left_hand, HAND_GRIP_ROT, 1.0 - exp(-13.0 * dt))
					elif left_hand != null:
						left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-9.0 * dt))
					if right_hand != null:
						right_hand.position = right_hand.position.lerp(right_base, 1.0 - exp(-11.0 * dt))
			if left_hand != null and p > 0.3 and (bolt == null or bolt_base.x >= 0.0):
				left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-9.0 * dt))
		"slide":
			if slide != null:
				slide.position.z = slide_base_z + curve * amp
			if left_hand != null:
				# 手枪空仓上膛:从弹匣抓握点沿低弧线移到套筒后部下方,
				# 手腕不越过套筒顶部,避免手臂突然上甩穿模。
				var target := Vector3(-0.018, slide_base.y - 0.012, slide.position.z + 0.045) if slide != null else _chamber_hand_start
				var e := _ez(minf(p * 1.25, 1.0))
				var arc := Vector3(0.0, sin(e * PI) * 0.012, 0.0)
				left_hand.position = _chamber_hand_start.lerp(target, e) + arc
		"belt_slap":
			if mag != null:
				mag.position = mag_base + Vector3(0.0, sin(p * PI) * 0.022, 0.0)
			if left_hand != null:
				left_hand.position = left_hand.position.lerp(mag_base + Vector3(0.0, -0.05, 0.06), 1.0 - exp(-12.0 * dt))
		"top_slap":
			if mag != null:
				mag.position = mag_base + Vector3(0.0, sin(p * PI) * 0.018, 0.0)
			if left_hand != null:
				left_hand.position = left_hand.position.lerp(mag_base + Vector3(0.0, 0.035, 0.02), 1.0 - exp(-12.0 * dt))
		"bolt_cycle":
			# 完整枪栓循环由 Gun.bolt_t 播放;这里右手跟栓走
			pass
		_:
			if left_hand != null:
				left_hand.position = left_hand.position.lerp(hand_rest, _ez(p))
	_update_hand_rotation(dt)


func _start_chamber() -> void:
	if chamber_started:
		return
	# 空仓换弹才允许枪机/套筒/拉机柄动作;战术换弹(膛内仍有余弹)绝不触发
	if not started_empty:
		return
	chamber_started = true
	var style: String = String(cfg.get("chamber_style", "pull"))
	if style == "bolt_cycle":
		if bolt != null and _g().bolt_t <= 0.0:
			_g().bolt_t = 0.0001
			_g()._bolt_snd = false
		elif _g().bolt_t <= 0.0:
			_g().bolt_t = 0.0001
	elif style == "slide":
		AudioSys.reload_action(String(cfg.get("bolt_snd", "slide_release")))
	elif style in ["top_slap", "belt_slap"]:
		AudioSys.reload_action(String(cfg.get("mag_in_snd", "mag_in")))
	else:
		AudioSys.reload_action(String(cfg.get("bolt_snd", "bolt_cycle")))
	var imp: float = float(cfg.get("chamber_impact", 0.011))
	_impulse(imp * 0.7, 0.9)
	_camera_kick(0.8, 0.65)


func _reset_chamber_part() -> void:
	if bolt != null:
		bolt.position = bolt_base
	if slide != null:
		slide.position = slide_base


func _finish_reload() -> void:
	active = false
	_g().reloading = false
	_g().reload_t = time
	state = State.FINISH
	finish_t = 0.0
	finish_dur = float(cfg.get("finish_dur", 0.26))


# ============================================================
# 取消 / 收尾 / 待机
# ============================================================

func _restore_mag_if_valid() -> void:
	if mag == null:
		if rocket != null:
			rocket.visible = committed or not old_mag_dropped
		if new_rocket != null:
			new_rocket.visible = false
		return
	if cfg.get("mag", "down") == "none":
		return
	if committed or not old_mag_dropped:
		# 只恢复可见性;位置由 CANCEL 状态的 _recover_anim_parts 平滑拉回,禁止瞬移
		mag.visible = true
	if new_mag != null:
		new_mag.visible = false


func _snap_mag_to_base() -> void:
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		mag.rotation = mag_base_rot
	if belt != null:
		belt.visible = true
		belt.position = belt_base
		belt.rotation = belt_base_rot
		_set_belt_fill(belt, float(_g().ammo) / maxf(1.0, float(_g().mag_cap)))
	if new_mag != null:
		new_mag.visible = false
	if new_belt != null:
		new_belt.visible = false
	if cover != null:
		cover.visible = true
		cover.rotation = cover_base
	if rocket != null:
		rocket.visible = true
		rocket.position = rocket_base
		rocket.rotation = Vector3.ZERO
	if new_rocket != null:
		new_rocket.visible = false


func _snap_rig_to_base() -> void:
	_snap_mag_to_base()
	if bolt != null:
		bolt.position = bolt_base
	if slide != null:
		slide.position = slide_base
	if pump != null:
		pump.position = pump_base
	if revolver_crane != null:
		revolver_crane.rotation = revolver_crane_base
	if revolver_cylinder != null:
		revolver_cylinder.position = revolver_cyl_pos_base
		var chamber_count: int = _g()._chamber_loaded.size()
		if chamber_count > 0:
			var idx_rot := float(_g()._chamber_index) * TAU / float(chamber_count)
			revolver_cylinder.rotation = revolver_cyl_base + Vector3(0.0, 0.0, idx_rot)
			_g()._cyl_from = revolver_cylinder.rotation.z
			_g()._cyl_to = revolver_cylinder.rotation.z
		else:
			revolver_cylinder.rotation = revolver_cyl_base
	if revolver_hammer != null:
		revolver_hammer.rotation = Vector3.ZERO
	revolver_open = 0.0
	if left_hand != null:
		left_hand.position = hand_rest
		left_hand.rotation = hand_rest_rot
	if right_hand != null:
		right_hand.position = right_base
		right_hand.rotation = right_rot_base


func _update_cancel(dt: float) -> void:
	cancel_t += dt
	var k := clampf(cancel_t / 0.22, 0.0, 1.0)
	_update_pose(0.0, dt)
	_update_camera(0.0, dt)
	_recover_hands(dt)
	_recover_anim_parts(dt)
	if k >= 1.0:
		state = State.IDLE


func _update_finish(dt: float) -> void:
	finish_t += dt
	_update_pose(0.0, dt)
	_update_camera(0.0, dt)
	_recover_hands(dt)
	_recover_anim_parts(dt)
	if finish_t >= finish_dur:
		state = State.IDLE


func _update_idle(dt: float) -> void:
	_update_pose(0.0, dt)
	_update_camera(0.0, dt)
	_recover_hands(dt)
	_recover_anim_parts(dt)
	if mag != null and not mag.visible:
		mag.visible = true
	if belt != null:
		# 待机/换弹完成后的弹链长度始终与实际弹药同步
		_set_belt_fill(belt, float(_g().ammo) / maxf(1.0, float(_g().mag_cap)))
	if new_mag != null:
		new_mag.visible = false
	if new_rocket != null:
		new_rocket.visible = false
	if speedloader_mesh != null:
		speedloader_mesh.visible = false
	if _g().def.get("revolver") == true:
		_g()._sync_revolver_chambers()


func _recover_anim_parts(dt: float) -> void:
	var k := 1.0 - exp(-11.0 * dt)
	if mag != null:
		mag.position = mag.position.lerp(mag_base, k)
		mag.rotation = mag.rotation.lerp(mag_base_rot, k)
		mag.visible = true
	if belt != null:
		belt.position = belt.position.lerp(belt_base, k)
		belt.rotation = belt.rotation.lerp(belt_base_rot, k)
		belt.visible = true
	if new_mag != null:
		new_mag.visible = false
	if new_belt != null:
		new_belt.position = new_belt.position.lerp(belt_base, k)
		new_belt.rotation = new_belt.rotation.lerp(belt_base_rot, k)
		new_belt.visible = false
	if cover != null:
		cover.rotation = cover.rotation.lerp(cover_base, k)
		cover.visible = true
	if bolt != null:
		bolt.position = bolt.position.lerp(bolt_base, k)
	if slide != null:
		slide.position = slide.position.lerp(slide_base, k)
	if pump != null:
		pump.position = pump.position.lerp(pump_base, k)
	if rocket != null:
		rocket.position = rocket.position.lerp(rocket_base, k)
		rocket.rotation = rocket.rotation.lerp(Vector3.ZERO, k)
		rocket.visible = true
	if new_rocket != null:
		new_rocket.visible = false
	# 左轮:取消/收尾时弹巢连续平移回闭锁位,速度与换弹姿态恢复一致
	if revolver_crane != null:
		revolver_crane.rotation = revolver_crane.rotation.lerp(revolver_crane_base, k)
		revolver_open = Utils.damp(revolver_open, 0.0, 10.0, dt)
	if revolver_cylinder != null:
		revolver_cylinder.position = revolver_cylinder.position.lerp(revolver_cyl_pos_base, k)
	if revolver_hammer != null:
		revolver_hammer.rotation = revolver_hammer.rotation.lerp(Vector3.ZERO, k)
	if speedloader_mesh != null:
		speedloader_mesh.visible = false


func _recover_hands(dt: float) -> void:
	if left_hand != null:
		left_hand.position = left_hand.position.lerp(hand_rest, 1.0 - exp(-12.0 * dt))
		_rot_slerp(left_hand, hand_rest_rot, 1.0 - exp(-12.0 * dt))
	if right_hand != null:
		right_hand.position = right_hand.position.lerp(right_base, 1.0 - exp(-12.0 * dt))
		_rot_slerp(right_hand, right_rot_base, 1.0 - exp(-12.0 * dt))
	if _g().grip_amt != 0.0:
		_g().grip_amt = maxf(0.0, _g().grip_amt - dt * 8.0)


# ============================================================
# 姿态 / 惯性 / 镜头
# ============================================================

func _pose_envelope() -> float:
	var t01 := clampf(time / maxf(total, 0.0001), 0.0, 1.0)
	var pin := maxf(0.05, float(cfg.get("pose_in", 0.14)))
	var pout := maxf(0.05, float(cfg.get("pose_out", 0.16)))
	var a := _ez(minf(t01 / pin, 1.0))
	var b := _ez(clampf((1.0 - t01) / pout, 0.0, 1.0))
	return a * b


func _update_pose(env: float, dt: float) -> void:
	var inertia: float = float(cfg.get("inertia_strength", 1.0))
	var pose_pos_cfg: Vector3 = cfg.get("pose_pos", Vector3.ZERO)
	var pose_rot_cfg: Vector3 = cfg.get("pose_rot", Vector3.ZERO)
	# COD 式区分:战术换弹枪身动作收敛,空仓换弹展示完整枪机操作
	var pose_scale: float = float(cfg.get("empty_pose_scale", 1.0)) if started_empty else float(cfg.get("tac_pose_scale", 0.82))
	pose_pos_cfg *= inertia * pose_scale
	pose_rot_cfg *= inertia * pose_scale
	var amp: float = float(cfg.get("sway_amp", 0.004)) * inertia
	var freq: float = float(cfg.get("sway_freq", 1.2))
	var target_pos := pose_pos_cfg * env
	var target_rot := pose_rot_cfg * env
	# 惯性微动:像真人换弹时枪身被手腕带动,而不是固定姿势
	if env > 0.001:
		var s1 := sin(time * freq * TAU)
		var s2 := cos(time * freq * 0.73 * TAU + 0.8)
		var s3 := sin(time * freq * 0.51 * TAU + 1.7)
		target_pos += Vector3(s1 * amp, s2 * amp * 0.7, s3 * amp * 0.5) * env
		target_rot += Vector3(s2 * amp * 4.0, s3 * amp * 3.0, s1 * amp * 3.0) * env
	# ADS:开镜时换弹姿态向正常持枪姿态让位,但仍保持换弹动作连续性
	var state_blend := 1.0
	if _g().ads_amount > 0.01:
		state_blend = lerpf(1.0, float(cfg.get("ads_keep", 0.55)), _g().ads_amount)
	# 奔跑换弹:不再把换弹姿态压到“奔跑持枪低位”;
	# 换弹期间播放与走路一致的完整换弹动画,奔跑速度保持由 Player/Gun 控制,
	# 换弹结束后的 IDLE 姿态会自然回落,继续维持奔跑持枪低位。
	target_pos *= state_blend
	target_rot *= state_blend
	var pose_damp: float = float(cfg.get("pose_damp", 11.0))
	pose_pos = pose_pos.lerp(target_pos, 1.0 - exp(-pose_damp * dt))
	pose_rot = pose_rot.lerp(target_rot, 1.0 - exp(-pose_damp * dt))
	# 冲击弹簧:插入/枪机动作的短促反馈,快速衰减
	var idamp: float = float(cfg.get("impact_damp", 10.0))
	impulse_pos = impulse_pos.lerp(Vector3.ZERO, 1.0 - exp(-idamp * dt))
	impulse_rot = impulse_rot.lerp(Vector3.ZERO, 1.0 - exp(-idamp * dt))
	_g().reload_pose = pose_pos + impulse_pos
	_g().reload_rot = pose_rot + impulse_rot


func _impulse(pos_amp: float, rot_amp: float) -> void:
	var inertia: float = float(cfg.get("inertia_strength", 1.0))
	impulse_pos += Vector3(Utils.rand(-0.2, 0.2) * pos_amp, -pos_amp * 0.55, pos_amp * 0.75) * inertia
	# rot_amp 是"冲击强度"而非弧度:换算成 0.01~0.04 rad 级视角模型抖动,
	# 之前按 1.6 倍直接累加会产生 1 rad 级瞬间旋转,正是换弹完成前枪口上甩的来源。
	var rot_strength := rot_amp * 0.028
	impulse_rot += Vector3(rot_strength * 1.4, Utils.rand(-1.0, 1.0) * rot_strength * 0.4, Utils.rand(-1.0, 1.0) * rot_strength * 0.35) * inertia


func _update_camera(env: float, dt: float) -> void:
	if player == null:
		return
	var strength: float = float(cfg.get("cam_strength", 1.0))
	var damp: float = float(cfg.get("cam_damp", 9.0))
	var freq: float = float(cfg.get("cam_freq", 1.2))
	var sway: float = float(cfg.get("cam_sway", 0.0011)) * strength
	# 持续目标接近 0:换弹期间镜头有极轻微呼吸式跟随,结束后自动归零
	var tp := sin(time * freq * TAU) * sway * env
	var ty := cos(time * freq * 0.61 * TAU + 0.5) * sway * 0.7 * env
	var roll_target := sin(time * freq * 0.43 * TAU + 1.1) * sway * 0.35 * env
	player.reload_cam_pitch = Utils.damp(player.reload_cam_pitch, tp, damp, dt)
	player.reload_cam_yaw = Utils.damp(player.reload_cam_yaw, ty, damp, dt)
	player.reload_cam_roll = Utils.damp(player.reload_cam_roll, roll_target, damp, dt)


func _camera_kick(amount: float, yaw_amount: float) -> void:
	if player == null:
		return
	var strength: float = float(cfg.get("cam_strength", 1.0))
	var pitch := -amount * 0.0045 * strength
	player.reload_cam_pitch += pitch
	player.reload_cam_yaw += Utils.rand(-yaw_amount, yaw_amount) * 0.0032 * strength
	player.reload_cam_roll += Utils.rand(-yaw_amount, yaw_amount) * 0.0016 * strength


# ============================================================
# 弹匣 / 手部路径
# ============================================================

func _ez(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## 手部旋转球面插值:替代 Vector3.lerp,避免欧拉角直接线性插值造成换弹时手肘/手腕扭曲。
func _rot_slerp(n: Node3D, target_rot: Vector3, t: float) -> void:
	if n == null:
		return
	var k := clampf(t, 0.0, 1.0)
	var target_q := Quaternion.from_euler(target_rot)
	n.quaternion = n.quaternion.slerp(target_q, k).normalized()


func _chest_pocket() -> Vector3:
	# 每把枪的携行具位置由换弹签名决定,保证“旧匣收哪里”每把枪都不一样
	var def_pocket := Vector3(0.02, -0.20, 0.10)
	return cfg.get("pouch", def_pocket) as Vector3


func _grip_offset() -> Vector3:
	match String(cfg.get("mag", "down")):
		"none":
			return Vector3.ZERO
		"side":
			return GRIP_SIDE
		"drum":
			return GRIP_DRUM
		"belt":
			return GRIP_BELT
		"top":
			return GRIP_TOP
		"p90":
			return Vector3(0.0, -0.055, 0.018)
		"pistol":
			return GRIP_PISTOL
	return GRIP_DOWN


## 供弹具局部抓握点变换到枪械空间:弹鼓/弹链箱旋转时,手腕仍贴合实际抓握处。
func _grip_on(part: Node3D) -> Vector3:
	if part == null:
		return hand_grip_anchor
	return part.transform * _grip_offset()


## 按剩余弹药比例显示旧弹链的实际链节长度;新弹链始终满链。
func _set_belt_fill(b: Node3D, ratio: float) -> void:
	if b == null:
		return
	var n := b.get_child_count()
	var want := 0
	if ratio > 0.01:
		want = clampi(int(ceil(ratio * float(n))), 1, n)
	for i in n:
		var c := b.get_child(i)
		if c is Node3D:
			(c as Node3D).visible = i < want


## 新弹链装填后预计的弹药比例(备弹不足时新链也按实际可装量显示,不虚标满链)。
func _planned_belt_fill() -> float:
	return clampf(float(_g().ammo + _g().reserve) / maxf(1.0, float(_g().mag_cap)), 0.0, 1.0)


func _mag_grip_pos(base_pos: Vector3) -> Vector3:
	if cfg.get("mag", "down") == "none":
		return _g()._hand_l1
	return base_pos + _grip_offset()


func _drop_old_mag() -> void:
	if old_mag_dropped:
		return
	old_mag_dropped = true
	hand_after_remove = left_hand.position if left_hand != null else hand_grip_anchor
	if mag != null and mag.visible:
		mag.visible = false
		_g()._drop_mag()
	if rocket != null:
		rocket.visible = false


func _mag_remove_pose(p: float) -> Dictionary:
	var e := _ez(p)
	var dist: float = float(cfg.get("drop_dist", 0.16))
	var rot: float = float(cfg.get("mag_rot", 0.13))
	var rb: Vector3 = cfg.get("remove_bias", Vector3.ZERO)
	var rr: Vector3 = cfg.get("remove_rot_bias", Vector3.ZERO)
	match String(cfg.get("mag", "down")):
		"side":
			# AK/SVD 前挂后卡:向下 + 沿枪口方向前送拔出,不再横向右甩;每把 AK 系再叠加自身签名
			return { "pos": mag_base + Vector3(0.0, -e * 0.10, -e * 0.06) + rb * e, "rot": Vector3(e * 0.35, 0.0, 0.0) + rr * e }
		"drum":
			return { "pos": mag_base + Vector3(0.0, -e * 0.09, 0.0) + rb * e, "rot": Vector3(0.0, 0.0, e * 0.85) + rr * e }
		"belt":
			var belt_side := -1.0 if mag_base.x < -0.01 else 1.0
			return { "pos": mag_base + Vector3(belt_side * e * 0.05, -e * 0.08, 0.0) + rb * e, "rot": Vector3(0.0, 0.0, e * 0.5) + rr * e }
		"p90":
			# P90:先按前端两侧弹匣扣,弹匣整体向后方抽出(前卡头先脱出前卡槽),再离枪
			return { "pos": mag_base + Vector3(0.0, e * 0.10, e * 0.10) + rb * e, "rot": Vector3(-e * 0.22, 0.0, sin(e * PI) * 0.04) + rr * e }
		"top":
			return { "pos": mag_base + Vector3(0.0, e * 0.13, 0.0) + rb * e, "rot": Vector3(0.0, 0.0, sin(e * PI * 2.0) * 0.14) + rr * e }
		"none":
			return { "pos": mag_base, "rot": mag_base_rot }
	return { "pos": mag_base + Vector3(sin(e * PI) * 0.012, -e * dist, 0.0) + rb * e, "rot": Vector3(0.0, 0.0, sin(e * PI) * rot) + rr * e }


func _mag_insert_start() -> Dictionary:
	# 从卸弹终态出发:新弹匣先出现在弹匣井外,再沿手部路径进入;每把枪的起始偏移不同
	var dist: float = float(cfg.get("drop_dist", 0.16))
	var rot: float = float(cfg.get("mag_rot", 0.13))
	var ib: Vector3 = cfg.get("insert_bias", Vector3.ZERO)
	match String(cfg.get("mag", "down")):
		"side":
			return { "pos": mag_base + Vector3(0.0, -0.10, -0.06) + ib, "rot": Vector3(0.3, 0.0, 0.0) }
		"drum":
			return { "pos": mag_base + Vector3(0.0, -0.09, 0.0) + ib, "rot": Vector3(0.0, 0.0, 0.8) }
		"belt":
			var belt_side := -1.0 if mag_base.x < -0.01 else 1.0
			return { "pos": mag_base + Vector3(belt_side * 0.05, -0.08, 0.0) + ib, "rot": Vector3(0.0, 0.0, 0.45) }
		"p90":
			return { "pos": mag_base + Vector3(0.0, 0.12, 0.10) + ib, "rot": Vector3(-0.14, 0.0, 0.02) }
		"top":
			return { "pos": mag_base + Vector3(0.0, 0.13, 0.0) + ib, "rot": Vector3(0.0, 0.0, 0.3) }
		"none":
			return { "pos": mag_base, "rot": mag_base_rot }
	return { "pos": mag_base + Vector3(0.0, -dist, 0.0) + ib, "rot": Vector3(0.0, 0.0, rot) }


func _mag_insert_pose(p: float) -> Dictionary:
	# P90 专属插匣:新匣先向后/上方进入,前端卡头先向前滑入前卡槽,后部再旋转压入弹匣扣
	if String(cfg.get("mag", "down")) == "p90":
		var start_pose := _mag_insert_start()
		var start_pos: Vector3 = start_pose.get("pos", mag_base)
		var start_rot: Vector3 = start_pose.get("rot", Vector3.ZERO)
		var align := mag_base + Vector3(0.0, 0.05, 0.0)
		var align_rot := Vector3(0.0, 0.0, 0.0)
		if p < 0.5:
			var e := _ez(p / 0.5)
			return { "pos": start_pos.lerp(align, e), "rot": start_rot.lerp(align_rot, e) }
		var e2 := _ez((p - 0.5) / 0.5)
		return { "pos": align.lerp(mag_base, e2), "rot": align_rot * (1.0 - e2) }
	var insert_pose := _mag_insert_start()
	var e := _ez(p)
	var pos: Vector3 = insert_pose.get("pos", mag_base)
	var rot: Vector3 = insert_pose.get("rot", Vector3.ZERO)
	pos = pos.lerp(mag_base, e)
	rot *= 1.0 - e
	return { "pos": pos, "rot": rot }


func _update_hand_rotation(dt: float) -> void:
	if left_hand == null:
		return
	var grip := 0.0
	if state == State.ACTIVE:
		if _g().def.get("revolver") == true:
			if stage < phase_names.size():
				match String(phase_names[stage]):
					"rv_reach", "rv_insert":
						grip = 1.0
					"rv_open", "rv_eject", "rv_fetch_loader", "rv_load_loader", "rv_close":
						grip = 0.9
					_:
						grip = 0.2
		elif _g().def.pellets > 1:
			grip = 1.0 if tube_stage == TubeStage.PUSH else (0.5 if tube_stage == TubeStage.REACH and stage_p > 0.6 else 0.15)
		elif stage < phase_names.size():
			match String(phase_names[stage]):
				"prepare":
					grip = _ez(stage_p)
				"unlock":
					grip = _ez(stage_p)
				"remove", "belt_out":
					grip = 1.0
				"stow":
					grip = 0.7
				"fetch":
					grip = 0.8 if stage_p > 0.42 else 0.2
				"insert", "belt_in":
					grip = 1.0
				"lock", "cover_open", "cover_close":
					grip = 1.0
				"chamber", "charge":
					var left_pull := bolt != null and bolt_base.x < 0.0 and String(cfg.get("chamber_style", "pull")) in ["pull", "pull_heavy", "pull_ak", "release", "g3_pull", "hk_slap", "ar_release", "bullpup_tap", "p90_charge"]
					grip = 0.9 if left_pull or String(cfg.get("chamber_style", "pull")) in ["slide", "belt_slap", "top_slap"] else 0.3
				"recover":
					grip = 0.0
	var rest_q := Quaternion.from_euler(hand_rest_rot)
	var grip_q := Quaternion.from_euler(HAND_REVOLVER_GRIP_ROT if _g().def.get("revolver") == true else HAND_GRIP_ROT)
	var target_q := rest_q.slerp(grip_q, grip).normalized()
	left_hand.quaternion = left_hand.quaternion.slerp(target_q, 1.0 - exp(-14.0 * dt)).normalized()
	_g().grip_amt = grip


func _hand_rotation_for_grip(grip: float) -> void:
	_g().grip_amt = grip


# ============================================================
# 枪机辅助手同步(泵动护木 / 枪栓柄 / 套筒)
# ============================================================

func _follow_auxiliary_hands(dt: float) -> void:
	if state == State.IDLE and not (_g().pump_t > 0.0 or _g().bolt_t > 0.0):
		return
	# 泵动护木:左手必须真正抓住护木跟随后拉/前推
	if pump != null and _g().pump_t > 0.0 and left_hand != null:
		var off: Vector3 = Vector3(0.0, 0.015, 0.0)
		if group != null and group.has_meta("pump_grip_offset"):
			off = group.get_meta("pump_grip_offset") as Vector3
		left_hand.position = pump.position + off
		_rot_slerp(left_hand, HAND_GRIP_ROT, 1.0 - exp(-16.0 * dt))
		_g().grip_amt = 1.0
	# 枪栓循环:右手离开握把跟栓柄
	if bolt != null and _g().bolt_t > 0.0 and right_hand != null:
		var off := Vector3(0.012, 0.01, 0.0)
		right_hand.position = bolt.position + off
		_rot_slerp(right_hand, right_rot_base + Vector3(-0.45, 0.25, 0.0), 1.0 - exp(-16.0 * dt))


# ============================================================
# 阶段状态查询
# ============================================================

func progress01() -> float:
	return clampf(time / maxf(total, 0.0001), 0.0, 1.0)


func stage_name() -> String:
	if state == State.IDLE:
		return "idle"
	if state == State.CANCEL:
		return "cancel"
	if state == State.FINISH:
		return "finish"
	if _g().def.get("revolver") == true:
		return String(phase_names[stage]) if stage < phase_names.size() else "rv_recover"
	if _g().def.pellets > 1:
		match tube_stage:
			TubeStage.REACH:
				return "shell_reach"
			TubeStage.PUSH:
				return "shell_push"
			_:
				return "shell_return"
	return String(phase_names[stage]) if stage < phase_names.size() else "recover"
