class_name Gun extends RefCounted
## 枪械手感(对应 weapons.js 的 Gun 类):射击/换弹/后座/视角模型动画

const HIP_POS := Vector3(0.17, -0.155, -0.34)
const ADS_POS := Vector3(0, -0.0755, -0.26)
# 手臂肘部屏外锚点(枪身局部空间):臂筒自手腕延伸至屏幕外,消除断臂。
# 锚点必须保持 z < -group.z(约 -0.34),即位于视角相机前方;旧值在相机后方,
# 透视翻转后右臂会从屏幕中央/胸口方向穿出。现在分别推到画面右下/左下角。
const ELBOW_R := Vector3(0.26, -0.50, 0.22)
const ELBOW_L := Vector3(-0.34, -0.46, 0.20)
# 火箭筒 CLU 昼视镜可切换放大倍率:开镜时滚轮上/下在 0×(宽视野)→ 2× → 4× 间切换。
# 0× 表示不放大(镜内与镜外同 FOV),弹道等高线会按当前倍率自动重算刻度间距。
const RPG_ZOOM_LEVELS := [0.0, 2.0, 4.0]

var def                         # WeaponDef(改装后为实例级副本,不污染全局表)
var id := ""
var mods_cfg := {}              # 改装配置 {槽位: 改装件id}(setup 时读档)
var mag_cap := 30               # 应用 mag_ammo 后的弹匣上限(HUD 余量条/换弹判断基准)
var player = null               # Player
var group: Node3D = null        # 武器模型(vm_camera 子节点)
var muzzle: Node3D = null
var ammo := 0
var reserve := 0
var reloading := false
var reload_t := 0.0            # 当前换弹计时(兼容截图/诊断脚本)
var reload_ctl: WeaponReloadController = null
var reload_pose := Vector3.ZERO   # 换弹控制器输出的视角模型位移
var reload_rot := Vector3.ZERO    # 换弹控制器输出的视角模型旋转
var fire_timer := 0.0
var ads_amount := 0.0
var ads_held := false
var zoom_idx := 2                # 火箭筒 CLU 倍率档位(RPG_ZOOM_LEVELS 索引,默认 4×)
var bloom := 0.0                # 连射扩散
var kick_z := 0.0
var kick_rot := 0.0             # 视角模型后坐
var draw_t := 1.0               # 拔枪动画
var trigger_held := false
var fire_mode := 0              # 0=全自动 1=半自动(B 键切换;仅步枪可切换)
var equipped := false
var bolt_t := 0.0               # 拉栓动画(AWM/M24)
var pump_t := 0.0               # 泵动动画(M1014)
var wall_amt := 0.0
var grip_amt := 0.0
var _semi_ready := true
var _bolt_snd := false
var shot_streak := 0              # 连射计数(后坐力/散布递增)
var last_shot_t := -99.0
var _kick_side := -1.0            # 水平后坐模式方向(左右交替)
var kick_y := 0.0                 # 视角模型水平后坐
# === 枪械改装应用后的运行时倍率(setup 时一次性计算,避免每帧开销) ===
var _dmg_mult := 1.0
var _reload_mult := 1.0
var _recoil_mult := 1.0
var _recoil_pitch_mult := 1.0
var _recoil_yaw_mult := 1.0
var _hip_spread_mult := 1.0
var _spread_mult := 1.0
var _mobility_mult := 1.0            # 枪械重量 → 移动速度倍率
var _aim_stability := 1.0            # 瞄准稳定性 → 开镜散布倍率
var _suppressed := false          # 消音器:射击静音

var _mag: Node3D = null             # 弹匣(直插 MeshInstance3D 或弯弹匣 Node3D 根)
var _mag_y0 := 0.0
var _mag_x0 := 0.0
var _mag_anim := "down"
var _bolt: Node3D = null            # 拉机柄/枪机(换弹上膛驱动)
var _bolt_base := Vector3.ZERO
var _pump: MeshInstance3D = null
var _pump_base := Vector3.ZERO
var _slide: MeshInstance3D = null
var _slide_base_z := 0.0
var _rocket: Node3D = null              # 火箭筒膛内弹(换弹时隐藏→装入)
var _bullet_type := 0                    # 0=rifle 1=sniper 2=shotgun 3=pistol

var _right_hand: Node3D = null
var _left_hand: Node3D = null
var _right_arm: Node3D = null
var _left_arm: Node3D = null
var _hand_l0 := Vector3.ZERO
var _hand_l1 := Vector3.ZERO
var hand_l2 := Vector3(0.03, -0.34, 0.02)
var _hip_pos := Vector3.ZERO
var _ads_pos := Vector3.ZERO
var _right_hand_base := Vector3.ZERO
var _right_hand_rot0 := Vector3.ZERO
var _left_hand_rot0 := Vector3.ZERO
var _holster_tw: Tween = null
var _holster_ready := false       # 首次 equip 后才启用平滑收枪(避免初始多枪同屏)
# === Procedural Motion 每把枪独立手感(确定性,非随机) ===
var motion_weight := 1.0                  # 枪械重量系数(影响 Bob/Sway/惯性/弹簧软硬)
var motion_breath_freq_mult := 1.0        # 呼吸频率差异
var motion_breath_amp_mult := 1.0         # 呼吸幅度差异
var motion_breath_phase := 0.0            # 呼吸运行相位(初始由 id 确定性生成)
var motion_bob_phase := 0.0               # Bob 相位偏移(避免所有枪同相位)
# === 原始备份枪械晃动参数(直接叠加,与已完成项目版本一致) ===
var bob_t := 0.0
var sway_x := 0.0
var sway_y := 0.0


func _init(weapon_id: String, p) -> void:
	def = WeaponsData.W()[weapon_id]
	id = weapon_id
	player = p
	_apply_mods()
	# mods_cfg 已由上方 _apply_mods() 就绪(load_cfg 含默认标准件),传入后 viewmodel 挂载改装件
	group = WeaponModels.build(weapon_id, true, mods_cfg)
	muzzle = group.get_meta("muzzle")
	ammo = def.mag
	reserve = def.reserve

	if group.has_meta("mag"):
		_mag = group.get_meta("mag")
		_mag_y0 = _mag.position.y
		_mag_x0 = _mag.position.x
	# 弹匣动画类型:AK/SVD 前挂后卡(侧摆),机枪弹鼓/弹链箱(专用流程),P90 顶置弹匣(上抽),其余直插(下沉)
	_mag_anim = "down"
	if weapon_id in ["ak", "svd"]:
		_mag_anim = "side"
	elif weapon_id == "rpd":
		_mag_anim = "drum"
	elif weapon_id in ["m249", "pkm", "mg42", "m60", "mk48", "negev", "mg3"]:
		_mag_anim = "belt"
	elif weapon_id == "p90":
		_mag_anim = "up"
	if group.has_meta("pump"):
		_pump = group.get_meta("pump")
		_pump_base = _pump.position
	if group.has_meta("slide"):
		_slide = group.get_meta("slide")
	_slide_base_z = 0.0
	if _slide != null:
		_slide_base_z = _slide.position.z
	if group.has_meta("rocket"):
		_rocket = group.get_meta("rocket")
	if group.has_meta("bolt"):
		_bolt = group.get_meta("bolt")
		_bolt_base = _bolt.position
	_bullet_type = 0
	if weapon_id in ["awm", "m24", "svd"]:
		_bullet_type = 1
	elif weapon_id in ["m1014", "spas12"]:
		_bullet_type = 2
	elif weapon_id in ["g17", "m1911", "p226", "deagle", "m93r"]:
		_bullet_type = 3
	_init_motion_profile(weapon_id)
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
	# 手部基准(换弹控制器负责双手/枪机配合)
	if _left_hand != null:
		_left_hand_rot0 = _left_hand.rotation
	if _right_hand != null:
		_right_hand_base = _right_hand.position
		_right_hand_rot0 = _right_hand.rotation
	# 模块化换弹控制器(全部阶段/取消/枪机动作由 ReloadProfiles 配置驱动)
	reload_ctl = WeaponReloadController.new(self)


## 改装应用层:读档 → 聚合属性 → 构建实例级 def 副本(不污染 WeaponsData 全局表)
func _apply_mods() -> void:
	mods_cfg = WeaponModsData.load_cfg(id)
	if mods_cfg.is_empty():
		mag_cap = def.mag
		return
	var eff := WeaponModsData.total_effects(mods_cfg)
	var applied := 0
	for slot in mods_cfg:
		if not WeaponModsData.effect_total(mods_cfg, slot).is_empty():
			applied += 1
	if applied > 0:
		_dmg_mult = float(eff.get("dmg_mult", 1.0))
		_reload_mult = float(eff.get("reload_mult", 1.0))
		_recoil_mult = float(eff.get("recoil_mult", 1.0))
		_recoil_pitch_mult = float(eff.get("recoil_pitch_mult", 1.0))
		_recoil_yaw_mult = float(eff.get("recoil_yaw_mult", 1.0))
		_hip_spread_mult = float(eff.get("hip_spread_mult", 1.0))
		_spread_mult = float(eff.get("spread_mult", 1.0))
		_mobility_mult = float(eff.get("mobility_mult", 1.0))
		_aim_stability = float(eff.get("aim_stability", 1.0))
		_suppressed = bool(eff.get("suppress", false))
		# 静态属性写入 def 副本(伤害/射速/开镜速度/弹匣容量/备弹),运行时只读副本
		var nd: WeaponsData.WeaponDef = WeaponModsData.clone_def(def)
		nd.damage = def.damage * _dmg_mult
		nd.rpm = maxf(10.0, def.rpm * float(eff.get("fire_rate_mult", 1.0)))
		nd.ads_time = maxf(0.02, def.ads_time / float(eff.get("ads_speed_mult", 1.0)))
		var mag_extra: int = int(eff.get("mag_ammo", 0))
		nd.mag = maxi(1, def.mag + mag_extra)
		nd.reserve = maxi(0, def.reserve + mag_extra)
		def = nd
	# === optic 视野决策:红点 50(≈1.5x)/全息 55(机瞄同等)/2 倍镜 28(≈2x)/棱镜与红点同级;
	#     狙击枪(def.scope)自带 zoom_fov 数据值更小,任何 optic 改装都不覆盖其 zoom。
	var optic_id: String = String(mods_cfg.get("optic", "opt_std"))
	if optic_id != "opt_std" and not def.scope:
		# 纯标准件组合时 def 仍是全局表引用:先构建副本再写,不污染 WeaponsData 全局表
		if def == WeaponsData.W()[id]:
			def = WeaponModsData.clone_def(def)
		match optic_id:
			"opt_reddot", "opt_reddot_mini", "opt_1xprism":
				def.zoom_fov = 50.0
			"opt_reddot_dot":
				def.zoom_fov = 52.0
			"opt_holo":
				def.zoom_fov = 55.0
			"opt_2x":
				def.zoom_fov = 28.0
	mag_cap = def.mag
	print("[MODS] %s 应用了 %d 个改装件" % [id, applied])


## 每把武器独立的程序化运动手感(武器重量 + 确定性呼吸差异)。
## 重量由武器类别决定;呼吸频率/幅度/相位由 id 哈希生成,同一把枪永远一致。
func _init_motion_profile(weapon_id: String) -> void:
	var kind := String(def.kind)
	motion_weight = float(FirstPersonMotionSystem.KIND_WEIGHT.get(kind, 1.0))
	# 短枪频率略高、长枪/机枪更慢;幅度随重量略有变化,但保持 ADS 可用
	motion_breath_freq_mult = 1.08 if kind in ["pistol", "smg"] else (0.88 if kind in ["lmg", "sniper", "rpg"] else 1.0)
	motion_breath_amp_mult = 0.88 if kind in ["pistol", "smg"] else (1.14 if kind in ["lmg", "sniper", "rpg"] else 1.0)
	var h := 0
	for i in weapon_id.length():
		h = (h * 131 + weapon_id.unicode_at(i)) % 1000003
	motion_breath_phase = fmod(float(h % 997) / 997.0 * TAU + 0.37, TAU)
	motion_bob_phase = fmod(float(h % 613) / 613.0 * TAU + 0.19, TAU)
	motion_breath_freq_mult *= 1.0 + float(h % 7) * 0.006
	motion_breath_amp_mult *= 1.0 + float(h % 5) * 0.012


func equip() -> void:
	equipped = true
	_holster_ready = true
	if _holster_tw != null and _holster_tw.is_valid():
		_holster_tw.kill()
	_holster_tw = null
	group.visible = true
	draw_t = 0
	reloading = false
	if reload_ctl != null:
		reload_ctl.reset()
	# 切枪/重生清零视角模型后坐弹簧与换弹姿态,避免残留跳动
	kick_z = 0
	kick_rot = 0
	kick_y = 0
	bolt_t = 0
	pump_t = 0
	reload_pose = Vector3.ZERO
	reload_rot = Vector3.ZERO
	# 新枪接管程序化运动弹簧:不同重量从零开始建立,不继承旧枪残量
	if player != null and player.motion != null:
		player.motion.on_weapon_equipped(self)


func holster(instant := false) -> void:
	equipped = false
	if group == null or not is_instance_valid(group):
		return
	# 主菜单/退出对局等场景必须瞬时隐藏,不能用平滑收枪 Tween,
	# 否则视角模型会在菜单出现的头几帧残留手臂/枪械。
	if instant:
		if _holster_tw != null and _holster_tw.is_valid():
			_holster_tw.kill()
		_holster_tw = null
		if reload_ctl != null:
			reload_ctl.on_holster()
		group.visible = false
		return
	if reload_ctl != null:
		reload_ctl.on_holster()
	# 尚未真正上手的枪(初始化/换装时批量 holster)直接隐藏,避免同屏重叠
	if not _holster_ready:
		group.visible = false
		return
	# 平滑收枪:从当前姿态(可能正在换弹)向屏幕外下方带惯性地收,不做瞬时隐藏
	if _holster_tw != null and _holster_tw.is_valid():
		_holster_tw.kill()
	var start_pos: Vector3 = group.position
	var start_rot: Vector3 = group.rotation
	var tw := group.create_tween()
	_holster_tw = tw
	tw.set_parallel(true)
	tw.tween_property(group, "position", start_pos + Vector3(0.08, -0.16, 0.05), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(group, "rotation", start_rot + Vector3(-0.35, 0.25, -0.12), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		_holster_tw = null
		if is_instance_valid(group):
			group.visible = false)


func can_ads() -> bool:
	# 换弹中允许进入 ADS:ReloadController 会把换弹姿态按 ads_keep 平滑让位,
	# 准星/枪械/镜头始终使用同一组插值,避免脱节。
	if reload_ctl != null and not bool(reload_ctl.cfg.get("ads_allowed", true)):
		return false
	return draw_t > 0.7


func current_spread() -> float:
	var d = def
	var p = player
	# 瞄准稳定性:开镜散布倍率(长枪管/重型枪托/棱镜等)
	var s := lerpf(d.spread_hip * _hip_spread_mult, d.spread_ads * _aim_stability, ads_amount)
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
	return s * _spread_mult * (PI / 180.0)


## B 键切换射击模式:全自动 ⇄ 半自动(仅步枪;半自动=按一下打一发)
func toggle_fire_mode() -> void:
	if def.kind != "rifle":
		AudioSys.dry_fire()
		return
	fire_mode = 1 - fire_mode
	_semi_ready = true
	AudioSys.ui()
	if G.hud != null and G.hud.has_method("hint"):
		G.hud.hint("射击模式: " + ("半自动(单发)" if fire_mode == 1 else "全自动"))


## 是否半自动模式(供 HUD 显示)
func is_semi() -> bool:
	return fire_mode == 1


func try_fire() -> void:
	if draw_t < 0.6 or fire_timer > 0:
		return
	if player.sprint_amount > 0.5:
		return
	# ADS 状态下换弹:即使 reloading 已置 false、收尾动画仍在播放,也不允许提前击发,
	# 避免“按住右键时换弹动作还没播完就开枪”。
	if reload_ctl != null and reload_ctl.is_animating() and (ads_held or ads_amount > 0.35):
		return
	if reloading:
		if reload_ctl == null:
			return
		# 可中断系统:准备/拔弹早期(旧匣未脱离)与新匣推入后允许立即开火;
		# 弹匣脱离但未装好时无法射击,保持换弹不锁死玩家。
		if def.pellets <= 1:
			if reload_ctl == null or not reload_ctl.can_fire_interrupt():
				return
		else:
			# 霰弹枪:至少已推入一发且泵动循环收尾后才能打断开火
			if ammo <= 0:
				return
			if reload_ctl != null and reload_ctl.is_busy_cycle():
				return
		# 霰弹枪:管式弹仓逐发装填中开火,保留已推入弹数并自然收回
		if reload_ctl != null:
			reload_ctl.cancel("fire")
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
		# 制导只属于毒刺(rpg):榴弹发射器永远走无制导抛物线弹道
		var locked = G.lock_target if id == "rpg" else null
		var use_def = def
		if locked != null:
			use_def = { "cn": "反载具毒刺导弹", "name": "反载具毒刺导弹", "damage": 320.0, "splash": 10.0, "speed": 50.0, "tracer": def.tracer }
		G.effects.spawn_rocket(p, use_def, origin, dir, locked)
		if locked != null:
			G.hud.hint("防空导弹已发射,追踪目标中")
			G.lock_target = null
		AudioSys.rpg_fire(p.pos)
	else:
		var pellets = def.pellets
		var spread := current_spread()
		var mv := muzzle_world_main()
		var cam_basis := aim_basis()
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
		AudioSys.shoot_weapon(id, def.kind, p.pos, true, _suppressed)

	# === 3A 后坐力曲线:首发高、连射递增、水平左右模式、开镜降低 ===
	var ads_scale := lerpf(1.0, 0.62, ads_amount)
	var k: float = def.recoil_first if shot_streak <= 0 else minf(1.0 + def.recoil_ramp * float(shot_streak), 1.5)
	p.recoil_pitch += def.recoil_pitch * k * ads_scale * (_recoil_mult * _recoil_pitch_mult) * (PI / 180.0)
	# 水平后坐:72% 概率换向(左右交替但有模式感)
	if randf() < 0.72:
		_kick_side = -_kick_side
	p.recoil_yaw += _kick_side * Utils.rand(0.55, 1.0) * def.recoil_yaw * k * ads_scale * (_recoil_mult * _recoil_yaw_mult) * (PI / 180.0)
	# 摄像机微后坐(开火瞬间视角震动,随后坐力弹簧回正)
	p.cam_kick_pitch += def.recoil_cam * k * (0.5 + ads_scale * 0.5) * _recoil_mult
	p.cam_kick_yaw += _kick_side * Utils.rand(0.2, 0.7) * def.recoil_cam * 0.4 * k * _recoil_mult
	# 视角模型后坐:后缩 + 上仰 + 水平侧移(开镜收敛 80%,枪口不挡瞄准视野)
	var vm_k := lerpf(1.0, 0.2, ads_amount)   # 腰射 1.0 不变;满开镜 0.2
	kick_z += def.recoil_vm * k * vm_k * _recoil_mult
	kick_rot += def.recoil_vm * 1.6 * k * vm_k * _recoil_mult
	kick_y += Utils.rand(0.01, 0.024) * k * vm_k * _recoil_mult
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
	if id in ["awm", "m24", "m40", "l115", "sv98", "m2010"]:
		bolt_t = 0.0001
		_bolt_snd = false
	if _pump != null:
		pump_t = 0.0001
	if ammo == 0:
		reload()


## 弹匣/弹鼓/弹链箱掉落
func _drop_mag() -> void:
	if _mag == null:
		return
	# 按当前换弹流程决定世界掉落物模型:弹鼓掉落圆鼓,弹链机枪掉落弹链箱,
	# 普通武器仍掉落弹匣,避免 RPD 掉出步枪弹匣、M249 掉出小手枪弹匣的违和感。
	var drop_kind := "mag"
	if reload_ctl != null and not reload_ctl.cfg.is_empty():
		match String(reload_ctl.cfg.get("reload_flow", "mag")):
			"drum":
				drop_kind = "drum"
			"belt":
				drop_kind = "beltbox"
	# _mag 属于 vm_camera(own_world_3d 独立 SubViewport)子树,其 global_position 是视角模型层
	# 局部世界坐标,直接传入会把弹匣放到原点附近;与 muzzle_world_main 同约定:
	# 经主相机全局变换把 视角模型层局部坐标 → 主世界坐标
	var world_pos: Vector3 = G.camera.global_transform * (group.transform * _mag.position)
	G.effects.spawn_mag(world_pos, G.camera.global_transform.basis, drop_kind)


func reload() -> void:
	if reload_ctl == null:
		return
	if reloading or ammo >= mag_cap or reserve <= 0:
		return
	# 普通换弹 vs 空仓换弹、逐发装填与枪机操作全部交给模块化控制器。
	reload_ctl.start()


func update(dt: float) -> void:
	if not equipped:
		return
	var g := group
	# 防悬空:换枪/BR 剥装时序下 group 可能已被 queue_free(帧末销毁),跳过本帧
	if not is_instance_valid(g):
		return
	var p = player
	fire_timer -= dt
	draw_t = minf(1, draw_t + dt / 0.28)
	bloom = maxf(0, bloom - dt * 3.5)
	# 后坐力连射计数:停火超时复位
	if G.time - last_shot_t > def.recoil_recover:
		shot_streak = 0

	# 扳机(全自动=按住连发;半自动/手动切半自动=按下沿单发)
	var auto_fire: bool = def.auto and fire_mode == 0
	if trigger_held and (auto_fire or _semi_ready):
		try_fire()
	if not trigger_held:
		_semi_ready = true
	elif not auto_fire:
		_semi_ready = false

	# ADS 插值(指数缓动:起手快、落点稳,放大倍率过渡顺滑)
	var ads_target := 1.0 if (ads_held and can_ads()) else 0.0
	if ads_target != ads_amount:
		ads_amount = Utils.damp(ads_amount, ads_target, 2.6 / maxf(def.ads_time, 0.05), dt)

	# === 视角模型运动 ===
	g.position = _hip_pos.lerp(_ads_pos, ads_amount)
	# 视角模型深度/臂长设置:整体向屏幕内伸展,并放大视角模型让细节更清楚
	var vm_depth := _viewmodel_depth()
	g.position.z += (vm_depth - 1.0) * 0.09
	# 肩扛式反载具武器:从屏幕右下横入画面、模型明显放大,ADS 时前移到 CLU 目镜位置
	var vm_scale_k := 1.55 if id == "rpg" else 1.0
	g.scale = Vector3.ONE * clampf((1.0 + (vm_depth - 1.0) * 0.18) * vm_scale_k, 0.8, 1.7)
	g.rotation = Vector3.ZERO
	if id == "rpg":
		# 发射器头部沿中心向左旋转 5°(ADS 时回正以对准 CLU 目镜)
		g.rotation.y = lerpf(deg_to_rad(5.0), 0.0, ads_amount)
		g.rotation.x = lerpf(-0.05, 0.0, ads_amount)
		g.rotation.z = lerpf(0.06, 0.0, ads_amount)
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
	# === 模块化换弹控制器 ===
	# 控制器输出换弹姿态/双手/弹匣/枪机动作;这里只叠加,不在 gun.gd 写死动画。
	if reload_ctl != null:
		reload_ctl.update(dt)
		if reloading:
			reload_t = reload_ctl.time
		g.position += reload_pose
		g.rotation += reload_rot
	# === 枪械自然晃动(走路 Bob / 鼠标惯性 Sway / 呼吸) ===
	# ADS 时枪身必须稳定:Bob/Sway/呼吸在满镜时收敛到 0,只保留开火后坐与换弹动画。
	var speed := Vector2(p.vel.x, p.vel.z).length()
	if p.on_ground and speed > 0.5:
		bob_t += dt * speed * 1.6
	var bob_amp := lerpf(0.008, 0.0, ads_amount) * clampf(speed / 5.0, 0, 1)
	g.position.x += sin(bob_t) * bob_amp
	g.position.y += absf(cos(bob_t)) * bob_amp * 1.2
	# 呼吸/惯性摇摆(sway,压制时加剧);ADS 满镜时完全消除
	var sup_k = 1 + p.suppression * 2.5
	sway_x = Utils.damp(sway_x, -p.look_vel_x * 0.00006 * sup_k, 10, dt)
	sway_y = Utils.damp(sway_y, p.look_vel_y * 0.00006 * sup_k, 10, dt)
	g.position.x += sway_x * (1.0 - ads_amount)
	g.position.y += sway_y * (1.0 - ads_amount)
	# 呼吸摆动:腰射与满镜均为 0,仅在 ADS 过渡中段有极轻微起伏
	var br: float = 1.0 + p.suppression * 3.0
	var tb: float = G.time
	var breath_k := ads_amount * (1.0 - ads_amount)
	g.position.y += sin(tb * 1.55) * 0.0013 * breath_k * br
	g.position.x += sin(tb * 0.87 + 1.3) * 0.0010 * breath_k * br
	g.rotation.z += sin(tb * 0.7) * 0.0005 * breath_k * br
	# 臂筒:手腕 → 屏外肘锚点连续定向(修复断臂)
	_point_arm(_left_arm, _left_hand.position, ELBOW_L)
	_point_arm(_right_arm, _right_hand.position, ELBOW_R)
	# === AWM/M24 拉栓动画 ===
	if bolt_t > 0:
		bolt_t += dt
		if bolt_t > 0.18 and not _bolt_snd:
			_bolt_snd = true
			if reloading:
				AudioSys.reload_action(String(reload_ctl.cfg.get("bolt_snd", "bolt_cycle")))
			else:
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
			# 泵动护木沿枪管轴 z 前后运动:护木(cyl z 轴长 0.12)位于枪身前段 z=-0.34,枪口朝 -Z;
			# 负 sin = 先向 -Z(朝枪口)前推再复位,即装填完毕"推弹入膛"的收尾微动(完整后拉上膛相位含在 0.45s 泵动内),
			# 幅度 0.06 ≈ 护木长度一半,行程醒目
			_pump.position.z = _pump_base.z - sin(pt * PI) * 0.06
			g.rotation.x += sin(pt * PI) * 0.06
	# 高倍率狙击镜 PIP:ADS 时隐藏镜筒实体/黑目镜,只留高透目镜、细分划与细镜口圈;
	# 镜外完全透明(正常视野)。非 ADS 时恢复全黑镜筒,避免透明枪筒观感。
	_update_pip_scope_visuals(g, ads_amount)
	# === 光学瞄具 3D 分划:普通瞄具开镜时隐藏,由 2D HUD 稳定准星接管(防贴目放大/模糊/双准星) ===
	if ret_style() != "":
		_set_ret_visible(g, ads_amount < 0.5)


## 高倍镜内部可见性切换:非 ADS 全黑镜筒;ADS 只留透明目镜 + 分划。
func _update_pip_scope_visuals(g: Node3D, ads: float) -> void:
	if not def.scope:
		return
	var in_ads := ads >= 0.5
	var body: Node3D = _meta_node(g, "scope_tube")
	if body != null:
		# 毒刺 CLU 的方形目镜筒在 ADS 时保留,作为 PIP 取景框;狙击镜仍隐藏镜筒
		body.visible = (id == "rpg") or not in_ads
	var clu_body: Node3D = _meta_node(g, "scope_clu")
	if clu_body != null:
		clu_body.visible = not in_ads
	var black: MeshInstance3D = _meta_node(g, "scope_lens_black") as MeshInstance3D
	if black != null:
		black.visible = not in_ads
	var clear: MeshInstance3D = _meta_node(g, "scope_lens_clear") as MeshInstance3D
	if clear != null:
		clear.visible = in_ads
	var reticle: Node3D = _meta_node(g, "scope_reticle")
	if reticle != null:
		reticle.visible = in_ads
	# 部分狙击枪原厂导轨上仍有机瞄;ADS 时隐藏,避免共轴机瞄遮挡 PIP 镜内视野。
	var irons: Node3D = g.get_node_or_null("StockIrons")
	if irons != null:
		irons.visible = not in_ads


func _meta_node(g: Node3D, meta: String) -> Node3D:
	if g == null or not g.has_meta(meta):
		return null
	var n: Node3D = g.get_meta(meta)
	if n == null or not is_instance_valid(n):
		return null
	return n


## 是否使用独立镜内渲染的高倍率狙击镜(仅 def.scope 武器)。
## SKS/M110 原厂镂空镜为低倍率 DMR 镜,继续走普通 ADS + HUD 分划,不再误入全屏镜罩。
func scope_sight() -> bool:
	if not def.scope:
		return false
	var eye: Node3D = group.get_meta("scope_eye") if group != null and group.has_meta("scope_eye") else null
	return eye != null and is_instance_valid(eye) and eye.is_inside_tree() and eye.is_visible_in_tree()


## 镜内实际 FOV:优先按真实倍率(scope_mag)和玩家基础 FOV 换算,
## 保证 75/90/110 FOV 下都获得一致的 4×/6×/7×/8× 感知倍率;
## 没有 scope_mag 的旧数据回退 def.zoom_fov。
## 火箭筒 CLU 走可切换倍率档位(0×/2×/4×),0× 档镜内与镜外同 FOV。
func scope_fov() -> float:
	var mag := float(def.scope_mag)
	if id == "rpg":
		mag = zoom_mag()
		if mag <= 1.0:
			# 0× 宽视野档:与镜外同 FOV,CLU 屏幕画面和裸眼视野连续(不放大也不缩小)
			return G.camera.fov if G.camera != null else float(G.settings.get("fov", 75.0))
	if mag > 1.0:
		var base := float(G.settings.get("fov", 75.0))
		return rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / mag))
	return float(def.zoom_fov)


## 当前光学倍率:火箭筒读 CLU 档位,其余武器读数据表 scope_mag
func zoom_mag() -> float:
	if id != "rpg":
		return float(def.scope_mag)
	return float(RPG_ZOOM_LEVELS[clampi(zoom_idx, 0, RPG_ZOOM_LEVELS.size() - 1)])


## 分划右上角倍率文字(0× 档显示 0X)
func zoom_label() -> String:
	return "%dX" % int(round(zoom_mag()))


## 火箭筒开镜时滚轮切换 CLU 倍率档位。
## 返回 true 表示本次滚轮已被瞄具消费(调用方不得再切换武器);
## 到达两端时仍然消费滚轮,避免开镜微调倍率时把武器换掉。
func cycle_zoom(dir: int) -> bool:
	if id != "rpg" or dir == 0:
		return false
	var i := clampi(zoom_idx + (1 if dir > 0 else -1), 0, RPG_ZOOM_LEVELS.size() - 1)
	if i != zoom_idx:
		zoom_idx = i
		AudioSys.ui()
		if G.hud != null:
			G.hud.hint("CLU 昼视镜倍率 %s" % zoom_label())
	return true


## 镜内渲染是否已足够开启(供 OpticScopeSystem/射击弹道使用)
func pip_scope_active() -> bool:
	return scope_sight() and ads_amount > 0.35


## 射击/索敌使用的实际瞄准轴:高倍镜满镜时跟随镜内 Optic Scope 相机,
## 否则使用主相机轴。这样镜内 3D 分划中心与子弹落点严格一致。
func aim_basis() -> Basis:
	if pip_scope_active() and G.scope != null and G.scope.has_method("aim_basis"):
		return (G.scope.aim_basis() as Basis).orthonormalized()
	return G.camera.global_transform.basis.orthonormalized()


## 当前光学瞄具的准星样式(""=机械瞄具;reddot/holo/tac 由 HUD 2D 准星绘制)
func ret_style() -> String:
	# SKS / M110 原厂镂空圆环镜:开镜时给一个固定细十字,与环心对齐
	if id in ["sks", "m110"] and String(mods_cfg.get("optic", "opt_std")) == "opt_std":
		return "tac"
	match String(mods_cfg.get("optic", "opt_std")):
		"opt_reddot", "opt_reddot_mini", "opt_reddot_dot": return "reddot"
		"opt_holo": return "holo"
		"opt_2x", "opt_1xprism": return "tac"
	return ""


## 枪械重量对移动速度的倍率(配件堆叠;玩家移动系统消费)
func mobility_mult() -> float:
	return _mobility_mult


## 递归设置枪身内分划节点可见性(RetDot/RetRing/RetCross)
func _set_ret_visible(n: Node, on: bool) -> void:
	if n.name == "RetDot" or n.name == "RetRing" or n.name == "RetCross":
		n.visible = on
	for c in n.get_children():
		_set_ret_visible(c, on)


## 视角模型深度/臂长设置(设置页可调 0.8~1.4)
func _viewmodel_depth() -> float:
	if G == null or G.settings == null:
		return 1.0
	return float(G.settings.get("viewmodel_depth", 1.0))


## 手臂定向:腕部 → 屏外肘锚点,臂筒连续伸缩(修复第一人称断臂)
func _point_arm(arm: Node3D, wrist: Vector3, elbow: Vector3) -> void:
	if arm == null:
		return
	# 肩扛式反载具武器:左臂肘锚点再向左下前方延伸,让手臂向准心方向自然前伸
	if id == "rpg" and arm == _left_arm:
		elbow = Vector3(-0.52, -0.62, 0.34)
	var depth := _viewmodel_depth()
	# 深度设置会把肘部向屏幕外/更深处推远,从而拉长前臂,让换弹细节更清楚
	var elbow2 := elbow + Vector3(0.0, 0.0, (depth - 1.0) * 0.55)
	var d := wrist - elbow2
	var arm_len := maxf(d.length(), 0.06)
	var fwd := d / arm_len
	# 手工构造稳定基:前臂长轴对齐腕-肘方向,local Y 尽量朝上,
	# 避免 Basis.looking_at 在手臂角度较大时产生绕长轴的翻滚(换弹手肘扭曲)。
	var right := Vector3.UP.cross(fwd)
	if right.length() < 0.01:
		right = Vector3.RIGHT.cross(fwd)
	right = right.normalized()
	var up := fwd.cross(right)
	arm.position = (wrist + elbow2) * 0.5
	arm.basis = Basis(right, up, fwd) * Basis.from_scale(Vector3(1.0, 1.0, arm_len * 1.1))


## 枪口在主世界坐标(视角模型层 → 主场景变换)
func muzzle_world_main() -> Vector3:
	return G.camera.global_transform * (group.transform * muzzle.position)
