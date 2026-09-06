extends SceneTree
## dump vehicle GLB node tree + materials

func _initialize() -> void:
	for vid in ["tank", "jeep", "apc", "aa"]:
		var ps: PackedScene = load("res://models/vehicles/%s.glb" % vid)
		var g: Node3D = ps.instantiate()
		root.add_child(g)
		print("==== ", vid)
		var meshes := g.find_children("*", "MeshInstance3D", true, false)
		print("MESHES=", meshes.size())
		for m in meshes:
			var mi := m as MeshInstance3D
			var mat := mi.material_override
			var own := ""
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var sm = mi.mesh.surface_get_material(0)
				if sm != null:
					own = sm.resource_name
			print("  %-28s own_mat='%s'" % [mi.name, own])
	quit()
