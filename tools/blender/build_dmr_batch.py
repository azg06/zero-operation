"""
DMR 批次建模(8 把):M110 / SKS / M1A / G28 / MK14 / M14 / AR-10 / FN FAL

尺寸沿用 weapon_models.gd 程序化定义,锚点零改动。
DMR 无原厂 PIP 镜(def.scope=false),机瞄 StockIrons 常显 —— 齿顶平面
低于 sight_y >=12mm,照门/准星归 StockIrons 组(ALLOW_IN_AXIS 排除)。

换弹契约:
    bolt   半自动拉机柄(FAL 左侧,mag_style "down",chamber_style "release")
    mag    弹匣(SKS 内仓无此件,mag_style "none")

用法:
    blender --background --python build_dmr_batch.py
    blender --background --python build_dmr_batch.py -- m110 sks
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


def bolt_handle_assembly(y, z_rear, side=1.0):
    """半自动拉机柄总成(bolt)。FAL 左侧(side=-1)。"""
    parts = [
        add_cyl("BoltBody", 0.008, 0.050, (0, y + 0.006, z_rear), axis="z", seg=12, bevel=0.0005),
        add_cyl("BoltArm", 0.0045, 0.030, (side * 0.014, y - 0.006, z_rear + 0.010), axis="x", seg=10, bevel=0.0004),
        add_torus("BoltKnob", 0.0075, 0.0038, (side * 0.030, y - 0.008, z_rear + 0.010), seg_major=14, seg_minor=8),
    ]
    return join_parts("bolt", parts)


def dmr_rail(z_front, z_rear, rail_y=0.086, w=0.024, mount_h=0.0):
    """DMR 顶轨。齿顶必须低于 sight_y >=12mm(机瞄照门在 sight_y 上,导轨别去凑)。"""
    return add_picatinny("TopRail", absf(z_front - z_rear),
                         (0, rail_y, (z_front + z_rear) * 0.5), width=w, mount_h=mount_h)


def skeleton_dmr_stock(y, z_hinge, plate_z, mat):
    """骨架/调节托 v2(AR 式 DMR):托板挖两孔减重 + 托底橡胶垫 + 贴腮调节钮。"""
    plate = add_box("StockPlate", (0.036, 0.086, 0.026), (0, y - 0.024, plate_z), bevel=0.0010)
    # 托板减重孔(挖穿)
    for i, dy in enumerate((-0.022, 0.010)):
        c = add_cyl("_platehole%d" % i, 0.008, 0.040, (0, y - 0.024 + dy, plate_z), axis="y", seg=14)
        cut(plate, c)
    parts = [
        add_box("StockTop", (0.020, 0.024, 0.26), (0, y - 0.008, z_hinge + 0.14), bevel=0.0008),
        plate,
        add_box("CheekRest", (0.042, 0.020, 0.100), (0, y + 0.022, plate_z - 0.050), bevel=0.0008),
        add_butt_pad("ButtPad", y - 0.024, plate_z + 0.017, w=0.036, h=0.086),
        add_cyl("CheekKnob", 0.006, 0.014, (0.025, y + 0.022, plate_z - 0.018), axis="x", seg=10, bevel=0.0004),
    ]
    return parts


def wood_stock_set(g, ry, mat):
    """木托全家桶 v3:直托(枪托偏下修正,与各枪 inline 写法一致)+ 托底垫 +
    托面菱形防滑纹。注意:此函数当前未被引用,保留供以后复用;
    实际托参数以各枪 build_* 内的 add_stock 调用为准。"""
    ck = add_checkering("StockCheck", 0.040, 0.060, (0, 0.030, 0.28), n=7, m=3)
    return [
        add_box("Stock", (0.046, 0.098, 0.02), (0, 0.0, 0.28), bevel=0.0010),
        add_stock("StockGrip", 0.042, 0.095, 0.18, 0.11, 0.056, drop=0.12, plate=False),
        add_butt_pad("ButtPad", 0.0, 0.292, w=0.046, h=0.098),
        ck,
    ]


TRIGGER_GUARD_RULES = [("TriggerGuard", "dark"), ("bolt", "dark"), ("mag", "dark"),
                       ("TopRail", "dark"), ("StockIrons", "dark"), ("BoltHandle", "dark")]


def build_m110():
    reset()
    ry = 0.028
    # AR 式机匣 + 加长护木(KAC 构型)
    add_box("Receiver", (0.050, 0.075, 0.34), (0, 0.016, -0.06), bevel=0.0014)
    add_box("Handguard", (0.046, 0.026, 0.48), (0, 0.062, -0.20), bevel=0.0012)
    dmr_rail(0.02, -0.44, mount_h=0.0)
    # 7.62 长管 + 消焰器
    add_cyl("Barrel", 0.011, 0.62, (0, ry, -0.52), axis="z", seg=18, bevel=0.0006, taper=0.88)
    add_cyl("FlashHider", 0.016, 0.05, (0, ry, -0.82), axis="z", seg=16, bevel=0.0006)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.36, mat="dark")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.046, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 + 0.038), bevel=0.0004)
    # 20 发弹匣
    add_mag_straight("mag", 0.036, 0.10, 0.06, (0, 0.006, -0.10), tilt=0.10, mat="tan")
    # 伸缩托
    for p in skeleton_dmr_stock(0.024, 0.120, 0.28, "tan"):
        pass
    bolt_handle_assembly(0.030, -0.02)
    add_irons("StockIrons", 0.110, -0.55, 0.05, 0.05, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "tan"), ("Handguard", "dark"), ("Stock", "tan"),
        ("CheekRest", "tan"), ("StockGrip", "tan"), ("Grip", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"),
    ], default="dark")


def build_sks():
    reset()
    ry = 0.026
    add_cyl("Barrel", 0.011, 0.47, (0, ry, -0.44), axis="z", seg=16, bevel=0.0005, taper=0.9)
    add_cyl("Muzzle", 0.015, 0.05, (0, ry, -0.66), axis="z", seg=14, bevel=0.0005)
    add_box("Receiver", (0.05, 0.08, 0.34), (0, 0.016, -0.04), bevel=0.0014)
    add_box("ReceiverCover", (0.044, 0.026, 0.30), (0, 0.06, -0.10), bevel=0.0008)
    add_picatinny("TopRail", 0.16, (0, 0.0804, -0.12), width=0.020, mount_h=0.006)
    add_box("Bayonet", (0.01, 0.025, 0.16), (0.03, -0.01, -0.52), bevel=0.0004)  # 折叠刺刀
    add_stock("StockGrip", 0.042, 0.095, 0.17, 0.13, 0.056, drop=0.12, plate=False)
    add_box("Stock", (0.046, 0.095, 0.02), (0, 0.0, 0.28), bevel=0.0010)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.045), tilt=0.40, mat="wood")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.044, 0.030), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.044 + 0.009, 0.030 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.044 + 0.009, 0.030 + 0.038), bevel=0.0004)
    # 固定弹仓:只有底板,无 mag 节点(mag_style "none")
    add_box("MagFloorplate", (0.03, 0.02, 0.08), (0, -0.052, -0.06), bevel=0.0004)
    bolt_handle_assembly(0.030, 0.0)
    add_irons("StockIrons", 0.105, -0.50, 0.05, 0.05, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "metal"), ("ReceiverCover", "metal"), ("Bayonet", "dark"),
        ("Stock", "wood"), ("StockGrip", "wood"), ("Grip", "wood"),
        ("Barrel", "dark"), ("Muzzle", "dark"), ("MagFloorplate", "dark"),
    ], default="dark")


def build_m1a():
    reset()
    ry = 0.026
    add_cyl("Barrel", 0.012, 0.56, (0, ry, -0.50), axis="z", seg=18, bevel=0.0006, taper=0.9)
    add_cyl("Muzzle", 0.016, 0.05, (0, ry, -0.755), axis="z", seg=14, bevel=0.0005)
    add_box("Receiver", (0.05, 0.082, 0.34), (0, 0.016, -0.06), bevel=0.0014)
    add_box("ReceiverCover", (0.046, 0.028, 0.30), (0, 0.064, -0.12), bevel=0.0008)
    add_picatinny("TopRail", 0.16, (0, 0.0854, -0.12), width=0.020, mount_h=0.006)
    add_stock("StockGrip", 0.042, 0.095, 0.18, 0.11, 0.057, drop=0.12, plate=False)
    add_box("Stock", (0.046, 0.1, 0.02), (0, 0.0, 0.28), bevel=0.0010)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.40, mat="wood")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.046, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 + 0.038), bevel=0.0004)
    add_mag_straight("mag", 0.038, 0.12, 0.06, (0, 0.006, -0.09), tilt=0.08, mat="dark")
    bolt_handle_assembly(0.030, 0.0)
    add_irons("StockIrons", 0.112, -0.56, 0.05, 0.06, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "metal"), ("ReceiverCover", "metal"),
        ("Stock", "wood"), ("StockGrip", "wood"), ("Grip", "wood"),
        ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


def build_g28():
    reset()
    ry = 0.024
    add_box("Receiver", (0.05, 0.075, 0.32), (0, 0.016, -0.06), bevel=0.0014)
    add_box("Handguard", (0.046, 0.026, 0.40), (0, 0.062, -0.16), bevel=0.0012)
    dmr_rail(0.02, -0.42, mount_h=0.0)
    add_cyl("Barrel", 0.012, 0.56, (0, ry, -0.49), axis="z", seg=18, bevel=0.0006, taper=0.9)
    add_cyl("FlashHider", 0.016, 0.05, (0, ry, -0.755), axis="z", seg=14, bevel=0.0005)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.36, mat="dark")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.046, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 + 0.038), bevel=0.0004)
    add_mag_straight("mag", 0.036, 0.10, 0.06, (0, 0.006, -0.10), tilt=0.10, mat="tan")
    for p in skeleton_dmr_stock(0.024, 0.110, 0.28, "poly"):
        pass
    bolt_handle_assembly(0.028, -0.02)
    add_irons("StockIrons", 0.110, -0.55, 0.05, 0.05, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "tan"), ("Handguard", "dark"), ("Stock", "poly"),
        ("CheekRest", "poly"), ("StockGrip", "poly"), ("Grip", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"),
    ], default="dark")


def build_mk14():
    reset()
    ry = 0.024
    add_box("Receiver", (0.05, 0.075, 0.34), (0, 0.016, -0.06), bevel=0.0014)
    add_box("Handguard", (0.046, 0.028, 0.46), (0, 0.062, -0.20), bevel=0.0012)
    dmr_rail(0.02, -0.44, mount_h=0.0)
    add_cyl("Barrel", 0.012, 0.62, (0, ry, -0.53), axis="z", seg=18, bevel=0.0006, taper=0.9)
    add_cyl("Muzzle", 0.016, 0.05, (0, ry, -0.815), axis="z", seg=14, bevel=0.0005)
    add_box("LowerRail", (0.046, 0.018, 0.28), (0, 0.018, -0.32), bevel=0.0006)  # EBR 下轨
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.36, mat="dark")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.046, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 + 0.038), bevel=0.0004)
    add_mag_straight("mag", 0.038, 0.12, 0.06, (0, 0.006, -0.09), tilt=0.08, mat="tan")
    for p in skeleton_dmr_stock(0.024, 0.120, 0.28, "tan"):
        pass
    bolt_handle_assembly(0.030, -0.02)
    add_irons("StockIrons", 0.110, -0.55, 0.05, 0.05, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "dark"), ("Handguard", "dark"), ("LowerRail", "tan"),
        ("Stock", "tan"), ("CheekRest", "tan"), ("StockGrip", "tan"), ("Grip", "dark"),
        ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


def build_m14():
    reset()
    ry = 0.026
    add_cyl("Barrel", 0.012, 0.58, (0, ry, -0.51), axis="z", seg=18, bevel=0.0006, taper=0.9)
    add_cyl("Muzzle", 0.016, 0.05, (0, ry, -0.775), axis="z", seg=14, bevel=0.0005)
    add_box("Receiver", (0.05, 0.082, 0.34), (0, 0.016, -0.06), bevel=0.0014)
    add_box("ReceiverCover", (0.046, 0.028, 0.32), (0, 0.064, -0.12), bevel=0.0008)
    add_picatinny("TopRail", 0.16, (0, 0.0854, -0.12), width=0.020, mount_h=0.006)
    add_box("BayonetLug", (0.016, 0.03, 0.10), (0.03, -0.01, -0.55), bevel=0.0004)
    add_stock("StockGrip", 0.042, 0.095, 0.18, 0.11, 0.057, drop=0.12, plate=False)
    add_box("Stock", (0.046, 0.1, 0.02), (0, 0.0, 0.28), bevel=0.0010)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.40, mat="wood")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.046, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 + 0.038), bevel=0.0004)
    add_mag_straight("mag", 0.038, 0.12, 0.06, (0, 0.006, -0.09), tilt=0.08, mat="dark")
    bolt_handle_assembly(0.030, 0.0)
    add_irons("StockIrons", 0.112, -0.56, 0.05, 0.06, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "metal"), ("ReceiverCover", "metal"), ("BayonetLug", "dark"),
        ("Stock", "wood"), ("StockGrip", "wood"), ("Grip", "wood"),
        ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


def build_ar10():
    reset()
    ry = 0.024
    add_box("Receiver", (0.05, 0.075, 0.32), (0, 0.016, -0.06), bevel=0.0014)
    add_box("Handguard", (0.046, 0.026, 0.38), (0, 0.062, -0.16), bevel=0.0012)
    dmr_rail(0.01, -0.40, mount_h=0.0)
    add_cyl("Barrel", 0.012, 0.54, (0, ry, -0.48), axis="z", seg=18, bevel=0.0006, taper=0.9)
    add_cyl("FlashHider", 0.016, 0.05, (0, ry, -0.735), axis="z", seg=14, bevel=0.0005)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.36, mat="dark")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.046, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.046 + 0.009, 0.020 + 0.038), bevel=0.0004)
    add_mag_straight("mag", 0.036, 0.10, 0.06, (0, 0.006, -0.10), tilt=0.10, mat="dark")
    for p in skeleton_dmr_stock(0.024, 0.105, 0.28, "poly"):
        pass
    bolt_handle_assembly(0.028, -0.02)
    add_irons("StockIrons", 0.110, -0.54, 0.05, 0.05, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "poly"), ("Handguard", "dark"), ("Stock", "poly"),
        ("CheekRest", "poly"), ("StockGrip", "poly"), ("Grip", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"),
    ], default="dark")


def build_fal():
    reset()
    ry = 0.026
    add_cyl("Barrel", 0.012, 0.55, (0, ry, -0.49), axis="z", seg=18, bevel=0.0006, taper=0.9)
    add_cyl("Muzzle", 0.016, 0.05, (0, ry, -0.755), axis="z", seg=14, bevel=0.0005)
    add_box("Receiver", (0.05, 0.08, 0.34), (0, 0.016, -0.06), bevel=0.0014)
    add_box("ReceiverCover", (0.046, 0.026, 0.32), (0, 0.062, -0.12), bevel=0.0008)
    add_picatinny("TopRail", 0.16, (0, 0.0824, -0.14), width=0.020, mount_h=0.006)
    add_box("WoodHandguard", (0.046, 0.04, 0.20), (0, 0.012, -0.24), bevel=0.0010)
    add_stock("StockGrip", 0.042, 0.095, 0.18, 0.11, 0.056, drop=0.12, plate=False)
    add_box("Stock", (0.046, 0.1, 0.02), (0, 0.0, 0.28), bevel=0.0010)
    add_grip("Grip", 0.034, 0.1, 0.045, (0, -0.024, 0.04), tilt=0.40, mat="wood")
    add_box("TriggerGuard", (0.026, 0.008, 0.085), (0, -0.044, 0.020), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.026, 0.008), (0, -0.044 + 0.009, 0.020 - 0.038), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.026, 0.008), (0, -0.044 + 0.009, 0.020 + 0.038), bevel=0.0004)
    add_mag_straight("mag", 0.038, 0.12, 0.06, (0, 0.006, -0.09), tilt=0.08, mat="dark")
    # FAL 拉机柄在左侧
    bolt_handle_assembly(0.030, -0.08, side=-1.0)
    add_irons("StockIrons", 0.112, -0.56, 0.05, 0.06, ry)
    apply_materials([("ButtPad", "dark"), ("CheekKnob", "metal"), ("StockCheck", "wood")]
                      + TRIGGER_GUARD_RULES + [
        ("Receiver", "metal"), ("ReceiverCover", "metal"),
        ("WoodHandguard", "wood"), ("Stock", "wood"), ("StockGrip", "wood"), ("Grip", "wood"),
        ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


BUILDERS = {
    "m110": build_m110,
    "sks": build_sks,
    "m1a": build_m1a,
    "g28": build_g28,
    "mk14": build_mk14,
    "m14": build_m14,
    "ar10": build_ar10,
    "fal": build_fal,
}

NO_MAG = {"sks"}   # 固定弹仓


def main():
    targets = list(BUILDERS.keys())
    argv = sys.argv
    if "--" in argv:
        tail = argv[argv.index("--") + 1:]
        if tail:
            targets = [t for t in tail if t in BUILDERS]
    os.makedirs(OUT_DIR, exist_ok=True)
    print("=" * 60)
    for wid in targets:
        BUILDERS[wid]()
        objs, verts, tris = stats()
        path = os.path.join(OUT_DIR, "%s.glb" % wid)
        export_glb(path)
        names = sorted(o.name for o in bpy.data.objects)
        need = ["bolt", "StockIrons"]
        if wid not in NO_MAG:
            need.append("mag")
        ok = all(k in names for k in need)
        print("%-6s objs=%-4d verts=%-6d tris=%-6d  契约=%s  %.0f KB" % (
            wid, objs, verts, tris, "OK" if ok else "MISSING!",
            os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
