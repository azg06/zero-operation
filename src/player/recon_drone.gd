class_name ReconDroneSystem extends Node
## 侦察兵第二技能:无人侦察机(按 F 起飞并接管操控)。
##
## 规则:
##   以起飞点为圆心 150m 圆形范围内自由飞行侦察地形,越界自动被"链路"拉回;
##   操控期间玩家本体原地待机(仍可被击杀),再按 F / 电池耗尽 / 玩家死亡 → 自动召回。
##
## 架构:
##   独立 Camera3D 接管 current(与实时 3D 部署相机同一套做法),不改主相机参数;
##   四旋翼模型挂 G.world_root,机身按速度倾斜、旋翼持续旋转;
##   镜头下方按 SPOT_INTERVAL 自动标记范围内敌人(侦察机的战术价值)。
##   召回时相机 current 交还主相机并恢复视角模型显示,状态完全复位。

const RADIUS := 100.0          # 侦察半径(以起飞点为圆心的圆形范围;超出即开始失联倒计时)
const LOST_LIMIT := 3.0        # 超出半径后允许的失联时长(秒):倒计时归零即彻底断链
const BLACKOUT := 0.6          # 断链黑屏时长(秒),黑屏结束交还本体视角
const ALT_MIN := 2.5           # 最低离地高度
const ALT_MAX := 65.0          # 最高离地高度
const SPEED := 9.0             # 水平巡航速度(m/s ≈ 32km/h,四旋翼手感)
const SPEED_BOOST := 16.0      # 按住 Shift 的加速档(m/s)
const ACCEL := 3.2             # 速度趋近率(1/s):越小起步/收油越"有惯性"
const LIFT_SPEED := 4.5        # 升降速度(m/s)
const YAW_SMOOTH := 12.0       # 转向平滑率(1/s):消除鼠标抖动带来的瞬转
const LIFE := 45.0             # 电池续航(秒)
const SPOT_R := 60.0           # 自动标记敌人半径
const SPOT_INTERVAL := 2.0     # 自动标记间隔(秒)
const CAM_FOV := 78.0
const CAM_FWD := 0.52          # 云台相机前伸量(m):前旋翼叶尖到 z≈-0.45,必须越过它否则挡视野
const CAM_DOWN := -0.06        # 云台相机相对机身中心的高度偏移(略低于旋翼平面)

var piloting := false           # 玩家操控中 —— 此标志会把玩家本体 update 冻结,严禁被 AI 起飞占用
var ai_flying := false          # AI 无人机的实体在飞(不冻结玩家,不接管相机)
var actor = null                # 操控者(Player 或 Bot)
var ai_mode := false            # true = AI 侦察兵起飞(不接管玩家相机,自动盘旋侦察)
var ai_turn_t := 0.0            # AI 自动转向计时
var ai_turn_dir := 1.0          # AI 盘旋方向
var origin := Vector3.ZERO      # 起飞点(圆心)
var pos := Vector3.ZERO
var vel := Vector3.ZERO         # 当前速度(惯性模型:目标速度阻尼趋近)
var yaw := 0.0
var pitch := -0.35
var yaw_target := 0.0           # 鼠标输入的目标视角(云台平滑到它)
var pitch_target := -0.35
var life := 0.0
var dist_to_origin := 0.0
var lost_t := 0.0               # 已超出半径的累计时长(秒):>0 时图传开始雪花化
var blackout_t := 0.0           # 断链黑屏剩余时长(秒)
var mesh: Node3D = null
var cam: Camera3D = null
var _fx_layer: CanvasLayer = null   # 失联/黑屏全屏层(压在 HUD 之上)
var _fx_rect: ColorRect = null
var _rotors: Array = []
var _spot_t := 0.0
var _warn_t := 0.0
var _edge := false              # 上一帧是否已在边界(提示节流)


## 起飞:成功返回 true(失败不扣技能次数)
func launch(p_actor) -> bool:
	if piloting:
		return false
	if p_actor == null or not p_actor.alive:
		return false
	if p_actor.vehicle != null:
		G.hud.hint("载具内无法起飞无人机")
		return false
	if G.mode == "tdm":
		G.hud.hint("团队死斗禁用兵种技能")
		return false
	actor = p_actor
	origin = p_actor.pos
	pos = origin + Vector3(0, 6.0, 0)
	vel = Vector3.ZERO
	yaw = p_actor.yaw
	pitch = -0.35
	yaw_target = yaw
	pitch_target = pitch
	life = LIFE
	lost_t = 0.0
	blackout_t = 0.0
	_spot_t = 0.0
	_warn_t = 0.0
	_edge = false
	_build_fx()
	_build_mesh()
	_build_camera()
	piloting = true
	# 视角模型隐藏:操控无人机时不该在画面里看到自己的枪
	var g = p_actor.gun()
	if g != null and g.group != null and is_instance_valid(g.group):
		g.group.visible = false
	AudioSys.capture(true)
	G.hud.hint("无人侦察机已起飞:WASD 飞行 · 鼠标转向 · 空格上升 · Ctrl 下降 · F 召回")
	return true


## AI 侦察兵起飞:不接管玩家相机,只生成四旋翼实体并自动盘旋标记敌人。
func launch_ai(p_actor) -> bool:
	if piloting:
		return false
	if p_actor == null or not p_actor.alive:
		return false
	if p_actor.vehicle != null:
		return false
	if G.mode == "tdm" or G.mode == "br":
		return false
	actor = p_actor
	ai_mode = true
	origin = p_actor.pos
	pos = origin + Vector3(0, 18.0, 0)
	vel = Vector3.ZERO
	yaw = p_actor.yaw
	pitch = -0.35
	yaw_target = yaw
	pitch_target = pitch
	life = 30.0
	lost_t = 0.0
	blackout_t = 0.0
	_spot_t = 0.0
	_warn_t = 0.0
	_edge = false
	ai_turn_t = Utils.rand(2.0, 5.0)
	ai_turn_dir = Utils.choice([-1.0, 1.0])
	_build_mesh()
	# 关键修复:AI 起飞绝不能置 piloting —— G.drone 是全局单例,player.gd 每帧
	# 检查 piloting 决定是否把输入交给无人机并冻结本体。友军 AI 一起飞,
	# 玩家就会被冻在原地,体感等同"视角被切到无人机"(实机已验证的 bug)。
	ai_flying = true
	AudioSys.capture(true)
	return true


## 失联/黑屏全屏层(CanvasLayer 95:压住 HUD,低于爆闪层 100),惰性创建复用
func _build_fx() -> void:
	if _fx_layer != null and is_instance_valid(_fx_layer):
		_fx_rect.visible = false
		return
	_fx_layer = CanvasLayer.new()
	_fx_layer.name = "DroneLinkFX"
	_fx_layer.layer = 95
	add_child(_fx_layer)
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rect.color = Color(0, 0, 0, 0)
	_fx_rect.visible = false
	_fx_layer.add_child(_fx_rect)


## 图传画面状态:0=正常,1=完全雪花(失联倒计时走完);黑屏阶段返回 1
func signal_lost01() -> float:
	if blackout_t > 0.0:
		return 1.0
	return clampf(lost_t / LOST_LIMIT, 0.0, 1.0)


## 失联倒计时剩余秒数(HUD 显示用;未越界返回 0)
func lost_countdown() -> float:
	if lost_t <= 0.0:
		return 0.0
	return maxf(0.0, LOST_LIMIT - lost_t)


## 全屏效果:越界 → 灰白雪花逐渐吃掉画面;断链 → 纯黑
func _update_fx(_dt: float) -> void:
	if _fx_rect == null or not is_instance_valid(_fx_rect):
		return
	if blackout_t > 0.0:
		_fx_rect.visible = true
		_fx_rect.color = Color(0, 0, 0, 1)
		return
	if lost_t <= 0.0:
		if _fx_rect.visible:
			_fx_rect.visible = false
		return
	# 灰白噪声:透明度随失联进度上升,并逐帧抖动模拟模拟信号丢失
	var k := clampf(lost_t / LOST_LIMIT, 0.0, 1.0)
	var a: float = clampf(0.30 + 0.62 * k + Utils.rand(-0.06, 0.06), 0.0, 0.96)
	var g_j: float = Utils.rand(-0.03, 0.03)
	_fx_rect.visible = true
	_fx_rect.color = Color(0.86 + g_j, 0.89 + g_j, 0.92 + g_j, a)


## 召回:视角交还主相机,模型与相机销毁,状态复位(幂等)
func recall(reason := "") -> void:
	if not piloting and not ai_flying:
		return
	var was_ai := ai_mode
	piloting = false
	ai_flying = false
	lost_t = 0.0
	blackout_t = 0.0
	if _fx_rect != null and is_instance_valid(_fx_rect):
		_fx_rect.visible = false
		_fx_rect.color = Color(0, 0, 0, 0)
	if cam != null and is_instance_valid(cam):
		cam.queue_free()
	cam = null
	if mesh != null and is_instance_valid(mesh):
		G.effects.smoke_spawn(pos.x, pos.y, pos.z, 0, 0.4, 0, 0.5, 0.7, 0.7, 0.7, -0.01)
		mesh.queue_free()
	mesh = null
	_rotors.clear()
	if not was_ai and G.camera != null and is_instance_valid(G.camera):
		G.camera.current = true
	if actor != null and actor.has_method("gun"):
		var ag = actor.gun()
		if ag != null and ag.group != null and is_instance_valid(ag.group):
			ag.group.visible = true
	actor = null
	ai_mode = false
	AudioSys.reload(0)
	if reason != "" and not was_ai:
		G.hud.hint("无人侦察机已回收:" + reason)


func _process(dt: float) -> void:
	if not piloting and not ai_flying:
		return
	# AI 无人机:自动盘旋侦察,不读取玩家输入、不接管主相机、无图传 UI
	if ai_flying:
		if actor == null or not actor.alive or actor.vehicle != null or G.state != "playing":
			recall("链路中断")
			return
		life -= dt
		if life <= 0.0:
			recall("电池耗尽")
			return
		_fly_ai(dt)
		_update_mesh(dt)
		_auto_spot(dt)
		return
	# 断链黑屏:黑屏走完才把视角交还本体(不再接受操控输入)
	if blackout_t > 0.0:
		blackout_t -= dt
		_update_fx(dt)
		if blackout_t <= 0.0:
			recall("链路中断:无人机已在半径外失联")
		return
	# 操控者阵亡 / 上车 / 对局结束 → 强制召回
	if actor == null or not actor.alive or actor.vehicle != null or G.state != "playing":
		recall("链路中断")
		return
	life -= dt
	if life <= 0.0:
		recall("电池耗尽")
		return
	if life < 8.0 and _warn_t <= 0.0:
		_warn_t = 4.0
		G.hud.hint("无人机电量低:剩余 %d 秒" % int(ceil(life)))
	_warn_t = maxf(0.0, _warn_t - dt)
	_fly(dt)
	_update_mesh(dt)
	_auto_spot(dt)
	_update_fx(dt)
	# 失联倒计时走完 → 进入黑屏,随后自动交还视角
	if lost_t >= LOST_LIMIT:
		blackout_t = BLACKOUT
		AudioSys.dry_fire()
		G.hud.hint("图传断链:无人机已失联")


## AI 自动飞行:在起飞点半径内盘旋,定期随机转向;始终限制在链路范围内。
func _fly_ai(dt: float) -> void:
	ai_turn_t -= dt
	if ai_turn_t <= 0.0:
		ai_turn_t = Utils.rand(3.0, 6.5)
		ai_turn_dir = Utils.choice([-1.0, 1.0])
	yaw_target += ai_turn_dir * 0.55 * dt
	yaw = lerp_angle(yaw, yaw_target, 1.0 - exp(-YAW_SMOOTH * dt))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var flat := Vector2(pos.x - origin.x, pos.z - origin.z)
	var want := fwd * SPEED
	if flat.length() > RADIUS * 0.78:
		var home := Vector2(origin.x - pos.x, origin.z - pos.z).normalized()
		want = Vector3(home.x, 0, home.y) * SPEED
		yaw_target = atan2(-home.x, -home.y)
	vel = vel.lerp(want, 1.0 - exp(-ACCEL * dt))
	pos += vel * dt
	dist_to_origin = Vector2(pos.x - origin.x, pos.z - origin.z).length()
	var gy: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	pos.y = clampf(pos.y, gy + 14.0, gy + 40.0)
	if vel.length() > 0.001:
		var dirn := vel.normalized()
		var hit = Utils.raycast_world(pos, dirn, 1.2)
		if hit != null:
			pos -= dirn * (1.2 - float(hit["dist"]))
			vel *= 0.25
			ai_turn_t = 0.0


## 飞行操控:鼠标转向 + WASD 水平移动 + 空格/Ctrl 升降,150m 圆形电子围栏。
## 速度走"目标速度 → 阻尼趋近"的惯性模型,起步/收油/转向都有过渡,不再像瞬移。
func _fly(dt: float) -> void:
	var md: Vector2 = G.input_sys.consume_mouse()
	var sens: float = 0.0016 * float(G.settings.get("sensitivity", 1.0))
	yaw_target -= md.x * sens
	pitch_target = clampf(pitch_target - md.y * sens, -1.35, 0.6)
	# 视角平滑:云台有转动惯量,鼠标猛甩不会瞬间贴到目标角
	yaw = lerp_angle(yaw, yaw_target, 1.0 - exp(-YAW_SMOOTH * dt))
	pitch = lerpf(pitch, pitch_target, 1.0 - exp(-YAW_SMOOTH * dt))
	var fx := 0.0
	var fz := 0.0
	if Input.is_action_pressed("move_forward"):
		fz += 1.0
	if Input.is_action_pressed("move_back"):
		fz -= 1.0
	if Input.is_action_pressed("move_right"):
		fx += 1.0
	if Input.is_action_pressed("move_left"):
		fx -= 1.0
	var top: float = SPEED_BOOST if Input.is_action_pressed("sprint") else SPEED
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var want := fwd * fz + right * fx
	if want.length() > 0.001:
		want = want.normalized() * top
	else:
		want = Vector3.ZERO
	# 升降同样走目标速度(松键后自然滑停,而不是立刻停住)
	var want_y := 0.0
	if Input.is_action_pressed("jump"):
		want_y += LIFT_SPEED
	if Input.is_action_pressed("crouch"):
		want_y -= LIFT_SPEED
	want.y = want_y
	vel = vel.lerp(want, 1.0 - exp(-ACCEL * dt))
	pos += vel * dt
	# 链路半径:超出 100m 不再有空气墙,而是图传逐渐雪花化 + 失联倒计时(3s 后彻底断链)
	var flat := Vector2(pos.x - origin.x, pos.z - origin.z)
	dist_to_origin = flat.length()
	if dist_to_origin > RADIUS:
		if not _edge:
			_edge = true
			G.hud.hint("已超出链路半径 100 米:图传信号丢失,3 秒内返回否则断链")
		lost_t += dt
	else:
		if _edge and dist_to_origin < RADIUS - 4.0:
			_edge = false
			if lost_t > 0.2:
				G.hud.hint("已回到链路范围:图传恢复")
		# 回到范围内:信号快速恢复(比丢失更快,避免边缘反复刷屏)
		lost_t = maxf(0.0, lost_t - dt * 2.5)
	# 离地高度限制 + 撞地保护
	var gy: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	var y_lo := gy + ALT_MIN
	var y_hi := gy + ALT_MAX
	if pos.y < y_lo or pos.y > y_hi:
		vel.y = 0.0
	pos.y = clampf(pos.y, y_lo, y_hi)
	# 建筑碰撞:贴到墙面前停住(沿运动方向短射线)
	if vel.length() > 0.001:
		var dirn := vel.normalized()
		var hit = Utils.raycast_world(pos, dirn, 1.2)
		if hit != null:
			pos -= dirn * (1.2 - float(hit["dist"]))
			vel *= 0.25
	if cam != null and is_instance_valid(cam):
		cam.global_position = _cam_pos()
		cam.rotation = Vector3(pitch, yaw, 0.0)


## 机载云台相机位置:沿机头方向前伸并略低于旋翼平面,
## 避免前两副旋翼糊在镜头前(FPV 视角看不到自机机身)。
func _cam_pos() -> Vector3:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	return pos + fwd * CAM_FWD + Vector3(0, CAM_DOWN, 0)


## 机身姿态:按实际速度前倾/侧倾(惯性可见),旋翼高速旋转
func _update_mesh(dt: float) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	mesh.global_position = pos
	mesh.rotation.y = yaw
	# 机体系速度 → 俯仰/横滚(真实四旋翼靠倾斜产生水平推力)
	var lv := Vector3(vel.x, 0, vel.z).rotated(Vector3.UP, -yaw)
	var tilt: float = clampf(-lv.z / maxf(SPEED_BOOST, 1.0), -1.0, 1.0) * 0.3
	var roll: float = clampf(-lv.x / maxf(SPEED_BOOST, 1.0), -1.0, 1.0) * 0.26
	mesh.rotation.x = lerpf(mesh.rotation.x, tilt, 1.0 - exp(-dt * 5.0))
	mesh.rotation.z = lerpf(mesh.rotation.z, roll, 1.0 - exp(-dt * 5.0))
	for i in _rotors.size():
		var r: Node3D = _rotors[i]
		if is_instance_valid(r):
			r.rotation.y += dt * (48.0 if i % 2 == 0 else -48.0)


## ---- HUD 数据接口(现代军用 UAV 抬头显示读这些) ----
func speed_ms() -> float:
	return Vector3(vel.x, 0, vel.z).length()


func alt_agl() -> float:
	var gy: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	return maxf(0.0, pos.y - gy)


func battery01() -> float:
	return clampf(life / LIFE, 0.0, 1.0)


## 自动侦察:定期标记无人机下方半径内的敌人(侦察机的核心价值)
func _auto_spot(dt: float) -> void:
	_spot_t -= dt
	if _spot_t > 0.0:
		return
	_spot_t = SPOT_INTERVAL
	var n := 0
	var my_team = actor.team if actor != null else "us"
	for b in G.bots:
		if not b.alive or b.team == my_team:
			continue
		if b.pos.distance_to(pos) > SPOT_R:
			continue
		b.spotted = maxf(3.0, float(b.spotted))
		n += 1
	if n > 0 and not ai_mode:
		G.hud.hint("无人机侦察:已标记 %d 名敌人" % n)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "ReconDroneCamera"
	cam.fov = CAM_FOV
	cam.near = 0.08
	cam.far = 1200.0
	# 必须先入场景树再写 global_transform(节点不在树内时全局变换无效)
	G.world_root.add_child(cam)
	cam.global_position = _cam_pos()
	cam.rotation = Vector3(pitch, yaw, 0.0)
	cam.current = true


## 四旋翼模型:机身 + 四臂 + 四旋翼 + 云台球机 + 导航灯
func _build_mesh() -> void:
	var g := Node3D.new()
	g.name = "ReconDrone"
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color.html("#22262b")
	dark.roughness = 0.55
	dark.metallic = 0.35
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color.html("#39505e")
	accent.roughness = 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.13, 0.5)
	body.mesh = bm
	body.material_override = dark
	g.add_child(body)
	# 云台球机
	var gimbal := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.075
	gm.height = 0.15
	gimbal.mesh = gm
	gimbal.material_override = accent
	gimbal.position = Vector3(0, -0.1, -0.16)
	g.add_child(gimbal)
	var lens := MeshInstance3D.new()
	var lensm := CylinderMesh.new()
	lensm.top_radius = 0.028
	lensm.bottom_radius = 0.032
	lensm.height = 0.05
	lens.mesh = lensm
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color(0.05, 0.08, 0.12)
	lens_mat.metallic = 0.9
	lens_mat.roughness = 0.15
	lens.material_override = lens_mat
	lens.rotation.x = PI / 2.0
	lens.position = Vector3(0, -0.1, -0.23)
	g.add_child(lens)
	# 四臂 + 四旋翼
	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.7, 0.78, 0.85, 0.55)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rotor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 4:
		var sx: float = 1.0 if i % 2 == 0 else -1.0
		var sz: float = 1.0 if i < 2 else -1.0
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.05, 0.04, 0.05)
		arm.mesh = am
		arm.material_override = dark
		arm.position = Vector3(sx * 0.24, 0.0, sz * 0.26)
		g.add_child(arm)
		var boom := MeshInstance3D.new()
		var boomm := BoxMesh.new()
		boomm.size = Vector3(0.3, 0.028, 0.028)
		boom.mesh = boomm
		boom.material_override = dark
		boom.position = Vector3(sx * 0.15, 0.0, sz * 0.18)
		boom.rotation.y = -sx * sz * 0.7
		g.add_child(boom)
		var hub := Node3D.new()
		hub.position = Vector3(sx * 0.26, 0.05, sz * 0.28)
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(0.34, 0.006, 0.035)
		blade.mesh = blm
		blade.material_override = rotor_mat
		hub.add_child(blade)
		var blade2 := MeshInstance3D.new()
		blade2.mesh = blm
		blade2.material_override = rotor_mat
		blade2.rotation.y = PI / 2.0
		hub.add_child(blade2)
		g.add_child(hub)
		_rotors.append(hub)
	# 导航灯(前白后红)
	for i in 2:
		var lamp := MeshInstance3D.new()
		var lmm := SphereMesh.new()
		lmm.radius = 0.022
		lmm.height = 0.044
		lamp.mesh = lmm
		var lmat := StandardMaterial3D.new()
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat.albedo_color = Color(0.9, 1.0, 1.0) if i == 0 else Color(1.0, 0.25, 0.2)
		lamp.material_override = lmat
		lamp.position = Vector3(0, 0.06, -0.26 if i == 0 else 0.26)
		g.add_child(lamp)
	g.position = pos
	G.world_root.add_child(g)
	mesh = g


## HUD 状态行:操控中显示电量/半径/高度
func status_text() -> String:
	if not piloting:
		return ""
	if lost_t > 0.0:
		return "图传信号丢失 · 距起点 %dm(限 %dm)· %.1fs 后断链 · 立即返回" % [
			int(round(dist_to_origin)), int(RADIUS), lost_countdown()]
	var gy: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	return "无人侦察机 · 电量 %ds · 距起点 %dm/%dm · 高度 %dm · F 召回" % [
		int(ceil(life)), int(round(dist_to_origin)), int(RADIUS), int(round(pos.y - gy))]
