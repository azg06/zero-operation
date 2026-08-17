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
				"radius": 1.6, "seat": Vector3(-0.45, 1.62, 0.45), "vehicle_name": "侦察吉普", "weapon": null, "sus": 1.0,
				# [VEH-FIX] sus_ground 14→30 / sus_rate 6→8:BR 最大坡度 0.171 rad@17m/s 稳态滞后
				# 2.9/14=0.21m→2.9/30=0.097m(y-gh 偏差实测 max 0.128m>0.1m;平地恒 0 无感知差异)
				"sus_ground": 30.0, "sus_rate": 8.0 },
			"apc": { "hp": 2200.0, "max_speed": 11.0, "max_rev": -4.5, "accel": 6.0, "brake": 10.0, "turn": 1.1,
				"radius": 2.3, "seat": Vector3(0, 2.6, 0.6), "vehicle_name": "装甲步战车", "weapon": apc_w, "sus": 0.55,
				"sus_ground": 20.0, "sus_rate": 6.0 },
			"aa": { "hp": 1500.0, "max_speed": 12.5, "max_rev": -5.0, "accel": 7.0, "brake": 11.0, "turn": 1.3,
				"radius": 2.1, "seat": Vector3(0, 2.7, 1.2), "vehicle_name": "自行防空炮", "weapon": aa_w, "sus": 0.7,
				"sus_ground": 22.0, "sus_rate": 7.0 },
			"tank": { "hp": 3600.0, "max_speed": 8.5, "max_rev": -3.5, "accel": 4.5, "brake": 8.0, "turn": 0.85,
				"radius": 2.6, "seat": Vector3(0, 2.45, 0.3), "vehicle_name": "主战坦克", "weapon": null, "sus": 0.35,
				"sus_ground": 15.0, "sus_rate": 5.0 },
		}
	return _types


var type := "jeep"
var def: Dictionary
var pos := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var steer := 0.0
var driver = null                # 驾驶员(控制移动;只能驾驶,不能开炮)
var gunner = null                # 炮手/乘员(控制炮塔与开火;炮塔载具为炮手,吉普为乘客)
var hp := 900.0
var dead := false
var turret_yaw := 0.0
var turret_pitch := 0.0
var cannon_t := 0.0
var cannon_ammo := 20   # [8/10] 坦克主炮弹药(打空自动 8s 补弹)
var ai_input = null              # 驾驶员 AI 输入(由 Bot 每帧填充:fwd/steer)
var gunner_ai_input = null       # 炮手 AI 输入(由 Bot 每帧填充:turret_yaw/turret_pitch/fire)
var mesh: Node3D = null
var camera_ctl: VehicleCameraController = null   # 视角统一控制器(座位/状态机/第三人称)
# === 部位伤害(战地风格) ===
var track_hp := 1.0              # 履带/轮胎:低于 0.35 减速 + 转向变差
var engine_hp := 1.0             # 引擎:低于 0.35 动力下降
var part_regen_t := 0.0          # 停止受击后的恢复计时
# === 悬挂 ===
var sus_phase := 0.0
var sus_amp := 0.0
# === 贴地平滑(BR 起伏地形:阻尼 + 坡度速率限制;旧图平地恒 0 → 无感知差异) ===
var _sus_y := 0.0           # 平滑贴地高度
var _ground_ready := false  # 首帧直接贴合(防出生瞬间爬升)
var _pitch_s := 0.0         # 平滑俯仰角(转向过渡不抖)
var _roll_s := 0.0          # 平滑侧倾角
var respawn_protect := 0.0         # 重生保护剩余时间:无敌 + 半透明闪烁,防原地 pop-in
# === 渐进车损 + 残骸燃烧 ===
var _damage_stage := 0             # 车损档位:0=完好 1=焦痕(<60%) 2=重度焦痕+冒烟(<30%)
var _smoke_t := 0.0                # 重度车损冒烟间隔计时
var _burn_t := 0.0                 # 残骸燃烧剩余时间(前 12s 火焰,后 6s 余烬只烟)
var _burn_light: OmniLight3D = null
var _burn_timer := 0.0             # 燃烧粒子发射间隔计时
# === 卡死检测与脱困(滑动解析之外的兜底) ===
var stuck_t := 0.0              # 持续踩油门但净位移极小的累计时间
var stuck_net := Vector2.ZERO   # 卡死窗口内累计净位移(矢量求和,原地抖动互消)
var _still_t := 0.0             # [PERF] 静止空车累计时长(>1s 进入节流,跳过悬挂/地形/碰撞重采样)
var unstuck_t := 0.0            # 脱困剩余时间(>0 表示脱困中,驾驶输入被覆盖)
var unstuck_turn_t := 0.0       # 脱困阶段1(随机侧向原地转向)剩余时间
var unstuck_side := 0.0         # 脱困转向侧(±1;保留上次值用于交替换向)
var unstuck_disp := 0.0         # 脱困期间累计位移(恢复移动即提前退出)


func _init(x: float, z: float, p_yaw: float, p_type := "jeep") -> void:
	type = p_type
	def = TYPES()[p_type]
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
	camera_ctl = VehicleCameraController.new(self)
	add_child(camera_ctl)


func is_tank() -> bool:
	return type == "tank"


func has_turret() -> bool:
	return type != "jeep"


func team():
	if driver != null:
		return driver.team
	if gunner != null:
		return gunner.team
	return null


func seat_world() -> Vector3:
	return pos + (def["seat"] as Vector3).rotated(Vector3.UP, yaw)


## 乘客位世界坐标(吉普副驾 / 无人炮塔载具的炮手位兜底)
func passenger_world() -> Vector3:
	if type == "jeep":
		return pos + Vector3(0.45, 0, 0.45).rotated(Vector3.UP, yaw) + Vector3(0, def["seat"].y, 0)
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
	# [8/10] 坦克炮弹弹药系统:20 发备弹,打空自动长装填
	if cannon_ammo <= 0:
		cannon_t = 8.0   # 空仓补弹(长装填)
		if gunner == G.player or driver == G.player:
			G.hud.hint("炮弹耗尽 — 正在补弹 8s")
		return
	cannon_ammo -= 1
	cannon_t = 3.5
	var md := muzzle_world()
	var shell_def := { "damage": 230.0, "splash": 8.5, "speed": 75.0, "cn": "125mm 主炮", "name": "坦克主炮", "tracer": Color.html("#ffe0a0") }
	G.effects.spawn_rocket(shooter, shell_def, md[0], md[1])
	AudioSys.veh_weapon(type, pos)
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
	AudioSys.veh_weapon(type, pos)


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
	# 渐进车损:按耐久比例两阶段焦痕材质(一次性 set,避免每帧重复)
	var ratio: float = hp / float(def["hp"])
	if ratio < 0.3 and _damage_stage < 2:
		_damage_stage = 2
		_apply_damage_material(Color.html("#2a2824"), 0.9)
	elif ratio < 0.6 and _damage_stage < 1:
		_damage_stage = 1
		_apply_damage_material(Color.html("#3a3833"), 0.85)
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
	G.game.explode(pos + Vector3(0, 1, 0), 8, 110, attacker)
	# 驾驶员阵亡
	if driver != null:
		var d = driver
		driver = null
		ai_input = null
		if d == G.player:
			d.exit_vehicle(true)
			d.damage(300, pos, attacker, { "cn": "载具殉爆", "name": "殉爆" })
			print("[CREW] 载具殉爆 type=%s driver=player 乘员必死" % type)
		else:
			d.take_damage(9999.0, attacker, false, { "cn": "载具殉爆", "name": "殉爆" })
			print("[CREW] 载具殉爆 type=%s driver=bot%d 乘员必死" % [type, d.id])
	# 炮手/乘客阵亡
	if gunner != null:
		var g = gunner
		gunner = null
		gunner_ai_input = null
		if g == G.player:
			g.exit_vehicle(true)
			g.damage(300, pos, attacker, { "cn": "载具殉爆", "name": "殉爆" })
		else:
			g.take_damage(9999.0, attacker, false, { "cn": "载具殉爆", "name": "殉爆" })
	# 残骸外观
	var wreck_mat := StandardMaterial3D.new()
	wreck_mat.albedo_color = Color.html("#161412")
	wreck_mat.roughness = 1.0
	_set_all_materials(mesh, wreck_mat)
	mesh.position.y -= 0.25
	speed = 0
	AudioSys.engine_stop()
	_start_burn()


## 残骸燃烧启动:12s 火焰 + 6s 余烬,橙色 OmniLight 挂残骸上方(纯视觉,不产生伤害)
func _start_burn() -> void:
	_burn_t = 18.0
	_burn_timer = 0.0
	if _burn_light == null:
		_burn_light = OmniLight3D.new()
		_burn_light.light_color = Color.html("#ff7a20")
		_burn_light.omni_range = 9.0
		_burn_light.light_energy = 1.1
		_burn_light.shadow_enabled = false
		add_child(_burn_light)
	print("[BURN] 残骸燃烧开始 type=", type)


func _stop_burn() -> void:
	_burn_t = 0.0
	_burn_timer = 0.0
	if _burn_light != null:
		_burn_light.queue_free()
		_burn_light = null


## 残骸燃烧更新:车体前中后 3 点喷火 + 少量烟(间隔 0.12-0.18s),
## 灯光随燃烧时间 sin 闪烁衰减;12s 后余烬期只留烟,灯熄灭
func _update_burn(dt: float) -> void:
	var q: float = G.effects.fx_scale
	if _burn_light != null:
		_burn_light.position = pos + Vector3(0, def["seat"].y * 0.75, 0)
	if _burn_t > 6.0:
		_burn_timer -= dt
		if _burn_timer <= 0:
			_burn_timer = Utils.rand(0.12, 0.18)
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			for k in 3:
				var off := fwd * (k - 1) * float(def["radius"]) * 0.6
				var p := pos + Vector3(off.x + Utils.rand(-0.4, 0.4),
					def["seat"].y * 0.3 + Utils.rand(0.1, 0.5), off.z + Utils.rand(-0.4, 0.4))
				if randf() < q:
					G.effects.fire_spawn(p.x, p.y, p.z,
						Utils.rand(-0.4, 0.4), Utils.rand(0.4, 1.1), Utils.rand(-0.4, 0.4),
						Utils.rand(0.3, 0.55), Utils.rand(0.4, 0.7), Utils.rand(0.7, 1.3))
				if randf() < 0.5:
					G.effects.smoke_spawn(p.x, p.y, p.z,
						Utils.rand(-0.3, 0.3), Utils.rand(1.0, 2.2), Utils.rand(-0.3, 0.3),
						Utils.rand(0.5, 1.0), 0.2, 0.18, 0.16, -0.15, Utils.rand(0.8, 1.3))
		var k := clampf(_burn_t / 12.0, 0.2, 1.0)
		_burn_light.light_energy = 1.1 * k * (0.6 + 0.4 * sin(G.time * 26.0 + pos.x * 3.1))
	elif _burn_light != null:
		# 余烬期:只留烟,灯光熄灭
		_burn_timer -= dt
		if _burn_timer <= 0:
			_burn_timer = Utils.rand(0.25, 0.4)
			var p := pos + Vector3(Utils.rand(-0.8, 0.8), def["seat"].y * 0.4, Utils.rand(-0.8, 0.8))
			G.effects.smoke_spawn(p.x, p.y, p.z,
				Utils.rand(-0.3, 0.3), Utils.rand(1.2, 2.4), Utils.rand(-0.3, 0.3),
				Utils.rand(0.8, 1.4), 0.24, 0.22, 0.2, -0.2, Utils.rand(1.0, 1.6))
		_burn_light.light_energy = maxf(0.0, _burn_light.light_energy - dt * 2.0)
		if _burn_light.light_energy <= 0.0:
			_burn_light.queue_free()
			_burn_light = null


func _set_all_materials(node: Node, mat: Material) -> void:
	for o in node.get_children():
		if o is MeshInstance3D:
			o.material_override = mat
		# 内构(Interior/InteriorTurret)保留原材质:车内视角依赖内构可见,
		# 车损焦痕只作用于外部装甲
		if o.name == "Interior" or o.name == "InteriorTurret":
			continue
		_set_all_materials(o, mat)


## 车损焦痕材质一次性应用(比原色暗 35% 左右 + 高粗糙)
func _apply_damage_material(color: Color, rough: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	_set_all_materials(mesh, mat)


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
## [PERF] P0-2:与 Utils.move_collide 共用空间网格邻域查询(候选盒升序,行为与线性一致)
func _push_out(v: Vector3, radius: float) -> Vector3:
	if not Utils._bench_init:
		Utils.bench_init()
	var _bt0 := Time.get_ticks_usec() if Utils._bench else 0
	var p := v
	var colliders := G.colliders
	for _pass in 2:
		var seq: Variant = range(colliders.size()) if (Utils._grid.is_empty() or Utils._bench_linear) else Utils.colliders_near(p, radius)
		var pushed := false
		for i in seq:
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
	if Utils._bench:
		Utils._bench_veh_t += Time.get_ticks_usec() - _bt0
		Utils._bench_veh_n += 1
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
		# 残骸燃烧:被炸毁的载具保持残骸、不可驾驶不可开火,绝不自动复活
		# (车位载具由 _on_point_captured 在点位易主时重新部署新车)
		if _burn_t > 0 or _burn_light != null:
			_burn_t = maxf(0.0, _burn_t - dt)
			_update_burn(dt)
		return
	# 重度车损:车顶周期冒烟(0.5s 一次,参考 aircraft 冒烟参数)
	if _damage_stage >= 2:
		_smoke_t -= dt
		if _smoke_t <= 0:
			_smoke_t = 0.5
			G.effects.smoke_spawn(
				pos.x + Utils.rand(-0.35, 0.35), pos.y + def["seat"].y + Utils.rand(0.1, 0.4), pos.z + Utils.rand(-0.35, 0.35),
				Utils.rand(-0.3, 0.3), Utils.rand(1.0, 2.2), Utils.rand(-0.3, 0.3),
				Utils.rand(0.5, 1.0), 0.2, 0.18, 0.16, -0.15, Utils.rand(0.8, 1.3))
	# 重生保护:2s 内无敌 + 半透明闪烁;玩家上车后立即正常显示
	if respawn_protect > 0:
		respawn_protect = maxf(0.0, respawn_protect - dt)
		if driver == null:
			mesh.visible = (int(G.time * 10.0) % 2) == 0
		else:
			mesh.visible = true
		if respawn_protect <= 0:
			mesh.visible = true
	# [PERF] 静止空车节流:无乘员且停稳 >1s → 跳过驾驶/移动/碰撞/悬挂/地形重采样(外观位置不变),
	# 仅同步模型位置(可能被移动载具推挤微动);乘员上车/开动即恢复完整更新
	if driver == null and gunner == null and absf(speed) < 0.05 and absf(steer) < 0.05:
		_still_t += dt
		if _still_t > 1.0:
			mesh.position = pos
			mesh.rotation.y = yaw
			return
	else:
		_still_t = 0.0
	# 幽灵驾驶防护:阵亡后不再接受玩家输入(防止死后到重部署前仍可驾驶)
	var player_driving: bool = driver != null and driver == G.player and driver.alive
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
		AudioSys.engine_update(speed, def["max_speed"])
	elif driver != null and ai_input != null:
		# ---- AI 驾驶(驾驶员只驾驶,不开炮) ----
		var ai: Dictionary = ai_input
		if ai["fwd"] > 0.05:
			speed += eff_accel() * (0.55 + 0.45 * (1.0 - absf(speed) / maxf(def["max_speed"], 0.1))) * ai["fwd"] * dt
		elif ai["fwd"] < -0.05:
			speed += (-def["brake"] if speed > 0.5 else -eff_accel() * 0.65) * -ai["fwd"] * dt
		else:
			speed = Utils.damp(speed, 0, 1.6, dt)
		speed = clampf(speed, def["max_rev"], eff_max_speed() * 0.92)
		steer = Utils.damp(steer, clampf(ai["steer"], -1, 1), 6, dt)
	else:
		speed = Utils.damp(speed, 0, 2.5, dt)
		steer = Utils.damp(steer, 0, 6, dt)
	# ---- 炮手位:炮塔瞄准 + 开火(驾驶位不能开炮;只有坐在炮手位才能开火) ----
	if has_turret():
		var pitch_max := 1.22 if type == "aa" else 0.32
		var player_gunning: bool = gunner != null and gunner == G.player and gunner.alive
		if player_gunning:
			# 玩家炮手:炮塔跟随观察角瞄准(指哪打哪),左键开火
			var ctl = camera_ctl
			if ctl != null and ctl.turret_chase():
				turret_yaw = Utils.damp(turret_yaw, clampf(ctl.look_yaw, -2.6, 2.6), 12.0, dt)
				turret_pitch = Utils.damp(turret_pitch, clampf(ctl.look_pitch, -0.14, pitch_max), 12.0, dt)
			if Input.is_action_pressed("fire"):
				if is_tank():
					fire_cannon(gunner)
				else:
					fire_auto(gunner)
		elif gunner != null and gunner_ai_input != null:
			# AI 炮手:按目标角瞄准 + 开火
			var gai: Dictionary = gunner_ai_input
			turret_yaw = Utils.damp(turret_yaw, clampf(gai.get("turret_yaw", 0.0), -2.6, 2.6), 5.0, dt)
			turret_pitch = Utils.damp(turret_pitch, clampf(gai.get("turret_pitch", 0.0), -0.14, pitch_max), 5.0, dt)
			if gai.get("fire", false):
				if is_tank():
					fire_cannon(gunner)
				else:
					fire_auto(gunner)
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

	# 悬挂震动:地面高频颠簸(短波长起伏) + 车速 → 振幅(吉普颠簸、坦克沉稳)
	# [VEH-FIX] 颠簸度 = 2m 基距二阶差分与 6m 基距预测值的差值(高频分量):
	# 对任意平滑正弦地形 d2(2m) ≈ d2(6m)·(2/6)² = d2(6m)/9 → 差值≈0 → 不再触发
	# 持续人工颠簸(旧实现把局部坡度当颠簸度,起伏图 0.05 坡度即把 sus_amp 顶满
	# 0.055,实测 5-8Hz 恒晃 97% 时间);短波长真颠簸(碎石/凸起/棱坎)差值显著 → 照常触发。
	var rough := 0.0
	if G.ground_h.is_valid():
		var gh0: float = G.ground_h.call(pos.x, pos.z)
		var d2_2 := 0.0
		var d2_6 := 0.0
		for ax in 2:
			var px: float = sin(yaw) if ax == 0 else cos(yaw)
			var pz: float = cos(yaw) if ax == 0 else -sin(yaw)
			var h2p: float = G.ground_h.call(pos.x - px * 2, pos.z - pz * 2)
			var h2n: float = G.ground_h.call(pos.x + px * 2, pos.z + pz * 2)
			var h6p: float = G.ground_h.call(pos.x - px * 6, pos.z - pz * 6)
			var h6n: float = G.ground_h.call(pos.x + px * 6, pos.z + pz * 6)
			d2_2 += absf(h2p + h2n - 2.0 * gh0)
			d2_6 += absf(h6p + h6n - 2.0 * gh0)
		rough = 0.5 * maxf(0.0, d2_2 - d2_6 / 9.0)
		# 死区:剔除数值噪声级起伏(平地 ground_h 恒 0 → rough 恒 0,无任何人为颠簸)
		if rough < 0.005:
			rough = 0.0
	var sus_k: float = def.get("sus", 0.6)
	# [VEH-FIX] 振幅上限 0.055→0.03:旧上限在河岸 16-20m 平滑过渡边缘也会顶满,
	# 造成 6Hz 俯仰振荡单帧 0.07 rad 的瞬时甩动;新上限保留真颠簸(碎石/棱坎)触感,
	# 但幅度减半(±0.072 rad≈4.1°)——平地恒 0 不受影响
	sus_amp = Utils.damp(sus_amp, clampf(absf(speed) * rough * 2.0 * sus_k, 0, 0.03), 8, dt)
	if sus_amp < 0.0008:
		sus_amp = 0.0  # 指数平滑渐近不收敛到 0,残余微幅直接归零
	sus_phase += dt * (3.5 + absf(speed) * 1.6)

	# 地形贴合(BR 起伏:阻尼贴地 + 坡度速率限制;旧图平地 target 恒 0 → 行为不变)
	if G.ground_h.is_valid():
		var gh_t: float = G.ground_h.call(pos.x, pos.z)
		# 车体随地形倾斜采样(前后/左右 ±2m)
		var h_f: float = G.ground_h.call(pos.x - sin(yaw) * 2, pos.z - cos(yaw) * 2)
		var h_b: float = G.ground_h.call(pos.x + sin(yaw) * 2, pos.z + cos(yaw) * 2)
		var h_l: float = G.ground_h.call(pos.x + cos(yaw) * 2, pos.z - sin(yaw) * 2)
		var h_r: float = G.ground_h.call(pos.x - cos(yaw) * 2, pos.z + sin(yaw) * 2)
		if not _ground_ready:
			_sus_y = gh_t
			_pitch_s = atan2(h_f - h_b, 4)
			_roll_s = atan2(h_l - h_r, 4)
			_ground_ready = true
		# 低通平滑:帧率无关阻尼,k 按载具类型(坦克沉稳/吉普跟手)
		var sus_ground_k: float = def.get("sus_ground", 8.0)
		var step := Utils.damp(_sus_y, gh_t, sus_ground_k, dt) - _sus_y
		# 坡度变化率限制:每帧最大 y 变化(m/s × dt),防地形跳变/高速弹跳
		step = clampf(step, -def.get("sus_rate", 4.5) * dt, def.get("sus_rate", 4.5) * dt)
		_sus_y += step
		pos.y = _sus_y
		# 俯仰/侧倾角低通平滑(转向过渡不抖)+ 悬挂俯仰/侧倾叠加
		_pitch_s = Utils.damp(_pitch_s, atan2(h_f - h_b, 4), sus_ground_k * 1.3, dt)
		_roll_s = Utils.damp(_roll_s, atan2(h_l - h_r, 4), sus_ground_k * 1.3, dt)
		mesh.rotation_order = EULER_ORDER_YXZ
		mesh.rotation.x = _pitch_s + sin(sus_phase * 1.23) * sus_amp * 2.4
		mesh.rotation.z = _roll_s + sin(sus_phase * 0.83 + 1.7) * sus_amp * 2.4

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
	_stop_burn()
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
