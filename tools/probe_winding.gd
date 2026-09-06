extends SceneTree
## 一次性探针:确认 Godot 内置 BoxMesh 的正面绕序,供自定义 SurfaceTool 几何参照。


func _init() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 2.0, 2.0)
	var arr := bm.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	print("verts=", v.size(), " index=", idx.size())
	for t in 2:
		var a := v[idx[t * 3 + 0]]
		var b := v[idx[t * 3 + 1]]
		var c := v[idx[t * 3 + 2]]
		var na := n[idx[t * 3 + 0]]
		var geo := (b - a).cross(c - a).normalized()
		var dot := geo.dot(na)
		print("tri", t, " pos=", [a, b, c])
		print("     stored_normal=", na, " geometric=", geo, " dot=", dot)
		print("     => ", "CCW(逆时针)为正面" if dot > 0.0 else "CW(顺时针)为正面")
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 2.0
	cm.radial_segments = 8
	var carr := cm.surface_get_arrays(0)
	var cv: PackedVector3Array = carr[Mesh.ARRAY_VERTEX]
	var cn: PackedVector3Array = carr[Mesh.ARRAY_NORMAL]
	var cidx: PackedInt32Array = carr[Mesh.ARRAY_INDEX]
	print("--- cylinder ---")
	for t in 2:
		var a := cv[cidx[t * 3 + 0]]
		var b := cv[cidx[t * 3 + 1]]
		var c := cv[cidx[t * 3 + 2]]
		var na := cn[cidx[t * 3 + 0]]
		var geo := (b - a).cross(c - a).normalized()
		print("tri", t, " dot=", geo.dot(na), " n=", na)
	quit()
