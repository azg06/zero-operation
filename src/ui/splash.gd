extends Control
## 零度行动启动动画:全屏深色底 + 大标题"零度行动"淡入/轻微缩放,
## 金色分割线展开 + 副标渐显,停留后整体淡出并切换主菜单场景。
## 命令行带参数(测试/验证模式)时跳过动画直接进主场景。

const MAIN_SCENE := "res://scenes/main.tscn"
const FONT_PATH := "res://fonts/NotoSansSC.ttf"

const FADE_IN := 0.8
const HOLD := 1.4
const FADE_OUT := 0.6

var _t := 0.0
var _phase := 0            # 0=淡入 1=停留 2=淡出
var _done := false
var _font: Font
var _title: Label
var _sub: Label
var _hint: Label
var _divider: ColorRect


func _ready() -> void:
	print("[PERF] splash._ready 于 %.2fs" % (Time.get_ticks_msec() / 1000.0))
	if not OS.get_cmdline_user_args().is_empty():
		_go_main()
		return
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#0B0F14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_font = load(FONT_PATH)
	_title = _make_label("零度行动", 240, Color("#EDE7D6"))
	_title.size = Vector2(1300, 360)
	_title.position = Vector2(310, 330)
	_title.pivot_offset = _title.size / 2.0
	add_child(_title)
	_divider = ColorRect.new()
	_divider.color = Color("#C9A227")
	_divider.size = Vector2(640, 4)
	_divider.position = Vector2(640, 700)
	_divider.pivot_offset = _divider.size / 2.0
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider)
	_sub = _make_label("O P E R A T I O N   Z E R O", 40, Color("#8E99A5"))
	_sub.size = Vector2(900, 70)
	_sub.position = Vector2(510, 720)
	add_child(_sub)
	_hint = _make_label("点击任意处进入", 24, Color("#55606C"))
	_hint.size = Vector2(500, 60)
	_hint.position = Vector2(710, 940)
	add_child(_hint)
	_title.modulate.a = 0.0
	_divider.scale.x = 0.0
	_sub.modulate.a = 0.0
	_hint.modulate.a = 0.0


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	match _phase:
		0:
			var k := clampf(_t / FADE_IN, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - k, 3.0)
			_title.modulate.a = eased
			_title.scale = Vector2.ONE * lerpf(1.08, 1.0, eased)
			_divider.scale.x = eased
			_sub.modulate.a = clampf((_t - 0.25) / 0.55, 0.0, 1.0)
			_hint.modulate.a = clampf((_t - 0.45) / 0.35, 0.0, 1.0)
			if _t >= FADE_IN:
				_phase = 1
				_t = 0.0
		1:
			_title.scale = Vector2.ONE * (1.0 + 0.006 * sin(_t * 2.2))
			if _t >= HOLD:
				_phase = 2
				_t = 0.0
		2:
			var a := 1.0 - clampf(_t / FADE_OUT, 0.0, 1.0)
			_title.modulate.a = a
			_divider.modulate.a = a
			_sub.modulate.a = a
			_hint.modulate.a = a
			if _t >= FADE_OUT:
				_go_main()


## 任意按键/鼠标/手柄按钮可跳过动画
func _unhandled_input(event: InputEvent) -> void:
	if _done or _phase == 2:
		return
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton:
		_phase = 2
		_t = 0.0


func _go_main() -> void:
	if _done:
		return
	_done = true
	# 延迟切场景:change_scene_to_file 会 remove_child 当前节点,若在 _ready 阶段
	# (树仍在挂载子节点)直接调用会报 "Parent node is busy adding/removing children"
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)

