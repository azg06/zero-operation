class_name FirstPersonMotionSystem extends RefCounted
## ============================================================================
## Procedural First-Person Camera + Weapon Motion System
## ----------------------------------------------------------------------------
## 单一运动层控制器(Player 持有,每帧只 update 一次):
##   Movement Velocity + Acceleration + Mouse Delta + Player State + Weapon Weight
##     -> 状态参数插值(11 套预设)
##     -> 呼吸层 / Bob 层 / Sway 层 / Inertia 层 / Landing-Jump 冲量层
##     -> Spring / Damping
##     -> Camera Offset + Weapon Offset + Hand IK Offset
##
## 设计原则:
##   * 不用 sin(time)*amp 作为唯一晃动源;Bob 由“步距积分相位 + 多谐波叠加”驱动。
##   * Camera 与 Weapon 使用不同频率/幅度/相位,武器额外经过低刚度弹簧,天然滞后。
##   * 转向 Sway 使用带饱和的非线性鼠标速度,慢速自动接近 0。
##   * 急停/换向通过加速度目标 + 欠阻尼弹簧产生“前冲→回弹”的惯性。
##   * 全系统零每帧对象分配;所有弹簧预创建,参数均为标量/Vector3。
## ============================================================================

class Spring3 extends RefCounted:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO

	func update(target: Vector3, stiffness: float, damping: float, dt: float) -> void:
		var s := maxf(stiffness, 0.5)
		var d := maxf(damping, 0.0)
		vel = (vel + (target - pos) * (s * dt)) * exp(-d * dt)
		pos += vel * dt

	func impulse(v: Vector3) -> void:
		vel += v

	func snap(target: Vector3) -> void:
		pos = target
		vel = Vector3.ZERO

	func reset() -> void:
		pos = Vector3.ZERO
		vel = Vector3.ZERO


# 每套状态独立参数。标量全部集中于此;Vector3 参数由 VEC_KEYS 单独插值。
const PRESETS := {
	"idle": {
		"bob_freq": 0.95, "bob_amp": 0.0018, "bob_lat": 0.0007, "bob_fwd": 0.0003, "bob_rot": 0.0013,
		"wpn_bob_amp": 0.0042, "wpn_bob_lat": 0.0015, "wpn_bob_fwd": 0.0011, "wpn_bob_rot": 0.012, "wpn_bob_roll": 0.007,
		"sway_pos": 0.006, "sway_rot": 0.038,
		"inertia_pos": 0.010, "inertia_rot": 0.024,
		"spring_stiff": 62.0, "spring_damp": 9.0, "rot_stiff": 72.0, "rot_damp": 10.0,
		"hand_stiff": 20.0, "hand_damp": 7.5, "hand_follow": 0.55, "hand_bob": 0.0022,
		"breath_freq": 0.21, "breath_pos_amp": 0.00095, "breath_lat_amp": 0.00042, "breath_rot_amp": 0.00028,
		"cam_offset": Vector3.ZERO, "wpn_offset": Vector3.ZERO, "rot_offset": Vector3.ZERO,
	},
	"walk": {
		"bob_freq": 1.55, "bob_amp": 0.0060, "bob_lat": 0.0024, "bob_fwd": 0.0008, "bob_rot": 0.0050,
		"wpn_bob_amp": 0.0155, "wpn_bob_lat": 0.0055, "wpn_bob_fwd": 0.0035, "wpn_bob_rot": 0.055, "wpn_bob_roll": 0.028,
		"sway_pos": 0.010, "sway_rot": 0.062,
		"inertia_pos": 0.019, "inertia_rot": 0.052,
		"spring_stiff": 55.0, "spring_damp": 8.4, "rot_stiff": 66.0, "rot_damp": 9.6,
		"hand_stiff": 22.0, "hand_damp": 7.2, "hand_follow": 0.62, "hand_bob": 0.0075,
		"breath_freq": 0.27, "breath_pos_amp": 0.00082, "breath_lat_amp": 0.00036, "breath_rot_amp": 0.00022,
		"cam_offset": Vector3(0.0, -0.0008, 0.0), "wpn_offset": Vector3(0.0, -0.003, 0.001), "rot_offset": Vector3(0.0015, 0.0, 0.001),
	},
	"run": {
		"bob_freq": 1.78, "bob_amp": 0.0105, "bob_lat": 0.0045, "bob_fwd": 0.0015, "bob_rot": 0.010,
		"wpn_bob_amp": 0.027, "wpn_bob_lat": 0.0095, "wpn_bob_fwd": 0.0060, "wpn_bob_rot": 0.105, "wpn_bob_roll": 0.052,
		"sway_pos": 0.013, "sway_rot": 0.082,
		"inertia_pos": 0.031, "inertia_rot": 0.085,
		"spring_stiff": 50.0, "spring_damp": 7.6, "rot_stiff": 60.0, "rot_damp": 8.8,
		"hand_stiff": 24.0, "hand_damp": 6.6, "hand_follow": 0.70, "hand_bob": 0.014,
		"breath_freq": 0.34, "breath_pos_amp": 0.00068, "breath_lat_amp": 0.00030, "breath_rot_amp": 0.00018,
		"cam_offset": Vector3(0.0, -0.0015, 0.001), "wpn_offset": Vector3(0.0, -0.006, 0.003), "rot_offset": Vector3(0.003, 0.0, 0.002),
	},
	"sprint": {
		"bob_freq": 2.05, "bob_amp": 0.0165, "bob_lat": 0.0080, "bob_fwd": 0.0026, "bob_rot": 0.018,
		"wpn_bob_amp": 0.042, "wpn_bob_lat": 0.0175, "wpn_bob_fwd": 0.0105, "wpn_bob_rot": 0.175, "wpn_bob_roll": 0.085,
		"sway_pos": 0.016, "sway_rot": 0.105,
		"inertia_pos": 0.046, "inertia_rot": 0.125,
		"spring_stiff": 46.0, "spring_damp": 7.0, "rot_stiff": 55.0, "rot_damp": 8.0,
		"hand_stiff": 25.0, "hand_damp": 6.0, "hand_follow": 0.78, "hand_bob": 0.022,
		"breath_freq": 0.42, "breath_pos_amp": 0.00050, "breath_lat_amp": 0.00024, "breath_rot_amp": 0.00014,
		"cam_offset": Vector3(0.0, -0.0025, 0.0015), "wpn_offset": Vector3(0.0, -0.011, 0.005), "rot_offset": Vector3(0.005, 0.006, 0.004),
	},
	"crouch": {
		"bob_freq": 1.05, "bob_amp": 0.0032, "bob_lat": 0.0013, "bob_fwd": 0.0004, "bob_rot": 0.0028,
		"wpn_bob_amp": 0.0075, "wpn_bob_lat": 0.0030, "wpn_bob_fwd": 0.0018, "wpn_bob_rot": 0.026, "wpn_bob_roll": 0.013,
		"sway_pos": 0.008, "sway_rot": 0.050,
		"inertia_pos": 0.014, "inertia_rot": 0.038,
		"spring_stiff": 60.0, "spring_damp": 8.8, "rot_stiff": 70.0, "rot_damp": 9.8,
		"hand_stiff": 21.0, "hand_damp": 7.3, "hand_follow": 0.58, "hand_bob": 0.0038,
		"breath_freq": 0.24, "breath_pos_amp": 0.00088, "breath_lat_amp": 0.00038, "breath_rot_amp": 0.00024,
		"cam_offset": Vector3(0.0, -0.0012, 0.0), "wpn_offset": Vector3(0.0, -0.0015, 0.001), "rot_offset": Vector3(0.0008, 0.0, 0.0005),
	},
	"crouch_walk": {
		"bob_freq": 1.42, "bob_amp": 0.0080, "bob_lat": 0.0040, "bob_fwd": 0.0012, "bob_rot": 0.008,
		"wpn_bob_amp": 0.021, "wpn_bob_lat": 0.0090, "wpn_bob_fwd": 0.0045, "wpn_bob_rot": 0.080, "wpn_bob_roll": 0.038,
		"sway_pos": 0.011, "sway_rot": 0.070,
		"inertia_pos": 0.026, "inertia_rot": 0.072,
		"spring_stiff": 52.0, "spring_damp": 7.9, "rot_stiff": 62.0, "rot_damp": 9.0,
		"hand_stiff": 23.0, "hand_damp": 6.9, "hand_follow": 0.68, "hand_bob": 0.010,
		"breath_freq": 0.30, "breath_pos_amp": 0.00076, "breath_lat_amp": 0.00032, "breath_rot_amp": 0.00020,
		"cam_offset": Vector3(0.0, -0.0018, 0.001), "wpn_offset": Vector3(0.0, -0.005, 0.002), "rot_offset": Vector3(0.0022, 0.0, 0.0015),
	},
	"aim": {
		"bob_freq": 0.78, "bob_amp": 0.0007, "bob_lat": 0.0003, "bob_fwd": 0.0001, "bob_rot": 0.0006,
		"wpn_bob_amp": 0.0018, "wpn_bob_lat": 0.0008, "wpn_bob_fwd": 0.0005, "wpn_bob_rot": 0.008, "wpn_bob_roll": 0.004,
		"sway_pos": 0.0018, "sway_rot": 0.014,
		"inertia_pos": 0.008, "inertia_rot": 0.022,
		"spring_stiff": 78.0, "spring_damp": 11.0, "rot_stiff": 88.0, "rot_damp": 12.0,
		"hand_stiff": 28.0, "hand_damp": 9.0, "hand_follow": 0.45, "hand_bob": 0.0009,
		"breath_freq": 0.24, "breath_pos_amp": 0.00072, "breath_lat_amp": 0.00030, "breath_rot_amp": 0.00020,
		"cam_offset": Vector3.ZERO, "wpn_offset": Vector3.ZERO, "rot_offset": Vector3.ZERO,
	},
	"aim_walk": {
		"bob_freq": 1.02, "bob_amp": 0.0028, "bob_lat": 0.0012, "bob_fwd": 0.0004, "bob_rot": 0.0022,
		"wpn_bob_amp": 0.0055, "wpn_bob_lat": 0.0022, "wpn_bob_fwd": 0.0012, "wpn_bob_rot": 0.022, "wpn_bob_roll": 0.010,
		"sway_pos": 0.004, "sway_rot": 0.026,
		"inertia_pos": 0.013, "inertia_rot": 0.040,
		"spring_stiff": 68.0, "spring_damp": 10.0, "rot_stiff": 78.0, "rot_damp": 11.0,
		"hand_stiff": 26.0, "hand_damp": 8.4, "hand_follow": 0.50, "hand_bob": 0.0028,
		"breath_freq": 0.28, "breath_pos_amp": 0.00068, "breath_lat_amp": 0.00028, "breath_rot_amp": 0.00018,
		"cam_offset": Vector3.ZERO, "wpn_offset": Vector3(0.0, -0.0015, 0.0), "rot_offset": Vector3(0.0008, 0.0, 0.0005),
	},
	"aim_sprint": {
		"bob_freq": 1.25, "bob_amp": 0.0060, "bob_lat": 0.0028, "bob_fwd": 0.0010, "bob_rot": 0.005,
		"wpn_bob_amp": 0.012, "wpn_bob_lat": 0.0055, "wpn_bob_fwd": 0.0030, "wpn_bob_rot": 0.050, "wpn_bob_roll": 0.022,
		"sway_pos": 0.006, "sway_rot": 0.040,
		"inertia_pos": 0.020, "inertia_rot": 0.060,
		"spring_stiff": 58.0, "spring_damp": 8.8, "rot_stiff": 66.0, "rot_damp": 9.6,
		"hand_stiff": 24.0, "hand_damp": 7.6, "hand_follow": 0.58, "hand_bob": 0.0055,
		"breath_freq": 0.32, "breath_pos_amp": 0.00060, "breath_lat_amp": 0.00026, "breath_rot_amp": 0.00016,
		"cam_offset": Vector3(0.0, -0.001, 0.0008), "wpn_offset": Vector3(0.0, -0.004, 0.002), "rot_offset": Vector3(0.002, 0.0, 0.001),
	},
	"jump": {
		"bob_freq": 1.35, "bob_amp": 0.0035, "bob_lat": 0.0018, "bob_fwd": 0.0012, "bob_rot": 0.006,
		"wpn_bob_amp": 0.009, "wpn_bob_lat": 0.004, "wpn_bob_fwd": 0.005, "wpn_bob_rot": 0.045, "wpn_bob_roll": 0.020,
		"sway_pos": 0.011, "sway_rot": 0.070,
		"inertia_pos": 0.038, "inertia_rot": 0.100,
		"spring_stiff": 40.0, "spring_damp": 5.6, "rot_stiff": 46.0, "rot_damp": 6.4,
		"hand_stiff": 20.0, "hand_damp": 5.6, "hand_follow": 0.70, "hand_bob": 0.006,
		"breath_freq": 0.38, "breath_pos_amp": 0.00062, "breath_lat_amp": 0.00028, "breath_rot_amp": 0.00018,
		"cam_offset": Vector3(0.0, 0.004, -0.002), "wpn_offset": Vector3(0.0, 0.008, -0.004), "rot_offset": Vector3(0.006, 0.0, 0.003),
	},
	"landing": {
		"bob_freq": 1.15, "bob_amp": 0.0028, "bob_lat": 0.0012, "bob_fwd": 0.0010, "bob_rot": 0.005,
		"wpn_bob_amp": 0.007, "wpn_bob_lat": 0.003, "wpn_bob_fwd": 0.005, "wpn_bob_rot": 0.040, "wpn_bob_roll": 0.018,
		"sway_pos": 0.009, "sway_rot": 0.060,
		"inertia_pos": 0.055, "inertia_rot": 0.135,
		"spring_stiff": 78.0, "spring_damp": 15.0, "rot_stiff": 84.0, "rot_damp": 15.0,
		"hand_stiff": 26.0, "hand_damp": 12.0, "hand_follow": 0.74, "hand_bob": 0.004,
		"breath_freq": 0.36, "breath_pos_amp": 0.00066, "breath_lat_amp": 0.00030, "breath_rot_amp": 0.00020,
		"cam_offset": Vector3(0.0, -0.005, 0.004), "wpn_offset": Vector3(0.0, 0.007, -0.007), "rot_offset": Vector3(0.010, 0.0, 0.004),
	},
}

const PARAM_KEYS: Array[String] = [
	"bob_freq", "bob_amp", "bob_lat", "bob_fwd", "bob_rot",
	"wpn_bob_amp", "wpn_bob_lat", "wpn_bob_fwd", "wpn_bob_rot", "wpn_bob_roll",
	"sway_pos", "sway_rot",
	"inertia_pos", "inertia_rot",
	"spring_stiff", "spring_damp", "rot_stiff", "rot_damp",
	"hand_stiff", "hand_damp", "hand_follow", "hand_bob",
	"breath_freq", "breath_pos_amp", "breath_lat_amp", "breath_rot_amp",
]

const VEC_KEYS: Array[String] = ["cam_offset", "wpn_offset", "rot_offset"]

# 武器类别基准重量(步枪=1.0)。数值越大:Bob/Sway/惯性越大、弹簧越软。
const KIND_WEIGHT := {
	"pistol": 0.72, "smg": 0.84, "rifle": 1.0, "shotgun": 1.08,
	"dmr": 1.12, "lmg": 1.24, "sniper": 1.2, "rpg": 1.35,
}

var _player_ref: WeakRef = null
var _cur: Dictionary = PRESETS["idle"].duplicate()
var _state := "idle"
var _land_t := 0.0

var _phase := 0.0                # 步距积分相位(rad)
var _breath_phase := 0.0
var _bob_speed := 0.0            # 平滑后的移动速度(用于 Bob 强度)
var _last_vel := Vector3.ZERO
var _accel_smooth := Vector3.ZERO

var _mouse_input := Vector2.ZERO
var _mouse_vel := Vector2.ZERO
var _mouse_sway_amp := 0.0
var _mouse_sway_dir := Vector3.ZERO
var _mouse_sway_rot_dir := Vector3.ZERO
var _anim_keep := 1.0              # 换弹/拔枪时程序层平滑让位(禁止硬切)

var _cam_bob := Vector3.ZERO
var _cam_breath := Vector3.ZERO
var _cam_breath_rot := Vector3.ZERO
var _cam_bob_rot := Vector3.ZERO
var _turn_roll := 0.0

var _camera_pos := Vector3.ZERO
var _camera_rot := Vector3.ZERO

# 武器目标在 apply_weapon 中按当前枪械重量/呼吸配置计算
var _weapon_bob_pos := Vector3.ZERO
var _weapon_bob_rot := Vector3.ZERO
var _inertia_target := Vector3.ZERO
var _inertia_rot_target := Vector3.ZERO
var _weapon_inertia_rot := Vector3.ZERO

# 弹簧(预创建,零每帧分配)
var _cam_inertia := Spring3.new()
var _cam_inertia_rot := Spring3.new()
var _cam_impulse := Spring3.new()
var _weapon_pos := Spring3.new()
var _weapon_rot := Spring3.new()
var _hand_pos := Spring3.new()
var _hand_rot := Spring3.new()


func _init(p) -> void:
	_player_ref = weakref(p)
	_last_vel = p.vel if p != null else Vector3.ZERO


## 玩家重生/上下车/恢复控制时调用,清掉所有残留运动。
func reset(velocity := Vector3.ZERO) -> void:
	_state = "idle"
	_cur = PRESETS["idle"].duplicate()
	_land_t = 0.0
	_phase = 0.0
	_bob_speed = velocity.length()
	_last_vel = velocity
	_accel_smooth = Vector3.ZERO
	_mouse_input = Vector2.ZERO
	_mouse_vel = Vector2.ZERO
	_mouse_sway_amp = 0.0
	_mouse_sway_dir = Vector3.ZERO
	_mouse_sway_rot_dir = Vector3.ZERO
	_anim_keep = 1.0
	_cam_bob = Vector3.ZERO
	_cam_breath = Vector3.ZERO
	_cam_breath_rot = Vector3.ZERO
	_cam_bob_rot = Vector3.ZERO
	_turn_roll = 0.0
	_camera_pos = Vector3.ZERO
	_camera_rot = Vector3.ZERO
	_weapon_bob_pos = Vector3.ZERO
	_weapon_bob_rot = Vector3.ZERO
	_inertia_target = Vector3.ZERO
	_inertia_rot_target = Vector3.ZERO
	_weapon_inertia_rot = Vector3.ZERO
	_cam_inertia.reset()
	_cam_inertia_rot.reset()
	_cam_impulse.reset()
	_weapon_pos.reset()
	_weapon_rot.reset()
	_hand_pos.reset()
	_hand_rot.reset()


## 当前帧鼠标增量(在 apply_look 后立即喂入,内部转为带衰减的速度)。
func input_mouse(dx: float, dy: float) -> void:
	_mouse_input.x += dx
	_mouse_input.y += dy


func notify_jump() -> void:
	_cam_impulse.impulse(Vector3(0.0, 0.010, -0.004))
	_weapon_pos.impulse(Vector3(0.0, 0.014, -0.009))
	_weapon_rot.impulse(Vector3(0.012, 0.0, 0.0))


func notify_landing(impact: float) -> void:
	_land_t = 0.52
	var k := clampf(impact / 7.0, 0.18, 1.0)
	var diag := clampf(impact / 12.0, 0.0, 1.0)
	_cam_impulse.impulse(Vector3(0.0, -0.012 - 0.010 * diag, 0.006 + 0.004 * diag))
	_weapon_pos.impulse(Vector3(0.0, -0.007 - 0.011 * k, 0.009 + 0.013 * k))
	_weapon_rot.impulse(Vector3(0.010 + 0.020 * k, 0.0, 0.0))
	_hand_pos.impulse(Vector3(0.0, -0.005 * k, 0.0035 * k))


func on_weapon_equipped(_g = null) -> void:
	# 切枪瞬间不要让旧枪弹簧延续到新枪;重量差异从 0 开始重新建立。
	_weapon_pos.reset()
	_weapon_rot.reset()
	_hand_pos.reset()
	_hand_rot.reset()
	_weapon_bob_pos = Vector3.ZERO
	_weapon_bob_rot = Vector3.ZERO
	_weapon_inertia_rot = Vector3.ZERO


func _resolve_state(p: Player) -> String:
	if p == null or not p.alive:
		return "idle"
	if _land_t > 0.0 and p.on_ground:
		return "landing"
	if not p.on_ground:
		return "jump"
	var speed := Vector2(p.vel.x, p.vel.z).length()
	var g := p.gun()
	var ads := g.ads_amount if g != null else 0.0
	if p.slide_t > 0.0:
		return "crouch_walk"
	if p.prone:
		return "crouch_walk" if speed > 0.5 else "crouch"
	if p.crouched:
		return "crouch_walk" if speed > 0.55 else "crouch"
	if ads > 0.55:
		if speed > 3.6:
			return "aim_sprint"
		return "aim_walk" if speed > 0.7 else "aim"
	var sp := p.sprint_amount
	if sp > 0.16:
		return "run" if sp < 0.78 else "sprint"
	if speed > 5.2 and sp > 0.0:
		return "sprint"
	if speed > 0.45:
		return "walk"
	return "idle"


## 每帧主更新:必须在 Gun.update 之前调用。
func update(dt: float) -> void:
	var p := _player_ref.get_ref() as Player
	if p == null:
		return
	dt = clampf(dt, 0.001, 0.05)

	_land_t = maxf(0.0, _land_t - dt)
	_state = _resolve_state(p)

	# --- 状态参数平滑插值:切换状态永不硬切 ---
	var target: Dictionary = PRESETS[_state]
	var blend_speed := 13.0 if _state == "landing" else 7.5
	var blend := 1.0 - exp(-blend_speed * dt)
	for key in PARAM_KEYS:
		_cur[key] = Utils.lerpf(float(_cur[key]), float(target[key]), blend)
	for key in VEC_KEYS:
		var cv: Vector3 = _cur[key]
		var tv: Vector3 = target[key]
		_cur[key] = cv.lerp(tv, blend)

	# --- 输入:速度 / 加速度 / 鼠标 ---
	var vel := p.vel
	var accel := (vel - _last_vel) / dt
	_last_vel = vel
	var al := accel.length()
	if al > 70.0:
		accel *= 70.0 / al
	_accel_smooth = _accel_smooth.lerp(accel, 1.0 - exp(-10.0 * dt))

	var speed := Vector2(vel.x, vel.z).length()
	_bob_speed = Utils.damp(_bob_speed, speed, 9.0, dt)
	var spd_k := clampf(_bob_speed / 5.6, 0.0, 1.0)
	if _bob_speed < 0.05:
		spd_k = 0.0

	var yaw := p.yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var flat_a := Vector3(_accel_smooth.x, 0.0, _accel_smooth.z)
	var fwd_a := flat_a.dot(fwd)
	var strafe_a := flat_a.dot(right)
	var local_vx := vel.x * right.x + vel.z * right.z
	var strafe_k := clampf(absf(local_vx) / 2.6, 0.0, 1.0)
	var strafe_sign := 1.0 if local_vx >= 0.0 else -1.0

	# 鼠标速度(像素/秒 → 近似 rad/s,使用玩家灵敏度;饱和防单帧尖峰)
	var sens: float = 0.0022 * float(G.settings.sensitivity)
	if dt > 0.0001:
		var inst := _mouse_input / dt
		_mouse_vel = _mouse_vel.lerp(inst, 1.0 - exp(-18.0 * dt))
	_mouse_input = Vector2.ZERO
	var yaw_rate := clampf(_mouse_vel.x * sens, -8.0, 8.0)
	var pitch_rate := clampf(_mouse_vel.y * sens, -6.0, 6.0)
	var mouse_spd := Vector2(yaw_rate, pitch_rate).length()
	var raw_amp := clampf(mouse_spd / 3.4, 0.0, 1.0)
	_mouse_sway_amp = raw_amp * raw_amp  # 慢鼠标平方衰减 → 瞄准时几乎无 Sway
	var inv_spd := 1.0 / maxf(mouse_spd, 0.001)
	_mouse_sway_dir = Vector3(-yaw_rate, -pitch_rate, -yaw_rate * 0.22) * inv_spd
	_mouse_sway_rot_dir = Vector3(pitch_rate, -yaw_rate, -yaw_rate * 0.62) * inv_spd
	_turn_roll = Utils.damp(_turn_roll, clampf(-yaw_rate * 0.0032, -0.020, 0.020), 14.0, dt)

	# --- 步距相位:距离积分,不用 wall-clock sin ---
	# bob_freq 单位是 rad/m:直接乘当前速度(m/s)得到 rad/s。
	# 这里不能再乘 TAU,否则步频会高出 6.28 倍,武器弹簧会把 Bob 全部滤掉,
	# 表现为走路/奔跑时枪械几乎没有自然晃动。
	var bob_freq := float(_cur["bob_freq"])
	_phase += dt * _bob_speed * bob_freq
	_phase = fmod(_phase, TAU)
	var wp := _phase

	# --- Camera Bob(多谐波叠加;cam 与 weapon 相位/频率不同) ---
	var bamp := float(_cur["bob_amp"]) * spd_k
	var blat := float(_cur["bob_lat"]) * spd_k
	var bfwd := float(_cur["bob_fwd"]) * spd_k
	var cam_bob_target := Vector3(
		(sin(wp * 0.5 + 0.55) * 0.68 + sin(wp * 1.37 + 1.2) * 0.32) * blat
			+ strafe_sign * strafe_k * blat * 0.85,
		(sin(wp) * 0.72 + sin(wp * 2.0 + 0.4) * 0.28) * bamp,
		(sin(wp + 0.9) * 0.42 + sin(wp * 2.0 + 1.15) * 0.18) * bfwd)
	_cam_bob = _cam_bob.lerp(cam_bob_target, 1.0 - exp(-16.0 * dt))

	var brot := float(_cur["bob_rot"]) * spd_k
	_cam_bob_rot = _cam_bob_rot.lerp(Vector3(
		(sin(wp * 0.5 + 0.3) * 0.7 + sin(wp * 1.31 + 1.7) * 0.3) * brot,
		(sin(wp * 1.0 + 0.9) * 0.55 + sin(wp * 0.61 + 2.2) * 0.45) * brot * 0.5,
		(sin(wp * 0.5 + 0.1) * 0.75 + strafe_sign * strafe_k * 0.25) * brot * 0.9), 1.0 - exp(-14.0 * dt))

	# --- Weapon Bob 目标(apply_weapon 按枪重缩放) ---
	var wba := float(_cur["wpn_bob_amp"]) * spd_k
	var wbl := float(_cur["wpn_bob_lat"]) * spd_k
	var wbf := float(_cur["wpn_bob_fwd"]) * spd_k
	_weapon_bob_pos = Vector3(
		(sin(wp * 0.5 + 1.05) * 0.62 + sin(wp * 1.45 + 0.4) * 0.38) * wbl
			+ strafe_sign * strafe_k * wbl * 1.15,
		(sin(wp + 0.35) * 0.66 + sin(wp * 2.0 + 0.9) * 0.34) * wba,
		(sin(wp + 1.5) * 0.45 + sin(wp * 2.0 + 0.6) * 0.22) * wbf)
	var wbr := float(_cur["wpn_bob_rot"]) * spd_k
	var wbrl := float(_cur["wpn_bob_roll"]) * spd_k
	_weapon_bob_rot = Vector3(
		(sin(wp + 0.7) * 0.58 + sin(wp * 2.0 + 0.25) * 0.42) * wbr,
		(sin(wp * 0.5 + 0.8) * 0.62 + sin(wp * 1.5 + 1.9) * 0.38) * wbrl
			+ strafe_sign * strafe_k * wbrl * 0.9,
		(sin(wp * 0.5 + 0.2) * 0.7 + sin(wp + 2.35) * 0.3) * wbrl
			+ strafe_sign * strafe_k * wbrl * 0.45)

	# --- 加速度惯性目标(武器滞后/前冲,相机只取小比例且弹簧更硬) ---
	var ipos := float(_cur["inertia_pos"])
	var irot := float(_cur["inertia_rot"])
	_inertia_target = Vector3(-strafe_a * ipos * 0.0011, 0.0, fwd_a * ipos * 0.0012)
	_inertia_rot_target = Vector3(-fwd_a * irot * 0.0005, -strafe_a * irot * 0.00055, strafe_a * irot * 0.00042)
	_cam_inertia.update(_inertia_target * 0.30, 68.0, 11.0, dt)
	_cam_inertia_rot.update(_inertia_rot_target * 0.30, 64.0, 10.0, dt)
	_weapon_inertia_rot = _inertia_rot_target

	# --- 呼吸(慢速、低幅、多谐波;相位连续,绝不随机) ---
	var bfreq := float(_cur["breath_freq"]) * (1.0 + p.sprint_amount * 0.65)
	_breath_phase += dt * bfreq * TAU
	_breath_phase = fmod(_breath_phase, TAU)
	var bp := _breath_phase
	var bpa := float(_cur["breath_pos_amp"])
	var bla := float(_cur["breath_lat_amp"])
	var bra := float(_cur["breath_rot_amp"])
	_cam_breath = Vector3(
		(sin(bp * 0.83 + 1.2) * 0.75 + sin(bp * 1.61 + 0.4) * 0.25) * bla,
		(sin(bp) * 0.68 + sin(bp * 0.47 + 2.1) * 0.32) * bpa,
		(sin(bp * 0.61 + 0.9) * 0.5 + sin(bp * 1.19 + 2.6) * 0.22) * bpa * 0.4)
	_cam_breath_rot = Vector3(
		sin(bp * 0.53 + 0.7) * bra,
		sin(bp * 0.71 + 2.4) * bra * 0.7,
		sin(bp * 0.39 + 1.0) * bra * 0.6)

	# --- Camera 输出汇总 ---
	_cam_impulse.update(Vector3.ZERO, 74.0, 9.5, dt)
	_camera_pos = (Vector3(_cur["cam_offset"]) if _cur["cam_offset"] is Vector3 else Vector3.ZERO) \
		+ _cam_breath + _cam_bob + _cam_inertia.pos + _cam_impulse.pos
	_camera_rot = (Vector3(_cur["rot_offset"]) if _cur["rot_offset"] is Vector3 else Vector3.ZERO) \
		+ _cam_breath_rot + _cam_bob_rot + _cam_inertia_rot.pos \
		+ Vector3(_cam_impulse.pos.x * 1.4, 0.0, _turn_roll)


## 枪械视角模型最终运动层(Gun.update 调用;必须在 reload/bolt/pump 之前加入)。
func apply_weapon(g, dt: float) -> void:
	if g == null or g.group == null or not is_instance_valid(g.group):
		return
	var w: float = float(g.motion_weight)
	var phase: float = _phase + float(g.motion_bob_phase)

	# 每把枪独立呼吸相位推进(频率倍率来自 Gun 的确定性配置,绝不与其他枪同频同相)。
	var sprint_boost: float = 1.0 + float(g.player.sprint_amount) * 0.65 if g.player != null else 1.0
	g.motion_breath_phase = fmod(g.motion_breath_phase \
		+ dt * float(_cur["breath_freq"]) * float(g.motion_breath_freq_mult) * sprint_boost * TAU, TAU)
	var breath_phase: float = float(g.motion_breath_phase)

	# 换弹/拔枪时程序层收缩,把表演空间让给动画系统;目标切换本身仍走阻尼,无跳变。
	var anim_target: float = 0.30 if (g.reloading or g.draw_t < 0.85) else 1.0
	_anim_keep = Utils.damp(_anim_keep, anim_target, 9.0, dt)
	var anim_keep := _anim_keep

	var sway_amp: float = _mouse_sway_amp * float(_cur["sway_pos"]) * w * anim_keep
	var sway_rot_amp: float = _mouse_sway_amp * float(_cur["sway_rot"]) * w * anim_keep
	var sway_pos_target: Vector3 = _mouse_sway_dir * sway_amp
	var sway_rot_target: Vector3 = _mouse_sway_rot_dir * sway_rot_amp

	var wpn_base: Vector3 = _cur["wpn_offset"]
	var rot_base: Vector3 = _cur["rot_offset"]

	# 每把枪独立的呼吸频率/幅度/相位(由 Gun 的确定性配置提供)
	var bamp: float = float(g.motion_breath_amp_mult) * float(_cur["breath_pos_amp"]) * w
	var blamp: float = float(g.motion_breath_amp_mult) * float(_cur["breath_lat_amp"]) * w
	var bramp: float = float(g.motion_breath_amp_mult) * float(_cur["breath_rot_amp"]) * w
	var breath_pos := Vector3(
		(sin(breath_phase * 0.79 + 0.8) * 0.72 + sin(breath_phase * 1.53 + 1.9) * 0.28) * blamp,
		(sin(breath_phase) * 0.64 + sin(breath_phase * 0.51 + 1.3) * 0.36) * bamp,
		(sin(breath_phase * 0.57 + 2.0) * 0.5 + sin(breath_phase * 1.13 + 0.2) * 0.2) * bamp * 0.42)
	var breath_rot := Vector3(
		sin(breath_phase * 0.49 + 1.5) * bramp,
		sin(breath_phase * 0.67 + 0.2) * bramp * 0.75,
		sin(breath_phase * 0.35 + 2.2) * bramp * 0.6)

	var inertia_pos: Vector3 = _inertia_target * w * anim_keep
	var inertia_rot: Vector3 = _weapon_inertia_rot * w * anim_keep

	var pos_target: Vector3 = wpn_base * (0.35 + 0.65 * anim_keep) \
		+ (_weapon_bob_pos * w * anim_keep) + breath_pos + sway_pos_target + inertia_pos
	var rot_target: Vector3 = rot_base * (0.35 + 0.65 * anim_keep) \
		+ (_weapon_bob_rot * w * anim_keep) + breath_rot + sway_rot_target + inertia_rot

	var stiff_mult: float = 1.0 / (0.62 + 0.38 * w)
	_weapon_pos.update(pos_target, float(_cur["spring_stiff"]) * stiff_mult, float(_cur["spring_damp"]), dt)
	_weapon_rot.update(rot_target, float(_cur["rot_stiff"]) * stiff_mult, float(_cur["rot_damp"]), dt)

	g.group.position += _weapon_pos.pos
	g.group.rotation += _weapon_rot.pos

	# --- 双手 IK:跟随武器弹簧状态再滞后一拍,左右手反向补偿 ---
	var hand_target := _weapon_pos.pos * float(_cur["hand_follow"]) \
		+ Vector3(
			sin(phase * 0.5 + 0.4) * float(_cur["hand_bob"]) * w * spd01(),
			sin(phase + 1.1) * float(_cur["hand_bob"]) * 0.6 * w * spd01(),
			sin(phase * 1.5 + 0.9) * float(_cur["hand_bob"]) * 0.45 * w * spd01()) * anim_keep
	var hand_rot_target := _weapon_rot.pos * float(_cur["hand_follow"]) * 0.8
	_hand_pos.update(hand_target, float(_cur["hand_stiff"]), float(_cur["hand_damp"]), dt)
	_hand_rot.update(hand_rot_target, float(_cur["hand_stiff"]), float(_cur["hand_damp"]), dt)

	var hpos := _hand_pos.pos * anim_keep
	var hrot := _hand_rot.pos * anim_keep
	if g._right_hand != null:
		g._right_hand.position += Vector3(hpos.x * 0.55, hpos.y * 0.75, hpos.z * 0.6)
		g._right_hand.rotation += Vector3(hrot.x * 0.6, hrot.y * 0.5, hrot.z * 0.6)
	if g._left_hand != null:
		g._left_hand.position += Vector3(-hpos.x * 0.45, hpos.y * 0.55, hpos.z * 0.38)
		g._left_hand.rotation += Vector3(hrot.x * 0.45, -hrot.y * 0.4, -hrot.z * 0.45)


## 当前 Bob 强度系数(0~1),供双手/调试使用。
func spd01() -> float:
	return clampf(_bob_speed / 5.6, 0.0, 1.0)


## 相机本地空间位置偏移(由 Player 用相机 basis 变换)。
func camera_position() -> Vector3:
	return _camera_pos


## 当前武器弹簧位置偏移(视角模型局部空间;调试/测试用)。
func weapon_offset() -> Vector3:
	return _weapon_pos.pos


## 当前武器弹簧旋转偏移(视角模型局部空间;调试/测试用)。
func weapon_rotation_offset() -> Vector3:
	return _weapon_rot.pos


## 相机欧拉角增量(Player 直接叠加到 pitch/yaw/roll)。
func camera_rotation() -> Vector3:
	return _camera_rot


## 步距相位(rad;腿/脚动画复用,避免出现第二套 bob)。
func stride_phase() -> float:
	return _phase


## 当前运动状态名(调试/HUD 诊断用)。
func state_name() -> String:
	return _state
