class_name Player extends Node3D
## 玩家控制器(对应 player.js)

var team := "us"
var player_name := "你"
var pos := Vector3(0, 0, -100)
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var recoil_pitch := 0.0
var recoil_yaw := 0.0
var cam_kick_pitch := 0.0          # 开火瞬间摄像机微后坐(高衰减)
var cam_kick_yaw := 0.0
var look_vel_x := 0.0
var look_vel_y := 0.0
var radius := 0.38
var height := 1.75
var eye_height := 1.62
var health := 100.0
var alive := false
var on_ground := true
var crouched := false
var sprint_amount := 0.0
var last_damage_t := -99.0
var spawn_protect := 0.0
var guns: Array = []
var gun_index := 0
var grenades := 2
var at_grenades := 2                # 反坦克手雷(X)
var at_mines := 1                   # 反坦克地雷(V)
var gadget := ""
var gadget_count := 0
var class_id := "assault"
var loadout = null
var step_t := 0.0
var bob_y := 0.0
var vehicle = null                # 驾驶中的载具
var prone := false                # 趴下
var spot_cd := 0.0                # 索敌冷却
var suppression := 0.0            # 压制值
var night_vision := false         # 夜视仪(T,仅夜间地图侦察兵)
var tac_sprint := 0.0             # 战术冲刺剩余
var tac_cd := 0.0
var last_shift_tap := -9.0
var heal_over_time := 0.0
var _lock_cand = null
var _lock_t := 0.0
var _lock_los_t := 0.0               # 锁定目标 LOS 丢失宽限计时
var _veh_tp := false                 # 载具第三人称
var _veh_tp_pitch := 0.0             # 第三人称炮塔类载具:相机俯仰微调(±0.35rad)
var _killed_by_def = null
var sprint_toggled := false           # Shift 切换疾跑
var slide_t := 0.0                    # 滑铲剩余时间
var slide_dir := Vector2.ZERO         # 滑铲方向
var _slide_roll := 0.0                # 滑铲相机侧倾
var _prone_amt := 0.0                 # 趴下姿势插值(0=站立 1=全趴)

var body: Node3D = null           # 第一人称下半身
var veh_body: Node3D = null       # 第三人称载具乘员模型(吉普/炮塔探身)


func _ready() -> void:
	name = "你"
	body = SoldierModel.build_player_body()
	G.main.add_child(body)


func gun() -> Gun:
	if guns.is_empty() or gun_index >= guns.size():
		return null
	return guns[gun_index]


func camera() -> Camera3D:
	return G.camera


func give_class(p_class_id: String, p_loadout) -> void:
	class_id = p_class_id
	var cls = WeaponsData.C()[p_class_id]
	if p_loadout is String:
		p_loadout = { "primary": p_loadout }
	var primary = cls.primary
	var secondary = cls.secondaries[0]
	var shotgun = cls.shotguns[0] if not cls.shotguns.is_empty() else null
	if p_loadout != null:
		if p_loadout.get("primary") != null:
			primary = p_loadout["primary"]
		if p_loadout.get("secondary") != null:
			secondary = p_loadout["secondary"]
		if p_loadout.has("shotgun"):
			shotgun = p_loadout["shotgun"]
	loadout = { "primary": primary, "secondary": secondary, "shotgun": shotgun }
	# 清理旧枪(视角模型层)
	for g in guns:
		G.vm_camera.remove_child(g.group)
		g.group.queue_free()
	guns = [Gun.new(loadout["primary"], self)]
	# 突击兵:额外携带一把主武器霰弹枪(槽位 2)
	if not cls.shotguns.is_empty() and loadout["shotgun"] != null:
		guns.append(Gun.new(loadout["shotgun"], self))
	guns.append(Gun.new(loadout["secondary"], self))
	if cls.gadget == "rpg":
		guns.append(Gun.new("rpg", self))
	for g in guns:
		G.vm_camera.add_child(g.group)
		g.holster()
	gun_index = 0
	gun().equip()
	gadget = cls.gadget
	gadget_count = cls.gadget_count
	grenades = 2
	at_grenades = 2
	at_mines = 1
	# 重建第三人称载具乘员模型(兵种外观同步)
	if veh_body != null:
		veh_body.queue_free()
	veh_body = SoldierModel.build_soldier("us", loadout["primary"], class_id)
	veh_body.visible = false
	G.main.add_child(veh_body)


func spawn(p_pos: Vector3) -> void:
	if vehicle != null:
		exit_vehicle(true)
	pos = p_pos
	vel = Vector3.ZERO
	health = 100
	alive = true
	prone = false
	body.rotation.x = 0
	spawn_protect = 2
	last_damage_t = -99
	heal_over_time = 0
	# 面向地图中心
	yaw = atan2(-pos.x, -pos.z) + PI
	pitch = 0
	recoil_pitch = 0
	recoil_yaw = 0
	give_class(class_id, loadout)
	# 夜视仪重部署自动关闭(防残留)
	night_vision = false
	G.effects.set_night_vision(false)


func apply_look(dx: float, dy: float) -> void:
	var sens = 0.0022 * G.settings.sensitivity * lerpf(1.0, 0.6, gun().ads_amount if gun() != null else 0.0)
	yaw -= dx * sens
	pitch -= dy * sens
	pitch = clampf(pitch, -1.45, 1.45)
	look_vel_x = dx
	look_vel_y = dy


func switch_weapon(i: int) -> void:
	if i == gun_index or i >= guns.size() or not alive:
		return
	gun().holster()
	gun_index = i
	gun().equip()
	G.lock_target = null  # 切枪脱锁
	AudioSys.reload(1)


func damage(amount: float, attacker_pos: Vector3, attacker, def = null) -> void:
	if not alive or spawn_protect > 0 or G.state != "playing":
		return
	health -= amount
	_killed_by_def = def
	last_damage_t = G.time
	AudioSys.hurt()
	G.hud.on_player_hurt(attacker_pos)
	G.effects.shake(0.25)
	if health <= 0:
		health = 0
		alive = false
		night_vision = false
		G.effects.set_night_vision(false)
		if veh_body != null:
			veh_body.visible = false
		G.game.on_player_death(attacker)


func heal(x: float) -> void:
	health = minf(100, health + x)


func resupply() -> void:
	for g in guns:
		g.reserve = g.def.reserve
	grenades = 2
	at_grenades = 2
	at_mines = 1
	var cls = WeaponsData.C()[class_id]
	if gadget != "rpg":
		gadget_count = cls.gadget_count


## Q 索敌:标记准星附近的敌人(BF 索敌系统)
func spot_enemy() -> void:
	if spot_cd > 0:
		return
	spot_cd = 1.5
	var dir: Vector3 = -G.camera.global_transform.basis.z
	var best = null
	var best_ang := 0.06
	for b in G.bots:
		if not b.alive or b.team == team:
			continue
		var wish := Vector3(b.pos.x - G.camera.global_position.x, b.pos.y + 1.4 - G.camera.global_position.y, b.pos.z - G.camera.global_position.z)
		var d := wish.length()
		if d > 160:
			continue
		var ang := wish.normalized().angle_to(dir)
		if ang < best_ang:
			var target := Vector3(b.pos.x, b.pos.y + 1.4, b.pos.z)
			if Utils.los_clear(G.camera.global_position, target):
				best = b
				best_ang = ang
	if best != null:
		best.spotted = 8
		G.hud.hint("已标记敌人位置(全队可见)")
		AudioSys.hit(false)
	else:
		G.hud.hint("未发现目标")


## T 夜视仪:仅存活 + 侦察兵 + 夜间地图(G.map_night 由世界构建设置,缺失按 false)
func _toggle_night_vision() -> void:
	if not alive or class_id != "recon" or G.get("map_night") != true:
		AudioSys.ui()
		if night_vision:
			night_vision = false
			G.effects.set_night_vision(false)
		if G.hud != null and G.hud.has_method("hint"):
			G.hud.hint("仅夜间地图侦察兵可使用夜视仪(T)")
		return
	night_vision = not night_vision
	G.effects.set_night_vision(night_vision)
	AudioSys.ui()
	if G.hud != null and G.hud.has_method("hint"):
		G.hud.hint("夜视仪开启 — 敌踪显现" if night_vision else "夜视仪关闭")


func throw_grenade() -> void:
	if grenades <= 0 or not alive:
		AudioSys.dry_fire()
		return
	grenades -= 1
	# 抛掷弧线:轻微上扬形成自然抛物线
	var dir: Vector3 = (-G.camera.global_transform.basis.z + Vector3.UP * 0.14).normalized()
	var p: Vector3 = G.camera.global_position + dir * 0.6
	p.y -= 0.1
	G.effects.spawn_grenade(self, p, dir)
	AudioSys.reload(0)


## 反坦克手雷(X):更重、碰载具即炸、对载具高伤
func throw_at_grenade() -> void:
	if at_grenades <= 0 or not alive:
		AudioSys.dry_fire()
		return
	at_grenades -= 1
	# 抛掷弧线:轻微上扬形成自然抛物线
	var dir: Vector3 = (-G.camera.global_transform.basis.z + Vector3.UP * 0.14).normalized()
	var p: Vector3 = G.camera.global_position + dir * 0.6
	p.y -= 0.1
	G.effects.spawn_at_grenade(self, p, dir)
	AudioSys.reload(0)


## 反坦克地雷(V):部署在脚前,敌方载具靠近即炸;突击兵为 C5 定时炸药
func place_at_mine() -> void:
	if at_mines <= 0 or not alive:
		AudioSys.dry_fire()
		return
	at_mines -= 1
	if class_id == "assault":
		G.game.spawn_c5(self)
	else:
		G.game.spawn_at_mine(self)


func use_gadget() -> void:
	if not alive:
		return
	# 工程兵:F 维修附近己方受损载具
	if class_id == "engineer" and _try_repair_vehicle():
		return
	# 侦察兵:F 部署重生信标
	if class_id == "recon":
		if gadget_count <= 0:
			AudioSys.dry_fire()
			return
		gadget_count -= 1
		G.game.spawn_beacon(self)
		return
	if gadget_count <= 0:
		AudioSys.dry_fire()
		return
	if gadget == "medkit":
		gadget_count -= 1
		heal_over_time = 60
		AudioSys.capture(true)
		G.hud.hint("医疗包:恢复中…")
	elif gadget == "ammobox":
		gadget_count -= 1
		resupply()
		AudioSys.reload(1)
		G.hud.hint("弹药已补给")
	elif gadget == "sensor":
		gadget_count -= 1
		G.game.spot_enemies(50, 12)
		AudioSys.capture(true)
		G.hud.hint("动态探测器已启动:敌人已标记")
	elif gadget == "ammopack":
		gadget_count -= 1
		G.game.spawn_ammo_pack(self)


## 工程兵维修:附近 4m 内有受损己方/中立载具则持续修复
func _try_repair_vehicle() -> bool:
	for v in G.vehicles:
		if v.dead or v.hp >= v.def["hp"]:
			continue
		var vt = v.team()
		if vt != null and vt != team:
			continue  # 敌方驾驶的不能修
		if pos.distance_to(v.pos) < 4.5:
			v.hp = minf(v.def["hp"], v.hp + 45)
			G.effects.spark_spawn(v.pos.x, v.pos.y + 1.2, v.pos.z, Utils.rand(-1, 1), Utils.rand(1, 2.5), Utils.rand(-1, 1), 0.3, 1, 0.8, 0.4, 1.6)
			AudioSys.reload(0)
			G.hud.hint("维修中… " + str(int(v.hp / v.def["hp"] * 100)) + "%")
			return true
	return false


# ============ 载具 ============
func enter_vehicle(v) -> void:
	vehicle = v
	v.driver = self
	yaw = 0
	pitch = 0  # 相对载具的观察角
	_veh_tp = false
	_veh_tp_pitch = 0.0
	for g in guns:
		g.holster()
	AudioSys.engine_start()
	G.hud.hint("W/S 油门刹车 · A/D 转向 · C 第三人称 · E 下车")


func exit_vehicle(silent := false) -> void:
	var v = vehicle
	if v == null:
		return
	v.driver = null
	vehicle = null
	if veh_body != null:
		veh_body.visible = false
	AudioSys.engine_stop()
	# 下到车侧
	var side := Vector3(2.2, 0, 0).rotated(Vector3.UP, v.yaw)
	pos = Vector3(v.pos.x + side.x, 0, v.pos.z + side.z)
	# 下车惯性:载具行驶中下车继承速度(低速则静止)
	if absf(v.speed) > 2.0:
		vel = Vector3(-sin(v.yaw), 0.5, -cos(v.yaw)) * v.speed * 0.65
	else:
		vel = Vector3.ZERO
	yaw = v.yaw
	if not silent:
		gun().equip()
	else:
		for g in guns:
			g.holster()


## 第三人称载具相机(车尾后上方,防穿墙)
func _place_tp_cam(cam: Camera3D, v, cam_yaw: float) -> void:
	var dist := 7.0 if v.type == "tank" else 5.5
	var cam_h := 2.8 if v.type == "tank" else 2.3
	var back := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var eye: Vector3 = v.pos + Vector3(0, cam_h, 0)
	var hit = Utils.raycast_world(eye, back, dist + 0.3)
	var d := dist
	if hit != null:
		d = maxf(1.2, hit["dist"] - 0.3)
	cam.global_position = eye + back * d


## 第三人称载具乘员模型(吉普坐姿 / 炮塔探身;仅第三人称时显示)
func _update_veh_body(v) -> void:
	if veh_body == null:
		return
	if not _veh_tp or v.type != "jeep":
		veh_body.visible = false  # 仅侦察吉普显示玩家第三人称模型
		return
	veh_body.visible = true
	var leg_l: Node3D = veh_body.get_meta("leg_l")
	var leg_l_knee: Node3D = veh_body.get_meta("leg_l_knee")
	var leg_r: Node3D = veh_body.get_meta("leg_r")
	var leg_r_knee: Node3D = veh_body.get_meta("leg_r_knee")
	var rig: Node3D = veh_body.get_meta("rig")
	veh_body.rotation_order = EULER_ORDER_YXZ
	# 吉普:臀部落座(模型原点在脚底,座椅面高约 1.08,下沉 1.32 防站穿车顶)
	var seat: Vector3 = v.seat_world()
	veh_body.position = Vector3(seat.x, seat.y - 1.32, seat.z)
	veh_body.rotation = Vector3(0, v.yaw, 0)
	if leg_l != null:
		leg_l.visible = true
		leg_r.visible = true
		leg_l.rotation.x = 1.35
		leg_r.rotation.x = 1.35
		leg_l_knee.rotation.x = -1.35
		leg_r_knee.rotation.x = -1.35
	if rig != null:
		rig.rotation.x = 0.1


func update_vehicle(dt: float) -> void:
	var v = vehicle
	var input = G.input_sys
	body.visible = false  # 驾驶时隐藏下半身
	_update_veh_body(v)
	if Input.is_action_just_pressed("interact"):
		exit_vehicle()
		return
	if Input.is_action_just_pressed("crouch"):
		_veh_tp = not _veh_tp
	var cam := camera()
	var seat: Vector3 = v.seat_world()
	pos = Vector3(v.pos.x, v.pos.y, v.pos.z)  # 供 AI 瞄准/小地图
	cam.rotation_order = EULER_ORDER_YXZ
	if v.has_turret():
		# 炮塔视角(第三人称恢复原版:镜头沿炮塔指向,随炮塔俯仰;HUD 载具准星保留)
		var cam_yaw: float = v.yaw + v.turret_yaw
		if _veh_tp:
			_place_tp_cam(cam, v, cam_yaw)
		else:
			cam.global_position = seat
		cam.rotation.y = cam_yaw + G.effects.shake_yaw
		cam.rotation.x = v.turret_pitch + G.effects.shake_pitch
		cam.rotation.z = 0
		var w_name: String = "主炮" if v.is_tank() else v.def.weapon["cn"]
		if v.cannon_t > 0 and v.is_tank():
			G.hud.hint(w_name + "装填 " + str(ceil(v.cannon_t)) + "s · C 第三人称 · E 下车")
		else:
			G.hud.hint(w_name + "就绪 · 左键开火 · C 第三人称 · E 下车")
	else:
		# 吉普:自由观察
		var md: Vector2 = input.consume_mouse()
		var sens = 0.0022 * G.settings.sensitivity
		yaw -= md.x * sens
		pitch = clampf(pitch - md.y * sens, -1.1, 1.1)
		if _veh_tp:
			_place_tp_cam(cam, v, v.yaw + yaw)
		else:
			cam.global_position = seat
		cam.rotation.y = v.yaw + yaw + G.effects.shake_yaw
		cam.rotation.x = pitch + G.effects.shake_pitch
		cam.rotation.z = 0
		G.hud.hint("W/S 油门刹车 · A/D 转向 · C 第三人称 · E 下车")
	if absf(cam.fov - G.settings.fov) > 0.05:
		cam.fov = Utils.damp(cam.fov, G.settings.fov, 10, dt)


func update_player(dt: float) -> void:
	if not alive:
		return
	var input = G.input_sys
	spawn_protect = maxf(0, spawn_protect - dt)
	# 驾驶模式
	if vehicle != null:
		update_vehicle(dt)
		return

	# ---- 视角 ----
	var md: Vector2 = input.consume_mouse()
	apply_look(md.x, md.y)
	look_vel_x = Utils.damp(look_vel_x, 0, 12, dt)
	look_vel_y = Utils.damp(look_vel_y, 0, 12, dt)

	# ---- 移动输入 ----
	var fwd_in := (1 if Input.is_action_pressed("move_forward") else 0) - (1 if Input.is_action_pressed("move_back") else 0)
	var right_in := (1 if Input.is_action_pressed("move_right") else 0) - (1 if Input.is_action_pressed("move_left") else 0)
	# Z 趴下(切换)
	if Input.is_action_just_pressed("prone") and on_ground and slide_t <= 0:
		prone = not prone
		if prone:
			crouched = false
			sprint_toggled = false
	# C 蹲下(切换)/ 疾跑中滑铲(COD);趴下时按 C 起身变蹲
	if Input.is_action_just_pressed("crouch") and prone and on_ground:
		prone = false
		crouched = true
	elif Input.is_action_just_pressed("crouch") and on_ground and not prone:
		var h_spd := Vector2(vel.x, vel.z).length()
		if slide_t <= 0 and sprint_amount > 0.5 and h_spd > 4.5:
			# 滑铲(干净利落:0.7s 全程,初速爆发)
			slide_t = 0.7
			slide_dir = Vector2(vel.x, vel.z).normalized()
			sprint_toggled = false
			AudioSys.step(true)
		else:
			crouched = not crouched
	# Shift 疾跑(切换:按一下疾跑,再按一下行走)
	tac_cd = maxf(0, tac_cd - dt)
	if Input.is_action_just_pressed("sprint"):
		sprint_toggled = not sprint_toggled
		if sprint_toggled:
			crouched = false
			tac_sprint = 2.2  # 起步短暂战术冲刺提速
			tac_cd = 5
			AudioSys.step(true)
		last_shift_tap = G.time
	if tac_sprint > 0 and (fwd_in <= 0 or not sprint_toggled):
		tac_sprint = 0
	tac_sprint = maxf(0, tac_sprint - dt)
	# 滑铲计时
	if slide_t > 0:
		slide_t -= dt
	var want_sprint: bool = sprint_toggled and fwd_in > 0 and not crouched and not prone and slide_t <= 0 and gun().ads_amount < 0.3
	sprint_amount = Utils.damp(sprint_amount, 1.0 if want_sprint else 0.0, 10, dt)

	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := Vector3.ZERO + fwd * fwd_in + right * right_in
	if wish.length_squared() > 0:
		wish = wish.normalized()

	var speed := 4.6
	if sprint_amount > 0.5:
		speed = 6.9
	if tac_sprint > 0:
		speed = 8.3
	if crouched:
		speed = 2.4
	if prone:
		speed = 1.3
	if gun().ads_amount > 0.5:
		speed = minf(speed, 2.8)

	if slide_t > 0:
		# 滑铲:方向锁定,初速 8.8 爆发,后段干净收束
		var slide_speed := lerpf(3.4, 8.8, pow(slide_t / 0.7, 0.8))
		vel.x = slide_dir.x * slide_speed
		vel.z = slide_dir.y * slide_speed
	else:
		# 加速/摩擦
		var accel := 42.0 if on_ground else 9.0
		vel.x = Utils.damp(vel.x, wish.x * speed, accel / speed, dt)
		vel.z = Utils.damp(vel.z, wish.z * speed, accel / speed, dt)

	# 跳跃/重力(趴下与滑铲时不能跳)
	if on_ground and not prone and slide_t <= 0 and Input.is_action_just_pressed("jump"):
		vel.y = 5.4
		on_ground = false
	vel.y -= 13.5 * dt
	pos.x += vel.x * dt
	pos.z += vel.z * dt
	pos.y += vel.y * dt
	var gh: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	if pos.y <= gh:
		pos.y = gh
		vel.y = 0
		on_ground = true
	pos = Utils.move_collide(pos, radius, 0.75 if prone else (1.25 if (crouched or slide_t > 0) else height))
	# 载具实体碰撞(不再穿模)
	pos = Vehicle.vehicle_collide(pos, radius)

	# 脚步声
	var h_speed := Vector2(vel.x, vel.z).length()
	if on_ground and h_speed > 1:
		step_t -= dt * h_speed
		if step_t <= 0:
			step_t = 3.4
			AudioSys.step(sprint_amount > 0.5)

	# ---- 附近载具:按 E 上车 ----
	for v in G.vehicles:
		if v.driver == null and not v.dead and Vector2(v.pos.x - pos.x, v.pos.z - pos.z).length() < 3.4:
			G.hud.hint("按 E 驾驶 " + v.def.vehicle_name)
			if Input.is_action_just_pressed("interact"):
				enter_vehicle(v)
				return
			break

	# ---- 武器操作 ----
	var g := gun()
	g.trigger_held = Input.is_action_pressed("fire")
	# ADS 打断疾跑(BF 手感):跑步中按右键瞬间取消疾跑,同帧即可开镜
	if Input.is_action_just_pressed("ads") and (sprint_amount > 0.5 or sprint_toggled):
		sprint_toggled = false
		tac_sprint = 0
		sprint_amount = 0
	g.ads_held = Input.is_action_pressed("ads") and sprint_amount < 0.5
	# 开火/换弹打断疾跑(BF 手感):按下瞬间取消疾跑,立即进入可射击/换弹状态
	# sprint_amount 直接归零:消除射击精度惩罚残留(gun.current_spread 与 sprint_amount 联动)
	# 与既有行为并存:滑铲/ADS 解除疾跑走 want_sprint 分支,不受影响
	if g.trigger_held and (sprint_amount > 0.5 or sprint_toggled):
		sprint_toggled = false
		tac_sprint = 0
		sprint_amount = 0
	if Input.is_action_just_pressed("reload"):
		# 奔跑中按 R 保持奔跑模式,换弹在奔跑中正常进行(gun.gd 负责节奏)
		g.reload()
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(0)
	if Input.is_action_just_pressed("weapon_2"):
		switch_weapon(1)
	if Input.is_action_just_pressed("weapon_3"):
		switch_weapon(2)
	var wheel = input.consume_wheel()
	if wheel != 0:
		var i := (gun_index + (1 if wheel > 0 else -1) + guns.size()) % guns.size()
		switch_weapon(i)
	if Input.is_action_just_pressed("grenade"):
		throw_grenade()
	if Input.is_action_just_pressed("at_grenade"):
		throw_at_grenade()
	if Input.is_action_just_pressed("at_mine"):
		place_at_mine()
	if Input.is_action_just_pressed("gadget"):
		use_gadget()
	if Input.is_action_just_pressed("spot"):
		spot_enemy()
	if Input.is_action_just_pressed("nightvision"):
		_toggle_night_vision()
	if Input.is_action_just_pressed("streak_uav"):
		G.game.call_uav()
	if Input.is_action_just_pressed("streak_arty"):
		G.game.call_artillery()
	spot_cd = maxf(0, spot_cd - dt)
	suppression = maxf(0, suppression - dt * 0.5)

	# ---- 防空导弹锁定(工程兵 RPG:瞄准空中载具 1 秒自动锁敌) ----
	# 失效实例防护(换图/目标被销毁后残留引用)
	if _lock_cand != null and not is_instance_valid(_lock_cand):
		_lock_cand = null
		_lock_t = 0
	if G.lock_target != null and not is_instance_valid(G.lock_target):
		G.lock_target = null
	if g.id == "rpg" and not G.aircraft.is_empty():
		var dir_l: Vector3 = -G.camera.global_transform.basis.z
		var cand = null
		var best_ang := 0.09
		for a in G.aircraft:
			if a.dead or a.team == team:
				continue
			var wish2 := Vector3(a.pos.x - G.camera.global_position.x, a.pos.y - G.camera.global_position.y, a.pos.z - G.camera.global_position.z)
			var d := wish2.length()
			if d > 280:
				continue
			var ang := wish2.normalized().angle_to(dir_l)
			if ang < best_ang and Utils.los_clear(G.camera.global_position, a.pos):
				cand = a
				best_ang = ang
		# 粘性候选:正在锁定的目标仍在宽容锥角(~8°)内时保持,避免双机掠过交替重置 1 秒计时
		if _lock_cand != null and not _lock_cand.dead and _lock_cand.team != team:
			var wish3: Vector3 = _lock_cand.pos - G.camera.global_position
			if wish3.length() <= 280 and wish3.normalized().angle_to(dir_l) < 0.14 and Utils.los_clear(G.camera.global_position, _lock_cand.pos):
				cand = _lock_cand
		if cand != null and _lock_cand == cand:
			_lock_t += dt
			if _lock_t > 1.0 and G.lock_target != cand:
				G.lock_target = cand
				G.hud.hint("防空导弹已锁定 — 开火!")
				AudioSys.capture(true)
			elif _lock_t > 0.3 and G.lock_target != cand and randf() < 0.1:
				G.hud.hint("锁定中…保持瞄准")
		else:
			_lock_cand = cand
			_lock_t = 0
			# 候选消失或切换 → 旧锁定作废
			if G.lock_target != null and G.lock_target != cand:
				G.lock_target = null
		# 目标坠毁或持续飞出视线 → 脱锁(单帧建筑遮挡给 0.3 秒宽限)
		if G.lock_target != null:
			if G.lock_target.dead:
				G.lock_target = null
				_lock_los_t = 0
			elif not Utils.los_clear(G.camera.global_position, G.lock_target.pos):
				_lock_los_t += dt
				if _lock_los_t > 0.3:
					G.lock_target = null
					_lock_los_t = 0
			else:
				_lock_los_t = 0
	elif G.lock_target != null:
		G.lock_target = null

	for g2 in guns:
		g2.update(dt)

	# ---- 生命恢复(COD 式)----
	if heal_over_time > 0:
		var h := minf(heal_over_time, 40 * dt)
		heal(h)
		heal_over_time -= h
	elif G.time - last_damage_t > 4.5 and health < 100:
		heal(14 * dt)

	# ---- 相机 ----
	# 垂直后坐恢复 3.4/s:平衡爬升 M4A1≈1.5°、AK47≈1.8°、PKM≈1.9°(含连射递增 k=1.5 时 2.3-2.8°)
	# 平衡角 = 射速(发/s) × 每发仰角° × k ÷ 恢复速率;开镜再乘 ads_scale 0.62。原 9/s 爬升仅 0.58° 肉眼不可见
	recoil_pitch = Utils.damp(recoil_pitch, 0, 3.4, dt)
	recoil_yaw = Utils.damp(recoil_yaw, 0, 9, dt)
	# 开火微后坐:快衰减的冲击震动
	cam_kick_pitch = Utils.damp(cam_kick_pitch, 0, 13, dt)
	cam_kick_yaw = Utils.damp(cam_kick_yaw, 0, 13, dt)
	var target_eye := 0.45 if prone else (0.72 if slide_t > 0 else (1.12 if crouched else 1.62))
	# 滑铲视线快速压下(22),起身利落回正(12)
	eye_height = Utils.damp(eye_height, target_eye, 22.0 if slide_t > 0 else 12.0, dt)
	# 相机 bob
	if on_ground and h_speed > 0.5:
		bob_y += dt * h_speed * 1.55
	var bob_amp := 0.035 if sprint_amount > 0.5 else 0.018
	var cam := camera()
	cam.global_position = Vector3(
		pos.x + sin(bob_y) * bob_amp * 0.5,
		pos.y + eye_height + absf(cos(bob_y)) * bob_amp,
		pos.z)
	cam.rotation_order = EULER_ORDER_YXZ
	# 压制效果:被压制时准星抖动(开镜大幅减免)
	var sup_j := clampf(suppression, 0, 1) * 0.0032 * (1.0 - g.ads_amount * 0.65)
	var jt: float = G.time
	cam.rotation.y = yaw + recoil_yaw + cam_kick_yaw + G.effects.shake_yaw + sin(jt * 31.0) * sup_j
	cam.rotation.x = pitch + recoil_pitch + cam_kick_pitch + G.effects.shake_pitch + cos(jt * 27.0 + 1.4) * sup_j
	# 滑铲相机侧倾:快速压入,干净回正
	_slide_roll = Utils.damp(_slide_roll, -0.1 if slide_t > 0 else 0.0, 16.0 if slide_t > 0 else 10.0, dt)
	cam.rotation.z = sin(bob_y * 0.5) * 0.003 + recoil_yaw * 0.3 + _slide_roll
	# FOV:冲刺 +,滑铲瞬时冲击(随滑铲进程衰减),机瞄/狙击全屏放大 -
	var base_fov: float = G.settings.fov + sprint_amount * 6 + (4 if tac_sprint > 0 else 0) + 7.0 * clampf(slide_t / 0.7, 0.0, 1.0)
	var target_fov := lerpf(base_fov, g.def.zoom_fov, g.ads_amount)
	if absf(cam.fov - target_fov) > 0.05:
		cam.fov = Utils.damp(cam.fov, target_fov, 18, dt)

	# ---- 下半身同步(趴下平躺 / 蹲下压缩) ----
	body.visible = true
	body.position = pos
	# 第一人称显示腿 + 躯干/双肩:upper 顶面 1.35m < 站立眼高 1.62m,平视不穿模;
	# 低头可见胸口/双腿、蹲姿(眼 1.12m)可见胸口,均为游戏内正常表现。
	var upper: Node3D = body.get_meta("upper")
	upper.visible = true
	_prone_amt = Utils.damp(_prone_amt, 1.0 if prone else 0.0, 8, dt)
	# 站立:身体略后移,低头看到腿部;趴下:身体整体后移约一个身长,
	# 使旋转后头部落在原站立位置(头下压、脚后伸),而非绕脚轴把头向前翻倒
	var back_off := lerpf(0.2, 1.35, _prone_amt)
	body.position.x += sin(yaw) * back_off
	body.position.z += cos(yaw) * back_off
	body.position.y -= _prone_amt * 0.05
	body.rotation.y = yaw
	var target_rx := (-PI / 2 + 0.1) * _prone_amt
	body.rotation.x = Utils.damp(body.rotation.x, target_rx, 10, dt)
	var target_sy := 0.72 if (crouched or slide_t > 0) else 1.0
	body.scale.y = Utils.damp(body.scale.y, target_sy, 10, dt)
	# 腿部行走动画(膝关节,与相机 bob 同步)
	var leg_l: Node3D = body.get_meta("leg_l")
	var leg_l_knee: Node3D = body.get_meta("leg_l_knee")
	var leg_r: Node3D = body.get_meta("leg_r")
	var leg_r_knee: Node3D = body.get_meta("leg_r_knee")
	if not prone:
		var speed_k := clampf(h_speed / 4.6, 0, 1)
		var swing := sin(bob_y) * speed_k * 0.58
		leg_l.rotation.x = Utils.damp(leg_l.rotation.x, swing, 14, dt)
		leg_r.rotation.x = Utils.damp(leg_r.rotation.x, -swing, 14, dt)
		leg_l_knee.rotation.x = Utils.damp(leg_l_knee.rotation.x, -maxf(0, sin(bob_y - 2.0)) * speed_k * 1.0, 12, dt)
		leg_r_knee.rotation.x = Utils.damp(leg_r_knee.rotation.x, -maxf(0, sin(bob_y - 2.0 + PI)) * speed_k * 1.0, 12, dt)
	else:
		# 趴下时腿伸直
		leg_l.rotation.x = Utils.damp(leg_l.rotation.x, 0.12, 8, dt)
		leg_r.rotation.x = Utils.damp(leg_r.rotation.x, -0.08, 8, dt)
		leg_l_knee.rotation.x = Utils.damp(leg_l_knee.rotation.x, 0.05, 8, dt)
		leg_r_knee.rotation.x = Utils.damp(leg_r_knee.rotation.x, 0.05, 8, dt)
