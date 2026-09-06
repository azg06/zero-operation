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
		# 程序化生成的枪械 PBR 贴图(见 tools/gen_gun_textures.py):
		# 周期性正弦叠加 fBm 保证无缝平铺,各向异性控制拉丝方向。
		# 取代了原先的 metal_plate 钢板压花贴图(钢筋混凝土质感)。
		_mat["metal"] = _std(Color.html("#9aa0a8"), 0.45, 0.4, "gun_metal_diff.jpg", "gun_metal_nor.jpg")
		_mat["dark"] = _std(Color.html("#5a5e64"), 0.6, 0.3, "gun_dark_diff.jpg", "gun_dark_nor.jpg")
		_mat["poly"] = _std(Color.html("#3e4248"), 0.85, 0.05, "gun_poly_diff.jpg", "gun_poly_nor.jpg")
		_mat["tan"] = _std(Color.html("#b09a78"), 0.75, 0.1, "gun_poly_diff.jpg", "gun_poly_nor.jpg")
		_mat["wood"] = _std(Color.html("#a87848"), 0.75, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg")
		_mat["olive"] = _std(Color.html("#6a7458"), 0.75, 0.15, "gun_poly_diff.jpg", "gun_poly_nor.jpg")
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
		_mat["brass"] = _std(Color.html("#d0b070"), 0.4, 0.6, "gun_brass_diff.jpg", "gun_brass_nor.jpg")
		_mat["chrome"] = _std(Color.html("#d8dde2"), 0.18, 0.95, "gun_chrome_diff.jpg", "gun_chrome_nor.jpg")
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


## 稳定字符串哈希(材质变体种子)
static func _hash_text(s: String) -> int:
	var h := 17
	for i in s.length():
		h = (h * 131 + s.unicode_at(i)) % 1000003
	return h


## 为指定材质族生成材质变体。功能材质(镜片/分划/手/袖)保持原样。
##
## 变体池说明(性能关键):
##   _merge_static 按"材质对象"分组合并,一个材质变体 = 一个 surface = 一次 draw call。
##   高精度 GLB 模型零件数在 60~150 量级,若每个零件独占一个变体,单枪 draw call 就会
##   跟着零件数线性上涨 —— 战场上几十把枪同屏时会直接吃满。
##   这里把变体收敛成 _VARIANT_POOL 大小的池子循环复用:相邻零件大概率拿到不同变体
##   (层次感几乎不变),但 draw call 被压到"材质族数 × 池大小"的常量级。
const _VARIANT_POOL := 4

static func _part_material(mat_name: String) -> StandardMaterial3D:
	if _current_weapon.is_empty() or mat_name in _VARY_SKIP:
		return MAT()[mat_name] as StandardMaterial3D
	var slot := _current_part_idx % _VARIANT_POOL
	var key := "%s|%s|%d" % [_current_weapon, mat_name, slot]
	_current_part_idx += 1
	if _variant_cache.has(key):
		return _variant_cache[key] as StandardMaterial3D
	var base: StandardMaterial3D = MAT()[mat_name] as StandardMaterial3D
	var m := base.duplicate(true) as StandardMaterial3D
	var h := _hash_text(key)
	m.albedo_color = _variant_color(mat_name, h)
	# 整枪表面处理偏移:不同枪有整体偏亮/偏暗/偏冷/偏暖的完成度差异
	var weapon_finish := float(_hash_text(_current_weapon) % 9 - 4) * 0.022
	m.albedo_color = m.albedo_color.lightened(weapon_finish)
	var rough_delta := float((h >> 3) % 9 - 4) * 0.028
	var metal_delta := float((h >> 6) % 7 - 3) * 0.045
	m.roughness = clampf(base.roughness + rough_delta, 0.22, 0.96)
	m.metallic = clampf(base.metallic + metal_delta, 0.0, 1.0)
	_variant_cache[key] = m
	return m


static func _variant_color(mat_name: String, h: int) -> Color:
	var arr: Array = _METAL_VARIANTS
	match mat_name:
		"dark":
			arr = _DARK_VARIANTS
		"poly":
			arr = _POLY_VARIANTS
		"wood":
			arr = _WOOD_VARIANTS
		"tan":
			arr = _TAN_VARIANTS
		"olive":
			arr = _OLIVE_VARIANTS
		"brass":
			arr = _BRASS_VARIANTS
		"chrome":
			arr = _CHROME_VARIANTS
	var idx := absi((h + _current_weapon.length() * 37 + _current_part_idx * 13) % arr.size())
	return arr[idx] as Color


static var _box_mesh_cache: Dictionary = {}
static var _cyl_mesh_cache: Dictionary = {}
static var _torus_mesh_cache: Dictionary = {}

# === [材质分化] 每把枪 + 每个零部件独立材质 ===
# box/cyl/ring 创建网格时自动消耗一个部件序号,按 武器id+材质族+序号 生成确定性变体:
#   同枪不同部件颜色/粗糙度不同;不同枪的同名材质族也会整体偏移,不再整枪同一种材质。
static var _current_weapon := ""
static var _current_part_idx := 0
static var _variant_cache: Dictionary = {}
const _VARY_SKIP := ["glove", "sleeve", "glove_knuckle", "lens", "lens_clear", "ret_dark", "ret_light",
	"scope_black", "red_glow", "green_glow", "lamp_white"]
const _METAL_VARIANTS := [Color("#8c949c"), Color("#9aa2aa"), Color("#778089"), Color("#a7aeb5"),
	Color("#6d757e"), Color("#b2b8be"), Color("#818a93"), Color("#9fa8b0")]
const _DARK_VARIANTS := [Color("#4f5358"), Color("#5d6268"), Color("#44484d"), Color("#666b72"),
	Color("#3a3e43"), Color("#70757b"), Color("#585d63"), Color("#62686e")]
const _POLY_VARIANTS := [Color("#35393e"), Color("#41464c"), Color("#2c3035"), Color("#4a5057"),
	Color("#262a2e"), Color("#545a61"), Color("#3d4248"), Color("#5d646b")]
const _WOOD_VARIANTS := [Color("#a87848"), Color("#b98a58"), Color("#94683c"), Color("#c69a66"),
	Color("#825832"), Color("#d2a876"), Color("#ad7c50"), Color("#8f6038")]
const _TAN_VARIANTS := [Color("#b09a78"), Color("#bdA887"), Color("#a08a66"), Color("#cbb596"),
	Color("#8f7a58"), Color("#d9c3a4"), Color("#b5a080"), Color("#9c8668")]
const _OLIVE_VARIANTS := [Color("#6a7458"), Color("#788266"), Color("#5c6549"), Color("#879170"),
	Color("#4f5840"), Color("#96a17e"), Color("#707c60"), Color("#657058")]
const _BRASS_VARIANTS := [Color("#d0b070"), Color("#d9bc80"), Color("#c2a15f"), Color("#e2c68c"),
	Color("#b39150"), Color("#ecd4a0"), Color("#cbaa6c"), Color("#bd9b58")]
const _CHROME_VARIANTS := [Color("#d8dde2"), Color("#e3e8ec"), Color("#c8ced4"), Color("#edf1f4"),
	Color("#b9c0c7"), Color("#f5f8fa"), Color("#cfd5da"), Color("#c2c8ce")]


static func box(w: float, h: float, d: float, x: float, y: float, z: float, mat_name := "metal") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := Vector3(w, h, d)
	var bm: BoxMesh = _box_mesh_cache.get(key)
	if bm == null:
		bm = BoxMesh.new()
		bm.size = key
		_box_mesh_cache[key] = bm
	mi.mesh = bm
	mi.material_override = _part_material(mat_name)
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
	mi.material_override = _part_material(mat_name)
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
	mi.material_override = _part_material(mat_name)
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
	mi.material_override = _part_material(mat_name)
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

## ============ [9/10] 泵动霰弹枪 / 左轮手枪 程序化模块 ============
## 泵动霰弹枪:机匣 + 枪管 + 下挂管式弹仓 + 独立泵体/枪机/抛壳动画件。
## 枪口朝 -Z,泵体沿 Z 轴后拉(+Z)/前推(-Z);meta 与 Gun/ReloadController 完全对齐。
## 全部尺寸由 c 配置驱动,避免枪托/隔热罩/泵体肋条与机匣、枪管穿模。
static func _pump_shotgun(g: Node3D, c: Dictionary) -> void:
	var receiver_mat: String = c.get("receiver_mat", "metal")
	var furniture_mat: String = c.get("furniture_mat", "poly")
	var stock_mat: String = c.get("stock_mat", furniture_mat)
	var receiver_w: float = c.get("receiver_w", 0.05)
	var receiver_h: float = c.get("receiver_h", 0.075)
	var receiver_y: float = c.get("receiver_y", 0.018)
	var receiver_z0: float = c.get("receiver_z0", -0.17)
	var receiver_z1: float = c.get("receiver_z1", 0.13)
	var barrel_y: float = c.get("barrel_y", 0.045)
	var barrel_r: float = c.get("barrel_r", 0.014)
	var barrel_z0: float = c.get("barrel_z0", -0.22)
	var muzzle_z: float = c.get("muzzle_z", -0.74)
	var tube_y: float = c.get("tube_y", barrel_y - 0.052)
	var tube_r: float = c.get("tube_r", 0.0125)
	var tube_z0: float = c.get("tube_z0", -0.24)
	var tube_z1: float = c.get("tube_z1", -0.68)
	var pump_z: float = c.get("pump_z", -0.35)
	var pump_len: float = c.get("pump_len", 0.14)
	var pump_r: float = c.get("pump_r", 0.024)
	var semi_auto: bool = c.get("semi_auto", false)
	var stroke: float = c.get("stroke", 0.065)
	var heat_shield: bool = c.get("heat_shield", false)
	var exposed_hammer: bool = c.get("exposed_hammer", false)
	var ghost_ring: bool = c.get("ghost_ring", false)
	var bayonet_lug: bool = c.get("bayonet_lug", false)
	var straight_stock: bool = c.get("straight_stock", false)
	var sight_y: float = c.get("sight_y", 0.098)
	var receiver_bottom: float = receiver_y - receiver_h * 0.5
	var receiver_top: float = receiver_y + receiver_h * 0.5
	# 机匣:三段式轮廓(主体 + 上机匣 + 抛壳窗),不同枪型宽高长不同
	g.add_child(box(receiver_w, receiver_h, receiver_z1 - receiver_z0, 0, receiver_y,
		(receiver_z0 + receiver_z1) * 0.5, receiver_mat))
	g.add_child(box(receiver_w * 0.82, 0.022, (receiver_z1 - receiver_z0) * 0.72, 0,
		receiver_top - 0.008, (receiver_z0 + receiver_z1) * 0.5 - 0.015, receiver_mat))
	g.add_child(box(0.004, 0.02, 0.06, receiver_w * 0.5 + 0.003, receiver_y + 0.012, -0.055, "dark"))
	# 枪管:必须从机匣内部伸出,与机匣前缘连续,不能在中途断开
	var bz0 := receiver_z0 + 0.015
	var bz1 := muzzle_z - 0.015
	if bz1 <= bz0:
		bz1 = bz0 + 0.2
	g.add_child(cyl(barrel_r, barrel_r + 0.002, absf(bz1 - bz0), 0, barrel_y, (bz0 + bz1) * 0.5, receiver_mat))
	# 管式弹仓:限制在机匣前缘与枪口之间,泵体前后各露出正确长度
	var tz0 := maxf(tube_z0, receiver_z0 - 0.02)
	var tz1 := maxf(tube_z1, muzzle_z + 0.055)
	# 枪口朝 -Z:合法弹仓必须 tz1 < tz0;只有参数顺序颠倒时才回退
	if tz1 > tz0:
		tz1 = tz0 - 0.25
	g.add_child(cyl(tube_r, tube_r, absf(tz1 - tz0), 0, tube_y, (tz0 + tz1) * 0.5, "dark"))
	# 枪口帽:中心对准枪管实际前端,并包住枪管末端
	var muzzle_cap_z: float = bz1 + 0.008
	# 半自动霰弹枪:整段枪管被一体式护木/枪管罩包住,从机匣前缘一直延伸到枪口帽前
	var shroud_bottom := barrel_y - barrel_r
	if semi_auto:
		var sh_r := barrel_r + 0.009
		var sh_z0: float = receiver_z0 + 0.005
		var sh_z1: float = muzzle_cap_z - 0.02
		if sh_z0 > sh_z1:
			g.add_child(cyl(sh_r, sh_r, absf(sh_z1 - sh_z0), 0, barrel_y,
				(sh_z0 + sh_z1) * 0.5, furniture_mat, "z"))
			for i in 4:
				var slot_z := sh_z0 + absf(sh_z1 - sh_z0) * (0.2 + float(i) * 0.18)
				g.add_child(box(0.03, 0.008, 0.04, 0, barrel_y + sh_r + 0.003, slot_z, "dark"))
		shroud_bottom = barrel_y - sh_r
	# 枪管/弹仓连接箍:位于弹仓最前端,用竖直连接块从枪管底连到弹仓顶,不能悬浮在两者之间
	var clamp_z := tz1 + 0.009
	var barrel_bottom := barrel_y - barrel_r
	var tube_top := tube_y + tube_r
	var link_h := maxf(barrel_bottom - tube_top, 0.012)
	g.add_child(box(0.014, link_h, 0.02, 0, (barrel_bottom + tube_top) * 0.5, clamp_z, "dark"))
	g.add_child(cyl(barrel_r + 0.009, barrel_r + 0.011, 0.022, 0, barrel_y, muzzle_cap_z, "dark"))
	# 泵体 / 半自动固定护木
	var pmin := tz0 + pump_len * 0.5 + stroke + 0.02
	var pmax := tz1 - pump_len * 0.5 - stroke - 0.02
	var pump_zc := clampf(pump_z, minf(pmin, pmax), maxf(pmin, pmax))
	if semi_auto:
		# 半自动(M1014/SPAS-12):护木是固定件,直接桥接机匣前缘、枪管与弹仓,不再是一个可滑动圆筒
		var hg_rear := receiver_z0 - 0.035
		var hg_front := pump_zc + pump_len * 0.5
		if hg_rear > hg_front:
			var hg_len := absf(hg_front - hg_rear)
			var hg_top := shroud_bottom
			var hg_h := maxf(hg_top - (tube_y + tube_r), 0.02)
			g.add_child(box(receiver_w * 0.86, hg_h, hg_len, 0,
				(hg_top + tube_y + tube_r) * 0.5, (hg_rear + hg_front) * 0.5, furniture_mat))
			for i in 3:
				g.add_child(box(receiver_w * 0.72, 0.006, 0.012, 0,
					tube_y - tube_r - 0.005, hg_rear + (i + 0.5) * hg_len / 3.0, "dark"))
	else:
		# 泵动护木:一个大圆筒同时包住枪管与管式弹仓,前后带收口环,
		# 侧面与底部做纵向手指槽,不再是长条矩形。
		# 护木只包住管式弹仓,顶部开槽托住枪管但不与枪管融合;
		# 外径 = 护木半径,位置 = 弹仓轴线,枪管与护木之间保持可见间隙。
		var pump_center_y := tube_y
		var pump_radius := pump_r
		var pump := Node3D.new()
		pump.name = "PumpForend"
		pump.position = Vector3(0, pump_center_y, pump_zc)
		pump.add_child(cyl(pump_radius, pump_radius, pump_len, 0, 0, 0, furniture_mat, "z"))
		pump.add_child(cyl(pump_radius - 0.006, pump_radius + 0.002, 0.02, 0, 0, -pump_len * 0.5 + 0.01, "dark", "z"))
		pump.add_child(cyl(pump_radius + 0.002, pump_radius - 0.006, 0.02, 0, 0, pump_len * 0.5 - 0.01, "dark", "z"))
		var groove_len := pump_len * 0.68
		for side in [-1.0, 1.0]:
			pump.add_child(box(0.008, 0.008, groove_len, side * (pump_radius - 0.004), -pump_radius * 0.18, 0, "dark"))
			pump.add_child(box(0.008, 0.008, groove_len, side * (pump_radius - 0.004), pump_radius * 0.2, 0, "dark"))
		pump.add_child(box(pump_radius * 1.7, 0.009, groove_len, 0, -pump_radius - 0.004, 0, "dark"))
		# 顶部枪管托槽:护木上端为浅槽,枪管悬在槽上方,不和护木长成一体
		pump.add_child(box(pump_radius * 1.25, 0.007, groove_len, 0, pump_radius - 0.002, 0, "dark"))
		# 双动作杆:从护木后端伸向机匣,随护木一起前后运动(870/590/1897 的真实结构)
		for side in [-1.0, 1.0]:
			pump.add_child(box(0.006, 0.006, 0.15, side * (pump_radius - 0.004), 0.0,
				pump_len * 0.5 - 0.04, "metal"))
		g.add_child(pump)
		g.set_meta("pump", pump)
		g.set_meta("pump_grip_offset", Vector3(0, -pump_radius - 0.012, 0))
	# 枪机/护木连杆(独立动画件):沿机匣左侧外表面运动,不和抛壳窗/机匣穿插
	var bolt_x := -receiver_w * 0.5 - 0.004
	var bolt := Node3D.new()
	bolt.name = "PumpBolt"
	bolt.position = Vector3(bolt_x, receiver_y + 0.014, -0.03)
	bolt.add_child(box(0.012, 0.014, 0.07, 0, 0, 0, "metal"))
	bolt.add_child(box(0.02, 0.009, 0.024, 0.002, 0.012, -0.018, "dark"))
	g.add_child(bolt)
	g.set_meta("bolt", bolt)
	# 抛壳动画件:从右侧抛壳窗飞出(外置,不嵌进机匣)
	var eject_x := receiver_w * 0.5 + 0.002
	var eject_shell := cyl(0.009, 0.009, 0.045, eject_x, receiver_y + 0.014, -0.045, "brass", "z")
	eject_shell.visible = false
	g.add_child(eject_shell)
	g.set_meta("eject_shell", eject_shell)
	# 枪托与握把:顶端严格贴合机匣底,老式枪采用直托,战术枪采用手枪式握把
	var grip_top: float = receiver_bottom
	if straight_stock:
		g.add_child(_grip(0.04, 0.075, 0.19, 0, grip_top, receiver_z1 + 0.04, stock_mat, 0.07))
		g.add_child(box(0.042, 0.075, 0.022, 0, grip_top - 0.012, receiver_z1 + 0.125, stock_mat))
	else:
		g.add_child(_grip(0.042, 0.08, 0.16, 0, grip_top, receiver_z1 + 0.02, stock_mat, 0.12))
		g.add_child(box(0.044, 0.08, 0.022, 0, grip_top - 0.006, receiver_z1 + 0.115, stock_mat))
	g.add_child(_grip(0.034, 0.095, 0.045, 0, grip_top, 0.04, stock_mat, 0.38))
	_trigger(g, receiver_bottom - 0.012, 0.01)
	# 外露击锤(温彻斯特 1897 特征),位于机匣尾部上方但不高于瞄准线
	if exposed_hammer:
		var ham := Node3D.new()
		ham.position = Vector3(0, receiver_top + 0.008, receiver_z1 - 0.015)
		ham.add_child(cyl(0.007, 0.007, 0.012, 0, 0, 0, "metal", "z"))
		ham.add_child(box(0.014, 0.02, 0.008, 0, 0.015, -0.003, "metal"))
		g.add_child(ham)
	# 隔热罩:紧贴枪管顶部,跨过护木前部到枪口中段,不压准星、不穿机匣
	var sight_base_y := barrel_y + barrel_r + 0.005
	if semi_auto:
		# 半自动枪管罩高于裸枪管,准星底座必须从枪管罩顶部长出
		sight_base_y = barrel_y + barrel_r + 0.009 + 0.004
	if heat_shield:
		var hs_z0 := receiver_z0 - 0.06
		var hs_z1 := maxf(muzzle_z + 0.12, hs_z0 - 0.32)
		if hs_z0 > hs_z1:
			var shield_top := barrel_y + barrel_r + 0.012
			g.add_child(box(0.036, 0.011, hs_z0 - hs_z1, 0, barrel_y + barrel_r + 0.0065,
				(hs_z0 + hs_z1) * 0.5, "dark"))
			sight_base_y = shield_top + 0.004
	# 枪管顶部连续肋条:从机匣前缘一直连到枪口帽,枪管/枪口/准星成为一条整体
	var rib_rear := receiver_z0 - 0.05
	var rib_front := muzzle_cap_z + 0.025
	if rib_rear > rib_front:
		g.add_child(box(0.02, 0.006, absf(rib_front - rib_rear), 0, sight_base_y + 0.003,
			(rib_rear + rib_front) * 0.5, "dark"))
	# 刺刀座(温彻斯特 1897 堑壕枪特征):贴在弹仓前端下方,不越过枪口
	if bayonet_lug:
		g.add_child(box(0.018, 0.03, 0.02, 0, tube_y - tube_r - 0.016, tz1 - 0.04, "dark"))
	# 瞄具:低轮廓珠状准星 + 低照门/鬼环,ADS 中心线只留一个小珠,不让大片照门座挡视野
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	var front_z := muzzle_cap_z + 0.04
	var front_base_bottom := sight_base_y + 0.006
	var front_base_h := maxf((sight_y - 0.012) - front_base_bottom, 0.008)
	ir.add_child(box(0.012, front_base_h, 0.014, 0, front_base_bottom + front_base_h * 0.5,
		front_z, "dark"))
	ir.add_child(cyl(0.0038, 0.0038, 0.014, 0, sight_y, front_z, "brass", "y"))
	var rear_base_bottom := receiver_top
	var rear_base_h := maxf((sight_y - 0.02) - rear_base_bottom, 0.008)
	ir.add_child(box(0.024, rear_base_h, 0.016, 0, rear_base_bottom + rear_base_h * 0.5,
		0.085, "dark"))
	if ghost_ring:
		ir.add_child(ring(0.009, 0.0135, 0, sight_y, 0.085, "dark"))
	else:
		ir.add_child(box(0.003, 0.013, 0.012, -0.006, sight_y - 0.008, 0.085, "dark"))
		ir.add_child(box(0.003, 0.013, 0.012, 0.006, sight_y - 0.008, 0.085, "dark"))
	# 装填口/检视锚点:贴机匣底,不悬空
	var load_port := Node3D.new()
	load_port.name = "LoadPort"
	load_port.position = Vector3(0, receiver_bottom - 0.01, -0.04)
	g.add_child(load_port)
	g.set_meta("load_port", load_port)
	g.set_meta("inspect_point", Vector3(0.0, receiver_y + 0.005, -0.07))
	# 泵动行程只读参数(供 Gun 运行时装填/泵动使用)
	g.set_meta("pump_stroke", stroke)


## 左轮手枪:可绕前铰链摆出的弹巢 + 独立击锤 + 逐膛可见弹壳。
## 弹巢绕自身 Z 轴旋转(换膛),整体随 crane 绕 Y 轴摆出装填;壳位与实际弹药严格同步。
static func _revolver(g: Node3D, c: Dictionary) -> void:
	var cap: int = c.get("chambers", 6)
	var barrel_len: float = c.get("barrel_len", 0.11)
	var frame_mat: String = c.get("frame_mat", "metal")
	var grip_mat: String = c.get("grip_mat", "wood")
	var barrel_y: float = c.get("barrel_y", 0.032)
	var heavy: bool = c.get("heavy", false)
	var sight_y: float = c.get("sight_y", 0.078)
	var style: String = c.get("style", "")
	var vent_rib: bool = c.get("vent_rib", false)
	var underlug: bool = c.get("underlug", false)
	var top_rail: bool = c.get("top_rail", false)
	var compensator: bool = c.get("compensator", false)
	var fluted: bool = c.get("fluted", true)
	var grip_style: String = c.get("grip_style", "target")
	# 三把枪骨架尺寸不同:500 是宽大的 X 框架,686 紧凑,蟒蛇介于两者之间。
	# 机匣高度/宽度必须明显小于弹巢,让弹巢从方形机匣轮廓中露出来。
	var frame_w := 0.044 if heavy else (0.041 if style == "python" else 0.037)
	var frame_h := 0.056 if heavy else (0.052 if style == "python" else 0.048)
	var frame_y := 0.024 if heavy else (0.023 if style == "python" else 0.021)
	var front_w := frame_w - 0.002
	var front_h := frame_h - 0.012
	var cyl_r := 0.025 if heavy else (0.023 if style == "python" else 0.021)
	var cyl_len := 0.058 if heavy else (0.055 if style == "python" else 0.052)
	# 后机匣 + 前枪管座(中间留出弹巢窗口):顶面压低,不挡 ADS
	g.add_child(box(frame_w, frame_h, 0.1, 0, frame_y, -0.01, frame_mat))
	g.add_child(box(front_w, front_h, 0.06, 0, frame_y - 0.005, -0.125, frame_mat))
	var top_strap_y := barrel_y + cyl_r + 0.007
	g.add_child(box(frame_w - 0.004, 0.009, 0.09, 0, top_strap_y, -0.085, frame_mat))
	# 枪管:python 带通风肋,686 有全尺寸下挂退壳杆护管,500 用重管 + 顶部战术轨 + 制退器
	var barrel_len_total: float = barrel_len + 0.13
	var barrel_center_z: float = -0.155 - barrel_len_total * 0.5
	var front_z: float = -0.155 - barrel_len_total + 0.02
	var barrel_r := 0.014 if heavy else (0.0115 if style == "python" else 0.0105)
	g.add_child(cyl(barrel_r, barrel_r + 0.001, barrel_len_total, 0, barrel_y, barrel_center_z, frame_mat))
	g.add_child(cyl(barrel_r + 0.004, barrel_r + 0.005, 0.03, 0, barrel_y,
		-0.155 - barrel_len_total, "dark"))
	if vent_rib:
		var rib_z1 := front_z - 0.01
		g.add_child(box(0.016, 0.007, absf(-0.17 - rib_z1), 0, barrel_y + barrel_r + 0.006,
			(-0.17 + rib_z1) * 0.5, frame_mat))
		for i in 5:
			var slot_z := -0.2 - float(i) * 0.055
			g.add_child(box(0.006, 0.004, 0.022, 0, barrel_y + barrel_r + 0.013, slot_z, "dark"))
	if underlug:
		var lug_z0 := -0.19
		var lug_z1 := front_z + 0.03
		if lug_z0 > lug_z1:
			g.add_child(cyl(0.0085, 0.009, absf(lug_z1 - lug_z0), 0, barrel_y - barrel_r - 0.008,
				(lug_z0 + lug_z1) * 0.5, frame_mat))
	g.add_child(cyl(0.005, 0.005, barrel_len_total * 0.55, 0, barrel_y - 0.017,
		-0.2 - barrel_len_total * 0.27, frame_mat))                       # 退壳杆
	if top_rail:
		g.add_child(box(0.024, 0.008, absf(-0.16 - front_z), 0, barrel_y + barrel_r + 0.01,
			(-0.16 + front_z) * 0.5, "dark"))
	if compensator:
		g.add_child(cyl(0.018, 0.019, 0.042, 0, barrel_y, front_z - 0.01, "dark"))
		for side in [-1.0, 1.0]:
			g.add_child(box(0.02, 0.012, 0.012, side * 0.018, barrel_y + 0.012, front_z - 0.012, "dark"))
	# 弹巢摆出铰链:枢轴位于枪管轴前下方偏右,弹巢重心在枢轴后上方,开巢向左侧滚出
	var crane := Node3D.new()
	crane.name = "RevolverCrane"
	crane.position = Vector3(0.005, barrel_y - 0.017, -0.152)
	g.add_child(crane)
	g.set_meta("crane", crane)
	var cylinder := Node3D.new()
	cylinder.name = "RevolverCylinder"
	cylinder.position = Vector3(0.0, 0.014, 0.072)
	cylinder.add_child(cyl(cyl_r, cyl_r, cyl_len, 0, 0, 0, frame_mat, "z"))
	if fluted:
		for i in cap:
			var flute := box(0.007 if not heavy else 0.009, cyl_len * 0.72, cyl_len,
				0, 0, 0, "dark")
			flute.rotation.z = float(i) * TAU / float(cap)
			cylinder.add_child(flute)
	else:
		for i in cap:
			var band := box(0.046, cyl_len * 0.22, cyl_len, 0, 0, 0, "dark")
			band.rotation.z = float(i) * TAU / float(cap)
			cylinder.add_child(band)
	crane.add_child(cylinder)
	g.set_meta("cylinder", cylinder)
	# 逐膛弹壳(独立可见性 = 实际弹巢状态)
	var shells: Array = []
	var shell_radius: float = cyl_r - 0.007
	for i in cap:
		var ang := float(i) * TAU / float(cap)
		var shell := cyl(0.0045, 0.0045, 0.014, sin(ang) * shell_radius, cos(ang) * shell_radius,
			cyl_len * 0.5 - 0.001, "brass", "z")
		shell.name = "ChamberShell_%d" % i
		cylinder.add_child(shell)
		shells.append(shell)
	g.set_meta("chamber_shells", shells)
	# 击锤:蟒蛇宽靶锤,686 短平,500 大型战斗锤
	var hammer := Node3D.new()
	hammer.name = "RevolverHammer"
	hammer.position = Vector3(0, 0.046, 0.045)
	var hammer_w := 0.014 if style == "python" else (0.012 if not heavy else 0.017)
	var hammer_h := 0.026 if style == "python" else (0.022 if not heavy else 0.03)
	var hammer_spur := box(hammer_w, hammer_h, 0.008, 0, hammer_h * 0.5, -0.002, frame_mat)
	hammer_spur.rotation.x = -0.35
	hammer.add_child(hammer_spur)
	g.add_child(hammer)
	g.set_meta("hammer", hammer)
	# 握把:三把枪完全不同(木制靶握把 / 橡胶指槽握把 / X 框架大握把)
	var grip_top := frame_y - frame_h * 0.5
	match grip_style:
		"hogue":
			g.add_child(_grip(0.032, 0.095, 0.048, 0, grip_top, 0.045, grip_mat, 0.32))
			for i in 2:
				var groove := box(0.034, 0.006, 0.046, 0, grip_top - 0.035 - i * 0.016, 0.042, "dark")
				g.add_child(groove)
		"xframe":
			g.add_child(_grip(0.042, 0.115, 0.055, 0, grip_top, 0.05, grip_mat, 0.3))
			g.add_child(box(0.046, 0.03, 0.05, 0, grip_top - 0.005, 0.05, frame_mat))
			g.add_child(box(0.046, 0.022, 0.018, 0, grip_top - 0.1, 0.072, "dark"))
		_:
			g.add_child(_grip(0.038, 0.105, 0.05, 0, grip_top, 0.045, grip_mat, 0.32))
			g.add_child(box(0.012, 0.012, 0.006, 0.018, grip_top - 0.045, 0.042, "brass"))
			g.add_child(box(0.012, 0.012, 0.006, -0.018, grip_top - 0.045, 0.042, "brass"))
	_trigger(g, frame_y - frame_h * 0.5 - 0.012, 0.0)
	# 机械瞄具:python 红色坡道准星,686 黑柱,500 高位黑柱
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	var front_base_h := maxf((sight_y - 0.012) - (barrel_y + barrel_r), 0.014)
	ir.add_child(box(0.018, front_base_h, 0.018, 0, barrel_y + barrel_r + front_base_h * 0.5,
		front_z, "dark"))
	ir.add_child(box(0.009, 0.024, 0.009, 0, sight_y - 0.002, front_z,
		"brass" if style == "python" else "dark"))
	var rear_base_h := maxf((sight_y - 0.014) - top_strap_y, 0.012)
	ir.add_child(box(0.02, rear_base_h, 0.016, 0, top_strap_y + rear_base_h * 0.5, 0.045, "dark"))
	ir.add_child(box(0.005, 0.02, 0.014, -0.007, sight_y - 0.004, 0.045, "dark"))
	ir.add_child(box(0.005, 0.02, 0.014, 0.007, sight_y - 0.004, 0.045, "dark"))
	g.set_meta("inspect_point", Vector3(0.0, 0.03, -0.08))


## [9/10] 半自动霰弹枪专用一体式枪身(M1014 / SPAS-12)。
## 参考实物结构:机匣与枪管护木/隔热罩是同一段连续枪身,枪管包在枪身内部,
## 枪口帽与准星都安装在枪身前端;不存在裸露枪管与机匣之间的空隙。
static func _semi_shotgun(g: Node3D, c: Dictionary) -> void:
	var body_mat: String = c.get("body_mat", "poly")
	var furniture_mat: String = c.get("furniture_mat", body_mat)
	var stock_mat: String = c.get("stock_mat", furniture_mat)
	var body_w: float = c.get("body_w", 0.052)
	var body_h: float = c.get("body_h", 0.068)
	var body_y: float = c.get("body_y", 0.045)
	var muzzle_z: float = c.get("muzzle_z", -0.7)
	var tube_y: float = c.get("tube_y", -0.006)
	var tube_r: float = c.get("tube_r", 0.012)
	var tube_z1: float = c.get("tube_z1", -0.63)
	var sight_y: float = c.get("sight_y", 0.096)
	var top_rail: bool = c.get("top_rail", true)
	var heat_slots: bool = c.get("heat_slots", false)
	var folding_stock: bool = c.get("folding_stock", false)
	var body_rear := 0.13
	var body_front := muzzle_z - 0.012
	var body_len := absf(body_front - body_rear)
	var body_center_z := (body_rear + body_front) * 0.5
	var body_bottom := body_y - body_h * 0.5
	var body_top := body_y + body_h * 0.5
	# 一体式上部枪身:机匣、枪管罩、护木上段是同一根主体
	g.add_child(box(body_w, body_h, body_len, 0, body_y, body_center_z, body_mat))
	# 下护木从枪身底部连到弹仓下方,和枪身完全贴合
	var tube_z0 := -0.2
	if tube_z1 > tube_z0:
		tube_z1 = tube_z0 - 0.3
	var hg_rear := -0.14
	var hg_front := tube_z1 + 0.015
	if hg_rear > hg_front:
		var hg_len := absf(hg_front - hg_rear)
		var hg_bottom := tube_y - tube_r - 0.008
		var hg_h := maxf(body_bottom - hg_bottom, 0.018)
		g.add_child(box(body_w * 0.88, hg_h, hg_len, 0,
			(hg_bottom + body_bottom) * 0.5, (hg_rear + hg_front) * 0.5, furniture_mat))
	# 管式弹仓:前半段露出,后半段被下护木包住
	g.add_child(cyl(tube_r, tube_r, absf(tube_z1 - tube_z0), 0, tube_y, (tube_z0 + tube_z1) * 0.5, "dark"))
	# 顶部导轨 / SPAS 式隔热槽,都直接长在枪身顶部
	if top_rail:
		_rail(g, body_top, body_rear, body_front - 0.02, body_w - 0.018, "dark")
	elif heat_slots:
		for i in 4:
			var sz := body_rear - 0.05 - float(i) * 0.1
			g.add_child(box(0.026, 0.006, 0.055, 0, body_top + 0.004, sz, "dark"))
	# 抛壳窗/枪机/抛壳动画件
	g.add_child(box(0.004, 0.018, 0.07, body_w * 0.5 + 0.003, body_y + 0.004, -0.06, "dark"))
	var bolt_x := -body_w * 0.5 - 0.004
	var bolt := Node3D.new()
	bolt.name = "SemiAutoBolt"
	bolt.position = Vector3(bolt_x, body_y + 0.012, -0.03)
	bolt.add_child(box(0.012, 0.014, 0.075, 0, 0, 0, "metal"))
	bolt.add_child(box(0.02, 0.009, 0.024, 0.002, 0.012, -0.018, "dark"))
	g.add_child(bolt)
	g.set_meta("bolt", bolt)
	var eject_x := body_w * 0.5 + 0.002
	var eject_shell := cyl(0.009, 0.009, 0.045, eject_x, body_y + 0.012, -0.05, "brass", "z")
	eject_shell.visible = false
	g.add_child(eject_shell)
	g.set_meta("eject_shell", eject_shell)
	# 枪口帽:装在一体枪身前端,不是独立悬空件
	var cap_z := body_front + 0.01
	g.add_child(cyl(0.017, 0.018, 0.024, 0, body_y, cap_z, "dark"))
	# 枪托/握把/扳机:顶端与一体枪身底部贴合
	if folding_stock:
		g.add_child(box(0.01, 0.05, 0.16, 0, body_top + 0.015, 0.16, "metal"))
	g.add_child(_grip(0.042, 0.08, 0.16, 0, body_bottom, 0.16, stock_mat, 0.1))
	g.add_child(box(0.044, 0.08, 0.022, 0, body_bottom - 0.004, 0.25, stock_mat))
	g.add_child(_grip(0.034, 0.095, 0.045, 0, body_bottom, 0.04, stock_mat, 0.38))
	_trigger(g, body_bottom - 0.012, 0.01)
	# 瞄具:低轮廓珠状准星 + 低照门,ADS 中心线只留一个小珠,枪身不会遮住目标
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	var front_z := body_front + 0.04
	var fbase_h := maxf(sight_y - body_top - 0.012, 0.008)
	ir.add_child(box(0.012, fbase_h, 0.014, 0, body_top + fbase_h * 0.5, front_z, "dark"))
	ir.add_child(cyl(0.0038, 0.0038, 0.014, 0, sight_y, front_z, "brass", "y"))
	var rbase_h := maxf(sight_y - body_top - 0.02, 0.008)
	ir.add_child(box(0.024, rbase_h, 0.016, 0, body_top + rbase_h * 0.5, 0.085, "dark"))
	ir.add_child(box(0.003, 0.013, 0.012, -0.006, sight_y - 0.008, 0.085, "dark"))
	ir.add_child(box(0.003, 0.013, 0.012, 0.006, sight_y - 0.008, 0.085, "dark"))
	var load_port := Node3D.new()
	load_port.name = "LoadPort"
	load_port.position = Vector3(0, body_bottom - 0.01, -0.05)
	g.add_child(load_port)
	g.set_meta("load_port", load_port)
	g.set_meta("inspect_point", Vector3(0.0, body_y + 0.004, -0.07))


## ============ [9/10] 三把泵动霰弹枪专用重做 ============
static func _shotgun_stock(g: Node3D, grip_top: float, z_rear: float, stock_mat: String, straight: bool) -> void:
	if straight:
		g.add_child(_grip(0.04, 0.075, 0.19, 0, grip_top, z_rear + 0.05, stock_mat, 0.07))
		g.add_child(box(0.042, 0.075, 0.022, 0, grip_top - 0.01, z_rear + 0.13, stock_mat))
	else:
		g.add_child(_grip(0.042, 0.08, 0.16, 0, grip_top, z_rear + 0.02, stock_mat, 0.12))
		g.add_child(box(0.044, 0.08, 0.022, 0, grip_top - 0.005, z_rear + 0.12, stock_mat))
	g.add_child(_grip(0.034, 0.095, 0.045, 0, grip_top, 0.04, stock_mat, 0.38))
	_trigger(g, grip_top - 0.012, 0.01)


static func _shotgun_sights(g: Node3D, sight_y: float, base_y: float, front_z: float, rear_z: float, ghost: bool) -> void:
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	var fbase_h := maxf(sight_y - base_y - 0.012, 0.008)
	ir.add_child(box(0.012, fbase_h, 0.014, 0, base_y + fbase_h * 0.5, front_z, "dark"))
	ir.add_child(cyl(0.0038, 0.0038, 0.014, 0, sight_y, front_z, "brass", "y"))
	var rbase_h := maxf(sight_y - base_y - 0.02, 0.008)
	ir.add_child(box(0.024, rbase_h, 0.016, 0, base_y + rbase_h * 0.5, rear_z, "dark"))
	if ghost:
		ir.add_child(ring(0.009, 0.0135, 0, sight_y, rear_z, "dark"))
	else:
		ir.add_child(box(0.003, 0.013, 0.012, -0.006, sight_y - 0.008, rear_z, "dark"))
		ir.add_child(box(0.003, 0.013, 0.012, 0.006, sight_y - 0.008, rear_z, "dark"))


static func _pump_forend(g: Node3D, radius: float, length: float, center_y: float, center_z: float, mat: String) -> void:
	var pump := Node3D.new()
	pump.name = "PumpForend"
	pump.position = Vector3(0, center_y, center_z)
	pump.add_child(cyl(radius, radius, length, 0, 0, 0, mat, "z"))
	pump.add_child(cyl(radius - 0.006, radius + 0.002, 0.02, 0, 0, -length * 0.5 + 0.01, "dark", "z"))
	pump.add_child(cyl(radius + 0.002, radius - 0.006, 0.02, 0, 0, length * 0.5 - 0.01, "dark", "z"))
	var groove_len := length * 0.66
	for side in [-1.0, 1.0]:
		pump.add_child(box(0.008, 0.008, groove_len, side * (radius - 0.004), -radius * 0.18, 0, "dark"))
		pump.add_child(box(0.008, 0.008, groove_len, side * (radius - 0.004), radius * 0.2, 0, "dark"))
	pump.add_child(box(radius * 1.7, 0.009, groove_len, 0, -radius - 0.004, 0, "dark"))
	pump.add_child(box(radius * 1.25, 0.007, groove_len, 0, radius - 0.002, 0, "dark"))
	for side in [-1.0, 1.0]:
		pump.add_child(box(0.006, 0.006, 0.15, side * (radius - 0.004), 0.0, length * 0.5 - 0.04, "metal"))
	g.add_child(pump)
	g.set_meta("pump", pump)
	g.set_meta("pump_grip_offset", Vector3(0, -radius - 0.012, 0))


static func _shotgun_action(g: Node3D, receiver_w: float, receiver_y: float, receiver_z0: float) -> void:
	var bolt_x := -receiver_w * 0.5 - 0.004
	var bolt := Node3D.new()
	bolt.name = "PumpBolt"
	bolt.position = Vector3(bolt_x, receiver_y + 0.012, -0.03)
	bolt.add_child(box(0.012, 0.014, 0.075, 0, 0, 0, "metal"))
	bolt.add_child(box(0.02, 0.009, 0.024, 0.002, 0.012, -0.018, "dark"))
	g.add_child(bolt)
	g.set_meta("bolt", bolt)
	var eject_x := receiver_w * 0.5 + 0.002
	var eject_shell := cyl(0.009, 0.009, 0.045, eject_x, receiver_y + 0.012, -0.05, "brass", "z")
	eject_shell.visible = false
	g.add_child(eject_shell)
	g.set_meta("eject_shell", eject_shell)


static func _build_rem870(g: Node3D) -> void:
	var receiver_w := 0.048
	var receiver_h := 0.072
	var receiver_y := 0.018
	var receiver_z0 := -0.16
	var receiver_z1 := 0.12
	var barrel_y := 0.045
	var barrel_r := 0.016
	var muzzle_z := -0.73
	var tube_y := -0.006
	var tube_r := 0.012
	var tube_z0 := -0.26
	var tube_z1 := -0.68
	var sight_y := 0.098
	var receiver_bottom := receiver_y - receiver_h * 0.5
	var receiver_top := receiver_y + receiver_h * 0.5
	g.add_child(box(receiver_w, receiver_h, receiver_z1 - receiver_z0, 0, receiver_y, (receiver_z0 + receiver_z1) * 0.5, "metal"))
	g.add_child(box(receiver_w * 0.8, 0.022, (receiver_z1 - receiver_z0) * 0.7, 0, receiver_top - 0.008, (receiver_z0 + receiver_z1) * 0.5 - 0.015, "metal"))
	g.add_child(box(0.004, 0.02, 0.06, receiver_w * 0.5 + 0.003, receiver_y + 0.012, -0.055, "dark"))
	var bz0 := receiver_z0 + 0.015
	var bz1 := muzzle_z - 0.015
	g.add_child(cyl(barrel_r, barrel_r + 0.002, absf(bz1 - bz0), 0, barrel_y, (bz0 + bz1) * 0.5, "metal"))
	var tz0 := maxf(tube_z0, receiver_z0 - 0.02)
	var tz1 := maxf(tube_z1, muzzle_z + 0.055)
	g.add_child(cyl(tube_r, tube_r, absf(tz1 - tz0), 0, tube_y, (tz0 + tz1) * 0.5, "dark"))
	var link_h := maxf((barrel_y - barrel_r) - (tube_y + tube_r), 0.012)
	g.add_child(box(0.014, link_h, 0.02, 0, ((barrel_y - barrel_r) + (tube_y + tube_r)) * 0.5, tz1 + 0.009, "dark"))
	var muzzle_cap_z := bz1 + 0.008
	g.add_child(cyl(barrel_r + 0.009, barrel_r + 0.011, 0.022, 0, barrel_y, muzzle_cap_z, "dark"))
	g.add_child(box(0.02, 0.006, absf((muzzle_cap_z + 0.025) - (receiver_z0 - 0.05)), 0, barrel_y + barrel_r + 0.005,
		((receiver_z0 - 0.05) + (muzzle_cap_z + 0.025)) * 0.5, "dark"))
	_pump_forend(g, 0.021, 0.23, tube_y, -0.34, "wood")
	_shotgun_action(g, receiver_w, receiver_y, receiver_z0)
	_shotgun_stock(g, receiver_bottom, receiver_z1, "wood", false)
	_shotgun_sights(g, sight_y, barrel_y + barrel_r + 0.011, muzzle_cap_z + 0.04, 0.085, false)
	var load_port := Node3D.new()
	load_port.name = "LoadPort"
	load_port.position = Vector3(0, receiver_bottom - 0.01, -0.04)
	g.add_child(load_port)
	g.set_meta("load_port", load_port)
	g.set_meta("inspect_point", Vector3(0, receiver_y + 0.004, -0.07))


static func _build_m590(g: Node3D) -> void:
	var receiver_w := 0.054
	var receiver_h := 0.076
	var receiver_y := 0.018
	var receiver_z0 := -0.18
	var receiver_z1 := 0.13
	var barrel_y := 0.047
	var barrel_r := 0.018
	var muzzle_z := -0.78
	var tube_y := -0.007
	var tube_r := 0.013
	var tube_z0 := -0.28
	var tube_z1 := -0.74
	var sight_y := 0.101
	var receiver_bottom := receiver_y - receiver_h * 0.5
	var receiver_top := receiver_y + receiver_h * 0.5
	g.add_child(box(receiver_w, receiver_h, receiver_z1 - receiver_z0, 0, receiver_y, (receiver_z0 + receiver_z1) * 0.5, "dark"))
	g.add_child(box(receiver_w * 0.8, 0.024, (receiver_z1 - receiver_z0) * 0.7, 0, receiver_top - 0.008, (receiver_z0 + receiver_z1) * 0.5 - 0.015, "dark"))
	g.add_child(box(0.004, 0.02, 0.06, receiver_w * 0.5 + 0.003, receiver_y + 0.012, -0.055, "dark"))
	var bz0 := receiver_z0 + 0.015
	var bz1 := muzzle_z - 0.015
	g.add_child(cyl(barrel_r, barrel_r + 0.002, absf(bz1 - bz0), 0, barrel_y, (bz0 + bz1) * 0.5, "dark"))
	var tz0 := maxf(tube_z0, receiver_z0 - 0.02)
	var tz1 := maxf(tube_z1, muzzle_z + 0.055)
	g.add_child(cyl(tube_r, tube_r, absf(tz1 - tz0), 0, tube_y, (tz0 + tz1) * 0.5, "dark"))
	var link_h := maxf((barrel_y - barrel_r) - (tube_y + tube_r), 0.012)
	g.add_child(box(0.016, link_h, 0.022, 0, ((barrel_y - barrel_r) + (tube_y + tube_r)) * 0.5, tz1 + 0.009, "dark"))
	var muzzle_cap_z := bz1 + 0.008
	g.add_child(cyl(barrel_r + 0.009, barrel_r + 0.011, 0.024, 0, barrel_y, muzzle_cap_z, "dark"))
	# M590A1 隔热罩与刺刀座
	var hs_z0 := receiver_z0 - 0.06
	var hs_z1 := maxf(muzzle_z + 0.12, hs_z0 - 0.32)
	if hs_z0 > hs_z1:
		g.add_child(box(0.04, 0.012, hs_z0 - hs_z1, 0, barrel_y + barrel_r + 0.0065, (hs_z0 + hs_z1) * 0.5, "dark"))
		for i in 4:
			g.add_child(box(0.008, 0.008, 0.04, 0, barrel_y + barrel_r + 0.016, hs_z0 - 0.06 - i * 0.07, "dark"))
	g.add_child(box(0.02, 0.03, 0.022, 0, tube_y - tube_r - 0.017, tz1 - 0.04, "dark"))
	_pump_forend(g, 0.023, 0.25, tube_y, -0.37, "poly")
	_shotgun_action(g, receiver_w, receiver_y, receiver_z0)
	_shotgun_stock(g, receiver_bottom, receiver_z1, "poly", false)
	_shotgun_sights(g, sight_y, barrel_y + barrel_r + 0.018, muzzle_cap_z + 0.04, 0.085, true)
	var load_port := Node3D.new()
	load_port.name = "LoadPort"
	load_port.position = Vector3(0, receiver_bottom - 0.01, -0.04)
	g.add_child(load_port)
	g.set_meta("load_port", load_port)
	g.set_meta("inspect_point", Vector3(0, receiver_y + 0.004, -0.07))


static func _build_win1897(g: Node3D) -> void:
	var receiver_w := 0.046
	var receiver_h := 0.075
	var receiver_y := 0.02
	var receiver_z0 := -0.16
	var receiver_z1 := 0.11
	var barrel_y := 0.046
	var barrel_r := 0.015
	var muzzle_z := -0.7
	var tube_y := -0.005
	var tube_r := 0.0115
	var tube_z0 := -0.3
	var tube_z1 := -0.66
	var sight_y := 0.103
	var receiver_bottom := receiver_y - receiver_h * 0.5
	var receiver_top := receiver_y + receiver_h * 0.5
	g.add_child(box(receiver_w, receiver_h, receiver_z1 - receiver_z0, 0, receiver_y, (receiver_z0 + receiver_z1) * 0.5, "brass"))
	g.add_child(box(receiver_w * 0.78, 0.022, (receiver_z1 - receiver_z0) * 0.7, 0, receiver_top - 0.008, (receiver_z0 + receiver_z1) * 0.5 - 0.015, "brass"))
	g.add_child(box(0.004, 0.02, 0.06, receiver_w * 0.5 + 0.003, receiver_y + 0.012, -0.055, "dark"))
	var bz0 := receiver_z0 + 0.015
	var bz1 := muzzle_z - 0.015
	g.add_child(cyl(barrel_r, barrel_r + 0.002, absf(bz1 - bz0), 0, barrel_y, (bz0 + bz1) * 0.5, "metal"))
	var tz0 := maxf(tube_z0, receiver_z0 - 0.02)
	var tz1 := maxf(tube_z1, muzzle_z + 0.055)
	g.add_child(cyl(tube_r, tube_r, absf(tz1 - tz0), 0, tube_y, (tz0 + tz1) * 0.5, "dark"))
	var link_h := maxf((barrel_y - barrel_r) - (tube_y + tube_r), 0.012)
	g.add_child(box(0.014, link_h, 0.02, 0, ((barrel_y - barrel_r) + (tube_y + tube_r)) * 0.5, tz1 + 0.009, "dark"))
	var muzzle_cap_z := bz1 + 0.008
	g.add_child(cyl(barrel_r + 0.009, barrel_r + 0.011, 0.022, 0, barrel_y, muzzle_cap_z, "dark"))
	# 1897 堑壕枪:隔热罩 + 刺刀座 + 外露击锤
	var hs_z0 := receiver_z0 - 0.06
	var hs_z1 := maxf(muzzle_z + 0.12, hs_z0 - 0.32)
	if hs_z0 > hs_z1:
		g.add_child(box(0.036, 0.011, hs_z0 - hs_z1, 0, barrel_y + barrel_r + 0.0065, (hs_z0 + hs_z1) * 0.5, "dark"))
		for i in 4:
			g.add_child(box(0.007, 0.007, 0.04, 0, barrel_y + barrel_r + 0.015, hs_z0 - 0.05 - i * 0.06, "dark"))
	g.add_child(box(0.018, 0.03, 0.02, 0, tube_y - tube_r - 0.016, tz1 - 0.04, "dark"))
	var hammer := Node3D.new()
	hammer.position = Vector3(0, receiver_top + 0.008, receiver_z1 - 0.015)
	hammer.add_child(cyl(0.007, 0.007, 0.012, 0, 0, 0, "metal", "z"))
	hammer.add_child(box(0.014, 0.02, 0.008, 0, 0.015, -0.003, "metal"))
	g.add_child(hammer)
	_pump_forend(g, 0.019, 0.26, tube_y, -0.32, "wood")
	_shotgun_action(g, receiver_w, receiver_y, receiver_z0)
	_shotgun_stock(g, receiver_bottom, receiver_z1, "wood", true)
	_shotgun_sights(g, sight_y, barrel_y + barrel_r + 0.017, muzzle_cap_z + 0.04, 0.085, false)
	var load_port := Node3D.new()
	load_port.name = "LoadPort"
	load_port.position = Vector3(0, receiver_bottom - 0.01, -0.04)
	g.add_child(load_port)
	g.set_meta("load_port", load_port)
	g.set_meta("inspect_point", Vector3(0, receiver_y + 0.004, -0.07))


## ============ [9/10] 非左轮手枪专用重做 ============
static func _pistol_sights(g: Node3D, sy: float, front_z: float, rear_z: float, front_h: float, rear_h: float) -> void:
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	# 前准星:窄柱,只在视线中心占一个细点
	ir.add_child(box(0.006, front_h, 0.008, 0, sy - front_h * 0.5, front_z, "dark"))
	# 后照门:只有左右两个薄耳,中间留出明确缺口,绝不添加中央挡块
	ir.add_child(box(0.003, rear_h, 0.012, -0.0095, sy - rear_h * 0.5, rear_z, "dark"))
	ir.add_child(box(0.003, rear_h, 0.012, 0.0095, sy - rear_h * 0.5, rear_z, "dark"))


static func _pistol_hammer(g: Node3D, x: float, y: float, z: float, w: float, h: float, mat: String) -> Node3D:
	var hammer := Node3D.new()
	hammer.name = "PistolHammer"
	hammer.position = Vector3(x, y, z)
	var spur := box(w, h, 0.008, 0, h * 0.32, -0.002, mat)
	spur.rotation.x = -0.22
	hammer.add_child(spur)
	g.add_child(hammer)
	return hammer


static func _build_m1911(g: Node3D) -> void:
	var slide := box(0.034, 0.05, 0.2, 0, 0.032, -0.04, "metal")
	slide.name = "Slide"
	g.add_child(slide)
	g.set_meta("slide", slide)
	g.add_child(box(0.033, 0.04, 0.19, 0, -0.003, -0.03, "dark"))
	g.add_child(cyl(0.009, 0.0095, 0.07, 0, 0.033, -0.16, "metal"))
	g.add_child(cyl(0.011, 0.012, 0.016, 0, 0.033, -0.145, "dark"))
	g.add_child(box(0.004, 0.018, 0.045, 0.02, 0.035, -0.055, "dark"))
	for i in 4:
		g.add_child(box(0.004, 0.008, 0.04, 0.019, 0.034, 0.015 - i * 0.014, "dark"))
	_pistol_hammer(g, 0, 0.043, 0.078, 0.012, 0.018, "metal")
	g.add_child(box(0.012, 0.03, 0.008, 0, 0.01, 0.055, "metal"))
	g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.006, 0.045, "wood", 0.35))
	g.add_child(box(0.032, 0.078, 0.04, 0.012, -0.045, 0.045, "wood"))
	g.add_child(box(0.032, 0.078, 0.04, -0.012, -0.045, 0.045, "wood"))
	_trigger(g, -0.035, 0.0)
	_mag_straight(g, 0.024, 0.1, 0.034, 0, -0.008, 0.045, "metal")
	_pistol_sights(g, 0.073, -0.11, 0.05, 0.018, 0.022)


static func _build_g17(g: Node3D) -> void:
	var slide := box(0.034, 0.044, 0.2, 0, 0.03, -0.04, "dark")
	slide.name = "Slide"
	g.add_child(slide)
	g.set_meta("slide", slide)
	g.add_child(box(0.033, 0.03, 0.18, 0, -0.003, -0.03, "poly"))
	g.add_child(cyl(0.008, 0.009, 0.06, 0, 0.031, -0.15, "metal"))
	g.add_child(box(0.004, 0.016, 0.04, 0.02, 0.032, -0.045, "dark"))
	for i in 4:
		g.add_child(box(0.004, 0.007, 0.038, -0.019, 0.029, 0.01 - i * 0.013, "dark"))
	g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.006, 0.045, "poly", 0.35))
	for i in 3:
		g.add_child(box(0.034, 0.006, 0.042, 0, -0.025 - i * 0.014, 0.045, "dark"))
	_trigger(g, -0.035, 0.0)
	_mag_straight(g, 0.026, 0.11, 0.036, 0, -0.008, 0.045, "dark")
	_pistol_sights(g, 0.0685, -0.12, 0.045, 0.016, 0.018)


static func _build_p226(g: Node3D) -> void:
	var slide := box(0.035, 0.047, 0.2, 0, 0.032, -0.04, "dark")
	slide.name = "Slide"
	g.add_child(slide)
	g.set_meta("slide", slide)
	g.add_child(box(0.034, 0.038, 0.18, 0, -0.003, -0.03, "tan"))
	g.add_child(cyl(0.009, 0.01, 0.07, 0, 0.034, -0.16, "metal"))
	g.add_child(box(0.008, 0.03, 0.02, -0.022, 0.006, 0.03, "dark"))
	g.add_child(box(0.01, 0.026, 0.018, -0.022, -0.004, 0.03, "dark"))
	_pistol_hammer(g, 0, 0.042, 0.072, 0.012, 0.018, "dark")
	g.add_child(_grip(0.031, 0.09, 0.045, 0, -0.007, 0.045, "poly", 0.35))
	g.add_child(box(0.034, 0.007, 0.04, 0, -0.04, 0.045, "dark"))
	_trigger(g, -0.035, 0.0)
	_mag_straight(g, 0.026, 0.11, 0.036, 0, -0.008, 0.045, "metal")
	_pistol_sights(g, 0.0735, -0.12, 0.045, 0.018, 0.02)


static func _build_deagle(g: Node3D) -> void:
	var slide := box(0.044, 0.058, 0.25, 0, 0.04, -0.06, "chrome")
	slide.name = "Slide"
	g.add_child(slide)
	g.set_meta("slide", slide)
	g.add_child(box(0.042, 0.044, 0.2, 0, -0.004, -0.03, "dark"))
	g.add_child(cyl(0.011, 0.012, 0.09, 0, 0.04, -0.23, "chrome"))
	g.add_child(cyl(0.02, 0.021, 0.03, 0, 0.04, -0.28, "dark"))
	g.add_child(cyl(0.007, 0.007, 0.1, 0, 0.024, -0.16, "dark"))
	g.add_child(box(0.04, 0.01, 0.12, 0, 0.07, -0.08, "chrome"))
	_pistol_hammer(g, 0, 0.052, 0.075, 0.016, 0.022, "chrome")
	g.add_child(_grip(0.036, 0.1, 0.05, 0, -0.008, 0.05, "wood", 0.32))
	g.add_child(box(0.04, 0.008, 0.046, 0, -0.055, 0.05, "dark"))
	_trigger(g, -0.038, 0.0)
	_mag_straight(g, 0.03, 0.12, 0.04, 0, -0.009, 0.05, "chrome")
	_pistol_sights(g, 0.0825, -0.2, 0.05, 0.02, 0.022)


static func _build_m93r(g: Node3D) -> void:
	var slide := box(0.034, 0.045, 0.22, 0, 0.03, -0.05, "dark")
	slide.name = "Slide"
	g.add_child(slide)
	g.set_meta("slide", slide)
	g.add_child(box(0.033, 0.038, 0.19, 0, -0.003, -0.03, "metal"))
	g.add_child(cyl(0.008, 0.009, 0.08, 0, 0.031, -0.2, "metal"))
	g.add_child(cyl(0.019, 0.02, 0.04, 0, 0.031, -0.245, "dark"))
	for side in [-1.0, 1.0]:
		g.add_child(box(0.02, 0.012, 0.012, side * 0.018, 0.036, -0.245, "dark"))
	var fg := box(0.024, 0.06, 0.03, 0, -0.045, -0.08, "poly")
	fg.rotation.x = 0.2
	g.add_child(fg)
	g.add_child(box(0.008, 0.02, 0.03, -0.022, 0.03, 0.02, "dark"))
	g.add_child(_grip(0.03, 0.09, 0.044, 0, -0.007, 0.05, "poly", 0.35))
	_trigger(g, -0.035, 0.01)
	_mag_straight(g, 0.026, 0.14, 0.034, 0, -0.008, 0.045, "dark")
	_pistol_sights(g, 0.07, -0.12, 0.045, 0.016, 0.018)


# === [10/10] 突击步枪批次:逐把独立构建(结构资料见 tools/research_ar_batch1.md) ===
## 所有枪:原点=握把,枪口 -Z;顶部导轨/机匣上缘全部低于 sight_y,ADS 视轴只留准星与照门。

## M4A1:M16 系上下机匣 + 平顶导轨 + M4 圆护木 + 三角准星/导气座 + A2 鸟笼消焰器 + 伸缩托
static func _build_m4(g: Node3D) -> void:
	var ry := 0.024                      # 枪管轴线
	# 下机匣(弹匣井 + 扳机座)+ 弹匣井前缘外扩
	g.add_child(box(0.052, 0.05, 0.24, 0, -0.005, -0.02, "poly"))
	g.add_child(box(0.05, 0.046, 0.07, 0, -0.008, -0.14, "poly"))
	# 上机匣 + 平顶皮卡汀尼导轨(齿顶 0.086 < sight_y 0.108,不挡 ADS)
	g.add_child(box(0.048, 0.03, 0.28, 0, 0.047, -0.06, "metal"))
	_rail(g, 0.086, 0.03, -0.22, 0.026, "dark")
	# 枪管螺母 + M4 圆形护木(带纵向散热肋)+ 三角准星导气座
	g.add_child(cyl(0.024, 0.026, 0.022, 0, ry, -0.15, "dark"))
	g.add_child(cyl(0.023, 0.025, 0.24, 0, ry, -0.28, "poly"))
	for rib_z in [-0.36, -0.32, -0.28, -0.24, -0.2]:
		g.add_child(box(0.05, 0.005, 0.012, 0, ry + 0.021, rib_z, "poly"))
	g.add_child(box(0.025, 0.045, 0.032, 0, 0.038, -0.4, "dark"))   # A2 三角准星座
	g.add_child(box(0.005, 0.024, 0.02, -0.013, 0.091, -0.4, "dark"))  # 准星护翼左
	g.add_child(box(0.005, 0.024, 0.02, 0.013, 0.091, -0.4, "dark"))   # 准星护翼右
	# 14.5" 枪管 + A2 鸟笼消焰器
	g.add_child(cyl(0.011, 0.013, 0.62, 0, ry, -0.47))
	g.add_child(cyl(0.014, 0.016, 0.05, 0, ry, -0.775, "dark"))
	for slot_s in [-1.0, 1.0]:
		g.add_child(box(0.006, 0.01, 0.03, slot_s * 0.0145, ry, -0.77, "dark"))
	# M4 四段伸缩托:缓冲管 + 托体 + 托垫 + 贴腮 + 调节孔
	g.add_child(cyl(0.012, 0.012, 0.11, 0, 0.032, 0.18, "dark", "z"))
	g.add_child(box(0.042, 0.085, 0.13, 0, 0.011, 0.2, "poly"))
	g.add_child(box(0.046, 0.095, 0.02, 0, 0.011, 0.27, "dark"))
	g.add_child(box(0.03, 0.03, 0.09, 0, 0.05, 0.2, "poly"))
	for hole_z in [0.16, 0.2]:
		g.add_child(box(0.008, 0.02, 0.02, 0, -0.008, hole_z, "dark"))
	# A2 握把 + 扳机 + STANAG 30 发弹匣(底缘后收)
	g.add_child(_grip(0.032, 0.095, 0.044, 0, -0.026, 0.04, "poly", 0.34))
	_trigger(g, -0.038, 0.005)
	_mag_straight(g, 0.036, 0.13, 0.06, 0, -0.024, -0.09, "dark", 0.1)
	# 抛壳窗/黄铜偏转块/辅助推机柄/弹匣释放钮 + T 型拉机柄
	g.add_child(box(0.006, 0.02, 0.055, 0.027, 0.04, -0.07, "dark"))
	g.add_child(box(0.005, 0.012, 0.018, 0.026, 0.052, -0.02, "dark"))
	g.add_child(cyl(0.009, 0.009, 0.03, 0.026, 0.05, 0.045, "dark", "y"))
	g.add_child(box(0.01, 0.012, 0.018, 0.027, -0.012, -0.06, "dark"))
	_bolt(g, 0.028, 0.055, 0.06, 1.0, "dark")
	_irons(g, 0.108, -0.4, 0.055, 0.05, ry)


## AK-47:铣削机匣 + 防尘盖 + 导气管 + 木护木/木托 + 弧形钢弹匣 + 准星座/斜切制退器
static func _build_ak(g: Node3D) -> void:
	var ry := 0.028
	# 机匣 + 顶部防尘盖 + 右侧大拨片保险
	g.add_child(box(0.054, 0.066, 0.3, 0, 0.012, -0.03, "metal"))
	g.add_child(box(0.05, 0.02, 0.22, 0, 0.052, -0.02, "dark"))
	g.add_child(box(0.012, 0.02, 0.1, 0.03, 0.012, -0.02, "dark"))
	# 前节套 + 导气管(枪管上方)+ 导气座(带刺刀座)
	g.add_child(box(0.05, 0.05, 0.05, 0, 0.024, -0.16, "metal"))
	g.add_child(cyl(0.011, 0.012, 0.34, 0, 0.05, -0.26, "metal"))
	g.add_child(box(0.024, 0.045, 0.05, 0, 0.034, -0.44, "dark"))
	# 上下两片木护木夹住枪管/导气管
	g.add_child(box(0.046, 0.032, 0.16, 0, 0.054, -0.28, "wood"))
	g.add_child(box(0.05, 0.042, 0.16, 0, 0.009, -0.28, "wood"))
	g.add_child(box(0.051, 0.014, 0.018, 0, 0.03, -0.22, "dark"))   # 护木前箍
	# 枪管 + 准星座 + 枪口制退器
	g.add_child(cyl(0.012, 0.014, 0.52, 0, ry, -0.51))
	g.add_child(box(0.02, 0.055, 0.03, 0, 0.052, -0.76, "dark"))
	g.add_child(cyl(0.015, 0.017, 0.04, 0, ry, -0.84, "dark"))
	# 木枪托 + 托底板
	g.add_child(_grip(0.044, 0.1, 0.2, 0, -0.006, 0.19, "wood", 0.15))
	g.add_child(box(0.048, 0.1, 0.022, 0, 0.0, 0.29, "wood"))
	# 木握把 + 扳机 + 大弧度钢弹匣
	g.add_child(_grip(0.034, 0.1, 0.046, 0, -0.024, 0.045, "wood", 0.42))
	_trigger(g, -0.036, 0.015)
	_curved_mag(g, 0.038, 0, -0.023, -0.1, "metal")
	# 右侧大拉机柄
	_bolt(g, 0.032, 0.036, -0.02, 1.0, "dark")
	_irons(g, 0.104, -0.74, 0.0, 0.055, ry)


## FN SCAR-H:一体式铝上机匣 + 全顶轨 + 聚合物下机匣 + 短冲程导气座 + Ugg 靴型折叠托
static func _build_scar(g: Node3D) -> void:
	var ry := 0.024
	# 一体式上机匣(延伸到护木段)+ 聚合物下机匣
	g.add_child(box(0.05, 0.03, 0.42, 0, 0.048, -0.1, "tan"))
	g.add_child(box(0.052, 0.052, 0.2, 0, -0.006, -0.02, "tan"))
	_rail(g, 0.086, 0.03, -0.42, 0.026, "dark")
	# 护木下段 + 两侧可拆短轨
	g.add_child(box(0.046, 0.036, 0.15, 0, 0.003, -0.3, "dark"))
	for side_rail in [-1.0, 1.0]:
		g.add_child(box(0.01, 0.03, 0.16, side_rail * 0.025, 0.012, -0.3, "dark"))
	# 枪管 + 导气座(前准星折叠座)+ 三叉消焰器
	g.add_child(cyl(0.011, 0.013, 0.62, 0, ry, -0.46))
	g.add_child(box(0.022, 0.04, 0.05, 0, 0.035, -0.34, "dark"))
	g.add_child(cyl(0.016, 0.019, 0.05, 0, ry, -0.8, "dark"))
	# Ugg 靴型折叠托:铰链 + 上杆 + 靴跟 + 靴尖
	g.add_child(box(0.03, 0.06, 0.05, 0, 0.01, 0.13, "dark"))
	g.add_child(box(0.026, 0.03, 0.16, 0, 0.03, 0.2, "tan"))
	g.add_child(box(0.048, 0.1, 0.032, 0, 0.0, 0.27, "tan"))
	g.add_child(box(0.048, 0.035, 0.06, 0, -0.03, 0.24, "dark"))
	g.add_child(box(0.01, 0.025, 0.08, 0.022, 0.002, 0.19, "dark"))  # 折叠钮
	# M16 式握把 + 7.62 20 发短弹匣
	g.add_child(_grip(0.034, 0.1, 0.046, 0, -0.026, 0.04, "dark", 0.36))
	_trigger(g, -0.038, 0.005)
	_mag_straight(g, 0.038, 0.105, 0.065, 0, -0.022, -0.1, "tan", 0.1)
	# 左侧拉机柄 + 右侧抛壳窗
	_bolt(g, -0.03, 0.055, -0.16, -1.0, "dark")
	g.add_child(box(0.006, 0.018, 0.05, 0.027, 0.045, -0.06, "dark"))
	_irons(g, 0.112, -0.34, 0.08, 0.05, ry)


## Steyr AUG A3:无托聚合物枪身 + 顶部 A3 轨 + 前置折叠握把 + 后置透明弹匣 + 左后拉机柄
static func _build_aug(g: Node3D) -> void:
	var ry := 0.026
	# 无托一体枪身 + 贴腮凸起 + 托底板
	g.add_child(box(0.052, 0.08, 0.58, 0, 0.022, 0.03, "olive"))
	g.add_child(box(0.05, 0.05, 0.16, 0, 0.072, 0.12, "olive"))
	g.add_child(box(0.054, 0.095, 0.025, 0, 0.02, 0.31, "dark"))
	g.add_child(box(0.012, 0.02, 0.05, 0.03, 0.04, 0.16, "dark"))   # 抛壳偏转块
	# A3 顶部皮卡汀尼轨
	_rail(g, 0.082, 0.16, -0.28, 0.024, "dark")
	# 枪管 + 鸟笼消焰器
	g.add_child(cyl(0.011, 0.013, 0.42, 0, ry, -0.36))
	g.add_child(cyl(0.014, 0.017, 0.04, 0, ry, -0.64, "dark"))
	# 前置可折叠垂直握把 + 扳机护圈桥(一体大型护圈)
	g.add_child(_grip(0.028, 0.075, 0.04, 0, -0.03, -0.17, "olive", 0.12))
	g.add_child(box(0.046, 0.018, 0.26, 0, -0.05, 0.0, "olive"))
	# 后置手枪握把(扳机在前,弹匣在握把后方)
	g.add_child(_grip(0.034, 0.09, 0.05, 0, -0.026, 0.07, "olive", 0.3))
	_trigger(g, -0.037, -0.05)
	# 半透明聚合物弹匣(后置)+ 加强筋
	_mag_straight(g, 0.036, 0.12, 0.056, 0, -0.022, 0.16, "olive", -0.1)
	var aug_mag = g.get_meta("mag")
	if aug_mag is Node3D:
		aug_mag.add_child(box(0.038, 0.008, 0.057, 0, -0.02, 0.002, "dark"))
		aug_mag.add_child(box(0.038, 0.008, 0.057, 0, -0.08, 0.002, "dark"))
	# 左侧后置拉机柄
	_bolt(g, -0.03, 0.05, 0.24, -1.0, "dark")
	g.add_child(box(0.006, 0.02, 0.05, 0.027, 0.04, 0.18, "dark"))
	_irons(g, 0.125, -0.44, 0.18, 0.045, ry)


## HK G36C:聚合物机匣 + 短护木四向导轨 + 短枪管 + 侧折叠骨架托 + 顶置折叠拉机柄
static func _build_g36c(g: Node3D) -> void:
	var ry := 0.024
	# 聚合物机匣 + 提把/导轨基座
	g.add_child(box(0.05, 0.062, 0.34, 0, 0.014, -0.03, "poly"))
	g.add_child(box(0.046, 0.03, 0.18, 0, 0.052, 0.0, "poly"))
	_rail(g, 0.082, 0.04, -0.15, 0.024, "dark")
	# 枪管 + 鸟笼消焰器(G36C 短管)
	g.add_child(cyl(0.011, 0.013, 0.42, 0, ry, -0.42))
	g.add_child(cyl(0.014, 0.016, 0.05, 0, ry, -0.68, "dark"))
	# 短护木 + 左右/底部短轨
	g.add_child(box(0.05, 0.05, 0.13, 0, 0.006, -0.24, "poly"))
	for side_rail in [-1.0, 1.0]:
		g.add_child(box(0.008, 0.026, 0.1, side_rail * 0.026, 0.012, -0.24, "dark"))
	g.add_child(box(0.03, 0.008, 0.1, 0, -0.021, -0.24, "dark"))
	# 侧折叠骨架托:铰链 + 上杆/下杆 + 贴腮 + 托底板
	g.add_child(box(0.03, 0.055, 0.04, 0, 0.005, 0.14, "dark"))
	g.add_child(box(0.024, 0.02, 0.14, 0, 0.05, 0.21, "poly"))
	g.add_child(box(0.024, 0.02, 0.14, 0, -0.015, 0.21, "poly"))
	g.add_child(box(0.036, 0.03, 0.08, 0, 0.035, 0.24, "poly"))
	g.add_child(box(0.04, 0.08, 0.024, 0, 0.01, 0.27, "poly"))
	# 握把 + 扳机 + 半透明弧形弹匣
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.023, 0.04, "poly", 0.36))
	_trigger(g, -0.035, 0.005)
	_curved_mag(g, 0.036, 0, -0.022, -0.08, "tan")
	var g36_mag = g.get_meta("mag")
	if g36_mag is Node3D:
		g36_mag.add_child(box(0.038, 0.006, 0.053, 0, -0.03, 0.004, "dark"))
		g36_mag.add_child(box(0.038, 0.006, 0.05, 0, -0.1, -0.012, "dark"))
	# 顶置折叠拉机柄(居中)+ 抛壳窗
	_bolt(g, 0.0, 0.058, -0.06, 0.0, "dark")
	g.add_child(box(0.006, 0.018, 0.05, 0.027, 0.035, -0.08, "dark"))
	_irons(g, 0.1, -0.36, 0.04, 0.045, ry)


## AK-74M:现代化 AK:黑色聚合物家具 + 90° 导气座 + 直弧形 5.45 弹匣 + 侧折叠骨架托
static func _build_ak74(g: Node3D) -> void:
	var ry := 0.028
	# 机匣 + 防尘盖 + 保险拨片
	g.add_child(box(0.054, 0.066, 0.3, 0, 0.012, -0.03, "dark"))
	g.add_child(box(0.05, 0.02, 0.22, 0, 0.052, -0.02, "metal"))
	g.add_child(box(0.012, 0.02, 0.1, 0.03, 0.012, -0.02, "metal"))
	# 前节套 + 导气管 + 90° 导气座
	g.add_child(box(0.05, 0.05, 0.05, 0, 0.024, -0.16, "metal"))
	g.add_child(cyl(0.011, 0.012, 0.32, 0, 0.05, -0.25, "metal"))
	g.add_child(box(0.02, 0.042, 0.04, 0, 0.033, -0.46, "dark"))
	# 黑色聚合物上下护木 + 前箍
	g.add_child(box(0.046, 0.03, 0.15, 0, 0.053, -0.27, "poly"))
	g.add_child(box(0.05, 0.04, 0.15, 0, 0.01, -0.27, "poly"))
	g.add_child(box(0.051, 0.013, 0.016, 0, 0.031, -0.21, "dark"))
	# 枪管 + 准星座 + 74 式圆柱开槽制退器
	g.add_child(cyl(0.011, 0.013, 0.46, 0, ry, -0.49))
	g.add_child(box(0.02, 0.052, 0.028, 0, 0.05, -0.72, "dark"))
	g.add_child(cyl(0.014, 0.018, 0.07, 0, ry, -0.79, "dark"))
	for slot_s in [-1.0, 1.0]:
		g.add_child(box(0.006, 0.008, 0.045, slot_s * 0.0145, ry, -0.78, "metal"))
	# 侧折叠骨架托:铰链 + 双杆 + 托底板(与 AK-47 木托明显区分)
	g.add_child(box(0.03, 0.055, 0.04, 0, 0.005, 0.15, "dark"))
	g.add_child(box(0.022, 0.02, 0.15, 0, 0.045, 0.21, "poly"))
	g.add_child(box(0.022, 0.02, 0.15, 0, -0.012, 0.21, "poly"))
	g.add_child(box(0.04, 0.08, 0.024, 0, 0.01, 0.28, "poly"))
	# 聚合物握把 + 扳机 + 5.45 弹匣(比 7.62 更直)
	g.add_child(_grip(0.034, 0.1, 0.046, 0, -0.024, 0.045, "poly", 0.4))
	_trigger(g, -0.036, 0.015)
	_mag_straight(g, 0.036, 0.135, 0.058, 0, -0.023, -0.1, "dark", 0.14)
	_bolt(g, 0.032, 0.036, -0.02, 1.0, "dark")
	_irons(g, 0.104, -0.7, 0.0, 0.055, ry)


## FAMAS:高提把无托枪身 + 前置大护圈 + 两脚架收纳腿 + 后置弹匣 + 顶部拉机柄
static func _build_famas(g: Node3D) -> void:
	var ry := 0.024
	# 无托枪身(黑绿聚合物)+ 高提把(提把顶 0.088,低于 sight_y 0.1)
	g.add_child(box(0.05, 0.07, 0.56, 0, 0.02, 0.0, "olive"))
	g.add_child(box(0.046, 0.028, 0.16, 0, 0.062, -0.02, "poly"))
	g.add_child(box(0.048, 0.012, 0.2, 0, 0.08, -0.02, "dark"))
	# 枪管 + 消焰器
	g.add_child(cyl(0.011, 0.013, 0.46, 0, ry, -0.44))
	g.add_child(cyl(0.014, 0.016, 0.04, 0, ry, -0.69, "dark"))
	# 收纳式两脚架(贴合枪身两侧)
	for leg_s in [-1.0, 1.0]:
		g.add_child(cyl(0.006, 0.006, 0.22, leg_s * 0.029, -0.008, -0.32, "dark", "z"))
		g.add_child(box(0.01, 0.03, 0.04, leg_s * 0.029, -0.005, -0.42, "dark"))
	# 前置垂直握把 + 大型扳机护圈桥
	g.add_child(_grip(0.028, 0.06, 0.04, 0, -0.03, -0.16, "olive", 0.15))
	g.add_child(box(0.04, 0.014, 0.24, 0, -0.045, -0.02, "olive"))
	# 后置手枪握把(弹匣在握把后方)+ 25 发直弹匣
	g.add_child(_grip(0.034, 0.09, 0.05, 0, -0.025, 0.08, "olive", 0.3))
	_trigger(g, -0.035, -0.02)
	_mag_straight(g, 0.036, 0.12, 0.058, 0, -0.022, 0.16, "dark", -0.12)
	# 顶部拉机柄(提把下方居中)
	_bolt(g, 0.0, 0.06, 0.2, 0.0, "dark")
	g.add_child(box(0.006, 0.018, 0.05, 0.027, 0.04, 0.17, "dark"))
	# 提把式机械瞄具:细前准星柱 + 小缺口照门(FAMAS 照门贴着提把顶,不允许大块建模进入视轴)
	var ir := Node3D.new()
	ir.name = "StockIrons"
	g.add_child(ir)
	ir.add_child(box(0.01, 0.035, 0.012, 0, 0.0825, -0.5, "dark"))
	ir.add_child(box(0.016, 0.006, 0.012, 0, 0.087, 0.04, "dark"))
	ir.add_child(box(0.004, 0.012, 0.01, -0.0055, 0.095, 0.04, "dark"))
	ir.add_child(box(0.004, 0.012, 0.01, 0.0055, 0.095, 0.04, "dark"))


## HK G3:滚柱延迟钢机匣 + 细长护木 + 鼓式照门/三叉准星座 + 固定聚合物托 + 左前拉机柄
static func _build_g3(g: Node3D) -> void:
	var ry := 0.024
	# 冲压钢机匣 + 顶部照门座
	g.add_child(box(0.052, 0.068, 0.4, 0, 0.014, -0.03, "metal"))
	g.add_child(box(0.048, 0.016, 0.3, 0, 0.052, -0.04, "dark"))
	# 枪管 + 三叉准星座 + 枪口消焰器
	g.add_child(cyl(0.012, 0.014, 0.56, 0, ry, -0.46))
	g.add_child(box(0.024, 0.046, 0.03, 0, 0.044, -0.62, "dark"))
	g.add_child(box(0.005, 0.02, 0.024, -0.013, 0.068, -0.62, "dark"))
	g.add_child(box(0.005, 0.02, 0.024, 0.013, 0.068, -0.62, "dark"))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.715, "dark"))
	# 细长绿色聚合物护木 + 防滑筋
	g.add_child(box(0.048, 0.052, 0.22, 0, 0.012, -0.28, "olive"))
	for rib_z in [-0.35, -0.3, -0.25, -0.2]:
		g.add_child(box(0.05, 0.005, 0.016, 0, 0.037, rib_z, "olive"))
	# 固定聚合物托(直线型)+ 托底板
	g.add_child(_grip(0.042, 0.09, 0.19, 0, -0.005, 0.19, "olive", 0.1))
	g.add_child(box(0.046, 0.095, 0.02, 0, 0.002, 0.285, "dark"))
	g.add_child(box(0.01, 0.014, 0.03, 0.022, -0.012, 0.2, "dark"))  # 背带环
	# 聚合物握把 + 20 发钢弹匣
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "poly", 0.4))
	_trigger(g, -0.036, 0.015)
	_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.022, -0.09, "dark", 0.06)
	# 左侧前拉机柄(可折叠)+ 抛壳窗
	_bolt(g, -0.03, 0.04, -0.18, -1.0, "dark")
	g.add_child(box(0.006, 0.018, 0.05, 0.027, 0.035, -0.06, "dark"))
	_irons(g, 0.112, -0.62, 0.03, 0.05, ry)


# === [10/10] 冲锋枪批次:逐把独立构建(结构资料见 tools/research_smg_batch2.md) ===

## HK MP5:冲压钢机匣 + 上置拉机柄管 + 宽聚合物护木 + A2 固定托 + 弧形弹匣 + 鼓式照门
static func _build_mp5(g: Node3D) -> void:
	var ry := 0.02
	# 钢机匣 + 顶部拉机柄管(经典 MP5 前管)
	g.add_child(box(0.044, 0.062, 0.3, 0, 0.014, -0.03, "metal"))
	g.add_child(cyl(0.012, 0.012, 0.2, 0, 0.03, -0.16, "dark"))
	# 宽聚合物护木(带散热槽)+ 短枪管 + 三耳枪口
	g.add_child(box(0.052, 0.052, 0.15, 0, 0.012, -0.26, "poly"))
	for rib_z in [-0.3, -0.27, -0.24, -0.21]:
		g.add_child(box(0.054, 0.005, 0.012, 0, 0.037, rib_z, "poly"))
	g.add_child(cyl(0.009, 0.011, 0.18, 0, ry, -0.38))
	g.add_child(cyl(0.013, 0.014, 0.04, 0, ry, -0.47, "dark"))
	for lug_s in [-1.0, 1.0]:
		g.add_child(box(0.007, 0.007, 0.02, lug_s * 0.01, ry, -0.49, "dark"))
	# A2 固定托 + 握把
	g.add_child(_grip(0.038, 0.075, 0.15, 0, -0.003, 0.16, "poly", 0.08))
	g.add_child(box(0.042, 0.08, 0.02, 0, -0.004, 0.24, "poly"))
	g.add_child(_grip(0.03, 0.09, 0.04, 0, -0.02, 0.04, "poly", 0.4))
	_trigger(g, -0.034, 0.01)
	# 弧形弹匣 + 桨式释放钮 + 前部拉机柄(左)
	_curved_mag(g, 0.032, 0, -0.02, -0.1, "dark")
	g.add_child(box(0.01, 0.03, 0.03, 0.024, -0.04, -0.06, "dark"))
	_bolt(g, -0.026, 0.035, -0.22, -1.0, "dark")
	# 鼓式照门:圆觇孔 + 护圈准星
	var mp5_ir := Node3D.new()
	mp5_ir.name = "StockIrons"
	g.add_child(mp5_ir)
	mp5_ir.add_child(box(0.014, 0.026, 0.014, 0, 0.043, -0.42, "dark"))
	mp5_ir.add_child(box(0.006, 0.02, 0.012, 0, 0.068, -0.42, "dark"))
	mp5_ir.add_child(cyl(0.009, 0.01, 0.012, 0, 0.09, 0.1, "dark"))
	mp5_ir.add_child(box(0.005, 0.012, 0.012, -0.007, 0.087, 0.1, "dark"))
	mp5_ir.add_child(box(0.005, 0.012, 0.012, 0.007, 0.087, 0.1, "dark"))


## HK UMP:聚合物直机匣 + 折叠托 + 短护木 + .45 直弹匣 + 低瞄具
static func _build_ump(g: Node3D) -> void:
	var ry := 0.022
	# 聚合物机匣 + 顶部短轨(齿顶 0.072,低于 sight_y 0.1)
	g.add_child(box(0.048, 0.066, 0.26, 0, 0.012, -0.02, "poly"))
	_rail(g, 0.072, 0.04, -0.2, 0.022, "dark")
	# 短护木 + 底部附件轨
	g.add_child(box(0.046, 0.05, 0.12, 0, 0.005, -0.22, "poly"))
	g.add_child(box(0.03, 0.008, 0.1, 0, -0.021, -0.22, "dark"))
	# 短枪管 + 枪口环
	g.add_child(cyl(0.01, 0.011, 0.14, 0, ry, -0.32))
	g.add_child(cyl(0.013, 0.014, 0.03, 0, ry, -0.4, "dark"))
	# 侧折叠骨架托 + 握把
	g.add_child(box(0.028, 0.05, 0.04, 0, 0.005, 0.12, "dark"))
	g.add_child(box(0.022, 0.02, 0.14, 0, 0.045, 0.19, "poly"))
	g.add_child(box(0.022, 0.02, 0.14, 0, -0.012, 0.19, "poly"))
	g.add_child(box(0.04, 0.075, 0.024, 0, 0.008, 0.25, "poly"))
	g.add_child(_grip(0.032, 0.095, 0.045, 0, -0.02, 0.045, "poly", 0.38))
	_trigger(g, -0.034, 0.02)
	# .45 宽直弹匣
	_mag_straight(g, 0.04, 0.12, 0.06, 0, -0.02, -0.05, "dark")
	# 左侧拉机柄 + 释放杆
	_bolt(g, -0.027, 0.045, -0.08, -1.0, "dark")
	g.add_child(box(0.008, 0.03, 0.04, -0.027, -0.02, -0.02, "dark"))
	_irons(g, 0.1, -0.32, 0.06, 0.045, ry)


## FN P90(TR 平顶型):无托聚合物枪身 + 与枪管平行的顶置半透明弹匣 + 超大扳机护圈前握把
## + 前部手挡 + 拇指孔握把 + 枪托下方抛壳 + 左右对称拉机柄。结构与 Wikipedia/FN 资料一致。
static func _build_p90(g: Node3D) -> void:
	var ry := 0.008
	# 一体式枪身/枪托(高 100mm,顶部平台承托弹匣;枪托延伸至 z=0.24)
	g.add_child(box(0.052, 0.1, 0.38, 0, -0.005, -0.02, "poly"))
	g.add_child(box(0.05, 0.085, 0.1, 0, 0.0, 0.18, "poly"))
	g.add_child(box(0.052, 0.09, 0.024, 0, 0.0, 0.235, "dark"))
	# TR 平顶机匣:顶部平台低矮,只承担前卡槽与瞄具座;不是弹匣本身
	g.add_child(box(0.046, 0.018, 0.24, 0, 0.052, -0.05, "poly"))
	# 瞄具全部装在枪前侧(前卡槽上方):短皮轨从 z=-0.20 到 -0.04,齿顶 0.078 < sight_y 0.09
	_rail(g, 0.078, -0.20, -0.04, 0.022, "dark")
	# 低位枪管(263mm)+ 斜切消焰/补偿器
	g.add_child(cyl(0.008, 0.009, 0.26, 0, ry, -0.22))
	g.add_child(cyl(0.011, 0.012, 0.035, 0, ry, -0.325, "dark"))
	# 前侧弹匣卡槽:位于瞄具座下方,弹匣前端卡入这里
	g.add_child(box(0.046, 0.012, 0.04, 0, 0.056, -0.16, "metal"))
	# 顶置弹匣:与枪管平行,前端卡入前卡槽、弹体向后延伸至枪托上方;
	# 半透明聚合物弹体 + 后端螺旋供弹坡道 + 前端两侧弹匣扣
	var mag_p := Node3D.new()
	mag_p.position = Vector3(0.0, 0.062, -0.02)
	var p90_body := box(0.042, 0.028, 0.3, 0, 0, 0, "tan")
	p90_body.material_override = MAT()["lens_clear"]
	mag_p.add_child(p90_body)
	mag_p.add_child(box(0.044, 0.008, 0.31, 0, 0.014, 0.0, "dark"))          # 弹匣顶脊
	mag_p.add_child(box(0.04, 0.02, 0.06, 0, -0.004, 0.14, "dark"))           # 螺旋供弹坡道(后)
	mag_p.add_child(box(0.04, 0.024, 0.02, 0, 0.0, -0.15, "dark"))           # 前端卡头(插入前卡槽)
	for catch_s in [-1.0, 1.0]:
		mag_p.add_child(box(0.006, 0.014, 0.016, catch_s * 0.023, 0.004, -0.13, "metal"))  # 前端两侧弹匣扣
	for win_z in [-0.05, 0.02, 0.09]:
		mag_p.add_child(box(0.046, 0.013, 0.04, 0, 0.0, win_z, "dark"))       # 余弹观察窗
	g.add_child(mag_p)
	g.set_meta("mag", mag_p)
	# 超大扳机护圈兼前握把 + 前部手挡
	g.add_child(box(0.044, 0.018, 0.24, 0, -0.055, -0.02, "poly"))
	g.add_child(box(0.034, 0.05, 0.04, 0, -0.07, -0.14, "poly"))
	g.add_child(box(0.034, 0.012, 0.02, 0, -0.082, -0.14, "dark"))
	# 拇指孔握把(握把上方为拇指孔)+ 扳机 + 三档旋钮
	g.add_child(_grip(0.034, 0.085, 0.05, 0, -0.05, 0.1, "poly", 0.28))
	_trigger(g, -0.048, 0.015)
	g.add_child(cyl(0.009, 0.009, 0.012, 0, -0.06, 0.0, "dark", "y"))
	# 抛壳槽(枪托下方、握把后方)
	g.add_child(box(0.03, 0.03, 0.08, 0, -0.06, 0.15, "dark"))
	# 左右对称拉机柄(后部,与实枪一致)
	var p90_ch := Node3D.new()
	p90_ch.position = Vector3(0.0, 0.032, 0.16)
	p90_ch.add_child(cyl(0.007, 0.007, 0.03, -0.028, 0, 0, "dark", "x"))
	p90_ch.add_child(cyl(0.007, 0.007, 0.03, 0.028, 0, 0, "dark", "x"))
	g.add_child(p90_ch)
	g.set_meta("bolt", p90_ch)
	# TR 平顶型原厂氚光铁瞄:全部装在枪前侧短轨/前卡槽上方(照门 z=-0.04,准星 z=-0.18)
	var p90_ir := Node3D.new()
	p90_ir.name = "StockIrons"
	g.add_child(p90_ir)
	p90_ir.add_child(box(0.012, 0.008, 0.012, 0, 0.074, -0.04, "dark"))
	p90_ir.add_child(box(0.003, 0.012, 0.008, -0.0045, 0.084, -0.04, "dark"))
	p90_ir.add_child(box(0.003, 0.012, 0.008, 0.0045, 0.084, -0.04, "dark"))
	p90_ir.add_child(box(0.004, 0.018, 0.006, 0, 0.081, -0.18, "dark"))


## KRISS Vector:斜切聚合物机匣 + 顶部导轨 + 短管 + 前握把 + 折叠托
static func _build_vector(g: Node3D) -> void:
	var ry := 0.02
	# 上下两段斜切机匣(上段金属轨座,下段聚合物斜体)
	g.add_child(box(0.05, 0.046, 0.24, 0, 0.032, -0.08, "metal"))
	g.add_child(box(0.046, 0.06, 0.2, 0, -0.012, -0.02, "poly"))
	var v_skirt := box(0.044, 0.04, 0.1, 0, -0.018, -0.14, "poly")
	v_skirt.rotation.x = -0.25
	g.add_child(v_skirt)
	_rail(g, 0.086, 0.02, -0.3, 0.024, "dark")
	# 短枪管 + 消焰器
	g.add_child(cyl(0.014, 0.016, 0.2, 0, ry, -0.36))
	g.add_child(cyl(0.018, 0.019, 0.05, 0, ry, -0.47, "dark"))
	# 前垂直握把
	g.add_child(_grip(0.026, 0.06, 0.035, 0, -0.02, -0.16, "poly", 0.2))
	# 折叠托(铰链 + 杆 + 托垫)
	g.add_child(box(0.026, 0.045, 0.04, 0, 0.005, 0.1, "dark"))
	g.add_child(box(0.022, 0.02, 0.14, 0, 0.042, 0.17, "poly"))
	g.add_child(box(0.022, 0.02, 0.14, 0, -0.01, 0.17, "poly"))
	g.add_child(box(0.04, 0.07, 0.024, 0, 0.006, 0.23, "poly"))
	# 握把 + 前倾弹匣
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "poly", 0.38))
	_trigger(g, -0.036, 0.01)
	_mag_straight(g, 0.034, 0.14, 0.05, 0, -0.024, -0.06, "dark", 0.18)
	_bolt(g, -0.028, 0.04, 0.0, -1.0, "dark")
	_irons(g, 0.088, -0.4, 0.04, 0.045, ry)


## PP-19 野牛:AK 系短机匣 + 枪管下方长筒螺旋弹匣(弹匣即护木)+ 侧折叠托
static func _build_pp19(g: Node3D) -> void:
	var ry := 0.024
	# AK 式短机匣 + 防尘盖 + 右侧保险
	g.add_child(box(0.05, 0.062, 0.26, 0, 0.012, -0.03, "metal"))
	g.add_child(box(0.046, 0.018, 0.22, 0, 0.05, -0.04, "dark"))
	g.add_child(box(0.011, 0.018, 0.09, 0.028, 0.012, -0.02, "dark"))
	# 枪管 + 上护木(短)+ 准星座 + 枪口
	g.add_child(cyl(0.011, 0.013, 0.42, 0, ry, -0.38))
	g.add_child(box(0.044, 0.03, 0.13, 0, 0.052, -0.28, "poly"))
	g.add_child(box(0.018, 0.045, 0.024, 0, 0.048, -0.56, "dark"))
	g.add_child(cyl(0.014, 0.015, 0.04, 0, ry, -0.58, "dark"))
	# 螺旋弹匣:枪管下方长筒,沿 z 轴,带肋环与前后端盖(PP-19 标志)
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
	# 侧折叠骨架托 + 握把
	g.add_child(box(0.028, 0.05, 0.04, 0, 0.005, 0.13, "dark"))
	g.add_child(box(0.022, 0.02, 0.14, 0, 0.045, 0.19, "poly"))
	g.add_child(box(0.022, 0.02, 0.14, 0, -0.012, 0.19, "poly"))
	g.add_child(box(0.04, 0.075, 0.024, 0, 0.008, 0.25, "poly"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.022, 0.04, "poly", 0.38))
	_trigger(g, -0.034, 0.0)
	_bolt(g, 0.028, 0.04, -0.02, 1.0, "dark")
	_irons(g, 0.095, -0.44, 0.03, 0.05, ry)


## SIG MPX:AR 式小机匣 + 一体式上轨 + 细长 M-LOK 护木 + 侧折叠托
static func _build_mpx(g: Node3D) -> void:
	var ry := 0.024
	# 上下机匣 + 顶部导轨
	g.add_child(box(0.05, 0.05, 0.24, 0, -0.005, -0.02, "poly"))
	g.add_child(box(0.046, 0.028, 0.3, 0, 0.047, -0.1, "metal"))
	_rail(g, 0.082, 0.02, -0.34, 0.024, "dark")
	# 细长护木 + 侧/底短轨
	g.add_child(box(0.042, 0.046, 0.15, 0, 0.008, -0.26, "poly"))
	for side_rail in [-1.0, 1.0]:
		g.add_child(box(0.007, 0.024, 0.11, side_rail * 0.022, 0.012, -0.26, "dark"))
	g.add_child(box(0.024, 0.007, 0.11, 0, -0.016, -0.26, "dark"))
	# 短枪管 + 消焰器
	g.add_child(cyl(0.011, 0.013, 0.4, 0, ry, -0.44))
	g.add_child(cyl(0.015, 0.017, 0.04, 0, ry, -0.66, "dark"))
	# 侧折叠骨架托 + 握把
	g.add_child(box(0.026, 0.05, 0.04, 0, 0.003, 0.12, "dark"))
	g.add_child(box(0.022, 0.02, 0.14, 0, 0.044, 0.19, "poly"))
	g.add_child(box(0.022, 0.02, 0.14, 0, -0.012, 0.19, "poly"))
	g.add_child(box(0.04, 0.075, 0.024, 0, 0.006, 0.25, "poly"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.023, 0.04, "poly", 0.36))
	_trigger(g, -0.035, 0.005)
	_mag_straight(g, 0.034, 0.13, 0.055, 0, -0.023, -0.09, "dark", 0.12)
	_bolt(g, 0.028, 0.05, 0.04, 1.0, "dark")
	_irons(g, 0.09, -0.5, 0.05, 0.045, ry)


## HK MP7:紧凑机匣 + 顶部导轨 + 折叠前握把 + 伸缩托 + 握把弹匣
static func _build_mp7(g: Node3D) -> void:
	var ry := 0.018
	# 紧凑机匣 + 顶部导轨
	g.add_child(box(0.042, 0.06, 0.26, 0, 0.015, -0.05, "poly"))
	_rail(g, 0.075, 0.03, -0.28, 0.022, "dark")
	# 细短枪管 + 开槽消焰器
	g.add_child(cyl(0.008, 0.009, 0.26, 0, ry, -0.32))
	g.add_child(cyl(0.011, 0.012, 0.04, 0, ry, -0.46, "dark"))
	# 折叠前握把
	g.add_child(_grip(0.024, 0.06, 0.032, 0, -0.018, -0.14, "poly", 0.2))
	# 伸缩托(双杆 + 托垫)
	g.add_child(cyl(0.006, 0.006, 0.12, 0.012, 0.035, 0.14, "metal", "z"))
	g.add_child(cyl(0.006, 0.006, 0.12, -0.012, 0.035, 0.14, "metal", "z"))
	g.add_child(box(0.038, 0.075, 0.022, 0, 0.008, 0.21, "poly"))
	# 握把 + 弹匣(穿过握把,前倾)
	g.add_child(_grip(0.028, 0.09, 0.04, 0, -0.02, 0.03, "poly", 0.38))
	_trigger(g, -0.033, 0.01)
	_mag_straight(g, 0.03, 0.14, 0.045, 0, -0.02, -0.1, "dark", 0.1)
	_bolt(g, 0.024, 0.045, 0.03, 1.0, "dark")
	_irons(g, 0.085, -0.42, 0.045, 0.04, ry)


## PP-2000:方形紧凑机匣 + 顶部导轨 + 前置握把弹匣 + 后置折叠托
static func _build_pp2000(g: Node3D) -> void:
	var ry := 0.024
	# 方形机匣 + 顶部导轨
	g.add_child(box(0.046, 0.07, 0.3, 0, 0.014, -0.02, "poly"))
	_rail(g, 0.08, 0.04, -0.32, 0.024, "dark")
	# 短枪管 + 枪口
	g.add_child(cyl(0.011, 0.013, 0.3, 0, ry, -0.38))
	g.add_child(cyl(0.014, 0.015, 0.035, 0, ry, -0.53, "dark"))
	# 前置握把弹匣(PP-2000 弹匣即前握把,长直插入)
	g.add_child(_grip(0.032, 0.08, 0.05, 0, -0.022, -0.08, "poly", 0.28))
	_mag_straight(g, 0.032, 0.16, 0.05, 0, -0.022, -0.08, "dark")
	# 后置折叠托(折叠时兼作枪托/备用弹匣槽)
	g.add_child(box(0.026, 0.05, 0.04, 0, 0.005, 0.14, "dark"))
	g.add_child(box(0.022, 0.018, 0.14, 0, 0.045, 0.2, "poly"))
	g.add_child(box(0.038, 0.07, 0.022, 0, 0.01, 0.26, "poly"))
	# 扳机靠后
	_trigger(g, -0.034, 0.02)
	_bolt(g, 0.026, 0.045, 0.02, 1.0, "dark")
	_irons(g, 0.09, -0.46, 0.05, 0.045, ry)


# === [10/10] 轻机枪批次:逐把独立构建(结构资料见 tools/research_lmg_batch3.md) ===

## M249 SAW:长机匣 + 顶部受弹机盖(独立动画件)+ 左挂弹链箱 + 圆护木 + 聚合物托
static func _build_m249(g: Node3D) -> void:
	var ry := 0.028
	# 大机匣 + 受弹机盖(换弹开盖动画件,导轨随盖走)
	g.add_child(box(0.062, 0.1, 0.46, 0, 0.02, -0.08, "metal"))
	var cover := _feed_cover(g, 0.085, -0.1, 0.46, 0.052, "dark")
	_rail(cover, 0.021, -0.03, -0.47, 0.026, "dark")
	# 左挂 200 发弹链箱 + 可见弹链尾(左供弹)
	_side_belt_feed(g, -1.0, Vector3(-0.062, -0.075, -0.12), Vector3(0.075, 0.11, 0.13),
		Vector3(-0.026, -0.015, -0.16), "olive")
	# 圆护木 + 枪管提把 + 枪管 + 消焰器
	g.add_child(cyl(0.028, 0.032, 0.26, 0, ry, -0.42, "dark"))
	g.add_child(box(0.05, 0.012, 0.16, 0, ry + 0.032, -0.42, "poly"))   # 上护手板
	g.add_child(box(0.016, 0.04, 0.05, 0, ry + 0.038, -0.52, "dark"))   # 枪管提把
	g.add_child(cyl(0.014, 0.016, 0.4, 0, ry, -0.68))
	g.add_child(cyl(0.02, 0.022, 0.06, 0, ry, -0.875, "dark"))
	# 折叠两脚架(收折贴护木)
	g.add_child(box(0.008, 0.14, 0.008, -0.03, -0.075, -0.5, "dark"))
	g.add_child(box(0.008, 0.14, 0.008, 0.03, -0.075, -0.5, "dark"))
	# 聚合物枪托 + 液压缓冲 + 握把
	g.add_child(_grip(0.048, 0.1, 0.18, 0, -0.008, 0.19, "poly", 0.1))
	g.add_child(box(0.052, 0.1, 0.02, 0, 0.0, 0.28, "poly"))
	g.add_child(cyl(0.016, 0.016, 0.04, 0, 0.008, 0.14, "dark"))
	g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.03, 0.05, "poly", 0.35))
	_trigger(g, -0.04, 0.02)
	_bolt(g, 0.035, 0.03, 0.02, 1.0, "dark")
	_irons(g, 0.125, -0.6, 0.1, 0.055, ry)


## PKM:矩形机匣 + 顶盖 + 右供弹链箱 + 木护木/木托 + 左侧枪管提把
static func _build_pkm(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(box(0.062, 0.1, 0.46, 0, 0.02, -0.06, "metal"))
	_feed_cover(g, 0.082, -0.08, 0.48, 0.052, "dark")
	# PKM 特征:右供弹、左侧抛壳
	_side_belt_feed(g, 1.0, Vector3(0.062, -0.075, -0.1), Vector3(0.075, 0.11, 0.13),
		Vector3(0.026, -0.015, -0.15), "dark")
	# 枪管 + 左侧折叠提把 + 锥形消焰器
	g.add_child(cyl(0.028, 0.032, 0.28, 0, ry, -0.42, "wood"))
	g.add_child(box(0.046, 0.012, 0.18, 0, ry + 0.032, -0.42, "wood"))
	g.add_child(cyl(0.015, 0.017, 0.42, 0, ry, -0.7))
	g.add_child(cyl(0.02, 0.023, 0.06, 0, ry, -0.9, "dark"))
	g.add_child(box(0.012, 0.03, 0.1, -0.036, 0.056, -0.3, "dark"))   # 左提把
	# 木质枪托 + 握把 + 两脚架
	g.add_child(_grip(0.048, 0.1, 0.19, 0, -0.008, 0.19, "wood", 0.12))
	g.add_child(box(0.052, 0.1, 0.02, 0, 0.0, 0.29, "wood"))
	g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.03, 0.05, "wood", 0.38))
	_trigger(g, -0.04, 0.02)
	g.add_child(box(0.008, 0.13, 0.008, -0.03, -0.07, -0.48, "dark"))
	g.add_child(box(0.008, 0.13, 0.008, 0.03, -0.07, -0.48, "dark"))
	_bolt(g, 0.035, 0.03, 0.04, 1.0, "dark")
	_irons(g, 0.122, -0.6, 0.1, 0.055, ry)


## RPD:左侧金属弹鼓 + 顶部供弹盖 + 木托/木护木 + 折叠两脚架
static func _build_rpd(g: Node3D) -> void:
	var ry := 0.026
	# 机匣 + 顶部供弹盖(静态低盖;换弹由弹鼓流程驱动)
	g.add_child(box(0.056, 0.085, 0.4, 0, 0.018, -0.06, "metal"))
	g.add_child(box(0.052, 0.022, 0.4, 0, 0.068, -0.08, "dark"))
	g.add_child(box(0.054, 0.008, 0.14, 0, 0.081, -0.12, "dark"))
	# 左侧 100 发金属弹鼓(鼓面朝侧,与换弹 drum 流程对齐)
	var drum_root := Node3D.new()
	drum_root.position = Vector3(-0.048, -0.06, -0.08)
	drum_root.add_child(cyl(0.075, 0.075, 0.05, 0, 0, 0, "brass", "x"))
	drum_root.add_child(cyl(0.03, 0.036, 0.035, 0.026, 0.012, 0.0, "dark", "x"))  # 接口颈
	drum_root.add_child(cyl(0.062, 0.062, 0.012, -0.012, 0.045, 0.0, "dark", "x"))  # 鼓面锁扣
	drum_root.add_child(cyl(0.062, 0.062, 0.012, -0.012, -0.055, 0.0, "dark", "x"))
	g.add_child(drum_root)
	g.set_meta("mag", drum_root)
	g.add_child(box(0.024, 0.03, 0.05, -0.048, -0.028, -0.08, "dark"))             # 挂座
	# 木护木 + 枪管 + 消焰器 + 折叠两脚架
	g.add_child(cyl(0.026, 0.03, 0.28, 0, ry, -0.39, "wood"))
	g.add_child(cyl(0.013, 0.015, 0.42, 0, ry, -0.68))
	g.add_child(cyl(0.018, 0.021, 0.05, 0, ry, -0.875, "dark"))
	g.add_child(box(0.008, 0.14, 0.008, -0.03, -0.07, -0.5, "dark"))
	g.add_child(box(0.008, 0.14, 0.008, 0.03, -0.07, -0.5, "dark"))
	# 木托 + 木握把
	g.add_child(_grip(0.044, 0.095, 0.19, 0, -0.006, 0.18, "wood", 0.14))
	g.add_child(box(0.048, 0.095, 0.02, 0, 0.0, 0.28, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
	_trigger(g, -0.036, 0.01)
	_bolt(g, 0.032, 0.035, 0.0, 1.0, "dark")
	_irons(g, 0.115, -0.58, 0.1, 0.055, ry)


## MG42:方形机匣 + 顶部开盖 + 左供弹 + 多孔枪管套筒 + 木托
static func _build_mg42(g: Node3D) -> void:
	var ry := 0.024
	g.add_child(box(0.05, 0.09, 0.4, 0, 0.018, 0.02, "metal"))
	_feed_cover(g, 0.062, -0.12, 0.5, 0.05, "dark")
	_side_belt_feed(g, -1.0, Vector3(-0.060, -0.068, -0.07), Vector3(0.07, 0.1, 0.12),
		Vector3(-0.024, -0.018, -0.14), "olive")
	# 多孔枪管套筒(散热孔沿套筒排布)+ 枪口助退器
	g.add_child(cyl(0.022, 0.023, 0.56, 0, ry, -0.45, "dark"))
	for hole_z in [-0.62, -0.55, -0.48, -0.41, -0.34, -0.27]:
		g.add_child(box(0.052, 0.012, 0.02, 0, ry, hole_z, "metal"))
	g.add_child(cyl(0.014, 0.016, 0.06, 0, ry, -0.71, "dark"))
	# 两脚架 + 木托 + 握把
	g.add_child(box(0.02, 0.11, 0.03, 0, -0.035, -0.35, "dark"))
	for leg_s in [-1.0, 1.0]:
		var leg := cyl(0.006, 0.006, 0.16, leg_s * 0.03, -0.09, -0.35, "dark", "z")
		leg.rotation.z = leg_s * 0.3
		g.add_child(leg)
	g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.2, "wood", 0.14))
	g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.3, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "wood", 0.4))
	_trigger(g, -0.037, 0.02)
	_bolt(g, 0.03, 0.045, 0.02, 1.0, "dark")
	_irons(g, 0.13, -0.55, 0.05, 0.05, ry)


## M60:盒式机匣 + 顶盖 + 左挂弹链箱 + 粗枪管 + 提把 + 木托
static func _build_m60(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(box(0.052, 0.085, 0.34, 0, 0.018, -0.04, "metal"))
	_feed_cover(g, 0.0625, -0.04, 0.34, 0.052, "dark")
	g.add_child(box(0.03, 0.035, 0.14, 0, 0.073, -0.18, "poly"))       # 顶部提把
	_side_belt_feed(g, -1.0, Vector3(-0.060, -0.066, -0.05), Vector3(0.07, 0.1, 0.12),
		Vector3(-0.024, -0.018, -0.12), "olive")
	# 粗枪管 + 消焰器 + 两脚架
	g.add_child(cyl(0.016, 0.018, 0.56, 0, ry, -0.47))
	g.add_child(cyl(0.02, 0.022, 0.06, 0, ry, -0.735, "dark"))
	g.add_child(box(0.008, 0.13, 0.008, -0.03, -0.06, -0.45, "dark"))
	g.add_child(box(0.008, 0.13, 0.008, 0.03, -0.06, -0.45, "dark"))
	# 木托 + 握把
	g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.18, "wood", 0.14))
	g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
	_trigger(g, -0.036, 0.02)
	_bolt(g, 0.03, 0.045, 0.0, 1.0, "dark")
	_irons(g, 0.125, -0.52, 0.05, 0.05, ry)


## Mk 48:FN Minimi 放大版,长机匣 + 顶部轨 + 左挂弹链箱 + 重管 + 可调托
static func _build_mk48(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(box(0.052, 0.09, 0.38, 0, 0.018, -0.04, "tan"))
	var mk48_cover := _feed_cover(g, 0.062, -0.16, 0.46, 0.052, "dark")
	_rail(mk48_cover, 0.018, -0.03, -0.42, 0.026, "dark")
	_side_belt_feed(g, -1.0, Vector3(-0.060, -0.065, -0.05), Vector3(0.07, 0.1, 0.12),
		Vector3(-0.024, -0.018, -0.13), "olive")
	# 重管 + 短护木 + 消焰器 + 两脚架
	g.add_child(cyl(0.026, 0.03, 0.18, 0, ry, -0.34, "dark"))
	g.add_child(cyl(0.014, 0.016, 0.58, 0, ry, -0.51))
	g.add_child(cyl(0.018, 0.02, 0.06, 0, ry, -0.795, "dark"))
	g.add_child(box(0.008, 0.14, 0.008, -0.03, -0.07, -0.46, "dark"))
	g.add_child(box(0.008, 0.14, 0.008, 0.03, -0.07, -0.46, "dark"))
	# 可调聚合物托 + 握把
	g.add_child(cyl(0.012, 0.012, 0.1, 0, 0.035, 0.18, "dark", "z"))
	g.add_child(box(0.042, 0.085, 0.13, 0, 0.01, 0.2, "poly"))
	g.add_child(box(0.046, 0.095, 0.02, 0, 0.01, 0.27, "dark"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "poly", 0.4))
	_trigger(g, -0.037, 0.02)
	_bolt(g, 0.03, 0.045, 0.02, 1.0, "dark")
	_irons(g, 0.13, -0.58, 0.05, 0.05, ry)


## IWI Negev:长机匣 + 顶盖 + 左供弹 + 机匣固定轨 + 前握把 + 折叠托
static func _build_negev(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(box(0.052, 0.09, 0.44, 0, 0.018, -0.06, "olive"))
	_feed_cover(g, 0.062, -0.06, 0.44, 0.052, "dark")
	# 瞄准镜轨装在机匣框架上(Negev 实枪特征):换弹开盖时瞄具不跟着掀
	_rail(g, 0.086, 0.1, -0.2, 0.024, "dark")
	_side_belt_feed(g, -1.0, Vector3(-0.060, -0.065, -0.05), Vector3(0.07, 0.1, 0.12),
		Vector3(-0.024, -0.018, -0.12), "olive")
	# 枪管 + 前握把 + 两脚架 + 消焰器
	g.add_child(cyl(0.012, 0.014, 0.6, 0, ry, -0.56))
	g.add_child(cyl(0.016, 0.018, 0.06, 0, ry, -0.83, "dark"))
	g.add_child(_grip(0.026, 0.07, 0.04, 0, -0.018, -0.26, "olive", 0.18))
	g.add_child(box(0.008, 0.14, 0.008, -0.03, -0.07, -0.4, "dark"))
	g.add_child(box(0.008, 0.14, 0.008, 0.03, -0.07, -0.4, "dark"))
	# 折叠骨架托 + 握把
	g.add_child(box(0.028, 0.05, 0.04, 0, 0.005, 0.16, "dark"))
	g.add_child(box(0.022, 0.02, 0.15, 0, 0.045, 0.22, "poly"))
	g.add_child(box(0.022, 0.02, 0.15, 0, -0.012, 0.22, "poly"))
	g.add_child(box(0.04, 0.08, 0.024, 0, 0.008, 0.29, "poly"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "poly", 0.4))
	_trigger(g, -0.037, 0.02)
	_bolt(g, 0.03, 0.045, 0.02, 1.0, "dark")
	_irons(g, 0.125, -0.6, 0.05, 0.05, ry)


## MG3:MG42 现代化型,黑色聚合物家具 + 左供弹 + 多孔套筒 + 鼓式照门
static func _build_mg3(g: Node3D) -> void:
	var ry := 0.024
	g.add_child(box(0.05, 0.09, 0.4, 0, 0.018, 0.02, "dark"))
	_feed_cover(g, 0.062, -0.12, 0.5, 0.05, "dark")
	# MG3 与 MG42 同方向左供弹;外观靠黑聚合物与鼓式照门区分
	_side_belt_feed(g, -1.0, Vector3(-0.060, -0.068, -0.07), Vector3(0.07, 0.1, 0.12),
		Vector3(-0.024, -0.018, -0.14), "dark")
	# 多孔枪管套筒 + 枪口
	g.add_child(cyl(0.022, 0.023, 0.56, 0, ry, -0.45, "dark"))
	for hole_z in [-0.62, -0.55, -0.48, -0.41, -0.34, -0.27]:
		g.add_child(box(0.052, 0.012, 0.02, 0, ry, hole_z, "dark"))
	g.add_child(cyl(0.014, 0.016, 0.06, 0, ry, -0.71, "dark"))
	# 两脚架 + 聚合物托/握把
	g.add_child(box(0.02, 0.11, 0.03, 0, -0.035, -0.35, "dark"))
	for leg_s in [-1.0, 1.0]:
		var leg := cyl(0.006, 0.006, 0.16, leg_s * 0.03, -0.09, -0.35, "dark", "z")
		leg.rotation.z = leg_s * 0.3
		g.add_child(leg)
	g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.008, 0.2, "poly", 0.14))
	g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.3, "poly"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.025, 0.05, "poly", 0.4))
	_trigger(g, -0.037, 0.02)
	_bolt(g, 0.03, 0.045, 0.02, 1.0, "dark")
	_irons(g, 0.13, -0.55, 0.05, 0.05, ry)


# === [10/10] 狙击/DMR批次:逐把独立构建(结构资料见 tools/research_sniper_dmr_batch4.md) ===

## AWM:AI 绿色拇指孔托 + 贴腮板 + 自由浮置重管 + 大制退器 + 5 发弹匣 + 大栓柄
static func _build_awm(g: Node3D) -> void:
	var ry := 0.03
	g.add_child(box(0.05, 0.072, 0.38, 0, 0.012, -0.04, "olive"))
	g.add_child(box(0.046, 0.03, 0.16, 0, 0.052, 0.1, "olive"))    # 贴腮
	g.add_child(cyl(0.013, 0.017, 0.62, 0, ry, -0.55))             # 长管
	g.add_child(cyl(0.02, 0.023, 0.08, 0, ry, -0.885, "dark"))     # 制退器
	g.add_child(_grip(0.046, 0.1, 0.18, 0, -0.008, 0.2, "olive", 0.12))
	g.add_child(box(0.05, 0.1, 0.02, 0, 0.0, 0.29, "olive"))
	g.add_child(box(0.048, 0.055, 0.04, 0, -0.05, 0.24, "dark"))   # 拇指孔托底
	g.add_child(_grip(0.034, 0.09, 0.045, 0, -0.024, 0.05, "olive", 0.42))
	_trigger(g, -0.036, 0.03)
	_mag_straight(g, 0.036, 0.09, 0.08, 0, -0.024, -0.08, "dark")
	var bolt_a := Node3D.new()
	bolt_a.position = Vector3(0.03, 0.05, 0.1)
	bolt_a.add_child(cyl(0.006, 0.006, 0.05, 0, 0.02, 0, "chrome", "y"))
	bolt_a.add_child(cyl(0.014, 0.014, 0.02, 0, 0.045, 0, "chrome"))
	g.add_child(bolt_a)
	g.set_meta("bolt", bolt_a)
	_scope(g, 0.115, -0.06, 0.0495)


## M24:雷明顿 700 构型,黑聚合物托 + 可调贴腮 + 重管 + 内置弹仓 + 大栓柄
static func _build_m24(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(box(0.05, 0.072, 0.42, 0, 0.012, -0.05, "poly"))
	g.add_child(box(0.044, 0.035, 0.16, 0, 0.05, 0.12, "poly"))    # 贴腮
	g.add_child(cyl(0.013, 0.016, 0.62, 0, ry, -0.55))
	g.add_child(cyl(0.018, 0.021, 0.06, 0, ry, -0.83, "dark"))
	g.add_child(_grip(0.046, 0.1, 0.18, 0, -0.008, 0.2, "poly", 0.12))
	g.add_child(box(0.05, 0.1, 0.02, 0, 0.0, 0.29, "poly"))
	g.add_child(_grip(0.034, 0.09, 0.045, 0, -0.024, 0.05, "poly", 0.42))
	_trigger(g, -0.036, 0.03)
	# M24 为内置弹仓:无实体弹匣,换弹控制器按装填口路径处理
	g.add_child(box(0.03, 0.02, 0.09, 0, -0.05, -0.05, "dark"))
	var bolt_b := Node3D.new()
	bolt_b.position = Vector3(0.03, 0.05, 0.1)
	bolt_b.add_child(cyl(0.006, 0.006, 0.05, 0, 0.02, 0, "dark", "y"))
	bolt_b.add_child(cyl(0.013, 0.013, 0.02, 0, 0.045, 0, "dark"))
	g.add_child(bolt_b)
	g.set_meta("bolt", bolt_b)
	_scope(g, 0.112, -0.06, 0.0495)


## SVD:AK 系机匣 + 木质骨架托 + 细长管 + PSO 侧轨镜 + 弧形弹匣
static func _build_svd(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(box(0.052, 0.068, 0.36, 0, 0.014, -0.03, "wood"))
	g.add_child(box(0.048, 0.016, 0.26, 0, 0.052, -0.04, "dark"))
	g.add_child(cyl(0.011, 0.013, 0.64, 0, ry, -0.545))
	g.add_child(box(0.016, 0.05, 0.014, 0, 0.055, -0.6, "dark"))
	g.add_child(cyl(0.015, 0.018, 0.06, 0, ry, -0.81, "dark"))
	# SVD 骨架托:上梁 + 下梁 + 托底 + 贴腮
	g.add_child(box(0.03, 0.03, 0.2, 0, 0.032, 0.18, "wood"))
	g.add_child(box(0.03, 0.035, 0.18, 0, -0.014, 0.17, "wood"))
	g.add_child(box(0.046, 0.095, 0.024, 0, 0.0, 0.28, "wood"))
	g.add_child(box(0.04, 0.05, 0.06, 0, 0.045, 0.12, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.02, 0.045, "wood", 0.42))
	_trigger(g, -0.034, 0.02)
	_curved_mag(g, 0.036, 0, -0.02, -0.1, "metal")
	_bolt(g, 0.032, 0.035, -0.02, 1.0, "dark")
	# PSO-1 侧装镜
	g.add_child(box(0.012, 0.03, 0.1, -0.03, 0.06, -0.04, "dark"))
	_scope(g, 0.115, -0.02, 0.0495)


## M40A3:雷明顿 700 构型,绿色玻璃纤维托 + 重管 + 内置弹仓 + 大镜
static func _build_m40(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(cyl(0.011, 0.013, 0.55, 0, ry, -0.49))
	g.add_child(cyl(0.014, 0.016, 0.05, 0, ry, -0.72, "dark"))
	g.add_child(box(0.048, 0.07, 0.3, 0, 0.015, -0.1, "olive"))
	g.add_child(box(0.04, 0.04, 0.18, 0, 0.05, -0.16, "olive"))
	g.add_child(_grip(0.04, 0.085, 0.2, 0, -0.003, 0.16, "olive", 0.1))
	g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.26, "olive"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "olive", 0.4))
	_trigger(g, -0.036, 0.02)
	g.add_child(box(0.03, 0.018, 0.09, 0, -0.05, -0.06, "dark"))
	_bolt(g, 0.028, 0.045, 0.04, 1.0, "dark")
	_simple_scope(g, 0.113, -0.14, 0.26, 0.07)


## Barrett M82A1:大尺寸反器材,方机匣 + 箭形制退器 + 两脚架 + 10 发弹匣 + 大镜
static func _build_m82a1(g: Node3D) -> void:
	var ry := 0.03
	g.add_child(cyl(0.016, 0.018, 0.78, 0, ry, -0.65))
	g.add_child(box(0.024, 0.045, 0.09, 0, ry, -1.0, "dark"))       # 箭形制退器
	g.add_child(box(0.06, 0.1, 0.42, 0, 0.02, -0.06, "tan"))
	g.add_child(box(0.05, 0.035, 0.36, 0, 0.078, -0.14, "dark"))
	g.add_child(box(0.01, 0.16, 0.03, -0.035, -0.1, -0.55, "dark"))  # 两脚架左
	g.add_child(box(0.01, 0.16, 0.03, 0.035, -0.1, -0.55, "dark"))   # 两脚架右
	g.add_child(_grip(0.048, 0.11, 0.24, 0, -0.008, 0.2, "dark", 0.14))
	g.add_child(box(0.052, 0.11, 0.02, 0, 0.0, 0.32, "dark"))
	g.add_child(_grip(0.038, 0.11, 0.05, 0, -0.025, 0.04, "dark", 0.4))
	_trigger(g, -0.04, 0.02)
	_mag_straight(g, 0.04, 0.1, 0.07, 0, -0.025, -0.16, "dark")
	_bolt(g, 0.032, 0.05, 0.02, 1.0, "dark")
	_simple_scope(g, 0.116, -0.12, 0.3, 0.074, 0.022)


## L115A3:AWM 系,深色托 + 可调贴腮 + 长管 + 5 发弹匣 + 大镜
static func _build_l115(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(cyl(0.011, 0.013, 0.64, 0, ry, -0.56))
	g.add_child(cyl(0.015, 0.017, 0.05, 0, ry, -0.88, "dark"))
	g.add_child(box(0.048, 0.07, 0.32, 0, 0.015, -0.1, "dark"))
	g.add_child(box(0.04, 0.045, 0.2, 0, 0.052, -0.18, "dark"))
	g.add_child(_grip(0.04, 0.085, 0.2, 0, -0.003, 0.16, "dark", 0.1))
	g.add_child(box(0.044, 0.085, 0.02, 0, 0.0, 0.26, "dark"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.4))
	_trigger(g, -0.036, 0.02)
	_mag_straight(g, 0.028, 0.05, 0.05, 0, -0.02, -0.08, "dark")
	_bolt(g, 0.028, 0.045, 0.04, 1.0, "dark")
	_simple_scope(g, 0.114, -0.15, 0.3, 0.072)


## SV-98:俄制栓动,木质拇指孔托 + 重型枪口制退器 + 10 发弹匣 + 大镜
static func _build_sv98(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(cyl(0.011, 0.013, 0.58, 0, ry, -0.51))
	g.add_child(cyl(0.016, 0.019, 0.07, 0, ry, -0.815, "dark"))
	g.add_child(box(0.05, 0.075, 0.3, 0, 0.015, -0.08, "wood"))
	g.add_child(box(0.04, 0.05, 0.2, 0, 0.055, -0.16, "wood"))
	g.add_child(_grip(0.042, 0.09, 0.2, 0, -0.003, 0.16, "wood", 0.1))
	g.add_child(box(0.046, 0.09, 0.02, 0, 0.0, 0.26, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
	_trigger(g, -0.036, 0.02)
	_mag_straight(g, 0.03, 0.055, 0.05, 0, -0.02, -0.09, "dark")
	_bolt(g, 0.028, 0.045, 0.04, 1.0, "dark")
	_simple_scope(g, 0.113, -0.13, 0.28, 0.07)


## M2010 ESR:雷明顿 MSR 式沙色骨架托 + 长管 + 5 发弹匣 + 大镜
static func _build_m2010(g: Node3D) -> void:
	var ry := 0.028
	g.add_child(cyl(0.011, 0.013, 0.66, 0, ry, -0.57))
	g.add_child(cyl(0.015, 0.017, 0.05, 0, ry, -0.895, "dark"))
	g.add_child(box(0.048, 0.072, 0.3, 0, 0.015, -0.1, "tan"))
	g.add_child(box(0.04, 0.042, 0.2, 0, 0.05, -0.18, "tan"))
	# 骨架托:上梁 + 下梁 + 托垫(可折叠风格)
	g.add_child(box(0.022, 0.022, 0.18, 0, 0.042, 0.17, "tan"))
	g.add_child(box(0.022, 0.022, 0.18, 0, -0.012, 0.17, "tan"))
	g.add_child(box(0.044, 0.085, 0.022, 0, 0.004, 0.25, "dark"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.4))
	_trigger(g, -0.036, 0.02)
	_mag_straight(g, 0.028, 0.05, 0.05, 0, -0.02, -0.08, "dark")
	_bolt(g, 0.028, 0.045, 0.04, 1.0, "dark")
	_simple_scope(g, 0.115, -0.15, 0.3, 0.07)


## M110:AR-10 构型,沙色机匣 + 全顶轨 + 长护木 + 固定托 + 镂空 DMR 镜
static func _build_m110(g: Node3D) -> void:
	var ry := 0.024
	g.add_child(box(0.05, 0.075, 0.34, 0, 0.016, -0.06, "tan"))
	g.add_child(box(0.046, 0.026, 0.48, 0, 0.062, -0.2, "dark"))
	_rail(g, 0.086, 0.02, -0.44)
	g.add_child(cyl(0.024, 0.028, 0.3, 0, ry, -0.42, "tan"))
	g.add_child(cyl(0.011, 0.013, 0.62, 0, ry, -0.52))
	g.add_child(cyl(0.016, 0.019, 0.05, 0, ry, -0.82, "dark"))
	_hollow_dmr_scope(g, 0.096, -0.30, -0.12)
	g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "tan", 0.1))
	g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "tan"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
	_trigger(g, -0.036, 0.01)
	_mag_straight(g, 0.036, 0.1, 0.06, 0, -0.021, -0.1, "tan", 0.1)
	_bolt(g, 0.028, 0.045, -0.02, 1.0, "dark")
	_irons(g, 0.11, -0.55, 0.05, 0.05, ry)
	var ir := g.get_node_or_null("StockIrons")
	if ir != null:
		ir.visible = false


## SKS:木托半自动 + 固定弹仓 + 短管 + 折叠刺刀 + 镂空 DMR 镜
static func _build_sks(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(cyl(0.011, 0.013, 0.47, 0, ry, -0.44))
	g.add_child(cyl(0.015, 0.017, 0.05, 0, ry, -0.66, "dark"))
	g.add_child(box(0.05, 0.08, 0.34, 0, 0.016, -0.04, "wood"))
	g.add_child(box(0.044, 0.026, 0.3, 0, 0.06, -0.1, "dark"))
	g.add_child(box(0.01, 0.025, 0.16, 0.03, -0.01, -0.52, "dark"))   # 折叠刺刀
	_hollow_dmr_scope(g, 0.092, -0.25, -0.10)
	g.add_child(_grip(0.042, 0.095, 0.2, 0, -0.006, 0.18, "wood", 0.1))
	g.add_child(box(0.046, 0.095, 0.02, 0, 0.0, 0.28, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.045, "wood", 0.4))
	_trigger(g, -0.036, 0.02)
	# SKS 为固定弹仓:仅做底板,不设 meta mag,换弹走装填口路径
	g.add_child(box(0.03, 0.02, 0.08, 0, -0.052, -0.06, "dark"))
	_bolt(g, 0.028, 0.04, 0.0, 1.0, "dark")
	_irons(g, 0.105, -0.5, 0.05, 0.05, ry)
	var sks_irons := g.get_node_or_null("StockIrons")
	if sks_irons != null:
		sks_irons.visible = false


## M1A:M14 民用型,木托 + 20 发弹匣 + 镂空 DMR 镜
static func _build_m1a(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(cyl(0.012, 0.014, 0.56, 0, ry, -0.5))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.755, "dark"))
	g.add_child(box(0.05, 0.082, 0.34, 0, 0.016, -0.06, "wood"))
	g.add_child(box(0.046, 0.028, 0.3, 0, 0.064, -0.12, "dark"))
	_hollow_dmr_scope(g, 0.092, -0.28, -0.10)
	g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.006, 0.18, "wood", 0.12))
	g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
	_trigger(g, -0.036, 0.02)
	_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.025, -0.09, "dark", 0.08)
	_bolt(g, 0.03, 0.04, 0.0, 1.0, "dark")
	_irons(g, 0.112, -0.56, 0.05, 0.06, ry)
	var m1a_irons := g.get_node_or_null("StockIrons")
	if m1a_irons != null:
		m1a_irons.visible = false


## G28:HK417 构型,AR 式机匣 + 长顶轨 + 镂空 DMR 镜 + 可调托
static func _build_g28(g: Node3D) -> void:
	var ry := 0.024
	g.add_child(box(0.05, 0.075, 0.32, 0, 0.016, -0.06, "tan"))
	g.add_child(box(0.046, 0.026, 0.4, 0, 0.062, -0.16, "dark"))
	_rail(g, 0.086, 0.02, -0.42)
	g.add_child(cyl(0.012, 0.014, 0.56, 0, ry, -0.49))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.755, "dark"))
	_hollow_dmr_scope(g, 0.094, -0.28, -0.10)
	g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "poly", 0.1))
	g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "poly"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
	_trigger(g, -0.036, 0.01)
	_mag_straight(g, 0.036, 0.1, 0.06, 0, -0.021, -0.1, "tan", 0.1)
	_bolt(g, 0.028, 0.045, -0.02, 1.0, "dark")
	_irons(g, 0.11, -0.55, 0.05, 0.05, ry)
	var g28_irons := g.get_node_or_null("StockIrons")
	if g28_irons != null:
		g28_irons.visible = false


## MK14 EBR:M14 底盘的导轨机匣 + 镂空 DMR 镜 + 可调托
static func _build_mk14(g: Node3D) -> void:
	var ry := 0.024
	g.add_child(box(0.05, 0.075, 0.34, 0, 0.016, -0.06, "dark"))
	g.add_child(box(0.046, 0.028, 0.46, 0, 0.062, -0.2, "dark"))
	_rail(g, 0.086, 0.02, -0.44)
	g.add_child(cyl(0.012, 0.014, 0.62, 0, ry, -0.53))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.815, "dark"))
	g.add_child(box(0.046, 0.018, 0.28, 0, 0.018, -0.32, "tan"))   # EBR 护木下轨
	_hollow_dmr_scope(g, 0.094, -0.3, -0.12)
	g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "tan", 0.1))
	g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "tan"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
	_trigger(g, -0.036, 0.01)
	_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.021, -0.09, "tan", 0.08)
	_bolt(g, 0.03, 0.045, -0.02, 1.0, "dark")
	_irons(g, 0.11, -0.55, 0.05, 0.05, ry)
	var mk14_irons := g.get_node_or_null("StockIrons")
	if mk14_irons != null:
		mk14_irons.visible = false


## M14:经典木托战斗步枪,只保留机械瞄具,与 M1A 的镜座型明显区分
static func _build_m14(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(cyl(0.012, 0.014, 0.58, 0, ry, -0.51))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.775, "dark"))
	g.add_child(box(0.05, 0.082, 0.34, 0, 0.016, -0.06, "wood"))
	g.add_child(box(0.046, 0.028, 0.32, 0, 0.064, -0.12, "dark"))
	g.add_child(box(0.016, 0.03, 0.1, 0.03, -0.01, -0.55, "dark"))   # 背带/刺刀座
	g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.006, 0.18, "wood", 0.12))
	g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
	_trigger(g, -0.036, 0.02)
	_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.025, -0.09, "dark", 0.08)
	_bolt(g, 0.03, 0.04, 0.0, 1.0, "dark")
	_irons(g, 0.112, -0.56, 0.05, 0.06, ry)


## AR-10:AR 系机匣 + 长顶轨 + 镂空 DMR 镜 + 20 发弹匣
static func _build_ar10(g: Node3D) -> void:
	var ry := 0.024
	g.add_child(box(0.05, 0.075, 0.32, 0, 0.016, -0.06, "poly"))
	g.add_child(box(0.046, 0.026, 0.38, 0, 0.062, -0.16, "dark"))
	_rail(g, 0.086, 0.01, -0.4)
	g.add_child(cyl(0.012, 0.014, 0.54, 0, ry, -0.48))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.735, "dark"))
	_hollow_dmr_scope(g, 0.094, -0.26, -0.10)
	g.add_child(_grip(0.04, 0.09, 0.2, 0, -0.003, 0.18, "poly", 0.1))
	g.add_child(box(0.044, 0.09, 0.02, 0, 0.0, 0.28, "poly"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "dark", 0.36))
	_trigger(g, -0.036, 0.01)
	_mag_straight(g, 0.036, 0.1, 0.06, 0, -0.021, -0.1, "dark", 0.1)
	_bolt(g, 0.028, 0.045, -0.02, 1.0, "dark")
	_irons(g, 0.11, -0.54, 0.05, 0.05, ry)
	var ar10_irons := g.get_node_or_null("StockIrons")
	if ar10_irons != null:
		ar10_irons.visible = false


## FN FAL:经典钢木战斗步枪 + 长管 + 镂空 DMR 镜 + 20 发弹匣
static func _build_fal(g: Node3D) -> void:
	var ry := 0.026
	g.add_child(cyl(0.012, 0.014, 0.55, 0, ry, -0.49))
	g.add_child(cyl(0.016, 0.018, 0.05, 0, ry, -0.755, "dark"))
	g.add_child(box(0.05, 0.08, 0.34, 0, 0.016, -0.06, "metal"))
	g.add_child(box(0.046, 0.026, 0.32, 0, 0.062, -0.12, "dark"))
	g.add_child(box(0.046, 0.04, 0.2, 0, 0.012, -0.24, "wood"))    # 木护木
	_hollow_dmr_scope(g, 0.092, -0.26, -0.10)
	g.add_child(_grip(0.042, 0.1, 0.2, 0, -0.006, 0.18, "wood", 0.12))
	g.add_child(box(0.046, 0.1, 0.02, 0, 0.0, 0.28, "wood"))
	g.add_child(_grip(0.034, 0.1, 0.045, 0, -0.024, 0.04, "wood", 0.4))
	_trigger(g, -0.036, 0.02)
	_mag_straight(g, 0.038, 0.12, 0.06, 0, -0.024, -0.09, "dark", 0.08)
	_bolt(g, -0.03, 0.04, -0.08, -1.0, "dark")                    # FAL 左侧拉机柄
	_irons(g, 0.112, -0.56, 0.05, 0.06, ry)
	var fal_irons := g.get_node_or_null("StockIrons")
	if fal_irons != null:
		fal_irons.visible = false


## ============ 各武器构建 ============
static func _build(id: String, g: Node3D) -> void:
	match id:
		"m4":
			_build_m4(g)
		"ak":
			_build_ak(g)
		"scar":
			_build_scar(g)
		"aug":
			_build_aug(g)
		"mp5":
			_build_mp5(g)
		"ump":
			_build_ump(g)
		"p90":
			_build_p90(g)
		"m249":
			_build_m249(g)
		"pkm":
			_build_pkm(g)
		"rpd":
			_build_rpd(g)
		"awm":
			_build_awm(g)
		"m24":
			_build_m24(g)
		"svd":
			_build_svd(g)
		"m1014":
			# M1014 半自动:一体式聚合物枪身,机匣、枪管罩、下护木连续,顶部导轨 + 前准星坐在枪身上
			_semi_shotgun(g, {
				"body_mat": "poly", "furniture_mat": "poly", "stock_mat": "poly",
				"body_w": 0.052, "body_h": 0.068, "body_y": 0.045,
				"muzzle_z": -0.7, "tube_y": -0.006, "tube_r": 0.012, "tube_z1": -0.63,
				"sight_y": 0.096, "top_rail": true,
			})
		"spas12":
			# SPAS-12 半自动:一体式枪身 + 顶部隔热槽 + 折叠托钩,枪管完全包在枪身内部
			_semi_shotgun(g, {
				"body_mat": "dark", "furniture_mat": "dark", "stock_mat": "dark",
				"body_w": 0.054, "body_h": 0.074, "body_y": 0.048,
				"muzzle_z": -0.72, "tube_y": -0.006, "tube_r": 0.0125, "tube_z1": -0.66,
				"sight_y": 0.1, "heat_slots": true, "folding_stock": true,
			})
		# ==================== [9/10] 3 把泵动霰弹枪模型 ====================
		"rem870":
			_build_rem870(g)
		"m590":
			_build_m590(g)
		"win1897":
			_build_win1897(g)
		# ==================== [9/10] 3 把左轮手枪模型 ====================
		"python":
			# 柯尔特蟒蛇:6 英寸枪管 + 全长通风肋 + 全尺寸下挂护管 + 木制靶握把 + 红色坡道准星
			_revolver(g, {
				"chambers": 6, "barrel_len": 0.152, "frame_mat": "chrome", "grip_mat": "wood",
				"barrel_y": 0.033, "sight_y": 0.093, "style": "python",
				"vent_rib": true, "underlug": true, "fluted": true, "grip_style": "target",
			})
		"sw686":
			# S&W 686:4 英寸枪管 + 紧凑 L 框架 + 橡胶指槽握把 + 黑色准星
			_revolver(g, {
				"chambers": 6, "barrel_len": 0.102, "frame_mat": "metal", "grip_mat": "poly",
				"barrel_y": 0.032, "sight_y": 0.091, "style": "686",
				"underlug": true, "fluted": true, "grip_style": "hogue",
			})
		"sw500":
			# S&W M500:X 框架 + 无槽 5 发重型弹巢 + 顶部战术轨 + 双室制退器 + X 框架大握把
			_revolver(g, {
				"chambers": 5, "barrel_len": 0.213, "frame_mat": "dark", "grip_mat": "poly",
				"barrel_y": 0.034, "sight_y": 0.096, "heavy": true, "style": "500",
				"top_rail": true, "compensator": true, "fluted": false, "grip_style": "xframe",
			})
		"rpg":
			# 现代反载具导弹:方形发射筒 + 顶部/底部导轨 + 大型侧置 CLU 指挥发射单元
			# [FIX] 发射筒主体收进 RpgBody 组:ADS 时整体隐藏(全屏 CLU 取景,与狙击镜
			# 隐藏镜筒同构)—— 旧版筒体留在 PIP 视线里,镜内下半屏被筒身黑块遮挡
			var rpg_body := Node3D.new()
			rpg_body.name = "RpgBody"
			rpg_body.add_child(cyl(0.047, 0.047, 0.78, 0, 0.02, -0.14, "olive"))       # 发射筒芯
			rpg_body.add_child(box(0.072, 0.020, 0.82, 0, 0.056, -0.14, "poly"))       # 顶部战术导轨
			rpg_body.add_child(box(0.072, 0.018, 0.82, 0, -0.018, -0.14, "poly"))      # 底部加强筋
			rpg_body.add_child(box(0.086, 0.086, 0.05, 0, 0.02, -0.51, "dark"))        # 方形前口护罩
			rpg_body.add_child(box(0.092, 0.092, 0.06, 0, 0.02, 0.21, "dark"))         # 方形尾盖
			g.add_child(rpg_body)
			g.set_meta("scope_hidden", rpg_body)
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
			rpg_body.add_child(box(0.045, 0.060, 0.14, 0.064, -0.012, -0.18, "poly"))  # 右侧 BCU
			rpg_body.add_child(box(0.006, 0.075, 0.006, -0.018, 0.112, 0.04, "dark"))   # IFF 天线
			rpg_body.add_child(_grip(0.036, 0.10, 0.05, 0, -0.030, 0.05, "dark", 0.3))
			rpg_body.add_child(box(0.050, 0.10, 0.04, 0, 0.0, 0.13, "poly"))            # 肩托
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
			rpg_body.add_child(rkt)
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
			_build_m1911(g)
		"g17":
			_build_g17(g)
		"p226":
			_build_p226(g)
		"deagle":
			_build_deagle(g)
		"m93r":
			_build_m93r(g)
		# ==================== [8/10 武器扩充] 10 把新枪模型 ====================
		"g36c":
			_build_g36c(g)
		"ak74":
			_build_ak74(g)
		"famas":
			_build_famas(g)
		"vector":
			_build_vector(g)
		"pp19":
			_build_pp19(g)
		"mg42":
			_build_mg42(g)
		"m60":
			_build_m60(g)
		"m110":
			_build_m110(g)
		"m40":
			_build_m40(g)
		"g3":
			_build_g3(g)
		# ==================== [8/10 武器扩充 v2] 17 把新枪模型(顶部零件低矮,ADS 不挡视野) ====================
		"mpx":
			_build_mpx(g)
		"mp7":
			_build_mp7(g)
		"pp2000":
			_build_pp2000(g)
		"mk48":
			_build_mk48(g)
		"negev":
			_build_negev(g)
		"mg3":
			_build_mg3(g)
		"m82a1":
			_build_m82a1(g)
		"l115":
			_build_l115(g)
		"sv98":
			_build_sv98(g)
		"m2010":
			_build_m2010(g)
		"sks":
			_build_sks(g)
		"m1a":
			_build_m1a(g)
		"g28":
			_build_g28(g)
		"mk14":
			_build_mk14(g)
		"m14":
			_build_m14(g)
		"ar10":
			_build_ar10(g)
		"fal":
			_build_fal(g)


## 各武器的握持锚点(枪械局部空间,左手贴合护木底部)
const HAND_ANCHORS := {
	"m4": { "r": [0.012, -0.1, 0.04], "l": [0, -0.03, -0.33] },
	"ak": { "r": [0.012, -0.1, 0.045], "l": [0, -0.03, -0.34] },
	"mp5": { "r": [0.012, -0.095, 0.035], "l": [0, -0.04, -0.26] },
	"m249": { "r": [0.012, -0.11, 0.055], "l": [0, -0.035, -0.44] },
	"awm": { "r": [0.012, -0.095, 0.065], "l": [0, -0.035, -0.28] },
	"m1014": { "r": [0.012, -0.1, 0.045], "l": [0, -0.052, -0.24] },
	"m1911": { "r": [0.012, -0.075, 0.055], "l": [-0.035, -0.068, 0.075] },
	"rpg": { "r": [0.012, -0.07, 0.115], "l": [0, -0.02, -0.32] },
	"gl": { "r": [0.012, -0.088, 0.055], "l": [0, -0.055, -0.26] },
	"scar": { "r": [0.012, -0.1, 0.04], "l": [0, -0.035, -0.34] },
	"aug": { "r": [0.012, -0.1, 0.07], "l": [0, -0.055, -0.17] },
	"ump": { "r": [0.012, -0.095, 0.035], "l": [0, -0.045, -0.22] },
	"p90": { "r": [0.012, -0.07, 0.1], "l": [0, -0.07, -0.14] },
	"pkm": { "r": [0.012, -0.11, 0.055], "l": [0, -0.035, -0.44] },
	"rpd": { "r": [0.012, -0.105, 0.045], "l": [0, -0.035, -0.4] },
	"m24": { "r": [0.012, -0.095, 0.065], "l": [0, -0.04, -0.28] },
	"svd": { "r": [0.012, -0.1, 0.045], "l": [0, -0.03, -0.35] },
	"g17": { "r": [0.012, -0.075, 0.055], "l": [-0.035, -0.068, 0.075] },
	"p226": { "r": [0.012, -0.075, 0.055], "l": [-0.035, -0.068, 0.075] },
	"deagle": { "r": [0.012, -0.08, 0.06], "l": [-0.04, -0.072, 0.08] },
	"m93r": { "r": [0.012, -0.075, 0.06], "l": [-0.03, -0.058, -0.08] },
	"spas12": { "r": [0.012, -0.1, 0.045], "l": [0, -0.055, -0.26] },
	# [8/10 武器扩充] 新枪握持锚点
	"g36c": { "r": [0.012, -0.1, 0.04], "l": [0, -0.035, -0.26] },
	"ak74": { "r": [0.012, -0.1, 0.045], "l": [0, -0.03, -0.32] },
	"famas": { "r": [0.012, -0.1, 0.08], "l": [0, -0.055, -0.16] },
	"vector": { "r": [0.012, -0.095, 0.035], "l": [0, -0.04, -0.2] },
	"pp19": { "r": [0.012, -0.09, 0.035], "l": [0, -0.13, -0.34] },
	"mg42": { "r": [0.012, -0.11, 0.055], "l": [0, -0.03, -0.38] },
	"m60": { "r": [0.012, -0.11, 0.045], "l": [0, -0.02, -0.42] },
	"m110": { "r": [0.012, -0.1, 0.035], "l": [0, -0.035, -0.4] },
	"m40": { "r": [0.012, -0.095, 0.065], "l": [0, -0.04, -0.28] },
	"g3": { "r": [0.012, -0.1, 0.04], "l": [0, -0.035, -0.32] },
	# [8/10 武器扩充 v2] 17 把新枪握持锚点
	"mpx": { "r": [0.012, -0.095, 0.035], "l": [0, -0.04, -0.26] },
	"mp7": { "r": [0.012, -0.09, 0.03], "l": [0, -0.05, -0.14] },
	"pp2000": { "r": [0.012, -0.095, 0.035], "l": [0, -0.05, -0.14] },
	"mk48": { "r": [0.012, -0.11, 0.055], "l": [0, -0.035, -0.34] },
	"negev": { "r": [0.012, -0.11, 0.055], "l": [0, -0.09, -0.26] },
	"mg3": { "r": [0.012, -0.11, 0.055], "l": [0, -0.03, -0.38] },
	"m82a1": { "r": [0.012, -0.11, 0.065], "l": [0, -0.04, -0.42] },
	"l115": { "r": [0.012, -0.095, 0.065], "l": [0, -0.04, -0.28] },
	"sv98": { "r": [0.012, -0.095, 0.065], "l": [0, -0.04, -0.28] },
	"m2010": { "r": [0.012, -0.095, 0.065], "l": [0, -0.04, -0.28] },
	"sks": { "r": [0.012, -0.1, 0.045], "l": [0, -0.035, -0.28] },
	"m1a": { "r": [0.012, -0.1, 0.045], "l": [0, -0.035, -0.26] },
	"g28": { "r": [0.012, -0.1, 0.035], "l": [0, -0.02, -0.38] },
	"mk14": { "r": [0.012, -0.1, 0.035], "l": [0, -0.02, -0.38] },
	"m14": { "r": [0.012, -0.1, 0.045], "l": [0, -0.035, -0.3] },
	"ar10": { "r": [0.012, -0.1, 0.035], "l": [0, -0.02, -0.36] },
	"fal": { "r": [0.012, -0.1, 0.045], "l": [0, -0.035, -0.24] },
	# [9/10] 泵动霰弹枪 / 左轮握持锚点(左手贴合护木/弹巢护板)
	"rem870": { "r": [0.012, -0.1, 0.045], "l": [0, -0.03, -0.34] },
	"m590": { "r": [0.012, -0.105, 0.045], "l": [0, -0.032, -0.37] },
	"win1897": { "r": [0.012, -0.1, 0.045], "l": [0, -0.03, -0.32] },
	"python": { "r": [0.012, -0.078, 0.055], "l": [-0.035, -0.058, 0.065] },
	"sw686": { "r": [0.012, -0.075, 0.055], "l": [-0.033, -0.056, 0.065] },
	"sw500": { "r": [0.012, -0.082, 0.06], "l": [-0.037, -0.06, 0.068] },
}

## 枪口 z 位置表
const MUZZLE_Z := {
	"m4": -0.8, "ak": -0.86, "mp5": -0.49, "m249": -0.905, "awm": -0.92, "m1014": -0.715,
	"m1911": -0.15, "rpg": -0.48, "gl": -0.42, "scar": -0.825, "aug": -0.66, "ump": -0.42, "p90": -0.34,
	"pkm": -0.93, "rpd": -0.9, "m24": -0.86, "svd": -0.84,
	"g17": -0.15, "p226": -0.155, "deagle": -0.27, "m93r": -0.24, "spas12": -0.735,
	# [8/10 武器扩充] 新枪枪口位置
	"g36c": -0.705, "ak74": -0.825, "famas": -0.71, "vector": -0.5, "pp19": -0.6,
	"mg42": -0.74, "m60": -0.76, "m110": -0.845, "m40": -0.74, "g3": -0.74,
	# [8/10 武器扩充 v2] 17 把新枪枪口位置
	"mpx": -0.68, "mp7": -0.48, "pp2000": -0.55, "mk48": -0.825, "negev": -0.86,
	"mg3": -0.74, "m82a1": -1.04, "l115": -0.9, "sv98": -0.84, "m2010": -0.92,
	"sks": -0.68, "m1a": -0.78, "g28": -0.78, "mk14": -0.84, "m14": -0.8,
	"ar10": -0.76, "fal": -0.78,
	# [9/10] 泵动霰弹枪 / 左轮:与重构后的真实枪管前端严格一致
	"rem870": -0.745, "m590": -0.795, "win1897": -0.715,
	"python": -0.44, "sw686": -0.39, "sw500": -0.5,
}
## 枪口 y 位置表:特效/枪口节点必须贴合各枪实际枪管轴线,不能全用默认 0.03
const MUZZLE_Y := {
	"m1014": 0.045, "spas12": 0.048, "rem870": 0.045, "m590": 0.047, "win1897": 0.046,
	"python": 0.033, "sw686": 0.032, "sw500": 0.034,
	"m1911": 0.033, "g17": 0.031, "p226": 0.034, "deagle": 0.04, "m93r": 0.031,
	# [10/10] 突击步枪批次:与重构后的枪管轴线一致
	"m4": 0.024, "ak": 0.028, "scar": 0.024, "aug": 0.026,
	"g36c": 0.024, "ak74": 0.028, "famas": 0.024, "g3": 0.024,
	# [10/10] 冲锋枪批次:与重构后的枪管轴线一致
	"mp5": 0.02, "ump": 0.022, "p90": 0.008, "vector": 0.02,
	"pp19": 0.024, "mpx": 0.024, "mp7": 0.018, "pp2000": 0.024,
	# [10/10] 轻机枪批次:与重构后的枪管轴线一致
	"m249": 0.028, "pkm": 0.028, "rpd": 0.026, "mg42": 0.024,
	"m60": 0.028, "mk48": 0.026, "negev": 0.026, "mg3": 0.024,
	# [10/10] 狙击/DMR批次:与重构后的枪管轴线一致
	"awm": 0.03, "m24": 0.028, "svd": 0.026, "m40": 0.028,
	"m82a1": 0.03, "l115": 0.028, "sv98": 0.028, "m2010": 0.028,
	"m110": 0.024, "sks": 0.026, "m1a": 0.026, "g28": 0.024,
	"mk14": 0.024, "m14": 0.026, "ar10": 0.024, "fal": 0.026,
}

## ============ 枪械改装件(程序化挂载) ============
## 各武器改装件挂载锚点(相对武器根;改装件原点即锚点,几何向 -Z/-Y/+Y 展开)
## muzzle:枪口部(改装件 0 点贴合枪口,向 -Z 延伸);mag:改装弹匣体中心基准(换算为 meta "mag" 子节点偏移)
## grip:枪管/护木下方中部;trigger:扳机护圈内;optic:机匣顶部导轨(改装光学时原瞄具隐藏)
const MOD_ANCHORS := {
	"m4": { "muzzle": Vector3(0, 0.024, -0.8), "mag": Vector3(0, -0.12, -0.09), "grip": Vector3(0, -0.012, -0.28), "trigger": Vector3(0, -0.06, 0.0), "optic": Vector3(0, 0.086, -0.1) },
	"ak": { "muzzle": Vector3(0, 0.028, -0.86), "mag": Vector3(0, -0.12, -0.1), "grip": Vector3(0, -0.014, -0.3), "trigger": Vector3(0, -0.06, 0.01), "optic": Vector3(0, 0.072, -0.05) },
	"scar": { "muzzle": Vector3(0, 0.024, -0.825), "mag": Vector3(0, -0.105, -0.1), "grip": Vector3(0, -0.014, -0.3), "trigger": Vector3(0, -0.062, 0.0), "optic": Vector3(0, 0.086, -0.1) },
	"aug": { "muzzle": Vector3(0, 0.026, -0.66), "mag": Vector3(0, -0.105, 0.16), "grip": Vector3(0, -0.01, -0.17), "trigger": Vector3(0, -0.06, -0.055), "optic": Vector3(0, 0.082, -0.05) },
	"mp5": { "muzzle": Vector3(0, 0.02, -0.5), "mag": Vector3(0, -0.125, -0.1), "grip": Vector3(0, -0.02, -0.26), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.055, -0.05) },
	"ump": { "muzzle": Vector3(0, 0.022, -0.42), "mag": Vector3(0, -0.115, -0.05), "grip": Vector3(0, -0.018, -0.22), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.072, -0.02) },
	"p90": { "muzzle": Vector3(0, 0.008, -0.34), "grip": Vector3(0, -0.04, -0.14), "trigger": Vector3(0, -0.055, 0.015), "optic": Vector3(0, 0.09, -0.12) },
	"m249": { "muzzle": Vector3(0, 0.028, -0.905), "grip": Vector3(0, -0.015, -0.44), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.11, -0.12) },
	"pkm": { "muzzle": Vector3(0, 0.028, -0.93), "grip": Vector3(0, -0.015, -0.44), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.105, -0.12) },
	"rpd": { "muzzle": Vector3(0, 0.026, -0.9), "grip": Vector3(0, -0.01, -0.4), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.095, -0.1) },
	"awm": { "muzzle": Vector3(0, 0.03, -0.9), "mag": Vector3(0, -0.125, -0.08), "grip": Vector3(0, -0.012, -0.5), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.088, -0.06) },
	"m24": { "muzzle": Vector3(0, 0.028, -0.83), "grip": Vector3(0, -0.012, -0.5), "trigger": Vector3(0, -0.06, 0.025), "optic": Vector3(0, 0.086, -0.06) },
	"svd": { "muzzle": Vector3(0, 0.026, -0.82), "mag": Vector3(0, -0.125, -0.1), "grip": Vector3(0, -0.012, -0.45), "trigger": Vector3(0, -0.06, 0.015), "optic": Vector3(0, 0.09, -0.02) },
	"m1014": { "muzzle": Vector3(0, 0.045, -0.715), "grip": Vector3(0, -0.03, -0.34), "trigger": Vector3(0, -0.06, 0.005), "optic": Vector3(0, 0.062, -0.04) },
	"spas12": { "muzzle": Vector3(0, 0.048, -0.735), "grip": Vector3(0, -0.03, -0.36), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.065, -0.05) },
	"rpg": { "muzzle": Vector3(0, 0.02, -0.4), "grip": Vector3(0, -0.07, -0.28), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.065, -0.1) },
	"gl": { "muzzle": Vector3(0, 0.012, -0.38), "grip": Vector3(0, -0.06, -0.22), "trigger": Vector3(0, -0.055, 0.0), "optic": Vector3(0, 0.075, -0.06) },
	"m1911": { "muzzle": Vector3(0, 0.033, -0.15), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.073, -0.03) },
	"g17": { "muzzle": Vector3(0, 0.031, -0.165), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.0685, -0.03) },
	"p226": { "muzzle": Vector3(0, 0.034, -0.17), "mag": Vector3(0, -0.13, 0.045), "grip": Vector3(0, -0.035, -0.05), "trigger": Vector3(0, -0.055, -0.005), "optic": Vector3(0, 0.0735, -0.03) },
	"deagle": { "muzzle": Vector3(0, 0.04, -0.27), "mag": Vector3(0, -0.145, 0.05), "grip": Vector3(0, -0.038, -0.06), "trigger": Vector3(0, -0.058, -0.005), "optic": Vector3(0, 0.0825, -0.05) },
	"m93r": { "muzzle": Vector3(0, 0.031, -0.24), "mag": Vector3(0, -0.145, 0.045), "grip": Vector3(0, -0.06, -0.1), "trigger": Vector3(0, -0.055, 0.005), "optic": Vector3(0, 0.07, -0.04) },
	# [8/10 武器扩充 v2] 17 把新枪改装锚点
	"mpx": { "muzzle": Vector3(0, 0.024, -0.68), "mag": Vector3(0, -0.12, -0.1), "grip": Vector3(0, -0.014, -0.26), "trigger": Vector3(0, -0.06, 0.0), "optic": Vector3(0, 0.086, -0.12) },
	"mp7": { "muzzle": Vector3(0, 0.018, -0.48), "mag": Vector3(0, -0.11, -0.1), "grip": Vector3(0, -0.015, -0.14), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.08, -0.1) },
	"pp2000": { "muzzle": Vector3(0, 0.024, -0.55), "mag": Vector3(0, -0.15, -0.08), "grip": Vector3(0, -0.015, -0.14), "trigger": Vector3(0, -0.06, 0.01), "optic": Vector3(0, 0.085, -0.1) },
	"mk48": { "muzzle": Vector3(0, 0.026, -0.825), "grip": Vector3(0, -0.015, -0.34), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.1, -0.12) },
	"negev": { "muzzle": Vector3(0, 0.026, -0.86), "grip": Vector3(0, -0.015, -0.26), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.098, -0.12) },
	"mg3": { "muzzle": Vector3(0, 0.024, -0.74), "grip": Vector3(0, -0.015, -0.38), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.095, -0.12) },
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
	"g36c": { "muzzle": Vector3(0, 0.024, -0.705), "grip": Vector3(0, -0.02, -0.24), "trigger": Vector3(0, -0.058, 0.0), "optic": Vector3(0, 0.082, 0.0) },
	"ak74": { "muzzle": Vector3(0, 0.028, -0.825), "grip": Vector3(0, -0.014, -0.3), "trigger": Vector3(0, -0.06, 0.01), "optic": Vector3(0, 0.072, -0.05) },
	"famas": { "muzzle": Vector3(0, 0.024, -0.71), "grip": Vector3(0, -0.035, -0.16), "trigger": Vector3(0, -0.058, -0.025), "optic": Vector3(0, 0.088, -0.05) },
	"vector": { "muzzle": Vector3(0, 0.02, -0.5), "grip": Vector3(0, -0.018, -0.16), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.086, -0.05) },
	"pp19": { "muzzle": Vector3(0, 0.024, -0.6), "grip": Vector3(0, -0.12, -0.34), "trigger": Vector3(0, -0.058, 0.0), "optic": Vector3(0, 0.075, -0.05) },
	"mg42": { "muzzle": Vector3(0, 0.024, -0.74), "grip": Vector3(0, -0.025, -0.38), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.078, 0.0) },
	"m60": { "muzzle": Vector3(0, 0.028, -0.76), "grip": Vector3(0, -0.024, -0.42), "trigger": Vector3(0, -0.065, 0.015), "optic": Vector3(0, 0.06, -0.18) },
	"m110": { "muzzle": Vector3(0, 0.024, -0.845), "grip": Vector3(0, -0.021, -0.42), "trigger": Vector3(0, -0.062, 0.005), "optic": Vector3(0, 0.086, -0.12) },
	"m40": { "muzzle": Vector3(0, 0.028, -0.74), "grip": Vector3(0, -0.024, -0.4), "trigger": Vector3(0, -0.036, 0.02), "optic": Vector3(0, 0.075, -0.14) },
	"g3": { "muzzle": Vector3(0, 0.024, -0.74), "grip": Vector3(0, -0.018, -0.28), "trigger": Vector3(0, -0.06, 0.01), "optic": Vector3(0, 0.086, -0.08) },
	# [9/10] 泵动霰弹枪 / 左轮改装锚点
	"rem870": { "muzzle": Vector3(0, 0.045, -0.745), "grip": Vector3(0, -0.02, -0.34), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.062, -0.04) },
	"m590": { "muzzle": Vector3(0, 0.047, -0.795), "grip": Vector3(0, -0.02, -0.37), "trigger": Vector3(0, -0.06, 0.005), "optic": Vector3(0, 0.065, -0.04) },
	"win1897": { "muzzle": Vector3(0, 0.046, -0.715), "grip": Vector3(0, -0.02, -0.32), "trigger": Vector3(0, -0.058, 0.005), "optic": Vector3(0, 0.064, -0.04) },
	"python": { "muzzle": Vector3(0, 0.033, -0.44), "grip": Vector3(0, -0.03, -0.08), "trigger": Vector3(0, -0.057, 0.0), "optic": Vector3(0, 0.093, -0.06) },
	"sw686": { "muzzle": Vector3(0, 0.032, -0.39), "grip": Vector3(0, -0.028, -0.08), "trigger": Vector3(0, -0.055, 0.0), "optic": Vector3(0, 0.091, -0.06) },
	"sw500": { "muzzle": Vector3(0, 0.034, -0.5), "grip": Vector3(0, -0.032, -0.08), "trigger": Vector3(0, -0.059, 0.0), "optic": Vector3(0, 0.096, -0.06) },
}

const MOUNT_DATA := {
	"ak": {"rail": {"y": 0.0694, "z0": -0.13, "z1": 0.04}, "hg": {"x": 0.026, "y0": -0.012, "y1": 0.07, "z0": -0.367, "z1": -0.188}, "recv": {"rear_z": 0.12, "y_mid": 0.012}},
	"ak74": {"rail": {"y": 0.0694, "z0": -0.13, "z1": 0.04}, "hg": {"x": 0.0255, "y0": -0.01, "y1": 0.068, "z0": -0.345, "z1": -0.195}, "recv": {"rear_z": 0.12, "y_mid": 0.012}},
	"ar10": {"rail": {"y": 0.086, "z0": -0.4, "z1": 0.01}, "hg": {"x": 0.023, "y0": 0.049, "y1": 0.075, "z0": -0.35, "z1": 0.03}, "recv": {"rear_z": 0.1, "y_mid": 0.016}},
	"aug": {"rail": {"y": 0.082, "z0": -0.28, "z1": 0.08}, "hg": {"x": 0.0147, "y0": -0.10685, "y1": -0.02761, "z0": -0.18986, "z1": -0.14117}, "recv": {"rear_z": 0.32, "y_mid": 0.022}},
	"awm": {"recv": {"rear_z": 0.16, "y_mid": 0.024}},
	"deagle": {"rail": {"y": 0.0684, "z0": -0.044, "z1": 0.004}},
	"fal": {"rail": {"y": 0.0824, "z0": -0.22, "z1": -0.06}, "recv": {"rear_z": 0.11, "y_mid": 0.016}},
	"famas": {"rail": {"y": 0.0934, "z0": -0.1, "z1": 0.02}, "hg": {"x": 0.0147, "y0": -0.09232, "y1": -0.02701, "z0": -0.17978, "z1": -0.13126}, "recv": {"rear_z": 0.28, "y_mid": 0.02}},
	"g17": {"rail": {"y": 0.0594, "z0": -0.032, "z1": 0.016}},
	"g28": {"rail": {"y": 0.086, "z0": -0.42, "z1": 0.02}, "hg": {"x": 0.023, "y0": 0.049, "y1": 0.075, "z0": -0.36, "z1": 0.04}, "recv": {"rear_z": 0.1, "y_mid": 0.016}},
	"g3": {"rail": {"y": 0.0674, "z0": -0.16, "z1": -0.07}, "hg": {"x": 0.024, "y0": -0.014, "y1": 0.038, "z0": -0.39, "z1": -0.17}, "recv": {"rear_z": 0.17, "y_mid": 0.014}},
	"g36c": {"rail": {"y": 0.082, "z0": -0.15, "z1": 0.04}, "hg": {"x": 0.025, "y0": -0.019, "y1": 0.031, "z0": -0.305, "z1": -0.175}, "recv": {"rear_z": 0.14, "y_mid": 0.014}},
	"gl": {"rail": {"y": 0.057, "z0": -0.312, "z1": -0.112}, "recv": {"rear_z": 0.095, "y_mid": -0.004}},
	"l115": {"recv": {"rear_z": 0.17, "y_mid": 0.024}},
	"m1014": {"rail": {"y": 0.0864, "z0": -0.14, "z1": 0.1}, "hg": {"x": 0.02236, "y0": 0.00375, "y1": 0.02375, "z0": -0.39, "z1": -0.19}},
	"m110": {"rail": {"y": 0.086, "z0": -0.44, "z1": 0.02}, "hg": {"x": 0.023, "y0": 0.049, "y1": 0.075, "z0": -0.44, "z1": 0.04}, "recv": {"rear_z": 0.11, "y_mid": 0.016}},
	"m14": {"rail": {"y": 0.0854, "z0": -0.2, "z1": -0.04}, "recv": {"rear_z": 0.11, "y_mid": 0.016}},
	"m1911": {"rail": {"y": 0.0644, "z0": -0.032, "z1": 0.016}},
	"m1a": {"rail": {"y": 0.0854, "z0": -0.2, "z1": -0.04}, "recv": {"rear_z": 0.11, "y_mid": 0.016}},
	"m2010": {"recv": {"rear_z": 0.16, "y_mid": 0.024}},
	"m24": {"recv": {"rear_z": 0.15, "y_mid": 0.024}},
	"m249": {"rail": {"y": 0.0774, "z0": -0.3, "z1": 0.12}, "hg": {"x": 0.028, "y0": -0, "y1": 0.066, "z0": -0.55, "z1": -0.29}, "recv": {"rear_z": 0.15, "y_mid": 0.02}},
	"m4": {"rail": {"y": 0.086, "z0": -0.1595, "z1": 0.0355}, "hg": {"x": 0.0252, "y0": -0.0012, "y1": 0.0492, "z0": -0.3975, "z1": -0.1625}, "recv": {"rear_z": 0.08, "y_mid": 0.047}},
	"m40": {"recv": {"rear_z": 0.155, "y_mid": 0.026}},
	"m590": {"rail": {"y": 0.0634, "z0": -0.105, "z1": 0.055}, "recv": {"rear_z": 0.13, "y_mid": 0.0195}},
	"m60": {"rail": {"y": 0.0679, "z0": -0.2, "z1": 0.14}, "recv": {"rear_z": 0.13, "y_mid": 0.018}},
	"m82a1": {"rail": {"y": 0.096, "z0": -0.28, "z1": 0.08}, "recv": {"rear_z": 0.22, "y_mid": 0.03}},
	"m93r": {"rail": {"y": 0.0599, "z0": -0.0388, "z1": 0.0092}},
	"mg3": {"recv": {"rear_z": 0.22, "y_mid": 0.018}},
	"mg42": {"rail": {"y": 0.0704, "z0": -0.18, "z1": 0.22}, "recv": {"rear_z": 0.22, "y_mid": 0.018}},
	"mk14": {"rail": {"y": 0.086, "z0": -0.44, "z1": 0.02}, "hg": {"x": 0.023, "y0": 0.048, "y1": 0.076, "z0": -0.43, "z1": 0.03}, "recv": {"rear_z": 0.11, "y_mid": 0.016}},
	"mk48": {"rail": {"y": 0.0704, "z0": -0.23, "z1": 0.15}, "recv": {"rear_z": 0.15, "y_mid": 0.018}},
	"mp5": {"rail": {"y": 0.0524, "z0": -0.14, "z1": 0.02}, "hg": {"x": 0.026, "y0": -0.014, "y1": 0.038, "z0": -0.335, "z1": -0.185}, "recv": {"rear_z": 0.12, "y_mid": 0.014}},
	"mp7": {"rail": {"y": 0.07, "z0": -0.28, "z1": 0.03}, "hg": {"x": 0.012, "y0": -0.07998, "y1": -0.01482, "z0": -0.15568, "z1": -0.1124}, "recv": {"rear_z": 0.08, "y_mid": 0.015}},
	"mpx": {"rail": {"y": 0.078, "z0": -0.34, "z1": 0.02}, "hg": {"x": 0.021, "y0": -0.015, "y1": 0.031, "z0": -0.335, "z1": -0.185}, "recv": {"rear_z": 0.05, "y_mid": 0.047}},
	"negev": {"rail": {"y": 0.086, "z0": -0.2, "z1": 0.1}, "hg": {"x": 0.01365, "y0": -0.09045, "y1": -0.01442, "z0": -0.27968, "z1": -0.22779}, "recv": {"rear_z": 0.16, "y_mid": 0.018}},
	"p226": {"rail": {"y": 0.0629, "z0": -0.032, "z1": 0.016}},
	"p90": {"rail": {"y": 0.078, "z0": -0.2, "z1": -0.04}, "hg": {"x": 0.017, "y0": -0.12298, "y1": -0.06603, "z0": -0.1596, "z1": -0.11047}, "recv": {"rear_z": 0.17, "y_mid": -0.005}},
	"pkm": {"rail": {"y": 0.0774, "z0": -0.29, "z1": 0.15}, "hg": {"x": 0.028, "y0": -0, "y1": 0.066, "z0": -0.56, "z1": -0.28}, "recv": {"rear_z": 0.17, "y_mid": 0.02}},
	"pp19": {"hg": {"x": 0.022, "y0": 0.037, "y1": 0.067, "z0": -0.345, "z1": -0.215}, "recv": {"rear_z": 0.1, "y_mid": 0.012}},
	"pp2000": {"rail": {"y": 0.08, "z0": -0.32, "z1": 0.04}, "hg": {"x": 0.017, "y0": -0.10415, "y1": -0.01481, "z0": -0.10499, "z1": -0.03346}, "recv": {"rear_z": 0.13, "y_mid": 0.014}},
	"rem870": {"rail": {"y": 0.0614, "z0": -0.1, "z1": 0.06}, "recv": {"rear_z": 0.12, "y_mid": 0.0195}},
	"rpd": {"rail": {"y": 0.0864, "z0": -0.26, "z1": 0.14}, "hg": {"x": 0.026, "y0": -0, "y1": 0.052, "z0": -0.53, "z1": -0.25}, "recv": {"rear_z": 0.14, "y_mid": 0.018}},
	"rpg": {"rail": {"y": 0.063, "z0": -0.27, "z1": 0.03}},
	"scar": {"rail": {"y": 0.086, "z0": -0.35, "z1": 0.03}, "hg": {"x": 0.023, "y0": -0.015, "y1": 0.021, "z0": -0.375, "z1": -0.225}, "recv": {"rear_z": 0.11, "y_mid": 0.048}},
	"sks": {"rail": {"y": 0.0804, "z0": -0.2, "z1": -0.04}, "recv": {"rear_z": 0.13, "y_mid": 0.016}},
	"spas12": {"rail": {"y": 0.0924, "z0": -0.14, "z1": 0.1}, "hg": {"x": 0.02322, "y0": 0.0055, "y1": 0.0255, "z0": -0.39, "z1": -0.19}},
	"sv98": {"recv": {"rear_z": 0.16, "y_mid": 0.024}},
	"svd": {"recv": {"rear_z": 0.16, "y_mid": 0.024}},
	"sw500": {"rail": {"y": 0.062, "z0": -0.478, "z1": -0.16}},
	"ump": {"rail": {"y": 0.072, "z0": -0.2, "z1": 0.04}, "hg": {"x": 0.023, "y0": -0.02, "y1": 0.03, "z0": -0.28, "z1": -0.16}, "recv": {"rear_z": 0.11, "y_mid": 0.012}},
	"vector": {"rail": {"y": 0.076, "z0": -0.3, "z1": 0.02}, "hg": {"x": 0.01365, "y0": -0.08228, "y1": -0.01652, "z0": -0.17715, "z1": -0.13093}, "recv": {"rear_z": 0.04, "y_mid": 0.032}},
	"win1897": {"rail": {"y": 0.0649, "z0": -0.105, "z1": 0.055}, "recv": {"rear_z": 0.11, "y_mid": 0.0215}},
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
	# 机匣接板:锚点=机匣后端面(MOUNT_DATA recv),接板跨在端面上视觉焊死
	s.add_child(box(0.034, 0.058, 0.026, 0, 0.004, 0.010, "metal"))
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


## 战术镭射/手电/红外:全部侧面夹箍安装 —— 贴板 + 前后箍带 + 筒体朝前,
## 锚点 = 护木侧面中点(_apply_mods 按 MOUNT_DATA 护木数据推算)
static func build_mod_laser(mod_id: String) -> Node3D:
	mod_id = _MOD_ALIAS.get(mod_id, mod_id)
	var l := Node3D.new()
	l.name = "ModLaser_" + mod_id
	match mod_id:
		"laser_tac":
			l.add_child(box(0.006, 0.026, 0.055, -0.003, 0, -0.012, "dark"))     # 侧贴夹座
			l.add_child(box(0.004, 0.034, 0.014, -0.003, 0, 0.014, "metal"))     # 前箍带
			l.add_child(box(0.004, 0.034, 0.014, -0.003, 0, -0.038, "metal"))    # 后箍带
			l.add_child(cyl(0.009, 0.009, 0.075, 0.013, 0, -0.048, "dark"))      # 镭射管(朝前)
			l.add_child(cyl(0.011, 0.011, 0.012, 0.013, 0, -0.010, "metal"))     # 管尾座
			l.add_child(box(0.006, 0.006, 0.006, 0.013, 0, -0.090, "red_glow"))  # 发射窗(红)
		"laser_flash":
			l.add_child(box(0.006, 0.028, 0.055, -0.003, 0, -0.012, "dark"))     # 侧贴夹座
			l.add_child(box(0.004, 0.036, 0.014, -0.003, 0, 0.014, "metal"))     # 前箍带
			l.add_child(box(0.004, 0.036, 0.014, -0.003, 0, -0.038, "metal"))    # 后箍带
			l.add_child(cyl(0.014, 0.014, 0.062, 0.017, 0, -0.042, "dark"))      # 手电筒身
			l.add_child(cyl(0.017, 0.014, 0.018, 0.017, 0, -0.080, "chrome"))    # 灯头
			l.add_child(cyl(0.0105, 0.0105, 0.004, 0.017, 0, -0.090, "red_glow"))  # 灯面(发光)
			l.add_child(box(0.004, 0.014, 0.008, 0.026, 0.010, -0.010, "dark"))  # 侧开关
		"laser_ir":
			l.add_child(box(0.006, 0.024, 0.055, -0.003, 0, -0.012, "dark"))     # 侧贴夹座
			l.add_child(box(0.004, 0.032, 0.014, -0.003, 0, 0.014, "metal"))
			l.add_child(box(0.004, 0.032, 0.014, -0.003, 0, -0.038, "metal"))
			l.add_child(cyl(0.007, 0.008, 0.062, 0.012, 0, -0.045, "dark"))      # 细镭射管
			l.add_child(cyl(0.010, 0.010, 0.010, 0.012, 0, -0.010, "metal"))
			l.add_child(box(0.005, 0.005, 0.005, 0.012, 0, -0.078, "green_glow"))  # 发射窗(绿)
	return l


## 计算改装弹匣体相对 meta "mag" 节点的偏移(保证弹匣体顶部与原弹匣顶/弹匣口对齐)
static func _mag_body(base: Node3D, h_extra: float, w_scale: float) -> Dictionary:
	# 取弹匣网格真实 AABB(GLB 弹匣是 ArrayMesh 且节点原点在网格中心;
	# 旧公式假设"节点原点=弹匣顶",加长体顶部沉到原点以下 → 与枪身脱开)。
	var top := 0.075
	var bottom := -0.075
	var w := 0.042
	var d := 0.055
	if base is MeshInstance3D and (base as MeshInstance3D).mesh != null:
		var ab := (base as MeshInstance3D).mesh.get_aabb()
		top = ab.position.y + ab.size.y
		bottom = ab.position.y
		w = ab.size.x
		d = ab.size.z
	else:
		for c in base.get_children():
			if c is MeshInstance3D and c.mesh != null:
				var ab2 := (c as MeshInstance3D).mesh.get_aabb()
				top = maxf(top, c.position.y + ab2.position.y + ab2.size.y)
				bottom = minf(bottom, c.position.y + ab2.position.y)
				w = maxf(w, ab2.size.x)
				d = maxf(d, ab2.size.z)
	var h := (top - bottom) + h_extra
	# 顶对齐:改装弹匣顶与原弹匣顶同高,向下加长 h_extra
	var center := top - h * 0.5
	return { "w": maxf(w * w_scale, 0.03), "d": maxf(d, 0.05), "h": h, "c": center }


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
			# 弹鼓:盘面垂直枪身(鼓轴沿前后方向,圆面朝枪口/枪尾,与 RPD 弹鼓同向);
			# 旧版鼓轴沿左右 = 盘面与枪身平行,实拍被否。
			# 颈部从鼓顶伸进弹匣井(y 到 +0.06,已越过弹匣顶进入机匣)与枪身焊死。
			base.add_child(box(0.034, 0.10, 0.052, 0, 0.010, 0, "dark"))                  # 颈部(伸入弹匣井)
			base.add_child(cyl(0.062, 0.062, 0.055, 0, -0.075, 0, "dark", "z"))           # 鼓盘(面朝前后)
			base.add_child(cyl(0.058, 0.058, 0.010, 0, -0.075, -0.030, "metal", "z"))     # 前盖环
			base.add_child(cyl(0.058, 0.058, 0.010, 0, -0.075, 0.030, "metal", "z"))      # 后盖环
			base.add_child(cyl(0.014, 0.014, 0.072, 0, -0.075, 0, "metal", "z"))          # 中心轴头
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
static func build_mod_optic(mod_id: String, rail_local := 0.0) -> Node3D:
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
			o.add_child(box(0.008, 0.009, 0.008, 0, 0.021, 0.005, "dark"))     # 调节钮(坐在遮阳罩上)
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
			o.add_child(box(0.006, 0.013, 0.012, 0, 0.021, 0, "dark"))         # 顶钮(坐在顶梁上)
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
			o.add_child(box(0.01, 0.011, 0.01, 0, 0.0265, 0.004, "dark"))        # 调节钮(坐在遮阳顶上)
			var drd := MeshInstance3D.new()
			var drdp := PlaneMesh.new()
			drdp.size = Vector2(0.0013, 0.0013)
			drd.mesh = drdp
			drd.material_override = rm
			drd.position = Vector3(0, 0, -0.038)
			drd.name = "RetDot"
			o.add_child(drd)
		"opt_2x":
			# 2 倍战术镜:空芯镜筒 + 空心镜环(两端 open)—— 开镜视线从膛内穿过,
			# 实心筒会把整个视野堵死(实拍实锤)。十字分划在镜腔中段。
			o.add_child(box(0.02, 0.008, 0.04, 0, -0.012, -0.02, "dark"))       # 底座
			o.add_child(cyl_open(0.0125, 0.0125, 0.1, 0, 0, -0.055, "dark"))    # 镜筒(空芯)
			o.add_child(cyl_open(0.0135, 0.0135, 0.007, 0, 0, -0.004, "metal")) # 目镜环(空心)
			o.add_child(cyl_open(0.0155, 0.0155, 0.009, 0, 0, -0.105, "metal")) # 物镜环(空心)
			o.add_child(cyl(0.011, 0.011, 0.003, 0, 0, -0.004, "lens_clear"))   # 目镜片(透明)
			o.add_child(cyl(0.013, 0.013, 0.003, 0, 0, -0.11, "lens_clear"))    # 物镜片(透明)
			o.add_child(box(0.006, 0.012, 0.01, 0, 0.015, -0.06, "dark"))       # 倍率钮(坐筒顶)
			# 十字分划:显式横/竖短臂(各 12mm)+ 中心点 —— 旧版竖臂贯穿整个
			# 视野且旋转叠加后横臂不可见,只剩一条怪异红竖线(实拍实锤)
			o.add_child(box(0.012, 0.0006, 0.0006, 0, 0, -0.055, "red_glow"))  # 横臂
			o.add_child(box(0.0006, 0.012, 0.0006, 0, 0, -0.055, "red_glow"))  # 竖臂
			var cdot := box(0.0016, 0.0016, 0.0006, 0, 0, -0.055, "red_glow")
			cdot.name = "RetDot"
			o.add_child(cdot)
		"opt_1xprism":
			# 1 倍棱镜:紧凑筒 + 小分划点
			o.add_child(box(0.016, 0.007, 0.026, 0, -0.012, -0.012, "dark"))    # 底座
			o.add_child(cyl_open(0.0105, 0.0105, 0.05, 0, 0, -0.028, "dark"))   # 镜筒(空芯)
			o.add_child(cyl_open(0.0115, 0.0115, 0.005, 0, 0, -0.004, "metal")) # 目镜环(空心)
			o.add_child(cyl_open(0.0125, 0.0125, 0.006, 0, 0, -0.056, "metal")) # 物镜环(空心)
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
	# ---- 皮卡汀尼夹座:底面精确落在导轨齿顶平面上(局部高 rail_local,负值) ----
	# 落差 = 视轴高 - 齿顶高。升高柱把镜体从齿顶举到视轴,侧夹板 + 锁紧
	# 螺钮可见,底面与导轨齿零间隙贴合 —— 不悬空、不穿轨。
	if rail_local < -0.004:
		var drop := -rail_local
		if drop > 0.016:
			# 标准夹座:升高柱从齿顶举到镜体底缘,横贯锁紧钮远在视轴下方
			var top := -0.014
			var col_h := drop - 0.014
			if col_h > 0.002:
				o.add_child(box(0.026, col_h, 0.052, 0, top - col_h * 0.5, -0.012, "metal"))
				o.add_child(box(0.005, col_h, 0.058, -0.016, top - col_h * 0.5, -0.012, "dark"))
				o.add_child(box(0.005, col_h, 0.058, 0.016, top - col_h * 0.5, -0.012, "dark"))
			o.add_child(cyl(0.005, 0.005, 0.044, 0, -drop + 0.006, 0.008, "chrome", "x"))
		else:
			# 低 Profile(手枪套筒板等):齿顶离视轴近,镜底微沉入轨座属正常贴装;
			# 锁紧螺钉只从两侧露出,绝不横穿视轴
			o.add_child(cyl(0.003, 0.003, 0.012, 0.0155, -drop * 0.5, -0.012, "chrome", "x"))
			o.add_child(cyl(0.003, 0.003, 0.012, -0.0155, -drop * 0.5, -0.012, "chrome", "x"))
	return o


## 运行时 optic 锚点:视轴线 y = def.sight_y;目镜 z 依 ADS 相机位置推算
## gun.gd 满开镜时武器根置于相机 (0, -sight_y, ads_z),即相机位于武器局部 (0, sight_y, -ads_z);
## 目镜置于相机前方 0.12 m(≈ 枪身中后段导轨),贴目且不穿视点
## WeaponsData 未就绪(菜单未初始化等)时回退静态 MOD_ANCHORS 值,保持稳健
static func _optic_anchor(id: String, fallback: Vector3) -> Vector3:
	var wd: Dictionary = WeaponsData.W()
	var d = wd.get(id, null)
	if d == null:
		return fallback
	# 目镜贴目:相机(武器局部 z=-ads_z)前方 0.12m,再夹进导轨跨度
	var z: float = -float(d.ads_z) - 0.12
	if id == "p90":
		z = -0.12
	return Vector3(0.0, float(d.sight_y), _clamp_rail_z(id, z, fallback))


## 把 optic 锚点 z 夹进该枪导轨跨度内(镜体必须落在导轨上,不许悬出轨外)
static func _clamp_rail_z(id: String, z: float, fallback: Vector3) -> float:
	var md: Dictionary = MOUNT_DATA.get(id, {})
	var rail: Dictionary = md.get("rail", {})
	if rail.is_empty():
		return fallback.z
	return clampf(z, float(rail.z0) + 0.04, float(rail.z1) - 0.03)


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
					# 机匣后端面(安装数据;无数据回落旧推导)
					var md6: Dictionary = MOUNT_DATA.get(id, {})
					var rv6: Dictionary = md6.get("recv", {})
					if not rv6.is_empty():
						a = Vector3(0, float(rv6.y_mid), float(rv6.rear_z))
					else:
						var bt: Vector3 = anchors.get("trigger", Vector3(0, -0.06, 0.0))
						a = bt + Vector3(0, 0.05, 0.22)
				"laser":
					# 护木侧面夹箍侧挂(安装数据优先:护木半宽/高度/跨度)
					var md4: Dictionary = MOUNT_DATA.get(id, {})
					var hg4: Dictionary = md4.get("hg", {})
					if not hg4.is_empty():
						var gz0: float = anchors.get("grip", Vector3(0, 0, -0.3)).z
						var lz := clampf(gz0, float(hg4.z0) + 0.06, float(hg4.z1) - 0.05)
						a = Vector3(float(hg4.x) + 0.004, (float(hg4.y0) + float(hg4.y1)) * 0.5, lz)
					else:
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
				var md5: Dictionary = MOUNT_DATA.get(id, {})
				var hg5: Dictionary = md5.get("hg", {})
				if not hg5.is_empty():
					# 前握把落在护木底缘正下方(顶安装板包住底缘,z 夹进护木跨度)
					var gz := clampf(a.z, float(hg5.z0) + 0.05, float(hg5.z1) - 0.05)
					a = Vector3(0, float(hg5.y0) + 0.004, gz)
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
				var optic_anchor := _optic_anchor(id, a)
				# 夹座落差 = 该枪导轨齿顶绝对高 - 视轴高(局部负值),无轨枪回落 0
				var rail_local := 0.0
				var mdl: Dictionary = MOUNT_DATA.get(id, {})
				var rl: Dictionary = mdl.get("rail", {})
				if not rl.is_empty():
					rail_local = float(rl.y) - optic_anchor.y
				var op := build_mod_optic(mod_id, rail_local)
				op.position = optic_anchor
				g.add_child(op)


## 圆头关节球(手模指节用;独立函数避免污染通用 mesh 缓存语义)
static func _hand_ball(r: float, x: float, y: float, z: float, mat_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _part_material(mat_name)
	mi.position = Vector3(x, y, z)
	return mi


## 第一人称手模(战术手套 v2)
## 旧版 15 个直角盒子,方块指在第一人称占满下三分之一屏幕,"积木手"非常显眼。
## v2:手掌倒角盒(皮革边缘高光) + 锥形圆柱指节(由粗到细自然收窄) + 关节球 +
## 圆指尖,手套质感由倒角边缘光与圆柱高光带出来。
## 节点结构(finger→seg2→seg3 的关节树)与旧版完全一致 —— 手指关节动画挂点、
## _optimize_hand 的分层合并、HAND_ANCHORS 全部不受影响。
static func build_hand(is_left: bool) -> Node3D:
	var g := Node3D.new()
	if not _mat.has("glove"):
		_mat["glove"] = _std(Color.html("#6a5a42"), 0.85, 0.0)
	if not _mat.has("glove_knuckle"):
		_mat["glove_knuckle"] = _std(Color.html("#514735"), 0.9, 0.0)
	# 手掌:三块倒角盒(主掌/手背护片/掌根),倒角 4~5mm 出皮革高光边
	g.add_child(WeaponParts.bevel_box(0.058, 0.052, 0.085, 0, 0, 0, _part_material("glove"), 0.005))
	g.add_child(WeaponParts.bevel_box(0.052, 0.012, 0.045, 0, 0.022, -0.03, _part_material("glove_knuckle"), 0.004))
	g.add_child(WeaponParts.bevel_box(0.058, 0.054, 0.032, 0, 0, 0.052, _part_material("glove"), 0.005))
	# 掌前缘指根隆起:一条横向圆棱,衔接手掌与四指,消除"手指从方块里长出来"的断裂感
	g.add_child(cyl(0.0075, 0.0075, 0.052, 0, -0.004, -0.050, "glove", "x"))
	# 四指:每指三节。锥形圆柱(r1 近端粗 → r2 远端细)+ 节间关节球 + 圆指尖;
	# 弯曲角较旧版略加深(-0.34/-0.52/-0.58),扣握把/护木的"包握感"更强。
	for i in 4:
		var finger := Node3D.new()
		finger.position = Vector3((i - 1.5) * 0.0135, -0.006, -0.058)
		finger.rotation.x = -0.34
		# 近节
		finger.add_child(cyl(0.0062, 0.0054, 0.030, 0, -0.003, -0.013, "glove", "z"))
		var seg2 := Node3D.new()
		seg2.position = Vector3(0, -0.006, -0.027)
		seg2.rotation.x = -0.52
		# 近节远端关节球(衔接 seg2,遮住锥台断口)
		seg2.add_child(_hand_ball(0.0056, 0, -0.004, -0.002, "glove_knuckle"))
		# 中节
		seg2.add_child(cyl(0.0052, 0.0046, 0.026, 0, -0.004, -0.011, "glove", "z"))
		var seg3 := Node3D.new()
		seg3.position = Vector3(0, -0.008, -0.024)
		seg3.rotation.x = -0.58
		seg3.add_child(_hand_ball(0.0048, 0, -0.003, -0.001, "glove_knuckle"))
		# 末节 + 圆指尖
		seg3.add_child(cyl(0.0044, 0.0028, 0.020, 0, -0.003, -0.008, "glove_knuckle", "z"))
		seg3.add_child(_hand_ball(0.0032, 0, -0.003, -0.018, "glove_knuckle"))
		seg2.add_child(seg3)
		finger.add_child(_hand_ball(0.0058, 0, -0.002, 0.001, "glove_knuckle"))
		g.add_child(finger)
	# 拇指:双节锥柱 + 关节球,握把时自然包向食指侧
	var thumb := Node3D.new()
	thumb.position = Vector3(0.03 if is_left else -0.03, -0.002, -0.038)
	thumb.rotation = Vector3(-0.2, 0.55 if is_left else -0.55, 0.1)
	thumb.add_child(cyl(0.0080, 0.0068, 0.035, 0, 0, -0.014, "glove", "z"))
	var thumb_tip := Node3D.new()
	thumb_tip.position = Vector3(0, 0.002, -0.032)
	thumb_tip.rotation.x = -0.5
	thumb_tip.add_child(_hand_ball(0.0070, 0, 0, 0.001, "glove_knuckle"))
	thumb_tip.add_child(cyl(0.0066, 0.0046, 0.022, 0, -0.002, -0.009, "glove_knuckle", "z"))
	thumb_tip.add_child(_hand_ball(0.0042, 0, -0.002, -0.020, "glove_knuckle"))
	thumb.add_child(thumb_tip)
	g.add_child(thumb)
	return g


## 第一人称前臂(战术服):单位长度臂筒(z 轴 1m),运行时按腕部-肘锚点定向缩放
static func build_forearm() -> Node3D:
	# 士兵风格前臂(视觉对齐骨骼士兵手臂):锥形筒腕细肘粗 + 袖口环 + 肘端收圆。
	# 臂筒原点 = 腕部,+z 指向后下方(肘向);挂载时旋转把 +z 转向"后下方"即指向身体。
	# 节点结构与旧版一致(单容器),gun.gd 腕→肘屏外锚点定向算法不受影响。
	var g := Node3D.new()
	if not _mat.has("sleeve"):
		_mat["sleeve"] = _std(Color.html("#4a5548"), 0.9, 0.0)
	if not _mat.has("sleeve_cuff"):
		_mat["sleeve_cuff"] = _std(Color.html("#39413a"), 0.85, 0.0)
	# 锥形主筒:腕端(top=-z)细 0.030 → 肘端(bottom=+z)粗 0.044,长 0.36(前臂解剖比例;
	# 旧 0.55 超长戳穿地面/躯干 —— 用户实测穿模,勿回长)
	g.add_child(cyl(0.030, 0.044, 0.36, 0, 0, 0.18, "sleeve"))
	# 袖口环(腕后加深色环,袖子收口)
	g.add_child(cyl(0.037, 0.037, 0.06, 0, 0, 0.08, "sleeve_cuff"))
	# 肘端收圆(锥形盖帽,避免平头截面)
	g.add_child(cyl(0.042, 0.012, 0.05, 0, 0, 0.385, "sleeve"))
	return g


## ============ 近战小刀(程序化:棱形刀身 + 黑柄,单手右握) ============
## 原点位于护手处,刀尖朝 -Z;结构参考 build() 的 group 约定(meta: muzzle/right_hand/right_arm)
static func build_knife() -> Node3D:
	_current_weapon = ""
	_current_part_idx = 0
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
	right_arm.position = right_hand.position + Vector3(0, -0.012, 0.035)
	right_arm.rotation = Vector3(1.18, 0.30, 0)   # 68° 下压 + 缩短后不至于悬空截断
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
static func _mergeable_collect(g: Node3D, out: Array[MeshInstance3D], skip: Dictionary) -> void:
	for c in g.get_children():
		if skip.has(c):
			continue
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.name != "RetDot" and mi.name != "RetRing" and mi.name != "RetCross":
				out.append(mi)
		elif c is Node3D:
			# skip 必须从顶层一路传下去:可动件可能挂在任意深度(例如 GLB 自带根节点时,
			# mag/bolt 是根节点的孙节点)。早先的写法每层重新按"直接子节点"算一遍,
			# 结果深层可动件会被当成静态件合并掉并 free —— 换弹时拿到的就是个野对象。
			_mergeable_collect(c, out, skip)


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
	# 跳过集合只在顶层算一次,再沿递归传下去
	var skip: Dictionary = {}
	for key in g.get_meta_list():
		var n = g.get_meta(key)
		if n is Node:
			skip[n] = true
	for nm in ["StockIrons", "StockOptic", "StockTrigger"]:
		# 必须递归找:GLB 模型自带根节点时,这些件是孙节点而不是 g 的直接子节点。
		# 用 get_node_or_null 会漏掉它们,导致原厂机械瞄具被并进 MergedStatic ——
		# 后果是装备红点镜后照门藏不掉(gun.gd 按名字找它),直接在镜筒里穿模。
		var n = _find_node_named(g, nm)
		if n != null:
			skip[n] = true
	var meshes: Array[MeshInstance3D] = []
	_mergeable_collect(g, meshes, skip)
	_merge_list(g, meshes)


## [PERF] 只合并 g 的直接子节点里的静态 mesh,不递归进 Node3D 子树。
## 用于手部:手掌的几块合成一块,但手指节点必须整根保留 —— 它们是将来做
## 「松开/扣紧」手指关节动画的挂点,整只手糊成一坨就没法再动了。
static func _merge_direct(g: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	for c in g.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			meshes.append(c as MeshInstance3D)
	_merge_list(g, meshes)


## [PERF] 手部层级合并:手掌合成一块,每根手指内部的三节合成一块(手指节点本身保留)。
## 手部是 draw call 大户 —— 两只手 + 前臂在合并前能占到整枪的七成以上。
static func _optimize_hand(hand: Node3D) -> void:
	if hand == null:
		return
	_merge_direct(hand)
	for c in hand.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			_merge_static(c as Node3D)


## 合并核心:把给定 mesh 列表按材质分组,烘焙到 g 下的单个 MergedStatic 节点。
static func _merge_list(g: Node3D, meshes: Array[MeshInstance3D]) -> void:
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


## ==================== Blender 高精度模型接入 ====================
## 由 tools/blender/build_*.py 生成。相比 GDScript 图元拼接,GLB 路径能拿到真实的
## 布尔挖切(抛壳窗/弹匣井)、倒角边缘与皮卡汀尼齿距,且每个零件是独立命名节点。

const GLB_DIR := "res://models/weapons/"
## 可动件语义名:Blender 侧用这些名字命名对象,Godot 侧按名字绑定 meta,
## 换弹控制器(weapon_reload_controller.gd)就靠 meta 找到它们。
const _GLB_ANIM_PARTS: Array[String] = ["mag", "bolt", "slide", "pump", "cover",
	"belt", "rocket", "breech"]
## GLB 实物名 → 控制器语义名的别名表(机枪供弹机构专用,详见 _build_from_glb)
const _GLB_NAME_ALIAS := {
	"FeedCover": "cover",
	"CoverLatch": "cover_latch",
	"FeedPort": "feed_port",
	"BeltTail": "belt",
	"MagFollower": "mag_follower",
	"Slide": "slide",   # 手枪套筒(实物名首字母大写,meta 语义名小写)
	"PumpForend": "pump",      # 泵动霰弹护木
	"EjectShell": "eject_shell",   # 抛壳演示弹
	"LoadPort": "load_port",   # 装填口参考点(空对象)
	"Breech": "breech",   # M320 中折膛体
}


static func _has_glb(id: String) -> bool:
	return ResourceLoader.exists(GLB_DIR + id + ".glb")


## 外部接口(BR 物资系统):地面武器实体用真枪 GLB
static func has_glb(id: String) -> bool:
	return _has_glb(id)


static func build_from_glb(id: String, g: Node3D) -> bool:
	return _build_from_glb(id, g)


## 把 GLB 挂到武器根节点下,映射材质并绑定可动件。失败返回 false,由调用方回退程序化建模。
static func _build_from_glb(id: String, g: Node3D) -> bool:
	if not _has_glb(id):
		return false
	var ps: PackedScene = load(GLB_DIR + id + ".glb")
	if ps == null:
		push_warning("[WeaponModels] GLB 加载失败,回退程序化建模: " + id)
		return false
	var inst := ps.instantiate()
	# 保留 GLB 自身根节点,避免丢失导入时的根变换
	g.add_child(inst)
	_remap_glb_materials(g)
	for k in _GLB_ANIM_PARTS:
		var n := _find_node_named(g, k)
		if n != null:
			g.set_meta(k, n)
	# Blender 侧零件用实物名(FeedCover/BeltTail...),meta 用控制器语义名(cover/belt...),
	# 这里做别名映射。教训:语义名查不到 ≠ 零件不存在,是两边命名没对齐 ——
	# meta 落空时控制器静默跳过,开盖/弹链动画整个消失(实机验证抓出的 bug)。
	for glb_name in _GLB_NAME_ALIAS:
		var na := _find_node_named(g, glb_name)
		if na != null:
			g.set_meta(_GLB_NAME_ALIAS[glb_name], na)
	# 狙击镜 PIP 契约(与 GDScript 版 _scope 完全同构):
	# StockOptic → ScopeEye(PIP 相机挂点) → ScopeLensBlack/Clear + RetCross。
	# GLB 路径的 StockOptic 已被 _hoist_to_root 提升,ScopeEye 父子链随组保留,
	# scope_sight() 的树内检查才能通过 —— 开镜才有镜内放大画面。
	var scope_optic := _find_node_named(g, "StockOptic")
	if scope_optic != null:
		var eye := _find_node_named(g, "ScopeEye")
		if eye != null:
			g.set_meta("scope_eye", eye)
			g.set_meta("scope_eye_radius", 0.028)
		var tube := _find_node_named(g, "ScopeTubeBody")
		if tube != null:
			g.set_meta("scope_tube", tube)
		var lens_b := _find_node_named(g, "ScopeLensBlack")
		if lens_b != null:
			g.set_meta("scope_lens_black", lens_b)
		var lens_c := _find_node_named(g, "ScopeLensClear")
		if lens_c != null:
			lens_c.visible = false
			g.set_meta("scope_lens_clear", lens_c)
		var ret := _find_node_named(g, "RetCross")
		if ret != null:
			ret.visible = false
			g.set_meta("scope_reticle", ret)
	# 左轮手枪契约(与 GDScript 版 _revolver 完全同构):
	# crane(摆出铰链) → cylinder(弹巢) → ChamberShell_N(逐膛弹壳) + hammer(击锤)。
	# 弹壳数组按 _N 索引排序,与膛位显隐逻辑一一对应。
	var crane := _find_node_named(g, "RevolverCrane")
	if crane != null:
		g.set_meta("crane", crane)
		var cylinder := _find_node_named(g, "RevolverCylinder")
		if cylinder != null:
			g.set_meta("cylinder", cylinder)
			var shells: Array = []
			for i in 12:
				var sh := _find_node_named(g, "ChamberShell_%d" % i)
				if sh != null:
					shells.append(sh)
			if not shells.is_empty():
				g.set_meta("chamber_shells", shells)
	var hammer := _find_node_named(g, "RevolverHammer")
	if hammer != null:
		g.set_meta("hammer", hammer)
	# RPG 的 CLU 制导镜:ScopeEye 独立于 StockOptic(侧置 CLU 结构),
	# 方形目镜框在 ADS 时保留显示作为 PIP 取景框(gun.gd 按 id=="rpg" 特判)。
	var clu := _find_node_named(g, "ScopeCLU")
	if clu != null:
		g.set_meta("scope_clu", clu)
		var rpg_eye := _find_node_named(g, "ScopeEye")
		if rpg_eye != null:
			g.set_meta("scope_eye", rpg_eye)
			g.set_meta("scope_eye_radius", 0.030)
		var rpg_frame := _find_node_named(g, "ScopeTubeBody")
		if rpg_frame != null:
			g.set_meta("scope_tube", rpg_frame)
	# 把"可被运行时隐藏"的件提到武器根节点下。
	# 原因:gun.gd / 配件系统在 g 上按名字直接 get_node_or_null("StockIrons"),
	# 而 GLB 自带一层根节点,这些件实际上是孙节点,直接查会漏 —— 装备红点镜后
	# 原厂照门就藏不掉,直接穿模。提升后保持世界变换,等价于原位不动。
	for hn in ["StockIrons", "StockOptic", "StockTrigger"]:
		_hoist_to_root(g, inst, hn)
	return true


## 把 inst 下名为 name 的节点重挂到 g 下,保持其相对 g 的累积变换不变。
static func _hoist_to_root(g: Node3D, inst: Node, name: String) -> void:
	var n := _find_node_named(inst, name)
	if n == null or not (n is Node3D):
		return
	if n.get_parent() == g:
		return
	var t := _rel_transform(g, n as Node3D)
	var p := n.get_parent()
	if p != null:
		p.remove_child(n)
	n.owner = null   # 从 GLB 场景摘出时清 owner,否则 add_child 触发 owner 不一致告警
	g.add_child(n)
	(n as Node3D).transform = t


## GLB 自带材质的名字就是项目材质族名(metal/dark/poly...),换成 _part_material 的变体,
## 这样高精度模型同样享受"同枪不同部件有轻微色差/粗糙度差"的表面层次。
static func _remap_glb_materials(g: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_mi(g, meshes)
	for mi in meshes:
		var mname := ""
		for s in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(s)
			if sm != null and not sm.resource_name.is_empty():
				mname = sm.resource_name
				break
		if mname.is_empty() or not MAT().has(mname):
			mname = "metal"
		mi.material_override = _part_material(mname)


static func _collect_mi(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_mi(c, out)


static func _find_node_named(n: Node, target: String) -> Node:
	if n.name == target:
		return n
	for c in n.get_children():
		var r := _find_node_named(c, target)
		if r != null:
			return r
	return null


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
##
## 建模来源优先级:
##   1. models/weapons/<id>.glb —— Blender 高精度模型(tools/blender/ 生成),零件带倒角、
##      抛壳窗/弹匣井是真布尔挖出来的,可动件按语义名暴露给换弹控制器。
##   2. 没有 GLB 时回退到 GDScript 程序化建模(_build),保证渐进替换期间不会开天窗。
static func build(id: String, with_hands := false, mods := {}) -> Node3D:
	# 每次构建都进入独立材质上下文:这把枪的每个 box/cyl/ring 都会拿到唯一材质变体
	_current_weapon = id
	_current_part_idx = 0
	var g := Node3D.new()
	g.name = "Weapon_" + id
	if not _build_from_glb(id, g):
		_build(id, g)
	if not mods.is_empty():
		_apply_mods(g, id, mods)
	_merge_static(g)
	# 枪口参考点
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, MUZZLE_Y.get(id, 0.03), MUZZLE_Z.get(id, -0.7))
	g.add_child(muzzle)
	g.set_meta("muzzle", muzzle)
	if with_hands:
		var anchors: Dictionary = HAND_ANCHORS[id]
		var pistol_hand := id in ["m1911", "g17", "p226", "deagle", "m93r", "python", "sw686", "sw500"]
		var revolver_hand := id in ["python", "sw686", "sw500"]
		var hand_scale := 0.88 if revolver_hand else (1.0 if pistol_hand else 1.15)
		var right_hand := build_hand(false)
		right_hand.scale = Vector3.ONE * hand_scale
		right_hand.position = Vector3(anchors["r"][0], anchors["r"][1], anchors["r"][2])
		right_hand.rotation = Vector3(-0.2, -0.15, -1.3)
		g.add_child(right_hand)
		g.set_meta("right_hand", right_hand)
		var right_arm := build_forearm()
		right_arm.position = right_hand.position + Vector3(0, -0.012, 0.035)
		right_arm.rotation = Vector3(1.18, 0.30, 0)
		g.add_child(right_arm)
		g.set_meta("right_arm", right_arm)
		var left_hand := build_hand(true)
		left_hand.scale = Vector3.ONE * hand_scale
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
		left_arm.position = left_pos + Vector3(0, -0.012, 0.035)
		left_arm.rotation = Vector3(1.18, -0.30, 0)
		g.add_child(left_arm)
		g.set_meta("left_arm", left_arm)
		# [PERF] 手/臂内部静态合并:整只手仍是独立节点(换弹 pose 动画要动它),
		# 但手内部几十个零件先压成"手掌一块 + 每根手指一块",draw call 直接砍半。
		_optimize_hand(right_hand)
		_optimize_hand(left_hand)
		_merge_static(right_arm)
		_merge_static(left_arm)
	# 视角模型不投影
	set_shadow_recursive(g, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_current_weapon = ""
	_current_part_idx = 0
	return g


## 复制前的 owner 归一:pack() 只带走 owner 链上的节点,而 GLB 摘出来的散件
## (StockIrons 等,见 _hoist_to_root)已清 owner —— 不归一会被 pack 静默丢弃。
static func prepare_for_pack(root: Node) -> void:
	_set_owner_rec(root, root)


static func _set_owner_rec(n: Node, owner: Node) -> void:
	# 根节点自己不能设 owner 为自己(p_owner == this 报错);pack 时根节点
	# 本来就会被带走,只有子孙才需要 owner 归一。
	if n != owner:
		n.owner = owner
	for c in n.get_children():
		_set_owner_rec(c, owner)


## 安全深复制。
## 背景:GLB 模型是 PackedScene 实例,再被 _hoist_to_root 动过子树后,直接
## duplicate(含默认 USE_INSTANTIATION)会打穿 Godot 场景实例的内部缓存 ——
## "Index p_index=0 out of bounds / Child node disappeared while duplicating"
## (effects.gd 掉落武器、换弹 NewMag 复制都踩中)。
## pack→instantiate 走的是干净的场景序列化路径,无视实例缓存。
static func safe_duplicate(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	prepare_for_pack(node)
	var ps := PackedScene.new()
	if ps.pack(node) != OK:
		return null
	return ps.instantiate()


## 遍历节点树设置投影(工具函数)
static func set_shadow_recursive(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for o in node.get_children():
		if o is MeshInstance3D:
			o.cast_shadow = mode
		set_shadow_recursive(o, mode)
