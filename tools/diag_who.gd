extends Node
## 逐顶层子节点隐藏渲染,与全显图做像素差异,自动锁定白圆柱所属子树。
var base_img: Image = null
var g: Node3D = null
var gun = null
var tops: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	gun = load("res://src/player/gun.gd").new("m1911", null)
	gun.equipped = true
	var s := RefCounted.new()
	for prop in ["vel", "pos", "cam_kick_pitch", "cam_kick_yaw", "look_vel_x", "look_vel_y", "recoil_pitch", "recoil_yaw"]:
		s.set(prop, Vector3.ZERO if prop in ["vel", "pos"] else 0.0)
	s.set("on_ground", true)
	s.set("crouched", false)
	s.set("prone", false)
	for prop in ["slide_t", "sprint_amount", "suppression"]:
		s.set(prop, 0.0)
	gun.player = s
	g = gun.group
	get_tree().root.add_child(g)
	await get_tree().process_frame
	var cam := Camera3D.new()
	cam.position = Vector3(-0.248, 0.12, 0.264)
	cam.look_at(Vector3(0, 0, -0.02), Vector3.UP)
	cam.fov = 55.0
	get_tree().root.add_child(cam)
	cam.make_current()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.20, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	get_tree().root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.2
	get_tree().root.add_child(sun)
	await get_tree().process_frame
	await get_tree().process_frame
	base_img = get_tree().root.get_texture().get_image()
	base_img.save_png("E:/工作目录2/models_probe/who_base.png")
	# 逐顶层子节点隐藏
	for c in g.get_children():
		tops.append(c)
	for c in tops:
		var vis: bool = c.visible
		c.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_tree().root.get_texture().get_image()
		var diff := 0
		if img != null and not img.is_empty():
			for yy in range(0, img.get_height(), 6):
				for xx in range(0, img.get_width(), 6):
					if img.get_pixel(xx, yy).hex() != base_img.get_pixel(xx, yy).hex():
						diff += 1
		print("HIDE %-24s pixdiff=%d" % [c.name, diff])
		c.visible = vis
	get_tree().quit(0)
