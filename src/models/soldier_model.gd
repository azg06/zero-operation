class_name SoldierModel
## 士兵模型(对应 ai.js 的 buildSoldier 与 player.js 的 _buildBody)

static var _mat_cache: Dictionary = {}


static func _mat(color: Color, rough := 0.9, unshaded := false) -> StandardMaterial3D:
	# [PERF] 材质缓存:同色/同粗糙/同着色模式共享实例,减少材质数量并让合并真正降 Draw Call
	var key := "%.4f_%.4f_%.4f_%.4f_%.2f_%d" % [color.r, color.g, color.b, color.a, rough, int(unshaded)]
	var m: StandardMaterial3D = _mat_cache.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_cache[key] = m
	return m


static func _box(w: float, h: float, d: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = mat
	return mi


static func _add(parent: Node3D, mesh: MeshInstance3D, x: float, y: float, z: float) -> MeshInstance3D:
	mesh.position = Vector3(x, y, z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh)
	return mesh


## [PERF] 合并父节点下的直接静态网格子节点(按材质分组为多 surface,降低 Draw Call)
## 父节点保持为动画枢轴;合并后的网格仍随父节点刚性运动。
static func _merge_children(parent: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	for c in parent.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			meshes.append(c as MeshInstance3D)
	if meshes.size() <= 1:
		return
	var by_mat: Dictionary = {}
	for m in meshes:
		var mat: Material = m.material_override
		if mat == null:
			continue
		if not by_mat.has(mat):
			by_mat[mat] = []
		by_mat[mat].append(m)
	var am := ArrayMesh.new()
	for mat in by_mat:
		var group: Array = by_mat[mat]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for mm in group:
			var mi3 := mm as MeshInstance3D
			if mi3.mesh.get_surface_count() == 0:
				continue
			var arr := mi3.mesh.surface_get_arrays(0)
			var mv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var mn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var muv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var mi2: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tf := mi3.transform
			var base := verts.size()
			for v in mv:
				verts.append(tf * v)
			for nrm in mn:
				norms.append((tf.basis * nrm).normalized())
			for uv in muv:
				uvs.append(uv)
			for ix in mi2:
				idx.append(base + ix)
		if verts.is_empty():
			continue
		var arrs := []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = verts
		arrs[Mesh.ARRAY_NORMAL] = norms
		arrs[Mesh.ARRAY_TEX_UV] = uvs
		arrs[Mesh.ARRAY_INDEX] = idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs, [], {}, 0)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	if am.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	for m in meshes:
		parent.remove_child(m)
		m.free()


## 兵种皮肤配色(每兵种 3 套;standard 与无 skin 参数时完全一致)
const SKINS := {
	"assault": {
		"standard": { "uniform": "#4a5548", "vest": "#3a4a5a", "helmet": "#3a4438", "gear": "#33382e", "gear2": "#565a44" },
		"arctic": { "uniform": "#cfd6d8", "vest": "#aeb8bd", "helmet": "#dde2e4", "gear": "#8e979b", "gear2": "#bcc4c8", "cover": "#e8ecee", "strap": "#5a6670" },
		"night": { "uniform": "#23262c", "vest": "#171a20", "helmet": "#2c2f36", "gear": "#0f1216", "gear2": "#1d2128", "cover": "#14181e", "strap": "#0a0d10" },
	},
	"engineer": {
		"standard": { "uniform": "#8a6a3e", "vest": "#c07a34", "helmet": "#96682f", "gear": "#5c4a30", "gear2": "#7c6640" },
		"desert": { "uniform": "#c4a46c", "vest": "#b08c50", "helmet": "#ccb074", "gear": "#8a7448", "gear2": "#a8905e", "cover": "#d8c088", "strap": "#a8905e" },
		"black": { "uniform": "#3a3a40", "vest": "#26262c", "helmet": "#44444c", "gear": "#1c1c22", "gear2": "#32323a", "cover": "#101014", "strap": "#26262e" },
	},
	"support": {
		"standard": { "uniform": "#4a5c44", "vest": "#3a4c38", "helmet": "#40503c", "gear": "#2c3a2c", "gear2": "#4e5e4a" },
		"brown": { "uniform": "#5c4c3a", "vest": "#6e5838", "helmet": "#52442e", "gear": "#3a3228", "gear2": "#5e4e3a", "cover": "#6a5638", "strap": "#463a2a" },
		"gray": { "uniform": "#5a5e64", "vest": "#484c52", "helmet": "#62666c", "gear": "#34383e", "gear2": "#50545a", "cover": "#6e7278", "strap": "#3c4046" },
	},
	"recon": {
		"standard": { "uniform": "#5c6c4a", "vest": "#4a5c3c", "helmet": "#54643f", "gear": "#38462c", "gear2": "#6c7c54" },
		"urban": { "uniform": "#6e747a", "vest": "#585e64", "helmet": "#767c82", "gear": "#44484e", "gear2": "#62686e", "cover": "#82888e", "strap": "#50565c" },
		"white": { "uniform": "#d8dcde", "vest": "#c2c8cc", "helmet": "#e4e8ea", "gear": "#a8aeb2", "gear2": "#ccd2d4", "cover": "#f0f2f4", "strap": "#b4babd" },
	},
}


## ---- GLB 骨骼士兵(盒子拼装的替代管线,2026-09 重建) ----
## Blender 管线(tools/blender/build_soldier.py):17 骨人形 + 顶点色分区 +
## 4 条骨骼动画(Idle/Walk/Run/Death)。顶点色 R 通道存部件 id(0.1~0.8),
## 配 soldier_palette.gdshader 按兵种/皮肤/队伍调色,一个 GLB 通吃 24 变体。
## 每兵种一个 GLB(建模差异,Blender 管线分 4 兵种导出);assault 兼作兜底基准。
const SOLDIER_GLB := "res://models/soldiers/soldier.glb"
const USE_GLB_SOLDIER := true

static var _glb_scenes: Dictionary = {}
static var _glb_mats: Dictionary = {}


## 按兵种取 GLB 场景(缺失兵种文件时回退 assault 基准)
static func _glb_scene_for(class_id: String) -> PackedScene:
	var path := "res://models/soldiers/soldier_%s.glb" % class_id
	if not ResourceLoader.exists(path):
		path = SOLDIER_GLB
	if not _glb_scenes.has(path):
		_glb_scenes[path] = load(path)
	return _glb_scenes[path]


## 调色材质(兵种/皮肤/队伍)——全局缓存共享实例,不增加 draw call
static func _glb_material(class_id: String, skin: String, team: String) -> ShaderMaterial:
	var key := "%s/%s/%s" % [class_id, skin, team]
	var m: ShaderMaterial = _glb_mats.get(key)
	if m != null:
		return m
	var cl_skins: Dictionary = SKINS.get(class_id, SKINS["assault"])
	if not cl_skins.has(skin):
		skin = "standard"
	var pal: Dictionary = cl_skins[skin]
	m = ShaderMaterial.new()
	m.shader = load("res://src/shaders/soldier_palette.gdshader")
	m.set_shader_parameter("pal_uniform", Color.html(pal["uniform"]))
	m.set_shader_parameter("pal_vest", Color.html(pal["vest"]))
	m.set_shader_parameter("pal_helmet", Color.html(pal["helmet"]))
	m.set_shader_parameter("pal_gear", Color.html(pal["gear"]))
	m.set_shader_parameter("pal_skin", Color.html("#c8a080"))
	m.set_shader_parameter("pal_boot", Color.html("#26221e"))
	m.set_shader_parameter("pal_accent", Color.html("#00ff88") if team == "us" else Color.html("#ff5500"))
	m.set_shader_parameter("pal_gear2", Color.html(pal["gear2"]))
	_glb_mats[key] = m
	return m


## GLB 士兵:Skeleton3D + AnimationPlayer + 真枪挂右手骨
## meta: anim / skel / gun_mount / far_hide(供 bot.gd LOD 与死亡处理)
static func build_soldier_glb(team: String, weapon_id: String, class_id := "assault", skin := "standard") -> Node3D:
	var scn: PackedScene = _glb_scene_for(class_id)
	var g: Node3D = scn.instantiate()
	g.name = "Soldier"
	var mat := _glb_material(class_id, skin, team)
	var skel: Skeleton3D = null
	var anim: AnimationPlayer = null
	var stack: Array = [g]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			skel = n as Skeleton3D
		elif n is AnimationPlayer and anim == null:
			anim = n as AnimationPlayer
		elif n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)
	var far_hide: Array = []
	var gun_mount: Node3D = null
	if skel != null and not weapon_id.is_empty():
		var ba := BoneAttachment3D.new()
		ba.name = "GunMount"
		ba.bone_name = "HandR"
		skel.add_child(ba)
		# 第三人称枪:同款 WeaponModels 管线(带全改装件,与玩家视觉一致)
		var gun: Node3D = WeaponModels.build(weapon_id, false, WeaponModsData.load_cfg(weapon_id))
		gun.name = "Weapon_" + weapon_id
		# 手骨局部系(骨骼延伸=局部 -Y):绕 X +90° 把枪管从竖直转到沿骨前指
		gun.rotation_degrees = Vector3(90, 0, 0)
		gun.position = Vector3(0, 0, 0)
		ba.add_child(gun)
		far_hide.append(ba)
		gun_mount = ba
	g.set_meta("anim", anim)
	g.set_meta("skel", skel)
	g.set_meta("gun_mount", gun_mount)
	g.set_meta("far_hide", far_hide)
	return g


## AI 士兵:膝关节双腿 + 可编程持枪臂组 + 兵种专属外观
## 返回 Node3D,meta: leg_l{thigh,knee}, leg_r, upper, rig
static func build_soldier(team: String, weapon_id: String, class_id := "assault", skin := "standard") -> Node3D:
	if USE_GLB_SOLDIER:
		return build_soldier_glb(team, weapon_id, class_id, skin)
	var g := Node3D.new()
	g.name = "Soldier"
	# [PERF] 远距可藏件收集:护膝/靴/手/枪在 >LOD_FAR_DIST 亚像素不可辨,
	# bot 按距离分级隐藏(战地同款 LOD 思想),每远 bot 省 ~15+ drawcall
	var far_hide: Array = []
	var is_us: bool = team == "us"
	# 防御:未知皮肤 id(含跨兵种皮肤)一律回退本兵种 standard
	var cl_skins: Dictionary = SKINS.get(class_id, SKINS["assault"])
	if not cl_skins.has(skin):
		skin = "standard"
	var pal: Dictionary = cl_skins[skin]
	var uniform := _mat(Color.html(pal["uniform"]), 0.95)
	var vest := _mat(Color.html(pal["vest"]), 0.9)
	var skin_mat := _mat(Color.html("#c8a080"), 0.8)
	var helmet := _mat(Color.html(pal["helmet"]), 0.85)
	var accent := _mat(Color.html("#00ff88") if is_us else Color.html("#ff5500"), 0.9, true)
	var gear := _mat(Color.html(pal["gear"]), 0.92)                  # 装具深色
	var gear2 := _mat(Color.html(pal["gear2"]), 0.92)                # 装具帆布色
	var boot := _mat(Color.html("#26221e"), 0.9)                     # 靴
	var brass := _mat(Color.html("#c8a860"), 0.5)                    # 弹链铜色

	# 腿:髋部枢轴(大腿) + 膝关节(小腿) + 护膝 + 靴
	# [ANIM] 腿长与髋高(0.78)匹配:thigh→knee 0.40 + knee→靴底 0.36 = 0.76,
	# 站立可近直腿(脚部 IK 无需深屈膝),跑步摆腿自然腾空
	var mk_leg := func(x: float) -> Dictionary:
		var thigh := Node3D.new()
		thigh.position = Vector3(x, 0.78, 0)
		var tm := _box(0.16, 0.38, 0.18, uniform)
		tm.position.y = -0.19
		tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		thigh.add_child(tm)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.4, 0)
		var sm := _box(0.15, 0.36, 0.16, uniform)
		sm.position.y = -0.16
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(sm)
		var kp := _box(0.16, 0.12, 0.06, gear)                      # 护膝
		kp.position = Vector3(0, -0.03, -0.1)
		kp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(kp)
		var bt := _box(0.16, 0.1, 0.24, boot)                       # 靴(前伸)
		bt.position = Vector3(0, -0.31, -0.03)
		bt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(bt)
		far_hide.append(kp)
		far_hide.append(bt)
		thigh.add_child(knee)
		g.add_child(thigh)
		return { "thigh": thigh, "knee": knee }
	var leg_l: Dictionary = mk_leg.call(-0.11)
	var leg_r: Dictionary = mk_leg.call(0.11)
	# 下半身转向组:腿部相对身体独立转向(身体朝向目标,腿朝向移动方向),
	# 消除"身体已转过去、腿还朝原方向"的僵硬转身
	var legs := Node3D.new()
	legs.name = "Legs"
	g.add_child(legs)
	for ld in [leg_l, leg_r]:
		var th: Node3D = ld["thigh"]
		g.remove_child(th)
		legs.add_child(th)
	g.set_meta("legs", legs)
	g.set_meta("leg_l", leg_l["thigh"])
	g.set_meta("leg_l_knee", leg_l["knee"])
	g.set_meta("leg_r", leg_r["thigh"])
	g.set_meta("leg_r_knee", leg_r["knee"])

	# 上半身组(髋部枢轴)
	var upper := Node3D.new()
	upper.position = Vector3(0, 0.95, 0)
	g.add_child(upper)
	_add(upper, _box(0.42, 0.62, 0.24, uniform), 0, 0.13, 0)      # 躯干
	_add(upper, _box(0.44, 0.4, 0.28, vest), 0, 0.17, 0)          # 背心
	_add(upper, _box(0.45, 0.05, 0.29, accent), 0, 0.35, 0)       # 队伍识别条
	_add(upper, _box(0.4, 0.1, 0.26, gear), 0, 0.42, 0)           # 肩颈线/领口护具
	_add(upper, _box(0.2, 0.22, 0.2, skin_mat), 0, 0.57, 0)           # 头
	_add(upper, _box(0.24, 0.12, 0.24, helmet), 0, 0.69, 0)       # 头盔
	_add(upper, _box(0.25, 0.03, 0.25, gear), 0, 0.635, 0)        # 头盔箍带
	_add(upper, _box(0.06, 0.05, 0.05, gear), 0, 0.665, -0.13)    # 夜视仪座

	# ============ 兵种专属外观(明显区分) ============
	match class_id:
		"assault":
			# 突击兵:胸前双弹匣包 + 左臂医疗十字章 + 大腿手雷包(轻装突击)
			_add(upper, _box(0.1, 0.12, 0.06, gear2), -0.08, 0.14, -0.16)
			_add(upper, _box(0.1, 0.12, 0.06, gear2), 0.08, 0.14, -0.16)
			_add(upper, _box(0.07, 0.1, 0.05, gear), 0.15, -0.05, -0.13)
			var cross1 := _box(0.1, 0.03, 0.02, _mat(Color.html("#e8e8e8"), 0.8, true))
			_add(upper, cross1, -0.225, 0.32, 0.02)
			var cross2 := _box(0.035, 0.1, 0.02, _mat(Color.html("#e8e8e8"), 0.8, true))
			_add(upper, cross2, -0.225, 0.32, 0.02)
			var crossm1 := _box(0.08, 0.024, 0.021, _mat(Color.html("#cc2222"), 0.8, true))
			_add(upper, crossm1, -0.225, 0.32, 0.025)
			var crossm2 := _box(0.026, 0.08, 0.021, _mat(Color.html("#cc2222"), 0.8, true))
			_add(upper, crossm2, -0.225, 0.32, 0.025)
		"engineer":
			# 工程兵:加厚防弹护胸 + 背负 RPG 发射筒 + 护目镜 + 工具腰包
			_add(upper, _box(0.46, 0.34, 0.31, vest), 0, 0.15, 0)                 # 加厚护板
			_add(upper, _box(0.3, 0.16, 0.06, gear), 0, 0.3, -0.16)               # 胸前工具板
			var tube := _cylx(0.055, 0.055, 0.78, gear2)                          # RPG 背筒
			tube.rotation.z = 0.42
			tube.rotation.x = 0.12
			tube.position = Vector3(-0.12, 0.32, 0.2)
			tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			upper.add_child(tube)
			var tube_head := _cylx(0.075, 0.06, 0.1, gear)
			tube_head.rotation.z = 0.42
			tube_head.position = Vector3(-0.28, 0.62, 0.2)
			tube_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			upper.add_child(tube_head)
			_add(upper, _box(0.2, 0.06, 0.05, gear), 0, 0.6, -0.115)              # 护目镜(推至盔沿)
			_add(upper, _box(0.34, 0.12, 0.2, gear2), 0, -0.12, 0.1)              # 工具腰包
		"support":
			# 支援兵:大弹药背包 + 斜挎弹链 + 腿部弹鼓包(火力后勤)
			_add(upper, _box(0.36, 0.42, 0.18, gear2), 0, 0.18, 0.21)             # 弹药背包
			_add(upper, _box(0.3, 0.1, 0.2, gear), 0, 0.42, 0.19)                 # 包顶盖
			for i in 7:                                                           # 斜挎弹链(铜)
				var lk := _box(0.035, 0.07, 0.03, brass)
				lk.rotation.z = -0.5
				_add(upper, lk, -0.14 + i * 0.045, 0.32 - i * 0.045, -0.155)
			_add(upper, _box(0.12, 0.14, 0.08, gear2), -0.24, -0.06, 0.02)        # 腿侧弹鼓包
			_add(upper, _box(0.12, 0.14, 0.08, gear2), 0.24, -0.06, 0.02)
		"recon":
			# 侦察兵:吉利服兜帽 + 蒙面 + 背负天线 + 伪装布条(隐蔽猎手)
			_add(upper, _box(0.26, 0.14, 0.26, uniform), 0, 0.7, 0)               # 兜帽
			_add(upper, _box(0.27, 0.2, 0.06, uniform), 0, 0.62, 0.13)            # 兜帽后垂布
			_add(upper, _box(0.2, 0.08, 0.04, gear), 0, 0.54, -0.11)              # 蒙面巾
			var ant := _cylx(0.006, 0.006, 0.72, gear)                            # 背负天线
			ant.rotation.x = -0.22
			ant.position = Vector3(0.16, 0.62, 0.2)
			ant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			upper.add_child(ant)
			_add(upper, _box(0.1, 0.16, 0.08, gear2), 0.14, 0.3, 0.18)            # 电台包
			for i in 4:                                                           # 肩部伪装布条
				var st := _box(0.05, 0.16, 0.03, uniform)
				st.rotation.z = -0.25 + i * 0.17
				_add(upper, st, -0.18 + i * 0.12, 0.44, 0.06)

	# 皮肤轻量装饰(头盔套/肩带/背包色块,仅非 standard 皮肤)
	if skin != "standard":
		_apply_skin_decor(upper, class_id, skin, pal)
	# [PERF] 合并上半身刚性装具(躯干/头/盔/护具/背包装具),upper 仍为动画枢轴
	_merge_children(upper)

	# 持枪臂组(rig):肩 → 上臂 → 肘 → 前臂/手(肘关节可动,持枪姿态灵活)
	var rig := Node3D.new()
	rig.position = Vector3(0, 0.35, 0)
	var mk_arm := func(x: float, nm: String) -> Dictionary:
		var arm := Node3D.new()
		arm.name = nm
		arm.position = Vector3(x, -0.02, -0.18)
		var up := _box(0.1, 0.1, 0.24, uniform)
		up.position = Vector3(0, 0, -0.12)
		up.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		arm.add_child(up)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, 0, -0.24)
		var fore := _box(0.09, 0.09, 0.2, uniform)
		fore.position = Vector3(0, 0, -0.1)
		fore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elbow.add_child(fore)
		var hand := _box(0.07, 0.07, 0.07, skin_mat)
		hand.position = Vector3(0, 0, -0.2)
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elbow.add_child(hand)
		far_hide.append(hand)
		arm.add_child(elbow)
		rig.add_child(arm)
		return { "arm": arm, "elbow": elbow }
	var arm_l: Dictionary = mk_arm.call(-0.2, "arm_l")
	var arm_r: Dictionary = mk_arm.call(0.2, "arm_r")
	# 第三人称武器:同步玩家改装配置(附件随枪显示,挂点由 MOD_ANCHORS 精确绑定)
	var gun := WeaponModels.build(weapon_id, false, WeaponModsData.load_cfg(weapon_id))
	gun.scale = Vector3.ONE * 1.15
	gun.position = Vector3(0.1, 0.02, -0.45)
	rig.add_child(gun)
	far_hide.append(gun)  # [PERF] 枪 GLB 是最大单体 drawcall,远距整体隐藏
	upper.add_child(rig)
	g.set_meta("rig", rig)
	g.set_meta("arm_l_elbow", arm_l["elbow"])
	g.set_meta("arm_r_elbow", arm_r["elbow"])
	g.set_meta("upper", upper)
	g.set_meta("far_hide", far_hide)
	return g


## 皮肤轻量装饰:头盔套 + 双肩带 + 腰封 + 兵种色块 + 夜视仪(夜间/雪地)
static func _apply_skin_decor(upper: Node3D, class_id: String, skin: String, pal: Dictionary) -> void:
	var cover := _mat(Color.html(pal.get("cover", pal["helmet"])), 0.9)
	var strap := _mat(Color.html(pal.get("strap", pal["gear2"])), 0.92)
	_add(upper, _box(0.26, 0.022, 0.26, cover), 0, 0.752, 0)                 # 头盔套(盖住盔顶)
	_add(upper, _box(0.09, 0.03, 0.27, strap), -0.13, 0.4, -0.02)             # 左肩带
	_add(upper, _box(0.09, 0.03, 0.27, strap), 0.13, 0.4, -0.02)              # 右肩带
	_add(upper, _box(0.4, 0.04, 0.02, strap), 0, 0.06, 0.14)                  # 腰封色带
	match class_id:
		"support":
			_add(upper, _box(0.32, 0.3, 0.02, strap), 0, 0.18, 0.32)           # 背包盖布
		"recon":
			_add(upper, _box(0.2, 0.07, 0.05, cover), 0.16, 0.33, 0.19)        # 电台包盖
			for i in 5:                                                        # 额外伪装布条
				var st := _box(0.05, 0.14, 0.03, cover)
				st.rotation.z = -0.3 + i * 0.2
				_add(upper, st, -0.2 + i * 0.1, 0.46, 0.08)
		"assault":
			_add(upper, _box(0.1, 0.05, 0.04, strap), 0.08, 0.24, -0.17)       # 胸前袋盖
		"engineer":
			_add(upper, _box(0.34, 0.035, 0.21, strap), 0, 0.13, 0.05)         # 护胸横带
	if skin == "night" or skin == "arctic":
		var nvg := _mat(Color(0.1, 0.9, 0.3), 0.3, true)                       # 夜视仪(绿透镜)
		_add(upper, _box(0.026, 0.02, 0.03, nvg), -0.035, 0.66, -0.128)
		_add(upper, _box(0.026, 0.02, 0.03, nvg), 0.035, 0.66, -0.128)


## 圆柱网格助手(z 轴,供背筒/天线等)
static func _cylx(rt: float, rb: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	return mi


## ★第一人称身体的"眼—胸口"间距(米):由 player.gd 每帧把 Chest 骨下压这个量。
## 士兵 GLB 的背心顶面 1.595m / 冲刺前倾最高 ~1.62m,与站立眼高 1.70m 只差 ~10cm;
## 主相机 near=0.08 ⇒ 相机平面会把背心顶面切出一条可见裂缝(Blender 逐帧量化:
## Idle -17° 最小视深 0.077m < 0.08 ⇒ 穿模)。下压 0.15 后间距 ~25cm(真人 ≈30cm),
## 全兵种 x 全动画 x 全俯角最小视深 ≥0.143m,且低头看到的是正常大小的胸口。
const FP_CHEST_DROP := 0.15


## 玩家第一人称身体(骨骼 GLB 版):低头可见真实胸口/腿部,阴影 = 人形轮廓
## - 复用士兵骨骼 GLB;头/脖/双臂骨骼 pose 缩至 0.01(动画不轨 scale 不会被覆盖):
##   头/脖收进躯干防挡视线;手臂隐藏(第一人称手臂由 viewmodel 锥形臂+手模独立渲染,防双臂)
##   **胸腔 Chest 必须保持 1.0**(低头要看得见自己的胸口,见 main.gd 身体可见性注释);
##   胸段整体下移由 player.gd::_apply_fp_chest_drop() 用 pose position 实现(见 FP_CHEST_DROP)
## - 影子补偿:Head 骨附件挂 SHADOWS_ONLY 头/盔代理(地面影子有头);
##   影子枪挂 AimPitch 骨附件(臂链已缩不可挂,枪影仍随视线俯仰)
## meta: skel / anim / gun_mount / far_hide
static func build_player_body(skin := "standard", weapon_id := "", class_id := "assault") -> Node3D:
	var g := build_soldier_glb("us", "", class_id, skin)
	g.name = "PlayerBody"
	# 玩家身体用**独立材质副本**:NPC 共享的调色材质不能被写 uniform(否则所有人一起让位)
	var src_m: ShaderMaterial = null
	var st0: Array = [g]
	while not st0.is_empty():
		var n0: Node = st0.pop_back()
		if n0 is MeshInstance3D and (n0 as MeshInstance3D).material_override is ShaderMaterial:
			src_m = (n0 as MeshInstance3D).material_override
			break
		for c0 in n0.get_children():
			st0.append(c0)
	if src_m != null:
		var pm: ShaderMaterial = src_m.duplicate() as ShaderMaterial
		var st1: Array = [g]
		while not st1.is_empty():
			var n1: Node = st1.pop_back()
			if n1 is MeshInstance3D and (n1 as MeshInstance3D).material_override is ShaderMaterial:
				(n1 as MeshInstance3D).material_override = pm
			for c1 in n1.get_children():
				st1.append(c1)
		g.set_meta("fp_mat", pm)
	var skel: Skeleton3D = g.get_meta("skel")
	if skel != null:
		# 藏头/脖/双臂:缩到 1cm 藏进躯干(GLB 动画只轨 rotation/location,scale 设置永久生效)
		# ★Chest 严禁缩(缩掉 = 低头看不见自己的胸口,用户已明确否决):旧版把 Chest 一起缩到
		#   1cm 是治标——穿模真根因是**站姿眼高错配**:GLB 胸口(背心顶面 1.595,冲刺前倾最高
		#   ~1.62)与旧眼高 1.62 几乎等高,相机等于贴在胸腔里,主相机 near=0.08 把胸口整片裁掉
		#   ⇒ 低头"看不到胸部/看到内部"。正解 = 眼高对齐模型真实眼位(1.62→1.70,净空 ~8cm)。
		for bn in ["Head", "Neck", "ShoulderL", "ShoulderR",
				"UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "HandL", "HandR"]:
			var bi := skel.find_bone(bn)
			if bi >= 0:
				skel.set_bone_pose_scale(bi, Vector3.ONE * 0.01)
		# 影子头代理(只投影不渲染)
		var ha := BoneAttachment3D.new()
		ha.name = "ShadowHead"
		ha.bone_name = "Head"
		skel.add_child(ha)
		var hs := _box(0.2, 0.24, 0.2, _mat(Color.html("#c8a080"), 0.8))
		hs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		ha.add_child(hs)
		# (影子躯干代理已删:胸腔本体恢复渲染后自身即影子投手,再挂代理会双层叠影)
		var hpal: Dictionary = SKINS.get(class_id, SKINS["assault"]).get(skin, SKINS["assault"]["standard"])
		var hel := _box(0.24, 0.12, 0.24, _mat(Color.html(hpal["helmet"]), 0.85))
		hel.position = Vector3(0, 0.14, 0)
		hel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		ha.add_child(hel)
		# 影子武器挂点:AimPitch 骨(未缩;跟随瞄准俯仰) + 右手 rest 偏移
		# 手世界位 (0.14, 1.44, -0.26) - 骨原点 (0, 1.40, -0.04) ≈ (0.14, 0.04, -0.22)
		var ba := BoneAttachment3D.new()
		ba.name = "BodyGun"
		ba.bone_name = "AimPitch"
		skel.add_child(ba)
		ba.position = Vector3(0.14, 0.04, -0.22)
		if not weapon_id.is_empty() and weapon_id != "rpg":
			var gn := WeaponModels.build(weapon_id, false, WeaponModsData.load_cfg(weapon_id))
			gn.rotation_degrees = Vector3(90, 0, 0)
			_set_shadow_only_recursive(gn)
			ba.add_child(gn)
		g.set_meta("gun_mount", ba)
	g.set_meta("far_hide", [])
	return g


static func _set_shadow_only_recursive(node: Node3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for ch in node.get_children():
		_set_shadow_only_recursive(ch)


## 血条(画布贴图 Sprite3D,对应 makeHealthBar)
static func make_health_bar() -> Dictionary:
	var img := Image.create(64, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.pixel_size = 0.9 / 64.0
	sprite.no_depth_test = true
	sprite.position.y = 1.95
	sprite.visible = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	return { "sprite": sprite, "img": img, "tex": tex }


static func update_health_bar(hb: Dictionary, health: float, team: String) -> void:
	# [PERF] 血条上传节流:ImageTexture.update 每次触发 GPU 纹理上传(渲染队列同步点),
	# 64 人混战下受击频繁,每秒几十次 stall;同 bot 0.25s 内或 hp 变化 <6 点时跳过重绘
	var now: float = Time.get_ticks_msec() / 1000.0
	if hb.has("_last_t"):
		var dtu: float = now - float(hb["_last_t"])
		var dhp: float = absf(health - float(hb["_last_hp"]))
		if dtu < 0.25 and dhp < 6.0:
			(hb["sprite"] as Sprite3D).visible = true
			return
	hb["_last_t"] = now
	hb["_last_hp"] = health
	var img: Image = hb["img"]
	# [FIX 纹理空图] img 意外为空时跳过上传(引擎 _texture_2d_update 报错根),
	# 首次发生打诊断日志定位来源
	if img == null or img.is_empty():
		if not hb.has("_img_bad"):
			hb["_img_bad"] = true
			push_warning("[TEX] 血条 Image 为空,跳过纹理上传 (诊断: img=", img, ")")
		(hb["sprite"] as Sprite3D).visible = true
		return
	img.fill(Color(0, 0, 0, 0.7))
	var col := Color(0.0, 1.0, 0.53) if team == "us" else Color(1.0, 0.33, 0.0)
	var w := int(clampf(health / 100.0, 0.0, 1.0) * 62.0)
	if w > 0:
		img.fill_rect(Rect2i(1, 1, w, 8), col)
	(hb["tex"] as ImageTexture).update(img)
	(hb["sprite"] as Sprite3D).visible = true


## ---- BR 头顶阵营标记(视觉敌我识别:敌方红菱形 / 队友绿菱形) ----
## 纹理静态缓存:全 bot 共享 red/green 两张 64×64 菱形贴图(暗描边 + 实心),
## 每 bot 仅 1 个 Sprite3D(billboard + no_depth_test),挂 mesh 下头顶(高 0.28m)。
static var _mk_tex: Dictionary = {}


static func _mk_diamond_tex(col: Color) -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := S * 0.5
	var half := S * 0.44
	for y in S:
		for x in S:
			var d := absf(x - c) + absf(y - c)
			if d <= half:
				var bc := Color(col.r * 0.32, col.g * 0.32, col.b * 0.32, 1.0)
				img.set_pixel(x, y, bc if d > half - 3.0 else col)
	return ImageTexture.create_from_image(img)


## 敌/友标记纹理("red" / "green",各创建一次后共享)
static func team_marker_texture(color: String) -> ImageTexture:
	if _mk_tex.has(color):
		return _mk_tex[color]
	var col := Color(1.0, 0.15, 0.12) if color == "red" else Color(0.25, 1.0, 0.5)
	var tex := _mk_diamond_tex(col)
	_mk_tex[color] = tex
	return tex


## BR 头顶阵营标记(默认隐藏;bot.gd 按小队分类设置纹理/可见性)
static func make_team_marker() -> Sprite3D:
	var s := Sprite3D.new()
	s.pixel_size = 0.28 / 64.0
	s.no_depth_test = true
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.position.y = 2.22
	s.visible = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	return s
