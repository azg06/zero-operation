"""AK-74M 高精度模型 —— 突击步枪批次 5/8(AK 系现代聚合物版)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *


def build():
    reset()
    RY = 0.028
    SIGHT = 0.104

    # 机匣(同 AK,但带防尘盖、保险、抛壳窗)
    upper = add_box("UpperReceiver", (0.054, 0.066, 0.30), (0, 0.012, -0.03), bevel=0.0012)
    add_box("DustCover", (0.05, 0.020, 0.22), (0, 0.052, -0.02), bevel=0.0008)
    add_box("CoverHandle", (0.018, 0.006, 0.030), (0, 0.063, -0.020), bevel=0.0004)
    add_box("SafetyLever", (0.012, 0.020, 0.10), (0.030, 0.012, -0.02), bevel=0.0006)
    cut(upper, add_box("_port", (0.024, 0.014, 0.045), (0.029, 0.040, -0.060)))

    # 前节套 + 导气管 + 90° 导气座
    add_box("FrontTrunnion", (0.05, 0.05, 0.05), (0, 0.024, -0.16), bevel=0.0008)
    add_cyl("GasTube", 0.011, 0.32, (0, 0.05, -0.25), axis="z", seg=10, bevel=0.0004)
    add_box("GasBlock", (0.020, 0.042, 0.04), (0, 0.033, -0.46), bevel=0.0006)

    # 黑色聚合物上下护木
    add_box("UpperHandguard", (0.046, 0.030, 0.15), (0, 0.053, -0.27), bevel=0.0008)
    add_box("LowerHandguard", (0.05, 0.040, 0.15), (0, 0.010, -0.27), bevel=0.0008)
    add_box("HandguardBand", (0.051, 0.013, 0.016), (0, 0.031, -0.21), bevel=0.0004)

    # 枪管 + 准星座 + 74 式圆柱开槽制退器
    add_cyl("Barrel", 0.011, 0.46, (0, RY, -0.49), axis="z", seg=16, bevel=0.0006)
    add_box("FrontSightBase", (0.020, 0.052, 0.028), (0, 0.05, -0.72), bevel=0.0006)
    muzzle = add_cyl("MuzzleDevice", 0.014, 0.070, (0, RY, -0.79), axis="z", seg=18, bevel=0.0005)
    # 制退器开槽
    for side in [-1.0, 1.0]:
        cut(muzzle, add_box("_mslot%d" % int(side), (0.006, 0.008, 0.045), (side * 0.0145, RY, -0.78)))

    # 侧折叠骨架托
    add_box("StockHinge", (0.030, 0.055, 0.04), (0, 0.005, 0.15), bevel=0.0006)
    add_box("StockUpper", (0.022, 0.020, 0.15), (0, 0.045, 0.21), bevel=0.0006)
    add_box("StockLower", (0.022, 0.020, 0.15), (0, -0.012, 0.21), bevel=0.0006)
    add_box("StockPlate", (0.040, 0.080, 0.024), (0, 0.010, 0.28), bevel=0.0008)

    # 聚合物握把 + 5.45 弹匣(更直)
    add_box("Grip", (0.034, 0.100, 0.046), (0, -0.024, 0.045), bevel=0.0010)
    for i in range(4):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.010 - i * 0.014, 0.055), bevel=0.0003)
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.036, 0.015), bevel=0.0005)
    add_box("TriggerGuardF", (0.008, 0.020, 0.008), (0, -0.040, -0.020), bevel=0.0006)
    add_box("TriggerGuardB", (0.008, 0.020, 0.008), (0, -0.040, 0.030), bevel=0.0006)
    add_box("TriggerGuardBot", (0.008, 0.008, 0.052), (0, -0.050, 0.005), bevel=0.0006)

    # 可动件:5.45 直弹匣
    segs = [
        add_box("MagBody", (0.036, 0.135, 0.058), (0, -0.023, -0.100), bevel=0.0010),
        add_box("_mfl", (0.038, 0.008, 0.060), (0, -0.095, -0.100), bevel=0.0005),
        add_box("_mlip", (0.034, 0.010, 0.056), (0, 0.035, -0.100), bevel=0.0005),
    ]
    mag = join_parts("mag", segs)

    # 可动件:右侧拉机柄
    bolt = add_box("bolt", (0.008, 0.010, 0.055), (0.032, 0.036, -0.020), bevel=0.0005)

    rules = [
        ("UpperReceiver", "dark"), ("DustCover", "metal"),
        ("CoverHandle", "metal"), ("SafetyLever", "metal"),
        ("FrontTrunnion", "metal"), ("GasBlock", "metal"),
        ("UpperHandguard", "poly"), ("LowerHandguard", "poly"),
        ("HandguardBand", "dark"),
        ("Barrel", "dark"), ("FrontSight", "dark"),
        ("MuzzleDevice", "dark"),
        ("StockHinge", "dark"), ("StockUpper", "poly"),
        ("StockLower", "poly"), ("StockPlate", "poly"),
        ("Grip", "poly"), ("Trigger", "dark"),
        ("TriggerGuard", "dark"),
        ("mag", "dark"), ("bolt", "dark"),
    ]
    apply_materials(rules, default="dark")
    return mag


if __name__ == "__main__":
    m = build()
    o, v, t = stats()
    print("AK74 objects=%d verts=%d tris=%d" % (o, v, t))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/ak74.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
