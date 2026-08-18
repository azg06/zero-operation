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
var gadget_count := 0
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
var _veh_tp := false                 # 载具第三人称
var _veh_crew := 0                   # [8/10] 载具乘员位:0=驾驶位 1=炮手/操作位(炮塔载具)
var _veh_scope := false              # [8/10] 炮手位炮镜(右键 ADS)
var _passenger_gun := false          # 吉普副驾驶持个人武器状态(可开火)
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


## 同步影子手持武器:重建 body 上的当前主武器投影(SHADOWS_ONLY,不渲染)
func _update_body_gun() -> void:
	if body == null or not is_instance_valid(body) or not body.has_meta("upper"):
		return
	var upper: Node3D = body.get_meta("upper")
	var old: Node3D = upper.get_node_or_null("BodyGun")
	if old != null:
		old.queue_free()
	var g := gun()
	if g == null or g.id == "rpg":
		return
	var gn: Node3D = WeaponModels.build(g.id, false, WeaponModsData.load_cfg(g.id))
	gn.name = "BodyGun"
	gn.scale = Vector3.ONE * 1.15
	gn.position = Vector3(0.16, 0.28, -0.35)
	var so_stack: Array = [gn]
	while not so_stack.is_empty():
		var n: Node3D = so_stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		for ch in n.get_children():
			so_stack.append(ch)
	upper.add_child(gn)
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
	_update_body_gun()
	gadget = cls.gadget
	gadget_count = cls.gadget_count
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
	# 重生恢复尸体隐藏的枪/手臂(死亡时隐藏)
	if body != null and is_instance_valid(body) and body.has_meta("upper"):
		var bu: Node3D = body.get_meta("upper")
		for bn in ["BodyGun", "sho_l", "sho_r"]:
			var bn2: Node3D = bu.get_node_or_null(bn)
			if bn2 != null:
				bn2.visible = true
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
		if body != null and is_instance_valid(body):
			var body_upper: Node3D = body.get_meta("upper") if body.has_meta("upper") else null
			if body_upper != null:
				var bg: Node3D = body_upper.get_node_or_null("BodyGun")
				if bg != null:
					bg.visible = false
				for bn in ["sho_l", "sho_r"]:
					var sh: Node3D = body_upper.get_node_or_null(bn)
					if sh != null:
						sh.visible = false
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
	var cls = WeaponsData.C()[class_id]
	if gadget != "rpg":
		gadget_count = cls.gadget_count


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
	# 工程兵:F 维修附近己方受损载具
	if class_id == "engineer" and _try_repair_vehicle():
		return
	# 侦察兵:F 部署重生信标
	if class_id == "recon":
		# 任务1:BR 禁用重生信标(BR 的 F 键为医疗包,此为兜底门控)
		if G.mode == "br":
			G.hud.hint("大逃杀禁用重生信标")
			AudioSys.dry_fire()
			return
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
	if melee_active:
		_deactivate_melee(false)   # 上车:小刀强制收回(载具互斥)
	if motion != null:
		motion.reset(Vector3.ZERO)  # 车上由 VehicleCameraController 接管,清掉步战运动残留
	vehicle = v
	# 座位分配:优先驾驶位;驾驶位被占(队友/NPC)则坐炮手/乘客位;两个座位都满则不能上车
	if v.driver == null:
		v.driver = self
		_veh_crew = 0
	elif v.gunner == null:
		v.gunner = self
		_veh_crew = 1
	else:
		vehicle = null
		G.hud.hint("载具已满员")
		return
	yaw = 0
	pitch = 0  # 相对载具的观察角
	_veh_tp = false
	_passenger_gun = false
	if v.camera_ctl != null:
		v.camera_ctl.reset()       # 重置第三人称平滑(防瞬移插值)
		v.camera_ctl.set_gunner_mode(_veh_crew == 1)
	for g in guns:
		g.holster()
	AudioSys.engine_start(v.type)
	if _veh_crew == 1 and v.has_turret():
		G.hud.hint("炮手位:鼠标瞄准 · 左键开火 · F 换驾驶位 · E 下车")
	else:
		G.hud.hint("W/S 油门刹车 · A/D 转向 · C 第三人称 · E 下车")
	# 征召附近空闲队友当炮手(炮塔载具双人制;玩家驾驶时缺炮手)
	_call_gunner_crew(v)


## 征召最近空闲同队 bot 登车担任炮手/乘客(半径 150m;在载具中的 bot 不征召)
func _call_gunner_crew(v) -> void:
	if not v.has_turret() or v.gunner != null or G.bots.is_empty():
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
	if best != null:
		best.board_vehicle(v)
		if not _veh_recruit_notified:
			_veh_recruit_notified = true
			G.hud.hint("队友已响应,正在登车担任炮手")


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
	var leg_l: Node3D = veh_body.get_meta("leg_l")
	var leg_l_knee: Node3D = veh_body.get_meta("leg_l_knee")
	var leg_r: Node3D = veh_body.get_meta("leg_r")
	var leg_r_knee: Node3D = veh_body.get_meta("leg_r_knee")
	var rig: Node3D = veh_body.get_meta("rig")
	veh_body.rotation_order = EULER_ORDER_YXZ
	# 吉普:臀部落座(模型原点在脚底,座椅面高约 1.08,下沉 1.32 防站穿车顶)
	# 副驾驶位用乘客锚点(右前座),驾驶位用座位锚点(左前座)
	var seat: Vector3 = v.passenger_world() if _veh_crew == 1 else v.seat_world()
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
	# Z 键(载具内趴下键):召唤附近空闲队友补齐空缺乘员位(驾驶位/炮手/乘客)
	if Input.is_action_just_pressed("prone"):
		_call_crew_mates(v)
	if Input.is_action_just_pressed("crouch"):
		_veh_tp = not _veh_tp
	# F 切换乘员位(目标座位被 NPC 占时玩家可顶替,NPC 下一帧自动释放)
	if Input.is_action_just_pressed("gadget"):
		if _veh_crew == 0 and v.gunner != self:
			if v.gunner != null:
				print("[CREW-F] 顶替 NPC 炮手位")
			v.driver = null
			v.gunner = self
			_veh_crew = 1
		elif _veh_crew == 1 and v.driver != self:
			if v.driver != null:
				print("[CREW-F] 顶替 NPC 驾驶位")
			v.gunner = null
			v.driver = self
			_veh_crew = 0
	var cam := camera()
	pos = Vector3(v.pos.x, v.pos.y, v.pos.z)  # 供 AI 瞄准/小地图
	var ctl = v.camera_ctl
	if ctl == null:
		return
	ctl.set_gunner_mode(_veh_crew == 1)
	cam.rotation_order = EULER_ORDER_YXZ
	# 炮镜:仅炮手位可用(驾驶位只能驾驶)
	_veh_scope = Input.is_action_pressed("ads") and _veh_crew == 1 and not _veh_tp
	if v.has_turret():
		if _veh_crew == 1:
			# 炮手位:瞄准镜头(准心=炮口=准心)
			if _veh_tp:
				ctl.view = VehicleCameraController.VehView.THIRD_PERSON
			elif _veh_scope:
				ctl.view = VehicleCameraController.VehView.FP_OPTIC
			else:
				ctl.view = VehicleCameraController.VehView.FP_GUNNER
		else:
			# 驾驶位:只能驾驶,自由观察(不带动炮塔)
			ctl.view = VehicleCameraController.VehView.THIRD_PERSON if _veh_tp else VehicleCameraController.VehView.FP_DRIVER
		if G.hud != null and G.hud.has_method("set_veh_scope"):
			G.hud.set_veh_scope(_veh_scope)
		var w_name: String = "主炮" if v.is_tank() else v.def.weapon["cn"]
		var crew_hint: String = "F 换位(" + ("炮手" if _veh_crew == 0 else "驾驶") + ") · C 第三人称 · E 下车"
		if _veh_crew == 1:
			G.hud.hint(w_name + ("装填 " + str(ceil(v.cannon_t)) + "s · " if v.cannon_t > 0 and v.is_tank() else "就绪 · 左键开火 · ") + crew_hint)
		else:
			G.hud.hint("驾驶中(驾驶位不能开炮) · " + crew_hint)
	else:
		# 吉普:驾驶位/乘客位均自由观察(只转相机,车体方向由驾驶输入控制)
		ctl.view = VehicleCameraController.VehView.THIRD_PERSON if _veh_tp else VehicleCameraController.VehView.FP_DRIVER
		if _veh_crew == 1:
			# 副驾驶:可持个人武器开火(准心=观察方向),第三人称时收枪
			_update_passenger_gun(dt)
			G.hud.hint("乘客位 · 左键开火 · R 换弹 · F 换驾驶位 · Z 召唤队友 · C 第三人称 · E 下车")
		else:
			if _passenger_gun:
				_passenger_gun = false
				if gun() != null:
					gun().holster()
			G.hud.hint("W/S 油门刹车 · A/D 转向 · Z 召唤队友 · C 第三人称 · E 下车")
	# 鼠标观察(第三人称=360° 环绕;第一人称=观察角;只转相机,不转车体)
	var md: Vector2 = input.consume_mouse()
	if _veh_tp:
		ctl.apply_tp_orbit(md.x, md.y)
	else:
		ctl.apply_look(md.x, md.y)
	# 副驾驶持枪后坐作用于观察角(复用玩家后坐衰减,开枪有真实抬枪感)
	if _passenger_gun:
		ctl.look_pitch = clampf(ctl.look_pitch + recoil_pitch + cam_kick_pitch,
			VehicleCameraController.LOOK_PITCH_DOWN, VehicleCameraController.LOOK_PITCH_UP)
		ctl.look_yaw = clampf(ctl.look_yaw + recoil_yaw + cam_kick_yaw,
			-VehicleCameraController.LOOK_YAW_MAX, VehicleCameraController.LOOK_YAW_MAX)
	recoil_pitch = Utils.damp(recoil_pitch, 0, 3.4, dt)
	recoil_yaw = Utils.damp(recoil_yaw, 0, 9, dt)
	cam_kick_pitch = Utils.damp(cam_kick_pitch, 0, 13, dt)
	cam_kick_yaw = Utils.damp(cam_kick_yaw, 0, 13, dt)
	ctl.update(dt)
	# 定期征召炮手:驾驶炮塔载具期间若炮手位空缺,每 3s 尝试拉最近空闲队友登车
	if v.has_turret() and v.gunner == null:
		_veh_recruit_t -= dt
		if _veh_recruit_t <= 0:
			_veh_recruit_t = 3.0
			_call_gunner_crew(v)
	# FOV:载具第一人称 86°,炮镜缩放 0.7×;吉普副驾驶持枪开镜按武器 zoom_fov 缩放,
	# 高倍率狙击镜例外:主相机保持正常 FOV,镜内倍率由 OpticScopeSystem 独立渲染。
	var fov_target: float = VehicleCameraController.FP_FOV
	if _veh_scope:
		fov_target = VehicleCameraController.FP_FOV * 0.7
	elif _passenger_gun and gun() != null:
		if gun().scope_sight():
			fov_target = VehicleCameraController.FP_FOV
		else:
			fov_target = lerpf(VehicleCameraController.FP_FOV, gun().def.zoom_fov, gun().ads_amount)
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
			b.board_vehicle(v)
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
	var want: bool = not _veh_tp and g != null
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
		switch_weapon((gun_index + (1 if wheel > 0 else -1) + guns.size()) % guns.size())
	g.update(dt)


func update_player(dt: float) -> void:
	if not alive:
		return
	var input = G.input_sys
	spawn_protect = maxf(0, spawn_protect - dt)
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
			if G.mode == "br":
				# 大逃杀:按 F 使用医疗包
				if br_medkits > 0:
					br_medkits -= 1
					heal(50)
					AudioSys.capture(true)
					G.hud.hint("医疗包:恢复 50 生命(剩余 %d)" % br_medkits)
				else:
					AudioSys.dry_fire()
					G.hud.hint("没有医疗包 — 搜索物资获取(按 F 使用)")
			else:
				use_gadget()
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
		# 手雷蓄力/抛掷动作(视角模型)
		if not _nade_arming and _nade_vm_t < 0.0 and melee_active:
			pass
		_update_nade_vm(dt)
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
	cam.rotation.y = yaw + recoil_yaw + cam_kick_yaw + reload_cam_yaw + G.effects.shake_yaw + sin(jt * 31.0) * sup_j + motion_rot.y
	cam.rotation.x = pitch + recoil_pitch + cam_kick_pitch + reload_cam_pitch + G.effects.shake_pitch + cos(jt * 27.0 + 1.4) * sup_j + motion_rot.x
	# 滑铲相机侧倾:快速压入,干净回正
	_slide_roll = Utils.damp(_slide_roll, -0.1 if slide_t > 0 else 0.0, 16.0 if slide_t > 0 else 10.0, dt)
	cam.rotation.z = recoil_yaw * 0.3 + _slide_roll + reload_cam_roll + motion_rot.z
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

## 登机时清空装备:仅保留一把基础手枪(避免 gun() 空引用),护甲/药品清零
## 时序注意:被保留手枪的 group 绝不能 queue_free(帧末会被真正销毁),否则下一帧
## gun.update 访问已释放节点(gun.gd:496 "previously freed" 报错根因)
func br_strip_inventory() -> void:
	if melee_active:
		_deactivate_melee(false)   # 登机清装:小刀强制收回
	var keep: Gun = null
	for g in guns:
		if g.def.kind == "pistol":
			keep = g
			break
	for g in guns:
		if is_same(g, keep) or g.group == null or not is_instance_valid(g.group):
			continue
		G.vm_camera.remove_child(g.group)
		g.group.queue_free()
	guns = []
	if keep != null and keep.group != null and is_instance_valid(keep.group):
		if keep.group.get_parent() != G.vm_camera:
			G.vm_camera.add_child(keep.group)
		guns = [keep]
	else:
		guns = [Gun.new("m1911", self)]
		G.vm_camera.add_child(guns[0].group)
	gun_index = 0
	gun().equip()
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
		g.def = Utils.def_copy(g.def)
		g.def.damage = g.def.damage * (1.0 + 0.25 * quality)
		g.def.mag = maxi(1, g.def.mag + 10 * quality)
		g.def.reserve = maxi(0, g.def.reserve + 20 * quality)
		g.mag_cap = g.def.mag
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
