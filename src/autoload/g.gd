extends Node
## 全局共享状态(对应 Three.js 版 state.js 的 G)

# ---- 引擎对象引用(由 main.gd 装配) ----
var main: Node3D = null              # 根节点
var camera: Camera3D = null          # 主相机
var vm_camera: Camera3D = null       # 视角模型相机(独立世界)
var vm_viewport: SubViewport = null
var scope = null                     # OpticScopeSystem(高倍率狙击镜 PIP 渲染器)
var drone = null                     # ReconDroneSystem(侦察兵无人侦察机操控器)


## 当前真正在渲染的视角相机:操控无人机时返回无人机相机,否则主相机。
## HUD 的世界标记(敌人标点/占领点/队友/目标)必须用它投影,
## 否则无人机视角下会拿被冻结的主相机算屏幕坐标,标点卡在屏幕上不动。
func view_camera() -> Camera3D:
	if drone != null and drone.piloting and drone.cam != null and is_instance_valid(drone.cam):
		return drone.cam
	return camera
var world_root: Node3D = null        # 动态世界容器(换图时整体销毁)
var world_group: Node3D = null       # 当前地图内容组
var sun: DirectionalLight3D = null
var sun_dir: Vector3 = Vector3(0.3, 0.8, 0.3)
var world_env: WorldEnvironment = null
var map_night := false               # 当前地图是否为夜间(world_builder.gd 构建时设置)

# ---- 系统引用 ----
var input_sys = null                 # InputSys(main.gd 内部)
var effects = null
var hud = null
var menus = null
var game = null
var player = null
var bot_manager = null
var campaign = null                  # 战役控制器(Campaign 实例,main.gd 创建)
var portal = null                    # 门户模式管理器(PortalManager,架构 Agent;BR 未就绪时由 GameMode_BR 兜底)
var br = null                        # 大逃杀模式实例(GameMode_BR;PortalManager 实例化或 main.gd 兜底)
var deployment = null                # 实时 3D 战场部署系统(BattleDeploymentManager,main.gd 创建)

# ---- 战役模式 ----
var campaign_pending_id := ""        # 待启动战役章节 id(章节选择屏设置,game.gd 战役分支读取)
var campaign_unlocked := 1           # 已解锁战役章节数(读 user://campaign_save.cfg)

# ---- 战场数据 ----
var bots: Array = []                 # 所有 AI(不含玩家)
var colliders: Array[AABB] = []      # 静态碰撞盒
var flags: Array = []                # 旗帜对象
var spawns := { "us": [], "ru": [] }
var bt_spawns = null                 # 突破模式出生线 { att: [[...]], def: [[...]] }
var bounds := 110.0                  # 地图半径(米)
var world_size := 120.0
var ground_h: Callable = Callable()  # 地形高度场 (x, z) -> y
var ground_flat := false             # [PERF] 平地(恒 0)标记:raycast_world 走封闭解免步进
var ground_grid := {}                # [PERF] 非平地 4m 高度网格(raycast_world 双线性插值加速)
var minimap_rects: Array = []
var destructibles: Array = []
var vehicle_spawns: Array = []
var map_fx := {}                     # { smokes: [...], snow: MultiMesh 等 }
var vehicles: Array = []
var aircraft: Array = []
var deployables: Array = []          # 部署物(支援兵弹药箱/反坦克地雷/重生信标)
var smoke_zones: Array = []          # 烟雾区 { pos, radius, life, emit_t }
var lock_target = null               # 防空导弹锁定目标
var squads: Array = []
var player_squad = null
var ai_tasks := {}               # squad_id → { kind, flag }(AI Director 每 4s 分配)

# ---- 流程状态 ----
var state := "menu"                  # menu | deploy | playing | dead | over
var paused := false
var time := 0.0
var tickets := { "us": 400, "ru": 400 }
var stats := { "kills": 0, "deaths": 0 }
var streak := 0
var mode := "conquest"               # conquest | breakthrough
var sel_maps := { "conquest": "random", "breakthrough": "random" }
var current_map := "city"
var bt = null                        # 突破模式状态 { sector, total }
var bt_player_side := "att"          # 突破模式玩家侧:att=进攻方(us) | def=防守方(ru)

# ---- 设置 ----
var settings := {
	"sensitivity": 1.0, "fov": 75.0, "volume": 0.8,
	"music_vol": 1.0, "sfx_vol": 1.0, "amb_vol": 1.0, "ui_vol": 1.0,
	"scale": 1.0, "aniso": 8, "shadows": 4096,
	"ssao": true, "fxaa": true, "particles": 1.0, "fog": 1.0,
	"fx_scale": 1.0,
	# ---- 3A 画质升级项(设置菜单可自由开关;ULTRA 预设默认全开) ----
	"msaa": 2,          # MSAA 档位: 0=关 1=2x 2=4x 3=8x
	"ssr": false,       # 屏幕空间反射(水面/金属反射细节)
	"ssil": false,      # 屏幕空间间接光照(环境光反弹)
	"glow": true,       # 泛光 Bloom
	"cinema": true,     # 电影级后期(自定义着色器:微对比/颗粒/暗角;色差已移除防红蓝彩边)
	"auto_quality": true,  # [8/10] 动态质量:帧时间超标自动逐级降级,稳定后恢复(不覆盖手动设置)
}
var fog_base := [60.0, 400.0]
var apply_graphics: Callable = Callable()


## 音频/UI 辅助:读取带默认值的设置项(音量等)
func audio_setting(key: String, def_v: float = 1.0) -> float:
	return float(settings.get(key, def_v))


## 统一错误日志:所有子系统通过它记录对象、状态和上下文,便于定位崩溃来源
func log_err(tag: String, msg: String, ctx: Variant = null) -> void:
	var detail := "" if ctx == null else " | ctx=" + str(ctx)
	push_error("[%s] %s%s" % [tag, msg, detail])


## 音频/UI 辅助:mm:ss 时钟格式(击杀时间戳等)
func fmt_clock(sec: float) -> String:
	var s := maxi(0, int(sec))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


func _ready() -> void:
	_setup_input_map()


## 键位映射(对应原 input.js 的键位)
func _setup_input_map() -> void:
	var defs := {
		"move_forward": [KEY_W], "move_back": [KEY_S],
		"move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE],
		"crouch": [KEY_CTRL, KEY_C], "prone": [KEY_Z],
		"reload": [KEY_R], "interact": [KEY_E],
		"fire_mode": [KEY_B],
		"grenade": [KEY_G], "gadget": [KEY_F], "spot": [KEY_Q],
		"at_grenade": [KEY_X], "at_mine": [KEY_V],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
		"scoreboard": [KEY_TAB], "pause": [KEY_ESCAPE],
		"nightvision": [KEY_T],
		"melee": [KEY_H],          # 近战小刀(长按呼出/收回)
		"inspect": [KEY_I],        # 武器检视
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	# 鼠标键
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var lmb := InputEventMouseButton.new()
		lmb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", lmb)
	if not InputMap.has_action("ads"):
		InputMap.add_action("ads")
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("ads", rmb)
	# 滚轮切枪
	for a in ["wheel_up", "wheel_down"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_UP if a == "wheel_up" else KEY_DOWN
			InputMap.action_add_event(a, ev)


# ==================== 特效辅助函数(GraphicsQuality 与 effects 联动) ====================
## 粒子预算倍率:画质档位 particles × 预设 fx_scale
func fx_particle_budget() -> float:
	return float(settings.get("particles", 1.0)) * float(settings.get("fx_scale", 1.0))


## 帧率自适应降级倍率:60fps 满配,低帧率自动砍粒子
func fx_fps_scale() -> float:
	var fps := Engine.get_frames_per_second()
	return clampf(fps / 60.0, 0.35, 1.0) if fps > 0 else 1.0


## 爆炸中心贴地高度(供特效对齐地面尘土/冲击波)
func fx_ground_height(x: float, z: float) -> float:
	return ground_h.call(x, z) if ground_h.is_valid() else 0.0


## 特效画质档位倍率(与 GraphicsQuality 预设联动):低档额外砍特效
func fx_quality_mult() -> float:
	match GraphicsQuality.current_level:
		GraphicsQuality.Level.LOW:
			return 0.55
		GraphicsQuality.Level.MEDIUM:
			return 0.8
		GraphicsQuality.Level.HIGH:
			return 1.0
		_:
			return 1.1


## 低端设备检测(Web 或最低画质档):特效系统据此额外缩减
func fx_low_end() -> bool:
	return OS.has_feature("web") or GraphicsQuality.current_level <= GraphicsQuality.Level.LOW


## 爆炸特效密度系数:大爆炸(高半径)不堆粒子只放大范围,防低配爆炸卡顿
func fx_boom_density(radius: float) -> float:
	return clampf(1.0 - (radius - 6.0) / 30.0, 0.7, 1.0)
