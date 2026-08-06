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
	_build_armory()
	_build_battlepass()
	_build_profile()
	_build_store()
	_make_toast()
	hide_all()
	_screens["menu"].visible = true
	# 调试:--test-campaign-menu 直接打开战役章节选择屏(验证构建)
	if OS.get_cmdline_user_args().has("--test-campaign-menu"):
		hide_all()
		_screens["campaign"].visible = true
	# 调试:--test-armory-menu 直接打开枪械改装屏(验证 3D 预览 + 槽位/改装件构建)
	if OS.get_cmdline_user_args().has("--test-armory-menu"):
		hide_all()
		_screens["armory"].visible = true
		_armory_enter()
	# 调试:--test-battlepass 直接打开战斗通行证屏(验证构建 + 皮肤装备交互)
	if OS.get_cmdline_user_args().has("--test-battlepass"):
		hide_all()
		_screens["battlepass"].visible = true
		_bp_load_equipped(_bp_class)
		_refresh_bp_grid()


func _process(dt: float) -> void:
	# 战役 signal 懒连接(campaign 由 main 在 Menus 之后创建);
	# 实例变化(切换/重建 Campaign)时先断开旧实例再重连,防结算信号挂到废弃实例上
	if G.campaign != null and G.campaign != _campaign_src:
		if _campaign_src != null and is_instance_valid(_campaign_src):
			_campaign_src.chapter_finished.disconnect(_on_chapter_finished)
		_campaign_src = G.campaign
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
	# 枪械改装 3D 预览自动旋转(拖拽时暂停)
	if _screens.has("armory") and _screens["armory"].visible and _arm_pivot != null and not _arm_dragging:
		_arm_yaw += dt * 0.4
		_arm_pivot.rotation = Vector3(_arm_pitch, _arm_yaw, 0)
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
	# ---- 顶部标签栏(BF2042:PLAY / ARMORY / BATTLE PASS / PROFILE / STORE,可点击切换) ----
	_make_tab_bar(s, "menu")
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
[b]区域按顺序解锁[/b]:尚未攻到的区域处于封锁状态,地图上以灰色显示;越过封锁线会被遣返回战线,
且封锁区域内无法部署 —— 攻守双方都不能跨区域作战。
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
var _campaign_src: Node = null       # 章节结算 signal 已连接实例(实例重建时断开旧/重连新)
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
	# 直达游玩(--test-play campaign 等未经章节选择屏)时索引仍为 -1:按当前战役章节定位,兜底第 1 章
	if _campaign_cur_index < 0:
		if G.campaign != null:
			for i in chs.size():
				if str(chs[i].get("id", "")) == str(G.campaign.chapter_id):
					_campaign_cur_index = i
					break
		if _campaign_cur_index < 0:
			_campaign_cur_index = 0
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
	_set_tab_active("menu")


## ==================== 顶部标签栏(5 Tab:游玩/枪械/战斗通行证/档案/商店) ====================
const TAB_IDS: Array = [
	["menu", "游玩"], ["armory", "枪械"], ["battlepass", "战斗通行证"], ["profile", "档案"], ["store", "商店"],
]
const TAB_BTN_W := 92.0
const TAB_PITCH := 118.0   # 按钮宽 92 + 间距 26
const TAB_LINE_W := 52.0
var _tab_btns: Dictionary = {}   # 屏id → {tabid: Button}
var _tab_lines: Dictionary = {}  # 屏id → 下划线 ColorRect


## 每个主界面各自挂一套标签栏(当前屏高亮,下划线跟随)
func _make_tab_bar(parent: Control, active: String) -> void:
	var tabs := HBoxContainer.new()
	tabs.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tabs.position = Vector2(26, 16)
	tabs.add_theme_constant_override("separation", 26)
	parent.add_child(tabs)
	var line := ColorRect.new()
	line.color = UiTheme.PRIMARY
	line.position = Vector2(26, 42)
	line.size = Vector2(TAB_LINE_W, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	_tab_lines[active] = line
	var btns := {}
	for i in TAB_IDS.size():
		var tid: String = TAB_IDS[i][0]
		var b := Button.new()
		b.theme = UiTheme.theme()
		b.text = TAB_IDS[i][1]
		b.flat = true
		b.custom_minimum_size = Vector2(TAB_BTN_W, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UiTheme.TXT_DIM)
		b.add_theme_color_override("font_hover_color", Color(0.9, 0.95, 0.98))
		b.add_theme_color_override("font_pressed_color", UiTheme.PRIMARY)
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.mouse_entered.connect(func(): AudioSys.ui_hover())
		b.pressed.connect(func(): _switch_tab(tid))
		tabs.add_child(b)
		btns[tid] = b
	_tab_btns[active] = btns
	_set_tab_active(active)


## 设置某屏标签栏的选中态(高亮色 + 下划线移动到对应 Tab)
func _set_tab_active(id: String) -> void:
	var btns: Dictionary = _tab_btns.get(id, {})
	var line: ColorRect = _tab_lines.get(id)
	if line == null and btns.is_empty():
		return
	var idx := 0
	for i in TAB_IDS.size():
		if TAB_IDS[i][0] == id:
			idx = i
			break
	for tid in btns:
		var b: Button = btns[tid]
		b.add_theme_color_override("font_color", UiTheme.PRIMARY if tid == id else UiTheme.TXT_DIM)
	if line != null:
		var tx := 26.0 + float(idx) * TAB_PITCH + (TAB_BTN_W - TAB_LINE_W) * 0.5
		if line.is_inside_tree():
			var tw := line.create_tween()
			tw.tween_property(line, "position:x", tx, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			line.position.x = tx


## Tab 切换:隐藏全部界面 → 显示目标屏(游玩=主菜单;主菜单模式选择/播放后可随时切回)
func _switch_tab(id: String) -> void:
	AudioSys.ui()
	if not _screens.has(id):
		return
	hide_all()
	_screens[id].visible = true
	_set_tab_active(id)
	if id == "armory":
		_armory_enter()
	if id == "battlepass":
		# 每次进入通行证屏重新读取已装备皮肤(存档可能在游戏内变更)
		_bp_load_equipped(_bp_class)
		_refresh_bp_grid()


## ==================== 轻提示(底部弹出,自动淡出) ====================
var _toast_l: Label = null


func _make_toast() -> void:
	_toast_l = UiTheme.make_label("", 14, Color(1, 1, 1))
	_toast_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_l.position = Vector2(0, -70)
	_toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_l.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.0, 0.06, 0.09, 0.92), UiTheme.PRIMARY, 1, 2, 14))
	_toast_l.visible = false
	_toast_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_l)


func _toast(msg: String) -> void:
	if _toast_l == null:
		return
	_toast_l.text = msg
	_toast_l.visible = true
	_toast_l.modulate.a = 1.0
	var tw := _toast_l.create_tween()
	tw.tween_property(_toast_l, "scale", Vector2(1.04, 1.04), 0.1)
	tw.tween_interval(1.4)
	tw.tween_property(_toast_l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): _toast_l.visible = false)


## ==================== 枪械改装界面(核心,三角洲风格:左选枪/中 3D/右槽位) ====================
const ARM_SLOT_CN := { "muzzle": "枪口", "mag": "弹匣", "grip": "握把", "trigger": "扳机", "optic": "瞄具" }
const STAT_CN := {
	"mag_ammo": "弹匣容量", "reload_mult": "换弹速度", "recoil_mult": "后座控制", "recoil_pitch_mult": "垂直后座控制",
	"hip_spread_mult": "腰射精度", "spread_mult": "散布精度", "ads_speed_mult": "开镜速度",
	"fire_rate_mult": "射速", "dmg_mult": "伤害", "suppress": "隐蔽",
}
const KIND_CN := {
	"rifle": "突击步枪", "smg": "冲锋枪", "lmg": "轻机枪", "shotgun": "霰弹枪",
	"sniper": "狙击步枪", "pistol": "手枪", "rpg": "火箭筒", "dmr": "精确射手步枪",
}
## 兜底改装件数据(WeaponModsData 未就绪时界面仍可完整演示,键结构与其契约一致)
const DEMO_MODS := {
	"muzzle": {
		"std_muzzle": { "n": "原装枪口", "d": "标准制式枪口,性能均衡", "s": {} },
		"comp": { "n": "制退器", "d": "降低后座,便于连射控制", "s": { "recoil_mult": 0.85 } },
		"supp": { "n": "消音器", "d": "消除枪口火光与噪音,隐蔽作战", "s": { "recoil_mult": 0.97, "suppress": true } },
	},
	"mag": {
		"std_mag": { "n": "标准弹匣", "d": "制式供弹具", "s": {} },
		"ext": { "n": "加长弹匣", "d": "增加弹药携带量", "s": { "mag_ammo": 12 } },
		"quick": { "n": "快拔弹匣", "d": "快速换弹,牺牲少量容量", "s": { "reload_mult": 0.8, "mag_ammo": -3 } },
	},
	"grip": {
		"std_grip": { "n": "原装握把", "d": "标准握持手感", "s": {} },
		"ang": { "n": "直角握把", "d": "改善前握持,降低腰射散布", "s": { "hip_spread_mult": 0.85 } },
		"vrt": { "n": "垂直握把", "d": "稳定后座,连发更可控", "s": { "recoil_mult": 0.9 } },
	},
	"trigger": {
		"std_trigger": { "n": "原装扳机", "d": "标准扳机组", "s": {} },
		"hair": { "n": "轻量化扳机", "d": "缩短扳机行程,射速提升", "s": { "fire_rate_mult": 1.08, "recoil_mult": 1.05 } },
		"match": { "n": "比赛扳机", "d": "精准击发,减少动作扰动", "s": { "ads_speed_mult": 1.05, "fire_rate_mult": 1.04 } },
	},
	"optic": {
		"std_optic": { "n": "机械瞄具", "d": "原装准星照门", "s": {} },
		"holo": { "n": "全息瞄具", "d": "快速上镜,近战利器", "s": { "ads_speed_mult": 0.9 } },
		"scope": { "n": "4x 光学瞄准镜", "d": "中远距离精确射击", "s": { "recoil_mult": 0.95, "hip_spread_mult": 1.15 } },
	},
}
var _arm_weapon := ""                # 记住上次选择的武器(切 Tab 回来不丢)
var _arm_cfg: Dictionary = {}        # 工作配置 {槽位: 件id}(未保存)
var _arm_open_slot := ""
var _arm_pivot: Node3D = null
var _arm_yaw := 0.0
var _arm_pitch := 0.0
var _arm_dragging := false
var _arm_list: VBoxContainer = null
var _arm_slots: VBoxContainer = null
var _arm_cur_label: Label = null
var _mod_data: Dictionary = {}       # {槽位:{件id:{n,d,s}}} = 真实 MODS ∪ 兜底 DEMO_MODS
var _mod_ready := false


func _build_armory() -> void:
	var s := _add_screen("armory")
	_bg(s, Color(0.01, 0.03, 0.05, 0.9))
	s.add_child(UiTheme.BattleBg.new())
	_make_tab_bar(s, "armory")
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 58
	root.offset_right = -24
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 8)
	s.add_child(root)
	# 顶栏
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	head.add_child(UiTheme.make_label("枪械改装", 30, UiTheme.TXT))
	head.add_child(UiTheme.make_label("ARMORY · 选配槽位 · 实时预览", 14, UiTheme.PRIMARY))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	_arm_cur_label = UiTheme.make_label("未选择武器", 16, UiTheme.TXT_DIM)
	head.add_child(_arm_cur_label)
	# 主体三栏
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	# ---- 左:武器列表(按兵种/类别分组,可滚动) ----
	var left_panel := UiTheme.make_panel(0.7)
	left_panel.custom_minimum_size = Vector2(360, 0)
	body.add_child(left_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left_panel.add_child(lv)
	lv.add_child(UiTheme.make_label("选择武器", 15, UiTheme.PRIMARY))
	var lscroll := ScrollContainer.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.custom_minimum_size = Vector2(0, 420)
	lv.add_child(lscroll)
	_arm_list = VBoxContainer.new()
	_arm_list.add_theme_constant_override("separation", 6)
	lscroll.add_child(_arm_list)
	# ---- 中:3D 武器预览(SubViewport 透明背景 + 相机 + 灯光 + 拖拽旋转) ----
	var view_panel := UiTheme.make_panel(0.7)
	view_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_panel.custom_minimum_size = Vector2(640, 0)
	body.add_child(view_panel)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 6)
	view_panel.add_child(vv)
	var vhead := HBoxContainer.new()
	vv.add_child(vhead)
	vhead.add_child(UiTheme.make_label("武器预览", 14, UiTheme.PRIMARY))
	var vsp := Control.new()
	vsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vhead.add_child(vsp)
	var vhint := UiTheme.make_label("拖拽旋转 · 自动巡航 · 改装实时生效", 12, UiTheme.TXT_DIM)
	vhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vhead.add_child(vhint)
	var vpc := SubViewportContainer.new()
	vpc.custom_minimum_size = Vector2(640, 420)
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	vpc.gui_input.connect(_armory_view_input)
	vv.add_child(vpc)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 420)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(vp)
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 0.32, 2.6)
	cam.fov = 34
	vp.add_child(cam)
	cam.look_at(Vector3(0, -0.02, -0.2), Vector3.UP)
	var l1 := DirectionalLight3D.new()
	l1.rotation_degrees = Vector3(-50, -35, 0)
	l1.light_energy = 1.1
	vp.add_child(l1)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(15, 50, 0)
	l2.light_energy = 0.45
	vp.add_child(l2)
	_arm_pivot = Node3D.new()
	vp.add_child(_arm_pivot)
	# ---- 右:槽位面板 ----
	var right_panel := UiTheme.make_panel(0.7)
	right_panel.custom_minimum_size = Vector2(470, 0)
	body.add_child(right_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right_panel.add_child(rv)
	rv.add_child(UiTheme.make_label("改装槽位", 15, UiTheme.PRIMARY))
	_arm_slots = VBoxContainer.new()
	_arm_slots.add_theme_constant_override("separation", 6)
	_arm_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_arm_slots)
	# ---- 底部:恢复默认 / 保存改装 ----
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 20)
	root.add_child(foot)
	var b_reset := UiTheme.make_button("恢复默认", 15)
	b_reset.custom_minimum_size = Vector2(180, 40)
	b_reset.pressed.connect(func(): _armory_reset())
	foot.add_child(b_reset)
	var b_save := UiTheme.make_cta("保存改装", 16)
	b_save.custom_minimum_size = Vector2(220, 40)
	b_save.pressed.connect(func(): _armory_save())
	foot.add_child(b_save)
	_armory_build_list()


## 进入枪械屏:初始化改装数据 + 恢复上次武器选择
func _armory_enter() -> void:
	_init_mod_data()
	if _arm_weapon == "":
		_arm_weapon = "m4"
	if not WeaponsData.W().has(_arm_weapon):
		_arm_weapon = WeaponsData.W().keys()[0]
	_armory_select(_arm_weapon)


func _armory_build_list() -> void:
	for c in _arm_list.get_children():
		_arm_list.remove_child(c)
		c.queue_free()
	var classes := WeaponsData.C()
	for cid in classes:
		var cls = classes[cid]
		_arm_list.add_child(UiTheme.make_label(cls.icon + " " + cls.cn + " · " + cls.en, 13, cls.color))
		var ids: Array = []
		ids.append_array(cls.weapons)
		ids.append_array(cls.shotguns)
		for wid in ids:
			_arm_list.add_child(_armory_weapon_btn(wid))
	_arm_list.add_child(UiTheme.make_label("副武器 · SIDEARMS", 13, Color(0.55, 0.62, 0.7)))
	for wid in WeaponsData.SECONDARIES:
		_arm_list.add_child(_armory_weapon_btn(wid))


func _armory_weapon_btn(wid: String) -> Button:
	var w = WeaponsData.W()[wid]
	var b := Button.new()
	b.theme = UiTheme.theme()
	b.toggle_mode = true
	b.button_pressed = (wid == _arm_weapon)
	b.custom_minimum_size = Vector2(0, 54)
	b.text = w.cn + "\n" + str(KIND_CN.get(w.kind, w.kind)) + " · 伤害 " + str(w.damage) + " · 弹匣 " + str(w.mag)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UiTheme.TXT)
	var sel: bool = wid == _arm_weapon
	var bg := Color(0.0, 0.16, 0.2, 0.95) if sel else Color(0.0, 0.03, 0.05, 0.9)
	var border := UiTheme.PRIMARY if sel else Color(0.22, 0.28, 0.34, 0.5)
	b.add_theme_stylebox_override("normal", UiTheme.stylebox(bg, border, 1, 3, 6))
	b.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.2, 0.26, 0.95), border, 1, 3, 6))
	b.add_theme_stylebox_override("pressed", UiTheme.stylebox(bg, border, 1, 3, 6))
	b.add_theme_stylebox_override("focus", UiTheme.stylebox(bg, border, 1, 3, 6))
	UiTheme.wire_button(b)
	b.pressed.connect(func(): _armory_select(wid))
	return b


## 选中武器:换配置 → 重建 3D → 刷新槽位
func _armory_select(wid: String) -> void:
	AudioSys.ui()
	if wid != _arm_weapon or _arm_cfg.is_empty():
		_arm_weapon = wid
		_arm_cfg = _armory_defaults(wid)
	_arm_open_slot = ""
	_armory_build_list()
	if _arm_cur_label != null:
		_arm_cur_label.text = WeaponsData.W()[wid].cn
	_armory_rebuild_view()
	_armory_refresh_slots()


## 3D 预览:重建武器模型(Visual 团队 build(id,with_hands,mods) 扩展前按 2 参调用)
func _armory_rebuild_view() -> void:
	if _arm_pivot == null:
		return
	for c in _arm_pivot.get_children():
		_arm_pivot.remove_child(c)
		c.queue_free()
	var m := _build_weapon_view(_arm_weapon, _arm_cfg)
	if m != null:
		_arm_pivot.add_child(m)
		_shadow_off(m)
	_arm_pivot.rotation = Vector3(_arm_pitch, _arm_yaw, 0)


func _armory_view_input(ev: InputEvent) -> void:
	if _arm_pivot == null:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_arm_dragging = ev.pressed
	elif ev is InputEventMouseMotion and _arm_dragging:
		_arm_yaw += ev.relative.x * 0.01
		_arm_pitch = clampf(_arm_pitch + ev.relative.y * 0.008, -1.2, 1.2)
		_arm_pivot.rotation = Vector3(_arm_pitch, _arm_yaw, 0)


## 槽位面板:5 槽竖排,行=槽名+当前件+属性摘要;点击展开可选件(is_compatible 过滤)
func _armory_refresh_slots() -> void:
	for c in _arm_slots.get_children():
		_arm_slots.remove_child(c)
		c.queue_free()
	for slot in ARM_SLOT_CN:
		_arm_slots.add_child(_armory_slot_row(slot))


func _armory_slot_row(slot: String) -> Control:
	var is_open: bool = _arm_open_slot == slot
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var border := UiTheme.PRIMARY if is_open else Color(0.25, 0.32, 0.4, 0.6)
	panel.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.0, 0.05, 0.08, 0.92), border, 1, 2, 10))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var sn := UiTheme.make_label(str(ARM_SLOT_CN.get(slot, slot)), 14, UiTheme.PRIMARY)
	sn.custom_minimum_size = Vector2(52, 0)
	head.add_child(sn)
	var cur_id: String = str(_arm_cfg.get(slot, ""))
	var cur_name := "—"
	var cur_effect := ""
	if cur_id != "" and _mod_data.get(slot, {}).has(cur_id):
		var md: Dictionary = _mod_data[slot][cur_id]
		cur_name = str(md.get("n", cur_id))
		cur_effect = _mod_effect_text(md.get("s", {}))
	var vn := VBoxContainer.new()
	vn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(vn)
	vn.add_child(UiTheme.make_label(cur_name, 14, UiTheme.TXT))
	var ef := RichTextLabel.new()
	ef.bbcode_enabled = true
	ef.fit_content = true
	ef.scroll_active = false
	ef.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ef.add_theme_font_size_override("normal_font_size", 12)
	ef.text = cur_effect if cur_effect != "" else "[color=#7a8790]无属性差异[/color]"
	vn.add_child(ef)
	var mark := UiTheme.make_label("▾" if not is_open else "▴", 14, UiTheme.TXT_DIM)
	head.add_child(mark)
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			AudioSys.ui()
			_arm_open_slot = "" if is_open else slot
			_armory_refresh_slots())
	var opts := VBoxContainer.new()
	opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opts.add_theme_constant_override("separation", 3)
	opts.visible = is_open
	col.add_child(opts)
	if is_open:
		var pool: Dictionary = _mod_data.get(slot, {})
		var scr := _wmd_script()
		var def_mid := ""
		if scr != null and _wmd_methods().has("default_mod"):
			def_mid = str(scr.call("default_mod", slot))
		for mid in pool:
			if _mod_ready and scr != null and _wmd_methods().has("is_compatible"):
				if not bool(scr.call("is_compatible", _arm_weapon, slot, mid)):
					continue
			opts.add_child(_armory_mod_item(slot, mid, pool[mid], def_mid))
	return panel


## 可选件条目:名称+描述+属性增减(绿加/红减),选中高亮
func _armory_mod_item(slot: String, mid: String, md: Dictionary, def_mid := "") -> Control:
	var equipped: bool = str(_arm_cfg.get(slot, "")) == mid
	var is_std: bool = (def_mid != "" and mid == def_mid) or (def_mid == "" and str(mid).begins_with("std_"))
	var item := PanelContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	var border := UiTheme.PRIMARY if equipped else Color(0.2, 0.26, 0.32, 0.45)
	item.add_theme_stylebox_override("panel", UiTheme.stylebox(
		Color(0.0, 0.09, 0.12, 0.95) if equipped else Color(0.01, 0.04, 0.06, 0.9), border, 1, 2, 8))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	item.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var name_l := UiTheme.make_label(str(md.get("n", mid)), 13, Color(0.9, 0.95, 0.98))
	h.add_child(name_l)
	if is_std:
		var tag := UiTheme.make_label("标准", 11, UiTheme.TXT_DIM)
		tag.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.1, 0.14, 0.18, 0.8), Color(0.3, 0.36, 0.42, 0.5), 1, 1, 4))
		h.add_child(tag)
	if equipped:
		var eq := UiTheme.make_label("已装备", 11, UiTheme.PRIMARY)
		eq.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.0, 0.22, 0.3, 0.85), UiTheme.PRIMARY, 1, 1, 4))
		h.add_child(eq)
	var d := UiTheme.make_label(str(md.get("d", "")), 11, UiTheme.TXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var eff_txt := _mod_effect_text(md.get("s", {}))
	var ef := RichTextLabel.new()
	ef.bbcode_enabled = true
	ef.fit_content = true
	ef.scroll_active = false
	ef.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ef.add_theme_font_size_override("normal_font_size", 12)
	ef.text = eff_txt if eff_txt != "" else "[color=#7a8790]无属性差异[/color]"
	v.add_child(ef)
	item.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			AudioSys.ui()
			_arm_cfg[slot] = mid
			_arm_open_slot = ""
			_armory_refresh_slots()
			_armory_rebuild_view())
	return item


## 属性摘要 BBCode(绿色加成/红色减益,属性名中文化)
func _mod_effect_text(s: Variant) -> String:
	if s == null or not (s is Dictionary):
		return ""
	var parts: Array = []
	for key in s:
		var line := _stat_line(str(key), s[key])
		if line != "":
			parts.append(line)
	return " · ".join(parts)


func _stat_line(key: String, val) -> String:
	var cn: String = str(STAT_CN.get(key, key))
	var green := "[color=#00FF88]"
	var red := "[color=#ff6a55]"
	match key:
		"mag_ammo":
			var iv := int(val)
			return (green if iv >= 0 else red) + cn + " " + ("+" if iv >= 0 else "") + str(iv) + "[/color]"
		"reload_mult", "recoil_mult", "recoil_pitch_mult", "hip_spread_mult", "spread_mult", "ads_speed_mult":
			var p1 := (1.0 - float(val)) * 100.0
			return (green if p1 >= 0.0 else red) + cn + " " + ("+" if p1 >= 0.0 else "-") + ("%.0f%%" % absf(p1)) + "[/color]"
		"fire_rate_mult", "dmg_mult":
			var p2 := (float(val) - 1.0) * 100.0
			return (green if p2 >= 0.0 else red) + cn + " " + ("+" if p2 >= 0.0 else "-") + ("%.0f%%" % absf(p2)) + "[/color]"
		"suppress":
			return (green + cn + " 开启[/color]") if bool(val) else ""
		_:
			return green + cn + " " + str(val) + "[/color]"


## 恢复默认:重读默认配置
func _armory_reset() -> void:
	AudioSys.ui()
	_arm_cfg = _armory_defaults(_arm_weapon)
	_arm_open_slot = ""
	_armory_refresh_slots()
	_armory_rebuild_view()
	_toast("已恢复默认配置")


## 保存改装:调用 WeaponModsData.save_cfg(weapon_id, cfg)(模块未就绪则提示)
func _armory_save() -> void:
	AudioSys.ui()
	if _arm_weapon == "":
		return
	var scr := _wmd_script()
	if scr != null and _wmd_methods().has("save_cfg"):
		scr.call("save_cfg", _arm_weapon, _arm_cfg)
		_toast("已保存 " + WeaponsData.W()[_arm_weapon].cn + " 的改装配置")
	else:
		_toast("改装数据模块未就绪 · 配置仅本次会话有效")


func _armory_defaults(wid: String) -> Dictionary:
	var scr := _wmd_script()
	# 优先读存档配置(load_cfg 内含 defaults 回退),再退化到兜底演示件
	if scr != null and _wmd_methods().has("load_cfg"):
		var ld = scr.call("load_cfg", wid)
		if ld is Dictionary and not ld.is_empty():
			return ld
	if scr != null and _wmd_methods().has("defaults"):
		var d = scr.call("defaults", wid)
		if d is Dictionary and not d.is_empty():
			return d
	var cfg := {}
	for slot in ARM_SLOT_CN:
		cfg[slot] = _armory_std_mod(slot)
	return cfg


## 槽位默认件:优先 WMD.default_mod(slot),再找兜底 "std_槽位",最后取第一件
func _armory_std_mod(slot: String) -> String:
	var scr := _wmd_script()
	if scr != null and _wmd_methods().has("default_mod"):
		var dm: String = str(scr.call("default_mod", slot))
		if dm != "" and _mod_data.get(slot, {}).has(dm):
			return dm
	var pool: Dictionary = _mod_data.get(slot, {})
	if pool.is_empty():
		return ""
	if pool.has("std_" + slot):
		return "std_" + slot
	for mid in pool:
		return mid
	return ""


## 改装数据初始化:WeaponModsData.MODS(若有) ∪ DEMO_MODS 兜底(真实数据已覆盖的槽位不混入演示件)
func _init_mod_data() -> void:
	if not _mod_data.is_empty():
		return
	_mod_data = {}
	var scr := _wmd_script()
	_mod_ready = scr != null
	var real: Dictionary = {}
	if scr != null and scr.get_script_constant_map().has("MODS"):
		var m: Variant = scr.get("MODS")
		if m is Dictionary:
			real = m
	var names: Dictionary = ARM_SLOT_CN
	if scr != null and scr.get_script_constant_map().has("SLOT_NAMES"):
		var sn: Variant = scr.get("SLOT_NAMES")
		if sn is Dictionary and not sn.is_empty():
			names = sn
	for slot in names:
		_mod_data[slot] = {}
		var pool: Dictionary = real.get(slot, {}) if real.has(slot) else {}
		for mid in pool:
			_mod_data[slot][mid] = pool[mid]
		if not real.has(slot) and DEMO_MODS.has(slot):
			for mid in DEMO_MODS[slot]:
				if not _mod_data[slot].has(mid):
					_mod_data[slot][mid] = DEMO_MODS[slot][mid]


## ==================== WeaponModsData / WeaponModels 防御访问 ====================
func _wmd_script() -> Script:
	var p := "res://src/data/weapon_mods_data.gd"
	if not ResourceLoader.exists(p):
		return null
	var s = load(p)
	return s if s is Script else null


var _wmd_methods_cache: Dictionary = {}
func _wmd_methods() -> Dictionary:
	if _wmd_methods_cache.is_empty():
		var scr := _wmd_script()
		if scr != null:
			for m in scr.get_script_method_list():
				_wmd_methods_cache[str(m.get("name"))] = true
	return _wmd_methods_cache


## WeaponModels.build(id, with_hands, mods):Visual 团队扩展前 build 只有 2 参,按参数数量防御调用
func _build_weapon_view(wid: String, mods: Dictionary) -> Node3D:
	var WM: Script = load("res://src/models/weapon_models.gd")
	if WM == null:
		return null
	var nargs := 2
	for m in WM.get_script_method_list():
		if m.get("name") == "build":
			nargs = int(m.get("args", []).size())
			break
	if nargs >= 3:
		return WM.call("build", wid, false, mods)
	return WM.call("build", wid, false)


func _shadow_off(node: Node) -> void:
	for c in node.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow_off(c)


## ==================== 战斗通行证界面 ====================
const BP_LEVEL := 32
const BP_DEMO := {
	"assault": [
		{ "n": "丛林突击", "d": "丛林迷彩作战服,突击兵标准外观", "colors": [Color(0.24, 0.35, 0.23), Color(0.18, 0.29, 0.17), Color(0.11, 0.17, 0.11)], "lv": 1 },
		{ "n": "雪原猎手", "d": "极地伪装,高海拔严寒作战", "colors": [Color(0.91, 0.93, 0.92), Color(0.73, 0.77, 0.77), Color(0.56, 0.64, 0.65)], "lv": 15 },
		{ "n": "夜袭者", "d": "暗夜行动套装,低可见度渗透", "colors": [Color(0.1, 0.11, 0.13), Color(0.17, 0.2, 0.22), Color(0.05, 0.06, 0.07)], "lv": 40 },
	],
	"engineer": [
		{ "n": "装甲工兵", "d": "重型护甲携行具,前线修械", "colors": [Color(0.55, 0.42, 0.24), Color(0.4, 0.3, 0.17), Color(0.25, 0.19, 0.12)], "lv": 1 },
		{ "n": "废土技师", "d": "硝烟熏染的维修作战服", "colors": [Color(0.36, 0.34, 0.3), Color(0.28, 0.26, 0.23), Color(0.19, 0.18, 0.16)], "lv": 15 },
		{ "n": "燃烧军团", "d": "烈焰涂装,反装甲精英", "colors": [Color(0.62, 0.22, 0.1), Color(0.45, 0.16, 0.08), Color(0.3, 0.1, 0.05)], "lv": 40 },
	],
	"support": [
		{ "n": "战地医护", "d": "红十字标识补给装甲服", "colors": [Color(0.78, 0.8, 0.78), Color(0.55, 0.58, 0.55), Color(0.35, 0.38, 0.35)], "lv": 1 },
		{ "n": "沙漠之狐", "d": "荒漠迷彩,中东战场补给线", "colors": [Color(0.72, 0.62, 0.4), Color(0.58, 0.5, 0.33), Color(0.42, 0.36, 0.24)], "lv": 15 },
		{ "n": "幽灵信使", "d": "灰白数码迷彩,前线生命线", "colors": [Color(0.42, 0.44, 0.46), Color(0.3, 0.32, 0.34), Color(0.2, 0.21, 0.22)], "lv": 40 },
	],
	"recon": [
		{ "n": "林地侦察", "d": "林地伪装网,观察手标配", "colors": [Color(0.28, 0.36, 0.22), Color(0.2, 0.27, 0.16), Color(0.13, 0.17, 0.1)], "lv": 1 },
		{ "n": "冰原之眼", "d": "雪地吉利服,极地狙击手", "colors": [Color(0.9, 0.92, 0.94), Color(0.72, 0.76, 0.8), Color(0.55, 0.6, 0.64)], "lv": 15 },
		{ "n": "暗影猎手", "d": "全黑夜战装具,无声无息", "colors": [Color(0.12, 0.12, 0.14), Color(0.2, 0.2, 0.23), Color(0.08, 0.08, 0.09)], "lv": 40 },
	],
}
var _bp_class := "assault"
var _bp_class_btns: Dictionary = {}
var _bp_grid: GridContainer = null
var _bp_sel: Dictionary = {}      # 兵种 → 选中的皮肤索引
var _bp_skins: Dictionary = {}    # SoldierModel.SKINS(若有),结构归一化后使用
var _bp_equipped: Dictionary = {} # 兵种 → 已装备皮肤 id(优先 SkinCfg 持久化,缺失时本地内存兜底)
var _bp_purchase: Button = null
var _skin_cfg: Script = null      # SkinCfg 脚本(Gameplay 团队交付,可能尚未存在 → 防御式加载)
var _skin_cfg_missed := false     # 已尝试加载但失败/API 不符,不再重试


func _build_battlepass() -> void:
	var s := _add_screen("battlepass")
	_bg(s, Color(0.01, 0.03, 0.05, 0.92))
	s.add_child(UiTheme.BattleBg.new())
	_make_tab_bar(s, "battlepass")
	_bp_load_skins()
	_bp_load_equipped(_bp_class)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 58
	root.offset_right = -24
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	s.add_child(root)
	# 顶栏
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	head.add_child(UiTheme.make_label("战斗通行证", 30, UiTheme.TXT))
	head.add_child(UiTheme.make_label("BATTLE PASS · 赛季 I", 14, UiTheme.PRIMARY))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	head.add_child(UiTheme.make_label("通行证等级 " + str(BP_LEVEL), 16, UiTheme.PRIMARY))
	# 等级进度条 + 每 10 级奖励标记
	var bar_panel := UiTheme.make_panel(0.7)
	root.add_child(bar_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bar_panel.add_child(bv)
	var mark_titles := { 10: "徽章", 20: "挂件", 30: "武器皮肤", 40: "名片", 50: "战术动作",
		60: "武器皮肤", 70: "载具皮肤", 80: "处决动作", 90: "特殊名片", 100: "大师皮肤" }
	var marks := HBoxContainer.new()
	bv.add_child(marks)
	for lv in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
		var m := VBoxContainer.new()
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.alignment = BoxContainer.ALIGNMENT_CENTER
		marks.add_child(m)
		var reached: bool = lv <= BP_LEVEL
		var box := ColorRect.new()
		box.color = Color(0.0, 0.35, 0.45, 0.95) if reached else Color(0.1, 0.14, 0.18, 0.9)
		box.custom_minimum_size = Vector2(26, 26)
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		m.add_child(box)
		var tl := UiTheme.make_label("Lv." + str(lv), 10, UiTheme.PRIMARY if reached else UiTheme.TXT_DIM)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.add_child(tl)
		var tn := UiTheme.make_label(mark_titles[lv], 10, UiTheme.TXT_DIM)
		tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.add_child(tn)
	var track := HBoxContainer.new()
	bv.add_child(track)
	var fill := ColorRect.new()
	fill.color = UiTheme.PRIMARY
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.size_flags_stretch_ratio = float(BP_LEVEL)
	fill.custom_minimum_size = Vector2(0, 14)
	track.add_child(fill)
	var rest := ColorRect.new()
	rest.color = Color(0.08, 0.12, 0.16, 0.9)
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.size_flags_stretch_ratio = float(100 - BP_LEVEL)
	rest.custom_minimum_size = Vector2(0, 14)
	track.add_child(rest)
	# 兵种标签 + 购买按钮
	var ctab := HBoxContainer.new()
	ctab.add_theme_constant_override("separation", 8)
	root.add_child(ctab)
	ctab.add_child(UiTheme.make_label("兵种皮肤", 15, UiTheme.PRIMARY))
	for cid in WeaponsData.C():
		var cb := UiTheme.make_button(WeaponsData.C()[cid].cn, 13)
		cb.toggle_mode = true
		cb.button_pressed = (cid == _bp_class)
		cb.custom_minimum_size = Vector2(120, 32)
		cb.pressed.connect(func(): _bp_switch_class(cid))
		ctab.add_child(cb)
		_bp_class_btns[cid] = cb
	var csp := Control.new()
	csp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctab.add_child(csp)
	_bp_purchase = UiTheme.make_cta("购买通行证", 14)
	_bp_purchase.custom_minimum_size = Vector2(170, 32)
	_bp_purchase.pressed.connect(func(): _toast("演示:购买通行证功能即将推出"))
	ctab.add_child(_bp_purchase)
	# 皮肤卡片网格(3 列)
	var gpanel := UiTheme.make_panel(0.7)
	gpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(gpanel)
	_bp_grid = GridContainer.new()
	_bp_grid.columns = 3
	_bp_grid.add_theme_constant_override("h_separation", 12)
	_bp_grid.add_theme_constant_override("v_separation", 12)
	_bp_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gpanel.add_child(_bp_grid)
	_refresh_bp_grid()


func _bp_switch_class(cid: String) -> void:
	AudioSys.ui()
	_bp_class = cid
	for k in _bp_class_btns:
		_bp_class_btns[k].button_pressed = (k == cid)
	_bp_load_equipped(cid)
	_refresh_bp_grid()


func _refresh_bp_grid() -> void:
	for c in _bp_grid.get_children():
		_bp_grid.remove_child(c)
		c.queue_free()
	var skins: Array = _bp_skins_for(_bp_class)
	for i in skins.size():
		_bp_grid.add_child(_bp_skin_card(skins[i], i))


func _bp_skins_for(cid: String) -> Array:
	if _bp_skins.has(cid) and not (_bp_skins[cid] as Array).is_empty():
		return _bp_skins[cid]
	return BP_DEMO.get(cid, [])


## SkinCfg 防御式适配:Gameplay 团队交付 res://src/data/skin_cfg.gd(class_name SkinCfg,静态方法),
## 未交付/API 不符时返回 null,界面降级为本地演示状态(装备仅存内存,不崩溃)。
## 依赖 API: SkinCfg.get_skin(class_id: String) -> String; SkinCfg.save_skin(class_id: String, skin_id: String) -> void
## 存档路径 user://skin_cfg.cfg,键 class_<class_id>,默认 "standard"(由 Gameplay 负责)
func _bp_skin_cfg() -> Script:
	if _skin_cfg != null or _skin_cfg_missed:
		return _skin_cfg
	if not ResourceLoader.exists("res://src/data/skin_cfg.gd"):
		return null
	var s: Script = load("res://src/data/skin_cfg.gd") as Script
	if s == null or not (s.has_method("get_skin") and s.has_method("save_skin")):
		_skin_cfg_missed = true
		push_warning("[BP] SkinCfg 缺失 get_skin/save_skin,降级为本地演示装备")
		return null
	_skin_cfg = s
	print("[BP] SkinCfg 已就绪,皮肤装备将持久化到 user://skin_cfg.cfg")
	return _skin_cfg


## 读取某兵种已装备皮肤 id(界面打开/兵种 Tab 切换时调用;SkinCfg 缺失时保留本地状态)
func _bp_load_equipped(cid: String) -> void:
	var cfg := _bp_skin_cfg()
	if cfg != null:
		_bp_equipped[cid] = str(cfg.call("get_skin", cid))


## 装备皮肤:先落本地状态(即时反馈),再经 SkinCfg 持久化(防御式,失败不影响界面)
func _bp_equip_skin(cid: String, sid: String, skin_name: String) -> void:
	AudioSys.ui()
	_bp_equipped[cid] = sid
	var cfg := _bp_skin_cfg()
	if cfg != null:
		cfg.call("save_skin", cid, sid)
		print("[BP] SkinCfg.save_skin(class=", cid, ", skin=", sid, ")")
	_toast("已装备 " + skin_name)
	_refresh_bp_grid()


## 皮肤数据:优先 SoldierModel.SKINS(存在即用,支持 {皮肤id:{部件:色}} 与 [{n,d,colors,lv}] 两种结构),否则内置演示数据
const SKIN_CN := { "standard": "原版制服", "arctic": "北极迷彩", "night": "夜战装", "desert": "荒漠迷彩",
	"black": "黑色作战", "brown": "棕土涂装", "gray": "城市灰", "urban": "城市迷彩", "white": "雪地伪装" }
const SKIN_PART_ORDER := ["uniform", "vest", "helmet", "gear", "gear2"]
func _bp_load_skins() -> void:
	_bp_skins = {}
	var p := "res://src/models/soldier_model.gd"
	if not ResourceLoader.exists(p):
		return
	var SM: Script = load(p)
	if SM == null:
		return
	var raw: Variant = null
	if SM.get_script_constant_map().has("SKINS"):
		raw = SM.get("SKINS")
	if raw is Dictionary:
		for k in raw:
			var arr: Array = []
			var v = raw[k]
			if v is Array:
				for e in v:
					if e is Dictionary:
						var cols: Variant = e.get("colors", e.get("c", []))
						var colors: Array = []
						if cols is Array:
							for cc in cols:
								colors.append(_to_color(cc))
						arr.append({
							"id": str(e.get("id", "")),
							"n": str(e.get("n", e.get("cn", e.get("name", "未命名皮肤")))),
							"d": str(e.get("d", e.get("desc", ""))),
							"colors": colors,
							"lv": int(e.get("lv", e.get("level", 1))),
						})
					elif e is String:
						arr.append({ "id": e, "n": e, "d": "", "colors": [], "lv": 1 })
			elif v is Dictionary:
				# 真实结构 {皮肤id: {uniform/vest/helmet/gear: "#hex"}}:皮肤名+配色色块(4)+演示等级
				var i := 0
				for sid in v:
					var pal: Dictionary = v[sid]
					var colors: Array = []
					for part in SKIN_PART_ORDER:
						if pal.has(part) and colors.size() < 4:
							colors.append(_to_color(pal[part]))
					arr.append({
						"id": str(sid),
						"n": str(SKIN_CN.get(sid, sid)),
						"d": "兵种标准配色 · 部件涂装已应用",
						"colors": colors,
						"lv": [1, 20, 45][mini(i, 2)],
					})
					i += 1
			_bp_skins[str(k)] = arr


func _to_color(v) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, Color(0.5, 0.55, 0.6))
	return Color(0.5, 0.55, 0.6)


## 皮肤卡片:名称 + 配色色块条 + 描述 + 状态徽章 + 装备按钮;已装备卡片高亮边框+徽章;未解锁不可装备(点击提示等级不足)
func _bp_skin_card(s: Dictionary, idx: int) -> Control:
	var lv := int(s.get("lv", 1))
	var unlocked: bool = lv <= BP_LEVEL
	var selected: bool = _bp_sel.get(_bp_class) == idx
	var sid := str(s.get("id", ""))
	if sid == "":
		sid = "bp_demo_" + str(idx)
	var equipped_id := str(_bp_equipped.get(_bp_class, ""))
	var equipped: bool = unlocked and equipped_id != "" and equipped_id == sid
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var border := UiTheme.FRIENDLY if equipped else (UiTheme.PRIMARY if (selected and unlocked) else Color(0.2, 0.26, 0.32, 0.5))
	card.add_theme_stylebox_override("panel", UiTheme.stylebox(
		Color(0.0, 0.05, 0.08, 0.92) if unlocked else Color(0.02, 0.03, 0.05, 0.92),
		border, 2 if equipped else 1, 2, 12))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	h.add_child(UiTheme.make_label(str(s.get("n", "未命名皮肤")), 15, Color(0.9, 0.95, 0.98)))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(hsp)
	var badge_txt := "已装备" if equipped else ("已解锁" if unlocked else "未解锁 · Lv." + str(lv))
	var badge_col := UiTheme.FRIENDLY if (equipped or unlocked) else UiTheme.ENEMY
	var badge := UiTheme.make_label(badge_txt, 11, badge_col)
	badge.add_theme_stylebox_override("normal", UiTheme.stylebox(
		Color(0.0, 0.28, 0.16, 0.85) if equipped else (Color(0.0, 0.2, 0.28, 0.8) if unlocked else Color(0.3, 0.08, 0.05, 0.8)),
		UiTheme.FRIENDLY if equipped else Color.TRANSPARENT, 1 if equipped else 0, 1, 6))
	h.add_child(badge)
	var sw := HBoxContainer.new()
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_theme_constant_override("separation", 4)
	v.add_child(sw)
	var colors: Array = s.get("colors", [])
	if colors.is_empty():
		colors = [Color(0.4, 0.45, 0.5), Color(0.3, 0.34, 0.38), Color(0.2, 0.23, 0.26)]
	for c in colors:
		var cb := ColorRect.new()
		cb.color = c
		cb.custom_minimum_size = Vector2(46, 14)
		sw.add_child(cb)
	var d := UiTheme.make_label(str(s.get("d", "")), 12, UiTheme.TXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	# 装备按钮行(仅已解锁皮肤;已装备的置灰显示)
	if unlocked:
		var bh := HBoxContainer.new()
		bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bh.add_theme_constant_override("separation", 8)
		v.add_child(bh)
		var bhsp := Control.new()
		bhsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(bhsp)
		var btn := UiTheme.make_button("装备", 12, Color(0.0, 0.3, 0.38, 0.9))
		btn.custom_minimum_size = Vector2(84, 26)
		if equipped:
			btn.disabled = true
			btn.text = "已装备"
		else:
			var cid := _bp_class
			var skin_name := str(s.get("n", "未命名皮肤"))
			btn.pressed.connect(func(): _bp_equip_skin(cid, sid, skin_name))
		bh.add_child(btn)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			AudioSys.ui()
			if not unlocked:
				_toast("通行证等级不足 · 需 Lv." + str(lv) + " 解锁该皮肤")
				return
			_bp_sel[_bp_class] = idx
			_refresh_bp_grid())
	return card


## ==================== 档案界面 ====================
func _build_profile() -> void:
	var s := _add_screen("profile")
	_bg(s, Color(0.01, 0.03, 0.05, 0.92))
	s.add_child(UiTheme.BattleBg.new())
	_make_tab_bar(s, "profile")
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 58
	root.offset_right = -24
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	s.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	head.add_child(UiTheme.make_label("个人档案", 30, UiTheme.TXT))
	head.add_child(UiTheme.make_label("PROFILE · 作战记录与服役数据", 14, UiTheme.PRIMARY))
	# 中段:左军衔卡 + 右生涯统计
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var rank_panel := UiTheme.make_panel(0.7)
	rank_panel.custom_minimum_size = Vector2(420, 0)
	mid.add_child(rank_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	rank_panel.add_child(rv)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(120, 120)
	avatar.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.0, 0.2, 0.26, 0.9), UiTheme.PRIMARY, 2, 3, 10))
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(avatar)
	var al := UiTheme.make_label("SF-7749", 16, UiTheme.PRIMARY)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.add_child(al)
	var rank_l := UiTheme.make_label("上尉", 26, UiTheme.TXT)
	rank_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rank_l)
	var rv2 := UiTheme.make_label("等级 32 · 服役时长 142 小时", 14, UiTheme.TXT_DIM)
	rv2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rv2)
	var xp_track := HBoxContainer.new()
	rv.add_child(xp_track)
	var xp_fill := ColorRect.new()
	xp_fill.color = UiTheme.PRIMARY
	xp_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_fill.size_flags_stretch_ratio = 64.0
	xp_fill.custom_minimum_size = Vector2(0, 12)
	xp_track.add_child(xp_fill)
	var xp_rest := ColorRect.new()
	xp_rest.color = Color(0.08, 0.12, 0.16, 0.9)
	xp_rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_rest.size_flags_stretch_ratio = 36.0
	xp_rest.custom_minimum_size = Vector2(0, 12)
	xp_track.add_child(xp_rest)
	rv.add_child(UiTheme.make_label("军衔经验 64% · 距离下一军衔还差 36%", 12, UiTheme.TXT_DIM))
	rv.add_child(UiTheme.make_label("军衔晋升:少尉 → 上尉 → 少校", 12, UiTheme.TXT_DIM))
	var stats_panel := UiTheme.make_panel(0.7)
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(stats_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	stats_panel.add_child(sv)
	sv.add_child(UiTheme.make_label("生涯统计", 15, UiTheme.PRIMARY))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)
	var stats := [
		["总击杀", "1,248", UiTheme.TXT],
		["总阵亡", "862", UiTheme.TXT],
		["KD 比值", "1.45", Color(1, 0.85, 0.4)],
		["胜场", "86", UiTheme.FRIENDLY],
		["胜率", "61%", UiTheme.FRIENDLY],
		["最常用武器", "M4A1", UiTheme.TXT],
		["总游戏时长", "142h", UiTheme.TXT],
		["爆头率", "28%", UiTheme.TXT],
	]
	for st in stats:
		grid.add_child(_stat_card(st[0], st[1], st[2]))
	# 底部:最近战绩条形图 + 最近对局列表
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 14)
	root.add_child(bot)
	var chart_panel := UiTheme.make_panel(0.7)
	chart_panel.custom_minimum_size = Vector2(560, 200)
	bot.add_child(chart_panel)
	var cv := VBoxContainer.new()
	chart_panel.add_child(cv)
	cv.add_child(UiTheme.make_label("最近战绩", 14, UiTheme.PRIMARY))
	var bars := HBoxContainer.new()
	bars.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 14)
	cv.add_child(bars)
	var rounds := [ [true, 212], [true, 186], [false, 98], [true, 243], [false, 61], [true, 154], [true, 197], [false, 122] ]
	for r in rounds:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 3)
		bars.add_child(col)
		var tag := UiTheme.make_label("胜" if r[0] else "负", 11, UiTheme.FRIENDLY if r[0] else UiTheme.ENEMY)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(spacer)
		var bar := ColorRect.new()
		bar.color = UiTheme.FRIENDLY if r[0] else UiTheme.ENEMY
		bar.custom_minimum_size = Vector2(38, maxi(14, int(r[1]) / 2))
		col.add_child(bar)
	var list_panel := UiTheme.make_panel(0.7)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(list_panel)
	var lp := VBoxContainer.new()
	lp.add_theme_constant_override("separation", 6)
	list_panel.add_child(lp)
	lp.add_child(UiTheme.make_label("最近对局", 14, UiTheme.PRIMARY))
	var matches := [
		["断裂谷地", "征服", "212 : 178", true],
		["风暴海岸", "突破", "147 : 153", false],
		["迷雾森林", "征服", "243 : 150", true],
		["钢铁工厂", "征服", "98 : 210", false],
		["暗夜废墟", "突破", "186 : 164", true],
	]
	for mt in matches:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		lp.add_child(row)
		var tag := UiTheme.make_label("胜" if mt[3] else "负", 12, UiTheme.FRIENDLY if mt[3] else UiTheme.ENEMY)
		tag.custom_minimum_size = Vector2(24, 0)
		row.add_child(tag)
		row.add_child(UiTheme.make_label(str(mt[0]) + " · " + str(mt[1]), 13, UiTheme.TXT))
		var rowsp := Control.new()
		rowsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rowsp)
		row.add_child(UiTheme.make_label(str(mt[2]), 13, UiTheme.TXT_DIM))


func _stat_card(t: String, v: String, c: Color) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 74)
	p.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.0, 0.05, 0.08, 0.9), Color(0.22, 0.28, 0.34, 0.5), 1, 2, 10))
	var vc := VBoxContainer.new()
	vc.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vc)
	var vl := UiTheme.make_label(v, 22, c)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vc.add_child(vl)
	var tl := UiTheme.make_label(t, 12, UiTheme.TXT_DIM)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vc.add_child(tl)
	return p


## ==================== 商店界面 ====================
func _build_store() -> void:
	var s := _add_screen("store")
	_bg(s, Color(0.01, 0.03, 0.05, 0.9))
	s.add_child(UiTheme.BattleBg.new())
	_make_tab_bar(s, "store")
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 58
	root.offset_right = -24
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	s.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	head.add_child(UiTheme.make_label("军需商店", 30, UiTheme.TXT))
	head.add_child(UiTheme.make_label("ARMY STORE · 军需物资供应部", 14, UiTheme.PRIMARY))
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 12)
	root.add_child(center)
	center.add_child(UiTheme.make_label("敬 请 期 待", 42, UiTheme.PRIMARY))
	var sub := UiTheme.make_label("COMING SOON · 军需物资正在调配", 14, UiTheme.TXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.custom_minimum_size = Vector2(900, 200)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(grid)
	for i in 6:
		var ph := PanelContainer.new()
		ph.custom_minimum_size = Vector2(280, 80)
		ph.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.04, 0.06, 0.08, 0.85), Color(0.2, 0.26, 0.32, 0.4), 1, 2, 10))
		var phl := UiTheme.make_label("商品位 " + str(i + 1), 13, UiTheme.TXT_DIM)
		phl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.add_child(phl)
		grid.add_child(ph)
	var foot := UiTheme.make_label("更多军需物资即将上架 · 关注前线通告", 12, UiTheme.TXT_DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(foot)

