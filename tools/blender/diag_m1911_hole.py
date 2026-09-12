"""诊断 m1911 长方形镂空:打印包围盒 + 网格非流形检查 + 多特写渲染。
用法: blender --background --python diag_m1911_hole.py
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
src = open(os.path.join(HERE, "build_pistol_batch.py"), encoding="utf-8").read()
src = src.replace('if __name__ == "__main__":\n    main()', '')
exec(src)

from gunforge import *  # noqa

build_m1911()

# ---- 1. 所有顶层对象的包围盒(Godot 语义坐标打印) ----
print("=" * 70)
print("TOP-LEVEL OBJECT BBOX (Godot coords: x=左右 y=上下 z=前后, +z=枪尾)")
print("=" * 70)
for ob in bpy.data.objects:
    if ob.parent is not None:
        continue
    mw = ob.matrix_world
    corners = [mw @ __import__("mathutils").Vector(c) for c in ob.bound_box]
    xs = [c.x for c in corners]; ys = [c.y for c in corners]; zs = [c.z for c in corners]
    # Blender world -> Godot: (x, z, -y)
    print("%-16s G-x[%7.4f,%7.4f] G-y[%7.4f,%7.4f] G-z[%7.4f,%7.4f] tris=%d" % (
        ob.name, min(xs), max(xs), min(zs), max(zs), -max(ys), -min(ys),
        len(ob.data.polygons) if ob.type == "MESH" else -1))

# ---- 2. Slide 网格有效性 ----
print("=" * 70)
slide = bpy.data.objects.get("Slide")
if slide:
    me = slide.data
    print("Slide verts=%d polys=%d" % (len(me.vertices), len(me.polygons)))
    # 非流形边统计
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    print("Slide non-manifold edges = %d" % non_manifold)
    bm.free()

# ---- 3. 特写渲染 ----
exec(open(os.path.join(HERE, "render_preview.py"), encoding="utf-8").read()
     .replace('if __name__ == "__main__":', 'if False:'))
OUT = "E:/工作目录2/models_probe"
VIEWS = [
    ("zright",  (0, 0.00, -0.02), 0.42, (0, 0, -90)),    # 右侧正视(Godot -x 方向看)
    ("zleft",   (0, 0.00, -0.02), 0.42, (0, 0, 90)),     # 左侧正视
    ("zrear",   (0, 0.00, 0.02),  0.42, (-8, 0, 180)),   # 正后方
    ("zfront",  (0, 0.00, -0.02), 0.42, (-8, 0, 0)),     # 正前方
    ("ztop",    (0, 0.00, -0.02), 0.42, (88, 0, 0)),     # 俯视
    ("zhero3q", (0, 0.01, 0.00),  0.40, (-25, 0, 140)),  # 右后 3/4 特写
]
for tag, tgt, dist, ang in VIEWS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    exec(src)
    build_m1911()
    setup_scene()
    setup_camera(target=tgt, dist=dist, angle=ang, lens=60)
    render(os.path.join(OUT, "diag1911_%s.png" % tag), res=(800, 500))
    print("SHOT", tag)
print("DONE")
