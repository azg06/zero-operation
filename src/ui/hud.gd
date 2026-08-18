class_name HUD extends CanvasLayer
## 战斗 HUD — 极简军事数字终端设计系统
## 设计语言:细边框 / 圆角 / 半透明磨砂(20~40%)/ 青绿+白主色 / 敌方橙 / 警告红 / 占领蓝绿
## 信息分层:
##   第一层(常驻):生命 / 弹药 / 准星 / 目标提示
##   第二层(偶尔):小地图 / 队友状态 / 载具状态 / 占领进度
##   第三层(临时):击杀播报 / 动态消息 / 横幅 / 语音提示 / 警告
## 动画统一:Ease Out 200~300ms,禁止瞬移(淡入/滑入/缩放/透明度渐变)

# ==================== 常量 ====================
const US_HEX := "#00ff88"
const RU_HEX := "#ff5500"

## 据点中文名(数据层只有字母 id;世界悬浮 UI 用)
const FLAG_NAMES := {
	"A": "指挥中心", "B": "前沿哨站", "C": "装甲兵站",
	"D": "通讯塔", "E": "补给基地", "F": "山腰据点",
}

## 武器配件短名(右下配件状态标签)
const MOD_SHORT := {
	"mag_ext": "扩容", "mag_quick": "快拔", "mag_ap": "穿甲", "mag_drum": "弹鼓",
	"muz_supp": "消音", "muz_flash": "消焰", "muz_brk": "制退", "muz_comp": "补偿", "muz_choke": "收束",
	"grip_vert": "垂直", "grip_ang": "斜角", "grip_light": "轻量", "grip_fg": "前握",
	"stock_light": "轻托", "stock_heavy": "重托", "stock_fold": "折托",
	"barrel_long": "长管", "barrel_short": "短管", "barrel_heavy": "重管",
	"trig_comp": "比赛", "trig_dual": "双段",
	"opt_reddot": "红点", "opt_holo": "全息", "opt_reddot_mini": "微红点", "opt_reddot_dot": "大视窗",
	"opt_2x": "2倍镜", "opt_1xprism": "棱镜",
	"laser_tac": "镭射", "laser_flash": "手电", "laser_ir": "红外",
}

## 模式名(小地图状态条)
const MODE_NAMES := {
	"conquest": "征服", "breakthrough": "突破", "campaign": "战役",
	"tdm": "团队死斗", "br": "大逃杀",
}

# ==================== 准星:四短线 + 中心点(命中白闪 + 淡环反馈 + 爆头微放大) ====================
# 光学瞄具准星样式(ret_style):reddot=纯红实心点 / holo=红环+点 / tac=细十字+点;
# 红点尺寸随分辨率稳定缩放,固定屏幕中心(不随散布),无模糊无发光
class Crosshair extends Control:
	var spread_px := 4.0
	var ch_opacity := 1.0
	var kick_px := 0.0          # 后坐力联动:射击时上跳,随相机后坐衰减回落
	var hit_t := 0.0            # 命中反馈计时
	var hit_kill := false
	var hit_head := false
	var zoom_k := 1.0           # 爆头轻微放大(平滑)
	var ret_style := ""         # ""=机械瞄具四短线 | reddot | holo | tac
	var ret_color := Color(1.0, 0.12, 0.1)   # 红点/全息分划红

	func show_hit(kill: bool, head: bool) -> void:
		hit_kill = kill
		hit_head = head
		hit_t = 0.35
		queue_redraw()

	func _process(dt: float) -> void:
		if hit_t > 0.0:
			hit_t -= dt
			if hit_t <= 0.0:
				hit_kill = false
				hit_head = false
			queue_redraw()
		var goal := 1.14 if (hit_t > 0.0 and hit_head) else 1.0
		if absf(zoom_k - goal) > 0.001:
			zoom_k = lerpf(zoom_k, goal, 1.0 - exp(-dt * 10.0))
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0 + Vector2(0, -kick_px)
		var col := Color(1, 1, 1, 0.8 * ch_opacity)
		# 光学瞄具准星:固定屏幕中心、不随散布扩散、尺寸按分辨率缩放
		if ret_style == "reddot":
			# 纯实心红点:极小、稳定、无圆环无十字
			var dr := clampf(2.0 * size.y / 1080.0, 1.5, 3.2)
			draw_circle(c, dr, Color(ret_color.r, ret_color.g, ret_color.b, 0.95 * ch_opacity))
			return
		if ret_style == "holo":
			# 全息:小圆环 + 中心实心点(经典 EOTech 风格)
			var s := clampf(size.y / 1080.0, 0.7, 1.4)
			var rr := 4.6 * s
			draw_arc(c, rr, 0, TAU, 24, Color(ret_color.r, ret_color.g, ret_color.b, 0.9 * ch_opacity), 1.4 * s)
			draw_circle(c, 1.6 * s, Color(ret_color.r, ret_color.g, ret_color.b, 0.95 * ch_opacity))
			return
		if ret_style == "tac":
			# 低倍战术镜:细十字 + 中心点(中心隙 1px,短线 7px)
			var s := clampf(size.y / 1080.0, 0.7, 1.4)
			var gap := 1.5 * s
			var L2 := 7.0 * s
			var cc := Color(0.0, 0.0, 0.0, 0.5 * ch_opacity)
			var cw := Color(1, 1, 1, 0.75 * ch_opacity)
			for i in 2:
				var tick_w: float = 1.2 if i == 0 else 0.7
				draw_line(c + Vector2(-gap - L2, 0), c + Vector2(-gap, 0), cw, tick_w)
				draw_line(c + Vector2(gap, 0), c + Vector2(gap + L2, 0), cw, tick_w)
				draw_line(c + Vector2(0, -gap - L2), c + Vector2(0, -gap), cw, tick_w)
				draw_line(c + Vector2(0, gap), c + Vector2(0, gap + L2), cw, tick_w)
				draw_line(c + Vector2(-gap - 1.2, 0), c + Vector2(-gap, 0), cc, tick_w + 0.8)
				draw_line(c + Vector2(gap, 0), c + Vector2(gap + 1.2, 0), cc, tick_w + 0.8)
				draw_line(c + Vector2(0, -gap - 1.2), c + Vector2(0, -gap), cc, tick_w + 0.8)
				draw_line(c + Vector2(0, gap), c + Vector2(0, gap + 1.2), cc, tick_w + 0.8)
				L2 *= 0.62
				gap *= 1.0
			draw_circle(c, 1.3 * s, cw)
			return
		var L := 8.0 * zoom_k
		var g := (5.0 + spread_px) * zoom_k
		var w := 1.5
		# 四短线(极简,中心留隙)
		draw_line(c + Vector2(0, -g - L), c + Vector2(0, -g), col, w)
		draw_line(c + Vector2(0, g), c + Vector2(0, g + L), col, w)
		draw_line(c + Vector2(-g - L, 0), c + Vector2(-g, 0), col, w)
		draw_line(c + Vector2(g, 0), c + Vector2(g + L, 0), col, w)
		# 中心小点
		draw_circle(c, 1.5, Color(1, 1, 1, 0.85 * ch_opacity))
		# 命中反馈:准星外围一圈极淡扩散环(不遮挡视野,不做巨大 X)
		if hit_t > 0.0:
			var k := clampf(hit_t / 0.35, 0.0, 1.0)
			var rc: Color
			if hit_kill:
				rc = Color(1.0, 0.55, 0.22, 0.5 * k)
			elif hit_head:
				rc = Color(0.16, 0.78, 0.86, 0.42 * k)
			else:
				rc = Color(1, 1, 1, 0.3 * k)
			var rr := (15.0 + (1.0 - k) * 24.0) * zoom_k
			draw_arc(c, rr, 0, TAU, 28, rc, 1.3)
			draw_arc(c, rr * 0.76, 0, TAU, 20, Color(rc.r, rc.g, rc.b, rc.a * 0.35), 1.0)


# ==================== 顶部横条:据点字母芯片(灰=中立 / 青=己方 / 橙=敌方 / 占领=环形动画) ====================
class FlagChip extends Control:
	var fid := ""
	var owner_team := ""         # "" | "us" | "ru"
	var contested := false
	var progress := 0.0          # -100..100
	var zone_locked := false
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(30, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		if _t >= 0.03:            # ~33Hz 脉冲重绘
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(0, 0, size.x, size.y)
		var bc: Color
		var fc: Color
		if owner_team == "us":
			bc = UiTheme.H_CYAN
			fc = Color(0.72, 0.94, 0.98)
		elif owner_team == "ru":
			bc = UiTheme.H_ORANGE
			fc = Color(1.0, 0.8, 0.62)
		else:
			bc = UiTheme.H_GRAY_DIM if zone_locked else UiTheme.H_GRAY
			fc = Color(0.72, 0.76, 0.8)
		if contested:
			var pu := 0.5 + 0.5 * sin(_t * 14.0)
			bc = Color(0.95, 0.34, 0.28, 0.4 + 0.5 * pu)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.05, 0.07, 0.35)
		sb.border_color = Color(bc.r, bc.g, bc.b, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, rect)
		# 字母
		draw_string(UiTheme.mono_font(), Vector2(0, size.y * 0.5 + 4.5), fid,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, fc)
		# 占领过程环形动画(灰→蓝绿 己方 / 灰→橙 敌方)
		var frac := clampf((progress + 100.0) / 200.0, 0.0, 1.0)
		if not zone_locked and frac > 0.01 and frac < 0.999:
			var c := size / 2.0
			var r := size.x * 0.5 + 2.0
			var pcol := UiTheme.H_TEAL if progress >= 0.0 else UiTheme.H_ORANGE
			draw_arc(c, r, PI / 2, PI / 2 + frac * TAU, 24, Color(0.4, 0.45, 0.5, 0.4), 1.6)
			draw_arc(c, r, PI / 2, PI / 2 + frac * TAU, 24, Color(pcol.r, pcol.g, pcol.b, 0.95), 1.8)


# ==================== 左侧中部:动态消息区(图标 + 两行文字,滑入滑出渐隐 2~4s) ====================
class EventFeed extends Control:
	const ROW_W := 330.0
	const ROW_H := 46.0
	const SPACING := 5.0
	const MAX_ROWS := 4
	var _rows: Array = []        # [{ panel }]

	func _init() -> void:
		custom_minimum_size = Vector2(ROW_W, ROW_H * MAX_ROWS + SPACING * (MAX_ROWS - 1))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_event(icon: String, title: String, sub: String, col: Color) -> void:
		var row := _make_row(icon, title, sub, col)
		add_child(row)
		_rows.append({ "panel": row })
		if _rows.size() > MAX_ROWS:
			var old: Dictionary = _rows.pop_front()
			if is_instance_valid(old["panel"]):
				_fade_out(old["panel"], 0.3)
		_relayout()
		# 入场:淡入 + 下滑 14px 回位(EaseOut 0.28s,禁止突然弹出)
		row.modulate.a = 0.0
		var y0: float = row.position.y
		row.position.y = y0 + 14.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(row, "position:y", y0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# 停留 ~3s 后渐隐滑出
		var held: float = 2.6 if _rows.size() > 2 else 3.4
		get_tree().create_timer(held).timeout.connect(func():
			if is_instance_valid(row) and row.is_inside_tree():
				_fade_out(row, 0.4))

	func _make_row(icon: String, title: String, sub: String, col: Color) -> PanelContainer:
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(ROW_W, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel",
			UiTheme.hud_frost(0.28, Color(col.r, col.g, col.b, 0.4), 1, 4, 10))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)
		var ic := Label.new()
		ic.theme = UiTheme.theme()
		ic.text = icon
		ic.custom_minimum_size = Vector2(26, 0)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.add_theme_font_size_override("font_size", 17)
		ic.add_theme_color_override("font_color", col)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)
		var tl := Label.new()
		tl.theme = UiTheme.theme()
		tl.text = title
		tl.add_theme_font_size_override("font_size", 14)
		tl.add_theme_color_override("font_color", UiTheme.H_WHITE)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tl)
		var sl := Label.new()
		sl.theme = UiTheme.theme()
		sl.text = sub
		sl.add_theme_font_size_override("font_size", 11)
		sl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.68))
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(sl)
		return row

	func _fade_out(row: PanelContainer, dur: float) -> void:
		for i in range(_rows.size() - 1, -1, -1):
			if _rows[i]["panel"] == row:
				_rows.remove_at(i)
				break
		_relayout()
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(row, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(row, "position:x", -18.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(row.queue_free)

	func _relayout() -> void:
		for i in _rows.size():
			var p: PanelContainer = _rows[i]["panel"]
			var target := Vector2(0, i * (ROW_H + SPACING))
			if p.position.distance_to(target) > 0.5:
				var tw := create_tween()
				tw.tween_property(p, "position", target, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ==================== 右下:武器线稿图标(按枪型绘制) ====================
class WeaponIcon extends Control:
	var kind := "rifle"
	var _sup := false

	func _init() -> void:
		custom_minimum_size = Vector2(64, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_weapon(weapon_kind: String, suppressed: bool) -> void:
		self.kind = weapon_kind
		_sup = suppressed
		queue_redraw()

	func _draw() -> void:
		var col := Color(0.88, 0.93, 0.97, 0.85)
		var dim := Color(0.88, 0.93, 0.97, 0.4)
		var w := 1.6
		match kind:
			"smg":
				draw_line(Vector2(12, 24), Vector2(42, 24), col, w)
				draw_line(Vector2(42, 24), Vector2(52, 22), col, w)
				draw_line(Vector2(12, 24), Vector2(10, 18), col, w)
				draw_line(Vector2(20, 25), Vector2(20, 34), col, w)
				draw_line(Vector2(24, 25), Vector2(24, 34), col, w)
			"lmg":
				draw_line(Vector2(8, 22), Vector2(56, 22), col, w)
				draw_line(Vector2(8, 22), Vector2(6, 16), col, w)
				draw_rect(Rect2(22, 22, 8, 14), Color(col.r, col.g, col.b, 0.9), false, 1.2)
				draw_line(Vector2(14, 24), Vector2(14, 31), dim, 1.2)
			"sniper":
				draw_line(Vector2(8, 22), Vector2(56, 22), col, w)
				draw_line(Vector2(8, 22), Vector2(6, 16), col, w)
				draw_arc(Vector2(26, 16), 4.5, 0, TAU, 16, col, 1.2)
				draw_line(Vector2(38, 24), Vector2(42, 31), dim, 1.2)
			"shotgun":
				draw_line(Vector2(10, 24), Vector2(54, 24), col, w)
				draw_line(Vector2(10, 24), Vector2(8, 17), col, w)
				draw_line(Vector2(14, 25), Vector2(14, 32), col, 1.4)
				draw_line(Vector2(22, 25), Vector2(22, 32), col, 1.4)
			"pistol":
				draw_line(Vector2(18, 24), Vector2(40, 24), col, w)
				draw_line(Vector2(18, 24), Vector2(16, 30), col, w)
				draw_line(Vector2(28, 25), Vector2(28, 35), col, w)
			"dmr":
				draw_line(Vector2(10, 22), Vector2(54, 22), col, w)
				draw_line(Vector2(10, 22), Vector2(8, 16), col, w)
				draw_arc(Vector2(24, 15), 3.4, 0, TAU, 14, col, 1.1)
				draw_line(Vector2(36, 24), Vector2(40, 30), dim, 1.2)
			"rpg":
				draw_line(Vector2(8, 22), Vector2(46, 22), col, 3.0)
				draw_line(Vector2(46, 22), Vector2(56, 20), col, 2.6)
				draw_line(Vector2(56, 20), Vector2(56, 24), col, 2.6)
				draw_line(Vector2(56, 24), Vector2(46, 22), col, 2.6)
				draw_line(Vector2(14, 22), Vector2(14, 27), dim, 1.2)
			"melee":
				draw_line(Vector2(18, 30), Vector2(52, 12), col, 2.2)
				draw_line(Vector2(52, 12), Vector2(46, 8), col, 2.2)
				draw_line(Vector2(18, 30), Vector2(14, 33), col, 2.2)
			_:   # rifle 默认
				draw_line(Vector2(8, 22), Vector2(56, 22), col, w)
				draw_line(Vector2(8, 22), Vector2(6, 16), col, w)
				draw_line(Vector2(24, 24), Vector2(24, 33), col, w)
				draw_line(Vector2(28, 24), Vector2(28, 33), col, w)
				draw_line(Vector2(42, 24), Vector2(42, 31), dim, 1.2)
		# 消音器标识(枪口加粗段)
		if _sup:
			draw_line(Vector2(50, 22), Vector2(56, 22), Color(0.16, 0.78, 0.86, 0.8), 3.0)


# ==================== 右下:工具行(投掷物 / 医疗包 / 工具,线稿图标 + 数量) ====================
class ToolsRow extends Control:
	var _items: Array = []       # [{kind, count}]

	func _init() -> void:
		custom_minimum_size = Vector2(0, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_items(items: Array) -> void:
		if _items.size() == items.size():
			var same := true
			for i in _items.size():
				if _items[i]["kind"] != items[i]["kind"] or _items[i]["count"] != items[i]["count"]:
					same = false
					break
			if same:
				return
		_items = items
		queue_redraw()

	func _draw() -> void:
		var x := 0.0
		var y := 14.0
		var f := UiTheme.mono_font()
		for it in _items:
			var kind: String = it["kind"]
			var count: int = it["count"]
			var active: bool = count > 0
			var col := Color(0.72, 0.8, 0.86, 0.95) if active else Color(0.45, 0.5, 0.55, 0.6)
			_draw_icon(kind, Vector2(x + 6, y), col)
			draw_string(f, Vector2(x + 14, y + 4), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			x += 44.0

	func _draw_icon(kind: String, c: Vector2, col: Color) -> void:
		match kind:
			"grenade":     # 手雷:圆 + 引信
				draw_arc(c, 4.0, 0, TAU, 12, col, 1.3)
				draw_line(c + Vector2(0, -4), c + Vector2(0, -7), col, 1.3)
			"at_grenade":  # 反坦克雷:菱形
				var p := PackedVector2Array([c + Vector2(0, -4.6), c + Vector2(4.6, 0), c + Vector2(0, 4.6), c + Vector2(-4.6, 0)])
				draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), col, 1.3)
			"mine":        # 地雷:圆盘 + 中心点
				draw_arc(c, 4.2, 0, TAU, 12, col, 1.3)
				draw_circle(c, 1.2, col)
			"medkit":      # 医疗包:十字
				draw_line(c + Vector2(0, -4), c + Vector2(0, 4), col, 1.5)
				draw_line(c + Vector2(-4, 0), c + Vector2(4, 0), col, 1.5)
			"rpg":         # 火箭:斜管
				draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), col, 1.6)
			"ammo":        # 弹药箱:方盒 + 内条
				draw_rect(Rect2(c - Vector2(4.5, 3.5), Vector2(9, 7)), col, false, 1.3)
				draw_line(c + Vector2(-2.5, -1), c + Vector2(2.5, -1), col, 1.0)
			"sensor":      # 探测器:扇形扫掠
				draw_arc(c, 4.4, -0.9, 0.9, 10, col, 1.3)
				draw_line(c, c + Vector2(0, -4.4), col, 1.0)
			_:             # 工具:扳手(圆 + 柄)
				draw_arc(c, 2.6, 0, TAU, 10, col, 1.3)
				draw_line(c, c + Vector2(3.5, 3.5), col, 1.3)


# ==================== 载具:雷达(敌我点迹 + 扫描线) ====================
class Radar extends Control:
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(88, 88)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		_t += dt
		if _t >= 0.05:
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r, Color(0.03, 0.05, 0.07, 0.55))
		draw_arc(c, r, 0, TAU, 32, Color(0.65, 0.75, 0.8, 0.45), 1.2)
		draw_arc(c, r * 0.62, 0, TAU, 24, Color(0.65, 0.75, 0.8, 0.18), 1.0)
		draw_arc(c, r * 0.3, 0, TAU, 18, Color(0.65, 0.75, 0.8, 0.18), 1.0)
		draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(0.65, 0.75, 0.8, 0.1), 1.0)
		draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0.65, 0.75, 0.8, 0.1), 1.0)
		# 扫描线
		var sweep_a: float = _t * 2.4
		draw_line(c, c + Vector2(cos(sweep_a), sin(sweep_a)) * r, Color(0.16, 0.78, 0.86, 0.14), 1.4)
		var p = G.player
		if p == null or not p.alive:
			return
		var yaw: float = p.vehicle.yaw if p.vehicle != null else p.yaw
		var fx := -sin(yaw)
		var fy := -cos(yaw)
		var rx := -fy
		var ry := fx
		var range_m := 150.0
		var vp: Vector2 = c + Vector2(0, -5)
		var tri := PackedVector2Array([vp + Vector2(0, -5), vp + Vector2(4, 4), vp + Vector2(0, 2), vp + Vector2(-4, 4)])
		draw_colored_polygon(tri, Color(0.16, 0.78, 0.86, 0.95))
		# 敌我点迹
		for b in G.bots:
			if b == null or not b.alive:
				continue
			var d := Vector2(b.pos.x - p.pos.x, b.pos.z - p.pos.z)
			if d.length() > range_m:
				continue
			var sp := c + Vector2(d.x * rx + d.y * fx, d.x * ry + d.y * fy) * (r / range_m)
			if sp.distance_to(c) > r - 2.0:
				continue
			if b.team == p.team:
				draw_circle(sp, 2.0, Color(0.35, 0.8, 0.5, 0.9))
			else:
				draw_circle(sp, 2.0, Color(1.0, 0.55, 0.22, 0.9))
		for v in G.vehicles:
			if v == null or v.dead or v.driver == null:
				continue
			var d := Vector2(v.pos.x - p.pos.x, v.pos.z - p.pos.z)
			if d.length() > range_m:
				continue
			var sp := c + Vector2(d.x * rx + d.y * fx, d.x * ry + d.y * fy) * (r / range_m)
			var vcol: Color = Color(0.35, 0.8, 0.5) if v.driver.team == p.team else Color(1.0, 0.55, 0.22)
			draw_rect(Rect2(sp - Vector2(2.5, 2.5), Vector2(5, 5)), vcol, false, 1.3)
		for a in G.aircraft:
			if a == null or a.dead or a.team == p.team:
				continue
			var d := Vector2(a.pos.x - p.pos.x, a.pos.z - p.pos.z)
			if d.length() > range_m:
				continue
			var sp := c + Vector2(d.x * rx + d.y * fx, d.x * ry + d.y * fy) * (r / range_m)
			var tri2 := PackedVector2Array([sp + Vector2(0, -3.4), sp + Vector2(3.4, 2.4), sp + Vector2(-3.4, 2.4)])
			draw_colored_polygon(tri2, Color(1.0, 0.55, 0.22, 0.9))


# ==================== 载具:指南针条带 ====================
class CompassStrip extends Control:
	var heading := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(150, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_heading(deg: float) -> void:
		if absf(heading - deg) > 0.5:
			heading = deg
			queue_redraw()

	func _draw() -> void:
		var f := UiTheme.mono_font()
		var w := size.x
		var h := size.y
		for off in range(-90, 91, 15):
			var deg := wrapf(heading + float(off), 0.0, 360.0)
			var major := absf(fmod(deg, 90.0)) < 0.1
			var px := w / 2.0 + float(off) / 90.0 * (w / 2.0 - 8.0)
			var col := Color(0.75, 0.84, 0.9, 0.85) if major else Color(0.5, 0.58, 0.65, 0.5)
			draw_line(Vector2(px, h - 8), Vector2(px, h - 8 + (6.0 if major else 3.5)), col, 1.1)
			if major:
				var dirs := ["N", "E", "S", "W"]
				var label: String = dirs[int(round(deg / 90.0)) % 4]
				draw_string(f, Vector2(px - 6, h - 14), label, HORIZONTAL_ALIGNMENT_CENTER, 12, 9,
					Color(0.95, 0.4, 0.35) if label == "N" else col)
		# 中心指针
		draw_line(Vector2(w / 2, 1), Vector2(w / 2, h - 2), Color(0.16, 0.78, 0.86, 0.9), 1.6)


# ==================== 世界空间指示器(据点悬浮 UI / 队友头顶 / 敌人标记) ====================
class WorldOverlay extends Control:
	var _redraw_t := 0.0

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		_redraw_t -= dt
		if _redraw_t <= 0.0:
			_redraw_t = 0.033    # ~30Hz 重绘,减少标记跳变
			queue_redraw()

	func _draw() -> void:
		if not is_visible_in_tree():
			return
		var cam: Camera3D = G.camera
		var p = G.player
		if cam == null or p == null or not p.alive or G.state != "playing":
			return
		_draw_flags(cam)
		_draw_teammates(cam, p)
		_draw_enemies(cam, p)

	func _occluded(_cam: Camera3D, from: Vector3, wpos: Vector3, dist: float) -> bool:
		if dist < 1.5:
			return false
		var hit = Utils.raycast_world(from, (wpos - from) / dist, dist - 0.5)
		return hit != null

	# ---- 据点悬浮 UI:字母 + 名称 + 占领进度 + 距离;距离越远越小,底部圆环 灰→蓝绿 ----
	func _draw_flags(cam: Camera3D) -> void:
		if G.mode == "br":
			return
		var cpos: Vector3 = cam.global_position
		for f in G.flags:
			if f == null:
				continue
			var dist: float = cpos.distance_to(f.pos)
			if dist > 430.0:
				continue
			var wpos: Vector3 = f.pos + Vector3(0, 6.6, 0)
			if cam.is_position_behind(wpos):
				continue
			var sp: Vector2 = cam.unproject_position(wpos)
			if not Rect2(Vector2.ZERO, size).grow(-12.0).has_point(sp):
				continue
			var s: float = clampf(1.4 - dist * 0.0032, 0.5, 1.4)
			var alpha: float = clampf(1.1 - dist / 400.0, 0.12, 1.0)
			if _occluded(cam, cpos, wpos, dist):
				alpha *= 0.4
			var fc: Color
			if f.owner_team != null and f.owner_team == G.player.team:
				fc = Color(0.72, 0.94, 0.98)
			elif f.owner_team != null:
				fc = Color(1.0, 0.8, 0.62)
			else:
				fc = Color(0.75, 0.8, 0.85)
			# 字母(大字)
			draw_string(UiTheme.mono_font(), sp + Vector2(-40 * s, 12 * s), f.id,
				HORIZONTAL_ALIGNMENT_CENTER, 80 * s, int(round(26 * s)), fc)
			# 名称
			var fname: String = HUD.FLAG_NAMES.get(f.id, f.id + " 据点")
			draw_string(UiTheme.font(), sp + Vector2(-60 * s, 27 * s), fname,
				HORIZONTAL_ALIGNMENT_CENTER, 120 * s, int(round(12 * s)), Color(0.72, 0.8, 0.86, alpha))
			# 距离
			draw_string(UiTheme.mono_font(), sp + Vector2(-30 * s, 42 * s), str(int(round(dist))) + "m",
				HORIZONTAL_ALIGNMENT_CENTER, 60 * s, int(round(10 * s)), Color(0.55, 0.62, 0.68, alpha))
			# 占领进度:底部半环(灰底 → 蓝绿/橙 填充)
			var frac := clampf((f.progress + 100.0) / 200.0, 0.0, 1.0)
			if frac > 0.01 and frac < 0.999:
				var r: float = 11.0 * s
				var base := Color(0.45, 0.5, 0.55, 0.35 * alpha)
				var fill := UiTheme.H_TEAL if f.progress >= 0.0 else UiTheme.H_ORANGE
				draw_arc(sp + Vector2(0, 44 * s), r, PI, TAU, 22, base, 2.4)
				draw_arc(sp + Vector2(0, 44 * s), r, PI, PI + frac * PI, 22,
					Color(fill.r, fill.g, fill.b, 0.9 * alpha), 2.6)

	# ---- 队友头顶:名字 + 职业图标 + 距离 + 血量;仅玩家小队成员 ----
	# 遮挡降透明;倒地变红
	func _is_squad_mate(b) -> bool:
		if b == null:
			return false
		if G.mode == "br":
			return b.get("squad_id") == GameMode_BR.BR_PLAYER_SQUAD
		if G.mode == "campaign":
			return b.get("follow") != null
		var sq = G.player_squad
		if sq == null:
			return false
		return (sq.get("members", []) as Array).has(b)

	func _draw_teammates(cam: Camera3D, p) -> void:
		var cpos: Vector3 = cam.global_position
		for b in G.bots:
			if b == null or not b.alive or b.team != p.team:
				continue
			if not _is_squad_mate(b):
				continue
			var wpos: Vector3 = b.pos + Vector3(0, 2.2, 0)
			var dist: float = cpos.distance_to(wpos)
			if dist > 90.0:
				continue
			var alpha: float = clampf(1.0 - dist / 90.0, 0.0, 1.0)
			if alpha <= 0.02:
				continue
			if cam.is_position_behind(wpos):
				continue
			var sp: Vector2 = cam.unproject_position(wpos)
			if not Rect2(Vector2.ZERO, size).grow(-20.0).has_point(sp):
				continue
			if _occluded(cam, cpos, wpos, dist):
				alpha *= 0.35
			var downed: bool = b.downed
			# 背景条
			var bw := 78.0
			var bh := 26.0
			var tl := sp + Vector2(-bw / 2.0, -bh - 6.0)
			var bcol := UiTheme.H_RED if downed else UiTheme.H_GREEN
			draw_rect(Rect2(tl, Vector2(bw, bh)), Color(0.02, 0.03, 0.05, 0.55 * alpha))
			draw_rect(Rect2(tl, Vector2(bw, bh)), Color(bcol.r, bcol.g, bcol.b, 0.55 * alpha), false, 1.0)
			# 职业图标(单字)
			var cls = WeaponsData.C().get(b.class_id)
			var icon_ch: String = cls.icon if cls != null else "兵"
			var cls_col: Color = cls.color if cls != null else UiTheme.H_GREEN
			if downed:
				cls_col = UiTheme.H_RED
			draw_string(UiTheme.font(), tl + Vector2(4, 15), icon_ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(cls_col.r, cls_col.g, cls_col.b, alpha))
			# 名字 / 倒地状态
			var name_col: Color
			var name_txt: String
			if downed:
				name_txt = "倒地 · 可救治"
				name_col = Color(1.0, 0.55, 0.4, alpha)
			else:
				name_txt = Bot.display_name(b)
				name_col = Color(0.85, 0.92, 0.95, alpha)
			draw_string(UiTheme.font(), tl + Vector2(19, 14), name_txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, name_col)
			# 距离(右对齐)
			draw_string(UiTheme.mono_font(), tl + Vector2(bw - 34, 14), str(int(round(dist))) + "m",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.62, 0.68, alpha))
			# 血量条(倒地→红)
			if not downed:
				var hp_frac: float = clampf(b.health / 100.0, 0.0, 1.0)
				var bar_tl := tl + Vector2(19, 19)
				var bar_sz := Vector2(bw - 38, 3)
				draw_rect(Rect2(bar_tl, bar_sz), Color(0.2, 0.24, 0.28, 0.8 * alpha))
				var hp_col := Color(0.35, 0.8, 0.5) if hp_frac > 0.35 else Color(0.95, 0.34, 0.28)
				draw_rect(Rect2(bar_tl, Vector2(bar_sz.x * hp_frac, bar_sz.y)), Color(hp_col.r, hp_col.g, hp_col.b, alpha))

	# ---- 敌人标记:仅侦察 / 标记 / 瞄准镜识别;红菱形 + 距离 + 名字,无血条 ----
	func _draw_enemies(cam: Camera3D, p) -> void:
		var cpos: Vector3 = cam.global_position
		var gun = p.gun()
		var scoped: bool = gun != null and gun.def.scope and gun.ads_amount > 0.7
		var fwd: Vector3 = -cam.global_transform.basis.z
		for b in G.bots:
			if b == null or not b.alive or b.team == p.team:
				continue
			var dist: float = cpos.distance_to(b.pos)
			if dist > 320.0:
				continue
			var vis: bool = b.spotted > 0.0
			if not vis and scoped and dist < 170.0:
				var to: Vector3 = (b.pos - cpos).normalized()
				if to.angle_to(fwd) < deg_to_rad(7.0):
					vis = true
			if not vis:
				continue
			var wpos: Vector3 = b.pos + Vector3(0, 2.15, 0)
			if cam.is_position_behind(wpos):
				continue
			var sp: Vector2 = cam.unproject_position(wpos)
			if not Rect2(Vector2.ZERO, size).grow(-16.0).has_point(sp):
				continue
			var s: float = clampf(1.0 - dist / 320.0, 0.55, 1.0)
			var alpha: float = clampf(1.1 - dist / 320.0, 0.15, 1.0)
			if _occluded(cam, cpos, wpos, dist):
				alpha *= 0.5
			_draw_enemy_marker(sp, s, alpha, dist, Bot.display_name(b))
		# 敌方载具(有驾驶员且被侦察)
		for v in G.vehicles:
			if v == null or v.dead or v.driver == null or v.driver.team == p.team:
				continue
			if v.driver.spotted <= 0.0:
				continue
			var wpos: Vector3 = v.pos + Vector3(0, 2.6, 0)
			var dist: float = cpos.distance_to(wpos)
			if dist > 320.0 or cam.is_position_behind(wpos):
				continue
			var sp: Vector2 = cam.unproject_position(wpos)
			if not Rect2(Vector2.ZERO, size).grow(-16.0).has_point(sp):
				continue
			var s: float = clampf(1.0 - dist / 320.0, 0.55, 1.0)
			var alpha: float = clampf(1.1 - dist / 320.0, 0.15, 1.0)
			var vname: String = str(v.def.get("vehicle_name", "载具"))
			_draw_enemy_marker(sp, s, alpha, dist, vname)
		# 敌方飞机(被锁定/瞄准镜内可见)
		for a in G.aircraft:
			if a == null or a.dead or a.team == p.team:
				continue
			var dist: float = cpos.distance_to(a.pos)
			if dist > 600.0:
				continue
			var vis: bool = G.lock_target == a
			if not vis and scoped and dist < 400.0:
				var to: Vector3 = (a.pos - cpos).normalized()
				if to.angle_to(fwd) < deg_to_rad(7.0):
					vis = true
			if not vis:
				continue
			var wpos: Vector3 = a.pos + Vector3(0, 1.5, 0)
			if cam.is_position_behind(wpos):
				continue
			var sp: Vector2 = cam.unproject_position(wpos)
			if not Rect2(Vector2.ZERO, size).grow(-16.0).has_point(sp):
				continue
			var s: float = clampf(1.0 - dist / 600.0, 0.5, 1.0)
			var alpha: float = clampf(1.1 - dist / 600.0, 0.15, 1.0)
			_draw_enemy_marker(sp, s, alpha, dist, a.craft_name)

	func _draw_enemy_marker(sp: Vector2, s: float, alpha: float, dist: float, label_text: String) -> void:
		var col := Color(1.0, 0.55, 0.22, alpha)
		var r: float = 6.0 * s
		var pts := PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(1.0, 0.4, 0.16, 0.3 * alpha))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.4)
		draw_string(UiTheme.mono_font(), sp + Vector2(-24 * s, r + 13 * s), str(int(round(dist))) + "m",
			HORIZONTAL_ALIGNMENT_CENTER, 48 * s, int(round(10 * s)), Color(1.0, 0.72, 0.55, alpha))
		draw_string(UiTheme.font(), sp + Vector2(-40 * s, r + 26 * s), label_text,
			HORIZONTAL_ALIGNMENT_CENTER, 80 * s, int(round(11 * s)), Color(1.0, 0.62, 0.4, alpha))


# ==================== 实时战场部署观察层(3D 世界空间战术标记 + 准星 + 操作提示) ====================
class DeploymentOverlay extends Control:
	var _t := 0.0
	var _redraw_t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		_redraw_t -= dt
		if _redraw_t <= 0.0:
			_redraw_t = 0.04    # ~25Hz 重绘,标记平滑且省开销
			queue_redraw()

	func _occluded(_cam: Camera3D, from: Vector3, wpos: Vector3, dist: float) -> bool:
		if dist < 2.0 or dist > 220.0:
			return false
		var hit = Utils.raycast_world(from, (wpos - from) / dist, dist - 0.5)
		return hit != null

	func _draw() -> void:
		if not is_visible_in_tree():
			return
		var dep = G.deployment
		if dep == null or not dep.active or G.camera == null:
			return
		var cam: Camera3D = G.camera
		var p = G.player
		if p == null:
			return
		var cpos: Vector3 = cam.global_position
		var center: Vector2 = size * 0.5
		var hovered: Dictionary = dep.hovered
		# 世界空间标记:队友 / 旗帜 / 信标 / 载具 / 基地
		for t in dep.observer.collect():
			if cam.is_position_behind(t["pos"]):
				continue
			var sp: Vector2 = cam.unproject_position(t["pos"])
			var dist: float = cpos.distance_to(t["pos"])
			if sp.x < -40 or sp.x > size.x + 40 or sp.y < -40 or sp.y > size.y + 40 or dist > 600.0:
				continue
			var s: float = clampf(1.5 - dist * 0.0028, 0.5, 1.5)
			var alpha: float = clampf(1.15 - dist / 550.0, 0.15, 1.0)
			if _occluded(cam, cpos, t["pos"], dist):
				alpha *= 0.5
			var is_hover: bool = not hovered.is_empty() and hovered.get("ref") == t.get("ref") \
				and hovered.get("kind") == t.get("kind")
			match t["kind"]:
				"mate":
					_draw_mate_marker(sp, s, alpha, t, is_hover)
				"flag":
					_draw_flag_marker(sp, s, alpha, t, is_hover)
				"beacon":
					_draw_beacon_marker(sp, s, alpha, t, is_hover)
				"vehicle":
					_draw_vehicle_marker(sp, s, alpha, t, is_hover)
				"base":
					_draw_base_marker(sp, s, alpha, t, is_hover)
		# 侦察规则敌人:仅已标记/暴露者显示,标记随时间淡出
		_draw_spotted_enemies(cam, p, center)
		# 顶部操作提示(底部为同屏兵种/武器栏,提示条置顶)
		var hint := "左键拖动地图 · 点击部署点部署 · 空格部署基地 · WASD 平移"
		if not hovered.is_empty() and bool(hovered.get("valid", false)):
			hint = "点击部署: " + str(hovered.get("label", "部署点")) + " · 空格部署基地 · 拖动地图观察"
		var f := UiTheme.mono_font()
		var bar_w := 680.0
		var bar_rect := Rect2(center.x - bar_w / 2.0, 64.0, bar_w, 30.0)
		draw_rect(bar_rect.grow(1.0), Color(0, 0, 0, 0.4))
		draw_rect(bar_rect, Color(0.06, 0.09, 0.11, 0.5), false, 1.0)
		draw_string(f, bar_rect.position + Vector2(0, 21), hint,
			HORIZONTAL_ALIGNMENT_CENTER, bar_w, 14, Color(0.72, 0.94, 0.98, 0.92))

	func _ring(sp: Vector2, r: float, col: Color, width := 2.2, pulse := 0.0) -> void:
		var pr := r + sin(_t * 5.0 + pulse) * 1.5
		draw_arc(sp, pr, 0, TAU, 32, col, width)

	func _marker_hover(sp: Vector2, s: float, col: Color, r: float) -> void:
		# 悬停:白亮外环 + 呼吸脉冲
		_ring(sp, r + 7.0 * s, Color(1, 1, 1, 0.95), 2.6, sp.x)
		draw_arc(sp, r + 3.0 * s, 0, TAU, 32, Color(col.r, col.g, col.b, 0.9), 1.6)

	func _draw_mate_marker(sp: Vector2, s: float, alpha: float, t: Dictionary, is_hover: bool) -> void:
		var col: Color
		var status := ""
		if bool(t.get("downed", false)):
			col = Color(0.95, 0.34, 0.28, 0.55 * alpha)   # 倒地:暗红
			status = "倒地"
		elif bool(t.get("in_vehicle", false)):
			col = Color(0.55, 0.62, 0.68, 0.5 * alpha)    # 载具中:灰
			status = "载具中"
		elif bool(t.get("danger", false)):
			col = Color(1.0, 0.85, 0.2, 0.6 * alpha)      # 危险区域:黄
			status = "危险区域"
		elif bool(t.get("squad", false)):
			col = Color(0.0, 1.0, 0.53, 0.95 * alpha)     # 小队成员:亮绿
		else:
			col = Color(0.35, 0.8, 0.5, 0.75 * alpha)     # 其他队友:绿
		var r: float = 6.0 * s if bool(t.get("squad", false)) else 4.5 * s
		var pts := PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, col.a * 0.35))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.5)
		if bool(t.get("squad", false)) and not bool(t.get("downed", false)):
			draw_arc(sp, r + 2.0 * s, 0, TAU, 24, Color(0.0, 1.0, 0.53, 0.4 * alpha), 1.2)
		if is_hover and bool(t.get("valid", false)):
			_marker_hover(sp, s, Color(0.0, 1.0, 0.53), r)
		# 名字 + 状态
		var label: String = str(t.get("label", "")) + ((" · " + status) if status != "" else "")
		draw_string(UiTheme.font(), sp + Vector2(-50 * s, r + 18 * s), label,
			HORIZONTAL_ALIGNMENT_CENTER, 100 * s, int(round(11 * s)), Color(col.r, col.g, col.b, col.a))

	func _draw_flag_marker(sp: Vector2, s: float, alpha: float, t: Dictionary, is_hover: bool) -> void:
		var bc: Color
		var fc: Color
		match t.get("state", "neutral"):
			"mine":
				bc = UiTheme.H_CYAN
				fc = Color(0.72, 0.94, 0.98)
			"enemy":
				bc = UiTheme.H_ORANGE
				fc = Color(1.0, 0.8, 0.62)
			_:
				bc = Color(0.55, 0.6, 0.66, 0.75 * alpha) if bool(t.get("locked", false)) else UiTheme.H_GRAY
				fc = Color(0.75, 0.8, 0.85)
		if bool(t.get("contested", false)):
			var pu := 0.5 + 0.5 * sin(_t * 8.0)
			bc = Color(0.95, 0.34, 0.28, 0.5 + 0.5 * pu)
		var r: float = 10.0 * s
		draw_circle(sp, r, Color(bc.r, bc.g, bc.b, 0.18 * alpha))
		draw_arc(sp, r, 0, TAU, 28, Color(bc.r, bc.g, bc.b, 0.9 * alpha), 1.8)
		# 字母 + 名称
		var fid: String = str(t.get("label", "")).split(" ")[0]
		draw_string(UiTheme.mono_font(), sp + Vector2(-20 * s, 5 * s), fid,
			HORIZONTAL_ALIGNMENT_CENTER, 40 * s, int(round(20 * s)), fc)
		draw_string(UiTheme.font(), sp + Vector2(-60 * s, 20 * s), str(t.get("label", "")),
			HORIZONTAL_ALIGNMENT_CENTER, 120 * s, int(round(11 * s)), Color(0.72, 0.8, 0.86, alpha))
		# 占领进度弧(灰 → 蓝绿/橙)
		var frac := clampf((float(t.get("progress", 0.0)) + 100.0) / 200.0, 0.0, 1.0)
		if frac > 0.01 and frac < 0.999:
			var fill := UiTheme.H_TEAL if float(t.get("progress", 0.0)) >= 0.0 else UiTheme.H_ORANGE
			draw_arc(sp + Vector2(0, 4 * s), r, PI, TAU, 22, Color(0.45, 0.5, 0.55, 0.4 * alpha), 2.0)
			draw_arc(sp + Vector2(0, 4 * s), r, PI, PI + frac * PI, 22, Color(fill.r, fill.g, fill.b, 0.95 * alpha), 2.2)
		if is_hover and bool(t.get("valid", false)):
			_marker_hover(sp, s, UiTheme.H_CYAN, r)
		elif bool(t.get("locked", false)):
			draw_string(UiTheme.font(), sp + Vector2(-30 * s, 34 * s), "未解锁",
				HORIZONTAL_ALIGNMENT_CENTER, 60 * s, int(round(10 * s)), Color(0.62, 0.66, 0.7, alpha))

	func _draw_beacon_marker(sp: Vector2, s: float, alpha: float, _entry: Dictionary, is_hover: bool) -> void:
		var col := Color(0.0, 1.0, 0.53, 0.9 * alpha)
		var r: float = 6.0 * s
		var pts := PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.3 * alpha))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.6)
		if is_hover:
			_marker_hover(sp, s, col, r)
		draw_string(UiTheme.font(), sp + Vector2(-50 * s, r + 18 * s), "重生信标",
			HORIZONTAL_ALIGNMENT_CENTER, 100 * s, int(round(11 * s)), Color(col.r, col.g, col.b, alpha))

	func _draw_vehicle_marker(sp: Vector2, s: float, alpha: float, t: Dictionary, is_hover: bool) -> void:
		var col := Color(0.16, 0.78, 0.86, 0.9 * alpha)
		var r := 5.0 * s
		var rect := Rect2(sp - Vector2(r, r), Vector2(r * 2, r * 2))
		draw_rect(rect, Color(col.r, col.g, col.b, 0.25), true)
		draw_rect(rect, col, false, 1.6)
		if is_hover:
			_marker_hover(sp, s, col, r)
		draw_string(UiTheme.font(), sp + Vector2(-60 * s, r + 16 * s), str(t.get("label", "载具")),
			HORIZONTAL_ALIGNMENT_CENTER, 120 * s, int(round(11 * s)), Color(col.r, col.g, col.b, alpha))

	func _draw_base_marker(sp: Vector2, s: float, alpha: float, _entry: Dictionary, is_hover: bool) -> void:
		var col := Color(0.0, 1.0, 0.53, 0.95 * alpha)
		var r: float = 9.0 * s
		draw_arc(sp, r, 0, TAU, 32, col, 2.0)
		draw_arc(sp, r * 0.55, 0, TAU, 24, col, 1.4)
		if is_hover:
			_marker_hover(sp, s, col, r)
		draw_string(UiTheme.font(), sp + Vector2(-40 * s, r + 16 * s), "基地",
			HORIZONTAL_ALIGNMENT_CENTER, 80 * s, int(round(11 * s)), Color(col.r, col.g, col.b, alpha))

	## 侦察规则敌人:仅被标记(b.spotted)或暴露位置者显示,标记渐隐(信息不确定性)
	func _draw_spotted_enemies(cam: Camera3D, p, _center: Vector2) -> void:
		var cpos: Vector3 = cam.global_position
		for b in G.bots:
			if b == null or not b.alive or b.team == p.team:
				continue
			if b.spotted <= 0.0:
				continue
			var wpos: Vector3 = b.pos + Vector3(0, 1.9, 0)
			if cam.is_position_behind(wpos):
				continue
			var dist: float = cpos.distance_to(wpos)
			if dist > 450.0:
				continue
			var sp: Vector2 = cam.unproject_position(wpos)
			if sp.x < -30 or sp.x > size.x + 30 or sp.y < -30 or sp.y > size.y + 30:
				continue
			var alpha: float = clampf(0.35 + b.spotted / 8.0 * 0.65, 0.15, 1.0)
			if dist > 200.0:
				alpha *= 0.7
			var s: float = clampf(1.2 - dist * 0.002, 0.5, 1.2)
			var col := Color(1.0, 0.4, 0.16, alpha)
			var r: float = 5.5 * s
			var pts := PackedVector2Array([
				sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.28))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.5)
			draw_string(UiTheme.mono_font(), sp + Vector2(-26 * s, r + 14 * s), str(int(round(dist))) + "m",
				HORIZONTAL_ALIGNMENT_CENTER, 52 * s, int(round(10 * s)), Color(1.0, 0.72, 0.55, alpha))
		# 敌方有人载具(驾驶员被标记才显示)
		for v in G.vehicles:
			if v == null or v.dead or v.driver == null or v.driver.team == p.team or v.driver.spotted <= 0.0:
				continue
			var wpos2: Vector3 = v.pos + Vector3(0, 2.4, 0)
			if cam.is_position_behind(wpos2):
				continue
			var dist2: float = cpos.distance_to(wpos2)
			if dist2 > 450.0:
				continue
			var sp2: Vector2 = cam.unproject_position(wpos2)
			if sp2.x < -30 or sp2.x > size.x + 30 or sp2.y < -30 or sp2.y > size.y + 30:
				continue
			var alpha2: float = clampf(0.35 + v.driver.spotted / 8.0 * 0.65, 0.15, 1.0)
			var r2 := 5.0
			var rect := Rect2(sp2 - Vector2(r2, r2), Vector2(r2 * 2, r2 * 2))
			draw_rect(rect, Color(1.0, 0.45, 0.2, alpha2), false, 1.6)


# ==================== 夜视仪敌人高亮(全屏标记,穿墙可见) ====================
class NightVisionOverlay extends Control:
	func _process(_dt: float) -> void:
		var on: bool = G.player != null and G.player.alive and G.player.night_vision and G.state == "playing"
		if visible != on:
			visible = on
		if on:
			queue_redraw()

	func _draw() -> void:
		if not is_visible_in_tree():
			return
		var cam: Camera3D = G.camera
		var p = G.player
		if cam == null or p == null:
			return
		var vr: Rect2 = Rect2(Vector2.ZERO, size)
		var cpos: Vector3 = cam.global_position
		for b in G.bots:
			if b == null or not b.alive or b.team == p.team:
				continue
			_draw_marker(cam, cpos, Vector3(b.pos.x, b.pos.y + 1.4, b.pos.z), vr)
		for v in G.vehicles:
			if v == null or v.dead or v.driver == null or v.driver.team == p.team:
				continue
			_draw_marker(cam, cpos, Vector3(v.pos.x, v.pos.y + 1.8, v.pos.z), vr)
		for a in G.aircraft:
			if a == null or a.dead or a.team == p.team:
				continue
			_draw_marker(cam, cpos, a.pos, vr)

	func _draw_marker(cam: Camera3D, cpos: Vector3, wpos: Vector3, vr: Rect2) -> void:
		if cam.is_position_behind(wpos):
			return
		var sp: Vector2 = cam.unproject_position(wpos)
		if not vr.grow(-8.0).has_point(sp):
			return
		var to: Vector3 = wpos - cpos
		var dist: float = to.length()
		if dist > 450.0:
			return
		var alpha := 1.0
		if dist > 1.0:
			var hit = Utils.raycast_world(cpos, to / dist, dist - 0.4)
			if hit != null:
				alpha = 0.45
		var s := clampf(14.0 - dist * 0.02, 4.0, 14.0)
		var fill := Color(0.35, 1.0, 0.45, alpha)
		var out := Color(0.9, 1, 0.95, alpha)
		var pts := PackedVector2Array([
			sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0)])
		draw_colored_polygon(pts, fill)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), out, 1.6)
		var dist_txt: String = str(int(round(dist))) + "m"
		draw_string(UiTheme.mono_font(), sp + Vector2(-20, s + 13), dist_txt,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.75, 1, 0.8, alpha))


# ==================== 载具瞄准辅助(炮塔类:主准星 + 炮管指向指示点;仅炮手位显示) ====================
class VehicleAim extends Control:
	func _process(_dt: float) -> void:
		var vis: bool = G.player != null and G.player.alive and G.player.vehicle != null \
			and G.player.vehicle.has_turret() and G.player._veh_crew == 1 and G.state == "playing"
		if visible != vis:
			visible = vis
		if vis:
			queue_redraw()

	func _draw() -> void:
		if not is_visible_in_tree():
			return
		var p = G.player
		var v = p.vehicle
		if v == null or not v.has_turret() or G.camera == null:
			return
		var center := size / 2.0
		var md: Array = v.muzzle_world()
		var pt: Vector3 = md[0] + (md[1] as Vector3) * 40.0
		var sp: Vector2 = G.camera.unproject_position(pt)
		var aligned: bool = not G.camera.is_position_behind(pt) and sp.distance_to(center) < 80.0
		if G.camera.is_position_behind(pt):
			var dirv: Vector3 = md[1] as Vector3
			var cb := G.camera.global_transform.basis
			var d2 := Vector2(dirv.dot(cb.x), -dirv.dot(cb.y)).normalized()
			if d2.length() < 0.01:
				d2 = Vector2(0, -1)
			sp = center + d2 * (minf(size.x, size.y) * 0.5 - 28.0)
			aligned = false
		elif sp.x < 10 or sp.x > size.x - 10 or sp.y < 10 or sp.y > size.y - 10:
			var d3: Vector2 = sp - center
			if d3.length() < 1.0:
				d3 = Vector2(0, -1)
			sp = center + d3.normalized() * (minf(size.x, size.y) * 0.5 - 28.0)
			aligned = false
		var dcol := Color(1.0, 0.72, 0.35)
		var ds := 7.0
		var pts := PackedVector2Array([
			sp + Vector2(0, -ds), sp + Vector2(ds, 0), sp + Vector2(0, ds), sp + Vector2(-ds, 0)])
		draw_colored_polygon(pts, Color(dcol.r, dcol.g, dcol.b, 0.3 if aligned else 0.85))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), dcol, 1.5)
		if not aligned:
			draw_line(center, sp, Color(1.0, 0.72, 0.35, 0.35), 1.0)
			draw_string(UiTheme.mono_font(), sp + Vector2(-18, -12), "转炮",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 13, dcol)
		var col := Color(1.0, 0.34, 0.28) if aligned else Color(0.82, 0.9, 0.95, 0.9)
		var gap := 6.0
		var L := 12.0
		draw_line(center + Vector2(0, -gap - L), center + Vector2(0, -gap), col, 2)
		draw_line(center + Vector2(0, gap), center + Vector2(0, gap + L), col, 2)
		draw_line(center + Vector2(-gap - L, 0), center + Vector2(-gap, 0), col, 2)
		draw_line(center + Vector2(gap, 0), center + Vector2(gap + L, 0), col, 2)
		draw_arc(center, 16.0, 0, TAU, 32, Color(col.r, col.g, col.b, col.a * 0.8), 1.5)
		if aligned:
			draw_circle(center, 2.2, col)


# ==================== 狙击镜(优化版:渐变暗角 + 镜筒内环 + 精细分划) ====================
class ScopeOverlay extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.42
		# 四周径向渐变暗角(替代硬边矩形:内圈透明 → 外圈全黑)
		# 注意:必须用圆环(draw_arc),不能用 draw_circle 填充圆——后者会一层层盖黑中央镜内画面。
		var steps := 14
		var ring_w: float = maxf(2.0, r * 0.045)
		for i in steps:
			var rr: float = r * (1.0 + (float(i) + 0.5) / float(steps) * 0.55)
			var a: float = pow((float(i) + 0.5) / float(steps), 1.6) * 1.0
			draw_arc(c, rr, 0, TAU, 96, Color(0, 0, 0, a * 0.55), ring_w)
			# 用弧形挖出中央圆窗
		# 精确遮罩:中央圆外全黑(圆环填充)
		var mask := 64
		var pts := PackedVector2Array()
		for i in mask + 1:
			var ang := TAU * i / mask
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		# 外部四个区域填充(圆窗外的黑色区域)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, c.y - r), Vector2(0, c.y - r)]), Color(0, 0, 0, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(0, c.y + r), Vector2(size.x, c.y + r), Vector2(size.x, size.y), Vector2(0, size.y)]), Color(0, 0, 0, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(0, c.y - r), Vector2(c.x - r, c.y - r), Vector2(c.x - r, c.y + r), Vector2(0, c.y + r)]), Color(0, 0, 0, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(c.x + r, c.y - r), Vector2(size.x, c.y - r), Vector2(size.x, c.y + r), Vector2(c.x + r, c.y + r)]), Color(0, 0, 0, 1))
		# 圆窗外沿柔边(渐变环)
		for i in 12:
			var rr2: float = r + (i + 1) * r * 0.035
			draw_arc(c, rr2, 0, TAU, 96, Color(0, 0, 0, 0.85 * (1.0 - float(i) / 12.0)), r * 0.03)
		# 镜筒结构:外筒暗环 + 内沿亮环
		draw_arc(c, r * 1.02, 0, TAU, 96, Color(0.03, 0.03, 0.03, 1), r * 0.045)
		draw_arc(c, r * 0.985, 0, TAU, 96, Color(0.16, 0.17, 0.19, 0.9), 2.5)
		draw_arc(c, r * 0.955, 0, TAU, 96, Color(0.02, 0.02, 0.02, 0.92), 3.0)
		draw_arc(c, r * 0.93, 0, TAU, 96, Color(0, 0, 0, 0.35), 1.2)
		# 镜内暗角渐变(内圈边缘微暗)
		for i in 10:
			var rr3: float = r * (0.93 - i * 0.03)
			draw_arc(c, rr3, 0, TAU, 96, Color(0, 0, 0, 0.05 * (10 - i) / 10.0), 1.0)
		# 十字分划(细亮线,中心隙)
		var col := Color(0.03, 0.03, 0.03, 0.9)
		var col2 := Color(0.55, 0.58, 0.62, 0.7)
		draw_line(c + Vector2(-r * 0.94, 0), c + Vector2(-10, 0), col, 1.4)
		draw_line(c + Vector2(10, 0), c + Vector2(r * 0.94, 0), col, 1.4)
		draw_line(c + Vector2(0, -r * 0.94), c + Vector2(0, -10), col, 1.4)
		draw_line(c + Vector2(0, 10), c + Vector2(0, r * 0.94), col, 1.4)
		# 密位刻度(横/纵,长短交替)
		for i in range(-6, 7):
			if i == 0:
				continue
			var off: float = i * r / 7.0
			var half: float = 6.0 if absi(i) % 2 == 1 else 3.5
			draw_line(c + Vector2(off, -half), c + Vector2(off, half), col2, 1.0)
			draw_line(c + Vector2(-half, off), c + Vector2(half, off), col2, 1.0)
		# 中心十字尖 + 中心点
		var cs := 5.0
		draw_line(c + Vector2(-cs, 0), c + Vector2(cs, 0), Color(0.08, 0.08, 0.08, 0.95), 1.0)
		draw_line(c + Vector2(0, -cs), c + Vector2(0, cs), Color(0.08, 0.08, 0.08, 0.95), 1.0)
		draw_circle(c, 1.4, Color(0.1, 0.1, 0.1, 0.9))


# ==================== 伤害方向弧 ====================
class DamageArc extends Control:
	var rel_angle := 0.0
	var arc_opacity := 0.0

	func _draw() -> void:
		if arc_opacity <= 0:
			return
		var c := size / 2.0
		var r := 62.0
		var col := Color(0.95, 0.34, 0.28, arc_opacity)
		var a0 := rel_angle - 0.55
		var a1 := rel_angle + 0.55
		draw_arc(c, r, a0, a1, 12, col, 4)


# ==================== 战役目标指示器(屏幕边缘三角 + 距离) ====================
class CampaignIndicator extends Control:
	var target := Vector3.ZERO
	var show_mark := false
	var dist := 0.0

	func set_target(p: Vector3) -> void:
		target = p
		show_mark = true
		queue_redraw()

	func clear() -> void:
		show_mark = false
		queue_redraw()

	func _draw() -> void:
		if not show_mark or G.camera == null:
			return
		var cam: Camera3D = G.camera
		var col := Color(0.16, 0.78, 0.86)
		var sp: Vector2 = cam.unproject_position(target)
		var center := size / 2.0
		if not cam.is_position_behind(target) and Rect2(Vector2.ZERO, size).grow(-34.0).has_point(sp):
			var d2 := 9.0
			var pts := PackedVector2Array([
				sp + Vector2(0, -d2), sp + Vector2(d2, 0),
				sp + Vector2(0, d2), sp + Vector2(-d2, 0)])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85))
			draw_string(UiTheme.mono_font(), sp + Vector2(-26, d2 + 16), str(int(round(dist))) + "m",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 12, col)
			return
		var dir: Vector2
		if cam.is_position_behind(target):
			var to3: Vector3 = (target - cam.global_position).normalized()
			var cb := cam.global_transform.basis
			dir = Vector2(to3.dot(cb.x), -to3.dot(cb.y)).normalized()
			if dir.length() < 0.01:
				dir = Vector2(0, -1)
		else:
			dir = sp - center
			if dir.length() < 0.01:
				dir = Vector2(0, -1)
			dir = dir.normalized()
		var half := size / 2.0
		var t: float
		if absf(dir.x) > absf(dir.y):
			t = (half.x - 46.0) / absf(dir.x)
		else:
			t = (half.y - 46.0) / absf(dir.y)
		var edge := center + dir * t
		var ang := atan2(dir.y, dir.x)
		var tip := edge + Vector2(cos(ang), sin(ang)) * 16.0
		var perp := Vector2(-sin(ang), cos(ang)) * 8.0
		draw_colored_polygon(PackedVector2Array([tip, edge + perp, edge - perp]),
			Color(col.r, col.g, col.b, 0.92))
		draw_string(UiTheme.mono_font(), edge + Vector2(-24, 27), str(int(round(dist))) + "m",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, col)


# ==================== 大逃杀毒圈指示 ====================
class BrZoneIndicator extends Control:
	var active := false
	var zone_center := Vector3.ZERO
	var zone_radius := 100.0
	var inside := false
	var dist := 0.0
	var _t := 0.0

	func _process(dt: float) -> void:
		if not visible:
			return
		_t += dt
		if _t >= 0.1:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		if not active or G.camera == null or G.player == null:
			return
		var cam: Camera3D = G.camera
		var c := size / 2.0
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var col := Color(1.0, 0.45, 0.2, 0.8 + 0.2 * pulse) if not inside else Color(0.05, 0.62, 0.6, 0.85)
		var sp: Vector2 = cam.unproject_position(zone_center)
		var behind: bool = cam.is_position_behind(zone_center)
		var on_screen: bool = not behind and Rect2(Vector2.ZERO, size).grow(-60.0).has_point(sp)
		if on_screen:
			var to: Vector3 = zone_center - cam.global_position
			var d3: float = to.length()
			if d3 > 1.0:
				var ang := atan2(zone_radius, d3)
				var rad_px := tan(ang) * (get_viewport().get_visible_rect().size.y * 0.5) / maxf(tan(deg_to_rad(cam.fov) * 0.5), 0.001)
				draw_arc(sp, clampf(rad_px, 6.0, 3000.0), 0, TAU, 60, Color(col.r, col.g, col.b, 0.5), 1.6)
			draw_arc(sp, 7.0, 0, TAU, 24, col, 2.0)
			draw_string(UiTheme.mono_font(), sp + Vector2(-60, 26), _label(), HORIZONTAL_ALIGNMENT_CENTER, 120, 13, col)
			return
		var dir: Vector2
		if behind:
			var to3: Vector3 = (zone_center - cam.global_position).normalized()
			var cb := cam.global_transform.basis
			dir = Vector2(to3.dot(cb.x), -to3.dot(cb.y)).normalized()
			if dir.length() < 0.01:
				dir = Vector2(0, -1)
		else:
			dir = sp - c
			if dir.length() < 0.01:
				dir = Vector2(0, -1)
			dir = dir.normalized()
		var half := size / 2.0
		var t: float
		if absf(dir.x) > absf(dir.y):
			t = (half.x - 52.0) / absf(dir.x)
		else:
			t = (half.y - 52.0) / absf(dir.y)
		var edge := c + dir * t
		var ang2 := atan2(dir.y, dir.x)
		var tip := edge + Vector2(cos(ang2), sin(ang2)) * 18.0
		var perp := Vector2(-sin(ang2), cos(ang2)) * 9.0
		draw_colored_polygon(PackedVector2Array([tip, edge + perp, edge - perp]), Color(col.r, col.g, col.b, 0.92))
		draw_string(UiTheme.mono_font(), edge + Vector2(-50, 30), _label(), HORIZONTAL_ALIGNMENT_CENTER, 100, 13, col)

	func _label() -> String:
		var d: String = str(int(round(dist))) + "m"
		return ("圈内 · 距圈缘 " if inside else "圈外 · 距毒圈 ") + d


# ==================== 坦克/防空炮车炮镜(炮手位 ADS:轻量分划叠加,无全屏黑罩) ====================
class TankScope extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.42
		# 全屏黑色遮罩:只留中央圆窗(炮镜视觉,其余全黑)
		var r_out := r * 1.04
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, c.y - r_out), Vector2(0, c.y - r_out)]), Color(0, 0, 0, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(0, c.y + r_out), Vector2(size.x, c.y + r_out), Vector2(size.x, size.y), Vector2(0, size.y)]), Color(0, 0, 0, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(0, c.y - r_out), Vector2(c.x - r_out, c.y - r_out), Vector2(c.x - r_out, c.y + r_out), Vector2(0, c.y + r_out)]), Color(0, 0, 0, 1))
		draw_colored_polygon(PackedVector2Array([Vector2(c.x + r_out, c.y - r_out), Vector2(size.x, c.y - r_out), Vector2(size.x, c.y + r_out), Vector2(c.x + r_out, c.y + r_out)]), Color(0, 0, 0, 1))
		# 圆窗外沿柔边(渐变环,防硬边锯齿)
		for i in 10:
			var rr2: float = r_out + (i + 1) * r * 0.03
			draw_arc(c, rr2, 0, TAU, 96, Color(0, 0, 0, 0.8 * (1.0 - float(i) / 10.0)), r * 0.03)
		# 镜筒:外暗环 + 内亮沿 + 镜内暗角
		draw_arc(c, r * 1.03, 0, TAU, 96, Color(0.03, 0.03, 0.03, 1), r * 0.05)
		draw_arc(c, r * 0.99, 0, TAU, 96, Color(0.22, 0.26, 0.3, 0.75), 2.5)
		draw_arc(c, r * 0.97, 0, TAU, 96, Color(0.01, 0.01, 0.01, 0.9), 3.0)
		for i in 8:
			var rr: float = r * (0.94 - i * 0.03)
			draw_arc(c, rr, 0, TAU, 96, Color(0, 0, 0, 0.05 * (8 - i) / 8.0), 1.0)
		# 十字分划(粗主 + 细副,中心留隙)
		var col := Color(0.08, 0.09, 0.1, 0.85)
		var col2 := Color(0.6, 0.66, 0.72, 0.55)
		draw_line(c + Vector2(-r * 0.95 + 10, 0), c + Vector2(-12, 0), col, 2.2)
		draw_line(c + Vector2(12, 0), c + Vector2(r * 0.95 - 10, 0), col, 2.2)
		draw_line(c + Vector2(0, -r * 0.95 + 10), c + Vector2(0, -12), col, 2.2)
		draw_line(c + Vector2(0, 12), c + Vector2(0, r * 0.95 - 10), col, 2.2)
		# 密位刻度(长短交替)
		for i in range(-6, 7):
			if i == 0:
				continue
			var off: float = i * r / 7.0
			var half: float = 5.0 if absi(i) % 2 == 1 else 3.0
			draw_line(c + Vector2(off, -half), c + Vector2(off, half), col2, 1.0)
			draw_line(c + Vector2(-half, off), c + Vector2(half, off), col2, 1.0)
		# 下塔形测距分划(坦克炮镜特征)
		for i in range(1, 4):
			var yy: float = r * 0.16 * i
			var ww: float = r * 0.05 * i
			draw_line(c + Vector2(-ww, yy), c + Vector2(ww, yy), col2, 1.0)
		# 中心瞄准尖
		var cs := 6.0
		draw_line(c + Vector2(-cs, 0), c + Vector2(cs, 0), Color(0.05, 0.05, 0.05, 0.95), 1.2)
		draw_line(c + Vector2(0, -cs), c + Vector2(0, cs), Color(0.05, 0.05, 0.05, 0.95), 1.2)
		draw_circle(c, 1.6, Color(0.06, 0.06, 0.06, 0.9))


# ==================== 主 HUD ====================
var spawn_point = null                 # 玩家自选前线出生点(旗帜对象)
var spawn_mate = null                  # 玩家自选小队成员(部署到其身旁)

var _crosshair: Crosshair
var _scope: ScopeOverlay
var _dmg_arc: DamageArc
var _dmg_vignette: TextureRect
var _nvg: NightVisionOverlay
var _veh_aim: VehicleAim
var _world: WorldOverlay
var _deployment_overlay: DeploymentOverlay
var _minimap: Minimap
var _event_feed: EventFeed
var _ticket_us: Label
var _ticket_ru: Label
var _pips: Dictionary = {}
var _sector_label: Label
var _timer: Label
var _killfeed: VBoxContainer
var _banner: Label
var _br_redeploy_label: Label
var _cap_bar: PanelContainer
var _cap_fill: ColorRect
var _cap_text: Label
var _health_fill: ColorRect
var _health_num: Label
var _class_icon: Label
var _gadget_info: Label
var _stance: Label
var _wpn_panel: PanelContainer
var _weapon_name: Label
var _weapon_icon: WeaponIcon
var _attach_label: Label
var _ammo_mag: Label
var _ammo_reserve: Label
var _fire_mode: Label
var _tools_row: ToolsRow
var _veh_panel: PanelContainer
var _veh_name: Label
var _veh_crew: Label
var _veh_hp_fill: ColorRect
var _veh_hp_pct: Label
var _veh_wpn_fill: ColorRect
var _veh_wpn_label: Label
var _veh_lock: Label
var _veh_speed: Label
var _veh_gear: Label
var _veh_compass: CompassStrip
var _veh_alt: Label
var _veh_ammo_tag: Label          # [载具 HUD v2] 炮弹数量(大号)
var _veh_ammo: Label
var _veh_pos: Label               # 坐标
var _veh_data: Label              # 附加数据(海拔/航向等)
var _radar: Radar
var _hint: Label
var _streak: RichTextLabel
var _scoreboard: PanelContainer
var _sb_us: RichTextLabel
var _sb_ru: RichTextLabel
var _sb_title: Label
var _camp_obj: Label
var _camp_dialogue: Label
var _camp_dialogue_name: Label
var _camp_dialogue_box: PanelContainer
var _camp_dialogue_tw: Tween
var _camp_card: Label
var _camp_card_tw: Tween
var _camp_indicator: CampaignIndicator
var _squad_panel: PanelContainer
var _squad_row: HBoxContainer
var _squad_blocks: Array = []
var _revive_label: Label
var _interact_box: PanelContainer
var _interact_label: Label
var _interact_fill: ColorRect
var _fade_rect: ColorRect
var _fade_tw: Tween
var _zone_prev := false
var _top_bar: HBoxContainer
var _campaign_src: Node = null
var _portal_src: Node = null
var _portal_active := false
var _portal_last_result: Dictionary = {}
var _portal_style := ""
var _portal_bar: VBoxContainer
var _pb_left: PanelContainer
var _pb_left_l: Label
var _pb_mid: Label
var _pb_right: PanelContainer
var _pb_right_l: Label
var _portal_sub: Label
var _br_zone: BrZoneIndicator
var _tank_scope: TankScope       # [8/10] 坦克/防空炮车炮镜分划

var _banner_t := 0.0
var _hint_t := 0.0
var _dmg_t := 0.0
var _hud_root: Control
var _hud_t := 0.0
var _hp_show := 100.0
var _hp_flash_t := 0.0
var _last_hp_disp := 100.0
var _last_ammo := -1
var _ammo_disp := 30.0
var _last_tick_us := ""
var _last_tick_ru := ""
var _ammo_bar: ColorRect
var _ammo_fill: ColorRect
var _flash: ColorRect
var _pop_times: Dictionary = {}
var _pop_tweens: Dictionary = {}
var _weapon_ctx := ""
var _veh_lock_tw: Tween


func _ready() -> void:
	layer = 5
	_build()
	G.hud = self


func _build() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.visible = false
	add_child(_hud_root)

	# ---- 夜视仪敌人高亮(最下层) ----
	_nvg = NightVisionOverlay.new()
	_nvg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nvg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nvg.visible = false
	_hud_root.add_child(_nvg)

	# ---- 世界空间指示器(据点/队友/敌人;置于全屏效果之下,狙击镜黑罩可覆盖) ----
	_world = WorldOverlay.new()
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_world)

	# ---- 实时战场部署观察层(死亡后 3D 部署模式的战术标记;独立于 _hud_root,死亡隐藏 HUD 时仍显示) ----
	_deployment_overlay = DeploymentOverlay.new()
	_deployment_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deployment_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deployment_overlay.visible = false
	add_child(_deployment_overlay)

	# ---- 准星/狙击镜/载具瞄准/伤害弧/暗角/闪光(全屏层) ----
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_crosshair)
	_veh_aim = VehicleAim.new()
	_veh_aim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veh_aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veh_aim.visible = false
	_hud_root.add_child(_veh_aim)
	_scope = ScopeOverlay.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	_hud_root.add_child(_scope)
	_dmg_arc = DamageArc.new()
	_dmg_arc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_dmg_arc)
	_dmg_vignette = TextureRect.new()
	_dmg_vignette.texture = _make_vignette_tex()
	_dmg_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dmg_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_dmg_vignette.modulate = Color(0.55, 0.05, 0.03, 0)
	_dmg_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_dmg_vignette)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 1)
	_flash.modulate.a = 0.0
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_flash)

	# ---- 左下:小地图(288px ≈ 15% 屏宽,底部信息条) ----
	# 显式四边 offset + grow BEGIN:防止最小高度撑开时向下溢出屏幕
	_minimap = Minimap.new()
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap.offset_left = 16
	_minimap.offset_bottom = -16
	_minimap.offset_top = -(16.0 + Minimap.MAP_SIDE + Minimap.STATS_H)
	_minimap.offset_right = 16 + Minimap.MAP_SIDE
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_root.add_child(_minimap)

	# ---- 左侧中部:动态消息区 ----
	_event_feed = EventFeed.new()
	_event_feed.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_event_feed.position = Vector2(16, 300)
	_event_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_event_feed)

	# ---- 顶部中央:比分 + 时间 + 据点字母(战役/门户模式整条隐藏) ----
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.position = Vector2(0, 12)
	_top_bar.add_theme_constant_override("separation", 12)
	_top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_top_bar)
	_ticket_us = UiTheme.make_mono_label("400", 24, Color(0.72, 0.94, 0.98))
	_ticket_us.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticket_us.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ticket_us.custom_minimum_size = Vector2(84, 34)
	_ticket_us.add_theme_stylebox_override("normal", UiTheme.hud_frost(0.22, Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.4), 1, 3, 8))
	_top_bar.add_child(_ticket_us)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(mid)
	_sector_label = UiTheme.make_label("", 12, Color(0.85, 0.88, 0.92))
	_sector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sector_label.visible = false
	mid.add_child(_sector_label)
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 6)
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(pip_row)
	for fid in ["A", "B", "C", "D", "E", "F"]:
		var chip := FlagChip.new()
		chip.fid = fid
		chip.visible = false
		pip_row.add_child(chip)
		_pips[fid] = chip
	_timer = UiTheme.make_mono_label("00:00", 13, Color(0.75, 0.82, 0.88))
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_timer)
	_ticket_ru = UiTheme.make_mono_label("400", 24, Color(1.0, 0.8, 0.62))
	_ticket_ru.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticket_ru.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ticket_ru.custom_minimum_size = Vector2(84, 34)
	_ticket_ru.add_theme_stylebox_override("normal", UiTheme.hud_frost(0.22, Color(UiTheme.H_ORANGE.r, UiTheme.H_ORANGE.g, UiTheme.H_ORANGE.b, 0.4), 1, 3, 8))
	_top_bar.add_child(_ticket_ru)

	# ---- 顶部中央:门户栏(TDM 计分条 / BR 存活数) ----
	_portal_bar = VBoxContainer.new()
	_portal_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_portal_bar.position = Vector2(0, 12)
	_portal_bar.add_theme_constant_override("separation", 4)
	_portal_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_portal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portal_bar.visible = false
	_hud_root.add_child(_portal_bar)
	var pb_row := HBoxContainer.new()
	pb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pb_row.add_theme_constant_override("separation", 8)
	pb_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portal_bar.add_child(pb_row)
	_pb_left = PanelContainer.new()
	_pb_left.custom_minimum_size = Vector2(110, 34)
	_pb_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb_row.add_child(_pb_left)
	_pb_left_l = UiTheme.make_mono_label("0", 22, Color(0.72, 0.94, 0.98))
	_pb_left_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pb_left_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pb_left_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pb_left.add_child(_pb_left_l)
	_pb_mid = UiTheme.make_mono_label(":", 20, Color(0.6, 0.68, 0.74))
	_pb_mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pb_row.add_child(_pb_mid)
	_pb_right = PanelContainer.new()
	_pb_right.custom_minimum_size = Vector2(110, 34)
	_pb_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb_row.add_child(_pb_right)
	_pb_right_l = UiTheme.make_mono_label("0", 22, Color(1.0, 0.8, 0.62))
	_pb_right_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pb_right_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pb_right_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pb_right.add_child(_pb_right_l)
	_portal_sub = UiTheme.make_mono_label("", 12, Color(0.72, 0.78, 0.84))
	_portal_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portal_bar.add_child(_portal_sub)

	# ---- 大逃杀毒圈指示(全屏) ----
	_br_zone = BrZoneIndicator.new()
	_br_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_br_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_br_zone.visible = false
	_hud_root.add_child(_br_zone)
	# ---- [8/10] 坦克/防空炮车炮镜(炮手位 ADS 显示,全屏顶层) ----
	_tank_scope = TankScope.new()
	_tank_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tank_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tank_scope.visible = false
	_hud_root.add_child(_tank_scope)

	# ---- 右上:击杀播报 ----
	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_killfeed.grow_vertical = Control.GROW_DIRECTION_END
	_killfeed.position = Vector2(-16, 64)
	_killfeed.custom_minimum_size = Vector2(360, 0)
	_killfeed.add_theme_constant_override("separation", 3)
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_killfeed)

	# ---- 中央横幅 ----
	var banner_row := HBoxContainer.new()
	banner_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_row.position = Vector2(0, 116)
	banner_row.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(banner_row)
	_banner = UiTheme.make_label("", 20, Color(1, 0.92, 0.7))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_banner.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.3, Color(0.65, 0.75, 0.8, 0.4), 1, 4, 14))
	banner_row.add_child(_banner)

	# ---- 战役目标(顶部中央,票数行下方) ----
	var camp_obj_row := HBoxContainer.new()
	camp_obj_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	camp_obj_row.offset_top = 58
	camp_obj_row.offset_bottom = 104
	camp_obj_row.alignment = BoxContainer.ALIGNMENT_CENTER
	camp_obj_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(camp_obj_row)
	_camp_obj = UiTheme.make_label("", 14, Color(0.16, 0.78, 0.86))
	_camp_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camp_obj.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_camp_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_obj.custom_minimum_size = Vector2(640, 0)
	_camp_obj.visible = false
	_camp_obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_obj.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.22, Color(0.16, 0.78, 0.86, 0.35), 1, 3, 10))
	camp_obj_row.add_child(_camp_obj)

	# ---- 占领进度(顶部中央下方) ----
	_cap_bar = PanelContainer.new()
	_cap_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cap_bar.position = Vector2(-150, 186)
	_cap_bar.custom_minimum_size = Vector2(300, 48)
	_cap_bar.visible = false
	_cap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_bar.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.3, Color(0.16, 0.78, 0.86, 0.3), 1, 4, 10))
	_hud_root.add_child(_cap_bar)
	var cap_v := VBoxContainer.new()
	cap_v.add_theme_constant_override("separation", 3)
	_cap_bar.add_child(cap_v)
	var cap_bg := ColorRect.new()
	cap_bg.color = Color(0.1, 0.12, 0.15, 0.8)
	cap_bg.custom_minimum_size = Vector2(0, 8)
	cap_v.add_child(cap_bg)
	_cap_fill = ColorRect.new()
	_cap_fill.color = Color(0.05, 0.62, 0.6)
	cap_bg.add_child(_cap_fill)
	_cap_fill.anchor_right = 0.5
	_cap_fill.anchor_bottom = 1.0
	_cap_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cap_text = UiTheme.make_label("占领中", 13, Color(0.8, 0.86, 0.9))
	_cap_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_v.add_child(_cap_text)

	# ---- 左下:生命与兵种(整体面板,小地图上方) ----
	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_panel.offset_left = 16
	status_panel.offset_bottom = -(16.0 + Minimap.MAP_SIDE + Minimap.STATS_H + 10.0)
	status_panel.offset_top = status_panel.offset_bottom - 52.0
	status_panel.offset_right = 16.0 + 300.0
	status_panel.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.28, Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.3), 1, 4, 10))
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(status_panel)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 10)
	status_panel.add_child(status)
	_class_icon = UiTheme.make_label("突", 22, Color(0.5, 0.82, 1))
	_class_icon.custom_minimum_size = Vector2(40, 44)
	_class_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_class_icon.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.2, Color(0.3, 0.5, 0.6, 0.35), 1, 4, 4))
	status.add_child(_class_icon)
	var st_right := VBoxContainer.new()
	st_right.alignment = BoxContainer.ALIGNMENT_CENTER
	st_right.add_theme_constant_override("separation", 3)
	status.add_child(st_right)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.1, 0.12, 0.15, 0.8)
	hp_bg.custom_minimum_size = Vector2(170, 9)
	st_right.add_child(hp_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.35, 0.8, 0.5)
	hp_bg.add_child(_health_fill)
	_health_fill.anchor_right = 1.0
	_health_fill.anchor_bottom = 1.0
	_health_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var st_row := HBoxContainer.new()
	st_row.add_theme_constant_override("separation", 10)
	st_right.add_child(st_row)
	_health_num = UiTheme.make_mono_label("100", 18, Color(0.92, 0.96, 0.98))
	st_row.add_child(_health_num)
	_stance = UiTheme.make_label("站立", 12, Color(0.6, 0.68, 0.74))
	st_row.add_child(_stance)
	_gadget_info = UiTheme.make_label("F 医疗包 ×2", 12, Color(0.62, 0.7, 0.76))
	st_row.add_child(_gadget_info)

	# ---- 战役小队状态栏(左下,生命面板上方) ----
	_squad_panel = PanelContainer.new()
	_squad_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_squad_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_squad_panel.offset_left = 16
	_squad_panel.offset_bottom = -(16.0 + Minimap.MAP_SIDE + Minimap.STATS_H + 10.0 + 52.0 + 8.0)
	_squad_panel.offset_top = _squad_panel.offset_bottom - 58.0
	_squad_panel.offset_right = 16.0 + 440.0
	_squad_panel.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.28, Color(0.35, 0.5, 0.58, 0.35), 1, 4, 10))
	_squad_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_panel.visible = false
	_hud_root.add_child(_squad_panel)
	_squad_row = HBoxContainer.new()
	_squad_row.add_theme_constant_override("separation", 6)
	_squad_panel.add_child(_squad_row)
	for k in 3:
		var blk := PanelContainer.new()
		blk.custom_minimum_size = Vector2(140, 46)
		blk.add_theme_stylebox_override("panel",
			UiTheme.hud_frost(0.2, Color(0.35, 0.5, 0.58, 0.3), 1, 3, 6))
		_squad_row.add_child(blk)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		blk.add_child(vb)
		var nm := UiTheme.make_label("", 11, Color(0.85, 0.9, 0.92))
		vb.add_child(nm)
		var hb2 := ColorRect.new()
		hb2.color = Color(0.1, 0.12, 0.15, 0.8)
		hb2.custom_minimum_size = Vector2(124, 5)
		vb.add_child(hb2)
		var fill := ColorRect.new()
		fill.color = Color(0.35, 0.8, 0.5)
		hb2.add_child(fill)
		fill.anchor_right = 1.0
		fill.anchor_bottom = 1.0
		fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		var st := UiTheme.make_label("正常", 10, Color(0.6, 0.8, 0.66))
		vb.add_child(st)
		_squad_blocks.append({ "name": nm, "fill": fill, "status": st })

	# ---- 连杀指示 ----
	_streak = RichTextLabel.new()
	_streak.theme = UiTheme.theme()
	_streak.bbcode_enabled = true
	_streak.fit_content = true
	_streak.scroll_active = false
	_streak.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_streak.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_streak.offset_left = 16
	_streak.offset_bottom = -(16.0 + Minimap.MAP_SIDE + Minimap.STATS_H + 10.0 + 52.0 + 8.0 + 58.0 + 8.0)
	_streak.offset_top = _streak.offset_bottom - 30.0
	_streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak.add_theme_font_size_override("normal_font_size", 14)
	_hud_root.add_child(_streak)

	# ---- 右下:武器面板(横向布局:图标/名称/弹药大字/备用/射击模式/配件/工具) ----
	_wpn_panel = PanelContainer.new()
	_wpn_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_wpn_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_wpn_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_wpn_panel.position = Vector2(-16, -16)
	_wpn_panel.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.26, Color(0.6, 0.72, 0.8, 0.35), 1, 4, 12))
	_wpn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_wpn_panel)
	var wpn_box := HBoxContainer.new()
	wpn_box.add_theme_constant_override("separation", 12)
	wpn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wpn_panel.add_child(wpn_box)
	_weapon_icon = WeaponIcon.new()
	wpn_box.add_child(_weapon_icon)
	var wpn_mid := VBoxContainer.new()
	wpn_mid.alignment = BoxContainer.ALIGNMENT_END
	wpn_mid.add_theme_constant_override("separation", 1)
	wpn_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_box.add_child(wpn_mid)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.alignment = BoxContainer.ALIGNMENT_END
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_mid.add_child(name_row)
	_weapon_name = UiTheme.make_label("M4A1", 15, Color(0.82, 0.88, 0.92))
	name_row.add_child(_weapon_name)
	_fire_mode = UiTheme.make_label("全自动", 11, Color(0.5, 0.6, 0.68))
	_fire_mode.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.12, Color(0.6, 0.72, 0.8, 0.25), 1, 3, 4))
	name_row.add_child(_fire_mode)
	_attach_label = UiTheme.make_label("", 11, Color(0.45, 0.55, 0.62))
	wpn_mid.add_child(_attach_label)
	_tools_row = ToolsRow.new()
	wpn_mid.add_child(_tools_row)
	var wpn_ammo := VBoxContainer.new()
	wpn_ammo.alignment = BoxContainer.ALIGNMENT_END
	wpn_ammo.add_theme_constant_override("separation", 1)
	wpn_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_box.add_child(wpn_ammo)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 5)
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_ammo.add_child(ammo_row)
	_ammo_mag = UiTheme.make_mono_label("030", 38, Color(1, 1, 1))
	ammo_row.add_child(_ammo_mag)
	ammo_row.add_child(UiTheme.make_label("/", 20, Color(0.45, 0.52, 0.58)))
	_ammo_reserve = UiTheme.make_mono_label("150", 18, Color(0.55, 0.62, 0.7))
	ammo_row.add_child(_ammo_reserve)
	_ammo_bar = ColorRect.new()
	_ammo_bar.color = Color(0.1, 0.12, 0.15, 0.85)
	_ammo_bar.custom_minimum_size = Vector2(110, 3)
	wpn_ammo.add_child(_ammo_bar)
	_ammo_fill = ColorRect.new()
	_ammo_fill.color = Color(0.75, 0.82, 0.88)
	_ammo_bar.add_child(_ammo_fill)
	_ammo_fill.anchor_right = 1.0
	_ammo_fill.anchor_bottom = 1.0
	_ammo_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# ---- 右下:载具 HUD(进入载具自动切换,独立布局) ----
	_veh_panel = PanelContainer.new()
	_veh_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_veh_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_veh_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_veh_panel.position = Vector2(-16, -16)
	# [载具 HUD v2] 方形军事面板(直角 + 亮边框)
	var veh_sb := StyleBoxFlat.new()
	veh_sb.bg_color = Color(0.03, 0.045, 0.06, 0.78)
	veh_sb.border_color = Color(0.72, 0.82, 0.88, 0.55)
	veh_sb.set_border_width_all(1)
	veh_sb.set_corner_radius_all(0)
	veh_sb.set_content_margin_all(8)
	_veh_panel.add_theme_stylebox_override("panel", veh_sb)
	_veh_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veh_panel.visible = false
	_hud_root.add_child(_veh_panel)
	var veh_box := HBoxContainer.new()
	veh_box.add_theme_constant_override("separation", 12)
	veh_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veh_panel.add_child(veh_box)
	_radar = Radar.new()
	veh_box.add_child(_radar)
	var veh_info := VBoxContainer.new()
	veh_info.add_theme_constant_override("separation", 3)
	veh_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_box.add_child(veh_info)
	var veh_name_row := HBoxContainer.new()
	veh_name_row.add_theme_constant_override("separation", 8)
	veh_name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_name_row)
	_veh_name = UiTheme.make_label("", 15, Color(0.85, 0.91, 0.95))
	veh_name_row.add_child(_veh_name)
	_veh_crew = UiTheme.make_label("乘员 1", 11, Color(0.5, 0.6, 0.68))
	veh_name_row.add_child(_veh_crew)
	var veh_hp_row := HBoxContainer.new()
	veh_hp_row.add_theme_constant_override("separation", 6)
	veh_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_hp_row)
	var hp_tag := UiTheme.make_label("耐久", 10, Color(0.5, 0.58, 0.65))
	veh_hp_row.add_child(hp_tag)
	var veh_hp_bg := ColorRect.new()
	veh_hp_bg.color = Color(0.1, 0.12, 0.15, 0.85)
	veh_hp_bg.custom_minimum_size = Vector2(120, 6)
	veh_hp_row.add_child(veh_hp_bg)
	_veh_hp_fill = ColorRect.new()
	_veh_hp_fill.color = Color(0.65, 0.75, 0.8)
	veh_hp_bg.add_child(_veh_hp_fill)
	_veh_hp_fill.anchor_right = 1.0
	_veh_hp_fill.anchor_bottom = 1.0
	_veh_hp_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_veh_hp_pct = UiTheme.make_mono_label("100%", 11, Color(0.8, 0.86, 0.9))
	veh_hp_row.add_child(_veh_hp_pct)
	var veh_wpn_row := HBoxContainer.new()
	veh_wpn_row.add_theme_constant_override("separation", 6)
	veh_wpn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_wpn_row)
	var wpn_tag := UiTheme.make_label("武备", 10, Color(0.5, 0.58, 0.65))
	veh_wpn_row.add_child(wpn_tag)
	var veh_wpn_bg := ColorRect.new()
	veh_wpn_bg.color = Color(0.1, 0.12, 0.15, 0.85)
	veh_wpn_bg.custom_minimum_size = Vector2(120, 6)
	veh_wpn_row.add_child(veh_wpn_bg)
	_veh_wpn_fill = ColorRect.new()
	_veh_wpn_fill.color = Color(0.16, 0.78, 0.86)
	veh_wpn_bg.add_child(_veh_wpn_fill)
	_veh_wpn_fill.anchor_right = 1.0
	_veh_wpn_fill.anchor_bottom = 1.0
	_veh_wpn_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_veh_wpn_label = UiTheme.make_mono_label("", 11, Color(0.72, 0.8, 0.86))
	veh_wpn_row.add_child(_veh_wpn_label)
	_veh_lock = UiTheme.make_label("", 11, Color(0.95, 0.34, 0.28))
	_veh_lock.visible = false
	veh_info.add_child(_veh_lock)
	var veh_speed_row := HBoxContainer.new()
	veh_speed_row.add_theme_constant_override("separation", 6)
	veh_speed_row.alignment = BoxContainer.ALIGNMENT_END
	veh_speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_speed_row)
	_veh_speed = UiTheme.make_mono_label("0", 26, Color(0.92, 0.96, 0.98))
	veh_speed_row.add_child(_veh_speed)
	veh_speed_row.add_child(UiTheme.make_label("KM/H", 10, Color(0.5, 0.6, 0.68)))
	_veh_gear = UiTheme.make_mono_label("N", 14, Color(0.7, 0.78, 0.84))
	veh_speed_row.add_child(_veh_gear)
	_veh_compass = CompassStrip.new()
	veh_info.add_child(_veh_compass)
	_veh_alt = UiTheme.make_mono_label("", 11, Color(0.5, 0.6, 0.68))
	veh_info.add_child(_veh_alt)
	# [载具 HUD v2] 方形数据区:炮弹数量(大号)+ 坐标 + 附加数据
	var veh_ammo_row := HBoxContainer.new()
	veh_ammo_row.add_theme_constant_override("separation", 6)
	veh_ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_ammo_row)
	_veh_ammo_tag = UiTheme.make_label("炮弹", 11, Color(0.55, 0.64, 0.72))
	veh_ammo_row.add_child(_veh_ammo_tag)
	_veh_ammo = UiTheme.make_mono_label("--", 22, Color(1.0, 0.85, 0.45))
	veh_ammo_row.add_child(_veh_ammo)
	var veh_pos_row := HBoxContainer.new()
	veh_pos_row.add_theme_constant_override("separation", 6)
	veh_pos_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_pos_row)
	var pos_tag := UiTheme.make_label("坐标", 10, Color(0.5, 0.58, 0.65))
	veh_pos_row.add_child(pos_tag)
	_veh_pos = UiTheme.make_mono_label("X 0000 · Z 0000", 11, Color(0.65, 0.75, 0.82))
	veh_pos_row.add_child(_veh_pos)
	var veh_data_row := HBoxContainer.new()
	veh_data_row.add_theme_constant_override("separation", 6)
	veh_data_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veh_info.add_child(veh_data_row)
	_veh_data = UiTheme.make_mono_label("", 11, Color(0.5, 0.6, 0.68))
	veh_data_row.add_child(_veh_data)

	# ---- 底部中央提示 ----
	var hint_row := HBoxContainer.new()
	hint_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_row.position = Vector2(0, -120)
	hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(hint_row)
	_hint = UiTheme.make_label("", 14, Color(0.72, 0.78, 0.84))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_row.add_child(_hint)

	# ---- 救治队友提示(底部中央) ----
	_revive_label = UiTheme.make_label("", 14, Color(0.6, 0.85, 0.7))
	_revive_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_revive_label.position = Vector2(0, -84)
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_label.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.25, Color(0.35, 0.8, 0.5, 0.35), 1, 3, 8))
	_revive_label.visible = false
	_revive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_revive_label)

	# ---- 交互目标提示(底部中央) ----
	_interact_box = PanelContainer.new()
	_interact_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_box.position = Vector2(0, -46)
	_interact_box.custom_minimum_size = Vector2(300, 0)
	_interact_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_box.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.25, Color(0.16, 0.78, 0.86, 0.35), 1, 3, 8))
	_interact_box.visible = false
	_hud_root.add_child(_interact_box)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 3)
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_box.add_child(iv)
	_interact_label = UiTheme.make_label("", 14, Color(0.78, 0.9, 0.95))
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(_interact_label)
	var ibar := ColorRect.new()
	ibar.color = Color(0.1, 0.12, 0.15, 0.8)
	ibar.custom_minimum_size = Vector2(0, 7)
	ibar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(ibar)
	_interact_fill = ColorRect.new()
	_interact_fill.color = Color(0.16, 0.78, 0.86)
	_interact_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ibar.add_child(_interact_fill)
	_interact_fill.anchor_right = 0.0
	_interact_fill.anchor_bottom = 1.0
	_interact_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# ---- 战役字幕(底部中央) ----
	_camp_dialogue_box = PanelContainer.new()
	_camp_dialogue_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_camp_dialogue_box.offset_top = -216
	_camp_dialogue_box.offset_bottom = -128
	_camp_dialogue_box.offset_left = 140
	_camp_dialogue_box.offset_right = -140
	_camp_dialogue_box.visible = false
	_camp_dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_dialogue_box.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.35, Color(0.16, 0.78, 0.86, 0.3), 1, 3, 12))
	_hud_root.add_child(_camp_dialogue_box)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	drow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_dialogue_box.add_child(drow)
	_camp_dialogue_name = UiTheme.make_label("", 15, UiTheme.H_CYAN)
	drow.add_child(_camp_dialogue_name)
	_camp_dialogue = UiTheme.make_label("", 15, Color(0.88, 0.92, 0.95))
	_camp_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camp_dialogue.custom_minimum_size = Vector2(560, 0)
	drow.add_child(_camp_dialogue)

	# ---- 战役大字卡 ----
	_camp_card = UiTheme.make_label("", 40, Color(0.72, 0.94, 0.98))
	_camp_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camp_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_camp_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_camp_card.offset_left = -480
	_camp_card.offset_top = -150
	_camp_card.offset_right = 480
	_camp_card.offset_bottom = -60
	_camp_card.visible = false
	_camp_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_card.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.35, Color(0.16, 0.78, 0.86, 0.45), 1, 4, 16))
	_hud_root.add_child(_camp_card)

	# ---- 战役目标屏幕边缘指示器 ----
	_camp_indicator = CampaignIndicator.new()
	_camp_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	_camp_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_indicator.visible = false
	_hud_root.add_child(_camp_indicator)

	# ---- 记分板 ----
	_scoreboard = PanelContainer.new()
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard.custom_minimum_size = Vector2(680, 420)
	_scoreboard.position = Vector2(-340, -210)
	_scoreboard.visible = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.4, Color(0.6, 0.72, 0.8, 0.45), 1, 6, 18))
	_hud_root.add_child(_scoreboard)
	var sb_v := VBoxContainer.new()
	sb_v.add_theme_constant_override("separation", 10)
	_scoreboard.add_child(sb_v)
	_sb_title = UiTheme.make_label("记分板 — 征服模式", 17, Color(0.85, 0.91, 0.95))
	_sb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sb_v.add_child(_sb_title)
	var sb_cols := HBoxContainer.new()
	sb_cols.add_theme_constant_override("separation", 24)
	sb_cols.alignment = BoxContainer.ALIGNMENT_CENTER
	sb_v.add_child(sb_cols)
	_sb_us = RichTextLabel.new()
	_sb_us.theme = UiTheme.theme()
	_sb_us.bbcode_enabled = true
	_sb_us.fit_content = true
	_sb_us.scroll_active = false
	_sb_us.custom_minimum_size = Vector2(300, 0)
	sb_cols.add_child(_sb_us)
	_sb_ru = RichTextLabel.new()
	_sb_ru.theme = UiTheme.theme()
	_sb_ru.bbcode_enabled = true
	_sb_ru.fit_content = true
	_sb_ru.scroll_active = false
	_sb_ru.custom_minimum_size = Vector2(300, 0)
	sb_cols.add_child(_sb_ru)

	# ---- 全屏黑(最顶层,独立于 _hud_root) ----
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.modulate.a = 0.0
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	add_child(_fade_rect)

	# ---- 大逃杀:重部署提示(独立于 _hud_root) ----
	_br_redeploy_label = UiTheme.make_label("", 18, Color(1.0, 0.8, 0.55))
	_br_redeploy_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_br_redeploy_label.offset_left = -560
	_br_redeploy_label.offset_right = 560
	_br_redeploy_label.offset_top = -200
	_br_redeploy_label.offset_bottom = -156
	_br_redeploy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_br_redeploy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_br_redeploy_label.add_theme_stylebox_override("normal",
		UiTheme.hud_frost(0.3, Color(1.0, 0.55, 0.22, 0.45), 1, 4, 12))
	_br_redeploy_label.visible = false
	_br_redeploy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_br_redeploy_label)


func _make_vignette_tex() -> Texture2D:
	return Effects.make_vignette_tex(Color(1, 1, 1), 0.55, 1.0, true, 1.0)


## ============ 界面切换 ============
func show_screen(p_name: String) -> void:
	if p_name == "hud":
		_hud_root.visible = true


func hide_screen(p_name: String) -> void:
	match p_name:
		"hud":
			_hud_root.visible = false
		"death":
			G.menus.hide_death()
		"deploy":
			G.menus.hide_deploy()


func show_deploy(is_redeploy := false) -> void:
	G.effects.reset_death_fade()
	G.menus.show_deploy(is_redeploy)


func show_death(killer_text: String) -> void:
	G.menus.show_death(killer_text)


func show_end(win: bool) -> void:
	G.menus.show_end(win)


## ============ 战斗反馈 ============
func show_hitmarker(kill: bool, head: bool) -> void:
	_crosshair.show_hit(kill, head)
	_screen_flash(Color(1, 1, 1), 0.3 if kill else 0.15, 0.24 if kill else 0.16)


func _screen_flash(col: Color, peak: float, dur: float) -> void:
	if _flash == null or not _flash.is_inside_tree():
		return
	_flash.color = col
	_flash.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", peak, 0.03)
	tw.tween_property(_flash, "modulate:a", 0.0, dur)


## ============ 动态消息区(第三层信息:图标 + 两行文字,滑入滑出渐隐) ============
func event(icon: String, title: String, sub: String, col: Color = Color(0.16, 0.78, 0.86)) -> void:
	if _event_feed != null and is_instance_valid(_event_feed) and _event_feed.is_inside_tree():
		_event_feed.add_event(icon, title, sub, col)


## [8/10] 坦克/防空炮车炮镜开关(炮手位 ADS;player.gd 调用)
func set_veh_scope(on: bool) -> void:
	if _tank_scope != null and _tank_scope.visible != on:
		_tank_scope.visible = on
		if on:
			_tank_scope.queue_redraw()


## 实时战场部署观察层开关(BattleDeploymentManager 调用)
func set_deployment_overlay(on: bool) -> void:
	if _deployment_overlay == null:
		return
	if _deployment_overlay.visible != on:
		_deployment_overlay.visible = on
		if on:
			_deployment_overlay.queue_redraw()


## 部署转场:黑幕渐入/渐出(部署管理器调用)
func fade_to_black(dur := 0.5) -> void:
	_fade_to_black(dur)


func fade_from_black(dur := 0.6) -> void:
	_fade_from_black(dur)


## ============ 击杀播报(右上,极简行) ============
func add_killfeed(killer_name: String, killer_team, victim_name: String, victim_team, weapon_name: String, head: bool, is_me: bool) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel",
		UiTheme.hud_frost(0.24 if is_me else 0.16,
			Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.4) if is_me else Color(0.5, 0.6, 0.7, 0.25), 1, 3, 8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)
	var kc: Color = UiTheme.H_CYAN if killer_team == "us" else UiTheme.H_ORANGE
	var vc: Color = UiTheme.H_CYAN if victim_team == "us" else UiTheme.H_ORANGE
	var t_l := UiTheme.make_mono_label(G.fmt_clock(G.time), 10, Color(0.45, 0.52, 0.58))
	hb.add_child(t_l)
	var k_l := UiTheme.make_label(killer_name, 13, kc)
	hb.add_child(k_l)
	var w_l := UiTheme.make_label("[" + weapon_name + "]", 11, Color(0.45, 0.52, 0.58))
	hb.add_child(w_l)
	var v_l := UiTheme.make_label(victim_name, 13, vc)
	hb.add_child(v_l)
	if head:
		var h_l := UiTheme.make_label("爆头", 10, Color(0.95, 0.55, 0.3))
		hb.add_child(h_l)
	_killfeed.add_child(row)
	if _killfeed.get_child_count() > 6:
		_killfeed.get_child(0).queue_free()
	# 入场:右侧滑入 + 淡入(EaseOut 0.24s)
	row.modulate.a = 0.0
	row.position.x = 22.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(row, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "position:x", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var wr = weakref(row)
	get_tree().create_timer(5.0).timeout.connect(func():
		var p = wr.get_ref()
		if p != null and is_instance_valid(p):
			var fw: Tween = p.create_tween()
			fw.set_parallel(true)
			fw.tween_property(p, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			fw.tween_property(p, "position:x", 14.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			fw.chain().tween_callback(p.queue_free))


func banner(text: String, bad := false) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.4) if bad else Color(0.72, 0.94, 0.98))
	_banner.visible = true
	_banner_t = 2.4


func hint(text: String) -> void:
	_hint.text = text
	_hint_t = 2.0


func br_redeploy_hint(text: String) -> void:
	if _br_redeploy_label == null:
		return
	_br_redeploy_label.text = text
	_br_redeploy_label.visible = text != ""


func _fade_to_black(dur := 0.5) -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.tween_property(_fade_rect, "modulate:a", 1.0, dur)


func _fade_from_black(dur := 0.6) -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.tween_property(_fade_rect, "modulate:a", 0.0, dur)
	_fade_tw.tween_callback(func():
		if _fade_rect != null and _fade_rect.modulate.a <= 0.001:
			_fade_rect.visible = false)


func _consume_campaign_transition() -> void:
	if G.campaign == null:
		return
	var pt: String = G.campaign.consume_pending_transition()
	if pt == "fade_in":
		_fade_from_black(0.6)
	elif pt == "fade_out":
		_fade_to_black(0.5)


## ============ 战役模式 HUD ============
func set_campaign_objective(text: String) -> void:
	if _camp_obj == null:
		return
	if text == "":
		_camp_obj.visible = false
	else:
		_camp_obj.text = text
		_camp_obj.visible = true


func show_campaign_dialogue(p_name: String, text: String, dur: float) -> void:
	if _camp_dialogue_box == null:
		return
	if _camp_dialogue_tw != null and _camp_dialogue_tw.is_valid():
		_camp_dialogue_tw.kill()
	_camp_dialogue_name.text = p_name
	var lname := p_name.to_lower()
	if lname.contains("敌") or lname.contains("ru"):
		_camp_dialogue_name.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	elif lname.contains("友") or lname.contains("us"):
		_camp_dialogue_name.add_theme_color_override("font_color", Color(0.35, 0.8, 0.5))
	else:
		_camp_dialogue_name.add_theme_color_override("font_color", UiTheme.H_CYAN)
	_camp_dialogue.text = text
	_camp_dialogue_box.visible = true
	_camp_dialogue_box.modulate.a = 0.0
	_camp_dialogue_tw = create_tween()
	_camp_dialogue_tw.tween_property(_camp_dialogue_box, "modulate:a", 1.0, 0.2)
	_camp_dialogue_tw.tween_interval(maxf(dur - 0.55, 0.1))
	_camp_dialogue_tw.tween_property(_camp_dialogue_box, "modulate:a", 0.0, 0.35)
	_camp_dialogue_tw.tween_callback(func(): _camp_dialogue_box.visible = false)


func show_campaign_card(text: String, dur: float = 2.2) -> void:
	if _camp_card == null:
		return
	if _camp_card_tw != null and _camp_card_tw.is_valid():
		_camp_card_tw.kill()
	_camp_card.text = text
	_camp_card.visible = true
	_camp_card.modulate.a = 0.0
	_camp_card_tw = create_tween()
	_camp_card_tw.tween_property(_camp_card, "modulate:a", 1.0, 0.35)
	_camp_card_tw.tween_interval(maxf(dur, 0.25))
	_camp_card_tw.tween_property(_camp_card, "modulate:a", 0.0, 0.5)
	_camp_card_tw.tween_callback(func(): _camp_card.visible = false)


func hide_campaign_card() -> void:
	if _camp_card_tw != null and _camp_card_tw.is_valid():
		_camp_card_tw.kill()
	if _camp_card != null:
		_camp_card.visible = false


func hide_campaign_dialogue() -> void:
	if _camp_dialogue_tw != null and _camp_dialogue_tw.is_valid():
		_camp_dialogue_tw.kill()
	if _camp_dialogue_box != null:
		_camp_dialogue_box.visible = false


func clear_campaign_ui() -> void:
	set_campaign_objective("")
	hide_campaign_dialogue()
	hide_campaign_card()
	if _camp_indicator != null:
		_camp_indicator.clear()
	if _squad_panel != null:
		_squad_panel.visible = false
	if _revive_label != null:
		_revive_label.visible = false
	if _interact_box != null:
		_interact_box.visible = false
	_zone_prev = false
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	if _fade_rect != null:
		_fade_rect.visible = false
		_fade_rect.modulate.a = 0.0


func _update_campaign_indicator(camp_mode: bool, in_cutscene: bool) -> void:
	if _camp_indicator == null:
		return
	var p: Vector3 = Vector3.ZERO
	if camp_mode and not in_cutscene and G.campaign != null and G.campaign.running \
			and G.state == "playing" and G.player != null and G.player.alive:
		p = G.campaign.route_target()
	var vis: bool = p != Vector3.ZERO
	if vis:
		var d: float = G.player.pos.distance_to(p)
		if not _camp_indicator.show_mark or _camp_indicator.target != p or _camp_indicator.dist != d:
			_camp_indicator.set_target(p)
			_camp_indicator.dist = d
			_camp_indicator.visible = true
	else:
		if _camp_indicator.show_mark:
			_camp_indicator.clear()
		if _camp_indicator.visible:
			_camp_indicator.visible = false


func on_player_hurt(attacker_pos) -> void:
	_dmg_t = 0.8
	_screen_flash(Color(1, 0.28, 0.22), 0.2, 0.3)
	if attacker_pos is Vector3:
		var p = G.player
		var ang := atan2(attacker_pos.x - p.pos.x, -(attacker_pos.z - p.pos.z))
		_dmg_arc.rel_angle = ang - p.yaw
		_dmg_arc.arc_opacity = 1.0
		_dmg_arc.queue_redraw()


func _update_campaign_squad(camp_mode: bool, in_cutscene: bool) -> void:
	if _squad_panel == null or _squad_blocks.is_empty():
		return
	var vis: bool = camp_mode and G.campaign != null and G.campaign.running
	if vis:
		var info: Array = G.campaign.get_squad_info()
		_update_squad_panel(info)
	if _squad_panel.visible != vis:
		_squad_panel.visible = vis
	var rv: Dictionary = G.campaign.get_revive_info() if (camp_mode and G.campaign != null) else {}
	if not rv.is_empty() and not in_cutscene and G.player != null and G.player.alive:
		var t: float = float(rv.get("t", 0.0))
		var dur: float = float(rv.get("dur", 3.0))
		var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		_revive_label.text = "按住 E 救治 " + str(rv.get("name", "")) + "  " + str(int(k * 100.0)) + "%"
		_revive_label.visible = true
	elif _revive_label != null and _revive_label.visible:
		_revive_label.visible = false


func _update_squad_panel(infos: Array) -> void:
	for i in mini(infos.size(), _squad_blocks.size()):
		var info: Dictionary = infos[i]
		var blk: Dictionary = _squad_blocks[i]
		var nm: Label = blk["name"]
		nm.text = str(info.get("name", ""))
		var downed: bool = info.get("downed", false)
		var gone: bool = info.get("gone", false)
		var hp: float = float(info.get("hp", 0.0))
		var max_hp: float = float(info.get("max_hp", 100.0))
		var fill: ColorRect = blk["fill"]
		var st: Label = blk["status"]
		if gone:
			fill.anchor_right = 0.0
			fill.color = Color(0.4, 0.42, 0.44)
			st.text = "已撤离"
			st.add_theme_color_override("font_color", Color(0.55, 0.58, 0.6))
		elif downed:
			fill.anchor_right = 0.0
			fill.color = Color(1.0, 0.55, 0.22, 0.65 + 0.35 * (0.5 + 0.5 * sin(_hud_t * 6.0)))
			var self_left: float = float(info.get("self_left", 12.0))
			st.text = "自救中 " + str(maxi(1, int(ceil(self_left)))) + "s · 可救治"
			st.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
		else:
			fill.anchor_right = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
			fill.color = Color(0.35, 0.8, 0.5)
			st.text = "正常"
			st.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))


func _update_interact_prompt(camp_mode: bool, in_cutscene: bool) -> void:
	if _interact_box == null:
		return
	var info: Dictionary = G.campaign.get_interact_info() if (camp_mode and G.campaign != null) else {}
	var vis: bool = not info.is_empty() and not in_cutscene and G.player != null and G.player.alive
	if vis:
		var t: float = float(info.get("t", 0.0))
		var dur: float = float(info.get("dur", 3.0))
		_interact_label.text = "按住 E " + str(info.get("label", "交互"))
		_interact_fill.anchor_right = clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		if not _interact_box.visible:
			_interact_box.visible = true
	elif _interact_box.visible:
		_interact_box.visible = false


## ============ 每帧更新 ============
func update_hud(dt: float) -> void:
	var p = G.player
	_hud_t += dt
	if G.campaign != null and G.campaign != _campaign_src:
		if _campaign_src != null and is_instance_valid(_campaign_src):
			_campaign_src.dialogue_requested.disconnect(show_campaign_dialogue)
			_campaign_src.cutscene_card_requested.disconnect(show_campaign_card)
		_campaign_src = G.campaign
		G.campaign.dialogue_requested.connect(show_campaign_dialogue)
		G.campaign.cutscene_card_requested.connect(show_campaign_card)
		if G.campaign.running:
			G.campaign.request_objective_card()
	_consume_campaign_transition()
	var portal: Node = G.get("portal") as Node
	if portal != null and portal != _portal_src:
		if _portal_src != null and is_instance_valid(_portal_src):
			if _portal_src.has_signal("round_started"):
				_portal_src.round_started.disconnect(_on_portal_round_started)
			if _portal_src.has_signal("round_ended"):
				_portal_src.round_ended.disconnect(_on_portal_round_ended)
			if _portal_src.has_signal("portal_hint"):
				_portal_src.portal_hint.disconnect(_on_portal_hint)
		_portal_src = portal
		if portal.has_signal("round_started"):
			portal.round_started.connect(_on_portal_round_started)
		if portal.has_signal("round_ended"):
			portal.round_ended.connect(_on_portal_round_ended)
		if portal.has_signal("portal_hint"):
			portal.portal_hint.connect(_on_portal_hint)
	var camp_mode: bool = G.mode == "campaign"
	var portal_mode: bool = G.mode == "tdm" or G.mode == "br"
	var hide_top: bool = camp_mode or portal_mode
	if _minimap != null and _minimap.visible == camp_mode:
		_minimap.visible = not camp_mode
	if _top_bar != null and _top_bar.visible == hide_top:
		_top_bar.visible = not hide_top
	if not camp_mode:
		if _camp_obj != null and _camp_obj.visible:
			set_campaign_objective("")
		if _camp_dialogue_box != null and _camp_dialogue_box.visible:
			hide_campaign_dialogue()
		if _camp_card != null and _camp_card.visible:
			hide_campaign_card()
		if _camp_indicator != null and _camp_indicator.show_mark:
			_camp_indicator.clear()
		_zone_prev = false
		if _fade_rect != null and _fade_rect.visible:
			if _fade_tw != null and _fade_tw.is_valid():
				_fade_tw.kill()
			_fade_rect.visible = false
			_fade_rect.modulate.a = 0.0
	var in_cutscene: bool = camp_mode and G.campaign != null and G.campaign.is_cutscene()
	if in_cutscene and _camp_obj != null and _camp_obj.visible:
		set_campaign_objective("")
	if camp_mode and G.campaign != null and G.campaign.running and not in_cutscene:
		var otxt: String = G.campaign.objective_text()
		if _camp_obj != null and _camp_obj.text != otxt:
			_camp_obj.text = otxt
			_camp_obj.visible = otxt != ""
	_update_campaign_indicator(camp_mode, in_cutscene)
	_update_campaign_squad(camp_mode, in_cutscene)
	_update_interact_prompt(camp_mode, in_cutscene)
	if camp_mode and G.campaign != null and G.campaign.running and not in_cutscene:
		var zin: bool = G.campaign.zone_in()
		if zin != _zone_prev:
			_zone_prev = zin
			hint("已进入目标区域" if zin else "已离开目标区域")
		var zs: String = G.campaign.zone_status()
		if zs != "":
			_hint.text = zs
			_hint_t = 0.2
	else:
		_zone_prev = false
	if _banner_t > 0:
		_banner_t -= dt
		if _banner_t <= 0:
			_banner.visible = false
	if _hint_t > 0:
		_hint_t -= dt
		if _hint_t <= 0:
			_hint.text = ""
	if _dmg_t > 0:
		_dmg_t -= dt
		if _dmg_t <= 0:
			_dmg_arc.arc_opacity = 0
			_dmg_arc.queue_redraw()
	var hp0: float = p.health if p != null else 100.0
	var low_hp_fog: float = 0.0
	if hp0 < 30.0:
		low_hp_fog = (0.22 + 0.16 * sin(_hud_t * 7.0)) * (1.0 - hp0 / 30.0)
	var v_alpha: float = clampf(maxf(maxf(clampf(1 - hp0 / 100.0, 0, 0.7),
		0.3 if _dmg_t > 0 else 0.0), p.suppression * 0.45) + low_hp_fog, 0, 1)
	_dmg_vignette.modulate.a = v_alpha
	var ks := ""
	if G.mode != "campaign":
		if G.streak >= 2:
			ks = "[color=#ffd24d]连杀 ×" + str(G.streak) + "[/color]"
	_streak.text = ks

	if portal_mode and G.state == "playing":
		_update_portal_hud(portal)
	else:
		if _portal_bar != null and _portal_bar.visible:
			_portal_bar.visible = false
		if _br_zone != null:
			_br_zone.active = false
			if _br_zone.visible:
				_br_zone.visible = false

	var my_t: float = G.tickets[G.player.team]
	var en_t: float = G.tickets["ru" if G.player.team == "us" else "us"]
	var tick_us := "∞" if is_inf(my_t) else str(maxi(0, int(ceil(my_t))))
	var tick_ru := "∞" if is_inf(en_t) else str(maxi(0, int(ceil(en_t))))
	_set_text(_ticket_us, tick_us)
	_set_text(_ticket_ru, tick_ru)
	if tick_us != _last_tick_us:
		_last_tick_us = tick_us
		_pop_label(_ticket_us)
	if tick_ru != _last_tick_ru:
		_last_tick_ru = tick_ru
		_pop_label(_ticket_ru)
	_set_text(_timer, Utils.fmt_time(G.time))
	if G.mode == "campaign":
		_sb_title.text = "记分板 — 战役"
	elif G.mode == "breakthrough" and G.bt != null:
		_sector_label.visible = true
		_sector_label.text = "区域 " + str(mini(G.bt["sector"] + 1, G.bt["total"])) + "/" + str(G.bt["total"])
		for fid in _pips:
			var chip: FlagChip = _pips[fid]
			var f = _flag_by_id(fid)
			chip.visible = f != null and f.sector == G.bt["sector"]
			if f != null:
				_update_chip(chip, f)
		_sb_title.text = "记分板 — 突破模式(" + ("进攻方" if G.bt_player_side == "att" else "防守方") + ":友军)"
	elif G.mode == "tdm" or G.mode == "br":
		_sb_title.text = "记分板 — 门户 · " + ("团队死斗" if G.mode == "tdm" else "大逃杀")
	else:
		_sector_label.visible = false
		for fid in _pips:
			var chip: FlagChip = _pips[fid]
			var f = _flag_by_id(fid)
			chip.visible = f != null
			if f != null:
				_update_chip(chip, f)
		_sb_title.text = "记分板 — 征服模式"

	if p != null and p.alive:
		# 生命
		var hp := clampf(p.health, 0, 100)
		_hp_show = lerpf(_hp_show, hp, 1.0 - exp(-dt * 10.0))
		if hp < _last_hp_disp:
			_hp_flash_t = 0.45
		_last_hp_disp = hp
		_health_fill.anchor_right = _hp_show / 100.0
		var base_col := Color(0.95, 0.34, 0.28) if hp < 35 else Color(0.35, 0.8, 0.5)
		if _hp_flash_t > 0:
			_hp_flash_t -= dt
			base_col = base_col.lerp(Color(1, 1, 1), clampf(_hp_flash_t * 3.0, 0, 1))
		_health_fill.color = base_col
		_set_text(_health_num, str(int(ceil(_hp_show))))
		var gun = p.gun()
		# 载具 HUD 切换
		if p.vehicle != null:
			_update_vehicle_hud(p.vehicle)
		else:
			if _veh_panel != null and _veh_panel.visible:
				_veh_panel.visible = false
				_wpn_panel.visible = true
			if gun == null:
				return
			_update_weapon_hud(p, gun, dt)
		# 准星扩散
		var ch_op: float
		var spread_px: float
		var ret_style: String = ""
		if p.vehicle != null:
			ch_op = 0.0
			spread_px = 0.0
		elif gun == null or not gun.scope_sight() or gun.ads_amount < 0.7:
			# 光学瞄具开镜:镜内准星(红点/全息/战术镜)固定屏幕中心,不随散布
			if gun != null and gun.ads_amount > 0.6 and gun.ret_style() != "":
				ret_style = gun.ret_style()
				ch_op = 1.0
				spread_px = 0.0
			else:
				spread_px = clampf(gun.current_spread() / (G.camera.fov * PI / 180.0) * get_viewport().get_visible_rect().size.y, 2, 90) if gun != null else 2.0
				ch_op = 0.25 if (gun != null and gun.ads_amount > 0.6 and not gun.scope_sight()) else 1.0
		else:
			spread_px = 2.0
			ch_op = 0.0
		if _crosshair.kick_px > 0:
			_crosshair.kick_px = maxf(_crosshair.kick_px - dt * 18.0, 0.0)
		if absf(spread_px - _crosshair.spread_px) > 0.5 or ch_op != _crosshair.ch_opacity \
				or _crosshair.kick_px > 0.01 or ret_style != _crosshair.ret_style:
			_crosshair.spread_px = spread_px
			_crosshair.ch_opacity = ch_op
			_crosshair.ret_style = ret_style
			_crosshair.queue_redraw()
		# 高倍率狙击镜由 OpticScopeSystem 的圆形 PIP 着色器渲染;旧的 2D 全屏镜罩彻底停用。
		_scope.visible = false
		if _scope.visible:
			_scope.queue_redraw()
		# 占领进度
		var in_flag = null
		for f in G.flags:
			if Vector2(p.pos.x - f.pos.x, p.pos.z - f.pos.z).length() < f.radius:
				in_flag = f
				break
		if in_flag != null and G.mode != "campaign" and G.mode != "tdm" and G.mode != "br":
			_cap_bar.visible = true
			var prog: float = (in_flag.progress + 100) / 200.0
			_cap_fill.anchor_right = prog
			_cap_fill.color = UiTheme.H_TEAL if in_flag.progress >= 0 else UiTheme.H_ORANGE
			if in_flag.contested:
				_cap_fill.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(_hud_t * 6.0))
			else:
				_cap_fill.modulate.a = 1.0
			var fname: String = FLAG_NAMES.get(in_flag.id, in_flag.id + " 点")
			_set_text(_cap_text, fname + " — " + ("已控制" if in_flag.owner_team == G.player.team else ("敌方控制" if in_flag.owner_team != null else "中立")) + (" · 争夺中" if in_flag.contested else ""))
		else:
			_cap_bar.visible = false

	var in_br_spectate := false
	if G.mode == "br" and G.br != null and G.br.has_method("is_spectating"):
		in_br_spectate = bool(G.br.is_spectating())
	var sb_visible: bool = Input.is_action_pressed("scoreboard") and (G.state == "playing" or G.state == "dead") and not in_br_spectate
	if _scoreboard.visible != sb_visible:
		_scoreboard.visible = sb_visible
	if sb_visible:
		_update_scoreboard()

	# 小地图自绘由 Minimap._process 统一 30Hz 刷新(此处不再强制重绘,避免双节流抖动)


## 武器 HUD(右下):名称/图标/弹匣大字/备用/射击模式/配件/工具
func _update_weapon_hud(p, gun, dt: float) -> void:
	_set_text(_weapon_name, gun.def.cn)
	# 切枪/近战切换检测(图标滑动 + 数字滚动 + 配件淡入)
	var wid: String = gun.id + (":knife" if p.melee_active else "")
	if wid != _weapon_ctx:
		_weapon_ctx = wid
		_anim_weapon_switch(p, gun)
	if p.melee_active:
		_set_text(_weapon_name, "近战小刀")
		_set_text(_ammo_mag, "—")
		_set_text(_ammo_reserve, "")
		_ammo_fill.anchor_right = 0.0
		_ammo_fill.modulate.a = 1.0
		_ammo_fill.color = Color(0.7, 0.78, 0.85)
		_set_text(_fire_mode, "近战")
		_ammo_disp = 0.0
		_tools_row.set_items(_tool_items(p))
		return
	var ammo_now: int = gun.ammo
	if not gun.reloading and _last_ammo != -1 and ammo_now < _last_ammo:
		_crosshair.kick_px = minf(_crosshair.kick_px + 7.0, 16.0)
		_crosshair.queue_redraw()
	if ammo_now != _last_ammo:
		_last_ammo = ammo_now
		_pop_label(_ammo_mag)
	if gun.reloading:
		_set_text(_ammo_mag, "——")
		_ammo_disp = ammo_now
	else:
		# 数字滚动变化(切枪/换弹后平滑过渡)
		_ammo_disp = lerpf(_ammo_disp, ammo_now, 1.0 - exp(-dt * 18.0))
		_set_text(_ammo_mag, "%03d" % int(round(_ammo_disp)))
	_ammo_mag.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.3) if ammo_now <= gun.mag_cap * 0.25 else Color(1, 1, 1))
	_set_text(_ammo_reserve, str(gun.reserve))
	_ammo_fill.anchor_right = clampf(float(ammo_now) / float(maxi(1, gun.mag_cap)), 0, 1)
	if gun.reloading:
		_ammo_fill.modulate.a = 0.45 + 0.35 * (0.5 + 0.5 * sin(_hud_t * 13.0))
		_ammo_fill.color = Color(1.0, 0.72, 0.3)
	else:
		_ammo_fill.modulate.a = 1.0
		_ammo_fill.color = Color(1.0, 0.45, 0.3) if ammo_now <= gun.mag_cap * 0.25 else Color(0.7, 0.78, 0.85)
	# 射击模式(B 键切换:步枪 全自动⇄单发;其余按枪型显示)
	var fm_txt := "火箭推进" if gun.def.projectile else ("全自动" if gun.def.auto else ("泵动/半自动" if gun.def.pellets > 1 else "半自动"))
	if gun.def.kind == "rifle" and gun.def.auto:
		fm_txt = "单发 [B]" if gun.fire_mode == 1 else "全自动 [B]"
	_fire_mode.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.75) if fm_txt.begins_with("单发") else Color(0.8, 0.86, 0.9))
	_set_text(_fire_mode, fm_txt)
	_tools_row.set_items(_tool_items(p))
	var cls = WeaponsData.C()[p.class_id]
	_set_text(_class_icon, cls.icon)
	_class_icon.add_theme_color_override("font_color", cls.color)
	_gadget_info.visible = G.mode != "tdm"
	if G.mode != "tdm":
		_set_text(_gadget_info, "按 3 切换火箭筒" if p.gadget == "rpg" else (
			("2 霰弹枪 · F " + cls.gadget_cn + " ×" + str(p.gadget_count)) if (not cls.shotguns.is_empty() and p.guns.size() > 2)
			else ("F " + cls.gadget_cn + " ×" + str(p.gadget_count))))
	_set_text(_stance, "驾驶" if p.vehicle != null else ("滑铲" if p.slide_t > 0 else ("趴下" if p.prone else ("蹲下" if p.crouched else "站立"))))


## 工具行数据(投掷物/医疗包/工具;数量为 0 时置灰)
func _tool_items(p) -> Array:
	var out: Array = []
	out.append({ "kind": "grenade", "count": p.grenades })
	out.append({ "kind": "at_grenade", "count": p.at_grenades })
	out.append({ "kind": "mine", "count": p.at_mines })
	var gkind := "medkit"
	match p.gadget:
		"rpg":
			gkind = "rpg"
		"ammopack":
			gkind = "ammo"
		"sensor":
			gkind = "sensor"
	out.append({ "kind": gkind, "count": p.gadget_count })
	return out


## 切枪动画:图标滑动切换 + 配件淡入(≈0.2s,EaseOut)
func _anim_weapon_switch(p, gun) -> void:
	var kind: String = "melee" if p.melee_active else str(gun.def.kind)
	var sup: bool = bool(gun._suppressed)
	# 旧图标滑出
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_weapon_icon, "position:x", -34.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_weapon_icon, "modulate:a", 0.0, 0.09)
	tw.chain().tween_callback(func():
		_weapon_icon.set_weapon(kind, sup)
		_weapon_icon.position.x = 34.0)
	tw.tween_callback(func():
		var tw2 := create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(_weapon_icon, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_weapon_icon, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	# 配件标签重建 + 淡入
	var tags: Array = []
	if gun.mods_cfg is Dictionary:
		for slot in gun.mods_cfg:
			var mid: String = str(gun.mods_cfg[slot])
			if MOD_SHORT.has(mid):
				tags.append(MOD_SHORT[mid])
	_attach_label.text = " ▍" + " ▍".join(tags) if not tags.is_empty() else ""
	_attach_label.modulate.a = 0.0
	var atw := create_tween()
	atw.tween_property(_attach_label, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ammo_disp = gun.ammo
	_last_ammo = gun.ammo


## 载具 HUD(右下独立布局):耐久/武备冷却/锁定/乘员/速度/档位/指南针/高度/雷达
func _update_vehicle_hud(v) -> void:
	if _wpn_panel != null and _wpn_panel.visible:
		_wpn_panel.visible = false
		_veh_panel.visible = true
	var is_air: bool = v.get("air") == true
	var vname: String = str(v.craft_name) if is_air else str(v.def.get("vehicle_name", "载具"))
	_set_text(_veh_name, vname)
	# 乘员席位(双人乘坐:驾驶员 + 炮手/乘客;玩家与 NPC 均可)
	var crew_txt := "驾驶 "
	crew_txt += "你" if v.driver == G.player else ("NPC" if v.driver != null else "—")
	crew_txt += " · " + ("炮手 " if v.has_turret() else "乘客 ")
	crew_txt += "你" if v.gunner == G.player else ("NPC" if v.gunner != null else "—")
	_set_text(_veh_crew, crew_txt)
	# 耐久
	var hp_max: float = float(v.def.get("hp", v.max_hp if v.get("max_hp") != null else 100.0)) if not is_air else float(v.max_hp)
	var hp: float = float(v.hp) if not is_air else float(v.hp)
	var hp_frac := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
	_veh_hp_fill.anchor_right = hp_frac
	_veh_hp_fill.color = Color(0.95, 0.34, 0.28) if hp_frac < 0.25 else (Color(1.0, 0.55, 0.22) if hp_frac < 0.55 else Color(0.65, 0.78, 0.84))
	_set_text(_veh_hp_pct, str(int(round(hp_frac * 100.0))) + "%")
	# 武备冷却
	var wpn_frac := 0.0
	var wpn_txt := "无武器"
	if is_air:
		var rt: float = float(v.rocket_t)
		if rt > 0.0:
			wpn_frac = clampf(rt / 6.0, 0.0, 1.0)
			wpn_txt = "火箭弹装填 %0.1fS" % rt
		else:
			wpn_txt = "火箭弹就绪"
	elif v.has_turret():
		var ct: float = float(v.cannon_t)
		if ct > 0.0:
			wpn_frac = clampf(ct / 6.0, 0.0, 1.0)
			wpn_txt = "主炮装填 %0.1fS" % ct
		else:
			wpn_txt = "主炮就绪"
		# [8/10] 坦克:炮弹数量 + 炮塔方向/仰角
		if v.is_tank():
			if v.cannon_t > 0.0 and v.cannon_ammo <= 0:
				wpn_txt = "补弹中 %0.1fS" % ct
			else:
				wpn_txt = "炮弹 %d · %s" % [v.cannon_ammo, wpn_txt]
	# [载具 HUD v2] 炮弹数量(大号):坦克显示备弹,机炮载具显示 ∞
	if is_air:
		_set_text(_veh_ammo, "∞")
		_set_text(_veh_ammo_tag, "火箭弹")
	elif v.has_turret():
		if v.is_tank():
			_set_text(_veh_ammo_tag, "炮弹")
			_set_text(_veh_ammo, str(v.cannon_ammo))
		else:
			_set_text(_veh_ammo_tag, "弹药")
			_set_text(_veh_ammo, "∞")
	else:
		_set_text(_veh_ammo_tag, "炮弹")
		_set_text(_veh_ammo, "--")
	# [载具 HUD v2] 坐标与附加数据
	var pos_x := int(round(v.pos.x))
	var pos_z := int(round(v.pos.z))
	_set_text(_veh_pos, "X %s · Z %s" % [str(pos_x).pad_zeros(4) if pos_x >= 0 else "-" + str(-pos_x).pad_zeros(3), str(pos_z).pad_zeros(4) if pos_z >= 0 else "-" + str(-pos_z).pad_zeros(3)])
	if is_air:
		_set_text(_veh_data, "海拔 %dM · 航向 %03d°" % [int(round(v.pos.y)), int(round(wrapf(rad_to_deg(-v.yaw), 0.0, 360.0)))])
	elif v.has_turret():
		_set_text(_veh_data, "航向 %03d° · 目标 %03d°" % [
			int(round(wrapf(rad_to_deg(-v.yaw), 0.0, 360.0))),
			int(round(wrapf(rad_to_deg(-(v.yaw + v.turret_yaw)), 0.0, 360.0)))])
	else:
		_set_text(_veh_data, "航向 %03d°" % int(round(wrapf(rad_to_deg(-v.yaw), 0.0, 360.0))))
	# [8/10] 炮塔方向/仰角(炮塔载具;指南针旁附加)
	var ang_txt := ""
	if v.has_turret():
		var deg: float = wrapf(rad_to_deg(-(v.yaw + v.turret_yaw)), 0.0, 360.0)
		var elev: float = rad_to_deg(v.turret_pitch)
		ang_txt = "炮塔 %03d° · 仰角 %+d°" % [int(deg), int(elev)]
	_veh_alt.text = ang_txt if ang_txt != "" else ""
	_veh_alt.visible = ang_txt != ""
	_veh_wpn_fill.anchor_right = 1.0 - wpn_frac
	_veh_wpn_fill.color = Color(0.16, 0.78, 0.86) if wpn_frac <= 0.01 else Color(1.0, 0.55, 0.22)
	_set_text(_veh_wpn_label, wpn_txt)
	# 锁定
	var locked: bool = G.lock_target != null
	if locked and not _veh_lock.visible:
		_veh_lock.visible = true
		_veh_lock.text = "● 导弹锁定"
		if _veh_lock_tw != null and _veh_lock_tw.is_valid():
			_veh_lock_tw.kill()
		_veh_lock_tw = create_tween()
		_veh_lock_tw.set_loops()
		_veh_lock_tw.tween_property(_veh_lock, "modulate:a", 0.35, 0.35)
		_veh_lock_tw.tween_property(_veh_lock, "modulate:a", 1.0, 0.35)
	elif not locked and _veh_lock.visible:
		_veh_lock.visible = false
		if _veh_lock_tw != null and _veh_lock_tw.is_valid():
			_veh_lock_tw.kill()
	# 速度 / 档位
	var spd: float = float(v.airspeed if is_air else v.speed)
	var max_spd: float = float(v.def.get("max_speed", 40.0)) if not is_air else 80.0
	_set_text(_veh_speed, str(int(round(spd * 3.6))))
	var gear_txt := "N"
	if is_air:
		gear_txt = "F" if v.mode != "landing" else "LDG"
	elif spd > 0.8:
		gear_txt = "D" + str(maxi(1, mini(4, 1 + int(spd / max_spd * 4.0))))
	elif spd < -0.8:
		gear_txt = "R"
	_set_text(_veh_gear, gear_txt)
	# 指南针
	var yaw: float = v.yaw if not is_air else v.yaw
	_veh_compass.set_heading(wrapf(rad_to_deg(-yaw), 0.0, 360.0))
	# 高度/仰角(飞机显示高度;地面炮塔载具显示炮塔方向/仰角)
	if is_air:
		_set_text(_veh_alt, "高度 %dM · 空速 %d" % [int(round(v.pos.y)), int(round(spd * 3.6))])
		_veh_alt.visible = true
	else:
		_veh_alt.visible = ang_txt != ""
	_radar.queue_redraw()


func _flag_by_id(fid: String):
	for f in G.flags:
		if f.id == fid:
			return f
	return null


## 顶部据点芯片状态(状态变化才写,减少重绘)
func _update_chip(chip: FlagChip, f) -> void:
	var key := str(f.owner_team) + "|" + str(f.contested) + "|" + str(int(f.progress)) + "|" + str(f.zone_locked)
	if chip.get_meta("chip_state", "") == key:
		return
	chip.set_meta("chip_state", key)
	chip.owner_team = "" if f.owner_team == null else f.owner_team
	chip.contested = f.contested
	chip.progress = f.progress
	chip.zone_locked = f.zone_locked


func _set_text(l: Label, s: String) -> void:
	if l.text != s:
		l.text = s


func _pop_label(l: Label) -> void:
	if not is_instance_valid(l) or not l.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if _pop_times.has(l) and now - _pop_times[l] < 200:
		return
	_pop_times[l] = now
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE
	if _pop_tweens.has(l) and is_instance_valid(_pop_tweens[l]):
		_pop_tweens[l].kill()
	var tw := l.create_tween()
	_pop_tweens[l] = tw
	tw.tween_property(l, "scale", Vector2(1.14, 1.14), 0.06)
	tw.tween_property(l, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_scoreboard() -> void:
	var us_list := [{ "name": "你(玩家)", "kills": G.stats["kills"], "deaths": G.stats["deaths"], "me": true }]
	var ru_list := []
	for b in G.bots:
		var e := { "name": b.bot_name, "kills": b.kills, "deaths": b.deaths, "me": false }
		if b.team == G.player.team:
			us_list.append(e)
		else:
			ru_list.append(e)
	us_list.sort_custom(func(a, b): return a["kills"] > b["kills"])
	ru_list.sort_custom(func(a, b): return a["kills"] > b["kills"])
	_sb_us.text = _mk_table("友军", us_list, US_HEX)
	_sb_ru.text = _mk_table("敌军", ru_list, RU_HEX)


func _mk_table(title: String, list: Array, hex_col: String) -> String:
	var s := "[color=" + hex_col + "][b]" + title + "[/b][/color]\n"
	s += "[color=#7c8b9a]士兵 — 击杀/阵亡[/color]\n"
	for e in list:
		var row: String = e["name"] + "　—　" + str(e["kills"]) + " / " + str(e["deaths"])
		if e["me"]:
			row = "[b]" + row + "[/b]"
		s += row + "\n"
	return s


## ============ 门户模式 HUD ============
func _p_val(p: Node, key: String, def_val):
	if p == null:
		return def_val
	var v = p.get(key)
	return v if v != null else def_val


func _on_portal_round_started(mode: String, _map_id: String, _player_count: int) -> void:
	_portal_active = true
	_portal_last_result = {}
	if G.menus != null:
		G.menus.hide_end()
	if G.mode != mode and (mode == "tdm" or mode == "br"):
		G.mode = mode


func _on_portal_round_ended(result: Dictionary) -> void:
	_portal_active = false
	_portal_last_result = result if result is Dictionary else {}
	_portal_style = ""
	if G.menus != null:
		G.menus.show_portal_end(_portal_last_result)


func _on_portal_hint(text: String) -> void:
	hint(str(text))


func _update_portal_hud(portal: Node) -> void:
	if _portal_bar == null:
		return
	if not _portal_bar.visible:
		_portal_bar.visible = true
	if _portal_style != G.mode:
		_portal_style = G.mode
		_portal_apply_style(G.mode)
	if G.mode == "tdm":
		var us_s: int = int(_p_val(portal, "tdm_us", G.tickets.get("us", 0)))
		var ru_s: int = int(_p_val(portal, "tdm_ru", G.tickets.get("ru", 0)))
		var target: int = int(_p_val(portal, "tdm_target", 50))
		var tleft: float = float(_p_val(portal, "tdm_time_left", -1.0))
		_set_text(_pb_left_l, str(maxi(0, us_s)))
		_set_text(_pb_mid, ":")
		_set_text(_pb_right_l, str(maxi(0, ru_s)))
		var ttxt := "剩余 " + Utils.fmt_time(tleft) if tleft >= 0.0 else "用时 " + Utils.fmt_time(G.time)
		_set_text(_portal_sub, ttxt + " · 目标击杀 " + str(target))
		return
	var alive: int = int(_p_val(portal, "br_alive", 100))
	var total: int = int(_p_val(portal, "br_total", 100))
	var alive_t := -1
	var total_t := 0
	var br_mode: Node = G.get("br")
	if br_mode != null and br_mode.get("br_alive_teams") != null:
		alive_t = int(br_mode.get("br_alive_teams"))
		total_t = int(br_mode.get("br_total_teams"))
	elif portal != null and portal.get("br_alive_teams") != null:
		alive_t = int(portal.get("br_alive_teams"))
		total_t = int(portal.get("br_total_teams"))
	if alive_t >= 0:
		_set_text(_pb_left_l, "存活 " + str(maxi(0, alive_t)) + " 队")
		_set_text(_pb_mid, "/")
		_set_text(_pb_right_l, str(maxi(0, total_t)) + " 队")
	else:
		_set_text(_pb_left_l, "存活 " + str(maxi(0, alive)))
		_set_text(_pb_mid, "/")
		_set_text(_pb_right_l, str(maxi(0, total)))
	var zc: Variant = _p_val(portal, "zone_center", null)
	var zr: float = float(_p_val(portal, "zone_radius", 0.0))
	var br_jumping := false
	var br_mode2: Node = G.get("br")
	if br_mode2 != null and br_mode2.has_method("player_jump_active"):
		br_jumping = bool(br_mode2.player_jump_active())
	if br_jumping:
		_br_zone.active = false
		if _br_zone.visible:
			_br_zone.visible = false
		_set_text(_portal_sub, "跳伞中 — 落地后注意安全区")
	elif zc is Vector3 and zr > 0.0 and G.player != null:
		var d2 := Vector2(zc.x - G.player.pos.x, zc.z - G.player.pos.z).length()
		var in_zone: bool = d2 <= zr
		_br_zone.active = true
		_br_zone.zone_center = zc
		_br_zone.zone_radius = zr
		_br_zone.inside = in_zone
		_br_zone.dist = maxf(zr - d2, 0.0) if in_zone else maxf(d2 - zr, 0.0)
		_br_zone.visible = true
		_set_text(_portal_sub, ("圈内 · 距圈缘 " if in_zone else "圈外 · 距毒圈 ") + str(int(round(_br_zone.dist))) + "m")
	else:
		_br_zone.active = false
		if _br_zone.visible:
			_br_zone.visible = false
		_set_text(_portal_sub, "等待毒圈收缩…")


func _portal_apply_style(mode: String) -> void:
	if mode == "tdm":
		_pb_left.add_theme_stylebox_override("panel",
			UiTheme.hud_frost(0.22, Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.4), 1, 3, 10))
		_pb_right.add_theme_stylebox_override("panel",
			UiTheme.hud_frost(0.22, Color(UiTheme.H_ORANGE.r, UiTheme.H_ORANGE.g, UiTheme.H_ORANGE.b, 0.4), 1, 3, 10))
		_pb_left_l.add_theme_font_size_override("font_size", 22)
		_pb_right_l.add_theme_font_size_override("font_size", 22)
		_pb_left_l.add_theme_color_override("font_color", Color(0.72, 0.94, 0.98))
		_pb_right_l.add_theme_color_override("font_color", Color(1.0, 0.8, 0.62))
	else:
		_pb_left.add_theme_stylebox_override("panel",
			UiTheme.hud_frost(0.22, Color(UiTheme.H_GREEN.r, UiTheme.H_GREEN.g, UiTheme.H_GREEN.b, 0.4), 1, 3, 10))
		_pb_right.add_theme_stylebox_override("panel",
			UiTheme.hud_frost(0.22, Color(0.55, 0.6, 0.66, 0.4), 1, 3, 10))
		_pb_left_l.add_theme_font_size_override("font_size", 14)
		_pb_right_l.add_theme_font_size_override("font_size", 14)
		_pb_left_l.add_theme_color_override("font_color", Color(0.62, 0.9, 0.7))
		_pb_right_l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
