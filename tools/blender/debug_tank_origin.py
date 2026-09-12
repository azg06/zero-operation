# 车底炮塔下沉 bug 二分诊断:
# 1) 跑 build_tank() 2) 打印 Turret 对象 location + 网格数据范围 + 世界范围
# 3) 导出临时 GLB 4) 对比 Godot 端读数
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from gunforge import *  # noqa
from build_vehicle_batch import build_tank, OUT_DIR

build_tank()

t = bpy.data.objects.get("Turret")
if t is None:
    print("[DBG] 没有 Turret 对象! 对象表:", [o.name for o in bpy.data.objects][:30])
else:
    bb = [t.matrix_world @ __import__("mathutils").Vector(c) for c in t.bound_box]
    print("[DBG] Turret location=", tuple(round(v, 3) for v in t.location))
    zs = [v.z for v in bb]
    ys = [v.y for v in bb]
    xs = [v.x for v in bb]
    print("[DBG] Turret 世界范围 Blender: x=[%.3f,%.3f] y=[%.3f,%.3f] z(上)=[%.3f,%.3f]" % (
        min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
    vs = t.data.vertices
    vz = [v.co.z for v in vs]
    vy = [v.co.y for v in vs]
    print("[DBG] Turret 网格数据(相对origin) 顶点数=%d z(上)=[%.3f,%.3f] y=[%.3f,%.3f]" % (
        len(vs), min(vz), max(vz), min(vy), max(vy)))
    print("[DBG] Turret parent=", t.parent.name if t.parent else None)

out = "E:/工作目录2/models_probe/tank_debug.glb"
export_glb(out)
print("[DBG] 已导出: ", out)
