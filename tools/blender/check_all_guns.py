"""
批量核对 —— 每把枪的"左肩→护木"距离是否落在手臂 IK 可及区间内。

背景: 左臂用 2-bone IK 去够各枪自己的左手锚点(护木), 臂长固定(左上臂 0.2655 +
左前臂 0.3535 = 0.619)。若某把枪的护木离左肩太远(>0.615)或太近(<0.108), IK 会被
三角不等式钳制 ⇒ 手臂拉直/折叠, 看起来就不像"扶着护木"。本脚本逐把枪报距离,
把超范围的挑出来。

用法:
    blender --background --python check_all_guns.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import build_fp_arms as A  # noqa: E402

WEAPONS = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"
L1, L2 = A.LEN_UP_L, A.LEN_FORE_L
LO, HI = abs(L1 - L2) + 0.02, L1 + L2 - 0.004
OFF = Vector((-0.26, 0.02, 0.02))       # 左肩相对右手腕(Blender 空间)


def bbox():
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


def find(*keys):
    for o in bpy.data.objects:
        nm = o.name.lower()
        if any(k in nm for k in keys):
            return o.matrix_world.translation.copy()
    return None


def main():
    guns = sorted(f[:-4] for f in os.listdir(WEAPONS) if f.endswith(".glb"))
    print("[CHK] 臂长 上=%.4f 前=%.4f ⇒ 可及区间 (%.3f, %.3f), 共 %d 把" % (
        L1, L2, LO, HI, len(guns)))
    bad = []
    est = []
    for g in guns:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        try:
            bpy.ops.import_scene.gltf(filepath=os.path.join(WEAPONS, g + ".glb"))
        except Exception as e:
            print("[CHK] !! %-10s 导入失败: %s" % (g, e))
            continue
        grip = find("grip")
        guard = find("handguard", "foregrip")
        mn, mx = bbox()
        eg = eh = False
        if grip is None:
            grip = Vector((0.0, mn.y + (mx.y - mn.y) * 0.22, mn.z + (mx.z - mn.z) * 0.35))
            eg = True
        if guard is None:
            guard = Vector((0.0, mn.y + (mx.y - mn.y) * 0.55, mn.z + (mx.z - mn.z) * 0.45))
            eh = True
        reach = (guard - (grip + OFF)).length
        ok = LO < reach < HI
        if not ok:
            bad.append((g, round(reach, 3)))
        if eg or eh:
            est.append((g, eg, eh))
        print("[CHK] %s %-9s 握把→护木=%6.3f  肩→护木=%6.3f%s%s" % (
            "OK" if ok else "!!", g, (guard - grip).length, reach,
            "  [估握把]" if eg else "", "  [估护木]" if eh else ""))
    print("[CHK] ---- 汇总 ----")
    print("[CHK] 超出可及范围: %d 把 %s" % (len(bad), bad))
    print("[CHK] 靠包围盒估算锚点的: %d 把 %s" % (len(est), est))


if __name__ == "__main__":
    main()
