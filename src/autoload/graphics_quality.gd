extends Node
## 画质预设注册器(基于 graphics_quality_registry.gd 游戏安全版)
## 4 级预设 + 硬件检测;只应用与游戏兼容的画质项,不覆盖每图主题定制的
## tonemap/背景/雾/环境光;与 G.settings 同步后由 main.apply_graphics 统一收尾

enum Level { LOW, MEDIUM, HIGH, ULTRA }

## 各级与游戏字段的映射(仅游戏支持的项)
const PRESETS := {
	Level.LOW: {
		"shadows": 1024, "ssao": false, "fxaa": true, "taa": false, "scale": 0.75, "aniso": 2,
		"ssil": false, "ssr": false, "glow": false, "fog": 0.8, "particles": 0.4,
		"fx_scale": 0.6,
	},
	Level.MEDIUM: {
		"shadows": 2048, "ssao": true, "fxaa": true, "taa": false, "scale": 1.0, "aniso": 4,
		"ssil": false, "ssr": false, "glow": true, "fog": 1.0, "particles": 0.7,
		"fx_scale": 0.8,
	},
	Level.HIGH: {
		"shadows": 4096, "ssao": true, "fxaa": false, "taa": true, "scale": 1.0, "aniso": 8,
		"ssil": true, "ssr": false, "glow": true, "fog": 1.0, "particles": 1.0,
		"fx_scale": 1.0,
	},
	Level.ULTRA: {
		"shadows": 8192, "ssao": true, "fxaa": false, "taa": true, "scale": 1.0, "aniso": 16,
		"ssil": true, "ssr": true, "glow": true, "fog": 1.1, "particles": 1.0,
		"fx_scale": 1.0,
	},
}

var current_level: int = Level.HIGH


func _ready() -> void:
	current_level = _detect_level()
	print("[GraphicsQuality] 硬件检测画质等级: ", _level_name(current_level))


func _detect_level() -> int:
	var gpu := ""
	if RenderingServer.has_method("get_video_adapter_name"):
		gpu = RenderingServer.get_video_adapter_name().to_lower()
	print("[GraphicsQuality] GPU: ", gpu)
	# 旗舰/高性能(含 RTX 50/40/30 高端、RX 9000/7000 高端)
	for k in ["rtx 5090", "rtx 5080", "rtx 5070 ti", "rtx 5070", "rtx 4090", "rtx 4080", "rtx 4070 ti", "rtx 4070",
			"rtx 3090", "rtx 3080 ti", "rtx 3080", "rx 9070 xt", "rx 9070", "rx 7900 xtx", "rx 7900 xt", "rx 7900",
			"rx 7800 xt", "rx 7800", "quadro rtx"]:
		if gpu.contains(k):
			return Level.ULTRA
	# 主流性能
	for k in ["rtx 5060 ti", "rtx 5060", "rtx 4060 ti", "rtx 4060", "rtx 3070 ti", "rtx 3070", "rtx 3060 ti", "rtx 3060",
			"rtx 2080 ti", "rtx 2080", "rtx 2070", "rtx 2060", "gtx 1080 ti", "gtx 1080", "gtx 1070",
			"rx 7700 xt", "rx 7700", "rx 6800 xt", "rx 6800", "rx 6700 xt", "rx 6700", "gtx 1660", "gtx 1660 ti"]:
		if gpu.contains(k):
			return Level.HIGH
	# 入门/核显
	for k in ["intel", "iris", "uhd", "arc", "a380", "a750", "a770", "vega", "gtx 1060", "gtx 1050", "gtx 960", "gtx 970", "mx"]:
		if gpu.contains(k):
			return Level.LOW
	return Level.MEDIUM


func _level_name(lv: int) -> String:
	return ["LOW", "MEDIUM", "HIGH", "ULTRA"][lv]


## 应用预设:同步 G.settings(主画质项) + 安全后处理直写 env
func apply_preset(lv: int) -> void:
	current_level = lv
	var p: Dictionary = PRESETS[lv]
	# 1) 同步到游戏设置(阴影/SSAO/FXAA/缩放/各向异性/雾/粒子)
	G.settings.shadows = p["shadows"]
	G.settings.ssao = p["ssao"]
	G.settings.fxaa = p["fxaa"]
	G.settings.scale = p["scale"]
	G.settings.aniso = p["aniso"]
	G.settings.fog = p["fog"]
	G.settings.particles = p["particles"]
	G.settings.fx_scale = p["fx_scale"]
	# 2) 安全后处理(SSIL/SSR/glow/adjustment,游戏未用到的项)
	if G.world_env != null and G.world_env.environment != null:
		var env := G.world_env.environment
		env.ssil_enabled = p["ssil"]
		env.ssr_enabled = p["ssr"]
		if p["ssr"]:
			env.ssr_max_steps = 32
			env.ssr_fade_out = 2.0
		env.glow_enabled = p["glow"]
		if p["glow"]:
			# Bloom 强度随档位:中档收敛,高档通透,超高档更过曝(战地式辉光)
			if lv == Level.ULTRA:
				env.glow_intensity = 0.42
				env.glow_strength = 0.72
				env.glow_bloom = 0.32
			else:
				env.glow_intensity = 0.35
				env.glow_strength = 0.7
				env.glow_bloom = 0.28
			env.glow_hdr_threshold = 1.05
		# SSAO 质量随档位:低档不开(见 PRESETS),中档低质量,高档以上高质量
		if p["ssao"]:
			env.ssao_enabled = true
			if lv >= Level.HIGH:
				env.ssao_intensity = 1.7
				env.ssao_radius = 1.5
				env.ssao_detail = 1.2
				env.ssao_horizon = 0.1
				env.ssao_sharpness = 0.98
			else:
				env.ssao_intensity = 1.3
				env.ssao_radius = 1.0
				env.ssao_detail = 0.6
				env.ssao_horizon = 0.08
				env.ssao_sharpness = 0.98
		# SSIL 强度:超高档更柔和自然
		if p["ssil"]:
			env.ssil_intensity = 1.4 if lv == Level.ULTRA else 1.1
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.06
		env.adjustment_saturation = 1.04
	# 3) 各向异性过滤 + MSAA(视口级)
	var vp := get_viewport()
	vp.anisotropic_filtering_level = p["aniso"]
	# 3b) 抗锯齿策略:高档用 TAA,低档用自定义 FXAA 层(与 main.apply_graphics 保持一致)
	vp.use_taa = p["taa"]
	# 4) 收尾:走游戏自己的画质应用(阴影图集/雾距/粒子质量)
	if G.apply_graphics.is_valid():
		G.apply_graphics.call()
	print("[GraphicsQuality] 已应用预设: ", _level_name(lv))


## 换图后重挂(环境被 world_builder 重建,重新应用安全后处理)
func reapply() -> void:
	apply_preset(current_level)


func save_config(path := "user://graphics.cfg") -> void:
	var c := ConfigFile.new()
	c.set_value("graphics", "level", current_level)
	c.save(path)


func load_config(path := "user://graphics.cfg") -> void:
	var c := ConfigFile.new()
	if c.load(path) == OK:
		current_level = int(c.get_value("graphics", "level", current_level))
