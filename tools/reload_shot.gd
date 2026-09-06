extends Node
## 换弹动画关键帧截图:跑完整空仓换弹,按阶段权重在每阶段中点出图。
## 用法: godot --path . res://tools/reload_shot.tscn
## 输出: models_probe/reload_<id>_<stage>.png

const TARGETS := ["m4", "ak"]
const OUT := "E:/工作目录2/models_probe"
const DT := 1.0 / 60.0

## 空仓换弹的 6 阶段权重(prepare/remove/fetch/insert/chamber/recover)取自
## ReloadProfiles.empty_weights;取每阶段中点时刻作为拍摄点。
const STAGE_MID := {
	"prepare": 0.06, "remove": 0.20, "fetch": 0.40,
	"insert": 0.60, "chamber": 0.77, "recover": 0.93,
}
const STAGE_ORDER := ["prepare", "remove", "fetch", "insert", "chamber", "recover"]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var stub := Camera3D.new()
	get_tree().root.add_child(stub)
	G.camera = stub
	if G.effects == null:
		var fx: Node3D = load("res://src/fx/effects.gd").new()
		get_tree().root.add_child(fx)
		# 特效池(弹壳/弹匣/命中共用 mesh)全部初始化在原点 —— 相机在 (0,0,0)
		# 会被包进 mesh 内部拍出一帧纯色。整体挪到远处,不影响换弹逻辑取用。
		fx.position = Vector3(5000, 0, 0)
		G.effects = fx
	# 渲染环境
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.20, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	get_tree().root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -55, 0)
	sun.light_energy = 1.15
	get_tree().root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.02
	get_tree().root.add_child(cam)
	cam.make_current()
	for id in TARGETS:
		await _shoot_one(id)
	print("RELOAD_SHOTS_DONE")
	get_tree().quit(0)


func _shoot_one(id: String) -> void:
	var gun = Gun.new(id, null)
	get_tree().root.add_child(gun.group)
	gun.ammo = 0
	gun.reserve = 120
	# 腰际持枪位:比 ADS 稍远稍侧,能看全弹匣拔出/取匣/插匣的完整轨迹
	gun.group.position = Vector3(0, -0.115, -0.46)
	gun.group.rotation = Vector3(0.08, 0.38, 0.03)
	var ctl = gun.reload_ctl
	if not ctl.start():
		print("START_FAIL ", id)
		get_tree().root.remove_child(gun.group)
		gun.group.free()
		return
	# 第一遍:测总帧数 → 换算各阶段中点的目标帧;第二遍:按帧精确拍摄
	var f := 0
	while ctl.active and f < 3000:
		ctl.update(DT)
		f += 1
	var total := f
	print("%s 总帧数 %d (%.2fs)" % [id, total, float(total) * DT])
	var targets := {}
	for st in STAGE_ORDER:
		targets[int(round(STAGE_MID[st] * float(total)))] = st
	var keys := targets.keys()
	keys.sort()
	# 第一遍跑完控制器停在 FINISH/IDLE,且 _commit_mag 已把弹匣补满(start 会拒绝),
	# 必须清空弹药 + reset 基准姿态后再重开(两个坑都踩过)。
	gun.ammo = 0
	ctl.reset()
	if not ctl.start():
		print("RESTART_FAIL ", id)
		get_tree().root.remove_child(gun.group)
		gun.group.free()
		return
	f = 0
	var ki := 0
	var shots := 0
	while ctl.active and f < 3000 and ki < keys.size():
		ctl.update(DT)
		f += 1
		if f >= int(keys[ki]):
			var st: String = targets[keys[ki]]
			var img := get_tree().root.get_texture().get_image()
			if img != null and not img.is_empty():
				if ki == 0:
					# 诊断:确认渲染路径上的相机与世界状态
					var cc := get_viewport().get_camera_3d()
					print("  [diag] current_cam=%s gun_in_tree=%s center_px=%s" % [
						cc.name if cc != null else "null",
						gun.group.is_inside_tree(),
						str(img.get_pixel(img.get_width() / 2, img.get_height() / 2))])
				var path := "%s/reload_%s_%s.png" % [OUT, id, st]
				img.save_png(path)
				shots += 1
				print("  SHOT %-18s (帧 %d)" % [st, f])
			else:
				print("  IMG_NULL 帧 %d" % f)
			ki += 1
	print("%s 拍摄 %d 张 (跑到帧 %d)" % [id, shots, f])
	get_tree().root.remove_child(gun.group)
	gun.group.free()
