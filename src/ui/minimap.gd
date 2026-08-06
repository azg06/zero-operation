class_name Minimap extends Control
## 小地图(对应 hud.js 的 _drawMinimap / _drawMapBase)
## 3A 升级:颜色分级 + 四向罗盘 + 玩家箭头旋转描边 + 缩放级别(滚轮/±按钮)
## + 据点占领进度弧 + 争夺闪烁

const US_COL := Color(0.0, 1.0, 0.53)    # #00FF88 友军亮绿
const RU_COL := Color(1.0, 0.33, 0.0)    # #FF5500 敌方橙红
const BG_COL := Color(0.045, 0.062, 0.078)
const BLD_COL := Color(0.16, 0.2, 0.24)
const GRID_COL := Color(0.35, 0.55, 0.65, 0.07)
const PANEL_BG := Color(0.03, 0.04, 0.06, 0.72)     # 原 PanelContainer 面板底色
const PANEL_BORDER := Color(0.3, 0.38, 0.45, 0.6)   # 原面板 1px 边框

var _zoom := 1.0
var _blink := 0.0


func _init() -> void:
	# 自绘方形面板:背景+边框由 _draw_map_base 以控件实际尺寸绘制,内容严格对齐
	custom_minimum_size = Vector2(228, 228)
	mouse_filter = MOUSE_FILTER_STOP


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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 1.25)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# 右上角 ± 缩放按钮
			var s: float = min(size.x, size.y)
			if Rect2(s - 40, 6, 16, 16).has_point(event.position):
				_set_zoom(_zoom * 1.25)
			elif Rect2(s - 22, 6, 16, 16).has_point(event.position):
				_set_zoom(_zoom / 1.25)


func _draw_map_base(s: float) -> void:
	var ws: float = G.world_size if G.world_size > 0 else 120.0
	var sc: float = s * _zoom / (2 * ws)
	draw_rect(Rect2(0, 0, s, s), BG_COL)
	# 细网格(颜色分级:淡青线)
	var step := s / 8.0
	for i in range(1, 8):
		draw_line(Vector2(i * step, 0), Vector2(i * step, s), GRID_COL, 1)
		draw_line(Vector2(0, i * step), Vector2(s, i * step), GRID_COL, 1)
	# 建筑(实体块 + 顶部高光,立体感)
	for r in G.minimap_rects:
		var rect := Rect2(_wm2(Vector2(r["x"] - r["w"] / 2, r["z"] - r["d"] / 2), ws, s), Vector2(r["w"] * sc, r["d"] * sc))
		if rect.size.x < 1 or rect.size.y < 1:
			continue
		draw_rect(rect, BLD_COL)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.2)), Color(0.24, 0.3, 0.34))
		draw_rect(Rect2(rect.position, Vector2(1.2, rect.size.y)), Color(0.24, 0.3, 0.34))
	# 旗帜(颜色分级 + 占领进度弧 + 争夺闪烁)
	for f in G.flags:
		var cp := _wm2(Vector2(f.pos.x, f.pos.z), ws, s)
		var zone_locked: bool = G.mode == "breakthrough" and f.zone_locked
		var fill: Color
		var stroke: Color
		if zone_locked:
			fill = Color(0.4, 0.43, 0.47, 0.22)
			stroke = Color(0.55, 0.58, 0.62)
		elif f.owner_team != null and f.owner_team == G.player.team:
			fill = Color(0.2, 0.85, 0.5, 0.35)
			stroke = US_COL
		elif f.owner_team != null:
			fill = Color(0.95, 0.32, 0.12, 0.35)
			stroke = RU_COL
		else:
			fill = Color(0.55, 0.58, 0.6, 0.28)
			stroke = Color(0.65, 0.68, 0.7)
		if f.contested:
			stroke = Color(1, 1, 1).lerp(Color(1, 0.85, 0.2), 0.5 + sin(_blink * 9.0) * 0.5)
		draw_circle(cp, 7.5, fill)
		draw_arc(cp, 7.5, 0, TAU, 24, stroke, 1.6)
		# 占领进度弧(空心圆环片段,-100..100 映射 0..TAU)
		var frac := clampf((f.progress + 100.0) / 200.0, 0, 1)
		if not zone_locked and frac > 0.01 and frac < 0.999:
			draw_arc(cp, 10.5, -PI / 2, -PI / 2 + frac * TAU, 24, Color(stroke.r, stroke.g, stroke.b, 0.9), 2.2)
		draw_string(UiTheme.font(), Vector2(cp.x - 8, cp.y + 4), f.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.7, 0.72, 0.75) if zone_locked else Color.WHITE)


func _draw() -> void:
	var s: float = min(size.x, size.y)
	_blink += 0.016
	_draw_map_base(s)
	var p = G.player
	var ws: float = G.world_size if G.world_size > 0 else 120.0
	# 载具(按阵营着色 + 航向短条)
	for v in G.vehicles:
		var vp := _wm2(Vector2(v.pos.x, v.pos.z), ws, s)
		if vp.x < -4 or vp.x > s + 4 or vp.y < -4 or vp.y > s + 4:
			continue
		var vc := US_COL if v.driver != null and v.driver.team == G.player.team else RU_COL
		var r2 := Rect2(vp.x - 2.5, vp.y - 2.5, 5, 5)
		draw_rect(r2, Color(vc.r, vc.g, vc.b, 0.55))
		draw_rect(r2, Color(vc.r, vc.g, vc.b, 0.95), false, 1.0)
		# 航向短条(与玩家箭头同向:yaw=0→指上(北),yaw=90°→指左(西))
		var ang: float = -v.yaw
		draw_line(vp, vp + Vector2(sin(ang), -cos(ang)) * 7.0, Color(1, 1, 1, 0.5), 1.2)
	# 友军与敌军
	for b in G.bots:
		if not b.alive:
			continue
		var bp := _wm2(Vector2(b.pos.x, b.pos.z), ws, s)
		if G.player != null and b.team == G.player.team:
			draw_rect(Rect2(bp.x - 2, bp.y - 2, 4, 4), US_COL)
		elif b.spotted > 0 or (b.last_fired_t > 0 and G.time - b.last_fired_t < 2):
			draw_circle(bp, 2.6, RU_COL)
	# 玩家箭头(白色描边 + 琥珀填充 + 航向线)
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
			var ox: float = t.x * 1.35 * cos(ang) - t.y * 1.35 * sin(ang)
			var oy: float = t.x * 1.35 * sin(ang) + t.y * 1.35 * cos(ang)
			outline.append(cp + Vector2(ox, oy))
		draw_colored_polygon(outline, Color(1, 1, 1, 0.92))
		draw_colored_polygon(pts, Color(1, 0.88, 0.5))
		# 航向线(箭头前方 13px 淡线;与箭头前点旋转一致:ang=0→(0,-1)指上,yaw=90°→(-1,0)指左)
		draw_line(cp, cp + Vector2(sin(ang), -cos(ang)) * 13.0, Color(1, 1, 1, 0.4), 1.0)
	_draw_compass(s)
	_draw_frame(s)


## 外框:4 条 1px 实心条,精确贴合内容区外圈像素(第 0 行/列与第 s-1 行/列),四边严格对称。
## 不用 draw_rect 的 1px 描边——它把线条画在矩形边界中线,左/上边落在控件外(压到游戏世界)、
## 右/下边落在控件内,导致框架相对内容整体错位 1px。最后绘制保证边框不被边缘内容盖住。
func _draw_frame(s: float) -> void:
	draw_rect(Rect2(0, 0, s, 1), PANEL_BORDER)
	draw_rect(Rect2(0, s - 1, s, 1), PANEL_BORDER)
	draw_rect(Rect2(0, 0, 1, s), PANEL_BORDER)
	draw_rect(Rect2(s - 1, 0, 1, s), PANEL_BORDER)


## 四向罗盘(北/东/南/西 + 刻度)+ 缩放按钮
func _draw_compass(s: float) -> void:
	var col := Color(0.62, 0.72, 0.78, 0.75)
	var f := UiTheme.mono_font()
	draw_string(f, Vector2(s * 0.5 - 4, 13), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.85, 0.4, 0.35, 0.9))
	draw_string(f, Vector2(s - 12, s * 0.5 + 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col)
	draw_string(f, Vector2(4, s * 0.5 + 4), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col)
	draw_string(f, Vector2(s * 0.5 - 4, s - 6), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col)
	# 四边刻度
	for i in 12:
		var tx: float = (i + 0.5) / 12.0 * s
		draw_line(Vector2(tx, 0), Vector2(tx, 3), Color(0.5, 0.6, 0.66, 0.5), 1)
		draw_line(Vector2(tx, s - 3), Vector2(tx, s), Color(0.5, 0.6, 0.66, 0.5), 1)
		draw_line(Vector2(0, tx), Vector2(3, tx), Color(0.5, 0.6, 0.66, 0.5), 1)
		draw_line(Vector2(s - 3, tx), Vector2(s, tx), Color(0.5, 0.6, 0.66, 0.5), 1)
	# 右上角缩放按钮(±)
	var bs: float = min(size.x, size.y)
	var bcol := Color(0.55, 0.75, 0.85, 0.85)
	draw_string(f, Vector2(bs - 40, 19), "+", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, bcol)
	draw_string(f, Vector2(bs - 22, 19), "-", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, bcol)
