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
		# 战术镭射/手电发射窗:自发光红/绿/白
		for glow_cfg in [["red_glow", Color.html("#ff2020")], ["green_glow", Color.html("#30ff50")]]:
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.2, 0.2, 0.2, 1)
			gm.emission_enabled = true
			gm.emission = (glow_cfg[1] as Color)
			gm.emission_energy_multiplier = 2.4
			_mat[glow_cfg[0]] = gm
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color(0.9, 0.95, 1.0, 1)
		lamp.emission_enabled = true
		lamp.emission = Color(0.8, 0.85, 0.95)
		lamp.emission_energy_multiplier = 1.6
		_mat["lamp_white"] = lamp
		# 狙击镜 3D 玻璃分划:非受光纯色,黑线 + 白描边,开镜时始终可见
		var ret_dark := StandardMaterial3D.new()
		ret_dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ret_dark.albedo_color = Color(0.025, 0.03, 0.035, 1.0)
		_mat["ret_dark"] = ret_dark
		var ret_light := StandardMaterial3D.new()
		ret_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ret_light.albedo_color = Color(0.82, 0.85, 0.88, 1.0)
		_mat["ret_light"] = ret_light
		# 高倍镜镜筒/目镜圈:非 ADS 时全黑实体;ADS 时镜筒体隐藏,只保留细分划与 PIP 圆窗
		var scope_black := StandardMaterial3D.new()
		scope_black.albedo_color = Color(0.018, 0.02, 0.024, 1.0)
		scope_black.roughness = 0.55
		scope_black.metallic = 0.35
		_mat["scope_black"] = scope_black
	return _mat


static var _box_mesh_cache: Dictionary = {}
static var _cyl_mesh_cache: Dictionary = {}
static var _torus_mesh_cache: Dictionary = {}


static func box(w: float, h: float, d: float, x: float, y: float, z: float, mat_name := "metal") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := Vector3(w, h, d)
	var bm: BoxMesh = _box_mesh_cache.get(key)
	if bm == null:
		bm = BoxMesh.new()
		bm.size = key
		_box_mesh_cache[key] = bm
	mi.mesh = bm
	mi.material_override = MAT()[mat_name]
	mi.position = Vector3(x, y, z)
	return mi


static func cyl(r1: float, r2: float, length: float, x: float, y: float, z: float,
		mat_name := "metal", axis := "z") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := Vector3(r1, r2, length)
	var cm: CylinderMesh = _cyl_mesh_cache.get(key)
	if cm == null:
		cm = CylinderMesh.new()
		cm.top_radius = r1
		cm.bottom_radius = r2
		cm.height = length
		cm.radial_segments = 16
		_cyl_mesh_cache[key] = cm
	mi.mesh = cm
	mi.material_override = MAT()[mat_name]
	if axis == "z":
		mi.rotation.x = PI / 2.0
	elif axis == "x":
		mi.rotation.z = PI / 2.0
	# axis == "y":CylinderMesh 默认沿 y 轴,无需旋转
	mi.position = Vector3(x, y, z)
	return mi


## 两端开口的镜筒圆柱(无顶/底盖):保证开镜时视线能真正穿过镜筒看到目镜/PIP 画面,
## 而不是被 CylinderMesh 的端盖挡成一块实心圆片。
static func cyl_open(r1: float, r2: float, length: float, x: float, y: float, z: float,
		mat_name := "dark", axis := "z") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r2
	cm.height = length
	cm.radial_segments = 20
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.material_override = MAT()[mat_name]
	if axis == "z":
		mi.rotation.x = PI / 2.0
	elif axis == "x":
		mi.rotation.z = PI / 2.0
	mi.position = Vector3(x, y, z)
	return mi


## 圆形镂空环(TorusMesh,孔洞沿 z 轴即枪械瞄具视轴)
static func ring(inner: float, outer: float, x: float, y: float, z: float, mat_name := "dark") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := Vector2(inner, outer)
	var tm: TorusMesh = _torus_mesh_cache.get(key)
	if tm == null:
		tm = TorusMesh.new()
		tm.inner_radius = inner
		tm.outer_radius = outer
		tm.rings = 24
		tm.ring_segments = 10
		_torus_mesh_cache[key] = tm
	mi.mesh = tm
	mi.material_override = MAT()[mat_name]
	mi.rotation.x = PI / 2.0   # Torus 默认孔洞沿 Y;转 90° 后沿 Z(枪管/视线方向)
	mi.position = Vector3(x, y, z)
	return mi


## DMR 瞄准镜完整镜筒:主管体 + 目镜筒 + 物镜筒 + 箍环/调节钮/镜座。
## 镜体为实体低模管状,ADS 后枪身由 2D 镜罩接管,不会遮挡开镜视野。
static func _hollow_dmr_scope(g: Node3D, y: float, z_front: float, z_rear: float, mat := "dark") -> void:
	var s := Node3D.new()
	s.name = "StockOptic"   # 与改装光学镜互斥:装备红点/全息时隐藏此原厂镜
	g.add_child(s)
	var zc := (z_rear + z_front) * 0.5
	var tube_len: float = absf(z_rear - z_front)
	# 镜筒主体(沿视线方向)
	s.add_child(cyl(0.0155, 0.0155, tube_len, 0, y, zc, mat, "z"))
	# 目镜筒(靠近眼睛一端)+ 目镜箍环
	s.add_child(cyl(0.019, 0.016, 0.035, 0, y, z_rear + 0.012, "poly", "z"))
	s.add_child(ring(0.0155, 0.0205, 0, y, z_rear + 0.026, "metal"))
	# 物镜筒(前端口径略大)+ 物镜箍环
	s.add_child(cyl(0.023, 0.017, 0.05, 0, y, z_front - 0.015, "poly", "z"))
	s.add_child(ring(0.019, 0.024, 0, y, z_front - 0.036, "metal"))
	# 顶部调节钮 + 底部镜座
	s.add_child(cyl(0.008, 0.008, 0.018, 0, y + 0.021, zc, mat, "y"))
	s.add_child(cyl(0.01, 0.01, 0.022, 0, y - 0.023, zc, mat, "y"))


## 顶部皮卡汀尼导轨:安装面(齿顶)在 rail_y,横跨 z0..z1(自动排序);底座+分段齿
static func _rail(g: Node3D, rail_y: float, z0: float, z1: float, w := 0.026, mat := "dark") -> void:
	var za := minf(z0, z1)
	var zb := maxf(z0, z1)
	var d := zb - za
	var zc := (za + zb) * 0.5
	g.add_child(box(w + 0.004, 0.008, d, 0, rail_y - 0.009, zc, mat))      # 导轨底座
	var step := 0.04
	var n: int = maxi(1, int(d / step))
	for i in n:
		g.add_child(box(w, 0.005, step * 0.5, 0, rail_y - 0.0025, za + (i + 0.5) * step, mat))  # 齿


## 扳机护圈(闭合矩形环)+ 扳机;扳机命名 "StockTrigger" 供改装替换
## y/z = 扳机中心;护圈宽 w(默认 0.05)
static func _trigger(g: Node3D, y: float, z: float, w := 0.05, mat := "dark") -> void:
	var top := y + 0.012
	var bot := y - 0.026
	var h := top - bot
	var fz0 := z - 0.024
	var fz1 := z + 0.028
	var fd := fz1 - fz0
	var fzc := (fz0 + fz1) * 0.5
	var cy := (top + bot) * 0.5
	g.add_child(box(0.006, h, fd, -w * 0.5, cy, fzc, mat))     # 左壁
	g.add_child(box(0.006, h, fd, w * 0.5, cy, fzc, mat))      # 右壁
	g.add_child(box(w, 0.007, 0.006, 0, bot, fz0, mat))        # 前下缘
	g.add_child(box(w, 0.007, 0.006, 0, bot, fz1, mat))        # 后下缘
	var trig := box(0.008, 0.03, 0.006, 0, y - 0.002, z - 0.004, mat)
	trig.rotation.x = 0.2
	trig.name = "StockTrigger"
	g.add_child(trig)                                          # 扳机


## 拉机柄:柄杆 + 柄头;meta "bolt"(Node3D,供换弹上膛动画驱动);side=+1 右/-1 左
static func _bolt(g: Node3D, x: float, y: float, z: float, side := 1.0, mat := "dark") -> void:
	var b := Node3D.new()
	b.position = Vector3(x, y, z)
	b.add_child(cyl(0.006, 0.006, 0.022, side * 0.008, 0, 0, mat, "x"))   # 柄杆
	b.add_child(box(0.013, 0.015, 0.028, side * 0.021, 0, 0, mat))        # 柄头
	g.add_child(b)
	g.set_meta("bolt", b)


## 弹链供弹机枪的受弹机盖:独立 Node3D 动画件(绕根部 X 轴前掀开盖)。
## CoverLatch 为手部抓握点,机盖旋转后随动,保证换弹手不会抓空气。
static func _feed_cover(g: Node3D, y: float, z_center: float, length: float, w := 0.052, mat := "dark") -> Node3D:
	var cover := Node3D.new()
	cover.name = "FeedCover"
	# 铰链根位于机匣后缘:绕 +X 旋转时只有盖体前端向 -Z 方向掀开,后缘不穿入机匣。
	cover.position = Vector3(0, y, z_center + length * 0.5)
	cover.add_child(box(w, 0.018, length, 0, 0, -length * 0.5, mat))
	cover.add_child(box(w - 0.012, 0.007, length - 0.06, 0, 0.0105, -length * 0.5, "metal"))  # 顶部加强筋
	var latch := box(0.016, 0.016, 0.036, 0, 0.017, -length * 0.66, mat)
	latch.name = "CoverLatch"
	cover.add_child(latch)
	g.add_child(cover)
	g.set_meta("cover", cover)
	g.set_meta("cover_latch", latch)
	return cover


## 弹链尾:从弹链箱口伸入受弹机端口的一段可见弹链(铜色弹壳 + 深色链节)。
## 挂在弹链箱(meta "mag")节点下,随箱体拆卸/装填移动,由换弹控制器独立调整入槽姿态。
static func _add_belt_tail(mag: Node3D, a: Vector3, b: Vector3, c: Vector3, links := 7) -> Node3D:
	var belt := Node3D.new()
	belt.name = "BeltTail"
	for i in links:
		var t := float(i) / float(maxi(1, links - 1))
		var ab := a.lerp(b, t)
		var bc := b.lerp(c, t)
		var p := ab.lerp(bc, t)
		belt.add_child(box(0.017, 0.02, 0.042, p.x, p.y, p.z, "brass" if i % 2 == 0 else "dark"))
	mag.add_child(belt)
	return belt


## 侧挂弹链箱(meta "mag") + 弹链尾(BeltTail) + 供弹口参考点(meta "feed_port")。
## side=-1 挂左侧 / +1 挂右侧;弹链从箱口上缘弧线进入 port_pos 的受弹机供弹槽。
static func _side_belt_feed(g: Node3D, side: float, box_pos: Vector3, box_size: Vector3, port_pos: Vector3, mat := "olive") -> MeshInstance3D:
	var mag := box(box_size.x, box_size.y, box_size.z, box_pos.x, box_pos.y, box_pos.z, mat)
	# 弹链箱上盖锁扣/提手
	mag.add_child(box(0.024, 0.014, 0.05, -side * box_size.x * 0.28, box_size.y * 0.5 + 0.009, -box_size.z * 0.18, "dark"))
	var from := box_pos + Vector3(-side * box_size.x * 0.34, box_size.y * 0.42, 0.0)
	var mid := (from + port_pos) * 0.5 + Vector3(side * 0.02, 0.052, 0.01)
	var tail := _add_belt_tail(mag, from - box_pos, mid - box_pos, port_pos - box_pos, 7)
	g.add_child(mag)
	g.set_meta("mag", mag)
	g.set_meta("belt", tail)
	var port := Node3D.new()
	port.name = "FeedPort"
	port.position = port_pos
	g.add_child(port)
	g.set_meta("feed_port", port)
	return mag


## 手枪式握把:顶端(y_top)枢轴后倾,顶端贴合机匣底(消除握把悬空);返回枢轴供 add_child
static func _grip(w: float, h: float, d: float, x: float, y_top: float, z: float, mat := "poly", tilt := 0.32) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, y_top, z)
	pivot.rotation.x = tilt
	pivot.add_child(box(w, h, d, 0, -h * 0.5, 0, mat))
	return pivot


## 直弹匣(BoxMesh,meta "mag";顶部 y_top 插入弹匣井,可选前倾)
static func _mag_straight(g: Node3D, w: float, h: float, d: float, x: float, y_top: float, z: float, mat := "dark", tilt := 0.0) -> MeshInstance3D:
	var m := box(w, h, d, x, y_top - h * 0.5, z, mat)
	if tilt != 0.0:
		m.rotation.x = tilt
	g.add_child(m)
	g.set_meta("mag", m)
	return m


## 弯弹匣(AK 弧度:三段前倾;meta "mag" Node3D;顶部 y_top 贴合机匣底)
static func _curved_mag(g: Node3D, w: float, x: float, y_top: float, z: float, mat := "brass") -> void:
	var root := Node3D.new()
	root.position = Vector3(x, y_top, z)
	root.add_child(box(w, 0.07, 0.052, 0, -0.032, 0.004, mat))          # 上段(竖直插入弹匣井)
	var s2 := box(w * 0.95, 0.07, 0.05, 0, -0.097, -0.012, mat)
	s2.rotation.x = 0.32
	root.add_child(s2)
	var s3 := box(w * 0.88, 0.06, 0.046, 0, -0.152, -0.048, mat)
	s3.rotation.x = 0.6
	root.add_child(s3)
	g.add_child(root)
	g.set_meta("mag", root)


## 机械瞄具:前准星柱(带底座坐于枪管)+ 后缺口双耳(带底座贴合导轨);视轴 = sy
static func _irons(g: Node3D, sy: float, fz: float, rz: float, ph: float, barrel_y := 0.03) -> void:
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	# 前准星底座:自枪管(barrel_y)向上延伸,顶端顶住准星柱底(消除悬空)
	var base_h := (sy - ph) - barrel_y + 0.006
	if base_h < 0.018:
		base_h = 0.018
	ir.add_child(box(0.022, base_h, 0.02, 0, barrel_y + base_h * 0.5, fz, "dark"))
	var post := box(0.009, ph, 0.011, 0, sy - ph * 0.5, fz, "dark")
	post.name = "IronsFront"
	ir.add_child(post)
	# 后照门:底座自机匣高度(barrel_y)向上延伸到耳底,双耳再向上(消除悬空)
	var rb_h := (sy - 0.02) - barrel_y
	if rb_h < 0.012:
		rb_h = 0.012
	ir.add_child(box(0.024, rb_h, 0.02, 0, barrel_y + rb_h * 0.5, rz, "dark"))
	var el := box(0.005, 0.02, 0.016, -0.009, sy - 0.01, rz, "dark")
	el.name = "IronsRearL"
	ir.add_child(el)
	var er := box(0.005, 0.02, 0.016, 0.009, sy - 0.01, rz, "dark")
	er.name = "IronsRearR"
	ir.add_child(er)


## 狙击镜 3D 分划(绑定在镜体目镜节点下,随枪械 Sway/呼吸/后坐同步运动)。
## 采用黑线+白描边两层薄片,保证明亮天空与暗色目标前都清晰可见。
static func _scope_reticle(eye: Node3D) -> void:
	var ret := Node3D.new()
	ret.name = "RetCross"
	var half_len := 0.0165
	var t := 0.00024                              # 细分划:约 4~5px @1080p,不再遮挡目标
	var dark_mat: StandardMaterial3D = MAT()["ret_dark"]
	var light_mat: StandardMaterial3D = MAT()["ret_light"]
	# 完整连续十字:横/竖两条细线直接穿过中心,不留缺口,便于精确瞄准。
	var lh := box(half_len * 2.0, t * 1.8, t * 1.8, 0, 0, 0.00018, "ret_light")
	lh.material_override = light_mat
	ret.add_child(lh)
	var dh := box(half_len * 2.0, t, t, 0, 0, 0, "ret_dark")
	dh.material_override = dark_mat
	ret.add_child(dh)
	var lv := box(t * 1.8, half_len * 2.0, t * 1.8, 0, 0, 0.00018, "ret_light")
	lv.material_override = light_mat
	ret.add_child(lv)
	var dv := box(t, half_len * 2.0, t, 0, 0, 0, "ret_dark")
	dv.material_override = dark_mat
	ret.add_child(dv)
	eye.add_child(ret)


## 狙击镜:镜筒 + 前后支架(自机匣顶 base_y 托起)+ 半透物镜/目镜;视轴 = y
## 目镜/3D 分划固定位于枪械局部 z=0.06:ADS 时距眼点约 0.09m,
## 在 vm_camera 60° FOV 下投影直径约 54% 屏高,镜体边界真实包围镜内 PIP 画面。
static func _scope(g: Node3D, y: float, z: float, base_y: float) -> void:
	var s := Node3D.new()
	s.name = "StockOptic"
	g.add_child(s)
	var body := Node3D.new()
	body.name = "ScopeTubeBody"
	s.add_child(body)
	body.add_child(cyl(0.024, 0.030, 0.22, 0, y, z - 0.03, "scope_black"))      # 镜筒(后粗前细,两端封口,非 ADS 完整实体)
	var mh := (y - 0.021) - base_y
	if mh < 0.004:
		mh = 0.004
	body.add_child(cyl(0.019, 0.019, mh, 0, base_y + mh * 0.5, z + 0.05, "dark"))   # 前支架
	body.add_child(cyl(0.019, 0.019, mh, 0, base_y + mh * 0.5, z - 0.11, "dark"))   # 后支架
	body.add_child(cyl(0.030, 0.027, 0.03, 0, y, z - 0.14, "scope_black"))    # 物镜(非 ADS 黑实体)
	body.add_child(cyl(0.005, 0.005, 0.02, 0, y + 0.03, z - 0.03, "dark", "y"))  # 调节钮
	# 目镜:黑玻璃(非 ADS)/ 高透玻璃(ADS)/ 细黑镜口圈 / 连续细十字分划
	var eye := Node3D.new()
	eye.name = "ScopeEye"
	eye.position = Vector3(0, y, 0.06)
	s.add_child(eye)
	eye.add_child(ring(0.0280, 0.0296, 0, 0, -0.0035, "scope_black"))            # 目镜外圈(细)
	var black_lens := cyl(0.028, 0.028, 0.012, 0, 0, 0, "scope_black")
	black_lens.name = "ScopeLensBlack"
	black_lens.position.z = 0.0005
	eye.add_child(black_lens)
	var clear_lens := cyl(0.028, 0.028, 0.012, 0, 0, 0, "lens_clear")
	clear_lens.name = "ScopeLensClear"
	clear_lens.position.z = -0.0005
	clear_lens.visible = false
	eye.add_child(clear_lens)
	_scope_reticle(eye)
	var reticle: Node3D = eye.get_node_or_null("RetCross")
	if reticle != null:
		reticle.visible = false
	g.set_meta("scope_eye", eye)
	g.set_meta("scope_eye_radius", 0.028)
	g.set_meta("scope_tube", body)
	g.set_meta("scope_lens_black", black_lens)
	g.set_meta("scope_lens_clear", clear_lens)
	g.set_meta("scope_reticle", reticle)

static func _simple_scope(g: Node3D, y: float, zc: float, length: float, base_y: float, tube_r := 0.019) -> void:
	var s := Node3D.new()
	s.name = "StockOptic"
	g.add_child(s)
	var body := Node3D.new()
	body.name = "ScopeTubeBody"
	s.add_child(body)
	body.add_child(cyl(tube_r, tube_r * 1.35, length, 0, y, zc, "scope_black"))
	var z_front := zc - length * 0.5
	var z_rear := zc + length * 0.5
	# 物镜端收口
	body.add_child(cyl(tube_r * 1.55, tube_r * 1.2, 0.028, 0, y, z_front - 0.01, "scope_black"))
	body.add_child(cyl(tube_r * 1.15, tube_r * 1.15, 0.006, 0, y, z_front - 0.024, "scope_black"))
	# 镜座(与机匣顶 base_y 连接)
	var mh := (y - tube_r * 1.35) - base_y
	if mh < 0.004:
		mh = 0.004
	body.add_child(cyl(0.018, 0.018, mh, 0, base_y + mh * 0.5, zc + 0.06, "dark"))
	body.add_child(cyl(0.018, 0.018, mh, 0, base_y + mh * 0.5, zc - 0.10, "dark"))
	# 目镜端:开口收口喇叭 + 玻璃 + 3D 分划
	var eye_z := 0.06
	var cup_len := maxf(0.018, absf(eye_z - z_rear) + 0.018)
	body.add_child(cyl(tube_r * 1.35, 0.028, cup_len, 0, y, (z_rear + eye_z) * 0.5, "scope_black"))
	var eye := Node3D.new()
	eye.name = "ScopeEye"
	eye.position = Vector3(0, y, eye_z)
	s.add_child(eye)
	eye.add_child(ring(0.0280, 0.0296, 0, 0, -0.0035, "scope_black"))
	var black_lens := cyl(0.028, 0.028, 0.012, 0, 0, 0, "scope_black")
	black_lens.name = "ScopeLensBlack"
	black_lens.position.z = 0.0005
	eye.add_child(black_lens)
	var clear_lens := cyl(0.028, 0.028, 0.012, 0, 0, 0, "lens_clear")
	clear_lens.name = "ScopeLensClear"
	clear_lens.position.z = -0.0005
	clear_lens.visible = false
	eye.add_child(clear_lens)
	_scope_reticle(eye)
	var reticle: Node3D = eye.get_node_or_null("RetCross")
	if reticle != null:
		reticle.visible = false
	g.set_meta("scope_eye", eye)
	g.set_meta("scope_eye_radius", 0.028)
	g.set_meta("scope_tube", body)
	g.set_meta("scope_lens_black", black_lens)
	g.set_meta("scope_lens_clear", clear_lens)
	g.set_meta("scope_reticle", reticle)

## ============ 各武器构建 ============
static func _build(id: String, g: Node3D) -> void:
	match id:
		"m4":
			# 机匣(底 = 弹匣井/扳机护圈顶;顶承接导轨)+ 上机匣前伸
			g.add_child(box(0.052, 0.068, 0.34, 0, 0.009, -0.06))
			g.add_child(box(0.048, 0.026, 0.46, 0, 0.058, -0.16, "dark"))
			_rail(g, 0.086, 0.05, -0.38)
			# 护木(圆柱贴合机匣前缘) + 枪管 + 制退器
			g.add_child(cyl(0.026, 0.03, 0.3, 0, 0.024, -0.42))
			g.add_child(cyl(0.011, 0.013, 0.48, 0, 0.024, -0.56))
			g.add_child(cyl(0.017, 0.019, 0.05, 0, 0.024, -0.775, "dark"))
			# 枪托(斜,顶端贴合机匣尾)+ 托垫 + 托腮
			g.add_child(_grip(0.042, 0.09, 0.19, 0, 0.003, 0.17, "poly", 0.12))
			g.add_child(box(0.046, 0.1, 0.022, 0, 0.0, 0.27, "dark"))
			g.add_child(box(0.044, 0.03, 0.14, 0, 0.045, 0.16, "dark"))
			# 握把(顶端贴合机匣底) + 扳机护圈(贴合机匣底)
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.04, "poly", 0.38))
			_trigger(g, -0.037, 0.01)
			# 弹匣(顶部插入弹匣井)
			_mag_straight(g, 0.036, 0.13, 0.06, 0, -0.024, -0.09, "dark", 0.12)
			# 抛壳窗 + 弹匣释放钮 + 拉机柄(右后)
			g.add_child(box(0.004, 0.02, 0.05, 0.027, 0.03, -0.06, "dark"))
			g.add_child(box(0.01, 0.012, 0.018, 0.027, -0.012, -0.06, "dark"))
			_bolt(g, 0.028, 0.045, 0.06, 1.0)
			# 机械瞄具(视轴 = sight_y 0.108)
			_irons(g, 0.108, -0.55, 0.09, 0.06, 0.024)
		"ak":
			g.add_child(box(0.054, 0.072, 0.34, 0, 0.012, -0.05))
			g.add_child(box(0.05, 0.024, 0.3, 0, 0.058, -0.07, "dark"))
			# 木护木(贴合机匣前缘,上下两段夹住枪管)
			g.add_child(cyl(0.024, 0.03, 0.28, 0, 0.02, -0.36, "wood"))
			g.add_child(box(0.048, 0.04, 0.14, 0, 0.048, -0.33, "wood"))
			# 枪管 + 准星座 + 消焰器
			g.add_child(cyl(0.012, 0.014, 0.46, 0, 0.028, -0.59))
			g.add_child(box(0.014, 0.04, 0.016, 0, 0.05, -0.58, "dark"))
			g.add_child(cyl(0.016, 0.019, 0.05, 0, 0.028, -0.835, "dark"))
			# 木枪托(斜) + 握把
			g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.008, 0.18, "wood", 0.16))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.045, "wood", 0.42))
			_trigger(g, -0.036, 0.02)
			# 弯弹匣(前挂后卡;顶部贴合机匣底)
			_curved_mag(g, 0.038, 0, -0.023, -0.1)
			# 拉机柄(右侧大柄)
			_bolt(g, 0.032, 0.035, -0.02, 1.0)
			# 机械瞄具(视轴 = sight_y 0.104)
			_irons(g, 0.104, -0.56, 0.05, 0.06, 0.028)
		"scar":
			g.add_child(box(0.052, 0.076, 0.36, 0, 0.016, -0.07, "tan"))
			g.add_child(box(0.048, 0.026, 0.48, 0, 0.064, -0.2, "dark"))
			_rail(g, 0.086, 0.02, -0.44)
			g.add_child(cyl(0.025, 0.029, 0.28, 0, 0.02, -0.42, "tan"))
			g.add_child(cyl(0.011, 0.013, 0.4, 0, 0.024, -0.6))
			g.add_child(cyl(0.016, 0.019, 0.05, 0, 0.024, -0.8, "dark"))
			# 折叠枪托(带铰链座)
			g.add_child(box(0.02, 0.06, 0.05, 0, 0.0, 0.13, "dark"))
			g.add_child(_grip(0.04, 0.085, 0.19, 0, -0.003, 0.21, "tan", 0.1))
			g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "dark"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.026, 0.04, "dark", 0.36))
			_trigger(g, -0.038, 0.01)
			_mag_straight(g, 0.038, 0.11, 0.062, 0, -0.022, -0.1, "tan", 0.1)
			# 左侧拉机柄(SCAR 特征)
			_bolt(g, -0.028, 0.04, -0.02, -1.0)
			# 机械瞄具(视轴 = sight_y 0.112)
			_irons(g, 0.112, -0.58, 0.09, 0.06, 0.024)
		"aug":
			# 无托:长机匣一体(枪托并入机匣)
			g.add_child(box(0.05, 0.085, 0.52, 0, 0.02, 0.02, "olive"))
			g.add_child(box(0.046, 0.03, 0.5, 0, 0.068, 0.0, "dark"))
			# 前握把(可折,顶端贴合机匣底)
			g.add_child(_grip(0.03, 0.07, 0.04, 0, -0.018, -0.2, "olive", 0.3))
			g.add_child(cyl(0.012, 0.014, 0.42, 0, 0.026, -0.45))
			g.add_child(cyl(0.015, 0.018, 0.05, 0, 0.026, -0.67, "dark"))
			# 后握把(扳机后方) + 扳机(靠前)
			g.add_child(_grip(0.034, 0.09, 0.05, 0, -0.024, 0.14, "olive", 0.3))
			_trigger(g, -0.036, -0.06)
			# 透明弹匣(后置,顶部插入机匣)
			_mag_straight(g, 0.036, 0.12, 0.055, 0, -0.022, 0.06, "olive", -0.12)
			# 枪托左侧拉机柄
			_bolt(g, -0.028, 0.05, 0.12, -1.0)
			# 一体提把(保留外观) + 机械瞄具(视轴 = sight_y 0.125)
			g.add_child(box(0.02, 0.035, 0.2, 0, 0.095, -0.05, "dark"))
			_irons(g, 0.125, -0.52, 0.17, 0.045, 0.026)
		"mp5":
			# 细机匣 + 海军托
			g.add_child(box(0.044, 0.07, 0.3, 0, 0.016, -0.05))
			g.add_child(cyl(0.024, 0.026, 0.16, 0, 0.02, -0.28, "dark"))
			g.add_child(cyl(0.009, 0.01, 0.2, 0, 0.024, -0.4))
			g.add_child(cyl(0.017, 0.017, 0.04, 0, 0.024, -0.5, "dark"))
			g.add_child(_grip(0.038, 0.075, 0.15, 0, -0.003, 0.16, "dark", 0.08))
			g.add_child(box(0.042, 0.08, 0.02, 0, -0.004, 0.24, "dark"))
			g.add_child(_grip(0.03, 0.09, 0.04, 0, -0.02, 0.04, "poly", 0.4))
			_trigger(g, -0.034, 0.01)
			# 弧形弹匣(顶部贴合机匣底)
			_curved_mag(g, 0.032, 0, -0.02, -0.1, "dark")
			# 桨式弹匣释放(右) + 左侧拉机柄
			g.add_child(box(0.01, 0.03, 0.03, 0.024, -0.04, -0.06, "dark"))
			_bolt(g, -0.026, 0.045, -0.14, -1.0)
			# 机械瞄具(视轴 = sight_y 0.09)
			_irons(g, 0.09, -0.36, 0.1, 0.05, 0.024)
		"ump":
			g.add_child(box(0.048, 0.075, 0.3, 0, 0.018, -0.04, "poly"))
			g.add_child(cyl(0.026, 0.028, 0.14, 0, 0.02, -0.24, "dark"))
			g.add_child(cyl(0.01, 0.011, 0.16, 0, 0.022, -0.34))
			g.add_child(cyl(0.015, 0.016, 0.035, 0, 0.022, -0.44, "dark"))
			g.add_child(_grip(0.04, 0.08, 0.15, 0, -0.003, 0.16, "poly", 0.06))
			g.add_child(box(0.044, 0.085, 0.02, 0, -0.003, 0.235, "poly"))
			g.add_child(_grip(0.032, 0.095, 0.045, 0, -0.02, 0.045, "poly", 0.38))
			_trigger(g, -0.034, 0.02)
			# .45 宽直弹匣
			_mag_straight(g, 0.04, 0.12, 0.06, 0, -0.02, -0.05, "dark")
			# 左侧释放杆 + 空挂钮
			g.add_child(box(0.008, 0.03, 0.04, -0.027, -0.02, -0.02, "dark"))
			_bolt(g, -0.027, 0.045, -0.08, -1.0)
			# 机械瞄具(视轴 = sight_y 0.1)
			_irons(g, 0.1, -0.35, 0.09, 0.05, 0.022)
		"p90":
			# 无托一体框架
			g.add_child(box(0.05, 0.07, 0.34, 0, 0.0, -0.02, "poly"))
			# 水平顶置弹匣(半透明长条)
			var mag_p := box(0.042, 0.024, 0.3, 0, 0.048, -0.06, "tan")
			g.add_child(mag_p); g.set_meta("mag", mag_p)
			g.add_child(box(0.044, 0.012, 0.31, 0, 0.036, -0.06, "dark"))
			# 下弯枪身 + 前握把槽(顶端贴合框架底)
			g.add_child(_grip(0.034, 0.06, 0.08, 0, -0.034, -0.12, "poly", 0.5))
			g.add_child(_grip(0.032, 0.08, 0.05, 0, -0.035, 0.08, "poly", 0.35))
			_trigger(g, -0.033, 0.02)
			g.add_child(cyl(0.009, 0.01, 0.24, 0, 0.01, -0.2))
			g.add_child(cyl(0.012, 0.013, 0.04, 0, 0.01, -0.33, "dark"))
			# 枪托左侧拉机柄
			_bolt(g, -0.026, 0.03, 0.12, -1.0)
			# 机械瞄具(视轴 = sight_y 0.078)
			_irons(g, 0.078, -0.18, 0.09, 0.032, 0.01)
		"m249":
			# 大机匣 + 顶部受弹机盖(独立动画件)
			g.add_child(box(0.062, 0.1, 0.44, 0, 0.02, -0.08))
			var m249_cover := _feed_cover(g, 0.085, -0.1, 0.46)
			# M249 顶部导轨装在受弹机盖上:作为 cover 子节点,开盖时随盖翻转,不穿模
			_rail(m249_cover, 0.021, -0.03, -0.47)
			# 弹链箱(左侧挂)+ 可见弹链尾 → 受弹机左供弹口
			_side_belt_feed(g, -1.0, Vector3(-0.062, -0.075, -0.12), Vector3(0.075, 0.11, 0.13),
				Vector3(-0.026, -0.015, -0.16), "olive")
			# 护木 + 枪管 + 两脚架
			g.add_child(cyl(0.028, 0.032, 0.26, 0, 0.02, -0.42, "dark"))
			g.add_child(cyl(0.014, 0.016, 0.4, 0, 0.028, -0.68))
			g.add_child(cyl(0.02, 0.022, 0.06, 0, 0.028, -0.875, "dark"))
			g.add_child(box(0.008, 0.14, 0.008, -0.03, -0.075, -0.5, "dark"))
			g.add_child(box(0.008, 0.14, 0.008, 0.03, -0.075, -0.5, "dark"))
			# 枪托 + 握把
			g.add_child(_grip(0.048, 0.1, 0.18, 0, -0.008, 0.19, "poly", 0.1))
			g.add_child(box(0.052, 0.1, 0.02, 0, 0.0, 0.28, "poly"))
			g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.03, 0.05, "poly", 0.35))
			_trigger(g, -0.04, 0.02)
			_bolt(g, 0.035, 0.03, 0.02, 1.0)
			# 机械瞄具(视轴 = sight_y 0.125)
			_irons(g, 0.125, -0.6, 0.1, 0.055, 0.028)
		"pkm":
			g.add_child(box(0.062, 0.1, 0.46, 0, 0.02, -0.06))
			_feed_cover(g, 0.082, -0.08, 0.48)
			# 弹链箱(右侧挂,PKM 特征)+ 可见弹链尾 → 受弹机右供弹口
			_side_belt_feed(g, 1.0, Vector3(0.062, -0.075, -0.1), Vector3(0.075, 0.11, 0.13),
				Vector3(0.026, -0.015, -0.15), "dark")
			g.add_child(cyl(0.028, 0.032, 0.28, 0, 0.02, -0.42, "wood"))
			g.add_child(cyl(0.015, 0.017, 0.42, 0, 0.028, -0.7))
			g.add_child(cyl(0.02, 0.023, 0.06, 0, 0.028, -0.9, "dark"))
			g.add_child(_grip(0.048, 0.1, 0.19, 0, -0.008, 0.19, "wood", 0.12))
			g.add_child(box(0.052, 0.1, 0.02, 0, 0.0, 0.29, "wood"))
			g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.03, 0.05, "wood", 0.38))
			_trigger(g, -0.04, 0.02)
			_bolt(g, 0.035, 0.03, 0.04, 1.0)
			# 机械瞄具(视轴 = sight_y 0.122)
			_irons(g, 0.122, -0.6, 0.1, 0.055, 0.028)
		"rpd":
			g.add_child(box(0.056, 0.085, 0.4, 0, 0.018, -0.06))
			g.add_child(box(0.052, 0.024, 0.4, 0, 0.068, -0.08, "dark"))
			# 弹鼓(左侧大圆鼓):外包 Node3D 作为动画根,网格自转 90° 横置,
			# 保证换弹时根节点基准旋转为 0,不会出现 90° 翻转。
			var drum_root := Node3D.new()
			drum_root.position = Vector3(-0.048, -0.06, -0.08)
			drum_root.add_child(cyl(0.075, 0.075, 0.05, 0, 0, 0, "brass", "x"))
			drum_root.add_child(cyl(0.03, 0.036, 0.035, 0.026, 0.012, 0.0, "dark", "x"))  # 弹鼓接口颈
			drum_root.add_child(box(0.012, 0.02, 0.032, -0.016, 0.052, 0.0, "dark"))       # 鼓面锁扣
			g.add_child(drum_root)
			g.set_meta("mag", drum_root)
			g.add_child(box(0.024, 0.03, 0.05, -0.048, -0.028, -0.08, "dark"))             # 机匣侧弹鼓挂座
			g.add_child(cyl(0.026, 0.03, 0.28, 0, 0.02, -0.39, "wood"))
			g.add_child(cyl(0.013, 0.015, 0.42, 0, 0.026, -0.68))
			g.add_child(cyl(0.018, 0.021, 0.05, 0, 0.026, -0.875, "dark"))
			g.add_child(_grip(0.044, 0.095, 0.19, 0, -0.006, 0.18, "wood", 0.14))
			g.add_child(box(0.048, 0.095, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.01)
			_bolt(g, 0.032, 0.035, 0.0, 1.0)
			# 机械瞄具(视轴 = sight_y 0.115)
			_irons(g, 0.115, -0.58, 0.1, 0.055, 0.026)
		"awm":
			# 栓动狙:长枪管 + 大镜 + 栓柄
			g.add_child(box(0.05, 0.075, 0.42, 0, 0.012, -0.04, "olive"))
			g.add_child(cyl(0.013, 0.017, 0.6, 0, 0.03, -0.55))
			g.add_child(cyl(0.02, 0.023, 0.08, 0, 0.03, -0.885, "dark"))
			# 贴腮 + 枪托
			g.add_child(box(0.044, 0.06, 0.14, 0, 0.05, 0.12, "olive"))
			g.add_child(_grip(0.046, 0.1, 0.18, 0, -0.008, 0.2, "olive", 0.12))
			g.add_child(box(0.05, 0.1, 0.02, 0, 0.0, 0.29, "olive"))
			g.add_child(_grip(0.034, 0.09, 0.045, 0, -0.024, 0.05, "olive", 0.42))
			_trigger(g, -0.036, 0.03)
			# 弹匣(底部 5 发)
			_mag_straight(g, 0.036, 0.09, 0.08, 0, -0.024, -0.08, "dark")
			# 栓柄(尾部大球)
			var bolt_h := Node3D.new()
			bolt_h.position = Vector3(0.03, 0.05, 0.1)
			bolt_h.add_child(cyl(0.006, 0.006, 0.05, 0, 0.02, 0, "chrome", "y"))
			bolt_h.add_child(cyl(0.014, 0.014, 0.02, 0, 0.045, 0, "chrome"))
			g.add_child(bolt_h)
			g.set_meta("bolt", bolt_h)
			_scope(g, 0.115, -0.06, 0.0495)
		"m24":
			g.add_child(box(0.05, 0.075, 0.44, 0, 0.012, -0.05, "wood"))
			g.add_child(cyl(0.013, 0.016, 0.62, 0, 0.028, -0.55))
			g.add_child(cyl(0.018, 0.021, 0.06, 0, 0.028, -0.83, "dark"))
			g.add_child(box(0.044, 0.06, 0.14, 0, 0.048, 0.12, "wood"))
			g.add_child(_grip(0.046, 0.1, 0.18, 0, -0.008, 0.2, "wood", 0.12))
			g.add_child(box(0.05, 0.1, 0.02, 0, 0.0, 0.29, "wood"))
			g.add_child(_grip(0.034, 0.09, 0.045, 0, -0.024, 0.05, "wood", 0.42))
			_trigger(g, -0.036, 0.03)
			# 内置弹仓底板
			g.add_child(box(0.03, 0.02, 0.09, 0, -0.05, -0.05, "dark"))
			# 栓柄
			var bolt_h2 := Node3D.new()
			bolt_h2.position = Vector3(0.03, 0.05, 0.1)
			bolt_h2.add_child(cyl(0.006, 0.006, 0.05, 0, 0.02, 0, "dark", "y"))
			bolt_h2.add_child(cyl(0.013, 0.013, 0.02, 0, 0.045, 0, "dark"))
			g.add_child(bolt_h2)
			g.set_meta("bolt", bolt_h2)
			_scope(g, 0.112, -0.06, 0.0495)
		"svd":
			# AK 式机匣 + 长枪管 + 弯弹匣 + PSO 镜
			g.add_child(box(0.052, 0.07, 0.38, 0, 0.015, -0.04, "wood"))
			g.add_child(cyl(0.011, 0.013, 0.64, 0, 0.026, -0.545))
			g.add_child(cyl(0.015, 0.018, 0.06, 0, 0.026, -0.81, "dark"))
			g.add_child(box(0.014, 0.05, 0.014, 0, 0.055, -0.6, "dark"))
			g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.008, 0.18, "wood", 0.16))
			g.add_child(box(0.04, 0.05, 0.06, 0, 0.045, 0.12, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.02, 0.045, "wood", 0.42))
			_trigger(g, -0.034, 0.02)
			_curved_mag(g, 0.036, 0, -0.02, -0.1)
			_bolt(g, 0.032, 0.035, -0.02, 1.0)
			# PSO 侧轨镜
			g.add_child(box(0.012, 0.03, 0.1, -0.03, 0.06, -0.04, "dark"))
			_scope(g, 0.115, -0.02, 0.0495)
		"m1014":
			# 霰弹枪:机匣 + 管状弹仓
			g.add_child(box(0.05, 0.08, 0.32, 0, 0.02, -0.02))
			g.add_child(cyl(0.014, 0.016, 0.44, 0, 0.045, -0.4))
			g.add_child(cyl(0.012, 0.012, 0.4, 0, -0.005, -0.38, "dark"))
			g.add_child(cyl(0.019, 0.02, 0.03, 0, 0.045, -0.625, "dark"))
			# 泵动护木
			var pump_m := cyl(0.024, 0.024, 0.12, 0, -0.005, -0.34, "poly")
			g.add_child(pump_m); g.set_meta("pump", pump_m)
			g.add_child(_grip(0.042, 0.09, 0.17, 0, -0.003, 0.17, "poly", 0.1))
			g.add_child(box(0.046, 0.09, 0.02, 0, 0.0, 0.26, "poly"))
			g.add_child(_grip(0.032, 0.095, 0.045, 0, -0.02, 0.04, "poly", 0.38))
			_trigger(g, -0.034, 0.01)
			# 机械瞄具(视轴 = sight_y 0.096)
			_irons(g, 0.096, -0.57, 0.09, 0.045, 0.045)
		"spas12":
			g.add_child(box(0.052, 0.085, 0.34, 0, 0.02, -0.03))
			g.add_child(cyl(0.015, 0.017, 0.46, 0, 0.048, -0.42))
			g.add_child(cyl(0.013, 0.013, 0.4, 0, -0.005, -0.39, "dark"))
			g.add_child(cyl(0.02, 0.021, 0.03, 0, 0.048, -0.655, "dark"))
			# 泵动护木(长行程)
			var pump_s := cyl(0.026, 0.026, 0.15, 0, -0.005, -0.36, "dark")
			g.add_child(pump_s); g.set_meta("pump", pump_s)
			# 折叠枪托钩
			g.add_child(box(0.008, 0.05, 0.16, 0, 0.06, 0.16, "metal"))
			g.add_child(_grip(0.044, 0.09, 0.16, 0, -0.003, 0.18, "dark", 0.1))
			g.add_child(box(0.048, 0.09, 0.02, 0, 0.0, 0.27, "dark"))
			g.add_child(_grip(0.034, 0.1, 0.05, 0, -0.022, 0.04, "dark", 0.36))
			_trigger(g, -0.036, 0.01)
			# 机械瞄具(视轴 = sight_y 0.1)
			_irons(g, 0.1, -0.58, 0.09, 0.045, 0.048)
		"rpg":
			# 现代反载具导弹:方形发射筒 + 顶部/底部导轨 + 大型侧置 CLU 指挥发射单元
			g.add_child(cyl(0.047, 0.047, 0.78, 0, 0.02, -0.14, "olive"))       # 发射筒芯
			g.add_child(box(0.072, 0.020, 0.82, 0, 0.056, -0.14, "poly"))       # 顶部战术导轨
			g.add_child(box(0.072, 0.018, 0.82, 0, -0.018, -0.14, "poly"))      # 底部加强筋
			g.add_child(box(0.086, 0.086, 0.05, 0, 0.02, -0.51, "dark"))        # 方形前口护罩
			g.add_child(box(0.092, 0.092, 0.06, 0, 0.02, 0.21, "dark"))         # 方形尾盖
			# 侧置 CLU:光学物镜 + 目镜 + 控制面板 + 橡胶眼罩
			var clu := Node3D.new()
			clu.position = Vector3(-0.066, 0.095, -0.16)
			clu.add_child(box(0.055, 0.14, 0.32, 0, 0, 0, "dark"))
			clu.add_child(box(0.060, 0.040, 0.050, 0, 0.008, -0.16, "poly"))
			clu.add_child(cyl(0.019, 0.019, 0.05, 0, 0.010, -0.16, "metal", "z"))   # 物镜筒
			clu.add_child(cyl(0.021, 0.019, 0.035, 0, 0.010, 0.13, "dark", "z"))    # 目镜筒
			clu.add_child(box(0.020, 0.055, 0.02, 0, -0.06, 0.08, "poly"))           # 控制按钮区
			g.add_child(clu)
			g.set_meta("scope_clu", clu)
			# PIP 制导镜目镜锚点:开镜时由 OpticScopeSystem 渲染镜内放大画面
			var rpg_eye := Node3D.new()
			rpg_eye.name = "ScopeEye"
			rpg_eye.position = Vector3(-0.066, 0.105, -0.069)
			g.add_child(rpg_eye)
			g.set_meta("scope_eye", rpg_eye)
			g.set_meta("scope_eye_radius", 0.030)
			# 方形目镜筒:ADS 时作为 PIP 取景框保留显示
			var rpg_frame := Node3D.new()
			rpg_frame.position = rpg_eye.position
			rpg_frame.add_child(box(0.085, 0.012, 0.035, 0, 0.038, 0, "dark"))
			rpg_frame.add_child(box(0.085, 0.012, 0.035, 0, -0.038, 0, "dark"))
			rpg_frame.add_child(box(0.012, 0.088, 0.035, -0.040, 0, 0, "dark"))
			rpg_frame.add_child(box(0.012, 0.088, 0.035, 0.040, 0, 0, "dark"))
			g.add_child(rpg_frame)
			g.set_meta("scope_tube", rpg_frame)
			g.add_child(box(0.045, 0.060, 0.14, 0.064, -0.012, -0.18, "poly"))  # 右侧 BCU
			g.add_child(box(0.006, 0.075, 0.006, -0.018, 0.112, 0.04, "dark"))   # IFF 天线
			g.add_child(_grip(0.036, 0.10, 0.05, 0, -0.030, 0.05, "dark", 0.3))
			g.add_child(box(0.050, 0.10, 0.04, 0, 0.0, 0.13, "poly"))            # 肩托
			_trigger(g, -0.040, 0.02)
			# 可拆装导弹筒(换弹动画件):方形导弹筒 + 外露战斗部 + 十字稳定鳍
			var rkt := Node3D.new()
			rkt.position = Vector3(0, 0.02, -0.14)
			rkt.add_child(box(0.060, 0.060, 0.54, 0, 0, 0.02, "olive"))          # 导弹筒体
			rkt.add_child(cyl(0.0, 0.042, 0.15, 0, 0, -0.27, "brass", "z"))      # 外露战斗部锥体
			rkt.add_child(box(0.012, 0.048, 0.05, 0, 0.030, -0.19, "dark"))      # 上鳍
			rkt.add_child(box(0.012, 0.048, 0.05, 0, -0.030, -0.19, "dark"))     # 下鳍
			rkt.add_child(box(0.048, 0.012, 0.05, 0.030, 0, -0.19, "dark"))      # 右鳍
			rkt.add_child(box(0.048, 0.012, 0.05, -0.030, 0, -0.19, "dark"))     # 左鳍
			g.add_child(rkt)
			g.set_meta("rocket", rkt)
		"gl":
			# 突击兵 M320:中折式单发 40mm 榴弹发射器
			# 结构:握把机匣(固定)+ 绕机匣前下方铰链「向下」折开的膛体 breech + 膛内榴弹 rocket
			g.add_child(box(0.062, 0.088, 0.16, 0, -0.006, 0.02, "dark"))          # 机匣本体(立breech面 z=-0.06)
			g.add_child(box(0.05, 0.03, 0.1, 0, 0.05, 0.03, "poly"))               # 机匣上盖
			g.add_child(box(0.03, 0.018, 0.03, 0, -0.04, -0.062, "metal"))         # 铰链座(轴点)
			g.add_child(_grip(0.036, 0.105, 0.05, 0, -0.075, 0.06, "poly", 0.28))  # 手枪握把
			_trigger(g, -0.045, 0.015)
			# 膛体:枢轴 = 机匣前下方铰链销(0,-0.04,-0.062);子件相对该轴点摆放,
			# 换弹时绕 X 负向旋转 → 枪管向下折开、弹膛口抬离立breech面(经典中折)
			var gl_breech := Node3D.new()
			gl_breech.name = "Breech"
			gl_breech.position = Vector3(0, -0.04, -0.062)
			var gl_ax := 0.052                                                      # 枪管轴线相对铰链的高度
			gl_breech.add_child(cyl(0.031, 0.031, 0.3, 0, gl_ax, -0.143, "olive", "z"))   # 40mm 膛管
			gl_breech.add_child(cyl(0.036, 0.036, 0.04, 0, gl_ax, -0.285, "dark", "z"))   # 前口加强环
			gl_breech.add_child(box(0.052, 0.014, 0.2, 0, gl_ax + 0.038, -0.15, "poly"))  # 顶部导轨
			gl_breech.add_child(box(0.012, 0.026, 0.012, 0, gl_ax + 0.06, -0.03, "dark")) # 照门
			gl_breech.add_child(box(0.01, 0.022, 0.01, 0, gl_ax + 0.05, -0.27, "dark"))   # 准星
			gl_breech.add_child(box(0.03, 0.024, 0.06, 0, gl_ax - 0.04, -0.21, "poly"))   # 前护木
			g.add_child(gl_breech)
			g.set_meta("breech", gl_breech)
			# 膛内 40mm 榴弹:坐进膛管后段(弹膛),战斗部朝前;随膛体一起下折
			var gl_rd := Node3D.new()
			gl_rd.position = Vector3(0, gl_ax, -0.062)
			gl_rd.add_child(cyl(0.0195, 0.0195, 0.075, 0, 0, 0.02, "brass", "z"))        # 药筒
			gl_rd.add_child(cyl(0.0, 0.021, 0.055, 0, 0, -0.045, "olive", "z"))          # 战斗部锥体
			gl_breech.add_child(gl_rd)
			g.set_meta("rocket", gl_rd)
		"m1911":
			var sl1 := box(0.034, 0.048, 0.19, 0, 0.032, -0.03, "dark"); g.add_child(sl1)
			g.set_meta("slide", sl1)
			g.add_child(box(0.032, 0.036, 0.17, 0, -0.002, -0.02, "dark"))
			g.add_child(cyl(0.008, 0.009, 0.03, 0, 0.034, -0.14))
			g.add_child(cyl(0.004, 0.004, 0.01, 0, 0.06, 0.06, "dark", "y"))
			g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.006, 0.045, "wood", 0.35))
			_trigger(g, -0.035, 0.0)
			_mag_straight(g, 0.024, 0.1, 0.034, 0, -0.008, 0.045, "metal")
			var ir1 := Node3D.new()
			ir1.name = "StockIrons"
			g.add_child(ir1)
			ir1.add_child(box(0.01, 0.02, 0.01, 0, 0.062, -0.1, "dark"))
			ir1.add_child(box(0.005, 0.024, 0.014, -0.0075, 0.062, 0.05, "dark"))
			ir1.add_child(box(0.005, 0.024, 0.014, 0.0075, 0.062, 0.05, "dark"))
		"g17":
			var sl2 := box(0.034, 0.045, 0.2, 0, 0.03, -0.03, "dark"); g.add_child(sl2)
			g.set_meta("slide", sl2)
			g.add_child(box(0.033, 0.03, 0.18, 0, -0.002, -0.02, "poly"))
			g.add_child(cyl(0.008, 0.009, 0.03, 0, 0.032, -0.14))
			g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.006, 0.045, "poly", 0.35))
			_trigger(g, -0.035, 0.0)
			_mag_straight(g, 0.026, 0.11, 0.036, 0, -0.008, 0.045, "dark")
			var ir2 := Node3D.new()
			ir2.name = "StockIrons"
			g.add_child(ir2)
			ir2.add_child(box(0.01, 0.018, 0.01, 0, 0.06, -0.1, "dark"))
			ir2.add_child(box(0.005, 0.02, 0.014, -0.0075, 0.058, 0.05, "dark"))
			ir2.add_child(box(0.005, 0.02, 0.014, 0.0075, 0.058, 0.05, "dark"))
		"p226":
			var sl3 := box(0.035, 0.048, 0.2, 0, 0.032, -0.03, "dark"); g.add_child(sl3)
			g.set_meta("slide", sl3)
			g.add_child(box(0.034, 0.038, 0.18, 0, -0.002, -0.02, "tan"))
			g.add_child(cyl(0.009, 0.01, 0.03, 0, 0.034, -0.14))
			# 待击解脱杆(左)
			g.add_child(box(0.008, 0.03, 0.02, -0.02, 0.005, 0.03, "dark"))
			g.add_child(_grip(0.031, 0.09, 0.045, 0, -0.007, 0.045, "poly", 0.35))
			_trigger(g, -0.035, 0.0)
			_mag_straight(g, 0.026, 0.11, 0.036, 0, -0.008, 0.045, "metal")
			var ir3 := Node3D.new()
			ir3.name = "StockIrons"
			g.add_child(ir3)
			ir3.add_child(box(0.01, 0.02, 0.01, 0, 0.064, -0.1, "dark"))
			ir3.add_child(box(0.005, 0.022, 0.014, -0.0075, 0.062, 0.05, "dark"))
			ir3.add_child(box(0.005, 0.022, 0.014, 0.0075, 0.062, 0.05, "dark"))
		"deagle":
			var sl4 := box(0.042, 0.058, 0.24, 0, 0.038, -0.05, "chrome"); g.add_child(sl4)
			g.set_meta("slide", sl4)
			g.add_child(cyl(0.011, 0.012, 0.06, 0, 0.04, -0.2, "chrome"))
			g.add_child(cyl(0.02, 0.02, 0.025, 0, 0.04, -0.24, "dark"))
			g.add_child(box(0.04, 0.04, 0.19, 0, -0.002, -0.03, "dark"))
			g.add_child(_grip(0.036, 0.1, 0.05, 0, -0.008, 0.05, "wood", 0.32))
			_trigger(g, -0.038, 0.0)
			_mag_straight(g, 0.03, 0.12, 0.04, 0, -0.009, 0.05, "chrome")
			var ir4 := Node3D.new()
			ir4.name = "StockIrons"
			g.add_child(ir4)
			ir4.add_child(box(0.012, 0.022, 0.012, 0, 0.072, -0.15, "dark"))
			ir4.add_child(box(0.006, 0.024, 0.016, -0.008, 0.07, 0.05, "dark"))
			ir4.add_child(box(0.006, 0.024, 0.016, 0.008, 0.07, 0.05, "dark"))
			g.add_child(box(0.042, 0.012, 0.1, 0, 0.068, -0.1, "chrome"))
		"m93r":
			var sl5 := box(0.034, 0.045, 0.21, 0, 0.03, -0.04, "dark"); g.add_child(sl5)
			g.set_meta("slide", sl5)
			g.add_child(box(0.033, 0.038, 0.19, 0, -0.002, -0.03, "metal"))
			g.add_child(cyl(0.008, 0.009, 0.04, 0, 0.032, -0.16))
			# 前握把(展开,顶端贴合防尘盖)
			var fg2 := box(0.024, 0.06, 0.03, 0, -0.045, -0.08, "poly"); fg2.rotation.x = 0.2
			g.add_child(fg2)
			g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.007, 0.05, "poly", 0.35))
			_trigger(g, -0.035, 0.01)
			_mag_straight(g, 0.026, 0.14, 0.034, 0, -0.008, 0.045, "dark")
			g.add_child(box(0.008, 0.02, 0.03, -0.02, 0.03, 0.02, "dark"))
			var ir5 := Node3D.new()
			ir5.name = "StockIrons"
			g.add_child(ir5)
			ir5.add_child(box(0.01, 0.018, 0.01, 0, 0.061, -0.11, "dark"))
			ir5.add_child(box(0.005, 0.02, 0.014, -0.0075, 0.059, 0.045, "dark"))
			ir5.add_child(box(0.005, 0.02, 0.014, 0.0075, 0.059, 0.045, "dark"))
		# ==================== [8/10 武器扩充] 10 把新枪模型 ====================
		"g36c":
			# G36C 卡宾枪:短机匣 + 顶部导轨 + 短枪管 + 聚合物折叠托
			g.add_child(box(0.052, 0.07, 0.3, 0, 0.012, -0.04))
			g.add_child(box(0.048, 0.026, 0.4, 0, 0.06, -0.12, "dark"))
			_rail(g, 0.082, 0.06, -0.38)
			g.add_child(cyl(0.026, 0.029, 0.2, 0, 0.024, -0.34, "poly"))
			g.add_child(cyl(0.011, 0.013, 0.36, 0, 0.024, -0.52))
			g.add_child(cyl(0.016, 0.018, 0.04, 0, 0.024, -0.7, "dark"))
			g.add_child(_grip(0.04, 0.085, 0.17, 0, -0.003, 0.16, "poly", 0.1))
			g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.25, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.023, 0.04, "poly", 0.38))
			_trigger(g, -0.035, 0.01)
			_mag_straight(g, 0.036, 0.12, 0.06, 0, -0.022, -0.08, "dark", 0.12)
			_bolt(g, 0.028, 0.045, 0.0, 1.0)
			_irons(g, 0.1, -0.5, 0.06, 0.055, 0.024)
		"ak74":
			# AK-74M:机匣 + 橙木护木 + 74 风格微弯弹匣 + 倾斜消焰器
			g.add_child(box(0.054, 0.072, 0.34, 0, 0.012, -0.05))
			g.add_child(box(0.05, 0.024, 0.3, 0, 0.058, -0.07, "dark"))
			g.add_child(cyl(0.023, 0.028, 0.26, 0, 0.02, -0.34, "wood"))
			g.add_child(cyl(0.012, 0.014, 0.42, 0, 0.028, -0.55))
			g.add_child(box(0.014, 0.04, 0.016, 0, 0.05, -0.52, "dark"))
			g.add_child(cyl(0.014, 0.018, 0.08, 0, 0.028, -0.79, "dark"))
			g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.008, 0.18, "wood", 0.16))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.045, "wood", 0.42))
			_trigger(g, -0.036, 0.02)
			_curved_mag(g, 0.036, 0, -0.023, -0.1)
			_bolt(g, 0.032, 0.035, -0.02, 1.0)
			_irons(g, 0.104, -0.52, 0.05, 0.06, 0.028)
		"famas":
			# FAMAS 无托:长机匣 + 顶部导轨 + 前握把 + 无托弹匣
			g.add_child(box(0.05, 0.085, 0.5, 0, 0.02, 0.0))
			g.add_child(box(0.046, 0.028, 0.46, 0, 0.068, 0.0, "dark"))
			_rail(g, 0.088, 0.2, -0.4)
			g.add_child(cyl(0.011, 0.013, 0.46, 0, 0.024, -0.47))
			g.add_child(cyl(0.014, 0.016, 0.04, 0, 0.024, -0.7, "dark"))
			g.add_child(_grip(0.024, 0.07, 0.03, 0, -0.022, -0.2, "poly", 0.25))
			g.add_child(_grip(0.032, 0.095, 0.05, 0, -0.022, 0.1, "poly", 0.3))
			_trigger(g, -0.034, 0.04)
			_mag_straight(g, 0.036, 0.12, 0.055, 0, -0.022, -0.02, "dark")
			_bolt(g, 0.02, 0.03, 0.08, 1.0)
			_irons(g, 0.1, -0.46, 0.05, 0.05, 0.024)
		"vector":
			# KRISS Vector:机匣 + 顶部轨道 + 粗短管 + 折叠托
			g.add_child(box(0.05, 0.08, 0.32, 0, 0.015, -0.05, "poly"))
			g.add_child(box(0.046, 0.028, 0.4, 0, 0.063, -0.14, "dark"))
			_rail(g, 0.086, 0.04, -0.36)
			g.add_child(cyl(0.015, 0.017, 0.38, 0, 0.024, -0.4))
			g.add_child(cyl(0.02, 0.022, 0.04, 0, 0.024, -0.58, "dark"))
			g.add_child(_grip(0.04, 0.08, 0.16, 0, -0.003, 0.14, "poly", 0.1))
			g.add_child(box(0.044, 0.08, 0.02, 0, 0.0, 0.23, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "poly", 0.38))
			_trigger(g, -0.036, 0.01)
			_mag_straight(g, 0.034, 0.14, 0.05, 0, -0.024, -0.06, "dark", 0.18)
			_bolt(g, 0.028, 0.04, 0.0, 1.0)
			_irons(g, 0.088, -0.46, 0.05, 0.05, 0.024)
		"pp19":
			# PP-19 野牛:自由枪机 + 枪管下方长筒螺旋弹匣(弹匣即护木,一直延伸到枪口后方)
			g.add_child(box(0.05, 0.07, 0.26, 0, 0.012, -0.03))
			g.add_child(box(0.046, 0.024, 0.26, 0, 0.058, -0.05, "dark"))
			# 枪管 + 圆筒形护木/枪管套(野牛无导气管,上半筒为护木)
			g.add_child(cyl(0.011, 0.013, 0.47, 0, 0.024, -0.375))
			g.add_child(cyl(0.021, 0.024, 0.32, 0, 0.025, -0.325, "poly"))
			g.add_child(box(0.03, 0.04, 0.03, 0, 0.052, -0.47, "dark"))
			g.add_child(cyl(0.014, 0.015, 0.045, 0, 0.024, -0.605, "dark"))
			# 螺旋弹匣:长筒沿枪管方向直接挂在枪管/护木下方,根部连接机匣弹匣井
			var helical_mag := Node3D.new()
			helical_mag.position = Vector3(0.0, -0.068, -0.335)
			helical_mag.add_child(cyl(0.037, 0.037, 0.36, 0.0, 0.0, 0.0, "dark", "z"))
			for rib_z in [-0.12, -0.04, 0.04, 0.12]:
				helical_mag.add_child(cyl(0.041, 0.041, 0.014, 0.0, 0.0, rib_z, "metal", "z"))
			helical_mag.add_child(cyl(0.042, 0.042, 0.03, 0.0, 0.0, 0.18, "poly", "z"))
			helical_mag.add_child(cyl(0.042, 0.042, 0.025, 0.0, 0.0, -0.19, "poly", "z"))
			helical_mag.add_child(box(0.048, 0.05, 0.08, 0.0, 0.025, 0.18, "dark"))
			helical_mag.add_child(box(0.044, 0.03, 0.05, 0.0, 0.053, -0.13, "poly"))
			g.add_child(helical_mag)
			g.set_meta("mag", helical_mag)
			g.add_child(_grip(0.038, 0.09, 0.18, 0, -0.003, 0.15, "poly", 0.1))
			g.add_child(box(0.042, 0.09, 0.02, 0, 0.0, 0.24, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.022, 0.04, "poly", 0.38))
			_trigger(g, -0.034, 0.0)
			_bolt(g, 0.028, 0.04, -0.02, 1.0)
			_irons(g, 0.095, -0.46, 0.05, 0.05, 0.028)
		"mg42":
			# MG42:方形机匣 + 细长枪管 + 侧挂弹链箱 + 两脚架
			g.add_child(box(0.05, 0.09, 0.4, 0, 0.018, 0.02))
			_feed_cover(g, 0.062, -0.12, 0.5)
			g.add_child(cyl(0.011, 0.012, 0.56, 0, 0.024, -0.45))
			g.add_child(cyl(0.014, 0.016, 0.06, 0, 0.024, -0.71, "dark"))
			_side_belt_feed(g, -1.0, Vector3(-0.060, -0.068, -0.07), Vector3(0.07, 0.1, 0.12),
				Vector3(-0.024, -0.018, -0.14), "olive")
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.2, "wood", 0.14))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.3, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "wood", 0.4))
			_trigger(g, -0.037, 0.02)
			# 两脚架(收折,经安装座贴合枪管)
			g.add_child(box(0.02, 0.11, 0.03, 0, -0.035, -0.35, "dark"))
			for leg_s in [-1.0, 1.0]:
				var leg := cyl(0.006, 0.006, 0.16, leg_s * 0.03, -0.09, -0.35, "dark", "z")
				leg.rotation.z = leg_s * 0.3
				g.add_child(leg)
			_bolt(g, 0.03, 0.045, 0.02, 1.0)
			_irons(g, 0.13, -0.55, 0.05, 0.05, 0.024)
		"m60":
			# M60:粗枪管 + 盒机匣 + 提把 + 弹链箱
			g.add_child(box(0.052, 0.085, 0.34, 0, 0.018, -0.04))
			_feed_cover(g, 0.0625, -0.04, 0.34)
			g.add_child(cyl(0.016, 0.018, 0.56, 0, 0.028, -0.47))
			g.add_child(cyl(0.02, 0.022, 0.06, 0, 0.028, -0.735, "dark"))
			g.add_child(box(0.03, 0.035, 0.14, 0, 0.073, -0.18, "poly"))
			_side_belt_feed(g, -1.0, Vector3(-0.060, -0.066, -0.05), Vector3(0.07, 0.1, 0.12),
				Vector3(-0.024, -0.018, -0.12), "olive")
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.18, "wood", 0.14))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_bolt(g, 0.03, 0.045, 0.0, 1.0)
			_irons(g, 0.125, -0.52, 0.05, 0.05, 0.028)
		"m110":
			# M110 DMR:长管 + 导轨 + 圆形镂空瞄准镜 + 固定托
			g.add_child(box(0.05, 0.075, 0.34, 0, 0.016, -0.06, "tan"))
			g.add_child(box(0.046, 0.026, 0.48, 0, 0.062, -0.2, "dark"))
			_rail(g, 0.086, 0.02, -0.44)
			g.add_child(cyl(0.011, 0.013, 0.62, 0, 0.024, -0.52))
			g.add_child(cyl(0.016, 0.019, 0.05, 0, 0.024, -0.82, "dark"))
			_hollow_dmr_scope(g, 0.096, -0.30, -0.12)
			g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "tan", 0.1))
			g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "tan"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
			_trigger(g, -0.036, 0.01)
			_mag_straight(g, 0.036, 0.1, 0.06, 0, -0.021, -0.1, "tan", 0.1)
			_bolt(g, 0.028, 0.045, -0.02, 1.0)
			_irons(g, 0.11, -0.55, 0.05, 0.05, 0.024)
			var m110_irons := g.get_node_or_null("StockIrons")
			if m110_irons != null:
				m110_irons.visible = false
		"m40":
			# M40A3:栓动 + 细长管 + 木托 + 镜
			g.add_child(cyl(0.011, 0.013, 0.55, 0, 0.028, -0.49))
			g.add_child(cyl(0.014, 0.016, 0.05, 0, 0.028, -0.72, "dark"))
			g.add_child(box(0.048, 0.07, 0.3, 0, 0.015, -0.1, "wood"))
			g.add_child(box(0.04, 0.04, 0.18, 0, 0.05, -0.16, "wood"))
			_simple_scope(g, 0.113, -0.14, 0.26, 0.07)
			g.add_child(_grip(0.04, 0.085, 0.2, 0, -0.003, 0.16, "wood", 0.1))
			g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.26, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.028, 0.05, 0.05, 0, -0.02, -0.08, "dark")
			_bolt(g, 0.028, 0.045, 0.04, 1.0)
			_irons(g, 0.113, -0.5, 0.05, 0.05, 0.028)
		"g3":
			# G3 战斗步枪:机匣 + 粗管 + 木托 + 20 发直弹匣
			g.add_child(box(0.052, 0.076, 0.36, 0, 0.016, -0.06))
			g.add_child(box(0.048, 0.026, 0.4, 0, 0.062, -0.14, "dark"))
			_rail(g, 0.086, 0.04, -0.4)
			g.add_child(cyl(0.013, 0.015, 0.54, 0, 0.024, -0.5))
			g.add_child(cyl(0.017, 0.02, 0.05, 0, 0.024, -0.725, "dark"))
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.18, "wood", 0.12))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.022, -0.08, "dark", 0.1)
			_bolt(g, 0.03, 0.04, 0.0, 1.0)
			_irons(g, 0.112, -0.54, 0.05, 0.06, 0.024)
		# ==================== [8/10 武器扩充 v2] 17 把新枪模型(顶部零件低矮,ADS 不挡视野) ====================
		"mpx":
			# SIG MPX:短 AR 机匣 + 顶部导轨 + 短管 + 折叠托
			g.add_child(box(0.05, 0.07, 0.3, 0, 0.012, -0.05))
			g.add_child(box(0.046, 0.024, 0.34, 0, 0.056, -0.13, "dark"))
			_rail(g, 0.082, 0.02, -0.34)
			g.add_child(cyl(0.011, 0.013, 0.52, 0, 0.024, -0.44))
			g.add_child(cyl(0.016, 0.018, 0.04, 0, 0.024, -0.69, "dark"))
			g.add_child(_grip(0.04, 0.085, 0.17, 0, -0.003, 0.16, "poly", 0.1))
			g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.25, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.023, 0.04, "poly", 0.38))
			_trigger(g, -0.035, 0.01)
			_mag_straight(g, 0.034, 0.13, 0.055, 0, -0.023, -0.09, "dark", 0.12)
			_bolt(g, 0.028, 0.045, 0.0, 1.0)
			_irons(g, 0.09, -0.52, 0.05, 0.05, 0.024)
		"mp7":
			# HK MP7:紧凑机匣 + 顶部导轨 + 折叠握把 + 长直弹匣
			g.add_child(box(0.042, 0.068, 0.3, 0, 0.012, -0.04))
			g.add_child(box(0.04, 0.022, 0.32, 0, 0.053, -0.12, "dark"))
			_rail(g, 0.075, 0.02, -0.3)
			g.add_child(cyl(0.009, 0.011, 0.36, 0, 0.022, -0.36))
			g.add_child(cyl(0.012, 0.013, 0.035, 0, 0.022, -0.505, "dark"))
			g.add_child(_grip(0.034, 0.08, 0.14, 0, -0.003, 0.14, "poly", 0.1))
			g.add_child(box(0.038, 0.08, 0.02, 0, 0.0, 0.22, "poly"))
			g.add_child(_grip(0.028, 0.09, 0.04, 0, -0.02, 0.03, "poly", 0.38))
			_trigger(g, -0.033, 0.01)
			_mag_straight(g, 0.03, 0.12, 0.045, 0, -0.02, -0.1, "dark")
			_bolt(g, 0.024, 0.04, 0.0, 1.0)
			_irons(g, 0.085, -0.48, 0.045, 0.045, 0.022)
		"pp2000":
			# PP-2000:方形机匣 + 顶部导轨 + 大容量弹匣
			g.add_child(box(0.046, 0.076, 0.34, 0, 0.014, -0.04))
			g.add_child(box(0.042, 0.024, 0.36, 0, 0.058, -0.12, "dark"))
			_rail(g, 0.08, 0.04, -0.34)
			g.add_child(cyl(0.011, 0.013, 0.37, 0, 0.024, -0.38))
			g.add_child(cyl(0.014, 0.015, 0.035, 0, 0.024, -0.545, "dark"))
			g.add_child(_grip(0.036, 0.085, 0.16, 0, -0.003, 0.15, "poly", 0.1))
			g.add_child(box(0.04, 0.085, 0.02, 0, 0.0, 0.24, "poly"))
			g.add_child(_grip(0.03, 0.095, 0.042, 0, -0.02, 0.035, "poly", 0.38))
			_trigger(g, -0.034, 0.02)
			_mag_straight(g, 0.032, 0.17, 0.05, 0, -0.022, -0.08, "dark")
			_bolt(g, 0.026, 0.04, 0.0, 1.0)
			_irons(g, 0.09, -0.5, 0.05, 0.05, 0.024)
		"mk48":
			# MK48:7.62 轻机枪,方机匣 + 粗管 + 弹链箱
			g.add_child(box(0.052, 0.09, 0.38, 0, 0.018, -0.04))
			_feed_cover(g, 0.062, -0.16, 0.46)
			g.add_child(cyl(0.014, 0.016, 0.58, 0, 0.026, -0.51))
			g.add_child(cyl(0.018, 0.02, 0.06, 0, 0.026, -0.795, "dark"))
			_side_belt_feed(g, -1.0, Vector3(-0.060, -0.065, -0.05), Vector3(0.07, 0.1, 0.12),
				Vector3(-0.024, -0.018, -0.13), "olive")
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.2, "wood", 0.14))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.3, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "wood", 0.4))
			_trigger(g, -0.037, 0.02)
			_bolt(g, 0.03, 0.045, 0.02, 1.0)
			_irons(g, 0.13, -0.58, 0.05, 0.05, 0.026)
		"negev":
			# 内格夫:长机匣 + 粗管散热 + 两脚架
			g.add_child(box(0.052, 0.09, 0.44, 0, 0.018, -0.06))
			_feed_cover(g, 0.062, -0.06, 0.44)
			g.add_child(cyl(0.012, 0.014, 0.6, 0, 0.026, -0.56))
			g.add_child(cyl(0.016, 0.018, 0.06, 0, 0.026, -0.83, "dark"))
			_side_belt_feed(g, -1.0, Vector3(-0.060, -0.065, -0.05), Vector3(0.07, 0.1, 0.12),
				Vector3(-0.024, -0.018, -0.12), "olive")
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.22, "poly", 0.14))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.32, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "poly", 0.4))
			_trigger(g, -0.037, 0.02)
			g.add_child(box(0.02, 0.11, 0.03, 0, -0.035, -0.4, "dark"))
			for leg_s in [-1.0, 1.0]:
				var leg := cyl(0.006, 0.006, 0.16, leg_s * 0.03, -0.09, -0.4, "dark", "z")
				leg.rotation.z = leg_s * 0.3
				g.add_child(leg)
			_bolt(g, 0.03, 0.045, 0.02, 1.0)
			_irons(g, 0.125, -0.6, 0.05, 0.05, 0.026)
		"mg3":
			# MG3:MG42 风格方机匣 + 细长管 + 右侧挂弹链箱(与 MG42 镜像区分)
			g.add_child(box(0.05, 0.09, 0.4, 0, 0.018, 0.02))
			_feed_cover(g, 0.062, -0.12, 0.5)
			g.add_child(cyl(0.011, 0.012, 0.56, 0, 0.024, -0.45))
			g.add_child(cyl(0.014, 0.016, 0.06, 0, 0.024, -0.71, "dark"))
			_side_belt_feed(g, 1.0, Vector3(0.060, -0.068, -0.07), Vector3(0.07, 0.1, 0.12),
				Vector3(0.024, -0.018, -0.14), "dark")
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.2, "wood", 0.14))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.3, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "wood", 0.4))
			_trigger(g, -0.037, 0.02)
			_bolt(g, 0.03, 0.045, 0.02, 1.0)
			_irons(g, 0.13, -0.55, 0.05, 0.05, 0.024)
		"m82a1":
			# 巴雷特 M82A1:反器材大粗管 + 方机匣 + 大镜
			g.add_child(cyl(0.016, 0.018, 0.78, 0, 0.03, -0.65))
			g.add_child(cyl(0.02, 0.022, 0.08, 0, 0.03, -1.0, "dark"))
			g.add_child(box(0.06, 0.1, 0.42, 0, 0.02, -0.06))
			g.add_child(box(0.05, 0.035, 0.36, 0, 0.078, -0.14, "dark"))
			_simple_scope(g, 0.116, -0.12, 0.3, 0.074, 0.022)
			g.add_child(_grip(0.048, 0.11, 0.24, 0, -0.008, 0.2, "dark", 0.14))
			g.add_child(box(0.052, 0.11, 0.02, 0, 0.0, 0.32, "dark"))
			g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.025, 0.04, "dark", 0.4))
			_trigger(g, -0.04, 0.02)
			_mag_straight(g, 0.04, 0.1, 0.07, 0, -0.025, -0.16, "dark")
			_bolt(g, 0.032, 0.05, 0.02, 1.0)
			_irons(g, 0.135, -0.62, 0.06, 0.06, 0.03)
		"l115":
			# L115A3:栓动 + 细长管 + 绿色托 + 镜
			g.add_child(cyl(0.011, 0.013, 0.64, 0, 0.028, -0.56))
			g.add_child(cyl(0.015, 0.017, 0.05, 0, 0.028, -0.88, "dark"))
			g.add_child(box(0.048, 0.07, 0.32, 0, 0.015, -0.1, "dark"))
			g.add_child(box(0.04, 0.045, 0.2, 0, 0.052, -0.18, "dark"))
			_simple_scope(g, 0.114, -0.15, 0.3, 0.072)
			g.add_child(_grip(0.04, 0.085, 0.2, 0, -0.003, 0.16, "dark", 0.1))
			g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.26, "dark"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.028, 0.05, 0.05, 0, -0.02, -0.08, "dark")
			_bolt(g, 0.028, 0.045, 0.04, 1.0)
			_irons(g, 0.115, -0.56, 0.05, 0.05, 0.028)
		"sv98":
			# SV-98:栓动 + 木托 + 细管 + 镜
			g.add_child(cyl(0.011, 0.013, 0.58, 0, 0.028, -0.51))
			g.add_child(cyl(0.015, 0.017, 0.05, 0, 0.028, -0.815, "dark"))
			g.add_child(box(0.05, 0.075, 0.3, 0, 0.015, -0.08, "wood"))
			g.add_child(box(0.04, 0.05, 0.2, 0, 0.055, -0.16, "wood"))
			_simple_scope(g, 0.113, -0.13, 0.28, 0.07)
			g.add_child(_grip(0.042, 0.09, 0.2, 0, -0.003, 0.16, "wood", 0.1))
			g.add_child(box(0.046, 0.09, 0.02, 0, 0.0, 0.26, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.03, 0.055, 0.05, 0, -0.02, -0.09, "dark")
			_bolt(g, 0.028, 0.045, 0.04, 1.0)
			_irons(g, 0.11, -0.52, 0.05, 0.05, 0.028)
		"m2010":
			# M2010 ESR:栓动 + 细管 + 镜
			g.add_child(cyl(0.011, 0.013, 0.66, 0, 0.028, -0.57))
			g.add_child(cyl(0.015, 0.017, 0.05, 0, 0.028, -0.895, "dark"))
			g.add_child(box(0.048, 0.072, 0.3, 0, 0.015, -0.1, "dark"))
			g.add_child(box(0.04, 0.042, 0.2, 0, 0.05, -0.18, "dark"))
			_simple_scope(g, 0.115, -0.15, 0.3, 0.07)
			g.add_child(_grip(0.04, 0.085, 0.2, 0, -0.003, 0.16, "dark", 0.1))
			g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.26, "dark"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.028, 0.05, 0.05, 0, -0.02, -0.08, "dark")
			_bolt(g, 0.028, 0.045, 0.04, 1.0)
			_irons(g, 0.113, -0.58, 0.05, 0.05, 0.028)
		"sks":
			# SKS:木托 + 固定弹仓 + 短管 + 圆形镂空瞄准镜
			g.add_child(cyl(0.011, 0.013, 0.47, 0, 0.026, -0.44))
			g.add_child(cyl(0.015, 0.017, 0.05, 0, 0.026, -0.66, "dark"))
			g.add_child(box(0.05, 0.08, 0.34, 0, 0.016, -0.04, "wood"))
			g.add_child(box(0.044, 0.026, 0.3, 0, 0.06, -0.1, "dark"))
			_hollow_dmr_scope(g, 0.092, -0.25, -0.10)
			g.add_child(_grip(0.042, 0.095, 0.2, 0, -0.006, 0.18, "wood", 0.1))
			g.add_child(box(0.046, 0.095, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.045, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.03, 0.06, 0.05, 0, -0.024, -0.06, "dark")
			_bolt(g, 0.028, 0.04, 0.0, 1.0)
			_irons(g, 0.105, -0.5, 0.05, 0.05, 0.026)
			var sks_irons := g.get_node_or_null("StockIrons")
			if sks_irons != null:
				sks_irons.visible = false
		"m1a":
			# M1A:木托 + 长管 + 20 发弹匣 + 瞄准镜
			g.add_child(cyl(0.012, 0.014, 0.56, 0, 0.026, -0.5))
			g.add_child(cyl(0.016, 0.018, 0.05, 0, 0.026, -0.755, "dark"))
			g.add_child(box(0.05, 0.082, 0.34, 0, 0.016, -0.06, "wood"))
			g.add_child(box(0.046, 0.028, 0.3, 0, 0.064, -0.12, "dark"))
			var scope_a := cyl(0.017, 0.017, 0.2, 0, 0.092, -0.16, "dark", "z")
			g.add_child(scope_a)
			g.add_child(cyl(0.012, 0.012, 0.02, 0, 0.068, -0.16, "dark"))
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.006, 0.18, "wood", 0.12))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.025, -0.09, "dark", 0.08)
			_bolt(g, 0.03, 0.04, 0.0, 1.0)
			_irons(g, 0.112, -0.56, 0.05, 0.06, 0.026)
		"g28":
			# HK G28:AR 风格 + 顶部导轨 + 镜
			g.add_child(box(0.05, 0.075, 0.32, 0, 0.016, -0.06))
			g.add_child(box(0.046, 0.026, 0.4, 0, 0.062, -0.16, "dark"))
			_rail(g, 0.086, 0.02, -0.42)
			g.add_child(cyl(0.012, 0.014, 0.56, 0, 0.024, -0.49))
			g.add_child(cyl(0.016, 0.018, 0.05, 0, 0.024, -0.755, "dark"))
			var scope_g := cyl(0.018, 0.018, 0.24, 0, 0.094, -0.16, "dark", "z")
			g.add_child(scope_g)
			g.add_child(cyl(0.012, 0.012, 0.02, 0, 0.07, -0.16, "dark"))
			g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "poly", 0.1))
			g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
			_trigger(g, -0.036, 0.01)
			_mag_straight(g, 0.036, 0.1, 0.06, 0, -0.021, -0.1, "tan", 0.1)
			_bolt(g, 0.028, 0.045, -0.02, 1.0)
			_irons(g, 0.11, -0.55, 0.05, 0.05, 0.024)
		"mk14":
			# MK14 EBR:导轨护木 + 镜
			g.add_child(box(0.05, 0.075, 0.34, 0, 0.016, -0.06))
			g.add_child(box(0.046, 0.028, 0.46, 0, 0.062, -0.2, "dark"))
			_rail(g, 0.086, 0.02, -0.44)
			g.add_child(cyl(0.012, 0.014, 0.62, 0, 0.024, -0.53))
			g.add_child(cyl(0.016, 0.018, 0.05, 0, 0.024, -0.815, "dark"))
			var scope_m14 := cyl(0.018, 0.018, 0.24, 0, 0.094, -0.18, "dark", "z")
			g.add_child(scope_m14)
			g.add_child(cyl(0.012, 0.012, 0.02, 0, 0.07, -0.18, "dark"))
			g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "tan", 0.1))
			g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "tan"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
			_trigger(g, -0.036, 0.01)
			_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.021, -0.09, "tan", 0.08)
			_bolt(g, 0.03, 0.045, -0.02, 1.0)
			_irons(g, 0.11, -0.55, 0.05, 0.05, 0.024)
		"m14":
			# M14:木托 + 长管 + 瞄准镜
			g.add_child(cyl(0.012, 0.014, 0.58, 0, 0.026, -0.51))
			g.add_child(cyl(0.016, 0.018, 0.05, 0, 0.026, -0.775, "dark"))
			g.add_child(box(0.05, 0.082, 0.34, 0, 0.016, -0.06, "wood"))
			g.add_child(box(0.046, 0.028, 0.32, 0, 0.064, -0.12, "dark"))
			var scope_14 := cyl(0.017, 0.017, 0.2, 0, 0.092, -0.16, "dark", "z")
			g.add_child(scope_14)
			g.add_child(cyl(0.012, 0.012, 0.02, 0, 0.068, -0.16, "dark"))
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.006, 0.18, "wood", 0.12))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.025, -0.09, "dark", 0.08)
			_bolt(g, 0.03, 0.04, 0.0, 1.0)
			_irons(g, 0.112, -0.56, 0.05, 0.06, 0.026)
		"ar10":
			# AR-10:AR 风格 + 导轨 + 20 发弹匣
			g.add_child(box(0.05, 0.075, 0.32, 0, 0.016, -0.06))
			g.add_child(box(0.046, 0.026, 0.38, 0, 0.062, -0.16, "dark"))
			_rail(g, 0.086, 0.01, -0.4)
			g.add_child(cyl(0.012, 0.014, 0.54, 0, 0.024, -0.48))
			g.add_child(cyl(0.016, 0.018, 0.05, 0, 0.024, -0.735, "dark"))
			var scope_10 := cyl(0.017, 0.017, 0.2, 0, 0.094, -0.16, "dark", "z")
			g.add_child(scope_10)
			g.add_child(cyl(0.012, 0.012, 0.02, 0, 0.07, -0.16, "dark"))
			g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "poly", 0.1))
			g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "poly"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
			_trigger(g, -0.036, 0.01)
			_mag_straight(g, 0.036, 0.1, 0.06, 0, -0.021, -0.1, "dark", 0.1)
			_bolt(g, 0.028, 0.045, -0.02, 1.0)
			_irons(g, 0.11, -0.54, 0.05, 0.05, 0.024)
		"fal":
			# FN FAL:木托 + 细管 + 20 发弹匣 + 瞄准镜
			g.add_child(cyl(0.012, 0.014, 0.55, 0, 0.026, -0.49))
			g.add_child(cyl(0.016, 0.018, 0.05, 0, 0.026, -0.755, "dark"))
			g.add_child(box(0.05, 0.08, 0.34, 0, 0.016, -0.06, "wood"))
			g.add_child(box(0.046, 0.026, 0.32, 0, 0.062, -0.12, "dark"))
			var scope_f := cyl(0.017, 0.017, 0.2, 0, 0.092, -0.16, "dark", "z")
			g.add_child(scope_f)
			g.add_child(cyl(0.012, 0.012, 0.02, 0, 0.068, -0.16, "dark"))
			g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.006, 0.18, "wood", 0.12))
			g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
			g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
			_trigger(g, -0.036, 0.02)
			_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.024, -0.09, "dark", 0.08)
			_bolt(g, 0.03, 0.04, 0.0, 1.0)
			_irons(g, 0.112, -0.56, 0.05, 0.06, 0.026)


## 各武器的握持锚点(枪械局部空间,左手贴合护木底部)
const HAND_ANCHORS := {
	"m4": { "r": [0.012, -0.1, 0.035], "l": [0, -0.038, -0.4] },
	"ak": { "r": [0.012, -0.1, 0.045], "l": [0, -0.032, -0.4] },
	"mp5": { "r": [0.012, -0.095, 0.035], "l": [0, -0.085, -0.26] },
	"m249": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.46] },
	"awm": { "r": [0.012, -0.095, 0.065], "l": [0, -0.048, -0.32] },
	"m1014": { "r": [0.012, -0.1, 0.045], "l": [0, -0.062, -0.32] },
	"m1911": { "r": [0.012, -0.075, 0.055], "l": [-0.028, -0.085, 0.05] },
	"rpg": { "r": [0.012, -0.07, 0.115], "l": [0, -0.02, -0.32] },
	"gl": { "r": [0.012, -0.088, 0.055], "l": [0, -0.055, -0.26] },
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
	# [8/10 武器扩充] 新枪握持锚点
	"g36c": { "r": [0.012, -0.1, 0.035], "l": [0, -0.038, -0.38] },
	"ak74": { "r": [0.012, -0.1, 0.045], "l": [0, -0.032, -0.38] },
	"famas": { "r": [0.012, -0.1, 0.015], "l": [0, -0.04, -0.22] },
	"vector": { "r": [0.012, -0.095, 0.035], "l": [0, -0.05, -0.28] },
	"pp19": { "r": [0.012, -0.09, 0.035], "l": [0, -0.19, -0.3] },
	"mg42": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.42] },
	"m60": { "r": [0.012, -0.11, 0.045], "l": [0, -0.045, -0.45] },
	"m110": { "r": [0.012, -0.1, 0.035], "l": [0, -0.035, -0.4] },
	"m40": { "r": [0.012, -0.095, 0.065], "l": [0, -0.048, -0.3] },
	"g3": { "r": [0.012, -0.1, 0.035], "l": [0, -0.04, -0.4] },
	# [8/10 武器扩充 v2] 17 把新枪握持锚点
	"mpx": { "r": [0.012, -0.095, 0.035], "l": [0, -0.038, -0.4] },
	"mp7": { "r": [0.012, -0.09, 0.03], "l": [0, -0.035, -0.32] },
	"pp2000": { "r": [0.012, -0.095, 0.035], "l": [0, -0.04, -0.34] },
	"mk48": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.46] },
	"negev": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.48] },
	"mg3": { "r": [0.012, -0.11, 0.055], "l": [0, -0.045, -0.42] },
	"m82a1": { "r": [0.012, -0.11, 0.065], "l": [0, -0.05, -0.5] },
	"l115": { "r": [0.012, -0.095, 0.065], "l": [0, -0.048, -0.32] },
	"sv98": { "r": [0.012, -0.095, 0.065], "l": [0, -0.045, -0.3] },
	"m2010": { "r": [0.012, -0.095, 0.065], "l": [0, -0.048, -0.34] },
	"sks": { "r": [0.012, -0.1, 0.045], "l": [0, -0.04, -0.3] },
	"m1a": { "r": [0.012, -0.1, 0.045], "l": [0, -0.042, -0.38] },
	"g28": { "r": [0.012, -0.1, 0.035], "l": [0, -0.035, -0.42] },
	"mk14": { "r": [0.012, -0.1, 0.035], "l": [0, -0.035, -0.42] },
	"m14": { "r": [0.012, -0.1, 0.045], "l": [0, -0.042, -0.4] },
	"ar10": { "r": [0.012, -0.1, 0.035], "l": [0, -0.035, -0.4] },
	"fal": { "r": [0.012, -0.1, 0.045], "l": [0, -0.042, -0.4] },
}

## 枪口 z 位置表
const MUZZLE_Z := {
	"m4": -0.8, "ak": -0.86, "mp5": -0.53, "m249": -0.9, "awm": -0.92, "m1014": -0.72,
	"m1911": -0.15, "rpg": -0.48, "gl": -0.42, "scar": -0.82, "aug": -0.66, "ump": -0.46, "p90": -0.35,
	"pkm": -0.94, "rpd": -0.88, "m24": -0.86, "svd": -0.84,
	"g17": -0.15, "p226": -0.155, "deagle": -0.21, "m93r": -0.18, "spas12": -0.75,
	# [8/10 武器扩充] 新枪枪口位置
	"g36c": -0.7, "ak74": -0.82, "famas": -0.72, "vector": -0.6, "pp19": -0.6,
	"mg42": -0.74, "m60": -0.76, "m110": -0.84, "m40": -0.74, "g3": -0.74,
	# [8/10 武器扩充 v2] 17 把新枪枪口位置
	"mpx": -0.7, "mp7": -0.52, "pp2000": -0.56, "mk48": -0.82, "negev": -0.86,
	"mg3": -0.74, "m82a1": -1.04, "l115": -0.9, "sv98": -0.84, "m2010": -0.92,
	"sks": -0.68, "m1a": -0.78, "g28": -0.78, "mk14": -0.84, "m14": -0.8,
	"ar10": -0.76, "fal": -0.78,
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
	"gl": { "muzzle": Vector3(0, 0.012, -0.38), "grip": Vector3(0, -0.06, -0.22), "trigger": Vector3(0, -0.055, 0.0), "optic": Vector3(0, 0.075, -0.06) },
	"m1911": { "muzzle": Vector3(0, 0.034, -0.155), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.062, -0.03) },
	"g17": { "muzzle": Vector3(0, 0.032, -0.165), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.06, -0.03) },
	"p226": { "muzzle": Vector3(0, 0.034, -0.165), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.062, -0.03) },
	"deagle": { "muzzle": Vector3(0, 0.04, -0.25), "mag": Vector3(0, -0.145, 0.05), "grip": Vector3(0, -0.038, -0.06), "trigger": Vector3(0, -0.058, -0.005), "optic": Vector3(0, 0.07, -0.05) },
	"m93r": { "muzzle": Vector3(0, 0.032, -0.18), "mag": Vector3(0, -0.145, 0.045), "grip": Vector3(0, -0.06, -0.1), "trigger": Vector3(0, -0.055, 0.005), "optic": Vector3(0, 0.06, -0.04) },
	# [8/10 武器扩充 v2] 17 把新枪改装锚点
	"mpx": { "muzzle": Vector3(0, 0.024, -0.7), "mag": Vector3(0, -0.12, -0.1), "grip": Vector3(0, -0.012, -0.4), "trigger": Vector3(0, -0.06, 0.005), "optic": Vector3(0, 0.086, -0.12) },
	"mp7": { "muzzle": Vector3(0, 0.022, -0.5), "mag": Vector3(0, -0.11, -0.1), "grip": Vector3(0, -0.01, -0.32), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.08, -0.1) },
	"pp2000": { "muzzle": Vector3(0, 0.024, -0.56), "mag": Vector3(0, -0.15, -0.08), "grip": Vector3(0, -0.01, -0.34), "trigger": Vector3(0, -0.06, 0.01), "optic": Vector3(0, 0.085, -0.1) },
	"mk48": { "muzzle": Vector3(0, 0.026, -0.82), "grip": Vector3(0, -0.015, -0.48), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.1, -0.12) },
	"negev": { "muzzle": Vector3(0, 0.026, -0.86), "grip": Vector3(0, -0.015, -0.5), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.098, -0.12) },
	"mg3": { "muzzle": Vector3(0, 0.024, -0.74), "grip": Vector3(0, -0.015, -0.42), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.095, -0.12) },
	"m82a1": { "muzzle": Vector3(0, 0.03, -1.04), "mag": Vector3(0, -0.1, -0.16), "grip": Vector3(0, -0.02, -0.5), "trigger": Vector3(0, -0.07, 0.02), "optic": Vector3(0, 0.1, -0.12) },
	"l115": { "muzzle": Vector3(0, 0.028, -0.9), "grip": Vector3(0, -0.012, -0.5), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.09, -0.06) },
	"sv98": { "muzzle": Vector3(0, 0.028, -0.84), "grip": Vector3(0, -0.012, -0.45), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.088, -0.06) },
	"m2010": { "muzzle": Vector3(0, 0.028, -0.92), "grip": Vector3(0, -0.012, -0.5), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.09, -0.06) },
	"sks": { "muzzle": Vector3(0, 0.026, -0.68), "mag": Vector3(0, -0.08, -0.06), "grip": Vector3(0, -0.012, -0.32), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.088, -0.08) },
	"m1a": { "muzzle": Vector3(0, 0.026, -0.78), "mag": Vector3(0, -0.11, -0.1), "grip": Vector3(0, -0.012, -0.4), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.09, -0.1) },
	"g28": { "muzzle": Vector3(0, 0.024, -0.78), "mag": Vector3(0, -0.1, -0.1), "grip": Vector3(0, -0.012, -0.42), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.088, -0.12) },
	"mk14": { "muzzle": Vector3(0, 0.024, -0.84), "mag": Vector3(0, -0.11, -0.1), "grip": Vector3(0, -0.012, -0.42), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.088, -0.14) },
	"m14": { "muzzle": Vector3(0, 0.026, -0.8), "mag": Vector3(0, -0.11, -0.1), "grip": Vector3(0, -0.012, -0.4), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.09, -0.1) },
	"ar10": { "muzzle": Vector3(0, 0.024, -0.76), "mag": Vector3(0, -0.1, -0.1), "grip": Vector3(0, -0.012, -0.4), "trigger": Vector3(0, -0.06, 0.005), "optic": Vector3(0, 0.086, -0.12) },
	"fal": { "muzzle": Vector3(0, 0.026, -0.78), "mag": Vector3(0, -0.11, -0.1), "grip": Vector3(0, -0.012, -0.4), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.088, -0.1) },
	# [8/10 武器扩充] 10 把新枪改装锚点(补齐,否则改装件挂到原点)
	"g36c": { "muzzle": Vector3(0, 0.024, -0.7), "grip": Vector3(0, -0.012, -0.32), "trigger": Vector3(0, -0.035, 0.01), "optic": Vector3(0, 0.082, 0.0) },
	"ak74": { "muzzle": Vector3(0, 0.028, -0.82), "grip": Vector3(0, -0.012, -0.36), "trigger": Vector3(0, -0.036, 0.02), "optic": Vector3(0, 0.072, -0.06) },
	"famas": { "muzzle": Vector3(0, 0.024, -0.72), "grip": Vector3(0, -0.022, -0.2), "trigger": Vector3(0, -0.034, 0.04), "optic": Vector3(0, 0.088, -0.1) },
	"vector": { "muzzle": Vector3(0, 0.024, -0.6), "grip": Vector3(0, -0.024, -0.3), "trigger": Vector3(0, -0.036, 0.01), "optic": Vector3(0, 0.086, -0.05) },
	"pp19": { "muzzle": Vector3(0, 0.024, -0.6), "grip": Vector3(0, -0.022, -0.3), "trigger": Vector3(0, -0.034, 0.0), "optic": Vector3(0, 0.08, -0.05) },
	"mg42": { "muzzle": Vector3(0, 0.024, -0.74), "grip": Vector3(0, -0.025, -0.4), "trigger": Vector3(0, -0.037, 0.02), "optic": Vector3(0, 0.078, 0.0) },
	"m60": { "muzzle": Vector3(0, 0.028, -0.76), "grip": Vector3(0, -0.024, -0.4), "trigger": Vector3(0, -0.036, 0.02), "optic": Vector3(0, 0.06, -0.18) },
	"m110": { "muzzle": Vector3(0, 0.024, -0.84), "grip": Vector3(0, -0.021, -0.42), "trigger": Vector3(0, -0.036, 0.01), "optic": Vector3(0, 0.086, -0.12) },
	"m40": { "muzzle": Vector3(0, 0.028, -0.74), "grip": Vector3(0, -0.024, -0.4), "trigger": Vector3(0, -0.036, 0.02), "optic": Vector3(0, 0.075, -0.14) },
	"g3": { "muzzle": Vector3(0, 0.024, -0.74), "grip": Vector3(0, -0.024, -0.4), "trigger": Vector3(0, -0.036, 0.02), "optic": Vector3(0, 0.086, -0.12) },
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
const _STD_IDS := {
	"muzzle": "muz_std", "barrel": "barrel_std", "grip": "grip_std", "stock": "stock_std",
	"mag": "mag_std", "trigger": "trig_std", "optic": "opt_std", "laser": "laser_std",
}

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
		"muz_comp":
			# 补偿器:双排侧孔短筒(水平后座泄压)
			m.add_child(cyl(0.023, 0.024, 0.09, 0, 0, -0.045, "metal"))
			for i in 3:
				m.add_child(box(0.02, 0.012, 0.012, 0.021, 0.008, -0.02 - i * 0.028, "poly"))
				m.add_child(box(0.02, 0.012, 0.012, -0.021, 0.008, -0.02 - i * 0.028, "poly"))
				m.add_child(box(0.02, 0.012, 0.012, 0.021, -0.008, -0.02 - i * 0.028, "poly"))
				m.add_child(box(0.02, 0.012, 0.012, -0.021, -0.008, -0.02 - i * 0.028, "poly"))
			m.add_child(cyl(0.026, 0.026, 0.009, 0, 0, -0.094, "dark"))      # 前口环
			m.add_child(cyl(0.025, 0.025, 0.008, 0, 0, 0.004, "dark"))       # 后接环
		"muz_choke":
			# 收束器(霰弹):前细后粗的锥形短管
			m.add_child(cyl(0.022, 0.016, 0.09, 0, 0, -0.045, "metal"))      # 锥形管
			m.add_child(cyl(0.0165, 0.0155, 0.012, 0, 0, -0.093, "dark"))    # 前口环(细)
			m.add_child(cyl(0.024, 0.024, 0.008, 0, 0, 0.004, "dark"))       # 后接环
	return m


## 枪管改装(挂枪管中段):长枪管(延长套管)/短枪管(收短段)/重型枪管(加粗散热箍)
static func build_mod_barrel(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var b := Node3D.new()
	b.name = "ModBarrel_" + mod_id
	match mod_id:
		"barrel_long":
			b.add_child(cyl(0.014, 0.015, 0.22, 0, 0, -0.11, "metal"))       # 延长套管
			b.add_child(cyl(0.016, 0.016, 0.012, 0, 0, -0.004, "dark"))      # 后箍
			b.add_child(cyl(0.016, 0.016, 0.012, 0, 0, -0.216, "dark"))      # 前箍
			b.add_child(cyl(0.017, 0.018, 0.03, 0, 0, -0.235, "dark"))       # 前口环(更远)
		"barrel_short":
			b.add_child(cyl(0.015, 0.016, 0.08, 0, 0, -0.04, "metal"))       # 收短段
			b.add_child(cyl(0.017, 0.018, 0.012, 0, 0, -0.088, "dark"))      # 短口环
			b.add_child(cyl(0.016, 0.016, 0.01, 0, 0, 0.004, "dark"))        # 后接环
		"barrel_heavy":
			b.add_child(cyl(0.02, 0.021, 0.22, 0, 0, -0.11, "dark"))         # 加粗枪管
			b.add_child(cyl(0.022, 0.022, 0.01, 0, 0, -0.006, "metal"))      # 后箍
			b.add_child(cyl(0.022, 0.022, 0.01, 0, 0, -0.11, "metal"))       # 中箍
			b.add_child(cyl(0.022, 0.022, 0.01, 0, 0, -0.214, "metal"))      # 前箍
	return b


## 枪托改装(挂机匣尾部,向 +Z 延伸):轻型(细杆)/重型(加厚托垫)/折叠(铰链短托)
static func build_mod_stock(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var s := Node3D.new()
	s.name = "ModStock_" + mod_id
	match mod_id:
		"stock_light":
			s.add_child(cyl(0.012, 0.013, 0.16, 0, 0.005, 0.14, "metal"))    # 细托杆
			s.add_child(box(0.028, 0.05, 0.045, 0, 0.002, 0.23, "dark"))     # 轻托尾
			s.add_child(box(0.026, 0.03, 0.008, 0, -0.02, 0.235, "poly"))    # 托肩垫
		"stock_heavy":
			s.add_child(box(0.03, 0.07, 0.16, 0, 0.012, 0.13, "dark"))       # 加厚托体
			s.add_child(box(0.034, 0.085, 0.05, 0, 0.014, 0.23, "poly"))     # 大托垫
			s.add_child(box(0.028, 0.04, 0.02, 0, 0.035, 0.05, "metal"))     # 顶部导轨槽
		"stock_fold":
			s.add_child(box(0.014, 0.018, 0.05, 0, 0.012, 0.06, "metal"))    # 铰链座
			s.add_child(box(0.02, 0.03, 0.12, 0, 0.006, 0.14, "dark"))       # 折叠短托
			s.add_child(box(0.024, 0.036, 0.03, 0, 0.006, 0.205, "poly"))    # 托尾垫
	return s


## 战术镭射(小圆柱+红光点)/战术手电(粗短筒+灯头)/红外镭射(细杆+绿点)
static func build_mod_laser(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var l := Node3D.new()
	l.name = "ModLaser_" + mod_id
	match mod_id:
		"laser_tac":
			l.add_child(cyl(0.009, 0.009, 0.07, 0, -0.035, -0.03, "dark"))   # 镭射管(朝前下)
			l.add_child(cyl(0.011, 0.011, 0.012, 0, -0.012, -0.004, "metal")) # 安装座
			l.add_child(box(0.006, 0.006, 0.006, 0, -0.078, -0.062, "red_glow"))  # 发射窗(红光)
		"laser_flash":
			l.add_child(cyl(0.014, 0.014, 0.06, 0, -0.03, -0.02, "dark"))    # 手电筒身
			l.add_child(cyl(0.018, 0.014, 0.018, 0, -0.03, -0.058, "chrome")) # 灯头
			l.add_child(cyl(0.01, 0.012, 0.015, 0, -0.03, 0.0, "metal"))      # 灯尾座
			l.add_child(box(0.004, 0.018, 0.004, 0.014, -0.035, -0.06, "dark"))  # 开关
		"laser_ir":
			l.add_child(cyl(0.007, 0.008, 0.06, 0, -0.03, -0.03, "dark"))    # 细镭射管
			l.add_child(cyl(0.01, 0.01, 0.01, 0, -0.012, -0.004, "metal"))    # 安装座
			l.add_child(box(0.004, 0.004, 0.004, 0, -0.066, -0.058, "green_glow"))  # 发射窗(绿光)
	return l


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
		"mag_drum":
			# 弹鼓:粗短圆鼓 + 底座(容量大,换弹慢)
			var drum := cyl(0.062, 0.062, 0.05, 0, b["c"] + 0.02, 0, "dark", "y")
			base.add_child(drum)
			base.add_child(cyl(0.06, 0.06, 0.012, 0, b["c"] + 0.045, 0, "metal", "y"))   # 上盖
			base.add_child(cyl(0.064, 0.064, 0.014, 0, b["c"] - 0.03, 0, "metal", "y"))  # 底盖
			base.add_child(box(b["w"] + 0.01, 0.03, b["d"] + 0.01, 0, b["c"] - 0.012, 0, "dark"))  # 颈部过渡
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
		"grip_fg":
			# 前握把:短竖把 + 微前倾 + 指槽(均衡型)
			var fg := box(0.024, 0.055, 0.028, 0, -0.03, 0, "olive")
			fg.rotation.x = 0.22
			gr.add_child(fg)
			gr.add_child(box(0.028, 0.014, 0.032, 0, -0.004, 0, "dark"))      # 顶安装座
			gr.add_child(box(0.026, 0.008, 0.03, 0, -0.056, 0, "dark"))      # 底部收尾
			gr.add_child(box(0.025, 0.005, 0.03, 0, -0.042, 0, "dark"))      # 指槽
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
			var rdot := MeshInstance3D.new()
			var rdp := PlaneMesh.new()
			rdp.size = Vector2(0.0012, 0.0012)
			rdot.mesh = rdp
			rdot.material_override = rm
			rdot.position = Vector3(0, 0, -0.03)
			rdot.name = "RetDot"
			o.add_child(rdot)  # 分划:极小实心红点(无圆环;开镜时由 2D HUD 稳定红点接管)
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
		"opt_reddot_mini":
			# 微型红点:紧凑小框 + 极小分划点(手枪/卡宾友好)
			o.add_child(box(0.014, 0.006, 0.018, 0, -0.012, -0.008, "dark"))   # 小底座
			o.add_child(box(0.012, 0.014, 0.002, 0, 0.001, 0.001, "lens_clear"))  # 小透镜窗
			o.add_child(box(0.002, 0.024, 0.038, -0.008, 0.001, -0.014, "dark"))  # 左镜框
			o.add_child(box(0.002, 0.024, 0.038, 0.008, 0.001, -0.014, "dark"))   # 右镜框
			o.add_child(box(0.016, 0.004, 0.02, 0, 0.013, -0.014, "dark"))        # 顶罩
			var mrd := MeshInstance3D.new()
			var mrdp := PlaneMesh.new()
			mrdp.size = Vector2(0.001, 0.001)
			mrd.mesh = mrdp
			mrd.material_override = rm
			mrd.position = Vector3(0, 0, -0.022)
			mrd.name = "RetDot"
			o.add_child(mrd)
		"opt_reddot_dot":
			# 大视窗红点:宽框大透镜 + 标准分划点
			o.add_child(box(0.03, 0.008, 0.03, 0, -0.014, -0.012, "dark"))     # 宽底座
			o.add_child(box(0.026, 0.024, 0.002, 0, 0.001, 0.001, "lens_clear")) # 大透镜窗
			o.add_child(box(0.003, 0.036, 0.06, -0.015, 0.001, -0.024, "dark"))  # 左镜框
			o.add_child(box(0.003, 0.036, 0.06, 0.015, 0.001, -0.024, "dark"))   # 右镜框
			o.add_child(box(0.032, 0.006, 0.022, 0, 0.02, -0.024, "dark"))       # 遮阳顶
			o.add_child(box(0.01, 0.011, 0.01, 0, 0.034, 0.004, "dark"))         # 调节钮
			var drd := MeshInstance3D.new()
			var drdp := PlaneMesh.new()
			drdp.size = Vector2(0.0013, 0.0013)
			drd.mesh = drdp
			drd.material_override = rm
			drd.position = Vector3(0, 0, -0.038)
			drd.name = "RetDot"
			o.add_child(drd)
		"opt_2x":
			# 2 倍战术镜:细长镜筒 + 目镜/物镜 + 十字分划(开镜由 2D tac 准星接管)
			o.add_child(box(0.02, 0.008, 0.04, 0, -0.012, -0.02, "dark"))       # 底座
			o.add_child(cyl(0.012, 0.012, 0.1, 0, 0, -0.055, "dark"))           # 镜筒
			o.add_child(cyl(0.0135, 0.0135, 0.006, 0, 0, -0.004, "metal"))      # 目镜环
			o.add_child(cyl(0.0155, 0.0155, 0.008, 0, 0, -0.106, "metal"))      # 物镜环
			o.add_child(cyl(0.011, 0.011, 0.003, 0, 0, -0.004, "lens_clear"))   # 目镜片
			o.add_child(cyl(0.013, 0.013, 0.003, 0, 0, -0.11, "lens_clear"))    # 物镜片
			o.add_child(box(0.006, 0.012, 0.01, 0, 0.02, -0.06, "dark"))        # 倍率调节钮
			# 十字分划(两片交叉平面,开镜时由 HUD tac 准星接管)
			var cr1 := box(0.0008, 0.018, 0.0008, 0, 0, -0.055, "red_glow")
			var cr2 := box(0.0008, 0.018, 0.0008, 0, 0, -0.055, "red_glow")
			cr2.rotation.y = PI / 2.0
			cr2.rotation.z = PI / 2.0
			cr1.name = "RetCross"
			cr2.name = "RetCross"
			o.add_child(cr1)
			o.add_child(cr2)
		"opt_1xprism":
			# 1 倍棱镜:紧凑筒 + 小分划点
			o.add_child(box(0.016, 0.007, 0.026, 0, -0.012, -0.012, "dark"))    # 底座
			o.add_child(cyl(0.01, 0.01, 0.05, 0, 0, -0.028, "dark"))            # 镜筒
			o.add_child(cyl(0.0115, 0.0115, 0.005, 0, 0, -0.004, "metal"))      # 目镜环
			o.add_child(cyl(0.0125, 0.0125, 0.006, 0, 0, -0.056, "metal"))      # 物镜环
			o.add_child(cyl(0.009, 0.009, 0.003, 0, 0, -0.004, "lens_clear"))   # 目镜片
			o.add_child(cyl(0.0105, 0.0105, 0.003, 0, 0, -0.06, "lens_clear"))  # 物镜片
			var prd := MeshInstance3D.new()
			var prdp := PlaneMesh.new()
			prdp.size = Vector2(0.0011, 0.0011)
			prd.mesh = prdp
			prd.material_override = rm
			prd.position = Vector3(0, 0, -0.03)
			prd.name = "RetDot"
			o.add_child(prd)
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
## 新槽位(barrel/stock/laser)锚点由既有锚点程序化推导,无需逐枪手写,新增武器自动生效
static func _apply_mods(g: Node3D, id: String, mods: Dictionary) -> void:
	if mods.is_empty():
		return
	var anchors: Dictionary = MOD_ANCHORS.get(id, {})
	for slot: String in mods:
		var mod_id: String = mods[slot]
		if mod_id == _STD_IDS.get(slot, ""):
			continue  # 标准件(原厂件):不挂载任何改装件
		var a: Vector3 = anchors.get(slot, Vector3.ZERO)
		if a == Vector3.ZERO:
			match slot:
				"barrel":
					# 枪管中段(枪口与握把之间)
					var bm: Vector3 = anchors.get("muzzle", Vector3(0, 0.02, -0.7))
					var bg: Vector3 = anchors.get("grip", Vector3(0, -0.01, -0.3))
					a = Vector3(0, bm.y, (bm.z + bg.z) * 0.5)
				"stock":
					# 机匣尾部(扳机后方)
					var bt: Vector3 = anchors.get("trigger", Vector3(0, -0.06, 0.0))
					a = bt + Vector3(0, 0.05, 0.22)
				"laser":
					# 护木下方(握把附近)
					var bl: Vector3 = anchors.get("grip", Vector3(0, -0.01, -0.3))
					a = bl + Vector3(0, -0.015, 0.02)
		match slot:
			"muzzle":
				var mu := build_mod_muzzle(mod_id)
				mu.position = a
				g.add_child(mu)
			"barrel":
				var ba := build_mod_barrel(mod_id)
				ba.position = a
				g.add_child(ba)
			"stock":
				var st2 := build_mod_stock(mod_id)
				st2.position = a
				g.add_child(st2)
			"laser":
				var la := build_mod_laser(mod_id)
				la.position = a
				g.add_child(la)
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
				var trigger_part := build_mod_trigger(mod_id)
				trigger_part.position = a
				g.add_child(trigger_part)
			"optic":
				var so := g.get_node_or_null("StockOptic")
				if so != null:
					so.visible = false
				var si := g.get_node_or_null("StockIrons")
				if si != null:
					si.visible = false
				var op := build_mod_optic(mod_id)
				var optic_anchor := _optic_anchor(id, a)
				var optic_host: Node3D = g
				if id == "m249" and g.has_meta("cover"):
					# M249 导轨装在受弹机盖上:瞄准镜也随盖开合,换弹时不会浮空/穿盖
					var cv: Node3D = g.get_meta("cover")
					if cv != null:
						optic_host = cv
						optic_anchor = optic_anchor - cv.position
				op.position = optic_anchor
				optic_host.add_child(op)


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


## ============ 近战小刀(程序化:棱形刀身 + 黑柄,单手右握) ============
## 原点位于护手处,刀尖朝 -Z;结构参考 build() 的 group 约定(meta: muzzle/right_hand/right_arm)
static func build_knife() -> Node3D:
	var g := Node3D.new()
	g.name = "Weapon_knife"
	# 刀身:中脊 + 上下斜刃面(菱形截面) + 锥形刀尖
	g.add_child(box(0.02, 0.003, 0.3, 0, 0, -0.24, "chrome"))            # 中脊
	var b1 := box(0.014, 0.007, 0.3, 0, 0.0045, -0.24, "chrome")
	b1.rotation.z = 0.55                                                    # 上斜面
	g.add_child(b1)
	var b2 := box(0.014, 0.007, 0.3, 0, -0.0045, -0.24, "chrome")
	b2.rotation.z = -0.55                                                   # 下斜面
	g.add_child(b2)
	g.add_child(cyl(0.008, 0.0, 0.07, 0, 0, -0.4, "chrome"))             # 刀尖锥(细端朝 -Z)
	# 护手(横挡)
	g.add_child(box(0.036, 0.026, 0.01, 0, 0, -0.05, "dark"))
	# 刀柄(黑):柄体 + 防滑环 + 尾帽
	g.add_child(box(0.022, 0.028, 0.14, 0, 0, 0.035, "poly"))
	for i in 3:
		g.add_child(box(0.024, 0.03, 0.008, 0, 0, 0.0 + i * 0.04, "dark"))
	g.add_child(box(0.026, 0.034, 0.022, 0, 0, 0.115, "dark"))
	# 刀口参考点(特效/调试对齐)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -0.45)
	g.add_child(muzzle)
	g.set_meta("muzzle", muzzle)
	# 右手握持(单手握刀)
	var right_hand := build_hand(false)
	right_hand.scale = Vector3.ONE * 1.15
	right_hand.position = Vector3(0.012, -0.022, 0.05)
	right_hand.rotation = Vector3(-0.2, -0.15, -1.3)
	g.add_child(right_hand)
	g.set_meta("right_hand", right_hand)
	var right_arm := build_forearm()
	right_arm.rotation = Vector3(0.72, 0.32, 0)
	g.add_child(right_arm)
	g.set_meta("right_arm", right_arm)
	# 视角模型不投影
	set_shadow_recursive(g, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	return g


## ============ [PERF] 静态网格合并(降低 Draw Call) ============
## 把「不参与动画、不被运行时隐藏」的静态 MeshInstance3D 合并为单个多材质 ArrayMesh,
## 每把枪 Draw Call 从 15~25 降到材质数(8~12)。
## 排除:所有 meta 引用节点(mag/bolt/pump/slide/rocket/muzzle/手/臂等动画件)、
## StockIrons/StockOptic/StockTrigger 可隐藏件、开镜分划(RetDot/RetRing/RetCross,由 gun.gd 切换显隐)。
static func _mergeable_collect(g: Node3D, out: Array[MeshInstance3D]) -> void:
	var skip: Dictionary = {}
	for key in g.get_meta_list():
		var n = g.get_meta(key)
		if n is Node:
			skip[n] = true
	for nm in ["StockIrons", "StockOptic", "StockTrigger"]:
		var n = g.get_node_or_null(nm)
		if n != null:
			skip[n] = true
	for c in g.get_children():
		if skip.has(c):
			continue
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.name != "RetDot" and mi.name != "RetRing" and mi.name != "RetCross":
				out.append(mi)
		elif c is Node3D:
			_mergeable_collect(c, out)


## 计算节点 m 相对 g 的累积变换(g 局部空间)
static func _rel_transform(g: Node3D, m: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = m
	while n != null and n != g:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _merge_static(g: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_mergeable_collect(g, meshes)
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
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var mv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var mn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var muv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var mi2: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tf := _rel_transform(g, mi3)
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
	mi.name = "MergedStatic"
	mi.mesh = am
	g.add_child(mi)
	for m in meshes:
		var p := m.get_parent()
		if p != null:
			p.remove_child(m)
		m.free()


## 前握把配件 → 左手持握偏移/旋转。
## 配件模型自身从 MOD_ANCHORS["grip"] 向下展开,因此手也必须移到握把体上,
## 而不是继续按裸枪护木位置悬空或穿模。
static func _foregrip_hand_pose(mod_id: String) -> Dictionary:
	match mod_id:
		"grip_vert":
			return { "pos": Vector3(0.0, -0.050, 0.006), "rot": Vector3(-0.42, -0.06, PI - 0.42) }
		"grip_ang":
			return { "pos": Vector3(0.0, -0.052, 0.010), "rot": Vector3(0.08, 0.12, PI - 0.28) }
		"grip_light":
			return { "pos": Vector3(0.0, -0.056, 0.006), "rot": Vector3(-0.16, 0.0, PI - 0.22) }
		"grip_fg":
			return { "pos": Vector3(0.0, -0.040, 0.006), "rot": Vector3(-0.24, 0.0, PI - 0.30) }
	return {}


## 构建完整武器模型(含枪口参考点;viewmodel = 第一人称时附带手模)
## mods = {槽位: 改装件id},见 MOD_ANCHORS 与 build_mod_*;不传/空 dict 行为与旧版完全一致
static func build(id: String, with_hands := false, mods := {}) -> Node3D:
	var g := Node3D.new()
	g.name = "Weapon_" + id
	_build(id, g)
	if not mods.is_empty():
		_apply_mods(g, id, mods)
	_merge_static(g)
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
		var left_pos := Vector3(anchors["l"][0], anchors["l"][1], anchors["l"][2])
		var left_rot := Vector3(0.1, 0, PI - 0.15)
		# 装备前握把类配件后,左手移到实际握把模型上,握姿随握把类型变化。
		var grip_mod: String = String(mods.get("grip", "grip_std"))
		if grip_mod != "grip_std" and MOD_ANCHORS.has(id) and MOD_ANCHORS[id].has("grip"):
			var grip_pose := _foregrip_hand_pose(grip_mod)
			if not grip_pose.is_empty():
				var grip_anchor: Vector3 = MOD_ANCHORS[id]["grip"]
				left_pos = grip_anchor + (grip_pose["pos"] as Vector3)
				left_rot = grip_pose["rot"] as Vector3
		left_hand.position = left_pos
		left_hand.rotation = left_rot
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
