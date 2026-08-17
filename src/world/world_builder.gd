class_name WorldBuilder
## 地图构建器(对应 map.js 的 buildWorld / updateMap)




## ==================== 地形高度场(全图平地) ====================
## 地形统一为 y=0 平地(修复地形数据 bug 的最终方案):
## 建筑/载具/出生点/粒子全部经由 G.ground_h 对齐,返回恒 0 即可。
static func make_ground_h(_theme_id: String, _size: float, _road: float) -> Callable:
	# 征服模式:恒 0 平地
	return func(_x: float, _z: float) -> float:
		return 0.0


## 平滑步进(两端导数归零):过渡区 C¹ 连续,消除线性过渡/if 分支的斜率跳变
## (载具高速经过 0.05-0.11 rad 坡度跳变 → 车体瞬间倾斜/视觉穿地,已实测)
static func _sstep(t: float) -> float:
	var s := clampf(t, 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s)


static func make_bt_ground_h(_T, _size: float) -> Callable:
	# 突破模式:恒 0 平地(河道/海岸平滑压平逻辑已无意义)
	return func(_x: float, _z: float) -> float:
		return 0.0


static func make_br_ground_h(T) -> Callable:
	# BR 山谷:河谷低地滚动起伏 + 东西山脊抬升 + 河床凹陷(世界高度场)
	var half: float = T.size / 2.0
	var river_x: float = T.river
	return func(x: float, z: float) -> float:
		var roll: float = sin(x * 0.028 + z * 0.017) * 2.2 \
			+ sin(x * 0.061 + z * 0.043) * 1.1 + sin(z * 0.09 + 2.3) * 0.8
		var dx := absf(x)
		var ridge := 0.0
		if dx > 190.0:
			var t0 := (dx - 190.0) / maxf(half - 190.0, 1.0)
			t0 = t0 * t0
			ridge = 6.0 * t0 + 10.0 * t0 * t0
		ridge *= 1.0 + sin(z * 0.011 + x * 0.004) * 0.3
		# 河道压平(水面贴合,防穿帮) + 河床凹陷(两岸可见)
		# [VEH-FIX] 平滑步进替代线性 lerp:消除 rd=46/26 处斜率跳变(实测 0.048-0.062 rad)
		var rd := absf(x - river_x)
		var w := WorldBuilder._sstep((46.0 - rd) / 20.0)
		roll *= 1.0 - w
		# 河床凹陷:平滑锥替代线性 V(消除 rd=0 尖角 0.1125 rad 双向斜率跳变)
		var dip := 0.9 * (1.0 - WorldBuilder._sstep(rd / 16.0))
		return roll + ridge - dip


static func make_snow_ground_h(T) -> Callable:
	# 雪山哨站:全图滚动起伏 ±2.5m + 东北角(+x,-z)雪山坡地抬升 4-8m。
	# 抬升自 x>95 / z<-95 起平滑步进过渡(C¹,两端导数归零),哨站区/建筑带(|x|,|z| ≤ 90)保持平缓,
	# 角部(边界墙 154m 内)叠加后约 4.5-7.5m;TDM 120m 圈定区域(|x|,|z|≤60)天然无抬升。
	return func(x: float, z: float) -> float:
		var roll: float = sin(x * 0.021 + z * 0.015) * 1.5 \
			+ sin(x * 0.051 + z * 0.037) * 0.7 + sin(z * 0.082 + 2.1) * 0.45
		# [VEH-FIX] 平滑步进替代线性 clamp:消除 x=95/180、z=-95/-180 处斜率跳变(实测 0.07 rad)
		var nx := WorldBuilder._sstep((x - 95.0) / 85.0)
		var nz := WorldBuilder._sstep((-z - 95.0) / 85.0)
		var ne := 12.0 * nx * nz
		ne *= 1.0 + sin(z * 0.02 + x * 0.011) * 0.25
		return roll + ne


static func make_jungle_ground_h(T) -> Callable:
	# 丛林河谷(突破):主河道凹陷 + 两岸起伏 ±2m + 周边丘陵 3-5m(世界高度场)。
	# 河道沿 z 轴(T.river,丛林 -55):河床 -0.8m 凹陷且 40m 带内起伏压平(水面 y=0.2 贴合);
	# 两岸(距河道 40-110m)±2m 起伏;周边丘陵自距河道 110m+(北岸 z>55 / 远南缘 z<-165)
	# 与东西缘 |x|>135 起抬升 3-5m,主战区(目标点带 z∈[-110,110])保持缓起伏。
	var river: float = T.river if T.river != null else -55.0
	return func(x: float, z: float) -> float:
		var roll: float = sin(x * 0.019 + z * 0.014) * 1.1 \
			+ sin(x * 0.05 + z * 0.035) * 0.55 + sin(z * 0.08 + 2.3) * 0.35
		var dist := absf(z - river)
		# 河道压平(水面贴合,防穿帮) + 河床凹陷(两岸可见)
		# [VEH-FIX] 平滑步进替代线性 lerp:消除 dist=40/22 处斜率跳变(实测 0.04-0.06 rad)
		var w := WorldBuilder._sstep((40.0 - dist) / 18.0)
		roll *= 1.0 - w
		# 河床凹陷:平滑锥替代线性 V(消除 dist=0 尖角 0.08 rad 双向斜率跳变)
		var dip := 0.8 * (1.0 - WorldBuilder._sstep(dist / 20.0))
		# 周边丘陵:北岸/远南缘 + 东西缘抬升 3-5m
		# [VEH-FIX] 平滑步进替代线性 clamp(消除 dist=110/190、|x|=135/175 斜率跳变);
		# smooth-max 替代 maxf(消除 hz==hx 折线脊的导数跳变)
		var hz := WorldBuilder._sstep((dist - 110.0) / 80.0)
		var hx := WorldBuilder._sstep((absf(x) - 135.0) / 40.0)
		var hd := hz - hx
		var hill := 0.5 * (hz + hx + sqrt(hd * hd + 0.0004))
		hill = 4.5 * hill * hill
		hill *= 1.0 + sin(x * 0.013 + z * 0.02) * 0.2
		# [BASE-FLAT] 南北基地带(|z|>150)丘陵平滑压平:消除出生点被地形山脊包裹的
		# "碗状"观感,载具出生区平坦,路基不再架在山脊上(棕色悬浮板)
		hill *= 1.0 - WorldBuilder._sstep((absf(z) - 150.0) / 45.0)
		return roll + hill - dip


## ==================== 共享材质工具 ====================
## [3A 8/10] 递归设置视距裁剪(LOD:远处粗模=不渲染,雾内保留精模)
static func _set_lod_range(n: Node, end: float, margin: float) -> void:
	if n.get_meta("no_lod", false):
		return
	if n is GeometryInstance3D:
		n.visibility_range_end = end
		n.visibility_range_end_margin = margin
	for ch in n.get_children():
		_set_lod_range(ch, end, margin)
## HD 贴图优先(res://textures/hd/ 下的 ambientCG 4K 材质:diff/nor/rough/ao),
## 缺失时回退 textures/ 旧贴图(rough/ao 缺失则用单一 float 粗糙度)
## [FIX 8/10] 用 ImageTexture 而非 ctex:导出 exe 重打包贴图时丢失 sRGB 标志,
## 纹理被当 linear 采样导致整图变亮(实测同帧亮度差 4 倍,城市地面发白像雪地)。
## ImageTexture(RGBA8) 保证 sRGB 空间正确;Web 端无文件系统,回退 load(ctex)。
static func _load_tex(tex_name: String, suffix: String):
	# [FIX 8/10 根因] 不能用 FileAccess.file_exists 判断 res:// 路径:
	# 导出 exe 中 pck 内资源没有文件系统条目,file_exists 恒 false → 贴图全部加载失败
	# 材质变纯色(混凝土白 tint → 地面发白像雪地)。
	# 用 ResourceLoader.exists(资源系统检查,对 pck 可靠) + load() 经 .import remap 加载。
	var p := "res://textures/hd/" + tex_name + "_" + suffix + ".jpg"
	if ResourceLoader.exists(p):
		return load(p)
	p = "res://textures/" + tex_name + "_" + suffix + ".jpg"
	if ResourceLoader.exists(p):
		return load(p)
	return null


static func _std_tex(color: Color, rough: float, tex_name: String, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_repeat = true
	var diff: Texture2D = _load_tex(tex_name, "diff")
	if diff != null:
		m.albedo_texture = diff
	var nor: Texture2D = _load_tex(tex_name, "nor")
	if nor != null:
		m.normal_enabled = true
		m.normal_texture = nor
	var rough_tex: Texture2D = _load_tex(tex_name, "rough")
	if rough_tex != null:
		m.roughness_texture = rough_tex
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao_tex: Texture2D = _load_tex(tex_name, "ao")
	if ao_tex != null:
		m.ao_enabled = true
		m.ao_texture = ao_tex
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
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
## [PERF] end_dist > 0:视距裁剪(end_dist 全隐,end_dist*0.75 起渐变淡出;800m BR 图植被用)
## [PERF] shadows=false:关闭阴影投射(小体积植被,省 4 级 cascade 重渲染)
static func _flush_prop_mm(wg: Node3D, buf: Dictionary, end_dist := 0.0, shadows := true) -> void:
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
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if end_dist > 0.0:
			mmi.visibility_range_end = end_dist
			mmi.visibility_range_end_margin = end_dist * 0.25
		wg.add_child(mmi)


## 预烘焙 2m 分辨率地形高度网格(供粒子/雪花着地判定 + raycast_world 地形步进,免逐帧噪声求值)
static func _bake_hgrid() -> Dictionary:
	var res := 2.0
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
	g.add_to_group("enterable")
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


## ==================== 可进入室内房(外壳 + 内部隔断墙 + 家具掩体) ====================
## 双房间布局:前厅(门在 -Z)+ 隔断墙(z=0,居中 1.5m 门洞)+ 里间;
## 室内桌/箱/柜作为掩体(带碰撞);rot 仅支持 0/PI,保证 AABB 碰撞轴对齐
static func build_enterable_house(wg: Node3D, x: float, z: float, rot: float, wall_mat: Material, roof_mat2: Material,
		wood_mat: Material, add_collider: Callable, minimap_rects: Array) -> void:
	var W := 8.0
	var D := 6.6
	var H := 3.3
	var T := 0.26
	var DW := 1.5
	var DH := 2.3
	var PW := 3.2   # 隔断墙单段宽(居中留 1.5 门洞)
	var gh: float = G.ground_h.call(x, z)
	var g := Node3D.new()
	g.name = "EnterableHouse"
	var mk := func(lx: float, ly: float, lz: float, w: float, h: float, d: float) -> void:
		var m := _box(w, h, d, wall_mat)
		m.position = Vector3(lx, ly, lz)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(m)
	# 外壳:后墙(+Z)与左右墙
	mk.call(0, H / 2, D / 2 - T / 2, W, H, T)
	mk.call(-W / 2 + T / 2, H / 2, 0, T, H, D)
	mk.call(W / 2 - T / 2, H / 2, 0, T, H, D)
	# 前墙(-Z):门两侧 + 门楣
	var seg := (W - DW) / 2.0
	mk.call(-(DW + seg) / 2.0, H / 2, -D / 2 + T / 2, seg, H, T)
	mk.call((DW + seg) / 2.0, H / 2, -D / 2 + T / 2, seg, H, T)
	mk.call(0, DH + (H - DH) / 2, -D / 2 + T / 2, DW, H - DH, T)
	# 内部隔断墙(z=0 横向,居中门洞):左右段 + 门楣
	mk.call(-(PW + DW / 2), H / 2, T / 2, PW, H, T)
	mk.call(PW + DW / 2, H / 2, T / 2, PW, H, T)
	mk.call(0, DH + (H - DH) / 2, T / 2, DW, H - DH, T)
	# 屋顶
	var roof := _box(W + 0.5, 0.22, D + 0.5, roof_mat2)
	roof.position = Vector3(0, H + 0.11, 0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(roof)
	# 窗户(贴侧墙黑色窗板,装饰无碰撞)
	var win_mat := _basic(Color.html("#1a1e22"), true)
	for wl in [[-1, D / 4], [-1, -D / 4], [1, D / 4], [1, -D / 4]]:
		var win := _box(0.08, 0.95, 1.15, win_mat)
		win.position = Vector3(wl[0] * (W / 2 - 0.06), 2.0, wl[1])
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(win)
	# 家具掩体:前厅木桌 + 木箱,里间立柜 + 木桌;长凳纯装饰
	var f_table := _box(1.6, 0.75, 0.9, wood_mat)
	f_table.position = Vector3(-2.4, 0.375, -2.5)
	f_table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(f_table)
	var f_crate := _box(0.8, 0.8, 0.8, wall_mat)
	f_crate.position = Vector3(2.3, 0.4, -2.7)
	f_crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(f_crate)
	var f_cab := _box(1.0, 1.9, 0.5, wood_mat)
	f_cab.position = Vector3(2.5, 0.95, D / 2 - 0.3)
	f_cab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(f_cab)
	var f_table2 := _box(1.4, 0.7, 0.8, wood_mat)
	f_table2.position = Vector3(-2.3, 0.35, 2.3)
	f_table2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(f_table2)
	var bench := _box(2.0, 0.42, 0.5, wood_mat)
	bench.position = Vector3(0.6, 0.21, 1.2)
	bench.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(bench)
	g.rotation.y = rot
	g.position = Vector3(x, gh, z)
	g.add_to_group("enterable")
	wg.add_child(g)
	# 复合碰撞(rot ∈ {0, PI}:局部→世界 = sgn 翻转)
	var sgn := 1.0 if rot == 0.0 else -1.0
	add_collider.call(x + 0, 0, z + sgn * (D / 2 - T / 2), W, H, T)
	add_collider.call(x + sgn * (-W / 2 + T / 2), 0, z, T, H, D)
	add_collider.call(x + sgn * (W / 2 - T / 2), 0, z, T, H, D)
	add_collider.call(x + sgn * (-(DW + seg) / 2.0), 0, z + sgn * (-D / 2 + T / 2), seg, H, T)
	add_collider.call(x + sgn * ((DW + seg) / 2.0), 0, z + sgn * (-D / 2 + T / 2), seg, H, T)
	add_collider.call(x + 0, DH, z + sgn * (-D / 2 + T / 2), DW, H - DH, T)  # 门楣(高于头顶)
	add_collider.call(x + sgn * (-(PW + DW / 2) + PW / 2), 0, z + sgn * (T / 2), PW, H, T)   # 隔断左段
	add_collider.call(x + sgn * (PW + DW / 2 + PW / 2), 0, z + sgn * (T / 2), PW, H, T)      # 隔断右段
	add_collider.call(x + 0, DH, z + sgn * (T / 2), DW, H - DH, T)                            # 隔断门楣
	add_collider.call(x + sgn * -2.4, 0, z + sgn * -2.5, 1.6, 0.75, 0.9)                      # 前厅木桌
	add_collider.call(x + sgn * 2.3, 0, z + sgn * -2.7, 0.8, 0.8, 0.8)                        # 木箱
	add_collider.call(x + sgn * 2.5, 0, z + sgn * (D / 2 - 0.3), 1.0, 1.9, 0.5)               # 立柜
	add_collider.call(x + sgn * -2.3, 0, z + sgn * 2.3, 1.4, 0.7, 0.8)                        # 里间木桌
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
	# TDM 圈定:5 张主题图(tdm_ok)按 120m 等比缩放(与 tdm_city 同规格)。
	# 副本方式:size/road/river/sectors 同步缩放,布局 sc 同步传入主题构建函数;
	# 原始 MapDef 不动(conquest/breakthrough 回归零影响)。
	var is_tdm: bool = T.mode == "tdm" or G.mode == "tdm"
	var tdm_sc := 1.0
	if is_tdm and T.tdm_ok:
		tdm_sc = 120.0 / T.size
		var T2 := MapsData.MapDef.new()
		for kp in T.get_property_list():
			if kp.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				T2.set(kp.name, T.get(kp.name))
		T2.size = 120.0
		T2.road = T.road * tdm_sc
		if T.river != null:
			T2.river = (T.river as float) * tdm_sc
		if not T.sectors.is_empty():
			var sec2 := []
			for row in T.sectors:
				var row2 := []
				for o in row:
					row2.append({ "id": o["id"], "x": o["x"] * tdm_sc, "z": o["z"] * tdm_sc })
				sec2.append(row2)
			T2.sectors = sec2
		T = T2
	var size: float = T.size
	var road: float = T.road
	var is_bt: bool = T.mode == "breakthrough" and not is_tdm
	var is_br: bool = T.mode == "br"
	var theme: String = T.theme if T.theme != "" else theme_id   # 外观主题(tdm_city 复用 city)
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

	# 地形高度场(按主题分发:snow 雪山起伏 / bt_jungle 河谷起伏 / br 山谷起伏;
	# 其余保持平地。TDM 圈定副本(T2)同走本分支,圈定区域内地形起伏自动保留)
	if is_br:
		G.ground_h = make_br_ground_h(T)
		G.ground_flat = false
	elif theme_id == "snow":
		G.ground_h = make_snow_ground_h(T)
		G.ground_flat = false
	elif theme_id == "bt_jungle":
		G.ground_h = make_jungle_ground_h(T)
		G.ground_flat = false
	else:
		G.ground_h = make_bt_ground_h(T, size) if is_bt else make_ground_h(theme_id, size, road)
		G.ground_flat = true  # 征服/突破其余图均恒 0 平地
	# [PERF] 非平地地图烘焙 4m 高度网格(raycast_world 地形步进双线性插值,免逐点 Callable 求值)
	if G.ground_flat:
		G.ground_grid = {}
	else:
		G.ground_grid = _bake_hgrid()

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
	var tod_time := { "city": 13.0, "desert": 15.2, "snow": 10.0, "bt_jungle": 12.2, "bt_harbor": 16.4, "bt_peak": 22.0, "br_valley": 14.0 }
	sky3d.game_time_enabled = false
	sky3d.tod.current_time = tod_time.get(theme, 12.5)
	# 每图亮度系数表(修复全图过亮/雪地最严重;bt_peak 暗夜保持原值)
	var exp_k: float = { "city": 0.86, "desert": 0.8, "snow": 0.66, "bt_jungle": 0.82, "bt_harbor": 0.86, "bt_peak": 1.0, "br_valley": 0.85 }.get(theme, 0.86)
	var sun_k: float = { "city": 0.9, "desert": 0.85, "snow": 0.7, "bt_jungle": 0.9, "bt_harbor": 0.9, "bt_peak": 1.0, "br_valley": 0.88 }.get(theme, 0.9)
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
		"br_valley": { "cov": 0.5, "cloud": 0.62, "wind": 1.0 },
	}
	var sc: Dictionary = sky_cfg.get(theme, sky_cfg["city"])
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
	if theme == "city":
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
	var vfog := hi and not web and theme != "city"
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
	var gn: int = q_grid[lv] + (10 if is_bt else 0) + (48 if is_br else 0)
	# 1) 预计算全部网格点高度
	var heights := []
	heights.resize(gn + 1)
	for i in gn + 1:
		var row := PackedFloat32Array()
		row.resize(gn + 1)
		heights[i] = row
	for i in gn + 1:
		var row: PackedFloat32Array = heights[i]
		for j in gn + 1:
			var x: float = -size / 2 + size * i / gn
			var gz: float = -size / 2 + size * j / gn
			row[j] = G.ground_h.call(x, gz)
		heights[i] = row
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
	ground.set_meta("no_lod", true)   # [8/10] 地形不参与 LOD 裁剪(裁掉会出现空洞)
	# 3A 地面:多层纹理混合(路线图底层 + 岩层/沙雪/混凝土细节层 + 宏观噪声)
	ground.material_override = TerrainTextures.make_ground_material(theme, T)
	wg.add_child(ground)

	# 突破地图水体(3A 水面:折射 + 天空反射 + 波动法线;水面略高于平地形成浅滩)
	# 河面横向加长:河道视觉上延伸出地图两侧(配合自然边界,而非在地图边缘截断)
	if is_bt and T.river != null:
		var water := MeshInstance3D.new()
		var wpm := PlaneMesh.new()
		wpm.size = Vector2(size + 260, 22)
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

	# BR 山谷河流(北南贯穿河谷:河道地形已压平 + 河床凹陷,水面略高于河床形成两岸)
	if T.mode == "br" and T.river != null:
		var brw := MeshInstance3D.new()
		var bwpm := PlaneMesh.new()
		bwpm.size = Vector2(24, size)
		bwpm.subdivide_width = 3
		bwpm.subdivide_depth = 48
		brw.mesh = bwpm
		brw.material_override = TerrainTextures.make_water_material(
			Color.html("#1d4a45"), Color.html("#2e6a5c"), 0.16, 0.9)
		brw.position = Vector3(T.river, -0.35, 0)
		brw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(brw)

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

	# [PERF] 车辆 MultiMesh 批绘(车身 5 色 + 驾驶舱 + 车轮,各 1 材质 1 draw;原每车 6 独立 mesh)
	var car_colors := [Color.html("#5a6a7a"), Color.html("#7a5a4a"), Color.html("#4a5a4a"), Color.html("#6a6a6a"), Color.html("#8a7a3a")]
	var car_body_mats := {}
	for _cc in car_colors:
		car_body_mats[_cc] = _std(_cc, 0.5, 0.6)
	var car_cab_mat := _std(Color.html("#1a2028"), 0.2, 0.8)
	var car_wheel_mat := _std(Color.html("#14161a"), 0.9)
	var car_glass_mat := _std(Color.html("#1c2a36"), 0.12, 0.6)   # 车窗玻璃
	var car_trim_mat := _std(Color.html("#262a2e"), 0.55, 0.35)   # 保险杠/侧裙
	var car_light_mat := _basic(Color.html("#ffe8a8"), true)      # 前大灯
	var car_tail_mat := _basic(Color.html("#ff5a40"), true)       # 尾灯
	var car_hub_mat := _std(Color.html("#8a9096"), 0.35, 0.7)     # 轮毂
	var car_unit_wheel := CylinderMesh.new()
	car_unit_wheel.top_radius = 1.0
	car_unit_wheel.bottom_radius = 1.0
	car_unit_wheel.height = 1.0
	car_unit_wheel.radial_segments = 10
	var car_mm := {}
	for _cc in car_colors:
		car_mm[car_body_mats[_cc]] = { "mesh": m_box1, "t": [] }
	car_mm[car_cab_mat] = { "mesh": m_box1, "t": [] }
	car_mm[car_wheel_mat] = { "mesh": car_unit_wheel, "t": [] }
	car_mm[car_glass_mat] = { "mesh": m_box1, "t": [] }
	car_mm[car_trim_mat] = { "mesh": m_box1, "t": [] }
	car_mm[car_light_mat] = { "mesh": m_box1, "t": [] }
	car_mm[car_tail_mat] = { "mesh": m_box1, "t": [] }
	car_mm[car_hub_mat] = { "mesh": car_unit_wheel, "t": [] }
	var car := func(x: float, z: float, rot := 0.0, col_override = null) -> void:
		var gh: float = G.ground_h.call(x, z)
		var col: Color = col_override if col_override != null else Utils.choice(car_colors)
		var bm = car_body_mats.get(col)
		if bm == null:
			bm = _std(col, 0.5, 0.6)
			car_body_mats[col] = bm
			car_mm[bm] = { "mesh": m_box1, "t": [] }
		var base := Transform3D(Basis(Vector3.UP, rot), Vector3(x, gh, z))
		# 车身(下层底盘 + 引擎盖 + 后备箱 + 驾驶舱 + 车窗)
		(car_mm[bm]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(4.2, 0.85, 1.9)), Vector3(0, 0.65, 0)))
		(car_mm[bm]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(1.5, 0.3, 1.75)), Vector3(1.3, 0.85, 0)))
		(car_mm[bm]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(1.25, 0.32, 1.75)), Vector3(-1.45, 0.83, 0)))
		(car_mm[car_cab_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(2.2, 0.7, 1.7)), Vector3(-0.2, 1.35, 0)))
		(car_mm[car_glass_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(1.95, 0.46, 1.52)), Vector3(-0.18, 1.52, 0)))
		# 保险杠(前后) + 侧裙
		(car_mm[car_trim_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(0.26, 0.4, 2.0)), Vector3(2.22, 0.38, 0)))
		(car_mm[car_trim_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(0.26, 0.4, 2.0)), Vector3(-2.22, 0.38, 0)))
		for sb in [-1.0, 1.0]:
			(car_mm[car_trim_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(4.0, 0.12, 0.08)), Vector3(0, 0.3, sb * 0.98)))
		# 前大灯 / 尾灯
		for lz in [-0.55, 0.55]:
			(car_mm[car_light_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(0.06, 0.15, 0.4)), Vector3(2.16, 0.75, lz)))
			(car_mm[car_tail_mat]["t"] as Array).append(base * Transform3D(Basis().scaled(Vector3(0.06, 0.14, 0.4)), Vector3(-2.16, 0.75, lz)))
		# 车轮 + 轮毂
		for wp in [[-1.4, 0.95], [1.4, 0.95], [-1.4, -0.95], [1.4, -0.95]]:
			(car_mm[car_wheel_mat]["t"] as Array).append(base * Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(0.72, 0.3, 0.72)), Vector3(wp[0], 0.36, wp[1])))
			(car_mm[car_hub_mat]["t"] as Array).append(base * Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(0.4, 0.34, 0.4)), Vector3(wp[0], 0.36, wp[1])))
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
			# 可殉爆油桶(细节:桶身 + 上下桶沿 + 双钢箍 + 黄色危险带 + 注油盖)
			var body_col := _std(Color.html("#7a3a1e"), 0.5, 0.6)   # 锈红桶身
			var steel := _std(Color.html("#3a3d42"), 0.4, 0.7)       # 钢箍/桶沿
			var hazard := _std(Color.html("#d8b020"), 0.55, 0.4)     # 危险警示黄带
			var b := _cyl(0.34, 0.34, 0.92, 14, body_col)
			b.position.y = 0.46
			g.add_child(b)
			# 顶部/底部加强桶沿(凸起圆环)
			var rim_top := _cyl(0.365, 0.365, 0.07, 14, steel)
			rim_top.position.y = 0.9
			g.add_child(rim_top)
			var rim_bot := _cyl(0.365, 0.365, 0.07, 14, steel)
			rim_bot.position.y = 0.05
			g.add_child(rim_bot)
			# 上下两道钢箍
			for by in [0.24, 0.7]:
				var band := _cyl(0.355, 0.355, 0.11, 14, steel)
				band.position.y = by
				g.add_child(band)
			# 危险警示带(桶身中部)
			var haz := _cyl(0.347, 0.347, 0.22, 14, hazard)
			haz.position.y = 0.47
			g.add_child(haz)
			# 桶顶注油盖(偏心小圆盘)
			var cap := _cyl(0.1, 0.1, 0.05, 10, steel)
			cap.position = Vector3(0.1, 0.925, 0.0)
			g.add_child(cap)
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

	if theme_id == "city" or theme_id == "tdm_city":
		# TDM 城市死斗:120m 紧凑城市布局(复用城市街区;sc 按 240m→120m 等比 0.75×0.5;
		# tdm_city 与 city 主题 TDM 均经 is_tdm 统一走该公式,征服模式 sc=1.0 不变)
		_city_blocks(T, wg, add_collider, minimap_rects, car, container, crate, barrel, barrier, road,
			0.75 * T.size / 240.0 if is_tdm else 1.0)
	elif theme_id == "br_valley":
		_br_valley_build(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, destructible, rock_photo_mat)
	elif theme_id == "desert":
		_desert_blocks(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, car, container, rock_photo_mat, tdm_sc)
	elif theme_id == "snow":
		_snow_blocks(T, wg, add_collider, minimap_rects, crate, sandbag, container, barrier, rock_photo_mat, tdm_sc)
	elif theme_id == "bt_jungle":
		_jungle_blocks(T, wg, add_collider, minimap_rects, crate, barrel, near_obj, rock_photo_mat, tdm_sc)
	elif theme_id == "bt_harbor":
		_harbor_blocks(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, car, barrier, container, cont_mats, near_obj, roof_mat, tdm_sc)
	elif theme_id == "bt_peak":
		_peak_blocks(T, wg, add_collider, minimap_rects, crate, barrel, sandbag, barrier, container, near_obj, rock_photo_mat, roof_mat)

	# [8/10] 统一 LOD:突破大图(420m)建筑/道具/装饰 >340m 不渲染(雾 far=500 内保留精模);
	# 地形/水面已标记 no_lod 排除;植被 MultiMesh 各自有裁剪
	if is_bt:
		for ch in wg.get_children():
			if ch is MultiMeshInstance3D:
				continue
			_set_lod_range(ch, 340.0, 100.0)

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
	elif is_tdm:
		# TDM 城市死斗:中央旗点南北各一座 + 巷战网加密(同城市主题)
		build_enterable(wg, 12, -road * 0.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, -12, road * 0.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, road * 0.5, -road * 1.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, -road * 1.5, road * 0.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, road * 1.5, road * 0.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, -road * 0.5, road * 1.5, 0.0, ent_wall, roof_mat, add_collider, minimap_rects)
		build_enterable(wg, road * 1.5, -road * 0.5, PI, ent_wall, roof_mat, add_collider, minimap_rects)
	elif is_br:
		pass  # BR 山谷:村庄可进入建筑由 _br_valley_build 布置
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
	elif is_br:
		pass  # BR 掩体/碎石由 _br_valley_build 布置
	else:
		_battlefield_dressing(wg, add_collider, size, road)

	# 可破坏建筑布置
	var pts := []
	if is_bt:
		for sec in T.sectors:
			for o in sec:
				pts.append(o)
	elif is_br:
		pts = []  # BR 村庄破坏物由 _br_valley_build 布置
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
	elif is_br:
		pass  # BR 无旗帜(跳伞/毒圈流程由 BR Agent 处理)
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

	# ---------- 自然化地图边界(取消箱庭围墙;保留隐形碰撞边界) ----------
	var B: float = G.bounds + 4
	add_collider.call(0, 0, -B, 2 * B + 8, 20, 2)
	add_collider.call(0, 0, B, 2 * B + 8, 20, 2)
	add_collider.call(-B, 0, 0, 2, 20, 2 * B + 8)
	add_collider.call(B, 0, 0, 2, 20, 2 * B + 8)
	# 可见围墙已移除 → 主题化天然边界 + 远景世界延伸(大逃杀山谷为开放世界,不套用)
	if not is_br:
		_build_natural_boundary(wg, theme_id, T, size, is_bt, is_tdm, lv, web)

	# ---------- 草地与地表细节(3A 植被/碎石;密度随画质档位) ----------
	_flush_prop_mm(wg, mm_buf)
	_flush_prop_mm(wg, car_mm)
	add_grass(wg, theme_id, is_bt, T, lv)
	var stone_k: float = T.size / 320.0 if is_br else 1.0   # BR 大地图碎石密度按面积缩放
	_add_surface_stones(wg, int(q_stones[lv] * (0.5 if web else 1.0) * stone_k), rock_photo_mat)

	# ---------- 出生点 ----------
	var sz := size / 2.0 - 16
	if is_tdm:
	# TDM:蓝队(us)北部 / 红队(ru)南部,四角分区随机出生点(贴边带避开楼群,
	# 碰撞体清障防出生穿模;120m 图 tsz=46:两队在 z∈[±37.7,±46] 带,间距 ≥75m 不贴脸)
		var tsz: float = size / 2.0 - 14
		var tdm_spawn := func(corner: float, side: float, tsp: float) -> Vector3:
			for attempt in 40:
				var px := corner * Utils.rand(tsp * 0.5, tsp)
				var pz := side * Utils.rand(tsp * 0.82, tsp)
				var gh2: float = G.ground_h.call(px, pz)
				var clear := true
				for b in G.colliders:
					var bb: AABB = b
					var ddx := maxf(absf(px - bb.get_center().x) - bb.size.x * 0.5, 0.0)
					var ddz := maxf(absf(pz - bb.get_center().z) - bb.size.z * 0.5, 0.0)
					if ddx * ddx + ddz * ddz < 4.0:
						clear = false
						break
				if clear:
					return Vector3(px, gh2, pz)
			return Vector3(corner * tsp * 0.9, 0.0, side * tsp * 0.9)
		for k in 12:
			var corner := 1.0 if (k & 1) == 0 else -1.0
			G.spawns["us"].append(tdm_spawn.call(corner, -1.0, tsz))
			G.spawns["ru"].append(tdm_spawn.call(corner, 1.0, tsz))
	elif is_br:
		# BR 开局跳伞由 BR Agent 处理;生成中心备用出生点兜底(防空出生列表)
		for k in 4:
			var bx := Utils.rand(-40, 40)
			G.spawns["us"].append(Vector3(bx, G.ground_h.call(bx, 30), 30.0))
			G.spawns["ru"].append(Vector3(-bx, G.ground_h.call(-bx, -30), -30.0))
	else:
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
	elif is_tdm:
		G.vehicle_spawns = []   # TDM 纯步兵:不生成任何载具
	elif is_br:
		# BR:按 extra.vehicle_points 生成吉普/步战(村庄外围与道路旁)
		G.vehicle_spawns = []
		for vp in (T.extra.get("vehicle_points", []) as Array):
			G.vehicle_spawns.append({
				"x": vp.x, "z": vp.z,
				"yaw": Utils.rand(TAU),
				"type": "jeep" if G.vehicle_spawns.size() % 4 else "apc",
			})
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
## sc: 布局缩放系数(tdm_city 120m 紧凑图按 0.75×size/240 等比缩放街道道具/天际线范围)
static func _city_blocks(_T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		car: Callable, container: Callable, crate: Callable, barrel: Callable, barrier: Callable, road: float,
		sc := 1.0) -> void:
	var facade_mats := []
	for fd in [["#8a8f98", 0.15], ["#9a8a78", 0.2], ["#7a8088", 0.1], ["#a4988a", 0.25]]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = TerrainTextures.facade_texture(fd[0], fd[1])
		m.roughness = 0.9
		facade_mats.append(m)
	var roof_mat := _std(Color.html("#3a3c40"), 0.95)
	# [PERF] 建筑盒批量 MultiMesh:单位盒缩放,按材质分桶(4 facade + 1 roof),1 材质 1 次绘制
	# (原每栋 2 个独立 BoxMesh 无法合批,~245 栋 ≈ 490 draw;改后 5 draw)
	var _unit_box := BoxMesh.new()
	_unit_box.size = Vector3.ONE
	var mm_buf := {}
	for fd in facade_mats:
		mm_buf[fd] = { "mesh": _unit_box, "t": [] }
	mm_buf[roof_mat] = { "mesh": _unit_box, "t": [] }
	var add_building := func(x: float, z: float, w: float, d: float, h: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		mm_buf[Utils.choice(facade_mats)]["t"].append(Transform3D(Basis().scaled(Vector3(w, h, d)), Vector3(x, gh + h / 2.0, z)))
		mm_buf[roof_mat]["t"].append(Transform3D(Basis().scaled(Vector3(w + 0.4, 0.5, d + 0.4)), Vector3(x, gh + h + 0.2, z)))
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
			# [密度 8/10] 街区填充率 0.55→0.78,楼群更密;建筑更高(天际线更丰满)
			if randf() < 0.78:
				add_building.call(cx - bw / 4 + Utils.rand(-2, 2), cz + Utils.rand(-3, 3), Utils.rand(13, 17), Utils.rand(20, minf(28, bd - 6)), Utils.rand(16, 34))
				add_building.call(cx + bw / 4 + Utils.rand(-2, 2), cz + Utils.rand(-3, 3), Utils.rand(13, 17), Utils.rand(20, minf(28, bd - 6)), Utils.rand(20, 52))
			else:
				add_building.call(cx + Utils.rand(-3, 3), cz + Utils.rand(-3, 3), Utils.rand(20, minf(30, bw - 6)), Utils.rand(20, minf(30, bd - 6)), Utils.rand(18, 46))
			# 街区内补一栋中层楼(密度提升)
			if randf() < 0.5:
				add_building.call(cx + Utils.rand(-bw * 0.28, bw * 0.28), cz + Utils.rand(-bd * 0.28, bd * 0.28),
					Utils.rand(10, 16), Utils.rand(10, 16), Utils.rand(12, 26))
		i += 2
	_flush_prop_mm(wg, mm_buf)
	# [8/10] 城市遮挡剔除已移除:大体积 BoxOccluder 在快速镜头移动下导致楼群闪动(相机移动
	# 时整片街区在遮挡边界来回剔除),且无遮挡收益;改为纯 draw call 渲染(城市楼数可控)
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
			0: car.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R - 3, -R + 3, -3.0, 3.0, R - 3, R + 3]) + Utils.rand(-1, 1), Utils.rand(-0.2, 0.2))
			1: car.call(Utils.choice([-R - 3, -R + 3, -3.0, 3.0, R - 3, R + 3]) + Utils.rand(-1, 1), Utils.rand(-140 * sc, 140 * sc), PI / 2 + Utils.rand(-0.2, 0.2))
			2: container.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R, 0.0, R]) + Utils.rand(-5, 5), Utils.rand(PI))
			3: crate.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc))
			4: barrel.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc))
			5: barrier.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R, 0.0, R]) + Utils.rand(-5, 5), Utils.rand(PI))
	# 天际线([PERF] 26 栋远景楼合并单 MultiMesh:原 26 独立盒 → 1 draw)
	var skyline_mat := _basic(Color.html("#6a7684"), true)
	var sky_buf := { skyline_mat: { "mesh": _unit_box, "t": [] } }
	for k in 26:
		var a := k / 26.0 * TAU + Utils.rand(-0.1, 0.1)
		var r := Utils.rand(190 * sc, 260 * sc)
		var h := Utils.rand(30, 90)
		(sky_buf[skyline_mat]["t"] as Array).append(Transform3D(Basis().scaled(Vector3(Utils.rand(15, 30), h, Utils.rand(15, 30))), Vector3(cos(a) * r, h / 2 - 2, sin(a) * r)))
	_flush_prop_mm(wg, sky_buf)
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
		for lx in [-120.0 * sc, -40.0 * sc, 40.0 * sc, 120.0 * sc]:
			if near_flag3.call(lx, lr + 3.5, 25.0):
				continue
			lamp_at.call(lx, lr + 3.5, false)
	for lc in [-R2, 0.0, R2]:
		for lz in [-120.0 * sc, -40.0 * sc, 40.0 * sc, 120.0 * sc]:
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
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 2.0):
				continue
			push.call(trash_mat, cyl_mesh_u, bx, bz, 0.0, 0.35, Vector3(2.8, 0.7, 2.8))
			push.call(trash_mat, cyl_mesh_u, bx, bz, 0.0, 0.76, Vector3(3.0, 0.1, 3.0))
			break
	for k in 3:
		for t in 30:
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.2):
				continue
			push.call(hyd_mat, cyl_mesh_u, bx, bz, 0.0, 0.25, Vector3(1.6, 0.5, 1.6))
			push.call(hyd_mat, cyl_mesh_u, bx, bz, 0.0, 0.52, Vector3(1.9, 0.12, 1.9))
			break
	for k in 3:
		for t in 30:
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.2):
				continue
			var mr := Utils.rand(-0.3, 0.3)
			push.call(mail_mat, box_mesh_u, bx, bz, mr, 0.42, Vector3(0.09, 0.85, 0.09))
			push.call(mail_mat, box_mesh_u, bx, bz, mr, 0.95, Vector3(0.35, 0.45, 0.3))
			break
	for k in 3:
		for t in 30:
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
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
			var bz := Utils.rand(-140 * sc, 140 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 0.8):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)


## ==================== 沙漠油站 ====================
## sc: 布局缩放系数(TDM 120m 圈定按 0.375 等比;默认 1.0 不影响征服/突破)
static func _desert_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, sandbag: Callable, car: Callable, container: Callable, rock_photo_mat: Material,
		sc := 1.0) -> void:
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
	if sc < 1.0:
		blocks = [-66, -14, 14, 66]   # TDM 120m 圈定:仅取中心 4 列,避免建筑探出边界墙
	for i in blocks.size() - 1:
		for j in blocks.size() - 1:
			var cx: float = (blocks[i] + blocks[i + 1]) / 2.0 * sc
			var cz: float = (blocks[j] + blocks[j + 1]) / 2.0 * sc
			var w: float = (blocks[i + 1] - blocks[i]) * sc
			if w < 40 * sc:
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
		var px := Utils.rand(-130 * sc, 130 * sc)
		var pz := Utils.rand(-130 * sc, 130 * sc)
		p.position = Vector3(px, G.ground_h.call(px, pz) + 0.5, pz)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(p)
		add_collider.call(px, 0, pz, 10, 1, 2)
	# 道具
	for i in 52:
		var roll := randi() % 6
		match roll:
			0: barrel.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc))
			1: crate.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc))
			2: sandbag.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R, 0.0, R]) + Utils.rand(-6, 6), Utils.rand(PI))
			3: car.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R - 3, R + 3, -3.0, 3.0]), Utils.rand(-0.3, 0.3), Color.html("#9a7a4a"))
			4: container.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc), Utils.rand(PI))
			5: rock.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc), Utils.rand(0.8, 1.6))
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
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
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
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
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
			var bx := Utils.rand(-120 * sc, 120 * sc)
			var bz := Utils.rand(-120 * sc, 120 * sc)
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
			var bx := Utils.rand(-120 * sc, 120 * sc)
			var bz := Utils.rand(-120 * sc, 120 * sc)
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
	# 报废卡车(缺轮斜躺,带碰撞;细节:底盘大梁/木货厢/车头/引擎/排气管/破窗/散落备胎)
	var wrk_mat := _std(Color.html("#7a5a3a"), 0.9, 0.2)
	var wrk_cab := _std(Color.html("#5a4a3a"), 0.95)
	var wrk_wood := _std_tex(Color.html("#8a6f4e"), 0.95, "plywood")
	var wrk_metal := _std_tex(Color.html("#4a3a2a"), 0.7, "rusty_metal", 0.5)
	var wrk_glass := _std(Color.html("#141d18"), 0.15, 0.3)
	var whm := _std(Color.html("#1a1a1a"), 0.95)
	for k in 3:
		for t in 40:
			var on_h := randf() < 0.5
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz: float = Utils.choice([-R - 4.0, -R + 4.0, -4.0, 4.0, R - 4.0, R + 4.0]) + Utils.rand(-1, 1)
			if not on_h:
				var sw := bx
				bx = bz
				bz = sw
			if near_flag3.call(bx, bz, 22.0) or not clear_spot.call(bx, bz, 1.5):
				continue
			var grp := Node3D.new()
			# 底盘大梁(两根纵梁)
			for cr in [-0.72, 0.72]:
				var rail := _box(5.6, 0.16, 0.12, wrk_metal)
				rail.position = Vector3(0, 0.42, cr)
				grp.add_child(rail)
			# 木货厢(底板 + 左右栏板 + 前挡板)
			var deck := _box(4.0, 0.14, 2.3, wrk_wood)
			deck.position = Vector3(-1.5, 0.95, 0)
			grp.add_child(deck)
			for sr in [-1.15, 1.15]:
				var rail2 := _box(4.0, 0.18, 0.07, wrk_metal)
				rail2.position = Vector3(-1.5, 1.18, sr)
				grp.add_child(rail2)
			var headboard := _box(0.1, 0.55, 2.3, wrk_mat)
			headboard.position = Vector3(0.5, 1.22, 0)
			grp.add_child(headboard)
			# 车头(驾驶室 + 车顶 + 引擎盖 + 前脸 + 破窗)
			var cb := _box(1.7, 1.4, 2.2, wrk_cab)
			cb.position = Vector3(2.15, 1.15, 0)
			grp.add_child(cb)
			var roof := _box(1.85, 0.16, 2.32, wrk_cab)
			roof.position = Vector3(2.15, 1.92, 0)
			grp.add_child(roof)
			var hood := _box(1.05, 0.5, 1.95, wrk_mat)
			hood.position = Vector3(3.2, 0.85, 0)
			grp.add_child(hood)
			var front := _box(0.14, 0.5, 2.0, wrk_metal)
			front.position = Vector3(3.75, 0.55, 0)
			grp.add_child(front)
			var ws := _box(0.07, 0.62, 1.9, wrk_glass)
			ws.position = Vector3(1.28, 1.5, 0)
			ws.rotation.z = -0.18
			grp.add_child(ws)
			# 排气管(竖管) + 外露引擎
			var stack := _cyl(0.09, 0.09, 1.3, 8, wrk_metal)
			stack.position = Vector3(1.55, 2.0, 1.18)
			grp.add_child(stack)
			var engine := _box(0.6, 0.4, 1.4, wrk_metal)
			engine.position = Vector3(3.0, 0.75, 0)
			grp.add_child(engine)
			# 车轮(前左缺失 + 三只残留 + 散落备胎)
			for wpp in [[-1.7, 0.95], [-1.7, -0.95], [2.6, -0.95]]:
				var wh := _cyl(0.42, 0.42, 0.32, 8, whm)
				wh.rotation.x = PI / 2.0
				wh.position = Vector3(wpp[0], 0.4, wpp[1])
				grp.add_child(wh)
			var spare := _cyl(0.42, 0.42, 0.32, 8, whm)
			spare.rotation = Vector3(Utils.rand(-0.5, 0.5), 0, Utils.rand(-0.5, 0.5))
			spare.position = Vector3(-2.6, 0.2, 1.7)
			grp.add_child(spare)
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
			var rx := Utils.rand(-110 * sc, 110 * sc)
			var rz2 := Utils.rand(-110 * sc, 110 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 0.8):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# [3A 内容 8/10] 沙漠工业区(油田/矿井/工厂)
	_desert_industry(wg, add_collider, minimap_rects)
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


## ==================== [3A 内容 8/10] 沙漠工业区:油田 + 矿井 + 工厂(精细模型) ====================
## 油田:抽油机(桁架摆臂平衡重块)+ 储油罐组(圆柱+锥顶+加强环)
## 矿井:井架(A 形桁架+提升轮)+ 矿车轨道 + 矿石堆
## 工厂:锯齿屋顶厂房(PrismMesh)+ 烟囱 + 通风管 + 窗户阵列 + 地面管线
static func _desert_industry(wg: Node3D, add_collider: Callable, minimap_rects: Array) -> void:
	var rig_mat := _std_tex(Color.html("#8a6a4a"), 0.7, "rusty_metal", 0.4)       # 结构锈铁
	var tank_mat := _std_tex(Color.html("#b8a880"), 0.5, "corrugated_iron", 0.3)  # 油罐波纹铁
	var dark_mat := _std_tex(Color.html("#5a5e64"), 0.6, "metal_plate", 0.4)      # 深金属
	var plant_mat := _std_tex(Color.html("#9a948a"), 0.95, "rough_concrete")      # 厂房混凝土
	var glass_mat := _basic(Color.html("#7fb0d8"), true)                          # 窗户发光
	var ghf := G.ground_h
	var near_flag := func(x: float, z: float, r: float) -> bool:
		for f in G.flags:
			var dx: float = x - f.pos.x
			var dz: float = z - f.pos.z
			if dx * dx + dz * dz < r * r:
				return true
		return false
	var pick_spot := func(min_r: float) -> Vector2:
		for t in 60:
			var sx := Utils.rand(-130.0, 130.0)
			var sz := Utils.rand(-130.0, 130.0)
			if near_flag.call(sx, sz, min_r):
				continue
			return Vector2(sx, sz)
		return Vector2.ZERO
	# ---- 抽油机(桁架式摆臂泵) ----
	var pumpjack := func(x: float, z: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var base := _box(3.2, 0.25, 2.0, dark_mat)
		base.position.y = 0.12
		g2.add_child(base)
		for s in [-1.0, 1.0]:
			for t in [-0.8, 0.8]:
				var leg := _cyl(0.09, 0.09, 3.4, 6, rig_mat)
				leg.position = Vector3(s * 1.2, 1.7, t * 0.6)
				leg.rotation.x = t * 0.5
				leg.rotation.z = s * 0.3
				g2.add_child(leg)
		var topb := _box(2.6, 0.18, 0.18, rig_mat)
		topb.position = Vector3(0, 3.5, 0)
		g2.add_child(topb)
		var arm := _box(0.22, 0.3, 5.6, rig_mat)
		arm.position = Vector3(0, 3.1, -2.0)
		arm.rotation.x = -0.16
		g2.add_child(arm)
		var wgt := _cyl(0.5, 0.5, 0.9, 10, dark_mat)
		wgt.position = Vector3(0, 3.45, -4.55)
		g2.add_child(wgt)
		var rod := _cyl(0.06, 0.06, 0.6, 6, rig_mat)
		rod.position = Vector3(0, 0.55, 0.55)
		g2.add_child(rod)
		var motor := _box(0.7, 0.5, 0.9, dark_mat)
		motor.position = Vector3(1.4, 0.45, 0)
		g2.add_child(motor)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 3.6, 3.8, 5.6)
	# ---- 储油罐(圆柱 + 锥顶 + 加强环) ----
	var oil_tank2 := func(x: float, z: float, r: float, h: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var body := _cyl(r, r, h, 16, tank_mat)
		body.position.y = h / 2.0
		g2.add_child(body)
		var roof := _cone(r, 1.3, 14, tank_mat)
		roof.position.y = h + 0.65
		g2.add_child(roof)
		for i in 3:
			var ring := _cyl(r * 0.999, r * 0.999, 0.07, 16, dark_mat)
			ring.position.y = h * float(i + 1) / 4.0
			g2.add_child(ring)
		var ladder := _box(0.5, h, 0.12, dark_mat)
		ladder.position = Vector3(r * 0.7, h / 2.0, 0)
		g2.add_child(ladder)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, r * 2.0, h + 1.6, r * 2.0)
		minimap_rects.append({ "x": x, "z": z, "w": r * 2.0, "d": r * 2.0 })
	# ---- 井架(桁架 + 提升轮 + 缆线) ----
	var headframe := func(x: float, z: float, h: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		for s in [-1.0, 1.0]:
			for t in [-1.0, 1.0]:
				var leg := _cyl(0.12, 0.12, h, 6, rig_mat)
				leg.position = Vector3(s * 1.8, h / 2.0, t * 1.8)
				leg.rotation.x = t * 0.22
				leg.rotation.z = -s * 0.22
				g2.add_child(leg)
		for i in 3:
			var brace := _box(3.9, 0.14, 0.14, rig_mat)
			brace.position = Vector3(0, h * float(i + 1) / 4.0, 0)
			g2.add_child(brace)
			var brace2 := _box(0.14, 0.14, 3.9, rig_mat)
			brace2.position = Vector3(0, h * float(i + 1) / 4.0, 0)
			g2.add_child(brace2)
		var plat := _box(3.6, 0.3, 3.6, dark_mat)
		plat.position.y = h
		g2.add_child(plat)
		var wheel := _cyl(0.7, 0.7, 0.3, 12, dark_mat)
		wheel.rotation.x = PI / 2.0
		wheel.position = Vector3(0, h + 0.6, 1.2)
		g2.add_child(wheel)
		var cable := _cyl(0.03, 0.03, h + 1.0, 4, dark_mat)
		cable.position = Vector3(0, (h + 1.0) / 2.0, 1.2)
		g2.add_child(cable)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 4.0, h + 1.2, 4.0)
	# ---- 矿石堆(压扁球簇) ----
	var ore_pile := func(x: float, z: float, s: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var om := _std_tex(Color.html("#6a5a4a"), 1.0, "rock_04")
		for i in 5:
			var ob := _ico(Utils.rand(0.5, 1.1) * s, om)
			ob.position = Vector3(Utils.rand(-1.6, 1.6) * s, Utils.rand(0.1, 0.9) * s, Utils.rand(-1.6, 1.6) * s)
			ob.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
			g2.add_child(ob)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 3.2 * s, 1.2 * s, 3.2 * s)
	# ---- 矿车轨道 + 矿车 ----
	var minecart := func(x: float, z: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var rail_mat := _std(Color.html("#6a5a48"), 0.7, 0.5)
		for rs in [-0.7, 0.7]:
			var rail := _box(6.0, 0.1, 0.08, rail_mat)
			rail.position = Vector3(rs, 0.15, 0)
			g2.add_child(rail)
		var cart := _box(1.3, 0.7, 0.9, dark_mat)
		cart.position = Vector3(0, 0.55, 0)
		g2.add_child(cart)
		var cart_ore := _cone(0.55, 0.5, 8, _std(Color.html("#8a7a5a"), 1.0))
		cart_ore.position = Vector3(0, 1.15, 0)
		g2.add_child(cart_ore)
		for wp2 in [[-0.5, 0.5], [0.5, 0.5], [-0.5, -0.5], [0.5, -0.5]]:
			var w2 := _cyl(0.16, 0.16, 0.12, 8, dark_mat)
			w2.rotation.x = PI / 2.0
			w2.position = Vector3(wp2[0], 0.18, wp2[1])
			g2.add_child(w2)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		_shadows_on(g2)
		wg.add_child(g2)
	# ---- 工厂厂房(锯齿屋顶 + 烟囱 + 窗户 + 通风管) ----
	var plant := func(x: float, z: float, w: float, d: float, h: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var body := _box(w, h, d, plant_mat)
		body.position.y = h / 2.0
		g2.add_child(body)
		# 锯齿屋顶(PrismMesh 三角棱柱阵列)
		var n_saw := maxi(2, int(w / 4.0))
		for i in n_saw:
			var saw := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(4.2, 1.6, d + 0.6)
			pm.left_to_right = 1.0
			saw.mesh = pm
			saw.material_override = tank_mat
			saw.position = Vector3(-w / 2.0 + 2.1 + i * 4.0, h + 0.8, 0)
			g2.add_child(saw)
		# 烟囱 + 顶部环
		var chim := _cyl(0.6, 0.6, 7.5, 12, dark_mat)
		chim.position = Vector3(-w * 0.3, h + 3.75, d * 0.2)
		g2.add_child(chim)
		var chim_ring := _cyl(0.72, 0.72, 0.35, 12, rig_mat)
		chim_ring.position = Vector3(-w * 0.3, h + 7.6, d * 0.2)
		g2.add_child(chim_ring)
		# 通风管(屋顶短管)
		for i in 3:
			var vent := _cyl(0.3, 0.3, 1.2, 8, dark_mat)
			vent.position = Vector3(w * 0.15 + i * 2.6, h + 1.2, -d * 0.25)
			g2.add_child(vent)
		# 窗户阵列(发光)
		for i in int(w / 3.0) - 1:
			var win := _box(1.8, 1.1, 0.15, glass_mat)
			win.position = Vector3(-w / 2.0 + 2.6 + i * 3.0, h * 0.62, d / 2.0 + 0.05)
			g2.add_child(win)
			var win2 := _box(1.8, 1.1, 0.15, glass_mat)
			win2.position = Vector3(-w / 2.0 + 2.6 + i * 3.0, h * 0.62, -d / 2.0 - 0.05)
			g2.add_child(win2)
		# 大门
		var door := _box(2.4, 2.2, 0.12, dark_mat)
		door.position = Vector3(0, 1.1, d / 2.0 + 0.05)
		g2.add_child(door)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, w, h + 2.6, d)
		minimap_rects.append({ "x": x, "z": z, "w": w, "d": d })
	# ---- 地面管线(储罐区连接管) ----
	var pipe_mat := _std(Color.html("#8a7a5a"), 0.6, 0.6)
	var pipe := func(x: float, z: float, len: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var p := _cyl(0.22, 0.22, len, 8, pipe_mat)
		p.rotation.x = PI / 2.0
		p.position.y = 0.35
		g2.add_child(p)
		var joint := _cyl(0.3, 0.3, 0.4, 8, pipe_mat)
		joint.position = Vector3(0, 0.6, 0)
		g2.add_child(joint)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		wg.add_child(g2)
	# ---- 布局:2 油田 + 1 矿井 + 2 工厂 + 管线 ----
	var oil1: Vector2 = pick_spot.call(60.0)
	pumpjack.call(oil1.x, oil1.y, Utils.rand(TAU))
	oil_tank2.call(oil1.x + 12.0, oil1.y + 6.0, 3.0, 4.5)
	oil_tank2.call(oil1.x + 20.0, oil1.y + 9.0, 3.6, 5.5)
	oil_tank2.call(oil1.x + 28.0, oil1.y + 4.0, 2.6, 4.0)
	pipe.call(oil1.x + 6.0, oil1.y + 3.0, 18.0, 0.3)
	var oil2: Vector2 = pick_spot.call(55.0)
	pumpjack.call(oil2.x, oil2.y, Utils.rand(TAU))
	pumpjack.call(oil2.x + 8.0, oil2.y + 7.0, Utils.rand(TAU))
	oil_tank2.call(oil2.x - 10.0, oil2.y - 5.0, 2.8, 4.0)
	var mine: Vector2 = pick_spot.call(50.0)
	headframe.call(mine.x, mine.y, 9.0)
	ore_pile.call(mine.x + 8.0, mine.y + 3.0, 1.0)
	ore_pile.call(mine.x - 7.0, mine.y - 4.0, 1.3)
	minecart.call(mine.x + 5.0, mine.y + 8.0, Utils.rand(TAU))
	var pl1: Vector2 = pick_spot.call(45.0)
	plant.call(pl1.x, pl1.y, 18.0, 12.0, 5.0, Utils.rand(TAU))
	var pl2: Vector2 = pick_spot.call(45.0)
	plant.call(pl2.x, pl2.y, 14.0, 10.0, 4.5, Utils.rand(TAU))


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


## ==================== BR 山谷战场(800m 大图:起伏地形 + 河流 + 树林 + 村庄) ====================
static func _br_valley_build(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, sandbag: Callable, destructible: Callable, rock_photo_mat: Material) -> void:
	var half: float = T.size / 2.0
	var river_x: float = T.river
	# ---- 材质 ----
	var wood_mat := _std_tex(Color.html("#8a6f4e"), 0.95, "plywood")
	var thatch_mat := _std(Color.html("#9a7c4a"), 1.0)
	var conc_mat := _std_tex(Color.html("#9a948a"), 0.95, "rough_concrete")
	var roof_mat := _std(Color.html("#3a3c40"), 0.95)
	var trunk_mat := _std(Color.html("#4a3a26"), 1.0)
	var leaf_mat := _std(Color.html("#3a5a30"), 1.0)
	var leaf_mat2 := _std(Color.html("#486840"), 1.0)
	var bush_mat := _std(Color.html("#44603a"), 1.0)
	# ---- 村庄房屋(三种样式:茅草屋/平顶木屋/混凝土小屋) ----
	var house := func(x: float, z: float, rot := 0.0, style := 0) -> void:
		var gh: float = G.ground_h.call(x, z)
		var g := Node3D.new()
		g.name = "VillageHouse"
		g.add_to_group("village_house")
		var w := 5.2
		var d := 4.2
		var h := 3.4
		match style % 3:
			0:
				w = 5.2; d = 4.2; h = 3.4
				var body := _box(w, 2.8, d, wood_mat)
				body.position.y = 2.2
				g.add_child(body)
				var roof := _cone(4.1, 1.8, 4, thatch_mat)
				roof.position.y = 4.5
				roof.rotation.y = PI / 4.0
				g.add_child(roof)
				var door := _box(1.1, 1.9, 0.1, _basic(Color.html("#201812"), true))
				door.position = Vector3(0, 1.75, d / 2 + 0.02)
				g.add_child(door)
				for lp in [[-2.2, -1.7], [2.2, -1.7], [-2.2, 1.7], [2.2, 1.7]]:
					var leg := _cyl(0.14, 0.14, 0.9, 6, trunk_mat)
					leg.position = Vector3(lp[0], 0.45, lp[1])
					g.add_child(leg)
			1:
				w = Utils.rand(6, 8); d = Utils.rand(5, 6); h = Utils.rand(3.2, 3.8)
				var body2 := _box(w, h, d, wood_mat)
				body2.position.y = h / 2
				g.add_child(body2)
				var rf := _box(w + 0.5, 0.25, d + 0.5, roof_mat)
				rf.position.y = h + 0.12
				g.add_child(rf)
				var door2 := _box(1.0, 1.8, 0.1, _basic(Color.html("#201812"), true))
				door2.position = Vector3(0, h * 0.55, d / 2 + 0.02)
				g.add_child(door2)
			_:
				w = 4.0; d = 3.4; h = 2.9
				var body3 := _box(w, h, d, conc_mat)
				body3.position.y = h / 2
				g.add_child(body3)
				var rf2 := _box(w + 0.4, 0.22, d + 0.4, roof_mat)
				rf2.position.y = h + 0.1
				g.add_child(rf2)
				var slit := _box(w * 0.7, 0.28, 0.08, _basic(Color.html("#1a1e22"), true))
				slit.position = Vector3(0, h * 0.62, d / 2 + 0.01)
				g.add_child(slit)
		g.rotation.y = rot
		g.position = Vector3(x, gh, z)
		_shadows_on(g)
		wg.add_child(g)
		var cs := absf(cos(rot)) > 0.5
		add_collider.call(x, 0.8, z, w if cs else d, h + 0.6, d if cs else w)
		minimap_rects.append({ "x": x, "z": z, "w": w if cs else d, "d": d if cs else w })
	# ---- 村庄聚落(4 个;每村 4-6 栋房 + 破坏物棚屋 + 道具 + 可进入哨所) ----
	var villages: Array = T.extra.get("villages", [])
	for vi in villages.size():
		var v: Dictionary = villages[vi]
		var vx: float = v["x"]
		var vz: float = v["z"]
		var n_houses := 11 + (vi % 2)
		for k in n_houses:
			var ha := k / float(n_houses) * TAU + Utils.rand(-0.25, 0.25)
			var hr := Utils.rand(13, 30)
			var hx := vx + cos(ha) * hr
			var hz := vz + sin(ha) * hr
			if absf(hx) > half - 24 or absf(hz) > half - 24:
				continue
			if absf(hx - river_x) < 26.0:
				continue
			house.call(hx, hz, Utils.rand(-0.35, 0.35), vi + k)
		for k2 in 2:
			destructible.call(vx + Utils.rand(-20, 20), vz + Utils.rand(-20, 20), Utils.rand(PI),
				"shed" if randf() < 0.6 else "tower")
		crate.call(vx - 9 + Utils.rand(-4, 4), vz + 6 + Utils.rand(-4, 4))
		crate.call(vx + 10 + Utils.rand(-4, 4), vz - 7 + Utils.rand(-4, 4))
		barrel.call(vx + Utils.rand(-14, 14), vz + Utils.rand(-14, 14))
		barrel.call(vx + Utils.rand(-14, 14), vz + Utils.rand(-14, 14))
		sandbag.call(vx + 12, vz + 14, 0.4)
		sandbag.call(vx - 13, vz - 12, -0.6)
		sandbag.call(vx + 15, vz - 10, 1.8)
		build_enterable(wg, vx + Utils.rand(-6, 6), vz + Utils.rand(-6, 6), Utils.choice([0.0, PI]),
			conc_mat, roof_mat, add_collider, minimap_rects)
	# ---- 城市区(东北部 x≥205 密集街区:5 排街区 + 街道 + 广场;含可进入室内房) ----
	var city_blocks: Array = T.extra.get("city_blocks", [])
	var city_streets: Array = T.extra.get("city_streets", [])
	var facade_mats := []
	for fd in [["#8a8f98", 0.15], ["#a89a88", 0.3], ["#7a8088", 0.1], ["#9a948a", 0.25]]:
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = TerrainTextures.facade_texture(fd[0], fd[1])
		fm.roughness = 0.9
		facade_mats.append(fm)
	var city_conc := _std_tex(Color.html("#9a948a"), 0.95, "rough_concrete")
	var city_roof := _std(Color.html("#2e3034"), 0.95)
	for bi in city_blocks.size():
		var blk: Dictionary = city_blocks[bi]
		var cx: float = blk["x"]
		var cz: float = blk["z"]
		var bw: float = blk["w"]
		var bd: float = blk["d"]
		var bh: float = blk["h"]
		var ghb: float = G.ground_h.call(cx, cz)
		if blk.get("enter", false):
			# 可进入室内房(门朝街道 -Z;外壳 + 隔断 + 家具掩体)
			build_enterable_house(wg, cx, cz, 0.0, city_conc, city_roof, wood_mat, add_collider, minimap_rects)
			continue
		var b := _box(bw, bh, bd, Utils.choice(facade_mats))
		b.name = "CityBlock"
		b.add_to_group("city_block")
		b.position = Vector3(cx, ghb + bh / 2.0, cz)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		var rfc := _box(bw + 0.4, 0.42, bd + 0.4, city_roof)
		rfc.position = Vector3(cx, ghb + bh + 0.2, cz)
		rfc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(rfc)
		add_collider.call(cx, 0, cz, bw, bh, bd)
		minimap_rects.append({ "x": cx, "z": cz, "w": bw, "d": bd })
	# 城市街道(沥青带沿街道 z 线 + 广场地面)
	var asphalt_mat := _std_tex(Color(1, 1, 1), 0.9, "asphalt_02")
	var street_mi := func(lx: float, lz: float, lw: float, ld: float) -> void:
		var pm := PlaneMesh.new()
		pm.size = Vector2(lw, ld)
		pm.orientation = PlaneMesh.FACE_Y
		var smi := MeshInstance3D.new()
		smi.mesh = pm
		smi.material_override = asphalt_mat
		smi.position = Vector3(lx, G.ground_h.call(lx, lz) + 0.08, lz)
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(smi)
	for sz2 in city_streets:
		street_mi.call(275.0, sz2, 170.0, 12.0)
	street_mi.call(275.0, 45.0, 34.0, 22.0)  # 中央广场
	# 广场纪念碑(可作掩体)+ 沙袋环 + 木箱油桶
	var mon_mat := _std_tex(Color.html("#b8bcc0"), 1.0, "rough_concrete")
	var mon := Node3D.new()
	var mbase := _box(4.0, 1.2, 4.0, mon_mat)
	mbase.position.y = 0.6
	mon.add_child(mbase)
	var mcol := _box(1.2, 4.6, 1.2, mon_mat)
	mcol.position.y = 3.5
	mon.add_child(mcol)
	var mtop := _box(2.2, 0.5, 2.2, mon_mat)
	mtop.position.y = 6.0
	mon.add_child(mtop)
	mon.position = Vector3(275.0, G.ground_h.call(275.0, 45.0), 45.0)
	_shadows_on(mon)
	wg.add_child(mon)
	add_collider.call(275.0, 0, 45.0, 4.0, 7.0, 4.0)
	minimap_rects.append({ "x": 275.0, "z": 45.0, "w": 4.0, "d": 4.0 })
	for sg_i in 8:
		var sa := sg_i / 8.0 * TAU
		sandbag.call(275.0 + cos(sa) * 12.0, 45.0 + sin(sa) * 9.0, sa)
	crate.call(275.0 - 5.0, 45.0 + 3.0)
	crate.call(275.0 + 6.0, 45.0 - 4.0)
	barrel.call(275.0 - 7.0, 45.0 - 6.0)
	barrel.call(275.0 + 4.0, 45.0 + 6.0)
	# 街道路灯(细杆 + 弯臂 + 暖白灯头;MultiMesh 批绘,同城市样式)
	var lamp_pole_mat := _std(Color.html("#2a2e33"), 0.7, 0.5)
	var lamp_head_mat2 := _basic(Color.html("#ffd9a0"), true)
	var lp_mesh := CylinderMesh.new()
	lp_mesh.top_radius = 0.06; lp_mesh.bottom_radius = 0.06; lp_mesh.height = 4.5; lp_mesh.radial_segments = 6
	var la_mesh := BoxMesh.new()
	la_mesh.size = Vector3(0.05, 0.05, 0.65)
	var lh_mesh := SphereMesh.new()
	lh_mesh.radius = 0.15; lh_mesh.height = 0.3; lh_mesh.radial_segments = 8; lh_mesh.rings = 6
	var lamp_buf := {}
	var lamp_push := func(mat: Material, mesh: Mesh, px: float, pz: float, rot2: float, y_off: float, s: Vector3) -> void:
		var ghl: float = G.ground_h.call(px, pz)
		var en2 = lamp_buf.get(mat)
		if en2 == null:
			en2 = { "mesh": mesh, "t": [] }
			lamp_buf[mat] = en2
		(en2["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot2).scaled(s), Vector3(px, ghl + y_off, pz)))
	var lamp_at := func(px: float, pz: float, v: bool) -> void:
		var ox := -0.3 if v else 0.0
		var oz := 0.0 if v else -0.3
		lamp_push.call(lamp_pole_mat, lp_mesh, px, pz, 0.0, 2.25, Vector3.ONE)
		lamp_push.call(lamp_pole_mat, la_mesh, px + ox, pz + oz, PI / 2.0 if v else 0.0, 4.5, Vector3.ONE)
		lamp_push.call(lamp_head_mat2, lh_mesh, px + ox - 0.2, pz + oz - 0.2, 0.0, 4.52, Vector3.ONE)
	var lamp_i := 0
	for sz3 in city_streets:
		for sx2 in [215.0, 245.0, 275.0, 305.0, 335.0]:
			if sz3 == 45.0 and absf(sx2 - 275.0) < 22.0:
				continue  # 广场内不立灯
			lamp_at.call(sx2, sz3 + (7.0 if lamp_i % 2 == 0 else -7.0), lamp_i % 2 == 0)
			lamp_i += 1
	# 街面道具:木箱/油桶/沙袋(沿街分布,碰撞作掩体)
	for sz4 in city_streets:
		for sx3 in [222.0, 252.0, 282.0, 312.0]:
			if randf() < 0.5:
				crate.call(sx3 + Utils.rand(-2, 2), sz4 + Utils.rand(-2, 2))
			else:
				barrel.call(sx3 + Utils.rand(-2, 2), sz4 + Utils.rand(-2, 2))
			sandbag.call(sx3 + Utils.rand(-8, 8), sz4 + Utils.rand(-8, 8), Utils.rand(PI))
	# 新区街道(±315)街头补防:街角沙袋组 + 箱/桶(随新街区放置;避让路灯 z±7 列)
	for ns5 in [-315.0, 315.0]:
		for nx5 in [215.0, 335.0]:
			var nside := -1.0 if ns5 < 0.0 else 1.0
			sandbag.call(nx5, ns5 + nside * 12.0, -0.7 if ns5 < 0.0 else 0.7)
			if randf() < 0.5:
				crate.call(nx5 + 4.0, ns5 + nside * 12.0)
			else:
				barrel.call(nx5 + 4.0, ns5 + nside * 12.0)
	_flush_prop_mm(wg, lamp_buf)
	# ---- 野外农场(西/外围散落谷仓 + 农舍 + 草垛掩体) ----
	var farms: Array = T.extra.get("farms", [])
	var hay_mat := _std(Color.html("#c8a85a"), 1.0)
	var hay_mesh := CylinderMesh.new()
	hay_mesh.top_radius = 0.9; hay_mesh.bottom_radius = 1.15; hay_mesh.height = 1.6; hay_mesh.radial_segments = 9
	var hay_buf2 := {}
	var hay_push := func(px: float, pz: float) -> void:
		var ghh: float = G.ground_h.call(px, pz)
		var en3 = hay_buf2.get(hay_mat)
		if en3 == null:
			en3 = { "mesh": hay_mesh, "t": [] }
			hay_buf2[hay_mat] = en3
		(en3["t"] as Array).append(Transform3D(Basis(Vector3.UP, Utils.rand(TAU)), Vector3(px, ghh + 0.8, pz)))
	for f in farms:
		var fx: float = f["x"]
		var fz: float = f["z"]
		var fstyle: int = f.get("style", 0)
		var ghf: float = G.ground_h.call(fx, fz)
		if f.get("enter", false):
			# 可进入农舍(木板房,内部隔断 + 家具)
			build_enterable_house(wg, fx, fz, 0.0, wood_mat, roof_mat, wood_mat, add_collider, minimap_rects)
		elif fstyle == 1:
			# 谷仓:木墙 + 人字顶
			var barn := _box(8.0, 4.2, 6.0, wood_mat)
			barn.name = "FarmBarn"
			barn.add_to_group("farm_building")
			barn.position = Vector3(fx, ghf + 2.1, fz)
			barn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(barn)
			var ridge := _box(9.0, 0.24, 6.8, roof_mat)
			ridge.rotation.x = 0.35
			ridge.position = Vector3(fx, ghf + 4.6, fz + 1.4)
			ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(ridge)
			var ridge2 := _box(9.0, 0.24, 6.8, roof_mat)
			ridge2.rotation.x = -0.35
			ridge2.position = Vector3(fx, ghf + 4.6, fz - 1.4)
			ridge2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(ridge2)
			add_collider.call(fx, 0, fz, 8.0, 4.6, 6.0)
			minimap_rects.append({ "x": fx, "z": fz, "w": 8.0, "d": 6.0 })
		else:
			# 平顶农舍(混凝土小屋)
			var fh := _box(6.0, 3.0, 5.0, conc_mat)
			fh.name = "FarmHouse"
			fh.add_to_group("farm_building")
			fh.position = Vector3(fx, ghf + 1.5, fz)
			fh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(fh)
			var fhr := _box(6.4, 0.22, 5.4, roof_mat)
			fhr.position = Vector3(fx, ghf + 3.1, fz)
			fhr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			wg.add_child(fhr)
			add_collider.call(fx, 0, fz, 6.0, 3.4, 5.0)
			minimap_rects.append({ "x": fx, "z": fz, "w": 6.0, "d": 5.0 })
		# 草垛掩体 ×2(带碰撞)+ 农具木箱/油桶
		hay_push.call(fx + 6.5, fz + 4.5)
		hay_push.call(fx - 6.0, fz - 5.0)
		add_collider.call(fx + 6.5, 0, fz + 4.5, 2.3, 1.6, 2.3)
		add_collider.call(fx - 6.0, 0, fz - 5.0, 2.3, 1.6, 2.3)
		crate.call(fx + 3.5, fz - 3.5)
		barrel.call(fx - 3.5, fz + 3.5)
	_flush_prop_mm(wg, hay_buf2)
	# ---- 土路(贴地起伏带状网格,连接聚落;河道处下潜成渡口) ----
	var dirt_mat := _std(Color.html("#8a7a58"), 1.0)
	var roads: Array = T.extra.get("roads", [])
	for seg in roads:
		var a0 := Vector2(seg[0], seg[1])
		var b0 := Vector2(seg[2], seg[3])
		var rl := a0.distance_to(b0)
		var steps := maxi(2, int(rl / 8.0))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var p0 := a0.lerp(b0, t0)
			var p1 := a0.lerp(b0, t1)
			var dirv := (p1 - p0).normalized()
			var perp := Vector2(-dirv.y, dirv.x)
			var y0a: float = G.ground_h.call(p0.x, p0.y) + 0.12
			var y0b: float = G.ground_h.call(p1.x, p1.y) + 0.12
			for s2 in [-4.5, 4.5]:
				var c0 := Vector3(p0.x + perp.x * s2, y0a, p0.y + perp.y * s2)
				var c1 := Vector3(p1.x + perp.x * s2, y0b, p1.y + perp.y * s2)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2((c0.x + half) / T.size, (c0.z + half) / T.size))
				st.add_vertex(c0)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2((c1.x + half) / T.size, (c1.z + half) / T.size))
				st.add_vertex(c1)
			var base := i * 4
			st.add_index(base + 0); st.add_index(base + 1); st.add_index(base + 2)
			st.add_index(base + 1); st.add_index(base + 3); st.add_index(base + 2)
		var road_mi := MeshInstance3D.new()
		road_mi.mesh = st.commit()
		road_mi.material_override = dirt_mat
		wg.add_child(road_mi)
	# ---- 树林(MultiMesh 批绘:树干/双层树冠/灌木,远离村庄与河道) ----
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 7
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.0
	canopy_mesh.height = 2.0
	canopy_mesh.radial_segments = 9
	canopy_mesh.rings = 6
	var tree_buf := {}
	var tree_push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = tree_buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			tree_buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	var near_village := func(x: float, z: float, r: float) -> bool:
		for vv in villages:
			var ddx: float = x - vv["x"]
			var ddz: float = z - vv["z"]
			if ddx * ddx + ddz * ddz < r * r:
				return true
		return false
	# 城市区(东北 x≥205,z ±230)与农场附近不长树
	var near_city := func(x: float, z: float) -> bool:
		return x > 190.0 and z > -350.0 and z < 350.0
	var near_farm := func(x: float, z: float, r: float) -> bool:
		for ff in farms:
			var ddx: float = x - ff["x"]
			var ddz: float = z - ff["z"]
			if ddx * ddx + ddz * ddz < r * r:
				return true
		return false
	var trees_placed := 0
	var attempts := 0
	while trees_placed < 260 and attempts < 900:
		attempts += 1
		var tx := Utils.rand(-half + 20, half - 20)
		var tz := Utils.rand(-half + 20, half - 20)
		if absf(tx - river_x) < 20.0 or near_village.call(tx, tz, 48.0) \
				or near_city.call(tx, tz) or near_farm.call(tx, tz, 36.0):
			continue
		trees_placed += 1
		var th := Utils.rand(5, 9)
		var tyaw := Utils.rand(TAU)
		tree_push.call(trunk_mat, trunk_mesh, tx, tz, tyaw, th * 0.5, Vector3(1, th, 1))
		tree_push.call(leaf_mat, canopy_mesh, tx, tz, 0.0, th * 0.95, Vector3(th * 0.36, th * 0.27, th * 0.36))
		tree_push.call(leaf_mat2, canopy_mesh, tx, tz, 0.0, th * 1.2, Vector3(th * 0.25, th * 0.175, th * 0.25))
	var bushes_placed := 0
	var attempts2 := 0
	while bushes_placed < 150 and attempts2 < 500:
		attempts2 += 1
		var bx := Utils.rand(-half + 20, half - 20)
		var bz := Utils.rand(-half + 20, half - 20)
		if absf(bx - river_x) < 18.0 or near_village.call(bx, bz, 44.0) \
				or near_city.call(bx, bz) or near_farm.call(bx, bz, 34.0):
			continue
		bushes_placed += 1
		var bs := Utils.rand(0.7, 1.4)
		tree_push.call(bush_mat, canopy_mesh, bx, bz, Utils.rand(TAU), bs, Vector3(bs, bs, bs))
	_flush_prop_mm(wg, tree_buf, 700.0)  # [PERF] 800m 图植被视距裁剪:>700m 全隐(525m 起淡出,相机 far=900)
	print("[PERF] 植被视距裁剪生效: 树/灌木 MultiMesh >700m 裁剪(相机 far=900)")
	# ---- 岩石与枯木(带碰撞,战场掩体) ----
	var rock := func(x: float, z: float, s := 1.0) -> void:
		var r := _ico(Utils.rand(1, 2.2) * s, rock_photo_mat)
		r.position = Vector3(x, G.ground_h.call(x, z) + Utils.rand(0.3, 0.8) * s, z)
		r.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(r)
		add_collider.call(x, 0, z, 2 * s, 1.6 * s, 2 * s)
	for i in 22:
		var rx := Utils.rand(-half + 16, half - 16)
		var rz := Utils.rand(-half + 16, half - 16)
		if absf(rx - river_x) < 24.0 or near_village.call(rx, rz, 40.0) or near_city.call(rx, rz) or near_farm.call(rx, rz, 32.0):
			continue
		rock.call(rx, rz, Utils.rand(0.8, 2.0))
	for i in 12:
		var lx := Utils.rand(-half + 16, half - 16)
		var lz := Utils.rand(-half + 16, half - 16)
		if absf(lx - river_x) < 20.0 or near_village.call(lx, lz, 40.0) or near_city.call(lx, lz) or near_farm.call(lx, lz, 32.0):
			continue
		var l := _cyl(0.3, 0.36, Utils.rand(5, 8), 8, trunk_mat)
		l.rotation.z = PI / 2.0
		l.rotation.y = Utils.rand(PI)
		l.position = Vector3(lx, G.ground_h.call(lx, lz) + 0.35, lz)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(l)
		add_collider.call(lx, 0, lz, 5, 0.8, 1.0)
	# ---- 战场氛围(废墟/拒马/烧毁残骸,同征服战地装饰) ----
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
	for i in 60:
		var px := Utils.rand(-half + 18, half - 18)
		var pz := Utils.rand(-half + 18, half - 18)
		if absf(px - river_x) < 20.0 or near_village.call(px, pz, 36.0) or near_city.call(px, pz) or near_farm.call(px, pz, 30.0):
			continue
		var roll := randf()
		(rubble if roll < 0.45 else (hedgehog if roll < 0.75 else burnt_wreck)).call(px, pz)
	# ---- [3A 8/10] 野外内容增强:更多岩石/石墙掩体/道具/干草堆 ----
	# 岩石增量(22→60,野外更密)
	for i in 38:
		var rx2 := Utils.rand(-half + 12, half - 12)
		var rz2 := Utils.rand(-half + 12, half - 12)
		if absf(rx2 - river_x) < 22.0 or near_village.call(rx2, rz2, 42.0) or near_city.call(rx2, rz2) or near_farm.call(rx2, rz2, 34.0):
			continue
		rock.call(rx2, rz2, Utils.rand(0.5, 1.8))
	# 矮石墙掩体(3-4 块矮岩横排,野外战斗掩体)
	var stone_wall := func(x: float, z: float, rot: float, len_s: float) -> void:
		var g := Node3D.new()
		var gy: float = G.ground_h.call(x, z)
		for i in 4:
			var rr := _ico(Utils.rand(0.5, 0.9) * len_s, rock_photo_mat)
			rr.position = Vector3(-1.8 * len_s + i * 1.2 * len_s, Utils.rand(0.15, 0.4), Utils.rand(-0.3, 0.3))
			rr.rotation = Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3))
			g.add_child(rr)
		g.position = Vector3(x, gy, z)
		g.rotation.y = rot
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 5.0 * len_s, 0.9, 1.2)
	for i in 14:
		var wx := Utils.rand(-half + 14, half - 14)
		var wz := Utils.rand(-half + 14, half - 14)
		if absf(wx - river_x) < 20.0 or near_village.call(wx, wz, 40.0) or near_city.call(wx, wz) or near_farm.call(wx, wz, 32.0):
			continue
		stone_wall.call(wx, wz, Utils.rand(TAU), Utils.rand(0.7, 1.3))
	# 战场道具增量(60→140)
	for i in 80:
		var px2 := Utils.rand(-half + 16, half - 16)
		var pz2 := Utils.rand(-half + 16, half - 16)
		if absf(px2 - river_x) < 18.0 or near_village.call(px2, pz2, 38.0) or near_city.call(px2, pz2) or near_farm.call(px2, pz2, 32.0):
			continue
		var roll2 := randf()
		(rubble if roll2 < 0.4 else (hedgehog if roll2 < 0.7 else burnt_wreck)).call(px2, pz2)
	# 野地干草堆(带碰撞的小掩体,农业区外散布)
	var hay_mat2 := _std(Color.html("#c8a85a"), 1.0)
	var hay_clump := func(x: float, z: float, s: float) -> void:
		var g := Node3D.new()
		var gy: float = G.ground_h.call(x, z)
		var hb := _cyl(0.8 * s, 1.0 * s, 1.1 * s, 9, hay_mat2)
		hb.position.y = 0.55 * s
		g.add_child(hb)
		g.position = Vector3(x, gy, z)
		_shadows_on(g)
		wg.add_child(g)
		add_collider.call(x, 0, z, 2.0 * s, 1.2 * s, 2.0 * s)
	for i in 26:
		var hx := Utils.rand(-half + 14, half - 14)
		var hz := Utils.rand(-half + 14, half - 14)
		if absf(hx - river_x) < 18.0 or near_village.call(hx, hz, 36.0) or near_city.call(hx, hz) or near_farm.call(hx, hz, 30.0):
			continue
		hay_clump.call(hx, hz, Utils.rand(0.6, 1.2))
	# 河岸沙袋防线
	for bank_z in [-260.0, -130.0, 130.0, 260.0]:
		for bank_s in [-1.0, 1.0]:
			sandbag.call(river_x + bank_s * 13.5, bank_z, Utils.rand(-0.3, 0.3))
	# [3A 8/10] LOD 视距裁剪:建筑/道具/岩石 >380m 不渲染(雾 far=500 内保留精模),
	# MultiMesh(树/灯/草)保留各自已有裁剪(树 700m)
	for ch in wg.get_children():
		if ch is MultiMeshInstance3D:
			continue
		_set_lod_range(ch, 380.0, 120.0)
	# 战场烟柱(大地图密度上调)
	G.map_fx["smokes"] = []
	var smoke_n: int = [6, 9, 12, 15][GraphicsQuality.current_level]
	for i in smoke_n:
		G.map_fx["smokes"].append({
			"x": Utils.rand(-half + 40, half - 40),
			"z": Utils.rand(-half + 40, half - 40),
			"t": Utils.rand(0.2),
		})
	# 远山天际线(雾中剪影)
	var hill_mat := _basic(Color.html("#6a7a5a"), true)
	for i in 20:
		var a := i / 20.0 * TAU + Utils.rand(-0.12, 0.12)
		var r := Utils.rand(half + 60, half + 160)
		var h := Utils.rand(40, 90)
		var m := _cone(Utils.rand(70, 120), h, 7, hill_mat)
		m.position = Vector3(cos(a) * r, h / 2 - 4, sin(a) * r)
		wg.add_child(m)


## ==================== 雪山哨站 ====================
## sc: 布局缩放系数(TDM 120m 圈定按 0.375 等比;默认 1.0 不影响征服/突破)
static func _snow_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, sandbag: Callable, container: Callable, barrier: Callable, rock_photo_mat: Material,
		sc := 1.0) -> void:
	var R: float = T.road
	var bunker_mat := _std_tex(Color.html("#b8bcc0"), 1.0, "rough_concrete")
	var wood_mat := _std_tex(Color.html("#8a7050"), 0.95, "plywood")
	var pine_trunk := _std(Color.html("#4a3a28"), 1.0)
	var pine_leaf := _std(Color.html("#2a4a3a"), 1.0)
	var pine_snow := _std(Color.html("#d8e4ec"), 1.0)
	var rock_mat: Material = rock_photo_mat
	# [PERF] 雪地建筑/树/岩 MultiMesh 批绘(碉堡/哨塔/松树/岩石,原每栋/棵独立 mesh 无法合批)
	var _sn_ubox := BoxMesh.new()
	_sn_ubox.size = Vector3.ONE
	var _sn_ucyl := CylinderMesh.new()
	_sn_ucyl.top_radius = 1.0
	_sn_ucyl.bottom_radius = 1.0
	_sn_ucyl.height = 1.0
	_sn_ucyl.radial_segments = 6
	var _sn_ucone := CylinderMesh.new()
	_sn_ucone.top_radius = 0.0
	_sn_ucone.bottom_radius = 1.0
	_sn_ucone.height = 1.0
	_sn_ucone.radial_segments = 8
	var _sn_uico := SphereMesh.new()
	_sn_uico.radius = 1.0
	_sn_uico.height = 2.0
	_sn_uico.radial_segments = 12
	_sn_uico.rings = 8
	var _sn_slit_mat := _basic(Color.html("#1a1e22"), true)
	var sm_buf := {}
	var sm_veg := {}   # [PERF] 小体积植被(松树/岩石):关闭阴影投射,省 4 级 cascade
	var sm_push := func(buf: Dictionary, mat: Material, mesh: Mesh, t: Transform3D) -> void:
		var entry = buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			buf[mat] = entry
		(entry["t"] as Array).append(t)
	var bunker := func(x: float, z: float, rot := 0.0) -> void:
		var w := Utils.rand(7, 10)
		var d := Utils.rand(6, 8)
		var h := Utils.rand(3, 4.2)
		var gh: float = G.ground_h.call(x, z)
		var rb := Basis(Vector3.UP, rot)
		sm_push.call(sm_buf, bunker_mat, _sn_ubox, Transform3D(rb.scaled(Vector3(w, h, d)), Vector3(x, gh + h / 2.0, z)))
		# 射击孔(世界朝向,与原逻辑一致)
		if absf(cos(rot)) > 0.5:
			sm_push.call(sm_buf, _sn_slit_mat, _sn_ubox, Transform3D(Basis().scaled(Vector3(w * 0.8, 0.3, 0.1)), Vector3(x, gh + h * 0.65, z + d / 2.0 + 0.01)))
		else:
			sm_push.call(sm_buf, _sn_slit_mat, _sn_ubox, Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3(w * 0.8, 0.3, 0.1)), Vector3(x + d / 2.0 + 0.01, gh + h * 0.65, z)))
		var ww := w if absf(cos(rot)) > 0.5 else d
		add_collider.call(x, 0, z, ww, h, d if ww == w else w)
		minimap_rects.append({ "x": x, "z": z, "w": ww, "d": d if ww == w else w })
	var tower := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		for lp in [[-1.2, -1.2], [1.2, -1.2], [-1.2, 1.2], [1.2, 1.2]]:
			sm_push.call(sm_buf, wood_mat, _sn_ubox, Transform3D(Basis().scaled(Vector3(0.25, 6, 0.25)), Vector3(x + lp[0], gh + 3, z + lp[1])))
		sm_push.call(sm_buf, wood_mat, _sn_ubox, Transform3D(Basis().scaled(Vector3(3.4, 2.2, 3.4)), Vector3(x, gh + 7.1, z)))
		sm_push.call(sm_buf, pine_snow, _sn_ucone, Transform3D(Basis(Vector3.UP, PI / 4.0).scaled(Vector3(5.6, 1.4, 5.6)), Vector3(x, gh + 9, z)))
		add_collider.call(x, 0, z, 2.8, 8, 2.8)
		minimap_rects.append({ "x": x, "z": z, "w": 2.8, "d": 2.8 })
	var pine := func(x: float, z: float) -> void:
		var gh: float = G.ground_h.call(x, z)
		var h := Utils.rand(4, 7)
		sm_push.call(sm_veg, pine_trunk, _sn_ucyl, Transform3D(Basis().scaled(Vector3(0.44, h * 0.4, 0.44)), Vector3(x, gh + h * 0.2, z)))
		sm_push.call(sm_veg, pine_leaf, _sn_ucone, Transform3D(Basis().scaled(Vector3(h * 0.64, h * 0.55, h * 0.64)), Vector3(x, gh + h * 0.55, z)))
		sm_push.call(sm_veg, pine_snow if randf() < 0.6 else pine_leaf, _sn_ucone, Transform3D(Basis().scaled(Vector3(h * 0.48, h * 0.45, h * 0.48)), Vector3(x, gh + h * 0.82, z)))
		add_collider.call(x, 0, z, 0.7, h, 0.7)
	var rock := func(x: float, z: float, s := 1.0) -> void:
		var gh: float = G.ground_h.call(x, z)
		var rr := Basis.from_euler(Vector3(Utils.rand(3), Utils.rand(3), Utils.rand(3)))
		var rs := Utils.rand(1, 2) * s
		sm_push.call(sm_veg, rock_mat, _sn_uico, Transform3D(rr.scaled(Vector3(rs, rs, rs)), Vector3(x, gh + Utils.rand(0.3, 0.7) * s, z)))
		add_collider.call(x, 0, z, 2 * s, 1.5 * s, 2 * s)
	var tower_spots := []
	var blocks := [-142, -94, -66, -14, 14, 66, 94, 142]
	if sc < 1.0:
		blocks = [-66, -14, 14, 66]   # TDM 120m 圈定:仅取中心 4 列,避免建筑探出边界墙
	for i in blocks.size() - 1:
		for j in blocks.size() - 1:
			var cx: float = (blocks[i] + blocks[i + 1]) / 2.0 * sc
			var cz: float = (blocks[j] + blocks[j + 1]) / 2.0 * sc
			var w: float = (blocks[i + 1] - blocks[i]) * sc
			if w < 40 * sc:
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
		pine.call(Utils.rand(-145 * sc, 145 * sc), Utils.rand(-145 * sc, 145 * sc))
	for i in 40:
		var roll := randi() % 5
		match roll:
			0: crate.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc))
			1: rock.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc), Utils.rand(0.8, 1.8))
			2: sandbag.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R, 0.0, R]) + Utils.rand(-6, 6), Utils.rand(PI))
			3: container.call(Utils.rand(-140 * sc, 140 * sc), Utils.rand(-140 * sc, 140 * sc), Utils.rand(PI))
			4: barrier.call(Utils.rand(-140 * sc, 140 * sc), Utils.choice([-R, 0.0, R]) + Utils.rand(-5, 5), Utils.rand(PI))
	_flush_prop_mm(wg, sm_buf)
	_flush_prop_mm(wg, sm_veg, 0.0, false)
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
		var bx := Utils.rand(-140 * sc, 140 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if on_road2.call(bx, bz, 4.5) or near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 1.6):
				continue
			push.call(sn_crate_mat, ubox2, bx, bz, Utils.rand(-0.3, 0.3), 0.65, Vector3(1.3, 1.3, 1.3))
			add_collider.call(bx, 0, bz, 1.3, 1.3, 1.3)
			break
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
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
		var bx := Utils.rand(-120 * sc, 120 * sc)
		var bz := Utils.rand(-120 * sc, 120 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_flag3.call(bx, bz, 20.0) or not clear_spot.call(bx, bz, 0.8):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# [3A 内容 8/10] 雪地科考站 + 附属建筑
	_snow_research_station(wg, add_collider, minimap_rects)
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


## ==================== [3A 内容 8/10] 雪地科考站 + 附属建筑(精细模型) ====================
## 科考站:主站房(白金属板+窗户阵列)+ 雷达罩(半球+基座)+ 天线塔(桁架+抛物面盘)
## + 太阳能板阵列 + 冰钻塔 + 集装箱舱 + 哨塔
static func _snow_research_station(wg: Node3D, add_collider: Callable, minimap_rects: Array) -> void:
	var white_mat := _std_tex(Color.WHITE, 0.6, "white_metal", 0.3)          # 白金属板(科考站主体)
	var wcorr_mat := _std_tex(Color.WHITE, 0.7, "white_corrugated", 0.2)     # 白波纹(屋顶)
	var dark_mat := _std_tex(Color.html("#5a5e64"), 0.6, "metal_plate", 0.4) # 深金属(结构)
	var blue_mat := _std(Color.html("#1a3a5a"), 0.8, 0.2)                    # 深蓝(太阳能板/窗)
	var glass_mat := _basic(Color.html("#9fd0f0"), true)                     # 发光窗
	var ghf := G.ground_h
	var near_flag := func(x: float, z: float, r: float) -> bool:
		for f in G.flags:
			var dx: float = x - f.pos.x
			var dz: float = z - f.pos.z
			if dx * dx + dz * dz < r * r:
				return true
		return false
	var pick_spot := func(min_r: float) -> Vector2:
		for t in 60:
			var sx := Utils.rand(-125.0, 125.0)
			var sz := Utils.rand(-125.0, 125.0)
			if near_flag.call(sx, sz, min_r):
				continue
			return Vector2(sx, sz)
		return Vector2.ZERO
	# ---- 科考站主楼(白盒 + 屋顶设备 + 窗户阵列) ----
	var main_building := func(x: float, z: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var body := _box(13.0, 3.6, 7.5, white_mat)
		body.position.y = 1.8
		g2.add_child(body)
		var roof := _box(13.6, 0.3, 8.1, wcorr_mat)
		roof.position.y = 3.75
		g2.add_child(roof)
		# 屋顶设备(通风/天线)
		for i in 3:
			var vent := _cyl(0.35, 0.35, 1.1, 8, dark_mat)
			vent.position = Vector3(-4.0 + i * 4.0, 4.4, 2.4)
			g2.add_child(vent)
		var roo_ant := _cyl(0.05, 0.05, 2.6, 4, dark_mat)
		roo_ant.position = Vector3(4.2, 5.1, 0)
		g2.add_child(roo_ant)
		# 窗户阵列(蓝色发光)
		for i in 5:
			var win := _box(1.7, 1.2, 0.12, glass_mat)
			win.position = Vector3(-4.6 + i * 2.3, 1.9, 3.8)
			g2.add_child(win)
			var win2 := _box(1.7, 1.2, 0.12, glass_mat)
			win2.position = Vector3(-4.6 + i * 2.3, 1.9, -3.8)
			g2.add_child(win2)
		# 入口舱(连接雪地)
		var airlock := _cyl(1.1, 1.1, 2.2, 10, white_mat)
		airlock.rotation.x = PI / 2.0
		airlock.position = Vector3(0, 1.1, 4.9)
		g2.add_child(airlock)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 13.0, 4.2, 8.1)
		minimap_rects.append({ "x": x, "z": z, "w": 13.0, "d": 8.1 })
	# ---- 雷达罩(白色半球 + 基座 + 天线) ----
	var radome := func(x: float, z: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var base := _cyl(3.0, 3.2, 1.2, 16, white_mat)
		base.position.y = 0.6
		g2.add_child(base)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 3.0
		sm.height = 3.0
		sm.radial_segments = 16
		sm.rings = 8
		dome.mesh = sm
		dome.material_override = white_mat
		dome.position.y = 2.9
		g2.add_child(dome)
		var mast := _cyl(0.06, 0.06, 3.2, 4, dark_mat)
		mast.position = Vector3(0.8, 4.6, 0.6)
		mast.rotation.z = 0.3
		g2.add_child(mast)
		var beacon := _cyl(0.18, 0.18, 0.25, 8, _std(Color.html("#ff6a3a"), 0.4))
		beacon.position = Vector3(1.15, 6.0, 0.8)
		g2.add_child(beacon)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 6.4, 3.0, 6.4)
	# ---- 天线塔(桁架 4 腿 + 交叉撑 + 抛物面盘) ----
	var dish_tower := func(x: float, z: float, h: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		for s in [-1.0, 1.0]:
			for t in [-1.0, 1.0]:
				var leg := _cyl(0.08, 0.08, h, 5, dark_mat)
				leg.position = Vector3(s * 0.8, h / 2.0, t * 0.8)
				leg.rotation.x = t * 0.12
				leg.rotation.z = -s * 0.12
				g2.add_child(leg)
		for i in 3:
			var brace := _box(1.7, 0.1, 0.1, dark_mat)
			brace.position = Vector3(0, h * float(i + 1) / 4.0, 0)
			g2.add_child(brace)
			var brace2 := _box(0.1, 0.1, 1.7, dark_mat)
			brace2.position = Vector3(0, h * float(i + 1) / 4.0, 0)
			g2.add_child(brace2)
		var plat := _box(1.6, 0.22, 1.6, dark_mat)
		plat.position.y = h
		g2.add_child(plat)
		# 抛物面天线(扁锥盘)
		var dish := _cone(1.5, 0.7, 14, white_mat)
		dish.rotation.x = PI / 2.0
		dish.position = Vector3(0, h + 0.8, 0.4)
		g2.add_child(dish)
		var feed := _cyl(0.03, 0.03, 1.0, 4, dark_mat)
		feed.position = Vector3(0, h + 1.1, 1.7)
		g2.add_child(feed)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 2.2, h + 1.4, 2.2)
	# ---- 太阳能板阵列(倾斜薄板) ----
	var solar := func(x: float, z: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var frame := _box(5.2, 0.18, 3.2, dark_mat)
		frame.position.y = 0.55
		frame.rotation.x = -0.6
		g2.add_child(frame)
		for i in 3:
			for j in 2:
				var panel := _box(1.5, 0.05, 1.2, blue_mat)
				panel.position = Vector3(-2.6 + 1.6 + i * 1.6, 0.55, -1.0 + 1.0 + j * 1.0)
				panel.rotation.x = -0.6
				g2.add_child(panel)
		# 支撑腿
		for s in [-2.2, 2.2]:
			var leg := _cyl(0.07, 0.07, 1.1, 5, dark_mat)
			leg.position = Vector3(s, 0.55, 0)
			g2.add_child(leg)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		_shadows_on(g2)
		wg.add_child(g2)
	# ---- 冰钻塔(桁架 + 顶部滑轮) ----
	var drill_tower := func(x: float, z: float, h: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		for s in [-1.0, 1.0]:
			var leg := _cyl(0.12, 0.12, h, 6, dark_mat)
			leg.position = Vector3(s * 1.2, h / 2.0, 0)
			leg.rotation.x = 0.16
			g2.add_child(leg)
		for i in 3:
			var brace := _box(2.6, 0.12, 0.12, dark_mat)
			brace.position = Vector3(0, h * float(i + 1) / 4.0, 0)
			g2.add_child(brace)
		var plat := _box(2.4, 0.25, 1.6, dark_mat)
		plat.position.y = h
		g2.add_child(plat)
		var wheel := _cyl(0.45, 0.45, 0.25, 10, dark_mat)
		wheel.rotation.x = PI / 2.0
		wheel.position = Vector3(0, h + 0.5, 0)
		g2.add_child(wheel)
		# 钻杆(垂下)
		var drill := _cyl(0.12, 0.12, 3.0, 6, dark_mat)
		drill.position = Vector3(0, h - 1.5, 0)
		g2.add_child(drill)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 3.0, h + 0.8, 2.2)
	# ---- 集装箱舱(白盒 + 波纹顶) ----
	var pod := func(x: float, z: float, rot: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		var body := _box(6.0, 2.5, 2.4, white_mat)
		body.position.y = 1.25
		g2.add_child(body)
		var roof := _box(6.2, 0.15, 2.6, wcorr_mat)
		roof.position.y = 2.6
		g2.add_child(roof)
		var win := _box(1.2, 0.8, 0.1, glass_mat)
		win.position = Vector3(0, 1.5, 1.25)
		g2.add_child(win)
		var base := _box(6.4, 0.25, 2.8, dark_mat)
		base.position.y = 0.12
		g2.add_child(base)
		g2.position = Vector3(x, gy, z)
		g2.rotation.y = rot
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 6.4, 2.9, 2.8)
	# ---- 哨塔(4 腿 + 平台 + 顶棚) ----
	var sentry_tower := func(x: float, z: float) -> void:
		var g2 := Node3D.new()
		var gy: float = ghf.call(x, z)
		for s in [-1.0, 1.0]:
			for t in [-1.0, 1.0]:
				var leg := _cyl(0.1, 0.1, 4.4, 6, dark_mat)
				leg.position = Vector3(s * 1.1, 2.2, t * 1.1)
				leg.rotation.x = t * 0.1
				leg.rotation.z = -s * 0.1
				g2.add_child(leg)
		var plat := _box(2.8, 0.22, 2.8, white_mat)
		plat.position.y = 4.4
		g2.add_child(plat)
		var rail := _box(2.8, 0.5, 0.08, dark_mat)
		rail.position.y = 4.9
		for r in 4:
			var rr := rail.duplicate()
			rr.rotation.y = r * PI / 2.0
			g2.add_child(rr)
		var roof2 := _cone(2.2, 1.0, 6, wcorr_mat)
		roof2.position.y = 5.7
		g2.add_child(roof2)
		g2.position = Vector3(x, gy, z)
		_shadows_on(g2)
		wg.add_child(g2)
		add_collider.call(x, 0, z, 3.0, 6.2, 3.0)
	# ---- 布局:主站 + 雷达 + 天线塔 + 太阳能 + 冰钻塔 + 舱体 + 哨塔 ----
	var st1: Vector2 = pick_spot.call(60.0)
	main_building.call(st1.x, st1.y, Utils.rand(TAU))
	radome.call(st1.x + 14.0, st1.y + 6.0)
	dish_tower.call(st1.x - 12.0, st1.y + 9.0, 8.0)
	solar.call(st1.x + 8.0, st1.y - 10.0, Utils.rand(TAU))
	solar.call(st1.x + 16.0, st1.y - 8.0, Utils.rand(TAU))
	pod.call(st1.x - 9.0, st1.y - 7.0, Utils.rand(TAU))
	var st2: Vector2 = pick_spot.call(50.0)
	drill_tower.call(st2.x, st2.y, 7.0)
	pod.call(st2.x + 8.0, st2.y + 4.0, Utils.rand(TAU))
	sentry_tower.call(st2.x - 9.0, st2.y - 5.0)
	solar.call(st2.x + 5.0, st2.y - 8.0, Utils.rand(TAU))


## ==================== 丛林河谷(突破) ====================
## sc: 布局缩放系数(TDM 120m 圈定按 1/3 等比;默认 1.0 不影响突破)
static func _jungle_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, near_obj: Callable, rock_photo_mat: Material,
		sc := 1.0) -> void:
	var trunk_mat := _std(Color.html("#4a3a26"), 1.0)
	var leaf_mat := _std(Color.html("#2e5230"), 1.0)
	var leaf_mat2 := _std(Color.html("#3a6036"), 1.0)
	var bush_mat := _std(Color.html("#3c5c2e"), 1.0)
	var wood_mat2 := _std_tex(Color.html("#8a6a44"), 0.95, "plywood")
	var thatch_mat := _std(Color.html("#9a7c4a"), 1.0)
	# [8/10] 丛林树/灌木改 MultiMesh 批绘(原 150 树×3 部件 + 85 灌木×3 部件单实例 ≈ 700 draw;
	# 批后 5 组 draw,碰撞保留)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.34
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	var crown1_mesh := SphereMesh.new()
	crown1_mesh.radius = 0.36
	crown1_mesh.height = 0.72
	crown1_mesh.radial_segments = 6
	crown1_mesh.rings = 4
	var crown2_mesh := SphereMesh.new()
	crown2_mesh.radius = 0.26
	crown2_mesh.height = 0.52
	crown2_mesh.radial_segments = 6
	crown2_mesh.rings = 4
	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 0.5
	bush_mesh.height = 1.0
	bush_mesh.radial_segments = 6
	bush_mesh.rings = 4
	var tree_buf := {}
	var tree_push := func(mat: Material, mesh: Mesh, x: float, z: float, rot: float, y_off: float, s: Vector3) -> void:
		var gh: float = G.ground_h.call(x, z)
		var entry = tree_buf.get(mat)
		if entry == null:
			entry = { "mesh": mesh, "t": [] }
			tree_buf[mat] = entry
		(entry["t"] as Array).append(Transform3D(Basis(Vector3.UP, rot).scaled(s), Vector3(x, gh + y_off, z)))
	var jungle_tree := func(x: float, z: float) -> void:
		var h := Utils.rand(6, 10)
		var leaf_a: Material = leaf_mat if randf() < 0.5 else leaf_mat2
		tree_push.call(trunk_mat, trunk_mesh, x, z, Utils.rand(TAU), h * 0.5, Vector3(1, h, 1))
		tree_push.call(leaf_a, crown1_mesh, x, z, Utils.rand(TAU), h * 0.92, Vector3(1, 0.75, 1) * (h * 0.36 / 0.36))
		tree_push.call(leaf_mat2, crown2_mesh, x + Utils.rand(-0.8, 0.8), z + Utils.rand(-0.8, 0.8), Utils.rand(TAU), h * 1.12, Vector3(1, 0.7, 1) * (h * 0.26 / 0.26))
		add_collider.call(x, 0, z, 0.8, h, 0.8)
	var bush := func(x: float, z: float) -> void:
		for i in 3:
			var s := Utils.rand(0.5, 1.1)
			tree_push.call(bush_mat, bush_mesh, x + Utils.rand(-0.7, 0.7), z + Utils.rand(-0.7, 0.7), Utils.rand(TAU), Utils.rand(0.2, 0.5), Vector3(s, s * 0.7, s))
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
		x_j = Utils.rand(-165 * sc, 165 * sc)
		z_j = Utils.rand(-165 * sc, 165 * sc)
		if absf(x_j) < 12 or near_obj.call(x_j, z_j, 19):
			continue
		if absf(z_j - T.river) < 9 and absf(x_j) < 18:
			continue
		jungle_tree.call(x_j, z_j)
	for i in 85:
		x_j = Utils.rand(-160 * sc, 160 * sc)
		z_j = Utils.rand(-160 * sc, 160 * sc)
		if absf(x_j) < 9 or near_obj.call(x_j, z_j, 15):
			continue
		bush.call(x_j, z_j)
	for i in 14:
		x_j = Utils.rand(-150 * sc, 150 * sc)
		z_j = Utils.rand(-150 * sc, 150 * sc)
		if absf(x_j) < 10 or near_obj.call(x_j, z_j, 16):
			continue
		log_f.call(x_j, z_j)
	for i in 16:
		x_j = Utils.rand(-150 * sc, 150 * sc)
		z_j = Utils.rand(-150 * sc, 150 * sc)
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
			var bx := Utils.rand(-150 * sc, 150 * sc)
			var bz := Utils.rand(-150 * sc, 150 * sc)
			if absf(bx) < 10 or near_obj.call(bx, bz, 18.0):
				continue
			bush.call(bx, bz)
			break
	# 枯木(倾斜深色圆柱,纯装饰)
	var dead_mat := _std(Color.html("#3a332a"), 1.0)
	for k in 4:
		for t in 40:
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
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
			var bx := Utils.rand(-120 * sc, 120 * sc)
			var bz := Utils.rand(-120 * sc, 120 * sc)
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
			var bx := Utils.rand(-120 * sc, 120 * sc)
			var bz := Utils.rand(-120 * sc, 120 * sc)
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
			var bx := Utils.rand(-130 * sc, 130 * sc)
			var bz := Utils.rand(-130 * sc, 130 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
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
			var bx := Utils.rand(-140 * sc, 140 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if absf(bx) < 10 or near_obj.call(bx, bz, 20.0):
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# [8/10] 丛林树/灌木 MultiMesh 批绘提交(420m 图内 420m 裁剪,远处树雾中不可见)
	# [PERF] 散布树/灌木关闭阴影投射(密林中阴影本就重叠,与密林环松树一致;省 4 级 cascade)
	_flush_prop_mm(wg, tree_buf, 420.0, false)
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
## sc: 布局缩放系数(TDM 120m 圈定按 1/3 等比;默认 1.0 不影响突破)
static func _harbor_blocks(T, wg: Node3D, add_collider: Callable, minimap_rects: Array,
		crate: Callable, barrel: Callable, sandbag: Callable, car: Callable, barrier: Callable,
		container: Callable, cont_mats: Array, near_obj: Callable, roof_mat: Material,
		sc := 1.0) -> void:
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
	var port_z := -150.0 * sc
	while port_z <= 150.0 * sc:
		for bx in [-101, 101]:
			var bo := _cyl(0.28, 0.34, 0.8, 8, bollard_mat)
			bo.position = Vector3(bx * sc, G.ground_h.call(bx * sc, port_z) + 0.4, port_z)
			wg.add_child(bo)
		port_z += 15
	# 路灯(黄昏发光)
	var lamp_mat := _basic(Color.html("#ffd9a0"), true)
	port_z = -140.0 * sc
	while port_z <= 140.0 * sc:
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
		var x: float = side * Utils.rand(24 * sc, 92 * sc)
		var zz := Utils.rand(-150 * sc, 150 * sc)
		if near_obj.call(x, zz, 17):
			continue
		cont_stack.call(x, zz, 0.0 if randf() < 0.7 else PI / 2 + Utils.rand(-0.1, 0.1))
	# 仓库群
	for i in 8:
		var side := -1.0 if randf() < 0.5 else 1.0
		var x: float = side * Utils.rand(36 * sc, 88 * sc)
		var zz := Utils.rand(-140 * sc, 140 * sc)
		if near_obj.call(x, zz, 22):
			continue
		warehouse.call(x, zz, Utils.rand(-0.2, 0.2))
	crane.call(-34 * sc, 34 * sc)
	crane.call(36 * sc, 96 * sc)
	# 道具散布
	for i in 42:
		var roll := randi() % 5
		match roll:
			0: barrel.call(Utils.rand(-95 * sc, 95 * sc), Utils.rand(-150 * sc, 150 * sc))
			1: crate.call(Utils.rand(-95 * sc, 95 * sc), Utils.rand(-150 * sc, 150 * sc))
			2: sandbag.call(Utils.rand(-60 * sc, 60 * sc), Utils.rand(-140 * sc, 140 * sc), Utils.rand(PI))
			3: car.call(Utils.rand(-14, 14) + Utils.choice([-16.0, 16.0]), Utils.rand(-150 * sc, 150 * sc), PI / 2 + Utils.rand(-0.25, 0.25), Color.html("#5a6a7a"))
			4: barrier.call(Utils.rand(-40 * sc, 40 * sc), Utils.rand(-140 * sc, 140 * sc), Utils.rand(PI))
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
			var bx := Utils.rand(-90 * sc, 90 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_obj.call(bx, bz, 15.0) or absf(bx) > 92 * sc:
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
			var bx := Utils.rand(-92 * sc, 92 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_obj.call(bx, bz, 15.0):
				continue
			push.call(rope_mat, rope_mesh, bx, bz, Utils.rand(TAU), 0.012, Vector3.ONE)
			break
	# 斜置变形集装箱(2 个,带碰撞)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-85 * sc, 85 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_obj.call(bx, bz, 20.0) or absf(bx) > 92 * sc:
				continue
			container.call(bx, bz, Utils.choice([-0.3, 0.25, -0.2, 0.3]))
			break
	# 叉车(黄色车体 + 货叉,2 辆,带碰撞)
	var fork_mat := _std(Color.html("#d0a020"), 0.5, 0.5)
	var fork_dark := _std(Color.html("#3a3a3a"), 0.7, 0.4)
	for k in 2:
		for t in 40:
			var bx := Utils.rand(-80 * sc, 80 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_obj.call(bx, bz, 20.0) or absf(bx) > 92 * sc:
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
			var bx := Utils.rand(-92 * sc, 92 * sc)
			var bz := Utils.rand(-140 * sc, 140 * sc)
			if near_obj.call(bx, bz, 20.0) or absf(bx) > 92 * sc:
				continue
			for j2 in 5:
				push.call(shell_mat, shell_mesh, bx + Utils.rand(-0.5, 0.5), bz + Utils.rand(-0.5, 0.5), Utils.rand(TAU), 0.035, Vector3.ONE)
			break
	_flush_prop_mm(wg, buf)
	# [8/10 撤销] 港口遮挡剔除实测无收益(avg/drawcalls 未改善),按"无收益则撤销"移除
	# 远处货轮剪影(海上)
	var ship_mat := _basic(Color.html("#2e3440"), true)
	for sd in [[-165, -60, 0.2], [170, 70, -0.3]]:
		var ship := Node3D.new()
		ship.add_to_group("sea_decor")   # 海上背景货轮(界外装饰;TDM 圈定断言豁免)
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
	# [8/10 撤销] 雷达站遮挡实测无收益(avg 下降),按"无收益则撤销"移除
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
			# [PERF] 内联随机(免 Utils.rand 静态调用开销,~500 次/帧)
			var y: float = p.y - dt * (2.0 + randf() * 2.0)
			var x: float = p.x + dt * 0.8
			# 着地判定:隔帧采样预烘焙高度网格(复用静态缓存,免字典查找)
			var gy := 0.0
			if not hg.is_empty() and (i & 1) == parity:
				gy = Utils._ground_h_fast(x, p.z)
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
	if T.mode == "br":
		count = int(count * clampf(T.size / 320.0, 1.0, 3.0))   # BR 大地图按面积增密
	if count <= 0:
		return
	var size: float = T.size
	var road: float = T.road
	var river: float = -9999.0 if T.river == null else T.river
	var sea: bool = T.sea
	var tints := {
		"city": Color.html("#5f7148"), "desert": Color.html("#94865a"),
		"bt_jungle": Color.html("#3f5d30"), "bt_harbor": Color.html("#5d6a52"),
		"bt_peak": Color.html("#7d8686"), "br_valley": Color.html("#3f5d30"),
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
		if T.mode == "br":
			# BR 山谷:避开河道与村庄聚落
			if absf(x - river) < 12.0:
				continue
			var near_v := false
			for vv in (T.extra.get("villages", []) as Array):
				var ddx: float = x - vv["x"]
				var ddz: float = z - vv["z"]
				if ddx * ddx + ddz * ddz < 42.0 * 42.0:
					near_v = true
					break
			if near_v:
				continue
		elif not is_bt:
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


## ==================== 自然化地图边界(取消箱庭围墙 → 真实战场外延) ====================
## 保留隐形碰撞边界(±bounds+4 的 20m 高碰撞体);移除可见围墙后,在可玩区外构建:
##   1) 地面延伸裙(粗网格环形 + 主题色)——消除"地形截断/草地消失"
##   2) 主题天然边界环(城市街区/峡谷岩壁/雪山松林/丛林/港区/山地)——替代围墙
##   3) 远景天际线(城市/台地/雪山/远山)——世界延伸感,天际不出现空白
##   4) 世界延伸道具(电线塔/远方车队/烟柱/远处灯光)
## 基地方向(±Z)留缺口:公路延出地图 + 检查站自然封锁(Soft Restriction)

## 基地缺口判定:±Z 轴方向(±35° 楔形)不放置边界环(基地公路由此延出)
static func _bnd_base_gap(ang: float) -> bool:
	var a := wrapf(ang, -PI, PI)
	var g := 0.61
	return absf(a) < g or absf(absf(a) - PI) < g


## 基地保护区判定:±Z 缺口楔形 + 基地矩形(出生点/载具出生区)统称保护区,
## 边界环物件(山体/冰丘/沙丘/丘陵等)一律不得侵入——防止玩家/NPC/载具出生在网格内部或卡住
static func _bnd_in_base_zone(x: float, z: float, half: float) -> bool:
	if _bnd_base_gap(atan2(x, z)):
		return true
	var base_z: float = half - 16.0
	return absf(x) < 34.0 and absf(absf(z) - base_z) < 26.0


## SurfaceTool 轴对齐盒(无光照材质用,法线朝上即可)
static func _bnd_st_box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var a := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	for vi in [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1, 3, 2, 6, 3, 6, 7, 0, 3, 7, 0, 7, 4, 1, 5, 6, 1, 6, 2]:
		st.add_vertex(a[vi])


## 地面延伸裙:环形双层网格(接缝带细网格精确贴地 + 外环粗网格),延伸到天际
## 使用与主地面相同的地面材质 + 连续 UV(map_tex 越界 clamp 为边缘色 + 噪声细节层),消除贴图接缝
## [FIX] 滚动地形(雪山/丛林)上粗网格(24m)弦线会凸出主地面最高 0.4m(胸口穿地感),
##       接缝带(r<half+55)改用 10m 网格精确贴合;外环保持 24m 粗网格省开销
static func _bnd_skirt(wg: Node3D, theme_id: String, T, half: float, is_bt: bool) -> void:
	# 裙长须覆盖最外圈远景底部(防止远景悬空);城市无雾需最长裙 + 楼群覆盖地平线
	var skirt_len: float = 820.0 if theme_id == "city" else (400.0 if (theme_id == "desert" or theme_id == "snow") else 320.0)
	var r_out := half + skirt_len
	var size2: float = half * 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for band in [[half - 6.0, half + 55.0, 10.0], [half + 55.0, r_out, 24.0]]:
		var r_in2: float = band[0]
		var r_out2: float = band[1]
		var cell: float = band[2]
		if r_in2 >= r_out2:
			continue
		var n := int(ceil(r_out2 / cell))
		for i in range(-n, n):
			for j in range(-n, n):
				var cx := i * cell + cell * 0.5
				var cz := j * cell + cell * 0.5
				var d := sqrt(cx * cx + cz * cz)
				if d <= r_in2 or d >= r_out2:
					continue
				var v00 := Vector3(i * cell, 0, j * cell)
				var v10 := Vector3((i + 1) * cell, 0, j * cell)
				var v01 := Vector3(i * cell, 0, (j + 1) * cell)
				var v11 := Vector3((i + 1) * cell, 0, (j + 1) * cell)
				# [FIX] for-in 循环变量是 Vector3 值类型副本,y 赋值会丢失 → 改为数组索引写入
				var verts4 := [v00, v10, v01, v11]
				for vi in 4:
					var h4: float = G.ground_h.call(verts4[vi].x, verts4[vi].z) if G.ground_h.is_valid() else 0.0
					verts4[vi].y = h4 - 0.06
				v00 = verts4[0]
				v10 = verts4[1]
				v01 = verts4[2]
				v11 = verts4[3]
				var uv00 := Vector2((v00.x + half) / size2, (v00.z + half) / size2)
				var uv10 := Vector2((v10.x + half) / size2, (v10.z + half) / size2)
				var uv01 := Vector2((v01.x + half) / size2, (v01.z + half) / size2)
				var uv11 := Vector2((v11.x + half) / size2, (v11.z + half) / size2)
				st.set_normal(Vector3.UP); st.set_uv(uv00); st.add_vertex(v00)
				st.set_normal(Vector3.UP); st.set_uv(uv10); st.add_vertex(v10)
				st.set_normal(Vector3.UP); st.set_uv(uv01); st.add_vertex(v01)
				st.set_normal(Vector3.UP); st.set_uv(uv10); st.add_vertex(v10)
				st.set_normal(Vector3.UP); st.set_uv(uv11); st.add_vertex(v11)
				st.set_normal(Vector3.UP); st.set_uv(uv01); st.add_vertex(v01)
	var skirt := MeshInstance3D.new()
	skirt.mesh = st.commit()
	skirt.material_override = TerrainTextures.make_ground_material(theme_id, T)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.set_meta("no_lod", true)
	wg.add_child(skirt)


## 松林环(MultiMesh 单锥松影;雪地/丛林/夜山共用;避开基地保护区)
static func _bnd_pines_mm(wg: Node3D, leaf_mat: Material, bnd: float, count: int, r0: float, r1: float, half: float) -> void:
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 1.0
	cone_mesh.height = 2.0
	cone_mesh.radial_segments = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone_mesh
	var pts: Array = []
	var k := 0
	while pts.size() < count and k < count * 4:
		k += 1
		var a := Utils.rand(TAU)
		var r := Utils.rand(bnd + r0, bnd + r1)
		var px := sin(a) * r
		var pz := cos(a) * r
		if _bnd_in_base_zone(px, pz, half):
			continue
		pts.append([px, pz])
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := Utils.rand(2.2, 5.5)
		var gy: float = G.ground_h.call(pts[i][0], pts[i][1]) if G.ground_h.is_valid() else 0.0
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, Utils.rand(TAU)).scaled(Vector3(s * 0.55, s, s * 0.55)),
			Vector3(pts[i][0], gy - 0.05, pts[i][1])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = leaf_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wg.add_child(mmi)


## 电线塔环(MultiMesh 单网格塔,2 条线延伸向远方)
static func _bnd_towers(wg: Node3D, bnd: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lp in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_bnd_st_box(st, Vector3(lp.x * 1.6, 9.0, lp.y * 1.6), Vector3(0.35, 18.0, 0.35))
	for y2 in [6.0, 12.0, 18.0]:
		_bnd_st_box(st, Vector3(0, y2, 0), Vector3(3.4, 0.3, 3.4))
	var tower_mesh := st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tower_mesh
	var pts: Array = []
	var k := 0
	while pts.size() < 10 and k < 60:
		k += 1
		var a := Utils.rand(TAU)
		if _bnd_base_gap(a):
			continue
		pts.append([sin(a) * Utils.rand(bnd + 40, bnd + 110), cos(a) * Utils.rand(bnd + 40, bnd + 110)])
	mm.instance_count = pts.size()
	for i in pts.size():
		var gy: float = G.ground_h.call(pts[i][0], pts[i][1]) if G.ground_h.is_valid() else 0.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(pts[i][0], gy - 0.2, pts[i][1])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wg.add_child(mmi)


## 通用世界延伸:远处烟柱(加入战场烟柱系统,update_map 驱动)
static func _bnd_smokes(bnd: float) -> void:
	if not G.map_fx.has("smokes"):
		return
	for k2 in 8:
		var a := k2 / 8.0 * TAU + Utils.rand(-0.3, 0.3)
		G.map_fx["smokes"].append({
			"x": cos(a) * Utils.rand(bnd + 70, bnd + 170),
			"z": sin(a) * Utils.rand(bnd + 70, bnd + 170),
			"t": Utils.rand(0.2),
		})


## ==================== 基地临时指挥部(我军部署点:帐篷/沙袋/电台/队旗/地图桌/发电机) ====================
## 布置于可玩边界内侧基地区,环绕出生点但不遮挡出生点;带碰撞体(玩家/NPC/载具可绕行不可穿入)
static func _build_base_camp(wg: Node3D, add_collider: Callable, half: float, side: float, team: String) -> void:
	var bz: float = side * (half - 16.0)
	var gh := func(x: float, z: float) -> float:
		return G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
	var canvas := _std_tex(Color.html("#4a5a3a"), 0.95, "plywood")
	var sand := _std(Color.html("#9a8a68"), 1.0)
	var wood := _std_tex(Color.html("#8a6f4e"), 0.95, "plywood")
	var metal := _std_tex(Color.html("#5a5e64"), 0.6, "metal_plate", 0.4)
	var dark := _std(Color.html("#23252a"), 1.0)
	# ---- 指挥帐篷(双坡顶) ----
	var tent := func(x: float, z: float, rot: float) -> void:
		var g := Node3D.new()
		var body := _box(5.0, 1.7, 3.4, canvas)
		body.position.y = 0.85
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(body)
		var roof1 := _box(5.0, 0.35, 2.1, dark)
		roof1.position = Vector3(0, 1.85, -0.7)
		roof1.rotation.x = 0.42
		g.add_child(roof1)
		var roof2 := _box(5.0, 0.35, 2.1, dark)
		roof2.position = Vector3(0, 1.85, 0.7)
		roof2.rotation.x = -0.42
		g.add_child(roof2)
		var door := _box(1.2, 1.3, 0.08, dark)
		door.position = Vector3(0, 0.65, 1.74)
		g.add_child(door)
		g.position = Vector3(x, gh.call(x, z), z)
		g.rotation.y = rot
		wg.add_child(g)
		add_collider.call(x, 0, z, 5.0, 2.2, 3.4)
	# ---- 沙袋墙(长条) ----
	var sandbag_wall := func(x: float, z: float, len: float, rot: float) -> void:
		var g := Node3D.new()
		for s in int(len / 1.2):
			var b := _box(1.0, 0.5, 0.5, sand)
			b.position = Vector3(-len / 2.0 + s * 1.2 + 0.6, 0.25, 0)
			b.rotation.y = Utils.rand(-0.06, 0.06)
			g.add_child(b)
		for s in int(len / 2.4):
			var b2 := _box(1.0, 0.5, 0.5, sand)
			b2.position = Vector3(-len / 2.0 + s * 2.4 + 1.2, 0.75, Utils.rand(-0.1, 0.1))
			b2.rotation.y = Utils.rand(-0.08, 0.08)
			g.add_child(b2)
		g.position = Vector3(x, gh.call(x, z), z)
		g.rotation.y = rot
		wg.add_child(g)
		add_collider.call(x, 0, z, len, 1.0, 0.7)
	# ---- 电台天线(桅杆 + 十字天线) ----
	var radio_mast := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var pole := _cyl(0.06, 0.08, 7.0, 6, metal)
		pole.position.y = 3.5
		g.add_child(pole)
		for k in 3:
			var arm := _box(1.6, 0.06, 0.06, metal)
			arm.position = Vector3(0, 5.0 + k * 0.8, 0)
			arm.rotation.z = 0.25
			g.add_child(arm)
		var lamp := _basic(Color.html("#ff5040"), false)
		var bl := _box(0.2, 0.2, 0.2, lamp)
		bl.position.y = 7.1
		g.add_child(bl)
		g.position = Vector3(x, gh.call(x, z), z)
		wg.add_child(g)
		add_collider.call(x, 0, z, 0.5, 7.0, 0.5)
	# ---- 队旗(旗杆 + 旗面) ----
	var flag_pole := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var pole := _cyl(0.05, 0.07, 6.0, 6, metal)
		pole.position.y = 3.0
		g.add_child(pole)
		var cloth := _box(2.0, 1.1, 0.05, _std(Color.html("#00ff88") if team == "us" else Color.html("#ff5500"), 1.0))
		cloth.position = Vector3(1.0, 4.3, 0)
		cloth.rotation.y = 0.15
		cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(cloth)
		g.position = Vector3(x, gh.call(x, z), z)
		wg.add_child(g)
		add_collider.call(x, 0, z, 0.4, 6.0, 0.4)
	# ---- 弹药箱堆 ----
	var crates := func(x: float, z: float) -> void:
		var g := Node3D.new()
		for l in 3:
			var c := _box(1.2, 0.6, 1.0, wood)
			c.position = Vector3(0, 0.3 + l * 0.55, 0)
			c.rotation.y = Utils.rand(-0.1, 0.1)
			g.add_child(c)
		g.position = Vector3(x, gh.call(x, z), z)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.4, 1.8, 1.2)
	# ---- 地图桌(桌板 + 支架) ----
	var map_table := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var top := _box(1.8, 0.08, 1.2, _std(Color.html("#5a6a4a"), 0.9))
		top.position.y = 0.85
		g.add_child(top)
		for l in [[-0.8, -0.5], [0.8, -0.5], [-0.8, 0.5], [0.8, 0.5]]:
			var leg := _box(0.08, 0.85, 0.08, metal)
			leg.position = Vector3(l[0], 0.42, l[1])
			g.add_child(leg)
		g.position = Vector3(x, gh.call(x, z), z)
		g.rotation.y = Utils.rand(-0.2, 0.2)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.8, 0.9, 1.2)
	# ---- 发电机(箱体 + 排气管 + 指示灯) ----
	var generator := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var body := _box(1.4, 1.0, 0.9, metal)
		body.position.y = 0.5
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(body)
		var pipe := _cyl(0.06, 0.06, 1.2, 6, dark)
		pipe.position = Vector3(0.5, 1.1, 0)
		pipe.rotation.x = 0.5
		g.add_child(pipe)
		var ind := _basic(Color.html("#40ff40"), false)
		var id := _box(0.1, 0.1, 0.1, ind)
		id.position = Vector3(0, 1.02, 0.46)
		g.add_child(id)
		g.position = Vector3(x, gh.call(x, z), z)
		g.rotation.y = Utils.rand(TAU)
		wg.add_child(g)
		add_collider.call(x, 0, z, 1.6, 1.2, 1.1)
	# ---- 探照灯柱 ----
	var searchlight := func(x: float, z: float) -> void:
		var g := Node3D.new()
		var pole := _cyl(0.08, 0.1, 4.5, 6, metal)
		pole.position.y = 2.25
		g.add_child(pole)
		var lamp := _basic(Color.html("#cfe4ff"), false)
		var head := _box(0.8, 0.5, 0.5, lamp)
		head.position = Vector3(0, 4.3, 0.35)
		g.add_child(head)
		g.position = Vector3(x, gh.call(x, z), z)
		wg.add_child(g)
		add_collider.call(x, 0, z, 0.6, 4.5, 0.6)
	# ---- 布局(北/南基地:帐篷两侧、后墙贴地图边缘、载具出生簇(x∈[-32..18])保持清空) ----
	var back_z: float = bz - 7.0    # 靠地图边缘一侧(后墙多在地图钳制线外,纯视觉)
	tent.call(-24.0, bz - 3.0, PI if side < 0 else 0.0)
	tent.call(24.0, bz - 3.0, PI if side < 0 else 0.0)
	sandbag_wall.call(0.0, back_z, 44.0, 0.0)            # 后墙(背靠地图边缘)
	radio_mast.call(-28.0, bz - 3.0)
	flag_pole.call(0.0, back_z)
	crates.call(-26.0, back_z)
	crates.call(26.0, back_z)
	map_table.call(-12.0, back_z)
	generator.call(27.0, back_z + 2.0)
	searchlight.call(12.0, back_z)


## ==================== 主题化天然边界 + 远景(入口) ====================
static func _build_natural_boundary(wg: Node3D, theme_id: String, T, size: float,
		is_bt: bool, is_tdm: bool, lv: int, web: bool) -> void:
	var half: float = size / 2.0
	var bnd: float = G.bounds
	var add_collider := func(x: float, y: float, z: float, w: float, h: float, d: float) -> AABB:
		var gh: float = G.ground_h.call(x, z)
		var b := AABB(Vector3(x - w / 2, gh + y, z - d / 2), Vector3(w, h, d))
		G.colliders.append(b)
		return b
	_bnd_skirt(wg, theme_id, T, half, is_bt)
	_bnd_smokes(bnd)
	match theme_id:
		"city":
			_bnd_city(wg, add_collider, bnd, half, is_tdm)
		"desert":
			_bnd_desert(wg, add_collider, bnd, half)
		"snow":
			_bnd_snow(wg, add_collider, bnd, half)
		"bt_jungle":
			_bnd_jungle(wg, add_collider, bnd, half)
		"bt_harbor":
			_bnd_harbor(wg, add_collider, bnd, half)
		"bt_peak":
			_bnd_peak(wg, add_collider, bnd, half)
	# 基地临时指挥部(我方/敌方基地各一座,环绕出生点;TDM 出生点密集不布置)
	if not is_tdm:
		_build_base_camp(wg, add_collider, half, -1.0, "us")
		_build_base_camp(wg, add_collider, half, 1.0, "ru")


## 城市:外围街区楼群 + 施工塔吊 + 集装箱堆 + 远处高层天际线(无雾,需覆盖地平线)
static func _bnd_city(wg: Node3D, add_collider: Callable, bnd: float, half: float, is_tdm: bool) -> void:
	var fac := []
	for fd in [["#7a8088", 0.15], ["#8a7a68", 0.2], ["#6a7078", 0.1], ["#94887a", 0.25]]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = TerrainTextures.facade_texture(fd[0], fd[1])
		m.roughness = 0.9
		fac.append(m)
	var dark := _std(Color.html("#23252a"), 1.0)
	var glass := _basic(Color.html("#5a7a90"), true)
	var steel := _std(Color.html("#4a4e54"), 0.6, 0.5)
	var conc2 := _std_tex(Color.WHITE, 0.95, "rough_concrete")
	var cont_mat := _std_tex(Color.html("#8aa0c0"), 0.6, "metal_plate", 0.4)
	var sc: float = 0.75 * (half * 2.0) / 240.0 if is_tdm else 1.0
	# 近环:外围街区楼群(碰撞体,遮挡视野 + 软性封锁)
	var k := 0
	var n := 0
	while n < 32 and k < 160:
		k += 1
		var a := k * 0.55 + Utils.rand(-0.05, 0.05)
		if _bnd_base_gap(a):
			continue
		var r := Utils.rand(bnd, bnd + 16)
		var x := sin(a) * r
		var z := cos(a) * r
		var w := Utils.rand(15, 26) * sc
		var d := Utils.rand(14, 24) * sc
		var h := Utils.rand(20, 42)
		var bmat: Material = Utils.choice(fac)
		if randf() < 0.25:
			bmat = conc2
		var b := _box(w, h, d, bmat)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		b.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		b.rotation.y = a + Utils.rand(-0.25, 0.25)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(b)
		add_collider.call(x, 0, z, w, h, d)
		var rb := _box(Utils.rand(3, 6) * sc, Utils.rand(2, 5), Utils.rand(3, 6) * sc, dark)
		rb.position = Vector3(x, gh + h + Utils.rand(1, 3), z)
		rb.rotation.y = Utils.rand(PI)
		wg.add_child(rb)
		if randf() < 0.55:
			var win := _box(w + 0.1, Utils.rand(4, 9), 0.3, glass)
			win.position = Vector3(x, gh + Utils.rand(h * 0.3, h * 0.7), z + d / 2.0)
			win.rotation.y = b.rotation.y
			wg.add_child(win)
		n += 1
	# 中环:稀疏高层(第二层轮廓,无碰撞)
	n = 0
	while n < 20 and k < 260:
		k += 1
		var a := k * 1.7 + Utils.rand(-0.1, 0.1)
		var r := Utils.rand(bnd + 26, bnd + 58)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := Utils.rand(30, 58)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var b := _box(Utils.rand(14, 24) * sc, h, Utils.rand(14, 24) * sc, Utils.choice(fac))
		b.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		b.rotation.y = Utils.rand(PI)
		wg.add_child(b)
		n += 1
	# 中间环(240-360):填充外围空旷视野,城市向天际线连续过渡(无碰撞)
	n = 0
	var k2 := 0
	while n < 18 and k2 < 80:
		k2 += 1
		var a := k2 * 0.9 + Utils.rand(-0.08, 0.08)
		var r := Utils.rand(bnd + 90, bnd + 210)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := Utils.rand(40, 72)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var b := _box(Utils.rand(16, 28) * sc, h, Utils.rand(16, 28) * sc, Utils.choice(fac))
		b.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		b.rotation.y = Utils.rand(PI)
		wg.add_child(b)
		n += 1
	# 施工塔吊(城市地标)
	for c in 6:
		var a := c / 6.0 * TAU + Utils.rand(-0.3, 0.3)
		if _bnd_base_gap(a):
			continue
		var tx := sin(a) * Utils.rand(bnd + 20, bnd + 45)
		var tz := cos(a) * Utils.rand(bnd + 20, bnd + 45)
		var ght: float = G.ground_h.call(tx, tz) if G.ground_h.is_valid() else 0.0
		var g := Node3D.new()
		var col := _box(0.6, 24, 0.6, steel)
		col.position.y = 12
		g.add_child(col)
		var arm := _box(10, 0.5, 0.6, steel)
		arm.position = Vector3(5, 21, 0)
		g.add_child(arm)
		var cnt := _box(2.4, 2.0, 2.4, dark)
		cnt.position = Vector3(-1, 22, 0)
		g.add_child(cnt)
		g.position = Vector3(tx, ght - 0.15, tz)
		g.rotation.y = Utils.rand(TAU)
		wg.add_child(g)
	# 集装箱堆(近环)
	for c in 7:
		var a := c / 7.0 * TAU + Utils.rand(-0.2, 0.2)
		if _bnd_base_gap(a):
			continue
		var x := sin(a) * Utils.rand(bnd + 2, bnd + 10)
		var z := cos(a) * Utils.rand(bnd + 2, bnd + 10)
		var ghc2: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		for l in 2:
			var cc := _box(6.2 * sc, 2.7, 2.5 * sc, cont_mat)
			cc.position = Vector3(x + Utils.rand(-2, 2), ghc2 + 2.7 * l + 1.35 - 0.1, z + Utils.rand(-2, 2))
			cc.rotation.y = Utils.rand(TAU)
			wg.add_child(cc)
	# 远处高层天际线(两环:420-560 / 600-780,无雾城市地平线全由楼群覆盖)
	var sky1 := _basic(Color.html("#5c6672"), true)
	for r2 in 2:
		var ring_r0 := 420.0
		var ring_r1 := 560.0
		var cnt2 := 20
		if r2 == 1:
			ring_r0 = 600.0
			ring_r1 = 780.0
			cnt2 = 28
		for i2 in cnt2:
			var a := i2 / float(cnt2) * TAU + Utils.rand(-0.05, 0.05)
			var r := Utils.rand(ring_r0, ring_r1)
			var h := Utils.rand(28, 70)
			var b := _box(Utils.rand(18, 34), h, Utils.rand(18, 34), sky1)
			b.position = Vector3(sin(a) * r, h / 2.0 - 4, cos(a) * r)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wg.add_child(b)
	# 基地缺口:公路 + 检查站


## 沙漠:峡谷岩壁 + 台地 + 岩柱 + 沙丘 + 远行油罐车队
static func _bnd_desert(wg: Node3D, add_collider: Callable, bnd: float, half: float) -> void:
	var mesa := _std_tex(Color.html("#b08a5a"), 1.0, "rock_04")
	var mesa_cap := _std_tex(Color.html("#8a6a4a"), 1.0, "rock_04")
	var spire := _std_tex(Color.html("#7a5c3e"), 1.0, "rock_04")
	var sand := _std_tex(Color.html("#c8b088"), 1.0, "sand_01")
	# 峡谷岩壁环(连续长墙块,带碰撞)
	var k := 0
	while k < 16:
		var a := k / 16.0 * TAU + Utils.rand(-0.08, 0.08)
		k += 1
		if _bnd_base_gap(a):
			continue
		var r := Utils.rand(bnd - 2, bnd + 12)
		var x := sin(a) * r
		var z := cos(a) * r
		var w := Utils.rand(20, 36)
		var h := Utils.rand(14, 30)
		var d := Utils.rand(10, 18)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var m2 := _box(w, h, d, mesa)
		m2.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		m2.rotation.y = a + Utils.rand(-0.15, 0.15)
		m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(m2)
		add_collider.call(x, 0, z, w, h, d)
		var cap := _box(w - 4, 2, d - 2, mesa_cap)
		cap.position = Vector3(x, gh + h + 1, z)
		wg.add_child(cap)
	# 岩柱/孤峰(外圈,无碰撞)
	for s2 in 12:
		var a := s2 * 2.4 + Utils.rand(-0.2, 0.2)
		var r := Utils.rand(bnd + 20, bnd + 50)
		var x := sin(a) * r
		var z := cos(a) * r
		var h := Utils.rand(12, 34)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var sp := _box(Utils.rand(5, 9), h, Utils.rand(5, 9), spire)
		sp.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		sp.rotation.y = Utils.rand(TAU)
		wg.add_child(sp)
	# 沙丘(压扁球,下半埋入地面;避开基地保护区)
	var dune := SphereMesh.new()
	dune.radius = 1
	dune.height = 2
	dune.radial_segments = 10
	dune.rings = 5
	for d2 in 14:
		var a := d2 / 14.0 * TAU + Utils.rand(-0.2, 0.2)
		var r := Utils.rand(bnd - 2, bnd + 24)
		var x := sin(a) * r
		var z := cos(a) * r
		if _bnd_in_base_zone(x, z, half):
			continue
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var sy := Utils.rand(1.5, 3.5)
		var dm2 := MeshInstance3D.new()
		dm2.mesh = dune
		dm2.material_override = sand
		dm2.scale = Vector3(Utils.rand(10, 22), sy, Utils.rand(10, 22))
		dm2.position = Vector3(x, gh - sy * 0.55, z)
		wg.add_child(dm2)
	# 远台地天际线(380-540)
	var mesa2 := _basic(Color.html("#a8845c"), true)
	for i2 in 12:
		var a := i2 / 12.0 * TAU + Utils.rand(-0.12, 0.12)
		var r := Utils.rand(380, 540)
		var h := Utils.rand(20, 50)
		var b := _box(Utils.rand(40, 80), h, Utils.rand(30, 60), mesa2)
		b.position = Vector3(sin(a) * r, h / 2.0 - 4, cos(a) * r)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(b)
	# 远行油罐车队(远景小车 MultiMesh,公路方向延出)
	var veh_mat := _std(Color.html("#3a3428"), 1.0)
	var veh_mesh := BoxMesh.new()
	veh_mesh.size = Vector3(2.2, 1.1, 6.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = veh_mesh
	mm.instance_count = 7
	for i in 7:
		var side := -1.0 if i % 2 == 0 else 1.0
		var zz: float = side * Utils.rand(bnd + 26, bnd + 105)
		var ghv: float = G.ground_h.call(0.0, zz) if G.ground_h.is_valid() else 0.0
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, PI if side < 0 else 0.0),
			Vector3(Utils.rand(-1.0, 1.0), ghv + 0.05, zz)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = veh_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wg.add_child(mmi)
	_bnd_towers(wg, bnd, _std(Color.html("#2e3238"), 0.8, 0.5))


## 雪山:雪山环 + 岩壁 + 松林 + 冰川 + 远峰天际线(全部对齐滚动地形,防浮空)
static func _bnd_snow(wg: Node3D, add_collider: Callable, bnd: float, half: float) -> void:
	var mtn := _std_tex(Color.html("#dde6ee"), 1.0, "rock_04")
	var mtn_rock := _std_tex(Color.html("#8a9098"), 1.0, "rock_04")
	var pine_mat := _std(Color.html("#2a4a3a"), 1.0)
	var ice := _std_tex(Color.html("#c8d8e4"), 0.9, "rock_04")
	# 雪山环(锥体,近环带碰撞)
	for m2 in 18:
		var a := m2 / 18.0 * TAU + Utils.rand(-0.1, 0.1)
		if _bnd_base_gap(a):
			continue
		var r := Utils.rand(bnd - 4, bnd + 14)
		var x := sin(a) * r
		var z := cos(a) * r
		var h := Utils.rand(30, 60)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var c := _cone(Utils.rand(20, 34), h, 6, mtn)
		c.position = Vector3(x, gh + h / 2.0 - 2, z)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(c)
		add_collider.call(x, 0, z, Utils.rand(16, 26), h, Utils.rand(16, 26))
	# 岩壁(长条倾斜块,半埋入地形)
	for r2 in 10:
		var a := r2 / 10.0 * TAU + Utils.rand(-0.2, 0.2)
		if _bnd_base_gap(a):
			continue
		var x := sin(a) * Utils.rand(bnd + 6, bnd + 18)
		var z := cos(a) * Utils.rand(bnd + 6, bnd + 18)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var wb := _box(Utils.rand(14, 26), Utils.rand(8, 16), Utils.rand(6, 10), mtn_rock)
		wb.position = Vector3(x, gh + 6, z)
		wb.rotation = Vector3(Utils.rand(-0.3, 0.3), a, Utils.rand(-0.3, 0.3))
		wg.add_child(wb)
	# 冰川块 + 雪丘(对齐地形,避开基地保护区)
	for g2 in 10:
		var a := g2 / 10.0 * TAU + Utils.rand(-0.25, 0.25)
		var r := Utils.rand(bnd - 2, bnd + 30)
		var x := sin(a) * r
		var z := cos(a) * r
		if _bnd_in_base_zone(x, z, half):
			continue
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var ib := _box(Utils.rand(6, 16), Utils.rand(3, 9), Utils.rand(6, 16), ice)
		ib.position = Vector3(x, gh + Utils.rand(2, 5), z)
		ib.rotation = Vector3(Utils.rand(-0.4, 0.4), Utils.rand(TAU), Utils.rand(-0.4, 0.4))
		wg.add_child(ib)
	# 松林(MultiMesh)
	_bnd_pines_mm(wg, pine_mat, bnd, 90, 0, 40, half)
	# 远峰天际线(360-500,对齐地形)
	var far_mtn := _basic(Color.html("#b8c4d0"), true)
	for i2 in 14:
		var a := i2 / 14.0 * TAU + Utils.rand(-0.1, 0.1)
		var r := Utils.rand(360, 500)
		var x := sin(a) * r
		var z := cos(a) * r
		var h := Utils.rand(50, 110)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var m2 := _cone(Utils.rand(40, 70), h, 6, far_mtn)
		m2.position = Vector3(x, gh + h / 2.0 - 2, z)
		m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(m2)
	# 基地缺口:公路 + 检查站

## 丛林:密林环(MultiMesh)+ 丘陵 + 岩壁;河道已延伸出地图两侧(全部对齐地形)
static func _bnd_jungle(wg: Node3D, add_collider: Callable, bnd: float, half: float) -> void:
	var leaf := _std(Color.html("#3a5a30"), 1.0)
	var hill_j := _std_tex(Color.html("#5a6a44"), 1.0, "rock_04")
	var rock_j := _std_tex(Color.html("#5a6256"), 1.0, "rock_04")
	# 密林环(MultiMesh,双层;基地压平带后移,环整体外推 25m 不再包裹出生点)
	_bnd_pines_mm(wg, leaf, bnd, 130, 25, 55, half)
	_bnd_pines_mm(wg, leaf, bnd, 80, 59, 89, half)
	# 丘陵(压扁球,下半埋入地形;避开基地保护区)
	var mound := SphereMesh.new()
	mound.radius = 1
	mound.height = 2
	mound.radial_segments = 10
	mound.rings = 5
	for d2 in 12:
		var a := d2 / 12.0 * TAU + Utils.rand(-0.2, 0.2)
		var r := Utils.rand(bnd + 21, bnd + 45)
		var x := cos(a) * r
		var z := sin(a) * r
		if _bnd_in_base_zone(x, z, half):
			continue
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var sy := Utils.rand(2.5, 5.5)
		var dm2 := MeshInstance3D.new()
		dm2.mesh = mound
		dm2.material_override = hill_j
		dm2.scale = Vector3(Utils.rand(12, 26), sy, Utils.rand(12, 26))
		dm2.position = Vector3(x, gh - sy * 0.55, z)
		wg.add_child(dm2)
	# 岩壁(半埋入地形)
	for r2 in 6:
		var a := r2 / 6.0 * TAU + Utils.rand(-0.25, 0.25)
		if _bnd_base_gap(a):
			continue
		var x := cos(a) * Utils.rand(bnd + 29, bnd + 41)
		var z := sin(a) * Utils.rand(bnd + 29, bnd + 41)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var wb := _box(Utils.rand(12, 22), Utils.rand(6, 12), Utils.rand(5, 8), rock_j)
		wb.position = Vector3(x, gh + 5, z)
		wb.rotation = Vector3(Utils.rand(-0.4, 0.4), a, Utils.rand(-0.4, 0.4))
		wg.add_child(wb)
	# 基地缺口:林间土路 + 检查站

## 港口:港区仓储/集装箱/塔吊环 + 海面延伸(±X)+ 远洋货轮 + 工业剪影
static func _bnd_harbor(wg: Node3D, add_collider: Callable, bnd: float, half: float) -> void:
	var ware := _std_tex(Color.html("#7a8a9a"), 0.7, "corrugated_iron", 0.3)
	var ware2 := _std_tex(Color.html("#9a8a7a"), 0.7, "corrugated_iron", 0.3)
	var cont := _std_tex(Color.html("#8aa0c0"), 0.6, "metal_plate", 0.4)
	var steel := _std(Color.html("#4a4e54"), 0.6, 0.5)
	# 港区仓储环(近环,带碰撞)
	var k := 0
	while k < 18:
		var a := k / 18.0 * TAU + Utils.rand(-0.1, 0.1)
		k += 1
		if _bnd_base_gap(a):
			continue
		var r := Utils.rand(bnd - 2, bnd + 12)
		var x := sin(a) * r
		var z := cos(a) * r
		var w := Utils.rand(18, 30)
		var d := Utils.rand(14, 22)
		var h := Utils.rand(9, 15)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var wb := _box(w, h, d, ware if randf() < 0.5 else ware2)
		wb.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		wb.rotation.y = a + Utils.rand(-0.15, 0.15)
		wb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(wb)
		add_collider.call(x, 0, z, w, h, d)
	# 集装箱堆 + 塔吊
	for c in 10:
		var a := c / 10.0 * TAU + Utils.rand(-0.2, 0.2)
		if _bnd_base_gap(a):
			continue
		var x := sin(a) * Utils.rand(bnd + 2, bnd + 12)
		var z := cos(a) * Utils.rand(bnd + 2, bnd + 12)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		if randf() < 0.6:
			for l in 2:
				var cc := _box(6.2, 2.7, 2.5, cont)
				cc.position = Vector3(x + Utils.rand(-2, 2), gh + 2.7 * l + 1.35 - 0.1, z + Utils.rand(-2, 2))
				cc.rotation.y = Utils.rand(TAU)
				wg.add_child(cc)
		else:
			var g := Node3D.new()
			var col := _box(0.5, 20, 0.5, steel)
			col.position.y = 10
			g.add_child(col)
			var arm := _box(11, 0.5, 0.5, steel)
			arm.position = Vector3(5.5, 18, 0)
			g.add_child(arm)
			g.position = Vector3(x, gh - 0.15, z)
			g.rotation.y = Utils.rand(TAU)
			wg.add_child(g)
	# 海面延伸(±X 超出地图边缘) + 远洋货轮
	for side in [-1.0, 1.0]:
		var ws := MeshInstance3D.new()
		var wpm := PlaneMesh.new()
		wpm.size = Vector2(160, half * 2 + 240)
		ws.mesh = wpm
		ws.material_override = TerrainTextures.make_water_material(
			Color.html("#14314a"), Color.html("#1d4a63"), 0.14, 0.7)
		ws.position = Vector3(side * (half + 80), 0.3, 0)
		ws.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(ws)
		for s2 in 3:
			var ship_mat := _basic(Color.html("#23262c"), true)
			var shp := Node3D.new()
			var hull := _box(50, 8, 12, ship_mat)
			hull.position.y = 2
			shp.add_child(hull)
			var tow := _box(6, 10, 8, ship_mat)
			tow.position = Vector3(-14, 8, 0)
			shp.add_child(tow)
			shp.position = Vector3(side * (half + 30 + s2 * 40), -0.55, Utils.rand(-half * 0.5, half * 0.5))
			shp.rotation.y = Utils.rand(-0.3, 0.3)
			wg.add_child(shp)
	# 远处工业剪影(380-520,烟囱+厂房)
	var ind := _basic(Color.html("#4a4458"), true)
	for i2 in 14:
		var a := i2 / 14.0 * PI + Utils.rand(-0.1, 0.1)
		var r := Utils.rand(380, 520)
		var h := Utils.rand(20, 55)
		var b := _box(Utils.rand(18, 36), h, Utils.rand(18, 36), ind)
		b.position = Vector3(sin(a) * r, h / 2.0 - 4, cos(a) * r)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(b)
		if randf() < 0.5:
			var ch := _cyl(2.5, 3.5, h * 0.6, 6, _basic(Color.html("#3a3648"), true))
			ch.position = Vector3(b.position.x + Utils.rand(-6, 6), h * 0.3, b.position.z + Utils.rand(-6, 6))
			wg.add_child(ch)
	# 基地缺口:堆场路 + 检查站

## 暗夜雷达站:暗色山环 + 松林 + 岩壁 + 远处军事设施灯光(全部对齐地形)
static func _bnd_peak(wg: Node3D, add_collider: Callable, bnd: float, half: float) -> void:
	var mtn := _std_tex(Color.html("#2e3238"), 1.0, "rock_04")
	var snowcap := _std_tex(Color.html("#6e767e"), 1.0, "rock_04")
	var pine_mat := _std(Color.html("#1e3026"), 1.0)
	var rock_p := _std_tex(Color.html("#3a3e44"), 1.0, "rock_04")
	# 暗色山环(锥,近环带碰撞)
	for m2 in 18:
		var a := m2 / 18.0 * TAU + Utils.rand(-0.1, 0.1)
		if _bnd_base_gap(a):
			continue
		var r := Utils.rand(bnd - 4, bnd + 14)
		var x := sin(a) * r
		var z := cos(a) * r
		var h := Utils.rand(28, 55)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var c := _cone(Utils.rand(18, 30), h, 6, mtn)
		c.position = Vector3(x, gh + h / 2.0 - 2, z)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wg.add_child(c)
		add_collider.call(x, 0, z, Utils.rand(15, 24), h, Utils.rand(15, 24))
		var cap := _cone(Utils.rand(6, 10), h * 0.14, 6, snowcap)
		cap.position = Vector3(x, gh + h - h * 0.05, z)
		wg.add_child(cap)
	# 岩壁(半埋入地形)
	for r2 in 8:
		var a := r2 / 8.0 * TAU + Utils.rand(-0.25, 0.25)
		if _bnd_base_gap(a):
			continue
		var x := sin(a) * Utils.rand(bnd + 6, bnd + 18)
		var z := cos(a) * Utils.rand(bnd + 6, bnd + 18)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var wb := _box(Utils.rand(12, 22), Utils.rand(8, 16), Utils.rand(6, 9), rock_p)
		wb.position = Vector3(x, gh + 6, z)
		wb.rotation = Vector3(Utils.rand(-0.3, 0.3), a, Utils.rand(-0.3, 0.3))
		wg.add_child(wb)
	# 松林(MultiMesh)
	_bnd_pines_mm(wg, pine_mat, bnd, 80, 0, 36, half)
	# 远处军事设施(灯光:窗灯 + 红色信标 + 天线)
	var bld := _std(Color.html("#20242a"), 1.0)
	var win_light := _basic(Color.html("#e8c878"), false)
	var beacon := _basic(Color.html("#ff3020"), false)
	for i2 in 10:
		var a := i2 / 10.0 * TAU + Utils.rand(-0.15, 0.15)
		var r := Utils.rand(360, 480)
		var x := sin(a) * r
		var z := cos(a) * r
		var h := Utils.rand(14, 30)
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var b := _box(Utils.rand(20, 40), h, Utils.rand(14, 26), bld)
		b.position = Vector3(x, gh + h / 2.0 - 0.2, z)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wg.add_child(b)
		var win := _box(Utils.rand(8, 16), 2.0, 0.2, win_light)
		win.position = Vector3(x, gh + Utils.rand(4, h - 3), z)
		wg.add_child(win)
		if randf() < 0.5:
			var bcon := _box(0.8, 0.8, 0.8, beacon)
			bcon.position = Vector3(x, gh + h + 1, z)
			wg.add_child(bcon)
		if randf() < 0.4:
			var mast := _box(0.3, 14, 0.3, _std(Color.html("#4a3a3a"), 0.6, 0.5))
			mast.position = Vector3(x + Utils.rand(-6, 6), gh + 7, z + Utils.rand(-6, 6))
			wg.add_child(mast)
	# 基地缺口:探照灯(两侧各一盏)
	for side in [-1.0, 1.0]:
		var ghl: float = G.ground_h.call(9.0, side * (bnd + 8)) if G.ground_h.is_valid() else 0.0
		var lp := _basic(Color.html("#cfe4ff"), false)
		var light := _box(1.0, 0.6, 0.6, lp)
		light.position = Vector3(9.0, ghl + 4.6, side * (bnd + 8))
		wg.add_child(light)
	_bnd_towers(wg, bnd, _std(Color.html("#2e3238"), 0.8, 0.5))






