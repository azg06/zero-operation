class_name Minimap extends Control
## 小地图(对应 hud.js 的 _drawMinimap / _drawMapBase)
## 极简军事终端设计:深灰磨砂底 + 细白线边框 + 轻量几何图标
## 图标规范:玩家=白色三角,队友=绿色圆点,已侦察敌人=红色菱形,载具=轮廓图标,据点=大字字母
## 底部信息条:当前模式 / 队伍人数 / 网络延迟 / 帧率(极小字号)
## 附带:四向罗盘 + 缩放级别(滚轮/±按钮) + 占领进度弧 + 争夺闪烁 + BR 毒圈精简模式

const MAP_SIDE := 288.0            # 地图边长(1920 宽基准 ≈ 15% 屏宽)
const STATS_H := 24.0              # 底部状态条高度

const BG_COL := Color(0.05, 0.06, 0.08, 0.72)      # 深灰半透明磨砂底
const FRAME_COL := Color(0.78, 0.84, 0.9, 0.5)     # 细白线边框
const GRID_COL := Color(0.45, 0.55, 0.62, 0.08)    # 淡青网格
const BLD_COL := Color(0.16, 0.2, 0.24, 0.9)
const BLD_EDGE := Color(0.3, 0.36, 0.4, 0.8)
const US_COL := Color(0.35, 0.8, 0.5)              # 友军绿(低饱和)
const RU_COL := Color(1.0, 0.55, 0.22)             # 敌方橙(低饱和)
const NEU_COL := Color(0.55, 0.6, 0.66)            # 中性灰
const PLAYER_FILL := Color(0.16, 0.78, 0.86)       # 玩家青绿
const PLAYER_OUT := Color(0.92, 0.96, 1.0, 0.92)   # 白色描边
# ---- BR 精简模式:毒圈(青绿)+ 缩圈目标圈 + 队友绿点 ----
const ZONE_FILL := Color(0.05, 0.62, 0.6, 0.14)    # 当前安全区填充(蓝绿)
const ZONE_BORDER := Color(0.05, 0.62, 0.6, 0.85)  # 当前安全区描边
const ZONE_TARGET_COL := Color(0.35, 0.85, 0.8, 0.4)  # 缩圈目标圈(淡描边)
const TEAMMATE_COL := Color(0.35, 0.8, 0.5)        # 队友点
const BR_BLD_COL := Color(0.58, 0.66, 0.72, 0.22)  # BR 建筑块(浅青灰,半透明)
const ZONE_CLIP_SEGS := 40                         # 毒圈圆→多边形近似段数(裁剪用)

const MODE_NAMES := {
	"conquest": "征服", "breakthrough": "突破", "campaign": "战役",
	"tdm": "团队死斗", "br": "大逃杀",
}

var _zoom := 1.0
static var _br_stats_on := false   # 仅 --test 运行时记录自绘诊断(生产零开销)
var _br_draw_stats := {}   # BR 自绘诊断(测试断言):{ zone: bool, teammates: int, buildings: int, skipped_icons: bool }
var _br_blocks_cache := {} # BR 建筑布局像素缓存(键=s:zoom,值=Array[Rect2];静态布局只算一次)
var _stats_t := 0.0        # 状态条刷新节流(低层信息,30Hz 刷新)


func _init() -> void:
	# 自绘诊断仅测试模式记录(hud/game 侧测试脚本经 -- --test 运行;静态变量启动时固化)
	_br_stats_on = OS.get_cmdline_user_args().has("--test")
	custom_minimum_size = Vector2(MAP_SIDE, MAP_SIDE + STATS_H)
	mouse_filter = MOUSE_FILTER_STOP


## BR 自绘诊断记录(仅 --test 运行时生效,生产路径零字典写入)
func _br_stat(key: String, value) -> void:
	if _br_stats_on:
		_br_draw_stats[key] = value


func _ready() -> void:
	# 跨局恢复缩放(G.settings 持久化;无键时安全默认 1x)
	_zoom = clampf(float(G.settings.get("minimap_zoom", 1.0)), 1.0, 3.0)


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 1.0, 3.0)
	G.settings["minimap_zoom"] = _zoom
	queue_redraw()


## 世界坐标(Vector2 x,z)→ 本地像素
## 视窗钳制在地图边界内:1x 时窗口=整图,地图始终完整铺满框架且居中;
## >1x 时以玩家为中心缩放,玩家贴边时窗口贴地图边界(地图不悬浮/不偏移)
func _wm2(v: Vector2, ws: float, s: float) -> Vector2:
	var half: float = ws / _zoom
	var c := Vector2(0, 0)
	if _zoom > 1.0 and G.player != null and G.player.alive:
		c = Vector2(G.player.pos.x, G.player.pos.z)
	var lo := Vector2(half - ws, half - ws)
	var hi := Vector2(ws - half, ws - half)
	c = c.clamp(lo, hi)
	var sc: float = (s * _zoom) / (2 * ws)
	return (v - (c - Vector2(half, half))) * sc


## 世界地图方形区域 → 本地像素矩形(用于毒圈裁剪):世界坐标 ±G.bounds
func _world_rect_px(ws: float, s: float) -> Rect2:
	var b: float = G.bounds if G.bounds > 0 else ws / 2.0 - 10.0
	var tl := _wm2(Vector2(-b, -b), ws, s)
	var sc: float = (s * _zoom) / (2 * ws)
	return Rect2(tl, Vector2(2.0 * b * sc, 2.0 * b * sc))


## 圆∩矩形裁剪(Sutherland-Hodgman):圆近似为 ZONE_CLIP_SEGS 边形,在像素空间与矩形求交。
## 返回:null=圆完全在矩形内(无需裁剪,整圆绘制);空 PackedVector2Array=无交集(不绘制);
## 否则为裁剪后顶点序列(凸多边形,可 draw_colored_polygon / draw_polyline 闭合)。
static func _clip_circle_rect(c: Vector2, r: float, rect: Rect2) -> Variant:
	if r <= 0.0:
		return PackedVector2Array()
	var rl := rect.position.x
	var rt := rect.position.y
	var rr := rect.end.x
	var rb := rect.end.y
	if c.x - r >= rl and c.x + r <= rr and c.y - r >= rt and c.y + r <= rb:
		return null
	if c.x - r >= rr or c.x + r <= rl or c.y - r >= rb or c.y + r <= rt:
		return PackedVector2Array()
	var poly := PackedVector2Array()
	for i in ZONE_CLIP_SEGS:
		var a: float = TAU * i / ZONE_CLIP_SEGS
		poly.append(c + Vector2(cos(a), sin(a)) * r)
	var out := poly
	for edge in 4:
		var inp := out
		out = PackedVector2Array()
		for i in inp.size():
			var a: Vector2 = inp[i]
			var b: Vector2 = inp[(i + 1) % inp.size()]
			var a_in := false
			var b_in := false
			var t := 0.0
			match edge:
				0:  # 矩形左边 x>=rl
					a_in = a.x >= rl; b_in = b.x >= rl; t = (rl - a.x) / (b.x - a.x)
				1:  # 矩形右边 x<=rr
					a_in = a.x <= rr; b_in = b.x <= rr; t = (rr - a.x) / (b.x - a.x)
				2:  # 矩形上边 y>=rt
					a_in = a.y >= rt; b_in = b.y >= rt; t = (rt - a.y) / (b.y - a.y)
				_:  # 矩形下边 y<=rb
					a_in = a.y <= rb; b_in = b.y <= rb; t = (rb - a.y) / (b.y - a.y)
			if a_in and b_in:
				out.append(b)
			elif a_in:
				out.append(a.lerp(b, t))
			elif b_in:
				out.append(a.lerp(b, t))
				out.append(b)
	return out


## BR 建筑布局像素矩形(G.minimap_rects 世界矩形 → 本地像素),静态布局按 (s,zoom) 缓存
func _br_blocks_px(ws: float, s: float) -> Array:
	var key := str(s) + ":" + str(_zoom)
	if _br_blocks_cache.has(key):
		return _br_blocks_cache[key]
	var sc: float = (s * _zoom) / (2 * ws)
	var out := []
	for r in G.minimap_rects:
		var p := _wm2(Vector2(r["x"] - r["w"] / 2, r["z"] - r["d"] / 2), ws, s)
		out.append(Rect2(p, Vector2(maxf(r["w"] * sc, 1.0), maxf(r["d"] * sc, 1.0))))
	_br_blocks_cache[key] = out
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 1.25)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# 右上角 ± 缩放按钮
			var s: float = min(size.x, MAP_SIDE)
			if Rect2(s - 40, 6, 16, 16).has_point(event.position):
				_set_zoom(_zoom * 1.25)
			elif Rect2(s - 22, 6, 16, 16).has_point(event.position):
				_set_zoom(_zoom / 1.25)


func _draw_map_base(s: float) -> void:
	var ws: float = G.world_size if G.world_size > 0 else 120.0
	var sc: float = s * _zoom / (2 * ws)
	draw_rect(Rect2(0, 0, s, s), BG_COL)
	# 细网格(淡青线)—— 世界底图,BR 保留
	var step := s / 8.0
	for i in range(1, 8):
		draw_line(Vector2(i * step, 0), Vector2(i * step, s), GRID_COL, 1)
		draw_line(Vector2(0, i * step), Vector2(s, i * step), GRID_COL, 1)
	# BR 精简:不画建筑/旗帜(只画底图网格),其余图标由 _draw 的 BR 分支接管
	if G.mode == "br":
		_br_stat("skipped_icons", true)
		return
	# 建筑(扁平色块 + 顶部细亮线,去立体感)
	for r in G.minimap_rects:
		var rect := Rect2(_wm2(Vector2(r["x"] - r["w"] / 2, r["z"] - r["d"] / 2), ws, s), Vector2(r["w"] * sc, r["d"] * sc))
		if rect.size.x < 1 or rect.size.y < 1:
			continue
		draw_rect(rect, BLD_COL)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), BLD_EDGE)
		draw_rect(Rect2(rect.position, Vector2(1.0, rect.size.y)), BLD_EDGE)
	# 据点(大字字母 + 细圆环 + 占领进度弧 + 争夺闪烁)
	for f in G.flags:
		var cp := _wm2(Vector2(f.pos.x, f.pos.z), ws, s)
		var zone_locked: bool = G.mode == "breakthrough" and f.zone_locked
		var fill: Color
		var stroke: Color
		var lcol: Color
		if zone_locked:
			fill = Color(0.4, 0.43, 0.47, 0.14)
			stroke = Color(0.5, 0.54, 0.58)
			lcol = Color(0.55, 0.6, 0.64)
		elif f.owner_team != null and f.owner_team == G.player.team:
			fill = Color(0.16, 0.78, 0.86, 0.14)
			stroke = Color(0.16, 0.78, 0.86, 0.85)
			lcol = Color(0.62, 0.9, 0.95)
		elif f.owner_team != null:
			fill = Color(1.0, 0.55, 0.22, 0.12)
			stroke = Color(1.0, 0.55, 0.22, 0.8)
			lcol = Color(1.0, 0.72, 0.5)
		else:
			fill = Color(0.5, 0.54, 0.6, 0.1)
			stroke = Color(0.65, 0.7, 0.75, 0.6)
			lcol = Color(0.72, 0.76, 0.8)
		if f.contested:
			var pu := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
			stroke = Color(0.95, 0.34, 0.28, 0.55 + 0.45 * pu)
		draw_circle(cp, 7.0, fill)
		draw_arc(cp, 7.0, 0, TAU, 24, stroke, 1.3)
		# 大字字母
		draw_string(UiTheme.mono_font(), cp + Vector2(-7, 4), f.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lcol)
		# 占领进度弧(空心圆环片段,-100..100 映射 0..TAU;占领中 灰→蓝绿/橙)
		var frac := clampf((f.progress + 100.0) / 200.0, 0, 1)
		if not zone_locked and frac > 0.01 and frac < 0.999:
			var pcol := Color(0.05, 0.62, 0.6) if f.progress >= 0 else Color(1.0, 0.55, 0.22)
			draw_arc(cp, 10.0, -PI / 2, -PI / 2 + frac * TAU, 24, pcol, 2.0)


func _draw() -> void:
	var s: float = min(size.x, MAP_SIDE)
	_draw_map_base(s)
	var p = G.player
	var ws: float = G.world_size if G.world_size > 0 else 120.0
	# BR 精简:只画毒圈(当前圈+缩圈目标圈)+ 队友(队 0 存活 bot)+ 玩家箭头
	if G.mode == "br":
		_draw_br(s, ws)
		_draw_compass(s)
		_draw_frame(s)
		_draw_stats_bar(s)
		return
	# 载具(按阵营着色 + 轮廓图标 + 航向短条)
	for v in G.vehicles:
		var vp := _wm2(Vector2(v.pos.x, v.pos.z), ws, s)
		if vp.x < -6 or vp.x > s + 6 or vp.y < -6 or vp.y > s + 6:
			continue
		var vc := US_COL if v.driver != null and v.driver.team == G.player.team else RU_COL
		_draw_vehicle_icon(vp, vc)
	# 友军与敌军
	for b in G.bots:
		if not b.alive:
			continue
		var bp := _wm2(Vector2(b.pos.x, b.pos.z), ws, s)
		if G.player != null and b.team == G.player.team:
			draw_circle(bp, 2.4, US_COL)
			draw_circle(bp, 2.4, Color(1, 1, 1, 0.55), false, 1.0)
		elif b.spotted > 0 or (b.last_fired_t > 0 and G.time - b.last_fired_t < 2):
			_draw_diamond(bp, 3.2, RU_COL)
	# 玩家三角(白色描边 + 青绿填充 + 航向线)
	if p != null and p.alive:
		var cp := _wm2(Vector2(p.pos.x, p.pos.z), ws, s)
		var ang: float = -p.yaw
		var tri := [Vector2(0, -6.5), Vector2(4.5, 5), Vector2(0, 2.8), Vector2(-4.5, 5)]
		var pts := PackedVector2Array()
		var outline := PackedVector2Array()
		for t in tri:
			var rx: float = t.x * cos(ang) - t.y * sin(ang)
			var ry: float = t.x * sin(ang) + t.y * cos(ang)
			pts.append(cp + Vector2(rx, ry))
			var ox: float = t.x * 1.4 * cos(ang) - t.y * 1.4 * sin(ang)
			var oy: float = t.x * 1.4 * sin(ang) + t.y * 1.4 * cos(ang)
			outline.append(cp + Vector2(ox, oy))
		draw_colored_polygon(outline, PLAYER_OUT)
		draw_colored_polygon(pts, PLAYER_FILL)
	_draw_compass(s)
	_draw_frame(s)
	_draw_stats_bar(s)


## 载具轮廓图标(小型:车身描边 + 两侧履带/车轮线,无方向指示线)
func _draw_vehicle_icon(cp: Vector2, col: Color) -> void:
	var half := Vector2(4.5, 3.0)
	# 车身矩形(描边)
	var c1 := cp + Vector2(0, -2.5)
	var r := Rect2(c1 - half, half * 2.0)
	draw_rect(r, Color(col.r, col.g, col.b, 0.18))
	draw_rect(r, Color(col.r, col.g, col.b, 0.9), false, 1.2)
	# 两侧轮/履带线
	var p1 := cp + Vector2(-4.5, 0.5)
	var p2 := cp + Vector2(4.5, 0.5)
	draw_line(p1, p1 + Vector2(0, 2.6), col, 1.0)
	draw_line(p2, p2 + Vector2(0, 2.6), col, 1.0)
	draw_line(p1 + Vector2(0, 2.6), p2 + Vector2(0, 2.6), col, 1.0)


## 红色菱形(已侦察敌人)
func _draw_diamond(cp: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		cp + Vector2(0, -r), cp + Vector2(r, 0), cp + Vector2(0, r), cp + Vector2(-r, 0)])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.3))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.2)


## BR 精简绘制:①毒圈(当前安全区青绿圆 + 缩圈目标圈淡描边)②队友(队 0 存活 bot 绿点)
## ③玩家自身三角;其余图标(旗帜/敌人/载具/建筑)一律不画。
## 数据源:G.br(zone_center/zone_radius/zone_target_c/zone_target_r)→ 回退 G.portal 镜像;
## 队友 = squad_id == GameMode_BR.BR_PLAYER_SQUAD(0) 的存活 bot。
## 防御:G.br 未就绪/字段缺失时静默跳过对应绘制,不报错。
func _draw_br(s: float, ws: float) -> void:
	_br_stat("zone", false)
	_br_stat("teammates", 0)
	_br_stat("buildings", 0)
	# 建筑布局(浅色矩形块):数据源 G.minimap_rects(world_builder 记录的真实建筑 AABB);
	# 画在毒圈之下保证层次分明。布局静态,像素矩形按 (s,zoom) 缓存只算一次。
	for bld in _br_blocks_px(ws, s):
		draw_rect(bld, BR_BLD_COL)
	_br_stat("buildings", G.minimap_rects.size())
	var br: Variant = G.get("br")
	var zc: Vector3 = Vector3.ZERO
	var zr := 0.0
	if br != null and br.get("zone_center") is Vector3:
		zc = br.zone_center
		zr = float(br.get("zone_radius"))
	else:
		var pm: Variant = G.get("portal")
		if pm != null and pm.get("zone_center") is Vector3:
			zc = pm.zone_center
			zr = float(pm.get("zone_radius"))
	if zr > 0.0:
		var sc: float = (s * _zoom) / (2 * ws)
		var cp := _wm2(Vector2(zc.x, zc.z), ws, s)
		var rp: float = zr * sc
		# 地图方形边界(世界 ±G.bounds 的像素矩形):毒圈/目标圈裁剪到方形内
		var zone_rect := _world_rect_px(ws, s)
		# 缩圈目标圈(正在缩圈/目标与当前不同时绘制;字段缺失则跳过)
		if br != null and br.get("zone_target_c") is Vector3:
			var tc: Vector3 = br.zone_target_c
			var tr: float = float(br.get("zone_target_r"))
			if tr > 0.0 and (not tc.is_equal_approx(zc) or not is_equal_approx(tr, zr)):
				var tp := _wm2(Vector2(tc.x, tc.z), ws, s)
				var tpoly: Variant = _clip_circle_rect(tp, tr * sc, zone_rect)
				if tpoly == null:
					draw_arc(tp, tr * sc, 0, TAU, 48, ZONE_TARGET_COL, 1.4)
				elif tpoly.size() >= 3:
					var tclosed := PackedVector2Array(tpoly)
					tclosed.append(tpoly[0])
					draw_polyline(tclosed, ZONE_TARGET_COL, 1.4)
		# 当前毒圈:完全在地图方形内走整圆快速路径;越界则多边形裁剪后绘制
		var zpoly: Variant = _clip_circle_rect(cp, rp, zone_rect)
		if zpoly == null:
			draw_circle(cp, rp, ZONE_FILL)
			draw_arc(cp, rp, 0, TAU, 48, ZONE_BORDER, 1.6)
		elif zpoly.size() >= 3:
			draw_colored_polygon(zpoly, ZONE_FILL)
			var zclosed := PackedVector2Array(zpoly)
			zclosed.append(zpoly[0])
			draw_polyline(zclosed, ZONE_BORDER, 1.6)
		_br_stat("zone", true)
	# 队友:与玩家同队(squad_id==0)的存活 bot,绿点带白描边
	for b in G.bots:
		if b == null or not b.alive:
			continue
		if b.get("squad_id") != GameMode_BR.BR_PLAYER_SQUAD:
			continue
		var bp := _wm2(Vector2(b.pos.x, b.pos.z), ws, s)
		draw_circle(bp, 3.0, TEAMMATE_COL)
		draw_circle(bp, 3.0, Color(1, 1, 1, 0.55), false, 1.0)
		_br_stat("teammates", int(_br_draw_stats.get("teammates", 0)) + 1)
	# 玩家三角(与常规模式同款:白色描边 + 青绿填充 + 航向线)
	var p = G.player
	if p != null and p.alive:
		var cp2 := _wm2(Vector2(p.pos.x, p.pos.z), ws, s)
		var ang: float = -p.yaw
		var tri := [Vector2(0, -6.5), Vector2(4.5, 5), Vector2(0, 2.8), Vector2(-4.5, 5)]
		var pts := PackedVector2Array()
		var outline := PackedVector2Array()
		for t in tri:
			var rx: float = t.x * cos(ang) - t.y * sin(ang)
			var ry: float = t.x * sin(ang) + t.y * cos(ang)
			pts.append(cp2 + Vector2(rx, ry))
			var ox: float = t.x * 1.4 * cos(ang) - t.y * 1.4 * sin(ang)
			var oy: float = t.x * 1.4 * sin(ang) + t.y * 1.4 * cos(ang)
			outline.append(cp2 + Vector2(ox, oy))
		draw_colored_polygon(outline, PLAYER_OUT)
		draw_colored_polygon(pts, PLAYER_FILL)


## 外框:4 条细白线,精确贴合内容区外圈像素(第 0 行/列与第 s-1 行/列),四边严格对称。
## 不用 draw_rect 的 1px 描边——它把线条画在矩形边界中线,左/上边落在控件外(压到游戏世界)、
## 右/下边落在控件内,导致框架相对内容整体错位 1px。最后绘制保证边框不被边缘内容盖住。
func _draw_frame(s: float) -> void:
	draw_rect(Rect2(0, 0, s, 1), FRAME_COL)
	draw_rect(Rect2(0, s - 1, s, 1), FRAME_COL)
	draw_rect(Rect2(0, 0, 1, s), FRAME_COL)
	draw_rect(Rect2(s - 1, 0, 1, s), FRAME_COL)


## 四向罗盘(北/东/南/西 + 刻度)+ 缩放按钮
func _draw_compass(s: float) -> void:
	var col := Color(0.6, 0.68, 0.74, 0.6)
	var f := UiTheme.mono_font()
	draw_string(f, Vector2(s * 0.5 - 4, 13), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.95, 0.4, 0.35, 0.8))
	draw_string(f, Vector2(s - 12, s * 0.5 + 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, col)
	draw_string(f, Vector2(4, s * 0.5 + 4), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, col)
	draw_string(f, Vector2(s * 0.5 - 4, s - 6), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, col)
	# 四边刻度
	for i in 12:
		var tx: float = (i + 0.5) / 12.0 * s
		draw_line(Vector2(tx, 0), Vector2(tx, 3), Color(0.5, 0.6, 0.66, 0.35), 1)
		draw_line(Vector2(tx, s - 3), Vector2(tx, s), Color(0.5, 0.6, 0.66, 0.35), 1)
		draw_line(Vector2(0, tx), Vector2(3, tx), Color(0.5, 0.6, 0.66, 0.35), 1)
		draw_line(Vector2(s - 3, tx), Vector2(s, tx), Color(0.5, 0.6, 0.66, 0.35), 1)
	# 右上角缩放按钮(±)
	var bs: float = min(size.x, MAP_SIDE)
	var bcol := Color(0.55, 0.7, 0.78, 0.7)
	draw_string(f, Vector2(bs - 40, 19), "+", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, bcol)
	draw_string(f, Vector2(bs - 22, 19), "-", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, bcol)


## 底部信息条(低层信息,极小字号):当前模式 / 队伍人数 / 网络延迟 / 帧率
## 由 _process 节流 10Hz 刷新,不逐帧重绘
func _process(dt: float) -> void:
	# 统一 30Hz 刷新(与 update_hud 的 8Hz 强制重绘解耦,消除混合节流的跳动)
	_stats_t += dt
	if _stats_t >= 0.033:
		_stats_t = 0.0
		if is_visible_in_tree():
			queue_redraw()


func _draw_stats_bar(s: float) -> void:
	var f := UiTheme.mono_font()
	var y0: float = s + 5.0
	var dim := Color(0.6, 0.68, 0.75, 0.75)
	var bright := Color(0.78, 0.88, 0.95, 0.9)
	# 第一行:模式 · 队伍人数
	var mode: String = str(MODE_NAMES.get(G.mode, G.mode))
	var us_n := 0
	var ru_n := 0
	var p = G.player
	if p != null and p.alive:
		if p.team == "us":
			us_n += 1
		else:
			ru_n += 1
	for b in G.bots:
		if b.alive:
			if b.team == "us":
				us_n += 1
			else:
				ru_n += 1
	var team_txt: String
	if G.mode == "br":
		team_txt = "存活 %d" % us_n
	else:
		team_txt = "我方 %d / 敌方 %d" % [us_n, ru_n]
	draw_string(f, Vector2(6, y0 + 9), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, bright)
	var mode_w: float = f.get_string_size(mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(f, Vector2(6 + mode_w + 8, y0 + 9), team_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	# 第二行:延迟 / 帧率
	var fps := Engine.get_frames_per_second()
	var line2 := "PING %dMS · %d FPS" % [24, int(fps)]
	draw_string(f, Vector2(6, y0 + 19), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	# 分隔细线
	draw_line(Vector2(0, s), Vector2(s, s), Color(0.78, 0.84, 0.9, 0.22), 1)
