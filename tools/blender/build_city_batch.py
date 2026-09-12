"""
城市/场景 3A 级建筑与车辆批次(tools/blender/build_city_batch.py)
产出 models/props/{id}.glb —— 单一合并网格、多材质槽,Godot 侧按材质名重贴 PBR。

3A 建模准则(本批次严格遵守):
  * 分层构造 —— 基座(裙房/台阶)→ 主体(墙板+窗带)→ 檐口 → 屋顶(女儿墙+设备)
  * 倒角(bevel)—— 所有可见边缘倒角,消除"纸片/硬方盒"感
  * 细节部件 —— 窗框/窗台/门斗/雨棚/扶手/空调外机/管道/天线/招牌/台阶
  * 材质槽分离 —— wall/glass/trim/metal/roof/sign 六类,Godot 侧各自贴 PBR

模型清单(城市):
    city_hospital   医院(主楼+门诊裙房+急诊雨棚+十字标志+停机坪+坡道)
    city_shop       商铺(底部店招+橱窗+遮阳篷+空调外机+台阶)
    city_gas        加油站(双加油机+大顶棚+便利店+价格牌)
    city_mall       商场(玻璃幕墙裙房+主入口雨棚+顶层停车场)
    city_office     写字楼(玻璃幕墙+竖向装饰条+楼顶设备)
    city_church     教堂(钟楼+尖顶+十字+彩色玻璃+拱门)
    city_school     学校(教学楼+连廊+操场看台+旗杆)
    city_warehouse  仓库(波纹钢+卷帘门+装卸平台+排风管)
    city_hotel      酒店(塔楼+入口雨棚+招牌灯+阳台)
    city_police     警局(政务楼+蓝白条+旗杆+门廊柱)
    city_construct  工地(塔吊+脚手架+水泥管+围挡)
    city_park       小公园(喷泉+环形步道+长椅+树池)

坐标:根在地面 y=0,正面朝 -Z(与 Godot 前方一致),单位米。
用法: blender --background --python build_city_batch.py [-- city_hospital city_shop ...]
"""
import sys, os, math, random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/props"
random.seed(20260905)


# ============================================================ 基础工具
def _m(ob, name):
    """按名字打占位材质(GLB 携带材质名,Godot 侧重贴 PBR)"""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def _finish(name, parts, mat_rules):
    """按规则前缀给部件打材质名,再合并为单一多材质槽网格"""
    by_name = {}
    for ob in parts:
        by_name[ob.name] = ob
    for key, mname in mat_rules:
        for ob_name, ob in by_name.items():
            if ob_name.startswith(key):
                _m(ob, mname)
    return join_parts(name, parts)


def _box(name, size, pos, bev=0.02, rot=None):
    """带默认倒角的盒子(3A 感的关键:不要裸方盒)"""
    return add_box(name, size, pos, bevel=bev, rot_g=rot)


# ============================================================ 模块化构造件
def add_storey_slabs(prefix, w, d, y0, n_floor, floor_h, wall_t=0.18):
    """楼层外墙板:四面墙体,留出窗洞错位(用错位板模拟窗间墙)"""
    parts = []
    for i in range(n_floor):
        y = y0 + floor_h * (i + 0.5)
        # 前后墙(沿 x)
        for s in (-1, 1):
            parts.append(_box("%s_W%d_%d" % (prefix, i, s),
                              (w, floor_h * 0.34, wall_t),
                              (0, y + floor_h * 0.30, s * d * 0.5)))
        # 左右墙(沿 z)
        for s in (-1, 1):
            parts.append(_box("%s_E%d_%d" % (prefix, i, s),
                              (wall_t, floor_h * 0.34, d),
                              (s * w * 0.5, y + floor_h * 0.30, 0)))
    return parts


def add_glass_band(prefix, w, d, y, h, inset=0.06):
    """环形玻璃幕墙带(整层通长玻璃 + 竖向分隔条)"""
    parts = []
    gw, gd = w - inset, d - inset
    parts.append(_box("%s_GF" % prefix, (gw, h, 0.10), (0, y, -gd * 0.5), bev=0.012))
    parts.append(_box("%s_GB" % prefix, (gw, h, 0.10), (0, y, gd * 0.5), bev=0.012))
    parts.append(_box("%s_GL" % prefix, (0.10, h, gd), (-gw * 0.5, y, 0), bev=0.012))
    parts.append(_box("%s_GR" % prefix, (0.10, h, gd), (gw * 0.5, y, 0), bev=0.012))
    return parts


def add_mullions(prefix, w, d, y, h, n=6, t=0.07):
    """竖向窗框分隔条(玻璃幕墙的骨架,视觉密度来源)"""
    parts = []
    for i in range(n):
        t2 = (i + 0.5) / float(n) - 0.5
        parts.append(_box("%s_MF%d" % (prefix, i), (t, h, 0.14), (t2 * w, y, -d * 0.5 + 0.02)))
        parts.append(_box("%s_MB%d" % (prefix, i), (t, h, 0.14), (t2 * w, y, d * 0.5 - 0.02)))
    for i in range(max(2, int(n * d / max(w, 0.1)))):
        t2 = (i + 0.5) / float(max(2, int(n * d / max(w, 0.1)))) - 0.5
        parts.append(_box("%s_ML%d" % (prefix, i), (0.14, h, t), (-w * 0.5 + 0.02, y, t2 * d)))
        parts.append(_box("%s_MR%d" % (prefix, i), (0.14, h, t), (w * 0.5 - 0.02, y, t2 * d)))
    return parts


def add_cornice(prefix, w, d, y, out=0.30, h=0.34):
    """檐口(楼顶/层间收边,消除"盒子直上直下"感)"""
    return [
        _box("%s_C0" % prefix, (w + out, h, d + out), (0, y, 0), bev=0.03),
        _box("%s_C1" % prefix, (w + out * 0.55, h * 0.45, d + out * 0.55), (0, y + h * 0.60, 0), bev=0.02),
    ]


def add_parapet(prefix, w, d, y, h=0.9, t=0.20):
    """女儿墙(屋顶围栏)"""
    parts = []
    parts.append(_box("%s_PF" % prefix, (w, h, t), (0, y + h * 0.5, -d * 0.5 + t * 0.5), bev=0.02))
    parts.append(_box("%s_PB" % prefix, (w, h, t), (0, y + h * 0.5, d * 0.5 - t * 0.5), bev=0.02))
    parts.append(_box("%s_PL" % prefix, (t, h, d), (-w * 0.5 + t * 0.5, y + h * 0.5, 0), bev=0.02))
    parts.append(_box("%s_PR" % prefix, (t, h, d), (w * 0.5 - t * 0.5, y + h * 0.5, 0), bev=0.02))
    return parts


def add_roof_kit(prefix, w, d, y, seed=0):
    """楼顶设备组:水箱/空调机组/通风管/天线杆(3A 天际线的必备杂乱感)"""
    rnd = random.Random(20260905 + seed)
    parts = []
    # 水箱(圆柱 + 支腿)
    tx, tz = -w * 0.22, -d * 0.18
    parts.append(add_cyl("%s_Tank" % prefix, 0.85, 1.9, (tx, y + 1.35, tz), axis="y", seg=14, bevel=0.02))
    for dx in (-0.55, 0.55):
        for dz in (-0.55, 0.55):
            parts.append(_box("%s_TL%d%d" % (prefix, int((dx + 1) * 10), int((dz + 1) * 10)),
                              (0.09, 0.42, 0.09), (tx + dx, y + 0.21, tz + dz), bev=0.01))
    # 空调机组 ×2
    for i in range(2):
        ax = w * (0.16 + 0.22 * i)
        az = d * (0.05 - 0.20 * i)
        parts.append(_box("%s_AC%d" % (prefix, i), (1.5, 0.78, 1.1), (ax, y + 0.39, az), bev=0.03))
        parts.append(add_cyl("%s_ACF%d" % (prefix, i), 0.32, 0.10, (ax, y + 0.86, az), axis="y", seg=12, bevel=0.01))
    # 通风管(弯头)
    vx, vz = w * 0.30, d * 0.26
    parts.append(_box("%s_VT" % prefix, (0.42, 1.05, 0.42), (vx, y + 0.52, vz), bev=0.02))
    parts.append(_box("%s_VE" % prefix, (0.42, 0.38, 0.42), (vx + 0.34, y + 1.16, vz), bev=0.02,
                      rot=(0, 0, math.pi * 0.25)))
    # 天线杆 + 横杆
    ax2, az2 = -w * 0.34, d * 0.30
    parts.append(add_cyl("%s_Ant" % prefix, 0.05, 3.2, (ax2, y + 1.6, az2), axis="y", seg=8))
    for j in range(3):
        parts.append(_box("%s_AB%d" % (prefix, j), (0.9 - j * 0.18, 0.05, 0.05),
                          (ax2, y + 2.2 + j * 0.42, az2), bev=0.01))
    return parts


def add_steps(prefix, w, y0, n=3, run=0.32, rise=0.16, z0=0.0, dir_z=-1.0):
    """入口台阶"""
    parts = []
    for i in range(n):
        parts.append(_box("%s_S%d" % (prefix, i), (w, rise, run), (0, y0 + rise * (n - i) - rise * 0.5,
                                                              z0 + dir_z * run * (i + 0.5)), bev=0.012))
    return parts


def add_canopy(prefix, w, d, y, z, post_h=None, posts=2):
    """入口雨棚(板 + 立柱 + 吊杆)"""
    parts = [_box("%s_CP" % prefix, (w, 0.16, d), (0, y, z), bev=0.025)]
    if post_h is not None:
        for i in range(posts):
            px = (i / max(1, posts - 1) - 0.5) * (w - 0.5) if posts > 1 else 0.0
            pz = z - d * 0.5 + 0.18 if d > 0 else z
            parts.append(add_cyl("%s_CPS%d" % (prefix, i), 0.075, post_h,
                                 (px, y - post_h * 0.5, pz), axis="y", seg=10, bevel=0.01))
    return parts


def add_railing(prefix, w, y, z, h=1.05, n=6):
    """栏杆(扶手 + 立柱 + 横撑)"""
    parts = [
        _box("%s_RT" % prefix, (w, 0.07, 0.07), (0, y + h, z), bev=0.012),
        _box("%s_RM" % prefix, (w, 0.04, 0.04), (0, y + h * 0.55, z), bev=0.01),
    ]
    for i in range(n + 1):
        px = (i / float(n) - 0.5) * w
        parts.append(_box("%s_RP%d" % (prefix, i), (0.05, h, 0.05), (px, y + h * 0.5, z), bev=0.01))
    return parts


def add_ac_units(prefix, w, d, y, n=3, seed=0):
    """外挂空调机(沿墙,生活感细节)"""
    rnd = random.Random(777 + seed)
    parts = []
    for i in range(n):
        ay = y + rnd.uniform(0.4, 2.6)
        ax = (rnd.uniform(-0.35, 0.35)) * w
        parts.append(_box("%s_AU%d" % (prefix, i), (0.62, 0.44, 0.30),
                          (ax, ay, -d * 0.5 - 0.17), bev=0.02))
    return parts


def add_sign(prefix, w, h, y, z, thick=0.16):
    """招牌板"""
    return [_box("%s_SG" % prefix, (w, h, thick), (0, y, z), bev=0.02)]


# ============================================================ 医院
def build_city_hospital():
    """医院:主楼(6 层玻璃带)+ 门诊裙房 + 急诊雨棚 + 十字标志 + 停机坪 + 坡道"""
    reset()
    parts = []
    W, D = 16.0, 12.0
    # --- 基座
    parts.append(_box("_Base", (W + 1.2, 0.7, D + 1.2), (0, 0.35, 0), bev=0.03))
    # --- 主楼 6 层
    FLOORS, FH = 6, 3.1
    y0 = 0.7
    parts += add_storey_slabs("_Main", W, D, y0, FLOORS, FH)
    for i in range(FLOORS):
        yg = y0 + FH * i + FH * 0.52
        parts += add_glass_band("_G%d" % i, W, D, yg, FH * 0.52)
        parts += add_mullions("_M%d" % i, W, D, yg, FH * 0.52, n=8)
    # 层间腰线
    for i in range(FLOORS + 1):
        parts.append(_box("_BL%d" % i, (W + 0.22, 0.20, D + 0.22), (0, y0 + FH * i, 0), bev=0.02))
    top_y = y0 + FLOORS * FH
    parts += add_cornice("_Cor", W, D, top_y)
    parts += add_parapet("_Par", W, D, top_y + 0.5, h=1.0)
    # --- 楼顶停机坪(H 标记 + 围栏灯)
    parts.append(_box("_Pad", (7.0, 0.14, 7.0), (0, top_y + 0.78, 0), bev=0.02))
    parts.append(_box("_PadH1", (0.5, 0.06, 3.2), (-1.1, top_y + 0.88, 0), bev=0.01))
    parts.append(_box("_PadH2", (0.5, 0.06, 3.2), (1.1, top_y + 0.88, 0), bev=0.01))
    parts.append(_box("_PadH3", (2.7, 0.06, 0.5), (0, top_y + 0.88, 0), bev=0.01))
    parts += add_roof_kit("_Rf", W, D, top_y + 0.6, seed=1)
    # --- 正面急诊入口(雨棚 + 门斗 + 坡道)
    ez = -D * 0.5 - 0.1
    parts += add_canopy("_Ent", 6.4, 3.2, 3.2, ez - 1.6, post_h=3.2, posts=2)
    parts.append(_box("_Door", (2.4, 2.6, 0.18), (0, 1.98, -D * 0.5 + 0.06), bev=0.02))
    parts.append(_box("_DoorG", (1.9, 2.0, 0.10), (0, 1.72, -D * 0.5 + 0.02), bev=0.015))
    parts += add_steps("_St", 6.4, 0.7, n=3, run=0.34, z0=ez - 0.1)
    # 无障碍坡道
    parts.append(_box("_Ramp", (1.5, 0.14, 3.4), (4.2, 0.62, ez - 1.7), bev=0.02, rot=(-0.19, 0, 0)))
    parts += add_railing("_RampR", 3.2, 0.70, ez - 3.2, h=1.0, n=5)
    # --- 红十字标志(正面 + 侧面)
    for (sx, sz, ry) in ((0, -D * 0.5 - 0.06, 0.0), (W * 0.5 + 0.06, 0, math.pi * 0.5)):
        cy = top_y - 0.9
        parts.append(_box("_CrossA", (1.7, 0.44, 0.10), (sx, cy, sz), bev=0.015, rot=(0, ry, 0)))
        parts.append(_box("_CrossB", (0.44, 1.7, 0.10), (sx, cy, sz), bev=0.015, rot=(0, ry, 0)))
    # --- 侧裙房(门诊楼,2 层)
    parts.append(_box("_Wing", (7.0, 6.2, 8.0), (W * 0.5 + 3.3, 3.1 + 0.7, 1.0), bev=0.03))
    for i in range(2):
        parts.append(_box("_WG%d" % i, (6.4, 1.5, 0.10), (W * 0.5 + 3.3, 2.4 + i * 2.6, 1.0 - 4.0), bev=0.015))
        parts.append(_box("_WW%d" % i, (6.6, 1.1, 0.14), (W * 0.5 + 3.3, 2.4 + i * 2.6, 1.0 - 4.0), bev=0.015))
    parts.append(_box("_WCorn", (7.5, 0.32, 8.5), (W * 0.5 + 3.3, 6.9, 1.0), bev=0.025))
    # --- 空调外机 + 管道
    parts += add_ac_units("_AC", W, D, 1.2, n=4, seed=3)
    parts.append(add_cyl("_Pipe", 0.11, 5.6, (W * 0.5 - 0.35, 3.4, D * 0.5 - 0.35), axis="y", seg=10))
    rules = [
        ("_Base", "concrete"), ("_Main", "wall"), ("_BL", "trim"), ("_Cor", "trim"),
        ("_Par", "wall"), ("_Pad", "concrete"), ("_PadH", "sign"),
        ("_Rf", "metal"), ("_Ent", "metal"), ("_Door", "trim"), ("_DoorG", "glass"),
        ("_St", "concrete"), ("_Ramp", "concrete"), ("_RampR", "metal"),
        ("_Cross", "sign"), ("_Wing", "wall"), ("_WG", "glass"), ("_WW", "trim"),
        ("_WCorn", "trim"), ("_AC", "metal"), ("_Pipe", "metal"),
    ]
    # 玻璃带 / 分隔条
    for i in range(FLOORS):
        rules.append(("_G%d" % i, "glass"))
        rules.append(("_M%d" % i, "trim"))
    return _finish("Prop_city_hospital", parts, rules)


# ============================================================ 商铺
def build_city_shop():
    """沿街商铺:2 层 + 店招 + 橱窗 + 遮阳篷 + 空调外机 + 台阶"""
    reset()
    parts = []
    W, D, H = 11.0, 8.5, 7.4
    parts.append(_box("_Base", (W + 0.5, 0.5, D + 0.5), (0, 0.25, 0), bev=0.025))
    # 主体
    parts.append(_box("_Body", (W, H, D), (0, 0.5 + H * 0.5, 0), bev=0.03))
    # 一层:两侧实墙 + 中央橱窗 + 入口
    parts.append(_box("_ShopL", (2.6, 3.4, 0.24), (-W * 0.5 + 1.5, 2.3, -D * 0.5 + 0.10), bev=0.02))
    parts.append(_box("_ShopR", (2.6, 3.4, 0.24), (W * 0.5 - 1.5, 2.3, -D * 0.5 + 0.10), bev=0.02))
    parts.append(_box("_Win", (4.6, 2.5, 0.14), (-0.9, 2.0, -D * 0.5 + 0.06), bev=0.015))
    parts.append(_box("_WinF", (4.9, 0.14, 0.20), (-0.9, 0.85, -D * 0.5 + 0.07), bev=0.012))
    parts.append(_box("_WinT", (4.9, 0.14, 0.20), (-0.9, 3.22, -D * 0.5 + 0.07), bev=0.012))
    # 入口(凹进 + 门框 + 玻璃门)
    parts.append(_box("_Ent", (1.9, 2.7, 0.16), (3.0, 1.85, -D * 0.5 + 0.05), bev=0.02))
    parts.append(_box("_EntG", (1.5, 2.2, 0.10), (3.0, 1.6, -D * 0.5 + 0.01), bev=0.015))
    # 遮阳篷(斜板 + 侧板)
    for i, cx in enumerate((-0.9, 3.0)):
        parts.append(_box("_Awn%d" % i, (2.6 if i == 0 else 2.2, 0.10, 1.5),
                          (cx, 3.45, -D * 0.5 - 0.72), bev=0.02, rot=(-0.30, 0, 0)))
        for s in (-1, 1):
            parts.append(_box("_AwnS%d%d" % (i, s), (0.08, 0.62, 1.5),
                              (cx + s * (1.3 if i == 0 else 1.1), 3.18, -D * 0.5 - 0.72), bev=0.015))
    # 二层:通长玻璃 + 分隔 + 栏杆
    parts.append(_box("_F2W", (W - 1.2, 1.9, 0.12), (0, 6.0, -D * 0.5 + 0.05), bev=0.015))
    for i in range(5):
        parts.append(_box("_F2M%d" % i, (0.08, 1.9, 0.16),
                          ((i / 4.0 - 0.5) * (W - 1.4), 6.0, -D * 0.5 + 0.04), bev=0.01))
    parts += add_railing("_Bal", W - 1.4, 4.95, -D * 0.5 - 0.42, h=1.0, n=7)
    # 店招(灯箱 + 字板)
    parts.append(_box("_Sign", (W - 0.8, 1.5, 0.30), (0, 4.15, -D * 0.5 - 0.14), bev=0.025))
    for i in range(4):
        parts.append(_box("_SignL%d" % i, (1.5, 0.55, 0.10),
                          ((i / 3.0 - 0.5) * (W - 3.0), 4.15, -D * 0.5 - 0.30), bev=0.012))
    # 檐口 + 女儿墙
    parts += add_cornice("_Cor", W, D, 0.5 + H, out=0.34)
    parts += add_parapet("_Par", W, D, 0.5 + H + 0.55, h=0.75)
    parts.append(_box("_Roof", (W, 0.16, D), (0, 0.5 + H + 0.16, 0), bev=0.02))
    # 空调外机 + 落水管 + 台阶
    parts += add_ac_units("_AC", W, D, 1.0, n=2, seed=5)
    parts.append(add_cyl("_DP", 0.07, H + 0.4, (W * 0.5 - 0.22, (H + 0.4) * 0.5, D * 0.5 - 0.22),
                         axis="y", seg=8))
    parts += add_steps("_St", 2.2, 0.5, n=2, run=0.30, z0=-D * 0.5 - 0.05)
    rules = [
        ("_Base", "concrete"), ("_Body", "wall"), ("_Shop", "wall"),
        ("_Win", "glass"), ("_WinF", "trim"), ("_WinT", "trim"),
        ("_Ent", "trim"), ("_EntG", "glass"), ("_Awn", "sign"),
        ("_F2W", "glass"), ("_F2M", "trim"), ("_Bal", "metal"),
        ("_Sign", "sign"), ("_SignL", "sign"), ("_Cor", "trim"), ("_Par", "wall"),
        ("_Roof", "roof"), ("_AC", "metal"), ("_DP", "metal"), ("_St", "concrete"),
    ]
    return _finish("Prop_city_shop", parts, rules)


# ============================================================ 加油站
def build_city_gas():
    """加油站:大顶棚 + 4 柱 + 双加油机岛 + 便利店 + 价格牌"""
    reset()
    parts = []
    # --- 便利店(右侧)
    SW, SD, SH = 9.0, 7.0, 4.2
    sx = 8.0
    parts.append(_box("_Store", (SW, SH, SD), (sx, SH * 0.5, 0), bev=0.03))
    parts.append(_box("_StoreW", (SW - 1.0, 1.8, 0.12), (sx, 2.5, -SD * 0.5 + 0.05), bev=0.015))
    parts.append(_box("_StoreD", (1.8, 2.6, 0.14), (sx, 1.6, -SD * 0.5 + 0.05), bev=0.02))
    parts.append(_box("_StoreG", (1.4, 2.1, 0.10), (sx, 1.45, -SD * 0.5 + 0.01), bev=0.015))
    parts += add_cornice("_SCor", SW, SD, SH, out=0.28, h=0.30)
    parts.append(_box("_SRoof", (SW, 0.18, SD), (sx, SH + 0.20, 0), bev=0.02))
    parts.append(_box("_SSign", (SW - 2.0, 1.1, 0.28), (sx, SH + 1.0, -SD * 0.5 - 0.10), bev=0.02))
    # --- 顶棚(大板 + 4 柱 + 灯带)
    CW, CD, CY = 15.0, 11.0, 5.4
    cx = -4.0
    parts.append(_box("_Canopy", (CW, 0.55, CD), (cx, CY, 0), bev=0.04))
    parts.append(_box("_CanopyE", (CW + 0.4, 0.30, CD + 0.4), (cx, CY + 0.42, 0), bev=0.03))
    for i in range(6):
        parts.append(_box("_CLamp%d" % i, (1.5, 0.10, 0.5),
                          (cx + (i / 5.0 - 0.5) * (CW - 3.0), CY - 0.34, 0), bev=0.012))
    for px in (-1, 1):
        for pz in (-1, 1):
            parts.append(_box("_Col%d%d" % (px, pz), (0.55, CY - 0.55, 0.55),
                              (cx + px * (CW * 0.5 - 1.4), (CY - 0.55) * 0.5, pz * (CD * 0.5 - 1.4)),
                              bev=0.03))
            parts.append(_box("_ColB%d%d" % (px, pz), (0.85, 0.20, 0.85),
                              (cx + px * (CW * 0.5 - 1.4), 0.10, pz * (CD * 0.5 - 1.4)), bev=0.02))
    # --- 加油机岛(2 座)
    for i, iz in enumerate((2.6, -2.6)):
        parts.append(_box("_Island%d" % i, (5.4, 0.22, 1.5), (cx, 0.11, iz), bev=0.02))
        for s in (-1, 1):
            px2 = cx + s * 1.5
            parts.append(_box("_Pump%d%d" % (i, s), (0.72, 1.75, 0.62), (px2, 1.10, iz), bev=0.03))
            parts.append(_box("_PumpP%d%d" % (i, s), (0.52, 0.62, 0.10),
                              (px2 - s * 0.36, 1.45, iz), bev=0.015))
            parts.append(_box("_PumpL%d%d" % (i, s), (0.56, 0.20, 0.08),
                              (px2 - s * 0.36, 1.72, iz), bev=0.012))
            # 加油枪 + 软管
            parts.append(_box("_Nozzle%d%d" % (i, s), (0.10, 0.34, 0.10),
                              (px2 - s * 0.48, 1.05, iz + 0.28), bev=0.012))
    # --- 价格牌(高杆 + 板)
    parts.append(add_cyl("_PMast", 0.16, 5.6, (-12.0, 2.8, 5.5), axis="y", seg=10, bevel=0.02))
    parts.append(_box("_PBoard", (3.4, 2.2, 0.24), (-12.0, 5.6, 5.5), bev=0.025))
    parts.append(_box("_PFace", (3.0, 1.8, 0.10), (-12.0, 5.6, 5.38), bev=0.015))
    # --- 地面油罐口 + 消防栓
    parts.append(add_cyl("_Fill", 0.32, 0.14, (2.0, 0.07, -6.0), axis="y", seg=12, bevel=0.02))
    parts.append(_box("_Hydr", (0.26, 0.85, 0.26), (-11.0, 0.42, -5.5), bev=0.02))
    rules = [
        ("_Store", "wall"), ("_StoreW", "glass"), ("_StoreD", "trim"), ("_StoreG", "glass"),
        ("_SCor", "trim"), ("_SRoof", "roof"), ("_SSign", "sign"),
        ("_Canopy", "metal"), ("_CanopyE", "trim"), ("_CLamp", "sign"),
        ("_Col", "metal"), ("_Island", "concrete"), ("_Pump", "metal"),
        ("_PumpP", "sign"), ("_PumpL", "sign"), ("_Nozzle", "metal"),
        ("_PMast", "metal"), ("_PBoard", "metal"), ("_PFace", "sign"),
        ("_Fill", "metal"), ("_Hydr", "sign"),
    ]
    return _finish("Prop_city_gas", parts, rules)


# ============================================================ 商场
def build_city_mall():
    """商场:3 层玻璃幕墙裙房 + 主入口雨棚旋转门 + 顶层停车场 + 采光顶"""
    reset()
    parts = []
    W, D = 22.0, 15.0
    parts.append(_box("_Base", (W + 1.4, 0.8, D + 1.4), (0, 0.40, 0), bev=0.03))
    # 主体 3 层通高玻璃幕墙
    H = 11.5
    parts.append(_box("_Core", (W - 0.6, H - 1.0, D - 0.6), (0, 0.8 + (H - 1.0) * 0.5, 0), bev=0.03))
    for i in range(3):
        yg = 0.8 + 1.2 + i * 3.3
        parts += add_glass_band("_G%d" % i, W + 0.16, D + 0.16, yg, 2.5, inset=0.30)
        parts += add_mullions("_M%d" % i, W + 0.16, D + 0.16, yg, 2.5, n=12)
        parts.append(_box("_BL%d" % i, (W + 0.5, 0.28, D + 0.5), (0, 0.8 + i * 3.3, 0), bev=0.02))
    # 顶层:停车场(开放式,柱网 + 女儿墙)
    py = 0.8 + H
    parts.append(_box("_PDeck", (W, 0.35, D), (0, py + 0.18, 0), bev=0.03))
    for i in range(5):
        for j in range(4):
            px = (i / 4.0 - 0.5) * (W - 3.0)
            pz = (j / 3.0 - 0.5) * (D - 3.0)
            parts.append(_box("_PCol%d%d" % (i, j), (0.42, 2.6, 0.42), (px, py + 1.55, pz), bev=0.02))
    parts += add_parapet("_PPar", W, D, py + 0.35, h=1.1)
    parts.append(_box("_PRoof", (W - 0.8, 0.20, D - 0.8), (0, py + 2.95, 0), bev=0.025))
    parts += add_roof_kit("_Rf", W, D, py + 3.05, seed=7)
    # 采光顶(中央玻璃拱)
    for i in range(5):
        t = (i / 4.0 - 0.5)
        parts.append(_box("_Sky%d" % i, (3.4, 0.12, D - 4.0), (t * (W - 8.0), py + 3.25, 0),
                          bev=0.02, rot=(0, 0, -t * 0.22)))
    # 主入口(雨棚 + 旋转门 + 台阶)
    ez = -D * 0.5 - 0.2
    parts += add_canopy("_Ent", 8.0, 4.0, 3.6, ez - 2.0, post_h=3.6, posts=3)
    parts.append(_box("_EntF", (7.0, 3.4, 0.20), (0, 2.5, -D * 0.5 + 0.08), bev=0.02))
    parts.append(add_cyl("_Rev", 1.5, 3.0, (0, 1.5, -D * 0.5 + 0.90), axis="y", seg=16, bevel=0.03))
    for k in range(4):
        a = k * math.tau / 4.0
        parts.append(_box("_RevD%d" % k, (0.10, 2.8, 1.4),
                          (math.sin(a) * 0.72, 1.5, -D * 0.5 + 0.90 + math.cos(a) * 0.72),
                          bev=0.015, rot=(0, a, 0)))
    parts += add_steps("_St", 8.0, 0.8, n=3, run=0.36, z0=ez - 0.2)
    # 侧入口 + 卸货区
    parts.append(_box("_Side", (2.2, 2.8, 0.18), (W * 0.5 - 3.0, 2.2, -D * 0.5 + 0.06), bev=0.02))
    parts.append(_box("_Dock", (5.0, 0.9, 0.30), (-W * 0.5 + 4.0, 0.45, D * 0.5 + 0.40), bev=0.02))
    parts.append(_box("_DockD", (4.0, 2.8, 0.16), (-W * 0.5 + 4.0, 2.2, D * 0.5 + 0.06), bev=0.02))
    # 招牌塔
    parts.append(add_cyl("_SMast", 0.20, 6.0, (W * 0.5 - 1.5, 3.0, -D * 0.5 - 3.0), axis="y", seg=10))
    parts.append(_box("_Sign", (1.6, 4.0, 0.30), (W * 0.5 - 1.5, 8.0, -D * 0.5 - 3.0), bev=0.025))
    rules = [
        ("_Base", "concrete"), ("_Core", "wall"), ("_BL", "trim"),
        ("_PDeck", "concrete"), ("_PCol", "concrete"), ("_PPar", "wall"), ("_PRoof", "roof"),
        ("_Rf", "metal"), ("_Sky", "glass"), ("_Ent", "metal"), ("_EntF", "glass"),
        ("_Rev", "glass"), ("_RevD", "glass"), ("_St", "concrete"),
        ("_Side", "glass"), ("_Dock", "concrete"), ("_DockD", "metal"),
        ("_SMast", "metal"), ("_Sign", "sign"),
    ]
    for i in range(3):
        rules.append(("_G%d" % i, "glass"))
        rules.append(("_M%d" % i, "trim"))
    return _finish("Prop_city_mall", parts, rules)


# ============================================================ 写字楼
def build_city_office():
    """写字楼:12 层玻璃幕墙 + 竖向装饰条 + 基座广场 + 楼顶设备"""
    reset()
    parts = []
    W, D = 13.0, 13.0
    parts.append(_box("_Base", (W + 2.0, 1.0, D + 2.0), (0, 0.50, 0), bev=0.03))
    FLOORS, FH = 12, 3.15
    y0 = 1.0
    parts.append(_box("_Core", (W - 0.8, FLOORS * FH, D - 0.8),
                      (0, y0 + FLOORS * FH * 0.5, 0), bev=0.03))
    for i in range(FLOORS):
        yg = y0 + FH * i + FH * 0.55
        parts += add_glass_band("_G%d" % i, W - 0.2, D - 0.2, yg, FH * 0.62, inset=0.22)
        # 竖向装饰条(每面 5 根贯穿,3A 立面的骨架)
        for k in range(5):
            t2 = (k / 4.0 - 0.5) * (W - 1.6)
            parts.append(_box("_VB%d_%d" % (i, k), (0.16, FH * 0.66, 0.22),
                              (t2, yg, -D * 0.5 + 0.32), bev=0.012))
            parts.append(_box("_VF%d_%d" % (i, k), (0.16, FH * 0.66, 0.22),
                              (t2, yg, D * 0.5 - 0.32), bev=0.012))
    # 角柱(四角贯通,强化体量)
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Pil%d%d" % (sx, sz), (0.55, FLOORS * FH, 0.55),
                              (sx * (W * 0.5 - 0.28), y0 + FLOORS * FH * 0.5, sz * (D * 0.5 - 0.28)),
                              bev=0.025))
    top_y = y0 + FLOORS * FH
    parts += add_cornice("_Cor", W, D, top_y, out=0.40, h=0.45)
    parts += add_parapet("_Par", W, D, top_y + 0.6, h=1.2)
    parts += add_roof_kit("_Rf", W, D, top_y + 0.7, seed=11)
    # 顶部桅杆 + 航空灯
    parts.append(add_cyl("_Mast", 0.09, 4.5, (0, top_y + 3.0, 0), axis="y", seg=8))
    parts.append(_box("_Beacon", (0.26, 0.26, 0.26), (0, top_y + 5.3, 0), bev=0.03))
    # 基座广场(台阶 + 花池 + 旗杆)
    parts += add_steps("_St", 6.0, 1.0, n=3, run=0.36, z0=-D * 0.5 - 1.0)
    for s in (-1, 1):
        parts.append(_box("_Planter%d" % s, (2.2, 0.75, 2.2), (s * 4.0, 1.38, -D * 0.5 - 2.4), bev=0.025))
        parts.append(_box("_Shrub%d" % s, (1.9, 0.55, 1.9), (s * 4.0, 1.95, -D * 0.5 - 2.4), bev=0.10))
    for s in (-1, 1):
        parts.append(add_cyl("_Flag%d" % s, 0.07, 8.0, (s * 5.2, 5.0, -D * 0.5 - 3.2), axis="y", seg=8))
        parts.append(_box("_FlagC%d" % s, (1.4, 0.85, 0.05), (s * 5.2 + 0.72, 8.4, -D * 0.5 - 3.2), bev=0.015))
    # 入口雨棚
    parts += add_canopy("_Ent", 6.5, 3.0, 4.2, -D * 0.5 - 1.7, post_h=4.2, posts=2)
    parts.append(_box("_EntF", (5.4, 3.2, 0.18), (0, 2.7, -D * 0.5 + 0.06), bev=0.02))
    rules = [
        ("_Base", "concrete"), ("_Core", "wall"), ("_Pil", "trim"), ("_Cor", "trim"),
        ("_Par", "wall"), ("_Rf", "metal"), ("_Mast", "metal"), ("_Beacon", "sign"),
        ("_St", "concrete"), ("_Planter", "concrete"), ("_Shrub", "leaf"),
        ("_Flag", "metal"), ("_FlagC", "sign"), ("_Ent", "metal"), ("_EntF", "glass"),
    ]
    for i in range(FLOORS):
        rules.append(("_G%d" % i, "glass"))
        rules.append(("_VB%d" % i, "trim"))
        rules.append(("_VF%d" % i, "trim"))
    return _finish("Prop_city_office", parts, rules)


# ============================================================ 教堂
def build_city_church():
    """教堂:钟楼尖顶 + 十字 + 中殿坡顶 + 彩色玻璃窗 + 拱门廊"""
    reset()
    parts = []
    # --- 中殿
    NW, ND, NH = 12.0, 20.0, 8.0
    parts.append(_box("_Nave", (NW, NH, ND), (0, NH * 0.5, 0), bev=0.03))
    # 坡屋顶(两片斜板 + 屋脊)
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (NW * 0.62 + 0.6, 0.30, ND + 1.0),
                          (s * NW * 0.28, NH + 2.1, 0), bev=0.03, rot=(0, 0, -s * 0.62)))
    parts.append(_box("_Ridge", (0.55, 0.45, ND + 1.0), (0, NH + 3.55, 0), bev=0.025))
    # 侧墙扶壁 + 彩色玻璃窗
    for i in range(4):
        zt = (i / 3.0 - 0.5) * (ND - 5.0)
        for s in (-1, 1):
            parts.append(_box("_But%d%d" % (i, s), (0.7, NH * 0.8, 0.9),
                              (s * (NW * 0.5 + 0.30), NH * 0.42, zt), bev=0.025))
            parts.append(_box("_Win%d%d" % (i, s), (0.14, 3.4, 1.3),
                              (s * (NW * 0.5 + 0.06), 4.4, zt), bev=0.015))
            # 尖拱窗顶(三角)
            parts.append(_box("_Arc%d%d" % (i, s), (0.14, 0.7, 1.3),
                              (s * (NW * 0.5 + 0.06), 6.2, zt), bev=0.015,
                              rot=(0, 0, s * 0.0)))
    # --- 钟楼(正面)
    TW = 5.0
    tz = -ND * 0.5 - TW * 0.5
    parts.append(_box("_Tower", (TW, 20.0, TW), (0, 10.0, tz), bev=0.035))
    parts.append(_box("_TowerB1", (TW + 0.5, 0.4, TW + 0.5), (0, 6.0, tz), bev=0.025))
    parts.append(_box("_TowerB2", (TW + 0.5, 0.4, TW + 0.5), (0, 14.0, tz), bev=0.025))
    parts.append(_box("_TowerB3", (TW + 0.7, 0.5, TW + 0.7), (0, 20.0, tz), bev=0.025))
    # 钟室(四面开敞 + 柱 + 钟)
    parts.append(_box("_Belfry", (TW - 0.8, 3.4, TW - 0.8), (0, 17.7, tz), bev=0.025))
    for px in (-1, 1):
        for pz in (-1, 1):
            parts.append(_box("_BCol%d%d" % (px, pz), (0.42, 3.4, 0.42),
                              (px * (TW * 0.5 - 0.5), 17.7, tz + pz * (TW * 0.5 - 0.5)), bev=0.02))
    parts.append(add_cyl("_Bell", 0.75, 1.3, (0, 17.6, tz), axis="y", seg=14, taper=0.55, bevel=0.03))
    # 尖顶(四棱锥 via 锥形圆柱 4 段) + 十字
    parts.append(add_cyl("_Spire", TW * 0.72, 8.0, (0, 24.2, tz), axis="y", seg=4, taper=0.02, bevel=0.03))
    parts.append(_box("_CrossV", (0.18, 2.0, 0.18), (0, 29.4, tz), bev=0.02))
    parts.append(_box("_CrossH", (1.0, 0.18, 0.18), (0, 29.9, tz), bev=0.02))
    # 钟面
    parts.append(add_cyl("_Clock", 1.05, 0.20, (0, 15.0, tz - TW * 0.5 - 0.06), axis="z", seg=20, bevel=0.02))
    parts.append(_box("_ClockH", (0.10, 0.55, 0.10), (0, 15.22, tz - TW * 0.5 - 0.14), bev=0.012))
    parts.append(_box("_ClockM", (0.42, 0.10, 0.10), (0.22, 15.0, tz - TW * 0.5 - 0.14), bev=0.012))
    # --- 拱门廊(入口)
    parts += add_steps("_St", 6.0, 0.0, n=4, run=0.38, z0=tz - TW * 0.5 - 0.2)
    parts.append(_box("_Porch", (6.5, 5.0, 2.2), (0, 2.5, tz - TW * 0.5 - 1.0), bev=0.03))
    for px in (-1, 1):
        parts.append(add_cyl("_PCol%d" % px, 0.42, 4.6, (px * 2.5, 2.3, tz - TW * 0.5 - 2.0),
                             axis="y", seg=12, bevel=0.02))
    parts.append(_box("_Arch", (6.0, 1.2, 0.30), (0, 5.3, tz - TW * 0.5 - 1.9), bev=0.025))
    parts.append(_box("_Door", (2.4, 3.6, 0.20), (0, 1.8, tz - TW * 0.5 + 0.05), bev=0.025))
    parts.append(_box("_DoorG", (1.9, 2.9, 0.10), (0, 1.55, tz - TW * 0.5), bev=0.018))
    # 玫瑰窗
    parts.append(add_cyl("_Rose", 1.7, 0.22, (0, 13.0, tz - TW * 0.5 - 0.10), axis="z", seg=20, bevel=0.02))
    rules = [
        ("_Nave", "wall"), ("_Roof", "roof"), ("_Ridge", "roof"), ("_But", "wall"),
        ("_Win", "glass"), ("_Arc", "glass"), ("_Tower", "wall"), ("_TowerB", "trim"),
        ("_Belfry", "wall"), ("_BCol", "trim"), ("_Bell", "metal"),
        ("_Spire", "roof"), ("_Cross", "sign"), ("_Clock", "trim"),
        ("_ClockH", "sign"), ("_ClockM", "sign"), ("_St", "concrete"),
        ("_Porch", "wall"), ("_PCol", "trim"), ("_Arch", "trim"),
        ("_Door", "trim"), ("_DoorG", "glass"), ("_Rose", "glass"),
    ]
    return _finish("Prop_city_church", parts, rules)


# ============================================================ 学校
def build_city_school():
    """学校:3 层教学楼 + 连廊 + 操场看台 + 旗杆"""
    reset()
    parts = []
    W, D, H = 20.0, 11.0, 10.5
    parts.append(_box("_Base", (W + 1.0, 0.6, D + 1.0), (0, 0.30, 0), bev=0.03))
    parts.append(_box("_Body", (W, H, D), (0, 0.6 + H * 0.5, 0), bev=0.035))
    # 三层窗带(每层 6 扇 + 窗台 + 窗楣)
    for i in range(3):
        yw = 0.6 + H * (i + 0.42) / 3.0 + 0.6
        for k in range(7):
            wx = (k / 6.0 - 0.5) * (W - 2.4)
            parts.append(_box("_Win%d_%d" % (i, k), (1.5, 1.7, 0.14), (wx, yw, -D * 0.5 + 0.05), bev=0.015))
            parts.append(_box("_WinS%d_%d" % (i, k), (1.75, 0.13, 0.28), (wx, yw - 0.95, -D * 0.5 + 0.08), bev=0.012))
            parts.append(_box("_WinT%d_%d" % (i, k), (1.75, 0.13, 0.28), (wx, yw + 0.95, -D * 0.5 + 0.08), bev=0.012))
    # 背面临街窗(简化)
    for i in range(3):
        yw = 0.6 + H * (i + 0.42) / 3.0 + 0.6
        for k in range(5):
            wx = (k / 4.0 - 0.5) * (W - 3.0)
            parts.append(_box("_BW%d_%d" % (i, k), (1.5, 1.7, 0.14), (wx, yw, D * 0.5 - 0.05), bev=0.015))
    # 层间线 + 檐口 + 女儿墙
    for i in range(4):
        parts.append(_box("_BL%d" % i, (W + 0.4, 0.26, D + 0.4), (0, 0.6 + H * i / 3.0, 0), bev=0.02))
    parts += add_cornice("_Cor", W, D, 0.6 + H, out=0.36)
    parts += add_parapet("_Par", W, D, 0.6 + H + 0.55, h=0.9)
    parts.append(_box("_Roof", (W, 0.20, D), (0, 0.6 + H + 0.22, 0), bev=0.02))
    parts += add_roof_kit("_Rf", W, D, 0.6 + H + 0.32, seed=13)
    # 入口(门廊 + 柱 + 台阶 + 校名牌)
    ez = -D * 0.5 - 0.2
    parts += add_canopy("_Ent", 7.0, 3.2, 3.5, ez - 1.6, post_h=3.5, posts=3)
    parts.append(_box("_Door", (2.6, 2.9, 0.18), (0, 2.05, -D * 0.5 + 0.06), bev=0.02))
    parts.append(_box("_DoorG", (2.1, 2.3, 0.10), (0, 1.85, -D * 0.5 + 0.01), bev=0.015))
    parts += add_steps("_St", 7.0, 0.6, n=3, run=0.36, z0=ez - 0.15)
    parts.append(_box("_Nameplate", (5.0, 0.75, 0.14), (0, 3.9, -D * 0.5 - 0.10), bev=0.015))
    # 连廊(侧翼,柱 + 顶)
    for i in range(5):
        px = W * 0.5 + 2.0
        pz = (i / 4.0 - 0.5) * 9.0
        parts.append(add_cyl("_Arc%d" % i, 0.22, 3.2, (px, 1.6, pz), axis="y", seg=10, bevel=0.02))
    parts.append(_box("_ArcRoof", (1.8, 0.24, 11.0), (W * 0.5 + 2.0, 3.35, 0), bev=0.02))
    # 操场看台(3 级)
    for i in range(3):
        parts.append(_box("_Stand%d" % i, (14.0, 0.45 + i * 0.45, 1.0),
                          (-2.0, (0.45 + i * 0.45) * 0.5, D * 0.5 + 3.0 + i * 1.0), bev=0.02))
    # 旗杆 + 旗
    parts.append(add_cyl("_FPole", 0.09, 9.0, (0, 4.5, D * 0.5 + 9.0), axis="y", seg=8))
    parts.append(_box("_FCloth", (1.9, 1.1, 0.05), (0.98, 8.2, D * 0.5 + 9.0), bev=0.015))
    # 垃圾桶 + 空调
    parts += add_ac_units("_AC", W, D, 1.0, n=3, seed=17)
    rules = [
        ("_Base", "concrete"), ("_Body", "wall"), ("_Win", "glass"),
        ("_WinS", "trim"), ("_WinT", "trim"), ("_BW", "glass"), ("_BL", "trim"),
        ("_Cor", "trim"), ("_Par", "wall"), ("_Roof", "roof"), ("_Rf", "metal"),
        ("_Ent", "metal"), ("_Door", "trim"), ("_DoorG", "glass"), ("_St", "concrete"),
        ("_Nameplate", "sign"), ("_Arc", "trim"), ("_ArcRoof", "roof"),
        ("_Stand", "concrete"), ("_FPole", "metal"), ("_FCloth", "sign"), ("_AC", "metal"),
    ]
    return _finish("Prop_city_school", parts, rules)


# ============================================================ 仓库
def build_city_warehouse():
    """仓库:波纹钢外墙 + 卷帘门 ×3 + 装卸平台 + 排风管 + 屋顶采光带"""
    reset()
    parts = []
    W, D, H = 24.0, 16.0, 8.5
    parts.append(_box("_Base", (W + 0.8, 0.5, D + 0.8), (0, 0.25, 0), bev=0.03))
    parts.append(_box("_Body", (W, H, D), (0, 0.5 + H * 0.5, 0), bev=0.035))
    # 波纹钢:竖向壁板(每 1.2m 一道,视觉密度)
    n_panel = int(W / 1.2)
    for i in range(n_panel + 1):
        px = (i / float(n_panel) - 0.5) * W
        parts.append(_box("_RibF%d" % i, (0.16, H, 0.26), (px, 0.5 + H * 0.5, -D * 0.5 - 0.10), bev=0.012))
        parts.append(_box("_RibB%d" % i, (0.16, H, 0.26), (px, 0.5 + H * 0.5, D * 0.5 + 0.10), bev=0.012))
    # 卷帘门 ×3(门框 + 门板 + 顶箱)
    for i in range(3):
        dx = (i - 1) * 7.0
        parts.append(_box("_DoorF%d" % i, (4.4, 4.6, 0.24), (dx, 2.8, -D * 0.5 + 0.06), bev=0.02))
        parts.append(_box("_Door%d" % i, (4.0, 4.2, 0.14), (dx, 2.6, -D * 0.5 + 0.01), bev=0.018))
        for j in range(7):
            parts.append(_box("_Slat%d_%d" % (i, j), (3.9, 0.10, 0.18),
                              (dx, 0.9 + j * 0.55, -D * 0.5 + 0.02), bev=0.008))
        parts.append(_box("_DoorBox%d" % i, (4.7, 0.55, 0.55), (dx, 5.35, -D * 0.5 - 0.16), bev=0.02))
        # 装卸平台(门前方)
        parts.append(_box("_Dock%d" % i, (5.2, 0.95, 3.0), (dx, 0.98, -D * 0.5 - 1.6), bev=0.03))
        parts.append(_box("_DockE%d" % i, (5.2, 0.10, 0.16), (dx, 1.50, -D * 0.5 - 3.05), bev=0.012))
    # 屋顶:双坡 + 采光带 + 屋脊通风器
    for s in (-1, 1):
        parts.append(_box("_Roof%d" % s, (W * 0.54 + 0.8, 0.28, D + 1.2),
                          (s * W * 0.25, 0.5 + H + 1.3, 0), bev=0.03, rot=(0, 0, -s * 0.30)))
        parts.append(_box("_Sky%d" % s, (W * 0.30, 0.12, D - 3.0),
                          (s * W * 0.20, 0.5 + H + 2.35, 0), bev=0.02, rot=(0, 0, -s * 0.30)))
    parts.append(_box("_Gable", (0.5, 2.6, D + 1.2), (0, 0.5 + H + 1.3, 0), bev=0.03))
    for i in range(4):
        parts.append(_box("_Vent%d" % i, (1.6, 0.65, 0.9),
                          ((i / 3.0 - 0.5) * (W - 6.0), 0.5 + H + 2.9, 0), bev=0.02))
    # 排风管(侧墙) + 落水管 + 电箱
    for i in range(3):
        parts.append(add_cyl("_Duct%d" % i, 0.34, 5.5, (W * 0.5 - 3.5 - i * 5.0, 3.2, D * 0.5 + 0.55),
                             axis="y", seg=12, bevel=0.02))
        parts.append(_box("_DuctC%d" % i, (0.9, 0.55, 0.9),
                          (W * 0.5 - 3.5 - i * 5.0, 6.05, D * 0.5 + 0.55), bev=0.02))
    parts.append(_box("_Elec", (0.9, 1.3, 0.35), (-W * 0.5 + 3.0, 2.2, -D * 0.5 - 0.30), bev=0.02))
    rules = [
        ("_Base", "concrete"), ("_Body", "wall"), ("_Rib", "metal"),
        ("_DoorF", "trim"), ("_Door", "metal"), ("_Slat", "metal"), ("_DoorBox", "metal"),
        ("_Dock", "concrete"), ("_DockE", "trim"), ("_Roof", "roof"), ("_Sky", "glass"),
        ("_Gable", "wall"), ("_Vent", "metal"), ("_Duct", "metal"), ("_DuctC", "metal"),
        ("_Elec", "metal"),
    ]
    return _finish("Prop_city_warehouse", parts, rules)


# ============================================================ 酒店
def build_city_hotel():
    """酒店:高塔 + 阳台层 + 入口雨棚 + 招牌灯 + 旋转门"""
    reset()
    parts = []
    W, D = 12.0, 12.0
    parts.append(_box("_Base", (W + 2.4, 1.2, D + 2.4), (0, 0.60, 0), bev=0.03))
    FLOORS, FH = 10, 3.2
    y0 = 1.2
    parts.append(_box("_Core", (W, FLOORS * FH, D), (0, y0 + FLOORS * FH * 0.5, 0), bev=0.03))
    # 每层:窗 + 阳台(栏板 + 底板)
    for i in range(FLOORS):
        yf = y0 + FH * i
        parts.append(_box("_BL%d" % i, (W + 0.30, 0.22, D + 0.30), (0, yf, 0), bev=0.02))
        yw = yf + FH * 0.56
        parts += add_glass_band("_G%d" % i, W + 0.10, D + 0.10, yw, FH * 0.50, inset=0.18)
        # 阳台(前后面)
        for s in (-1, 1):
            parts.append(_box("_Bal%d_%d" % (i, s), (W + 0.2, 0.14, 1.3),
                              (0, yf + 0.30, s * (D * 0.5 + 0.6)), bev=0.015))
            parts.append(_box("_BalR%d_%d" % (i, s), (W + 0.2, 1.0, 0.10),
                              (0, yf + 0.85, s * (D * 0.5 + 1.2)), bev=0.012))
            for k in range(4):
                parts.append(_box("_BalP%d_%d_%d" % (i, s, k), (0.08, 1.0, 0.08),
                                  ((k / 3.0 - 0.5) * (W - 1.0), yf + 0.85, s * (D * 0.5 + 1.2)), bev=0.008))
    top_y = y0 + FLOORS * FH
    parts += add_cornice("_Cor", W, D, top_y, out=0.42, h=0.48)
    parts += add_parapet("_Par", W, D, top_y + 0.65, h=1.1)
    parts += add_roof_kit("_Rf", W, D, top_y + 0.75, seed=19)
    # 顶层餐厅(玻璃盒子 + 顶棚)
    parts.append(_box("_Rest", (W - 2.0, 3.4, D - 2.0), (0, top_y + 2.5, 0), bev=0.03))
    parts += add_glass_band("_RG", W - 1.6, D - 1.6, top_y + 2.5, 2.6, inset=0.2)
    parts.append(_box("_RestR", (W - 0.6, 0.30, D - 0.6), (0, top_y + 4.5, 0), bev=0.03))
    # 竖向招牌灯带(四角)
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(_box("_Stripe%d%d" % (sx, sz), (0.30, FLOORS * FH - 1.0, 0.30),
                              (sx * (W * 0.5 - 0.16), y0 + (FLOORS * FH - 1.0) * 0.5 + 0.5,
                               sz * (D * 0.5 - 0.16)), bev=0.02))
    # 入口(大堂雨棚 + 旋转门 + 台阶 + 门童柱)
    ez = -D * 0.5 - 1.4
    parts += add_canopy("_Ent", 9.0, 4.5, 4.6, ez - 2.2, post_h=4.6, posts=3)
    parts.append(_box("_EntF", (7.0, 4.0, 0.20), (0, 3.2, -D * 0.5 + 0.08), bev=0.025))
    parts.append(add_cyl("_Rev", 1.7, 3.6, (0, 1.9, -D * 0.5 + 1.0), axis="y", seg=18, bevel=0.03))
    for k in range(4):
        a = k * math.tau / 4.0
        parts.append(_box("_RevD%d" % k, (0.10, 3.4, 1.6),
                          (math.sin(a) * 0.82, 1.9, -D * 0.5 + 1.0 + math.cos(a) * 0.82),
                          bev=0.015, rot=(0, a, 0)))
    parts += add_steps("_St", 9.0, 1.2, n=3, run=0.38, z0=ez - 0.2)
    # 酒店名招牌
    parts.append(_box("_Sign", (7.0, 1.4, 0.28), (0, 6.4, -D * 0.5 - 0.20), bev=0.025))
    # 车道雨棚(侧)
    parts.append(_box("_Drive", (5.0, 0.24, 8.0), (W * 0.5 + 3.0, 4.4, -D * 0.5 + 2.0), bev=0.025))
    for i in range(3):
        parts.append(add_cyl("_DriveC%d" % i, 0.16, 4.4,
                             (W * 0.5 + 3.0 + (i - 1) * 2.0, 2.2, -D * 0.5 + 5.4), axis="y", seg=10))
    rules = [
        ("_Base", "concrete"), ("_Core", "wall"), ("_BL", "trim"), ("_Cor", "trim"),
        ("_Par", "wall"), ("_Rf", "metal"), ("_Rest", "wall"), ("_RestR", "roof"),
        ("_Stripe", "sign"), ("_Ent", "metal"), ("_EntF", "glass"), ("_Rev", "glass"),
        ("_RevD", "glass"), ("_St", "concrete"), ("_Sign", "sign"),
        ("_Drive", "metal"), ("_DriveC", "metal"), ("_Bal", "concrete"),
        ("_BalR", "metal"), ("_BalP", "metal"),
    ]
    for i in range(FLOORS):
        rules.append(("_G%d" % i, "glass"))
    rules.append(("_RG", "glass"))
    return _finish("Prop_city_hotel", parts, rules)


# ============================================================ 警局
def build_city_police():
    """警局:政务楼 + 门廊柱 + 蓝白条 + 旗杆 + 停车区"""
    reset()
    parts = []
    W, D, H = 16.0, 11.0, 9.0
    parts.append(_box("_Base", (W + 1.0, 0.7, D + 1.0), (0, 0.35, 0), bev=0.03))
    parts.append(_box("_Body", (W, H, D), (0, 0.7 + H * 0.5, 0), bev=0.035))
    # 蓝白装饰条(腰线)
    parts.append(_box("_Stripe1", (W + 0.16, 0.55, D + 0.16), (0, 2.2, 0), bev=0.02))
    parts.append(_box("_Stripe2", (W + 0.16, 0.35, D + 0.16), (0, 6.2, 0), bev=0.02))
    # 窗(两层,每层 5 扇 + 窗台)
    for i in range(2):
        yw = 3.4 + i * 3.2
        for k in range(5):
            wx = (k / 4.0 - 0.5) * (W - 3.0)
            parts.append(_box("_Win%d_%d" % (i, k), (1.7, 1.9, 0.14), (wx, yw, -D * 0.5 + 0.05), bev=0.015))
            parts.append(_box("_WinS%d_%d" % (i, k), (1.95, 0.14, 0.30), (wx, yw - 1.05, -D * 0.5 + 0.08), bev=0.012))
    parts += add_cornice("_Cor", W, D, 0.7 + H, out=0.36)
    parts += add_parapet("_Par", W, D, 0.7 + H + 0.55, h=0.95)
    parts.append(_box("_Roof", (W, 0.20, D), (0, 0.7 + H + 0.22, 0), bev=0.02))
    parts += add_roof_kit("_Rf", W, D, 0.7 + H + 0.32, seed=23)
    # 门廊(4 柱 + 山花 + 台阶)
    ez = -D * 0.5 - 2.2
    parts.append(_box("_Porch", (9.0, 0.35, 4.4), (0, 4.6, ez), bev=0.025))
    parts.append(_box("_Ped", (9.6, 1.6, 0.40), (0, 5.6, ez - 2.1), bev=0.03))
    parts.append(_box("_PedIn", (7.6, 1.0, 0.20), (0, 5.5, ez - 2.05), bev=0.02))
    for i in range(4):
        px = (i / 3.0 - 0.5) * 8.0
        parts.append(add_cyl("_PCol%d" % i, 0.44, 4.4, (px, 2.2, ez - 2.0), axis="y", seg=14, bevel=0.02))
        parts.append(_box("_PColB%d" % i, (1.0, 0.20, 1.0), (px, 0.10, ez - 2.0), bev=0.015))
    parts += add_steps("_St", 9.0, 0.7, n=3, run=0.38, z0=ez - 0.2)
    parts.append(_box("_Door", (2.8, 3.2, 0.18), (0, 2.30, -D * 0.5 + 0.06), bev=0.02))
    parts.append(_box("_DoorG", (2.3, 2.6, 0.10), (0, 2.05, -D * 0.5 + 0.01), bev=0.015))
    # 徽章 + 铭牌
    parts.append(add_cyl("_Badge", 0.85, 0.14, (0, 5.2, -D * 0.5 - 0.10), axis="z", seg=16, bevel=0.02))
    parts.append(_box("_Plate", (5.5, 0.80, 0.14), (0, 3.9, -D * 0.5 - 0.10), bev=0.015))
    # 旗杆 ×2 + 旗
    for s in (-1, 1):
        parts.append(add_cyl("_FP%d" % s, 0.08, 9.5, (s * 3.4, 4.75, ez - 4.0), axis="y", seg=8))
        parts.append(_box("_FC%d" % s, (1.6, 0.95, 0.05), (s * 3.4 + 0.82, 8.7, ez - 4.0), bev=0.015))
    # 停车区(车位线 + 隔离墩)
    for i in range(4):
        parts.append(_box("_Line%d" % i, (0.14, 0.03, 4.0), (W * 0.5 + 3.0 + i * 2.8, 0.72, 4.0), bev=0.008))
    for i in range(3):
        parts.append(_box("_Bol%d" % i, (0.32, 0.72, 0.32), (W * 0.5 - 2.0, 1.06, -D * 0.5 - 3.4 + i * 2.2), bev=0.02))
    rules = [
        ("_Base", "concrete"), ("_Body", "wall"), ("_Stripe", "sign"),
        ("_Win", "glass"), ("_WinS", "trim"), ("_Cor", "trim"), ("_Par", "wall"),
        ("_Roof", "roof"), ("_Rf", "metal"), ("_Porch", "concrete"), ("_Ped", "trim"),
        ("_PedIn", "wall"), ("_PCol", "trim"), ("_PColB", "concrete"), ("_St", "concrete"),
        ("_Door", "trim"), ("_DoorG", "glass"), ("_Badge", "sign"), ("_Plate", "sign"),
        ("_FP", "metal"), ("_FC", "sign"), ("_Line", "sign"), ("_Bol", "metal"),
    ]
    return _finish("Prop_city_police", parts, rules)


# ============================================================ 工地
def build_city_construct():
    """工地:塔吊 + 在建楼(裸框架 + 脚手架) + 水泥管 + 围挡 + 工棚"""
    reset()
    parts = []
    # --- 塔吊(基座 + 标准节桁架 + 驾驶室 + 吊臂 + 配重 + 吊钩)
    tx, tz = -6.0, -4.0
    TH = 26.0
    parts.append(_box("_CraneBase", (3.0, 1.2, 3.0), (tx, 0.60, tz), bev=0.03))
    # 标准节(4 腿 + 横撑 + 斜撑,每 2.2m 一节)
    n_seg = int(TH / 2.2)
    for s_i in range(n_seg):
        y0s = 1.2 + s_i * 2.2
        for px in (-1, 1):
            for pz in (-1, 1):
                parts.append(_box("_CLeg%d%d%d" % (s_i, px, pz), (0.14, 2.2, 0.14),
                                  (tx + px * 0.75, y0s + 1.1, tz + pz * 0.75), bev=0.012))
        for k in range(2):
            ys = y0s + 0.55 + k * 1.4
            for ax in ("x", "z"):
                for s2 in (-1, 1):
                    if ax == "x":
                        parts.append(_box("_CBr%d%d%d" % (s_i, k, s2), (1.5, 0.09, 0.09),
                                          (tx, ys, tz + s2 * 0.75), bev=0.008))
                    else:
                        parts.append(_box("_CBr2%d%d%d" % (s_i, k, s2), (0.09, 0.09, 1.5),
                                          (tx + s2 * 0.75, ys, tz), bev=0.008))
            # 斜撑
            parts.append(_box("_CDiag%d%d" % (s_i, k), (1.75, 0.08, 0.08),
                              (tx, ys + 0.55, tz - 0.75), bev=0.008, rot=(0, 0, 0.62)))
    top_y = 1.2 + n_seg * 2.2
    # 回转平台 + 驾驶室
    parts.append(_box("_CTur", (1.9, 0.45, 1.9), (tx, top_y + 0.3, tz), bev=0.02))
    parts.append(_box("_CCab", (1.7, 1.9, 1.5), (tx + 1.3, top_y + 1.4, tz), bev=0.03))
    parts.append(_box("_CCabG", (1.4, 1.1, 0.10), (tx + 2.12, top_y + 1.7, tz), bev=0.015))
    # 塔尖
    parts.append(add_cyl("_CTip", 0.10, 4.0, (tx, top_y + 2.6, tz), axis="y", seg=6))
    # 吊臂(前臂 + 拉杆 + 配重臂)
    parts.append(_box("_CJib", (22.0, 0.60, 0.60), (tx + 11.0, top_y + 0.75, tz), bev=0.02))
    for i in range(8):
        parts.append(_box("_CJibD%d" % i, (0.08, 0.08, 0.08),
                          (tx + 2.5 + i * 2.5, top_y + 1.55, tz), bev=0.006))
    parts.append(_box("_CTie1", (0.10, 0.10, 15.0), (tx + 6.0, top_y + 3.2, tz), bev=0.008,
                      rot=(0.28, 0, 0)))
    parts.append(_box("_CWeight", (1.6, 1.3, 1.4), (tx - 4.2, top_y + 0.9, tz), bev=0.03))
    # 吊钩 + 缆绳
    parts.append(_box("_CCable", (0.06, 11.0, 0.06), (tx + 17.0, top_y - 5.0, tz), bev=0.006))
    parts.append(_box("_CHook", (0.5, 0.6, 0.5), (tx + 17.0, top_y - 10.6, tz), bev=0.02))
    # --- 在建楼(裸框架 + 楼板 + 脚手架)
    BW, BD, BF = 12.0, 10.0, 5
    bx, bz = 7.0, 2.0
    for i in range(BF + 1):
        yf = 0.0 + i * 3.3
        parts.append(_box("_Slab%d" % i, (BW, 0.30, BD), (bx, yf, bz), bev=0.02))
    for i in range(6):
        px = (i / 5.0 - 0.5) * (BW - 1.0)
        for pz in (-1, 1):
            parts.append(_box("_Col%d%d" % (i, pz), (0.42, BF * 3.3, 0.42),
                              (bx + px, BF * 3.3 * 0.5, bz + pz * (BD * 0.5 - 0.4)), bev=0.015))
    # 脚手架(外立面网 + 横杆 + 立杆)
    for i in range(7):
        py = 1.0 + i * 2.4
        parts.append(_box("_ScH%d" % i, (BW + 1.2, 0.08, 0.08), (bx, py, bz - BD * 0.5 - 0.8), bev=0.006))
    for i in range(6):
        px = (i / 5.0 - 0.5) * (BW + 1.0)
        parts.append(_box("_ScV%d" % i, (0.08, 15.0, 0.08), (bx + px, 7.5, bz - BD * 0.5 - 0.8), bev=0.006))
    parts.append(_box("_ScNet", (BW + 1.2, 15.0, 0.06), (bx, 7.5, bz - BD * 0.5 - 0.90), bev=0.004))
    # --- 地面:水泥管 + 围挡 + 工棚 + 搅拌机
    for i in range(3):
        parts.append(add_cyl("_Pipe%d" % i, 0.62, 2.6, (-8.0 + i * 1.4, 0.62, 8.0),
                             axis="z", seg=14, bevel=0.02))
    parts.append(add_cyl("_Mixer", 0.85, 1.8, (bx - 9.0, 1.0, bz + 6.0), axis="y", seg=14,
                         taper=0.72, bevel=0.03))
    parts.append(_box("_Shed", (4.0, 2.6, 3.0), (-11.0, 1.3, -6.0), bev=0.03))
    parts.append(_box("_ShedR", (4.5, 0.22, 3.5), (-11.0, 2.75, -6.0), bev=0.02))
    # 围挡(板 + 立柱)
    for i in range(10):
        parts.append(_box("_Fence%d" % i, (2.4, 2.0, 0.10), (-14.0 + i * 2.5, 1.0, -9.0), bev=0.015))
        parts.append(_box("_FenceP%d" % i, (0.14, 2.2, 0.14), (-14.0 + i * 2.5, 1.1, -9.10), bev=0.01))
    rules = [
        ("_CraneBase", "concrete"), ("_CLeg", "metal"), ("_CBr", "metal"), ("_CBr2", "metal"),
        ("_CDiag", "metal"), ("_CTur", "metal"), ("_CCab", "metal"), ("_CCabG", "glass"),
        ("_CTip", "metal"), ("_CJib", "metal"), ("_CJibD", "metal"), ("_CTie", "metal"),
        ("_CWeight", "concrete"), ("_CCable", "metal"), ("_CHook", "metal"),
        ("_Slab", "concrete"), ("_Col", "concrete"), ("_ScH", "metal"), ("_ScV", "metal"),
        ("_ScNet", "sign"), ("_Pipe", "concrete"), ("_Mixer", "metal"),
        ("_Shed", "wall"), ("_ShedR", "roof"), ("_Fence", "sign"), ("_FenceP", "metal"),
    ]
    return _finish("Prop_city_construct", parts, rules)


# ============================================================ 小公园
def build_city_park():
    """小公园:中央喷泉 + 环形步道 + 长椅 + 树池 + 灯柱 + 凉亭"""
    reset()
    parts = []
    R = 11.0
    # 草坪底盘
    parts.append(add_cyl("_Lawn", R, 0.30, (0, 0.15, 0), axis="y", seg=36, bevel=0.05))
    # 环形步道(外圈)
    parts.append(add_cyl("_Path", R - 0.9, 0.16, (0, 0.24, 0), axis="y", seg=36, bevel=0.03))
    # --- 中央喷泉(池 + 水 + 柱 + 顶盘 + 喷头)
    parts.append(add_cyl("_Pool", 3.4, 0.95, (0, 0.62, 0), axis="y", seg=24, bevel=0.04))
    parts.append(add_cyl("_PoolRim", 3.6, 0.20, (0, 1.14, 0), axis="y", seg=24, bevel=0.03))
    parts.append(add_cyl("_Water", 3.15, 0.10, (0, 1.06, 0), axis="y", seg=24))
    parts.append(add_cyl("_Stem", 0.42, 2.2, (0, 2.20, 0), axis="y", seg=16, bevel=0.02))
    parts.append(add_cyl("_Bowl1", 1.30, 0.22, (0, 3.30, 0), axis="y", seg=20, bevel=0.025))
    parts.append(add_cyl("_Bowl2", 0.80, 0.18, (0, 3.85, 0), axis="y", seg=18, bevel=0.02))
    parts.append(add_cyl("_Jet", 0.20, 0.55, (0, 4.25, 0), axis="y", seg=14, bevel=0.015))
    # 池边坐凳(8 张,沿池沿)
    for i in range(8):
        a = i * math.tau / 8.0 + 0.4
        bx, bz = math.sin(a) * 4.6, math.cos(a) * 4.6
        parts.append(_box("_BS%d" % i, (1.5, 0.12, 0.45), (bx, 0.55, bz), bev=0.02, rot=(0, -a, 0)))
        for s in (-1, 1):
            parts.append(_box("_BL%d%d" % (i, s), (0.10, 0.42, 0.40),
                              (bx + math.cos(a) * s * 0.6, 0.32, bz - math.sin(a) * s * 0.6), bev=0.012))
    # --- 长椅 ×6(外圈)
    for i in range(6):
        a = i * math.tau / 6.0 + 0.9
        bx, bz = math.sin(a) * (R - 2.2), math.cos(a) * (R - 2.2)
        parts.append(_box("_BenchS%d" % i, (1.7, 0.10, 0.48), (bx, 0.48, bz), bev=0.02, rot=(0, -a, 0)))
        parts.append(_box("_BenchB%d" % i, (1.7, 0.50, 0.09),
                          (bx + math.cos(a) * 0.24, 0.72, bz - math.sin(a) * 0.24), bev=0.02, rot=(0, -a, 0)))
        for s in (-1, 1):
            parts.append(_box("_BenchL%d%d" % (i, s), (0.10, 0.42, 0.42),
                              (bx + math.cos(a) * s * 0.7, 0.24, bz - math.sin(a) * s * 0.7), bev=0.012))
    # --- 树池 ×5 + 树
    for i in range(5):
        a = i * math.tau / 5.0 + 0.25
        tx, tz = math.sin(a) * (R - 3.6), math.cos(a) * (R - 3.6)
        parts.append(add_cyl("_TP%d" % i, 0.95, 0.35, (tx, 0.42, tz), axis="y", seg=14, bevel=0.03))
        parts.append(add_cyl("_TTr%d" % i, 0.16, 2.6, (tx, 1.85, tz), axis="y", seg=8, taper=0.7))
        for k in range(3):
            parts.append(_box("_TCr%d%d" % (i, k), (1.5 - k * 0.3, 0.9, 1.5 - k * 0.3),
                              (tx + random.uniform(-0.3, 0.3), 3.2 + k * 0.7, tz + random.uniform(-0.3, 0.3)),
                              bev=0.16))
    # --- 灯柱 ×4
    for i in range(4):
        a = i * math.tau / 4.0 + 0.5
        lx, lz = math.sin(a) * (R - 1.4), math.cos(a) * (R - 1.4)
        parts.append(add_cyl("_LP%d" % i, 0.09, 4.5, (lx, 2.25, lz), axis="y", seg=8, bevel=0.015))
        parts.append(_box("_LArm%d" % i, (0.08, 0.08, 0.65), (lx, 4.45, lz - 0.32), bev=0.008))
        parts.append(_box("_LHead%d" % i, (0.52, 0.32, 0.52), (lx, 4.35, lz - 0.62), bev=0.03))
    # --- 凉亭(六柱 + 顶)
    gx, gz = 0.0, -(R - 2.6)
    for i in range(6):
        a = i * math.tau / 6.0
        parts.append(add_cyl("_GP%d" % i, 0.16, 3.2, (gx + math.sin(a) * 2.0, 1.60, gz + math.cos(a) * 2.0),
                             axis="y", seg=10, bevel=0.02))
    parts.append(add_cyl("_GRoof", 2.6, 1.3, (gx, 3.85, gz), axis="y", seg=6, taper=0.06, bevel=0.03))
    parts.append(add_cyl("_GTip", 0.14, 0.6, (gx, 4.75, gz), axis="y", seg=8))
    rules = [
        ("_Lawn", "grass"), ("_Path", "concrete"), ("_Pool", "concrete"),
        ("_PoolRim", "concrete"), ("_Water", "water"), ("_Stem", "concrete"),
        ("_Bowl", "concrete"), ("_Jet", "metal"), ("_BS", "wood"), ("_BL", "metal"),
        ("_BenchS", "wood"), ("_BenchB", "wood"), ("_BenchL", "metal"),
        ("_TP", "concrete"), ("_TTr", "bark"), ("_TCr", "leaf"),
        ("_LP", "metal"), ("_LArm", "metal"), ("_LHead", "sign"),
        ("_GP", "wood"), ("_GRoof", "roof"), ("_GTip", "metal"),
    ]
    return _finish("Prop_city_park", parts, rules)


BUILDERS = {
    "city_hospital": build_city_hospital,
    "city_shop": build_city_shop,
    "city_gas": build_city_gas,
    "city_mall": build_city_mall,
    "city_office": build_city_office,
    "city_church": build_city_church,
    "city_school": build_city_school,
    "city_warehouse": build_city_warehouse,
    "city_hotel": build_city_hotel,
    "city_police": build_city_police,
    "city_construct": build_city_construct,
    "city_park": build_city_park,
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
        tri = len(ob.data.polygons)
        print("[build] %-16s -> %s  (polys=%d)" % (pid, os.path.basename(path), tri))
        ok.append(pid)
    print("\n[done] city batch: %d/%d" % (len(ok), len(ids)))


if __name__ == "__main__":
    main()
