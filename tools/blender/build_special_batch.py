"""
霰弹枪 + 特种批次(7 把):Rem870 / M590 / Win1897 / M1014 / SPAS-12 / RPG(毒刺) / M320 GL

尺寸沿用 weapon_models.gd 程序化定义,锚点零改动。

换弹契约:
    PumpForend   泵动护木(空仓 pump 动作沿 Z 滑动) —— 泵动 3 把
    bolt         枪机/护木连杆(机匣左侧,全部霰弹)
    EjectShell   抛壳演示弹(gun.gd 抛壳动画)
    LoadPort     装填口参考点(空对象,逐发装填手位)
    rocket       RPG 导弹筒 / GL 膛内榴弹
    Breech       M320 中折膛体(空对象,绕铰链下折)
    ScopeCLU / ScopeEye / ScopeTubeBody   RPG 的 CLU 制导镜 PIP 契约

用法:
    blender --background --python build_special_batch.py
    blender --background --python build_special_batch.py -- rem870 rpg
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


# ---------------------------------------------------------------- 霰弹组件

def shotgun_receiver(receiver_w, receiver_h, receiver_y, receiver_z0, receiver_z1, mat):
    """机匣三段式轮廓:主体 + 上机匣 + 右侧抛壳窗沿。"""
    receiver_top = receiver_y + receiver_h * 0.5
    parts = [
        add_box("_RecvBody", (receiver_w, receiver_h, receiver_z1 - receiver_z0),
                (0, receiver_y, (receiver_z0 + receiver_z1) * 0.5), bevel=0.0014),
        add_box("_RecvUpper", (receiver_w * 0.82, 0.022, (receiver_z1 - receiver_z0) * 0.72),
                (0, receiver_top - 0.008, (receiver_z0 + receiver_z1) * 0.5 - 0.015), bevel=0.0008),
        add_box("_EjectRail", (0.004, 0.02, 0.06),
                (receiver_w * 0.5 + 0.003, receiver_y + 0.012, -0.055), bevel=0.0003),
    ]
    return join_parts("Receiver", parts)


def shotgun_barrel_assembly(barrel_y, barrel_r, receiver_z0, muzzle_z, tube_y, tube_r, tube_z0, tube_z1, mat):
    """枪管 + 管式弹仓 + 连接箍 + 枪口帽 + 顶部连续肋条。"""
    parts = []
    bz0 = receiver_z0 + 0.015
    bz1 = muzzle_z - 0.015
    parts.append(add_cyl("Barrel", barrel_r, abs(bz1 - bz0), (0, barrel_y, (bz0 + bz1) * 0.5),
                         axis="z", seg=20, bevel=0.0006, taper=0.94))
    tz0 = max(tube_z0, receiver_z0 - 0.02)
    tz1 = max(tube_z1, muzzle_z + 0.055)
    parts.append(add_cyl("_MagTube", tube_r, abs(tz1 - tz0), (0, tube_y, (tz0 + tz1) * 0.5),
                         axis="z", seg=16, bevel=0.0005))
    link_h = max((barrel_y - barrel_r) - (tube_y + tube_r), 0.012)
    parts.append(add_box("_TubeClamp", (0.014, link_h, 0.02),
                         (0, ((barrel_y - barrel_r) + (tube_y + tube_r)) * 0.5, tz1 + 0.009), bevel=0.0004))
    muzzle_cap_z = bz1 + 0.008
    parts.append(add_cyl("MuzzleCap", barrel_r + 0.009, 0.022, (0, barrel_y, muzzle_cap_z),
                         axis="z", seg=16, bevel=0.0005))
    # 顶部连续肋条:机匣前缘到枪口帽一条整体
    parts.append(add_box("TopRib", (0.02, 0.006, abs((muzzle_cap_z + 0.025) - (receiver_z0 - 0.05))),
                         (0, barrel_y + barrel_r + 0.005,
                          ((receiver_z0 - 0.05) + (muzzle_cap_z + 0.025)) * 0.5), bevel=0.0004))
    return join_parts("BarrelAssembly", parts), muzzle_cap_z


def pump_forend(pump_r, pump_len, tube_y, pump_z):
    """泵动护木(独立可动件):圆筒 + 收口环 + 手指槽 + 底棱 + 顶托槽 + 双动作杆。"""
    parts = [
        add_cyl("_PumpBody", pump_r, pump_len, (0, 0, 0), axis="z", seg=20, bevel=0.0010),
        add_cyl("_PumpRingR", pump_r - 0.006, 0.02, (0, 0, -pump_len * 0.5 + 0.01), axis="z", seg=18, bevel=0.0004),
        add_cyl("_PumpRingF", pump_r + 0.002, 0.02, (0, 0, pump_len * 0.5 - 0.01), axis="z", seg=18, bevel=0.0004),
        add_box("_PumpBottom", (pump_r * 1.7, 0.009, pump_len * 0.68), (0, -pump_r - 0.004, 0), bevel=0.0004),
        add_box("_PumpTopGroove", (pump_r * 1.25, 0.007, pump_len * 0.68), (0, pump_r - 0.002, 0), bevel=0.0004),
    ]
    groove_len = pump_len * 0.68
    for side in (-1.0, 1.0):
        parts.append(add_box("_PumpGrooveS%d" % (1 if side > 0 else 0), (0.008, 0.008, groove_len),
                             (side * (pump_r - 0.004), -pump_r * 0.18, 0), bevel=0.0003))
        parts.append(add_box("_PumpGrooveT%d" % (1 if side > 0 else 0), (0.008, 0.008, groove_len),
                             (side * (pump_r - 0.004), pump_r * 0.2, 0), bevel=0.0003))
        # 双动作杆:从护木后端伸向机匣,随护木前后运动
        parts.append(add_box("_PumpRod%s" % ("L" if side < 0 else "R"), (0.006, 0.006, 0.15),
                             (side * (pump_r - 0.004), 0.0, pump_len * 0.5 - 0.04), bevel=0.0003))
    joined = join_parts("PumpForend", parts)
    joined.location = g2b((0, tube_y, pump_z))
    return joined


def pump_bolt(receiver_w, receiver_y):
    """枪机/护木连杆(机匣左侧外表面运动)。"""
    bolt = add_empty("bolt", (-receiver_w * 0.5 - 0.004, receiver_y + 0.014, -0.03))
    b1 = add_box("_BoltBody", (0.012, 0.014, 0.07), (0, 0, 0), bevel=0.0005)
    b2 = add_box("_BoltNub", (0.02, 0.009, 0.024), (0.002, 0.012, -0.018), bevel=0.0003)
    parent_to(b1, bolt)
    parent_to(b2, bolt)
    return bolt


def eject_shell(receiver_w, receiver_y):
    """抛壳演示弹(gun.gd 抛壳动画,初始隐藏,Godot 侧处理)。"""
    sh = add_cyl("EjectShell", 0.009, 0.045, (receiver_w * 0.5 + 0.002, receiver_y + 0.014, -0.045),
                 axis="z", seg=10)
    return sh


def shotgun_furniture(receiver_bottom, receiver_z1, stock_mat, straight=False, exposed_hammer=False, receiver_top=0.055):
    """枪托 + 握把 + 扳机护圈 + 外露击锤(win1897)。
    v2(全项目枪托统一修正):直托贴机匣顶线、向后微垂,不再用握把式下垂托;
    托底板由 add_stock 自动生成并贴合后端面。"""
    if straight:
        add_stock("StockGrip", 0.040, 0.070, 0.150, receiver_z1, receiver_top, drop=0.10)
    else:
        add_stock("StockGrip", 0.042, 0.075, 0.140, receiver_z1, receiver_top, drop=0.12)
    add_grip("Grip", 0.034, 0.095, 0.045, (0, receiver_bottom, 0.04), tilt=0.38, mat=stock_mat)
    add_box("TriggerGuard", (0.026, 0.008, 0.075), (0, receiver_bottom - 0.012, 0.01), bevel=0.0004)
    if exposed_hammer:
        ham = add_empty("ExposedHammer", (0, receiver_top + 0.008, receiver_z1 - 0.015))
        h1 = add_cyl("_HammerBody", 0.007, 0.012, (0, 0, 0), axis="z", seg=10)
        h2 = add_box("_HammerSpur", (0.014, 0.02, 0.008), (0, 0.015, -0.003), bevel=0.0004)
        parent_to(h1, ham)
        parent_to(h2, ham)


def shotgun_sights(sight_y, base_y, front_z, rear_z, ghost_ring=False):
    """枪口珠 + 后照门(ghost ring 珠孔/缺口)。"""
    parts = [
        add_box("SightsFront", (0.007, sight_y - base_y, 0.010),
                (0, base_y + (sight_y - base_y) * 0.5, front_z), bevel=0.0003),
    ]
    if ghost_ring:
        parts.append(add_torus("SightsRearRing", 0.006, 0.0018, (0, sight_y - 0.006, rear_z),
                               seg_major=16, seg_minor=8))
    else:
        parts.append(add_box("SightsRearL", (0.005, 0.016, 0.014), (-0.008, sight_y - 0.010, rear_z), bevel=0.0003))
        parts.append(add_box("SightsRearR", (0.005, 0.016, 0.014), (0.008, sight_y - 0.010, rear_z), bevel=0.0003))
    return join_parts("StockIrons", parts)


def load_port(receiver_bottom, z=-0.04):
    lp = add_empty("LoadPort", (0, receiver_bottom - 0.01, z))
    return lp


# ============================================================ 泵动 3 把

def build_pump_shotgun(c):
    reset()
    receiver_w = c["receiver_w"]
    receiver_h = c["receiver_h"]
    receiver_y = c["receiver_y"]
    receiver_z0 = c["receiver_z0"]
    receiver_z1 = c["receiver_z1"]
    barrel_y = c["barrel_y"]
    barrel_r = c["barrel_r"]
    muzzle_z = c["muzzle_z"]
    tube_y = c["tube_y"]
    tube_r = c["tube_r"]
    tube_z0 = c["tube_z0"]
    tube_z1 = c["tube_z1"]
    sight_y = c["sight_y"]
    receiver_mat = c["receiver_mat"]
    furniture_mat = c["furniture_mat"]
    stock_mat = c.get("stock_mat", furniture_mat)
    receiver_bottom = receiver_y - receiver_h * 0.5
    receiver_top = receiver_y + receiver_h * 0.5

    shotgun_receiver(receiver_w, receiver_h, receiver_y, receiver_z0, receiver_z1, receiver_mat)
    # 机匣鞍轨(optic 落点):泵动霰弹枪标配的机匣顶轨
    if c.get("top_rail", False):
        add_picatinny("TopRail", 0.16, (0, receiver_top + 0.0074, (receiver_z0 + receiver_z1) * 0.5),
                      width=0.020, mount_h=0.004)
    barrel_parts, muzzle_cap_z = shotgun_barrel_assembly(
        barrel_y, barrel_r, receiver_z0, muzzle_z, tube_y, tube_r, tube_z0, tube_z1, receiver_mat)
    if c.get("heat_shield"):
        add_box("HeatShield", (0.036, 0.011, 0.32),
                (0, barrel_y + barrel_r + 0.0065, (receiver_z0 - 0.06 + muzzle_z + 0.12) * 0.5), bevel=0.0006)
    pump_forend(c["pump_r"], c["pump_len"], tube_y, c["pump_z"])
    pump_bolt(receiver_w, receiver_y)
    eject_shell(receiver_w, receiver_y)
    shotgun_furniture(receiver_bottom, receiver_z1, stock_mat,
                      straight=c.get("straight_stock", False),
                      exposed_hammer=c.get("exposed_hammer", False),
                      receiver_top=receiver_top)
    shotgun_sights(sight_y, barrel_y + barrel_r + 0.011, muzzle_cap_z + 0.04, 0.085,
                   ghost_ring=c.get("ghost_ring", False))
    load_port(receiver_bottom)
    apply_materials([
        ("PumpForend", furniture_mat), ("_PumpBody", furniture_mat), ("_PumpRing", "dark"),
        ("_PumpGroove", "dark"), ("_PumpBottom", "dark"), ("_PumpTopGroove", "dark"),
        ("_PumpRod", "metal"), ("bolt", "metal"), ("_BoltNub", "dark"), ("_BoltBody", "metal"),
        ("EjectShell", "brass"), ("StockIrons", "dark"), ("HeatShield", "dark"),
        ("Receiver", receiver_mat), ("BarrelAssembly", receiver_mat), ("Barrel", receiver_mat),
        ("_MagTube", "dark"), ("_TubeClamp", "dark"), ("MuzzleCap", "dark"), ("TopRib", "dark"),
        ("StockGrip", stock_mat), ("StockPlate", stock_mat), ("Grip", stock_mat),
        ("TriggerGuard", "dark"), ("_HammerBody", "metal"), ("_HammerSpur", "metal"),
    ], default="dark")


def build_rem870():
    build_pump_shotgun({
        "receiver_w": 0.048, "receiver_h": 0.072, "receiver_y": 0.018,
        "receiver_z0": -0.16, "receiver_z1": 0.12,
        "barrel_y": 0.045, "barrel_r": 0.016, "muzzle_z": -0.73,
        "tube_y": -0.006, "tube_r": 0.012, "tube_z0": -0.26, "tube_z1": -0.68,
        "sight_y": 0.098, "pump_r": 0.021, "pump_len": 0.23, "pump_z": -0.34,
        "receiver_mat": "metal", "furniture_mat": "wood", "stock_mat": "wood",
        "top_rail": True,
    })


def build_m590():
    build_pump_shotgun({
        "receiver_w": 0.054, "receiver_h": 0.076, "receiver_y": 0.018,
        "receiver_z0": -0.18, "receiver_z1": 0.13,
        "barrel_y": 0.047, "barrel_r": 0.018, "muzzle_z": -0.78,
        "tube_y": -0.007, "tube_r": 0.013, "tube_z0": -0.28, "tube_z1": -0.74,
        "sight_y": 0.101, "pump_r": 0.023, "pump_len": 0.25, "pump_z": -0.37,
        "receiver_mat": "dark", "furniture_mat": "poly", "stock_mat": "poly",
        "heat_shield": True, "ghost_ring": True, "top_rail": True,
    })


def build_win1897():
    build_pump_shotgun({
        "receiver_w": 0.046, "receiver_h": 0.075, "receiver_y": 0.02,
        "receiver_z0": -0.16, "receiver_z1": 0.11,
        "barrel_y": 0.046, "barrel_r": 0.015, "muzzle_z": -0.70,
        "tube_y": -0.005, "tube_r": 0.0115, "tube_z0": -0.30, "tube_z1": -0.66,
        "sight_y": 0.103, "pump_r": 0.020, "pump_len": 0.22, "pump_z": -0.33,
        "receiver_mat": "metal", "furniture_mat": "wood", "stock_mat": "wood",
        "exposed_hammer": True, "straight_stock": True, "top_rail": True,
    })


# ============================================================ 半自动 2 把

def build_semi_shotgun(c):
    reset()
    body_w = c["body_w"]
    body_h = c["body_h"]
    body_y = c["body_y"]
    muzzle_z = c["muzzle_z"]
    tube_y = c["tube_y"]
    tube_r = c["tube_r"]
    tube_z1 = c["tube_z1"]
    sight_y = c["sight_y"]
    body_mat = c["body_mat"]
    furniture_mat = c["furniture_mat"]
    stock_mat = c["stock_mat"]
    body_z0 = -0.18
    body_z1 = 0.14
    barrel_r = 0.0145
    # 一体式枪身(机匣+枪管罩连续)
    add_box("Body", (body_w, body_h, body_z1 - body_z0), (0, body_y, (body_z0 + body_z1) * 0.5), bevel=0.0018)
    # 枪管罩(圆柱):从机匣前缘到枪口
    sh_r = barrel_r + 0.009
    add_cyl("BarrelShroud", sh_r, abs((muzzle_z + 0.02) - (body_z0 - 0.005)),
            (0, body_y, ((body_z0 - 0.005) + (muzzle_z + 0.02)) * 0.5), axis="z", seg=20, bevel=0.0008)
    for i in range(4):
        add_box("_ShroudSlot%d" % i, (0.03, 0.008, 0.04),
                (0, body_y + sh_r + 0.003, body_z0 + abs(muzzle_z - body_z0) * (0.2 + i * 0.18)), bevel=0.0003)
    if c.get("heat_slots"):
        for i in range(5):
            add_box("_HeatSlot%d" % i, (0.056, 0.006, 0.03),
                    (0, body_y + body_h * 0.32, body_z0 - 0.08 - i * 0.05), bevel=0.0003)
    # 管式弹仓(罩下方露出)
    add_cyl("MagTube", tube_r, abs(tube_z1 - (body_z0 - 0.02)),
            (0, tube_y, ((body_z0 - 0.02) + tube_z1) * 0.5), axis="z", seg=14, bevel=0.0004)
    add_cyl("MuzzleCap", barrel_r + 0.010, 0.024, (0, body_y, muzzle_z + 0.012), axis="z", seg=16, bevel=0.0005)
    # 固定下护木(桥接机匣到弹仓端)
    hg_top = body_y - sh_r
    add_box("Foregrip", (body_w * 0.86, max(hg_top - (tube_y + tube_r), 0.02), 0.20),
            (0, (hg_top + tube_y + tube_r) * 0.5, body_z0 - 0.11), bevel=0.0010)
    for i in range(3):
        add_box("_FgRib%d" % i, (body_w * 0.72, 0.006, 0.012),
                (0, tube_y - tube_r - 0.005, body_z0 - 0.03 - i * 0.06), bevel=0.0003)
    if c.get("top_rail"):
        add_picatinny("TopRail", 0.24, (0, body_y + body_h * 0.5 + 0.0074, -0.02), width=0.022)
    # 枪机连杆 + 抛壳弹
    pump_bolt(body_w, body_y - 0.02)
    eject_shell(body_w, body_y - 0.02)
    # 枪托(m1014 伸缩 / spas12 折叠钩)
    if c.get("folding_stock"):
        add_box("StockHinge", (0.030, 0.044, 0.036), (0, body_y - 0.012, body_z1 + 0.015), bevel=0.0008)
        add_box("StockArmTop", (0.020, 0.018, 0.14), (0, body_y + 0.014, body_z1 + 0.10), bevel=0.0006)
        add_box("StockArmBot", (0.020, 0.018, 0.14), (0, body_y - 0.040, body_z1 + 0.10), bevel=0.0006)
        add_box("ButtHook", (0.024, 0.05, 0.026), (0, body_y - 0.010, body_z1 + 0.175), bevel=0.0008)
    else:
        add_box("Stock", (0.044, 0.078, 0.22), (0, body_y - 0.020, body_z1 + 0.14), bevel=0.0014)
        add_box("ButtPad", (0.048, 0.092, 0.020), (0, body_y - 0.020, body_z1 + 0.25), bevel=0.0008)
    add_grip("Grip", 0.034, 0.095, 0.046, (0, body_y - body_h * 0.5 - 0.02, 0.04), tilt=0.36, mat=stock_mat)
    add_box("TriggerGuard", (0.026, 0.008, 0.075), (0, body_y - body_h * 0.5 - 0.032, 0.012), bevel=0.0004)
    # 准星坐在枪身/罩顶
    base_y = body_y + body_h * 0.5 + 0.009
    shotgun_sights(sight_y, base_y, muzzle_z + 0.05, body_z1 - 0.02,
                   ghost_ring=c.get("ghost_ring", False))
    load_port(body_y - body_h * 0.5 - 0.02)
    apply_materials([
        ("bolt", "metal"), ("_BoltBody", "metal"), ("_BoltNub", "dark"),
        ("EjectShell", "brass"), ("StockIrons", "dark"),
        ("Body", body_mat), ("BarrelShroud", body_mat), ("_ShroudSlot", "dark"),
        ("_HeatSlot", "dark"), ("MagTube", "dark"), ("MuzzleCap", "dark"),
        ("Foregrip", furniture_mat), ("_FgRib", "dark"), ("TopRail", "dark"),
        ("Stock", stock_mat), ("ButtPad", "dark"), ("StockHinge", "dark"),
        ("StockArm", "dark"), ("ButtHook", "dark"), ("Grip", stock_mat), ("TriggerGuard", "dark"),
    ], default="dark")


def build_m1014():
    build_semi_shotgun({
        "body_w": 0.052, "body_h": 0.068, "body_y": 0.045,
        "muzzle_z": -0.70, "tube_y": -0.006, "tube_r": 0.012, "tube_z1": -0.63,
        "sight_y": 0.096, "top_rail": True,
        "body_mat": "poly", "furniture_mat": "poly", "stock_mat": "poly",
    })


def build_spas12():
    build_semi_shotgun({
        "body_w": 0.054, "body_h": 0.074, "body_y": 0.048,
        "muzzle_z": -0.72, "tube_y": -0.006, "tube_r": 0.0125, "tube_z1": -0.66,
        "sight_y": 0.100, "heat_slots": True, "folding_stock": True, "top_rail": True,
        "body_mat": "dark", "furniture_mat": "dark", "stock_mat": "dark",
    })


# ============================================================ 特种 2 把

def build_rpg():
    reset()
    # 发射筒 v2:双径圆筒(后段发射机粗 / 前段细)+ 箍环(旧版光杆+浮块,实拍实锤)
    ty = 0.02
    add_cyl("LaunchTube", 0.040, 0.60, (0, ty, -0.19), axis="z", seg=24, bevel=0.0010)
    add_cyl("LaunchMotor", 0.048, 0.18, (0, ty, 0.16), axis="z", seg=24, bevel=0.0010)
    add_cyl("MuzzleCollar", 0.045, 0.05, (0, ty, -0.465), axis="z", seg=24, bevel=0.0008)
    for i, dz in enumerate((-0.32, -0.10, 0.02)):   # 冷却箍环
        add_cyl("_TubeBand%d" % i, 0.043, 0.025, (0, ty, dz), axis="z", seg=24, bevel=0.0005)
    # 顶部短导轨(CLU 挂装)+ 底部握把组件贴管
    add_picatinny("TopRail", 0.30, (0, ty + 0.043, -0.12), width=0.030, mount_h=0.006)
    add_box("_CluMount", (0.024, 0.050, 0.10), (-0.052, ty + 0.048, -0.16), bevel=0.0008)
    add_box("FrontGuard", (0.086, 0.086, 0.045), (0, ty, -0.475), bevel=0.0010)
    # 尾端排焰喇叭口:t=1 端是朝枪口端(Blender +z = Godot -z),所以底半径给
    # 后端大径 0.054、taper=0.74 让朝枪口端收到 0.040 —— 后大前小 = 向后张口
    add_cyl("RearCap", 0.054, 0.09, (0, ty, 0.26), axis="z", seg=24, bevel=0.0010, taper=0.74)
    # 侧置 CLU(制导镜,meta scope_clu) + ScopeEye(空) + 方形目镜框(scope_tube)
    clu = add_empty("ScopeCLU", (-0.062, 0.062, -0.16))
    # 子件直接建在最终世界坐标(clu_pos + GDScript 本地偏移),parent_to 保持世界位置。
    # 混用"本地坐标当世界坐标"会丢父级偏移(CLU 错位实锤过)。
    cx, cy, cz = -0.062, 0.062, -0.16
    # CLU 子件必须 parent 到 ScopeCLU:HUD/开镜逻辑按 scope_clu meta 整组切显隐,
    # 散在根下的子件不会跟着走(实锤过:膛体散件被并进 MergedStatic 还挡视轴)。
    clu_children = [
        add_box("_CluBody", (0.046, 0.115, 0.28), (cx, cy, cz), bevel=0.0020),
        add_box("_CluHood", (0.060, 0.040, 0.050), (cx, cy + 0.008, cz - 0.16), bevel=0.0008),
        add_cyl("_CluObjective", 0.019, 0.05, (cx, cy + 0.010, cz - 0.16), axis="z", seg=14, bevel=0.0004),
        add_cyl("_CluEyepiece", 0.021, 0.035, (cx, cy + 0.010, cz + 0.13), axis="z", seg=14, bevel=0.0004),
        add_box("_CluPanel", (0.020, 0.055, 0.02), (cx, cy - 0.06, cz + 0.08), bevel=0.0004),
    ]
    for ob in clu_children:
        parent_to(ob, clu)
    add_empty("ScopeEye", (-0.062, 0.072, -0.069))
    # 方形目镜框(ADS 时保留显示作为 PIP 取景框) —— join 为 ScopeTubeBody
    frame_parts = [
        add_box("_FrameT", (0.085, 0.012, 0.035), (0, 0.038, 0), bevel=0.0004),
        add_box("_FrameB", (0.085, 0.012, 0.035), (0, -0.038, 0), bevel=0.0004),
        add_box("_FrameL", (0.012, 0.088, 0.035), (-0.040, 0, 0), bevel=0.0004),
        add_box("_FrameR", (0.012, 0.088, 0.035), (0.040, 0, 0), bevel=0.0004),
    ]
    frame = join_parts("ScopeTubeBody", frame_parts)
    frame.location = g2b((-0.062, 0.072, -0.069))
    add_box("BCU", (0.045, 0.060, 0.14), (0.064, -0.012, -0.18), bevel=0.0010)
    add_box("IFFAntenna", (0.006, 0.075, 0.006), (-0.018, 0.112, 0.04), bevel=0.0003)
    add_grip("Grip", 0.034, 0.095, 0.046, (0, -0.026, 0.055), tilt=0.34, mat="dark")
    add_box("ShoulderStock", (0.040, 0.085, 0.035), (0, -0.004, 0.185), bevel=0.0010)
    add_box("TriggerGuard", (0.026, 0.007, 0.070), (0, -0.046, 0.018), bevel=0.0004)
    add_box("_GuardPostF", (0.018, 0.024, 0.007), (0, -0.034, -0.014), bevel=0.0004)
    add_box("_GuardPostB", (0.018, 0.024, 0.007), (0, -0.034, 0.050), bevel=0.0004)
    # 可拆装导弹筒(换弹动画件) —— join 为 rocket
    rkt_parts = [
        # 导弹筒:圆柱 r=0.036 嵌进发射管(内径 0.040),尾端从筒后伸出 60mm
        add_cyl("_RktTube", 0.036, 0.62, (0, 0.02, -0.11), axis="z", seg=20, bevel=0.0008),
        # 战斗部锥:从发射口前伸 12cm
        add_cyl("_RktWarhead", 0.040, 0.14, (0, 0.02, -0.500), axis="z", seg=16, taper=0.05),
        add_box("_RktFinT", (0.010, 0.020, 0.045), (0, 0.045, 0.16), bevel=0.0004),
        add_box("_RktFinB", (0.010, 0.020, 0.045), (0, -0.005, 0.16), bevel=0.0004),
        add_box("_RktFinR", (0.020, 0.010, 0.045), (0.025, 0.02, 0.16), bevel=0.0004),
        add_box("_RktFinL", (0.020, 0.010, 0.045), (-0.025, 0.02, 0.16), bevel=0.0004),
    ]
    join_parts("rocket", rkt_parts)
    apply_materials([
        ("ScopeCLU", "dark"), ("_CluBody", "dark"), ("_CluHood", "poly"),
        ("_CluObjective", "metal"), ("_CluEyepiece", "dark"), ("_CluPanel", "poly"),
        ("ScopeTubeBody", "dark"), ("_Frame", "dark"), ("rocket", "olive"),
        ("_RktWarhead", "brass"), ("_RktFin", "dark"),
        ("LaunchTube", "olive"), ("TopRailBody", "poly"), ("BottomRail", "poly"),
        ("FrontGuard", "dark"), ("RearCap", "dark"), ("BCU", "poly"), ("IFFAntenna", "dark"),
        ("Grip", "dark"), ("ShoulderStock", "poly"), ("TriggerGuard", "dark"),
    ], default="dark")


def build_gl():
    reset()
    # 机匣本体 v2:收窄 + 管尾鞍座包住膛管后端(旧版管与机匣之间生硬台阶,实拍实锤)
    add_box("Receiver", (0.056, 0.078, 0.15), (0, -0.004, 0.02), bevel=0.0014)
    add_box("TopCover", (0.046, 0.026, 0.10), (0, 0.044, 0.03), bevel=0.0010)
    add_box("HingeBlock", (0.03, 0.018, 0.03), (0, -0.04, -0.062), bevel=0.0005)
    add_box("ButtPad", (0.034, 0.066, 0.018), (0, -0.004, 0.104), bevel=0.0008)
    # 鞍座:包住膛管后端(管 z 后端 -0.055),视觉上膛管从机匣里"长"出来
    add_cyl("BreechSaddle", 0.0335, 0.05, (0, 0.012, -0.072), axis="z", seg=20, bevel=0.0006)
    add_grip("Grip", 0.030, 0.098, 0.044, (0, -0.068, 0.055), tilt=0.34, mat="poly")
    add_box("TriggerGuard", (0.024, 0.007, 0.066), (0, -0.052, 0.012), bevel=0.0004)
    add_box("_GuardPostF", (0.016, 0.022, 0.007), (0, -0.041, -0.018), bevel=0.0004)
    add_box("_GuardPostB", (0.016, 0.022, 0.007), (0, -0.041, 0.042), bevel=0.0004)
    # 中折膛体:子件相对铰链轴点(0,-0.04,-0.062)摆放 —— Breech 空对象原点即轴点
    breech = add_empty("Breech", (0, -0.04, -0.062))
    gl_ax = 0.052
    # 子件直接建在最终世界坐标(breech 铰链位置 + GDScript 本地偏移),
    # parent_to 保持世界位置 —— 混用本地/世界坐标系会顶穿视轴(实锤过)。
    bx, by, bz = 0.0, -0.04, -0.062
    # 膛体子件必须 parent 到 Breech:中折换弹时整支膛体绕铰链下折,
    # 散在根下的子件不会跟(还会被 _merge_static 并进静态件挡死视轴,实锤过)。
    breech_children = [
        add_cyl("_GlTube", 0.031, 0.30, (bx, by + gl_ax, bz - 0.143), axis="z", seg=20, bevel=0.0008),
        add_cyl("_GlFrontRing", 0.036, 0.04, (bx, by + gl_ax, bz - 0.285), axis="z", seg=18, bevel=0.0006),
        add_box("_GlTopRail", (0.052, 0.014, 0.20), (bx, by + gl_ax + 0.038, bz - 0.15), bevel=0.0006),
        # 照门/准星顶面 = sight_y(0.0755):缺口照门中央低于视轴,柱体在视轴下缘
        add_box("_GlRearSight", (0.012, 0.026, 0.012), (bx, 0.0755 - 0.013, bz - 0.03), bevel=0.0004),
        add_box("_GlFrontSight", (0.01, 0.022, 0.01), (bx, 0.0755 - 0.011, bz - 0.27), bevel=0.0004),
        add_box("_GlForegrip", (0.03, 0.024, 0.06), (bx, by + gl_ax - 0.04, bz - 0.21), bevel=0.0006),
    ]
    for ob in breech_children:
        parent_to(ob, breech)
    # 膛内 40mm 榴弹(战斗部朝前,随膛体下折) —— 弹壳/战斗部独立命名并 parent 到 rocket
    rd = add_empty("rocket", (bx, by + gl_ax, bz - 0.062))
    parent_to(rd, breech)
    case = add_cyl("_GlCase", 0.0195, 0.075, (bx, by + gl_ax, bz - 0.042), axis="z", seg=12, bevel=0.0004)
    wh = add_cyl("_GlWarhead", 0.021, 0.055, (bx, by + gl_ax, bz - 0.1345), axis="z", seg=14, taper=0.05)
    parent_to(case, rd)
    parent_to(wh, rd)
    apply_materials([
        ("Receiver", "dark"), ("TopCover", "poly"), ("HingeBlock", "metal"),
        ("Grip", "poly"), ("TriggerGuard", "dark"),
        ("_GlTube", "olive"), ("_GlFrontRing", "dark"), ("_GlTopRail", "poly"),
        ("BreechSaddle", "dark"), ("ButtPad", "dark"), ("_GuardPost", "dark"),
        ("_GlRearSight", "dark"), ("_GlFrontSight", "dark"), ("_GlForegrip", "poly"),
        ("rocket", "brass"), ("_GlCase", "brass"), ("_GlWarhead", "olive"),
    ], default="dark")


BUILDERS = {
    "rem870": build_rem870,
    "m590": build_m590,
    "win1897": build_win1897,
    "m1014": build_m1014,
    "spas12": build_spas12,
    "rpg": build_rpg,
    "gl": build_gl,
}

PUMP_SHOTGUNS = {"rem870", "m590", "win1897"}


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
        if wid in PUMP_SHOTGUNS:
            need = ["bolt", "PumpForend", "EjectShell", "LoadPort", "StockIrons"]
        elif wid in ("m1014", "spas12"):
            need = ["bolt", "EjectShell", "LoadPort", "StockIrons"]
        elif wid == "rpg":
            need = ["rocket", "ScopeCLU", "ScopeEye", "ScopeTubeBody"]
        else:
            need = ["Breech", "rocket"]
        ok = all(k in names for k in need)
        print("%-8s objs=%-4d verts=%-6d tris=%-6d  契约=%s  %.0f KB" % (
            wid, objs, verts, tris, "OK" if ok else "MISSING!",
            os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
