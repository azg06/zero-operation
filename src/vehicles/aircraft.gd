class_name Aircraft extends Node3D
## 空中载具:武装直升机 / 战斗机(征服模式,AI 驾驶)(对应 aircraft.js)

var team := "us"
var type := "heli"               # heli | jet
var air := true
var craft_name := "武装直升机"
var def: Dictionary
var radius := 4.0
var hp := 1100.0
var max_hp := 1100.0
var dead := false
var crashing := false
var respawn_t := 0.0
var pilot: Dictionary            # 击杀归属(虚拟飞行员)
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var mesh: Node3D = null
var target = null
var fire_t := 0.0
var rocket_t := 0.0
var think_t := 0.0
var wp := Vector3.ZERO
var wp_t := 0.0
var strafe = null                # 战斗机俯冲航线 { tx, tz, rocket_fired }
# === 直升机战术机动状态机(cruise/orbit/strafe/disengage/rtb/land) ===
var mode := "cruise"          # 巡航 | 盘旋 | 俯冲扫射 | 脱离 | 返航 | 降落
var mode_t := 0.0             # 当前模式剩余时长(攻击会话 3-6s)
var orbit_dir := 1.0          # 盘旋方向 ±1(逆/顺时针随机)
var orbit_r := 75.0           # 盘旋半径(60-90m)
var orbit_ws := 0.35          # 盘旋角速度(0.25-0.5 rad/s)
var orbit_ang := 0.0          # 盘旋当前角
var orbit_alt := 38.0         # 攻击高度(30-45m)
var strafe_phase := "dive"    # 俯冲扫射阶段: dive | run | climb
var strafe_t := 0.0           # 俯冲阶段计时
var strafe_cd := 6.0          # 俯冲扫射间隔(4-8s)
var injured := false          # 受伤模式(hp<55%):攻击间隔×2、保持 70m+ 距离
var injured_t := 0.0          # 重伤评估计时(15s,<35% → 返航)
var rtb_t := 0.0              # 返航盘旋回血计时(8s,20/s)
var cruise_alt := 55.0        # 巡航高度目标(40-70m)
var drift_phase := 0.0        # 盘旋/悬停漂移相位
# === 飞行物理(速度/失速/滚转) ===
var airspeed := 10.0             # 当前水平空速
var prev_yaw := 0.0              # 上一帧机头角(滚转率估计)
var stall_t := 0.0               # 失速计时
var landing := false             # 重伤返航降落
var landed := false              # 已落地待修
var _eng_a: AudioStreamPlayer3D = null      # 引擎档位 player A/B(交叉淡化交替)
var _eng_b: AudioStreamPlayer3D = null
var _eng_streams: Array[AudioStreamWAV] = []  # 档位采样(heli: v1/v2;jet: v0/v2)
var _eng_gear := 0                          # 当前档位
var _eng_fade_in_t := 0.0                   # 新档淡入剩余时长(>0 时音量由计时器爬升)
var _eng_tween: Tween = null                # 旧档淡出 tween(0.15s → -60dB 后停)
var _eng_vol := 0.0                         # 稳态目标音量平滑值(jet 0↔0.44 渐变)
# === 坠毁残骸燃烧(坠地即销毁 → 坠毁点生成 8s 燃烧现场:火焰+烟+光) ===
var _burn_t := 0.0                          # 燃烧剩余时间
var _burn_light: OmniLight3D = null
var _burn_timer := 0.0                      # 粒子发射间隔计时
var _crash_burn_pos := Vector3.ZERO         # 坠毁点


func _init(p_team: String, p_type: String) -> void:
	team = p_team
	type = p_type
	craft_name = "武装直升机" if type == "heli" else "战斗机"
	radius = 4.0 if type == "heli" else 3.2
	def = { "name": craft_name, "cn": craft_name, "radius": radius }
	hp = 1100.0 if type == "heli" else 800.0
	max_hp = hp
	rocket_t = Utils.rand(2, 4)
	think_t = Utils.rand(0.3)
	pilot = { "team": team, "name": craft_name, "air": true, "pos": pos, "kills": 0 }
	mesh = AircraftModels.build_heli(team) if type == "heli" else AircraftModels.build_jet(team)
	mesh.visible = false
	add_child(mesh)
	_setup_engine_sound()
	_spawn()


## 引擎/呼啸 3D 循环音:按机型加载专属档位采样(heli=heli_engine_v1/v2 低速/高速旋翼,
## jet=fighter_engine_v0/v2 待命/俯冲),A/B 双 player 交叉淡化切换,3D 距离衰减
func _setup_engine_sound() -> void:
	var base := "heli" if type == "heli" else "fighter"
	var names := ["engine_v1", "engine_v2"] if type == "heli" else ["engine_v0", "engine_v2"]
	for i in 2:
		var p := AudioStreamPlayer3D.new()
		p.bus = AudioSys.BUS_SFX
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 20.0
		p.max_distance = 420.0
		p.position = pos
		add_child(p)
		if i == 0:
			_eng_a = p
		else:
			_eng_b = p
		var s: AudioStreamWAV = load("res://audio/engines/%s_%s.wav" % [base, names[i]])
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		_eng_streams.append(s)
	_eng_a.stream = _eng_streams[0]
	_eng_a.volume_db = linear_to_db(0.002)
	_eng_gear = 0


func _eng_player() -> AudioStreamPlayer3D:
	return _eng_a if _eng_gear == 0 else _eng_b


## 档位交叉淡化:旧 player 0.15s 淡出至 -60dB 后停(防换流爆音),新档采样载入
## 另一 player 以 0.004 起步播放,淡入音量由 _eng_update_sound 计时器爬升(0.25s)
func _eng_set_gear(gear: int) -> void:
	if gear == _eng_gear or gear >= _eng_streams.size():
		return
	var old := _eng_player()
	_eng_gear = gear
	if _eng_tween != null:
		_eng_tween.kill()
	_eng_tween = old.create_tween()
	# 起点夹取:旧 player 音量可能已是 -inf(linear_to_db(0)),直接由此插值会得 NaN,
	# 故 from 起点钳到 -60dB 以上,确保 lerp 数值有效
	_eng_tween.tween_property(old, "volume_db", -60.0, 0.15).from(maxf(old.volume_db, -60.0))
	_eng_tween.tween_callback(old.stop)
	var newp := _eng_player()
	newp.stop()
	newp.stream = _eng_streams[gear]
	newp.pitch_scale = 1.0
	newp.volume_db = linear_to_db(0.004)
	newp.position = pos
	newp.play()
	_eng_fade_in_t = 0.25


## 引擎音随速联动:档位按 speed_ratio 切换(2 档 → ≤0.45 档0 否则档1);
## 新采样真实,音高仅微调 0.92-1.12(jet 不再靠变调模拟呼啸);
## 淡入期音量由计时器控制,稳态音量平滑跟踪 vol_target(jet 待命淡至 0)
func _eng_update_sound(speed_ratio: float, vol_target: float, dt: float) -> void:
	if _eng_a == null:
		return
	_eng_a.position = pos
	_eng_b.position = pos
	var n := _eng_streams.size()
	var gear := 0
	if n == 2:
		gear = 1 if speed_ratio > 0.45 else 0
	elif n >= 3:
		gear = 2 if speed_ratio > 0.65 else (1 if speed_ratio > 0.3 else 0)
	if gear != _eng_gear:
		_eng_set_gear(gear)
	var p := _eng_player()
	p.pitch_scale = lerpf(0.92, 1.12, speed_ratio)
	_eng_vol = lerpf(_eng_vol, vol_target, minf(1.0, dt * 6.0))
	if _eng_fade_in_t > 0:
		_eng_fade_in_t -= dt
		if _eng_fade_in_t > 0:
			p.volume_db = linear_to_db(maxf(lerpf(0.004, _eng_vol, 1.0 - _eng_fade_in_t / 0.25), 0.0001))
			return
	# 稳态:音量平滑跟踪;目标≈0 时淡出至静音阈值后才停,防止静音下反复播放/停止
	if _eng_vol <= 0.004:
		p.volume_db = linear_to_db(maxf(_eng_vol, 0.0001))
		if p.playing and p.volume_db <= linear_to_db(0.008):
			p.stop()
	elif not p.playing:
		# 从静音恢复:先给基础音量再播放,避免从 -inf 慢慢爬升
		p.volume_db = linear_to_db(maxf(_eng_vol, 0.02))
		p.play()
	else:
		p.volume_db = linear_to_db(maxf(_eng_vol, 0.0001))


func _spawn() -> void:
	_stop_crash_burn()
	var B: float = G.bounds if G.bounds > 0 else 150.0
	if type == "heli":
		# 从己方基地上空出发
		var bz := -B + 20 if team == "us" else B - 20
		pos = Vector3(Utils.rand(-30, 30), 55, bz + Utils.rand(-10, 10))
		vel = Vector3.ZERO
		hp = max_hp
		dead = false
		crashing = false
		airspeed = 10.0
		stall_t = 0
		landing = false
		landed = false
		mesh.visible = true
		_pick_waypoint(true)
		mode = "cruise"
		mode_t = 0.0
		strafe_cd = Utils.rand(4, 8)
		injured = false
		injured_t = 0.0
		rtb_t = 0.0
		cruise_alt = Utils.rand(40, 70)
		drift_phase = Utils.rand(TAU)
	else:
		# 战斗机:地图外待命,定时俯冲
		mesh.visible = false
		dead = false
		crashing = false
		hp = max_hp
		respawn_t = Utils.rand(8, 16)
		strafe = null


func _pick_waypoint(force := false) -> void:
	if not force and wp_t > 0:
		return
	# 巡航点:有争议/敌方旗帜上空
	var pool := []
	for f in G.flags:
		if f.owner_team != team:
			pool.append(f)
	var f: Flag = Utils.choice(pool) if not pool.is_empty() else Utils.choice(G.flags)
	var cx := f.pos.x if f != null else 0.0
	var cz := f.pos.z if f != null else 0.0
	wp = Vector3(cx + Utils.rand(-45, 45), 0, cz + Utils.rand(-45, 45))
	wp_t = Utils.rand(6, 10)
	cruise_alt = Utils.rand(40, 70)


func _acquire():
	var best = null
	var best_d := 150.0
	for b in G.bots:
		if not b.alive or b.team == team or b.vehicle != null:
			continue
		var d: float = pos.distance_to(b.pos)
		if d < best_d:
			if Utils.los_clear(pos, b.pos + Vector3(0, 1.2, 0)):
				best = b
				best_d = d
	if G.player != null and G.player.alive and G.player.team != team:
		var d2: float = pos.distance_to(G.player.pos)
		if d2 < best_d:
			if Utils.los_clear(pos, G.player.pos + Vector3(0, 1.2, 0)):
				best = G.player
	return best


func damage(amount: float, attacker) -> void:
	if dead:
		return
	hp -= amount
	# 受损减速/冒烟(受损越重,机动越差)
	if hp < max_hp * 0.4 and hp > 0 and randf() < 0.35:
		G.effects.smoke_spawn(pos.x, pos.y - 1, pos.z, Utils.rand(-0.5, 0.5), Utils.rand(1, 2), Utils.rand(-0.5, 0.5),
			Utils.rand(0.3, 0.7), 0.2, 0.18, 0.16, 0.1)
	if hp <= 0:
		hp = 0
		dead = true
		crashing = true
		respawn_t = 30.0 if type == "heli" else 24.0
		# 失控下坠
		vel.y = -6
		vel.x += Utils.rand(-6, 6)
		vel.z += Utils.rand(-6, 6)
		G.effects.explosion(pos, 4)
		var k_name: String = "战场"
		var k_team = team
		if attacker != null:
			k_name = "你" if Game.is_player(attacker) else (attacker.get("name") if attacker.get("name") != null else "战场")
			# 攻击者阵营兼容获取:Bot/Player/飞行员字典的 team 为键值,Vehicle 的 team 是方法(vehicle.gd:115),
			# 直接 get("team") 对 Vehicle 返回 null → 击杀播报阵营色错误,需 get 失败后 call 兜底
			var atk_team = attacker.get("team")
			if atk_team == null and attacker is Object and attacker.has_method("team"):
				atk_team = attacker.call("team")
			k_team = atk_team if atk_team != null else k_team
		G.hud.add_killfeed(k_name, k_team, craft_name, team, "防空火力", false, Game.is_player(attacker))


## 坠毁点燃烧启动:8s 火焰 + 烟 + 橙色灯光(纯视觉,残骸无实体)
func _start_crash_burn(p: Vector3) -> void:
	_crash_burn_pos = p
	_burn_t = 8.0
	_burn_timer = 0.0
	if _burn_light == null:
		_burn_light = OmniLight3D.new()
		_burn_light.light_color = Color.html("#ff7a20")
		_burn_light.omni_range = 9.0
		_burn_light.light_energy = 1.1
		_burn_light.shadow_enabled = false
		add_child(_burn_light)
	print("[BURN] 坠毁残骸燃烧开始 type=", type)


func _stop_crash_burn() -> void:
	_burn_t = 0.0
	_burn_timer = 0.0
	if _burn_light != null:
		_burn_light.queue_free()
		_burn_light = null


## 坠毁燃烧更新:坠毁点随机喷火 + 少量烟(间隔 0.14-0.2s),灯光 sin 闪烁衰减
func _update_crash_burn(dt: float) -> void:
	if _burn_light != null:
		_burn_light.position = _crash_burn_pos + Vector3(0, 2.2, 0)
	_burn_timer -= dt
	if _burn_timer <= 0 and _burn_t > 0:
		_burn_timer = Utils.rand(0.14, 0.2)
		var q: float = G.effects.fx_scale
		for k in 3:
			var p := _crash_burn_pos + Vector3(Utils.rand(-1.5, 1.5), Utils.rand(0.2, 1.0), Utils.rand(-1.5, 1.5))
			if randf() < q:
				G.effects.fire_spawn(p.x, p.y, p.z,
					Utils.rand(-0.5, 0.5), Utils.rand(0.6, 1.4), Utils.rand(-0.5, 0.5),
					Utils.rand(0.35, 0.6), Utils.rand(0.5, 0.8), Utils.rand(0.8, 1.4))
			if randf() < 0.5:
				G.effects.smoke_spawn(p.x, p.y, p.z,
					Utils.rand(-0.4, 0.4), Utils.rand(1.2, 2.5), Utils.rand(-0.4, 0.4),
					Utils.rand(0.6, 1.2), 0.2, 0.18, 0.16, -0.2, Utils.rand(0.9, 1.5))
	if _burn_light != null:
		if _burn_t > 0:
			var k := clampf(_burn_t / 8.0, 0.2, 1.0)
			_burn_light.light_energy = 1.1 * k * (0.6 + 0.4 * sin(G.time * 26.0 + _crash_burn_pos.x * 3.1))
		else:
			_burn_light.light_energy = maxf(0.0, _burn_light.light_energy - dt * 3.0)
			if _burn_light.light_energy <= 0.0:
				_burn_light.queue_free()
				_burn_light = null


func _shoot_at(p_target, dt: float, w: Dictionary, rate_mul := 1.0) -> void:
	fire_t -= dt
	if fire_t > 0:
		return
	fire_t = (0.16 + randf() * 0.08) * rate_mul
	var tpos: Vector3 = p_target.get("pos")
	var aim := Vector3(tpos.x, tpos.y + 1.1, tpos.z)
	var dir := Utils.safe_norm(aim - pos, Vector3.FORWARD)
	var a := Utils.rand(TAU)
	var r := sqrt(randf()) * 0.045
	if pos.distance_to(tpos) > 60.0:
		r *= 2.0  # 射程衰减:>60m 散布翻倍
	dir.x += cos(a) * r
	dir.y += sin(a) * r
	dir = dir.normalized()
	var wdef := WeaponsData.WeaponDef.new()
	wdef.cn = w["cn"]
	wdef.name = w["name"]
	wdef.kind = w["kind"]
	wdef.damage = w["damage"]
	wdef.head_mult = w["head_mult"]
	wdef.rpm = w["rpm"]
	wdef.rng = w["rng"]
	wdef.tracer = w["tracer"]
	G.game.fire_hitscan(pilot, wdef, pos, dir, pos)
	AudioSys.veh_weapon(type, pos)


func _fire_rockets(target_pos: Vector3, n := 2) -> void:
	for i in n:
		var dir := Vector3(
			target_pos.x + Utils.rand(-6, 6) - pos.x,
			target_pos.y - pos.y,
			target_pos.z + Utils.rand(-6, 6) - pos.z).normalized()
		var rdef := { "damage": 85.0, "splash": 6.5, "speed": 60.0, "cn": "航空火箭弹", "name": "航空火箭弹", "tracer": Color.html("#ffe0a0") }
		G.effects.spawn_rocket(pilot, rdef, pos + Vector3(0, -1, 0), dir)
	AudioSys.veh_weapon(type, pos)


## 进入盘旋攻击:绕目标环形盘旋(半径 60-90m,角速度 0.25-0.5 rad/s)
func _heli_enter_attack() -> void:
	if not injured and strafe_cd <= 0:
		_heli_enter_strafe()
		return
	mode = "orbit"
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	orbit_r = Utils.rand(60, 90) if not injured else Utils.rand(70, 90)
	orbit_ws = Utils.rand(0.25, 0.5)
	orbit_alt = Utils.rand(30, 45)
	mode_t = Utils.rand(3, 6)
	var tp: Vector3 = target.get("pos")
	orbit_ang = atan2(pos.z - tp.z, pos.x - tp.x)


## 俯冲扫射跑:dive(俯冲至 25m)→ run(低空扫射 1.5-2.5s)→ climb(拉起爬升脱离)
func _heli_enter_strafe() -> void:
	mode = "strafe"
	strafe_phase = "dive"
	strafe_t = 0.0
	strafe_cd = Utils.rand(4, 8)
	mode_t = Utils.rand(3, 5)   # 俯冲会话时长,防 mode_t≤0 导致俯冲被瞬间截断


func update_aircraft(dt: float) -> void:
	# 飞行员坐标同步(字典为值类型,需手动同步)
	pilot["pos"] = pos
	if dead:
		# 坠毁:引擎停转(A/B 双 player 全停)
		if _eng_a != null:
			_eng_a.stop()
			_eng_b.stop()
		# 坠毁
		if crashing:
			vel.y -= 18 * dt
			pos += vel * dt
			mesh.position = pos
			mesh.rotation.x += dt * 3
			mesh.rotation.z += dt * 5
			var rotor_d: Node3D = mesh.get_meta("rotor") if mesh.has_meta("rotor") else null
			if rotor_d != null:
				rotor_d.rotation.y += dt * 3
			if randf() < 0.4:
				G.effects.smoke_spawn(pos.x, pos.y, pos.z, Utils.rand(-1, 1), Utils.rand(1, 3), Utils.rand(-1, 1),
					Utils.rand(0.5, 1.2), 0.2, 0.18, 0.16, 0.1)
			var gy: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
			if pos.y <= gy + 1:
				crashing = false
				mesh.visible = false
				G.game.explode(Vector3(pos.x, gy + 0.5, pos.z), 9, 130, pilot)
				_start_crash_burn(Vector3(pos.x, gy + 0.5, pos.z))
		else:
			respawn_t -= dt
			if _burn_t > 0 or _burn_light != null:
				_burn_t = maxf(0.0, _burn_t - dt)
				_update_crash_burn(dt)
			if respawn_t <= 0:
				_spawn()
		return

	if type == "jet":
		_update_jet(dt)
		return

	# ==================== 直升机:战术机动状态机(巡航→盘旋→俯冲→脱离→受伤→返航) ====================
	var rotor: Node3D = mesh.get_meta("rotor")
	var tail_rotor: Node3D = mesh.get_meta("tail_rotor")
	if rotor != null:
		rotor.rotation.y += dt * 18
	if tail_rotor != null:
		tail_rotor.rotation.x += dt * 25
	think_t -= dt
	wp_t -= dt
	rocket_t -= dt
	mode_t -= dt
	strafe_cd -= dt
	if think_t <= 0:
		think_t = 0.3
		target = _acquire()
		if target == null or (mode == "cruise" and wp_t <= 0):
			_pick_waypoint()
	var cap: float = clampf(hp / max_hp, 0.0, 1.0)
	# 受伤模式:hp<55% 保守作战(攻击间隔×2、保持 70m+ 距离);每 15s 评估重伤(<35%)→ 返航
	if cap < 0.55 and not injured:
		injured = true
		injured_t = 0.0
	elif cap >= 0.75:
		injured = false
	if injured:
		injured_t += dt
		if injured_t >= 15.0 and cap < 0.35 and mode != "rtb" and not landing:
			mode = "rtb"
			mode_t = 0.0
			rtb_t = 0.0
			target = null
	# 攻击窗口制:仅当与目标 50-140m 且机头朝向目标(夹角<50°)时开火(避免背对射击)
	var can_engage := false
	var tpos_e: Vector3 = Vector3.ZERO
	if target != null and target.get("alive") != false:
		tpos_e = target.get("pos")
		var to_t := Vector3(tpos_e.x - pos.x, 0, tpos_e.z - pos.z)
		if to_t.length() >= 50.0 and to_t.length() <= 140.0:
			var facing := Vector3(-sin(yaw), 0, -cos(yaw))
			if facing.normalized().dot(to_t.normalized()) > cos(deg_to_rad(50.0)):
				can_engage = true
	# 战术状态切换
	if landing or landed:
		mode = "land"
	elif mode == "rtb":
		pass
	elif mode == "strafe":
		# 已承诺的俯冲扫射跑:跑完再评估(不中途打断;目标已死则立即脱离)
		if mode_t <= 0 or target == null or target.get("alive") == false:
			mode = "disengage"
	elif can_engage:
		if mode == "cruise" or mode == "disengage":
			_heli_enter_attack()
		elif mode == "orbit":
			if mode_t <= 0:
				mode = "disengage"  # 攻击 3-6s 后脱离重巡
			elif not injured and strafe_cd <= 0:
				_heli_enter_strafe()  # 每 4-8s 穿插俯冲扫射
	elif mode == "orbit":
		mode = "disengage"
	elif mode == "disengage":
		if target == null or target.get("alive") == false or pos.distance_to(tpos_e) > 120.0:
			mode = "cruise"
			_pick_waypoint(true)  # 撤到 120m+ 外重新走位
	# 机动目标/高度/速度按战术模式
	var gy2: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	var goal_x := wp.x
	var goal_z := wp.z
	var want_y := gy2 + cruise_alt
	var eff_speed := 14.0 * (0.5 + 0.5 * cap)
	var want_yaw := yaw
	match mode:
		"cruise":
			# 巡航:高度 40-70m 随机,直线加速/转弯减速
			goal_x = wp.x
			goal_z = wp.z
			want_y = gy2 + cruise_alt
			eff_speed = 14.0 * (0.5 + 0.5 * cap)
			if airspeed > 2.0:
				want_yaw = atan2(-vel.x, -vel.z)
			else:
				want_yaw = atan2(-(wp.x - pos.x), -(wp.z - pos.z))
		"orbit":
			# 环形盘旋:绕目标 60-90m 半径,角速度 0.25-0.5 rad/s,高度正弦摆动
			orbit_ang += orbit_dir * orbit_ws * dt
			goal_x = tpos_e.x + cos(orbit_ang) * orbit_r
			goal_z = tpos_e.z + sin(orbit_ang) * orbit_r
			goal_x += cos(G.time * 0.6 + drift_phase) * 3.0  # 悬停轻微漂移
			goal_z += sin(G.time * 0.5 + drift_phase) * 3.0
			want_y = gy2 + orbit_alt + sin(G.time * 0.7 + drift_phase) * 4.0
			eff_speed = clampf(orbit_r * orbit_ws, 16.0, 26.0) * (0.5 + 0.5 * cap)
			want_yaw = atan2(-(tpos_e.x - pos.x), -(tpos_e.z - pos.z))
		"strafe":
			if strafe_phase == "dive":
				# 俯冲:朝向目标压至 25m 攻击高度
				var dir_s := Utils.safe_norm(Vector3(tpos_e.x - pos.x, 0, tpos_e.z - pos.z), Vector3.FORWARD)
				goal_x = tpos_e.x - dir_s.x * 20.0
				goal_z = tpos_e.z - dir_s.z * 20.0
				want_y = gy2 + 25.0
				eff_speed = 22.0 * (0.5 + 0.5 * cap)
				want_yaw = atan2(-dir_s.x, -dir_s.z)
				if Vector2(tpos_e.x - pos.x, tpos_e.z - pos.z).length() < 60.0:
					strafe_phase = "run"
					strafe_t = Utils.rand(1.5, 2.5)
			elif strafe_phase == "run":
				# 低空直飞扫射 1.5-2.5s
				strafe_t -= dt
				var dir_r := Utils.safe_norm(Vector3(vel.x, 0, vel.z), Vector3.FORWARD)
				goal_x = pos.x + dir_r.x * 80.0
				goal_z = pos.z + dir_r.z * 80.0
				want_y = gy2 + 26.0
				eff_speed = 22.0 * (0.5 + 0.5 * cap)
				want_yaw = atan2(-(tpos_e.x - pos.x), -(tpos_e.z - pos.z))
				if strafe_t <= 0:
					strafe_phase = "climb"
			else:
				# 拉起爬升脱离(60-80m)
				strafe_t -= dt
				var away := Utils.safe_norm(Vector3(pos.x - tpos_e.x, 0, pos.z - tpos_e.z), Vector3.FORWARD)
				goal_x = pos.x + away.x * 120.0
				goal_z = pos.z + away.z * 120.0
				want_y = gy2 + clampf(cruise_alt, 60.0, 80.0)
				eff_speed = 16.0 * (0.5 + 0.5 * cap)
				want_yaw = atan2(-away.x, -away.z)
				if strafe_t <= 0:
					mode = "disengage"
		"disengage":
			# 撤离:背对目标爬升至 60-80m,撤到 120m+ 外重新走位
			if target != null and target.get("alive") != false:
				var away2 := Utils.safe_norm(Vector3(pos.x - tpos_e.x, 0, pos.z - tpos_e.z), Vector3.FORWARD)
				goal_x = pos.x + away2.x * 160.0
				goal_z = pos.z + away2.z * 160.0
				want_yaw = atan2(-away2.x, -away2.z)
			else:
				goal_x = wp.x
				goal_z = wp.z
				want_yaw = atan2(-vel.x, -vel.z)
			want_y = gy2 + clampf(cruise_alt, 60.0, 80.0)
			eff_speed = 16.0 * (0.5 + 0.5 * cap)
		"rtb":
			# 返航:飞回己方基地,上空盘旋 8s 缓慢回血 20/s 后回归
			var land_b2: float = G.bounds if G.bounds > 0 else 150.0
			var base_x2 := 0.0
			var base_z2 := -land_b2 + 30.0 if team == "us" else land_b2 - 30.0
			if Vector2(base_x2 - pos.x, base_z2 - pos.z).length() > 60.0:
				goal_x = base_x2
				goal_z = base_z2
				want_y = gy2 + 70.0
				eff_speed = 14.0
				want_yaw = atan2(-(base_x2 - pos.x), -(base_z2 - pos.z))
			else:
				rtb_t += dt
				hp = minf(max_hp, hp + 20.0 * dt)
				var ba := G.time * 0.5
				goal_x = base_x2 + cos(ba) * 30.0
				goal_z = base_z2 + sin(ba) * 30.0
				want_y = gy2 + 60.0
				eff_speed = 10.0
				want_yaw = atan2(-cos(ba), -sin(ba))
				if rtb_t >= 8.0 or cap >= 0.7:
					mode = "cruise"
					rtb_t = 0.0
					injured_t = 0.0
					_pick_waypoint(true)
		_:
			# land:由下方降落逻辑接管
			goal_x = wp.x
			goal_z = wp.z
			want_y = gy2 + 38.0
			eff_speed = 0.0
	# 重伤着陆:回己方基地低空盘旋,最终落地缓慢回血待修(接续原有返航逻辑)
	if cap < 0.25 and not landing:
		landing = true
		mode = "land"
	if landing:
		if cap > 0.55:
			landing = false
			landed = false
			vel.y = 4.0  # 修好起飞
			mode = "cruise"
			_pick_waypoint(true)
		else:
			hp = minf(max_hp, hp + 20.0 * dt)  # 落地维修:缓慢回血
			var land_b: float = G.bounds if G.bounds > 0 else 150.0
			var base_x := 0.0
			var base_z := -land_b + 30.0 if team == "us" else land_b - 30.0
			goal_x = base_x + sin(G.time * 0.3) * 20
			goal_z = base_z + cos(G.time * 0.25) * 20
			eff_speed = 7.0
			target = null
			if pos.distance_to(Vector3(base_x, pos.y, base_z)) < 30:
				# 进场着陆:缓降减速
				want_y = gy2 + 0.6
				eff_speed = 2.5
				if pos.y < gy2 + 3.0 and airspeed < 3.5:
					landed = true
			if landed:
				want_y = gy2 + 0.6
				eff_speed = 0.0
	# 移动:惯性缓追期望(大而缓的操纵感),直线加速/转弯段减速
	var to_x := goal_x - pos.x
	var to_z := goal_z - pos.z
	var d_goal := Vector2(to_x, to_z).length()
	var yaw_err := wrapf(want_yaw - yaw, -PI, PI)
	if absf(yaw_err) > 0.9 and d_goal > 4:
		eff_speed *= 0.6  # 转弯段减速
	if injured:
		eff_speed *= 0.85
	if d_goal > 4:
		vel.x = Utils.damp(vel.x, to_x / d_goal * eff_speed, 0.9, dt)
		vel.z = Utils.damp(vel.z, to_z / d_goal * eff_speed, 0.9, dt)
	else:
		# 到点不停留:巡航模式抵达巡航点立即换点继续飞行,
		# 避免悬停"卡在空中"不动(失速下坠又被高度弹簧拉回,看似冻结)
		if mode == "cruise":
			wp_t = 0.0
			_pick_waypoint()
		vel.x = Utils.damp(vel.x, 0, 1.8, dt)
		vel.z = Utils.damp(vel.z, 0, 1.8, dt)
	airspeed = Vector2(vel.x, vel.z).length()
	# 机头转向:yaw 阻尼缓转(非瞬转),转弯自然倾斜
	var turn_rate := 1.8 if not injured else 1.4
	yaw += clampf(yaw_err, -turn_rate * dt, turn_rate * dt)
	# 引擎音随档位/空速联动(远近衰减由 AudioStreamPlayer3D 自动处理;26=盘旋最大空速)
	if _eng_a != null:
		var rot_k: float = clampf(airspeed / 14.0, 0.0, 1.0)
		_eng_update_sound(clampf(airspeed / 26.0, 0.0, 1.0), lerpf(0.12, 0.64, rot_k), dt)
	# 失速:空速过低 → 机头下垂抖动下坠,直到速度恢复
	if airspeed < 5.5 and not landed:
		stall_t += dt
		vel.y -= 3.5 * dt
	else:
		stall_t = 0
	# 高度:地形高度弹簧(着陆时贴地)
	if not landed:
		vel.y = Utils.damp(vel.y, clampf((want_y - pos.y) * 0.9, -8, 8), 3, dt)
	else:
		vel.y = Utils.damp(vel.y, clampf((want_y - pos.y) * 0.9, -3, 3), 4, dt)
	pos += vel * dt
	# 落地防穿地:贴地弹簧(hover 于 gy+0.6)本身不弹跳,加硬下限兜底
	if landed and G.ground_h.is_valid():
		var gyl: float = G.ground_h.call(pos.x, pos.z)
		if pos.y < gyl + 0.2:
			pos.y = gyl + 0.2
			vel.y = maxf(vel.y, 0.0)
	var B: float = G.bounds if G.bounds > 0 else 150.0
	pos.x = clampf(pos.x, -B, B)
	pos.z = clampf(pos.z, -B, B)
	# 开火:攻击窗口制(50-140m 且朝向目标),受伤时攻击间隔×2;火箭弹保持
	if can_engage:
		_shoot_at(target, dt, { "name": "机载机炮", "cn": "机载机炮", "kind": "lmg", "damage": 8.0,
			"head_mult": 1.2, "rpm": 600.0, "rng": [80.0, 160.0, 0.5], "tracer": Color.html("#ffe8a0") },
			2.0 if injured else 1.0)
		if rocket_t <= 0:
			rocket_t = 5.5
			_fire_rockets(tpos_e, 2)
	# 同步模型(转弯滚转 + 失速抖动;俯仰随升降/空速)
	var yaw_rate := wrapf(yaw - prev_yaw, -PI, PI) / maxf(dt, 0.001)
	prev_yaw = yaw
	var bank := clampf(yaw_rate * 0.28, -0.55, 0.55) * clampf(airspeed / 10.0, 0.3, 1.0)
	if stall_t > 0:
		bank += sin(stall_t * 7.0) * 0.12
	var pitch_nose := clampf(vel.y * 0.015, -0.25, 0.2) + clampf(airspeed * 0.006, 0, 0.12)
	mesh.position = pos
	mesh.rotation_order = EULER_ORDER_YXZ
	mesh.rotation.y = yaw
	mesh.rotation.z = Utils.damp(mesh.rotation.z, bank, 3.5, dt)
	mesh.rotation.x = Utils.damp(mesh.rotation.x, pitch_nose, 3, dt)


## ==================== 战斗机:高空俯冲扫射 ====================
func _update_jet(dt: float) -> void:
	# 引擎档位随速切换:待命(strafe==null)时音量淡至 0,俯冲加速切入高速档
	if _eng_a != null:
		var spd_k: float = clampf(vel.length() / 80.0, 0.0, 1.0)
		# 响度补偿:fighter_engine 素材峰值 0.23-0.29(-11~-13dB)偏低,jet 引擎音量 ×1.6
		# (0.44→0.704,heli 素材 0.72-0.94 正常不动)
		var target_v: float = 0.44 * 1.6 * spd_k if strafe != null else 0.0
		_eng_update_sound(spd_k, target_v, dt)
	var burner: MeshInstance3D = mesh.get_meta("burner")
	if burner != null:
		var bm := burner.material_override as StandardMaterial3D
		bm.albedo_color.a = 0.6 + randf() * 0.35
	if strafe == null:
		respawn_t -= dt
		if respawn_t > 0:
			return
		# 规划一次俯冲扫射:随机敌方密集旗帜
		var pool := []
		for f in G.flags:
			if f.owner_team != team:
				pool.append(f)
		var f: Flag = Utils.choice(pool) if not pool.is_empty() else Utils.choice(G.flags)
		var tx := f.pos.x if f != null else 0.0
		var tz := f.pos.z if f != null else 0.0
		var B: float = (G.bounds if G.bounds > 0 else 150.0) + 220
		var ang := Utils.rand(TAU)
		pos = Vector3(tx + cos(ang) * B, 85, tz + sin(ang) * B)
		var dir := Vector3(tx - pos.x, 0, tz - pos.z).normalized()
		yaw = atan2(-dir.x, -dir.z)
		strafe = { "tx": tx, "tz": tz, "rocket_fired": false }
		mesh.visible = true
		vel = Vector3(dir.x * 78, -6, dir.z * 78)
		return
	# 沿航线飞行(受损减速:按耐久一次性压低巡航速度,而非逐帧倍减——
	# 逐帧乘 (0.45+0.55*cap) 会让速度指数衰减到 1m/s,战机"卡死"在空中/原地垂直爬升)
	var cap2: float = clampf(hp / max_hp, 0.0, 1.0)
	var cruise := 78.0 * (0.45 + 0.55 * cap2)
	vel = Utils.safe_norm(vel, Vector3.FORWARD) * maxf(cruise, 1.0)
	pos += vel * dt
	if _eng_a != null:
		_eng_a.position = pos  # 位置在移动结算后同步(1 帧 78m/s,前置会偏 1.3m)
		_eng_b.position = pos
	mesh.position = pos
	mesh.rotation_order = EULER_ORDER_YXZ
	mesh.rotation.y = yaw
	mesh.rotation.x = 0.08
	mesh.rotation.z = sin(G.time * 2) * 0.05
	var d_t := Vector2(pos.x - strafe["tx"], pos.z - strafe["tz"]).length()
	# 进入窗口:机炮持续扫射地面目标
	if d_t < 260 and d_t > 60:
		var t = _acquire()
		if t != null:
			_shoot_at(t, dt, { "name": "机载航炮", "cn": "机载航炮", "kind": "lmg", "damage": 24.0,
				"head_mult": 1.2, "rpm": 900.0, "rng": [120.0, 260.0, 0.6], "tracer": Color.html("#a0e8ff") })
	# 最近点投弹
	if d_t < 110 and not strafe["rocket_fired"]:
		strafe["rocket_fired"] = true
		var gy: float = G.ground_h.call(strafe["tx"], strafe["tz"]) if G.ground_h.is_valid() else 0.0
		_fire_rockets(Vector3(strafe["tx"], gy, strafe["tz"]), 3)
	# 飞离后爬升消失
	if d_t < 60:
		vel.y = 14
	var B2: float = (G.bounds if G.bounds > 0 else 150.0) + 260
	if absf(pos.x) > B2 or absf(pos.z) > B2:
		strafe = null
		mesh.visible = false
		respawn_t = Utils.rand(20, 30)


func dispose() -> void:
	if _eng_a != null:
		_eng_a.stop()
		_eng_b.stop()
	_stop_crash_burn()
	queue_free()
