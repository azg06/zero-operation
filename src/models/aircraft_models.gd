class_name AircraftModels
## 空中载具建模(对应 aircraft.js 的 buildHeli/buildJet)
## [3A] GLB 外部建模管线(build_aircraft_batch.py)优先,缺失回落旧 box 堆。
## 契约节点:Rotor/TailRotor(动画)/BurnerDisc(加力辉光)/Muzzle。

const AC_GLB := "res://models/aircraft/"


static func build_heli(team: String) -> Node3D:
	var g := _load_ac("heli", "Heli", team)
	if g == null:
		return _legacy_build_heli(team)
	return g


static func build_jet(team: String) -> Node3D:
	var g := _load_ac("jet", "Jet", team)
	if g == null:
		return _legacy_build_jet(team)
	return g


static func _load_ac(id: String, root_name: String, team: String) -> Node3D:
	var path := AC_GLB + id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[aircraft] GLB 缺失,回落 box 堆: " + path)
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var g: Node3D = ps.instantiate()
	g.name = root_name
	_air_mats(g, team)
	# 契约节点接线(BurnerDisc 是 MeshInstance,Rotor/TailRotor/Muzzle 是空节点 Node3D)
	for pair in [["Rotor", "rotor"], ["TailRotor", "tail_rotor"]]:
		var found := g.find_children(pair[0], "Node3D", true, false)
		if found.size() > 0:
			g.set_meta(pair[1], found[0])
	var burner := g.find_children("BurnerDisc", "MeshInstance3D", true, false)
	if burner.size() > 0:
		g.set_meta("burner", burner[0])
	var muzzle := g.find_children("Muzzle", "Node3D", true, false)
	if muzzle.size() > 0:
		g.set_meta("muzzle", muzzle[0])
	return g


static func _ac_vstd(color: Color, rough: float, metal: float, tex: String, nor: String, tiling := 2.5) -> StandardMaterial3D:
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


static func _tex(p: String) -> Texture2D:
	return load("res://textures/" + p)


## 空中载具外表面材质:零件名 contains 匹配(与 build_aircraft_batch.py 命名对齐)。
## 机体漆 gun_metal 三平面(gun_poly 黑聚合物纹理会把漆色乘成近黑,实车轮已踩坑)。
static func _air_mats(g: Node3D, team: String) -> void:
	var is_us: bool = team == "us"
	var paint_base := Color.html("#5c6850") if is_us else Color.html("#6a5844")
	if g.name == "Jet":
		paint_base = Color.html("#66707c") if is_us else Color.html("#6e5a50")
	var ptex := "gun_metal_diff.jpg"
	var pnor := "gun_metal_nor.jpg"
	var paint := [
		_ac_vstd(paint_base.lightened(0.22), 0.82, 0.08, ptex, pnor, 2.5),
		_ac_vstd(paint_base.lightened(0.28), 0.8, 0.08, ptex, pnor, 2.5),
		_ac_vstd(paint_base.lightened(0.14), 0.85, 0.08, ptex, pnor, 2.5),
	]
	var dark := _ac_vstd(Color.html("#26292c"), 0.6, 0.4, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 3.0)
	var blade := _ac_vstd(Color.html("#1c1e20"), 0.9, 0.1, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 4.0)
	var metal := _ac_vstd(Color.html("#3c4044"), 0.45, 0.85, "gun_metal_diff.jpg", "gun_metal_nor.jpg", 5.0)
	var glass := _ac_vstd(Color(0.55, 0.68, 0.8, 0.25), 0.12, 0.5, "gun_chrome_diff.jpg", "gun_chrome_nor.jpg", 2.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var accent := _basic(Color.html("#00ff88") if is_us else Color.html("#ff5500"))
	var burner_m := _basic(Color(0.45, 0.78, 1.0, 0.9))
	burner_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		var picked: Material
		if nm.contains("Glass"):
			picked = glass
		elif nm.contains("Burner"):
			picked = burner_m
		elif nm.contains("Stripe"):
			picked = accent
		elif nm.contains("Nozzle") or nm.contains("Shaft") or nm.contains("Pitot"):
			picked = metal
		elif nm.contains("Blade") or nm.contains("Tire") or nm.contains("Antenna") or nm.contains("Wheel"):
			picked = blade
		elif nm.contains("Nose") or nm.contains("Lip") or nm.contains("Bow") or nm.contains("Hub") \
				or nm.contains("Grip") or nm.contains("Barrel") or nm.contains("Turret") or nm.contains("Lens") \
				or nm.contains("Gear") or nm.contains("Rail") or nm.contains("Pylon") or nm.contains("Fin"):
			picked = dark
		else:
			picked = paint[absi(nm.hash()) % paint.size()]
		mi.material_override = picked


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
static func _legacy_build_heli(team: String) -> Node3D:
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
static func _legacy_build_jet(team: String) -> Node3D:
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
