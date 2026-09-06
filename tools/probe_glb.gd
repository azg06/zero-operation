extends SceneTree
## GLB 武器模型落地检查:节点契约 + 坐标朝向 + 尺寸预算。
## 坐标对了才能复用现有 HAND_ANCHORS / MUZZLE_Z / MOD_ANCHORS。


func _init() -> void:
	var path := "res://models/weapons/m4.glb"
	if not ResourceLoader.exists(path):
		print("FAIL 资源不存在: ", path)
		quit(1)
		return
	var ps: PackedScene = load(path)
	if ps == null:
		print("FAIL 无法加载 PackedScene")
		quit(1)
		return
	var root := ps.instantiate()
	print("根节点: ", root.name, " 类型=", root.get_class())

	# --- 节点统计 ---
	var meshes: Array[String] = []
	_collect(root, meshes)
	print("MeshInstance3D 数量: ", meshes.size())

	# --- 可动件契约 ---
	for k in ["mag", "bolt"]:
		var n := _find(root, k)
		print("  可动件 %-6s %s" % [k, "FOUND" if n != null else "*** MISSING ***"])

	# --- 坐标朝向:合并全部静态件算整体 AABB ---
	var bb := AABB()
	for m in _mi_list(root):
		var global_aabb := _global_aabb(m, root)
		if bb.size == Vector3.ZERO and bb.position == Vector3.ZERO:
			bb = global_aabb
		else:
			bb = bb.merge(global_aabb)
	print("整体 AABB:")
	print("  min = ", _f(bb.position))
	print("  max = ", _f(bb.position + bb.size))
	print("  尺寸 = ", _f(bb.size))
	var ok := true
	# 枪口应朝 -Z:最小 z 明显小于 0,且 |min.z| > |max.z|
	var muzzle_minus_z: bool = absf(bb.position.z) > absf(bb.position.z + bb.size.z)
	print("  枪口朝 -Z: ", muzzle_minus_z)
	if not muzzle_minus_z:
		ok = false
	# 上方为 +Y:整体高度应在 0.1~0.2m 之间(枪械高度)
	var h := bb.size.y
	print("  高度(Y) = %.3f m" % h)
	if h < 0.05 or h > 0.35:
		ok = false
	# 长度沿 Z
	var len_z := bb.size.z
	print("  全长(Z) = %.3f m" % len_z)
	if len_z < 0.6 or len_z > 1.4:
		ok = false
	# 宽度沿 X
	print("  宽度(X) = %.3f m" % bb.size.x)
	if bb.size.x > 0.25:
		ok = false
	print("=== 坐标与尺寸通过 ===" if ok else "=== 坐标/尺寸异常 ===")
	quit(0 if ok else 1)


func _f(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _mi_list(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_mi_collect(root, out)
	return out


func _mi_collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_mi_collect(c, out)


func _collect(n: Node, out: Array[String]) -> void:
	if n is MeshInstance3D:
		out.append(n.name)
	for c in n.get_children():
		_collect(c, out)


func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find(c, name)
		if r != null:
			return r
	return null


## 计算 mesh 在世界空间(相对 root)的 AABB
func _global_aabb(mi: MeshInstance3D, root: Node3D) -> AABB:
	var am := mi.mesh
	if am == null:
		return AABB()
	var local := am.get_aabb()
	var t: Transform3D = _rel_transform(root, mi)
	return _xform_aabb(t, local)


## 变换 AABB:Transform3D 没有直接 xform(AABB) 的重载,取 8 角点重算包围盒。
func _xform_aabb(t: Transform3D, a: AABB) -> AABB:
	var out := AABB()
	for i in 8:
		var p := a.position + Vector3(
			(a.size.x if (i & 1) else 0.0),
			(a.size.y if (i & 2) else 0.0),
			(a.size.z if (i & 4) else 0.0))
		var q := t * p
		if i == 0:
			out = AABB(q, Vector3.ZERO)
		else:
			out = out.expand(q)
	return out


func _rel_transform(g: Node3D, m: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = m
	while n != null and n != g:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
