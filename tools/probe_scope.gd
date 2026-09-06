extends Node
## 狙击镜 PIP 契约验证:GLB 路径加载后 scope_eye/tube/lens/reticle meta 是否齐备、
## scope_sight() 树内检查是否通过(开镜有放大画面的前提)。
## 用法: godot --headless --path . --script res://tools/probe_scope.gd -- awm svd ...


func _ready() -> void:
	await get_tree().process_frame
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["awm", "m24", "svd", "m40", "m82a1", "l115", "sv98", "m2010"]
	print("=" .repeat(72))
	print("武器      scope_eye  radius  tube   lensB  lensC  ret    scope_sight()")
	var fail := 0
	for id in ids:
		var gun = Gun.new(id, null)
		if gun == null or gun.group == null:
			print("%-9s 构建失败" % id)
			fail += 1
			continue
		get_tree().root.add_child(gun.group)
		var g: Node3D = gun.group
		var col := func(key: String) -> String:
			return "Y" if g.has_meta(key) else "-"
		# scope_sight 需要 def.scope 且 eye 在树内可见
		var sight_ok: bool = false
		if gun.def.scope:
			sight_ok = gun.scope_sight()
		else:
			sight_ok = true   # 无原厂镜枪跳过
		var rad := "Y" if g.has_meta("scope_eye_radius") else "-"
		print("%-9s %-9s  %-6s  %-5s  %-5s  %-5s  %-5s  %s" % [
			id, col.call("scope_eye"), rad, col.call("scope_tube"),
			col.call("scope_lens_black"), col.call("scope_lens_clear"),
			col.call("scope_reticle"), "PASS" if sight_ok else "*** FAIL ***"])
		if not sight_ok or not g.has_meta("scope_eye"):
			fail += 1
		get_tree().root.remove_child(gun.group)
		gun.group.free()
	print("=" .repeat(72))
	print("=== 狙击镜契约全部通过 ===" if fail == 0 else "=== 失败 %d 项 ===" % fail)
	get_tree().quit(1 if fail > 0 else 0)
