# -*- coding: utf-8 -*-
"""vehicle_models.gd 载具 GLB 管线补丁:改名 legacy + 追加加载器/舱内构"""
import io

P = "E:/工作目录2/zero/steel_frontline_godot/src/models/vehicle_models.gd"
s = io.open(P, encoding="utf-8").read()
s = s.replace("\r\n", "\n")

# ---- 1) 旧构建函数改名 legacy ----
for fn, car in (("build_jeep", "Jeep"), ("build_tank", "Tank"), ("build_apc", "Apc"), ("build_aa", "Aa")):
    old = 'static func %s() -> Node3D:\n\tvar g := Node3D.new()\n\tg.name = "%s"' % (fn, car)
    new = 'static func _legacy_%s() -> Node3D:\n\tvar g := Node3D.new()\n\tg.name = "%s"' % (fn, car)
    n = s.count(old)
    print("rename %-12s count=%d" % (fn, n))
    if n == 1 and ("_legacy_%s" % fn) not in s:
        s = s.replace(old, new)

LOADER = '''

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
	_tank_interior(g)
	_veh_wire(g, true)
	return g


static func build_apc() -> Node3D:
	var g := _load_veh("apc", "Apc")
	if g == null:
		return _legacy_build_apc()
	_apc_interior(g)
	_veh_wire(g, true)
	return g


static func build_aa() -> Node3D:
	var g := _load_veh("aa", "Aa")
	if g == null:
		return _legacy_build_aa()
	_aa_interior(g)
	_veh_wire(g, true)
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


static func _veh_mats(g: Node3D, id: String) -> void:
	var camo: Material
	match id:
		"jeep":
			camo = _std(Color.html("#5a6348"), 0.55, 0.35)
		"tank":
			camo = _std(Color.html("#4e5a42"), 0.7, 0.3)
		"apc":
			camo = _std(Color.html("#55604a"), 0.6, 0.35)
		_:
			camo = _std(Color.html("#5c5a48"), 0.65, 0.3)
	var dark := _std(Color.html("#24282c"), 0.85, 0.0)
	var track := _std(Color.html("#3a3c38"), 0.9, 0.4, true)
	var tire := _plain(Color.html("#14161a"), 0.95)
	var hub := _plain(Color.html("#5a5c60"), 0.4, 0.7)
	var chrome := _plain(Color.html("#c8ccd0"), 0.3, 0.8)
	var glass := _plain(Color(0.16, 0.2, 0.24, 0.4), 0.15, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.begins_with("Track") or nm.begins_with("RoadWheel") or nm.begins_with("Sprocket") or nm.begins_with("Idler"):
			mi.material_override = track
		elif nm.begins_with("Tire"):
			mi.material_override = tire
		elif nm.begins_with("Hub") or nm.begins_with("SpareWheel"):
			mi.material_override = hub
		elif nm.begins_with("Glass") or nm.begins_with("WipeGlass"):
			mi.material_override = glass
		elif nm.begins_with("Light") or nm.begins_with("Head"):
			mi.material_override = chrome
		elif nm.begins_with("Barrel") or nm.begins_with("Brake") or nm.begins_with("Breech") or nm.begins_with("Receiver") or nm.begins_with("Muzzle") or nm.begins_with("Smoke") or nm.begins_with("Antenna") or nm.begins_with("Radar") or nm.begins_with("Grille") or nm.begins_with("Frame") or nm.begins_with("Cage") or nm.begins_with("Bumper") or nm.begins_with("Driveshaft") or nm.begins_with("Mg") or nm.begins_with("CannonTube") or nm.begins_with("Peri"):
			mi.material_override = dark
		else:
			mi.material_override = camo


## 接线契约节点:turret/cannon/muzzle/wheels/front_wheels
static func _veh_wire(g: Node3D, has_turret: bool) -> void:
	var wheels: Array = []
	var fronts: Array = []
	for c in g.find_children("*", "Node3D", true, false):
		var nm := String(c.name)
		if nm.begins_with("Wheel"):
			wheels.append(c)
		elif nm.begins_with("Steer_"):
			fronts.append(c)
	if wheels.size() > 0:
		g.set_meta("wheels", wheels)
	if fronts.size() > 0:
		g.set_meta("front_wheels", fronts)
	if has_turret:
		for key in ["Turret", "Cannon", "Muzzle"]:
			var nd: Node3D = g.get_node_or_null(NodePath(key))
			if nd != null:
				g.set_meta(key.to_lower(), nd)


## 吉普舱内件:方向盘(轮缘+三辐条+轮毂)
static func _jeep_cockpit(g: Node3D) -> void:
	var dark := _std(Color.html("#2a2e32"), 0.75, 0.0)
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
	_vision_frame(interior, in_dark, 0.0, 1.28, -0.34, 1.10, 0.38)
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.32, 0.10, 0.55, 2.6)
	g.add_child(interior)
	g.set_meta("interior", interior)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _cyl(0.045, 0.055, 0.45, 8, in_dark), 0.35, 0.78, -0.6).name = "Periscope"
	_add(it, _box(0.5, 0.4, 0.06, in_dark), 0, 0.2, 1.5)
	_add(it, _box(0.06, 0.4, 1.2, in_dark), -0.95, 0.25, 0.2)
	_add(it, _box(0.06, 0.4, 1.2, in_dark), 0.95, 0.25, 0.2)
	_add(it, _box(0.7, 0.08, 0.7, in_dark), 0, 0.62, 0.4)
	_crew_seat(it, in_dark, 0.34, 0.10, 0.02, 0.85)
	_crew_seat(it, in_dark, -0.42, 0.10, 0.10, 0.85)
	_fcs_screen(it, in_dark, Color(0.24, 0.88, 0.58), 0.58, 0.34, -0.44, 0.30, 0.20)
	_fcs_screen(it, in_dark, Color(0.95, 0.62, 0.2), -0.60, 0.36, -0.38, 0.24, 0.15)
	_add(it, _box(0.46, 0.05, 0.42, in_metal), 0.0, 0.10, -0.55)
	_add(it, _box(0.10, 0.30, 0.34, in_dark), -0.72, 0.16, 1.05)
	_control_stick(it, in_dark, 0.66, 0.10, 0.18, -1.0)
	_interior_light(it, Color(0.9, 0.38, 0.22), 0.0, 0.55, 0.55, 0.6, 2.8)
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
	_interior_light(interior, Color(0.95, 0.75, 0.45), 0.0, 1.35, -1.1, 0.55, 2.6)
	g.add_child(interior)
	g.set_meta("interior", interior)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _cyl(0.035, 0.045, 0.4, 8, in_dark), 0.3, 0.7, -0.55).name = "Periscope"
	_add(it, _box(0.4, 0.35, 0.05, in_dark), 0, 0.15, 1.3)
	_add(it, _box(0.05, 0.35, 1.0, in_dark), -0.62, 0.2, 0.1)
	_add(it, _box(0.05, 0.35, 1.0, in_dark), 0.62, 0.2, 0.1)
	_crew_seat(it, in_dark, 0.30, 0.04, -0.02, 0.8)
	_fcs_screen(it, in_dark, Color(0.24, 0.86, 0.56), 0.54, 0.28, -0.38, 0.26, 0.18)
	_control_stick(it, in_dark, 0.58, 0.04, 0.12, -1.0)
	_interior_light(it, Color(0.9, 0.4, 0.22), 0.0, 0.45, 0.4, 0.5, 2.4)
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
	g.add_child(interior)
	g.set_meta("interior", interior)
	var it := Node3D.new()
	it.name = "InteriorTurret"
	_add(it, _cyl(0.04, 0.05, 0.4, 8, in_dark), 0.3, 0.8, -0.5).name = "Periscope"
	_add(it, _box(0.06, 0.5, 1.4, in_dark), -0.75, 0.25, 0.2)
	_add(it, _box(0.06, 0.5, 1.4, in_dark), 0.75, 0.25, 0.2)
	_add(it, _box(0.6, 0.45, 0.06, in_dark), 0, 0.2, 1.3)
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
'''

if "static func build_jeep" not in s:
    s = s.rstrip() + "\n" + LOADER + "\n"
    print("loader appended")
io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("done, len =", len(s))
