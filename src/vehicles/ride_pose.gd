class_name RidePose
extends RefCounted
## 载具乘员骨架姿态工具(2026-09-11) —— player.gd / bot.gd 共用。
##
## GLB 士兵骨架的坐姿/骑姿只能靠代码摆(士兵 GLB 的 8 个动画里没有坐/骑姿)。这里提供:
##   * `ik_chain`  2-bone IK(`set_bone_global_pose_override`)。腿摆到脚踏/地板、手臂摆到
##                 车把握把都靠它 —— 摩托左右转向时车把会绕 Y 转, 手必须每帧重解才跟得上。
##   * `aim`       单骨"指向目标"的底层操作(把"当前指向子骨的方向"旋到目标方向)。
##   * `ride_legs` / `seat_legs`  骑姿腿(踩脚踏) / 吉普坐姿腿(前伸下垂)。
##   * `hide_arm_bones`  GLB 自带手臂缩到 1cm —— 骑手/驾驶的**手臂由分段模型接管**。
##     ★为什么不用 GLB 自己的手臂: 士兵右臂骨 rest 是**折叠**的(上臂仅 6cm,
##       肩→腕上限 0.30m), 根本够不到 0.51m 外的握把; 分段手臂(上臂 .266+前臂 .354)才够。
##
## 坐标约定: 所有 target/pole 都是 **Skeleton3D 所在空间**(= 模型空间), 不是世界空间。

const ARM_HIDE_BONES := ["ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR",
		"ForearmL", "ForearmR", "HandL", "HandR"]

# 落位基准(车体空间坐标 = mesh 局部)。臀部点由"座垫顶面 + 一点压缩量"给出。
const MOTO_HIP := Vector3(0.0, 0.80, 0.40)   # 骑手臀部: 座垫顶 0.785, 座垫 z 0.44
const JEEP_HIP_Y := 1.05                     # 乘员臀部高度: 座垫顶 1.01 + 0.04
const JEEP_HIP_Z := 0.45                     # 乘员纵向(座垫中心)

const MOTO_PEG_X := 0.270        # 脚踏 Peg27/Peg-27 的横向位置(车体空间)
const MOTO_PEG_Y := 0.430        # 脚踏高度
const MOTO_PEG_Z := 0.040        # 脚踏纵向

const JEEP_FOOT_Y := 0.62        # 吉普脚踝(车体空间, 落到地板下方被地板挡住)
const JEEP_FOOT_Z := 0.02
const JEEP_FOOT_X := 0.13


## GLB 自带手臂全部缩掉(否则会和分段手臂重叠出四条胳膊)。
static func hide_arm_bones(sk: Skeleton3D) -> void:
	if sk == null:
		return
	for bn in ARM_HIDE_BONES:
		var bi := sk.find_bone(bn)
		if bi >= 0:
			sk.set_bone_pose_scale(bi, Vector3.ONE * 0.01)


## 2-bone IK: 把 a→b→c 骨链摆到 target(模型空间), 中间关节朝 pole 方向鼓出。
static func ik_chain(sk: Skeleton3D, an: String, bn: String, cn: String,
		target: Vector3, pole: Vector3) -> void:
	if sk == null:
		return
	var ia := sk.find_bone(an)
	var ib := sk.find_bone(bn)
	var ic := sk.find_bone(cn)
	if ia < 0 or ib < 0 or ic < 0:
		return
	sk.force_update_all_bone_transforms()
	var pa := sk.get_bone_global_pose(ia)
	var pb := sk.get_bone_global_pose(ib)
	var pc := sk.get_bone_global_pose(ic)
	var la := pa.origin.distance_to(pb.origin)
	var lb := pb.origin.distance_to(pc.origin)
	if la < 1e-4 or lb < 1e-4:
		return
	var sh := pa.origin
	var to := target - sh
	var dr := to.length()
	if dr < 1e-5:
		return
	var d := clampf(dr, absf(la - lb) + 0.015, la + lb - 0.004)
	var axis := to / dr
	var pp := pole - axis * pole.dot(axis)
	if pp.length_squared() < 1e-6:
		pp = Vector3.DOWN - axis * Vector3.DOWN.dot(axis)
	var pdir := pp.normalized() if pp.length_squared() > 1e-8 else Vector3.DOWN
	var aa := (la * la - lb * lb + d * d) / (2.0 * d)
	var hh := sqrt(maxf(0.0, la * la - aa * aa))
	var mid := sh + axis * aa + pdir * hh
	aim(sk, ia, pb.origin - pa.origin, mid - sh, sh)
	sk.force_update_all_bone_transforms()
	var pb2 := sk.get_bone_global_pose(ib)
	var pc2 := sk.get_bone_global_pose(ic)
	aim(sk, ib, pc2.origin - pb2.origin, target - mid, mid)
	sk.force_update_all_bone_transforms()
	# 末端骨: 位置钉到目标, 朝向沿用下段骨(保持 rest 相对姿态)
	var pf := sk.get_bone_global_pose(ib)
	var ph := sk.get_bone_global_pose(ic)
	var rel := ph.basis * pf.basis.inverse()
	sk.set_bone_global_pose_override(ic, Transform3D(pf.basis * rel, target), 1.0, true)
	sk.force_update_all_bone_transforms()


## 把 idx 骨的"指向子骨方向"从 cur_dir 旋到 want_dir, 原点钉在 pos(模型空间)。
static func aim(sk: Skeleton3D, idx: int, cur_dir: Vector3, want_dir: Vector3, pos: Vector3) -> void:
	if cur_dir.length_squared() < 1e-8 or want_dir.length_squared() < 1e-8:
		return
	var p := sk.get_bone_global_pose(idx)
	var q := Quaternion(cur_dir.normalized(), want_dir.normalized())
	sk.set_bone_global_pose_override(idx, Transform3D(Basis(q) * p.basis, pos), 1.0, true)


## 恢复 GLB 自带手臂(取消 hide_arm_bones 的 1cm 缩放)。
## ★必须成对使用: `set_bone_pose_scale` 是**持久**的(动画只轨 rotation/location),
##   骑摩托时缩掉手臂后, 再上吉普若不恢复 ⇒ 乘员**没有手臂**(用户报"身体太大手臂太小")。
static func show_arm_bones(sk: Skeleton3D) -> void:
	if sk == null:
		return
	for bn in ARM_HIDE_BONES:
		var bi := sk.find_bone(bn)
		if bi >= 0:
			sk.set_bone_pose_scale(bi, Vector3.ONE)


## 跳跃/坠落腾空腿(2026-09-12):士兵 GLB 的 8 个动画里**没有 Jump/Fall/Land**,
## 腾空姿态只能程序化摆(与坐/骑姿同一路子)。
##   vy > 0 上升 → 收腿(膝盖朝前上抬、脚靠向臀部)
##   vy < 0 下落 → 伸腿(脚放低略前, 准备触地)
## 坐标 = 模型空间(原点脚底),与 ik_chain 一致。跳跃全程 <1s,调用开销可接受。
static func air_legs(sk: Skeleton3D, vy: float, amt: float) -> void:
	if sk == null or amt <= 0.001:
		return
	# t: 1 = 快速上升(收腿到底), 0 = 快速下落(伸腿到底)
	var t: float = clampf(0.5 + vy / 6.0, 0.0, 1.0)
	# amt 0→1 = 站立腿位 → 腾空腿位。用 amt 插值而不是硬切 ⇒ 起跳/落地时腿平滑过渡。
	var foot_y: float = lerpf(0.12, lerpf(0.14, 0.60, t), amt)
	var foot_z: float = lerpf(0.00, lerpf(-0.04, -0.20, t), amt)
	var pole_y: float = lerpf(0.10, lerpf(0.25, 0.80, t), amt)
	ik_chain(sk, "ThighL", "ShinL", "FootL",
		Vector3(-0.17, foot_y, foot_z), Vector3(-0.55, pole_y, -0.75))
	ik_chain(sk, "ThighR", "ShinR", "FootR",
		Vector3(0.17, foot_y, foot_z), Vector3(0.55, pole_y, -0.75))


## 骑姿腿: 双脚踩脚踏 Peg(车体 ±0.270, 0.430, 0.040), 膝盖朝外前方。
## org = 模型原点在车体空间的坐标(用于把车体坐标换成模型坐标)。
static func ride_legs(sk: Skeleton3D, org: Vector3) -> void:
	var peg_d := Vector3(MOTO_PEG_X, MOTO_PEG_Y, MOTO_PEG_Z) - org + Vector3(0, 0.05, 0)
	# ★膝盖朝"外 + 上 + 前": 真人骑姿大腿近乎水平前伸, 膝盖在臀部前上方 —— 这样
	#   第一人称低头才看得到膝盖/大腿(旧 pole 全是"下", 膝盖缩在臀下方 86° 俯角处, 看不见)。
	ik_chain(sk, "ThighL", "ShinL", "FootL",
		Vector3(-peg_d.x, peg_d.y, peg_d.z), Vector3(-0.8, 0.55, -0.9))
	ik_chain(sk, "ThighR", "ShinR", "FootR", peg_d, Vector3(0.8, 0.55, -0.9))


## 吉普坐姿腿: 大腿前伸、小腿垂到驾驶舱地板下方(被地板挡住看不见)。
static func seat_legs(sk: Skeleton3D, org: Vector3) -> void:
	var foot := Vector3(JEEP_FOOT_X, JEEP_FOOT_Y, JEEP_FOOT_Z) - org
	ik_chain(sk, "ThighL", "ShinL", "FootL",
		Vector3(-foot.x, foot.y, foot.z), Vector3(-0.6, 0.5, -1.0))
	ik_chain(sk, "ThighR", "ShinR", "FootR", foot, Vector3(0.6, 0.5, -1.0))
