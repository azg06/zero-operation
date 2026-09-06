"""
轻机枪批次建模(8 把):M249 / PKM / RPD / MG42 / M60 / Mk48 / Negev / MG3

尺寸沿用 weapon_models.gd 程序化定义,锚点零改动。

机枪换弹契约(Godot 侧按名字找,一个都不能少):
    mag        弹链箱 / 弹鼓(换弹时整体拆装)
    BeltTail   mag 的子对象,弹链尾随箱走
    FeedCover  受弹机盖(换弹绕根部铰链前掀),CoverLatch 为其子件(手抓握点)
    FeedPort   空对象,受弹口参考点
    bolt       拉机柄

用法:
    blender --background --python build_lmg_batch.py
    blender --background --python build_lmg_batch.py -- m249 pkm
"""

import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gunforge import *

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"


# ---------------------------------------------------------------- 机枪通用组件

def _set_origin_cursor(ob, pos_g):
    """把对象原点搬到 Godot 语义坐标 pos_g 处(网格世界位置不变)。
    换弹动画绕节点原点旋转 —— 铰链件(受弹机盖)的原点必须在铰链轴上,
    留在盖体中心的话,开盖 = 整块盖子绕自身中心翻转,前后缘双双砸进机匣。"""
    import mathutils
    bpy.context.scene.cursor.location = mathutils.Vector(g2b(pos_g))
    bpy.ops.object.select_all(action='DESELECT')  # gunforge 的 _deselect_all 不随 * 导出
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return ob


def feed_cover(y, z_center, length, w=0.052, mat="dark"):
    """受弹机盖:铰链根在盖体后缘(绕 +X 前掀),盖体/加强筋 join 为 FeedCover,
    CoverLatch 独立命名并 parent 到盖 —— 换弹手抓它,盖开它随动。
    盖内侧带供弹机械结构:横向送弹滚轴 + 压弹凸缘(开盖时玩家看到的机械,不是平板)。
    join 后原点必须在后缘铰链轴上(见 _set_origin_cursor)。"""
    inner = y - 0.009          # 盖内侧(下面)面
    cover_body = add_box("CoverBody", (w, 0.018, length), (0, y, z_center), bevel=0.0008)
    rib = add_box("CoverRib", (w - 0.012, 0.007, length - 0.06),
                  (0, y + 0.0105, z_center), bevel=0.0005)
    cover = join_parts("FeedCover", [cover_body, rib])
    # 盖内侧供弹机构(独立子件,开盖朝上可见):送弹滚轴 + 两条压弹凸缘 + 抓弹爪座
    roller = add_cyl("CoverRoller", 0.008, w * 0.62, (0, inner - 0.008, z_center + length * 0.18),
                     axis="x", seg=14, bevel=0.0004)
    parent_to(roller, cover)
    for s in (-1.0, 1.0):
        fl = add_box("CoverPressureFlange%s" % ("L" if s < 0 else "R"),
                     (w * 0.30, 0.008, length * 0.42),
                     (s * w * 0.30, inner - 0.004, z_center - length * 0.10), bevel=0.0004)
        parent_to(fl, cover)
    pawl = add_box("CoverPawlBlock", (w * 0.34, 0.010, 0.030),
                   (0, inner - 0.005, z_center - length * 0.30), bevel=0.0004)
    parent_to(pawl, cover)
    _set_origin_cursor(cover, (0, y, z_center + length * 0.5))
    latch = add_box("CoverLatch", (0.016, 0.016, 0.036),
                    (0, y + 0.017, z_center - length * 0.16), bevel=0.0005)
    parent_to(latch, cover)
    return cover


def feed_tray(y, z_center, length, w=0.050, mat="dark"):
    """受弹托盘:开盖后机匣顶面露出的凹形供弹槽 —— 底板 + 两侧壁 + 分隔齿 +
    三根竖直导柱(参考 M249 实枪照片)。开盖后玩家看到的就是它,不是导轨。"""
    parts = [
        # 凹槽底板(下凹,弹链贴着它滑)
        add_box("TrayBase", (w, 0.006, length),
                (0, y - 0.003, z_center), bevel=0.0005),
    ]
    # 两侧壁(挡住弹链不左右偏)
    for s in (-1.0, 1.0):
        parts.append(add_box("TrayWall%s" % ("L" if s < 0 else "R"),
                             (0.005, 0.020, length),
                             (s * (w * 0.5 + 0.0025), y + 0.007, z_center), bevel=0.0004))
    # 分隔齿:托盘中央一排横向短齿,卡住弹链节距(实枪 feed tray 的分隔凸排)
    n = max(4, int(length / 0.05))
    for i in range(n):
        parts.append(add_box("TrayDivider%d" % i, (w * 0.42, 0.008, 0.008),
                             (0, y + 0.004, z_center - length * 0.5 + (i + 0.5) * length / n),
                             bevel=0.0003))
    # 三根竖直导柱(实枪 feed tray 上的定位柱)
    for i, dz in enumerate((-0.30, 0.02, 0.32)):
        parts.append(add_cyl("TrayPost%d" % i, 0.005, 0.024,
                             (0, y + 0.010, z_center + length * dz), axis="y", seg=10))
    return join_parts("FeedTray", parts)


def belt_feed(side, box_pos, box_size, port_pos, mat="olive", feed_tray_y=None, feed_tray_len=0.30):
    """侧挂弹链箱(mag) + 弹链尾(BeltTail,parent 到箱) + 受弹口空点(FeedPort)。

    v3(实拍修正"弹箱偏上偏前、弹链隐形"):
    - 弹箱由调用方低挂:箱顶只到机匣半高,箱体大部分垂在机匣下沿以下
      (实枪 200 发弹箱形态),内侧面贴死供弹侧机匣面、不再前伸悬空。
    - 弹链:8 节链节从箱顶沿外凸弧线爬进受弹口 —— 控制点往箱外侧偏,
      链节走线在机匣外可见,绝不埋进箱体/机匣;链节用黄铜色(材质表 _bt)。"""
    bx, by, bz = box_pos
    sx, sy, sz = box_size
    parts = [add_box("AmmoBox", box_size, box_pos, bevel=0.0010)]
    # 提手贴箱体外侧(挂左= -x):曾写成 "-side*x" 镜到机匣另一侧埋进枪身
    parts.append(add_box("_box_handle", (0.024, 0.010, 0.05),
                         (side * sx * 0.28, by + sy * 0.5 - 0.002, bz - sz * 0.18),
                         bevel=0.0005))
    mag = join_parts("mag", parts)
    # 弹链:从箱顶竖直爬进正上方的受弹口(实拍修正"弹链斜着":弹箱已对齐
    # 受弹口正下方,链路近竖直,仅上端微向外弯进受弹口)。5 节×34mm,
    # 路径 ~65mm,相邻链节重叠一半,链肉体感。
    a = (bx - side * (sx * 0.5 - 0.030), by + sy * 0.5 - 0.008, port_pos[2])
    c = port_pos
    b = ((a[0] + c[0]) * 0.5 + side * 0.012, (a[1] + c[1]) * 0.5 + 0.006, port_pos[2])
    tail_parts = []
    n_link = 6
    for i in range(n_link):
        t = float(i) / float(n_link - 1)
        ab = lerp3(a, b, t)
        bc = lerp3(b, c, t)
        p = lerp3(ab, bc, t)
        tail_parts.append(add_box("_bt%d" % i, (0.018, 0.034, 0.026), p, bevel=0.0004))
    tail = join_parts("BeltTail", tail_parts)
    parent_to(tail, mag)
    add_empty("FeedPort", port_pos)
    if feed_tray_y is not None:
        feed_tray(feed_tray_y, port_pos[2] + feed_tray_len * 0.30, feed_tray_len)
    return mag


def bolt_handle(x, y, z, side=1.0):
    ch = add_box("ChargingHandle", (0.013, 0.015, 0.028), (x + side * 0.021, y, z), bevel=0.0005)
    rod = add_cyl("_ch_rod", 0.006, 0.022, (x + side * 0.008, y, z), axis="x", seg=10, bevel=0.0004)
    join_parts("bolt", [ch, rod])


def bipod(z, y=-0.07, spread=0.03, h=0.14):
    for s in (-1.0, 1.0):
        add_box("BipodLeg%s" % ("L" if s < 0 else "R"), (0.008, h, 0.008),
                (s * spread, -y * 0.5 - 0.005, z), bevel=0.0005)


def charging_handle_tube(y, z, length=0.2, r=0.012):
    return add_cyl("ChargingTube", r, length, (0, y, z), axis="z", seg=14, bevel=0.0006)


def _fold_stock(hinge_z, top_y=0.045, bot_y=-0.012, arm_len=0.14, plate_z=None):
    """侧折叠骨架托:铰链 + 上下杆 + 托底板。"""
    pz = plate_z if plate_z is not None else hinge_z + 0.12
    return [
        add_box("StockHinge", (0.028, 0.050, 0.040), (0, 0.005, hinge_z), bevel=0.0010),
        add_box("StockArmTop", (0.022, 0.020, arm_len), (0, top_y, hinge_z + 0.06), bevel=0.0008),
        add_box("StockArmBot", (0.022, 0.020, arm_len), (0, bot_y, hinge_z + 0.06), bevel=0.0008),
        add_box("StockPlate", (0.040, 0.075, 0.024), (0, 0.008, pz), bevel=0.0010),
    ]


def lmg_top_rail(recv_top, z0, z1, w=0.026, mount=0.0):
    """机匣固定顶轨(不随受弹盖掀)。所有机枪都必须有:optic 改装件的落点,
    也是"机枪观感"的一半。mount 按机匣顶到齿底的落差填实。"""
    return add_picatinny("FrameRail", absf(z1 - z0),
                         (0, recv_top + RAIL_THICK + mount, (z0 + z1) * 0.5),
                         width=w, mount_h=max(mount, 0.0))


def lmg_detail_pack(side, ry, port, recv_top, recv_z, recv_len, recv_w):
    """机枪细节包:抛壳口/排链槽/受弹机构/连接销/枪管锁扣/背带环/机匣侧肋。
    side=供弹方向(-1 左挂 / +1 右挂),抛壳口开在异侧。"""
    ex = -side
    return [
        # 抛壳口:供弹异侧机匣面
        add_box("EjectionPort", (0.006, 0.022, 0.060),
                (ex * (recv_w * 0.5 + 0.003), ry + 0.010, recv_z + recv_len * 0.12), bevel=0.0005),
        # 排链槽:受弹口下方向后的斜滑板,链节从这里被拨进膛
        add_box("BeltGuide", (0.030, 0.006, 0.090),
                (side * 0.012, ry - 0.022, port[2] + 0.050), bevel=0.0004),
        # 受弹机构块(port 正下方的机匣内凸)
        add_box("FeedMech", (0.036, 0.024, 0.050),
                (side * 0.010, ry - 0.020, port[2]), bevel=0.0006),
        # 机匣前后连接销
        add_cyl("TakedownPinF", 0.0045, recv_w + 0.014,
                (0, ry - 0.030, recv_z + recv_len * 0.26), axis="x", seg=10),
        add_cyl("TakedownPinR", 0.0045, recv_w + 0.014,
                (0, ry - 0.030, recv_z - recv_len * 0.26), axis="x", seg=10),
        # 枪管装卸锁扣(护木根部)
        add_box("BarrelLatch", (0.018, 0.014, 0.040),
                (0, ry + 0.030, port[2] + 0.110), bevel=0.0005),
        # 背带环(机匣尾底)
        add_box("SlingLoop", (0.010, 0.014, 0.030),
                (0, -0.030, recv_z - recv_len * 0.40), bevel=0.0005),
    ]


def _lmg_ribs(side, ry, recv_z, recv_len, recv_w):
    out = []
    for s in (-1.0, 1.0):
        out.append(add_box("ReceiverRib%s" % ("L" if s < 0 else "R"),
                           (0.004, 0.036, recv_len * 0.55),
                           (s * (recv_w * 0.5 + 0.002), ry - 0.008, recv_z), bevel=0.0004))
    return out


# ============================================================ M249
def build_m249():
    reset()
    ry = 0.028
    add_box("Receiver", (0.062, 0.100, 0.460), (0, 0.020, -0.080), bevel=0.0016)
    cover = feed_cover(0.085, -0.100, 0.460)
    # 盖顶不放导轨(用户反馈:开盖应看到供弹机械)。M249 实枪盖顶是平的;
    # 光学镜座在机匣固定轨(FrameRail)上。
    # 弹箱低挂(实拍修正:旧版箱体悬在机匣前上方半空):箱顶到机匣半高,
    # 箱体大半垂在机匣下沿以下,内侧面贴死左机匣面
    belt_feed(-1.0, (-0.068, -0.095, -0.165), (0.075, 0.110, 0.140),
              (-0.026, 0.062, -0.160), "olive", feed_tray_y=0.062, feed_tray_len=0.28)
    # 圆护木 + 上护手板 + 枪管提把 + 枪管 + 消焰器
    add_cyl("Handguard", 0.028, 0.260, (0, ry, -0.420), axis="z", seg=20, bevel=0.0010)
    add_box("HandguardTop", (0.050, 0.012, 0.160), (0, ry + 0.032, -0.420), bevel=0.0008)
    add_box("CarryHandle", (0.016, 0.040, 0.050), (0, ry + 0.038, -0.520), bevel=0.0008)
    add_cyl("Barrel", 0.0140, 0.400, (0, ry, -0.680), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0200, 0.060, (0, ry, -0.875), axis="z", seg=16, bevel=0.0006)
    bipod(-0.500, y=0.075)
    # 机匣固定顶轨(不随盖掀):optic 落点 + 机枪观感
    lmg_top_rail(0.070, -0.300, 0.120)
    lmg_detail_pack(-1.0, 0.028, (-0.026, -0.015, -0.160), 0.070, -0.080, 0.460, 0.062)
    _lmg_ribs(-1.0, 0.028, -0.080, 0.460, 0.062)
    # 聚合物托 + 液压缓冲 + 握把(直托:贴机匣顶、托尾微垂)
    add_stock("StockBody", 0.048, 0.095, 0.160, 0.150, 0.070, drop=0.10)
    add_cyl("HydroBuffer", 0.016, 0.040, (0, 0.008, 0.140), axis="z", seg=14, bevel=0.0006)
    add_grip("Grip", 0.038, 0.110, 0.050, (0, -0.030, 0.050), tilt=0.35, ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.040, 0.020), bevel=0.0005)
    add_trigger_guard(-0.048, 0.005, 0.062)
    bolt_handle(0.035, 0.030, 0.020)
    add_irons("StockIrons", 0.125, -0.600, 0.100, 0.055, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "metal"), ("Cover", "dark"), ("CoverRail", "dark"),
        ("Handguard", "dark"), ("CarryHandle", "dark"), ("Barrel", "dark"),
        ("FlashHider", "dark"), ("Stock", "poly"), ("Grip", "poly"),
        ("Trigger", "dark"), ("HydroBuffer", "dark"), ("bolt", "dark"),
        ("mag", "olive"), ("AmmoBox", "olive"), ("BeltTail", "dark"), ("_bt", "brass"),
        ("Bipod", "dark"),
    ], default="dark")


# ============================================================ PKM
def build_pkm():
    reset()
    ry = 0.028
    add_box("Receiver", (0.062, 0.100, 0.460), (0, 0.020, -0.060), bevel=0.0016)
    feed_cover(0.082, -0.080, 0.480)
    # PKM 特征:右供弹。弹箱低挂贴右机匣面(同 M249 修正)
    belt_feed(1.0, (0.068, -0.095, -0.155), (0.075, 0.110, 0.140),
              (0.026, 0.062, -0.150), "dark", feed_tray_y=0.062, feed_tray_len=0.28)
    # 木护木筒 + 上护手板 + 枪管 + 锥形消焰器 + 左提把
    add_cyl("Handguard", 0.028, 0.280, (0, ry, -0.420), axis="z", seg=20, bevel=0.0010)
    add_box("HandguardTop", (0.046, 0.012, 0.180), (0, ry + 0.032, -0.420), bevel=0.0008)
    add_cyl("Barrel", 0.0150, 0.420, (0, ry, -0.700), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0200, 0.060, (0, ry, -0.900), axis="z", seg=16, bevel=0.0006)
    add_box("LeftCarryHandle", (0.012, 0.030, 0.100), (-0.036, 0.056, -0.300), bevel=0.0008)
    bipod(-0.480, y=0.070)
    lmg_top_rail(0.070, -0.290, 0.150)
    lmg_detail_pack(1.0, 0.028, (0.026, -0.015, -0.150), 0.070, -0.060, 0.460, 0.062)
    _lmg_ribs(1.0, 0.028, -0.060, 0.460, 0.062)
    add_stock("StockBody", 0.048, 0.095, 0.160, 0.170, 0.070, drop=0.12)
    add_grip("Grip", 0.038, 0.110, 0.050, (0, -0.030, 0.050), tilt=0.38, mat="wood", ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.040, 0.020), bevel=0.0005)
    add_trigger_guard(-0.048, 0.005, 0.062)
    bolt_handle(0.035, 0.030, 0.040)
    add_irons("StockIrons", 0.122, -0.600, 0.100, 0.055, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "metal"), ("Cover", "dark"), ("Handguard", "wood"),
        ("Stock", "wood"), ("Grip", "wood"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("LeftCarryHandle", "dark"),
        ("bolt", "dark"), ("mag", "dark"), ("AmmoBox", "dark"),
        ("BeltTail", "dark"), ("Bipod", "dark"),
    ], default="dark")


# ============================================================ RPD
def build_rpd():
    reset()
    ry = 0.026
    add_box("Receiver", (0.056, 0.085, 0.400), (0, 0.018, -0.060), bevel=0.0016)
    add_box("TopCover", (0.052, 0.022, 0.400), (0, 0.068, -0.080), bevel=0.0008)
    add_box("TopCoverRib", (0.054, 0.008, 0.140), (0, 0.081, -0.120), bevel=0.0005)
    # 左侧 100 发弹鼓 v5(用户实拍终版):盘面正对枪口 —— 鼓轴沿枪管前后
    # 方向,圆形鼓盖朝前(左前 3/4 视角可见微椭圆盘面 + 同心盖环 + 中央
    # 凸钮,与实拍一致);位置沿用 v2(机匣前段正下方,z=-0.185),鼓顶埋进
    # 机匣底免挂架;弹链 6 节贴鼓盖前面爬升没入机匣底(链节随切线转向)。
    # (v6 平放方案做过一版,用户复核后确认看错,已还原本版。)
    _dz = -0.185
    _dy = -0.075
    _dx = -0.010
    drum_parts = [
        add_cyl("DrumBody", 0.078, 0.050, (_dx, _dy, _dz), axis="z", seg=26, bevel=0.0012),
        # 前盖同心环 + 中央凸钮(朝枪口面,实拍可见)
        add_cyl("DrumLidRing", 0.060, 0.008, (_dx, _dy, _dz - 0.027), axis="z", seg=24, bevel=0.0005),
        add_cyl("DrumHub", 0.020, 0.016, (_dx, _dy, _dz - 0.031), axis="z", seg=14, bevel=0.0006),
        # 圆缘前后细箍(与鼓身同心)
        add_cyl("DrumLatchT", 0.0795, 0.006, (_dx, _dy, _dz - 0.021), axis="z", seg=26, bevel=0.0004),
        add_cyl("DrumLatchB", 0.0795, 0.006, (_dx, _dy, _dz + 0.021), axis="z", seg=26, bevel=0.0004),
    ]
    # 弹链:鼓前缘下段 → 贴着鼓盖前面向上爬 → 没入机匣底。链节长轴随切线转向。
    _ba = (-0.030, -0.098, -0.222)
    _bc = (-0.030, 0.006, -0.186)
    _bb = ((_ba[0] + _bc[0]) * 0.5 - 0.006, (_ba[1] + _bc[1]) * 0.5 + 0.012, (_ba[2] + _bc[2]) * 0.5 - 0.008)
    for i in range(6):
        t = float(i) / 5.0
        ab = lerp3(_ba, _bb, t)
        bc = lerp3(_bb, _bc, t)
        p = lerp3(ab, bc, t)
        d = (bc[0] - ab[0], bc[1] - ab[1], bc[2] - ab[2])
        import math as _m
        ang = _m.atan2(d[2], d[1])
        drum_parts.append(add_box("_dbt%d" % i, (0.016, 0.034, 0.024), p,
                                  bevel=0.0004, rot_g=(ang, 0, 0)))
    belt = join_parts("DrumBelt", drum_parts[len(drum_parts) - 6:])
    drum_parts = drum_parts[:len(drum_parts) - 6]
    drum = join_parts("mag", drum_parts)
    parent_to(belt, drum)
    # 木护木筒 + 枪管 + 消焰器 + 两脚架
    add_cyl("Handguard", 0.026, 0.280, (0, ry, -0.390), axis="z", seg=20, bevel=0.0010)
    add_cyl("Barrel", 0.0130, 0.420, (0, ry, -0.680), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0180, 0.050, (0, ry, -0.875), axis="z", seg=16, bevel=0.0006)
    bipod(-0.500, y=0.070)
    lmg_top_rail(0.079, -0.260, 0.140)
    lmg_detail_pack(-1.0, 0.026, (-0.048, -0.028, -0.080), 0.079, -0.060, 0.400, 0.056)
    _lmg_ribs(-1.0, 0.026, -0.060, 0.400, 0.056)
    add_stock("StockBody", 0.044, 0.090, 0.160, 0.140, 0.060, drop=0.14)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.024, 0.040), tilt=0.40, mat="wood", ribs=3)
    add_box("Trigger", (0.007, 0.020, 0.009), (0, -0.036, 0.010), bevel=0.0005)
    add_trigger_guard(-0.044, 0.000, 0.055)
    bolt_handle(0.032, 0.035, 0.0)
    add_irons("StockIrons", 0.115, -0.580, 0.100, 0.055, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "metal"), ("TopCover", "dark"), ("Handguard", "wood"),
        ("Stock", "wood"), ("Grip", "wood"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("bolt", "dark"),
        ("mag", "dark"), ("Drum", "dark"), ("DrumNeck", "dark"),
        ("DrumLatch", "dark"), ("DrumMount", "dark"), ("Bipod", "dark"),
        ("DrumBelt", "brass"),
    ], default="dark")


# ============================================================ MG42
def build_mg42():
    reset()
    ry = 0.024
    add_box("Receiver", (0.050, 0.090, 0.400), (0, 0.018, 0.020), bevel=0.0016)
    feed_cover(0.062, -0.120, 0.500, w=0.050)
    belt_feed(-1.0, (-0.0595, -0.088, -0.145), (0.070, 0.100, 0.120),
              (-0.024, 0.054, -0.140), "olive", feed_tray_y=0.054, feed_tray_len=0.26)
    # 多孔枪管套筒(MG42 标志:横向冲压散热孔带)+ 枪口助退器
    add_cyl("BarrelSleeve", 0.022, 0.560, (0, ry, -0.450), axis="z", seg=20, bevel=0.0008)
    for i, hz in enumerate([-0.620, -0.550, -0.480, -0.410, -0.340, -0.270]):
        add_box("SleeveVent%d" % i, (0.052, 0.012, 0.020), (0, ry, hz), bevel=0.0004)
    add_cyl("MuzzleBooster", 0.0140, 0.060, (0, ry, -0.710), axis="z", seg=16, bevel=0.0006)
    lmg_top_rail(0.063, -0.180, 0.220)
    lmg_detail_pack(-1.0, 0.024, (-0.024, -0.018, -0.140), 0.063, 0.020, 0.400, 0.050)
    _lmg_ribs(-1.0, 0.024, 0.020, 0.400, 0.050)
    # 两脚架(斜张) + 木托
    add_box("BipodMount", (0.020, 0.110, 0.030), (0, -0.035, -0.350), bevel=0.0006)
    for s in (-1.0, 1.0):
        leg = add_cyl("BipodLeg%s" % ("L" if s < 0 else "R"), 0.006, 0.160,
                      (s * 0.030, -0.090, -0.350), axis="z", seg=10, bevel=0.0004)
        leg.rotation_euler = rot_g2b((0, 0, s * 0.30))
    add_stock("StockBody", 0.042, 0.095, 0.140, 0.220, 0.063, drop=0.14)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.025, 0.050), tilt=0.40, mat="wood", ribs=3)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.037, 0.020), bevel=0.0005)
    add_trigger_guard(-0.045, 0.005, 0.060)
    bolt_handle(0.030, 0.045, 0.020)
    add_irons("StockIrons", 0.130, -0.550, 0.050, 0.050, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "metal"), ("Cover", "dark"), ("SleeveVent", "metal"),
        ("Stock", "wood"), ("Grip", "wood"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("BarrelSleeve", "dark"), ("MuzzleBooster", "dark"),
        ("bolt", "dark"), ("mag", "olive"), ("AmmoBox", "olive"),
        ("BeltTail", "dark"), ("Bipod", "dark"),
    ], default="dark")


# ============================================================ M60
def build_m60():
    reset()
    ry = 0.028
    add_box("Receiver", (0.052, 0.085, 0.340), (0, 0.018, -0.040), bevel=0.0016)
    feed_cover(0.0625, -0.040, 0.340)
    add_box("TopCarryHandle", (0.030, 0.035, 0.140), (0, 0.073, -0.180), bevel=0.0008)
    belt_feed(-1.0, (-0.0605, -0.090, -0.125), (0.070, 0.100, 0.120),
              (-0.024, 0.050, -0.120), "olive", feed_tray_y=0.050, feed_tray_len=0.24)
    # 粗枪管 + 消焰器 + 两脚架
    add_cyl("Barrel", 0.0160, 0.560, (0, ry, -0.470), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0200, 0.060, (0, ry, -0.735), axis="z", seg=16, bevel=0.0006)
    lmg_top_rail(0.0605, -0.200, 0.140)
    lmg_detail_pack(-1.0, 0.028, (-0.024, -0.018, -0.120), 0.0605, -0.040, 0.340, 0.052)
    _lmg_ribs(-1.0, 0.028, -0.040, 0.340, 0.052)
    bipod(-0.450, y=0.060)
    add_stock("StockBody", 0.042, 0.095, 0.150, 0.130, 0.060, drop=0.14)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.024, 0.040), tilt=0.40, mat="wood", ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.036, 0.020), bevel=0.0005)
    add_trigger_guard(-0.044, 0.005, 0.060)
    bolt_handle(0.030, 0.045, 0.0)
    add_irons("StockIrons", 0.125, -0.520, 0.050, 0.050, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "metal"), ("Cover", "dark"), ("TopCarryHandle", "poly"),
        ("Stock", "wood"), ("Grip", "wood"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("FlashHider", "dark"), ("bolt", "dark"),
        ("mag", "olive"), ("AmmoBox", "olive"), ("BeltTail", "dark"),
        ("Bipod", "dark"),
    ], default="dark")


# ============================================================ Mk48
def build_mk48():
    reset()
    ry = 0.026
    add_box("Receiver", (0.052, 0.090, 0.380), (0, 0.018, -0.040), bevel=0.0016)
    cover = feed_cover(0.062, -0.160, 0.460)
    # 盖顶不放导轨(与全批一致:开盖看到的是供弹机械,镜座在机匣固定轨)
    belt_feed(-1.0, (-0.0605, -0.090, -0.135), (0.070, 0.100, 0.120),
              (-0.024, 0.054, -0.130), "olive", feed_tray_y=0.054, feed_tray_len=0.26)
    # 重管 + 短护木 + 消焰器 + 两脚架
    add_cyl("BarrelSleeve", 0.026, 0.180, (0, ry, -0.340), axis="z", seg=20, bevel=0.0008)
    add_cyl("Barrel", 0.0140, 0.580, (0, ry, -0.510), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0180, 0.060, (0, ry, -0.795), axis="z", seg=16, bevel=0.0006)
    lmg_top_rail(0.063, -0.230, 0.150)
    lmg_detail_pack(-1.0, 0.026, (-0.024, -0.018, -0.130), 0.063, -0.040, 0.380, 0.052)
    _lmg_ribs(-1.0, 0.026, -0.040, 0.380, 0.052)
    bipod(-0.460, y=0.070)
    # 可调聚合物托(缓冲管 + 托体 + 托垫)
    add_cyl("BufferTube", 0.012, 0.100, (0, 0.035, 0.180), axis="z", seg=14, bevel=0.0006)
    add_box("StockBody", (0.042, 0.085, 0.130), (0, 0.010, 0.200), bevel=0.0014)
    add_box("StockPlate", (0.046, 0.095, 0.020), (0, 0.010, 0.270), bevel=0.0010)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.025, 0.050), tilt=0.40, ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.037, 0.020), bevel=0.0005)
    add_trigger_guard(-0.045, 0.005, 0.060)
    bolt_handle(0.030, 0.045, 0.020)
    add_irons("StockIrons", 0.130, -0.580, 0.050, 0.050, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "tan"), ("Cover", "dark"), ("CoverRail", "dark"),
        ("BarrelSleeve", "dark"), ("Stock", "poly"), ("Grip", "poly"),
        ("Trigger", "dark"), ("Barrel", "dark"), ("FlashHider", "dark"),
        ("BufferTube", "dark"), ("bolt", "dark"),
        ("mag", "olive"), ("AmmoBox", "olive"), ("BeltTail", "dark"),
        ("Bipod", "dark"),
    ], default="dark")


# ============================================================ Negev
def build_negev():
    reset()
    ry = 0.026
    add_box("Receiver", (0.052, 0.090, 0.440), (0, 0.018, -0.060), bevel=0.0016)
    feed_cover(0.062, -0.060, 0.440)
    # 机匣固定轨(Negev 特征:开盖时瞄具不跟着掀,所以不 parent 到 cover)
    add_picatinny("FrameRail", 0.300, (0, 0.086, -0.050), width=0.024, mount_h=0.017)
    belt_feed(-1.0, (-0.0605, -0.090, -0.125), (0.070, 0.100, 0.120),
              (-0.024, 0.050, -0.120), "olive", feed_tray_y=0.050, feed_tray_len=0.24)
    # 枪管 + 前握把 + 两脚架 + 消焰器
    add_cyl("Barrel", 0.0120, 0.600, (0, ry, -0.560), axis="z", seg=16, bevel=0.0006)
    add_cyl("FlashHider", 0.0160, 0.060, (0, ry, -0.830), axis="z", seg=16, bevel=0.0006)
    lmg_detail_pack(-1.0, 0.026, (-0.024, -0.018, -0.120), 0.063, -0.060, 0.440, 0.052)
    _lmg_ribs(-1.0, 0.026, -0.060, 0.440, 0.052)
    add_grip("Foregrip", 0.026, 0.070, 0.040, (0, -0.018, -0.260), tilt=0.18, ribs=3)
    bipod(-0.400, y=0.070)
    # 折叠骨架托
    _fold_stock(0.160, top_y=0.045, bot_y=-0.012, arm_len=0.15, plate_z=0.290)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.025, 0.050), tilt=0.40, ribs=4)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.037, 0.020), bevel=0.0005)
    add_trigger_guard(-0.045, 0.005, 0.060)
    bolt_handle(0.030, 0.045, 0.020)
    add_irons("StockIrons", 0.125, -0.600, 0.050, 0.050, ry)
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"),
        ("Receiver", "olive"), ("Cover", "dark"), ("FrameRail", "dark"),
        ("Foregrip", "olive"), ("Stock", "poly"), ("Grip", "poly"),
        ("Trigger", "dark"), ("Barrel", "dark"), ("FlashHider", "dark"),
        ("bolt", "dark"), ("mag", "olive"), ("AmmoBox", "olive"),
        ("BeltTail", "dark"), ("Bipod", "dark"),
    ], default="dark")


# ============================================================ MG3
def build_mg3():
    reset()
    ry = 0.024
    add_box("Receiver", (0.050, 0.090, 0.400), (0, 0.018, 0.020), bevel=0.0016)
    feed_cover(0.062, -0.120, 0.500, w=0.050)
    belt_feed(-1.0, (-0.0595, -0.088, -0.145), (0.070, 0.100, 0.120),
              (-0.024, 0.054, -0.140), "dark", feed_tray_y=0.054, feed_tray_len=0.26)
    add_cyl("BarrelSleeve", 0.022, 0.560, (0, ry, -0.450), axis="z", seg=20, bevel=0.0008)
    for i, hz in enumerate([-0.620, -0.550, -0.480, -0.410, -0.340, -0.270]):
        add_box("SleeveVent%d" % i, (0.052, 0.012, 0.020), (0, ry, hz), bevel=0.0004)
    add_cyl("MuzzleBooster", 0.0140, 0.060, (0, ry, -0.710), axis="z", seg=16, bevel=0.0006)
    add_box("BipodMount", (0.020, 0.110, 0.030), (0, -0.035, -0.350), bevel=0.0006)
    for s in (-1.0, 1.0):
        leg = add_cyl("BipodLeg%s" % ("L" if s < 0 else "R"), 0.006, 0.160,
                      (s * 0.030, -0.090, -0.350), axis="z", seg=10, bevel=0.0004)
        leg.rotation_euler = rot_g2b((0, 0, s * 0.30))
    add_stock("StockBody", 0.042, 0.095, 0.140, 0.220, 0.063, drop=0.14)
    add_grip("Grip", 0.034, 0.100, 0.045, (0, -0.025, 0.050), tilt=0.40, ribs=3)
    add_box("Trigger", (0.007, 0.022, 0.009), (0, -0.037, 0.020), bevel=0.0005)
    add_trigger_guard(-0.045, 0.005, 0.060)
    bolt_handle(0.030, 0.045, 0.020)
    # 鼓式照门(MG3 与 MG42 的区分特征)
    irons = add_irons("StockIrons", 0.130, -0.550, 0.050, 0.050, ry)
    drum = add_cyl("RearDrum", 0.011, 0.020, (0, 0.120, 0.050), axis="x", seg=14, bevel=0.0004)
    join_parts("StockIrons", [drum, irons])
    apply_materials([
        ("FeedTray", "dark"), ("TrayPost", "metal"), ("TrayDivider", "dark"),
        ("TrayWall", "dark"), ("TrayBase", "dark"),
        ("CoverRoller", "metal"), ("CoverPressureFlange", "dark"), ("CoverPawlBlock", "metal"),
        ("EjectionPort", "dark"), ("BeltGuide", "dark"), ("FeedMech", "dark"),
        ("TakedownPin", "metal"), ("BarrelLatch", "dark"), ("SlingLoop", "dark"),
        ("ReceiverRib", "metal"), ("FrameRail", "dark"),
        ("StockIrons", "dark"), ("Irons", "dark"), ("RearDrum", "dark"),
        ("Receiver", "dark"), ("Cover", "dark"),
        ("Stock", "poly"), ("Grip", "poly"), ("Trigger", "dark"),
        ("Barrel", "dark"), ("BarrelSleeve", "dark"), ("MuzzleBooster", "dark"),
        ("bolt", "dark"), ("mag", "dark"), ("AmmoBox", "dark"),
        ("BeltTail", "dark"), ("Bipod", "dark"),
    ], default="dark")


BUILDERS = {
    "m249": build_m249,
    "pkm": build_pkm,
    "rpd": build_rpd,
    "mg42": build_mg42,
    "m60": build_m60,
    "mk48": build_mk48,
    "negev": build_negev,
    "mg3": build_mg3,
}


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
        if wid == "rpd":
            # RPD 走弹鼓流程(drum):只有 mag+bolt,无受弹盖/弹链
            ok = all(k in names for k in ["mag", "bolt"])
        else:
            ok = all(k in names for k in ["mag", "bolt", "FeedCover", "BeltTail", "FeedPort"])
        print("%-6s objs=%-4d verts=%-6d tris=%-6d  契约=%s  %.0f KB" % (
            wid, objs, verts, tris, "OK" if ok else "MISSING!",
            os.path.getsize(path) / 1024.0))
    print("=" * 60)


if __name__ == "__main__":
    main()
