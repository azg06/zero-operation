class_name Gun extends RefCounted
## 枪械手感(对应 weapons.js 的 Gun 类):射击/换弹/后座/视角模型动画

const HIP_POS := Vector3(0.17, -0.155, -0.34)
const ADS_POS := Vector3(0, -0.0755, -0.26)
# 手臂肘部屏外锚点(枪身局部空间):臂筒自手腕延伸至屏幕外,消除断臂
const ELBOW_R := Vector3(0.1, -0.46, 0.4)
const ELBOW_L := Vector3(-0.11, -0.44, 0.36)

var def                         # WeaponDef
var id := ""
var player = null               # Player
var group: Node3D = null        # 武器模型(vm_camera 子节点)
var muzzle: Node3D = null
var ammo := 0
var reserve := 0
var reloading := false
var reload_t := 0.0
var reload_stage := 0
var fire_timer := 0.0
var ads_amount := 0.0
var ads_held := false
var bloom := 0.0                # 连射扩散
var kick_z := 0.0
var kick_rot := 0.0             # 视角模型后坐
var bob_t := 0.0
var sway_x := 0.0
var sway_y := 0.0
var draw_t := 1.0               # 拔枪动画
var trigger_held := false
var equipped := false
var bolt_t := 0.0               # 拉栓动画(AWM/M24)
var pump_t := 0.0               # 泵动动画(M1014)
var _pump_last := false         # 霰弹链式装填最后一发才泵动
var wall_amt := 0.0
var grip_amt := 0.0
var _semi_ready := true
var _bolt_snd := false
var _tac := false                 # 战术换弹(膛内有余弹 → 换弹更快但余弹丢弃)
var _reload_dur := 0.0            # 本次换弹实际时长
var shot_streak := 0              # 连射计数(后坐力/散布递增)
var last_shot_t := -99.0
var _kick_side := -1.0            # 水平后坐模式方向(左右交替)
var kick_y := 0.0                 # 视角模型水平后坐

var _mag: Node3D = null             # 弹匣(直插 MeshInstance3D 或弯弹匣 Node3D 根)
var _mag_y0 := 0.0
var _mag_x0 := 0.0
var _mag_anim := "down"
var _bolt: Node3D = null            # 拉机柄/枪机(换弹上膛驱动)
var _bolt_base := Vector3.ZERO
var _pump: MeshInstance3D = null
var _pump_base := Vector3.ZERO
var _slide: MeshInstance3D = null
var _slide_base_x := 0.0
var _rocket: Node3D = null              # 火箭筒膛内弹(换弹时隐藏→装入)
var _scope_model := false
var _bullet_type := 0                    # 0=rifle 1=sniper 2=shotgun 3=pistol

var _right_hand: Node3D = null
var _left_hand: Node3D = null
var _right_arm: Node3D = null
var _left_arm: Node3D = null
var _hand_l0 := Vector3.ZERO
var _hand_l1 := Vector3.ZERO
var _hand_l2 := Vector3(0.03, -0.34, 0.02)
var _hip_pos := Vector3.ZERO
var _ads_pos := Vector3.ZERO


func _init(weapon_id: String, p) -> void:
	def = WeaponsData.W()[weapon_id]
	id = weapon_id
	player = p
	group = WeaponModels.build(weapon_id, true)
	muzzle = group.get_meta("muzzle")
	ammo = def.mag
	reserve = def.reserve

	if group.has_meta("mag"):
		_mag = group.get_meta("mag")
		_mag_y0 = _mag.position.y
		_mag_x0 = _mag.position.x
	# 弹匣动画类型:AK/SVD 前挂后卡(侧摆),机枪弹鼓/弹链箱(旋转),其余直插(下沉)
	_mag_anim = "down"
	if weapon_id in ["ak", "svd"]:
		_mag_anim = "side"
	elif weapon_id in ["rpd", "m249", "pkm"]:
		_mag_anim = "drum"
	if group.has_meta("pump"):
		_pump = group.get_meta("pump")
		_pump_base = _pump.position
	if group.has_meta("slide"):
		_slide = group.get_meta("slide")
	_slide_base_x = 0.0
	if _slide != null:
		_slide_base_x = _slide.position.x
	if group.has_meta("rocket"):
		_rocket = group.get_meta("rocket")
	if group.has_meta("bolt"):
		_bolt = group.get_meta("bolt")
		_bolt_base = _bolt.position
	_scope_model = def.scope
	_bullet_type = 0
	if weapon_id in ["awm", "m24", "svd"]:
		_bullet_type = 1
	elif weapon_id in ["m1014", "spas12"]:
		_bullet_type = 2
	elif weapon_id in ["g17", "m1911", "p226", "deagle", "m93r"]:
		_bullet_type = 3
	_right_hand = group.get_meta("right_hand", null)
	_left_hand = group.get_meta("left_hand", null)
	_right_arm = group.get_meta("right_arm", null)
	_left_arm = group.get_meta("left_arm", null)
	# 左手换弹路径锚点
	_hand_l0 = _left_hand.position if _left_hand != null else Vector3.ZERO
	if _mag != null:
		_hand_l1 = _mag.position + Vector3(0, 0.04, 0)
	elif def.projectile:
		_hand_l1 = Vector3(0, -0.05, 0.14)
	else:
		_hand_l1 = Vector3(0, -0.1, -0.12)
	_hip_pos = def.view_hip if def.view_hip != null else HIP_POS
	_ads_pos = def.view_ads if def.view_ads != null else Vector3(0, -def.sight_y, def.ads_z)


func equip() -> void:
	equipped = true
	group.visible = true
	draw_t = 0
	reloading = false
	# 切枪/重生清零视角模型后坐弹簧,避免残留跳动
	kick_z = 0
	kick_rot = 0
	kick_y = 0


func holster() -> void:
	equipped = false
	group.visible = false


func can_ads() -> bool:
	return not reloading and draw_t > 0.7


func current_spread() -> float:
	var d = def
	var p = player
	var s := lerpf(d.spread_hip, d.spread_ads, ads_amount)
	var speed := Vector2(p.vel.x, p.vel.z).length()
	# 移动惩罚:腰射移动影响大,开镜大幅减免
	s += d.spread_move * clampf(speed / 6.0, 0, 1) * (1 - ads_amount * 0.85)
	# 疾跑/滑铲/跳跃精度惩罚(BF 手感)
	s += p.sprint_amount * 1.6 * (1 - ads_amount * 0.9)
	if p.slide_t > 0:
		s += 1.4
	if p.crouched:
		s *= 0.75
	if p.prone:
		s *= 0.5
	if not p.on_ground:
		s += 2.2
	s += p.suppression * 0.9  # 压制降低精度
	s += bloom * (1 - ads_amount * 0.45)
	return s * (PI / 180.0)


func try_fire() -> void:
	if draw_t < 0.6 or fire_timer > 0:
		return
	if player.sprint_amount > 0.5:
		return
	if reloading:
		# 非霰弹:换弹期间禁止开火
		if def.pellets <= 1:
			return
		# 霰弹枪:上弹中开火打断换弹(保留已装弹数),本帧直接射击
		reloading = false
		reload_t = 0
		reload_stage = 0
	if ammo <= 0:
		AudioSys.dry_fire()
		fire_timer = 0.28
		reload()
		return
	ammo -= 1
	fire_timer = 60.0 / def.rpm
	var p = player

	if def.projectile:
		# RPG:发射火箭弹;已锁定空中目标 → 防空导弹(制导)
		var dir: Vector3 = -G.camera.global_transform.basis.z
		var origin: Vector3 = G.camera.global_position + dir * 0.5
		var locked = G.lock_target
		var use_def = def
		if locked != null:
			use_def = { "cn": "防空导弹", "name": "防空导弹", "damage": 320.0, "splash": 10.0, "speed": 50.0, "tracer": def.tracer }
		G.effects.spawn_rocket(p, use_def, origin, dir, locked)
		if locked != null:
			G.hud.hint("防空导弹已发射,追踪目标中")
			G.lock_target = null
		AudioSys.rpg_fire(p.pos)
	else:
		var pellets = def.pellets
		var spread := current_spread()
		var mv := muzzle_world_main()
		var cam_basis := G.camera.global_transform.basis
		for i in pellets:
			var dir: Vector3 = -cam_basis.z
			# 圆锥散布
			var a := Utils.rand(TAU)
			var r := sqrt(randf()) * spread
			var right: Vector3 = cam_basis.x
			var up: Vector3 = cam_basis.y
			dir = (dir + right * (cos(a) * r) + up * (sin(a) * r)).normalized()
			# 弹道:下坠补偿 + 穿透 + 部位倍率(内部结算到 fire_hitscan)
			Utils.ballistic_fire(p, def, G.camera.global_position, dir, mv)
		AudioSys.shoot(def.kind, p.pos, true)

	# === 3A 后坐力曲线:首发高、连射递增、水平左右模式、开镜降低 ===
	var ads_scale := lerpf(1.0, 0.62, ads_amount)
	var k: float = def.recoil_first if shot_streak <= 0 else minf(1.0 + def.recoil_ramp * float(shot_streak), 1.5)
	p.recoil_pitch += def.recoil_pitch * k * ads_scale * (PI / 180.0)
	# 水平后坐:72% 概率换向(左右交替但有模式感)
	if randf() < 0.72:
		_kick_side = -_kick_side
	p.recoil_yaw += _kick_side * Utils.rand(0.55, 1.0) * def.recoil_yaw * k * ads_scale * (PI / 180.0)
	# 摄像机微后坐(开火瞬间视角震动,随后坐力弹簧回正)
	p.cam_kick_pitch += def.recoil_cam * k * (0.5 + ads_scale * 0.5)
	p.cam_kick_yaw += _kick_side * Utils.rand(0.2, 0.7) * def.recoil_cam * 0.4 * k
	# 视角模型后坐:后缩 + 上仰 + 水平侧移(开镜收敛 80%,枪口不挡瞄准视野)
	var vm_k := lerpf(1.0, 0.2, ads_amount)   # 腰射 1.0 不变;满开镜 0.2
	kick_z += def.recoil_vm * k * vm_k
	kick_rot += def.recoil_vm * 1.6 * k * vm_k
	kick_y += Utils.rand(0.01, 0.024) * k * vm_k
	# 连射散布递增(开镜减半)
	bloom = minf(bloom + def.spread_bloom * (1.0 + 0.12 * float(shot_streak)), def.spread_bloom_max)
	shot_streak = mini(shot_streak + 1, 9)
	last_shot_t = G.time
	# === 枪口特效:每把武器独立闪光亮度/持续时间/衰减曲线/烟量/抛壳力度 ===
	var fb := 0.85      # 闪光亮度
	var fd := 0.045     # 闪光持续
	var fdecay := 1.5   # 衰减曲线指数:越大越锐(狙击刺眼短促),越小越柔(机枪长拖)
	var fsmoke := 1.0   # 枪口烟密度
	var eject_pw := 1.0 # 抛壳力度
	match def.kind:
		"sniper":
			fb = 1.2; fd = 0.065; fdecay = 2.2; fsmoke = 1.15; eject_pw = 1.35
		"rpg":
			fb = 1.35; fd = 0.07; fdecay = 2.0; fsmoke = 1.5; eject_pw = 1.0
		"shotgun":
			fb = 1.05; fd = 0.06; fdecay = 1.8; fsmoke = 1.3; eject_pw = 1.2
		"lmg":
			fb = 1.0; fd = 0.055; fdecay = 1.25; fsmoke = 1.4; eject_pw = 1.15
		"pistol":
			fb = 0.7; fd = 0.04; fdecay = 1.6; fsmoke = 0.7; eject_pw = 0.9
		"dmr":
			fb = 0.95; fd = 0.05; fdecay = 1.7; fsmoke = 1.0; eject_pw = 1.1
		"smg":
			fb = 0.8; fd = 0.042; fdecay = 1.4; fsmoke = 0.8; eject_pw = 1.0
		"rifle":
			fb = 0.85; fd = 0.045; fdecay = 1.5; fsmoke = 1.0; eject_pw = 1.0
	G.effects.muzzle(muzzle_world_main(), -G.camera.global_transform.basis.z,
		def.kind == "sniper" or def.kind == "rpg",
		fb * Utils.rand(0.92, 1.08), fd * Utils.rand(0.9, 1.1), fdecay, fsmoke)
	G.effects.casing(muzzle_world_main(), G.camera.global_transform.basis, _bullet_type, eject_pw)
	G.effects.shake(0.5 if def.kind == "sniper" else (0.7 if def.projectile else 0.12))
	if id == "awm" or id == "m24":
		bolt_t = 0.0001
		_bolt_snd = false
	if _pump != null:
		pump_t = 0.0001
	if ammo == 0:
		reload()


## 弹匣掉落
func _drop_mag() -> void:
	if _mag == null:
		return
	G.effects.spawn_mag(_mag.global_position)


## 左手换弹路径
func _hand_path(t: float) -> Vector3:
	var A := _hand_l0
	var B := _hand_l1
	var C := _hand_l2
	var ez := func(x: float) -> float: return x * x * (3 - 2 * x)
	if def.pellets > 1:
		# 霰弹枪:手移到装填口反复塞弹
		if t < 0.12:
			return A.lerp(B, ez.call(t / 0.12))
		elif t < 0.8:
			return B + Vector3(0, sin((t - 0.12) * PI * 7) * 0.025 - 0.025, 0)
		else:
			return B.lerp(A, ez.call((t - 0.8) / 0.2))
	if def.projectile:
		# RPG:手移到筒尾装填火箭弹
		if t < 0.2:
			return A.lerp(B, ez.call(t / 0.2))
		elif t < 0.7:
			return B
		else:
			return B.lerp(A, ez.call((t - 0.7) / 0.3))
	# 弹匣抓握点:跟随弹匣实时位置
	var grip := Vector3(0, -0.035, 0.012)
	if _mag != null:
		grip += _mag.position
	else:
		grip += B
	if t < 0.15:
		return A.lerp(grip, ez.call(t / 0.15))
	elif t < 0.32:
		return grip
	elif t < 0.5:
		return grip.lerp(C, ez.call((t - 0.32) / 0.18))
	elif t < 0.6:
		return C
	elif t < 0.78:
		return C.lerp(grip, ez.call((t - 0.6) / 0.18))
	elif t < 0.86:
		return grip
	else:
		return grip.lerp(A, ez.call((t - 0.86) / 0.14))


func reload() -> void:
	if reloading or ammo >= def.mag or reserve <= 0:
		return
	reloading = true
	reload_t = 0
	reload_stage = 0
	# 战术换弹(膛内有余弹,更快)/ 空仓换弹(满时长,包含上膛动作)
	_tac = ammo > 0
	_reload_dur = _reload_duration()


## 换弹时长:战术(余弹)> 空仓;霰弹枪按单发周期装填(每发 1 弹)
func _reload_duration() -> float:
	if def.pellets > 1:
		return maxf(0.45, def.reload_time / float(def.mag))
	if _tac:
		return def.reload_tac if def.reload_tac > 0 else def.reload_time * 0.78
	return def.reload_time


func update(dt: float) -> void:
	if not equipped:
		return
	var p = player
	fire_timer -= dt
	draw_t = minf(1, draw_t + dt / 0.28)
	bloom = maxf(0, bloom - dt * 3.5)
	# 后坐力连射计数:停火超时复位
	if G.time - last_shot_t > def.recoil_recover:
		shot_streak = 0

	# 扳机
	if trigger_held and (def.auto or _semi_ready):
		try_fire()
	if not trigger_held:
		_semi_ready = true
	elif not def.auto:
		_semi_ready = false

	# 换弹
	if reloading:
		reload_t += dt
		var rt = _reload_dur
		if reload_stage == 0 and reload_t > rt * 0.25:
			reload_stage = 1
			AudioSys.reload(0)
		if reload_stage == 1 and reload_t > rt * 0.7:
			reload_stage = 2
			AudioSys.reload(1)
		if reload_t >= rt:
			if def.pellets > 1:
				# 霰弹枪:逐发上弹(每发 1 弹),未满则链式开始下一发
				ammo += 1
				reserve -= 1
				if ammo < def.mag and reserve > 0:
					reload_t = 0
					reload_stage = 0
					_reload_dur = _reload_duration()
					_pump_last = false
				else:
					reloading = false
					_pump_last = true   # 最后一发(或装满)才泵动上膛
			else:
				# 战地真实规则:整匣更换,弹匣余弹丢弃
				var take2: int = mini(def.mag, reserve)
				ammo = take2
				reserve -= take2
				reloading = false

	# ADS 插值(指数缓动:起手快、落点稳,放大倍率过渡顺滑)
	var ads_target := 1.0 if (ads_held and can_ads()) else 0.0
	if ads_target != ads_amount:
		ads_amount = Utils.damp(ads_amount, ads_target, 2.6 / maxf(def.ads_time, 0.05), dt)

	# === 视角模型运动 ===
	var g := group
	g.position = _hip_pos.lerp(_ads_pos, ads_amount)
	g.rotation = Vector3.ZERO
	# 拔枪/收枪
	var draw_drop := (1 - draw_t) * 0.35
	g.position.y -= draw_drop
	g.rotation.x = -(1 - draw_t) * 0.9
	# 冲刺时压低枪口
	var sp: float = p.sprint_amount
	g.position.y -= sp * 0.06
	g.position.x -= sp * 0.05
	g.rotation.x += -sp * 0.5
	g.rotation.y += sp * 0.35
	g.rotation.z = sp * 0.15
	# 后坐弹簧
	kick_z = Utils.damp(kick_z, 0, 14, dt)
	kick_rot = Utils.damp(kick_rot, 0, 12, dt)
	kick_y = Utils.damp(kick_y, 0, 13, dt)
	g.position.z += kick_z
	g.rotation.x += kick_rot
	g.rotation.y += kick_y
	# 走路摆动(bob)
	var speed := Vector2(p.vel.x, p.vel.z).length()
	if p.on_ground and speed > 0.5:
		bob_t += dt * speed * 1.6
	var bob_amp := lerpf(0.008, 0.002, ads_amount) * clampf(speed / 5.0, 0, 1)
	g.position.x += sin(bob_t) * bob_amp
	g.position.y += absf(cos(bob_t)) * bob_amp * 1.2
	# 呼吸/惯性摇摆(sway,压制时加剧)
	var sup_k = 1 + p.suppression * 2.5
	sway_x = Utils.damp(sway_x, -p.look_vel_x * 0.00006 * sup_k, 10, dt)
	sway_y = Utils.damp(sway_y, p.look_vel_y * 0.00006 * sup_k, 10, dt)
	g.position.x += sway_x * (1 - ads_amount * 0.8)
	g.position.y += sway_y * (1 - ads_amount * 0.8)
	# 呼吸摆动(开镜时更明显;压制加剧手抖)
	var br: float = 1.0 + p.suppression * 3.0
	var tb: float = G.time
	g.position.y += sin(tb * 1.55) * 0.0013 * ads_amount * br
	g.position.x += sin(tb * 0.87 + 1.3) * 0.0010 * ads_amount * br
	g.rotation.z += sin(tb * 0.7) * 0.0005 * ads_amount * br
	# 贴墙检测:压低收回武器
	var fwd: Vector3 = -G.camera.global_transform.basis.z
	var wall_hit = Utils.raycast_world(G.camera.global_position, fwd, 1.05)
	var wall_target := 0.0
	if wall_hit != null:
		wall_target = clampf(1 - wall_hit["dist"] / 1.05, 0, 1)
	wall_amt = Utils.damp(wall_amt, wall_target, 12, dt)
	var wa := wall_amt * (1 - ads_amount * 0.55)
	if wa > 0.005:
		g.position.z += wa * 0.17
		g.position.y -= wa * 0.08
		g.rotation.x += wa * 0.6
	# === 换弹动画(COD 式:枪身拉近居中内倾展示细节 + 弹匣/拉机柄) ===
	var ez := func(x: float) -> float: return x * x * (3 - 2 * x)
	var reload_t01 := -1.0
	if reloading:
		var rt = _reload_dur
		var t := minf(reload_t / rt, 1.0)
		reload_t01 = t
		# 枪身姿态:前 16% 淡入,末 18% 淡出,中段保持(看清机匣/弹匣井细节)
		var k_in: float = ez.call(minf(t / 0.16, 1.0))
		var k_out: float = ez.call(clampf((1.0 - t) / 0.18, 0.0, 1.0))
		var dip := k_in * k_out
		g.position.z += dip * 0.055    # 拉近镜头
		g.position.x -= dip * 0.05     # 向屏幕中心靠拢
		g.position.y += dip * 0.03     # 略抬升,展示弹匣井
		g.rotation.y += dip * 0.3      # 内转,展示拉机柄/抛壳窗侧
		g.rotation.z += dip * 0.34     # COD 式左倾斜持
		g.rotation.x += dip * 0.08
		# 弹匣:滑出 → 掉落 → 新弹匣插入 → 拍实
		if _mag != null:
			if _mag_anim == "side":
				# AK/SVD 前挂后卡:绕前卡榫旋出/旋入
				if t < 0.15:
					_mag.visible = true
					_mag.rotation.x = 0
				elif t < 0.32:
					_mag.rotation.x = ez.call((t - 0.15) / 0.17) * 0.75
					_mag.position.x = _mag_x0 + ez.call((t - 0.15) / 0.17) * 0.1
				elif t < 0.55:
					if _mag.visible:
						_mag.visible = false
						_mag.rotation.x = 0
						_drop_mag()
				elif t < 0.78:
					_mag.visible = true
					_mag.position.x = _mag_x0 + 0.1 - ez.call((t - 0.55) / 0.23) * 0.1
					_mag.rotation.x = 0.6 - ez.call((t - 0.55) / 0.23) * 0.6
				elif t < 0.86:
					_mag.rotation.x = 0
					_mag.position.x = _mag_x0 - sin((t - 0.78) / 0.08 * PI) * 0.012
				else:
					_mag.visible = true
					_mag.rotation.x = 0
					_mag.position.x = _mag_x0
			elif _mag_anim == "drum":
				if t < 0.15:
					_mag.visible = true
					_mag.rotation.z = 0
					_mag.position.y = _mag_y0
				elif t < 0.32:
					var k: float = ez.call((t - 0.15) / 0.17)
					_mag.rotation.z = k * 0.9
					_mag.position.y = _mag_y0 - k * 0.1
				elif t < 0.55:
					if _mag.visible:
						_mag.visible = false
						_drop_mag()
				elif t < 0.78:
					var k: float = ez.call((t - 0.55) / 0.23)
					_mag.visible = true
					_mag.rotation.z = 0.9 - k * 0.9
					_mag.position.y = _mag_y0 - 0.1 + k * 0.1
				else:
					_mag.visible = true
					_mag.rotation.z = 0
					_mag.position.y = _mag_y0
			else:
				if t < 0.15:
					_mag.visible = true
					_mag.position.y = _mag_y0
				elif t < 0.32:
					_mag.position.y = _mag_y0 - ez.call((t - 0.15) / 0.17) * 0.16
				elif t < 0.55:
					if _mag.visible:
						_mag.visible = false
						_drop_mag()
				elif t < 0.78:
					_mag.visible = true
					_mag.position.y = _mag_y0 - 0.16 + ez.call((t - 0.55) / 0.23) * 0.16
				elif t < 0.86:
					# 拍实:冲锋枪加大拍击(HK slap)
					var pat := 0.035 if def.kind == "smg" else 0.018
					_mag.position.y = _mag_y0 + sin((t - 0.78) / 0.08 * PI) * pat
				else:
					_mag.visible = true
					_mag.position.y = _mag_y0
		# 左手路径(跟随弹匣)
		_left_hand.position = _hand_path(t)
		# 火箭筒:膛内弹抽出→装入
		if _rocket != null:
			_rocket.visible = not (t > 0.15 and t < 0.78)
		# 拉机柄上膛(t 0.84-0.97):步枪/冲锋枪/LMG/DMR 短后拉复位(战术换弹不上膛)
		if _bolt != null and id != "awm" and id != "m24" and not _tac:
			if t > 0.84 and t < 0.97:
				var st := (t - 0.84) / 0.13
				_bolt.position = _bolt_base + Vector3(0, 0, sin(st * PI) * 0.045)
			else:
				_bolt.position = _bolt_base
		# 栓动狙:换弹末触发完整枪栓循环(上抬解锁→后拉→前推→下压)
		if (id == "awm" or id == "m24") and t > 0.84 and bolt_t <= 0 and not _tac:
			bolt_t = 0.0001
			_bolt_snd = false
		# 霰弹枪:装填完毕泵动上膛(仅空仓链式装填的最后一发)
		if _pump != null and t > 0.88 and pump_t <= 0 and not _tac and _pump_last:
			pump_t = 0.0001
		# 手枪专属:末尾套筒后拉上膛(沿枪管轴)
		if _slide != null and not _tac:
			if t > 0.84 and t < 0.97:
				var st := (t - 0.84) / 0.13
				_slide.position.x = _slide_base_x - sin(st * PI) * 0.03
			else:
				_slide.position.x = _slide_base_x
		# 落定抖动
		if t > 0.82 and t < 0.96:
			var s2 := sin((t - 0.82) / 0.14 * PI)
			g.rotation.z += s2 * 0.03
			g.position.y += s2 * 0.008
	else:
		if _mag != null and not _mag.visible:
			_mag.visible = true
		if _mag != null:
			_mag.position.y = _mag_y0
			_mag.position.x = _mag_x0
			_mag.rotation.z = 0
		# 左手回位
		_left_hand.position.x = Utils.damp(_left_hand.position.x, _hand_l0.x, 12, dt)
		_left_hand.position.y = Utils.damp(_left_hand.position.y, _hand_l0.y, 12, dt)
		_left_hand.position.z = Utils.damp(_left_hand.position.z, _hand_l0.z, 12, dt)
	# 左手抓握姿态
	var grip_target := 1.0 if ((reload_t01 > 0.12 and reload_t01 < 0.36) or (reload_t01 > 0.58 and reload_t01 < 0.88)) else 0.0
	grip_amt = Utils.damp(grip_amt, grip_target, 14, dt)
	_left_hand.rotation.x = lerpf(0.1, -0.7, grip_amt)
	_left_hand.rotation.y = lerpf(0, 0.25, grip_amt)
	_left_hand.rotation.z = lerpf(PI - 0.15, PI - 0.35, grip_amt)
	# 臂筒:手腕 → 屏外肘锚点连续定向(修复断臂)
	_point_arm(_left_arm, _left_hand.position, ELBOW_L)
	_point_arm(_right_arm, _right_hand.position, ELBOW_R)
	# === AWM/M24 拉栓动画 ===
	if bolt_t > 0:
		bolt_t += dt
		if bolt_t > 0.18 and not _bolt_snd:
			_bolt_snd = true
			AudioSys.bolt()
		var bt := bolt_t / 0.85
		if bt >= 1:
			bolt_t = 0
			if _bolt != null:
				_bolt.position = _bolt_base
		elif _bolt != null:
			if bt < 0.2:
				_bolt.position.y = _bolt_base.y + bt / 0.2 * 0.025
			elif bt < 0.45:
				_bolt.position.y = _bolt_base.y + 0.025
				_bolt.position.z = _bolt_base.z + (bt - 0.2) / 0.25 * 0.07
			elif bt < 0.7:
				_bolt.position.z = _bolt_base.z + 0.07 - (bt - 0.45) / 0.25 * 0.07
			else:
				_bolt.position.y = _bolt_base.y + 0.025 - (bt - 0.7) / 0.3 * 0.025
			g.rotation.z += sin(bt * PI) * 0.05
	# === 霰弹枪泵动动画(沿枪管轴) ===
	if pump_t > 0:
		pump_t += dt
		var pt := pump_t / 0.45
		if pt >= 1:
			pump_t = 0
			if _pump != null:
				_pump.position = _pump_base
		elif _pump != null:
			_pump.position.x = _pump_base.x - sin(pt * PI) * 0.06
			g.rotation.x += sin(pt * PI) * 0.06
	# 狙击开镜:全屏放大 + 镜模型遮罩,隐藏枪身模型
	if def.scope:
		g.visible = ads_amount < 0.7 and draw_t > 0.1


## 手臂定向:腕部 → 屏外肘锚点,臂筒连续伸缩(修复第一人称断臂)
func _point_arm(arm: Node3D, wrist: Vector3, elbow: Vector3) -> void:
	if arm == null:
		return
	var d := wrist - elbow
	var arm_len := maxf(d.length(), 0.06)
	arm.position = (wrist + elbow) * 0.5
	arm.basis = Basis.looking_at(d / arm_len, Vector3.UP, true) * Basis.from_scale(Vector3(1.0, 1.0, arm_len * 1.1))


## 枪口在主世界坐标(视角模型层 → 主场景变换)
func muzzle_world_main() -> Vector3:
	return G.camera.global_transform * (group.transform * muzzle.position)
