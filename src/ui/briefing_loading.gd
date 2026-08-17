class_name LoadingBriefing extends Control
## 战术部署加载 / 战场简报层。
## 负责:动态阶段进度、地图情报、俯视战术图、动态扫描线。
## 它只负责展示,真实加载阶段由 Game.start_match 调用 set_stage 更新,不伪造精细进度。

var _time := 0.0
var _title: Label
var _map_title: Label
var _meta: RichTextLabel
var _objectives: RichTextLabel
var _zones: RichTextLabel
var _stage_label: Label
var _stage_detail: Label
var _progress: ColorRect
var _progress_bg: ColorRect
var _map_box: Control
var _map_def = null
var _mode := ""
var _progress_target := 0.0
var _progress_show := 0.0
var _stage_done: Array = []

const STAGES := [
	"正在建立加密链路",
	"正在加载地图",
	"正在加载场景",
	"正在加载作战单位",
	"正在配发武器",
	"正在初始化战场",
]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	set_process(true)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.022, 0.032, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 64
	root.offset_top = 56
	root.offset_right = -64
	root.offset_bottom = -48
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	_title = UiTheme.make_label("TACTICAL DEPLOYMENT // MAP BRIEFING", 28, UiTheme.H_WHITE)
	root.add_child(_title)
	_map_title = UiTheme.make_label("", 22, UiTheme.H_CYAN)
	root.add_child(_map_title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)

	# 左:阶段 + 地图情报
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)

	var stage_panel := UiTheme.make_panel(0.55)
	stage_panel.custom_minimum_size = Vector2(0, 150)
	left.add_child(stage_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	stage_panel.add_child(sv)
	sv.add_child(UiTheme.make_label("部署阶段", 15, UiTheme.H_CYAN))
	_stage_label = UiTheme.make_label("准备进入战场…", 18, UiTheme.H_WHITE)
	sv.add_child(_stage_label)
	_stage_detail = UiTheme.make_label("", 12, UiTheme.H_GRAY)
	_stage_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_stage_detail)
	_progress_bg = ColorRect.new()
	_progress_bg.color = Color(0.2, 0.3, 0.35, 0.8)
	_progress_bg.custom_minimum_size = Vector2(0, 6)
	sv.add_child(_progress_bg)
	_progress = ColorRect.new()
	_progress.color = UiTheme.H_CYAN
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress_bg.add_child(_progress)

	var info_panel := UiTheme.make_panel(0.5)
	info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(info_panel)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 8)
	info_panel.add_child(iv)
	iv.add_child(UiTheme.make_label("战场情报", 15, UiTheme.H_CYAN))
	_meta = RichTextLabel.new()
	_meta.bbcode_enabled = true
	_meta.fit_content = true
	_meta.scroll_active = false
	_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meta.add_theme_font_size_override("normal_font_size", 14)
	_meta.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(_meta)
	_objectives = RichTextLabel.new()
	_objectives.bbcode_enabled = true
	_objectives.fit_content = true
	_objectives.scroll_active = false
	_objectives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objectives.add_theme_font_size_override("normal_font_size", 14)
	iv.add_child(_objectives)
	_zones = RichTextLabel.new()
	_zones.bbcode_enabled = true
	_zones.fit_content = true
	_zones.scroll_active = false
	_zones.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zones.add_theme_font_size_override("normal_font_size", 13)
	iv.add_child(_zones)

	# 右:俯视战术图
	var right := UiTheme.make_panel(0.55)
	right.custom_minimum_size = Vector2(520, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(UiTheme.make_label("战术地图概览 // LIVE INTEL", 14, UiTheme.H_CYAN))
	_map_box = Control.new()
	_map_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_box.custom_minimum_size = Vector2(0, 320)
	_map_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(_map_box)
	_map_box.draw.connect(_draw_tactical_map)


func setup(map_id: String, mode: String) -> void:
	_mode = mode
	if MapsData.M().has(map_id):
		_map_def = MapsData.M()[map_id]
	else:
		_map_def = null
	var mcn: String = str(_map_def.cn) if _map_def != null else map_id.to_upper()
	var mode_cn: String = str({
		"conquest": "征服作战", "breakthrough": "突破作战",
		"tdm": "团队死斗", "br": "大逃杀", "campaign": "战役行动",
	}.get(mode, mode.to_upper()))
	_map_title.text = "%s // %s" % [map_id.to_upper(), mcn]
	_stage_done.clear()
	for s in STAGES:
		_stage_done.append(false)
	var side := "US 联合特遣队  VS  RU 东方阵线"
	if mode == "br":
		side = "多支小队 · 自由混战"
	elif mode == "campaign":
		side = "联合特遣队 · 战役行动"
	_meta.text = "[color=#a8ccd8]模式[/color]  %s\n[color=#a8ccd8]地图[/color]  %s\n[color=#a8ccd8]环境[/color]  %s\n[color=#a8ccd8]阵营[/color]  %s" % [
		mode_cn, mcn,
		("夜间作战" if (_map_def != null and _map_def.night) else "白昼作战"),
		side,
	]
	var obj := "夺取并控制全部关键据点,耗尽敌方兵力。"
	if mode == "breakthrough":
		obj = "沿主攻轴线逐区突破,在兵力耗尽前夺取全部战区。"
	elif mode == "tdm":
		obj = "在时限内取得更多击杀,控制中心交火区。"
	elif mode == "br":
		obj = "搜索物资、跟随缩圈,成为最后存活的队伍。"
	_objectives.text = "[color=#00d4ff]作战目标[/color]\n" + obj
	_zones.text = _zones_text()
	_map_box.queue_redraw()


func set_stage(text: String, progress: float, detail := "") -> void:
	_stage_label.text = text
	_stage_detail.text = detail
	_progress_target = clampf(progress, 0.0, 1.0)
	if _stage_done.size() != STAGES.size():
		_stage_done.clear()
		for s in STAGES:
			_stage_done.append(false)
	var si := int(progress * float(STAGES.size() - 1))
	for i in STAGES.size():
		_stage_done[i] = i <= si
	queue_redraw()


func _zones_text() -> String:
	if _map_def == null:
		return "[color=#7a8790]情报链路建立中…[/color]"
	var parts: Array = ["[color=#ffb347]主要战略区域[/color]"]
	if _map_def is Object and _map_def.get("sectors") is Array:
		for i in (_map_def.sectors as Array).size():
			var sec: Array = _map_def.sectors[i]
			var ids: Array = []
			for f in sec:
				ids.append(str(f.get("id", "?")))
			parts.append("  ALPHA-%s 战区 %d" % [",".join(ids), i + 1])
	elif _map_def is Dictionary and _map_def.has("sectors"):
		pass
	var theme := "城市" if _map_def is Object and _map_def.get("cn") != null else "未知"
	parts.append("[color=#9fb8c8]载具路线[/color]  主公路贯穿战区,侧翼道路可快速穿插")
	parts.append("[color=#9fb8c8]推进方向[/color]  敌军将沿道路与建筑群向己方基地推进")
	return "\n".join(parts)


func _process(dt: float) -> void:
	_time += dt
	_progress_show = lerpf(_progress_show, _progress_target, 1.0 - exp(-dt * 6.0))
	if _progress != null and _progress_bg != null and _progress_bg.size.x > 1.0:
		_progress.position = Vector2.ZERO
		_progress.size = Vector2(_progress_bg.size.x * _progress_show, _progress_bg.size.y)
	queue_redraw()


func _draw() -> void:
	# 全屏军事网格 + 扫描线
	var step := 56.0
	var col := Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.055)
	for x in range(0, int(size.x) + 1, step):
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
	for y in range(0, int(size.y) + 1, step):
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
	var sy := fmod(_time * 120.0, size.y)
	draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.16), 2.0)
	# 阶段清单
	var x0 := 90.0
	var y0 := 300.0
	for i in STAGES.size():
		var done: bool = i < _stage_done.size() and _stage_done[i]
		var c := UiTheme.H_CYAN if done else UiTheme.H_GRAY_DIM
		draw_string(UiTheme.font(), Vector2(x0, y0 + i * 26), ("▣ " if done else "▢ ") + STAGES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)


func _draw_tactical_map() -> void:
	if _map_box == null:
		return
	var c := _map_box.size * 0.5
	var half := minf(_map_box.size.x, _map_box.size.y) * 0.40
	var bg := Color(0.02, 0.09, 0.12, 0.8)
	_map_box.draw_rect(Rect2(c - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), bg, true)
	# 网格
	var gcol := Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.18)
	for i in range(5):
		var t := -0.8 + i * 0.4
		var px := c.x + t * half
		var pz := c.y + t * half
		_map_box.draw_line(Vector2(px, c.y - half), Vector2(px, c.y + half), gcol, 1.0)
		_map_box.draw_line(Vector2(c.x - half, pz), Vector2(c.x + half, pz), gcol, 1.0)
	# 地图边界高亮
	var border := Color(UiTheme.H_CYAN.r, UiTheme.H_CYAN.g, UiTheme.H_CYAN.b, 0.8)
	_map_box.draw_rect(Rect2(c - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), border, false, 2.0)
	# 主要道路:十字 + 斜向路线
	_map_box.draw_line(Vector2(c.x - half, c.y), Vector2(c.x + half, c.y), Color(0.75, 0.75, 0.75, 0.35), 2.0)
	_map_box.draw_line(Vector2(c.x, c.y - half), Vector2(c.x, c.y + half), Color(0.75, 0.75, 0.75, 0.35), 2.0)
	# 动态推进箭头(从敌方方向进入地图)
	var pulse := 0.5 + 0.5 * sin(_time * 2.2)
	for i in 3:
		var ay := c.y - half + half * (0.2 + i * 0.28)
		var a := Color(1.0, 0.45, 0.15, 0.25 + 0.35 * pulse)
		var head := Vector2(c.x + (0.15 - i * 0.1) * half, ay)
		_map_box.draw_line(Vector2(c.x + half, ay), head, a, 3.0)
		_map_box.draw_line(head, head + Vector2(-12, -7), a, 3.0)
		_map_box.draw_line(head, head + Vector2(-12, 7), a, 3.0)
	# 己方部署区域
	var us_rect := Rect2(c.x - half, c.y + half * 0.62, half * 2.0, half * 0.38)
	_map_box.draw_rect(us_rect, Color(0.0, 1.0, 0.53, 0.12), true)
	_map_box.draw_line(Vector2(c.x - half, us_rect.position.y), Vector2(c.x + half, us_rect.position.y), Color(0.0, 1.0, 0.53, 0.65), 2.0)
	# 据点
	if _map_def is Object and _map_def.get("sectors") is Array:
		for si in (_map_def.sectors as Array).size():
			var sec: Array = _map_def.sectors[si]
			for f in sec:
				var wx: float = float(f.get("x", 0.0))
				var wz: float = float(f.get("z", 0.0))
				var px := c.x + wx / 210.0 * half * 0.7
				var py := c.y + wz / 210.0 * half * 0.7
				var reveal := _progress_show > 0.18 + si * 0.12
				var pcol := UiTheme.H_CYAN if reveal else UiTheme.H_GRAY_DIM
				_map_box.draw_circle(Vector2(px, py), 7.0 if reveal else 4.0, pcol)
				_map_box.draw_string(UiTheme.font(), Vector2(px + 10, py - 8), str(f.get("id", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pcol)
	# 载具点
	for i in 4:
		var vx := c.x + (-0.55 + i * 0.36) * half
		var vy := c.y - 0.08 * half
		_map_box.draw_rect(Rect2(vx - 5, vy - 3, 10, 6), Color(0.9, 0.9, 0.95, 0.65), false, 1.5)
	_map_box.draw_string(UiTheme.font(), Vector2(c.x - 70, c.y - half + 18), "MAIN VEHICLE ROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 0.9, 0.7))
