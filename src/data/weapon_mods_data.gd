class_name WeaponModsData
## 枪械模块化改装:数据表 / 兼容规则 / 存档 / 属性汇总
## 本文件仅提供数据与运行时属性,界面与模型由其他团队并行开发

const SLOT_NAMES := {
	"muzzle": "枪口",
	"mag": "弹匣",
	"grip": "握把",
	"trigger": "扳机",
	"optic": "瞄具",
}

## 属性键(gun.gd 应用层消费):
## mag_ammo(int 弹匣容量增量) reload_mult(换弹时长倍率) recoil_mult(后座倍率)
## recoil_pitch_mult(垂直后座倍率,扩展键:制退器仅削垂直后座)
## hip_spread_mult(腰射散布) spread_mult(整体散布) ads_speed_mult(开镜速度)
## fire_rate_mult(射速) dmg_mult(伤害) suppress(bool 静音)
const MODS := {
	"mag": {
		"mag_std":   { "n": "标准弹匣", "d": "原厂弹匣,性能均衡", "s": {} },
		"mag_ext":   { "n": "扩容弹匣", "d": "弹容量 +12,换弹耗时 +25%", "s": { "mag_ammo": 12, "reload_mult": 1.25 } },
		"mag_quick": { "n": "快拔弹匣", "d": "换弹耗时 -30%,弹容量 -8", "s": { "mag_ammo": -8, "reload_mult": 0.7 } },
		"mag_ap":    { "n": "穿甲弹匣", "d": "伤害 +8%,射速 -5%", "s": { "dmg_mult": 1.08, "fire_rate_mult": 0.95 } },
	},
	"muzzle": {
		"muz_std":  { "n": "标准枪口", "d": "原厂枪口", "s": {} },
		"muz_supp": { "n": "消音器", "d": "射击静音(敌我难辨),伤害 -5%", "s": { "suppress": true, "dmg_mult": 0.95 } },
		"muz_flash": { "n": "消焰器", "d": "后座 -12%", "s": { "recoil_mult": 0.88 } },
		"muz_brk":  { "n": "制退器", "d": "垂直后座 -20%,散布 +8%", "s": { "recoil_pitch_mult": 0.8, "spread_mult": 1.08 } },
	},
	"grip": {
		"grip_std":  { "n": "标准握把", "d": "原厂握把", "s": {} },
		"grip_vert": { "n": "垂直握把", "d": "后座 -18%,开镜速度 -10%", "s": { "recoil_mult": 0.82, "ads_speed_mult": 0.9 } },
		"grip_ang":  { "n": "斜角握把", "d": "开镜速度 +15%,后座 +6%", "s": { "ads_speed_mult": 1.15, "recoil_mult": 1.06 } },
		"grip_light": { "n": "轻量握把", "d": "移动腰射精度 +10%", "s": { "hip_spread_mult": 0.9 } },
	},
	"trigger": {
		"trig_std":  { "n": "标准扳机", "d": "原厂扳机", "s": {} },
		"trig_comp": { "n": "比赛扳机", "d": "射速 +12%", "s": { "fire_rate_mult": 1.12 } },
		"trig_dual": { "n": "双段扳机", "d": "射速 +6%,散布 -10%", "s": { "fire_rate_mult": 1.06, "spread_mult": 0.9 } },
	},
	"optic": {
		"opt_std":   { "n": "机械瞄具", "d": "原厂机械瞄具", "s": {} },
		"opt_reddot": { "n": "红点镜", "d": "开镜速度 +20%,散布 -8%", "s": { "ads_speed_mult": 1.2, "spread_mult": 0.92 } },
		"opt_holo":  { "n": "全息镜", "d": "开镜速度 +8%,散布 -15%", "s": { "ads_speed_mult": 1.08, "spread_mult": 0.85 } },
		# 历史说明:4 倍镜(opt_4x,ads_speed 0.8/spread 0.75)已于方案回退时移除
	},
}


## 槽位默认件(首个=标准件)
static func default_mod(slot: String) -> String:
	for k in MODS.get(slot, {}):
		return k
	return ""


## 兼容规则:pistol 类无 optic 槽;shotgun 类无 muzzle/optic 槽;其余全兼容
static func is_compatible(weapon_id: String, slot: String, mod_id: String) -> bool:
	if not MODS.has(slot) or not MODS[slot].has(mod_id):
		return false
	var WD := WeaponsData.W()
	if not WD.has(weapon_id):
		return false
	var kind: String = WD[weapon_id].kind
	if slot == "optic" and kind == "pistol":
		return false
	if slot in ["muzzle", "optic"] and kind == "shotgun":
		return false
	return true


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
