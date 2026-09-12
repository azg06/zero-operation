"""
秋津市全图拼装 v2(tools/blender/assemble_jp_city.py)
直接调用 10 个区的建模函数(几何与分区验收同源, 无 GLB 往返伪影), 平移到绝对坐标渲染。
用法: blender --background --python assemble_jp_city.py -- [render|norender]
产出: shots/akitsu/city_iso.png / city_top.png / city_deploy.png
"""
import sys, os, math, time
import bpy

T0 = time.time()
def LOG(msg):
    line = "[%6.1fs] %s" % (time.time() - T0, msg)
    print(line, flush=True)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_asm_log.txt"), "a", encoding="utf-8") as f:
        f.write(line + "\n")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build_jp_city as B
import jp_common as J

ROOT = "E:/工作目录2/zero/steel_frontline_godot"
SHOT_DIR = ROOT + "/shots/akitsu"

# ZONES 真源: zone_id -> (原点绝对 x, z)  [与 build_jp_city.py 各区注释一致, B6 Godot 端同表]
ZONES = {
    1:  (-300.0, 60.0),
    2:  (-140.0, -120.0),
    3:  (50.0, 170.0),
    4:  (250.0, 340.0),
    5:  (-270.0, 340.0),
    6:  (325.0, -160.0),
    7:  (-80.0, -360.0),
    8:  (200.0, -60.0),
    9:  (0.0, 0.0),
    10: (0.0, 0.0),
}
MARKS = [("A", -300, 60), ("B", 30, 60), ("C", -140, -100), ("D", 230, 310),
         ("E", 340, -120), ("F", 180, -20), ("G", -60, -360), ("H", -260, 330),
         ("US", -430, -420), ("RU", 430, 420)]


def _mat_simple(ob, rgb, rough=0.9):
    name = "asm_%s" % "_".join(str(c) for c in rgb)
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        b.inputs["Roughness"].default_value = rough
    ob.data.materials.clear()
    ob.data.materials.append(m)


def _look_at(cam, tx, ty, tz):
    import mathutils
    fwd = mathutils.Vector((tx, ty, tz)) - cam.location
    fwd.normalize()
    back = -fwd
    up_w = mathutils.Vector((0, 0, 1)) if abs(fwd.z) < 0.98 else mathutils.Vector((0, 1, 0))
    right = fwd.cross(up_w).normalized()
    up = right.cross(fwd).normalized()
    cam.rotation_euler = mathutils.Matrix((right, up, back)).transposed().to_4x4().to_euler()


def assemble():
    # 猴补丁: 跳过每区的 reset(清场) 与 zone_export(join+写 GLB), 保住已建区
    B.reset = lambda: None
    B.zone_export = lambda *a, **k: None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    total = 0
    LOG("开始逐区建模(collection 隔离模式)")
    for zid, (ox, oz) in sorted(ZONES.items()):
        before = set(bpy.data.objects.keys())
        fn = B.BUILDERS["zone%d" % zid]
        fn(render=False)                       # 只建模: 不 join/不导出/不渲染
        new_obs = [o for o in bpy.data.objects if o.name not in before]
        root = bpy.data.objects.new("zone%d_root" % zid, None)
        bpy.context.scene.collection.objects.link(root)
        root.empty_display_size = 3.0
        root.location = (ox, -oz, 0.0)         # Blender 系: x=x, y=-z, z=y
        for o in new_obs:
            if o.parent is None:
                o.parent = root
        # 建完即移入独立 collection 并隐藏: 后续区 ops 的 depsgraph 更新不带 5000+ 旧对象(提速关键)
        coll = bpy.data.collections.new("zone%d" % zid)
        bpy.context.scene.collection.children.link(coll)
        for o in new_obs + [root]:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            coll.objects.link(o)
        coll.hide_viewport = True
        total += len(new_obs)
        LOG("zone%-2d 建完 +%d obj @ (%.0f,%.0f)" % (zid, len(new_obs), ox, oz))
    # 旗点/基地标注杆(红杆+顶球)
    for nm, mx, mz in MARKS:
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.5, depth=26.0,
                                            location=(mx, -mz, 13.0))
        _mat_simple(bpy.context.active_object, (0.85, 0.15, 0.12), 0.6)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.4, segments=12, ring_count=8,
                                             location=(mx, -mz, 27.0))
        _mat_simple(bpy.context.active_object, (0.95, 0.8, 0.1), 0.4)
    for c in bpy.data.collections:
        c.hide_viewport = False                # 渲染前恢复全部可见
    LOG("全部完成, 总对象=%d" % total)
    return total


def render_all():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 32
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    sc.render.image_settings.file_format = 'PNG'
    w = bpy.data.worlds.new("aw")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.52, 0.56, 0.62, 1.0)
    bg.inputs[1].default_value = 1.1
    sun = bpy.data.lights.new("asun", 'SUN')
    sun.energy = 3.2
    sun.angle = math.radians(9)
    so = bpy.data.objects.new("asun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(38), 0, math.radians(40))
    cam = bpy.data.cameras.new("acam")
    cam.clip_start = 1.0
    cam.clip_end = 6000.0
    co = bpy.data.objects.new("acam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    # 1) 高空等轴(全图 45°)
    cam.lens = 42
    co.location = (620, -700, 560)
    _look_at(co, 0, 0, 0)
    LOG("开始渲染 iso"); sc.render.filepath = SHOT_DIR + "/city_iso.png"
    bpy.ops.render.render(write_still=True)
    LOG("city_iso.png 完成")
    # 2) 正射俯视(部署图感; 画面上=南)
    cam.type = 'ORTHO'
    cam.ortho_scale = 1120.0
    co.location = (0, 0, 900)
    _look_at(co, 0, 0.1, 0)
    LOG("开始渲染 top"); sc.render.filepath = SHOT_DIR + "/city_top.png"
    bpy.ops.render.render(write_still=True)
    LOG("city_top.png 完成")
    # 3) 低空斜视(从西南看向市中心)
    cam.type = 'PERSP'
    cam.lens = 35
    co.location = (-520, -760, 260)
    _look_at(co, 30, 60, 10)
    LOG("开始渲染 deploy"); sc.render.filepath = SHOT_DIR + "/city_deploy.png"
    bpy.ops.render.render(write_still=True)
    LOG("city_deploy.png 完成")


if __name__ == "__main__":
    do_render = "norender" not in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    assemble()
    if do_render:
        os.makedirs(SHOT_DIR, exist_ok=True)
        render_all()
