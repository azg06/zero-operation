"""AUG A3 高精度模型 —— 突击步枪批次 4/8(无托)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *


def build():
    reset()
    RY = 0.026
    SIGHT = 0.125

    # 无托一体枪身 + 贴腮凸起 + 托底板
    body = add_box("Body", (0.052, 0.080, 0.58), (0, 0.022, 0.03), bevel=0.0015)
    add_box("CheekRise", (0.050, 0.050, 0.16), (0, 0.072, 0.12), bevel=0.0012)
    add_box("StockPlate", (0.054, 0.095, 0.025), (0, 0.020, 0.31), bevel=0.0010)
    add_box("BrassDeflector", (0.012, 0.020, 0.05), (0.030, 0.04, 0.16), bevel=0.0005)

    # A3 顶部导轨
    add_picatinny("TopRail", 0.40, (0, SIGHT + 0.004, 0.0))

    # 枪管 + 鸟笼消焰器
    add_cyl("Barrel", 0.011, 0.42, (0, RY, -0.36), axis="z", seg=16, bevel=0.0006)
    flash = add_cyl("FlashHider", 0.014, 0.040, (0, RY, -0.64), axis="z", seg=18, bevel=0.0005)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cx = math.cos(ang) * 0.0125; cy = RY + math.sin(ang) * 0.0125
        cut(flash, add_box("_fs%d" % i, (0.006, 0.005, 0.025), (cx, cy, -0.645)))

    # 前置可折叠垂直握把 + 大型扳机护圈桥
    add_box("Foregrip", (0.028, 0.075, 0.04), (0, -0.030, -0.17), bevel=0.0008)
    add_box("TriggerBridge", (0.046, 0.018, 0.26), (0, -0.050, 0.0), bevel=0.0008)

    # 后置手枪握把(扳机在前,弹匣在握把后方)
    add_box("Grip", (0.034, 0.090, 0.05), (0, -0.026, 0.07), bevel=0.0010)
    for i in range(4):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.012 - i * 0.012, 0.080), bevel=0.0003)
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.037, -0.05), bevel=0.0005)

    # 抛壳窗(右)
    cut(body, add_box("_port", (0.022, 0.014, 0.040), (0.029, 0.030, 0.18)))

    # 可动件:半透明聚合物后置弹匣
    segs = []
    for i in range(4):
        segs.append(add_box("_mseg%d" % i, (0.036, 0.025, 0.038), (0, -0.022 - i * 0.030, 0.16), bevel=0.0006))
    segs.append(add_box("_mfl", (0.038, 0.008, 0.058), (0, -0.090, 0.16), bevel=0.0005))
    # 加强筋
    segs.append(add_box("_mrib1", (0.040, 0.005, 0.057), (0, -0.020, 0.162), bevel=0.0004))
    segs.append(add_box("_mrib2", (0.040, 0.005, 0.057), (0, -0.080, 0.162), bevel=0.0004))
    mag = join_parts("mag", segs)

    # 可动件:左后拉机柄
    bolt = add_box("bolt", (0.008, 0.010, 0.050), (-0.030, 0.05, 0.24), bevel=0.0005)

    rules = [
        ("Body", "olive"), ("CheekRise", "olive"),
        ("StockPlate", "dark"), ("BrassDeflector", "dark"),
        ("TopRail", "dark"), ("Barrel", "dark"),
        ("FlashHider", "dark"), ("Foregrip", "olive"),
        ("TriggerBridge", "olive"), ("Grip", "olive"),
        ("Trigger", "dark"), ("mag", "olive"), ("bolt", "dark"),
    ]
    apply_materials(rules, default="dark")
    return mag


if __name__ == "__main__":
    m = build()
    o, v, t = stats()
    print("AUG objects=%d verts=%d tris=%d" % (o, v, t))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/aug.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
