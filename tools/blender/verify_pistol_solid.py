"""滑套完整性光线验证 v2(修正坐标系):
Blender 世界空间 = (godot_x, -godot_z, godot_y)。采样在 Godot 语义里做,
逐点换算成 Blender 世界坐标再投射,杜绝空间混用。
对 5 把半自动手枪的 Slide 两侧打网格光线:完全打穿(不见任何网格)= 破洞;
命中 ChamberBlock(抛壳窗内节套)或 Slide(窗内壁)视为合法。
用法: blender --background --python verify_pistol_solid.py
"""
import sys, os, math
import mathutils
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
src = open(os.path.join(HERE, "build_pistol_batch.py"), encoding="utf-8").read()
src = src.replace('if __name__ == "__main__":\n    main()', '')
exec(src)

NY, NZ = 11, 28

def g2bw(p):
    """Godot 语义点 -> Blender 世界点"""
    return mathutils.Vector((p[0], -p[2], p[1]))

def ray_hit(origin_g, direction_g):
    """在 Godot 语义空间投射,返回 (dist, obj_name) 或 None"""
    o = g2bw(origin_g)
    d = g2bw(direction_g).normalized()
    best = None
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        imw = mw.inverted()
        o_l = imw @ o
        d_l = (imw.to_3x3() @ d)
        if d_l.length < 1e-9:
            continue
        ok, loc, nrm, idx = ob.ray_cast(o_l, d_l.normalized())
        if ok:
            w = mw @ loc
            dist = (w - o).length
            if best is None or dist < best[0]:
                best = (dist, ob.name)
    return best

print("=" * 74)
for wid in ["m1911", "g17", "p226", "deagle", "m93r"]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    exec(src)
    build_pistol_spec(wid)
    bpy.context.view_layer.update()
    c = SPEC[wid]
    sw, sh, sl = c["slide_w"], c["slide_h"], c["slide_len"]
    sy, sz = c["slide_y"], c["slide_z"]
    z0, z1 = sz - sl * 0.5 + 0.002, sz + sl * 0.5 - 0.002
    y0, y1 = sy - sh * 0.5 + 0.002, sy + sh * 0.5 - 0.002
    leaks = []
    n_hit = 0
    for side in (1.0, -1.0):
        for iz in range(NZ):
            z = z0 + (z1 - z0) * (iz + 0.5) / NZ
            for iy in range(NY):
                y = y0 + (y1 - y0) * (iy + 0.5) / NY
                hit = ray_hit((side * 0.10, y, z), (-side, 0, 0))
                if hit is None:
                    leaks.append((side, y, z))
                else:
                    n_hit += 1
    status = "OK" if not leaks else "LEAK x%d (hit=%d)" % (len(leaks), n_hit)
    print("%-7s Slide 光线验证: %s" % (wid, status))
    for lk in leaks[:10]:
        print("   LEAK side=%+d y=%.4f z=%.4f" % lk)
print("=" * 74)
