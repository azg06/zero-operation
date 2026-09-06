extends SceneTree
## 接入验证:GLB 路径能否正常工作 + draw call 预算 + 可动件绑定 + 非 GLB 枪的回退。


func _init() -> void:
	var fail := 0

	# ---------- 1. GLB 路径:M4 ----------
	print("=== M4 (GLB 高精度路径) ===")
	var g := WeaponModels.build("m4", true, {})
	# 挂进场景树,否则 is_inside_tree() 恒为 false(不是模型的问题)
	get_root().add_child(g)
	if g == null:
		print("FAIL build 返回 null")
		quit(1)
		var _unused := 0
	var mi_before := _count_mi(g)
	print("  构建后 MeshInstance 总数: ", mi_before)

	# draw call = 合并后所有 mesh 的 surface 数
	var dc := _draw_calls(g)
	print("  合并后 draw call(surface 总数): ", dc)

	for k in ["mag", "bolt", "muzzle", "right_hand", "left_hand"]:
		var has := g.has_meta(k)
		print("  meta %-11s %s" % [k, "OK" if has else "*** MISSING ***"])
		if not has:
			fail += 1

	var muzzle: Node3D = g.get_meta("muzzle", null)
	if muzzle != null:
		print("  枪口点位置: (%.3f, %.3f, %.3f)" % [muzzle.position.x, muzzle.position.y, muzzle.position.z])

	# 可动件必须没被合并掉
	var mag_node: Node = g.get_meta("mag", null)
	if mag_node != null:
		print("  mag 节点仍在树中: ", mag_node.is_inside_tree(), " 名称=", mag_node.name)
		if not mag_node.is_inside_tree():
			fail += 1

	# ---------- 2. 回退路径:没有 GLB 的枪 ----------
	print("")
	print("=== AK (GDScript 程序化回退路径) ===")
	var ak := WeaponModels.build("ak", true, {})
	get_root().add_child(ak)
	if ak == null:
		print("FAIL ak build null")
		fail += 1
	else:
		print("  MeshInstance 总数: ", _count_mi(ak))
		print("  draw call: ", _draw_calls(ak))
		for k in ["mag", "bolt", "muzzle"]:
			var has := ak.has_meta(k)
			print("  meta %-11s %s" % [k, "OK" if has else "*** MISSING ***"])
			if not has:
				fail += 1

	# ---------- 3. 全部武器冒烟:确保回退路径没被改坏 ----------
	# 全量构建较慢(50+ 把枪),仅在传入 --all 时执行。
	var full := OS.get_cmdline_user_args().has("--all")
	if not full:
		print("")
		print("(跳过全量冒烟,加 --all 执行)")
		print("")
		print("=== 全部通过 ===" if fail == 0 else "=== 失败 %d 项 ===" % fail)
		quit(fail)
		return
	print("")
	print("=== 全部武器冒烟测试 ===")
	var ids: Array = WeaponModels.MUZZLE_Z.keys()
	var bad: Array[String] = []
	var total_dc := 0
	var max_dc := 0
	var max_id := ""
	for id in ids:
		var w := WeaponModels.build(String(id), false, {})
		if w == null:
			bad.append("%s:null" % id)
			continue
		var d := _draw_calls(w)
		total_dc += d
		if d > max_dc:
			max_dc = d
			max_id = String(id)
		w.free()
	print("  武器数: ", ids.size())
	print("  平均 draw call: %.1f" % (float(total_dc) / maxf(1.0, float(ids.size()))))
	print("  最大 draw call: %d (%s)" % [max_dc, max_id])
	if bad.is_empty():
		print("  无构建失败")
	else:
		print("  构建失败: ", bad)
		fail += bad.size()

	print("")
	print("=== 全部通过 ===" if fail == 0 else "=== 失败 %d 项 ===" % fail)
	quit(fail)


func _count_mi(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _count_mi(ch)
	return c


## draw call 估算:每个 mesh 的每个 surface 一次绘制调用
func _draw_calls(n: Node) -> int:
	var dc := 0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			dc += mi.mesh.get_surface_count()
	for ch in n.get_children():
		dc += _draw_calls(ch)
	return dc
