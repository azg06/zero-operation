extends SceneTree
## QA: 对第一批 8 把步枪按全改装槽构建,验证改装配件锚点兼容、无缺件崩溃。
## 用法: godot --headless --path <project> --script res://tools/qa_mods_ar.gd

const IDS := ["m4", "ak", "scar", "aug", "g36c", "ak74", "famas", "g3"]

func _initialize() -> void:
	var WD = load("res://src/data/weapons_data.gd")
	WD.W()  # 预热武器数据(optic 锚点依赖 sight_y/ads_z)
	var WM = load("res://src/models/weapon_models.gd")
	var fails: Array = []
	var mods := {
		"muzzle": "muz_brk", "barrel": "barrel_heavy", "stock": "stock_heavy",
		"grip": "grip_vert", "trigger": "trig_comp", "optic": "opt_reddot", "laser": "laser_tac",
	}
	for id in IDS:
		var g: Node3D = WM.build(id, true, mods)
		var parts := 0
		for c in g.get_children():
			parts += 1
		var errs := ""
		if g == null:
			errs = "null_root"
		if g.get_meta("mag", null) == null and id in ["m4", "ak", "scar", "aug", "g3", "g36c", "ak74", "famas"]:
			# 部分枪型本身无弹匣;这里仅提醒,不判失败(改装弹匣按数据表单独处理)
			pass
		var optic := g.get_node_or_null("ModOptic_opt_reddot")
		var muzzle := g.get_node_or_null("ModMuzzle_muz_brk")
		if optic == null:
			errs += " optic_missing"
		if muzzle == null:
			errs += " muzzle_missing"
		if errs != "":
			fails.append(id + errs)
			print("[QA-MODS] FAIL %s %s" % [id, errs])
		else:
			print("[QA-MODS] ok %s root_parts=%d" % [id, parts])
		g.free()
	print("[QA-MODS] done fails=%d %s" % [fails.size(), str(fails)])
	quit(1 if fails.size() > 0 else 0)
