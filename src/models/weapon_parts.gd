class_name WeaponParts extends RefCounted
## 高精度武器零件图元库(纯几何,零依赖)
##
## 存在意义:
##   WeaponModels 原有原语只有 box / cyl / ring 三种,所有零件都是数学意义上的绝对直角与
##   纯正圆柱 —— 这正是"不精细"的根本来源。真实枪械上没有任何一条绝对直棱:机匣有脱模
##   斜度与倒角,枪管螺母是六角,导轨是 10.4mm 齿距的皮卡汀尼,消焰器是开槽的,弹匣有
##   观察孔与托弹板。本库把这些"能一眼看出是枪"的特征做成可复用图元。
##
## 设计约束:
##   1. 零依赖 —— 不引用 WeaponModels。材质由调用方传入(通常是
##      WeaponModels._part_material("metal")),因此每个零件依然拿到独立材质变体,
##      保留原有"同枪不同部件色差/粗糙度不同"的表面层次。
##   2. 可被合并 —— 所有网格带 NORMAL + TEX_UV,能被 WeaponModels._merge_static 正确合并。
##   3. 硬边 —— 法线逐面写死,不做平滑。倒角的意义就在于捕捉高光,一平滑就白做了。
##
## 绕序:Godot 正面为"顺时针"(已用 BoxMesh/CylinderMesh 实测点积为 -1 确认)。
##   本库所有面写入都走 _quad_n / _tri_n,传入期望外法线后自动纠正绕序,调用方不必操心。
##
## 坐标约定:与 WeaponModels 一致 —— 枪口朝 -Z,上为 +Y。


## 贴图每米重复次数。metal_plate 这类 4k 板金贴图按实物尺度铺,避免近景拉伸。
const DEFAULT_UV_SCALE := 9.0

# MIL-STD-1913 皮卡汀尼导轨关键尺寸(米),按实物比例,不要随手改
const RAIL_PITCH := 0.0104      # 齿距 0.410"
const RAIL_TOOTH := 0.0052      # 齿顶宽 0.206"
const RAIL_TOOTH_H := 0.0042
const RAIL_TOP_W := 0.0212      # 顶面宽 0.835"

static var _mesh_cache: Dictionary = {}


# ==================== 底层:硬边三角面写入 ====================

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## 法线已在逐面写入时指定,绝不调用 generate_normals —— 那会把倒角平滑成一团糊。
##
## st.index() 是必须的:逐面独立顶点让 commit() 默认产出"非索引"网格(无 ARRAY_INDEX),
## 而 WeaponModels._merge_static 正是靠读 ARRAY_INDEX 做合并的 —— 少了索引,所有自定义
## 零件会在合并阶段被静默丢弃。开启索引后顶点属性(位置+法线+UV)不同的不会被合并,
## 硬边不受影响。
static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


## 按主法线轴做平面投影的 UV,保证板金贴图不拉伸。
static func _uv(p: Vector3, n: Vector3, s: float) -> Vector2:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if ax >= ay and ax >= az:
		return Vector2(p.z * s, p.y * s)
	if ay >= ax and ay >= az:
		return Vector2(p.x * s, p.z * s)
	return Vector2(p.x * s, p.y * s)


## 写入一个三角形。顶点顺序任意,按期望外法线自动纠正为 Godot 的顺时针正面。
static func _tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n_want: Vector3, s: float) -> void:
	var geo := (b - a).cross(c - a)
	if geo.dot(n_want) > 0.0:
		var t := c
		c = b
		b = t
	var n := -((b - a).cross(c - a)).normalized()
	st.set_normal(n)
	st.set_uv(_uv(a, n, s))
	st.add_vertex(a)
	st.set_uv(_uv(b, n, s))
	st.add_vertex(b)
	st.set_uv(_uv(c, n, s))
	st.add_vertex(c)


## 写入一个四边形。a,b,c,d 需沿外沿走一圈(顺逆均可),按期望外法线自动纠正。
static func _quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n_want: Vector3, s: float) -> void:
	var geo := (b - a).cross(c - a)
	if geo.dot(n_want) > 0.0:
		var t := d
		d = b
		b = t
	_tri_n(st, a, b, c, n_want, s)
	_tri_n(st, a, c, d, n_want, s)


## 按轴索引组装一个 Vector3,用于倒角盒的通用轴循环。
static func _vv(ax: int, sx: float, vx: float, ay: int, sy: float, vy: float, az: int, sz: float, vz: float) -> Vector3:
	var r := Vector3.ZERO
	r[ax] = sx * vx
	r[ay] = sy * vy
	r[az] = sz * vz
	return r


## 向已有 SurfaceTool 追加一个轴对齐盒(组合零件的基本积木)。
static func _box_at(st: SurfaceTool, c: Vector3, sz: Vector3, s: float) -> void:
	var hx := sz.x * 0.5
	var hy := sz.y * 0.5
	var hz := sz.z * 0.5
	var p000 := c + Vector3(-hx, -hy, -hz)
	var p100 := c + Vector3(hx, -hy, -hz)
	var p110 := c + Vector3(hx, hy, -hz)
	var p010 := c + Vector3(-hx, hy, -hz)
	var p001 := c + Vector3(-hx, -hy, hz)
	var p101 := c + Vector3(hx, -hy, hz)
	var p111 := c + Vector3(hx, hy, hz)
	var p011 := c + Vector3(-hx, hy, hz)
	_quad_n(st, p001, p101, p111, p011, Vector3(0, 0, 1), s)
	_quad_n(st, p100, p000, p010, p110, Vector3(0, 0, -1), s)
	_quad_n(st, p101, p100, p110, p111, Vector3(1, 0, 0), s)
	_quad_n(st, p000, p001, p011, p010, Vector3(-1, 0, 0), s)
	_quad_n(st, p011, p111, p110, p010, Vector3(0, 1, 0), s)
	_quad_n(st, p000, p100, p101, p001, Vector3(0, -1, 0), s)


# ==================== 核心体:倒角盒 ====================

## 12 条棱 + 8 个角全部斜切的盒子。
## 这是整套库的地基:真枪机匣、护木、弹匣、瞄具座没有一处是绝对直角,
## 倒角让边缘产生一条连续高光,低模也能读出"金属切削件"的质感。
static func bevel_box_mesh(w: float, h: float, d: float, b: float, uv_s: float) -> ArrayMesh:
	var key := PackedFloat64Array([0.0, w, h, d, b, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var hd := Vector3(w, h, d) * 0.5
	b = clampf(b, 0.0, minf(minf(hd.x, hd.y), hd.z) * 0.45)
	if b <= 0.0:
		var fb := _begin()
		_box_at(fb, Vector3.ZERO, Vector3(w, h, d), uv_s)
		var fm := _commit(fb)
		_mesh_cache[key] = fm
		return fm
	var iv := Vector3(hd.x - b, hd.y - b, hd.z - b)
	var st := _begin()
	# 6 个主面
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			var p0 := _vv(axis, sgn, hd[axis], a1, 1.0, iv[a1], a2, 1.0, iv[a2])
			var p1 := _vv(axis, sgn, hd[axis], a1, 1.0, iv[a1], a2, -1.0, iv[a2])
			var p2 := _vv(axis, sgn, hd[axis], a1, -1.0, iv[a1], a2, -1.0, iv[a2])
			var p3 := _vv(axis, sgn, hd[axis], a1, -1.0, iv[a1], a2, 1.0, iv[a2])
			_quad_n(st, p0, p1, p2, p3, n, uv_s)
	# 12 条棱斜面
	for a1 in 3:
		for a2 in 3:
			if a2 <= a1:
				continue
			var a3 := 3 - a1 - a2
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					var n := Vector3.ZERO
					n[a1] = s1
					n[a2] = s2
					n = n.normalized()
					var e0 := _vv(a1, s1, hd[a1], a2, s2, iv[a2], a3, -1.0, iv[a3])
					var e1 := _vv(a1, s1, hd[a1], a2, s2, iv[a2], a3, 1.0, iv[a3])
					var e2 := _vv(a1, s1, iv[a1], a2, s2, hd[a2], a3, 1.0, iv[a3])
					var e3 := _vv(a1, s1, iv[a1], a2, s2, hd[a2], a3, -1.0, iv[a3])
					_quad_n(st, e0, e1, e2, e3, n, uv_s)
	# 8 个角
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var c0 := Vector3(sx * hd.x, sy * iv.y, sz * iv.z)
				var c1 := Vector3(sx * iv.x, sy * hd.y, sz * iv.z)
				var c2 := Vector3(sx * iv.x, sy * iv.y, sz * hd.z)
				_tri_n(st, c0, c1, c2, n, uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


# ==================== 核心体:倒角圆柱 ====================

## 两端带倒角的圆柱(沿 Y 生成,与 CylinderMesh 一致,便于复用旋转逻辑)。
## 枪管口、消焰器、镜筒的"倒角圈"是金属件最容易被眼睛捕捉的细节。
static func chamfer_cyl_mesh(r: float, len: float, b: float, seg: int, uv_s: float,
		cap_top := true, cap_bottom := true) -> ArrayMesh:
	var key := PackedFloat64Array([1.0, r, len, b, float(seg), uv_s, 1.0 if cap_top else 0.0,
		1.0 if cap_bottom else 0.0])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var hy := len * 0.5
	b = clampf(b, 0.0, minf(r, hy) * 0.45)
	var ri := r - b
	var yc := hy - b
	var st := _begin()
	var po: Array[Vector3] = []
	var pi: Array[Vector3] = []
	for i in seg:
		var ang := TAU * float(i) / float(seg)
		var cs := cos(ang)
		var sn := sin(ang)
		po.append(Vector3(cs * r, 0.0, sn * r))
		pi.append(Vector3(cs * ri, 0.0, sn * ri))
	for i in seg:
		var j := (i + 1) % seg
		var radial := (Vector3(po[i].x, 0.0, po[i].z) + Vector3(po[j].x, 0.0, po[j].z)).normalized()
		# 侧面
		var s0 := po[i] + Vector3(0.0, -yc, 0.0)
		var s1 := po[j] + Vector3(0.0, -yc, 0.0)
		var s2 := po[j] + Vector3(0.0, yc, 0.0)
		var s3 := po[i] + Vector3(0.0, yc, 0.0)
		_quad_n(st, s0, s1, s2, s3, radial, uv_s)
		if cap_top:
			# 顶部倒角环 + 顶盖扇形
			var t0 := pi[i] + Vector3(0.0, hy, 0.0)
			var t1 := pi[j] + Vector3(0.0, hy, 0.0)
			var t2 := po[j] + Vector3(0.0, yc, 0.0)
			var t3 := po[i] + Vector3(0.0, yc, 0.0)
			_quad_n(st, t3, t2, t1, t0, (radial + Vector3.UP).normalized(), uv_s)
			_tri_n(st, Vector3(0.0, hy, 0.0), t0, t1, Vector3.UP, uv_s)
		if cap_bottom:
			var u0 := po[i] + Vector3(0.0, -yc, 0.0)
			var u1 := po[j] + Vector3(0.0, -yc, 0.0)
			var u2 := pi[j] + Vector3(0.0, -hy, 0.0)
			var u3 := pi[i] + Vector3(0.0, -hy, 0.0)
			_quad_n(st, u0, u1, u2, u3, (radial + Vector3.DOWN).normalized(), uv_s)
			_tri_n(st, Vector3(0.0, -hy, 0.0), u2, u3, Vector3.DOWN, uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


# ==================== 零件:皮卡汀尼导轨 ====================

## MIL-STD-1913 导轨。顶齿面位于 y = 0(调用方把节点摆到实际安装高度)。
## 原先的 _rail 用 40mm 齿距塞几个方块,近景一眼假;这里按 10.4mm 实物齿距排。
static func picatinny_mesh(length: float, uv_s: float, width := RAIL_TOP_W) -> ArrayMesh:
	var key := PackedFloat64Array([2.0, length, width, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var st := _begin()
	var z0 := -length * 0.5
	var z1 := length * 0.5
	# 底座:下部宽(含两侧安装卡槽),上部收窄成 T 型轨腰
	_box_at(st, Vector3(0.0, -0.0052, 0.0), Vector3(width + 0.0125, 0.0044, length), uv_s)
	_box_at(st, Vector3(0.0, -0.0028, 0.0), Vector3(width + 0.0044, 0.0024, length), uv_s)
	# 横向齿:齿顶在 y=0,槽底在 y=-RAIL_TOOTH_H
	var zc := z0 + RAIL_PITCH * 0.5
	while zc + RAIL_TOOTH * 0.5 <= z1 + 1e-6:
		_box_at(st, Vector3(0.0, -RAIL_TOOTH_H * 0.5, zc),
			Vector3(width, RAIL_TOOTH_H, RAIL_TOOTH), uv_s)
		zc += RAIL_PITCH
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


# ==================== 零件:滚花 / 减重槽 / 六角 ====================

## 滚花圆柱:表面沿周向交替凸起的细棱。用于枪管螺母、调节钮、握把螺丝等手拧件。
static func knurl_mesh(r: float, len: float, teeth: int, depth: float, uv_s: float) -> ArrayMesh:
	var key := PackedFloat64Array([3.0, r, len, float(teeth), depth, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var hy := len * 0.5
	var st := _begin()
	for i in teeth:
		var a0 := TAU * float(i) / float(teeth)
		var a1 := TAU * float(i + 0.5) / float(teeth)
		var a2 := TAU * float(i + 1.0) / float(teeth)
		var ro := r + depth
		var v := [
			Vector3(cos(a0) * r, -hy, sin(a0) * r),
			Vector3(cos(a1) * ro, -hy, sin(a1) * ro),
			Vector3(cos(a2) * r, -hy, sin(a2) * r),
			Vector3(cos(a0) * r, hy, sin(a0) * r),
			Vector3(cos(a1) * ro, hy, sin(a1) * ro),
			Vector3(cos(a2) * r, hy, sin(a2) * r),
		]
		var n0 := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		var n1 := Vector3(cos((a1 + a2) * 0.5), 0.0, sin((a1 + a2) * 0.5))
		_quad_n(st, v[0], v[1], v[4], v[3], n0, uv_s)
		_quad_n(st, v[1], v[2], v[5], v[4], n1, uv_s)
	# 两端封盖
	for i in teeth * 2:
		var a0 := TAU * float(i) / float(teeth * 2)
		var a1 := TAU * float(i + 1) / float(teeth * 2)
		var rr := r + (depth if (i % 2 == 1) else 0.0)
		var rr2 := r + (depth if ((i + 1) % 2 == 1) else 0.0)
		var p0 := Vector3(cos(a0) * rr, hy, sin(a0) * rr)
		var p1 := Vector3(cos(a1) * rr2, hy, sin(a1) * rr2)
		_tri_n(st, Vector3.ZERO + Vector3(0, hy, 0), p0, p1, Vector3.UP, uv_s)
		_tri_n(st, Vector3.ZERO + Vector3(0, -hy, 0), p1 - Vector3(0, hy * 2, 0),
			p0 - Vector3(0, hy * 2, 0), Vector3.DOWN, uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


## 带纵向减重槽的圆柱(转轮弹巢、栓动枪机、枪口制退器的常见特征)。
static func fluted_mesh(r: float, len: float, flutes: int, groove: float, uv_s: float) -> ArrayMesh:
	var key := PackedFloat64Array([4.0, r, len, float(flutes), groove, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var hy := len * 0.5
	var st := _begin()
	var seg := flutes * 4
	var rr: Array[float] = []
	for i in seg:
		var ph := float(i % 4)
		rr.append(r - (groove if ph == 1.0 or ph == 2.0 else 0.0))
	for i in seg:
		var j := (i + 1) % seg
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(j) / float(seg)
		var p0 := Vector3(cos(a0) * rr[i], -hy, sin(a0) * rr[i])
		var p1 := Vector3(cos(a1) * rr[j], -hy, sin(a1) * rr[j])
		var p2 := Vector3(cos(a1) * rr[j], hy, sin(a1) * rr[j])
		var p3 := Vector3(cos(a0) * rr[i], hy, sin(a0) * rr[i])
		var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		_quad_n(st, p0, p1, p2, p3, n, uv_s)
		_tri_n(st, Vector3(0, hy, 0), p3, p2, Vector3.UP, uv_s)
		_tri_n(st, Vector3(0, -hy, 0), p1, p0, Vector3.DOWN, uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


## 六角棱柱(枪管螺母/导气箍/消焰器扳手面)。直接用内置圆柱体 6 段,省一次自绘。
static func hex_nut_mesh(r: float, len: float) -> Mesh:
	var key := PackedFloat64Array([5.0, r, len])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = len
	cm.radial_segments = 6
	cm.rings = 1
	_mesh_cache[key] = cm
	return cm


# ==================== 零件:A2 鸟笼消焰器 ====================

## M16/M4 的 A2 鸟笼:前段实心环 + 后段三道纵向开槽(底部封闭,射击时不扬尘)。
## 用"外环片 + 纵向分隔筋"近似开槽,避免布尔运算 —— 低模下视觉等价,成本可忽略。
static func birdcage_mesh(r: float, len: float, uv_s: float) -> ArrayMesh:
	var key := PackedFloat64Array([6.0, r, len, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var st := _begin()
	var z0 := -len * 0.5
	var z1 := len * 0.5
	var seg := 16
	# 三段式:前端实心环 / 中段开槽(仅留 3 条纵向筋) / 后端与枪管连接的实心环
	var zones := [
		{"z0": z0, "z1": z0 + len * 0.28, "slots": false},
		{"z0": z0 + len * 0.28, "z1": z1 - len * 0.18, "slots": true},
		{"z0": z1 - len * 0.18, "z1": z1, "slots": false},
	]
	for z in zones:
		var za: float = z["z0"]
		var zb: float = z["z1"]
		if not z["slots"]:
			_ring_seg(st, r, za, zb, seg, 0.0, TAU, uv_s)
			continue
		# 开槽区:3 条纵向筋(上部一条 + 两侧各一条),筋间留空形成槽
		for k in 3:
			var base_ang := TAU * float(k) / 3.0 - PI * 0.5
			_ring_seg(st, r, za, zb, 5, base_ang - 0.30, base_ang + 0.30, uv_s)
	# 内芯:细管,让开槽处透出内部而不是看穿到背景
	_ring_seg(st, r * 0.55, z0 + len * 0.10, z1 - len * 0.05, 12, 0.0, TAU, uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


## 圆柱环面片:仅生成 [a0,a1] 弧度区间的外表面(开槽件的基本积木)。
## 轴向约定:与 CylinderMesh 一致,圆周在 XZ 平面、沿 Y 延伸;需要躺平成枪管方向时
## 由实例函数在节点上转 90°,不要在几何里各搞一套。
static func _ring_seg(st: SurfaceTool, r: float, y0: float, y1: float, seg: int,
		a0: float, a1: float, uv_s: float) -> void:
	var steps := maxi(2, int(round(absf(a1 - a0) / TAU * float(seg))))
	for i in steps:
		var b0 := a0 + (a1 - a0) * float(i) / float(steps)
		var b1 := a0 + (a1 - a0) * float(i + 1) / float(steps)
		var p0 := Vector3(cos(b0) * r, y0, sin(b0) * r)
		var p1 := Vector3(cos(b1) * r, y0, sin(b1) * r)
		var p2 := Vector3(cos(b1) * r, y1, sin(b1) * r)
		var p3 := Vector3(cos(b0) * r, y1, sin(b0) * r)
		var n := Vector3(cos((b0 + b1) * 0.5), 0.0, sin((b0 + b1) * 0.5))
		_quad_n(st, p0, p1, p2, p3, n, uv_s)


# ==================== 零件:螺丝 / 销钉 / 带槽板 ====================

## 一字槽螺丝(护木螺丝、瞄具调节钉)。近景能看到十字/一字槽是廉价感与精致感的分界。
static func screw_mesh(r: float, h: float, uv_s: float) -> ArrayMesh:
	var key := PackedFloat64Array([7.0, r, h, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var hy := h * 0.5
	var st := _begin()
	var seg := 12
	_ring_seg(st, r, -hy, hy, seg, 0.0, TAU, uv_s)
	# 顶面 + 一字槽(用下沉的窄条近似)
	_tri_fan(st, Vector3(0, hy, 0), r, seg, Vector3.UP, uv_s)
	_box_at(st, Vector3(0, hy - 0.0004, 0), Vector3(r * 1.75, 0.0012, r * 0.42), uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


## 圆柱销钉(机匣连接销)。两端带倒角,与 push pin 的实物观感一致。
static func pin_mesh(r: float, len: float, uv_s: float) -> ArrayMesh:
	return chamfer_cyl_mesh(r, len, minf(r * 0.35, 0.0008), 12, uv_s)


## 三角形扇形封盖(圆柱/螺丝端面的收口)。
static func _tri_fan(st: SurfaceTool, c: Vector3, r: float, seg: int, n: Vector3, s: float) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r) + Vector3(0, c.y, 0)
		var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r) + Vector3(0, c.y, 0)
		_tri_n(st, c, p0, p1, n, s)


## 带纵向散热槽的板件(护木、机匣侧板、隔热罩)。
static func ribbed_plate_mesh(w: float, h: float, d: float, ribs: int, groove: float, uv_s: float) -> ArrayMesh:
	var key := PackedFloat64Array([8.0, w, h, d, float(ribs), groove, uv_s])
	var hit: ArrayMesh = _mesh_cache.get(key)
	if hit != null:
		return hit
	var st := _begin()
	_box_at(st, Vector3(0, -groove * 0.5, 0), Vector3(w, h - groove, d), uv_s)
	for i in ribs:
		var zc := -d * 0.5 + d * (float(i) + 0.5) / float(ribs)
		_box_at(st, Vector3(0, h * 0.5 - groove * 0.5, zc),
			Vector3(w, groove, d / float(ribs) * 0.42), uv_s)
	var m := _commit(st)
	_mesh_cache[key] = m
	return m


# ==================== MeshInstance3D 包装层 ====================

static func _mi(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi


## 倒角盒实例。bevel 默认 0.0015(1.5mm),实物枪械零件的典型倒角量。
static func bevel_box(w: float, h: float, d: float, x: float, y: float, z: float,
		mat: Material, bevel := 0.0015, uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(bevel_box_mesh(w, h, d, bevel, uv_s), mat)
	mi.position = Vector3(x, y, z)
	return mi


## 倒角圆柱实例。axis: "z"(默认,枪管方向) / "y" / "x"。
static func chamfer_cyl(r: float, len: float, x: float, y: float, z: float,
		mat: Material, axis := "z", seg := 24, uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(chamfer_cyl_mesh(r, len, minf(r * 0.18, 0.0015), seg, uv_s), mat)
	if axis == "z":
		mi.rotation.x = PI * 0.5
	elif axis == "x":
		mi.rotation.z = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


## 皮卡汀尼导轨实例。安装面(齿顶)位于传入的 y。
static func picatinny(length: float, x: float, y: float, z: float, mat: Material,
		width := RAIL_TOP_W, uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(picatinny_mesh(length, uv_s, width), mat)
	mi.position = Vector3(x, y, z)
	return mi


static func knurl_cyl(r: float, len: float, x: float, y: float, z: float,
		mat: Material, axis := "z", teeth := 24, depth := 0.0008,
		uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(knurl_mesh(r, len, teeth, depth, uv_s), mat)
	if axis == "z":
		mi.rotation.x = PI * 0.5
	elif axis == "x":
		mi.rotation.z = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


static func fluted_cyl(r: float, len: float, x: float, y: float, z: float,
		mat: Material, axis := "z", flutes := 6, groove := 0.0015,
		uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(fluted_mesh(r, len, flutes, groove, uv_s), mat)
	if axis == "z":
		mi.rotation.x = PI * 0.5
	elif axis == "x":
		mi.rotation.z = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


static func hex_nut(r: float, len: float, x: float, y: float, z: float,
		mat: Material, axis := "z") -> MeshInstance3D:
	var mi := _mi(hex_nut_mesh(r, len), mat)
	if axis == "z":
		mi.rotation.x = PI * 0.5
	elif axis == "x":
		mi.rotation.z = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


static func birdcage(r: float, len: float, x: float, y: float, z: float,
		mat: Material, uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(birdcage_mesh(r, len, uv_s), mat)
	mi.rotation.x = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


static func screw(r: float, h: float, x: float, y: float, z: float,
		mat: Material, axis := "y", uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(screw_mesh(r, h, uv_s), mat)
	if axis == "z":
		mi.rotation.x = PI * 0.5
	elif axis == "x":
		mi.rotation.z = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


static func pin(r: float, len: float, x: float, y: float, z: float,
		mat: Material, axis := "x", uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(pin_mesh(r, len, uv_s), mat)
	if axis == "z":
		mi.rotation.x = PI * 0.5
	elif axis == "x":
		mi.rotation.z = PI * 0.5
	mi.position = Vector3(x, y, z)
	return mi


static func ribbed_plate(w: float, h: float, d: float, x: float, y: float, z: float,
		mat: Material, ribs := 6, groove := 0.002,
		uv_s := DEFAULT_UV_SCALE) -> MeshInstance3D:
	var mi := _mi(ribbed_plate_mesh(w, h, d, ribs, groove, uv_s), mat)
	mi.position = Vector3(x, y, z)
	return mi
