extends Node
## 游戏内实际截图(真实渲染器开窗口):
##   godot --path . --script res://tools/game_shot.gd -- <mode> <id> [id...]
## mode:
##   inspect  武器检视位(右侧 45° 俯视,看清弹箱/托盘/整枪轮廓)
##   ads      ADS 第一人称眼位
##   reload   换弹动画自动推进,受弹机盖开到一半时截图(看托盘机械结构)
## 输出:models_probe/game_<mode>_<id>.png

const WM = preload("res://src/models/weapon_models.gd")
const WD = preload("res://src/data/weapons_data.gd")

const OUT_DIR := "E:/工作目录2/models_probe"

var mode := "inspect"
var ids: Array = ["m249"]
var idx := 0
var frames := 0
var stage := 0            # 多子镜头计数
var weapon: Node3D = null
var gun = null
var cam: Camera3D = null
var shots := 0
var reload_started := false


func _ready() -> void:
	# 关键:_ready 期间 root 正在"busy setting up children",此刻 add_child
	# 全部静默失败(相机/武器/灯光都没进树,截图全灰) —— 必须延迟一帧再建场景。
	_setup.call_deferred()


func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		mode = args[0]
	if args.size() >= 2:
		ids = args.slice(1)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.20, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	get_tree().root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.1
	get_tree().root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_energy = 0.4
	get_tree().root.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.02
	get_tree().root.add_child(cam)
	cam.make_current()
	# 相机跟随补光:不管相机怎么摆,武器受光面都亮
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 30, 0)
	key.light_energy = 1.3
	get_tree().root.add_child(key)
	var fill2 := DirectionalLight3D.new()
	fill2.rotation_degrees = Vector3(-15, 160, 0)
	fill2.light_energy = 0.5
	get_tree().root.add_child(fill2)
	# Gun.update 的贴墙检测用 G.camera —— SceneTree 脚本模式下塞桩
	var g_node := get_tree().root.get_node_or_null("/root/G")
	if g_node != null:
		g_node.camera = cam
		if g_node.effects == null:
			var fx: Node3D = load("res://src/fx/effects.gd").new()
			get_tree().root.add_child(fx)
			g_node.effects = fx
			fx.position = Vector3(0, -50, 0)   # 特效池初始化在原点,挪远避免包住相机
	print("GAME_SHOT mode=%s ids=%s" % [mode, ", ".join(PackedStringArray(ids))])
	_next()


func _next() -> void:
	if weapon != null:
		get_tree().root.remove_child(weapon)
		weapon.free()
		weapon = null
		gun = null
	if idx >= ids.size():
		print("ALL_DONE %d 张" % shots)
		get_tree().quit()
		return
	var id := String(ids[idx])
	# 诊断:-- 后第一个参数若带 hide: 前缀则隐藏对应节点(如 hide:MergedStatic)
	var hide_name := ""
	print("[parse] raw id=", id)
	if ":" in id:
		var pp := id.split(":")
		hide_name = pp[0]   # 格式:要隐藏的节点名:武器id
		id = pp[1]
	# 改装验证:武器 id 带 @mod 后缀(如 m4@opt_reddot / m4@laser_flash),
	# 按前缀自动归槽:opt_→optic laser_→laser grip_→grip stock_→stock mag_→mag
	var mod_optic := ""
	var mods := {}
	if "@" in id:
		var aa := id.split("@")
		id = aa[0]
		mod_optic = aa[1]
		if mod_optic.begins_with("opt_"):
			mods = {"optic": mod_optic}
		elif mod_optic.begins_with("laser_"):
			mods = {"laser": mod_optic}
		elif mod_optic.begins_with("grip_"):
			mods = {"grip": mod_optic}
		elif mod_optic.begins_with("stock_"):
			mods = {"stock": mod_optic}
		elif mod_optic.begins_with("mag_"):
			mods = {"mag": mod_optic}
	var defs: Dictionary = WD.build_weapons()
	var def = defs.get(id)
	# 检视/换弹镜头不带手:前臂筒(olive 袖子)从这个相机会横穿整个画面,
	# 挡住弹箱/托盘 —— 那是第一人称持枪姿势的构件,检视视角不需要
	weapon = WM.build(id, mode == "ads", mods)
	get_tree().root.add_child(weapon)
	if hide_name != "":
		var hn: Node = _find_node(weapon, hide_name)
		print("[find] ", hide_name, " -> ", hn)
		if hn != null:
			hn.visible = false
			print("HIDDEN ", hide_name)
	reload_started = false
	match mode:
		"ads":
			var sy: float = 0.108 if def == null else def.sight_y
			# 开镜机位与游戏一致:武器根置于 (0, -sight_y, ads_z)
			var az: float = -0.22 if def == null else float(def.ads_z)
			weapon.position = Vector3(0, -sy, az)
		"inspect":
			weapon.position = Vector3.ZERO
			# 机位按枪长自适应:AABB 长度 × 0.85(手枪 0.25m→近机位,GL/RPG 0.7m→拉远)
			var aabb := _weapon_span(weapon)
			var d: float = maxf(0.40, aabb * 0.85)
			cam.look_at_from_position(Vector3(-d * 0.62, d * 0.30, d * 0.66),
				Vector3(0, 0.0, -0.02), Vector3.UP)
		"reload":
			weapon.position = Vector3(0, -0.04, -0.30)
			weapon.rotation_degrees = Vector3(0, 18, 0)
			# 俯视角避开前臂筒(带手构建的臂筒从握把伸向左上,侧面机会被包住全灰)
			cam.look_at_from_position(Vector3(-0.28, 0.62, 0.28), Vector3(0, 0.03, -0.14), Vector3.UP)
	frames = 0
	stage = 0


func _process(_delta: float) -> void:
	frames += 1
	match mode:
		"ads", "inspect":
			if frames == 6:
				var nm := String(ids[idx]).replace(":", "_")
				_snap("%s_%s" % [mode, nm])
				idx += 1
				_next()
		"reload":
			var id := String(ids[idx])
			if gun == null:
				gun = weapon.get_meta("gun") if weapon.has_meta("gun") else null
			# 找到武器根挂的 Gun 实例不可行(build 只返回节点) —— 直接构造独立 Gun 驱动
			if not reload_started and frames == 3:
				_start_reload()
			if reload_started and gun != null:
				gun.update(1.0 / 60.0)
				# 换弹姿态会持续移动武器组(reload_pose 叠加) —— 每帧把相机重新对准
				if weapon != null and weapon.is_inside_tree():
					cam.look_at(weapon.global_transform.origin + Vector3(0, 0.03, 0), Vector3.UP)
				var ctl = gun.reload_ctl
				if ctl != null and ctl.active and ctl.cover != null:
					# 受弹机盖开到一半:截一张
					var ang := absf(ctl.cover.rotation.x - ctl.cover_base.x)
					if ang > 0.35 and stage == 0:
						stage = 1
						_snap("reload_cover_%s" % id)
					if ang > 0.7 and stage == 1:
						stage = 2
						_snap("reload_open_%s" % id)
				if ctl == null or not ctl.active:
					if stage < 3:
						stage = 3
						_snap("reload_end_%s" % id)
					idx += 1
					_next()
			if frames > 900:
				idx += 1
				_next()


func _start_reload() -> void:
	# 独立 Gun 实例驱动换弹(武器节点由 Gun 内部 build 得来 —— 这里直接再造一把)
	var id := String(ids[idx])
	gun = load("res://src/player/gun.gd").new(id, null)
	gun.equipped = true
	gun.player = load("res://src/player/player_stub.gd").new() if ResourceLoader.exists("res://src/player/player_stub.gd") else null
	if gun.player == null:
		# 内联桩
		gun.player = _make_stub()
	gun.ammo = 0   # 空仓 → 触发开盖检查动作
	# 先移除旧展示武器,再挂 Gun 组(顺序反了会报 already has parent)
	get_tree().root.remove_child(weapon)
	weapon.free()
	weapon = gun.group
	get_tree().root.add_child(weapon)
	# 隐藏前臂筒(截图是看托盘/弹链的,臂筒会包住相机造成全灰帧)
	for arm_key in ["right_arm", "left_arm"]:
		if weapon.has_meta(arm_key):
			(weapon.get_meta(arm_key) as Node3D).visible = false
	weapon.position = Vector3(0, -0.04, -0.30)
	weapon.rotation_degrees = Vector3(0, 18, 0)
	# 场景重建后相机可能被移出树(reload_end 诊断实锤 in_tree=false),强制重挂并对准
	if not cam.is_inside_tree():
		get_tree().root.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(-0.28, 0.62, 0.28), Vector3(0, 0.03, -0.14), Vector3.UP)
	if gun.reload_ctl != null:
		gun.reload_ctl.start()
	reload_started = true


class PlayerStub:
	## Gun.update 需要的 player 属性(鸭子类型,必须显式声明)
	var vel := Vector3.ZERO
	var pos := Vector3.ZERO
	var on_ground := true
	var crouched := false
	var prone := false
	var slide_t := 0.0
	var sprint_amount := 0.0
	var suppression := 0.0
	var look_vel_x := 0.0
	var look_vel_y := 0.0
	var cam_kick_pitch := 0.0
	var cam_kick_yaw := 0.0
	var recoil_pitch := 0.0
	var recoil_yaw := 0.0


func _make_stub() -> RefCounted:
	return PlayerStub.new()


func _find_node(n: Node, target: String) -> Node:
	if String(n.name) == target:
		return n
	for c in n.get_children():
		var r := _find_node(c, target)
		if r != null:
			return r
	return null


func _weapon_span(w: Node3D) -> float:
	# 遍历 MeshInstance AABB 顶点世界包络,返回 z 向跨度(枪长)
	var mn := 1e9
	var mx := -1e9
	var stack: Array = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
			mn = minf(mn, aabb.position.z)
			mx = maxf(mx, aabb.position.z + aabb.size.z)
		for c in n.get_children():
			stack.append(c)
	return maxf(mx - mn, 0.2)


func _snap(tag: String) -> void:
	if cam != null:
		print("  [diag] cam.global=", cam.global_transform.origin,
			" fwd=", -cam.global_transform.basis.z,
			" in_tree=", cam.is_inside_tree(), " current=", cam.is_current())
	if weapon != null:
		print("  [diag] weapon.global=", weapon.global_transform.origin,
			" visible=", weapon.visible, " in_tree=", weapon.is_inside_tree())
	var img := get_tree().root.get_texture().get_image()
	if img == null or img.is_empty():
		print("SHOT_FAIL ", tag)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/game_%s.png" % [OUT_DIR, tag]
	img.save_png(path)
	shots += 1
	print("SHOT %-22s -> %s" % [tag, path])
