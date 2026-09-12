extends SceneTree
## QA: 在构建后、静态合并前,对每把枪做 ADS 视线遮挡筛查。
## 视线 = (0, sight_y, eye_z) 沿 -Z;排除 StockIrons/StockOptic(准星照门本来就该在线上),
## 其余任何网格 AABB 与视线相交都会被报告,用于抓"照门中间多一块建模"类问题。
## 用法: godot --headless --path <project> --script res://tools/qa_ads_occlusion.gd

const SIGHTS := {
	"m4": 0.108, "ak": 0.104, "scar": 0.112, "aug": 0.125,
	"g36c": 0.1, "ak74": 0.104, "famas": 0.1, "g3": 0.112,
	"mp5": 0.09, "ump": 0.1, "p90": 0.09, "vector": 0.088,
	"pp19": 0.095, "mpx": 0.09, "mp7": 0.085, "pp2000": 0.09,
	"m249": 0.125, "pkm": 0.122, "rpd": 0.115, "mg42": 0.13,
	"m60": 0.125, "mk48": 0.13, "negev": 0.125, "mg3": 0.13,
	"awm": 0.115, "m24": 0.112, "svd": 0.115, "m40": 0.113,
	"m82a1": 0.116, "l115": 0.114, "sv98": 0.113, "m2010": 0.115,
	"m110": 0.11, "sks": 0.105, "m1a": 0.112, "g28": 0.11,
	"mk14": 0.11, "m14": 0.112, "ar10": 0.11, "fal": 0.112,
}

func _collect(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		if c is Node3D:
			_collect(c, out)

func _rel_to_gun(mi: MeshInstance3D, gun: Node3D) -> Transform3D:
	var t := mi.transform
	var n: Node = mi.get_parent()
	while n != null and n != gun:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

func _under_named(node: Node, nm: String) -> bool:
	var n: Node = node
	while n != null:
		if n.name == nm:
			return true
		n = n.get_parent()
	return false

func _initialize() -> void:
	var WM = load("res://src/models/weapon_models.gd")
	var all_ok := true
	for id in SIGHTS:
		var g := Node3D.new()
		WM._build(id, g)
		var sight_y: float = SIGHTS[id]
		var eye_z := 0.24
		var ray_from := Vector3(0.0, sight_y, eye_z)
		var ray_dir := Vector3(0.0, 0.0, -1.0)
		var hits: Array = []
		var meshes: Array = []
		_collect(g, meshes)
		for mi in meshes:
			var minode := mi as MeshInstance3D
			if minode == null:
				continue
			if _under_named(minode, "StockIrons"):
				continue
			if _under_named(minode, "StockOptic"):
				continue
			var xf := _rel_to_gun(minode, g)
			var aabb: AABB = (xf * minode.get_aabb()) as AABB
			var hit = aabb.intersects_ray(ray_from, ray_dir)
			if hit != null and (hit as Vector3).z < eye_z - 0.001:
				var t: Vector3 = xf.origin
				hits.append("%s@(%.3f,%.3f,%.3f) hit_z=%.3f aabb=%s" % [
					minode.name, t.x, t.y, t.z, (hit as Vector3).z, str(aabb)])
		if hits.is_empty():
			print("[QA-ADS] ok %s sight_y=%.3f" % [id, sight_y])
		else:
			all_ok = false
			print("[QA-ADS] OCCLUSION %s sight_y=%.3f" % [id, sight_y])
			for h in hits:
				print("         ", h)
		g.free()
	print("[QA-ADS] done all_ok=%s" % str(all_ok))
	quit(0 if all_ok else 1)
