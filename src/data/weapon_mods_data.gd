class_name WeaponModsData
## 枪械模块化改装:数据表 / 兼容规则 / 存档 / 属性汇总(数据驱动,统一资源定义)
## 槽位(muzzle/barrel/grip/stock/mag/trigger/optic/laser)按武器种类配置可用性,
## 附件按 MOD_RESTRICT 限制适用种类;新增枪械无需改代码,仅需在武器数据中归类。

const SLOT_NAMES := {
	"muzzle": "枪口", "barrel": "枪管", "grip": "握把", "stock": "枪托",
	"mag": "弹匣", "trigger": "扳机", "optic": "瞄具", "laser": "镭射/手电",
}

## 属性键(gun.gd 应用层消费):
## mag_ammo(int 弹匣容量增量) reload_mult(换弹时长倍率) recoil_mult(后座倍率)
## recoil_pitch_mult(垂直后座倍率) recoil_yaw_mult(水平后座倍率)
## hip_spread_mult(腰射散布) spread_mult(整体散布) ads_speed_mult(开镜速度)
## fire_rate_mult(射速) dmg_mult(伤害) suppress(bool 静音)
## mobility_mult(移动速度倍率,重量体现) aim_stability(开镜散布倍率)
const MODS := {
	"muzzle": {
		"muz_std":   { "n": "标准枪口", "d": "原厂枪口,无加成", "s": {} },
		"muz_supp":  { "n": "消音器", "d": "射击静音(敌我难辨),伤害 -5%", "s": { "suppress": true, "dmg_mult": 0.95 } },
		"muz_flash": { "n": "消焰器", "d": "后座 -12%", "s": { "recoil_mult": 0.88 } },
		"muz_brk":   { "n": "制退器", "d": "垂直后座 -20%,散布 +8%", "s": { "recoil_pitch_mult": 0.8, "spread_mult": 1.08 } },
		"muz_comp":  { "n": "补偿器", "d": "水平后座 -35%(枪口不跳),垂直后座 +10%,散布 -5%", "s": { "recoil_yaw_mult": 0.65, "recoil_pitch_mult": 1.1, "spread_mult": 0.95 } },
		"muz_choke": { "n": "收束器", "d": "弹丸散布 -25%,伤害 +10%(射程延伸)", "s": { "spread_mult": 0.75, "dmg_mult": 1.1 } },
	},
	"barrel": {
		"barrel_std":   { "n": "标准枪管", "d": "原厂枪管", "s": {} },
		"barrel_long":  { "n": "长枪管", "d": "开镜散布 -10%,开镜速度 -12%,移动 -4%,伤害 +5%", "s": { "aim_stability": 0.9, "ads_speed_mult": 0.88, "mobility_mult": 0.96, "dmg_mult": 1.05 } },
		"barrel_short": { "n": "短枪管", "d": "开镜速度 +15%,移动 +6%,散布 +10%,后座 +12%", "s": { "ads_speed_mult": 1.15, "mobility_mult": 1.06, "spread_mult": 1.1, "recoil_mult": 1.12 } },
		"barrel_heavy": { "n": "重型枪管", "d": "后座 -15%,射速 -6%,移动 -8%", "s": { "recoil_mult": 0.85, "fire_rate_mult": 0.94, "mobility_mult": 0.92 } },
	},
	"grip": {
		"grip_std":   { "n": "标准握把", "d": "原厂握把", "s": {} },
		"grip_vert":  { "n": "垂直握把", "d": "后座 -18%,开镜速度 -10%", "s": { "recoil_mult": 0.82, "ads_speed_mult": 0.9 } },
		"grip_ang":   { "n": "斜角握把", "d": "开镜速度 +15%,后座 +6%", "s": { "ads_speed_mult": 1.15, "recoil_mult": 1.06 } },
		"grip_light": { "n": "轻量握把", "d": "移动腰射精度 +10%", "s": { "hip_spread_mult": 0.9 } },
		"grip_fg":    { "n": "前握把", "d": "开镜速度 +8%,后座 -8%(均衡)", "s": { "ads_speed_mult": 1.08, "recoil_mult": 0.92 } },
	},
	"stock": {
		"stock_std":   { "n": "标准枪托", "d": "原厂枪托", "s": {} },
		"stock_light": { "n": "轻型枪托", "d": "开镜速度 +12%,后座 +8%,移动 +4%", "s": { "ads_speed_mult": 1.12, "recoil_mult": 1.08, "mobility_mult": 1.04 } },
		"stock_heavy": { "n": "重型枪托", "d": "后座 -14%,移动 -10%", "s": { "recoil_mult": 0.86, "mobility_mult": 0.9 } },
		"stock_fold":  { "n": "折叠枪托", "d": "移动 +8%,后座 +10%(腰射出枪快)", "s": { "mobility_mult": 1.08, "recoil_mult": 1.1 } },
	},
	"mag": {
		"mag_std":   { "n": "标准弹匣", "d": "原厂弹匣,性能均衡", "s": {} },
		"mag_ext":   { "n": "扩容弹匣", "d": "弹容量 +12,换弹耗时 +25%", "s": { "mag_ammo": 12, "reload_mult": 1.25 } },
		"mag_quick": { "n": "快拔弹匣", "d": "换弹耗时 -30%,弹容量 -8", "s": { "mag_ammo": -8, "reload_mult": 0.7 } },
		"mag_ap":    { "n": "穿甲弹匣", "d": "伤害 +8%,射速 -5%", "s": { "dmg_mult": 1.08, "fire_rate_mult": 0.95 } },
		"mag_drum":  { "n": "弹鼓", "d": "弹容量 +24,换弹耗时 +50%,移动 -5%", "s": { "mag_ammo": 24, "reload_mult": 1.5, "mobility_mult": 0.95 } },
	},
	"trigger": {
		"trig_std":  { "n": "标准扳机", "d": "原厂扳机", "s": {} },
		"trig_comp": { "n": "比赛扳机", "d": "射速 +12%", "s": { "fire_rate_mult": 1.12 } },
		"trig_dual": { "n": "双段扳机", "d": "射速 +6%,散布 -10%", "s": { "fire_rate_mult": 1.06, "spread_mult": 0.9 } },
	},
	"optic": {
		"opt_std":        { "n": "机械瞄具", "d": "原厂机械瞄具", "s": {} },
		"opt_reddot":     { "n": "红点镜", "d": "开镜速度 +20%,散布 -8%", "s": { "ads_speed_mult": 1.2, "spread_mult": 0.92 } },
		"opt_holo":       { "n": "全息镜", "d": "开镜速度 +8%,散布 -15%", "s": { "ads_speed_mult": 1.08, "spread_mult": 0.85 } },
		"opt_reddot_mini": { "n": "微型红点", "d": "开镜速度 +28%,散布 -5%(轻量紧凑)", "s": { "ads_speed_mult": 1.28, "spread_mult": 0.95 } },
		"opt_reddot_dot": { "n": "大视窗红点", "d": "开镜速度 +15%,散布 -10%(大视野)", "s": { "ads_speed_mult": 1.15, "spread_mult": 0.9 } },
		"opt_2x":        { "n": "2 倍战术镜", "d": "2 倍放大,开镜速度 -20%,散布 -25%", "s": { "ads_speed_mult": 0.8, "spread_mult": 0.75 } },
		"opt_1xprism":   { "n": "1 倍棱镜", "d": "开镜散布 -12%,无倍率", "s": { "spread_mult": 0.88 } },
	},
	"laser": {
		"laser_std":  { "n": "无镭射", "d": "无挂载", "s": {} },
		"laser_tac":  { "n": "战术镭射", "d": "腰射散布 -15%(可见红光)", "s": { "hip_spread_mult": 0.85 } },
		"laser_flash": { "n": "战术手电", "d": "腰射散布 -10%,黑暗环境照明", "s": { "hip_spread_mult": 0.9 } },
		"laser_ir":   { "n": "红外镭射", "d": "腰射散布 -20%,开镜速度 -5%(不可见,需夜视)", "s": { "hip_spread_mult": 0.8, "ads_speed_mult": 0.95 } },
	},
}

## 附件适用武器种类限制(空数组=全兼容);muz_choke 仅霰弹,弹鼓不给手枪
const MOD_RESTRICT := {
	"muz_choke": ["shotgun"],
	"mag_drum": ["rifle", "smg", "lmg", "dmr"],
}

## 武器种类 → 可用槽位(结构合理约束,数据驱动;新增种类只需加一行)
const KIND_SLOTS := {
	"rifle":   ["muzzle", "barrel", "grip", "stock", "mag", "trigger", "optic", "laser"],
	"smg":     ["muzzle", "barrel", "grip", "stock", "mag", "trigger", "optic", "laser"],
	"lmg":     ["muzzle", "barrel", "grip", "stock", "mag", "trigger", "optic", "laser"],
	"dmr":     ["muzzle", "barrel", "grip", "stock", "mag", "trigger", "optic", "laser"],
	"sniper":  ["muzzle", "barrel", "grip", "stock", "mag", "trigger", "laser"],
	"pistol":  ["muzzle", "barrel", "mag", "trigger", "optic", "laser"],
	"shotgun": ["muzzle", "barrel", "grip", "stock", "mag", "trigger", "optic", "laser"],
	"rpg":     [],
}


## 槽位默认件(首个=标准件)
static func default_mod(slot: String) -> String:
	for k in MODS.get(slot, {}):
		return k
	return ""


## 兼容规则(数据驱动):槽位按武器种类表,附件按 MOD_RESTRICT
static func is_compatible(weapon_id: String, slot: String, mod_id: String) -> bool:
	if not MODS.has(slot) or not MODS[slot].has(mod_id):
		return false
	var WD := WeaponsData.W()
	if not WD.has(weapon_id):
		return false
	var kind: String = WD[weapon_id].kind
	if not KIND_SLOTS.get(kind, []).has(slot):
		return false
	var restrict: Array = MOD_RESTRICT.get(mod_id, [])
	if not restrict.is_empty() and not restrict.has(kind):
		return false
	return true


## 某武器可用槽位列表(UI 按此动态显示)
static func weapon_slots(weapon_id: String) -> Array:
	var WD := WeaponsData.W()
	if not WD.has(weapon_id):
		return []
	return KIND_SLOTS.get(WD[weapon_id].kind, []).duplicate()


## 每槽默认(标准件);仅含兼容槽位
static func defaults(weapon_id: String) -> Dictionary:
	var out := {}
	for slot in MODS:
		var mid := default_mod(slot)
		if is_compatible(weapon_id, slot, mid):
			out[slot] = mid
	return out


## 读 user://mods_<weapon_id>.cfg;无存档(或武器无数据)返回 defaults()(或 {})
static func load_cfg(weapon_id: String) -> Dictionary:
	var out := {}
	var cf := ConfigFile.new()
	if cf.load("user://mods_%s.cfg" % weapon_id) == OK:
		for slot in cf.get_sections():
			if not SLOT_NAMES.has(slot):
				continue
			var mid: String = cf.get_value(slot, "mod", "")
			if mid != "" and is_compatible(weapon_id, slot, mid):
				out[slot] = mid
	var dft := defaults(weapon_id)
	if out.is_empty() and dft.is_empty():
		return {}
	for slot in dft:
		if not out.has(slot):
			out[slot] = dft[slot]  # 未存档槽位回退默认件
	return out


## 写回 user://mods_<weapon_id>.cfg(不兼容槽位自动过滤)
static func save_cfg(weapon_id: String, cfg: Dictionary) -> void:
	var cf := ConfigFile.new()
	for slot in cfg:
		if SLOT_NAMES.has(slot) and is_compatible(weapon_id, slot, String(cfg[slot])):
			cf.set_value(slot, "mod", cfg[slot])
	cf.save("user://mods_%s.cfg" % weapon_id)


## 汇总某槽位改装件属性(UI 显示增减用);无效槽位/件返回 {}
static func effect_total(cfg: Dictionary, slot: String) -> Dictionary:
	var out := {}
	if not cfg.has(slot) or not MODS.has(slot):
		return out
	var mid = cfg[slot]
	if not MODS[slot].has(mid):
		return out
	var s: Dictionary = MODS[slot][mid].get("s", {})
	for k in s:
		out[k] = s[k]
	return out


## 汇总所有槽位(枪实例应用用):倍率类相乘,弹匣容量相加,静音取或
static func total_effects(cfg: Dictionary) -> Dictionary:
	var out := {}
	for slot in cfg:
		var eff := effect_total(cfg, slot)
		for k in eff:
			var v = eff[k]
			if k == "mag_ammo":
				out[k] = int(out.get(k, 0)) + int(v)
			elif k == "suppress":
				out[k] = bool(out.get(k, false)) or bool(v)
			else:
				out[k] = float(out.get(k, 1.0)) * float(v)
	return out


## 深拷贝 WeaponDef(RefCounted 无 duplicate();用于构建枪实例级改装副本,不污染全局表)
## rng 等 Array 共享引用但只读,无需深复制
static func clone_def(src) -> WeaponsData.WeaponDef:
	var nd := WeaponsData.WeaponDef.new()
	for prop in src.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			nd.set(prop.name, src.get(prop.name))
	return nd
