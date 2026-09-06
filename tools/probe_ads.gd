extends SceneTree
## ADS 视轴遮挡检测
##
## 为什么用射线而不是截图:
##   截图只能证明"这一帧看起来没问题",换把枪、换个配件就要重截一次,而且遮挡往往
##   只有几个像素,肉眼容易漏。这里沿视轴发射射线做三角形级相交测试,直接回答
##   "从眼睛到枪口这条 9mm 半径的圆柱内有没有几何挡路",可量化、可批量、可回归。
##
## 判定:
##   occl = 0.0   完全畅通
##   0 < occl < 1 部分遮挡(准星/照门属正常,已排除)
##   occl = 1.0   完全挡死,必须修


const WM = preload("res://src/models/weapon_models.gd")
const WD = preload("res://src/data/weapons_data.gd")

## 视轴半径:对应红点镜窗口的尺度,眼睛在这个半径内需要完全通透
const AXIS_R := 0.009
## 眼睛位置(ADS 时贴近枪托后上方),沿 -Z 看出去
const EYE_Z := 0.22

## 设计上就允许出现在视轴里的东西:机械瞄具(准星/照门本身就是瞄准参考)、
## 镜片类(半透明)、分划片。
const ALLOW_IN_AXIS := ["StockIrons", "lens", "lens_clear", "RetDot", "RetRing",
	"RetCross", "Muzzle", "ScopeEye", "OpticLens", "Lens",
	# ADS 时游戏隐藏原厂镜筒(gun.gd _update_pip_scope_visuals),视野由镜内 PIP
	# 接管 —— 探测与游戏行为一致,StockOptic 整组不参与视轴判定
	"StockOptic", "ScopeTubeBody", "ScopeMounts", "ScopeLensBlack", "ScopeLensClear",
	# M320 中折膛体的前后照门:必须随膛体折叠(设计如此),与 StockIrons 同为
	# "瞄具在视轴内"的合法存在
	"_GlRearSight", "_GlFrontSight"]


func _init() -> void:
	var defs: Dictionary = WD.build_weapons()
	# 默认突击步枪批次;支持命令行指定: godot --headless ... -- m249 pkm awm ...
	var ids: Array = ["m4", "ak", "scar", "aug", "g36c", "ak74", "famas", "g3"]
	var _uargs := OS.get_cmdline_user_args()
	if not _uargs.is_empty():
		ids = _uargs
	var fail := 0
	print("=".repeat(66))
	print("%-6s %-6s %-10s %-10s %s" % ["武器", "视轴y", "裸枪遮挡", "满配遮挡", "判定"])
	print("-".repeat(66))
	for id in ids:
		var def = defs.get(id)
		if def == null:
			print("%-6s 数据缺失" % id)
			fail += 1
			continue
		var sy: float = def.sight_y
		var bare := _occlusion(id, sy, {})
		var full := _occlusion(id, sy, _max_mods())
		var worst := maxf(bare, full)
		var verdict := "OK" if worst <= 0.001 else ("部分遮挡" if worst < 1.0 else "挡死!修!")
		if worst > 0.001:
			fail += 1
		print("%-6s %-6.3f %-10.2f %-10.2f %s" % [id, sy, bare, full, verdict])
	print("-".repeat(66))
	print("=== 全部通过 ===" if fail == 0 else "=== %d 把枪存在遮挡 ===" % fail)
	quit(fail)


## 挑一套"最容易挡视线"的满配:高倍镜 + 镭射 + 前握把 + 枪口
func _max_mods() -> Dictionary:
	return {
		"optic": "optic_6x",
		"muzzle": "muzzle_brake",
		"grip": "grip_vert",
		"laser": "laser_red",
		"barrel": "barrel_long",
		"stock": "stock_tac",
	}


func _occlusion(id: String, sight_y: float, mods: Dictionary) -> float:
	# rpg 的 ADS 由侧置 CLU 全屏 PIP 接管(view_ads 自定义持枪位),
	# 视轴眼位语义与常规枪不同,不做本检测(其 PIP 契约由 probe_scope 覆盖)。
	if id == "rpg":
		return 0.0
	var g := WM.build(id, false, mods)
	if g == null:
		return 1.0
	var eye := Vector3(0.0, sight_y, EYE_Z)
	var dir := Vector3(0, 0, -1)
	# 采样半径按武器类别:长枪 ADS 眼距瞄具 ~0.5m,瞳孔投影半径 ~9mm;
	# 手枪贴脸瞄准眼距照门 ~0.3m,投影半径 ~6mm(套筒顶距 sight_y 9mm 是贴脸
	# 瞄准的物理必然,套筒在视线正下方,不该按长枪标准判罚)。
	var r := 0.006 if id in ["m1911", "g17", "p226", "deagle", "m93r", "python", "sw686", "sw500"] else AXIS_R
	# 中心 + 四周 4 点采样(对应视轴圆截面)
	var offs := [
		Vector2(0, 0),
		Vector2(r, 0), Vector2(-r, 0),
		Vector2(0, r), Vector2(0, -r),
	]
	var hits := 0
	var who := ""
	for off in offs:
		var o := eye + Vector3(off.x, off.y, 0)
		var h := _ray_hit(g, o, dir)
		if h != "":
			hits += 1
			if who == "":
				who = h
	if who != "":
		print("      ^ 遮挡源: ", who)
	g.free()
	return float(hits) / float(offs.size())


# ---------------------------------------------------------------- 射线求交

## 返回命中的零件名,空串表示畅通
func _ray_hit(g: Node3D, origin: Vector3, dir: Vector3) -> String:
	var mis: Array[MeshInstance3D] = []
	_collect(g, mis)
	for mi in mis:
		if mi.mesh == null or mi.visible == false:
			continue
		if _allowed(mi):
			continue
		var t := _rel(g, mi)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if v.is_empty() or idx.is_empty():
				continue
			var n := idx.size() - (idx.size() % 3)
			for i in range(0, n, 3):
				var a := t * v[idx[i]]
				var b := t * v[idx[i + 1]]
				var c := t * v[idx[i + 2]]
				var tt := _tri_ray_t(origin, dir, a, b, c)
				if tt > 0.0:
					var p := origin + dir * tt
					var _chain := []
					var _pn: Node = mi
					while _pn != null:
						_chain.push_front(_pn.name)
						_pn = _pn.get_parent()
					return "%s @ (%.4f, %.4f, %.4f)" % [
						"/".join(PackedStringArray(_chain)), p.x, p.y, p.z]
	return ""


## Möller–Trumbore:命中返回距离 t,未命中返回 -1.0
func _tri_ray_t(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := d.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-9:
		return -1.0
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(p) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := tv.cross(e1)
	var vv := d.dot(q) * inv
	if vv < 0.0 or u + vv > 1.0:
		return -1.0
	var tt := e2.dot(q) * inv
	return tt if tt > 0.001 else -1.0


## 沿父链检查是否属于"允许出现在视轴里"的部件
func _allowed(mi: Node3D) -> bool:
	var n: Node = mi
	while n != null:
		if n.name in ALLOW_IN_AXIS:
			return true
		n = n.get_parent()
	return false


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect(c, out)


func _rel(g: Node3D, m: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = m
	while n != null and n != g:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
