"""G3 高精度模型 —— 突击步枪批次 7/8(滚柱延迟反后坐战斗步枪)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *


def build():
    reset()
    RY = 0.024
    SIGHT = 0.112

    # 冲压钢机匣 + 顶部照门座
    upper = add_box("UpperReceiver", (0.052, 0.068, 0.40), (0, 0.014, -0.03), bevel=0.0012)
    add_box("RearSightBlock", (0.048, 0.016, 0.30), (0, 0.052, -0.04), bevel=0.0006)
    cut(upper, add_box("_port", (0.022, 0.014, 0.040), (0.029, 0.030, -0.06)))

    # 枪管 + 三叉准星座 + 枪口消焰器
    add_cyl("Barrel", 0.012, 0.56, (0, RY, -0.46), axis="z", seg=16, bevel=0.0006)
    add_box("FrontSightBase", (0.024, 0.046, 0.03), (0, 0.044, -0.62), bevel=0.0006)
    # 三叉护翼(标志性)
    add_box("FrontWingL", (0.005, 0.020, 0.024), (-0.013, 0.068, -0.62), bevel=0.0004)
    add_box("FrontWingR", (0.005, 0.020, 0.024), (0.013, 0.068, -0.62), bevel=0.0004)
    flash = add_cyl("FlashHider", 0.016, 0.050, (0, RY, -0.715), axis="z", seg=20, bevel=0.0006)

    # 细长聚合物护木 + 防滑筋
    add_box("Handguard", (0.048, 0.052, 0.22), (0, 0.012, -0.28), bevel=0.0010)
    for rib_z in [-0.35, -0.30, -0.25, -0.20]:
        add_box("HandguardRib", (0.05, 0.005, 0.016), (0, 0.037, rib_z), bevel=0.0003)

    # 固定聚合物托
    add_box("StockBody", (0.042, 0.090, 0.19), (0, -0.005, 0.19), bevel=0.0012)
    add_box("StockPlate", (0.046, 0.095, 0.020), (0, 0.002, 0.285), bevel=0.0008)
    add_box("SlingEye", (0.010, 0.014, 0.03), (0.022, -0.012, 0.20), bevel=0.0004)

    # 聚合物握把 + 扳机
    add_box("Grip", (0.034, 0.100, 0.045), (0, -0.024, 0.04), bevel=0.0010)
    for i in range(4):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.010 - i * 0.014, 0.052), bevel=0.0003)
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.036, 0.015), bevel=0.0005)
    add_box("TriggerGuardF", (0.008, 0.020, 0.008), (0, -0.040, -0.020), bevel=0.0006)
    add_box("TriggerGuardB", (0.008, 0.020, 0.008), (0, -0.040, 0.030), bevel=0.0006)
    add_box("TriggerGuardBot", (0.008, 0.008, 0.052), (0, -0.050, 0.005), bevel=0.0006)

    # 鼓式照门(经典 G3 特征)
    add_box("RearSightDrum", (0.030, 0.014, 0.040), (0, 0.060, 0.04), bevel=0.0006)
    add_box("RearSightMark", (0.002, 0.001, 0.012), (0, 0.068, 0.04), bevel=0.0002)

    # 可动件:7.62 钢弹匣
    segs = [
        add_box("MagBody", (0.038, 0.120, 0.060), (0, -0.022, -0.090), bevel=0.0010),
        add_box("_mfl", (0.040, 0.008, 0.062), (0, -0.085, -0.090), bevel=0.0005),
        add_box("_mlip", (0.036, 0.010, 0.058), (0, 0.030, -0.090), bevel=0.0005),
    ]
    mag = join_parts("mag", segs)

    # 可动件:左前拉机柄(可折叠)
    bolt = add_box("bolt", (0.008, 0.010, 0.055), (-0.030, 0.04, -0.18), bevel=0.0005)

    rules = [
        ("UpperReceiver", "metal"), ("RearSightBlock", "dark"),
        ("Barrel", "dark"), ("FrontSight", "dark"),
        ("FrontWing", "dark"), ("FlashHider", "dark"),
        ("Handguard", "olive"), ("StockBody", "poly"),
        ("StockPlate", "poly"), ("SlingEye", "dark"),
        ("Grip", "poly"), ("Trigger", "dark"),
        ("TriggerGuard", "dark"),
        ("RearSight", "dark"),
        ("mag", "dark"), ("bolt", "dark"),
    ]
    apply_materials(rules, default="dark")
    return mag


if __name__ == "__main__":
    m = build()
    o, v, t = stats()
    print("G3 objects=%d verts=%d tris=%d" % (o, v, t))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/g3.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
