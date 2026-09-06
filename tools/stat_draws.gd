extends Node
## 统计 world_root 的 draw call 构成:独立 MeshInstance vs MultiMesh,按材质 TopN

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var holder := Node3D.new()
	add_child(holder)
	WorldBuilder.build_world(holder, "snow")
	var mi_count := 0
	var mm_count := 0
	var other := 0
	var by_mat := {}
	for c in holder.get_children():
		if c is MultiMeshInstance3D:
			mm_count += 1
		elif c is MeshInstance3D:
			mi_count += 1
			var mat: Material = c.material_override
			var key := str(mat.resource_name) if mat != null and mat.resource_name != "" else (str(mat.get_instance_id()) if mat != null else "embedded")
			by_mat[key] = int(by_mat.get(key, 0)) + 1
		else:
			other += 1
	# Node3D 组(灯光/装饰组)里的散件也统计
	var deep_mi := 0
	var deep_mm := 0
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		deep_mi += 1
	for c in holder.find_children("*", "MultiMeshInstance3D", true, false):
		deep_mm += 1
	print("[STAT] top: MeshInstance=%d MultiMesh=%d other=%d" % [mi_count, mm_count, other])
	print("[STAT] deep: MeshInstance=%d MultiMesh=%d" % [deep_mi, deep_mm])
	var pairs := []
	for k in by_mat:
		pairs.append([by_mat[k], k])
	pairs.sort()
	pairs.reverse()
	for i in mini(15, pairs.size()):
		print("[STAT] mat %-30s x%d" % [pairs[i][1], pairs[i][0]])
	print("[STAT] distinct materials=", pairs.size())
	get_tree().quit()
