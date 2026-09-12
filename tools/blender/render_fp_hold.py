"""
手臂持枪合成预览 —— NPC 手臂 + 指定枪, 用来**脱离引擎核对**"右手是否握住枪把、
左手是否扶住护木"。侧面照是唯一能看清手位的手段(游戏内 60° FOV 下手臂大半在画面外)。

摆法 = **引擎同款逻辑**
--------------------
- 右手心: 直接落到枪的**握把锚点** `HAND_ANCHORS[id].r`。
- 左手心: 落到**护木锚点** `HAND_ANCHORS[id].l`。
- 两条手臂各自 2-bone 解析 IK(余弦定理 + pole 平面)求肘; 肘由 pole 决定往哪侧鼓
  (左肘压左下、右肘张右下 —— 顺带避开轻机枪左下弹鼓)。

★锚点必须读引擎的 `weapon_models.gd::HAND_ANCHORS`, **不能去 GLB 里找
`handguard`/`grip` 节点名**: 两者差得远(m4: 表里 l=(0,-0.03,-0.33) 在**护木下方**,
而 handguard 节点在枪身**轴线上**, 高了 5.4cm) —— 用节点名会让手插进枪身,
预览与真实运行不符, 验证就失去意义。

用法
----
    blender --background --python render_fp_hold.py            # 默认 m4
    blender --background --python render_fp_hold.py -- ak       # 指定枪
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402
import build_soldier as S  # noqa: E402
import build_fp_arms as A  # noqa: E402

WEAPONS = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"
SHOT_DIR = "E:/工作目录2/models_probe"
GD_WEAPON_MODELS = "E:/工作目录2/zero/steel_frontline_godot/src/models/weapon_models.gd"

L1, L2 = A.LEN_UP, A.LEN_FORE

# ⚠ 必须与 src/player/fp_arms.gd 保持一致。
#   vm(Godot 相机空间) → Blender: (bx, by, bz) = (vx, -vz, vy)
SHOULDER_OFF_L = Vector((-0.26, 0.02, -0.04))     # vm (-0.26, -0.04, -0.02)
SHOULDER_OFF_R = Vector((0.20, -0.30, -0.22))     # vm ( 0.20, -0.22,  0.30)
POLE_L = Vector((-0.30, -0.10, -0.90))            # vm (-0.30, -0.90,  0.10)
# 左手心下移(与 fp_arms.gd::GUARD_DROP 同源): vm(0,-0.018,0) → Blender(0,0,-0.018)
GUARD_DROP = Vector((0.0, 0.0, -0.018))
POLE_R = Vector((0.90, -0.10, -0.40))             # vm ( 0.90, -0.40,  0.10)


def load_anchors():
    """解析 `weapon_models.gd::HAND_ANCHORS` —— 引擎真正用的手部锚点(枪械局部空间)。

    坐标换算 Godot→Blender(yup 往返一致): (x, y, z)_godot → (x, -z, y)_blender
    """
    try:
        txt = open(GD_WEAPON_MODELS, encoding="utf-8").read()
    except Exception as e:
        print("[HOLD] 读不到锚点表:", e)
        return {}
    i = txt.index("const HAND_ANCHORS := {")
    blk = txt[i:]
    blk = blk[:blk.index("\n}")]
    out = {}
    for m in re.finditer(r'"([A-Za-z0-9_]+)":\s*\{\s*"r":\s*\[([^\]]+)\],\s*"l":\s*\[([^\]]+)\]', blk):
        gid = m.group(1)
        r = [float(x) for x in m.group(2).split(",")]
        l = [float(x) for x in m.group(3).split(",")]
        out[gid] = (Vector((r[0], -r[2], r[1])), Vector((l[0], -l[2], l[1])))
    return out


def _gun_arg():
    if "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1:]
        if rest:
            return rest[0]
    return "m4"


def find_node(*keys):
    for o in bpy.data.objects:
        nm = o.name.lower()
        if any(k.lower() in nm for k in keys):
            return o.matrix_world.translation.copy()
    return None


def gun_bbox():
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return Vector(mn), Vector(mx)


def solve_ik(shoulder, wrist, pole):
    to = wrist - shoulder
    dr = to.length
    if dr < 1e-4:
        return shoulder
    d = max(abs(L1 - L2) + 0.02, min(L1 + L2 - 0.004, dr))
    axis = to.normalized()
    pp = pole - axis * pole.dot(axis)
    if pp.length < 1e-6:
        pp = Vector((0.0, 0.0, -1.0))
    pdir = pp.normalized()
    a = (L1 * L1 - L2 * L2 + d * d) / (2.0 * d)
    h = (max(0.0, L1 * L1 - a * a)) ** 0.5
    return shoulder + axis * a + pdir * h


def place(ob, pos, direction):
    """零件沿 +Y 建 ⇒ 把对象 +Y 转到 direction, 原点放到 pos(叠加在已有矩阵上)。"""
    q = Vector((0.0, 1.0, 0.0)).rotation_difference(direction.normalized())
    ob.matrix_world = Matrix.Translation(pos) @ q.to_matrix().to_4x4() @ ob.matrix_world


def pose_arms(arms, grip, guard):
    """两条手臂按引擎同款逻辑摆好。返回 (左肩→护木距离, 右肩→握把距离)。"""
    guard = guard + GUARD_DROP
    sh_l = grip + SHOULDER_OFF_L
    el_l = solve_ik(sh_l, guard, POLE_L)
    place(arms["LU"], sh_l, el_l - sh_l)
    place(arms["LF"], el_l, guard - el_l)
    place(arms["LH"], guard, guard - el_l)

    sh_r = grip + SHOULDER_OFF_R
    el_r = solve_ik(sh_r, grip, POLE_R)
    place(arms["RU"], sh_r, el_r - sh_r)
    place(arms["RF"], el_r, grip - el_r)
    place(arms["RH"], grip, grip - el_r)
    return (guard - sh_l).length, (grip - sh_r).length


def setup_and_render(gun_id, mn, mx):
    try:
        bpy.context.scene.render.engine = 'BLENDER_EEVEE'
    except Exception:
        pass
    bpy.ops.object.light_add(type='SUN', location=(2, -3, 5))
    bpy.context.active_object.data.energy = 2.2
    bpy.ops.object.light_add(type='AREA', location=(-2.5, 1.5, 2.0))
    al = bpy.context.active_object
    al.data.energy = 180
    al.data.size = 3.5
    if bpy.context.scene.world is None:
        bpy.context.scene.world = bpy.data.worlds.new("W")
    bpy.context.scene.world.use_nodes = True
    bg = bpy.context.scene.world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs['Color'].default_value = (0.30, 0.33, 0.37, 1.0)
        bg.inputs['Strength'].default_value = 0.65

    sc = bpy.context.scene
    sc.render.resolution_x = 1200
    sc.render.resolution_y = 640
    sc.render.film_transparent = False
    mid = (mn + mx) * 0.5
    span = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
    scale = span * 1.20
    views = [
        ("side", Vector((1.3, mid.y, 0.10))),
        ("top", Vector((0.0, mid.y, 1.3))),
        ("quarter", Vector((0.95, mid.y - 0.85, 0.85))),
    ]
    os.makedirs(SHOT_DIR, exist_ok=True)
    for nm, loc in views:
        cd = bpy.data.cameras.new(nm)
        cd.type = 'ORTHO'
        cd.ortho_scale = scale
        cam = bpy.data.objects.new(nm, cd)
        sc.collection.objects.link(cam)
        cam.location = loc
        cam.rotation_euler = (mid - loc).to_track_quat('-Z', 'Y').to_euler()
        sc.camera = cam
        sc.render.filepath = os.path.join(SHOT_DIR, "hold_%s_%s.png" % (gun_id, nm))
        bpy.ops.render.render(write_still=True)


def main():
    gun_id = _gun_arg()
    path = os.path.join(WEAPONS, gun_id + ".glb")
    if not os.path.exists(path):
        print("[HOLD] 找不到枪: " + path)
        return
    S.reset()
    arms = A.build_arms()
    bpy.ops.import_scene.gltf(filepath=path)

    mn, mx = gun_bbox()
    anch = load_anchors().get(gun_id)
    if anch is not None:
        grip, guard = anch
        src = "HAND_ANCHORS(引擎同源)"
    else:
        src = "GLB 节点(回退)"
        grip = find_node("grip")
        guard = find_node("handguard", "foregrip")
        if grip is None:
            grip = Vector((0.0, mn.y + (mx.y - mn.y) * 0.22, mn.z + (mx.z - mn.z) * 0.35))
        if guard is None:
            guard = Vector((0.0, mn.y + (mx.y - mn.y) * 0.55, mn.z + (mx.z - mn.z) * 0.45))

    reach_l, reach_r = pose_arms(arms, grip, guard)
    print("[HOLD] %s | 锚点来源=%s 握把=%s 护木=%s" % (gun_id, src, grip, guard))
    lo, hi = abs(L1 - L2) + 0.02, L1 + L2 - 0.004
    for tag, reach in (("左(肩→护木)", reach_l), ("右(肩→握把)", reach_r)):
        print("[HOLD]   %s=%.3fm 臂长区间=(%.3f, %.3f) 肘可自然弯曲=%s" % (
            tag, reach, lo, hi, lo < reach < hi))
    bpy.context.view_layer.update()
    setup_and_render(gun_id, mn, mx)
    print("[HOLD] %s 渲染完成" % gun_id)


if __name__ == "__main__":
    main()
