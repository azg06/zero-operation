"""
AK-47 高精度模型 —— 突击步枪批次 1/8

参考 weapon_models.gd 原 _build_ak 的布局(保持 HAND_ANCHORS / MUZZLE_Z 兼容),
用 Blender 重新构建:机匣铣削面、防尘盖、上下两片木护木、AK 标志性的弧形钢弹匣、
木枪托 / 木握把、斜切制退器、AKM 风格准星 / 照门。

可动件:mag(弧形钢弹匣)、bolt(右侧大拉机柄)—— Godot 侧按名字绑定 meta。
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gunforge import *
import math as _m


def build():
    reset()
    RY = 0.028       # 枪管轴线高度(AK 较 M4 高)
    SIGHT = 0.104    # sight_y(导轨/机匣上缘必须低于此值)

    # ================= 机匣 =================
    upper = add_box("UpperReceiver", (0.054, 0.066, 0.30), (0, 0.012, -0.03), bevel=0.0012)
    # 防尘盖(机匣顶部独立件,可单独打开清装)
    cover = add_box("DustCover", (0.05, 0.020, 0.22), (0, 0.052, -0.02), bevel=0.0008)
    # 防尘盖手柄(顶部凸起)
    add_box("CoverHandle", (0.018, 0.006, 0.030), (0, 0.063, -0.020), bevel=0.0004)
    # 右侧大拨片保险
    add_box("SafetyLever", (0.012, 0.020, 0.10), (0.030, 0.012, -0.02), bevel=0.0006)

    # ================= 前节套 / 导气 =================
    add_box("FrontTrunnion", (0.05, 0.05, 0.05), (0, 0.024, -0.16), bevel=0.0008)
    add_cyl("GasTube", 0.011, 0.34, (0, 0.05, -0.26), axis="z", seg=10, bevel=0.0004)
    add_box("GasBlock", (0.024, 0.045, 0.05), (0, 0.034, -0.44), bevel=0.0006)
    # 导气座顶部刺刀座(卡拉什尼科夫刺刀导轨)
    add_box("BayonetLug", (0.008, 0.010, 0.020), (0, 0.072, -0.430), bevel=0.0004)

    # ================= 木护木(上下两片夹住枪管) =================
    # 上护木
    add_box("UpperHandguard", (0.046, 0.032, 0.16), (0, 0.054, -0.28), bevel=0.0008)
    # 下护木
    add_box("LowerHandguard", (0.05, 0.042, 0.16), (0, 0.009, -0.28), bevel=0.0008)
    # 护木前箍(铁制)
    add_box("HandguardBand", (0.051, 0.014, 0.018), (0, 0.030, -0.22), bevel=0.0004)
    # 护木后箍
    add_box("HandguardRearBand", (0.051, 0.014, 0.018), (0, 0.030, -0.40), bevel=0.0004)

    # ================= 枪管 / 准星座 / 制退器 =================
    add_cyl("Barrel", 0.012, 0.52, (0, RY, -0.51), axis="z", seg=16, bevel=0.0006)
    add_cyl("BarrelStep", 0.014, 0.030, (0, RY, -0.245), axis="z", seg=16, bevel=0.0004)
    # 准星座(坐落在枪管护箍上,带斜切口)
    add_box("FrontSightBase", (0.020, 0.055, 0.030), (0, 0.052, -0.76), bevel=0.0006)
    # 准星柱(弧形 AK 准星头部)
    add_cyl("FrontSightPost", 0.0055, 0.022, (0, 0.085, -0.76), axis="y", seg=10, bevel=0.0004)
    # 斜切制退器(枪口楔形开口)
    muzzle_dev = add_cyl("MuzzleDevice", 0.015, 0.040, (0, RY, -0.84), axis="z", seg=16, bevel=0.0005)
    cut(muzzle_dev, add_box("_cut_muzzle", (0.012, 0.018, 0.020), (0, RY + 0.005, -0.85)))

    # ================= 木枪托 =================
    # 托体
    add_box("StockBody", (0.044, 0.100, 0.20), (0, -0.006, 0.19), bevel=0.0015)
    # 托底板
    add_box("StockPlate", (0.048, 0.10, 0.022), (0, 0.0, 0.29), bevel=0.0010)
    # 托与机匣的连接
    add_box("StockFerrule", (0.046, 0.060, 0.030), (0, -0.010, 0.09), bevel=0.0008)
    # 背带环
    add_box("SlingSlot", (0.005, 0.018, 0.008), (0.020, -0.030, 0.20), bevel=0.0004)

    # ================= 木握把 + 扳机 =================
    add_box("PistolGrip", (0.034, 0.100, 0.046), (0, -0.024, 0.045), bevel=0.0012)
    # 握把防滑纹
    for i in range(5):
        add_box("GripRib%d" % i, (0.0355, 0.005, 0.008), (0, -0.012 - i * 0.013, 0.050), bevel=0.0003)
    add_box("GripCap", (0.036, 0.008, 0.048), (0, -0.082, 0.045), bevel=0.0006)
    # 扳机
    add_box("Trigger", (0.008, 0.020, 0.010), (0, -0.036, 0.015), bevel=0.0005)
    # 扳机护圈
    add_box("TriggerGuardFront", (0.008, 0.024, 0.008), (0, -0.040, -0.020), bevel=0.0006)
    add_box("TriggerGuardBottom", (0.008, 0.008, 0.080), (0, -0.052, 0.020), bevel=0.0006)
    add_box("TriggerGuardRear", (0.008, 0.024, 0.008), (0, -0.038, 0.058), bevel=0.0006)

    # ================= 照门(鼓式,后托前段) =================
    add_box("RearSightBase", (0.030, 0.014, 0.040), (0, 0.038, 0.030), bevel=0.0006)
    add_box("RearSightDrum", (0.022, 0.012, 0.016), (0, 0.052, 0.030), bevel=0.0005)
    # 鼓式分划的滑块指示线
    add_box("RearSightMark", (0.002, 0.002, 0.012), (0, 0.058, 0.030), bevel=0.0002)

    # ================= 可动件:弧形钢弹匣(标志性) =================
    # 弧形弹匣弯曲向左前方 —— 用 5 段逼近曲线
    mag_segments = []
    N = 6
    RADIUS = 0.110
    ANGLE = 0.65
    for i in range(N):
        t = i / float(N - 1)
        a = -ANGLE * 0.5 + t * ANGLE
        zc = -0.060 - RADIUS * (1.0 - _m.cos(a)) - 0.040
        yc = -0.024 - RADIUS * _m.sin(a) + 0.005
        # 每段是一个微弯的盒子
        seg = add_box("_mag_seg%d" % i, (0.038, 0.022, 0.040),
                      (0, yc, zc), bevel=0.0006)
        seg.rotation_euler = (-_m.sin(a) * 0.0, 0, _m.sin(a) * 0.3)
        mag_segments.append(seg)
    # 底板
    floor = add_box("_mag_floor", (0.040, 0.008, 0.060), (0, -0.110, -0.110), bevel=0.0006)
    mag_segments.append(floor)
    # 弹匣脊背的加强筋
    rib = add_box("_mag_rib", (0.005, 0.080, 0.008), (0.019, -0.040, -0.085), bevel=0.0004)
    mag_segments.append(rib)
    mag = join_parts("MagShell", mag_segments)
    mag.name = "mag"

    # ================= 可动件:右侧大拉机柄 =================
    ch_shaft = add_box("bolt", (0.008, 0.012, 0.055), (0.034, 0.034, -0.020), bevel=0.0005)
    ch_head = add_box("_ch_head", (0.010, 0.020, 0.012), (0.044, 0.034, -0.020), bevel=0.0004)
    join_parts("bolt", [ch_shaft, ch_head])

    # ================= 材质分配 =================
    rules = [
        # 木材:护木、握把、枪托
        ("UpperHandguard", "wood"), ("LowerHandguard", "wood"),
        ("PistolGrip", "wood"), ("GripCap", "wood"),
        ("StockBody", "wood"), ("StockPlate", "wood"), ("StockFerrule", "wood"),
        # 金属:机匣、防尘盖、保险、刺刀座、销钉
        ("UpperReceiver", "metal"), ("DustCover", "metal"),
        ("CoverHandle", "metal"), ("SafetyLever", "metal"),
        ("FrontTrunnion", "metal"), ("BayonetLug", "metal"),
        ("HandguardBand", "metal"), ("HandguardRearBand", "metal"),
        ("Trigger", "dark"), ("TriggerGuard", "dark"),
        # 暗色:枪管、准星座、护圈
        ("Barrel", "dark"), ("FrontSight", "dark"),
        ("RearSight", "dark"),
        # 弹匣体:钢(深色,磷化)
        ("MagShell", "dark"), ("mag", "dark"),
    ]
    apply_materials(rules, default="dark")

    return mag


if __name__ == "__main__":
    m = build()
    objs, verts, tris = stats()
    print("AK47 objects=%d verts=%d tris=%d" % (objs, verts, tris))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/ak.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
