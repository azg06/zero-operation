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
## AABB -> col_ 节点名(仅秋津市注册; QA 定位"是谁挡的"用, 游戏逻辑不读)
var collider_tags: Dictionary = {}
## 可进建筑的门口位置({x,z}), 供 --test-akitsu-collide 做"门口能不能走进去"断言
var door_marks: Array = []
var flags: Array = []                # 旗帜对象
var spawns := { "us": [], "ru": [] }
var bt_spawns = null                 # 突破模式出生线 { att: [[...]], def: [[...]] }
var bounds := 110.0                  # 地图半径(米)
var world_size := 120.0
var ground_h: Callable = Callable()  # 地形高度场 (x, z) -> y
var ground_flat := false             # [PERF] 平地(恒 0)标记:raycast_world 走封闭解免步进
var ground_grid := {}                # [PERF] 非平地 4m 高度网格(raycast_world 双线性插值加速)
# ---- 可行走面高度场(静态 GLB 地图专用:秋津市的天桥/月台/屋顶/地下通道) ----
# 引擎无物理:垂直玩法靠 walk_ 面烘焙成高度场,floor_h 返回"脚边可站立的最高面"。
var floor_boxes: Array[AABB] = []    # 可行走面 AABB(站立高度 = position.y + size.y)
var floor_grid := {}                 # 32m 空间网格: Vector2i -> Array[int](小面索引)
var floor_big: Array = []            # 跨多格的大面(长月台/高架):全局候选
const FLOOR_CELL := 32.0
const FLOOR_STEP_UP := 0.62          # 可跨上的最大级差(楼梯单级 ≤0.5 直接走)
const FLOOR_DROP := 0.45             # 只认脚下这一步内的面:否则会把玩家"吸"到下方 3.5m 的地下通道面
                                     # (旧版无下限 → 站在地面上也会命中地下的 walk_ 面 → 掉进地下室/黑洞)
var floor_active := false            # 有可行走面时才启用(其他地图零开销)
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


## ==================== 可行走面高度场(静态 GLB 地图) ====================

## 构建可行走面索引(世界构建时调用一次;boxes 为世界坐标 AABB,顶面即可站立高度)
func build_floor_index(boxes: Array) -> void:
	floor_boxes.clear()
	floor_grid.clear()
	floor_big.clear()
	for b in boxes:
		floor_boxes.append(b)
	for i in floor_boxes.size():
		var b: AABB = floor_boxes[i]
		var cx0 := int(floor(b.position.x / FLOOR_CELL))
		var cx1 := int(floor((b.position.x + b.size.x) / FLOOR_CELL))
		var cz0 := int(floor(b.position.z / FLOOR_CELL))
		var cz1 := int(floor((b.position.z + b.size.z) / FLOOR_CELL))
		if (cx1 - cx0 + 1) * (cz1 - cz0 + 1) > 16:
			floor_big.append(i)     # 大面(高架桥/长月台):全局候选,避免写满网格
			continue
		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var k := Vector2i(cx, cz)
				if not floor_grid.has(k):
					floor_grid[k] = []
				(floor_grid[k] as Array).append(i)
	floor_active = not floor_boxes.is_empty()
	print("[FLOOR] 可行走面=", floor_boxes.size(), " 网格格=", floor_grid.size(), " 大面=", floor_big.size())


## 可行走高度:返回 ≤ ref_y+FLOOR_STEP_UP 的最高站立面;无面返回 -INF(调用方回退 ground_h)
func floor_h(ref_y: float, x: float, z: float) -> float:
	if not floor_active:
		return -INF
	var best := -INF
	var lim := ref_y + FLOOR_STEP_UP
	var low := ref_y - FLOOR_DROP
	var k := Vector2i(int(floor(x / FLOOR_CELL)), int(floor(z / FLOOR_CELL)))
	var cand: Array = floor_grid.get(k, [])
	for i in cand:
		var b: AABB = floor_boxes[i]
		if x < b.position.x or x > b.position.x + b.size.x:
			continue
		if z < b.position.z or z > b.position.z + b.size.z:
			continue
		var top := b.position.y + b.size.y
		if top <= lim and top >= low and top > best:
			best = top
	for i in floor_big:
		var b2: AABB = floor_boxes[i]
		if x < b2.position.x or x > b2.position.x + b2.size.x:
			continue
		if z < b2.position.z or z > b2.position.z + b2.size.z:
			continue
		var top2 := b2.position.y + b2.size.y
		if top2 <= lim and top2 >= low and top2 > best:
			best = top2
	return best


## 落地高度:floor_h 优先(可站上平台),无则回退地形高度场
func stand_h(ref_y: float, x: float, z: float) -> float:
	var fh := floor_h(ref_y, x, z)
	if fh > -INF:
		return fh
	return ground_h.call(x, z) if ground_h.is_valid() else 0.0


## 在指定高度附近找最近可行走面(部署/重生落点用;找不到返回 fallback)
func floor_near(ref_y: float, x: float, z: float, fallback := 0.0) -> float:
	var fh := floor_h(ref_y, x, z)
	return fh if fh > -INF else fallback


## 该点是否有可行走面(供 QA 断言)
func has_floor_at(ref_y: float, x: float, z: float) -> bool:
	return floor_h(ref_y, x, z) > -INF


# ==================== 可行驶面(秋津市 桥面/引道) ====================
# 载具旧版只读 ground_h(地形高度场)→ **任何桥都上不去**(用户: "有几座桥车上不去")。
# 引入 drive_ 面: 与 walk_ 同几何语义, 但只由桥面/坡道注册 —— 载具认 drive_ + 地形,
# 不认 walk_, 所以能上桥却不会爬屋顶/进室内。步兵仍走 walk_(两者桥上都做过)。
const VEH_STEP_UP := 0.55     # 载具可跨上的最大级差(坡道每米约 15cm)
const VEH_DROP := 2.4         # 下坡窗口(留足, 高速下坡不脱面)
var drive_boxes: Array[AABB] = []
var drive_grid := {}
var drive_big: Array = []
var drive_active := false


## 注册可行驶面(来自 GLB 里 drive_* 前缀的 Empty 节点)。语义同 set_floor_surfaces。
func set_drive_surfaces(boxes: Array) -> void:
	drive_boxes.clear()
	drive_grid.clear()
	drive_big.clear()
	for b in boxes:
		drive_boxes.append(b)
	for i in drive_boxes.size():
		var b: AABB = drive_boxes[i]
		var cx0 := int(floor(b.position.x / FLOOR_CELL))
		var cx1 := int(floor((b.position.x + b.size.x) / FLOOR_CELL))
		var cz0 := int(floor(b.position.z / FLOOR_CELL))
		var cz1 := int(floor((b.position.z + b.size.z) / FLOOR_CELL))
		if (cx1 - cx0 + 1) * (cz1 - cz0 + 1) > 16:
			drive_big.append(i)
			continue
		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var k := Vector2i(cx, cz)
				if not drive_grid.has(k):
					drive_grid[k] = []
				(drive_grid[k] as Array).append(i)
	drive_active = not drive_boxes.is_empty()
	if drive_active:
		print("[DRIVE] 可行驶面=", drive_boxes.size(), " 大面=", drive_big.size())


# ==================== 导航格网(大图 AI 寻路; 引擎无 NavigationRegion) ====================
# ★ 2026-09-10 实测: 秋津市 960m 城区上, bot 只有"直线转向 + 局部避障", 期望速度 4.6m/s
#   而净推进仅 1.5m/s(一路撞楼打转; 个别 bot 48s 内净位移 0)。后果是**两队 AI 4 分钟
#   都到不了 250~430m 外的中立旗** → 敌方全程不争点, 玩家单方面推点 → 几分钟流血取胜
#   (用户: "我方优势巨大, 不想公平")。这里建一张 6m 粗格网 + A*, 供**小队级**寻路。
const NAV_CELL := 6.0
var nav_ok := false
var nav_n := 0
var nav_org := -480.0
var nav_blk := PackedByteArray()
var nav_ex := PackedByteArray()   # 格(x,z) ↔ 右邻(x+1,z) 之间的边可通行
var nav_ez := PackedByteArray()   # 格(x,z) ↔ 下邻(x,z+1) 之间的边可通行
var _nav_dbg_n := 0


## 建格网。须在 Utils.rebuild_collider_grid() 之后(用与引擎同源的 move_collide 判定)。
func build_nav_grid() -> void:
	nav_org = -480.0
	nav_n = int(480.0 * 2.0 / NAV_CELL)
	nav_blk = PackedByteArray()
	nav_blk.resize(nav_n * nav_n)
	nav_ex = PackedByteArray()
	nav_ex.resize(nav_n * nav_n)
	nav_ez = PackedByteArray()
	nav_ez.resize(nav_n * nav_n)
	var blocked_n := 0
	for iz in nav_n:
		for ix in nav_n:
			var wx := nav_org + (ix + 0.5) * NAV_CELL
			var wz := nav_org + (iz + 0.5) * NAV_CELL
			var gy: float = stand_h(0.4, wx, wz)
			var bad := false
			if gy < -0.2:
				bad = true                                  # 海面/图外
			else:
				var p := Vector3(wx, gy, wz)
				var q: Vector3 = Utils.move_collide(p, 0.55, 1.7)
				if absf(q.x - p.x) > 0.06 or absf(q.z - p.z) > 0.06:
					bad = true                              # 胶囊被挤开 = 车/人都过不去
			nav_blk[iz * nav_n + ix] = 1 if bad else 0
			if bad:
				blocked_n += 1
	# ★ 边可通行判定(2026-09-11 根治"AI 沿直线穿墙"):
	#   6m 格中心大概率落在空地 → 96.7% 的格被标"可走", 但**相邻格之间可能隔着一堵墙**。
	#   旧版 A* 只看"目标格可走" → 认为能直穿建筑 → 路径简化成 200m+ 直线 → bot 一头撞墙、
	#   净推进只剩 ~1m/s(实测 148s 才走 70m)。这里对每条相邻格边做一次 raycast
	#   (格中心 → 邻格中心, 人眼高度): 命中即该边不通, A*/视线简化都改走"边"而非"点"。
	var cut_n := 0
	for iz in nav_n:
		for ix in nav_n:
			var i0 := iz * nav_n + ix
			if nav_blk[i0] != 0:
				continue
			var wx2 := nav_org + (ix + 0.5) * NAV_CELL
			var wz2 := nav_org + (iz + 0.5) * NAV_CELL
			var o := Vector3(wx2, stand_h(0.4, wx2, wz2) + 0.9, wz2)
			if ix + 1 < nav_n:
				if nav_blk[iz * nav_n + ix + 1] != 0:
					pass
				elif Utils.raycast_world(o, Vector3.RIGHT, NAV_CELL) == null:
					nav_ex[i0] = 1
				else:
					cut_n += 1
			if iz + 1 < nav_n:
				if nav_blk[(iz + 1) * nav_n + ix] != 0:
					pass
				elif Utils.raycast_world(o, Vector3.BACK, NAV_CELL) == null:
					nav_ez[i0] = 1
				else:
					cut_n += 1
	nav_ok = true
	print("[NAV] 格网 %dx%d cell=%.0fm 可走格=%d/%d 被墙截断的边=%d" % [
		nav_n, nav_n, NAV_CELL, nav_n * nav_n - blocked_n, nav_n * nav_n, cut_n])


## 公开:某格及其 `pad` 环域是否全部可走(载具随机投放选址:需 18m 见方开阔路面)
func nav_open_pad(cx: int, cz: int, pad: int) -> bool:
	if not nav_ok:
		return false
	for dz in range(-pad, pad + 1):
		for dx in range(-pad, pad + 1):
			var ax := cx + dx
			var az := cz + dz
			if ax < 0 or az < 0 or ax >= nav_n or az >= nav_n:
				return false
			if nav_blk[az * nav_n + ax] != 0:
				return false
	return true


func _nav_open(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= nav_n or cz >= nav_n:
		return false
	return nav_blk[cz * nav_n + cx] == 0


## 从格 (cx,cz) 迈到**相邻**格 (nx,nz) 是否可通行:
## 目标格可走 + 跨过的那条边没有墙 + 斜向不切角(两个正交邻格也要可走)
func _nav_step_ok(cx: int, cz: int, nx: int, nz: int) -> bool:
	if not _nav_open(nx, nz):
		return false
	var dx := nx - cx
	var dz := nz - cz
	if absi(dx) > 1 or absi(dz) > 1:
		return false
	if dx != 0 and nav_ex[cz * nav_n + mini(cx, nx)] == 0:
		return false
	if dz != 0 and nav_ez[mini(cz, nz) * nav_n + cx] == 0:
		return false
	if dx != 0 and dz != 0:
		if not _nav_open(cx + dx, cz) or not _nav_open(cx, cz + dz):
			return false
	return true


## 就近找可走格(起点/终点落在障碍里时用), 半径 6 格内找不到返回 (-1,-1)
func _nav_near_open(cx: int, cz: int) -> Vector2i:
	if _nav_open(cx, cz):
		return Vector2i(cx, cz)
	for r in range(1, 7):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				if _nav_open(cx + dx, cz + dz):
					return Vector2i(cx + dx, cz + dz)
	return Vector2i(-1, -1)


## A* 寻路(8 邻域, 禁切角, 二叉堆)。返回世界 XZ 路点(含终点);失败返回空。
func nav_path(fx: float, fz: float, tx: float, tz: float, max_nodes := 6000) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not nav_ok:
		return out
	var sc := _nav_near_open(int(floor((fx - nav_org) / NAV_CELL)), int(floor((fz - nav_org) / NAV_CELL)))
	var tc := _nav_near_open(int(floor((tx - nav_org) / NAV_CELL)), int(floor((tz - nav_org) / NAV_CELL)))
	if sc.x < 0 or tc.x < 0:
		return out
	var total := nav_n * nav_n
	var gs := PackedFloat32Array(); gs.resize(total)
	var fs := PackedFloat32Array(); fs.resize(total)
	var par := PackedInt32Array(); par.resize(total)
	var stt := PackedByteArray(); stt.resize(total)
	for i in total:
		gs[i] = 1e18
		par[i] = -1
	var si := sc.y * nav_n + sc.x
	var ti := tc.y * nav_n + tc.x
	gs[si] = 0.0
	fs[si] = Vector2(sc - tc).length()
	# 二叉堆(存 cell index, 按 fs 比较)
	var heap := PackedInt32Array([si])
	stt[si] = 1
	var found := false
	var expanded := 0
	while heap.size() > 0:
		var cur: int = heap[0]
		var last := heap.size() - 1
		heap[0] = heap[last]
		heap.resize(last)
		var i2 := 0
		while true:                                        # 下沉
			var l := i2 * 2 + 1
			var r2 := l + 1
			var m := i2
			if l < heap.size() and fs[heap[l]] < fs[heap[m]]:
				m = l
			if r2 < heap.size() and fs[heap[r2]] < fs[heap[m]]:
				m = r2
			if m == i2:
				break
			var t2 := heap[i2]; heap[i2] = heap[m]; heap[m] = t2
			i2 = m
		if cur == ti:
			found = true
			break
		stt[cur] = 2
		expanded += 1
		if expanded > max_nodes:
			break
		var cx := cur % nav_n
		var cz := cur / nav_n
		for d in 8:
			var dx: int = [1, -1, 0, 0, 1, 1, -1, -1][d]
			var dz: int = [0, 0, 1, -1, 1, -1, 1, -1][d]
			var nx := cx + dx
			var nz := cz + dz
			if not _nav_step_ok(cx, cz, nx, nz):
				continue                                   # 目标格可走 + 跨边无墙 + 斜向禁切角
			var ni := nz * nav_n + nx
			if stt[ni] == 2:
				continue
			var step := 1.41421 if (dx != 0 and dz != 0) else 1.0
			var ng := gs[cur] + step
			if ng < gs[ni]:
				gs[ni] = ng
				par[ni] = cur
				# ★ 权重启发式(h×1.35): 允许次优解换取展开数大幅下降 —— 960m 图上
				#   纯最优 A* 实测 3000 节点就撞上限搜不到路。
				fs[ni] = ng + Vector2(nx - tc.x, nz - tc.y).length() * 1.35
				if stt[ni] == 1:
					# ★ 已在堆中且 g 变小 → 必须**重新上浮**(旧版漏这步: 堆序失效,
					#   节点被以错误的 f 弹出 → 展开数从几百暴涨到撞上限)
					var up2 := heap.find(ni)
					while up2 > 0:
						var p3 := (up2 - 1) / 2
						if fs[heap[p3]] <= fs[heap[up2]]:
							break
						var t4 := heap[p3]; heap[p3] = heap[up2]; heap[up2] = t4
						up2 = p3
				else:
					stt[ni] = 1
					heap.append(ni)
					var up := heap.size() - 1               # 上浮
					while up > 0:
						var p2 := (up - 1) / 2
						if fs[heap[p2]] <= fs[heap[up]]:
							break
						var t3 := heap[p2]; heap[p2] = heap[up]; heap[up] = t3
						up = p2
	if not found:
		if _nav_dbg_n < 6:
			_nav_dbg_n += 1
			print("[NAV] 寻路失败 (%d,%d)->(%d,%d) 展开=%d 堆余=%d 起走=%s 终走=%s" % [
				sc.x, sc.y, tc.x, tc.y, expanded, heap.size(),
				_nav_open(sc.x, sc.y), _nav_open(tc.x, tc.y)])
		return out
	var cells := PackedInt32Array()
	var c := ti
	while c != -1:
		cells.append(c)
		if c == si:
			break
		c = par[c]
	cells.reverse()
	# 视线简化: 能直连就跳过中间点
	# ★2026-09-11: 单段跨度必须封顶(3 格 ≤18m)。旧版允许"能直连就一路并到终点",
	#   在 6m 格网上留下 100~200m 的超长段 —— bot 从**自身位置**(不是格中心)朝该航点直线走,
	#   与格中心路径有偏差 → 擦墙角被反复推回(实测撞墙 112 帧/12s, 净位移仅 1.3m/s)。
	var keep := [cells[0]]
	var ai := 0
	while ai < cells.size() - 1:
		var bi2 := mini(cells.size() - 1, ai + 3)
		while bi2 > ai + 1:
			if _nav_los(cells[ai], cells[bi2]):
				break
			bi2 -= 1
		keep.append(cells[bi2])
		ai = bi2
	for k in keep:
		var kx: int = k % nav_n
		var kz: int = k / nav_n
		out.append(Vector2(nav_org + (kx + 0.5) * NAV_CELL, nav_org + (kz + 0.5) * NAV_CELL))
	return out


## 格 a→b 能否直连。★2026-09-11: 必须逐**边**判定(旧版只查采样点是否可走 →
## 墙体落在两格之间就被漏掉, 于是 200m 穿越城区的"直线"被判为可直连, AI 沿它撞楼)。
func _nav_los(a: int, b: int) -> bool:
	var ax := a % nav_n
	var az := a / nav_n
	var bx := b % nav_n
	var bz := b / nav_n
	var n := maxi(absi(bx - ax), absi(bz - az))
	if n == 0:
		return true
	if n == 1:
		return _nav_step_ok(ax, az, bx, bz)
	var px := ax
	var pz := az
	for i in range(1, n + 1):
		var t := float(i) / n
		var cx := int(roundf(ax + (bx - ax) * t))
		var cz := int(roundf(az + (bz - az) * t))
		if cx == px and cz == pz:
			continue
		# 采样点可能跨 >1 格(斜向), 拆成逐格步进
		while px != cx or pz != cz:
			var sx := signi(cx - px)
			var sz := signi(cz - pz)
			if not _nav_step_ok(px, pz, px + sx, pz + sz):
				return false
			px += sx
			pz += sz
	return true


## 载具贴地高度: drive_ 面优先(桥面/引道), 否则回退地形高度场。
## ref_y = 载具当前高度;窗口 [ref_y-VEH_DROP, ref_y+VEH_STEP_UP] 只认脚下这一段,
## 不会把车从桥下"吸"上桥面, 也不会把桥上的车拉到地面。
func veh_h(x: float, z: float, ref_y: float) -> float:
	var g: float = ground_h.call(x, z) if ground_h.is_valid() else 0.0
	if not drive_active:
		return g
	var best := -INF
	var lim := ref_y + VEH_STEP_UP
	var low := ref_y - VEH_DROP
	var k := Vector2i(int(floor(x / FLOOR_CELL)), int(floor(z / FLOOR_CELL)))
	for i in drive_grid.get(k, []):
		var b: AABB = drive_boxes[i]
		if x < b.position.x or x > b.position.x + b.size.x:
			continue
		if z < b.position.z or z > b.position.z + b.size.z:
			continue
		var top := b.position.y + b.size.y
		if top <= lim and top >= low and top > best:
			best = top
	for i in drive_big:
		var b2: AABB = drive_boxes[i]
		if x < b2.position.x or x > b2.position.x + b2.size.x:
			continue
		if z < b2.position.z or z > b2.position.z + b2.size.z:
			continue
		var top2 := b2.position.y + b2.size.y
		if top2 <= lim and top2 >= low and top2 > best:
			best = top2
	return best if best > g else g
