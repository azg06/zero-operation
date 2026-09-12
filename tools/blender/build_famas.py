"""FAMAS 高精度模型 —— 突击步枪批次 6/8(法式无托)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *


def build():
    reset()
    RY = 0.024
    SIGHT = 0.100

    # 无托枪身(黑绿聚合物)+ 高提把
    body = add_box("Body", (0.050, 0.070, 0.56), (0, 0.020, 0.0), bevel=0.0015)
    add_box("CarryHandle", (0.046, 0.028, 0.16), (0, 0.062, -0.02), bevel=0.0010)
    # 提把顶上的整体式导轨(整条长)
    add_picatinny("TopRail", 0.20, (0, SIGHT + 0.005, -0.02))
    # 提把内部机械瞄具(看的是提把顶而非枪管轴)
    # 提把顶 0.088 < sight_y 0.100,刚好不挡

    # 枪管 + 消焰器
    add_cyl("Barrel", 0.011, 0.46, (0, RY, -0.44), axis="z", seg=16, bevel=0.0006)
    flash = add_cyl("FlashHider", 0.014, 0.040, (0, RY, -0.69), axis="z", seg=18, bevel=0.0005)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cx = math.cos(ang) * 0.0125; cy = RY + math.sin(ang) * 0.0125
        cut(flash, add_box("_fs%d" % i, (0.006, 0.005, 0.025), (cx, cy, -0.695)))

    # 收纳式两脚架(贴枪身两侧)
    for side in [-1.0, 1.0]:
        add_cyl("_bipod%d" % int(side), 0.006, 0.22, (side * 0.029, -0.008, -0.32), axis="z", seg=8)
        add_box("_bipod_foot%d" % int(side), (0.01, 0.03, 0.04), (side * 0.029, -0.005, -0.42), bevel=0.0004)

    # 前置垂直握把 + 大型扳机护圈桥
    add_box("Foregrip", (0.028, 0.060, 0.04), (0, -0.030, -0.16), bevel=0.0008)
    add_box("TriggerBridge", (0.040, 0.014, 0.24), (0, -0.045, -0.02), bevel=0.0008)

    # 后置手枪握把 + 扳机
    add_box("Grip", (0.034, 0.090, 0.05), (0, -0.025, 0.08), bevel=0.0010)
    for i in range(4):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.010 - i * 0.012, 0.090), bevel=0.0003)
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.035, -0.02), bevel=0.0005)

    # 抛壳窗
    cut(body, add_box("_port", (0.022, 0.014, 0.040), (0.029, 0.030, 0.17)))

    # 可动件:后置直弹匣
    segs = [
        add_box("MagBody", (0.036, 0.120, 0.058), (0, -0.022, 0.16), bevel=0.0010),
        add_box("_mfl", (0.038, 0.008, 0.060), (0, -0.090, 0.16), bevel=0.0005),
        add_box("_mlip", (0.034, 0.010, 0.056), (0, 0.032, 0.16), bevel=0.0005),
    ]
    mag = join_parts("mag", segs)

    # 可动件:顶部拉机柄(提把下方)
    bolt = add_box("bolt", (0.008, 0.010, 0.050), (0, 0.060, 0.20), bevel=0.0005)

    # 提把式机械瞄具(FAMAS 照门贴着提把顶,小缺口,不挡视轴)
    add_box("FrontSightPost", (0.004, 0.012, 0.010), (0, 0.095, 0.04), bevel=0.0004)
    add_box("RearSightL", (0.004, 0.012, 0.010), (-0.0055, 0.095, 0.04), bevel=0.0004)
    add_box("RearSightR", (0.004, 0.012, 0.010), (0.0055, 0.095, 0.04), bevel=0.0004)

    rules = [
        ("Body", "olive"), ("CarryHandle", "poly"),
        ("TopRail", "dark"), ("Barrel", "dark"),
        ("FlashHider", "dark"), ("Foregrip", "olive"),
        ("TriggerBridge", "olive"), ("Grip", "olive"),
        ("Trigger", "dark"), ("mag", "dark"), ("bolt", "dark"),
        ("FrontSight", "dark"), ("RearSight", "dark"),
    ]
    apply_materials(rules, default="dark")
    return mag


if __name__ == "__main__":
    m = build()
    o, v, t = stats()
    print("FAMAS objects=%d verts=%d tris=%d" % (o, v, t))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/famas.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
