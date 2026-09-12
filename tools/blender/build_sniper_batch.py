"""
狙击枪批次建模(8 把):AWM / M24 / SVD / M40A3 / M82A1 / L115A3 / SV-98 / M2010 ESR

尺寸沿用 weapon_models.gd 程序化定义(_scope/_simple_scope 调用参数),锚点零改动。

狙击镜 PIP 契约(docs/sniper_pistol_prep.md,缺一项开镜就废):
    StockOptic     原厂镜整组(空节点,Godot 提升到武器根)
    ScopeTubeBody  镜筒+物镜圈+调节钮(join)
    ScopeMounts    前后支架
    ScopeEye       空节点,PIP 相机挂点 —— 必须是 StockOptic 的子节点
    ScopeLensBlack / ScopeLensClear / RetCross   ScopeEye 的子节点

换弹契约:
    bolt   栓动枪机总成(空仓 bolt_cycle 沿 Z 滑动) / 半自动为拉机柄
    mag    弹匣(m24/m40 内仓枪无此件,mag_style=none)

用法:
    blender --background --python build_sniper_batch.py
    blender --background --python build_sniper_batch.py -- awm svd
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


# ---------------------------------------------------------------- 狙击组件

def bolt_assembly(y, z_rear, style="bolt", handle_r=0.008):
    """枪机总成。栓动枪(style='bolt')是带下弯球头柄的圆柱机头,join 为单对象,
    空仓换弹的 bolt_cycle 沿 Z 前后滑动;半自动('handle')只是拉机柄。"""
    parts = []
    if style == "bolt":
        parts.append(add_cyl("BoltBody", 0.011, 0.115, (0, y, z_rear - 0.058), axis="z", seg=16, bevel=0.0006))
        # 拉机柄:从机头右侧斜向下弯出,球头
        parts.append(add_cyl("BoltArm", 0.005, 0.038, (0.018, y - 0.012, z_rear - 0.012), axis="x", seg=10, bevel=0.0004))
        parts.append(add_torus("BoltKnob", 0.0085, 0.0042, (0.040, y - 0.016, z_rear - 0.012), seg_major=16, seg_minor=8))
    else:
        parts.append(add_cyl("BoltBody", 0.008, 0.050, (0, y + 0.006, z_rear), axis="z", seg=12, bevel=0.0005))
        parts.append(add_cyl("BoltArm", 0.0045, 0.030, (0.014, y - 0.006, z_rear + 0.010), axis="x", seg=10, bevel=0.0004))
        parts.append(add_torus("BoltKnob", 0.0075, 0.0038, (0.030, y - 0.008, z_rear + 0.010), seg_major=14, seg_minor=8))
    return join_parts("bolt", parts)


def sniper_scope(y, z_center, base_y, tube_len=0.24, front_r=0.024, rear_r=0.030, sunshade=False):
    """原厂狙击镜(契约链见文件头)。镜筒后粗前细锥形,ScopeEye 在目镜后缘。
    v2:遮阳罩 + 视差钮 + 炮塔滚花棱(高细节版)。"""
    eye_z = z_center + tube_len * 0.5 + 0.018
    optic = add_empty("StockOptic", (0, y, z_center))
    tube_parts = [
        add_cyl("TubeMain", rear_r, tube_len, (0, y, z_center), axis="z", seg=24, taper=front_r / rear_r, bevel=0.0008),
        add_torus("_ObjRing", front_r + 0.0035, 0.0030, (0, y, z_center - tube_len * 0.5), seg_major=24, seg_minor=8),
        add_torus("_OcularRing", rear_r + 0.003, 0.0028, (0, y, z_center + tube_len * 0.5), seg_major=24, seg_minor=8),
        # 俯仰/风偏炮塔 + 滚花棱
        add_cyl("_TurretElev", 0.0065, 0.016, (0, y + rear_r + 0.004, z_center + 0.01), axis="y", seg=12, bevel=0.0004),
        add_cyl("_TurretWind", 0.0065, 0.016, (rear_r + 0.004, y, z_center + 0.01), axis="x", seg=12, bevel=0.0004),
    ]
    for i in range(6):
        a = float(i) / 6.0 * math.tau
        tube_parts.append(add_box("_TurretElevK%d" % i, (0.003, 0.017, 0.003),
                                  (0.0055 * math.cos(a), y + rear_r + 0.004, z_center + 0.01 + 0.0055 * math.sin(a)), bevel=0.0002))
        tube_parts.append(add_box("_TurretWindK%d" % i, (0.017, 0.003, 0.003),
                                  (rear_r + 0.004 + 0.0055 * math.cos(a), 0.0055 * math.sin(a), z_center + 0.01), bevel=0.0002))
    if sunshade:
        tube_parts.append(add_scope_sunshade(y, z_center - tube_len * 0.5, front_r))
    tube_parts.append(add_parallax_knob("ParallaxKnob", y, z_center - tube_len * 0.30, front_r * 0.9))
    tube = join_parts("ScopeTubeBody", tube_parts)
    mh = (y - front_r - 0.006) - base_y
    if mh < 0.006:
        mh = 0.006
    mounts = join_parts("ScopeMounts", [
        add_cyl("_MountFront", 0.016, mh, (0, base_y + mh * 0.5, z_center + tube_len * 0.26), axis="y", seg=16, bevel=0.0005),
        add_cyl("_MountRear", 0.016, mh, (0, base_y + mh * 0.5, z_center - tube_len * 0.26), axis="y", seg=16, bevel=0.0005),
    ])
    eye = add_empty("ScopeEye", (0, y, eye_z))
    ring = add_torus("_EyeRing", 0.0296, 0.0016, (0, y, eye_z), seg_major=24, seg_minor=8)
    black = add_cyl("ScopeLensBlack", 0.028, 0.012, (0, y, eye_z + 0.0005), axis="z", seg=24)
    clear = add_cyl("ScopeLensClear", 0.028, 0.012, (0, y, eye_z - 0.0005), axis="z", seg=24)
    ret = join_parts("RetCross", [
        add_box("_RetH", (0.056, 0.0008, 0.0008), (0, y, eye_z - 0.007)),
        add_box("_RetV", (0.0008, 0.0008, 0.056), (0, y, eye_z - 0.007)),
    ])
    parent_to(tube, optic)
    parent_to(mounts, optic)
    parent_to(eye, optic)
    parent_to(ring, eye)
    parent_to(black, eye)
    parent_to(clear, eye)
    parent_to(ret, eye)
    return optic


def sniper_bipod(y, z, leg_len=0.16):
    """收折两脚架:两根斜贴护木底的杆 + 铰链座(不妨碍 ADS,视轴外)。"""
    hinge = add_cyl("BipodHinge", 0.010, 0.044, (0, y - 0.020, z), axis="x", seg=12, bevel=0.0005)
    ll = add_cyl("BipodLegL", 0.0045, leg_len, (-0.026, y - 0.048, z + 0.02), axis="y", seg=8, bevel=0.0003)
    ll.rotation_euler.y += 0.20
    lr = add_cyl("BipodLegR", 0.0045, leg_len, (0.026, y - 0.048, z + 0.02), axis="y", seg=8, bevel=0.0003)
    lr.rotation_euler.y -= 0.20
    return [hinge, ll, lr]


def skeleton_stock(y, z_hinge, plate_z=0.42, mat="poly"):
    """骨架托 v2:上杆 + 斜撑 + 托底板 + 贴腮板 + 拇指孔挖穿 + 托底橡胶垫 + 贴腮调节钮。
    拇指孔在斜撑与托板交接处挖穿(实枪 AICS/AW 系骨架托标志)。"""
    top = add_box("StockTop", (0.020, 0.024, 0.30), (0, y - 0.010, z_hinge + 0.15), bevel=0.0008)
    diag = add_box("StockDiag", (0.018, 0.020, 0.20), (0, y - 0.045, z_hinge + 0.17),
                   bevel=0.0008, rot_g=(0.42, 0, 0))
    plate = add_box("StockPlate", (0.036, 0.090, 0.026), (0, y - 0.028, plate_z), bevel=0.0010)
    stock = join_parts("Stock", [top, diag, plate])
    # 拇指孔:挖穿托体前上部(竖直椭圆)
    add_stock_thumbhole(stock, 0, y + 0.014, z_hinge + 0.24, rx=0.012, rz=0.028)
    cheek = add_box("CheekRest", (0.044, 0.020, 0.110), (0, y + 0.018, plate_z - 0.055), bevel=0.0008)
    pad = add_butt_pad("ButtPad", y - 0.028, plate_z + 0.018, w=0.036, h=0.090)
    knob = add_cyl("CheekKnob", 0.006, 0.014, (0.026, y + 0.018, plate_z - 0.020), axis="x", seg=10, bevel=0.0004)
    return [stock, cheek, pad, knob]


SCOPE_RULES = [
    ("ScopeTubeBody", "scope_black"), ("_EyeRing", "scope_black"),
    ("ScopeMounts", "dark"), ("ScopeLensBlack", "scope_black"),
    ("ScopeLensClear", "lens_clear"), ("RetCross", "ret_dark"),
]


# ============================================================ 各枪

def build_awm():
    reset()
    ry = 0.030
    # 机匣 + 枪管 + 鸟笼制退
    add_box("Receiver", (0.052, 0.075, 0.360), (0, 0.024, -0.020), bevel=0.0014)
    # 阶梯重枪管(节段递减:枪管节/喉缩段/口段)
    add_step_barrel("Barrel", ry, [
        (-0.280, 0.280, 0.0185),   # 后粗段
        (-0.520, 0.220, 0.0165),   # 中段
        (-0.660, 0.080, 0.0150),   # 口段
    ])
    brake = add_cyl("MuzzleBrake", 0.021, 0.075, (0, ry, -0.795), axis="z", seg=18, bevel=0.0008)
    # 侧孔挖穿(实枪鱼鳃式制退器)
    for ct in add_brake_ports("Brake", 0.021, ry, -0.795, n=3, w=0.046):
        cut(brake, ct)
    # 弹匣(5 发 AICS)
    add_mag_straight("mag", 0.040, 0.088, 0.115, (0, 0.008, -0.055), tilt=0.12, mat="dark")
    # 握把 + 扳机护圈
    add_box("Grip", (0.032, 0.098, 0.048), (0, -0.055, 0.075), bevel=0.0010, rot_g=(0.28, 0, 0))
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.048, 0.030), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.048 + 0.011, -0.008), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.048 + 0.011, 0.068), bevel=0.0004)
    # 绿色聚合物骨架托(带拇指孔/托底垫/贴腮调节钮)
    for p in skeleton_stock(0.024, 0.160, plate_z=0.44):
        pass
    bolt_assembly(0.042, 0.045, style="bolt")
    sniper_bipod(0.030, -0.320)
    sniper_scope(0.115, -0.06, 0.0495, tube_len=0.24, sunshade=True)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("mag", "dark"), ("Bipod", "dark"), ("ButtPad", "dark"),
        ("Stock", "olive"), ("CheekRest", "olive"), ("CheekKnob", "metal"), ("Grip", "olive"),
        ("Receiver", "metal"), ("Barrel", "dark"), ("MuzzleBrake", "dark"),
        ("ParallaxKnob", "scope_black"), ("_SunShade", "scope_black"),
    ], default="dark")


def build_m24():
    reset()
    ry = 0.030
    add_box("Receiver", (0.050, 0.070, 0.320), (0, 0.024, -0.010), bevel=0.0014)
    add_cyl("Barrel", 0.0155, 0.580, (0, ry, -0.470), axis="z", seg=20, bevel=0.0008, taper=0.9)
    # 内仓枪:mag_style=none,无弹匣件
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.046, 0.040), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.002), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.078), bevel=0.0004)
    add_box("Grip", (0.030, 0.094, 0.046), (0, -0.052, 0.085), bevel=0.0010, rot_g=(0.28, 0, 0))
    # 一体化玻璃钢托(整体式,非骨架)
    add_box("Stock", (0.048, 0.085, 0.400), (0, 0.000, 0.240), bevel=0.0016)
    add_box("CheekRest", (0.050, 0.022, 0.120), (0, 0.058, 0.300), bevel=0.0008)
    bolt_assembly(0.042, 0.050, style="bolt")
    sniper_bipod(0.030, -0.300)
    sniper_scope(0.112, -0.06, 0.0495, tube_len=0.22)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("Bipod", "dark"),
        ("Stock", "olive"), ("CheekRest", "olive"), ("Grip", "olive"),
        ("Receiver", "metal"), ("Barrel", "dark"),
    ], default="dark")


def build_svd():
    reset()
    ry = 0.030
    # 机匣 + 外露长行程导气活塞(右上方粗管)
    add_box("Receiver", (0.048, 0.070, 0.300), (0, 0.024, 0.010), bevel=0.0014)
    add_cyl("Barrel", 0.0135, 0.560, (0, ry, -0.460), axis="z", seg=18, bevel=0.0007, taper=0.9)
    add_cyl("GasTube", 0.011, 0.240, (0, ry + 0.032, -0.300), axis="z", seg=14, bevel=0.0006)
    add_box("GasBlock", (0.030, 0.048, 0.055), (0, ry + 0.024, -0.420), bevel=0.0008)
    add_cyl("Muzzle", 0.017, 0.070, (0, ry, -0.770), axis="z", seg=16, bevel=0.0006)
    # 10 发短弹匣(侧倾,AK 系)
    add_mag_curved("mag", 0.036, (0, 0.005, -0.030), mat="metal")
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.046, 0.060), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.022), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.098), bevel=0.0004)
    add_box("Grip", (0.030, 0.092, 0.046), (0, -0.050, 0.100), bevel=0.0010, rot_g=(0.30, 0, 0))
    # 骨架托(带拇指孔观感) + 提把
    for p in skeleton_stock(0.024, 0.160, plate_z=0.44):
        pass
    add_box("CheekPad", (0.040, 0.018, 0.100), (0, 0.052, 0.390), bevel=0.0006)
    bolt_assembly(0.044, 0.070, style="handle")
    sniper_scope(0.115, -0.02, 0.0495, tube_len=0.22)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("mag", "metal"), ("GasBlock", "dark"),
        ("Stock", "poly"), ("CheekPad", "dark"), ("Grip", "poly"),
        ("Receiver", "metal"), ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


def build_m40():
    reset()
    ry = 0.030
    add_box("Receiver", (0.050, 0.070, 0.310), (0, 0.026, 0.000), bevel=0.0014)
    add_cyl("Barrel", 0.0150, 0.580, (0, ry, -0.480), axis="z", seg=20, bevel=0.0008, taper=0.9)
    add_cyl("Muzzle", 0.0165, 0.060, (0, ry, -0.795), axis="z", seg=16, bevel=0.0006)
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.044, 0.050), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.044 + 0.011, 0.012), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.044 + 0.011, 0.088), bevel=0.0004)
    add_box("Grip", (0.030, 0.094, 0.046), (0, -0.050, 0.095), bevel=0.0010, rot_g=(0.28, 0, 0))
    # 整体木托(M40A3 经典)
    add_box("Stock", (0.050, 0.088, 0.420), (0, 0.000, 0.250), bevel=0.0016)
    add_box("CheekRest", (0.052, 0.020, 0.115), (0, 0.058, 0.310), bevel=0.0008)
    add_box("ForendTaper", (0.052, 0.040, 0.300), (0, 0.006, -0.260), bevel=0.0010)
    bolt_assembly(0.044, 0.055, style="bolt")
    sniper_bipod(0.030, -0.310)
    sniper_scope(0.113, -0.14, 0.07, tube_len=0.26)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("Bipod", "dark"),
        ("Stock", "wood"), ("CheekRest", "wood"), ("Grip", "wood"), ("ForendTaper", "wood"),
        ("Receiver", "metal"), ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


def build_m82a1():
    reset()
    ry = 0.034
    # 大方机匣(半自动反器材)
    add_box("Receiver", (0.058, 0.105, 0.520), (0, 0.030, -0.040), bevel=0.0018)
    add_cyl("Barrel", 0.021, 0.580, (0, ry, -0.560), axis="z", seg=20, bevel=0.0008)
    # 双腔大制退器(两侧开孔)
    add_cyl("MuzzleBrake", 0.030, 0.130, (0, ry, -0.910), axis="z", seg=20, bevel=0.0010)
    for s in (-1.0, 1.0):
        for i in range(3):
            add_cyl("_BrakePort%d%s" % (i, "L" if s < 0 else "R"), 0.008, 0.020,
                    (s * 0.030, ry, -0.875 + i * 0.030), axis="x", seg=10)
    # 提把 + 顶部 M1913 轨
    add_picatinny("TopRail", 0.360, (0, 0.096, -0.100), width=0.022, mount_h=0.012)
    add_box("CarryHandle", (0.030, 0.038, 0.140), (0, 0.085, -0.320), bevel=0.0008)
    # 10 发弹匣(握把前方,大倾角)
    add_mag_straight("mag", 0.044, 0.115, 0.130, (0, 0.006, -0.120), tilt=0.22, mat="dark")
    add_box("Grip", (0.034, 0.105, 0.050), (0, -0.062, 0.120), bevel=0.0010, rot_g=(0.26, 0, 0))
    add_box("TriggerGuard", (0.028, 0.008, 0.090), (0, -0.052, 0.070), bevel=0.0005)
    # 缓冲托(带托腮)
    add_box("Stock", (0.042, 0.095, 0.220), (0, 0.006, 0.330), bevel=0.0014)
    add_box("CheekRest", (0.046, 0.022, 0.100), (0, 0.070, 0.330), bevel=0.0008)
    add_box("Monopod", (0.024, 0.050, 0.024), (0, -0.040, 0.420), bevel=0.0006)
    bolt_assembly(0.050, 0.115, style="handle")
    sniper_scope(0.116, -0.12, 0.074, tube_len=0.30)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("mag", "dark"),
        ("Stock", "poly"), ("CheekRest", "poly"), ("Grip", "poly"), ("Monopod", "dark"),
        ("Receiver", "metal"), ("Barrel", "dark"), ("MuzzleBrake", "dark"),
        ("CarryHandle", "dark"), ("TopRail", "dark"),
    ], default="dark")


def build_l115():
    reset()
    ry = 0.030
    add_box("Receiver", (0.052, 0.078, 0.360), (0, 0.024, -0.010), bevel=0.0014)
    add_cyl("Barrel", 0.0175, 0.560, (0, ry, -0.490), axis="z", seg=20, bevel=0.0008, taper=0.88)
    add_cyl("MuzzleBrake", 0.022, 0.080, (0, ry, -0.810), axis="z", seg=18, bevel=0.0008)
    for i in range(2):
        add_box("_BrakeSlot%d" % i, (0.048, 0.012, 0.016), (0, ry + 0.013, -0.790 + i * 0.024), bevel=0.0004)
    add_mag_straight("mag", 0.040, 0.090, 0.120, (0, 0.008, -0.050), tilt=0.12, mat="dark")
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.046, 0.040), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.002), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.078), bevel=0.0004)
    add_box("Grip", (0.032, 0.098, 0.048), (0, -0.054, 0.085), bevel=0.0010, rot_g=(0.28, 0, 0))
    # AICS 直托(中空骨架)
    for p in skeleton_stock(0.024, 0.170, plate_z=0.45):
        pass
    bolt_assembly(0.042, 0.050, style="bolt")
    sniper_bipod(0.030, -0.320)
    sniper_scope(0.114, -0.15, 0.072, tube_len=0.28)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("mag", "dark"), ("Bipod", "dark"),
        ("Stock", "olive"), ("CheekRest", "olive"), ("Grip", "olive"),
        ("Receiver", "metal"), ("Barrel", "dark"), ("MuzzleBrake", "dark"),
    ], default="dark")


def build_sv98():
    reset()
    ry = 0.030
    add_box("Receiver", (0.048, 0.072, 0.320), (0, 0.024, 0.000), bevel=0.0014)
    add_cyl("Barrel", 0.0145, 0.560, (0, ry, -0.470), axis="z", seg=18, bevel=0.0007, taper=0.9)
    add_cyl("Muzzle", 0.016, 0.065, (0, ry, -0.780), axis="z", seg=16, bevel=0.0006)
    add_mag_straight("mag", 0.036, 0.092, 0.105, (0, 0.006, -0.045), tilt=0.15, mat="metal")
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.046, 0.050), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.012), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.088), bevel=0.0004)
    add_box("Grip", (0.030, 0.094, 0.046), (0, -0.050, 0.095), bevel=0.0010, rot_g=(0.28, 0, 0))
    # 骨架托 + 俄式贴腮板
    for p in skeleton_stock(0.024, 0.165, plate_z=0.44):
        pass
    add_box("CheekPad", (0.042, 0.018, 0.105), (0, 0.055, 0.385), bevel=0.0006)
    bolt_assembly(0.042, 0.055, style="bolt")
    sniper_scope(0.113, -0.13, 0.07, tube_len=0.26)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("mag", "metal"),
        ("Stock", "poly"), ("CheekPad", "dark"), ("Grip", "poly"),
        ("Receiver", "metal"), ("Barrel", "dark"), ("Muzzle", "dark"),
    ], default="dark")


def build_m2010():
    reset()
    ry = 0.030
    add_box("Receiver", (0.052, 0.076, 0.340), (0, 0.024, -0.010), bevel=0.0014)
    add_cyl("Barrel", 0.0160, 0.540, (0, ry, -0.470), axis="z", seg=20, bevel=0.0008, taper=0.92)
    # 消音器(M2010 ESR 标配,粗长)
    add_cyl("Suppressor", 0.024, 0.200, (0, ry, -0.730), axis="z", seg=20, bevel=0.0008)
    add_mag_straight("mag", 0.040, 0.088, 0.115, (0, 0.008, -0.050), tilt=0.12, mat="dark")
    add_box("TriggerGuardTop", (0.026, 0.008, 0.085), (0, -0.046, 0.045), bevel=0.0005)
    add_box("_GuardPostF", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.007), bevel=0.0004)
    add_box("_GuardPostB", (0.020, 0.030, 0.008), (0, -0.046 + 0.011, 0.083), bevel=0.0004)
    add_box("Grip", (0.032, 0.096, 0.048), (0, -0.054, 0.088), bevel=0.0010, rot_g=(0.28, 0, 0))
    # 模块化聚合物托(可调贴腮 + 托底板)
    add_box("Stock", (0.044, 0.080, 0.300), (0, 0.002, 0.300), bevel=0.0014)
    add_box("CheekRest", (0.050, 0.022, 0.110), (0, 0.058, 0.330), bevel=0.0008)
    add_box("ButtPad", (0.048, 0.098, 0.022), (0, 0.000, 0.455), bevel=0.0008)
    bolt_assembly(0.042, 0.055, style="bolt")
    sniper_scope(0.115, -0.15, 0.07, tube_len=0.28)
    apply_materials(SCOPE_RULES + [
        ("bolt", "dark"), ("mag", "dark"), ("Suppressor", "dark"),
        ("Stock", "tan"), ("CheekRest", "tan"), ("Grip", "tan"), ("ButtPad", "dark"),
        ("Receiver", "metal"), ("Barrel", "dark"),
    ], default="dark")


BUILDERS = {
    "awm": build_awm,
    "m24": build_m24,
    "svd": build_svd,
    "m40": build_m40,
    "m82a1": build_m82a1,
    "l115": build_l115,
    "sv98": build_sv98,
    "m2010": build_m2010,
}

NO_MAG = {"m24", "m40"}   # 内仓枪,mag_style=none


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
        need = ["bolt", "StockOptic", "ScopeTubeBody", "ScopeEye",
                "ScopeLensBlack", "ScopeLensClear", "RetCross"]
        if wid not in NO_MAG:
            need.append("mag")
        ok = all(k in names for k in need)
        # 层级契约:ScopeEye 必须是 StockOptic 的子孙(PIP 树内检查的前提)
        hier_ok = False
        so = bpy.data.objects.get("StockOptic")
        eye = bpy.data.objects.get("ScopeEye")
        if so is not None and eye is not None:
            p = eye.parent
            while p is not None:
                if p.name == "StockOptic":
                    hier_ok = True
                    break
                p = p.parent
        print("%-7s objs=%-4d verts=%-6d tris=%-6d  契约=%s 层级=%s  %.0f KB" % (
            wid, objs, verts, tris, "OK" if ok else "MISSING!",
            "OK" if hier_ok else "BROKEN!", os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
