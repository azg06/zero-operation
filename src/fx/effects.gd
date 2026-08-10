class_name Effects extends Node3D
## 特效系统(对应 effects.js):粒子池 / 曳光弹 / 枪口焰 / 弹壳 / 手雷 / 火箭弹 / 屏幕震动

static var MAXP := 0                    # 每类粒子池大小(Web 端自动缩减)


func _init_maxp() -> void:
	if MAXP == 0:
		MAXP = 500 if OS.has_feature("web") else 1500

var quality := 1.0  # 粒子质量(画质设置)

# ---- 动态画质:帧率自适应 + 画质档位联动的粒子预算 ----
var fx_scale := 1.0          # 总粒子预算倍率(quality * 帧率降级)
var _fps_scale := 1.0        # 帧率自适应倍率(低帧率自动降粒子数)
var _fps_smoothed := 60.0    # 平滑 FPS 采样
var _eff_t := 0.0
var _fxaa_wired := false          # --fxaa-debug 开关只接线一次

# ---- 全屏特效层(爆闪/死亡淡出,CanvasLayer 自包含,不动 HUD) ----
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_alpha := 0.0
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _fade_alpha := 0.0
var _was_dead := false

# ---- 夜视仪层(绿色滤镜 + 暗角,层 90:fxaa 4 之上 / 爆闪 100 之下) ----
var _nvg_layer: CanvasLayer
var _nvg_rect: ColorRect
var _nvg_vg: TextureRect

# ---- 粒子池(MultiMesh 公告牌) ----
var _sparks_mm: MultiMesh
var _smoke_mm: MultiMesh
var _fire_mm: MultiMesh
var _sparks_pos := PackedVector3Array()
var _sparks_vel := PackedVector3Array()
var _sparks_life := PackedFloat32Array()
var _sparks_max_life := PackedFloat32Array()
var _sparks_col := PackedColorArray()
var _sparks_grav := PackedFloat32Array()
var _sparks_size := PackedFloat32Array()
var _sparks_head := 0
var _sparks_scan_max := 0  # [PERF] P1-4:扫描高水位(最高存活槽+1;顶部死亡即收缩)
var _smoke_pos := PackedVector3Array()
var _smoke_vel := PackedVector3Array()
var _smoke_life := PackedFloat32Array()
var _smoke_max_life := PackedFloat32Array()
var _smoke_col := PackedColorArray()
var _smoke_grav := PackedFloat32Array()
var _smoke_size := PackedFloat32Array()
var _smoke_head := 0
var _smoke_scan_max := 0
var _sparks_alive := 0                # 活动粒子计数(空池跳过更新循环)
var _smoke_alive := 0
# ---- 火焰粒子池(残骸燃烧/坠毁火场) ----
var _fire_pos := PackedVector3Array()
var _fire_vel := PackedVector3Array()
var _fire_life := PackedFloat32Array()
var _fire_max_life := PackedFloat32Array()
var _fire_col := PackedColorArray()
var _fire_size := PackedFloat32Array()
var _fire_power := PackedFloat32Array()  # 上升/扩散强度倍率
var _fire_head := 0
var _fire_scan_max := 0
var _fire_alive := 0

# ---- 曳光弹池 ----
var _tracers: Array = []
# ---- 枪口焰池 ----
var _flashes: Array = []
var _flash_tex: Texture2D
# ---- 光源 ----
var _muzzle_light: OmniLight3D
var _expl_lights: Array = []        # 爆炸光源池(8 盏,并发爆炸按距离分配互不覆盖)
# ---- 地形高度网格缓存(4m 粒度):粒子着地判定避免每帧噪声求值(G.ground_h 换代时失效) ----
var _gh_grid: Dictionary = {}
var _gh_owner: Callable = Callable()
# ---- 弹壳/弹匣池 ----
var _casings: Array = []
var _mags: Array = []
# ---- 投射物 ----
var _grenades: Array = []
var _rockets: Array = []
var _grenade_mesh: SphereMesh
var _rocket_mesh: CylinderMesh
var _grenade_mat: StandardMaterial3D
var _rocket_mat: StandardMaterial3D
# ---- 掉落武器池(士兵阵亡掉枪) ----
var _drops: Array = []
# ---- 冲击波环 ----
var _rings: Array = []
# ---- 屏幕震动 ----
var shake_amt := 0.0
var shake_pitch := 0.0
var shake_yaw := 0.0
var _shake_bias := 0.0             # 方向性震屏(爆炸横向踢,朝爆点侧摇)

# ---- 延迟时间轴事件(爆炸分阶段:爆闪→扩张→烟柱→尘土) ----
var _delayed: Array = []

# ---- 受伤红边 vignette(受击脉冲 + 低血量常驻) ----
var _dmg_layer: CanvasLayer
var _dmg_rect: TextureRect
var _dmg_tex: Texture2D
var _dmg_alpha := 0.0
var _last_health := -1.0

# ---- 阵亡检测(玩家/士兵倒地尘土) ----
var _player_was_alive := true
var _bot_alive: Dictionary = {}


func _ready() -> void:
	_init_maxp()
	_build_screen_fx()
	_build_particle_pools()
	_build_tracers()
	_build_flashes()
	_build_lights()
	_build_casings()
	_build_rings()
	_grenade_mesh = SphereMesh.new()
	_grenade_mesh.radius = 0.07
	_grenade_mesh.height = 0.14
	_grenade_mesh.radial_segments = 8
	_grenade_mesh.rings = 6
	_grenade_mat = StandardMaterial3D.new()
	_grenade_mat.albedo_color = Color.html("#2a3a2a")
	_grenade_mat.roughness = 0.6
	_grenade_mat.metallic = 0.4
	_rocket_mesh = CylinderMesh.new()
	_rocket_mesh.top_radius = 0.0
	_rocket_mesh.bottom_radius = 0.07
	_rocket_mesh.height = 0.35
	_rocket_mesh.radial_segments = 8
	_rocket_mat = StandardMaterial3D.new()
	_rocket_mat.albedo_color = Color.html("#8a7a5a")
	_rocket_mat.roughness = 0.5
	_rocket_mat.metallic = 0.5
	# 掉落武器池(12 槽循环复用)
	for i in 12:
		var holder := Node3D.new()
		holder.visible = false
		add_child(holder)
		_drops.append({ "holder": holder, "vel": Vector3.ZERO, "yaw_vel": 0.0, "life": 0.0 })


static func _radial_tex(size: int, stops: Array) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := size / 2.0
	for y in size:
		for x in size:
			var dx := x - c + 0.5
			var dy := y - c + 0.5
			var d: float = sqrt(dx * dx + dy * dy) / c
			if d <= 1.0:
				var col: Color = stops[stops.size() - 1][1]
				for i in stops.size() - 1:
					var t0: float = stops[i][0]
					var t1: float = stops[i + 1][0]
					if d >= t0 and d <= t1:
						var f := 0.0 if t1 - t0 < 1e-6 else (d - t0) / (t1 - t0)
						col = (stops[i][1] as Color).lerp(stops[i + 1][1], f)
						break
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## 公告牌粒子池;additive=加法混合(火花/火焰),quad_size=公告牌基础尺寸,
## stops=径向贴图色标(空则白色),emission=发光材质(火焰 glow,池级共享缓存,粒子不 new 材质)
func _make_pool(additive: bool, quad_size: float, opacity: float,
		stops: Array = [], emission := false, emission_color := Color.WHITE, emission_energy := 1.0) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	var dot: ImageTexture
	if stops.is_empty():
		dot = _radial_tex(32, [
			[0.0, Color(1, 1, 1, 1)],
			[0.5, Color(1, 1, 1, 0.6)],
			[1.0, Color(1, 1, 1, 0)],
		])
	else:
		dot = _radial_tex(32, stops)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_texture = dot
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if emission:
		mat.emission_enabled = true
		mat.emission = emission_color
		mat.emission_energy_multiplier = emission_energy
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAXP
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))
	for i in MAXP:
		mm.set_instance_transform(i, zero)
		mm.set_instance_color(i, Color(1, 1, 1, opacity))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _build_particle_pools() -> void:
	_sparks_mm = _make_pool(true, 0.09, 1.0)
	_smoke_mm = _make_pool(false, 0.45, 0.5)
	# 火焰池:加法混合 + 橙黄 emission 发光(燃烧残骸/坠毁火场)
	_fire_mm = _make_pool(true, 0.4, 1.0, [
		[0.0, Color(1.0, 0.9, 0.55, 1.0)],
		[0.5, Color(1.0, 0.5, 0.15, 0.9)],
		[1.0, Color(1.0, 0.3, 0.04, 0.0)],
	], true, Color.html("#ff8a2a"), 2.5)
	_sparks_pos.resize(MAXP); _sparks_vel.resize(MAXP)
	_sparks_life.resize(MAXP); _sparks_max_life.resize(MAXP)
	_sparks_col.resize(MAXP); _sparks_grav.resize(MAXP)
	_sparks_size.resize(MAXP)
	_smoke_pos.resize(MAXP); _smoke_vel.resize(MAXP)
	_smoke_life.resize(MAXP); _smoke_max_life.resize(MAXP)
	_smoke_col.resize(MAXP); _smoke_grav.resize(MAXP)
	_smoke_size.resize(MAXP)
	_sparks_size.fill(1.0)
	_smoke_size.fill(1.0)
	_fire_pos.resize(MAXP); _fire_vel.resize(MAXP)
	_fire_life.resize(MAXP); _fire_max_life.resize(MAXP)
	_fire_col.resize(MAXP); _fire_size.resize(MAXP)
	_fire_power.resize(MAXP)
	_fire_size.fill(1.0)
	_fire_power.fill(1.0)


## 全屏特效层:爆闪(暖白) + 死亡淡出(黑),CanvasLayer 自包含不依赖 HUD
func _build_screen_fx() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 100
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 0.82, 0.6)
	_flash_rect.modulate = Color(1, 1, 1, 0)
	_flash_layer.add_child(_flash_rect)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 150
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0.015, 0.012, 0.02)
	_fade_rect.modulate = Color(1, 1, 1, 0)
	_fade_layer.add_child(_fade_rect)
	# 受伤红边:径向渐变贴图,层位于爆闪(100)与死亡淡出(150)之间
	_dmg_layer = CanvasLayer.new()
	_dmg_layer.layer = 120
	add_child(_dmg_layer)
	_dmg_tex = _make_vignette_tex()
	_dmg_rect = TextureRect.new()
	_dmg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_rect.texture = _dmg_tex
	_dmg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_dmg_rect.modulate = Color(1, 1, 1, 0)
	_dmg_layer.add_child(_dmg_rect)
	# 夜视仪:层 90(fxaa 4 之上 / 爆闪 100 之下),绿色滤镜 + 暗角,默认隐藏
	_nvg_layer = CanvasLayer.new()
	_nvg_layer.layer = 90
	add_child(_nvg_layer)
	_nvg_rect = ColorRect.new()
	_nvg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nvg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nvg_rect.color = Color(0.12, 0.85, 0.35, 0.22)
	_nvg_rect.modulate = Color(1, 1, 1, 0)
	_nvg_layer.add_child(_nvg_rect)
	_nvg_vg = TextureRect.new()
	_nvg_vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nvg_vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nvg_vg.texture = _make_nvg_vignette_tex()
	_nvg_vg.stretch_mode = TextureRect.STRETCH_SCALE
	_nvg_vg.modulate = Color(1, 1, 1, 0)
	_nvg_layer.add_child(_nvg_vg)


## 径向渐变贴图生成(受伤红边 / HUD 白色蒙版共用,像素级行为一致)
## linear=true 线性渐变(hud 蒙版),否则 smoothstep(受伤红边);alpha 乘 alpha_scale
static func make_vignette_tex(color: Color, edge0: float, edge1: float, linear := false, alpha_scale := 1.0) -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := size / 2.0
	for y in size:
		for x in size:
			var dx := (x - c + 0.5) / c
			var dy := (y - c + 0.5) / c
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf((d - edge0) / (edge1 - edge0), 0.0, 1.0) if linear else smoothstep(edge0, edge1, d)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a * alpha_scale))
	return ImageTexture.create_from_image(img)


## 受伤红边径向渐变贴图:中心透明,边缘深红(0.42~1.1 平滑过渡)
func _make_vignette_tex() -> ImageTexture:
	return make_vignette_tex(Color(0.52, 0.008, 0.016), 0.42, 1.1, false, 0.92)


## 夜视仪暗角径向渐变贴图:中心透明,四周墨绿压暗(镜片暗角感)
func _make_nvg_vignette_tex() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := size / 2.0
	for y in size:
		for x in size:
			var dx := (x - c + 0.5) / c
			var dy := (y - c + 0.5) / c
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = smoothstep(0.55, 1.1, d)
			img.set_pixel(x, y, Color(0.01, 0.09, 0.03, a * 0.85))
	return ImageTexture.create_from_image(img)


func _build_tracers() -> void:
	var geo := BoxMesh.new()
	geo.size = Vector3(0.03, 0.03, 1.0)
	for i in 40:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0.85, 0.63, 0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var m := MeshInstance3D.new()
		m.mesh = geo
		m.material_override = mat
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_tracers.append({ "mesh": m, "life": 0.0 })


func _build_flashes() -> void:
	_flash_tex = _radial_tex(64, [
		[0.0, Color(1, 1, 0.9, 1)],
		[0.3, Color(1, 0.78, 0.39, 0.9)],
		[1.0, Color(1, 0.47, 0.08, 0)],
	])
	for i in 10:
		var s := Sprite3D.new()
		s.texture = _flash_tex
		s.modulate = Color(1, 1, 1, 0)
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.visible = false
		add_child(s)
		_flashes.append({ "sprite": s, "life": 0.0, "max_life": 0.045, "bright": 1.0, "decay_pow": 1.5 })


func _build_lights() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color.html("#ffc070")
	_muzzle_light.light_energy = 0
	_muzzle_light.omni_range = 14
	_muzzle_light.shadow_enabled = false
	add_child(_muzzle_light)
	# 爆炸光源池化:8 盏 OmniLight,多爆并发时按距离最近优先分配,避免互相覆盖
	for i in 8:
		var lg := OmniLight3D.new()
		lg.light_color = Color.html("#ff9040")
		lg.light_energy = 0
		lg.omni_range = 30
		lg.shadow_enabled = false
		add_child(lg)
		_expl_lights.append(lg)


## 爆炸光源分配:空闲(能量耗尽)优先复用;全部占用时取离爆心最近的一盏
func _expl_light_for(pos: Vector3) -> OmniLight3D:
	var best: OmniLight3D = null
	var best_d := INF
	for lg in _expl_lights:
		if (lg as OmniLight3D).light_energy <= 0.5:
			return lg
		var d: float = (lg as OmniLight3D).global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = lg
	return best


## 地形高度(4m 网格缓存):同格粒子共享一次噪声求值;换图(ground_h 被重建)自动失效
func _ground_h(x: float, z: float) -> float:
	if G.ground_h != _gh_owner:
		_gh_grid.clear()
		_gh_owner = G.ground_h
	var key := Vector2i(int(floorf(x * 0.25)), int(floorf(z * 0.25)))
	var h: Variant = _gh_grid.get(key)
	if h == null:
		h = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		_gh_grid[key] = h
	return h


func _build_casings() -> void:
	for i in 30:
		var holder := Node3D.new()
		var m := MeshInstance3D.new()
		m.visible = false
		holder.add_child(m)
		add_child(holder)
		_casings.append({ "holder": holder, "mesh": m, "vel": Vector3.ZERO, "rot": Vector3.ZERO, "life": 0.0, "bullet_type": -1 })
	var mg_geo := BoxMesh.new()
	mg_geo.size = Vector3(0.035, 0.11, 0.055)
	var mg_mat := StandardMaterial3D.new()
	mg_mat.albedo_color = Color.html("#22252a")
	mg_mat.roughness = 0.7
	mg_mat.metallic = 0.4
	for i in 8:
		var m := MeshInstance3D.new()
		m.mesh = mg_geo
		m.material_override = mg_mat
		m.visible = false
		add_child(m)
		_mags.append({ "mesh": m, "vel": Vector3.ZERO, "rot": Vector3.ZERO, "life": 0.0 })


static func _casing_mesh(bullet_type: int) -> Mesh:
	match bullet_type:
		1:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.008; cm.bottom_radius = 0.01; cm.height = 0.06; cm.radial_segments = 6
			return cm
		2:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.012; cm.bottom_radius = 0.014; cm.height = 0.06; cm.radial_segments = 6
			return cm
		_:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.006; cm.bottom_radius = 0.008; cm.height = 0.04; cm.radial_segments = 6
			return cm


static func _casing_mat(_bullet_type: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html("#d4b060")
	m.roughness = 0.4
	m.metallic = 0.7
	return m


func _build_rings() -> void:
	var ring_mesh := Flag.make_ring_mesh(0.9, 1.0, 32)
	for i in 6:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0.75, 0.5, 0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var m := MeshInstance3D.new()
		m.mesh = ring_mesh
		m.material_override = mat
		m.visible = false
		add_child(m)
		_rings.append({ "mesh": m, "life": 0.0, "max_r": 10.0, "dur": 0.45 })


func shake(amt: float) -> void:
	shake_amt = minf(shake_amt + amt, 1.6)


# ==================== 粒子生成接口 ====================
## 粒子预算倍率:画质档位(particles) × 帧率自适应降级
func _budget() -> float:
	return fx_scale * _fps_scale


## 画质门控:返回 false 时调用方应跳过本次粒子生成(按预算概率丢弃)
## 仅做帧率自适应降级;fx_scale 已在 _budget() 统一折算,避免双重折扣
func _gate() -> bool:
	if _fps_scale < 1.0 and randf() > _fps_scale:
		return false
	return true


func spark_spawn(x: float, y: float, z: float, vx: float, vy: float, vz: float,
		life: float, r: float, g: float, b: float, grav := 1.0, size := 1.0) -> void:
	if not _gate():
		return
	var i: int = _sparks_head
	_sparks_head = (_sparks_head + 1) % MAXP
	if i >= _sparks_scan_max:
		_sparks_scan_max = i + 1
	if _sparks_life[i] <= 0:
		_sparks_alive += 1
	_sparks_pos[i] = Vector3(x, y, z)
	_sparks_vel[i] = Vector3(vx, vy, vz)
	_sparks_life[i] = life
	_sparks_max_life[i] = life
	_sparks_col[i] = Color(r, g, b)
	_sparks_grav[i] = grav
	_sparks_size[i] = size


func smoke_spawn(x: float, y: float, z: float, vx: float, vy: float, vz: float,
		life: float, r: float, g: float, b: float, grav := 1.0, size := 1.0) -> void:
	if not _gate():
		return
	var i: int = _smoke_head
	_smoke_head = (_smoke_head + 1) % MAXP
	if i >= _smoke_scan_max:
		_smoke_scan_max = i + 1
	if _smoke_life[i] <= 0:
		_smoke_alive += 1
	_smoke_pos[i] = Vector3(x, y, z)
	_smoke_vel[i] = Vector3(vx, vy, vz)
	_smoke_life[i] = life
	_smoke_max_life[i] = life
	_smoke_col[i] = Color(r, g, b)
	_smoke_grav[i] = grav
	_smoke_size[i] = size


## 火焰粒子:橙色发光火苗(加法混合 + emission glow),上升 + 水平扩散,
## 寿命内缩放衰减(0.5→0.1) + 快速淡出;power=上升/扩散/亮度强度倍率
## 材质为池级共享缓存(_make_pool 构建一次),粒子零分配
func fire_spawn(x: float, y: float, z: float, vx: float, vy: float, vz: float,
		life := 0.4, size := 0.5, power := 1.0) -> void:
	if not _gate():
		return
	var i: int = _fire_head
	_fire_head = (_fire_head + 1) % MAXP
	if i >= _fire_scan_max:
		_fire_scan_max = i + 1
	if _fire_life[i] <= 0:
		_fire_alive += 1
	_fire_pos[i] = Vector3(x, y, z)
	_fire_vel[i] = Vector3(vx, vy, vz)
	_fire_life[i] = life
	_fire_max_life[i] = life
	var pw := clampf(power, 0.2, 2.0)
	_fire_col[i] = Color(1.0, 0.68 + 0.2 * pw, 0.3, 1.0)
	_fire_size[i] = size
	_fire_power[i] = pw


# ==================== 特效接口 ====================
## 曳光弹:从 from 到 to(距离衰减:越远越淡、越细,近处核心炽亮)
## life=尾迹存续时间;thickness=弹径倍率(重机枪更粗)
func tracer(from: Vector3, to: Vector3, color: Color, life := 0.07, thickness := 1.0) -> void:
	var t = null
	for t_tr in _tracers:
		if t_tr["life"] <= 0:
			t = t_tr
			break
	if t == null:
		t = _tracers[0]
	var dist := from.distance_to(to)
	var m: MeshInstance3D = t["mesh"]
	var fade := clampf(1.0 - dist / 260.0, 0.18, 1.0)
	(m.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.9 * fade)
	m.position = (from + to) * 0.5
	if dist > 1e-6:
		m.look_at_from_position(m.position, to, Vector3.UP)
	var thick := clampf(1.0 - dist / 320.0, 0.55, 1.0) * clampf(thickness, 0.6, 1.5)
	m.scale = Vector3(thick, thick, maxf(dist, 0.01))
	m.visible = true
	t["life"] = life
	t["max_life"] = life
	t["dist"] = dist


## 枪口焰:big=大口径;brightness=武器独立闪光亮度;duration=持续时间;
## decay_pow=衰减曲线指数(越大越锐:狙击枪刺眼短促,越小越柔:机枪长拖尾);
## smoke_k=枪口烟密度倍率(重火力更浓)
func muzzle(pos: Vector3, dir: Vector3, big := false, brightness := 1.0, duration := 0.045, decay_pow := 1.5, smoke_k := 1.0) -> void:
	var f = null
	for fl in _flashes:
		if fl["life"] <= 0:
			f = fl
			break
	if f == null:
		f = _flashes[0]
	var s: Sprite3D = f["sprite"]
	s.position = pos + dir * 0.12
	var sc := Utils.rand(0.4, 0.55) if big else Utils.rand(0.16, 0.26)
	sc *= clampf(brightness, 0.5, 1.6)
	s.pixel_size = sc / 32.0
	s.rotation.z = Utils.rand(TAU)
	s.modulate = Color(brightness, brightness, brightness, 1)
	s.visible = true
	f["life"] = duration
	f["max_life"] = duration
	f["bright"] = brightness
	f["decay_pow"] = clampf(decay_pow, 0.8, 3.0)
	# 副闪光:同帧叠加一层柔光环(宽而暗),BF 式双重焰舌
	var f2 = null
	for fl in _flashes:
		if fl["life"] <= 0 and fl != f:
			f2 = fl
			break
	if f2 != null:
		var s2: Sprite3D = f2["sprite"]
		s2.position = pos + dir * 0.17
		s2.pixel_size = (sc * 1.85) / 32.0
		s2.rotation.z = Utils.rand(TAU)
		s2.modulate = Color(0.62, 0.55, 0.42, 1) * clampf(brightness, 0.5, 1.5)
		s2.visible = true
		f2["life"] = duration * 0.6
		f2["max_life"] = maxf(duration * 0.6, 0.01)
		f2["bright"] = 0.55 * clampf(brightness, 0.5, 1.5)
		f2["decay_pow"] = 1.2
	# 光源:每把武器独立亮度 + 颜色随亮度变化(炽热偏橙,低亮偏黄)
	var light_energy: float = (14.0 if big else 6.0) * clampf(brightness, 0.6, 1.8)
	_muzzle_light.position = pos
	_muzzle_light.light_color = Color(1.0, 0.78 + 0.1 * brightness, 0.42, 1)
	_muzzle_light.light_energy = light_energy
	# 喷射火花:沿枪口方向弹射(短命,重火力更多)
	var n_sparks: int = int((10 if big else 4) * clampf(brightness, 0.6, 1.6))
	for i in n_sparks:
		if not _gate():
			continue
		spark_spawn(pos.x, pos.y, pos.z,
				dir.x * Utils.rand(2, 7) + Utils.rand(-1.5, 1.5), dir.y * Utils.rand(2, 7) + Utils.rand(-1, 2),
				dir.z * Utils.rand(2, 7) + Utils.rand(-1.5, 1.5),
				Utils.rand(0.05, 0.14), 1, 0.8, 0.35, 0.4)
	# 枪口烟(密度按 smoke_k,重火力/自动武器更明显,受画质门控)
	var n_smoke: int = int((1.0 if big else 0.6) * clampf(smoke_k, 0.4, 1.6))
	for i in n_smoke:
		if not _gate():
			continue
		smoke_spawn(pos.x, pos.y, pos.z,
			dir.x * Utils.rand(0.2, 0.8) + Utils.rand(-0.15, 0.15),
			Utils.rand(0.35, 0.9),
			dir.z * Utils.rand(0.2, 0.8) + Utils.rand(-0.15, 0.15),
			Utils.rand(0.25, 0.45), 0.42, 0.41, 0.4, -0.25, Utils.rand(0.6, 1.1))


## 弹着点:按材质区分火花/尘土/水花;material 为空时自动按地形高度推断;
## from 传入入射点时可判定浅角度跳弹
func impact(pos: Vector3, normal: Vector3, material := "", from := Vector3.ZERO) -> void:
	if material == "":
		material = _material_at(pos, normal)
	# 浅角度命中 → 跳弹:沿弹射方向拉一道短曳光 + 偏折火花
	var ricocheted := false
	if from != Vector3.ZERO:
		var dir_in := (from - pos).normalized()
		if dir_in.dot(normal) > -0.35 and dir_in.dot(normal) < -0.02:
			var bounce := dir_in.bounce(normal).normalized()
			tracer(pos, pos + bounce * Utils.rand(1.2, 2.4), Color(1, 0.9, 0.7), 0.06)
			ricocheted = true
			_impact_flash(pos, 0.8)
			AudioSys.ricochet(pos)
	match material:
		"water":
			_impact_flash(pos, 0.7)
			for i in 8:
				if not _gate():
					continue
				spark_spawn(pos.x, pos.y, pos.z,
					Utils.rand(-2, 2), Utils.rand(0.5, 3.5), Utils.rand(-2, 2),
					Utils.rand(0.15, 0.3), 0.8, 0.9, 1.0, 0.6)
			for i in 6:
				smoke_spawn(pos.x, pos.y, pos.z,
					Utils.rand(-0.8, 0.8), Utils.rand(0.4, 1.4), Utils.rand(-0.8, 0.8),
					Utils.rand(0.25, 0.5), 0.85, 0.88, 0.92, 0.1, 0.8)
		"metal":
			_impact_flash(pos, 1.1)
			for i in 7:
				if not _gate():
					continue
				spark_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(2, 6) + Utils.rand(-1.5, 1.5), normal.y * Utils.rand(2, 6) + Utils.rand(0, 2),
					normal.z * Utils.rand(2, 6) + Utils.rand(-1.5, 1.5),
					Utils.rand(0.08, 0.2), 1.0, 0.85, 0.4, 0.9)
			for i in 3:
				smoke_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(0.4, 1.0), Utils.rand(0.3, 1.0), normal.z * Utils.rand(0.4, 1.0),
					Utils.rand(0.2, 0.4), 0.3, 0.3, 0.32, 0.1, 0.7)
		"dirt":
			_impact_flash(pos, 0.8)
			for i in 6:
				if not _gate():
					continue
				spark_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(1, 4) + Utils.rand(-2, 2), normal.y * Utils.rand(1, 4) + Utils.rand(0, 3),
					normal.z * Utils.rand(1, 4) + Utils.rand(-2, 2),
					Utils.rand(0.1, 0.3), 0.75, 0.62, 0.35, 1.2)
			for i in 7:
				if not _gate():
					continue
				smoke_spawn(pos.x, pos.y, pos.z,
					Utils.rand(-0.6, 0.6), Utils.rand(0.5, 1.6), Utils.rand(-0.6, 0.6),
					Utils.rand(0.3, 0.7), 0.5, 0.44, 0.34, 0.5, Utils.rand(0.8, 1.4))
			for i in 4:
				smoke_spawn(pos.x, pos.y, pos.z,
					Utils.rand(-0.3, 0.3), Utils.rand(0.2, 0.9), Utils.rand(-0.3, 0.3),
					Utils.rand(0.25, 0.5), 0.42, 0.37, 0.28, 0.9, 1.2)
		"wood":
			# 木箱/栅栏:浅色木屑 + 飘散粉尘,少火花
			_impact_flash(pos, 0.6)
			for i in 6:
				if not _gate():
					continue
				spark_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(1.5, 4.5) + Utils.rand(-1.5, 1.5), normal.y * Utils.rand(1, 4) + Utils.rand(0, 2),
					normal.z * Utils.rand(1.5, 4.5) + Utils.rand(-1.5, 1.5),
					Utils.rand(0.15, 0.35), 0.62, 0.5, 0.32, 1.6)
			for i in 5:
				smoke_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(0.4, 1.2) + Utils.rand(-0.4, 0.4), Utils.rand(0.4, 1.2),
					normal.z * Utils.rand(0.4, 1.2) + Utils.rand(-0.4, 0.4),
					Utils.rand(0.3, 0.6), 0.55, 0.5, 0.4, 0.3, Utils.rand(0.8, 1.3))
		"glass":
			# 玻璃:透明碎屑(偏亮白) + 极少烟
			_impact_flash(pos, 1.3)
			for i in 7:
				if not _gate():
					continue
				spark_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(2, 6) + Utils.rand(-2, 2), normal.y * Utils.rand(1, 5) + Utils.rand(0, 2),
					normal.z * Utils.rand(2, 6) + Utils.rand(-2, 2),
					Utils.rand(0.12, 0.3), 0.9, 0.95, 1.0, 1.8, Utils.rand(0.6, 1.0))
		"snow":
			# 雪地:白尘缓散,几乎无火花
			for i in 8:
				if not _gate():
					continue
				smoke_spawn(pos.x, pos.y, pos.z,
					Utils.rand(-0.8, 0.8), Utils.rand(0.4, 1.5), Utils.rand(-0.8, 0.8),
					Utils.rand(0.4, 0.9), 0.9, 0.92, 0.95, 0.15, Utils.rand(0.9, 1.5))
		_:
			# 混凝土/砖墙:偏白的碎屑火花 + 灰粉尘
			_impact_flash(pos, 0.7)
			for i in 6:
				if not _gate():
					continue
				spark_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(1, 4) + Utils.rand(-2, 2), normal.y * Utils.rand(1, 4) + Utils.rand(0, 3),
					normal.z * Utils.rand(1, 4) + Utils.rand(-2, 2),
					Utils.rand(0.1, 0.3), 0.9, 0.78, 0.55, 1.2)
			for i in 5:
				smoke_spawn(pos.x, pos.y, pos.z,
					normal.x * Utils.rand(0.5, 1.5) + Utils.rand(-0.5, 0.5), Utils.rand(0.5, 1.8),
					normal.z * Utils.rand(0.5, 1.5) + Utils.rand(-0.5, 0.5),
					Utils.rand(0.3, 0.7), 0.55, 0.53, 0.5, 0.05)
	# 跳弹金属啸叫
	if not ricocheted and randf() < 0.3:
		AudioSys.ricochet(pos)


## 着弹点微闪光:借用枪口焰池(短命小尺寸,加法混合)
func _impact_flash(pos: Vector3, strength: float) -> void:
	var f = null
	for fl in _flashes:
		if fl["life"] <= 0:
			f = fl
			break
	if f == null:
		f = _flashes[0]
	var s: Sprite3D = f["sprite"]
	s.position = pos
	s.pixel_size = 0.085 * clampf(strength, 0.5, 1.6)
	s.rotation.z = Utils.rand(TAU)
	s.modulate = Color(1, 0.94, 0.78, 1)
	s.visible = true
	f["life"] = 0.07
	f["max_life"] = 0.07
	f["bright"] = 0.7
	f["decay_pow"] = 2.0


## 贯穿效果(子弹穿墙):沿路径喷出一串细尘 + 出口闪光(供弹道系统调用)
func penetration(from: Vector3, to: Vector3, _material := "") -> void:
	var dir := (to - from)
	var dist := dir.length()
	if dist < 0.1:
		return
	dir /= dist
	var steps: int = clampi(int(dist / 1.2), 2, 8)
	for i in steps:
		if not _gate():
			continue
		var p := from + dir * (dist * float(i + 1) / float(steps + 1))
		smoke_spawn(p.x, p.y, p.z,
			dir.x * Utils.rand(0.3, 1.0) + Utils.rand(-0.3, 0.3), Utils.rand(0.2, 0.8),
			dir.z * Utils.rand(0.3, 1.0) + Utils.rand(-0.3, 0.3),
			Utils.rand(0.2, 0.4), 0.55, 0.53, 0.5, 0.1, Utils.rand(0.7, 1.1))
	_impact_flash(to, 1.0)


## 材质自动推断:贴地且法线朝上 → 泥土(雪地图 → 雪);
## 其余沿法线反向探针命中碰撞盒,按几何粗判(复用 Utils 薄壁启发式):
## 高<3.5 且 min(w,d)<0.6 → 木质掩体;小号紧凑盒(油桶/弹药箱) → 金属;其余 → 混凝土
func _material_at(pos: Vector3, normal: Vector3) -> String:
	var gh: float = G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0
	if pos.y <= gh + 0.12 and normal.y > 0.35:
		return "snow" if G.current_map == "snow" else "dirt"
	var probe = Utils.raycast_world(pos + normal * 0.03, -normal, 1.2)
	if probe != null and probe["box"] is AABB:
		var b: AABB = probe["box"]
		var h: float = b.size.y
		var w: float = b.size.x
		var d: float = b.size.z
		# 薄壁低矮 → 木质(围栏/木箱/棚屋),可穿透性判定同 Utils.is_light_cover(放宽到 0.6)
		if h < 3.5 and minf(w, d) < 0.6:
			return "wood"
		# 小号紧凑盒 → 金属(油桶/铁箱/装甲壳)
		if h < 2.2 and maxf(w, d) < 1.4:
			return "metal"
	return "concrete"


## 血液:低饱和红雾 + 弹射方向的血滴(真实重力)+ 地面血迹 + 命中微闪
func blood(pos: Vector3, dir: Vector3) -> void:
	# 血雾:沿命中方向喷射扩散(快散,半透明)
	for i in int(8 * _budget()):
		smoke_spawn(pos.x, pos.y, pos.z,
			dir.x * Utils.rand(0.3, 1.5) + Utils.rand(-1.0, 1.0), Utils.rand(0.3, 1.8),
			dir.z * Utils.rand(0.3, 1.5) + Utils.rand(-1.0, 1.0),
			Utils.rand(0.18, 0.4), 0.5, 0.05, 0.04, 0.6, Utils.rand(0.7, 1.2))
	# 血滴:沿命中方向高速喷射,重下落、随机尺寸
	for i in int(10 * _budget()):
		if not _gate():
			continue
		spark_spawn(pos.x, pos.y, pos.z,
			dir.x * Utils.rand(1.5, 5.0) + Utils.rand(-1.2, 1.2),
			Utils.rand(0.5, 4.0),
			dir.z * Utils.rand(1.5, 5.0) + Utils.rand(-1.2, 1.2),
			Utils.rand(0.12, 0.4), 0.55, 0.03, 0.03, 2.4, Utils.rand(0.6, 1.5))
	# 地面血迹(贴地深红雾)
	for i in int(4 * _budget()):
		smoke_spawn(pos.x + Utils.rand(-0.3, 0.3), pos.y - 0.05, pos.z + Utils.rand(-0.3, 0.3),
			Utils.rand(-0.3, 0.3), Utils.rand(0.1, 0.4), Utils.rand(-0.3, 0.3),
			Utils.rand(0.8, 1.5), 0.4, 0.02, 0.02, 1.5, Utils.rand(0.9, 1.2))
	_impact_flash(pos, 0.55)


## 阵亡倒地尘土:士兵倒地溅起尘土环 + 细尘上浮 + 血泊(玩家/士兵通用)
func death_dust(pos: Vector3) -> void:
	var q := _budget()
	for i in int(10 * q):
		var a := Utils.rand(TAU)
		smoke_spawn(pos.x + Utils.rand(-0.3, 0.3), pos.y + Utils.rand(0.0, 0.4), pos.z + Utils.rand(-0.3, 0.3),
			cos(a) * Utils.rand(0.5, 1.8), Utils.rand(0.4, 1.2), sin(a) * Utils.rand(0.5, 1.8),
			Utils.rand(0.6, 1.1), 0.52, 0.46, 0.38, 0.6, Utils.rand(0.9, 1.5))
	for i in int(6 * q):
		smoke_spawn(pos.x + Utils.rand(-0.4, 0.4), pos.y + Utils.rand(0.2, 0.8), pos.z + Utils.rand(-0.4, 0.4),
			Utils.rand(-0.25, 0.25), Utils.rand(0.6, 1.6), Utils.rand(-0.25, 0.25),
			Utils.rand(0.8, 1.4), 0.45, 0.4, 0.34, -0.1, Utils.rand(1.0, 1.8))
	for i in int(4 * q):
		smoke_spawn(pos.x + Utils.rand(-0.35, 0.35), pos.y - 0.03, pos.z + Utils.rand(-0.35, 0.35),
			Utils.rand(-0.2, 0.2), Utils.rand(0.05, 0.25), Utils.rand(-0.2, 0.2),
			Utils.rand(1.0, 1.6), 0.38, 0.02, 0.02, 1.5, Utils.rand(1.0, 1.5))


## 弹壳(程序化模型,按枪种类型切换);power=抛壳力度(狙击枪/霰弹更猛)
func casing(pos: Vector3, cam_basis: Basis, bullet_type := 0, power := 1.0) -> void:
	var c = null
	for cs in _casings:
		if cs["life"] <= 0:
			c = cs
			break
	if c == null:
		c = _casings[0]
	var holder: Node3D = c["holder"]
	var m: MeshInstance3D = c["mesh"]
	holder.position = pos
	var right: Vector3 = cam_basis.x
	var pw := clampf(power, 0.7, 1.5)
	c["vel"] = right * Utils.rand(1.2, 2) * pw
	c["vel"].y = Utils.rand(1.5, 2.5) * pw
	c["vel"] += cam_basis.z * Utils.rand(-0.25, 0.25)
	# 随机翻滚角速度:枪越猛翻得越快
	c["rot"] = Vector3(Utils.rand(-16, 16), Utils.rand(-16, 16), Utils.rand(-16, 16)) * (0.7 + pw * 0.5)
	c["life"] = 1.2 * (0.75 + pw * 0.45)
	if c["bullet_type"] != bullet_type:
		c["bullet_type"] = bullet_type
		m.mesh = _casing_mesh(bullet_type)
		m.material_override = _casing_mat(bullet_type)
	m.visible = true
	holder.visible = true


## 换弹时掉落的弹匣
func spawn_mag(pos: Vector3) -> void:
	var mg = null
	for m2 in _mags:
		if m2["life"] <= 0:
			mg = m2
			break
	if mg == null:
		mg = _mags[0]
	var m: MeshInstance3D = mg["mesh"]
	m.position = pos
	mg["vel"] = Vector3(Utils.rand(-0.4, 0.4), Utils.rand(-0.5, -0.2), Utils.rand(-0.4, 0.4))
	mg["rot"] = Vector3(Utils.rand(-6, 6), Utils.rand(-6, 6), Utils.rand(-6, 6))
	mg["life"] = 2.5
	m.visible = true


## 手雷(程序化模型)
func spawn_grenade(p_owner, pos: Vector3, dir: Vector3, speed := 16.0, rise := 3.5) -> void:
	var holder := Node3D.new()
	holder.position = pos
	var nade_mesh := MeshInstance3D.new()
	nade_mesh.mesh = _grenade_mesh
	nade_mesh.material_override = _grenade_mat
	holder.add_child(nade_mesh)
	add_child(holder)
	_grenades.append({
		"owner": p_owner, "mesh": holder, "pos": pos,
		"vel": dir * speed + Vector3(0, rise, 0),
		"timer": 2.2, "bounced": false,
	})


## 烟雾弹(突击/支援:落地起烟,阻断视线 14 秒)
func spawn_smoke_grenade(p_owner, pos: Vector3, dir: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = pos
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 0.14
	cm.radial_segments = 10
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html("#4a5a52")
	mat.roughness = 0.6
	mat.metallic = 0.3
	m.material_override = mat
	holder.add_child(m)
	add_child(holder)
	_grenades.append({
		"owner": p_owner, "mesh": holder, "pos": pos,
		"vel": dir * 13 + Vector3(0, 3.0, 0),
		"timer": 1.0, "bounced": false, "smoke": true,
	})


## 反坦克手雷(更重;磁碰载具即炸;对载具高伤、对人小溅射)
func spawn_at_grenade(p_owner, pos: Vector3, dir: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = pos
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.055
	cm.height = 0.16
	cm.radial_segments = 10
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html("#5a4a2a")
	mat.roughness = 0.5
	mat.metallic = 0.5
	m.material_override = mat
	holder.add_child(m)
	add_child(holder)
	var oteam: String = p_owner.team if p_owner.get("team") != null else ""
	_grenades.append({
		"owner": p_owner, "mesh": holder, "pos": pos,
		"vel": dir * 11 + Vector3(0, 2.6, 0),
		"timer": 2.6, "bounced": false,
		"at": true, "oteam": oteam,
	})


## 士兵阵亡掉落手中武器(池化;抛出落地后侧躺,25 秒后消失)
func spawn_dropped_weapon(weapon_id: String, pos: Vector3) -> void:
	var d = null
	for dr in _drops:
		if dr["life"] <= 0:
			d = dr
			break
	if d == null:
		d = _drops[0]
	var holder: Node3D = d["holder"]
	for c in holder.get_children():
		c.queue_free()
	holder.add_child(WeaponModels.build(weapon_id, false))
	holder.position = pos
	holder.rotation = Vector3(Utils.rand(-0.15, 0.15), Utils.rand(TAU), PI / 2.0 * 0.92)
	d["vel"] = Vector3(Utils.rand(-0.9, 0.9), Utils.rand(1.4, 2.4), Utils.rand(-0.9, 0.9))
	d["yaw_vel"] = Utils.rand(-4.0, 4.0)
	d["life"] = 25.0
	holder.visible = true


func _update_drops(dt: float) -> void:
	for d in _drops:
		if d["life"] <= 0:
			continue
		d["life"] -= dt
		var holder: Node3D = d["holder"]
		if d["life"] <= 0:
			holder.visible = false
			continue
		var v: Vector3 = d["vel"]
		if v.length_squared() > 0.001:
			v.y -= 9.8 * dt
			holder.position += v * dt
			holder.rotation.y += d["yaw_vel"] * dt
			var gy: float = (G.ground_h.call(holder.position.x, holder.position.z) if G.ground_h.is_valid() else 0.0) + 0.07
			if holder.position.y <= gy:
				holder.position.y = gy
				v.y *= -0.25
				v.x *= 0.4
				v.z *= 0.4
				if absf(v.y) < 0.6:
					v = Vector3.ZERO
					d["yaw_vel"] = 0.0
			d["vel"] = v


## 火箭弹/炮弹(target: 制导目标,防空导弹用)
func spawn_rocket(p_owner, def, pos: Vector3, dir: Vector3, target = null) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _rocket_mesh
	mesh.material_override = _rocket_mat
	mesh.position = pos
	var ref_up := Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
	mesh.basis = Basis.looking_at(dir, ref_up, true) * Basis.from_euler(Vector3(-PI / 2, 0, 0))
	add_child(mesh)
	var spd := 38.0
	if def is Dictionary:
		spd = float(def.get("speed", 38.0))
	else:
		spd = float(def.speed)
	_rockets.append({
		"owner": p_owner, "def": def, "mesh": mesh, "pos": pos, "dir": dir,
		"speed": spd, "life": 8.0, "smoke_t": 0.0, "target": target,
	})


## 爆炸:多层结构(闪光球+双层冲击波环+烟柱+火星+地面尘土+碎片)
## 时间轴分阶段:爆闪(0~0.3s)→ 扩张(0.12s 火球二次脉冲)→ 烟柱浮升(0.32~2.5s)→ 尘土(0.5s)
## 物理参数:烟密度/热浮升速度随半径放大;粒子数按画质×帧率降级
func explosion(pos: Vector3, radius := 6.0) -> void:
	var R := maxf(radius, 2.0)
	# 粒子预算:画质档×帧率自适应×爆炸半径密度(大爆炸不堆粒子,防低配爆炸)
	var q := _budget() * G.fx_boom_density(R)
	var gy: float = (G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0)
	# ---- 阶段1 爆闪球:白炽核心(短命,加法混合瞬时点亮) ----
	for i in int(24 * q):
		var a := Utils.rand(TAU)
		var e := Utils.rand(0.1, 1.0)
		var sp := Utils.rand(5.0, 15.0) * (0.7 + 0.3 * R / 6.0)
		spark_spawn(pos.x + Utils.rand(-0.25, 0.25), pos.y + 0.25 + Utils.rand(-0.2, 0.2), pos.z + Utils.rand(-0.25, 0.25),
			cos(a) * sp, e * sp, sin(a) * sp,
			Utils.rand(0.1, 0.28), 1.0, Utils.rand(0.8, 0.98), Utils.rand(0.4, 0.55), 0.35, Utils.rand(1.0, 1.8))
	# ---- 阶段1b 炽热火球(橙红,较慢,构成体积火) ----
	for i in int(14 * q):
		var a := Utils.rand(TAU)
		var sp := Utils.rand(2.5, 9.0)
		spark_spawn(pos.x + Utils.rand(-0.3, 0.3), pos.y + 0.3 + Utils.rand(-0.2, 0.3), pos.z + Utils.rand(-0.3, 0.3),
			cos(a) * sp, Utils.rand(0.5, 2.0) + sp * 0.4, sin(a) * sp,
			Utils.rand(0.2, 0.45), 1.0, Utils.rand(0.45, 0.7), Utils.rand(0.1, 0.25), 0.5, Utils.rand(1.2, 2.2))
	# ---- 阶段2 火星余烬:长寿命拖尾,真实重力回落 ----
	for i in int(20 * q):
		var a := Utils.rand(TAU)
		var e := Utils.rand(0.0, 1.0)
		var sp := Utils.rand(4, 14)
		spark_spawn(pos.x + Utils.rand(-0.1, 0.1), pos.y + 0.3 + e * 0.3, pos.z + Utils.rand(-0.1, 0.1),
			cos(a) * sp, e * sp + Utils.rand(1, 3), sin(a) * sp,
			Utils.rand(0.3, 0.7), Utils.rand(0.7, 1.0), Utils.rand(0.3, 0.5), 0.1, 1.2, Utils.rand(0.6, 1.2))
	# ---- 阶段3 初始烟团:爆炸瞬间一小撮浓烟(主烟柱延迟到 0.32s) ----
	for i in int(8 * q):
		var a := Utils.rand(TAU)
		var r := Utils.rand(0, R * 0.2)
		smoke_spawn(pos.x + cos(a) * r, pos.y + Utils.rand(0.2, 0.8), pos.z + sin(a) * r,
			Utils.rand(-0.6, 0.6), Utils.rand(1.5, 3.0), Utils.rand(-0.6, 0.6),
			Utils.rand(0.5, 1.0), 0.22, 0.21, 0.19, -0.35, Utils.rand(1.2, 2.0))
	# ---- 阶段4 地面尘土环:贴地平铺扩散,布朗色(延迟到 0.5s 二次加强) ----
	for i in int(12 * q):
		var a := Utils.rand(TAU)
		var sp := Utils.rand(1.5, 4.5) * (0.7 + 0.4 * R / 6.0)
		smoke_spawn(pos.x, gy + 0.05, pos.z,
			cos(a) * sp, Utils.rand(0.3, 1.2), sin(a) * sp,
			Utils.rand(0.5, 1.1), 0.42, 0.36, 0.28, 0.5, Utils.rand(1.0, 1.8))
	# ---- 阶段5 碎片:深色大块,强重力抛物 ----
	for i in int(12 * q):
		var a := Utils.rand(TAU)
		var sp := Utils.rand(6, 16)
		spark_spawn(pos.x, pos.y + 0.4, pos.z,
			cos(a) * sp, Utils.rand(3, 9), sin(a) * sp,
			Utils.rand(0.7, 1.5), 0.25, 0.22, 0.19, 1.8, Utils.rand(0.9, 1.7))
	# ---- 爆心光源:池化分配(并发爆炸不互相覆盖) + 闪亮 + 抖动衰减 ----
	var expl_light: OmniLight3D = _expl_light_for(pos)
	expl_light.position = pos + Vector3(0, 1.5, 0)
	expl_light.light_energy = 70.0 * (0.8 + 0.4 * R / 6.0)
	# ---- 延迟事件:扩张→烟柱→尘土(时间轴分阶段,帧率低时按预算缩水) ----
	_delay("boom_fire", 0.12, pos, { "radius": R, "q": q, "light": expl_light })
	_delay("boom_smoke", 0.32, pos, { "radius": R, "q": q, "gy": gy })
	_delay("boom_dust", 0.5, pos, { "radius": R, "q": q, "gy": gy })
	# ---- 冲击波双层:细锐快环(先发) + 厚重慢环(余波) ----
	for i in 2:
		var ring = null
		for rg in _rings:
			if rg["life"] <= 0:
				ring = rg
				break
		if ring == null:
			ring = _rings[0]
		var rm: MeshInstance3D = ring["mesh"]
		rm.position = Vector3(pos.x, gy + 0.15, pos.z)
		rm.visible = true
		if i == 0:
			ring["dur"] = 0.38
			ring["max_r"] = radius * 1.4
			ring["base_a"] = 0.8
			(rm.material_override as StandardMaterial3D).albedo_color = Color(1, 0.85, 0.65, 0.8)
		else:
			ring["dur"] = 0.7
			ring["max_r"] = radius * 1.15
			ring["base_a"] = 0.45
			(rm.material_override as StandardMaterial3D).albedo_color = Color(0.6, 0.45, 0.3, 0.45)
		ring["life"] = ring["dur"]
	# ---- 相机表现:距离衰减震屏 + 方向性横向踢(朝爆点) ----
	var d: float = G.camera.global_position.distance_to(pos) if G.camera else 99.0
	var s_amt := clampf(1.6 - d / 25.0, 0, 1.2)
	shake(s_amt)
	if G.camera != null and d > 0.5:
		var to_boom := (pos - G.camera.global_position) / d
		_shake_bias = G.camera.global_transform.basis.x.dot(to_boom) * clampf(s_amt, 0, 1) * 0.35
	# 近爆全屏闪光(45m 内,越近越亮;大爆炸更亮)
	if d < 45.0:
		screen_flash(Color(1.0, 0.8, 0.55), clampf((1.0 - d / 45.0) * 0.5 * (0.7 + 0.3 * R / 6.0), 0, 0.85))
	AudioSys.explosion(pos)


## 延迟事件登记(时间轴分阶段播放)
func _delay(kind: String, t: float, pos: Vector3, data := {}) -> void:
	_delayed.append({ "kind": kind, "t": t, "pos": pos, "data": data })


func _update_delayed(dt: float) -> void:
	for i in range(_delayed.size() - 1, -1, -1):
		var d: Dictionary = _delayed[i]
		d["t"] -= dt
		if d["t"] <= 0.0:
			_delayed.remove_at(i)
			_run_delayed(d)


## 延迟事件执行:爆炸扩张/烟柱/尘土各阶段
func _run_delayed(d: Dictionary) -> void:
	var pos: Vector3 = d["pos"]
	var data: Dictionary = d["data"]
	match d["kind"]:
		"boom_fire":
			# 扩张阶段:橙红火球二次脉冲(更慢更大)
			var R: float = float(data.get("radius", 6.0))
			var q: float = float(data.get("q", 1.0))
			for i in int(16 * q):
				var a := Utils.rand(TAU)
				var sp := Utils.rand(3.0, 8.0)
				spark_spawn(pos.x + Utils.rand(-0.4, 0.4), pos.y + 0.4 + Utils.rand(-0.3, 0.4), pos.z + Utils.rand(-0.4, 0.4),
					cos(a) * sp, Utils.rand(0.5, 2.2) + sp * 0.5, sin(a) * sp,
					Utils.rand(0.25, 0.5), 1.0, Utils.rand(0.4, 0.62), Utils.rand(0.08, 0.2), 0.35, Utils.rand(1.4, 2.4))
			var lg = data.get("light")
			if lg != null:
				lg.light_energy = maxf(lg.light_energy, 40.0 * (0.6 + 0.4 * R / 6.0))
		"boom_smoke":
			# 烟柱主喷:浓密热浮升(负重力=上升),直径随半径放大
			var R: float = float(data.get("radius", 6.0))
			var q: float = float(data.get("q", 1.0))
			var rise := Utils.rand(2.0, 4.5) * (1.0 + 0.3 * R / 6.0)
			for i in int(24 * q):
				var a := Utils.rand(TAU)
				var r := Utils.rand(0, R * 0.35)
				smoke_spawn(pos.x + cos(a) * r, pos.y + Utils.rand(0.4, 1.4), pos.z + sin(a) * r,
					Utils.rand(-0.8, 0.8), rise, Utils.rand(-0.8, 0.8),
					Utils.rand(1.2, 2.4), 0.24, 0.23, 0.21, -0.45, Utils.rand(1.4, 2.6))
			# 顶部翻滚浓烟(更暗、轻微水平扩张)
			for i in int(12 * q):
				var a := Utils.rand(TAU)
				var r := Utils.rand(0, R * 0.55)
				smoke_spawn(pos.x + cos(a) * r, pos.y + Utils.rand(1.2, 3.0), pos.z + sin(a) * r,
					Utils.rand(-1.5, 1.5), Utils.rand(-0.5, 1.5), Utils.rand(-1.5, 1.5),
					Utils.rand(1.0, 1.8), 0.17, 0.16, 0.15, -0.2, Utils.rand(1.8, 3.0))
		"boom_dust":
			# 尘土二次环:贴地强力铺开 + 细尘上扬
			var q: float = float(data.get("q", 1.0))
			var gy: float = float(data.get("gy", 0.0))
			for i in int(16 * q):
				var a := Utils.rand(TAU)
				var sp := Utils.rand(2.0, 5.5)
				smoke_spawn(pos.x, gy + 0.05, pos.z,
					cos(a) * sp, Utils.rand(0.4, 1.6), sin(a) * sp,
					Utils.rand(0.6, 1.2), 0.45, 0.38, 0.3, 0.4, Utils.rand(1.1, 2.0))
			for i in int(8 * q):
				smoke_spawn(pos.x + Utils.rand(-0.6, 0.6), gy + Utils.rand(0.2, 0.8), pos.z + Utils.rand(-0.6, 0.6),
					Utils.rand(-0.4, 0.4), Utils.rand(0.6, 1.8), Utils.rand(-0.4, 0.4),
					Utils.rand(0.9, 1.6), 0.5, 0.44, 0.36, -0.05, Utils.rand(1.0, 1.8))


## 全屏闪光(爆闪/被击中时的暖光过曝)
func screen_flash(color: Color, strength: float) -> void:
	_flash_rect.color = color
	_flash_alpha = maxf(_flash_alpha, clampf(strength, 0, 0.85))


## 部署/重部署时立即清掉死亡黑幕(update_effects 在 deploy 状态不跑,必须显式复位)
func reset_death_fade() -> void:
	_fade_alpha = 0.0
	_fade_rect.modulate.a = 0.0
	_was_dead = false


## 夜视仪开关:绿色滤镜 + 暗角显示/隐藏;环境亮度 1.35 提亮,关闭还原 1.0(env 为空跳过)
func set_night_vision(on: bool) -> void:
	if _nvg_rect == null:
		return
	_nvg_rect.modulate.a = 1.0 if on else 0.0
	_nvg_vg.modulate.a = 1.0 if on else 0.0
	if G.world_env != null and G.world_env.environment != null:
		G.world_env.environment.adjustment_brightness = 1.35 if on else 1.0


# ==================== 每帧更新 ====================
func update_effects(dt: float) -> void:
	_eff_t += dt
	if not _fxaa_wired:
		_fxaa_wired = true
		if OS.get_cmdline_user_args().has("--fxaa-debug"):
			_wire_fxaa_debug()
	# 画质档位联动:设置菜单/预设任意路径改动 particles 都能生效
	var sp: Dictionary = G.settings
	fx_scale = float(sp.get("particles", 1.0)) * float(sp.get("fx_scale", 1.0))
	# 帧率自适应降级:60fps 满配,低于 60 平滑降至 0.35 封底
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		_fps_smoothed = lerpf(_fps_smoothed, fps, minf(dt * 8.0, 1.0))
	_fps_scale = clampf(_fps_smoothed / 60.0, 0.35, 1.0)
	_update_particles(dt)
	_update_tracers(dt)
	_update_flashes(dt)
	_update_delayed(dt)
	_muzzle_light.light_energy *= pow(0.0001, dt * 8) * (1.0 + Utils.rand(-0.18, 0.18))  # 光源闪烁噪声
	for lg in _expl_lights:
		(lg as OmniLight3D).light_energy *= pow(0.0001, dt * 3)
		if (lg as OmniLight3D).light_energy < 0.5:
			(lg as OmniLight3D).light_energy = 0.0  # 快速释放,便于下次分配
	_update_casings(dt)
	_update_grenades(dt)
	_update_rockets(dt)
	_update_rings(dt)
	_update_smoke(dt)
	_update_drops(dt)
	# 全屏闪光衰减(快速过曝)
	if _flash_alpha > 0:
		_flash_alpha = maxf(0.0, _flash_alpha - dt * 3.6)
		_flash_rect.modulate.a = _flash_alpha * _flash_alpha
	# 死亡淡出:阵亡适当压暗(0.35,战场仍可见),重生快速退场
	var target_fade := 0.35 if G.state == "dead" else 0.0
	if _was_dead != (G.state == "dead"):
		_was_dead = G.state == "dead"
		if G.state == "dead":
			# 阵亡瞬间:深红过曝闪一下(死亡反馈)
			screen_flash(Color(0.72, 0.08, 0.05), 0.4)
	var fade_k := 0.9 if G.state == "dead" else 2.2
	_fade_alpha = lerpf(_fade_alpha, target_fade, minf(1.0, dt * fade_k))
	if _fade_alpha > 0.005:
		_fade_rect.modulate.a = clampf(_fade_alpha / 0.35, 0.0, 1.0) * 0.35
	else:
		_fade_rect.modulate.a = 0.0
	# 受伤红边 vignette(受击脉冲 + 低血量常驻)
	_update_damage_vignette(dt)
	# 阵亡检测(玩家/士兵倒地尘土)
	_poll_deaths()
	# 屏幕震动:指数衰减 + 噪声 + 爆炸方向横向踢
	shake_amt = maxf(0, shake_amt - dt * (3.2 + shake_amt * 1.8))
	_shake_bias = lerpf(_shake_bias, 0.0, minf(1.0, dt * 3.5))
	var s := shake_amt * shake_amt * 0.02
	shake_pitch = Utils.rand(-s, s) + shake_amt * 0.004
	shake_yaw = Utils.rand(-s, s) + _shake_bias * shake_amt


## --fxaa-debug 调试开关:把主界 FXAA 材质换成 fxaa_test.gdshader
## (mode: 0=原样透传校准 1=轻量 FXAA 2=边缘可视化,默认 2;可 --fxaa-debug 1 指定)
## 只动 fx 层(读取 main.gd 的 _fxaa_rect 并替换 material),不改 main.gd
func _wire_fxaa_debug() -> void:
	if G.main == null:
		return
	var rect: ColorRect = G.main.get("_fxaa_rect")
	if rect == null:
		return
	var mode := 2
	var ua := OS.get_cmdline_user_args()
	var idx := ua.find("--fxaa-debug")
	if idx >= 0 and ua.size() > idx + 1 and ua[idx + 1] in ["0", "1", "2"]:
		mode = int(ua[idx + 1])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/fx/fxaa_test.gdshader")
	mat.set_shader_parameter("mode", mode)
	rect.material = mat
	print("[FXAA-DEBUG] 已切换到 fxaa_test.gdshader mode=", mode, " (0=透传 1=轻量FXAA 2=边缘可视化)")


## 受伤红边:受击瞬间脉冲(按血量下降量) + 低血量常驻微红
func _update_damage_vignette(dt: float) -> void:
	var target := 0.0
	var p = G.player
	if p != null and G.state == "playing" and p.alive:
		if _last_health < 0.0:
			_last_health = p.health
		if p.health < _last_health:
			# 受击脉冲强度按伤害占比(34 点伤害≈满强度)
			var drop: float = clampf((_last_health - p.health) / 34.0, 0.12, 1.0)
			_dmg_alpha = maxf(_dmg_alpha, drop)
		_last_health = p.health
		# 低血量常驻红边(0~30 血线性增强)
		if p.health < 30.0:
			target = (1.0 - p.health / 30.0) * 0.32
	else:
		_last_health = -1.0
	# 冲击衰减快,常驻趋近慢
	var k := 5.5 if _dmg_alpha > target else 1.6
	_dmg_alpha = lerpf(_dmg_alpha, target, minf(1.0, dt * k))
	var a := _dmg_alpha
	if a > 0.004:
		# 呼吸脉动:冲击峰值上叠加微颤,模拟血压感
		a += maxf(0.0, sin(_eff_t * 14.0)) * _dmg_alpha * 0.15
		_dmg_rect.modulate.a = clampf(a, 0.0, 1.0)
	else:
		_dmg_rect.modulate.a = 0.0


## 阵亡检测:玩家与士兵倒地瞬间扬尘(士兵存活状态变化时触发一次)
func _poll_deaths() -> void:
	if G.player != null:
		if G.player.alive != _player_was_alive:
			_player_was_alive = G.player.alive
			if not G.player.alive and G.player.pos != null:
				death_dust(G.player.pos + Vector3(0, 0.9, 0))
	for b in G.bots:
		if b == null or not is_instance_valid(b):
			continue
		var key: int = b.get_instance_id()
		if not _bot_alive.has(key):
			_bot_alive[key] = b.alive
		elif _bot_alive[key] != b.alive:
			var was_alive: bool = _bot_alive[key]
			_bot_alive[key] = b.alive
			if was_alive and not b.alive and b.pos != null:
				death_dust(b.pos + Vector3(0, 0.9, 0))


## 烟雾区更新:持续喷烟 + 倒计时清除
func _update_smoke(dt: float) -> void:
	for i in range(G.smoke_zones.size() - 1, -1, -1):
		var s: Dictionary = G.smoke_zones[i]
		s["life"] -= dt
		s["emit_t"] -= dt
		if s["life"] <= 0:
			G.smoke_zones.remove_at(i)
			continue
		if s["emit_t"] <= 0:
			s["emit_t"] = 0.09
			var p: Vector3 = s["pos"]
			var a := Utils.rand(TAU)
			var r := Utils.rand(0.2, s["radius"] * 0.8)
			smoke_spawn(p.x + cos(a) * r, p.y + Utils.rand(0.1, 0.8), p.z + sin(a) * r,
				Utils.rand(-0.25, 0.25), Utils.rand(0.25, 0.7), Utils.rand(-0.25, 0.25),
				Utils.rand(1.6, 2.6), 0.62, 0.64, 0.66, -0.01)


func _update_particles(dt: float) -> void:
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))
	# 活动计数为空则整池跳过(原 3000 次空循环)
	# [PERF] P1-4:扫描上限=高水位 _sparks_scan_max(原固定扫 MAXP 全池)。
	# 环形池在覆盖时保证 head 侧连续,但中间死亡会在存活集合留空槽,不能只扫活跃数;
	# 改为"最高可能存活槽"水位:顶部死亡后逐帧收缩(均摊 O(1)),任何时点扫描槽
	# 集是原全池扫描槽集的子集,语义完全一致,低活跃期显著少扫
	if _sparks_alive > 0:
		for i in _sparks_scan_max:
			if _sparks_life[i] <= 0:
				continue
			_sparks_life[i] -= dt
			if _sparks_life[i] <= 0:
				_sparks_alive -= 1
				_sparks_mm.set_instance_transform(i, zero)
				continue
			var v := _sparks_vel[i]
			v.y -= 9.8 * _sparks_grav[i] * dt
			_sparks_vel[i] = v
			var p := _sparks_pos[i] + v * dt
			var gy: float = _ground_h(p.x, p.z) + 0.02
			if p.y < gy:
				p.y = gy
				v.y *= -0.3
				v.x *= 0.7
				v.z *= 0.7
				_sparks_vel[i] = v
			_sparks_pos[i] = p
			var sf: float = _sparks_life[i] / _sparks_max_life[i]
			var sz: float = _sparks_size[i] * clampf(minf(sf * 2.0, 1.0), 0.08, 1.0)
			_sparks_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * sz), p))
			var c := _sparks_col[i]
			_sparks_mm.set_instance_color(i, Color(c.r, c.g, c.b, clampf(sf * 2.5, 0.0, 1.0)))
	while _sparks_scan_max > 0 and _sparks_life[_sparks_scan_max - 1] <= 0:
		_sparks_scan_max -= 1
	if _smoke_alive > 0:
		for i in _smoke_scan_max:
			if _smoke_life[i] <= 0:
				continue
			_smoke_life[i] -= dt
			if _smoke_life[i] <= 0:
				_smoke_alive -= 1
				_smoke_mm.set_instance_transform(i, zero)
				continue
			var v := _smoke_vel[i]
			v.y -= 9.8 * _smoke_grav[i] * dt
			_smoke_vel[i] = v
			var p := _smoke_pos[i] + v * dt
			var gy: float = _ground_h(p.x, p.z) + 0.02
			if p.y < gy:
				p.y = gy
				v.y *= -0.3
				v.x *= 0.7
				v.z *= 0.7
				_smoke_vel[i] = v
			_smoke_pos[i] = p
			# 烟持续膨胀(体积感) + 淡出
			var f: float = _smoke_life[i] / _smoke_max_life[i]
			var growth: float = 1.0 + (1.0 - f) * 2.2
			_smoke_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (_smoke_size[i] * growth)), p))
			var col := _smoke_col[i]
			_smoke_mm.set_instance_color(i, Color(col.r, col.g, col.b, 0.5 * minf(1, f / 0.3)))
	while _smoke_scan_max > 0 and _smoke_life[_smoke_scan_max - 1] <= 0:
		_smoke_scan_max -= 1
	if _fire_alive > 0:
		for i in _fire_scan_max:
			if _fire_life[i] <= 0:
				continue
			_fire_life[i] -= dt
			if _fire_life[i] <= 0:
				_fire_alive -= 1
				_fire_mm.set_instance_transform(i, zero)
				continue
			var fv := _fire_vel[i]
			# 热浮升(轻缓上升) + 水平扩散阻尼
			fv.y += 3.0 * _fire_power[i] * dt
			fv.x *= 0.92
			fv.z *= 0.92
			_fire_vel[i] = fv
			var fp := _fire_pos[i] + fv * dt
			var fgy: float = _ground_h(fp.x, fp.z) + 0.02
			if fp.y < fgy:
				fp.y = fgy
				fv.y = maxf(fv.y, 0.0)
				_fire_vel[i] = fv
			_fire_pos[i] = fp
			var ft: float = _fire_life[i] / _fire_max_life[i]
			# 缩放衰减 0.5→0.1 + 快速淡出
			var fs: float = _fire_size[i] * lerpf(0.5, 0.1, 1.0 - ft)
			_fire_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * fs), fp))
			var fc := _fire_col[i]
			_fire_mm.set_instance_color(i, Color(fc.r, fc.g, fc.b, clampf(ft * ft * 2.2, 0.0, 1.0)))
	while _fire_scan_max > 0 and _fire_life[_fire_scan_max - 1] <= 0:
		_fire_scan_max -= 1


func _update_tracers(dt: float) -> void:
	for t in _tracers:
		if t["life"] <= 0:
			continue
		t["life"] -= dt
		var m: MeshInstance3D = t["mesh"]
		var c: Color = (m.material_override as StandardMaterial3D).albedo_color
		var flicker := 0.9 + Utils.rand(-0.12, 0.12)
		var ml: float = t.get("max_life", 0.07)
		var k: float = clampf(t["life"] / ml, 0.0, 1.0) if ml > 0.0 else 0.0
		c.a = k * 0.9 * flicker
		(m.material_override as StandardMaterial3D).albedo_color = c
		if t["life"] <= 0:
			m.visible = false


func _update_flashes(dt: float) -> void:
	for f in _flashes:
		if f["life"] <= 0:
			continue
		f["life"] -= dt
		var s: Sprite3D = f["sprite"]
		if f["life"] <= 0:
			s.visible = false
			continue
		# BF 式衰减:峰值锐利 → 长尾拖光(衰减曲线指数按武器独立)
		var k: float = f["life"] / f["max_life"]
		var a: float = pow(k, f.get("decay_pow", 1.5)) * f["bright"]
		s.modulate = Color(1, 1, 1, clampf(a, 0, 1))
		var flare: float = (1.0 - k) * f["bright"]
		s.scale = Vector3.ONE * (1.0 + flare * 0.9)


func _update_casings(dt: float) -> void:
	for c in _casings:
		if c["life"] <= 0:
			continue
		c["life"] -= dt
		var holder: Node3D = c["holder"]
		if c["life"] <= 0:
			holder.visible = false
			continue
		var v: Vector3 = c["vel"]
		v.y -= 9.8 * dt
		holder.position += v * dt
		var gy: float = (G.ground_h.call(holder.position.x, holder.position.z) if G.ground_h.is_valid() else 0.0) + 0.02
		if holder.position.y < gy:
			holder.position.y = gy
			if absf(v.y) < 1.1:
				v = Vector3(v.x * 0.55, 0, v.z * 0.55)
				if v.length() < 0.15:
					v = Vector3.ZERO
					c["rot"] = Vector3.ZERO
			else:
				v.y *= -0.35
				v.x *= 0.6
				v.z *= 0.6
		c["vel"] = v
		var r: Vector3 = c["rot"]
		holder.get_child(0).rotation.x += r.x * dt
		holder.get_child(0).rotation.y += r.y * dt
		holder.get_child(0).rotation.z += r.z * dt
	for mg in _mags:
		if mg["life"] <= 0:
			continue
		mg["life"] -= dt
		var m: MeshInstance3D = mg["mesh"]
		if mg["life"] <= 0:
			m.visible = false
			continue
		var v: Vector3 = mg["vel"]
		v.y -= 9.8 * dt
		m.position += v * dt
		var gy: float = (G.ground_h.call(m.position.x, m.position.z) if G.ground_h.is_valid() else 0.0) + 0.055
		if m.position.y < gy:
			m.position.y = gy
			v.y *= -0.3
			v.x *= 0.5
			v.z *= 0.5
			mg["rot"] = (mg["rot"] as Vector3) * 0.5
		mg["vel"] = v
		var r: Vector3 = mg["rot"]
		m.rotation.x += r.x * dt
		m.rotation.y += r.y * dt
		m.rotation.z += r.z * dt


func _update_grenades(dt: float) -> void:
	for i in range(_grenades.size() - 1, -1, -1):
		var g: Dictionary = _grenades[i]
		g["timer"] -= dt
		var vel: Vector3 = g["vel"]
		vel.y -= 12 * dt
		var step: Vector3 = vel * dt
		var dist := step.length()
		var pos: Vector3 = g["pos"]
		if dist > 0.0001:
			var hit = Utils.raycast_world(pos, step / dist, dist + 0.08)
			if hit != null:
				var n: Vector3 = hit["normal"]
				vel = vel.bounce(n) * 0.45
				if not g["bounced"]:
					AudioSys.grenade_bounce(pos)
					g["bounced"] = true
			else:
				pos += step
		var ggy: float = (G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0) + 0.07
		if pos.y < ggy:
			pos.y = ggy
			vel.y *= -0.4
			vel.x *= 0.8
			vel.z *= 0.8
			if not g["bounced"]:
				AudioSys.grenade_bounce(pos)
				g["bounced"] = true
		g["vel"] = vel
		g["pos"] = pos
		(g["mesh"] as Node3D).position = pos
		(g["mesh"] as Node3D).rotation.x += dt * 9.0
		# 反坦克手雷:碰到非友军驾驶的载具立即引爆
		if g.get("at", false):
			for v in G.vehicles:
				if v.dead:
					continue
				var vt = v.team()
				if vt != null and vt == g["oteam"]:
					continue
				var rr: float = v.def["radius"] + 0.5
				var d2 := Vector2(v.pos.x - pos.x, v.pos.z - pos.z).length_squared()
				if d2 < rr * rr and absf(v.pos.y - pos.y) < 3.0:
					g["timer"] = 0
					break
		if g["timer"] <= 0:
			(g["mesh"] as Node3D).queue_free()
			_grenades.remove_at(i)
			if g.get("smoke", false):
				# 起烟:登记烟雾区(AI 视线阻断)
				G.smoke_zones.append({ "pos": pos, "radius": 4.2, "life": 14.0, "emit_t": 0.0 })
				AudioSys.grenade_bounce(pos)
			elif g.get("at", false):
				G.game.explode(pos, 4.5, 170, g["owner"])
			else:
				G.game.explode(pos, 6, 110, g["owner"])


func _update_rockets(dt: float) -> void:
	for i in range(_rockets.size() - 1, -1, -1):
		var r: Dictionary = _rockets[i]
		r["life"] -= dt
		var boom := false
		var pos: Vector3 = r["pos"]
		var dir: Vector3 = r["dir"]
		var target = r["target"]
		# 制导:追踪锁定目标(防空导弹)
		if target != null:
			# Aircraft 为 Object:alive 是方法而非属性,get("alive") 恒为 null,只能查 dead + 实例有效性
			if not is_instance_valid(target) or target.get("dead") == true:
				r["target"] = null
				target = null
			else:
				r["speed"] = minf(r["speed"] + 55 * dt, 85)
				var to: Vector3 = target.pos - pos
				var d_t := to.length()
				if d_t < 4.5:
					boom = true  # 近炸引信
				else:
					to /= d_t
					dir = Utils.safe_norm(dir.lerp(to, minf(1, 4.5 * dt)), to)
		if r["target"] == null:
			dir.y -= 0.25 * dt  # 无制导直射弹道:重力 0.25(较原 0.35 弹道更平直,显著提升射程)
			dir = Utils.safe_norm(dir, Vector3.UP)
		var step_len: float = r["speed"] * dt
		var hit = Utils.raycast_world(pos, dir, step_len + 0.2)
		if hit != null:
			pos = hit["point"]
			boom = true
		else:
			pos += dir * step_len
			var rgy: float = (G.ground_h.call(pos.x, pos.z) if G.ground_h.is_valid() else 0.0) + 0.05
			if pos.y <= rgy:
				boom = true
		# 尾烟
		r["smoke_t"] -= dt
		if r["smoke_t"] <= 0:
			r["smoke_t"] = 0.015
			smoke_spawn(pos.x, pos.y, pos.z, Utils.rand(-0.3, 0.3), Utils.rand(0, 0.5), Utils.rand(-0.3, 0.3),
				Utils.rand(0.4, 0.9), 0.7, 0.68, 0.62, -0.02)
			spark_spawn(pos.x, pos.y, pos.z, 0, 0, 0, 0.08, 1, 0.7, 0.3, 0)
		r["pos"] = pos
		r["dir"] = dir
		var mesh: MeshInstance3D = r["mesh"]
		mesh.position = pos
		# dir 接近竖直时 looking_at 无法确定参考轴,改用 RIGHT 作上向量
		var ref_up := Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
		mesh.basis = Basis.looking_at(dir, ref_up, true) * Basis.from_euler(Vector3(-PI / 2, 0, 0))
		if boom or r["life"] <= 0:
			mesh.queue_free()
			_rockets.remove_at(i)
			var def = r["def"]
			var splash: float = 6.5
			var dmg: float = 100.0
			if def is Dictionary:
				splash = float(def.get("splash", 6.5))
				dmg = float(def.get("damage", 100.0))
			else:
				splash = float(def.splash)
				dmg = float(def.damage)
			G.game.explode(pos, splash, dmg, r["owner"])


func _update_rings(dt: float) -> void:
	for r in _rings:
		if r["life"] <= 0:
			continue
		r["life"] -= dt
		var dur: float = r["dur"]
		if dur <= 0.0:
			dur = 0.45
		var t: float = 1 - r["life"] / dur
		var s: float = 0.5 + t * r["max_r"]
		var m: MeshInstance3D = r["mesh"]
		m.scale = Vector3(s, 1, s)
		var c: Color = (m.material_override as StandardMaterial3D).albedo_color
		c.a = pow(1 - t, 1.4) * float(r.get("base_a", 0.7))
		(m.material_override as StandardMaterial3D).albedo_color = c
		if r["life"] <= 0:
			m.visible = false
