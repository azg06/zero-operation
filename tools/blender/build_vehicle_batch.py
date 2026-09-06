"""
载具外部建模批次(4 车):jeep 侦察吉普 / tank 主战坦克 / apc 轮式步战车 / aa 自行防空炮

节点命名契约(vehicle.gd / vehicle_models.gd 驱动):
    Turret        炮塔组(挂点:rotation.y = turret_yaw;可为目标网格合并体)
    Cannon        炮管组(Turret 子节点;rotation.x = turret_pitch,position.z = 后坐)
    Muzzle        炮口空点(Cannon 子节点;position.z = 后坐)
    SteerFL/FR    前轮转向枢轴(jeep/apc;rotation.y = steer)
    Wheel*        车轮自转节点(rotation.x = 滚动)
坐标:根在地面 y=0,前方 -Z,单位米。

用法:
    blender --background --python build_vehicle_batch.py
    blender --background --python build_vehicle_batch.py -- jeep tank
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/vehicles"


def _set_origin(ob, pos_g):
    """把对象原点搬到 Godot 语义坐标 pos_g(网格世界位置不变)。
    炮塔/炮管的旋转绕节点原点 —— 原点必须在旋转轴上。"""
    import mathutils
    bpy.context.scene.cursor.location = mathutils.Vector(g2b(pos_g))
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return ob


def _steer_wheel(sx, sz, r, spin_name, steer=False):
    """车轮:转向枢轴(可选)+ 自转节点 + 胎体 + 轮毂。返回 (spin, steer|None)。"""
    pivot = add_empty("Steer_%s" % spin_name, (sx, r, sz)) if steer else None
    spin = add_empty(spin_name, (sx, r, sz))
    if pivot is not None:
        parent_to(spin, pivot)
    tire = add_cyl("%s_Tire" % spin_name, r, 0.30, (sx, r, sz), axis="x", seg=18, bevel=0.02)
    hub = add_cyl("%s_Hub" % spin_name, r * 0.44, 0.32, (sx, r, sz), axis="x", seg=10)
    if pivot is not None:
        parent_to(tire, spin)
        parent_to(hub, spin)
    else:
        parent_to(tire, spin)
        parent_to(hub, spin)
    return spin, pivot


# ============================================================ 吉普
def build_jeep():
    reset()
    # --- 底盘双梁 + 传动轴
    add_box("FrameL", (0.08, 0.12, 3.7), (-0.42, 0.44, 0), bevel=0.01)
    add_box("FrameR", (0.08, 0.12, 3.7), (0.42, 0.44, 0), bevel=0.01)
    add_cyl("Driveshaft", 0.045, 2.4, (0, 0.42, 0.1), axis="z", seg=8)
    # --- 车身盆体 + 引擎舱 + 后货斗
    add_box("Tub", (1.78, 0.34, 3.3), (0, 0.74, 0.12), bevel=0.015)
    add_box("Hood", (1.66, 0.14, 1.34), (0, 1.00, -1.20), bevel=0.012)
    add_box("HoodSideL", (0.05, 0.22, 1.34), (-0.84, 0.90, -1.20))
    add_box("HoodSideR", (0.05, 0.22, 1.34), (0.84, 0.90, -1.20))
    # 格栅 + 竖栅条 + 大灯
    add_box("Grille", (1.06, 0.46, 0.05), (0, 0.88, -1.90))
    for i in range(5):
        add_box("_GrilleSlat%d" % i, (0.16, 0.40, 0.03), (-0.42 + i * 0.21, 0.88, -1.92))
    add_cyl("LightL", 0.09, 0.05, (-0.62, 0.98, -1.91), axis="z", seg=12)
    add_cyl("LightR", 0.09, 0.05, (0.62, 0.98, -1.91), axis="z", seg=12)
    # --- 翼子板(四轮上方圆弧观感的加厚板)
    for sx, sz, nm in ((-0.86, -1.25, "FL"), (0.86, -1.25, "FR"), (-0.86, 1.25, "RL"), (0.86, 1.25, "RR")):
        add_box("Fender%s" % nm, (0.30, 0.05, 1.10), (sx, 0.92, sz), bevel=0.01)
    # --- 前挡风框(倾斜)+ 玻璃
    add_box("WipeFrameB", (1.60, 0.07, 0.06), (0, 1.22, -0.44))
    add_box("WipeFrameT", (1.60, 0.07, 0.06), (0, 1.56, -0.56))
    glass = add_box("WipeGlass", (1.54, 0.40, 0.02), (0, 1.39, -0.50), rot_g=(-0.30, 0, 0))
    glass.name = "Glass"
    # --- 防滚架:四柱 + 顶纵杆 + 交叉斜撑
    for sx, sz in ((-0.80, -0.42), (0.80, -0.42), (-0.80, 0.92), (0.80, 0.92)):
        add_cyl("CagePost%d%d" % (sx * 10, sz * 10), 0.035, 1.06, (sx, 1.56, sz), axis="y", seg=8)
    for sz in (-0.42, 0.92):
        add_cyl("CageTop%d" % (sz * 10), 0.035, 1.64, (0, 2.08, sz), axis="x", seg=8)
    for sx in (-0.80, 0.80):
        add_cyl("CageRail%d" % (sx * 10), 0.033, 1.38, (sx, 2.08, 0.25), axis="z", seg=8)
    # --- 后货斗侧板 + 尾板 + 备胎
    add_box("CargoL", (0.05, 0.30, 1.10), (-0.86, 1.02, 1.30))
    add_box("CargoR", (0.05, 0.30, 1.10), (0.86, 1.02, 1.30))
    add_box("CargoB", (1.76, 0.30, 0.05), (0, 1.02, 1.87))
    add_cyl("SpareWheel", 0.40, 0.22, (0, 1.10, 2.00), axis="z", seg=16)
    # --- 前后保险杠
    add_box("BumperF", (1.70, 0.10, 0.12), (0, 0.56, -2.02), bevel=0.015)
    add_box("BumperR", (1.70, 0.10, 0.12), (0, 0.56, 2.06), bevel=0.015)
    # --- 车轮(前轴转向枢轴 + 自转)
    spins, steers = [], []
    sp, st = _steer_wheel(-0.86, -1.25, 0.42, "WheelFL", True)
    spins.append(sp); steers.append(st)
    sp, st = _steer_wheel(0.86, -1.25, 0.42, "WheelFR", True)
    spins.append(sp); steers.append(st)
    sp, _ = _steer_wheel(-0.86, 1.25, 0.42, "WheelRL")
    spins.append(sp)
    sp, _ = _steer_wheel(0.86, 1.25, 0.42, "WheelRR")
    spins.append(sp)
    # --- 乘客位机枪座环(纯模型:环形滑轨贴盆体顶面 + 立柱从环上升起;
    # 旧版整座悬空 0.3m)
    add_cyl("MgRing", 0.30, 0.05, (0, 0.935, 1.15), axis="y", seg=16)
    add_cyl("MgPost", 0.03, 0.34, (0, 1.13, 1.15), axis="y", seg=8)
    apply_materials([
        ("Tire", "dark"), ("Grille", "dark"), ("Cage", "dark"), ("Hub", "metal"),
        ("Glass", "dark"), ("Light", "chrome"), ("Bumper", "dark"), ("Frame", "dark"),
        ("Driveshaft", "dark"), ("Spare", "dark"), ("Mg", "dark"),
    ], default="olive")
    return


# ============================================================ 主战坦克
def build_tank():
    reset()
    # --- 履带总成(两侧):带体 + 驱动轮/导轮 + 7 负重轮 + 侧裙
    for tx, sd in ((-1.15, -1), (1.15, 1)):
        add_box("Track%d" % sd, (0.72, 0.58, 5.5), (tx, 0.47, 0), bevel=0.03)
        add_cyl("Sprocket%d" % sd, 0.30, 0.74, (tx, 0.40, 2.45), axis="x", seg=12)
        add_cyl("Idler%d" % sd, 0.28, 0.74, (tx, 0.42, -2.45), axis="x", seg=12)
        for i in range(7):
            add_cyl("RoadWheel%d_%d" % (sd, i), 0.33, 0.60, (tx, 0.36, -2.1 + i * 0.7), axis="x", seg=12)
        add_box("Skirt%d" % sd, (0.05, 0.40, 4.7), (tx + sd * 0.37, 0.95, 0), bevel=0.01)
    # --- 车体 + 首上斜甲 + 尾板 + 引擎甲板格栅
    # 首上斜甲压平(rot 0.45)并前缘收进:顶缘 1.583 让主炮(底 1.625)通过 ——
    # 旧版斜甲顶缘 1.77 高过炮管,0 瞬弹 clipping
    add_box("Hull", (2.46, 0.74, 4.7), (0, 1.14, 0), bevel=0.02)
    add_box("Glacis", (2.46, 0.10, 1.0), (0, 1.32, -2.15), bevel=0.01, rot_g=(0.45, 0, 0))
    add_box("RearPlate", (2.3, 0.55, 0.10), (0, 1.14, 2.40))
    add_box("EngineDeck", (2.3, 0.10, 1.5), (0, 1.53, 1.55), bevel=0.01)
    for i in range(4):
        add_box("_DeckGrille%d" % i, (1.9, 0.03, 0.16), (0, 1.59, 1.0 + i * 0.36))
    # --- 翼子板(履带上方)
    for tx, sd in ((-1.15, -1), (1.15, 1)):
        add_box("Fender%d" % sd, (0.34, 0.05, 4.8), (tx + sd * 0.36, 1.30, 0), bevel=0.01)
    # --- 炮塔(楔形焊接):侧斜板×2 + 正面板 + 尾舱 + 舱盖 + 潜望镜块 + 烟幕弹排
    # 整组下沉 0.26:旧版炮塔底缘(1.73)悬在车体顶(1.51)上方 0.22m;
    # 现侧板底 1.47 嵌进车体顶 —— 炮塔坐在车体上。
    # [FIX 车底露塔] parts 一律写世界坐标(origin y 1.80 已含在内):
    # 旧版写的是"相对 origin 局部坐标"(0.38-0.26=0.12 等),而 origin_set 只搬
    # 原点不搬网格 → 整座炮塔建在地面高度、嵌进车体、底面露出 0.35m(仰拍实锤)
    _TDY = -0.26
    _TOY = 1.80  # 炮塔 origin 高度,零件世界 y = 局部设计值 + _TOY
    parts = [
        add_box("_TurretRoof", (1.98, 0.10, 2.60), (0, 0.38 + _TDY + _TOY, 0.05), bevel=0.01),
        add_box("_TurretSideL", (0.10, 0.46, 2.60), (-0.95, 0.16 + _TDY + _TOY, 0.05), bevel=0.01, rot_g=(0, 0, -0.22)),
        add_box("_TurretSideR", (0.10, 0.46, 2.60), (0.95, 0.16 + _TDY + _TOY, 0.05), bevel=0.01, rot_g=(0, 0, 0.22)),
        add_box("_TurretFront", (1.60, 0.52, 0.16), (0, 0.18 + _TDY + _TOY, -1.20), bevel=0.01, rot_g=(0.22, 0, 0)),
        add_box("_TurretRear", (1.80, 0.44, 0.14), (0, 0.20 + _TDY + _TOY, 1.30)),
        add_box("_Mantlet", (0.90, 0.34, 0.30), (0, 0.16 + _TDY + _TOY, -1.28), bevel=0.02),
        add_box("_Cupola", (0.52, 0.16, 0.52), (0.52, 0.50 + _TDY + _TOY, 0.55), bevel=0.01),
        add_box("_Hatch", (0.46, 0.04, 0.46), (0.52, 0.60 + _TDY + _TOY, 0.55)),
        add_box("_PeriBlock", (0.30, 0.10, 0.20), (-0.45, 0.47 + _TDY + _TOY, 0.30)),
    ]
    for i in range(4):
        parts.append(add_cyl("_Smoke%d" % i, 0.035, 0.16, (-0.72 - (i % 2) * 0.14, 0.34 + _TDY - (i // 2) * 0.16 + _TOY, 0.92), axis="x", seg=8))
    turret = _set_origin(join_parts("Turret", parts), (0, 1.80, 0.20))
    # 炮塔尾舱篮(框架):底板贴炮塔后壁(z=1.37),托架从底板向后延伸 ——
    # 旧版整体悬在炮塔后方 0.44m 空中(实拍实锤)
    add_box("BustleRack", (1.72, 0.06, 0.50), (0, 1.65, 1.66))
    add_box("BustleBase", (1.72, 0.20, 0.06), (0, 1.76, 1.40))
    parent_to(bpy.data.objects["BustleRack"], turret)
    parent_to(bpy.data.objects["BustleBase"], turret)
    # --- 主炮组:Cannon 枢轴在耳轴,身管三段(热护套/抽烟器/制退器)
    # 耳轴随炮塔下沉:y 1.98 → 1.72
    cannon = add_empty("Cannon", (0, 1.72, -1.02))
    parent_to(cannon, turret)
    barrel_parts = [
        add_box("_Breech", (0.30, 0.30, 0.44), (0, 1.72, -0.78), bevel=0.01),
        add_cyl("_SleeveA", 0.095, 1.30, (0, 1.72, -1.60), axis="z", seg=14),
        add_cyl("_Evacuator", 0.115, 0.55, (0, 1.72, -2.55), axis="z", seg=14, bevel=0.02),
        add_cyl("_SleeveB", 0.088, 1.30, (0, 1.72, -3.42), axis="z", seg=14),
        add_cyl("_Brake", 0.125, 0.44, (0, 1.72, -4.22), axis="z", seg=14, bevel=0.02),
    ]
    # 制退器侧孔:在实体上切完再 join(join 会吞对象名)
    cut(bpy.data.objects["_Brake"], add_box("_BrakePortL", (0.05, 0.05, 0.20), (-0.09, 1.72, -4.24)))
    cut(bpy.data.objects["_Brake"], add_box("_BrakePortR", (0.05, 0.05, 0.20), (0.09, 1.72, -4.24)))
    barrel = join_parts("CannonTube", barrel_parts)
    _set_origin(barrel, (0, 1.72, -1.02))
    parent_to(barrel, cannon)
    muzzle = add_empty("Muzzle", (0, 1.72, -4.48))
    parent_to(muzzle, cannon)
    # --- 前大灯(坐在首上斜甲表面上)+ 尾部油桶(压低+支架连接尾板)
    add_cyl("HeadL", 0.09, 0.05, (-0.82, 1.66, -2.66), axis="z", seg=10)
    add_cyl("HeadR", 0.09, 0.05, (0.82, 1.66, -2.66), axis="z", seg=10)
    add_cyl("FuelDrumL", 0.22, 0.50, (-0.72, 1.28, 2.58), axis="z", seg=12, bevel=0.02)
    add_cyl("FuelDrumR", 0.22, 0.50, (0.72, 1.28, 2.58), axis="z", seg=12, bevel=0.02)
    for sdx in (-0.72, 0.72):
        add_box("DrumBracket%d" % int(sdx * 100), (0.08, 0.34, 0.10), (sdx, 1.28, 2.46))
    apply_materials([
        ("Track", "dark"), ("RoadWheel", "dark"), ("Sprocket", "dark"), ("Idler", "dark"),
        ("Skirt", "olive"), ("Barrel", "dark"), ("Brake", "dark"), ("Muzzle", "dark"),
        ("Breech", "dark"), ("Evacuator", "olive"), ("Sleeve", "olive"),
        ("Smoke", "dark"), ("Head", "chrome"), ("DeckGrille", "dark"),
        ("Glass", "dark"), ("Peri", "dark"), ("Cupola", "olive"), ("Hatch", "olive"),
    ], default="olive")
    return


# ============================================================ 轮式步战车
def build_apc():
    reset()
    # --- 8 轮:前两轴转向
    spins, steers = [], []
    axles = [-1.90, -0.65, 0.65, 1.90]
    for ai, wz in enumerate(axles):
        for sd, wx in ((-1, -1.08), (1, 1.08)):
            sp, st = _steer_wheel(wx, wz, 0.46, "Wheel%d%s" % (ai, "L" if sd < 0 else "R"), ai < 2)
            spins.append(sp)
            if st is not None:
                steers.append(st)
    # --- 车体:V 型底_hint + 主箱 + 上部箱 + 斜侧壁 + 轮拱
    add_box("Hull", (2.24, 0.86, 5.7), (0, 1.16, 0), bevel=0.02)
    add_box("HullUpper", (1.94, 0.52, 3.5), (0, 1.86, 0.42), bevel=0.015)
    for sd in (-1, 1):
        add_box("HullSlope%d" % sd, (0.10, 0.66, 4.9), (sd * 1.17, 1.42, 0), bevel=0.01, rot_g=(0, 0, sd * 0.18))
        add_box("WheelArch%d" % sd, (0.10, 0.16, 4.4), (sd * 1.16, 0.82, 0), bevel=0.01)
    add_box("Bow", (2.10, 0.30, 0.9), (0, 1.32, -3.02), bevel=0.02, rot_g=(0.42, 0, 0))
    # 驾驶观察窗(前斜面暗玻璃缝) + 侧门缝 + 尾门
    add_box("GlassFront", (1.30, 0.34, 0.03), (0, 1.78, -2.36), rot_g=(0.5, 0, 0))
    for sd in (-1, 1):
        add_box("DoorSlot%d" % sd, (0.04, 0.42, 0.90), (sd * 1.21, 1.60, -1.35))
    add_box("RearDoor", (1.60, 0.72, 0.05), (0, 1.28, 2.88))
    # --- 炮塔(双人 25mm):楔形小炮塔 + 炮管 + 抽壳匣 + 观瞄镜 + 烟幕弹
    # [FIX 车底露塔] 同 tank:parts 写世界坐标(origin y 2.14 已含在内),
    # 旧版局部坐标把炮塔建进车体内部(顶面不可见,仰角看穿)
    _TOY = 2.14  # APC 炮塔 origin 高度
    parts = [
        add_box("_TRoof", (1.36, 0.08, 1.66), (0, 0.26 + _TOY, 0.02), bevel=0.008),
        add_box("_TSideL", (0.08, 0.30, 1.66), (-0.66, 0.12 + _TOY, 0.02), bevel=0.006, rot_g=(0, 0, -0.16)),
        add_box("_TSideR", (0.08, 0.30, 1.66), (0.66, 0.12 + _TOY, 0.02), bevel=0.006, rot_g=(0, 0, 0.16)),
        add_box("_TFront", (1.10, 0.34, 0.12), (0, 0.14 + _TOY, -0.80), bevel=0.008, rot_g=(0.2, 0, 0)),
        add_box("_TRear", (1.14, 0.28, 0.10), (0, 0.14 + _TOY, 0.82)),
        add_box("_Mantlet", (0.42, 0.24, 0.24), (0, 0.10 + _TOY, -0.86), bevel=0.015),
    ]
    for i in range(3):
        parts.append(add_cyl("_Smoke%d" % i, 0.03, 0.14, (-0.52 - i * 0.15, 0.22 + _TOY, 0.60), axis="x", seg=8))
    turret = _set_origin(join_parts("Turret", parts), (0, 2.14, -0.30))
    # --- 25mm 机炮组
    cannon = add_empty("Cannon", (0, 2.26, -1.08))
    parent_to(cannon, turret)
    barrel_parts = [
        add_box("_Receiver", (0.20, 0.24, 0.60), (0, 2.26, -1.34), bevel=0.01),
        add_cyl("_BarrelA", 0.052, 0.90, (0, 2.26, -2.02), axis="z", seg=12),
        add_cyl("_BarrelB", 0.040, 1.30, (0, 2.26, -3.02), axis="z", seg=12),
    ]
    barrel = join_parts("CannonTube", barrel_parts)
    _set_origin(barrel, (0, 2.26, -1.08))
    parent_to(barrel, cannon)
    muzzle = add_empty("Muzzle", (0, 2.26, -3.70))
    parent_to(muzzle, cannon)
    # 观瞄镜箱 + 弹箱 + 尾部天线:全部挂在炮塔上随动(旧版是世界坐标孤件,
    # 炮塔一转就脱离悬空);箱底沉进炮塔顶固定
    add_box("SightBox", (0.24, 0.16, 0.40), (0.30, 2.50, -0.72))
    add_box("AmmoBoxL", (0.34, 0.26, 0.60), (-0.52, 2.54, -0.60))
    add_cyl("Antenna", 0.012, 0.90, (0.78, 2.88, 0.62), axis="y", seg=6)
    parent_to(bpy.data.objects["SightBox"], turret)
    parent_to(bpy.data.objects["AmmoBoxL"], turret)
    parent_to(bpy.data.objects["Antenna"], turret)
    apply_materials([
        ("Tire", "dark"), ("Hub", "metal"), ("Barrel", "dark"), ("Receiver", "dark"),
        ("Muzzle", "dark"), ("Smoke", "dark"), ("Glass", "dark"), ("Antenna", "dark"),
        ("Sight", "dark"), ("Ammo", "olive"), ("Door", "olive"), ("WheelArch", "olive"),
    ], default="olive")
    return


# ============================================================ 自行防空炮
def build_aa():
    reset()
    # --- 6 轮底盘(命名用轴索引:旧版 abs(wz)*10 使 ±1.60 两轴重名 Wheel16,
    #     Blender 自动派生 _001 后缀污染契约节点名)
    spins = []
    for ai, wz in enumerate((-1.60, 0.0, 1.60)):
        for sd, wx in ((-1, -1.02), (1, 1.02)):
            sp, _ = _steer_wheel(wx, wz, 0.44, "Wheel%d%s" % (ai, "L" if sd < 0 else "R"), wz < -1.0)
            spins.append(sp)
    # --- 车体:驾驶舱(前,带挡风玻璃+前墙) + 货斗侧板(中后)
    add_box("Hull", (2.12, 0.82, 5.0), (0, 1.10, -0.05), bevel=0.02)
    add_box("CabSideL", (0.06, 0.62, 1.5), (-1.03, 1.62, -1.55))
    add_box("CabSideR", (0.06, 0.62, 1.5), (1.03, 1.62, -1.55))
    add_box("CabRoof", (2.06, 0.06, 1.5), (0, 1.94, -1.55))
    # 驾驶室前墙:连接两侧CabSide并承住玻璃(旧版玻璃悬空无依托)
    add_box("CabFront", (2.06, 0.62, 0.06), (0, 1.62, -2.32))
    add_box("GlassFront", (1.70, 0.42, 0.03), (0, 1.72, -2.275), rot_g=(-0.18, 0, 0))
    for sz, nm in ((-0.30, "Mid"), (1.30, "Rear")):
        add_box("BedSide%sL" % nm, (0.06, 0.44, 1.30), (-1.04, 1.42, sz))
        add_box("BedSide%sR" % nm, (0.06, 0.44, 1.30), (1.04, 1.42, sz))
    add_box("BedGate", (2.06, 0.44, 0.06), (0, 1.42, 2.44))
    # --- 旋转平台(Turret):座圈圆台 + 齿圈观感 —— 整组下沉 0.38:平台底面
    # (1.51)必须坐在货斗底(车体顶)上,旧版悬空 0.38m(实拍实锤)
    platform = add_cyl("_Platform", 0.92, 0.34, (0, 1.68, 0.85), axis="y", seg=18, bevel=0.02)
    _set_origin(platform, (0, 1.68, 0.85))
    platform.name = "Turret"
    add_cyl("TurretRing", 1.00, 0.06, (0, 1.53, 0.85), axis="y", seg=20)
    # --- 四联高射机炮(Cannon 枢轴在平台前部)
    cannon = add_empty("Cannon", (0, 1.98, 0.42))
    parent_to(cannon, platform)
    add_box("_GunShield", (1.30, 0.52, 0.05), (0, 2.06, 0.16), bevel=0.008)
    parent_to(bpy.data.objects["_GunShield"], cannon)
    barrel_parts = []
    for i, (bx, by) in enumerate(((-0.17, 0.12), (0.17, 0.12), (-0.17, -0.12), (0.17, -0.12))):
        barrel_parts.append(add_cyl("_Barrel%d" % i, 0.038, 2.15, (bx, 2.02 + by, -0.92), axis="z", seg=10))
        barrel_parts.append(add_cyl("_BarrelTip%d" % i, 0.048, 0.16, (bx, 2.02 + by, -2.02), axis="z", seg=10))
    barrel_parts.append(add_box("_AmmoBox", (0.62, 0.36, 0.72), (0, 1.94, -0.18), bevel=0.01))
    barrel = join_parts("CannonTube", barrel_parts)
    _set_origin(barrel, (0, 1.98, 0.42))
    parent_to(barrel, cannon)
    muzzle = add_empty("Muzzle", (0, 2.02, -2.12))
    parent_to(muzzle, cannon)
    # --- 搜索雷达板(折叠支架,平台后方,支架挂平台随动) + 弹箱对 + 稳定支脚
    add_box("RadarArm", (0.08, 0.50, 0.08), (0, 2.04, 1.42))
    radar = add_box("RadarPanel", (1.05, 0.62, 0.06), (0, 2.34, 1.46), bevel=0.01, rot_g=(-0.45, 0, 0))
    parent_to(bpy.data.objects["RadarArm"], platform)
    parent_to(radar, platform)
    for sx, sz in ((-0.85, 1.9), (0.85, 1.9)):
        add_cyl("Outrigger%d%d" % (sx * 10, sz * 10), 0.035, 0.44, (sx, 0.62, sz), axis="y", seg=8)
    apply_materials([
        ("Tire", "dark"), ("Hub", "metal"), ("Barrel", "dark"), ("BarrelTip", "dark"),
        ("GunShield", "olive"), ("Ammo", "olive"), ("Radar", "dark"), ("RadarArm", "dark"),
        ("Glass", "dark"), ("Muzzle", "dark"), ("Outrigger", "dark"),
    ], default="olive")
    return


BUILDERS = {"jeep": build_jeep, "tank": build_tank, "apc": build_apc, "aa": build_aa}


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
        print("%-6s objs=%-4d verts=%-6d tris=%-6d  %.0f KB" % (
            wid, objs, verts, tris, os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
