extends Node
## 画质预设注册器(基于 graphics_quality_registry.gd 游戏安全版)
## 4 级预设 + 硬件检测;只应用与游戏兼容的画质项,不覆盖每图主题定制的
## tonemap/背景/雾/环境光;与 G.settings 同步后由 main.apply_graphics 统一收尾

enum Level { LOW, MEDIUM, HIGH, ULTRA }

## 各级与游戏字段的映射(仅游戏支持的项)
## [3A 画质升级 8/9] ULTRA=阴影 4096 + SSR + SSIL + MSAA + 增强泛光;
## SDFGI 已移除(8/10 用户反馈:开启后阴影过黑、对比度过高,永久关闭)
## HIGH=阴影 4096+SSR;LOW/MEDIUM 保持收敛。BR 保护档/GPU 保护档不受影响(自动降回收敛值防驱动崩溃)。
## 阴影锯齿:方向光阴影图集分辨率最高 4096,保留 PCF 软阴影质量=3,
## 配合 main 里 G.sun.shadow_blur 柔化边缘,显著减少阴影边缘锯齿/闪烁。
const PRESETS := {
	Level.LOW: {
		"shadows": 1024, "ssao": false, "fxaa": true, "taa": false, "scale": 0.75, "aniso": 2,
		"ssil": false, "ssr": false, "sdfgi": false, "glow": false, "msaa": 0, "cinema": false,
		"fog": 0.8, "particles": 0.4, "fx_scale": 0.6, "vfog": 16,
	},
	Level.MEDIUM: {
		"shadows": 2048, "ssao": true, "fxaa": true, "taa": false, "scale": 1.0, "aniso": 4,
		"ssil": false, "ssr": false, "sdfgi": false, "glow": true, "msaa": 1, "cinema": true,
		"fog": 1.0, "particles": 0.7, "fx_scale": 0.8, "vfog": 32,
	},
	Level.HIGH: {
		"shadows": 4096, "ssao": true, "fxaa": false, "taa": true, "scale": 1.0, "aniso": 8,
		"ssil": false, "ssr": true, "sdfgi": false, "glow": true, "msaa": 2, "cinema": true,
		"fog": 1.0, "particles": 1.0, "fx_scale": 1.0, "vfog": 32,
	},
	Level.ULTRA: {
		"shadows": 4096, "ssao": true, "fxaa": false, "taa": true, "scale": 1.0, "aniso": 8,
		"ssil": false, "ssr": true, "sdfgi": false, "glow": true, "msaa": 2, "cinema": true,
		"fog": 1.1, "particles": 1.0, "fx_scale": 1.0, "vfog": 32,
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
	_apply_dict(PRESETS[lv], lv, _level_name(lv))


## 预设字典落地(lv 用于档位相关的强度分级:SSAO 质量/glow 强度/SSIL 强度)
func _apply_dict(p: Dictionary, lv: int, label: String) -> void:
	# 1) 同步到游戏设置(阴影/SSAO/FXAA/缩放/各向异性/雾/粒子 + 3A 升级项)
	G.settings.shadows = p["shadows"]
	G.settings.ssao = p["ssao"]
	G.settings.fxaa = p["fxaa"]
	G.settings.scale = p["scale"]
	G.settings.aniso = p["aniso"]
	G.settings.fog = p["fog"]
	G.settings.particles = p["particles"]
	G.settings.fx_scale = p["fx_scale"]
	G.settings.msaa = p.get("msaa", 0)
	G.settings.ssr = p.get("ssr", false)
	G.settings.ssil = p.get("ssil", false)
	G.settings.glow = p.get("glow", false)
	G.settings.cinema = p.get("cinema", false)
	# 2) 安全后处理(SSIL/SSR/glow/adjustment,游戏未用到的项)
	if G.world_env != null and G.world_env.environment != null:
		var env := G.world_env.environment
		env.ssil_enabled = p["ssil"]
		env.ssr_enabled = p["ssr"]
		if p["ssr"]:
			env.ssr_max_steps = 24
			env.ssr_fade_out = 2.0
			env.ssr_depth_tolerance = 0.25
		# [8/10] SDFGI 全局光照已移除:开启后阴影过黑、对比度过高(用户反馈),永久关闭
		env.sdfgi_enabled = false
		env.glow_enabled = p["glow"]
		if p["glow"]:
			# Bloom 强度随档位:ULTRA 略强,其余档收敛(8/10 修复雪地过曝:0.6/0.9/0.45→0.42/0.72/0.32)
			if lv == Level.ULTRA:
				env.glow_intensity = 0.42
				env.glow_strength = 0.72
				env.glow_bloom = 0.32
				env.glow_hdr_threshold = 1.0
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
		# 体积雾分辨率随预设统一应用(project.godot 默认 32;BR 保护档 32 同值)
		if p.has("vfog"):
			RenderingServer.environment_set_volumetric_fog_volume_size(int(p["vfog"]), 64)
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.06
		env.adjustment_saturation = 1.04
	# 3) 各向异性过滤 + MSAA(视口级;退出时根视口可能已销毁,跳过写)
	var vp := get_viewport()
	if vp != null:
		vp.anisotropic_filtering_level = p["aniso"]
		vp.msaa_3d = int(p.get("msaa", 0))
		# 3b) 抗锯齿策略:高档用 TAA,低档用自定义 FXAA 层(与 main.apply_graphics 保持一致)
		vp.use_taa = p["taa"]
	# 4) 收尾:走游戏自己的画质应用(阴影图集/雾距/粒子质量)
	if G.apply_graphics.is_valid():
		G.apply_graphics.call()
	print("[GraphicsQuality] 已应用预设: ", label)


## ---- [PERF] BR 大地图优化档(100 bot + 800m):基于 HIGH 档,阴影 2048、SSIL 关、SSR 关 ----
## 画质影响:阴影软阴影分辨率 4096→2048(远距阴影细节略降)、SSIL/SSR 关闭(间接光晕/反射消失);
## 保留 SSAO/TAA/Bloom/全分辨率/粒子,核心观感(光照/体积雾/植被/材质)不变。
## 历史:8/5-8/7 四次 AppHangB1(同 bucket 1573442377187319525,驱动层 dxgi/D3D12Core 栈),
## BR 100 bot+重部署直升机+毒圈+800m 大地图为最高渲染负载模式 → 阴影图集 4096→2048
## (图集显存减半、阴影 pass 填充率降约 4 倍),体积雾 48→32(BR 对局内动态收敛,见下)。
const BR_PRESET := {
	"shadows": 2048, "ssao": true, "fxaa": false, "taa": true, "scale": 1.0, "aniso": 8,
	"ssil": false, "ssr": false, "sdfgi": false, "glow": true, "msaa": 2, "cinema": true,
	"fog": 1.0, "particles": 1.0, "fx_scale": 1.0, "vfog": 32,
}

## ---- [PERF] GPU 保护档(全模式自适应):main 主循环检测帧时间尖峰(单帧 >250ms
## 或 2s 均值 >100ms,驱动级卡死前兆)或持续低帧(fps<42×4s)时立即套用,消除 GPU 峰值;
## 5s 稳定后由 main 尝试恢复原档(仍卡则保持)。全模式生效(征服/突破/TDM/战役/BR)。
const PROTECT_PRESET := {
	"shadows": 2048, "ssao": true, "fxaa": false, "taa": true, "scale": 1.0, "aniso": 8,
	"ssil": false, "ssr": false, "sdfgi": false, "glow": true, "msaa": 2, "cinema": true,
	"fog": 1.0, "particles": 0.7, "fx_scale": 1.0, "vfog": 32,
}

var _br_active := false
var _vfog_orig := 32  # 与 project.godot environment/volumetric_fog/volume_size 一致(8/7 全局收敛 48→32)
var _protect_active := false

## BR 对局开局应用(由 GameMode_BR.start 调用;幂等)
func apply_br_preset() -> void:
	if _br_active:
		return
	_br_active = true
	_apply_br_preset_impl()


func _apply_br_preset_impl() -> void:
	_apply_dict(BR_PRESET, Level.HIGH, "BR 优化档(100 bot)")
	# 体积雾分辨率收敛(BR 对局内):体积雾 3D 纹理填充率随体积立方尺寸涨,
	# 800m 大地图 + 毒圈厚雾为全模式最大雾体负载;对局收尾恢复原值
	# (全局 RenderingServer 接口 environment_set_volumetric_fog_volume_size(size, depth);
	#  原值取 project.godot environment/volumetric_fog/volume_size=32, 深度默认 64)
	if G.world_env != null and G.world_env.environment != null:
		RenderingServer.environment_set_volumetric_fog_volume_size(int(BR_PRESET["vfog"]), 64)
	print("[PERF] graphics BR 优化档生效: shadows=2048 vfog=%d ssil=OFF ssr=OFF(对局结束恢复)" % BR_PRESET["vfog"])


## 进入 GPU 保护档(main 主循环帧时间尖峰/持续低帧触发;幂等)
func enter_protect() -> void:
	if _protect_active:
		return
	_protect_active = true
	if _br_active:
		# BR 优化档已覆盖大部分项(2048/SSIL off/SSR off/vfog 32),仅叠加粒子收敛
		G.settings.particles = minf(G.settings.particles, PROTECT_PRESET["particles"])
		if G.apply_graphics.is_valid():
			G.apply_graphics.call()
	else:
		_apply_dict(PROTECT_PRESET, Level.MEDIUM, "GPU 保护档(尖峰)")
	print("[PERF] graphics GPU 保护档生效: shadows=2048 vfog=32 ssil=OFF ssr=OFF particles=0.7")


## 退出 GPU 保护档(main 主循环检测 5s 无尖峰后调用;幂等)
func exit_protect() -> void:
	if not _protect_active:
		return
	_protect_active = false
	if _br_active:
		_apply_br_preset_impl()
	else:
		apply_preset(current_level)
	print("[PERF] graphics 退出 GPU 保护档,已恢复 ", _level_name(current_level))


func protect_active() -> bool:
	return _protect_active


## BR 对局收尾恢复(由 GameMode_BR._finish / NOTIFICATION_PREDELETE 调用;幂等)
func restore_preset() -> void:
	if not _br_active:
		return
	_br_active = false
	_protect_active = false  # 对局收尾同时重置保护状态,恢复原档(下次尖峰再触发)
	if G.world_env != null and G.world_env.environment != null:
		RenderingServer.environment_set_volumetric_fog_volume_size(_vfog_orig, 64)
	apply_preset(current_level)
	print("[PERF] graphics 退出 BR: 已恢复预设 ", _level_name(current_level))


## 换图后重挂(环境被 world_builder 重建,重新应用安全后处理;保护档期间保持保护档)
func reapply() -> void:
	if _protect_active:
		if _br_active:
			_apply_br_preset_impl()
		else:
			_apply_dict(PROTECT_PRESET, Level.MEDIUM, "GPU 保护档(换图重挂)")
		return
	apply_preset(current_level)


func save_config(path := "user://graphics.cfg") -> void:
	# 画质档位 + 全部画质细项(设置菜单自由开关后重启保留)
	_custom_settings = true
	var c := ConfigFile.new()
	c.set_value("graphics", "level", current_level)
	var keys := ["shadows", "ssao", "fxaa", "scale", "aniso", "fog", "particles", "fx_scale",
		"msaa", "ssr", "ssil", "glow", "cinema", "auto_quality"]
	var s := {}
	for k in keys:
		s[k] = G.settings.get(k, 0)
	c.set_value("graphics", "settings", s)
	c.save(path)


func load_config(path := "user://graphics.cfg") -> void:
	var c := ConfigFile.new()
	if c.load(path) == OK:
		current_level = int(c.get_value("graphics", "level", current_level))
		var s = c.get_value("graphics", "settings", {})
		if s is Dictionary and not (s as Dictionary).is_empty():
			_custom_settings = true
			for k in s:
				G.settings[k] = s[k]
			# 旧存档可能含 8192/16384 阴影,统一钳制到优化后的最高 4096
			if G.settings.has("shadows"):
				G.settings.shadows = mini(int(G.settings.shadows), 4096)


func has_custom_settings() -> bool:
	return _custom_settings


var _custom_settings := false


## 仅应用档位强度分级(SSAO 质量 / Glow 强度 / SSIL 强度),不覆盖用户手动开关;
## 启动时若存档含细项设置则用它,保证"设置里自由开关"重启后保留
func apply_level_strengths() -> void:
	var lv := current_level
	if G.world_env != null and G.world_env.environment != null:
		var env := G.world_env.environment
		if G.settings.get("ssao", false):
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
		if G.settings.get("glow", false):
			if lv == Level.ULTRA:
				env.glow_intensity = 0.42
				env.glow_strength = 0.72
				env.glow_bloom = 0.32
				env.glow_hdr_threshold = 1.0
			else:
				env.glow_intensity = 0.35
				env.glow_strength = 0.7
				env.glow_bloom = 0.28
				env.glow_hdr_threshold = 1.05
		if G.settings.get("ssil", false):
			env.ssil_intensity = 1.4 if lv == Level.ULTRA else 1.1
	if G.apply_graphics.is_valid():
		G.apply_graphics.call()
