"""
地图道具库批次:精细小物件/植被 GLB(替换棒棒糖树/灰色团块/无名方块)
产出 models/props/{id}.glb —— 单一合并网格、多材质槽,Godot 侧按材质名重贴 PBR。

模型清单:
    pine          云杉(三层锥冠+锥干,雪地/夜山边界环)
    broadleaf     阔叶树(弯曲干+五团树冠,丛林/河谷/城市)
    palm          棕榈(弯干+八叶,码头)
    wreck_sedan   焚毁轿车残骸(掀盖/爆胎圈/锈蚀)
    wreck_truck   焚毁卡车残骸(敞货厢)
    barrel        锈蚀油桶(双箍+注油盖)
    crate         军绿木箱(角柱+板条框)
    sandbag       沙袋墙(三行错缝)
    boulder       花岗岩巨石(不规则扰动)
    barrier       水泥隔离墩(梯形剖面)

坐标:根在地面 y=0,前方 -Z,单位米。
用法: blender --background --python build_props_batch.py [-- pine palm ...]
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/props"
random.seed(20260905)


def _m(ob, name):
    """按名字打占位材质(GLB 携带材质名,Godot 侧重贴 PBR)"""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def _ico(name, r, pos_g, subdiv=1, jitter=0.0):
    """低细分icosphere + 顶点扰动(有机形体:树冠/岩石)"""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r,
                                          location=g2b(pos_g))
    ob = bpy.context.active_object
    ob.name = name
    if jitter > 0.0:
        random.seed(hash(name) & 0xFFFF)
        for v in ob.data.vertices:
            v.co += v.normal * random.uniform(-jitter, jitter)
    return ob


def _finish(name, parts, mat_rules):
    """按规则前缀给部件打材质名,再合并为单一多材质槽网格(利于 MultiMesh 批绘)"""
    by_name = {}
    for ob in parts:
        by_name[ob.name] = ob
    for key, mname in mat_rules:
        for ob_name, ob in by_name.items():
            if ob_name.startswith(key):
                _m(ob, mname)
    joined = join_parts(name, parts)
    return joined


# ============================================================ 云杉
def build_pine():
    reset()
    trunk = add_cyl("_Trunk", 0.16, 2.4, (0, 1.2, 0), axis="y", seg=8, taper=0.55, bevel=0.0)
    tiers = []
    cfg = [(2.1, 2.0, 1.5), (1.62, 1.9, 2.9), (1.14, 1.8, 4.2), (0.66, 1.7, 5.35)]
    for i, (r, h, y) in enumerate(cfg):
        tiers.append(add_cyl("_Tier%d" % i, r, h, (0, y, 0), axis="y", seg=9, taper=0.02))
    parts = [trunk] + tiers
    rules = [("_Trunk", "bark")] + [("_Tier%d" % i, "leaf_pine") for i in range(4)]
    return _finish("Prop_pine", parts, rules)


# ============================================================ 阔叶树
def build_broadleaf():
    reset()
    trunk = add_cyl("_Trunk", 0.22, 2.8, (0, 1.4, 0), axis="y", seg=8, taper=0.45, bevel=0.0)
    b1 = add_cyl("_Branch1", 0.10, 1.3, (0.42, 2.9, 0.1), axis="y", seg=6, taper=0.5)
    b1.rotation_euler = rot_g2b((0, 0, 0.55))
    b2 = add_cyl("_Branch2", 0.09, 1.2, (-0.40, 3.0, -0.15), axis="y", seg=6, taper=0.5)
    b2.rotation_euler = rot_g2b((0.15, 0, -0.60))
    blobs = [
        ("_Crown0", 1.55, (0.0, 4.3, 0.0)),
        ("_Crown1", 1.15, (1.05, 3.75, 0.25)),
        ("_Crown2", 1.05, (-1.0, 3.85, -0.3)),
        ("_Crown3", 0.95, (0.35, 3.9, 1.0)),
        ("_Crown4", 0.90, (-0.3, 4.5, -0.55)),
    ]
    crowns = [_ico(n, r, p, subdiv=2, jitter=0.16) for n, r, p in blobs]
    parts = [trunk, b1, b2] + crowns
    rules = [("_Trunk", "bark"), ("_Branch", "bark")] + [(n, "leaf") for n, _, _ in blobs]
    return _finish("Prop_broadleaf", parts, rules)


# ============================================================ 棕榈
def build_palm():
    reset()
    parts = []
    segs = 7
    lean = 0.16
    for i in range(segs):
        t = i / float(segs - 1)
        x = lean * t * t * 3.2
        y = 0.35 + t * 4.2
        r = 0.16 * (1.0 - t * 0.45)
        seg = add_cyl("_Trunk%d" % i, r, 0.66, (x, y, 0), axis="y", seg=7, bevel=0.0)
        seg.rotation_euler = rot_g2b((0, 0, -lean * t * 1.9))
        parts.append(seg)
    top = (lean * 3.2, 4.75, 0)
    fronds = []
    for k in range(8):
        a = k * math.tau / 8.0 + 0.3
        frond = add_box("_Frond%d" % k, (0.30, 0.045, 2.15),
                        (top[0] + math.sin(a) * 0.95, top[1] - 0.16, math.cos(a) * 0.95), bevel=0.0)
        frond.rotation_euler = rot_g2b((-0.42, a + math.pi / 2.0, 0))
        parts.append(frond)
        fronds.append("_Frond%d" % k)
    rules = [("_Trunk", "bark_palm")] + [(n, "leaf_palm") for n in fronds]
    return _finish("Prop_palm", parts, rules)


# ============================================================ 焚毁轿车残骸
def build_wreck_sedan():
    reset()
    parts = [
        add_box("_Body", (1.78, 0.52, 4.35), (0, 0.52, 0), bevel=0.055),
        add_box("_Cabin", (1.64, 0.50, 2.05), (0, 1.02, 0.22), bevel=0.05),
        # 掀开的引擎盖(前倾搭在挡风位置)
        add_box("_Hood", (1.66, 0.05, 1.15), (0, 1.18, -1.62), bevel=0.01, rot_g=(0.85, 0, 0.06)),
        # 翘起的后备箱盖
        add_box("_TrunkLid", (1.62, 0.05, 0.95), (0, 1.05, 2.02), bevel=0.01, rot_g=(-0.7, 0, -0.05)),
        # 爆胎轮毂圈 ×4
    ]
    for sx, sz, nm in ((-0.82, -1.42, "FL"), (0.82, -1.42, "FR"), (-0.82, 1.45, "RL"), (0.82, 1.45, "RR")):
        parts.append(add_cyl("_Rim%s" % nm, 0.30, 0.22, (sx, 0.30, sz), axis="x", seg=10, bevel=0.0))
    # 车窗全无(镂空)——座舱顶留开口观感靠材质
    rules = [("_Body", "rust_burnt"), ("_Cabin", "rust_burnt"), ("_Hood", "rust_burnt"),
             ("_TrunkLid", "rust_burnt"), ("_Rim", "metal_burnt")]
    joined = _finish("Prop_wreck_sedan", parts, rules)
    _set_origin(joined, (0, 0, 0)) if False else None
    return joined


# ============================================================ 焚毁卡车残骸
def build_wreck_truck():
    reset()
    parts = [
        add_box("_Cab", (2.10, 1.30, 1.90), (0, 1.28, -2.05), bevel=0.05),
        add_box("_BedFloor", (2.14, 0.10, 3.60), (0, 0.78, 0.85), bevel=0.01),
        add_box("_BedSideL", (0.08, 0.52, 3.60), (-1.05, 1.08, 0.85), bevel=0.01),
        add_box("_BedSideR", (0.08, 0.52, 3.60), (1.05, 1.08, 0.85), bevel=0.01),
        add_box("_BedGate", (2.14, 0.52, 0.08), (0, 1.08, 2.62), bevel=0.01),
        # 翘起的驾驶室门
        add_box("_CabDoor", (0.06, 0.95, 0.85), (1.10, 1.05, -1.35), bevel=0.01, rot_g=(0, 0, -1.15)),
    ]
    for sx, sz, nm in ((-0.95, -2.05, "F"), (0.95, -2.05, "F2"), (-0.95, 0.6, "M"), (0.95, 0.6, "M2"), (-0.95, 2.35, "R"), (0.95, 2.35, "R2")):
        parts.append(add_cyl("_Rim%s" % nm, 0.36, 0.24, (sx, 0.36, sz), axis="x", seg=10, bevel=0.0))
    rules = [("_Cab", "rust_burnt"), ("_Bed", "rust_burnt"), ("_CabDoor", "rust_burnt"),
             ("_Rim", "metal_burnt")]
    return _finish("Prop_wreck_truck", parts, rules)


# ============================================================ 锈蚀油桶
def build_barrel():
    reset()
    parts = [
        add_cyl("_Body", 0.34, 0.94, (0, 0.47, 0), axis="y", seg=14, bevel=0.012),
        add_cyl("_Rib1", 0.355, 0.035, (0, 0.28, 0), axis="y", seg=14, bevel=0.0),
        add_cyl("_Rib2", 0.355, 0.035, (0, 0.66, 0), axis="y", seg=14, bevel=0.0),
        add_cyl("_Lid", 0.30, 0.02, (0, 0.945, 0), axis="y", seg=14, bevel=0.0),
        add_cyl("_Cap", 0.075, 0.03, (0.13, 0.955, 0.1), axis="y", seg=8, bevel=0.0),
    ]
    rules = [("_Body", "rust"), ("_Rib", "rust_dark"), ("_Lid", "rust"), ("_Cap", "metal_burnt")]
    return _finish("Prop_barrel", parts, rules)


# ============================================================ 军绿木箱
def build_crate():
    reset()
    w, h, d = 0.78, 0.62, 0.56
    parts = [
        add_box("_Panel", (w, h, d), (0, h / 2.0, 0), bevel=0.004),
    ]
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(add_box("_Post%d%d" % (sx, sz), (0.07, h + 0.03, 0.07),
                                 (sx * (w / 2.0 - 0.035), h / 2.0, sz * (d / 2.0 - 0.035)), bevel=0.002))
    for y2 in (0.07, h - 0.07):
        for sz in (-1, 1):
            parts.append(add_box("_RailZ%d%d" % (int(y2 * 100), sz), (w, 0.09, 0.05),
                                 (0, y2, sz * (d / 2.0 - 0.02)), bevel=0.002))
    rules = [("_Panel", "wood_olive"), ("_Post", "wood_dark"), ("_Rail", "wood_dark")]
    return _finish("Prop_crate", parts, rules)


# ============================================================ 沙袋墙
def build_sandbag():
    reset()
    parts = []
    rows = [(4, 0.0), (4, 0.26), (3, 0.52)]
    for ri, (n, y) in enumerate(rows):
        for i in range(n):
            x = (i - (n - 1) / 2.0) * 0.46 + (0.11 if ri % 2 == 1 else 0.0)
            bag = add_cyl("_Bag%d_%d" % (ri, i), 0.155, 0.44, (x, y + 0.12, 0), axis="x", seg=9, bevel=0.05)
            bag.rotation_euler = rot_g2b((0, math.radians(random.uniform(-7, 7)), 0))
            parts.append(bag)
    rules = [("_Bag", "sandbag")]
    return _finish("Prop_sandbag", parts, rules)


# ============================================================ 花岗岩巨石
def build_boulder():
    reset()
    a = _ico("_Rock0", 0.95, (0, 0.52, 0), subdiv=2, jitter=0.20)
    a.scale = gsz((1.35, 0.78, 1.05))
    b = _ico("_Rock1", 0.45, (0.75, 0.28, 0.35), subdiv=2, jitter=0.22)
    parts = [a, b]
    rules = [("_Rock", "rock")]
    return _finish("Prop_boulder", parts, rules)


# ============================================================ 水泥隔离墩
def build_barrier():
    reset()
    parts = [
        add_box("_Base", (0.64, 0.10, 2.30), (0, 0.05, 0), bevel=0.006),
        add_box("_Mid", (0.46, 0.34, 2.30), (0, 0.27, 0), bevel=0.008),
        add_box("_Top", (0.24, 0.46, 2.30), (0, 0.67, 0), bevel=0.010),
    ]
    rules = [("_Base", "concrete"), ("_Mid", "concrete"), ("_Top", "concrete")]
    return _finish("Prop_barrier", parts, rules)


# ============================================================ 螺旋桨侦察机(沙漠机场停机坪)
def build_plane():
    reset()
    # 上单翼撑杆式侦察机(总长 6.4m,翼展 8.6m,机首朝 -z)
    parts = [
        # 机身:主筒 + 收腰尾锥(两段圆柱)
        add_cyl("_Fuselage", 0.52, 4.0, (0, 1.05, 0.10), axis="z", seg=14, bevel=0.03),
        add_cyl("_TailCone", 0.30, 2.0, (0, 1.12, 2.85), axis="z", seg=12, bevel=0.02),
        # 引擎罩 + 螺旋桨整流锥 + 双叶桨
        add_cyl("_Nose", 0.44, 0.95, (0, 1.05, -2.15), axis="z", seg=14, bevel=0.02),
        add_cyl("_Spinner", 0.13, 0.30, (0, 1.05, -2.72), axis="z", seg=10, bevel=0.01),
        add_box("_PropBladeV", (0.05, 2.35, 0.17), (0, 1.05, -2.64), bevel=0.006),
        add_box("_PropBladeH", (2.35, 0.05, 0.17), (0, 1.05, -2.64), bevel=0.006),
        # 座舱玻璃罩 + 框条
        add_box("_Cabin", (0.74, 0.50, 1.60), (0, 1.56, 0.30), bevel=0.03),
        add_box("_CabinFrame", (0.78, 0.05, 1.64), (0, 1.78, 0.30), bevel=0.008),
        add_box("_CabinFrameV", (0.05, 0.54, 0.05), (0, 1.58, -0.35), bevel=0.006),
        # 上单翼(带 2° 上反 + 翼尖圆角)
        add_box("_Wing", (8.60, 0.14, 1.42), (0, 1.98, -0.15), bevel=0.035),
        # 左右翼撑杆(机身下侧 → 翼中段)
        add_cyl("_StrutL", 0.035, 1.45, (-1.55, 1.25, -0.15), axis="y", seg=6),
        add_cyl("_StrutR", 0.035, 1.45, (1.55, 1.25, -0.15), axis="y", seg=6),
        # 尾翼组
        add_box("_TailPlane", (3.10, 0.09, 1.05), (0, 1.30, 3.45), bevel=0.02),
        add_box("_Fin", (0.09, 1.35, 1.00), (0, 1.95, 3.60), bevel=0.02),
        # 固定起落架:左右撑杆 + 主轮 + 尾橇
        add_cyl("_GearL", 0.04, 0.75, (-0.62, 0.55, -0.65), axis="y", seg=6),
        add_cyl("_GearR", 0.04, 0.75, (0.62, 0.55, -0.65), axis="y", seg=6),
        add_cyl("_TireL", 0.27, 0.16, (-0.68, 0.27, -0.65), axis="x", seg=14),
        add_cyl("_TireR", 0.27, 0.16, (0.68, 0.27, -0.65), axis="x", seg=14),
        # 机身识别带(黄色)
        add_cyl("_Stripe", 0.535, 0.45, (0, 1.05, 1.30), axis="z", seg=14),
    ]
    rules = [
        ("_Fuselage", "olive"), ("_TailCone", "olive"), ("_Wing", "olive"),
        ("_TailPlane", "olive"), ("_Fin", "olive"), ("_Strut", "dark"),
        ("_Gear", "dark"), ("_Nose", "dark"), ("_Spinner", "dark"),
        ("_PropBlade", "dark"), ("_Cabin", "glass"), ("_CabinFrame", "dark"),
        ("_Tire", "tire"), ("_Stripe", "yellow"),
    ]
    return _finish("Prop_plane", parts, rules)


BUILDERS = {
    "pine": build_pine, "broadleaf": build_broadleaf, "palm": build_palm,
    "wreck_sedan": build_wreck_sedan, "wreck_truck": build_wreck_truck,
    "barrel": build_barrel, "crate": build_crate, "sandbag": build_sandbag,
    "boulder": build_boulder, "barrier": build_barrier, "plane": build_plane,
}


def main():
    targets = list(BUILDERS.keys())
    argv = sys.argv
    if "--" in argv:
        tail = argv[argv.index("--") + 1:]
        if tail:
            targets = [t for t in tail if t in BUILDERS]
    os.makedirs(OUT_DIR, exist_ok=True)
    print("=" * 60)
    for pid in targets:
        BUILDERS[pid]()
        objs, verts, tris = stats()
        path = os.path.join(OUT_DIR, "%s.glb" % pid)
        export_glb(path)
        print("%-12s objs=%-3d verts=%-6d tris=%-6d  %.0f KB" % (
            pid, objs, verts, tris, os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
