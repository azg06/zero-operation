class_name DeployMap extends Control
## 部署地图(BF2042 风格:青网格 + 友绿/敌橙旗帜 + 载具图标 + 重生信标 + 点击选点)

signal spawn_selected

var _blink := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(360, 360)
	mouse_filter = MOUSE_FILTER_STOP


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_blink += dt
	queue_redraw()


func _w2m(v: float, ws: float, s: float) -> float:
	return (v + ws) / (2 * ws) * s


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s: float = min(size.x, size.y)
		var ws: float = G.world_size if G.world_size > 0 else 120.0
		var wx: float = (event.position.x / s) * 2 * ws - ws
		var wz: float = (event.position.y / s) * 2 * ws - ws
		# 基地(默认出生点):攻方在北(顶),守方在南(底)
		var base_wz: float = (G.world_size - 16) if G.player.team == "ru" else -(G.world_size - 16)
		if Vector2(wx, wz - base_wz).length() < 22:
			G.hud.spawn_point = null
			G.hud.spawn_mate = null
			AudioSys.ui()
			spawn_selected.emit()
			queue_redraw()
			return
		# 重生信标(绿菱形,可点击)
		for d in G.deployables:
			if d["kind"] != "beacon" or d["team"] != G.player.team:
				continue
			if Vector2(d["pos"].x - wx, d["pos"].z - wz).length() < 16:
				G.hud.spawn_point = d
				G.hud.spawn_mate = null
				AudioSys.ui()
				spawn_selected.emit()
				queue_redraw()
				return
		# 小队成员(绿色标记)
		if G.player_squad != null:
			for m in G.player_squad["members"]:
				if not m.alive or m.vehicle != null:
					continue
				if Vector2(m.pos.x - wx, m.pos.z - wz).length() < 16:
					G.hud.spawn_mate = m
					G.hud.spawn_point = null
					AudioSys.ui()
					spawn_selected.emit()
					queue_redraw()
					return
		var best = null
		var bd := 24.0
		for f in G.flags:
			if f.owner_team != G.player.team:
				continue
			var d := Vector2(f.pos.x - wx, f.pos.z - wz).length()
			if d < bd:
				bd = d
				best = f
		G.hud.spawn_point = best
		if best != null:
			G.hud.spawn_mate = null
		AudioSys.ui()
		spawn_selected.emit()
		queue_redraw()


func _draw() -> void:
	var s: float = min(size.x, size.y)
	var ws: float = G.world_size if G.world_size > 0 else 120.0
	# 底色 + 青色科技网格
	draw_rect(Rect2(0, 0, s, s), Color(0.0, 0.02, 0.04))
	var grid := Color(UiTheme.PRIMARY.r, UiTheme.PRIMARY.g, UiTheme.PRIMARY.b, 0.06)
	var step := s / 10.0
	for i in range(1, 10):
		draw_line(Vector2(i * step, 0), Vector2(i * step, s), grid, 1)
		draw_line(Vector2(0, i * step), Vector2(s, i * step), grid, 1)
	var sc: float = s / (2 * ws)
	for r in G.minimap_rects:
		draw_rect(Rect2(_w2m(r["x"] - r["w"] / 2, ws, s), _w2m(r["z"] - r["d"] / 2, ws, s), r["w"] * sc, r["d"] * sc),
			Color(0.1, 0.16, 0.2, 0.9))
	# 旗帜:友绿 / 敌橙 / 中立灰 / 争夺黄闪
	for f in G.flags:
		var cx := _w2m(f.pos.x, ws, s)
		var cy := _w2m(f.pos.z, ws, s)
		var col: Color
		if f.contested:
			col = UiTheme.WARN.lerp(Color(1, 1, 1), 0.5 + sin(_blink * 8) * 0.5)
		elif f.owner_team != null:
			col = UiTheme.FRIENDLY if f.owner_team == G.player.team else UiTheme.ENEMY
		else:
			col = Color(0.55, 0.6, 0.65)
		draw_circle(Vector2(cx, cy), 8, Color(col.r, col.g, col.b, 0.32))
		draw_arc(Vector2(cx, cy), 8, 0, TAU, 24, col, 1.6)
		draw_string(UiTheme.font(), Vector2(cx - 5, cy + 4), f.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	# 载具图标:有人驾驶的己方载具(青色方块)
	for v in G.vehicles:
		if v.dead or v.driver == null:
			continue
		var vx := _w2m(v.pos.x, ws, s)
		var vy := _w2m(v.pos.z, ws, s)
		var vc := UiTheme.PRIMARY if v.driver.team == G.player.team else UiTheme.ENEMY
		var rect := Rect2(vx - 5, vy - 4, 10, 8)
		draw_rect(rect, Color(vc.r, vc.g, vc.b, 0.75), true)
		draw_rect(rect, Color(vc.r, vc.g, vc.b, 1), false, 1.2)
	# 顶部/底部标签:基地圆环位置随玩家阵营(攻方北顶/守方南底),"(你方)"标签须与圆环同位
	var def_side: bool = G.player.team == "ru"
	if G.mode == "breakthrough":
		if def_side:
			draw_string(UiTheme.font(), Vector2(0, 16), "进攻方基地", HORIZONTAL_ALIGNMENT_CENTER, s, 14, UiTheme.ENEMY)
			draw_string(UiTheme.font(), Vector2(0, s - 8), "防守方基地(你方)", HORIZONTAL_ALIGNMENT_CENTER, s, 14, UiTheme.FRIENDLY)
		else:
			draw_string(UiTheme.font(), Vector2(0, 16), "进攻方基地(你方)", HORIZONTAL_ALIGNMENT_CENTER, s, 14, UiTheme.FRIENDLY)
			draw_string(UiTheme.font(), Vector2(0, s - 8), "防守方基地", HORIZONTAL_ALIGNMENT_CENTER, s, 14, UiTheme.ENEMY)
	else:
		draw_string(UiTheme.font(), Vector2(0, 16), "友军基地", HORIZONTAL_ALIGNMENT_CENTER, s, 14, UiTheme.FRIENDLY)
		draw_string(UiTheme.font(), Vector2(0, s - 8), "敌军基地", HORIZONTAL_ALIGNMENT_CENTER, s, 14, UiTheme.ENEMY)
	# 选择失效(点位易主 / 实例已销毁 / 队友阵亡或上载具)则取消
	if G.hud.spawn_point != null and G.hud.spawn_point is Flag:
		if not is_instance_valid(G.hud.spawn_point) or G.hud.spawn_point.owner_team != G.player.team:
			G.hud.spawn_point = null
	if G.hud.spawn_mate != null and (not G.hud.spawn_mate.alive or G.hud.spawn_mate.vehicle != null):
		G.hud.spawn_mate = null
	# 基地默认出生点(攻方顶部 / 守方底部)
	var bx := _w2m(0, ws, s)
	var by := _w2m((G.world_size - 16) if G.player.team == "ru" else -(G.world_size - 16), ws, s)
	var base_sel: bool = G.hud.spawn_point == null and G.hud.spawn_mate == null
	draw_circle(Vector2(bx, by), 8 if not base_sel else 11, Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.3))
	draw_arc(Vector2(bx, by), 8 if not base_sel else 11, 0, TAU, 24,
		Color(0.42, 0.48, 0.54) if not base_sel else Color.WHITE, 1.5 if not base_sel else 3.0)
	if base_sel:
		# 选中脉冲:外扩呼吸环 + 旋转虚线
		draw_arc(Vector2(bx, by), 14 + sin(_blink * 5.0) * 2.0, 0, TAU, 32,
			Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.35), 1.2)
		var r0 := _blink * 2.2
		draw_arc(Vector2(bx, by), 17, r0, r0 + 1.1, 12,
			Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.8), 2.2)
	# 己方控制点位:可点击部署到前线
	for f in G.flags:
		if f.owner_team != G.player.team:
			continue
		var x := _w2m(f.pos.x, ws, s)
		var y := _w2m(f.pos.z, ws, s)
		var is_sel: bool = G.hud.spawn_point is Flag and G.hud.spawn_point == f
		draw_circle(Vector2(x, y), 12 if is_sel else 9, Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.35))
		draw_arc(Vector2(x, y), 12 if is_sel else 9, 0, TAU, 24,
			Color.WHITE if is_sel else UiTheme.FRIENDLY, 3.0 if is_sel else 1.5)
		if is_sel:
			# 选中点位:呼吸外环 + 旋转虚线(部署目标确认感)
			draw_arc(Vector2(x, y), 16 + sin(_blink * 5.0) * 2.5, 0, TAU, 32,
				Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.35), 1.4)
			var r1 := _blink * 2.4
			draw_arc(Vector2(x, y), 19, r1, r1 + 1.2, 14,
				Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.85), 2.4)
	# 重生信标(绿菱形,可点击)
	for d in G.deployables:
		if d["kind"] != "beacon" or d["team"] != G.player.team:
			continue
		var dx2 := _w2m(d["pos"].x, ws, s)
		var dy2 := _w2m(d["pos"].z, ws, s)
		var is_bsel: bool = G.hud.spawn_point is Dictionary and G.hud.spawn_point == d
		var rr := 7.0 if is_bsel else 5.0
		var pts := PackedVector2Array([Vector2(dx2, dy2 - rr), Vector2(dx2 + rr, dy2), Vector2(dx2, dy2 + rr), Vector2(dx2 - rr, dy2)])
		draw_colored_polygon(pts, Color(UiTheme.FRIENDLY.r, UiTheme.FRIENDLY.g, UiTheme.FRIENDLY.b, 0.7))
		if is_bsel:
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.WHITE, 1.5)
	# 小队成员(绿点,可点击)
	if G.player_squad != null:
		for m in G.player_squad["members"]:
			if not m.alive or m.vehicle != null:
				continue
			var x2 := _w2m(m.pos.x, ws, s)
			var y2 := _w2m(m.pos.z, ws, s)
			draw_circle(Vector2(x2, y2), 7 if G.hud.spawn_mate == m else 5, UiTheme.FRIENDLY)
			if G.hud.spawn_mate == m:
				draw_arc(Vector2(x2, y2), 7, 0, TAU, 20, Color.WHITE, 2)
	draw_string(UiTheme.font(), Vector2(0, s - 24), "点击己方点位 / 绿点队友 / 菱形信标 部署到前线",
		HORIZONTAL_ALIGNMENT_CENTER, s, 11, UiTheme.TXT_DIM)
