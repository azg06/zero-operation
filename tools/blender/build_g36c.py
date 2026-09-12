"""G36C 高精度模型 —— 突击步枪批次 3/8"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *


def build():
    reset()
    RY = 0.024
    SIGHT = 0.100

    # 聚合物机匣 + 提把
    add_box("Receiver", (0.050, 0.062, 0.34), (0, 0.014, -0.03), bevel=0.0012)
    add_box("CarryHandle", (0.046, 0.030, 0.18), (0, 0.052, 0.0), bevel=0.0010)
    add_picatinny("TopRail", 0.18, (0, SIGHT + 0.004, 0.0))

    # 短枪管 + 鸟笼消焰器(G36C 短管)
    add_cyl("Barrel", 0.011, 0.42, (0, RY, -0.42), axis="z", seg=16, bevel=0.0006)
    flash = add_cyl("FlashHider", 0.014, 0.050, (0, RY, -0.68), axis="z", seg=18, bevel=0.0005)
    # 鸟笼开槽
    import math as _m
    for i in range(3):
        ang = _m.pi * 0.5 + i * (2 * _m.pi / 3.0)
        cx = _m.cos(ang) * 0.0125; cy = RY + _m.sin(ang) * 0.0125
        cut(flash, add_box("_fs%d" % i, (0.006, 0.005, 0.030), (cx, cy, -0.685)))

    # 短护木 + 4 向导轨(侧/底轨必须绕枪管轴转 90°/180° 让齿朝外/朝下 ——
    # 否则是"齿朝上的平躺板"浮在枪侧,实机验证翻车点,与旧版 scar 同病;
    # 齿顶平面贴到护木面外:半宽 0.025 + 轨厚 0.0074)
    add_box("Handguard", (0.05, 0.05, 0.13), (0, 0.006, -0.24), bevel=0.0010)
    for side in [-1.0, 1.0]:
        add_picatinny("SideRail%s" % ("R" if side > 0 else "L"), 0.10,
                      (side * 0.0324, 0.006, -0.24), width=0.016,
                      rot_z=(-math.pi * 0.5 if side > 0 else math.pi * 0.5))
    add_picatinny("BottomRail", 0.10, (0, -0.0264, -0.24), width=0.016, rot_z=math.pi)

    # 折叠骨架托
    add_box("StockHinge", (0.030, 0.055, 0.04), (0, 0.005, 0.14), bevel=0.0006)
    add_box("StockUpper", (0.024, 0.020, 0.14), (0, 0.05, 0.21), bevel=0.0006)
    add_box("StockLower", (0.024, 0.020, 0.14), (0, -0.015, 0.21), bevel=0.0006)
    add_box("CheekRest", (0.036, 0.030, 0.08), (0, 0.035, 0.24), bevel=0.0008)
    add_box("StockPlate", (0.040, 0.080, 0.024), (0, 0.010, 0.27), bevel=0.0008)

    # 握把 + 扳机
    add_box("Grip", (0.034, 0.100, 0.045), (0, -0.023, 0.04), bevel=0.0010)
    for i in range(4):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.005 - i * 0.014, 0.055), bevel=0.0003)
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.035, 0.005), bevel=0.0005)
    add_box("TriggerGuardF", (0.008, 0.020, 0.008), (0, -0.040, -0.020), bevel=0.0006)
    add_box("TriggerGuardB", (0.008, 0.020, 0.008), (0, -0.040, 0.030), bevel=0.0006)
    add_box("TriggerGuardBot", (0.008, 0.008, 0.052), (0, -0.050, 0.005), bevel=0.0006)

    # 抛壳窗
    port = add_box("_port_cut", (0.020, 0.015, 0.045), (0.027, 0.040, -0.080))
    cut(_last_named("Receiver"), port)

    # 可动件:弧形弹匣(半透明聚合物风)
    segs = []
    for i in range(5):
        t = i / 4.0
        a = -0.5 + t * 1.0
        z = -0.060 - 0.08 * (1.0 - _m.cos(a))
        y = -0.022 - 0.08 * _m.sin(a)
        segs.append(add_box("_mseg%d" % i, (0.036, 0.020, 0.035), (0, y, z), bevel=0.0005))
    segs.append(add_box("_mfloor", (0.038, 0.008, 0.060), (0, -0.100, -0.075), bevel=0.0005))
    mag = join_parts("mag", segs)

    # 可动件:顶置折叠拉机柄
    ch = add_box("bolt", (0.008, 0.010, 0.040), (0, 0.062, -0.060), bevel=0.0005)

    rules = [
        ("Receiver", "poly"), ("CarryHandle", "poly"),
        ("Handguard", "poly"), ("SideRail", "dark"), ("BottomRail", "dark"),
        ("StockHinge", "dark"), ("CheekRest", "poly"),
        ("StockUpper", "poly"), ("StockLower", "poly"), ("StockPlate", "poly"),
        ("Grip", "poly"), ("Trigger", "dark"),
        ("TriggerGuard", "dark"),
        ("TopRail", "dark"), ("mag", "tan"),
    ]
    apply_materials(rules, default="dark")
    return mag


def _last_named(prefix):
    """最近一个名字以 prefix 开头的 mesh —— 给 cut 当 target 用"""
    candidates = [o for o in bpy.data.objects if o.name == prefix]
    return candidates[0] if candidates else None


if __name__ == "__main__":
    m = build()
    o, v, t = stats()
    print("G36C objects=%d verts=%d tris=%d" % (o, v, t))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/g36c.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
