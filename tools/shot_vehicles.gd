extends SceneTree
## 渲染 4 种载具:全景 + 近景 3/4(排查悬空零件与材质)

func _initialize() -> void:
	var vm = load("res://src/models/vehicle_models.gd")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.20, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-30, 140, 0)
	sun2.light_energy = 0.5
	root.add_child(sun2)
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	cam.make_current()
	var g_node := root.get_node_or_null("/root/G")
	if g_node != null:
		g_node.camera = cam
	var shots := {"jeep": 7.5, "apc": 11.0, "aa": 11.0, "tank": 12.5}
	for id in shots:
		var v: Node3D = vm.call("build_" + id)
		root.add_child(v)
		var d: float = shots[id]
		cam.look_at_from_position(Vector3(-d * 0.62, d * 0.34, d * 0.62), Vector3(0, 0.8, 0), Vector3.UP)
		await process_frame
		for i in 6:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("E:/工作目录2/models_probe/vehicle_%s.png" % id)
		print("SHOT ", id)
		# 近景:炮塔/车尾 3/4
		var d2: float = d * 0.42
		cam.look_at_from_position(Vector3(-d2 * 0.75, d2 * 0.55, d2 * 0.55), Vector3(0, d * 0.11, d * 0.08), Vector3.UP)
		await process_frame
		for i in 6:
			await process_frame
		img = root.get_viewport().get_texture().get_image()
		img.save_png("E:/工作目录2/models_probe/vehicle_%s_close.png" % id)
		print("SHOTS ", id)
		root.remove_child(v)
		v.free()
	print("ALL_DONE")
