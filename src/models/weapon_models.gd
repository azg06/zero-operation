class_name WeaponModels
## 精化武器建模(低模多部件:锥形枪管/斜置握把/导轨/弯弹匣/可见拉机柄)
## 所有模型:原点位于握把处,枪管朝 -Z,机械瞄具在 y≈0.075 处

static var _mat: Dictionary = {}


static func _tex(file: String, _srgb := true) -> Texture2D:
	var t: Texture2D = load("res://textures/" + file)
	return t


static func _std(color: Color, rough: float, metal: float, tex: String = "", nor: String = "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_repeat = true
	if tex != "":
		m.albedo_texture = _tex(tex)
	if nor != "":
		m.normal_enabled = true
		m.normal_texture = _tex(nor, false)
	return m


static func MAT() -> Dictionary:
	if _mat.is_empty():
		_mat["metal"] = _std(Color.html("#9aa0a8"), 0.45, 0.4, "metal_plate_diff.jpg", "metal_plate_nor.jpg")
		_mat["dark"] = _std(Color.html("#5a5e64"), 0.6, 0.3, "metal_plate_diff.jpg", "metal_plate_nor.jpg")
		_mat["poly"] = _std(Color.html("#3e4248"), 0.85, 0.05, "metal_plate_diff.jpg", "metal_plate_nor.jpg")
		_mat["tan"] = _std(Color.html("#b09a78"), 0.75, 0.1, "metal_plate_diff.jpg", "metal_plate_nor.jpg")
		_mat["wood"] = _std(Color.html("#a87848"), 0.75, 0.0, "plywood_diff.jpg", "plywood_nor.jpg")
		_mat["olive"] = _std(Color.html("#6a7458"), 0.75, 0.15, "metal_plate_diff.jpg", "metal_plate_nor.jpg")
		var lens := StandardMaterial3D.new()
		lens.albedo_color = Color.html("#3a6a9a")
		lens.roughness = 0.15
		lens.metallic = 0.9
		lens.emission_enabled = true
		lens.emission = Color.html("#0a2a4a")
		lens.emission_energy_multiplier = 0.6
		_mat["lens"] = lens
		_mat["brass"] = _std(Color.html("#d0b070"), 0.4, 0.6, "rusty_metal_diff.jpg", "rusty_metal_nor.jpg")
		_mat["chrome"] = _std(Color.html("#d8dde2"), 0.18, 0.95, "metal_plate_diff.jpg", "metal_plate_nor.jpg")
	return _mat


static func box(w: float, h: float, d: float, x: float, y: float, z: float, mat_name := "metal") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = MAT()[mat_name]
	mi.position = Vector3(x, y, z)
	return mi


static func cyl(r1: float, r2: float, length: float, x: float, y: float, z: float,
		mat_name := "metal", axis := "z") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r2
	cm.height = length
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = MAT()[mat_name]
	if axis == "z":
		mi.rotation.x = PI / 2.0
	elif axis == "x":
		mi.rotation.z = PI / 2.0
	mi.position = Vector3(x, y, z)
	return mi


## 顶部导轨(分段齿条)
static func _rail(g: Node3D, y: float, z0: float, z1: float, mat := "dark") -> void:
	var step := 0.045
	var n: int = maxi(1, int((z1 - z0) / step))
	for i in n:
		g.add_child(box(0.026, 0.011, step * 0.55, 0, y, z0 + i * step, mat))


## 扳机护圈 + 扳机
static func _trigger(g: Node3D, y: float, z: float, mat := "dark") -> void:
	g.add_child(box(0.006, 0.006, 0.05, -0.02, y - 0.012, z, mat))          # 左护圈
	g.add_child(box(0.006, 0.006, 0.05, 0.02, y - 0.012, z, mat))           # 右护圈
	g.add_child(box(0.044, 0.006, 0.006, 0, y - 0.03, z + 0.022, mat))      # 前护圈
	var trig := box(0.008, 0.028, 0.006, 0, y - 0.02, z - 0.005, mat)
	trig.rotation.x = 0.2
	g.add_child(trig)                                                          # 扳机


## 拉机柄(可见小部件,供换弹上膛动画驱动;meta "bolt")
static func _bolt(g: Node3D, x: float, y: float, z: float, mat := "dark") -> MeshInstance3D:
	var b := Node3D.new()
	b.position = Vector3(x, y, z)
	var handle := cyl(0.007, 0.007, 0.028, 0, 0, 0, mat, "x")
	b.add_child(handle)
	var knob := box(0.016, 0.014, 0.03, 0.018, 0, 0, mat)
	b.add_child(knob)
	g.add_child(b)
	g.set_meta("bolt", b)
	return handle


## 斜置握把
static func _grip(w: float, h: float, d: float, x: float, y: float, z: float, mat := "poly", tilt := 0.32) -> MeshInstance3D:
	var mi := box(w, h, d, x, y, z, mat)
	mi.rotation.x = tilt
	return mi


## 弯弹匣(AK 弧度:三段渐变,供 "mag" meta)
static func _curved_mag(g: Node3D, w: float, mat := "brass") -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, -0.05, -0.1)   # 上抬贴合机匣底(-0.02),消除弹匣悬浮
	var s1 := box(w, 0.07, 0.055, 0, -0.01, 0.005, mat); s1.rotation.x = 0.1
	root.add_child(s1)
	var s2 := box(w * 0.94, 0.065, 0.05, 0, -0.075, -0.012, mat); s2.rotation.x = 0.34
	root.add_child(s2)
	var s3 := box(w * 0.86, 0.05, 0.045, 0, -0.128, -0.045, mat); s3.rotation.x = 0.62
	root.add_child(s3)
	g.add_child(root)
	g.set_meta("mag", root)
	return root


## 全息瞄准镜配件(EOTech 风格:护罩 + 半透窗口 + 免光照全息分划)
static func _holo(g: Node3D, y: float, z: float) -> void:
	# 增高底座(向下延伸贴合机匣防悬浮;顶端低于视窗下沿,不挡瞄线)
	g.add_child(box(0.024, 0.024, 0.05, 0, y - 0.028, z, "dark"))
	g.add_child(box(0.0032, 0.04, 0.065, -0.016, y - 0.002, z, "dark"))
	g.add_child(box(0.0032, 0.04, 0.065, 0.016, y - 0.002, z, "dark"))
	g.add_child(box(0.035, 0.0032, 0.065, 0, y + 0.017, z, "dark"))
	var win := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(0.027, 0.03)
	win.mesh = wp
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color(0.55, 0.75, 0.8, 0.14)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	win.material_override = wm
	win.position = Vector3(0, y, z)
	g.add_child(win)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1, 0.12, 0.1)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.0058
	tm.outer_radius = 0.0068
	tm.ring_segments = 24
	tm.rings = 8
	ring.mesh = tm
	ring.material_override = rm
	ring.rotation.x = PI / 2.0
	ring.position = Vector3(0, y, z + 0.0008)
	g.add_child(ring)
	var dot := MeshInstance3D.new()
	var dp := PlaneMesh.new()
	dp.size = Vector2(0.0022, 0.0022)
	dot.mesh = dp
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1, 0.12, 0.1)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dot.material_override = dm
	dot.position = Vector3(0, y, z + 0.0008)
	g.add_child(dot)


## 狙击镜(长筒 + 前后镜片,scope 武器用)
static func _scope(g: Node3D, y: float, z: float) -> void:
	g.add_child(cyl(0.021, 0.021, 0.05, 0, y - 0.028, z + 0.03, "dark"))   # 前支架
	g.add_child(cyl(0.021, 0.021, 0.05, 0, y - 0.028, z - 0.09, "dark"))  # 后支架
	var tube := cyl(0.024, 0.027, 0.22, 0, y, z - 0.03, "dark")
	g.add_child(tube)                                                        # 镜筒
	var eye := cyl(0.019, 0.019, 0.012, 0, y, z + 0.085, "lens")
	g.add_child(eye)                                                         # 目镜
	var obj := cyl(0.03, 0.027, 0.03, 0, y, z - 0.14, "lens")
	g.add_child(obj)                                                         # 物镜
	g.add_child(cyl(0.005, 0.005, 0.02, 0, y + 0.03, z - 0.03, "dark", "y"))  # 调节钮


## ============ 各武器构建 ============
static func _build(id: String, g: Node3D) -> void:
	match id:
		"m4":
			# 机匣 + 上机匣(前伸至护木中段,承接导轨)
			g.add_child(box(0.052, 0.075, 0.34, 0, 0.015, -0.06))
			g.add_child(box(0.048, 0.028, 0.44, 0, 0.062, -0.14, "dark"))
			# 护木(圆柱+导轨)
			g.add_child(cyl(0.026, 0.03, 0.3, 0, 0.02, -0.4))
			_rail(g, 0.082, -0.2, -0.36)   # 导轨贴合上机匣顶面(0.076)
			# 枪管 + 枪口制退器
			g.add_child(cyl(0.011, 0.013, 0.24, 0, 0.024, -0.68))
			g.add_child(cyl(0.017, 0.019, 0.05, 0, 0.024, -0.79, "dark"))
			# 枪托(斜置) + 托垫
			g.add_child(_grip(0.042, 0.09, 0.19, 0, -0.005, 0.17, "poly", 0.12))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.27, "dark"))
			# 握把(斜) + 扳机
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.085, 0.04, "poly", 0.38))
			_trigger(g, -0.04, 0.01)
			# 弹匣(微弯)
			var mag := box(0.036, 0.13, 0.06, 0, -0.105, -0.09, "dark")
			mag.rotation.x = 0.14
			g.add_child(mag); g.set_meta("mag", mag)
			# 抛壳窗 + 拉机柄(右后)
			g.add_child(box(0.004, 0.02, 0.05, 0.027, 0.03, -0.06, "dark"))
			_bolt(g, 0.03, 0.045, 0.06)
			# 全息镜
			_holo(g, 0.108, -0.1)
			# 前准星
			g.add_child(box(0.01, 0.03, 0.01, 0, 0.055, -0.55, "dark"))
		"ak":
			g.add_child(box(0.054, 0.075, 0.34, 0, 0.015, -0.05))
			g.add_child(box(0.05, 0.024, 0.3, 0, 0.058, -0.07, "dark"))
			# 木护木(锥形,前伸贴合机匣,消除 -0.22 ~ -0.26 缝隙)
			g.add_child(cyl(0.024, 0.03, 0.28, 0, 0.02, -0.36, "wood"))
			g.add_child(box(0.048, 0.05, 0.12, 0, 0.05, -0.32, "wood"))
			# 枪管 + 准星座 + 消焰器
			g.add_child(cyl(0.012, 0.014, 0.34, 0, 0.028, -0.63))
			g.add_child(box(0.014, 0.05, 0.014, 0, 0.055, -0.56, "dark"))
			g.add_child(cyl(0.016, 0.019, 0.05, 0, 0.028, -0.81, "dark"))   # 消焰器贴合枪管尾端
			# 木枪托(斜) + 握把
			g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.01, 0.18, "wood", 0.16))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.085, 0.045, "wood", 0.42))
			_trigger(g, -0.04, 0.02)
			# 弯弹匣(前挂后卡)
			_curved_mag(g, 0.038)
			# 拉机柄(右侧大柄)
			_bolt(g, 0.032, 0.035, -0.02)
			_holo(g, 0.104, -0.06)
		"scar":
			g.add_child(box(0.052, 0.08, 0.36, 0, 0.018, -0.07, "tan"))
			g.add_child(box(0.048, 0.026, 0.48, 0, 0.065, -0.2, "dark"))   # 上机匣前伸承接导轨
			_rail(g, 0.084, -0.26, -0.44)   # 导轨贴合上机匣顶面(0.078)
			g.add_child(cyl(0.025, 0.029, 0.28, 0, 0.02, -0.42, "tan"))
			g.add_child(cyl(0.011, 0.013, 0.24, 0, 0.024, -0.7))
			g.add_child(cyl(0.016, 0.019, 0.05, 0, 0.024, -0.81, "dark"))
			# 折叠枪托(带铰链)
			g.add_child(box(0.02, 0.06, 0.05, 0, 0.0, 0.13, "dark"))
			g.add_child(_grip(0.04, 0.085, 0.19, 0, -0.005, 0.21, "tan", 0.1))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.088, 0.04, "dark", 0.36))
			_trigger(g, -0.042, 0.01)
			var mag_s := box(0.038, 0.11, 0.062, 0, -0.1, -0.1, "tan")
			mag_s.rotation.x = 0.1
			g.add_child(mag_s); g.set_meta("mag", mag_s)
			# 左侧拉机柄(SCAR 特征)
			_bolt(g, -0.03, 0.04, -0.02)
			_holo(g, 0.112, -0.1)
		"aug":
			# 无托:长机匣一体
			g.add_child(box(0.05, 0.085, 0.52, 0, 0.02, 0.02, "olive"))
			g.add_child(box(0.046, 0.03, 0.5, 0, 0.068, 0.0, "dark"))
			# 前握把(可折)
			var fg := box(0.03, 0.07, 0.04, 0, -0.055, -0.28, "olive"); fg.rotation.x = 0.3
			g.add_child(fg)
			g.add_child(cyl(0.012, 0.014, 0.22, 0, 0.026, -0.56))
			g.add_child(cyl(0.015, 0.018, 0.05, 0, 0.026, -0.68, "dark"))
			# 后握把(扳机后方) + 扳机(靠前)
			g.add_child(_grip(0.034, 0.09, 0.05, 0, -0.08, 0.14, "olive", 0.3))
			_trigger(g, -0.04, -0.06)
			# 透明弹匣(后置)
			var mag_a := box(0.036, 0.12, 0.055, 0, -0.1, 0.06, "olive")
			mag_a.rotation.x = -0.12
			g.add_child(mag_a); g.set_meta("mag", mag_a)
			# 枪托左侧拉机柄
			_bolt(g, -0.03, 0.05, 0.12)
			# 一体提把镜
			g.add_child(box(0.02, 0.035, 0.2, 0, 0.095, -0.05, "dark"))
			_holo(g, 0.125, -0.1)
		"mp5":
			# 细机匣 + 海军托
			g.add_child(box(0.044, 0.07, 0.3, 0, 0.018, -0.05))
			g.add_child(cyl(0.024, 0.026, 0.16, 0, 0.02, -0.28, "dark"))
			g.add_child(cyl(0.009, 0.01, 0.14, 0, 0.024, -0.42))          # 枪管前伸贴合护套
			g.add_child(cyl(0.017, 0.017, 0.04, 0, 0.024, -0.48, "dark"))  # 枪口贴合枪管
			g.add_child(_grip(0.038, 0.075, 0.15, 0, -0.005, 0.16, "dark", 0.08))
			g.add_child(_grip(0.03, 0.09, 0.04, 0, -0.082, 0.04, "poly", 0.4))
			_trigger(g, -0.038, 0.01)
			# 弧形弹匣
			_curved_mag(g, 0.032, "dark")
			# 桨式弹匣释放(右) + 左侧拉机柄
			g.add_child(box(0.01, 0.03, 0.03, 0.024, -0.04, -0.06, "dark"))
			_bolt(g, -0.026, 0.045, -0.14)
			_holo(g, 0.09, -0.06)   # 红点镜降至机匣顶(0.053),消除悬浮
		"ump":
			g.add_child(box(0.048, 0.078, 0.3, 0, 0.02, -0.04, "poly"))
			g.add_child(cyl(0.026, 0.028, 0.14, 0, 0.02, -0.24, "dark"))
			g.add_child(cyl(0.01, 0.011, 0.12, 0, 0.022, -0.36))          # 枪管贴合护套
			g.add_child(_grip(0.04, 0.08, 0.15, 0, -0.005, 0.16, "poly", 0.06))
			g.add_child(_grip(0.032, 0.095, 0.045, 0, -0.088, 0.045, "poly", 0.38))
			_trigger(g, -0.04, 0.02)
			# .45 宽直弹匣
			var mag_u := box(0.04, 0.12, 0.06, 0, -0.11, -0.05, "dark")
			g.add_child(mag_u); g.set_meta("mag", mag_u)
			# 左侧释放杆 + 空挂钮
			g.add_child(box(0.008, 0.03, 0.04, -0.027, -0.02, -0.02, "dark"))
			_bolt(g, -0.027, 0.045, -0.08)
			_holo(g, 0.1, -0.05)
		"p90":
			# 无托一体框架
			g.add_child(box(0.05, 0.07, 0.34, 0, 0.0, -0.02, "poly"))
			# 水平顶置弹匣(半透明长条)
			var mag_p := box(0.042, 0.024, 0.3, 0, 0.048, -0.06, "tan")
			g.add_child(mag_p); g.set_meta("mag", mag_p)
			g.add_child(box(0.044, 0.012, 0.31, 0, 0.036, -0.06, "dark"))
			# 下弯枪身 + 前握把槽
			g.add_child(_grip(0.034, 0.06, 0.08, 0, -0.055, -0.12, "poly", 0.5))
			g.add_child(_grip(0.032, 0.08, 0.05, 0, -0.075, 0.08, "poly", 0.35))
			_trigger(g, -0.035, 0.02)
			g.add_child(cyl(0.009, 0.01, 0.15, 0, 0.01, -0.26))          # 枪管贴合框架前端(-0.19)
			# 枪托左侧拉机柄
			_bolt(g, -0.026, 0.03, 0.12)
			# 顶部反射镜座(降至弹匣盖顶 0.042,消除悬浮)
			_holo(g, 0.078, -0.02)
		"m249":
			# 大机匣 + 顶部受弹机盖
			g.add_child(box(0.062, 0.1, 0.44, 0, 0.02, -0.08))
			g.add_child(box(0.058, 0.03, 0.46, 0, 0.085, -0.1, "dark"))
			_rail(g, 0.105, -0.18, -0.34)
			# 弹链箱(左侧挂)
			var mag_l := box(0.075, 0.11, 0.13, -0.045, -0.075, -0.12, "olive")
			g.add_child(mag_l); g.set_meta("mag", mag_l)
			# 护木 + 枪管 + 两脚架
			g.add_child(cyl(0.028, 0.032, 0.26, 0, 0.02, -0.46, "dark"))
			g.add_child(cyl(0.014, 0.016, 0.26, 0, 0.028, -0.72))
			g.add_child(cyl(0.02, 0.022, 0.06, 0, 0.028, -0.86, "dark"))
			g.add_child(box(0.008, 0.14, 0.008, -0.03, -0.08, -0.6, "dark"))
			g.add_child(box(0.008, 0.14, 0.008, 0.03, -0.08, -0.6, "dark"))
			# 枪托 + 握把
			g.add_child(_grip(0.048, 0.1, 0.18, 0, -0.01, 0.19, "poly", 0.1))
			g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.095, 0.05, "poly", 0.35))
			_trigger(g, -0.045, 0.02)
			_bolt(g, 0.035, 0.03, 0.02)
			_holo(g, 0.125, -0.12)
		"pkm":
			g.add_child(box(0.062, 0.1, 0.46, 0, 0.02, -0.06))
			g.add_child(box(0.058, 0.028, 0.48, 0, 0.082, -0.08, "dark"))
			# 弹链箱(右侧挂,PKM 特征)
			var mag_p2 := box(0.075, 0.11, 0.13, 0.045, -0.075, -0.1, "dark")
			g.add_child(mag_p2); g.set_meta("mag", mag_p2)
			g.add_child(cyl(0.028, 0.032, 0.28, 0, 0.02, -0.46, "wood"))
			g.add_child(cyl(0.015, 0.017, 0.28, 0, 0.028, -0.72))
			g.add_child(cyl(0.02, 0.023, 0.06, 0, 0.028, -0.88, "dark"))
			g.add_child(_grip(0.048, 0.1, 0.19, 0, -0.01, 0.19, "wood", 0.12))
			g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.095, 0.05, "wood", 0.38))
			_trigger(g, -0.045, 0.02)
			_bolt(g, 0.035, 0.03, 0.04)
			_holo(g, 0.122, -0.12)
		"rpd":
			g.add_child(box(0.056, 0.085, 0.4, 0, 0.018, -0.06))
			g.add_child(box(0.052, 0.024, 0.4, 0, 0.068, -0.08, "dark"))
			# 弹鼓(左侧大圆鼓)
			var drum := cyl(0.075, 0.075, 0.05, -0.06, -0.06, -0.08, "brass", "x")
			g.add_child(drum); g.set_meta("mag", drum)
			g.add_child(cyl(0.026, 0.03, 0.28, 0, 0.02, -0.44, "wood"))
			g.add_child(cyl(0.013, 0.015, 0.28, 0, 0.026, -0.72))
			g.add_child(cyl(0.018, 0.021, 0.05, 0, 0.026, -0.86, "dark"))
			g.add_child(_grip(0.044, 0.095, 0.19, 0, -0.008, 0.18, "wood", 0.14))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.09, 0.04, "wood", 0.4))
			_trigger(g, -0.042, 0.01)
			_bolt(g, 0.032, 0.035, 0.0)
			_holo(g, 0.115, -0.1)
		"awm":
			# 栓动狙:长枪管 + 大镜 + 栓柄
			g.add_child(box(0.05, 0.075, 0.42, 0, 0.012, -0.04, "olive"))
			g.add_child(cyl(0.013, 0.017, 0.5, 0, 0.03, -0.58))
			g.add_child(cyl(0.02, 0.023, 0.08, 0, 0.03, -0.86, "dark"))
			# 贴腮 + 枪托
			g.add_child(box(0.044, 0.06, 0.14, 0, 0.05, 0.12, "olive"))
			g.add_child(_grip(0.046, 0.1, 0.18, 0, -0.01, 0.2, "olive", 0.12))
			g.add_child(_grip(0.034, 0.09, 0.045, 0, -0.08, 0.05, "olive", 0.42))
			_trigger(g, -0.04, 0.03)
			# 弹匣(底部 5 发)
			var mag_aw := box(0.036, 0.09, 0.08, 0, -0.08, -0.08, "dark")
			g.add_child(mag_aw); g.set_meta("mag", mag_aw)
			# 栓柄(尾部大球)
			var bolt_h := Node3D.new()
			bolt_h.position = Vector3(0.03, 0.05, 0.1)
			bolt_h.add_child(cyl(0.006, 0.006, 0.05, 0, 0.02, 0, "chrome", "y"))
			bolt_h.add_child(cyl(0.014, 0.014, 0.02, 0, 0.045, 0, "chrome"))
			g.add_child(bolt_h)
			g.set_meta("bolt", bolt_h)
			_scope(g, 0.115, -0.06)
		"m24":
			g.add_child(box(0.05, 0.075, 0.44, 0, 0.012, -0.05, "wood"))
			g.add_child(cyl(0.013, 0.016, 0.46, 0, 0.028, -0.56))
			g.add_child(cyl(0.018, 0.021, 0.06, 0, 0.028, -0.8, "dark"))
			g.add_child(box(0.044, 0.06, 0.14, 0, 0.048, 0.12, "wood"))
			g.add_child(_grip(0.046, 0.1, 0.18, 0, -0.01, 0.2, "wood", 0.12))
			g.add_child(_grip(0.034, 0.09, 0.045, 0, -0.08, 0.05, "wood", 0.42))
			_trigger(g, -0.04, 0.03)
			# 内置弹仓底板
			g.add_child(box(0.03, 0.02, 0.09, 0, -0.05, -0.05, "dark"))
			# 栓柄
			var bolt_h2 := Node3D.new()
			bolt_h2.position = Vector3(0.03, 0.05, 0.1)
			bolt_h2.add_child(cyl(0.006, 0.006, 0.05, 0, 0.02, 0, "dark", "y"))
			bolt_h2.add_child(cyl(0.013, 0.013, 0.02, 0, 0.045, 0, "dark"))
			g.add_child(bolt_h2)
			g.set_meta("bolt", bolt_h2)
			_scope(g, 0.112, -0.06)
		"svd":
			# AK 式机匣 + 长枪管 + 弯弹匣 + PSO 镜
			g.add_child(box(0.052, 0.07, 0.38, 0, 0.015, -0.04, "wood"))
			g.add_child(cyl(0.011, 0.013, 0.42, 0, 0.026, -0.56))
			g.add_child(cyl(0.015, 0.018, 0.06, 0, 0.026, -0.79, "dark"))
			g.add_child(box(0.014, 0.05, 0.014, 0, 0.055, -0.6, "dark"))
			g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.01, 0.18, "wood", 0.16))
			g.add_child(box(0.04, 0.05, 0.06, 0, 0.045, 0.12, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.085, 0.045, "wood", 0.42))
			_trigger(g, -0.04, 0.02)
			_curved_mag(g, 0.036)
			_bolt(g, 0.032, 0.035, -0.02)
			# PSO 侧轨镜
			g.add_child(box(0.012, 0.03, 0.1, -0.03, 0.06, -0.04, "dark"))
			_scope(g, 0.115, -0.02)
		"m1014":
			# 霰弹枪:机匣 + 管状弹仓
			g.add_child(box(0.05, 0.08, 0.32, 0, 0.02, -0.02))
			g.add_child(cyl(0.014, 0.016, 0.42, 0, 0.045, -0.39))          # 枪管后伸贴合机匣(-0.18)
			g.add_child(cyl(0.012, 0.012, 0.38, 0, -0.005, -0.37, "dark"))  # 弹仓管贴合机匣
			g.add_child(cyl(0.019, 0.02, 0.03, 0, 0.045, -0.61, "dark"))   # 枪口贴合枪管
			# 泵动护木
			var pump_m := cyl(0.024, 0.024, 0.12, 0, -0.005, -0.34, "poly")
			g.add_child(pump_m); g.set_meta("pump", pump_m)
			g.add_child(_grip(0.042, 0.09, 0.17, 0, -0.005, 0.17, "poly", 0.1))
			g.add_child(_grip(0.032, 0.095, 0.045, 0, -0.085, 0.04, "poly", 0.38))
			_trigger(g, -0.04, 0.01)
			g.add_child(box(0.012, 0.032, 0.012, 0, 0.075, -0.57, "brass"))
			_holo(g, 0.096, -0.04)   # 红点镜降至机匣顶(0.06),消除悬浮
		"spas12":
			g.add_child(box(0.052, 0.085, 0.34, 0, 0.02, -0.03))
			g.add_child(cyl(0.015, 0.017, 0.42, 0, 0.048, -0.41))          # 枪管后伸贴合机匣(-0.2)
			g.add_child(cyl(0.013, 0.013, 0.36, 0, -0.005, -0.38, "dark"))  # 弹仓管贴合机匣
			g.add_child(cyl(0.02, 0.021, 0.03, 0, 0.048, -0.63, "dark"))   # 枪口贴合枪管
			# 泵动护木(长行程)
			var pump_s := cyl(0.026, 0.026, 0.15, 0, -0.005, -0.36, "dark")
			g.add_child(pump_s); g.set_meta("pump", pump_s)
			# 折叠枪托钩
			g.add_child(box(0.008, 0.05, 0.16, 0, 0.06, 0.16, "metal"))
			g.add_child(_grip(0.044, 0.09, 0.16, 0, -0.005, 0.18, "dark", 0.1))
			g.add_child(_grip(0.034, 0.1, 0.05, 0, -0.09, 0.04, "dark", 0.36))
			_trigger(g, -0.042, 0.01)
			g.add_child(box(0.012, 0.03, 0.012, 0, 0.078, -0.58, "brass"))
			_holo(g, 0.1, -0.05)   # 红点镜降至机匣顶(0.0625),消除悬浮
		"rpg":
			# 火箭筒:主筒 + 锥形弹头 + 握把 + 机瞄
			g.add_child(cyl(0.042, 0.042, 0.6, 0, 0.02, -0.1, "olive"))
			g.add_child(cyl(0.05, 0.05, 0.1, 0, 0.02, 0.22, "dark"))
			# 膛内火箭弹(锥头,换弹时隐藏)
			var rkt := Node3D.new()
			rkt.position = Vector3(0, 0.02, -0.42)
			rkt.add_child(cyl(0.0, 0.055, 0.16, 0, 0, 0, "brass"))
			rkt.add_child(cyl(0.055, 0.03, 0.1, 0, 0, 0.12, "dark"))
			g.add_child(rkt)
			g.set_meta("rocket", rkt)
			g.add_child(_grip(0.034, 0.1, 0.05, 0, -0.08, 0.02, "dark", 0.3))
			g.add_child(_grip(0.034, 0.08, 0.05, 0, -0.06, -0.25, "dark", 0.15))
			g.add_child(box(0.014, 0.06, 0.05, 0, 0.075, -0.1, "dark"))
			g.add_child(box(0.03, 0.02, 0.06, 0, 0.07, 0.08, "dark"))
		"m1911":
			var sl1 := box(0.034, 0.048, 0.19, 0, 0.032, -0.03, "dark"); g.add_child(sl1)
			g.set_meta("slide", sl1)
			g.add_child(box(0.032, 0.036, 0.17, 0, -0.002, -0.02, "dark"))
			g.add_child(cyl(0.008, 0.009, 0.03, 0, 0.034, -0.14))
			g.add_child(cyl(0.004, 0.004, 0.01, 0, 0.06, 0.06, "dark", "y"))
			g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.06, 0.045, "wood", 0.35))
			_trigger(g, -0.035, 0.0)
			var mag_1 := box(0.024, 0.1, 0.034, 0, -0.11, 0.045, "metal"); g.add_child(mag_1)
			g.set_meta("mag", mag_1)
			g.add_child(box(0.01, 0.02, 0.01, 0, 0.062, -0.1, "dark"))
			g.add_child(box(0.005, 0.024, 0.014, -0.0075, 0.062, 0.05, "dark"))  # 左照门(双耳缺口)
			g.add_child(box(0.005, 0.024, 0.014, 0.0075, 0.062, 0.05, "dark"))   # 右照门
		"g17":
			var sl2 := box(0.034, 0.045, 0.2, 0, 0.03, -0.03, "dark"); g.add_child(sl2)
			g.set_meta("slide", sl2)
			g.add_child(box(0.033, 0.03, 0.18, 0, -0.002, -0.02, "poly"))
			g.add_child(cyl(0.008, 0.009, 0.03, 0, 0.032, -0.15))
			g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.06, 0.045, "poly", 0.35))
			_trigger(g, -0.035, 0.0)
			var mag_2 := box(0.026, 0.11, 0.036, 0, -0.115, 0.045, "dark"); g.add_child(mag_2)
			g.set_meta("mag", mag_2)
			g.add_child(box(0.01, 0.018, 0.01, 0, 0.06, -0.1, "dark"))
			g.add_child(box(0.005, 0.02, 0.014, -0.0075, 0.058, 0.05, "dark"))  # 左照门(双耳缺口)
			g.add_child(box(0.005, 0.02, 0.014, 0.0075, 0.058, 0.05, "dark"))   # 右照门
		"p226":
			var sl3 := box(0.035, 0.048, 0.2, 0, 0.032, -0.03, "dark"); g.add_child(sl3)
			g.set_meta("slide", sl3)
			g.add_child(box(0.034, 0.038, 0.18, 0, -0.002, -0.02, "tan"))
			g.add_child(cyl(0.009, 0.01, 0.03, 0, 0.034, -0.15))
			# 待击解脱杆(左)
			g.add_child(box(0.008, 0.03, 0.02, -0.02, 0.005, 0.03, "dark"))
			g.add_child(_grip(0.031, 0.09, 0.045, 0, -0.062, 0.045, "poly", 0.35))
			_trigger(g, -0.035, 0.0)
			var mag_3 := box(0.026, 0.11, 0.036, 0, -0.115, 0.045, "metal"); g.add_child(mag_3)
			g.set_meta("mag", mag_3)
			g.add_child(box(0.01, 0.02, 0.01, 0, 0.064, -0.1, "dark"))
			g.add_child(box(0.005, 0.022, 0.014, -0.0075, 0.062, 0.05, "dark"))  # 左照门(双耳缺口)
			g.add_child(box(0.005, 0.022, 0.014, 0.0075, 0.062, 0.05, "dark"))   # 右照门
		"deagle":
			var sl4 := box(0.042, 0.058, 0.24, 0, 0.038, -0.05, "chrome"); g.add_child(sl4)
			g.set_meta("slide", sl4)
			g.add_child(cyl(0.011, 0.012, 0.06, 0, 0.04, -0.2, "chrome"))
			g.add_child(cyl(0.02, 0.02, 0.025, 0, 0.04, -0.24, "dark"))
			g.add_child(box(0.04, 0.04, 0.19, 0, -0.002, -0.03, "dark"))
			g.add_child(_grip(0.036, 0.1, 0.05, 0, -0.068, 0.05, "wood", 0.32))
			_trigger(g, -0.038, 0.0)
			var mag_4 := box(0.03, 0.12, 0.04, 0, -0.13, 0.05, "chrome"); g.add_child(mag_4)
			g.set_meta("mag", mag_4)
			g.add_child(box(0.012, 0.022, 0.012, 0, 0.072, -0.15, "dark"))
			g.add_child(box(0.006, 0.024, 0.016, -0.008, 0.07, 0.05, "dark"))  # 左照门(双耳缺口)
			g.add_child(box(0.006, 0.024, 0.016, 0.008, 0.07, 0.05, "dark"))   # 右照门
			g.add_child(box(0.042, 0.012, 0.1, 0, 0.068, -0.1, "chrome"))
		"m93r":
			var sl5 := box(0.034, 0.045, 0.21, 0, 0.03, -0.04, "dark"); g.add_child(sl5)
			g.set_meta("slide", sl5)
			g.add_child(box(0.033, 0.038, 0.19, 0, -0.002, -0.03, "metal"))
			g.add_child(cyl(0.008, 0.009, 0.04, 0, 0.032, -0.16))
			# 前握把(展开)
			var fg2 := box(0.024, 0.06, 0.03, 0, -0.06, -0.08, "poly"); fg2.rotation.x = 0.2
			g.add_child(fg2)
			g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.062, 0.05, "poly", 0.35))
			_trigger(g, -0.035, 0.01)
			var mag_5 := box(0.026, 0.14, 0.034, 0, -0.13, 0.045, "dark"); g.add_child(mag_5)
			g.set_meta("mag", mag_5)
			g.add_child(box(0.008, 0.02, 0.03, -0.02, 0.03, 0.02, "dark"))
			g.add_child(box(0.01, 0.018, 0.01, 0, 0.061, -0.11, "dark"))      # 前准星(补齐缺失瞄具)
			g.add_child(box(0.005, 0.02, 0.014, -0.0075, 0.059, 0.045, "dark"))  # 左照门(双耳缺口)
			g.add_child(box(0.005, 0.02, 0.014, 0.0075, 0.059, 0.045, "dark"))   # 右照门


## 各武器的握持锚点(枪械局部空间,左手贴合护木底部)
const HAND_ANCHORS := {
	"m4": { "r": [0.012, -0.1, 0.035], "l": [0, -0.038, -0.4] },
	"ak": { "r": [0.012, -0.1, 0.045], "l": [0, -0.032, -0.4] },
	"mp5": { "r": [0.012, -0.095, 0.035], "l": [0, -0.085, -0.26] },
	"m249": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.46] },
	"awm": { "r": [0.012, -0.095, 0.065], "l": [0, -0.048, -0.32] },
	"m1014": { "r": [0.012, -0.1, 0.045], "l": [0, -0.062, -0.32] },
	"m1911": { "r": [0.012, -0.075, 0.055], "l": [-0.028, -0.085, 0.05] },
	"rpg": { "r": [0.012, -0.07, 0.115], "l": [0, -0.03, -0.1] },
	"scar": { "r": [0.012, -0.1, 0.035], "l": [0, -0.038, -0.4] },
	"aug": { "r": [0.012, -0.1, -0.005], "l": [0, -0.045, -0.32] },
	"ump": { "r": [0.012, -0.095, 0.035], "l": [0, -0.055, -0.24] },
	"p90": { "r": [0.012, -0.05, 0.13], "l": [0, -0.065, -0.12] },
	"pkm": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.48] },
	"rpd": { "r": [0.012, -0.105, 0.045], "l": [0, -0.04, -0.44] },
	"m24": { "r": [0.012, -0.095, 0.065], "l": [0, -0.048, -0.3] },
	"svd": { "r": [0.012, -0.1, 0.045], "l": [0, -0.028, -0.42] },
	"g17": { "r": [0.012, -0.075, 0.055], "l": [-0.028, -0.085, 0.05] },
	"p226": { "r": [0.012, -0.075, 0.055], "l": [-0.028, -0.085, 0.05] },
	"deagle": { "r": [0.012, -0.08, 0.06], "l": [-0.028, -0.088, 0.05] },
	"m93r": { "r": [0.012, -0.075, 0.06], "l": [0, -0.06, -0.1] },
	"spas12": { "r": [0.012, -0.1, 0.045], "l": [0, -0.062, -0.33] },
}

## 枪口 z 位置表
const MUZZLE_Z := {
	"m4": -0.8, "ak": -0.86, "mp5": -0.53, "m249": -0.9, "awm": -0.92, "m1014": -0.72,
	"m1911": -0.15, "rpg": -0.62, "scar": -0.82, "aug": -0.66, "ump": -0.46, "p90": -0.35,
	"pkm": -0.94, "rpd": -0.88, "m24": -0.86, "svd": -0.84,
	"g17": -0.15, "p226": -0.155, "deagle": -0.21, "m93r": -0.18, "spas12": -0.75,
}


## 第一人称手模(拳头,战术手套)
static func build_hand(is_left: bool) -> Node3D:
	var g := Node3D.new()
	if not _mat.has("glove"):
		_mat["glove"] = _std(Color.html("#6a5a42"), 0.85, 0.0)
	var palm := box(0.055, 0.05, 0.09, 0, 0, 0, "glove")
	g.add_child(palm)
	# 四指(微弯)
	for i in 4:
		var f := box(0.011, 0.035, 0.03, (i - 1.5) * 0.013, -0.01, -0.095, "glove")
		f.rotation.x = -0.5
		g.add_child(f)
	# 拇指
	var th := box(0.013, 0.03, 0.035, 0.032 if is_left else -0.032, -0.005, -0.05, "glove")
	th.rotation.y = 0.6 if is_left else -0.6
	g.add_child(th)
	return g


## 第一人称前臂(战术服):单位长度臂筒(z 轴 1m),运行时按腕部-肘锚点定向缩放
static func build_forearm() -> Node3D:
	var g := Node3D.new()
	if not _mat.has("sleeve"):
		_mat["sleeve"] = _std(Color.html("#4a5548"), 0.9, 0.0)
	g.add_child(box(0.058, 0.058, 1.0, 0, 0, 0, "sleeve"))
	return g


## 构建完整武器模型(含枪口参考点;viewmodel = 第一人称时附带手模)
static func build(id: String, with_hands := false) -> Node3D:
	var g := Node3D.new()
	g.name = "Weapon_" + id
	_build(id, g)
	# 枪口参考点
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.03, MUZZLE_Z.get(id, -0.7))
	g.add_child(muzzle)
	g.set_meta("muzzle", muzzle)
	if with_hands:
		var anchors: Dictionary = HAND_ANCHORS[id]
		var right_hand := build_hand(false)
		right_hand.scale = Vector3.ONE * 1.15
		right_hand.position = Vector3(anchors["r"][0], anchors["r"][1], anchors["r"][2])
		right_hand.rotation = Vector3(-0.2, -0.15, -1.3)
		g.add_child(right_hand)
		g.set_meta("right_hand", right_hand)
		var right_arm := build_forearm()
		right_arm.rotation = Vector3(0.72, 0.32, 0)
		g.add_child(right_arm)
		g.set_meta("right_arm", right_arm)
		var left_hand := build_hand(true)
		left_hand.scale = Vector3.ONE * 1.15
		left_hand.position = Vector3(anchors["l"][0], anchors["l"][1], anchors["l"][2])
		left_hand.rotation = Vector3(0.1, 0, PI - 0.15)
		g.add_child(left_hand)
		g.set_meta("left_hand", left_hand)
		var left_arm := build_forearm()
		left_arm.rotation = Vector3(0.78, -0.32, 0)
		g.add_child(left_arm)
		g.set_meta("left_arm", left_arm)
	# 视角模型不投影
	set_shadow_recursive(g, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	return g


## 遍历节点树设置投影(工具函数)
static func set_shadow_recursive(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for o in node.get_children():
		if o is MeshInstance3D:
			o.cast_shadow = mode
		set_shadow_recursive(o, mode)
