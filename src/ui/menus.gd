class_name Menus extends CanvasLayer
## 菜单系统(对应 index.html 全部界面 + hud.js 的菜单逻辑)

var on_start: Callable
var on_deploy: Callable
var on_deploy3d: Callable         # 实时 3D 部署:确认兵种后进入 3D 战场部署(main 赋值)
var on_redeploy: Callable
var on_resume: Callable
var on_quit: Callable
var on_again: Callable
var on_campaign_start: Callable       # 战役章节启动(main 赋值):G.mode="campaign" + start_match

var selected_class := "assault"
var br_selected_class := "assault"   # 任务1:BR 兵种选择屏所选兵种(GameMode_BR 开局读取)
var _br_class_cards: Dictionary = {} # 任务1:cid -> PanelContainer(选中高亮)
var loadout := {
	"assault": { "primary": "m4", "secondary": "m1911", "shotgun": "m1014", "gadget": "medkit" },
	"engineer": { "primary": "m249", "secondary": "m1911", "gadget": "rpg" },
	"support": { "primary": "mp5", "secondary": "m1911", "gadget": "medpack" },
	"recon": { "primary": "awm", "secondary": "m1911", "gadget": "beacon" },
}
# TDM 装备屏选择(任意武器主副搭配,不限兵种;默认 M4 + M1911)
var tdm_loadout := { "primary": "m4", "secondary": "m1911" }
# TDM 装备屏:槽位按钮表(wid → Button,点击高亮刷新用)
var _tdm_prim_btns: Dictionary = {}
var _tdm_sec_btns: Dictionary = {}
# TDM 武器分组(主=步枪/冲锋枪/机枪/狙击/霰弹;副=手枪;rpg 火箭筒属工程兵技能武器,不入池)
const TDM_KIND_GROUPS: Array = [
	["步枪", "rifle"], ["冲锋枪", "smg"], ["机枪", "lmg"],
	["狙击", "sniper"], ["霰弹", "shotgun"], ["手枪", "pistol"],
]
# TDM 地图池(6 张,顺序即展示顺序;与 game.gd _start_portal 池过滤一致:tdm 专属 + tdm_ok 主题图)
const TDM_MAP_IDS: Array = ["tdm_city", "city", "desert", "snow", "bt_jungle", "bt_harbor"]
# 地图卡预览强调色(按地图主题氛围;random=金色)
const TDM_MAP_ACCENTS := {
	"tdm_city": Color(0.0, 0.83, 1.0),
	"city": Color(0.4, 0.65, 1.0),
	"desert": Color(1.0, 0.78, 0.45),
	"snow": Color(0.75, 0.88, 1.0),
	"bt_jungle": Color(0.45, 0.85, 0.5),
	"bt_harbor": Color(1.0, 0.55, 0.35),
	"random": Color(1.0, 0.85, 0.25),
}
# TDM 地图选择(默认随机;确认出战时写入 G.sel_maps["tdm"],随机则清除沿用默认)
var tdm_map_sel := "random"
var _tdm_map_cards: Dictionary = {}   # map id("random" 含) → PanelContainer
var _tdm_map_hint: Label

var _screens: Dictionary = {}
var _briefing = null
var _map_btns: Array = []
var _slot_class: Button
var _slot_primary: Button
var _slot_shotgun: Button
var _slot_secondary: Button
var _submenu: PanelContainer
var _submenu_open := ""
var _map_select: HBoxContainer
var _deploy_bg: ColorRect
var _deploy_battlebg: Control
var _deploy_btn: Button
var info_panel: PanelContainer
var _deploy_title: Label
var _dep_ticket_us: Label
var _dep_ticket_ru: Label
var _side_sel: HBoxContainer
var _btn_side_att: Button
var _btn_side_def: Button
var _death_killer: Label
var _death_btn: Button
var _death_t := 0.0
var _death_shown_t := 0.0     # 死亡屏已显示时长(BR 真淘汰自动隐藏计时)
var _spawn_time := 5.0             # 重生倒计时(优先读 G.settings.spawn_time,无配置默认 5s)
var _deploy_overlay: Label
var _end_title: Label
var _end_stats: RichTextLabel
var _settings_from_pause := false  # 设置屏上下文:true=暂停菜单打开,返回时回暂停界面
var _pause_switch_btn: Button      # 暂停菜单"切换兵种"按钮(战役/门户模式隐藏,show_pause 时刷新)
var _portal_last_result: Dictionary = {}  # 门户对局结算数据(G.portal round_ended 提供;未就绪时为空)

# ---- UI 状态机:Opening → Open → Interacting → Closing → Closed ----
var _ui_state := "closed"
var _active_screen := ""
var _ui_lock := false


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
	_build_portal()
	_build_tdm_loadout()
	_build_br_class_select()  # 任务1:BR 兵种选择屏
	_build_armory()
	_build_battlepass()
	_build_profile()
	_build_store()
	_make_toast()
	hide_all()
	_show_screen("menu")
	# 调试:--test-campaign-menu 直接打开战役章节选择屏(验证构建)
	if OS.get_cmdline_user_args().has("--test-campaign-menu"):
		hide_all()
		_show_screen("campaign")
	# 调试:--test-armory-menu 直接打开枪械改装屏(验证 3D 预览 + 槽位/改装件构建)
	if OS.get_cmdline_user_args().has("--test-armory-menu"):
		hide_all()
		_show_screen("armory")
		_armory_enter()
	# 调试:--test-battlepass 直接打开战斗通行证屏(验证构建 + 皮肤装备交互)
	if OS.get_cmdline_user_args().has("--test-battlepass"):
		hide_all()
		_show_screen("battlepass")
		_bp_load_equipped(_bp_class)
		_refresh_bp_grid()
	# 调试:--test-portal-menu 直接打开门户模式选择屏(验证构建)
	if OS.get_cmdline_user_args().has("--test-portal-menu"):
		hide_all()
		_show_screen("portal")
	# 调试:--test-tdm-loadout 直接打开 TDM 装备选择屏(验证构建 + 全武器池)
	if OS.get_cmdline_user_args().has("--test-tdm-loadout"):
		hide_all()
		_open_tdm_loadout()


## 空白界面兜底:菜单态(未进入对局)下若所有页面都不可见,说明 UI 状态机出了岔子,
## 玩家会卡在没有 UI、也退不出去的黑屏里。持续 0.5s 仍为空白就强制恢复主菜单。
## 0.5s 去抖是为了避开"hide_all → start_match"这一帧的正常空窗,不会误盖游戏画面。
var _blank_t := 0.0

func _watchdog_blank_ui(dt: float) -> void:
	if G.state != "menu" or _ui_lock or _ui_state == "closing":
		_blank_t = 0.0
		return
	for k in _screens:
		if _screens[k].visible:
			_blank_t = 0.0
			return
	_blank_t += dt
	if _blank_t < 0.5:
		return
	_blank_t = 0.0
	G.log_err("UI", "菜单态下所有页面均不可见,已自动恢复主菜单", _ui_state + "/" + _active_screen)
	_show_screen("menu", true)


func _process(dt: float) -> void:
	_watchdog_blank_ui(dt)
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
	# 枪械改装 3D 预览:自动旋转(拖拽暂停)+ 槽位聚焦镜头平滑过渡
	if _screens.has("armory") and _screens["armory"].visible:
		if _arm_pivot != null and not _arm_dragging:
			_arm_yaw += dt * 0.4
			_arm_pivot.rotation = Vector3(_arm_pitch, _arm_yaw, 0)
		if _arm_cam != null:
			var k := 1.0 - exp(-dt * 5.0)
			_arm_cam.position = _arm_cam.position.lerp(_arm_focus_pos, k)
			_arm_cam.look_at(_arm_focus_target, Vector3.UP)
	# 死亡重生倒计时(动画:数字跳动,归零解锁)
	if _death_btn != null and _death_btn.is_inside_tree() and _screens.has("death") and _screens["death"].visible:
		# BR 真淘汰:死亡屏短暂展示后自动隐藏进入观战(不等待点击;与 game_mode_br 淘汰流程对齐)
		if G.mode == "br" and G.br != null and G.br.has_method("is_player_eliminated") \
				and G.br.is_player_eliminated():
			_death_shown_t += dt
			if _death_shown_t >= 1.5:
				hide_death()
		elif _death_t > 0:
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
	_ui_lock = false
	_ui_state = "closed"
	_active_screen = ""
	for k in _screens:
		_screens[k].visible = false
		_screens[k].modulate.a = 1.0
		_screens[k].scale = Vector2.ONE


## 只隐藏结算屏(hud.gd 门户 round_started 回调调用,防新对局开局残留结算盖 HUD)
func hide_end() -> void:
	_hide_screen("end")


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


## UI 状态机辅助:打开页面,带平滑过渡和防重复点击锁
func _show_screen(id: String, instant := false) -> void:
	if not _screens.has(id):
		G.log_err("UI", "尝试打开不存在的页面: " + id, _active_screen)
		return
	# 正在播放关闭动画时,不能因此拒绝打开新页面:
	# 「旧页面已淡出 + 新页面被 UI 锁挡住」会留下没有任何 UI、也退不出去的空白画面
	# (战役/门户「返回主菜单」历史 bug 即此)。打开动作直接接管状态机 ——
	# 下面会强制隐藏其它页面,不存在两个页面同时抢输入的问题。
	if _active_screen == id and _screens[id].visible:
		return
	_ui_lock = true
	_ui_state = "opening"
	_active_screen = id
	# 旧页面立即隐藏,新页面淡入;避免动画重叠导致输入混乱
	for k in _screens:
		if k != id and _screens[k].visible:
			_screens[k].visible = false
			# 上一次淡出可能把 alpha 停在 0:一并复位,避免下次打开时"可见但全透明"
			_screens[k].modulate.a = 1.0
			_screens[k].scale = Vector2.ONE
	var sc: Control = _screens[id]
	if instant:
		sc.visible = true
		sc.modulate.a = 1.0
		sc.scale = Vector2.ONE
		_ui_state = "open"
		_ui_lock = false
	else:
		UiTheme.fade_screen(sc, true, 0.18)
		_ui_state = "open"
		_ui_lock = false


## UI 状态机辅助:关闭页面,播放淡出后隐藏
func _hide_screen(id: String, instant := false) -> void:
	if not _screens.has(id):
		G.log_err("UI", "尝试关闭不存在的页面: " + id, _active_screen)
		return
	var sc: Control = _screens[id]
	if not sc.visible and _active_screen != id:
		return
	if instant:
		if _ui_lock and _active_screen != id:
			return
		sc.visible = false
		sc.modulate.a = 1.0
		sc.scale = Vector2.ONE
		if _active_screen == id:
			_active_screen = ""
		_ui_state = "closed"
		_ui_lock = false
		return
	if _ui_lock:
		return
	_ui_lock = true
	_ui_state = "closing"
	UiTheme.fade_screen(sc, false, 0.12, func():
		if _active_screen == id:
			_active_screen = ""
		_ui_state = "closed"
		_ui_lock = false)


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
	left.add_child(_make_mode_row("门户模式", "PORTAL · 自定义规则作战", false, func():
		AudioSys.ui()
		_open_portal_select()))
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
	bh.pressed.connect(func(): AudioSys.ui(); _show_screen("help"))
	fn_row.add_child(bh)
	var bs := UiTheme.make_button("设置", 14)
	bs.custom_minimum_size = Vector2(110, 38)
	bs.pressed.connect(func(): AudioSys.ui(); _settings_from_pause = false; _show_screen("settings"))
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
	"［公告］门户模式上线:团队死斗 11v11 · 大逃杀 25 队同场竞技",
	"［战报］大逃杀更新:100 名参赛者 · 开局仅手枪,物资/空投/毒圈每局随机",
	"［公告］团队死斗装备选择:任意武器主副搭配,死亡 2 秒自动复活",
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
Q 索敌标记 · G 手雷 · F 兵种装备 · E 驾驶/离开载具 · Tab 记分板 · Esc 暂停 · 长按 H 近战小刀

[b][color=#7fd0ff]征服模式规则[/color][/b]
占领并保持分布在战场四处的 A / B / C / D / E 五面旗帜,站在旗圈内即可占领。
击杀敌人使敌方兵力值 -1。当一方控制多数旗帜时,敌方兵力值将持续流失。
先将敌方 400 点兵力值耗尽的一方获胜。占领旗帜后会在该点附近部署载具。

[b][color=#7fd0ff]突破模式规则(攻防)[/color][/b]
你方担任[b]进攻方[/b],沿战线逐区域推进,每区域有 A / B 两个目标点。
[b]同时[/b]控制当前区域全部目标点即可突破该区域,并[b]补充 120 点兵力值[/b];已突破的区域不可被夺回。
[b]区域按顺序解锁[/b]:尚未攻到的区域处于封锁状态,地图上以灰色显示;越过封锁线会被遣返回战线,
且封锁区域内无法部署 —— 攻守双方都不能跨区域作战。
进攻方兵力值 320 点,每次阵亡 -1,耗尽即战败;防守方兵力无限。攻陷全部 3 个区域即获胜。
每夺取一个目标点都会在该点附近部署载具;阵亡后可在部署界面点击己方点位或绿点小队队友,直接部署到前线。

[b][color=#7fd0ff]兵种[/color][/b]
[color=#7fd0ff]突击兵[/color]:M4A1 / AK-47 / SCAR-H / AUG,可额外携带一把霰弹枪(按 2),医疗包。
[color=#ffc46b]工程兵[/color]:M249 / PKM / RPD + 反载具毒刺导弹(按 3)。瞄准空中载具 1 秒自动锁定,发射制导导弹。
[color=#9fe08a]支援兵[/color]:MP5 / UMP45 / P90 + 弹药箱(按 F 部署,圈内友军持续补给弹药并恢复生命)。
[color=#e0a0ff]侦察兵[/color]:AWM / M24 / SVD + 动态探测器。
副武器(全兵种通用):M1911 均衡 / 格洛克17 速射 / P226 精准 / 沙漠之鹰 手炮 / M93R 冲锋手枪。

[b][color=#7fd0ff]载具(残骸保留,点位易主后重新部署)[/color][/b]
地面:侦察吉普 / 装甲步战车(25mm 机炮)/ 自行防空炮 / 主战坦克。
空中(征服模式):武装直升机 / 战斗机 由 AI 驾驶巡逻,可用防空导弹或枪炮击落。
战场上的木质哨棚与岗楼可被爆炸物摧毁。
"""
	var close := UiTheme.make_button("返回", 15)
	close.custom_minimum_size = Vector2(200, 38)
	close.pressed.connect(func():
		AudioSys.ui()
		_show_screen("menu"))
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
	v.add_child(_make_slider("视角模型深度/臂长", 0.8, 1.4, 0.05, float(G.settings.get("viewmodel_depth", 1.0)),
		func(val): G.settings["viewmodel_depth"] = val, func(val): return str(int(val * 100)) + "%"))
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
	# ---- 3A 画质升级项(可自由开关,重启保留) ----
	v.add_child(_make_select("MSAA 抗锯齿", [[0, "关"], [1, "2x"], [2, "4x"], [3, "8x"]],
		int(G.settings.msaa), func(val): _apply_gfx("msaa", val)))
	v.add_child(_make_select("屏幕反射 SSR", [[true, "开"], [false, "关"]],
		G.settings.ssr, func(val): _apply_gfx("ssr", val)))
	v.add_child(_make_select("间接光照 SSIL", [[true, "开"], [false, "关"]],
		G.settings.ssil, func(val): _apply_gfx("ssil", val)))
	v.add_child(_make_select("泛光 Glow", [[true, "开"], [false, "关"]],
		G.settings.glow, func(val): _apply_gfx("glow", val)))
	v.add_child(_make_select("电影后期", [[true, "开"], [false, "关"]],
		G.settings.cinema, func(val): _apply_gfx("cinema", val)))
	v.add_child(_make_select("自动动态画质", [[true, "开(卡顿时自动降级)"], [false, "关(手动固定)"]],
		G.settings.auto_quality, func(val): _apply_gfx("auto_quality", val)))
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
		if from_pause:
			_show_screen("pause")  # 暂停中打开设置 → 返回暂停界面
		else:
			_show_screen("menu"))  # 主界面打开设置 → 返回主菜单
	outer_v.add_child(close)


func _apply_gfx(key: String, val) -> void:
	G.settings[key] = val
	if G.apply_graphics.is_valid():
		G.apply_graphics.call()
	GraphicsQuality.save_config()   # 画质细项立即落盘,重启保留
	if G.main != null and G.main.has_method("reset_dq"):
		G.main.reset_dq()           # [8/10] 手动改画质重置动态降级(手动优先)
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


## ==================== 部署界面(与实时 3D 战场同屏一体:透明背景 + 底部兵种/武器栏) ====================
func _build_deploy() -> void:
	var s := _add_screen("deploy")
	# 部署屏为 3D 战场同屏层:整屏鼠标穿透(拖动/点选由部署系统处理),仅装备栏按钮交互
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy_bg = _bg(s, Color(0, 0.01, 0.02, 0.0))
	_deploy_battlebg = UiTheme.BattleBg.new()
	s.add_child(_deploy_battlebg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 20
	root.offset_top = 14
	root.offset_right = -20
	root.offset_bottom = -14
	# 3D 部署模式:背景区域全部穿透鼠标(拖动平移地图由部署系统处理),仅底部装备栏交互
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(root)
	# ---- 顶栏:模式·地图 + 双方兵力(仅信息展示,不拦截鼠标) ----
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 30)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_deploy_title = UiTheme.make_label("选择兵种并部署", 22, UiTheme.TXT)
	top.add_child(_deploy_title)
	var tickets := HBoxContainer.new()
	tickets.add_theme_constant_override("separation", 16)
	tickets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tickets)
	_dep_ticket_us = UiTheme.make_label("友军 400", 18, UiTheme.FRIENDLY)
	tickets.add_child(_dep_ticket_us)
	_dep_ticket_ru = UiTheme.make_label("敌军 400", 18, UiTheme.ENEMY)
	tickets.add_child(_dep_ticket_ru)
	# ---- 突破模式:选择阵营(进攻方 us / 防守方 ru,只改变玩家阵营,世界攻防方向固定) ----
	_side_sel = HBoxContainer.new()
	_side_sel.alignment = BoxContainer.ALIGNMENT_CENTER
	_side_sel.add_theme_constant_override("separation", 10)
	_side_sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		_refresh_ticket_labels())
	_btn_side_def.pressed.connect(func():
		AudioSys.ui()
		_btn_side_def.button_pressed = true
		_btn_side_att.button_pressed = false
		G.game.set_bt_side("def")
		_refresh_ticket_labels())
	# ---- 主体:3D 战场直接透出(拖动平移地图);非 3D 模式下显示说明面板 ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var info_area := VBoxContainer.new()
	info_area.add_theme_constant_override("separation", 8)
	info_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(info_area)
	info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(0.55))
	info_area.add_child(info_panel)
	var info_v := VBoxContainer.new()
	info_v.add_theme_constant_override("separation", 6)
	info_panel.add_child(info_v)
	info_v.add_child(UiTheme.make_label("实时 3D 战场部署", 20, UiTheme.PRIMARY))
	info_v.add_child(UiTheme.make_label("左键拖动地图选择视角 · 点击部署点(队友 / 占领点 / 基地 / 载具)立即部署 · 空格部署基地", 14, UiTheme.TXT))
	info_v.add_child(UiTheme.make_label("底部装备栏同屏选择兵种与武器 · 死亡后同样进入实时 3D 部署", 13, Color(0.62, 0.75, 0.82)))
	var info_spacer := Control.new()
	info_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_v.add_child(info_spacer)
	info_v.add_child(UiTheme.make_label("WASD 平移 · 拖动地图 · 高度恒定", 13, UiTheme.TXT_DIM))
	info_area.add_child(UiTheme.make_label("地图选择", 13, UiTheme.TXT_DIM))
	_map_select = HBoxContainer.new()
	_map_select.add_theme_constant_override("separation", 6)
	_map_select.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_area.add_child(_map_select)
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
	var gadget_slot := _make_slot("兵种装备", "", func(): _toggle_submenu("gadget"))
	bar.add_child(gadget_slot)
	var nade_slot := _make_slot("投掷物", "", Callable())
	bar.add_child(nade_slot)
	nade_slot.disabled = true
	_gadget_slot_btn = gadget_slot
	_nade_slot_btn = nade_slot
	# DEPLOY 按钮(右侧青绿大按钮:确认兵种 → 进入实时 3D 战场部署)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var btn_deploy := UiTheme.make_cta("部  署", 26)
	btn_deploy.custom_minimum_size = Vector2(230, 72)
	btn_deploy.pressed.connect(func():
		AudioSys.ui()
		btn_deploy.disabled = true
		# 部署确认覆盖层:弹出动画 → 0.7s 后进入 3D 部署
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
			if on_deploy3d.is_valid():
				on_deploy3d.call(selected_class, loadout[selected_class])
			elif on_deploy.is_valid():
				on_deploy.call(selected_class, loadout[selected_class])))
	bar.add_child(btn_deploy)
	_deploy_btn = btn_deploy
	# 部署确认覆盖层(居中大字)
	_deploy_overlay = UiTheme.make_label("正在部署战区…", 34, UiTheme.PRIMARY)
	_deploy_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_deploy_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deploy_overlay.add_theme_stylebox_override("normal", UiTheme.stylebox(Color(0.0, 0.04, 0.06, 0.88), UiTheme.PRIMARY, 1, 4, 24))
	_deploy_overlay.visible = false
	_deploy_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(_deploy_overlay)
	_refresh_slots()


func show_deploy(is_redeploy := false) -> void:
	_refresh_ticket_labels()
	var map_name: String = MapsData.M()[G.current_map].cn if MapsData.M().has(G.current_map) else ""
	var mode_name := "征服模式"
	match G.mode:
		"breakthrough":
			mode_name = "突破模式(" + ("进攻方" if G.bt_player_side == "att" else "防守方") + ")"
		"tdm":
			mode_name = "团队死斗"
		"br":
			mode_name = "大逃杀"
	_deploy_title.text = mode_name + " · 选择兵种并部署 — " + map_name
	_map_select.visible = not is_redeploy
	_side_sel.visible = (not is_redeploy) and G.mode == "breakthrough"
	_btn_side_att.button_pressed = G.bt_player_side == "att"
	_btn_side_def.button_pressed = G.bt_player_side == "def"
	_close_submenu()
	_refresh_slots()
	# 实时 3D 部署:透明背景,3D 战场同屏透出(底部装备栏与战场一体);非 3D 模式保留旧式面板
	var in_deploy: bool = G.deployment != null and G.deployment.active
	if _deploy_bg != null:
		_deploy_bg.color = Color(0, 0.01, 0.02, 0.0 if in_deploy else 0.9)
	if _deploy_battlebg != null:
		_deploy_battlebg.visible = not in_deploy
	if info_panel != null:
		info_panel.visible = not in_deploy
	if _deploy_btn != null:
		_deploy_btn.text = "部  署"
	# 调试:--dbg-submenu <class|primary|shotgun|secondary|gadget> 自动打开兵种二级菜单
	var ua := OS.get_cmdline_user_args()
	var dbg_idx := ua.find("--dbg-submenu")
	if dbg_idx != -1 and ua.size() > dbg_idx + 1:
		_toggle_submenu(ua[dbg_idx + 1])
		# QA:打印二级菜单实际生成的卡片首行,便于无头文本断言(不依赖截图)
		var titles: PackedStringArray = PackedStringArray()
		for node in _submenu.find_children("*", "Button", true, false):
			titles.append(String((node as Button).text).split("\n")[0])
		print("[SUBMENU] ", ua[dbg_idx + 1], " 槽位=", _gadget_slot_btn.text.replace("\n", " | "),
			" 卡片=[", ", ".join(titles), "]")
	_build_map_select()
	_show_screen("deploy")


func hide_deploy() -> void:
	_hide_screen("deploy")
	if _deploy_bg != null:
		_deploy_bg.color = Color(0, 0.01, 0.02, 0.9)
	if _deploy_battlebg != null:
		_deploy_battlebg.visible = true
	if info_panel != null:
		info_panel.visible = true
	if _deploy_btn != null:
		_deploy_btn.text = "部  署"


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
	var gopt: Dictionary = WeaponsData.gadget_option(selected_class, String(lo.get("gadget", "")))
	_set_slot(_gadget_slot_btn, "兵种装备", String(gopt.get("cn", cls.gadget_cn)) + " ×" + str(int(gopt.get("count", cls.gadget_count))))
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
		"gadget":
			v.add_child(UiTheme.make_label(cls.cn + " — 选择兵种技能(二选一,按 F 使用 / 占武器槽者按 3 切换)", 14, UiTheme.PRIMARY))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			v.add_child(grid)
			var cur_g: String = String(WeaponsData.gadget_option(selected_class, String(lo.get("gadget", ""))).get("id", ""))
			for opt in WeaponsData.gadget_options(selected_class):
				grid.add_child(_make_gadget_card(opt, String(opt.get("id", "")) == cur_g, cls.color))
	_submenu.visible = true


func _make_class_card(cid: String, selected: bool) -> Button:
	var cls = WeaponsData.C()[cid]
	var card := Button.new()
	card.theme = UiTheme.theme()
	card.toggle_mode = true
	card.button_pressed = selected
	card.custom_minimum_size = Vector2(240, 108)
	var role_line: String = { "assault": "破阵 / 烟雾 / C5 / 自疗或榴弹", "engineer": "反载具 / 维修 / 毒刺或掩体",
		"support": "补给 / 医疗包或弹药包", "recon": "狙击 / 标记 / 信标或无人机" }.get(cid, "")
	var gsel: Dictionary = WeaponsData.gadget_option(cid, String((loadout.get(cid, {}) as Dictionary).get("gadget", "")))
	card.text = cls.icon + " " + cls.cn + "  " + cls.en + "\n" + role_line + "\n" \
		+ String(gsel.get("cn", cls.gadget_cn)) + " ×" + str(int(gsel.get("count", cls.gadget_count)))
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


## 兵种技能卡(第二技能二选一:名称 + 携带量 + 用法说明 + 占槽提示)
func _make_gadget_card(opt: Dictionary, selected: bool, accent: Color) -> Button:
	var gid := String(opt.get("id", ""))
	var card := Button.new()
	card.theme = UiTheme.theme()
	card.toggle_mode = true
	card.button_pressed = selected
	card.custom_minimum_size = Vector2(372, 112)
	var slot_line: String = "武器槽 · 按 3 切换" if bool(opt.get("weapon", false)) else "装备槽 · 按 F 使用"
	card.text = String(opt.get("cn", gid)) + "  ×" + str(int(opt.get("count", 2))) + "\n" \
		+ slot_line + "\n" + String(opt.get("desc", ""))
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_theme_font_size_override("font_size", 13)
	card.add_theme_color_override("font_color", UiTheme.TXT)
	_style_card(card, selected, accent)
	UiTheme.wire_button(card)
	card.pressed.connect(func():
		AudioSys.ui()
		loadout[selected_class]["gadget"] = gid
		_refresh_slots()
		_close_submenu())
	return card


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
			_refresh_ticket_labels())
		_map_select.add_child(b)
		_map_btns.append(b)


## 小队列表已在实时 3D 部署中完成(点击队友标记即选点),此处保留空实现兼容调用方
func _build_squad_list() -> void:
	pass


## ==================== 死亡界面(右下角,不压暗画面) ====================
func _build_death() -> void:
	var s := _add_screen("death")
	_bg(s, Color(0.1, 0.02, 0.02, 0.0))   # 背景透明(战场保持可见)
	# 右下角布局:SYSTEM FAIL + 击杀者 + 重新部署按钮(放大)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	v.offset_left = -420
	v.offset_right = -28
	v.offset_top = -230
	v.offset_bottom = -24
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 10)
	s.add_child(v)
	var t := UiTheme.make_label("SYSTEM FAIL", 60, Color(1, 0.4, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(t)
	_death_killer = UiTheme.make_label("", 22, Color(0.9, 0.75, 0.7))
	_death_killer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_death_killer)
	var b := UiTheme.make_button("重新部署", 26)
	b.custom_minimum_size = Vector2(380, 68)
	b.pressed.connect(func():
		AudioSys.ui()
		on_redeploy.call())
	v.add_child(b)
	_death_btn = b
	_death_btn.disabled = true
	_death_btn.text = "重新部署 (" + str(int(ceil(_spawn_time))) + ")"


func show_death(killer_text: String) -> void:
	_death_killer.text = killer_text
	_death_shown_t = 0.0
	_death_t = _spawn_time
	# 实时 3D 战场部署(征服/突破):死亡屏仅保留战况信息,部署操作在 3D 观察层完成
	var uses_3d: bool = G.deployment != null and (G.mode == "conquest" or G.mode == "breakthrough")
	if _death_btn != null:
		_death_btn.visible = not uses_3d
		_death_btn.disabled = true
		_death_btn.scale = Vector2.ONE
		# TDM:死亡 2 秒自动复活(模式控制器排定 RESPAWN_DELAY=2s),死亡屏仅作提示,
		# 隐藏倒计时与立即部署按钮(禁用态显示文案)
		if G.mode == "tdm":
			_death_t = 0.0
			_death_btn.text = "2 秒后自动复活"
			_death_btn.modulate = Color(0.85, 0.85, 0.85, 0.9)
		# BR 真淘汰(二次阵亡):无重部署机会 → 按钮改观战入口,倒计时禁用,
		# 展示 1.5s 后自动隐藏进入观战(_process 驱动)
		elif G.mode == "br" and G.br != null and G.br.has_method("is_player_eliminated") \
				and G.br.is_player_eliminated():
			_death_t = 0.0
			_death_btn.text = "进入观战"
			_death_btn.modulate = Color(0.85, 0.85, 0.85, 0.9)
		elif not uses_3d:
			_death_btn.text = "重新部署 (" + str(int(ceil(_spawn_time))) + ")"
			_death_btn.modulate = Color(0.85, 0.85, 0.85, 0.9)
	_show_screen("death")


func hide_death() -> void:
	_hide_screen("death")
	if _death_btn != null:
		_death_btn.visible = true
		_death_btn.disabled = true
		_death_btn.text = "重新部署 (" + str(int(ceil(_spawn_time))) + ")"
		_death_btn.scale = Vector2.ONE
		_death_btn.modulate = Color(1, 1, 1, 1)


## 实时 3D 部署的兵种面板关闭后:恢复死亡信息面板(击杀者提示)
func reshown_death_panel() -> void:
	if _death_killer != null and _screens.has("death"):
		show_death(_death_killer.text)


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
	var is_portal := G.mode == "tdm" or G.mode == "br"
	if is_portal:
		# 主动放弃对局(暂停菜单"放弃战斗"→ end_match 传 aborted):标题优先判 aborted,不再误判战败
		if bool(_portal_last_result.get("aborted", false)):
			_end_title.text = "已退出对局"
			_end_title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
			_end_stats.text = _portal_result_text()
			_show_screen("end")
			return
		_end_title.text = "胜 利" if win else ("你被淘汰" if G.mode == "br" else "战 败")
		_end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if win else Color(0.85, 0.4, 0.35))
		_end_stats.text = _portal_result_text()
		_show_screen("end")
		return
	_end_title.text = ("全线突破" if win else "进攻失败") if (is_bt and G.bt_player_side == "att") else (("防守成功" if win else "防线失守") if is_bt else ("胜 利" if win else "战 败"))
	_end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if win else Color(0.85, 0.4, 0.35))
	var kd := "%.2f" % (float(G.stats["kills"]) / maxf(1, float(G.stats["deaths"])))
	var line2 := ""
	if is_bt:
		var sec_done: int = int(mini(G.bt["sector"], G.bt["total"])) if G.bt != null else 0
		var total: int = int(G.bt["total"]) if G.bt != null else 3
		var att_left: int = maxi(0, int(ceil(G.tickets["us"])))
		if G.bt_player_side == "att":
			line2 = "攻陷区域 [b]" + str(sec_done) + "/" + str(total) + "[/b] · 剩余兵力 [b]" + str(att_left) + "[/b] · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]"
		else:
			line2 = "防守方坚守 [b]" + str(sec_done) + "/" + str(total) + "[/b] 区域 · 进攻方剩余兵力 [b]" + str(att_left) + "[/b] · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]"
	else:
		line2 = "最终兵力 — 友军 [b]" + str(maxi(0, int(ceil(G.tickets[G.player.team])))) + "[/b] : [b]" + str(maxi(0, int(ceil(G.tickets["ru" if G.player.team == "us" else "us"])))) + "[/b] 敌军 · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]"
	_end_stats.text = "击杀 [b]" + str(G.stats["kills"]) + "[/b] · 阵亡 [b]" + str(G.stats["deaths"]) + "[/b] · KD [b]" + kd + "[/b]\n" + line2
	_show_screen("end")


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
		# 只需 _show_screen:它会自行隐藏其它页面。先 _hide_screen 会加锁挡住打开(空白界面 bug)
		_show_screen("menu"))
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
	_show_screen("campaign")


## QA:当前可见页面列表(空 = 没有任何 UI,玩家会被卡在空白画面里)
func qa_visible_screens() -> String:
	var out: PackedStringArray = PackedStringArray()
	for k in _screens:
		if _screens[k].visible and _screens[k].modulate.a > 0.01:
			out.append(k)
	return ", ".join(out)


## QA:按标题找页面里的按钮并真实触发 pressed(走玩家点击的同一条回调)
func qa_press_button(screen_id: String, label: String) -> bool:
	if not _screens.has(screen_id):
		return false
	for node in _screens[screen_id].find_children("*", "Button", true, false):
		var b := node as Button
		if b != null and String(b.text).begins_with(label):
			b.pressed.emit()
			return true
	return false


## QA 诊断:菜单导航状态机快照(锁/状态/活动页/可见页)
func qa_nav_state() -> String:
	return "lock=%s state=%s active=%s visible=[%s]" % [
		str(_ui_lock), _ui_state, _active_screen, qa_visible_screens()]


## QA:遍历所有菜单类页面的「返回/取消」按钮,逐个点击并断言点完仍有可见 UI。
## 用于回归"点进子页面再返回 → 全部页面消失、无法退出"这类空白界面死锁。
## 只覆盖不需要活体玩家的页面(deploy/death/pause/end/loading 依赖对局状态,跳过)。
func qa_back_button_sweep() -> String:
	const MENU_SCREENS := ["campaign", "portal", "tdm_loadout", "br_class",
		"armory", "battlepass", "profile", "store", "settings", "help", "campaign_end"]
	var report: PackedStringArray = PackedStringArray()
	for id in MENU_SCREENS:
		if not _screens.has(id):
			continue
		_show_screen(id, true)
		if not _screens[id].visible:
			report.append("%s → 打不开(跳过)" % id)
			continue
		var pressed := ""
		for node in _screens[id].find_children("*", "Button", true, false):
			var b := node as Button
			if b == null:
				continue
			var t := String(b.text)
			if t.find("返回") >= 0 or t.find("取消") >= 0:
				pressed = t.replace("\n", " ")
				b.pressed.emit()
				break
		if pressed == "":
			report.append("%s → 无返回按钮(跳过)" % id)
			continue
		# 只看 visible:淡入首帧 alpha 仍为 0,而 bug 表现是所有页面 visible=false
		var vis: PackedStringArray = PackedStringArray()
		for k in _screens:
			if _screens[k].visible:
				vis.append(k)
		var vtxt := ", ".join(vis)
		report.append("%s -[%s]-> %s" % [id, pressed, vtxt if vtxt != "" else "空白!!(BUG)"])
	_show_screen("menu", true)
	return "\n".join(report)


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
	_show_screen("campaign_end")


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
	_show_screen("campaign")


## ==================== 门户模式(自定义规则):模式选择屏 + 结算 ====================
## 契约:PortalManager(src/core/portal/portal_manager.gd)信号 round_ended(result) →
## menus.show_portal_end(result);result 可选键:winner("us"/"ru"/"player")/my_win/
## us_score/ru_score/mvp{name,kills,deaths,assists}/table[{name,kills,deaths,assists}]
## 全部可选 —— 未就绪/缺键时 UI 照常显示,不崩溃
const PORTAL_MODES := {
	"tdm": {
		"cn": "团队死斗", "en": "TEAM DEATHMATCH",
		"accent": Color(0.0, 0.83, 1.0),
		"desc": [
			"蓝队 VS 红队 · 11v11 对抗",
			"击杀得分 · 死亡 2 秒自动复活",
			"倒计时 + 目标击杀数决定胜负",
			"MVP / 连杀 / 助攻 全程记录",
			"AI Bot 参战 · 随时加入战斗",
		],
		"map_cn": "tdm_city · 城市 TDM", "map_size": "120m",
		"players": "22 人", "dur": "约 5 分钟", "map_id": "tdm_city",
	},
	"br": {
		"cn": "大逃杀", "en": "BATTLE ROYALE",
		"accent": Color(1.0, 0.85, 0.25),
		"desc": [
			"100 人 · 25 队 × 4 人 · 开局选择兵种",
			"飞机跳伞 · 开局仅手枪 · 毒圈每局随机",
			"空投物资 · 护甲与药品补给 · 载具机动",
			"队内不互伤 · 最后存活的队伍获胜",
			"99 名 AI 同场竞技",
		],
		"map_cn": "br_valley · 山谷 BR", "map_size": "800m",
		"players": "100 人", "dur": "约 20 分钟", "map_id": "br_valley",
	},
}


## 程序化地图预览占位(门户卡片:暗底 + 网格 + 中心十字/圈 + 名称/尺寸;避免依赖贴图资源)
class PortalMapPreview extends Control:
	var title := ""
	var subtitle := ""
	var accent := UiTheme.PRIMARY

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0.02, 0.05, 0.07, 0.92))
		var step := 26.0
		var gc := Color(accent.r, accent.g, accent.b, 0.1)
		for x in range(0, int(sz.x) + 1, int(step)):
			draw_line(Vector2(x, 0), Vector2(x, sz.y), gc, 1)
		for y in range(0, int(sz.y) + 1, int(step)):
			draw_line(Vector2(0, y), Vector2(sz.x, y), gc, 1)
		# 中心十字 + 菱形 + 外圈(战场示意)
		var c := sz / 2.0
		draw_line(c + Vector2(-12, 0), c + Vector2(12, 0), accent, 1.4)
		draw_line(c + Vector2(0, -12), c + Vector2(0, 12), accent, 1.4)
		var ds := 5.0
		draw_polyline(PackedVector2Array([c + Vector2(0, -ds), c + Vector2(ds, 0), c + Vector2(0, ds), c + Vector2(-ds, 0), c + Vector2(0, -ds)]), accent, 1.2)
		draw_arc(c, 26.0, 0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.5), 1.2)
		# 名称 + 尺寸(中文用项目字体,避免 mono 无中文字形;数字随之一并使用 font())
		draw_string(UiTheme.font(), Vector2(10, 18), title,
			HORIZONTAL_ALIGNMENT_LEFT, sz.x - 20, 13, Color(0.8, 0.9, 0.95, 0.92))
		draw_string(UiTheme.font(), Vector2(10, 34), subtitle,
			HORIZONTAL_ALIGNMENT_LEFT, sz.x - 20, 11, Color(0.45, 0.55, 0.62, 0.9))


func _build_portal() -> void:
	var s := _add_screen("portal")
	_bg(s, Color(0.01, 0.03, 0.05, 0.96))
	s.add_child(UiTheme.BattleBg.new())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 30
	v.offset_top = 22
	v.offset_right = -30
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 12)
	s.add_child(v)
	# 顶栏:标题 + 英文副题
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UiTheme.make_label("门户模式", 34, UiTheme.TXT))
	head.add_child(UiTheme.make_label("PORTAL · 自定义规则作战", 15, UiTheme.PRIMARY))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	head.add_child(UiTheme.make_label("选择规则 · 自定义战场体验", 13, UiTheme.TXT_DIM))
	# 模式卡片(左右并排)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cards)
	cards.add_child(_portal_mode_card("tdm"))
	cards.add_child(_portal_mode_card("br"))
	# 返回
	var back := UiTheme.make_button("返回主菜单", 15)
	back.custom_minimum_size = Vector2(200, 38)
	back.pressed.connect(func():
		AudioSys.ui()
		# 只需 _show_screen(它会隐藏其它页面);先 _hide_screen 会加锁挡住打开
		_show_screen("menu"))
	v.add_child(back)


func _open_portal_select() -> void:
	_show_screen("portal")


## 模式卡片:中文名 + 英文名 + 程序化地图预览 + 介绍文案 + 人数/时长 + 开始匹配
func _portal_mode_card(mid: String) -> Control:
	var d: Dictionary = PORTAL_MODES[mid]
	var accent: Color = d["accent"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.0, 0.03, 0.05, 0.9), Color(accent.r, accent.g, accent.b, 0.55), 1, 3, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	# 标题行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(UiTheme.make_label(str(d["cn"]), 26, UiTheme.TXT))
	head.add_child(UiTheme.make_label(str(d["en"]), 14, accent))
	# 地图预览
	var prev := PortalMapPreview.new()
	prev.custom_minimum_size = Vector2(0, 132)
	prev.title = str(d["map_cn"])
	prev.subtitle = "对局地图 · " + str(d["map_size"]) + " 战场半径"
	prev.accent = accent
	v.add_child(prev)
	# 介绍文案
	var dl := UiTheme.make_label("", 13, Color(0.72, 0.78, 0.83))
	var dlines: Array = []
	for dd in d["desc"]:
		dlines.append("◆ " + str(dd))
	dl.text = "\n".join(dlines)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dl)
	# 人数 / 时长 chips
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	v.add_child(chips)
	chips.add_child(_portal_chip("参战人数 · " + str(d["players"]), accent))
	chips.add_child(_portal_chip("预计时长 · " + str(d["dur"]), Color(0.75, 0.8, 0.85)))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	# 开始匹配(TDM 先进装备选择屏:任意武器主副搭配;BR 卡片先开兵种选择屏,任务1)
	var start := UiTheme.make_cta("开始匹配", 17)
	start.custom_minimum_size = Vector2(0, 48)
	start.pressed.connect(func():
		if mid == "tdm":
			G.sel_mode = "tdm"
			_open_tdm_loadout()
		elif mid == "br":
			_br_card_start_click("br")
		else:
			_portal_start(mid))
	v.add_child(start)
	return panel


func _portal_chip(text: String, accent: Color) -> Label:
	var l := UiTheme.make_label(text, 12, Color(0.85, 0.9, 0.92))
	l.add_theme_stylebox_override("normal",
		UiTheme.stylebox(Color(0.0, 0.09, 0.12, 0.85), Color(accent.r, accent.g, accent.b, 0.45), 1, 2, 8))
	return l


# ==================== TDM 装备选择屏(任意武器主副搭配,不限兵种) ====================

## 打开 TDM 装备屏(TDM 卡片"开始匹配"回调 → 先选装备再开对局)
func _open_tdm_loadout() -> void:
	# 恢复上次选择(G.sel_maps["tdm"] 有效 id 或 random;脏值回落随机)
	var cur := str(G.sel_maps.get("tdm", "random"))
	tdm_map_sel = cur if (cur == "random" or TDM_MAP_IDS.has(cur)) else "random"
	_tdm_map_refresh()
	_show_screen("tdm_loadout")


## 返回门户模式选择页
func _back_from_tdm_loadout() -> void:
	AudioSys.ui()
	_show_screen("portal")


## 确认出战:装备已写入 menus.tdm_loadout(模式控制器 game_mode_tdm.start() 读取),
## 地图选择写入 G.sel_maps["tdm"](game.gd start 读取;随机则清除键沿用默认随机),
## 开始对局流程与 _portal_start 一致(G.mode/sel_maps → on_start)
func _confirm_tdm_loadout() -> void:
	AudioSys.ui()
	G.mode = "tdm"
	if tdm_map_sel == "random":
		G.sel_maps.erase("tdm")
	else:
		G.sel_maps["tdm"] = tdm_map_sel
	hide_all()
	if on_start.is_valid():
		on_start.call()


## TDM 武器分组:读 WeaponsData.W() 全量,按 TDM_KIND_GROUPS 类别分组
## (rpg 火箭筒为工程兵技能武器且不在六类分组内 → 自动不入选择池)
func _tdm_group_weapons() -> Dictionary:
	var out := {}
	for g in TDM_KIND_GROUPS:
		out[g[1]] = []
	for wid in WeaponsData.W():
		var kind: String = WeaponsData.W()[wid].kind
		if out.has(kind):
			out[kind].append(wid)
	return out


## TDM 装备屏:标题 + 主/副武器分栏(分组网格,滚动)+ 底部返回/确认
func _build_tdm_loadout() -> void:
	var s := _add_screen("tdm_loadout")
	_bg(s, Color(0.01, 0.03, 0.05, 0.96))
	s.add_child(UiTheme.BattleBg.new())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 30
	v.offset_top = 22
	v.offset_right = -30
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 12)
	s.add_child(v)
	# 顶栏:标题 + 英文副题 + 规则提示
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UiTheme.make_label("团队死斗 · 装备选择", 30, UiTheme.TXT))
	head.add_child(UiTheme.make_label("TEAM DEATHMATCH · LOADOUT", 14, UiTheme.PRIMARY))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	head.add_child(UiTheme.make_label("任意武器 · 不限兵种 · 兵种技能禁用", 13, UiTheme.TXT_DIM))
	# 主/副武器两栏(滚动分组网格)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var groups := _tdm_group_weapons()
	cols.add_child(_tdm_weapon_column("主武器 — 步枪 / 冲锋枪 / 机枪 / 狙击 / 霰弹", groups, "primary"))
	cols.add_child(_tdm_weapon_column("副武器 — 手枪", groups, "secondary"))
	# 地图选择区:标题行 + 6 张地图 + 随机(共 7 卡,单选高亮;确认出战写入 G.sel_maps["tdm"])
	var msec := VBoxContainer.new()
	msec.add_theme_constant_override("separation", 6)
	v.add_child(msec)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	msec.add_child(mrow)
	mrow.add_child(UiTheme.make_label("选择地图", 16, UiTheme.TXT))
	mrow.add_child(UiTheme.make_label("6 张地图 + 随机 · 点击卡片选中", 12, UiTheme.TXT_DIM))
	var msp := Control.new()
	msp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(msp)
	_tdm_map_hint = UiTheme.make_label("已选地图: 随机", 12, UiTheme.PRIMARY)
	mrow.add_child(_tdm_map_hint)
	var mcards := HBoxContainer.new()
	mcards.add_theme_constant_override("separation", 10)
	msec.add_child(mcards)
	_tdm_map_cards.clear()
	for mid in TDM_MAP_IDS:
		mcards.add_child(_tdm_map_card(mid))
	mcards.add_child(_tdm_map_card("random"))
	_tdm_map_refresh()
	# 底部:返回 + 确认出战
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	var back := UiTheme.make_button("返回", 15)
	back.custom_minimum_size = Vector2(200, 44)
	back.pressed.connect(_back_from_tdm_loadout)
	foot.add_child(back)
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fsp)
	foot.add_child(UiTheme.make_label("默认 M4A1 + M1911 · 点击武器高亮选中", 13, UiTheme.TXT_DIM))
	var confirm := UiTheme.make_cta("确认出战", 18)
	confirm.custom_minimum_size = Vector2(240, 44)
	confirm.pressed.connect(_confirm_tdm_loadout)
	foot.add_child(confirm)


## 一列武器面板:分组标题 + 滚动网格(按钮点击选中高亮,单选)
func _tdm_weapon_column(title: String, groups: Dictionary, slot: String) -> PanelContainer:
	var accent := UiTheme.PRIMARY if slot == "primary" else Color(0.85, 0.6, 0.3)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.0, 0.03, 0.05, 0.88), Color(accent.r, accent.g, accent.b, 0.5), 1, 3, 12))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(UiTheme.make_label(title, 15, accent))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var btns: Dictionary = _tdm_prim_btns if slot == "primary" else _tdm_sec_btns
	for g in TDM_KIND_GROUPS:
		var kind: String = g[1]
		if (kind == "pistol") != (slot == "secondary"):
			continue  # 手枪仅进副武器列;其余仅进主武器列
		var wid_list: Array = groups.get(kind, [])
		if wid_list.is_empty():
			continue
		var gl := UiTheme.make_label("— " + str(g[0]) + " —", 12, Color(0.55, 0.65, 0.72))
		grid.add_child(gl)
		grid.add_child(Control.new())
		for wid in wid_list:
			var sel: bool = tdm_loadout[slot] == wid
			var b := Button.new()
			b.theme = UiTheme.theme()
			b.toggle_mode = true
			b.button_pressed = sel
			b.custom_minimum_size = Vector2(210, 58)
			var w = WeaponsData.W()[wid]
			var dmg_text := str(w.damage) + ("×" + str(w.pellets) if w.pellets > 1 else "")
			b.text = w.cn + "\n伤害 " + dmg_text + " · 射速 " + str(w.rpm) + " · 弹匣 " + str(w.mag)
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_color_override("font_color", UiTheme.TXT)
			_tdm_style_weapon(b, sel, accent)
			UiTheme.wire_button(b)
			b.pressed.connect(func():
				AudioSys.ui()
				tdm_loadout[slot] = wid
				_tdm_refresh_highlight(slot, wid))
			btns[wid] = b
			grid.add_child(b)
	return panel


## 武器按钮样式(选中 = 高亮边框)
func _tdm_style_weapon(b: Button, selected: bool, accent: Color) -> void:
	var bg := Color(0.0, 0.14, 0.18, 0.95) if selected else Color(0.0, 0.03, 0.05, 0.9)
	var border := accent if selected else Color(0.22, 0.28, 0.34, 0.5)
	b.add_theme_stylebox_override("normal", UiTheme.stylebox(bg, border, 2 if selected else 1, 3, 6))
	b.add_theme_stylebox_override("hover", UiTheme.stylebox(Color(0.0, 0.2, 0.26, 0.95), border, 2, 3, 6))
	b.add_theme_stylebox_override("pressed", UiTheme.stylebox(bg, border, 2, 3, 6))
	b.add_theme_stylebox_override("focus", UiTheme.stylebox(bg, border, 2, 3, 6))


## 点击后刷新该槽位全部按钮高亮(单选;wid 为空时仅刷新样式不改变选择)
func _tdm_refresh_highlight(slot: String, wid: String) -> void:
	var btns: Dictionary = _tdm_prim_btns if slot == "primary" else _tdm_sec_btns
	var accent := UiTheme.PRIMARY if slot == "primary" else Color(0.85, 0.6, 0.3)
	for bw in btns:
		var b: Button = btns[bw]
		var sel: bool = bw == wid
		b.button_pressed = sel
		_tdm_style_weapon(b, sel, accent)


## TDM 地图卡:小预览块(PortalMapPreview,复用门户卡风格)+ 中文名 + 透明点击层;
## 选中高亮边框(accent 描边);"random" 卡为金色随机
func _tdm_map_card(mid: String) -> Control:
	var accent: Color = TDM_MAP_ACCENTS.get(mid, UiTheme.PRIMARY)
	var cn := str(mid)
	var md = MapsData.M().get(mid)
	if md != null:
		cn = md.cn
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(150, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		UiTheme.stylebox(Color(0.0, 0.03, 0.05, 0.9), Color(0.22, 0.28, 0.34, 0.5), 1, 2, 8))
	var cv := VBoxContainer.new()
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_theme_constant_override("separation", 5)
	card.add_child(cv)
	var prev := PortalMapPreview.new()
	prev.custom_minimum_size = Vector2(0, 58)
	prev.title = cn
	prev.subtitle = str(mid)
	prev.accent = accent
	cv.add_child(prev)
	var nl := UiTheme.make_label(cn, 12, UiTheme.TXT)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(nl)
	var ov := Button.new()
	ov.theme = UiTheme.theme()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	var esb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		ov.add_theme_stylebox_override(st, esb)
	ov.pressed.connect(func():
		AudioSys.ui()
		tdm_map_sel = mid
		_tdm_map_refresh())
	card.add_child(ov)
	_tdm_map_cards[mid] = card
	return card


## 刷新地图卡高亮(单选) + 标题行当前选择提示
func _tdm_map_refresh() -> void:
	for mid in _tdm_map_cards:
		var card: PanelContainer = _tdm_map_cards[mid]
		var sel: bool = mid == tdm_map_sel
		var accent: Color = TDM_MAP_ACCENTS.get(mid, UiTheme.PRIMARY)
		card.add_theme_stylebox_override("panel", UiTheme.stylebox(
			Color(0.0, 0.14, 0.18, 0.95) if sel else Color(0.0, 0.03, 0.05, 0.9),
			accent if sel else Color(0.22, 0.28, 0.34, 0.5),
			2 if sel else 1, 2, 8))
	if _tdm_map_hint != null:
		var cn := "随机"
		if tdm_map_sel != "random":
			var md = MapsData.M().get(tdm_map_sel)
			if md != null:
				cn = md.cn
		_tdm_map_hint.text = "已选地图: " + cn


## 开始匹配:与主菜单模式行同风格(G.mode 赋值 → on_start);地图选择写入 sel_maps,
## 未匹配到门户地图时 game.gd 自带防御(中止开局而非崩溃)
func _portal_start(mid: String) -> void:
	AudioSys.ui()
	G.mode = mid
	G.sel_maps[mid] = PORTAL_MODES[mid]["map_id"]
	hide_all()
	if on_start.is_valid():
		on_start.call()


## 任务1:BR 卡片【开始匹配】→ 兵种选择屏(仅 BR 卡片自身回调;TDM 装备屏流程不动)
func _br_card_start_click(mid: String) -> void:
	AudioSys.ui()
	if mid != "br":
		_portal_start(mid)
		return
	_br_class_highlight()
	_show_screen("br_class")


## ==================== 任务1:BR 兵种选择屏(大逃杀 · 选择兵种) ====================
## 4 张兵种卡片(读 WeaponsData.C() 名称/描述/技能);选中高亮;
## 【确认跳伞】记录 br_selected_class 并开始对局;【返回】回门户。
func _build_br_class_select() -> void:
	var s := _add_screen("br_class")
	_bg(s, Color(0.01, 0.03, 0.05, 0.96))
	s.add_child(UiTheme.BattleBg.new())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 40
	v.offset_top = 26
	v.offset_right = -40
	v.offset_bottom = -20
	v.add_theme_constant_override("separation", 14)
	s.add_child(v)
	# 顶栏:标题 + 副题
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UiTheme.make_label("大逃杀 · 选择兵种", 30, UiTheme.TXT))
	head.add_child(UiTheme.make_label("BATTLE ROYALE · CLASS", 14, Color(1.0, 0.85, 0.25)))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	head.add_child(UiTheme.make_label("兵种决定外观与技能 · 开局仅手枪 · 25 队 × 4 人", 13, UiTheme.TXT_DIM))
	# 4 张兵种卡片
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cards)
	_br_class_cards.clear()
	for cid in ["assault", "engineer", "support", "recon"]:
		var cls = WeaponsData.C()[cid]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, 0)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel",
			UiTheme.stylebox(Color(0.0, 0.04, 0.06, 0.9), Color(0.35, 0.4, 0.45, 0.35), 1, 3, 12))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		panel.add_child(cv)
		cv.add_child(UiTheme.make_label("%s %s" % [cls.icon, cls.cn], 20, cls.color))
		cv.add_child(UiTheme.make_label(str(cls.en), 11, UiTheme.TXT_DIM))
		var dl := UiTheme.make_label(str(cls.desc), 12, Color(0.72, 0.78, 0.83))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(dl)
		cv.add_child(UiTheme.make_label("技能:F — " + str(cls.gadget_cn), 12, Color(0.95, 0.85, 0.5)))
		if cid == "recon":
			cv.add_child(UiTheme.make_label("大逃杀禁用:重生信标", 11, Color(1.0, 0.5, 0.45)))
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(sp)
		var pick := UiTheme.make_cta("选择", 15)
		pick.custom_minimum_size = Vector2(0, 40)
		pick.pressed.connect(func():
			br_selected_class = cid
			_br_class_highlight())
		cv.add_child(pick)
		_br_class_cards[cid] = panel
		cards.add_child(panel)
	# 底部按钮行:返回 / 确认跳伞
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var back := UiTheme.make_button("返回", 15)
	back.custom_minimum_size = Vector2(160, 42)
	back.pressed.connect(func():
		AudioSys.ui()
		_show_screen("portal"))
	row.add_child(back)
	var confirm := UiTheme.make_cta("确认跳伞", 17)
	confirm.custom_minimum_size = Vector2(0, 42)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func(): _portal_start("br"))
	row.add_child(confirm)
	_br_class_highlight()


## 选中卡片高亮(金色描边 + 加粗),其余灰边
func _br_class_highlight() -> void:
	for cid in _br_class_cards:
		var panel: PanelContainer = _br_class_cards[cid]
		var sel: bool = cid == br_selected_class
		panel.add_theme_stylebox_override("panel", UiTheme.stylebox(
			Color(0.0, 0.04, 0.06, 0.9),
			Color(1.0, 0.85, 0.25) if sel else Color(0.35, 0.4, 0.45, 0.35),
			2 if sel else 1, 3, 12))


## 门户对局结算(G.portal round_ended 驱动;复用 _build_end 的标题/统计/按钮布局)
func show_portal_end(result: Dictionary) -> void:
	_portal_last_result = result
	G.state = "over"
	G.paused = false
	if G.hud != null:
		G.hud.hide_screen("hud")
	if G.input_sys != null:
		G.input_sys.unlock()
	var winner := str(result.get("winner", result.get("winner_team", "")))
	var win := false
	# 结算结果键兼容三种来源:BR 带 my_win;TDM 只有 win(true→胜/false→负);
	# 旧契约按 winner 阵营推导。优先级 my_win > win > winner
	if bool(result.get("aborted", false)):
		# 主动放弃对局(暂停菜单"放弃战斗"):不判定胜负,直接显示退出
		_end_title.text = "已退出对局"
		_end_title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		_end_stats.text = _portal_result_text()
		hide_all()
		_show_screen("end")
		return
	if result.has("my_win"):
		win = bool(result["my_win"])
	elif result.has("win"):
		win = bool(result["win"])
	elif winner != "" and G.player != null:
		win = winner == str(G.player.team)
	if winner == "us" or winner == "ru":
		_end_title.text = ("蓝队胜出" if winner == "us" else "红队胜出") + " · " + ("我方获胜" if win else "我方落败")
	else:
		_end_title.text = "胜 利" if win else ("你被淘汰" if G.mode == "br" else "战 败")
	_end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if win else Color(0.85, 0.4, 0.35))
	_end_stats.text = _portal_result_text()
	hide_all()
	_show_screen("end")


## 门户结算统计(胜方比分 / 个人 KD / MVP / 战绩表;result 缺键时逐项降级)
func _portal_result_text() -> String:
	var r: Dictionary = _portal_last_result
	var kd := "%.2f" % (float(G.stats["kills"]) / maxf(1, float(G.stats["deaths"])))
	var lines: Array = ["击杀 [b]" + str(G.stats["kills"]) + "[/b] · 阵亡 [b]" + str(G.stats["deaths"]) + "[/b] · KD [b]" + kd + "[/b]"]
	# BR:最终排名(BR result 含 rank/teams,缺省按 25 队)
	if G.mode == "br":
		var rank: int = int(r.get("rank", 0))
		var teams_n: int = int(r.get("teams", 25))
		if rank > 0:
			lines.append("最终排名 [b]第 " + str(rank) + " 名[/b](共 " + str(teams_n) + " 队)")
	var us_s = r.get("us_score", r.get("us", null))
	var ru_s = r.get("ru_score", r.get("ru", null))
	if us_s != null and ru_s != null:
		lines.append("最终比分 — 蓝队 [b]" + str(us_s) + "[/b] : [b]" + str(ru_s) + "[/b] 红队 · 用时 [b]" + Utils.fmt_time(G.time) + "[/b]")
	else:
		lines.append("用时 [b]" + Utils.fmt_time(G.time) + "[/b]")
	var mvp = r.get("mvp")
	if mvp is Dictionary:
		var mn: String = str(mvp.get("name", mvp.get("bot_name", "?")))
		var assist_txt := (" / " + str(mvp.get("assists", 0)) + " 助攻") if int(mvp.get("assists", 0)) > 0 else ""
		lines.append("MVP [b][color=#ffd24d]" + mn + "[/color][/b] — " + str(mvp.get("kills", 0)) + " 击杀 / " + str(mvp.get("deaths", 0)) + " 阵亡" + assist_txt)
	# 战绩表键兼容:TDM 实际提供 top_players(前 5)/scoreboard(全量),旧契约键为 table
	var tbl: Variant = r.get("table", null)
	if tbl == null:
		tbl = r.get("top_players", null)
		if tbl == null:
			tbl = r.get("scoreboard", [])
	if tbl is Array and not (tbl as Array).is_empty():
		var tl: Array = []
		for e in tbl:
			if e is Dictionary:
				var t_name: String = str(e.get("name", e.get("bot_name", "?")))
				var t_extra := ""
				if int(e.get("assists", 0)) > 0:
					t_extra = "/" + str(e.get("assists", 0)) + " 助"
				tl.append(t_name + " " + str(e.get("kills", 0)) + "/" + str(e.get("deaths", 0)) + t_extra)
		if not tl.is_empty():
			lines.append("战绩表: " + " · ".join(tl))
	return "\n".join(lines)


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
	# "切换兵种":战役(线性关卡无部署系统)+ 门户 TDM/BR(自动复活流程,无兵种部署概念)隐藏
	var b_switch := UiTheme.make_button("切换兵种", 15)
	b_switch.custom_minimum_size = Vector2(260, 40)
	b_switch.pressed.connect(func():
		AudioSys.ui()
		_switch_class_from_pause())
	b_switch.visible = G.mode != "campaign" and G.mode != "tdm" and G.mode != "br"
	_pause_switch_btn = b_switch
	v.add_child(b_switch)
	var b_set := UiTheme.make_button("设置", 15)
	b_set.custom_minimum_size = Vector2(260, 40)
	b_set.pressed.connect(func():
		AudioSys.ui()
		_settings_from_pause = true
		# 不要先 _hide_screen("pause") 再 _show_screen("settings"):
		# _hide_screen 会加 UI 锁,导致 _show_screen 被锁挡住,最终所有页面消失。
		_show_screen("settings"))
	v.add_child(b_set)
	var b2 := UiTheme.make_button("放弃战斗", 15)
	b2.custom_minimum_size = Vector2(260, 40)
	b2.pressed.connect(func():
		AudioSys.ui()
		on_quit.call())
	v.add_child(b2)


func show_pause(p_show: bool) -> void:
	if p_show:
		_show_screen("pause")
	else:
		_hide_screen("pause")
	# 暂停菜单在启动时一次性构建(G.mode 当时为默认值),每次弹出按当前模式刷新
	# "切换兵种"可见性:战役/门户 TDM/BR 隐藏(避免误入部署屏/破坏模式自动复活流程)
	if _pause_switch_btn != null:
		_pause_switch_btn.visible = G.mode != "campaign" and G.mode != "tdm" and G.mode != "br"


func is_pause_visible() -> bool:
	return _screens["pause"].visible


## 暂停菜单 → 切换兵种:还原暂停态 → 载具中先下车 → 强制阵亡 → 进入实时 3D 战场部署(选兵种在部署中按 F2)
func _switch_class_from_pause() -> void:
	hide_all()
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
	# 征服/突破:死亡已自动进入实时 3D 部署(倒下动画 → 升空),同屏装备栏选兵种武器
	if G.deployment != null and G.deployment.active:
		return
	G.game.redeploy()  # 隐藏死亡界面 + show_deploy(true) + state="deploy"(其余模式兜底)


## 关闭设置屏(暂停中打开设置后按 Esc 恢复战斗等场景兜底)
func close_settings() -> void:
	_settings_from_pause = false
	if _screens.has("settings"):
		_hide_screen("settings")


## ==================== 加载 / 战场简报 ====================
func _build_loading() -> void:
	var s := _add_screen("loading")
	var lb: GDScript = load("res://src/ui/briefing_loading.gd")
	if lb != null:
		_briefing = lb.new()
		s.add_child(_briefing)


func show_loading(p_show: bool) -> void:
	if p_show:
		_show_screen("loading", true)
	else:
		_hide_screen("loading", true)


## 加载开始:填充地图情报(地图数据已在 Game 选图时确定)
func briefing_setup(map_id: String, mode: String) -> void:
	if _briefing != null:
		_briefing.setup(map_id, mode)
	show_loading(true)


## 真实加载阶段反馈(Game.setup_map / bot reset 等阶段前调用)
func set_loading_stage(stage: String, progress: float, detail := "") -> void:
	if _briefing != null:
		_briefing.set_stage(stage, progress, detail)


## 加载结束:交给部署/游戏状态机;不做多余停留
func finish_loading() -> void:
	if _briefing != null:
		_briefing.set_stage("战场已就绪", 1.0, "正在进入实时部署…")
	_hide_screen("loading", true)


func show_menu() -> void:
	hide_all()
	_show_screen("menu")
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
	_show_screen(id)
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
const ARM_SLOT_CN := {
	"muzzle": "枪口", "barrel": "枪管", "grip": "握把", "stock": "枪托",
	"mag": "弹匣", "trigger": "扳机", "optic": "瞄具", "laser": "镭射/手电",
}
const STAT_CN := {
	"mag_ammo": "弹匣容量", "reload_mult": "换弹速度", "recoil_mult": "后座控制", "recoil_pitch_mult": "垂直后座控制",
	"recoil_yaw_mult": "水平后座控制", "hip_spread_mult": "腰射精度", "spread_mult": "散布精度",
	"aim_stability": "瞄准稳定", "ads_speed_mult": "开镜速度",
	"fire_rate_mult": "射速", "dmg_mult": "伤害", "suppress": "隐蔽", "mobility_mult": "移动速度",
}
const KIND_CN := {
	"rifle": "突击步枪", "smg": "冲锋枪", "lmg": "轻机枪", "shotgun": "霰弹枪",
	"sniper": "狙击步枪", "pistol": "手枪", "rpg": "反载具导弹", "dmr": "精确射手步枪",
}
var _arm_weapon := ""                # 记住上次选择的武器(切 Tab 回来不丢)
var _arm_cfg: Dictionary = {}        # 工作配置 {槽位: 件id}(未保存)
var _arm_open_slot := ""
var _arm_pivot: Node3D = null
var _arm_cam: Camera3D = null
var _arm_cam_base := Vector3(0, 0.32, 2.6)
var _arm_focus_pos := Vector3(0, 0.32, 2.6)
var _arm_focus_target := Vector3(0, -0.02, -0.2)
var _arm_yaw := 0.0
var _arm_pitch := 0.0
var _arm_dragging := false
var _arm_zoom := 2.6
var _arm_list: VBoxContainer = null
var _arm_slots: VBoxContainer = null
var _arm_cur_label: Label = null
var _arm_stats: VBoxContainer = null
var _mod_data: Dictionary = {}       # {槽位:{件id:{n,d,s}}} = WeaponModsData.MODS 各槽位数据
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
	_arm_cam = cam
	_arm_focus_pos = _arm_cam_base
	_arm_focus_target = Vector3(0, -0.02, -0.2)
	_arm_zoom = 2.6
	var l1 := DirectionalLight3D.new()
	l1.rotation_degrees = Vector3(-50, -35, 0)
	l1.light_energy = 1.1
	vp.add_child(l1)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(15, 50, 0)
	l2.light_energy = 0.45
	vp.add_child(l2)
	# ---- 改枪台(浅色背墙 + 浅木台面 + 环境光,黑枪在深色 UI 上也能看清) ----
	var arm_env := WorldEnvironment.new()
	var arm_e := Environment.new()
	arm_e.background_mode = Environment.BG_COLOR
	arm_e.background_color = Color(0.62, 0.66, 0.72)
	arm_e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	arm_e.ambient_light_color = Color(0.72, 0.78, 0.86)
	arm_e.ambient_light_energy = 1.1
	arm_env.environment = arm_e
	vp.add_child(arm_env)
	var _mk_arm_mat := func(c: Color, rough: float, metal: float) -> StandardMaterial3D:
		var mm := StandardMaterial3D.new()
		mm.albedo_color = c
		mm.roughness = rough
		mm.metallic = metal
		return mm
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(3.2, 2.4, 0.06)
	wall.mesh = wm
	wall.material_override = _mk_arm_mat.call(Color(0.62, 0.66, 0.72), 0.92, 0.0)
	wall.position = Vector3(0, 0.25, -1.75)
	vp.add_child(wall)
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.1, 0.09, 1.2)
	table.mesh = tm
	table.material_override = _mk_arm_mat.call(Color(0.72, 0.63, 0.46), 0.72, 0.05)
	table.position = Vector3(0, -0.58, -0.3)
	vp.add_child(table)
	var trim := MeshInstance3D.new()
	var trim_m := BoxMesh.new()
	trim_m.size = Vector3(2.1, 0.035, 0.05)
	trim.mesh = trim_m
	trim.material_override = _mk_arm_mat.call(Color(0.78, 0.82, 0.86), 0.35, 0.75)
	trim.position = Vector3(0, -0.51, -0.3)
	vp.add_child(trim)
	_arm_pivot = Node3D.new()
	vp.add_child(_arm_pivot)
	# ---- 右:槽位面板 ----
	var right_panel := UiTheme.make_panel(0.7)
	right_panel.custom_minimum_size = Vector2(470, 0)
	body.add_child(right_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right_panel.add_child(rv)
	rv.add_child(UiTheme.make_label("性能总览 · 安装前 → 安装后", 14, UiTheme.PRIMARY))
	_arm_stats = VBoxContainer.new()
	_arm_stats.add_theme_constant_override("separation", 4)
	_arm_stats.custom_minimum_size = Vector2(0, 172)
	rv.add_child(_arm_stats)
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


## 配件切换时的平滑视觉反馈(小缩放脉冲,不瞬跳)
func _armory_pulse_view() -> void:
	if _arm_pivot == null:
		return
	_arm_pivot.scale = Vector3(0.92, 0.92, 0.92)
	var tw := _arm_pivot.create_tween()
	tw.tween_property(_arm_pivot, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
		_arm_zoom = clampf(_arm_zoom * 0.9, 1.5, 4.2)
		_armory_apply_focus(_arm_open_slot)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
		_arm_zoom = clampf(_arm_zoom * 1.11, 1.5, 4.2)
		_armory_apply_focus(_arm_open_slot)
	elif ev is InputEventMouseMotion and _arm_dragging:
		_arm_yaw += ev.relative.x * 0.01
		_arm_pitch = clampf(_arm_pitch + ev.relative.y * 0.008, -1.2, 1.2)
		_arm_pivot.rotation = Vector3(_arm_pitch, _arm_yaw, 0)


## 槽位聚焦镜头:选择不同改装部位时平滑移动/缩放 3D 预览相机
func _armory_apply_focus(slot: String) -> void:
	var targets := {
		"optic": Vector3(0.0, 0.06, -0.10),
		"muzzle": Vector3(0.0, 0.03, -0.72),
		"barrel": Vector3(0.0, 0.03, -0.48),
		"grip": Vector3(0.0, -0.04, -0.36),
		"mag": Vector3(0.0, -0.10, -0.06),
		"stock": Vector3(0.0, 0.02, 0.22),
		"trigger": Vector3(0.0, -0.05, 0.02),
		"laser": Vector3(0.0, -0.04, -0.36),
	}
	_arm_focus_target = targets.get(slot, Vector3(0.0, -0.02, -0.2))
	var dir := Vector3(0.14, 0.24, 1.0).normalized()
	_arm_focus_pos = _arm_focus_target + dir * _arm_zoom


## 性能总览:核心五项(伤害/射程/稳定/操控/精准),前后两段细条对比。
func _armory_refresh_stats() -> void:
	if _arm_stats == null:
		return
	for c in _arm_stats.get_children():
		_arm_stats.remove_child(c)
		c.queue_free()
	if _arm_weapon == "" or not WeaponsData.W().has(_arm_weapon):
		return
	var w = WeaponsData.W()[_arm_weapon]
	var scr := _wmd_script()
	var before: Dictionary = {}
	var after: Dictionary = {}
	if scr != null and _wmd_methods().has("total_effects") and _wmd_methods().has("defaults"):
		var dft = scr.call("defaults", _arm_weapon)
		if dft is Dictionary:
			before = scr.call("total_effects", dft)
		after = scr.call("total_effects", _arm_cfg)
	var def_dmg: float = float(w.damage)
	var def_rng: float = float(w.rng[1])
	var rows := [
		["伤害", def_dmg * float(after.get("dmg_mult", 1.0)), def_dmg * float(before.get("dmg_mult", 1.0)), 120.0],
		["射程", def_rng, def_rng, 320.0],
		["稳定", (1.0 - float(after.get("recoil_mult", 1.0))) * 0.5 + (1.0 - float(after.get("recoil_pitch_mult", 1.0))) * 0.5, (1.0 - float(before.get("recoil_mult", 1.0))) * 0.5 + (1.0 - float(before.get("recoil_pitch_mult", 1.0))) * 0.5, 1.0],
		["操控", (1.0 / maxf(float(after.get("ads_speed_mult", 1.0)), 0.2) + float(after.get("mobility_mult", 1.0))) * 0.5, (1.0 / maxf(float(before.get("ads_speed_mult", 1.0)), 0.2) + float(before.get("mobility_mult", 1.0))) * 0.5, 1.4],
		["精准", (2.0 - float(after.get("spread_mult", 1.0)) - float(after.get("hip_spread_mult", 1.0)) * 0.4) * 0.5, (2.0 - float(before.get("spread_mult", 1.0)) - float(before.get("hip_spread_mult", 1.0)) * 0.4) * 0.5, 1.0],
	]
	for row in rows:
		var label: String = row[0]
		var av: float = float(row[1])
		var bv: float = float(row[2])
		var mx: float = float(row[3])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var ll := UiTheme.make_label(label, 11, UiTheme.TXT_DIM)
		ll.custom_minimum_size = Vector2(34, 0)
		line.add_child(ll)
		var bar_bg := PanelContainer.new()
		bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_bg.custom_minimum_size = Vector2(0, 12)
		bar_bg.add_theme_stylebox_override("panel", UiTheme.stylebox(Color(0.08, 0.1, 0.12, 0.9), Color(0.25, 0.32, 0.4, 0.4), 1, 1, 4))
		var bars := Control.new()
		bar_bg.add_child(bars)
		var bbar := ColorRect.new()
		bbar.color = Color(0.45, 0.55, 0.62, 0.55)
		bbar.position = Vector2(1, 2)
		bbar.size = Vector2(maxf((bar_bg.size.x - 4.0) * clampf(bv / mx, 0.0, 1.0), 1.0), 6.0)
		bars.add_child(bbar)
		var abar := ColorRect.new()
		abar.color = UiTheme.PRIMARY
		abar.position = Vector2(1, 1)
		abar.size = Vector2(maxf((bar_bg.size.x - 4.0) * clampf(av / mx, 0.0, 1.0), 1.0), 6.0)
		bars.add_child(abar)
		bar_bg.resized.connect(func():
			bbar.size.x = maxf((bar_bg.size.x - 4.0) * clampf(bv / mx, 0.0, 1.0), 1.0)
			abar.size.x = maxf((bar_bg.size.x - 4.0) * clampf(av / mx, 0.0, 1.0), 1.0))
		line.add_child(bar_bg)
		_arm_stats.add_child(line)


## 槽位面板:5 槽竖排,行=槽名+当前件+属性摘要;点击展开可选件(is_compatible 过滤)
func _armory_refresh_slots() -> void:
	for c in _arm_slots.get_children():
		_arm_slots.remove_child(c)
		c.queue_free()
	# 按武器种类动态显示可用槽位(手枪/霰弹枪等结构约束,不支持的槽位隐藏)
	var avail: Array = []
	var scr := _wmd_script()
	if _mod_ready and scr != null and _wmd_methods().has("weapon_slots"):
		var ws = scr.call("weapon_slots", _arm_weapon)
		if ws is Array:
			avail = ws
	for slot in ARM_SLOT_CN:
		if not avail.is_empty() and not avail.has(slot):
			continue
		_arm_slots.add_child(_armory_slot_row(slot))
	_armory_apply_focus(_arm_open_slot)
	_armory_refresh_stats()


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
			_armory_rebuild_view()
			_armory_pulse_view())
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
		"reload_mult", "recoil_mult", "recoil_pitch_mult", "recoil_yaw_mult", "hip_spread_mult", "spread_mult", "ads_speed_mult", "aim_stability":
			var p1 := (1.0 - float(val)) * 100.0
			return (green if p1 >= 0.0 else red) + cn + " " + ("+" if p1 >= 0.0 else "-") + ("%.0f%%" % absf(p1)) + "[/color]"
		"fire_rate_mult", "dmg_mult", "mobility_mult":
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
		var mid2 := _armory_std_mod(slot)
		if mid2 == "":
			continue
		if scr != null and _wmd_methods().has("is_compatible"):
			if not bool(scr.call("is_compatible", wid, slot, mid2)):
				continue
		cfg[slot] = mid2
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


## 改装数据初始化:直接取 WeaponModsData.MODS 各槽位数据(MODS 五槽齐全:muzzle/mag/grip/trigger/optic)
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
		bar.custom_minimum_size = Vector2(38, maxi(14, int(float(r[1]) / 2.0)))
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

