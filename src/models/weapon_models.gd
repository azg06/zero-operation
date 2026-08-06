class_name WeaponModels
## 精化武器建模(低模多部件:锥形枪管/斜置握把/导轨/弯弹匣/可见拉机柄)
## 所有模型:原点位于握把处,枪管朝 -Z;裸枪默认机械瞄具,视轴(y=def.sight_y)与 ADS 视线对齐

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
		lens.albedo_color = Color(0.23, 0.42, 0.60, 0.55)   # 发光半透明蓝(开镜视线可穿透)
		lens.roughness = 0.15
		lens.metallic = 0.9
		lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lens.emission_enabled = true
		lens.emission = Color.html("#0a2a4a")
		lens.emission_energy_multiplier = 0.6
		_mat["lens"] = lens
		# 光学改装件透镜:高透明玻璃(alpha 0.15,无自发光)——镜片几乎不可见,
		# 保留玻璃反光质感但不挡视轴(全息/红点镜 ADS 时屏幕中央需清晰见敌)
		var lens_clear := StandardMaterial3D.new()
		lens_clear.albedo_color = Color(0.55, 0.72, 0.88, 0.15)
		lens_clear.roughness = 0.08
		lens_clear.metallic = 0.9
		lens_clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat["lens_clear"] = lens_clear
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
	trig.name = "StockTrigger"
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


## 机械瞄具(前准星柱 + 后缺口双耳),视轴 = sy(与 def.sight_y 一致,ADS 视线对准)
## 前柱顶与双耳顶齐平于视轴;全部收纳于 "StockIrons" 容器,供改装光学瞄具时整体隐藏
static func _irons(g: Node3D, sy: float, fz: float, rz: float, ph: float) -> void:
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	var post := box(0.011, ph, 0.012, 0, sy - ph * 0.5, fz, "dark")
	post.name = "IronsFront"
	ir.add_child(post)
	var ear_h := 0.022
	var el := box(0.004, ear_h, 0.014, -0.009, sy - ear_h * 0.5 + 0.003, rz, "dark")
	el.name = "IronsRearL"
	ir.add_child(el)
	var er := box(0.004, ear_h, 0.014, 0.009, sy - ear_h * 0.5 + 0.003, rz, "dark")
	er.name = "IronsRearR"
	ir.add_child(er)


## 狙击镜(镜筒 + 前后支架 + 半透物镜,scope 武器用;最初版本恢复)
## 结构:镜筒 cyl(r 0.021-0.024,长 0.22,dark,物镜端略粗)沿 -Z 水平延伸,
## 前后 2 个短支架 cyl 托于镜筒下方,物镜端为半透蓝 lens cyl(r 0.03),
## 目镜端为小号 lens cyl(贴视点侧),顶部小调节钮(垂直 cyl)。
## 镜体中心在视轴 (0, y)(y = def.sight_y),目镜朝 +Z;开镜时枪身由 2D 镜罩接管,
## 本模型仅供第三人称/手持简洁观感,无需镜片/reticle 贴图。
static func _scope(g: Node3D, y: float, z: float) -> void:
	var s := Node3D.new()
	s.name = "StockOptic"
	g.add_child(s)
	s.add_child(cyl(0.021, 0.024, 0.22, 0, y, z - 0.03, "dark"))      # 镜筒(目镜端细 0.021,物镜端粗 0.024)
	s.add_child(cyl(0.021, 0.021, 0.05, 0, y - 0.028, z + 0.03, "dark"))   # 前支架
	s.add_child(cyl(0.021, 0.021, 0.05, 0, y - 0.028, z - 0.09, "dark"))   # 后支架
	s.add_child(cyl(0.03, 0.027, 0.03, 0, y, z - 0.14, "lens"))       # 物镜(半透蓝,朝 -Z)
	s.add_child(cyl(0.019, 0.019, 0.01, 0, y, z + 0.085, "lens"))     # 目镜端(小半透蓝,贴视点侧)
	s.add_child(cyl(0.005, 0.005, 0.02, 0, y + 0.03, z - 0.03, "dark", "y"))  # 调节钮(垂直)


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
			# 机械瞄具(视轴 = sight_y 0.108)
			_irons(g, 0.108, -0.55, 0.09, 0.07)
		"ak":
			g.add_child(box(0.054, 0.075, 0.34, 0, 0.015, -0.05))
			g.add_child(box(0.05, 0.024, 0.3, 0, 0.058, -0.07, "dark"))
			# 木护木(锥形,前伸贴合机匣,消除 -0.22 ~ -0.26 缝隙)
			g.add_child(cyl(0.024, 0.03, 0.28, 0, 0.02, -0.36, "wood"))
			g.add_child(box(0.048, 0.05, 0.12, 0, 0.05, -0.32, "wood"))
			# 枪管 + 准星座 + 消焰器
			g.add_child(cyl(0.012, 0.014, 0.34, 0, 0.028, -0.63))
			g.add_child(cyl(0.016, 0.019, 0.05, 0, 0.028, -0.81, "dark"))   # 消焰器贴合枪管尾端
			# 木枪托(斜) + 握把
			g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.01, 0.18, "wood", 0.16))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.085, 0.045, "wood", 0.42))
			_trigger(g, -0.04, 0.02)
			# 弯弹匣(前挂后卡)
			_curved_mag(g, 0.038)
			# 拉机柄(右侧大柄)
			_bolt(g, 0.032, 0.035, -0.02)
			# 机械瞄具(视轴 = sight_y 0.104)
			_irons(g, 0.104, -0.56, 0.05, 0.062)
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
			# 机械瞄具(视轴 = sight_y 0.112)
			_irons(g, 0.112, -0.58, 0.09, 0.06)
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
			# 一体提把(保留外观) + 机械瞄具(视轴 = sight_y 0.125)
			g.add_child(box(0.02, 0.035, 0.2, 0, 0.095, -0.05, "dark"))
			_irons(g, 0.125, -0.52, 0.17, 0.045)
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
			# 机械瞄具(视轴 = sight_y 0.09)
			_irons(g, 0.09, -0.36, 0.1, 0.05)
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
			# 机械瞄具(视轴 = sight_y 0.1)
			_irons(g, 0.1, -0.35, 0.09, 0.05)
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
			# 机械瞄具(视轴 = sight_y 0.078)
			_irons(g, 0.078, -0.18, 0.09, 0.032)
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
			# 机械瞄具(视轴 = sight_y 0.125)
			_irons(g, 0.125, -0.6, 0.1, 0.055)
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
			# 机械瞄具(视轴 = sight_y 0.122)
			_irons(g, 0.122, -0.6, 0.1, 0.055)
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
			# 机械瞄具(视轴 = sight_y 0.115)
			_irons(g, 0.115, -0.58, 0.1, 0.055)
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
			# 机械瞄具(视轴 = sight_y 0.096)
			_irons(g, 0.096, -0.57, 0.09, 0.045)
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
			# 机械瞄具(视轴 = sight_y 0.1)
			_irons(g, 0.1, -0.58, 0.09, 0.045)
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

## ============ 枪械改装件(程序化挂载) ============
## 各武器改装件挂载锚点(相对武器根;改装件原点即锚点,几何向 -Z/-Y/+Y 展开)
## muzzle:枪口部(改装件 0 点贴合枪口,向 -Z 延伸);mag:改装弹匣体中心基准(换算为 meta "mag" 子节点偏移)
## grip:枪管/护木下方中部;trigger:扳机护圈内;optic:机匣顶部导轨(改装光学时原瞄具隐藏)
const MOD_ANCHORS := {
	"m4": { "muzzle": Vector3(0, 0.024, -0.8), "mag": Vector3(0, -0.12, -0.09), "grip": Vector3(0, -0.012, -0.42), "trigger": Vector3(0, -0.06, 0.005), "optic": Vector3(0, 0.0875, -0.1) },
	"ak": { "muzzle": Vector3(0, 0.028, -0.84), "mag": Vector3(0, -0.12, -0.1), "grip": Vector3(0, -0.012, -0.4), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.072, -0.06) },
	"scar": { "muzzle": Vector3(0, 0.024, -0.83), "mag": Vector3(0, -0.105, -0.1), "grip": Vector3(0, -0.012, -0.42), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.09, -0.1) },
	"aug": { "muzzle": Vector3(0, 0.026, -0.7), "mag": Vector3(0, -0.105, 0.06), "grip": Vector3(0, -0.01, -0.45), "trigger": Vector3(0, -0.06, -0.065), "optic": Vector3(0, 0.09, -0.1) },
	"mp5": { "muzzle": Vector3(0, 0.024, -0.5), "mag": Vector3(0, -0.125, -0.1), "grip": Vector3(0, -0.01, -0.3), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.058, -0.06) },
	"ump": { "muzzle": Vector3(0, 0.022, -0.42), "mag": Vector3(0, -0.115, -0.05), "grip": Vector3(0, -0.01, -0.26), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.065, -0.05) },
	"p90": { "muzzle": Vector3(0, 0.01, -0.33), "grip": Vector3(0, -0.01, -0.22), "trigger": Vector3(0, -0.055, 0.015), "optic": Vector3(0, 0.062, -0.02) },
	"m249": { "muzzle": Vector3(0, 0.028, -0.88), "grip": Vector3(0, -0.015, -0.5), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.11, -0.12) },
	"pkm": { "muzzle": Vector3(0, 0.028, -0.9), "grip": Vector3(0, -0.015, -0.5), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.105, -0.12) },
	"rpd": { "muzzle": Vector3(0, 0.026, -0.88), "grip": Vector3(0, -0.01, -0.5), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.095, -0.1) },
	"awm": { "muzzle": Vector3(0, 0.03, -0.9), "mag": Vector3(0, -0.125, -0.08), "grip": Vector3(0, -0.012, -0.5), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.088, -0.06) },
	"m24": { "muzzle": Vector3(0, 0.028, -0.83), "grip": Vector3(0, -0.012, -0.5), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.086, -0.06) },
	"svd": { "muzzle": Vector3(0, 0.026, -0.82), "mag": Vector3(0, -0.125, -0.1), "grip": Vector3(0, -0.012, -0.45), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.09, -0.02) },
	"m1014": { "muzzle": Vector3(0, 0.045, -0.62), "grip": Vector3(0, -0.03, -0.34), "trigger": Vector3(0, -0.06, 0.005), "optic": Vector3(0, 0.062, -0.04) },
	"spas12": { "muzzle": Vector3(0, 0.048, -0.64), "grip": Vector3(0, -0.03, -0.36), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.065, -0.05) },
	"rpg": { "muzzle": Vector3(0, 0.02, -0.4), "grip": Vector3(0, -0.07, -0.28), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.065, -0.1) },
	"m1911": { "muzzle": Vector3(0, 0.034, -0.155), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.062, -0.03) },
	"g17": { "muzzle": Vector3(0, 0.032, -0.165), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.06, -0.03) },
	"p226": { "muzzle": Vector3(0, 0.034, -0.165), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.062, -0.03) },
	"deagle": { "muzzle": Vector3(0, 0.04, -0.25), "mag": Vector3(0, -0.145, 0.05), "grip": Vector3(0, -0.038, -0.06), "trigger": Vector3(0, -0.058, -0.005), "optic": Vector3(0, 0.07, -0.05) },
	"m93r": { "muzzle": Vector3(0, 0.032, -0.18), "mag": Vector3(0, -0.145, 0.045), "grip": Vector3(0, -0.06, -0.1), "trigger": Vector3(0, -0.055, 0.005), "optic": Vector3(0, 0.06, -0.04) },
}

## 底部常规弹匣武器(改装弹匣仅替换这类;顶置/侧挂/弹鼓/无弹匣枪型跳过)
const _MAG_MOD_OK := ["m4", "ak", "scar", "aug", "mp5", "ump", "svd", "awm",
	"m1911", "g17", "p226", "deagle", "m93r"]

## 改装件 id 与 WeaponModsData 数据表对齐;以下为旧短名别名
const _MOD_ALIAS := {
	"suppressor": "muz_supp", "flash_hider": "muz_flash", "muzzle_brake": "muz_brk",
	"extended": "mag_ext", "quickdraw": "mag_quick", "ap": "mag_ap",
	"vertical": "grip_vert", "angled": "grip_ang", "lightweight": "grip_light",
	"match": "trig_comp", "two_stage": "trig_dual",
	"reddot": "opt_reddot", "holographic": "opt_holo",
}

## 各槽标准件(原厂件 = 不挂载)
const _STD_IDS := { "muzzle": "muz_std", "mag": "mag_std", "grip": "grip_std", "trigger": "trig_std", "optic": "opt_std" }

## 消音器(3 段渐变圆筒 + 端面盖)/消焰器(短筒开槽)/制退器(加粗短筒侧孔)
static func build_mod_muzzle(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var m := Node3D.new()
	m.name = "ModMuzzle_" + mod_id
	match mod_id:
		"muz_supp":
			m.add_child(cyl(0.023, 0.024, 0.055, 0, 0, -0.0275, "dark"))   # 后段(深灰)
			m.add_child(cyl(0.022, 0.023, 0.055, 0, 0, -0.0825, "metal"))  # 中段(灰金属)
			m.add_child(cyl(0.019, 0.022, 0.05, 0, 0, -0.135, "chrome"))   # 前段(亮铬)
			m.add_child(cyl(0.021, 0.021, 0.008, 0, 0, -0.16, "dark"))     # 前端环
			m.add_child(cyl(0.016, 0.016, 0.006, 0, 0, -0.167, "metal"))   # 端面盖
			m.add_child(cyl(0.02, 0.02, 0.008, 0, 0, 0.004, "dark"))       # 后接环(包住枪口)
		"muz_flash":
			m.add_child(cyl(0.018, 0.019, 0.08, 0, 0, -0.04, "dark"))      # 短筒
			m.add_child(box(0.006, 0.026, 0.045, 0, 0.013, -0.045, "poly"))    # 顶部开槽
			m.add_child(box(0.006, 0.026, 0.045, -0.011, -0.0065, -0.045, "poly"))  # 左槽
			m.add_child(box(0.006, 0.026, 0.045, 0.011, -0.0065, -0.045, "poly"))   # 右槽
			m.add_child(cyl(0.021, 0.021, 0.008, 0, 0, -0.084, "metal"))    # 前端口环
			m.add_child(cyl(0.02, 0.02, 0.006, 0, 0, 0.002, "dark"))        # 后接环
		"muz_brk":
			m.add_child(cyl(0.024, 0.025, 0.1, 0, 0, -0.05, "metal"))       # 加粗短筒
			m.add_child(box(0.02, 0.02, 0.02, 0.021, 0.004, -0.05, "poly"))  # 右侧泄压孔
			m.add_child(box(0.02, 0.02, 0.02, -0.021, 0.004, -0.05, "poly")) # 左侧泄压孔
			m.add_child(box(0.02, 0.02, 0.02, 0.004, 0.021, -0.05, "poly"))  # 顶部泄压孔
			m.add_child(box(0.02, 0.02, 0.02, 0.004, -0.021, -0.05, "poly")) # 底部泄压孔
			m.add_child(cyl(0.027, 0.027, 0.01, 0, 0, -0.105, "dark"))      # 前口环
			m.add_child(cyl(0.025, 0.025, 0.008, 0, 0, 0.004, "dark"))      # 后接环
	return m


## 计算改装弹匣体相对 meta "mag" 节点的偏移(保证弹匣体顶部与原弹匣顶/弹匣口对齐)
static func _mag_body(base: Node3D, h_extra: float, w_scale: float) -> Dictionary:
	if base is MeshInstance3D and base.mesh is BoxMesh:
		var s: Vector3 = (base.mesh as BoxMesh).size
		return { "w": s.x * w_scale, "d": maxf(s.z, 0.055), "h": s.y + h_extra, "c": -h_extra * 0.5 }
	return { "w": 0.042, "d": 0.055, "h": 0.15 + h_extra, "c": -(0.15 + h_extra) * 0.5 }


## 扩容弹匣(粗壮+加强筋)/快拔弹匣(细长)/穿甲弹匣(上色+黄色标记条)
## 直接挂在 meta "mag" 节点下:继承其位置/旋转/可见性,换弹动画语义不变
static func build_mod_mag(mod_id: String, base: Node3D) -> void:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	if base == null:
		return
	var b := _mag_body(base, 0.03, 1.12)
	match mod_id:
		"mag_ext":
			base.add_child(box(b["w"], b["h"], b["d"], 0, b["c"], 0, "dark"))        # 加长弹匣体
			base.add_child(box(b["w"] + 0.006, 0.007, b["d"] + 0.006, 0, b["c"] - b["h"] * 0.22, 0, "metal"))  # 加强筋(上)
			base.add_child(box(b["w"] + 0.006, 0.007, b["d"] + 0.006, 0, b["c"] + b["h"] * 0.28, 0, "metal"))  # 加强筋(下)
			base.add_child(box(b["w"] + 0.004, 0.014, b["d"] + 0.004, 0, b["c"] - b["h"] * 0.5 - 0.007, 0, "metal"))  # 底板
		"mag_quick":
			var q := _mag_body(base, 0.06, 0.88)
			base.add_child(box(q["w"], q["h"], q["d"], 0, q["c"], 0, "metal"))       # 细长弹匣体
			base.add_child(box(q["w"] + 0.002, 0.006, q["d"] + 0.002, 0, q["c"] + q["h"] * 0.15, 0, "poly"))  # 快拔槽(上)
			base.add_child(box(q["w"] + 0.002, 0.006, q["d"] + 0.002, 0, q["c"] - q["h"] * 0.15, 0, "poly"))  # 快拔槽(下)
			base.add_child(box(q["w"] + 0.002, 0.012, q["d"] + 0.002, 0, q["c"] - q["h"] * 0.5 - 0.006, 0, "dark"))
		"mag_ap":
			base.add_child(box(b["w"], b["h"], b["d"], 0, b["c"], 0, "olive"))       # 军绿弹匣体
			base.add_child(box(b["w"] + 0.004, 0.006, b["d"] + 0.004, 0, b["c"] - b["h"] * 0.3, 0, "dark"))
			var stripe := box(0.005, b["h"] * 0.86, 0.005, b["w"] * 0.5 + 0.004, b["c"], -b["d"] * 0.42, "brass")  # 黄色标记条
			base.add_child(stripe)
	# 隐藏原弹匣网格(节点保留,换弹动画仍驱动其变换)
	if base is MeshInstance3D:
		(base as MeshInstance3D).mesh = null
	else:
		for c in base.get_children():
			if c is MeshInstance3D:
				c.visible = false


## 垂直握把(短竖把+指槽)/斜角握把(前倾)/轻量握把(细杆镂空)
static func build_mod_grip(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var gr := Node3D.new()
	gr.name = "ModGrip_" + mod_id
	match mod_id:
		"grip_vert":
			gr.add_child(box(0.026, 0.07, 0.032, 0, -0.038, 0, "poly"))      # 竖握把体
			gr.add_child(box(0.03, 0.014, 0.036, 0, -0.004, 0, "dark"))      # 顶部安装座
			gr.add_child(box(0.028, 0.008, 0.034, 0, -0.073, 0, "dark"))     # 底部收尾
			gr.add_child(box(0.027, 0.005, 0.034, 0, -0.046, 0, "dark"))     # 指槽 1
			gr.add_child(box(0.027, 0.005, 0.034, 0, -0.06, 0, "dark"))      # 指槽 2
		"grip_ang":
			var body := box(0.024, 0.065, 0.03, 0, -0.038, 0, "olive")
			body.rotation.x = -0.55                                            # 前倾(与枪身握把方向相反,一眼可辨)
			gr.add_child(body)
			gr.add_child(box(0.028, 0.014, 0.034, 0, -0.004, 0, "dark"))
			gr.add_child(box(0.026, 0.012, 0.032, 0, -0.074, 0, "olive"))     # 斜底托
		"grip_light":
			gr.add_child(box(0.018, 0.09, 0.02, 0, -0.047, 0, "chrome"))      # 细杆
			gr.add_child(box(0.022, 0.012, 0.024, 0, -0.004, 0, "dark"))      # 顶夹座
			gr.add_child(box(0.022, 0.012, 0.024, 0, -0.09, 0, "dark"))       # 底夹座
			gr.add_child(box(0.02, 0.02, 0.007, 0, -0.038, 0.007, "poly"))    # 镂空孔 1
			gr.add_child(box(0.02, 0.02, 0.007, 0, -0.062, 0.007, "poly"))    # 镂空孔 2
	return gr


## 比赛扳机(弧形细亮色扳机)/双段扳机(双连杆+横梁)——安装在扳机护圈内
static func build_mod_trigger(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var t := Node3D.new()
	t.name = "ModTrigger_" + mod_id
	match mod_id:
		"trig_comp":
			var blade := box(0.006, 0.03, 0.004, 0, -0.004, -0.002, "chrome")
			blade.rotation.x = 0.35                                           # 弧形后弯
			t.add_child(blade)
			t.add_child(box(0.008, 0.014, 0.005, 0, 0.012, 0.003, "chrome"))  # 亮色上段
			t.add_child(box(0.003, 0.022, 0.003, 0, -0.014, -0.006, "dark"))  # 后连杆
		"trig_dual":
			t.add_child(box(0.006, 0.026, 0.004, -0.005, 0, 0, "metal"))      # 左连杆
			t.add_child(box(0.006, 0.026, 0.004, 0.005, 0, 0, "metal"))       # 右连杆
			t.add_child(box(0.014, 0.006, 0.004, 0, 0.012, 0, "metal"))       # 顶端横梁
			t.add_child(box(0.012, 0.009, 0.005, 0, 0.019, 0.003, "dark"))    # 触发杆
	return t


## 红点(中空镜框+发光透镜)/全息(骨架筒+前后透镜)
## 挂载锚点=(0, sight_y, z_eye),视轴与 ADS 视线精确共线
## 4 倍镜(opt_4x)已废弃移除:改装数据仍可能携带该 id,但不产出网格,
## 开镜画面由 2D 镜罩(枪身隐藏)接管,镜体仅第三人称/手持观感。
static func build_mod_optic(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var o := Node3D.new()
	o.name = "ModOptic_" + mod_id
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1, 0.12, 0.1)
	match mod_id:
		"opt_reddot":
			o.add_child(box(0.022, 0.007, 0.024, 0, -0.013, -0.012, "dark"))   # 导轨底座(低于轴线)
			o.add_child(box(0.017, 0.019, 0.002, 0, 0, 0.001, "lens_clear"))    # 目镜透镜窗(高透明玻璃,贴视点侧,不挡视轴)
			o.add_child(box(0.002, 0.03, 0.05, -0.012, 0, -0.02, "dark"))      # 左镜框筋(轴线外)
			o.add_child(box(0.002, 0.03, 0.05, 0.012, 0, -0.02, "dark"))       # 右镜框筋(轴线外)
			o.add_child(box(0.026, 0.005, 0.018, 0, 0.016, -0.02, "dark"))     # 遮阳罩(高于轴线)
			o.add_child(box(0.008, 0.009, 0.008, 0, 0.027, 0.005, "dark"))     # 调节钮(高于轴线)
			var rd := MeshInstance3D.new()
			var rdm := TorusMesh.new()
			rdm.inner_radius = 0.0065
			rdm.outer_radius = 0.0075
			rdm.ring_segments = 24
			rdm.rings = 8
			rd.mesh = rdm
			rd.material_override = rm
			rd.rotation.x = PI / 2.0
			rd.position = Vector3(0, 0, -0.006)
			rd.name = "RetRing"
			o.add_child(rd)                                                     # 红色分划环(镜内,无厚度,不挡视线)
			var rdot := MeshInstance3D.new()
			var rdp := PlaneMesh.new()
			rdp.size = Vector2(0.0022, 0.0022)
			rdot.mesh = rdp
			rdot.material_override = rm
			rdot.position = Vector3(0, 0, -0.006)
			rdot.name = "RetDot"
			o.add_child(rdot)                                                   # 分划中心点(轴线上)
		"opt_holo":
			o.add_child(box(0.03, 0.008, 0.05, 0, -0.013, -0.03, "dark"))      # 底座(低于轴线)
			o.add_child(cyl(0.012, 0.012, 0.004, 0, 0, 0.002, "lens_clear"))   # 目镜(高透明玻璃,贴视点侧,不挡视轴)
			o.add_child(cyl(0.012, 0.012, 0.004, 0, 0, -0.07, "lens_clear"))   # 物镜(高透明玻璃,朝 -Z)
			o.add_child(box(0.002, 0.03, 0.072, -0.013, 0, -0.035, "metal"))   # 左骨架柱(轴线外)
			o.add_child(box(0.002, 0.03, 0.072, 0.013, 0, -0.035, "metal"))    # 右骨架柱(轴线外)
			o.add_child(box(0.03, 0.002, 0.072, 0, 0.015, -0.035, "metal"))    # 顶骨架梁(高于轴线)
			o.add_child(box(0.03, 0.002, 0.072, 0, -0.015, -0.035, "metal"))   # 底骨架梁(低于轴线)
			o.add_child(box(0.006, 0.013, 0.012, 0, 0.024, 0, "dark"))         # 顶钮(高于轴线)
			var hr := MeshInstance3D.new()
			var hrm := TorusMesh.new()
			hrm.inner_radius = 0.0065
			hrm.outer_radius = 0.0075
			hrm.ring_segments = 24
			hrm.rings = 8
			hr.mesh = hrm
			hr.material_override = rm
			hr.rotation.x = PI / 2.0
			hr.position = Vector3(0, 0, -0.01)
			hr.name = "RetRing"
			o.add_child(hr)                                                     # 红色分划环(镜间,无厚度)
			var hdot := MeshInstance3D.new()
			var hdp := PlaneMesh.new()
			hdp.size = Vector2(0.0022, 0.0022)
			hdot.mesh = hdp
			hdot.material_override = rm
			hdot.position = Vector3(0, 0, -0.01)
			hdot.name = "RetDot"
			o.add_child(hdot)                                                   # 分划中心点(轴线上)
	return o


## 运行时 optic 锚点:视轴线 y = def.sight_y;目镜 z 依 ADS 相机位置推算
## gun.gd 满开镜时武器根置于相机 (0, -sight_y, ads_z),即相机位于武器局部 (0, sight_y, -ads_z);
## 目镜置于相机前方 0.12 m(≈ 枪身中后段导轨),贴目且不穿视点
## WeaponsData 未就绪(菜单未初始化等)时回退静态 MOD_ANCHORS 值,保持稳健
static func _optic_anchor(id: String, fallback: Vector3) -> Vector3:
	var wd: Dictionary = WeaponsData.W()
	var d = wd.get(id, null)
	if d != null:
		return Vector3(0.0, float(d.sight_y), -float(d.ads_z) - 0.12)
	return fallback


## 按 MOD_ANCHORS 将 mods{槽位: 改装件id} 挂载到武器根 g 上
static func _apply_mods(g: Node3D, id: String, mods: Dictionary) -> void:
	if mods.is_empty():
		return
	var anchors: Dictionary = MOD_ANCHORS.get(id, {})
	for slot: String in mods:
		var mod_id: String = mods[slot]
		if mod_id == _STD_IDS.get(slot, ""):
			continue  # 标准件(原厂件):不挂载任何改装件
		var a: Vector3 = anchors.get(slot, Vector3.ZERO)
		match slot:
			"muzzle":
				var mu := build_mod_muzzle(mod_id)
				mu.position = a
				g.add_child(mu)
			"mag":
				if not id in _MAG_MOD_OK:
					continue
				build_mod_mag(mod_id, g.get_meta("mag"))
			"grip":
				var gr := build_mod_grip(mod_id)
				gr.position = a
				g.add_child(gr)
			"trigger":
				var st := g.get_node_or_null("StockTrigger")
				if st != null:
					st.visible = false
				var tr := build_mod_trigger(mod_id)
				tr.position = a
				g.add_child(tr)
			"optic":
				var so := g.get_node_or_null("StockOptic")
				if so != null:
					so.visible = false
				var si := g.get_node_or_null("StockIrons")
				if si != null:
					si.visible = false
				var op := build_mod_optic(mod_id)
				op.position = _optic_anchor(id, a)
				g.add_child(op)


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
## mods = {槽位: 改装件id},见 MOD_ANCHORS 与 build_mod_*;不传/空 dict 行为与旧版完全一致
static func build(id: String, with_hands := false, mods := {}) -> Node3D:
	var g := Node3D.new()
	g.name = "Weapon_" + id
	_build(id, g)
	if not mods.is_empty():
		_apply_mods(g, id, mods)
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
