extends Node
## 地图物件审计:逐张构建 6 张地图,俯瞰 + 街面双机位截图
##   godot --path . res://tools/map_audit.tscn
## 输出 models_probe/audit_<map>_<ov|gd>.png

const MAPS := ["city", "desert", "snow", "bt_jungle", "bt_harbor", "bt_peak", "br_valley"]
const OUT := "E:/工作目录2/models_probe"

var idx := 0
var cam: Camera3D = null
var root_holder: Node3D = null
var frames := 0
var stage := 0          # 0=俯瞰机位 1=街面机位 2=收尾换图


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.38, 0.55, 0.78)
	mat.sky_horizon_color = Color(0.66, 0.72, 0.80)
	mat.ground_bottom_color = Color(0.25, 0.27, 0.30)
	mat.ground_horizon_color = Color(0.60, 0.65, 0.72)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-25, 145, 0)
	sun2.light_energy = 0.4
	add_child(sun2)
	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.make_current()
	G.camera = cam
	root_holder = Node3D.new()
	root_holder.name = "AuditWorld"
	add_child(root_holder)
	G.world_root = root_holder
	print("[AUDIT] begin")
	_build_next()


func _build_next() -> void:
	if idx >= MAPS.size():
		print("[AUDIT] all_done")
		get_tree().quit()
		return
	for c in root_holder.get_children():
		root_holder.remove_child(c)
		c.free()
	frames = 0
	stage = 0
	WorldBuilder.build_world(root_holder, MAPS[idx])
	print("[AUDIT] built ", MAPS[idx], " size=", G.world_size)


func _shoot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/audit_%s_%s.png" % [OUT, MAPS[idx], tag])
		print("[AUDIT-SHOT] ", MAPS[idx], " ", tag)


func _process(_dt: float) -> void:
	if idx >= MAPS.size():
		return
	frames += 1
	var half: float = maxf(G.world_size, 200.0) * 0.5
	match stage:
		0:
			if frames == 2:
				cam.look_at_from_position(Vector3(-half * 0.85, half * 0.7, -half * 0.85),
					Vector3(0, 0, 0), Vector3.UP)
			if frames >= 30:
				_shoot("ov")
				stage = 1
				frames = 0
		1:
			if frames == 2:
				cam.look_at_from_position(Vector3(-half * 0.4, 2.4, -half * 0.4),
					Vector3(half * 0.25, 2.5, half * 0.1), Vector3.UP)
			if frames >= 30:
				_shoot("gd")
				stage = 2
				frames = 0
		2:
			idx += 1
			_build_next()
