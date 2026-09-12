"""
第一人称手臂 —— **NPC 手臂的几何, 左右各拆三段**(2026-09-11 v7)。

为什么这么拆
------------
手臂必须能跟着**每把枪自己的两个锚点**(右手→握把 / 左手→护木)走, 而 55 把枪的
"握把→护木"距离各不相同, 所以两条手臂都得是**能独立摆姿势**的。

拆法
----
- 每条手臂 = 三段: `U` 上臂+肩甲 / `F` 肘球+前臂 / `H` 手盒。
  每段原点在关节, 几何沿 **+Y** 排开(导出 yup 后在 Godot 里即 -Z = 前方),
  引擎里用 2-bone 解析 IK 把"手心"摆到锚点, 肘由 pole 决定往哪侧鼓。
- 右臂**同样拆三段**。★2026-09-11: 早先右臂是"NPC 原样整体"(v6), 但实测它
  **必然穿模** —— NPC rest 姿态里右臂是**折叠**的(上臂只有 6cm, 手心到肩仅 0.23m),
  手心对齐握把后肩/肘正落在**枪托**位置; 以手心为支点扫遍 ±80° 偏航角, 相交三角形
  最少也有 251 对(0° 时 312), **没有任何角度能避开**。拆三段后右肩可以放到
  "握把右后下 ~0.43m"(真人腰射手肘外张的位置), 上臂落到相机后方, 既不相交
  也不出现在画面里。

几何规格全部来自 NPC(`build_soldier`)
-------------------------------------
半径/长度/关节球/手盒都用 `VARIANTS["assault"]` 的原值, 再统一乘 `FP_SCALE`
(等比例缩小, 适配第一人称近距视角)。

用法
----
    blender --background --python build_fp_arms.py
    blender --background --python build_fp_arms.py -- render
"""

import os
import sys
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import build_soldier as S  # noqa: E402  NPC 手臂的唯一来源
from gunforge import set_material  # noqa: E402

MODELS = "E:/工作目录2/zero/steel_frontline_godot/models"
OUT_GLB = os.path.join(MODELS, "fp_arms.glb")
SHOT_DIR = "E:/工作目录2/models_probe"

FP_SCALE = 0.80                      # 等比例缩放(整体, 比例不变)

# NPC 手臂骨点(build_soldier.BONES 原值)。左右手臂长度基本相同, 统一取左臂的:
#   左肩(-0.23,0.02,1.49) 左肘(-0.18,0.28,1.29) 左腕(0.10,0.60,1.41)
# (NPC 的右臂是折叠端枪姿态、上臂只有 6cm, 长度不可用; 而两段几何本身是轴对称的。)
P_SH_L = (-0.23, 0.02, 1.49)
P_EL_L = (-0.18, 0.28, 1.29)
P_WR_L = (0.10, 0.60, 1.41)

V_ARM = S.VARIANTS["assault"]["arm"]      # 0.058
V_FORE = S.VARIANTS["assault"]["fore"]    # 0.050
V_PAD = S.VARIANTS["assault"]["pad"]      # 0.074
J = 1.12                                  # 关节球系数(NPC 原值)

# 引擎 IK 要用的臂长(等比例缩放后) —— 必须与 fp_arms.gd 的常量一致
LEN_UP = (Vector(P_EL_L) - Vector(P_SH_L)).length * FP_SCALE
LEN_FORE = (Vector(P_WR_L) - Vector(P_EL_L)).length * FP_SCALE   # 肘 → **掌心**

# ★2026-09-11: 前臂**几何**只做到"腕", 比掌心短一个 WRIST_GAP。
#   手盒的原点在手心(要跟引擎锚点对齐), 如果前臂筒也一路伸到掌心, 它的末端就会
#   插进握把/护木/弹匣里 —— 实测 m4 RF 与 Grip 系相交 70 对、g17 RF 与 mag 相交 55 对。
#   掌心到腕在 NPC 里是 0.03m(左腕 (0.10,0.57,1.41) → 左掌心 (0.10,0.60,1.41)),
#   缩放后 0.024m。缩掉这段后前臂止于腕, 而手掌本体(沿 Y 长 0.072、以手心为中心)会
#   把腕整个盖住, 所以视觉上没有缝隙。
WRIST_GAP = 0.03 * FP_SCALE


def _tube_local(name, r, ln):
    """在局部空间沿 +Y 建一段圆柱(原点在关节头)。"""
    ob = S.cyl(name, r, ln, vtx=10, loc=(0.0, ln * 0.5, 0.0))
    ob.rotation_euler = (math.pi / 2, 0.0, 0.0)
    bpy.ops.object.shade_smooth()
    return ob


def build_upper_parts(sfx):
    """上段: 肩甲 + 上臂筒。原点 = 肩, 沿 +Y 长 LEN_UP。"""
    parts = []
    t = _tube_local("UpperArm" + sfx, V_ARM * FP_SCALE, LEN_UP)
    set_material(t, "olive")
    parts.append(t)
    pad = S.sphere("ShoulderPad_" + sfx, V_PAD * FP_SCALE, seg=8, ring=6,
                   loc=(0.0, 0.012 * FP_SCALE, 0.0))
    pad.scale = (1.0, 1.15, 0.9)
    bpy.ops.object.transform_apply(scale=True)
    set_material(pad, "dark")
    parts.append(pad)
    return parts


def build_fore_parts(sfx):
    """中段: 肘球(原点) + 前臂筒。原点 = 肘, 沿 +Y 长 LEN_FORE。"""
    parts = []
    # 肘球放在**前臂几何的中点**, 而不是关节原点 —— 段原点在关节, 若球也放原点,
    # 球会有一半探到上臂那一侧(与上臂筒重叠), 实测 RU/RF 互撞 50 对。
    e = S.sphere("Elbow" + sfx, V_FORE * FP_SCALE * J, seg=8, ring=6,
                 loc=(0.0, (LEN_FORE - WRIST_GAP) * 0.5, 0.0))
    set_material(e, "dark")
    parts.append(e)
    t = _tube_local("Forearm" + sfx, V_FORE * FP_SCALE, LEN_FORE - WRIST_GAP)
    set_material(t, "olive")
    parts.append(t)
    return parts


def build_hand_parts(sfx):
    """末段: 手盒。**原点 = 手心**(手盒居中于原点), 几何沿 +Y。

    ★2026-09-11 修: 旧版把盒中心放在 (0, 0.055*FP_SCALE, 0) —— 即**掌心比原点靠前
      4.4cm**。而 `HAND_ANCHORS` 的注释是"左手贴合护木底部"、旧程序化手
      (`weapon_models.build_hand`) 的原点也就在掌心 ⇒ 掌心前移就等于把整只手
      推进护木里(实测穿模)。改成手盒居中后, 引擎把本段原点对齐锚点 = 掌心落位。
    另: NPC 侧手盒相对腕是 +0.03(极小), 旧值 0.055 是凭空放大的。
    """
    h = S.box("Hand_" + sfx, 0.06 * FP_SCALE, 0.09 * FP_SCALE, 0.05 * FP_SCALE,
              loc=(0.0, 0.0, 0.0))
    set_material(h, "tan")
    return [h]


def finalize(parts, new_name):
    """join 成一个对象。原点已在关节(局部 0), 不需要 origin_set。"""
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = parts[0]
    ob.name = new_name
    # 烘焙各零件自带的旋转(圆柱靠 rotation 才躺到 +Y), 否则外侧改 transform 会走样
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def build_arms():
    """返回 6 段: LU/LF/LH + RU/RF/RH(左右同规格)。"""
    S.reset()
    out = {}
    for sfx in ("L", "R"):
        out[sfx + "U"] = finalize(build_upper_parts(sfx), "FpArm" + sfx + "U")
        out[sfx + "F"] = finalize(build_fore_parts(sfx), "FpArm" + sfx + "F")
        out[sfx + "H"] = finalize(build_hand_parts(sfx), "FpArm" + sfx + "H")
    return out


def render_shots():
    try:
        bpy.context.scene.render.engine = 'BLENDER_EEVEE'
    except Exception:
        pass
    bpy.ops.object.light_add(type='SUN', location=(2, -3, 5))
    bpy.context.active_object.data.energy = 1.9
    bpy.ops.object.light_add(type='AREA', location=(-3, 2, 2))
    al = bpy.context.active_object
    al.data.energy = 150
    al.data.size = 4.0
    if bpy.context.scene.world is None:
        bpy.context.scene.world = bpy.data.worlds.new("W")
    bpy.context.scene.world.use_nodes = True
    bg = bpy.context.scene.world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs['Color'].default_value = (0.30, 0.33, 0.37, 1.0)
        bg.inputs['Strength'].default_value = 0.6
    sc = bpy.context.scene
    sc.render.resolution_x = 1100
    sc.render.resolution_y = 620
    sc.render.film_transparent = False
    views = [("side", Vector((0.95, 0.15, 0.10))),
             ("front", Vector((0.0, 1.05, 0.10))),
             ("quarter", Vector((0.72, -0.62, 0.60)))]
    os.makedirs(SHOT_DIR, exist_ok=True)
    for nm, loc in views:
        cd = bpy.data.cameras.new(nm)
        cd.type = 'ORTHO'
        cd.ortho_scale = 1.05
        cam = bpy.data.objects.new(nm, cd)
        sc.collection.objects.link(cam)
        cam.location = loc
        tgt = Vector((-0.06, 0.06, 0.0))
        cam.rotation_euler = (tgt - loc).to_track_quat('-Z', 'Y').to_euler()
        sc.camera = cam
        sc.render.filepath = os.path.join(SHOT_DIR, "fp_arm_%s.png" % nm)
        bpy.ops.render.render(write_still=True)
        print("[FPARMS] shot", nm)


def main():
    arms = build_arms()
    if "render" in sys.argv:
        # 预览: 把 6 段沿臂排开(平时它们原点都在 0 会重叠), 左右各占一条线
        for sfx, base in (("L", Vector((0.0, 0.0, 0.0))), ("R", Vector((0.30, 0.0, 0.0)))):
            arms[sfx + "U"].location = base
            arms[sfx + "F"].location = base + Vector((0.0, LEN_UP, 0.0))
            arms[sfx + "H"].location = base + Vector((0.0, LEN_UP + LEN_FORE, 0.0))
        bpy.context.view_layer.update()
        render_shots()
        for k in arms:
            arms[k].location = Vector((0.0, 0.0, 0.0))
        bpy.context.view_layer.update()

    v = sum(len(o.data.vertices) for o in arms.values())
    t = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in arms.values())
    print("[FPARMS] v7 左右各三段 x%.2f: 件=%d 顶点=%d 面=%d 上臂=%.4f 前臂=%.4f" % (
        FP_SCALE, len(arms), v, t, LEN_UP, LEN_FORE))

    bpy.context.view_layer.update()
    os.makedirs(MODELS, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB, export_format='GLB', export_apply=True,
        export_yup=True, export_skins=False, export_animations=False)
    print("[FPARMS] 导出完成: %s  %.0f KB" % (OUT_GLB, os.path.getsize(OUT_GLB) / 1024.0))


if __name__ == "__main__":
    main()
