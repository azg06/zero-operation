class_name WeaponsData
## 武器与兵种数据(对应 weapons.js 中的 WEAPONS / CLASSES)

class WeaponDef extends RefCounted:
	var name := ""
	var cn := ""
	var kind := "rifle"
	var auto := false
	var damage := 25.0
	var head_mult := 2.0
	var rpm := 600.0
	var mag := 30
	var reserve := 150
	var reload_time := 2.0
	var ads_time := 0.13
	var zoom_fov := 55.0
	var rng := [30.0, 70.0, 0.6]       # [r0, r1, minMult]
	var sight_y := 0.0755
	var ads_z := -0.24
	var recoil_pitch := 0.4
	var recoil_yaw := 0.16
	var recoil_vm := 0.045
	var spread_hip := 1.5
	var spread_ads := 0.12
	var spread_move := 1.2
	var spread_bloom := 0.22
	var spread_bloom_max := 1.6
	var tracer := Color(1.0, 0.85, 0.63)
	var pellets := 1
	var scope := false
	var projectile := false
	var splash := 6.5
	var speed := 38.0
	var veh_dmg := 0.5
	var view_hip: Variant = null         # Vector3 覆盖腰射位
	var view_ads: Variant = null         # Vector3 覆盖瞄准位
	# === 弹道(3A 手感) ===
	var bullet_speed := 850.0            # 初速 m/s(决定下坠与命中时差)
	var bullet_drop := 1.0               # 下坠系数(0=激光,1=真实感)
	var penetration := 0                 # 穿透木掩体次数(0 不可穿)
	# === 后坐力曲线 ===
	var recoil_first := 1.3              # 首发后坐力倍率(首发高)
	var recoil_ramp := 0.07              # 每发连射递增增量(上限 1.5x)
	var recoil_recover := 0.6            # 停火多久连射计数复位(s)
	var recoil_cam := 0.006              # 摄像机微后坐(开火视角震动)
	# === 换弹 ===
	var reload_tac := 0.0                # 战术换弹时长(0=自动 = reload_time×0.78)


class ClassDef extends RefCounted:
	var cn := ""
	var en := ""
	var icon := ""
	var color := Color.WHITE
	var primary := ""
	var weapons: Array = []
	var shotguns: Array = []
	var secondaries: Array = []
	var gadget := ""
	var gadget_cn := ""
	var gadget_count := 2
	var desc := ""


static func _w(id_name: String, cn: String, kind: String, auto: bool, damage: float, head_mult: float,
		rpm: float, mag: int, reserve: int, reload_time: float, ads_time: float, zoom_fov: float,
		rng: Array, sight_y: float, ads_z: float, recoil: Array, spread: Array, tracer: Color,
		extra := {}) -> WeaponDef:
	var d := WeaponDef.new()
	d.name = id_name
	d.cn = cn
	d.kind = kind
	d.auto = auto
	d.damage = damage
	d.head_mult = head_mult
	d.rpm = rpm
	d.mag = mag
	d.reserve = reserve
	d.reload_time = reload_time
	d.ads_time = ads_time
	d.zoom_fov = zoom_fov
	d.rng = rng
	d.sight_y = sight_y
	d.ads_z = ads_z
	d.recoil_pitch = recoil[0]
	d.recoil_yaw = recoil[1]
	d.recoil_vm = recoil[2]
	d.spread_hip = spread[0]
	d.spread_ads = spread[1]
	d.spread_move = spread[2]
	d.spread_bloom = spread[3]
	d.spread_bloom_max = spread[4]
	d.tracer = tracer
	# 兵种口径默认穿透力(木板可穿、混凝土不可;狙击可穿两层)
	match kind:
		"pistol", "smg":
			d.penetration = 0
		"shotgun", "rifle", "lmg", "dmr":
			d.penetration = 1
		"sniper":
			d.penetration = 2
	for k in extra:
		d.set(k, extra[k])
	return d


static func build_weapons() -> Dictionary:
	var WD := {}
	WD["m4"] = _w("M4A1", "M4A1 突击步枪", "rifle", true, 26, 2.0, 750, 30, 150, 2.7, 0.13, 55,
		[30, 70, 0.6], 0.108, -0.24, [0.42, 0.16, 0.045], [1.5, 0.12, 1.2, 0.22, 1.6], Color(1, 0.85, 0.63),
		{ "bullet_speed": 880, "bullet_drop": 0.85 })
	WD["ak"] = _w("AK-47", "AK-47 突击步枪", "rifle", true, 33, 2.0, 600, 30, 120, 2.9, 0.15, 55,
		[32, 75, 0.55], 0.104, -0.24, [0.6, 0.26, 0.06], [1.7, 0.16, 1.3, 0.3, 2.0], Color(1, 0.75, 0.5),
		{ "bullet_speed": 720, "bullet_drop": 1.15, "recoil_first": 1.45, "recoil_ramp": 0.1 })
	WD["mp5"] = _w("MP5", "MP5 冲锋枪", "smg", true, 22, 1.8, 820, 32, 160, 1.8, 0.11, 60,
		[18, 45, 0.5], 0.09, -0.23, [0.3, 0.14, 0.035], [1.2, 0.14, 0.7, 0.18, 1.3], Color(1, 0.94, 0.75),
		{ "bullet_speed": 400, "bullet_drop": 1.1, "reload_tac": 1.25 })
	WD["m249"] = _w("M249", "M249 轻机枪", "lmg", true, 26, 1.8, 800, 100, 200, 5.5, 0.22, 58,
		[35, 80, 0.65], 0.125, -0.25, [0.5, 0.3, 0.055], [2.6, 0.3, 1.8, 0.12, 1.1], Color(1, 0.69, 0.38),
		{ "bullet_speed": 915, "bullet_drop": 0.9, "reload_tac": 4.3 })
	WD["awm"] = _w("AWM", "AWM 狙击步枪", "sniper", false, 95, 2.5, 42, 5, 30, 3.6, 0.28, 12,
		[120, 220, 0.85], 0.115, -0.15, [2.6, 0.5, 0.14], [5.0, 0.02, 3.0, 0, 0], Color(0.82, 0.91, 1),
		{ "scope": true, "bullet_speed": 950, "bullet_drop": 0.55, "recoil_cam": 0.014, "reload_tac": 2.7 })
	# 狙击 zoom_fov 12-14:镜内视野更窄、放大更强(目镜张角 35.7° / 镜内 FOV 12° ≈ 感知 2.9×)
	WD["m1014"] = _w("M1014", "M1014 霰弹枪", "shotgun", false, 11, 1.5, 78, 7, 42, 4.9, 0.13, 62,
		[10, 26, 0.25], 0.096, -0.24, [1.8, 0.4, 0.12], [3.2, 2.2, 0.8, 0, 0], Color(1, 0.75, 0.56),
		{ "pellets": 9, "bullet_speed": 380, "bullet_drop": 1.35 })
	WD["m1911"] = _w("M1911", "M1911 手枪", "pistol", false, 28, 2.0, 380, 8, 64, 1.7, 0.09, 62,
		[20, 50, 0.5], 0.073, -0.2, [0.55, 0.2, 0.05], [1.0, 0.15, 0.8, 0.25, 1.4], Color(1, 0.94, 0.75),
		{ "bullet_speed": 350, "bullet_drop": 1.05, "reload_tac": 1.15 })
	WD["scar"] = _w("SCAR-H", "SCAR-H 战斗步枪", "rifle", true, 34, 2.0, 550, 20, 100, 2.5, 0.15, 54,
		[35, 80, 0.6], 0.112, -0.24, [0.62, 0.24, 0.06], [1.6, 0.14, 1.2, 0.28, 1.8], Color(1, 0.82, 0.56),
		{ "bullet_speed": 800, "bullet_drop": 1.05, "reload_tac": 1.85 })
	WD["aug"] = _w("AUG A3", "AUG A3 突击步枪", "rifle", true, 27, 2.0, 700, 30, 150, 2.6, 0.11, 56,
		[30, 70, 0.6], 0.125, -0.23, [0.38, 0.14, 0.04], [1.4, 0.11, 1.1, 0.2, 1.5], Color(0.82, 1, 0.69),
		{ "bullet_speed": 940, "bullet_drop": 0.85, "reload_tac": 1.9 })
	WD["ump"] = _w("UMP45", "UMP45 冲锋枪", "smg", true, 28, 1.8, 600, 25, 150, 2.1, 0.12, 60,
		[20, 48, 0.5], 0.1, -0.23, [0.34, 0.12, 0.035], [1.1, 0.13, 0.7, 0.2, 1.3], Color(1, 0.94, 0.75),
		{ "bullet_speed": 410, "bullet_drop": 1.05, "reload_tac": 1.4 })
	WD["p90"] = _w("P90", "P90 个人防卫武器", "smg", true, 20, 1.8, 900, 50, 200, 2.5, 0.11, 60,
		[18, 45, 0.5], 0.078, -0.22, [0.28, 0.16, 0.03], [1.3, 0.16, 0.8, 0.16, 1.2], Color(0.75, 0.88, 1),
		{ "bullet_speed": 715, "bullet_drop": 0.95, "reload_tac": 1.7 })
	WD["pkm"] = _w("PKM", "PKM 通用机枪", "lmg", true, 32, 1.8, 650, 100, 200, 6.0, 0.24, 58,
		[38, 85, 0.65], 0.122, -0.25, [0.58, 0.32, 0.06], [2.7, 0.32, 1.9, 0.13, 1.2], Color(1, 0.69, 0.38),
		{ "bullet_speed": 830, "bullet_drop": 1.0, "reload_tac": 4.7 })
	WD["rpd"] = _w("RPD", "RPD 轻机枪", "lmg", true, 26, 1.8, 700, 75, 225, 5.1, 0.22, 58,
		[35, 80, 0.65], 0.115, -0.25, [0.46, 0.26, 0.05], [2.4, 0.3, 1.7, 0.14, 1.2], Color(1, 0.75, 0.5),
		{ "bullet_speed": 740, "bullet_drop": 1.05, "reload_tac": 4.0 })
	WD["m24"] = _w("M24", "M24 狙击步枪", "sniper", false, 80, 2.5, 55, 5, 35, 3.1, 0.24, 13,
		[110, 200, 0.85], 0.112, -0.15, [2.2, 0.45, 0.12], [4.5, 0.02, 2.8, 0, 0], Color(0.82, 0.91, 1),
		{ "scope": true, "bullet_speed": 800, "bullet_drop": 0.6, "recoil_cam": 0.012, "reload_tac": 2.3 })
	# 狙击 zoom_fov 12-14:镜内视野更窄、放大更强(m24 张角 35.7°/13° ≈ 感知 2.75×)
	WD["svd"] = _w("SVD", "SVD 狙击步枪", "sniper", false, 55, 2.2, 200, 10, 50, 2.3, 0.26, 14,
		[90, 180, 0.8], 0.115, -0.15, [1.4, 0.35, 0.09], [3.5, 0.05, 2.2, 0.5, 1.5], Color(1, 0.82, 0.63),
		{ "scope": true, "bullet_speed": 830, "bullet_drop": 0.7, "recoil_cam": 0.01, "reload_tac": 1.7 })
	# 狙击 zoom_fov 12-14:镜内视野更窄、放大更强(svd 张角 35.7°/14° ≈ 感知 2.55×)
	WD["rpg"] = _w("RPG-7", "RPG-7 火箭筒", "rpg", false, 120, 1.0, 30, 1, 4, 3.0, 0.2, 60,
		[999, 999, 1], 0.0755, -0.24, [1.5, 0.3, 0.12], [0.5, 0.1, 0.5, 0, 0], Color(1, 0.88, 0.63),
		{ "projectile": true, "splash": 6.5, "speed": 48.0,  # 非锁定直射弹速 38→48:射程提升
		  "view_hip": Vector3(0.24, -0.24, -0.52), "view_ads": Vector3(0, -0.085, -0.4) })
	WD["g17"] = _w("G17", "格洛克17 手枪", "pistol", false, 21, 2.0, 520, 17, 102, 1.4, 0.07, 63,
		[16, 42, 0.5], 0.0685, -0.2, [0.3, 0.11, 0.034], [1.15, 0.18, 0.85, 0.15, 0.9], Color(1, 0.94, 0.75),
		{ "bullet_speed": 380, "bullet_drop": 1.0, "reload_tac": 0.95 })
	WD["p226"] = _w("P226", "P226 手枪", "pistol", false, 34, 2.1, 300, 12, 60, 1.8, 0.1, 61,
		[24, 56, 0.52], 0.0735, -0.2, [0.52, 0.16, 0.048], [0.8, 0.07, 0.65, 0.2, 1.0], Color(0.85, 0.93, 1),
		{ "bullet_speed": 400, "bullet_drop": 0.95, "reload_tac": 1.25 })
	WD["deagle"] = _w("沙漠之鹰", "沙漠之鹰 手枪", "pistol", false, 56, 2.2, 155, 7, 28, 2.3, 0.13, 58,
		[30, 70, 0.45], 0.0825, -0.2, [2.3, 0.6, 0.16], [1.9, 0.24, 1.3, 0.9, 2.6], Color(1, 0.85, 0.63),
		{ "bullet_speed": 470, "bullet_drop": 0.85, "recoil_cam": 0.011, "reload_tac": 1.6 })
	WD["m93r"] = _w("M93R", "M93R 冲锋手枪", "pistol", true, 16, 1.8, 1100, 21, 126, 1.7, 0.08, 62,
		[13, 34, 0.42], 0.07, -0.2, [0.36, 0.3, 0.038], [1.7, 0.42, 1.15, 0.14, 1.6], Color(1, 0.91, 0.69),
		{ "bullet_speed": 400, "bullet_drop": 1.05, "reload_tac": 1.1 })
	WD["spas12"] = _w("SPAS-12", "SPAS-12 战斗霰弹枪", "shotgun", false, 13, 1.5, 68, 8, 40, 5.3, 0.14, 62,
		[12, 30, 0.28], 0.1, -0.24, [2.1, 0.45, 0.13], [3.0, 2.0, 0.8, 0, 0], Color(1, 0.75, 0.56),
		{ "pellets": 8, "bullet_speed": 400, "bullet_drop": 1.35 })
	return WD


static func build_classes() -> Dictionary:
	var secondaries := ["m1911", "g17", "p226", "deagle", "m93r"]
	var CD := {}
	# 突击兵:前线破阵(步枪 + 霰弹 + 烟雾弹 + C5 + 医疗针自用)
	var assault := ClassDef.new()
	assault.cn = "突击兵"; assault.en = "ASSAULT"; assault.icon = "突"; assault.color = Color(0.5, 0.82, 1.0)
	assault.primary = "m4"; assault.weapons = ["m4", "ak", "scar", "aug"]
	assault.shotguns = ["m1014", "spas12"]; assault.secondaries = secondaries
	assault.gadget = "medkit"; assault.gadget_cn = "医疗针"; assault.gadget_count = 2
	assault.desc = "前线破阵者。冲锋夺点、近战歼敌;烟雾弹掩护推进,C5 炸药摧毁工事载具,医疗针仅限自救。"
	CD["assault"] = assault
	# 工程兵:载具克星与守护者(轻机枪 + RPG-7 + 反坦克地雷 + 维修工具)
	var engineer := ClassDef.new()
	engineer.cn = "工程兵"; engineer.en = "ENGINEER"; engineer.icon = "工"; engineer.color = Color(1.0, 0.77, 0.42)
	engineer.primary = "m249"; engineer.weapons = ["m249", "pkm", "rpd"]
	engineer.secondaries = secondaries
	engineer.gadget = "rpg"; engineer.gadget_cn = "RPG-7"; engineer.gadget_count = 4
	engineer.desc = "载具克星与守护者。RPG-7 反载具(按 3),维修工具修复己方载具(靠近按 F),反坦克地雷预埋。"
	CD["engineer"] = engineer
	# 支援兵:战场生命线(冲锋枪 + 弹药箱/医疗箱 + 烟雾弹)
	var support := ClassDef.new()
	support.cn = "支援兵"; support.en = "SUPPORT"; support.icon = "援"; support.color = Color(0.62, 0.88, 0.54)
	support.primary = "mp5"; support.weapons = ["mp5", "ump", "p90"]
	support.secondaries = secondaries
	support.gadget = "ammopack"; support.gadget_cn = "弹药箱"; support.gadget_count = 2
	support.desc = "战场生命线。紧随小队提供弹药与医疗补给(按 F 部署补给箱,圈内回血+补弹),烟雾弹掩护转移。"
	CD["support"] = support
	# 侦察兵:战场之眼(狙击 + 标记 + 重生信标)
	var recon := ClassDef.new()
	recon.cn = "侦察兵"; recon.en = "RECON"; recon.icon = "侦"; recon.color = Color(0.88, 0.63, 1.0)
	recon.primary = "awm"; recon.weapons = ["awm", "m24", "svd"]
	recon.secondaries = secondaries
	recon.gadget = "sensor"; recon.gadget_cn = "动态探测器"; recon.gadget_count = 2
	recon.desc = "战场之眼。狙击与情报标记(Q 索敌),部署重生信标为小队提供隐蔽重生点(按 F)。"
	CD["recon"] = recon
	return CD


static var _weapons: Dictionary = {}
static var _classes: Dictionary = {}
const SECONDARIES: Array = ["m1911", "g17", "p226", "deagle", "m93r"]


## 惰性初始化(GDScript 静态变量初始化限制)
static func W() -> Dictionary:
	if _weapons.is_empty():
		_weapons = build_weapons()
	return _weapons


static func C() -> Dictionary:
	if _classes.is_empty():
		_classes = build_classes()
	return _classes
