"""
其余 5 张地图 3A 级建筑批次(tools/blender/build_scene_batch.py)
产出 models/props/{id}.glb —— 单一合并网格、多材质槽,Godot 侧按材质名重贴 PBR。

用户诉求:"沙漠地图也要加一些更多的真实可信的建模数高的建筑,其他地图也是同理"。
本批次按各图主题建高面数、可辨识度强的地标级建筑(与城市批次同一套 3A 准则:
分层构造 + 倒角 + 细节部件 + 材质槽分离)。

模型清单:
  沙漠(desert):
    desert_oilrig     抽油机(桁架摆臂 + 平衡重 + 底座 + 电机 + 皮带护罩)
    desert_tank       储油罐(罐体 + 加强环 + 锥顶 + 螺旋梯 + 阀门组 + 围堰)
    desert_pumpstation 泵站(泵房 + 管廊 + 阀组 + 仪表 + 高架罐)
    desert_mosque     清真寺(穹顶 + 宣礼塔 + 拱廊 + 庭院 + 新月)
    desert_market     集市(摊位棚 ×6 + 货箱 + 遮阳布 + 秤台)
    desert_adobe      土坯房群(平顶 + 拱门 + 女儿墙 + 外露木梁 + 院墙)
    desert_watertower 水塔(4 支腿 + 罐体 + 爬梯 + 检修平台 + 锥顶)
    desert_comms      通讯塔(格构桁架 + 抛物面天线 ×3 + 航空灯 + 机房)
    desert_factory    炼厂(分馏塔 ×2 + 管廊 + 烟囱 + 钢框架 + 梯子)
    desert_bunker     沙漠地堡(混凝土掩体 + 沙袋 + 射击口 + 铁门)

  丛林/雪山/暮港/BR:
    jungle_temple     丛林神庙遗迹(阶梯金字塔 + 石柱 + 浮雕墙 + 藤蔓)
    jungle_stilt      高脚木屋(支柱 + 草顶 + 梯 + 平台 + 晾架)
    snow_chalet       雪山木屋(坡顶积雪 + 木墙 + 烟囱 + 柴堆 + 窗灯)
    snow_station      科考站(圆顶 + 支腿 + 天线阵 + 太阳能板 + 连廊)
    harbor_crane      龙门吊(门架 + 吊臂 + 驾驶室 + 吊具 + 轨道)
    harbor_ship       货轮(船体 + 舰桥 + 集装箱堆 + 桅杆 + 舷梯 + 缆桩)
    harbor_shed       码头仓库(波纹钢 + 卷帘门 + 装卸平台 + 雨棚)
    br_farmhouse      农舍(主房 + 谷仓 + 筒仓 ×2 + 风车 + 围栏)
    br_church         乡村教堂(尖顶钟楼 + 中殿 + 墓地 + 围墙)

坐标:根在地面 y=0,正面朝 -Z,单位米。
用法: blender --background --python build_scene_batch.py [-- desert_oilrig desert_tank ...]
"""
import sys, os, math, random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/props"
random.seed(20260907)


# ============================================================ 基础工具
def _m(ob, name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def _finish(name, parts, mat_rules):
    by_name = {}
    for ob in parts:
        by_name[ob.name] = ob
    for key, mname in mat_rules:
        for ob_name, ob in by_name.items():
            if ob_name.startswith(key):
                _m(ob, mname)
    return join_parts(name, parts)


def _box(name, size, pos, bev=0.02, rot=None):
    return add_box(name, size, pos, bevel=bev, rot_g=rot)


def _ladder(prefix, x, y0, y1, z, w=0.55, n=None):
    """爬梯(两侧立杆 + 横档)"""
    n = n or max(4, int((y1 - y0) / 0.34))
    parts = []
    for s in (-1, 1):
        parts.append(_box("%s_Rail%d" % (prefix, s), (0.05, y1 - y0, 0.05),
                          (x + s * w * 0.5, (y0 + y1) * 0.5, z), bev=0.008))
    for i in range(n):
        parts.append(_box("%s_Rung%d" % (prefix, i), (w, 0.04, 0.04),
                          (x, y0 + (y1 - y0) * (i + 0.5) / n, z), bev=0.006))
    return parts


def _pipe_run(prefix, pts, r=0.13):
    """沿折线铺管道(简易:相邻点之间放一段圆柱)"""
    parts = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        mx, my, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5
        dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        ln = math.sqrt(dx * dx + dy * dy + dz * dz)
        if ln < 1e-6:
            continue
        # 用 X 轴圆柱 + 两角旋转近似任意朝向
        yaw = math.atan2(-dz, dx)
        pit = math.asin(max(-1.0, min(1.0, dy / ln)))
        ob = add_cyl("%s_P%d" % (prefix, i), r, ln, (mx, my, mz), axis="x", seg=10)
        ob.rotation_euler = rot_g2b((0, yaw, pit))
        parts.append(ob)
    return parts


# ============================================================ 抽油机(磕头机)
def build_desert_oilrig():
    reset()
    parts = []
    # 混凝土基座
    parts.append(_box("_Base", (4.2, 2.15, 2.6), (0, -0.525, 0), bev=0.03))
    parts.append(_box("_Base2", (3.2, 0.35, 1.9), (0, 0.72, 0), bev=0.02))
    # 支架(A 形桁架:4 腿 + 横撑 + 斜撑)
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Leg%d%d" % (sx, sz), (0.22, 5.2, 0.22),
                              (sx * 0.85, 3.2, sz * 0.55 + 0.3), bev=0.02,
                              rot=(sz * 0.10, 0, -sx * 0.10)))
    for i in range(3):
        y = 1.6 + i * 1.6
        shrink = 1.0 - i * 0.13
        for ax in ("x", "z"):
            for s in (-1, 1):
                if ax == "x":
                    parts.append(_box("_Brace%d_%s%d" % (i, ax, s), (1.7 * shrink, 0.10, 0.10),
                                      (0, y, s * 0.55 * shrink + 0.3), bev=0.008))
                else:
                    parts.append(_box("_Brace%d_%s%d" % (i, ax, s), (0.10, 0.10, 1.1 * shrink),
                                      (s * 0.85 * shrink, y, 0.3), bev=0.008))
    # 游梁(横梁)—— 前端(驴头)朝 -Z,后端(平衡重)朝 +Z
    parts.append(_box("_Beam", (0.55, 0.42, 6.4), (0, 5.75, 0.2), bev=0.025, rot=(-0.16, 0, 0)))
    # 驴头(前端弧形:多段渐收 + 吊绳)
    for i in range(5):
        t = i / 4.0
        zc = -2.9 - t * 0.55
        yc = 6.35 - t * 0.95
        parts.append(_box("_Head%d" % i, (0.52 - t * 0.10, 0.30, 0.50),
                          (0, yc, zc), bev=0.015, rot=(0.30 + t * 0.22, 0, 0)))
    # 悬绳器 + 抽油杆
    parts.append(_box("_Hanger", (0.42, 0.14, 0.42), (0, 5.42, -3.42), bev=0.012))
    parts.append(add_cyl("_Rod", 0.05, 4.4, (0, 3.2, -3.42), axis="y", seg=8))
    # 井口装置(采油树:阀组 + 法兰 + 出油管)
    parts.append(add_cyl("_WellHead", 0.34, 1.5, (0, 1.30, -3.42), axis="y", seg=14, bevel=0.02))
    for i in range(3):
        parts.append(add_cyl("_Flange%d" % i, 0.42, 0.10, (0, 0.95 + i * 0.42, -3.42),
                             axis="y", seg=14, bevel=0.012))
    for s in (-1, 1):
        parts.append(_box("_Valve%d" % s, (0.26, 0.30, 0.26), (s * 0.48, 1.55, -3.42), bev=0.012))
        parts.append(add_cyl("_Hand%d" % s, 0.16, 0.05, (s * 0.62, 1.72, -3.42), axis="x", seg=10))
    parts += _pipe_run("_Out", [(0.0, 1.9, -3.42), (2.2, 1.9, -3.42), (2.2, 0.9, -3.42), (4.6, 0.9, -3.42)], r=0.11)
    # 平衡重(后端配重块 ×3)
    for i in range(3):
        parts.append(_box("_Weight%d" % i, (0.95, 0.62, 0.28), (0, 5.05 - i * 0.30, 3.0 + i * 0.02), bev=0.02))
    # 支架轴承座 + 电机 + 皮带护罩
    parts.append(_box("_Bearing", (1.0, 0.55, 0.75), (0, 5.55, 0.2), bev=0.025))
    parts.append(add_cyl("_Motor", 0.42, 1.30, (1.35, 1.35, 1.7), axis="x", seg=14, bevel=0.02))
    parts.append(_box("_MotorB", (1.1, 0.22, 0.95), (1.35, 0.72, 1.7), bev=0.015))
    parts.append(_box("_BeltGuard", (0.30, 1.5, 1.05), (1.32, 2.55, 1.35), bev=0.02, rot=(0.16, 0, 0)))
    # 护栏(检修平台)
    parts.append(_box("_Plat", (2.6, 0.12, 1.2), (0, 2.0, -1.6), bev=0.012))
    parts.append(_box("_PlatR", (2.6, 0.07, 0.07), (0, 3.05, -2.15), bev=0.008))
    for s in (-1, 1):
        parts.append(_box("_PlatP%d" % s, (0.07, 1.05, 0.07), (s * 1.25, 2.55, -2.15), bev=0.008))
    rules = [
        ("_Base", "concrete"), ("_Leg", "metal"), ("_Brace", "metal"),
        ("_Beam", "metal"), ("_Head", "metal"), ("_Hanger", "metal"), ("_Rod", "chrome"),
        ("_WellHead", "metal"), ("_Flange", "metal"), ("_Valve", "metal"),
        ("_Hand", "sign"), ("_Out_P", "metal"), ("_Out", "metal"),
        ("_Weight", "metal"), ("_Bearing", "metal"), ("_Motor", "metal"),
        ("_MotorB", "metal"), ("_BeltGuard", "metal"),
        ("_Plat", "metal"), ("_PlatR", "metal"), ("_PlatP", "metal"),
    ]
    return _finish("Prop_desert_oilrig", parts, rules)


# ============================================================ 储油罐
def build_desert_tank():
    reset()
    parts = []
    R, H = 5.0, 7.5
    # 围堰(防火堤)
    parts.append(add_cyl("_Bund", R + 1.8, 2.7, (0, -0.25, 0), axis="y", seg=28, bevel=0.04))
    parts.append(add_cyl("_BundIn", R + 1.3, 1.2, (0, 0.60, 0), axis="y", seg=28))
    # 罐基础
    parts.append(add_cyl("_Found", R + 0.35, 2.15, (0, 0.55, 0), axis="y", seg=28, bevel=0.03))
    # 罐体(三段,微收分)
    parts.append(add_cyl("_Shell0", R, 2.6, (0, 2.90, 0), axis="y", seg=32, bevel=0.04))
    parts.append(add_cyl("_Shell1", R * 0.985, 2.6, (0, 5.45, 0), axis="y", seg=32, bevel=0.04))
    parts.append(add_cyl("_Shell2", R * 0.965, 2.1, (0, 7.80, 0), axis="y", seg=32, bevel=0.04))
    # 加强环(每 1.8m 一道)
    for i in range(4):
        parts.append(add_cyl("_Ring%d" % i, R * (1.005 - i * 0.010), 0.16,
                             (0, 2.0 + i * 1.85, 0), axis="y", seg=32, bevel=0.015))
    # 锥顶 + 顶圈 + 中心透气阀
    parts.append(add_cyl("_Top", R * 0.97, 1.5, (0, 9.60, 0), axis="y", seg=32, taper=0.16, bevel=0.04))
    parts.append(add_cyl("_TopRail", R * 0.90, 0.12, (0, 10.28, 0), axis="y", seg=32, bevel=0.012))
    parts.append(add_cyl("_Vent", 0.42, 0.85, (0, 10.65, 0), axis="y", seg=12, bevel=0.02))
    parts.append(add_cyl("_VentCap", 0.60, 0.16, (0, 11.10, 0), axis="y", seg=12, bevel=0.015))
    # 螺旋梯(绕罐体外侧)
    n_st = 26
    for i in range(n_st):
        t = i / float(n_st)
        a = t * math.tau * 1.05
        rr = R + 0.42
        y = 1.7 + t * (H + 1.0)
        parts.append(_box("_Stair%d" % i, (0.85, 0.07, 0.42),
                          (math.sin(a) * rr, y, math.cos(a) * rr), bev=0.008, rot=(0, -a, 0)))
        if i % 3 == 0:
            parts.append(_box("_StairP%d" % i, (0.06, 0.95, 0.06),
                              (math.sin(a) * (rr + 0.32), y + 0.50, math.cos(a) * (rr + 0.32)), bev=0.006))
            parts.append(_box("_StairH%d" % i, (0.05, 0.05, 0.42),
                              (math.sin(a) * (rr + 0.32), y + 1.00, math.cos(a) * (rr + 0.32)), bev=0.006))
    # 顶部检修平台 + 栏杆
    parts.append(_box("_TopPlat", (2.4, 0.12, 1.6), (R * 0.55, 10.35, 0.0), bev=0.012))
    parts.append(_box("_TopPlatR", (2.4, 0.07, 0.07), (R * 0.55, 11.35, -0.75), bev=0.008))
    for s in (-1, 1):
        parts.append(_box("_TopPlatP%d" % s, (0.07, 1.0, 0.07), (R * 0.55 + s * 1.15, 10.85, -0.75), bev=0.006))
    # 阀门组 + 出油管 + 人孔
    parts.append(add_cyl("_Manway", 0.62, 0.30, (R * 0.8, 1.9, 1.4), axis="x", seg=14, bevel=0.02))
    parts.append(_box("_ValveBlk", (1.3, 0.9, 0.85), (R + 1.0, 1.55, 2.6), bev=0.025))
    for i in range(3):
        parts.append(add_cyl("_VW%d" % i, 0.26, 0.06, (R + 1.0 + (i - 1) * 0.42, 2.10, 2.6),
                             axis="y", seg=12))
    parts += _pipe_run("_Out", [(R + 1.0, 1.55, 3.05), (R + 3.2, 1.55, 3.05), (R + 3.2, 0.95, 4.4)], r=0.16)
    # 罐号牌 + 接地
    parts.append(_box("_Sign", (2.2, 1.1, 0.10), (0, 4.6, -R - 0.10), bev=0.015))
    parts.append(_box("_Ground", (0.10, 1.6, 0.10), (-R - 0.5, 1.4, 0.6), bev=0.008))
    rules = [
        ("_Bund", "concrete"), ("_BundIn", "concrete"), ("_Found", "concrete"),
        ("_Shell", "tank"), ("_Ring", "metal"), ("_Top", "tank"), ("_TopRail", "metal"),
        ("_Vent", "metal"), ("_VentCap", "metal"),
        ("_Stair", "metal"), ("_TopPlat", "metal"), ("_TopPlatR", "metal"), ("_TopPlatP", "metal"),
        ("_Manway", "metal"), ("_ValveBlk", "metal"), ("_VW", "sign"),
        ("_Out_P", "metal"), ("_Out", "metal"), ("_Sign", "sign"), ("_Ground", "metal"),
    ]
    return _finish("Prop_desert_tank", parts, rules)


# ============================================================ 泵站
def build_desert_pumpstation():
    reset()
    parts = []
    # 泵房(主建筑)
    W, D, H = 9.0, 6.5, 4.4
    parts.append(_box("_Slab", (W + 1.4, 2.1, D + 1.4), (0, -0.55, 0), bev=0.03))
    parts.append(_box("_House", (W, H, D), (0, 0.5 + H * 0.5, 0), bev=0.035))
    # 波纹壁板
    for i in range(9):
        px = (i / 8.0 - 0.5) * W
        parts.append(_box("_RibF%d" % i, (0.14, H, 0.22), (px, 0.5 + H * 0.5, -D * 0.5 - 0.09), bev=0.010))
    # 屋顶(双坡 + 脊 + 出檐)
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (W * 0.56 + 0.9, 0.24, D + 1.4),
                          (s * (W * 0.24), 0.5 + H + 0.85, 0), bev=0.028, rot=(0, 0, -s * 0.26)))
    parts.append(_box("_Ridge", (0.45, 0.40, D + 1.4), (0, 0.5 + H + 1.60, 0), bev=0.025))
    # 卷帘门 + 门箱 + 便门
    parts.append(_box("_DoorF", (4.2, 3.6, 0.24), (0, 2.30, -D * 0.5 + 0.06), bev=0.02))
    parts.append(_box("_Door", (3.8, 3.3, 0.14), (0, 2.10, -D * 0.5 + 0.01), bev=0.018))
    for j in range(6):
        parts.append(_box("_Slat%d" % j, (3.7, 0.10, 0.18), (0, 0.85 + j * 0.52, -D * 0.5 + 0.02), bev=0.008))
    parts.append(_box("_DoorBox", (4.5, 0.50, 0.55), (0, 4.30, -D * 0.5 - 0.18), bev=0.02))
    parts.append(_box("_SideDoor", (1.0, 2.2, 0.16), (W * 0.5 - 1.6, 1.60, -D * 0.5 + 0.05), bev=0.018))
    # 通风百叶 + 排风口
    parts.append(_box("_Vent", (1.6, 1.0, 0.12), (-W * 0.5 + 2.0, 3.4, -D * 0.5 + 0.04), bev=0.012))
    for j in range(4):
        parts.append(_box("_Louver%d" % j, (1.5, 0.07, 0.16), (-W * 0.5 + 2.0, 3.05 + j * 0.24, -D * 0.5 + 0.06),
                          bev=0.006, rot=(0.30, 0, 0)))
    parts.append(add_cyl("_Stack", 0.28, 1.6, (W * 0.5 - 1.2, 0.5 + H + 1.9, 1.4), axis="y", seg=12, bevel=0.02))
    # 管廊(进出泵房的管道 + 支架)
    for i in range(4):
        zc = -D * 0.5 - 2.2 - i * 0.55
        parts.append(add_cyl("_Manifold%d" % i, 0.17, W + 2.0, (0, 0.75 + i * 0.32, zc),
                             axis="x", seg=12, bevel=0.012))
    for k in range(3):
        px = -W * 0.5 + 1.0 + k * (W * 0.5)
        parts.append(_box("_Support%d" % k, (0.22, 1.9, 0.22), (px, 0.95, -D * 0.5 - 2.6), bev=0.012))
        parts.append(_box("_SupportT%d" % k, (0.30, 0.16, 2.6), (px, 1.88, -D * 0.5 - 2.6), bev=0.010))
    # 阀组(手轮 ×4)
    for i in range(4):
        zc = -D * 0.5 - 2.2 - i * 0.55
        for s in (-1, 1):
            parts.append(_box("_Valve%d%d" % (i, s), (0.34, 0.40, 0.34),
                              (s * 3.2, 0.75 + i * 0.32, zc), bev=0.015))
            parts.append(add_cyl("_Wheel%d%d" % (i, s), 0.24, 0.05, (s * 3.2, 1.05 + i * 0.32, zc),
                                 axis="y", seg=12, bevel=0.006))
    # 高架小罐 + 梯 + 平台
    parts.append(add_cyl("_SmallTank", 1.15, 2.6, (W * 0.5 + 3.2, 3.0, 1.5), axis="y", seg=20, bevel=0.03))
    for k in range(4):
        a = k * math.tau / 4.0 + 0.4
        parts.append(_box("_TankLeg%d" % k, (0.16, 1.75, 0.16),
                          (W * 0.5 + 3.2 + math.sin(a) * 0.85, 0.88, 1.5 + math.cos(a) * 0.85), bev=0.012))
    parts += _ladder("_TL", W * 0.5 + 2.0, 0.0, 4.3, 1.5)
    # 变压器 + 电杆
    parts.append(_box("_Trans", (1.2, 1.5, 1.0), (-W * 0.5 - 2.4, 0.75, 2.4), bev=0.025))
    parts.append(add_cyl("_Pole", 0.14, 7.0, (-W * 0.5 - 3.2, 3.5, 3.6), axis="y", seg=10, bevel=0.015))
    parts.append(_box("_CrossArm", (2.2, 0.10, 0.10), (-W * 0.5 - 3.2, 6.6, 3.6), bev=0.010))
    rules = [
        ("_Slab", "concrete"), ("_House", "wall"), ("_Rib", "metal"),
        ("_Roof", "roof"), ("_Ridge", "roof"),
        ("_DoorF", "trim"), ("_Door", "metal"), ("_Slat", "metal"), ("_DoorBox", "metal"),
        ("_SideDoor", "trim"), ("_Vent", "metal"), ("_Louver", "metal"), ("_Stack", "metal"),
        ("_Manifold", "pipe"), ("_Support", "metal"), ("_SupportT", "metal"),
        ("_Valve", "pipe"), ("_Wheel", "sign"),
        ("_SmallTank", "tank"), ("_TankLeg", "metal"), ("_TL_Rail", "metal"), ("_TL_Rung", "metal"),
        ("_TL", "metal"), ("_Trans", "metal"), ("_Pole", "wood"), ("_CrossArm", "wood"),
    ]
    return _finish("Prop_desert_pumpstation", parts, rules)


# ============================================================ 清真寺
def build_desert_mosque():
    reset()
    parts = []
    # 台基
    parts.append(_box("_Plinth", (17.0, 2.2, 15.0), (0, -0.10, 0), bev=0.03))
    parts.append(_box("_Plinth2", (16.0, 0.35, 14.0), (0, 0.85, 0), bev=0.025))
    # 主殿(方形主体 + 中央穹顶)
    MW, MD, MH = 11.0, 10.0, 6.0
    parts.append(_box("_Hall", (MW, MH, MD), (0, 1.0 + MH * 0.5, 0), bev=0.035))
    # 四面拱门(凹龛 + 拱形顶)
    for (ax, s) in (("z", -1), ("z", 1), ("x", -1), ("x", 1)):
        if ax == "z":
            parts.append(_box("_Portal%d" % s, (3.4, 4.2, 0.55), (0, 3.1, s * (MD * 0.5 + 0.20)), bev=0.025))
            parts.append(add_cyl("_Arch%d" % s, 1.7, 0.85, (0, 5.4, s * (MD * 0.5 + 0.20)),
                                 axis="x", seg=18, bevel=0.02))
        else:
            parts.append(_box("_PSide%d" % s, (0.55, 4.2, 3.4), (s * (MW * 0.5 + 0.20), 3.1, 0), bev=0.025))
            parts.append(add_cyl("_ASide%d" % s, 1.7, 0.85, (s * (MW * 0.5 + 0.20), 5.4, 0),
                                 axis="z", seg=18, bevel=0.02))
    # 中央穹顶(鼓座 + 半球 + 顶尖新月)
    parts.append(add_cyl("_Drum", 4.4, 1.7, (0, 1.0 + MH + 0.85, 0), axis="y", seg=28, bevel=0.03))
    for i in range(8):
        a = i * math.tau / 8.0
        parts.append(_box("_DrumW%d" % i, (0.55, 1.1, 0.55),
                          (math.sin(a) * 4.4, 1.0 + MH + 0.85, math.cos(a) * 4.4), bev=0.015))
    # 穹顶(多层渐收环,近似半球)
    dome_y = 1.0 + MH + 1.70
    for i in range(9):
        t = i / 8.0
        r = 4.3 * math.cos(t * math.pi * 0.5)
        y = dome_y + 3.3 * math.sin(t * math.pi * 0.5)
        parts.append(add_cyl("_Dome%d" % i, r, 0.52, (0, y, 0), axis="y", seg=28, bevel=0.015))
    parts.append(add_cyl("_Finial", 0.16, 1.5, (0, dome_y + 3.5, 0), axis="y", seg=10, bevel=0.015))
    parts.append(_box("_Crescent", (0.55, 0.55, 0.06), (0.16, dome_y + 4.35, 0), bev=0.02))
    # 小穹顶 ×4(四角)
    for sx in (-1, 1):
        for sz in (-1, 1):
            bx, bz = sx * (MW * 0.5 - 1.6), sz * (MD * 0.5 - 1.6)
            parts.append(add_cyl("_SDrum%d%d" % (sx, sz), 1.25, 0.8, (bx, 1.0 + MH + 0.40, bz),
                                 axis="y", seg=18, bevel=0.02))
            for i in range(5):
                t = i / 4.0
                parts.append(add_cyl("_SDome%d%d_%d" % (sx, sz, i), 1.22 * math.cos(t * math.pi * 0.5), 0.26,
                                     (bx, 1.0 + MH + 0.80 + 1.05 * math.sin(t * math.pi * 0.5), bz),
                                     axis="y", seg=18, bevel=0.012))
            parts.append(add_cyl("_SFin%d%d" % (sx, sz), 0.09, 0.7, (bx, 1.0 + MH + 2.15, bz),
                                 axis="y", seg=8))
    # 宣礼塔(高细塔 + 挑檐阳台 + 尖顶)
    tx, tz = -MW * 0.5 - 1.6, -MD * 0.5 - 1.6
    parts.append(add_cyl("_Minaret", 1.35, 19.0, (tx, 10.5, tz), axis="y", seg=16, taper=0.80, bevel=0.035))
    for i in range(4):
        parts.append(add_cyl("_MBand%d" % i, 1.42 - i * 0.09, 0.28, (tx, 4.5 + i * 4.2, tz),
                             axis="y", seg=16, bevel=0.02))
    # 挑檐阳台(2 层)
    for k in range(2):
        by = 11.0 + k * 5.0
        parts.append(add_cyl("_Balcony%d" % k, 1.95, 0.30, (tx, by, tz), axis="y", seg=18, bevel=0.025))
        for i in range(10):
            a = i * math.tau / 10.0
            parts.append(_box("_BalP%d_%d" % (k, i), (0.10, 0.95, 0.10),
                              (tx + math.sin(a) * 1.80, by + 0.62, tz + math.cos(a) * 1.80), bev=0.008))
        parts.append(add_cyl("_BalRail%d" % k, 1.85, 0.06, (tx, by + 1.08, tz), axis="y", seg=18))
    parts.append(add_cyl("_MTop", 1.05, 1.4, (tx, 20.4, tz), axis="y", seg=14, bevel=0.025))
    parts.append(add_cyl("_MSpire", 0.72, 3.0, (tx, 22.2, tz), axis="y", seg=12, taper=0.05, bevel=0.02))
    parts.append(_box("_MCrescent", (0.62, 0.62, 0.07), (tx + 0.18, 23.9, tz), bev=0.02))
    # 庭院(拱廊 + 净礼池)
    for i in range(5):
        px = -6.0 + i * 3.0
        parts.append(add_cyl("_Col%d" % i, 0.28, 3.4, (px, 1.70, -MD * 0.5 - 4.2), axis="y", seg=12, bevel=0.015))
        parts.append(_box("_ColCap%d" % i, (0.72, 0.28, 0.72), (px, 3.52, -MD * 0.5 - 4.2), bev=0.015))
    parts.append(_box("_Arcade", (14.0, 0.34, 1.4), (0, 3.85, -MD * 0.5 - 4.2), bev=0.02))
    for i in range(4):
        px = -4.5 + i * 3.0
        parts.append(add_cyl("_ArchS%d" % i, 1.2, 0.30, (px, 3.30, -MD * 0.5 - 4.2), axis="x", seg=14, bevel=0.012))
    parts.append(add_cyl("_Pool", 1.9, 0.42, (0, 0.21, -MD * 0.5 - 8.0), axis="y", seg=20, bevel=0.025))
    parts.append(add_cyl("_PoolW", 1.70, 0.08, (0, 0.41, -MD * 0.5 - 8.0), axis="y", seg=20))
    for i in range(6):
        a = i * math.tau / 6.0
        parts.append(add_cyl("_Spout%d" % i, 0.07, 0.42,
                             (math.sin(a) * 1.9, 0.55, -MD * 0.5 - 8.0 + math.cos(a) * 1.9),
                             axis="y", seg=8))
    rules = [
        ("_Plinth", "sandstone"), ("_Hall", "sandstone"),
        ("_Portal", "sandstone"), ("_Arch", "sandstone"),
        ("_PSide", "sandstone"), ("_ASide", "sandstone"),
        ("_Drum", "sandstone"), ("_DrumW", "sandstone"),
        ("_Dome", "dome"), ("_Finial", "gold"), ("_Crescent", "gold"),
        ("_SDrum", "sandstone"), ("_SDome", "dome"), ("_SFin", "gold"),
        ("_Minaret", "sandstone"), ("_MBand", "sandstone"),
        ("_Balcony", "sandstone"), ("_BalP", "sandstone"), ("_BalRail", "sandstone"),
        ("_MTop", "sandstone"), ("_MSpire", "dome"), ("_MCrescent", "gold"),
        ("_Col", "sandstone"), ("_ColCap", "sandstone"), ("_Arcade", "sandstone"),
        ("_ArchS", "sandstone"), ("_Pool", "sandstone"), ("_PoolW", "water"),
        ("_Spout", "gold"),
    ]
    return _finish("Prop_desert_mosque", parts, rules)


# ============================================================ 集市
def build_desert_market():
    reset()
    parts = []
    # 地面(夯土 + 石板)
    parts.append(_box("_Ground", (22.0, 1.8, 16.0), (0, -0.74, 0), bev=0.02))
    # 摊位 ×6(3 列 ×2 排):棚架 + 4 柱 + 遮阳布 + 台面 + 货箱
    for r in range(2):
        for c in range(3):
            i = r * 3 + c
            bx = -7.0 + c * 7.0
            bz = -3.5 + r * 7.0
            # 4 立柱
            for sx in (-1, 1):
                for sz in (-1, 1):
                    parts.append(add_cyl("_Post%d_%d%d" % (i, sx, sz), 0.07, 2.55,
                                         (bx + sx * 1.6, 1.275, bz + sz * 1.2), axis="y", seg=8, bevel=0.010))
            # 顶框
            parts.append(_box("_FrameF%d" % i, (3.5, 0.09, 0.09), (bx, 2.55, bz - 1.2), bev=0.008))
            parts.append(_box("_FrameB%d" % i, (3.5, 0.09, 0.09), (bx, 2.55, bz + 1.2), bev=0.008))
            parts.append(_box("_FrameL%d" % i, (0.09, 0.09, 2.5), (bx - 1.6, 2.55, bz), bev=0.008))
            parts.append(_box("_FrameR%d" % i, (0.09, 0.09, 2.5), (bx + 1.6, 2.55, bz), bev=0.008))
            # 遮阳布(略下垂的斜板 + 波浪边)
            parts.append(_box("_Canvas%d" % i, (3.8, 0.10, 2.8), (bx, 2.68, bz), bev=0.020,
                              rot=(0.045, 0, 0.03)))
            for k in range(5):
                parts.append(_box("_Scallop%d_%d" % (i, k), (0.60, 0.14, 0.10),
                                  (bx - 1.5 + k * 0.75, 2.60, bz + 1.42), bev=0.012))
            # 台面(木板 + 支腿)
            parts.append(_box("_Table%d" % i, (3.2, 0.10, 1.1), (bx, 0.92, bz - 0.55), bev=0.015))
            for sx in (-1, 1):
                parts.append(_box("_TableL%d_%d" % (i, sx), (0.10, 0.88, 0.10),
                                  (bx + sx * 1.4, 0.44, bz - 0.55), bev=0.008))
            # 货箱 / 麻袋(台面上)
            for k in range(3):
                parts.append(_box("_Crate%d_%d" % (i, k), (0.52, 0.42, 0.44),
                                  (bx - 1.0 + k * 0.95, 1.19, bz - 0.55), bev=0.015))
            parts.append(_box("_Sack%d" % i, (0.55, 0.50, 0.45), (bx + 0.85, 1.22, bz - 0.30), bev=0.08))
            # 秤
            parts.append(_box("_Scale%d" % i, (0.40, 0.16, 0.34), (bx + 1.25, 1.06, bz - 0.80), bev=0.015))
    # 中央通道地毯摊位(地摊 + 卷毯)
    for i in range(3):
        rz = -1.2 + i * 1.6
        parts.append(_box("_Rug%d" % i, (2.4, 0.05, 1.2), (0.4, 0.19, rz), bev=0.015))
        for k in range(4):
            parts.append(_box("_Roll%d_%d" % (i, k), (0.42, 0.30, 0.30),
                              (2.2, 0.31, rz - 0.45 + k * 0.32), bev=0.03))
    # 遮阳帆布(中央大天棚,钢索)
    parts.append(_box("_Shade", (14.0, 0.10, 3.0), (0, 3.4, 0), bev=0.025, rot=(0, 0, 0.04)))
    for i in range(4):
        parts.append(add_cyl("_Cable%d" % i, 0.03, 8.2, (-6.0 + i * 4.0, 3.85, 0), axis="z", seg=6))
    # 水罐摊 + 陶罐
    parts.append(_box("_JarStall", (2.0, 0.10, 1.0), (-9.4, 0.92, 5.5), bev=0.015))
    for k in range(5):
        parts.append(add_cyl("_Jar%d" % k, 0.26 - k * 0.02, 0.62,
                             (-9.9 + k * 0.48, 1.28, 5.5), axis="y", seg=12, bevel=0.02))
    rules = [
        ("_Ground", "sandstone"), ("_Post", "wood"), ("_Frame", "wood"),
        ("_Canvas", "canvas"), ("_Scallop", "canvas"),
        ("_Table", "wood"), ("_TableL", "wood"), ("_Crate", "wood"), ("_Sack", "canvas"),
        ("_Scale", "metal"), ("_Rug", "canvas"), ("_Roll", "canvas"),
        ("_Shade", "canvas"), ("_Cable", "metal"),
        ("_JarStall", "wood"), ("_Jar", "clay"),
    ]
    return _finish("Prop_desert_market", parts, rules)


# ============================================================ 土坯房群
def build_desert_adobe():
    reset()
    parts = []
    # 院墙(夯土围墙 + 木门)
    parts.append(_box("_WallF", (18.0, 2.6, 0.5), (0, 1.3, -7.0), bev=0.03))
    parts.append(_box("_WallB", (18.0, 2.6, 0.5), (0, 1.3, 7.0), bev=0.03))
    parts.append(_box("_WallL", (0.5, 2.6, 14.0), (-9.0, 1.3, 0), bev=0.03))
    parts.append(_box("_WallR", (0.5, 2.6, 14.0), (9.0, 1.3, 0), bev=0.03))
    parts.append(_box("_WallTop", (18.4, 0.22, 0.75), (0, 2.70, -7.0), bev=0.02))
    # 大门(木框 + 双扇)
    parts.append(_box("_GateF", (2.6, 3.0, 0.55), (0, 1.5, -7.0), bev=0.03))
    for s in (-1, 1):
        parts.append(_box("_Gate%d" % s, (1.2, 2.5, 0.16), (s * 0.62, 1.30, -7.0), bev=0.025))
        for k in range(3):
            parts.append(_box("_GatePlank%d_%d" % (s, k), (1.1, 0.08, 0.05),
                              (s * 0.62, 0.55 + k * 0.72, -7.20), bev=0.006))
    # 主房(两层平顶 + 女儿墙 + 外露木梁)
    MW, MD, MH = 11.0, 8.0, 5.6
    parts.append(_box("_House", (MW, MH, MD), (-2.0, MH * 0.5, -1.0), bev=0.035))
    parts.append(_box("_Floor2", (MW + 0.5, 0.28, MD + 0.5), (-2.0, MH + 0.14, -1.0), bev=0.02))
    parts.append(_box("_Up", (MW - 1.2, 2.8, MD - 1.4), (-2.0, MH + 1.55, -1.0), bev=0.03))
    # 女儿墙
    hy = -1.0
    parts.append(_box("_ParF", (MW - 0.8, 0.85, 0.30), (-2.0, MH + 3.30, hy - (MD - 1.4) * 0.5), bev=0.02))
    parts.append(_box("_ParB", (MW - 0.8, 0.85, 0.30), (-2.0, MH + 3.30, hy + (MD - 1.4) * 0.5), bev=0.02))
    parts.append(_box("_ParL", (0.30, 0.85, MD - 1.4), (-2.0 - (MW - 1.2) * 0.5, MH + 3.30, hy), bev=0.02))
    parts.append(_box("_ParR", (0.30, 0.85, MD - 1.4), (-2.0 + (MW - 1.2) * 0.5, MH + 3.30, hy), bev=0.02))
    # 外露木梁(屋顶椽子头)
    for i in range(9):
        px = -2.0 - 4.4 + i * 1.10
        parts.append(_box("_Beam%d" % i, (0.18, 0.18, 0.85), (px, MH + 0.20, hy - MD * 0.5 - 0.30), bev=0.012))
        parts.append(_box("_BeamB%d" % i, (0.18, 0.18, 0.85), (px, MH + 0.20, hy + MD * 0.5 + 0.30), bev=0.012))
    # 拱窗 + 木格栅
    for i in range(3):
        wx = -6.0 + i * 3.4
        parts.append(_box("_Win%d" % i, (1.5, 1.8, 0.30), (wx, 2.6, hy - MD * 0.5 - 0.10), bev=0.02))
        parts.append(add_cyl("_WinArch%d" % i, 0.75, 0.28, (wx, 3.55, hy - MD * 0.5 - 0.10),
                             axis="x", seg=14, bevel=0.015))
        for k in range(3):
            parts.append(_box("_Grille%d_%d" % (i, k), (1.3, 0.07, 0.06),
                              (wx, 2.15 + k * 0.52, hy - MD * 0.5 - 0.26), bev=0.006))
        # 二层小窗
        parts.append(_box("_Win2_%d" % i, (1.1, 1.3, 0.28), (wx, MH + 1.7, hy - (MD - 1.4) * 0.5 - 0.08), bev=0.018))
    # 侧屋(厨房/储藏,单层)
    parts.append(_box("_Shed", (5.5, 3.4, 5.0), (6.0, 1.70, 3.0), bev=0.03))
    parts.append(_box("_ShedRoof", (6.0, 0.24, 5.5), (6.0, 3.52, 3.0), bev=0.02))
    for i in range(5):
        parts.append(_box("_ShedBeam%d" % i, (0.16, 0.16, 0.75),
                          (4.0 + i * 1.05, 3.35, 3.0 - 2.75), bev=0.010))
    # 外部楼梯(土坯台阶上二层)
    for i in range(9):
        parts.append(_box("_Stair%d" % i, (1.5, 0.30, 0.42),
                          (-8.6, 0.15 + i * 0.30, 2.4 - i * 0.42), bev=0.012))
    parts.append(_box("_StairRail", (0.08, 0.08, 4.0), (-9.3, 1.55, 1.6), bev=0.008, rot=(-0.72, 0, 0)))
    # 庭院:水井 + 陶罐 + 晾衣绳 + 枣椰树
    parts.append(add_cyl("_Well", 0.95, 1.1, (4.0, 0.55, -4.5), axis="y", seg=16, bevel=0.03))
    parts.append(add_cyl("_WellIn", 0.78, 0.20, (4.0, 1.02, -4.5), axis="y", seg=16))
    for s in (-1, 1):
        parts.append(add_cyl("_WellPost%d" % s, 0.09, 2.4, (4.0 + s * 1.0, 1.20, -4.5), axis="y", seg=8))
    parts.append(_box("_WellBeam", (2.4, 0.14, 0.14), (4.0, 2.42, -4.5), bev=0.010))
    parts.append(add_cyl("_WellRope", 0.03, 0.85, (4.0, 1.95, -4.5), axis="y", seg=6))
    parts.append(add_cyl("_WellBucket", 0.22, 0.34, (4.0, 1.42, -4.5), axis="y", seg=10, bevel=0.012))
    parts.append(add_cyl("_PalmTrunk", 0.18, 5.4, (-6.5, 2.70, 4.5), axis="y", seg=9, taper=0.72))
    for k in range(8):
        a = k * math.tau / 8.0
        parts.append(_box("_PalmFrond%d" % k, (0.34, 0.05, 2.4),
                          (-6.5 + math.sin(a) * 1.05, 5.25, 4.5 + math.cos(a) * 1.05),
                          bev=0.008, rot=(-0.40, a + math.pi * 0.5, 0)))
    rules = [
        ("_Wall", "adobe"), ("_WallTop", "adobe"), ("_GateF", "wood"), ("_Gate", "wood"),
        ("_GatePlank", "wood"), ("_House", "adobe"), ("_Floor2", "adobe"), ("_Up", "adobe"),
        ("_Par", "adobe"), ("_Beam", "wood"), ("_BeamB", "wood"),
        ("_Win", "wood"), ("_WinArch", "adobe"), ("_Grille", "wood"), ("_Win2", "wood"),
        ("_Shed", "adobe"), ("_ShedRoof", "adobe"), ("_ShedBeam", "wood"),
        ("_Stair", "adobe"), ("_StairRail", "wood"),
        ("_Well", "sandstone"), ("_WellIn", "water"), ("_WellPost", "wood"),
        ("_WellBeam", "wood"), ("_WellRope", "rope"), ("_WellBucket", "wood"),
        ("_PalmTrunk", "bark_palm"), ("_PalmFrond", "leaf_palm"),
    ]
    return _finish("Prop_desert_adobe", parts, rules)


# ============================================================ 水塔
def build_desert_watertower():
    reset()
    parts = []
    H_LEG = 9.0
    # 基础墩 ×4
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Foot%d%d" % (sx, sz), (1.5, 2.3, 1.5),
                              (sx * 3.0, -0.45, sz * 3.0), bev=0.03))
    # 4 支腿(内倾) + 交叉支撑
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Leg%d%d" % (sx, sz), (0.30, H_LEG, 0.30),
                              (sx * 2.45, H_LEG * 0.5 + 0.7, sz * 2.45), bev=0.02,
                              rot=(sz * 0.075, 0, -sx * 0.075)))
    for i in range(3):
        y = 1.6 + i * 2.7
        sh = 1.0 - i * 0.10
        for ax in ("x", "z"):
            for s in (-1, 1):
                if ax == "x":
                    parts.append(_box("_XBr%d_%s%d" % (i, ax, s), (5.0 * sh, 0.11, 0.11),
                                      (0, y, s * 2.45 * sh), bev=0.008))
                else:
                    parts.append(_box("_XBr%d_%s%d" % (i, ax, s), (0.11, 0.11, 5.0 * sh),
                                      (s * 2.45 * sh, y, 0), bev=0.008))
        # 斜撑
        parts.append(_box("_Diag%d" % i, (7.2 * sh, 0.09, 0.09), (0, y + 1.35, -2.45 * sh),
                          bev=0.008, rot=(0, 0, 0.60)))
        parts.append(_box("_Diag2%d" % i, (7.2 * sh, 0.09, 0.09), (0, y + 1.35, 2.45 * sh),
                          bev=0.008, rot=(0, 0, -0.60)))
    # 检修平台 + 围栏
    parts.append(_box("_Plat", (6.6, 0.16, 6.6), (0, H_LEG + 0.78, 0), bev=0.02))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Rail%d%d" % (sx, sz), (6.6 if sz else 0.08, 1.05, 0.08 if sz else 6.6),
                              (sx * 3.2 if sz else sx * 3.2, H_LEG + 1.40, sz * 3.2 if sz else 0.0), bev=0.008))
    parts.append(_box("_RailTop", (6.7, 0.08, 0.08), (0, H_LEG + 1.92, -3.25), bev=0.008))
    parts.append(_box("_RailTop2", (6.7, 0.08, 0.08), (0, H_LEG + 1.92, 3.25), bev=0.008))
    # 罐体(圆柱 + 锥顶 + 底锥 + 箍)
    ty = H_LEG + 0.86
    parts.append(add_cyl("_Tank", 3.1, 5.2, (0, ty + 2.6, 0), axis="y", seg=28, bevel=0.04))
    parts.append(add_cyl("_TankTop", 3.05, 1.5, (0, ty + 5.9, 0), axis="y", seg=28, taper=0.10, bevel=0.035))
    parts.append(add_cyl("_TankBot", 3.05, 1.2, (0, ty - 0.6, 0), axis="y", seg=28, taper=0.55, bevel=0.03))
    for i in range(3):
        parts.append(add_cyl("_Hoop%d" % i, 3.16, 0.18, (0, ty + 0.9 + i * 1.75, 0), axis="y", seg=28, bevel=0.015))
    # 顶栏 + 人孔 + 透气
    parts.append(add_cyl("_TopRail", 1.3, 0.10, (0, ty + 6.72, 0), axis="y", seg=16, bevel=0.012))
    parts.append(add_cyl("_Manway", 0.55, 0.35, (0, ty + 6.85, 0), axis="y", seg=12, bevel=0.02))
    parts.append(add_cyl("_Vent", 0.11, 0.75, (1.9, ty + 7.0, 0), axis="y", seg=8))
    # 爬梯(带护笼)
    parts += _ladder("_Lad", 3.35, 0.7, H_LEG + 1.0, 0.0, w=0.62)
    for i in range(10):
        y = 2.2 + i * 0.85
        parts.append(add_cyl("_Cage%d" % i, 0.42, 0.05, (3.62, y, 0), axis="y", seg=10))
    # 进出水管 + 水位计
    parts.append(add_cyl("_Inlet", 0.24, 5.0, (0, ty + 0.4, 0), axis="y", seg=12, bevel=0.02))
    parts += _pipe_run("_Pipe", [(0, 1.2, 0), (0, 1.2, 4.2), (2.6, 1.2, 4.2)], r=0.22)
    parts.append(_box("_Gauge", (0.28, 4.0, 0.14), (-3.3, ty + 2.6, 0.6), bev=0.012))
    rules = [
        ("_Foot", "concrete"), ("_Leg", "metal"), ("_XBr", "metal"), ("_Diag", "metal"), ("_Diag2", "metal"),
        ("_Plat", "metal"), ("_Rail", "metal"), ("_RailTop", "metal"), ("_RailTop2", "metal"),
        ("_Tank", "tank"), ("_TankTop", "tank"), ("_TankBot", "tank"), ("_Hoop", "metal"),
        ("_TopRail", "metal"), ("_Manway", "metal"), ("_Vent", "metal"),
        ("_Lad_Rail", "metal"), ("_Lad_Rung", "metal"), ("_Lad", "metal"), ("_Cage", "metal"),
        ("_Inlet", "metal"), ("_Pipe_P", "metal"), ("_Pipe", "metal"), ("_Gauge", "sign"),
    ]
    return _finish("Prop_desert_watertower", parts, rules)


# ============================================================ 通讯塔
def build_desert_comms():
    reset()
    parts = []
    TH = 26.0
    # 基础 ×4
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Foot%d%d" % (sx, sz), (1.7, 2.4, 1.7), (sx * 2.3, -0.40, sz * 2.3), bev=0.03))
    # 格构桁架(4 腿收分 + 横隔 + X 斜撑)
    n_seg = 11
    for i in range(n_seg):
        t0 = i / float(n_seg)
        t1 = (i + 1) / float(n_seg)
        r0 = 2.30 * (1.0 - t0 * 0.62)
        r1 = 2.30 * (1.0 - t1 * 0.62)
        y0 = 0.8 + t0 * (TH - 1.0)
        y1 = 0.8 + t1 * (TH - 1.0)
        for sx in (-1, 1):
            for sz in (-1, 1):
                mx, mz = sx * (r0 + r1) * 0.5, sz * (r0 + r1) * 0.5
                my = (y0 + y1) * 0.5
                seg_len = math.sqrt((r1 - r0) ** 2 * 2 + (y1 - y0) ** 2)
                ob = add_cyl("_Leg%d_%d%d" % (i, sx, sz), 0.09, seg_len, (mx, my, mz), axis="y", seg=6)
                # 倾斜:绕 X/Z 轴旋转使顶端收进
                ob.rotation_euler = rot_g2b((sz * 0.075, 0, -sx * 0.075))
                parts.append(ob)
        # 横隔 + X 斜撑
        for s in (-1, 1):
            parts.append(_box("_Hz%d_%d" % (i, s), (r0 * 2, 0.07, 0.07), (0, y0, s * r0), bev=0.006))
            parts.append(_box("_Hz2%d_%d" % (i, s), (0.07, 0.07, r0 * 2), (s * r0, y0, 0), bev=0.006))
        for s in (-1, 1):
            diag_len = math.sqrt((r0 * 2) ** 2 + (y1 - y0) ** 2)
            parts.append(_box("_Diag%d_%d" % (i, s), (0.06, diag_len, 0.06),
                              (0, (y0 + y1) * 0.5, s * r0 * 0.0 - s * (r0 + r1) * 0.5),
                              bev=0.005, rot=(0, 0, s * 0.34)))
    top_y = 0.8 + (TH - 1.0)
    r_top = 2.30 * 0.38
    # 顶部平台 + 天线阵
    parts.append(_box("_TopPlat", (r_top * 2.4, 0.14, r_top * 2.4), (0, top_y, 0), bev=0.015))
    parts.append(add_cyl("_Mast", 0.12, 5.0, (0, top_y + 2.6, 0), axis="y", seg=8))
    parts.append(_box("_Beacon", (0.30, 0.30, 0.30), (0, top_y + 5.3, 0), bev=0.03))
    # 抛物面天线 ×3(不同高度/朝向)
    for k, (ay, aa) in enumerate(((top_y - 4.0, 0.4), (top_y - 8.0, 2.6), (top_y - 12.0, 4.6))):
        dx, dz = math.sin(aa) * 1.5, math.cos(aa) * 1.5
        parts.append(add_cyl("_Dish%d" % k, 1.25, 0.42, (dx, ay, dz), axis="z", seg=20, taper=0.35, bevel=0.025))
        parts.append(add_cyl("_DishRim%d" % k, 1.28, 0.10, (dx, ay, dz), axis="z", seg=20, bevel=0.012))
        parts.append(add_cyl("_Feed%d" % k, 0.09, 0.85,
                             (dx + math.sin(aa) * 0.75, ay, dz + math.cos(aa) * 0.75), axis="z", seg=8))
        parts.append(_box("_DishArm%d" % k, (0.14, 0.14, 1.2),
                          (dx * 0.5, ay, dz * 0.5), bev=0.010, rot=(0, aa, 0)))
    # 微波鼓(圆柱天线)×4
    for k in range(4):
        ay = 6.0 + k * 3.4
        aa = k * 1.1
        parts.append(add_cyl("_Drum%d" % k, 0.42, 0.95, (math.sin(aa) * 1.3, ay, math.cos(aa) * 1.3),
                             axis="z", seg=14, bevel=0.02))
    # 机房(塔下小屋)
    parts.append(_box("_Hut", (5.0, 3.0, 4.0), (4.6, 1.50, 2.4), bev=0.03))
    parts.append(_box("_HutRoof", (5.5, 0.24, 4.5), (4.6, 3.12, 2.4), bev=0.02))
    parts.append(_box("_HutDoor", (1.1, 2.2, 0.16), (4.6, 1.10, 2.4 - 2.05), bev=0.018))
    parts.append(_box("_AC", (0.85, 0.60, 0.34), (6.6, 1.90, 2.4), bev=0.02))
    rules = [
        ("_Foot", "concrete"), ("_Leg", "metal"), ("_Hz", "metal"), ("_Hz2", "metal"),
        ("_Diag", "metal"), ("_TopPlat", "metal"), ("_Mast", "metal"), ("_Beacon", "sign"),
        ("_Dish", "metal"), ("_DishRim", "metal"), ("_Feed", "metal"), ("_DishArm", "metal"),
        ("_Drum", "metal"), ("_Hut", "wall"), ("_HutRoof", "roof"), ("_HutDoor", "trim"), ("_AC", "metal"),
    ]
    return _finish("Prop_desert_comms", parts, rules)


# ============================================================ 炼厂(分馏塔 + 管廊)
def build_desert_factory():
    reset()
    parts = []
    # 混凝土基础平台
    parts.append(_box("_Slab", (30.0, 2.1, 20.0), (0, -0.55, 0), bev=0.03))
    # 分馏塔 ×2(高圆柱 + 多层平台 + 梯)
    for k, cx in enumerate((-8.0, 2.0)):
        TH = 21.0 if k == 0 else 16.0
        R = 2.1 if k == 0 else 1.7
        parts.append(add_cyl("_Col%d" % k, R, TH, (cx, TH * 0.5 + 0.5, -3.0), axis="y", seg=24, bevel=0.04))
        parts.append(add_cyl("_ColTop%d" % k, R * 0.98, 1.6, (cx, TH + 1.30, -3.0), axis="y", seg=24,
                             taper=0.20, bevel=0.035))
        # 层平台(每 4m + 栏杆)
        n_p = int(TH / 4.0)
        for i in range(n_p):
            py = 0.5 + 3.0 + i * 4.0
            parts.append(add_cyl("_Deck%d_%d" % (k, i), R + 0.85, 0.16, (cx, py, -3.0),
                                 axis="y", seg=20, bevel=0.012))
            for j in range(8):
                a = j * math.tau / 8.0
                parts.append(_box("_Post%d_%d_%d" % (k, i, j), (0.07, 1.05, 0.07),
                                  (cx + math.sin(a) * (R + 0.78), py + 0.60, -3.0 + math.cos(a) * (R + 0.78)),
                                  bev=0.006))
            parts.append(add_cyl("_Hand%d_%d" % (k, i), R + 0.82, 0.05, (cx, py + 1.12, -3.0),
                                 axis="y", seg=20))
        # 直梯
        parts += _ladder("_CL%d" % k, cx + R + 0.55, 0.5, TH + 0.6, -3.0 + 0.0, w=0.62)
        # 顶部火炬/放空管
        parts.append(add_cyl("_VentP%d" % k, 0.34, 3.2, (cx, TH + 2.6, -3.0), axis="y", seg=12, bevel=0.02))
        parts.append(add_cyl("_VentTip%d" % k, 0.46, 0.4, (cx, TH + 4.3, -3.0), axis="y", seg=12, bevel=0.015))
    # 加热炉(方箱 + 烟囱 + 观火孔)
    parts.append(_box("_Furnace", (6.0, 7.0, 5.0), (10.0, 4.0, 2.0), bev=0.035))
    parts.append(_box("_FurnTop", (6.4, 0.40, 5.4), (10.0, 7.70, 2.0), bev=0.025))
    parts.append(add_cyl("_Stack", 1.15, 12.0, (10.0, 13.5, 2.0), axis="y", seg=18, taper=0.86, bevel=0.03))
    for i in range(3):
        parts.append(add_cyl("_StackRing%d" % i, 1.22 - i * 0.04, 0.20, (10.0, 9.0 + i * 3.4, 2.0),
                             axis="y", seg=18, bevel=0.015))
    for i in range(3):
        parts.append(_box("_Peep%d" % i, (0.34, 0.34, 0.20), (7.6, 2.4 + i * 1.6, 2.0 - 2.55), bev=0.012))
    # 钢框架(管廊支撑)
    for i in range(5):
        px = -13.0 + i * 6.5
        for pz in (-8.0, 5.0):
            parts.append(_box("_FCol%d_%d" % (i, int(pz)), (0.28, 6.0, 0.28), (px, 3.0, pz), bev=0.015))
    for pz in (-8.0, 5.0):
        parts.append(_box("_FBeam%d" % int(pz), (28.0, 0.32, 0.32), (0, 6.10, pz), bev=0.018))
        parts.append(_box("_FBeam2%d" % int(pz), (28.0, 0.24, 0.24), (0, 3.20, pz), bev=0.015))
    # 管廊(多层管道)
    for i in range(5):
        zc = -7.2 + i * 0.85
        parts.append(add_cyl("_Pipe%d" % i, 0.20 - (i % 2) * 0.05, 27.0, (0, 6.45, zc),
                             axis="x", seg=12, bevel=0.010))
    # 换热器组(卧式罐 ×3)
    for i in range(3):
        ex = -14.0 + i * 3.4
        parts.append(add_cyl("_Exch%d" % i, 0.95, 5.5, (ex, 1.35, 8.0), axis="x", seg=18, bevel=0.03))
        for s in (-1, 1):
            parts.append(_box("_ExchS%d%d" % (i, s), (0.18, 1.7, 0.18), (ex + s * 2.4, 0.85, 8.0), bev=0.012))
            parts.append(add_cyl("_ExchCap%d%d" % (i, s), 1.0, 0.30, (ex + s * 2.85, 1.35, 8.0),
                                 axis="x", seg=18, bevel=0.02))
    # 控制室(小房 + 窗)
    parts.append(_box("_Ctrl", (5.0, 3.2, 4.0), (13.0, 2.10, -7.0), bev=0.03))
    parts.append(_box("_CtrlRoof", (5.5, 0.26, 4.5), (13.0, 3.83, -7.0), bev=0.022))
    parts.append(_box("_CtrlWin", (3.4, 1.3, 0.12), (13.0, 2.30, -7.0 - 2.05), bev=0.015))
    parts.append(_box("_CtrlDoor", (1.1, 2.2, 0.16), (15.1, 1.10, -7.0), bev=0.018))
    rules = [
        ("_Slab", "concrete"), ("_Col", "tank"), ("_ColTop", "tank"),
        ("_Deck", "metal"), ("_Post", "metal"), ("_Hand", "metal"),
        ("_CL_Rail", "metal"), ("_CL_Rung", "metal"), ("_CL", "metal"),
        ("_VentP", "metal"), ("_VentTip", "metal"),
        ("_Furnace", "wall"), ("_FurnTop", "metal"), ("_Stack", "metal"), ("_StackRing", "metal"),
        ("_Peep", "sign"), ("_FCol", "metal"), ("_FBeam", "metal"), ("_FBeam2", "metal"),
        ("_Pipe", "pipe"), ("_Exch", "tank"), ("_ExchS", "metal"), ("_ExchCap", "tank"),
        ("_Ctrl", "wall"), ("_CtrlRoof", "roof"), ("_CtrlWin", "glass"), ("_CtrlDoor", "trim"),
    ]
    return _finish("Prop_desert_factory", parts, rules)


# ============================================================ 沙漠地堡
def build_desert_bunker():
    reset()
    parts = []
    # 主体(半埋混凝土掩体)
    parts.append(_box("_Body", (11.0, 3.6, 8.0), (0, 1.30, 0), bev=0.04))
    parts.append(_box("_Shoulder", (13.0, 2.6, 9.6), (0, -0.30, 0), bev=0.035))
    # 顶盖(斜面 + 覆土边缘)
    parts.append(_box("_Roof", (11.8, 0.55, 8.8), (0, 3.35, 0), bev=0.035))
    parts.append(_box("_Earth", (13.6, 0.85, 10.4), (0, 3.05, 0), bev=0.05))
    # 射击口 ×3(凹龛 + 内衬钢板)
    for i, sx in enumerate((-3.4, 0.0, 3.4)):
        parts.append(_box("_Embrasure%d" % i, (1.5, 0.85, 0.9), (sx, 2.05, -4.15), bev=0.02))
        parts.append(_box("_EmbrIn%d" % i, (1.15, 0.55, 0.55), (sx, 2.05, -3.90), bev=0.015))
        parts.append(_box("_EmbrPlate%d" % i, (1.7, 0.14, 0.14), (sx, 2.52, -4.40), bev=0.010))
    # 铁门(凹进门框 + 双扇 + 铰链 + 把手)
    parts.append(_box("_DoorF", (2.8, 2.6, 0.55), (0, 1.30, -4.30), bev=0.03))
    for s in (-1, 1):
        parts.append(_box("_Door%d" % s, (1.25, 2.25, 0.14), (s * 0.66, 1.15, -4.45), bev=0.025))
        for k in range(3):
            parts.append(_box("_DoorRib%d_%d" % (s, k), (1.1, 0.11, 0.05),
                              (s * 0.66, 0.55 + k * 0.62, -4.53), bev=0.008))
        parts.append(add_cyl("_Hinge%d" % s, 0.10, 0.55, (s * 1.32, 1.15, -4.45), axis="y", seg=8))
        parts.append(add_cyl("_Handle%d" % s, 0.045, 0.42, (s * 0.22, 1.15, -4.53), axis="y", seg=8))
    # 沙袋墙(门前弧形)
    n_bag = 16
    for i in range(n_bag):
        t = i / float(n_bag - 1)
        a = -0.85 + t * 1.70
        rr = 6.4
        bx, bz = math.sin(a) * rr, -math.cos(a) * rr + 1.2
        for row in range(3):
            off = (row % 2) * 0.28
            parts.append(_box("_Bag%d_%d" % (i, row), (0.62, 0.26, 0.42),
                              (bx + math.cos(a) * off, 0.15 + row * 0.25, bz + math.sin(a) * off),
                              bev=0.05, rot=(0, -a, 0)))
    # 通风管 + 天线 + 观测镜
    parts.append(add_cyl("_VentPipe", 0.26, 2.4, (4.2, 4.55, 2.6), axis="y", seg=12, bevel=0.02))
    parts.append(add_cyl("_VentCap", 0.36, 0.30, (4.2, 5.85, 2.6), axis="y", seg=12, bevel=0.015))
    parts.append(add_cyl("_Ant", 0.04, 3.0, (-4.4, 5.10, 2.4), axis="y", seg=6))
    parts.append(_box("_Scope", (0.22, 0.22, 0.75), (0, 3.95, -2.4), bev=0.015, rot=(-0.12, 0, 0)))
    # 台阶 + 排水沟
    parts.append(_box("_Step", (3.2, 0.22, 0.60), (0, 0.11, -5.2), bev=0.015))
    parts.append(_box("_Drain", (11.4, 0.20, 0.42), (0, 0.32, 4.35), bev=0.012))
    rules = [
        ("_Body", "concrete"), ("_Shoulder", "concrete"), ("_Roof", "concrete"),
        ("_Earth", "sandstone"), ("_Embrasure", "concrete"), ("_EmbrIn", "metal"),
        ("_EmbrPlate", "metal"), ("_DoorF", "concrete"), ("_Door", "metal"),
        ("_DoorRib", "metal"), ("_Hinge", "metal"), ("_Handle", "metal"),
        ("_Bag", "sandbag"), ("_VentPipe", "metal"), ("_VentCap", "metal"),
        ("_Ant", "metal"), ("_Scope", "metal"), ("_Step", "concrete"), ("_Drain", "concrete"),
    ]
    return _finish("Prop_desert_bunker", parts, rules)


BUILDERS = {
    "desert_oilrig": build_desert_oilrig,
    "desert_tank": build_desert_tank,
    "desert_pumpstation": build_desert_pumpstation,
    "desert_mosque": build_desert_mosque,
    "desert_market": build_desert_market,
    "desert_adobe": build_desert_adobe,
    "desert_watertower": build_desert_watertower,
    "desert_comms": build_desert_comms,
    "desert_factory": build_desert_factory,
    "desert_bunker": build_desert_bunker,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ids = args if args else sorted(BUILDERS.keys())
    os.makedirs(OUT_DIR, exist_ok=True)
    ok = []
    for pid in ids:
        if pid not in BUILDERS:
            print("[skip] unknown id:", pid)
            continue
        ob = BUILDERS[pid]()
        path = os.path.join(OUT_DIR, pid + ".glb")
        export_glb(path)
        print("[build] %-20s -> %s  (polys=%d)" % (pid, os.path.basename(path), len(ob.data.polygons)))
        ok.append(pid)
    print("\n[done] scene batch: %d/%d" % (len(ok), len(ids)))


if __name__ == "__main__":
    main()
