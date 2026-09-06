extends Node
## 通用点位截图:-- <map> <x> <z> [yaw_deg] [dist] [height]
## 相机放在 (x,z) 后方 dist 距离、height 高度,朝 (x,z) 看。

const OUT := "E:/工作目录2/models_probe"

var frames := 0
var _shot_done := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ua := OS.get_cmdline_user_args()
	var map := ua[0] if ua.size() > 0 else "br_valley"
	var x := float(ua[1]) if ua.size() > 1 else 0.0
	var z := float(ua[2]) if ua.size() > 2 else 0.0
	var yaw := deg_to_rad(float(ua[3])) if ua.size() > 3 else 0.0
	var dist := float(ua[4]) if ua.size() > 4 else 40.0
	var h := float(ua[5]) if ua.size() > 5 else 12.0
	var holder := Node3D.new()
	add_child(holder)
	WorldBuilder.build_world(holder, map)
	print("[SPOT] built ", map)
	var cam := Camera3D.new()
	add_child(cam)
	cam.far = 1200.0
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.38, 0.55, 0.78)
	mat.sky_horizon_color = Color(0.66, 0.72, 0.80)
	sky.sky_material = mat
	env.sky = sky
	cam.environment = env
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	var cam_pos := Vector3(x, 0, z) - dir * dist + Vector3(0, h, 0)
	var gh: float = G.ground_h.call(cam_pos.x, cam_pos.z) if G.ground_h.is_valid() else 0.0
	cam_pos.y = maxf(cam_pos.y, gh + 2.0)
	cam.position = cam_pos
	cam.look_at(Vector3(x, h * 0.35, z), Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	add_child(sun)


func _process(_dt: float) -> void:
	# 第 10 帧截图后立即退出(配合命令行 --quit-after 双保险,杜绝窗口挂住)
	if frames >= 10 and not _shot_done:
		_shot_done = true
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var ua := OS.get_cmdline_user_args()
			var nm := "spot_%s_%s_%s" % [ua[0], ua[1], ua[2]]
			img.save_png("%s/%s.png" % [OUT, nm])
			print("[SPOT-SHOT] ", nm)
		else:
			print("[SPOT-SHOT] 无渲染目标(headless 模式跳过)")
		get_tree().quit()
		return
	frames += 1
	# 兜底:24 帧仍未完成则强制退出(防止脚本异常导致窗口残留)
	if frames > 24:
		get_tree().quit()



