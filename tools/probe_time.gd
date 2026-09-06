extends SceneTree
## 分段计时:定位 build 流程的耗时点。


func _t(label: String, t0: int) -> int:
	var now := Time.get_ticks_msec()
	print("  [%5d ms] %s" % [now - t0, label])
	return now


func _init() -> void:
	var t := Time.get_ticks_msec()
	t = _t("start", t)

	var m := WeaponModels.MAT()
	t = _t("MAT() 加载材质表 (size=%d)" % m.size(), t)

	var ps: PackedScene = load("res://models/weapons/m4.glb")
	t = _t("load m4.glb", t)
	var inst := ps.instantiate()
	t = _t("instantiate", t)

	var g := Node3D.new()
	g.add_child(inst)
	t = _t("挂载", t)

	WeaponModels._remap_glb_materials(g)
	t = _t("_remap_glb_materials", t)

	for k in ["mag", "bolt"]:
		var n := WeaponModels._find_node_named(g, k)
		if n != null:
			g.set_meta(k, n)
	t = _t("绑定可动件 meta", t)

	WeaponModels._merge_static(g)
	t = _t("_merge_static", t)

	var n := _count_mi(g)
	t = _t("统计 (MeshInstance=%d)" % n, t)

	print("  最终 MeshInstance = ", n)
	print("  mag 在树中: ", (g.get_meta("mag", null) as Node).is_inside_tree())
	quit(0)


func _count_mi(x: Node) -> int:
	var c := 0
	if x is MeshInstance3D:
		c += 1
	for ch in x.get_children():
		c += _count_mi(ch)
	return c
