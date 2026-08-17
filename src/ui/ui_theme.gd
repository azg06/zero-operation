class_name UiTheme
## UI 主题助手(BF2042 风格:黑底 + 青绿主色 + 橙红敌方 + 亮绿友方 + 科技网格)

## ---- 配色规范(旧版,兼容) ----
const PRIMARY := Color(0.0, 0.83, 1.0)      # #00D4FF 青绿主色
const FRIENDLY := Color(0.0, 1.0, 0.53)     # #00FF88 友军/小队亮绿
const ENEMY := Color(1.0, 0.33, 0.0)        # #FF5500 敌方橙红
const WARN := Color(1.0, 0.85, 0.2)         # 争夺/警告黄
const TXT := Color(0.85, 0.92, 0.96)
const TXT_DIM := Color(0.45, 0.55, 0.62)

# ==================== 极简军事数字终端设计系统(战斗 HUD 主用) ====================
# 设计语言:细边框 / 圆角矩形 / 半透明磨砂(20~40%)/ 青绿+白主色 / 敌方橙 / 警告红 / 占领蓝绿
# 不使用厚重金属边框、不发光科幻面板、无高饱和色 —— UI 像漂浮的数字化信息层
const H_CYAN := Color(0.16, 0.78, 0.86)          # 主青绿(柔和,信息主色)
const H_CYAN_DIM := Color(0.16, 0.55, 0.62)      # 暗青绿(次级)
const H_WHITE := Color(0.9, 0.94, 0.97)          # 主白(文字/图标)
const H_GRAY := Color(0.55, 0.6, 0.66)           # 中性灰(未占领/未标记)
const H_GRAY_DIM := Color(0.38, 0.42, 0.47)      # 暗灰(次要文字)
const H_ORANGE := Color(1.0, 0.55, 0.22)         # 敌方橙(信息层2)
const H_RED := Color(0.95, 0.34, 0.28)           # 警告红(信息层3)
const H_TEAL := Color(0.05, 0.62, 0.6)           # 占领蓝绿(蓝绿色)
const H_GREEN := Color(0.35, 0.8, 0.5)           # 友军绿(轻量)
const H_PANEL := Color(0.03, 0.05, 0.07, 0.32)   # 磨砂面板底(32% 半透明)
const H_PANEL_DEEP := Color(0.02, 0.03, 0.05, 0.55)  # 深磨砂(弹窗/横幅)
const H_PANEL_MAP := Color(0.05, 0.06, 0.08, 0.72)   # 小地图深灰磨砂
const H_BORDER := Color(0.65, 0.75, 0.8, 0.4)    # 细白边框
const H_BORDER_SOFT := Color(0.65, 0.75, 0.8, 0.18)  # 极细弱白边(悬浮元素)

## 磨砂悬浮面板:半透明底 + 细边框 + 圆角(信息层容器统一样式)
static func hud_frost(alpha := 0.32, border := H_BORDER, border_w := 1, radius := 4, pad := 10) -> StyleBoxFlat:
	return stylebox(Color(0.03, 0.05, 0.07, alpha), border, border_w, radius, pad)

static var _font: Font = null
static var _theme: Theme = null
static var _mono: Font = null


static func font() -> Font:
	if _font == null:
		# 桌面/Web 统一使用项目打包字体,保证跨平台字形一致
		_font = load("res://fonts/NotoSansSC.ttf") as FontFile
	return _font


## 等宽数字字体(军事 HUD 弹药/血量/计时)
static func mono_font() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "Lucida Console"]
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_mono = f
	return _mono


static func make_mono_label(text: String, font_size := 16, color := TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = theme()
	l.add_theme_font_override("font", mono_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 16
		_theme = t
	return _theme


## 应用主题到控件树根
static func apply(root: Control) -> void:
	root.theme = theme()


## ==================== 统一 UI 动画管理(按钮/面板/页面) ====================
static var _button_tweens: Dictionary = {}
static var _screen_tweens: Dictionary = {}


static func _kill_tween(key: Variant) -> void:
	if _button_tweens.has(key):
		var old: Tween = _button_tweens[key]
		if old != null and old.is_valid():
			old.kill()
		_button_tweens.erase(key)


## 给按钮统一接入 Idle → Hover → Press → Release → Selected/Disabled 动画
## 所有动画都由 Tween 驱动,并且同一按钮重复触发会先 kill 旧 Tween,避免动画打架。
static func animate_button(b: Button) -> void:
	if b == null or b.has_meta("ui_anim_wired"):
		return
	b.set_meta("ui_anim_wired", true)
	b.mouse_entered.connect(func():
		_button_hover(b, true))
	b.mouse_exited.connect(func():
		_button_hover(b, false))
	b.button_down.connect(func():
		_button_press(b, true))
	b.button_up.connect(func():
		_button_press(b, false))
	b.pressed.connect(func():
		pulse_button(b))


static func _button_hover(b: Button, hover: bool) -> void:
	if b == null or not is_instance_valid(b):
		return
	_kill_tween(b)
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	_button_tweens[b] = tw
	tw.tween_property(b, "scale", Vector2(1.035, 1.035) if hover else Vector2.ONE, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _button_press(b: Button, down: bool) -> void:
	if b == null or not is_instance_valid(b):
		return
	_kill_tween(b)
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	_button_tweens[b] = tw
	tw.set_parallel(true)
	tw.tween_property(b, "scale", Vector2(0.95, 0.95) if down else Vector2.ONE, 0.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if down else Tween.EASE_OUT)
	tw.tween_property(b, "position:y", (b.position.y + 1.5) if down else (b.position.y - 1.5), 0.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if down else Tween.EASE_OUT)


## 页面/面板统一淡入淡出 + 轻微缩放过渡
## show=true 会先显示再渐入;show=false 会在动画结束后自动隐藏。
static func fade_screen(c: Control, show: bool, duration := 0.18, on_done: Callable = Callable()) -> void:
	if c == null or not is_instance_valid(c):
		if on_done.is_valid():
			on_done.call()
		return
	if _screen_tweens.has(c):
		var old: Tween = _screen_tweens[c]
		if old != null and old.is_valid():
			old.kill()
	c.pivot_offset = c.size * 0.5
	if show:
		c.visible = true
		c.modulate.a = 0.0
		c.scale = Vector2(0.985, 0.985)
	else:
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
	var tw := c.create_tween()
	_screen_tweens[c] = tw
	if show:
		tw.set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.set_parallel(true)
		tw.tween_property(c, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "scale", Vector2(0.985, 0.985), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func():
			if is_instance_valid(c):
				c.visible = false
				c.modulate.a = 1.0
				c.scale = Vector2.ONE
			if on_done.is_valid():
				on_done.call())


static func stylebox(bg: Color, border: Color = Color.TRANSPARENT, border_w := 0, radius := 4, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


## BF2042 面板样式:深色磨砂 + 青绿描边
static func panel_box(alpha := 0.72, border := PRIMARY) -> StyleBoxFlat:
	return stylebox(Color(0.0, 0.03, 0.05, alpha), Color(border.r, border.g, border.b, 0.55), 1, 3, 12)


static func make_button(text: String, font_size := 16, accent := Color(0.0, 0.1, 0.14, 0.85)) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", stylebox(accent, Color(PRIMARY.r, PRIMARY.g, PRIMARY.b, 0.5), 1, 2))
	b.add_theme_stylebox_override("hover", stylebox(Color(0.0, 0.2, 0.26, 0.92), PRIMARY, 1, 2))
	b.add_theme_stylebox_override("pressed", stylebox(Color(0.0, 0.32, 0.4, 0.98), Color(0.6, 0.95, 1.0), 1, 2))
	b.add_theme_stylebox_override("disabled", stylebox(Color(0.03, 0.04, 0.06, 0.8), Color(0.15, 0.2, 0.24, 0.4), 1, 2))
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", TXT_DIM)
	# 悬停音效 + 统一按钮状态动画(Idle/Hover/Press/Release/Pulse)
	b.mouse_entered.connect(func():
		AudioSys.ui_hover())
	animate_button(b)
	return b


## 按钮按下回弹动画(供手写 Button 复用)
static func pulse_button(b: Button) -> void:
	if not is_instance_valid(b):
		return
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2(0.955, 0.955), 0.045)
	t.tween_property(b, "scale", Vector2.ONE, 0.09)


## 给手写 Button 统一接上悬停音效 + 按下回弹(3A 手感)
static func wire_button(b: Button) -> void:
	b.mouse_entered.connect(func():
		AudioSys.ui_hover())
	animate_button(b)


## 军事化 HUD 面板:半透明深底 + 1px 细边框(战斗 HUD 用)
static func hud_box(alpha := 0.78, border := Color(0.42, 0.52, 0.6, 0.6)) -> StyleBoxFlat:
	return stylebox(Color(0.015, 0.025, 0.04, alpha), border, 1, 3, 10)


## 军事化滑块(设置界面:细轨 + 青绿填充 + 方块把手)
static func style_slider(sl: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.08, 0.1, 0.9)
	track.border_color = Color(0.3, 0.38, 0.45, 0.7)
	track.set_border_width_all(1)
	track.set_corner_radius_all(2)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.0, 0.45, 0.6, 0.95)
	fill.set_corner_radius_all(2)
	var fill_h := StyleBoxFlat.new()
	fill_h.bg_color = Color(0.1, 0.72, 0.9, 1.0)
	fill_h.set_corner_radius_all(2)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.75, 0.92, 0.97, 1.0)
	grab.border_color = Color(0.0, 0.83, 1.0, 0.9)
	grab.set_border_width_all(1)
	grab.set_corner_radius_all(2)
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_h)
	sl.add_theme_stylebox_override("grabber", grab)
	sl.add_theme_stylebox_override("grabber_highlight", grab)
	sl.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 主按钮(部署/开始):青绿填充
static func make_cta(text: String, font_size := 18) -> Button:
	var b := make_button(text, font_size, Color(0.0, 0.42, 0.55, 0.95))
	b.add_theme_stylebox_override("hover", stylebox(Color(0.0, 0.55, 0.7, 0.98), Color(0.7, 1, 1), 1, 2))
	return b


static func make_label(text: String, font_size := 16, color := TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = theme()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_panel(alpha := 0.72) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(alpha))
	return p


## 科技网格背景(细网格线 + 扫描线;attach 到容器上 draw)
class TechGrid extends Control:
	var grid_col := Color(0.0, 0.83, 1.0, 0.05)
	var scan_col := Color(0.0, 0.83, 1.0, 0.03)
	var scan_y := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		scan_y = fmod(scan_y + dt * 40, 1200.0)
		queue_redraw()

	func _draw() -> void:
		var sz := size
		var step := 44.0
		for x in range(0, int(sz.x) + 1, int(step)):
			draw_line(Vector2(x, 0), Vector2(x, sz.y), grid_col, 1)
		for y in range(0, int(sz.y) + 1, int(step)):
			draw_line(Vector2(0, y), Vector2(sz.x, y), grid_col, 1)
		# 扫描线(缓慢下移)
		draw_rect(Rect2(0, scan_y, sz.x, 2), scan_col)
		draw_rect(Rect2(0, scan_y - 60, sz.x, 60), Color(scan_col.r, scan_col.g, scan_col.b, 0.012))


## 战场动态背景(程序化 canvas shader:烟尘 fbm + 军事网格 + 扫描线 + 暗角)
class BattleBg extends Control:
	const SHADER_CODE := """
shader_type canvas_item;

uniform float speed = 0.10;
uniform vec4 smoke_col : source_color = vec4(0.09, 0.16, 0.18, 0.55);
uniform vec4 grid_col : source_color = vec4(0.0, 0.83, 1.0, 0.075);
uniform vec4 base_col : source_color = vec4(0.012, 0.025, 0.04, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}
void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	vec2 p = uv * 2.0 - 1.0;
	p.x += t * 0.3;
	p.y -= t * 0.18;
	float s1 = fbm(p * 1.7 + vec2(4.0, 8.0));
	float s2 = fbm(vec2(p.x * 3.4 - t * 0.35, p.y * 3.4 + t * 0.22 + 2.0));
	float smoke = clamp(s1 * 0.5 + s2 * 0.55 - 0.28, 0.0, 1.0) * smoke_col.a;
	vec3 col = base_col.rgb;
	col += smoke_col.rgb * smoke;
	vec2 g = abs(fract(uv * vec2(48.0, 30.0)) - 0.5);
	float line = smoothstep(0.485, 0.5, max(g.x, g.y));
	col += grid_col.rgb * line * grid_col.a;
	col += grid_col.rgb * (0.5 + 0.5 * sin(uv.y * 900.0 + TIME * 2.0)) * 0.02;
	col += grid_col.rgb * smoothstep(0.495, 0.5, abs(fract(uv.x * 12.0 + t * 0.5) - 0.5)) * 0.05;
	float d = distance(uv, vec2(0.5));
	col *= mix(1.0, 0.5, smoothstep(0.45, 0.98, d));
	COLOR = vec4(col, 1.0);
}
"""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = sh
		material = mat
