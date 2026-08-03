extends Node3D
## 主装配与主循环(对应 main.js)

## ---- 输入系统(对应 input.js) ----
class InputSys extends RefCounted:
	var mouse_dx := 0.0
	var mouse_dy := 0.0
	var wheel := 0

	func consume_mouse() -> Vector2:
		var r := Vector2(mouse_dx, mouse_dy)
		mouse_dx = 0
		mouse_dy = 0
		return r

	func consume_wheel() -> int:
		var w := wheel
		wheel = 0
		return w

	func lock() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func unlock() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	func is_locked() -> bool:
		return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


var _camera: Camera3D
var _vm_viewport: SubViewport
var _vm_camera: Camera3D
var _vm_sun: DirectionalLight3D
var _vm_e: Environment
var _fxaa_rect: ColorRect
var _effects: Effects
var _hud: HUD
var _menus: Menus
var _world_root: Node3D

var _fps_acc := 0.0
var _fps_n := 0
var _fps_low_t := 0
var _degraded := false
var _validate := false
var _shot_frame := 0
var _shot_path := ""
var _dbg_ads := false
var _dbg_prone := false
var _dbg_slide := false
var _dbg_lookdown := false
var _dbg_pose := false
var _memwatch := false
var _memwatch_t := 0.0
var _memwatch_n := 0
var _menu_squad: Array = []
var _sun_occ_t := 0.0
var _sun_blocked := false
var _flashlight: SpotLight3D
var _ready_room: Node3D                    # 特勤处备战屋(主菜单背景 3D 战争房间)
var _room_cam_yaw := 0.0                   # 房间相机左右摆动相位
var _room_cam_base := Vector3(0, 81.55, 7.1)   # 房间相机基准位(房间位于 (0,80,0))
var _room_cam_look := Vector3(0, 81.1, -1.4)   # 房间相机注视点(四陈列台一排)


func _ready() -> void:
	_validate = OS.get_cmdline_user_args().has("--validate")
	G.main = self
	# ---- 启动即全屏(桌面) + CPU/GPU 加速 ----
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	OS.set_low_processor_usage_mode(false)
	Engine.max_fps = 144 if not OS.has_feature("web") else 0
	# ---- 垂直同步设置项(0=关 1=开 2=自适应;web 端强制关) ----
	if OS.has_feature("web"):
		G.settings["vsync"] = 0
	else:
		G.settings["vsync"] = G.settings.get("vsync", 1)
	# ---- Web 专配:浏览器端 GPU 远弱于桌面 Vulkan,预设低碳 + 禁止自动降级(降级即模糊) ----
	if OS.has_feature("web"):
		G.settings.shadows = 1024
		G.settings.ssao = false
		G.settings.fxaa = false
		G.settings.particles = 0.4
		G.settings.fog = 0.75
		G.settings.scale = 0.92
		G.settings.aniso = 16
		_degraded = true
	else:
		# Windows 桌面版:GPU 足够强,强制全分辨率 + 3D 超采样抗锯齿
		G.settings.scale = 1.0
		get_viewport().scaling_3d_scale = 1.0
	# ---- 输入 ----
	G.input_sys = InputSys.new()
	# ---- 主相机 ----
	_camera = Camera3D.new()
	_camera.fov = G.settings.fov
	_camera.near = 0.08
	_camera.far = 900
	_camera.current = true
	add_child(_camera)
	G.camera = _camera
	# ---- 枪口手电(黑夜地图专属,挂枪口照亮前方战场) ----
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color.html("#fff0d8")
	_flashlight.light_energy = 12.0
	_flashlight.spot_range = 50.0
	_flashlight.spot_angle = 34.0
	_flashlight.spot_attenuation = 1.0
	_flashlight.shadow_enabled = true
	_camera.add_child(_flashlight)
	_flashlight.visible = false
	# ---- 环境 ----
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	add_child(we)
	G.world_env = we
	# ---- 世界容器 ----
	_world_root = Node3D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)
	G.world_root = _world_root
	# ---- 第一图层视角模型(独立世界+独立相机,永不穿模) ----
	var vm_layer := CanvasLayer.new()
	vm_layer.layer = 4
	add_child(vm_layer)
	var vm_container := SubViewportContainer.new()
	vm_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vm_container.stretch = true
	vm_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_layer.add_child(vm_container)
	_vm_viewport = SubViewport.new()
	_vm_viewport.own_world_3d = true
	_vm_viewport.transparent_bg = true
	_vm_viewport.msaa_3d = Viewport.MSAA_4X  # 手臂/枪械抗锯齿(原 FXAA 覆盖不到独立世界边缘)
	_vm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vm_viewport.size = get_viewport().get_visible_rect().size
	vm_container.add_child(_vm_viewport)
	G.vm_viewport = _vm_viewport
	var vm_env := WorldEnvironment.new()
	var vm_e := Environment.new()
	vm_e.background_mode = Environment.BG_COLOR
	vm_e.background_color = Color(0, 0, 0, 0)
	vm_e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	vm_e.ambient_light_color = Color(0.75, 0.83, 0.91)
	vm_e.ambient_light_energy = 1.2
	vm_e.tonemap_mode = Environment.TONE_MAPPER_ACES
	vm_env.environment = vm_e
	_vm_viewport.add_child(vm_env)
	_vm_e = vm_e
	var vm_sun := DirectionalLight3D.new()
	vm_sun.light_color = Color.html("#fff2dd")
	vm_sun.light_energy = 1.5
	vm_sun.rotation = Vector3(-0.7, 0.6, 0)
	_vm_viewport.add_child(vm_sun)
	_vm_sun = vm_sun
	# ---- FXAA 后处理(自定义着色器抗锯齿,层 4:HUD(5)/菜单(10) 之下,只覆盖 3D 与视角模型) ----
	var fxaa_layer := CanvasLayer.new()
	fxaa_layer.layer = 4
	add_child(fxaa_layer)
	_fxaa_rect = ColorRect.new()
	_fxaa_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fxaa_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fxaa_mat := ShaderMaterial.new()
	fxaa_mat.shader = load("res://src/fx/fxaa.gdshader")
	_fxaa_rect.material = fxaa_mat
	fxaa_layer.add_child(_fxaa_rect)
	_vm_camera = Camera3D.new()
	_vm_camera.fov = 60
	_vm_camera.near = 0.01
	_vm_camera.far = 10
	_vm_camera.current = true
	_vm_viewport.add_child(_vm_camera)
	G.vm_camera = _vm_camera
	# ---- 系统装配 ----
	_effects = Effects.new()
	add_child(_effects)
	G.effects = _effects
	var gm := Game.new()
	add_child(gm)
	G.game = gm
	var bm := BotManager.new()
	add_child(bm)
	G.bot_manager = bm
	var pl := Player.new()
	add_child(pl)
	G.player = pl
	_hud = HUD.new()
	add_child(_hud)
	_menus = Menus.new()
	add_child(_menus)
	# ---- 战役控制器(战争故事;campaign.gd 由数据子智能体实现,未就绪时跳过) ----
	if ResourceLoader.exists("res://src/campaign/campaign.gd"):
		var c = load("res://src/campaign/campaign.gd")
		if c is GDScript:
			G.campaign = c.new()
			add_child(G.campaign)
	# ---- 流程绑定 ----
	_menus.on_start = func():
		_go_fullscreen()
		_menus.hide_all()
		G.game.start_match(G.mode)
	_menus.on_deploy = func(class_id: String, loadout):
		_go_fullscreen()
		_menus.hide_all()
		G.game.deploy(class_id, loadout)
	_menus.on_redeploy = func():
		_menus.hide_all()
		G.game.redeploy()
	_menus.on_resume = func():
		_go_fullscreen()
		_menus.close_settings()  # 暂停中打开设置后按 Esc 恢复,一并收起设置屏
		_menus.show_pause(false)
		G.paused = false
		G.input_sys.lock()
	_menus.on_quit = func():
		_menus.hide_all()
		G.state = "menu"
		G.paused = false
		_hud.hide_screen("hud")
		_hud.clear_campaign_ui()  # 回主菜单:清战役 UI 残留(目标/字幕/点名卡/箭头)
		if G.campaign != null:
			G.campaign.abort()   # 清理战役封锁带/路点/破坏物(菜单态无残留)
		G.input_sys.unlock()
		_setup_menu_scene()
		_menus.show_menu()
	_menus.on_again = func():
		_menus.hide_all()
		G.game.start_match(G.mode)
	# ---- 战役模式:章节启动(menus 章节选择屏赋值) ----
	# game.gd 战役分支读 G.campaign_pending_id 构建章节地图并自动部署玩家(不经过部署屏)
	_menus.on_campaign_start = func():
		_go_fullscreen()
		_menus.hide_all()
		G.mode = "campaign"
		G.game.start_match("campaign")
		_ensure_campaign_started()  # 幂等兜底:game.gd 战役分支已调 start_chapter 则跳过
	G.apply_graphics = apply_graphics
	apply_graphics()
	# 默认战场(主菜单背景,不生成载具/飞机,与原版一致)
	WorldBuilder.build_world(G.world_root, "city")
	_build_ready_room()  # 特勤处备战屋:主菜单背景 3D 战争房间(高空展厅,四兵种陈列)
	GraphicsQuality.load_config()
	GraphicsQuality.apply_preset(GraphicsQuality.current_level)  # 启动即应用硬件检测/存档画质预设(无条件)
	_setup_menu_scene()  # 主界面背景:四兵种编队
	get_tree().root.size_changed.connect(_on_resize)
	if _validate:
		print("[VALIDATE] 初始化完成,世界已构建: 碰撞体=", G.colliders.size(), " 旗帜=", G.flags.size())
	# 无头游玩测试:--test-play [mode] [map]
	var ua := OS.get_cmdline_user_args()
	if ua.has("--screenshot"):
		var sidx := ua.find("--screenshot")
		_shot_frame = int(ua[sidx + 1])
		_shot_path = ua[sidx + 2]
	if ua.has("--test-play"):
		var idx := ua.find("--test-play")
		var mode: String = ua[idx + 1] if ua.size() > idx + 1 else "conquest"
		G.sel_maps[mode] = ua[idx + 2] if ua.size() > idx + 2 else "random"
		_menus.hide_all()
		G.game.start_match(mode)
		if not ua.has("--no-deploy"):
			G.game.deploy("assault", { "primary": "m4", "secondary": "m1911", "shotgun": "m1014" })
			print("[TEST] 已部署,开始模拟游玩 state=", G.state)
		else:
			print("[TEST] 部署界面 state=", G.state)
	# 换枪测试:--test-gun <id>
	if ua.has("--test-gun"):
		var gidx := ua.find("--test-gun")
		var gid: String = ua[gidx + 1]
		await get_tree().create_timer(1.0).timeout
		var found := false
		for g in G.player.guns:
			if g.id == gid:
				G.player.switch_weapon(G.player.guns.find(g))
				found = true
				break
		if not found:
			# 没有则临时装配一把
			for g in G.player.guns:
				G.vm_camera.remove_child(g.group)
				g.group.queue_free()
			G.player.guns = [Gun.new(gid, G.player)]
			G.vm_camera.add_child(G.player.guns[0].group)
			G.player.gun_index = 0
			G.player.gun().equip()
		print("[TEST] 已切换武器: ", gid)
	# 按换弹进度截屏:--reload-shot <换弹秒数> <输出路径>(自动触发换弹)
	if ua.has("--reload-shot"):
		var rsidx := ua.find("--reload-shot")
		var rs_t: float = float(ua[rsidx + 1])
		var rs_path: String = ua[rsidx + 2]
		await get_tree().create_timer(2.0).timeout
		G.player.gun().ammo = 5
		G.player.gun().reload()
		# rs_t 超过换弹总时长或换弹被中断时不得死循环:换弹结束(或超时 1200 帧≈20s)即退出
		var rs_guard := 0
		while G.player.gun() == null or (G.player.gun().reloading and G.player.gun().reload_t < rs_t):
			rs_guard += 1
			if rs_guard > 1200:
				break
			await get_tree().process_frame
		var rs_img := get_viewport().get_texture().get_image()
		rs_img.save_png(rs_path)
		print("[SHOT] 换弹 t=%.2f 已保存: %s" % [G.player.gun().reload_t, rs_path])
	# 换弹动画测试:--test-reload <帧号触发>
	if ua.has("--test-reload"):
		await get_tree().create_timer(2.0).timeout
		G.player.gun().ammo = 5
		G.player.gun().reload()
		for k in 10:
			await get_tree().create_timer(0.22).timeout
			var g3 = G.player.gun()
			print("[RELOAD] t=%.2f mag_visible=%s mag_y=%.3f" % [g3.reload_t,
				g3._mag.visible if g3._mag != null else false,
				g3._mag.position.y if g3._mag != null else -999.0])
	# 弹药包测试:--test-ammo
	if ua.has("--test-ammo"):
		await get_tree().create_timer(2.0).timeout
		G.game.spawn_ammo_pack(G.player)
	# 掉枪测试:--test-drop(在玩家面前掉落各一把步枪/狙击枪)
	if ua.has("--test-drop"):
		await get_tree().create_timer(1.5).timeout
		var fwd2 := Vector3(-sin(G.player.yaw), 0, -cos(G.player.yaw))
		G.effects.spawn_dropped_weapon("m4", G.player.pos + fwd2 * 3.0 + Vector3(0, 1.2, 0))
		G.effects.spawn_dropped_weapon("awm", G.player.pos + fwd2 * 3.5 + Vector3(0.8, 1.2, 0))
		print("[DROP] 已掉落两把武器")
	# 碰撞验证:--test-collide
	if ua.has("--test-collide"):
		await get_tree().create_timer(1.0).timeout
		# 1) 静态碰撞体推挤:把玩家强塞进一个盒体
		var p := Vector3(G.player.pos.x, G.player.pos.y, G.player.pos.z)
		G.colliders.append(AABB(Vector3(p.x - 1, p.y - 1, p.z - 1), Vector3(2, 10, 2)))
		var before := p
		p.x += 0.5  # 强制进入盒内
		p = Utils.move_collide(p, 0.38, 1.75)
		var ejected: bool = absf(p.x - before.x) >= 1.38 - 0.5 - 0.01 or absf(p.z - before.z) >= 1.38 - 0.01
		print("[COLLIDE] 建筑推挤: ", "通过" if ejected else "失败", " (弹出点 ", p, ")")
		# 2) 载具推挤:把玩家放到载具中心
		if not G.vehicles.is_empty():
			var v = G.vehicles[0]
			var p2 := Vector3(v.pos.x + 0.5, v.pos.y, v.pos.z)  # 偏移 0.5m,避免正中心退化
			p2 = Vehicle.vehicle_collide(p2, 0.38)
			var d := Vector2(p2.x - v.pos.x, p2.z - v.pos.z).length()
			print("[COLLIDE] 载具推挤: ", "通过" if d >= v.def["radius"] * 0.92 + 0.3 else "失败", " (推出距离 ", d, ")")
		# 3) 射线 vs 世界
		var hit = Utils.raycast_world(G.camera.global_position, Vector3(0, -1, 0), 100)
		print("[COLLIDE] 落地射线: ", "通过" if hit != null else "失败")
	# 命中判定验证:--test-hitscan(敌人传送到 LOS 通透位置,双向验证伤害注册)
	if ua.has("--test-hitscan"):
		await get_tree().create_timer(2.0).timeout
		var enemy = null
		for b in G.bots:
			if b.team != G.player.team and b.alive and b.get("vehicle") == null:
				enemy = b
				break
		if enemy != null:
			# 其他敌方单位/载具/飞机传送远处,避免走进弹道走廊被优先命中(hitscan 取最近命中,载具会覆盖角色)
			for b in G.bots:
				if b != enemy and b.team != G.player.team:
					b.pos = Vector3(400, 0, 400)
			for v in G.vehicles:
				v.pos = Vector3(400, 0, 430)
			for a in G.aircraft:
				a.pos = Vector3(400, 80, 400)
			var eye: Vector3 = G.player.pos + Vector3(0, 1.62, 0)
			var pchest: Vector3 = G.player.pos + Vector3(0, 1.05, 0)
			var placed := false
			for k in 16:
				var ang := TAU * k / 16.0
				var spot: Vector3 = G.player.pos + Vector3(cos(ang), 0, sin(ang)) * 8
				spot.y = G.ground_h.call(spot.x, spot.z) if G.ground_h.is_valid() else 0.0
				var echest := Vector3(spot.x, spot.y + 1.05, spot.z)
				var epos0 := Vector3(spot.x, spot.y + 1.4, spot.z)
				# 双向 LOS 都通透才采用(反向路径高度不同,可能撞上低矮掩体)
				if Utils.los_clear(eye, echest) and Utils.los_clear(epos0, pchest):
					enemy.pos = spot
					placed = true
					break
			if placed:
				enemy.vel = Vector3.ZERO
				enemy.prone = false  # 姿态影响受弹高度,强制站立排除干扰
				G.player.prone = false
				G.player.crouched = false
				var chest := Vector3(enemy.pos.x, enemy.pos.y + 1.05, enemy.pos.z)
				var hp0: float = enemy.health
				var def2 = G.player.gun().def
				var fdir: Vector3 = (chest - eye).normalized()
				var dbg_wall = Utils.raycast_world(eye, fdir, 300)
				var dbg_d: float = Utils.ray_sphere(eye, fdir, chest, 0.42, 300)
				print("[HITSCAN-D] wall=", dbg_wall["dist"] if dbg_wall != null else -1,
					" sphere_d=", dbg_d, " enemy_alive=", enemy.alive,
					" enemy_veh=", enemy.get("vehicle"), " epos=", enemy.pos)
				G.game.fire_hitscan(G.player, def2, eye, fdir, eye)
				print("[HITSCAN] 玩家→敌人: ", "通过" if enemy.health < hp0 else "失败", " (", hp0, " → ", enemy.health, ")")
				G.player.spawn_protect = 0  # 出生保护会拒绝伤害,测试前清零
				var php0: float = G.player.health
				var epos := Vector3(enemy.pos.x, enemy.pos.y + 1.4, enemy.pos.z)
				var bdir: Vector3 = ((G.player.pos + Vector3(0, 1.05, 0)) - epos).normalized()
				var dbg_wall2 = Utils.raycast_world(epos, bdir, 300)
				var dbg_d2: float = Utils.ray_sphere(epos, bdir, G.player.pos + Vector3(0, 1.05, 0), 0.42, 300)
				print("[HITSCAN-D] wall2=", dbg_wall2["dist"] if dbg_wall2 != null else -1,
					" sphere_d2=", dbg_d2, " p_alive=", G.player.alive,
					" p_veh=", G.player.get("vehicle"), " state=", G.state)
				G.game.fire_hitscan(enemy, def2, epos, bdir, epos)
				print("[HITSCAN] 敌人→玩家: ", "通过" if G.player.health < php0 else "失败", " (", php0, " → ", G.player.health, ")")
			else:
				print("[HITSCAN] 跳过: 周围 8m 无通透位置")
		else:
			print("[HITSCAN] 失败: 没有存活敌人")
	# RPG 制导验证:--test-rpg(锁定→发射→追踪;目标销毁后无崩溃)
	if ua.has("--test-rpg"):
		await get_tree().create_timer(2.0).timeout
		var heli = null
		for a in G.aircraft:
			if a.team != G.player.team and not a.dead:
				heli = a
				break
		if heli != null:
			var hp1: float = heli.hp
			G.lock_target = heli
			var dir3: Vector3 = (heli.pos - G.camera.global_position).normalized()
			# 距目标 40m 处生成(消除飞行时间与建筑遮挡的测试不确定性)
			G.effects.spawn_rocket(G.player, { "cn": "防空导弹", "damage": 320.0, "splash": 10.0, "speed": 50.0 },
				heli.pos - dir3 * 40, dir3, G.lock_target)
			G.lock_target = null
			print("[RPG] 制导火箭已发射 → 追踪中")
			await get_tree().create_timer(3.0).timeout
			print("[RPG] 制导命中: ", "通过" if heli.hp < hp1 or heli.dead else "失败", " (", hp1, " → ", heli.hp, ")")
			# 失效实例防护:目标被销毁后,在飞火箭不得崩溃
			G.lock_target = heli
			G.effects.spawn_rocket(G.player, { "cn": "防空导弹", "damage": 320.0, "splash": 10.0, "speed": 50.0 },
				G.camera.global_position, Vector3.UP, G.lock_target)
			G.lock_target = null
			heli.dispose()
			G.aircraft.erase(heli)  # 与 setup_map 一致:销毁即移出列表
			await get_tree().create_timer(1.5).timeout
			print("[RPG] 目标销毁后火箭无崩溃: 通过")
		else:
			print("[RPG] 跳过: 无敌方空中单位")
	# 可进入建筑测试:--test-enterable(后墙应阻挡,门口应通行)
	if ua.has("--test-enterable"):
		await get_tree().create_timer(2.0).timeout
		var rd: float = MapsData.M()["city"].road
		G.player.pos = Vector3(12, 0, -rd * 0.5)  # 建筑内部中心
		await get_tree().process_frame
		for k in 25:  # 向后墙走(+Z)
			G.player.pos += Vector3(0, 0, 0.15)
			G.player.pos = Utils.move_collide(G.player.pos, 0.38, 1.75)
		var back_z: float = G.player.pos.z
		for k in 45:  # 向门口走(-Z)
			G.player.pos += Vector3(0, 0, -0.15)
			G.player.pos = Utils.move_collide(G.player.pos, 0.38, 1.75)
		var door_z: float = G.player.pos.z
		print("[ENTER] 后墙阻挡: ", "通过" if back_z < -rd * 0.5 + 2.4 else "失败", " (z=%.2f)" % back_z)
		print("[ENTER] 门口通行: ", "通过" if door_z < -rd * 0.5 - 3.2 else "失败", " (z=%.2f)" % door_z)
		# 传回建筑内供截图
		G.player.pos = Vector3(11, 0, -rd * 0.5 + 0.5)
		G.player.yaw = 2.6
	# 地图连切压测:--test-mapcycle <次数>(反复重建世界,抓销毁/重建崩溃)
	if ua.has("--test-mapcycle"):
		var midx2 := ua.find("--test-mapcycle")
		var cycles: int = int(ua[midx2 + 1]) if ua.size() > midx2 + 1 else 3
		var maps := ["city", "desert", "snow", "bt_jungle", "bt_harbor", "bt_peak"]
		for cyc in cycles:
			for m in maps:
				print("[MAPCYCLE] 第", cyc + 1, "轮 切换到 ", m)
				G.game.setup_map(m)
				await get_tree().process_frame
				await get_tree().process_frame
				print("[MAPCYCLE] ", m, " 碰撞体=", G.colliders.size(), " 破坏物=", G.destructibles.size(), " 载具=", G.vehicles.size())
		print("[MAPCYCLE] 全部完成")
	if ua.has("--test-at"):
		await get_tree().create_timer(2.0).timeout
		var veh = null
		for attempt in 12:
			for v in G.vehicles:
				if not v.dead and v.team() != null and v.team() != G.player.team:
					veh = v
					break
		if veh != null:
			# 先测地雷(需要活体驾驶员在车上)
			var hp1: float = veh.hp
			G.game.spawn_at_mine(G.player)
			await get_tree().process_frame
			for d in G.deployables:
				if d["kind"] == "atmine":
					veh.pos = Vector3(d["pos"].x, veh.pos.y, d["pos"].z)  # 把载具开到雷上
					veh.speed = 0
					d["arm"] = 0
			await get_tree().create_timer(0.5).timeout
			print("[AT] 反坦克地雷触发: ", "通过" if veh.hp < hp1 else "失败", " (", hp1, " → ", veh.hp, ")")
			# 再测手雷碰炸
			var hp0: float = veh.hp
			G.effects.spawn_at_grenade(G.player, veh.pos + Vector3(0, 0.8, 0), Vector3.DOWN)
			await get_tree().create_timer(1.2).timeout
			print("[AT] 反坦克手雷碰炸: ", "通过" if veh.hp < hp0 else "失败", " (", hp0, " → ", veh.hp, ")")
		else:
			print("[AT] 跳过: 无敌方载具")
	# 设置页截图:--test-settings
	if ua.has("--test-settings"):
		await get_tree().create_timer(1.0).timeout
		_menus._screens["settings"].visible = true
	# 传送:--tp <x> <z>(把玩家传送到指定坐标观察)
	if ua.has("--tp"):
		var tpidx := ua.find("--tp")
		var tx2: float = float(ua[tpidx + 1])
		var tz2: float = float(ua[tpidx + 2])
		await get_tree().create_timer(1.2).timeout
		G.player.pos = Vector3(tx2, (G.ground_h.call(tx2, tz2) if G.ground_h.is_valid() else 0.0), tz2)
		print("[TP] 已传送至 ", G.player.pos)
	# 兵种模型合影:--test-classes(四种兵排列于玩家面前,面向玩家)
	if ua.has("--test-classes"):
		await get_tree().create_timer(1.5).timeout
		var cls_ids := ["assault", "engineer", "support", "recon"]
		var wids := ["m4", "m249", "mp5", "awm"]
		# 摆放在玩家视线正前 3.2m 处(玩家朝向地图中心)
		var fwd := Vector3(-sin(G.player.yaw), 0, -cos(G.player.yaw))
		var right := Vector3(cos(G.player.yaw), 0, -sin(G.player.yaw))
		var base_p: Vector3 = G.player.pos + fwd * 3.2
		for i in 4:
			var sm := SoldierModel.build_soldier("us", wids[i], cls_ids[i])
			sm.position = base_p + right * ((i - 1.5) * 1.1)
			sm.rotation.y = G.player.yaw + PI  # 面向玩家
			G.world_root.add_child(sm)
		print("[CLASSES] 已生成四兵种模型合影")
	# Sky3D 调试:--test-sky
	if ua.has("--test-sky"):
		await get_tree().create_timer(2.0).timeout
		var e := G.world_env.environment
		print("[SKY] sun.rot=", G.sun.rotation, " energy=", G.sun.light_energy, " color=", G.sun.light_color,
			" shadows=", G.sun.shadow_enabled)
		print("[SKY] amb_src=", e.ambient_light_source, " amb_color=", e.ambient_light_color,
			" amb_energy=", e.ambient_light_energy, " contrib=", e.ambient_light_sky_contribution,
			" bg=", e.background_mode, " exposure=", e.tonemap_exposure)
	if ua.has("--test-drive"):
		var tidx := ua.find("--test-drive")
		var vtype: String = ua[tidx + 1] if ua.size() > tidx + 1 else "tank"
		await get_tree().create_timer(2.0).timeout
		var veh = null
		for v in G.vehicles:
			if v.type == vtype and v.driver == null and not v.dead:
				veh = v
				break
		if veh != null:
			if ua.has("--veh-isolate"):
				veh.pos = Vector3(150, 0, 150)  # 空旷角隔离观察
			G.player.pos = veh.pos + Vector3(2, 0, 2)
			G.player.enter_vehicle(veh)
			if ua.has("--veh-tp"):
				G.player._veh_tp = true
			if ua.has("--veh-down"):
				veh.turret_pitch = -0.13
			if ua.has("--veh-up"):
				veh.turret_pitch = 0.9 if vtype == "aa" else 0.3
			print("[DRIVE] 进入载具 ", vtype, " tp=", G.player._veh_tp, " pitch=", veh.turret_pitch)
		else:
			print("[DRIVE] 找不到载具 ", vtype)
	# 输入行为测试:--test-input(用 parse_input_event 走标准输入管线)
	if ua.has("--test-input"):
		var tap := func(action: String) -> void:
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = true
			Input.parse_input_event(ev)
			await get_tree().process_frame
			var ev2 := InputEventAction.new()
			ev2.action = action
			ev2.pressed = false
			Input.parse_input_event(ev2)
			await get_tree().process_frame
		await get_tree().create_timer(2.0).timeout
		await tap.call("sprint")
		print("[INPUT] Shift 按下后 sprint_toggled =", G.player.sprint_toggled, " (期望 true)")
		await tap.call("sprint")
		print("[INPUT] Shift 再次按下后 sprint_toggled =", G.player.sprint_toggled, " (期望 false)")
		await tap.call("crouch")
		print("[INPUT] C 按下后 crouched =", G.player.crouched, " (期望 true)")
		await tap.call("crouch")
		print("[INPUT] C 再次按下后 crouched =", G.player.crouched, " (期望 false)")
		# 滑铲:冲刺状态下按 C
		G.player.sprint_toggled = true
		Input.action_press("move_forward")
		await get_tree().create_timer(0.5).timeout
		print("[INPUT] 滑铲前状态 sprint_amount=", G.player.sprint_amount,
			" h_spd=", Vector2(G.player.vel.x, G.player.vel.z).length(),
			" on_ground=", G.player.on_ground, " crouched=", G.player.crouched)
		await tap.call("crouch")
		Input.action_release("move_forward")
		print("[INPUT] 奔跑按 C 后 slide_t =", G.player.slide_t, " (期望 > 0)")
	if ua.has("--test-end"):
		await get_tree().create_timer(4.0).timeout
		G.tickets["ru"] = 0
		G.game.check_end()
		print("[TEST] 强制结束 state=", G.state)
		await get_tree().create_timer(2.0).timeout
		_menus.on_again.call()
		print("[TEST] 再战一局 state=", G.state)
	if ua.has("--test-kill"):
		await get_tree().create_timer(3.5).timeout
		G.player.damage(999, Vector3.ZERO, null)
		print("[TEST] 击杀玩家 state=", G.state)
		await get_tree().create_timer(3.0).timeout
		_menus.on_redeploy.call()
		print("[TEST] 重部署 state=", G.state)
		await get_tree().create_timer(1.0).timeout
		G.game.deploy("assault", { "primary": "m4", "secondary": "m1911", "shotgun": "m1014" })
		print("[TEST] 再次部署 state=", G.state)
	_dbg_ads = ua.has("--test-ads")
	_dbg_prone = ua.has("--test-prone")
	_dbg_slide = ua.has("--test-slide")
	_memwatch = ua.has("--memwatch")
	if ua.has("--test-lookdown"):
		_dbg_lookdown = true
	if ua.has("--test-pose"):
		_dbg_pose = true
	if _dbg_ads:
		Input.action_press("ads")  # 模拟按住右键瞄准
	if ua.has("--test-sb"):
		Input.action_press("scoreboard")  # 模拟按住 Tab 记分板
	# 环境调试:--nofog / --noamb / --nosun / --noenv
	if ua.has("--nofog") and G.world_env != null:
		G.world_env.environment.fog_enabled = false
	if ua.has("--noamb") and G.world_env != null:
		G.world_env.environment.ambient_light_energy = 0.0
	if ua.has("--nosun") and G.sun != null:
		G.sun.light_energy = 0.0
	if ua.has("--noenv"):
		G.world_env.environment = null
	if ua.has("--noshadow") and G.sun != null:
		G.sun.shadow_enabled = false
	# 地面排障:--redground 把地面材质改成纯红无贴图
	if ua.has("--redground"):
		for c in G.world_group.get_children():
			if c is MeshInstance3D and c.mesh != null and c.mesh.get_faces().size() > 5000:
				var red_mat := StandardMaterial3D.new()
				red_mat.albedo_color = Color(1, 0, 0)
				red_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 双面渲染,排查绕序
				c.material_override = red_mat
				print("[DBG] 地面已替换为纯红材质(双面)")
	if ua.has("--groundcheck"):
		for c in G.world_group.get_children():
			if c is MeshInstance3D and c.mesh != null and c.mesh.get_faces().size() > 5000:
				print("[GC] faces=", c.mesh.get_faces().size(), " aabb=", c.mesh.get_aabb(), " visible=", c.visible)
		var e := G.world_env.environment
		print("[GC] fog enabled=", e.fog_enabled, " mode=", e.fog_mode, " begin=", e.fog_depth_begin, " end=", e.fog_depth_end, " color=", e.fog_light_color)
		# 地面网格 UV / 贴图检查
		for c in G.world_group.get_children():
			if c is MeshInstance3D and c.mesh != null and c.mesh.get_faces().size() > 5000:
				var arrays: Array = c.mesh.surface_get_arrays(0)
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var minuv := Vector2(INF, INF)
				var maxuv := Vector2(-INF, -INF)
				for uv in uvs:
					minuv.x = minf(minuv.x, uv.x)
					minuv.y = minf(minuv.y, uv.y)
					maxuv.x = maxf(maxuv.x, uv.x)
					maxuv.y = maxf(maxuv.y, uv.y)
				var mat := c.material_override as StandardMaterial3D
				print("[GC] UV范围: ", minuv, " → ", maxuv, " | 贴图: ", mat.albedo_texture, " | 反照色: ", mat.albedo_color)
				if mat.albedo_texture != null:
					mat.albedo_texture.get_image().save_png("C:\\Users\\gza\\AppData\\Local\\Temp\\opencode\\dbg_runtime_groundtex.png")


## ============ 主界面背景:特勤处备战屋(3D 战争房间 + 四兵种陈列台) ============
func _setup_menu_scene() -> void:
	# 清理旧编队(历史遗留,防残留)
	for m in _menu_squad:
		if is_instance_valid(m):
			m.queue_free()
	_menu_squad.clear()
	# 隐藏玩家视角模型/乘员/身体(主菜单不显示)
	if G.player != null:
		for gun in G.player.guns:
			gun.holster()
		if G.player.veh_body != null:
			G.player.veh_body.visible = false
		G.player.alive = false
	# 特勤处备战屋:显示房间 + 相机入位(缓慢摆动由 _process 菜单分支逐帧驱动)
	if _ready_room != null:
		_ready_room.visible = true
		_room_cam_yaw = 0.0
		_camera.global_position = _room_cam_base
		_camera.look_at(_room_cam_look, Vector3.UP)
		_camera.fov = 50  # Godot 4 设置 fov 自动生效(玩家部署后由 update 逐帧恢复)


## 兵种一句话简介(与部署界面卡片一致)
func _class_role(cid: String) -> String:
	return {
		"assault": "破阵 / 烟雾 / C5 / 自疗",
		"engineer": "反载具 / 维修 / RPG",
		"support": "补给 / 医疗 / 烟雾",
		"recon": "狙击 / 标记 / 信标",
	}.get(cid, "")


## 特勤处备战屋:启动时构建一次(悬空独立展厅,避免与地图碰撞;换图不受影响)
## 结构:16×9 混凝土房间 + 后墙武器架(5 把枪)/战术板/弹药箱/油桶/地图桌 + 暖色聚光 3 盏
## + 4 个 0.9m 兵种陈列台(士兵模型 + Label3D 兵种名/简介 + 台前兵种色条)
func _build_ready_room() -> void:
	_ready_room = Node3D.new()
	_ready_room.name = "ReadyRoom"
	_ready_room.position = Vector3(0, 80, 0)
	_ready_room.visible = false
	add_child(_ready_room)
	var room := _ready_room

	# ---- 材质 ----
	var mat_concrete := StandardMaterial3D.new()
	mat_concrete.albedo_color = Color(0.28, 0.31, 0.35)
	mat_concrete.roughness = 0.95
	var mat_metal := StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.45, 0.5, 0.55)
	mat_metal.roughness = 0.55
	mat_metal.metallic = 0.6
	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.36, 0.4, 0.42)
	mat_floor.roughness = 0.7
	mat_floor.metallic = 0.3
	var mat_dark := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.12, 0.13, 0.15)
	mat_dark.roughness = 0.9
	var mat_olive := StandardMaterial3D.new()
	mat_olive.albedo_color = Color(0.35, 0.38, 0.25)
	mat_olive.roughness = 0.85

	# ---- 地面(16×9) + 后墙 + 左右墙 + 顶部横梁 ----
	var floor_mi := MeshInstance3D.new()
	var floor_bm := BoxMesh.new()
	floor_bm.size = Vector3(16, 0.25, 9)
	floor_mi.mesh = floor_bm
	floor_mi.material_override = mat_floor
	floor_mi.position.y = -0.125
	room.add_child(floor_mi)
	for i in 4:  # 地面混凝土板接缝
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.06, 0.012, 9)
		line.mesh = lm
		line.material_override = mat_dark
		line.position = Vector3(-6.0 + i * 4.0, 0.006, 0)
		room.add_child(line)
	var mk_wall := func(w: float, h: float, d: float, x: float, y: float, z: float, mat: Material) -> void:
		var wi := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(w, h, d)
		wi.mesh = wm
		wi.material_override = mat
		wi.position = Vector3(x, y, z)
		room.add_child(wi)
	mk_wall.call(16, 5, 0.3, 0, 2.5, -4.65, mat_concrete)   # 后墙(内面 z=-4.5)
	mk_wall.call(0.3, 5, 9, -8.15, 2.5, 0, mat_concrete)    # 左墙
	mk_wall.call(0.3, 5, 9, 8.15, 2.5, 0, mat_concrete)     # 右墙
	for bz in [-3.0, 0.0, 3.0]:  # 顶部横梁
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(16, 0.35, 0.35)
		beam.mesh = bm
		beam.material_override = mat_metal
		beam.position = Vector3(0, 4.9, bz)
		room.add_child(beam)

	# ---- 暖色聚光灯(3 盏,悬于陈列台上方) ----
	for lx in [-3.0, 0.0, 3.0]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.85, 0.6)
		sl.light_energy = 2.6
		sl.spot_range = 12.0
		sl.spot_angle = 26.0
		sl.spot_attenuation = 1.2
		sl.shadow_enabled = true
		sl.position = Vector3(lx, 4.7, -2.2)
		sl.rotation.x = -PI / 2.0  # 垂直向下
		room.add_child(sl)

	# ---- 武器架(后墙:横杆 + 5 把枪,枪口朝上悬挂) ----
	var rack_bar := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(4.4, 0.08, 0.08)
	rack_bar.mesh = rb
	rack_bar.material_override = mat_metal
	rack_bar.position = Vector3(0, 2.35, -4.25)
	room.add_child(rack_bar)
	var rack_ids := ["m4", "awm", "m249", "mp5", "m1911"]
	for i in rack_ids.size():
		var gun := WeaponModels.build(rack_ids[i], false)
		gun.position = Vector3(-2.0 + i * 1.0, 2.35, -4.25)
		gun.rotation.x = PI / 2.0  # 模型前向 -Z → +Y,枪口朝上
		room.add_child(gun)

	# ---- 战术板(后墙右段:深色板 + 战术色点) ----
	var board := MeshInstance3D.new()
	var bom := BoxMesh.new()
	bom.size = Vector3(3.0, 2.0, 0.06)
	board.mesh = bom
	board.material_override = mat_dark
	board.position = Vector3(5.4, 2.6, -4.42)
	room.add_child(board)
	var dot_cols := [Color(0.0, 0.83, 1.0), Color(0.9, 0.5, 0.2), Color(0.62, 0.88, 0.54), Color(0.88, 0.63, 1.0), Color(1, 0.85, 0.2)]
	for i in dot_cols.size():
		var dot := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.14, 0.14, 0.02)
		dot.mesh = dm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = dot_cols[i]
		dmat.emission_enabled = true
		dmat.emission = dot_cols[i]
		dmat.emission_energy_multiplier = 1.2
		dot.material_override = dmat
		dot.position = Vector3(4.2 + (i % 3) * 0.7, 3.4 - floori(i / 3.0) * 0.7, -4.38)
		room.add_child(dot)

	# ---- 弹药箱堆(左墙) + 油桶堆(左墙圆柱) ----
	var crate_cols := [mat_olive, mat_dark, mat_metal]
	for i in 3:
		var crate := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.55, 0.4, 0.45)
		crate.mesh = cm
		crate.material_override = crate_cols[i % crate_cols.size()]
		crate.position = Vector3(-7.0, 0.2 + i * 0.42, 0.5 - (i % 2) * 0.4)
		room.add_child(crate)
	for i in 2:
		for j in 3:
			if j > 0 and i == 1:
				continue
			var drum := MeshInstance3D.new()
			var drum_m := CylinderMesh.new()
			drum_m.top_radius = 0.28
			drum_m.bottom_radius = 0.28
			drum_m.height = 0.85
			drum.mesh = drum_m
			var drum_mat := StandardMaterial3D.new()
			drum_mat.albedo_color = Color(0.5, 0.3, 0.18)
			drum_mat.roughness = 0.6
			drum_mat.metallic = 0.4
			drum.material_override = drum_mat
			drum.position = Vector3(-6.6 + i * 0.5, 0.425 + j * 0.87, -1.6)
			room.add_child(drum)

	# ---- 地图桌(房间前区:桌 + 战术地图薄板 + 无线电) ----
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(3.2, 0.1, 1.9)
	table.mesh = tm
	table.material_override = mat_metal
	table.position = Vector3(0, 0.78, 2.9)
	room.add_child(table)
	for lx2 in [-1.35, 1.35]:
		for lz2 in [-0.7, 0.7]:
			var leg := MeshInstance3D.new()
			var lm2 := BoxMesh.new()
			lm2.size = Vector3(0.12, 0.75, 0.12)
			leg.mesh = lm2
			leg.material_override = mat_dark
			leg.position = Vector3(lx2, 0.375, 2.9 + lz2)
			room.add_child(leg)
	var top_map := MeshInstance3D.new()
	var tmm := BoxMesh.new()
	tmm.size = Vector3(2.6, 0.025, 1.5)
	top_map.mesh = tmm
	var tmm2 := StandardMaterial3D.new()
	tmm2.albedo_color = Color(0.55, 0.72, 0.62)
	tmm2.roughness = 0.8
	top_map.material_override = tmm2
	top_map.position = Vector3(0, 0.845, 2.9)
	room.add_child(top_map)
	var radio := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.5, 0.22, 0.9)
	radio.mesh = rm
	var rm2 := StandardMaterial3D.new()
	rm2.albedo_color = Color(0.2, 0.24, 0.2)
	rm2.roughness = 0.7
	radio.material_override = rm2
	radio.position = Vector3(1.1, 0.98, 2.9)
	room.add_child(radio)

	# ---- 4 个兵种陈列台(一字排开:突击/工程/支援/侦察) ----
	var cls_ids := ["assault", "engineer", "support", "recon"]
	var podia := [Vector3(-3.0, 0, -2.4), Vector3(-1.0, 0, -2.4), Vector3(1.0, 0, -2.4), Vector3(3.0, 0, -2.4)]
	for i in 4:
		var cid: String = cls_ids[i]
		var cls = WeaponsData.C()[cid]
		var base: Vector3 = podia[i]
		# 0.9m 方台(深色台体 + 兵种色发光边框)
		var podium := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.9, 0.5, 0.9)
		podium.mesh = pm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.16, 0.18, 0.2)
		pmat.roughness = 0.6
		pmat.metallic = 0.4
		podium.material_override = pmat
		podium.position = base + Vector3(0, 0.25, 0)
		room.add_child(podium)
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(1.0, 0.03, 1.0)
		edge.mesh = em
		var em2 := StandardMaterial3D.new()
		em2.albedo_color = cls.color
		em2.emission_enabled = true
		em2.emission = cls.color
		em2.emission_energy_multiplier = 0.8
		em2.roughness = 0.4
		edge.material_override = em2
		edge.position = base + Vector3(0, 0.52, 0)
		room.add_child(edge)
		# 士兵模型(按兵种主武器,面向相机 +Z)
		var sm := SoldierModel.build_soldier("us", cls.primary, cid)
		sm.position = base + Vector3(0, 0.5, 0)
		sm.rotation.y = PI
		room.add_child(sm)
		# 兵种名 + 一句话简介(已按需求移除头顶文字,仅保留士兵与色条)
		# 台前地面兵种色条
		var strip := MeshInstance3D.new()
		var stm := BoxMesh.new()
		stm.size = Vector3(0.9, 0.03, 0.6)
		strip.mesh = stm
		var stm2 := StandardMaterial3D.new()
		stm2.albedo_color = cls.color
		stm2.emission_enabled = true
		stm2.emission = cls.color
		stm2.emission_energy_multiplier = 0.6
		stm2.roughness = 0.5
		strip.material_override = stm2
		strip.position = base + Vector3(0, 0.02, 1.2)
		room.add_child(strip)

	# 房间铭牌(后墙上方)
	var room_sign := Label3D.new()
	room_sign.font = UiTheme.font()
	room_sign.text = "特勤处 · 备战屋 READY ROOM"
	room_sign.font_size = 42
	room_sign.pixel_size = 0.012
	room_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	room_sign.no_depth_test = true
	room_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_sign.position = Vector3(0, 4.35, -4.28)
	room_sign.modulate = Color(0.0, 0.83, 1.0)
	room.add_child(room_sign)


## 主菜单编队战斗姿势(站姿警戒/低姿/侧向警戒/跪姿据枪)
func _pose_menu_soldier(sm: Node3D, cid: String) -> void:
	var rig: Node3D = sm.get_meta("rig")
	var upper: Node3D = sm.get_meta("upper")
	var leg_l: Node3D = sm.get_meta("leg_l")
	var leg_l_knee: Node3D = sm.get_meta("leg_l_knee")
	var leg_r: Node3D = sm.get_meta("leg_r")
	var leg_r_knee: Node3D = sm.get_meta("leg_r_knee")
	match cid:
		"assault":
			rig.rotation.x = 0.12          # 站姿警戒持枪
		"engineer":
			rig.rotation.x = 0.3           # 低姿持枪待命
			upper.rotation.y = -0.12
		"support":
			upper.rotation.y = 0.4         # 侧向警戒
			rig.rotation.x = 0.16
		"recon":
			leg_l.rotation.x = 1.25        # 跪姿据枪(左膝立,右膝跪)
			leg_l_knee.rotation.x = -1.25
			leg_r.rotation.x = -0.5
			leg_r_knee.rotation.x = -1.45
			rig.rotation.x = -0.05
			upper.rotation.x = 0.08
			sm.position.y -= 0.34


func _go_fullscreen() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## ============ 战役模式启动辅助 ============
## 幂等启动当前章节:game.gd 战役分支若已调 start_chapter 则跳过,否则补调(重试/下一章均生效)
func _ensure_campaign_started() -> void:
	if G.campaign == null or G.campaign_pending_id == "":
		return
	if not G.campaign.running or G.campaign.chapter_id != G.campaign_pending_id:
		G.campaign.start_chapter(G.campaign_pending_id)


func _on_resize() -> void:
	if _vm_viewport != null:
		_vm_viewport.size = get_viewport().get_visible_rect().size


func _unhandled_input(event: InputEvent) -> void:
	if not G.input_sys.is_locked():
		return
	if event is InputEventMouseMotion:
		G.input_sys.mouse_dx += event.relative.x
		G.input_sys.mouse_dy += event.relative.y
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			G.input_sys.wheel += 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			G.input_sys.wheel -= 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# 焦点丢失(等价于指针锁定丢失)→ 暂停
		if G.state == "playing" and not G.paused:
			_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func _pause() -> void:
	G.paused = true
	G.input_sys.unlock()
	_menus.show_pause(true)


## ============ 画质选项应用(对应 applyGraphics) ============
func apply_graphics() -> void:
	var s: Dictionary = G.settings
	var vp := get_viewport()
	# 分辨率缩放 + 各向异性过滤(强制应用,避免预设覆盖)
	if OS.has_feature("web"):
		vp.scaling_3d_scale = s.scale  # Web 端使用动态缩放
	else:
		vp.scaling_3d_scale = 1.0      # Windows 端强制全分辨率
	if s.has("aniso") and s.aniso > 0:
		vp.anisotropic_filtering_level = s.aniso
	# 阴影
	if G.sun != null:
		G.sun.shadow_enabled = s.shadows > 0
		RenderingServer.directional_shadow_atlas_set_size(int(s.shadows) if s.shadows > 0 else 1024, true)
		if OS.has_feature("web"):
			G.sun.shadow_bias = 0.09
			G.sun.shadow_normal_bias = 0.35
			G.sun.directional_shadow_max_distance = 80
		else:
			G.sun.shadow_bias = 0.1
			G.sun.shadow_normal_bias = 1.0
	# TAA(WebGL 兼容模式下会产生条纹伪影,关闭)
	if OS.has_feature("web") and G.world_env != null and G.world_env.environment != null:
		G.world_env.environment.sdfgi_enabled = false
		G.world_env.environment.ssil_enabled = false
		G.world_env.environment.ssr_enabled = false
		G.world_env.environment.glow_enabled = false
	# SSAO / FXAA
	if G.world_env != null and G.world_env.environment != null:
		G.world_env.environment.ssao_enabled = s.ssao
	# 抗锯齿:内置 MSAA 已在 project.godot 关闭;高档用 TAA,低档用自定义 FXAA 着色器(互斥)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = GraphicsQuality.current_level >= GraphicsQuality.Level.HIGH
	if _fxaa_rect != null:
		_fxaa_rect.visible = s.fxaa
	# 垂直同步(0=关 1=开 2=自适应;headless/Web 无操作窗口时跳过)
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var vsync: int = int(s.get("vsync", 1))
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ADAPTIVE if vsync == 2 else (DisplayServer.VSYNC_ENABLED if vsync == 1 else DisplayServer.VSYNC_DISABLED))
	# 粒子
	if G.effects != null:
		G.effects.quality = s.particles
	# 雾效
	if G.world_env != null and G.world_env.environment != null and G.world_env.environment.fog_enabled:
		G.world_env.environment.fog_depth_begin = G.fog_base[0] * s.fog
		G.world_env.environment.fog_depth_end = G.fog_base[1] * s.fog


## ============ 主循环(对应 loop) ============
func _process(dt_raw: float) -> void:
	var dt := minf(dt_raw, 0.05)

	# 特勤处备战屋状态机:菜单态显示房间 + 相机缓慢左右摆动;非菜单态隐藏(相机交还战斗/部署逻辑)
	if _ready_room != null:
		_ready_room.visible = G.state == "menu"
		if _ready_room.visible:
			_room_cam_yaw += dt * 0.22
			var sway := sin(_room_cam_yaw) * 0.55
			var sway2 := cos(_room_cam_yaw * 0.7) * 0.35
			_camera.global_position = _room_cam_base + Vector3(sway, 0, 0)
			_camera.look_at(_room_cam_look + Vector3(sway2, 0, 0), Vector3.UP)
			_camera.fov = 50
		elif G.state == "deploy":
			# 部署界面背景与旧版一致:地图上空视角(友军出生点)
			var anchor := Vector3.ZERO
			if not G.spawns["us"].is_empty():
				anchor = G.spawns["us"][0]
			var ah: float = G.ground_h.call(anchor.x, anchor.z) if G.ground_h.is_valid() else 0.0
			_camera.global_position = Vector3(anchor.x + 3.1, ah + 1.55, anchor.z + 5.0)
			_camera.look_at(Vector3(anchor.x + 0.25, ah + 1.0, anchor.z), Vector3.UP)

	var active: bool = (G.state == "playing" or G.state == "dead") and not G.paused

	# 暂停键
	if Input.is_action_just_pressed("pause"):
		if G.paused:
			_menus.on_resume.call()
		elif G.state == "playing":
			_pause()

	if active:
		if G.player.alive:
			if _dbg_prone:
				G.player.prone = true
			if _dbg_lookdown:
				G.player.pitch = -1.3
			if _dbg_slide:
				G.player.sprint_toggled = true
				if Engine.get_process_frames() % 120 == 0 and G.player.slide_t <= 0:
					G.player.slide_t = 0.85
					G.player.slide_dir = Vector2(0, -1)
			# 战役过场:相机由 campaign 接管(不跑玩家相机/输入),结束交还
			if not (G.campaign != null and G.campaign.is_cutscene()):
				G.player.update_player(dt)
		G.bot_manager.update_bots(dt)
		_effects.update_effects(dt)
		WorldBuilder.update_map(dt)
		G.game.update_game(dt)
		if G.campaign != null and G.campaign.running:
			G.campaign.update(dt)
		for v in G.vehicles:
			v.update_vehicle(dt)
		for a in G.aircraft:
			a.update_aircraft(dt)
	# 死亡倒地镜头
	if G.state == "dead":
		_camera.global_position.y = maxf(0.32, _camera.global_position.y - dt * 1.4)
		_camera.rotation.z = minf(0.55, _camera.rotation.z + dt * 0.5)
	# 玩家身体模型:第一人称显示双腿 + 躯干/双肩(upper 顶面 1.35m 低于站立眼高
	# 1.62m,平视不穿模;低头/蹲姿可见胸口属正常);阵亡倒地与载具驾驶隐藏;
	# 战役过场由 campaign 控制可见性,跳过覆盖。
	# --test-pose 姿势外视调试除外(相机移到侧后方观察全身)。
	if G.player != null and G.player.body != null \
			and not (G.campaign != null and G.campaign.is_cutscene()):
		G.player.body.visible = _dbg_pose or (G.player.alive and G.player.vehicle == null)
	# 姿势外部观察:--test-pose(传送到空旷点,把主相机架到侧后方看向身体)
	if _dbg_pose and G.player != null:
		if G.player.pos.length() > 50 or absf(G.player.yaw) > 0.01:
			G.player.pos = Vector3(0, 0, 0)
			G.player.yaw = 0.0
			G.player.pitch = 0.0
		var pp: Vector3 = G.player.pos
		var up2: Node3D = G.player.body.get_meta("upper")
		if up2 != null:
			up2.visible = true  # 外视调试看全身(第一人称默认即显示躯干,此处兜底)
		_camera.global_position = pp + Vector3(3.0, 2.6, 3.0)
		_camera.look_at(pp + Vector3(0, 0.4, 0), Vector3.UP)
	if G.state == "playing" or G.state == "dead":
		_hud.update_hud(dt)

	# 视角模型相机同步(仅同步旋转;位置恒为原点)
	_vm_camera.global_transform = Transform3D(_camera.global_transform.basis, Vector3.ZERO)
	# 枪口手电:仅黑夜地图 + 步战存活时启用(驾驶中关闭);光源挂枪口(每帧跟随当前武器枪口)
	if _flashlight != null:
		var nm: bool = MapsData.M().has(G.current_map) and MapsData.M()[G.current_map].night
		_flashlight.visible = nm and (G.state == "playing" or G.state == "dead") \
			and G.player != null and G.player.alive and G.player.vehicle == null
		if _flashlight.visible:
			var gun = G.player.gun()
			if gun != null:
				_flashlight.global_position = gun.muzzle_world_main()
	# 视角模型光照同步场景(太阳方向/颜色/强度 + 环境光,避免视模型与场景脱节)
	if G.sun != null:
		_vm_sun.rotation = G.sun.rotation
		_vm_sun.light_color = G.sun.light_color
		# 建筑阴影互动:相机被建筑遮挡阳光时,第一图层手臂/枪械同步变暗
		_sun_occ_t += dt
		if _sun_occ_t >= 0.12:
			_sun_occ_t = 0.0
			_sun_blocked = false
			if (G.state == "playing" or G.state == "dead") and G.player != null and G.player.alive:
				_sun_blocked = Utils.raycast_world(_camera.global_position, -G.sun_dir, 150.0) != null
		_vm_sun.light_energy = Utils.damp(_vm_sun.light_energy,
			G.sun.light_energy * (0.12 if _sun_blocked else 1.0), 6, dt)
	if G.world_env != null and G.world_env.environment != null:
		var se := G.world_env.environment
		_vm_e.ambient_light_color = se.ambient_light_color
		_vm_e.ambient_light_energy = se.ambient_light_energy

	# 性能自适应:持续低帧则降级(关 SSAO/阴影/降分辨率)
	if not _degraded and G.state == "playing":
		_fps_acc += dt_raw
		_fps_n += 1
		if _fps_acc >= 1:
			var fps: float = _fps_n / _fps_acc
			_fps_acc = 0
			_fps_n = 0
			if fps < 42:
				_fps_low_t += 1
			else:
				_fps_low_t = 0
			if _fps_low_t >= 4:
				_degraded = true
				if OS.has_feature("web"):
					# Web 端性能有限,降级保帧率
					G.settings.ssao = false
					G.settings.shadows = 0
					G.settings.scale = 0.8
				else:
					# Windows 端只关 SSAO,不降分辨率(避免模糊)
					G.settings.ssao = false
				apply_graphics()

	if _validate:
		_validate = false
		print("[VALIDATE] 首帧渲染完成 state=", G.state)
		get_tree().quit()

	# 内存监控:--memwatch(每 5 秒打印帧率/静态内存/对象计数)
	if _memwatch:
		_memwatch_t += dt_raw
		_memwatch_n += 1
		if _memwatch_t >= 5.0:
			print("[MEM] fps=%.1f static=%.1fMB nodes=%d resources=%d objects=%d orphans=%d state=%s" % [
				_memwatch_n / _memwatch_t,
				OS.get_static_memory_usage() / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				G.state])
			_memwatch_t = 0.0
			_memwatch_n = 0

	# 截图测试:--screenshot <帧号> <输出路径>
	if _shot_frame > 0:
		_shot_frame -= 1
		if _shot_frame == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("[SHOT] 已保存截图: ", _shot_path)
			get_tree().quit()
