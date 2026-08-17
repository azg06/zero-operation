class_name WeaponReloadController extends RefCounted
## 模块化武器换弹控制器
##
## 状态机:
##   Reload Start     → 准备阶段(枪械下沉/内倾,非持枪手接近弹匣)
##   Magazine Remove  → 释放/拔出弹匣,弹匣带惯性离开,随后世界掉落
##   Magazine Insert  → 非持枪手从屏外取新弹匣,连续路径返回并推入
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


var _gun_ref: WeakRef = null
var player = null
var group: Node3D = null
var cfg: Dictionary = {}

var state := State.IDLE
var stage := Stage.PREPARE
var tube_stage := TubeStage.REACH
var phase_names: Array = []
var phase_durs: Array = []
var active := false
var committed := false
var started_empty := false
var old_mag_dropped := false
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
var pump: MeshInstance3D = null
var rocket: Node3D = null
var left_hand: Node3D = null
var right_hand: Node3D = null

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

# 霰弹枪可见弹壳(逐发装填视觉)
var shell_mesh: MeshInstance3D = null
# 战术换弹用“新弹匣”独立视觉:旧弹匣还在枪上时,新弹匣已在手上,避免“旧弹匣自己飞出去”
var new_mag: Node3D = null


func _init(g: Gun) -> void:
	# 控制器只弱引用 Gun:Gun 强持有控制器,避免 RefCounted 循环引用导致切枪/拾枪内存泄漏
	_gun_ref = weakref(g)
	player = g.player
	group = g.group
	cfg = ReloadProfiles.profile_for(g.id, g.def)
	_capture_rig()
	_build_shell()
	_build_new_mag()


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
	if mag != null:
		mag_base = mag.position
		mag_base_rot = mag.rotation
	if bolt != null:
		bolt_base = bolt.position
	if slide != null:
		slide_base = slide.position
		slide_base_z = slide.position.z
	if pump != null:
		pump_base = pump.position
	if rocket != null:
		rocket_base = rocket.position
	if left_hand != null:
		hand_rest = left_hand.position
		hand_rest_rot = left_hand.rotation
	if right_hand != null:
		right_base = right_hand.position
		right_rot_base = right_hand.rotation
	hand_pocket = _g()._hand_l2
	hand_grip_anchor = _mag_grip_pos(mag_base)
	# 插入路径起点必须在首次换弹前就绪:FETCH 阶段会先读取 insert_start,
	# 若等 INSERT 阶段才赋值,首轮换弹会从原点附近瞬移到弹匣井下方(弹匣/手抽搐)。
	var ins := _mag_insert_start()
	insert_start = ins.get("pos", mag_base)
	insert_start_rot = ins.get("rot", Vector3.ZERO)


func _build_shell() -> void:
	if shell_mesh != null or group == null:
		return
	if _g().def.pellets <= 1:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.011
	cm.bottom_radius = 0.011
	cm.height = 0.055
	cm.radial_segments = 10
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.18, 0.15)
	mat.metallic = 0.6
	mat.roughness = 0.35
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	group.add_child(mi)
	shell_mesh = mi


func _build_new_mag() -> void:
	if new_mag != null or mag == null or _g().def.pellets > 1:
		return
	var dup := mag.duplicate(true) as Node3D
	if dup == null:
		return
	dup.name = "NewMagReload"
	dup.visible = false
	group.add_child(dup)
	WeaponModels.set_shadow_recursive(dup, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	new_mag = dup


# ============================================================
# 对外接口(Gun 调用)
# ============================================================

func start() -> bool:
	if state == State.ACTIVE:
		return false
	if _g().ammo >= _g().mag_cap or _g().reserve <= 0:
		return false
	reset_motion(false)
	if _g().def.pellets > 1:
		_start_tube()
	else:
		_start_mag()
	state = State.ACTIVE
	active = true
	committed = false
	started_empty = _g().ammo == 0
	old_mag_dropped = false
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


func cancel(reason := "fire") -> void:
	if state == State.IDLE:
		_g().reloading = false
		return
	# 枪机/泵动循环动画不能因取消瞬移,由 Gun 的 bolt_t/pump_t 自然收尾
	if shell_mesh != null:
		shell_mesh.visible = false
	if new_mag != null:
		new_mag.visible = false
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
	return _pump_wait > 0.0 or _bolt_wait > 0.0


func can_fire_interrupt() -> bool:
	if not active:
		return true
	# 泵动/拉栓循环尚未收尾:枪械不在可击发状态
	if is_busy_cycle():
		return false
	if _g().def.pellets > 1:
		return _g().ammo > 0
	if committed:
		return true
	# 空仓换弹且新匣未入:没有可发射的弹药,不允许打断
	if _g().ammo <= 0:
		return false
	# 战术换弹的准备阶段与拔弹初期:旧弹匣仍在,允许打断并立即开火
	var early: float = float(cfg.get("cancel_time", 0.45))
	if stage == Stage.PREPARE:
		return true
	if stage == Stage.REMOVE and stage_p < early and not old_mag_dropped:
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
	old_mag_dropped = false
	chamber_started = false
	time = 0.0
	stage_time = 0.0
	cancel_t = 0.0
	finish_t = 0.0
	_pump_wait = 0.0
	_bolt_wait = 0.0
	_insert_slap_t = -1.0
	_chamber_hand_start = hand_grip_anchor
	if snap:
		pose_pos = Vector3.ZERO
		pose_rot = Vector3.ZERO
		impulse_pos = Vector3.ZERO
		impulse_rot = Vector3.ZERO
	if shell_mesh != null:
		shell_mesh.visible = false
	if new_mag != null:
		new_mag.visible = false
	_g().grip_amt = 0.0
	if snap:
		_g().reloading = false
		_snap_rig_to_base()


func reset() -> void:
	reset_motion(true)


func on_holster() -> void:
	if active or state == State.ACTIVE or state == State.FINISH:
		cancel("holster")
	# 不 snap:holster Tween 从当前姿态开始;只确保收起途中弹匣可见,reset 交给下次 equip()
	if mag != null:
		mag.visible = true
	if new_mag != null:
		new_mag.visible = false
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
	var weights_raw: Array = cfg.get("tac_weights", []) if tac else cfg.get("empty_weights", [])
	var weights := weights_raw.duplicate()
	if weights.is_empty():
		weights = [0.16, 0.2, 0.32, 0.18, 0.14]
	var phase_names: Array = ["prepare", "remove", "fetch", "insert", "recover"]
	if not tac and String(cfg.get("chamber_style", "pull")) != "none":
		phase_names.insert(4, "chamber")
	# 防御:配置错误时补权重
	while weights.size() < phase_names.size():
		weights.append(0.1)
	while weights.size() > phase_names.size():
		weights.remove_at(weights.size() - 1)
	_build_phases(phase_names, weights, base_time)
	# 栓动狙刚开火后的拉栓循环先收尾,再开始卸弹;右手跟栓,左手保持护木
	if String(cfg.get("chamber_style", "pull")) == "bolt_cycle" and _g().bolt_t > 0.0:
		_bolt_wait = maxf(0.0, 0.85 - _g().bolt_t)


func _start_tube() -> void:
	var shell_time: float = maxf(0.3, float(cfg.get("shell_time", 0.7)) * _g()._reload_mult / maxf(0.1, float(cfg.get("anim_speed", 1.0))))
	shells_needed = mini(_g().mag_cap - _g().ammo, _g().reserve)
	shells_loaded = 0
	total = float(shells_needed) * shell_time
	var tube_weights_v: Array = cfg.get("tube_weights", [0.32, 0.3, 0.38])
	var weights := tube_weights_v.duplicate()
	_build_phases(["reach", "push", "return"], weights, shell_time)
	# 刚开火后的泵动循环先自然收尾,再开始逐发装填;避免左手同时"泵动+塞弹"
	_pump_wait = maxf(0.0, 0.45 - _g().pump_t) if _g().pump_t > 0.0 else 0.0
	if _pump_wait <= 0.0:
		AudioSys.reload(0)


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
			AudioSys.reload(0)
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
	if _g().def.pellets > 1:
		_update_tube(dt, env)
	else:
		_update_mag_reload(dt, env)
	# 阶段推进
	if state == State.ACTIVE and stage_p >= 1.0:
		_next_stage()


func _next_stage() -> void:
	if _g().def.pellets > 1:
		var tube_idx := stage + 1
		if tube_idx < phase_names.size():
			stage = tube_idx
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
	stage = idx
	stage_time = 0.0
	stage_dur = float(phase_durs[idx])
	stage_p = 0.0
	_on_stage_enter(idx)


func _on_stage_enter(idx: int) -> void:
	var nm: String = String(phase_names[idx])
	match nm:
		"remove":
			# 手已接触到弹匣/释放钮,开始卸弹
			AudioSys.reload(0)
			if rocket != null:
				rocket.visible = false
		"fetch":
			if mag != null and not old_mag_dropped and cfg.get("mag", "down") != "none":
				_drop_old_mag()
			if rocket != null:
				rocket.visible = false
			hand_after_remove = left_hand.position if left_hand != null else hand_grip_anchor
			# FETCH 后半段直接使用 insert_start 规划手/弹匣路径,阶段开始时必须更新。
			var ins := _mag_insert_start()
			insert_start = ins.get("pos", mag_base)
			insert_start_rot = ins.get("rot", Vector3.ZERO)
		"insert":
			if mag != null and cfg.get("mag", "down") != "none":
				mag.visible = true
			if rocket != null:
				rocket.visible = true
			insert_start = _mag_insert_start().get("pos", mag_base)
			insert_start_rot = _mag_insert_start().get("rot", Vector3.ZERO)
			if cfg.get("mag", "down") == "none":
				# 无实体弹匣(如 M24 内置弹仓):新弹药直接由手送到装填口
				insert_start = _g()._hand_l1
				insert_start_rot = Vector3.ZERO
		"chamber":
			_chamber_hand_start = left_hand.position if left_hand != null else hand_grip_anchor
			_start_chamber()
		"recover":
			pass


func _update_mag_reload(dt: float, env: float) -> void:
	# 注意:战术换弹的 phase_names 没有 chamber,阶段索引不能直接当 Stage 枚举用,
	# 必须按阶段名分发,否则战术换弹会把第 4 阶段误判成 CHAMBER 并触发拉栓。
	if stage >= phase_names.size():
		return
	var nm := String(phase_names[stage])
	match nm:
		"prepare":
			_update_mag_prepare()
		"remove":
			_update_mag_remove()
		"fetch":
			_update_mag_fetch()
		"insert":
			_update_mag_insert(dt)
		"chamber":
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


func _update_tube(dt: float, env: float) -> void:
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
	stage = 0
	stage_time = 0.0
	stage_p = 0.0
	stage_dur = float(phase_durs[0]) if phase_durs.size() > 0 else 0.2
	tube_stage = TubeStage.REACH
	committed = false
	AudioSys.reload(0)
	if shell_mesh != null:
		shell_mesh.visible = false


func _update_tube_hand(dt: float) -> void:
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
	AudioSys.reload(1)
	_impulse(float(cfg.get("insert_impact", 0.008)) * 0.8, 0.7)
	_camera_kick(0.7, 0.5)
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
	if started_empty and pump != null and _g().pump_t <= 0.0:
		_g().pump_t = 0.0001
		finish_dur = 0.55
		_camera_kick(1.0, 0.8)
		_impulse(float(cfg.get("chamber_impact", 0.014)), 1.0)
		AudioSys.bolt()
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
	var start := hand_after_remove
	if p < 0.42:
		# 旧弹匣脱手后手收回胸口/屏外,随后从胸口取出新弹匣
		var e := _ez(p / 0.42)
		var arc := sin(e * PI) * 0.07
		left_hand.position = start.lerp(pocket, e) + Vector3(-arc, 0.0, -arc * 0.5)
		if mag != null:
			mag.visible = false
	else:
		var e := _ez((p - 0.42) / 0.58)
		var target := insert_start + _grip_offset()
		var arc := sin(e * PI) * float(cfg.get("hand_arc", 0.09))
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
	if committed and _insert_slap_t >= 0.0 and mag != null:
		# 拍实动作从 0 起幅,避免 committed 翻转瞬间弹匣/手臂跳变
		_insert_slap_t += dt
		var s := sin(clampf(_insert_slap_t / 0.09, 0.0, 1.0) * PI)
		var slap: float = float(cfg.get("slap", 0.018))
		match String(cfg.get("mag", "down")):
			"side":
				mag.position.x += s * slap * 0.4
			"top":
				mag.position.y -= s * slap * 0.8
			_:
				mag.position.y += s * slap
		if left_hand != null:
			left_hand.position = mag.position + _grip_offset()


func _commit_mag() -> void:
	committed = true
	_insert_slap_t = 0.0
	# 弹匣余弹归还备弹,再取走整匣(总数守恒)
	_g().reserve += _g().ammo
	var take := mini(_g().mag_cap, _g().reserve)
	_g().ammo = take
	_g().reserve -= take
	AudioSys.reload(1)
	var slap: float = float(cfg.get("slap", 0.018))
	var imp: float = float(cfg.get("insert_impact", 0.009))
	_impulse(imp + slap * 0.25, 0.8)
	_camera_kick(0.75, 0.5)


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
	else:
		AudioSys.bolt()
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
	if mag == null or cfg.get("mag", "down") == "none":
		return
	if committed or not old_mag_dropped:
		# 只恢复可见性;位置由 CANCEL 状态的 _recover_anim_parts 平滑拉回,禁止瞬移
		mag.visible = true


func _snap_mag_to_base() -> void:
	if mag != null:
		mag.visible = true
		mag.position = mag_base
		mag.rotation = mag_base_rot
	if new_mag != null:
		new_mag.visible = false
	if rocket != null:
		rocket.visible = true


func _snap_rig_to_base() -> void:
	_snap_mag_to_base()
	if bolt != null:
		bolt.position = bolt_base
	if slide != null:
		slide.position = slide_base
	if pump != null:
		pump.position = pump_base
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
	if new_mag != null:
		new_mag.visible = false


func _recover_anim_parts(dt: float) -> void:
	var k := 1.0 - exp(-11.0 * dt)
	if mag != null:
		mag.position = mag.position.lerp(mag_base, k)
		mag.rotation = mag.rotation.lerp(mag_base_rot, k)
		mag.visible = true
	if new_mag != null:
		new_mag.visible = false
	if bolt != null:
		bolt.position = bolt.position.lerp(bolt_base, k)
	if slide != null:
		slide.position = slide.position.lerp(slide_base, k)
	if pump != null:
		pump.position = pump.position.lerp(pump_base, k)
	if rocket != null:
		rocket.visible = true


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
	# ADS / 冲刺:姿态向正常持枪姿态平滑让位,但仍保持换弹动作连续性
	var state_blend := 1.0
	if _g().ads_amount > 0.01:
		state_blend = lerpf(1.0, float(cfg.get("ads_keep", 0.55)), _g().ads_amount)
	if player != null and player.sprint_amount > 0.01:
		state_blend *= lerpf(1.0, float(cfg.get("sprint_keep", 0.16)), player.sprint_amount)
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
	var tr := sin(time * freq * 0.43 * TAU + 1.1) * sway * 0.35 * env
	player.reload_cam_pitch = Utils.damp(player.reload_cam_pitch, tp, damp, dt)
	player.reload_cam_yaw = Utils.damp(player.reload_cam_yaw, ty, damp, dt)
	player.reload_cam_roll = Utils.damp(player.reload_cam_roll, tr, damp, dt)


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
	# 新弹匣从胸口/胸前取出,符合“取下旧弹匣 → 扔地 → 从胸口拿新弹匣”的换弹流程
	return Vector3(0.02, -0.20, 0.10)


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
		"pistol":
			return GRIP_PISTOL
	return GRIP_DOWN


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
	match String(cfg.get("mag", "down")):
		"side":
			# AK/SVD 前挂后卡:向下 + 沿枪口方向前送拔出,不再横向右甩
			return { "pos": mag_base + Vector3(0.0, -e * 0.10, -e * 0.06), "rot": Vector3(e * 0.35, 0.0, 0.0) }
		"drum":
			return { "pos": mag_base + Vector3(0.0, -e * 0.09, 0.0), "rot": Vector3(0.0, 0.0, e * 0.85) }
		"belt":
			var belt_side := -1.0 if mag_base.x < -0.01 else 1.0
			return { "pos": mag_base + Vector3(belt_side * e * 0.05, -e * 0.08, 0.0), "rot": Vector3(0.0, 0.0, e * 0.5) }
		"top":
			return { "pos": mag_base + Vector3(0.0, e * 0.13, 0.0), "rot": Vector3(0.0, 0.0, sin(e * PI * 2.0) * 0.14) }
		"none":
			return { "pos": mag_base, "rot": mag_base_rot }
	return { "pos": mag_base + Vector3(sin(e * PI) * 0.012, -e * dist, 0.0), "rot": Vector3(0.0, 0.0, sin(e * PI) * rot) }


func _mag_insert_start() -> Dictionary:
	# 从卸弹终态出发:新弹匣先出现在弹匣井外,再沿手部路径进入
	var dist: float = float(cfg.get("drop_dist", 0.16))
	var rot: float = float(cfg.get("mag_rot", 0.13))
	match String(cfg.get("mag", "down")):
		"side":
			return { "pos": mag_base + Vector3(0.0, -0.10, -0.06), "rot": Vector3(0.3, 0.0, 0.0) }
		"drum":
			return { "pos": mag_base + Vector3(0.0, -0.09, 0.0), "rot": Vector3(0.0, 0.0, 0.8) }
		"belt":
			var belt_side := -1.0 if mag_base.x < -0.01 else 1.0
			return { "pos": mag_base + Vector3(belt_side * 0.05, -0.08, 0.0), "rot": Vector3(0.0, 0.0, 0.45) }
		"top":
			return { "pos": mag_base + Vector3(0.0, 0.13, 0.0), "rot": Vector3(0.0, 0.0, 0.3) }
		"none":
			return { "pos": mag_base, "rot": mag_base_rot }
	return { "pos": mag_base + Vector3(0.0, -dist, 0.0), "rot": Vector3(0.0, 0.0, rot) }


func _mag_insert_pose(p: float) -> Dictionary:
	var start := _mag_insert_start()
	var e := _ez(p)
	var pos: Vector3 = start.get("pos", mag_base)
	var rot: Vector3 = start.get("rot", Vector3.ZERO)
	pos = pos.lerp(mag_base, e)
	rot *= 1.0 - e
	return { "pos": pos, "rot": rot }


func _update_hand_rotation(dt: float) -> void:
	if left_hand == null:
		return
	var grip := 0.0
	if state == State.ACTIVE:
		if _g().def.pellets > 1:
			grip = 1.0 if tube_stage == TubeStage.PUSH else (0.5 if tube_stage == TubeStage.REACH and stage_p > 0.6 else 0.15)
		elif stage < phase_names.size():
			match String(phase_names[stage]):
				"prepare":
					grip = _ez(stage_p)
				"remove":
					grip = 1.0
				"fetch":
					grip = 0.8 if stage_p > 0.42 else 0.2
				"insert":
					grip = 1.0
				"chamber":
					var left_pull := bolt != null and bolt_base.x < 0.0 and String(cfg.get("chamber_style", "pull")) in ["pull", "pull_heavy", "pull_ak", "release"]
					grip = 0.9 if left_pull or String(cfg.get("chamber_style", "pull")) in ["slide", "belt_slap", "top_slap"] else 0.3
				"recover":
					grip = 0.0
	var rest_q := Quaternion.from_euler(hand_rest_rot)
	var grip_q := Quaternion.from_euler(HAND_GRIP_ROT)
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
		var off := Vector3(0.0, 0.015, 0.0)
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
	if _g().def.pellets > 1:
		match tube_stage:
			TubeStage.REACH:
				return "shell_reach"
			TubeStage.PUSH:
				return "shell_push"
			_:
				return "shell_return"
	return String(phase_names[stage]) if stage < phase_names.size() else "recover"
