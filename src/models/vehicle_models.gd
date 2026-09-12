class_name VehicleModels
## 载具建模(对应 vehicles.js 的 buildJeep/buildTank/buildApc/buildAa)


static func _tex(file: String) -> Texture2D:
	return load("res://textures/" + file)


static func _std(color: Color, rough: float, metal: float, rust := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_repeat = true
	if rust:
		m.albedo_texture = _tex("rusty_metal_diff.jpg")
		m.normal_enabled = true
		m.normal_texture = _tex("rusty_metal_nor.jpg")
	else:
		m.albedo_texture = _tex("metal_plate_diff.jpg")
		m.normal_enabled = true
		m.normal_texture = _tex("metal_plate_nor.jpg")
	return m


static func _plain(color: Color, rough: float, metal := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


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


static func _add(parent: Node3D, mesh: MeshInstance3D, x: float, y: float, z: float) -> MeshInstance3D:
	mesh.position = Vector3(x, y, z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh)
	return mesh


## ==================== 第一人称座舱内构辅助(统一复用,不复制代码) ====================

## 乘员座椅:坐垫 + 靠背 + 头枕;forward=-Z,back=+Z
static func _crew_seat(parent: Node3D, mat: Material, x: float, y: float, z: float, s := 1.0) -> Node3D:
	var seat := Node3D.new()
	seat.position = Vector3(x, y, z)
	parent.add_child(seat)
	var cushion := _box(0.52 * s, 0.10 * s, 0.52 * s, mat)
	cushion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	seat.add_child(cushion)
	var back := _box(0.52 * s, 0.62 * s, 0.09 * s, mat)
	back.position = Vector3(0, 0.30 * s, 0.30 * s)
	back.rotation.x = -0.10
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	seat.add_child(back)
	var head := _box(0.30 * s, 0.18 * s, 0.08 * s, mat)
	head.position = Vector3(0, 0.58 * s, 0.34 * s)
	head.rotation.x = -0.10
	seat.add_child(head)
	return seat


## 观瞄/火控显示器:黑色设备体 + 发光电子屏(屏面朝 -Z,即乘员视线方向)
static func _fcs_screen(parent: Node3D, dark: Material, screen_col: Color, x: float, y: float, z: float, w := 0.34, h := 0.22) -> Node3D:
	var unit := Node3D.new()
	unit.position = Vector3(x, y, z)
	parent.add_child(unit)
	var case_box := _box(w + 0.05, h + 0.05, 0.09, dark)
	case_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	unit.add_child(case_box)
	var scr_mat := _plain(Color(screen_col.r, screen_col.g, screen_col.b, 1.0), 0.35, 0.1)
	scr_mat.emission_enabled = true
	scr_mat.emission = screen_col
	scr_mat.emission_energy_multiplier = 0.85
	var screen := _box(w, h, 0.012, scr_mat)
	screen.position = Vector3(0, 0, -0.052)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	unit.add_child(screen)
	return unit


## 操纵杆/方向杆:底座 + 斜杆 + 握把
static func _control_stick(parent: Node3D, mat: Material, x: float, y: float, z: float, side := 1.0) -> Node3D:
	var st := Node3D.new()
	st.position = Vector3(x, y, z)
	parent.add_child(st)
	var base := _cyl(0.055, 0.075, 0.08, 8, mat)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	st.add_child(base)
	var shaft := _cyl(0.014, 0.014, 0.30, 6, mat)
	shaft.position = Vector3(0, 0.16, 0)
	shaft.rotation.z = 0.38 * side
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	st.add_child(shaft)
	var grip := _cyl(0.025, 0.025, 0.09, 8, mat)
	grip.position = Vector3(side * 0.09, 0.30, 0)
	grip.rotation.x = PI / 2.0
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	st.add_child(grip)
	return st


## 舱内微光照明(暖白/暗红,不投影):保证第一人称舱内可见且不过曝
static func _interior_light(parent: Node3D, color: Color, x: float, y: float, z: float, energy := 0.65, range_m := 3.0) -> void:
	var li := OmniLight3D.new()
	li.light_color = color
	li.light_energy = energy
	li.omni_range = range_m
	li.shadow_enabled = false
	li.position = Vector3(x, y, z)
	parent.add_child(li)


## 观察窗装甲框:两条竖框 + 上/下横框,中央留观察缝(乘员真实视野遮挡)
static func _vision_frame(parent: Node3D, mat: Material, x: float, y: float, z: float, w: float, h: float) -> void:
	_add(parent, _box(0.07, h, 0.08, mat), x - w * 0.5, y, z)
	_add(parent, _box(0.07, h, 0.08, mat), x + w * 0.5, y, z)
	_add(parent, _box(w + 0.14, 0.07, 0.08, mat), x, y + h * 0.5, z)
	_add(parent, _box(w + 0.14, 0.07, 0.08, mat), x, y - h * 0.5, z)


## 军用吉普
static func _legacy_build_jeep() -> Node3D:
	var g := Node3D.new()
	g.name = "Jeep"
	var body := _std(Color.html("#5a6348"), 0.55, 0.35)
	var dark := _std(Color.html("#2a2e32"), 0.75, 0.0)
	var glass := _plain(Color(0.54, 0.69, 0.78, 0.5), 0.15, 0.8)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add(g, _box(1.8, 0.5, 3.8, body), 0, 0.72, 0)
	_add(g, _box(1.7, 0.4, 1.1, body), 0, 1.05, -1.25)
	_add(g, _box(1.7, 0.25, 1.2, body), 0, 1.0, 1.25)
	_add(g, _box(1.6, 0.15, 0.9, dark), 0, 1.0, 0.3)
	var ws := _add(g, _box(1.6, 0.7, 0.06, glass), 0, 1.55, -0.45)
	ws.rotation.x = -0.25
	var cage := _plain(Color.html("#2a2e32"), 0.5, 0.6)
	for p in [[-0.8, -0.4], [0.8, -0.4], [-0.8, 0.9], [0.8, 0.9]]:
		_add(g, _cyl(0.04, 0.04, 1.1, 6, cage), p[0], 1.55, p[1])
	_add(g, _box(1.7, 0.08, 1.4, cage), 0, 2.1, 0.25)
	# 方向盘:细轮缘 + 三辐条 + 轮毂(替代原实心圆盘)
	var sw := Node3D.new()
	sw.position = Vector3(-0.45, 1.38, -0.28)
	sw.rotation.x = -0.62
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.132
	tor.outer_radius = 0.158
	tor.rings = 8
	tor.ring_segments = 24
	rim.mesh = tor
	rim.material_override = dark
	rim.rotation.x = PI / 2.0
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sw.add_child(rim)
	for k in 3:  # 三辐条
		var ang: float = k * TAU / 3.0
		var spoke := _box(0.024, 0.145, 0.014, dark)
		spoke.position = Vector3(sin(ang) * 0.0725, cos(ang) * 0.0725, 0)
		spoke.rotation.z = -ang
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		sw.add_child(spoke)
	var sw_hub := _cyl(0.035, 0.035, 0.045, 8, dark)
	sw_hub.rotation.x = PI / 2.0
	sw_hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sw.add_child(sw_hub)
	g.add_child(sw)
	var wheel_mat := _plain(Color.html("#14161a"), 0.95)
	var hub_mat := _plain(Color.html("#5a5c60"), 0.4, 0.7)
	var wheels: Array = []
	var front_wheels: Array = []
	for w in [[-0.85, -1.25, true], [0.85, -1.25, true], [-0.85, 1.25, false], [0.85, 1.25, false]]:
		var pivot := Node3D.new()
		pivot.position = Vector3(w[0], 0.42, w[1])
		var spin := Node3D.new()
		var tire := _cyl(0.42, 0.42, 0.3, 12, wheel_mat)
		tire.rotation.z = PI / 2.0
		tire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var hub := _cyl(0.18, 0.18, 0.32, 8, hub_mat)
		hub.rotation.z = PI / 2.0
		spin.add_child(tire)
		spin.add_child(hub)
		pivot.add_child(spin)
		g.add_child(pivot)
		wheels.append(spin)
		if w[2]:
			front_wheels.append(pivot)
	g.set_meta("wheels", wheels)
	g.set_meta("front_wheels", front_wheels)
	return g


## 主战坦克
static func _legacy_build_tank() -> Node3D:
	var g := Node3D.new()
	g.name = "Tank"
	var camo := _std(Color.html("#4e5a42"), 0.7, 0.3)
	var dark := _std(Color.html("#24282c"), 0.85, 0.0)
	var track_mat := _std(Color.html("#3a3c38"), 0.9, 0.4, true)
	for tx in [-1.15, 1.15]:
		_add(g, _box(0.7, 0.8, 5.4, track_mat), tx, 0.55, 0)
		for i in 5:
			var w := _cyl(0.34, 0.34, 0.74, 10, dark)
			w.rotation.z = PI / 2.0
			_add(g, w, tx, 0.36, -2.0 + i * 1.0)
	_add(g, _box(2.5, 0.85, 4.7, camo), 0, 1.15, 0)
	_add(g, _box(2.2, 0.3, 1.6, camo), 0, 1.65, 1.6)
	# 炮塔(独立旋转)
	var turret := Node3D.new()
	turret.position = Vector3(0, 1.85, 0.2)
	_add(turret, _box(1.9, 0.6, 2.5, camo), 0, 0.15, 0)
	_add(turret, _box(1.5, 0.5, 0.8, camo), 0, 0.12, 1.5)
	var cannon := Node3D.new()
	cannon.position = Vector3(0, 0.22, -1.1)
	var barrel := _cyl(0.085, 0.095, 3.4, 10, dark)
	barrel.rotation.x = PI / 2.0
	barrel.position.z = -1.7
	barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cannon.add_child(barrel)
	var brake := _cyl(0.13, 0.13, 0.4, 8, dark)
	brake.rotation.x = PI / 2.0
	brake.position.z = -3.2
	cannon.add_child(brake)
	turret.add_child(cannon)
	_add(turret, _cyl(0.3, 0.3, 0.12, 10, camo), -0.4, 0.5, 0.5)
	g.add_child(turret)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.22, -4.6)
	turret.add_child(muzzle)
	g.set_meta("turret", turret)
	g.set_meta("cannon", cannon)
	g.set_meta("muzzle", muzzle)
	# [车内视角 v2] 坦克驾驶位观察舱(低模):舱顶/观察口上缘/后舱壁/侧舱壁/仪表台/地板
	# 相机驾驶位 ≈ 车体局部 (0, 1.23, 0.35);观察口:上缘 ~19° / 下缘(仪表台)~17.6°
	# 中央 60%~75% 保持战场视野,车内结构只出现在屏幕四周
	var interior := Node3D.new()
	interior.name = "Interior"
	var in_dark := _std(Color.html("#1c1f22"), 0.85, 0.0)
	var in_metal := _std(Color.html("#2c3035"), 0.7, 0.3)
	_add(interior, _box(1.7, 0.06, 1.4, in_dark), 0, 1.545, 0.35)        # 舱顶(齐车体顶,防仰角透天)
	_add(interior, _box(1.7, 0.105, 0.05, in_dark), 0, 1.5225, -0.35)    # 观察口上缘
	_add(interior, _box(1.7, 0.87, 0.08, in_dark), 0, 1.14, 1.25)        # 后舱壁
	_add(interior, _box(0.08, 0.87, 1.6, in_dark), -0.86, 1.14, 0.45)    # 左舱壁
	_add(interior, _box(0.08, 0.87, 1.6, in_dark), 0.86, 1.14, 0.45)     # 右舱壁
	_add(interior, _box(1.7, 0.06, 1.6, in_dark), 0, 0.73, 0.45)         # 地板
	_add(interior, _box(1.6, 0.32, 0.6, in_dark), 0, 0.88, 0.05)         # 仪表台
	_add(interior, _box(0.5, 0.03, 0.3, in_metal), -0.3, 1.08, -0.25)    # 仪表板
	# [载具内构 v3] 驾驶员座舱细节:座椅/双操纵杆/电子仪表/装甲观察窗框
	_crew_seat(interior, in_dark, 0.0, 0.78, 0.68, 0.9)
	_control_stick(interior, in_dark, -0.33, 0.93, 0.04, 1.0)
	_control_stick(interior, in_dark, 0.33, 0.93, 0.04, -1.0)
	_fcs_screen(interior, in_dark, Color(0.2, 0.85, 0.55), -0.30, 1.10, -0.16, 0.30, 0.15)
	_fcs_screen(interior, in_dark, Color(0.22, 0.68, 0.92), 0.32, 1.10, -0.16, 0.28, 0.15)
	_vision_frame(interior, in_dark, 0.0, 1.30, -0.40, 1.30, 0.52)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.32, 0.10, 0.55, 2.6)
	g.add_child(interior)
	g.set_meta("interior", interior)
	# 炮手位内构(随炮塔):潜望镜(上移到炮塔顶装饰,不挡炮镜视线)+ 炮塔内壁 + 舱盖框
	# (舱顶内衬已移除:贴脸黑色建模挡视野;炮塔顶盖背面剔除,抬头自然透光)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _cyl(0.045, 0.055, 0.45, 8, in_dark), 0.35, 0.78, -0.6).name = "Periscope"  # 潜望镜杆(炮手位第一人称隐藏)
	_add(it, _box(0.5, 0.4, 0.06, in_dark), 0, 0.2, 1.5)
	_add(it, _box(0.06, 0.4, 1.2, in_dark), -0.95, 0.25, 0.2)
	_add(it, _box(0.06, 0.4, 1.2, in_dark), 0.95, 0.25, 0.2)
	_add(it, _box(0.7, 0.08, 0.7, in_dark), 0, 0.62, 0.4)
	# [载具内构 v3] 炮手位/车长位细节:双座椅/光电观瞄设备/火控面板/弹药架
	_crew_seat(it, in_dark, 0.34, 0.10, 0.02, 0.85)
	_crew_seat(it, in_dark, -0.42, 0.10, 0.10, 0.85)
	_fcs_screen(it, in_dark, Color(0.24, 0.88, 0.58), 0.58, 0.34, -0.44, 0.30, 0.20)
	_fcs_screen(it, in_dark, Color(0.95, 0.62, 0.2), -0.60, 0.36, -0.38, 0.24, 0.15)
	_add(it, _box(0.46, 0.05, 0.42, in_metal), 0.0, 0.10, -0.55)      # 炮手脚踏/防滑板
	_add(it, _box(0.10, 0.30, 0.34, in_dark), -0.72, 0.16, 1.05)      # 待发弹药架
	_control_stick(it, in_dark, 0.66, 0.10, 0.18, -1.0)
	_interior_light(it, Color(0.9, 0.38, 0.22), 0.0, 0.55, 0.55, 0.6, 2.8)
	turret.add_child(it)
	g.set_meta("interior_turret", it)
	return g


## 轮式装甲步战车(APC,25mm 机炮)
static func _legacy_build_apc() -> Node3D:
	var g := Node3D.new()
	g.name = "Apc"
	var camo := _std(Color.html("#55604a"), 0.6, 0.35)
	var dark := _std(Color.html("#25292d"), 0.85, 0.0)
	var wheel_mat := _plain(Color.html("#14161a"), 0.95)
	var wheels: Array = []
	for wz in [-1.9, -0.65, 0.65, 1.9]:
		for wx in [-1.05, 1.05]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, 0.46, wz)
			var tire := _cyl(0.46, 0.46, 0.34, 12, wheel_mat)
			tire.rotation.z = PI / 2.0
			tire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			pivot.add_child(tire)
			g.add_child(pivot)
			wheels.append(tire)
	_add(g, _box(2.2, 0.9, 5.6, camo), 0, 1.15, 0)
	_add(g, _box(1.9, 0.5, 3.4, camo), 0, 1.85, 0.5)
	for sx in [-1.15, 1.15]:
		_add(g, _box(0.12, 0.6, 4.6, camo), sx, 0.85, 0)
	var turret := Node3D.new()
	turret.position = Vector3(0, 2.15, -0.3)
	_add(turret, _box(1.3, 0.5, 1.7, camo), 0, 0.1, 0)
	var cannon := Node3D.new()
	cannon.position = Vector3(0, 0.16, -0.8)
	var barrel := _cyl(0.045, 0.055, 2.3, 8, dark)
	barrel.rotation.x = PI / 2.0
	barrel.position.z = -1.15
	barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cannon.add_child(barrel)
	var cage := _box(0.16, 0.16, 0.5, dark)
	cage.position.z = -0.35
	cannon.add_child(cage)
	turret.add_child(cannon)
	_add(turret, _box(0.5, 0.28, 0.7, dark), 0.45, 0.2, 0.4)
	g.add_child(turret)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.16, -3.2)
	turret.add_child(muzzle)
	g.set_meta("turret", turret)
	g.set_meta("cannon", cannon)
	g.set_meta("muzzle", muzzle)
	g.set_meta("wheels", wheels)
	# [车内视角 v2] APC 驾驶位观察舱(低模)
	# 相机驾驶位 ≈ 车体局部 (0, 1.3, -1.3);观察口:上缘 ~17.4° / 下缘(仪表台)~15.6°
	var interior := Node3D.new()
	interior.name = "Interior"
	var in_dark := _std(Color.html("#1c1f22"), 0.85, 0.0)
	var in_metal := _std(Color.html("#2c3035"), 0.7, 0.3)
	_add(interior, _box(1.7, 0.06, 1.8, in_dark), 0, 1.57, -1.2)         # 舱顶(齐车体顶,防仰角透天)
	_add(interior, _box(1.7, 0.05, 0.05, in_dark), 0, 1.575, -2.1)       # 观察口上缘
	_add(interior, _box(1.7, 0.87, 0.08, in_dark), 0, 1.165, -0.35)      # 后舱壁
	_add(interior, _box(0.08, 0.87, 1.8, in_dark), -0.86, 1.165, -1.2)   # 左舱壁
	_add(interior, _box(0.08, 0.87, 1.8, in_dark), 0.86, 1.165, -1.2)    # 右舱壁
	_add(interior, _box(1.7, 0.06, 1.8, in_dark), 0, 0.73, -1.2)         # 地板
	_add(interior, _box(1.6, 0.27, 0.6, in_dark), 0, 0.915, -1.9)        # 仪表台
	_add(interior, _box(0.5, 0.03, 0.3, in_metal), -0.3, 1.09, -1.6)     # 仪表板
	# [载具内构 v3] 驾驶员座舱:座椅/方向盘/电子仪表/观察窗框
	_crew_seat(interior, in_dark, 0.0, 0.75, -0.88, 0.9)
	var apc_wheel := _cyl(0.025, 0.025, 0.34, 8, in_dark)
	apc_wheel.position = Vector3(0, 1.0, -1.58)
	apc_wheel.rotation.x = -0.55
	apc_wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	interior.add_child(apc_wheel)
	_fcs_screen(interior, in_dark, Color(0.2, 0.82, 0.52), -0.28, 1.1, -1.52, 0.30, 0.15)
	_fcs_screen(interior, in_dark, Color(0.22, 0.66, 0.9), 0.30, 1.1, -1.52, 0.28, 0.15)
	_vision_frame(interior, in_dark, 0.0, 1.30, -2.08, 1.12, 0.42)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.35, -1.1, 0.55, 1.5)
	g.add_child(interior)
	g.set_meta("interior", interior)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _cyl(0.035, 0.045, 0.4, 8, in_dark), 0.3, 0.7, -0.55).name = "Periscope"
	_add(it, _box(0.4, 0.35, 0.05, in_dark), 0, 0.15, 1.3)
	_add(it, _box(0.05, 0.35, 1.0, in_dark), -0.62, 0.2, 0.1)
	_add(it, _box(0.05, 0.35, 1.0, in_dark), 0.62, 0.2, 0.1)
	# [载具内构 v3] 炮手位:座椅/光电显示屏/操作台
	_crew_seat(it, in_dark, 0.30, 0.04, -0.02, 0.8)
	_fcs_screen(it, in_dark, Color(0.24, 0.86, 0.56), 0.54, 0.28, -0.38, 0.26, 0.18)
	_control_stick(it, in_dark, 0.58, 0.04, 0.12, -1.0)
	_interior_light(it, Color(0.9, 0.4, 0.22), 0.0, 0.45, 0.4, 0.5, 2.4)
	turret.add_child(it)
	g.set_meta("interior_turret", it)
	return g


## 自行防空炮车(AA,四联高射机炮)
static func _legacy_build_aa() -> Node3D:
	var g := Node3D.new()
	g.name = "Aa"
	var camo := _std(Color.html("#5c5a48"), 0.65, 0.3)
	var dark := _std(Color.html("#24282c"), 0.85, 0.0)
	var wheel_mat := _plain(Color.html("#14161a"), 0.95)
	var wheels: Array = []
	for wz in [-1.6, 0.0, 1.6]:
		for wx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, 0.44, wz)
			var tire := _cyl(0.44, 0.44, 0.32, 12, wheel_mat)
			tire.rotation.z = PI / 2.0
			tire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			pivot.add_child(tire)
			g.add_child(pivot)
			wheels.append(tire)
	_add(g, _box(2.1, 0.85, 4.9, camo), 0, 1.1, 0)
	_add(g, _box(1.7, 0.6, 1.4, camo), 0, 1.8, -1.5)
	var win_mat := _plain(Color(0.16, 0.2, 0.24, 0.35), 0.15, 0.5)
	win_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add(g, _box(1.5, 0.4, 0.06, win_mat), 0, 1.85, -2.22)
	var turret := Node3D.new()
	turret.position = Vector3(0, 2.0, 0.9)
	_add(turret, _cyl(0.85, 1.0, 0.5, 10, camo), 0, 0, 0)
	var cannon := Node3D.new()
	cannon.position = Vector3(0, 0.35, 0)
	for b in [[-0.16, 0.1], [0.16, 0.1], [-0.16, -0.1], [0.16, -0.1]]:
		var barrel := _cyl(0.035, 0.04, 2.1, 8, dark)
		barrel.rotation.x = PI / 2.0
		barrel.position = Vector3(b[0], b[1], -1.0)
		barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		cannon.add_child(barrel)
	var ammo_box := _box(0.6, 0.4, 0.8, camo)
	ammo_box.position = Vector3(0, 0, -0.2)
	cannon.add_child(ammo_box)
	turret.add_child(cannon)
	var radar := _box(0.9, 0.5, 0.1, dark)
	radar.position = Vector3(0, 0.75, 0.55)
	radar.rotation.x = -0.5
	turret.add_child(radar)
	g.add_child(turret)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.35, -2.2)
	turret.add_child(muzzle)
	g.set_meta("turret", turret)
	g.set_meta("cannon", cannon)
	g.set_meta("muzzle", muzzle)
	g.set_meta("wheels", wheels)
	# [车内视角 v2] AA 驾驶位观察舱(低模)
	# 相机驾驶位 ≈ 车体局部 (0, 1.28, -1.35);观察口:上缘 ~14.4° / 下缘(仪表台)~18.4°
	var interior := Node3D.new()
	interior.name = "Interior"
	var in_dark := _std(Color.html("#1c1f22"), 0.85, 0.0)
	var in_metal := _std(Color.html("#2c3035"), 0.7, 0.3)
	_add(interior, _box(1.6, 0.06, 1.8, in_dark), 0, 1.495, -1.25)       # 舱顶(齐车体顶,防仰角透天)
	_add(interior, _box(1.6, 0.045, 0.05, in_dark), 0, 1.5025, -2.15)    # 观察口上缘
	_add(interior, _box(1.6, 0.82, 0.08, in_dark), 0, 1.115, -0.4)       # 后舱壁
	_add(interior, _box(0.08, 0.82, 1.8, in_dark), -0.81, 1.115, -1.25)  # 左舱壁
	_add(interior, _box(0.08, 0.82, 1.8, in_dark), 0.81, 1.115, -1.25)   # 右舱壁
	_add(interior, _box(1.6, 0.06, 1.8, in_dark), 0, 0.7, -1.25)         # 地板
	_add(interior, _box(1.5, 0.27, 0.6, in_dark), 0, 0.895, -1.8)        # 仪表台
	_add(interior, _box(0.5, 0.03, 0.3, in_metal), -0.3, 1.07, -1.5)     # 仪表板
	# [载具内构 v3] AA 驾驶员座舱:座椅/方向盘/仪表/防弹观察窗装甲框
	_crew_seat(interior, in_dark, 0.0, 0.72, -0.82, 0.9)
	var aa_wheel := _cyl(0.024, 0.024, 0.34, 8, in_dark)
	aa_wheel.position = Vector3(0, 0.98, -1.56)
	aa_wheel.rotation.x = -0.55
	aa_wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	interior.add_child(aa_wheel)
	_fcs_screen(interior, in_dark, Color(0.2, 0.85, 0.55), -0.27, 1.08, -1.48, 0.30, 0.15)
	_fcs_screen(interior, in_dark, Color(0.9, 0.6, 0.2), 0.30, 1.08, -1.48, 0.26, 0.15)
	_vision_frame(interior, in_dark, 0.0, 1.26, -2.14, 1.02, 0.46)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.34, -1.05, 0.55, 2.6)
	# 观察位车顶机枪(战地式):盆环 + 立柱 + 随观察方向旋转的机枪座
	# (货斗前右角,避开旋转平台半径;controller 驱动 meta "observer_mg" 转向)
	var mg_ring := _cyl(0.16, 0.18, 0.04, 12, in_metal)
	mg_ring.position = Vector3(0.62, 1.53, -0.55)
	interior.add_child(mg_ring)
	var mg_post := _cyl(0.025, 0.03, 0.42, 8, in_dark)
	mg_post.position = Vector3(0.62, 1.75, -0.55)
	interior.add_child(mg_post)
	var mg_pivot := Node3D.new()
	mg_pivot.name = "ObserverMg"
	mg_pivot.position = Vector3(0.62, 1.96, -0.55)
	interior.add_child(mg_pivot)
	_add(mg_pivot, _box(0.09, 0.10, 0.52, in_dark), 0, 0, -0.10)
	_add(mg_pivot, _cyl(0.018, 0.018, 0.46, 8, in_dark), 0, 0.01, -0.55).name = "MgBarrel"
	_add(mg_pivot, _box(0.07, 0.12, 0.10, in_dark), 0, -0.10, 0.06)
	_add(mg_pivot, _box(0.10, 0.09, 0.16, in_dark), 0.0, -0.11, -0.18)
	g.set_meta("observer_mg", mg_pivot)
	g.add_child(interior)
	g.set_meta("interior", interior)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _cyl(0.04, 0.05, 0.4, 8, in_dark), 0.3, 0.8, -0.5).name = "Periscope"
	_add(it, _box(0.06, 0.5, 1.4, in_dark), -0.75, 0.25, 0.2)
	_add(it, _box(0.06, 0.5, 1.4, in_dark), 0.75, 0.25, 0.2)
	_add(it, _box(0.6, 0.45, 0.06, in_dark), 0, 0.2, 1.3)
	# [载具内构 v3] AA 武器操作员:座椅/搜索雷达显示屏/火控面板/双手握把
	_crew_seat(it, in_dark, 0.32, 0.22, 0.0, 0.82)
	_crew_seat(it, in_dark, -0.48, 0.34, -0.12, 0.78)
	_fcs_screen(it, in_dark, Color(0.18, 0.9, 0.5), 0.58, 0.52, -0.34, 0.34, 0.24)
	_fcs_screen(it, in_dark, Color(1.0, 0.55, 0.18), -0.56, 0.54, -0.30, 0.24, 0.16)
	_control_stick(it, in_dark, 0.50, 0.30, -0.46, -1.0)
	_control_stick(it, in_dark, 0.18, 0.30, -0.46, 1.0)
	_add(it, _box(0.36, 0.05, 0.30, in_metal), 0.32, 0.12, -0.50)
	_interior_light(it, Color(0.9, 0.42, 0.2), 0.0, 0.62, 0.35, 0.55, 2.6)
	turret.add_child(it)
	g.set_meta("interior_turret", it)
	return g


## ==================== GLB 外部建模管线(方案 A) ====================
## 外部车体来自 models/vehicles/{id}.glb(build_vehicle_batch.py,Blender 管线)。
## 契约节点:Turret(炮塔旋转)/Cannon(炮管俯仰+后坐)/Muzzle(炮口)/
## Wheel*(滚动)/Steer_*(前轮转向)。
## 舱内构(座椅/火控屏/操纵杆/观察窗框)保留 GDScript 版叠加在 GLB 之上。

const VEH_GLB := "res://models/vehicles/"


static func build_jeep() -> Node3D:
	var g := _load_veh("jeep", "Jeep")
	if g == null:
		return _legacy_build_jeep()
	_jeep_cockpit(g)
	_veh_wire(g, false)
	return g


static func build_tank() -> Node3D:
	var g := _load_veh("tank", "Tank")
	if g == null:
		return _legacy_build_tank()
	_veh_wire(g, true)
	_tank_interior(g)
	return g


static func build_apc() -> Node3D:
	var g := _load_veh("apc", "Apc")
	if g == null:
		return _legacy_build_apc()
	_veh_wire(g, true)
	_apc_interior(g)
	return g


static func build_aa() -> Node3D:
	var g := _load_veh("aa", "Aa")
	if g == null:
		return _legacy_build_aa()
	_veh_wire(g, true)
	_aa_interior(g)
	return g


## 突击摩托:无炮塔、无内饰(车把/仪表已在 GLB 内),仅接轮子契约。
static func build_motorcycle() -> Node3D:
	var g := _load_veh("motorcycle", "Motorcycle")
	if g == null:
		return _legacy_build_jeep()
	_veh_wire(g, false)
	return g


## 载入 GLB 外壳并按名字前缀重贴金属板/锈蚀材质
static func _load_veh(id: String, root_name: String) -> Node3D:
	var path := VEH_GLB + id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[vehicle] GLB 缺失,回落程序化建模: " + path)
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var g: Node3D = ps.instantiate()
	g.name = root_name
	_veh_mats(g, id)
	return g


## 载具外表面材质:对标枪模材质水准 —— 程序化 PBR 贴图(gun_poly/gun_metal/
## gun_dark/gun_chrome/rusty_metal)+ 三平面映射(车体大面无 UV 拉伸)。
## 哑光军绿漆面(金属度 0.05,漆面不是裸金属!)、橡胶轮胎、履带钢、裸金属、
## 镀铬大灯、锈蚀油桶、透明玻璃。军绿按零件名哈希取 3 档明暗打破均匀感。
static func _vstd(color: Color, rough: float, metal: float, tex: String, nor: String, tiling := 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_repeat = true
	m.albedo_texture = _tex(tex)
	m.normal_enabled = true
	m.normal_texture = _tex(nor)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * tiling
	return m


static func _veh_mats(g: Node3D, id: String) -> void:
	var paint_base: Color
	match id:
		"jeep":
			paint_base = Color.html("#66714f")
		"tank":
			paint_base = Color.html("#55614a")
		"apc":
			paint_base = Color.html("#5d6a50")
		"motorcycle":
			paint_base = Color.html("#4f5a44")
		_:
			paint_base = Color.html("#6a6a52")
	# [FIX] 漆面纹理换 gun_metal(avg 160) —— 旧 gun_poly 是黑色聚合物纹理(avg 64),
	# × 军绿 albedo 相乘后整车近黑("车身没有贴图"实锤);albedo 大幅提亮:
	# 军绿 #55614a 本身暗(linear ~0.12),竖直面只剩弱天光(正午太阳直射顶面),
	# lightened 0.38+ 后侧面才有"上漆"观感
	var ptex := "gun_metal_diff.jpg"
	var pnor := "gun_metal_nor.jpg"
	# 摩托体积小,三档明暗差太大显"花";收紧到 0.34~0.40 保持整车一体
	var lo := 0.30
	var mid := 0.44
	var hi := 0.38
	if id == "motorcycle":
		lo = 0.34
		mid = 0.40
		hi = 0.37
	var paint := [
		_vstd(paint_base.lightened(hi), 0.78, 0.05, ptex, pnor, 2.5),
		_vstd(paint_base.lightened(mid), 0.76, 0.05, ptex, pnor, 2.5),
		_vstd(paint_base.lightened(lo), 0.8, 0.05, ptex, pnor, 2.5),
	]
	var rubber := _vstd(Color.html("#17181a"), 0.95, 0.0, ptex, pnor, 4.0)
	var track := _vstd(Color.html("#4a4c46"), 0.6, 0.75, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 5.0)
	var hub := _vstd(Color.html("#6a6e74"), 0.4, 0.8, "gun_metal_diff.jpg", "gun_metal_nor.jpg", 6.0)
	var dark := _vstd(Color.html("#26292c"), 0.6, 0.4, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 3.0)
	var chrome := _vstd(Color.html("#cfd4d8"), 0.2, 0.9, "gun_chrome_diff.jpg", "gun_chrome_nor.jpg", 4.0)
	var rust := _vstd(Color.html("#9a6a42"), 0.92, 0.3, "rusty_metal_diff.jpg", "rusty_metal_nor.jpg", 3.0)
	var glass := _plain(Color(0.55, 0.65, 0.75, 0.20), 0.10, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		# 包含匹配:零件名是 WheelFL_Tire / _DeckGrille0 这类"前缀无关"格式,
		# 旧版 begins_with 前缀匹配全部落空 → 全车默认漆色金属感(实拍实锤)
		var picked: Material
		if nm.contains("Glass"):
			picked = glass
		elif nm.contains("SpareWheel") or nm.contains("Tire"):
			picked = rubber
		elif nm.contains("RoadWheel") or nm.contains("Sprocket") or nm.contains("Idler") or nm.contains("Track"):
			picked = track
		elif nm.contains("Hub"):
			picked = hub
		elif nm.contains("Head") or nm.contains("Light"):
			picked = chrome
		# 摩托裸金属件(2026-09-11): 前叉/车把/转向柱/三角台/后视镜/拉杆/轮辐/刹车盘/脚踏
		elif nm.contains("Fork") or nm.contains("Handlebar") or nm.contains("Steerer") \
				or nm.contains("Clamp") or nm.contains("Mirror") or nm.contains("Lever") \
				or nm.contains("Disc") or nm.contains("Spoke") or nm.contains("Peg"):
			picked = hub
		# 摩托深色件: 座垫/链条/握把/仪表/摇臂/减震/排气(哑光黑; 排气用亮金属会在侧视压住后轮太扎眼)
		elif nm.contains("Seat") or nm.contains("Chain") or nm.contains("Grip") \
				or nm.contains("Dash") or nm.contains("Swingarm") or nm.contains("Shock") \
				or nm.contains("Muffler") or nm.contains("Pipe"):
			picked = dark
		elif nm.contains("FuelDrum") or nm.contains("DrumBracket"):
			picked = rust
		elif nm.contains("Barrel") or nm.contains("Brake") or nm.contains("Breech") or nm.contains("Receiver") \
				or nm.contains("Muzzle") or nm.contains("CannonTube") or nm.contains("Smoke") or nm.contains("Antenna") \
				or nm.contains("Mg") or nm.contains("Driveshaft") or nm.contains("Grille") or nm.contains("Cage") \
				or nm.contains("Bumper") or nm.contains("Frame") or nm.contains("Radar") or nm.contains("Outrigger") \
				or nm.contains("Rack") or nm.contains("Slot") or nm.contains("Sight"):
			picked = dark
		elif nm.contains("Ammo"):
			picked = paint[0]
		else:
			picked = paint[absi(nm.hash()) % paint.size()]
		mi.material_override = picked


## 接线契约节点:turret/cannon/muzzle/wheels/front_wheels
static func _veh_wire(g: Node3D, has_turret: bool) -> void:
	var wheels: Array = []
	var fronts: Array = []
	for c in g.find_children("*", "Node3D", true, false):
		var nm := String(c.name)
		# [FIX 船桨轮] 只收轮自转节点(spin)本身 ——
		# ① WheelArch*(轮拱长板)也以 "Wheel" 开头,旧版 begins_with("Wheel")
		#   把两块 4.4m 侧轮拱板误收进 wheels,行驶时随轮轴旋转 = 两侧"船桨";
		# ② 递归查找会带出 spin 下的 *_Tire/*_Hub 子件(含 Blender 重名派生的
		#   *_Hub_001 变体),它们已随 spin 转动,再单独转一次 = 轮胎双倍转速。
		# 兼容 WheelFL(jeep) / Wheel0L~3R(apc/aa) 全部现有契约命名。
		if nm.begins_with("Wheel") and not nm.contains("Arch") \
				and not nm.contains("_Tire") and not nm.contains("_Hub"):
			wheels.append(c)
		elif nm.begins_with("Steer_"):
			fronts.append(c)
	if wheels.size() > 0:
		g.set_meta("wheels", wheels)
	if fronts.size() > 0:
		g.set_meta("front_wheels", fronts)
	if has_turret:
		# Turret/Cannon/Muzzle 是嵌套链(Turret/Cannon/Muzzle),必须递归查找 ——
		# 旧版 get_node 只查直接子节点,Cannon/Muzzle meta 永远接不上,
		# 炮塔俯仰/后坐/muzzle_world 一用就崩(无头跑实拍时实锤)
		for key in ["Turret", "Cannon", "Muzzle"]:
			var found := g.find_children(key, "Node3D", true, false)
			if found.size() > 0:
				g.set_meta(key.to_lower(), found[0])


## 吉普舱内件:方向盘(轮缘+三辐条+轮毂)
static func _jeep_cockpit(g: Node3D) -> void:
	var dark := _std(Color.html("#2a2e32"), 0.75, 0.0)
	# 仪表台:横贯车身,立在盆体顶面(0.91)上承住方向盘(旧版方向盘悬空)
	_add(g, _box(1.56, 0.38, 0.12, dark), 0, 1.10, -0.36)
	_add(g, _box(1.56, 0.05, 0.16, _std(Color.html("#1e2124"), 0.6, 0.2)), 0, 1.30, -0.37)
	# 驾驶/乘员座椅(桶椅):座垫落在盆体地板(0.91),靠背向后仰
	for sx in [-0.45, 0.45]:
		_add(g, _box(0.44, 0.10, 0.44, dark), sx, 0.96, 0.45)
		var back := _box(0.44, 0.44, 0.08, dark)
		back.position = Vector3(sx, 1.18, 0.66)
		back.rotation.x = 0.16
		g.add_child(back)
	# 方向盘: 第一人称双手抓盘点(GripL/GripR, 9 点 / 3 点方向)挂在盘节点下随盘倾斜。
	var sw := Node3D.new()
	sw.name = "SteerWheel"
	sw.position = Vector3(-0.45, 1.38, -0.28)
	sw.rotation.x = -0.62
	for gs in [1.0, -1.0]:
		var gm := Marker3D.new()
		gm.name = "GripR" if gs > 0.0 else "GripL"
		gm.position = Vector3(gs * 0.145, 0.0, 0.0)
		sw.add_child(gm)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.132
	tor.outer_radius = 0.158
	tor.rings = 8
	tor.ring_segments = 24
	rim.mesh = tor
	rim.material_override = dark
	rim.rotation.x = PI / 2.0
	sw.add_child(rim)
	for k in 3:
		var ang: float = k * TAU / 3.0
		var spoke := _box(0.024, 0.145, 0.014, dark)
		spoke.position = Vector3(sin(ang) * 0.0725, cos(ang) * 0.0725, 0)
		spoke.rotation.z = -ang
		sw.add_child(spoke)
	var sw_hub := _cyl(0.035, 0.035, 0.045, 8, dark)
	sw_hub.rotation.x = PI / 2.0
	sw.add_child(sw_hub)
	g.add_child(sw)


## 坦克舱内构(驾驶舱 + 随炮塔的炮手舱)
static func _tank_interior(g: Node3D) -> void:
	var turret: Node3D = g.get_meta("turret")
	var interior := Node3D.new()
	interior.name = "Interior"
	var in_dark := _std(Color.html("#1c1f22"), 0.85, 0.0)
	var in_metal := _std(Color.html("#2c3035"), 0.7, 0.3)
	_add(interior, _box(1.7, 0.06, 1.4, in_dark), 0, 1.545, 0.35)
	_add(interior, _box(1.7, 0.105, 0.05, in_dark), 0, 1.5225, -0.35)
	_add(interior, _box(1.7, 0.87, 0.08, in_dark), 0, 1.14, 1.25)
	_add(interior, _box(0.08, 0.87, 1.6, in_dark), -0.86, 1.14, 0.45)
	_add(interior, _box(0.08, 0.87, 1.6, in_dark), 0.86, 1.14, 0.45)
	_add(interior, _box(1.7, 0.06, 1.6, in_dark), 0, 0.73, 0.45)
	_add(interior, _box(1.6, 0.32, 0.6, in_dark), 0, 0.88, 0.05)
	_add(interior, _box(0.5, 0.03, 0.3, in_metal), -0.3, 1.08, -0.25)
	_crew_seat(interior, in_dark, 0.0, 0.78, 0.68, 0.9)
	_control_stick(interior, in_dark, -0.33, 0.93, 0.04, 1.0)
	_control_stick(interior, in_dark, 0.33, 0.93, 0.04, -1.0)
	_fcs_screen(interior, in_dark, Color(0.2, 0.85, 0.55), -0.30, 1.10, -0.16, 0.30, 0.15)
	_fcs_screen(interior, in_dark, Color(0.22, 0.68, 0.92), 0.32, 1.10, -0.16, 0.28, 0.15)
	_vision_frame(interior, in_dark, 0.0, 1.30, -0.40, 1.30, 0.52)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.32, 0.10, 0.55, 2.6)
	g.add_child(interior)
	g.set_meta("interior", interior)
	# 炮塔战斗室(随炮塔旋转):坐标为炮塔局部 —— 炮塔节点原点 (0,1.80,0.20),
	# 壳体 world 1.47..1.97;地板 world 1.49,顶棚 1.87 嵌进炮塔顶。
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _box(1.7, 0.05, 2.4, in_dark), 0, -0.285, 0.1)          # 地板
	_add(it, _box(1.7, 0.05, 1.3, in_dark), 0, 0.095, 0.65)          # 顶棚(只盖后半,前半敞开给目镜)
	_add(it, _box(1.6, 0.30, 0.06, in_dark), 0, -0.16, -1.20)        # 前墙(半高,眼位1.82看得过去)
	_add(it, _box(0.06, 0.42, 2.4, in_dark), -0.90, -0.10, 0.1)      # 左壁
	_add(it, _box(0.06, 0.42, 2.4, in_dark), 0.90, -0.10, 0.1)       # 右壁
	_add(it, _box(1.6, 0.42, 0.06, in_dark), 0, -0.10, 1.35)         # 尾墙
	_add(it, _cyl(0.045, 0.055, 0.40, 8, in_dark), 0.55, -0.05, 0.15).name = "Periscope"
	_crew_seat(it, in_dark, 0.40, -0.20, 0.55, 0.85)                 # 车长位(舱盖下)
	_crew_seat(it, in_dark, -0.40, -0.20, -0.45, 0.85)               # 炮手位
	_fcs_screen(it, in_dark, Color(0.24, 0.88, 0.58), 0.55, 0.02, -0.60, 0.30, 0.20)
	_fcs_screen(it, in_dark, Color(0.95, 0.62, 0.2), -0.58, 0.04, -0.55, 0.24, 0.15)
	_add(it, _box(0.46, 0.05, 0.42, in_metal), 0.0, -0.18, -0.65)
	_add(it, _box(0.10, 0.30, 0.34, in_dark), -0.72, -0.10, 1.05)    # 尾部弹架
	_control_stick(it, in_dark, 0.60, -0.18, -0.10, -1.0)
	_interior_light(it, Color(0.9, 0.38, 0.22), 0.0, 0.0, 0.4, 0.6, 2.8)
	turret.add_child(it)
	g.set_meta("interior_turret", it)


## APC 舱内构
static func _apc_interior(g: Node3D) -> void:
	var turret: Node3D = g.get_meta("turret")
	var interior := Node3D.new()
	interior.name = "Interior"
	var in_dark := _std(Color.html("#1c1f22"), 0.85, 0.0)
	var in_metal := _std(Color.html("#2c3035"), 0.7, 0.3)
	_add(interior, _box(1.7, 0.06, 1.8, in_dark), 0, 1.57, -1.2)
	_add(interior, _box(1.7, 0.05, 0.05, in_dark), 0, 1.575, -2.1)
	_add(interior, _box(1.7, 0.87, 0.08, in_dark), 0, 1.165, -0.35)
	_add(interior, _box(0.08, 0.87, 1.8, in_dark), -0.86, 1.165, -1.2)
	_add(interior, _box(0.08, 0.87, 1.8, in_dark), 0.86, 1.165, -1.2)
	_add(interior, _box(1.7, 0.06, 1.8, in_dark), 0, 0.73, -1.2)
	_add(interior, _box(1.6, 0.27, 0.6, in_dark), 0, 0.915, -1.9)
	_add(interior, _box(0.5, 0.03, 0.3, in_metal), -0.3, 1.09, -1.6)
	_crew_seat(interior, in_dark, 0.0, 0.75, -0.88, 0.9)
	var apc_wheel := _cyl(0.025, 0.025, 0.34, 8, in_dark)
	apc_wheel.position = Vector3(0, 1.0, -1.58)
	apc_wheel.rotation.x = -0.55
	interior.add_child(apc_wheel)
	_fcs_screen(interior, in_dark, Color(0.2, 0.82, 0.52), -0.28, 1.1, -1.52, 0.30, 0.15)
	_fcs_screen(interior, in_dark, Color(0.22, 0.66, 0.9), 0.30, 1.1, -1.52, 0.28, 0.15)
	_vision_frame(interior, in_dark, 0.0, 1.30, -2.08, 1.12, 0.42)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.35, -1.1, 0.55, 1.5)
	g.add_child(interior)
	g.set_meta("interior", interior)
	# 炮塔战斗室(随炮塔旋转):炮塔节点原点 (0,2.14,-0.30),壳体 world 2.07..2.40;
	# 地板 world 2.09,顶棚 2.30 嵌进炮塔顶 2.32。
	var it := Node3D.new()
	it.name = "InteriorTurret"
	# [FIX] 敞开炮座(同 AA 修法):眼位抬高到炮塔壳顶上方(world 2.46)后,
	# 内饰必须全部压到视线之下 —— 旧版顶棚(world 2.32)夹住眼位 2.24,
	# ADS 只剩 0.1m 视缝("看不清任何东西");尾墙/侧壁超壳体外露被误读为"车底还有个炮塔"
	_add(it, _box(1.2, 0.05, 1.5, in_dark), 0, -0.025, 0.05)         # 地板
	_add(it, _box(1.0, 0.10, 0.05, in_dark), 0, -0.08, -0.75)        # 前墙(压到腰下,world 2.00~2.10)
	_add(it, _box(0.05, 0.13, 1.5, in_dark), -0.60, -0.03, 0.05)     # 左壁(顶 world 2.18)
	_add(it, _box(0.05, 0.13, 1.5, in_dark), 0.60, -0.03, 0.05)      # 右壁
	_add(it, _box(1.0, 0.13, 0.05, in_dark), 0, -0.03, 0.80)         # 尾墙
	_add(it, _cyl(0.035, 0.045, 0.28, 8, in_dark), 0.30, -0.02, -0.5).name = "Periscope"
	_crew_seat(it, in_dark, 0.30, -0.02, -0.05, 0.8)
	_fcs_screen(it, in_dark, Color(0.24, 0.86, 0.56), 0.54, 0.06, -0.42, 0.26, 0.18)
	_control_stick(it, in_dark, 0.56, -0.02, 0.10, -1.0)
	_interior_light(it, Color(0.9, 0.4, 0.22), 0.0, 0.10, 0.35, 0.5, 1.5)
	turret.add_child(it)
	g.set_meta("interior_turret", it)


## AA 舱内构
static func _aa_interior(g: Node3D) -> void:
	var turret: Node3D = g.get_meta("turret")
	var interior := Node3D.new()
	interior.name = "Interior"
	var in_dark := _std(Color.html("#1c1f22"), 0.85, 0.0)
	var in_metal := _std(Color.html("#2c3035"), 0.7, 0.3)
	_add(interior, _box(1.6, 0.06, 1.8, in_dark), 0, 1.495, -1.25)
	_add(interior, _box(1.6, 0.045, 0.05, in_dark), 0, 1.5025, -2.15)
	_add(interior, _box(1.6, 0.82, 0.08, in_dark), 0, 1.115, -0.4)
	_add(interior, _box(0.08, 0.82, 1.8, in_dark), -0.81, 1.115, -1.25)
	_add(interior, _box(0.08, 0.82, 1.8, in_dark), 0.81, 1.115, -1.25)
	_add(interior, _box(1.6, 0.06, 1.8, in_dark), 0, 0.7, -1.25)
	_add(interior, _box(1.5, 0.27, 0.6, in_dark), 0, 0.895, -1.8)
	_add(interior, _box(0.5, 0.03, 0.3, in_metal), -0.3, 1.07, -1.5)
	_crew_seat(interior, in_dark, 0.0, 0.72, -0.82, 0.9)
	var aa_wheel := _cyl(0.024, 0.024, 0.34, 8, in_dark)
	aa_wheel.position = Vector3(0, 0.98, -1.56)
	aa_wheel.rotation.x = -0.55
	interior.add_child(aa_wheel)
	_fcs_screen(interior, in_dark, Color(0.2, 0.85, 0.55), -0.27, 1.08, -1.48, 0.30, 0.15)
	_fcs_screen(interior, in_dark, Color(0.9, 0.6, 0.2), 0.30, 1.08, -1.48, 0.26, 0.15)
	_vision_frame(interior, in_dark, 0.0, 1.26, -2.14, 1.02, 0.46)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.34, -1.05, 0.55, 2.6)
	# 观察位车顶机枪(战地式):盆环 + 立柱 + 随观察方向旋转的机枪座
	# (货斗前右角,避开旋转平台半径;controller 驱动 meta "observer_mg" 转向)
	var mg_ring := _cyl(0.16, 0.18, 0.04, 12, in_metal)
	mg_ring.position = Vector3(0.62, 1.53, -0.55)
	interior.add_child(mg_ring)
	var mg_post := _cyl(0.025, 0.03, 0.42, 8, in_dark)
	mg_post.position = Vector3(0.62, 1.75, -0.55)
	interior.add_child(mg_post)
	var mg_pivot := Node3D.new()
	mg_pivot.name = "ObserverMg"
	mg_pivot.position = Vector3(0.62, 1.96, -0.55)
	interior.add_child(mg_pivot)
	_add(mg_pivot, _box(0.09, 0.10, 0.52, in_dark), 0, 0, -0.10)
	_add(mg_pivot, _cyl(0.018, 0.018, 0.46, 8, in_dark), 0, 0.01, -0.55).name = "MgBarrel"
	_add(mg_pivot, _box(0.07, 0.12, 0.10, in_dark), 0, -0.10, 0.06)
	_add(mg_pivot, _box(0.10, 0.09, 0.16, in_dark), 0.0, -0.11, -0.18)
	g.set_meta("observer_mg", mg_pivot)
	g.add_child(interior)
	g.set_meta("interior", interior)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	# 敞开炮座(无顶棚):平台原点 (0,1.68,0.85),平台顶 world 1.85;
	# 地板 world ~1.85,矮围壁顶 world 2.145(低于炮手眼位 2.35,越过炮盾 2.32)
	_add(it, _box(1.5, 0.05, 1.7, in_dark), 0, 0.165, 0.0)
	_add(it, _box(1.4, 0.30, 0.05, in_dark), 0, 0.315, -0.80)
	_add(it, _box(0.05, 0.30, 1.7, in_dark), -0.70, 0.315, 0.0)
	_add(it, _box(0.05, 0.30, 1.7, in_dark), 0.70, 0.315, 0.0)
	_add(it, _box(1.4, 0.30, 0.05, in_dark), 0, 0.315, 0.80)
	_add(it, _cyl(0.04, 0.05, 0.4, 8, in_dark), 0.42, 0.30, 0.55).name = "Periscope"
	_crew_seat(it, in_dark, 0.32, 0.22, 0.0, 0.82)
	_crew_seat(it, in_dark, -0.48, 0.34, -0.12, 0.78)
	_fcs_screen(it, in_dark, Color(0.18, 0.9, 0.5), 0.58, 0.42, -0.34, 0.34, 0.24)
	_fcs_screen(it, in_dark, Color(1.0, 0.55, 0.18), -0.56, 0.44, -0.30, 0.24, 0.16)
	_control_stick(it, in_dark, 0.50, 0.30, -0.46, -1.0)
	_control_stick(it, in_dark, 0.18, 0.30, -0.46, 1.0)
	_add(it, _box(0.36, 0.05, 0.30, in_metal), 0.32, 0.12, -0.50)
	_interior_light(it, Color(0.9, 0.42, 0.2), 0.0, 0.62, 0.35, 0.55, 2.6)
	turret.add_child(it)
	g.set_meta("interior_turret", it)

