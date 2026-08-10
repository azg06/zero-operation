class_name TerrainTextures
## 地面/立面程序化贴图合成(对应 map.js 的 makeGround / makeBtGround / facadeTexture)

const S := 2048


static func _photo(name: String) -> Image:
	# [FIX 8/9] 不加载 4K HD 贴图:get_image() 需把大纹理从 VRAM 读回,
	# 在导出版(exe,贴图被重压缩)上触发驱动级访问冲突(0xC0000005);
	# CPU 合成路径固定用旧贴图,HD 4K 贴图仅走 GPU 端材质路径(_std_tex/layers)
	var t: Texture2D = load("res://textures/" + name + "_diff.jpg")
	var img := t.get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _html(c: String) -> Color:
	return Color.html(c)


## 战场痕迹:弹坑焦痕 + 裂缝
static func battle_scars(img: Image, s: int, alpha := 1.0) -> void:
	for i in 24:
		var x := randf() * s
		var y := randf() * s
		var r := 20.0 + randf() * 55.0
		ImgDraw.gradient_circle(img, x, y, r, [
			[0.0, Color(0.055, 0.047, 0.04, 0.8 * alpha)],
			[0.55, Color(0.086, 0.075, 0.063, 0.4 * alpha)],
			[1.0, Color(0, 0, 0, 0)],
		])
	for i in 34:
		var col := Color(0.07, 0.063, 0.055, (0.3 + randf() * 0.3) * alpha)
		var lw := 1.0 + randf() * 2.5
		var x := randf() * s
		var y := randf() * s
		for j in 4:
			var nx: float = x + (randf() - 0.5) * 120
			var ny: float = y + (randf() - 0.5) * 120
			ImgDraw.thick_line(img, x, y, nx, ny, lw, col)
			x = nx
			y = ny


static func _block_edges(road: float) -> Array:
	var B := road * 2 - 18
	var r7 := road + 7
	return [-B, -r7, -road + 7, -7, 7, road - 7, r7, B]


## 征服模式地面(城市/沙漠/雪地)
static func make_ground(theme: String, size: float, road: float) -> ImageTexture:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var base := _html("#3d3f42") if theme == "city" else (_html("#c2a068") if theme == "desert" else _html("#e2e8ee"))
	img.fill(base)
	# 照片平铺
	var photo := _photo("asphalt_02" if theme == "city" else ("sand_01" if theme == "desert" else "snow_02"))
	ImgDraw.tile_draw(img, photo, 10 if theme == "city" else 8)
	# 道路(以全局透明度绘制在照片上)
	var ga := 0.75 if theme == "city" else 0.9
	var w2t := func(x: float) -> float: return (x + size / 2.0) / size * S
	if theme == "city":
		var edges := _block_edges(road)
		var block_col := Color(0.274, 0.282, 0.298, 0.9 * ga)
		var i := 0
		while i < edges.size():
			var j := 0
			while j < edges.size():
				ImgDraw.alpha_rect(img, w2t.call(edges[i]), w2t.call(edges[j]),
					(edges[i + 1] - edges[i]) / size * S, (edges[j + 1] - edges[j]) / size * S, block_col)
				j += 2
			i += 2
		var road_col := Color(0.15, 0.157, 0.172, 0.92 * ga)
		for r in [-road, 0.0, road]:
			ImgDraw.alpha_rect(img, w2t.call(r - 7), 0, 14.0 / size * S, S, road_col)
			ImgDraw.alpha_rect(img, 0, w2t.call(r - 7), S, 14.0 / size * S, road_col)
		# 虚线车道线
		var dash_col := Color(0.54, 0.51, 0.35, 1.0 * ga)
		var dash := 0
		while dash < S:
			for r in [-road, 0.0, road]:
				ImgDraw.alpha_rect(img, w2t.call(r) - 2, dash, 4, 24, dash_col)
				ImgDraw.alpha_rect(img, dash, w2t.call(r) - 2, 24, 4, dash_col)
			dash += 54
	else:
		# 沙漠/雪地:压实路 + 车辙
		var road_col := Color(0.588, 0.486, 0.314, 0.55 * ga) if theme == "desert" else Color(0.588, 0.612, 0.643, 0.6 * ga)
		for r in [-road, 0.0, road]:
			ImgDraw.alpha_rect(img, w2t.call(r - 7), 0, 14.0 / size * S, S, road_col)
			ImgDraw.alpha_rect(img, 0, w2t.call(r - 7), S, 14.0 / size * S, road_col)
		var rut_col := Color(0.353, 0.275, 0.157, 0.5 * ga) if theme == "desert" else Color(0.275, 0.29, 0.314, 0.45 * ga)
		for r in [-road, 0.0, road]:
			for off in [-3.0, 3.0]:
				ImgDraw.alpha_rect(img, w2t.call(r + off) - 3, 0, 6, S, rut_col)
				ImgDraw.alpha_rect(img, 0, w2t.call(r + off) - 3, S, 6, rut_col)
	# 旗帜广场(5 点)
	for f in [[-road, -road], [road, -road], [0.0, 0.0], [-road, road], [road, road]]:
		var plaza_col := Color(0.333, 0.322, 0.298, 0.9 * ga) if theme == "city" else (
			Color(0.627, 0.549, 0.392, 0.7 * ga) if theme == "desert" else Color(0.667, 0.69, 0.714, 0.75 * ga))
		ImgDraw.alpha_circle(img, w2t.call(f[0]), w2t.call(f[1]), 16.0 / size * S, plaza_col)
		# 白边描圈:薄环近似
		var ring_col := Color(1, 1, 1, 0.25 * ga)
		var rr := 16.0 / size * S
		for k in 40:
			var a0 := k / 40.0 * TAU
			var a1 := (k + 1) / 40.0 * TAU
			ImgDraw.thick_line(img, w2t.call(f[0]) + cos(a0) * rr, w2t.call(f[1]) + sin(a0) * rr,
				w2t.call(f[0]) + cos(a1) * rr, w2t.call(f[1]) + sin(a1) * rr, 4, ring_col)
	battle_scars(img, S, ga)
	return ImgDraw.to_texture(img)


## BR 山谷地面(草地基色 + 聚落土路 + 村庄广场 + 南北向河道;地图像素底)
static func make_br_ground(T) -> ImageTexture:
	var size: float = T.size
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(_html("#4e603c"))
	# 沙地照片平铺作底(无草地照片),叠加草绿基色
	var photo := _photo("sand_01")
	ImgDraw.tile_draw(img, photo, 14)
	ImgDraw.overlay(img, Color(_html("#4e603c"), 0.82))
	var w2t := func(x: float) -> float: return (x + size / 2.0) / size * S
	# 聚落间土路(先画,河道带后覆盖形成两处渡口)
	var roads: Array = T.extra.get("roads", [])
	var road_col := Color(0.47, 0.38, 0.24, 0.55)
	var rut_col := Color(0.33, 0.26, 0.15, 0.4)
	for seg in roads:
		var x0: float = seg[0]
		var z0: float = seg[1]
		var x1: float = seg[2]
		var z1: float = seg[3]
		ImgDraw.thick_line(img, w2t.call(x0), w2t.call(z0), w2t.call(x1), w2t.call(z1), 30, road_col)
		ImgDraw.thick_line(img, w2t.call(x0), w2t.call(z0), w2t.call(x1), w2t.call(z1), 6, rut_col)
	# 村庄广场
	var plaza_col := Color(0.51, 0.42, 0.28, 0.5)
	for v in (T.extra.get("villages", []) as Array):
		ImgDraw.alpha_circle(img, w2t.call(v["x"]), w2t.call(v["z"]), 34.0 / size * S, plaza_col)
	# 河道(垂直带,x = T.river 向两侧渐变)
	var stops := [
		[0.0, Color(0.18, 0.31, 0.26, 0.35)],
		[0.5, Color(0.13, 0.27, 0.31, 0.95)],
		[1.0, Color(0.18, 0.31, 0.26, 0.35)],
	]
	var band := 26.0 / size * S
	var x0r: float = w2t.call(T.river) - band * 0.5
	var strips := 24
	for k in strips:
		var t := float(k) / strips
		var col: Color
		if t < 0.5:
			col = (stops[0][1] as Color).lerp(stops[1][1], t * 2)
		else:
			col = (stops[1][1] as Color).lerp(stops[2][1], (t - 0.5) * 2)
		ImgDraw.alpha_rect(img, x0r + band * t, 0, band / strips + 1, S, col)
	battle_scars(img, S, 0.8)
	return ImgDraw.to_texture(img)


## 突破模式地面(照片平铺 + 中央进军路 + 目标广场 + 河道/海洋/雪斑)
static func make_bt_ground(T) -> ImageTexture:
	var size: float = T.size
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(T.base_color)
	# 照片平铺 + 基色覆盖
	var photo := _photo(T.ground_photo)
	ImgDraw.tile_draw(img, photo, T.tiles)
	ImgDraw.overlay(img, Color(T.base_color, 0.72))
	# 地貌绘制
	var w2t := func(x: float) -> float: return (x + size / 2.0) / size * S
	# 中央进军主路
	ImgDraw.alpha_rect(img, w2t.call(-8.0), 0, 16.0 / size * S, S, T.road_color)
	# 车辙
	for off in [-4.0, 4.0]:
		ImgDraw.alpha_rect(img, w2t.call(off) - 2.5, 0, 5, S, T.rut_color)
	# 目标点广场
	for sec in T.sectors:
		for o in sec:
			ImgDraw.alpha_circle(img, w2t.call(o["x"]), w2t.call(o["z"]), 17.0 / size * S, T.plaza_color)
			var ring_col := Color(1, 1, 1, 0.22)
			var rr := 17.0 / size * S
			for k in 40:
				var a0 := k / 40.0 * TAU
				var a1 := (k + 1) / 40.0 * TAU
				ImgDraw.thick_line(img, w2t.call(o["x"]) + cos(a0) * rr, w2t.call(o["z"]) + sin(a0) * rr,
					w2t.call(o["x"]) + cos(a1) * rr, w2t.call(o["z"]) + sin(a1) * rr, 4, ring_col)
	# 两端基地区
	for bz in [-size / 2.0 + 16, size / 2.0 - 16]:
		ImgDraw.alpha_circle(img, w2t.call(0.0), w2t.call(bz), 20.0 / size * S, T.plaza_color)
	# 河道(丛林)
	if T.river != null:
		var stops := [
			[0.0, Color(0.18, 0.31, 0.26, 0.35)],
			[0.5, Color(0.13, 0.27, 0.31, 0.95)],
			[1.0, Color(0.18, 0.31, 0.26, 0.35)],
		]
		var y0: float = w2t.call(T.river - 9)
		var band := 18.0 / size * S
		var strips := 24
		for k in strips:
			var t := float(k) / strips
			var col: Color
			if t < 0.5:
				col = (stops[0][1] as Color).lerp(stops[1][1], t * 2)
			else:
				col = (stops[1][1] as Color).lerp(stops[2][1], (t - 0.5) * 2)
			ImgDraw.alpha_rect(img, 0, y0 + band * t, S, band / strips + 1, col)
	# 两侧海洋(港口)
	if T.sea:
		var sea_col := Color(0.15, 0.227, 0.33, 0.96)
		ImgDraw.alpha_rect(img, 0, 0, w2t.call(-104.0), S, sea_col)
		ImgDraw.alpha_rect(img, w2t.call(104.0), 0, S - w2t.call(104.0), S, sea_col)
		var foam_col := Color(0.78, 0.84, 0.88, 0.5)
		ImgDraw.alpha_rect(img, w2t.call(-104.0) - 3, 0, 6, S, foam_col)
		ImgDraw.alpha_rect(img, w2t.call(104.0) - 3, 0, 6, S, foam_col)
	# 雪斑(雷达站)
	if T.night:
		for i in 60:
			ImgDraw.gradient_circle(img, randf() * S, randf() * S, 14 + randf() * 46, [
				[0.0, Color(0.91, 0.94, 0.96, 0.75)],
				[1.0, Color(0.91, 0.94, 0.96, 0)],
			])
	battle_scars(img, S, 1.0)
	return ImgDraw.to_texture(img)


## 建筑立面:混凝土照片底 + 程序化窗户
static func facade_texture(base: String, lit: float, floors := 8) -> ImageTexture:
	var FS2 := 256
	var img := Image.create(FS2, FS2, false, Image.FORMAT_RGBA8)
	img.fill(_html(base))
	var photo := _photo("concrete_floor_02")
	ImgDraw.tile_draw(img, photo, 2)
	ImgDraw.overlay(img, Color(_html(base), 0.55))
	# 窗户
	var cols := 6
	var ww := float(FS2) / cols
	var wh := float(FS2) / floors
	for x in cols:
		for y in floors:
			var is_lit := randf() < lit
			var col := _html("#c8b070") if is_lit else (_html("#141a22") if randf() < 0.5 else _html("#1e2630"))
			var wx: float = x * ww + ww * 0.22
			var wy: float = y * wh + wh * 0.22
			ImgDraw.alpha_rect(img, wx, wy, ww * 0.56, wh * 0.5, col)
			ImgDraw.alpha_rect(img, wx, y * wh + wh * 0.72, ww * 0.56, 3, Color(0, 0, 0, 0.35))
	return ImgDraw.to_texture(img)


## 灯光光晕贴图(暗夜雷达站)
static func glow_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	ImgDraw.gradient_circle(img, 32, 32, 31, [
		[0.0, Color(0.75, 0.86, 1, 0.9)],
		[0.4, Color(0.55, 0.71, 0.94, 0.25)],
		[1.0, Color(0.47, 0.63, 0.86, 0)],
	])
	return ImgDraw.to_texture(img)


## ==================== 3A 地面:多层纹理混合着色器 ====================
## 底层为整图绘制的路线图(道路/广场/河道),细节层按世界坐标重复平铺,
## 以"大尺度噪声斑块 + 高度 + 权重"混合,配合宏观明暗打破平铺感。

static var _macro_noise_tex: ImageTexture = null


static func _make_noise_tex(seed_v: int, sz := 256, oct := 4) -> ImageTexture:
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = 1.0 / sz * 3.0
	fn.fractal_octaves = oct
	fn.fractal_lacunarity = 2.2
	fn.fractal_gain = 0.5
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var v := fn.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImgDraw.to_texture(img)


static func _macro_noise() -> ImageTexture:
	if _macro_noise_tex == null:
		_macro_noise_tex = _make_noise_tex(1337)
	return _macro_noise_tex


## 各主题的地面细节层配置(a 岩层 / b 沙-雪-泥 / c 混凝土-沥青)
## hs = 高度场→着色器高度比例(height_scale):起伏越大越放大,避免高峰全裸岩。
## snow 雪山坡地(最高 ~8m)放大到 10 → 山脊仍保雪层;bt_jungle 丘陵(3-5m)放大到 5 → 丘顶保沙色。
static func _layer_cfg(theme: String) -> Dictionary:
	var cfgs := {
		"city": { "a": "rock_04", "b": "concrete_floor_02", "c": "rough_concrete",
			"wa": 0.85, "wb": 0.4, "wc": 0.55, "uv": 0.17,
			"ta": Color(0.97, 0.95, 0.92), "tb": Color(1.0, 1.0, 1.0), "tc": Color(0.98, 0.98, 1.0) },
		"desert": { "a": "rock_04", "b": "sand_01", "c": "rough_concrete",
			"wa": 0.9, "wb": 0.55, "wc": 0.12, "uv": 0.13,
			"ta": Color(0.99, 0.95, 0.88), "tb": Color(1.03, 0.98, 0.88), "tc": Color(0.96, 0.95, 0.93) },
		"snow": { "a": "rock_04", "b": "snow_02", "c": "rough_concrete",
			"wa": 0.8, "wb": 0.55, "wc": 0.3, "uv": 0.15, "hs": 10.0,
			"ta": Color(0.874, 0.883, 0.902), "tb": Color(0.975, 0.975, 0.994), "tc": Color(0.846, 0.856, 0.883) },
		"bt_jungle": { "a": "rock_04", "b": "sand_01", "c": "asphalt_02",
			"wa": 0.7, "wb": 0.6, "wc": 0.2, "uv": 0.16, "hs": 5.0,
			"ta": Color(0.96, 0.94, 0.88), "tb": Color(1.0, 0.94, 0.78), "tc": Color(0.85, 0.86, 0.88) },
		"bt_harbor": { "a": "rock_04", "b": "sand_01", "c": "asphalt_02",
			"wa": 0.5, "wb": 0.55, "wc": 0.6, "uv": 0.16,
			"ta": Color(0.93, 0.92, 0.9), "tb": Color(0.98, 0.95, 0.85), "tc": Color(0.8, 0.82, 0.85) },
		"bt_peak": { "a": "rock_04", "b": "snow_02", "c": "rough_concrete",
			"wa": 0.9, "wb": 0.55, "wc": 0.45, "uv": 0.14,
			"ta": Color(0.93, 0.94, 0.96), "tb": Color(1.07, 1.07, 1.09), "tc": Color(0.88, 0.89, 0.92) },
		"br_valley": { "a": "rock_04", "b": "sand_01", "c": "rough_concrete",
			"wa": 0.5, "wb": 0.55, "wc": 0.15, "uv": 0.1,
			"ta": Color(0.92, 0.92, 0.88), "tb": Color(0.98, 0.94, 0.8), "tc": Color(0.88, 0.89, 0.91) },
	}
	return cfgs.get(theme, cfgs["city"])


static var _ground_shader_code := """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D map_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D layer_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_b : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_c : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.16;
uniform vec4 tint_a : source_color = vec4(1.0);
uniform vec4 tint_b : source_color = vec4(1.0);
uniform vec4 tint_c : source_color = vec4(1.0);
uniform float weight_a = 0.8;
uniform float weight_b = 0.35;
uniform float weight_c = 0.5;
uniform float macro_amp = 0.13;
uniform float height_scale = 3.0;
uniform float micro_detail = 0.3;

varying vec2 v_uv;
varying vec2 v_wp;
varying float v_h;

void vertex() {
	v_uv = UV;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wp = wp.xz;
	v_h = wp.y;
}

void fragment() {
	vec3 base = texture(map_tex, v_uv).rgb;
	vec2 wu = v_wp * uv_scale;
	float n1 = texture(noise_tex, v_wp * 0.022 + 0.17).r;
	float n2 = texture(noise_tex, v_wp * 0.088 + 0.61).r;
	float n3 = texture(noise_tex, wu * 2.2 + 0.33).r;
	float h = v_h / height_scale;
	float w_a = clamp((n1 - 0.40) * 2.0 + (n2 - 0.52) * 0.8 + step(0.68, n1) * 0.3, 0.0, 1.0) * weight_a;
	float w_b = clamp((0.56 - n1) * 1.6 + (0.5 - h) * 0.6, 0.0, 1.0) * weight_b;
	float w_c = clamp((n2 - 0.44) * 2.2 + smoothstep(0.4, 0.85, n1) * 0.25, 0.0, 1.0) * weight_c;
	w_b = min(w_b, 1.0 - w_a);
	w_c = min(w_c, 1.0 - w_a - w_b);
	vec3 col = base;
	col = mix(col, texture(layer_a, wu).rgb * tint_a.rgb, w_a);
	col = mix(col, texture(layer_b, wu * 1.7).rgb * tint_b.rgb, w_b);
	col = mix(col, texture(layer_c, wu * 0.85).rgb * tint_c.rgb, w_c);
	col *= 0.9 + n1 * macro_amp * 2.0 + n2 * macro_amp * 0.8 + n3 * macro_amp * 0.4;
	ALBEDO = col;
	ROUGHNESS = 0.9 + n2 * 0.08;
	vec3 micro = texture(noise_tex, wu * 3.0 + 0.9).rgb - 0.5;
	NORMAL = normalize(NORMAL + micro * micro_detail * 1.5);
}
"""


## 生成地面多层混合材质(替代单一 StandardMaterial)
static func make_ground_material(theme: String, T) -> ShaderMaterial:
	var map_tex: ImageTexture
	if T.mode == "breakthrough":
		map_tex = make_bt_ground(T)
	elif T.mode == "br":
		map_tex = make_br_ground(T)
	else:
		map_tex = make_ground(theme, T.size, T.road)
	var cfg := _layer_cfg(theme)
	var sh := Shader.new()
	sh.code = _ground_shader_code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("map_tex", map_tex)
	mat.set_shader_parameter("layer_a", WorldBuilder._load_tex(cfg.a, "diff"))
	mat.set_shader_parameter("layer_b", WorldBuilder._load_tex(cfg.b, "diff"))
	mat.set_shader_parameter("layer_c", WorldBuilder._load_tex(cfg.c, "diff"))
	mat.set_shader_parameter("noise_tex", _macro_noise())
	mat.set_shader_parameter("uv_scale", cfg.uv)
	mat.set_shader_parameter("tint_a", cfg.ta)
	mat.set_shader_parameter("tint_b", cfg.tb)
	mat.set_shader_parameter("tint_c", cfg.tc)
	mat.set_shader_parameter("weight_a", cfg.wa)
	mat.set_shader_parameter("weight_b", cfg.wb)
	mat.set_shader_parameter("weight_c", cfg.wc)
	mat.set_shader_parameter("macro_amp", 0.13)
	mat.set_shader_parameter("height_scale", cfg.get("hs", 4.0))
	mat.set_shader_parameter("micro_detail", 0.3)
	return mat


## ==================== 3A 水体:折射 + 天空反射 + 波动法线着色器 ====================
static var _water_shader_code := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 deep_col : source_color = vec4(0.02, 0.08, 0.09, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.1, 0.22, 0.2, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.6, 0.7, 0.8, 1.0);
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float wave_amp = 0.18;
uniform float wave_speed = 0.9;
uniform float wave_scale = 3.0;
uniform float roughness = 0.05;
uniform float refraction = 0.09;
uniform float fresnel_power = 3.2;
uniform float reflection_strength = 0.45;
uniform float alpha = 0.97;

void fragment() {
	vec2 p = VERTEX.xz * wave_scale;
	float t = TIME * wave_speed;
	vec3 g = vec3(0.0);
	g.x += sin(p.x * 1.0 + t * 1.0) * 0.5;
	g.z += cos(p.y * 1.0 + t * 1.3) * 0.5;
	g.x += sin(p.x * 2.3 + t * 1.7 + 2.0) * 0.3;
	g.z += cos(p.y * 1.8 + t * 2.1 + 1.0) * 0.3;
	g.x += sin(p.x * 5.0 + t * 2.6 + 4.0) * 0.13;
	g.z += cos(p.y * 4.3 + t * 3.1 + 3.0) * 0.13;
	NORMAL = normalize(NORMAL + g * wave_amp);
	vec3 V = normalize(VIEW);
	float ndv = max(dot(NORMAL, V), 0.0);
	float fres = pow(1.0 - ndv, fresnel_power);
	vec3 refl = texture(screen_tex, SCREEN_UV + g.xz * refraction * 0.35).rgb;
	vec3 col = mix(shallow_col.rgb, deep_col.rgb, clamp(fres * 1.4 + 0.25, 0.0, 1.0));
	col = mix(col, refl * sky_tint.rgb, fres * reflection_strength);
	ALBEDO = col;
	ROUGHNESS = roughness + (1.0 - ndv) * 0.2;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = alpha;
}
"""


static func make_water_material(deep: Color, shallow: Color, amp := 0.16, speed := 0.9) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = _water_shader_code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("deep_col", deep)
	mat.set_shader_parameter("shallow_col", shallow)
	mat.set_shader_parameter("wave_amp", amp)
	mat.set_shader_parameter("wave_speed", speed)
	return mat
