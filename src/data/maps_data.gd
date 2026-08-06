class_name MapsData
## 地图主题数据(对应 map.js 中的 MAPS)

class MapDef extends RefCounted:
	var id := ""
	var cn := ""
	var mode := "conquest"            # conquest | breakthrough
	var size := 320.0
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
	MD["city"] = city

	var desert := MapDef.new()
	desert.id = "desert"; desert.cn = "沙漠油站"; desert.size = 320; desert.road = 80
	desert.sky_top = Color.html("#6a9ac8"); desert.sky_mid = Color.html("#d8c8a0"); desert.sky_bot = Color.html("#e8c890")
	desert.fog_color = Color.html("#d8c09a"); desert.fog_near = 50; desert.fog_far = 400
	desert.hemi_sky = Color.html("#ffe8c8"); desert.hemi_ground = Color.html("#8a6a4a"); desert.hemi_energy = 1.1
	desert.sun_color = Color.html("#ffe0b0"); desert.sun_energy = 1.8; desert.sun_pos = Vector3(100, 120, 40)
	desert.cloud_color = Color.html("#fff0d8")
	MD["desert"] = desert

	var snow := MapDef.new()
	snow.id = "snow"; snow.cn = "雪山哨站"; snow.size = 320; snow.road = 80
	snow.sky_top = Color.html("#7a9ac0"); snow.sky_mid = Color.html("#c0d0e0"); snow.sky_bot = Color.html("#e0e8f0")
	snow.fog_color = Color.html("#c8d4e0"); snow.fog_near = 40; snow.fog_far = 320
	snow.hemi_sky = Color.html("#d0e0f0"); snow.hemi_ground = Color.html("#6a7078"); snow.hemi_energy = 1.2
	snow.sun_color = Color.html("#f0f4ff"); snow.sun_energy = 1.3; snow.sun_pos = Vector3(60, 140, 80)
	snow.cloud_color = Color.html("#f0f4f8")
	MD["snow"] = snow

	var jungle := MapDef.new()
	jungle.id = "bt_jungle"; jungle.cn = "丛林河谷"; jungle.mode = "breakthrough"
	jungle.size = 360; jungle.amp = 1.3
	jungle.sky_top = Color.html("#4a7ab0"); jungle.sky_mid = Color.html("#98c8a0"); jungle.sky_bot = Color.html("#d8e0b0")
	jungle.fog_color = Color.html("#9ab896"); jungle.fog_near = 38; jungle.fog_far = 280
	jungle.hemi_sky = Color.html("#cfe8c8"); jungle.hemi_ground = Color.html("#36452e"); jungle.hemi_energy = 1.15
	jungle.sun_color = Color.html("#fff0c0"); jungle.sun_energy = 1.5; jungle.sun_pos = Vector3(70, 135, 55)
	jungle.cloud_color = Color.html("#f0f8e0")
	jungle.ground_photo = "rock_04"; jungle.tiles = 9; jungle.base_color = Color.html("#55663c")
	jungle.road_color = Color(0.47, 0.39, 0.26, 0.55); jungle.rut_color = Color(0.29, 0.24, 0.15, 0.5)
	jungle.plaza_color = Color(0.51, 0.44, 0.29, 0.6)
	jungle.river = -55.0
	jungle.sectors = [
		[{ "id": "A", "x": -26, "z": -110 }, { "id": "B", "x": 24, "z": -106 }],
		[{ "id": "A", "x": -24, "z": -6 }, { "id": "B", "x": 26, "z": 2 }],
		[{ "id": "A", "x": -26, "z": 106 }, { "id": "B", "x": 24, "z": 110 }],
	]
	MD["bt_jungle"] = jungle

	var harbor := MapDef.new()
	harbor.id = "bt_harbor"; harbor.cn = "暮港码头"; harbor.mode = "breakthrough"
	harbor.size = 360; harbor.amp = 0.9
	harbor.sky_top = Color.html("#3a3a68"); harbor.sky_mid = Color.html("#b86a58"); harbor.sky_bot = Color.html("#e8a068")
	harbor.fog_color = Color.html("#9a7a72"); harbor.fog_near = 55; harbor.fog_far = 340
	harbor.hemi_sky = Color.html("#e8b090"); harbor.hemi_ground = Color.html("#3a3a4e"); harbor.hemi_energy = 1.05
	harbor.sun_color = Color.html("#ffb070"); harbor.sun_energy = 1.35; harbor.sun_pos = Vector3(-95, 55, 45)
	harbor.cloud_color = Color.html("#d8a08a")
	harbor.ground_photo = "asphalt_02"; harbor.tiles = 10; harbor.base_color = Color.html("#34363a")
	harbor.road_color = Color(0.24, 0.24, 0.26, 0.9); harbor.rut_color = Color(0.54, 0.51, 0.35, 0.9)
	harbor.plaza_color = Color(0.29, 0.28, 0.26, 0.9)
	harbor.sea = true
	harbor.sectors = [
		[{ "id": "A", "x": -28, "z": -110 }, { "id": "B", "x": 26, "z": -106 }],
		[{ "id": "A", "x": -25, "z": -4 }, { "id": "B", "x": 27, "z": 4 }],
		[{ "id": "A", "x": -27, "z": 106 }, { "id": "B", "x": 25, "z": 110 }],
	]
	MD["bt_harbor"] = harbor

	var peak := MapDef.new()
	peak.id = "bt_peak"; peak.cn = "暗夜雷达站"; peak.mode = "breakthrough"
	peak.size = 360; peak.amp = 1.6
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

	return MD


static var _maps: Dictionary = {}


static func M() -> Dictionary:
	if _maps.is_empty():
		_maps = build_maps()
	return _maps
