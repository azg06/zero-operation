class_name HUD extends CanvasLayer
## 战斗 HUD(对应 hud.js):准星/命中标记/狙击镜/小地图/票数/击杀播报/记分板…

## ---------------- 准星 ----------------
class Crosshair extends Control:
	var spread_px := 4.0
	var ch_opacity := 1.0
	var kick_px := 0.0   # 后坐力联动:射击时上跳,随相机后坐衰减回落

	func _draw() -> void:
		var c := size / 2.0 + Vector2(0, -kick_px)
		var col := Color(1, 1, 1, 0.85 * ch_opacity)
		var L := 9.0
		var g := spread_px
		draw_line(c + Vector2(0, -g - L), c + Vector2(0, -g), col, 2)
		draw_line(c + Vector2(0, g), c + Vector2(0, g + L), col, 2)
		draw_line(c + Vector2(-g - L, 0), c + Vector2(-g, 0), col, 2)
		draw_line(c + Vector2(g, 0), c + Vector2(g + L, 0), col, 2)
		draw_rect(Rect2(c.x - 1, c.y - 1, 2, 2), col)


## ---------------- 命中标记(X 形 + 缩放弹出动画) ----------------
class Hitmarker extends Control:
	var t := 0.0
	var kill := false
	var head := false

	func show_hit(p_kill: bool, p_head: bool) -> void:
		kill = p_kill
		head = p_head
		t = 0.35
		visible = true

	func _process(dt: float) -> void:
		if t > 0:
			t -= dt
			if t <= 0:
				visible = false
			else:
				queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var col := Color(1, 0.25, 0.2) if kill else (Color(1, 0.6, 0.15) if head else Color(1, 1, 1))
		col.a = clampf(t / 0.35, 0, 1)
		# 缩放弹出:出现瞬间放大,快速回落到 1
		var k: float = t / 0.35
		var s := 1.0 + 0.45 * pow(maxf(1 - k, 0), 2.2)
		var L := (10.0 if kill else 8.0) * s
		var g := (4.0 * s)
		var w := 2.5 if kill else 2.0
		var w2 := w * s
		draw_line(c + Vector2(-g - L, -g - L), c + Vector2(-g, -g), col, w2)
		draw_line(c + Vector2(g, -g), c + Vector2(g + L, -g - L), col, w2)
		draw_line(c + Vector2(-g - L, g + L), c + Vector2(-g, g), col, w2)
		draw_line(c + Vector2(g, g), c + Vector2(g + L, g + L), col, w2)
		# 击杀:附加扩散光环
		if kill:
			draw_arc(c, (6 + 14 * k) * s, 0, TAU, 24, Color(1, 0.4, 0.3, 0.7 * k), 2.0)


## ---------------- 夜视仪敌人高亮(全屏标记,穿墙可见) ----------------
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
		# 敌方步兵(头部)
		for b in G.bots:
			if b == null or not b.alive or b.team == p.team:
				continue
			_draw_marker(cam, cpos, Vector3(b.pos.x, b.pos.y + 1.4, b.pos.z), vr)
		# 敌方载具(有驾驶员的车体中心;无驾驶员无法判定阵营,跳过)
		for v in G.vehicles:
			if v == null or v.dead or v.driver == null or v.driver.team == p.team:
				continue
			_draw_marker(cam, cpos, Vector3(v.pos.x, v.pos.y + 1.8, v.pos.z), vr)
		# 敌方飞机
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


## ---------------- 载具瞄准辅助(炮塔类:主准星 + 炮管指向指示点) ----------------
class VehicleAim extends Control:
	func _process(_dt: float) -> void:
		var vis: bool = G.player != null and G.player.alive and G.player.vehicle != null \
			and G.player.vehicle.has_turret() and G.state == "playing"
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
			# 炮口在相机后方:unproject 会产生镜像坐标,改用炮管方向在相机系中的投影推算屏缘指向
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
		# 炮管指向指示点(小菱形)
		var dcol := Color(1, 0.78, 0.3)
		var ds := 7.0
		var pts := PackedVector2Array([
			sp + Vector2(0, -ds), sp + Vector2(ds, 0), sp + Vector2(0, ds), sp + Vector2(-ds, 0)])
		draw_colored_polygon(pts, Color(dcol.r, dcol.g, dcol.b, 0.3 if aligned else 0.85))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), dcol, 1.5)
		if not aligned:
			draw_line(center, sp, Color(1, 0.78, 0.3, 0.35), 1.0)
			draw_string(UiTheme.mono_font(), sp + Vector2(-18, -12), "转炮",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 13, dcol)
		# 主准星(坦克风格:十字 + 外圈;偏差<80px 就绪 → 变红实心)
		var col := Color(1, 0.3, 0.25) if aligned else Color(0.85, 0.95, 1, 0.9)
		var gap := 6.0
		var L := 12.0
		draw_line(center + Vector2(0, -gap - L), center + Vector2(0, -gap), col, 2)
		draw_line(center + Vector2(0, gap), center + Vector2(0, gap + L), col, 2)
		draw_line(center + Vector2(-gap - L, 0), center + Vector2(-gap, 0), col, 2)
		draw_line(center + Vector2(gap, 0), center + Vector2(gap + L, 0), col, 2)
		draw_arc(center, 16.0, 0, TAU, 32, Color(col.r, col.g, col.b, col.a * 0.8), 1.5)
		if aligned:
			draw_circle(center, 2.2, col)


## ---------------- 狙击镜(镜内放大:清晰视窗 + 黑色目镜环 + 分划) ----------------
class ScopeOverlay extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.44
		# 目镜外全黑(圆形视窗之外)
		var dark := Color(0, 0, 0, 1)
		draw_rect(Rect2(0, 0, size.x, c.y - r), dark)                        # 上
		draw_rect(Rect2(0, c.y + r, size.x, size.y - c.y - r), dark)         # 下
		draw_rect(Rect2(0, c.y - r, c.x - r, 2 * r), dark)                   # 左
		draw_rect(Rect2(c.x + r, c.y - r, size.x - c.x - r, 2 * r), dark)    # 右
		# 四角圆弧补全黑 + 目镜筒厚度(多层环形渐变模拟金属镜筒)
		draw_arc(c, r * 1.45, 0, TAU, 72, Color(0, 0, 0, 1), r * 0.9)
		draw_arc(c, r * 1.03, 0, TAU, 72, Color(0.02, 0.02, 0.02, 1), r * 0.1)
		draw_arc(c, r * 1.0, 0, TAU, 72, Color(0.12, 0.13, 0.14, 0.95), 5.0)    # 镜筒金属内沿
		draw_arc(c, r * 0.985, 0, TAU, 72, Color(0.0, 0.0, 0.0, 0.85), 3.0)     # 内缘阴影
		# 镜内暗角(视窗边缘轻微压暗,模拟光学渐晕)
		draw_arc(c, r * 0.9, 0, TAU, 72, Color(0, 0, 0, 0.12), r * 0.18)
		# 分划:细十字线(中心留隙) + 密位点
		var col := Color(0.02, 0.02, 0.02, 0.92)
		draw_line(c + Vector2(-r, 0), c + Vector2(-7, 0), col, 1.6)
		draw_line(c + Vector2(7, 0), c + Vector2(r, 0), col, 1.6)
		draw_line(c + Vector2(0, -r), c + Vector2(0, -7), col, 1.6)
		draw_line(c + Vector2(0, 7), c + Vector2(0, r), col, 1.6)
		for i in range(-4, 5):
			if i == 0:
				continue
			var off: float = i * r / 5.0
			draw_circle(c + Vector2(off, 0), 2.0, col)
			draw_circle(c + Vector2(0, off), 2.0, col)
		# 中心瞄准点
		draw_circle(c, 1.8, Color(0.05, 0.05, 0.05, 0.95))


## ---------------- 伤害方向弧 ----------------
class DamageArc extends Control:
	var rel_angle := 0.0
	var arc_opacity := 0.0

	func _draw() -> void:
		if arc_opacity <= 0:
			return
		var c := size / 2.0
		var r := 60.0
		var col := Color(1, 0.2, 0.15, arc_opacity)
		var a0 := rel_angle - 0.6
		var a1 := rel_angle + 0.6
		draw_arc(c, r, a0, a1, 12, col, 6)


## ---------------- 战役目标指示器(COD 屏幕边缘黄三角 + 距离米数) ----------------
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
		var col := Color(1.0, 0.85, 0.25)
		var sp: Vector2 = cam.unproject_position(target)
		var center := size / 2.0
		# 目标在屏幕内(留 34px 边距):画小菱形标记 + 距离
		if not cam.is_position_behind(target) and Rect2(Vector2.ZERO, size).grow(-34.0).has_point(sp):
			var d2 := 9.0
			var pts := PackedVector2Array([
				sp + Vector2(0, -d2), sp + Vector2(d2, 0),
				sp + Vector2(0, d2), sp + Vector2(-d2, 0)])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85))
			draw_string(UiTheme.mono_font(), sp + Vector2(-26, d2 + 16), str(int(round(dist))) + "m",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 12, col)
			return
		# 屏幕外 / 相机后方:边缘黄三角(方向指向目标)
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


## ---------------- 军事四角括号装饰(挂到面板上) ----------------
class Corners extends Control:
	var bracket_col := Color(0.35, 0.75, 0.85, 0.8)
	var bar_len := 10.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var sz := size
		var col := bracket_col
		var l := bar_len
		var w := 1.6
		# 左上
		draw_line(Vector2(0, l), Vector2(0, 0), col, w)
		draw_line(Vector2(0, 0), Vector2(l, 0), col, w)
		# 右上
		draw_line(Vector2(sz.x - l, 0), Vector2(sz.x, 0), col, w)
		draw_line(Vector2(sz.x, 0), Vector2(sz.x, l), col, w)
		# 左下
		draw_line(Vector2(0, sz.y - l), Vector2(0, sz.y), col, w)
		draw_line(Vector2(0, sz.y), Vector2(l, sz.y), col, w)
		# 右下
		draw_line(Vector2(sz.x - l, sz.y), Vector2(sz.x, sz.y), col, w)
		draw_line(Vector2(sz.x, sz.y), Vector2(sz.x, sz.y - l), col, w)


# ==================== 主 HUD ====================
var spawn_point = null                 # 玩家自选前线出生点(旗帜对象)
var spawn_mate = null                  # 玩家自选小队成员(部署到其身旁)

var _crosshair: Crosshair
var _hitmarker: Hitmarker
var _scope: ScopeOverlay
var _dmg_arc: DamageArc
var _dmg_vignette: TextureRect
var _nvg: NightVisionOverlay
var _veh_aim: VehicleAim
var _minimap: Minimap
var _ticket_us: Label
var _ticket_ru: Label
var _pips: Dictionary = {}
var _sector_label: Label
var _timer: Label
var _killfeed: VBoxContainer
var _banner: Label
var _cap_bar: PanelContainer
var _cap_fill: ColorRect
var _cap_text: Label
var _health_fill: ColorRect
var _health_num: Label
var _class_icon: Label
var _gadget_info: Label
var _stance: Label
var _weapon_name: Label
var _ammo_mag: Label
var _ammo_reserve: Label
var _fire_mode: Label
var _nade_count: Label
var _hint: Label
var _streak: RichTextLabel
var _scoreboard: PanelContainer
var _sb_us: RichTextLabel
var _sb_ru: RichTextLabel
var _sb_title: Label
var _camp_obj: Label                  # 战役目标文本(顶部中央,票数行下方)
var _camp_dialogue: Label             # 战役字幕正文(底部中央)
var _camp_dialogue_name: Label        # 战役字幕角色名(角色色)
var _camp_dialogue_box: PanelContainer
var _camp_dialogue_tw: Tween
var _camp_card: Label                 # 战役大字卡(开场标题卡 / 目标点名卡)
var _camp_card_tw: Tween
var _camp_indicator: CampaignIndicator # 战役目标屏幕边缘指示器(COD 黄三角)
var _squad_panel: PanelContainer      # 战役小队状态栏(左下,生命面板上方)
var _squad_row: HBoxContainer
var _squad_blocks: Array = []         # [{box,name,fill,status}]
var _revive_label: Label              # 救治读条提示(底部中央,提示行上方)
var _interact_box: PanelContainer     # 交互目标提示(底部中央:按住 E + label + 进度条)
var _interact_label: Label
var _interact_fill: ColorRect
var _fade_rect: ColorRect             # 全屏黑(章末转场/重试淡入;独立于 _hud_root,死亡时仍可见)
var _fade_tw: Tween
var _zone_prev := false               # 目标区域进入/离开轻提示去抖(上一帧状态)
var _top_bar: HBoxContainer           # 顶部票数/旗帜/计时条(战役模式隐藏)
var _campaign_connected := false      # 战役 signal 懒连接标记(campaign 由 main 后创建)

var _banner_t := 0.0
var _hint_t := 0.0
var _dmg_t := 0.0
var _hud_root: Control
var _pip_sb := {}
var _mm_t := 0.0
var _hud_t := 0.0                 # 累计时间(低血量脉冲/占领进度脉动)
var _hp_show := 100.0             # 血量显示值(平滑下落)
var _hp_flash_t := 0.0            # 血量条受击白闪
var _last_hp_disp := 100.0        # 上一帧实际血量(检测受击)
var _last_ammo := -1              # 上一帧弹匣量(检测射击/换弹)
var _last_tick_us := ""
var _last_tick_ru := ""
var _ammo_bar: ColorRect          # 弹匣余量条背景
var _ammo_fill: ColorRect         # 弹匣余量条填充
var _flash: ColorRect             # 命中/击杀屏幕微闪光
var _pop_times: Dictionary = {}   # 弹出动画节流时间戳(0.2s 内同一控件只弹一次)
var _pop_tweens: Dictionary = {}  # 弹出动画引用(新建前杀掉旧 tween)

const US_HEX := "#00ff88"
const RU_HEX := "#ff5500"


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
	# 旗帜指示样式缓存(原每帧每旗新建 StyleBox,现建一次复用)
	_pip_sb = {
		"us": UiTheme.stylebox(Color(0.15, 0.35, 0.6, 0.9), Color.html("#00ff88"), 1, 3, 2),
		"ru": UiTheme.stylebox(Color(0.6, 0.18, 0.15, 0.9), Color.html("#ff5500"), 1, 3, 2),
		"neutral": UiTheme.stylebox(Color(0.15, 0.17, 0.2, 0.85), Color(0.4, 0.42, 0.45), 1, 3, 2),
		"warn": UiTheme.stylebox(Color(0.5, 0.4, 0.1, 0.9), Color(1, 0.85, 0.3), 1, 3, 2),
	}

	# ---- 夜视仪敌人高亮(最下层:命中标记/准星之下) ----
	_nvg = NightVisionOverlay.new()
	_nvg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nvg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nvg.visible = false
	_hud_root.add_child(_nvg)

	# ---- 准星/命中标记/狙击镜/伤害弧/暗角(全屏层) ----
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_crosshair)
	_veh_aim = VehicleAim.new()
	_veh_aim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veh_aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veh_aim.visible = false
	_hud_root.add_child(_veh_aim)
	_hitmarker = Hitmarker.new()
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hitmarker.visible = false
	_hud_root.add_child(_hitmarker)
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
	# 命中/击杀屏幕微闪光(全屏白闪,瞬间起灭)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 1)
	_flash.modulate.a = 0.0
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_flash)

	# ---- 左上:小地图(自带背景+边框,与内容同坐标系绘制,杜绝错位) ----
	_minimap = Minimap.new()
	_minimap.position = Vector2(16, 16)
	_minimap.custom_minimum_size = Vector2(228, 228)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_root.add_child(_minimap)

	# ---- 顶部中央:票数 + 旗帜 + 计时(战役模式整条隐藏) ----
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.position = Vector2(0, 12)
	_top_bar.add_theme_constant_override("separation", 14)
	_top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_top_bar)
	var us_box := PanelContainer.new()
	us_box.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.08, 0.17, 0.3, 0.88), Color.html("#00ff88"), 1, 3, 12))
	us_box.custom_minimum_size = Vector2(96, 40)
	_top_bar.add_child(us_box)
	_ticket_us = UiTheme.make_label("400", 22, Color(0.65, 0.82, 1))
	_ticket_us.add_theme_font_override("font", UiTheme.mono_font())
	_ticket_us.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticket_us.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ticket_us.set_anchors_preset(Control.PRESET_FULL_RECT)
	us_box.add_child(_ticket_us)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(mid)
	_sector_label = UiTheme.make_label("", 13, Color(1, 0.85, 0.5))
	_sector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sector_label.visible = false
	mid.add_child(_sector_label)
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 5)
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(pip_row)
	for fid in ["A", "B", "C", "D", "E"]:
		var pip := UiTheme.make_label(fid, 14, Color(0.7, 0.72, 0.75))
		pip.custom_minimum_size = Vector2(28, 24)
		pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pip.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.15, 0.17, 0.2, 0.85), Color(0.4, 0.42, 0.45), 1, 3, 2))
		pip_row.add_child(pip)
		_pips[fid] = pip
	_timer = UiTheme.make_label("00:00", 13, Color(0.72, 0.75, 0.78))
	_timer.add_theme_font_override("font", UiTheme.mono_font())
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_timer)
	var ru_box := PanelContainer.new()
	ru_box.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.3, 0.1, 0.09, 0.88), Color.html("#ff5500"), 1, 3, 12))
	ru_box.custom_minimum_size = Vector2(96, 40)
	_top_bar.add_child(ru_box)
	_ticket_ru = UiTheme.make_label("400", 22, Color(1, 0.6, 0.55))
	_ticket_ru.add_theme_font_override("font", UiTheme.mono_font())
	_ticket_ru.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticket_ru.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ticket_ru.set_anchors_preset(Control.PRESET_FULL_RECT)
	ru_box.add_child(_ticket_ru)
	# 军事四角括号(票数面板)
	for box in [us_box, ru_box]:
		var cr := Corners.new()
		cr.bracket_col = Color(0.5, 0.85, 0.95, 0.5)
		cr.bar_len = 8.0
		box.add_child(cr)

	# ---- 右上:击杀播报 ----
	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_killfeed.grow_vertical = Control.GROW_DIRECTION_END
	_killfeed.position = Vector2(-16, 70)
	_killfeed.custom_minimum_size = Vector2(380, 0)
	_killfeed.add_theme_constant_override("separation", 3)
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_killfeed)

	# ---- 中央横幅(容器居中) ----
	var banner_row := HBoxContainer.new()
	banner_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_row.position = Vector2(0, 118)
	banner_row.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(banner_row)
	_banner = UiTheme.make_label("", 22, Color(1, 0.92, 0.7))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_banner.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.04, 0.05, 0.07, 0.78), Color(0.55, 0.48, 0.3, 0.7), 1, 4, 16))
	banner_row.add_child(_banner)

	# ---- 战役目标(顶部中央,票数行下方,金黄小字;居中容器不挤压/遮挡左上小地图) ----
	var camp_obj_row := HBoxContainer.new()
	camp_obj_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	camp_obj_row.offset_top = 58
	camp_obj_row.offset_bottom = 104
	camp_obj_row.alignment = BoxContainer.ALIGNMENT_CENTER
	camp_obj_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(camp_obj_row)
	_camp_obj = UiTheme.make_label("", 14, Color(1, 0.85, 0.5))
	_camp_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camp_obj.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_camp_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_obj.custom_minimum_size = Vector2(640, 0)
	_camp_obj.visible = false
	_camp_obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_obj.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.04, 0.05, 0.07, 0.7), Color(0.6, 0.5, 0.25, 0.55), 1, 3, 10))
	camp_obj_row.add_child(_camp_obj)

	# ---- 占领进度 ----
	_cap_bar = PanelContainer.new()
	_cap_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cap_bar.position = Vector2(-150, 186)  # 半宽偏移回正中
	_cap_bar.custom_minimum_size = Vector2(300, 48)
	_cap_bar.visible = false
	_cap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_bar.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.04, 0.05, 0.07, 0.82), Color(0.4, 0.45, 0.5, 0.6), 1, 4, 10))
	_hud_root.add_child(_cap_bar)
	var cap_v := VBoxContainer.new()
	_cap_bar.add_child(cap_v)
	var cap_bg := ColorRect.new()
	cap_bg.color = Color(0.12, 0.14, 0.18)
	cap_bg.custom_minimum_size = Vector2(0, 10)
	cap_v.add_child(cap_bg)
	_cap_fill = ColorRect.new()
	_cap_fill.color = Color(0.24, 0.49, 0.85)
	cap_bg.add_child(_cap_fill)
	_cap_fill.anchor_right = 0.5
	_cap_fill.anchor_bottom = 1.0
	_cap_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cap_text = UiTheme.make_label("占领中", 13, Color(0.85, 0.88, 0.9))
	_cap_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_v.add_child(_cap_text)

	# ---- 左下:生命与兵种(整体面板) ----
	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_panel.position = Vector2(16, -104)
	status_panel.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.04, 0.06, 0.09, 0.78), Color(0.3, 0.38, 0.45, 0.5), 1, 4, 10))
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(status_panel)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 10)
	status_panel.add_child(status)
	_class_icon = UiTheme.make_label("突", 24, Color(0.5, 0.82, 1))
	_class_icon.custom_minimum_size = Vector2(48, 48)
	_class_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_class_icon.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.08, 0.11, 0.15, 0.9), Color(0.3, 0.4, 0.5, 0.7), 1, 5, 4))
	status.add_child(_class_icon)
	var st_right := VBoxContainer.new()
	st_right.alignment = BoxContainer.ALIGNMENT_CENTER
	st_right.add_theme_constant_override("separation", 4)
	status.add_child(st_right)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.1, 0.12, 0.15)
	hp_bg.custom_minimum_size = Vector2(210, 14)
	st_right.add_child(hp_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.4, 0.85, 0.45)
	hp_bg.add_child(_health_fill)
	_health_fill.anchor_right = 1.0
	_health_fill.anchor_bottom = 1.0
	_health_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var st_row := HBoxContainer.new()
	st_row.add_theme_constant_override("separation", 12)
	st_right.add_child(st_row)
	_health_num = UiTheme.make_label("100", 17, Color(0.9, 0.95, 0.9))
	_health_num.add_theme_font_override("font", UiTheme.mono_font())
	st_row.add_child(_health_num)
	_stance = UiTheme.make_label("站立", 13, Color(0.65, 0.7, 0.75))
	st_row.add_child(_stance)
	_gadget_info = UiTheme.make_label("F 医疗包 ×2", 13, Color(0.75, 0.72, 0.6))
	st_row.add_child(_gadget_info)
	# 军事四角括号(生命面板)
	var crs := Corners.new()
	crs.bracket_col = Color(0.5, 0.85, 0.95, 0.5)
	crs.bar_len = 8.0
	status_panel.add_child(crs)

	# ---- 战役小队状态栏(左下,生命面板上方;仅战役模式且小队非空时显示) ----
	_squad_panel = PanelContainer.new()
	_squad_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_squad_panel.position = Vector2(16, -194)
	_squad_panel.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.04, 0.06, 0.09, 0.8), Color(0.35, 0.42, 0.5, 0.55), 1, 4, 10))
	_squad_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_panel.visible = false
	_hud_root.add_child(_squad_panel)
	_squad_row = HBoxContainer.new()
	_squad_row.add_theme_constant_override("separation", 6)
	_squad_panel.add_child(_squad_row)
	for k in 3:
		var blk := PanelContainer.new()
		blk.custom_minimum_size = Vector2(150, 52)
		blk.add_theme_stylebox_override("panel",
			UiTheme.stylebox(Color(0.08, 0.11, 0.15, 0.9), Color(0.3, 0.4, 0.5, 0.6), 1, 3, 6))
		_squad_row.add_child(blk)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		blk.add_child(vb)
		var nm := UiTheme.make_label("", 11, Color(0.85, 0.9, 0.92))
		vb.add_child(nm)
		var hb2 := ColorRect.new()
		hb2.color = Color(0.1, 0.12, 0.15)
		hb2.custom_minimum_size = Vector2(134, 7)
		vb.add_child(hb2)
		var fill := ColorRect.new()
		fill.color = Color(0.4, 0.85, 0.45)
		hb2.add_child(fill)
		fill.anchor_right = 1.0
		fill.anchor_bottom = 1.0
		fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		var st := UiTheme.make_label("正常", 10, Color(0.6, 0.9, 0.65))
		vb.add_child(st)
		_squad_blocks.append({ "name": nm, "fill": fill, "status": st })

	# ---- 连杀指示(左下之上) ----
	_streak = RichTextLabel.new()
	_streak.theme = UiTheme.theme()
	_streak.bbcode_enabled = true
	_streak.fit_content = true
	_streak.scroll_active = false
	_streak.position = Vector2(16, -180)
	_streak.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak.add_theme_font_size_override("normal_font_size", 15)
	_hud_root.add_child(_streak)

	# ---- 右下:弹药(整体面板) ----
	var ammo_panel := PanelContainer.new()
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_panel.position = Vector2(-16, -16)
	ammo_panel.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.04, 0.06, 0.09, 0.78), Color(0.3, 0.38, 0.45, 0.5), 1, 4, 10))
	ammo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(ammo_panel)
	var ammo_box := VBoxContainer.new()
	ammo_box.alignment = BoxContainer.ALIGNMENT_END
	ammo_box.add_theme_constant_override("separation", 2)
	ammo_panel.add_child(ammo_box)
	_weapon_name = UiTheme.make_label("M4A1", 15, Color(0.75, 0.78, 0.8))
	ammo_box.add_child(_weapon_name)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 6)
	ammo_box.add_child(ammo_row)
	_ammo_mag = UiTheme.make_label("30", 30, Color(1, 1, 1))
	_ammo_mag.add_theme_font_override("font", UiTheme.mono_font())
	ammo_row.add_child(_ammo_mag)
	ammo_row.add_child(UiTheme.make_label("/", 22, Color(0.5, 0.55, 0.6)))
	_ammo_reserve = UiTheme.make_label("150", 19, Color(0.6, 0.65, 0.7))
	_ammo_reserve.add_theme_font_override("font", UiTheme.mono_font())
	ammo_row.add_child(_ammo_reserve)
	# 弹匣余量条(当前/备用之下)
	_ammo_bar = ColorRect.new()
	_ammo_bar.color = Color(0.1, 0.12, 0.15, 0.9)
	_ammo_bar.custom_minimum_size = Vector2(0, 5)
	ammo_box.add_child(_ammo_bar)
	_ammo_fill = ColorRect.new()
	_ammo_fill.color = Color(0.75, 0.8, 0.85)
	_ammo_bar.add_child(_ammo_fill)
	_ammo_fill.anchor_right = 1.0
	_ammo_fill.anchor_bottom = 1.0
	_ammo_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var fr := HBoxContainer.new()
	fr.alignment = BoxContainer.ALIGNMENT_END
	fr.add_theme_constant_override("separation", 10)
	ammo_box.add_child(fr)
	_fire_mode = UiTheme.make_label("全自动", 13, Color(0.55, 0.6, 0.65))
	fr.add_child(_fire_mode)
	_nade_count = UiTheme.make_label("G ×2", 13, Color(0.65, 0.7, 0.6))
	fr.add_child(_nade_count)
	# 军事四角括号(弹药面板)
	var cra := Corners.new()
	cra.bracket_col = Color(0.5, 0.85, 0.95, 0.5)
	cra.bar_len = 8.0
	ammo_panel.add_child(cra)

	# ---- 底部中央提示(容器居中) ----
	var hint_row := HBoxContainer.new()
	hint_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_row.position = Vector2(0, -140)
	hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(hint_row)
	_hint = UiTheme.make_label("", 15, Color(0.85, 0.87, 0.75))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_row.add_child(_hint)

	# ---- 救治队友提示(底部中央,提示行下方:按住 E + 读条进度) ----
	_revive_label = UiTheme.make_label("", 15, Color(0.55, 0.95, 0.65))
	_revive_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_revive_label.position = Vector2(0, -98)
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_label.add_theme_stylebox_override("normal",
		UiTheme.stylebox(Color(0.02, 0.05, 0.03, 0.8), Color(0.3, 0.7, 0.45, 0.6), 1, 3, 8))
	_revive_label.visible = false
	_revive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_revive_label)

	# ---- 交互目标提示(底部中央,救治提示下方:按住 E + label + 黄色进度条) ----
	_interact_box = PanelContainer.new()
	_interact_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_box.position = Vector2(0, -52)
	_interact_box.custom_minimum_size = Vector2(300, 0)
	_interact_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_box.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.05, 0.06, 0.09, 0.82), Color(0.55, 0.48, 0.3, 0.6), 1, 3, 8))
	_interact_box.visible = false
	_hud_root.add_child(_interact_box)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 3)
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_box.add_child(iv)
	_interact_label = UiTheme.make_label("", 15, Color(1, 0.9, 0.65))
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(_interact_label)
	var ibar := ColorRect.new()
	ibar.color = Color(0.12, 0.14, 0.18)
	ibar.custom_minimum_size = Vector2(0, 8)
	ibar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(ibar)
	_interact_fill = ColorRect.new()
	_interact_fill.color = Color(1.0, 0.72, 0.25)
	_interact_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ibar.add_child(_interact_fill)
	_interact_fill.anchor_right = 0.0
	_interact_fill.anchor_bottom = 1.0
	_interact_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# ---- 战役字幕(底部中央:深色底 + 白字,角色名角色色) ----
	_camp_dialogue_box = PanelContainer.new()
	_camp_dialogue_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_camp_dialogue_box.offset_top = -232
	_camp_dialogue_box.offset_bottom = -138
	_camp_dialogue_box.offset_left = 140
	_camp_dialogue_box.offset_right = -140
	_camp_dialogue_box.visible = false
	_camp_dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_dialogue_box.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.02, 0.03, 0.04, 0.85), Color(0.42, 0.52, 0.6, 0.5), 1, 3, 12))
	_hud_root.add_child(_camp_dialogue_box)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	drow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_dialogue_box.add_child(drow)
	_camp_dialogue_name = UiTheme.make_label("", 15, UiTheme.PRIMARY)
	drow.add_child(_camp_dialogue_name)
	_camp_dialogue = UiTheme.make_label("", 15, Color(0.92, 0.95, 0.97))
	_camp_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 吃掉面板剩余宽度,杜绝逐字竖排
	_camp_dialogue.custom_minimum_size = Vector2(560, 0)
	drow.add_child(_camp_dialogue)

	# ---- 战役大字卡(开场标题卡 / 目标点名卡:居中大标题,淡入停留淡出) ----
	_camp_card = UiTheme.make_label("", 44, Color(1, 0.92, 0.65))
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
	_camp_card.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.02, 0.03, 0.05, 0.82), Color(0.78, 0.64, 0.3, 0.6), 1, 4, 16))
	_hud_root.add_child(_camp_card)

	# ---- 战役目标屏幕边缘指示器(COD 黄三角 + 距离;战役 combat 专属) ----
	_camp_indicator = CampaignIndicator.new()
	_camp_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	_camp_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camp_indicator.visible = false
	_hud_root.add_child(_camp_indicator)

	# ---- 记分板 ----
	_scoreboard = PanelContainer.new()
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard.custom_minimum_size = Vector2(680, 420)
	_scoreboard.position = Vector2(-340, -210)  # 锚点居中后偏移回正中
	_scoreboard.visible = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.04, 0.05, 0.08, 0.92), Color(0.35, 0.42, 0.5, 0.7), 1, 6, 18))
	_hud_root.add_child(_scoreboard)
	var sb_v := VBoxContainer.new()
	sb_v.add_theme_constant_override("separation", 10)
	_scoreboard.add_child(sb_v)
	_sb_title = UiTheme.make_label("记分板 — 征服模式", 18, Color(0.9, 0.92, 0.95))
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

	# ---- 全屏黑(最顶层:章末 fade 黑 → 结算屏;重试淡入;独立于 _hud_root 保证死亡时可见) ----
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.modulate.a = 0.0
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	add_child(_fade_rect)


func _make_vignette_tex() -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 256:
		for x in 256:
			var dx := (x - 127.5) / 127.5
			var dy := (y - 127.5) / 127.5
			var d := sqrt(dx * dx + dy * dy)
			if d > 0.55:
				img.set_pixel(x, y, Color(1, 1, 1, clampf((d - 0.55) / 0.45, 0, 1)))
	return ImageTexture.create_from_image(img)


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
	_hitmarker.show_hit(kill, head)
	_screen_flash(Color(1, 1, 1), 0.3 if kill else 0.15, 0.24 if kill else 0.16)


## 全屏微闪光(命中白闪 / 击杀强闪 / 受击红闪)
func _screen_flash(col: Color, peak: float, dur: float) -> void:
	if _flash == null or not _flash.is_inside_tree():
		return
	_flash.color = col
	_flash.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", peak, 0.03)
	tw.tween_property(_flash, "modulate:a", 0.0, dur)


func add_killfeed(killer_name: String, killer_team, victim_name: String, victim_team, weapon_name: String, head: bool, is_me: bool) -> void:
	var row_panel := PanelContainer.new()
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.03, 0.04, 0.06, 0.65 if is_me else 0.45), Color(0.35, 0.42, 0.5, 0.4) if is_me else Color.TRANSPARENT, 1, 2, 6))
	var row := RichTextLabel.new()
	row.theme = UiTheme.theme()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_font_size_override("normal_font_size", 14)
	var kc: String = US_HEX if killer_team == "us" else RU_HEX
	var vc: String = US_HEX if victim_team == "us" else RU_HEX
	# 时间戳 + 击杀图标(★)+ 姓名 + 武器 + 受害者 + 爆头
	var text := "[color=#55646f]" + G.fmt_clock(G.time) + "[/color]  [color=#ffd24d]★[/color] [color=" + kc + "]" + killer_name + "[/color][color=#8a94a0] [" + weapon_name + "][/color][color=" + vc + "]" + victim_name + "[/color]"
	if head:
		text += " [color=#ffb040]爆头[/color]"
	if is_me:
		text = "[b]" + text + "[/b]"
	row.text = text
	row_panel.add_child(row)
	_killfeed.add_child(row_panel)
	# queue_free 在 Godot 4 中延迟执行(帧末),不能用 while 循环判断 get_child_count() —— 必须是 if
	if _killfeed.get_child_count() > 6:
		_killfeed.get_child(0).queue_free()
	# 滑入动画:透明度 0→1 + 轻微缩放弹出
	row_panel.modulate.a = 0.0
	row_panel.scale = Vector2(0.92, 0.92)
	row_panel.pivot_offset = row_panel.size * 0.5
	var tw := row_panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(row_panel, "modulate:a", 1.0, 0.16)
	tw.tween_property(row_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var wr = weakref(row_panel)
	get_tree().create_timer(5.0).timeout.connect(func():
		var p = wr.get_ref()
		if p != null:
			# 退出前淡出,再由 queue_free 移除
			var fw: Tween = p.create_tween()
			fw.tween_property(p, "modulate:a", 0.0, 0.4)
			fw.tween_callback(p.queue_free))


func banner(text: String, bad := false) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if bad else Color(1, 0.92, 0.7))
	_banner.visible = true
	_banner_t = 2.4


func hint(text: String) -> void:
	_hint.text = text
	_hint_t = 2.0


## 全屏黑渐入(章末转场/判负:0.5s 淡入黑,盖住 HUD 层)
func _fade_to_black(dur := 0.5) -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.tween_property(_fade_rect, "modulate:a", 1.0, dur)


## 全屏黑渐出(重试/下一章开场:0.6s 淡出露出飞越过场)
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


## 消费战役转场请求(fade_in=开场淡入 / fade_out=章末黑屏)
func _consume_campaign_transition() -> void:
	if G.campaign == null:
		return
	var pt: String = G.campaign.consume_pending_transition()
	if pt == "fade_in":
		_fade_from_black(0.6)
	elif pt == "fade_out":
		_fade_to_black(0.5)


## ============ 战役模式 HUD ============
## 战役目标文本(空文本隐藏;update_hud 每帧刷新 objective_text)
func set_campaign_objective(text: String) -> void:
	if _camp_obj == null:
		return
	if text == "":
		_camp_obj.visible = false
	else:
		_camp_obj.text = text
		_camp_obj.visible = true


## 战役字幕:淡入 → 停留 dur → 淡出隐藏(名字用角色色)
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
		_camp_dialogue_name.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	else:
		_camp_dialogue_name.add_theme_color_override("font_color", UiTheme.PRIMARY)
	_camp_dialogue.text = text
	_camp_dialogue_box.visible = true
	_camp_dialogue_box.modulate.a = 0.0
	_camp_dialogue_tw = create_tween()
	_camp_dialogue_tw.tween_property(_camp_dialogue_box, "modulate:a", 1.0, 0.2)
	_camp_dialogue_tw.tween_interval(maxf(dur - 0.55, 0.1))
	_camp_dialogue_tw.tween_property(_camp_dialogue_box, "modulate:a", 0.0, 0.35)
	_camp_dialogue_tw.tween_callback(func(): _camp_dialogue_box.visible = false)


## 战役大字卡(开场标题卡 / 目标点名卡):淡入 → 停留 dur → 淡出隐藏
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


## 清空全部战役 UI 残留(目标/字幕/点名卡/箭头/小队栏/救治提示/信标转场),模式切换时调用
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


## 战役目标指示器:combat 时指向战役路线引导点(目标坐标 > 路点 > 下一目标区;kill 目标也有箭头)
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


## 战役小队状态栏(左下 3 块:姓名+血条+状态)与救治读条(底部中央)
## 数据每帧从 G.campaign.get_squad_info()/get_revive_info() 读取
func _update_campaign_squad(camp_mode: bool, in_cutscene: bool) -> void:
	if _squad_panel == null or _squad_blocks.is_empty():
		return
	var vis: bool = camp_mode and G.campaign != null and G.campaign.running
	if vis:
		var info: Array = G.campaign.get_squad_info()
		_update_squad_panel(info)
	if _squad_panel.visible != vis:
		_squad_panel.visible = vis
	# 救治读条:队友倒地且玩家贴近 → "按住 E 救治 XX xx%"
	var rv: Dictionary = G.campaign.get_revive_info() if (camp_mode and G.campaign != null) else {}
	if not rv.is_empty() and not in_cutscene and G.player != null and G.player.alive:
		var t: float = float(rv.get("t", 0.0))
		var dur: float = float(rv.get("dur", 3.0))
		var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
		_revive_label.text = "按住 E 救治 " + str(rv.get("name", "")) + "  " + str(int(k * 100.0)) + "%"
		_revive_label.visible = true
	elif _revive_label != null and _revive_label.visible:
		_revive_label.visible = false


## 小队面板填充(3 块:姓名+血条+状态)
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
			fill.color = Color(0.4, 0.4, 0.42)
			st.text = "已撤离"
			st.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
		elif downed:
			fill.anchor_right = 0.0
			fill.color = Color(1.0, 0.62, 0.2,
				0.65 + 0.35 * (0.5 + 0.5 * sin(_hud_t * 6.0)))
			var self_left: float = float(info.get("self_left", 12.0))
			st.text = "自救中 " + str(maxi(1, int(ceil(self_left)))) + "s · 可救治"
			st.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
		else:
			fill.anchor_right = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
			fill.color = Color(0.4, 0.85, 0.45)
			st.text = "正常"
			st.add_theme_color_override("font_color", Color(0.6, 0.9, 0.65))


## 交互目标提示(底部中央):interact 目标且玩家进入半径 → "按住 E + label" + 进度百分比进度条
## 数据每帧从 G.campaign.get_interact_info() 读取(不在半径内返回空 → 自动隐藏)
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
	# 战役 signal 懒连接(campaign 由 main 在 HUD 之后创建,首帧补齐)
	if not _campaign_connected and G.campaign != null:
		_campaign_connected = true
		G.campaign.dialogue_requested.connect(show_campaign_dialogue)
		G.campaign.cutscene_card_requested.connect(show_campaign_card)
		# 懒连接补齐:若已在战斗中(开场被跳过),补发当前目标点名卡
		if G.campaign.running:
			G.campaign.request_objective_card()
	# 战役转场轮询(fade_in 开场淡入 / fade_out 章末黑屏;轮询不依赖信号连接时机)
	_consume_campaign_transition()
	# 战役模式:隐藏征服 UI(左上小地图 / 顶部票数面板);切回征服自动恢复
	var camp_mode: bool = G.mode == "campaign"
	if _minimap != null and _minimap.visible == camp_mode:
		_minimap.visible = not camp_mode
	if _top_bar != null and _top_bar.visible == camp_mode:
		_top_bar.visible = not camp_mode
	# 非战役模式:强制清空战役 UI 残留(每帧自愈,防切模式后残留)
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
	# 战役目标文本(运行中且非过场每帧刷新)
	var in_cutscene: bool = camp_mode and G.campaign != null and G.campaign.is_cutscene()
	if in_cutscene and _camp_obj != null and _camp_obj.visible:
		set_campaign_objective("")  # 过场期间不显示目标文本(显示大字卡/字幕)
	if camp_mode and G.campaign != null and G.campaign.running and not in_cutscene:
		var otxt: String = G.campaign.objective_text()
		if _camp_obj != null and _camp_obj.text != otxt:
			_camp_obj.text = otxt
			_camp_obj.visible = otxt != ""
	# 战役目标屏幕边缘指示器(仅 combat 且有坐标的目标)
	_update_campaign_indicator(camp_mode, in_cutscene)
	# 战役小队状态栏 + 救治读条提示
	_update_campaign_squad(camp_mode, in_cutscene)
	# 战役交互目标提示(interact 读条)
	_update_interact_prompt(camp_mode, in_cutscene)
	# 战役目标区域进入/离开轻提示(去抖) + hold 坚守中持久提示
	if camp_mode and G.campaign != null and G.campaign.running and not in_cutscene:
		var zin: bool = G.campaign.zone_in()
		if zin != _zone_prev:
			_zone_prev = zin
			hint("已进入目标区域" if zin else "已离开目标区域")
		var zs: String = G.campaign.zone_status()
		if zs != "":
			_hint.text = zs
			_hint_t = 0.2   # 每帧续命:hold 区内常显"坚守中…",离开自动交还普通提示
	else:
		_zone_prev = false
	# 横幅/提示计时
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
	# 受击暗角 + 压制暗角 + 低血量血雾(边缘脉冲)
	var hp0: float = p.health if p != null else 100.0
	var low_hp_fog: float = 0.0
	if hp0 < 30.0:
		low_hp_fog = (0.22 + 0.16 * sin(_hud_t * 7.0)) * (1.0 - hp0 / 30.0)
	var v_alpha: float = clampf(maxf(maxf(clampf(1 - hp0 / 100.0, 0, 0.7),
		0.3 if _dmg_t > 0 else 0.0), p.suppression * 0.45) + low_hp_fog, 0, 1)
	_dmg_vignette.modulate.a = v_alpha
	# 连杀指示(战役模式禁用)
	var ks := ""
	if G.mode != "campaign":
		if G.streak >= 2:
			ks = "[color=#ffd24d]连杀 ×" + str(G.streak) + "[/color]"
		if G.streak_uav:
			ks += "\n[color=#7fd0ff][4] UAV 就绪[/color]"
		if G.streak_arty:
			ks += "\n[color=#7fd0ff][5] 炮火支援就绪[/color]"
	_streak.text = ks

	# 票数/计时(突破模式防守方兵力无限;文本变化才写入,避免每帧重排版)
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
		# 战役模式:无旗帜/无模式元素,记分板标题不出现"征服模式"
		_sb_title.text = "记分板 — 战役"
	elif G.mode == "breakthrough" and G.bt != null:
		_pips["C"].visible = false
		_pips["D"].visible = false
		_pips["E"].visible = false
		_sector_label.visible = true
		_sector_label.text = "区域 " + str(mini(G.bt["sector"] + 1, G.bt["total"])) + "/" + str(G.bt["total"])
		for f in G.flags:
			if f.sector != G.bt["sector"]:
				continue
			var pip: Label = _pips.get(f.id)
			if pip != null:
				_set_pip_style(pip, f)
		_sb_title.text = "记分板 — 突破模式(" + ("进攻方" if G.bt_player_side == "att" else "防守方") + ":友军)"
	else:
		for fid in ["C", "D", "E"]:
			_pips[fid].visible = true
		_sector_label.visible = false
		for f in G.flags:
			var pip: Label = _pips.get(f.id)
			if pip != null:
				_set_pip_style(pip, f)
		_sb_title.text = "记分板 — 征服模式"

	if p != null and p.alive:
		# 生命:显示值平滑下落(tween 手感),受击瞬间条带白闪
		var hp := clampf(p.health, 0, 100)
		_hp_show = lerpf(_hp_show, hp, 1.0 - exp(-dt * 10.0))
		if hp < _last_hp_disp:
			_hp_flash_t = 0.45
		_last_hp_disp = hp
		_health_fill.anchor_right = _hp_show / 100.0
		var base_col := Color(0.85, 0.3, 0.25) if hp < 35 else Color(0.4, 0.85, 0.45)
		if _hp_flash_t > 0:
			_hp_flash_t -= dt
			base_col = base_col.lerp(Color(1, 1, 1), clampf(_hp_flash_t * 3.0, 0, 1))
		_health_fill.color = base_col
		_set_text(_health_num, str(int(ceil(_hp_show))))
		# 弹药(未部署时 gun 为 null)
		var gun = p.gun()
		if gun == null:
			return
		_set_text(_weapon_name, gun.def.cn)
		var ammo_now: int = gun.ammo
		# 射击检测:弹匣量下降 → 准星后坐上跳
		if not gun.reloading and _last_ammo != -1 and ammo_now < _last_ammo:
			_crosshair.kick_px = minf(_crosshair.kick_px + 7.0, 16.0)
			_crosshair.queue_redraw()
		if ammo_now != _last_ammo:
			_last_ammo = ammo_now
			_pop_label(_ammo_mag)
		_set_text(_ammo_mag, "——" if gun.reloading else str(ammo_now))
		_ammo_mag.add_theme_color_override("font_color", Color(1, 0.45, 0.3) if ammo_now <= gun.def.mag * 0.25 else Color(1, 1, 1))
		_set_text(_ammo_reserve, str(gun.reserve))
		# 弹匣余量条:换弹时黄色脉动,低弹红色
		_ammo_fill.anchor_right = clampf(float(ammo_now) / float(maxi(1, gun.def.mag)), 0, 1)
		if gun.reloading:
			_ammo_fill.modulate.a = 0.45 + 0.35 * (0.5 + 0.5 * sin(_hud_t * 13.0))
			_ammo_fill.color = Color(1.0, 0.82, 0.3)
		else:
			_ammo_fill.modulate.a = 1.0
			_ammo_fill.color = Color(1.0, 0.4, 0.3) if ammo_now <= gun.def.mag * 0.25 else Color(0.75, 0.8, 0.85)
		_set_text(_fire_mode, "火箭推进" if gun.def.projectile else ("全自动" if gun.def.auto else ("泵动/半自动" if gun.def.pellets > 1 else "半自动")))
		_set_text(_nade_count, "G ×" + str(p.grenades) + "  X 反雷 ×" + str(p.at_grenades) + "  V 地雷 ×" + str(p.at_mines))
		var cls = WeaponsData.C()[p.class_id]
		_set_text(_class_icon, cls.icon)
		_class_icon.add_theme_color_override("font_color", cls.color)
		_set_text(_gadget_info, "按 3 切换火箭筒" if p.gadget == "rpg" else (
			("2 霰弹枪 · F " + cls.gadget_cn + " ×" + str(p.gadget_count)) if (not cls.shotguns.is_empty() and p.guns.size() > 2)
			else ("F " + cls.gadget_cn + " ×" + str(p.gadget_count))))
		_set_text(_stance, "驾驶" if p.vehicle != null else ("滑铲" if p.slide_t > 0 else ("趴下" if p.prone else ("蹲下" if p.crouched else "站立"))))
		# 准星扩散(变化才重绘)+ 后坐力联动衰减
		var ch_op: float
		var spread_px: float
		if p.vehicle != null:
			# 驾驶中隐藏步战准星(载具 HUD 提供坦克风格主准星)
			ch_op = 0.0
			spread_px = 0.0
		elif not gun.def.scope or gun.ads_amount < 0.7:
			spread_px = clampf(gun.current_spread() / (G.camera.fov * PI / 180.0) * get_viewport().get_visible_rect().size.y, 2, 90)
			ch_op = 0.25 if (gun.ads_amount > 0.6 and not gun.def.scope) else 1.0
		else:
			spread_px = 2.0
			ch_op = 0.0
		if _crosshair.kick_px > 0:
			_crosshair.kick_px = maxf(_crosshair.kick_px - dt * 18.0, 0.0)
		if absf(spread_px - _crosshair.spread_px) > 0.5 or ch_op != _crosshair.ch_opacity or _crosshair.kick_px > 0.01:
			_crosshair.spread_px = spread_px
			_crosshair.ch_opacity = ch_op
			_crosshair.queue_redraw()
		# 狙击镜:全屏放大 + 镜模型遮罩(镜内放大效果)
		_scope.visible = gun.def.scope and gun.ads_amount > 0.7
		if _scope.visible:
			_scope.queue_redraw()
		# 占领进度(战役模式隐藏:旗帜不参与胜负)
		var in_flag = null
		for f in G.flags:
			if Vector2(p.pos.x - f.pos.x, p.pos.z - f.pos.z).length() < f.radius:
				in_flag = f
				break
		if in_flag != null and G.mode != "campaign":
			_cap_bar.visible = true
			var prog: float = (in_flag.progress + 100) / 200.0
			_cap_fill.anchor_right = prog
			_cap_fill.color = Color(0.24, 0.49, 0.85) if in_flag.progress >= 0 else Color(0.85, 0.29, 0.24)
			# 争夺中脉冲:亮度/透明度呼吸
			if in_flag.contested:
				_cap_fill.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(_hud_t * 6.0))
			else:
				_cap_fill.modulate.a = 1.0
			_set_text(_cap_text, in_flag.id + " 点 — " + ("已控制" if in_flag.owner_team == G.player.team else ("敌方控制" if in_flag.owner_team != null else "中立")) + (" · 争夺中" if in_flag.contested else ""))
		else:
			_cap_bar.visible = false

	# 记分板
	var sb_visible: bool = Input.is_action_pressed("scoreboard") and (G.state == "playing" or G.state == "dead")
	if _scoreboard.visible != sb_visible:
		_scoreboard.visible = sb_visible
	if sb_visible:
		_update_scoreboard()

	# 小地图降频重绘(每帧 → 8Hz)
	_mm_t += dt
	if _mm_t >= 0.125:
		_mm_t = 0.0
		_minimap.queue_redraw()


## 文本变化才写入(避免 Label 每帧重排版)
func _set_text(l: Label, s: String) -> void:
	if l.text != s:
		l.text = s


## 数值变化弹出动画(票数/弹药数字 1.18x 回弹;0.2s 节流防连发堆积)
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
	tw.tween_property(l, "scale", Vector2(1.18, 1.18), 0.06)
	tw.tween_property(l, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pip_style(pip: Label, f) -> void:
	var key := "neutral"
	if f.contested:
		key = "warn"
	elif f.owner_team != null:
		key = "us" if f.owner_team == G.player.team else "ru"
	# 状态变化才重写样式(缓存 StyleBox,不再每帧新建)
	if pip.get_meta("pip_state", "") == key:
		return
	pip.set_meta("pip_state", key)
	pip.add_theme_stylebox_override("normal", _pip_sb[key])
	pip.add_theme_color_override("font_color",
		Color(0.8, 0.9, 1) if key == "us" else (Color(1, 0.8, 0.75) if key == "ru" else Color(0.7, 0.72, 0.75)))


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
