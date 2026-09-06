"""
M4A1 高精度模型 —— 标杆件

坐标一律用 Godot 语义(枪口 -Z, 上 +Y),gunforge.g2b 内部转成 Blender 坐标,
这样重建后的模型与现有 HAND_ANCHORS / MUZZLE_Z / MOD_ANCHORS 保持对齐。

可动件命名用小写语义名(mag / bolt),Godot 侧加载 GLB 后按名字绑定 set_meta,
换弹控制器就能驱动它们。静态件用描述性名字。

运行:
    blender --background --python build_m4.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gunforge import *

RY = 0.024          # 枪管轴线高度
RAIL_Y = 0.086      # 皮卡汀尼导轨安装面
SIGHT_Y = 0.108     # 机械瞄具视轴(不可遮挡)


def build():
    reset()

    # ================= 上机匣 =================
    upper = add_box("UpperReceiver", (0.048, 0.032, 0.28), (0, 0.047, -0.06), bevel=0.0012)

    # 抛壳窗:右侧真实挖穿(不是贴一块深色板)
    port = add_box("_cut_port", (0.030, 0.021, 0.058), (0.026, 0.050, -0.070))
    cut(upper, port)

    # 抛壳偏转块(抛壳窗后方的凸起)
    add_box("BrassDeflector", (0.006, 0.014, 0.020), (0.026, 0.056, -0.022), bevel=0.0006)

    # 辅助推机柄座(forward assist)
    add_cyl("ForwardAssistBody", 0.0085, 0.022, (0.028, 0.056, 0.030), axis="x", seg=16, bevel=0.0005)
    add_cyl("ForwardAssistBtn", 0.0045, 0.010, (0.040, 0.056, 0.030), axis="x", seg=12, bevel=0.0004)

    # 顶部平顶导轨(真齿距)
    # 贴合垫块:机匣顶 0.063 到齿底 0.0786 的落差用实心填满,导轨坐实不悬空
    add_picatinny("TopRail", 0.195, (0, RAIL_Y, -0.062), mount_h=0.0156)

    # ================= 下机匣 =================
    lower = add_box("LowerReceiver", (0.052, 0.052, 0.24), (0, -0.005, -0.02), bevel=0.0012)

    # 弹匣井:从下机匣底部真实挖空
    well = add_box("_cut_well", (0.038, 0.085, 0.072), (0, -0.030, -0.088))
    cut(lower, well)

    # 弹匣井前缘外扩(实际枪上是喇叭口)
    add_box("MagwellFlare", (0.050, 0.020, 0.030), (0, -0.030, -0.126), bevel=0.0010)

    # 扳机护圈:三段拼一个 U 形(护圈内要能看见手指)
    add_box("TriggerGuardF", (0.008, 0.024, 0.010), (0, -0.040, -0.108), bevel=0.0006)
    add_box("TriggerGuardB", (0.008, 0.024, 0.010), (0, -0.038, -0.028), bevel=0.0006)
    add_box("TriggerGuardBtm", (0.008, 0.008, 0.082), (0, -0.052, -0.068), bevel=0.0006)

    # 扳机
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.038, -0.070), bevel=0.0005)

    # 保险拨片(右侧)
    add_box("SafetyLever", (0.014, 0.007, 0.026), (0.029, -0.008, -0.030), bevel=0.0006)

    # 弹匣释放钮
    add_cyl("MagRelease", 0.007, 0.010, (0.029, -0.022, -0.116), axis="x", seg=12, bevel=0.0004)

    # 空仓挂机杆
    add_box("BoltCatch", (0.013, 0.006, 0.018), (0.029, -0.014, -0.092), bevel=0.0005)

    # 前后机匣连接销
    add_cyl("PivotPin", 0.0045, 0.062, (0, -0.012, -0.128), axis="x", seg=12)
    add_cyl("TakedownPin", 0.0045, 0.062, (0, -0.012, 0.012), axis="x", seg=12)

    # ================= 枪管 / 导气 =================
    # 枪管螺母(六角 —— 真枪上是六角,不是圆柱)
    add_cyl("BarrelNut", 0.021, 0.022, (0, RY, -0.148), axis="z", seg=6, bevel=0.0006)

    # M4 圆形护木(双层 + 纵向散热肋)
    add_cyl("HandguardOuter", 0.0245, 0.235, (0, RY, -0.280), axis="z", seg=20, bevel=0.0008)
    for i in range(6):
        zc = -0.170 - i * 0.038
        add_cyl("HandguardRib%d" % i, 0.0252, 0.008, (0, RY, zc), axis="z", seg=20, bevel=0.0003)

    # 枪管
    add_cyl("Barrel", 0.0110, 0.600, (0, RY, -0.470), axis="z", seg=16, bevel=0.0006)
    add_cyl("BarrelStep", 0.0135, 0.030, (0, RY, -0.196), axis="z", seg=16)

    # 导气管(枪管上方,从导气座通到机匣)
    add_cyl("GasTube", 0.0055, 0.300, (0, RY + 0.026, -0.300), axis="z", seg=10)

    # ================= A2 三角准星座 =================
    add_box("FrontSightBase", (0.026, 0.046, 0.034), (0, 0.038, -0.400), bevel=0.0008)
    add_cyl("GasBlockCollar", 0.0135, 0.020, (0, RY, -0.408), axis="z", seg=14, bevel=0.0005)
    # 准星护翼(左右两片,中间夹准星柱)
    add_box("SightWingL", (0.005, 0.026, 0.022), (-0.013, 0.090, -0.400), bevel=0.0005)
    add_box("SightWingR", (0.005, 0.026, 0.022), (0.013, 0.090, -0.400), bevel=0.0005)
    add_cyl("FrontSightPost", 0.0032, 0.020, (0, 0.086, -0.400), axis="y", seg=8)

    # ================= A2 鸟笼消焰器 =================
    flash = add_cyl("FlashHider", 0.0148, 0.050, (0, RY, -0.775), axis="z", seg=20, bevel=0.0006)
    # 三道纵向开槽(底部不切 —— A2 的设计就是底部封闭防扬尘)
    import math as _m
    for i in range(3):
        ang = _m.pi * 0.5 + i * (2 * _m.pi / 3.0)
        cx = _m.cos(ang) * 0.0135
        cy = RY + _m.sin(ang) * 0.0135
        slot = add_box("_cut_slot%d" % i, (0.006, 0.006, 0.030), (cx, cy, -0.782))
        cut(flash, slot)
    # 前端实心环 + 内芯
    add_cyl("FlashHiderTip", 0.0138, 0.010, (0, RY, -0.800), axis="z", seg=20, bevel=0.0004)

    # ================= 枪托(四段伸缩) =================
    add_cyl("BufferTube", 0.0125, 0.115, (0, 0.032, 0.175), axis="z", seg=16, bevel=0.0006)
    stock = add_box("StockBody", (0.044, 0.086, 0.130), (0, 0.012, 0.205), bevel=0.0015)
    # 托底板
    add_box("StockPlate", (0.048, 0.096, 0.018), (0, 0.012, 0.272), bevel=0.0010)
    # 贴腮板
    add_box("CheekRest", (0.032, 0.030, 0.090), (0, 0.052, 0.205), bevel=0.0012)
    # 伸缩调节孔
    for i in range(4):
        add_box("StockHole%d" % i, (0.009, 0.009, 0.009), (0, -0.020, 0.150 + i * 0.032), bevel=0.0003)
    # 托体两侧的减轻孔
    add_box("StockSlotL", (0.006, 0.020, 0.055), (-0.021, 0.012, 0.210), bevel=0.0006)
    add_box("StockSlotR", (0.006, 0.020, 0.055), (0.021, 0.012, 0.210), bevel=0.0006)

    # ================= A2 握把 =================
    grip = add_box("Grip", (0.033, 0.098, 0.046), (0, -0.052, 0.042), bevel=0.0012)
    # 握把防滑纹(横向凸棱)
    for i in range(5):
        add_box("GripRib%d" % i, (0.0345, 0.005, 0.006), (0, -0.030 - i * 0.014, 0.060), bevel=0.0003)
    # 握把底部
    add_box("GripCap", (0.035, 0.008, 0.048), (0, -0.100, 0.046), bevel=0.0006)

    # ================= 机械瞄具(翻转照门) =================
    # 照门整组必须归到 StockIrons:装备红点/全息镜时由 gun.gd 按名字整组隐藏,
    # 否则镜筒后面还立着原厂照门,直接穿模。前准星留在枪管的导气座上不参与隐藏。
    _rs = [
        add_box("RearSightBase", (0.030, 0.008, 0.034), (0, RAIL_Y + 0.004, 0.052), bevel=0.0006),
        add_box("RearSightLeaf", (0.026, 0.016, 0.008), (0, RAIL_Y + 0.012, 0.052), bevel=0.0005),
        # 调节钮:风偏在右侧、高低在照门座下方,两者都不能进入视轴
        add_cyl("RearSightWindage", 0.0055, 0.012, (0.014, RAIL_Y + 0.010, 0.052),
                axis="x", seg=12, bevel=0.0003),
        add_cyl("RearSightElev", 0.0050, 0.008, (0, RAIL_Y + 0.008, 0.052),
                axis="y", seg=12, bevel=0.0003),
        # 觇孔环:孔洞沿枪管方向,ADS 时视线从环中穿过
        add_torus("RearAperture", 0.0055, 0.0012, (0, SIGHT_Y, 0.048),
                  seg_major=16, seg_minor=8),
    ]
    join_parts("StockIrons", _rs)

    # ================= 可动件:拉机柄 =================
    # T 型拉机柄,换弹时空仓动作要拉它
    ch = add_box("bolt", (0.008, 0.010, 0.030), (0.0, 0.062, 0.062), bevel=0.0005)
    ch_l = add_box("_ch_l", (0.020, 0.007, 0.008), (-0.012, 0.062, 0.076), bevel=0.0004)
    ch_r = add_box("_ch_r", (0.020, 0.007, 0.008), (0.012, 0.062, 0.076), bevel=0.0004)
    join_parts("bolt", [ch, ch_l, ch_r])

    # ================= 可动件:STANAG 弹匣 =================
    # 弹匣整体作为一个节点运动:换弹时它要脱离枪身、被抽出、插回
    mag_body = add_box("MagBody", (0.036, 0.128, 0.060), (0, -0.086, -0.088), bevel=0.0010)
    # 弹匣底板
    mag_floor = add_box("_mag_floor", (0.039, 0.010, 0.064), (0, -0.153, -0.084), bevel=0.0006)
    # 弹匣口部加强(前缘)
    mag_lip = add_box("_mag_lip", (0.034, 0.012, 0.058), (0, -0.026, -0.088), bevel=0.0006)
    # 侧面观察孔(真枪上的余弹观察孔)
    holes = []
    for i in range(3):
        h = add_box("_mag_hole%d" % i, (0.006, 0.006, 0.006),
                    (0.0175, -0.070 - i * 0.022, -0.062))
        holes.append(h)
    mag = join_parts("MagShell", [mag_body, mag_lip, mag_floor])
    for h in holes:
        cut(mag, h)
    mag.name = "mag"

    # 弹匣内的可见托弹板(从顶部能瞥见,增加细节可信度)
    follower = add_box("_mag_follower", (0.032, 0.008, 0.050), (0, -0.032, -0.088), bevel=0.0004)
    follower.name = "MagFollower"
    follower.parent = mag
    follower.matrix_parent_inverse = mag.matrix_world.inverted()

    # ---- 材质:名字与 Godot WeaponModels.MAT() 对齐 ----
    mat_rules = [
        # 聚合物件(护木 / 握把 / 枪托)
        ("Handguard", "poly"), ("Grip", "poly"), ("Stock", "poly"),
        ("CheekRest", "poly"),
        # 深色磷化钢件(枪管 / 消焰器 / 导轨 / 弹匣 / 枪机)
        ("Barrel", "dark"), ("FlashHider", "dark"), ("TopRail", "dark"),
        ("FrontSight", "dark"), ("Gas", "dark"), ("Rear", "dark"),
        ("mag", "dark"), ("MagShell", "dark"), ("MagFollower", "dark"),
        ("bolt", "dark"), ("Trigger", "dark"), ("Safety", "dark"),
        ("MagRelease", "dark"), ("BoltCatch", "dark"),
        ("PivotPin", "metal"), ("TakedownPin", "metal"),
        # 机匣为阳极氧化铝
        ("Upper", "metal"), ("Lower", "metal"), ("Magwell", "metal"),
        ("BufferTube", "metal"), ("BarrelNut", "metal"),
    ]
    apply_materials(mat_rules, default="dark")

    return mag


if __name__ == "__main__":
    m = build()
    objs, verts, tris = stats()
    print("M4A1 objects=%d verts=%d tris=%d" % (objs, verts, tris))
    out = "E:/工作目录2/zero/steel_frontline_godot/models/weapons/m4.glb"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    export_glb(out)
    print("EXPORT", out)
