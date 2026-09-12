"""
手臂穿模定量检测 —— 逐把枪检查"手臂是否与枪身相交"。

为什么需要它
------------
`render_fp_hold.py` 出的是**正交侧视图**, 前后方向的重叠看不出来(前臂在枪的
正下方 vs 插进枪里, 侧视投影一模一样)。而"手托护木"本来就有**轻微接触**,
靠肉眼分不清"贴合"和"穿进去"。

做法
----
把手臂 6 段与枪的全部网格都建成**世界坐标**的 `BVHTree`, 两两求 `overlap()` ——
返回**真正相交的三角形对**。0 = 干净; 个位数 = 轻微接触; 几十上百 = 明显穿模。

★踩坑: `BVHTree.FromObject` 建的是**局部坐标**的树 —— 直接拿两条在不同位置的
  手臂/枪去 overlap, 会得到上万对"相交"(其实只是各自局部原点附近重叠), 完全不可用。
  必须自己把顶点乘 matrix_world 再用 `FromPolygons` 建。

用法
----
    blender --background --python check_hand_clip.py            # 全部 55 把
    blender --background --python check_hand_clip.py -- m4 m249 # 指定几把
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402
import build_soldier as S  # noqa: E402
import build_fp_arms as A  # noqa: E402
import render_fp_hold as H  # noqa: E402

WEAPONS = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"

CLIP_LIMIT = 5          # 臂段(上臂/前臂)与枪相交 >= 此值判定为"穿模"
# 手(RH/LH)与枪相交是**设计使然** —— 手掌本来就包住握把/托住护木, 几何必然重叠。
# 所以手单独用一个宽松上限, 只看它是不是"整只手插进枪里"。
HAND_LIMIT = 400
SEGS = ("RU", "RF", "RH", "LU", "LF", "LH")
ARM_SEGS = ("RU", "RF", "LU", "LF")     # 这两段绝不该碰到枪
HAND_SEGS = ("RH", "LH")


def gun_ids():
    if "--" in sys.argv:
        rest = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("-")]
        if rest:
            return rest
    return sorted(f[:-4] for f in os.listdir(WEAPONS) if f.endswith(".glb"))


def gun_bbox():
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for o in bpy.data.objects:
        if o.type != 'MESH' or o.name.startswith("FpArm"):
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return Vector(mn), Vector(mx)


def tree_of(objs, dg, cut_center=None, cut_radius=0.0):
    """把若干对象的(已应用修改器的)网格拼成**世界坐标**的 BVH。

    `cut_center`/`cut_radius`: 跳过重心落在该球内的三角形 —— 用来**排除"手所在的
    那一小块区域"**。手本来就包住握把/托住护木, 那段重叠是设计使然; 我们想知道的
    是"手臂**主体**有没有穿枪"。
    """
    verts = []
    polys = []
    base = 0
    cc = None
    r2 = cut_radius * cut_radius
    if cut_center is not None and cut_radius > 0.0:
        cc = Vector(cut_center)
    for ob in objs:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ob.matrix_world
        vs = [mw @ v.co for v in me.vertices]
        verts.extend(vs)
        for p in me.polygons:
            idx = tuple(base + i for i in p.vertices)
            if cc is not None:
                c = Vector((0.0, 0.0, 0.0))
                for i in idx:
                    c += verts[i]
                c /= len(idx)
                if (c - cc).length_squared < r2:
                    continue                        # 手部区域, 跳过
            polys.append(idx)
        base += len(me.vertices)
        ev.to_mesh_clear()
    if not polys:
        return None
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)


def check_one(gun_id, anchors):
    path = os.path.join(WEAPONS, gun_id + ".glb")
    if not os.path.exists(path):
        return None
    S.reset()
    arms = A.build_arms()
    bpy.ops.import_scene.gltf(filepath=path)
    # ★必须排除手臂自身 —— 否则 gun_objs 会把 FpArm* 也算成"枪零件",
    #   臂段与自己重叠被当成穿模(实测报告出 RU→[FpArmRU:91] 这种自相交)。
    gun_objs = [o for o in bpy.data.objects
                if o.type == 'MESH' and not o.name.startswith("FpArm")]
    mn, mx = gun_bbox()

    anch = anchors.get(gun_id)
    if anch is None:
        grip = H.find_node("grip")
        guard = H.find_node("handguard", "foregrip")
        if grip is None:
            grip = Vector((0.0, mn.y + (mx.y - mn.y) * 0.22, mn.z + (mx.z - mn.z) * 0.35))
        if guard is None:
            guard = Vector((0.0, mn.y + (mx.y - mn.y) * 0.55, mn.z + (mx.z - mn.z) * 0.45))
    else:
        grip, guard = anch

    H.pose_arms(arms, grip, guard)
    bpy.context.view_layer.update()

    dg = bpy.context.evaluated_depsgraph_get()
    gun_tree = tree_of(gun_objs, dg)

    report = {}
    HAND_ZONE = 0.09            # 手心周围 9cm 视为"手部区域"
    for key in SEGS:
        hand_pt = grip if key.startswith("R") else guard
        t = tree_of([arms[key]], dg, cut_center=hand_pt, cut_radius=HAND_ZONE)
        n = 0
        hits = []
        if t is not None:
            if gun_tree is not None:
                n = len(t.overlap(gun_tree))
            if n >= CLIP_LIMIT:                     # 超阈值才逐零件定位, 省时间
                for o in gun_objs:
                    gt = tree_of([o], dg)
                    if gt is None:
                        continue
                    c = len(t.overlap(gt))
                    if c:
                        hits.append((o.name, c))
                hits.sort(key=lambda x: -x[1])
        report[key] = (n, hits)

    for o in gun_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in list(bpy.data.objects):
        if o.name.startswith("FpArm"):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.update()
    return report


def main():
    ids = gun_ids()
    anchors = H.load_anchors()
    print("[CLIP] 待检 %d 把; 判定阈值 = 臂段(上臂/前臂) >= %d, 手(包住握把属正常) >= %d"
          % (len(ids), CLIP_LIMIT, HAND_LIMIT))
    bad = []
    for gid in ids:
        rep = check_one(gid, anchors)
        if rep is None:
            continue
        worst = max(rep[k][0] for k in SEGS)
        bad_arm = max(rep[k][0] for k in ARM_SEGS) >= CLIP_LIMIT
        bad_hand = max(rep[k][0] for k in HAND_SEGS) >= HAND_LIMIT
        flag = "!!" if (bad_arm or bad_hand) else "OK"
        detail = " ".join("%s=%d" % (k, rep[k][0]) for k in SEGS)
        hits_all = []
        for k in SEGS:
            if rep[k][0] >= CLIP_LIMIT:
                top = ", ".join("%s:%d" % (n, c) for n, c in rep[k][1][:3])
                hits_all.append("%s→[%s]" % (k, top))
        where = ("  ← " + " ".join(hits_all)) if hits_all else ""
        print("[CLIP] %s %-8s 最大=%-5d %s%s" % (flag, gid, worst, detail, where))
        if flag == "!!":
            bad.append(gid)
    print("[CLIP] ==== 结论: 穿模 %d 把 %s" % (len(bad), bad if bad else "无"))


if __name__ == "__main__":
    main()
