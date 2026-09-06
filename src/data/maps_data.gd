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

	return MD


static var _maps: Dictionary = {}


static func M() -> Dictionary:
	if _maps.is_empty():
		_maps = build_maps()
	return _maps

