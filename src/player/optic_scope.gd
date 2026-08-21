class_name OpticScopeSystem extends Node
## 现代 FPS 高倍率狙击镜 PIP 系统。
## 架构:
##   主相机始终保持正常 FOV(不再做全屏数字缩放);
##   开镜后启用一个与主世界共享 World3D 的 SubViewport + 独立 OpticScope 相机,
##   以 def.zoom_fov(12~14°)渲染镜内视野,再用 CanvasLayer 3 的圆形着色器
##   把该 Render Target 画在狙击镜目镜的屏幕空间投影内。
##   镜筒/枪身/3D 分划仍由 vm_camera 层正常渲染并跟随枪械运动,因此:
##   枪不隐藏、准星与瞄具绑定、镜内镜外视角随同一组 Camera/Weapon Motion 同步。
##
## 性能:只有高倍率镜开镜期间才额外渲染一次 640² 的场景;关镜时 Render Target
## 直接 DISABLED,不重复渲染场景。低倍率镜/红点/全息仍走原有全屏 ADS 流程。

const SCOPE_LAYER := 3          # 主世界之上、VM 层(4)/FXAA/电影后期之下
const VP_SIZE := 640            # 镜内渲染目标边长(圆形视野,640² 足够)
const SCOPE_LAYER_MASK := 1     # 镜内相机只渲染 layer 1(玩家第一人称身体在 layer 2)

var layer: CanvasLayer = null
var rect: ColorRect = null
var mat: ShaderMaterial = null
var vp: SubViewport = null
var cam: Camera3D = null

var scope_basis := Basis.IDENTITY       # 本帧镜内相机方向(枪械+相机运动合成)
var active := false                     # 当前是否有有效高倍镜 ADS
var active_amount := 0.0                # 平滑后的启用量(Gun.try_fire 使用)
var aim_pos := Vector3.ZERO
var debug_center := Vector2.ZERO        # QA:最近一帧镜片屏幕投影中心
var debug_radius := 0.0                 # QA:最近一帧镜片屏幕投影半径
var lens_half_px := Vector2.ZERO        # 镜片屏幕半宽/半高(与 PIP 着色器采样口径一致)
var lens_fov_deg := 0.0                 # 镜内相机垂直 FOV(角度→像素换算基准)


func _ready() -> void:
	# ---- 镜内 Render Target(共享主世界,只多渲染一次,不做独立世界) ----
	vp = SubViewport.new()
	vp.name = "OpticScopeViewport"
	vp.own_world_3d = false
	vp.transparent_bg = false
	vp.size = Vector2i(VP_SIZE, VP_SIZE)
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.handle_input_locally = false
	add_child(vp)

	cam = Camera3D.new()
	cam.name = "OpticScopeCamera"
	cam.current = true
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 900.0
	cam.cull_mask = SCOPE_LAYER_MASK
	vp.add_child(cam)

	# ---- 圆形镜片合成层(透明背景,不遮挡镜外主相机画面) ----
	layer = CanvasLayer.new()
	layer.name = "OpticScopeLayer"
	layer.layer = SCOPE_LAYER
	layer.visible = false
	add_child(layer)

	rect = ColorRect.new()
	rect.name = "OpticScopeRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

	mat = ShaderMaterial.new()
	mat.shader = load("res://src/fx/scope_pip.gdshader")
	rect.material = mat
	mat.set_shader_parameter("scope_tex", vp.get_texture())


## 关镜/无有效狙击镜时彻底停止第二场景渲染
func _set_rendering(on: bool) -> void:
	if on:
		if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if not layer.visible:
			layer.visible = true
			rect.visible = true
	else:
		if layer.visible:
			layer.visible = false
			rect.visible = false
		if vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		active = false
		lens_fov_deg = 0.0
		lens_half_px = Vector2.ZERO


## 当前枪械的镜片锚点;无则返回 null
func _scope_eye_for(gun) -> Node3D:
	if gun == null or gun.group == null or not is_instance_valid(gun.group):
		return null
	if not gun.group.has_meta("scope_eye"):
		return null
	var eye: Node3D = gun.group.get_meta("scope_eye")
	if eye == null or not is_instance_valid(eye) or not eye.is_inside_tree():
		return null
	return eye


func _process(dt: float) -> void:
	if G.player == null or not G.player.alive or G.camera == null:
		_set_rendering(false)
		active_amount = Utils.damp(active_amount, 0.0, 14.0, dt)
		return

	var gun = G.player.gun()
	var want: bool = false
	if gun != null and gun.equipped and gun.scope_sight() and gun.ads_amount > 0.015:
		want = _scope_eye_for(gun) != null and gun.group.visible \
			and gun.group.is_visible_in_tree()

	if not want:
		_set_rendering(false)
		active_amount = Utils.damp(active_amount, 0.0, 14.0, dt)
		return

	# 启用第二场景渲染(仅此期间)
	active = true
	_set_rendering(true)
	active_amount = Utils.damp(active_amount, 1.0, 14.0, dt)

	var eye := _scope_eye_for(gun)
	if eye == null:
		_set_rendering(false)
		return
	var vm_cam: Camera3D = G.vm_camera
	if vm_cam == null:
		_set_rendering(false)
		return
	var eye_global: Vector3 = eye.global_position
	# 镜内相机轴线必须精确穿过目镜/分划中心:以 vm_camera 投影中心为基准,
	# 用“主相机 → 目镜中心”的真实视线构建镜内相机朝向。
	# 注意 eye_global 已在 vm_camera 世界内,而 vm_camera.basis 已同步为主相机
	# basis,所以 eye_global.normalized() 就是主世界中的视线方向;再乘 main_basis
	# 会双重旋转,导致镜内画面不是正前方且不随鼠标上下移动。
	var main_basis: Basis = G.camera.global_transform.basis.orthonormalized()
	var fwd := eye_global.normalized()
	var up := main_basis.y
	var z := -fwd
	var x := up.cross(z)
	if x.length() < 0.001:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	scope_basis = Basis(x, y, z).orthonormalized()
	aim_pos = G.camera.global_position
	# 必须写 global_transform:SubViewport 共享主世界时,镜内相机是世界中的
	# 真实相机,不能只写相对 SubViewport 节点的局部 position/basis。
	cam.global_transform = Transform3D(scope_basis, aim_pos)

	# 镜内 FOV:基础 FOV → 瞄具倍率 FOV(4×/6×/8×/12× 由数据表 zoom_fov 决定),
	# 与 ADS 曲线同步平滑,不碰主相机 FOV。
	var ads := clampf(gun.ads_amount, 0.0, 1.0)
	var scope_k := smoothstep(0.18, 0.95, ads)
	# 从当前主相机 FOV(含镜外轻微缩放)过渡到镜内倍率 FOV,保证开关镜顺滑。
	var base_fov := G.camera.fov
	cam.fov = lerpf(base_fov, gun.scope_fov(), scope_k)

	# ---- 镜片屏幕空间投影(与 vm_camera 层中真实镜筒/镜片逐帧对齐) ----
	var center: Vector2 = vm_cam.unproject_position(eye_global)
	var radius: float = float(gun.group.get_meta("scope_eye_radius", 0.024))
	radius *= maxf(gun.group.scale.x, gun.group.scale.y)
	var eye_basis: Basis = eye.global_transform.basis.orthonormalized()
	var px_r: Vector2 = vm_cam.unproject_position(eye_global + eye_basis.x * radius)
	var px_u: Vector2 = vm_cam.unproject_position(eye_global + eye_basis.y * radius)
	var half_w := center.distance_to(px_r)
	var half_h := center.distance_to(px_u)
	var radius_px := maxf(half_w, half_h)
	# 略微外扩,让镜片着色器与 3D 镜筒实体边缘重叠,消除接缝。
	half_w *= 1.055
	half_h *= 1.055
	radius_px *= 1.055
	# vm_camera.unproject_position 返回 vm_viewport 逻辑像素;着色器使用根视口
	# UV × 逻辑分辨率,因此统一换算到根视口逻辑坐标,窗口物理缩放/DPI 不会造成偏移。
	var root_vp := get_viewport()
	var vm_size: Vector2 = Vector2(G.vm_viewport.get_visible_rect().size)
	var root_size: Vector2 = Vector2(root_vp.get_visible_rect().size)
	var sx := root_size.x / maxf(vm_size.x, 1.0)
	var sy := root_size.y / maxf(vm_size.y, 1.0)
	center = Vector2(center.x * sx, center.y * sy)
	radius_px *= maxf(sx, sy)
	var center_uv := Vector2(center.x / maxf(root_size.x, 1.0), center.y / maxf(root_size.y, 1.0))

	var show := smoothstep(0.22, 0.45, ads)
	debug_center = center
	debug_radius = maxf(radius_px, 2.0)
	# 供 HUD 绘制镜内分划(火箭筒弹道等高线)换算角度→像素:
	# 取与着色器同一口径的镜片半宽/半高与镜内 FOV,标尺才能与镜内画面严格对齐。
	lens_half_px = Vector2(half_w, half_h) if gun.id == "rpg" else Vector2(debug_radius, debug_radius)
	lens_fov_deg = cam.fov
	mat.set_shader_parameter("center_uv", center_uv)
	mat.set_shader_parameter("screen_size", root_size)
	mat.set_shader_parameter("radius_px", debug_radius)
	# 毒刺 CLU 使用方形/矩形镜片;狙击镜保持圆形
	mat.set_shader_parameter("rect_mode", 1.0 if gun.id == "rpg" else 0.0)
	mat.set_shader_parameter("rect_half_px", Vector2(half_w, half_h))
	# 镜片投影始终固定大小,只做透明度淡入,避免“由小变大/贴图缩放”感
	mat.set_shader_parameter("radius_scale", 1.0)
	mat.set_shader_parameter("alpha", show)
	mat.set_shader_parameter("time", G.time)


## 供枪械射击/索敌等系统读取:满镜时弹道跟随镜内实际视轴,
## 保证 3D 分划中心与子弹落点一致。
func aim_basis() -> Basis:
	if active and active_amount > 0.45:
		return scope_basis
	return G.camera.global_transform.basis


func is_scope_aiming() -> bool:
	return active and active_amount > 0.45


## 镜内“正切→像素”换算系数:屏幕纵向像素偏移 = 该系数 × tan(俯角)。
## PIP 是正切投影,大俯角(火箭筒 holdover 可达 15°+)不能用线性角度近似,
## 否则等高线刻度会明显偏离真实落点。返回 0 表示当前无有效镜内渲染。
func lens_px_per_tan() -> float:
	if not active or lens_fov_deg <= 0.01 or lens_half_px.y <= 1.0:
		return 0.0
	return lens_half_px.y / maxf(tan(deg_to_rad(lens_fov_deg) * 0.5), 0.0001)


## QA 诊断:打印镜内相机/镜头投影状态(供 --test-ads-capture 等验证)
func debug_state() -> String:
	if not active:
		return "scope_inactive"
	var cam_basis := cam.global_transform.basis.orthonormalized()
	var main_basis := G.camera.global_transform.basis.orthonormalized()
	return "scope_active active_amt=%.2f fov=%.1f center=(%.0f,%.0f) radius=%.0f cam_pos=(%.1f,%.1f,%.1f) cam_basis_yaw=%.2f cam_pitch=%.2f main_yaw=%.2f main_pitch=%.2f" % [
		active_amount, cam.fov, debug_center.x, debug_center.y, debug_radius,
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		cam_basis.get_euler().y, cam_basis.get_euler().x,
		main_basis.get_euler().y, main_basis.get_euler().x]


func apply_graphics() -> void:
	if vp != null:
		vp.msaa_3d = Viewport.MSAA_2X
