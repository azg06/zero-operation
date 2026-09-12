"""SCAR-H 高精度模型 —— 突击步枪批次 2/8"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *


def build():
    reset()
    RY = 0.024
    SIGHT = 0.112

    # 一体式上机匣(延伸到护木)
    upper = add_box("UpperReceiver", (0.050, 0.030, 0.42), (0, 0.048, -0.10), bevel=0.0012)
    add_box("LowerReceiver", (0.052, 0.052, 0.20), (0, -0.006, -0.02), bevel=0.0010)
    add_picatinny("TopRail", 0.40, (0, SIGHT + 0.002, -0.10))

    # 护木段
    add_box("Handguard", (0.046, 0.036, 0.15), (0, 0.003, -0.30), bevel=0.0008)
    # 侧轨必须绕枪管轴转 90° 让齿朝外(右轨 -PI/2 / 左轨 +PI/2),齿顶平面贴到
    # 护木面外(半宽 0.023 + 轨厚 0.0074)—— 不转就是"齿朝上的平躺板"横向穿模
    for side in [-1.0, 1.0]:
        add_picatinny("SideRail%s" % ("R" if side > 0 else "L"), 0.14,
                      (side * 0.0304, 0.012, -0.30), width=0.016,
                      rot_z=(-math.pi * 0.5 if side > 0 else math.pi * 0.5))

    # 枪管 + 短冲程导气座 + 三叉消焰器
    add_cyl("Barrel", 0.011, 0.62, (0, RY, -0.46), axis="z", seg=16, bevel=0.0006)
    add_box("GasBlock", (0.022, 0.040, 0.05), (0, 0.035, -0.34), bevel=0.0006)
    flash = add_cyl("FlashHider", 0.016, 0.050, (0, RY, -0.80), axis="z", seg=20, bevel=0.0006)
    # 三叉:三个突出小杆
    for ang_deg in [-90, 30, 150]:
        ang = math.radians(ang_deg)
        x = math.cos(ang) * 0.018
        y = RY + math.sin(ang) * 0.018
        add_cyl("_prong%d" % int(ang_deg), 0.003, 0.025, (x, y, -0.81), axis="z", seg=8)

    # 抛壳窗(右)
    cut(upper, add_box("_port", (0.030, 0.022, 0.060), (0.027, 0.045, -0.060)))

    # 靴型折叠托
    add_box("StockHinge", (0.030, 0.060, 0.05), (0, 0.010, 0.13), bevel=0.0006)
    add_box("StockUpper", (0.026, 0.030, 0.16), (0, 0.03, 0.20), bevel=0.0008)
    add_box("StockBody", (0.048, 0.10, 0.032), (0, 0.0, 0.27), bevel=0.0010)
    add_box("StockHeel", (0.048, 0.035, 0.06), (0, -0.03, 0.24), bevel=0.0008)
    add_box("FoldingLatch", (0.010, 0.025, 0.08), (0.022, 0.002, 0.19), bevel=0.0004)

    # 握把 + 扳机
    add_box("Grip", (0.034, 0.100, 0.046), (0, -0.026, 0.04), bevel=0.0010)
    for i in range(4):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.012 - i * 0.014, 0.052), bevel=0.0003)
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.038, 0.005), bevel=0.0005)
    add_box("TriggerGuardF", (0.008, 0.020, 0.008), (0, -0.040, -0.020), bevel=0.0006)
    add_box("TriggerGuardB", (0.008, 0.020, 0.008), (0, -0.040, 0.030), bevel=0.0006)
    add_box("TriggerGuardBot", (0.008, 0.008, 0.052), (0, -0.050, 0.005), bevel=0.0006)

    # 可动件:7.62 短直弹匣
    mag_body = add_box("MagBody", (0.038, 0.105, 0.065), (0, -0.022, -0.100), bevel=0.0010)
    floor = add_box("_mfl", (0.040, 0.008, 0.067), (0, -0.078, -0.100), bevel=0.0005)
    lip = add_box("_mlip", (0.036, 0.010, 0.063), (0, 0.024, -0.100), bevel=0.0005)
    mag = join_parts("mag", [mag_body, floor, lip])

    # 可动件:左侧拉机柄
    ch = add_box("bolt", (0.008, 0.010, 0.055), (-0.030, 0.055, -0.16), bevel=0.0005)

    rules = [
        ("UpperReceiver", "tan"), ("LowerReceiver", "tan"),
        ("Handguard", "dark"), ("SideRail", "dark"),
        ("TopRail", "dark"), ("Barrel", "dark"),
        ("GasBlock", "dark"), ("FlashHider", "dark"),
        ("_prong", "dark"),
        ("StockHinge", "dark"), ("StockUpper", "tan"),
        ("StockBody", "tan"), ("StockHeel", "dark"),
        ("Grip", "dark"), ("Trigger", "dark"),
        ("TriggerGuard", "dark"),
        ("mag", "tan"), ("bolt", "dark"),
    ]
    apply_materials(rules, default="dark")
    return mag


if __name__ == "__main__":
    m = build()
    o, v, t = stats()
    print("SCAR-H objects=%d verts=%d tris=%d" % (o, v, t))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/scar.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
