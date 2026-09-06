extends Node
## 载具第一人称视角实拍:驾驶员 / 炮手 / 观瞄目镜
##   godot --path . res://tools/vehicle_fp_shot.tscn -- tank apc aa jeep
## 用真实 FirstPersonVehicleController 驱动 G.camera(与游戏同一代码路径),
## 靶标摆在主炮轴线上验证观瞄视线对齐。输出 models_probe/fp_<veh>_<view>.png

const OUT_DIR := "E:/工作目录2/models_probe"
const FPScript = preload("res://src/vehicles/first_person_vehicle_controller.gd")

var jobs: Array = []      # [vid, view_key]
var cur := -1
var veh = null
var cam: Camera3D = null
var frames := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var ids: Array = args if args.size() > 0 else ["tank", "apc", "aa", "jeep"]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.44, 0.52, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.3
	add_child(sun)
	# 地面
	var fl := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(160, 160)
	fl.mesh = pl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.40, 0.32)
	fm.roughness = 0.95
	fl.material_override = fm
	add_child(fl)
	# 主炮轴线上的靶标(炮口正前方 35m,不同距离三块)
	var gun_y := {"tank": 1.72, "apc": 2.22, "aa": 2.02, "jeep": 1.5}
	for d in [18.0, 35.0, 60.0]:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4, 3.0, 0.4)
		t.mesh = bm
		t.position = Vector3(0, 1.5, -d)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.85, 0.35, 0.2)
		t.material_override = tm
		add_child(t)
	cam = Camera3D.new()
	cam.fov = 86.0
	add_child(cam)
	cam.make_current()
	G.camera = cam
	for vid in ids:
		jobs.append([vid, "driver"])
		jobs.append([vid, "gunner"])
		if vid != "jeep":
			jobs.append([vid, "optic"])
	cur = 0
	_next_job()


func _next_job() -> void:
	if cur >= jobs.size():
		print("ALL_DONE")
		get_tree().quit()
		return
	var job: Array = jobs[cur]
	if veh != null:
		remove_child(veh)
		veh.free()
		veh = null
	veh = Vehicle.new(0, 0, 0, job[0])
	add_child(veh)
	var ctl = veh.camera_ctl
	match job[1]:
		"driver":
			ctl.view = FPScript.VehView.FP_DRIVER
			cam.fov = 86.0
		"gunner":
			ctl.view = FPScript.VehView.FP_GUNNER
			ctl.station = FPScript.Station.GUNNER
			cam.fov = 86.0
		"optic":
			ctl.view = FPScript.VehView.FP_OPTIC
			ctl.station = FPScript.Station.GUNNER
			cam.fov = 40.0
	frames = 0


func _process(delta: float) -> void:
	if cur < 0 or cur >= jobs.size() or veh == null:
		return
	veh.camera_ctl.update(delta)
	frames += 1
	if frames == 12:
		var job: Array = jobs[cur]
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("%s/fp_%s_%s.png" % [OUT_DIR, job[0], job[1]])
		print("SHOT %s %s%s" % [job[0], job[1], "" if img != null else " (headless, 跳过存图)"])
		cur += 1
		_next_job()
