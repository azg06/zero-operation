extends Node
## 玩家桩:Gun.update 需要的 player 属性(鸭子类型,字段与 Player 对齐)
class PlayerStub:
	var vel := Vector3.ZERO
	var pos := Vector3.ZERO
	var on_ground := true
	var crouched := false
	var prone := false
	var slide_t := 0.0
	var sprint_amount := 0.0
	var suppression := 0.0
	var look_vel_x := 0.0
	var look_vel_y := 0.0
	var cam_kick_pitch := 0.0
	var cam_kick_yaw := 0.0
	var recoil_pitch := 0.0
	var recoil_yaw := 0.0

## 换弹动画仿真(场景模式:autoload/音效系统完整可用)
## 用法: godot --headless --path . res://tools/reload_sim.tscn
## 逻辑与判定详见本文件;通过后自动退出,失败码非 0。

const IDS := ["m4", "ak", "scar", "aug", "g36c", "ak74", "famas", "g3"]
const DT := 1.0 / 60.0


func _ready() -> void:
	var t := Timer.new()
	add_child(t)
	# 等 2 帧让 autoload 全部就绪
	await get_tree().process_frame
	await get_tree().process_frame
	# 支持命令行指定枪型: godot --headless --path . res://tools/reload_sim.tscn -- mp5 p90
	var ids: Array = IDS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		ids = args
	var fails := 0
	# 仿真环境补桩:_drop_mag 掉落弹匣要走 G.camera / G.effects(游戏内由主场景赋值),
	# 不塞桩会在换弹中途报 Nil 错误并中断该帧逻辑,让动画状态机失真。
	var stub_cam := Camera3D.new()
	get_tree().root.add_child(stub_cam)
	G.camera = stub_cam
	if G.effects == null:
		# Effects 依赖 _ready() 里的池子初始化,必须挂树,不能只 new
		var fx: Node3D = load("res://src/fx/effects.gd").new()
		get_tree().root.add_child(fx)
		G.effects = fx
	for id in ids:
		fails += await _run_one(id, true)
		# rocket 类(rpg/gl)膛内有弹时拒绝换弹是正确的游戏语义(单发武器打完才能装填),
		# 战术换弹路径不存在,仿真跳过而不是记失败
		var wdef = load("res://src/data/weapons_data.gd").build_weapons().get(id)
		if wdef != null and not wdef.projectile:
			fails += await _run_one(id, false)
	print("=== 换弹仿真全部通过 ===" if fails == 0 else "=== 失败 %d 项 ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _run_one(id: String, empty: bool) -> int:
	var tag := "%s(%s)" % [id, "空仓" if empty else "战术"]
	var gun = Gun.new(id, null)
	gun.equipped = true   # Gun.update 的入口条件;不置位则枪机动画/换弹推进全被跳过
	gun.player = PlayerStub.new()   # player 属性鸭子类型桩(内部类,免资源加载)
	# 必须挂进场景树:控制器与 gun.gd 多处读 global_transform / 相机,
	# 不挂树的节点访问会报错并中断该帧逻辑,让仿真结果失真(已踩)。
	get_tree().root.add_child(gun.group)
	gun.ammo = 0 if empty else maxi(1, int(gun.def.mag) / 2)
	gun.reserve = 120
	var ctl = gun.reload_ctl
	if ctl == null:
		print("[FAIL] %s 无 reload_ctl" % tag)
		gun.group.free()
		return 1
	if not ctl.start():
		print("[FAIL] %s start() 被拒" % tag)
		gun.group.free()
		return 1
	var mag_base: Vector3 = ctl.mag_base
	var bolt_base: Vector3 = ctl.bolt_base
	var max_mag_travel := 0.0
	var max_bolt_travel := 0.0
	var max_cover_angle := 0.0
	var nan_hit := false
	var stages := {}
	var guard := 0
	# 与游戏同链路驱动:Gun.update 内部会调 reload_ctl.update 并推进 bolt_t
	# 枪机动画(bolt_cycle 的枪机由 Gun 驱动,旧版仿真只调 ctl.update 属于漏驱动,
	# 会把栓动狙的枪机误判成"没动")
	while ctl.active and guard < 3000:
		gun.update(DT)
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
		# [盲区修补] 机枪供弹盖:控制器对 null cover 静默跳过,旧版仿真没断言盖子
		# 必须掀开 —— GLB 节点名没对齐时 meta 落空,开盖动画整个消失,仿真照样全绿。
		# 凡是带 cover meta 的枪,全程必须有 >30° 的开盖角。
		if ctl.cover != null:
			var ca: float = absf(ctl.cover.rotation.x - ctl.cover_base.x)
			max_cover_angle = maxf(max_cover_angle, ca)
	var errs := ""
	if nan_hit:
		errs += " NaN"
	if guard >= 3000:
		errs += " 未结束(%.1fs)" % (float(guard) * DT)
	if ctl.mag != null:
		var back: Vector3 = ctl.mag.position - mag_base
		if back.length() > 0.012:
			errs += " 弹匣未归位(偏差%.3f)" % back.length()
	# mag_style "none" 的枪(内仓霰弹/内置弹仓狙击)没有 mag 节点,不该断言拔匣
	if ctl.mag != null and max_mag_travel < 0.05:
		errs += " 弹匣没拔出来(位移%.3f)" % max_mag_travel
	if empty:
		# 按标志性枪机动作区分期望:AR 系拍空挂释放/无托拍击不拉拉机柄,
		# 这是 COD 的正确动作;拉柄系(pull*/g3_pull/hk_slap/p90_charge)必须动 bolt。
		var cs := String(ctl.cfg.get("chamber_style", "pull"))
		var no_pull := cs in ["ar_release", "bullpup_tap", "right_tap"]
		if ctl.bolt != null:
			if no_pull and max_bolt_travel > 0.008:
				errs += " %s 不该动拉机柄却动了(%.3f)" % [cs, max_bolt_travel]
			if not no_pull and max_bolt_travel < 0.02:
				errs += " %s 该动拉机柄却没动(%.3f)" % [cs, max_bolt_travel]
	else:
		if ctl.bolt != null and max_bolt_travel > 0.008:
			errs += " 战术换弹却动了拉机柄(%.3f)" % max_bolt_travel
	if ctl.cover != null and max_cover_angle < 0.5:
		errs += " 有受弹机盖却没掀开(峰值%.2frad)" % max_cover_angle
	var keys := stages.keys()
	keys.sort()
	if errs == "":
		print("[OK]   %-14s %.2fs  mag位移%.3f  bolt位移%.3f  盖%.2frad  阶段:%s" % [
			tag, float(guard) * DT, max_mag_travel, max_bolt_travel,
			max_cover_angle, ",".join(PackedStringArray(keys))])
	else:
		print("[FAIL] %-14s %s  阶段:%s" % [tag, errs, ",".join(PackedStringArray(keys))])
		# 失败时 dump 阶段时长配置 —— 阶段被异常压缩是弹匣不归位的常见根因
		var durs: Array = []
		for d in ctl.phase_durs:
			durs.append("%.2f" % (float(d) * 1000.0))
		print("    phase_durs(ms)=%s  tac_weights=%s" % [
			",".join(PackedStringArray(durs)), str(ctl.cfg.get("tac_weights", []))])
		# 失败时输出关键轨迹:每 10 帧采样 stage / mag / bolt 相对位移
		var gun2 = Gun.new(id, null)
		get_tree().root.add_child(gun2.group)
		gun2.ammo = 0 if empty else maxi(1, int(gun2.def.mag) / 2)
		gun2.reserve = 120
		var c2 = gun2.reload_ctl
		if c2.start():
			var mb: Vector3 = c2.mag_base
			var bb: Vector3 = c2.bolt_base
			var g2 := 0
			var last_stage := ""
			while c2.active and g2 < 3000:
				c2.update(DT)
				g2 += 1
				var st := String(c2.phase_name())
				if st != last_stage or g2 % 20 == 0:
					var mo: Vector3 = (c2.mag.position - mb) if c2.mag != null else Vector3.ZERO
					var bo: Vector3 = (c2.bolt.position - bb) if c2.bolt != null else Vector3.ZERO
					print("    f%-4d %-9s mag(%.3f,%.3f,%.3f) bolt(%.3f,%.3f,%.3f)" % [
						g2, st, mo.x, mo.y, mo.z, bo.x, bo.y, bo.z])
					last_stage = st
		get_tree().root.remove_child(gun2.group)
		gun2.group.free()
	get_tree().root.remove_child(gun.group)
	gun.group.free()
	return 0 if errs == "" else 1
