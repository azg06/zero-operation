"""
城市/场景 3A 级车辆批次(tools/blender/build_veh_city_batch.py)
产出 models/props/{id}.glb —— 单一合并网格、多材质槽,Godot 侧按材质名重贴 PBR。

与旧版"15 个裸方盒堆车"的区别(用户明确指出"本质上仍是一堆多边形"):
  * 车身用**多段倒角体**拼出腰线/引擎盖/后备箱/轮拱,而非单个长方盒
  * 前后风挡/侧窗均为**倾斜面**,座舱有真实的三厢/两厢轮廓
  * 车轮 = 轮胎(扁环) + 轮毂(盘 + 5 辐条 + 中心盖),不再是纯圆柱
  * 灯组 = 灯壳 + LED 灯带 + 反光碗;尾灯独立红色材质
  * 细节件:后视镜 / 门把手 / 雨刷 / 天线 / 排气管 / 车牌 / 格栅 / 保险杠

模型清单:
    veh_sedan     现代三厢轿车(4.6m)
    veh_suv       SUV(4.8m,行李架+踏板)
    veh_taxi      出租车(轿车变体 + 顶灯 + 涂装)
    veh_police    警车(轿车变体 + 双色涂装 + 顶灯排)
    veh_bus       公交车(11m,多窗 + 顶置空调 + 路牌屏)
    veh_ambulance 救护车(厢式 + 红十字 + 顶灯)
    veh_pickup    皮卡(5.3m,敞货厢 + 防滚架)
    veh_delivery  厢式货车(6.0m,封闭货厢 + 后门)

坐标:根在地面 y=0,**车头朝 -Z**(与 Godot 前方一致),单位米。
用法: blender --background --python build_veh_city_batch.py [-- veh_sedan veh_suv ...]
"""
import sys, os, math, random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/props"
random.seed(20260906)


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


# ============================================================ 车轮(3A:胎+毂+辐条)
def add_wheel(prefix, cx, cy, cz, r_tire=0.34, w_tire=0.24, spokes=5):
    """车轮总成:轮胎(扁环) + 轮毂盘 + 辐条 + 中心盖。轴沿 X(车宽方向)。"""
    parts = []
    # 轮胎(外圈:扁圆柱模拟胎壁 + 胎面环)
    parts.append(add_cyl("%s_Tire" % prefix, r_tire, w_tire, (cx, cy, cz),
                         axis="x", seg=20, bevel=0.012))
    # 胎面凹槽(几条细环,增加细节密度)
    for k in range(3):
        rr = r_tire - 0.012
        parts.append(add_cyl("%s_Groove%d" % (prefix, k), rr, w_tire * 0.24,
                             (cx, cy, cz), axis="x", seg=18))
    # 轮毂盘
    parts.append(add_cyl("%s_Rim" % prefix, r_tire * 0.62, w_tire * 0.86, (cx, cy, cz),
                         axis="x", seg=16, bevel=0.008))
    # 辐条
    for k in range(spokes):
        a = k * math.tau / float(spokes)
        sy = math.sin(a) * r_tire * 0.34
        sz = math.cos(a) * r_tire * 0.34
        parts.append(_box("%s_Spoke%d" % (prefix, k),
                          (w_tire * 0.80, r_tire * 0.46, 0.075),
                          (cx, cy + sy, cz + sz), bev=0.008, rot=(a, 0, 0)))
    # 中心盖
    parts.append(add_cyl("%s_Cap" % prefix, r_tire * 0.16, w_tire * 0.92, (cx, cy, cz),
                         axis="x", seg=12, bevel=0.006))
    return parts


# ============================================================ 灯组(3A:壳+LED+反光碗)
def add_headlight(prefix, x, y, z, w=0.42, h=0.16, axis="z"):
    """前大灯组:灯壳(镀铬) + LED 灯带 + 反光碗"""
    parts = []
    parts.append(_box("%s_HL" % prefix, (w, h, 0.16), (x, y, z), bev=0.012))
    parts.append(_box("%s_LED" % prefix, (w * 0.86, h * 0.42, 0.06),
                      (x, y + h * 0.10, z - 0.09), bev=0.006))
    parts.append(_box("%s_Bowl" % prefix, (w * 0.70, h * 0.55, 0.08),
                      (x, y - h * 0.12, z - 0.05), bev=0.008))
    return parts


def add_taillight(prefix, x, y, z, w=0.40, h=0.14):
    """尾灯:灯壳 + 红色灯带"""
    parts = []
    parts.append(_box("%s_TL" % prefix, (w, h, 0.14), (x, y, z), bev=0.012))
    parts.append(_box("%s_TLG" % prefix, (w * 0.86, h * 0.50, 0.06),
                      (x, y, z + 0.08), bev=0.006))
    return parts


# ============================================================ 轿车底盘/车身(共享)
def _sedan_shell(prefix, L=4.60, W=1.86, body_h=0.62, cabin_h=0.56,
                 ground=0.30, bev=0.035):
    """
    三厢轿车壳体:底盘 → 下车身(带腰线) → 座舱(倾斜风挡) → 车顶。
    车头朝 -Z。返回 (parts, 关键高度字典)。
    """
    parts = []
    hw = W * 0.5
    zf = -L * 0.5          # 车头 z
    zb = L * 0.5           # 车尾 z
    # --- 底盘(离地间隙)
    y_chassis = ground
    parts.append(_box("%s_Chassis" % prefix, (W - 0.16, 0.20, L - 0.30),
                      (0, y_chassis, 0), bev=0.02))
    # --- 下车身(主箱体 + 前后收窄 + 腰线)
    y_body = y_chassis + body_h * 0.5 + 0.08
    parts.append(_box("%s_Body" % prefix, (W, body_h, L - 0.22), (0, y_body, 0), bev=bev))
    # 引擎盖段(略低、前倾)
    parts.append(_box("%s_Hood" % prefix, (W - 0.10, 0.14, L * 0.26),
                      (0, y_body + body_h * 0.44, zf + L * 0.17), bev=0.03,
                      rot=(-0.055, 0, 0)))
    # 后备箱段(略低)
    parts.append(_box("%s_Trunk" % prefix, (W - 0.10, 0.13, L * 0.20),
                      (0, y_body + body_h * 0.44, zb - L * 0.13), bev=0.03,
                      rot=(0.045, 0, 0)))
    # 腰线(贯穿侧面的凹槽条)
    for s in (-1, 1):
        parts.append(_box("%s_Belt%d" % (prefix, s), (0.05, 0.055, L - 0.60),
                          (s * (hw + 0.01), y_body + body_h * 0.16, 0), bev=0.008))
    # 轮拱(四轮外凸弧板)
    for sx in (-1, 1):
        for sz, zc in ((-1, -L * 0.30), (1, L * 0.30)):
            parts.append(add_cyl("%s_Arch%d%d" % (prefix, sx, sz), 0.46, 0.20,
                                 (sx * (hw - 0.06), y_chassis + 0.10, zc),
                                 axis="x", seg=14, bevel=0.012))
    # --- 座舱(前风挡倾斜 / 后风挡倾斜 / 车顶)
    y_cab0 = y_body + body_h * 0.5
    z_wind_f = -L * 0.06
    z_wind_b = L * 0.40
    parts.append(_box("%s_WindF" % prefix, (W - 0.14, cabin_h * 0.92, 0.10),
                      (0, y_cab0 + cabin_h * 0.50, z_wind_f), bev=0.020,
                      rot=(-0.62, 0, 0)))
    parts.append(_box("%s_WindB" % prefix, (W - 0.20, cabin_h * 0.88, 0.10),
                      (0, y_cab0 + cabin_h * 0.48, z_wind_b), bev=0.020,
                      rot=(0.55, 0, 0)))
    parts.append(_box("%s_Roof" % prefix, (W - 0.26, 0.09, L * 0.42),
                      (0, y_cab0 + cabin_h * 0.92, 0.10), bev=0.025))
    # A/B/C 柱 + 侧窗
    for s in (-1, 1):
        parts.append(_box("%s_PillarA%d" % (prefix, s), (0.09, cabin_h * 0.86, 0.10),
                          (s * (hw - 0.09), y_cab0 + cabin_h * 0.48, z_wind_f + 0.02),
                          bev=0.012, rot=(-0.62, 0, 0)))
        parts.append(_box("%s_PillarC%d" % (prefix, s), (0.09, cabin_h * 0.82, 0.10),
                          (s * (hw - 0.11), y_cab0 + cabin_h * 0.46, z_wind_b - 0.02),
                          bev=0.012, rot=(0.55, 0, 0)))
        parts.append(_box("%s_WinF%d" % (prefix, s), (0.05, cabin_h * 0.66, L * 0.20),
                          (s * (hw - 0.055), y_cab0 + cabin_h * 0.56, -L * 0.16), bev=0.010))
        parts.append(_box("%s_WinR%d" % (prefix, s), (0.05, cabin_h * 0.66, L * 0.19),
                          (s * (hw - 0.055), y_cab0 + cabin_h * 0.56, L * 0.22), bev=0.010))
    info = {
        "hw": hw, "zf": zf, "zb": zb, "y_body": y_body, "y_cab0": y_cab0,
        "body_h": body_h, "cabin_h": cabin_h, "ground": ground, "L": L, "W": W,
    }
    return parts, info


def _sedan_details(prefix, info, with_mirror=True, with_rack=False):
    """通用细节:后视镜 / 门把手 / 雨刷 / 天线 / 排气管 / 车牌 / 格栅 / 保险杠"""
    parts = []
    hw, zf, zb = info["hw"], info["zf"], info["zb"]
    y_body = info["y_body"]
    body_h = info["body_h"]
    y_cab0 = info["y_cab0"]
    # 后视镜(支臂 + 壳体 + 镜面)
    if with_mirror:
        for s in (-1, 1):
            parts.append(_box("%s_MirA%d" % (prefix, s), (0.16, 0.05, 0.05),
                              (s * (hw - 0.02), y_cab0 + 0.32, -info["L"] * 0.10), bev=0.008))
            parts.append(_box("%s_Mir%d" % (prefix, s), (0.19, 0.11, 0.09),
                              (s * (hw + 0.10), y_cab0 + 0.32, -info["L"] * 0.10), bev=0.015))
            parts.append(_box("%s_MirG%d" % (prefix, s), (0.03, 0.085, 0.07),
                              (s * (hw + 0.195), y_cab0 + 0.32, -info["L"] * 0.10), bev=0.006))
    # 门把手
    for s in (-1, 1):
        parts.append(_box("%s_HandleF%d" % (prefix, s), (0.05, 0.045, 0.20),
                          (s * (hw + 0.005), y_body + body_h * 0.10, -info["L"] * 0.08), bev=0.008))
        parts.append(_box("%s_HandleR%d" % (prefix, s), (0.05, 0.045, 0.20),
                          (s * (hw + 0.005), y_body + body_h * 0.10, info["L"] * 0.20), bev=0.008))
    # 雨刷
    parts.append(_box("%s_Wiper" % prefix, (0.60, 0.02, 0.02),
                      (0.0, y_cab0 + 0.30, -info["L"] * 0.13), bev=0.004, rot=(0, 0.30, 0)))
    # 鲨鱼鳍天线
    parts.append(_box("%s_Ant" % prefix, (0.05, 0.13, 0.20),
                      (0, y_cab0 + info["cabin_h"] * 0.96, info["L"] * 0.34), bev=0.012,
                      rot=(0.25, 0, 0)))
    # 排气管
    parts.append(add_cyl("%s_Exh" % prefix, 0.055, 0.22, (-0.45, info["ground"] + 0.02, zb - 0.06),
                         axis="z", seg=12, bevel=0.008))
    # 前后车牌
    parts.append(_box("%s_PlateF" % prefix, (0.44, 0.13, 0.03), (0, y_body + 0.06, zf - 0.02), bev=0.006))
    parts.append(_box("%s_PlateB" % prefix, (0.44, 0.13, 0.03), (0, y_body + 0.06, zb + 0.02), bev=0.006))
    # 前格栅(横条 + 边框)
    parts.append(_box("%s_Grille" % prefix, (info["W"] * 0.56, 0.30, 0.08),
                      (0, y_body + 0.10, zf - 0.02), bev=0.012))
    for k in range(4):
        parts.append(_box("%s_GBar%d" % (prefix, k), (info["W"] * 0.50, 0.022, 0.05),
                          (0, y_body - 0.02 + k * 0.085, zf - 0.05), bev=0.005))
    # 保险杠(前后)
    parts.append(_box("%s_BumpF" % prefix, (info["W"] + 0.02, 0.20, 0.20),
                      (0, info["ground"] + 0.14, zf + 0.02), bev=0.020))
    parts.append(_box("%s_BumpB" % prefix, (info["W"] + 0.02, 0.20, 0.18),
                      (0, info["ground"] + 0.14, zb - 0.02), bev=0.020))
    return parts


# ============================================================ 现代轿车
def build_veh_sedan():
    reset()
    parts, info = _sedan_shell("_", L=4.60, W=1.86)
    hw, zf, zb = info["hw"], info["zf"], info["zb"]
    y_body, body_h = info["y_body"], info["body_h"]
    # 车轮
    for sx in (-1, 1):
        for zc in (-info["L"] * 0.30, info["L"] * 0.30):
            parts += add_wheel("_W%d_%s" % (sx, "F" if zc < 0 else "R"),
                               sx * (hw - 0.10), 0.34, zc)
    # 灯组
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.62, y_body + 0.16, zf - 0.06)
        parts += add_taillight("_TL%d" % s, s * 0.60, y_body + 0.18, zb + 0.06)
    parts += _sedan_details("_", info)
    rules = [
        ("_Chassis", "metal_dark"), ("_Body", "car_paint"), ("_Hood", "car_paint"),
        ("_Trunk", "car_paint"), ("_Belt", "trim"), ("_Arch", "car_paint"),
        ("_WindF", "glass"), ("_WindB", "glass"), ("_Roof", "car_paint"),
        ("_Pillar", "trim"), ("_WinF", "glass"), ("_WinR", "glass"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
        ("_Mir", "car_paint"), ("_MirG", "glass"), ("_MirA", "trim"),
        ("_Handle", "chrome"), ("_Wiper", "metal_dark"), ("_Ant", "car_paint"),
        ("_Exh", "chrome"), ("_Plate", "plate"), ("_Grille", "metal_dark"),
        ("_GBar", "chrome"), ("_Bump", "trim"),
    ]
    return _finish("Prop_veh_sedan", parts, rules)


# ============================================================ SUV
def build_veh_suv():
    reset()
    parts, info = _sedan_shell("_", L=4.82, W=1.94, body_h=0.72, cabin_h=0.62,
                               ground=0.40, bev=0.038)
    hw, zf, zb = info["hw"], info["zf"], info["zb"]
    y_body, body_h = info["y_body"], info["body_h"]
    y_cab0 = info["y_cab0"]
    # 更大的轮
    for sx in (-1, 1):
        for zc in (-info["L"] * 0.30, info["L"] * 0.30):
            parts += add_wheel("_W%d_%s" % (sx, "F" if zc < 0 else "R"),
                               sx * (hw - 0.10), 0.42, zc, r_tire=0.40, w_tire=0.28, spokes=6)
    # 车顶行李架(纵轨 + 横杆)
    for s in (-1, 1):
        parts.append(_box("_Rail%d" % s, (0.07, 0.07, info["L"] * 0.46),
                          (s * (hw - 0.34), y_cab0 + info["cabin_h"] * 0.98, 0.10), bev=0.010))
    for k in range(2):
        parts.append(_box("_Bar%d" % k, (hw * 1.36, 0.05, 0.07),
                          (0, y_cab0 + info["cabin_h"] * 1.02, -0.55 + k * 1.15), bev=0.010))
    # 侧踏板
    for s in (-1, 1):
        parts.append(_box("_Step%d" % s, (0.20, 0.06, info["L"] * 0.42),
                          (s * (hw + 0.06), info["ground"] + 0.06, 0.0), bev=0.012))
    # 灯组(更高位)
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.66, y_body + 0.20, zf - 0.06, w=0.46)
        parts += add_taillight("_TL%d" % s, s * 0.62, y_body + 0.24, zb + 0.06, w=0.42)
    parts += _sedan_details("_", info)
    rules = [
        ("_Chassis", "metal_dark"), ("_Body", "car_paint"), ("_Hood", "car_paint"),
        ("_Trunk", "car_paint"), ("_Belt", "trim"), ("_Arch", "car_paint"),
        ("_WindF", "glass"), ("_WindB", "glass"), ("_Roof", "car_paint"),
        ("_Pillar", "trim"), ("_WinF", "glass"), ("_WinR", "glass"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
        ("_Mir", "car_paint"), ("_MirG", "glass"), ("_MirA", "trim"),
        ("_Handle", "chrome"), ("_Wiper", "metal_dark"), ("_Ant", "car_paint"),
        ("_Exh", "chrome"), ("_Plate", "plate"), ("_Grille", "metal_dark"),
        ("_GBar", "chrome"), ("_Bump", "trim"), ("_Rail", "trim"), ("_Bar", "trim"),
        ("_Step", "trim"),
    ]
    return _finish("Prop_veh_suv", parts, rules)


def prefix_s(_x):
    return "_"


# ============================================================ 出租车
def build_veh_taxi():
    reset()
    parts, info = _sedan_shell("_", L=4.60, W=1.86)
    hw, zf, zb = info["hw"], info["zf"], info["zb"]
    y_body = info["y_body"]
    y_cab0 = info["y_cab0"]
    for sx in (-1, 1):
        for zc in (-info["L"] * 0.30, info["L"] * 0.30):
            parts += add_wheel("_W%d_%s" % (sx, "F" if zc < 0 else "R"),
                               sx * (hw - 0.10), 0.34, zc)
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.62, y_body + 0.16, zf - 0.06)
        parts += add_taillight("_TL%d" % s, s * 0.60, y_body + 0.18, zb + 0.06)
    parts += _sedan_details("_", info)
    # 顶灯(计价器灯箱)
    parts.append(_box("_TaxiBase", (0.34, 0.05, 0.24), (0, y_cab0 + info["cabin_h"] * 0.99, -0.15), bev=0.008))
    parts.append(_box("_TaxiSign", (0.44, 0.20, 0.30), (0, y_cab0 + info["cabin_h"] * 0.99 + 0.14, -0.15), bev=0.018))
    parts.append(_box("_TaxiFace", (0.38, 0.11, 0.06), (0, y_cab0 + info["cabin_h"] * 0.99 + 0.14, -0.30), bev=0.008))
    # 车身涂装条(黄色带)
    parts.append(_box("_LiveryF", (info["W"] + 0.03, 0.16, 0.06), (0, y_body + 0.02, -0.6), bev=0.006))
    parts.append(_box("_LiveryB", (info["W"] + 0.03, 0.16, 0.06), (0, y_body + 0.02, 0.6), bev=0.006))
    rules = [
        ("_Chassis", "metal_dark"), ("_Body", "car_paint"), ("_Hood", "car_paint"),
        ("_Trunk", "car_paint"), ("_Belt", "trim"), ("_Arch", "car_paint"),
        ("_WindF", "glass"), ("_WindB", "glass"), ("_Roof", "car_paint"),
        ("_Pillar", "trim"), ("_WinF", "glass"), ("_WinR", "glass"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
        ("_Mir", "car_paint"), ("_MirG", "glass"), ("_MirA", "trim"),
        ("_Handle", "chrome"), ("_Wiper", "metal_dark"), ("_Ant", "car_paint"),
        ("_Exh", "chrome"), ("_Plate", "plate"), ("_Grille", "metal_dark"),
        ("_GBar", "chrome"), ("_Bump", "trim"),
        ("_TaxiBase", "metal_dark"), ("_TaxiSign", "sign"), ("_TaxiFace", "sign"),
        ("_Livery", "sign"),
    ]
    return _finish("Prop_veh_taxi", parts, rules)


# ============================================================ 警车
def build_veh_police():
    reset()
    parts, info = _sedan_shell("_", L=4.70, W=1.88)
    hw, zf, zb = info["hw"], info["zf"], info["zb"]
    y_body = info["y_body"]
    y_cab0 = info["y_cab0"]
    for sx in (-1, 1):
        for zc in (-info["L"] * 0.30, info["L"] * 0.30):
            parts += add_wheel("_W%d_%s" % (sx, "F" if zc < 0 else "R"),
                               sx * (hw - 0.10), 0.34, zc)
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.62, y_body + 0.16, zf - 0.06)
        parts += add_taillight("_TL%d" % s, s * 0.60, y_body + 0.18, zb + 0.06)
    parts += _sedan_details("_", info)
    # 警灯排(底座 + 左右灯罩 + 中间控制器)
    y_top = y_cab0 + info["cabin_h"] * 0.99
    parts.append(_box("_LightBar", (1.24, 0.10, 0.30), (0, y_top + 0.04, -0.10), bev=0.012))
    parts.append(_box("_LightL", (0.46, 0.19, 0.26), (-0.36, y_top + 0.18, -0.10), bev=0.015))
    parts.append(_box("_LightR", (0.46, 0.19, 0.26), (0.36, y_top + 0.18, -0.10), bev=0.015))
    parts.append(_box("_LightC", (0.24, 0.15, 0.24), (0, y_top + 0.16, -0.10), bev=0.012))
    # 双色涂装(白车身 + 黑前后段 + 侧面 POLICE 条)
    parts.append(_box("_LivF", (info["W"] + 0.02, 0.42, 0.90), (0, y_body + 0.06, -1.55), bev=0.008))
    parts.append(_box("_LivB", (info["W"] + 0.02, 0.42, 0.80), (0, y_body + 0.06, 1.70), bev=0.008))
    for s in (-1, 1):
        parts.append(_box("_Stripe%d" % s, (0.04, 0.30, 1.5),
                          (s * (hw + 0.015), y_body + 0.02, 0.1), bev=0.006))
    # 前保险杠推杠
    parts.append(_box("_PushBar", (info["W"] * 0.80, 0.42, 0.08), (0, info["ground"] + 0.34, zf - 0.14), bev=0.015))
    rules = [
        ("_Chassis", "metal_dark"), ("_Body", "car_paint"), ("_Hood", "car_paint"),
        ("_Trunk", "car_paint"), ("_Belt", "trim"), ("_Arch", "car_paint"),
        ("_WindF", "glass"), ("_WindB", "glass"), ("_Roof", "car_paint"),
        ("_Pillar", "trim"), ("_WinF", "glass"), ("_WinR", "glass"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
        ("_Mir", "car_paint"), ("_MirG", "glass"), ("_MirA", "trim"),
        ("_Handle", "chrome"), ("_Wiper", "metal_dark"), ("_Ant", "car_paint"),
        ("_Exh", "chrome"), ("_Plate", "plate"), ("_Grille", "metal_dark"),
        ("_GBar", "chrome"), ("_Bump", "trim"),
        ("_LightBar", "metal_dark"), ("_LightL", "lamp_blue"),
        ("_LightR", "lamp_red"), ("_LightC", "metal_dark"),
        ("_Liv", "metal_dark"), ("_Stripe", "sign"), ("_PushBar", "metal_dark"),
    ]
    return _finish("Prop_veh_police", parts, rules)


# ============================================================ 公交车
def build_veh_bus():
    reset()
    parts = []
    L, W, H = 11.0, 2.52, 3.15
    hw, zf, zb = W * 0.5, -L * 0.5, L * 0.5
    ground = 0.42
    # 底盘 + 主箱体
    parts.append(_box("_Chassis", (W - 0.20, 0.30, L - 0.40), (0, ground, 0), bev=0.025))
    yb = ground + 1.30
    parts.append(_box("_Body", (W, 2.30, L - 0.20), (0, yb, 0), bev=0.040))
    # 车顶(略收) + 顶置空调机组
    parts.append(_box("_Roof", (W - 0.10, 0.14, L - 0.30), (0, yb + 1.22, 0), bev=0.025))
    for k in range(3):
        parts.append(_box("_ACUnit%d" % k, (1.5, 0.34, 2.0),
                          (0, yb + 1.45, (k - 1) * 3.2), bev=0.02))
    # 前风挡(大倾斜) + 后窗
    parts.append(_box("_WindF", (W - 0.16, 1.55, 0.10), (0, yb + 0.42, zf + 0.06), bev=0.022,
                      rot=(-0.24, 0, 0)))
    parts.append(_box("_WindB", (W - 0.40, 1.10, 0.10), (0, yb + 0.35, zb - 0.06), bev=0.020,
                      rot=(0.16, 0, 0)))
    # 侧窗(每侧 5 扇 + 立柱)
    for s in (-1, 1):
        for k in range(5):
            zc = -L * 0.32 + k * (L * 0.155)
            parts.append(_box("_Win%d_%d" % (s, k), (0.06, 1.15, L * 0.125),
                              (s * (hw - 0.03), yb + 0.42, zc), bev=0.012))
        for k in range(6):
            zc = -L * 0.40 + k * (L * 0.155)
            parts.append(_box("_Post%d_%d" % (s, k), (0.09, 1.30, 0.11),
                              (s * (hw - 0.02), yb + 0.42, zc), bev=0.010))
    # 车门(前 + 中)
    for k, zc in enumerate((-L * 0.36, L * 0.06)):
        parts.append(_box("_DoorF%d" % k, (0.10, 2.05, 1.15), (hw + 0.02, yb - 0.10, zc), bev=0.018))
        parts.append(_box("_DoorG%d" % k, (0.06, 1.70, 0.52), (hw + 0.05, yb - 0.02, zc - 0.28), bev=0.012))
        parts.append(_box("_DoorG2%d" % k, (0.06, 1.70, 0.52), (hw + 0.05, yb - 0.02, zc + 0.28), bev=0.012))
    # 路牌屏(前 + 侧)
    parts.append(_box("_DestF", (1.70, 0.34, 0.08), (0, yb + 1.05, zf - 0.02), bev=0.010))
    parts.append(_box("_DestS", (0.06, 0.26, 1.10), (hw + 0.03, yb + 0.95, -L * 0.22), bev=0.008))
    # 保险杠 + 灯组 + 后视镜 + 轮
    parts.append(_box("_BumpF", (W + 0.04, 0.30, 0.22), (0, ground + 0.16, zf + 0.04), bev=0.022))
    parts.append(_box("_BumpB", (W + 0.04, 0.30, 0.20), (0, ground + 0.16, zb - 0.04), bev=0.022))
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.86, yb - 0.42, zf - 0.06, w=0.50, h=0.18)
        parts += add_taillight("_TL%d" % s, s * 0.84, yb - 0.30, zb + 0.06, w=0.46, h=0.16)
        # 后视镜(大巴长支臂)
        parts.append(_box("_MirA%d" % s, (0.30, 0.06, 0.06),
                          (s * (hw + 0.14), yb + 0.72, zf + 0.55), bev=0.010))
        parts.append(_box("_Mir%d" % s, (0.22, 0.30, 0.10),
                          (s * (hw + 0.32), yb + 0.66, zf + 0.50), bev=0.018))
    # 车轮(前 2 + 后 4 双胎)
    for sx in (-1, 1):
        parts += add_wheel("_WF%d" % sx, sx * (hw - 0.12), 0.46, -L * 0.30,
                           r_tire=0.46, w_tire=0.30, spokes=6)
        for k in range(2):
            parts += add_wheel("_WR%d_%d" % (sx, k), sx * (hw - 0.06 - k * 0.30), 0.46,
                               L * 0.28 + (k * 0.02), r_tire=0.46, w_tire=0.28, spokes=6)
    # 轮拱 + 侧裙 + 排气管
    for sx in (-1, 1):
        for zc in (-L * 0.30, L * 0.28):
            parts.append(add_cyl("_Arch%d_%d" % (sx, int(zc)), 0.60, W * 0.22,
                                 (sx * (hw - 0.08), 0.46, zc), axis="x", seg=14, bevel=0.015))
    for s in (-1, 1):
        parts.append(_box("_Skirt%d" % s, (0.10, 0.42, L - 2.6), (s * (hw + 0.01), ground - 0.02, 0), bev=0.012))
    parts.append(add_cyl("_Exh", 0.07, 0.30, (-hw + 0.30, ground - 0.05, zb - 0.40), axis="z", seg=10))
    rules = [
        ("_Chassis", "metal_dark"), ("_Body", "car_paint"), ("_Roof", "car_paint"),
        ("_ACUnit", "metal_dark"), ("_WindF", "glass"), ("_WindB", "glass"),
        ("_Win", "glass"), ("_Post", "trim"), ("_DoorF", "trim"), ("_DoorG", "glass"),
        ("_Dest", "sign"), ("_Bump", "trim"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
        ("_Mir", "metal_dark"), ("_MirA", "metal_dark"),
        ("_Arch", "car_paint"), ("_Skirt", "trim"), ("_Exh", "chrome"),
    ]
    return _finish("Prop_veh_bus", parts, rules)


# ============================================================ 救护车
def build_veh_ambulance():
    reset()
    parts = []
    L, W = 5.9, 2.16
    hw, zf, zb = W * 0.5, -L * 0.5, L * 0.5
    ground = 0.36
    # 底盘 + 驾驶室(前段)
    parts.append(_box("_Chassis", (W - 0.16, 0.24, L - 0.30), (0, ground, 0), bev=0.02))
    yb = ground + 0.86
    parts.append(_box("_Cab", (W - 0.04, 1.24, L * 0.30), (0, yb, zf + L * 0.16), bev=0.035))
    parts.append(_box("_WindF", (W - 0.18, 0.72, 0.10), (0, yb + 0.34, zf + L * 0.015), bev=0.018,
                      rot=(-0.52, 0, 0)))
    for s in (-1, 1):
        parts.append(_box("_WinF%d" % s, (0.05, 0.62, L * 0.11),
                          (s * (hw - 0.03), yb + 0.34, zf + L * 0.10), bev=0.010))
    # 医疗舱(后段大方厢)
    yv = ground + 1.16
    parts.append(_box("_Van", (W, 2.06, L * 0.62), (0, yv, zb - L * 0.31), bev=0.040))
    parts.append(_box("_VanRoof", (W - 0.08, 0.16, L * 0.60), (0, yv + 1.11, zb - L * 0.31), bev=0.025))
    # 车厢侧面:加强筋 + 小窗 + 红十字
    for s in (-1, 1):
        for k in range(3):
            parts.append(_box("_Rib%d_%d" % (s, k), (0.06, 1.90, 0.09),
                              (s * (hw + 0.01), yv, zb - L * 0.08 - k * 1.35), bev=0.010))
        parts.append(_box("_VanWin%d" % s, (0.05, 0.55, 0.70),
                          (s * (hw + 0.01), yv + 0.52, zb - L * 0.22), bev=0.010))
        parts.append(_box("_CrossV%d" % s, (0.04, 1.15, 0.32),
                          (s * (hw + 0.03), yv + 0.30, zb - L * 0.44), bev=0.012))
        parts.append(_box("_CrossH%d" % s, (0.04, 0.32, 1.15),
                          (s * (hw + 0.03), yv + 0.30, zb - L * 0.44), bev=0.012))
    # 后门(对开双门 + 把手 + 踏板)
    parts.append(_box("_DoorF", (W - 0.10, 1.85, 0.10), (0, yv - 0.05, zb - 0.02), bev=0.020))
    parts.append(_box("_DoorL", (0.06, 1.05, 0.06), (-0.35, yv - 0.05, zb - 0.09), bev=0.010))
    parts.append(_box("_DoorR", (0.06, 1.05, 0.06), (0.35, yv - 0.05, zb - 0.09), bev=0.010))
    parts.append(_box("_Step", (W * 0.5, 0.10, 0.34), (0, ground - 0.02, zb + 0.16), bev=0.012))
    # 顶灯排(前后各一 + 两侧闪灯)
    y_top = yv + 1.22
    for k, zc in enumerate((zf + L * 0.10, zb - L * 0.31)):
        parts.append(_box("_Bar%d" % k, (1.10, 0.09, 0.26), (0, y_top + 0.03, zc), bev=0.010))
        parts.append(_box("_BarL%d" % k, (0.40, 0.17, 0.23), (0, y_top + 0.16, zc), bev=0.014))
    for s in (-1, 1):
        parts.append(_box("_Flash%d" % s, (0.05, 0.16, 0.24),
                          (s * (hw + 0.02), yv + 0.72, zb - L * 0.22), bev=0.010))
    parts.append(_box("_Grille", (W * 0.52, 0.28, 0.08), (0, yb - 0.16, zf - 0.02), bev=0.012))
    parts.append(_box("_BumpF", (W + 0.02, 0.22, 0.20), (0, ground + 0.14, zf + 0.03), bev=0.020))
    parts.append(_box("_BumpB", (W + 0.02, 0.22, 0.18), (0, ground + 0.14, zb - 0.03), bev=0.020))
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.72, yb - 0.10, zf - 0.05, w=0.40)
        parts += add_taillight("_TL%d" % s, s * 0.82, yv - 0.42, zb + 0.06, w=0.34, h=0.30)
        parts.append(_box("_MirA%d" % s, (0.20, 0.05, 0.05), (s * (hw + 0.05), yb + 0.52, zf + L * 0.12), bev=0.008))
        parts.append(_box("_Mir%d" % s, (0.20, 0.24, 0.10), (s * (hw + 0.20), yb + 0.50, zf + L * 0.10), bev=0.018))
    for sx in (-1, 1):
        for zc in (-L * 0.30, L * 0.30):
            parts += add_wheel("_W%d_%s" % (sx, "F" if zc < 0 else "R"),
                               sx * (hw - 0.10), 0.40, zc, r_tire=0.40, w_tire=0.26, spokes=6)
    rules = [
        ("_Chassis", "metal_dark"), ("_Cab", "car_paint"), ("_WindF", "glass"),
        ("_WinF", "glass"), ("_Van", "car_paint"), ("_VanRoof", "car_paint"),
        ("_Rib", "trim"), ("_VanWin", "glass"),
        ("_CrossV", "sign"), ("_CrossH", "sign"),
        ("_DoorF", "trim"), ("_DoorL", "chrome"), ("_DoorR", "chrome"), ("_Step", "trim"),
        ("_Bar", "metal_dark"), ("_BarL", "lamp_red"), ("_Flash", "lamp_blue"),
        ("_Grille", "metal_dark"), ("_Bump", "trim"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
        ("_Mir", "metal_dark"), ("_MirA", "metal_dark"),
    ]
    return _finish("Prop_veh_ambulance", parts, rules)


# ============================================================ 皮卡
def build_veh_pickup():
    reset()
    parts = []
    L, W = 5.35, 1.96
    hw, zf, zb = W * 0.5, -L * 0.5, L * 0.5
    ground = 0.40
    parts.append(_box("_Chassis", (W - 0.16, 0.24, L - 0.30), (0, ground, 0), bev=0.02))
    yb = ground + 0.92
    # 驾驶室(双排座)
    parts.append(_box("_Cab", (W, 1.34, L * 0.40), (0, yb, zf + L * 0.22), bev=0.036))
    parts.append(_box("_WindF", (W - 0.18, 0.76, 0.10), (0, yb + 0.36, zf + L * 0.035), bev=0.018,
                      rot=(-0.50, 0, 0)))
    parts.append(_box("_WindB", (W - 0.24, 0.70, 0.10), (0, yb + 0.36, zf + L * 0.415), bev=0.018,
                      rot=(0.34, 0, 0)))
    parts.append(_box("_Roof", (W - 0.26, 0.10, L * 0.34), (0, yb + 0.73, zf + L * 0.22), bev=0.022))
    for s in (-1, 1):
        parts.append(_box("_WinF%d" % s, (0.05, 0.62, L * 0.14),
                          (s * (hw - 0.03), yb + 0.36, zf + L * 0.14), bev=0.010))
        parts.append(_box("_WinR%d" % s, (0.05, 0.62, L * 0.12),
                          (s * (hw - 0.03), yb + 0.36, zf + L * 0.32), bev=0.010))
        parts.append(_box("_Handle%d" % s, (0.05, 0.05, 0.22),
                          (s * (hw + 0.005), yb + 0.14, zf + L * 0.20), bev=0.008))
        parts.append(_box("_MirA%d" % s, (0.20, 0.05, 0.05), (s * (hw + 0.05), yb + 0.54, zf + L * 0.10), bev=0.008))
        parts.append(_box("_Mir%d" % s, (0.21, 0.26, 0.10), (s * (hw + 0.22), yb + 0.52, zf + L * 0.08), bev=0.018))
    # 货厢(底板 + 三面挡板 + 内衬筋)
    yd = ground + 0.62
    parts.append(_box("_Bed", (W, 0.12, L * 0.48), (0, yd, zb - L * 0.24), bev=0.020))
    for s in (-1, 1):
        parts.append(_box("_BedS%d" % s, (0.10, 0.52, L * 0.48),
                          (s * (hw - 0.05), yd + 0.32, zb - L * 0.24), bev=0.015))
    parts.append(_box("_BedF", (W, 0.56, 0.10), (0, yd + 0.34, zf + L * 0.42), bev=0.015))
    parts.append(_box("_BedT", (W, 0.46, 0.10), (0, yd + 0.29, zb - 0.02), bev=0.015))
    # 防滚架(货厢上方)
    for s in (-1, 1):
        parts.append(_box("_Roll%d" % s, (0.07, 0.62, 0.07),
                          (s * (hw - 0.30), yd + 0.86, zf + L * 0.44), bev=0.010))
    parts.append(_box("_RollT", (W - 0.52, 0.07, 0.07), (0, yd + 1.16, zf + L * 0.44), bev=0.010))
    # 灯组 + 保险杠 + 轮
    parts.append(_box("_Grille", (W * 0.56, 0.32, 0.08), (0, yb - 0.10, zf - 0.02), bev=0.012))
    parts.append(_box("_BumpF", (W + 0.03, 0.24, 0.22), (0, ground + 0.16, zf + 0.03), bev=0.020))
    parts.append(_box("_BumpB", (W * 0.9, 0.22, 0.16), (0, ground + 0.16, zb - 0.03), bev=0.018))
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.66, yb - 0.04, zf - 0.05, w=0.44)
        parts += add_taillight("_TL%d" % s, s * 0.74, yd + 0.42, zb + 0.05, w=0.34, h=0.26)
    for sx in (-1, 1):
        for zc in (-L * 0.29, L * 0.30):
            parts += add_wheel("_W%d_%s" % (sx, "F" if zc < 0 else "R"),
                               sx * (hw - 0.10), 0.42, zc, r_tire=0.42, w_tire=0.28, spokes=6)
        parts.append(add_cyl("_Arch%d" % sx, 0.55, 0.22, (sx * (hw - 0.06), 0.44, -L * 0.29),
                             axis="x", seg=14, bevel=0.014))
    parts.append(add_cyl("_Exh", 0.06, 0.24, (-hw + 0.35, ground + 0.02, zb - 0.10), axis="z", seg=10))
    rules = [
        ("_Chassis", "metal_dark"), ("_Cab", "car_paint"), ("_WindF", "glass"),
        ("_WindB", "glass"), ("_Roof", "car_paint"), ("_WinF", "glass"), ("_WinR", "glass"),
        ("_Handle", "chrome"), ("_Mir", "metal_dark"), ("_MirA", "metal_dark"),
        ("_Bed", "metal_dark"), ("_BedS", "car_paint"), ("_BedF", "car_paint"),
        ("_BedT", "car_paint"), ("_Roll", "chrome"), ("_RollT", "chrome"),
        ("_Grille", "metal_dark"), ("_Bump", "trim"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"), ("_Arch", "car_paint"),
        ("_Exh", "chrome"),
    ]
    return _finish("Prop_veh_pickup", parts, rules)


# ============================================================ 厢式货车
def build_veh_delivery():
    reset()
    parts = []
    L, W = 6.10, 2.20
    hw, zf, zb = W * 0.5, -L * 0.5, L * 0.5
    ground = 0.40
    parts.append(_box("_Chassis", (W - 0.16, 0.26, L - 0.30), (0, ground, 0), bev=0.02))
    yb = ground + 0.92
    parts.append(_box("_Cab", (W - 0.02, 1.30, L * 0.26), (0, yb, zf + L * 0.14), bev=0.036))
    parts.append(_box("_WindF", (W - 0.20, 0.74, 0.10), (0, yb + 0.36, zf + L * 0.02), bev=0.018,
                      rot=(-0.48, 0, 0)))
    for s in (-1, 1):
        parts.append(_box("_WinF%d" % s, (0.05, 0.60, L * 0.09),
                          (s * (hw - 0.03), yb + 0.36, zf + L * 0.09), bev=0.010))
        parts.append(_box("_MirA%d" % s, (0.22, 0.05, 0.05), (s * (hw + 0.06), yb + 0.56, zf + L * 0.10), bev=0.008))
        parts.append(_box("_Mir%d" % s, (0.22, 0.28, 0.10), (s * (hw + 0.24), yb + 0.54, zf + L * 0.08), bev=0.018))
    # 货厢(大方厢 + 顶 + 加强筋)
    yv = ground + 1.32
    parts.append(_box("_Box", (W, 2.40, L * 0.66), (0, yv, zb - L * 0.33), bev=0.042))
    parts.append(_box("_BoxTop", (W - 0.10, 0.14, L * 0.64), (0, yv + 1.27, zb - L * 0.33), bev=0.025))
    for s in (-1, 1):
        for k in range(4):
            parts.append(_box("_Rib%d_%d" % (s, k), (0.06, 2.20, 0.09),
                              (s * (hw + 0.01), yv, zb - L * 0.06 - k * 1.02), bev=0.010))
    parts.append(_box("_BoxRoof", (W * 0.62, 0.10, L * 0.40), (0, yv + 1.20, zb - L * 0.33), bev=0.015))
    # 后门(对开 + 铰链 + 把手)
    parts.append(_box("_DoorF", (W - 0.08, 2.20, 0.10), (0, yv - 0.08, zb - 0.02), bev=0.020))
    for s in (-1, 1):
        parts.append(_box("_DoorH%d" % s, (0.07, 1.30, 0.07), (s * 0.42, yv - 0.05, zb - 0.08), bev=0.010))
        parts.append(_box("_Hinge%d" % s, (0.10, 0.22, 0.10), (s * (hw - 0.06), yv + 0.62, zb - 0.06), bev=0.008))
    parts.append(_box("_Step", (W * 0.44, 0.10, 0.36), (0, ground - 0.02, zb + 0.18), bev=0.012))
    # 侧滑门 + 轨道
    parts.append(_box("_Slide", (0.06, 1.90, 1.30), (hw + 0.02, yv - 0.16, zb - L * 0.30), bev=0.015))
    parts.append(_box("_Rail", (0.06, 0.08, 1.40), (hw + 0.04, yv + 0.86, zb - L * 0.30), bev=0.008))
    # 灯组 + 保险杠 + 轮
    parts.append(_box("_Grille", (W * 0.54, 0.30, 0.08), (0, yb - 0.18, zf - 0.02), bev=0.012))
    parts.append(_box("_BumpF", (W + 0.03, 0.26, 0.24), (0, ground + 0.16, zf + 0.03), bev=0.020))
    parts.append(_box("_BumpB", (W * 0.86, 0.24, 0.18), (0, ground + 0.16, zb - 0.03), bev=0.018))
    for s in (-1, 1):
        parts += add_headlight("_HL%d" % s, s * 0.74, yb - 0.14, zf - 0.05, w=0.42)
        parts += add_taillight("_TL%d" % s, s * 0.86, yv - 0.72, zb + 0.06, w=0.32, h=0.34)
    for sx in (-1, 1):
        parts += add_wheel("_WF%d" % sx, sx * (hw - 0.12), 0.42, -L * 0.28,
                           r_tire=0.42, w_tire=0.28, spokes=6)
        for k in range(2):
            parts += add_wheel("_WR%d_%d" % (sx, k), sx * (hw - 0.06 - k * 0.30), 0.42,
                               L * 0.28, r_tire=0.42, w_tire=0.26, spokes=6)
    rules = [
        ("_Chassis", "metal_dark"), ("_Cab", "car_paint"), ("_WindF", "glass"),
        ("_WinF", "glass"), ("_Mir", "metal_dark"), ("_MirA", "metal_dark"),
        ("_Box", "car_paint"), ("_BoxTop", "car_paint"), ("_Rib", "trim"),
        ("_BoxRoof", "metal_dark"), ("_DoorF", "trim"), ("_DoorH", "chrome"),
        ("_Hinge", "chrome"), ("_Step", "trim"), ("_Slide", "car_paint"), ("_Rail", "chrome"),
        ("_Grille", "metal_dark"), ("_Bump", "trim"),
        ("_W", "tire"), ("_Tire", "tire"), ("_Groove", "tire"),
        ("_Rim", "chrome"), ("_Spoke", "chrome"), ("_Cap", "chrome"),
        ("_HL", "chrome"), ("_LED", "lamp_white"), ("_Bowl", "chrome"),
        ("_TL", "lamp_red"), ("_TLG", "lamp_red"),
    ]
    return _finish("Prop_veh_delivery", parts, rules)


BUILDERS = {
    "veh_sedan": build_veh_sedan,
    "veh_suv": build_veh_suv,
    "veh_taxi": build_veh_taxi,
    "veh_police": build_veh_police,
    "veh_bus": build_veh_bus,
    "veh_ambulance": build_veh_ambulance,
    "veh_pickup": build_veh_pickup,
    "veh_delivery": build_veh_delivery,
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
        print("[build] %-16s -> %s  (polys=%d)" % (pid, os.path.basename(path), len(ob.data.polygons)))
        ok.append(pid)
    print("\n[done] city vehicle batch: %d/%d" % (len(ok), len(ids)))


if __name__ == "__main__":
    main()
