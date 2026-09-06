"""
冲锋枪批次建模(8 把):MP5 / UMP / P90 / Vector / PP-19 / MPX / MP7 / PP-2000

尺寸沿用 weapon_models.gd 程序化定义,锚点(HAND_ANCHORS/MUZZLE_Z/MOD_ANCHORS)零改动。
导轨教训已吸收:侧轨必须 rot_z 转向 + mount_h 贴合,凡加导轨一律带上。

特殊结构:
    P90    顶置弹匣(与枪管平行横置,半透明) + 左右对称拉机柄
    PP-19  枪管下方长筒螺旋弹匣(弹匣即护木)
    MP7    握把式弹匣(穿过握把)
    PP2000 前置握把弹匣(弹匣兼前握把)

用法:
    blender --background --python build_smg_batch.py               # 全部 8 把
    blender --background --python build_smg_batch.py -- mp5 p90    # 指定
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


def _fold_stock(hinge_z, top_y=0.045, bot_y=-0.012, arm_len=0.14, plate_z=None):
    """侧折叠骨架托:铰链 + 上下杆 + 托底板(SMG 通用件)。"""
    pz = plate_z if plate_z is not None else hinge_z + 0.12
    return [
        add_box("StockHinge", (0.028, 0.050, 0.040), (0, 0.005, hinge_z), bevel=0.0010),
        add_box("StockArmTop", (0.022, 0.020, arm_len), (0, top_y, hinge_z + 0.06), bevel=0.0008),
        add_box("StockArmBot", (0.022, 0.020, arm_len), (0, bot_y, hinge_z + 0.06), bevel=0.0008),
        add_box("StockPlate", (0.040, 0.075, 0.024), (0, 0.008, pz), bevel=0.0010),
    ]


# ============================================================ MP5
def build_mp5():
    reset()
    ry = 0.020
    # 钢机匣 + 顶部拉机柄管(MP5 标志性的前管)
    add_box("Receiver", (0.044, 0.062, 0.300), (0, 0.014, -0.030), bevel=0.0014)
    add_cyl("ChargingTube", 0.012, 0.200, (0, 0.030, -0.160), axis="z", seg=14, bevel=0.0006)
    # 机匣顶轨(optic 落点):齿顶 0.0524,位于拉机柄管上方
    add_picatinny("TopRail", 0.16, (0, 0.0524, -0.060), width=0.020, mount_h=0.006)
    # 宽聚合物护木 + 散热棱
    add_box("Handguard", (0.052, 0.052, 0.150), (0, 0.012, -0.260), bevel=0.0014)
    for i in range(4):
        add_box("HGRib%d" % i, (0.054, 0.005, 0.012), (0, 0.037, -0.300 + i * 0.030), bevel=0.0004)
    # 短枪管 + 三耳枪口
    add_cyl("Barrel", 0.0090, 0.180, (0, ry, -0.380), axis="z", seg=14, bevel=0.0005)
    add_cyl("MuzzleCollar", 0.0135, 0.040, (0, ry, -0.470), axis="z", seg=14, bevel=0.0005)
    for s in (-1.0, 1.0):
        add_box("MuzzleLug%s" % ("L" if s < 0 else "R"), (0.007, 0.007, 0.020),
                (s * 0.010, ry, -0.490), bevel=0.0004)
    # A2 固定托(直托修正) + 握把
    add_stock("StockBody", 0.038, 0.070, 0.135, 0.120, 0.045, drop=0.10)
    add_grip("Grip", 0.030, 0.090, 0.040, (0, -0.020, 0.040), tilt=0.40, ribs=3)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.034, 0.010), bevel=0.0005)
    add_trigger_guard(-0.042, -0.005, 0.050)
    # 弧形弹匣(可动) + 桨式释放钮
    add_mag_curved("MagCurved", 0.032, (0, -0.020, -0.100))
    add_box("MagPaddle", (0.010, 0.030, 0.030), (0.024, -0.040, -0.060), bevel=0.0006)
    # 左前拉机柄(可动,MP5 拍柄是它的招牌)
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.026), (-0.028, 0.035, -0.220), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.007, 0.014, (-0.038, 0.035, -0.220), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    # 鼓式照门(圆觇孔 + 护圈准星)整组归 StockIrons
    irs = [
        add_box("IronsFrontBase", (0.014, 0.026, 0.014), (0, 0.043, -0.420), bevel=0.0005),
        add_box("IronsFront", (0.006, 0.020, 0.012), (0, 0.068, -0.420), bevel=0.0004),
        add_cyl("RearDrum", 0.0095, 0.012, (0, 0.090, 0.100), axis="z", seg=14, bevel=0.0004),
        add_box("IronsRearL", (0.005, 0.012, 0.012), (-0.007, 0.087, 0.100), bevel=0.0004),
        add_box("IronsRearR", (0.005, 0.012, 0.012), (0.007, 0.087, 0.100), bevel=0.0004),
    ]
    join_parts("StockIrons", irs)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"), ("RearDrum", "dark"),
        ("Receiver", "metal"), ("ChargingTube", "dark"), ("Handguard", "poly"),
        ("Stock", "poly"), ("Grip", "poly"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("Muzzle", "dark"), ("bolt", "dark"),
        ("mag", "dark"), ("Mag", "dark"), ("MagPaddle", "dark"),
    ], default="dark")


# ============================================================ UMP
def build_ump():
    reset()
    ry = 0.022
    # 聚合物机匣 + 顶部短轨(齿顶 0.072,机匣顶 0.045 → 垫 0.0194)
    add_box("Receiver", (0.048, 0.066, 0.260), (0, 0.012, -0.020), bevel=0.0014)
    add_rail("TopRail", 0.072, 0.040, -0.200, w=0.022, mount_h=0.0194)
    # 短护木 + 底部附件轨(齿朝下,贴护木底 0.020+0.0074)
    add_box("Handguard", (0.046, 0.050, 0.120), (0, 0.005, -0.220), bevel=0.0012)
    add_picatinny("RailBottom", 0.100, (0, -0.0274, -0.220), width=0.018, rot_z=math.pi)
    # 短枪管 + 枪口环
    add_cyl("Barrel", 0.0100, 0.140, (0, ry, -0.320), axis="z", seg=14, bevel=0.0005)
    add_cyl("MuzzleCollar", 0.0135, 0.030, (0, ry, -0.400), axis="z", seg=14, bevel=0.0005)
    # 侧折叠骨架托 + 握把
    _fold_stock(0.120, plate_z=0.250)
    add_grip("Grip", 0.032, 0.095, 0.045, (0, -0.020, 0.045), tilt=0.38, ribs=4)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.034, 0.020), bevel=0.0005)
    add_trigger_guard(-0.042, 0.005, 0.055)
    # .45 宽直弹匣(可动)
    add_mag_straight("MagShell", 0.040, 0.120, 0.060, (0, -0.020, -0.050), holes=2)
    # 左侧拉机柄(可动) + 释放杆
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.026), (-0.029, 0.045, -0.080), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.007, 0.014, (-0.039, 0.045, -0.080), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_box("MagRelease", (0.008, 0.030, 0.040), (-0.027, -0.020, -0.020), bevel=0.0006)
    add_irons("StockIrons", 0.100, -0.320, 0.060, 0.045, ry)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "poly"), ("Handguard", "poly"), ("Stock", "poly"),
        ("Grip", "poly"), ("Trigger", "dark"), ("Barrel", "dark"),
        ("Muzzle", "dark"), ("Rail", "dark"), ("TopRail", "dark"),
        ("bolt", "dark"), ("mag", "dark"), ("Mag", "dark"),
        ("MagRelease", "dark"),
    ], default="dark")


# ============================================================ P90
def build_p90():
    reset()
    ry = 0.008
    # 一体式枪身/枪托(高 100mm)
    add_box("Receiver", (0.052, 0.100, 0.380), (0, -0.005, -0.020), bevel=0.0018)
    add_box("StockExt", (0.050, 0.085, 0.100), (0, 0.0, 0.180), bevel=0.0014)
    add_box("StockPlate", (0.052, 0.090, 0.024), (0, 0.0, 0.235), bevel=0.0012)
    # TR 平顶机匣平台
    add_box("TopDeck", (0.046, 0.018, 0.240), (0, 0.052, -0.050), bevel=0.0010)
    # 前侧短轨(装在瞄具座,垫块贴合顶台 0.061)
    add_picatinny("TopRail", 0.160, (0, 0.078, -0.120), width=0.022, mount_h=0.0096)
    # 低位枪管 + 斜切消焰器
    add_cyl("Barrel", 0.0080, 0.260, (0, ry, -0.220), axis="z", seg=14, bevel=0.0005)
    add_cyl("MuzzleComp", 0.0115, 0.035, (0, ry, -0.325), axis="z", seg=14, bevel=0.0005)
    # 前侧弹匣卡槽
    add_box("MagFrontSlot", (0.046, 0.012, 0.040), (0, 0.056, -0.160), bevel=0.0008)
    # 顶置弹匣(半透明,可动):弹体沿枪管方向横置
    mag_parts = [
        add_box("MagBody", (0.042, 0.028, 0.300), (0, 0.062, -0.020), bevel=0.0010),
        add_box("_mag_ridge", (0.044, 0.008, 0.310), (0, 0.076, -0.020), bevel=0.0005),
        add_box("_mag_ramp", (0.040, 0.020, 0.060), (0, 0.058, 0.120), bevel=0.0006),
        add_box("_mag_head", (0.040, 0.024, 0.020), (0, 0.062, -0.170), bevel=0.0006),
    ]
    for s in (-1.0, 1.0):
        mag_parts.append(add_box("_mag_catch%s" % ("L" if s < 0 else "R"),
                                 (0.006, 0.014, 0.016), (s * 0.023, 0.066, -0.150), bevel=0.0004))
    for wz in [-0.070, 0.000, 0.070]:
        mag_parts.append(add_box("_mag_win%d" % int(wz * 1000), (0.046, 0.013, 0.040),
                                 (0, 0.062, wz), bevel=0.0004))
    mag = join_parts("MagShell", mag_parts)
    mag.name = "mag"
    # 超大扳机护圈兼前握把 + 手挡
    add_box("TriggerGuardBridge", (0.044, 0.018, 0.240), (0, -0.055, -0.020), bevel=0.0008)
    add_grip("Foregrip", 0.034, 0.050, 0.040, (0, -0.070, -0.140), tilt=0.2)
    # 拇指孔握把 + 三档旋钮
    add_grip("Grip", 0.034, 0.085, 0.050, (0, -0.050, 0.100), tilt=0.28, ribs=3)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.048, 0.015), bevel=0.0005)
    add_cyl("FireSelector", 0.009, 0.012, (0, -0.060, 0.0), axis="y", seg=12, bevel=0.0004)
    # 抛壳槽(枪托下方)
    add_box("EjectionChute", (0.030, 0.030, 0.080), (0, -0.060, 0.150), bevel=0.0006)
    # 左右对称拉机柄(可动)
    ch_l = add_cyl("ChargingHandleL", 0.007, 0.030, (-0.028, 0.032, 0.160), axis="x", seg=12, bevel=0.0005)
    ch_r = add_cyl("ChargingHandleR", 0.007, 0.030, (0.028, 0.032, 0.160), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch_l, ch_r])
    # 原厂氚光铁瞄(前侧短轨上方)整组归 StockIrons
    irs = [
        add_box("IronsRearBase", (0.012, 0.008, 0.012), (0, 0.074, -0.040), bevel=0.0004),
        add_box("IronsRearL", (0.003, 0.012, 0.008), (-0.0045, 0.084, -0.040), bevel=0.0004),
        add_box("IronsRearR", (0.003, 0.012, 0.008), (0.0045, 0.084, -0.040), bevel=0.0004),
        add_box("IronsFront", (0.004, 0.018, 0.006), (0, 0.081, -0.180), bevel=0.0004),
    ]
    join_parts("StockIrons", irs)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "poly"), ("Stock", "poly"), ("TopDeck", "poly"),
        ("Foregrip", "poly"), ("Grip", "poly"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("Muzzle", "dark"), ("TopRail", "dark"),
        ("bolt", "dark"), ("TriggerGuard", "poly"), ("Ejection", "dark"),
        ("mag", "tan"), ("Mag", "tan"),
    ], default="dark")


# ============================================================ Vector
def build_vector():
    reset()
    ry = 0.020
    # 上下两段斜切机匣(Vector 的标志:下段聚合物斜体)
    add_box("UpperReceiver", (0.050, 0.046, 0.240), (0, 0.032, -0.080), bevel=0.0014)
    add_box("LowerReceiver", (0.046, 0.060, 0.200), (0, -0.012, -0.020), bevel=0.0014)
    skirt = add_box("LowerSkirt", (0.044, 0.040, 0.100), (0, -0.018, -0.140), bevel=0.0012)
    skirt.rotation_euler = rot_g2b((-0.25, 0, 0))
    # 顶轨(上机匣顶 0.055 → 垫 0.0236)
    add_rail("TopRail", 0.076, 0.020, -0.300, w=0.024, mount_h=0.0336)  # 齿顶距 sight_y(0.088) 12mm
    # 短枪管 + 消焰器
    add_cyl("Barrel", 0.0140, 0.200, (0, ry, -0.360), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0185, 0.050, (0, ry, -0.470), axis="z", seg=16, bevel=0.0006)
    # 前垂直握把
    add_grip("Foregrip", 0.026, 0.060, 0.035, (0, -0.020, -0.160), tilt=0.20, ribs=3)
    # 折叠托
    _fold_stock(0.100, top_y=0.042, bot_y=-0.010, plate_z=0.230)
    # 握把 + 前倾弹匣(KRISS 的弹匣插在握把里,前倾 0.18)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.024, 0.040), tilt=0.38, ribs=4)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.036, 0.010), bevel=0.0005)
    add_trigger_guard(-0.044, 0.000, 0.050)
    add_mag_straight("MagShell", 0.034, 0.140, 0.050, (0, -0.024, -0.060), tilt=0.18, holes=2)
    # 左侧拉机柄(可动)
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.026), (-0.030, 0.040, 0.0), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.007, 0.014, (-0.040, 0.040, 0.0), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.088, -0.400, 0.040, 0.045, ry)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Upper", "metal"), ("Lower", "poly"), ("Skirt", "poly"),
        ("Handguard", "poly"), ("Stock", "poly"), ("Foregrip", "poly"),
        ("Grip", "poly"), ("Trigger", "dark"), ("Barrel", "dark"),
        ("FlashHider", "dark"), ("TopRail", "dark"), ("bolt", "dark"),
        ("mag", "dark"), ("Mag", "dark"),
    ], default="dark")


# ============================================================ PP-19
def build_pp19():
    reset()
    ry = 0.024
    # AK 式短机匣 + 防尘盖 + 右侧保险
    add_box("Receiver", (0.050, 0.062, 0.260), (0, 0.012, -0.030), bevel=0.0014)
    add_box("DustCover", (0.046, 0.018, 0.220), (0, 0.050, -0.040), bevel=0.0008)
    add_box("SafetyLever", (0.011, 0.018, 0.090), (0.028, 0.012, -0.020), bevel=0.0006)
    # 枪管 + 上护木 + 准星座 + 枪口
    add_cyl("Barrel", 0.0110, 0.420, (0, ry, -0.380), axis="z", seg=16, bevel=0.0006)
    add_box("HandguardTop", (0.044, 0.030, 0.130), (0, 0.052, -0.280), bevel=0.0010)
    add_box("FrontSightBase", (0.018, 0.045, 0.024), (0, 0.048, -0.560), bevel=0.0008)
    add_cyl("MuzzleCollar", 0.0145, 0.040, (0, ry, -0.580), axis="z", seg=14, bevel=0.0005)
    # 螺旋弹匣:枪管下方长筒 + 肋环 + 前后端盖(弹匣即护木,可动)
    hp = []
    hp.append(add_cyl("MagTube", 0.037, 0.360, (0, -0.068, -0.335), axis="z", seg=20, bevel=0.0008))
    for i, rz in enumerate([-0.12, -0.04, 0.04, 0.12]):
        hp.append(add_cyl("MagRib%d" % i, 0.041, 0.014, (0, -0.068, -0.335 + rz),
                          axis="z", seg=20, bevel=0.0004))
    hp.append(add_cyl("MagCapR", 0.042, 0.030, (0, -0.068, -0.155), axis="z", seg=20, bevel=0.0006))
    hp.append(add_cyl("MagCapF", 0.042, 0.025, (0, -0.068, -0.525), axis="z", seg=20, bevel=0.0006))
    hp.append(add_box("MagMount", (0.048, 0.050, 0.080), (0, -0.043, -0.155), bevel=0.0008))
    hp.append(add_box("MagRailSeat", (0.044, 0.030, 0.050), (0, -0.015, -0.465), bevel=0.0006))
    mag = join_parts("MagShell", hp)
    mag.name = "mag"
    # 侧折叠骨架托 + 握把
    _fold_stock(0.130, plate_z=0.250)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.022, 0.040), tilt=0.38, ribs=3)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.034, 0.0), bevel=0.0005)
    add_trigger_guard(-0.042, -0.005, 0.050)
    # 右侧拉机柄(可动)
    ch = add_box("ChargingHandle", (0.012, 0.014, 0.028), (0.030, 0.040, -0.020), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.008, 0.016, (0.040, 0.040, -0.020), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.095, -0.440, 0.030, 0.050, ry)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "metal"), ("DustCover", "metal"), ("SafetyLever", "metal"),
        ("Handguard", "poly"), ("Stock", "poly"), ("Grip", "poly"),
        ("Trigger", "dark"), ("Barrel", "dark"), ("Muzzle", "dark"),
        ("bolt", "dark"), ("mag", "dark"), ("Mag", "dark"), ("MagRib", "metal"),
    ], default="dark")


# ============================================================ MPX
def build_mpx():
    reset()
    ry = 0.024
    # 上下机匣 + 一体顶轨(上机匣顶 0.061 → 垫 0.0136)
    add_box("LowerReceiver", (0.050, 0.050, 0.240), (0, -0.005, -0.020), bevel=0.0014)
    add_box("UpperReceiver", (0.046, 0.028, 0.300), (0, 0.047, -0.100), bevel=0.0014)
    add_rail("TopRail", 0.078, 0.020, -0.340, w=0.024, mount_h=0.0176)  # 齿顶距 sight_y(0.090) 12mm
    # 细长护木 + 侧/底短轨(全部转向贴合)
    add_box("Handguard", (0.042, 0.046, 0.150), (0, 0.008, -0.260), bevel=0.0012)
    add_picatinny("RailBottom", 0.110, (0, -0.0224, -0.260), width=0.016, rot_z=math.pi)
    for s in (-1.0, 1.0):
        side = "L" if s < 0 else "R"
        add_picatinny("Rail%s" % side, 0.110,
                      (s * 0.0284, 0.012, -0.260), width=0.016,
                      rot_z=(-math.pi * 0.5 if s > 0 else math.pi * 0.5))
    # 短枪管 + 消焰器
    add_cyl("Barrel", 0.0110, 0.400, (0, ry, -0.440), axis="z", seg=16, bevel=0.0006)
    fh = add_cyl("FlashHider", 0.0155, 0.040, (0, ry, -0.660), axis="z", seg=16, bevel=0.0006)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cut(fh, add_box("_fh%d" % i, (0.006, 0.006, 0.024),
                        (math.cos(ang) * 0.014, ry + math.sin(ang) * 0.014, -0.665)))
    # 侧折叠骨架托 + 握把
    _fold_stock(0.120, top_y=0.044, plate_z=0.250)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.023, 0.040), tilt=0.36, ribs=4)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.035, 0.005), bevel=0.0005)
    add_trigger_guard(-0.043, 0.000, 0.050)
    # 直弹匣(可动)
    add_mag_straight("MagShell", 0.034, 0.130, 0.055, (0, -0.023, -0.090), tilt=0.12, holes=2)
    # 右侧拉机柄(可动,AR 式位于机匣上方)
    ch = add_box("ChargingHandle", (0.012, 0.012, 0.028), (0.028, 0.050, 0.040), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.008, 0.016, (0.038, 0.050, 0.040), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.090, -0.500, 0.050, 0.045, ry)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Upper", "metal"), ("Lower", "poly"), ("Handguard", "poly"),
        ("Stock", "poly"), ("Grip", "poly"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("Rail", "dark"),
        ("TopRail", "dark"), ("bolt", "dark"), ("mag", "dark"), ("Mag", "dark"),
    ], default="dark")


# ============================================================ MP7
def build_mp7():
    reset()
    ry = 0.018
    # 紧凑机匣 + 顶轨(机匣顶 0.045 → 垫 0.0226)
    add_box("Receiver", (0.042, 0.060, 0.260), (0, 0.015, -0.050), bevel=0.0014)
    add_rail("TopRail", 0.070, 0.030, -0.280, w=0.022, mount_h=0.0276)  # 齿顶距 sight_y(0.082) 12mm
    # 细短枪管 + 开槽消焰器
    add_cyl("Barrel", 0.0080, 0.260, (0, ry, -0.320), axis="z", seg=14, bevel=0.0005)
    fh = add_cyl("FlashHider", 0.0115, 0.040, (0, ry, -0.460), axis="z", seg=14, bevel=0.0005)
    for s in (-1.0, 1.0):
        cut(fh, add_box("_fh%d" % s, (0.005, 0.005, 0.026),
                        (s * 0.009, ry, -0.455)))
    # 折叠前握把
    add_grip("Foregrip", 0.024, 0.060, 0.032, (0, -0.018, -0.140), tilt=0.20)
    # 伸缩托(双杆 + 托垫)
    add_cyl("StockRodL", 0.006, 0.120, (-0.012, 0.035, 0.140), axis="z", seg=10)
    add_cyl("StockRodR", 0.006, 0.120, (0.012, 0.035, 0.140), axis="z", seg=10)
    add_box("StockPlate", (0.038, 0.075, 0.022), (0, 0.008, 0.210), bevel=0.0010)
    # 握把 + 握把弹匣(MP7 弹匣插在握把里,可动)
    add_grip("Grip", 0.028, 0.090, 0.040, (0, -0.020, 0.030), tilt=0.38, ribs=3)
    add_box("Trigger", (0.007, 0.020, 0.008), (0, -0.033, 0.010), bevel=0.0005)
    add_trigger_guard(-0.040, 0.000, 0.042)
    add_mag_straight("MagShell", 0.030, 0.140, 0.045, (0, -0.020, -0.100), tilt=0.10)
    # 右侧拉机柄(可动)
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.024), (0.024, 0.045, 0.030), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.007, 0.014, (0.033, 0.045, 0.030), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.085, -0.420, 0.045, 0.040, ry)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "poly"), ("Stock", "poly"), ("Foregrip", "poly"),
        ("Grip", "poly"), ("Trigger", "dark"), ("Barrel", "dark"),
        ("FlashHider", "dark"), ("TopRail", "dark"), ("StockRod", "metal"),
        ("bolt", "dark"), ("mag", "dark"), ("Mag", "dark"),
    ], default="dark")


# ============================================================ PP-2000
def build_pp2000():
    reset()
    ry = 0.024
    # 方形机匣 + 顶轨(机匣顶 0.049 → 垫 0.0236)
    add_box("Receiver", (0.046, 0.070, 0.300), (0, 0.014, -0.020), bevel=0.0014)
    add_rail("TopRail", 0.080, 0.040, -0.320, w=0.024, mount_h=0.0236)
    # 短枪管 + 枪口
    add_cyl("Barrel", 0.0110, 0.300, (0, ry, -0.380), axis="z", seg=16, bevel=0.0006)
    add_cyl("MuzzleCollar", 0.0145, 0.035, (0, ry, -0.530), axis="z", seg=14, bevel=0.0005)
    # 前置握把弹匣(弹匣兼前握把,可动) —— 握把壳体固定,弹匣从里面插
    add_grip("ForegripShell", 0.034, 0.078, 0.052, (0, -0.022, -0.080), tilt=0.28, ribs=0)
    add_mag_straight("MagShell", 0.028, 0.160, 0.046, (0, -0.030, -0.080), tilt=0.28)
    # 扳机 + 护圈
    add_box("Trigger", (0.007, 0.020, 0.008), (0, -0.034, 0.020), bevel=0.0005)
    add_trigger_guard(-0.042, 0.005, 0.052)
    # 后置折叠托
    _fold_stock(0.140, top_y=0.045, bot_y=-0.010, arm_len=0.14, plate_z=0.260)
    add_grip("Grip", 0.030, 0.085, 0.042, (0, -0.022, 0.060), tilt=0.34, ribs=3)
    # 左侧拉机柄(可动)
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.024), (-0.026, 0.040, 0.020), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.007, 0.014, (-0.035, 0.040, 0.020), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.090, -0.460, 0.040, 0.042, ry)
    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "poly"), ("Stock", "poly"), ("Foregrip", "poly"),
        ("Grip", "poly"), ("Trigger", "dark"), ("Barrel", "dark"),
        ("Muzzle", "dark"), ("TopRail", "dark"), ("bolt", "dark"),
        ("mag", "dark"), ("Mag", "dark"),
    ], default="dark")


BUILDERS = {
    "mp5": build_mp5,
    "ump": build_ump,
    "p90": build_p90,
    "vector": build_vector,
    "pp19": build_pp19,
    "mpx": build_mpx,
    "mp7": build_mp7,
    "pp2000": build_pp2000,
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
    for wid in targets:
        BUILDERS[wid]()
        objs, verts, tris = stats()
        path = os.path.join(OUT_DIR, "%s.glb" % wid)
        export_glb(path)
        names = sorted(o.name for o in bpy.data.objects if o.type == 'MESH')
        print("%-7s objs=%-4d verts=%-6d tris=%-6d  mag=%s bolt=%s  %.0f KB" % (
            wid, objs, verts, tris,
            "OK" if "mag" in names else "MISSING",
            "OK" if "bolt" in names else "MISSING",
            os.path.getsize(path) / 1024.0))
    print("=" * 60)
    print("输出目录:", OUT_DIR)


if __name__ == "__main__":
    main()
