class_name VehicleCameraController extends Node3D
## 载具视角统一控制器(v4 — 双人乘员 + 驾驶/炮手分离)
## 状态机:THIRD_PERSON / FP_DRIVER / FP_GUNNER / FP_OPTIC
## 乘员规则:
##   驾驶位(FP_DRIVER):只能驾驶,不能开炮;自由观察(鼠标只转相机,不带动炮塔)
##   炮手位(FP_GUNNER/FP_OPTIC):瞄准镜头,准心=炮口=准心,指哪打哪;左键开火
##   第三人称:观察模式,相机环绕载具并始终 look_at 载具(主体=载具,不飘)
## 全程只驱动唯一 G.camera(单个 current 相机),绝不隐藏载具外壳。

enum VehView { THIRD_PERSON, FP_DRIVER, FP_GUNNER, FP_OPTIC }

## 各车型座位(车体/炮塔局部坐标,与 vehicle_models.gd 观察舱几何对齐)
const SEAT_CFG := {
	"tank": {
		"driver": Vector3(0, 1.23, 0.35),       # 驾驶位:观察舱中心(观察口上缘 19°/仪表台 17.6°)
		"gunner": Vector3(0.35, 0.3, -0.7),     # 炮手位:炮塔内(低于舱顶,顶盖不挡视线)
		"optic": Vector3(0.35, 0.3, -0.3),      # 炮镜:炮塔内前方(镜筒已上移,无黑柱)
	},
	"apc": {
		"driver": Vector3(0, 1.3, -1.3),        # 驾驶位:观察舱中心
		"gunner": Vector3(0.3, 0.22, -0.6),     # 炮手位:炮塔内(低于舱顶)
		"optic": Vector3(0.3, 0.22, -0.25),     # 炮镜:炮塔内前方
	},
	"aa": {
		"driver": Vector3(0, 1.28, -1.35),      # 驾驶位:观察舱中心
		"gunner": Vector3(0.3, 0.5, -0.55),     # 操作位:半敞开炮塔(原版)
		"optic": Vector3(0.3, 0.52, -0.2),      # 炮镜:半敞开炮塔(原版)
	},
	"jeep": {
		"driver": Vector3(-0.45, 1.62, 0.45),   # 吉普驾驶位(与 def.seat 一致)
		"gunner": Vector3(0.45, 1.62, 0.45),    # 吉普乘客位(副驾)
		"optic": Vector3.ZERO,
	},
}

## 鼠标观察范围:水平 ±115°,垂直 +70°/-60°
const LOOK_YAW_MAX := 2.0
const LOOK_PITCH_UP := 1.22
const LOOK_PITCH_DOWN := -1.05
## 载具第一人称视野
const FP_FOV := 86.0

var vehicle = null
var view := VehView.THIRD_PERSON
var look_yaw := 0.0               # 鼠标观察角(第一人称/炮塔瞄准)
var look_pitch := 0.0
var _gunner_mode := false         # 玩家是否坐在炮手/乘客位(瞄准与开火权限)
var _tp_orbit_yaw := 0.0          # 第三人称环绕角(无钳制,可 360° 环绕)
var _tp_orbit_pitch := 0.0        # 第三人称环绕俯仰(相机高低)

var _seats: Node3D = null
var _driver_seat: Node3D = null
var _gunner_seat: Node3D = null
var _optic: Node3D = null
var _fp_rig: Node3D = null        # FirstPersonCameraRig
var _fp_yaw: Node3D = null        # YawPivot
var _fp_pitch: Node3D = null      # PitchPivot
var _fp_cam: Node3D = null        # Camera3D(标记)
var _fp_base: Transform3D = Transform3D()   # 炮手位/炮镜位平滑过渡基准
var _fp_base_key := -1            # 当前基准目标(1=driver 2=gunner 3=optic)


func _init(v) -> void:
	vehicle = v
	name = "VehicleCameraController"


func _ready() -> void:
	_seats = Node3D.new()
	_seats.name = "Seats"
	add_child(_seats)
	_driver_seat = Node3D.new()
	_driver_seat.name = "DriverSeat"
	_seats.add_child(_driver_seat)
	_gunner_seat = Node3D.new()
	_gunner_seat.name = "GunnerSeat"
	_seats.add_child(_gunner_seat)
	_optic = Node3D.new()
	_optic.name = "GunnerOptic"
	_seats.add_child(_optic)
	# FirstPersonCameraRig → YawPivot → PitchPivot → Camera3D
	_fp_rig = Node3D.new()
	_fp_rig.name = "FirstPersonCameraRig"
	add_child(_fp_rig)
	_fp_yaw = Node3D.new()
	_fp_yaw.name = "YawPivot"
	_fp_rig.add_child(_fp_yaw)
	_fp_pitch = Node3D.new()
	_fp_pitch.name = "PitchPivot"
	_fp_yaw.add_child(_fp_pitch)
	_fp_cam = Node3D.new()
	_fp_cam.name = "Camera3D"
	_fp_pitch.add_child(_fp_cam)


## 上车时调用:重置观察角与平滑(防瞬移插值)
func reset() -> void:
	look_yaw = 0.0
	look_pitch = 0.0
	_tp_orbit_yaw = 0.0
	_tp_orbit_pitch = 0.0
	_fp_base_key = -1
	_gunner_mode = false


## 设置玩家所在座位(0=驾驶位 1=炮手/乘客位)
func set_gunner_mode(on: bool) -> void:
	_gunner_mode = on


## 玩家是否在炮手位(决定炮塔是否跟随观察角瞄准)
func is_gunner() -> bool:
	return _gunner_mode


## 鼠标观察(dx/dy 为原始鼠标位移;只转相机,绝不转车体)
func apply_look(dx: float, dy: float) -> void:
	var sens: float = 0.0022 * G.settings.get("sensitivity", 1.0)
	look_yaw = clampf(look_yaw - dx * sens, -LOOK_YAW_MAX, LOOK_YAW_MAX)
	look_pitch = clampf(look_pitch - dy * sens, LOOK_PITCH_DOWN, LOOK_PITCH_UP)


## 第三人称环绕观察(360° 环绕 + 俯仰调高/压低相机;只转相机,不影响炮塔/车体)
func apply_tp_orbit(dx: float, dy: float) -> void:
	var sens: float = 0.0022 * G.settings.get("sensitivity", 1.0)
	_tp_orbit_yaw = wrapf(_tp_orbit_yaw - dx * sens, -PI, PI)
	# 鼠标上推(dy<0) → 相机降低(从下往上看),与第一人称手感一致
	_tp_orbit_pitch = clampf(_tp_orbit_pitch + dy * sens, -0.85, 0.9)


## 炮塔是否跟随观察方向瞄准:仅玩家坐在炮手位时的瞄准镜头/第三人称
func turret_chase() -> bool:
	return _gunner_mode and view != VehView.FP_DRIVER


func _seat_cfg() -> Dictionary:
	return SEAT_CFG.get(vehicle.type, SEAT_CFG["jeep"])


## 每帧把座位锚点同步到正确世界位置(驾驶位随车体、炮手位随炮塔)
func _sync_seat_anchors() -> void:
	var cfg := _seat_cfg()
	var mesh: Node3D = vehicle.mesh
	var turret: Node3D = mesh
	if mesh.has_meta("turret"):
		turret = mesh.get_meta("turret")
	_driver_seat.global_transform = mesh.global_transform * Transform3D(Basis(), cfg["driver"])
	_gunner_seat.global_transform = turret.global_transform * Transform3D(Basis(), cfg["gunner"])
	_optic.global_transform = turret.global_transform * Transform3D(Basis(), cfg["optic"])


## 潜望镜/天线杆显隐:炮手位/炮镜第一人称隐藏(挡视野),其余视角恢复
func _set_periscope_vis(vis: bool) -> void:
	if vehicle == null or vehicle.mesh == null:
		return
	var it = vehicle.mesh.get_meta("interior_turret", null) if vehicle.mesh.has_meta("interior_turret") else null
	if it == null:
		return
	var stack: Array = [it]
	while not stack.is_empty():
		var nd = stack.pop_back()
		if nd.name == "Periscope":
			nd.visible = vis
		for ch in nd.get_children():
			stack.append(ch)


func _shake() -> Vector2:
	if G.effects == null:
		return Vector2.ZERO
	return Vector2(G.effects.shake_yaw, G.effects.shake_pitch)


func update(dt: float) -> void:
	if vehicle == null or vehicle.mesh == null:
		return
	var cam: Camera3D = G.camera
	if cam == null:
		return
	_sync_seat_anchors()
	match view:
		VehView.FP_DRIVER:
			_update_fp_driver(cam, dt)
		VehView.FP_GUNNER:
			_update_fp_gunner(cam, dt, 2)
		VehView.FP_OPTIC:
			_update_fp_gunner(cam, dt, 3)
		_:
			_update_tp(cam)


## 驾驶位第一人称:只能驾驶;自由观察(鼠标只转相机,不带动炮塔)
## 吉普副驾驶(_gunner_mode):相机锚定乘客位(副驾),同样自由观察 + 可持个人武器开火
func _update_fp_driver(cam: Camera3D, dt: float) -> void:
	_set_periscope_vis(true)   # 驾驶位/第三人称恢复潜望镜
	var target: Transform3D = _gunner_seat.global_transform if _gunner_mode else _driver_seat.global_transform
	# 驾驶位 ⇄ 副驾驶位平滑过渡(换位不瞬移)
	if _fp_base_key == 1:
		_fp_base = target
	else:
		if _fp_base_key < 0:
			_fp_base = target
		else:
			var k := 1.0 - exp(-dt * 8.0)
			_fp_base = _fp_base.interpolate_with(target, k)
		_fp_base_key = 1
	_fp_rig.global_transform = _fp_base
	_fp_yaw.rotation.y = look_yaw
	_fp_pitch.rotation.x = look_pitch
	var sh := _shake()
	cam.global_transform = _fp_cam.global_transform
	cam.rotation_order = EULER_ORDER_YXZ
	cam.rotation.y += sh.x
	cam.rotation.x += sh.y
	# 加速/转向微惯性(轻量,不抖动)
	var max_s: float = vehicle.def["max_speed"]
	cam.rotation.x += clampf(vehicle.speed / maxf(max_s, 1.0), -1.0, 1.0) * 0.02
	cam.rotation.z += clampf(vehicle.steer, -1.0, 1.0) * 0.008


## 炮手位/炮镜位第一人称:瞄准镜头,准心=炮口=准心;位置随座位,方向=炮塔瞄准
func _update_fp_gunner(cam: Camera3D, dt: float, key: int) -> void:
	_set_periscope_vis(false)   # 炮手位第一人称隐藏潜望镜/天线杆(挡视野)
	var target: Transform3D
	match key:
		2:
			target = _gunner_seat.global_transform
		_:
			target = _optic.global_transform
	# 炮手位 ⇄ 炮镜位平滑过渡
	if key == _fp_base_key:
		_fp_base = target
	else:
		if _fp_base_key < 0:
			_fp_base = target
		else:
			var k := 1.0 - exp(-dt * 6.0)
			_fp_base = _fp_base.interpolate_with(target, k)
		_fp_base_key = key
	_fp_rig.global_transform = _fp_base
	_fp_yaw.rotation.y = 0.0
	_fp_pitch.rotation.x = 0.0
	var shake_k: float = 0.35 if key == 3 else 1.0
	var sh := _shake()
	cam.global_transform = _fp_cam.global_transform
	cam.rotation_order = EULER_ORDER_YXZ
	cam.rotation.y = vehicle.yaw + vehicle.turret_yaw + sh.x * shake_k
	cam.rotation.x = vehicle.turret_pitch + sh.y * shake_k
	cam.rotation.z = 0


## 第三人称(原版距离/高度 + 鼠标 360° 环绕):相机固定在载具后上方
## (坦克 7m/2.8m,其余 5.5m/2.3m),鼠标可 360° 环绕与俯仰观察,
## 相机始终看向载具(主体=载具),近墙射线收束。
func _update_tp(cam: Camera3D) -> void:
	var v = vehicle
	var dist := 7.0 if v.type == "tank" else 5.5
	var cam_h := 2.8 if v.type == "tank" else 2.3
	# 环绕角 = 车体朝向 + 鼠标环绕(360°,只转相机,车体方向由驾驶输入控制)
	var orbit: float = v.yaw + _tp_orbit_yaw
	var back := Vector3(sin(orbit), 0, cos(orbit))
	var eye: Vector3 = v.pos + Vector3(0, cam_h, 0)
	var target: Vector3 = eye + back * dist
	# 俯仰 → 相机高低(鼠标上下观察)
	target.y += sin(_tp_orbit_pitch) * dist * 0.6
	# 近墙碰撞:射线收束
	var hit = Utils.raycast_world(eye, back, dist + 0.3)
	if hit != null:
		target = eye + back * maxf(1.2, hit["dist"] - 0.3)
	# 地面抬升:相机不低于地面 0.35m(防半埋)
	if G.ground_h.is_valid():
		var gh: float = G.ground_h.call(target.x, target.z)
		if target.y < gh + 0.35:
			target.y = gh + 0.35
	cam.global_position = target
	# 相机始终看向载具(主体=载具,静止时不漂移)
	cam.look_at(v.pos + Vector3(0, 1.0, 0), Vector3.UP)
	var sh := _shake()
	cam.rotation_order = EULER_ORDER_YXZ
	cam.rotation.y += sh.x
	cam.rotation.x += sh.y
	cam.rotation.z = 0
