class_name WorldBuilder
## 地图构建器(对应 map.js 的 buildWorld / updateMap)




## ==================== 地形高度场(全图平地) ====================
## 地形统一为 y=0 平地(修复地形数据 bug 的最终方案):
## 建筑/载具/出生点/粒子全部经由 G.ground_h 对齐,返回恒 0 即可。
static func make_ground_h(_theme_id: String, _size: float, _road: float) -> Callable:
	# 征服模式:恒 0 平地
	return func(_x: float, _z: float) -> float:
		return 0.0


static func make_bt_ground_h(_T, _size: float) -> Callable:
	# 突破模式:恒 0 平地(河道/海岸平滑压平逻辑已无意义)
	return func(_x: float, _z: float) -> float:
		return 0.0


## ==================== 共享材质工具 ====================
static func _std_tex(color: Color, rough: float, tex_name: String, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_repeat = true
	m.albedo_texture = load("res://textures/" + tex_name + "_diff.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://textures/" + tex_name + "_nor.jpg")
	return m


static func _std(color: Color, rough := 0.95, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


## 粒子公告牌材质(不受雾,用于雪花/星空)
static func _particle_mat(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec4 col : source_color = vec4(1.0);
void vertex() {
	mat4 bb = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}
void fragment() { ALBEDO = col.rgb; ALPHA = col.a; }
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("col", color)
	return sm


## 无光照材质(fog = 是否受雾影响)
static func _basic(color: Color, fog := true) -> Material:
	if fog:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return m
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec4 col : source_color = vec4(1.0);
void fragment() { ALBEDO = col.rgb; ALPHA = col.a; }
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("col", color)
	return sm


static func _box(w: float, h: float, d: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = mat
	return mi


static func _cyl(rt: float, rb: float, h: float, segs: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	return mi


static func _cone(r: float, h: float, segs: int, mat: Material) -> MeshInstance3D:
	return _cyl(0.0, r, h, segs, mat)


static func _ico(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 12
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	return mi


static func _shadows_on(node: Node) -> void:
	for o in node.get_children():
		if o is MeshInstance3D:
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_shadows_on(o)


## ==================== 碰撞网格脏标记(帧末合并重建) ====================
## 同帧多次销毁/残骸移除只重建一次空间网格,避免全量重建风暴
static var _grid_dirty := false


static func _rebuild_grid_deferred() -> void:
	_grid_dirty = false
	Utils.rebuild_collider_grid()


static func _mark_grid_dirty() -> void:
	if _grid_dirty:
		return
	_grid_dirty = true
	_rebuild_grid_deferred.call_deferred()


## 静态道具 MultiMesh 批量落地(每个材质一个 MultiMeshInstance3D)
static func _flush_prop_mm(wg: Node3D, buf: Dictionary) -> void:
	for mat in buf:
		var entry: Dictionary = buf[mat]
		var list: Array = entry["t"]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(mmi)


## 预烘焙 4m 分辨率地形高度网格(供粒子/雪花着地判定,避免逐帧噪声求值)
static func _bake_hgrid() -> Dictionary:
	var res := 4.0
	var half: float = G.bounds + 20.0
	var hn := int(ceil(half * 2.0 / res)) + 1
	var h := PackedFloat32Array()
	h.resize(hn * hn)
	for j in hn:
		for i in hn:
			h[j * hn + i] = G.ground_h.call(-half + i * res, -half + j * res)
	return { "res": res, "n": hn, "x0": -half, "z0": -half, "h": h }


## 网格高度查询(越界夹取)
static func _hgrid_h(hg: Dictionary, x: float, z: float) -> float:
	var hn: int = hg["n"]
	var res: float = hg["res"]
	var ix := int(clampf(floor((x - hg["x0"]) / res), 0, hn - 1))
	var iz := int(clampf(floor((z - hg["z0"]) / res), 0, hn - 1))
	return (hg["h"] as PackedFloat32Array)[iz * hn + ix]


## ==================== 可破坏建筑 ====================
class Destructible extends RefCounted:
	var kind := "shed"
	var group: Node3D = null
	var collider: AABB
	var pos := Vector3.ZERO
	var hp := 200.0
	var radius := 3.2
	var dead := false

	func damage(amount: float, _attacker) -> void:
		if dead:
			return
		hp -= amount
		if hp <= 0:
			destroy()

	func destroy() -> void:
		dead = true
		# 战役模式:爆破目标被摧毁 → 战役控制器计数
		var cm = G.get("campaign")
		if cm != null and cm.running:
			cm.on_destructible_destroyed(self)
		var ci := G.colliders.find(collider)
		if ci >= 0:
			G.colliders.remove_at(ci)
			WorldBuilder._mark_grid_dirty()
		# 原地化为残骸堆(简单静态碰撞体防穿模;60s 后淡出移除,避免永久堆积)
		var rubble_mat := WorldBuilder._std(Color.html("#2e241c"), 1.0)
		var wg := G.world_group
		var boxes := []
		var gh3: float = G.ground_h.call(pos.x, pos.z)
		var rubble_col := AABB(Vector3(pos.x - 0.7, gh3, pos.z - 0.7), Vector3(1.4, 0.5, 1.4))
		G.colliders.append(rubble_col)
		for i in 5:
			var rb := WorldBuilder._box(Utils.rand(0.8, 1.8), Utils.rand(0.3, 0.7), Utils.rand(0.6, 1.4), rubble_mat)
			rb.position = Vector3(pos.x + Utils.rand(-1.4, 1.4), G.ground_h.call(pos.x, pos.z) + Utils.rand(0.15, 0.5),
				pos.z + Utils.rand(-1.4, 1.4))
			rb.rotation = Vector3(Utils.rand(-0.4, 0.4), Utils.rand(PI), Utils.rand(-0.4, 0.4))
			rb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(rb)
			boxes.append(rb)
		group.queue_free()
		G.effects.explosion(pos, 5)
		if kind == "barrel":
			# 油桶殉爆:真实爆炸伤害并可连锁引爆周围破坏物
			G.game.explode(pos, 3.5, 55, null)
		var t := wg.get_tree().create_timer(60.0)
		t.timeout.connect(func() -> void:
			for b2 in boxes:
				if is_instance_valid(b2):
					b2.queue_free()
			var cj := G.colliders.find(rubble_col)
			if cj >= 0:
				G.colliders.remove_at(cj)
				WorldBuilder._mark_grid_dirty()
		)


## ==================== 大型可进入机库(宽门 + 四壁 + 拱顶 + 复合碰撞) ====================
## rot 仅支持 0(门朝 -Z)或 PI(门朝 +Z),保证 AABB 碰撞轴对齐
static func build_hangar_enterable(wg: Node3D, x: float, z: float, rot: float, wall_mat: Material, roof_mat2: Material,
	add_collider: Callable, minimap_rects: Array) -> void:
	var W := 14.0
	var D := 11.0
	var H := 5.2
	var T := 0.3
	var DW := 5.0   # 大门宽
	var DH := 3.8   # 大门高
	var gh: float = G.ground_h.call(x, z)
	var g := Node3D.new()
	var mk := func(lx: float, ly: float, lz: float, w: float, h: float, d: float) -> void:
		var m := _box(w, h, d, wall_mat)
		m.position = Vector3(lx, ly, lz)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(m)
	# 后墙(+Z)与左右墙
	mk.call(0, H / 2, D / 2 - T / 2, W, H, T)
	mk.call(-W / 2 + T / 2, H / 2, 0, T, H, D)
	mk.call(W / 2 - T / 2, H / 2, 0, T, H, D)
	# 前墙(-Z):大门两侧 + 门楣
	var seg := (W - DW) / 2.0
	mk.call(-(DW + seg) / 2.0, H / 2, -D / 2 + T / 2, seg, H, T)
	mk.call((DW + seg) / 2.0, H / 2, -D / 2 + T / 2, seg, H, T)
	mk.call(0, DH + (H - DH) / 2, -D / 2 + T / 2, DW, H - DH, T)
	# 拱顶(缓坡两片) + 屋脊
	var roof1 := _box(W + 0.6, 0.22, D / 2 + 0.8, roof_mat2)
	roof1.rotation.x = 0.16
	roof1.position = Vector3(0, H + 0.55, -D / 4 + 0.2)
	roof1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(roof1)
	var roof2 := _box(W + 0.6, 0.22, D / 2 + 0.8, roof_mat2)
	roof2.rotation.x = -0.16
	roof2.position = Vector3(0, H + 0.55, D / 4 - 0.2)
	roof2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(roof2)
	# 库内氛围:工具台 + 木箱 + 油桶架
	var tb := _box(2.4, 0.85, 0.9, roof_mat2)
	tb.position = Vector3(-W / 2 + 1.8, 0.42, D / 2 - 1.4)
	tb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(tb)
	var c1 := _box(1.0, 1.0, 1.0, wall_mat)
	c1.position = Vector3(W / 2 - 1.5, 0.5, D / 2 - 1.6)
	c1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(c1)
	var c2 := _box(0.8, 0.8, 0.8, wall_mat)
	c2.position = Vector3(W / 2 - 2.6, 0.4, D / 2 - 1.2)
	c2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(c2)
	g.rotation.y = rot
	g.position = Vector3(x, gh, z)
	wg.add_child(g)
	# 复合碰撞(rot ∈ {0, PI}:局部→世界 = sgn 翻转)
	var sgn := 1.0 if rot == 0.0 else -1.0
	add_collider.call(x + 0, 0, z + sgn * (D / 2 - T / 2), W, H, T)
	add_collider.call(x + sgn * (-W / 2 + T / 2), 0, z, T, H, D)
	add_collider.call(x + sgn * (W / 2 - T / 2), 0, z, T, H, D)
	add_collider.call(x + sgn * (-(DW + seg) / 2.0), 0, z + sgn * (-D / 2 + T / 2), seg, H, T)
	add_collider.call(x + sgn * ((DW + seg) / 2.0), 0, z + sgn * (-D / 2 + T / 2), seg, H, T)
	add_collider.call(x + 0, DH, z + sgn * (-D / 2 + T / 2), DW, H - DH, T)  # 门楣
	minimap_rects.append({ "x": x, "z": z, "w": W, "d": D })


## ==================== 可进入建筑(门口 + 四壁 + 屋顶 + 复合碰撞) ====================
## rot 仅支持 0(门朝 -Z)或 PI(门朝 +Z),保证 AABB 碰撞轴对齐
static func build_enterable(wg: Node3D, x: float, z: float, rot: float, wall_mat: Material, roof_mat2: Material,
	add_collider: Callable, minimap_rects: Array) -> void:
	var W := 6.4
	var D := 5.2
	var H := 3.0
	var T := 0.26
	var DW := 1.5
	var DH := 2.25
	var gh: float = G.ground_h.call(x, z)
	var g := Node3D.new()
	var mk := func(lx: float, ly: float, lz: float, w: float, h: float, d: float) -> void:
		var m := _box(w, h, d, wall_mat)
		m.position = Vector3(lx, ly, lz)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(m)
	# 后墙(+Z)与左右墙
	mk.call(0, H / 2, D / 2 - T / 2, W, H, T)
	mk.call(-W / 2 + T / 2, H / 2, 0, T, H, D)
	mk.call(W / 2 - T / 2, H / 2, 0, T, H, D)
	# 前墙(-Z):门两侧 + 门楣
	var seg := (W - DW) / 2.0
	mk.call(-(DW + seg) / 2.0, H / 2, -D / 2 + T / 2, seg, H, T)
	mk.call((DW + seg) / 2.0, H / 2, -D / 2 + T / 2, seg, H, T)
	mk.call(0, DH + (H - DH) / 2, -D / 2 + T / 2, DW, H - DH, T)
	# 屋顶
	var roof := _box(W + 0.5, 0.22, D + 0.5, roof_mat2)
	roof.position = Vector3(0, H + 0.11, 0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(roof)
	# 室内氛围:弹药箱 + 长凳 + 木桌
	var c1 := _box(0.8, 0.8, 0.8, wall_mat)
	c1.position = Vector3(-W / 2 + 0.95, 0.4, D / 2 - 0.95)
	c1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(c1)
	var bench := _box(2.0, 0.42, 0.5, roof_mat2)
	bench.position = Vector3(W / 2 - 1.5, 0.21, 0.4)
	bench.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(bench)
	var table := _box(1.4, 0.75, 0.9, roof_mat2)
	table.position = Vector3(-0.5, 0.375, D / 2 - 1.1)
	table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(table)
	g.rotation.y = rot
	g.position = Vector3(x, gh, z)
	wg.add_child(g)
	# 复合碰撞(rot ∈ {0, PI}:局部→世界 = sgn 翻转)
	var sgn := 1.0 if rot == 0.0 else -1.0
	add_collider.call(x + 0, 0, z + sgn * (D / 2 - T / 2), W, H, T)
	add_collider.call(x + sgn * (-W / 2 + T / 2), 0, z, T, H, D)
	add_collider.call(x + sgn * (W / 2 - T / 2), 0, z, T, H, D)
	add_collider.call(x + sgn * (-(DW + seg) / 2.0), 0, z + sgn * (-D / 2 + T / 2), seg, H, T)
	add_collider.call(x + sgn * ((DW + seg) / 2.0), 0, z + sgn * (-D / 2 + T / 2), seg, H, T)
	add_collider.call(x + 0, DH, z + sgn * (-D / 2 + T / 2), DW, H - DH, T)  # 门楣(高于头顶,可直接走过)
	minimap_rects.append({ "x": x, "z": z, "w": W, "d": D })


## ==================== 世界销毁 ====================
static func dispose_world() -> void:
	if G.world_group != null and is_instance_valid(G.world_group):
		G.world_group.queue_free()
	G.world_group = null
	G.map_fx = {}


## ==================== 地图构建 ====================
static func build_world(root: Node3D, theme_id: String) -> void:
	dispose_world()
	# 地图 id 校验:无效时清空世界状态后安全返回(绝不访问 MapsData.M()[id],防世界构建中途中止)
	if not MapsData.M().has(theme_id):
		push_error("[WORLD] 无效地图 id: \"%s\",已中止世界构建(可用: %s)" % [theme_id, MapsData.M().keys()])
		G.current_map = ""
		G.map_night = false
		G.world_size = 0
		G.bounds = 0
		G.colliders = []
		G.flags = []
		G.spawns = { "us": [], "ru": [] }
		G.vehicle_spawns = []
		G.bt_spawns = null
		G.destructibles = []
		Utils.rebuild_collider_grid()  # 空网格重建:旧碰撞体索引全部失效
		return
	var T = MapsData.M()[theme_id]
	var size: float = T.size
	var road: float = T.road
	var is_bt: bool = T.mode == "breakthrough"
	G.current_map = theme_id
	G.map_night = T.night
	G.world_size = size / 2.0
	G.bounds = size / 2.0 - 10
	G.colliders = []
	G.flags = []
	G.spawns = { "us": [], "ru": [] }
	G.vehicle_spawns = []
	G.bt_spawns = null
	G.map_fx = {}
	G.destructibles = []
	var minimap_rects := []
	var wg := Node3D.new()
	wg.name = "WorldGroup"
	G.world_group = wg
	root.add_child(wg)

	# 地形高度场
	G.ground_h = make_bt_ground_h(T, size) if is_bt else make_ground_h(theme_id, size, road)

	var add_collider := func(x: float, y: float, z: float, w: float, h: float, d: float) -> AABB:
		var gh: float = G.ground_h.call(x, z)
		var b := AABB(Vector3(x - w / 2, gh + y, z - d / 2), Vector3(w, h, d))
		G.colliders.append(b)
		return b

	# ---------- 光照与环境(Sky3D 大气天空;每图时刻/雾色/ACES) ----------
	# 画质分级:世界生成参数按档位缩放(LOW..ULTRA)
	var lv: int = GraphicsQuality.current_level
	var web := OS.has_feature("web")
	var hi := lv >= GraphicsQuality.Level.HIGH
	var q_grid := [80, 104, 128, 144]        # 地形网格密度
	var q_sun_dist := [130.0, 180.0, 230.0, 270.0]  # 阴影距离(米)
	var q_stones := [40, 80, 130, 180]       # 地表碎石数
	var sky3d: WorldEnvironment = load("res://addons/sky_3d/src/Sky3D.gd").new()
	wg.add_child(sky3d)
	# 替换 main 里的占位 WorldEnvironment(旧的随世界组销毁)
	if G.world_env != null and is_instance_valid(G.world_env) and G.world_env != sky3d:
		G.world_env.queue_free()
	G.world_env = sky3d
	# 每图时刻(决定太阳角度与天色;暗夜雷达站为夜晚)
	var tod_time := { "city": 13.0, "desert": 15.2, "snow": 10.0, "bt_jungle": 12.2, "bt_harbor": 16.4, "bt_peak": 22.0 }
	sky3d.game_time_enabled = false
	sky3d.tod.current_time = tod_time.get(theme_id, 12.5)
	# 每图亮度系数表(修复全图过亮/雪地最严重;bt_peak 暗夜保持原值)
	var exp_k: float = { "city": 0.86, "desert": 0.8, "snow": 0.66, "bt_jungle": 0.82, "bt_harbor": 0.86, "bt_peak": 1.0 }.get(theme_id, 0.86)
	var sun_k: float = { "city": 0.9, "desert": 0.85, "snow": 0.7, "bt_jungle": 0.9, "bt_harbor": 0.9, "bt_peak": 1.0 }.get(theme_id, 0.9)
	sky3d.fog_enabled = false          # 关闭天空着色器雾,统一用游戏深度/指数雾
	sky3d.tonemap_exposure = 0.9
	sky3d.sky.sun_light_energy = T.sun_energy * sun_k          # 太阳能量对齐原主题(×每图系数收敛过亮)
	# 夜间图提亮(暗夜雷达站过黑):提高环境光与曝光
	sky3d.ambient_energy = 0.62 if T.night else maxf(0.35, T.hemi_energy * 0.32)
	sky3d.moon.shadow_enabled = false  # 月光不投影(省一份阴影开销)
	# ---- Sky3D 最佳品质参数(高分辨率云 / 大气散射 / 风) ----
	var sky_cfg := {
		"city": { "cov": 0.55, "cloud": 0.72, "wind": 0.9 },
		"desert": { "cov": 0.32, "cloud": 0.5, "wind": 0.8 },
		"snow": { "cov": 0.66, "cloud": 0.78, "wind": 1.4 },
		"bt_jungle": { "cov": 0.5, "cloud": 0.66, "wind": 0.9 },
		"bt_harbor": { "cov": 0.55, "cloud": 0.75, "wind": 1.1 },
		"bt_peak": { "cov": 0.42, "cloud": 0.3, "wind": 1.6 },
	}
	var sc: Dictionary = sky_cfg.get(theme_id, sky_cfg["city"])
	var sk = sky3d.sky
	sk.exposure = 0.9
	sk.atm_sun_intensity = 16.0
	sk.atm_darkness = 0.42
	sk.atm_thickness = 0.8
	sk.atm_turbidity = 0.002
	sk.atm_mie = 0.09
	sk.cumulus_visible = true
	sk.cirrus_visible = true
	sk.cumulus_noise_freq = 3.8
	sk.cumulus_size = 0.42
	sk.cumulus_coverage = sc["cov"]
	sk.cumulus_intensity = sc["cloud"]
	sk.cirrus_intensity = 1.6
	sk.wind_speed = sc["wind"]
	# 环境:指数雾 + 体积雾 / SSAO / ACES 电影级(Sky3D environment 原地修改,天穹照常渲染)
	var env := sky3d.environment
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = (1.18 if T.night else 0.9) * exp_k
	env.tonemap_white = 1.0          # Sky3D 默认 6 会压暗中灰,回到原值
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL   # 指数雾(距离连续,大气感)
	if theme_id == "city":
		# 城市地图去雾:城市不应有浓雾,远处保持清晰;其余地图雾效完全不变
		env.fog_enabled = false
	env.fog_light_color = T.fog_color
	env.fog_light_energy = 0.5
	env.fog_density = 2.6 / (T.fog_far * maxf(G.settings.fog, 0.1))
	env.fog_sun_scatter = 0.35        # 阳光在雾中的散射(体积感光柱)
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25        # 雾色向天空过渡,天地一色
	env.fog_depth_begin = T.fog_near * G.settings.fog   # 兼容深度雾回退
	env.fog_depth_end = T.fog_far * G.settings.fog
	G.fog_base = [T.fog_near, T.fog_far]
	G.map_fx["fog_density_base"] = 2.6 / T.fog_far      # update_map 跟随雾距设置
	# 体积雾(默认 HIGH+ 开启;Web/低画质自动关闭,性能回退;城市去雾强制关闭)
	var vfog := hi and not web and theme_id != "city"
	env.volumetric_fog_enabled = vfog
	if vfog:
		var fcol: Color = T.fog_color
		fcol.a = 1.0
		env.volumetric_fog_density = 0.03 if T.night else 0.018
		env.volumetric_fog_albedo = fcol
		env.volumetric_fog_emission = Color(0, 0, 0, 1)
		env.volumetric_fog_emission_energy = 0.0
		env.volumetric_fog_ambient_inject = 0.04
		env.volumetric_fog_sky_affect = 0.4
		env.volumetric_fog_length = 170.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_temporal_reprojection_enabled = true
		env.volumetric_fog_temporal_reprojection_amount = 0.6
	print("[FOG] map=", theme_id, " fog_enabled=", env.fog_enabled, " fog_mode=", env.fog_mode, " vfog=", env.volumetric_fog_enabled)
	env.ssao_enabled = G.settings.ssao
	env.ssao_radius = 0.55
	env.ssao_intensity = 2.2
	if hi:
		env.ssao_detail = 1.3
		env.ssao_sharpness = 0.9
	# 太阳(Sky3D SunLight,套用游戏阴影参数;高质量开启级联平滑过渡)
	G.sun = sky3d.sun
	G.sun_dir = -sky3d.sun.global_transform.basis.z
	sky3d.sun.shadow_enabled = G.settings.shadows > 0
	sky3d.sun.shadow_bias = 0.1
	sky3d.sun.shadow_normal_bias = 1.0
	sky3d.sun.directional_shadow_max_distance = q_sun_dist[lv]
	sky3d.sun.directional_shadow_split_1 = 0.15
	sky3d.sun.directional_shadow_split_2 = 0.4
	sky3d.sun.directional_shadow_split_3 = 0.7
	sky3d.sun.directional_shadow_blend_splits = hi
	sky3d.sun.shadow_blur = 0.6 if hi else 0.0
	# 天空反向补光(照亮楼影/背光面,不投影)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color.html("#c8d8e8")
	fill.light_energy = 0.12 if T.night else 0.34
	fill.rotation = sky3d.sun.rotation + Vector3(PI * 0.55, PI, 0)
	wg.add_child(fill)

	# ---------- 地面(起伏地形网格;预计算高度 + 解析法线) ----------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gn: int = q_grid[lv] + (10 if is_bt else 0)
	# 1) 预计算全部网格点高度
	var heights := []
	heights.resize(gn + 1)
	for i in gn + 1:
		var row := PackedFloat32Array()
		row.resize(gn + 1)
		heights[i] = row
	for j in gn + 1:
		for i in gn + 1:
			var x: float = -size / 2 + size * i / gn
			var gz: float = -size / 2 + size * j / gn
			(heights[i] as PackedFloat32Array)[j] = G.ground_h.call(x, gz)
	# 2) 网格点解析法线(中心差分)
	var pt_normal := func(i: int, j: int) -> Vector3:
		var im: int = maxi(i - 1, 0)
		var ip: int = mini(i + 1, gn)
		var jm: int = maxi(j - 1, 0)
		var jp: int = mini(j + 1, gn)
		var cell: float = size / gn
		var dhdx: float = ((heights[ip] as PackedFloat32Array)[j] - (heights[im] as PackedFloat32Array)[j]) / ((ip - im) * cell)
		var dhdz: float = ((heights[i] as PackedFloat32Array)[jp] - (heights[i] as PackedFloat32Array)[jm]) / ((jp - jm) * cell)
		return Vector3(-dhdx, 1, -dhdz).normalized()
	var pt := func(i: int, j: int) -> Vector3:
		return Vector3(-size / 2 + size * i / gn, (heights[i] as PackedFloat32Array)[j], -size / 2 + size * j / gn)
	# 3) 生成三角形(Godot 从 +Y 看为正面)
	for j in gn:
		for i in gn:
			var uv00 := Vector2(float(i) / gn, float(j) / gn)
			var uv10 := Vector2(float(i + 1) / gn, float(j) / gn)
			var uv01 := Vector2(float(i) / gn, float(j + 1) / gn)
			var uv11 := Vector2(float(i + 1) / gn, float(j + 1) / gn)
			var n00: Vector3 = pt_normal.call(i, j)
			var n10: Vector3 = pt_normal.call(i + 1, j)
			var n01: Vector3 = pt_normal.call(i, j + 1)
			var n11: Vector3 = pt_normal.call(i + 1, j + 1)
			# 三角形 1: (a, b, c)
			st.set_normal(n00); st.set_uv(uv00); st.add_vertex(pt.call(i, j))
			st.set_normal(n10); st.set_uv(uv10); st.add_vertex(pt.call(i + 1, j))
			st.set_normal(n01); st.set_uv(uv01); st.add_vertex(pt.call(i, j + 1))
			# 三角形 2: (b, d, c)
			st.set_normal(n10); st.set_uv(uv10); st.add_vertex(pt.call(i + 1, j))
			st.set_normal(n11); st.set_uv(uv11); st.add_vertex(pt.call(i + 1, j + 1))
			st.set_normal(n01); st.set_uv(uv01); st.add_vertex(pt.call(i, j + 1))
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	# 3A 地面:多层纹理混合(路线图底层 + 岩层/沙雪/混凝土细节层 + 宏观噪声)
	ground.material_override = TerrainTextures.make_ground_material(theme_id, T)
	wg.add_child(ground)

	# 突破地图水体(3A 水面:折射 + 天空反射 + 波动法线;水面略高于平地形成浅滩)
	if is_bt and T.river != null:
		var water := MeshInstance3D.new()
		var wpm := PlaneMesh.new()
		wpm.size = Vector2(size, 22)
		wpm.subdivide_width = 48
		wpm.subdivide_depth = 3
		water.mesh = wpm
		water.material_override = TerrainTextures.make_water_material(
			Color.html("#1d4a45"), Color.html("#2e6a5c"), 0.16, 0.9)
		water.position = Vector3(0, 0.2, T.river)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(water)
	if is_bt and T.sea:
		# 两侧海面各一片(避开可玩区域,海岸线位于 |x| = 104)
		for side in [-1.0, 1.0]:
			var sea := MeshInstance3D.new()
			var spm := PlaneMesh.new()
			spm.size = Vector2(1500, 1500)
			spm.subdivide_width = 72
			spm.subdivide_depth = 72
			sea.mesh = spm
			sea.material_override = TerrainTextures.make_water_material(
				Color.html("#14314a"), Color.html("#1d4a63"), 0.14, 0.7)
			sea.position = Vector3(side * 854.0, 0.35, 0)
			sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wg.add_child(sea)

	# ---------- 共享材质 ----------
	var crate_mat := _std_tex(Color.WHITE, 0.85, "plywood")
	var conc_mat := _std_tex(Color.WHITE, 0.95, "rough_concrete")
	var rock_photo_mat := _std_tex(Color.WHITE, 1.0, "rock_04")
	var sand_mat := _std(Color.html("#9a8a68"), 1.0)
	var roof_mat := _std(Color.html("#3a3c40"), 0.95)
	var cont_mats := [
		_std_tex(Color.html("#8aa0c0"), 0.6, "metal_plate", 0.4),
		_std_tex(Color.html("#c09080"), 0.6, "metal_plate", 0.4),
		_std_tex(Color.html("#90b090"), 0.6, "metal_plate", 0.4),
	]

	# 静态道具批量绘制(3A:木箱/油桶/沙袋/货箱合并 MultiMesh,1 材质 1 次绘制)
	var m_box1 := BoxMesh.new()
	m_box1.size = Vector3(1, 1, 1)
	var m_barrel_mesh := CylinderMesh.new()
	m_barrel_mesh.top_radius = 0.35
	m_barrel_mesh.bottom_radius = 0.35
	m_barrel_mesh.height = 0.95
	m_barrel_mesh.radial_segments = 10
	var mm_buf := {}
	var mm_push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = mm_buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			mm_buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))

	var crate := func(x: float, z: float, s := 1.3) -> void:
		mm_push.call(crate_mat, m_box1, x, z, 0.0, s * 0.5, Vector3(s, s, s))
		add_collider.call(x, 0, z, s, s, s)

	var barrier := func(x: float, z: float, rot := 0.0) -> void:
		var m := _box(2.4, 0.9, 0.5, conc_mat)
		m.rotation.y = rot
		m.position = Vector3(x, G.ground_h.call(x, z) + 0.45, z)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(m)
		var ww := 2.4 if absf(cos(rot)) > 0.5 else 0.5
		add_collider.call(x, 0, z, ww, 0.9, 0.5 if ww == 2.4 else 2.4)

	var sandbag := func(x: float, z: float, rot := 0.0, sb_len := 3.0) -> void:
		mm_push.call(sand_mat, m_box1, x, z, rot, 0.5, Vector3(sb_len, 1.0, 0.7))
		var ww := sb_len if absf(cos(rot)) > 0.5 else 0.7
		add_collider.call(x, 0, z, ww, 1.0, 0.7 if ww == sb_len else sb_len)

	var container := func(x: float, z: float, rot := 0.0) -> void:
		mm_push.call(Utils.choice(cont_mats), m_box1, x, z, rot, 1.35, Vector3(6.2, 2.7, 2.5))
		var ww := 6.2 if absf(cos(rot)) > 0.5 else 2.5
		add_collider.call(x, 0, z, ww, 2.7, 2.5 if ww == 6.2 else 6.2)
		minimap_rects.append({ "x": x, "z": z, "w": ww, "d": 2.5 if ww == 6.2 else 6.2 })

	var barrel := func(x: float, z: float) -> void:
		mm_push.call(cont_mats[0], m_barrel_mesh, x, z, 0.0, 0.475, Vector3.ONE)
		add_collider.call(x, 0, z, 0.7, 0.95, 0.7)

	var car := func(x: float, z: float, rot := 0.0, col_override = null) -> void:
		var g := Node3D.new()
		var col: Color = col_override if col_override != null else Utils.choice(
			[Color.html("#5a6a7a"), Color.html("#7a5a4a"), Color.html("#4a5a4a"), Color.html("#6a6a6a"), Color.html("#8a7a3a")])
		var body_mat := _std(col, 0.5, 0.6)
		var body := _box(4.2, 0.85, 1.9, body_mat)
		body.position.y = 0.65
		g.add_child(body)
		var cab := _box(2.2, 0.7, 1.7, _std(Color.html("#1a2028"), 0.2, 0.8))
		cab.position = Vector3(-0.2, 1.35, 0)
		g.add_child(cab)
		var wheel_mat := _std(Color.html("#14161a"), 0.9)
		for wp in [[-1.4, 0.95], [1.4, 0.95], [-1.4, -0.95], [1.4, -0.95]]:
			var w := _cyl(0.36, 0.36, 0.3, 10, wheel_mat)
			w.rotation.x = PI / 2.0
			w.position = Vector3(wp[0], 0.36, wp[1])
			g.add_child(w)
		g.rotation.y = rot
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		var ww := 4.2 if absf(cos(rot)) > 0.5 else 1.9
		add_collider.call(x, 0, z, ww, 1.7, 1.9 if ww == 4.2 else 4.2)

	# ---------- 可破坏建筑 ----------
	var shed_wood := _std_tex(Color.html("#8a6f4e"), 0.95, "plywood")
	# 小型可破坏物:油桶(殉爆连锁)/木箱
	var destructible_prop := func(x: float, z: float, kind: String) -> void:
		var gh2: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		var ds := Destructible.new()
		var col2: AABB
		if kind == "barrel":
			var b := _cyl(0.34, 0.34, 0.92, 12, _std(Color.html("#7a3a1e"), 0.5, 0.6))
			b.position.y = 0.46
			g.add_child(b)
			var band := _cyl(0.355, 0.355, 0.12, 12, _std(Color.html("#3a3d42"), 0.4, 0.7))
			band.position.y = 0.62
			g.add_child(band)
			col2 = add_collider.call(x, 0, z, 0.68, 0.92, 0.68)
			ds.hp = 40
			ds.pos = Vector3(x, gh2 + 0.46, z)
			ds.radius = 0.85
		else:
			var c := _box(0.85, 0.85, 0.85, shed_wood)
			c.position.y = 0.425
			c.rotation.y = Utils.rand(PI)
			g.add_child(c)
			col2 = add_collider.call(x, 0, z, 0.85, 0.85, 0.85)
			ds.hp = 30
			ds.pos = Vector3(x, gh2 + 0.425, z)
			ds.radius = 0.8
		ds.kind = kind
		ds.group = g
		ds.collider = col2
		g.position = Vector3(x, gh2, z)
		_shadows_on(g)
		wg.add_child(g)
		G.destructibles.append(ds)

	var destructible := func(x: float, z: float, rot := 0.0, kind := "shed") -> void:
		var gh: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		if kind == "shed":
			var b := _box(3.4, 2.2, 2.6, shed_wood)
			b.position.y = 1.1
			g.add_child(b)
			var rf := _box(3.8, 0.24, 3.0, roof_mat)
			rf.position.y = 2.3
			g.add_child(rf)
		else:
			for lp in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				var leg := _box(0.22, 2.4, 0.22, shed_wood)
				leg.position = Vector3(lp[0], 1.2, lp[1])
				g.add_child(leg)
			var cab := _box(2.6, 1.8, 2.6, shed_wood)
			cab.position.y = 3.2
			g.add_child(cab)
			var rf := _cone(2.2, 1.0, 4, roof_mat)
			rf.position.y = 4.6
			rf.rotation.y = PI / 4.0
			g.add_child(rf)
		g.rotation.y = rot
		g.position = Vector3(x, gh, z)
		_shadows_on(g)
		wg.add_child(g)
		var w := 3.4 if kind == "shed" else 2.6
		var d := 2.6
		var h := 2.4 if kind == "shed" else 4.6
		var cs := absf(cos(rot)) > 0.5
		var collider: AABB = add_collider.call(x, 0, z, w if cs else d, h, d if cs else w)
		minimap_rects.append({ "x": x, "z": z, "w": w if cs else d, "d": d if cs else w })
		var ds := Destructible.new()
		ds.kind = kind
		ds.group = g
		ds.collider = collider
		ds.pos = Vector3(x, gh + 1.2, z)
		ds.hp = 200 if kind == "shed" else 260
		G.destructibles.append(ds)

	# ---------- 主题建筑 ----------
	var near_obj := func(x: float, z: float, r := 20.0) -> bool:
		for sec in T.sectors:
			for o in sec:
				var dx: float = x - o["x"]
				var dz: float = z - o["z"]
				if sqrt(dx * dx + dz * dz) < r:
					return true
		return false

	if theme_id == "city":
		_city_blocks(T, wg, add_collider, minimap_rects, car, container, crate, barrel, barrier, road)
	elif theme_id == "desert":
		_desert_blocks(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, car, container, rock_photo_mat)
	elif theme_id == "snow":
		_snow_blocks(T, wg, add_collider, minimap_rects, crate, sandbag, container, barrier, rock_photo_mat)
	elif theme_id == "bt_jungle":
		_jungle_blocks(T, wg, add_collider, minimap_rects, crate, barrel, near_obj, rock_photo_mat)
	elif theme_id == "bt_harbor":
		_harbor_blocks(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, car, barrier, container, cont_mats, near_obj, roof_mat)
	elif theme_id == "bt_peak":
		_peak_blocks(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, barrier, container, near_obj, rock_photo_mat, roof_mat)

	# ---------- 可进入建筑(混凝土哨所;各图按特点加密) ----------
	var ent_wall := _std_tex(Color.html("#9a948a"), 0.95, "rough_concrete")
	if is_bt:
		# 突破:第一/第二区域之间的走廊旁 + 翼侧增援
		var mid_z: float = (T.sectors[0][0]["z"] + T.sectors[min(1, T.sectors.size() - 1)][0]["z"]) / 2.0
		build_enterable(wg, 14, mid_z, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, -20, T.sectors[0][0]["z"] + 22, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		if T.sectors.size() > 2:
			build_enterable(wg, -16, T.sectors[2][0]["z"] + 20, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		# 大型机库式可进入建筑(码头/雷达站仓储)
		if theme_id == "bt_harbor":
			build_hangar_enterable(wg, -20, T.sectors[1][0]["z"] + 20, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		elif theme_id == "bt_peak":
			build_hangar_enterable(wg, 20, T.sectors[0][0]["z"] + 24, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		elif theme_id == "bt_jungle":
			build_enterable(wg, 20, T.sectors[1][0]["z"] - 18, PI, ent_wall, roof_mat, add_collider, minimap_rects)
	else:
		# 征服:中央旗点南北各一座(错开旗帜)
		build_enterable(wg, 12, -road * 0.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, -12, road * 0.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		if theme_id == "city":
			# 巷战:区块间小巷加密可进入建筑(形成迂回巷战网)
			build_enterable(wg, road * 0.5, -road * 1.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
			build_enterable(wg, -road * 1.5, road * 0.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
			build_enterable(wg, road * 1.5, road * 0.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
			build_enterable(wg, -road * 0.5, road * 1.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
			build_enterable(wg, road * 1.5, -road * 0.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		elif theme_id == "snow":
			# 雪山:翼侧哨所加密
			build_enterable(wg, road * 0.5, -road * 1.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
			build_enterable(wg, -road * 0.5, road * 1.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		elif theme_id == "desert":
			# 沙漠机场:跑道 + 双机库(可进入) + 塔台 + 停机坪飞机
			_desert_airport(wg, add_collider, minimap_rects, ent_wall, roof_mat)

	# 战场氛围
	if is_bt:
		_bt_battle_dressing(T, wg, add_collider, size, sandbag, crate)
	else:
		_battlefield_dressing(wg, add_collider, size, road)

	# 可破坏建筑布置
	var pts := []
	if is_bt:
		for sec in T.sectors:
			for o in sec:
				pts.append(o)
	else:
		for p in [[-road, -road], [road, -road], [0.0, 0.0], [-road, road], [road, road]]:
			pts.append({ "x": p[0], "z": p[1] })
	for p in pts:
		if randf() < (0.55 if is_bt else 0.65) and absf(p["z"]) < size / 2 - 18:
			destructible.call(p["x"] + Utils.rand(-18, -13),
				clampf(p["z"] + Utils.rand(-16, 16), -size / 2 + 18, size / 2 - 18),
				Utils.rand(PI), "shed" if randf() < 0.6 else "tower")
		if randf() < (0.45 if is_bt else 0.5) and absf(p["z"]) < size / 2 - 18:
			destructible.call(p["x"] + Utils.rand(13, 18),
				clampf(p["z"] + Utils.rand(-16, 16), -size / 2 + 18, size / 2 - 18),
				Utils.rand(PI), "shed")
		# 小型可破坏物:旗帜周围油桶(可殉爆)与木箱
		for k in 3:
			if randf() < 0.75:
				destructible_prop.call(p["x"] + Utils.rand(-12, 12),
					clampf(p["z"] + Utils.rand(-12, 12), -size / 2 + 14, size / 2 - 14),
					"barrel" if randf() < 0.55 else "crate")
	# 全图随机散布油桶/木箱(战争氛围)
	for k in int(size / 6):
		destructible_prop.call(Utils.rand(-size / 2 + 12, size / 2 - 12),
			Utils.rand(-size / 2 + 12, size / 2 - 12), "barrel" if randf() < 0.5 else "crate")

	# ---------- 旗帜 ----------
	if is_bt:
		for si in T.sectors.size():
			for o in T.sectors[si]:
				var f := Flag.new(o["id"], o["x"], o["z"])
				f.sector = si
				f.position.y = G.ground_h.call(o["x"], o["z"])
				f.pos.y = G.ground_h.call(o["x"], o["z"])
				wg.add_child(f)
				G.flags.append(f)
				sandbag.call(o["x"] - 6, o["z"] - 4, 0.3)
				sandbag.call(o["x"] + 5, o["z"] + 5, -0.5)
				sandbag.call(o["x"] + 6, o["z"] - 5, 1.8)
				sandbag.call(o["x"] - 5, o["z"] + 6, 1.2)
				crate.call(o["x"] - 9, o["z"] + 2)
				crate.call(o["x"] + 9, o["z"] - 3)
				barrier.call(o["x"] - 3, o["z"] - 9, 0.2)
				barrier.call(o["x"] + 4, o["z"] + 9, -0.3)
	else:
		var flag_defs := [["A", -road, -road], ["B", road, -road], ["C", 0.0, 0.0], ["D", -road, road], ["E", road, road]]
		for fd in flag_defs:
			var f := Flag.new(fd[0], fd[1], fd[2])
			f.position.y = G.ground_h.call(fd[1], fd[2])
			f.pos.y = G.ground_h.call(fd[1], fd[2])
			wg.add_child(f)
			G.flags.append(f)
			sandbag.call(fd[1] - 6, fd[2] - 4, 0.3)
			sandbag.call(fd[1] + 5, fd[2] + 5, -0.5)
			sandbag.call(fd[1] + 6, fd[2] - 5, 1.8)
			sandbag.call(fd[1] - 5, fd[2] + 6, 1.2)
			crate.call(fd[1] - 9, fd[2] + 2)
			crate.call(fd[1] + 9, fd[2] - 3)
			crate.call(fd[1] + 2, fd[2] + 9, 1.1)
			barrier.call(fd[1] - 3, fd[2] - 9, 0.2)
			barrier.call(fd[1] + 4, fd[2] + 9, -0.3)

	# 战役模式:旗帜仅保留注册(占点判定/AI 逻辑),隐藏旗杆/旗面/标牌/占领圈视觉
	if G.mode == "campaign":
		for f in G.flags:
			f.hide_visuals()

	# ---------- 边界墙(碰撞体先注册,贴墙带草地/碎石自动避让,避免嵌入墙内) ----------
	var B: float = G.bounds + 4
	add_collider.call(0, 0, -B, 2 * B + 8, 20, 2)
	add_collider.call(0, 0, B, 2 * B + 8, 20, 2)
	add_collider.call(-B, 0, 0, 2, 20, 2 * B + 8)
	add_collider.call(B, 0, 0, 2, 20, 2 * B + 8)
	var wall_mat := _std(Color.html("#a89060") if theme_id == "desert" else Color.html("#5a5c60"), 0.95)
	for wd in [[0, -B, 2 * B, 1.5], [0, B, 2 * B, 1.5], [-B, 0, 1.5, 2 * B], [B, 0, 1.5, 2 * B]]:
		var wall := _box(wd[2], 4, wd[3], wall_mat)
		wall.position = Vector3(wd[0], 2, wd[1])
		wg.add_child(wall)

	# ---------- 草地与地表细节(3A 植被/碎石;密度随画质档位) ----------
	_flush_prop_mm(wg, mm_buf)
	add_grass(wg, theme_id, is_bt, T, lv)
	_add_surface_stones(wg, int(q_stones[lv] * (0.5 if web else 1.0)), rock_photo_mat)

	# ---------- 出生点 ----------
	var sz := size / 2.0 - 16
	for i in 5:
		var ux := -12.0 + i * 6
		var uz := -sz + Utils.rand(-3, 3)
		G.spawns["us"].append(Vector3(ux, G.ground_h.call(ux, uz), uz))
		var rx := -12.0 + i * 6
		var rz := sz + Utils.rand(-3, 3)
		G.spawns["ru"].append(Vector3(rx, G.ground_h.call(rx, rz), rz))
	if is_bt:
		G.bt_spawns = { "att": [], "def": [] }
		for si in T.sectors.size():
			var mid_z = (T.sectors[si][0]["z"] + T.sectors[si][1]["z"]) / 2.0
			var att_z = -sz + 4 if si == 0 else mid_z - 56
			var def_z = sz - 4 if si == T.sectors.size() - 1 else mid_z + 34
			var att_arr := []
			var def_arr := []
			for k in 8:
				var ax := Utils.rand(-26, 26)
				var az = att_z + Utils.rand(-5, 5)
				att_arr.append(Vector3(ax, G.ground_h.call(ax, az), az))
				var dx2 := Utils.rand(-26, 26)
				var dz2 = def_z + Utils.rand(-5, 5)
				def_arr.append(Vector3(dx2, G.ground_h.call(dx2, dz2), dz2))
			G.bt_spawns["att"].append(att_arr)
			G.bt_spawns["def"].append(def_arr)

	# ---------- 载具出生点 ----------
	if is_bt:
		G.vehicle_spawns = [
			{ "x": 0, "z": -sz + 4, "yaw": PI, "type": "tank" },
			{ "x": -18, "z": -sz + 10, "yaw": PI + 0.2, "type": "apc" },
			{ "x": 18, "z": -sz + 10, "yaw": PI - 0.3, "type": "apc" },
			{ "x": -32, "z": -sz + 12, "yaw": PI + 0.1, "type": "aa" },
			{ "x": -8, "z": -sz + 8, "yaw": PI, "type": "jeep" },
			{ "x": 10, "z": -sz + 8, "yaw": PI - 0.3, "type": "jeep" },
			{ "x": 0, "z": sz - 4, "yaw": 0, "type": "tank" },
			{ "x": -16, "z": sz - 10, "yaw": -0.2, "type": "apc" },
			{ "x": 16, "z": sz - 10, "yaw": 0.3, "type": "aa" },
			{ "x": 8, "z": sz - 8, "yaw": 0.1, "type": "jeep" },
		]
	else:
		G.vehicle_spawns = [
			{ "x": 0, "z": -sz + 4, "yaw": PI, "type": "tank" },
			{ "x": -18, "z": -sz + 10, "yaw": PI + 0.2, "type": "apc" },
			{ "x": 18, "z": -sz + 10, "yaw": PI - 0.3, "type": "aa" },
			{ "x": -10, "z": -sz + 8, "yaw": PI, "type": "jeep" },
			{ "x": 10, "z": -sz + 8, "yaw": PI - 0.3, "type": "jeep" },
			{ "x": 0, "z": sz - 4, "yaw": 0, "type": "tank" },
			{ "x": -18, "z": sz - 10, "yaw": -0.2, "type": "apc" },
			{ "x": 18, "z": sz - 10, "yaw": 0.3, "type": "aa" },
			{ "x": -10, "z": sz - 8, "yaw": 0, "type": "jeep" },
			{ "x": 10, "z": sz - 8, "yaw": 0.3, "type": "jeep" },
			{ "x": 14, "z": 14, "yaw": Utils.rand(TAU), "type": "jeep" },
		]

	# ---------- 出生点 ----------
	G.minimap_rects = minimap_rects
	# 碰撞体空间网格(射线检测加速:AI 视线/弹道/避障)
	Utils.rebuild_collider_grid()


## ==================== 战场氛围(废墟堆 / 反坦克拒马 / 烟柱) ====================
static func _battlefield_dressing(wg: Node3D, add_collider: Callable, size: float, road: float) -> void:
	var rubble_mat := _std_tex(Color.html("#9a9a9a"), 1.0, "rough_concrete")
	var hedge_mat := _std_tex(Color.html("#6a5a4a"), 0.7, "metal_plate", 0.5)
	var burnt_mat := _std(Color.html("#1e1c1a"), 1.0)
	var rubble := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for i in 4:
			var r := _ico(Utils.rand(0.2, 0.55), rubble_mat)
			r.position = Vector3(Utils.rand(-0.8, 0.8), Utils.rand(0.1, 0.35), Utils.rand(-0.8, 0.8))
			r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
			g.add_child(r)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.4, 0.6, 1.4)
	var hedgehog := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for i in 3:
			var beam := _box(0.14, 2.1, 0.14, hedge_mat)
			beam.rotation = Vector3(Utils.rand(-0.7, 0.7), Utils.rand(0, PI), Utils.rand(-0.7, 0.7))
			beam.position.y = 0.7
			g.add_child(beam)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.2, 1.4, 1.2)
	var burnt_wreck := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var body := _box(Utils.rand(2.5, 3.5), Utils.rand(0.8, 1.2), Utils.rand(1.4, 1.8), burnt_mat)
		body.position.y = 0.55
		body.rotation.y = Utils.rand(PI)
		g.add_child(body)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 3, 1.3, 1.8)
	for i in 30:
		var on_vertical := randf() < 0.5
		var r: float = Utils.choice([-road, 0.0, road]) + Utils.rand(-6, 6)
		var p := Utils.rand(-size / 2 + 15, size / 2 - 15)
		var roll := randf()
		var fn: Callable = rubble if roll < 0.45 else (hedgehog if roll < 0.75 else burnt_wreck)
		if on_vertical:
			fn.call(p, r)
		else:
			fn.call(r, p)
	G.map_fx["smokes"] = []
	var smoke_n: int = [4, 6, 8, 10][GraphicsQuality.current_level]
	for i in smoke_n:
		G.map_fx["smokes"].append({
			"x": Utils.rand(-size / 2 + 25, size / 2 - 25),
			"z": Utils.rand(-size / 2 + 25, size / 2 - 25),
			"t": Utils.rand(0.2),
		})


## ==================== 城市街区 ====================
static func _city_blocks(_T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		car: Callable, container: Callable, crate: Callable, barrel: Callable, barrier: Callable, road: float) -> void:
	var facade_mats := []
	for fd in [["#8a8f98", 0.15], ["#9a8a78", 0.2], ["#7a8088", 0.1], ["#a4988a", 0.25]]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = TerrainTextures.facade_texture(fd[0], fd[1])
		m.roughness = 0.9
		facade_mats.append(m)
	var roof_mat := _std(Color.html("#3a3c40"), 0.95)
	var add_building := func(x: float, z: float, w: float, d: float, h: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var b := _box(w, h, d, Utils.choice(facade_mats))
		b.position = Vector3(x, gh + h / 2.0, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var roof := _box(w + 0.4, 0.5, d + 0.4, roof_mat)
		roof.position = Vector3(x, gh + h + 0.2, z)
		wg.add_child(roof)
		add_collider.call(x, 0, z, w, h, d)
		minimap_rects.append({ "x": x, "z": z, "w": w, "d": d })
	var B := road * 2 - 18
	var r7 := road + 7
	var edges := [-B, -r7, -road + 7, -7, 7, road - 7, r7, B]
	var i := 0
	while i < edges.size():
		var j := 0
		while j < edges.size():
			var cx: float = (edges[i] + edges[i + 1]) / 2.0
			var cz: float = (edges[j] + edges[j + 1]) / 2.0
			var bw: float = edges[i + 1] - edges[i]
			var bd: float = edges[j + 1] - edges[j]
			j += 2
			if bw < 30 or bd < 30:
				continue
			if randf() < 0.55:
				add_building.call(cx - bw / 4 + Utils.rand(-2, 2), cz + Utils.rand(-3, 3), Utils.rand(13, 17), Utils.rand(20, minf(28, bd - 6)), Utils.rand(10, 24))
				add_building.call(cx + bw / 4 + Utils.rand(-2, 2), cz + Utils.rand(-3, 3), Utils.rand(13, 17), Utils.rand(20, minf(28, bd - 6)), Utils.rand(14, 38))
			else:
				add_building.call(cx + Utils.rand(-3, 3), cz + Utils.rand(-3, 3), Utils.rand(20, minf(30, bw - 6)), Utils.rand(20, minf(30, bd - 6)), Utils.rand(14, 34))
		i += 2
	# 坠毁直升机地标
	var heli := Node3D.new()
	var h_mat := _std(Color.html("#3a4238"), 0.8, 0.3)
	var body := _box(6, 2.2, 2.4, h_mat)
	body.position.y = 1.1
	heli.add_child(body)
	var tail := _box(4.5, 0.7, 0.7, h_mat)
	tail.position = Vector3(5, 1.4, 0)
	tail.rotation.z = 0.15
	heli.add_child(tail)
	var rotor := _box(9, 0.08, 0.5, h_mat)
	rotor.position = Vector3(0, 2.5, 0)
	rotor.rotation.y = 0.6
	heli.add_child(rotor)
	var rotor2 := _box(9, 0.08, 0.5, h_mat)
	rotor2.position = Vector3(0, 2.5, 0)
	rotor2.rotation.y = 0.6 + PI / 2.0
	heli.add_child(rotor2)
	heli.position = Vector3(8, G.ground_h.call(8, -8), -8)
	heli.rotation.y = 0.7
	heli.rotation.z = 0.08
	_shadows_on(heli)
	wg.add_child(heli)
	add_collider.call(8, 0, -8, 6, 2.4, 3.5)
	minimap_rects.append({ "x": 8, "z": -8, "w": 6, "d": 3.5 })
	# 街道道具
	var R := road
	for k in 56:
		var roll := randi() % 6
		match roll:
			0: car.call(Utils.rand(-140, 140), Utils.choice([-R - 3, -R + 3, -3.0, 3.0, R - 3, R + 3]) + Utils.rand(-1, 1), Utils.rand(-0.2, 0.2))
			1: car.call(Utils.choice([-R - 3, -R + 3, -3.0, 3.0, R - 3, R + 3]) + Utils.rand(-1, 1), Utils.rand(-140, 140), PI / 2 + Utils.rand(-0.2, 0.2))
			2: container.call(Utils.rand(-140, 140), Utils.choice([-R, 0.0, R]) + Utils.rand(-5, 5), Utils.rand(PI))
			3: crate.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			4: barrel.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			5: barrier.call(Utils.rand(-140, 140), Utils.choice([-R, 0.0, R]) + Utils.rand(-5, 5), Utils.rand(PI))
	# 天际线
	var skyline_mat := _basic(Color.html("#6a7684"), true)
	for k in 26:
		var a := k / 26.0 * TAU + Utils.rand(-0.1, 0.1)
		var r := Utils.rand(190, 260)
		var h := Utils.rand(30, 90)
		var b := _box(Utils.rand(15, 30), h, Utils.rand(15, 30), skyline_mat)
		b.position = Vector3(cos(a) * r, h / 2 - 2, sin(a) * r)
		wg.add_child(b)
	# ---------- 战争沉浸感街道物件(路灯/垃圾桶/消防栓/邮箱/长椅/路障锥/烧毁车辆/弹壳) ----------
	var R2 := road
	var flag_pts := [[-R2, -R2], [R2, -R2], [0.0, 0.0], [-R2, R2], [R2, R2]]
	var near_flag3 := func(x: float, z: float, r: float) -> bool:
		for fp in flag_pts:
			var dx: float = x - fp[0]
			var dz: float = z - fp[1]
			if sqrt(dx * dx + dz * dz) < r:
				return true
		return false
	var clear_spot := func(x: float, z: float, margin: float) -> bool:
		for b in G.colliders:
			var bb: AABB = b
			var dx: float = maxf(absf(x - bb.get_center().x) - bb.size.x * 0.5, 0.0)
			var dz: float = maxf(absf(z - bb.get_center().z) - bb.size.z * 0.5, 0.0)
			if dx * dx + dz * dz < margin * margin:
				return false
		return true
	var on_road2 := func(x: float, z: float, w: float) -> bool:
		for r in [-R2, 0.0, R2]:
			if absf(x - r) < w or absf(z - r) < w:
				return true
		return false
	# 路灯(细杆 + 弯臂 + 暖白灯头;MultiMesh 批量 24 盏)
	var lamp_pole_mat := _std(Color.html("#2a2e33"), 0.7, 0.5)
	var lamp_head_mat2 := _basic(Color.html("#ffd9a0"), true)
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = 4.5
	pole_mesh.radial_segments = 6
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.05, 0.05, 0.65)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15
	head_mesh.height = 0.3
	head_mesh.radial_segments = 8
	head_mesh.rings = 6
	var buf := {}
	var push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	var lamp_at := func(px: float, pz: float, v: bool) -> void:
		var ox := -0.3 if v else 0.0
		var oz := 0.0 if v else -0.3
		push.call(lamp_pole_mat, pole_mesh, px, pz, 0.0, 2.25, Vector3.ONE)
		push.call(lamp_pole_mat, arm_mesh, px + ox, pz + oz, PI / 2.0 if v else 0.0, 4.5, Vector3.ONE)
		push.call(lamp_head_mat2, head_mesh, px + ox - 0.2, pz + oz - 0.2, 0.0, 4.52, Vector3.ONE)
	for lr in [-R2, 0.0, R2]:
		for lx in [-120.0, -40.0, 40.0, 120.0]:
			if near_flag3.call(lx, lr + 3.5, 25.0):
				continue
			lamp_at.call(lx, lr + 3.5, false)
	for lc in [-R2, 0.0, R2]:
		for lz in [-120.0, -40.0, 40.0, 120.0]:
			if near_flag3.call(lc + 3.5, lz, 25.0):
				continue
			lamp_at.call(lc + 3.5, lz, true)
	# 小件街道家具(MultiMesh:垃圾桶/消防栓/邮箱/长椅/路障锥,纯装饰无碰撞)
	var trash_mat := _std(Color.html("#2e4a2e"), 0.9)
	var hyd_mat := _std(Color.html("#b03028"), 0.6, 0.3)
	var mail_mat := _std(Color.html("#1e3a52"), 0.7)
	var bench_mat := _std(Color.html("#8a6a44"), 0.9)
	var cone_mat := _std(Color.html("#e07020"), 0.8)
	var tip_mat := _std(Color.html("#e8e8e0"), 0.6)
	var box_mesh_u := BoxMesh.new()
	box_mesh_u.size = Vector3.ONE
	var cyl_mesh_u := CylinderMesh.new()
	cyl_mesh_u.top_radius = 0.1
	cyl_mesh_u.bottom_radius = 0.1
	cyl_mesh_u.height = 1.0
	cyl_mesh_u.radial_segments = 8
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.22
	cone_mesh.height = 0.45
	cone_mesh.radial_segments = 8
	for k in 8:
		for t in 30:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 2.0):
				continue
			push.call(trash_mat, cyl_mesh_u, bx, bz, 0.0, 0.35, Vector3(2.8, 0.7, 2.8))
			push.call(trash_mat, cyl_mesh_u, bx, bz, 0.0, 0.76, Vector3(3.0, 0.1, 3.0))
			break
	for k in 3:
		for t in 30:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.2):
				continue
			push.call(hyd_mat, cyl_mesh_u, bx, bz, 0.0, 0.25, Vector3(1.6, 0.5, 1.6))
			push.call(hyd_mat, cyl_mesh_u, bx, bz, 0.0, 0.52, Vector3(1.9, 0.12, 1.9))
			break
	for k in 3:
		for t in 30:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.2):
				continue
			var mr := Utils.rand(-0.3, 0.3)
			push.call(mail_mat, box_mesh_u, bx, bz, mr, 0.42, Vector3(0.09, 0.85, 0.09))
			push.call(mail_mat, box_mesh_u, bx, bz, mr, 0.95, Vector3(0.35, 0.45, 0.3))
			break
	for k in 3:
		for t in 30:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.8):
				continue
			var br := Utils.rand(-0.25, 0.25)
			push.call(bench_mat, box_mesh_u, bx, bz, br, 0.2, Vector3(0.1, 0.45, 0.26))
			push.call(bench_mat, box_mesh_u, bx + 0.85, bz, br, 0.2, Vector3(0.1, 0.45, 0.26))
			push.call(bench_mat, box_mesh_u, bx, bz, br, 0.42, Vector3(1.9, 0.07, 0.26))
			push.call(bench_mat, box_mesh_u, bx, bz, br, 0.52, Vector3(1.9, 0.07, 0.26))
			push.call(bench_mat, box_mesh_u, bx, bz, br, 0.62, Vector3(1.9, 0.07, 0.26))
			break
	for k in 4:
		for t in 30:
			var cr: float = Utils.choice([-R2, 0.0, R2]) + Utils.choice([-5.0, 5.0]) + Utils.rand(-0.8, 0.8)
			var on_h := randf() < 0.5
			var bx := cr
			var bz := Utils.rand(-140, 140)
			if not on_h:
				var t2 := bx
				bx = bz
				bz = t2
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.0):
				continue
			var crr := Utils.rand(TAU)
			push.call(cone_mat, cone_mesh, bx, bz, crr, 0.225, Vector3.ONE)
			push.call(tip_mat, cyl_mesh_u, bx, bz, crr, 0.49, Vector3(0.9, 0.13, 0.9))
			break
	# 烧毁车辆残骸(低矮车体 + 歪斜 + 少轮,带碰撞)
	var burnt_mat := _std(Color.html("#1c1a18"), 0.95, 0.2)
	for k in 4:
		for t in 40:
			var on_h := randf() < 0.5
			var bx := Utils.rand(-140, 140)
			var bz: float = Utils.choice([-R2 - 3.5, -R2 + 3.5, -3.5, 3.5, R2 - 3.5, R2 + 3.5]) + Utils.rand(-0.5, 0.5)
			var rr := 0.0
			if not on_h:
				var sw := bx
				bx = bz
				bz = sw
				rr = PI / 2.0
			if near_flag3.call(bx, bz, 22.0) or not clear_spot.call(bx, bz, 1.5):
				continue
			var grp := Node3D.new()
			var bd := _box(4.0, 1.1, 1.8, burnt_mat)
			bd.position.y = 0.55
			grp.add_child(bd)
			var cb := _box(2.0, 0.75, 1.6, burnt_mat)
			cb.position = Vector3(-0.2, 1.2, 0)
			grp.add_child(cb)
			var whm := _std(Color.html("#101010"), 0.95)
			for wpp in [[-1.3, 0.9], [1.3, -0.9]]:
				var wh := _cyl(0.33, 0.33, 0.26, 8, whm)
				wh.rotation.x = PI / 2.0
				wh.position = Vector3(wpp[0], 0.32, wpp[1])
				grp.add_child(wh)
			grp.rotation.y = rr + Utils.rand(-0.2, 0.2)
			grp.rotation.z = Utils.rand(-0.07, 0.07)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 4.2, 1.7, 1.9)
			break
	# 弹壳堆(金色极小圆柱簇,纯装饰)
	var shell_mat := _std(Color.html("#d9a520"), 0.4, 0.9)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.012
	shell_mesh.bottom_radius = 0.012
	shell_mesh.height = 0.07
	shell_mesh.radial_segments = 5
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 0.8):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)


## ==================== 沙漠油站 ====================
static func _desert_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, sandbag: Callable, car: Callable, container: Callable, rock_photo_mat: Material) -> void:
	var R: float = T.road
	var tan_mat := StandardMaterial3D.new()
	tan_mat.albedo_texture = TerrainTextures.facade_texture("#b89a70", 0.08, 3)
	tan_mat.roughness = 0.95
	var hangar_mat := _std_tex(Color.html("#b8a880"), 0.7, "corrugated_iron", 0.3)
	var rust_mat := _std_tex(Color.html("#b07050"), 0.75, "metal_plate", 0.35)
	var rock_mat: Material = rock_photo_mat
	var _roof_mat := _std(Color.html("#3a3c40"), 0.95)
	var barracks := func(x: float, z: float, rot := 0.0) -> void:
		var w := Utils.rand(10, 14)
		var d := Utils.rand(7, 9)
		var h := Utils.rand(3.5, 5)
		var b := _box(w, h, d, tan_mat)
		b.rotation.y = rot
		b.position = Vector3(x, G.ground_h.call(x, z) + h / 2.0, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var ww := w if absf(cos(rot)) > 0.5 else d
		add_collider.call(x, 0, z, ww, h, d if ww == w else w)
		minimap_rects.append({ "x": x, "z": z, "w": ww, "d": d if ww == w else w })
	var hangar := func(x: float, z: float, rot := 0.0) -> void:
		var gh: float = G.ground_h.call(x, z)
		var b := _box(16, 7, 12, hangar_mat)
		b.rotation.y = rot
		b.position = Vector3(x, gh + 3.5, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var roof := _cyl(6, 6, 16.5, 12, hangar_mat)
		roof.rotation.z = PI / 2.0
		roof.rotation.y = rot
		roof.position = Vector3(x, gh + 7, z)
		wg.add_child(roof)
		var ww := 16 if absf(cos(rot)) > 0.5 else 12
		add_collider.call(x, 0, z, ww, 7, 12 if ww == 16 else 16)
		minimap_rects.append({ "x": x, "z": z, "w": ww, "d": 12 if ww == 16 else 16 })
	var oil_tank := func(x: float, z: float) -> void:
		var r := Utils.rand(3.5, 5)
		var t := _cyl(r, r, Utils.rand(7, 10), 16, rust_mat)
		t.position = Vector3(x, G.ground_h.call(x, z) + 4.2, z)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(t)
		add_collider.call(x, 0, z, r * 1.7, 8.5, r * 1.7)
		minimap_rects.append({ "x": x, "z": z, "w": r * 1.7, "d": r * 1.7 })
	var rock := func(x: float, z: float, s := 1.0) -> void:
		var r := _ico(Utils.rand(1, 2.2) * s, rock_mat)
		r.position = Vector3(x, G.ground_h.call(x, z) + Utils.rand(0.3, 0.8) * s, z)
		r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(r)
		add_collider.call(x, 0, z, 2 * s, 1.6 * s, 2 * s)
	var blocks := [-142, -94, -66, -14, 14, 66, 94, 142]
	for i in blocks.size() - 1:
		for j in blocks.size() - 1:
			var cx: float = (blocks[i] + blocks[i + 1]) / 2.0
			var cz: float = (blocks[j] + blocks[j + 1]) / 2.0
			var w: float = blocks[i + 1] - blocks[i]
			if w < 40:
				continue
			var roll := randf()
			if roll < 0.35:
				barracks.call(cx - 10, cz, Utils.rand(-0.2, 0.2))
				barracks.call(cx + 12, cz + Utils.rand(-8, 8), Utils.rand(-0.2, 0.2))
			elif roll < 0.55:
				hangar.call(cx, cz, Utils.rand(-0.3, 0.3))
			elif roll < 0.75:
				oil_tank.call(cx - 8, cz - 6)
				oil_tank.call(cx + 8, cz - 6)
				oil_tank.call(cx, cz + 8)
			else:
				rock.call(cx - 8, cz, 1.4)
				rock.call(cx + 6, cz + 7, 1.1)
				crate.call(cx + 2, cz - 8)
	# 管道
	for i in 6:
		var p := _cyl(0.5, 0.5, Utils.rand(14, 24), 8, rust_mat)
		p.rotation.z = PI / 2.0
		p.rotation.y = Utils.rand(PI)
		var px := Utils.rand(-130, 130)
		var pz := Utils.rand(-130, 130)
		p.position = Vector3(px, G.ground_h.call(px, pz) + 0.5, pz)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(p)
		add_collider.call(px, 0, pz, 10, 1, 2)
	# 道具
	for i in 52:
		var roll := randi() % 6
		match roll:
			0: barrel.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			1: crate.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			2: sandbag.call(Utils.rand(-140, 140), Utils.choice([-R, 0.0, R]) + Utils.rand(-6, 6), Utils.rand(PI))
			3: car.call(Utils.rand(-140, 140), Utils.choice([-R - 3, R + 3, -3.0, 3.0]), Utils.rand(-0.3, 0.3), Color.html("#9a7a4a"))
			4: container.call(Utils.rand(-140, 140), Utils.rand(-140, 140), Utils.rand(PI))
			5: rock.call(Utils.rand(-140, 140), Utils.rand(-140, 140), Utils.rand(0.8, 1.6))
	# ---------- 战争沉浸感物件(轮胎堆/油罐架/沙袋环堡/报废卡车/油布棚/沙丘微堆/弹壳) ----------
	var flag_pts := [[-R, -R], [R, -R], [0.0, 0.0], [-R, R], [R, R]]
	var near_flag3 := func(x: float, z: float, r: float) -> bool:
		for fp in flag_pts:
			var dx: float = x - fp[0]
			var dz: float = z - fp[1]
			if sqrt(dx * dx + dz * dz) < r:
				return true
		return false
	var clear_spot := func(x: float, z: float, margin: float) -> bool:
		for b in G.colliders:
			var bb: AABB = b
			var dx: float = maxf(absf(x - bb.get_center().x) - bb.size.x * 0.5, 0.0)
			var dz: float = maxf(absf(z - bb.get_center().z) - bb.size.z * 0.5, 0.0)
			if dx * dx + dz * dz < margin * margin:
				return false
		return true
	var on_road2 := func(x: float, z: float, w: float) -> bool:
		for r in [-R, 0.0, R]:
			if absf(x - r) < w or absf(z - r) < w:
				return true
		return false
	var buf := {}
	var push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	# 轮胎堆(扁环 _cyl 双层,黑色)
	var tire_mat := _std(Color.html("#161616"), 0.95)
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = 0.5
	tire_mesh.bottom_radius = 0.5
	tire_mesh.height = 0.16
	tire_mesh.radial_segments = 10
	for k in 3:
		for t in 40:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if on_road2.call(bx, bz, 6.0) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.5):
				continue
			var yr := Utils.rand(TAU)
			push.call(tire_mat, tire_mesh, bx, bz, yr, 0.08, Vector3.ONE)
			push.call(tire_mat, tire_mesh, bx, bz, yr, 0.25, Vector3.ONE)
			break
	# 沙丘微堆(低矮扁球)
	var hum_mat := _std(Color.html("#b8a468"), 1.0)
	var sph_mesh_u := SphereMesh.new()
	sph_mesh_u.radius = 1.0
	sph_mesh_u.height = 2.0
	sph_mesh_u.radial_segments = 12
	sph_mesh_u.rings = 8
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if on_road2.call(bx, bz, 8.0) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 2.5):
				continue
			var s := Utils.rand(2.2, 3.6)
			push.call(hum_mat, sph_mesh_u, bx, bz, Utils.rand(TAU), 0.18, Vector3(s * 1.3, 0.28, s))
			break
	# 油罐架(木架十字 + 油桶 2 个)
	var rack_mat := _std(Color.html("#6a5232"), 0.95)
	var dr_mat := _std(Color.html("#7a3a1e"), 0.5, 0.6)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if near_flag3.call(bx, bz, 24.0) or not clear_spot.call(bx, bz, 2.5):
				continue
			var gh: float = G.ground_h.call(bx, bz)
			var grp := Node3D.new()
			var cross1 := _box(1.6, 0.12, 0.45, rack_mat)
			cross1.position.y = 1.15
			grp.add_child(cross1)
			var cross2 := _box(0.45, 0.12, 1.6, rack_mat)
			cross2.position.y = 1.15
			grp.add_child(cross2)
			for dr in [[-0.5, 0.0], [0.5, 0.0]]:
				var d := _cyl(0.34, 0.34, 0.95, 10, dr_mat)
				d.position = Vector3(dr[0], 1.8, dr[1])
				grp.add_child(d)
			grp.position = Vector3(bx, gh, bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 1.9, 2.4, 1.9)
			break
	# 油布棚(斜顶 + 双柱,2 组)
	var tarp_mat := _std(Color.html("#8a7a4a"), 0.95)
	var post_mat := _std(Color.html("#5a4a2e"), 0.95)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if near_flag3.call(bx, bz, 24.0) or not clear_spot.call(bx, bz, 3.0):
				continue
			var gh: float = G.ground_h.call(bx, bz)
			var grp := Node3D.new()
			for pp in [[-1.8, 0.0], [1.8, 0.0]]:
				var post := _box(0.18, 2.6, 0.18, post_mat)
				post.position = Vector3(pp[0], 1.3, pp[1])
				grp.add_child(post)
			var top1 := _box(4.6, 0.1, 2.6, tarp_mat)
			top1.position = Vector3(0, 2.6, 0)
			top1.rotation.z = -0.25
			grp.add_child(top1)
			var top2 := _box(4.6, 0.1, 2.6, tarp_mat)
			top2.position = Vector3(0, 2.55, -0.1)
			top2.rotation.z = 0.25
			grp.add_child(top2)
			grp.position = Vector3(bx, gh, bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 4.8, 2.8, 2.8)
			break
	# 报废卡车(缺轮斜躺,带碰撞)
	var wrk_mat := _std(Color.html("#7a5a3a"), 0.9, 0.2)
	var wrk_cab := _std(Color.html("#5a4a3a"), 0.95)
	for k in 3:
		for t in 40:
			var on_h := randf() < 0.5
			var bx := Utils.rand(-140, 140)
			var bz: float = Utils.choice([-R - 4.0, -R + 4.0, -4.0, 4.0, R - 4.0, R + 4.0]) + Utils.rand(-1, 1)
			if not on_h:
				var sw := bx
				bx = bz
				bz = sw
			if near_flag3.call(bx, bz, 22.0) or not clear_spot.call(bx, bz, 1.5):
				continue
			var grp := Node3D.new()
			var bd := _box(5.4, 1.1, 2.1, wrk_mat)
			bd.position.y = 0.55
			grp.add_child(bd)
			var cb := _box(1.6, 1.5, 2.1, wrk_cab)
			cb.position = Vector3(2.0, 0.9, 0)
			grp.add_child(cb)
			var whm := _std(Color.html("#1a1a1a"), 0.95)
			for wpp in [[-1.8, 0.95], [1.6, -0.95]]:
				var wh := _cyl(0.42, 0.42, 0.32, 8, whm)
				wh.rotation.x = PI / 2.0
				wh.position = Vector3(wpp[0], 0.4, wpp[1])
				grp.add_child(wh)
			grp.rotation.y = Utils.rand(TAU)
			grp.rotation.z = Utils.rand(-0.04, 0.1)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 5.4, 1.7, 2.2)
			break
	# 沙袋环堡(围圈 8 个一组 × 2,带碰撞)
	for k in 2:
		for t in 40:
			var rx := Utils.rand(-110, 110)
			var rz2 := Utils.rand(-110, 110)
			if near_flag3.call(rx, rz2, 26.0) or not clear_spot.call(rx, rz2, 3.5):
				continue
			for a2 in 8:
				var ang := a2 / 8.0 * TAU
				sandbag.call(rx + cos(ang) * 2.4, rz2 + sin(ang) * 2.4, ang + PI / 2.0)
			break
	# 弹壳堆(金色极小圆柱簇,纯装饰)
	var shell_mat := _std(Color.html("#d9a520"), 0.4, 0.9)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.012
	shell_mesh.bottom_radius = 0.012
	shell_mesh.height = 0.07
	shell_mesh.radial_segments = 5
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 0.8):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# 沙丘(界外)
	var dune_mat := _std(Color.html("#c8a868"), 1.0)
	for i in 10:
		var a := i / 10.0 * TAU + Utils.rand(-0.2, 0.2)
		var d := MeshInstance3D.new()
		var dm := SphereMesh.new()
		dm.radius = Utils.rand(30, 60)
		dm.height = dm.radius * 2
		dm.radial_segments = 12
		dm.rings = 8
		d.mesh = dm
		d.material_override = dune_mat
		d.scale.y = Utils.rand(0.12, 0.2)
		d.position = Vector3(cos(a) * Utils.rand(190, 260), 0, sin(a) * Utils.rand(190, 260))
		wg.add_child(d)
	# 台地天际线
	var mesa_mat := _basic(Color.html("#b08a5a"), true)
	for i in 16:
		var a := i / 16.0 * TAU + Utils.rand(-0.15, 0.15)
		var r := Utils.rand(220, 300)
		var h := Utils.rand(20, 55)
		var b := _box(Utils.rand(40, 80), h, Utils.rand(30, 60), mesa_mat)
		b.position = Vector3(cos(a) * r, h / 2 - 2, sin(a) * r)
		wg.add_child(b)


## ==================== 沙漠机场(南区:跑道 + 双机库 + 塔台 + 停机坪) ====================
static func _desert_airport(wg: Node3D, add_collider: Callable, minimap_rects: Array,
		ent_wall: Material, roof_mat: Material) -> void:
	var tarmac_mat := _std(Color.html("#4a4c4e"), 0.92)
	var line_mat := _basic(Color.html("#e8e8e0"), true)
	var plane_mat := _std_tex(Color.html("#b8bcc0"), 0.5, "metal_plate", 0.5)
	var rz := -95.0
	# 跑道(东西向沥青带)
	var gh0: float = G.ground_h.call(0, rz)
	var runway := _box(116, 0.14, 11, tarmac_mat)
	runway.position = Vector3(0, gh0 + 0.07, rz)
	wg.add_child(runway)
	# 中线虚线
	for k in 13:
		var dash := _box(3.2, 0.03, 0.4, line_mat)
		dash.position = Vector3(-54 + k * 9, gh0 + 0.16, rz)
		wg.add_child(dash)
	# 两端斑马线
	for e in [-54.0, 54.0]:
		for k in 6:
			var st := _box(0.7, 0.03, 7.5, line_mat)
			st.position = Vector3(e + (2.2 if e < 0 else -2.2) + k * 0.9 * (1 if e < 0 else -1), gh0 + 0.16, rz)
			wg.add_child(st)
	minimap_rects.append({ "x": 0, "z": rz, "w": 116, "d": 11 })
	# 双机库(可进入,大门朝跑道北)
	build_hangar_enterable(wg, -72, rz, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
	build_hangar_enterable(wg, 72, rz, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
	# 塔台(可进入底层 + 顶部指挥室)
	build_enterable(wg, 88, -78, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
	var tw_gh: float = G.ground_h.call(88, -78)
	var cab := _box(4.6, 2.4, 4.6, roof_mat)
	cab.position = Vector3(88, tw_gh + 6.2, -78)
	cab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	wg.add_child(cab)
	var cab_top := _box(5.2, 0.3, 5.2, roof_mat)
	cab_top.position = Vector3(88, tw_gh + 7.5, -78)
	wg.add_child(cab_top)
	add_collider.call(88, 0, -78, 4.6, 7.6, 4.6)
	# 停机坪飞机(螺旋桨机道具 ×2)
	var plane := func(x: float, z: float, rot: float) -> void:
		var g := Node3D.new()
		var fus := _cyl(0.55, 0.75, 6.4, 10, plane_mat)
		fus.rotation.z = PI / 2.0
		fus.position.y = 1.0
		g.add_child(fus)
		var wing := _box(1.1, 0.1, 8.6, plane_mat)
		wing.position = Vector3(-0.4, 1.15, 0)
		g.add_child(wing)
		var tail := _box(1.4, 0.09, 3.2, plane_mat)
		tail.position = Vector3(2.9, 1.3, 0)
		g.add_child(tail)
		var fin := _box(1.2, 1.3, 0.1, plane_mat)
		fin.position = Vector3(2.9, 1.9, 0)
		g.add_child(fin)
		var prop := _box(0.06, 2.3, 0.16, roof_mat)
		prop.position = Vector3(-3.3, 1.0, 0)
		g.add_child(prop)
		g.rotation.y = rot
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 6.4, 2.2, 8.6)
	plane.call(-30, rz - 12, 0.15)
	plane.call(26, rz - 13, -0.2)
	# 停机位标线
	for k in [-30.0, 26.0]:
		var mk := _box(7.5, 0.03, 0.35, line_mat)
		mk.position = Vector3(k, G.ground_h.call(k, rz - 12) + 0.05, rz - 12)
		wg.add_child(mk)


## ==================== 雪山哨站 ====================
static func _snow_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, sandbag: Callable, container: Callable, barrier: Callable, rock_photo_mat: Material) -> void:
	var R: float = T.road
	var bunker_mat := _std_tex(Color.html("#b8bcc0"), 1.0, "rough_concrete")
	var wood_mat := _std_tex(Color.html("#8a7050"), 0.95, "plywood")
	var pine_trunk := _std(Color.html("#4a3a28"), 1.0)
	var pine_leaf := _std(Color.html("#2a4a3a"), 1.0)
	var pine_snow := _std(Color.html("#d8e4ec"), 1.0)
	var rock_mat: Material = rock_photo_mat
	var bunker := func(x: float, z: float, rot := 0.0) -> void:
		var w := Utils.rand(7, 10)
		var d := Utils.rand(6, 8)
		var h := Utils.rand(3, 4.2)
		var gh: float = G.ground_h.call(x, z)
		var b := _box(w, h, d, bunker_mat)
		b.rotation.y = rot
		b.position = Vector3(x, gh + h / 2.0, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var slit := _box(w * 0.8, 0.3, 0.1, _basic(Color.html("#1a1e22"), true))
		if absf(cos(rot)) > 0.5:
			slit.position = Vector3(x, gh + h * 0.65, z + d / 2.0 + 0.01)
		else:
			slit.rotation.y = PI / 2.0
			slit.position = Vector3(x + d / 2.0 + 0.01, gh + h * 0.65, z)
		wg.add_child(slit)
		var ww := w if absf(cos(rot)) > 0.5 else d
		add_collider.call(x, 0, z, ww, h, d if ww == w else w)
		minimap_rects.append({ "x": x, "z": z, "w": ww, "d": d if ww == w else w })
	var tower := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for lp in [[-1.2, -1.2], [1.2, -1.2], [-1.2, 1.2], [1.2, 1.2]]:
			var leg := _box(0.25, 6, 0.25, wood_mat)
			leg.position = Vector3(lp[0], 3, lp[1])
			g.add_child(leg)
		var cabin := _box(3.4, 2.2, 3.4, wood_mat)
		cabin.position.y = 7.1
		g.add_child(cabin)
		var roof := _cone(2.8, 1.4, 4, pine_snow)
		roof.position.y = 9
		roof.rotation.y = PI / 4.0
		g.add_child(roof)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 2.8, 8, 2.8)
		minimap_rects.append({ "x": x, "z": z, "w": 2.8, "d": 2.8 })
	var pine := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var h := Utils.rand(4, 7)
		var trunk := _cyl(0.18, 0.25, h * 0.4, 6, pine_trunk)
		trunk.position.y = h * 0.2
		g.add_child(trunk)
		var c1 := _cone(h * 0.32, h * 0.55, 8, pine_leaf)
		c1.position.y = h * 0.55
		g.add_child(c1)
		var c2 := _cone(h * 0.24, h * 0.45, 8, pine_snow if randf() < 0.6 else pine_leaf)
		c2.position.y = h * 0.82
		g.add_child(c2)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 0.7, h, 0.7)
	var rock := func(x: float, z: float, s := 1.0) -> void:
		var r := _ico(Utils.rand(1, 2) * s, rock_mat)
		r.position = Vector3(x, G.ground_h.call(x, z) + Utils.rand(0.3, 0.7) * s, z)
		r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(r)
		add_collider.call(x, 0, z, 2 * s, 1.5 * s, 2 * s)
	var tower_spots := []
	var blocks := [-142, -94, -66, -14, 14, 66, 94, 142]
	for i in blocks.size() - 1:
		for j in blocks.size() - 1:
			var cx: float = (blocks[i] + blocks[i + 1]) / 2.0
			var cz: float = (blocks[j] + blocks[j + 1]) / 2.0
			var w: float = blocks[i + 1] - blocks[i]
			if w < 40:
				continue
			var roll := randf()
			if roll < 0.4:
				bunker.call(cx - 8, cz, Utils.rand(-0.2, 0.2))
				bunker.call(cx + 10, cz + Utils.rand(-6, 6), Utils.rand(-0.2, 0.2))
			elif roll < 0.55:
				tower.call(cx, cz)
				tower_spots.append(Vector2(cx, cz))
				pine.call(cx - 10, cz + 8)
				pine.call(cx + 9, cz - 7)
			else:
				for k in 5:
					pine.call(cx + Utils.rand(-16, 16), cz + Utils.rand(-16, 16))
				rock.call(cx + Utils.rand(-10, 10), cz + Utils.rand(-10, 10), 1.2)
	for i in 40:
		pine.call(Utils.rand(-145, 145), Utils.rand(-145, 145))
	for i in 40:
		var roll := randi() % 5
		match roll:
			0: crate.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			1: rock.call(Utils.rand(-140, 140), Utils.rand(-140, 140), Utils.rand(0.8, 1.8))
			2: sandbag.call(Utils.rand(-140, 140), Utils.choice([-R, 0.0, R]) + Utils.rand(-6, 6), Utils.rand(PI))
			3: container.call(Utils.rand(-140, 140), Utils.rand(-140, 140), Utils.rand(PI))
			4: barrier.call(Utils.rand(-140, 140), Utils.choice([-R, 0.0, R]) + Utils.rand(-5, 5), Utils.rand(PI))
	# ---------- 积雪核心物件(雪堆/覆雪木箱与沙袋/结冰车/房檐冰柱/雪人彩蛋/弹壳) ----------
	var flag_pts := [[-R, -R], [R, -R], [0.0, 0.0], [-R, R], [R, R]]
	var near_flag3 := func(x: float, z: float, r: float) -> bool:
		for fp in flag_pts:
			var dx: float = x - fp[0]
			var dz: float = z - fp[1]
			if sqrt(dx * dx + dz * dz) < r:
				return true
		return false
	var clear_spot := func(x: float, z: float, margin: float) -> bool:
		for b in G.colliders:
			var bb: AABB = b
			var dx: float = maxf(absf(x - bb.get_center().x) - bb.size.x * 0.5, 0.0)
			var dz: float = maxf(absf(z - bb.get_center().z) - bb.size.z * 0.5, 0.0)
			if dx * dx + dz * dz < margin * margin:
				return false
		return true
	var on_road2 := func(x: float, z: float, w: float) -> bool:
		for r in [-R, 0.0, R]:
			if absf(x - r) < w or absf(z - r) < w:
				return true
		return false
	var buf := {}
	var push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	# 雪堆/雪脊(白色扁椭球,沿路边,纯装饰)
	var sn_pile_mat := _std(Color.html("#eef2f6"), 0.95)
	var sph_u := SphereMesh.new()
	sph_u.radius = 1.0
	sph_u.height = 2.0
	sph_u.radial_segments = 12
	sph_u.rings = 8
	for k in 8:
		var bx := Utils.rand(-140, 140)
		var bz: float = Utils.choice([-R, 0.0, R]) + Utils.choice([-1.0, 1.0]) * Utils.rand(7.5, 12.5)
		if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.5):
			continue
		var s := Utils.rand(1.8, 3.2)
		push.call(sn_pile_mat, sph_u, bx, bz, Utils.rand(TAU), 0.18, Vector3(s * 1.4, 0.34, s))
	# 覆雪木箱/沙袋(白 albedo,带碰撞,等效原 crate/sandbag)
	var sn_crate_mat := _std(Color.html("#e2e8ee"), 0.85)
	var sn_bag_mat2 := _std(Color.html("#dde4ea"), 0.95)
	var ubox2 := BoxMesh.new()
	ubox2.size = Vector3.ONE
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.6):
				continue
			push.call(sn_crate_mat, ubox2, bx, bz, Utils.rand(-0.3, 0.3), 0.65, Vector3(1.3, 1.3, 1.3))
			add_collider.call(bx, 0, bz, 1.3, 1.3, 1.3)
			break
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.6):
				continue
			var sr := Utils.rand(TAU)
			push.call(sn_bag_mat2, ubox2, bx, bz, sr, 0.5, Vector3(3.0, 1.0, 0.7))
			var ww := 3.0 if absf(cos(sr)) > 0.5 else 0.7
			add_collider.call(bx, 0, bz, ww, 1.0, 0.7 if ww == 3.0 else 3.0)
			break
	# 结冰车(白车顶变体,带碰撞)
	var frz_mat := _std(Color.html("#d8e2ea"), 0.45, 0.3)
	var frz_cab := _std(Color.html("#eef2f6"), 0.5)
	for k in 3:
		for t in 40:
			var on_h := randf() < 0.5
			var bx := Utils.rand(-140, 140)
			var bz: float = Utils.choice([-R - 3.5, -R + 3.5, -3.5, 3.5, R - 3.5, R + 3.5]) + Utils.rand(-0.5, 0.5)
			var rr := 0.0
			if not on_h:
				var sw := bx
				bx = bz
				bz = sw
				rr = PI / 2.0
			if near_flag3.call(bx, bz, 22.0) or not clear_spot.call(bx, bz, 1.5):
				continue
			var grp := Node3D.new()
			var bd := _box(4.2, 0.85, 1.9, frz_mat)
			bd.position.y = 0.65
			grp.add_child(bd)
			var cb := _box(2.2, 0.7, 1.7, frz_cab)
			cb.position = Vector3(-0.2, 1.35, 0)
			grp.add_child(cb)
			var whm := _std(Color.html("#14161a"), 0.9)
			for wpp in [[-1.4, 0.95], [1.4, 0.95], [-1.4, -0.95], [1.4, -0.95]]:
				var wh := _cyl(0.36, 0.36, 0.3, 10, whm)
				wh.rotation.x = PI / 2.0
				wh.position = Vector3(wpp[0], 0.36, wpp[1])
				grp.add_child(wh)
			grp.rotation.y = rr + Utils.rand(-0.1, 0.1)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 4.2, 1.7, 1.9)
			break
	# 房檐冰柱(挂哨塔檐下,倒锥,纯装饰)
	var icicle_mat := _std(Color.html("#e8f0f6"), 0.3, 0.1)
	var icicle_mesh := CylinderMesh.new()
	icicle_mesh.top_radius = 0.0
	icicle_mesh.bottom_radius = 0.045
	icicle_mesh.height = 0.6
	icicle_mesh.radial_segments = 6
	var ic_n: int = mini(tower_spots.size(), 3)
	for k in ic_n:
		var ts: Vector2 = tower_spots[k]
		for j2 in 2:
			var icx: float = ts.x + cos(j2 * 2.1 + k) * 2.5
			var icz: float = ts.y + sin(j2 * 2.1 + k) * 2.5
			push.call(icicle_mat, icicle_mesh, icx, icz, Utils.rand(TAU), 8.4, Vector3(1, -1, 1))
	# 雪人彩蛋(三球叠 + 眼睛 + 胡萝卜鼻,纯装饰)
	var smn_spot := Vector2.ZERO
	var found_s := false
	for t in 50:
		var bx := Utils.rand(-120, 120)
		var bz := Utils.rand(-120, 120)
		if on_road2.call(bx, bz, 6.0) or near_flag3.call(bx, bz, 22.0) or not clear_spot.call(bx, bz, 2.5):
			continue
		smn_spot = Vector2(bx, bz)
		found_s = true
		break
	if found_s:
		var smn := Node3D.new()
		var smat := _std(Color.html("#f4f8fc"), 0.9)
		var b1 := _ico(0.55, smat)
		b1.position.y = 0.55
		smn.add_child(b1)
		var b2 := _ico(0.4, smat)
		b2.position.y = 1.4
		smn.add_child(b2)
		var b3 := _ico(0.28, smat)
		b3.position.y = 2.05
		smn.add_child(b3)
		var eye_m := _std(Color.html("#181818"), 0.8)
		for ep in [[-0.1, 2.15, 0.18], [0.12, 2.15, 0.18]]:
			var e := _cyl(0.03, 0.03, 0.03, 6, eye_m)
			e.position = Vector3(ep[0], ep[1], ep[2])
			smn.add_child(e)
		var nose := _cone(0.06, 0.28, 6, _std(Color.html("#e08020"), 0.6))
		nose.rotation.x = PI / 2.0
		nose.position = Vector3(0.02, 2.1, 0.3)
		smn.add_child(nose)
		smn.position = Vector3(smn_spot.x, G.ground_h.call(smn_spot.x, smn_spot.y), smn_spot.y)
		_shadows_on(smn)
		wg.add_child(smn)
	# 弹壳堆(金色极小圆柱簇,纯装饰)
	var shell_mat := _std(Color.html("#d9a520"), 0.4, 0.9)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.012
	shell_mesh.bottom_radius = 0.012
	shell_mesh.height = 0.07
	shell_mesh.radial_segments = 5
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 0.8):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# 雪山天际线
	var mtn_mat := _basic(Color.html("#dde6ee"), true)
	for i in 18:
		var a := i / 18.0 * TAU + Utils.rand(-0.12, 0.12)
		var r := Utils.rand(220, 300)
		var h := Utils.rand(60, 130)
		var m := _cone(Utils.rand(40, 70), h, 6, mtn_mat)
		m.position = Vector3(cos(a) * r, h / 2 - 4, sin(a) * r)
		wg.add_child(m)
	# 降雪粒子(MultiMesh 公告牌,update_map 驱动;密度随画质档位)
	var lv_snow: int = GraphicsQuality.current_level
	var snow_n := int(500 * G.settings.particles * (0.3 if OS.has_feature("web") else 1.0) * [0.45, 0.7, 1.0, 1.3][lv_snow])
	G.map_fx["hgrid"] = _bake_hgrid()
	var positions := PackedVector3Array()
	positions.resize(snow_n)
	for i in snow_n:
		positions[i] = Vector3(Utils.rand(-35, 35), Utils.rand(0, 30), Utils.rand(-35, 35))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var snow_mat := _particle_mat(Color(1, 1, 1, 0.85))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = snow_n
	for i in snow_n:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = snow_mat
	wg.add_child(mmi)
	G.map_fx["snow"] = { "positions": positions, "mm": mm }


## ==================== 丛林河谷(突破) ====================
static func _jungle_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, near_obj: Callable, rock_photo_mat: Material) -> void:
	var trunk_mat := _std(Color.html("#4a3a26"), 1.0)
	var leaf_mat := _std(Color.html("#2e5230"), 1.0)
	var leaf_mat2 := _std(Color.html("#3a6036"), 1.0)
	var bush_mat := _std(Color.html("#3c5c2e"), 1.0)
	var wood_mat2 := _std_tex(Color.html("#8a6a44"), 0.95, "plywood")
	var thatch_mat := _std(Color.html("#9a7c4a"), 1.0)
	var jungle_tree := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var h := Utils.rand(6, 10)
		var trunk := _cyl(0.22, 0.34, h, 7, trunk_mat)
		trunk.position.y = h / 2.0
		g.add_child(trunk)
		var c1 := MeshInstance3D.new()
		var s1 := SphereMesh.new()
		s1.radius = h * 0.36
		s1.height = s1.radius * 2
		s1.radial_segments = 8
		s1.rings = 6
		c1.mesh = s1
		c1.material_override = leaf_mat if randf() < 0.5 else leaf_mat2
		c1.position.y = h * 0.92
		c1.scale.y = 0.75
		g.add_child(c1)
		var c2 := MeshInstance3D.new()
		var s2 := SphereMesh.new()
		s2.radius = h * 0.26
		s2.height = s2.radius * 2
		s2.radial_segments = 7
		s2.rings = 5
		c2.mesh = s2
		c2.material_override = leaf_mat2
		c2.position = Vector3(Utils.rand(-0.8, 0.8), h * 1.12, Utils.rand(-0.8, 0.8))
		c2.scale.y = 0.7
		g.add_child(c2)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 0.8, h, 0.8)
	var bush := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for i in 3:
			var b := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = Utils.rand(0.5, 1.1)
			sm.height = sm.radius * 2
			sm.radial_segments = 7
			sm.rings = 5
			b.mesh = sm
			b.material_override = bush_mat
			b.position = Vector3(Utils.rand(-0.7, 0.7), Utils.rand(0.2, 0.5), Utils.rand(-0.7, 0.7))
			b.scale.y = 0.7
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			g.add_child(b)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		wg.add_child(g)
	var rock := func(x: float, z: float, s := 1.0) -> void:
		var r := _ico(Utils.rand(1, 2.2) * s, rock_photo_mat)
		r.position = Vector3(x, G.ground_h.call(x, z) + Utils.rand(0.3, 0.7) * s, z)
		r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(r)
		add_collider.call(x, 0, z, 2 * s, 1.5 * s, 2 * s)
	var hut := func(x: float, z: float, rot := 0.0) -> void:
		var gh: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		var body := _box(5.2, 2.8, 4.2, wood_mat2)
		body.position.y = 2.2
		g.add_child(body)
		var roof := _cone(4.1, 1.8, 4, thatch_mat)
		roof.position.y = 4.5
		roof.rotation.y = PI / 4.0
		g.add_child(roof)
		var door := _box(1.1, 1.9, 0.1, _basic(Color.html("#201812"), true))
		door.position = Vector3(0, 1.75, 2.12)
		g.add_child(door)
		for lp in [[-2.2, -1.7], [2.2, -1.7], [-2.2, 1.7], [2.2, 1.7]]:
			var leg := _cyl(0.14, 0.14, 0.9, 6, trunk_mat)
			leg.position = Vector3(lp[0], 0.45, lp[1])
			g.add_child(leg)
		g.rotation.y = rot
		g.position = Vector3(x, gh, z)
		_shadows_on(g)
		wg.add_child(g)
		var cs := absf(cos(rot)) > 0.5
		add_collider.call(x, 0.8, z, 5.2 if cs else 4.2, 3.5, 4.2 if cs else 5.2)
		minimap_rects.append({ "x": x, "z": z, "w": 5.2 if cs else 4.2, "d": 4.2 if cs else 5.2 })
	var log_f := func(x: float, z: float) -> void:
		var l := _cyl(0.32, 0.38, Utils.rand(5, 8), 8, trunk_mat)
		l.rotation.z = PI / 2.0
		l.rotation.y = Utils.rand(PI)
		l.position = Vector3(x, G.ground_h.call(x, z) + 0.35, z)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(l)
		add_collider.call(x, 0, z, 5, 0.7, 0.8)
	# 目标点村庄/哨站布景
	for sec in T.sectors:
		for o in sec:
			hut.call(o["x"] + Utils.rand(-14, -10), o["z"] + Utils.rand(8, 13), Utils.rand(-0.4, 0.4))
			hut.call(o["x"] + Utils.rand(10, 14), o["z"] + Utils.rand(-13, -8), Utils.rand(-0.4, 0.4))
			crate.call(o["x"] + Utils.rand(-8, 8), o["z"] + Utils.rand(-8, 8))
			barrel.call(o["x"] + Utils.rand(-9, 9), o["z"] + Utils.rand(-9, 9))
	# 渡口两侧巨石
	rock.call(-11, T.river + Utils.rand(-3, 3), 1.6)
	rock.call(11, T.river + Utils.rand(-3, 3), 1.4)
	# 全图密林(变量声明提至函数级,避免循环间遮蔽)
	var x_j := 0.0
	var z_j := 0.0
	for i in 150:
		x_j = Utils.rand(-165, 165)
		z_j = Utils.rand(-165, 165)
		if absf(x_j) < 12 or near_obj.call(x_j, z_j, 19):
			continue
		if absf(z_j - T.river) < 9 and absf(x_j) < 18:
			continue
		jungle_tree.call(x_j, z_j)
	for i in 85:
		x_j = Utils.rand(-160, 160)
		z_j = Utils.rand(-160, 160)
		if absf(x_j) < 9 or near_obj.call(x_j, z_j, 15):
			continue
		bush.call(x_j, z_j)
	for i in 14:
		x_j = Utils.rand(-150, 150)
		z_j = Utils.rand(-150, 150)
		if absf(x_j) < 10 or near_obj.call(x_j, z_j, 16):
			continue
		log_f.call(x_j, z_j)
	for i in 16:
		x_j = Utils.rand(-150, 150)
		z_j = Utils.rand(-150, 150)
		if absf(x_j) < 10 or near_obj.call(x_j, z_j, 16):
			continue
		rock.call(x_j, z_j, Utils.rand(0.8, 1.7))
	# ---------- 战争沉浸感物件(灌木加密/枯木/藤蔓棚/弹药箱堆/伪装网棚/半埋橡皮艇/弹壳) ----------
	var buf := {}
	var push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	# 灌木加密(8 丛)
	for k in 8:
		for t in 40:
			var bx := Utils.rand(-150, 150)
			var bz := Utils.rand(-150, 150)
			if absf(bx) < 10 or near_obj.call(bx, bz, 18.0):
				continue
			bush.call(bx, bz)
			break
	# 枯木(倾斜深色圆柱,纯装饰)
	var dead_mat := _std(Color.html("#3a332a"), 1.0)
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if absf(bx) < 10 or near_obj.call(bx, bz, 18.0):
				continue
			if absf(bz - T.river) < 9 and absf(bx) < 18:
				continue
			var dw := _cyl(0.09, 0.13, Utils.rand(2.6, 4.2), 6, dead_mat)
			dw.rotation.z = Utils.rand(-0.25, 0.25)
			dw.rotation.x = Utils.rand(-0.25, 0.25)
			dw.position = Vector3(bx, G.ground_h.call(bx, bz) + 1.6, bz)
			dw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(dw)
			break
	# 藤蔓棚(木架 + 绿色斜板,2 组)
	var vine_mat := _std(Color.html("#2e4a2e"), 1.0)
	var jpost_mat := _std(Color.html("#4a3a26"), 1.0)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if absf(bx) < 10 or near_obj.call(bx, bz, 22.0):
				continue
			var grp := Node3D.new()
			for pp in [[-2.2, -1.8], [2.2, -1.8], [-2.2, 1.8], [2.2, 1.8]]:
				var post := _box(0.16, 2.8, 0.16, jpost_mat)
				post.position = Vector3(pp[0], 1.4, pp[1])
				grp.add_child(post)
			for sl in 4:
				var slat := _box(0.35, 0.06, 4.4, vine_mat)
				slat.position = Vector3(-1.65 + sl * 1.1, 2.9, 0)
				slat.rotation.y = Utils.rand(-0.15, 0.15)
				grp.add_child(slat)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			break
	# 伪装网棚(绿顶 + 四柱,2 组)
	var camo_mat := _std(Color.html("#3a5a2e"), 0.95)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if absf(bx) < 10 or near_obj.call(bx, bz, 22.0):
				continue
			var grp := Node3D.new()
			for pp in [[-2.0, -2.0], [2.0, -2.0], [-2.0, 2.0], [2.0, 2.0]]:
				var post := _box(0.14, 2.2, 0.14, jpost_mat)
				post.position = Vector3(pp[0], 1.1, pp[1])
				grp.add_child(post)
			var net := _box(4.6, 0.08, 4.6, camo_mat)
			net.position.y = 2.2
			net.rotation.x = Utils.rand(-0.12, 0.12)
			net.rotation.z = Utils.rand(-0.12, 0.12)
			grp.add_child(net)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			break
	# 弹药箱堆(底层 crate + 两层叠加木箱,3 组)
	var ammo_mat := _std_tex(Color.html("#8a6f4e"), 0.95, "plywood")
	var ubox3 := BoxMesh.new()
	ubox3.size = Vector3.ONE
	for k in 3:
		for t in 40:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if absf(bx) < 10 or near_obj.call(bx, bz, 20.0):
				continue
			crate.call(bx, bz)
			push.call(ammo_mat, ubox3, bx + Utils.rand(-0.2, 0.2), bz + Utils.rand(-0.2, 0.2), Utils.rand(-0.2, 0.2), 1.3, Vector3(1.3, 1.3, 1.3))
			add_collider.call(bx, 0.65, bz, 1.3, 1.3, 1.3)
			push.call(ammo_mat, ubox3, bx + Utils.rand(-0.2, 0.2), bz + Utils.rand(-0.2, 0.2), Utils.rand(-0.2, 0.2), 2.6, Vector3(1.3, 1.3, 1.3))
			add_collider.call(bx, 1.95, bz, 1.3, 1.3, 1.3)
			break
	# 半埋橡皮艇(低矮船壳,2 艘,带碰撞)
	var boat_mat := _std(Color.html("#2c4438"), 0.9, 0.1)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if absf(bx) < 10 or near_obj.call(bx, bz, 20.0):
				continue
			if absf(bz - T.river) > 30:
				continue
			var grp := Node3D.new()
			var hull := _cyl(0.5, 0.62, 3.6, 10, boat_mat)
			hull.rotation.z = PI / 2.0
			hull.position.y = 0.42
			grp.add_child(hull)
			var rim := _cyl(0.3, 0.3, 3.9, 8, _std(Color.html("#3a5848"), 0.9))
			rim.rotation.z = PI / 2.0
			rim.position = Vector3(0, 0.62, 0)
			grp.add_child(rim)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 3.6, 0.9, 1.3)
			break
	# 弹壳堆(金色极小圆柱簇,纯装饰)
	var shell_mat := _std(Color.html("#d9a520"), 0.4, 0.9)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.012
	shell_mesh.bottom_radius = 0.012
	shell_mesh.height = 0.07
	shell_mesh.radial_segments = 5
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-140, 140)
			var bz := Utils.rand(-140, 140)
			if absf(bx) < 10 or near_obj.call(bx, bz, 20.0):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# 远山天际线
	var hill_mat := _basic(Color.html("#5a7a52"), true)
	for i in 18:
		var a := i / 18.0 * TAU + Utils.rand(-0.15, 0.15)
		var r := Utils.rand(220, 300)
		var h := Utils.rand(25, 60)
		var m := _cone(Utils.rand(45, 75), h, 7, hill_mat)
		m.position = Vector3(cos(a) * r, h / 2 - 3, sin(a) * r)
		wg.add_child(m)


## ==================== 暮港码头(突破) ====================
static func _harbor_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, sandbag: Callable, car: Callable, barrier: Callable,
		container: Callable, cont_mats: Array, near_obj: Callable, roof_mat: Material) -> void:
	var ware_wall := _std_tex(Color.html("#7a8a9a"), 0.7, "corrugated_iron", 0.3)
	var ware_wall2 := _std_tex(Color.html("#9a8a7a"), 0.7, "corrugated_iron", 0.3)
	var crane_mat := _std_tex(Color.html("#c07840"), 0.7, "rusty_metal", 0.4)
	var bollard_mat := _std(Color.html("#2a2e33"), 0.8, 0.4)
	var warehouse := func(x: float, z: float, rot := 0.0) -> void:
		var gh: float = G.ground_h.call(x, z)
		var w := Utils.rand(16, 22)
		var d := Utils.rand(11, 14)
		var h := Utils.rand(7, 9)
		var b := _box(w, h, d, ware_wall if randf() < 0.5 else ware_wall2)
		b.rotation.y = rot
		b.position = Vector3(x, gh + h / 2.0, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var roof := _cyl(d * 0.42, d * 0.42, w + 0.6, 3, roof_mat)
		roof.rotation.z = PI / 2.0
		roof.rotation.x = PI
		roof.rotation.y = rot
		roof.position = Vector3(x, gh + h + d * 0.1, z)
		wg.add_child(roof)
		var cs := absf(cos(rot)) > 0.5
		add_collider.call(x, 0, z, w if cs else d, h, d if cs else w)
		minimap_rects.append({ "x": x, "z": z, "w": w if cs else d, "d": d if cs else w })
	var cont_stack := func(x: float, z: float, rot := 0.0) -> void:
		container.call(x, z, rot)
		if randf() < 0.55:
			var m := _box(6.2, 2.7, 2.5, Utils.choice(cont_mats))
			m.rotation.y = rot + Utils.rand(-0.06, 0.06)
			m.position = Vector3(x + Utils.rand(-0.3, 0.3), G.ground_h.call(x, z) + 2.7 + 1.35, z + Utils.rand(-0.3, 0.3))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(m)
	var crane := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		for lp in [[-7, -4], [7, -4], [-7, 4], [7, 4]]:
			var leg := _box(0.9, 21, 0.9, crane_mat)
			leg.position = Vector3(lp[0], 10.5, lp[1])
			g.add_child(leg)
		var beam := _box(26, 1.6, 2.2, crane_mat)
		beam.position.y = 21.5
		g.add_child(beam)
		var cab := _box(3.4, 2.6, 3, _std(Color.html("#3a424a"), 0.5, 0.5))
		cab.position = Vector3(Utils.rand(-6, 6), 19.5, 0)
		g.add_child(cab)
		var cable := _cyl(0.05, 0.05, 8, 4, bollard_mat)
		cable.position = Vector3(cab.position.x, 15, 0)
		g.add_child(cable)
		var hook_box := _box(1.6, 1.2, 1.2, crane_mat)
		hook_box.position = Vector3(cab.position.x, 10.6, 0)
		g.add_child(hook_box)
		g.position = Vector3(x, gh, z)
		_shadows_on(g)
		wg.add_child(g)
		for lp in [[-7, -4], [7, -4], [-7, 4], [7, 4]]:
			add_collider.call(x + lp[0], 0, z + lp[1], 1.2, 21, 1.2)
		minimap_rects.append({ "x": x, "z": z, "w": 16, "d": 9 })
	# 码头系缆桩
	var port_z := -150.0
	while port_z <= 150:
		for bx in [-101, 101]:
			var bo := _cyl(0.28, 0.34, 0.8, 8, bollard_mat)
			bo.position = Vector3(bx, G.ground_h.call(bx, port_z) + 0.4, port_z)
			wg.add_child(bo)
		port_z += 15
	# 路灯(黄昏发光)
	var lamp_mat := _basic(Color.html("#ffd9a0"), true)
	port_z = -140.0
	while port_z <= 140:
		for lx in [-11, 11]:
			if near_obj.call(lx, port_z, 14):
				continue
			var pole := _cyl(0.09, 0.12, 6.5, 6, bollard_mat)
			pole.position = Vector3(lx, G.ground_h.call(lx, port_z) + 3.25, port_z)
			wg.add_child(pole)
			var head := MeshInstance3D.new()
			var hsm := SphereMesh.new()
			hsm.radius = 0.28
			hsm.height = 0.56
			hsm.radial_segments = 8
			hsm.rings = 6
			head.mesh = hsm
			head.material_override = lamp_mat
			head.position = Vector3(lx, G.ground_h.call(lx, port_z) + 6.6, port_z)
			wg.add_child(head)
			add_collider.call(lx, 0, port_z, 0.4, 6.5, 0.4)
		port_z += 28
	# 区域布景
	for si in T.sectors.size():
		for o in T.sectors[si]:
			warehouse.call(o["x"] + (-17 if o["x"] < 0 else 17), o["z"] + Utils.rand(-4, 4), Utils.rand(-0.15, 0.15))
			cont_stack.call(o["x"] + Utils.rand(-6, 6), o["z"] + (-14 if si % 2 else 14), Utils.rand(-0.2, 0.2))
			barrel.call(o["x"] + Utils.rand(-8, 8), o["z"] + Utils.rand(-8, 8))
			crate.call(o["x"] + Utils.rand(-9, 9), o["z"] + Utils.rand(-9, 9))
	# 集装箱堆场
	for i in 34:
		var side := -1.0 if randf() < 0.5 else 1.0
		var x: float = side * Utils.rand(24, 92)
		var zz := Utils.rand(-150, 150)
		if near_obj.call(x, zz, 17):
			continue
		cont_stack.call(x, zz, 0.0 if randf() < 0.7 else PI / 2 + Utils.rand(-0.1, 0.1))
	# 仓库群
	for i in 8:
		var side := -1.0 if randf() < 0.5 else 1.0
		var x: float = side * Utils.rand(36, 88)
		var zz := Utils.rand(-140, 140)
		if near_obj.call(x, zz, 22):
			continue
		warehouse.call(x, zz, Utils.rand(-0.2, 0.2))
	crane.call(-34, 34)
	crane.call(36, 96)
	# 道具散布
	for i in 42:
		var roll := randi() % 5
		match roll:
			0: barrel.call(Utils.rand(-95, 95), Utils.rand(-150, 150))
			1: crate.call(Utils.rand(-95, 95), Utils.rand(-150, 150))
			2: sandbag.call(Utils.rand(-60, 60), Utils.rand(-140, 140), Utils.rand(PI))
			3: car.call(Utils.rand(-14, 14) + Utils.choice([-16.0, 16.0]), Utils.rand(-150, 150), PI / 2 + Utils.rand(-0.25, 0.25), Color.html("#5a6a7a"))
			4: barrier.call(Utils.rand(-40, 40), Utils.rand(-140, 140), Utils.rand(PI))
	# ---------- 战争沉浸感物件(木托盘/叉车/斜置集装箱/系缆绳/弹壳;拴船柱沿用既有系缆桩) ----------
	var buf := {}
	var push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	# 木托盘(矮平板 ×8,纯装饰)
	var pallet_mat := _std(Color.html("#8a6a44"), 0.9)
	var ubox4 := BoxMesh.new()
	ubox4.size = Vector3.ONE
	for k in 8:
		for t in 40:
			var bx := Utils.rand(-90, 90)
			var bz := Utils.rand(-140, 140)
			if near_obj.call(bx, bz, 15.0) or absf(bx) > 92:
				continue
			var pr := Utils.rand(TAU)
			push.call(pallet_mat, ubox4, bx, bz, pr, 0.06, Vector3(1.2, 0.12, 1.0))
			push.call(pallet_mat, ubox4, bx, bz, pr, 0.05, Vector3(0.1, 0.1, 1.0))
			push.call(pallet_mat, ubox4, bx + 0.5, bz, pr, 0.05, Vector3(0.1, 0.1, 1.0))
			break
	# 系缆绳(地面深色扁长条 ×4,纯装饰)
	var rope_mat := _std(Color.html("#1c1a18"), 1.0)
	var rope_mesh := BoxMesh.new()
	rope_mesh.size = Vector3(8.0, 0.02, 0.1)
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-92, 92)
			var bz := Utils.rand(-140, 140)
			if near_obj.call(bx, bz, 15.0):
				continue
			push.call(rope_mat, rope_mesh, bx, bz, Utils.rand(TAU), 0.012, Vector3.ONE)
			break
	# 斜置变形集装箱(2 个,带碰撞)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-85, 85)
			var bz := Utils.rand(-140, 140)
			if near_obj.call(bx, bz, 20.0) or absf(bx) > 92:
				continue
			container.call(bx, bz, Utils.choice([-0.3, 0.25, -0.2, 0.3]))
			break
	# 叉车(黄色车体 + 货叉,2 辆,带碰撞)
	var fork_mat := _std(Color.html("#d0a020"), 0.5, 0.5)
	var fork_dark := _std(Color.html("#3a3a3a"), 0.7, 0.4)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-80, 80)
			var bz := Utils.rand(-140, 140)
			if near_obj.call(bx, bz, 20.0) or absf(bx) > 92:
				continue
			var grp := Node3D.new()
			var bd := _box(2.1, 1.3, 1.05, fork_mat)
			bd.position.y = 0.85
			grp.add_child(bd)
			var mst := _box(0.3, 1.7, 1.05, fork_dark)
			mst.position = Vector3(1.15, 1.35, 0)
			grp.add_child(mst)
			for fk in [[0.35, 0.0], [-0.35, 0.0]]:
				var fork1 := _box(0.9, 0.1, 0.12, fork_dark)
				fork1.position = Vector3(1.55, 0.35, fk[0])
				grp.add_child(fork1)
			var rf2 := _box(1.5, 0.12, 1.1, fork_mat)
			rf2.position = Vector3(-0.2, 1.85, 0)
			grp.add_child(rf2)
			var whm := _std(Color.html("#161616"), 0.95)
			for wpp in [[-0.8, 0.55], [0.5, 0.55], [-0.8, -0.55], [0.5, -0.55]]:
				var wh := _cyl(0.3, 0.3, 0.25, 8, whm)
				wh.rotation.x = PI / 2.0
				wh.position = Vector3(wpp[0], 0.3, wpp[1])
				grp.add_child(wh)
			grp.rotation.y = Utils.rand(TAU)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 2.2, 1.9, 1.1)
			break
	# 弹壳堆(金色极小圆柱簇,纯装饰)
	var shell_mat := _std(Color.html("#d9a520"), 0.4, 0.9)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.012
	shell_mesh.bottom_radius = 0.012
	shell_mesh.height = 0.07
	shell_mesh.radial_segments = 5
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-92, 92)
			var bz := Utils.rand(-140, 140)
			if near_obj.call(bx, bz, 20.0) or absf(bx) > 92:
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# 远处货轮剪影(海上)
	var ship_mat := _basic(Color.html("#2e3440"), true)
	for sd in [[-165, -60, 0.2], [170, 70, -0.3]]:
		var ship := Node3D.new()
		var hull := _box(60, 9, 14, ship_mat)
		hull.position.y = 2
		ship.add_child(hull)
		var tower2 := _box(8, 12, 10, ship_mat)
		tower2.position = Vector3(-18, 10, 0)
		ship.add_child(tower2)
		for k in 4:
			var cc := _box(6.2, 2.7, 2.5, ship_mat)
			cc.position = Vector3(-6 + k * 8, 7, Utils.rand(-3, 3))
			ship.add_child(cc)
		ship.rotation.y = sd[2]
		ship.position = Vector3(sd[0], -0.55, sd[1])   # 吃水线对齐水面
		wg.add_child(ship)
	# 城市天际线(后方)
	var port_sky := _basic(Color.html("#4a4458"), true)
	for i in 20:
		var a := i / 20.0 * PI + Utils.rand(-0.08, 0.08)
		var r := Utils.rand(230, 300)
		var h := Utils.rand(25, 70)
		var b := _box(Utils.rand(16, 32), h, Utils.rand(16, 32), port_sky)
		b.position = Vector3(sin(a) * r * 0.4, h / 2 - 2, cos(a) * r + 60)
		wg.add_child(b)


## ==================== 暗夜雷达站(突破) ====================
static func _peak_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, sandbag: Callable, barrier: Callable, container: Callable,
		near_obj: Callable, rock_photo_mat: Material, roof_mat: Material) -> void:
	var bunker_mat := _std_tex(Color.html("#b0b6bc"), 1.0, "rough_concrete")
	var white_mat := _std(Color.html("#dde2e8"), 0.6, 0.2)
	var mast_mat := _std(Color.html("#8a4040"), 0.6, 0.5)
	var prefab_mat := _std_tex(Color.html("#9aa4ac"), 0.7, "metal_plate", 0.3)
	var beacon_mat := _basic(Color.html("#ff3020"), false)
	var lamp_head_mat := _basic(Color.html("#cfe4ff"), false)
	var lamp_pole_mat := _std(Color.html("#2a2e33"), 0.8, 0.4)
	var glow_tex := TerrainTextures.glow_texture()
	var lamp := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var pole := _cyl(0.08, 0.11, 5.6, 6, lamp_pole_mat)
		pole.position = Vector3(x, gh + 2.8, z)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(pole)
		var head := MeshInstance3D.new()
		var hsm := SphereMesh.new()
		hsm.radius = 0.22
		hsm.height = 0.44
		hsm.radial_segments = 8
		hsm.rings = 6
		head.mesh = hsm
		head.material_override = lamp_head_mat
		head.position = Vector3(x, gh + 5.7, z)
		wg.add_child(head)
		var glow := Sprite3D.new()
		glow.texture = glow_tex
		glow.pixel_size = 4.5 / 64.0
		glow.modulate = Color(0.75, 0.85, 1, 0.55)
		glow.position = Vector3(x, gh + 5.7, z)
		wg.add_child(glow)
		add_collider.call(x, 0, z, 0.35, 5.6, 0.35)
	var zz := -150.0
	while zz <= 150:
		lamp.call(-10.5, zz)
		lamp.call(10.5, zz + 15)
		zz += 30
	for sec in T.sectors:
		for o in sec:
			lamp.call(o["x"] + 9, o["z"] - 7)
			lamp.call(o["x"] - 9, o["z"] + 8)
	# ---------- 探照灯(投射阴影的光源;夜战氛围与战术照明) ----------
	var flood := func(x: float, z: float, aim_x: float, aim_z: float, shadow := false) -> void:
		var gh: float = G.ground_h.call(x, z)
		# 灯杆 + 灯头
		var pole := _cyl(0.1, 0.14, 7.2, 6, lamp_pole_mat)
		pole.position = Vector3(x, gh + 3.6, z)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(pole)
		var head_b := _box(0.5, 0.35, 0.6, lamp_pole_mat)
		head_b.position = Vector3(x, gh + 7.3, z)
		head_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(head_b)
		# 聚光灯(仅中央山包 + 基地前沿两盏投影,其余省阴影 pass)
		var spot := SpotLight3D.new()
		spot.light_color = Color.html("#cfe0ff")
		spot.light_energy = 9.0
		spot.spot_range = 55.0
		spot.spot_angle = 42.0
		spot.spot_attenuation = 1.2
		spot.shadow_enabled = shadow
		spot.position = Vector3(x, gh + 7.2, z)
		wg.add_child(spot)
		# 瞄准目标点
		var tgt := Node3D.new()
		tgt.position = Vector3(aim_x, G.ground_h.call(aim_x, aim_z), aim_z)
		wg.add_child(tgt)
		spot.look_at_from_position(spot.position, tgt.position, Vector3.UP)
		# 灯头发光片(自发光标记光源位置)
		var lamp_glow := Sprite3D.new()
		lamp_glow.texture = glow_tex
		lamp_glow.pixel_size = 6.0 / 64.0
		lamp_glow.modulate = Color(0.8, 0.88, 1, 0.7)
		lamp_glow.position = spot.position
		wg.add_child(lamp_glow)
		add_collider.call(x, 0, z, 0.4, 7.0, 0.4)
	# 部署探照灯:第一/二区域 + 中心山包 + 双方基地前沿(仅中央山包与攻击方基地前沿投影)
	var hs2: float = T.size / 2.0
	flood.call(12, T.sectors[0][0]["z"] - 14, 0, T.sectors[0][0]["z"])
	flood.call(-14, T.sectors[1][0]["z"] + 16, 0, T.sectors[1][0]["z"])
	flood.call(16, 2, 0, 0, true)
	flood.call(-16, -2, 0, 0)
	flood.call(8, -hs2 + 34, 0, -hs2 + 55, true)
	flood.call(-8, hs2 - 34, 0, hs2 - 55)
	# 雷达碟(地标)
	var radar := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		var base := _cyl(2.2, 2.8, 2.5, 10, bunker_mat)
		base.position.y = 1.25
		g.add_child(base)
		var ped := _cyl(0.5, 0.7, 3.5, 8, mast_mat)
		ped.position.y = 4.2
		g.add_child(ped)
		var dish := MeshInstance3D.new()
		var dm := SphereMesh.new()
		dm.radius = 4.2
		dm.height = 8.4
		dm.radial_segments = 16
		dm.rings = 8
		dm.is_hemisphere = true
		dish.mesh = dm
		dish.material_override = white_mat
		dish.position.y = 6.4
		dish.rotation.x = PI / 3.0
		g.add_child(dish)
		var feed := _cyl(0.06, 0.06, 3.4, 6, mast_mat)
		feed.position = Vector3(0, 7.4, 1.9)
		feed.rotation.x = PI / 3.0
		g.add_child(feed)
		g.position = Vector3(x, gh, z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 5, 6, 5)
		minimap_rects.append({ "x": x, "z": z, "w": 5, "d": 5 })
	# 天线桅杆
	var mast := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		var pole := _cyl(0.16, 0.3, 19, 7, mast_mat)
		pole.position.y = 9.5
		g.add_child(pole)
		for k in 3:
			var arm := _box(3.2 - k * 0.7, 0.12, 0.12, mast_mat)
			arm.position.y = 14 + k * 1.8
			arm.rotation.y = Utils.rand(PI)
			g.add_child(arm)
		var beacon := MeshInstance3D.new()
		var bsm := SphereMesh.new()
		bsm.radius = 0.22
		bsm.height = 0.44
		bsm.radial_segments = 8
		bsm.rings = 6
		beacon.mesh = bsm
		beacon.material_override = beacon_mat
		beacon.position.y = 19.2
		g.add_child(beacon)
		g.position = Vector3(x, gh, z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 0.7, 19, 0.7)
	# 碉堡
	var bunker := func(x: float, z: float, rot := 0.0) -> void:
		var w := Utils.rand(7, 10)
		var d := Utils.rand(6, 8)
		var h := Utils.rand(3, 4.2)
		var gh: float = G.ground_h.call(x, z)
		var b := _box(w, h, d, bunker_mat)
		b.rotation.y = rot
		b.position = Vector3(x, gh + h / 2.0, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var slit := _box(w * 0.8, 0.3, 0.1, _basic(Color.html("#1a1e22"), true))
		if absf(cos(rot)) > 0.5:
			slit.position = Vector3(x, gh + h * 0.65, z + d / 2.0 + 0.01)
		else:
			slit.rotation.y = PI / 2.0
			slit.position = Vector3(x + d / 2.0 + 0.01, gh + h * 0.65, z)
		wg.add_child(slit)
		var ww := w if absf(cos(rot)) > 0.5 else d
		add_collider.call(x, 0, z, ww, h, d if ww == w else w)
		minimap_rects.append({ "x": x, "z": z, "w": ww, "d": d if ww == w else w })
	# 预制营房(夜间亮窗)
	var win_mat := _basic(Color.html("#ffd98a"), false)
	var prefab := func(x: float, z: float, rot := 0.0) -> void:
		var gh: float = G.ground_h.call(x, z)
		var b := _box(8.5, 3.4, 5.5, prefab_mat)
		b.rotation.y = rot
		b.position = Vector3(x, gh + 1.7, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var rf := _box(9, 0.3, 6, roof_mat)
		rf.rotation.y = rot
		rf.position = Vector3(x, gh + 3.55, z)
		wg.add_child(rf)
		for side in [-1, 1]:
			var win := _box(3.2, 0.5, 0.06, win_mat)
			win.rotation.y = rot
			var off := Vector3(Utils.rand(-1.5, 1.5), 0, side * 2.78).rotated(Vector3.UP, rot)
			win.position = Vector3(x + off.x, gh + 2.0, z + off.z)
			wg.add_child(win)
		var cs := absf(cos(rot)) > 0.5
		add_collider.call(x, 0, z, 8.5 if cs else 5.5, 3.6, 5.5 if cs else 8.5)
		minimap_rects.append({ "x": x, "z": z, "w": 8.5 if cs else 5.5, "d": 5.5 if cs else 8.5 })
	var rock := func(x: float, z: float, s := 1.0) -> void:
		var r := _ico(Utils.rand(1, 2.4) * s, rock_photo_mat)
		r.position = Vector3(x, G.ground_h.call(x, z) + Utils.rand(0.3, 0.8) * s, z)
		r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(r)
		add_collider.call(x, 0, z, 2 * s, 1.6 * s, 2 * s)
	# 区域布景:前哨 / 雷达阵列 / 指挥中心
	var S_: Array = T.sectors
	bunker.call(S_[0][0]["x"] - 10, S_[0][0]["z"] + 8, 0.3)
	bunker.call(S_[0][1]["x"] + 10, S_[0][1]["z"] - 7, -0.4)
	prefab.call(S_[0][0]["x"] + 9, S_[0][0]["z"] - 10, 0.2)
	prefab.call(S_[0][1]["x"] - 11, S_[0][1]["z"] + 9, -0.2)
	radar.call(S_[1][0]["x"] - 8, S_[1][0]["z"] - 12)
	radar.call(S_[1][1]["x"] + 9, S_[1][1]["z"] + 12)
	radar.call(0, 18)
	mast.call(S_[1][0]["x"] + 12, S_[1][0]["z"] + 10)
	mast.call(S_[1][1]["x"] - 13, S_[1][1]["z"] - 10)
	mast.call(-6, -30)
	prefab.call(S_[2][0]["x"] - 12, S_[2][0]["z"] + 6, 0.15)
	prefab.call(S_[2][0]["x"] + 10, S_[2][0]["z"] - 11, -0.15)
	bunker.call(S_[2][1]["x"] + 9, S_[2][1]["z"] + 9, 0.25)
	bunker.call(S_[2][1]["x"] - 10, S_[2][1]["z"] - 8, -0.3)
	radar.call(S_[2][1]["x"] + 14, S_[2][1]["z"] - 2)
	mast.call(S_[2][0]["x"], S_[2][0]["z"] + 16)
	# 全图散布
	for i in 46:
		var x := Utils.rand(-160, 160)
		var bz1 := Utils.rand(-160, 160)
		if absf(x) < 10 or near_obj.call(x, bz1, 17):
			continue
		rock.call(x, bz1, Utils.rand(0.8, 2.2))
	for i in 10:
		var x := Utils.rand(-140, 140)
		var bz2 := Utils.rand(-140, 140)
		if absf(x) < 12 or near_obj.call(x, bz2, 20):
			continue
		if randf() < 0.5:
			bunker.call(x, bz2, Utils.rand(-0.4, 0.4))
		else:
			prefab.call(x, bz2, Utils.rand(-0.4, 0.4))
	# 道具
	for i in 36:
		var roll := randi() % 5
		match roll:
			0: crate.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			1: barrel.call(Utils.rand(-140, 140), Utils.rand(-140, 140))
			2: sandbag.call(Utils.rand(-60, 60), Utils.rand(-130, 130), Utils.rand(PI))
			3: barrier.call(Utils.rand(-50, 50), Utils.rand(-130, 130), Utils.rand(PI))
			4: container.call(Utils.rand(-90, 90), Utils.rand(-140, 140), Utils.rand(PI))
	# ---------- 战争沉浸感物件(导弹发射架/备用雷达碟/电缆卷筒/双联探照灯/防空沙袋工事/雪堆/屋顶天线阵列/弹壳) ----------
	var buf := {}
	var push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	# 导弹发射架(倾斜细管 ×2 组,空旷处,带碰撞)
	var ml_mat := _std(Color.html("#3a4a3a"), 0.6, 0.3)
	var ml_dark := _std(Color.html("#2a2e33"), 0.7, 0.4)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if near_obj.call(bx, bz, 26.0):
				continue
			var gh: float = G.ground_h.call(bx, bz)
			var grp := Node3D.new()
			var base := _box(1.8, 0.5, 1.8, ml_dark)
			base.position.y = 0.25
			grp.add_child(base)
			for tt in 3:
				var tube := _cyl(0.09, 0.11, 3.6, 8, ml_mat)
				tube.position = Vector3(-0.8 + tt * 0.8, 1.1, 0)
				tube.rotation.x = -0.55
				grp.add_child(tube)
			grp.rotation.y = Utils.rand(TAU)
			grp.position = Vector3(bx, gh, bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 1.8, 1.6, 1.8)
			break
	# 备用雷达碟(小三脚 + 碟形,2 组)
	var sdish_mat := _std(Color.html("#c8ccd2"), 0.5, 0.4)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if near_obj.call(bx, bz, 24.0):
				continue
			var grp := Node3D.new()
			for lp in 3:
				var ang := lp / 3.0 * TAU
				var leg := _cyl(0.05, 0.07, 1.6, 6, ml_dark)
				leg.position = Vector3(cos(ang) * 0.55, 0.8, sin(ang) * 0.55)
				leg.rotation.z = cos(ang) * 0.35
				leg.rotation.x = -sin(ang) * 0.35
				grp.add_child(leg)
			var dish := MeshInstance3D.new()
			var dm2 := SphereMesh.new()
			dm2.radius = 0.95
			dm2.height = 1.9
			dm2.radial_segments = 10
			dm2.rings = 6
			dm2.is_hemisphere = true
			dish.mesh = dm2
			dish.material_override = sdish_mat
			dish.position.y = 1.9
			dish.rotation.x = PI / 4.0
			grp.add_child(dish)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			add_collider.call(bx, 0, bz, 1.9, 2.6, 1.9)
			break
	# 电缆卷筒(双盘立式,4 个)
	var reel_mat := _std(Color.html("#7a5a3a"), 0.8, 0.2)
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-120, 120)
			var bz := Utils.rand(-120, 120)
			if near_obj.call(bx, bz, 20.0):
				continue
			var grp := Node3D.new()
			var disc1 := _cyl(0.85, 0.85, 0.09, 12, reel_mat)
			disc1.rotation.z = PI / 2.0
			disc1.position = Vector3(0, 0.34, -0.35)
			grp.add_child(disc1)
			var disc2 := _cyl(0.85, 0.85, 0.09, 12, reel_mat)
			disc2.rotation.z = PI / 2.0
			disc2.position = Vector3(0, 0.34, 0.35)
			grp.add_child(disc2)
			var core := _cyl(0.32, 0.32, 0.72, 10, reel_mat)
			core.rotation.z = PI / 2.0
			core.position.y = 0.34
			grp.add_child(core)
			grp.rotation.y = Utils.rand(TAU)
			grp.position = Vector3(bx, G.ground_h.call(bx, bz), bz)
			_shadows_on(grp)
			wg.add_child(grp)
			break
	# 双联探照灯(杆 + 双灯头,1 组,带碰撞)
	var twin := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var grp := Node3D.new()
		var pole2 := _cyl(0.09, 0.12, 6.0, 6, lamp_pole_mat)
		pole2.position.y = 3.0
		grp.add_child(pole2)
		var arm2 := _box(1.6, 0.14, 0.14, lamp_pole_mat)
		arm2.position = Vector3(0, 5.9, 0)
		grp.add_child(arm2)
		for hp in [[-0.45, 0.0], [0.45, 0.0]]:
			var hb := _box(0.5, 0.34, 0.55, lamp_pole_mat)
			hb.position = Vector3(hp[0], 5.95, hp[1])
			grp.add_child(hb)
			var hg2 := MeshInstance3D.new()
			var hsm2 := SphereMesh.new()
			hsm2.radius = 0.14
			hsm2.height = 0.28
			hsm2.radial_segments = 8
			hsm2.rings = 6
			hg2.mesh = hsm2
			hg2.material_override = lamp_head_mat
			hg2.position = Vector3(hp[0], 5.95, hp[1] - 0.22)
			grp.add_child(hg2)
		grp.position = Vector3(x, gh, z)
		_shadows_on(grp)
		wg.add_child(grp)
		add_collider.call(x, 0, z, 0.4, 6.0, 0.4)
	for k in 1:
		for t in 40:
			var bx := Utils.rand(-100, 100)
			var bz := Utils.rand(-100, 100)
			if near_obj.call(bx, bz, 26.0):
				continue
			twin.call(bx, bz)
			break
	# 防空沙袋工事(围圈 8 个一组,带碰撞)
	for k in 1:
		for t in 40:
			var rx := Utils.rand(-100, 100)
			var rz2 := Utils.rand(-100, 100)
			if near_obj.call(rx, rz2, 26.0):
				continue
			for a2 in 8:
				var ang := a2 / 8.0 * TAU
				sandbag.call(rx + cos(ang) * 3.0, rz2 + sin(ang) * 3.0, ang + PI / 2.0)
			break
	# 雪堆(白色扁球,纯装饰)
	var pk_snow_mat := _std(Color.html("#d8e0e8"), 0.95)
	var sph_u2 := SphereMesh.new()
	sph_u2.radius = 1.0
	sph_u2.height = 2.0
	sph_u2.radial_segments = 12
	sph_u2.rings = 8
	for k in 5:
		for t in 40:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if near_obj.call(bx, bz, 20.0):
				continue
			var s := Utils.rand(1.8, 3.0)
			push.call(pk_snow_mat, sph_u2, bx, bz, Utils.rand(TAU), 0.15, Vector3(s * 1.4, 0.3, s))
			break
	# 屋顶天线阵列(前哨预制营房屋顶,2 组)
	for ap in [[S_[0][0]["x"] + 9, S_[0][0]["z"] - 10], [S_[0][1]["x"] - 11, S_[0][1]["z"] + 9]]:
		var ax: float = ap[0]
		var az: float = ap[1]
		var gh: float = G.ground_h.call(ax, az)
		var grp := Node3D.new()
		for k2 in 4:
			var rod := _cyl(0.025, 0.025, 1.6, 5, mast_mat)
			rod.position = Vector3(-0.45 + k2 * 0.3, gh + 4.4, 0)
			grp.add_child(rod)
			var bar := _box(0.14, 0.03, 0.5, mast_mat)
			bar.position = Vector3(-0.45 + k2 * 0.3, gh + 4.3, 0.25)
			grp.add_child(bar)
		grp.position = Vector3(ax, gh, az)
		_shadows_on(grp)
		wg.add_child(grp)
	# 弹壳堆(金色极小圆柱簇,纯装饰)
	var shell_mat := _std(Color.html("#d9a520"), 0.4, 0.9)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = 0.012
	shell_mesh.bottom_radius = 0.012
	shell_mesh.height = 0.07
	shell_mesh.radial_segments = 5
	for k in 6:
		for t in 40:
			var bx := Utils.rand(-130, 130)
			var bz := Utils.rand(-130, 130)
			if near_obj.call(bx, bz, 20.0):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# 暗夜山脊剪影
	var mtn_mat := _basic(Color.html("#141e2c"), true)
	for i in 20:
		var a := i / 20.0 * TAU + Utils.rand(-0.12, 0.12)
		var r := Utils.rand(230, 310)
		var h := Utils.rand(70, 140)
		var m := _cone(Utils.rand(45, 75), h, 6, mtn_mat)
		m.position = Vector3(cos(a) * r, h / 2 - 4, sin(a) * r)
		wg.add_child(m)
	# 星空(密度随画质档位)
	var lv_star: int = GraphicsQuality.current_level
	var star_n := int(420 * [0.55, 0.75, 1.0, 1.25][lv_star])
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var star_mat := _particle_mat(Color(0.81, 0.88, 1, 0.85))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = star_n
	for i in star_n:
		var a := Utils.rand(TAU)
		var el := Utils.rand(0.12, 1.35)
		var r := 620.0
		var p := Vector3(cos(a) * cos(el) * r, sin(el) * r, sin(a) * cos(el) * r)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = star_mat
	wg.add_child(mmi)


## ==================== 突破模式战场氛围 ====================
static func _bt_battle_dressing(T, wg: Node3D, add_collider: Callable, size: float,
		sandbag: Callable, crate: Callable) -> void:
	var rubble_mat := _std_tex(Color.html("#9a9a9a"), 1.0, "rough_concrete")
	var hedge_mat := _std_tex(Color.html("#6a5a4a"), 0.7, "metal_plate", 0.5)
	var burnt_mat := _std(Color.html("#1e1c1a"), 1.0)
	var rubble := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for i in 4:
			var r := _ico(Utils.rand(0.2, 0.55), rubble_mat)
			r.position = Vector3(Utils.rand(-0.8, 0.8), Utils.rand(0.1, 0.35), Utils.rand(-0.8, 0.8))
			r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
			g.add_child(r)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.4, 0.6, 1.4)
	var hedgehog := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for i in 3:
			var beam := _box(0.14, 2.1, 0.14, hedge_mat)
			beam.rotation = Vector3(Utils.rand(-0.7, 0.7), Utils.rand(0, PI), Utils.rand(-0.7, 0.7))
			beam.position.y = 0.7
			g.add_child(beam)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.2, 1.4, 1.2)
	var burnt_wreck := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var body := _box(Utils.rand(2.5, 3.5), Utils.rand(0.8, 1.2), Utils.rand(1.4, 1.8), burnt_mat)
		body.position.y = 0.55
		body.rotation.y = Utils.rand(PI)
		g.add_child(body)
		g.position = Vector3(x, G.ground_h.call(x, z), z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 3, 1.3, 1.8)
	var near_obj2 := func(x: float, z: float, r: float) -> bool:
		for sec in T.sectors:
			for o in sec:
				var dx: float = x - o["x"]
				var dz: float = z - o["z"]
				if sqrt(dx * dx + dz * dz) < r:
					return true
		return false
	for i in 34:
		var x := Utils.rand(-70, 70)
		var dz := Utils.rand(-size / 2 + 18, size / 2 - 18)
		if absf(x) < 9 or near_obj2.call(x, dz, 15):
			continue
		var roll := randf()
		(rubble if roll < 0.45 else (hedgehog if roll < 0.75 else burnt_wreck)).call(x, dz)
	# 进攻通道掩体带
	for sec in T.sectors:
		var mid_z = (sec[0]["z"] + sec[1]["z"]) / 2.0
		for lz in [mid_z - 28, mid_z - 42]:
			for lx in [-21, -8, 8, 21]:
				if randf() < 0.8:
					var roll := randf()
					(rubble if roll < 0.4 else (hedgehog if roll < 0.65 else burnt_wreck)).call(lx + Utils.rand(-3, 3), lz + Utils.rand(-4, 4))
				if randf() < 0.55:
					sandbag.call(lx + Utils.rand(-2, 2), lz + Utils.rand(5, 9), Utils.rand(-0.5, 0.5))
				if randf() < 0.35:
					crate.call(lx + Utils.rand(-4, 4), lz + Utils.rand(-2, 2))
	G.map_fx["smokes"] = []
	var smoke_n: int = [4, 6, 8, 10][GraphicsQuality.current_level]
	for i in smoke_n:
		G.map_fx["smokes"].append({
			"x": Utils.rand(-70, 70),
			"z": Utils.rand(-size / 2 + 25, size / 2 - 25),
			"t": Utils.rand(0.2),
		})


## ==================== 每帧地图更新(旗帜/烟柱/降雪/雾密度) ====================
static var _update_frame := 0


static func update_map(dt: float) -> void:
	_update_frame += 1
	for f in G.flags:
		f.update_flag(dt)
	# 指数雾密度跟随雾距设置(运行时改画质/雾距实时生效;雾关闭的图不重算)
	if G.world_env != null and G.world_env.environment != null and G.map_fx.has("fog_density_base"):
		var e := G.world_env.environment
		if e.fog_enabled and e.fog_mode == Environment.FOG_MODE_EXPONENTIAL:
			var want := float(G.map_fx["fog_density_base"]) / maxf(float(G.settings.fog), 0.05)
			if not is_equal_approx(want, e.fog_density):
				e.fog_density = want
	# 战场烟柱
	if G.map_fx.has("smokes") and G.effects != null:
		for s in G.map_fx["smokes"]:
			s["t"] -= dt
			if s["t"] <= 0:
				s["t"] = 0.14
				var gy: float = (G.ground_h.call(s["x"], s["z"]) if G.ground_h.is_valid() else 0.0) + 0.6
				G.effects.smoke_spawn(
					s["x"] + Utils.rand(-0.6, 0.6), gy, s["z"] + Utils.rand(-0.6, 0.6),
					Utils.rand(-0.25, 0.25), Utils.rand(2.8, 4.5), Utils.rand(-0.25, 0.25),
					Utils.rand(1.6, 3.2), 0.16, 0.15, 0.14, -0.3)
	# 降雪
	if G.map_fx.has("snow") and G.camera != null:
		var snow: Dictionary = G.map_fx["snow"]
		var positions: PackedVector3Array = snow["positions"]
		var mm: MultiMesh = snow["mm"]
		var cam := G.camera.global_position
		var hg: Dictionary = G.map_fx.get("hgrid", {})
		var parity: int = _update_frame & 1
		for i in positions.size():
			var p := positions[i]
			var y: float = p.y - dt * Utils.rand(2, 4)
			var x: float = p.x + dt * 0.8
			# 着地判定:隔帧采样预烘焙 4m 高度网格(避免逐帧噪声求值)
			var gy := 0.0
			if not hg.is_empty() and (i & 1) == parity:
				gy = _hgrid_h(hg, x, p.z)
			if y < gy:
				y += 30
			if x - cam.x > 35: x -= 70
			if x - cam.x < -35: x += 70
			var z := p.z
			if z - cam.z > 35: z -= 70
			if z - cam.z < -35: z += 70
			positions[i] = Vector3(x, y, z)
			# transform 按奇偶帧对半写入(每帧只更新一半实例,位置数组仍逐帧推进)
			if (i & 1) == parity:
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))


## ==================== 3A 草地系统(MultiMesh 单次绘制 + 风摆动 + 距离淡出) ====================
static var _grass_shader_res: Shader = null


static var _grass_shader_code := """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(0.35, 0.5, 0.25, 1.0);
uniform float sway_amp = 0.5;
uniform float sway_speed = 2.2;
uniform float fade_near = 1.8;
uniform float fade_far = 140.0;
uniform float fade_len = 40.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float d = distance(CAMERA_POSITION_WORLD, wp);
	float fade = smoothstep(fade_near, fade_near + 1.6, d) * (1.0 - smoothstep(fade_far, fade_far + fade_len, d));
	COLOR.a = fade;
	float s1 = sin(TIME * sway_speed + wp.x * 0.55 + wp.z * 0.37);
	float s2 = sin(TIME * sway_speed * 1.7 + ph * 6.28 + wp.x * 0.2);
	VERTEX.x += (s1 * 0.7 + s2 * 0.3) * sway_amp * VERTEX.y;
	VERTEX.z += s2 * 0.24 * sway_amp * VERTEX.y;
}

void fragment() {
	float v = fract(sin(dot(UV, vec2(41.17, 29.3))) * 257.7);
	ALBEDO = tint.rgb * (0.72 + 0.55 * v);
	ALPHA = COLOR.a * smoothstep(0.0, 0.18, UV.y) * (0.75 + 0.25 * v);
	ROUGHNESS = 1.0;
}
"""


static func _grass_shader() -> Shader:
	if _grass_shader_res == null:
		var sh := Shader.new()
		sh.code = _grass_shader_code
		_grass_shader_res = sh
	return _grass_shader_res


static func _grass_mat(tint: Color, fade_far := 140.0, fade_len := 40.0) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _grass_shader()
	sm.set_shader_parameter("tint", tint)
	sm.set_shader_parameter("fade_far", fade_far)
	sm.set_shader_parameter("fade_len", fade_len)
	return sm


## 草地散布:按画质档位实例化,避开道路/河道/建筑/旗帜圈
static func add_grass(wg: Node3D, theme_id: String, is_bt: bool, T, lv: int) -> void:
	if theme_id == "snow":
		return
	var base_count: int = [600, 1400, 2400, 3300][lv]
	var web := OS.has_feature("web")
	var count := int(base_count * (0.45 if web else 1.0) * clampf(G.settings.particles, 0.35, 1.0))
	if count <= 0:
		return
	var size: float = T.size
	var road: float = T.road
	var river: float = -9999.0 if T.river == null else T.river
	var sea: bool = T.sea
	var tints := {
		"city": Color.html("#5f7148"), "desert": Color.html("#94865a"),
		"bt_jungle": Color.html("#3f5d30"), "bt_harbor": Color.html("#5d6a52"),
		"bt_peak": Color.html("#7d8686"),
	}
	var mat := _grass_mat(tints.get(theme_id, tints["city"]), [85.0, 100.0, 125.0, 140.0][lv], [28.0, 30.0, 35.0, 40.0][lv])
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.34)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var placed := 0
	var attempts := 0
	# 20m 空间哈希:碰撞盒先注册到覆盖格,只查候选点 3×3 邻格内的盒子
	# (避免 ULTRA 城市图每次尝试遍历全部 ~400 碰撞盒的 O(N) 开销)
	var cell := 20.0
	var hash_grid := {}
	for ci in G.colliders.size():
		var b: AABB = G.colliders[ci]
		var c0x := int(floor(b.position.x / cell))
		var c0z := int(floor(b.position.z / cell))
		var c1x := int(floor(b.end.x / cell))
		var c1z := int(floor(b.end.z / cell))
		for cx in range(c0x, c1x + 1):
			for cz in range(c0z, c1z + 1):
				var key := Vector2i(cx, cz)
				if not hash_grid.has(key):
					hash_grid[key] = []
				(hash_grid[key] as Array).append(ci)
	while placed < count and attempts < count * 15:
		attempts += 1
		var x := Utils.rand(-size / 2 + 6, size / 2 - 6)
		var z := Utils.rand(-size / 2 + 6, size / 2 - 6)
		if not is_bt:
			var on_road := false
			for r in [-road, 0.0, road]:
				if absf(x - r) < 8.5 or absf(z - r) < 8.5:
					on_road = true
					break
			if on_road:
				continue
		else:
			if absf(x) < 8.0:
				continue
			if river > -9990.0 and absf(z - river) < 6.0:
				continue
			if sea and absf(x) > 96.0:
				continue
		var near_c := false
		var pcx := int(floor(x / cell))
		var pcz := int(floor(z / cell))
		for dxc in [-1, 0, 1]:
			for dzc in [-1, 0, 1]:
				var list = hash_grid.get(Vector2i(pcx + dxc, pcz + dzc))
				if list == null:
					continue
				for ci2 in list:
					var b2: AABB = G.colliders[ci2]
					var bc := b2.get_center()
					var bh := b2.size * 0.5
					var dx := maxf(absf(x - bc.x) - bh.x, 0.0)
					var dz := maxf(absf(z - bc.z) - bh.z, 0.0)
					if dx * dx + dz * dz < 5.76:
						near_c = true
						break
				if near_c:
					break
			if near_c:
				break
		if near_c:
			continue
		var near_f := false
		for f in G.flags:
			var dx: float = x - f.pos.x
			var dz: float = z - f.pos.z
			if dx * dx + dz * dz < 144.0:
				near_f = true
				break
		if near_f:
			continue
		var gy: float = G.ground_h.call(x, z)
		var t := Transform3D(Basis(Vector3.UP, Utils.rand(TAU)), Vector3(x, gy + 0.01, z))
		t = t.scaled(Vector3(Utils.rand(0.75, 1.35), Utils.rand(0.85, 1.3), Utils.rand(0.75, 1.35)))
		mm.set_instance_transform(placed, t)
		placed += 1
	if placed > 0:
		mm.instance_count = placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(mmi)


## 地表碎石散落(战争氛围细节,不参与碰撞;MultiMesh 单次绘制)
static func _add_surface_stones(wg: Node3D, count: int, mat: Material) -> void:
	if count <= 0:
		return
	var size: float = G.world_size * 2.0
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = count
	for i in count:
		var x := Utils.rand(-size / 2 + 4, size / 2 - 4)
		var z := Utils.rand(-size / 2 + 4, size / 2 - 4)
		var gy: float = G.ground_h.call(x, z)
		var s := Utils.rand(0.08, 0.26)
		var b := Basis.from_euler(Vector3(Utils.rand(TAU), Utils.rand(TAU), Utils.rand(TAU)))
		b = b.scaled(Vector3(s, s * Utils.rand(0.8, 1.3), s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(x, gy + s * 0.4, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wg.add_child(mmi)
