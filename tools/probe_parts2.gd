extends SceneTree


const WP = preload("res://src/models/weapon_parts.gd")


func _init() -> void:
	print("step1 begin")
	var m1 := WP.bevel_box_mesh(0.05, 0.03, 0.2, 0.0015, 9.0)
	print("step1 bevel_box tris=", m1.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m2 := WP.chamfer_cyl_mesh(0.012, 0.4, 0.0015, 24, 9.0)
	print("step2 chamfer_cyl tris=", m2.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m3 := WP.picatinny_mesh(0.2, 9.0)
	print("step3 picatinny tris=", m3.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m4 := WP.knurl_mesh(0.012, 0.03, 24, 0.0008, 9.0)
	print("step4 knurl tris=", m4.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m5 := WP.fluted_mesh(0.02, 0.06, 6, 0.0015, 9.0)
	print("step5 fluted tris=", m5.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m6 := WP.birdcage_mesh(0.014, 0.05, 9.0)
	print("step6 birdcage tris=", m6.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m7 := WP.screw_mesh(0.004, 0.002, 9.0)
	print("step7 screw tris=", m7.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	var m8 := WP.ribbed_plate_mesh(0.05, 0.02, 0.15, 7, 0.002, 9.0)
	print("step8 ribbed_plate tris=", m8.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	print("ALL_OK")
	quit()
