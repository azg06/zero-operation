extends SceneTree
## 特效子智能体隔离冒烟测试:不依赖 world_builder.gd(其他子智能体在改)
##
## 时序说明(--script 独立模式):
## autoload 节点在 SceneTree 初始化完成、Main::start 挂载后才注册;
## 在 _init 阶段编译期引用 autoload 标识符(G/GraphicsQuality/AudioSys)会
## "Identifier not found" 编译失败,且此时 load() 引用 autoload 的脚本也会失败。
## → 全部测试体推迟到首帧 process_frame 执行(此时 autoload 已挂载,
##   load() 可正常编译、/root/G 可运行期访问)。

var _pass_all := true
var _e = null  # untyped(Effects 实例):_ready 构建的池成员需运行期动态访问

func _init() -> void:
	process_frame.connect(_run_all)


func _run_all() -> void:
	process_frame.disconnect(_run_all)

	# 1) g.gd 解析 + fx_scale 默认键
	var GScript: GDScript = load("res://src/autoload/g.gd")
	if GScript == null or not GScript.can_instantiate():
		print("FAIL g.gd 无法加载")
		quit(1)
		return
	var g = GScript.new()
	var has_fx_scale: bool = g.settings.has("fx_scale")
	print(("PASS" if has_fx_scale else "FAIL") + " g.gd fx_scale 默认键 = " + str(g.settings.get("fx_scale")))
	_pass_all = _pass_all and has_fx_scale

	# 2) effects.gd 解析
	var EScript: GDScript = load("res://src/fx/effects.gd")
	if EScript == null or not EScript.can_instantiate():
		print("FAIL effects.gd 解析失败")
		quit(1)
		return
	print("PASS effects.gd 解析通过")
	_e = EScript.new()

	# 3) fxaa_test.gdshader 资源可加载(结构校验)
	var sh: Shader = load("res://src/fx/fxaa_test.gdshader")
	print(("PASS" if sh != null else "FAIL") + " fxaa_test.gdshader 加载")
	_pass_all = _pass_all and sh != null
	var sh2: Shader = load("res://src/fx/fxaa.gdshader")
	_pass_all = _pass_all and sh2 != null
	print(("PASS" if sh2 != null else "FAIL") + " fxaa.gdshader 加载")

	# 4) 运行时冒烟:爆炸光源池 + 地形高度缓存 + 材质推断(手动触发不依赖 _ready 的世界部分)
	# root.add_child(e) 即触发 effects.gd _ready()(_build_lights/_build_flashes 已含于其中,
	# 一次性构建) → 严禁再手动重复调用,否则灯池翻倍,断言 n_lights == 8 必失败
	root.add_child(_e)
	var n_lights: int = _e._expl_lights.size()
	print(("PASS" if n_lights == 8 else "FAIL") + " 爆炸光源池数量 = " + str(n_lights))
	_pass_all = _pass_all and n_lights == 8
	for lg in _e._expl_lights:
		(lg as OmniLight3D).light_energy = 70.0
	var picked = _e._expl_light_for(Vector3(1000, 0, 1000))
	print("PASS 光源分配返回 " + str(picked))

	# 5) 光源池衰减释放:能量低于阈值归零
	# (_ready 同步完成后 _expl_lights 已含 8 盏,池非空,index 0 安全)
	var lg0: OmniLight3D = _e._expl_lights[0]
	lg0.light_energy = 0.3
	var picked2 = _e._expl_light_for(Vector3.ZERO)
	print(("PASS" if picked2 == lg0 else "FAIL") + " 低能量灯优先复用")
	_pass_all = _pass_all and picked2 == lg0

	# 6) G autoload 运行时测试:运行期 /root/G 节点访问,不做编译期标识符依赖
	var g_node: Variant = root.get_node_or_null("/root/G")
	if g_node == null:
		print("SKIP 运行时测试(G autoload 不可用)")
		_finish()
		return

	# 高度缓存:模拟 G.ground_h(先清空缓存,再验证同格只求值一次;effects.gd 为 4m 网格:
	# key=floor(x*0.25),x=1.5/1.9 同格共享,x=5.5 落入相邻格重新求值)
	g_node.ground_h = func(x: float, z: float) -> float:
		return sin(x * 0.1) * 0.5 + z * 0.01
	_e._gh_grid.clear()
	_e._gh_owner = Callable()
	var h1: float = _e._ground_h(1.5, 2.5)
	var h2: float = _e._ground_h(1.9, 2.7)
	var h3: float = _e._ground_h(5.5, 5.5)
	print(("PASS" if absf(h1 - h2) < 0.001 and absf(h3 - (sin(0.55) * 0.5 + 0.055)) < 0.001 else "FAIL") + " 4m 网格缓存命中(同格共享) h1=" + str(h1) + " h2=" + str(h2) + " h3=" + str(h3))
	_pass_all = _pass_all and absf(h1 - h2) < 0.001 and absf(h3 - (sin(0.55) * 0.5 + 0.055)) < 0.001

	# 材质推断:假地形贴地 → dirt;高处无盒 → concrete
	g_node.ground_h = func(x: float, z: float) -> float: return 0.0
	var m_dirt: String = _e._material_at(Vector3(5, 0.05, 5), Vector3.UP)
	print(("PASS" if m_dirt == "dirt" else "FAIL") + " 贴地判定 = " + m_dirt)
	_pass_all = _pass_all and m_dirt == "dirt"
	var m_air: String = _e._material_at(Vector3(5, 8.0, 5), Vector3(1, 0, 0))
	print(("PASS" if m_air == "concrete" else "FAIL") + " 空中默认 = " + m_air)
	_pass_all = _pass_all and m_air == "concrete"

	# 几何粗判:矮薄盒 → wood(g.gd colliders 为 Array[AABB],需构造同型数组)
	var utils: GDScript = load("res://src/data/utils.gd")
	var ca: Array[AABB] = []
	ca.append(AABB(Vector3(0, 0, 0), Vector3(2.0, 1.0, 0.3)))
	g_node.colliders = ca
	utils.rebuild_collider_grid()
	var m_wood: String = _e._material_at(Vector3(1.0, 0.31, 0.1), Vector3(0, 0, -1))
	print(("PASS" if m_wood == "wood" else "FAIL") + " 薄壁低矮 → wood = " + m_wood)
	_pass_all = _pass_all and m_wood == "wood"
	# 小紧凑盒 → metal
	ca = []
	ca.append(AABB(Vector3(0, 0, 0), Vector3(0.7, 0.95, 0.7)))
	g_node.colliders = ca
	utils.rebuild_collider_grid()
	var m_metal: String = _e._material_at(Vector3(0.35, 0.98, 0.35), Vector3(0, 1, 0))
	print(("PASS" if m_metal == "metal" else "FAIL") + " 小号紧凑盒 → metal = " + m_metal)
	_pass_all = _pass_all and m_metal == "metal"
	# 高大盒 → concrete
	ca = []
	ca.append(AABB(Vector3(0, 0, 0), Vector3(4.0, 6.0, 3.0)))
	g_node.colliders = ca
	utils.rebuild_collider_grid()
	var m_conc: String = _e._material_at(Vector3(2.0, 6.05, 1.5), Vector3(0, 1, 0))
	print(("PASS" if m_conc == "concrete" else "FAIL") + " 高大实心 → concrete = " + m_conc)
	_pass_all = _pass_all and m_conc == "concrete"

	_finish()


func _finish() -> void:
	print("RESULT: " + ("ALL PASS" if _pass_all else "HAS FAILURES"))
	quit(0 if _pass_all else 1)
