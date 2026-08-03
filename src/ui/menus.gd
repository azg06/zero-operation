class_name Menus extends CanvasLayer
## 菜单系统(对应 index.html 全部界面 + hud.js 的菜单逻辑)

var on_start: Callable
var on_deploy: Callable
var on_redeploy: Callable
var on_resume: Callable
var on_quit: Callable
var on_again: Callable
var on_campaign_start: Callable       # 战役章节启动(main 赋值):G.mode="campaign" + start_match

var selected_class := "assault"
var loadout := {
	"assault": { "primary": "m4", "secondary": "m1911", "shotgun": "m1014" },
	"engineer": { "primary": "mp5", "secondary": "m1911" },
	"support": { "primary": "m249", "secondary": "m1911" },
	"recon": { "primary": "awm", "secondary": "m1911" },
}

var _screens: Dictionary = {}
var _map_btns: Array = []
var _slot_class: Button
var _slot_primary: Button
var _slot_shotgun: Button
var _slot_secondary: Button
var _submenu: PanelContainer
var _submenu_open := ""
var _map_select: HBoxContainer
var _squad_list: VBoxContainer
var _deploy_map: DeployMap
var _deploy_title: Label
var _dep_ticket_us: Label
var _dep_ticket_ru: Label
var _side_sel: HBoxContainer
var _btn_side_att: Button
var _btn_side_def: Button
var _death_killer: Label
var _death_btn: Button
var _death_t := 0.0
var _spawn_time := 5.0             # 重生倒计时(优先读 G.settings.spawn_time,无配置默认 5s)
var _deploy_overlay: Label
var _end_title: Label
var _end_stats: RichTextLabel
var _settings_from_pause := false  # 设置屏上下文:true=暂停菜单打开,返回时回暂停界面


func _ready() -> void:
	layer = 10
	G.menus = self
	_init_spawn_time()
	_campaign_load_save()
	_build_main_menu()
	_build_help()
	_build_settings()
	_build_deploy()
	_build_death()
	_build_end()
	_build_pause()
	_build_loading()
	_build_campaign_select()
	_build_campaign_end()
	hide_all()
	_screens["menu"].visible = true
	# 调试:--test-campaign-menu 直接打开战役章节选择屏(验证构建)
	if OS.get_cmdline_user_args().has("--test-campaign-menu"):
		hide_all()
		_screens["campaign"].visible = true


func _process(dt: float) -> void:
	# 战役 signal 懒连接(campaign 由 main 在 Menus 之后创建)
	if not _campaign_connected and G.campaign != null:
		_campaign_connected = true
		G.campaign.chapter_finished.connect(_on_chapter_finished)
	# 新闻滚动条
	if _news_label != null and _screens.has("menu") and _screens["menu"].visible:
		_news_t += dt
		if _news_t > 5.0:
			_news_t = 0
			_news_i = (_news_i + 1) % NEWS.size()
			_news_label.text = NEWS[_news_i]
			if _news_label.text == "":
				_news_label.text = NEWS[0]
	# 死亡重生倒计时(动画:数字跳动,归零解锁)
	if _death_btn != null and _death_btn.is_inside_tree() and _screens.has("death") and _screens["death"].visible and _death_t > 0:
		_death_t -= dt
		var n := int(ceil(_death_t))
		if n < 1:
			_death_t = 0.0
			_death_btn.disabled = false
			_death_btn.text = "立即部署"
			_death_btn.modulate = Color(1, 1, 1, 1)
			AudioSys.ui_hover()
		else:
			var cur := str(n)
			if _death_btn.text != "重新部署 (" + cur + ")":
				_death_btn.text = "重新部署 (" + cur + ")"
				# 数字变化弹出
				_death_btn.pivot_offset = _death_btn.size * 0.5
				var tw := _death_btn.create_tween()
				tw.tween_property(_death_btn, "scale", Vector2(1.06, 1.06), 0.05)
				tw.tween_property(_death_btn, "scale", Vector2.ONE, 0.1)


func hide_all() -> void:
	for k in _screens:
		_screens[k].visible = false


## 重生倒计时:读取 G.settings.spawn_time(模式配置),无配置保持默认 5s 并记录来源
func _init_spawn_time() -> void:
	_spawn_time = float(G.settings.get("spawn_time", 5.0))
	print("[menus] 重生倒计时 = " + str(_spawn_time) + "s (" + ("G.settings.spawn_time" if G.settings.has("spawn_time") else "默认值") + ")")


func _add_screen(id: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	add_child(c)
	_screens[id] = c
	return c


func _bg(parent: Control, color := Color(0.04, 0.05, 0.08, 1)) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg


## ==================== 主菜单(BF2042 风格:左侧竖排模式列表 + 顶部标签 + 战场背景) ====================
func _build_main_menu() -> void:
	var s := _add_screen("menu")
	# 半透明底色(战场景色透出,左侧压暗便于阅读)
	_bg(s, Color(0.01, 0.03, 0.05, 0.55))
	# 程序化战场背景(烟尘 fbm + 军事网格 + 扫描线 shader)
	s.add_child(UiTheme.BattleBg.new())
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.04, 0.55)
	dim.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	dim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dim.custom_minimum_size = Vector2(460, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(dim)
	# ---- 顶部标签栏(BF2042:PLAY / COLLECTION / BATTLE PASS / PROFILE / STORE) ----
	var tabs := HBoxContainer.new()
	tabs.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tabs.position = Vector2(26, 16)
	tabs.add_theme_constant_override("separation", 26)
	s.add_child(tabs)
	var tab_play := UiTheme.make_label("游玩", 15, UiTheme.PRIMARY)
	tabs.add_child(tab_play)
	for t in ["收藏", "战斗通行证", "档案", "商店"]:
		var tl2 := UiTheme.make_label(t, 15, UiTheme.TXT_DIM)
		tabs.add_child(tl2)
	# 装饰:标签下划线
	var tab_line := ColorRect.new()
	tab_line.color = UiTheme.PRIMARY
	tab_line.position = Vector2(26, 42)
	tab_line.size = Vector2(30, 2)
	tab_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(tab_line)
	# ---- 右上:玩家卡 ----
	var trow := VBoxContainer.new()
	trow.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	trow.position = Vector2(-226, 14)
	trow.add_theme_constant_override("separation", 1)
	s.add_child(trow)
	var pc1 := UiTheme.make_label("等级 32", 16, UiTheme.PRIMARY)
	pc1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trow.add_child(pc1)
	var pc2 := UiTheme.make_label("指挥官 · SF-7749", 12, UiTheme.TXT)
	pc2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trow.add_child(pc2)
	var pc3 := UiTheme.make_label("在线好友 3 · 幽灵 猎鹰 毒蛇", 11, UiTheme.TXT_DIM)
	pc3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trow.add_child(pc3)
	# ---- 左侧:游戏标题 + 竖排模式列表 ----
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left.position = Vector2(46, -190)
	left.add_theme_constant_override("separation", 6)
	s.add_child(left)
	var title := UiTheme.make_label("零度行动", 44, UiTheme.TXT)
	left.add_child(title)
	var en := UiTheme.make_label("ZERO OPERATION · 大型多兵种征服/突破作战", 12, UiTheme.PRIMARY)
	left.add_child(en)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 16)
	left.add_child(sep)
	left.add_child(_make_mode_row("征服模式", "CONQUEST · 全面战场 占点为王", false, func():
		G.mode = "conquest"; AudioSys.ui(); on_start.call()))
	left.add_child(_make_mode_row("突破模式", "BREAKTHROUGH · 攻防推进 逐区争夺", false, func():
		G.mode = "breakthrough"; AudioSys.ui(); on_start.call()))
	left.add_child(_make_mode_row("门户模式", "PORTAL · 自定义规则(即将推出)", true, Callable()))
	left.add_child(_make_mode_row("战争故事", "WAR STORIES · 单人战役", false, func():
		AudioSys.ui()
		_open_campaign_select()))
	# ---- 左下:功能按钮 + 连续服役统计 ----
	var bl := VBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(46, -130)
	bl.add_theme_constant_override("separation", 8)
	s.add_child(bl)
	var fn_row := HBoxContainer.new()
	fn_row.add_theme_constant_override("separation", 10)
	bl.add_child(fn_row)
	var bh := UiTheme.make_button("作战手册", 14)
	bh.custom_minimum_size = Vector2(130, 38)
	bh.pressed.connect(func(): AudioSys.ui(); _screens["help"].visible = true)
	fn_row.add_child(bh)
	var bs := UiTheme.make_button("设置", 14)
	bs.custom_minimum_size = Vector2(110, 38)
	bs.pressed.connect(func(): AudioSys.ui(); _settings_from_pause = false; _screens["settings"].visible = true)
	fn_row.add_child(bs)
	var bq := UiTheme.make_button("退出游戏", 14)
	bq.custom_minimum_size = Vector2(110, 38)
	bq.pressed.connect(func(): AudioSys.ui(); get_tree().quit())
	fn_row.add_child(bq)
	bl.add_child(UiTheme.make_label("连续服役 142 场 · 胜率 61%", 12, UiTheme.TXT_DIM))
	# ---- 右下:新闻滚动条 ----
	_news_label = UiTheme.make_label(NEWS[0], 12, UiTheme.TXT_DIM)
	_news_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_news_label.position = Vector2(-560, -34)
	s.add_child(_news_label)


var _news_label: Label = null
var _news_t := 0.0
var _news_i := 0
const NEWS := [
	"［战报］第六战区攻势升级,前线需要更多的指挥官",
	"［公告］新装备:反坦克地雷与 C5 炸药已配发至各兵种",
	"［公告］侦察兵重生信标系统上线,小队可纵深部署",
	"［战报］防空炮仰角扩展至 70°,空中威胁显著降低",
]


## BF2042 风格模式行(大标题 + 英文副题,悬停高亮左移)
func _make_mode_row(cn: String, en: String, disabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.theme = UiTheme.theme()
	b.custom_minimum_size = Vector2(400, 62)
	b.text = cn + "\n" + en
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", UiTheme.TXT if not disabled else UiTheme.TXT_DIM)
	b.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 2, 8))
	b.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.16, 0.22, 0.6), UiTheme.PRIMARY, 1, 2, 8))
	b.add_theme_stylebox_override("pressed", UiTheme.stylebox(Color(0.0, 0.24, 0.3, 0.75), UiTheme.PRIMARY, 1, 2, 8))
	b.add_theme_stylebox_override("focus", UiTheme.stylebox(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 2, 8))
	b.add_theme_stylebox_override("disabled", UiTheme.stylebox(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 2, 8))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", UiTheme.TXT_DIM)
	if disabled:
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.45)
	elif cb.is_valid():
		UiTheme.wire_button(b)
		b.pressed.connect(cb)
	return b


## ==================== 帮助 ====================
func _build_help() -> void:
	var s := _add_screen("help")
	_bg(s, Color(0.02, 0.03, 0.05, 0.96))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(center)
	var panel := UiTheme.make_panel(0.92)
	panel.custom_minimum_size = Vector2(980, 640)
	center.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UiTheme.make_label("作战手册", 26, Color(0.92, 0.95, 1)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	scroll.add_child(text)
	text.text = """[b][color=#7fd0ff]操作[/color][/b]
W A S D 移动 · Shift 冲刺(双击=战术冲刺) · 空格 跳跃 · C/Ctrl 蹲下 · Z 趴下
鼠标左键 射击 · 鼠标右键 机瞄/狙击开镜 · R 换弹 · 1/2/3/滚轮 切换武器
Q 索敌标记 · G 手雷 · F 兵种装备 · E 驾驶/离开载具 · 4/5 连杀奖励 · Tab 记分板 · Esc 暂停

[b][color=#7fd0ff]征服模式规则[/color][/b]
占领并保持分布在战场四处的 A / B / C / D / E 五面旗帜,站在旗圈内即可占领。
击杀敌人使敌方兵力值 -1。当一方控制多数旗帜时,敌方兵力值将持续流失。
先将敌方 400 点兵力值耗尽的一方获胜。占领旗帜后会在该点附近部署载具。

[b][color=#7fd0ff]突破模式规则(攻防)[/color][/b]
你方担任[b]进攻方[/b],沿战线逐区域推进,每区域有 A / B 两个目标点。
[b]同时[/b]控制当前区域全部目标点即可突破该区域,并[b]补充 100 点兵力值[/b];已突破的区域不可被夺回。
进攻方兵力值仅 250 点,每次阵亡 -1,耗尽即战败;防守方兵力无限。攻陷全部 3 个区域即获胜。
每夺取一个目标点都会在该点附近部署载具;阵亡后可在部署界面点击己方点位或绿点小队队友,直接部署到前线。

[b][color=#7fd0ff]兵种[/color][/b]
[color=#7fd0ff]突击兵[/color]:M4A1 / AK-47 / SCAR-H / AUG,可额外携带一把霰弹枪(按 2),医疗包。
[color=#ffc46b]工程兵[/color]:MP5 / UMP45 / P90 + RPG-7(按 3)。瞄准空中载具 1 秒自动锁定,发射防空导弹。
[color=#9fe08a]支援兵[/color]:M249 / PKM / RPD + 弹药箱(按 F 部署,圈内友军持续补给弹药并恢复生命)。
[color=#e0a0ff]侦察兵[/color]:AWM / M24 / SVD + 动态探测器。
副武器(全兵种通用):M1911 均衡 / 格洛克17 速射 / P226 精准 / 沙漠之鹰 手炮 / M93R 冲锋手枪。

[b][color=#7fd0ff]载具(被击毁 10 秒后重新部署)[/color][/b]
地面:侦察吉普 / 装甲步战车(25mm 机炮)/ 自行防空炮 / 主战坦克。
空中(征服模式):武装直升机 / 战斗机 由 AI 驾驶巡逻,可用防空导弹或枪炮击落。
战场上的木质哨棚与岗楼可被爆炸物摧毁。

[b][color=#7fd0ff]连杀奖励[/color][/b]
连杀 3 人:UAV 侦察机(按 4,敌人显示在小地图 25 秒)。
连杀 5 人:炮火支援(按 5,对准星位置弹幕覆盖)。阵亡后连杀清零。
"""
	var close := UiTheme.make_button("返回", 15)
	close.custom_minimum_size = Vector2(200, 38)
	close.pressed.connect(func():
		AudioSys.ui()
		s.visible = false)
	v.add_child(close)


## ==================== 设置 ====================
func _build_settings() -> void:
	var s := _add_screen("settings")
	_bg(s, Color(0.02, 0.03, 0.05, 0.96))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(center)
	var panel := UiTheme.make_panel(0.92)
	panel.custom_minimum_size = Vector2(700, 600)
	center.add_child(panel)
	var outer_v := VBoxContainer.new()
	outer_v.add_theme_constant_override("separation", 8)
	panel.add_child(outer_v)
	outer_v.add_child(UiTheme.make_label("设置", 26, Color(0.92, 0.95, 1)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_v.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	# 操作设置
	v.add_child(UiTheme.make_label("操作", 17, Color(0.6, 0.75, 0.9)))
	v.add_child(_make_slider("鼠标灵敏度", 0.2, 3.0, 0.1, G.settings.sensitivity,
		func(val): G.settings.sensitivity = val, func(val): return "%.1f" % val))
	v.add_child(_make_slider("视野 FOV", 60, 110, 1, G.settings.fov,
		func(val): G.settings.fov = val, func(val): return str(int(val))))
	v.add_child(_make_slider("音量", 0, 1, 0.05, G.settings.volume,
		func(val):
			G.settings.volume = val
			AudioSys.set_volume(val),
		func(val): return str(int(val * 100)) + "%"))
	# 音频分层(总线音量实时生效)
	v.add_child(UiTheme.make_label("音频分层", 17, Color(0.6, 0.75, 0.9)))
	v.add_child(_make_slider("音乐音量", 0, 1, 0.05, G.audio_setting("music_vol", 1.0),
		func(val):
			G.settings["music_vol"] = val
			AudioSys.set_bus_volume(AudioSys.BUS_MUSIC, val),
		func(val): return str(int(val * 100)) + "%"))
	v.add_child(_make_slider("音效音量", 0, 1, 0.05, G.audio_setting("sfx_vol", 1.0),
		func(val):
			G.settings["sfx_vol"] = val
			AudioSys.set_bus_volume(AudioSys.BUS_SFX, val),
		func(val): return str(int(val * 100)) + "%"))
	v.add_child(_make_slider("环境音量", 0, 1, 0.05, G.audio_setting("amb_vol", 1.0),
		func(val):
			G.settings["amb_vol"] = val
			AudioSys.set_bus_volume(AudioSys.BUS_AMBIENCE, val),
		func(val): return str(int(val * 100)) + "%"))
	v.add_child(_make_slider("界面音量", 0, 1, 0.05, G.audio_setting("ui_vol", 1.0),
		func(val):
			G.settings["ui_vol"] = val
			AudioSys.set_bus_volume(AudioSys.BUS_UI, val),
		func(val): return str(int(val * 100)) + "%"))
	# 画质设置
	v.add_child(UiTheme.make_label("画质", 17, Color(0.6, 0.75, 0.9)))
	v.add_child(_make_select("画质预设", [[0, "低 (性能)"], [1, "中"], [2, "高 (推荐)"], [3, "极致"]],
		GraphicsQuality.current_level, func(val):
			GraphicsQuality.apply_preset(val)
			GraphicsQuality.save_config()))
	v.add_child(_make_select("分辨率缩放", [[0.7, "70% 性能"], [0.85, "85%"], [1.0, "100% 原生"], [1.25, "125% 超采样"]],
		G.settings.scale, func(val): _apply_gfx("scale", val)))
	v.add_child(_make_select("纹理过滤", [[1, "低"], [4, "中"], [8, "高"], [16, "极高"]],
		G.settings.aniso, func(val): _apply_gfx("aniso", val)))
	v.add_child(_make_select("阴影质量", [[0, "关"], [1024, "低"], [2048, "中"], [4096, "高"]],
		G.settings.shadows, func(val): _apply_gfx("shadows", val)))
	v.add_child(_make_select("SSAO 遮蔽", [[true, "开"], [false, "关"]],
		G.settings.ssao, func(val): _apply_gfx("ssao", val)))
	v.add_child(_make_select("抗锯齿 FXAA", [[true, "开"], [false, "关"]],
		G.settings.fxaa, func(val): _apply_gfx("fxaa", val)))
	v.add_child(_make_select("粒子质量", [[1.0, "高"], [0.5, "中"], [0.25, "低"]],
		G.settings.particles, func(val): _apply_gfx("particles", val)))
	v.add_child(_make_select("雾效距离", [[0.7, "近"], [1.0, "标准"], [1.5, "远"]],
		G.settings.fog, func(val): _apply_gfx("fog", val)))
	var close := UiTheme.make_button("返回", 15)
	close.custom_minimum_size = Vector2(200, 38)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		AudioSys.ui()
		var from_pause := _settings_from_pause
		_settings_from_pause = false
		s.visible = false
		if from_pause:
			_screens["pause"].visible = true)  # 暂停中打开设置 → 返回暂停界面
	outer_v.add_child(close)


func _apply_gfx(key: String, val) -> void:
	G.settings[key] = val
	if G.apply_graphics.is_valid():
		G.apply_graphics.call()
	AudioSys.ui()


func _make_slider(label_text: String, min_v: float, max_v: float, step: float, cur: float,
		on_change: Callable, fmt: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiTheme.make_label(label_text, 14, Color(0.75, 0.8, 0.85))
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = cur
	slider.custom_minimum_size = Vector2(320, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val_l := UiTheme.make_label(fmt.call(cur), 14, Color(0.85, 0.88, 0.9))
	val_l.custom_minimum_size = Vector2(60, 0)
	row.add_child(val_l)
	slider.mouse_entered.connect(func(): AudioSys.ui_hover())
	slider.value_changed.connect(func(val):
		val_l.text = fmt.call(val)
		on_change.call(val)
		AudioSys.ui_hover())
	UiTheme.style_slider(slider)
	return row


func _make_select(label_text: String, options: Array, cur, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiTheme.make_label(label_text, 14, Color(0.75, 0.8, 0.85))
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.theme = UiTheme.theme()
	ob.custom_minimum_size = Vector2(200, 0)
	var sel_idx := 0
	for i in options.size():
		ob.add_item(options[i][1], i)
		if options[i][0] == cur:
			sel_idx = i
	ob.selected = sel_idx
	row.add_child(ob)
	ob.item_selected.connect(func(idx):
		on_change.call(options[idx][0]))
	return row


## ==================== 部署界面(BF2042 风格:战区图 + 底部装备栏 + 兵种二级菜单) ====================
func _build_deploy() -> void:
	var s := _add_screen("deploy")
	_bg(s, Color(0, 0.01, 0.02, 0.97))
	s.add_child(UiTheme.BattleBg.new())
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 20
	root.offset_top = 14
	root.offset_right = -20
	root.offset_bottom = -14
	s.add_child(root)
	# ---- 顶栏:模式·地图 + 双方兵力 ----
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 30)
	root.add_child(top)
	_deploy_title = UiTheme.make_label("选择兵种并部署", 22, UiTheme.TXT)
	top.add_child(_deploy_title)
	var tickets := HBoxContainer.new()
	tickets.add_theme_constant_override("separation", 16)
	top.add_child(tickets)
	_dep_ticket_us = UiTheme.make_label("友军 400", 18, UiTheme.FRIENDLY)
	tickets.add_child(_dep_ticket_us)
	_dep_ticket_ru = UiTheme.make_label("敌军 400", 18, UiTheme.ENEMY)
	tickets.add_child(_dep_ticket_ru)
	# ---- 突破模式:选择阵营(进攻方 us / 防守方 ru,只改变玩家阵营,世界攻防方向固定) ----
	_side_sel = HBoxContainer.new()
	_side_sel.alignment = BoxContainer.ALIGNMENT_CENTER
	_side_sel.add_theme_constant_override("separation", 10)
	root.add_child(_side_sel)
	_side_sel.add_child(UiTheme.make_label("选择阵营:", 16, UiTheme.PRIMARY))
	var side_hint := UiTheme.make_label("我方阵营决定出生点与敌我识别;世界攻防方向不变(进攻方兵力有限)", 12, UiTheme.TXT_DIM)
	_side_sel.add_child(side_hint)
	_btn_side_att = UiTheme.make_button("进攻方(兵力有限)", 14)
	_btn_side_att.toggle_mode = true
	_btn_side_att.custom_minimum_size = Vector2(180, 36)
	_side_sel.add_child(_btn_side_att)
	_btn_side_def = UiTheme.make_button("防守方(兵力无限)", 14)
	_btn_side_def.toggle_mode = true
	_btn_side_def.custom_minimum_size = Vector2(180, 36)
	_side_sel.add_child(_btn_side_def)
	_btn_side_att.pressed.connect(func():
		AudioSys.ui()
		_btn_side_att.button_pressed = true
		_btn_side_def.button_pressed = false
		G.game.set_bt_side("att")
		_refresh_ticket_labels()
		_build_squad_list()
		_deploy_map.queue_redraw())
	_btn_side_def.pressed.connect(func():
		AudioSys.ui()
		_btn_side_def.button_pressed = true
		_btn_side_att.button_pressed = false
		G.game.set_bt_side("def")
		_refresh_ticket_labels()
		_build_squad_list()
		_deploy_map.queue_redraw())
	# ---- 主体:左侧战区图 + 右侧小队栏 ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var map_area := VBoxContainer.new()
	map_area.add_theme_constant_override("separation", 8)
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(map_area)
	map_area.add_child(UiTheme.make_label("战区俯视图 — 点击己方点位 / 绿点队友 / 菱形信标 部署", 13, UiTheme.PRIMARY))
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	map_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_area.add_child(map_row)
	_deploy_map = DeployMap.new()
	_deploy_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deploy_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deploy_map.custom_minimum_size = Vector2(430, 430)
	map_row.add_child(_deploy_map)
	_squad_list = VBoxContainer.new()
	_squad_list.add_theme_constant_override("separation", 4)
	_squad_list.custom_minimum_size = Vector2(190, 0)
	map_row.add_child(_squad_list)
	map_area.add_child(UiTheme.make_label("地图选择", 13, UiTheme.TXT_DIM))
	_map_select = HBoxContainer.new()
	_map_select.add_theme_constant_override("separation", 6)
	map_area.add_child(_map_select)
	# ---- 兵种二级菜单(底部装备栏槽位上方弹出) ----
	_submenu = PanelContainer.new()
	_submenu.add_theme_stylebox_override("panel", UiTheme.panel_box(0.94))
	_submenu.custom_minimum_size = Vector2(0, 168)
	_submenu.visible = false
	root.add_child(_submenu)
	# ---- 底部装备栏(BF2042:兵种 / 主武器 / 副武器 / 装备 / 投掷 + DEPLOY) ----
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.custom_minimum_size = Vector2(0, 72)
	root.add_child(bar)
	_slot_class = _make_slot("兵种", "", func(): _toggle_submenu("class"))
	bar.add_child(_slot_class)
	_slot_primary = _make_slot("主武器", "", func(): _toggle_submenu("primary"))
	bar.add_child(_slot_primary)
	_slot_shotgun = _make_slot("随身霰弹枪", "", func(): _toggle_submenu("shotgun"))
	bar.add_child(_slot_shotgun)
	_slot_secondary = _make_slot("副武器", "", func(): _toggle_submenu("secondary"))
	bar.add_child(_slot_secondary)
	var gadget_slot := _make_slot("兵种装备", "", Callable())
	bar.add_child(gadget_slot)
	var nade_slot := _make_slot("投掷物", "", Callable())
	bar.add_child(nade_slot)
	gadget_slot.disabled = true
	nade_slot.disabled = true
	_gadget_slot_btn = gadget_slot
	_nade_slot_btn = nade_slot
	# DEPLOY 按钮(右侧青绿大按钮)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var btn_deploy := UiTheme.make_cta("部  署", 26)
	btn_deploy.custom_minimum_size = Vector2(230, 72)
	btn_deploy.pressed.connect(func():
		AudioSys.ui()
		btn_deploy.disabled = true
		# 部署确认覆盖层:弹出动画 → 0.7s 后正式部署
		_deploy_overlay.visible = true
		_deploy_overlay.scale = Vector2(0.6, 0.6)
		_deploy_overlay.modulate.a = 0.0
		var tw := _deploy_overlay.create_tween()
		tw.set_parallel(true)
		tw.tween_property(_deploy_overlay, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_deploy_overlay, "modulate:a", 1.0, 0.18)
		get_tree().create_timer(0.7).timeout.connect(func():
			_deploy_overlay.visible = false
			btn_deploy.disabled = false
			on_deploy.call(selected_class, loadout[selected_class])))
	bar.add_child(btn_deploy)
	# 部署确认覆盖层(居中大字)
	_deploy_overlay = UiTheme.make_label("正在部署战区…", 34, UiTheme.PRIMARY)
	_deploy_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_deploy_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deploy_overlay.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.0, 0.04, 0.06, 0.88), UiTheme.PRIMARY, 1, 4, 24))
	_deploy_overlay.visible = false
	_deploy_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(_deploy_overlay)
	_deploy_map.spawn_selected.connect(func(): _build_squad_list())
	_refresh_slots()


func show_deploy(is_redeploy := false) -> void:
	_refresh_ticket_labels()
	var map_name: String = MapsData.M()[G.current_map].cn if MapsData.M().has(G.current_map) else ""
	var mode_name := ("突破模式(" + ("进攻方" if G.bt_player_side == "att" else "防守方") + ")") if G.mode == "breakthrough" else "征服模式"
	_deploy_title.text = mode_name + " · 选择兵种并部署 — " + map_name
	_map_select.visible = not is_redeploy
	_side_sel.visible = (not is_redeploy) and G.mode == "breakthrough"
	_btn_side_att.button_pressed = G.bt_player_side == "att"
	_btn_side_def.button_pressed = G.bt_player_side == "def"
	_close_submenu()
	_refresh_slots()
	# 调试:--dbg-submenu <class|primary|shotgun|secondary> 自动打开兵种二级菜单
	var ua := OS.get_cmdline_user_args()
	var dbg_idx := ua.find("--dbg-submenu")
	if dbg_idx != -1 and ua.size() > dbg_idx + 1:
		_toggle_submenu(ua[dbg_idx + 1])
	_build_map_select()
	_build_squad_list()
	_screens["deploy"].visible = true
	_deploy_map.queue_redraw()


func hide_deploy() -> void:
	_screens["deploy"].visible = false


## 部署界面双方兵力文本:左=我方阵营票,右=敌方阵营票(突破防守方显示 ∞)
func _refresh_ticket_labels() -> void:
	var my_t: float = G.tickets[G.player.team]
	var en_t: float = G.tickets["ru" if G.player.team == "us" else "us"]
	_dep_ticket_us.text = "友军 " + ("∞" if is_inf(my_t) else str(int(ceil(my_t))))
	_dep_ticket_ru.text = "敌军 " + ("∞" if is_inf(en_t) else str(int(ceil(en_t))))


## ---- 装备槽按钮(BF2042 底部栏:标题小字 + 当前选项大字) ----
var _gadget_slot_btn: Button
var _nade_slot_btn: Button


func _make_slot(title: String, current: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme = UiTheme.theme()
	b.custom_minimum_size = Vector2(170, 72)
	b.text = title.to_upper() + "\n" + current
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UiTheme.TXT)
	b.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.0, 0.05, 0.08, 0.92), Color(0.25, 0.33, 0.4, 0.6), 1, 3, 8))
	b.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.16, 0.22, 0.95), UiTheme.PRIMARY, 1, 3, 8))
	b.add_theme_stylebox_override("pressed", UiTheme.stylebox(Color(0.0, 0.22, 0.28, 0.98), UiTheme.PRIMARY, 2, 3, 8))
	b.add_theme_stylebox_override("focus", UiTheme.stylebox(Color(0.0, 0.05, 0.08, 0.92), Color(0.25, 0.33, 0.4, 0.6), 1, 3, 8))
	b.add_theme_stylebox_override("disabled", UiTheme.stylebox(Color(0.02, 0.03, 0.05, 0.85), Color(0.15, 0.2, 0.24, 0.4), 1, 3, 8))
	b.add_theme_color_override("font_disabled_color", UiTheme.TXT_DIM)
	UiTheme.wire_button(b)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _set_slot(b: Button, title: String, current: String) -> void:
	b.text = title.to_upper() + "\n" + current


## 刷新装备栏显示(当前兵种配装)
func _refresh_slots() -> void:
	var cls = WeaponsData.C()[selected_class]
	var lo: Dictionary = loadout[selected_class]
	_set_slot(_slot_class, "兵种", cls.icon + " " + cls.cn)
	_set_slot(_slot_primary, "主武器", WeaponsData.W()[lo["primary"]].cn)
	_slot_shotgun.visible = not cls.shotguns.is_empty()
	if not cls.shotguns.is_empty():
		_set_slot(_slot_shotgun, "随身霰弹枪", WeaponsData.W()[lo.get("shotgun", cls.shotguns[0])].cn)
	_set_slot(_slot_secondary, "副武器", WeaponsData.W()[lo["secondary"]].cn)
	_set_slot(_gadget_slot_btn, "兵种装备", cls.gadget_cn + " ×" + str(cls.gadget_count))
	_set_slot(_nade_slot_btn, "投掷物", "手雷 ×2")


## ---- 兵种二级菜单(槽位点击弹出;主/副武器均在兵种二级菜单内) ----
func _toggle_submenu(kind: String) -> void:
	AudioSys.ui()
	if _submenu_open == kind and _submenu.visible:
		_close_submenu()
		return
	_submenu_open = kind
	_open_submenu(kind)


func _close_submenu() -> void:
	_submenu_open = ""
	_submenu.visible = false


func _open_submenu(kind: String) -> void:
	for c in _submenu.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_submenu.add_child(v)
	var cls = WeaponsData.C()[selected_class]
	var lo: Dictionary = loadout[selected_class]
	match kind:
		"class":
			v.add_child(UiTheme.make_label("选择兵种", 14, UiTheme.PRIMARY))
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			v.add_child(grid)
			for cid in WeaponsData.C():
				grid.add_child(_make_class_card(cid, cid == selected_class))
		"primary":
			v.add_child(UiTheme.make_label(cls.cn + " — 选择主武器", 14, UiTheme.PRIMARY))
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			v.add_child(grid)
			for wid in cls.weapons:
				grid.add_child(_make_weapon_card(wid, lo["primary"] == wid,
					func(): _select_weapon("primary", wid)))
		"shotgun":
			v.add_child(UiTheme.make_label(cls.cn + " — 选择随身霰弹枪(按 2 切换)", 14, UiTheme.PRIMARY))
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			v.add_child(grid)
			for wid in cls.shotguns:
				grid.add_child(_make_weapon_card(wid, lo.get("shotgun") == wid,
					func(): _select_weapon("shotgun", wid)))
		"secondary":
			v.add_child(UiTheme.make_label(cls.cn + " — 选择副武器(全兵种通用)", 14, UiTheme.PRIMARY))
			var grid := GridContainer.new()
			grid.columns = 5
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			v.add_child(grid)
			for wid in cls.secondaries:
				grid.add_child(_make_weapon_card(wid, lo["secondary"] == wid,
					func(): _select_weapon("secondary", wid)))
	_submenu.visible = true


func _make_class_card(cid: String, selected: bool) -> Button:
	var cls = WeaponsData.C()[cid]
	var card := Button.new()
	card.theme = UiTheme.theme()
	card.toggle_mode = true
	card.button_pressed = selected
	card.custom_minimum_size = Vector2(240, 108)
	var role_line: String = { "assault": "破阵 / 烟雾 / C5 / 自疗", "engineer": "反载具 / 维修 / RPG",
		"support": "补给 / 医疗 / 烟雾", "recon": "狙击 / 标记 / 信标" }.get(cid, "")
	card.text = cls.icon + " " + cls.cn + "  " + cls.en + "\n" + role_line + "\n" + cls.gadget_cn + " ×" + str(cls.gadget_count)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_theme_font_size_override("font_size", 13)
	card.add_theme_color_override("font_color", UiTheme.TXT)
	_style_card(card, selected, cls.color)
	UiTheme.wire_button(card)
	card.pressed.connect(func():
		AudioSys.ui()
		selected_class = cid
		_refresh_slots()
		_close_submenu())  # 选定后自动退回装备栏界面
	return card


func _style_card(card: Button, selected: bool, accent: Color) -> void:
	var bg := Color(0.0, 0.12, 0.16, 0.92) if selected else Color(0.0, 0.03, 0.05, 0.9)
	var border := accent if selected else Color(0.2, 0.28, 0.34, 0.5)
	card.add_theme_stylebox_override("normal", UiTheme.stylebox(bg, border, 2 if selected else 1, 3, 8))
	card.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.18, 0.24, 0.95), border, 2, 3, 8))
	card.add_theme_stylebox_override("pressed", UiTheme.stylebox(bg, border, 2, 3, 8))
	card.add_theme_stylebox_override("focus", UiTheme.stylebox(bg, border, 2, 3, 8))


func _make_weapon_card(wid: String, selected: bool, cb: Callable) -> Button:
	var w = WeaponsData.W()[wid]
	var b := Button.new()
	b.theme = UiTheme.theme()
	b.toggle_mode = true
	b.button_pressed = selected
	b.custom_minimum_size = Vector2(240, 88)
	var dmg_text := str(w.damage) + ("×" + str(w.pellets) if w.pellets > 1 else "")
	b.text = w.cn + "\n伤害 " + dmg_text + " · 射速 " + str(w.rpm) + " · 弹匣 " + str(w.mag)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UiTheme.TXT)
	var bg := Color(0.0, 0.14, 0.18, 0.95) if selected else Color(0.0, 0.03, 0.05, 0.9)
	var border := UiTheme.PRIMARY if selected else Color(0.22, 0.28, 0.34, 0.5)
	b.add_theme_stylebox_override("normal", UiTheme.stylebox(bg, border, 1, 3, 6))
	b.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.2, 0.26, 0.95), border, 1, 3, 6))
	b.add_theme_stylebox_override("pressed", UiTheme.stylebox(bg, border, 1, 3, 6))
	b.add_theme_stylebox_override("focus", UiTheme.stylebox(bg, border, 1, 3, 6))
	UiTheme.wire_button(b)
	b.pressed.connect(cb)
	return b


func _select_weapon(kind: String, wid: String) -> void:
	AudioSys.ui()
	loadout[selected_class][kind] = wid
	_refresh_slots()
	_close_submenu()  # 选定一把武器后自动退回装备栏界面(兵种/主武器/副武器槽)


func _build_map_select() -> void:
	for c in _map_select.get_children():
		c.queue_free()
	_map_btns.clear()
	var pool := []
	for mid in MapsData.M():
		var m = MapsData.M()[mid]
		if (m.mode if m.mode != "" else "conquest") == G.mode:
			pool.append([mid, m.cn])
	var defs := [["random", "随机地图"]] + pool
	for dd in defs:
		var b := UiTheme.make_button(dd[1], 13)
		b.toggle_mode = true
		b.button_pressed = (G.sel_maps.get(G.mode, "random") == dd[0])
		b.pressed.connect(func():
			AudioSys.ui()
			G.sel_maps[G.mode] = dd[0]
			_build_map_select()
			# 立即重建地图并刷新部署界面
			var pool_ids := pool.map(func(e): return e[0])
			var map_id: String = Utils.choice(pool_ids) if dd[0] == "random" else dd[0]
			G.game.setup_map(map_id)
			_refresh_ticket_labels()
			_deploy_map.queue_redraw())
		_map_select.add_child(b)
		_map_btns.append(b)


func _build_squad_list() -> void:
	for c in _squad_list.get_children():
		c.queue_free()
	_squad_list.add_child(UiTheme.make_label("小队部署", 14, Color(0.55, 0.62, 0.7)))
	var hud = G.hud
	var base := UiTheme.make_button("基地\n默认出生点", 12)
	base.toggle_mode = true
	base.button_pressed = hud.spawn_mate == null and hud.spawn_point == null
	base.pressed.connect(func():
		AudioSys.ui()
		hud.spawn_mate = null
		hud.spawn_point = null
		_build_squad_list()
		_deploy_map.queue_redraw())
	_squad_list.add_child(base)
	if G.player_squad != null:
		for m in G.player_squad["members"]:
			var ok: bool = m.alive and m.vehicle == null
			var b := UiTheme.make_button(m.bot_name + "\n" + ("驾驶中" if m.vehicle != null else ("存活" if m.alive else "阵亡")), 12)
			b.toggle_mode = true
			b.button_pressed = hud.spawn_mate == m
			b.disabled = not ok
			if ok:
				b.pressed.connect(func():
					AudioSys.ui()
					hud.spawn_mate = m
					hud.spawn_point = null
					_build_squad_list()
					_deploy_map.queue_redraw())
			_squad_list.add_child(b)


## ==================== 死亡界面 ====================
func _build_death() -> void:
	var s := _add_screen("death")
	_bg(s, Color(0.1, 0.02, 0.02, 0.55))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)
	var t := UiTheme.make_label("system fail", 44, Color(1, 0.4, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_death_killer = UiTheme.make_label("", 18, Color(0.9, 0.75, 0.7))
	_death_killer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_killer)
	var b := UiTheme.make_button("重新部署", 18)
	b.custom_minimum_size = Vector2(260, 46)
	b.pressed.connect(func():
		AudioSys.ui()
		on_redeploy.call())
	v.add_child(b)
	_death_btn = b
	_death_btn.disabled = true
	_death_btn.text = "重新部署 (" + str(int(ceil(_spawn_time))) + ")"


func show_death(killer_text: String) -> void:
	_death_killer.text = killer_text
	_death_t = _spawn_time
	if _death_btn != null:
		_death_btn.disabled = true
		_death_btn.text = "重新部署 (" + str(int(ceil(_spawn_time))) + ")"
		_death_btn.scale = Vector2.ONE
		_death_btn.modulate = Color(0.85, 0.85, 0.85, 0.9)
	_screens["death"].visible = true


func hide_death() -> void:
	_screens["death"].visible = false
	if _death_btn != null:
		_death_btn.disabled = true
		_death_btn.text = "重新部署 (" + str(int(ceil(_spawn_time))) + ")"
		_death_btn.scale = Vector2.ONE
		_death_btn.modulate = Color(1, 1, 1, 1)


## ==================== 结算界面 ====================
func _build_end() -> void:
	var s := _add_screen("end")
	_bg(s, Color(0.02, 0.03, 0.05, 0.92))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	_end_title = UiTheme.make_label("胜 利", 56, Color(1, 0.85, 0.4))
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_end_title)
	_end_stats = RichTextLabel.new()
	_end_stats.bbcode_enabled = true
	_end_stats.fit_content = true
	_end_stats.scroll_active = false
	_end_stats.add_theme_font_size_override("normal_font_size", 18)
	v.add_child(_end_stats)
	var b1 := UiTheme.make_button("再战一局", 18)
	b1.custom_minimum_size = Vector2(280, 46)
	b1.pressed.connect(func():
		AudioSys.ui()
		on_again.call())
	v.add_child(b1)
	var b2 := UiTheme.make_button("返回主菜单", 15)
	b2.custom_minimum_size = Vector2(280, 40)
	b2.pressed.connect(func():
		AudioSys.ui()
		on_quit.call())
	v.add_child(b2)


func show_end(win: bool) -> void:
	var is_bt := G.mode == "breakthrough"
	_end_title.text = ("全线突破" if win else "进攻失败") if (is_bt and G.bt_player_side == "att") else (("防守成功" if win else "防线失守") if is_bt else ("胜 利" if win else "战 败"))
	_end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if win else Color(0.85, 0.4, 0.35))
	var kd := "%.2f" % (float(G.stats["kills"]) / maxf(1, float(G.stats["deaths"])))
	var line2 := ""
	if is_bt:
		var sec_done: int = mini(G.bt["sector"], G.bt["total"]) if G.bt != null else 0
		var total: int = G.bt["total"] if G.bt != null else 3
		var att_left: int = maxi(0, int(ceil(G.tickets["us"])))
		if G.bt_player_side == "att":
			line2 = "攻陷区域 [b]" + str(sec_done) + "/" + str(total) + "[/b] · 剩余兵力 [b]" + str(att_left) + "[/b] · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]"
		else:
			line2 = "防守方坚守 [b]" + str(sec_done) + "/" + str(total) + "[/b] 区域 · 进攻方剩余兵力 [b]" + str(att_left) + "[/b] · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]"
	else:
		line2 = "最终兵力 — 友军 [b]" + str(maxi(0, int(ceil(G.tickets[G.player.team])))) + "[/b] : [b]" + str(maxi(0, int(ceil(G.tickets["ru" if G.player.team == "us" else "us"])))) + "[/b] 敌军 · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]"
	_end_stats.text = "击杀 [b]" + str(G.stats["kills"]) + "[/b] · 阵亡 [b]" + str(G.stats["deaths"]) + "[/b] · KD [b]" + kd + "[/b]\n" + line2
	_screens["end"].visible = true


## ==================== 战役模式(战争故事):章节选择屏 + 结算屏 + 存档 ====================
const CAMPAIGN_SAVE_PATH := "user://campaign_save.cfg"
var _campaign_connected := false     # 章节结算 signal 懒连接标记
var _campaign_cur_index := -1        # 当前游玩章节索引(结算屏"下一章"定位)
var _campaign_done: Array = []       # 已完成章节 id(存档)
var _camp_grid: GridContainer
var _camp_progress: Label
var _camp_end_title: Label
var _camp_end_sub: Label
var _camp_end_stats: Label
var _camp_end_btn1: Button
var _camp_end_win := false


## 只读读取战役章节数据(CampaignData 未就绪/缺失时返回空,不硬依赖他方文件)
func _campaign_chapters() -> Array:
	if not ResourceLoader.exists("res://src/campaign/campaign_data.gd"):
		return []
	var CD = load("res://src/campaign/campaign_data.gd")
	if CD == null or not CD.has_method("chapters"):
		return []
	return CD.chapters()


## 存档:读取解锁进度
func _campaign_load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CAMPAIGN_SAVE_PATH) != OK:
		return
	G.campaign_unlocked = maxi(1, int(cfg.get_value("campaign", "unlocked", 1)))
	_campaign_done = cfg.get_value("campaign", "completed", [])


## 存档:章节完成 → 解锁下一章(第 i 章完成 → unlocked = i+2)+ 记录已完成
func campaign_save_unlock(chapter_index: int) -> void:
	G.campaign_unlocked = maxi(G.campaign_unlocked, chapter_index + 2)
	if G.campaign_pending_id != "" and not _campaign_done.has(G.campaign_pending_id):
		_campaign_done.append(G.campaign_pending_id)
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "unlocked", G.campaign_unlocked)
	cfg.set_value("campaign", "completed", _campaign_done)
	cfg.save(CAMPAIGN_SAVE_PATH)


func _on_chapter_finished(win: bool) -> void:
	show_campaign_end(win)


## ==================== 战役章节选择屏 ====================
func _build_campaign_select() -> void:
	var s := _add_screen("campaign")
	_bg(s, Color(0.01, 0.03, 0.05, 0.96))
	s.add_child(UiTheme.BattleBg.new())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 30
	v.offset_top = 22
	v.offset_right = -30
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 10)
	s.add_child(v)
	# 顶栏:标题 + 解锁进度
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UiTheme.make_label("战争故事", 34, UiTheme.TXT))
	head.add_child(UiTheme.make_label("WAR STORIES · 单人战役", 15, UiTheme.PRIMARY))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_camp_progress = UiTheme.make_label("", 14, UiTheme.TXT_DIM)
	head.add_child(_camp_progress)
	# 章节卡网格(3 列)
	_camp_grid = GridContainer.new()
	_camp_grid.columns = 3
	_camp_grid.add_theme_constant_override("h_separation", 12)
	_camp_grid.add_theme_constant_override("v_separation", 12)
	_camp_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_camp_grid)
	_refresh_campaign_cards()
	var back := UiTheme.make_button("返回主菜单", 15)
	back.custom_minimum_size = Vector2(200, 38)
	back.pressed.connect(func():
		AudioSys.ui()
		_screens["campaign"].visible = false
		_screens["menu"].visible = true)
	v.add_child(back)


## 重建章节卡(解锁状态随进度变化,打开屏时刷新)
func _refresh_campaign_cards() -> void:
	for c in _camp_grid.get_children():
		_camp_grid.remove_child(c)
		c.queue_free()
	var chs: Array = _campaign_chapters()
	_camp_progress.text = "已解锁 " + str(mini(G.campaign_unlocked, chs.size())) + "/" + str(chs.size()) + " 章"
	for i in chs.size():
		_camp_grid.add_child(_make_campaign_card(chs[i], i))


## 章节卡:标题/副题/地图名/一句话梗概;锁定章 🔒 + 解锁条件
func _make_campaign_card(d: Dictionary, idx: int) -> Button:
	var locked: bool = idx >= G.campaign_unlocked
	var cn: String = str(d.get("cn", d.get("title", "第 " + str(idx + 1) + " 章")))
	var en: String = str(d.get("title", ""))
	var map_id: String = str(d.get("map", ""))
	var map_cn: String = MapsData.M()[map_id].cn if MapsData.M().has(map_id) else map_id
	var brief: Array = d.get("briefing", [])
	var blurb := ""
	if not brief.is_empty() and brief[0] is Dictionary:
		blurb = str(brief[0].get("text", ""))
	var b := Button.new()
	b.theme = UiTheme.theme()
	b.custom_minimum_size = Vector2(400, 148)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = (("🔒 " if locked else "◆ ") + cn + "  " + en + "\n") + ("地图: " + map_cn) + ("\n" + blurb if blurb != "" else "")
	if locked:
		b.text += "\n🔒 完成第 " + str(idx) + " 章解锁"
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiTheme.TXT)
	var bg := Color(0.0, 0.05, 0.08, 0.9)
	var border := Color(0.3, 0.38, 0.45, 0.55)
	b.add_theme_stylebox_override("normal", UiTheme.stylebox(bg, border, 1, 3, 10))
	b.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.2, 0.28, 0.95), UiTheme.PRIMARY, 2, 3, 10))
	b.add_theme_stylebox_override("pressed", UiTheme.stylebox(Color(0.0, 0.28, 0.36, 0.98), UiTheme.PRIMARY, 2, 3, 10))
	b.add_theme_stylebox_override("focus", UiTheme.stylebox(bg, border, 1, 3, 10))
	b.add_theme_stylebox_override("disabled", UiTheme.stylebox(Color(0.03, 0.04, 0.06, 0.85), Color(0.15, 0.2, 0.24, 0.4), 1, 3, 10))
	b.add_theme_color_override("font_disabled_color", UiTheme.TXT_DIM)
	if locked:
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.5)
	else:
		UiTheme.wire_button(b)
		b.pressed.connect(func():
			_campaign_enter(idx, d))
	return b


## 点击已解锁章节 → 确认进入(写 pending id → 关闭屏 → 启动)
func _campaign_enter(idx: int, d: Dictionary) -> void:
	AudioSys.ui()
	var cid: String = str(d.get("id", ""))
	if cid == "":
		return
	G.campaign_pending_id = cid
	_campaign_cur_index = idx
	hide_all()
	if on_campaign_start.is_valid():
		on_campaign_start.call()


func _open_campaign_select() -> void:
	_campaign_load_save()
	_refresh_campaign_cards()
	_screens["campaign"].visible = true


## ==================== 战役结算屏 ====================
func _build_campaign_end() -> void:
	var s := _add_screen("campaign_end")
	_bg(s, Color(0.02, 0.03, 0.05, 0.94))
	s.add_child(UiTheme.BattleBg.new())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(center)
	var panel := UiTheme.make_panel(0.92)
	panel.custom_minimum_size = Vector2(640, 470)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	_camp_end_title = UiTheme.make_label("任务完成", 46, Color(1, 0.85, 0.4))
	_camp_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_camp_end_title)
	_camp_end_sub = UiTheme.make_label("", 16, UiTheme.TXT_DIM)
	_camp_end_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_camp_end_sub)
	_camp_end_stats = UiTheme.make_label("", 15, UiTheme.TXT)
	_camp_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_camp_end_stats)
	_camp_end_btn1 = UiTheme.make_button("下一章", 18)
	_camp_end_btn1.custom_minimum_size = Vector2(300, 46)
	_camp_end_btn1.pressed.connect(func():
		_campaign_end_primary())
	v.add_child(_camp_end_btn1)
	var b2 := UiTheme.make_button("返回章节选择", 15)
	b2.custom_minimum_size = Vector2(300, 40)
	b2.pressed.connect(func():
		_campaign_end_back())
	v.add_child(b2)


## 结算屏显示(win=true 任务完成+epilogue+下一章;win=false 任务失败+重试)
func show_campaign_end(win: bool) -> void:
	_camp_end_win = win
	G.state = "menu"
	G.paused = false
	if G.hud != null:
		G.hud.hide_screen("hud")
		G.hud.hide_screen("death")
	if G.input_sys != null:
		G.input_sys.unlock()
	var chs: Array = _campaign_chapters()
	var has_next: bool = win and (_campaign_cur_index + 1) < chs.size()
	_camp_end_title.text = "任务完成" if win else "任务失败"
	_camp_end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if win else Color(0.85, 0.4, 0.35))
	var d: Dictionary = chs[_campaign_cur_index] if (_campaign_cur_index >= 0 and _campaign_cur_index < chs.size()) else {}
	var cn: String = str(d.get("cn", "第 " + str(_campaign_cur_index + 1) + " 章"))
	if win:
		var ep = d.get("epilogue", "")
		var lines: Array = []
		if ep is Array:
			for e in ep:
				lines.append(str(e.get("text", e) if e is Dictionary else e))
		else:
			lines.append(str(ep))
		_camp_end_sub.text = "章节达成:" + cn + "\n" + "\n".join(lines)
		_camp_end_btn1.text = "下一章" if has_next else "终章通关 · 战役完成"
		_camp_end_btn1.disabled = not has_next
		campaign_save_unlock(_campaign_cur_index)
	else:
		_camp_end_sub.text = "章节失败:" + cn + "\n部队未能达成目标,重整旗鼓再试一次。"
		_camp_end_btn1.text = "重试本章"
		_camp_end_btn1.disabled = false
	_camp_end_stats.text = "击杀 " + str(G.stats["kills"]) + " · 阵亡 " + str(G.stats["deaths"]) + " · 用时 " + Utils.fmt_time(G.time)
	hide_all()
	_screens["campaign_end"].visible = true


## 结算主按钮:win → 下一章(无则禁用);fail → 重试本章
func _campaign_end_primary() -> void:
	AudioSys.ui()
	var chs: Array = _campaign_chapters()
	if _camp_end_win:
		if (_campaign_cur_index + 1) >= chs.size():
			return
		var nid: String = str(chs[_campaign_cur_index + 1].get("id", ""))
		if nid == "":
			return
		G.campaign_pending_id = nid
		_campaign_cur_index += 1
	hide_all()
	if on_campaign_start.is_valid():
		on_campaign_start.call()


## 结算 → 返回章节选择屏(回主菜单态,ready room 露出)
func _campaign_end_back() -> void:
	AudioSys.ui()
	G.state = "menu"
	G.paused = false
	if G.input_sys != null:
		G.input_sys.unlock()
	if G.hud != null:
		G.hud.hide_screen("hud")
	hide_all()
	_screens["campaign"].visible = true


## ==================== 暂停 ====================
func _build_pause() -> void:
	var s := _add_screen("pause")
	_bg(s, Color(0.02, 0.03, 0.05, 0.7))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var t := UiTheme.make_label("已暂停", 36, Color(0.92, 0.95, 1))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b1 := UiTheme.make_button("继续战斗", 18)
	b1.custom_minimum_size = Vector2(260, 46)
	b1.pressed.connect(func():
		AudioSys.ui()
		on_resume.call())
	v.add_child(b1)
	# 战役模式:线性关卡无部署系统,隐藏"切换兵种"(避免误入部署屏/消耗阵亡次数)
	var b_switch := UiTheme.make_button("切换兵种", 15)
	b_switch.custom_minimum_size = Vector2(260, 40)
	b_switch.pressed.connect(func():
		AudioSys.ui()
		_switch_class_from_pause())
	b_switch.visible = G.mode != "campaign"
	v.add_child(b_switch)
	var b_set := UiTheme.make_button("设置", 15)
	b_set.custom_minimum_size = Vector2(260, 40)
	b_set.pressed.connect(func():
		AudioSys.ui()
		_settings_from_pause = true
		_screens["pause"].visible = false
		_screens["settings"].visible = true)
	v.add_child(b_set)
	var b2 := UiTheme.make_button("放弃战斗", 15)
	b2.custom_minimum_size = Vector2(260, 40)
	b2.pressed.connect(func():
		AudioSys.ui()
		on_quit.call())
	v.add_child(b2)


func show_pause(p_show: bool) -> void:
	_screens["pause"].visible = p_show


func is_pause_visible() -> bool:
	return _screens["pause"].visible


## 暂停菜单 → 切换兵种:还原暂停态 → 载具中先下车 → 强制阵亡 → 直接进部署界面选兵种
## (state 先置 "dead" 再立即 redeploy 置 "deploy",game.gd 的 1.2s 死亡计时器因 state 已变更不会弹死亡界面)
func _switch_class_from_pause() -> void:
	_screens["pause"].visible = false
	_screens["settings"].visible = false
	G.paused = false
	if G.player != null:
		G.player.exit_vehicle(true)  # 载具中先下车
		G.player.spawn_protect = 0
		if G.player.alive:
			G.player.damage(99999.0, Vector3.ZERO, null)
		if G.player.alive:
			# 兜底:仍存活(伤害被出生保护等拦截)则强制进入阵亡流程
			G.player.health = 0
			G.player.alive = false
			G.player.night_vision = false
			G.effects.set_night_vision(false)
			if G.player.veh_body != null:
				G.player.veh_body.visible = false
			G.game.on_player_death(null)
	G.game.redeploy()  # 隐藏死亡界面 + show_deploy(true) + state="deploy";死亡黑幕由 reset_death_fade 清理


## 关闭设置屏(暂停中打开设置后按 Esc 恢复战斗等场景兜底)
func close_settings() -> void:
	_settings_from_pause = false
	if _screens.has("settings"):
		_screens["settings"].visible = false


## ==================== 加载 ====================
func _build_loading() -> void:
	var s := _add_screen("loading")
	_bg(s, Color(0.02, 0.03, 0.05, 1))
	var l := UiTheme.make_label("正在部署战场…", 26, Color(0.8, 0.85, 0.9))
	l.set_anchors_preset(Control.PRESET_CENTER)
	s.add_child(l)


func show_loading(p_show: bool) -> void:
	_screens["loading"].visible = p_show


func show_menu() -> void:
	hide_all()
	_screens["menu"].visible = true

