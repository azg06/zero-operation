class_name BattleDeploymentManager extends Node
## 实时 3D 战场部署系统(战地式):死亡后先播倒下动画,镜头再升空,进入高空战术观察与部署。
## - 世界/物理/AI 完全不暂停,只替换主相机为部署观察相机
## - 鼠标释放:左键拖动平移地图(WASD 亦可),点击部署点部署;高度恒定,无滚轮缩放
## - 兵种/武器选择栏与 3D 战场同屏一体(底部装备栏,由 menus 部署屏承载)
## - 流程:死亡 → 倒下动画 → 镜头升空 → 自由观察(世界实时运行)→ 点击部署点 → 镜头飞向目标 → 第一人称重生

const DOWN_DUR := 1.0            # 死亡倒下动画时长(秒)
const RISE_DUR := 2.3            # 升空时长(秒)
const FLY_DUR := 1.15            # 部署飞向目标时长(秒)
const CLICK_DRAG_PX := 7.0       # 拖动阈值:超过视为平移,不触发点击部署
const MIN_ALT := 2.6             # 最低观察高度(米)
const MAX_ALT_K := 0.95          # 最大观察高度 = 地图半宽 × 系数


## ==================== 部署观察摄像机(真 3D 自由镜头,高度恒定) ====================
class DeploymentCamera extends RefCounted:
	var pos := Vector3.ZERO
	var yaw := 0.0
	var pitch := -1.15
	var vel := Vector3.ZERO
	var alt := 90.0               # 离地高度(相机 y = 地表/屋顶 + alt,部署期间恒定)
	var max_alt := 160.0

	func setup(from: Vector3, map_half: float) -> void:
		pos = from
		max_alt = clampf(map_half * MAX_ALT_K, 60.0, 380.0)
		alt = clampf(map_half * 0.68, 45.0, 240.0)

	## 该点可站立的地表高度:建筑屋顶 > 地形(自上而下射线取最近面)
	func floor_h(x: float, z: float) -> float:
		var gh: float = G.ground_h.call(x, z) if G.ground_h.is_valid() else 0.0
		var oy := pos.y + 220.0
		var hit = Utils.raycast_world(Vector3(x, oy, z), Vector3.DOWN, 320.0)
		if hit != null and hit.get("box") is AABB:
			var hy: float = oy - hit["dist"]
			if hy > gh:
				return hy
		return gh

	## 应用位置约束:建筑碰撞 + 边界 + 贴地(恒定高度,绝不穿地形与建筑)
	func clamp_pos(npos: Vector3) -> Vector3:
		npos = Utils.move_collide(npos, 1.5, 1.8)
		npos.x = clampf(npos.x, -G.bounds, G.bounds)
		npos.z = clampf(npos.z, -G.bounds, G.bounds)
		npos.y = floor_h(npos.x, npos.z) + alt
		return npos

	## WASD 平移(速度随高度;高空快速,低空精细)
	func move_wasd(dt: float) -> void:
		var fwd_in := (1 if Input.is_action_pressed("move_forward") else 0) - (1 if Input.is_action_pressed("move_back") else 0)
		var right_in := (1 if Input.is_action_pressed("move_right") else 0) - (1 if Input.is_action_pressed("move_left") else 0)
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var wish := Vector3.ZERO + fwd * fwd_in + right * right_in
		if wish.length_squared() > 0:
			wish = wish.normalized()
		var speed := clampf(alt * 1.05, 9.0, 120.0)
		var accel_k := 5.0 if alt > 20.0 else 8.5
		vel.x = Utils.damp(vel.x, wish.x * speed, accel_k, dt)
		vel.z = Utils.damp(vel.z, wish.z * speed, accel_k, dt)
		pos = clamp_pos(pos + vel * dt)

	## 鼠标拖动平移:按高度换算每像素世界位移(RTS 拖图手感)
	func pan_px(dx: float, dz: float) -> void:
		var world_per_px := alt * 0.0011
		pos = clamp_pos(pos + Vector3(-dx * world_per_px, 0.0, -dz * world_per_px))


## ==================== 战场实时观察者(读取可部署目标与战场状态) ====================
class BattlefieldWorldObserver extends RefCounted:
	var my_team := "us"

	func base_pos() -> Vector3:
		var z: float = (G.world_size - 16.0) if my_team == "ru" else -(G.world_size - 16.0)
		return Vector3(0, G.ground_h.call(0.0, z) if G.ground_h.is_valid() else 0.0, z)

	## 突破模式封锁区判定(与 deploy_map.gd 一致)
	func bt_ok(z: float) -> bool:
		if G.mode != "breakthrough" or G.bt == null:
			return true
		return (z >= G.game.bt_rear_z()) if my_team == "ru" else (z <= G.game.bt_front_z())

	## 危险区域:25m 内有存活敌人(该处队友不可部署)
	func in_danger(b) -> bool:
		for e in G.bots:
			if e == null or not e.alive or e.team == b.team:
				continue
			if b.pos.distance_to(e.pos) < 25.0:
				return true
		return false

	## 收集全部可显示部署目标(每帧调用,数据量小)
	func collect() -> Array:
		var out: Array = []
		var p = G.player
		if p == null:
			return out
		my_team = p.team
		# 1) 固定基地出生点(备用)
		out.append({ "kind": "base", "pos": base_pos(), "label": "基地", "ref": null, "valid": true })
		# 2) 占领点(仅己方/解锁区域可部署)
		for f in G.flags:
			if f == null:
				continue
			var deployable: bool = f.owner_team == my_team and not (G.mode == "breakthrough" and f.zone_locked)
			out.append({
				"kind": "flag", "pos": f.pos, "label": f.id + " 据点", "ref": f,
				"valid": deployable and bt_ok(f.pos.z),
				"state": "mine" if f.owner_team == my_team else ("enemy" if f.owner_team != null else "neutral"),
				"contested": f.contested, "progress": f.progress,
				"locked": G.mode == "breakthrough" and f.zone_locked,
			})
		# 3) 队友(全队显示;仅小队成员可部署,战斗中/濒死/危险区域禁止)
		var sq = G.player_squad
		for b in G.bots:
			if b == null or not b.alive or b.team != my_team:
				continue
			var in_sq: bool = sq != null and (sq["members"] as Array).has(b)
			var downed: bool = b.downed
			var in_veh: bool = b.vehicle != null
			var dng := in_danger(b)
			out.append({
				"kind": "mate", "pos": b.pos, "label": Bot.display_name(b), "ref": b,
				"valid": in_sq and not downed and not in_veh and not dng,
				"squad": in_sq, "downed": downed, "in_vehicle": in_veh, "danger": dng,
			})
		# 4) 重生信标(侦察兵部署物)
		for d in G.deployables:
			if d == null or d["kind"] != "beacon" or d["team"] != my_team or not bt_ok(d["pos"].z):
				continue
			out.append({ "kind": "beacon", "pos": d["pos"], "label": "重生信标", "ref": d, "valid": true })
		# 5) 己方有人驾驶载具(可部署到车旁)
		for v in G.vehicles:
			if v == null or v.dead or v.driver == null or v.driver.team != my_team:
				continue
			out.append({ "kind": "vehicle", "pos": v.pos,
				"label": v.def.get("vehicle_name", "载具"), "ref": v, "valid": true })
		return out

	## 点击部署时的实时复核(防止点位已失效/易主)
	func validate(t: Dictionary) -> bool:
		var p = G.player
		if p == null:
			return false
		my_team = p.team
		match t["kind"]:
			"base":
				return true
			"flag":
				var f = t["ref"]
				return is_instance_valid(f) and f.owner_team == my_team \
					and not f.zone_locked and bt_ok(f.pos.z)
			"mate":
				var b = t["ref"]
				var sq = G.player_squad
				return is_instance_valid(b) and b.alive and b.team == my_team \
					and b.vehicle == null and not b.downed \
					and sq != null and (sq["members"] as Array).has(b) and not in_danger(b)
			"beacon":
				var d = t["ref"]
				return d != null and G.deployables.has(d) and d["kind"] == "beacon" \
					and d["team"] == my_team and bt_ok(d["pos"].z)
			"vehicle":
				var v = t["ref"]
				return is_instance_valid(v) and not v.dead and v.driver != null and v.driver.team == my_team
		return false


## ==================== 管理器状态 ====================
var active := false
var phase := "idle"               # idle | down(倒下动画) | rise | free | fly
var cam := DeploymentCamera.new()
var observer := BattlefieldWorldObserver.new()
var hovered: Dictionary = {}      # 鼠标悬停目标(空字典=无)
var ui_open := false              # 底部装备栏(menus 部署屏)是否已显示
var _entered_from := "death"      # death | match(开局 3D 部署)
var _deploy_target: Dictionary = {}
var _phase_t := 0.0
var _rise_from := Vector3.ZERO
var _rise_to := Vector3.ZERO
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.ZERO
var _fly_pitch0 := -1.15
var _fade_started := false
var _hint_shown := false
var _mouse_down := false
var _press_pos := Vector2.ZERO
var _drag_moved := false
var _death_yaw := 0.0            # 死亡瞬间相机朝向(倒下动画保持)
var _rise_yaw0 := 0.0            # 升空起始朝向(死亡点朝地图中心)
var _base_yaw := 0.0             # 部署"回正"朝向(与开局一致:us=朝己方基地)
var _fog_saved := false          # 部署期间关闭雾景(高空视野清晰),退出恢复
var _fog_env = null
var _fog_enabled := false
var _volfog_enabled := false
var _occl_saved := false         # 部署期间关闭遮挡剔除(城市大楼高空闪动),退出恢复


## ==================== 进入 / 退出 ====================
func enter() -> void:
	if active:
		return
	# 仅征服/突破模式使用实时 3D 部署(战役/TDM/BR 走各自重生流程)
	if G.mode != "conquest" and G.mode != "breakthrough":
		return
	if G.hud == null or G.camera == null:
		return
	active = true
	phase = "down"
	_phase_t = 0.0
	hovered = {}
	_deploy_target = {}
	_fade_started = false
	_hint_shown = false
	ui_open = false
	_mouse_down = false
	_drag_moved = false
	_entered_from = "death"
	var c := G.camera
	_rise_from = c.global_position
	_death_yaw = c.rotation.y
	# 目标观察位:死亡点朝地图中心方向抬升
	var to_c: Vector3 = Vector3.ZERO - _rise_from
	to_c.y = 0
	var dir_c: Vector3 = to_c.normalized() if to_c.length() > 0.1 else Vector3(0, 0, 1)
	var map_half: float = maxf(G.world_size, 60.0)
	var alt: float = clampf(map_half * 0.8, 50.0, 240.0)
	var above := _rise_from + dir_c * map_half * 0.2
	above.y = (G.ground_h.call(above.x, above.z) if G.ground_h.is_valid() else 0.0) + alt
	_rise_to = above
	cam.setup(_rise_from, map_half)
	cam.alt = alt
	# 地图"回正":升空结束后朝向与开局部署一致(us 朝己方基地),拖图方向感与开局相同
	_base_yaw = PI if G.player != null and G.player.team == "ru" else 0.0
	_rise_yaw0 = atan2(-dir_c.x, -dir_c.z)
	cam.yaw = _rise_yaw0
	cam.vel = Vector3.ZERO
	G.input_sys.unlock()          # 部署全程鼠标释放(拖动平移地图)
	G.effects.reset_death_fade()  # 立即清掉死亡黑幕,战场清晰可见
	_setup_view_cleanup(true)
	print("[DEPLOY] 进入实时 3D 战场部署模式 state=", G.state)


## 开局(征服/突破)3D 部署:直接进入战场上空观察(兵种/武器栏同屏一体);返回是否已进入
func enter_match_deploy() -> bool:
	if active:
		_show_ui()
		return true
	if G.mode != "conquest" and G.mode != "breakthrough":
		return false
	if G.hud == null or G.camera == null:
		return false
	active = true
	phase = "free"
	_phase_t = 0.0
	hovered = {}
	_deploy_target = {}
	_fade_started = false
	_hint_shown = false
	ui_open = false
	_mouse_down = false
	_drag_moved = false
	_entered_from = "match"
	# 高空观察位:地图中心上方,朝己方基地方向(地图"回正")
	var map_half: float = maxf(G.world_size, 60.0)
	cam.setup(Vector3.ZERO, map_half)
	var gh: float = G.ground_h.call(0.0, 0.0) if G.ground_h.is_valid() else 0.0
	cam.pos = Vector3(0, gh + cam.alt, 0)
	cam.vel = Vector3.ZERO
	_base_yaw = PI if G.player != null and G.player.team == "ru" else 0.0
	cam.yaw = _base_yaw
	G.input_sys.unlock()          # 部署全程鼠标释放(拖动平移地图)
	G.effects.reset_death_fade()
	_setup_view_cleanup(true)
	_show_ui()
	print("[DEPLOY] 开局 3D 部署模式 state=", G.state)
	return true


func exit() -> void:
	if not active:
		return
	active = false
	phase = "idle"
	hovered = {}
	_deploy_target = {}
	_mouse_down = false
	if ui_open:
		ui_open = false
		if G.menus != null:
			G.menus.hide_deploy()
	if G.hud != null:
		G.hud.set_deployment_overlay(false)
	# 未部署退出(仍死亡 / 仍开局部署屏)则保持鼠标可见;部署成功由 deploy() 接管锁定
	if G.state == "dead" or G.state == "deploy":
		G.input_sys.unlock()
	_setup_view_cleanup(false)   # 恢复雾景与遮挡剔除
	print("[DEPLOY] 退出部署模式")


## 部署期间视野清理:关闭雾景(非城市图高空观察清晰)+ 关闭遮挡剔除(城市大楼高空闪动修复)
## on=true 进入部署时应用;on=false 退出时恢复
func _setup_view_cleanup(on: bool) -> void:
	if on:
		if not _fog_saved and G.world_env != null and G.world_env.environment != null:
			_fog_env = G.world_env.environment
			_fog_enabled = _fog_env.fog_enabled
			_volfog_enabled = _fog_env.volumetric_fog_enabled
			_fog_env.fog_enabled = false
			_fog_env.volumetric_fog_enabled = false
			_fog_saved = true
		if not _occl_saved and G.camera != null:
			RenderingServer.viewport_set_use_occlusion_culling(get_viewport().get_viewport_rid(), false)
			_occl_saved = true
	else:
		if _fog_saved:
			if _fog_env != null and is_instance_valid(_fog_env):
				_fog_env.fog_enabled = _fog_enabled
				_fog_env.volumetric_fog_enabled = _volfog_enabled
			_fog_saved = false
			_fog_env = null
		if _occl_saved:
			if G.camera != null:
				RenderingServer.viewport_set_use_occlusion_culling(get_viewport().get_viewport_rid(), true)
			_occl_saved = false


## 显示同屏装备栏(menus 部署屏:透明背景 + 底部兵种/武器栏)与 3D 战术标记层
func _show_ui() -> void:
	if ui_open or G.menus == null:
		return
	ui_open = true
	# 死亡/重部署:隐藏地图选择与阵营选择;开局部署:保留(可换图/换边)
	G.menus.show_deploy(_entered_from != "match")
	if G.hud != null:
		G.hud.set_deployment_overlay(true)


## 死亡屏"重新部署"入口(未激活时回退传统流程)
func confirm_redeploy() -> void:
	if active:
		deploy_to_target(hovered if not hovered.is_empty() else {})
		return
	G.game.redeploy()


## 底部「部 署」按钮确认:部署到悬停/选中目标,无则基地
func confirm_deploy_ui() -> void:
	if phase != "free":
		return
	deploy_to_target(hovered if not hovered.is_empty() else {})


## ==================== 原始输入(鼠标释放状态下的拖图/点选) ====================
func _input(event: InputEvent) -> void:
	if not active or phase != "free" or G.menus == null:
		return
	if event is InputEventMouseMotion:
		# 按住左键拖动 = 平移地图;悬停判定跟随鼠标
		if _mouse_down and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if _drag_moved or event.relative.length() > 0.0:
				_drag_moved = true
				cam.pan_px(event.relative.x, event.relative.y)
		_update_hover()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_press_pos = event.position
			_drag_moved = false
		else:
			_mouse_down = false
			# 点击(未拖动):若落在 UI 上则交给界面,否则部署到悬停目标
			if not _drag_moved and not _over_ui(event.position):
				deploy_to_target(hovered if not hovered.is_empty() else {})
			_drag_moved = false


## 指针是否悬停于交互 UI 之上(底部装备栏等,交给 GUI 处理)
func _over_ui(screen_pos: Vector2) -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	# 3D 模式中透明背景区域无 Control(mouse_filter=IGNORE),故任何悬停 Control 即交互 UI
	return vp.gui_get_hovered_control() != null


## ==================== 每帧更新 ====================
func update(dt: float) -> void:
	if not active:
		return
	_phase_t += dt
	match phase:
		"down":
			# 死亡倒下动画:镜头原地坠落并轻微侧倾(约 1 秒),随后升空
			var c := G.camera
			var k := clampf(_phase_t / DOWN_DUR, 0.0, 1.0)
			cam.pos = _rise_from
			cam.pos.y = lerpf(_rise_from.y, maxf(0.32, _rise_from.y - 1.3), k)
			c.rotation_order = EULER_ORDER_YXZ
			c.global_position = cam.pos
			c.rotation = Vector3(-0.15, _death_yaw, minf(0.5, k * 0.55))
			c.fov = G.settings.fov if G.settings.has("fov") else 75.0
			if k >= 1.0:
				phase = "rise"
				_phase_t = 0.0
		"rise":
			var c := G.camera
			var k := clampf(_phase_t / RISE_DUR, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)   # smoothstep
			cam.pos = _rise_from.lerp(_rise_to, k)
			cam.pitch = lerpf(-0.15, -1.15, k)
			# 朝向平滑回正(与开局部署一致),保证拖图方向感
			cam.yaw = lerp_angle(_rise_yaw0, _base_yaw, k)
			c.global_position = cam.pos
			c.rotation_order = EULER_ORDER_YXZ
			c.rotation = Vector3(cam.pitch, cam.yaw, 0)
			c.rotation.z = lerpf(0.5, 0.0, k)
			c.fov = G.settings.fov if G.settings.has("fov") else 75.0
			if k >= 1.0:
				phase = "free"
				_show_ui()
				if not _hint_shown:
					_hint_shown = true
					G.hud.hint("左键拖动地图 · 点击部署点部署 · 空格部署基地 · WASD 平移 · 底部选择兵种武器")
		"free":
			cam.move_wasd(dt)
			_update_hover()
			# 空格:快速部署基地/悬停点
			if Input.is_action_just_pressed("jump"):
				deploy_to_target(hovered if not hovered.is_empty() else {})
		"fly":
			var c := G.camera
			var k := clampf(_phase_t / FLY_DUR, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)   # ease-out cubic
			cam.pos = _fly_from.lerp(_fly_to, e)
			cam.pitch = lerpf(_fly_pitch0, -1.25, e)
			c.global_position = cam.pos
			c.rotation_order = EULER_ORDER_YXZ
			c.rotation = Vector3(cam.pitch, cam.yaw, 0)
			c.fov = G.settings.fov if G.settings.has("fov") else 75.0
			if k >= 0.62 and not _fade_started:
				_fade_started = true
				G.hud.fade_to_black(0.42)
			if k >= 1.0:
				_finish_deploy()
				return
	if phase == "free":
		_apply_camera()


func _apply_camera() -> void:
	var c := G.camera
	if c == null:
		return
	c.global_position = cam.pos
	c.rotation_order = EULER_ORDER_YXZ
	c.rotation = Vector3(cam.pitch, cam.yaw, 0)
	c.fov = G.settings.fov if G.settings.has("fov") else 75.0


## 悬停检测:鼠标指针最近的部署目标(屏幕空间命中,无需 LOS)
func _update_hover() -> void:
	var c := G.camera
	if c == null:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var best: Dictionary = {}
	var best_px := 46.0
	for t in observer.collect():
		if not bool(t.get("valid", false)):
			continue
		var wpos: Vector3 = t["pos"] + Vector3(0, 1.8, 0)
		if c.is_position_behind(wpos):
			continue
		var sp: Vector2 = c.unproject_position(wpos)
		var dpx: float = sp.distance_to(mouse_pos)
		if dpx < best_px:
			best_px = dpx
			best = t
	hovered = best


## ==================== 部署 ====================
func deploy_to_target(t: Dictionary) -> void:
	if phase != "free":
		return
	if t.is_empty():
		t = { "kind": "base", "pos": observer.base_pos(), "label": "基地", "ref": null, "valid": true }
	if not observer.validate(t):
		G.hud.hint("该部署点已不可用")
		AudioSys.dry_fire()
		return
	_deploy_target = t
	phase = "fly"
	_phase_t = 0.0
	_fade_started = false
	_fly_from = cam.pos
	var tp: Vector3 = t["pos"]
	var off := Vector3.ZERO if t["kind"] == "base" else Vector3(Utils.rand(-4.0, 4.0), 0.0, Utils.rand(-4.0, 4.0))
	var gh: float = G.ground_h.call(tp.x + off.x, tp.z + off.z) if G.ground_h.is_valid() else 0.0
	_fly_to = Vector3(tp.x + off.x, gh + 15.0, tp.z + off.z)
	_fly_pitch0 = cam.pitch
	AudioSys.ui()


## 镜头抵达目标后:选定出生点 → 重生 → 无缝切回第一人称
func _finish_deploy() -> void:
	# 已重生/对局结束:仅清理部署层,不再重复部署
	if G.state != "dead" and G.state != "deploy":
		exit()
		return
	var t = _deploy_target
	var p = G.player
	if p == null:
		exit()
		return
	# 兵种/武器取自同屏装备栏(menus 选择;死亡重部署亦保持最新选择)
	var cls := "assault"
	var lo: Dictionary = { "primary": "m4", "secondary": "m1911", "shotgun": "m1014" }
	if G.menus != null:
		cls = G.menus.selected_class
		lo = G.menus.loadout.get(cls, lo)
	match t.get("kind", ""):
		"flag", "beacon":
			G.hud.spawn_point = t["ref"]
			G.hud.spawn_mate = null
			G.game.deploy(cls, lo)
		"mate":
			G.hud.spawn_mate = t["ref"]
			G.hud.spawn_point = null
			G.game.deploy(cls, lo)
		"vehicle":
			# 载具部署:直接生成在车旁(复用 spawn,不动 spawn_point 语义)
			G.hud.spawn_point = null
			G.hud.spawn_mate = null
			var v = t["ref"]
			var a := Utils.rand(TAU)
			var s2: Vector3 = v.pos + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)
			s2.y = G.ground_h.call(s2.x, s2.z) if G.ground_h.is_valid() else 0.0
			G.game.deploy(cls, lo, s2)
		_:
			G.hud.spawn_point = null
			G.hud.spawn_mate = null
			G.game.deploy(cls, lo)
	if G.hud != null:
		G.hud.fade_from_black(0.5)   # 高空镜头 → 第一人称的无缝过渡
	exit()
