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
var _cine_rect: ColorRect      # 电影级后期(自定义着色器:微对比/泛光/颗粒/暗角;色差已移除)
# ---- [8/10] 动态质量系统:帧时间超标自动逐级降级(SSR→MSAA→阴影→后期→泛光),稳定后恢复 ----
var _dq_level := 0
var _dq_t := 0.0
var _dq_n := 0
var _dq_stable_t := 0.0
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
# ---- QA 性能基准:--perf-test(每秒采样 FPS/帧时间/内存) ----
var _perf_on := false
var _perf_t := 0.0
var _perf_min := 0.0
var _perf_max := 0.0
# ---- [8/10] 完整性能基准:--bench <帧数>(采集帧时间/1%Low/CPU/GPU/DrawCalls/Objects/内存,到帧写报告) ----
var _bench_on := false
var _bench_target := 0
var _bench_n := 0
var _bench_fts := PackedFloat64Array()      # 帧时间 ms
var _bench_proc := PackedFloat64Array()     # process 时间 ms
var _bench_phys := PackedFloat64Array()     # physics 时间 ms
var _bench_dc := PackedInt32Array()         # draw calls
var _bench_prims := PackedInt64Array()      # primitives
var _bench_objs := PackedInt32Array()       # 渲染对象数
var _bench_nodes := PackedInt32Array()      # 场景节点数
var _bench_mem := PackedFloat64Array()      # 静态内存 MB
var _bench_label := ""                      # 场景标签(文件名用)
var _bench_dc_last := 0                     # [PERF 9/6] 渲染统计 30 帧缓存(免每帧 GPU flush)
var _bench_prims_last := 0
var _bench_objs_last := 0
# ---- QA 帧时间尖峰压测:--perf-stress <帧数>(GUI 实机采样:帧时间 p95/尖峰计数;到帧自动退出) ----
var _ps_stress_on := false
var _ps_stress_target := 0
var _ps_stress_n := 0
var _ps_times := PackedFloat64Array()
var _ps_gt250 := 0
var _ps_gt100 := 0
# ---- GPU 保护档自适应 v2:帧时间尖峰检测(防驱动级挂起) ----
var _ps_win_t := 0.0
var _ps_win_n := 0
var _ps_enter_t := -1e9
# ---- [PERF] 载具/飞机更新分级计时(--bench-veh;性能审计) ----
var _bench_veh_on := false
var _bv_t := 0.0
var _bv_n := 0
# ---- [PERF] Debug 性能监控(--perf-monitor 或 F3 切换):实时 FPS/帧时间/CPU/物理/AI/DrawCall/对象/内存/显存 ----
var _perf_mon := false
var _perf_layer: CanvasLayer = null
var _perf_label: Label = null
var _perf_tick := 0.0
var _perf_f3_held := false
var _ai_time_us := 0.0          # 平滑后的 AI(bot) 更新耗时(µs)
# ---- [PERF] 子系统分项计时(--bench-sys;定位帧尖峰来源) ----
var _bsys_on := false
var _bsys := {}                 # name -> { t(累计µs), max(单帧µs), n }
var _bsys_n := 0
var _sun_occ_t := 0.0
var _sun_blocked := false
var _flashlight: SpotLight3D
var _ready_room: Node3D                    # 特勤处备战屋(主菜单背景 3D 战争房间)
var _room_cam_yaw := 0.0                   # 房间相机左右摆动相位
var _room_cam_base := Vector3(0, 81.55, 7.1)   # 房间相机基准位(房间位于 (0,80,0))
var _room_cam_look := Vector3(0, 81.1, -1.4)   # 房间相机注视点(四陈列台一排)


func _ready() -> void:
	print("[PERF] main._ready 开始于 %.2fs" % (Time.get_ticks_msec() / 1000.0))
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
		# 默认关垂直同步:vsync 开启会把帧率锁到显示器刷新率,120+ 帧目标无从谈起;
		# 存档里显式设置过的用户保留其选择
		G.settings["vsync"] = G.settings.get("vsync", 0)
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
	_camera.cull_mask = 0xFFFFF   # 主相机渲染全部视觉层(第一人称身体在 layer 2)
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
	_vm_viewport.msaa_3d = Viewport.MSAA_2X  # 手臂/枪械抗锯齿(独立世界;4X→2X 降低视角模型采样开销)
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
	# ---- PCSS 阴影软化(自写后处理:屏幕空间 PCF 边缘软化,层 3.5,在 FXAA 之下) ----
	var pcss_layer := CanvasLayer.new()
	pcss_layer.layer = int(3.5)
	add_child(pcss_layer)
	var pcss_rect := ColorRect.new()
	pcss_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	pcss_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pcss_mat := ShaderMaterial.new()
	pcss_mat.shader = load("res://src/fx/pcss_soft.gdshader")
	pcss_rect.material = pcss_mat
	pcss_layer.add_child(pcss_rect)
	# 阴影基础质量:软模糊 + 高分辨率阴影图集 + 32bit 深度(use_16_bits=false,
	# 更高的深度精度可显著减少阴影边缘锯齿/闪烁与 shadow acne)
	if G.sun != null:
		G.sun.shadow_blur = 1.15
		RenderingServer.directional_shadow_atlas_set_size(4096, false)
	# ---- 电影级后期(自定义着色器;层 4.5:3D/FXAA 之上,HUD(5) 之下,设置可开关) ----
	var cine_layer := CanvasLayer.new()
	cine_layer.layer = int(4.5)
	add_child(cine_layer)
	_cine_rect = ColorRect.new()
	_cine_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cine_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cine_mat := ShaderMaterial.new()
	cine_mat.shader = load("res://src/fx/cinematic.gdshader")
	_cine_rect.material = cine_mat
	_cine_rect.visible = bool(G.settings.get("cinema", true))
	cine_layer.add_child(_cine_rect)
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
	var pm := PortalManager.new()
	add_child(pm)
	G.portal = pm
	var pl := Player.new()
	add_child(pl)
	G.player = pl
	# ---- 高倍率狙击镜 PIP 渲染器(独立 Optic Scope Camera + 圆形 Render Target 合成) ----
	var scope_sys = load("res://src/player/optic_scope.gd").new()
	add_child(scope_sys)
	G.scope = scope_sys
	# ---- 侦察兵无人侦察机(独立相机接管 + 150m 圆形侦察范围) ----
	var drone_sys = load("res://src/player/recon_drone.gd").new()
	add_child(drone_sys)
	G.drone = drone_sys
	# ---- 实时 3D 战场部署系统(死亡后高空观察部署;征服/突破启用) ----
	var dep := BattleDeploymentManager.new()
	add_child(dep)
	G.deployment = dep
	_hud = HUD.new()
	add_child(_hud)
	_menus = Menus.new()
	add_child(_menus)
	# 门户模式提示(模式控制器经 G.portal.hint 发出,接现有 HUD 提示条)
	G.portal.portal_hint.connect(func(t: String):
		if G.hud != null:
			G.hud.hint(t))
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
	# 实时 3D 部署:兵种/武器与 3D 战场同屏一体,「部 署」按钮 = 确认部署到悬停/基地
	_menus.on_deploy3d = func(class_id: String, loadout):
		_go_fullscreen()
		if G.deployment != null and G.deployment.active:
			G.deployment.confirm_deploy_ui()
		elif G.deployment != null:
			G.deployment.enter_match_deploy()
		else:
			G.game.deploy(class_id, loadout)
	_menus.on_redeploy = func():
		# 大逃杀:首次阵亡重部署机会(R 键/死亡屏按钮同一入口 → 乘小直升机重返战场)
		if G.mode == "br" and G.br != null and G.br.has_method("try_redeploy_player") \
				and G.br.try_redeploy_player():
			return
		# 实时 3D 战场部署(征服/突破):死亡后点击部署点/空格直接部署
		if G.deployment != null and G.deployment.active:
			G.deployment.confirm_redeploy()
			return
		_menus.hide_all()
		G.game.redeploy()
	_menus.on_resume = func():
		_go_fullscreen()
		_menus.close_settings()  # 暂停中打开设置后按 Esc 恢复,一并收起设置屏
		_menus.show_pause(false)
		G.paused = false
		G.input_sys.lock()
	_menus.on_quit = func():
		# 门户对局退出到主菜单:先收尾模式(防御判空)。否则 active 残留 → 下次 start_mode
		# 触发 portal_manager 防御 end_match({}) → TDM 空记分板判负 → 重进即显示"战败"
		# aborted 标记:结算屏优先显示"已退出对局",不判胜负
		if G.portal != null and G.portal.active != null:
			G.portal.end_match({ "aborted": true })
		_menus.hide_all()
		G.state = "menu"
		G.paused = false
		_hud.hide_screen("hud")
		_hud.clear_campaign_ui()  # 回主菜单:清战役 UI 残留(目标/字幕/点名卡/箭头)
		if G.campaign != null:
			G.campaign.abort()   # 清理战役封锁带/路点/破坏物(菜单态无残留)
		G.input_sys.unlock()
		print("[PERF] 开始构建菜单 UI %.2fs" % (Time.get_ticks_msec() / 1000.0))
		_setup_menu_scene()
		print("[PERF] 菜单 UI 构建完成 %.2fs" % (Time.get_ticks_msec() / 1000.0))
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
	print("[PERF] 菜单显示于 %.2fs,开始构建菜单背景城市" % (Time.get_ticks_msec() / 1000.0))
	WorldBuilder.build_world(G.world_root, "city")
	print("[PERF] 菜单背景城市构建完成于 %.2fs" % (Time.get_ticks_msec() / 1000.0))
	_build_ready_room()  # 特勤处备战屋:主菜单背景 3D 战争房间(高空展厅,四兵种陈列)
	print("[PERF] 备战屋完成于 %.2fs" % (Time.get_ticks_msec() / 1000.0))
	GraphicsQuality.load_config()
	# 启动画质:存档含细项设置(手动开关过)时保留用户开关,只套档位强度;否则完整套用预设
	if GraphicsQuality.has_custom_settings():
		GraphicsQuality.apply_level_strengths()
	else:
		GraphicsQuality.apply_preset(GraphicsQuality.current_level)  # 启动即应用硬件检测/存档画质预设(无条件)
	# QA 性能基准:--preset <low|medium|high|ultra>(覆盖硬件检测/存档档位,不写回存档)
	var ua0 := OS.get_cmdline_user_args()
	var pidx := ua0.find("--preset")
	if pidx >= 0 and ua0.size() > pidx + 1:
		var lv: int = { "low": 0, "medium": 1, "high": 2, "ultra": 3 }.get(String(ua0[pidx + 1]).to_lower(), -1)
		if lv >= 0:
			GraphicsQuality.apply_preset(lv)
			print("[PERF] --preset 覆盖画质档位: ", GraphicsQuality._level_name(lv))
	_setup_menu_scene()  # 主界面背景:四兵种编队
	get_tree().root.size_changed.connect(_on_resize)
	if _validate:
		print("[VALIDATE] 初始化完成,世界已构建: 碰撞体=", G.colliders.size(), " 旗帜=", G.flags.size())
	# 无头游玩测试:--test-play [mode] [map]
	var ua := OS.get_cmdline_user_args()
	if ua.has("--test-play"):
		print("[TEST] 收到 --test-play, args=", ua)
	if ua.has("--screenshot"):
		var sidx := ua.find("--screenshot")
		if ua.size() > sidx + 2:
			_shot_frame = int(ua[sidx + 1])
			_shot_path = ua[sidx + 2]
		else:
			print("[SHOT] 用法: --screenshot <帧号> <输出路径>(参数缺失,已忽略)")
	if ua.has("--test-play"):
		var idx := ua.find("--test-play")
		var mode: String = ua[idx + 1] if ua.size() > idx + 1 else "conquest"
		# 模式名校验:非法模式(如把地图名误当模式参数)时打印用法说明并忽略 --test-play,不中止
		if mode != "conquest" and mode != "breakthrough" and mode != "campaign" and mode != "tdm" and mode != "br":
			print("[TEST] 警告:未知游玩模式 \"", mode, "\"(可用: conquest / breakthrough / campaign / tdm / br),已忽略 --test-play")
		else:
			# 地图名解析:跳过以 -- 开头的 flag 参数(如 --test-rpg/--quit-after/--screenshot),
			# 首个非 flag 参数若为合法地图 id 则采用,否则回退随机并提示。
			# 绝不带无效 id 进入世界构建(防中途中止与悬空 Flag 引用)
			var map_arg := "random"
			var map_warn := ""
			for i in range(idx + 2, ua.size()):
				var a: String = ua[i]
				if a.begins_with("--"):
					continue
				if MapsData.M().has(a):
					map_arg = a
				else:
					map_warn = a
				break
			if not map_warn.is_empty():
				print("[TEST] 警告:未知地图名 \"", map_warn, "\"(可用: ", MapsData.M().keys(), "),回退随机地图")
			G.sel_maps[mode] = map_arg
			_menus.hide_all()
			G.game.start_match(mode)
			# 防御:地图未就绪(如 br_valley 缺失)时开局中止(state 仍为 menu),跳过部署防空出生点崩溃
			if not ua.has("--no-deploy") and G.state != "menu":
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
	# 性能剖析:--test-perf(配合 --test-play):部署后采样 8s FPS/draw calls/显存
	if ua.has("--test-perf"):
		_run_perf_probe()
	# 载具战地式视角 QA:--test-vehicle <type>(配合 --test-play conquest)
	# 自动上车 → 第三人称/开炮 → 右键 ADS 目镜 → 观察位(AA 机枪开火),分阶段截图
	if ua.has("--test-vehicle"):
		var vidx := ua.find("--test-vehicle")
		var vtype_qa: String = ua[vidx + 1] if ua.size() > vidx + 1 else "tank"
		_run_vehicle_qa(vtype_qa)
	# 吉普乘客位 QA:--test-jeep-passenger(配合 --test-play conquest)
	# NPC 司机登车起步 → 玩家上车应坐乘客位(不顶司机)+强制第一人称+可开枪
	if ua.has("--test-jeep-passenger"):
		_run_jeep_passenger_qa()
	# 第一人称腰射枪位截图:--test-hip-shot(配合 --test-play,可前置 --test-gun <id>)
	if ua.has("--test-hip-shot"):
		_run_hip_shot()
	# 主菜单截图:--test-menu-shot(不部署,等背景城市就绪后截主菜单整屏)
	if ua.has("--test-menu-shot"):
		_run_menu_shot()
	# ADS 三点一线批量验证:--test-ads-line <all|枪id>(配合 --test-play)
	# 每把枪满镜后把 muzzle 世界坐标 unproject 到屏幕,量化枪口与准星(屏幕中心)偏差
	if ua.has("--test-ads-line"):
		var alidx := ua.find("--test-ads-line")
		var alid: String = ua[alidx + 1] if ua.size() > alidx + 1 else "all"
		_run_ads_line(alid)
	# 空中载具建模 QA:--test-air <heli|jet>(悬浮多角度认证,不进飞行逻辑)
	if ua.has("--test-air"):
		var aidx := ua.find("--test-air")
		var atype: String = ua[aidx + 1] if ua.size() > aidx + 1 else "heli"
		_run_aircraft_qa(atype)
	# 车底专项 QA:--test-belly(配合 --test-play)
	# 全部 6 台载具悬空,正下方仰拍 + 斜下 45° × 4 + 远景,并数值扫描
	# 穿透车体底面(局部 y<-0.05)的网格节点 —— 定位"车底多出一截"
	if ua.has("--test-belly"):
		_run_belly_qa()
	# GLB 解剖:--test-xray <vehicle>(headless 打印节点变换/网格 AABB)
	if ua.has("--test-xray"):
		var xidx := ua.find("--test-xray")
		var xid: String = ua[xidx + 1] if ua.size() > xidx + 1 else "tank"
		_run_veh_xray(xid)
	# 全导轨枪械认证:--test-rail-all(配合 --test-play)
	# 16 把带导轨枪逐把:检视动画中段拍全枪照 + 满 ADS 拍实战照
	# 认证点:顶轨/侧轨方向沿枪管、不横穿、不悬空、不与机匣穿模
	if ua.has("--test-rail-all"):
		_run_rail_certify()
	# 枪械 X 光认证:--test-gun-xray <id|all>(配合 --test-play)
	# 枪模单独悬空(无地形/HUD/视角模型干扰),独立相机环绕 5 机位:
	# top(正上方看顶轨齿向)/left34/right34(斜上 3/4)/left/right(正侧看侧轨)
	# 单把模式额外:拍无改装对照 + 打印超宽网格节点(定位横向穿模零件)
	if ua.has("--test-gun-xray"):
		var gxidx := ua.find("--test-gun-xray")
		var gxid: String = ua[gxidx + 1] if ua.size() > gxidx + 1 else "all"
		_run_gun_xray(gxid)
	# NPC 士兵 GLB 管线认证:--test-npc(配合 --test-play)
	# 结构打印(动画/骨骼名) + 悬空 4 姿态截图(Idle/Walk/Run/Death) + 战场实况
	if ua.has("--test-npc"):
		_run_npc_check()
	# 玩家第一人称身体 + 阴影认证:--test-pbody(配合 --test-play)
	# ①低头俯视真实腿部 ②侧上视角人形阴影 ③切枪后阴影武器轮廓变化
	if ua.has("--test-pbody"):
		_run_pbody_check()
	# 蹲姿游戏内实拍认证:--test-squat(配合 --test-play)
	# 玩家真实蹲下 + 强制最近 NPC 蹲下,近景多机位截真实游戏画面(不做悬空摆拍)
	if ua.has("--test-squat"):
		_run_squat_check()
	# 死亡布娃娃 + 趴姿贴地 + 蹲走/匍匐步态认证:--test-death(配合 --test-play)
	if ua.has("--test-death"):
		_run_death_check()
	# 全武器 ADS 互斥冒烟测试:--test-scope-all(配合 --test-play)
	# 逐把装配所有武器并强制满 ADS,验证:高倍镜启用 PIP 且不隐藏枪身/主相机不缩放,
	# 普通枪/红点/全息/低倍镜绝不误启 PIP,各枪 ScopeEye/Reticle 构建无缺件。
	if ua.has("--test-scope-all"):
		await get_tree().create_timer(1.0).timeout
		var wids: Array = WeaponsData.W().keys()
		var fails: Array = []
		var scope_ok := 0
		var normal_ok := 0
		for wid in wids:
			var old = G.player.gun()
			var ng = Gun.new(String(wid), G.player)
			ng.draw_t = 1.0
			if old != null and old.group != null and is_instance_valid(old.group):
				G.vm_camera.remove_child(old.group)
				old.group.queue_free()
			G.player.guns[G.player.gun_index] = ng
			G.vm_camera.add_child(ng.group)
			ng.equip()
			G.player.gun_index = clampi(G.player.gun_index, 0, G.player.guns.size() - 1)
			Input.action_press("ads")
			ng.ads_amount = 1.0
			await get_tree().create_timer(0.18).timeout
			await get_tree().process_frame
			var ng2 = G.player.gun()
			var ok := true
			var reason := ""
			if ng2.def.scope:
				if G.scope == null or not G.scope.active:
					ok = false
					reason = "scope_pip_inactive"
				elif not ng2.group.visible:
					ok = false
					reason = "gun_hidden"
				else:
					var eye: Node3D = ng2.group.get_meta("scope_eye", null)
					if eye == null or not is_instance_valid(eye) or not eye.is_visible_in_tree():
						ok = false
						reason = "missing_scope_eye"
				if ok:
					scope_ok += 1
			else:
				if G.scope != null and G.scope.active:
					ok = false
					reason = "pip_should_be_off"
				else:
					normal_ok += 1
			if not ok:
				fails.append(String(wid) + ":" + reason)
				push_error("[SCOPE-ALL] %s failed: %s" % [wid, reason])
			else:
				print("[SCOPE-ALL] ok %s scope=%s fov=%.1f" % [wid, ng2.def.scope, G.camera.fov])
			Input.action_release("ads")
			ng2.ads_amount = 0.0
			await get_tree().process_frame
		print("[SCOPE-ALL] done weapons=%d scope_ok=%d normal_ok=%d fails=%d %s" % [
			wids.size(), scope_ok, normal_ok, fails.size(), str(fails)])
		get_tree().quit()
		return
	# 出生点诊断:--test-spawns(配合 --test-play)
	if ua.has("--test-spawns"):
		await get_tree().create_timer(1.0).timeout
		print("[SPAWNS] map=%s size=%s bounds=%.1f world_size=%.1f" % [G.current_map, MapsData.M()[G.current_map].size, G.bounds, G.world_size])
		print("[SPAWNS] us=%s" % str(G.spawns["us"]))
		print("[SPAWNS] ru=%s" % str(G.spawns["ru"]))
		print("[SPAWNS] vehicle_spawns=%s" % str(G.vehicle_spawns))
		get_tree().quit()
		return
	# [8/10] 车内视角诊断:--test-tank [gunner|driver] 自动进入最近坦克(验证内构/乘员位/炮镜)
	if ua.has("--test-tank"):
		var tt_crew: int = 1 if (ua.size() > ua.find("--test-tank") + 1 and ua[ua.find("--test-tank") + 1] == "gunner") else 0
		await get_tree().create_timer(1.5).timeout
		var best_v = null
		var best_d := 1e9
		for v in G.vehicles:
			if v.dead or v.type != "tank" or v.driver != null:
				continue
			var d: float = v.pos.distance_to(G.player.pos)
			if d < best_d:
				best_d = d
				best_v = v
		if best_v != null:
			G.player.enter_vehicle(best_v)
			G.player._veh_tp = false
			# 指定乘员位:gunner → 玩家坐到炮手位(驾驶位空出)
			if tt_crew == 1:
				best_v.driver = null
				best_v.gunner = G.player
				G.player._veh_crew = 1
			# 控制变量:固定车位置与朝向(消除随机对截图验证的影响)
			best_v.pos = Vector3(0, 0, 0)
			best_v.yaw = PI
			best_v.turret_yaw = 0.0
			if tt_crew == 1:
				Input.action_press("ads")  # 炮手位模拟按住炮镜(真实按键路径)
			print("[TANK-TEST] 已进入坦克 crew=", tt_crew, " pos=", best_v.pos)
		else:
			print("[TANK-TEST] 未找到可用坦克")
	# ADS 截图诊断:--test-ads-capture [--test-optics <reddot|holo|none>](配合 --test-play)
	# QA 用途:满 ADS 定帧截取 视角模型 SubViewport + 全屏画面,检查镜罩/枪身隐藏/FOV 放大
	# 置于 --test-gun 之后:同时传 --test-gun 时,截图作用于切换后的枪(如狙击验证)
	if ua.has("--test-ads-capture"):
		await get_tree().create_timer(1.0).timeout
		if G.player.guns.is_empty():
			print("[ADS-CAP] 玩家无武器(需配合 --test-play 部署),已跳过")
		else:
			var gid: String = G.player.guns[0].id
			var opt_cfg := { "reddot": "opt_reddot", "holo": "opt_holo" }
			var opt_arg := "none"
			if ua.has("--test-optics"):
				var oidx := ua.find("--test-optics")
				if ua.size() > oidx + 1 and opt_cfg.has(ua[oidx + 1]):
					opt_arg = ua[oidx + 1]
				else:
					print("[ADS-CAP] 无效 --test-optics 参数(可用: reddot / holo / none),回退 none")
			# 临时改装:备份现档 → 写入临时 optic → 重建枪实例(经 load_cfg 完整走改装管线,
			# 镜模型与 zoom_fov 均由枪实例读档后一并应用,最稳妥;截图后恢复原档)
			var cfg_path := "user://mods_%s.cfg" % gid
			var had_cfg: bool = FileAccess.file_exists(cfg_path)
			var orig_cfg: Dictionary = WeaponModsData.load_cfg(gid)
			if opt_arg != "none":
				var tmp_cfg: Dictionary = orig_cfg.duplicate()
				tmp_cfg["optic"] = opt_cfg[opt_arg]
				WeaponModsData.save_cfg(gid, tmp_cfg)
				var old_gun = G.player.gun()
				G.vm_camera.remove_child(old_gun.group)
				old_gun.group.queue_free()
				var ng := Gun.new(gid, G.player)
				G.player.guns[0] = ng
				G.vm_camera.add_child(ng.group)
				ng.equip()
			G.player.spawn_protect = 60  # 诊断期间免被打死(枪被收起则截图无意义)
			# player.gd 每帧用 Input.is_action_pressed 重算 ads_held,必须走真实输入管线(同 --test-ads)
			Input.action_press("ads")
			var g2 = G.player.gun()
			g2.ads_amount = 1.0          # 强制满 ADS(跳过插值,立即进入开镜态)
			await get_tree().create_timer(0.8).timeout  # 等 FOV 阻尼收敛 + 镜罩显现
			g2 = G.player.gun()
			# 诊断数值:目镜装点 y / 视角模型满 ADS 位 z(枪相对 vm_camera)/ 数据 ads_z
			print("[ADS-CAP] optic_y=%.4f cam_z=%.4f ads_z=%.4f" % [
				g2.def.sight_y, g2.group.position.z, g2.def.ads_z])
			print("[ADS-CAP] gun=%s optic=%s scope=%s zoom_fov=%.1f fov=%.1f ads=%.3f base_fov=%.1f" % [
				gid, opt_arg, g2.def.scope, g2.def.zoom_fov, G.camera.fov, g2.ads_amount,
				G.settings.fov + G.player.sprint_amount * 6 + (4 if G.player.tac_sprint > 0 else 0) + 7.0 * clampf(G.player.slide_t / 0.7, 0.0, 1.0)])
			if g2.def.scope:
				print("[ADS-CAP] scope_fov=%.2f scope_mag=%.2f" % [g2.scope_fov(), float(g2.def.scope_mag)])
			print("[ADS-CAP] viewport=root_rect=%s vm_viewport_size=%s vm_visible_rect=%s root_tex=%s" % [get_viewport().get_visible_rect().size, G.vm_viewport.size, G.vm_viewport.get_visible_rect().size, get_viewport().get_texture().get_size()])
			if G.scope != null and G.scope.has_method("debug_state"):
				print("[ADS-CAP] scope_pip=", G.scope.debug_state())
			# 火箭筒弹道等高线诊断:各档刻度像素位置必须全部落在可见画面内
			if G.hud != null and G.hud._crosshair != null and G.hud._crosshair.has_method("bal_debug"):
				print("[ADS-CAP] rpg_ballistic=", G.hud._crosshair.bal_debug())
			# 火箭筒 CLU 三档倍率(0×/2×/4×):镜内 FOV 与弹道等高线刻度都必须随倍率重算
			if gid == "rpg" and G.hud != null:
				var keep_zoom: int = g2.zoom_idx
				for zi in Gun.RPG_ZOOM_LEVELS.size():
					g2.zoom_idx = zi
					# 镜内 FOV → 镜片投影 → HUD 分划为逐帧链式采样,等其收敛再读数
					await get_tree().create_timer(0.2).timeout
					print("[ADS-CAP] rpg_zoom=%s scope_fov=%.1f %s" % [
						g2.zoom_label(), g2.scope_fov(), G.hud._crosshair.bal_debug()])
				g2.zoom_idx = keep_zoom
				await get_tree().create_timer(0.2).timeout
				# 滚轮通路验证:直接注入滚轮量(绕开指针锁定判定),
				# 开镜时必须只改 CLU 倍率、不切换武器(gun_index 不变)
				var zoom_before: String = g2.zoom_label()
				var idx_before: int = G.player.gun_index
				G.input_sys.wheel -= 1
				await get_tree().create_timer(0.2).timeout
				print("[ADS-CAP] rpg_wheel_down zoom %s→%s gun_index %d→%d" % [
					zoom_before, G.player.gun().zoom_label(), idx_before, G.player.gun_index])
			# 曝光诊断:主世界/主相机的自动曝光状态与曝光参数
			var wa: CameraAttributes = G.world_env.camera_attributes if G.world_env != null else null
			var ma: CameraAttributes = G.camera.attributes if G.camera != null else null
			var ae := func(a) -> String:
				return "none" if a == null else ("on" if a.auto_exposure_enabled else "off")
			var em := func(a) -> String:
				return "-" if a == null else "%.2f" % a.exposure_multiplier
			print("[ADS-CAP] world_te=%.3f world_ae=%s world_em=%s | cam_ae=%s cam_em=%s" % [
				G.world_env.environment.tonemap_exposure if G.world_env != null and G.world_env.environment != null else -1.0,
				ae.call(wa), em.call(wa), ae.call(ma), em.call(ma)])
			if DisplayServer.get_name() != "headless":
				var cap_path := "E:/工作目录2/models_probe/ads_%s.png" % opt_arg
				G.vm_viewport.get_texture().get_image().save_png(cap_path)
				print("[ADS-CAP] saved ", cap_path)
				if G.scope != null and G.scope.active:
					var scope_cap := "E:/工作目录2/models_probe/ads_%s_scopeview.png" % opt_arg
					G.scope.vp.get_texture().get_image().save_png(scope_cap)
					print("[ADS-CAP] saved ", scope_cap)
				var cap_full := "E:/工作目录2/models_probe/ads_%s_full.png" % opt_arg
				# 强制刷新 HUD 准星后截图(红点/全息镜内准星状态最新)
				if G.hud != null:
					G.hud._crosshair.queue_redraw()
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(cap_full)
				print("[ADS-CAP] saved ", cap_full)
			# 恢复原档(原本无档则删除临时文件,不留残留)
			WeaponModsData.save_cfg(gid, orig_cfg)
			if not had_cfg and FileAccess.file_exists(cfg_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
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
	# 换弹动画测试:--test-reload(--reload-empty 强制空仓;--reload-ammo N 指定膛内弹数,默认弹匣-2)
	if ua.has("--test-reload"):
		await get_tree().create_timer(2.0).timeout
		var test_ammo: int = maxi(0, G.player.gun().mag_cap - 2)
		if ua.has("--reload-empty"):
			test_ammo = 0
		elif ua.has("--reload-ammo"):
			var aidx := ua.find("--reload-ammo")
			if ua.size() > aidx + 1:
				test_ammo = clampi(int(ua[aidx + 1]), 0, G.player.gun().mag_cap)
		G.player.gun().ammo = test_ammo
		G.player.gun().reload()
		for k in 30:
			await get_tree().create_timer(0.22).timeout
			var g3 = G.player.gun()
			var cover_x := 0.0
			if g3.reload_ctl != null and g3.reload_ctl.cover != null:
				cover_x = g3.reload_ctl.cover.rotation.x
			print("[RELOAD] t=%.2f flow=%s stage=%s ammo=%d/%d reserve=%d pump_t=%.2f state=%s mag_visible=%s mag_y=%.3f cover_x=%.2f" % [g3.reload_t,
				String(g3.reload_ctl.cfg.get("reload_flow", "mag")) if g3.reload_ctl != null else "?",
				g3.reload_ctl.stage_name() if g3.reload_ctl != null else "?",
				g3.ammo, g3.mag_cap, g3.reserve, g3.pump_t, g3.state_name(),
				g3._mag.visible if g3._mag != null else false,
				g3._mag.position.y if g3._mag != null else -999.0,
				cover_x])
	# 全武器换弹验证:--test-reload-all
	# 对 55 把枪逐把跑战术(膛内剩 2 发)与空仓两套换弹,断言:
	#   1) 弹药总量守恒(旧弹保留/丢匣在数学上都不得多出或消失);
	#   2) 战术换弹必须进入 stow(旧供弹具收入携行具),空仓不进入 stow;
	#   3) 换弹能自然结束且最终弹匣填满。
	if ua.has("--test-reload-all"):
		await get_tree().create_timer(1.0).timeout
		var rl_wids: Array = WeaponsData.W().keys()
		var rl_fails: Array = []
		var rl_passes: Array = []
		G.player.spawn_protect = 999999.0
		for wid in rl_wids:
			var old_gun = G.player.gun()
			var ng = Gun.new(String(wid), G.player)
			ng.draw_t = 1.0
			if old_gun != null and old_gun.group != null and is_instance_valid(old_gun.group):
				G.vm_camera.remove_child(old_gun.group)
				old_gun.group.queue_free()
			G.player.guns[G.player.gun_index] = ng
			G.vm_camera.add_child(ng.group)
			ng.equip()
			for rl_mode in ["tac", "empty"]:
				var rl_empty: bool = rl_mode == "empty"
				ng.ammo = 0 if rl_empty else maxi(0, ng.mag_cap - 2)
				ng.reserve = ng.mag_cap + 3
				var a0: int = ng.ammo
				var r0: int = ng.reserve
				var total: int = a0 + r0
				ng.reload()
				var saw_stow := false
				var rl_guard := 0
				while ng.reloading and rl_guard < 3000:
					rl_guard += 1
					if ng.reload_ctl != null and ng.reload_ctl.phase_name() == "stow":
						saw_stow = true
					await get_tree().process_frame
				await get_tree().create_timer(0.3).timeout
				var expect_full: int = mini(ng.mag_cap, total)
				var rl_errs: Array = []
				if ng.ammo != expect_full:
					rl_errs.append("ammo")
				if ng.reserve != total - ng.ammo:
					rl_errs.append("reserve")
				if not rl_empty and saw_stow:
					pass
				elif not rl_empty and ng.reload_ctl != null and String(ng.reload_ctl.cfg.get("reload_flow", "mag")) == "mag" \
						and not ng.def.projectile and String(ng.reload_ctl.cfg.get("mag", "down")) != "none":
					rl_errs.append("no_stow")
				if rl_errs.is_empty():
					rl_passes.append(String(wid) + ":" + rl_mode)
				else:
					rl_fails.append("%s:%s:%s" % [wid, rl_mode, str(rl_errs)])
		print("[RELOAD-ALL] done passes=%d fails=%d %s" % [rl_passes.size(), rl_fails.size(), str(rl_fails)])
		get_tree().quit()
		return
	# 换弹签名唯一性检查:--test-reload-sig(打印每把枪的换弹动作参数,人工/日志核对)
	if ua.has("--test-reload-sig"):
		var sig_keys: Dictionary = {}
		var sig_dupes: Array = []
		for wid in WeaponsData.W().keys():
			var sd = WeaponsData.W()[wid]
			var sp: Dictionary = ReloadProfiles.profile_for(String(wid), sd)
			var key := "%s|%s|%s|%.3f|%.3f" % [
				str(sp.get("pouch", Vector3.ZERO)), str(sp.get("remove_bias", Vector3.ZERO)),
				str(sp.get("insert_bias", Vector3.ZERO)), float(sp.get("fetch_arc", 0.0)), float(sp.get("drop_dist", 0.0))]
			if sig_keys.has(key):
				sig_dupes.append("%s==%s" % [wid, sig_keys[key]])
			else:
				sig_keys[key] = wid
			print("[RELOAD-SIG] %-8s chamber=%-12s pouch=%s remove=%s insert=%s arc=%.3f drop=%.3f rot=%.3f speed=%.3f" % [
				wid, str(sp.get("chamber_style", "?")), str(sp.get("pouch", Vector3.ZERO)),
				str(sp.get("remove_bias", Vector3.ZERO)), str(sp.get("insert_bias", Vector3.ZERO)),
				float(sp.get("fetch_arc", 0.0)), float(sp.get("drop_dist", 0.0)), float(sp.get("mag_rot", 0.0)), float(sp.get("anim_speed", 1.0))])
		print("[RELOAD-SIG] done weapons=%d unique=%d dupes=%s" % [sig_keys.size(), sig_keys.size(), str(sig_dupes)])
		get_tree().quit()
		return
	# [9/10] 泵动霰弹枪 / 左轮 QA:射击、泵动、逐发/快速换弹、部分装填、中断保留、检视、切换
	if ua.has("--test-shotgun-revolver"):
		await get_tree().create_timer(1.5).timeout
		var nw_fails: Array = []
		var nw_pass: Array = []
		var sim_step := 0.016
		var shotgun_ids: Array = ["rem870", "m590", "win1897"]
		var revolver_ids: Array = ["python", "sw686", "sw500"]
		for sid in shotgun_ids:
			var ok := true
			G.player.give_class("assault", { "primary": "m4", "secondary": "m1911", "shotgun": sid })
			G.player.switch_weapon(1)
			var sg: Gun = G.player.gun()
			sg.draw_t = 1.0
			sg.fire_timer = 0.0
			G.player.sprint_amount = 0.0
			var before_fire: int = sg.ammo
			sg.try_fire()
			if sg.ammo != before_fire - 1:
				ok = false
				nw_fails.append(sid + ":fire_ammo")
			var pumped := false
			for i in 40:
				sg.update(sim_step)
				if sg.pump_t > 0.0:
					pumped = true
			if not pumped:
				ok = false
				nw_fails.append(sid + ":pump_cycle")
			# 逐发装填:3 → 4 → 立即中断,保留 4 发
			sg.ammo = 3
			sg.reserve = sg.def.reserve
			sg.reload()
			var got_one := false
			var partial_ammo := 3
			for i in 400:
				sg.update(sim_step)
				if sg.ammo > 3:
					got_one = true
					partial_ammo = sg.ammo
					sg.reload_ctl.cancel("fire")
					break
			for i in 30:
				sg.update(sim_step)
			if not got_one or sg.ammo != partial_ammo or sg.reloading:
				ok = false
				nw_fails.append(sid + ":partial_reload_keep")
			# 继续装到满,确认不跳变、最终满弹
			sg.reload()
			var guard := 0
			while sg.reloading and guard < 900:
				sg.update(sim_step)
				guard += 1
			if sg.ammo != sg.mag_cap:
				ok = false
				nw_fails.append(sid + ":full_reload")
			# 空仓逐发:第一发入膛必须触发一次真实泵动,随后继续装填
			sg.ammo = 0
			sg.reserve = sg.def.reserve
			sg.reload()
			var first_guard := 0
			while sg.ammo < 1 and first_guard < 500:
				sg.update(sim_step)
				first_guard += 1
			if sg.ammo < 1 or sg.reload_ctl == null or not sg.reload_ctl.tube_first_chambered:
				ok = false
				nw_fails.append(sid + ":empty_first_pump")
			var empty_guard := 0
			while sg.reloading and empty_guard < 1200:
				sg.update(sim_step)
				empty_guard += 1
			if sg.ammo != sg.mag_cap:
				ok = false
				nw_fails.append(sid + ":empty_full_reload")
			# 开镜与移动姿态不崩溃、不残留泵动
			sg.ads_held = true
			for i in 20:
				sg.update(sim_step)
			if sg.ads_amount < 0.4:
				ok = false
				nw_fails.append(sid + ":ads")
			sg.ads_held = false
			# 检视:武器从战斗位置自然移出并回到战斗状态
			var sg_settle0 := 0
			while (sg.pump_t > 0.0 or (sg.reload_ctl != null and sg.reload_ctl.is_animating())) and sg_settle0 < 120:
				sg.update(sim_step)
				sg_settle0 += 1
			sg.try_inspect()
			for i in 20:
				sg.update(sim_step)
			if not sg.inspect_active:
				ok = false
				nw_fails.append(sid + ":inspect")
			sg._stop_inspect()
			# 等待泵动/收尾动画完全归零后测试运动姿态,避免动画重叠
			var sg_settle := 0
			while (sg.pump_t > 0.0 or (sg.reload_ctl != null and sg.reload_ctl.is_animating())) and sg_settle < 200:
				sg.update(sim_step)
				sg_settle += 1
			# 冲刺/蹲伏/跳跃姿态与切枪切换
			G.player.sprint_amount = 1.0
			for i in 12:
				sg.update(sim_step)
			if sg.state_name() != "sprint":
				ok = false
				nw_fails.append(sid + ":sprint_state")
			G.player.sprint_amount = 0.0
			G.player.crouched = true
			for i in 12:
				sg.update(sim_step)
			if sg.state_name() != "crouch":
				ok = false
				nw_fails.append(sid + ":crouch_state")
			G.player.crouched = false
			G.player.on_ground = false
			for i in 12:
				sg.update(sim_step)
			if sg.state_name() != "jump":
				ok = false
				nw_fails.append(sid + ":jump_state")
			G.player.on_ground = true
			G.player.switch_weapon(0)
			G.player.switch_weapon(1)
			if G.player.gun().id != sid:
				ok = false
				nw_fails.append(sid + ":weapon_switch")
			if ok:
				nw_pass.append(sid)
			print("[NEWWEAPON] shotgun %s %s" % [sid, "PASS" if ok else "FAIL"])
		for rid in revolver_ids:
			var ok := true
			G.player.give_class("assault", { "primary": "m4", "secondary": rid, "shotgun": "m1014" })
			G.player.switch_weapon(2)
			var rg: Gun = G.player.gun()
			rg.draw_t = 1.0
			rg.fire_timer = 0.0
			G.player.sprint_amount = 0.0
			var cap: int = rg.mag_cap
			var before_r: int = rg.ammo
			rg.try_fire()
			if rg.ammo != before_r - 1 or rg._chamber_loaded[0] == true:
				ok = false
				nw_fails.append(rid + ":fire_cylinder")
			var spin_ok := false
			for i in 20:
				rg.update(sim_step)
				if rg.cylinder_t > 0.0 or rg.hammer_t > 0.0:
					spin_ok = true
			if not spin_ok:
				ok = false
				nw_fails.append(rid + ":cylinder_anim")
			# 逐发:缺 2 发时开始,装到 +1 后中断,保留已装弹
			rg.ammo = cap - 2
			rg._normalize_revolver_chambers()
			rg.reserve = rg.def.reserve
			rg.reload()
			var r_got := false
			var r_partial := cap - 2
			for i in 800:
				rg.update(sim_step)
				if rg.ammo > cap - 2:
					r_got = true
					r_partial = rg.ammo
					rg.reload_ctl.cancel("fire")
					break
			for i in 30:
				rg.update(sim_step)
			if not r_got or rg.ammo != r_partial or rg.reloading:
				ok = false
				nw_fails.append(rid + ":single_reload_keep")
			# 快速换弹:空膛 → 甩出全清 → 装弹器压满
			rg.ammo = 0
			rg._normalize_revolver_chambers()
			rg.reserve = rg.def.reserve
			rg.reload()
			# 弹巢打开早期允许 B 键在快速/逐发之间切换;QA 切过去再切回来
			if not rg.reload_ctl.toggle_revolver_mode() or not rg.reload_ctl.toggle_revolver_mode():
				ok = false
				nw_fails.append(rid + ":reload_mode_toggle")
			var r_guard := 0
			while rg.reloading and r_guard < 900:
				rg.update(sim_step)
				r_guard += 1
			var loaded := 0
			for v in rg._chamber_loaded:
				if v == true:
					loaded += 1
			if rg.ammo != cap or loaded != cap:
				ok = false
				nw_fails.append(rid + ":quick_reload_sync")
			# 检视(等待快速换弹收尾动画/击锤动画完全归零后再进入,不能动画重叠)
			var r_settle := 0
			while (rg.reload_ctl != null and rg.reload_ctl.is_animating()) and r_settle < 120:
				rg.update(sim_step)
				r_settle += 1
			for i in 20:
				rg.update(sim_step)
			rg.try_inspect()
			for i in 20:
				rg.update(sim_step)
			if not rg.inspect_active:
				ok = false
				nw_fails.append(rid + ":inspect")
			rg._stop_inspect()
			# 冲刺/蹲伏/跳跃姿态与切枪切换
			G.player.sprint_amount = 1.0
			for i in 12:
				rg.update(sim_step)
			if rg.state_name() != "sprint":
				ok = false
				nw_fails.append(rid + ":sprint_state")
			G.player.sprint_amount = 0.0
			G.player.crouched = true
			for i in 12:
				rg.update(sim_step)
			if rg.state_name() != "crouch":
				ok = false
				nw_fails.append(rid + ":crouch_state")
			G.player.crouched = false
			G.player.on_ground = false
			for i in 12:
				rg.update(sim_step)
			if rg.state_name() != "jump":
				ok = false
				nw_fails.append(rid + ":jump_state")
			G.player.on_ground = true
			G.player.switch_weapon(0)
			G.player.switch_weapon(2)
			if G.player.gun().id != rid:
				ok = false
				nw_fails.append(rid + ":weapon_switch")
			if ok:
				nw_pass.append(rid)
			print("[NEWWEAPON] revolver %s %s" % [rid, "PASS" if ok else "FAIL"])
		# 恢复默认配装,让测试期 queue_free 的旧枪帧末真正释放,避免退出时资源残留
		G.player.give_class("assault", { "primary": "m4", "secondary": "m1911", "shotgun": "m1014" })
		for i in 30:
			await get_tree().process_frame
		print("[NEWWEAPON] pass=%s fail=%s details=%s" % [str(nw_pass), str(nw_fails), "OK" if nw_fails.is_empty() else "FAIL"])
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
	# 菜单导航回归:--test-menu-nav(主菜单 → 战役/门户 → 返回主菜单,断言返回后始终有可见 UI)
	# 复现历史 bug:_hide_screen 加的 UI 锁挡住随后的 _show_screen,导致所有页面消失、无法退出
	if ua.has("--test-menu-nav"):
		await get_tree().create_timer(0.6).timeout
		var mn = _menus
		# 深路径:若当前在对局里(配合 --test-play),先走暂停菜单「返回主菜单」再验菜单可用
		if G.state != "menu" and mn.on_quit.is_valid():
			mn.on_quit.call()
			await get_tree().create_timer(0.5).timeout
			var vq: String = mn.qa_visible_screens()
			print("[NAV] 对局中退回主菜单 → %s %s" % [
				("OK" if vq.find("menu") >= 0 else "X 失败(空白/无主菜单)"), mn.qa_nav_state()])
		print("[NAV] 起始 ", mn.qa_nav_state())
		for step in [["战争故事", "campaign"], ["门户", "portal"]]:
			var entry: String = step[0]
			var screen: String = step[1]
			var ok_in: bool = mn.qa_press_button("menu", entry)
			await get_tree().create_timer(0.45).timeout
			print("[NAV] 进入 %s(命中=%s) %s" % [entry, str(ok_in), mn.qa_nav_state()])
			var ok_back: bool = mn.qa_press_button(screen, "返回主菜单")
			await get_tree().create_timer(0.45).timeout
			print("[NAV] 返回(命中=%s) %s" % [str(ok_back), mn.qa_nav_state()])
			var vis: String = mn.qa_visible_screens()
			if vis == "":
				print("[NAV] X 失败:返回后没有任何可见页面(玩家卡在空白界面)")
			elif vis.find("menu") < 0:
				print("[NAV] X 失败:返回后主菜单不可见,可见页=", vis)
			else:
				print("[NAV] OK:主菜单已回到可见")
		print("[NAV] 菜单导航回归结束")
		# 全页面「返回/取消」按钮清扫:任何一条返回路径都不许留下空白界面
		print("[NAV] ---- 返回按钮全量清扫 ----")
		for line in String(mn.qa_back_button_sweep()).split("\n"):
			print("[NAV] ", line)
		await get_tree().create_timer(0.3).timeout
		print("[NAV] 清扫后 ", mn.qa_nav_state())
		# 兜底看门狗:人为制造"菜单态全页面隐藏"的空白态,0.5s 后应自动恢复主菜单
		mn.hide_all()
		await get_tree().create_timer(0.15).timeout
		print("[NAV] 人为空白 ", mn.qa_nav_state())
		await get_tree().create_timer(0.8).timeout
		var vw: String = mn.qa_visible_screens()
		print("[NAV] 看门狗 %s %s" % [("OK:已自动恢复主菜单" if vw.find("menu") >= 0 else "X 失败:仍空白"), mn.qa_nav_state()])
	# 兵种第二技能冒烟测试:--test-gadgets(配合 --test-play)
	# 逐兵种切换到第二技能并真实调用 use_gadget,断言:武器槽/部署物/碰撞体/无人机接管全部生效
	if ua.has("--test-gadgets"):
		await get_tree().create_timer(1.5).timeout
		var p2 = G.player
		for pair in [["assault", "gl"], ["engineer", "rpg"], ["engineer", "coverkit"],
				["support", "medpack"], ["support", "ammopack"], ["recon", "drone"]]:
			var cid2: String = pair[0]
			var gid2: String = pair[1]
			var lo2: Dictionary = { "gadget": gid2 }
			p2.give_class(cid2, lo2)
			await get_tree().process_frame
			var guns_txt := ""
			for gg in p2.guns:
				guns_txt += gg.id + "/"
			print("[GADGET] %s → %s(×%d) guns=[%s]" % [cid2, p2.gadget_cn, p2.gadget_count, guns_txt])
			var dep_before: int = G.deployables.size()
			var coll_before: int = G.colliders.size()
			p2.use_gadget()
			await get_tree().create_timer(0.35).timeout
			print("[GADGET]   use → count=%d deployables %d→%d colliders %d→%d drone_piloting=%s" % [
				p2.gadget_count, dep_before, G.deployables.size(), coll_before, G.colliders.size(),
				str(G.drone.piloting if G.drone != null else false)])
			if gid2 == "drone" and G.drone != null and G.drone.piloting:
				# 惯性验证:按住前进 → 速度应逐步爬升(不是瞬间满速),松开后滑停
				var p0: Vector3 = G.drone.pos
				Input.action_press("move_forward")
				await get_tree().create_timer(0.15).timeout
				var v_early: float = G.drone.speed_ms()
				await get_tree().create_timer(1.0).timeout
				var v_late: float = G.drone.speed_ms()
				Input.action_release("move_forward")
				await get_tree().create_timer(0.5).timeout
				print("[GADGET]   drone 速度爬升 0.15s=%.1f → 1.15s=%.1f(上限 %.0f) 松开后=%.1f 位移=%.1fm" % [
					v_early, v_late, G.drone.SPEED, G.drone.speed_ms(), p0.distance_to(G.drone.pos)])
				var dh = G.hud._drone_hud if G.hud != null else null
				print("[GADGET]   drone UAV-HUD visible=%s 类=%s 武器面板=%s" % [
					str(dh != null and dh.visible), str(dh.get_class() if dh != null else "nil"),
					str(G.hud._wpn_panel.visible if G.hud != null else true)])
				# 云台相机检查:必须越过前旋翼叶尖(z≈-0.45),且 HUD 世界标记改用无人机相机投影
				var cam_local: Vector3 = (G.drone.cam.global_position - G.drone.pos).rotated(Vector3.UP, -G.drone.yaw)
				print("[GADGET]   drone view_cam_is_drone=%s cam_fwd=%.2f(叶尖0.45) cam_dy=%.2f alt=%.1f" % [
					str(G.view_camera() == G.drone.cam), -cam_local.z, cam_local.y, G.drone.alt_agl()])
				# 越界失联流程:飞出 100m → 灰白雪花 + 3s 倒计时 → 黑屏 → 自动交还本体视角
				G.drone.pos += Vector3(400.0, 0.0, 0.0)
				await get_tree().create_timer(0.4).timeout
				print("[GADGET]   drone 越界 dist=%.0f/%.0f 信号丢失=%.2f 倒计时=%.1fs piloting=%s" % [
					G.drone.dist_to_origin, G.drone.RADIUS, G.drone.signal_lost01(),
					G.drone.lost_countdown(), str(G.drone.piloting)])
				await get_tree().create_timer(2.0).timeout
				print("[GADGET]   drone 失联中 信号丢失=%.2f 倒计时=%.1fs piloting=%s 黑屏=%.2f" % [
					G.drone.signal_lost01(), G.drone.lost_countdown(), str(G.drone.piloting), G.drone.blackout_t])
				await get_tree().create_timer(0.75).timeout
				print("[GADGET]   drone 黑屏阶段 信号丢失=%.2f 黑屏剩余=%.2fs piloting=%s" % [
					G.drone.signal_lost01(), G.drone.blackout_t, str(G.drone.piloting)])
				await get_tree().create_timer(1.5).timeout
				print("[GADGET]   drone 断链后 piloting=%s 主相机=%s UAV-HUD=%s 武器面板=%s" % [
					str(G.drone.piloting), str(G.camera.current),
					str(G.hud._drone_hud.visible if G.hud != null else false),
					str(G.hud._wpn_panel.visible if G.hud != null else true)])
			if gid2 == "gl" or gid2 == "rpg":
				# 占武器槽的技能:切到技能槽 → 开火 → 换弹全流程(榴弹含中折开膛动画)
				p2.switch_weapon(p2.guns.size() - 1)
				await get_tree().process_frame
				var glg = p2.gun()
				print("[GADGET]   gl gun=%s ammo=%d/%d proj=%s grav=%.1f breech=%s" % [
					glg.id, glg.ammo, glg.reserve, str(glg.def.projectile), glg.def.proj_grav,
					str(glg.group.has_meta("breech"))])
				glg.trigger_held = true
				# 先等拔枪动画播完(draw_t≥0.6 才允许击发),再按真实输入路径开火
				await get_tree().create_timer(0.45).timeout
				Input.action_press("fire")
				await get_tree().create_timer(0.3).timeout
				Input.action_release("fire")
				await get_tree().create_timer(0.2).timeout
				print("[GADGET]   gl 开火后 ammo=%d/%d 火箭弹在飞=%s" % [
					glg.ammo, glg.reserve, str(G.effects.rocket_count() > 0)])
				glg.reload()
				for si in 7:
					await get_tree().create_timer(0.42).timeout
					var bo: float = glg.reload_ctl.breech_open if glg.reload_ctl != null else -1.0
					var bn: Node3D = glg.group.get_meta("breech") if glg.group.has_meta("breech") else null
					# 中折方向验证:枪口点(膛体空间 0,0.052,-0.29)在枪身空间的 y 必须随开膛「下降」
					var tip_y := 0.0
					if bn != null:
						tip_y = (bn.transform * Vector3(0, 0.052, -0.29)).y
					# 榴弹必须始终"握在左手里"被带到装填口(不是在装填口凭空出现):
					# 取弹后手与弹的世界距离应恒定在握持偏移(≈9cm)左右
					var rc = glg.reload_ctl
					var hand_gap := -1.0
					if rc != null and rc.new_rocket != null and rc.new_rocket.visible and rc.left_hand != null:
						hand_gap = rc.left_hand.global_position.distance_to(rc.new_rocket.global_position)
					print("[GADGET]   gl reload t=%.2f 阶段=%s 开膛=%.2f 膛体rot.x=%.3f 枪口y=%.3f 手弹距=%.3f ammo=%d/%d" % [
						glg.reload_t, glg.reload_ctl.phase_name() if glg.reload_ctl != null else "?",
						bo, (bn.rotation.x if bn != null else -9.0), tip_y, hand_gap,
						glg.ammo, glg.reserve])
		print("[GADGET] 第二技能冒烟测试完成")
	# AI 第二技能验证:--test-ai-gadgets(配合 --test-play)
	# 检查双方 AI 的技能分配覆盖两种选项,并逐项强制触发 GL/掩体/医疗包/弹药包/无人机。
	if ua.has("--test-ai-gadgets"):
		await get_tree().create_timer(2.5).timeout
		var dist: Dictionary = {}
		for b in G.bots:
			var key := String(b.class_id) + ":" + String(b.gadget)
			dist[key] = int(dist.get(key, 0)) + 1
		print("[AI-GADGET] 分布=", dist)
		var dep0: int = G.deployables.size()
		var fired_gl := 0
		var cover_used := 0
		var pack_used := 0
		var drone_used := false
		for b in G.bots:
			if not b.alive:
				continue
			match String(b.gadget):
				"coverkit":
					b.suppress_t = 2.0
					b.gadget_cd = 0.0
					b._duty_engineer(0.1)
					if b.gadget_cd > 0.0:
						cover_used += 1
				"medpack", "ammopack":
					var ally = null
					for o in G.bots:
						if o != b and o.alive and o.team == b.team and o.pos.distance_to(b.pos) < 20:
							ally = o
							break
					if ally == null:
						ally = b
					if String(b.gadget) == "medpack":
						ally.health = 30.0
					else:
						ally.ammo = 1
					b.ability_cd = 0.0
					b._duty_support()
					if b.ability_cd > 0.0:
						pack_used += 1
				"drone":
					if G.drone != null and not G.drone.piloting and not G.drone.ai_flying and G.drone.launch_ai(b):
						drone_used = true
				"gl":
					var enemy = null
					for o in G.bots:
						if o.alive and o.team != b.team:
							enemy = o
							break
					if enemy != null:
						enemy.pos = b.pos + Vector3(30.0, 0, 0)
						b.target = enemy
						b.target_visible = true
						b.gl_cd = 0.0
						var d_gl: float = b.pos.distance_to(enemy.pos)
						b._duty_assault()
						print("[AI-GADGET] GL尝试 bot=%d team=%s dist=%.1f vis=%s cd=%.2f" % [
							b.id, b.team, d_gl, str(b.target_visible), b.gl_cd])
						if b.gl_cd > 0.0:
							fired_gl += 1
		await get_tree().create_timer(0.6).timeout
		print("[AI-GADGET] 结果 GL开火=%d 掩体=%d 补给=%d 无人机=%s 部署物=%d→%d" % [
			fired_gl, cover_used, pack_used, str(drone_used), dep0, G.deployables.size()])
		if G.drone != null and G.drone.ai_mode:
			G.drone.recall("测试完成")
		get_tree().quit()
		return
	# BR 拾取/掉落/空投验证:--test-br-loot(配合 --test-play br br_valley)
	if ua.has("--test-br-loot"):
		await get_tree().create_timer(2.0).timeout
		var brl = G.br
		if brl == null:
			print("[BR-LOOT] 失败:BR 模式未启动")
			get_tree().quit()
			return
		var ok_drop := false
		var ok_airdrop := false
		var bot = null
		for b in G.bots:
			if b != null and b.alive:
				bot = b
				break
		if bot != null:
			# NPC 死亡掉落:强制丢一把 AK,把玩家放到掉落点按 E 拾取(不跨帧,避免跳伞状态重置玩家位置)
			bot.weapon_id = "ak"
			bot.br_weapon_q = 1
			brl._drop_victim_loot(bot)
			G.player.pos = bot.pos + Vector3(0.6, 0, 0)
			ok_drop = brl.try_player_pickup(G.player)
			print("[BR-LOOT] NPC掉落拾取=%s 玩家主武器=%s 品质加成=%s" % [
				str(ok_drop), G.player.gun().id, str(G.player.gun().def.damage)])
		# 空投箱:生成在玩家脚下,验证 E 能捡起(史诗武器+护甲+医疗包)
		var air_pos: Vector3 = G.player.pos + Vector3(1.0, 0, 0)
		brl._place_loot(air_pos, "airdrop", "scar", 2)
		G.player.pos = air_pos + Vector3(0.4, 0, 0)
		ok_airdrop = brl.try_player_pickup(G.player)
		print("[BR-LOOT] 空投拾取=%s 主武器=%s 护甲=%.0f 医疗包=%d" % [
			str(ok_airdrop), G.player.gun().id, G.player.br_armor, G.player.br_medkits])
		print("[BR-LOOT] 完成 drop=%s airdrop=%s" % [str(ok_drop), str(ok_airdrop)])
		get_tree().quit()
		return
	# BR 小队/永久淘汰验证:--test-br-squads(配合 --test-play br br_valley)
	if ua.has("--test-br-squads"):
		await get_tree().create_timer(2.0).timeout
		var sqc: Dictionary = {}
		for b in G.bots:
			sqc[b.squad_id] = int(sqc.get(b.squad_id, 0)) + 1
		print("[BR-SQ] 小队人数分布=", sqc)
		# 1) 玩家子弹必须能命中“同 team 但不同小队”的 NPC(禁区冲突按小队,不按阵营)
		var same_team_enemy = null
		for b in G.bots:
			if b.alive and b.team == G.player.team and b.squad_id != GameMode_BR.BR_PLAYER_SQUAD:
				same_team_enemy = b
				break
		var probe_ok := false
		if same_team_enemy != null:
			var eye: Vector3 = G.camera.global_position
			var fdir: Vector3 = -G.camera.global_transform.basis.z
			same_team_enemy.pos = eye + fdir * 20.0 - Vector3(0, 1.05, 0)
			var pr: Dictionary = Utils.probe_actor(same_team_enemy, G.player, G.player.team, eye, fdir, 30.0)
			probe_ok = not pr.is_empty()
		print("[BR-SQ] 同阵营不同小队可命中=%s" % str(probe_ok))
		# 2) NPC 阵亡必须永久淘汰,不再进入复活队列
		var victim2 = null
		for b in G.bots:
			if b.alive and b.squad_id != GameMode_BR.BR_PLAYER_SQUAD:
				victim2 = b
				break
		var perm_ok := false
		if victim2 != null:
			var before_alive: int = G.br.br_alive
			G.br.on_player_killed(G.player, victim2)
			perm_ok = G.br._eliminated.has(victim2) and not G.br._br_redeploy_queue.has(victim2) \
				and G.br.br_alive == before_alive - 1
		print("[BR-SQ] NPC永久淘汰=%s(br_alive 已减,复活队列无此NPC)" % str(perm_ok))
		print("[BR-SQ] 完成 probe=%s permanent=%s" % [str(probe_ok), str(perm_ok)])
		get_tree().quit()
		return
	# BR 开局兵种道具验证:--test-br-gadget-start(配合 --test-play br br_valley)
	if ua.has("--test-br-gadget-start"):
		await get_tree().create_timer(2.0).timeout
		var fails2: Array = []
		for pair in [["assault", "gl"], ["engineer", "rpg"], ["engineer", "coverkit"],
				["support", "medpack"], ["support", "ammopack"], ["recon", "drone"]]:
			var cid3: String = pair[0]
			var gid3: String = pair[1]
			G.player.give_class(cid3, { "gadget": gid3 })
			G.player.br_strip_inventory()
			var has_weapon: bool = false
			var ids: Array = []
			for g in G.player.guns:
				ids.append(g.id)
				if g.id == gid3:
					has_weapon = true
			var ok: bool = false
			if gid3 == "gl" or gid3 == "rpg":
				ok = has_weapon
			else:
				ok = G.player.gadget_count > 0 and G.player.gadget_count == G.player.gadget_max
			print("[BR-GADGET-START] %s:%s guns=%s count=%d/%d ok=%s" % [
				cid3, gid3, str(ids), G.player.gadget_count, G.player.gadget_max, str(ok)])
			if not ok:
				fails2.append(cid3 + ":" + gid3)
		print("[BR-GADGET-START] done fails=%s" % str(fails2))
		get_tree().quit()
		return
	# BR 中途离场结算验证:--test-br-abort(配合 --test-play br br_valley)
	if ua.has("--test-br-abort"):
		await get_tree().create_timer(2.0).timeout
		G.portal.end_match({ "aborted": true })
		await get_tree().create_timer(0.5).timeout
		var r2: Dictionary = G.menus._portal_last_result if G.menus != null else {}
		print("[BR-ABORT] state=%s active=%s title_result=%s rank=%s team_rank=%s winner=%s" % [
			G.state, str(G.portal.active), str(r2.get("aborted", false)),
			str(r2.get("rank", 0)), str(r2.get("team_rank", 0)), str(r2.get("winner", ""))])
		get_tree().quit()
		return
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
			if v.type == vtype and not v.dead and (v.driver == null or v.driver != G.player):
				veh = v
				break
		if veh != null:
			# bot 可能抢先登车(2s 窗口):踢下让玩家上(测试用)
			if veh.driver != null and veh.driver != G.player:
				veh.driver = null
				veh.ai_input = null
			if veh.gunner != null and veh.gunner != G.player:
				veh.gunner = null
				veh.gunner_ai_input = null
			if ua.has("--veh-isolate"):
				veh.pos = Vector3(150, 0, 150)  # 空旷角隔离观察
			G.player.pos = veh.pos + Vector3(2, 0, 2)
			G.player.enter_vehicle(veh)
			if ua.has("--veh-tp"):
				G.player._veh_tp = true
			if ua.has("--veh-down"):
				veh.turret_pitch = -0.13
				if veh.camera_ctl != null:
					veh.camera_ctl.look_pitch = -0.13
			if ua.has("--veh-up"):
				veh.turret_pitch = 0.9 if vtype == "aa" else 0.3
				# 同步观察角:炮手位/炮镜视角 = 炮塔瞄准方向
				if veh.camera_ctl != null:
					veh.camera_ctl.look_pitch = veh.turret_pitch
			if ua.has("--veh-gunner"):
				# 玩家坐到炮手位(驾驶位空出)
				veh.driver = null
				veh.gunner = G.player
				G.player._veh_crew = 1
			if ua.has("--veh-ads"):
				Input.action_press("ads")  # 炮手位按住炮镜
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
		# 载具 F 键切换乘员位验证(--test-drive 配合):驾驶员 → 炮手 → 驾驶
		if G.player.vehicle != null:
			var vv = G.player.vehicle
			print("[INPUT] 载具初始 driver=", vv.driver == G.player, " gunner=", vv.gunner == G.player, " crew=", G.player._veh_crew)
			await tap.call("gadget")
			print("[INPUT] F 后 driver=", vv.driver == G.player, " gunner=", vv.gunner == G.player, " crew=", G.player._veh_crew)
			await tap.call("gadget")
			print("[INPUT] F 再按 driver=", vv.driver == G.player, " gunner=", vv.gunner == G.player, " crew=", G.player._veh_crew)
	# 程序化运动链路测试:--test-motion(配合 --test-play)
	# 覆盖 Idle -> Walk -> Run -> Sprint -> Hard Stop -> Turn -> ADS -> Aim Walk -> Jump -> Landing。
	# 只打印诊断,不修改手感参数;正常游玩无此 flag 时零开销。
	if ua.has("--test-motion") and G.player != null and G.player.alive:
		await get_tree().create_timer(1.5).timeout
		G.player.spawn_protect = 999.0
		G.player.sprint_toggled = false
		var mot := G.player.motion as FirstPersonMotionSystem
		var log_motion := func(tag: String) -> void:
			if mot == null:
				print("[MOTION] ", tag, " motion=null")
				return
			var gg := G.player.gun() as Gun
			var wpo: Vector3 = mot.weapon_offset()
			var wro: Vector3 = mot.weapon_rotation_offset()
			print("[MOTION] %-12s state=%-10s hspd=%5.2f ads=%4.2f cam_off=(%+.4f,%+.4f,%+.4f) cam_rot=(%+.4f,%+.4f,%+.4f) wpn_off=(%+.4f,%+.4f,%+.4f) wpn_rot=(%+.4f,%+.4f,%+.4f)" % [
				tag, mot.state_name(), Vector2(G.player.vel.x, G.player.vel.z).length(),
				gg.ads_amount if gg != null else 0.0,
				mot.camera_position().x, mot.camera_position().y, mot.camera_position().z,
				mot.camera_rotation().x, mot.camera_rotation().y, mot.camera_rotation().z,
				wpo.x, wpo.y, wpo.z, wro.x, wro.y, wro.z])
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
		await get_tree().create_timer(1.2).timeout
		log_motion.call("idle")
		# 1) Walk:不切 sprint,按住 W 0.9s
		Input.action_press("move_forward")
		await get_tree().create_timer(0.9).timeout
		log_motion.call("walk")
		# 2) Run -> Sprint:sprint 切换为 toggle,速度平滑爬升期间经过 run 状态
		await tap.call("sprint")
		await get_tree().create_timer(0.12).timeout
		log_motion.call("run")
		await get_tree().create_timer(0.78).timeout
		log_motion.call("sprint")
		# 3) Hard Stop:释放 W,让武器前冲并回弹;采样停止瞬间与稳定后
		Input.action_release("move_forward")
		await get_tree().create_timer(0.10).timeout
		log_motion.call("stop")
		await get_tree().create_timer(0.75).timeout
		log_motion.call("stop_settle")
		# 4) Turn:注入快速鼠标 Delta(等价于快速右转),Sway 应按速度非线性增大
		G.input_sys.mouse_dx += 420.0
		G.input_sys.mouse_dy -= 30.0
		await get_tree().create_timer(0.08).timeout
		log_motion.call("turn_peak")
		await get_tree().create_timer(0.55).timeout
		log_motion.call("turn_settle")
		# 5) ADS:开镜后 Bob/Sway 大幅降低,呼吸保留
		Input.action_press("ads")
		await get_tree().create_timer(0.85).timeout
		log_motion.call("ads")
		# 6) Aim Walk:开镜中移动,程序层必须仍保留轻微节奏
		Input.action_press("move_forward")
		await get_tree().create_timer(0.8).timeout
		log_motion.call("aim_walk")
		Input.action_release("move_forward")
		Input.action_release("ads")
		await get_tree().create_timer(0.6).timeout
		# 7) Jump -> Landing:真实跳跃输入,随后落地冲量衰减
		await tap.call("jump")
		await get_tree().create_timer(0.10).timeout
		log_motion.call("jump")
		await get_tree().create_timer(0.70).timeout
		log_motion.call("landing")
		await get_tree().create_timer(1.10).timeout
		log_motion.call("landing_settle")
		print("[MOTION] 运动链路测试完成")
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
	# QA 性能基准:--perf-test(关闭垂直同步测真实帧率 + 每秒打印 FPS/帧时间/内存)
	_perf_on = ua.has("--perf-test")
	if _perf_on:
		G.settings["vsync"] = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("[PERF] --perf-test 开启:垂直同步关闭,每秒采样 FPS/帧时间/内存")
	# QA 帧时间尖峰压测:--perf-stress <帧数>(对局内逐帧采样帧时间,退出时输出 p95/尖峰统计)
	_ps_stress_on = ua.has("--perf-stress")
	if _ps_stress_on:
		var sidx2 := ua.find("--perf-stress")
		_ps_stress_target = maxi(100, int(ua[sidx2 + 1])) if ua.size() > sidx2 + 1 else 1800
		print("[STRESS] --perf-stress 开启:目标 %d 帧(对局内采样帧时间/尖峰,到帧自动退出)" % _ps_stress_target)
	# [8/10] 完整性能基准:--bench <帧数> [标签](关垂直同步,对局内逐帧采集,到帧写 user://perf_bench_<标签>.json)
	_bench_on = ua.has("--bench")
	if _bench_on:
		var bidx := ua.find("--bench")
		_bench_target = maxi(120, int(ua[bidx + 1])) if ua.size() > bidx + 1 else 900
		if ua.size() > bidx + 2:
			_bench_label = String(ua[bidx + 2]).replace(" ", "_")
		G.settings["vsync"] = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("[BENCH] --bench 开启:目标 %d 帧 标签=%s(垂直同步已关)" % [_bench_target, _bench_label])
	_bench_veh_on = ua.has("--bench-veh")
	_bsys_on = ua.has("--bench-sys")
	# [PERF] 实验:物理服务器空转验证(--physoff;项目全自研物理,无 _physics_process,
	# Godot Physics 60Hz 空转白收税;ray query 按需执行不依赖 tick 频率)
	if ua.has("--physoff"):
		Engine.physics_ticks_per_second = 5
		print("[PERF] 实验: physics_ticks 60→5(--physoff)")
	_perf_mon = ua.has("--perf-monitor")
	if _perf_mon:
		_build_perf_monitor()
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
				# material_override 可为空(地面网格走自身材质):此时仅报 UV,跳过贴图读取防 Nil 报错
				print("[GC] UV范围: ", minuv, " → ", maxuv,
					" | 贴图: ", str(mat.albedo_texture) if mat != null else "(无 override 材质)",
					" | 反照色: ", str(mat.albedo_color) if mat != null else "N/A")
				if mat != null and mat.albedo_texture != null:
					var p := "user://dbg_runtime_groundtex.png"
					mat.albedo_texture.get_image().save_png(p)
					print("[GC] 地面贴图已保存: ", p)


## ============ 主界面背景:特勤处备战屋(3D 战争房间 + 四兵种陈列台) ============
## ============ 主界面背景:特勤处备战屋(3D 战争房间 + 四兵种陈列台) ============
func _setup_menu_scene() -> void:
	# 隐藏玩家视角模型/乘员/身体(主菜单不显示)
	if G.player != null:
		for gun in G.player.guns:
			gun.holster(true)
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
	if vp == null:
		return  # 退出收尾时根视口已销毁,跳过画质写(如 BR 恢复预设路径)
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
		RenderingServer.directional_shadow_atlas_set_size(int(s.shadows) if s.shadows > 0 else 1024, false)
		if OS.has_feature("web"):
			G.sun.shadow_bias = 0.09
			G.sun.shadow_normal_bias = 0.35
			G.sun.directional_shadow_max_distance = 80
		else:
			G.sun.shadow_bias = 0.1
			G.sun.shadow_normal_bias = 1.0
	# TAA(WebGL 兼容模式下会产生条纹伪影,关闭)
	if OS.has_feature("web") and G.world_env != null and G.world_env.environment != null:
		G.world_env.environment.ssil_enabled = false
		G.world_env.environment.ssr_enabled = false
		G.world_env.environment.glow_enabled = false
	# 3A 画质项(桌面):MSAA / SSR / SSIL / Glow / 电影后期
	# [8/10] SDFGI 已移除(阴影过黑、对比度过高),恒关闭
	vp.msaa_3d = (int(s.get("msaa", 0)) as Viewport.MSAA)
	if not OS.has_feature("web") and G.world_env != null and G.world_env.environment != null:
		var env: Environment = G.world_env.environment
		env.sdfgi_enabled = false
		# [PERF-AUDIT] --nossr / --no-ssil 临时禁用(仅性能审计用)
		var _no_ssr: bool = OS.get_cmdline_user_args().has("--nossr")
		var _no_ssil: bool = OS.get_cmdline_user_args().has("--nossil")
		env.ssr_enabled = bool(s.get("ssr", false)) and not _no_ssr
		env.ssil_enabled = bool(s.get("ssil", false)) and not _no_ssil
		env.glow_enabled = bool(s.get("glow", true))
	if _cine_rect != null:
		_cine_rect.visible = bool(s.get("cinema", true))
	# SSAO / FXAA
	if G.world_env != null and G.world_env.environment != null:
		G.world_env.environment.ssao_enabled = s.ssao
	# 抗锯齿:内置 MSAA 已在 project.godot 关闭;高档用 TAA,低档用自定义 FXAA 着色器(互斥)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = GraphicsQuality.current_level >= GraphicsQuality.Level.HIGH
	if _fxaa_rect != null:
		_fxaa_rect.visible = s.fxaa
	if G.scope != null and G.scope.has_method("apply_graphics"):
		G.scope.apply_graphics()
	# 垂直同步(0=关 1=开 2=自适应;headless/Web 无操作窗口时跳过)
	# 默认关(竞技 FPS 惯例):vsync 开=帧率锁屏参,120+ 帧目标无从谈起;存档值优先
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var vsync: int = int(G.settings.get("vsync", 0))
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ADAPTIVE if vsync == 2 else (DisplayServer.VSYNC_ENABLED if vsync == 1 else DisplayServer.VSYNC_DISABLED))
	# 粒子
	if G.effects != null:
		G.effects.quality = s.particles
	# 雾效
	if G.world_env != null and G.world_env.environment != null and G.world_env.environment.fog_enabled:
		G.world_env.environment.fog_depth_begin = G.fog_base[0] * s.fog
		G.world_env.environment.fog_depth_end = G.fog_base[1] * s.fog


## [8/10] 动态质量应用:按降级深度运行时降级(不动 G.settings,手动设置优先;level 0 重建)
func _apply_dq() -> void:
	var vp := get_viewport()
	var s: Dictionary = G.settings
	if _dq_level <= 0:
		# 完全恢复:按当前手动设置重建渲染
		if G.apply_graphics.is_valid():
			G.apply_graphics.call()
		if GraphicsQuality != null:
			GraphicsQuality.apply_level_strengths()
		return
	if vp != null:
		vp.msaa_3d = ((int(s.get("msaa", 0)) if _dq_level < 2 else 0) as Viewport.MSAA)
	if G.world_env != null and G.world_env.environment != null:
		var env: Environment = G.world_env.environment
		env.ssr_enabled = bool(s.get("ssr", false)) if _dq_level < 1 else false
		env.ssil_enabled = bool(s.get("ssil", false)) and _dq_level < 1
		env.glow_enabled = bool(s.get("glow", true)) if _dq_level < 5 else false
		if _dq_level >= 3 and G.sun != null:
			G.sun.shadow_enabled = true
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
	if _cine_rect != null and _dq_level >= 4:
		_cine_rect.visible = false


## 手动改画质时重置动态降级(手动设置优先)
func reset_dq() -> void:
	if _dq_level > 0:
		_dq_level = 0
		_apply_dq()
		print("[DQ] 手动设置已重置动态降级")


## ============ 主循环(对应 loop) ============
func _process(dt_raw: float) -> void:
	var dt := minf(dt_raw, 0.05)

	# [PERF] Debug 性能监控:F3 切换显隐 + 节流刷新(0.5s 一拍,避免监控自身成为开销)
	if _perf_mon and _perf_label != null:
		var _f3 := Input.is_key_pressed(KEY_F3)
		if _f3 and not _perf_f3_held:
			_perf_label.visible = not _perf_label.visible
		_perf_f3_held = _f3
		if _perf_label.visible:
			_perf_tick -= dt
			if _perf_tick <= 0.0:
				_perf_tick = 0.5
				_update_perf_label()

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
			# 开局 3D 部署视图(实时 3D 部署系统接管相机时跳过旧版静态部署机位)
			if G.deployment != null and G.deployment.active:
				pass
			elif not G.spawns["us"].is_empty():
				# 部署界面背景与旧版一致:地图上空视角(友军出生点)
				var anchor := Vector3.ZERO
				if not G.spawns["us"].is_empty():
					anchor = G.spawns["us"][0]
				var ah: float = G.ground_h.call(anchor.x, anchor.z) if G.ground_h.is_valid() else 0.0
				_camera.global_position = Vector3(anchor.x + 3.1, ah + 1.55, anchor.z + 5.0)
				_camera.look_at(Vector3(anchor.x + 0.25, ah + 1.0, anchor.z), Vector3.UP)

	var deployment_active: bool = G.deployment != null and G.deployment.active
	# 开局 3D 部署(state=deploy)期间战场同样实时运行(AI 出生/交战/移动)
	var active: bool = (G.state == "playing" or G.state == "dead"
		or (G.state == "deploy" and deployment_active)) and not G.paused

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
			var _pt0 := 0
			if _bsys_on:
				_pt0 = Time.get_ticks_usec()
			if not (G.campaign != null and G.campaign.is_cutscene()):
				G.player.update_player(dt)
			if _bsys_on:
				_bsys_tick("player", _pt0)
		var _bt := 0
		if _bsys_on or _perf_mon:
			_bt = Time.get_ticks_usec()
		# [PERF] 动态实体空间网格每帧重建(ballistic_fire 命中扫描 O(n)→O(近邻))
		Utils.rebuild_actor_grid()
		G.bot_manager.update_bots(dt)
		if _bsys_on:
			_bsys_tick("bot", _bt)
		if _perf_mon:
			_ai_time_us = Utils.damp(_ai_time_us, float(Time.get_ticks_usec() - _bt), 4.0, dt)
		if _bsys_on:
			_bt = Time.get_ticks_usec()
		_effects.update_effects(dt)
		if _bsys_on:
			_bsys_tick("fx", _bt)
		if _bsys_on:
			_bt = Time.get_ticks_usec()
		WorldBuilder.update_map(dt)
		if _bsys_on:
			_bsys_tick("world", _bt)
		if _bsys_on:
			_bt = Time.get_ticks_usec()
		G.game.update_game(dt)
		if _bsys_on:
			_bsys_tick("game", _bt)
		if G.campaign != null and G.campaign.running:
			G.campaign.update(dt)
		var _vbt0 := 0
		if _bench_veh_on or _bsys_on:
			_vbt0 = Time.get_ticks_usec()
		# [PERF] 载具/飞机距离分级:远距降频 + 位置外推(移动连续);debug --veh-lod-off 关闭用于基线
		var _pv_pos: Vector3 = G.player.pos if (G.player != null and G.player.alive) else Vector3.ZERO
		var _pv_ok: bool = G.player != null and G.player.alive
		var _frm := Engine.get_process_frames()
		# [PERF 9/6] 开关静态缓存,免每帧新建字符串数组(审计 P1-7)
		var _veh_lod_off: bool = Utils.FLAG_VEH_LOD_OFF
		for v in G.vehicles:
			if not _veh_lod_off and _pv_ok and v.pos.distance_to(_pv_pos) > 70.0 and (_frm + v.get_instance_id()) % 2 == 1:
				v.pos.x += -sin(v.yaw) * v.speed * dt
				v.pos.z += -cos(v.yaw) * v.speed * dt
				if v.mesh != null:
					v.mesh.position = v.pos
				continue
			v.update_vehicle(dt)
		for a in G.aircraft:
			if not _veh_lod_off and _pv_ok and a.pos.distance_to(_pv_pos) > 140.0 and (_frm + a.get_instance_id()) % 2 == 1:
				a.pos += a.vel * dt
				if a.mesh != null:
					a.mesh.position = a.pos
				continue
			a.update_aircraft(dt)
		if _bench_veh_on:
			_bv_t += Time.get_ticks_usec() - _vbt0
			_bv_n += 1
			if _bv_n >= 900:
				print("[BENCH-VEH] update_veh+air avg=%.1fus/frame  vehicles=%d aircraft=%d frames=%d" % [_bv_t / float(_bv_n), G.vehicles.size(), G.aircraft.size(), _bv_n])
				_bv_t = 0.0
				_bv_n = 0
		if _bsys_on:
			_bsys_tick("veh", _vbt0)
			_bsys_report()
	# ---- 大逃杀:全局引用同步(模式实例生命周期归 PortalManager;死亡观战相机接管) ----
	if G.mode == "br":
		if G.portal != null:
			G.br = G.portal.active
	# 实时 3D 战场部署(征服/突破):死亡升空/自由观察/部署飞行全程独立驱动,
	# 不受状态切换影响(如部署飞行中对局结束或外部重生,仍需收尾清理)
	if G.deployment != null and G.deployment.active:
		G.deployment.update(dt)
	# 死亡倒地镜头(大逃杀死亡 → 死亡回放 5s + 观战,相机由 BR 接管;
	# [BR-R] 重部署阶段(直升机追尾/跳伞 TP)相机由 BR 重部署接管,不走倒地镜头)
	if G.state == "dead":
		if G.mode == "br" and G.br != null and G.br.is_spectating():
			G.br.update_spectate(dt)
		elif G.mode == "br" and G.br != null and G.br.has_method("redeploy_cam_active") \
				and G.br.redeploy_cam_active():
			G.br.update_redeploy_camera(dt)
		else:
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

	# 性能自适应:持续低帧则降级(进入 GPU 保护档)
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
				print("[PERF] 自适应降级触发(fps<42 持续 4s):Windows 进入 GPU 保护档")
				if OS.has_feature("web"):
					# Web 端性能有限,降级保帧率
					G.settings.ssao = false
					G.settings.shadows = 0
					G.settings.scale = 0.8
				else:
					# Windows 端:套用 GPU 保护档(阴影 2048/SSIL off/SSR off/体积雾 32/粒子 0.7)
					GraphicsQuality.enter_protect()
	# [PERF] GPU 保护档自适应 v2:帧时间尖峰检测(驱动级挂起前兆——dxgi/D3D12Core 卡死时
	# 单帧 >250ms 或 2s 均值 >100ms)→ 立即套保护档;5s 无尖峰后恢复原档(仍卡则保持)。
	# 全模式生效(征服/突破/TDM/战役/BR);慢路径(_degraded 锁存)不自动恢复。
	# Web 端走自己的静态低碳配置,不参与保护档切换。
	if not OS.has_feature("web") and (G.state == "playing" or G.state == "dead") and not G.paused:
		_ps_win_t += dt_raw
		_ps_win_n += 1
		var spiked := dt_raw > 0.25
		if _ps_win_t >= 2.0:
			if _ps_win_n > 0 and _ps_win_t / _ps_win_n > 0.1:
				spiked = true
			_ps_win_t = 0.0
			_ps_win_n = 0
		if spiked:
			_ps_enter_t = Time.get_ticks_msec()
			if not GraphicsQuality.protect_active():
				GraphicsQuality.enter_protect()
				print("[PERF] 自适应 GPU 保护档触发: 帧时间尖峰 %.0fms" % (dt_raw * 1000.0))
		elif GraphicsQuality.protect_active() and not _degraded \
				and Time.get_ticks_msec() - _ps_enter_t >= 5000:
			GraphicsQuality.exit_protect()
			print("[PERF] 自适应 GPU 保护档恢复(5s 稳定)")
			_ps_enter_t = -1e9
	else:
		_ps_win_t = 0.0
		_ps_win_n = 0

	if _validate:
		_validate = false
		print("[VALIDATE] 首帧渲染完成 state=", G.state)
		get_tree().quit()

	# [8/10] 动态质量:帧时间 2s 均值 >33ms 逐级降级;<20ms 且稳定 5s 恢复一级
	if bool(G.settings.get("auto_quality", true)) and G.state == "playing":
		_dq_t += dt_raw
		_dq_n += 1
		if _dq_t >= 2.0:
			var dq_avg: float = _dq_t / float(_dq_n)
			if dq_avg > 0.033 and _dq_level < 5:
				_dq_level += 1
				_apply_dq()
				print("[DQ] 动态降级 -> level %d (帧时间 %.0fms)" % [_dq_level, dq_avg * 1000.0])
				_dq_t = 0.0
				_dq_n = 0
				_dq_stable_t = 0.0
			elif dq_avg < 0.02 and _dq_level > 0:
				_dq_stable_t += _dq_t
				if _dq_stable_t >= 5.0:
					_dq_level -= 1
					_apply_dq()
					print("[DQ] 动态恢复 -> level %d" % [_dq_level])
					_dq_stable_t = 0.0
				_dq_t = 0.0
				_dq_n = 0
			else:
				_dq_t = 0.0
				_dq_n = 0

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

	# QA 性能基准采样:--perf-test(每秒打印 fps/帧时间/最低/内存)
	if _perf_on:
		_perf_t += dt_raw
		var fps_now := Engine.get_frames_per_second()
		if fps_now > 0.0:
			_perf_min = minf(_perf_min, fps_now)
			_perf_max = maxf(_perf_max, fps_now)
		if _perf_t >= 1.0:
			_perf_t = 0.0
			var mem := OS.get_static_memory_usage() / 1048576.0
			print("[PERF] frame=%d fps=%.1f ft=%.2fms min=%.1f max=%.1f mem=%.0fMB state=%s" % [
				Engine.get_process_frames(), fps_now, 1000.0 / maxf(fps_now, 0.1),
				_perf_min, _perf_max, mem, G.state])

	# [8/10] 完整性能基准采样:--bench(逐帧采集,到帧写报告退出)
	# [PERF 9/6] RenderingServer.get_rendering_info 每次调用强制 CPU/GPU 同步 flush,
	# 每帧 3 次会把被测帧率本身压低(测量探针干扰被测系统);降为每 30 帧刷新一次缓存值,
	# 帧时间/process/physics/mem 仍逐帧采集,报告统计口径不变
	if _bench_on and G.state == "playing":
		_bench_fts.append(dt_raw * 1000.0)
		_bench_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_bench_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		if Engine.get_process_frames() % 30 == 0:
			_bench_dc_last = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			_bench_prims_last = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			_bench_objs_last = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		_bench_dc.append(_bench_dc_last)
		_bench_prims.append(_bench_prims_last)
		_bench_objs.append(_bench_objs_last)
		_bench_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		_bench_mem.append(OS.get_static_memory_usage() / 1048576.0)
		_bench_n += 1
		if _bench_n % 300 == 0:
			print("[BENCH] 采样中 frame=%d/%d fps=%.1f" % [_bench_n, _bench_target, Engine.get_frames_per_second()])
		if _bench_n >= _bench_target:
			_dump_bench()

	# 截图测试:--screenshot <帧号> <输出路径>
	if _shot_frame > 0:
		_shot_frame -= 1
		if _shot_frame == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("[SHOT] 已保存截图: ", _shot_path)
			get_tree().quit()
	# QA 帧时间尖峰压测采样:--perf-stress <帧数>
	if _ps_stress_on:
		if G.state == "playing" or G.state == "dead":
			_ps_times.append(dt_raw)
			_ps_stress_n += 1
			if dt_raw > 0.25:
				_ps_gt250 += 1
			if dt_raw > 0.1:
				_ps_gt100 += 1
			if dt_raw > 0.05:
				print("[SPIKE] frame=%d dt=%.0fms state=%s bots=%d vehicles=%d aircraft=%d nodes=%d" % [
					Engine.get_process_frames(), dt_raw * 1000.0, G.state, G.bots.size(), G.vehicles.size(), G.aircraft.size(),
					Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
			if _ps_stress_n % 300 == 0:
				print("[STRESS] frame=%d fps=%.1f" % [_ps_stress_n, Engine.get_frames_per_second()])
			if _ps_stress_n >= _ps_stress_target:
				_dump_stress()
				get_tree().quit()


## [PERF] 构建 Debug 性能监控浮层(CanvasLayer + Label,最顶层)
func _build_perf_monitor() -> void:
	_perf_layer = CanvasLayer.new()
	_perf_layer.layer = 100
	add_child(_perf_layer)
	_perf_label = Label.new()
	_perf_label.position = Vector2(12, 12)
	_perf_label.add_theme_font_size_override("font_size", 15)
	_perf_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_perf_label.add_theme_constant_override("outline_size", 5)
	_perf_label.text = "PERF MONITOR ..."
	_perf_layer.add_child(_perf_label)


## [PERF] 子系统计时累加(--bench-sys)
func _bsys_tick(sys_name: String, t0: int) -> void:
	if not _bsys_on:
		return
	var d: Dictionary = _bsys.get(sys_name, {})
	if d.is_empty():
		d = { "t": 0.0, "max": 0.0, "n": 0 }
	var us := float(Time.get_ticks_usec() - t0)
	d["t"] += us
	d["max"] = maxf(float(d["max"]), us)
	d["n"] = int(d["n"]) + 1
	_bsys[sys_name] = d


## [PERF] 子系统计时汇报(--bench-sys;每 900 帧打印 avg/max)
func _bsys_report() -> void:
	if not _bsys_on:
		return
	_bsys_n += 1
	if _bsys_n < 900:
		return
	var parts: Array = []
	for key in _bsys:
		var d: Dictionary = _bsys[key]
		parts.append("%s=%.0f/%.0fus" % [key, d["t"] / maxf(float(d["n"]), 1.0), d["max"]])
	print("[BENCH-SYS] " + "  ".join(parts))
	_bsys.clear()
	_bsys_n = 0


## [PERF] 刷新性能监控文本:实时 FPS/帧时间/CPU/物理/AI/DrawCall/对象/可见对象/NPC/粒子/内存/显存
func _update_perf_label() -> void:
	var fps := Engine.get_frames_per_second()
	var ft := 1000.0 / maxf(fps, 0.1)
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var rs := RenderingServer
	var dc := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var vram := rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	var smem := OS.get_static_memory_usage() / 1048576.0
	var npc := G.bots.size()
	var parts := 0
	if G.effects != null and G.effects.has_method("particle_count"):
		parts = G.effects.particle_count()
	_perf_label.text = (
		"FPS %5.1f   FT %4.2fms\n" % [fps, ft] +
		"CPU %4.2fms  Phys %4.2fms  AI %4.2fms\n" % [proc, phys, _ai_time_us / 1000.0] +
		"DrawCall %d  Obj %d  Node %d\n" % [dc, objs, nodes] +
		"NPC %d  Particle %d\n" % [npc, parts] +
		"Mem %dMB  VRAM %dMB" % [int(smem), int(vram)])


## [8/10] --bench 结果汇总:avg/min/1%Low FPS + CPU/GPU 帧时间 + DrawCalls/Objects/内存,写 json + 打印
func _dump_bench() -> void:
	var n := _bench_fts.size()
	if n == 0:
		print("[BENCH] 无采样数据(state 未进入 playing)")
		return
	var fts := _bench_fts.duplicate()
	fts.sort()
	var total := 0.0
	for t in _bench_fts:
		total += t
	var avg_ms: float = total / n
	var p1_ms: float = fts[clampi(int(n * 0.99), 0, n - 1)]  # 1% 最差帧时间(99 分位)
	var p95_ms: float = fts[clampi(int(n * 0.95) - 1, 0, n - 1)]
	var max_ms: float = fts[n - 1]
	var avg_fps: float = 1000.0 / maxf(avg_ms, 0.01)
	var p1_fps: float = 1000.0 / maxf(p1_ms, 0.01)
	# 聚合
	var avg_proc := 0.0
	var avg_phys := 0.0
	var avg_dc := 0.0
	var max_dc := 0
	var avg_prims := 0.0
	var avg_objs := 0.0
	var avg_nodes := 0.0
	var avg_mem := 0.0
	for i in n:
		avg_proc += _bench_proc[i]
		avg_phys += _bench_phys[i]
		avg_dc += _bench_dc[i]
		max_dc = maxi(max_dc, _bench_dc[i])
		avg_prims += _bench_prims[i]
		avg_objs += _bench_objs[i]
		avg_nodes += _bench_nodes[i]
		avg_mem += _bench_mem[i]
	avg_proc /= n; avg_phys /= n; avg_dc /= n
	avg_prims /= n; avg_objs /= n; avg_nodes /= n; avg_mem /= n
	print("[BENCH] ===== 汇总 标签=%s frames=%d =====" % [_bench_label, n])
	print("[BENCH] avg=%.1ffps(%.2fms) 1%%Low=%.1ffps(%.2fms) p95=%.2fms max=%.2fms" % [avg_fps, avg_ms, p1_fps, p1_ms, p95_ms, max_ms])
	print("[BENCH] process=%.2fms physics=%.2fms drawcalls=%.0f(max %d) prims=%.0f obj=%.0f nodes=%.0f mem=%.0fMB" % [
		avg_proc, avg_phys, avg_dc, max_dc, avg_prims, avg_objs, avg_nodes, avg_mem])
	var cf := ConfigFile.new()
	var label: String = _bench_label if _bench_label != "" else G.current_map + "_" + G.mode
	cf.set_value("bench", "label", label)
	cf.set_value("bench", "frames", n)
	cf.set_value("bench", "avg_fps", avg_fps)
	cf.set_value("bench", "avg_ft_ms", avg_ms)
	cf.set_value("bench", "p1_fps", p1_fps)
	cf.set_value("bench", "p1_ft_ms", p1_ms)
	cf.set_value("bench", "p95_ft_ms", p95_ms)
	cf.set_value("bench", "max_ft_ms", max_ms)
	cf.set_value("bench", "process_ms", avg_proc)
	cf.set_value("bench", "physics_ms", avg_phys)
	cf.set_value("bench", "draw_calls", avg_dc)
	cf.set_value("bench", "max_draw_calls", max_dc)
	cf.set_value("bench", "primitives", avg_prims)
	cf.set_value("bench", "render_objects", avg_objs)
	cf.set_value("bench", "nodes", avg_nodes)
	cf.set_value("bench", "mem_mb", avg_mem)
	var path := "user://perf_bench_" + label + ".cfg"
	cf.save(path)
	print("[BENCH] 已写入: ", path)
	get_tree().quit()


## --perf-stress 结果汇总:平均 FPS / 帧时间 p95/p99/max / 尖峰次数(>250ms 单帧 / >100ms)
func _dump_stress() -> void:
	var n := _ps_times.size()
	if n == 0:
		print("[STRESS] 无采样数据(state 未进入 playing)")
		return
	var total := 0.0
	var sorted := _ps_times.duplicate()
	sorted.sort()
	for t in sorted:
		total += t
	var p95_ms: float = sorted[clampi(int(n * 0.95) - 1, 0, n - 1)] * 1000.0
	var p99_ms: float = sorted[clampi(int(n * 0.99) - 1, 0, n - 1)] * 1000.0
	print("[STRESS] ===== 汇总 ===== frames=%d avg=%.1ffps avg_ft=%.2fms p95=%.2fms p99=%.2fms max=%.2fms >250ms=%d >100ms=%d" % [
		n, n / total, total / n * 1000.0, p95_ms, p99_ms, sorted[n - 1] * 1000.0, _ps_gt250, _ps_gt100])



## 载具视角 QA:截一帧存 PNG
func _qa_shot(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("E:/工作目录2/models_probe/qa_%s.png" % tag)
		print("[TEST-SHOT] ", tag)


## 第一人称腰射(hip)枪位截图:--test-hip-shot(配合 --test-play,可前置 --test-gun <id>)
## 部署后静止站立不 ADS,待切枪动画与 sway 稳定后正前视角截一帧 —— 用于
## 对比参考游戏的持枪画面横向位置(枪中轴应在画面中心偏右一点点)
func _run_hip_shot() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[TEST] 玩家未部署,hip 截图跳过")
		get_tree().quit()
		return
	await get_tree().create_timer(2.2).timeout
	var gid: String = G.player.gun().id if G.player.gun() != null else "default"
	await _qa_shot("hip_" + gid)
	print("[TEST] hip 截图完成:", gid)
	get_tree().quit()


## 主菜单整屏截图:--test-menu-shot(不部署;等菜单背景城市构建完成再截)
func _run_menu_shot() -> void:
	# 菜单背景城市在主菜单显示后异步构建([PERF] 菜单背景城市构建完成),给足 6s
	await get_tree().create_timer(6.0).timeout
	await _qa_shot("menu_main")
	print("[TEST] 主菜单截图完成")
	get_tree().quit()


## ADS 三点一线批量验证:--test-ads-line <all|id>
## 每把枪满镜后 muzzle 世界坐标 unproject 到屏幕,输出与屏幕中心的偏差
## (px 与半屏高百分比);偏差 >6% 半屏高判 FAIL(doom 视角)
func _run_ads_line(which: String) -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[ADS-LINE] 玩家未部署,跳过")
		get_tree().quit()
		return
	var ids: Array = []
	if which == "all":
		for wd_id in WeaponsData.W().keys():
			ids.append(wd_id)
	else:
		ids.append(which)
	var vp_size := get_viewport().get_visible_rect().size
	var center := vp_size * 0.5
	var fail := 0
	var tested := 0
	for gid in ids:
		if not WeaponsData.W().has(gid):
			continue
		var def = WeaponsData.W()[gid]
		if def.scope:
			continue   # 狙击满镜走镜内遮罩,枪模不可见,无三点一线概念
		# 装配并切枪
		for g in G.player.guns:
			G.vm_camera.remove_child(g.group)
			g.group.queue_free()
		G.player.guns = [Gun.new(gid, G.player)]
		G.vm_camera.add_child(G.player.guns[0].group)
		G.player.gun_index = 0
		G.player.gun().equip()
		Input.action_press("ads")
		await get_tree().create_timer(1.2).timeout
		var gun = G.player.gun()
		var mzl: Node3D = gun.group.get_meta("muzzle", null)
		if mzl == null:
			print("[ADS-LINE] %-8s 无 muzzle meta,跳过" % gid)
			continue
		var wpos: Vector3 = mzl.global_position
		var sp: Vector2 = get_viewport().get_camera_3d().unproject_position(wpos)
		var dy_pct: float = (sp.y - center.y) / (vp_size.y * 0.5) * 100.0
		var dx_pct: float = (sp.x - center.x) / (vp_size.x * 0.5) * 100.0
		tested += 1
		var ok := absf(dy_pct) <= 6.0 and absf(dx_pct) <= 6.0
		if not ok:
			fail += 1
		print("[ADS-LINE] %-8s 枪口屏幕偏差 dx=%+.1f%% dy=%+.1f%% (%s)" % [
			gid, dx_pct, dy_pct, "OK" if ok else "FAIL"])
		Input.action_release("ads")
	print("[ADS-LINE] 完成:测试 %d 枪,FAIL %d 枪" % [tested, fail])
	get_tree().quit()


## 载具战地式座位/视角序列验证:上车(炮手位=驾驶+开炮) → 第三人称开炮 →
## 右键 ADS(第一人称目镜,藏炮管) → 观察位(第三人称旁观,AA 机枪开火)
func _run_vehicle_qa(vtype: String) -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[TEST] 玩家未部署,载具 QA 跳过")
		return
	var v := Vehicle.new(G.player.pos.x + 6.0, G.player.pos.z, 0.0, vtype)
	G.vehicles.append(v)
	G.main.add_child(v)
	await get_tree().create_timer(0.8).timeout
	G.player.enter_vehicle(v)
	print("[TEST] 已上车:", vtype)
	# [FIX 船桨轮] 断言:轮自转节点名单不得混入轮拱/装饰件(WheelArch 等)
	if v.mesh.has_meta("wheels"):
		var wn := PackedStringArray()
		for w in v.mesh.get_meta("wheels"):
			wn.append(String(w.name))
		var arch_bad := 0
		for n in wn:
			if n.contains("Arch"):
				arch_bad += 1
		print("[TEST] wheels(%d): %s" % [wn.size(), ", ".join(wn)])
		print("[TEST] 轮名单断言: %s" % ["OK 无 Arch 误配" if arch_bad == 0 else "FAIL %d 个 Arch 误配" % arch_bad])
	await get_tree().create_timer(1.6).timeout
	await _qa_shot("veh_" + vtype + "_tp")
	# TP 炮塔跟随实测:轨道相机左转 0.8rad → 炮塔应收敛到同向
	var yaw_before_tp: float = v.turret_yaw
	v.camera_ctl.apply_tp_orbit(-400.0, 0.0)   # 像素:≈0.88rad
	await get_tree().create_timer(1.5).timeout
	print("[TEST] TP 炮塔跟随: yaw %.3f → %.3f (%s)" % [yaw_before_tp, v.turret_yaw,
		"OK" if absf(v.turret_yaw - yaw_before_tp) > 0.3 else "FAIL 不跟随"])
	Input.action_press("fire")
	await get_tree().create_timer(0.35).timeout
	Input.action_release("fire")
	await get_tree().create_timer(0.8).timeout
	await _qa_shot("veh_" + vtype + "_tp_fire")
	Input.action_press("ads")
	await get_tree().create_timer(1.1).timeout
	# ADS 炮塔跟随实测:目镜内鼠标右转 → 炮塔 yaw 应显著变化(旧版死循环恒 0)
	var yaw_before_ads: float = v.turret_yaw
	v.camera_ctl.apply_look(300.0, 0.0)
	await get_tree().create_timer(1.6).timeout
	print("[TEST] ADS 炮塔跟随: yaw %.3f → %.3f (%s)" % [yaw_before_ads, v.turret_yaw,
		"OK" if absf(v.turret_yaw - yaw_before_ads) > 0.1 else "FAIL 不跟随"])
	await _qa_shot("veh_" + vtype + "_ads")
	Input.action_release("ads")
	await get_tree().create_timer(0.7).timeout
	G.player._cycle_vehicle_station(v)
	print("[TEST] 已切观察位")
	await get_tree().create_timer(1.2).timeout
	await _qa_shot("veh_" + vtype + "_observer")
	if vtype == "aa":
		Input.action_press("fire")
		await get_tree().create_timer(0.5).timeout
		await _qa_shot("veh_" + vtype + "_observer_fire")
		Input.action_release("fire")
	G.player._cycle_vehicle_station(v)
	await get_tree().create_timer(0.6).timeout
	print("[TEST] 载具视角 QA 序列完成:", vtype)
	get_tree().quit()


## 吉普乘客位 QA:--test-jeep-passenger(配合 --test-play conquest)
## 编排:NPC 司机登车起步 → 玩家上车(应坐乘客位不顶司机/强制第一人称) →
## FP 开火 → F 换岗守卫(司机在位不可抢驾驶位) → 玩家下车恢复
func _run_jeep_passenger_qa() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[JEEPSAFE] 玩家未部署,QA 跳过")
		return
	var p = G.player
	# 选址:远离最近载具,避免误抓战场吉普
	var vx: float = p.pos.x + 9.0
	var vz: float = p.pos.z
	for ov in G.vehicles:
		if not ov.dead and Vector2(ov.pos.x - vx, ov.pos.z - vz).length() < 30.0:
			vx = p.pos.x - 12.0
			break
	var v := Vehicle.new(vx, vz, 0.0, "jeep")
	G.vehicles.append(v)
	G.main.add_child(v)
	await get_tree().create_timer(0.8).timeout
	# 召同队空闲 bot 当司机(步行登车)
	var driver = null
	for b in G.bots:
		if b.alive and b.team == p.team and b.vehicle == null:
			driver = b
			break
	if driver == null:
		print("[JEEPSAFE] FAIL 无可用 bot 当司机")
		get_tree().quit()
		return
	driver.board_vehicle_as_driver(v)
	print("[JEEPSAFE] 已指派 bot=%d 登车当司机,等待登车…" % driver.id)
	waited = 0.0
	while (v.driver == null) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if v.driver == null:
		print("[JEEPSAFE] FAIL bot 登车超时(25s)")
		get_tree().quit()
		return
	await get_tree().create_timer(1.2).timeout
	var drv_pos0: Vector3 = v.pos
	print("[JEEPSAFE] 司机就位 bot=%d vehicle=%s 车速=%.2f" % [driver.id, "司机本车" if driver.vehicle == v else "未挂车", absf(v.speed)])
	await get_tree().create_timer(1.5).timeout
	print("[JEEPSAFE] NPC 驾驶确认: ai_input=%s 车位移=%.2fm" % ["有" if v.ai_input != null else "无", Vector2(v.pos.x - drv_pos0.x, v.pos.z - drv_pos0.z).length()])
	# 玩家上车(核心断言:不顶司机 + 乘客位 + 强制第一人称)
	var drv_before = v.driver
	p.enter_vehicle(v)
	await get_tree().process_frame
	await get_tree().process_frame
	var ok_driver: bool = v.driver == drv_before and v.driver != p
	var ok_gunner: bool = v.gunner == p
	var ok_fp: bool = p._veh_fp_passenger and p._veh_crew == 1
	var ok_view: bool = v.camera_ctl != null and v.camera_ctl.view == FirstPersonVehicleController.VehView.FP_DRIVER
	print("[JEEPSAFE] 断言①不顶司机: %s (driver==原NPC:%s)" % ["OK" if ok_driver else "FAIL", str(ok_driver)])
	print("[JEEPSAFE] 断言②玩家乘客位: %s (gunner==player:%s)" % ["OK" if ok_gunner else "FAIL", str(ok_gunner)])
	print("[JEEPSAFE] 断言③强制第一人称: %s (fp=%s crew=%d)" % ["OK" if ok_fp else "FAIL", str(p._veh_fp_passenger), p._veh_crew])
	print("[JEEPSAFE] 断言④FP视图: %s (view=%d)" % ["OK" if ok_view else "FAIL", v.camera_ctl.view if v.camera_ctl != null else -1])
	await get_tree().create_timer(1.2).timeout
	await _qa_shot("jeepsafe_enter")
	# 乘客位开火(个人武器完整管线)
	Input.action_press("fire")
	await get_tree().create_timer(0.4).timeout
	await _qa_shot("jeepsafe_fire")
	Input.action_release("fire")
	await get_tree().create_timer(0.6).timeout
	# NPC 继续驾驶确认(玩家在车上不应弃车/停车)
	var pos_mid: Vector3 = v.pos
	await get_tree().create_timer(1.5).timeout
	var moved: float = Vector2(v.pos.x - pos_mid.x, v.pos.z - pos_mid.z).length()
	print("[JEEPSAFE] 断言⑤NPC继续驾驶: %s (1.5s 位移 %.2fm 速度 %.2f)" % ["OK" if v.driver == drv_before else "FAIL", moved, absf(v.speed)])
	# F 换岗守卫:司机在位时不可抢驾驶位
	p._cycle_vehicle_station(v)
	await get_tree().create_timer(0.5).timeout
	var ok_guard: bool = v.driver == drv_before and p._veh_crew == 1
	print("[JEEPSAFE] 断言⑥F守卫拒抢驾驶位: %s (crew=%d)" % ["OK" if ok_guard else "FAIL", p._veh_crew])
	# 玩家下车恢复
	p.exit_vehicle()
	await get_tree().create_timer(0.5).timeout
	print("[JEEPSAFE] 断言⑦下车恢复: %s (vehicle=%s gunner清理=%s fp=%s)" % [
		"OK" if p.vehicle == null and v.gunner == null and not p._veh_fp_passenger else "FAIL",
		"无" if p.vehicle == null else "仍在车", str(v.gunner == null), str(p._veh_fp_passenger)])
	await _qa_shot("jeepsafe_exit")
	print("[JEEPSAFE] QA 序列完成")
	get_tree().quit()


## 空中载具建模 QA:GLB 悬浮在玩家上空,四角度截图 + 契约节点检查
func _run_aircraft_qa(kind: String) -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[TEST] 玩家未部署,空中 QA 跳过")
		return
	var m: Node3D
	match kind:
		"heli":
			m = AircraftModels.build_heli("us")
		"jet":
			m = AircraftModels.build_jet("us")
		_:
			m = VehicleModels.build_tank()
	var base: Vector3 = G.player.pos + Vector3(0, 8.0, 0)
	m.position = base
	G.main.add_child(m)
	await get_tree().create_timer(0.5).timeout
	print("[TEST-AIR] kind=", kind, " rotor=", m.has_meta("rotor"), " tail=", m.has_meta("tail_rotor"),
		" burner=", m.has_meta("burner"))
	# 独立 QA 相机(make_current 顶掉玩家第一人称相机 —— 玩家每帧覆写 G.camera)
	var cam := Camera3D.new()
	cam.fov = 55.0
	G.main.add_child(cam)
	cam.make_current()
	for a in [[0.0, 15.0, 3.5, "front"], [16.0, 0.0, 2.5, "side"], [9.0, 6.0, 9.0, "top"], [-14.0, 10.0, 6.0, "rear"]]:
		cam.global_position = base + Vector3(a[0], a[2], a[1])
		cam.look_at(base)
		await get_tree().process_frame
		await get_tree().process_frame
		await _qa_shot("air_" + kind + "_" + a[3])
	print("[TEST-AIR] 完成:", kind)
	get_tree().quit()


## 车底专项 QA:全部载具悬空 10m,仰拍车底 + 数值扫描穿透节点
## 每台 6 张:正下方 under / 斜下 45° ×4 / 远景 far;报告写 belly_report.txt
func _run_belly_qa() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[TEST] 玩家未部署,车底 QA 跳过")
		return
	var kinds := ["jeep", "tank", "apc", "aa", "heli", "jet"]
	var cam := Camera3D.new()
	cam.fov = 60.0
	G.main.add_child(cam)
	cam.make_current()
	var report := PackedStringArray()
	for kind in kinds:
		var m: Node3D
		match kind:
			"jeep":
				m = VehicleModels.build_jeep()
			"tank":
				m = VehicleModels.build_tank()
			"apc":
				m = VehicleModels.build_apc()
			"aa":
				m = VehicleModels.build_aa()
			"heli":
				m = AircraftModels.build_heli("us")
			"jet":
				m = AircraftModels.build_jet("us")
		var base: Vector3 = G.player.pos + Vector3(0, 10.0, 0)
		m.position = base
		G.main.add_child(m)
		await get_tree().process_frame
		await get_tree().process_frame
		# 数值诊断:整车全局 AABB + 穿透车体底面(局部 y<-0.05)的节点
		var aabb := _qa_merged_aabb(m)
		report.append("[%s] 全车AABB: min_y=%.3f max_y=%.3f 高=%.3f" % [
			kind, aabb.position.y - base.y, aabb.position.y + aabb.size.y - base.y, aabb.size.y])
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var wa: AABB = mi.global_transform * mi.get_aabb()
			if wa.position.y < base.y - 0.05:
				report.append("  [穿透车底] %s: 低于原点 %.3f m" % [String(mi.name), base.y - wa.position.y])
		var shots := [[1.2, -7.0, 1.2, "under"], [0.0, -5.5, 8.0, "belly_front"],
			[0.0, -5.5, -8.0, "belly_rear"], [8.0, -5.5, 0.0, "belly_left"],
			[-8.0, -5.5, 0.0, "belly_right"], [13.0, 3.0, 13.0, "far_overview"]]
		for s in shots:
			cam.global_position = base + Vector3(s[0], s[1], s[2])
			cam.look_at(base + Vector3(0, -0.6, 0), Vector3(0, 0, 1))
			await get_tree().process_frame
			await get_tree().process_frame
			await _qa_shot("belly_" + kind + "_" + s[3])
		report.append("")
		m.queue_free()
		await get_tree().process_frame
	FileAccess.open("E:/工作目录2/models_probe/belly_report.txt", FileAccess.WRITE).store_string("\n".join(report))
	print("[TEST-BELLY] 6 台完成,报告: E:/工作目录2/models_probe/belly_report.txt")
	get_tree().quit()


## 递归合并节点树所有 MeshInstance3D 的全局 AABB
func _qa_merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var wa: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = wa
			first = false
		else:
			out = out.merge(wa)
	return out


## GLB 解剖:打印异常节点(低于 y=0 或炮塔链)的节点变换/局部/世界 AABB
func _run_veh_xray(id: String) -> void:
	var path := "res://models/vehicles/%s.glb" % id
	if not ResourceLoader.exists(path):
		print("[XRAY] 缺失: ", path)
		get_tree().quit()
		return
	var ps: PackedScene = load(path)
	var g: Node3D = ps.instantiate()
	G.main.add_child(g)
	await get_tree().process_frame
	print("[XRAY] === ", id, " ===")
	for c in g.find_children("*", "MeshInstance3D", true, false):
		var t := (c as MeshInstance3D).global_transform
		var wa: AABB = t * (c as MeshInstance3D).get_aabb()
		var low := wa.position.y < -0.01
		var key := String(c.name).contains("Turret") or String(c.name).contains("Cannon") \
			or String(c.name).contains("Muzzle") or String(c.name).contains("Barrel")
		if low or key:
			print("[XRAY] %-14s 局pos=%s 网格min=%s 世界y=[%.3f, %.3f]" % [
				String(c.name), t.origin, (c as MeshInstance3D).get_aabb().position,
				wa.position.y, wa.position.y + wa.size.y])
	print("[XRAY] 完成")
	get_tree().quit()


## 全导轨枪械认证:逐把检视照 + ADS 照(导轨方向/穿模逐一目检)
func _run_rail_certify() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[RAIL] 玩家未部署,跳过")
		return
	var rail_guns := ["m1014", "m4", "scar", "aug", "g36c", "ump", "p90", "vector",
		"mpx", "mp7", "pp2000", "negev", "m110", "g28", "mk14", "ar10"]
	G.player.spawn_protect = 60
	Input.action_release("ads")
	# 选址:随机出生点可能贴着帐篷/集装箱(相机被内壁+立柱遮挡,整屏报废)。
	# 从出生点探测四向 9m 净距,朝最开阔方向平移 6m,直到四向 ≥8m 全净或步数用尽。
	var body := G.player as CharacterBody3D
	if body != null:
		var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
		for step in 6:
			var base: Vector3 = body.global_position + Vector3(0, 1.5, 0)
			var best_dir := Vector3.ZERO
			var best_len := -1.0
			var blocked := false
			for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
				var q := PhysicsRayQueryParameters3D.create(base, base + d * 9.0)
				q.exclude = [body.get_rid()]
				var hit := space.intersect_ray(q)
				var l: float = 9.0 if hit.is_empty() else float(base.distance_to(hit.position))
				if l < 8.0:
					blocked = true
				if l > best_len:
					best_len = l
					best_dir = d
			if not blocked or best_dir == Vector3.ZERO:
				break
			body.global_position += best_dir * 6.0
			body.velocity = Vector3.ZERO
		print("[RAIL] 选址: ", body.global_position)
	var done := PackedStringArray()
	for gid in rail_guns:
		# 卸下当前主武器(含玩家出生自带的枪 —— 不卸会残留在 vm_camera 挡住画面)
		# 注意:Gun 是 RefCounted 包装,不能用 Node 类型注解
		var old = G.player.guns[0] if G.player.guns.size() > 0 else null
		if old != null and old.get("group") != null:
			G.vm_camera.remove_child(old.group)
			old.group.queue_free()
		var ng := Gun.new(gid, G.player)
		G.player.guns[0] = ng
		G.player.gun_index = 0  # 必须指向当前槽:非当前枪不跑 update,draw_t 永远 0,检视/ADS 姿态全失效
		G.vm_camera.add_child(ng.group)
		ng.equip()
		await get_tree().create_timer(1.3).timeout  # 等出枪(draw_t>0.9 才能 inspect)
		ng = G.player.guns[0]
		# 检视动画中段:枪转到屏幕中央,顶轨/侧轨方向一目了然
		print("[RAIL] %s pre: eq=%s draw=%.2f sprint=%.2f ground=%s pump=%.2f bolt=%.2f semi=%.2f" % [
			gid, ng.equipped, ng.draw_t, G.player.sprint_amount, G.player.on_ground,
			ng.pump_t, ng.bolt_t, ng.semi_t])
		ng.try_inspect()
		print("[RAIL] %s inspecting=%s t=%.2f" % [gid, ng.is_inspecting(), ng.inspect_t])
		await get_tree().create_timer(1.7).timeout
		await _qa_shot("rail_" + gid + "_inspect")
		ng._stop_inspect()
		# 满 ADS 实战视野
		Input.action_press("ads")
		ng.ads_amount = 1.0
		await get_tree().create_timer(0.7).timeout
		await _qa_shot("rail_" + gid + "_ads")
		Input.action_release("ads")
		done.append(gid)
		print("[RAIL] 已认证: ", gid, " (", done.size(), "/", rail_guns.size(), ")")
		await get_tree().process_frame
	print("[RAIL] 完成 ", done.size(), " 把: ", " ".join(done))
	get_tree().quit()


## 枪械 X 光:枪模单独悬空 + 独立相机 5 机位环绕(导轨方向/穿模几何认证)。
## --test-gun-xray scar 单把(额外拍无改装对照 + 打印超宽件) / --test-gun-xray all 全部导轨枪
func _run_gun_xray(gxid: String) -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[GXRAY] 玩家未部署,跳过")
		return
	var gids: Array = []
	if gxid == "all":
		gids = ["m1014", "m4", "scar", "aug", "g36c", "ump", "p90", "vector",
			"mpx", "mp7", "pp2000", "negev", "m110", "g28", "mk14", "ar10"]
	else:
		gids = [gxid]
	G.player.spawn_protect = 60
	Input.action_release("ads")
	if G.hud != null:
		G.hud.visible = false   # 画面只留被测枪
	# 卸下玩家当前主武器渲染组(不 free:player 每帧仍会 update 该 Gun,free 会炸)
	if G.player.guns.size() > 0:
		var old0 = G.player.guns[0]
		if old0 != null and old0.get("group") != null:
			G.vm_camera.remove_child(old0.group)
	# 悬空锚点:出生点上空 30m,阳光直射无遮挡
	var anchor := Node3D.new()
	G.main.add_child(anchor)
	var p0: Vector3 = G.player.pos
	anchor.global_position = Vector3(p0.x, p0.y + 30.0, p0.z)
	var cam := Camera3D.new()
	cam.fov = 30.0
	G.main.add_child(cam)
	for gid in gids:
		var variants: Array = [["mod", WeaponModsData.load_cfg(gid)]]
		if gxid != "all":
			variants.append(["plain", {}])   # 单把模式:无改装对照(隔离配件与本体)
		for vv in variants:
			var model: Node3D = WeaponModels.build(gid, false, vv[1])
			anchor.add_child(model)
			await get_tree().process_frame
			var ab := _qa_merged_aabb(model)
			var ctr: Vector3 = ab.get_center()
			model.position -= ctr - anchor.global_position   # 模型包围盒中心对齐锚点
			var span: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
			var D: float = span * 1.2 + 0.3
			if vv[0] == "plain":
				# 数值解剖:打印超出机匣半宽的网格件(横向穿模元凶直接点名)
				var half_w: float = ab.size.x * 0.5
				for mi in model.find_children("*", "MeshInstance3D", true, false):
					var mm := mi as MeshInstance3D
					var wa: AABB = mm.global_transform * mm.get_aabb()
					var lx: float = maxf(absf(wa.position.x), absf(wa.position.x + wa.size.x))
					if lx > half_w + 0.004:
						print("[GXRAY] %s 超宽件 %s x_max=%.3f y=[%.3f,%.3f] z=[%.3f,%.3f]" % [
							gid, mm.name, lx, wa.position.y, wa.position.y + wa.size.y,
							wa.position.z, wa.position.z + wa.size.z])
			var views := {
				"top": [Vector3(0, D, 0.0001), Vector3(0, 0, -1)],
				"left34": [Vector3(-D * 0.8, D * 0.5, -D * 0.62), Vector3(0, 1, 0)],
				"right34": [Vector3(D * 0.8, D * 0.5, -D * 0.62), Vector3(0, 1, 0)],
				"left": [Vector3(-D, 0.02, 0), Vector3(0, 1, 0)],
				"right": [Vector3(D, 0.02, 0), Vector3(0, 1, 0)],
			}
			for vname in views:
				var off: Vector3 = views[vname][0]
				var upv: Vector3 = views[vname][1]
				cam.global_position = anchor.global_position + off
				cam.look_at(anchor.global_position, upv)
				cam.make_current()
				await get_tree().process_frame
				await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				var tag: String = "xray_%s_%s%s" % [gid, vname, "" if vv[0] == "mod" else "_plain"]
				if img != null:
					img.save_png("E:/工作目录2/models_probe/%s.png" % tag)
					print("[GXRAY-SHOT] ", tag)
			anchor.remove_child(model)
			model.free()
		print("[GXRAY] 完成: ", gid)
	print("[GXRAY] 全部完成 ", gids.size(), " 把")
	get_tree().quit()


## 性能剖析:等部署完成后采样 8s —— FPS/帧耗时/draw calls/图元/对象数/显存
func _run_perf_probe() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 40.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[PERF] 玩家未部署,跳过")
		return
	print("[PERF] === 部署完成于 %.2fs,开始采样 ===" % (Time.get_ticks_msec() / 1000.0))
	# 三阶段对比定位瓶颈:A 正常 4s → B 关太阳阴影 3s → C 关 MSAA 3s
	for stage in 5:
		if stage == 1 and G.sun != null:
			G.sun.shadow_enabled = false
			_perf_log("--- 阶段B: 太阳阴影关闭 ---")
		elif stage == 2:
			if G.sun != null:
				G.sun.shadow_enabled = true
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			_perf_log("--- 阶段C: MSAA 关闭 ---")
		elif stage == 3:
			get_viewport().msaa_3d = Viewport.MSAA_2X
			for b in G.bots:
				if b.mesh != null:
					b.mesh.visible = false
			_perf_log("--- 阶段D: 隐藏全部士兵 ---")
		elif stage == 4:
			for b in G.bots:
				if b.mesh != null:
					b.mesh.visible = true
			for v in G.vehicles:
				if v.mesh != null:
					v.mesh.visible = false
			_perf_log("--- 阶段E: 士兵恢复+隐藏载具 ---")
		else:
			_perf_log("--- 阶段A: 正常 ---")
		var fps_sum := 0.0
		var fps_min := 9999.0
		var dc_max := 0
		var prim_max := 0.0
		var n := 6
		for i in n:
			await get_tree().create_timer(0.5).timeout
			var fps: float = Performance.get_monitor(Performance.TIME_FPS)
			var dc: int = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var prim: float = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			fps_min = minf(fps_min, fps)
			fps_sum += fps
			dc_max = maxi(dc_max, dc)
			prim_max = maxf(prim_max, prim)
			_perf_log("%d-%d: fps=%.0f dc=%d prims=%.1fM obj=%d pipe=%d" % [
				stage, i, fps, dc, prim / 1_000_000.0,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)])
		_perf_log("=== 阶段%d 汇总: avg=%.0f min=%.0f dc_max=%d prims_max=%.1fM ===" % [
			stage, fps_sum / n, fps_min, dc_max, prim_max / 1_000_000.0])
	get_tree().quit()


var _perf_lines: PackedStringArray = []


func _perf_log(line: String) -> void:
	_perf_lines.append(line)
	FileAccess.open("E:/工作目录2/models_probe/perf_out.txt", FileAccess.WRITE).store_string("\n".join(_perf_lines))


## NPC 士兵 GLB 管线认证:--test-npc
## ① 结构打印(动画列表/骨骼数/材质覆盖) ② 悬空 6 姿态截图(Idle/Walk/Run/Crouch/Prone/Death)
## ③ 战场实况一张(活 bot 交战中的新模型效果)
func _run_npc_check() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[NPC] 玩家未部署,跳过")
		return
	G.player.spawn_protect = 60
	if G.hud != null:
		G.hud.visible = false
	if G.player.guns.size() > 0:
		var old0 = G.player.guns[0]
		if old0 != null and old0.get("group") != null:
			G.vm_camera.remove_child(old0.group)
	# ---- ① 结构验证 ----
	var probe: Node3D = SoldierModel.build_soldier_glb("us", "m4", "assault", "standard")
	var pskel: Skeleton3D = probe.get_meta("skel")
	var panim: AnimationPlayer = probe.get_meta("anim")
	print("[NPC] skel=%s anim=%s" % [pskel != null, panim != null])
	if pskel != null:
		print("[NPC] 骨骼数=", pskel.get_bone_count(), " 关键骨: LegsRoot=", pskel.find_bone("LegsRoot"),
			" AimPitch=", pskel.find_bone("AimPitch"), " HandR=", pskel.find_bone("HandR"))
	if panim != null:
		print("[NPC] 动画列表: ", panim.get_animation_list())
	probe.free()
	# ---- ② 悬空 4 姿态截图 ----
	var anchor := Node3D.new()
	G.main.add_child(anchor)
	var p0: Vector3 = G.player.pos
	anchor.global_position = Vector3(p0.x, p0.y + 12.0, p0.z)
	var cam := Camera3D.new()
	cam.fov = 40.0
	G.main.add_child(cam)
	var poses := {
		"idle": ["Idle", 1.0],
		"walk": ["Walk", 0.3],
		"run": ["Run", 0.2],
		"crouch": ["Crouch", 1.0],
		"crouchwalk": ["CrouchWalk", 0.3],
		"prone": ["Prone", 1.0],
		"pronecrawl": ["ProneCrawl", 0.3],
		"death": ["Death", 1.15],
	}
	for pose in poses:
		var sm: Node3D = SoldierModel.build_soldier_glb("us", "m4", "assault", "standard")
		anchor.add_child(sm)
		# [修v5] 旧死亡动画悬空 0.82 需压镜头掩盖;location 轴修复后贴地,不再补偿
		var ap: AnimationPlayer = sm.get_meta("anim")
		ap.play(poses[pose][0])
		ap.advance(poses[pose][1])
		await get_tree().process_frame
		await get_tree().process_frame
		# 模型面朝 -Z:front34 机位放 -Z 侧,side 正右,back 在 +Z 后方
		var views := {
			"front34": [Vector3(-2.2, 1.4, -2.2)],
			"side": [Vector3(3.0, 1.1, 0.0)],
			"back": [Vector3(1.8, 1.5, 2.4)],
		}
		for vname in views:
			cam.global_position = anchor.global_position + views[vname][0]
			cam.look_at(anchor.global_position + Vector3(0, 0.9, 0), Vector3.UP)
			cam.make_current()
			await get_tree().process_frame
			await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var tag := "npc_%s_%s" % [pose, vname]
			if img != null:
				img.save_png("E:/工作目录2/models_probe/%s.png" % tag)
				print("[NPC-SHOT] ", tag)
		anchor.remove_child(sm)
		sm.free()
	# ---- ②b 四兵种建模差异巡检:全家福 front34 + 每兵种 side 特写 ----
	var cls_ids := ["assault", "engineer", "support", "recon"]
	var cls_wids := ["m4", "m249", "mp5", "awm"]
	var gp: Vector3 = anchor.global_position
	var fam_models: Array = []
	for i in 4:
		var cm: Node3D = SoldierModel.build_soldier_glb("us", cls_wids[i], cls_ids[i], "standard")
		cm.position = Vector3((i - 1.5) * 1.05, 0, 0)
		anchor.add_child(cm)
		var cap: AnimationPlayer = cm.get_meta("anim")
		cap.play("Idle")
		cap.advance(1.0)
		fam_models.append(cm)
	await get_tree().process_frame
	await get_tree().process_frame
	# 模型面朝 -Z:全家福机位放 -Z 侧
	cam.global_position = gp + Vector3(-2.6, 1.6, -3.4)
	cam.look_at(gp + Vector3(0, 0.9, 0), Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	var fam := get_viewport().get_texture().get_image()
	if fam != null:
		fam.save_png("E:/工作目录2/models_probe/npc_classes_family.png")
		print("[NPC-SHOT] npc_classes_family")
	for cm in fam_models:
		anchor.remove_child(cm)
		cm.free()
	await get_tree().process_frame
	# 单兵种 side 特写(逐个独立拍,特征件细节可辨)
	for i in 4:
		var so: Node3D = SoldierModel.build_soldier_glb("us", cls_wids[i], cls_ids[i], "standard")
		anchor.add_child(so)
		var sap: AnimationPlayer = so.get_meta("anim")
		sap.play("Idle")
		sap.advance(1.0)
		await get_tree().process_frame
		await get_tree().process_frame
		cam.global_position = gp + Vector3(2.6, 1.2, 0)
		cam.look_at(gp + Vector3(0, 0.95, 0), Vector3.UP)
		cam.make_current()
		await get_tree().process_frame
		await get_tree().process_frame
		var cimg := get_viewport().get_texture().get_image()
		if cimg != null:
			cimg.save_png("E:/工作目录2/models_probe/npc_class_%s.png" % cls_ids[i])
			print("[NPC-SHOT] npc_class_%s" % cls_ids[i])
		anchor.remove_child(so)
		so.free()
	# ---- ③ 战场实况(对准最近活 bot 的交战现场) ----
	var nb: Node3D = null
	var nd := 1e9
	for b in G.bots:
		if b == null or not is_instance_valid(b) or not b.alive or b.vehicle != null:
			continue
		var d: float = b.pos.distance_to(p0)
		if d > 8.0 and d < nd:
			nd = d
			nb = b
	var img2: Image = null
	if nb != null:
		var bp: Vector3 = nb.pos
		cam.global_position = bp + Vector3(2.6, 1.7, 2.6)
		cam.look_at(bp + Vector3(0, 1.0, 0), Vector3.UP)
		cam.make_current()
		await get_tree().create_timer(0.5).timeout
		await get_tree().process_frame
		img2 = get_viewport().get_texture().get_image()
		if img2 != null:
			img2.save_png("E:/工作目录2/models_probe/npc_battle_live.png")
			print("[NPC-SHOT] npc_battle_live bot_dist=%.0f" % nd)
	else:
		print("[NPC] 附近无活 bot,跳过实况")
	print("[NPC] 认证完成")
	get_tree().quit()


## 玩家第一人称身体 + 阴影认证:--test-pbody
## ①低头俯视腿部(骨骼 GLB 下半身) ②侧上视角人形阴影 ③切枪后阴影武器轮廓变化
func _run_pbody_check() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[PBODY] 玩家未部署,跳过")
		return
	var p = G.player
	p.spawn_protect = 60
	if G.hud != null:
		G.hud.visible = false
	await get_tree().create_timer(0.5).timeout
	# ①低头俯视腿部(第一人称主相机)
	p.pitch = -1.05
	p.recoil_pitch = 0
	await get_tree().create_timer(0.4).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("E:/工作目录2/models_probe/pbody_legs.png")
		print("[PBODY-SHOT] pbody_legs")
	# ②侧上视角看人形阴影(临时相机,先回平视让身体站立)
	p.pitch = 0
	var cam := Camera3D.new()
	cam.fov = 55.0
	G.main.add_child(cam)
	var bp: Vector3 = p.pos
	cam.global_position = bp + Vector3(4.2, 5.2, 4.2)
	cam.look_at(bp + Vector3(0, 0.3, 0), Vector3.UP)
	cam.make_current()
	await get_tree().create_timer(0.4).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 := get_viewport().get_texture().get_image()
	if img2 != null:
		img2.save_png("E:/工作目录2/models_probe/pbody_shadow.png")
		print("[PBODY-SHOT] pbody_shadow")
	# ③切枪重建影子武器,再拍阴影(轮廓应变化)
	var g0: int = p.gun_index
	if p.guns.size() > 1:
		p.gun_index = (p.gun_index + 1) % p.guns.size()
		p._update_body_gun()
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		var img3 := get_viewport().get_texture().get_image()
		if img3 != null:
			img3.save_png("E:/工作目录2/models_probe/pbody_shadow_switch.png")
			print("[PBODY-SHOT] pbody_shadow_switch weapon=", p.gun().id)
		p.gun_index = g0
		p._update_body_gun()
	# ④蹲姿(屈膝战斗蹲,非"腿缩一截")—— 相机对准身体实际位置(蹲/趴会把身体沿朝向前移)
	p.crouched = true
	await get_tree().create_timer(0.8).timeout
	var bp4: Vector3 = p.body.global_position if "body" in p else bp
	cam.global_position = bp4 + Vector3(4.6, 5.6, 4.6)
	cam.look_at(bp4 + Vector3(0, 0.4, 0), Vector3.UP)
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var img4 := get_viewport().get_texture().get_image()
	if img4 != null:
		img4.save_png("E:/工作目录2/models_probe/pbody_crouch.png")
		print("[PBODY-SHOT] pbody_crouch")
	# ⑤趴姿(贴地趴平+抬头,非"硬抬 45°")
	p.crouched = false
	p.prone = true
	await get_tree().create_timer(0.8).timeout
	var bp5: Vector3 = p.body.global_position if "body" in p else bp
	cam.global_position = bp5 + Vector3(4.6, 5.6, 4.6)
	cam.look_at(bp5 + Vector3(0, 0.2, 0), Vector3.UP)
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var img5 := get_viewport().get_texture().get_image()
	if img5 != null:
		img5.save_png("E:/工作目录2/models_probe/pbody_prone.png")
		print("[PBODY-SHOT] pbody_prone")
	p.prone = false
	cam.queue_free()
	print("[PBODY] 认证完成")
	get_tree().quit()


## 蹲姿游戏内实拍认证:--test-squat
## 玩家真实蹲下 + 强制最近 NPC 蹲下,近景多机位截真实游戏画面(非悬空摆拍)
func _run_squat_check() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[SQUAT] 玩家未部署,跳过")
		return
	var p = G.player
	p.spawn_protect = 60
	if G.hud != null:
		G.hud.visible = false
	# 躲 NPC 采样选址:出生点可能人挤人(近距离 bot 挡机位),取 8 方向 10m 采样点中
	# 离最近 bot/载具最远者传送过去,趁 AI 围拢前拍完(射线测不到自研碰撞,纯距离采样)
	var best_p: Vector3 = p.pos
	var best_bd := -1.0
	for i in 8:
		var ang := TAU * i / 8.0
		var cand: Vector3 = p.pos + Vector3(sin(ang), 0, cos(ang)) * 10.0
		var nd := 1e9
		for b in G.bots:
			if b != null and is_instance_valid(b) and b.alive:
				nd = minf(nd, (b.pos - cand).length())
		for v in G.vehicles:
			if v != null and is_instance_valid(v):
				nd = minf(nd, (v.pos - cand).length())
		if nd > best_bd:
			best_bd = nd
			best_p = cand
	p.pos = best_p
	p.vel = Vector3.ZERO
	print("[SQUAT] 选址 dist_to_nearest=%.1f" % best_bd)
	# 摘掉第一人称 viewmodel(独立相机会拍到挂在原点的枪,抢镜)
	var _sq_vmguns: Array = []
	for gg in p.guns:
		if gg != null and gg.get("group") != null and gg.group.get_parent() != null:
			_sq_vmguns.append([gg.group, gg.group.get_parent()])
			gg.group.get_parent().remove_child(gg.group)
	await get_tree().create_timer(0.3).timeout
	var cam := Camera3D.new()
	cam.fov = 50.0
	G.main.add_child(cam)
	# ---- 玩家蹲姿:真实蹲下,近景 3 机位 ----
	p.crouched = true
	await get_tree().create_timer(1.0).timeout
	var bp: Vector3 = p.body.global_position if "body" in p else p.pos
	# [实测] 浮空诊断:打印玩家原点/身体/Hips 骨/两脚骨的世界高度与地面高度
	var sk: Skeleton3D = p.body.get_meta("skel") if p.body.has_meta("skel") else null
	var gh: float = G.ground_h.call(p.pos.x, p.pos.z) if G.ground_h.is_valid() else 0.0
	print("[SQUAT] pos.y=%.3f body.y=%.3f ground=%.3f anim=%s" % [
		p.pos.y, p.body.global_position.y, gh,
		(p.body.get_meta("anim").current_animation if p.body.has_meta("anim") else "?")])
	if sk != null:
		for bn in ["Hips", "FootL", "FootR"]:
			var bi := sk.find_bone(bn)
			if bi >= 0:
				var gp: Vector3 = sk.get_bone_global_pose(bi).origin
				print("[SQUAT] bone %s world_y=%.3f (x=%.2f z=%.2f)" % [bn, p.body.global_position.y + gp.y, gp.x, gp.z])
	# 机位视线净空:静态世界(木箱/墙体)在物理空间内,射线挑无遮挡方位。
	# 每个机位从偏好方位起试 12 个方位角,第一个 LOS 全净的胜出;全堵则退化为高角俯拍。
	var body3d := p as CharacterBody3D
	var space: PhysicsDirectSpaceState3D = body3d.get_world_3d().direct_space_state if body3d != null else null
	var chest: Vector3 = bp + Vector3(0, 0.55, 0)
	var los_clear := func(campos: Vector3) -> bool:
		if space == null:
			return true
		var q := PhysicsRayQueryParameters3D.create(campos, chest)
		if body3d != null:
			q.exclude = [body3d.get_rid()]
		return space.intersect_ray(q).is_empty()
	var place_cam := func(hd: float, hh: float, start_ang: float) -> void:
		var ok := false
		for k in 12:
			var ang: float = start_ang + float(k) * TAU / 12.0
			var campos: Vector3 = bp + Vector3(sin(ang), 0.0, cos(ang)) * hd + Vector3(0, hh, 0)
			if not los_clear.call(campos):
				continue
			cam.global_position = campos
			cam.look_at(chest, Vector3.UP)
			ok = true
			break
		if not ok:  # 全方位被堵:最高角俯拍最不易挡
			cam.global_position = bp + Vector3(0.9, 2.8, 0.9)
			cam.look_at(chest, Vector3.UP)
		cam.make_current()
	var shots := {
		"squat_side":  [1.9, 0.75, 0.0],          # [水平距, 高度, 起始方位角] 纯侧视
		"squat_34":    [2.3, 1.70, PI * 0.25],    # 3/4 高角俯拍
		"squat_front": [2.0, 1.20, -PI * 0.5],    # 正面
		"squat_low":   [1.35, 0.35, PI * 0.75],   # 贴地仰角
	}
	for sname in shots:
		place_cam.call(shots[sname][0], shots[sname][1], shots[sname][2])
		await get_tree().create_timer(0.2).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("E:/工作目录2/models_probe/%s.png" % sname)
			print("[SQUAT-SHOT] ", sname)
	p.crouched = false
	# ---- NPC 蹲姿:强制最近活 bot 蹲下,游戏内实拍 ----
	var nb: Node = null
	var nd := 1e9
	for b in G.bots:
		if b == null or not is_instance_valid(b) or not b.alive or b.vehicle != null:
			continue
		var d: float = b.pos.distance_to(p.pos)
		if d < nd:
			nd = d
			nb = b
	if nb != null:
		nb.qa_lock_crouch = true   # AI 每帧 _decide_crouch 会覆盖 crouch,必须走 QA 锁
		await get_tree().create_timer(1.2).timeout
		var np: Vector3 = nb.pos
		var nchest: Vector3 = np + Vector3(0, 0.5, 0)
		var nok := false
		for k in 12:
			var ang := PI * 0.75 + float(k) * TAU / 12.0
			var ncam: Vector3 = np + Vector3(sin(ang), 0.0, cos(ang)) * 2.3 + Vector3(0, 1.1, 0)
			if space != null:
				var q2 := PhysicsRayQueryParameters3D.create(ncam, nchest)
				if not space.intersect_ray(q2).is_empty():
					continue
			cam.global_position = ncam
			cam.look_at(nchest, Vector3.UP)
			nok = true
			break
		if not nok:
			cam.global_position = np + Vector3(0.9, 2.8, 0.9)
			cam.look_at(nchest, Vector3.UP)
		cam.make_current()
		await get_tree().create_timer(0.2).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		var img3: Image = get_viewport().get_texture().get_image()
		if img3 != null:
			img3.save_png("E:/工作目录2/models_probe/squat_npc_live.png")
			print("[SQUAT-SHOT] squat_npc_live bot_dist=%.0f" % nd)
		nb.qa_lock_crouch = false
		nb.crouch = false
	else:
		print("[SQUAT] 附近无活 bot,跳过 NPC 实拍")
	cam.queue_free()
	# 还原 viewmodel
	for rec in _sq_vmguns:
		(rec[1] as Node).add_child(rec[0])
	print("[SQUAT] 认证完成")
	get_tree().quit()


## 死亡布娃娃 + 趴姿贴地 + 蹲走/匍匐步态认证:--test-death
## 4 死法(站/蹲/趴/站)双时刻截图 + 玩家趴姿骨位贴地数值 + 步态 bot 动画选片诊断
func _run_death_check() -> void:
	var waited := 0.0
	while (G.state == "menu" or G.player == null or not G.player.alive) and waited < 25.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if G.player == null or not G.player.alive:
		print("[DEATH] 玩家未部署,跳过")
		return
	var p = G.player
	p.spawn_protect = 60
	if G.hud != null:
		G.hud.visible = false
	# 选址:8 向×10m 离最近 bot/载具最远点(同 --test-squat)
	var best_p: Vector3 = p.pos
	var best_bd := -1.0
	for k in 8:
		var ang := k * TAU / 8.0
		var cand: Vector3 = p.pos + Vector3(sin(ang), 0.0, cos(ang)) * 10.0
		var nd := 1e9
		for b in G.bots:
			if b == null or not is_instance_valid(b) or not b.alive:
				continue
			nd = minf(nd, (b.pos - cand).length())
		for v in G.vehicles:
			nd = minf(nd, (v.pos - cand).length())
		if nd > best_bd:
			best_bd = nd
			best_p = cand
	p.pos = best_p
	p.vel = Vector3.ZERO
	print("[DEATH] 选址 dist_to_nearest=%.1f" % best_bd)
	# 摘 viewmodel(独立相机拍到挂原点的枪抢镜)
	var _dt_vmguns: Array = []
	for gg in p.guns:
		if gg != null and gg.get("group") != null and gg.group.get_parent() != null:
			_dt_vmguns.append([gg.group, gg.group.get_parent()])
			gg.group.get_parent().remove_child(gg.group)
	await get_tree().create_timer(0.4).timeout
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	# ---- 玩家趴姿骨位贴地数值(趴姿悬空诊断) ----
	p.crouched = false
	p.prone = true
	await get_tree().create_timer(1.3).timeout
	var gh: float = G.ground_h.call(p.pos.x, p.pos.z) if G.ground_h.is_valid() else 0.0
	var psk: Skeleton3D = p.body.get_meta("skel") if p.body.has_meta("skel") else null
	print("[DEATH] 玩家趴姿 body.y=%.3f 地=%.3f" % [p.body.global_position.y, gh])
	if psk != null:
		for bn in ["Hips", "Chest", "Head", "FootL", "FootR"]:
			var bi := psk.find_bone(bn)
			if bi >= 0:
				var gp: Vector3 = psk.get_bone_global_pose(bi).origin
				print("[DEATH] 玩家趴姿 %s world_y=%.3f (地=%.3f 抬高=%+.3f) 水平偏移=%.2f" % [
					bn, p.body.global_position.y + gp.y, gh,
					p.body.global_position.y + gp.y - gh, Vector2(gp.x, gp.z).length()])
	p.prone = false
	await get_tree().create_timer(0.6).timeout
	# ---- 4 种死法:抓 4 个最近活 bot 摆一排(6m 前方,间隔 3m) ----
	var victims: Array = []
	for b in G.bots:
		if b == null or not is_instance_valid(b) or not b.alive or b.vehicle != null:
			continue
		victims.append(b)
		if victims.size() >= 4:
			break
	if victims.size() < 4:
		print("[DEATH] 活 bot 不足 4 个(现有 %d),跳过尸体段" % victims.size())
	else:
		for i in victims.size():
			var b = victims[i]
			var off: Vector3 = right * ((i - 1.5) * 3.0) + fwd * 6.0
			b.pos = Vector3(p.pos.x + off.x, p.pos.y, p.pos.z + off.z)
			if G.ground_h.is_valid():
				b.pos.y = G.ground_h.call(b.pos.x, b.pos.z)
			b.vel = Vector3.ZERO
			b.mesh.visible = true
			b.respawn_t = 99.0   # 测试期不重生,防尸体截图到一半被拉走
		victims[1].qa_lock_crouch = true
		victims[2].qa_lock_prone = true
		await get_tree().create_timer(1.3).timeout
		victims[0].die(p)
		victims[1].die(p)
		victims[2].die(p)
		victims[3].die(p)
		var cam := Camera3D.new()
		cam.fov = 55.0
		G.main.add_child(cam)
		for phase in [["mid", 0.25], ["end", 1.6]]:
			await get_tree().create_timer(phase[1] as float).timeout
			await get_tree().process_frame
			await get_tree().process_frame
			var row_c: Vector3 = Vector3(p.pos.x, p.pos.y + 0.9, p.pos.z) + fwd * 6.0
			cam.global_position = row_c - fwd * 4.2 + right * 3.0 + Vector3(0, 0.4, 0)
			cam.look_at(row_c, Vector3.UP)
			cam.make_current()
			var img: Image = get_viewport().get_texture().get_image()
			if img != null:
				img.save_png("E:/工作目录2/models_probe/death_%s.png" % phase[0])
				print("[DEATH-SHOT] ", phase[0])
		for i in victims.size():
			var b = victims[i]
			var sk2: Skeleton3D = b.mesh.get_meta("skel") if b.mesh.has_meta("skel") else null
			var hy := -1.0
			if sk2 != null:
				var hi := sk2.find_bone("Hips")
				if hi >= 0:
					hy = b.mesh.global_position.y + sk2.get_bone_global_pose(hi).origin.y
			print("[DEATH] 尸体%d death_t=%.2f mesh_rx=%.2f flat=%s Hips骨y=%.3f" % [
				i, b.death_t, b.mesh.rotation.x, str(b._died_flat), hy])
		cam.queue_free()
	# ---- 蹲走/匍匐步态:抓 2 个活 bot,锁姿态等 AI 自己走,打印动画选片 ----
	var moved: Array = []
	for b in G.bots:
		if b == null or not is_instance_valid(b) or not b.alive or b.vehicle != null:
			continue
		moved.append(b)
		if moved.size() >= 2:
			break
	if moved.size() == 2:
		# 清场:尸体段残留的尸体(death_t 4.5s 才隐藏)会挡在步态 bot 旁边冒充主角
		if victims.size() == 4:
			for vb in victims:
				vb.mesh.visible = false
		# 传送到玩家近旁干净点:匍匐 bot 爬向交火线会中弹变尸体(上轮实测)
		for j in moved.size():
			var go: Vector3 = p.pos + fwd * (4.0 + 3.0 * j)
			moved[j].pos = Vector3(go.x, p.pos.y, go.z)
			if G.ground_h.is_valid():
				moved[j].pos.y = G.ground_h.call(go.x, go.z)
			moved[j].vel = Vector3.ZERO
		moved[0].qa_lock_crouch = true
		moved[1].qa_lock_prone = true
		await get_tree().create_timer(1.2).timeout
		var camt := Camera3D.new()
		camt.fov = 55.0
		G.main.add_child(camt)
		var b3d: Node3D = p as Node3D
		var dspace: PhysicsDirectSpaceState3D = b3d.get_world_3d().direct_space_state
		for j in moved.size():
			var b3 = moved[j]
			if not b3.alive:
				print("[DEATH] 步态bot%d 已阵亡,跳过" % j)
				continue
			var an: AnimationPlayer = b3.mesh.get_meta("anim") if b3.mesh.has_meta("anim") else null
			print("[DEATH] 步态bot%d anim=%s speed=%.2f" % [
				j, (an.current_animation if an != null else "?"), b3._anim_speed])
			var bp3: Vector3 = Vector3(b3.pos.x, b3.pos.y + 0.6, b3.pos.z)
			# LOS 选址:12 方位角挑无遮挡机位(匍匐 bot 会爬到载具边,固定机位被挡)
			for kk in 12:
				var g_ang := float(kk) * TAU / 12.0
				var gpos: Vector3 = bp3 + Vector3(sin(g_ang), 0.0, cos(g_ang)) * 3.0 + Vector3(0, 0.5, 0)
				var q3 := PhysicsRayQueryParameters3D.create(gpos, bp3)
				if dspace.intersect_ray(q3).is_empty():
					camt.global_position = gpos
					break
				if kk == 11:
					camt.global_position = bp3 + Vector3(0.8, 2.6, 0.8)
			camt.look_at(bp3, Vector3.UP)
			camt.make_current()
			await get_tree().create_timer(0.2).timeout
			await get_tree().process_frame
			await get_tree().process_frame
			var img2: Image = get_viewport().get_texture().get_image()
			if img2 != null:
				img2.save_png("E:/工作目录2/models_probe/gait_bot%d.png" % j)
				print("[DEATH-SHOT] gait_bot%d" % j)
		camt.queue_free()
		moved[0].qa_lock_crouch = false
		moved[1].qa_lock_prone = false
	else:
		print("[DEATH] 活 bot 不足 2 个,跳过步态段")
	# 还原 viewmodel
	for rec in _dt_vmguns:
		(rec[1] as Node).add_child(rec[0])
	print("[DEATH] 认证完成")
	get_tree().quit()
