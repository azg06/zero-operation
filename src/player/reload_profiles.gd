class_name ReloadProfiles extends RefCounted
## 数据驱动换弹配置表
## 所有换弹手感参数集中在这里:阶段时序、镜头反馈、枪械惯性、ADS/冲刺兼容、
## 各枪族动作幅度与枪机操作方式。Gun 与 WeaponReloadController 只读配置,不写死动作。
##
## 时间约定:
##   tac_time / empty_time   普通换弹与空仓换弹总时长(秒,0=由 WeaponDef 自动推导)
##   insert_time / chamber_time  由 empty_weights 换算出的阶段绝对秒数(只读输出)
##   cancel_time             开火可中断点:REMOVE 阶段进度小于该值视为弹匣尚未脱离
##   anim_speed              动画播放速度倍率(总时长 ÷ anim_speed)
##   cam_strength            镜头反馈强度倍率
##   inertia_strength        枪械惯性幅度倍率
##   ads_allowed             换弹期间是否允许进入 ADS
##   ads_keep                ADS 时换弹姿态保留比例
##   sprint_keep             冲刺时换弹姿态保留比例


static func _ez(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _style_for(id: String, def) -> String:
	if def.pellets > 1:
		return "shotgun"
	if def.projectile:
		return "rocket"
	if def.kind == "pistol":
		return "pistol"
	if id in ["awm", "m24", "m40", "l115", "sv98", "m2010"]:
		return "bolt"
	if id == "g36c":
		return "carbine"
	match def.kind:
		"smg":
			return "smg"
		"lmg":
			return "lmg"
		"dmr":
			return "dmr"
		"sniper":
			return "sniper"
	return "rifle"


## 弹匣运动类型:与 WeaponModels 的实际模型结构对应
static func _mag_style_for(id: String, def) -> String:
	if def.pellets > 1 or def.projectile:
		return "none"
	if def.kind == "pistol":
		return "pistol"
	if id == "p90":
		return "top"
	if id in ["ak", "ak74", "svd"]:
		return "side"
	if id == "rpd":
		# RPD 为左侧大圆鼓供弹:必须走“解锁 → 横移摘下 → 重新对位 → 旋转锁定”的弹鼓流程
		return "drum"
	if id == "pp19":
		# 野牛长筒螺旋弹匣沿枪管方向横置,装填时垂直落下/垂直推入,不走弹鼓旋转路径
		return "down"
	if id in ["m249", "pkm", "mg42", "m60", "mk48", "negev", "mg3"]:
		return "belt"
	if id in ["m24"]:
		return "none"
	return "down"


## 换弹音效枪族:让 AK 钢弹匣、SMG、手枪、狙击枪的拔插/枪机声有明显区别
static func _snd_family_for(id: String, def) -> String:
	if def.pellets > 1:
		return "shotgun"
	if def.kind == "pistol":
		return "pistol"
	if id in ["ak", "ak74", "svd"]:
		return "ak"
	if def.kind == "sniper":
		return "sniper"
	if def.kind == "smg":
		return "smg"
	return "rifle"


## 弹链机枪音效组:轻机枪组与重机枪组使用不同的开盖/抽链/闭锁采样
static func _belt_snd_set_for(id: String) -> String:
	if id in ["pkm", "mg42", "mg3", "m60"]:
		return "heavy"
	return "light"


## 枪机操作风格:不同枪族/结构完全不同的收尾动作
static func _chamber_for(id: String, def) -> String:
	if def.pellets > 1:
		return "pump"
	if def.kind == "pistol":
		return "slide"
	if def.projectile:
		return "none"
	if id in ["awm", "m24", "m40", "l115", "sv98", "m2010"]:
		return "bolt_cycle"
	if id == "p90":
		return "top_slap"
	if id in ["ak", "ak74", "svd"]:
		return "pull_ak"
	if def.kind == "lmg":
		# 弹鼓/弹链机枪的空仓收尾:拉机柄/受弹机盖闭锁后的真实上膛循环,不再“拍弹匣”
		return "pull_heavy"
	if def.kind == "dmr":
		return "release"
	if def.kind == "sniper":
		return "pull_heavy"
	if def.kind == "smg":
		return "pull"
	if id in ["aug", "famas"]:
		return "pull_heavy"
	return "pull"


static func _base(style: String) -> Dictionary:
	var p := {
		"style": style,
		"mag": "down",
		"reload_flow": "mag",
		"tac_time": 0.0,
		"empty_time": 0.0,
		"tac_weights": [0.16, 0.20, 0.32, 0.18, 0.14],
		"empty_weights": [0.12, 0.15, 0.26, 0.15, 0.18, 0.14],
		"drum_weights": [0.13, 0.18, 0.25, 0.18, 0.12, 0.14],
		"belt_weights": [0.17, 0.18, 0.24, 0.17, 0.13, 0.11],
		"charge_weight": 0.14,
		"cover_angle": 0.62,
		"cover_open_at": 0.10,
		"cover_open_span": 0.74,
		"cover_close_at": 0.08,
		"cover_close_span": 0.76,
		"belt_commit": 0.68,
		"drum_commit": 0.78,
		"seal_point": 0.68,
		"cover_seal": 0.84,
		"swap_point": 0.88,
		"mech_pitch": 1.0,
		"pose_pos": Vector3(0.045, 0.030, 0.060),
		"pose_rot": Vector3(0.035, -0.16, -0.22),
		"pose_in": 0.14,
		"pose_out": 0.16,
		"pose_damp": 11.0,
		"tac_pose_scale": 0.95,
		"empty_pose_scale": 1.2,
		"finish_dur": 0.26,
		"sway_amp": 0.0045,
		"sway_freq": 1.35,
		"ads_allowed": true,
		"ads_keep": 0.22,
		"sprint_keep": 0.16,
		"cam_strength": 1.0,
		"cam_damp": 9.0,
		"cam_freq": 1.2,
		"cam_sway": 0.0011,
		"inertia_strength": 1.0,
		"impact_damp": 10.0,
		"insert_impact": 0.009,
		"chamber_impact": 0.011,
		"drop_dist": 0.16,
		"mag_rot": 0.13,
		"drop_point": 0.62,
		"insert_commit": 0.52,
		"commit_gap": 0.016,
		"insert_contact": 0.30,
		"hand_arc": 0.09,
		"slap": 0.018,
		"cancel_time": 0.45,
		"chamber_amp": 0.052,
		"chamber_style": "pull",
		"anim_speed": 1.0,
		"shell_time": 0.7,
		"tube_weights": [0.32, 0.30, 0.38],
	}
	match style:
		"rifle":
			p["pose_pos"] = Vector3(0.050, 0.035, 0.062)
			p["pose_rot"] = Vector3(0.05, -0.18, -0.24)
		"carbine":
			p["pose_pos"] = Vector3(0.030, 0.024, 0.046)
			p["pose_rot"] = Vector3(0.03, -0.12, -0.15)
			p["chamber_amp"] = 0.044
			p["anim_speed"] = 1.04
			p["inertia_strength"] = 0.8
		"smg":
			p["pose_pos"] = Vector3(0.040, 0.030, 0.052)
			p["pose_rot"] = Vector3(0.04, -0.15, -0.18)
			p["chamber_amp"] = 0.046
			p["slap"] = 0.032
			p["anim_speed"] = 1.03
		"lmg":
			p["pose_pos"] = Vector3(0.038, -0.006, 0.060)
			p["pose_rot"] = Vector3(0.05, -0.13, -0.16)
			p["pose_damp"] = 9.0
			p["sway_amp"] = 0.0035
			p["sway_freq"] = 0.9
			p["chamber_amp"] = 0.062
			p["insert_impact"] = 0.012
			p["chamber_impact"] = 0.015
			p["inertia_strength"] = 1.35
			p["anim_speed"] = 0.96
			p["drop_dist"] = 0.18
		"dmr":
			p["pose_pos"] = Vector3(0.032, 0.024, 0.044)
			p["pose_rot"] = Vector3(0.03, -0.11, -0.13)
			p["sway_amp"] = 0.003
			p["chamber_amp"] = 0.048
			p["inertia_strength"] = 1.1
		"sniper":
			p["pose_pos"] = Vector3(0.034, 0.014, 0.048)
			p["pose_rot"] = Vector3(0.035, -0.12, -0.14)
			p["sway_amp"] = 0.003
			p["sway_freq"] = 0.8
			p["chamber_amp"] = 0.064
			p["inertia_strength"] = 1.25
			p["insert_impact"] = 0.010
			p["chamber_impact"] = 0.013
			p["anim_speed"] = 0.97
		"bolt":
			p["pose_pos"] = Vector3(0.034, 0.012, 0.050)
			p["pose_rot"] = Vector3(0.035, -0.12, -0.14)
			p["sway_amp"] = 0.0032
			p["sway_freq"] = 0.85
			p["inertia_strength"] = 1.2
			p["anim_speed"] = 0.96
		"pistol":
			p["pose_pos"] = Vector3(0.030, 0.020, 0.030)
			p["pose_rot"] = Vector3(0.06, -0.12, -0.10)
			p["tac_weights"] = [0.18, 0.20, 0.30, 0.18, 0.14]
			p["empty_weights"] = [0.14, 0.16, 0.27, 0.16, 0.15, 0.12]
			p["drop_dist"] = 0.10
			p["mag_rot"] = 0.08
			p["slap"] = 0.012
			p["chamber_amp"] = 0.036
			p["cam_strength"] = 0.75
			p["inertia_strength"] = 0.45
			p["anim_speed"] = 1.05
			p["tac_pose_scale"] = 0.85
			p["empty_pose_scale"] = 1.0
			p["hand_arc"] = 0.06
		"shotgun":
			p["pose_pos"] = Vector3(0.038, 0.010, 0.054)
			p["pose_rot"] = Vector3(0.045, -0.14, -0.17)
			p["sway_amp"] = 0.004
			p["sway_freq"] = 1.0
			p["insert_impact"] = 0.008
			p["chamber_impact"] = 0.014
			p["inertia_strength"] = 1.15
			p["shell_time"] = 0.7
		"rocket":
			p["pose_pos"] = Vector3(0.0, -0.030, 0.080)
			p["pose_rot"] = Vector3(0.05, -0.08, -0.10)
			p["tac_weights"] = [0.14, 0.18, 0.32, 0.18, 0.18]
			p["empty_weights"] = [0.12, 0.18, 0.32, 0.20, 0.18]
			p["inertia_strength"] = 1.6
			p["pose_damp"] = 8.5
			p["insert_impact"] = 0.014
			p["chamber_impact"] = 0.0
	return p


## 武器级覆写:只放真正需要单独设计的枪,其余走枪族配置
static func _override(id: String, p: Dictionary) -> void:
	match id:
		"gl":
			# M320 中折式榴弹发射器:开膛 → 抽空壳 → 取新榴弹 → 推入 → 合膛闭锁
			# breech_hinge=开膛下折角度(rad),由 WeaponReloadController 按阶段驱动膛体铰链
			p["breech_hinge"] = 0.62
			p["insert_offset"] = Vector3(0.02, 0.055, 0.15)   # 榴弹从弹膛后上方塞入(中折式)
			p["load_snd"] = "shell_insert"   # 40mm 榴弹逐发塞入声(比导弹筒入膛更贴切)
			p["pose_pos"] = Vector3(0.0, -0.022, 0.055)
			p["pose_rot"] = Vector3(0.10, -0.16, -0.14)
			p["tac_weights"] = [0.18, 0.2, 0.26, 0.2, 0.16]
			p["empty_weights"] = [0.18, 0.2, 0.26, 0.2, 0.16]
			p["inertia_strength"] = 1.25
			p["pose_damp"] = 10.0
			p["insert_impact"] = 0.011
			p["cam_strength"] = 1.1
		"m4":
			p["pose_rot"] = Vector3(0.025, -0.09, -0.12)
		"ak":
			p["pose_rot"] = Vector3(0.04, -0.12, -0.16)
			p["chamber_amp"] = 0.066
			p["inertia_strength"] = 1.15
		"ak74":
			p["pose_rot"] = Vector3(0.035, -0.11, -0.15)
		"scar":
			p["pose_rot"] = Vector3(0.03, -0.10, -0.13)
			p["chamber_amp"] = 0.056
		"aug":
			p["pose_pos"] = Vector3(0.018, 0.008, 0.036)
			p["pose_rot"] = Vector3(0.02, -0.08, -0.11)
		"famas":
			p["pose_rot"] = Vector3(0.025, -0.09, -0.12)
		"g3":
			p["inertia_strength"] = 1.2
		"mp5":
			p["slap"] = 0.038
		"ump":
			p["inertia_strength"] = 1.05
		"vector":
			p["anim_speed"] = 1.05
		"pp2000":
			p["drop_dist"] = 0.18
		"m249":
			p["pose_pos"] = Vector3(0.014, -0.014, 0.052)
			p["anim_speed"] = 0.94
			p["mech_pitch"] = 0.98
			p["belt_weights"] = [0.16, 0.19, 0.24, 0.17, 0.13, 0.11]
		"pkm":
			p["pose_pos"] = Vector3(0.014, -0.016, 0.054)
			p["anim_speed"] = 0.93
			p["mech_pitch"] = 0.92
			p["cover_angle"] = 0.68
			p["belt_weights"] = [0.15, 0.18, 0.26, 0.17, 0.13, 0.11]
		"mg42":
			p["anim_speed"] = 0.97
			p["mech_pitch"] = 1.05
			p["cover_angle"] = 0.74
			p["belt_weights"] = [0.18, 0.16, 0.24, 0.16, 0.15, 0.11]
		"m82a1":
			p["pose_pos"] = Vector3(0.018, -0.004, 0.038)
			p["inertia_strength"] = 1.4
		"deagle":
			p["anim_speed"] = 0.96
			p["inertia_strength"] = 0.75
			p["insert_impact"] = 0.012
		"m93r":
			p["anim_speed"] = 1.07
		"m1911":
			p["anim_speed"] = 1.02
			p["insert_impact"] = 0.010
		"g17":
			p["anim_speed"] = 1.08
			p["inertia_strength"] = 0.4
		"p226":
			p["anim_speed"] = 1.04
		"p90":
			p["drop_dist"] = 0.14
			p["slap"] = 0.024
			p["hand_arc"] = 0.12
		"mpx":
			p["anim_speed"] = 1.06
		"mp7":
			p["anim_speed"] = 1.07
			p["chamber_amp"] = 0.05
		"pp19":
			p["drop_dist"] = 0.16
			p["slap"] = 0.010
		"rpd":
			p["anim_speed"] = 0.96
			p["mech_pitch"] = 0.97
			p["chamber_amp"] = 0.058
			p["drum_weights"] = [0.12, 0.17, 0.26, 0.18, 0.13, 0.14]
		"m60":
			p["anim_speed"] = 0.90
			p["mech_pitch"] = 0.88
			p["cover_angle"] = 0.58
			p["chamber_amp"] = 0.06
			p["belt_weights"] = [0.14, 0.18, 0.26, 0.17, 0.14, 0.11]
		"mk48":
			p["anim_speed"] = 0.92
			p["mech_pitch"] = 0.95
			p["chamber_amp"] = 0.064
			p["belt_weights"] = [0.16, 0.18, 0.25, 0.17, 0.13, 0.11]
		"negev":
			p["anim_speed"] = 0.88
			p["mech_pitch"] = 0.90
			p["chamber_amp"] = 0.066
			p["belt_weights"] = [0.14, 0.18, 0.26, 0.18, 0.13, 0.11]
		"mg3":
			p["anim_speed"] = 0.94
			p["mech_pitch"] = 1.02
			p["chamber_amp"] = 0.064
			p["belt_weights"] = [0.17, 0.17, 0.24, 0.17, 0.14, 0.11]
		"m110":
			p["chamber_amp"] = 0.05
		"sks":
			p["chamber_amp"] = 0.05
		"m1a":
			p["chamber_amp"] = 0.05
		"g28":
			p["chamber_amp"] = 0.052
		"mk14":
			p["chamber_amp"] = 0.054
		"m14":
			p["chamber_amp"] = 0.052
		"ar10":
			p["chamber_amp"] = 0.05
		"fal":
			p["chamber_amp"] = 0.052
		"svd":
			p["chamber_amp"] = 0.07
		"awm":
			p["inertia_strength"] = 1.3
		"m24":
			p["inertia_strength"] = 1.25
		"m40":
			p["inertia_strength"] = 1.2
		"l115":
			p["inertia_strength"] = 1.25
		"sv98":
			p["inertia_strength"] = 1.2
		"m2010":
			p["inertia_strength"] = 1.25
		"m1014":
			p["shell_time"] = maxf(0.52, float(p.get("shell_time", 0.7)))
		"spas12":
			p["shell_time"] = maxf(0.52, float(p.get("shell_time", 0.7)))
	return


static func profile_for(id: String, def) -> Dictionary:
	var style := _style_for(id, def)
	var p := _base(style)
	p["mag"] = _mag_style_for(id, def)
	p["chamber_style"] = _chamber_for(id, def)
	# 弹鼓/弹链轻机枪切换到专用换弹流程;其余武器保持原弹匣流程
	match String(p["mag"]):
		"drum":
			p["reload_flow"] = "drum"
		"belt":
			p["reload_flow"] = "belt"
	# 按枪族映射换弹音效:不同结构/材质的武器不再共用同一声
	var snd_family := _snd_family_for(id, def)
	match snd_family:
		"ak":
			p["mag_out_snd"] = "mag_out_ak"
			p["mag_in_snd"] = "mag_in_ak"
			p["pouch_snd"] = "ammo_pouch"
			p["bolt_snd"] = "bolt_cycle_ak"
		"pistol":
			p["mag_out_snd"] = "mag_out_pistol"
			p["mag_in_snd"] = "mag_in_pistol"
			p["pouch_snd"] = "ammo_pouch_pistol"
			p["bolt_snd"] = "slide_release"
		"sniper":
			p["mag_out_snd"] = "mag_out_sniper"
			p["mag_in_snd"] = "mag_in_sniper"
			p["pouch_snd"] = "ammo_pouch_sniper"
			p["bolt_snd"] = "bolt_cycle_sniper"
		"smg":
			p["mag_out_snd"] = "mag_out_smg"
			p["mag_in_snd"] = "mag_in_smg"
			p["pouch_snd"] = "ammo_pouch_smg"
			p["bolt_snd"] = "bolt_cycle_smg"
		_:
			p["mag_out_snd"] = "mag_out"
			p["mag_in_snd"] = "mag_in"
			p["pouch_snd"] = "ammo_pouch"
			p["bolt_snd"] = "bolt_cycle"
	if def.kind == "lmg":
		p["bolt_snd"] = "bolt_cycle_lmg"
		p["belt_snd_set"] = _belt_snd_set_for(id)
	# 换弹总时长:优先 WeaponDef 的专用战术时长,否则按 78% 折算
	if def.pellets > 1:
		p["shell_time"] = maxf(0.45, float(def.reload_time) / float(maxi(1, def.mag)))
		p["empty_time"] = float(def.reload_time)
		p["tac_time"] = float(def.reload_time)
		var tube_weights: Array = p["tube_weights"]
		p["insert_time"] = float(p["shell_time"]) * float(tube_weights[1])
		p["chamber_time"] = 0.45
	elif def.projectile:
		p["empty_time"] = float(def.reload_time)
		p["tac_time"] = float(def.reload_time)
		var rw: Array = p["empty_weights"]
		p["insert_time"] = float(p["empty_time"]) * float(rw[3])
		p["chamber_time"] = 0.0
	else:
		p["tac_time"] = float(def.reload_tac) if float(def.reload_tac) > 0.0 else float(def.reload_time) * 0.78
		p["empty_time"] = float(def.reload_time)
		var ew: Array = p["empty_weights"]
		p["insert_time"] = float(p["empty_time"]) * float(ew[3])
		p["chamber_time"] = float(p["empty_time"]) * float(ew[4]) if ew.size() > 4 else 0.0
	_override(id, p)
	return p
