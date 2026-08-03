class_name Vehicle extends Node3D
## 地面载具(对应 vehicles.js 的 Vehicle + TYPES + vehicleCollide)

static var _types: Dictionary = {}


static func TYPES() -> Dictionary:
	if _types.is_empty():
		var apc_w := WeaponsData.WeaponDef.new()
		apc_w.cn = "25mm 机炮"
		apc_w.name = "25mm 机炮"
		apc_w.kind = "lmg"
		apc_w.damage = 34
		apc_w.head_mult = 1.5
		apc_w.rpm = 240
		apc_w.rng = [70.0, 160.0, 0.55]
		apc_w.spread_hip = 0.7
		apc_w.tracer = Color.html("#ffe8a0")
		apc_w.veh_dmg = 0.8
		apc_w.bullet_speed = 1050.0
		apc_w.bullet_drop = 0.35
		apc_w.penetration = 1
		var aa_w := WeaponsData.WeaponDef.new()
		aa_w.cn = "四联高射机炮"
		aa_w.name = "高射机炮"
		aa_w.kind = "lmg"
		aa_w.damage = 16
		aa_w.head_mult = 1.2
		aa_w.rpm = 700
		aa_w.rng = [55.0, 120.0, 0.45]
		aa_w.spread_hip = 1.3
		aa_w.tracer = Color.html("#a0e8ff")
		aa_w.veh_dmg = 0.5
		aa_w.bullet_speed = 900.0
		aa_w.bullet_drop = 0.45
		aa_w.penetration = 1
		_types = {
			"jeep": { "hp": 900.0, "max_speed": 17.0, "max_rev": -6.5, "accel": 10.5, "brake": 15.0, "turn": 1.7,
				"radius": 1.6, "seat": Vector3(-0.45, 1.62, 0.45), "vehicle_name": "侦察吉普", "weapon": null, "sus": 1.0 },
			"apc": { "hp": 2200.0, "max_speed": 11.0, "max_rev": -4.5, "accel": 6.0, "brake": 10.0, "turn": 1.1,
				"radius": 2.3, "seat": Vector3(0, 2.6, 0.6), "vehicle_name": "装甲步战车", "weapon": apc_w, "sus": 0.55 },
			"aa": { "hp": 1500.0, "max_speed": 12.5, "max_rev": -5.0, "accel": 7.0, "brake": 11.0, "turn": 1.3,
				"radius": 2.1, "seat": Vector3(0, 2.7, 1.2), "vehicle_name": "自行防空炮", "weapon": aa_w, "sus": 0.7 },
			"tank": { "hp": 3600.0, "max_speed": 8.5, "max_rev": -3.5, "accel": 4.5, "brake": 8.0, "turn": 0.85,
				"radius": 2.6, "seat": Vector3(0, 2.45, 0.3), "vehicle_name": "主战坦克", "weapon": null, "sus": 0.35 },
		}
	return _types


var type := "jeep"
var def: Dictionary
var spawn_pos := Vector3.ZERO
var spawn_yaw := 0.0
var pos := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var steer := 0.0
var driver = null
var hp := 900.0
var dead := false
var wreck_t := 0.0
var turret_yaw := 0.0
var turret_pitch := 0.0
var cannon_t := 0.0
var ai_input = null              # AI 驾驶输入(由 Bot 每帧填充)
var mesh: Node3D = null
# === 部位伤害(战地风格) ===
var track_hp := 1.0              # 履带/轮胎:低于 0.35 减速 + 转向变差
var engine_hp := 1.0             # 引擎:低于 0.35 动力下降
var part_regen_t := 0.0          # 停止受击后的恢复计时
# === 悬挂 ===
var sus_phase := 0.0
var sus_amp := 0.0
var respawn_protect := 0.0         # 重生保护剩余时间:无敌 + 半透明闪烁,防原地 pop-in
var _wreck_warned := false         # 残骸重生倒计时提示已播
# === 卡死检测与脱困(滑动解析之外的兜底) ===
var stuck_t := 0.0              # 持续踩油门但净位移极小的累计时间
var stuck_net := Vector2.ZERO   # 卡死窗口内累计净位移(矢量求和,原地抖动互消)
var unstuck_t := 0.0            # 脱困剩余时间(>0 表示脱困中,驾驶输入被覆盖)
var unstuck_turn_t := 0.0       # 脱困阶段1(随机侧向原地转向)剩余时间
var unstuck_side := 0.0         # 脱困转向侧(±1;保留上次值用于交替换向)
var unstuck_disp := 0.0         # 脱困期间累计位移(恢复移动即提前退出)


func _init(x: float, z: float, p_yaw: float, p_type := "jeep") -> void:
	type = p_type
	def = TYPES()[p_type]
	spawn_pos = Vector3(x, 0, z)
	spawn_yaw = p_yaw
	pos = Vector3(x, 0, z)
	yaw = p_yaw
	hp = def["hp"]
	match p_type:
		"jeep":
			mesh = VehicleModels.build_jeep()
		"tank":
			mesh = VehicleModels.build_tank()
		"apc":
			mesh = VehicleModels.build_apc()
		"aa":
			mesh = VehicleModels.build_aa()
	mesh.position = pos
	mesh.rotation.y = yaw
	add_child(mesh)


func is_tank() -> bool:
	return type == "tank"


func has_turret() -> bool:
	return type != "jeep"


func team():
	return driver.team if driver != null else null


func alive() -> bool:
	return not dead


func seat_world() -> Vector3:
	return pos + (def["seat"] as Vector3).rotated(Vector3.UP, yaw)


## 炮口世界坐标与方向
func muzzle_world() -> Array:
	var mz: Node3D = mesh.get_meta("muzzle")
	var out := mz.global_position
	var ty := yaw + turret_yaw
	var dir := Vector3(-sin(ty) * cos(turret_pitch), sin(turret_pitch), -cos(ty) * cos(turret_pitch)).normalized()
	return [out, dir]


## 主炮(坦克,投射物)
func fire_cannon(shooter) -> void:
	if cannon_t > 0 or dead:
		return
	cannon_t = 3.5
	var md := muzzle_world()
	var shell_def := { "damage": 230.0, "splash": 8.5, "speed": 75.0, "cn": "125mm 主炮", "name": "坦克主炮", "tracer": Color.html("#ffe0a0") }
	G.effects.spawn_rocket(shooter, shell_def, md[0], md[1])
	AudioSys.rpg_fire(pos)
	G.effects.muzzle(md[0], md[1], true)
	G.effects.shake(1.1 if driver == G.player else 0.0)


## 机炮(APC/AA,直射)
func fire_auto(shooter) -> void:
	if cannon_t > 0 or dead or def["weapon"] == null:
		return
	var w = def["weapon"]
	cannon_t = 60.0 / w.rpm
	var md := muzzle_world()
	var dir: Vector3 = md[1]
	# 散布
	var a = Utils.rand(TAU)
	var r = sqrt(randf()) * w.spread_hip * (PI / 180.0)
	var right := Utils.safe_norm(Vector3(1, 0, 0).cross(dir), Vector3.FORWARD)
	var up2 := dir.cross(right)
	dir = (dir + right * (cos(a) * r) + up2 * (sin(a) * r)).normalized()
	# 弹道结算(下坠补偿 + 穿透 + 部位倍率)
	Utils.ballistic_fire(shooter, w, md[0], dir, md[0])
	G.effects.muzzle(md[0], dir, true)
	AudioSys.shoot("lmg", pos, shooter == G.player)


func damage(amount: float, attacker) -> void:
	if dead or respawn_protect > 0:
		return
	# 部位判定:受击引发履带/引擎损坏(按受击位置与概率)
	var part := _pick_part(attacker)
	if part == "track":
		track_hp = maxf(0.0, track_hp - amount / def["hp"] * 0.45)
		if driver == G.player and track_hp < 0.35:
			G.hud.hint("履带受损!速度与转向大幅下降")
	elif part == "engine":
		engine_hp = maxf(0.0, engine_hp - amount / def["hp"] * 0.4)
		if driver == G.player and engine_hp < 0.35:
			G.hud.hint("引擎受损!动力大幅下降")
	part_regen_t = 6.0
	hp -= amount
	if driver == G.player:
		G.hud.hint("载具耐久 " + str(maxi(0, int(ceil(hp / def["hp"] * 100)))) + "%")
	if hp <= 0:
		hp = 0
		destroy(attacker)


## 受击部位:后侧命中高概率伤引擎,其余 45% 概率伤履带
func _pick_part(attacker) -> String:
	if attacker != null and attacker.get("pos") != null:
		var apos: Vector3 = attacker["pos"]
		var fwd: Vector3 = Vector3(-sin(yaw), 0, -cos(yaw))
		var to_at: Vector3 = Vector3(apos.x - pos.x, 0, apos.z - pos.z)
		if to_at.length() > 0.01 and to_at.normalized().dot(fwd) < -0.2 and randf() < 0.65:
			return "engine"
	if randf() < 0.45:
		return "track"
	return "hull"


## 有效极速(履带/引擎损坏后下降)
func eff_max_speed() -> float:
	var s := def["max_speed"] as float
	if track_hp < 0.35:
		s *= 0.5
	if engine_hp < 0.35:
		s *= 0.75
	return s


## 有效加速(引擎损坏后动力不足)
func eff_accel() -> float:
	var a := def["accel"] as float
	if engine_hp < 0.35:
		a *= 0.45
	if track_hp < 0.35:
		a *= 0.75
	return a


## 有效转向速率(履带损坏后转向差)
func eff_turn() -> float:
	var t := def["turn"] as float
	if track_hp < 0.35:
		t *= 0.55
	return t


func destroy(attacker) -> void:
	if dead:
		return
	dead = true
	wreck_t = 0
	G.game.explode(pos + Vector3(0, 1, 0), 8, 110, attacker)
	# 驾驶员阵亡
	if driver != null:
		var d = driver
		driver = null
		ai_input = null
		if d == G.player:
			d.exit_vehicle(true)
			d.damage(300, pos, attacker, { "cn": "载具殉爆", "name": "殉爆" })
		else:
			d.take_damage(300, attacker, false, { "cn": "载具殉爆", "name": "殉爆" })
	# 残骸外观
	var wreck_mat := StandardMaterial3D.new()
	wreck_mat.albedo_color = Color.html("#161412")
	wreck_mat.roughness = 1.0
	_set_all_materials(mesh, wreck_mat)
	mesh.position.y -= 0.25
	speed = 0
	AudioSys.engine_stop()


func _set_all_materials(node: Node, mat: Material) -> void:
	for o in node.get_children():
		if o is MeshInstance3D:
			o.material_override = mat
		_set_all_materials(o, mat)


func respawn() -> void:
	mesh.queue_free()
	match type:
		"jeep":
			mesh = VehicleModels.build_jeep()
		"tank":
			mesh = VehicleModels.build_tank()
		"apc":
			mesh = VehicleModels.build_apc()
		"aa":
			mesh = VehicleModels.build_aa()
	add_child(mesh)
	pos = spawn_pos
	yaw = spawn_yaw
	hp = def["hp"]
	dead = false
	speed = 0
	steer = 0
	turret_yaw = 0
	turret_pitch = 0
	ai_input = null
	track_hp = 1.0
	engine_hp = 1.0
	part_regen_t = 0
	sus_amp = 0
	respawn_protect = 2.0
	_wreck_warned = false
	stuck_t = 0.0
	stuck_net = Vector2.ZERO
	unstuck_t = 0.0
	unstuck_turn_t = 0.0
	unstuck_side = 0.0
	unstuck_disp = 0.0


## ==================== 滑动移动与脱困 ====================

## 载具滑动移动:位移被碰撞阻挡时,把剩余位移分解到碰撞表面切平面继续滑行
## (最多 3 次迭代),使贴墙/贴箱载具滑行通过而非原地抖动卡死;边界墙仅夹紧
func _slide_move(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var cur := from
	var rem := to - from
	for _iter in 3:
		var target := cur + rem
		var resolved := _push_out(target, radius)
		var px := resolved.x - target.x
		var pz := resolved.z - target.z
		var plen := sqrt(px * px + pz * pz)
		if plen < 0.003:
			cur = resolved
			break
		# 接触法线 ≈ 推出方向;剔除沿法线位移,保留切平面分量继续滑
		var nx := px / plen
		var nz := pz / plen
		var dn := rem.x * nx + rem.z * nz
		rem.x -= nx * dn
		rem.z -= nz * dn
		cur = resolved
		if rem.x * rem.x + rem.z * rem.z < 1e-8:
			break
	cur.x = clampf(cur.x, -G.bounds, G.bounds)
	cur.z = clampf(cur.z, -G.bounds, G.bounds)
	return cur


## 推挤解算(两遍,与 Utils.move_collide 语义一致):矮障碍(盒顶 ≤ 车底+0.55m)
## 可骑越;2.2m 视为车体高度
func _push_out(v: Vector3, radius: float) -> Vector3:
	var p := v
	var colliders := G.colliders
	for _pass in 2:
		var pushed := false
		for i in colliders.size():
			var b: AABB = colliders[i]
			if p.y + 0.55 >= b.end.y or p.y + 2.2 <= b.position.y:
				continue
			var cx := clampf(p.x, b.position.x, b.end.x)
			var cz := clampf(p.z, b.position.z, b.end.z)
			var dx := p.x - cx
			var dz := p.z - cz
			var d2 := dx * dx + dz * dz
			if d2 < radius * radius:
				if d2 > 1e-10:
					var d := sqrt(d2)
					var push := (radius - d) / d
					p.x += dx * push
					p.z += dz * push
				else:
					# 圆心在盒内:沿最小穿透轴推出
					var px1 := p.x - b.position.x + radius
					var px2 := b.end.x - p.x + radius
					var pz1 := p.z - b.position.z + radius
					var pz2 := b.end.z - p.z + radius
					var m := minf(minf(px1, px2), minf(pz1, pz2))
					if m == px1:
						p.x = b.position.x - radius
					elif m == px2:
						p.x = b.end.x + radius
					elif m == pz1:
						p.z = b.position.z - radius
					else:
						p.z = b.end.z + radius
				pushed = true
		if not pushed:
			break
	return p


## 进入脱困:随机侧向原地转向 0.6-1.2s + 倒车 0.8s;面朝边界墙则跳过转向直接倒车
func _begin_unstuck() -> void:
	stuck_t = 0.0
	stuck_net = Vector2.ZERO
	unstuck_disp = 0.0
	unstuck_side = -unstuck_side if absf(unstuck_side) > 0.5 else (1.0 if randf() < 0.5 else -1.0)
	unstuck_turn_t = Utils.rand(0.6, 1.2)
	# 面朝边界墙:直接反向倒车,不做无谓乱转
	var ahead := pos + Vector3(-sin(yaw), 0, -cos(yaw)) * (def["radius"] as float + 1.5)
	if absf(ahead.x) > G.bounds - 0.5 or absf(ahead.z) > G.bounds - 0.5:
		unstuck_turn_t = 0.0
	unstuck_t = unstuck_turn_t + 0.8


func update_vehicle(dt: float) -> void:
	if dead:
		# 炸毁 10 秒后在出生点重新部署(末 2 秒提示,重生自带 2s 无敌保护)
		wreck_t += dt
		if wreck_t > 8 and not _wreck_warned:
			_wreck_warned = true
			G.hud.hint("载具即将在出生点重新部署(重生保护 2s)")
		if wreck_t > 10:
			respawn()
		return
	# 重生保护:2s 内无敌 + 半透明闪烁;玩家上车后立即正常显示
	if respawn_protect > 0:
		respawn_protect = maxf(0.0, respawn_protect - dt)
		if driver == null:
			mesh.visible = (int(G.time * 10.0) % 2) == 0
		else:
			mesh.visible = true
		if respawn_protect <= 0:
			mesh.visible = true
	# 幽灵驾驶防护:阵亡后不再接受玩家输入(防止死后到重部署前仍可驾驶)
	var player_driving: bool = driver == G.player and driver.alive
	if player_driving:
		var fwd := (1 if Input.is_action_pressed("move_forward") else 0) - (1 if Input.is_action_pressed("move_back") else 0)
		var steer_in := (1 if Input.is_action_pressed("move_left") else 0) - (1 if Input.is_action_pressed("move_right") else 0)
		if fwd > 0:
			# 加速曲线:低速高推重比,接近极速时衰减(真实感)
			speed += eff_accel() * (0.55 + 0.45 * (1.0 - absf(speed) / maxf(def["max_speed"], 0.1))) * dt
		elif fwd < 0:
			speed += (-def["brake"] if speed > 0.5 else -eff_accel() * 0.65) * dt
		else:
			speed = Utils.damp(speed, 0, 1.4, dt)
		speed = clampf(speed, def["max_rev"], eff_max_speed())
		steer = Utils.damp(steer, float(steer_in), 8, dt)
		# 炮塔随鼠标(防空炮仰角提到 70° 以对空)
		if has_turret():
			var md: Vector2 = G.input_sys.consume_mouse()
			var pitch_max := 1.22 if type == "aa" else 0.32
			turret_yaw = clampf(turret_yaw - md.x * 0.002 * G.settings.sensitivity, -2.6, 2.6)
			turret_pitch = clampf(turret_pitch - md.y * 0.0016 * G.settings.sensitivity, -0.14, pitch_max)
			if Input.is_action_pressed("fire"):
				if is_tank():
					fire_cannon(driver)
				else:
					fire_auto(driver)
		AudioSys.engine_update(speed * (0.5 if is_tank() else 1.0))
	elif driver != null and ai_input != null:
		# ---- AI 驾驶 ----
		var ai: Dictionary = ai_input
		if ai["fwd"] > 0.05:
			speed += eff_accel() * (0.55 + 0.45 * (1.0 - absf(speed) / maxf(def["max_speed"], 0.1))) * ai["fwd"] * dt
		elif ai["fwd"] < -0.05:
			speed += (-def["brake"] if speed > 0.5 else -eff_accel() * 0.65) * -ai["fwd"] * dt
		else:
			speed = Utils.damp(speed, 0, 1.6, dt)
		speed = clampf(speed, def["max_rev"], eff_max_speed() * 0.92)
		steer = Utils.damp(steer, clampf(ai["steer"], -1, 1), 6, dt)
		# 炮塔指向 AI 目标角
		var ai_pitch_max := 1.22 if type == "aa" else 0.32
		turret_yaw = Utils.damp(turret_yaw, clampf(ai.get("turret_yaw", 0.0), -2.6, 2.6), 4, dt)
		turret_pitch = Utils.damp(turret_pitch, clampf(ai.get("turret_pitch", 0.0), -0.14, ai_pitch_max), 4, dt)
		if ai["fire"]:
			if is_tank():
				fire_cannon(driver)
			else:
				fire_auto(driver)
	else:
		speed = Utils.damp(speed, 0, 2.5, dt)
		steer = Utils.damp(steer, 0, 6, dt)
	# 踩油门判定(前进/倒车都算;AI 阈值避开到点后的 0.1 蠕动,防止原地误判)
	var throttle_on := false
	if player_driving:
		throttle_on = ((1 if Input.is_action_pressed("move_forward") else 0)
			- (1 if Input.is_action_pressed("move_back") else 0)) != 0
	elif driver != null and ai_input != null:
		throttle_on = absf(ai_input["fwd"]) > 0.25
	# ---- 脱困:覆盖驾驶输入(玩家与 AI 一致) ----
	if unstuck_t > 0:
		unstuck_t -= dt
		if unstuck_turn_t > 0:
			# 阶段1:随机侧向原地转向甩头(小幅前进配合,让车头侧出)
			unstuck_turn_t -= dt
			steer = unstuck_side
			speed = Utils.damp(speed, 1.2, 2.0, dt)
		else:
			# 阶段2:倒车拉开
			steer = unstuck_side
			speed = Utils.damp(speed, def["max_rev"] * 0.85, 3.0, dt)
		if unstuck_t <= 0:
			unstuck_t = 0.0
	cannon_t = maxf(0, cannon_t - dt)
	# 部位恢复:停火 6 秒后缓慢自愈(工程兵维修是主要手段)
	part_regen_t = maxf(0, part_regen_t - dt)
	if part_regen_t <= 0:
		track_hp = minf(1.0, track_hp + dt * 0.12)
		engine_hp = minf(1.0, engine_hp + dt * 0.08)

	# 履带/轮式转向(转向半径随速度增大;履带车高速转向更迟钝)
	var moving: bool = (absf(speed) > 0.05 or absf(steer) > 0.1) if has_turret() else absf(speed) > 0.3
	if moving:
		var rate: float = eff_turn() / (1.0 + absf(speed) * (0.28 if has_turret() else 0.13))
		yaw += steer * rate * dt * (1.0 if has_turret() else signf(speed))

	# 移动与碰撞(静态世界):滑动解析——位移被阻挡时剔除法线分量,沿切平面继续滑行
	var prev_pos := pos
	if absf(speed) > 0.01:
		var dx = -sin(yaw) * speed * dt
		var dz = -cos(yaw) * speed * dt
		pos = _slide_move(pos, pos + Vector3(dx, 0, dz), def["radius"])
		# 被碰撞强烈阻挡(净位移远小于期望)才减速;贴墙滑行保留切向分量,不误伤
		var disp := Vector2(pos.x - prev_pos.x, pos.z - prev_pos.z)
		var desired := absf(speed) * dt
		if desired > 0.01 and disp.length() < desired * 0.45:
			if disp.length() < desired * 0.2:
				if absf(speed) > 8:
					G.effects.shake(0.5)
					AudioSys.ricochet(pos)
				speed *= 0.35
			else:
				speed *= 0.8
		if absf(speed) > 5 and randf() < 0.5:
			G.effects.smoke_spawn(
				pos.x + Utils.rand(-1, 1), 0.25, pos.z + Utils.rand(-1, 1),
				Utils.rand(-0.6, 0.6), Utils.rand(0.6, 1.6), Utils.rand(-0.6, 0.6),
				Utils.rand(0.4, 0.9), 0.62, 0.58, 0.48, 0.08)
		# 碾压敌人(重生保护期间不碾压,防原地刷新秒人)
		if absf(speed) > 4 and driver != null and respawn_protect <= 0:
			for b in G.bots:
				if not b.alive or b.team == driver.team:
					continue
				if Vector2(b.pos.x - pos.x, b.pos.z - pos.z).length() < def["radius"] + 0.8:
					G.effects.blood(Vector3(b.pos.x, 1.1, b.pos.z), Vector3.UP)
					b.take_damage(500, driver, false, { "cn": "载具碾压", "name": "载具" })
					G.effects.shake(0.45 if driver == G.player else 0.0)

	# 载具间实体碰撞(不再互相穿模)
	for v in G.vehicles:
		if v == self:
			continue
		var rr: float = def["radius"] + v.def["radius"]
		var dx = pos.x - v.pos.x
		var dz = pos.z - v.pos.z
		var d2 = dx * dx + dz * dz
		if d2 > 1e-6 and d2 < rr * rr:
			var d := sqrt(d2)
			var push := (rr - d) / d * 0.5
			pos.x += dx * push
			pos.z += dz * push
			if v.driver == null:
				v.pos.x -= dx * push * 0.5
				v.pos.z -= dz * push * 0.5
			speed *= 0.6

	# 卡死检测:持续踩油门但净位移 < 0.05m/s(窗口内平均值)连续 1.5s → 判定卡住,进入脱困
	if throttle_on:
		stuck_t += dt
		stuck_net += Vector2(pos.x - prev_pos.x, pos.z - prev_pos.z)
		if stuck_net.length() > 0.05 * stuck_t:
			# 平均速度达标 → 未被卡死(含坡道爬升/贴墙滑行),重置窗口
			stuck_t = 0.0
			stuck_net = Vector2.ZERO
		elif stuck_t >= 1.5 and unstuck_t <= 0:
			_begin_unstuck()
	else:
		stuck_t = 0.0
		stuck_net = Vector2.ZERO
	# 脱困期间恢复位移 → 已脱困,提前结束
	if unstuck_t > 0:
		unstuck_disp += Vector2(pos.x - prev_pos.x, pos.z - prev_pos.z).length()
		if unstuck_disp > 0.6:
			unstuck_t = 0.0

	# 悬挂震动:地面起伏 + 车速 → 振幅(吉普颠簸、坦克沉稳)
	var rough := 0.0
	if G.ground_h.is_valid():
		var gh0: float = G.ground_h.call(pos.x, pos.z)
		rough = absf(gh0 - G.ground_h.call(pos.x - sin(yaw) * 2, pos.z - cos(yaw) * 2))
		rough += absf(gh0 - G.ground_h.call(pos.x + cos(yaw) * 2, pos.z - sin(yaw) * 2))
		rough *= 0.5
		# 死区:剔除数值噪声级起伏(平地 ground_h 恒 0 → rough 恒 0,无任何人为颠簸)
		if rough < 0.01:
			rough = 0.0
	var sus_k: float = def.get("sus", 0.6)
	sus_amp = Utils.damp(sus_amp, clampf(absf(speed) * rough * 2.0 * sus_k, 0, 0.055), 8, dt)
	if sus_amp < 0.0008:
		sus_amp = 0.0  # 指数平滑渐近不收敛到 0,残余微幅直接归零
	sus_phase += dt * (3.5 + absf(speed) * 1.6)

	# 地形贴合
	if G.ground_h.is_valid():
		pos.y = G.ground_h.call(pos.x, pos.z)
		# 车体随地形倾斜 + 悬挂俯仰/侧倾叠加
		var h_f: float = G.ground_h.call(pos.x - sin(yaw) * 2, pos.z - cos(yaw) * 2)
		var h_b: float = G.ground_h.call(pos.x + sin(yaw) * 2, pos.z + cos(yaw) * 2)
		var h_l: float = G.ground_h.call(pos.x + cos(yaw) * 2, pos.z - sin(yaw) * 2)
		var h_r: float = G.ground_h.call(pos.x - cos(yaw) * 2, pos.z + sin(yaw) * 2)
		mesh.rotation_order = EULER_ORDER_YXZ
		mesh.rotation.x = atan2(h_f - h_b, 4) + sin(sus_phase * 1.23) * sus_amp * 2.4
		mesh.rotation.z = atan2(h_l - h_r, 4) + sin(sus_phase * 0.83 + 1.7) * sus_amp * 2.4

	# 同步模型
	mesh.position = pos
	mesh.position.y += sin(sus_phase) * sus_amp * 0.6 + sin(sus_phase * 1.7 + 1.1) * sus_amp * 0.4
	mesh.rotation.y = yaw
	# 高速行驶悬挂冲击(仅玩家驾驶时震相机;仅地面起伏时触发,平地无源震动禁止)
	if driver == G.player and absf(speed) > 12 and rough > 0.0 and randf() < dt * 3:
		G.effects.shake(0.05)
	if mesh.has_meta("wheels"):
		for w in mesh.get_meta("wheels"):
			w.rotation.x += speed * dt / 0.42
	if type == "jeep":
		if mesh.has_meta("front_wheels"):
			for p in mesh.get_meta("front_wheels"):
				p.rotation.y = steer * 0.42
	else:
		(mesh.get_meta("turret") as Node3D).rotation.y = turret_yaw
		# rotation.x 正值=炮口上扬,与 turret_pitch 同号(原负号导致俯仰反向)
		(mesh.get_meta("cannon") as Node3D).rotation.x = turret_pitch


func dispose() -> void:
	queue_free()


## ==================== 步兵 vs 载具实体碰撞 ====================
static func vehicle_collide(p_pos: Vector3, radius: float) -> Vector3:
	for v in G.vehicles:
		var rr: float = radius + v.def["radius"] * 0.92
		var dx = p_pos.x - v.pos.x
		var dz = p_pos.z - v.pos.z
		var d2 = dx * dx + dz * dz
		if d2 > 1e-6 and d2 < rr * rr:
			# 驾驶员本人不受自己载具推挤
			if G.player != null and G.player.vehicle == v:
				continue
			var d := sqrt(d2)
			var push := (rr - d) / d
			p_pos.x += dx * push
			p_pos.z += dz * push
	return p_pos
