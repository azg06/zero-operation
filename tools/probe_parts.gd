extends SceneTree
## 零件库自检:几何合法性(无 NaN/退化面) + 与 _merge_static 的合并兼容性。
## 这是"质量必须可验证"的底线,不能只靠肉眼。


const WP = preload("res://src/models/weapon_parts.gd")
const WM = preload("res://src/models/weapon_models.gd")


func _init() -> void:
	var mat := StandardMaterial3D.new()
	var cases := [
		["bevel_box", WP.bevel_box_mesh(0.05, 0.03, 0.2, 0.0015, 9.0)],
		["chamfer_cyl", WP.chamfer_cyl_mesh(0.012, 0.4, 0.0015, 24, 9.0)],
		["picatinny", WP.picatinny_mesh(0.2, 9.0)],
		["knurl", WP.knurl_mesh(0.012, 0.03, 24, 0.0008, 9.0)],
		["fluted", WP.fluted_mesh(0.02, 0.06, 6, 0.0015, 9.0)],
		["birdcage", WP.birdcage_mesh(0.014, 0.05, 9.0)],
		["screw", WP.screw_mesh(0.004, 0.002, 9.0)],
		["pin", WP.pin_mesh(0.003, 0.02, 9.0)],
		["ribbed_plate", WP.ribbed_plate_mesh(0.05, 0.02, 0.15, 7, 0.002, 9.0)],
	]
	var fail := 0
	for c in cases:
		var name: String = c[0]
		var m: ArrayMesh = c[1]
		var ok := _check(name, m)
		if not ok:
			fail += 1
	# --- 合并兼容性:塞进一个节点跑 WeaponModels._merge_static ---
	var g := Node3D.new()
	for c in cases:
		var mi := MeshInstance3D.new()
		mi.mesh = c[1] as ArrayMesh
		mi.material_override = mat
		g.add_child(mi)
	var before := _count_mi(g)
	WM._merge_static(g)
	var after := _count_mi(g)
	var merged: MeshInstance3D = g.get_node_or_null("MergedStatic")
	var tris := 0
	if merged != null and merged.mesh != null:
		for s in merged.mesh.get_surface_count():
			var idx: PackedInt32Array = merged.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
	print("[merge] MeshInstance %d -> %d (合并后节点数应为 1), 合并面数=%d" % [before, after, tris])
	if after != 1:
		print("  !! 合并失败:节点数不为 1")
		fail += 1
	print("=== 全部通过 ===" if fail == 0 else "=== 失败 %d 项 ===" % fail)
	quit(fail)


func _count_mi(g: Node3D) -> int:
	var n := 0
	for c in g.get_children():
		if c is MeshInstance3D:
			n += 1
	return n


func _check(name: String, m: ArrayMesh) -> bool:
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bad_n := 0
	var bad_uv := 0
	for i in nrm.size():
		var n: Vector3 = nrm[i]
		if not is_finite(n.x) or not is_finite(n.y) or not is_finite(n.z):
			bad_n += 1
		elif absf(n.length() - 1.0) > 0.02:
			bad_n += 1
	var bad_aabb := false
	var bb := m.get_aabb()
	if bb.size.x <= 0.0 or bb.size.y <= 0.0 or bb.size.z <= 0.0:
		bad_aabb = true
	if uv.size() != v.size():
		bad_uv = v.size()
	var ok := bad_n == 0 and not bad_aabb and bad_uv == 0 and idx.size() % 3 == 0
	print("%-14s verts=%-5d tris=%-5d nan/非单位法线=%-3d uv缺失=%-3d aabb=%s  %s" % [
		name, v.size(), idx.size() / 3, bad_n, bad_uv,
		"(%s)" % str(bb.size).substr(0, 24), "OK" if ok else "FAIL"])
	return ok
