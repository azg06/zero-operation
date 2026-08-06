class_name SoldierModel
## 士兵模型(对应 ai.js 的 buildSoldier 与 player.js 的 _buildBody)

static func _mat(color: Color, rough := 0.9, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _box(w: float, h: float, d: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = mat
	return mi


static func _add(parent: Node3D, mesh: MeshInstance3D, x: float, y: float, z: float) -> MeshInstance3D:
	mesh.position = Vector3(x, y, z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh)
	return mesh


## 兵种皮肤配色(每兵种 3 套;standard 与无 skin 参数时完全一致)
const SKINS := {
	"assault": {
		"standard": { "uniform": "#4a5548", "vest": "#3a4a5a", "helmet": "#3a4438", "gear": "#33382e", "gear2": "#565a44" },
		"arctic": { "uniform": "#cfd6d8", "vest": "#aeb8bd", "helmet": "#dde2e4", "gear": "#8e979b", "gear2": "#bcc4c8", "cover": "#e8ecee", "strap": "#5a6670" },
		"night": { "uniform": "#23262c", "vest": "#171a20", "helmet": "#2c2f36", "gear": "#0f1216", "gear2": "#1d2128", "cover": "#14181e", "strap": "#0a0d10" },
	},
	"engineer": {
		"standard": { "uniform": "#8a6a3e", "vest": "#c07a34", "helmet": "#96682f", "gear": "#5c4a30", "gear2": "#7c6640" },
		"desert": { "uniform": "#c4a46c", "vest": "#b08c50", "helmet": "#ccb074", "gear": "#8a7448", "gear2": "#a8905e", "cover": "#d8c088", "strap": "#a8905e" },
		"black": { "uniform": "#3a3a40", "vest": "#26262c", "helmet": "#44444c", "gear": "#1c1c22", "gear2": "#32323a", "cover": "#101014", "strap": "#26262e" },
	},
	"support": {
		"standard": { "uniform": "#4a5c44", "vest": "#3a4c38", "helmet": "#40503c", "gear": "#2c3a2c", "gear2": "#4e5e4a" },
		"brown": { "uniform": "#5c4c3a", "vest": "#6e5838", "helmet": "#52442e", "gear": "#3a3228", "gear2": "#5e4e3a", "cover": "#6a5638", "strap": "#463a2a" },
		"gray": { "uniform": "#5a5e64", "vest": "#484c52", "helmet": "#62666c", "gear": "#34383e", "gear2": "#50545a", "cover": "#6e7278", "strap": "#3c4046" },
	},
	"recon": {
		"standard": { "uniform": "#5c6c4a", "vest": "#4a5c3c", "helmet": "#54643f", "gear": "#38462c", "gear2": "#6c7c54" },
		"urban": { "uniform": "#6e747a", "vest": "#585e64", "helmet": "#767c82", "gear": "#44484e", "gear2": "#62686e", "cover": "#82888e", "strap": "#50565c" },
		"white": { "uniform": "#d8dcde", "vest": "#c2c8cc", "helmet": "#e4e8ea", "gear": "#a8aeb2", "gear2": "#ccd2d4", "cover": "#f0f2f4", "strap": "#b4babd" },
	},
}


## AI 士兵:膝关节双腿 + 可编程持枪臂组 + 兵种专属外观
## 返回 Node3D,meta: leg_l{thigh,knee}, leg_r, upper, rig
static func build_soldier(team: String, weapon_id: String, class_id := "assault", skin := "standard") -> Node3D:
	var g := Node3D.new()
	g.name = "Soldier"
	var is_us: bool = team == "us"
	# 防御:未知皮肤 id(含跨兵种皮肤)一律回退本兵种 standard
	var cl_skins: Dictionary = SKINS.get(class_id, SKINS["assault"])
	if not cl_skins.has(skin):
		skin = "standard"
	var pal: Dictionary = cl_skins[skin]
	var uniform := _mat(Color.html(pal["uniform"]), 0.95)
	var vest := _mat(Color.html(pal["vest"]), 0.9)
	var skin_mat := _mat(Color.html("#c8a080"), 0.8)
	var helmet := _mat(Color.html(pal["helmet"]), 0.85)
	var accent := _mat(Color.html("#00ff88") if is_us else Color.html("#ff5500"), 0.9, true)
	var gear := _mat(Color.html(pal["gear"]), 0.92)                  # 装具深色
	var gear2 := _mat(Color.html(pal["gear2"]), 0.92)                # 装具帆布色
	var boot := _mat(Color.html("#26221e"), 0.9)                     # 靴
	var brass := _mat(Color.html("#c8a860"), 0.5)                    # 弹链铜色

	# 腿:髋部枢轴(大腿) + 膝关节(小腿) + 护膝 + 靴
	var mk_leg := func(x: float) -> Dictionary:
		var thigh := Node3D.new()
		thigh.position = Vector3(x, 0.78, 0)
		var tm := _box(0.16, 0.42, 0.18, uniform)
		tm.position.y = -0.21
		tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		thigh.add_child(tm)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.44, 0)
		var sm := _box(0.15, 0.4, 0.16, uniform)
		sm.position.y = -0.18
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(sm)
		var kp := _box(0.16, 0.12, 0.06, gear)                      # 护膝
		kp.position = Vector3(0, -0.05, -0.1)
		kp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(kp)
		var bt := _box(0.16, 0.1, 0.24, boot)                       # 靴(前伸)
		bt.position = Vector3(0, -0.4, -0.03)
		bt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(bt)
		thigh.add_child(knee)
		g.add_child(thigh)
		return { "thigh": thigh, "knee": knee }
	var leg_l: Dictionary = mk_leg.call(-0.11)
	var leg_r: Dictionary = mk_leg.call(0.11)
	g.set_meta("leg_l", leg_l["thigh"])
	g.set_meta("leg_l_knee", leg_l["knee"])
	g.set_meta("leg_r", leg_r["thigh"])
	g.set_meta("leg_r_knee", leg_r["knee"])

	# 上半身组(髋部枢轴)
	var upper := Node3D.new()
	upper.position = Vector3(0, 0.95, 0)
	g.add_child(upper)
	_add(upper, _box(0.42, 0.62, 0.24, uniform), 0, 0.13, 0)      # 躯干
	_add(upper, _box(0.44, 0.4, 0.28, vest), 0, 0.17, 0)          # 背心
	_add(upper, _box(0.45, 0.05, 0.29, accent), 0, 0.35, 0)       # 队伍识别条
	_add(upper, _box(0.4, 0.1, 0.26, gear), 0, 0.42, 0)           # 肩颈线/领口护具
	_add(upper, _box(0.2, 0.22, 0.2, skin_mat), 0, 0.57, 0)           # 头
	_add(upper, _box(0.24, 0.12, 0.24, helmet), 0, 0.69, 0)       # 头盔
	_add(upper, _box(0.25, 0.03, 0.25, gear), 0, 0.635, 0)        # 头盔箍带
	_add(upper, _box(0.06, 0.05, 0.05, gear), 0, 0.665, -0.13)    # 夜视仪座

	# ============ 兵种专属外观(明显区分) ============
	match class_id:
		"assault":
			# 突击兵:胸前双弹匣包 + 左臂医疗十字章 + 大腿手雷包(轻装突击)
			_add(upper, _box(0.1, 0.12, 0.06, gear2), -0.08, 0.14, -0.16)
			_add(upper, _box(0.1, 0.12, 0.06, gear2), 0.08, 0.14, -0.16)
			_add(upper, _box(0.07, 0.1, 0.05, gear), 0.15, -0.05, -0.13)
			var cross1 := _box(0.1, 0.03, 0.02, _mat(Color.html("#e8e8e8"), 0.8, true))
			_add(upper, cross1, -0.225, 0.32, 0.02)
			var cross2 := _box(0.035, 0.1, 0.02, _mat(Color.html("#e8e8e8"), 0.8, true))
			_add(upper, cross2, -0.225, 0.32, 0.02)
			var crossm1 := _box(0.08, 0.024, 0.021, _mat(Color.html("#cc2222"), 0.8, true))
			_add(upper, crossm1, -0.225, 0.32, 0.025)
			var crossm2 := _box(0.026, 0.08, 0.021, _mat(Color.html("#cc2222"), 0.8, true))
			_add(upper, crossm2, -0.225, 0.32, 0.025)
		"engineer":
			# 工程兵:加厚防弹护胸 + 背负 RPG 发射筒 + 护目镜 + 工具腰包
			_add(upper, _box(0.46, 0.34, 0.31, vest), 0, 0.15, 0)                 # 加厚护板
			_add(upper, _box(0.3, 0.16, 0.06, gear), 0, 0.3, -0.16)               # 胸前工具板
			var tube := _cylx(0.055, 0.055, 0.78, gear2)                          # RPG 背筒
			tube.rotation.z = 0.42
			tube.rotation.x = 0.12
			tube.position = Vector3(-0.12, 0.32, 0.2)
			tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			upper.add_child(tube)
			var tube_head := _cylx(0.075, 0.06, 0.1, gear)
			tube_head.rotation.z = 0.42
			tube_head.position = Vector3(-0.28, 0.62, 0.2)
			tube_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			upper.add_child(tube_head)
			_add(upper, _box(0.2, 0.06, 0.05, gear), 0, 0.6, -0.115)              # 护目镜(推至盔沿)
			_add(upper, _box(0.34, 0.12, 0.2, gear2), 0, -0.12, 0.1)              # 工具腰包
		"support":
			# 支援兵:大弹药背包 + 斜挎弹链 + 腿部弹鼓包(火力后勤)
			_add(upper, _box(0.36, 0.42, 0.18, gear2), 0, 0.18, 0.21)             # 弹药背包
			_add(upper, _box(0.3, 0.1, 0.2, gear), 0, 0.42, 0.19)                 # 包顶盖
			for i in 7:                                                           # 斜挎弹链(铜)
				var lk := _box(0.035, 0.07, 0.03, brass)
				lk.rotation.z = -0.5
				_add(upper, lk, -0.14 + i * 0.045, 0.32 - i * 0.045, -0.155)
			_add(upper, _box(0.12, 0.14, 0.08, gear2), -0.24, -0.06, 0.02)        # 腿侧弹鼓包
			_add(upper, _box(0.12, 0.14, 0.08, gear2), 0.24, -0.06, 0.02)
		"recon":
			# 侦察兵:吉利服兜帽 + 蒙面 + 背负天线 + 伪装布条(隐蔽猎手)
			_add(upper, _box(0.26, 0.14, 0.26, uniform), 0, 0.7, 0)               # 兜帽
			_add(upper, _box(0.27, 0.2, 0.06, uniform), 0, 0.62, 0.13)            # 兜帽后垂布
			_add(upper, _box(0.2, 0.08, 0.04, gear), 0, 0.54, -0.11)              # 蒙面巾
			var ant := _cylx(0.006, 0.006, 0.72, gear)                            # 背负天线
			ant.rotation.x = -0.22
			ant.position = Vector3(0.16, 0.62, 0.2)
			ant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			upper.add_child(ant)
			_add(upper, _box(0.1, 0.16, 0.08, gear2), 0.14, 0.3, 0.18)            # 电台包
			for i in 4:                                                           # 肩部伪装布条
				var st := _box(0.05, 0.16, 0.03, uniform)
				st.rotation.z = -0.25 + i * 0.17
				_add(upper, st, -0.18 + i * 0.12, 0.44, 0.06)

	# 皮肤轻量装饰(头盔套/肩带/背包色块,仅非 standard 皮肤)
	if skin != "standard":
		_apply_skin_decor(upper, class_id, skin, pal)

	# 持枪臂组(rig)
	var rig := Node3D.new()
	rig.position = Vector3(0, 0.35, 0)
	var arm_l := _box(0.11, 0.11, 0.42, uniform)
	arm_l.position = Vector3(-0.18, -0.02, -0.24)
	arm_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rig.add_child(arm_l)
	var arm_r := _box(0.11, 0.11, 0.42, uniform)
	arm_r.position = Vector3(0.18, -0.02, -0.24)
	arm_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rig.add_child(arm_r)
	var gun := WeaponModels.build(weapon_id, false)
	gun.scale = Vector3.ONE * 1.15
	gun.position = Vector3(0.1, 0, -0.45)
	rig.add_child(gun)
	upper.add_child(rig)
	g.set_meta("rig", rig)
	g.set_meta("upper", upper)
	return g


## 皮肤轻量装饰:头盔套 + 双肩带 + 腰封 + 兵种色块 + 夜视仪(夜间/雪地)
static func _apply_skin_decor(upper: Node3D, class_id: String, skin: String, pal: Dictionary) -> void:
	var cover := _mat(Color.html(pal.get("cover", pal["helmet"])), 0.9)
	var strap := _mat(Color.html(pal.get("strap", pal["gear2"])), 0.92)
	_add(upper, _box(0.26, 0.022, 0.26, cover), 0, 0.752, 0)                 # 头盔套(盖住盔顶)
	_add(upper, _box(0.09, 0.03, 0.27, strap), -0.13, 0.4, -0.02)             # 左肩带
	_add(upper, _box(0.09, 0.03, 0.27, strap), 0.13, 0.4, -0.02)              # 右肩带
	_add(upper, _box(0.4, 0.04, 0.02, strap), 0, 0.06, 0.14)                  # 腰封色带
	match class_id:
		"support":
			_add(upper, _box(0.32, 0.3, 0.02, strap), 0, 0.18, 0.32)           # 背包盖布
		"recon":
			_add(upper, _box(0.2, 0.07, 0.05, cover), 0.16, 0.33, 0.19)        # 电台包盖
			for i in 5:                                                        # 额外伪装布条
				var st := _box(0.05, 0.14, 0.03, cover)
				st.rotation.z = -0.3 + i * 0.2
				_add(upper, st, -0.2 + i * 0.1, 0.46, 0.08)
		"assault":
			_add(upper, _box(0.1, 0.05, 0.04, strap), 0.08, 0.24, -0.17)       # 胸前袋盖
		"engineer":
			_add(upper, _box(0.34, 0.035, 0.21, strap), 0, 0.13, 0.05)         # 护胸横带
	if skin == "night" or skin == "arctic":
		var nvg := _mat(Color(0.1, 0.9, 0.3), 0.3, true)                       # 夜视仪(绿透镜)
		_add(upper, _box(0.026, 0.02, 0.03, nvg), -0.035, 0.66, -0.128)
		_add(upper, _box(0.026, 0.02, 0.03, nvg), 0.035, 0.66, -0.128)


## 圆柱网格助手(z 轴,供背筒/天线等)
static func _cylx(rt: float, rb: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	return mi


## 玩家第一人称下半身(低头可见 + 投影)
## skin: 皮肤 id(与 build_soldier 共用 SKINS 表;本身体无头/盔,采用 assault 兵种配色,
##        standard 与旧版完全一致);未知皮肤 id 回退 standard
## 返回 Node3D,meta: leg_l{thigh,knee}, leg_r
static func build_player_body(skin := "standard") -> Node3D:
	var g := Node3D.new()
	g.name = "PlayerBody"
	var pal: Dictionary = SKINS.get("assault", SKINS["assault"]).get(skin, SKINS["assault"]["standard"])
	var uniform := _mat(Color.html(pal["uniform"]), 0.95)
	var vest := _mat(Color.html(pal["vest"]), 0.9)
	var boot := _mat(Color.html("#2a2622"), 0.9)
	var accent := _mat(Color.html("#00ff88"), 0.9, true)

	var mk_leg := func(x: float) -> Dictionary:
		var leg := Node3D.new()
		leg.position = Vector3(x, 0.85, 0)
		var thigh := _box(0.18, 0.4, 0.2, uniform)
		thigh.position.y = -0.2
		thigh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		leg.add_child(thigh)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.42, 0)
		var shin := _box(0.17, 0.45, 0.19, boot)
		shin.position.y = -0.21
		shin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		knee.add_child(shin)
		leg.add_child(knee)
		g.add_child(leg)
		return { "thigh": leg, "knee": knee }
	var leg_l: Dictionary = mk_leg.call(-0.11)
	var leg_r: Dictionary = mk_leg.call(0.11)
	g.set_meta("leg_l", leg_l["thigh"])
	g.set_meta("leg_l_knee", leg_l["knee"])
	g.set_meta("leg_r", leg_r["thigh"])
	g.set_meta("leg_r_knee", leg_r["knee"])
	# 上半身组(髋部枢轴;不建头/头盔,避免遮挡第一人称相机)
	var upper := Node3D.new()
	upper.position = Vector3(0, 0.95, 0)
	g.add_child(upper)
	_add(upper, _box(0.4, 0.6, 0.24, uniform), 0, 0.12, 0)        # 躯干
	_add(upper, _box(0.42, 0.4, 0.28, vest), 0, 0.15, 0)          # 背心
	_add(upper, _box(0.43, 0.05, 0.29, accent), 0, 0.33, 0)       # 识别条
	# 双肩/上臂
	var sho_l := _box(0.13, 0.36, 0.15, uniform)
	sho_l.position = Vector3(-0.27, 0.22, 0)
	sho_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	upper.add_child(sho_l)
	var sho_r := _box(0.13, 0.36, 0.15, uniform)
	sho_r.position = Vector3(0.27, 0.22, 0)
	sho_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	upper.add_child(sho_r)
	# 持枪投影代理(只投影不渲染:地面可见持枪姿态的影子)
	var gun_proxy := _box(0.055, 0.09, 0.5, uniform)
	gun_proxy.position = Vector3(0.16, 0.28, -0.35)
	gun_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	upper.add_child(gun_proxy)
	# 前伸小臂投影代理
	var arm_proxy := _box(0.1, 0.1, 0.38, uniform)
	arm_proxy.position = Vector3(-0.2, 0.2, -0.28)
	arm_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	upper.add_child(arm_proxy)
	g.set_meta("upper", upper)
	return g


## 血条(画布贴图 Sprite3D,对应 makeHealthBar)
static func make_health_bar() -> Dictionary:
	var img := Image.create(64, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.pixel_size = 0.9 / 64.0
	sprite.no_depth_test = true
	sprite.position.y = 1.95
	sprite.visible = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	return { "sprite": sprite, "img": img, "tex": tex }


static func update_health_bar(hb: Dictionary, health: float, team: String) -> void:
	var img: Image = hb["img"]
	img.fill(Color(0, 0, 0, 0.7))
	var col := Color(0.0, 1.0, 0.53) if team == "us" else Color(1.0, 0.33, 0.0)
	var w := int(clampf(health / 100.0, 0.0, 1.0) * 62.0)
	if w > 0:
		img.fill_rect(Rect2i(1, 1, w, 8), col)
	(hb["tex"] as ImageTexture).update(img)
	(hb["sprite"] as Sprite3D).visible = true
