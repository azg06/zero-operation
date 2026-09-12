"""
突击步枪批次建模(除 M4 外的 7 把):AK-47 / SCAR-H / AUG A3 / G36C / AK-74M / FAMAS / G3

尺寸与布局严格沿用现有 weapon_models.gd 里的程序化定义,保证
HAND_ANCHORS / MUZZLE_Z / MOD_ANCHORS 不需要改动。

每把枪都带独立可动件:
    mag  —— 弹匣(换弹时脱离枪身)
    bolt —— 拉机柄(空仓换弹的上膛动作驱动它)

用法:
    blender --background --python build_ar_batch.py              # 全部 7 把
    blender --background --python build_ar_batch.py -- ak g3     # 指定几把
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


# ============================================================ AK-47
## 铣削机匣 + 防尘盖 + 导气管 + 木护木/木托 + 弧形钢弹匣 + 右侧大拉机柄
def build_ak():
    reset()
    ry = 0.028
    # --- 机匣(铣削型:侧面带纵向凹槽)+ 防尘盖 + 右侧大拨片保险 ---
    recv = add_box("Receiver", (0.054, 0.066, 0.300), (0, 0.012, -0.030), bevel=0.0014)
    # 机匣侧面减重槽(铣削机匣的标志)
    for s in (-1.0, 1.0):
        slot = add_box("_rs%d" % s, (0.004, 0.020, 0.180), (s * 0.028, 0.012, -0.030))
        cut(recv, slot)
    add_box("DustCover", (0.050, 0.020, 0.220), (0, 0.052, -0.020), bevel=0.0008)
    add_box("SafetyLever", (0.012, 0.022, 0.100), (0.030, 0.012, -0.020), bevel=0.0008)
    # 防尘盖顶轨( optic 改装落点):AK 原生无轨,采用市售防尘盖轨方案
    add_picatinny("TopRail", 0.17, (0, 0.0694, -0.045), width=0.020, mount_h=0.006)
    # --- 前节套 + 导气管(枪管上方粗管)+ 导气座 ---
    add_box("FrontTrunnion", (0.050, 0.050, 0.050), (0, 0.024, -0.160), bevel=0.0010)
    add_cyl("GasTube", 0.0115, 0.320, (0, 0.050, -0.250), axis="z", seg=14, bevel=0.0006)
    add_cyl("GasTubeCollar", 0.0135, 0.030, (0, 0.050, -0.130), axis="z", seg=14, bevel=0.0005)
    add_box("GasBlock", (0.024, 0.045, 0.050), (0, 0.034, -0.440), bevel=0.0008)
    # --- 上下两片木护木夹住枪管/导气管 + 前箍 ---
    add_box("HandguardTop", (0.046, 0.032, 0.160), (0, 0.054, -0.280), bevel=0.0012)
    hg_bot = add_box("HandguardBottom", (0.050, 0.042, 0.160), (0, 0.009, -0.280), bevel=0.0012)
    for i in range(4):
        add_box("HandguardGrip%d" % i, (0.052, 0.006, 0.014),
                (0, -0.006, -0.360 + i * 0.055), bevel=0.0004)
    add_box("HandguardBand", (0.051, 0.014, 0.018), (0, 0.030, -0.220), bevel=0.0006)
    # --- 枪管 + 准星座 + 斜切制退器 ---
    add_cyl("Barrel", 0.0110, 0.520, (0, ry, -0.510), axis="z", seg=16, bevel=0.0006)
    add_box("FrontSightBase", (0.020, 0.055, 0.030), (0, 0.052, -0.760), bevel=0.0008)
    add_box("SightWingL", (0.005, 0.024, 0.022), (-0.013, 0.076, -0.760), bevel=0.0005)
    add_box("SightWingR", (0.005, 0.024, 0.022), (0.013, 0.076, -0.760), bevel=0.0005)
    add_cyl("FrontSightPost", 0.0032, 0.022, (0, 0.072, -0.760), axis="y", seg=8)
    brake = add_cyl("MuzzleBrake", 0.0150, 0.048, (0, ry, -0.845), axis="z", seg=16, bevel=0.0006)
    # 斜切口(制退器右侧斜切,AK-47 的标志)
    cut(brake, add_box("_brake_cut", (0.020, 0.010, 0.030), (0.008, ry + 0.014, -0.840)))
    # --- 木枪托 + 托底板 ---
    # v2(实拍修正"枪托偏下"):旧版套用 add_grip 手枪握把逻辑 —— 枢轴在顶端、
    # 整体下垂,托底比枪管轴线低约 10cm,像握把一样吊在机匣下。
    # 真 AK 是直托:上缘贴防尘盖顶线,向后微垂 0.08rad,托底中心与枪管
    # 轴线大致齐平。前端面(z≈0.11)与机匣后端面(z=0.12)重叠 10mm 焊死。
    add_box("StockBody", (0.044, 0.085, 0.190), (0, 0.012, 0.205),
            bevel=0.0015, rot_g=(0.08, 0, 0))
    # 托底板:贴枪托旋转后的后端面(中心后移 0.106*cos0.08,下移 0.106*sin0.08)
    add_box("StockPlate", (0.048, 0.095, 0.022), (0, 0.004, 0.310),
            bevel=0.0012, rot_g=(0.08, 0, 0))
    # --- 木握把 + 扳机 + 大弧度钢弹匣 ---
    add_grip("Grip", 0.034, 0.100, 0.046, (0, -0.024, 0.045), tilt=0.42, mat="wood", ribs=3)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.036, 0.015), bevel=0.0005)
    for p in add_trigger_guard(-0.044, -0.005, 0.055):
        pass
    add_mag_curved("MagCurved", 0.038, (0, -0.023, -0.100))
    # --- 右侧大拉机柄(可动) ---
    ch = add_box("ChargingHandle", (0.012, 0.014, 0.030), (0.034, 0.036, -0.020), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.008, 0.016, (0.044, 0.036, -0.020), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.104, -0.740, 0.0, 0.055, ry)

    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Handguard", "wood"), ("Stock", "wood"), ("Grip", "wood"),
        ("Barrel", "dark"), ("MuzzleBrake", "dark"), ("Brake", "dark"),
        ("FrontSight", "dark"), ("SightWing", "dark"), ("Gas", "dark"),
        ("Trigger", "dark"), ("bolt", "dark"), ("mag", "metal"),
        ("MagFollower", "metal"), ("Mag", "metal"),
        ("Receiver", "metal"), ("FrontTrunnion", "metal"),
        ("SafetyLever", "metal"), ("DustCover", "metal"),
    ], default="dark")


# ============================================================ SCAR-H
## 一体式铝上机匣 + 全顶轨 + 聚合物下机匣 + 短冲程导气座 + Ugg 靴型折叠托
def build_scar():
    reset()
    ry = 0.024
    # --- 一体式上机匣(延伸到护木段)+ 聚合物下机匣 ---
    upper = add_box("UpperReceiver", (0.050, 0.032, 0.420), (0, 0.048, -0.100), bevel=0.0014)
    cut(upper, add_box("_port", (0.030, 0.021, 0.058), (0.027, 0.048, -0.060)))
    lower = add_box("LowerReceiver", (0.052, 0.052, 0.200), (0, -0.006, -0.020), bevel=0.0014)
    cut(lower, add_box("_well", (0.040, 0.085, 0.072), (0, -0.030, -0.092)))
    add_box("MagwellFlare", (0.054, 0.020, 0.030), (0, -0.030, -0.128), bevel=0.0010)
    # 顶轨止于 z=-0.35:原长到 -0.42,前段 45mm 超出护木悬空(mount_h 垫块下无支撑)
    add_rail("TopRail", 0.086, 0.030, -0.350, mount_h=0.0146)
    # --- 护木下段 + 两侧可拆短轨(带齿) ---
    add_box("Handguard", (0.046, 0.036, 0.150), (0, 0.003, -0.300), bevel=0.0012)
    # 侧轨必须绕枪管轴转 90° 让齿朝外,否则就是"齿朝上的平躺板"浮在枪侧(实机验证翻车点);
    # 齿顶平面贴到护木面外侧:半宽 0.023 + 轨厚 0.0074
    for s in (-1.0, 1.0):
        side = "L" if s < 0 else "R"
        add_picatinny("SideRail%s" % side, 0.150,
                      (s * 0.0304, 0.012, -0.300), width=0.016,
                      rot_z=(-math.pi * 0.5 if s > 0 else math.pi * 0.5))
    # --- 枪管 + 导气座(前准星折叠座)+ 三叉消焰器 ---
    add_cyl("Barrel", 0.0110, 0.620, (0, ry, -0.460), axis="z", seg=16, bevel=0.0006)
    add_box("GasBlock", (0.022, 0.040, 0.050), (0, 0.035, -0.340), bevel=0.0008)
    # 前折准星坐在导轨齿顶上(0.086),原 y=0.062 直接嵌在导轨体内部穿模;
    # 它是瞄具,必须归入 StockIrons 组(装备光学镜时整组隐藏,否则红点镜里立着个准星)
    fold_sight = add_box("FoldingFrontSight", (0.008, 0.026, 0.010), (0, 0.099, -0.340), bevel=0.0005)
    fh = add_cyl("FlashHider", 0.0160, 0.050, (0, ry, -0.800), axis="z", seg=16, bevel=0.0006)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cut(fh, add_box("_fh%d" % i, (0.007, 0.007, 0.032),
                        (math.cos(ang) * 0.0145, ry + math.sin(ang) * 0.0145, -0.805)))
    # --- Ugg 靴型折叠托:铰链 + 上杆 + 靴跟 + 靴尖 + 折叠钮 ---
    add_box("StockHinge", (0.030, 0.060, 0.050), (0, 0.010, 0.130), bevel=0.0010)
    add_box("StockArm", (0.026, 0.030, 0.160), (0, 0.030, 0.200), bevel=0.0010)
    add_box("StockHeel", (0.048, 0.100, 0.032), (0, 0.000, 0.270), bevel=0.0012)
    add_box("StockToe", (0.048, 0.035, 0.060), (0, -0.030, 0.240), bevel=0.0010)
    add_cyl("StockFoldButton", 0.010, 0.025, (0.022, 0.002, 0.190), axis="x", seg=12, bevel=0.0005)
    add_box("CheekRest", (0.040, 0.022, 0.090), (0, 0.052, 0.190), bevel=0.0008)
    # --- M16 式握把 + 7.62 20 发短弹匣 ---
    add_grip("Grip", 0.034, 0.100, 0.046, (0, -0.026, 0.040), tilt=0.36, ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.038, 0.005), bevel=0.0005)
    add_trigger_guard(-0.046, -0.020, 0.045)
    add_mag_straight("MagShell", 0.038, 0.105, 0.065, (0, -0.022, -0.100), tilt=0.10, holes=2)
    # --- 左侧拉机柄(可动)+ 右侧抛壳窗 ---
    add_box("EjectionPort", (0.006, 0.018, 0.050), (0.027, 0.045, -0.060), bevel=0.0005)
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.028), (-0.032, 0.055, -0.160), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.007, 0.014, (-0.042, 0.055, -0.160), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    _scar_irons = add_irons("StockIrons", 0.112, -0.340, 0.080, 0.050, ry)
    join_parts("StockIrons", [fold_sight, _scar_irons])

    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Upper", "metal"), ("Receiver", "metal"), ("Handguard", "tan"),
        ("Stock", "tan"), ("Grip", "tan"), ("CheekRest", "tan"),
        ("mag", "tan"), ("Mag", "tan"), ("Barrel", "dark"),
        ("FlashHider", "dark"), ("Gas", "dark"), ("Folding", "dark"),
        ("Ejection", "dark"), ("bolt", "dark"), ("Trigger", "dark"),
        ("TopRail", "dark"), ("SideRail", "dark"), ("HG", "dark"),
    ], default="dark")


# ============================================================ AUG A3
## 无托聚合物枪身 + 顶部 A3 轨 + 前置折叠握把 + 后置弹匣 + 左后拉机柄
def build_aug():
    reset()
    ry = 0.026
    # --- 无托一体枪身 + 贴腮凸起 + 托底板 ---
    body = add_box("Receiver", (0.052, 0.080, 0.580), (0, 0.022, 0.030), bevel=0.0016)
    add_box("CheekRest", (0.050, 0.050, 0.160), (0, 0.072, 0.200), bevel=0.0014)
    add_box("StockPlate", (0.054, 0.095, 0.025), (0, 0.020, 0.310), bevel=0.0012)
    add_box("EjectionPort", (0.012, 0.020, 0.050), (0.030, 0.040, 0.160), bevel=0.0006)
    # AUG 枪身侧面的散热/减重槽
    for s in (-1.0, 1.0):
        for i in range(3):
            add_box("BodySlot%d%s" % (i, "L" if s < 0 else "R"), (0.004, 0.016, 0.040),
                    (s * 0.027, 0.020, -0.120 + i * 0.070), bevel=0.0004)
    # --- A3 顶部皮卡汀尼轨 ---
    # 顶轨止于 z=0.08:原 0.44 长伸到 z=0.16,与贴腮板(z 0.04~0.20,y 0.047~0.097)体积重叠
    add_picatinny("TopRail", 0.360, (0, 0.082, -0.100), width=0.020, mount_h=0.0126)
    # --- 枪管 + 鸟笼消焰器 + 枪管锁柄 ---
    add_cyl("Barrel", 0.0110, 0.420, (0, ry, -0.360), axis="z", seg=16, bevel=0.0006)
    add_cyl("BarrelCollar", 0.0155, 0.030, (0, ry, -0.170), axis="z", seg=16, bevel=0.0005)
    add_cyl("BarrelRelease", 0.009, 0.030, (0.030, 0.030, -0.150), axis="x", seg=12, bevel=0.0005)
    fh = add_cyl("FlashHider", 0.0145, 0.042, (0, ry, -0.640), axis="z", seg=16, bevel=0.0006)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cut(fh, add_box("_fh%d" % i, (0.006, 0.006, 0.026),
                        (math.cos(ang) * 0.013, ry + math.sin(ang) * 0.013, -0.645)))
    # --- 前置可折叠垂直握把 + 大型扳机护圈桥 ---
    add_grip("Foregrip", 0.028, 0.075, 0.040, (0, -0.030, -0.170), tilt=0.12, ribs=3)
    add_box("TriggerGuardBridge", (0.046, 0.018, 0.260), (0, -0.050, 0.0), bevel=0.0008)
    # --- 后置手枪握把(扳机在前,弹匣在握把后方)---
    add_grip("Grip", 0.034, 0.090, 0.050, (0, -0.026, 0.070), tilt=0.30, ribs=4)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.037, -0.050), bevel=0.0005)
    # 后置半透明聚合物弹匣 + 加强筋
    add_mag_straight("MagShell", 0.036, 0.120, 0.056, (0, -0.022, 0.160), tilt=-0.10, holes=3)
    # --- 左侧后置拉机柄(可动)---
    ch = add_box("ChargingHandle", (0.010, 0.014, 0.032), (-0.032, 0.050, 0.240), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.008, 0.016, (-0.044, 0.050, 0.240), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.125, -0.440, 0.180, 0.045, ry)

    apply_materials([
        ("Receiver", "olive"), ("CheekRest", "olive"), ("Foregrip", "olive"),
        ("Grip", "olive"), ("TriggerGuard", "olive"), ("mag", "olive"),
        ("Mag", "olive"), ("Barrel", "dark"), ("FlashHider", "dark"),
        ("Ejection", "dark"), ("bolt", "dark"), ("Trigger", "dark"),
        ("TopRail", "dark"), ("StockPlate", "dark"), ("BodySlot", "dark"),
    ], default="dark")


# ============================================================ G36C
## 聚合物机匣 + 短护木四向导轨 + 短枪管 + 侧折叠骨架托 + 顶置折叠拉机柄
def build_g36c():
    reset()
    ry = 0.024
    # --- 聚合物机匣 + 提把/导轨基座 ---
    recv = add_box("Receiver", (0.050, 0.062, 0.340), (0, 0.014, -0.030), bevel=0.0014)
    add_box("CarryHandleBase", (0.046, 0.030, 0.180), (0, 0.052, 0.0), bevel=0.0010)
    add_picatinny("TopRail", 0.190, (0, 0.082, -0.055), width=0.022, mount_h=0.0076)
    # G36 标志性的机匣侧面大圆形凹槽
    for s in (-1.0, 1.0):
        cut(recv, add_cyl("_circ%d" % s, 0.014, 0.010, (s * 0.026, 0.014, -0.030), axis="x", seg=16))
    # --- 枪管 + 鸟笼消焰器(短管)---
    add_cyl("Barrel", 0.0110, 0.420, (0, ry, -0.420), axis="z", seg=16, bevel=0.0006)
    fh = add_cyl("FlashHider", 0.0142, 0.050, (0, ry, -0.680), axis="z", seg=16, bevel=0.0006)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cut(fh, add_box("_fh%d" % i, (0.006, 0.006, 0.028),
                        (math.cos(ang) * 0.013, ry + math.sin(ang) * 0.013, -0.685)))
    # --- 短护木 + 左右/底部短轨(四向导轨)---
    add_box("Handguard", (0.050, 0.050, 0.130), (0, 0.006, -0.240), bevel=0.0012)
    add_picatinny("RailTop", 0.130, (0, 0.034, -0.240), width=0.018)
    # 四向轨:底/侧轨同样必须转向,齿顶平面贴到护木面外(半高 0.025 / 半宽 0.025 + 轨厚 0.0074)
    add_picatinny("RailBottom", 0.100, (0, -0.0264, -0.240), width=0.018, rot_z=math.pi)
    for s in (-1.0, 1.0):
        side = "L" if s < 0 else "R"
        add_picatinny("Rail%s" % side, 0.100,
                      (s * 0.0324, 0.006, -0.240), width=0.016,
                      rot_z=(-math.pi * 0.5 if s > 0 else math.pi * 0.5))
    # --- 侧折叠骨架托:铰链 + 上杆/下杆 + 贴腮 + 托底板 ---
    add_box("StockHinge", (0.030, 0.055, 0.040), (0, 0.005, 0.140), bevel=0.0010)
    add_box("StockArmTop", (0.024, 0.020, 0.140), (0, 0.050, 0.210), bevel=0.0008)
    add_box("StockArmBottom", (0.024, 0.020, 0.140), (0, -0.015, 0.210), bevel=0.0008)
    add_box("CheekRest", (0.036, 0.030, 0.080), (0, 0.035, 0.240), bevel=0.0008)
    add_box("StockPlate", (0.040, 0.080, 0.024), (0, 0.010, 0.270), bevel=0.0010)
    # --- 握把 + 扳机 + 半透明弧形弹匣 ---
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.023, 0.040), tilt=0.36, ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.035, 0.005), bevel=0.0005)
    add_trigger_guard(-0.044, -0.020, 0.048)
    add_mag_curved("MagCurved", 0.036, (0, -0.022, -0.080))
    # --- 顶置折叠拉机柄(居中,可动)+ 抛壳窗 ---
    add_box("EjectionPort", (0.006, 0.018, 0.050), (0.027, 0.035, -0.080), bevel=0.0005)
    ch = add_box("ChargingHandle", (0.016, 0.012, 0.030), (0, 0.060, -0.060), bevel=0.0006)
    lw = add_box("_ch_l", (0.030, 0.008, 0.010), (-0.020, 0.060, -0.048), bevel=0.0004)
    rw = add_box("_ch_r", (0.030, 0.008, 0.010), (0.020, 0.060, -0.048), bevel=0.0004)
    join_parts("bolt", [ch, lw, rw])
    add_irons("StockIrons", 0.100, -0.360, 0.040, 0.045, ry)

    apply_materials([
        ("Receiver", "poly"), ("Handguard", "poly"), ("Grip", "poly"),
        ("CarryHandle", "poly"), ("Stock", "poly"), ("CheekRest", "poly"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("Rail", "dark"),
        ("TopRail", "dark"), ("Ejection", "dark"), ("bolt", "dark"),
        ("Trigger", "dark"), ("mag", "tan"), ("Mag", "tan"),
    ], default="dark")


# ============================================================ AK-74M
## 黑色聚合物家具 + 90° 导气座 + 直弧形 5.45 弹匣 + 侧折叠骨架托
def build_ak74():
    reset()
    ry = 0.028
    # --- 机匣 + 防尘盖 + 保险拨片 ---
    add_box("Receiver", (0.054, 0.066, 0.300), (0, 0.012, -0.030), bevel=0.0014)
    add_box("DustCover", (0.050, 0.020, 0.220), (0, 0.052, -0.020), bevel=0.0008)
    add_box("SafetyLever", (0.012, 0.022, 0.100), (0.030, 0.012, -0.020), bevel=0.0008)
    # 防尘盖顶轨( optic 改装落点)
    add_picatinny("TopRail", 0.17, (0, 0.0694, -0.045), width=0.020, mount_h=0.006)
    # --- 前节套 + 导气管 + 90° 导气座 ---
    add_box("FrontTrunnion", (0.050, 0.050, 0.050), (0, 0.024, -0.160), bevel=0.0010)
    add_cyl("GasTube", 0.0115, 0.320, (0, 0.050, -0.250), axis="z", seg=14, bevel=0.0006)
    add_box("GasBlock90", (0.020, 0.042, 0.040), (0, 0.033, -0.460), bevel=0.0008)
    # 90° 导气座的凸起特征
    add_box("GasBlockNub", (0.014, 0.018, 0.026), (0, 0.052, -0.460), bevel=0.0005)
    # --- 黑色聚合物上下护木 + 前箍 + 防滑槽 ---
    add_box("HandguardTop", (0.046, 0.030, 0.150), (0, 0.053, -0.270), bevel=0.0012)
    add_box("HandguardBottom", (0.050, 0.040, 0.150), (0, 0.010, -0.270), bevel=0.0012)
    for i in range(3):
        add_box("HGRib%d" % i, (0.052, 0.006, 0.016), (0, -0.006, -0.320 + i * 0.050), bevel=0.0004)
    add_box("HandguardBand", (0.051, 0.013, 0.016), (0, 0.031, -0.210), bevel=0.0006)
    # --- 枪管 + 准星座 + 74 式圆柱开槽制退器 ---
    add_cyl("Barrel", 0.0110, 0.460, (0, ry, -0.490), axis="z", seg=16, bevel=0.0006)
    add_box("FrontSightBase", (0.020, 0.052, 0.028), (0, 0.050, -0.720), bevel=0.0008)
    add_box("SightWingL", (0.005, 0.024, 0.020), (-0.013, 0.074, -0.720), bevel=0.0005)
    add_box("SightWingR", (0.005, 0.024, 0.020), (0.013, 0.074, -0.720), bevel=0.0005)
    add_cyl("FrontSightPost", 0.0032, 0.022, (0, 0.070, -0.720), axis="y", seg=8)
    brake = add_cyl("MuzzleBrake", 0.0145, 0.070, (0, ry, -0.790), axis="z", seg=16, bevel=0.0006)
    for s in (-1.0, 1.0):
        cut(brake, add_box("_brake%d" % s, (0.006, 0.008, 0.045), (s * 0.0145, ry, -0.785)))
    add_cyl("BrakeCollar", 0.0155, 0.014, (0, ry, -0.760), axis="z", seg=16, bevel=0.0005)
    # --- 侧折叠骨架托:铰链 + 双杆 + 托底板 ---
    add_box("StockHinge", (0.030, 0.055, 0.040), (0, 0.005, 0.150), bevel=0.0010)
    add_box("StockArmTop", (0.022, 0.020, 0.150), (0, 0.045, 0.210), bevel=0.0008)
    add_box("StockArmBottom", (0.022, 0.020, 0.150), (0, -0.012, 0.210), bevel=0.0008)
    add_box("StockPlate", (0.040, 0.080, 0.024), (0, 0.010, 0.280), bevel=0.0010)
    add_cyl("StockFoldButton", 0.009, 0.018, (0.028, 0.010, 0.160), axis="x", seg=12, bevel=0.0005)
    # --- 聚合物握把 + 扳机 + 5.45 弹匣(比 7.62 更直)---
    add_grip("Grip", 0.034, 0.100, 0.046, (0, -0.024, 0.045), tilt=0.40, ribs=3)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.036, 0.015), bevel=0.0005)
    add_trigger_guard(-0.044, -0.005, 0.055)
    add_mag_straight("MagShell", 0.036, 0.135, 0.058, (0, -0.023, -0.100), tilt=0.14, holes=2)
    # --- 右侧拉机柄(可动)---
    ch = add_box("ChargingHandle", (0.012, 0.014, 0.030), (0.034, 0.036, -0.020), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.008, 0.016, (0.044, 0.036, -0.020), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    add_irons("StockIrons", 0.104, -0.700, 0.0, 0.055, ry)

    apply_materials([
        ("Handguard", "poly"), ("Grip", "poly"), ("Stock", "poly"),
        ("Barrel", "dark"), ("MuzzleBrake", "dark"), ("Brake", "dark"),
        ("FrontSight", "dark"), ("SightWing", "dark"), ("Gas", "dark"),
        ("Trigger", "dark"), ("bolt", "dark"), ("mag", "dark"), ("Mag", "dark"),
        ("Receiver", "metal"), ("DustCover", "metal"), ("SafetyLever", "metal"),
        ("FrontTrunnion", "metal"),
    ], default="dark")


# ============================================================ FAMAS
## 高提把无托枪身 + 前置大护圈 + 两脚架收纳腿 + 后置弹匣 + 顶部拉机柄
def build_famas():
    reset()
    ry = 0.024
    # --- 无托枪身(黑绿聚合物)+ 高提把(提把顶 0.088,低于 sight_y 0.1)---
    body = add_box("Receiver", (0.050, 0.070, 0.560), (0, 0.020, 0.0), bevel=0.0016)
    add_box("CarryHandle", (0.046, 0.028, 0.160), (0, 0.062, -0.020), bevel=0.0010)
    add_box("CarryHandleTop", (0.048, 0.012, 0.200), (0, 0.080, -0.020), bevel=0.0008)
    # 提把顶轨(optic 落点):齿顶 0.0934,避开照门耳(z>=0.03)
    add_picatinny("TopRail", 0.12, (0, 0.0934, -0.040), width=0.020, mount_h=0.006)
    # 提把两侧的握持凹槽
    for s in (-1.0, 1.0):
        cut(body, add_box("_chg%d" % s, (0.006, 0.030, 0.130), (s * 0.026, 0.060, -0.020)))
    # --- 枪管 + 消焰器 ---
    add_cyl("Barrel", 0.0110, 0.460, (0, ry, -0.440), axis="z", seg=16, bevel=0.0006)
    fh = add_cyl("FlashHider", 0.0142, 0.042, (0, ry, -0.690), axis="z", seg=16, bevel=0.0006)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cut(fh, add_box("_fh%d" % i, (0.006, 0.006, 0.026),
                        (math.cos(ang) * 0.013, ry + math.sin(ang) * 0.013, -0.695)))
    # --- 收纳式两脚架(贴合枪身两侧)---
    for s in (-1.0, 1.0):
        add_cyl("BipodLeg%s" % ("L" if s < 0 else "R"), 0.006, 0.220,
                (s * 0.029, -0.008, -0.320), axis="z", seg=10, bevel=0.0005)
        add_box("BipodFoot%s" % ("L" if s < 0 else "R"), (0.010, 0.030, 0.040),
                (s * 0.029, -0.005, -0.420), bevel=0.0006)
    # --- 前置垂直握把 + 大型扳机护圈桥 ---
    add_grip("Foregrip", 0.028, 0.060, 0.040, (0, -0.030, -0.160), tilt=0.15, ribs=3)
    add_box("TriggerGuardBridge", (0.040, 0.014, 0.240), (0, -0.045, -0.020), bevel=0.0008)
    # --- 后置手枪握把(弹匣在握把后方)+ 25 发直弹匣 ---
    add_grip("Grip", 0.034, 0.090, 0.050, (0, -0.025, 0.080), tilt=0.30, ribs=4)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.035, -0.020), bevel=0.0005)
    add_mag_straight("MagShell", 0.036, 0.120, 0.058, (0, -0.022, 0.160), tilt=-0.12, holes=2)
    # --- 顶部拉机柄(提把下方居中,可动)---
    ch = add_box("ChargingHandle", (0.018, 0.014, 0.034), (0, 0.062, 0.200), bevel=0.0006)
    lw = add_box("_ch_l", (0.032, 0.009, 0.011), (-0.022, 0.062, 0.212), bevel=0.0004)
    rw = add_box("_ch_r", (0.032, 0.009, 0.011), (0.022, 0.062, 0.212), bevel=0.0004)
    join_parts("bolt", [ch, lw, rw])
    # 提把式机械瞄具:细前准星柱 + 小缺口照门(照门贴着提把顶,不允许大块进入视轴)
    irs = [
        add_box("IronsFront", (0.010, 0.035, 0.012), (0, 0.0825, -0.500), bevel=0.0005),
        add_box("IronsRearBase", (0.016, 0.006, 0.012), (0, 0.087, 0.040), bevel=0.0004),
        add_box("IronsRearL", (0.004, 0.012, 0.010), (-0.0055, 0.095, 0.040), bevel=0.0004),
        add_box("IronsRearR", (0.004, 0.012, 0.010), (0.0055, 0.095, 0.040), bevel=0.0004),
    ]
    join_parts("StockIrons", irs)

    apply_materials([
        ("Receiver", "olive"), ("Foregrip", "olive"), ("Grip", "olive"),
        ("TriggerGuard", "olive"), ("CarryHandle", "poly"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("Bipod", "dark"),
        ("Irons", "dark"), ("bolt", "dark"), ("Trigger", "dark"),
        ("mag", "dark"), ("Mag", "dark"),
    ], default="dark")


# ============================================================ G3
## 滚柱延迟钢机匣 + 细长护木 + 鼓式照门/三叉准星座 + 固定聚合物托 + 左前拉机柄
def build_g3():
    reset()
    ry = 0.024
    # --- 冲压钢机匣 + 顶部照门座 ---
    recv = add_box("Receiver", (0.052, 0.068, 0.400), (0, 0.014, -0.030), bevel=0.0014)
    add_box("SightBase", (0.048, 0.016, 0.300), (0, 0.052, -0.040), bevel=0.0008)
    # 照门前轨(optic 落点):爪式镜座方案,避开鼓式照门(z -0.055..-0.025)
    add_picatinny("TopRail", 0.09, (0, 0.0674, -0.115), width=0.020, mount_h=0.008)
    # G3 机匣侧面的冲压加强筋
    for s in (-1.0, 1.0):
        add_box("RecvRib%s" % ("L" if s < 0 else "R"), (0.004, 0.040, 0.240),
                (s * 0.027, 0.014, -0.030), bevel=0.0005)
    add_box("EjectionPort", (0.008, 0.024, 0.060), (0.028, 0.030, -0.080), bevel=0.0005)
    # --- 枪管 + 三叉准星座 + 枪口消焰器 ---
    add_cyl("Barrel", 0.0120, 0.560, (0, ry, -0.460), axis="z", seg=16, bevel=0.0006)
    add_box("FrontSightBase", (0.024, 0.046, 0.030), (0, 0.044, -0.620), bevel=0.0008)
    add_box("SightWingL", (0.005, 0.020, 0.024), (-0.013, 0.068, -0.620), bevel=0.0005)
    add_box("SightWingR", (0.005, 0.020, 0.024), (0.013, 0.068, -0.620), bevel=0.0005)
    add_cyl("FrontSightPost", 0.0030, 0.018, (0, 0.064, -0.620), axis="y", seg=8)
    fh = add_cyl("FlashHider", 0.0160, 0.050, (0, ry, -0.715), axis="z", seg=16, bevel=0.0006)
    for i in range(3):
        ang = math.pi * 0.5 + i * (2 * math.pi / 3.0)
        cut(fh, add_box("_fh%d" % i, (0.007, 0.007, 0.030),
                        (math.cos(ang) * 0.0145, ry + math.sin(ang) * 0.0145, -0.720)))
    # --- 细长绿色聚合物护木 + 防滑筋 ---
    add_box("Handguard", (0.048, 0.052, 0.220), (0, 0.012, -0.280), bevel=0.0014)
    for i in range(4):
        add_box("HGRib%d" % i, (0.050, 0.005, 0.016), (0, 0.037, -0.350 + i * 0.050), bevel=0.0004)
    # --- 固定聚合物托(直线型)+ 托底板 + 背带环 ---
    # v2(与 AK 同款修正):弃用握把式下垂枪托,直托贴机匣顶、后端微垂 0.06rad
    add_box("StockBody", (0.042, 0.085, 0.180), (0, 0.014, 0.250),
            bevel=0.0015, rot_g=(0.06, 0, 0))
    add_box("StockPlate", (0.046, 0.090, 0.020), (0, 0.007, 0.345),
            bevel=0.0012, rot_g=(0.06, 0, 0))
    add_box("SlingLoop", (0.010, 0.014, 0.030), (0.022, -0.012, 0.200), bevel=0.0005)
    # --- 聚合物握把 + 扳机 + 20 发钢弹匣 ---
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.024, 0.040), tilt=0.40, ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.036, 0.015), bevel=0.0005)
    add_trigger_guard(-0.044, -0.005, 0.052)
    add_mag_straight("MagShell", 0.038, 0.120, 0.060, (0, -0.022, -0.100), tilt=0.06, holes=2)
    # --- 左前拉机柄(可动,在护木上方左侧)---
    ch = add_box("ChargingHandle", (0.010, 0.012, 0.026), (-0.030, 0.048, -0.190), bevel=0.0006)
    knob = add_cyl("_ch_knob", 0.008, 0.016, (-0.040, 0.048, -0.190), axis="x", seg=12, bevel=0.0005)
    join_parts("bolt", [ch, knob])
    # 鼓式照门(G3 的标志:带转鼓的觇孔照门)
    irs = [
        add_box("IronsRearBase", (0.024, 0.020, 0.030), (0, 0.052, -0.040), bevel=0.0006),
        add_cyl("RearDrum", 0.011, 0.020, (0, 0.064, -0.040), axis="x", seg=14, bevel=0.0005),
        add_box("IronsFront", (0.009, 0.030, 0.010), (0, 0.070, -0.620), bevel=0.0004),
    ]
    join_parts("StockIrons", irs)

    apply_materials([
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Handguard", "olive"), ("Stock", "olive"), ("Grip", "poly"),
        ("Receiver", "metal"), ("SightBase", "metal"), ("RecvRib", "metal"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("FrontSight", "dark"),
        ("SightWing", "dark"), ("Irons", "dark"), ("RearDrum", "dark"),
        ("Ejection", "dark"), ("bolt", "dark"), ("Trigger", "dark"),
        ("mag", "dark"), ("Mag", "dark"), ("StockPlate", "dark"),
    ], default="dark")


# ============================================================ 批处理

BUILDERS = {
    "ak": build_ak,
    "scar": build_scar,
    "aug": build_aug,
    "g36c": build_g36c,
    "ak74": build_ak74,
    "famas": build_famas,
    "g3": build_g3,
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
        has_mag = "mag" in names
        has_bolt = "bolt" in names
        print("%-6s objs=%-4d verts=%-6d tris=%-6d  mag=%s bolt=%s  %.0f KB" % (
            wid, objs, verts, tris,
            "OK" if has_mag else "MISSING",
            "OK" if has_bolt else "MISSING",
            os.path.getsize(path) / 1024.0))
    print("=" * 60)
    print("输出目录:", OUT_DIR)


if __name__ == "__main__":
    main()
