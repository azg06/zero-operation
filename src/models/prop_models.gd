class_name PropModels
## 地图道具 GLB 库(tools/blender/build_props_batch.py 产出 models/props/*.glb)
## 单一合并网格多材质槽;按 GLB 材质名重贴程序化 PBR(三平面映射,无 UV 依赖)。
## MultiMesh 批绘直接用 prop_mesh() 返回的 ArrayMesh(表面材质已内嵌)。

const PROP_DIR := "res://models/props/"
static var _mesh_cache: Dictionary = {}
static var _mat_lib: Dictionary = {}


static func _tex(file: String) -> Texture2D:
	return load("res://textures/" + file)


## 材质名 → PBR(对标枪模/载具材质水准:三平面 + 法线 + 合理粗糙度/金属度)
static func _mats() -> Dictionary:
	if not _mat_lib.is_empty():
		return _mat_lib
	var mk := func(cname: String, rough: float, metal: float,
			tex := "", nor := "", tiling := 2.0, tint := Color.WHITE) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.html(cname) * tint
		m.roughness = rough
		m.metallic = metal
		m.texture_repeat = true
		if tex != "":
			m.albedo_texture = _tex(tex)
		if nor != "":
			m.normal_enabled = true
			m.normal_texture = _tex(nor)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tiling
		return m
	# 树皮:深棕木纹
	_mat_lib["bark"] = mk.call("#4a3520", 0.92, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg", 3.0)
	_mat_lib["bark_palm"] = mk.call("#6a5232", 0.88, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg", 4.0)
	# 树冠:低多边形哑光双色(无贴图,靠顶点扰动+光照)
	_mat_lib["leaf"] = mk.call("#4a7038", 0.9, 0.0)
	_mat_lib["leaf_pine"] = mk.call("#2e5030", 0.9, 0.0)
	_mat_lib["leaf_palm"] = mk.call("#4a8040", 0.88, 0.0)
	# 锈蚀/灼烧
	_mat_lib["rust"] = mk.call("#8a5a34", 0.9, 0.3, "rusty_metal_diff.jpg", "rusty_metal_nor.jpg", 2.5)
	_mat_lib["rust_dark"] = mk.call("#5a3c24", 0.92, 0.3, "rusty_metal_diff.jpg", "rusty_metal_nor.jpg", 2.5)
	_mat_lib["rust_burnt"] = mk.call("#3a322c", 0.95, 0.25, "rusty_metal_diff.jpg", "rusty_metal_nor.jpg", 2.0)
	_mat_lib["metal_burnt"] = mk.call("#26241f", 0.7, 0.6, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 3.0)
	# 木质
	_mat_lib["wood_olive"] = mk.call("#6a6a48", 0.85, 0.0, "plywood_diff.jpg", "plywood_nor.jpg", 2.0)
	_mat_lib["wood_dark"] = mk.call("#4e4230", 0.88, 0.0, "plywood_diff.jpg", "plywood_nor.jpg", 2.5)
	# 沙袋/岩石/水泥
	_mat_lib["sandbag"] = mk.call("#9a8a62", 0.98, 0.0, "sand_01_diff.jpg", "", 3.0)
	_mat_lib["rock"] = mk.call("#8a8a84", 0.95, 0.0, "rock_04_diff.jpg", "rock_04_nor.jpg", 1.5)
	_mat_lib["concrete"] = mk.call("#9a988e", 0.92, 0.0, "rough_concrete_diff.jpg", "rough_concrete_nor.jpg", 1.5)
	# 飞机:军绿蒙皮漆 / 座舱玻璃 / 识别条纹 / 橡胶轮胎
	_mat_lib["olive"] = mk.call("#4e5a3c", 0.55, 0.15, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.74, 0.82, 0.42)
	glass.roughness = 0.08
	glass.metallic = 0.2
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_lib["glass"] = glass
	_mat_lib["yellow"] = mk.call("#d8b430", 0.6, 0.1)
	_mat_lib["tire"] = mk.call("#1a1c1e", 0.96, 0.0)
	# ============ 城市/场景建筑 3A 批次材质(build_city_batch / build_scene_batch) ============
	# 墙体类:砖石/抹灰/波纹钢/木板/土坯/庙石/教堂石
	_mat_lib["wall"] = mk.call("#b0aca2", 0.90, 0.0, "rough_concrete_diff.jpg", "rough_concrete_nor.jpg", 1.2)
	_mat_lib["station_panel"] = mk.call("#c8ccd2", 0.62, 0.35, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.6)
	_mat_lib["sandstone"] = mk.call("#c2a878", 0.93, 0.0, "sand_01_diff.jpg", "", 2.0)
	_mat_lib["adobe"] = mk.call("#b89870", 0.95, 0.0, "sand_01_diff.jpg", "", 2.5)
	_mat_lib["temple_stone"] = mk.call("#8a867a", 0.94, 0.0, "rock_04_diff.jpg", "rock_04_nor.jpg", 1.8)
	_mat_lib["church_stone"] = mk.call("#a8a49c", 0.92, 0.0, "rock_04_diff.jpg", "rock_04_nor.jpg", 1.5)
	_mat_lib["farm_wall"] = mk.call("#d8d2c0", 0.88, 0.0, "plywood_diff.jpg", "plywood_nor.jpg", 1.8)
	_mat_lib["barn_red"] = mk.call("#9a3a2e", 0.88, 0.0, "plywood_diff.jpg", "plywood_nor.jpg", 1.8)
	_mat_lib["barn_white"] = mk.call("#e0dcd0", 0.85, 0.0, "plywood_diff.jpg", "plywood_nor.jpg", 2.0)
	_mat_lib["brick"] = mk.call("#8a4a38", 0.92, 0.0, "rough_concrete_diff.jpg", "rough_concrete_nor.jpg", 2.2)
	# 屋顶类:油毡/石板/瓦/茅草/穹顶
	_mat_lib["roof"] = mk.call("#4a4e52", 0.86, 0.15, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.8)
	_mat_lib["church_slate"] = mk.call("#3a4048", 0.80, 0.20, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 2.0)
	_mat_lib["farm_roof"] = mk.call("#5a5a5e", 0.85, 0.15, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.6)
	_mat_lib["thatch"] = mk.call("#9a7a42", 0.96, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg", 3.5)
	_mat_lib["dome"] = mk.call("#2e8a8a", 0.42, 0.30, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.4)
	_mat_lib["radome"] = mk.call("#d8d8d2", 0.70, 0.10, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.2)
	# 结构金属:钢构/管道/储罐/起重机/深色件
	_mat_lib["metal"] = mk.call("#8a8e94", 0.55, 0.75, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.6)
	_mat_lib["metal_dark"] = mk.call("#3e4248", 0.62, 0.65, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 1.8)
	_mat_lib["crane_steel"] = mk.call("#c89a2e", 0.58, 0.70, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.4)
	_mat_lib["pipe"] = mk.call("#7a8288", 0.50, 0.80, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.8)
	_mat_lib["tank"] = mk.call("#a8aab0", 0.62, 0.55, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.5)
	_mat_lib["silo"] = mk.call("#b8bcc0", 0.60, 0.60, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.5)
	_mat_lib["chrome"] = mk.call("#c8ccd0", 0.14, 1.0, "gun_chrome_diff.jpg", "gun_chrome_nor.jpg", 2.0)
	# 木材:原木/竹/绳
	_mat_lib["wood"] = mk.call("#6a5232", 0.88, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg", 2.2)
	_mat_lib["wood_log"] = mk.call("#7a5a36", 0.90, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg", 2.0)
	_mat_lib["bamboo"] = mk.call("#a89848", 0.86, 0.0, "gun_wood_diff.jpg", "gun_wood_nor.jpg", 3.0)
	_mat_lib["rope"] = mk.call("#8a7448", 0.96, 0.0)
	# 装饰/涂料:收边/招牌/陶土/帆布/玻璃/金
	_mat_lib["trim"] = mk.call("#d0ccc2", 0.78, 0.10, "rough_concrete_diff.jpg", "rough_concrete_nor.jpg", 1.6)
	_mat_lib["sign"] = mk.call("#c83a30", 0.62, 0.05)
	_mat_lib["clay"] = mk.call("#a06848", 0.90, 0.0, "sand_01_diff.jpg", "", 2.5)
	_mat_lib["canvas"] = mk.call("#c8b898", 0.95, 0.0, "plywood_diff.jpg", "plywood_nor.jpg", 2.5)
	_mat_lib["gold"] = mk.call("#d8b040", 0.28, 0.95, "gun_brass_diff.jpg", "gun_brass_nor.jpg", 2.0)
	_mat_lib["plate"] = mk.call("#e8e8e0", 0.55, 0.10)
	# 车辆专用
	_mat_lib["car_paint"] = mk.call("#3a4a5e", 0.28, 0.55, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.4)
	_mat_lib["lamp_white"] = mk.call("#fff4d8", 0.20, 0.0)
	_mat_lib["lamp_red"] = mk.call("#c82a20", 0.30, 0.0)
	_mat_lib["lamp_blue"] = mk.call("#2a5ad8", 0.30, 0.0)
	# 灯窗/太阳能/水面/植被/雪
	var lamp_warm := StandardMaterial3D.new()
	lamp_warm.albedo_color = Color(1.0, 0.86, 0.55, 1.0)
	lamp_warm.emission_enabled = true
	lamp_warm.emission = Color(1.0, 0.78, 0.42, 1.0)
	lamp_warm.emission_energy_multiplier = 1.6
	lamp_warm.roughness = 0.30
	_mat_lib["lamp_warm"] = lamp_warm
	_mat_lib["solar"] = mk.call("#1a2440", 0.18, 0.55, "gun_dark_diff.jpg", "gun_dark_nor.jpg", 2.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.20, 0.42, 0.56, 0.80)
	water.roughness = 0.10
	water.metallic = 0.15
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_lib["water"] = water
	_mat_lib["grass"] = mk.call("#5b6b43", 0.96, 0.0, "gun_wood_diff.jpg", "", 4.0)
	_mat_lib["jungle_leaf"] = mk.call("#2e5a28", 0.92, 0.0)
	_mat_lib["snow"] = mk.call("#e8ecf0", 0.78, 0.0, "sand_01_diff.jpg", "", 2.0)
	# 集装箱/船体(暮港)
	_mat_lib["container"] = mk.call("#2e6a8a", 0.72, 0.30, "corrugated_iron_diff.jpg", "corrugated_iron_nor.jpg", 1.6)
	_mat_lib["container_alt"] = mk.call("#8a6a2e", 0.72, 0.30, "corrugated_iron_diff.jpg", "corrugated_iron_nor.jpg", 1.6)
	_mat_lib["container_red"] = mk.call("#8a3030", 0.72, 0.30, "corrugated_iron_diff.jpg", "corrugated_iron_nor.jpg", 1.6)
	_mat_lib["ship_hull"] = mk.call("#2a3038", 0.68, 0.45, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.2)
	_mat_lib["ship_deck"] = mk.call("#5a5a4e", 0.85, 0.20, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.5)
	_mat_lib["ship_super"] = mk.call("#dcd8cc", 0.70, 0.10, "metal_plate_diff.jpg", "metal_plate_nor.jpg", 1.4)
	# 洞口(纯暗,做凹龛/开口用)
	_mat_lib["dark_opening"] = mk.call("#0a0c0e", 0.98, 0.0)
	# ============ 秋津市(akitsu)日式城市批次(与 tools/blender/jp_common.ZMAT 同名对应) ============
	# 湿润沥青(刚下过雨:低粗糙度 → 天光反射/积水感)
	_mat_lib["asphalt"] = mk.call("#7c7f86", 0.93, 0.0, "asphalt_02_diff.jpg", "", 2.0)
	_mat_lib["asphalt_w"] = mk.call("#84878e", 0.94, 0.0, "asphalt_02_diff.jpg", "", 3.0)
	_mat_lib["paint_w"] = mk.call("#d6d6d0", 0.92, 0.0)
	_mat_lib["paint_y"] = mk.call("#c7a629", 0.92, 0.0)
	# 神社/寺院
	_mat_lib["vermilion"] = mk.call("#b8331f", 0.62, 0.0, "plywood_diff.jpg", "", 2.0)
	_mat_lib["roof_tile"] = mk.call("#3b4350", 0.58, 0.10, "corrugated_iron_diff.jpg", "", 3.0)
	_mat_lib["plaster"] = mk.call("#dbd9cf", 0.90, 0.0, "rough_concrete_diff.jpg", "", 1.4)
	_mat_lib["stone"] = mk.call("#8a877e", 0.96, 0.0, "rock_04_diff.jpg", "", 1.6)
	_mat_lib["stone_d"] = mk.call("#5e5c56", 0.94, 0.0, "rock_04_diff.jpg", "", 1.6)
	_mat_lib["concrete_d"] = mk.call("#78776f", 0.95, 0.0, "rough_concrete_diff.jpg", "", 1.6)
	_mat_lib["wood_b"] = mk.call("#6b4d30", 0.86, 0.0, "gun_wood_diff.jpg", "", 2.2)
	_mat_lib["wood_d"] = mk.call("#4a3826", 0.88, 0.0, "gun_wood_diff.jpg", "", 2.4)
	_mat_lib["metal_d"] = mk.call("#3e4248", 0.62, 0.65, "gun_dark_diff.jpg", "", 1.8)
	# 室内货架/柜体:浅灰哑光。旧版货架走 metal_d(深色高金属度),在室内单点补光下整块
	# 发黑,被读作"莫名其妙的黑箱子"(用户反馈)。
	#   ★ albedo = 颜色 × 贴图:metal_plate_diff 平均亮度只有 50, 配浅灰会乘成 0.14(=发黑)。
	#     货架用高亮度波纹铁贴图(mean 175)配浅灰, 最终 ≈0.59 才是"看得见的浅色货架"。
	_mat_lib["shelf"] = mk.call("#d8dbd8", 0.55, 0.04, "corrugated_iron_diff.jpg", "", 2.0)
	_mat_lib["dark"] = mk.call("#2b2b2e", 0.96, 0.0)
	_mat_lib["sand"] = mk.call("#c7b88f", 0.94, 0.0, "sand_01_diff.jpg", "", 2.5)
	# 樱(春树,暖粉)
	_mat_lib["cherry"] = mk.call("#e09eb2", 0.90, 0.0)
	_mat_lib["banner"] = mk.call("#d9d1c0", 0.92, 0.0)
	_mat_lib["taxi_y"] = mk.call("#d9a61a", 0.42, 0.35, "metal_plate_diff.jpg", "", 1.4)

	# ---------------- 日语标识(UV 图集;不能走三平面,否则 UV 被毁) ----------------
	# 贴图由 tools/blender/gen_jp_signs.py 生成:4x4 图集(每格 256px)+ 地面报纸 512²。
	# jp_common.sign_panel() 按格写 UV;材质名与 ZMAT 表同名。
	var sig := func(file: String, _tiling := 0.0) -> StandardMaterial3D:   # _tiling 未使用(图集靠 UV 取格,不缩放)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.WHITE
		m.roughness = 0.55
		m.metallic = 0.0
		m.texture_repeat = false
		m.uv1_triplanar = false            # ★ 关键:图集靠 UV 取格,三平面会毁掉
		# ☆ 勿在此加 uv1_scale/offset 做翻转:图集的"格"就是靠 UV 的 v 区间选的,
		#   材质端翻 v 会连格子一起换行(实测 cell11 的牌会变成 cell7 的内容)。
		m.uv1_scale = Vector3.ONE
		m.albedo_texture = _tex(file)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m
	_mat_lib["sign_jp_shop"] = sig.call("jp_sign_shop.png")
	_mat_lib["sign_jp_ad"] = sig.call("jp_sign_ad.png")
	_mat_lib["sign_jp_notice"] = sig.call("jp_sign_notice.png")
	_mat_lib["sign_jp_road"] = sig.call("jp_sign_road.png")
	_mat_lib["sign_jp_banner"] = sig.call("jp_sign_banner.png")
	_mat_lib["jp_flyer"] = sig.call("jp_flyer.png")
	# 招牌背板/支架(无贴图)
	_mat_lib["sign_back"] = mk.call("#4a4e54", 0.80, 0.15, "metal_plate_diff.jpg", "", 1.6)
	_mat_lib["sign_pole"] = mk.call("#7c8086", 0.62, 0.45, "metal_plate_diff.jpg", "", 1.4)
	# 招牌/販卖机
	_mat_lib["sign_r"] = mk.call("#c03028", 0.60, 0.05)
	_mat_lib["sign_b"] = mk.call("#2857a8", 0.60, 0.05)
	_mat_lib["sign_g"] = mk.call("#28784a", 0.60, 0.05)
	_mat_lib["sign_o"] = mk.call("#d17828", 0.60, 0.05)
	_mat_lib["sign_w"] = mk.call("#e0e0d8", 0.62, 0.05)
	_mat_lib["soda_red"] = mk.call("#c02929", 0.30, 0.15)
	_mat_lib["soda_blue"] = mk.call("#2859c0", 0.30, 0.15)
	_mat_lib["rubber"] = mk.call("#17191b", 0.97, 0.0)
	_mat_lib["tent"] = mk.call("#5a6048", 0.94, 0.0, "plywood_diff.jpg", "", 2.0)
	# 和纸灯笼(暖白自发光;街灯/鸟居前灯)
	var lant := StandardMaterial3D.new()
	lant.albedo_color = Color(1.0, 0.92, 0.76, 1.0)
	lant.emission_enabled = true
	lant.emission = Color(1.0, 0.82, 0.55, 1.0)
	lant.emission_energy_multiplier = 1.4
	lant.roughness = 0.45
	_mat_lib["lamp"] = lant
	return _mat_lib


## 公开材质库(秋津市 GLB 按材质名重贴用)
static func mat_lib() -> Dictionary:
	return _mats()


## 材质名 → PBR(未注册名回退 rust,不崩)
static func mat_named(nm: String) -> Material:
	var lib := _mats()
	return lib.get(nm, lib["rust"])


## GLB → 按材质名重贴 PBR 的 ArrayMesh(缓存;供 MultiMesh 批绘/单实例共用)
static func prop_mesh(id: String) -> ArrayMesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var path := PROP_DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[props] GLB 缺失: " + path)
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var node: Node3D = ps.instantiate()
	var mesh: ArrayMesh = null
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			mesh = mi.mesh.duplicate(true)
			break
	node.free()
	if mesh == null:
		return null
	var lib := _mats()
	var fallback: StandardMaterial3D = lib["rust"]
	for si in mesh.get_surface_count():
		var smat := mesh.surface_get_material(si)
		var sname := smat.resource_name if smat != null else ""
		mesh.surface_set_material(si, lib.get(sname, fallback))
	_mesh_cache[id] = mesh
	return mesh


## 单实例放置(残骸等大型道具;rot 弧度,sc 缩放)
static func place(wg: Node3D, id: String, x: float, z: float, rot := 0.0, sc := 1.0, y_off := 0.0) -> Node3D:
	var mesh := prop_mesh(id)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
	mi.position = Vector3(x, gh + y_off, z)
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	wg.add_child(mi)
	return mi
