extends SceneTree
## draw call 构成诊断:区分"静态件合并后的 surface""可动件""手部/手臂",
## 用来确认材质变体池(_VARIANT_POOL)是否真的把 draw call 压住了。


func _init() -> void:
	for id in ["m4", "ak"]:
		var g := WeaponModels.build(id, true, {})
		print("=== %s ===" % id)
		var total := 0
		var by_group := {}
		for mi in _list(g):
			var s := mi.mesh.get_surface_count() if mi.mesh != null else 0
			total += s
			var key := _group_of(mi, g)
			by_group[key] = int(by_group.get(key, 0)) + s
		print("  MeshInstance 数: ", _list(g).size())
		print("  总 draw call  : ", total)
		for k in by_group.keys():
			print("    %-16s %d" % [k, by_group[k]])
		var merged: MeshInstance3D = _find(g, "MergedStatic")
		if merged != null and merged.mesh != null:
			print("  MergedStatic surface 数: ", merged.mesh.get_surface_count(),
				"  (变体池生效时应远小于静态零件数)")
		# 可动件是否存活(不依赖场景树,直接查父链)
		for k in ["mag", "bolt"]:
			if g.has_meta(k):
				var n := g.get_meta(k) as Node
				print("  %-5s 父链可达根节点: %s" % [k, _reachable(n, g)])
		print("")
	quit(0)


func _list(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(n, out)
	return out


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect(c, out)


## 按归属分类:静态合并件 / 可动件 / 手部 / 其他
func _group_of(mi: MeshInstance3D, g: Node3D) -> String:
	if mi.name == "MergedStatic":
		return "静态件(合并)"
	var n: Node = mi
	while n != null and n != g:
		if n.name == "mag" or n.name == "bolt":
			return "可动件:" + n.name
		if n.name.begins_with("Hand") or n.name.begins_with("Arm"):
			return "手部/手臂"
		n = n.get_parent()
	# 手部模型的根节点名由 build_hand 决定,退化为按材质名判断
	var mn := _mat_name(mi)
	if mn in ["glove", "sleeve", "glove_knuckle"]:
		return "手部/手臂"
	return "其他:" + mi.name


func _mat_name(mi: MeshInstance3D) -> String:
	if mi.material_override != null:
		return mi.material_override.resource_name
	return ""


func _reachable(n: Node, root: Node) -> bool:
	var w := n
	while w != null:
		if w == root:
			return true
		w = w.get_parent()
	return false


func _find(n: Node, name: String) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == name:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find(c, name)
		if r != null:
			return r
	return null
