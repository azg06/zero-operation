extends SceneTree
## 换弹动画仿真:真实实例化 Gun + WeaponReloadController,按 60fps 步进完整换弹,
## 采样 mag/bolt 轨迹,验证 COD 式空仓/战术换弹的关键特征。
##
## 判定标准(COD 手感的几何底线):
##   空仓换弹:弹匣必须明显离开枪身(拔出),最终必须插回原位;
##             拉机柄必须有独立后拉动作(上膛)。
##   战术换弹:弹匣拔插同上,但拉机柄全程不得动(膛内有弹,不需要上膛)。
##   全程:任何轴不得出现 NaN;控制器必须自行结束(active 变 false)。

const GD = preload("res://src/data/weapons_data.gd")
const GunC = preload("res://src/player/gun.gd")

const IDS := ["m4", "ak", "scar", "aug", "g36c", "ak74", "famas", "g3"]
const DT := 1.0 / 60.0


func _initialize() -> void:
	GD.W()
	var fails := 0
	for id in IDS:
		fails += _run_one(id, true)    # 空仓
		fails += _run_one(id, false)   # 战术
	print("=== 换弹仿真全部通过 ===" if fails == 0 else "=== 失败 %d 项 ===" % fails)
	quit(1 if fails > 0 else 0)


func _run_one(id: String, empty: bool) -> int:
	var tag := "%s(%s)" % [id, "空仓" if empty else "战术"]
	var gun = GunC.new(id, null)
	gun.ammo = 0 if empty else maxi(1, int(gun.def.mag) / 2)
	gun.reserve = 120
	var ctl = gun.reload_ctl
	if ctl == null:
		print("[FAIL] %s 无 reload_ctl" % tag)
		return 1
	if not ctl.start():
		print("[FAIL] %s start() 被拒" % tag)
		return 1
	var mag_base: Vector3 = ctl.mag_base
	var bolt_base: Vector3 = ctl.bolt_base
	var max_mag_travel := 0.0
	var max_bolt_travel := 0.0
	var nan_hit := false
	var stages := {}
	var guard := 0
	while ctl.active and guard < 3000:
		ctl.update(DT)
		guard += 1
		stages[String(ctl.phase_name())] = true
		if ctl.mag != null:
			var d: Vector3 = ctl.mag.position - mag_base
			if not (is_finite(d.x) and is_finite(d.y) and is_finite(d.z)):
				nan_hit = true
				break
			max_mag_travel = maxf(max_mag_travel, d.length())
		if ctl.bolt != null:
			var bd: Vector3 = ctl.bolt.position - bolt_base
			if not (is_finite(bd.x) and is_finite(bd.y) and is_finite(bd.z)):
				nan_hit = true
				break
			max_bolt_travel = maxf(max_bolt_travel, bd.length())
	var errs := ""
	if nan_hit:
		errs += " NaN"
	if guard >= 3000:
		errs += " 未结束"
	if ctl.mag != null:
		var back: Vector3 = ctl.mag.position - mag_base
		if back.length() > 0.012:
			errs += " 弹匣未归位(偏差%.3f)" % back.length()
	if max_mag_travel < 0.05:
		errs += " 弹匣没拔出来(位移%.3f)" % max_mag_travel
	if empty:
		if ctl.bolt != null and max_bolt_travel < 0.02:
			errs += " 空仓但拉机柄没动(%.3f)" % max_bolt_travel
	else:
		if ctl.bolt != null and max_bolt_travel > 0.008:
			errs += " 战术换弹却动了拉机柄(%.3f)" % max_bolt_travel
	var stage_keys := stages.keys()
	stage_keys.sort()
	if errs == "":
		print("[OK]   %-14s %.2fs  mag位移%.3f  bolt位移%.3f  阶段:%s" % [
			tag, float(guard) * DT, max_mag_travel, max_bolt_travel,
			",".join(PackedStringArray(stage_keys))])
	else:
		print("[FAIL] %-14s %s" % [tag, errs])
	gun.group.free()
	return 0 if errs == "" else 1
