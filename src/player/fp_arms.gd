class_name FpArms extends Node3D
## 第一人称手臂(2026-09-11 v7) —— **左右各三段 + 2-bone IK**。
##
## 模型 `tools/blender/build_fp_arms.py` → `models/fp_arms.glb`(6 个对象)
##   `FpArmLU / LF / LH`(左上臂+肩甲 / 左肘球+前臂 / 左手盒)
##   `FpArmRU / RF / RH`(同规格, 右)
## 每段原点在关节、几何沿局部 -Z(前方)排开。
##
## 两条手臂都走 IK
## ---------------
## 右手心 → 枪的握把锚点 `right_hand`; 左手心 → 护木锚点 `left_hand`。
## 55 把枪的两个锚点距离各不相同(0.21~0.54m), 所以两条手臂都必须是能独立摆姿势的。
##
## ★右臂为什么也拆(2026-09-11): v6 的右臂是"NPC 原样整体", 实测**必然与枪相交** ——
##   NPC 的右臂在 rest 里是**折叠**的(上臂仅 6cm, 手心到肩只有 0.23m), 手心对齐握把后
##   肩/肘正好落在**枪托**上; 以手心为支点扫过 ±80° 偏航角, 相交三角形最少也有 251 对
##   (0° 时 312) —— **没有任何角度能避开**。拆三段后右肩可以放到"握把右后下 ~0.43m"
##   (真人腰射手肘外张的位置), 上臂整个落到相机后方, 既不相交也不出现在画面里。

const GLB_PATH := "res://models/fp_arms.glb"

const LEN_UP := 0.2655          # 上臂长(须与 build_fp_arms.py 一致)
const LEN_FORE := 0.3535        # 前臂长

# 肩相对**手心**的偏移(vm 相机空间: x 右 / y 上 / -z 前)。
#
# 左肩 ★2026-09-11 实测调参: 旧值 y=+0.02 时左肩屏 y=1363(视口 1200), 而肩甲球在该
#   距离(0.32m)的投影半径约 191px ⇒ **肩甲上缘探进画面底部约 28px**(游戏内实拍左下角
#   露出一块灰球 + 整条上臂)。y 改 -0.04(再下移 6cm)后肩屏 y≈1558, 上缘 1367 ⇒ 上臂
#   与肩甲全部落在画面外, 画面里只剩前臂和手。
const SHOULDER_OFF_L := Vector3(-0.26, -0.04, -0.02)
# 右肩: 握把右后下 —— 让右上臂退到相机后方(真人腰射手肘外张的位置)
const SHOULDER_OFF_R := Vector3(0.20, -0.22, 0.30)

# 肘鼓出方向(只取垂直于"肩→手"轴的分量, 模长无所谓)。
# 左 ★2026-09-11 实测调参: 旧值 (-0.70,-0.65,0.20) 让肘跑到屏幕 x=577, 与手(x=1038)
#   横向差 461px ⇒ 左前臂在画面上是一条**横跨 24% 屏宽的粗斜条**。改成"近乎正下方、
#   只略偏左"后肘落到 x≈780, 前臂接近竖直, 露出面积减少约 25%; 肘更低也更容易避开
#   轻机枪的左下弹鼓。
const POLE_L := Vector3(-0.30, -0.90, 0.10)
# ★2026-09-11 试过更靠外的 (-0.85,-0.50,0.10): 它能把"左前臂 vs 枪下挂附件(两脚架/弹匣)"的相交从 259 对降到 159 对(8 把→6 把), **但游戏内实拍左前臂变成一条横贯画面底部的粗条、还把肘关节球顶进了画面** —— 观感明显变差, 所以回退。屏幕观感优先: 那些残留相交发生在画面外的枪下挂附件上。
const POLE_R := Vector3(0.90, -0.40, 0.10)

# 手臂整体抬升。★2026-09-11 置 0: 早先的 +0.045 是为"把手抬进画面"加的补偿, 但它同时
# 把上臂/前臂也抬高 4.5cm(肘深度处约 90px), 直接加重"手臂糊住画面下半"。现在肩已压低、
# 肘已改竖直, 不抬时手心屏 y≈887/1200(74%, 仍在画面内且更贴近真实腰射)。
const ARM_LIFT := Vector3(0.0, 0.0, 0.0)

# **左手心相对锚点的下移量**。
# `HAND_ANCHORS` 的语义是"左手贴合护木**底部**"(表头注释), 而手盒有厚度(0.04m),
# 把盒**中心**放在锚点上就等于让手掌上半埋进护木 —— 实测 m4 LH 与护木相交 63 对,
# 泵动霰弹枪(rem870/win1897)的锚点落在泵动护木内部, 更是相交 414/460 对, 整只手
# 被护木吃掉。下移 0.018(略小于半厚 0.02) 让手掌上沿刚好与护木底面相切 = 真正的"托"。
# 右手不加这个偏移 —— 右手是要**包住**握把的, 重叠是设计使然。
const GUARD_DROP := Vector3(0.0, -0.018, 0.0)

var ok := false
var _lu: Node3D = null
var _lf: Node3D = null
var _lh: Node3D = null
var _ru: Node3D = null
var _rf: Node3D = null
var _rh: Node3D = null

# ---- 可覆盖姿态参数(2026-09-11) ----
# 默认值 = 腰射持枪姿态(上面那批 const)。**载具第一人称 / 骑乘**会把它们换成自己的值:
# 手不再抓枪, 而是抓方向盘 / 车把握把, 肩与肘的鼓出方向完全不同。
var shoulder_off_l := SHOULDER_OFF_L
var shoulder_off_r := SHOULDER_OFF_R
var pole_l := POLE_L
var pole_r := POLE_R
var len_up := LEN_UP
var len_fore := LEN_FORE
var guard_drop := GUARD_DROP
var arm_lift := ARM_LIFT
# 可选: 绝对肩位置(父空间, 已含 arm_lift 空间)。null = 用"手心 + shoulder_off"的默认语义。
# 载具第一人称里两条肩都挂在躯干上、与手无关, 必须显式给 —— 否则左肩会跟着右手跑。
var shoulder_pos_l: Variant = null
var shoulder_pos_r: Variant = null
# 零件几何缩放(1.0 = FP 原尺寸)。载具第三/第一人称手臂放回与士兵 GLB 同尺寸时用 1.25,
# 同时外部要把 len_up / len_fore 一起乘上同一个系数, 否则 IK 长度与实际几何不符。
var seg_scale := 1.0
# 只显示"前臂 + 手"(隐藏上臂含肩甲)。第一人称驾驶时肩甲球会顶进画面(实拍两个黑球),
# 而上臂中段本来就在画面外, 藏掉后画面里只剩"从下缘伸入的前臂 + 握在操纵件上的手"。
var hide_upper := false


func _ready() -> void:
	for c in get_children():
		c.queue_free()
	if not ResourceLoader.exists(GLB_PATH):
		push_warning("[FpArms] 缺模型: " + GLB_PATH)
		return
	var ps := load(GLB_PATH) as PackedScene
	if ps == null:
		push_warning("[FpArms] 载入失败: " + GLB_PATH)
		return
	var inst := ps.instantiate()
	inst.name = "FpArmsModel"
	add_child(inst)
	_lu = _find(inst, "FpArmLU")
	_lf = _find(inst, "FpArmLF")
	_lh = _find(inst, "FpArmLH")
	_ru = _find(inst, "FpArmRU")
	_rf = _find(inst, "FpArmRF")
	_rh = _find(inst, "FpArmRH")
	_apply_materials(inst)
	ok = _lu != null and _lf != null and _lh != null \
			and _ru != null and _rf != null and _rh != null
	print("[FpArms] v7 左三段=%s/%s/%s 右三段=%s/%s/%s ok=%s" % [
		_lu != null, _lf != null, _lh != null, _ru != null, _rf != null, _rh != null, ok])


## 按名字找 GLB 里的节点(Godot 会保留 glTF 节点名)
func _find(root: Node, nm: String) -> Node3D:
	return root.find_child(nm, true, false) as Node3D


## 每帧驱动(由 Gun 调用)。right_hand = 右握把锚点, left_hand = 左手锚点(护木)。
func solve(right_hand: Node3D, left_hand: Node3D) -> void:
	if not ok or right_hand == null or not is_instance_valid(right_hand):
		return
	var lw: Variant = null
	if left_hand != null and is_instance_valid(left_hand):
		lw = left_hand.global_position
	solve_world(right_hand.global_position, lw)


## 世界坐标版: 两个手心目标都是**世界坐标**(lw 传 null = 只摆右臂)。
## 载具第一人称/骑乘用它 —— 手目标是方向盘/车把上的固定点, 与相机无关。
func solve_world(rw: Vector3, lw: Variant) -> void:
	if not ok:
		return
	# ★必须换算到**自身空间**: `_place()` 写的是零件的局部 transform(相对本节点)。
	# 旧版用 `get_parent().to_local()` —— 只有"本节点 transform == identity"(vm 层)时才碰巧等价;
	# 车内手臂要把本节点对齐车体(global_transform = mesh.global_transform), 用父空间会**双重变换**
	# (整车 yaw/位移被再乘一次 ⇒ 手/肘飞到车外, 实拍"吉普第一人称看不到手")。
	var inv := global_transform.affine_inverse()
	var grip: Vector3 = (inv * rw) + arm_lift

	# ---- 右臂: 手心 → 目标 ----
	var sh_r := grip + shoulder_off_r
	if shoulder_pos_r != null:
		sh_r = shoulder_pos_r
	var el_r := _solve_ik(sh_r, grip, pole_r)
	_place(_ru, sh_r, el_r - sh_r)
	_place(_rf, el_r, grip - el_r)
	_place(_rh, grip, grip - el_r)

	# ---- 左臂: 手心 → 目标 ----
	if lw != null:
		var guard: Vector3 = (inv * lw) + arm_lift + guard_drop
		var sh_l := grip + shoulder_off_l
		if shoulder_pos_l != null:
			sh_l = shoulder_pos_l
		var el_l := _solve_ik(sh_l, guard, pole_l)
		_place(_lu, sh_l, el_l - sh_l)
		_place(_lf, el_l, guard - el_l)
		_place(_lh, guard, guard - el_l)
	if _ru != null:
		_ru.visible = not hide_upper
	if _lu != null:
		_lu.visible = not hide_upper


## 解析 2-bone IK(与 render_fp_hold.py 同式)
func _solve_ik(shoulder: Vector3, wrist: Vector3, pole: Vector3) -> Vector3:
	var to := wrist - shoulder
	var dr := to.length()
	if dr < 1e-4:
		return shoulder
	var d := clampf(dr, absf(len_up - len_fore) + 0.02, len_up + len_fore - 0.004)
	var axis := to / dr
	var pp := pole - axis * pole.dot(axis)
	if pp.length_squared() < 1e-6:
		pp = Vector3.DOWN - axis * Vector3.DOWN.dot(axis)
	if pp.length_squared() < 1e-6:
		return shoulder + axis * d
	var pdir := pp.normalized()
	var a := (LEN_UP * LEN_UP - LEN_FORE * LEN_FORE + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, LEN_UP * LEN_UP - a * a))
	return shoulder + axis * a + pdir * h


## 零件沿局部 -Z 排开 ⇒ 把 -Z 转到 dir, 原点放到 pos
## ※ `seg_scale` 只缩放**零件几何**(基向量), 位置 pos 不受影响 ⇒ 手臂可整体放大而不位移。
func _place(ob: Node3D, pos: Vector3, dir: Vector3) -> void:
	if ob == null or dir.length_squared() < 1e-9:
		return
	var z := -dir.normalized()
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.985:
		up = Vector3.RIGHT
	var xa := up.cross(z).normalized()
	var ya := z.cross(xa)
	var b := Basis(xa, ya, z)
	if seg_scale != 1.0:
		b = Basis(xa * seg_scale, ya * seg_scale, z * seg_scale)
	ob.transform = Transform3D(b, pos)


## GLB 材质名不会自动映射项目 PBR(不处理=纯白) —— 按 surface 材质名给色
func _apply_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mm := (mi as MeshInstance3D).mesh
		if mm == null:
			continue
		for i in mm.get_surface_count():
			var src := mm.surface_get_material(i)
			var nm := src.resource_name if src != null else ""
			(mi as MeshInstance3D).set_surface_override_material(i, _mat_for(nm))


static func _mat_for(nm: String) -> StandardMaterial3D:
	var c := Color.html("#5a6349")          # olive: 袖
	var rough := 0.78
	var metal := 0.03
	if nm.contains("dark"):
		c = Color.html("#2c3035")           # 关节球 / 肩甲
		rough = 0.62
		metal = 0.10
	elif nm.contains("tan"):
		c = Color.html("#8a7a62")           # 手
		rough = 0.80
		metal = 0.02
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
