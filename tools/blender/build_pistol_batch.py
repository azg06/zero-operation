"""
手枪批次建模(8 把):M1911 / G17 / P226 / Desert Eagle / M93R / Python / SW686 / SW500

尺寸沿用 weapon_models.gd 程序化定义,锚点零改动。

换弹契约:
    Slide             套筒(空仓 slide 风格后拉) —— 半自动 5 把
    RevolverCrane     弹巢摆出铰链(空对象) —— 左轮 3 把
    RevolverCylinder  弹巢(带退壳槽),parent 到 crane
    ChamberShell_N    逐膛弹壳(N=0..N-1),parent 到 cylinder,Godot 按膛位显隐
    RevolverHammer    击锤
    mag               弹匣(半自动)

用法:
    blender --background --python build_pistol_batch.py
    blender --background --python build_pistol_batch.py -- m1911 python
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


# ---------------------------------------------------------------- 通用组件

def pistol_sights(sight_y, front_z, rear_z, front_h, rear_h):
    """照门只留左右薄耳,中间缺口绝无中央挡块。"""
    parts = [
        add_box("SightsFront", (0.006, front_h, 0.008), (0, sight_y - front_h * 0.5, front_z), bevel=0.0003),
        add_box("SightsRearL", (0.003, rear_h, 0.012), (-0.0095, sight_y - rear_h * 0.5, rear_z), bevel=0.0003),
        add_box("SightsRearR", (0.003, rear_h, 0.012), (0.0095, sight_y - rear_h * 0.5, rear_z), bevel=0.0003),
    ]
    return join_parts("StockIrons", parts)


def pistol_grip(y, z, mat, w=0.030, h=0.09, d=0.044, tilt=0.35, ribs=0, rib_n=3):
    """手枪握把(倾斜)+ 可选防滑纹。"""
    add_grip("Grip", w, h, d, (0, y, z), tilt=tilt, mat=mat)
    for i in range(rib_n):
        add_box("_GripRib%d" % i, (w + 0.004, 0.006, d - 0.002),
                (0, y - h * 0.28 - i * 0.014, z), bevel=0.0003)


def hammer_block(y, z, w, h, mat, name="RevolverHammer"):
    """击锤(spir 斜面)。"""
    ham = add_empty(name, (0, y, z))
    spur = add_box("_HammerSpur", (w, h, 0.008), (0, y + h * 0.32, z - 0.002), bevel=0.0004)
    spur.rotation_euler.x = -0.22
    parent_to(spur, ham)
    return ham


def trigger_guard(y, z, w=0.026):
    return add_box("TriggerGuard", (w, 0.008, 0.075), (0, y, z), bevel=0.0005)


# ============================================================ 半自动 5 把

def _pistol_trigger(y, z, mat_hint="metal"):
    """扳机叶片(护圈内可见) + 护圈三段 U 形。"""
    blade = add_box("Trigger", (0.008, 0.022, 0.005), (0, y + 0.010, z - 0.006),
                    bevel=0.0004, rot_g=(0.18, 0, 0))
    guard = add_trigger_guard(y, z + 0.030, z - 0.042, depth=0.022)
    return [blade] + guard


def _pistol_levers(y, z, w_frame):
    """空挂释放杆(左) + 分解杆(左下) + 弹匣释放钮(右)。"""
    return [
        add_box("SlideStopLever", (0.004, 0.007, 0.028), (-w_frame * 0.5 - 0.002, y + 0.004, z - 0.010), bevel=0.0003),
        add_box("TakedownLever", (0.004, 0.006, 0.022), (-w_frame * 0.5 - 0.002, y - 0.008, z - 0.030), bevel=0.0003),
        add_box("MagRelease", (0.005, 0.010, 0.009), (w_frame * 0.5 + 0.002, y - 0.004, z + 0.008), bevel=0.0004),
    ]


def build_semi_auto(c):
    """半自动手枪统一构建器(参数见 SPEC)。
    套筒:主体 + 右侧抛壳窗布尔 + 尾部斜向拉栓槽 + 枪口冠 + 顶肋(可选);
    下机匣:防尘盖配件轨(可选) + 扳机/护圈/操作杆;
    握把:前后撑板滚花 + 两侧握把片(木/菱纹)。
    契约:Slide / mag / StockIrons / Hammer。"""
    reset()
    sw = c["slide_w"]; sh = c["slide_h"]; sl = c["slide_len"]
    sy = c["slide_y"]; sz = c["slide_z"]
    fw = c["frame_w"]; fh = c["frame_h"]; fl = c["frame_len"]
    fy = c["frame_y"]; fz = c["frame_z"]
    ry = c["barrel_y"]; sight_y = c["sight_y"]
    grip = c["grip"]; grip_mat = c["grip_mat"]
    frame_mat = c["frame_mat"]; slide_mat = c["slide_mat"]

    # ---- 套筒 ----
    # v5 结构性修复(用户实拍"机匣右侧长方形镂空露背景"的真正根因):
    # 旧版把 体/面壁/顶肋/尾板 join 成多壳体后再做布尔 —— 面壁内侧面与盒体
    # 侧面严格共面(x=±0.017),EXACT 求解器遇到共面壳体会整块吞噬网格
    # (隔离实验:216 面 join 后一次切割只剩 108 面,右半套筒直接消失;
    # 单壳体切割则 60 面全数完好)。规则:**布尔只对单一壳体做** ——
    # 体+尾板 join 后切抛壳窗;左右面壁各自单壳体切同窗;防滑拉栓槽弃布尔
    # 改竖向加法凸肋(斜置薄肋的转角会前凸 3.5mm 成怪瘤)。
    slide_parts = [
        add_box("_SlideBody", (sw, sh, sl), (0, sy, sz), bevel=0.0012),
        add_box("_SlideTail", (sw, sh, 0.004), (0, sy, sz + sl * 0.5), bevel=0.0006),
    ]
    slide = join_parts("Slide", slide_parts)
    # 抛壳窗(右侧挖穿):切割器末端面停在套筒中剖面内侧,单壳体布尔,安全。
    # 注意 cut() 默认会删除切割器 —— 体/左面壁/右面壁三次切割各建一个,
    # 复用已删对象会 ReferenceError(StructRNA removed)。
    ep = add_box("_EjectPortCut", (sw * 0.7, sh * 0.52, 0.026),
                 (sw * 0.35, sy + sh * 0.16, sz - sl * 0.24))
    cut(slide, ep)
    n_ser = c.get("serrations", 5)
    ser_len = c.get("serr_len", 0.042)
    _ser_y = sy - sh * 0.06
    _ser_h = sh * 0.42
    _ser_z0 = sz + sl * 0.5 - 0.030            # 槽区后端(靠枪尾)
    extras = []
    for side in (-1.0, 1.0):
        # 削平面壁(上圆下方的流线观感):单独壳体切同窗后再合入
        plate = add_box("_SlideFlat%s" % ("L" if side < 0 else "R"),
                        (0.0018, sh * 0.55, sl * 0.96),
                        (side * (sw * 0.5 + 0.0009), sy - sh * 0.10, sz), bevel=0.0002)
        cut(plate, add_box("_EjectPortCut2", (sw * 0.7, sh * 0.52, 0.026),
                           (sw * 0.35, sy + sh * 0.16, sz - sl * 0.24)))
        extras.append(plate)
        # 竖向防滑拉栓肋:嵌进面壁 0.2mm、凸出外表面 1.6mm,靠明暗对比读槽;
        # 必须与 Slide 同一节点(Slide 是换弹可动件,分立节点不会跟着后拉)
        for i in range(n_ser):
            f = (i + 0.5) / float(n_ser)
            zc = _ser_z0 - ser_len * f
            extras.append(add_box(
                "_SerRib%s%d" % ("L" if side < 0 else "R", i),
                (0.0018, _ser_h, ser_len / n_ser * 0.45),
                (side * (sw * 0.5 + 0.0025), _ser_y, zc),
                bevel=0.0002))
    if c.get("top_rib"):
        extras.append(add_box("_TopRib", (sw * 0.78, 0.006, sl * 0.62),
                              (0, sy + sh * 0.5 + 0.003, sz), bevel=0.0005))
    slide = join_parts("Slide", [slide] + extras)
    # ===== 枪口堆栈 v3(用户实拍"套筒没包住枪管,枪管露出"):旧版衬环缩在滑套
    # 内 20mm 不可见、枪管露 4mm、冠环悬空 5.6mm —— 三段形体不连贯。
    # 按实枪逻辑从后往前钉死:枪管从滑套内连续伸出 → 衬环坐在滑套端面包住
    # 枪管(前伸 12mm)→ 冠环贴枪管尖端,全程零间隙、零露出。
    br = c["barrel_r"]
    _face = sz - sl * 0.5                     # 滑套前端面
    # ===== 枪口零露出方案(多轮实拍仍被读成"枪管露出",彻底内缩) =====
    # 衬环与滑套端面齐平、枪管尖端不越过滑套端面 —— 侧面任何角度只能看到
    # 滑套端面 + 端面上的衬环圈和小膛孔,零凸出。
    _tip = _face + 0.002                      # 枪管尖端:缩进滑套端面内 2mm
    _bz0 = _face + 0.06
    _blen = _bz0 - _tip
    add_cyl("Barrel", br, _blen, (0, ry, (_bz0 + _tip) * 0.5), axis="z", seg=16, bevel=0.0004)
    if c.get("bushing", True):
        # 衬环:与滑套端面齐平。Godot z 越负越靠枪口 —— 中心必须取 +len/2 侧
        # (往射手方向),span = -0.141..-0.123,前缘只露 1mm。
        # 教训(第三次):"+_face+x"是往枪托方向,不是"往里缩"!
        add_cyl("MuzzleBushing", br + 0.0024, 0.018, (0, ry, _face + 0.010),
                axis="z", seg=16, bevel=0.0006)   # span -0.139..-0.121:前缘缩进端面 1mm,零凸出
    add_crown("MuzzleCrown", br, ry, _tip + 0.002)
    add_cyl("MuzzleFace", br * 0.995, 0.004, (0, ry, _tip + 0.001), axis="z", seg=16)
    add_cyl("Bore", br * 0.42, 0.004, (0, ry, _tip + 0.0025), axis="z", seg=12)
    # 抛壳窗内的节套(从窗里看到的是枪机/膛室而不是穿堂空洞)
    add_cyl("ChamberBlock", br * 1.25, 0.024, (0, ry, sz - sl * 0.24 + 0.012), axis="z", seg=16, bevel=0.0004)
    if c.get("compensator"):
        # 制退器套在衬环之外(枪口最前端)
        comp = add_cyl("MuzzleComp", br + 0.008, 0.030, (0, ry, _tip - 0.008), axis="z", seg=16, bevel=0.0005)
        for ct in add_brake_ports("Comp", br + 0.008, ry, _tip - 0.008, n=2, w=sw):
            cut(comp, ct)

    # ---- 下机匣 ----
    add_box("Frame", (fw, fh, fl), (0, fy, fz), bevel=0.0010)
    if c.get("acc_rail"):
        # 防尘盖下三槽配件轨
        rail = add_box("AccRail", (fw * 0.8, 0.006, 0.055), (0, fy - fh * 0.5 - 0.003, fz - fl * 0.30), bevel=0.0004)
        for i in range(3):
            add_box("_AccSlot%d" % i, (fw * 0.5, 0.004, 0.005), (0, fy - fh * 0.5 - 0.005, fz - fl * 0.30 - 0.018 + i * 0.018))
    # 击锤 / 无击锤(subcompact)
    if c.get("hammer", True):
        hammer_block(ry + 0.010, sz + sl * 0.5 + 0.004, 0.012, 0.018, "metal", name="Hammer")
    else:
        # striker 式:套筒尾托弹指示条
        add_box("StrikerPlate", (0.006, 0.004, 0.010), (0, sy + sh * 0.5 + 0.002, sz + sl * 0.5 - 0.004), bevel=0.0002)
    # 鱼腮状 beavertail / 握把保险
    add_box("Beavertail", (0.014, 0.026, 0.008), (0, sy - sh - 0.008, sz + sl * 0.5 + 0.012), bevel=0.0006)

    # ---- 握把(倾斜) + 前后撑板滚花 + 两侧握把片 ----
    gw = c.get("grip_w", fw - 0.002); gh = c.get("grip_h", 0.092); gd = c.get("grip_d", 0.046)
    gt = c.get("grip_tilt", 0.32)
    gy = fy - fh * 0.42; gz = fz + fl * 0.28
    add_grip("Grip", gw, gh, gd, (0, gy, gz), tilt=gt)
    # 前撑板滚花(实枪 M1911/G17 前倾面)
    fk = add_knurl("FrontStrapKnurl", gw * 0.55, gz - gd * 0.42, gy - gh * 0.06, h=gh * 0.5, n=6, depth=0.0016)
    for ob in ([fk] if not isinstance(fk, list) else fk):
        ob.rotation_euler.x = -gt   # 与修正后的握把倾角一致(负角=后倾)
    fkj = join_parts("FrontStrap", [fk] if not isinstance(fk, list) else fk)
    # 两侧握把片(木/菱纹) —— 比握把体略凸
    if grip == "panels":
        for side in (-1.0, 1.0):
            add_box("GripPanelL" if side < 0 else "GripPanelR", (0.004, gh * 0.72, gd * 0.82),
                    (side * (gw * 0.5 + 0.002), gy - gh * 0.42, gz), bevel=0.0006, rot_g=(-gt, 0, 0))

    # ---- 扳机/护圈/操作杆 ----
    for t in _pistol_trigger(fy - fh * 0.30, fz + fl * 0.10):
        pass
    for lv in _pistol_levers(fy + fh * 0.10, fz + fl * 0.30, fw):
        pass
    # 空挂释放杆抬起的窗口观感(套筒下沿缺口) —— 挖套筒底部小口
    # (M1911 滑轨停杆在空挂时可见,这里给静态造型即可)

    # ---- 弹匣 ----
    # 弹匣沿握把轴线插入(tilt=握把倾角):竖直弹匣 + 后倾握把 = 匣底从握把后下方
    # 戳出去一截(实机截图实锤)。匣长 = 握把长 × 0.95,底板与握把底齐平。
    # 弹匣与握把轴平行:add_mag_straight 内部符号是"正角=向前倾"(AK/AR 弹匣用),
    # 手枪弹匣必须随握把后倾 → 传 -gt(旧版 +gt 与握把反向交叉,实拍实锤)
    add_mag_straight("mag", c.get("mag_w", fw - 0.008), c.get("mag_h", gh * 0.95), c.get("mag_d", gd - 0.008),
                     (0, gy + 0.004, gz), tilt=-gt, mat="metal", holes=c.get("mag_holes", 2))

    # ---- 瞄具(前柱+后缺口,中间绝对通透) ----
    fh_post = c.get("front_h", 0.018); rh = c.get("rear_h", 0.020)
    parts = [
        # 前准星必须坐在套筒顶面上(旧版 z 超出套筒前端 12mm 浮空,数值探针实锤)
        add_box("SightsFront", (0.006, fh_post, 0.008), (0, sight_y - fh_post * 0.5, sz - sl * 0.5 + 0.014), bevel=0.0003),
        # 前准星白点(氚管观感)
        add_box("SightsFrontDot", (0.0025, 0.0025, 0.001), (0, sight_y - 0.004, sz - sl * 0.5 + 0.014), bevel=0.0001),
        add_box("SightsRearL", (0.0035, rh, 0.014), (-(sw * 0.28), sight_y - rh * 0.5, sz + sl * 0.5 - 0.010), bevel=0.0003),
        add_box("SightsRearR", (0.0035, rh, 0.014), (sw * 0.28, sight_y - rh * 0.5, sz + sl * 0.5 - 0.010), bevel=0.0003),
    ]
    joined = join_parts("StockIrons", parts)

    # ---- 套筒顶 RMR 底板(微型红点安装位):抛壳窗与照门之间的平面区 ----
    _slide_top = sy + sh * 0.5
    add_picatinny("SlideRail", 0.048, (0, _slide_top + 0.0074, sz + sl * 0.16), width=0.016, mount_h=0.002)

    # ---- 材质 ----
    mat_rules = [
        ("Slide", slide_mat), ("Hammer", "metal"), ("StockIrons", "dark"),
        ("Frame", frame_mat), ("AccRail", frame_mat), ("Grip", grip_mat),
        ("FrontStrap", grip_mat), ("mag", "metal"), ("Barrel", "metal"),
        ("MuzzleCrown", "dark"), ("MuzzleBushing", "dark"), ("MuzzleComp", "dark"),
        ("Bore", "dark"), ("MuzzleFace", "metal"), ("ChamberBlock", "metal"),
        ("TriggerGuard", frame_mat), ("Trigger", "metal"),
        ("SlideStopLever", "metal"), ("TakedownLever", "metal"), ("MagRelease", "metal"),
        ("Beavertail", frame_mat), ("StrikerPlate", "dark"), ("SlideRail", slide_mat),
    ]
    if grip == "panels":
        mat_rules.append(("GripPanel", grip_mat))
    apply_materials(mat_rules, default="dark")


SPEC = {
    "m1911": dict(
        slide_w=0.034, slide_h=0.050, slide_len=0.200, slide_y=0.032, slide_z=-0.040,
        frame_w=0.033, frame_h=0.040, frame_len=0.190, frame_y=-0.003, frame_z=-0.030,
        barrel_y=0.033, barrel_r=0.009, barrel_len=0.070, sight_y=0.073,
        grip="panels", grip_mat="wood", frame_mat="dark", slide_mat="metal",
        bushing=True, serrations=5, top_rib=False, grip_tilt=0.34, front_h=0.018, rear_h=0.020,
    ),
    "g17": dict(
        slide_w=0.034, slide_h=0.044, slide_len=0.200, slide_y=0.030, slide_z=-0.040,
        frame_w=0.033, frame_h=0.032, frame_len=0.180, frame_y=-0.003, frame_z=-0.030,
        barrel_y=0.031, barrel_r=0.008, barrel_len=0.060, sight_y=0.0685,
        grip="plain", grip_mat="poly", frame_mat="poly", slide_mat="dark",
        hammer=False, acc_rail=True, serrations=5, grip_tilt=0.32, front_h=0.016, rear_h=0.018,
    ),
    "p226": dict(
        slide_w=0.035, slide_h=0.047, slide_len=0.200, slide_y=0.032, slide_z=-0.040,
        frame_w=0.034, frame_h=0.038, frame_len=0.180, frame_y=-0.003, frame_z=-0.030,
        barrel_y=0.034, barrel_r=0.009, barrel_len=0.070, sight_y=0.0735,
        grip="panels", grip_mat="poly", frame_mat="tan", slide_mat="dark",
        bushing=False, serrations=4, grip_tilt=0.32, front_h=0.018, rear_h=0.020,
    ),
    "deagle": dict(
        # slide_h 0.058→0.050:套筒顶+顶肋距 sight_y(0.0825) 仅 5.5mm,擦到 6mm 采样半径
        slide_w=0.044, slide_h=0.050, slide_len=0.250, slide_y=0.036, slide_z=-0.060,
        frame_w=0.042, frame_h=0.044, frame_len=0.200, frame_y=-0.004, frame_z=-0.030,
        barrel_y=0.036, barrel_r=0.011, barrel_len=0.090, sight_y=0.0825,
        grip="panels", grip_mat="wood", frame_mat="dark", slide_mat="chrome",
        top_rib=True, compensator=True, serrations=6, grip_tilt=0.30, front_h=0.020, rear_h=0.022,
    ),
    "m93r": dict(
        slide_w=0.034, slide_h=0.045, slide_len=0.220, slide_y=0.030, slide_z=-0.050,
        frame_w=0.033, frame_h=0.038, frame_len=0.190, frame_y=-0.003, frame_z=-0.030,
        barrel_y=0.031, barrel_r=0.008, barrel_len=0.080, sight_y=0.070,
        grip="plain", grip_mat="poly", frame_mat="metal", slide_mat="dark",
        serrations=5, grip_tilt=0.32, front_h=0.016, rear_h=0.018, mag_h=0.14,
    ),
}


def build_pistol_spec(wid):
    c = SPEC[wid]
    build_semi_auto(c)
    if wid == "m93r":
        # 前折握把 + 长管配重(M93R 标志)
        fg = add_box("ForeGrip", (0.024, 0.06, 0.03), (0, -0.045, -0.14), bevel=0.0008)
        fg.rotation_euler.x = 0.2
        add_box("MuzzleWeight", (0.019, 0.02, 0.04), (0, 0.031, -0.245), bevel=0.0005)
        add_box("SelectorL", (0.008, 0.02, 0.03), (-0.022, 0.03, 0.02), bevel=0.0004)
        apply_materials([("ForeGrip", "poly"), ("MuzzleWeight", "dark"), ("SelectorL", "dark")], default="dark")
    if wid == "g17":
        # G17 的 poly 握把片 = 模压纹理,不加木片
        pass


def build_m1911():
    build_pistol_spec("m1911")


def build_g17():
    build_pistol_spec("g17")


def build_p226():
    build_pistol_spec("p226")


def build_deagle():
    build_pistol_spec("deagle")


def build_m93r():
    build_pistol_spec("m93r")


# ============================================================ 左轮 3 把

def revolver_fluted_cylinder(cyl_r, cyl_len, cap, fluted=True, origin_bl=None):
    """弹巢:带退壳槽(或无槽束带)。命名 RevolverCylinder,parent 到 crane。
    origin_bl: 弹巢世界位置(Blender 坐标)。逐膛弹壳按此位置生成 ——
    旧版壳建在世界原点,parent_to 保持世界位置后全部留在握把区(实锤)。"""
    parts = [add_cyl("_CylBody", cyl_r, cyl_len, (0, 0, 0), axis="z", seg=24, bevel=0.0008)]
    for i in range(cap):
        ang = float(i) * math.tau / float(cap)
        if fluted:
            f = add_box("_Flute%d" % i, (0.007, cyl_len * 0.72, cyl_len), (0, 0, 0), bevel=0.0004)
            f.rotation_euler.z = ang
            # 退壳槽贴柱面:沿旋转方向推到半径处 —— 用局部 y 平移近似
            f.location = (f.location.x, f.location.y + cyl_r * 0.86, f.location.z)
        else:
            b = add_box("_Band%d" % i, (0.046, cyl_len * 0.22, cyl_len), (0, 0, 0), bevel=0.0005)
            b.rotation_euler.z = ang
    joined = join_parts("RevolverCylinder", parts)
    # 逐膛弹壳必须是独立命名节点(Godot 按膛位显隐) —— 绝不能 join 进弹巢,
    # join 会吞掉名字,膛位状态就没了。
    ob = origin_bl if origin_bl is not None else (0.0, 0.0, 0.0)
    shells = []
    for i in range(cap):
        ang = float(i) * math.tau / float(cap)
        sh = add_cyl("ChamberShell_%d" % i, 0.0045, 0.014,
                     (ob[0] + math.sin(ang) * (cyl_r - 0.007),
                      ob[1] + math.cos(ang) * (cyl_r - 0.007),
                      ob[2] + cyl_len * 0.5 - 0.001), axis="z", seg=8)
        shells.append(sh)
    return joined, shells


def build_revolver(c):
    reset()
    cap = c["chambers"]
    barrel_len = c["barrel_len"]
    frame_mat = c["frame_mat"]
    grip_mat = c["grip_mat"]
    barrel_y = c["barrel_y"]
    sight_y = c["sight_y"]
    heavy = c.get("heavy", False)
    style = c.get("style", "")
    fluted = c.get("fluted", True)

    frame_w = 0.044 if heavy else (0.041 if style == "python" else 0.037)
    frame_h = 0.056 if heavy else (0.052 if style == "python" else 0.048)
    frame_y = 0.024 if heavy else (0.023 if style == "python" else 0.021)
    front_w = frame_w - 0.002
    front_h = frame_h - 0.012
    cyl_r = 0.025 if heavy else (0.023 if style == "python" else 0.021)
    cyl_len = 0.058 if heavy else (0.055 if style == "python" else 0.052)

    # ===== 一体化框架(用户实拍:旧版各块之间 35mm 空隙、顶条浮空 13mm、全部分离) =====
    # 布局(枪口朝 -z):后机匣 -0.06..0.04 | 弹巢窗口 -0.124..-0.06 | 前枪管座 -0.19..-0.124
    # 三块在顶部由连续顶条(TopStrap)焊成一体,弹巢嵌在窗口中。
    frame_top = frame_y + frame_h * 0.5
    frame = join_parts("Frame", [
        add_box("_FrameRear", (frame_w, frame_h, 0.10), (0, frame_y, -0.01), bevel=0.0012),
        # 前枪管座:上缘压到弹巢中心线下方(弹巢上半露出窗口,实枪形态)
        add_box("_FrameFront", (front_w, front_h, 0.070), (0, frame_y - 0.004, -0.159), bevel=0.0010),
        # 底框(握把前方连接条,托住弹巢下缘)
        add_box("_FrameBottom", (frame_w - 0.008, 0.014, 0.19), (0, frame_y - frame_h * 0.5 + 0.004, -0.075), bevel=0.0008),
    ])
    # 顶条:厚 12mm,中心贴机匣顶(重叠 5mm 焊死),z 全程横跨三块
    top_strap_y = frame_top + 0.001
    add_box("TopStrap", (frame_w - 0.006, 0.012, 0.235), (0, top_strap_y, -0.075), bevel=0.0008)

    # 枪管
    barrel_len_total = barrel_len + 0.13
    barrel_center_z = -0.155 - barrel_len_total * 0.5
    front_z = -0.155 - barrel_len_total + 0.02
    barrel_r = 0.014 if heavy else (0.0115 if style == "python" else 0.0105)
    add_cyl("Barrel", barrel_r, barrel_len_total, (0, barrel_y, barrel_center_z),
            axis="z", seg=18, bevel=0.0006, taper=0.96)
    add_cyl("MuzzleRing", barrel_r + 0.004, 0.03, (0, barrel_y, -0.155 - barrel_len_total),
            axis="z", seg=16, bevel=0.0005)
    if c.get("vent_rib"):
        rib_z1 = front_z - 0.01
        add_box("VentRib", (0.016, 0.007, absf(-0.17 - rib_z1)),
                (0, barrel_y + barrel_r + 0.006, (-0.17 + rib_z1) * 0.5), bevel=0.0005)
        for i in range(5):
            add_box("_RibPost%d" % i, (0.006, 0.004, 0.022),
                    (0, barrel_y + barrel_r + 0.013, -0.2 - float(i) * 0.055), bevel=0.0003)
    if c.get("underlug"):
        lug_z0 = -0.19
        lug_z1 = front_z + 0.03
        if lug_z0 > lug_z1:
            add_cyl("Underlug", 0.0085, absf(lug_z1 - lug_z0),
                    (0, barrel_y - barrel_r - 0.008, (lug_z0 + lug_z1) * 0.5),
                    axis="z", seg=12, bevel=0.0005)
    # 退壳杆:贴枪管下表面(旧版悬在下方 17mm 空中)
    add_cyl("EjectorRod", 0.0045, barrel_len_total * 0.55,
            (0, barrel_y - barrel_r - 0.001, -0.2 - barrel_len_total * 0.27), axis="z", seg=10)
    if c.get("top_rail"):
        add_box("TopRail", (0.024, 0.008, absf(-0.16 - front_z)),
                (0, barrel_y + barrel_r + 0.01, (-0.16 + front_z) * 0.5), bevel=0.0005)
    if c.get("compensator"):
        add_cyl("Compensator", 0.018, 0.042, (0, barrel_y, front_z - 0.01), axis="z", seg=16, bevel=0.0006)
        for side in (-1.0, 1.0):
            add_box("_CompPort%d" % (1 if side > 0 else 0), (0.02, 0.012, 0.012),
                    (side * 0.018, barrel_y + 0.012, front_z - 0.012), bevel=0.0004)

    # 弹巢摆出铰链(空对象) → 弹巢 → 逐膛弹壳
    crane = add_empty("RevolverCrane", (0.005, barrel_y - 0.017, -0.152))
    # 弹巢最终世界位置 = crane 位置 + GDScript 本地偏移 (0,0.014,0.072)。
    # join 后先摆到世界位置,再 parent_to(保持世界位置公式)。
    # Blender world -> Godot: (x, z, -y)
    # GDScript 本地偏移 (0, 0.014, 0.072) 转 Blender:(x, -z_g, y_g) = (0, -0.072, 0.014)。
    # 旧版写成 +0.072 —— Blender y 是 Godot -z,弹巢被推到枪管下方悬空(实拍实锤)。
    cyl_obj, shell_objs = revolver_fluted_cylinder(cyl_r, cyl_len, cap, fluted)
    cw = crane.matrix_world.translation
    bpy.context.view_layer.update()
    cyl_obj.location = (cw.x, cw.y - 0.072, cw.z + 0.014)
    bpy.context.view_layer.update()
    parent_to(cyl_obj, crane)
    # 壳按弹巢最终世界位置生成(旧版建在世界原点,parent 后留在握把区)
    for sh in shell_objs:
        sh.location = (sh.location.x + cyl_obj.location.x,
                       sh.location.y + cyl_obj.location.y,
                       sh.location.z + cyl_obj.location.z)
        parent_to(sh, cyl_obj)

    # 击锤:贴机匣后上角(spur 在机匣后端面后方一点点,旧版悬空 5mm)
    hammer_w = 0.014 if style == "python" else (0.012 if not heavy else 0.017)
    hammer_h = 0.026 if style == "python" else (0.022 if not heavy else 0.03)
    # 击锤贴机匣后端面(z=0.042 与机匣重叠 2mm;旧 z=0.052 悬空 6mm,三视图实锤)
    hammer_block(frame_top - 0.006, 0.042, hammer_w, hammer_h, frame_mat)

    # 握把(按款式)
    # 握把:后倾 0.42rad(~74°,实枪左轮握把角),落在机匣后下角
    add_grip("Grip", 0.032 if not heavy else 0.038, 0.092, 0.044, (0, -0.012, 0.042),
             tilt=0.42, mat=grip_mat)
    # 护圈三段 U 形:立柱上到机匣底(单条悬空横杆已实锤)
    add_box("TriggerGuard", (0.024, 0.007, 0.068), (0, -0.046, 0.012), bevel=0.0004)
    add_box("_GuardPostF", (0.018, 0.026, 0.007), (0, -0.034, -0.020), bevel=0.0004)
    add_box("_GuardPostB", (0.018, 0.026, 0.007), (0, -0.034, 0.043), bevel=0.0004)
    # 照门缺口 + 前准星(带基座落地:顶条顶/枪管面 → 视轴,旧版双耳浮空 35mm)
    strap_top = top_strap_y + 0.006
    barrel_top = barrel_y + barrel_r
    rh = 0.016
    irons = [
        # 后照门:基座从顶条顶面起到耳底
        add_box("SightsRearBase", (0.022, sight_y - rh - strap_top, 0.016),
                (0, strap_top + (sight_y - rh - strap_top) * 0.5, -0.060), bevel=0.0004),
        add_box("SightsRearL", (0.0035, rh, 0.014), (-0.0095, sight_y - rh * 0.5, -0.060), bevel=0.0003),
        add_box("SightsRearR", (0.0035, rh, 0.014), (0.0095, sight_y - rh * 0.5, -0.060), bevel=0.0003),
        # 前准星:基座在枪管面上,柱到视轴
        add_box("SightsFrontBase", (0.008, 0.010, 0.016), (0, barrel_top + 0.005, front_z + 0.02), bevel=0.0003),
        add_box("SightsFront", (0.005, sight_y - barrel_top - 0.010, 0.007),
                (0, barrel_top + 0.010 + (sight_y - barrel_top - 0.010) * 0.5, front_z + 0.02), bevel=0.0003),
    ]
    join_parts("StockIrons", irons)

    mats = [
        ("RevolverCylinder", frame_mat), ("_CylBody", frame_mat), ("_CylCore", frame_mat),
        ("_Flute", "dark"), ("_Band", "dark"), ("_ChamberShell", "brass"),
        ("Hammer", frame_mat), ("StockIrons", "dark"), ("EjectorRod", "dark"),
        ("TopRail", "dark"), ("Compensator", "dark"), ("_CompPort", "dark"),
        ("VentRib", frame_mat), ("_RibPost", "dark"), ("MuzzleRing", "dark"),
        ("Underlug", frame_mat), ("Frame", frame_mat), ("FrontStrap", frame_mat),
        ("TopStrap", frame_mat), ("Barrel", frame_mat), ("Grip", grip_mat),
        ("TriggerGuard", frame_mat),
    ]
    apply_materials(mats, default=frame_mat)


def build_python():
    build_revolver({
        "chambers": 6, "barrel_len": 0.152, "frame_mat": "chrome", "grip_mat": "wood",
        "barrel_y": 0.033, "sight_y": 0.093, "style": "python",
        "vent_rib": True, "underlug": True, "fluted": True,
    })


def build_sw686():
    build_revolver({
        "chambers": 6, "barrel_len": 0.102, "frame_mat": "metal", "grip_mat": "poly",
        "barrel_y": 0.032, "sight_y": 0.091, "style": "686",
        "underlug": True, "fluted": True,
    })


def build_sw500():
    build_revolver({
        "chambers": 5, "barrel_len": 0.213, "frame_mat": "dark", "grip_mat": "poly",
        "barrel_y": 0.034, "sight_y": 0.096, "heavy": True, "style": "500",
        "top_rail": True, "compensator": True, "fluted": False,
    })


BUILDERS = {
    "m1911": build_m1911,
    "g17": build_g17,
    "p226": build_p226,
    "deagle": build_deagle,
    "m93r": build_m93r,
    "python": build_python,
    "sw686": build_sw686,
    "sw500": build_sw500,
}

REVOLVERS = {"python", "sw686", "sw500"}


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
        if wid in REVOLVERS:
            need = ["RevolverCrane", "RevolverCylinder", "RevolverHammer", "StockIrons"]
            cap = 6 if wid != "sw500" else 5
            need += ["ChamberShell_%d" % i for i in range(cap)]
        else:
            need = ["Slide", "mag", "StockIrons"]
        ok = all(k in names for k in need)
        print("%-7s objs=%-4d verts=%-6d tris=%-6d  契约=%s  %.0f KB" % (
            wid, objs, verts, tris, "OK" if ok else "MISSING!",
            os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
