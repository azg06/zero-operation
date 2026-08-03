class_name AircraftModels
## 空中载具建模(对应 aircraft.js 的 buildHeli/buildJet)

static func _std(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func _basic(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
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


## 武装直升机
static func build_heli(team: String) -> Node3D:
	var g := Node3D.new()
	g.name = "Heli"
	var is_us: bool = team == "us"
	var body := _std(Color.html("#4a5240") if is_us else Color.html("#54423c"), 0.55, 0.4)
	var dark := _std(Color.html("#22262a"), 0.7, 0.5)
	var glass := _std(Color(0.48, 0.69, 0.85, 0.6), 0.15, 0.85)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var accent := _basic(Color.html("#00ff88") if is_us else Color.html("#ff5500"))
	_add(g, _box(1.7, 1.5, 4.4, body), 0, 0, 0)
	var canopy := _add(g, _box(1.4, 1.0, 1.6, glass), 0, 0.35, -1.9)
	canopy.rotation.x = 0.25
	_add(g, _box(1.72, 0.18, 0.5, accent), 0, -0.2, -0.6)
	_add(g, _box(0.55, 0.55, 3.8, body), 0, 0.25, 3.6)
	_add(g, _box(0.14, 1.2, 0.7, body), 0, 0.9, 5.2)
	var tail_rotor := Node3D.new()
	tail_rotor.position = Vector3(0.35, 0.85, 5.2)
	for r in [0.0, PI / 2.0]:
		var b := _box(0.06, 1.4, 0.14, dark)
		b.rotation.x = r
		tail_rotor.add_child(b)
	g.add_child(tail_rotor)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.0, -0.2)
	for r in [0.0, PI / 2.0]:
		var b := _box(9.6, 0.06, 0.42, dark)
		b.rotation.y = r
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		rotor.add_child(b)
	_add(g, _cyl(0.14, 0.2, 0.7, 8, dark), 0, 0.75, -0.2)
	g.add_child(rotor)
	_add(g, _box(3.6, 0.14, 0.8, body), 0, -0.1, -0.4)
	for sx in [-1.5, 1.5]:
		_add(g, _cyl(0.28, 0.28, 1.1, 8, dark), sx, -0.35, -0.4).rotation.x = PI / 2.0
	for sx in [-0.8, 0.8]:
		_add(g, _box(0.12, 0.12, 3.2, dark), sx, -1.05, 0)
		_add(g, _box(0.1, 0.5, 0.1, dark), sx, -0.8, -1.1)
		_add(g, _box(0.1, 0.5, 0.1, dark), sx, -0.8, 1.1)
	_add(g, _cyl(0.07, 0.09, 1.4, 8, dark), 0, -0.55, -2.6).rotation.x = PI / 2.0
	g.set_meta("rotor", rotor)
	g.set_meta("tail_rotor", tail_rotor)
	return g


## 战斗机
static func build_jet(team: String) -> Node3D:
	var g := Node3D.new()
	g.name = "Jet"
	var is_us: bool = team == "us"
	var body := _std(Color.html("#6a7078") if is_us else Color.html("#6e5a50"), 0.4, 0.6)
	var glass := _std(Color(0.48, 0.69, 0.85, 0.65), 0.1, 0.9)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var accent := _basic(Color.html("#00ff88") if is_us else Color.html("#ff5500"))
	var fus := _add(g, _cyl(0.65, 0.75, 6.4, 10, body), 0, 0, 0)
	fus.rotation.x = PI / 2.0
	var nose_mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.62
	cone.height = 2.2
	cone.radial_segments = 10
	nose_mi.mesh = cone
	nose_mi.material_override = body
	_add(g, nose_mi, 0, 0, -4.3)
	nose_mi.rotation.x = -PI / 2.0
	var canopy_mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.55
	sph.height = 1.1
	sph.radial_segments = 10
	sph.rings = 6
	canopy_mi.mesh = sph
	canopy_mi.material_override = glass
	_add(g, canopy_mi, 0, 0.55, -1.6)
	canopy_mi.scale = Vector3(0.8, 0.7, 1.6)
	for sx in [-1.0, 1.0]:
		var wing := _add(g, _box(2.8, 0.08, 1.6, body), sx * 1.9, 0, 0.6)
		wing.rotation.y = sx * 0.5
		var tail := _add(g, _box(0.1, 1.1, 0.9, body), sx * 0.6, 0.6, 2.8)
		tail.rotation.z = sx * 0.35
		var h_tail := _add(g, _box(1.4, 0.07, 0.8, body), sx * 0.9, 0.1, 2.9)
		h_tail.rotation.y = sx * 0.3
	_add(g, _box(0.7, 0.06, 2.4, accent), 0, 0.68, 0.4)
	# 尾喷口辉光
	var burner_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	disc.radial_segments = 12
	burner_mi.mesh = disc
	var burner_mat := _basic(Color(0.4, 0.75, 1, 0.9))
	burner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burner_mi.material_override = burner_mat
	_add(g, burner_mi, 0, 0, 3.25)
	burner_mi.rotation.y = PI
	g.set_meta("burner", burner_mi)
	return g
