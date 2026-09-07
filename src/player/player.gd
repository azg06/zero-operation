class_name Player extends Node3D
## 玩家控制器(对应 player.js)

var team := "us"
var pos := Vector3(0, 0, -100)
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var recoil_pitch := 0.0
var recoil_yaw := 0.0
var cam_kick_pitch := 0.0          # 开火瞬间摄像机微后坐(高衰减)
var cam_kick_yaw := 0.0
var reload_cam_pitch := 0.0        # 换弹镜头反馈(ReloadController 驱动,克制幅度)
var reload_cam_yaw := 0.0
var reload_cam_roll := 0.0
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
var gadget_cn := ""                 # 当前兵种技能中文名(第二技能可选,HUD/提示读它)
var gadget_count := 0
var gadget_max := 0                 # 所选技能满携带量(补给时按它回满,而非兵种默认技能量)
var class_id := "assault"
var loadout = null
var step_t := 0.0
var bob_y := 0.0
var motion: FirstPersonMotionSystem = null   # 程序化 Camera + Weapon Motion(单实例集中驱动)
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
var _veh_tp := true                  # 载具第三人称(战地式:常开;唯一第一人称=炮手右键 ADS)
var _veh_crew := 0                   # 乘员位:0=炮手位(驾驶+开炮一体) 1=观察位(纯旁观;AA 可开机枪)
var _veh_station := 0                # 当前岗位冗余标记:0=炮手位 1=观察位(与 _veh_crew 同步)
var _veh_optic_mode := 0             # 观瞄模式:0=白光 1=热成像 2=微光夜视
var _veh_scope := false              # [8/10] 炮手位炮镜(右键 ADS)
var _passenger_gun := false          # 吉普副驾驶持个人武器状态(可开火)
var _veh_fp_passenger := false       # 吉普乘客位强制第一人称(NPC 司机在位时上车)
var _killed_by_def = null
var sprint_toggled := false           # Shift 切换疾跑
var slide_t := 0.0                    # 滑铲剩余时间
var slide_dir := Vector2.ZERO         # 滑铲方向
var _slide_roll := 0.0                # 滑铲相机侧倾
var _prone_amt := 0.0                 # 趴下姿势插值(0=站立 1=全趴)

var body: Node3D = null           # 第一人称下半身
var veh_body: Node3D = null       # 第三人称载具乘员模型(吉普/炮塔探身)

# ---- 大逃杀(BR)扩展:护甲/药品背包 + 跳伞状态(player.gd 只做路由,物理归 GameMode_BR) ----
var br_armor := 0.0               # 护甲值(吸收 30% 伤害,耐久 100)
var br_armor_max := 100.0
var br_medkits := 0               # 医疗包数量(按 F 使用,+50 HP)
var _br_f_hold := 0.0             # BR F 键按住时长(短按=兵种技能,长按=使用地图医疗包)

# ---- 近战小刀(全模式) ----
var melee_active := false         # 小刀状态(与枪械/换弹/载具/跳伞互斥)
var melee: Melee = null           # 小刀实例(vm_camera 层)
var _melee_hold_t := 0.0          # H 长按累计时间
var _melee_hold_fired := false    # 本次按压是否已触发过
var _melee_auto := false          # 弹尽自动切刀(获弹后自动收回)
var _melee_last_gun := 0          # 收回时的目标枪槽
var _melee_check_t := 0.0         # 弹尽检查节流(0.25s)
var _melee_prev_empty := false    # 上一节流周期弹药状态(转移沿检测:H 手动收回后不再弹回)


func _ready() -> void:
	name = "你"
	motion = FirstPersonMotionSystem.new(self)
	body = SoldierModel.build_player_body()
	_set_fp_body_layers(body)   # 第一人称身体放入 layer 2:镜内 PIP 相机不渲染,主相机仍可见
	G.main.add_child(body)


## 把第一人称身体/乘员模型递归放入视觉 layer 2(镜内相机 cull_mask=1 排除;
## 主相机默认 cull_mask 含全部 layer,不受影响)。
func _set_fp_body_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 2
	for c in n.get_children():
		_set_fp_body_layers(c)


## 同步影子手持武器:重建 HandR 骨附件上的当前武器投影(SHADOWS_ONLY,不渲染)
## 阴影武器轮廓随切枪切换
func _update_body_gun() -> void:
	if body == null or not is_instance_valid(body) or not body.has_meta("gun_mount"):
		return
	var mount: Node3D = body.get_meta("gun_mount")
	for c in mount.get_children():
		c.queue_free()
	var g := gun()
	if g == null or g.id == "rpg":
		return
	var gn: Node3D = WeaponModels.build(g.id, false, WeaponModsData.load_cfg(g.id))
	gn.rotation_degrees = Vector3(90, 0, 0)
	var so_stack: Array = [gn]
	while not so_stack.is_empty():
		var n: Node3D = so_stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		for ch in n.get_children():
			so_stack.append(ch)
	mount.add_child(gn)
	_set_fp_body_layers(gn)


func gun() -> Gun:
	if guns.is_empty() or gun_index >= guns.size():
		return null
	return guns[gun_index]


func camera() -> Camera3D:
	return G.camera


func give_class(p_class_id: String, p_loadout) -> void:
	if melee_active:
		_deactivate_melee(false)   # 换装/重生:小刀强制收回
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
	# 兵种技能:第二技能可在部署界面「兵种装备」槽选择;loadout["gadget"] 给 id,非法值回退默认
	var gsel := ""
	if p_loadout != null and p_loadout.get("gadget") != null:
		gsel = String(p_loadout["gadget"])
	var gopt: Dictionary = WeaponsData.gadget_option(p_class_id, gsel)
	loadout["gadget"] = String(gopt.get("id", cls.gadget))
	# 清理旧枪(视角模型层)
	for g in guns:
		G.vm_camera.remove_child(g.group)
		g.group.queue_free()
	guns = [Gun.new(loadout["primary"], self)]
	# 突击兵:额外携带一把主武器霰弹枪(槽位 2)
	if not cls.shotguns.is_empty() and loadout["shotgun"] != null:
		guns.append(Gun.new(loadout["shotgun"], self))
	guns.append(Gun.new(loadout["secondary"], self))
	# 占武器槽的兵种技能(工程兵毒刺 / 突击兵榴弹发射器):按 3 切换
	if bool(gopt.get("weapon", false)):
		guns.append(Gun.new(String(gopt.get("id", "rpg")), self))
	for g in guns:
		G.vm_camera.add_child(g.group)
		g.holster()
	gun_index = 0
	gun().equip()
	_update_body_gun()
	gadget = String(gopt.get("id", cls.gadget))
	gadget_cn = String(gopt.get("cn", cls.gadget_cn))
	gadget_max = int(gopt.get("count", cls.gadget_count))
	gadget_count = gadget_max
	grenades = 2
	at_grenades = 2
	at_mines = 1
	# 重建第三人称载具乘员模型(兵种外观同步;皮肤读档,give_class 覆盖部署/重生/换兵种全部路径)
	if veh_body != null:
		veh_body.queue_free()
	veh_body = SoldierModel.build_soldier("us", loadout["primary"], class_id, SkinCfg.get_skin(class_id))
	veh_body.visible = false
	_set_fp_body_layers(veh_body)
	G.main.add_child(veh_body)


func spawn(p_pos: Vector3) -> void:
	if vehicle != null:
		exit_vehicle(true)
	pos = p_pos
	vel = Vector3.ZERO
	health = 100
	alive = true
	if motion != null:
		motion.reset(vel)
	prone = false
	body.rotation.x = 0
	# 手雷蓄力复位(重生不残留)
	_nade_arming = false
	_nade_hold = 0.0
	if _nade_vm != null and is_instance_valid(_nade_vm):
		_nade_vm.visible = false
	_nade_vm_t = -1.0
	if _adren_vm != null and is_instance_valid(_adren_vm):
		_adren_vm.visible = false
	_adren_t = -1.0
	# 重生恢复死亡时隐藏的影子武器
	if body != null and is_instance_valid(body) and body.has_meta("gun_mount"):
		var mount: Node3D = body.get_meta("gun_mount")
		for c in mount.get_children():
			if c is Node3D:
				(c as Node3D).visible = true
	spawn_protect = 4 if G.mode == "breakthrough" else 2   # [BALANCE] 突破模式出生保护延长(防出门团灭)
	last_damage_t = -99
	heal_over_time = 0
	# 面向地图中心
	yaw = atan2(-pos.x, -pos.z) + PI
	pitch = 0
	recoil_pitch = 0
	recoil_yaw = 0
	reload_cam_pitch = 0
	reload_cam_yaw = 0
	reload_cam_roll = 0
	give_class(class_id, loadout)
	# 夜视仪重部署自动关闭(防残留)
	night_vision = false
	G.effects.set_night_vision(false)
	# 小刀状态重置(重生后默认持枪)
	melee_active = false
	_melee_hold_t = 0
	_melee_hold_fired = false
	_melee_auto = false
	_melee_prev_empty = false
	if melee != null:
		melee.holster()


func apply_look(dx: float, dy: float) -> void:
	var g := gun()
	var ads := g.ads_amount if g != null else 0.0
	var aim_mult := 0.6
	# 高倍率狙击镜:灵敏度按 镜内FOV/基础FOV 的比例缩放,基础 FOV 改变后仍保持一致的
	# 镜内实际手感(12°镜 ≈ 0.16×);普通瞄具维持原 BF 手感曲线。
	if g != null and g.def.scope:
		var base_fov: float = float(G.settings.get("fov", 75.0))
		var scope_fov: float = g.scope_fov()
		aim_mult = clampf(tan(deg_to_rad(scope_fov) * 0.5) / maxf(tan(deg_to_rad(base_fov) * 0.5), 0.01), 0.08, 0.6)
	var sens = 0.0022 * G.settings.sensitivity * lerpf(1.0, aim_mult, ads)
	yaw -= dx * sens
	pitch -= dy * sens
	pitch = clampf(pitch, -1.45, 1.45)
	look_vel_x = dx
	look_vel_y = dy


func switch_weapon(i: int) -> void:
	if melee_active:
		_deactivate_melee(true)    # 小刀状态按切枪键:先收回再切(同槽位=仅收回)
	if i == gun_index or i >= guns.size() or not alive:
		return
	gun().holster()
	gun_index = i
	gun().equip()
	_update_body_gun()
	G.lock_target = null  # 切枪脱锁
	AudioSys.reload(1)


func damage(amount: float, attacker_pos: Vector3, attacker, def = null) -> void:
	if not alive or spawn_protect > 0 or G.state != "playing":
		return
	# 大逃杀护甲:吸收 30% 伤害(耐久 = 吸收量)
	if br_armor > 0.01 and amount > 0.0:
		var absorbed := minf(br_armor, amount * 0.3)
		br_armor -= absorbed
		amount -= absorbed
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
		_nade_arming = false
		if _nade_vm != null and is_instance_valid(_nade_vm):
			_nade_vm.visible = false
		# 死亡:视角手/枪隐藏(屏幕不再显示武器),尸体影子枪/手臂隐藏
		for gg in guns:
			if gg != null and gg.group != null and is_instance_valid(gg.group):
				gg.group.visible = false
		if gun() != null and gun().id != "rpg":
			G.effects.spawn_dropped_weapon(gun().id, pos + Vector3(0, 1.2, 0))
		if body != null and is_instance_valid(body) and body.has_meta("gun_mount"):
			var mount: Node3D = body.get_meta("gun_mount")
			for c in mount.get_children():
				if c is Node3D:
					(c as Node3D).visible = false
		if melee_active:
			_deactivate_melee(false)   # 死亡:小刀强制收回
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
	# 占武器槽的技能(毒刺/榴弹)弹药随枪械 reserve 一起补,不重置技能次数
	if not _gadget_is_weapon():
		gadget_count = gadget_max if gadget_max > 0 else int(WeaponsData.C()[class_id].gadget_count)


## 当前兵种技能是否占用武器槽(工程兵毒刺 / 突击兵榴弹发射器:按 3 切换,F 不触发)
func _gadget_is_weapon() -> bool:
	return gadget == "rpg" or gadget == "gl"


## Q 索敌:标记准星附近的敌人(BF 索敌系统)
func spot_enemy() -> void:
	if spot_cd > 0:
		return
	spot_cd = 1.5
	var g := gun()
	var aim: Basis = g.aim_basis() if g != null else G.camera.global_transform.basis
	var dir: Vector3 = -aim.z
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


## 手雷蓄力投掷(按住 G 保持蓄力,松开投出;力度随蓄力,含视角手雷动作)
var _nade_arming := false
var _nade_hold := 0.0
var _nade_vm: Node3D = null      # 手雷视角模型(vm_camera 层)
var _nade_vm_t := -1.0           # 抛掷动画计时(>=0 播放中)
var _adren_vm: Node3D = null     # 肾上腺素注射器视角模型
var _adren_t := -1.0             # 注射动画计时(>=0 播放中)
var _veh_recruit_t := 0.0          # 征召炮手节流计时
var _veh_recruit_notified := false # 已提示过队友响应


func _ensure_nade_vm() -> void:
	if _nade_vm != null and is_instance_valid(_nade_vm):
		return
	_nade_vm = Node3D.new()
	var nade_body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.032
	bm.bottom_radius = 0.032
	bm.height = 0.065
	bm.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.2)
	mat.roughness = 0.6
	nade_body.mesh = bm
	nade_body.material_override = mat
	nade_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nade_vm.add_child(nade_body)
	var fuse := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.006
	fm.bottom_radius = 0.006
	fm.height = 0.03
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.82, 0.55, 0.2)
	fuse.mesh = fm
	fuse.material_override = fmat
	fuse.position = Vector3(0, 0.047, 0)
	fuse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nade_vm.add_child(fuse)
	_nade_vm.visible = false
	G.vm_camera.add_child(_nade_vm)


## 手雷视角模型没有自身透明度属性(Node3D),透明度统一写到子级 GeometryInstance3D.transparency。
func _set_nade_vm_alpha(a: float) -> void:
	if _nade_vm == null or not is_instance_valid(_nade_vm):
		return
	for ch in _nade_vm.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).transparency = 1.0 - a


func _ensure_adren_vm() -> void:
	if _adren_vm != null and is_instance_valid(_adren_vm):
		return
	_adren_vm = Node3D.new()
	var fbody := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.012
	bm.bottom_radius = 0.012
	bm.height = 0.085
	bm.radial_segments = 8
	fbody.mesh = bm
	fbody.rotation.x = PI / 2.0
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.86, 0.92, 0.96)
	body_mat.roughness = 0.25
	body_mat.metallic = 0.4
	fbody.material_override = body_mat
	fbody.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adren_vm.add_child(fbody)
	var liquid := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.007
	lm.bottom_radius = 0.007
	lm.height = 0.045
	liquid.mesh = lm
	liquid.rotation.x = PI / 2.0
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(0.95, 0.65, 0.18)
	liquid.material_override = lmat
	liquid.position.z = 0.012
	_adren_vm.add_child(liquid)
	var needle := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0015
	nm.bottom_radius = 0.0015
	nm.height = 0.045
	needle.mesh = nm
	needle.rotation.x = PI / 2.0
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.82, 0.86, 0.9)
	nmat.metallic = 0.9
	nmat.roughness = 0.15
	needle.material_override = nmat
	needle.position.z = -0.062
	_adren_vm.add_child(needle)
	var plunger := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.006
	pm.bottom_radius = 0.006
	pm.height = 0.06
	plunger.mesh = pm
	plunger.rotation.x = PI / 2.0
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 0.25, 0.3)
	plunger.material_override = pmat
	plunger.position.z = 0.055
	_adren_vm.add_child(plunger)
	var hand := WeaponModels.build_hand(false)
	hand.scale = Vector3.ONE * 0.82
	hand.position = Vector3(0, -0.022, 0.02)
	hand.rotation = Vector3(0.15, 0.0, -1.35)
	_adren_vm.add_child(hand)
	_adren_vm.visible = false
	G.vm_camera.add_child(_adren_vm)


func _start_adren_anim() -> void:
	_ensure_adren_vm()
	_adren_t = 0.0
	_adren_vm.visible = true
	var g := gun()
	if g != null and g.group != null and is_instance_valid(g.group):
		g.group.visible = false


## 肾上腺素注射:右手从画面右侧抬起 → 刺入左胸 → 轻推注射 → 拔出收回
func _update_adren_vm(dt: float) -> void:
	if class_id != "assault":
		return
	_ensure_adren_vm()
	if _adren_t < 0.0:
		if _adren_vm.visible:
			_adren_vm.visible = false
			var g0 := gun()
			if g0 != null and g0.group != null and is_instance_valid(g0.group):
				g0.group.visible = true
		return
	_adren_t += dt
	var dur := 1.15
	var k := clampf(_adren_t / dur, 0.0, 1.0)
	var start := Vector3(0.24, -0.16, -0.28)
	var chest := Vector3(-0.14, -0.10, -0.20)
	var lpos := start
	var rot := Vector3(0.15, 0.35, 0.1)
	if k < 0.22:
		var e := k / 0.22
		lpos = start.lerp(chest, e * e * (3.0 - 2.0 * e))
		rot = rot.lerp(Vector3(-0.55, -0.9, 0.2), e)
	elif k < 0.52:
		lpos = chest + Vector3(0.0, 0.004, -0.012 * sin((k - 0.22) / 0.3 * PI))
		rot = Vector3(-0.55, -0.9, 0.2)
	elif k < 0.78:
		lpos = chest + Vector3(0.0, 0.004, -0.012)
		rot = Vector3(-0.55, -0.9, 0.2)
	else:
		var e := (k - 0.78) / 0.22
		lpos = (chest + Vector3(0.0, 0.004, -0.012)).lerp(start, e)
		rot = Vector3(-0.55, -0.9, 0.2).lerp(Vector3(0.15, 0.35, 0.1), e)
	_adren_vm.position = lpos
	_adren_vm.rotation = rot
	if k >= 1.0:
		_adren_t = -1.0
		_adren_vm.visible = false
		var g := gun()
		if g != null and g.group != null and is_instance_valid(g.group):
			g.group.visible = true


func _nade_force() -> float:
	return 0.4 + 0.6 * clampf(_nade_hold / 1.6, 0.0, 1.0)


## 蓄力/抛掷动画(每帧):蓄力时右手持雷(枪收回),松开右手直接抛出
func _update_nade_vm(dt: float) -> void:
	_ensure_nade_vm()
	var g := gun()
	if _nade_vm_t >= 0.0:
		# 抛掷动画:右手前抛+上旋+淡出(0.32s)
		_nade_vm_t += dt
		var k := clampf(_nade_vm_t / 0.32, 0.0, 1.0)
		_nade_vm.position = Vector3(0.3 - 0.25 * k, -0.1 + 0.05 * k, -0.3 - 0.35 * k)
		_nade_vm.rotation = Vector3(0.2, k * 4.5, 0.15)
		_set_nade_vm_alpha(1.0 - k)
		if _nade_vm_t >= 0.32:
			_nade_vm_t = -1.0
			_nade_vm.visible = false
			_set_nade_vm_alpha(1.0)
			if g != null and g.group != null and is_instance_valid(g.group):
				g.group.visible = true   # 枪收回恢复
		return
	if _nade_arming:
		# 蓄力:右手持雷抬起(画面右侧),枪收回
		if g != null and g.group != null and is_instance_valid(g.group) and g.group.visible:
			g.group.visible = false
		var t := clampf(_nade_hold / 1.6, 0.0, 1.0)
		_nade_vm.visible = true
		_nade_vm.position = Vector3(0.3, -0.1 + 0.12 * t, -0.3)
		_nade_vm.rotation = Vector3(0.2, -0.5, 0.1)
		_set_nade_vm_alpha(1.0)
	else:
		if _nade_vm.visible:
			_nade_vm.visible = false
			if g != null and g.group != null and is_instance_valid(g.group):
				g.group.visible = true


func throw_grenade(force := 0.4) -> void:
	if grenades <= 0 or not alive:
		AudioSys.dry_fire()
		return
	grenades -= 1
	# 抛掷弧线:力度越大抛越远、上扬越高
	var dir: Vector3 = (-G.camera.global_transform.basis.z + Vector3.UP * (0.1 + force * 0.14)).normalized()
	var p: Vector3 = G.camera.global_position + dir * (0.5 + force * 0.3)
	p.y -= 0.1
	G.effects.spawn_grenade(self, p, dir, 13.0 + force * 10.0, 2.6 + force * 2.6)
	AudioSys.reload(0)
	# 抛掷动作(视角手雷)
	_nade_arming = false
	_nade_hold = 0.0
	if _nade_vm != null and is_instance_valid(_nade_vm):
		_nade_vm_t = 0.0


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
	# TDM:团队死斗禁用全部兵种技能(F 键直接拦截,含侦察兵信标/工程兵维修/补给系;
	#      AI 侦察兵信标部署同步门控于 bot.gd _duty_recon)
	if G.mode == "tdm":
		G.hud.hint("团队死斗禁用兵种技能")
		return
	# 无人机操控中:F 直接召回(不消耗次数)
	if G.drone != null and G.drone.piloting:
		G.drone.recall("玩家手动召回")
		return
	# 工程兵:F 优先维修附近己方受损载具(不消耗技能次数)
	if class_id == "engineer" and _try_repair_vehicle():
		return
	# 占武器槽的技能(毒刺/榴弹发射器):F 不触发,提示按 3 切换
	if _gadget_is_weapon():
		G.hud.hint("按 3 切换" + (gadget_cn if gadget_cn != "" else "兵种武器"))
		return
	# 重生信标:BR 禁用(BR 的 F 键为医疗包,此为兜底门控)
	if gadget == "beacon" and G.mode == "br":
		G.hud.hint("大逃杀禁用重生信标")
		AudioSys.dry_fire()
		return
	if gadget_count <= 0:
		AudioSys.dry_fire()
		return
	match gadget:
		"beacon":
			gadget_count -= 1
			G.game.spawn_beacon(self)
		"medkit":
			gadget_count -= 1
			heal_over_time = 60
			_start_adren_anim()
			AudioSys.capture(true)
			G.hud.hint("肾上腺素注入:恢复中…")
		"ammobox":
			gadget_count -= 1
			resupply()
			AudioSys.reload(1)
			G.hud.hint("弹药已补给")
		"sensor":
			gadget_count -= 1
			G.game.spot_enemies(50, 12)
			AudioSys.capture(true)
			G.hud.hint("动态探测器已启动:敌人已标记")
		"medpack":
			gadget_count -= 1
			G.game.spawn_med_pack(self)
		"ammopack":
			gadget_count -= 1
			G.game.spawn_ammo_pack(self)
		"coverkit":
			# 掩体制造器:正前方架起半身掩体(位置被占/贴墙时不消耗次数)
			if G.game.spawn_cover(self):
				gadget_count -= 1
			else:
				AudioSys.dry_fire()
		"drone":
			if G.drone == null:
				AudioSys.dry_fire()
				G.hud.hint("无人机系统未就绪")
			elif G.drone.launch(self):
				gadget_count -= 1
			else:
				AudioSys.dry_fire()
		_:
			AudioSys.dry_fire()


## BR 短按 F:使用开局自带兵种技能(武器型技能切枪,非武器型按正常 use_gadget)
func _br_use_class_gadget() -> void:
	if _gadget_is_weapon():
		var gslot := -1
		for i in guns.size():
			if guns[i].id == gadget:
				gslot = i
				break
		if gslot >= 0:
			if gun_index == gslot:
				switch_weapon(0)
				G.hud.hint("已切回主/副武器")
			else:
				switch_weapon(gslot)
				G.hud.hint("已切换 %s(按 3/F 切换)" % gadget_cn)
		else:
			AudioSys.dry_fire()
			G.hud.hint("兵种武器未就绪")
		return
	if gadget == "beacon":
		G.hud.hint("大逃杀禁用重生信标")
		AudioSys.dry_fire()
		return
	if gadget_count <= 0:
		AudioSys.dry_fire()
		G.hud.hint("%s 次数已用完" % gadget_cn)
		return
	use_gadget()


## BR 长按 F:使用地图拾取的医疗包(与开局兵种技能互不冲突)
func _br_use_loot_medkit() -> void:
	if br_medkits > 0:
		br_medkits -= 1
		heal(50)
		AudioSys.capture(true)
		G.hud.hint("医疗包:恢复 50 生命(剩余 %d)" % br_medkits)
	else:
		AudioSys.dry_fire()
		G.hud.hint("没有医疗包 — 搜索物资获取(长按 F 使用)")


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
	var npc_driver: bool = v.driver != null and v.driver != self
	var _npc_gunner: bool = v.gunner != null and v.gunner != self  # 预留:乘客/司机区分提示
	if v.type == "jeep" and npc_driver:
		# 吉普司机在位:玩家坐乘客位(不顶司机下车),强制第一人称,持个人武器开火;
		# 乘客位被 NPC 占时顶替乘客(乘客无操作价值,NPC 由座位兜底下车),司机必须保留
		if v.gunner != null and v.gunner != self:
			print("[CREW] 玩家上车顶替吉普乘客位")
		if melee_active:
			_deactivate_melee(false)   # 上车:小刀强制收回(载具互斥)
		if motion != null:
			motion.reset(Vector3.ZERO)  # 车上由 VehicleCameraController 接管,清掉步战运动残留
		vehicle = v
		v.gunner = self
		_veh_crew = 1
		_veh_station = 1
		_veh_fp_passenger = true
		yaw = 0
		pitch = 0  # 相对载具的观察角
		_veh_tp = false       # 乘客位强制第一人称
		_passenger_gun = false
		_veh_scope = false
		_veh_optic_mode = 0
		night_vision = false
		G.effects.set_night_vision(false)
		if v.camera_ctl != null:
			v.camera_ctl.reset()       # 重置第三人称平滑(防瞬移插值)
			v.camera_ctl.set_gunner_mode(false)  # 乘客不驱动炮塔
			v.camera_ctl.set_station(FirstPersonVehicleController.Station.GUNNER)  # FP 眼位=吉普右座
			v.camera_ctl.set_optic_mode(0)
		# 不收枪:_update_passenger_gun 首帧自动 equip 个人武器
		AudioSys.engine_start(v.type)
		G.hud.hint("乘客位(第一人称) · 左键开火 · 右键瞄准 · R 换弹 · E 下车")
		return
	if melee_active:
		_deactivate_melee(false)   # 上车:小刀强制收回(载具互斥)
	if motion != null:
		motion.reset(Vector3.ZERO)  # 车上由 VehicleCameraController 接管,清掉步战运动残留
	vehicle = v
	# 战地式座位:上车即炮手位(驾驶+开炮一体,顶替在位 NPC,NPC 由各自 update 自动让位);
	# 观察位由 F 键切换。默认第三人称,唯一第一人称 = 右键 ADS 目镜。
	if v.driver != null and v.driver != self:
		print("[CREW] 玩家上车顶替驾驶位")
	if v.gunner != null and v.gunner != self:
		print("[CREW] 玩家上车顶替炮手位")
	v.driver = self
	v.gunner = self
	_veh_crew = 0
	yaw = 0
	pitch = 0  # 相对载具的观察角
	_veh_tp = true
	_passenger_gun = false
	_veh_fp_passenger = false
	_veh_station = 0
	_veh_scope = false
	_veh_optic_mode = 0
	night_vision = false
	G.effects.set_night_vision(false)
	if v.camera_ctl != null:
		v.camera_ctl.reset()       # 重置第三人称平滑(防瞬移插值)
		v.camera_ctl.set_gunner_mode(true)
		v.camera_ctl.set_station(FirstPersonVehicleController.Station.GUNNER)
		v.camera_ctl.set_optic_mode(0)
	for g in guns:
		g.holster()
	AudioSys.engine_start(v.type)
	if v.has_turret():
		var w_name: String = "主炮" if v.is_tank() else v.def.weapon["cn"]
		G.hud.hint("炮手位:" + w_name + " · 左键开火 · 右键瞄准镜 · F 观察位 · E 下车")
	else:
		G.hud.hint("驾驶位:W/S 油门刹车 · A/D 转向 · F 观察位 · E 下车")


## 上车时征召最近空闲同队 bot 补齐空缺乘员位:
## 玩家驾驶 → 召炮手;玩家坐炮手 → 召驾驶员(半径 150m;在载具中的 bot 不征召)
func _call_gunner_crew(v) -> void:
	if not v.has_turret() or G.bots.is_empty():
		return
	var need_driver: bool = v.driver == null and v.gunner == self
	var need_gunner: bool = v.gunner == null and v.driver == self
	if not need_driver and not need_gunner:
		return
	var best = null
	var best_d := 150.0
	for b in G.bots:
		if not b.alive or b.team != team or b.vehicle != null:
			continue
		var d: float = b.pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return
	if need_driver:
		best.board_vehicle_as_driver(v)
	else:
		best.board_vehicle(v)
	if not _veh_recruit_notified:
		_veh_recruit_notified = true
		G.hud.hint("队友已响应,正在登车担任" + ("驾驶员" if need_driver else "炮手"))


func exit_vehicle(silent := false) -> void:
	var v = vehicle
	if v == null:
		return
	if v.driver == self:
		v.driver = null
	if v.gunner == self:
		v.gunner = null
	vehicle = null
	_passenger_gun = false
	_veh_fp_passenger = false
	_veh_station = 0
	_veh_optic_mode = 0
	if v.camera_ctl != null:
		v.camera_ctl.set_gunner_mode(false)
		v.camera_ctl.set_station(0)
		v.camera_ctl.deactivate_optic_modes()
	if veh_body != null:
		veh_body.visible = false
	_veh_scope = false
	if G.hud != null and G.hud.has_method("set_veh_scope"):
		G.hud.set_veh_scope(false)
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
	if motion != null:
		motion.reset(vel)  # 下车继承速度直接作为运动系统初始输入,避免首帧加速度尖峰
	if not silent:
		gun().equip()
	else:
		for g in guns:
			g.holster()


## 第三人称载具乘员模型(吉普坐姿 / 炮塔探身;仅第三人称时显示)
func _update_veh_body(v) -> void:
	if veh_body == null:
		return
	if not _veh_tp or v.type != "jeep":
		veh_body.visible = false  # 仅侦察吉普显示玩家第三人称模型
		return
	veh_body.visible = true
	# GLB 骨骼乘员:停动画 + 骨骼坐姿(同 bot 乘员);旧盒子 meta 仅作回退兼容
	var vskel: Skeleton3D = veh_body.get_meta("skel", null)
	var vanim: AnimationPlayer = veh_body.get_meta("anim", null)
	var leg_l: Node3D = veh_body.get_meta("leg_l", null)
	var leg_l_knee: Node3D = veh_body.get_meta("leg_l_knee", null)
	var leg_r: Node3D = veh_body.get_meta("leg_r", null)
	var leg_r_knee: Node3D = veh_body.get_meta("leg_r_knee", null)
	var rig: Node3D = veh_body.get_meta("rig", null)
	veh_body.rotation_order = EULER_ORDER_YXZ
	# 吉普:臀部落座(模型原点在脚底,座椅面高约 1.08,下沉 1.32 防站穿车顶)
	# 副驾驶位用乘客锚点(右前座),驾驶位用座位锚点(左前座)
	var seat: Vector3 = v.passenger_world() if _veh_crew == 1 else v.seat_world()
	veh_body.position = Vector3(seat.x, seat.y - 1.32, seat.z)
	veh_body.rotation = Vector3(0, v.yaw, 0)
	if vskel != null:
		if vanim != null:
			vanim.stop()
		for bn in ["ThighL", "ThighR"]:
			var bi := vskel.find_bone(bn)
			if bi >= 0:
				vskel.set_bone_pose_rotation(bi, Quaternion(Vector3(1, 0, 0), 1.35))
		for bn in ["ShinL", "ShinR"]:
			var bi2 := vskel.find_bone(bn)
			if bi2 >= 0:
				vskel.set_bone_pose_rotation(bi2, Quaternion(Vector3(1, 0, 0), -1.35))
	elif leg_l != null:
		leg_l.visible = true
		leg_r.visible = true
		leg_l.rotation.x = 1.35
		leg_r.rotation.x = 1.35
		leg_l_knee.rotation.x = -1.35
		leg_r_knee.rotation.x = -1.35
	if rig != null:
		rig.rotation.x = 0.1


## 乘员岗位占用(战地式):0=炮手位(驾驶+开炮一体,占 driver+gunner)
## 1=观察位(纯第三人称旁观;防空车配机枪)。玩家占用时顶替在位 NPC。
func _take_vehicle_station(v, s: int) -> void:
	var prev_crew := _veh_crew
	if s == 0:
		# 吉普驾驶员由 NPC 担任时不可抢占(F 换岗守卫),保持乘客位
		if v.type == "jeep" and v.driver != null and v.driver != self:
			G.hud.hint("驾驶员已就位")
			return
		if v.driver != self:
			print("[CREW-F] 玩家接管炮手位(驾驶+开炮)")
		v.driver = self
		v.gunner = self
		_veh_crew = 0
	else:
		if v.driver == self:
			v.driver = null
		if v.gunner == self:
			v.gunner = null
		_veh_crew = 1
		_veh_scope = false
		if G.hud != null and G.hud.has_method("set_veh_scope"):
			G.hud.set_veh_scope(false)
	_veh_station = s
	if prev_crew != _veh_crew and v.camera_ctl != null:
		v.camera_ctl.set_station(FirstPersonVehicleController.Station.GUNNER if _veh_crew == 0
			else FirstPersonVehicleController.Station.OBSERVER)


## F 键换岗:炮手位 ↔ 观察位
func _cycle_vehicle_station(v) -> void:
	_take_vehicle_station(v, 1 if _veh_crew == 0 else 0)


func update_vehicle(dt: float) -> void:
	var v = vehicle
	var input = G.input_sys
	body.visible = false  # 驾驶时隐藏下半身
	_update_veh_body(v)
	if Input.is_action_just_pressed("interact"):
		exit_vehicle()
		return
	# F 换岗:炮手位(驾驶+开炮) ↔ 观察位
	if Input.is_action_just_pressed("gadget"):
		_cycle_vehicle_station(v)
	var cam := camera()
	pos = Vector3(v.pos.x, v.pos.y, v.pos.z)  # 供 AI 瞄准/小地图
	var ctl = v.camera_ctl
	if ctl == null:
		return
	# 战地式视角:默认第三人称;唯一第一人称 = 炮手位右键 ADS 目镜
	_veh_tp = true
	cam.rotation_order = EULER_ORDER_YXZ
	if v.has_turret():
		# ADS:右键按住进入目镜(第一人称,藏炮管只留分划);松开回第三人称
		_veh_scope = Input.is_action_pressed("ads") and _veh_crew == 0
		ctl.view = FirstPersonVehicleController.VehView.FP_OPTIC if _veh_scope else FirstPersonVehicleController.VehView.THIRD_PERSON
		if _veh_scope:
			ctl.set_optic_mode(_veh_optic_mode)
		else:
			ctl.set_optic_mode(FirstPersonVehicleController.OpticMode.DAY)
		if Input.is_action_just_pressed("nightvision") and _veh_scope:
			_veh_optic_mode = ctl.cycle_optic_mode()
			match _veh_optic_mode:
				FirstPersonVehicleController.OpticMode.THERMAL:
					G.hud.hint("热成像开启 — 白光/热像/夜视循环")
				FirstPersonVehicleController.OpticMode.NIGHT:
					G.hud.hint("微光夜视开启 — 白光/热像/夜视循环")
				_:
					G.hud.hint("白光观瞄 — 白光/热像/夜视循环")
		if G.hud != null and G.hud.has_method("set_veh_scope"):
			G.hud.set_veh_scope(_veh_scope)
		if G.hud != null and G.hud.has_method("set_veh_optic_mode"):
			G.hud.set_veh_optic_mode(_veh_optic_mode if _veh_scope else 0)
		if _veh_crew == 0:
			var w_name: String = "主炮" if v.is_tank() else v.def.weapon["cn"]
			var reload_hint: String = ("装填 " + str(ceil(v.cannon_t)) + "s · " if v.cannon_t > 0 and v.is_tank() else "")
			G.hud.hint("炮手位:" + w_name + reload_hint + "左键开火 · 右键瞄准镜 · F 观察位 · E 下车")
		else:
			# 观察位:纯第三人称旁观;防空车配一挺可开火的机枪
			if v.type == "aa":
				_update_passenger_gun(dt)
				G.hud.hint("观察位 · 车顶机枪:左键开火 · R 换弹 · F 回炮手位 · E 下车")
			else:
				if _passenger_gun:
					_passenger_gun = false
					if gun() != null:
						gun().holster()
				G.hud.hint("观察位 · F 回炮手位 · E 下车")
	else:
		# 吉普:主位=驾驶(无车载武器),乘客位=个人武器(NPC 司机在位时强制第一人称)
		ctl.set_optic_mode(FirstPersonVehicleController.OpticMode.DAY)
		if _veh_crew == 1:
			_veh_tp = not _veh_fp_passenger
			ctl.view = (FirstPersonVehicleController.VehView.FP_DRIVER if _veh_fp_passenger
				else FirstPersonVehicleController.VehView.THIRD_PERSON)  # FP_DRIVER 视图按 station 取锚点:GUNNER=吉普右座
			_update_passenger_gun(dt)
			G.hud.hint("乘客位" + ("(第一人称)" if _veh_fp_passenger else "") + " · 左键开火 · R 换弹 · F 换驾驶位 · E 下车")
		else:
			_veh_tp = true
			ctl.view = FirstPersonVehicleController.VehView.THIRD_PERSON
			if _passenger_gun:
				_passenger_gun = false
				if gun() != null:
					gun().holster()
			G.hud.hint("驾驶位:W/S 油门刹车 · A/D 转向 · F 乘客位 · E 下车")
	# 鼠标:第三人称=环绕观察(炮塔/机枪跟随视线);ADS 目镜/乘客位第一人称=车内自由视角
	var md: Vector2 = input.consume_mouse()
	if _veh_scope or _veh_fp_passenger:
		ctl.apply_look(md.x, md.y)
	else:
		ctl.apply_tp_orbit(md.x, md.y)
	# 观察位/乘客位持枪后坐作用于观察角(复用玩家后坐衰减)
	if _passenger_gun:
		if _veh_fp_passenger:
			ctl.look_pitch = clampf(ctl.look_pitch - (recoil_pitch + cam_kick_pitch),
				FirstPersonVehicleController.LOOK_PITCH_DOWN, FirstPersonVehicleController.LOOK_PITCH_UP)
			ctl.look_yaw = clampf(ctl.look_yaw + recoil_yaw + cam_kick_yaw,
				-FirstPersonVehicleController.LOOK_YAW_MAX, FirstPersonVehicleController.LOOK_YAW_MAX)
		else:
			ctl._tp_orbit_pitch = clampf(ctl._tp_orbit_pitch - (recoil_pitch + cam_kick_pitch),
				-FirstPersonVehicleController.LOOK_PITCH_UP, -FirstPersonVehicleController.LOOK_PITCH_DOWN)
			ctl.look_yaw = clampf(ctl.look_yaw + recoil_yaw + cam_kick_yaw,
				-FirstPersonVehicleController.LOOK_YAW_MAX, FirstPersonVehicleController.LOOK_YAW_MAX)
	recoil_pitch = Utils.damp(recoil_pitch, 0, 3.4, dt)
	recoil_yaw = Utils.damp(recoil_yaw, 0, 9, dt)
	cam_kick_pitch = Utils.damp(cam_kick_pitch, 0, 13, dt)
	cam_kick_yaw = Utils.damp(cam_kick_yaw, 0, 13, dt)
	ctl.update(dt)
	# 定期征召乘员:玩家驾驶缺炮手 → 召炮手;玩家坐炮手/车长缺驾驶 → 召驾驶员(每 3s 重试)
	if v.has_turret():
		var crew_missing := false
		if _veh_crew == 0:
			crew_missing = v.gunner == null
		else:
			crew_missing = v.driver == null
		if crew_missing:
			_veh_recruit_t -= dt
			if _veh_recruit_t <= 0:
				_veh_recruit_t = 3.0
				_call_crew_mates(v)
	# FOV:载具第一人称由 FirstPersonVehicleController 按岗位配置(驾驶 86°/炮镜 40~46°);
	# 吉普副驾驶持枪开镜按武器 zoom_fov 缩放;高倍率狙击镜镜内倍率由 OpticScopeSystem 独立渲染。
	var fov_target: float = ctl.target_fov()
	if _veh_tp:
		fov_target = float(G.settings.get("fov", 75.0))
	elif _passenger_gun and gun() != null:
		if gun().scope_sight():
			fov_target = FirstPersonVehicleController.FP_FOV
		else:
			fov_target = lerpf(FirstPersonVehicleController.FP_FOV, gun().def.zoom_fov, gun().ads_amount)
	if absf(cam.fov - fov_target) > 0.05:
		cam.fov = Utils.damp(cam.fov, fov_target, 10, dt)


## Z 键召唤队友补齐乘员位:玩家在驾驶位→召炮手/乘客;玩家在炮手/乘客位→召驾驶员
## 招募 150m 内最近的空间闲同队 bot 登车(步行入车,复用现有 board_vehicle 机制)
func _call_crew_mates(v) -> void:
	if v == null or v.dead:
		return
	var need_driver: bool = v.driver == null or v.driver == self
	var need_gunner: bool = v.gunner == null or v.gunner == self
	if not need_driver and not need_gunner:
		G.hud.hint("乘员位已满")
		return
	var recruited := 0
	for b in G.bots:
		if b == null or not b.alive or b.team != team or b.vehicle != null:
			continue
		if b.pos.distance_to(pos) > 150.0:
			continue
		if need_driver and v.driver == null:
			b.board_vehicle_as_driver(v)
			recruited += 1
		elif need_gunner and v.gunner == null:
			b.board_vehicle(v)
			recruited += 1
		if recruited >= 2 or (recruited >= 1 and (not need_driver or not need_gunner)):
			break
	if recruited > 0:
		G.hud.hint("已召唤 %d 名队友登车" % recruited)
		AudioSys.reload(1)
	else:
		G.hud.hint("附近没有可召唤的队友")
		AudioSys.dry_fire()


## 吉普副驾驶持枪:显示个人武器视角模型,左键开火 / 右键开镜 / R 换弹 / B 射速 / 切枪
## 射击结算复用 Gun 完整管线(准心=观察方向,枪口=相机位置,含后坐/散布/曳光/命中反馈)
func _update_passenger_gun(dt: float) -> void:
	var g := gun()
	var want: bool = g != null
	if want != _passenger_gun:
		_passenger_gun = want
		if g != null:
			if want:
				g.equip()
			else:
				g.holster()
	if not want:
		return
	var input = G.input_sys
	g.trigger_held = Input.is_action_pressed("fire")
	g.ads_held = Input.is_action_pressed("ads")
	if Input.is_action_just_pressed("reload"):
		g.reload()
	if Input.is_action_just_pressed("fire_mode"):
		g.toggle_fire_mode()
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"):
		switch_weapon(2)
	var wheel = input.consume_wheel()
	if wheel != 0:
		if not _wheel_to_scope_zoom(wheel):
			switch_weapon((gun_index + (1 if wheel > 0 else -1) + guns.size()) % guns.size())
	g.update(dt)
	# 乘客位第三人称:只走射击结算管线,枪模隐藏(避免悬空枪挡屏);
	# 乘客位第一人称:显示完整视角模型(个人武器在车内可见可开火)
	if g.group != null:
		g.group.visible = _veh_fp_passenger


## 制导瞄准镜 UI 使用的锁定进度(0~1)
func missile_lock_progress() -> float:
	var g := gun()
	if g == null or g.id != "rpg":
		return 0.0
	return clampf(_lock_t, 0.0, 1.0)


## 火箭筒开镜时滚轮改变 CLU 放大倍率(0×/2×/4×)而不是切换武器。
## 返回 true 表示滚轮已被瞄具消费;未开镜/非火箭筒时返回 false 走原切枪逻辑。
func _wheel_to_scope_zoom(wheel: int) -> bool:
	if melee_active:
		return false
	var g := gun()
	if g == null or g.id != "rpg" or not g.ads_held or g.ads_amount < 0.3:
		return false
	return g.cycle_zoom(wheel)


func update_player(dt: float) -> void:
	if not alive:
		return
	var input = G.input_sys
	spawn_protect = maxf(0, spawn_protect - dt)
	# 无人侦察机操控中:输入全部交给无人机,本体原地待机(仍会被敌人打中)。
	# 相机由 ReconDroneSystem 的独立相机接管,这里不再推进步战视角/移动/武器逻辑。
	if G.drone != null and G.drone.piloting:
		if Input.is_action_just_pressed("gadget"):
			G.drone.recall("玩家手动召回")
		else:
			return
	# 驾驶模式
	if vehicle != null:
		update_vehicle(dt)
		return
	# 大逃杀跳伞状态机(飞机/自由落体/开伞;物理归 GameMode_BR,复用视角与输入)
	if G.br != null and G.br.has_method("player_jump_active") and G.br.player_jump_active():
		if melee_active:
			_deactivate_melee(false)   # 跳伞:小刀强制收回(跳伞互斥)
		G.br.update_player_jump(self, dt)
		return

	# ---- 视角 ----
	var md: Vector2 = input.consume_mouse()
	apply_look(md.x, md.y)
	if motion != null:
		motion.input_mouse(md.x, md.y)  # 原始 Delta 进 Sway(apply_look 已扣灵敏度)
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
	# 枪械重量:配件(长枪管/重型枪托/弹鼓等)降低移动速度
	speed *= gun().mobility_mult()

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
		if motion != null:
			motion.notify_jump()
	vel.y -= 13.5 * dt
	pos.x += vel.x * dt
	pos.z += vel.z * dt
	pos.y += vel.y * dt
	var gh: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	if pos.y <= gh:
		var fall_impact := -vel.y
		pos.y = gh
		vel.y = 0
		on_ground = true
		if motion != null and fall_impact > 1.0:
			motion.notify_landing(fall_impact)
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

	# ---- 附近载具:按 E 上车(驾驶位优先,满员不可上) ----
	for v in G.vehicles:
		if not v.dead and (v.driver == null or v.gunner == null) \
				and Vector2(v.pos.x - pos.x, v.pos.z - pos.z).length() < 3.4:
			var seat_txt := ("驾驶" if v.driver == null else ("炮手" if v.has_turret() else "乘客"))
			G.hud.hint("按 E 上车(坐" + seat_txt + "位) " + v.def.vehicle_name)
			if Input.is_action_just_pressed("interact"):
				enter_vehicle(v)
				return
			break

	# ---- 大逃杀:物资拾取提示(靠近 + 按 E;拾取逻辑在 GameMode_BR) ----
	if G.mode == "br" and G.br != null and G.br.has_method("pickup_hint_nearest"):
		var hit = G.br.pickup_hint_nearest(pos, 2.2)
		if hit != null:
			G.hud.hint("按 E 拾取 " + str(hit["label"]))
			if Input.is_action_just_pressed("interact"):
				G.br.try_player_pickup(self)

	# ---- 近战小刀状态机(H 长按/弹尽自动/挥击/收回) ----
	_update_melee(dt)
	# ---- 程序化 Camera + Weapon Motion 主更新(必须在 g.update 之前,相机/枪械共用同一输入) ----
	if motion != null:
		motion.update(dt)
		bob_y = motion.stride_phase()   # 腿/脚动画继续与步距相位同步
	var g := gun()
	if not melee_active:
		# ---- 武器操作 ----
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
		if Input.is_action_just_pressed("fire_mode"):
			g.toggle_fire_mode()
		if Input.is_action_just_pressed("inspect"):
			g.try_inspect()
		if Input.is_action_just_pressed("weapon_1"):
			switch_weapon(0)
		if Input.is_action_just_pressed("weapon_2"):
			switch_weapon(1)
		if Input.is_action_just_pressed("weapon_3"):
			switch_weapon(2)
		var wheel = input.consume_wheel()
		if wheel != 0:
			# 火箭筒开镜:滚轮调 CLU 倍率(0×/2×/4×);其余情况仍是滚轮切枪
			if not _wheel_to_scope_zoom(wheel):
				var i := (gun_index + (1 if wheel > 0 else -1) + guns.size()) % guns.size()
				switch_weapon(i)
		# 手雷蓄力:按住 G 保持(抬臂蓄力),松开投出;力度随蓄力
		if Input.is_action_just_pressed("grenade"):
			if grenades > 0 and alive:
				_nade_arming = true
				_nade_hold = 0.0
				_ensure_nade_vm()
			else:
				AudioSys.dry_fire()
		elif _nade_arming and Input.is_action_pressed("grenade"):
			_nade_hold += dt
			# 蓄力提示(节流)
			if _nade_hold > 0.15 and fmod(_nade_hold, 0.35) < dt:
				G.hud.hint("松开 G 投掷 · 力度 %d%%" % int(_nade_force() * 100))
		elif _nade_arming and Input.is_action_just_released("grenade"):
			throw_grenade(_nade_force())
		if Input.is_action_just_pressed("at_grenade"):
			throw_at_grenade()
		if Input.is_action_just_pressed("at_mine"):
			place_at_mine()
		if Input.is_action_just_pressed("gadget"):
			_br_f_hold = 0.0
		elif Input.is_action_pressed("gadget") and G.mode == "br":
			_br_f_hold += dt
		if Input.is_action_just_released("gadget"):
			if G.mode == "br":
				# 大逃杀:短按 F = 开局自带兵种技能;长按 F = 使用地图拾取的医疗包
				if _br_f_hold < 0.22:
					_br_use_class_gadget()
				else:
					_br_use_loot_medkit()
			else:
				use_gadget()
			_br_f_hold = 0.0
		if Input.is_action_just_pressed("spot"):
			spot_enemy()
		if Input.is_action_just_pressed("nightvision"):
			_toggle_night_vision()
		# 连杀奖励已全局取消:按键 4/5(呼叫 UAV/炮火支援)入口一并移除
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
					G.hud.hint("毒刺导弹已锁定 — 开火!")
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
		# 手雷蓄力/抛掷动作(视角模型)
		if not _nade_arming and _nade_vm_t < 0.0 and melee_active:
			pass
		_update_nade_vm(dt)
		_update_adren_vm(dt)
	else:
		# 小刀状态:左键挥击;R/切枪键/滚轮收回
		if melee != null:
			melee.update(dt)
		if Input.is_action_just_pressed("fire"):
			if melee != null:
				melee.try_swing()
		if Input.is_action_just_pressed("reload"):
			_deactivate_melee(true)
		if Input.is_action_just_pressed("weapon_1"):
			switch_weapon(0)
		if Input.is_action_just_pressed("weapon_2"):
			switch_weapon(1)
		if Input.is_action_just_pressed("weapon_3"):
			switch_weapon(2)
		var wheel = input.consume_wheel()
		if wheel != 0:
			switch_weapon((gun_index + (1 if wheel > 0 else -1) + guns.size()) % guns.size())

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
	# ---- Camera Base -> Breathing -> Movement Bob -> Inertia -> Recoil 逐层合成 ----
	# Bob/呼吸/惯性/落地冲量全部由 FirstPersonMotionSystem 输出;这里只做:
	#   1) 基础位置 + 本地空间偏移(随相机朝向变换)
	#   2) 基础朝向 + 后坐/换弹/压制/滑铲 + 程序化旋转增量
	var cam := camera()
	cam.rotation_order = EULER_ORDER_YXZ
	# 换弹镜头反馈兜底衰减:枪械被收起(近战/载具)时控制器不更新,这里确保镜头归零不残留
	if not g.reloading:
		reload_cam_pitch = Utils.damp(reload_cam_pitch, 0.0, 10.0, dt)
		reload_cam_yaw = Utils.damp(reload_cam_yaw, 0.0, 10.0, dt)
		reload_cam_roll = Utils.damp(reload_cam_roll, 0.0, 10.0, dt)
	# 压制效果:被压制时准星抖动(开镜大幅减免)
	var sup_j := clampf(suppression, 0, 1) * 0.0032 * (1.0 - g.ads_amount * 0.65)
	var jt: float = G.time
	var motion_rot := motion.camera_rotation() if motion != null else Vector3.ZERO
	var motion_pos := motion.camera_position() if motion != null else Vector3.ZERO
	cam.rotation.y = yaw + recoil_yaw + cam_kick_yaw + reload_cam_yaw + g.inspect_cam_yaw + G.effects.shake_yaw + sin(jt * 31.0) * sup_j + motion_rot.y
	cam.rotation.x = pitch + recoil_pitch + cam_kick_pitch + reload_cam_pitch + g.inspect_cam_pitch + G.effects.shake_pitch + cos(jt * 27.0 + 1.4) * sup_j + motion_rot.x
	# 滑铲相机侧倾:快速压入,干净回正
	_slide_roll = Utils.damp(_slide_roll, -0.1 if slide_t > 0 else 0.0, 16.0 if slide_t > 0 else 10.0, dt)
	cam.rotation.z = recoil_yaw * 0.3 + _slide_roll + reload_cam_roll + g.inspect_cam_roll + motion_rot.z
	# 位置 = 眼位 + 相机局部空间偏移;偏移随相机 basis 旋转,保证与屏幕上下左右一致
	var cam_base := Vector3(pos.x, pos.y + eye_height, pos.z)
	cam.global_position = cam_base + cam.global_transform.basis * motion_pos
	# FOV:冲刺 +,滑铲瞬时冲击(随滑铲进程衰减)。
	# 普通武器继续原有全屏 ADS 缩放(55 机瞄 / 50 红点 / 28 低倍镜);
	# 高倍率狙击镜主相机只做轻微镜外缩放(约 -8°),避免夸张数字放大,
	# 镜内高倍率视野由 OpticScopeSystem 独立相机渲染。
	var base_fov: float = G.settings.fov + sprint_amount * 6 + (4 if tac_sprint > 0 else 0) + 7.0 * clampf(slide_t / 0.7, 0.0, 1.0)
	var target_fov: float
	if g.scope_sight():
		target_fov = lerpf(base_fov, maxf(base_fov - 8.0, 55.0), g.ads_amount)
	else:
		target_fov = lerpf(base_fov, g.def.zoom_fov, g.ads_amount)
	if absf(cam.fov - target_fov) > 0.05:
		cam.fov = Utils.damp(cam.fov, target_fov, 18, dt)

	# ---- 下半身同步(骨骼 GLB 版:真实腿部 + 人形阴影) ----
	body.visible = true
	body.position = pos
	_prone_amt = Utils.damp(_prone_amt, 1.0 if prone else 0.0, 8, dt)
	# 趴下:身体整体后移让趴平后的头回到原眼位下方(Prone 动画自身把身体铺平,
	# 不再绕脚轴刚体转体——旧版"上半身硬抬 45°枪杵地"已废弃)
	# 旧值 1.35 按悬空趴姿调的;location 轴修复后 Prone 实测头部水平偏移 0.55,留 0.05 余量
	var back_off := lerpf(0.2, 0.6, _prone_amt)
	body.position.x += sin(yaw) * back_off
	body.position.z += cos(yaw) * back_off
	body.position.y -= _prone_amt * 0.05
	body.rotation.y = yaw
	body.rotation.x = 0
	# 动画:Prone(贴地趴) / Crouch(屈膝战斗蹲) / Run / Walk / Idle,步频随速度
	# 瞄准俯仰随视线(AimPitch 只带手臂+枪;趴姿枪口由动画压低,代码只做视线微调)
	var skel: Skeleton3D = body.get_meta("skel") if body.has_meta("skel") else null
	var panim: AnimationPlayer = body.get_meta("anim") if body.has_meta("anim") else null
	if panim != null:
		var want := "Idle"
		var ss := 1.0
		if _prone_amt > 0.5:
			# 匍匐爬行:趴姿 + 移动 → ProneCrawl(用户实测:趴着滑行保持静止趴姿很怪)
			if h_speed > 0.4:
				want = "ProneCrawl"; ss = clampf(h_speed / 1.3, 0.6, 1.4)
			else:
				want = "Prone"
		elif crouched or slide_t > 0:
			# 蹲走:蹲姿 + 移动 → CrouchWalk
			if h_speed > 0.6:
				want = "CrouchWalk"; ss = clampf(h_speed / 2.8, 0.6, 1.3)
			else:
				want = "Crouch"
		elif h_speed > 4.4:
			want = "Run"; ss = clampf(h_speed / 5.8, 0.7, 1.5)
		elif h_speed > 0.6:
			want = "Walk"; ss = clampf(h_speed / 4.2, 0.5, 1.5)
		if not panim.has_animation(want):
			# 兜底:旧 GLB 无步态片回退静态姿态
			want = "Prone" if _prone_amt > 0.5 else ("Crouch" if (crouched or slide_t > 0) else "Idle")
			ss = 1.0
		if panim.current_animation != want:
			panim.play(want, 0.25)
		panim.speed_scale = ss
	if skel != null:
		var ai := skel.find_bone("AimPitch")
		if ai >= 0:
			skel.set_bone_pose_rotation(ai, Quaternion(Vector3(1, 0, 0), clampf(pitch, -0.6, 0.6)))


# ============ 近战小刀(全模式:弹尽自动 / H 长按 / 左键挥击) ============

func _ensure_melee() -> void:
	if melee == null:
		melee = Melee.new(self)
		melee.holster()


## 呼出小刀(弹尽自动 / H 长按);载具/跳伞/死亡时禁止
func _activate_melee(auto := false) -> void:
	if melee_active or not alive or vehicle != null:
		return
	if G.br != null and G.br.has_method("player_jump_active") and G.br.player_jump_active():
		return
	_nade_arming = false
	_nade_hold = 0.0
	_ensure_melee()
	_melee_last_gun = gun_index
	_melee_auto = auto
	if gun() != null:
		gun().holster()
	melee_active = true
	melee.equip()
	if auto:
		if G.hud != null and G.hud.has_method("hint"):
			G.hud.hint("弹药耗尽 — 已切换近战小刀")
		print("[MELEE] 弹药耗尽 — 自动切换近战小刀")


## 收回小刀(restore_gun: 切回上次枪槽)
func _deactivate_melee(restore_gun: bool) -> void:
	if not melee_active:
		return
	melee_active = false
	_melee_auto = false
	if melee != null:
		melee.holster()
	if restore_gun and not guns.is_empty():
		gun_index = clampi(_melee_last_gun, 0, guns.size() - 1)
		gun().equip()


## 弹尽自动切刀 / 获弹自动收回(H 长按 0.4s 呼出/收回,短按不触发)
func _update_melee(dt: float) -> void:
	var h_held := Input.is_action_pressed("melee")
	if h_held:
		_melee_hold_t += dt
		if not _melee_hold_fired and _melee_hold_t >= 0.4:
			_melee_hold_fired = true
			if melee_active:
				_deactivate_melee(true)
				if G.hud != null and G.hud.has_method("hint"):
					G.hud.hint("小刀收回 — 切回主武器")
				print("[MELEE] H 长按收回")
			else:
				_activate_melee()
	else:
		_melee_hold_t = 0
		_melee_hold_fired = false
	# 弹尽自动切换 / 获弹自动收回(节流 0.25s,避免每帧开销)
	_melee_check_t -= dt
	if _melee_check_t > 0:
		return
	_melee_check_t = 0.25
	var empty_now := _all_guns_empty()
	if melee_active:
		if _melee_auto:
			var refill := -1
			if _melee_last_gun < guns.size() \
					and (guns[_melee_last_gun].ammo > 0 or guns[_melee_last_gun].reserve > 0):
				refill = _melee_last_gun
			else:
				refill = _any_gun_ready()
			if refill >= 0:
				_deactivate_melee(true)
				if G.hud != null and G.hud.has_method("hint"):
					G.hud.hint("弹药已补充 — 切回武器")
				print("[MELEE] 弹药已补充 — 自动切回武器")
	elif empty_now and not _melee_prev_empty and alive and vehicle == null \
			and not (G.br != null and G.br.has_method("player_jump_active") and G.br.player_jump_active()):
		# 仅"转入空弹"瞬间自动切刀:H 手动收回后保持枪械,不再弹回
		_activate_melee(true)
	_melee_prev_empty = empty_now


## 所有持有武器(主+副)弹药耗尽
func _all_guns_empty() -> bool:
	for g in guns:
		if g.ammo > 0 or g.reserve > 0:
			return false
	return true


## 返回第一把有弹药(弹匣或备弹)的枪槽,-1 = 全空
func _any_gun_ready() -> int:
	for i in guns.size():
		if guns[i].ammo > 0 or guns[i].reserve > 0:
			return i
	return -1


# ============ 大逃杀(BR):背包/拾取 ============

## 登机时清空装备:保留一把基础手枪 + 当前兵种技能武器(gl/rpg),
## 非武器类兵种道具(gadget_count)在开局即满,不需要进图捡。
## 时序注意:被保留手枪的 group 绝不能 queue_free(帧末会被真正销毁),否则下一帧
## gun.update 访问已释放节点(gun.gd:496 "previously freed" 报错根因)
func br_strip_inventory() -> void:
	if melee_active:
		_deactivate_melee(false)   # 登机清装:小刀强制收回
	var keep: Gun = null
	var keep_gadget: Gun = null
	for g in guns:
		if keep == null and g.def.kind == "pistol":
			keep = g
		elif _gadget_is_weapon() and g.id == gadget:
			keep_gadget = g
	for g in guns:
		if is_same(g, keep) or is_same(g, keep_gadget) or g.group == null or not is_instance_valid(g.group):
			continue
		G.vm_camera.remove_child(g.group)
		g.group.queue_free()
	guns = []
	if keep != null and keep.group != null and is_instance_valid(keep.group):
		if keep.group.get_parent() != G.vm_camera:
			G.vm_camera.add_child(keep.group)
		guns.append(keep)
	if keep_gadget != null and keep_gadget.group != null and is_instance_valid(keep_gadget.group):
		if keep_gadget.group.get_parent() != G.vm_camera:
			G.vm_camera.add_child(keep_gadget.group)
		guns.append(keep_gadget)
	if guns.is_empty():
		guns = [Gun.new("m1911", self)]
		G.vm_camera.add_child(guns[0].group)
	gun_index = 0
	gun().equip()
	# 兵种道具开场即满:非武器技能直接回满次数;医疗包/护甲仍由地图物资提供
	if not _gadget_is_weapon():
		gadget_count = gadget_max if gadget_max > 0 else int(WeaponsData.C()[class_id].gadget_count)
	br_armor = 0.0
	br_medkits = 0


## 拾取入口(kind: weapon / armor / medkit / ammo;quality: 0 普通 1 稀有 2 史诗)
func br_pickup(kind: String, weapon_id: String, quality: int) -> bool:
	match kind:
		"weapon":
			return br_equip_weapon(weapon_id, quality)
		"armor":
			if br_armor >= br_armor_max:
				G.hud.hint("护甲已满")
				return false
			br_armor = br_armor_max
			G.hud.hint("护甲已装备:减少 30% 伤害")
			return true
		"medkit":
			if br_medkits >= 2:
				G.hud.hint("医疗包已满(最多 2 个)")
				return false
			br_medkits += 1
			G.hud.hint("医疗包 +1(按 F 使用,+50 HP)")
			return true
		"ammo":
			var gave := false
			for g in guns:
				if g.reserve < g.def.reserve:
					g.reserve = mini(g.def.reserve, g.reserve + int(ceil(g.def.reserve * 0.5)))
					gave = true
			if gave:
				G.hud.hint("弹药补给 +50%")
			return gave
	return false


## 拾取武器:1 主武器 + 1 副武器(手枪)槽位;品质加成作用于 def 副本(参考 gun.gd 改装副本机制)
func br_equip_weapon(weapon_id: String, quality: int) -> bool:
	if melee_active:
		_deactivate_melee(false)   # 拾取换枪:小刀强制收回
	var wdef = WeaponsData.W().get(weapon_id)
	if wdef == null:
		return false
	var is_pistol: bool = wdef.kind == "pistol"
	var slot: int = 1 if is_pistol else 0
	var g := Gun.new(weapon_id, self)
	if quality > 0:
		# 品质加成:伤害 +25%/级;弹匣容量按比例小幅提升(+15%/级,至少 1 发),
		# 不再使用“弹匣 +10*q”的绝对值——那会让 5 发枪在史诗品质下变成 25 发。
		var base_mag: int = g.def.mag
		var base_reserve: int = g.def.reserve
		g.def = Utils.def_copy(g.def)
		g.def.damage = g.def.damage * (1.0 + 0.25 * quality)
		g.def.mag = maxi(1, int(round(float(base_mag) * (1.0 + 0.15 * quality))))
		g.def.reserve = maxi(0, int(round(float(base_reserve) * (1.0 + 0.2 * quality))))
		g.mag_cap = g.def.mag
	# 新枪必须按“这把枪自己的 def”装满弹药,绝不继承上一把枪的弹匣/备弹
	g.ammo = g.def.mag
	g.reserve = g.def.reserve
	# 替换旧槽位枪(视角模型层)
	if slot < guns.size():
		var old = guns[slot]
		if old.group != null and is_instance_valid(old.group):
			G.vm_camera.remove_child(old.group)
			old.group.queue_free()
		guns.remove_at(slot)
	guns.insert(slot, g)
	G.vm_camera.add_child(g.group)
	g.holster()
	# 切到新枪(旧枪收起,防双枪同时可见)
	gun_index = mini(gun_index, guns.size() - 1)
	if not is_same(guns[gun_index], g):
		guns[gun_index].holster()
	gun_index = slot
	guns[gun_index].equip()
	G.lock_target = null
	AudioSys.reload(1)
	return true
