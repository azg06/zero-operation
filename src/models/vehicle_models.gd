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


## 军用吉普
static func build_jeep() -> Node3D:
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
static func build_tank() -> Node3D:
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
	var glacis := _add(g, _box(2.5, 0.7, 1.2, camo), 0, 1.05, -2.6)
	glacis.rotation.x = 0.5
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
	_add(turret, _box(0.08, 0.08, 0.9, dark), 0.5, 0.55, -0.3)
	g.add_child(turret)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.22, -4.6)
	turret.add_child(muzzle)
	g.set_meta("turret", turret)
	g.set_meta("cannon", cannon)
	g.set_meta("muzzle", muzzle)
	return g


## 轮式装甲步战车(APC,25mm 机炮)
static func build_apc() -> Node3D:
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
	var nose := _add(g, _box(2.2, 0.75, 1.1, camo), 0, 1.05, -3.05)
	nose.rotation.x = 0.55
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
	return g


## 自行防空炮车(AA,四联高射机炮)
static func build_aa() -> Node3D:
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
	var nose := _add(g, _box(2.1, 0.6, 1.0, camo), 0, 1.0, -2.7)
	nose.rotation.x = 0.5
	_add(g, _box(1.7, 0.6, 1.4, camo), 0, 1.8, -1.5)
	var win_mat := _plain(Color.html("#20262c"), 0.2, 0.6)
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
	return g
