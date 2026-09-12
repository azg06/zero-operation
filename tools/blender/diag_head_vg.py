# -*- coding: utf-8 -*-
"""定位眼位附近 5cm 内的顶点:打印其绑定骨权重 + 缩放覆盖前后的变形 AABB。"""
import sys
import bpy
import math
from mathutils import Vector

ROOT = "E:/工作目录2/zero/steel_frontline_godot"
EYE = (0.0, 1.70, 0.0)
HIDE = ["Head", "Neck", "ShoulderL", "ShoulderR",
        "UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "HandL", "HandR"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=ROOT + "/models/soldiers/soldier_assault.glb")
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")


def deformed():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    out = []
    for v in me.vertices:
        w = mw @ v.co
        out.append((w.x, w.z, -w.y))     # → Godot 语义
    cols = [tuple(me.color_attributes[0].data[i].color) for i in range(len(me.vertices))] \
        if len(me.color_attributes) else None
    ev.to_mesh_clear()
    return out, cols


def aabb(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; zs = [p[2] for p in pts]
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


act = bpy.data.actions.get("Idle")
arm.animation_data_create()
arm.animation_data.action = act
bpy.context.scene.frame_set(0)

pts, cols = deformed()
print("[DIAG] 未加覆盖 AABB  x[%.3f..%.3f] y[%.3f..%.3f] z[%.3f..%.3f]" % aabb(pts))

for b in HIDE:
    pb = arm.pose.bones.get(b)
    if pb:
        pb.scale = (0.01, 0.01, 0.01)
bpy.context.view_layer.update()
pts2, cols2 = deformed()
print("[DIAG] 加覆盖后  AABB  x[%.3f..%.3f] y[%.3f..%.3f] z[%.3f..%.3f]" % aabb(pts2))

# 眼位 8cm 球内的顶点:部位 + 权重
groups = {g.index: g.name for g in mesh.vertex_groups}
hits = {}
for i, p in enumerate(pts2):
    d = math.dist(p, EYE)
    if d < 0.09:
        pid = int(round(cols2[i][0] * 10.0)) if cols2 else 0
        w = sorted(((groups[g.group], round(g.weight, 3)) for g in mesh.data.vertices[i].groups),
                   key=lambda t: -t[1])[:3]
        key = (pid, tuple(n for n, _ in w))
        hits.setdefault(key, [0, 1e9, None])
        hits[key][0] += 1
        if d < hits[key][1]:
            hits[key][1] = d
            hits[key][2] = (pts2[i], w)
print("[DIAG] 眼位 9cm 内顶点分组 (共 %d 个):" % sum(v[0] for v in hits.values()))
for k, v in sorted(hits.items(), key=lambda kv: kv[1][1]):
    print("   parts=%s  骨权重=%s  数量=%d  最近=%.3fm  @Godot(%.2f, %.2f, %.2f)" % (
        k[0], k[1], v[0], v[1], v[2][0][0], v[2][0][1], v[2][0][2]))
