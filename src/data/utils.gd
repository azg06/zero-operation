class_name Utils
## 数学与碰撞工具(对应 utils.js)

const TAU := PI * 2.0


static func lerpf(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## 安全归一化:零向量返回 fallback(防 NaN 穿透)
static func safe_norm(v: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	var l := v.length()
	return fallback if l < 1e-6 else v / l


## 帧率无关的指数平滑
static func damp(a: float, b: float, k: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-k * dt))


static func rand(a: float = 1.0, b: float = NAN) -> float:
	if is_nan(b):
		return randf() * a
	return a + randf() * (b - a)


static func rand_int(a: int, b: int) -> int:
	return int(floor(rand(float(a), float(b) + 1.0)))


static func choice(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


static func dist_2d(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := ax - bx
	var dz := az - bz
	return sqrt(dx * dx + dz * dz)


## 射线 vs AABB(slab 法),返回距离或 -1
static func ray_box(origin: Vector3, dir: Vector3, box: AABB, max_dist: float) -> float:
	var tmin := 0.0
	var tmax := max_dist
	var bmin: Vector3 = box.position
	var bmax: Vector3 = box.end
	for ax in 3:
		var o := origin[ax]
		var d := dir[ax]
		var mn := bmin[ax]
		var mx := bmax[ax]
		if absf(d) < 1e-9:
			if o < mn or o > mx:
				return -1.0
		else:
			var t1 := (mn - o) / d
			var t2 := (mx - o) / d
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
			if t1 > tmin:
				tmin = t1
			if t2 < tmax:
				tmax = t2
			if tmin > tmax:
				return -1.0
	return tmin


## ==================== 碰撞体空间网格(射线检测加速) ====================
## 地图构建后重建;DDA 只遍历射线经过的格子,印章数组去重(热路径零分配)
static var _grid := {}
static var _grid_cell := 20.0
static var _stamp := PackedInt32Array()
static var _ray_id := 0
static var _hit_result := { "dist": 0.0, "point": Vector3.ZERO, "normal": Vector3.ZERO }

# ---- [BENCH] 热点计时(--bench-collide 启用,默认零开销) ----
static var _bench := false
static var _bench_linear := false  # [BENCH] 临时:强制线性路径(基线对比用)
static var _bench_init := false
static var _bench_mc_t := 0.0
static var _bench_mc_n := 0
static var _bench_veh_t := 0.0
static var _bench_veh_n := 0
static var _bench_fh_t := 0.0
static var _bench_fh_n := 0


static func bench_init() -> void:
	if _bench_init:
		return
	_bench_init = true
	var ua := OS.get_cmdline_user_args()
	_bench = ua.has("--bench-collide")
	_bench_linear = ua.has("--bench-linear")
	if _bench:
		Engine.max_fps = 0  # 基准:解除 144 帧封顶,测真实 CPU 帧时间
		print("[BENCH] max_fps=0 已生效(当前 %d)" % Engine.max_fps)


static func bench_report(tag: String) -> void:
	if not _bench:
		return
	print("[BENCH] %s move_collide=%s vehicle_push=%s fire_hitscan=%s" % [
		tag,
		_bench_str(_bench_mc_t, _bench_mc_n),
		_bench_str(_bench_veh_t, _bench_veh_n),
		_bench_str(_bench_fh_t, _bench_fh_n)])


static func _bench_str(t: float, n: int) -> String:
	return "-" if n <= 0 else "%.1fusx%d" % [t / float(n), n]


static func rebuild_collider_grid() -> void:
	_grid.clear()
	_stamp = PackedInt32Array()
	_stamp.resize(G.colliders.size())
	for i in G.colliders.size():
		var b: AABB = G.colliders[i]
		var c0x := int(floor(b.position.x / _grid_cell))
		var c0z := int(floor(b.position.z / _grid_cell))
		var c1x := int(floor(b.end.x / _grid_cell))
		var c1z := int(floor(b.end.z / _grid_cell))
		for cx in range(c0x, c1x + 1):
			for cz in range(c0z, c1z + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = []
				(_grid[key] as Array).append(i)


## 射线 vs 世界(沿线格子内的静态碰撞体 + 地形),返回 { dist, point, normal } 或 null
static func raycast_world(origin: Vector3, dir: Vector3, max_dist: float) -> Variant:
	var best := max_dist
	var hit_box: Variant = null
	if not _grid.is_empty():
		_ray_id += 1
		if _ray_id <= 0:
			_ray_id = 1
			_stamp.fill(0)
		var rid := _ray_id
		var cell := _grid_cell
		var cx := int(floor(origin.x / cell))
		var cz := int(floor(origin.z / cell))
		var sx := 1 if dir.x >= 0.0 else -1
		var sz := 1 if dir.z >= 0.0 else -1
		var t_max_x := INF
		var t_max_z := INF
		var t_dx := INF
		var t_dz := INF
		if absf(dir.x) > 1e-9:
			t_max_x = (((cx + (1 if sx > 0 else 0)) * cell) - origin.x) / dir.x
			t_dx = cell / absf(dir.x)
		if absf(dir.z) > 1e-9:
			t_max_z = (((cz + (1 if sz > 0 else 0)) * cell) - origin.z) / dir.z
			t_dz = cell / absf(dir.z)
		var t := 0.0
		var guard := 0
		while t <= best and guard < 64:
			guard += 1
			var key := Vector2i(cx, cz)
			if _grid.has(key):
				for ci in _grid[key]:
					if ci >= G.colliders.size():
						continue
					if _stamp[ci] == rid:
						continue
					_stamp[ci] = rid
					var d := ray_box(origin, dir, G.colliders[ci], best)
					if d >= 0.0 and d < best:
						best = d
						hit_box = G.colliders[ci]
			if t_max_x < t_max_z:
				t = t_max_x
				t_max_x += t_dx
				cx += sx
			else:
				t = t_max_z
				t_max_z += t_dz
				cz += sz
	else:
		# 网格未建(兜底):线性扫描
		for i in G.colliders.size():
			var d := ray_box(origin, dir, G.colliders[i], best)
			if d >= 0.0 and d < best:
				best = d
				hit_box = G.colliders[i]
	# 地形高度场(步进 + 二分)
	if G.ground_h.is_valid() and not (origin.y > 4.0 and dir.y >= 0.0):
		var t_end := best
		if dir.y < -1e-6:
			t_end = minf(best, (origin.y + 4.0) / -dir.y)
		var prev_t := 0.0
		var prev_dy: float = origin.y - G.ground_h.call(origin.x, origin.z)
		if prev_dy > 0.0:
			var t := 1.5
			while t <= t_end:
				var px: float = origin.x + dir.x * t
				var py: float = origin.y + dir.y * t
				var pz: float = origin.z + dir.z * t
				var dy: float = py - G.ground_h.call(px, pz)
				if dy <= 0.0:
					var lo := prev_t
					var hi := t
					for j in 5:
						var mid := (lo + hi) * 0.5
						if origin.y + dir.y * mid - G.ground_h.call(origin.x + dir.x * mid, origin.z + dir.z * mid) <= 0.0:
							hi = mid
						else:
							lo = mid
					if hi < best:
						best = hi
						hit_box = "ground"
					break
				prev_t = t
				t += 1.5
	elif not G.ground_h.is_valid() and dir.y < -1e-6:
		var t2 := -origin.y / dir.y
		if t2 > 0.0 and t2 < best:
			best = t2
			hit_box = "ground"
	if hit_box == null:
		return null
	var point: Vector3 = origin + dir * best
	var normal := Vector3(0, 1, 0)
	if hit_box is AABB:
		var c: Vector3 = (hit_box as AABB).get_center()
		var size2: Vector3 = (hit_box as AABB).size * 0.5
		var dx := (point.x - c.x) / (size2.x + 1e-6)
		var dy2 := (point.y - c.y) / (size2.y + 1e-6)
		var dz := (point.z - c.z) / (size2.z + 1e-6)
		var ax2 := absf(dx)
		var ay2 := absf(dy2)
		var az2 := absf(dz)
		if ax2 > ay2 and ax2 > az2:
			normal = Vector3(signf(dx), 0, 0)
		elif ay2 > az2:
			normal = Vector3(0, signf(dy2), 0)
		else:
			normal = Vector3(0, 0, signf(dz))
	_hit_result["dist"] = best
	_hit_result["point"] = point
	_hit_result["normal"] = normal
	_hit_result["box"] = hit_box if hit_box is AABB else null
	return _hit_result


## 两点间是否有遮挡(用于 AI 视线;烟雾区阻断)
static func los_clear(a: Vector3, b: Vector3) -> bool:
	# 烟雾区:连线穿过烟雾即视为被遮蔽
	for s in G.smoke_zones:
		if _seg_near_point(a, b, s["pos"], s["radius"]):
			return false
	var dir := b - a
	var dist := dir.length()
	if dist < 0.001:
		return true
	dir /= dist
	return raycast_world(a, dir, dist - 0.1) == null


## 线段 ab 是否经过以 c 为球心 r 为半径的球体(近似:采样 8 点)
static func _seg_near_point(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	for i in 9:
		var p: Vector3 = a.lerp(b, i / 8.0)
		if p.distance_squared_to(c) < r * r:
			return true
	return false


## 圆柱(玩家/AI) vs 静态碰撞体 推挤解算,pos 为脚底中心
## 注意:Vector3 为值类型,必须返回修正后的位置
## [PERF] P0-1:网格化 —— 每 pass 按 pos 查 20m 空间网格取候选盒(半径+1.5m 边距
## 最多触及 4 格,覆盖 pass 内推挤累计位移),索引升序处理保证与线性扫描顺序一致;
## 网格未建时回退原线性路径,行为完全一致
static func move_collide(pos: Vector3, radius: float, height: float) -> Vector3:
	if not _bench_init:
		bench_init()
	var _bt0 := Time.get_ticks_usec() if _bench else 0
	var colliders := G.colliders
	var n := colliders.size()
	for iter in 3:
		var seq: Variant = range(n) if (_grid.is_empty() or _bench_linear) else colliders_near(pos, radius)
		var pushed := false
		for i in seq:
			var b: AABB = colliders[i]
			# 垂直重叠检查(允许跨上 0.55m 的矮台阶)
			if pos.y + 0.55 >= b.end.y or pos.y + height <= b.position.y:
				continue
			# 最近点(XZ)
			var cx := clampf(pos.x, b.position.x, b.end.x)
			var cz := clampf(pos.z, b.position.z, b.end.z)
			var dx := pos.x - cx
			var dz := pos.z - cz
			var d2 := dx * dx + dz * dz
			if d2 < radius * radius:
				if d2 > 1e-10:
					var d := sqrt(d2)
					var push := (radius - d) / d
					pos.x += dx * push
					pos.z += dz * push
				else:
					# 圆心在盒内:沿最小穿透轴推出
					var px1 := pos.x - b.position.x + radius
					var px2 := b.end.x - pos.x + radius
					var pz1 := pos.z - b.position.z + radius
					var pz2 := b.end.z - pos.z + radius
					var m := minf(minf(px1, px2), minf(pz1, pz2))
					if m == px1:
						pos.x = b.position.x - radius
					elif m == px2:
						pos.x = b.end.x + radius
					elif m == pz1:
						pos.z = b.position.z - radius
					else:
						pos.z = b.end.z + radius
				pushed = true
		if not pushed:
			break
	# 地图边界
	pos.x = clampf(pos.x, -G.bounds, G.bounds)
	pos.z = clampf(pos.z, -G.bounds, G.bounds)
	if _bench:
		_bench_mc_t += Time.get_ticks_usec() - _bt0
		_bench_mc_n += 1
	return pos


## 空间网格邻域查询:返回 pos 半径 radius(+margin)范围内可能相交的碰撞体索引
## (升序去重,与线性扫描处理顺序一致);网格未建返回 null → 调用方回退线性扫描
## [PERF] P0-1/P0-2:move_collide / 载具 _push_out 共用
static func colliders_near(pos: Vector3, radius: float, margin := 1.5) -> Variant:
	if _grid.is_empty():
		return null
	var cell := _grid_cell
	var r := radius + margin
	_ray_id += 1
	if _ray_id <= 0:
		_ray_id = 1
		_stamp.fill(0)
	var rid := _ray_id
	var out: Array = []
	var c0x := int(floor((pos.x - r) / cell))
	var c1x := int(floor((pos.x + r) / cell))
	var c0z := int(floor((pos.z - r) / cell))
	var c1z := int(floor((pos.z + r) / cell))
	for cx in range(c0x, c1x + 1):
		for cz in range(c0z, c1z + 1):
			var lst: Variant = _grid.get(Vector2i(cx, cz))
			if lst == null:
				continue
			for ci in lst:
				if ci >= G.colliders.size() or ci >= _stamp.size() or _stamp[ci] == rid:
					continue
				_stamp[ci] = rid
				out.append(ci)
	out.sort()
	return out


## 射线 XZ 投影预过滤:返回点(x,z)到射线水平投影的距离²(含沿射线段约束,
## 若命中段外返回 INF 表示必定不命中)。射线近乎垂直时无法水平过滤,返回 -1
## (调用方不得剔除)。[PERF] P0-3:命中结算只对可能命中者做球探针
static func ray_xz_miss(origin: Vector3, dir: Vector3, x: float, z: float, best: float) -> float:
	var dxx := dir.x * dir.x + dir.z * dir.z
	if dxx < 1e-9:
		return -1.0
	var tox := x - origin.x
	var toz := z - origin.z
	var along := tox * dir.x + toz * dir.z
	if along < 0.0 or along > best * dxx:
		return INF
	return tox * tox + toz * toz - along * along / dxx


## 射线 vs 球体,返回距离或 -1
static func ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float, max_dist: float) -> float:
	var ox := origin.x - center.x
	var oy := origin.y - center.y
	var oz := origin.z - center.z
	var b := ox * dir.x + oy * dir.y + oz * dir.z
	var c := ox * ox + oy * oy + oz * oz - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	if t < 0.0 or t > max_dist:
		return -1.0
	return t


static func fmt_time(sec: float) -> String:
	var m := int(sec / 60.0)
	var s := int(sec) % 60
	return "%02d:%02d" % [m, s]


## 类型安全的身份比较(一方可能是 Dictionary 飞行员,语义同 JS 的 !==)
static func same_actor(a, b) -> bool:
	if a is Object and b is Object:
		return is_same(a, b)
	return false


## ==================== 弹道系统(子弹下坠/穿透/部位伤害) ====================
const BULLET_G := 9.0          # 游戏内子弹重力(m/s²,手感标定:稍低于真实重力)

static func bullet_speed_of(def) -> float:
	if def != null and def.get("bullet_speed") != null:
		return def["bullet_speed"]
	return 850.0


static func bullet_drop_of(def) -> float:
	if def != null and def.get("bullet_drop") != null:
		return def["bullet_drop"]
	return 1.0


static func bullet_pen_of(def) -> int:
	if def != null and def.get("penetration") != null:
		return int(def["penetration"])
	return 0


## 距离 dist 处视线下方的子弹下坠量(抛物线 y = ½gt²)
static func ballistic_drop(dist: float, speed: float, drop_scale: float) -> float:
	if speed <= 0.01:
		return 0.0
	var t := maxf(dist, 0.0) / speed
	return 0.5 * BULLET_G * t * t * drop_scale


## 下坠补偿瞄准:快速射线 + 两轮中间点迭代,返回 {dir, dist}
## 不需要完整物理弹丸,但命中点精确落在下坠抛物线上
static func ballistic_aim(origin: Vector3, dir: Vector3, speed: float, drop_scale: float, max_dist: float) -> Dictionary:
	var d := dir
	var hit = raycast_world(origin, d, max_dist)
	var dist: float = hit["dist"] if hit != null else max_dist
	for i in 2:
		var target: Vector3 = origin + d * dist
		target.y -= ballistic_drop(dist, speed, drop_scale)
		var delta: Vector3 = target - origin
		var l := delta.length()
		if l < 0.001:
			break
		d = delta / l
		var h2 = raycast_world(origin, d, max_dist)
		dist = h2["dist"] if h2 != null else max_dist
	return { "dir": d, "dist": dist }


## 射线出盒距离(用于计算穿透厚度)
static func ray_box_exit(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var tfar := INF
	for ax in 3:
		var d := dir[ax]
		if absf(d) < 1e-9:
			continue
		var t1 := (box.position[ax] - origin[ax]) / d
		var t2 := (box.end[ax] - origin[ax]) / d
		tfar = minf(tfar, maxf(t1, t2))
	return tfar


## 轻型(木质)掩体判定:细薄 + 低矮 ≈ 木板/围栏/木屋(可穿透)
## 碰撞盒无材质元数据,用几何启发:厚高实体(混凝土楼/碉堡)不可穿透
static func is_light_cover(box) -> bool:
	if not (box is AABB):
		return false
	var b: AABB = box
	return b.size.y < 3.5 and minf(b.size.x, b.size.z) < 0.45


## 身体部位倍率(头 2.0x 由武器 head_mult 承担,此处为其余部位)
static func part_mult(part: String) -> float:
	match part:
		"neck":
			return 1.5
		"limb":
			return 0.7
	return 1.0


## 角色部位探针:几何与 game.gd 的 _hitscan_actor 完全一致(头/胸/骨盆球),
## 额外细分颈部与四肢。返回 {dist, actor, part} 或 {}
static func probe_actor(actor, shooter, s_team, origin: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	if actor is Object and shooter is Object and is_same(actor, shooter):
		return {}
	if actor.team == s_team:
		return {}
	if actor.alive == false:
		return {}
	if actor.get("vehicle") != null:
		return {}
	var hf := 1.0
	if actor is Object and is_same(actor, G.player):
		hf = 0.3 if actor.prone else (0.72 if actor.crouched else 1.0)
	else:
		hf = 0.32 if actor.prone else 1.0
	# 头(1.56·hf,r0.21)— 与 game.gd 相同
	var head_pos := Vector3(actor.pos.x, actor.pos.y + 1.56 * hf, actor.pos.z)
	var d := ray_sphere(origin, dir, head_pos, 0.21, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "part": "head" }
	# 胸(1.05·hf,r0.42)— 命中点上沿细分颈部
	var chest_pos := Vector3(actor.pos.x, actor.pos.y + 1.05 * hf, actor.pos.z)
	d = ray_sphere(origin, dir, chest_pos, 0.42, max_d)
	if d >= 0:
		var p := origin + dir * d
		if p.y > actor.pos.y + 1.27 * hf:
			return { "dist": d, "actor": actor, "part": "neck" }
		return { "dist": d, "actor": actor, "part": "torso" }
	# 骨盆(0.5·hf,r0.38)→ 躯干
	var pelvis_pos := Vector3(actor.pos.x, actor.pos.y + 0.5 * hf, actor.pos.z)
	d = ray_sphere(origin, dir, pelvis_pos, 0.38, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "part": "torso" }
	# 四肢(game.gd 不检测,命中走手动结算)
	var leg_pos := Vector3(actor.pos.x, actor.pos.y + 0.22 * hf, actor.pos.z)
	d = ray_sphere(origin, dir, leg_pos, 0.2, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "part": "limb" }
	var arm_pos := Vector3(actor.pos.x, actor.pos.y + 0.95 * hf, actor.pos.z)
	d = ray_sphere(origin, dir, arm_pos, 0.17, max_d)
	if d >= 0:
		return { "dist": d, "actor": actor, "part": "limb" }
	return {}


## 武器数据副本:Dictionary 原生 duplicate;WeaponDef(RefCounted) 无 duplicate,手动浅拷贝
## (结算时需改 damage 倍率,不能直接改共享 def)
static func def_copy(d) -> Variant:
	if d is Dictionary:
		return (d as Dictionary).duplicate()
	if d is RefCounted:
		var c := WeaponsData.WeaponDef.new()
		for p in (d as RefCounted).get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				c.set(p["name"], (d as RefCounted).get(p["name"]))
		return c
	return d


## 弹道开火:下坠补偿瞄准 → 穿透链(木板可穿) → 部位倍率 → 命中结算
## 结算复用 G.game.fire_hitscan(伤害/压制/击杀反馈),四肢命中手动结算
static func ballistic_fire(shooter, def, origin: Vector3, dir: Vector3, muzzle_pos: Vector3) -> void:
	var spd := bullet_speed_of(def)
	var drop := bullet_drop_of(def)
	var pen := bullet_pen_of(def)
	var ba := ballistic_aim(origin, dir, spd, drop, 300.0)
	var fdir: Vector3 = ba["dir"]
	var o := origin
	var mult := 1.0                 # 穿透累计衰减系数
	var pen_left := pen
	var s_team = shooter.get("team") if shooter != null else null
	var tracer_c: Color = def.get("tracer") if def.get("tracer") != null else Color(1, 0.85, 0.63)
	for attempt in 6:
		var wall = raycast_world(o, fdir, 300.0)
		var best: float = wall["dist"] if wall != null else 300.0
		# 最近敌方角色(部位探针)
		var probe: Dictionary = {}
		var probe_max := best
		# [PERF] P0-3:XZ 投影预过滤(与 game.gd fire_hitscan 同构,纯几何只剔必不中者)
		var thr := 0.43 * 0.43  # 最大探针半径 0.42(胸)+FP 余量
		for b in G.bots:
			var pm := -1.0 if _bench_linear else ray_xz_miss(o, fdir, b.pos.x, b.pos.z, probe_max)
			if pm < 0.0 or pm <= thr:
				var pr := probe_actor(b, shooter, s_team, o, fdir, probe_max)
				if not pr.is_empty() and (probe.is_empty() or pr["dist"] < probe["dist"]):
					probe = pr
		if G.player != null and s_team != G.player.team:
			var prp := probe_actor(G.player, shooter, s_team, o, fdir, probe_max)
			if not prp.is_empty() and (probe.is_empty() or prp["dist"] < probe["dist"]):
				probe = prp
		if not probe.is_empty():
			best = probe["dist"]
		# 载具 / 空中载具 / 可破坏物(与 game.gd 相同优先级与几何)
		var hit_veh = null
		for v in G.vehicles:
			if v.dead:
				continue
			if v.driver != null and s_team != null and v.driver.team == s_team:
				continue
			var rv: float = v.def["radius"] + 0.35
			var mv := -1.0 if _bench_linear else ray_xz_miss(o, fdir, v.pos.x, v.pos.z, best)
			if mv < 0.0 or mv <= rv * rv:
				var dv := ray_sphere(o, fdir, Vector3(v.pos.x, v.pos.y + 1.2, v.pos.z), rv, best)
				if dv >= 0:
					best = dv
					hit_veh = v
		var hit_air = null
		for a in G.aircraft:
			if a.dead:
				continue
			if s_team != null and a.team == s_team:
				continue
			var ma := -1.0 if _bench_linear else ray_xz_miss(o, fdir, a.pos.x, a.pos.z, best)
			if ma < 0.0 or ma <= a.radius * a.radius:
				var da := ray_sphere(o, fdir, a.pos, a.radius, best)
				if da >= 0:
					best = da
					hit_air = a
		var hit_ds = null
		for ds in G.destructibles:
			if ds.dead:
				continue
			# 粗筛参考点用盒近面(中心投影 > 盒面 best 会被误杀——油箱打不坏回归)
			var _cc2: Vector3 = ds.collider.get_center()
			var md := -1.0 if _bench_linear else ray_xz_miss(o, fdir, _cc2.x - fdir.x * ds.collider.size.x * 0.5, _cc2.z - fdir.z * ds.collider.size.z * 0.5, best)
			if md < 0.0 or md <= ds.radius * ds.radius:
				# 真实碰撞盒判定(球面判定对球在盒内的目标会漏——战役油箱等)
				var dd := ray_box(o, fdir, ds.collider, best)
				if dd >= 0:
					best = dd
					hit_ds = ds
		# ---- 结算 ----
		if not probe.is_empty() and probe["dist"] <= best + 0.001:
			var part: String = probe["part"]
			if part == "limb":
				_apply_limb_hit(shooter, def, probe["actor"], o, fdir, probe["dist"], mult, tracer_c, muzzle_pos)
			else:
				var dc = def_copy(def)
				dc.damage = (dc.damage as float) * part_mult(part) * mult
				G.game.fire_hitscan(shooter, dc, o, fdir, muzzle_pos)
			return
		if hit_veh != null or hit_air != null or hit_ds != null:
			var dc2 = def_copy(def)
			dc2.damage = (dc2.damage as float) * mult
			G.game.fire_hitscan(shooter, dc2, o, fdir, muzzle_pos)
			return
		# 轻型(木)掩体:穿透,继续追踪
		if wall != null and pen_left > 0 and is_light_cover(wall["box"]):
			var box: AABB = wall["box"]
			var thick := maxf(ray_box_exit(o, fdir, box) - wall["dist"], 0.05)
			if thick > 1.2:
				break
			G.effects.impact(wall["point"], wall["normal"])
			pen_left -= 1
			mult *= 0.65
			o = wall["point"] + fdir * (thick + 0.06)
			continue
		G.game.fire_hitscan(shooter, def, o, fdir, muzzle_pos)
		return
	G.game.fire_hitscan(shooter, def, o, fdir, muzzle_pos)


## 四肢命中手动结算(fire_hitscan 几何不含四肢)
static func _apply_limb_hit(shooter, def, actor, origin: Vector3, dir: Vector3, dist: float, mult: float, tracer_c: Color, muzzle_pos: Vector3) -> void:
	# def 为 WeaponDef(RefCounted),其 get() 只接受 1 参;WeaponDef 有 rng 字段,直接属性访问(无则安全默认)
	var rng: Array = def.rng if def is WeaponsData.WeaponDef else [50.0, 100.0, 0.5]
	var falloff := 1.0
	if dist <= rng[0]:
		falloff = 1.0
	elif dist >= rng[1]:
		falloff = rng[2]
	else:
		falloff = 1.0 - (1.0 - rng[2]) * (dist - rng[0]) / (rng[1] - rng[0])
	var dmg: float = (def.damage if def is WeaponsData.WeaponDef else 25.0) * falloff * mult * 0.7
	var end: Vector3 = origin + dir * dist
	G.effects.tracer(muzzle_pos, end, tracer_c)
	var is_p: bool = shooter is Object and is_same(shooter, G.player)
	var s_pos = shooter.get("pos") if shooter != null else null
	if actor is Object and is_same(actor, G.player):
		# 仅 bot 打玩家才加权(玩家打 bot 不乘,走下方 take_damage 原伤害):按 bot skill 加权 0.7~1.0(与 game.gd:294 一致)
		var ai_mult: float = 0.7 + 0.3 * clampf((float(shooter.get("skill") if shooter != null else 0.8) - 0.45) / 0.65, 0.0, 1.0)
		G.player.damage(dmg * ai_mult, s_pos if s_pos != null else Vector3.ZERO, shooter, def)
	else:
		G.effects.blood(end, dir)
		actor.take_damage(dmg, shooter, false, def)
	if is_p:
		var killed: bool = actor.alive == false
		G.hud.show_hitmarker(killed, false)
		if killed:
			AudioSys.kill_confirm(false)
		else:
			AudioSys.hit(false)
