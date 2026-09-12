extends SceneTree
## ADS 第一人称截图:真实渲染器跑起来,相机摆在 ADS 眼位,逐枪出图。
##
## 相机几何:武器本地的瞄准线是 (0, sight_y, z),z 从眼位 0.22 到枪口。
## 要让瞄准线正对屏幕中心,把武器放在 相机原点 - (0, sight_y, 0.22),
## 即 weapon.position = (0, -sight_y, -0.22) —— 和游戏里 ADS 挂载的几何一致。
##
## 用法:
##   godot --path . --script res://tools/ads_shot.gd -- m4 ak scar aug g36c ak74 famas g3
## 输出:models_probe/ads_<id>.png


const WM = preload("res://src/models/weapon_models.gd")
const WD = preload("res://src/data/weapons_data.gd")

const OUT_DIR := "E:/工作目录2/models_probe"
const EYE_Z := 0.22

var ids: Array = ["m4"]
var idx := 0
var frames := 0
var weapon: Node3D = null
var shots := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		ids = args
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.20, 0.26)   # 冷灰蓝靶场背景,枪的轮廓清楚
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.02
	root.add_child(cam)
	cam.make_current()
	print("ADS 截图: %s" % ", ".join(PackedStringArray(ids)))
	_next()


func _next() -> void:
	if weapon != null:
		root.remove_child(weapon)
		weapon.free()
		weapon = null
	if idx >= ids.size():
		print("ALL_DONE %d 张" % shots)
		quit()
		return
	var id := String(ids[idx])
	var defs: Dictionary = WD.build_weapons()
	var def = defs.get(id)
	var sy: float = 0.108
	if def != null:
		sy = def.sight_y
	weapon = WM.build(id, true, {})
	root.add_child(weapon)
	weapon.position = Vector3(0, -sy, -EYE_Z)
	frames = 0


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		_snap(String(ids[idx]))
		idx += 1
		_next()
	return false


func _snap(id: String) -> void:
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("SHOT_FAIL ", id)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := OUT_DIR + "/ads_%s.png" % id
	img.save_png(path)
	shots += 1
	print("SHOT %-6s -> %s" % [id, path])
