"""
SoldierForge —— NPC 士兵骨骼建模 + 动画(替代盒子拼装 SoldierModel)

为什么重做
----------
原 soldier_model.gd 用 BoxMesh 拼人:四肢是规则长方体、躯干是方块、跑步时手臂
几乎不摆、没有骨盆/躯干联动 —— 用户看到的"方块人 + 动作奇怪不协调"。
本脚本走项目标准 Blender GLB 管线:真骨骼人形(21 骨)+ 蒙皮网格(顶点色分区调色)
+ 4 条骨骼动画(Idle/Walk/Run/Death + 代码控制的 AimPitch),动作在 Blender 里
按人体运动学 K 帧,不再靠代码摆节点。

坐标约定(与 gunforge 一致)
--------------------------
Godot / glTF: +Y 上, -Z 前(人物面朝 -Z,由 bot.gd 的 yaw 语义决定)
Blender:      +Z 上, +Y 深度 —— 人物面朝 +Y 建模(导出自动变 -Z)
              绕 X 正旋转 = 上身后仰,负 = 前倾(勿写反!)

调色方案
--------
每个兵种一个 GLB(建模差异),GLB 内一个 mesh 通吃 3 皮肤 x 2 队伍:网格顶点色
R 通道存"部件 id"(0.1=uniform 0.2=vest 0.3=helmet 0.4=gear 0.5=skin 0.6=boot
0.7=accent 0.8=gear2),Godot 端 soldier_palette.gdshader 按 id 从调色板取色。

四兵种差异(用户要求:建模要做出差异,符合兵种特征)
------------------------------------------------
assault  突击:基准体型,标准背心+双弹匣包+背包。
engineer 工程:背部工具架(线缆卷/撬棍)+盔顶护目镜+胸前爆破块+腰后工具卷。
support  支援机枪手:重装体型(四肢加粗/背心加宽/肩垫加大),胸前斜跨弹链
         (7 颗弹),右腰弹链箱(顶露弹链),加大背包。
recon    侦察狙击手:轻装瘦体型,无背包(低轮廓),吉利布片(肩/背/臂/腿),
         面罩+侧垂布,盔顶植被条,左腰鞍袋+观测镜筒。

用法
----
    blender --background --python build_soldier.py
导出: models/soldiers/soldier_{assault,engineer,support,recon}.glb
"""

import bpy
import math
import random

FPS = 24
OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/soldiers"
CLASSES = ["assault", "engineer", "support", "recon"]

# ---------------------------------------------------------------- 基础工具

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS


def new_mesh_obj(name, me):
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def cyl(name, r, depth, vtx=8, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vtx, radius=r, depth=depth,
                                        location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    return ob


def box(name, sx, sy, sz, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    return ob


def sphere(name, r, seg=8, ring=6, loc=(0, 0, 0), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, radius=r,
                                         location=loc, rotation=rot)
    ob = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    return ob


def assign_vg(ob, bone):
    """整段网格 100% 绑到骨骼(join 后顶点组自动合并进蒙皮)。"""
    vg = ob.vertex_groups.get(bone)
    if vg is None:
        vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')


def paint(ob, fn):
    """按顶点刷部件 id 色到 R 通道。fn(v: Blender 顶点) -> id(float)。"""
    me = ob.data
    ca = me.color_attributes.get("Col")
    if ca is None:
        ca = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
    for i, v in enumerate(me.vertices):
        ca.data[i].color = (fn(v), 0.0, 0.0, 1.0)


def const_id(colid):
    return lambda v: colid


ID_UNIFORM, ID_VEST, ID_HELMET, ID_GEAR, ID_SKIN, ID_BOOT, ID_ACCENT, ID_GEAR2 = \
    0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8

# ---------------------------------------------------------------- 兵种体型变体

# 体型差异(用户要求兵种建模有差异):support 重装加粗,recon 轻装偏瘦。
VARIANTS = {
    #            上臂r   前臂r  vest宽  chest横向 thigh_r shin_r 肩垫r  背包宽/深
    "assault":  dict(arm=0.058, fore=0.050, vest=0.40, chest=1.45, thigh=0.095,
                     shin=0.078, pad=0.074, pack_w=0.26, pack_d=0.12),
    "engineer": dict(arm=0.058, fore=0.050, vest=0.42, chest=1.45, thigh=0.095,
                     shin=0.078, pad=0.074, pack_w=0.24, pack_d=0.05),
    "support":  dict(arm=0.070, fore=0.058, vest=0.47, chest=1.56, thigh=0.108,
                     shin=0.088, pad=0.090, pack_w=0.31, pack_d=0.16),
    "recon":    dict(arm=0.050, fore=0.044, vest=0.36, chest=1.36, thigh=0.088,
                     shin=0.072, pad=0.068, pack_w=0.0,  pack_d=0.0),
}

# ---------------------------------------------------------------- 骨骼

# (骨名, 父, head(x,y,z), tail(x,y,z)) —— rest pose 即端枪战斗姿态
BONES = [
    ("Hips",      None,       (0.00, 0.00, 1.00), (0.00, 0.00, 1.12)),
    ("Spine",     "Hips",     (0.00, 0.00, 1.12), (0.00, 0.02, 1.30)),
    ("AimPitch",  "Spine",    (0.00, 0.02, 1.30), (0.00, 0.04, 1.40)),
    ("Chest",     "Spine",    (0.00, 0.04, 1.40), (0.00, 0.04, 1.56)),
    ("Neck",      "Chest",    (0.00, 0.04, 1.56), (0.00, 0.05, 1.64)),
    ("Head",      "Neck",     (0.00, 0.05, 1.64), (0.00, 0.07, 1.80)),
    # 手臂链挂 AimPitch:瞄准俯仰只带枪+手臂,头/躯干稳定(FPS NPC 标准)
    ("ShoulderL", "AimPitch", (-0.18, 0.03, 1.52), (-0.23, 0.02, 1.49)),
    ("UpperArmL", "ShoulderL", (-0.23, 0.02, 1.49), (-0.18, 0.28, 1.29)),
    ("ForearmL",  "UpperArmL", (-0.18, 0.28, 1.29), (0.10, 0.57, 1.41)),
    ("HandL",     "ForearmL",  (0.10, 0.57, 1.41), (0.12, 0.64, 1.405)),
    ("ShoulderR", "AimPitch", (0.18, 0.03, 1.52), (0.23, 0.02, 1.49)),
    ("UpperArmR", "ShoulderR", (0.23, 0.02, 1.49), (0.27, 0.06, 1.47)),
    ("ForearmR",  "UpperArmR", (0.27, 0.06, 1.47), (0.14, 0.26, 1.44)),
    ("HandR",     "ForearmR",  (0.14, 0.26, 1.44), (0.135, 0.35, 1.435)),
    ("LegsRoot",  "Hips",     (0.00, 0.00, 1.00), (0.00, 0.00, 0.94)),
    ("ThighL",    "LegsRoot", (-0.11, 0.00, 0.94), (-0.11, 0.00, 0.52)),
    ("ShinL",     "ThighL",   (-0.11, 0.00, 0.52), (-0.11, 0.00, 0.12)),
    ("FootL",     "ShinL",    (-0.11, 0.00, 0.12), (-0.11, 0.06, 0.04)),
    ("ThighR",    "LegsRoot", (0.11, 0.00, 0.94), (0.11, 0.00, 0.52)),
    ("ShinR",     "ThighR",   (0.11, 0.00, 0.52), (0.11, 0.00, 0.12)),
    ("FootR",     "ShinR",    (0.11, 0.00, 0.12), (0.11, 0.06, 0.04)),
]


def build_armature():
    ada = bpy.data.armatures.new("SoldierRig")
    arm = bpy.data.objects.new("Armature", ada)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb_map = {}
    for name, parent, head, tail in BONES:
        eb = ada.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        eb_map[name] = eb
        if parent is not None:
            eb.parent = eb_map[parent]
            # 父尾吸附到父骨链(保持连续,避免导出蒙皮断节)
            if eb_map[parent].tail.length < 0.01:
                eb.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


# ---------------------------------------------------------------- 身体网格

def build_body_parts(cls):
    """分段建模(每段单骨刚性绑定,关节用球/套筒遮缝),按兵种变体出件。"""
    V = VARIANTS[cls]
    parts = []

    # ---- 骨盆 + 腰带(Hips) ----
    p = cyl("Pelvis", 0.135, 0.20, vtx=8, loc=(0, -0.005, 1.00))
    p.scale = (1.22, 1.0, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    assign_vg(p, "Hips"); paint(p, const_id(ID_UNIFORM)); parts.append(p)

    belt = box("Belt", 0.30, 0.24, 0.055, loc=(0, 0, 0.965))
    assign_vg(belt, "Hips"); paint(belt, const_id(ID_GEAR)); parts.append(belt)
    pouch = box("HipPouch", 0.09, 0.10, 0.09, loc=(-0.17, 0.10, 0.94))
    assign_vg(pouch, "Hips"); paint(pouch, const_id(ID_GEAR2)); parts.append(pouch)

    # ---- 大腿 x2(ThighL/R,裤腿圆柱) ----
    for s, sfx in ((-1, "L"), (1, "R")):
        t = cyl("Thigh_%s" % sfx, V["thigh"], 0.40, vtx=8,
                loc=(s * 0.098, 0, 0.72))
        assign_vg(t, "Thigh" + sfx); paint(t, const_id(ID_UNIFORM)); parts.append(t)

    # ---- 小腿 + 护膝 + 靴(ShinL/R) ----
    for s, sfx in ((-1, "L"), (1, "R")):
        sh = cyl("Shin_%s" % sfx, V["shin"], 0.36, vtx=8,
                 loc=(s * 0.098, 0, 0.32))
        assign_vg(sh, "Shin" + sfx); paint(sh, const_id(ID_UNIFORM)); parts.append(sh)
        kp = box("KneePad_%s" % sfx, 0.115, 0.055, 0.12,
                 loc=(s * 0.098, 0.065, 0.50))
        assign_vg(kp, "Shin" + sfx); paint(kp, const_id(ID_GEAR)); parts.append(kp)
        boot = box("Boot_%s" % sfx, 0.13, 0.285, 0.105,
                   loc=(s * 0.098, 0.055, 0.06))
        assign_vg(boot, "Shin" + sfx); paint(boot, const_id(ID_BOOT)); parts.append(boot)
        toe = box("Toe_%s" % sfx, 0.12, 0.065, 0.085,
                  loc=(s * 0.098, 0.175, 0.05))
        assign_vg(toe, "Shin" + sfx); paint(toe, const_id(ID_BOOT)); parts.append(toe)

    # ---- 躯干下段(Spine):腹 + 侧腹 ----
    belly = cyl("Belly", 0.145, 0.24, vtx=8, loc=(0, 0.01, 1.19))
    belly.scale = (1.38, 0.92, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    assign_vg(belly, "Spine"); paint(belly, const_id(ID_UNIFORM)); parts.append(belly)

    # ---- 胸段(Chest):胸+背心+挂件(端枪姿态,识别条按队伍调色) ----
    chest = cyl("ChestCore", 0.16, 0.30, vtx=8, loc=(0, 0.02, 1.44))
    chest.scale = (V["chest"], 0.88, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    assign_vg(chest, "Chest"); paint(chest, const_id(ID_UNIFORM)); parts.append(chest)

    vest = box("Vest", V["vest"], 0.27, 0.35, loc=(0, 0.015, 1.42))
    assign_vg(vest, "Chest"); paint(vest, const_id(ID_VEST)); parts.append(vest)
    vest_plate = box("VestPlate", 0.30, 0.03, 0.26, loc=(0, 0.155, 1.44))
    assign_vg(vest_plate, "Chest"); paint(vest_plate, const_id(ID_GEAR)); parts.append(vest_plate)

    # 胸前双弹匣包
    for s in (-1, 1):
        mag = box("MagPouch%d" % s, 0.075, 0.05, 0.13, loc=(s * 0.085, 0.15, 1.36))
        assign_vg(mag, "Chest"); paint(mag, const_id(ID_GEAR2)); parts.append(mag)
    # 队伍识别条(右肩臂外沿)
    band = box("TeamBand", 0.04, 0.20, 0.05, loc=(0.20, 0.08, 1.48),
               rot=(0.15, 0, 0))
    assign_vg(band, "Chest"); paint(band, const_id(ID_ACCENT)); parts.append(band)
    # 双肩带
    for s in (-1, 1):
        st = box("VestStrap%d" % s, 0.05, 0.03, 0.26, loc=(s * 0.115, 0.10, 1.50),
                 rot=(0.12, 0, s * 0.10))
        assign_vg(st, "Chest"); paint(st, const_id(ID_GEAR)); parts.append(st)

    # ---- 头 + 盔(Neck/Head) ----
    neck = cyl("NeckStump", 0.065, 0.09, vtx=6, loc=(0, 0.05, 1.59))
    assign_vg(neck, "Neck"); paint(neck, const_id(ID_SKIN)); parts.append(neck)
    head = sphere("Head", 0.098, seg=8, ring=6, loc=(0, 0.015, 1.685))
    head.scale = (0.92, 1.05, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    assign_vg(head, "Head"); paint(head, const_id(ID_SKIN)); parts.append(head)
    helmet = sphere("Helmet", 0.118, seg=8, ring=6, loc=(0, 0.005, 1.70))
    helmet.scale = (1.06, 1.12, 0.82)
    bpy.ops.object.transform_apply(scale=True)
    assign_vg(helmet, "Head"); paint(helmet, const_id(ID_HELMET)); parts.append(helmet)
    brim = cyl("HelmetBrim", 0.119, 0.025, vtx=10, loc=(0, 0.01, 1.68))
    brim.scale = (1.05, 1.1, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    assign_vg(brim, "Head"); paint(brim, const_id(ID_HELMET)); parts.append(brim)

    # ---- 手臂(端枪姿态已定骨骼;网格按骨骼路径包肉) ----
    # 上臂:肩到肘的斜柱
    arm_defs = [
        ("UpperArmL", "UpperArmL", (-0.23, 0.02, 1.49), (-0.18, 0.28, 1.29), V["arm"]),
        ("UpperArmR", "UpperArmR", (0.23, 0.02, 1.49), (0.27, 0.06, 1.47), V["arm"]),
        ("ForearmL", "ForearmL", (-0.18, 0.28, 1.29), (0.10, 0.57, 1.41), V["fore"]),
        ("ForearmR", "ForearmR", (0.27, 0.06, 1.47), (0.14, 0.26, 1.44), V["fore"]),
    ]
    for pname, bone, a, b, r in arm_defs:
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5)
        dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        ln = math.sqrt(dx * dx + dy * dy + dz * dz)
        # 圆柱默认沿 Z;欧拉 XYZ (0, pitch, rz) 可把 Z 轴精确转到 a->b 方向:
        # Ry(pitch) 把 Z 轴倾到 XZ 面,再 Rz(rz) 转到水平投影方位。
        rz = math.atan2(dy, dx)
        pitch = math.acos(max(-1.0, min(1.0, dz / ln)))
        seg = cyl("Mesh_" + pname, r, ln, vtx=8, loc=mid)
        seg.rotation_euler = (0.0, pitch, rz)
        assign_vg(seg, bone)
        paint(seg, const_id(ID_UNIFORM))
        parts.append(seg)
        # 肘/肩关节球(遮弯折缝)
        j = sphere("Joint_" + pname, r * 1.12, seg=6, ring=5, loc=b)
        assign_vg(j, bone); paint(j, const_id(ID_UNIFORM)); parts.append(j)

    # 手(皮肤色小盒);L 手心对齐护木锚点(HAND_ANCHORS m4 l=(0,-0.03,-0.33) 绕挂载 X+90°
    # → HandR(0.14,0.26,1.44) 系下 (0.14,0.59,1.41),手盒中心微收 —— 左手真实托枪,勿再悬空)
    for sfx, loc in (("L", (0.10, 0.60, 1.41)), ("R", (0.13, 0.28, 1.44))):
        h = box("Hand_" + sfx, 0.06, 0.09, 0.05, loc=loc)
        assign_vg(h, "Hand" + sfx); paint(h, const_id(ID_SKIN)); parts.append(h)

    # 肩甲(Shoulder 骨,装具色,端枪姿态护肩;support 加大)
    for s, sfx in ((-1, "L"), (1, "R")):
        sh = sphere("ShoulderPad_" + sfx, V["pad"], seg=6, ring=5,
                    loc=(s * 0.235, 0.02, 1.50))
        sh.scale = (1.0, 1.15, 0.9)
        bpy.ops.object.transform_apply(scale=True)
        assign_vg(sh, "Shoulder" + sfx); paint(sh, const_id(ID_GEAR)); parts.append(sh)

    # ---- 背部装具(assault/support 背包;engineer/recon 兵种件替代) ----
    if V["pack_w"] > 0.01:
        pack = box("Backpack", V["pack_w"], V["pack_d"], 0.30, loc=(0, -0.17, 1.38))
        assign_vg(pack, "Chest"); paint(pack, const_id(ID_GEAR2)); parts.append(pack)
        pack_lid = box("BackpackLid", V["pack_w"] + 0.01, 0.03, 0.14, loc=(0, -0.17, 1.50))
        assign_vg(pack_lid, "Chest"); paint(pack_lid, const_id(ID_GEAR)); parts.append(pack_lid)
        waist = box("WaistStrap", 0.32, 0.03, 0.05, loc=(0, -0.12, 1.10))
        assign_vg(waist, "Spine"); paint(waist, const_id(ID_GEAR)); parts.append(waist)

    # ---- 兵种专属特征件 ----
    _class_gear(cls, parts)
    return parts


def _class_gear(cls, parts):
    """兵种专属外观件(建模差异,符合各兵种特征)。"""

    # ============ engineer 工程兵:工具架 + 护目镜 + 爆破块 ============
    if cls == "engineer":
        # 背部工具架(替代背包):底板 + 双竖柱 + 顶横梁
        frame = box("EngFrameBase", 0.24, 0.045, 0.30, loc=(0, -0.185, 1.40))
        assign_vg(frame, "Chest"); paint(frame, const_id(ID_GEAR)); parts.append(frame)
        for s in (-1, 1):
            post = box("EngFramePost%d" % s, 0.035, 0.04, 0.36, loc=(s * 0.085, -0.205, 1.44))
            assign_vg(post, "Chest"); paint(post, const_id(ID_GEAR)); parts.append(post)
        beam = box("EngFrameBeam", 0.24, 0.035, 0.045, loc=(0, -0.205, 1.60))
        assign_vg(beam, "Chest"); paint(beam, const_id(ID_GEAR)); parts.append(beam)
        # 线缆卷筒(横放圆柱,架上)
        reel = cyl("EngCableReel", 0.055, 0.17, vtx=10, loc=(0, -0.225, 1.52),
                   rot=(0, math.pi / 2, 0))
        assign_vg(reel, "Chest"); paint(reel, const_id(ID_GEAR2)); parts.append(reel)
        # 撬棍(竖柄露头)
        bar = cyl("EngPrybar", 0.012, 0.26, vtx=6, loc=(0.11, -0.22, 1.46))
        assign_vg(bar, "Chest"); paint(bar, const_id(ID_GEAR2)); parts.append(bar)
        # 盔顶护目镜:镜体 + 两侧带
        gog = box("EngGoggles", 0.17, 0.035, 0.05, loc=(0, 0.015, 1.782))
        assign_vg(gog, "Head"); paint(gog, const_id(ID_GEAR)); parts.append(gog)
        for s in (-1, 1):
            gb = box("EngGoggleBand%d" % s, 0.02, 0.02, 0.09, loc=(s * 0.095, 0.0, 1.74))
            assign_vg(gb, "Head"); paint(gb, const_id(ID_GEAR)); parts.append(gb)
        # 胸前爆破块 x2(弹匣包下方)
        for s in (-1, 1):
            chg = box("EngCharge%d" % s, 0.075, 0.05, 0.115, loc=(s * 0.088, 0.17, 1.295))
            assign_vg(chg, "Chest"); paint(chg, const_id(ID_GEAR2)); parts.append(chg)
        # 腰后工具卷
        roll = box("EngToolRoll", 0.19, 0.06, 0.10, loc=(0, -0.15, 1.06))
        assign_vg(roll, "Spine"); paint(roll, const_id(ID_GEAR)); parts.append(roll)

    # ============ support 支援机枪手:弹链 + 弹箱 + 重装 ============
    elif cls == "support":
        # 胸前斜跨弹链带(右肩 → 左腰)
        a = (0.15, 0.10, 1.54)
        b = (-0.14, 0.13, 1.16)
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5)
        dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        ln = math.sqrt(dx * dx + dy * dy + dz * dz)
        rz = math.atan2(dy, dx)
        pitch = math.acos(max(-1.0, min(1.0, dz / ln)))
        strap = box("MgBelt", 0.07, 0.025, ln, loc=mid, rot=(0, pitch, rz))
        assign_vg(strap, "Chest"); paint(strap, const_id(ID_GEAR)); parts.append(strap)
        # 沿带 7 颗弹(小圆柱,带外侧)
        ux, uy, uz = dx / ln, dy / ln, dz / ln
        for i in range(7):
            t = -0.18 + i * 0.06
            rd = cyl("MgRound%d" % i, 0.014, 0.05, vtx=6,
                     loc=(mid[0] + ux * t, mid[1] + uy * t + 0.028, mid[2] + uz * t),
                     rot=(0, pitch, rz))
            assign_vg(rd, "Chest"); paint(rd, const_id(ID_GEAR2)); parts.append(rd)
        # 右腰弹链箱 + 箱顶露出的弹链(3 竖弹)
        ammo = box("MgAmmoBox", 0.15, 0.19, 0.13, loc=(0.19, 0.06, 1.08))
        assign_vg(ammo, "Spine"); paint(ammo, const_id(ID_GEAR2)); parts.append(ammo)
        for i in range(3):
            lr = cyl("MgBoxLink%d" % i, 0.012, 0.06, vtx=6,
                     loc=(0.19, 0.02 + i * 0.04, 1.165))
            assign_vg(lr, "Spine"); paint(lr, const_id(ID_GEAR)); parts.append(lr)

    # ============ recon 侦察狙击手:吉利服 + 面罩 + 低轮廓 ============
    elif cls == "recon":
        # 面罩(盖口鼻)+ 两侧垂布
        veil = box("RecVeil", 0.135, 0.022, 0.085, loc=(0, 0.096, 1.655))
        assign_vg(veil, "Head"); paint(veil, const_id(ID_GEAR)); parts.append(veil)
        for s in (-1, 1):
            flap = box("RecVeilFlap%d" % s, 0.022, 0.10, 0.13,
                       loc=(s * 0.068, 0.045, 1.63), rot=(0, -s * 0.15, 0))
            assign_vg(flap, "Head"); paint(flap, const_id(ID_GEAR2)); parts.append(flap)
        # 盔顶植被条 x3
        for i, (x, z, ry) in enumerate(((0.0, 1.78, 0.12), (-0.075, 1.762, 0.18), (0.075, 1.762, -0.15))):
            vg_ = box("RecFoliage%d" % i, 0.045, 0.22, 0.04, loc=(x, 0.0, z), rot=(0, ry, 0))
            assign_vg(vg_, "Head"); paint(vg_, const_id(ID_GEAR2)); parts.append(vg_)
        # 左腰鞍袋 + 观测镜筒(替代背包,低轮廓)
        bag = box("RecSaddleBag", 0.10, 0.13, 0.15, loc=(-0.205, -0.05, 1.16))
        assign_vg(bag, "Spine"); paint(bag, const_id(ID_GEAR)); parts.append(bag)
        scope_t = cyl("RecSpotter", 0.032, 0.26, vtx=8, loc=(-0.21, -0.12, 1.38))
        assign_vg(scope_t, "Spine"); paint(scope_t, const_id(ID_GEAR)); parts.append(scope_t)
        lens = cyl("RecSpotterLens", 0.020, 0.02, vtx=8, loc=(-0.21, -0.12, 1.52))
        assign_vg(lens, "Spine"); paint(lens, const_id(ID_GEAR2)); parts.append(lens)
        # 吉利布片 x14(固定种子,肩/背/臂/腿,双色交替)
        random.seed(11)
        ghillie_spots = [
            # (骨, 位置, 尺寸(sx,sy,sz), 欧拉)
            ("Chest",      (0.20, 0.03, 1.50), (0.06, 0.022, 0.13), (0.1, 0.1, 0.3)),
            ("Chest",      (-0.21, -0.01, 1.47), (0.055, 0.022, 0.12), (-0.1, -0.1, -0.4)),
            ("Chest",      (0.12, -0.145, 1.52), (0.075, 0.025, 0.15), (0.2, 0.05, 0.5)),
            ("Chest",      (-0.10, -0.15, 1.44), (0.07, 0.025, 0.14), (-0.15, -0.05, -0.3)),
            ("Chest",      (0.05, -0.155, 1.34), (0.065, 0.022, 0.13), (0.1, 0.0, 0.7)),
            ("Chest",      (-0.06, -0.15, 1.56), (0.06, 0.02, 0.11), (-0.2, 0.08, -0.6)),
            ("UpperArmL",  (-0.28, 0.10, 1.40), (0.05, 0.10, 0.022), (0.0, 0.2, 0.4)),
            ("UpperArmR",  (0.27, 0.02, 1.46), (0.05, 0.09, 0.022), (0.1, -0.15, -0.3)),
            ("UpperArmL",  (-0.25, 0.02, 1.36), (0.045, 0.09, 0.022), (-0.1, 0.3, 0.8)),
            ("UpperArmR",  (0.28, 0.10, 1.42), (0.05, 0.10, 0.022), (0.15, -0.2, -0.5)),
            ("ThighL",     (-0.13, 0.09, 0.80), (0.06, 0.12, 0.022), (0.1, 0.0, 0.5)),
            ("ThighR",     (0.14, 0.08, 0.76), (0.06, 0.11, 0.022), (-0.1, 0.05, -0.7)),
            ("ThighL",     (-0.15, 0.06, 0.62), (0.055, 0.10, 0.022), (0.2, -0.05, 0.9)),
            ("ThighR",     (0.15, 0.09, 0.86), (0.06, 0.12, 0.022), (-0.15, 0.0, -0.4)),
        ]
        for i, (bone, loc, dims, rot) in enumerate(ghillie_spots):
            g = box("RecGhillie%d" % i, dims[0], dims[1], dims[2],
                    loc=loc, rot=rot)
            assign_vg(g, bone)
            paint(g, const_id(ID_GEAR2 if i % 2 else ID_UNIFORM))
            parts.append(g)


def join_body(parts):
    """join 成单 mesh + armature 修改器(蒙皮)。"""
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = parts[0]
    body.name = "Body"
    return body


# ---------------------------------------------------------------- 动画

ANIMATED = ["Hips", "Spine", "AimPitch", "Chest", "Neck", "Head",
            "ShoulderL", "UpperArmL", "ForearmL",
            "ShoulderR", "UpperArmR", "ForearmR",
            "LegsRoot", "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]


def _reset_pose():
    for n in ANIMATED:
        pb = _pose.bones[n]
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def _q(pb_name, rx=0.0, ry=0.0, rz=0.0):
    """欧拉(rad)-> 四元数,赋给 pose bone 并 K 帧。"""
    pb = _pose.bones[pb_name]
    import mathutils
    q = mathutils.Euler((rx, ry, rz), 'XYZ').to_quaternion()
    pb.rotation_quaternion = (q.w, q.x, q.y, q.z)


def _key_all(f):
    for n in ANIMATED:
        pb = _pose.bones[n]
        pb.keyframe_insert('rotation_quaternion', frame=f)
        pb.keyframe_insert('location', frame=f)


def _bake(name, frames, fn):
    """采样式烘焙:每帧 fn(frame) 摆 pose 后对全骨骼 K 帧。"""
    act = bpy.data.actions.new(name)
    _arm_obj.animation_data_create()
    _arm_obj.animation_data.action = act
    for f in frames:
        bpy.context.scene.frame_set(f)
        _reset_pose()
        fn(f)
        _key_all(f)
    # 动作入 NLA(导出器 NLA_TRACKS 模式下每 track = 一条 glTF animation)
    _arm_obj.animation_data.action = None
    tr = _arm_obj.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, int(act.frame_range[0]), act)
    tr.mute = True
    return act


def q4(rx, ry, rz):
    import mathutils
    q = mathutils.Euler((rx, ry, rz), 'XYZ').to_quaternion()
    return (q.w, q.x, q.y, q.z)


def build_animations():
    TAU = math.pi * 2.0

    # ---- Idle(48f = 2s 循环):呼吸/重心微晃/头部警戒扫描/持枪微沉浮 ----
    def idle_fn(f):
        t = f / 48.0 * TAU
        _q("Chest", rx=0.012 * math.sin(t) + 0.01)            # 呼吸起伏
        _q("Spine", rx=0.008 * math.sin(t + 0.5))
        _q("Head", ry=0.28 * math.sin(t * 0.5) )               # 慢速警戒扫描
        _q("Hips", rz=0.015 * math.sin(t))                     # 重心微移
        _q("UpperArmL", rx=0.02 * math.sin(t * 2.0))
        _q("UpperArmR", rx=0.025 * math.sin(t * 2.0 + 1.0))
        _q("AimPitch", rx=0.02 * math.sin(t + 1.2))
    _bake("Idle", range(49), idle_fn)

    # ---- Walk(24f = 1 循环 = 2 步):对侧摆腿/屈膝/骨盆-躯干反向扭转/持枪稳 ----
    def walk_fn(f):
        ph = f / 24.0 * TAU
        A = 0.42                                               # 走路摆腿幅
        for side in (0, 1):
            p = ph + (math.pi if side else 0.0)
            sgn = "R" if side else "L"
            _q("Thigh" + sgn, rx=A * math.sin(p))
            # 屈膝只在摆动相(腿从后向前摆时弯),支撑相近直
            swing = max(0.0, math.sin(p - 0.9))
            _q("Shin" + sgn, rx=-swing * 0.55)
            # 脚补偿保持脚底近似平地
            _q("Foot" + sgn, rx=-(A * math.sin(p)) * 0.4 + swing * 0.35)
        _q("Hips", ry=0.10 * math.sin(ph))                     # 骨盆前送
        _q("Chest", ry=-0.06 * math.sin(ph), rx=0.05)          # 躯干反向扭转+微前倾
        _q("Head", ry=0.045 * math.sin(ph))                    # 头稳(抵消躯干扭转)
        _q("LegsRoot", ry=0.0)                                 # 代码层控制
        _q("UpperArmL", rx=0.03 * math.sin(ph * 2.0))          # 端枪双臂微起伏
        _q("UpperArmR", rx=0.035 * math.sin(ph * 2.0 + 0.8))
        _q("AimPitch", rx=0.015 * math.sin(ph * 2.0))
    _bake("Walk", range(25), walk_fn)

    # ---- Run(16f = 1 循环 = 2 步):大步幅/深屈膝/真前倾/port arms ----
    # 注意:Blender 面朝 +Y,绕 X 正 = 后仰,负 = 前倾(勿写反!)
    def run_fn(f):
        ph = f / 16.0 * TAU
        A = 0.80
        for side in (0, 1):
            p = ph + (math.pi if side else 0.0)
            sgn = "R" if side else "L"
            _q("Thigh" + sgn, rx=A * math.sin(p))
            swing = max(0.0, math.sin(p - 1.1))
            _q("Shin" + sgn, rx=-swing * 1.15)
            _q("Foot" + sgn, rx=-(A * math.sin(p)) * 0.35 + swing * 0.5)
        _q("Hips", ry=0.16 * math.sin(ph))
        _q("Spine", rx=-0.10)                                  # 前倾(负 X = 上身向 +Y 前)
        _q("Chest", ry=-0.10 * math.sin(ph), rx=-0.16)         # 冲刺前倾合计 ~15°
        _q("Head", ry=0.07 * math.sin(ph), rx=0.20)            # 头反向补偿,视线水平
        # [修] 手臂保持 rest 端枪奔跑(双手贴枪)——旧版 port arms 折臂轨让左手脱离
        # 枪身(枪跟右手链走,左手独立轨必脱枪),用户实测"奔跑左手没放枪上"
    _bake("Run", range(17), run_fn)

    # ---- Crouch(16f 循环):战术高低蹲——前腿全蹲膝上耸,后腿外展深折臀坐脚跟 ----
    # [修v3] 用户实测:v2 蹲太浅(骨盆 -0.62)→ 上半身高度几乎没降+脚够不到地 = 浮空;
    # 右腿折叠幅度不够。v3:骨盆 -0.75(髋高 0.25),两腿按踝贴地反推:
    # 左腿大腿 +1.90/小腿 -2.47(膝前顶踝在膝下前,全掌贴地);右腿 +1.30/小腿 -2.62
    # (脚跟收到臀正下贴地);上身微后坐挺直(Spine +0.06)+Head +0.14 视线水平
    def crouch_fn(f):
        t = f / 16.0 * TAU
        pb = _pose.bones["Hips"]
        # [坑·铁律] pb.location 永远是 rest 局部轴,与该骨当前姿态旋转无关!
        # (Blender pose = rest @ T(location) @ R(rotation),平移先于旋转)
        # Hips rest 局部:Y=世界竖直、Z=全局前后。下沉一律写 Y;写 Z = 水平漂移。
        # 旧注释"前倒后局部 Z 转成世界下"是错的——Prone/Death 写 Z 曾致趴姿/尸体悬空 0.8m
        pb.location = (0.0, -0.75, 0.0)                        # 骨盆沿骨轴下移(髋高 0.25)
        _q("ThighL", rx=1.90, rz=-0.12)
        _q("ShinL", rx=-2.47)
        _q("FootL", rx=0.42)
        _q("ThighR", rx=1.30, rz=0.35)
        _q("ShinR", rx=-2.62)
        _q("FootR", rx=0.55)
        # 上身微后坐挺直 + 视线水平,持枪端在胸线
        _q("Spine", rx=0.06)
        _q("Chest", rx=0.02 + 0.015 * math.sin(t))
        _q("Head", rx=0.14)
        _q("UpperArmL", rx=0.05)                               # 肘收贴肋
        _q("UpperArmR", rx=0.03)
    # [修] _bake 必须在 fn 体外(旧版缩进误入函数体,从未执行 → GLB 缺 Crouch 轨)
    _bake("Crouch", range(17), crouch_fn)

    # ---- Prone(16f 循环):贴地趴姿,身体前倒铺平 + 抬头 + 双肘撑地托枪 ----
    # [修v5] 用户实测趴姿悬空(影子实证):location 写 (0,0.08,-0.80) 中 Z 是水平轴
    # (location 恒为 rest 局部轴,Hips 自身旋转不改变其轴向)→ 骨盆没降反升+水平漂移
    # 0.8m,整尸悬在 ~1.06m 高度。改为 Y 轴下沉 -0.83(髋高 0.98→0.15 俯卧贴地)
    def prone_fn(f):
        t = f / 16.0 * TAU
        pb = _pose.bones["Hips"]
        pb.location = (0.0, -0.83 + 0.012 * math.sin(t), 0.0)  # 骨盆贴地(髋高 0.15)+呼吸微起伏
        _q("Hips", rx=-1.46)                                   # 前倾倒平(头朝 +Y 前)
        _q("Spine", rx=0.10)
        _q("Chest", rx=0.22 + 0.012 * math.sin(t))             # 微挺胸撑地
        # 抬头:链累计 -1.14+1.35 = +0.21,脸朝前上 12°(明显抬头不埋地)
        _q("Head", rx=1.35)
        # 双腿贴地微开,脚背朝下
        _q("ThighL", rx=0.10, rz=-0.12)
        _q("ThighR", rx=0.14, rz=0.10)
        _q("ShinL", rx=-0.08)
        _q("ShinR", rx=-0.05)
        _q("FootL", rx=0.30)
        _q("FootR", rx=0.30)
        # [修v6] 手臂重摆 v2:骨位解剖实证——旧 AimPitch 1.16 把肩带翻到支点上方
        # 0.22m(ShoulderL y=0.42),整臂悬空"斜上举"(旧版身体悬空 0.9m 恰好掩盖)。
        # 改 AimPitch 0.30 让肩带贴地(y≈0.1),臂链角度重配:
        _q("UpperArmL", rx=1.35, rz=-0.28)                     # 左肘外撑前伸贴地
        _q("UpperArmR", rx=1.30, rz=0.10)                      # 右肘贴肋前伸
        _q("ForearmL", rx=-0.98)                               # 前臂回折托枪(实证迭代)
        _q("ForearmR", rx=-1.35)
        # 肩带贴地基准:AimPitch 0.30(肩带近贴地),枪线由臂链+HandR 挂载决定
        _q("AimPitch", rx=0.16)
    # [修] _bake 必须在 fn 体外(旧版缩进误入函数体,从未执行 → GLB 缺 Prone 轨)
    _bake("Prone", range(17), prone_fn)

    # ---- Death(30f,一次性):中弹倒地 -> 着地 -> 微弹静止 ----
    # [修v5] 旧 location (0,-0.45e,-0.78e) 的 Z 水平漂移 + Y 下沉不足 → 尸体悬空 0.82m
    # (--test-npc 靠 sm.position.y-=0.82 压镜头掩盖)。改 Y 轴直落 -0.80(髋高 0.18)
    def death_fn(f):
        t = min(1.0, f / 22.0)
        e = 1.0 - (1.0 - t) * (1.0 - t)                        # ease-out
        # 骨盆:倒地 + 下坠
        _q("Hips", rx=-1.42 * e)
        pb = _pose.bones["Hips"]
        pb.location = (0.0, -0.80 * e, 0.0)
        _q("UpperArmL", rz=-0.9 * e, rx=-0.3 * e)
        _q("UpperArmR", rz=0.9 * e, rx=-0.2 * e)
        _q("ForearmL", rx=-0.4 * e)
        _q("ForearmR", rx=-0.3 * e)
        _q("ThighL", rx=-0.1 * e, rz=-0.25 * e)
        _q("ThighR", rx=-0.15 * e, rz=0.18 * e)
        _q("ShinL", rx=0.5 * e)
        _q("ShinR", rx=0.3 * e)
        _q("Head", rx=-0.4 * e)
        if f > 22:
            # 落地微弹(第 23~30 帧 5% 回弹)
            k = math.sin((f - 22) / 8.0 * math.pi) * 0.04
            pb.location = (0.0, -0.80 * (1 + k), 0.0)
            _q("Hips", rx=-1.42 * (1 + k))
    _bake("Death", range(31), death_fn)

    # ---- CrouchWalk(24f 循环):蹲姿步态——髋高恒定深蹲 + 双腿交替小步 ----
    # [v5] 用户实测:蹲下移动时腿保持静止蹲姿很怪。蹲走 = Crouch 基础 + Walk 式对侧摆腿;
    # 摆幅收小(蹲姿步短),小腿全程深弯,脚掌按 (thigh+shin) 反推贴地
    def crouchwalk_fn(f):
        ph = f / 24.0 * TAU
        pb = _pose.bones["Hips"]
        pb.location = (0.0, -0.75 + 0.025 * math.sin(ph * 2.0), 0.0)   # 髋高恒定+步频微起伏
        _q("Hips", ry=0.07 * math.sin(ph))                             # 骨盆前送
        for side in (0, 1):
            p = ph + (math.pi if side else 0.0)
            sgn = "R" if side else "L"
            th = 1.55 + 0.40 * math.sin(p)                             # 蹲姿摆腿(基线深弯)
            sh = -(2.15 + 0.45 * max(0.0, math.sin(p - 0.9)))          # 摆动相屈膝加深
            _q("Thigh" + sgn, rx=th, rz=(-0.12 if side == 0 else 0.30))
            _q("Shin" + sgn, rx=sh)
            _q("Foot" + sgn, rx=-(th + sh) - 0.12)                     # 脚掌贴地补偿
        _q("Spine", rx=0.06)
        _q("Chest", rx=0.02, ry=-0.05 * math.sin(ph))
        _q("Head", rx=0.14)
        _q("UpperArmL", rx=0.05)                                       # 端枪微起伏
        _q("UpperArmR", rx=0.03)
        _q("LegsRoot", ry=0.0)                                         # 代码层控制
    _bake("CrouchWalk", range(25), crouchwalk_fn)

    # ---- ProneCrawl(32f 循环):匍匐爬行——Prone 基础 + 四肢交替爬动 ----
    # [v5.1] 首版摆幅过大:手臂划到头顶外/腿翘 25°,游戏内视角像翻滚仰卧(实拍证伪)。
    # 收敛:臂摆 ±0.18、腿摆 ±0.20、躯干扭摆减半,保持"贴地爬"而不是"抹泳"
    def pronecrawl_fn(f):
        ph = f / 32.0 * TAU
        pb = _pose.bones["Hips"]
        pb.location = (0.0, -0.83 + 0.012 * math.sin(ph * 2.0), 0.0)   # 贴地 + 爬行微起伏
        _q("Hips", rx=-1.46, ry=0.03 * math.sin(ph))                   # 躯干铺平 + 轻扭摆
        _q("Spine", rx=0.10, ry=0.03 * math.sin(ph))
        _q("Chest", rx=0.22, ry=0.03 * math.sin(ph + math.pi))
        _q("Head", rx=1.35)
        for side in (0, 1):
            p = ph + (math.pi if side else 0.0)
            sgn = "R" if side else "L"
            _q("UpperArm" + sgn, rx=(1.35 if side == 0 else 1.30) + 0.18 * math.sin(p),
               rz=(-0.28 if side == 0 else 0.10))                      # 交替前扒(小摆幅)
            _q("Forearm" + sgn, rx=(-0.98 if side == 0 else -1.28) - 0.22 * max(0.0, math.sin(p - 0.8)))
            _q("Thigh" + sgn, rx=(0.10 if side == 0 else 0.14) + 0.20 * math.sin(p + math.pi),
               rz=(-0.12 if side == 0 else 0.10))                      # 交替后蹬(贴地小步)
            _q("Shin" + sgn, rx=-0.08 - 0.28 * max(0.0, math.sin(p + math.pi - 1.0)))
            _q("Foot" + sgn, rx=0.30)
        _q("AimPitch", rx=0.10)                                        # 肩带贴低(同 Prone v6)
        _q("LegsRoot", ry=0.0)
    _bake("ProneCrawl", range(33), pronecrawl_fn)


# ---------------------------------------------------------------- 导出

def main():
    global _arm_obj, _pose
    import os
    os.makedirs(OUT_DIR, exist_ok=True)
    for cls in CLASSES:
        reset()
        arm = build_armature()
        _arm_obj = arm
        _pose = arm.pose

        parts = build_body_parts(cls)
        body = join_body(parts)

        # 蒙皮:parent + armature modifier(顶点组已带骨权重)
        body.parent = arm
        mod = body.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm

        print("[SOLDIER:%s] 顶点=%d 面=%d" % (cls, len(body.data.vertices), len(body.data.polygons)))

        build_animations()

        # 导出前强制求值(沿用 gunforge 教训:matrix_world 惰性)
        bpy.context.view_layer.update()
        out = os.path.join(OUT_DIR, "soldier_%s.glb" % cls)
        bpy.ops.export_scene.gltf(
            filepath=out,
            export_format='GLB',
            export_apply=False,          # 蒙皮网格不可 apply 修改器
            export_yup=True,
            export_skins=True,
            export_animations=True,
            export_animation_mode='NLA_TRACKS',
            export_optimize_animation_size=False,
        )
        print("[SOLDIER] 导出完成:", out)


if __name__ == "__main__":
    main()
