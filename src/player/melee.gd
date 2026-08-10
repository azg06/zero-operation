class_name Melee extends RefCounted
## 近战小刀系统(全模式可用):
## - 弹尽自动切换 / H 长按呼出收回 / 左键锥形挥击
## - 状态与模型均挂 player 侧(vm_camera 层),仅激活时更新,无每帧全局开销
## - 伤害结算复用 bot.take_damage → die → game.on_kill(击杀播报/记分/门户接线)

const DMG := 50.0                  # 一刀 50(两刀击杀 100 血敌人)
const RANGE := 2.0                 # 前方 2m 半径
const CONE_HALF := PI / 6.0        # 60° 锥形(半角 30°)
const SWING_CD := 0.6              # 挥击冷却
const SWING_DUR := 0.35            # 挥击动画时长(前刺+横挥)
const HIP_POS := Vector3(0.22, -0.19, -0.3)
# 手臂肘部屏外锚点(小刀局部空间):与 gun.gd:7 同值,臂筒自手腕延伸至屏幕外
const ELBOW_R := Vector3(0.1, -0.46, 0.4)

var player = null
var group: Node3D = null           # 小刀模型(vm_camera 子节点)
var _r_hand: Node3D = null         # 右手握持点(build_knife meta)
var _r_arm: Node3D = null          # 右臂筒(build_knife meta,单位 1m 臂筒需每帧缩放)
var cd := 0.0
var swing_t := 0.0                 # >0 = 挥击动画进行中
var draw_t := 1.0                  # 拔刀动画


func _init(p) -> void:
	player = p
	group = WeaponModels.build_knife()
	# 缓存手臂节点(build_knife 仅构建右手/右臂;防御判空)
	_r_hand = group.get_meta("right_hand", null)
	_r_arm = group.get_meta("right_arm", null)
	if G.vm_camera != null:
		G.vm_camera.add_child(group)
	holster()


func equip() -> void:
	if group == null or not is_instance_valid(group):
		return
	group.visible = true
	draw_t = 0
	cd = 0.0
	AudioSys.reload(1)
	print("[MELEE] 小刀呼出")


func holster() -> void:
	if group != null and is_instance_valid(group):
		group.visible = false
	swing_t = 0


## 小刀状态每帧更新(仅激活时由 player 调用):冷却 + 待机/挥击动画
func update(dt: float) -> void:
	if group == null or not is_instance_valid(group) or not group.visible:
		return
	cd = maxf(0, cd - dt)
	draw_t = minf(1, draw_t + dt / 0.25)
	if swing_t > 0:
		# 挥击动画:快速前刺 + 横挥(0.35s,参考换弹动画写法)
		swing_t += dt
		if swing_t >= SWING_DUR:
			swing_t = 0
			group.position = HIP_POS
			group.rotation = Vector3.ZERO
		else:
			var t := swing_t / SWING_DUR
			var thrust := sin(t * PI)          # 0→1→0 突进
			group.position = HIP_POS + Vector3(-0.02, -0.04, -thrust * 0.24)
			group.rotation.x = -thrust * 0.55
			group.rotation.y = (t - 0.5) * 0.9
			group.rotation.z = -0.15
	else:
		# 待机:轻微呼吸 + 拔刀落位
		var tb: float = G.time
		group.position = HIP_POS + Vector3(sin(tb * 1.3) * 0.004, -0.02 + absf(sin(tb * 1.1)) * 0.008, 0)
		group.rotation = Vector3(sin(tb * 1.3) * 0.02, 0, sin(tb * 0.8) * 0.03)
		var dd := (1 - draw_t) * 0.3
		group.position.y -= dd
		group.rotation.x -= (1 - draw_t) * 0.7
	# 臂筒:手腕 → 屏外肘锚点连续定向伸缩(与 gun.gd:719-721 一致,修复原样 1m 臂筒悬空过长)
	if _r_arm != null and _r_hand != null:
		_point_arm(_r_arm, _r_hand.position, ELBOW_R)


## 手臂定向:腕部 → 屏外肘锚点,臂筒连续伸缩(与 gun.gd:764-770 相同算法副本)
func _point_arm(arm: Node3D, wrist: Vector3, elbow: Vector3) -> void:
	if arm == null:
		return
	var d := wrist - elbow
	var arm_len := maxf(d.length(), 0.06)
	arm.position = (wrist + elbow) * 0.5
	arm.basis = Basis.looking_at(d / arm_len, Vector3.UP, true) * Basis.from_scale(Vector3(1.0, 1.0, arm_len * 1.1))


## 挥击:前方 2m / 60° 锥形范围内最近的敌人造成 50 伤害
## 命中 bot 走 take_damage → die → game.on_kill(击杀播报/记分/门户接线);队友与 BR 同队免伤
func try_swing() -> void:
	if cd > 0 or draw_t < 0.35 or G.camera == null:
		return
	cd = SWING_CD
	swing_t = 0.0001
	var cam: Camera3D = G.camera
	var origin: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var def := { "cn": "近战小刀", "name": "melee", "damage": DMG, "kind": "melee" }
	var best = null
	var best_d := INF
	for b in G.bots:
		if b == null or b.get("alive") != true or b.get("vehicle") != null:
			continue
		# 队伍判定:BR 同队(玩家=队 0)免伤;常规模式同阵营免伤
		if G.mode == "br":
			if Bot.br_same_squad(b, player):
				continue
		elif b.get("team") == player.team:
			continue
		var chest := Vector3(b.pos.x, b.pos.y + 1.05, b.pos.z)
		var to := chest - origin
		var d := to.length()
		if d > RANGE or d < 0.05:
			continue
		if fwd.angle_to(to / d) > CONE_HALF:
			continue
		if not Utils.los_clear(origin, chest):
			continue
		if d < best_d:
			best = b
			best_d = d
	if best != null:
		var hp0: float = best.health
		best.take_damage(DMG, player, false, def)
		if G.game != null and G.game.has_method("_portal_damage"):
			G.game._portal_damage(player, best, DMG)
		var killed: bool = best.get("alive") != true
		if G.hud != null and G.hud.has_method("show_hitmarker"):
			G.hud.show_hitmarker(killed, false)
		if killed:
			AudioSys.kill_confirm(false)
		else:
			AudioSys.hit(false)
		print("[MELEE] 挥击命中 %s 伤害=%.0f hp=%.0f→%.0f %s" % [
			str(best.get("name")) if best.get("name") != null else "bot",
			DMG, hp0, best.health, "击杀" if killed else "命中"])
	else:
		AudioSys.bolt()


## 判定辅助(纯函数,供隔离测试):target 是否位于 origin 前向 range 内 half 半角锥形中
static func in_cone(origin: Vector3, fwd: Vector3, target: Vector3, range := RANGE, half := CONE_HALF) -> bool:
	var to := target - origin
	var d := to.length()
	if d > range or d < 0.05:
		return false
	return fwd.angle_to(to / d) <= half
