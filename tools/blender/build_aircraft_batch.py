# 空中载具高模批次:武装直升机 heli + 喷气战斗机 jet
# 产出 models/aircraft/{heli,jet}.glb —— 多零件多材质槽(零件名=材质语义),
# Godot 侧按零件名重贴 PBR + 契约空节点(Rotor/TailRotor/Muzzle/Burner)接线动画。
# 坐标:Godot 语义(Y 上 / -Z 机头 / +Z 机尾)。旧 box 堆模型作几何参考(尺寸协调)。
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from gunforge import (reset, add_box, add_cyl, add_empty, parent_to, join_parts,
                      export_glb, stats, rot_g2b)


def add_cyl_r(name, radius, length, pos_g, axis="z", seg=24, bevel=0.0, taper=None, rot_g=None):
    """带全局姿态的圆柱:add_cyl 的 axis 旋转已烘焙,再叠加 rot_g 全局欧拉。"""
    ob = add_cyl(name, radius, length, pos_g, axis=axis, seg=seg, bevel=bevel, taper=taper)
    if rot_g:
        ob.rotation_euler = rot_g2b(rot_g)
    return ob

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/aircraft"


def build_heli():
    reset()
    # ---------- 机身 ----------
    add_box("FusMid", (1.55, 1.35, 3.4), (0, 0, 0.2), bevel=0.28)
    add_box("FusFront", (1.4, 1.05, 1.8), (0, -0.08, -2.0), bevel=0.24, rot_g=(0.12, 0, 0))
    add_box("NoseCone", (0.9, 0.6, 0.7), (0, -0.28, -3.0), bevel=0.2)
    # 机鼻传感器转塔(Dark)+ 镜头
    add_cyl("NoseTurret", 0.26, 0.5, (0, -0.62, -3.2), axis="z", seg=14, bevel=0.02)
    add_cyl("NoseLens", 0.12, 0.12, (0, -0.62, -3.48), axis="z", seg=12)
    # 串列双座玻璃(前后舱盖,分段弓形)
    add_box("GlassFront", (1.05, 0.6, 1.1), (0, 0.5, -2.45), bevel=0.24, rot_g=(0.32, 0, 0))
    add_box("GlassRear", (1.15, 0.62, 1.15), (0, 0.72, -1.35), bevel=0.26, rot_g=(0.18, 0, 0))
    add_box("CanopyFrame", (1.2, 0.1, 2.4), (0, 1.05, -1.9), bevel=0.04)
    # 发动机舱 + 排气口
    for sx in (-1, 1):
        add_box("Cowl%d" % (sx + 2), (0.6, 0.65, 2.8), (sx * 0.78, 0.5, 0.7), bevel=0.18)
        add_cyl("Nozzle%d" % (sx + 2), 0.2, 0.5, (sx * 0.88, 0.42, 2.25), axis="z", seg=12, taper=0.7)
    # 主减速器罩
    add_cyl("Gearbox", 0.52, 0.55, (0, 0.98, -0.1), axis="y", seg=16, taper=0.75)
    # ---------- 尾部 ----------
    add_cyl("TailBoom", 0.42, 3.8, (0, 0.42, 4.7), axis="z", seg=14, bevel=0.02, taper=0.5)
    add_box("FinSlope", (0.12, 1.6, 0.9), (0, 1.15, 6.35), bevel=0.04, rot_g=(-0.35, 0, 0))
    add_box("StabH", (1.9, 0.09, 0.55), (0, 0.62, 5.5), bevel=0.03)
    for sx in (-1, 1):
        add_box("StabEnd%d" % (sx + 2), (0.06, 0.45, 0.5), (sx * 0.95, 0.8, 5.5), bevel=0.02)
    # ---------- 尾桨(TailRotor 空节点,4 叶) ----------
    tr = add_empty("TailRotor", (0.3, 1.3, 6.3))
    tr_hub = add_cyl("TRHub", 0.14, 0.12, (0.3, 1.3, 6.3), axis="x", seg=12)
    parent_to(tr_hub, tr)
    for k in range(4):
        a = k * 3.14159265 / 4.0
        blade = add_box("TRBlade%d" % k, (0.05, 0.14, 1.35), (0.3, 1.3, 6.3), bevel=0.01,
                        rot_g=(a, 0, 0))
        parent_to(blade, tr)
    # ---------- 主旋翼(Rotor 空节点,5 叶) ----------
    ro = add_empty("Rotor", (0, 1.5, -0.1))
    shaft = add_cyl("RotorShaft", 0.09, 0.75, (0, 1.13, -0.1), axis="y", seg=10)
    parent_to(shaft, ro)
    hub = add_cyl("RotorHub", 0.3, 0.22, (0, 1.5, -0.1), axis="y", seg=14)
    parent_to(hub, ro)
    import math
    for k in range(5):
        a = k * math.tau / 5.0
        cx = math.cos(a) * 2.4
        cz = -math.sin(a) * 2.4
        blade = add_box("RBlade%d" % k, (4.8, 0.05, 0.4), (cx, 1.52, cz), bevel=0.012,
                        rot_g=(0, a, 0))
        parent_to(blade, ro)
        grip = add_cyl("RGrip%d" % k, 0.07, 0.2, (math.cos(a) * 0.45, 1.5, -math.sin(a) * 0.45),
                       axis="y", seg=8)
        parent_to(grip, ro)
    # ---------- 短翼 + 挂载 ----------
    for sx in (-1, 1):
        add_box("WingStub%d" % (sx + 2), (1.75, 0.12, 0.72), (sx * 0.95, 0.18, -0.5),
                bevel=0.03, rot_g=(0, -sx * 0.08, 0))
        add_box("PylonIn%d" % (sx + 2), (0.14, 0.34, 0.7), (sx * 1.15, -0.08, -0.5), bevel=0.02)
        add_box("PylonOut%d" % (sx + 2), (0.14, 0.34, 0.7), (sx * 1.85, -0.02, -0.55), bevel=0.02)
        # 火箭巢(外壳 + 前后端盖)
        add_cyl("RocketPod%d" % (sx + 2), 0.3, 1.5, (sx * 1.15, -0.42, -0.5), axis="z", seg=16)
        add_cyl("PodCapF%d" % (sx + 2), 0.31, 0.08, (sx * 1.15, -0.42, -1.28), axis="z", seg=16)
        # 反坦克导弹 ×2(上/下)
        for k, my in ((0, -0.28), (1, -0.5)):
            add_cyl("Missile%d%d" % (sx + 2, k), 0.09, 1.7, (sx * 1.85, my, -0.45), axis="z", seg=10)
            add_cyl("MslNose%d%d" % (sx + 2, k), 0.09, 0.3, (sx * 1.85, my, -1.42), axis="z",
                    seg=10, taper=0.05)
            for f in (-1, 1):
                add_box("MslFin%d%d%d" % (sx + 2, k, f + 2), (0.012, 0.22, 0.16),
                        (sx * 1.85, my + f * 0.075, 0.28), bevel=0.004)
    # ---------- 机腹链炮 ----------
    add_cyl("GunTurret", 0.18, 0.35, (0, -0.78, -2.1), axis="y", seg=12)
    add_cyl("Barrel", 0.05, 1.3, (0, -0.9, -2.9), axis="z", seg=10)
    add_empty("Muzzle", (0, -0.9, -3.6))
    # ---------- 起落架 ----------
    add_cyl("GearStrutF", 0.05, 0.55, (0, -1.0, -2.5), axis="y", seg=8)
    add_cyl("GearWheelF", 0.17, 0.14, (0, -1.28, -2.5), axis="x", seg=12)
    for sx in (-1, 1):
        add_cyl("GearStrut%d" % (sx + 2), 0.06, 0.6, (sx * 0.75, -1.0, 1.4), axis="y", seg=8)
        add_cyl("GearWheel%d" % (sx + 2), 0.2, 0.16, (sx * 0.75, -1.32, 1.4), axis="x", seg=12)
        add_box("GearFairing%d" % (sx + 2), (0.2, 0.4, 0.9), (sx * 0.75, -0.72, 1.4), bevel=0.08)
    # 天线 + 队伍色条
    add_cyl("Antenna", 0.012, 0.5, (0, 1.42, 1.9), axis="y", seg=6)
    for sx in (-1, 1):
        add_box("Stripe%d" % (sx + 2), (0.05, 0.16, 2.6), (sx * 0.8, 0.15, 0.2), bevel=0.01)
    return stats()


def build_jet():
    reset()
    # ---------- 机身 ----------
    add_cyl("NoseRadome", 0.5, 2.0, (0, 0.02, -5.2), axis="z", seg=14, bevel=0.02, taper=0.02)
    add_cyl("Pitot", 0.018, 0.7, (0, 0.05, -6.4), axis="z", seg=6)
    add_box("FusFront", (1.35, 0.95, 2.8), (0, 0.03, -3.0), bevel=0.22)
    add_box("GlassCanopy", (0.7, 0.5, 1.9), (0, 0.62, -2.3), bevel=0.3)
    add_box("CanopyBow", (0.74, 0.06, 0.14), (0, 0.66, -1.38), bevel=0.02)
    add_box("Spine", (0.55, 0.4, 3.2), (0, 0.5, 0.7), bevel=0.16)
    add_box("FusMid", (1.75, 0.9, 3.6), (0, 0, 0.3), bevel=0.24)
    add_box("FusRear", (1.5, 0.72, 2.6), (0, 0.06, 3.2), bevel=0.2)
    # 双发尾喷管 + 加力光盘(join 成 BurnerDisc 单 MeshInstance)
    burners = []
    for sx in (-1, 1):
        add_cyl("Nozzle%d" % (sx + 2), 0.34, 0.9, (sx * 0.42, 0.06, 4.7), axis="z", seg=14,
                taper=0.85)
        b = add_cyl("BurnerCone%d" % (sx + 2), 0.3, 0.06, (sx * 0.42, 0.06, 5.2), axis="z", seg=14)
        burners.append(b)
    burner = join_parts("BurnerDisc", burners)
    # ---------- 翼面 ----------
    for sx in (-1, 1):
        add_box("LERX%d" % (sx + 2), (1.1, 0.07, 2.0), (sx * 0.9, -0.06, -2.4), bevel=0.03,
                rot_g=(0, -sx * 0.1, 0))
        add_box("Wing%d" % (sx + 2), (3.4, 0.1, 2.0), (sx * 2.45, -0.02, 0.9), bevel=0.04,
                rot_g=(0, -sx * 0.42, 0))
        # 翼尖格斗弹
        add_box("TipRail%d" % (sx + 2), (0.08, 0.1, 1.9), (sx * 4.05, 0.02, 0.5), bevel=0.01,
                rot_g=(0, -sx * 0.42, 0))
        tip = (sx * 4.28, 0.06, 0.15)
        add_cyl_r("AAM%d" % (sx + 2), 0.075, 2.1, tip, axis="z", seg=10,
                     rot_g=(0, -sx * 0.42, 0))
        add_cyl_r("AAMNose%d" % (sx + 2), 0.075, 0.35, (sx * 4.45, 0.02, -0.85), axis="z", seg=10,
                     rot_g=(0, -sx * 0.42, 0), taper=0.03)
        # 翼下中距弹
        add_box("WingPylon%d" % (sx + 2), (0.1, 0.28, 0.8), (sx * 1.7, -0.35, 0.8), bevel=0.01)
        add_cyl("MLong%d" % (sx + 2), 0.1, 2.6, (sx * 1.7, -0.62, 0.8), axis="z", seg=10)
        add_cyl("MLongNose%d" % (sx + 2), 0.1, 0.4, (sx * 1.7, -0.62, -0.9), axis="z", seg=10,
                taper=0.03)
        add_box("MFin%d%d" % (sx + 2, 0), (0.012, 0.26, 0.3), (sx * 1.7, -0.47, 1.9), bevel=0.005)
        add_box("MFin%d%d" % (sx + 2, 1), (0.012, 0.26, 0.3), (sx * 1.7, -0.77, 1.9), bevel=0.005)
        # 双垂尾(后掠 + 外倾)
        add_box("VStab%d" % (sx + 2), (0.09, 1.7, 1.5), (sx * 0.8, 1.0, 3.6), bevel=0.03,
                rot_g=(0, 0.5, sx * 0.3))
        # 全动平尾
        add_box("HStab%d" % (sx + 2), (2.0, 0.08, 1.15), (sx * 1.55, 0.1, 4.35), bevel=0.03,
                rot_g=(0, -sx * 0.45, 0))
        # 腹鳍
        add_box("VF%d" % (sx + 2), (0.06, 0.65, 1.0), (sx * 0.55, -0.6, 3.3), bevel=0.02,
                rot_g=(0, 0, -sx * 0.35))
        # 两侧进气道 + 唇口
        add_box("Intake%d" % (sx + 2), (0.55, 0.6, 2.4), (sx * 1.0, -0.32, -1.3), bevel=0.16)
        add_box("IntakeLip%d" % (sx + 2), (0.5, 0.55, 0.12), (sx * 1.0, -0.32, -2.52), bevel=0.03)
        # 主起落架舱鼓包
        add_box("GearBay%d" % (sx + 2), (0.4, 0.3, 1.8), (sx * 0.95, -0.5, 1.2), bevel=0.1)
    add_empty("Muzzle", (0, -0.25, -5.8))
    # 队伍色条(垂尾 + 机身侧)
    for sx in (-1, 1):
        add_box("StripeV%d" % (sx + 2), (0.02, 0.38, 0.5), (sx * 0.87, 1.1, 3.75), bevel=0.008,
                rot_g=(0, 0.5, sx * 0.3))
        add_box("StripeF%d" % (sx + 2), (0.04, 0.12, 2.2), (sx * 0.89, 0.2, -0.5), bevel=0.008)
    return stats()


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for bid, fn in (("heli", build_heli), ("jet", build_jet)):
        reset()
        objs, verts, tris = fn()
        path = OUT_DIR + "/" + bid + ".glb"
        export_glb(path)
        print("[build] %s objs=%d verts=%d tris=%d" % (bid, objs, verts, tris))
    print("[done]")
