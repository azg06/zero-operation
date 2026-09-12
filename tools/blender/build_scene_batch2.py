"""
其余 4 张地图(丛林/雪山/暮港/BR)3A 级建筑批次
—— 作为 build_scene_batch.py 的第二段,追加 9 个模型。
"""
import sys, os, math, random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/props"
random.seed(20260908)


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


# ============================================================ 丛林神庙遗迹
def build_jungle_temple():
    reset()
    parts = []
    # 基座平台
    parts.append(_box("_Plinth", (22.0, 2.2, 20.0), (0, -0.50, 0), bev=0.035))
    # 阶梯金字塔 5 层(逐层收分 + 中央阶梯)
    TIERS = 5
    for i in range(TIERS):
        t = i / float(TIERS)
        w = 17.0 * (1.0 - t * 0.62)
        d = 15.0 * (1.0 - t * 0.62)
        h = 2.4
        y = 0.6 + i * h + h * 0.5
        parts.append(_box("_Tier%d" % i, (w, h, d), (0, y, 0), bev=0.035))
        # 层沿(出檐)
        parts.append(_box("_Cornice%d" % i, (w + 0.7, 0.30, d + 0.7), (0, y + h * 0.5 + 0.12, 0), bev=0.028))
    # 中央阶梯(正面,每级)
    n_st = 14
    for i in range(n_st):
        t = i / float(n_st)
        y = 0.6 + t * (TIERS * 2.4)
        z = 8.6 - t * 6.6
        parts.append(_box("_Step%d" % i, (5.0, 0.30, 0.62), (0, y + 0.15, z), bev=0.015))
    # 阶梯两侧扶手墙
    for s in (-1, 1):
        parts.append(_box("_Rail%d" % s, (0.75, TIERS * 2.4 + 1.2, 7.4),
                          (s * 2.85, 0.6 + (TIERS * 2.4 + 1.2) * 0.5, 5.3), bev=0.025,
                          rot=(0.42, 0, 0)))
    # 顶部神殿(门廊 + 4 柱 + 楣梁 + 顶饰)
    ty = 0.6 + TIERS * 2.4
    parts.append(_box("_Shrine", (7.4, 4.2, 6.0), (0, ty + 2.10, -1.0), bev=0.035))
    parts.append(_box("_ShrineRoof", (8.4, 0.45, 7.0), (0, ty + 4.38, -1.0), bev=0.03))
    parts.append(_box("_RoofComb", (7.0, 1.5, 0.55), (0, ty + 5.30, -1.0 - 3.0), bev=0.025))
    # 门廊柱
    for s in (-1, 1):
        parts.append(add_cyl("_PCol%d" % s, 0.45, 3.8, (s * 2.4, ty + 1.90, -4.30),
                             axis="y", seg=14, bevel=0.02))
        parts.append(_box("_PColCap%d" % s, (1.2, 0.35, 1.2), (s * 2.4, ty + 3.95, -4.30), bev=0.02))
    parts.append(_box("_Lintel", (6.6, 0.75, 0.9), (0, ty + 4.40, -4.30), bev=0.025))
    parts.append(_box("_Door", (2.4, 3.2, 0.30), (0, ty + 1.60, -4.05), bev=0.025))
    # 浮雕带(神殿四面的横向雕刻条)
    for i in range(3):
        parts.append(_box("_Relief%d" % i, (7.6, 0.55, 0.14), (0, ty + 1.0 + i * 1.3, -4.05), bev=0.012))
        for k in range(5):
            parts.append(_box("_Glyph%d_%d" % (i, k), (0.55, 0.40, 0.10),
                              (-2.6 + k * 1.3, ty + 1.0 + i * 1.3, -4.16), bev=0.010))
    # 倒塌石柱(散落四周)
    for i in range(6):
        a = i * 1.05 + 0.3
        rr = 12.5 + (i % 3) * 1.6
        cx, cz = math.sin(a) * rr, math.cos(a) * rr
        if i % 2 == 0:
            parts.append(add_cyl("_FallCol%d" % i, 0.55, 3.6 + (i % 3), (cx, 0.60, cz),
                                 axis="y", seg=12, bevel=0.025))
        else:
            ob = add_cyl("_FallCol%d" % i, 0.52, 4.0, (cx, 0.52, cz),
                         axis="z", seg=12, bevel=0.025)
            ob.rotation_euler = rot_g2b((0, a, 0))
            parts.append(ob)
            parts.append(_box("_FallDrum%d" % i, (0.9, 0.9, 0.9), (cx + 1.2, 0.45, cz + 0.7), bev=0.06))
    # 藤蔓(沿神殿垂下的绿条)
    for i in range(8):
        t = i / 7.0
        parts.append(_box("_Vine%d" % i, (0.16, 3.2 + (i % 3) * 0.9, 0.16),
                          (-3.2 + t * 6.4, ty + 2.6, -4.55), bev=0.03))
    rules = [
        ("_Plinth", "temple_stone"), ("_Tier", "temple_stone"), ("_Cornice", "temple_stone"),
        ("_Step", "temple_stone"), ("_Rail", "temple_stone"),
        ("_Shrine", "temple_stone"), ("_ShrineRoof", "temple_stone"), ("_RoofComb", "temple_stone"),
        ("_PCol", "temple_stone"), ("_PColCap", "temple_stone"), ("_Lintel", "temple_stone"),
        ("_Door", "dark_opening"), ("_Relief", "temple_stone"), ("_Glyph", "temple_stone"),
        ("_FallCol", "temple_stone"), ("_FallDrum", "temple_stone"),
        ("_Vine", "jungle_leaf"),
    ]
    return _finish("Prop_jungle_temple", parts, rules)


# ============================================================ 丛林高脚木屋
def build_jungle_stilt():
    reset()
    parts = []
    # 支柱(6 根,入地)
    for sx in (-1, 0, 1):
        for sz in (-1, 1):
            parts.append(add_cyl("_Post%d_%d" % (sx, sz), 0.16, 4.2,
                                 (sx * 2.6, 1.70, sz * 2.0), axis="y", seg=10, taper=0.88, bevel=0.012))
            parts.append(_box("_Pad%d_%d" % (sx, sz), (0.55, 0.30, 0.55),
                              (sx * 2.6, 0.15, sz * 2.0), bev=0.02))
    # 交叉支撑
    for s in (-1, 1):
        parts.append(_box("_Brace%d" % s, (0.11, 3.4, 0.11), (0, 1.70, s * 2.0), bev=0.006,
                          rot=(s * 0.38, 0, 0)))
    parts.append(_box("_BeamX", (6.2, 0.20, 0.20), (0, 3.62, -2.0), bev=0.012))
    parts.append(_box("_BeamX2", (6.2, 0.20, 0.20), (0, 3.62, 2.0), bev=0.012))
    for sx in (-1, 1):
        parts.append(_box("_BeamZ%d" % sx, (0.20, 0.20, 4.6), (sx * 2.6, 3.62, 0), bev=0.012))
    # 地板
    parts.append(_box("_Floor", (7.0, 0.22, 5.6), (0, 3.84, 0), bev=0.02))
    # 墙体(竹编墙:竖条 + 横条)
    W, D, H = 6.6, 5.2, 2.9
    for i in range(14):
        px = (i / 13.0 - 0.5) * (W - 0.3)
        parts.append(_box("_WallF%d" % i, (0.13, H, 0.10), (px, 3.95 + H * 0.5, -D * 0.5), bev=0.008))
    for i in range(11):
        px = (i / 10.0 - 0.5) * (W - 0.3)
        parts.append(_box("_WallB%d" % i, (0.13, H, 0.10), (px, 3.95 + H * 0.5, D * 0.5), bev=0.008))
    for s in (-1, 1):
        for i in range(9):
            pz = (i / 8.0 - 0.5) * (D - 0.4)
            parts.append(_box("_WallS%d_%d" % (s, i), (0.10, H, 0.13), (s * W * 0.5, 3.95 + H * 0.5, pz), bev=0.008))
    for j in range(2):
        parts.append(_box("_Rail%d" % j, (W, 0.09, 0.09), (0, 4.4 + j * 1.4, -D * 0.5 + 0.07), bev=0.006))
    # 草顶(两层坡顶 + 脊 + 出檐)
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (W * 0.60 + 1.3, 0.26, D + 2.0),
                          (s * (W * 0.225), 3.95 + H + 0.95, 0), bev=0.05, rot=(0, 0, -s * 0.55)))
        parts.append(_box("_Thatch%d" % s, (W * 0.58 + 1.1, 0.16, D + 1.8),
                          (s * (W * 0.225), 3.95 + H + 1.18, 0), bev=0.06, rot=(0, 0, -s * 0.55)))
    parts.append(_box("_Ridge", (0.42, 0.55, D + 2.2), (0, 3.95 + H + 2.15, 0), bev=0.04))
    parts.append(_box("_RidgeCap", (0.60, 0.20, D + 2.3), (0, 3.95 + H + 2.50, 0), bev=0.03))
    # 窗(木框 + 支杆)
    for s in (-1, 1):
        parts.append(_box("_Win%d" % s, (1.5, 1.3, 0.14), (s * 1.8, 3.95 + 1.75, -D * 0.5 - 0.06), bev=0.015))
        parts.append(_box("_WinShut%d" % s, (1.6, 1.35, 0.08), (s * 1.8, 3.95 + 1.75, -D * 0.5 - 0.20),
                          bev=0.015, rot=(0, s * 0.55, 0)))
    # 门 + 梯子(斜靠)
    parts.append(_box("_Door", (1.4, 2.3, 0.14), (0, 3.95 + 1.15, -D * 0.5 - 0.05), bev=0.018))
    for i in range(9):
        parts.append(_box("_Rung%d" % i, (1.5, 0.08, 0.34),
                          (0, 0.35 + i * 0.44, -D * 0.5 - 1.15 - i * 0.30), bev=0.010))
    for s in (-1, 1):
        parts.append(_box("_LadderRail%d" % s, (0.10, 4.2, 0.10),
                          (s * 0.68, 2.10, -D * 0.5 - 1.90), bev=0.008, rot=(0.60, 0, 0)))
    # 晾架(晒鱼/衣物)
    parts.append(_box("_DryF", (3.2, 0.10, 0.10), (0, 4.30, D * 0.5 + 1.4), bev=0.008))
    for s in (-1, 1):
        parts.append(_box("_DryP%d" % s, (0.10, 1.30, 0.10), (s * 1.5, 3.70, D * 0.5 + 1.4), bev=0.008))
    for k in range(5):
        parts.append(_box("_Cloth%d" % k, (0.48, 0.72, 0.05),
                          (-1.2 + k * 0.60, 3.85, D * 0.5 + 1.4), bev=0.02))
    # 屋下杂物(陶罐 + 柴堆 + 鸡笼)
    for k in range(3):
        parts.append(add_cyl("_Jar%d" % k, 0.32 - k * 0.04, 0.68, (-1.8 + k * 0.75, 0.34, 1.0),
                             axis="y", seg=12, bevel=0.02))
    for k in range(5):
        parts.append(add_cyl("_Wood%d" % k, 0.09, 1.6, (2.2, 0.18 + (k // 3) * 0.20, 1.2 + (k % 3) * 0.20),
                             axis="x", seg=8, bevel=0.008))
    parts.append(_box("_Coop", (1.3, 1.0, 1.1), (-3.0, 0.50, -1.6), bev=0.02))
    rules = [
        ("_Post", "wood"), ("_Pad", "temple_stone"), ("_Brace", "wood"),
        ("_Beam", "wood"), ("_Floor", "wood"),
        ("_WallF", "bamboo"), ("_WallB", "bamboo"), ("_WallS", "bamboo"), ("_Rail", "bamboo"),
        ("_Roof", "thatch"), ("_Thatch", "thatch"), ("_Ridge", "thatch"), ("_RidgeCap", "thatch"),
        ("_Win", "wood"), ("_WinShut", "wood"), ("_Door", "wood"),
        ("_Rung", "wood"), ("_LadderRail", "wood"),
        ("_Dry", "wood"), ("_Cloth", "canvas"),
        ("_Jar", "clay"), ("_Wood", "wood"), ("_Coop", "bamboo"),
    ]
    return _finish("Prop_jungle_stilt", parts, rules)


# ============================================================ 雪山木屋
def build_snow_chalet():
    reset()
    parts = []
    W, D, H = 9.5, 8.0, 3.4
    # 石砌基座(防雪)
    parts.append(_box("_Found", (W + 0.8, 2.6, D + 0.8), (0, -0.30, 0), bev=0.035))
    # 木屋主体(原木墙:横条堆叠)
    n_log = 9
    for i in range(n_log):
        y = 1.0 + (H * (i + 0.5) / n_log)
        parts.append(_box("_LogF%d" % i, (W, H / n_log * 0.94, 0.32), (0, y, -D * 0.5), bev=0.018))
        parts.append(_box("_LogB%d" % i, (W, H / n_log * 0.94, 0.32), (0, y, D * 0.5), bev=0.018))
    for s in (-1, 1):
        for i in range(n_log):
            y = 1.0 + (H * (i + 0.5) / n_log)
            parts.append(_box("_LogS%d_%d" % (s, i), (0.32, H / n_log * 0.94, D - 0.64),
                              (s * W * 0.5, y, 0), bev=0.018))
    # 角柱(交叉的原木头)
    for sx in (-1, 1):
        for sz in (-1, 1):
            for i in range(3):
                parts.append(_box("_Corner%d%d_%d" % (sx, sz, i), (0.60, 0.26, 0.60),
                                  (sx * W * 0.5, 1.3 + i * 1.15, sz * D * 0.5), bev=0.02))
    # 大坡顶(双坡 + 厚积雪 + 椽头)
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (W * 0.58 + 0.9, 0.30, D + 2.0),
                          (s * (W * 0.29), 1.0 + H + 1.75, 0), bev=0.04, rot=(0, 0, -s * 0.50)))
        # 积雪层(略厚于屋顶,悬出)
        parts.append(_box("_Snow%d" % s, (W * 0.58 + 1.0, 0.34, D + 2.1),
                          (s * (W * 0.295), 1.0 + H + 2.02, 0), bev=0.09, rot=(0, 0, -s * 0.50)))
        for i in range(7):
            parts.append(_box("_Rafter%d_%d" % (s, i), (0.20, 0.20, 0.85),
                              (s * (W * 0.37), 1.0 + H + 1.35, -D * 0.5 - 0.85 + i * ((D + 1.7) / 6.0)),
                              bev=0.012))
    parts.append(_box("_Ridge", (0.55, 0.60, D + 2.1), (0, 1.0 + H + 3.18, 0), bev=0.05))
    parts.append(_box("_RidgeSnow", (0.75, 0.34, D + 2.2), (0, 1.0 + H + 3.43, 0), bev=0.10))
    # 烟囱(石砌 + 顶盖 + 积雪)
    parts.append(_box("_Chim", (1.25, 3.4, 1.25), (-2.6, 1.0 + H + 1.55, 1.4), bev=0.03))
    parts.append(_box("_ChimCap", (1.55, 0.26, 1.55), (-2.6, 1.0 + H + 3.35, 1.4), bev=0.025))
    parts.append(_box("_ChimSnow", (1.35, 0.22, 1.35), (-2.6, 1.0 + H + 3.60, 1.4), bev=0.09))
    # 窗(木框 + 十字格 + 暖光窗 + 窗台积雪 + 花箱)
    for i, wx in enumerate((-3.0, 0.0, 3.0)):
        parts.append(_box("_WinF%d" % i, (1.55, 1.45, 0.30), (wx, 2.55, -D * 0.5 - 0.02), bev=0.02))
        parts.append(_box("_WinG%d" % i, (1.25, 1.15, 0.10), (wx, 2.55, -D * 0.5 - 0.14), bev=0.015))
        parts.append(_box("_WinC1_%d" % i, (0.07, 1.15, 0.06), (wx, 2.55, -D * 0.5 - 0.18), bev=0.006))
        parts.append(_box("_WinC2_%d" % i, (1.25, 0.07, 0.06), (wx, 2.55, -D * 0.5 - 0.18), bev=0.006))
        parts.append(_box("_WinSill%d" % i, (1.75, 0.14, 0.42), (wx, 1.85, -D * 0.5 - 0.16), bev=0.015))
        parts.append(_box("_SillSnow%d" % i, (1.70, 0.12, 0.38), (wx, 1.98, -D * 0.5 - 0.16), bev=0.06))
        parts.append(_box("_FlowerBox%d" % i, (1.5, 0.28, 0.32), (wx, 1.72, -D * 0.5 - 0.28), bev=0.02))
    # 门(厚重木门 + 门框 + 台阶)
    parts.append(_box("_DoorF", (1.9, 2.6, 0.34), (0, 2.30, -D * 0.5 - 0.05), bev=0.025))
    parts.append(_box("_Door", (1.5, 2.25, 0.16), (0, 2.10, -D * 0.5 - 0.18), bev=0.022))
    for k in range(3):
        parts.append(_box("_DoorPlank%d" % k, (1.35, 0.09, 0.05), (0, 1.40 + k * 0.68, -D * 0.5 - 0.27), bev=0.006))
    parts.append(add_cyl("_DoorHandle", 0.05, 0.35, (0.55, 2.10, -D * 0.5 - 0.28), axis="y", seg=8))
    for i in range(3):
        parts.append(_box("_Step%d" % i, (2.4, 0.24, 0.55), (0, 1.0 - i * 0.24, -D * 0.5 - 0.45 - i * 0.50), bev=0.012))
    # 柴堆(侧墙) + 雪地木桩
    for k in range(9):
        parts.append(add_cyl("_Firewood%d" % k, 0.10, 1.5,
                             (W * 0.5 + 0.75, 1.20 + (k // 5) * 0.22, -2.0 + (k % 5) * 0.22),
                             axis="z", seg=8, bevel=0.008))
    parts.append(_box("_FirewoodRoof", (0.7, 1.5, 1.4), (W * 0.5 + 0.75, 1.72, -1.6), bev=0.02, rot=(0.14, 0, 0)))
    rules = [
        ("_Found", "rock"), ("_Log", "wood_log"), ("_Corner", "wood_log"),
        ("_Roof", "wood_log"), ("_Snow", "snow"), ("_Rafter", "wood_log"),
        ("_Ridge", "wood_log"), ("_RidgeSnow", "snow"),
        ("_Chim", "rock"), ("_ChimCap", "rock"), ("_ChimSnow", "snow"),
        ("_WinF", "wood"), ("_WinG", "lamp_warm"), ("_WinC", "wood"),
        ("_WinSill", "wood"), ("_SillSnow", "snow"), ("_FlowerBox", "wood"),
        ("_DoorF", "wood"), ("_Door", "wood"), ("_DoorPlank", "wood"),
        ("_DoorHandle", "metal"), ("_Step", "rock"),
        ("_Firewood", "wood"), ("_FirewoodRoof", "wood"),
    ]
    return _finish("Prop_snow_chalet", parts, rules)


# ============================================================ 科考站
def build_snow_station():
    reset()
    parts = []
    # 主站房(架空模块箱体 + 支腿)
    MW, MD, MH = 12.0, 8.0, 3.6
    leg_h = 1.5
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(add_cyl("_Leg%d%d" % (sx, sz), 0.28, leg_h,
                                 (sx * (MW * 0.5 - 1.0), leg_h * 0.5, sz * (MD * 0.5 - 1.0)),
                                 axis="y", seg=12, bevel=0.02))
            parts.append(_box("_Foot%d%d" % (sx, sz), (1.1, 0.30, 1.1),
                              (sx * (MW * 0.5 - 1.0), 0.15, sz * (MD * 0.5 - 1.0)), bev=0.02))
    y0 = leg_h
    parts.append(_box("_Module", (MW, MH, MD), (0, y0 + MH * 0.5, 0), bev=0.04))
    # 波纹壁板
    for i in range(13):
        px = (i / 12.0 - 0.5) * MW
        parts.append(_box("_RibF%d" % i, (0.14, MH, 0.20), (px, y0 + MH * 0.5, -MD * 0.5 - 0.09), bev=0.010))
    # 圆顶(雷达罩:半球多层环)
    dx, dz = -MW * 0.5 - 2.6, 0.0
    parts.append(add_cyl("_DomeBase", 3.4, 1.0, (dx, y0 + MH + 0.50, dz), axis="y", seg=28, bevel=0.03))
    for i in range(9):
        t = i / 8.0
        r = 3.30 * math.cos(t * math.pi * 0.5)
        y = y0 + MH + 1.0 + 3.2 * math.sin(t * math.pi * 0.5)
        parts.append(add_cyl("_Dome%d" % i, r, 0.46, (dx, y, dz), axis="y", seg=28, bevel=0.015))
    parts.append(add_cyl("_DomeFin", 0.12, 0.9, (dx, y0 + MH + 4.5, dz), axis="y", seg=8))
    # 主站房顶:设备 + 天线阵 + 积雪
    parts.append(_box("_RoofDeck", (MW, 0.18, MD), (0, y0 + MH + 0.10, 0), bev=0.02))
    parts.append(_box("_RoofSnow", (MW - 0.4, 0.20, MD - 0.4), (0, y0 + MH + 0.26, 0), bev=0.08))
    for i in range(5):
        parts.append(add_cyl("_Ant%d" % i, 0.04, 2.4 + (i % 3) * 0.8,
                             (-4.0 + i * 2.0, y0 + MH + 1.4, MD * 0.5 - 1.2), axis="y", seg=6))
    for i in range(2):
        parts.append(_box("_HVAC%d" % i, (1.5, 0.75, 1.1), (-3.0 + i * 5.0, y0 + MH + 0.70, -MD * 0.5 + 1.4), bev=0.025))
    # 太阳能板阵列(倾斜板 + 支架)
    for i in range(4):
        px = 4.0 + (i % 2) * 2.6
        pz = -2.4 + (i // 2) * 3.2
        parts.append(_box("_Panel%d" % i, (2.3, 0.10, 1.5), (px + MW * 0.5 + 1.5, 1.55, pz),
                          bev=0.012, rot=(-0.52, 0, 0)))
        parts.append(_box("_PanelF%d" % i, (2.42, 0.07, 1.62), (px + MW * 0.5 + 1.5, 1.50, pz),
                          bev=0.010, rot=(-0.52, 0, 0)))
        for s in (-1, 1):
            parts.append(_box("_PanelL%d_%d" % (i, s), (0.10, 1.30, 0.10),
                              (px + MW * 0.5 + 1.5 + s * 0.9, 0.90, pz + 0.35), bev=0.008))
    # 连廊(通往圆顶的管道走廊)
    parts.append(add_cyl("_Corridor", 1.05, MW * 0.5 + 2.6, (dx * 0.5, y0 + MH * 0.55, dz),
                         axis="x", seg=16, bevel=0.025))
    for i in range(4):
        parts.append(add_cyl("_CorrRing%d" % i, 1.12, 0.12,
                             (dx * 0.5 - 2.0 + i * 1.4, y0 + MH * 0.55, dz), axis="x", seg=16, bevel=0.012))
    # 舷梯 + 平台 + 栏杆
    for i in range(8):
        parts.append(_box("_Step%d" % i, (1.8, 0.16, 0.42),
                          (2.5, 0.12 + i * 0.19, -MD * 0.5 - 1.0 - i * 0.42), bev=0.010))
    parts.append(_box("_Landing", (2.4, 0.16, 1.6), (2.5, y0 + 0.08, -MD * 0.5 - 1.9), bev=0.012))
    parts.append(_box("_LandR", (2.4, 0.07, 0.07), (2.5, y0 + 1.12, -MD * 0.5 - 2.6), bev=0.008))
    for s in (-1, 1):
        parts.append(_box("_LandP%d" % s, (0.07, 1.05, 0.07), (2.5 + s * 1.15, y0 + 0.60, -MD * 0.5 - 2.6), bev=0.006))
    parts.append(_box("_DoorF", (1.6, 2.3, 0.30), (2.5, y0 + 1.25, -MD * 0.5 + 0.05), bev=0.02))
    # 舷窗 ×4(暖光)
    for i in range(4):
        parts.append(add_cyl("_Porthole%d" % i, 0.42, 0.12,
                             (-4.2 + i * 2.8, y0 + MH * 0.62, -MD * 0.5 - 0.14), axis="z", seg=16, bevel=0.015))
    # 旗杆 + 风向标
    parts.append(add_cyl("_FlagPole", 0.06, 6.0, (-6.5, 3.0, 3.5), axis="y", seg=8))
    parts.append(_box("_FlagCloth", (1.5, 0.9, 0.05), (-5.72, 5.30, 3.5), bev=0.015))
    parts.append(_box("_WindVane", (0.70, 0.05, 0.05), (-6.5, 6.15, 3.5), bev=0.006))
    rules = [
        ("_Leg", "metal"), ("_Foot", "metal"), ("_Module", "station_panel"), ("_Rib", "metal"),
        ("_DomeBase", "metal"), ("_Dome", "radome"), ("_DomeFin", "metal"),
        ("_RoofDeck", "metal"), ("_RoofSnow", "snow"), ("_Ant", "metal"), ("_HVAC", "metal"),
        ("_Panel", "solar"), ("_PanelF", "solar"), ("_PanelL", "metal"),
        ("_Corridor", "station_panel"), ("_CorrRing", "metal"),
        ("_Step", "metal"), ("_Landing", "metal"), ("_LandR", "metal"), ("_LandP", "metal"),
        ("_DoorF", "trim"), ("_Porthole", "lamp_warm"),
        ("_FlagPole", "metal"), ("_FlagCloth", "sign"), ("_WindVane", "metal"),
    ]
    return _finish("Prop_snow_station", parts, rules)


# ============================================================ 龙门吊
def build_harbor_crane():
    reset()
    parts = []
    SPAN, HGT = 26.0, 22.0
    # 海侧/陆侧支腿(门架)
    for sx in (-1, 1):
        parts.append(_box("_LegF%d" % sx, (1.5, HGT, 1.8), (sx * SPAN * 0.42, HGT * 0.5 + 2.0, 6.5), bev=0.035))
        parts.append(_box("_LegB%d" % sx, (1.5, HGT, 1.8), (sx * SPAN * 0.42, HGT * 0.5 + 2.0, -6.5), bev=0.035))
        # 支腿斜撑 + 横撑
        for i in range(3):
            y = 4.0 + i * 5.5
            parts.append(_box("_Brace%d_%d" % (sx, i), (0.30, 0.30, 13.0), (sx * SPAN * 0.42, y, 0), bev=0.018))
        parts.append(_box("_Diag%d" % sx, (1.2, 15.0, 0.30), (sx * SPAN * 0.42, 11.0, 6.0), bev=0.020,
                          rot=(0.20, 0, 0)))
        parts.append(_box("_DiagB%d" % sx, (1.2, 15.0, 0.30), (sx * SPAN * 0.42, 11.0, -6.0), bev=0.020,
                          rot=(-0.20, 0, 0)))
    # 行走台车(4 组轮 + 横梁)
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Bogie%d%d" % (sx, sz), (2.4, 1.4, 3.0),
                              (sx * SPAN * 0.42, 1.0, sz * 6.5), bev=0.025))
            for k in range(3):
                parts.append(add_cyl("_Wheel%d%d%d" % (sx, sz, k), 0.55, 0.40,
                                     (sx * SPAN * 0.42, 0.55, sz * 6.5 - 1.0 + k * 1.0),
                                     axis="x", seg=14, bevel=0.02))
    # 顶部主梁(双箱梁)
    parts.append(_box("_GirderF", (SPAN + 6.0, 2.2, 1.6), (0, HGT + 3.0, 6.5), bev=0.04))
    parts.append(_box("_GirderB", (SPAN + 6.0, 2.2, 1.6), (0, HGT + 3.0, -6.5), bev=0.04))
    parts.append(_box("_GirderTop", (SPAN + 6.0, 0.30, 13.0), (0, HGT + 4.20, 0), bev=0.03))
    # 前伸大梁(海侧悬臂 + 拉杆)
    parts.append(_box("_Boom", (SPAN + 6.0, 1.8, 1.5), (0, HGT + 3.0, -16.0), bev=0.035))
    parts.append(_box("_BoomTip", (SPAN + 6.0, 1.2, 0.6), (0, HGT + 3.4, -22.5), bev=0.03))
    for s in (-1, 1):
        parts.append(_box("_Tie%d" % s, (0.35, 0.35, 26.0), (s * SPAN * 0.42, HGT + 7.0, -8.0),
                          bev=0.015, rot=(0.42, 0, 0)))
    # A 字架(顶部塔架 + 拉杆)
    for s in (-1, 1):
        parts.append(_box("_AFrame%d" % s, (0.55, 9.0, 0.55), (s * SPAN * 0.42, HGT + 8.0, 0), bev=0.025,
                          rot=(0, 0, -s * 0.16)))
    parts.append(_box("_AFrameTop", (SPAN * 0.86, 0.60, 1.0), (0, HGT + 12.6, 0), bev=0.025))
    # 司机室(悬吊小车下方)
    parts.append(_box("_Cab", (2.6, 2.6, 2.4), (SPAN * 0.20, HGT - 1.2, -13.0), bev=0.03))
    parts.append(_box("_CabG", (2.3, 1.5, 0.10), (SPAN * 0.20, HGT - 1.0, -14.25), bev=0.018))
    parts.append(_box("_CabTop", (2.9, 0.20, 2.7), (SPAN * 0.20, HGT + 0.20, -13.0), bev=0.02))
    # 小车(沿梁行走) + 起升钢丝绳 + 吊具(集装箱吊架)
    parts.append(_box("_Trolley", (5.0, 1.5, 14.5), (0, HGT + 4.9, -14.0), bev=0.03))
    for k in range(4):
        parts.append(add_cyl("_TRoller%d" % k, 0.42, 0.34, (-1.8 + k * 1.2, HGT + 5.8, -14.0),
                             axis="x", seg=12, bevel=0.015))
    for s in (-1, 1):
        parts.append(_box("_Cable%d" % s, (0.07, 15.0, 0.07),
                          (s * 1.8, HGT - 2.5, -14.0), bev=0.006))
    parts.append(_box("_Spreader", (7.0, 0.55, 2.8), (0, HGT - 10.0, -14.0), bev=0.03))
    for s in (-1, 1):
        parts.append(_box("_SHead%d" % s, (0.55, 0.75, 0.75), (s * 3.1, HGT - 10.0, -14.0), bev=0.02))
    # 吊着的集装箱(吊具下方)
    if True:
        parts.append(_box("_Container", (6.1, 2.6, 2.45), (0, HGT - 13.2, -14.0), bev=0.03))
        for i in range(9):
            parts.append(_box("_ContRib%d" % i, (0.09, 2.4, 0.09),
                              (-2.7 + i * 0.68, HGT - 13.2, -14.0 - 1.25), bev=0.006))
    # 梯子 + 平台(支腿内侧)
    parts += _ladder("_Acc", SPAN * 0.42 - 1.4, 2.0, HGT + 2.0, 6.5, w=0.62)
    for i in range(4):
        parts.append(_box("_Plat%d" % i, (2.0, 0.14, 2.4),
                          (SPAN * 0.42 - 2.4, 4.0 + i * 5.0, 6.5), bev=0.012))
    rules = [
        ("_Leg", "crane_steel"), ("_Brace", "crane_steel"), ("_Diag", "crane_steel"),
        ("_Bogie", "crane_steel"), ("_Wheel", "tire"),
        ("_Girder", "crane_steel"), ("_GirderTop", "crane_steel"),
        ("_Boom", "crane_steel"), ("_BoomTip", "crane_steel"), ("_Tie", "crane_steel"),
        ("_AFrame", "crane_steel"), ("_AFrameTop", "crane_steel"),
        ("_Cab", "crane_steel"), ("_CabG", "glass"), ("_CabTop", "crane_steel"),
        ("_Trolley", "crane_steel"), ("_TRoller", "metal"), ("_Cable", "metal"),
        ("_Spreader", "sign"), ("_SHead", "crane_steel"),
        ("_Container", "container"), ("_ContRib", "container"),
        ("_Acc_Rail", "metal"), ("_Acc_Rung", "metal"), ("_Acc", "metal"), ("_Plat", "metal"),
    ]
    return _finish("Prop_harbor_crane", parts, rules)


# ============================================================ 货轮
def build_harbor_ship():
    reset()
    parts = []
    L, W, H = 46.0, 12.0, 7.0
    hw, zf, zb = W * 0.5, -L * 0.5, L * 0.5
    # 船体(主箱体 + 船首尖 + 船尾)
    parts.append(_box("_Hull", (W, H, L * 0.80), (0, 2.2, 0), bev=0.05))
    # 船首(楔形:多段渐收)
    for i in range(6):
        t = i / 5.0
        parts.append(_box("_Bow%d" % i, (W * (1.0 - t * 0.78), H * (1.0 - t * 0.30), L * 0.075),
                          (0, 2.2 - t * 0.55, zf + L * 0.10 - t * L * 0.09), bev=0.04))
    parts.append(_box("_BowTip", (0.6, 2.2, 1.6), (0, 1.35, zf + 0.3), bev=0.03))
    # 船尾 + 舵 + 螺旋桨
    parts.append(_box("_Stern", (W * 0.92, H * 0.86, L * 0.09), (0, 2.35, zb - L * 0.045), bev=0.04))
    parts.append(_box("_Rudder", (0.5, 3.2, 2.4), (0, -0.30, zb + 0.9), bev=0.03, rot=(0.10, 0, 0)))
    parts.append(add_cyl("_Prop", 1.5, 0.55, (0, 0.55, zb + 1.9), axis="z", seg=16, bevel=0.03))
    for k in range(4):
        a = k * math.tau / 4.0
        parts.append(_box("_PropBlade%d" % k, (0.22, 1.5, 0.55),
                          (math.sin(a) * 0.85, 0.55 + math.cos(a) * 0.85, zb + 1.9),
                          bev=0.03, rot=(a, 0, 0.35)))
    # 舷墙(主甲板围栏)
    for s in (-1, 1):
        parts.append(_box("_Bulwark%d" % s, (0.35, 1.5, L * 0.80), (s * (hw - 0.18), 6.45, 0), bev=0.025))
        for i in range(14):
            parts.append(_box("_BulPost%d_%d" % (s, i), (0.45, 0.30, 0.28),
                              (s * (hw - 0.18), 7.05, -L * 0.38 + i * (L * 0.058)), bev=0.012))
    # 主甲板 + 舱口盖
    parts.append(_box("_Deck", (W - 0.7, 0.30, L * 0.78), (0, 5.85, 0), bev=0.03))
    for i in range(4):
        parts.append(_box("_Hatch%d" % i, (W - 2.6, 0.32, L * 0.15),
                          (0, 6.12, -L * 0.28 + i * (L * 0.155)), bev=0.025))
        for k in range(3):
            parts.append(_box("_HatchRib%d_%d" % (i, k), (W - 2.8, 0.10, 0.20),
                              (0, 6.30, -L * 0.28 + i * (L * 0.155) - L * 0.05 + k * (L * 0.05)), bev=0.008))
    # 集装箱堆(甲板上 3 堆 ×3 层)
    cols = ["container", "container_alt", "container_red"]
    for i in range(5):
        for j in range(3):
            cx = -3.2 + (i % 2) * 6.4
            cz = -L * 0.24 + (i // 2) * 7.5
            parts.append(_box("_Cont%d_%d" % (i, j), (6.0, 2.55, 2.42),
                              (cx, 7.85 + j * 2.60, cz), bev=0.03))
            for k in range(7):
                parts.append(_box("_CRib%d_%d_%d" % (i, j, k), (0.09, 2.35, 0.09),
                                  (cx - 2.6 + k * 0.87, 7.85 + j * 2.60, cz - 1.24), bev=0.006))
    # 舰桥(上层建筑,在船尾)
    by = 5.85
    parts.append(_box("_Bridge0", (W - 1.4, 3.2, 9.0), (0, by + 1.70, zb - 8.0), bev=0.035))
    parts.append(_box("_Bridge1", (W - 2.4, 3.0, 7.0), (0, by + 4.80, zb - 8.5), bev=0.035))
    parts.append(_box("_Bridge2", (W - 3.6, 2.8, 5.4), (0, by + 7.70, zb - 8.8), bev=0.035))
    # 舰桥窗(环绕)
    parts.append(_box("_BridgeWin", (W - 1.8, 1.25, 0.10), (0, by + 8.30, zb - 11.45), bev=0.020))
    for s in (-1, 1):
        parts.append(_box("_BridgeWinS%d" % s, (0.10, 1.15, 4.6),
                          (s * (W * 0.5 - 1.85), by + 8.25, zb - 8.8), bev=0.015))
    # 驾驶台顶(桅杆 + 雷达 + 灯)
    parts.append(_box("_BridgeTop", (W - 3.0, 0.30, 5.8), (0, by + 9.25, zb - 8.8), bev=0.025))
    parts.append(add_cyl("_Mast", 0.20, 8.0, (0, by + 13.2, zb - 8.8), axis="y", seg=10, bevel=0.02))
    for k in range(3):
        parts.append(_box("_Yard%d" % k, (5.0 - k * 0.8, 0.10, 0.10), (0, by + 11.0 + k * 1.5, zb - 8.8), bev=0.008))
    parts.append(add_cyl("_Radar", 1.1, 0.10, (0, by + 16.0, zb - 8.8), axis="x", seg=16, bevel=0.015))
    parts.append(_box("_NavLight", (0.30, 0.30, 0.30), (0, by + 17.4, zb - 8.8), bev=0.03))
    # 烟囱
    parts.append(add_cyl("_Funnel", 1.9, 5.0, (0, by + 10.2, zb - 13.5), axis="y", seg=18, taper=0.90, bevel=0.03))
    parts.append(_box("_FunnelCap", (4.4, 0.35, 4.4), (0, by + 12.7, zb - 13.5), bev=0.03))
    for i in range(3):
        parts.append(add_cyl("_FunnelBand%d" % i, 1.98 - i * 0.05, 0.22, (0, by + 8.6 + i * 1.3, zb - 13.5),
                             axis="y", seg=18, bevel=0.015))
    # 克令吊(甲板起重机 ×2)
    for i in range(2):
        cx = 0.0
        cz = -L * 0.16 + i * 9.0
        parts.append(add_cyl("_CraneBase%d" % i, 1.3, 1.6, (cx, 7.00, cz), axis="y", seg=16, bevel=0.03))
        parts.append(add_cyl("_CranePost%d" % i, 0.55, 5.5, (cx, 10.4, cz), axis="y", seg=12, bevel=0.02))
        parts.append(_box("_CraneJib%d" % i, (0.55, 0.55, 11.0), (cx, 13.0, cz - 4.6), bev=0.025,
                          rot=(0.30, 0, 0)))
        parts.append(_box("_CraneCab%d" % i, (1.6, 1.7, 1.5), (cx + 1.3, 10.0, cz), bev=0.025))
        parts.append(_box("_CraneHook%d" % i, (0.06, 6.5, 0.06), (cx, 10.0, cz - 9.4), bev=0.006))
    # 舷梯 + 缆桩 + 导缆孔
    parts.append(_box("_Gangway", (1.4, 0.22, 9.0), (hw + 1.6, 4.60, 6.0), bev=0.020, rot=(0, 0, -0.62)))
    for s in (-1, 1):
        parts.append(_box("_GangRail%d" % s, (0.08, 1.0, 9.0), (hw + 1.6 + s * 0.66, 5.10, 6.0),
                          bev=0.008, rot=(0, 0, -0.62)))
    for i in range(6):
        parts.append(add_cyl("_Bollard%d" % i, 0.28, 0.85,
                             ((1 if i % 2 else -1) * (hw - 0.7), 6.30, -L * 0.30 + i * 4.4),
                             axis="y", seg=12, bevel=0.02))
    # 船名 + 吃水线
    parts.append(_box("_Name", (5.0, 1.4, 0.10), (0, 4.4, zf + 5.0), bev=0.015))
    parts.append(_box("_Waterline", (W + 0.05, 0.30, L * 0.80), (0, 0.60, 0), bev=0.015))
    rules = [
        ("_Hull", "ship_hull"), ("_Bow", "ship_hull"), ("_BowTip", "ship_hull"),
        ("_Stern", "ship_hull"), ("_Rudder", "ship_hull"), ("_Prop", "chrome"), ("_PropBlade", "chrome"),
        ("_Bulwark", "ship_hull"), ("_BulPost", "ship_hull"),
        ("_Deck", "ship_deck"), ("_Hatch", "ship_deck"), ("_HatchRib", "ship_deck"),
        ("_Cont", "container"), ("_CRib", "container"),
        ("_Bridge", "ship_super"), ("_BridgeWin", "glass"), ("_BridgeWinS", "glass"),
        ("_BridgeTop", "ship_deck"), ("_Mast", "metal"), ("_Yard", "metal"),
        ("_Radar", "metal"), ("_NavLight", "sign"),
        ("_Funnel", "ship_super"), ("_FunnelCap", "sign"), ("_FunnelBand", "sign"),
        ("_CraneBase", "crane_steel"), ("_CranePost", "crane_steel"), ("_CraneJib", "crane_steel"),
        ("_CraneCab", "crane_steel"), ("_CraneHook", "metal"),
        ("_Gangway", "metal"), ("_GangRail", "metal"), ("_Bollard", "metal"),
        ("_Name", "sign"), ("_Waterline", "sign"),
    ]
    return _finish("Prop_harbor_ship", parts, rules)


# ============================================================ 码头仓库
def build_harbor_shed():
    reset()
    parts = []
    W, D, H = 26.0, 16.0, 9.0
    # 码头平台(混凝土 + 护木 + 系船柱)
    parts.append(_box("_Quay", (W + 6.0, 2.8, D + 8.0), (0, -1.30, 2.0), bev=0.035))
    parts.append(_box("_QuayEdge", (W + 6.0, 0.35, 0.5), (0, 0.10, -6.0), bev=0.03))
    for i in range(6):
        px = -W * 0.42 + i * (W * 0.17)
        parts.append(add_cyl("_Bollard%d" % i, 0.30, 1.0, (px, 0.50, -5.4), axis="y", seg=12, bevel=0.025))
        parts.append(_box("_Fender%d" % i, (0.7, 1.4, 0.45), (px, -0.30, -6.15), bev=0.06))
    # 仓库主体
    parts.append(_box("_Base", (W + 0.8, 2.1, D + 0.8), (0, -0.55, 0), bev=0.03))
    parts.append(_box("_Body", (W, H, D), (0, 0.5 + H * 0.5, 0), bev=0.045))
    # 波纹壁板(竖向)
    for i in range(int(W / 1.1) + 1):
        px = -W * 0.5 + i * 1.1
        if px > W * 0.5:
            break
        parts.append(_box("_RibF%d" % i, (0.15, H, 0.24), (px, 0.5 + H * 0.5, -D * 0.5 - 0.10), bev=0.012))
        parts.append(_box("_RibB%d" % i, (0.15, H, 0.24), (px, 0.5 + H * 0.5, D * 0.5 + 0.10), bev=0.012))
    # 屋顶(双坡 + 采光带 + 屋脊通风)
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (W * 0.55 + 0.9, 0.30, D + 1.4),
                          (s * (W * 0.245), 0.5 + H + 1.35, 0), bev=0.035, rot=(0, 0, -s * 0.28)))
        parts.append(_box("_Sky%d" % s, (W * 0.30, 0.12, D - 3.0),
                          (s * (W * 0.20), 0.5 + H + 2.40, 0), bev=0.02, rot=(0, 0, -s * 0.28)))
    parts.append(_box("_Gable", (0.6, 2.8, D + 1.4), (0, 0.5 + H + 1.35, 0), bev=0.035))
    for i in range(5):
        parts.append(_box("_Vent%d" % i, (1.7, 0.70, 1.0),
                          (-W * 0.32 + i * (W * 0.16), 0.5 + H + 3.0, 0), bev=0.025))
    # 卷帘门 ×4(临水面) + 装卸平台
    for i in range(4):
        dx = -W * 0.36 + i * (W * 0.24)
        parts.append(_box("_DoorF%d" % i, (4.6, 5.2, 0.26), (dx, 3.1, -D * 0.5 + 0.07), bev=0.025))
        parts.append(_box("_Door%d" % i, (4.2, 4.8, 0.14), (dx, 2.9, -D * 0.5 + 0.01), bev=0.020))
        for j in range(8):
            parts.append(_box("_Slat%d_%d" % (i, j), (4.1, 0.10, 0.18),
                              (dx, 0.85 + j * 0.55, -D * 0.5 + 0.02), bev=0.008))
        parts.append(_box("_DoorBox%d" % i, (4.9, 0.60, 0.60), (dx, 5.95, -D * 0.5 - 0.18), bev=0.02))
        parts.append(_box("_Dock%d" % i, (5.4, 0.95, 3.4), (dx, 0.98, -D * 0.5 - 1.8), bev=0.03))
        parts.append(_box("_DockE%d" % i, (5.4, 0.10, 0.16), (dx, 1.50, -D * 0.5 - 3.45), bev=0.012))
    # 装卸雨棚(门上方挑出)
    parts.append(_box("_Canopy", (W + 1.0, 0.28, 4.4), (0, 6.60, -D * 0.5 - 2.0), bev=0.03))
    for i in range(6):
        parts.append(_box("_CanopyT%d" % i, (0.10, 1.4, 3.8),
                          (-W * 0.42 + i * (W * 0.17), 6.05, -D * 0.5 - 2.0), bev=0.008, rot=(0.22, 0, 0)))
    # 侧墙高窗 + 排风管 + 落水管
    for i in range(6):
        wx = -W * 0.38 + i * (W * 0.152)
        parts.append(_box("_Win%d" % i, (1.6, 1.5, 0.14), (wx, 6.4, -D * 0.5 - 0.03), bev=0.015))
    for i in range(3):
        parts.append(add_cyl("_Duct%d" % i, 0.36, 6.0, (W * 0.5 - 3.0 - i * 7.0, 3.5, D * 0.5 + 0.60),
                             axis="y", seg=12, bevel=0.02))
        parts.append(_box("_DuctC%d" % i, (0.95, 0.55, 0.95),
                          (W * 0.5 - 3.0 - i * 7.0, 6.65, D * 0.5 + 0.60), bev=0.02))
    # 集装箱堆场(仓库侧)
    for i in range(4):
        for j in range(2):
            parts.append(_box("_Yard%d_%d" % (i, j), (6.1, 2.6, 2.45),
                              (-W * 0.36 + i * 6.4 + (j % 2) * 0.2, 1.30 + j * 2.62, D * 0.5 + 5.5), bev=0.03))
            for k in range(7):
                parts.append(_box("_YardRib%d_%d_%d" % (i, j, k), (0.09, 2.4, 0.09),
                                  (-W * 0.36 + i * 6.4 + (j % 2) * 0.2 - 2.7 + k * 0.9,
                                   1.30 + j * 2.62, D * 0.5 + 5.5 - 1.25), bev=0.006))
    rules = [
        ("_Quay", "concrete"), ("_QuayEdge", "concrete"), ("_Bollard", "metal"), ("_Fender", "tire"),
        ("_Base", "concrete"), ("_Body", "wall"), ("_Rib", "metal"),
        ("_Roof", "roof"), ("_Sky", "glass"), ("_Gable", "wall"), ("_Vent", "metal"),
        ("_DoorF", "trim"), ("_Door", "metal"), ("_Slat", "metal"), ("_DoorBox", "metal"),
        ("_Dock", "concrete"), ("_DockE", "trim"),
        ("_Canopy", "metal"), ("_CanopyT", "metal"),
        ("_Win", "glass"), ("_Duct", "metal"), ("_DuctC", "metal"),
        ("_Yard", "container"), ("_YardRib", "container"),
    ]
    return _finish("Prop_harbor_shed", parts, rules)


# ============================================================ BR 农舍
def build_br_farmhouse():
    reset()
    parts = []
    # --- 主房(两层坡顶 + 门廊)
    FW, FD, FH = 11.0, 8.5, 6.2
    parts.append(_box("_FBase", (FW + 0.8, 2.2, FD + 0.8), (0, -0.50, 0), bev=0.03))
    parts.append(_box("_House", (FW, FH, FD), (0, 0.6 + FH * 0.5, 0), bev=0.04))
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (FW * 0.60 + 1.2, 0.28, FD + 1.4),
                          (s * (FW * 0.23), 0.6 + FH + 1.30, 0), bev=0.035, rot=(0, 0, -s * 0.50)))
    parts.append(_box("_Ridge", (0.48, 0.42, FD + 1.4), (0, 0.6 + FH + 2.45, 0), bev=0.03))
    parts.append(_box("_GableF", (FW + 0.2, 2.5, 0.35), (0, 0.6 + FH + 0.90, -FD * 0.5 - 0.10), bev=0.03))
    # 门廊(柱 + 顶 + 台阶 + 栏杆)
    parts.append(_box("_Porch", (FW + 1.0, 0.22, 2.6), (0, 3.30, -FD * 0.5 - 1.30), bev=0.02))
    for i in range(4):
        px = -FW * 0.42 + i * (FW * 0.28)
        parts.append(add_cyl("_PCol%d" % i, 0.19, 3.2, (px, 1.90, -FD * 0.5 - 2.40), axis="y", seg=12, bevel=0.015))
        parts.append(_box("_PColCap%d" % i, (0.52, 0.22, 0.52), (px, 3.62, -FD * 0.5 - 2.40), bev=0.012))
    parts.append(_box("_PorchRail", (FW + 0.6, 0.08, 0.08), (0, 4.05, -FD * 0.5 - 2.55), bev=0.006))
    parts.append(_box("_PorchRoof", (FW + 1.4, 0.24, 3.2), (0, 3.62, -FD * 0.5 - 1.20), bev=0.025,
                      rot=(0.14, 0, 0)))
    for i in range(3):
        parts.append(_box("_PStep%d" % i, (3.4, 0.22, 0.50), (0, 0.60 - i * 0.22, -FD * 0.5 - 2.90 - i * 0.46), bev=0.012))
    # 窗(上下各 3)
    for i in range(3):
        wx = -3.4 + i * 3.4
        parts.append(_box("_WinD%d" % i, (1.5, 1.6, 0.16), (wx, 2.30, -FD * 0.5 - 0.06), bev=0.02))
        parts.append(_box("_WinDG%d" % i, (1.25, 1.3, 0.06), (wx, 2.30, -FD * 0.5 - 0.14), bev=0.015))
        parts.append(_box("_WinU%d" % i, (1.4, 1.4, 0.16), (wx, 5.60, -FD * 0.5 - 0.06), bev=0.02))
        parts.append(_box("_WinUG%d" % i, (1.15, 1.15, 0.06), (wx, 5.60, -FD * 0.5 - 0.14), bev=0.015))
        parts.append(_box("_WinSill%d" % i, (1.75, 0.12, 0.34), (wx, 1.48, -FD * 0.5 - 0.16), bev=0.012))
    parts.append(_box("_Door", (1.5, 2.5, 0.18), (0, 1.85, -FD * 0.5 - 0.05), bev=0.022))
    # 烟囱
    parts.append(_box("_Chim", (1.2, 3.2, 1.2), (3.4, 0.6 + FH + 2.30, 1.8), bev=0.03))
    parts.append(_box("_ChimCap", (1.45, 0.24, 1.45), (3.4, 0.6 + FH + 4.00, 1.8), bev=0.02))
    # --- 谷仓(红色大坡顶 + 白色交叉门)
    bx, bz = 16.0, 2.0
    BW, BD, BH = 10.0, 12.0, 6.5
    parts.append(_box("_Barn", (BW, BH, BD), (bx, BH * 0.5, bz), bev=0.045))
    for s in (-1, 1):
        parts.append(_box("_BRoof%d" % s, (BW * 0.62 + 1.0, 0.28, BD + 1.2),
                          (bx + s * (BW * 0.24), BH + 1.55, bz), bev=0.035, rot=(0, 0, -s * 0.56)))
    parts.append(_box("_BRidge", (0.50, 0.45, BD + 1.2), (bx, BH + 2.85, bz), bev=0.03))
    # 白色十字装饰门
    parts.append(_box("_BDoorH", (4.6, 0.42, 0.16), (bx, 1.30, bz - BD * 0.5 - 0.06), bev=0.02))
    parts.append(_box("_BDoorV", (0.42, 4.6, 0.16), (bx, 1.30, bz - BD * 0.5 - 0.06), bev=0.02))
    parts.append(_box("_BDoorF", (3.6, 3.6, 0.14), (bx, 1.80, bz - BD * 0.5 - 0.02), bev=0.025))
    # 阁楼窗 + 干草吊臂
    parts.append(_box("_BLoft", (1.3, 1.3, 0.16), (bx, BH + 0.4, bz - BD * 0.5 - 0.06), bev=0.02))
    parts.append(_box("_BBeam", (0.24, 0.24, 1.6), (bx, BH + 2.1, bz - BD * 0.5 - 0.90), bev=0.012))
    parts.append(add_cyl("_BPulley", 0.20, 0.14, (bx, BH + 2.0, bz - BD * 0.5 - 1.55), axis="x", seg=12, bevel=0.01))
    # --- 筒仓 ×2(圆柱 + 锥顶)
    for k in range(2):
        sx = 7.0 + k * 4.4
        sz = -9.0
        parts.append(add_cyl("_Silo%d" % k, 2.1, 11.0, (sx, 5.50, sz), axis="y", seg=22, bevel=0.04))
        for i in range(4):
            parts.append(add_cyl("_SiloRing%d_%d" % (k, i), 2.16, 0.14, (sx, 2.0 + i * 2.6, sz),
                                 axis="y", seg=22, bevel=0.012))
        parts.append(add_cyl("_SiloTop%d" % k, 2.15, 2.2, (sx, 12.10, sz), axis="y", seg=22,
                             taper=0.06, bevel=0.035))
        parts.append(add_cyl("_SiloCap%d" % k, 0.35, 0.55, (sx, 13.45, sz), axis="y", seg=10, bevel=0.015))
        parts += _ladder("_SL%d" % k, sx - 2.35, 0.0, 11.0, sz, w=0.55)
    # --- 风车(塔 + 叶片)
    wx2, wz2 = -12.0, -8.0
    parts.append(add_cyl("_WTower", 0.55, 8.0, (wx2, 4.0, wz2), axis="y", seg=12, taper=0.55, bevel=0.025))
    for i in range(3):
        parts.append(add_cyl("_WBand%d" % i, 0.60 - i * 0.08, 0.14, (wx2, 1.6 + i * 2.4, wz2),
                             axis="y", seg=12, bevel=0.010))
    parts.append(add_cyl("_WHub", 0.28, 0.42, (wx2, 8.2, wz2 - 0.45), axis="z", seg=14, bevel=0.015))
    for k in range(12):
        a = k * math.tau / 12.0
        # 叶片在竖直 XY 面内辐射:长轴沿 Godot Y,绕 Godot Z 转 a(原混入偏航轴导致叶片束成一排)
        parts.append(_box("_WBlade%d" % k, (0.14, 2.3, 0.07),
                          (wx2 + math.sin(a) * 1.35, 8.2 + math.cos(a) * 1.35, wz2 - 0.62),
                          bev=0.008, rot=(0, 0, a)))
    # --- 围栏(木桩 + 横杆)
    for i in range(16):
        px = -14.0 + i * 2.0
        if abs(px) < 6.0:
            continue
        parts.append(_box("_FenceP%d" % i, (0.12, 1.25, 0.12), (px, 0.62, 8.5), bev=0.008))
    for j in range(2):
        parts.append(_box("_FenceR%d" % j, (28.0, 0.09, 0.09), (0, 0.55 + j * 0.55, 8.5), bev=0.006))
    rules = [
        ("_FBase", "concrete"), ("_House", "farm_wall"), ("_Roof", "farm_roof"), ("_Ridge", "farm_roof"),
        ("_Gable", "farm_wall"), ("_Porch", "wood"), ("_PCol", "wood"), ("_PColCap", "wood"),
        ("_PorchRail", "wood"), ("_PorchRoof", "farm_roof"), ("_PStep", "concrete"),
        ("_WinD", "wood"), ("_WinDG", "lamp_warm"), ("_WinU", "wood"), ("_WinUG", "glass"),
        ("_WinSill", "wood"), ("_Door", "wood"),
        ("_Chim", "brick"), ("_ChimCap", "brick"),
        ("_Barn", "barn_red"), ("_BRoof", "farm_roof"), ("_BRidge", "farm_roof"),
        ("_BDoorH", "barn_white"), ("_BDoorV", "barn_white"), ("_BDoorF", "barn_red"),
        ("_BLoft", "wood"), ("_BBeam", "wood"), ("_BPulley", "metal"),
        ("_Silo", "silo"), ("_SiloRing", "metal"), ("_SiloTop", "silo"), ("_SiloCap", "metal"),
        ("_SL_Rail", "metal"), ("_SL_Rung", "metal"), ("_SL", "metal"),
        ("_WTower", "metal"), ("_WBand", "metal"), ("_WHub", "metal"), ("_WBlade", "metal"),
        ("_FenceP", "wood"), ("_FenceR", "wood"),
    ]
    return _finish("Prop_br_farmhouse", parts, rules)


# ============================================================ BR 乡村教堂
def build_br_church():
    reset()
    parts = []
    # 台基
    parts.append(_box("_Plinth", (11.0, 2.15, 20.0), (0, -0.525, 0), bev=0.03))
    # 中殿
    NW, ND, NH = 8.0, 14.0, 6.0
    parts.append(_box("_Nave", (NW, NH, ND), (0, 0.55 + NH * 0.5, 3.0), bev=0.04))
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (NW * 0.60 + 0.9, 0.26, ND + 1.2),
                          (s * (NW * 0.23), 0.55 + NH + 1.10, 3.0), bev=0.03, rot=(0, 0, -s * 0.62)))
    parts.append(_box("_Ridge", (0.42, 0.38, ND + 1.2), (0, 0.55 + NH + 2.25, 3.0), bev=0.028))
    # 侧窗(尖拱窗 ×4 每侧)
    for i in range(4):
        zc = -2.0 + i * 3.0
        for s in (-1, 1):
            parts.append(_box("_Win%d_%d" % (i, s), (0.13, 2.6, 1.1),
                              (s * (NW * 0.5 + 0.04), 3.40, zc), bev=0.015))
            parts.append(_box("_WinArc%d_%d" % (i, s), (0.13, 0.55, 1.1),
                              (s * (NW * 0.5 + 0.04), 4.90, zc), bev=0.015, rot=(0, 0, s * 0.0)))
            parts.append(_box("_WinSill%d_%d" % (i, s), (0.30, 0.10, 1.35),
                              (s * (NW * 0.5 + 0.10), 2.05, zc), bev=0.012))
    # 钟楼(正面高塔 + 尖顶 + 十字)
    TW = 5.0
    tz = -ND * 0.5 - 2.2
    parts.append(_box("_Tower", (TW, 17.0, TW), (0, 8.50, tz), bev=0.04))
    parts.append(_box("_TBand1", (TW + 0.4, 0.34, TW + 0.4), (0, 5.0, tz), bev=0.025))
    parts.append(_box("_TBand2", (TW + 0.4, 0.34, TW + 0.4), (0, 12.0, tz), bev=0.025))
    parts.append(_box("_TBand3", (TW + 0.6, 0.44, TW + 0.6), (0, 17.0, tz), bev=0.028))
    # 钟室(开敞 + 柱 + 钟)
    parts.append(_box("_Belfry", (TW - 1.0, 3.2, TW - 1.0), (0, 14.90, tz), bev=0.03))
    for px in (-1, 1):
        for pz in (-1, 1):
            parts.append(_box("_BCol%d%d" % (px, pz), (0.40, 3.2, 0.40),
                              (px * (TW * 0.5 - 0.55), 14.90, tz + pz * (TW * 0.5 - 0.55)), bev=0.018))
    parts.append(add_cyl("_Bell", 0.68, 1.2, (0, 14.80, tz), axis="y", seg=14, taper=0.55, bevel=0.03))
    parts.append(add_cyl("_BellYoke", 0.07, 1.5, (0, 15.60, tz), axis="z", seg=8))
    # 尖顶(四棱锥 + 十字)
    parts.append(add_cyl("_Spire", TW * 0.74, 7.0, (0, 21.0, tz), axis="y", seg=4, taper=0.03, bevel=0.03))
    parts.append(_box("_CrossV", (0.17, 1.80, 0.17), (0, 25.6, tz), bev=0.02))
    parts.append(_box("_CrossH", (0.92, 0.17, 0.17), (0, 26.05, tz), bev=0.02))
    # 钟面
    parts.append(add_cyl("_Clock", 1.0, 0.18, (0, 10.5, tz - TW * 0.5 - 0.06), axis="z", seg=20, bevel=0.02))
    parts.append(_box("_ClockH", (0.09, 0.50, 0.09), (0, 10.70, tz - TW * 0.5 - 0.13), bev=0.010))
    parts.append(_box("_ClockM", (0.38, 0.09, 0.09), (0.20, 10.50, tz - TW * 0.5 - 0.13), bev=0.010))
    # 拱门廊 + 双开门
    parts += [add_cyl("_Arch", 1.5, 0.70, (0, 4.4, tz - TW * 0.5 - 0.30), axis="x", seg=18, bevel=0.02)[0]] \
        if False else []
    parts.append(add_cyl("_ArchTop", 1.45, 0.60, (0, 4.35, tz - TW * 0.5 - 0.25), axis="x", seg=18, bevel=0.02))
    for s in (-1, 1):
        parts.append(add_cyl("_PCol%d" % s, 0.24, 3.6, (s * 1.5, 2.10, tz - TW * 0.5 - 0.70),
                             axis="y", seg=12, bevel=0.015))
    parts.append(_box("_DoorF", (2.3, 3.3, 0.24), (0, 2.20, tz - TW * 0.5 + 0.06), bev=0.025))
    for s in (-1, 1):
        parts.append(_box("_Door%d" % s, (1.0, 2.9, 0.10), (s * 0.52, 2.00, tz - TW * 0.5), bev=0.020))
        for k in range(3):
            parts.append(_box("_DoorPanel%d_%d" % (s, k), (0.75, 0.65, 0.05),
                              (s * 0.52, 1.05 + k * 0.85, tz - TW * 0.5 - 0.06), bev=0.010))
    for i in range(3):
        parts.append(_box("_Step%d" % i, (3.2, 0.20, 0.48), (0, 0.65 - i * 0.20, tz - TW * 0.5 - 1.60 - i * 0.44), bev=0.012))
    # 墓地(墓碑群 + 围墙)
    for i in range(9):
        gx = -3.6 + (i % 5) * 1.8
        gz = 12.5 + (i // 5) * 2.4
        parts.append(_box("_Grave%d" % i, (0.62, 0.90 + (i % 3) * 0.16, 0.16), (gx, 1.00, gz), bev=0.025))
        parts.append(_box("_GraveT%d" % i, (0.46, 0.24, 0.10), (gx, 1.42 + (i % 3) * 0.16, gz - 0.10), bev=0.015))
    for s in (-1, 1):
        parts.append(_box("_Wall%d" % s, (0.35, 1.5, 12.0), (s * 5.2, 1.30, 12.0), bev=0.02))
    parts.append(_box("_WallB", (10.6, 1.5, 0.35), (0, 1.30, 18.2), bev=0.02))
    for i in range(6):
        parts.append(_box("_WallP%d" % i, (0.42, 1.85, 0.42), (-5.2 + i * 2.08, 0.92, 18.2), bev=0.015))
    rules = [
        ("_Plinth", "church_stone"), ("_Nave", "church_stone"), ("_Roof", "church_slate"),
        ("_Ridge", "church_slate"), ("_Win", "glass"), ("_WinArc", "glass"), ("_WinSill", "church_stone"),
        ("_Tower", "church_stone"), ("_TBand", "church_stone"),
        ("_Belfry", "church_stone"), ("_BCol", "church_stone"), ("_Bell", "metal"), ("_BellYoke", "metal"),
        ("_Spire", "church_slate"), ("_Cross", "gold"),
        ("_Clock", "trim"), ("_ClockH", "sign"), ("_ClockM", "sign"),
        ("_ArchTop", "church_stone"), ("_PCol", "church_stone"),
        ("_DoorF", "wood"), ("_Door", "wood"), ("_DoorPanel", "wood"), ("_Step", "church_stone"),
        ("_Grave", "church_stone"), ("_GraveT", "church_stone"),
        ("_Wall", "church_stone"), ("_WallB", "church_stone"), ("_WallP", "church_stone"),
    ]
    return _finish("Prop_br_church", parts, rules)


BUILDERS = {
    "jungle_temple": build_jungle_temple,
    "jungle_stilt": build_jungle_stilt,
    "snow_chalet": build_snow_chalet,
    "snow_station": build_snow_station,
    "harbor_crane": build_harbor_crane,
    "harbor_ship": build_harbor_ship,
    "harbor_shed": build_harbor_shed,
    "br_farmhouse": build_br_farmhouse,
    "br_church": build_br_church,
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
        print("[build] %-18s -> %s  (polys=%d)" % (pid, os.path.basename(path), len(ob.data.polygons)))
        ok.append(pid)
    print("\n[done] scene batch 2: %d/%d" % (len(ok), len(ids)))


if __name__ == "__main__":
    main()
