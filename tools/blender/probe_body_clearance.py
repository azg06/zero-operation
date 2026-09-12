# -*- coding: utf-8 -*-
"""第一人称身体穿模量化 v3(修正版)
- 每帧 frame_set 之后重新施加 pose 覆盖(动画含 scale 通道,会冲掉一次性覆盖)
- 可配置 眼高 / 身体后移 / 胸腔下压,直接对比"现状 vs 修复方案"
主相机 near=0.08 ⇒ 视深 <0.08 的可见面被裁掉 = 穿模。
用法: blender.exe --background --python probe_body_clearance.py -- <项目根>
"""
import sys
import bpy
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = argv[0] if argv else "E:/工作目录2/zero/steel_frontline_godot"

CLASSES = ["assault", "support", "recon"]
ANIMS = ["Idle", "Walk", "Run", "Crouch", "CrouchWalk", "Prone"]
HIDE = ["Head", "Neck", "ShoulderL", "ShoulderR",
        "UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "HandL", "HandR"]
PITCHES = [0.0, -0.30, -0.50, -0.80, -1.05, -1.35]
ASPECT = 2560.0 / 1600.0
TAN_V = math.tan(math.radians(75.0 * 0.5))
NEAR = 0.08
SAFE = 0.12
PART = {1: "uniform", 2: "vest", 3: "helmet", 4: "gear", 5: "skin",
        6: "boot", 7: "accent", 8: "gear2", 0: "?"}

# (标签, 眼高, 身体后移, 胸腔下压)
CASES = [
    ("现状  eye1.70 B0      ", 1.70, 0.00, 0.00),
    ("方案  eye1.70 B0 胸-15", 1.70, 0.00, -0.15),
    ("方案  eye1.70 B.06胸-15", 1.70, 0.06, -0.15),
]


def apply_overrides(arm, chest_dz):
    for b in HIDE:
        pb = arm.pose.bones.get(b)
        if pb is not None:
            pb.scale = (0.01, 0.01, 0.01)
    cb = arm.pose.bones.get("Chest")
    if cb is not None:
        cb.scale = (1.0, 1.0, 1.0)
        rest = cb.bone.matrix_local.to_translation()
        cb.location = (0.0, chest_dz, 0.0)   # 骨局部系(沿骨方向为 Y,向下≈-Y)


def min_depth(verts, colors, eye, backoff, pitch):
    c = Vector((0.0, eye, -backoff))
    d = Vector((0.0, math.sin(pitch), -math.cos(pitch)))
    up = Vector((1.0, 0.0, 0.0)).cross(d)
    best = (1e9, "?", None)
    for i, v in enumerate(verts):
        rel = Vector(v) - c
        dep = rel.dot(d)
        if dep <= 0.0:
            continue
        if abs(rel.dot(up)) > dep * TAN_V * 1.05:
            continue
        if abs(rel.x) > dep * TAN_V * ASPECT * 1.05:
            continue
        if dep < best[0]:
            pid = int(round(colors[i][0] * 10.0)) if colors else 0
            best = (dep, PART.get(pid, "?"), Vector(v))
    return best


print("\n================ FP BODY CLEARANCE v3 ================")
print("near=%.2f 安全线=%.2f 俯角(°) %s" % (NEAR, SAFE, [round(math.degrees(p)) for p in PITCHES]))
for cls in CLASSES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath="%s/models/soldiers/soldier_%s.glb" % (ROOT, cls))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    acts = {a.name: a for a in bpy.data.actions}
    arm.animation_data_create()
    print("\n### %s" % cls)
    for an in ANIMS:
        act = acts.get(an)
        if act is None:
            continue
        arm.animation_data.action = act
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        step = max(1, (f1 - f0) // 8)
        for label, eye, back, cdz in CASES:
            agg = {p: (1e9, "?", None) for p in PITCHES}
            for f in range(f0, f1 + 1, step):
                bpy.context.scene.frame_set(f)
                apply_overrides(arm, cdz)          # ★ 每帧重施(动画会冲掉)
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                ev = mesh.evaluated_get(dg)
                me = ev.to_mesh()
                mw = ev.matrix_world
                verts = []
                for v in me.vertices:
                    w = mw @ v.co
                    verts.append((w.x, w.z, -w.y))
                colors = None
                if len(me.color_attributes) > 0:
                    ca = me.color_attributes[0]
                    colors = [tuple(ca.data[i].color) for i in range(len(me.vertices))]
                for p in PITCHES:
                    r = min_depth(verts, colors, eye, back, p)
                    if r[0] < agg[p][0]:
                        agg[p] = r
                ev.to_mesh_clear()
            line = "  %-11s %s" % (an, label)
            for p in PITCHES:
                md, part, pos = agg[p]
                if md > 1e8:
                    line += " | --"
                else:
                    line += " | %.3f%s" % (md, "!" if md < NEAR else ("~" if md < SAFE else " "))
            worst = min(agg.values(), key=lambda t: t[0])
            print(line + ("   最差=%.3f @%s" % (worst[0], worst[1]) if worst[0] < 1e8 else ""))
print("\n(! = 视深<near → 会被裁掉穿模; ~ = 余量<0.12m)\n================ DONE ================")
