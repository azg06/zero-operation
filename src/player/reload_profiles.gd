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
	if def.get("revolver") == true:
		return "revolver"
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
	if def.pellets > 1 or def.projectile or def.get("revolver") == true:
		return "none"
	if def.kind == "pistol":
		return "pistol"
	if id == "p90":
		return "p90"
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
	if id in ["m24", "m40", "sks"]:
		return "none"
	return "down"


## 换弹音效枪族:让 AK 钢弹匣、SMG、手枪、狙击枪的拔插/枪机声有明显区别
static func _snd_family_for(id: String, def) -> String:
	if def.pellets > 1:
		return "shotgun"
	if def.get("revolver") == true:
		return "revolver"
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
	if def.get("revolver") == true:
		return "none"
	if def.kind == "pistol":
		return "slide"
	if def.projectile:
		return "none"
	if id in ["awm", "m24", "m40", "l115", "sv98", "m2010"]:
		return "bolt_cycle"
	if id == "p90":
		return "p90_charge"
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
		"tac_weights": [0.13, 0.16, 0.15, 0.21, 0.20, 0.15],
		"empty_weights": [0.12, 0.15, 0.26, 0.15, 0.18, 0.14],
		"drum_weights": [0.13, 0.18, 0.25, 0.18, 0.12, 0.14],
		"belt_weights": [0.17, 0.18, 0.24, 0.17, 0.13, 0.11],
		"charge_weight": 0.14,
		"cover_angle": 0.85,
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
			p["tac_weights"] = [0.16, 0.18, 0.14, 0.20, 0.18, 0.14]
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
		"revolver":
			# 左轮:枪身倾斜展示弹巢,手臂动作幅度小但镜头反馈清晰;换弹流程由控制器按 quick/single 展开
			p["pose_pos"] = Vector3(0.024, 0.018, 0.044)
			p["pose_rot"] = Vector3(0.07, -0.13, -0.16)
			p["sway_amp"] = 0.0032
			p["sway_freq"] = 0.95
			p["insert_impact"] = 0.006
			p["chamber_impact"] = 0.010
			p["inertia_strength"] = 0.62
			p["cam_strength"] = 0.85
			p["anim_speed"] = 1.0
			p["hand_arc"] = 0.055
			p["reload_flow"] = "revolver"
			p["mag"] = "none"
			p["chamber_style"] = "none"
			p["cylinder_angle"] = 0.92
			p["quick_weights"] = [0.16, 0.15, 0.2, 0.18, 0.16, 0.15]
			p["single_weights"] = [0.16, 0.14, 0.22, 0.28, 0.20]
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
			p["tac_shell_time"] = maxf(0.46, float(p.get("tac_shell_time", 0.6)))
			p["pump_dur"] = 0.45
			p["pump_stroke"] = 0.06
			p["mech_pitch"] = 1.0
		"spas12":
			p["shell_time"] = maxf(0.52, float(p.get("shell_time", 0.7)))
			p["tac_shell_time"] = maxf(0.46, float(p.get("tac_shell_time", 0.6)))
			p["pump_dur"] = 0.5
			p["pump_stroke"] = 0.065
			p["mech_pitch"] = 0.94
		# [9/10] 泵动霰弹枪:每把独立壳入膛节奏/泵动行程/机械音高
		"rem870":
			p["shell_time"] = maxf(0.48, float(p.get("shell_time", 0.65)))
			p["tac_shell_time"] = maxf(0.44, float(p.get("tac_shell_time", 0.58)))
			p["pump_dur"] = 0.46
			p["pump_stroke"] = 0.065
			p["mech_pitch"] = 0.98
			p["shell_grab_snd"] = "shell_grab_rem870"
			p["shell_insert_snd"] = "shell_insert_rem870"
		"m590":
			p["shell_time"] = maxf(0.52, float(p.get("shell_time", 0.72)))
			p["tac_shell_time"] = maxf(0.46, float(p.get("tac_shell_time", 0.62)))
			p["pump_dur"] = 0.5
			p["pump_stroke"] = 0.075
			p["mech_pitch"] = 0.92
			p["shell_grab_snd"] = "shell_grab_m590"
			p["shell_insert_snd"] = "shell_insert_m590"
		"win1897":
			p["shell_time"] = maxf(0.56, float(p.get("shell_time", 0.78)))
			p["tac_shell_time"] = maxf(0.5, float(p.get("tac_shell_time", 0.68)))
			p["pump_dur"] = 0.52
			p["pump_stroke"] = 0.07
			p["mech_pitch"] = 0.9
			p["shell_grab_snd"] = "shell_grab_win1897"
			p["shell_insert_snd"] = "shell_insert_win1897"
	return


## 稳定字符串哈希:换弹签名种子(同一把枪永远得到同一组动作差异)
static func _hash_sig(s: String) -> int:
	var h := 17
	for i in s.length():
		h = (h * 131 + s.unicode_at(i)) % 1000000007
	return h


## 对阶段权重做确定性抖动:同一把枪节奏固定,不同枪之间永远不同(_build_phases 会归一化)
static func _jitter_weights(w: Array, h: int) -> Array:
	# 相对抖动:每个权重乘 0.78~1.22,再归一化回总和 1(总时长不变,节奏签名保留)。
	# 旧版是绝对加减 ±0.18 —— 和权重本身(0.13~0.21)同量级,个别阶段会被压到 0.02
	# 的钳底:插匣阶段只剩 2~3 帧,拍匣动画被整个吞掉(mp5/vector 战术换弹翻车根因)。
	var out: Array = []
	var sum := 0.0
	for i in w.size():
		var v := float(w[i])
		var j := 0.78 + 0.44 * float(((h / int(1 + i * 13)) % 9)) / 8.0
		v *= j
		out.append(v)
		sum += v
	if sum <= 0.0001:
		return w
	for i in out.size():
		out[i] = float(out[i]) / sum
	return out


## 每把枪的换弹签名:决定取/收/插弹匣的三段弧线、弹匣旋转、携行具位置、
## 枪身姿态、镜头惯性、拍匣力度与枪机行程。结构相同但动作绝不雷同。
static func _signature(id: String, p: Dictionary) -> void:
	var h := _hash_sig(id)
	var ax := float((h % 13) - 6) / 6.0
	var ay := float(((h / 13) % 11) - 5) / 5.0
	var az := float(((h / 143) % 17) - 8) / 8.0
	p["sig_id"] = id
	p["pouch"] = Vector3(0.02 + ax * 0.055, -0.20 + ay * 0.07, 0.10 + az * 0.06)
	p["remove_bias"] = Vector3(ax * 0.028, ay * 0.02, az * 0.026)
	p["remove_rot_bias"] = Vector3(ax * 0.11, ay * 0.09, az * 0.16)
	p["insert_bias"] = Vector3(-ax * 0.02, -ay * 0.014, -az * 0.02)
	p["stow_bias"] = Vector3(-ax * 0.045, -ay * 0.035, az * 0.05)
	p["fetch_arc"] = maxf(0.035, float(p.get("hand_arc", 0.09)) * (0.82 + 0.36 * float((h % 9)) / 8.0))
	p["stow_arc"] = maxf(0.03, float(p.get("hand_arc", 0.09)) * (0.75 + 0.42 * float((h % 7)) / 6.0))
	p["drop_dist"] = maxf(0.05, float(p.get("drop_dist", 0.16)) * (0.9 + 0.22 * float((h % 7)) / 6.0))
	p["mag_rot"] = float(p.get("mag_rot", 0.13)) * (0.8 + 0.44 * float((h % 5)) / 4.0)
	p["slap"] = float(p.get("slap", 0.018)) * (0.72 + 0.56 * float((h % 5)) / 4.0)
	p["pose_pos"] = (p.get("pose_pos", Vector3.ZERO) as Vector3) + Vector3(ax * 0.007, ay * 0.006, az * 0.007)
	p["pose_rot"] = (p.get("pose_rot", Vector3.ZERO) as Vector3) + Vector3(ax * 0.022, ay * 0.016, az * 0.022)
	p["anim_speed"] = float(p.get("anim_speed", 1.0)) * (0.965 + 0.07 * float((h % 5)) / 4.0)
	p["inertia_strength"] = float(p.get("inertia_strength", 1.0)) * (0.94 + 0.12 * float((h % 5)) / 4.0)
	p["cam_strength"] = float(p.get("cam_strength", 1.0)) * (0.94 + 0.12 * float((h % 5)) / 4.0)
	p["chamber_amp"] = float(p.get("chamber_amp", 0.05)) * (0.88 + 0.24 * float((h % 5)) / 4.0)
	p["mech_pitch"] = float(p.get("mech_pitch", 1.0)) * (0.96 + 0.08 * float((h % 5)) / 4.0)
	p["sway_amp"] = float(p.get("sway_amp", 0.0045)) * (0.9 + 0.2 * float((h % 5)) / 4.0)
	p["sway_freq"] = float(p.get("sway_freq", 1.35)) * (0.94 + 0.12 * float((h % 5)) / 4.0)
	p["pose_damp"] = float(p.get("pose_damp", 11.0)) * (0.94 + 0.12 * float((h % 5)) / 4.0)
	if p.has("tac_weights"):
		p["tac_weights"] = _jitter_weights(p["tac_weights"], h)
	if p.has("empty_weights"):
		p["empty_weights"] = _jitter_weights(p["empty_weights"], h)
	if p.has("drum_weights"):
		p["drum_weights"] = _jitter_weights(p["drum_weights"], h)
	if p.has("belt_weights"):
		p["belt_weights"] = _jitter_weights(p["belt_weights"], h)
	# 标志性枪机动作(空仓收尾)。每个枪族/枪型不同,避免所有枪都做同一个“拉拉机柄”。
	match id:
		"m4", "scar", "mpx", "ar10", "m110", "g28", "mk14":
			p["chamber_style"] = "ar_release"
		"aug", "famas":
			p["chamber_style"] = "bullpup_tap"
		"g3":
			p["chamber_style"] = "g3_pull"
		"mp5":
			p["chamber_style"] = "hk_slap"
		"p90":
			p["chamber_style"] = "p90_charge"
		"m14", "m1a", "sks", "fal":
			p["chamber_style"] = "right_tap"


## 无需每枪签名的枪(已单独完整制作的换弹系统):3 把左轮 + 5 把霰弹枪
const _SIG_SKIP := ["python", "sw686", "sw500", "m1014", "spas12", "rem870", "m590", "win1897"]


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
	# 左轮:快速装弹器与逐发装填两套时长/流程全部由数据驱动
	if def.get("revolver") == true:
		var qr := 2.0
		var sr := 3.0
		if def.get("quick_reload") != null:
			qr = float(def.get("quick_reload"))
		if def.get("single_reload") != null:
			sr = float(def.get("single_reload"))
		p["quick_time"] = maxf(0.8, qr)
		p["single_time"] = maxf(1.0, sr)
		p["round_time"] = maxf(0.42, (p["single_time"] - 0.85) / maxf(1.0, float(def.mag)))
		p["single_weights"] = [0.16, 0.14, 0.22, 0.28, 0.20]
		p["quick_weights"] = [0.16, 0.15, 0.20, 0.18, 0.16, 0.15]
		p["open_snd"] = "revolver_open_" + id
		p["close_snd"] = "revolver_close_" + id
		p["eject_snd"] = "revolver_eject_" + id
		p["round_snd"] = "revolver_round_" + id
		p["loader_snd"] = "revolver_loader_" + id
		p["cock_snd"] = "revolver_hammer_" + id
		p["insert_snd"] = "revolver_insert_" + id
		_override(id, p)
		return p
	# 换弹总时长:优先 WeaponDef 的专用战术时长,否则按 78% 折算
	if def.pellets > 1:
		p["reload_flow"] = "tube"
		p["shell_time"] = maxf(0.45, float(def.reload_time) / float(maxi(1, def.mag)))
		var tac_time: float = float(def.reload_tac) if float(def.reload_tac) > 0.0 else float(def.reload_time) * 0.78
		p["tac_shell_time"] = maxf(0.45, tac_time / float(maxi(1, def.mag)))
		p["empty_time"] = float(def.reload_time)
		p["tac_time"] = tac_time
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
	if not _SIG_SKIP.has(id):
		_signature(id, p)
	return p
