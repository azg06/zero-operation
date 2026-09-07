class_name FirstPersonVehicleController
extends Node3D
## 现代载具第一人称乘员系统(统一控制器)
##
## 架构原则:
##   * 每个车型声明自己的座位/观瞄/FOV/晃动/反馈配置,不复制整套视角逻辑
##   * 驾驶位 = 车体锚点(继承车体起伏/俯仰/侧倾),炮手/车长/炮镜 = 炮塔锚点
##   * 岗位切换使用车内短弧线过渡(不黑屏、不瞬移、不穿到车外)
##   * 火炮指向、炮手视线、观瞄分划三者共用同一 bore direction
##
## 状态机:
##   THIRD_PERSON → FP_DRIVER → FP_GUNNER → FP_OPTIC
##   FP_OPTIC 是 FP_GUNNER 的“目镜模式”:炮手仍控制火炮,观瞄电子分划由 HUD 叠加。

enum VehView { THIRD_PERSON, FP_DRIVER, FP_GUNNER, FP_OPTIC }
enum OpticMode { DAY, THERMAL, NIGHT }
enum Station { DRIVER, GUNNER, OBSERVER }

const LOOK_YAW_MAX := 2.0
const LOOK_PITCH_UP := 1.22
const LOOK_PITCH_DOWN := -1.05
const FP_FOV := 86.0

## 车型 → 乘员位配置(局部坐标与 vehicle_models.gd 的内构几何对齐)
## opt 为观瞄目镜/电子观瞄设备位置;所有炮塔位随 turret 旋转。
const STATION_CFG := {
	# 坐标与 GLB 建模(build_vehicle_batch)对齐:
	#   tank 炮塔节点原点 (0,1.80,0.20),炮塔壳 world 1.47..1.97
	#   apc  炮塔节点原点 (0,2.14,-0.30),炮塔壳 world 2.07..2.41
	#   aa   平台节点原点 (0,1.68,0.85),平台顶 world 1.85(敞开炮座)
	"tank": {
		"driver": { "pos": Vector3(0.0, 1.30, 0.35), "fov": 86.0 },
		# [FIX] 炮手/观瞄眼位抬到炮塔壳顶上方(world 1.80+0.32=2.12 > 壳顶 1.97),
		# 敞开舱盖观察 —— 旧版 0.02(world 1.82)整颗头埋在壳内,
		# ADS 下半屏被炮塔壳内壁挡住 45%(qa_veh_tank_ads 实锤)
		"gunner": { "pos": Vector3(0.0, 0.32, -0.55), "fov": 86.0 },
		"optic": { "pos": Vector3(0.28, 0.32, -0.85), "fov": 40.0 },
		"motion": {
			"vibe": 0.0045, "accel_pitch": 0.007,
			"brake_pitch": 0.005, "steer_roll": 0.012,
			"recoil_pitch": 0.016, "recoil_yaw": 0.006, "recoil_roll": 0.005,
			"recoil_pos_z": 0.07, "recoil_decay": 4.2,
		},
		"reticle": "tank",
	},
	"aa": {
		"driver": { "pos": Vector3(0.0, 1.60, -1.50), "fov": 86.0 },
		"gunner": { "pos": Vector3(0.0, 0.67, -0.35), "fov": 86.0 },
		"optic": { "pos": Vector3(0.30, 0.69, -0.70), "fov": 46.0 },
		"motion": {
			"vibe": 0.0065, "accel_pitch": 0.008,
			"brake_pitch": 0.006, "steer_roll": 0.015,
			"recoil_pitch": 0.0032, "recoil_yaw": 0.0022, "recoil_roll": 0.0018,
			"recoil_pos_z": 0.012, "recoil_decay": 11.0,
		},
		"reticle": "aa",
	},
	"apc": {
		"driver": { "pos": Vector3(0.0, 1.38, -1.85), "fov": 86.0 },
		# [FIX] 炮手/观瞄眼位抬到炮塔壳顶上方(world 2.14+0.32=2.46 > 壳顶 2.41),
		# 敞开炮座观察 —— 旧版 0.10(world 2.24)被内饰顶棚 2.32 夹出 0.1m 视缝
		"gunner": { "pos": Vector3(0.0, 0.32, -0.50), "fov": 86.0 },
		"optic": { "pos": Vector3(0.0, 0.32, -0.55), "fov": 44.0 },
		"motion": {
			"vibe": 0.0055, "accel_pitch": 0.007,
			"brake_pitch": 0.005, "steer_roll": 0.014,
			"recoil_pitch": 0.0030, "recoil_yaw": 0.0020, "recoil_roll": 0.0016,
			"recoil_pos_z": 0.012, "recoil_decay": 11.0,
		},
		"reticle": "autocannon",
	},
	"jeep": {
		"driver": { "pos": Vector3(-0.45, 1.62, 0.45), "fov": 86.0 },
		"gunner": { "pos": Vector3(0.45, 1.62, 0.45), "fov": 86.0 },
		"optic": { "pos": Vector3.ZERO, "fov": 86.0 },
		"motion": {
			"vibe": 0.007, "accel_pitch": 0.009,
			"brake_pitch": 0.007, "steer_roll": 0.018,
			"recoil_pitch": 0.004, "recoil_yaw": 0.002, "recoil_roll": 0.002,
			"recoil_pos_z": 0.01, "recoil_decay": 9.0,
		},
		"reticle": "none",
	},
}

const SENS := 0.0022

var vehicle = null
var view := VehView.THIRD_PERSON
var look_yaw := 0.0
var look_pitch := 0.0
var station := Station.DRIVER
var optic_mode := OpticMode.DAY

# ---- 第三人称环绕 ----
var _tp_orbit_yaw := 0.0
var _tp_orbit_pitch := 0.0

# ---- 座位/观瞄锚点 ----
var _cannon_tube: Node3D = null      # ADS 时隐藏的炮管网格(CannonTube)
var _seats: Node3D = null
var _driver_seat: Node3D = null
var _gunner_seat: Node3D = null
var _optic: Node3D = null

# ---- 相机平滑与岗位过渡 ----
var _render_xf := Transform3D()
var _trans_from := Transform3D()
var _trans_t := -1.0
var _trans_dur := 0.38
var _trans_veh_pos := Vector3.ZERO
var _last_view := -1
var _last_station := -1
var _gunner_mode := false

# ---- 悬挂/惯性/机械反馈(全部指数平滑,不跳帧) ----
var _accel_s := 0.0
var _steer_s := 0.0
var _pos_off := Vector3.ZERO
var _rot_off := Vector3.ZERO
var _impact_t := -1.0
var _impact_amp := 0.0
var _prev_speed := 0.0
var _prev_turret_yaw := 0.0
var _prev_turret_pitch := 0.0
var _turret_rate := 0.0

# ---- 武器后坐/视觉冲击(由 Vehicle 通知) ----
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _recoil_roll := 0.0
var _recoil_pos_z := 0.0

# ---- 传感器/火控(激光测距、目标指示、雷达接触) ----
var laser_range := 0.0
var target_locked := false
var target_range := 0.0
var target_bearing_deg := 0.0
var radar_contacts := 0
var _lock_t := 0.0
var _sensor_tick := 0.0


func _init(v) -> void:
	vehicle = v
	name = "FirstPersonVehicleController"


func _ready() -> void:
	_seats = Node3D.new()
	_seats.name = "Seats"
	add_child(_seats)
	_driver_seat = _make_seat("DriverSeat")
	_gunner_seat = _make_seat("GunnerSeat")
	_optic = _make_seat("GunnerOptic")
	_render_xf = Transform3D(Basis(), vehicle.pos + Vector3(0, 2, 0))


func _make_seat(seat_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = seat_name
	_seats.add_child(n)
	return n


func reset() -> void:
	view = VehView.THIRD_PERSON
	look_yaw = 0.0
	look_pitch = 0.0
	_tp_orbit_yaw = 0.0
	_tp_orbit_pitch = 0.0
	_last_view = -1
	_last_station = -1
	_trans_t = -1.0
	_gunner_mode = false
	station = Station.DRIVER
	_pos_off = Vector3.ZERO
	_rot_off = Vector3.ZERO
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_recoil_roll = 0.0
	_recoil_pos_z = 0.0
	laser_range = 0.0
	target_locked = false
	target_range = 0.0
	_lock_t = 0.0
	optic_mode = OpticMode.DAY
	_apply_optic_effects()


## 兼容旧接口:上车时设置玩家实际座位(0=驾驶,1=炮手/乘客)
func set_gunner_mode(on: bool) -> void:
	_gunner_mode = on
	if on:
		if station == Station.DRIVER:
			station = Station.GUNNER
	elif station != Station.DRIVER:
		station = Station.DRIVER


## 乘员岗位:0=驾驶位 1=炮手位
func set_station(s: int) -> void:
	if s == station:
		return
	station = clampi(s, Station.DRIVER, Station.OBSERVER)


## 战地式:炮手位(驾驶+开炮一体)在任何视角下炮塔都跟随相机瞄准并可开火;
## 观察位不驱动炮塔。
func turret_chase() -> bool:
	return _gunner_mode and station == Station.GUNNER


func apply_look(dx: float, dy: float) -> void:
	var sens: float = SENS * float(G.settings.get("sensitivity", 1.0))
	look_yaw = clampf(look_yaw - dx * sens, -LOOK_YAW_MAX, LOOK_YAW_MAX)
	look_pitch = clampf(look_pitch - dy * sens, LOOK_PITCH_DOWN, LOOK_PITCH_UP)


func apply_tp_orbit(dx: float, dy: float) -> void:
	var sens: float = SENS * float(G.settings.get("sensitivity", 1.0))
	_tp_orbit_yaw = wrapf(_tp_orbit_yaw - dx * sens, -PI, PI)
	_tp_orbit_pitch = clampf(_tp_orbit_pitch + dy * sens, -0.85, 0.9)


## 观瞄模式循环:白光 → 热成像 → 微光夜视
func cycle_optic_mode() -> int:
	optic_mode = (int(optic_mode) + 1) % 3
	_apply_optic_effects()
	return int(optic_mode)


func set_optic_mode(mode: int) -> void:
	var next: int = clampi(mode, OpticMode.DAY, OpticMode.NIGHT)
	if next == optic_mode:
		return
	optic_mode = next
	_apply_optic_effects()


func deactivate_optic_modes() -> void:
	optic_mode = OpticMode.DAY
	_apply_optic_effects()


func _apply_optic_effects() -> void:
	if G.effects == null:
		return
	if G.effects.has_method("set_night_vision"):
		G.effects.set_night_vision(optic_mode == OpticMode.NIGHT)
	if G.effects.has_method("set_thermal_vision"):
		G.effects.set_thermal_vision(optic_mode == OpticMode.THERMAL)


func _cfg() -> Dictionary:
	return STATION_CFG.get(vehicle.type, STATION_CFG["jeep"])


func _station_cfg(s: int) -> Dictionary:
	var cfg := _cfg()
	if s == Station.GUNNER:
		return cfg.get("gunner", cfg["driver"])
	return cfg.get("driver", cfg["driver"])


func _station_anchor(s: int) -> Node3D:
	if s == Station.GUNNER:
		return _gunner_seat
	return _driver_seat


func _optic_cfg() -> Dictionary:
	var cfg := _cfg()
	return cfg.get("optic", cfg.get("gunner", cfg["driver"]))


func _motion_cfg() -> Dictionary:
	return _cfg().get("motion", STATION_CFG["jeep"]["motion"])


func target_fov() -> float:
	match view:
		VehView.FP_OPTIC:
			return float(_optic_cfg().get("fov", FP_FOV))
		VehView.FP_GUNNER:
			return float(_station_cfg(Station.GUNNER).get("fov", FP_FOV))
		VehView.FP_DRIVER:
			return float(_station_cfg(Station.DRIVER).get("fov", FP_FOV))
		_:
			return float(G.settings.get("fov", 75.0))


## 载具开火通知(kind: cannon / autocannon / passenger)
func notify_weapon_fire(kind: String) -> void:
	var m := _motion_cfg()
	var player_inside: bool = G.player != null and (G.player == vehicle.gunner or G.player == vehicle.driver)
	if not player_inside:
		return
	if kind == "cannon":
		_recoil_pitch += float(m.get("recoil_pitch", 0.016))
		_recoil_yaw += Utils.rand(-1.0, 1.0) * float(m.get("recoil_yaw", 0.006))
		_recoil_roll += Utils.rand(-1.0, 1.0) * float(m.get("recoil_roll", 0.005))
		_recoil_pos_z += float(m.get("recoil_pos_z", 0.07))
		# 巨大炮声的视觉冲击:仅本车乘员可见(轻微过曝闪,比普通枪械闪光更钝、更重)
		if G.effects != null and G.effects.has_method("screen_flash"):
			G.effects.screen_flash(Color(1.0, 0.86, 0.62), 0.16)
		if G.effects != null:
			G.effects.shake(0.55)
	else:
		# 机炮:高频、小幅度、连续机械震动
		_recoil_pitch += float(m.get("recoil_pitch", 0.003))
		_recoil_yaw += Utils.rand(-1.0, 1.0) * float(m.get("recoil_yaw", 0.002))
		_recoil_roll += Utils.rand(-1.0, 1.0) * float(m.get("recoil_roll", 0.0016))
		_recoil_pos_z += float(m.get("recoil_pos_z", 0.012))
		if G.effects != null:
			G.effects.shake(0.055)


## 悬挂冲击(过障/撞墙/碾过障碍)
func notify_suspension_impact(amt: float) -> void:
	_impact_t = 0.0
	_impact_amp = minf(_impact_amp + clampf(amt, 0.0, 1.4), 1.4)


func _sync_seat_anchors() -> void:
	var cfg := _cfg()
	var mesh: Node3D = vehicle.mesh
	var turret: Node3D = mesh
	if mesh.has_meta("turret"):
		turret = mesh.get_meta("turret")
	_driver_seat.global_transform = mesh.global_transform * Transform3D(Basis(), cfg["driver"]["pos"])
	_gunner_seat.global_transform = turret.global_transform * Transform3D(Basis(), cfg["gunner"]["pos"])
	_optic.global_transform = turret.global_transform * Transform3D(Basis(), _optic_cfg()["pos"])


func _set_periscope_vis(vis: bool) -> void:
	if vehicle == null or vehicle.mesh == null:
		return
	if not vehicle.mesh.has_meta("interior_turret"):
		return
	var it: Node3D = vehicle.mesh.get_meta("interior_turret")
	var stack: Array = [it]
	while not stack.is_empty():
		var nd = stack.pop_back()
		if nd.name == "Periscope":
			nd.visible = vis
		for ch in nd.get_children():
			stack.append(ch)


func _world_shake() -> Vector2:
	if G.effects == null:
		return Vector2.ZERO
	return Vector2(G.effects.shake_yaw, G.effects.shake_pitch)


func _update_motion(dt: float) -> void:
	var v = vehicle
	var max_s: float = maxf(float(v.def["max_speed"]), 1.0)
	var spd: float = v.speed
	# 加速度:用平滑车速差分估计,避免原始输入阶跃
	var raw_accel := (spd - _prev_speed) / maxf(dt, 0.0001)
	_accel_s = Utils.damp(_accel_s, clampf(raw_accel / maxf(float(v.def["accel"]), 0.1), -1.5, 1.5), 5.0, dt)
	_steer_s = Utils.damp(_steer_s, v.steer, 7.0, dt)
	_prev_speed = spd
	var m := _motion_cfg()
	var vibe: float = float(m.get("vibe", 0.005))
	var speed_k := clampf(absf(spd) / max_s, 0.0, 1.0)
	var sus: float = float(v.sus_amp)
	var ph: float = float(v.sus_phase)
	# 发动机/路面高频振动(两路正弦 + 相位错开;频率随车速上升)
	var v1 := sin(G.time * (26.0 + speed_k * 9.0)) * vibe * (0.4 + 0.6 * speed_k)
	var v2 := sin(G.time * (43.0 + speed_k * 13.0) + 1.7) * vibe * 0.5 * (0.3 + 0.7 * speed_k)
	var v3 := sin(G.time * 17.0 + 0.6) * 0.0012 * speed_k
	# 目标偏移(车体局部:y 垂直起伏 / z 加减速前后 / x 转向横向惯性)
	var target_pos := Vector3(
		_steer_s * -0.010 * speed_k + v3,
		sin(ph) * sus * 0.55 + v1 + v2 + _impact_pos_y(dt),
		clampf(_accel_s, -1.0, 1.0) * -0.035 + sin(ph * 1.7 + 1.1) * sus * 0.3
	)
	var accel_pitch: float = float(m.get("accel_pitch", 0.007))
	var brake_pitch: float = float(m.get("brake_pitch", 0.005))
	var steer_roll: float = float(m.get("steer_roll", 0.012))
	var target_rot := Vector3(
		_clamp_tilt(_accel_s) * -accel_pitch * 0.7 + sin(ph * 1.23) * sus * 1.8 + _impact_rot_x(),
		sin(G.time * 33.0) * 0.0004 * speed_k,
		_steer_s * -steer_roll * speed_k + cos(ph * 0.83 + 1.7) * sus * 1.2
	)
	# 刹车前倾(减速时反向)
	if raw_accel < -0.15:
		target_rot.x += brake_pitch * clampf(-raw_accel / maxf(float(v.def["brake"]), 0.1), 0.0, 1.0)
	_pos_off = _damp_v3(_pos_off, target_pos, 9.0, dt)
	_rot_off = _damp_v3(_rot_off, target_rot, 11.0, dt)
	# 炮塔机械运动反馈:炮手能感受到炮塔转动的离心/齿轮感
	var dyaw: float = wrapf(v.turret_yaw - _prev_turret_yaw, -PI, PI)
	var dpitch: float = v.turret_pitch - _prev_turret_pitch
	var rate: float = dyaw / maxf(dt, 0.0001)
	_turret_rate = Utils.damp(_turret_rate, clampf(rate, -3.0, 3.0), 8.0, dt)
	if turret_chase():
		_rot_off.z += clampf(_turret_rate, -2.2, 2.2) * -0.0035
		_rot_off.x += absf(dpitch / maxf(dt, 0.0001)) * 0.0006 * signf(dpitch)
		_pos_off.x += clampf(_turret_rate, -2.2, 2.2) * -0.004
	_prev_turret_yaw = v.turret_yaw
	_prev_turret_pitch = v.turret_pitch


func _clamp_tilt(a: float) -> float:
	return clampf(a, -1.2, 1.2)


func _damp_v3(cur: Vector3, target: Vector3, k: float, dt: float) -> Vector3:
	return Vector3(
		Utils.damp(cur.x, target.x, k, dt),
		Utils.damp(cur.y, target.y, k, dt),
		Utils.damp(cur.z, target.z, k, dt)
	)


func _impact_pos_y(dt: float) -> float:
	if _impact_t < 0.0:
		return 0.0
	_impact_t += dt
	var dur := 0.3
	var k := clampf(_impact_t / dur, 0.0, 1.0)
	if k >= 1.0:
		_impact_t = -1.0
		_impact_amp *= 0.15
		return 0.0
	# 冲击:快速下沉 → 弹性回位(乘员被座椅“托”了一下)
	var curve := sin(k * PI)
	return -_impact_amp * 0.022 * curve + _impact_amp * 0.006 * sin(k * PI * 3.0) * (1.0 - k)


func _impact_rot_x() -> float:
	if _impact_t < 0.0:
		return 0.0
	var k := clampf(_impact_t / 0.3, 0.0, 1.0)
	return _impact_amp * 0.018 * sin(k * PI) * (1.0 - k)


func _update_recoil(dt: float) -> void:
	var m := _motion_cfg()
	var decay: float = float(m.get("recoil_decay", 6.0))
	_recoil_pitch = Utils.damp(_recoil_pitch, 0.0, decay, dt)
	_recoil_yaw = Utils.damp(_recoil_yaw, 0.0, decay * 1.7, dt)
	_recoil_roll = Utils.damp(_recoil_roll, 0.0, decay * 1.4, dt)
	_recoil_pos_z = Utils.damp(_recoil_pos_z, 0.0, decay * 1.6, dt)
	if _recoil_pitch < 0.00008 and _recoil_yaw < 0.00008:
		_recoil_pitch = 0.0
		_recoil_yaw = 0.0


func _update_sensors(dt: float) -> void:
	if vehicle == null or vehicle.dead or not vehicle.has_turret():
		return
	_sensor_tick -= dt
	if _sensor_tick > 0.0:
		return
	_sensor_tick = 0.08
	var md: Array = vehicle.muzzle_world()
	var origin: Vector3 = md[0]
	var dir: Vector3 = md[1]
	var max_r: float = 1400.0 if vehicle.type == "tank" else 900.0
	var hit = Utils.raycast_world(origin, dir, max_r)
	laser_range = float(hit["dist"]) if hit != null else 0.0
	# 雷达接触数(AA 车长/炮手数据链)与最近目标
	radar_contacts = 0
	var best: Variant = null
	var best_ang := PI
	var best_range := 0.0
	var my_team = vehicle.team()
	if my_team == null:
		my_team = G.player.team if G.player != null else "us"
	# 空中目标
	for a in G.aircraft:
		if a == null or a.dead or a.team == my_team:
			continue
		var d: float = origin.distance_to(a.pos)
		if d > 800.0:
			continue
		radar_contacts += 1
		var to: Vector3 = (a.pos - origin).normalized()
		var ang: float = dir.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = a
			best_range = d
	# 地面目标(坦克/装甲车火控优先车辆,其次步兵)
	for b in G.vehicles:
		if b == null or b.dead or b == vehicle:
			continue
		if b.team() == my_team:
			continue
		var d: float = origin.distance_to(b.pos + Vector3(0, 1.0, 0))
		if d > 800.0:
			continue
		radar_contacts += 1
		var to: Vector3 = (b.pos + Vector3(0, 1.0, 0) - origin).normalized()
		var ang: float = dir.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = b
			best_range = d
	if best == null:
		for b in G.bots:
			if b == null or not b.alive or b.team == my_team:
				continue
			var d: float = origin.distance_to(b.pos + Vector3(0, 1.3, 0))
			if d > 700.0:
				continue
			radar_contacts += 1
			var to: Vector3 = (b.pos + Vector3(0, 1.3, 0) - origin).normalized()
			var ang: float = dir.angle_to(to)
			if ang < best_ang:
				best_ang = ang
				best = b
				best_range = d
	if best != null:
		target_range = best_range
		# 目标方位角 = 炮手视线(火炮轴线)到目标的水平角差
		var bore_yaw: float = vehicle.yaw + vehicle.turret_yaw
		var to_v: Vector3 = (best.pos - origin)
		var target_world_yaw: float = atan2(-to_v.x, -to_v.z)
		target_bearing_deg = wrapf(rad_to_deg(target_world_yaw - bore_yaw), -180.0, 180.0)
		var lock_cone: float = 0.07 if vehicle.type == "aa" else 0.045
		if best_ang < lock_cone and Utils.los_clear(origin, best.pos + Vector3(0, 1.0, 0)):
			_lock_t += 0.08
		else:
			_lock_t = maxf(0.0, _lock_t - 0.12)
	else:
		target_range = 0.0
		target_bearing_deg = 0.0
		_lock_t = maxf(0.0, _lock_t - 0.12)
	target_locked = _lock_t >= (0.85 if vehicle.type == "aa" else 1.0)
	if target_locked:
		_lock_t = minf(_lock_t, 1.0)


func _begin_transition() -> void:
	_trans_from = _render_xf
	_trans_veh_pos = vehicle.pos
	_trans_t = 0.0
	_trans_dur = 0.34 if view == VehView.FP_OPTIC or _last_view == VehView.FP_OPTIC else 0.42


func _desired_xf() -> Transform3D:
	var sh := _world_shake()
	var shake_k := 0.35 if view == VehView.FP_OPTIC else 1.0
	var xf := Transform3D()
	match view:
		VehView.FP_DRIVER:
			var anchor: Node3D = _station_anchor(station)
			var xf_a: Transform3D = anchor.global_transform
			xf_a.origin += xf_a.basis * _pos_off
			xf_a.origin += xf_a.basis * Vector3(0.0, 0.0, _recoil_pos_z * 0.25)
			var b_xf := xf_a.basis
			b_xf = b_xf * Basis(Vector3.UP, look_yaw)
			b_xf = b_xf * Basis(Vector3.RIGHT, look_pitch)
			b_xf = b_xf * Basis.from_euler(_rot_off)
			xf = Transform3D(b_xf, xf_a.origin)
		_:
			# FP_OPTIC(战地式 ADS 目镜):眼位=观瞄锚点,朝向=鼠标 look 角。
			# 旧版相机沿炮管轴线取朝向,而炮塔又跟随相机射线 → "相机锁炮管、
			# 炮塔锁相机"死循环,ADS 下鼠标永远转不动炮塔(实车 QA 实锤)。
			# 现在鼠标直接驱动视线,炮塔伺服追赶同一条视线(与第三人称一致)。
			var anchor_g: Node3D = _optic
			var xf_g: Transform3D = anchor_g.global_transform
			xf_g.origin += xf_g.basis * _pos_off
			xf_g.origin += xf_g.basis * Vector3(0.0, 0.0, _recoil_pos_z)
			var gb: Basis = Basis(Vector3.UP, vehicle.yaw + look_yaw)
			gb = gb * Basis(Vector3.RIGHT, look_pitch)
			# 后坐抖动叠加在头部(不改变瞄准基线)
			gb = gb * Basis.from_euler(_rot_off + Vector3(_recoil_pitch * 0.55, _recoil_yaw * 0.5, _recoil_roll * 0.6))
			xf = Transform3D(gb, xf_g.origin)
	# 世界级屏幕震动
	var cam_basis := xf.basis
	cam_basis = cam_basis * Basis(Vector3.UP, sh.x * shake_k)
	cam_basis = cam_basis * Basis(Vector3.RIGHT, sh.y * shake_k)
	xf = Transform3D(cam_basis.orthonormalized(), xf.origin)
	return xf


## 用 forward 构造相机基:-Z 对准弹道方向,保留世界 up 约束。
func _basis_looking_forward(forward: Vector3, yaw_hint: float) -> Basis:
	var fwd := Utils.safe_norm(forward, Vector3(0, 0, -1))
	var right: Vector3
	if absf(fwd.y) > 0.985:
		# 接近垂直俯仰时用炮塔水平方向确定 right,防万向翻转
		right = Vector3(cos(yaw_hint), 0.0, -sin(yaw_hint))
	else:
		right = fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	return Basis(right, up, -fwd).orthonormalized()


func update(dt: float) -> void:
	if vehicle == null or vehicle.mesh == null:
		return
	var cam: Camera3D = G.camera
	if cam == null:
		return
	_sync_seat_anchors()
	_update_motion(dt)
	_update_recoil(dt)
	_update_sensors(dt)
	match view:
		VehView.FP_DRIVER, VehView.FP_GUNNER, VehView.FP_OPTIC:
			_set_periscope_vis(view != VehView.FP_GUNNER and view != VehView.FP_OPTIC)
			var desired: Transform3D = _desired_xf()
			if _last_view != int(view) or _last_station != station:
				_begin_transition()
				_last_view = int(view)
				_last_station = station
			if _trans_t >= 0.0:
				_trans_t += dt / maxf(_trans_dur, 0.01)
				var t := clampf(_trans_t, 0.0, 1.0)
				# 岗位切换沿乘员头部自然弧线移动(轻微低头绕过舱内设备)
				var smooth_t := t * t * (3.0 - 2.0 * t)
				var arc := Vector3(0.0, sin(t * PI) * 0.14, 0.0)
				var mid: Transform3D = _trans_from
				mid.origin += vehicle.pos - _trans_veh_pos
				mid.origin += arc
				_render_xf = mid.interpolate_with(desired, smooth_t)
				if t >= 1.0:
					_trans_t = -1.0
					_render_xf = desired
			else:
				_render_xf = desired
			# FOV 由 player 统一阻尼;镜头闪烁/火光余晖在这里衰减即可
			cam.global_transform = _render_xf
		_:
			_update_tp(cam, dt)
	_update_ads_barrel(view)
	_update_observer_mg()


## ADS(炮手右键目镜):藏起炮管网格,镜内只留火控分划;退出恢复。
func _update_ads_barrel(view: int) -> void:
	if vehicle == null or vehicle.mesh == null:
		return
	if _cannon_tube == null:
		_cannon_tube = vehicle.mesh.find_child("CannonTube", true, false)
	if _cannon_tube == null:
		return
	var hide_fl: bool = view == VehView.FP_OPTIC
	if _cannon_tube.visible == hide_fl:
		_cannon_tube.visible = not hide_fl


## 观察位(防空车):机枪随观察方向旋转(模型挂车体,局部 yaw=轨道 yaw)
func _update_observer_mg() -> void:
	if vehicle == null or vehicle.mesh == null:
		return
	if station != Station.OBSERVER or vehicle.type != "aa":
		return
	if not vehicle.mesh.has_meta("observer_mg"):
		return
	var mg: Node3D = vehicle.mesh.get_meta("observer_mg")
	mg.rotation.y = _tp_orbit_yaw


func _update_tp(cam: Camera3D, _dt: float) -> void:
	_set_periscope_vis(true)
	var v = vehicle
	var dist := 7.0 if v.type == "tank" else 5.5
	var cam_h := 2.8 if v.type == "tank" else 2.3
	# 战地式自由第三人称:视线方向由鼠标全角控制(俯仰不限盯车),
	# 相机挂在视线反方向上;炮塔/开火都以这条视线为瞄准基准。
	var orbit: float = v.yaw + _tp_orbit_yaw
	var view_pitch: float = -_tp_orbit_pitch          # 正=抬头上望
	var cp: float = cos(view_pitch)
	var fwd := Vector3(-sin(orbit) * cp, sin(view_pitch), -cos(orbit) * cp)
	# 锚点取全高(坦克 2.8 / 其余 2.3):相机高于炮塔顶,车体不挡视线(实拍实锤)
	var anchor: Vector3 = v.pos + Vector3(0, cam_h, 0)
	var target: Vector3 = anchor - fwd * dist
	# 仰视时相机下沉不低于车顶一半,防止扎进车体
	target.y = maxf(target.y, v.pos.y + cam_h * 0.5)
	var hit = Utils.raycast_world(anchor, -fwd, dist + 0.3)
	if hit != null:
		target = anchor - fwd * maxf(1.4, hit["dist"] - 0.3)
	if G.ground_h.is_valid():
		var gh: float = G.ground_h.call(target.x, target.z)
		if target.y < gh + 0.35:
			target.y = gh + 0.35
	cam.global_position = target
	cam.rotation_order = EULER_ORDER_YXZ
	cam.rotation = Vector3(view_pitch, orbit, 0)
	var sh := _world_shake()
	cam.rotation_order = EULER_ORDER_YXZ
	cam.rotation.y += sh.x
	cam.rotation.x += sh.y
	cam.rotation.z = 0


## HUD 数据出口:现代军用载具界面只读这里,不直接翻车辆私有状态。
func get_hud_info() -> Dictionary:
	var v = vehicle
	var out := {
		"type": v.type,
		"vehicle_name": str(v.def.get("vehicle_name", "载具")),
		"view": int(view),
		"station": station,
		"turret_chase": turret_chase(),
		"optic_mode": int(optic_mode),
		"speed": v.speed,
		"max_speed": float(v.def["max_speed"]),
		"engine_rpm": clampf(absf(v.speed) / maxf(float(v.def["max_speed"]), 1.0), 0.0, 1.0),
		"turret_deg": wrapf(rad_to_deg(-(v.yaw + v.turret_yaw)), 0.0, 360.0),
		"turret_elev_deg": rad_to_deg(v.turret_pitch),
		"cannon_ammo": v.cannon_ammo,
		"auto_ammo": v.auto_ammo,
		"cannon_t": v.cannon_t,
		"laser_range": laser_range,
		"target_locked": target_locked,
		"target_range": target_range,
		"target_bearing_deg": target_bearing_deg,
		"radar_contacts": radar_contacts,
		"recoil": _recoil_pitch,
	}
	return out
