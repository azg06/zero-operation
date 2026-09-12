class_name MapsData
## 地图主题数据(对应 map.js 中的 MAPS)

class MapDef extends RefCounted:
	var id := ""
	var cn := ""
	var mode := "conquest"            # conquest | breakthrough | tdm | br
	var size := 320.0
	var theme := ""                   # 外观主题(空=id 自身;tdm_city 复用 city)
	var extra := {}                   # 模式专属数据(br: villages/roads/loot_points/vehicle_points/drop_zone/zone_bounds)
	var road := 80.0
	var amp := 0.0                    # 突破地形起伏幅度
	var sky_top := Color()
	var sky_mid := Color()
	var sky_bot := Color()
	var fog_color := Color()
	var fog_near := 60.0
	var fog_far := 400.0
	var hemi_sky := Color()
	var hemi_ground := Color()
	var hemi_energy := 1.15
	var sun_color := Color()
	var sun_energy := 1.6
	var sun_pos := Vector3(80, 140, 60)
	var cloud_color := Color.WHITE
	# 突破模式专用
	var ground_photo := ""
	var tiles := 8
	var base_color := Color()
	var road_color := Color()
	var rut_color := Color()
	var plaza_color := Color()
	var river: Variant = null         # 河道中心 z
	var sea := false
	var night := false
	var tdm_ok := false               # TDM 兼容(120m 圈定构建;夜战图不加)
	var sectors: Array = []           # [[{id,x,z}, ...], ...]


static func build_maps() -> Dictionary:
	var MD := {}

	var city := MapDef.new()
	city.id = "city"; city.cn = "城市街区"; city.size = 320; city.road = 80
	city.sky_top = Color.html("#5a8ac8"); city.sky_mid = Color.html("#9ab8d8"); city.sky_bot = Color.html("#c8b89a")
	city.fog_color = Color.html("#9aa5b0"); city.fog_near = 60; city.fog_far = 400
	city.hemi_sky = Color.html("#bfd4e8"); city.hemi_ground = Color.html("#5a5248"); city.hemi_energy = 1.15
	city.sun_color = Color.html("#fff2dd"); city.sun_energy = 1.6; city.sun_pos = Vector3(80, 140, 60)
	city.cloud_color = Color.WHITE
	city.tdm_ok = true   # TDM 兼容:120m 圈定(圈选城市中心区)
	MD["city"] = city

	var desert := MapDef.new()
	desert.id = "desert"; desert.cn = "沙漠油站"; desert.size = 320; desert.road = 80
	desert.sky_top = Color.html("#6a9ac8"); desert.sky_mid = Color.html("#d8c8a0"); desert.sky_bot = Color.html("#e8c890")
	desert.fog_color = Color.html("#d8c09a"); desert.fog_near = 50; desert.fog_far = 400
	desert.hemi_sky = Color.html("#ffe8c8"); desert.hemi_ground = Color.html("#8a6a4a"); desert.hemi_energy = 1.1
	desert.sun_color = Color.html("#ffe0b0"); desert.sun_energy = 1.8; desert.sun_pos = Vector3(100, 120, 40)
	desert.cloud_color = Color.html("#fff0d8")
	desert.tdm_ok = true   # TDM 兼容:120m 圈定(油站中心区)
	MD["desert"] = desert

	var snow := MapDef.new()
	snow.id = "snow"; snow.cn = "雪山哨站"; snow.size = 320; snow.road = 80
	snow.sky_top = Color.html("#7a9ac0"); snow.sky_mid = Color.html("#c0d0e0"); snow.sky_bot = Color.html("#e0e8f0")
	snow.fog_color = Color.html("#c8d4e0"); snow.fog_near = 40; snow.fog_far = 320
	snow.hemi_sky = Color.html("#d0e0f0"); snow.hemi_ground = Color.html("#6a7078"); snow.hemi_energy = 1.2
	snow.sun_color = Color.html("#f0f4ff"); snow.sun_energy = 1.3; snow.sun_pos = Vector3(60, 140, 80)
	snow.cloud_color = Color.html("#f0f4f8")
	snow.tdm_ok = true   # TDM 兼容:120m 圈定(哨站中心区)
	MD["snow"] = snow

	var jungle := MapDef.new()
	jungle.id = "bt_jungle"; jungle.cn = "丛林河谷"; jungle.mode = "breakthrough"
	jungle.size = 420; jungle.amp = 1.3
	jungle.sky_top = Color.html("#4a7ab0"); jungle.sky_mid = Color.html("#98c8a0"); jungle.sky_bot = Color.html("#d8e0b0")
	jungle.fog_color = Color.html("#9ab896"); jungle.fog_near = 38; jungle.fog_far = 280
	jungle.hemi_sky = Color.html("#cfe8c8"); jungle.hemi_ground = Color.html("#36452e"); jungle.hemi_energy = 1.15
	jungle.sun_color = Color.html("#fff0c0"); jungle.sun_energy = 1.5; jungle.sun_pos = Vector3(70, 135, 55)
	jungle.cloud_color = Color.html("#f0f8e0")
	jungle.ground_photo = "rock_04"; jungle.tiles = 9; jungle.base_color = Color.html("#55663c")
	jungle.road_color = Color(0.47, 0.39, 0.26, 0.55); jungle.rut_color = Color(0.29, 0.24, 0.15, 0.5)
	jungle.plaza_color = Color(0.51, 0.44, 0.29, 0.6)
	jungle.river = -55.0
	jungle.tdm_ok = true   # TDM 兼容:120m 圈定(河谷中段)
	jungle.sectors = [
		[{ "id": "A", "x": -26, "z": -110 }, { "id": "B", "x": 24, "z": -106 }],
		[{ "id": "A", "x": -24, "z": -6 }, { "id": "B", "x": 26, "z": 2 }],
		[{ "id": "A", "x": -26, "z": 106 }, { "id": "B", "x": 24, "z": 110 }],
	]
	MD["bt_jungle"] = jungle

	var harbor := MapDef.new()
	harbor.id = "bt_harbor"; harbor.cn = "暮港码头"; harbor.mode = "breakthrough"
	harbor.size = 420; harbor.amp = 0.9
	harbor.sky_top = Color.html("#3a3a68"); harbor.sky_mid = Color.html("#b86a58"); harbor.sky_bot = Color.html("#e8a068")
	harbor.fog_color = Color.html("#9a7a72"); harbor.fog_near = 55; harbor.fog_far = 340
	harbor.hemi_sky = Color.html("#e8b090"); harbor.hemi_ground = Color.html("#3a3a4e"); harbor.hemi_energy = 1.05
	harbor.sun_color = Color.html("#ffb070"); harbor.sun_energy = 1.35; harbor.sun_pos = Vector3(-95, 55, 45)
	harbor.cloud_color = Color.html("#d8a08a")
	harbor.ground_photo = "asphalt_02"; harbor.tiles = 10; harbor.base_color = Color.html("#34363a")
	harbor.road_color = Color(0.24, 0.24, 0.26, 0.9); harbor.rut_color = Color(0.54, 0.51, 0.35, 0.9)
	harbor.plaza_color = Color(0.29, 0.28, 0.26, 0.9)
	harbor.sea = true
	harbor.tdm_ok = true   # TDM 兼容:120m 圈定(码头中段)
	harbor.sectors = [
		[{ "id": "A", "x": -28, "z": -110 }, { "id": "B", "x": 26, "z": -106 }],
		[{ "id": "A", "x": -25, "z": -4 }, { "id": "B", "x": 27, "z": 4 }],
		[{ "id": "A", "x": -27, "z": 106 }, { "id": "B", "x": 25, "z": 110 }],
	]
	MD["bt_harbor"] = harbor

	var peak := MapDef.new()
	peak.id = "bt_peak"; peak.cn = "暗夜雷达站"; peak.mode = "breakthrough"
	peak.size = 420; peak.amp = 1.6
	peak.sky_top = Color.html("#04070f"); peak.sky_mid = Color.html("#0e1a2e"); peak.sky_bot = Color.html("#223448")
	peak.fog_color = Color.html("#0a121e"); peak.fog_near = 40; peak.fog_far = 250
	peak.hemi_sky = Color.html("#6a86b8"); peak.hemi_ground = Color.html("#080d16"); peak.hemi_energy = 0.42
	peak.sun_color = Color.html("#c4d4f8"); peak.sun_energy = 0.72; peak.sun_pos = Vector3(60, 150, 75)
	peak.cloud_color = Color.html("#16223a")
	peak.ground_photo = "rock_04"; peak.tiles = 8; peak.base_color = Color.html("#3d4247")
	peak.road_color = Color(0.31, 0.33, 0.36, 0.55); peak.rut_color = Color(0.18, 0.2, 0.22, 0.5)
	peak.plaza_color = Color(0.35, 0.37, 0.4, 0.6)
	peak.night = true
	peak.sectors = [
		[{ "id": "A", "x": -25, "z": -108 }, { "id": "B", "x": 27, "z": -112 }],
		[{ "id": "A", "x": -27, "z": 2 }, { "id": "B", "x": 25, "z": -8 }],
		[{ "id": "A", "x": -24, "z": 110 }, { "id": "B", "x": 26, "z": 106 }],
	]
	MD["bt_peak"] = peak

	var tdm_city := MapDef.new()
	tdm_city.id = "tdm_city"; tdm_city.cn = "城市死斗"; tdm_city.mode = "tdm"
	# TDM 圈定小块区域:240m → 120m(街道 road 等比 56→28,保证街区/可进入建筑不越界)
	tdm_city.size = 120; tdm_city.road = 28; tdm_city.theme = "city"
	tdm_city.sky_top = Color.html("#5a8ac8"); tdm_city.sky_mid = Color.html("#9ab8d8"); tdm_city.sky_bot = Color.html("#c8b89a")
	tdm_city.fog_color = Color.html("#9aa5b0"); tdm_city.fog_near = 60; tdm_city.fog_far = 400
	tdm_city.hemi_sky = Color.html("#bfd4e8"); tdm_city.hemi_ground = Color.html("#5a5248"); tdm_city.hemi_energy = 1.15
	tdm_city.sun_color = Color.html("#fff2dd"); tdm_city.sun_energy = 1.6; tdm_city.sun_pos = Vector3(80, 140, 60)
	tdm_city.cloud_color = Color.WHITE
	MD["tdm_city"] = tdm_city

	var br_valley := MapDef.new()
	br_valley.id = "br_valley"; br_valley.cn = "山谷战场"; br_valley.mode = "br"
	br_valley.size = 800; br_valley.road = 0; br_valley.theme = "br_valley"
	br_valley.river = -60.0   # BR 语义:河道中心 x(北南走向贯穿河谷)
	br_valley.sky_top = Color.html("#4a7ab0"); br_valley.sky_mid = Color.html("#9ac0a8"); br_valley.sky_bot = Color.html("#d8dcc0")
	br_valley.fog_color = Color.html("#a8b49a"); br_valley.fog_near = 80; br_valley.fog_far = 500
	br_valley.hemi_sky = Color.html("#cfe8cc"); br_valley.hemi_ground = Color.html("#3a4430"); br_valley.hemi_energy = 1.1
	br_valley.sun_color = Color.html("#fff2d0"); br_valley.sun_energy = 1.5; br_valley.sun_pos = Vector3(120, 150, 80)
	br_valley.cloud_color = Color.html("#f0f8e8")
	# ---- BR 专属数据(BR Agent 读取) ----
	br_valley.extra = {
		"villages": [
			{ "x": 0.0, "z": -240.0 },
			{ "x": -150.0, "z": 40.0 },
			{ "x": 160.0, "z": -50.0 },
			{ "x": 20.0, "z": 235.0 },
			{ "x": -270.0, "z": -275.0 },
			{ "x": -245.0, "z": 270.0 },
			{ "x": 270.0, "z": 190.0 },
			{ "x": 150.0, "z": -305.0 },
		],
		"roads": [
			[0.0, -240.0, -150.0, 40.0],
			[-150.0, 40.0, 20.0, 235.0],
			[20.0, 235.0, 160.0, -50.0],
			[160.0, -50.0, 0.0, -240.0],
			[160.0, -50.0, 215.0, 45.0],       # 村庄3 → 城市西缘(接入街道 z=45)
			[20.0, 235.0, 215.0, 225.0],       # 村庄4 → 城市北缘(接入街道 z=225)
			[0.0, -240.0, -270.0, -275.0],
			[-270.0, -275.0, -150.0, 40.0],
			[-150.0, 40.0, -245.0, 270.0],
			[-245.0, 270.0, 20.0, 235.0],
			[20.0, 235.0, 270.0, 190.0],
			[270.0, 190.0, 160.0, -50.0],
			[160.0, -50.0, 150.0, -305.0],
			[150.0, -305.0, 0.0, -240.0],
			[-270.0, -275.0, -245.0, 270.0],
		],
		"loot_points": [],
		"vehicle_points": [],
		"drop_zone": Rect2(-200, -370, 400, 740),   # 跳伞航线参考区:地图中线纵向带
		"zone_bounds": 390.0,                        # 毒圈计算区域 = G.bounds(800m 地图半宽)
	}
	# ---- 城市区(东北部高密度街区:8 排 × 6-8 栋 + 横竖街道 + 广场;可进入房 16 栋,固定种子) ----
	var crng := RandomNumberGenerator.new()
	crng.seed = 20240808
	var city_blocks := []
	var city_streets := [-360.0, -315.0, -225.0, -135.0, -45.0, 45.0, 135.0, 225.0, 315.0, 360.0]
	var city_rows := [-315.0, -225.0, -135.0, -45.0, 45.0, 135.0, 225.0, 315.0]
	var city_avenues := [225.0, 315.0]
	var ent_city := 0
	for ri in city_rows.size():
		var rx := 190.0 + crng.randf_range(0, 8)
		var guard := 0
		while rx < 365.0 and guard < 60:
			guard += 1
			var ent: bool = crng.randf() < 0.5 and ent_city < 16
			var bw := 0.0
			var bd := 0.0
			var bh := 0.0
			if ent:
				ent_city += 1
				bw = crng.randf_range(8.0, 10.0)
				bd = crng.randf_range(6.6, 8.0)
				bh = 3.3
			else:
				bw = crng.randf_range(12.0, 18.0)
				bd = crng.randf_range(16.0, 23.0)
				bh = crng.randf_range(10.0, 26.0)
			var cx := rx + bw / 2.0
			var cz: float = float(city_rows[ri]) + crng.randf_range(-2.0, 2.0)
			city_blocks.append({
				"x": cx, "z": cz, "w": bw, "d": bd, "h": bh, "enter": ent,
				"street": city_streets[ri],  # 南侧临街(门朝向/物资贴街)
			})
			rx += bw + crng.randf_range(3.0, 6.0)
	# 沿街填充:新区街道(±360)外侧 4 座小商店(网格外沿,避让路灯/街面道具)
	for sk in [[-360.0, -1.0], [360.0, 1.0]]:
		for sx4 in [230.0, 300.0]:
			city_blocks.append({
				"x": sx4 + crng.randf_range(-3.0, 3.0),
				"z": sk[0] + sk[1] * 14.0 + crng.randf_range(-2.0, 2.0),
				"w": crng.randf_range(6.0, 9.0), "d": crng.randf_range(6.0, 9.0),
				"h": crng.randf_range(5.0, 9.0), "enter": false, "street": sk[0],
			})
	br_valley.extra["city_blocks"] = city_blocks
	br_valley.extra["city_streets"] = city_streets
	br_valley.extra["city_avenues"] = city_avenues
	# ---- 野外农场(西/外围散落;4 栋可进入农舍) ----
	br_valley.extra["farms"] = [
		{ "x": -245.0, "z": -150.0, "style": 1 },
		{ "x": -265.0, "z": 60.0, "style": 0 },
		{ "x": -225.0, "z": 210.0, "style": 1 },
		{ "x": 250.0, "z": -265.0, "style": 0, "enter": true },
		{ "x": 170.0, "z": 265.0, "style": 1 },
		{ "x": -320.0, "z": -310.0, "style": 0, "enter": true },
		{ "x": -330.0, "z": 320.0, "style": 1, "enter": true },
		{ "x": 330.0, "z": -330.0, "style": 0, "enter": true },
		{ "x": 320.0, "z": 330.0, "style": 1 },
		{ "x": -30.0, "z": -350.0, "style": 0 },
	]
	# 物资点:每村 16 个 + 道路沿线 14 个 + 野外网格 24 个(固定种子,可复现;地图不再空旷)
	var br_rng := RandomNumberGenerator.new()
	br_rng.seed = 20240807
	for v in br_valley.extra["villages"]:
		for k in 16:
			br_valley.extra["loot_points"].append(Vector3(
				v["x"] + br_rng.randf_range(-26, 26), 0.0,
				v["z"] + br_rng.randf_range(-26, 26)))
	for k in 14:
		br_valley.extra["loot_points"].append(Vector3(
			br_rng.randf_range(-180, 180), 0.0,
			br_rng.randf_range(-340, 340)))
	# 野外网格物资:把物资铺到远离聚落的空地(网格 + 抖动,保证全图可搜)
	for gy in 4:
		for gx in 4:
			br_valley.extra["loot_points"].append(Vector3(
				-280.0 + gx * 180.0 + br_rng.randf_range(-30, 30), 0.0,
				-280.0 + gy * 180.0 + br_rng.randf_range(-30, 30)))
	# 村庄新楼配套物资点(每村 2 个,聚落外环 28-34m,避开河道/城市区)
	var v_extra := [
		[28.0, 0.0], [-28.0, 0.0],       # 村1(0,-240) 东西侧
		[0.0, 30.0], [0.0, -30.0],       # 村2(-150,40) 南北侧
		[-34.0, 0.0], [-26.0, 14.0],     # 村3(160,-50) 西/西南(避城市)
		[30.0, 0.0], [-30.0, 0.0],       # 村4(20,235) 东西侧
		[0.0, 34.0], [0.0, -34.0],       # 村5(-270,-275) 南北侧
		[-34.0, 0.0], [34.0, 0.0],       # 村6(-245,270) 东西侧
		[0.0, -32.0], [26.0, 18.0],      # 村7(270,190) 南/西南(避城市)
		[-30.0, 0.0], [30.0, 0.0],       # 村8(150,-305) 东西侧
	]
	for vi2 in br_valley.extra["villages"].size():
		var vv2: Dictionary = br_valley.extra["villages"][vi2]
		for k2 in 2:
			br_valley.extra["loot_points"].append(Vector3(
				vv2["x"] + v_extra[vi2 * 2 + k2][0], 0.0,
				vv2["z"] + v_extra[vi2 * 2 + k2][1]))
	# 城市物资点:约 85% 栋临街 1 个 + 可进入房内 2 个 + 广场 8 个(贴合街区布局)
	var cr2 := RandomNumberGenerator.new()
	cr2.seed = 20240809
	var city_loot := 0
	for blk in city_blocks:
		if cr2.randf() < 0.85:
			br_valley.extra["loot_points"].append(Vector3(
				blk["x"] + cr2.randf_range(-5, 5), 0.0,
				blk["street"] + 5.0))
			city_loot += 1
		if blk["enter"]:
			br_valley.extra["loot_points"].append(Vector3(blk["x"], 0.0, blk["z"]))
			br_valley.extra["loot_points"].append(Vector3(blk["x"] + 2.0, 0.0, blk["z"] + 2.0))
			city_loot += 2
	for k in 8:
		br_valley.extra["loot_points"].append(Vector3(275.0 + cr2.randf_range(-8, 8), 0.0, 45.0 + cr2.randf_range(-6, 6)))
	# 农场物资点:每农场 3 个(谷仓/农舍旁 + 草垛旁 + 场院入口)
	for f in br_valley.extra["farms"]:
		br_valley.extra["loot_points"].append(Vector3(f["x"] + 4.0, 0.0, f["z"]))
		br_valley.extra["loot_points"].append(Vector3(f["x"] - 6.0, 0.0, f["z"] - 5.0))
		br_valley.extra["loot_points"].append(Vector3(f["x"] + 2.0, 0.0, f["z"] + 8.0))
	# 城市接驳道路口 2 个
	br_valley.extra["loot_points"].append(Vector3(190.0, 0.0, 40.0))
	br_valley.extra["loot_points"].append(Vector3(190.0, 0.0, 220.0))
	print("[MAPS] br_valley 城市区: 街区=", city_blocks.size(), " 可进入房=", ent_city + 4, " 城市物资点=", city_loot,
		" 物资总数=", br_valley.extra["loot_points"].size())
	# 载具点:每村外围 2 个 + 道路旁 2 个 + 城市外围 4 个 = 14 个
	for v in br_valley.extra["villages"]:
		var side := 1.0 if br_rng.randf() < 0.5 else -1.0
		br_valley.extra["vehicle_points"].append(Vector3(
			v["x"] + side * br_rng.randf_range(32, 44), 0.0, v["z"] + br_rng.randf_range(-10, 10)))
		br_valley.extra["vehicle_points"].append(Vector3(
			v["x"] - side * br_rng.randf_range(32, 44), 0.0, v["z"] + br_rng.randf_range(-10, 10)))
	for k in 2:
		br_valley.extra["vehicle_points"].append(Vector3(
			br_rng.randf_range(-40, 40), 0.0, br_rng.randf_range(-120, 120)))
	for vp in [[210.0, -135.0], [210.0, 135.0], [350.0, 0.0], [350.0, -180.0]]:
		br_valley.extra["vehicle_points"].append(Vector3(vp[0], 0.0, vp[1]))
	# 道路两侧载具点:沿 roads 每段布置(法线偏移 ±6-10m,两侧各 1),贴合道路且避让
	# 河道(river±30)/村庄(±40)/城市区(x>185)/农场(±30)/边界(±385)。
	# 段 t 值按段长 150-250m 间距选定:段0 双点受河道渡口(x∈[-90,-30])挤压取单点,
	# 段1 双点绕开渡口(t=0.53 处 x=-60),段4(村庄3→城市西缘 110m 短接驳)不布置。
	var rv_rng := RandomNumberGenerator.new()
	rv_rng.seed = 20240810
	var seg_ts := [[0.72], [0.22, 0.8], [0.5], [0.5], [], [0.55]]
	var roads_arr: Array = br_valley.extra["roads"]
	var avoid_spot := func(px: float, pz: float) -> bool:
		if absf(px - br_valley.river) < 30.0:
			return false
		for vv2 in br_valley.extra["villages"]:
			var ddx2: float = px - vv2["x"]
			var ddz2: float = pz - vv2["z"]
			if ddx2 * ddx2 + ddz2 * ddz2 < 40.0 * 40.0:
				return false
		if px > 185.0 and pz > -350.0 and pz < 350.0:
			return false
		for ff2 in br_valley.extra["farms"]:
			var fdx2: float = px - ff2["x"]
			var fdz2: float = pz - ff2["z"]
			if fdx2 * fdx2 + fdz2 * fdz2 < 30.0 * 30.0:
				return false
		return true
	for si3 in seg_ts.size():
		var seg3: Array = roads_arr[si3]
		var a3 := Vector2(seg3[0], seg3[1])
		var b3 := Vector2(seg3[2], seg3[3])
		if a3.distance_to(b3) < 120.0:
			continue
		var dir3 := (b3 - a3).normalized()
		var perp3 := Vector2(-dir3.y, dir3.x)
		for t3: float in (seg_ts[si3] as Array):
			var p3 := a3.lerp(b3, t3)
			for s3: float in [-1.0, 1.0]:
				var off3 := 6.0 + rv_rng.randf_range(0.0, 4.0)
				var px3 := p3.x + perp3.x * off3 * s3
				var pz3 := p3.y + perp3.y * off3 * s3
				if avoid_spot.call(px3, pz3) and absf(px3) < 385.0 and absf(pz3) < 385.0:
					br_valley.extra["vehicle_points"].append(Vector3(px3, 0.0, pz3))
	print("[MAPS] br_valley 载具点=", br_valley.extra["vehicle_points"].size(),
		"(村庄 8 + 道路旁 ", br_valley.extra["vehicle_points"].size() - 14, " + 城市 4 + 中心 2)")
	MD["br_valley"] = br_valley

	# ==================== 秋津市(AKITSU;全 Blender 手工建模静态城市,960m 征服) ====================
	# 布局真源:tools/blender/jp_city_design.md。10 区 GLB 拼装(models/map_akitsu/zone_N.glb),
	# 引擎侧不做程序化生成;垂直玩法由 walk_ 面烘焙进 G.floor_h(天桥/月台/屋顶/地下通道)。
	var akitsu := MapDef.new()
	akitsu.id = "akitsu"; akitsu.cn = "秋津市"; akitsu.mode = "conquest"
	akitsu.size = 960; akitsu.road = 120
	# 黄金黄昏(15.2):暖天穹 + 低斜长影;靠天穹/光色而非压低太阳(用户定,部署界面保持可辨)
	akitsu.sky_top = Color.html("#3f6398"); akitsu.sky_mid = Color.html("#b08a6a"); akitsu.sky_bot = Color.html("#eab887")
	akitsu.fog_color = Color.html("#d3b193"); akitsu.fog_near = 320; akitsu.fog_far = 2800   # 960m 图:雾太近会吃掉海滨/港区的远距交火视野
	akitsu.hemi_sky = Color.html("#f2caa0"); akitsu.hemi_ground = Color.html("#5a5244"); akitsu.hemi_energy = 2.30
	akitsu.sun_color = Color.html("#ffd7a0"); akitsu.sun_energy = 1.65; akitsu.sun_pos = Vector3(-150, 95, 70)
	akitsu.cloud_color = Color.html("#ecc8a4")
	akitsu.tdm_ok = false   # 960m 大图不进 TDM 圈定池
	akitsu.extra = {
		# 分区偏移(局部原点 → 世界坐标;与 tools/blender/assemble_jp_city.py 的 ZONES 同源)
		"zones": [
			{ "id": 1, "x": -300.0, "z": 60.0 },
			{ "id": 2, "x": -140.0, "z": -120.0 },
			{ "id": 3, "x": 50.0, "z": 170.0 },
			{ "id": 4, "x": 250.0, "z": 340.0 },
			{ "id": 5, "x": -270.0, "z": 340.0 },
			{ "id": 6, "x": 325.0, "z": -160.0 },
			{ "id": 7, "x": -80.0, "z": -360.0 },
			{ "id": 8, "x": 200.0, "z": -60.0 },
			{ "id": 9, "x": 0.0, "z": 0.0 },
			{ "id": 10, "x": 0.0, "z": 0.0 },
		],
		# 8 个主要征服点(非对称:西神社/中央车站/东港区/北寺院/南海滨)
		"flags": [
			{ "id": "A", "x": -300.0, "z": 60.0 },     # 秋津神社
			{ "id": "B", "x": 30.0, "z": 60.0 },       # 秋津站前(中央核心)
			{ "id": "C", "x": -140.0, "z": -100.0 },   # 本町商店街
			{ "id": "D", "x": 230.0, "z": 310.0 },     # 若叶住宅区
			{ "id": "E", "x": 340.0, "z": -120.0 },    # 秋津港
			{ "id": "F", "x": 180.0, "z": -20.0 },     # 临海新都心(办公)
			{ "id": "G", "x": -60.0, "z": -360.0 },    # 汐见海滨公园
			{ "id": "H", "x": -260.0, "z": 330.0 },    # 西念寺
		],
		# 出生点(2026-09-10 用户定):我方(us) 固定 G 汐见海滨 / 敌方(ru) 固定 D 若叶住宅,
		# 各 32 个点(离旗 11~35m 的净空环),玩家与 NPC 共用;载具同基地起(离旗 30~64m)。
		"spawns": {
			"us": [
				Vector3(-56.1, 0, -349.7), Vector3(-58.9, 0, -349.1), Vector3(-61.8, 0, -349.1),
				Vector3(-64.5, 0, -350.0), Vector3(-67.0, 0, -351.5), Vector3(-68.9, 0, -353.6),
				Vector3(-70.3, 0, -356.1), Vector3(-70.9, 0, -358.9), Vector3(-70.9, 0, -361.8),
				Vector3(-70.0, 0, -364.5), Vector3(-68.5, 0, -367.0), Vector3(-66.4, 0, -368.9),
				Vector3(-63.9, 0, -370.3), Vector3(-61.1, 0, -370.9), Vector3(-58.2, 0, -370.9),
				Vector3(-55.5, 0, -370.0), Vector3(-53.0, 0, -368.5), Vector3(-51.1, 0, -366.4),
				Vector3(-49.7, 0, -363.9), Vector3(-49.1, 0, -361.1), Vector3(-49.1, 0, -358.2),
				Vector3(-50.0, 0, -355.5), Vector3(-51.5, 0, -353.0), Vector3(-53.6, 0, -351.1),
				Vector3(-61.2, 0, -348.6), Vector3(-65.0, 0, -345.9), Vector3(-68.5, 0, -347.6),
				Vector3(-71.4, 0, -350.3), Vector3(-73.5, 0, -353.6), Vector3(-74.8, 0, -357.3),
				Vector3(-75.0, 0, -361.2), Vector3(-74.1, 0, -365.0),
			],
			"ru": [
				Vector3(233.9, 0, 320.3), Vector3(231.1, 0, 320.9), Vector3(228.2, 0, 320.9),
				Vector3(225.5, 0, 320.0), Vector3(223.0, 0, 318.5), Vector3(219.7, 0, 313.9),
				Vector3(219.1, 0, 311.1), Vector3(219.1, 0, 308.2), Vector3(220.0, 0, 305.5),
				Vector3(221.5, 0, 303.0), Vector3(226.1, 0, 299.7), Vector3(228.9, 0, 299.1),
				Vector3(231.8, 0, 299.1), Vector3(234.5, 0, 300.0), Vector3(237.0, 0, 301.5),
				Vector3(238.9, 0, 303.6), Vector3(240.9, 0, 308.9), Vector3(240.9, 0, 311.8),
				Vector3(240.0, 0, 314.5), Vector3(238.5, 0, 317.0), Vector3(228.8, 0, 325.0),
				Vector3(225.0, 0, 324.1), Vector3(221.5, 0, 322.4), Vector3(218.6, 0, 319.7),
				Vector3(216.5, 0, 316.4), Vector3(215.2, 0, 312.7), Vector3(215.0, 0, 308.8),
				Vector3(215.9, 0, 305.0), Vector3(217.6, 0, 301.5), Vector3(220.3, 0, 298.6),
				Vector3(223.6, 0, 296.5), Vector3(227.3, 0, 295.2),
			],
		},
		# 载具出生(24 = 每侧 12:坦克×2 + 步战×3 + 吉普×7),全部固定在 G / D 基地
		"vehicles": [
			{ "x": -75.1, "z": -334.1, "yaw": 3.23, "type": "tank" },   # US-1
			{ "x": -81.3, "z": -338.9, "yaw": 3.39, "type": "tank" },   # US-2
			{ "x": -86.1, "z": -345.1, "yaw": 3.55, "type": "apc" },   # US-3
			{ "x": -97.7, "z": -346.6, "yaw": 3.71, "type": "apc" },   # US-4
			{ "x": -96.1, "z": -377.2, "yaw": 3.87, "type": "apc" },   # US-5
			{ "x": -90.4, "z": -385.9, "yaw": 3.23, "type": "jeep" },   # US-6
			{ "x": -105.7, "z": -384.9, "yaw": 3.39, "type": "jeep" },   # US-7
			{ "x": -97.7, "z": -395.8, "yaw": 3.55, "type": "jeep" },   # US-8
			{ "x": -87.1, "z": -404.4, "yaw": 3.71, "type": "jeep" },   # US-9
			{ "x": -74.7, "z": -422.3, "yaw": 3.87, "type": "jeep" },   # US-10
			{ "x": -58.1, "z": -424.0, "yaw": 3.23, "type": "jeep" },   # US-11
			{ "x": -41.6, "z": -421.3, "yaw": 3.39, "type": "jeep" },   # US-12
			{ "x": 214.9, "z": 335.9, "yaw": 0.09, "type": "tank" },   # RU-1
			{ "x": 208.7, "z": 331.1, "yaw": 0.25, "type": "tank" },   # RU-2
			{ "x": 201.0, "z": 317.6, "yaw": 0.41, "type": "apc" },   # RU-3
			{ "x": 192.3, "z": 323.4, "yaw": 0.57, "type": "apc" },   # RU-4
			{ "x": 190.1, "z": 313.2, "yaw": 0.73, "type": "apc" },   # RU-5
			{ "x": 207.3, "z": 277.1, "yaw": 0.09, "type": "jeep" },   # RU-6
			{ "x": 184.3, "z": 285.1, "yaw": 0.25, "type": "jeep" },   # RU-7
			{ "x": 192.3, "z": 274.2, "yaw": 0.41, "type": "jeep" },   # RU-8
			{ "x": 202.9, "z": 265.6, "yaw": 0.57, "type": "jeep" },   # RU-9
			{ "x": 231.9, "z": 246.0, "yaw": 0.73, "type": "jeep" },   # RU-10
			{ "x": 248.4, "z": 248.7, "yaw": 0.09, "type": "jeep" },   # RU-11
			{ "x": 263.6, "z": 255.5, "yaw": 0.25, "type": "jeep" },   # RU-12
			# 基地快速反应摩托(2026-09-11 新增: 960m 图需要快穿插单位)
			{ "x": -76.2, "z": -352.4, "yaw": 3.55, "type": "motorcycle" },  # US-M1
			{ "x": -80.6, "z": -357.0, "yaw": 3.71, "type": "motorcycle" },  # US-M2
			{ "x": -71.8, "z": -357.9, "yaw": 3.39, "type": "motorcycle" },  # US-M3
			{ "x": 222.4, "z": 251.0, "yaw": 0.41, "type": "motorcycle" },   # RU-M1
			{ "x": 228.0, "z": 245.6, "yaw": 0.57, "type": "motorcycle" },   # RU-M2
			{ "x": 219.0, "z": 244.8, "yaw": 0.73, "type": "motorcycle" },   # RU-M3
			# 旗点就近载具(用户: "刷的载具要多一些") —— 每面中立旗旁 1 吉普 + 1 摩托,
			# 距旗 20~25m, 便于夺点后快速转场; 具体格子由 safe_spawn_pos 自动避障吸附。
			{ "x": -322.0, "z": 42.0, "yaw": 1.57, "type": "jeep" },          # A 神社
			{ "x": -278.0, "z": 42.0, "yaw": 1.57, "type": "motorcycle" },
			{ "x": 52.0, "z": 42.0, "yaw": 1.57, "type": "jeep" },             # B 站前
			{ "x": 8.0, "z": 42.0, "yaw": 1.57, "type": "motorcycle" },
			{ "x": -118.0, "z": -118.0, "yaw": 0.79, "type": "jeep" },         # C 商店街
			{ "x": -162.0, "z": -118.0, "yaw": 0.79, "type": "motorcycle" },
			{ "x": 362.0, "z": -138.0, "yaw": 5.50, "type": "jeep" },          # E 秋津港
			{ "x": 318.0, "z": -138.0, "yaw": 5.50, "type": "motorcycle" },
			{ "x": 158.0, "z": -38.0, "yaw": 2.36, "type": "jeep" },           # F 临海新都心
			{ "x": 202.0, "z": -38.0, "yaw": 2.36, "type": "motorcycle" },
			{ "x": -238.0, "z": 312.0, "yaw": 3.93, "type": "jeep" },          # H 西念寺
			{ "x": -282.0, "z": 312.0, "yaw": 3.93, "type": "motorcycle" },
		],
		# 每队 AI 数:秋津市 960m 大图 → 64 v 64(玩家占我方 1 席,故我方 AI=63)
		"bot_per_team": 63,
	}
	MD["akitsu"] = akitsu

	return MD


static var _maps: Dictionary = {}


static func M() -> Dictionary:
	if _maps.is_empty():
		_maps = build_maps()
	return _maps

