"""
GunForge —— Blender 无头武器建模框架

为什么需要它
------------
项目原先所有枪都是 GDScript 用 box/cyl/ring 图元拼的(weapon_models.gd)。那套管线的
表达力上限就是"直角盒子 + 正圆柱",而真枪上没有任何一处绝对直角:机匣有脱模斜度、
弹匣井和抛壳窗是切出来的、导轨是 10.4mm 齿距的、消焰器是开槽的。纯图元拼接做不出
这些特征,所以怎么加零件都还是"积木感"。

Blender 给了两样 GDScript 没有的东西:布尔运算(真能切出抛壳窗/弹匣井)和倒角修改器
(真圆角边缘,低模也能出金属高光)。而且导出的 GLB 会保留对象名 —— 每个零件在 Godot
里就是独立节点,换弹动画需要的 mag/bolt/slide 才拿得到。

坐标系
------
Godot / glTF: +Y 上, -Z 前(枪口朝 -Z)
Blender:      +Z 上, +Y 深度

glTF 导出做的是 (x,y,z)_blender -> (x,z,-y)_gltf,所以反向映射为:
    bx =  gx
    by = -gz
    bz =  gy

建模时一律按 Godot 语义坐标思考(g2b 内部转换),好处是可以直接复用现有 weapon_models.gd
里已经调好的手部锚点 / 枪口点 / 配件锚点,重建模型不会打乱它们。

用法
----
    blender --background --python build_m4.py
或直接:
    from gunforge import *
"""

import bpy
import math


# ---------------------------------------------------------------- 场景

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def g2b(p):
    """Godot 位置 (x,y,z) -> Blender 位置。"""
    return (p[0], -p[2], p[1])


def gsz(s):
    """Godot 尺寸 (宽w, 高h, 深d) -> Blender 尺寸 (x,y,z)。"""
    return (s[0], s[2], s[1])


_AXIS_MAP = {"x": "X", "y": "Z", "z": "Y"}   # Godot 轴 -> Blender 轴


def rot_g2b(r):
    """
    Godot 欧拉角 (绕 X / Y / Z) -> Blender 欧拉角。

    推导(Godot->Blender 是 (x,y,z) -> (x,-z,y)):
      绕 Godot X 转 θ  ==  绕 Blender X 转  θ
      绕 Godot Z 转 θ  ==  绕 Blender Y 转 -θ
      绕 Godot Y 转 θ  ==  绕 Blender Z 转  θ
    搞错这个,握把会往后倒、弹匣会歪,所以单独封一个函数而不是到处手写。
    """
    return (r[0], -r[2], r[1])


def _deselect_all():
    bpy.ops.object.select_all(action='DESELECT')


def _activate(ob):
    _deselect_all()
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    return ob


def add_bevel(ob, width=0.001, segments=2):
    """倒角。真枪零件的边缘圆角 —— 低模下金属质感的来源。"""
    mod = ob.modifiers.new(name="bevel", type='BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(60)
    _activate(ob)
    try:
        bpy.ops.object.modifier_apply(modifier="bevel")
    except Exception as e:
        print("  [warn] bevel apply failed on %s: %s" % (ob.name, e))
    return ob


# ---------------------------------------------------------------- 图元

def add_box(name, size_g, pos_g, bevel=0.0, bevel_seg=2, rot_g=None):
    """盒子。size_g / pos_g 均为 Godot 语义 (w,h,d) / (x,y,z)。"""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g2b(pos_g))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = gsz(size_g)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot_g:
        ob.rotation_euler = rot_g2b(rot_g)
    if bevel > 0:
        add_bevel(ob, bevel, bevel_seg)
    return ob


def add_cyl(name, radius, length, pos_g, axis="z", seg=24, bevel=0.0, taper=None):
    """
    圆柱 / 锥台。axis 用 Godot 轴名('x'/'y'/'z')。
    taper: 末端半径比例(0~1,0.88 = 末端收细到 88%),None 表示等径。
    """
    # Blender 5.x 的 primitive_cylinder_add 只有 radius(无 radius_top/bottom),
    # 锥台靠创建后直接改顶点半径实现。
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=seg,
        radius=radius,
        depth=length,
        location=g2b(pos_g),
    )
    ob = bpy.context.active_object
    ob.name = name
    if taper is not None:
        # 锥台:直接改顶点半径。taper 是比例(末端半径 = radius * taper,0.88=末端收细12%)。
        # 教训:旧实现把 taper 当"另一端的绝对半径"(米)用,狙击批次传 0.88
        # 直接把枪管末端张成直径 1.76m 的喇叭,ADS 视轴全挡 —— 语义必须在 API 注释里钉死。
        for v in ob.data.vertices:
            t = (v.co.z + length * 0.5) / max(length, 1e-9)
            r = radius * (1.0 + (taper - 1.0) * t)
            if abs(v.co.x) > 1e-9 or abs(v.co.y) > 1e-9:
                cur = math.hypot(v.co.x, v.co.y)
                if cur > 1e-9:
                    v.co.x *= r / cur
                    v.co.y *= r / cur
    # 圆柱默认沿 Blender Z;Godot 'z'(枪管方向)对应 Blender 'Y'
    if axis == "z":
        ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    elif axis == "x":
        ob.rotation_euler = (0.0, math.pi * 0.5, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if bevel > 0:
        add_bevel(ob, bevel, 2)
    return ob


def add_torus(name, major, minor, pos_g, seg_major=24, seg_minor=10):
    """环(准星护圈 / 照门环 / 弹链扣)。孔洞沿 Godot Z 轴。"""
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=seg_major, minor_segments=seg_minor,
        location=g2b(pos_g),
    )
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return ob


# ---------------------------------------------------------------- 布尔

def cut(target, cutter, keep_cutter=False, solver='EXACT'):
    """
    布尔减:从 target 上挖掉 cutter。抛壳窗、弹匣井、减重槽全靠它。

    注意:modifier_apply 只作用于 active object,必须先把 target 设为活动对象,
    否则静默失败(不报错,但切割没生效 —— 已踩过)。
    """
    mod = target.modifiers.new(name="bool_cut", type='BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cutter
    if hasattr(mod, "solver"):
        mod.solver = solver
    _activate(target)
    ok = True
    try:
        bpy.ops.object.modifier_apply(modifier="bool_cut")
    except Exception as e:
        print("  [warn] boolean failed on %s: %s" % (target.name, e))
        ok = False
    if not keep_cutter:
        _deselect_all()
        cutter.select_set(True)
        bpy.ops.object.delete()
    return ok


def union(target, other, keep_other=False):
    """布尔并:把两个零件焊成一个(用于复杂壳体的组合)。"""
    mod = target.modifiers.new(name="bool_union", type='BOOLEAN')
    mod.operation = 'UNION'
    mod.object = other
    if hasattr(mod, "solver"):
        mod.solver = 'EXACT'
    _activate(target)
    try:
        bpy.ops.object.modifier_apply(modifier="bool_union")
    except Exception as e:
        print("  [warn] union failed: %s" % e)
    if not keep_other:
        _deselect_all()
        other.select_set(True)
        bpy.ops.object.delete()
    return target


# ---------------------------------------------------------------- 复用零件

## 导轨截面总厚(底座+齿,沿"齿朝向"方向),供侧轨/底轨计算贴合偏移
RAIL_THICK = 0.0074


def add_picatinny(name, length, pos_g, width=0.0212, rot_z=0.0, mount_h=0.0):
    """
    MIL-STD-1913 导轨:齿距 10.4mm、齿顶宽 5.2mm、顶面宽 21.2mm。

    pos_g 语义:齿顶平面中心(默认顶轨:齿朝 +Y,齿顶在 pos_g.y)。
    rot_z:整条导轨绕枪管轴(Godot Z)旋转,用于侧轨/底轨 ——
           不旋转的侧轨就是"齿朝上的平躺板",悬在枪身侧面,一眼假(玩家已抓包)。
           右侧轨(齿朝 +X)用 -PI/2,左侧轨(齿朝 -X)用 +PI/2,底轨(齿朝 -Y)用 PI。
    mount_h:贴合垫块。传"机匣顶面到齿底的落差",底座向下延伸实心填满,
           导轨才真正"坐"在机匣上,否则齿顶对齐视轴后底座悬空 10~15mm。
    """
    return _picatinny_group(name, length, pos_g, width, rot_z, mount_h)


## 导轨截面总厚(沿"齿朝向"方向),侧轨/底轨算贴合偏移用
RAIL_THICK = 0.0074


def _picatinny_group(name, length, pos_g, width, rot_z, mount_h):
    """按默认朝向(齿朝 +Y,齿顶平面过 pos_g)构建后整体绕 Godot Z 转 rot_z。
    mount_h>0 时底座向下延伸,把导轨坐实到机匣面。"""
    import mathutils
    pitch = 0.0104
    tooth_w = 0.0052
    tooth_h = 0.0042
    parts = []
    base_h = 0.0044 + mount_h
    parts.append(add_box(name + "_base", (width + 0.0125, base_h, length),
                         (pos_g[0], pos_g[1] - 0.0030 - base_h * 0.5, pos_g[2]),
                         bevel=0.0004))
    parts.append(add_box(name + "_web", (width + 0.0044, 0.0028, length),
                         (pos_g[0], pos_g[1] - 0.0030, pos_g[2]), bevel=0.0004))
    z0 = pos_g[2] - length * 0.5 + pitch * 0.5
    n = max(1, int(length / pitch))
    for i in range(n):
        parts.append(add_box(name + "_t%d" % i, (width, tooth_h, tooth_w),
                             (pos_g[0], pos_g[1] - tooth_h * 0.5, z0 + i * pitch),
                             bevel=0.0003))
    joined = join_parts(name, parts)
    if rot_z != 0.0:
        # join 后原点在 base 中心,直接设旋转会绕错轴 —— 把枢轴搬回 pos_g:
        # 新位置 = pos_g + R(rot_z) @ (原位置 - pos_g)
        # 轴向铁律:绕枪管轴(Godot Z)转 θ == 绕 Blender Y 转 -θ(rot_g2b 推导)。
        # 旧版误用 Blender Z(= Godot 竖直轴)= 偏航 90° —— 侧轨没滚到齿朝外,
        # 反而整条横过来穿出枪身(玩家实机抓包的"横向穿模翅膀"根因)。
        R = mathutils.Matrix.Rotation(-rot_z, 3, 'Y')
        pivot = mathutils.Vector(g2b(pos_g))
        joined.location = pivot + R @ (joined.location - pivot)
        joined.rotation_euler.y += -rot_z
    return joined


def add_empty(name, pos_g):
    """空节点(参考点)。GLB 导出为无 mesh 的 node,Godot 导入成 Node3D,
    名字保留 —— feed_port 这类"逻辑锚点"就靠它进引擎。"""
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=g2b(pos_g))
    ob = bpy.context.active_object
    ob.name = name
    ob.empty_display_size = 0.01
    return ob


def parent_to(child, parent):
    """保持世界变换的父子绑定。弹链尾(BeltTail)必须 parent 到弹链箱(mag):
    换弹拆箱时弹链要跟着走,控制器按 mag.get_node_or_null("BeltTail") 找它。
    matrix_world 是 depsgraph 惰性求值 —— 刚用 ops 摆完位置立即读会拿到陈旧矩阵,
    父子绑定整体错位(gl 膛体被抬到视线正中实锤过),必须先强制刷新。"""
    # Python 直接赋 child.parent 不会自动算 matrix_parent_inverse(那是 ops 的行为),
    # 必须手动设 parent.MW^-1 —— 保持子件世界位置。
    # 注意:不要右乘 child.MW!无父子件的 basis=world,右乘会把 world 应用两次
    # (弹链位置精确 2 倍偏移的实锤根因)。
    # matrix_world 是 depsgraph 惰性求值,ops 摆位后必须先强制刷新再读。
    bpy.context.view_layer.update()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()
    bpy.context.view_layer.update()
    return child


def lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def join_parts(name, objs):
    """把若干对象合并为一个,减少节点数(它们之间没有相对运动)。"""
    if not objs:
        return None
    _deselect_all()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    merged = bpy.context.active_object
    merged.name = name
    return merged


# ---------------------------------------------------------------- 枪械通用部件

def add_grip(name, w, h, d, pos_g, tilt=0.32, mat="poly", ribs=0, bevel=0.0012):
    """
    手枪式握把:枢轴在 pos_g(顶端贴合机匣底),绕 Godot X 轴后倾 tilt。
    pos_g = (x, y_top, z)。与 WeaponModels._grip 几何一致,保证手部锚点不变。
    ribs > 0 时加横向防滑棱。
    """
    # 倾角符号(全枪握把前倾翻车的根因):Rx(θ) 下握把底端 (0,-h/2,0) 的
    # z 偏移 = -h/2·sinθ —— 正 θ 让底端往 -z(枪口方向)偏 = 前倾。
    # 握把必须后倾(底端往 +z 射手方向),所以旋转取 -tilt、中心 z 偏移取 +。
    cy = -h * 0.5 * math.cos(tilt)
    cz = +h * 0.5 * math.sin(tilt)
    center_g = (pos_g[0], pos_g[1] + cy, pos_g[2] + cz)
    ob = add_box(name, (w, h, d), center_g, bevel=bevel, rot_g=(-tilt, 0, 0))
    parts = [ob]
    for i in range(ribs):
        # 防滑棱沿前撑板分布(前撑板朝 -z 枪口侧,偏移取 -d*0.42)
        f = (i + 1) / float(ribs + 1)
        ly = -h * f * math.cos(tilt)
        lz = +h * f * math.sin(tilt)
        rib = add_box("%s_rib%d" % (name, i), (w * 1.05, 0.005, d * 0.16),
                      (pos_g[0], pos_g[1] + ly, pos_g[2] + lz - d * 0.42),
                      bevel=0.0004, rot_g=(-tilt, 0, 0))
        parts.append(rib)
    if len(parts) > 1:
        return join_parts(name, parts)
    return ob


def add_stock(name, w, h, length, attach_z, attach_y, drop=0.10, plate=True, bevel=0.0015):
    """直枪托(2026-09 全项目"枪托偏下"统一修正)。
    旧版多处用 add_grip(握把逻辑:枢轴在顶、往下长)做枪托 —— 托底比枪管
    轴线低 10cm,像握把一样吊在机匣下(实拍实锤)。直托:前端面与机匣后
    端面重叠 12mm 焊死,上缘贴 attach_y(机匣顶)下方 6mm,向后下垂 drop
    弧度。符号:Godot Rx 正角降低 +z 端 —— 正 drop = 托尾下沉(别再写反)。
    attach_z = 机匣后端面 z,attach_y = 机匣顶 y。
    plate=True 自动生成贴合后端面的托底板(命名 <name>Plate,按 Stock 前缀
    命中材质规则)。"""
    cy = attach_y - h * 0.5 + 0.006
    cz = attach_z + length * 0.5 - 0.012
    body = add_box(name, (w, h, length), (0, cy, cz), bevel=bevel, rot_g=(drop, 0, 0))
    if plate:
        ry_ = cy - (length * 0.5) * math.sin(drop)     # 后端面中心 y(下沉)
        rz_ = cz + (length * 0.5) * math.cos(drop)     # 后端面中心 z
        add_box(name + "Plate", (w + 0.004, h + 0.010, 0.022), (0, ry_, rz_ + 0.011),
                bevel=bevel * 0.8, rot_g=(drop, 0, 0))
    return body


def add_mag_straight(name, w, h, d, pos_g, tilt=0.0, mat="dark", holes=0):
    """
    直弹匣。pos_g = (x, y_top, z) —— y_top 是插入弹匣井的顶部高度。
    返回的对象名必须是 'mag',Godot 侧按名字绑定换弹可动件。
    holes: 侧面观察孔数量。
    """
    cy = -h * 0.5 * math.cos(tilt)
    cz = -h * 0.5 * math.sin(tilt)
    body = add_box(name, (w, h, d),
                   (pos_g[0], pos_g[1] + cy, pos_g[2] + cz),
                   bevel=0.0010, rot_g=(tilt, 0, 0))
    parts = [body]
    # 底板
    fy = -h * math.cos(tilt)
    fz = -h * math.sin(tilt)
    parts.append(add_box("%s_floor" % name, (w * 1.08, 0.010, d * 1.06),
                         (pos_g[0], pos_g[1] + fy, pos_g[2] + fz),
                         bevel=0.0006, rot_g=(tilt, 0, 0)))
    mag = join_parts(name, parts)
    mag.name = "mag"
    # 观察孔:布尔挖穿侧壁,能看到里面的托弹板
    for i in range(holes):
        f = 0.30 + 0.18 * i
        hy = -h * f * math.cos(tilt)
        hz = -h * f * math.sin(tilt)
        cutter = add_box("_maghole%d" % i, (w * 1.4, 0.007, 0.007),
                         (pos_g[0], pos_g[1] + hy, pos_g[2] + hz + d * 0.5),
                         bevel=0.0)
        cut(mag, cutter)
    # 托弹板:顶部能瞥见一点,增加可信度
    fol = add_box("MagFollower", (w * 0.88, 0.008, d * 0.85),
                  (pos_g[0], pos_g[1] - 0.008, pos_g[2]), bevel=0.0004,
                  rot_g=(tilt, 0, 0))
    return mag


def add_mag_curved(name, w, pos_g, mat="metal"):
    """
    弯弹匣(AK 系):三段递减前倾,复刻 WeaponModels._curved_mag 的弧度。
    返回名必须是 'mag'。
    """
    x, y_top, z = pos_g
    parts = []
    parts.append(add_box("%s_s1" % name, (w, 0.070, 0.052), (x, y_top - 0.032, z + 0.004), bevel=0.0010))
    parts.append(add_box("%s_s2" % name, (w * 0.95, 0.070, 0.050), (x, y_top - 0.097, z - 0.012),
                         bevel=0.0010, rot_g=(0.32, 0, 0)))
    parts.append(add_box("%s_s3" % name, (w * 0.88, 0.060, 0.046), (x, y_top - 0.152, z - 0.048),
                         bevel=0.0010, rot_g=(0.60, 0, 0)))
    parts.append(add_box("%s_floor" % name, (w * 0.92, 0.010, 0.048), (x, y_top - 0.180, z - 0.070),
                         bevel=0.0006, rot_g=(0.60, 0, 0)))
    mag = join_parts(name, parts)
    mag.name = "mag"
    return mag


def add_irons(name, sight_y, fz, rz, post_h, barrel_y=0.03):
    """
    机械瞄具:前准星柱 + 后缺口双耳。整个组命名为 StockIrons,
    与 WeaponModels 一致 —— 装备光学瞄具时由 gun.gd 整组隐藏。
    视轴高度 sight_y,前/后位置 fz / rz。
    """
    irs = []
    # 前准星底座(自枪管向上)+ 准星柱
    base_h = max((sight_y - post_h) - barrel_y + 0.006, 0.018)
    irs.append(add_box("IronsFrontBase", (0.022, base_h, 0.020),
                       (0, barrel_y + base_h * 0.5, fz), bevel=0.0006))
    irs.append(add_box("IronsFront", (0.009, post_h, 0.011),
                       (0, sight_y - post_h * 0.5, fz), bevel=0.0004))
    # 后照门底座 + 双耳
    rb_h = max((sight_y - 0.02) - barrel_y, 0.012)
    irs.append(add_box("IronsRearBase", (0.024, rb_h, 0.020),
                       (0, barrel_y + rb_h * 0.5, rz), bevel=0.0006))
    irs.append(add_box("IronsRearL", (0.005, 0.020, 0.016), (-0.009, sight_y - 0.010, rz), bevel=0.0004))
    irs.append(add_box("IronsRearR", (0.005, 0.020, 0.016), (0.009, sight_y - 0.010, rz), bevel=0.0004))
    joined = join_parts(name, irs)
    joined.name = "StockIrons"
    return joined


def add_trigger_guard(y, zf, zb, w=0.008, depth=0.024):
    """扳机护圈:三段拼一个 U 形(护圈内要能看见手指,不能是实心块)。"""
    parts = [
        add_box("TriggerGuardF", (w, depth, 0.010), (0, y, zf), bevel=0.0006),
        add_box("TriggerGuardB", (w, depth, 0.010), (0, y + 0.002, zb), bevel=0.0006),
        add_box("TriggerGuardBtm", (w, 0.008, absf(zb - zf)),
                (0, y - depth * 0.5, (zf + zb) * 0.5), bevel=0.0006),
    ]
    return parts


def add_serrations(name, side, y, z0, z1, n=6, w=0.036, depth=0.0035, groove=(0.0035, 0.022), tilt=0.0):
    """套筒防滑拉栓槽(斜向凹槽,布尔挖进套筒侧壁)。side=-1 左 / +1 右。
    groove=(槽宽, 槽深) — Godot 语义坐标,z0>z1 或反之都行。返回切割后的对象列表(cutter 已删)。

    ⚠ 已实锤的两个致命坑(2026-09 m1911"机匣长方形镂空"根因):
    1. 相邻 cutter 沿 z 重叠(槽长 > 间距)时,逐个布尔会把目标网格撕成碎片;
    2. 目标是 join 出的多壳体(如盒体+侧面壁)时,面壁内侧面与盒体侧面
       严格共面 —— EXACT 求解器直接吞掉半边网格(216 面切完剩 108 面)。
    规则:布尔只对单一壳体做;cutter 互不重叠;防滑槽建议直接用加法凸肋
    (build_pistol_batch.build_semi_auto 的 v5 写法)。"""
    cutters = []
    span = absf(z1 - z0)
    for i in range(n):
        f = (i + 0.5) / float(n)
        z = min(z0, z1) + span * f
        c = add_box("_%s_c%d" % (name, i), (groove[0], groove[1], w * 0.45),
                    (side * (w * 0.5), y, z), rot_g=(0, 0, tilt))
        cutters.append(c)
    return cutters


def add_knurl(name, w, z_center, y, h=0.030, n=7, depth=0.0018, axis="y"):
    """握把前后撑板防滑纹:一排凸起横棱(比挖槽便宜,第一人称近景读得出)。
    沿 Godot Z 轴排布在 z_center 处,宽 w,总高 h。"""
    parts = []
    for i in range(n):
        f = (i + 0.5) / float(n)
        yy = y - h * f
        parts.append(add_box("_%s_k%d" % (name, i), (w, depth, h * 0.55 / max(n, 1)),
                             (0, yy, z_center), bevel=0.0002))
    return join_parts(name, parts)


def add_step_barrel(name, y, steps, seg=20):
    """阶梯枪管:steps = [(z_center, length, radius), ...] 从后到前递减。"""
    parts = []
    for i, (zc, ln, r) in enumerate(steps):
        parts.append(add_cyl("%s_s%d" % (name, i), r, ln, (0, y, zc), axis="z", seg=seg, bevel=0.0005))
    return join_parts(name, parts)


def add_crown(name, r, y, z):
    """枪口冠:倒角环。细且薄 —— 粗环在光下读成"空管口"(用户实拍反馈),只留一圈高光。"""
    return add_torus(name, r + 0.0006, 0.0007, (0, y, z), seg_major=20, seg_minor=6)


def add_brake_ports(name, r, y, z, n=3, w=0.046):
    """制退器侧孔:上下交错挖穿制退器体。返回 cutter 列表(调用方自己 cut 到目标件)。"""
    cutters = []
    for i in range(n):
        dz = (i - (n - 1) * 0.5) * 0.018
        cutters.append(add_box("_%s_pu%d" % (name, i), (w, 0.010, 0.010), (0, y + r * 0.55, z + dz)))
        cutters.append(add_box("_%s_pd%d" % (name, i), (w, 0.010, 0.010), (0, y - r * 0.55, z + dz + 0.009)))
    return cutters


def add_stock_thumbhole(target, cx, cy, cz, rx=0.014, rz=0.030):
    """托体拇指孔:竖直椭圆布尔挖穿(骨架托拇指孔观感)。cut 后返回。"""
    c = add_cyl("_thumbhole", rx, rz * 2.4, (cx, cy, cz), axis="y", seg=18)
    scale = c.scale
    c.scale = (scale[0], 1.0, 0.45)   # Blender 局部轴压扁成椭圆 — y 是 Blender 深度轴
    cut(target, c)
    return target


def add_butt_pad(name, y, z, w=0.040, h=0.096):
    """托底橡胶垫:比托板略凸的一块,分色。"""
    return add_box(name, (w + 0.004, h, 0.014), (0, y, z), bevel=0.0008)


def add_scope_sunshade(y, z_front, r):
    """镜筒遮阳罩(物镜前延伸管)。"""
    return add_cyl("_SunShade", r * 0.94, 0.055, (0, y, z_front - 0.026), axis="z", seg=22, bevel=0.0004)


def add_parallax_knob(name, y, z, r):
    """物镜侧视差调节钮(左侧粗钮 + 三段滚花棱)。"""
    parts = [add_cyl(name, 0.011, 0.016, (-(r + 0.008), y, z), axis="x", seg=14, bevel=0.0004)]
    for i in range(3):
        parts.append(add_box("_%s_f%d" % (name, i), (0.018, 0.0022, 0.014),
                             (-(r + 0.008), y, z - 0.005 + i * 0.005), bevel=0.0002))
    return join_parts(name, parts)


def add_vent_slots(name, side, y, z0, z1, n=5, depth=0.010, slot=(0.008, 0.026)):
    """护木散热槽(挖穿侧壁,护木内透光)。返回 cutter 列表。"""
    cutters = []
    span = absf(z1 - z0)
    for i in range(n):
        f = (i + 0.5) / float(n)
        z = min(z0, z1) + span * f
        cutters.append(add_box("_%s_v%d" % (name, i), (slot[0], slot[1], depth),
                               (side * 0.020, y, z)))
    return cutters


def add_checkering(name, w, h, pos_g, n=6, m=3, depth=0.0016):
    """托面/握把菱形防滑纹(双向细棱交叉网格,贴面凸起)。"""
    parts = []
    for i in range(n):
        f = (i + 0.5) / float(n)
        parts.append(add_box("_%s_h%d" % (name, i), (w, depth, 0.0016),
                             (pos_g[0], pos_g[1] - h * f, pos_g[2]), bevel=0.0001))
    for j in range(m):
        parts.append(add_box("_%s_v%d" % (name, j), (0.0016, depth, h),
                             (pos_g[0] - w * 0.5 + (j + 0.5) * w / float(m), pos_g[1] - h * 0.5, pos_g[2]), bevel=0.0001))
    return join_parts(name, parts)


def absf(x):
    return x if x >= 0 else -x


def add_rail(g, rail_y, z0, z1, w=0.026, mat="dark", mount_h=0.0):
    """顶部导轨(旧接口名,GDScript _rail 的对应物)。mount_h:贴合垫块高度。"""
    za = min(z0, z1)
    zb = max(z0, z1)
    return add_picatinny("TopRail", absf(zb - za), (0, rail_y, (za + zb) * 0.5),
                         width=w, mount_h=mount_h)


# ---------------------------------------------------------------- 材质

## 材质名必须与 Godot WeaponModels.MAT() 的 key 一致:Godot 侧读材质名做映射,
## 替换成项目自己的 PBR 材质,并接入 _part_material 的逐零件变体系统。
## 这里给的颜色只用于 Blender 内预览/渲染出图,Godot 不使用 GLB 里的颜色(按名字换材质)。
MAT_NAMES = ("metal", "dark", "poly", "tan", "wood", "olive", "brass",
             "chrome", "lens", "lens_clear", "scope_black", "ret_dark", "ret_light")

_MAT_RGB = {
    "metal": (0.604, 0.627, 0.659, 1.0),
    "dark": (0.353, 0.369, 0.392, 1.0),
    "poly": (0.243, 0.259, 0.282, 1.0),
    "tan": (0.690, 0.604, 0.471, 1.0),
    "wood": (0.659, 0.471, 0.282, 1.0),
    "olive": (0.416, 0.455, 0.345, 1.0),
    "brass": (0.816, 0.690, 0.439, 1.0),
    "chrome": (0.847, 0.867, 0.886, 1.0),
    "lens": (0.23, 0.42, 0.60, 0.55),
    "lens_clear": (0.55, 0.72, 0.88, 0.15),
    "scope_black": (0.018, 0.02, 0.024, 1.0),
    "ret_dark": (0.025, 0.03, 0.035, 1.0),
    "ret_light": (0.82, 0.85, 0.88, 1.0),
}

_MAT_ROUGH = {"metal": 0.45, "dark": 0.60, "poly": 0.85, "chrome": 0.18,
              "brass": 0.40, "wood": 0.75, "tan": 0.75, "olive": 0.75}
_MAT_METAL = {"metal": 0.40, "dark": 0.30, "poly": 0.05, "chrome": 0.95,
              "brass": 0.60, "wood": 0.0, "tan": 0.10, "olive": 0.15}


def set_material(ob, mat_name):
    """给对象指定材质。材质名会被写进 GLB,Godot 侧据此映射到项目材质。

    颜色仅用于 Blender 内预览/渲染出图 —— Godot 不读 GLB 里的颜色,
    而是按材质名查 WeaponModels.MAT() 替换成项目 PBR,所以这里的颜色对游戏里
    看到的画面没有影响,纯粹让我们自己确认模型"长得对不对"。

    Blender 5.x 的 EEVEE 渲染完全走节点,所以必须 node 接口;legacy 模式只对
    viewport 立即预览有效,渲染会被忽略(已踩)。"""
    if mat_name not in MAT_NAMES:
        print("  [warn] 未知材质名 %s(不在 WeaponModels.MAT 里)" % mat_name)
    mat = bpy.data.materials.get(mat_name)
    if mat is None:
        mat = bpy.data.materials.new(name=mat_name)
    mat.use_nodes = True
    nt = mat.node_tree
    # 找/创建 Principled BSDF(默认材质可能没有,Blender 5 某些版本默认走更简化的 node 树)
    bsdf = None
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            bsdf = n
            break
    if bsdf is None:
        # 清空默认节点,重铺一个最小可用图
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        out.location = (300, 0)
        nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    if mat_name in _MAT_RGB:
        r, g, b, a = _MAT_RGB[mat_name]
        bsdf.inputs['Base Color'].default_value = (r, g, b, a)
        # diffuse_color 给 WorkBench 引擎直接读取(不走 PBR,只用作色块预览)
        mat.diffuse_color = (r, g, b, a)
        # 自发光保底:无论场景光照/材 metal/roughness 怎么影响,都能一眼看到材质颜色。
        # 这里只是给 Blender 内部预览用,不影响 GLB 出口。
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = (r * 0.35, g * 0.35, b * 0.35, 1.0)
        if 'Emission Strength' in bsdf.inputs:
            bsdf.inputs['Emission Strength'].default_value = 0.5
    bsdf.inputs['Roughness'].default_value = _MAT_ROUGH.get(mat_name, 0.6)
    bsdf.inputs['Metallic'].default_value = _MAT_METAL.get(mat_name, 0.3)
    if len(ob.data.materials) == 0:
        ob.data.materials.append(mat)
    else:
        ob.data.materials[0] = mat
    return ob


def apply_materials(rules, default="metal"):
    """
    按规则批量分配材质。rules 为 [(名字或前缀, 材质名), ...],按顺序匹配,先命中先应用。
    不传 default 时用 metal。
    """
    n = 0
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        picked = default
        for key, mname in rules:
            if ob.name == key or ob.name.startswith(key):
                picked = mname
                break
        set_material(ob, picked)
        n += 1
    return n


# ---------------------------------------------------------------- 导出

def export_glb(path, apply_mods=True):
    # gltf exporter 读的是 matrix_world(depsgraph 惰性求值)。建模末段对
    # location 的直接赋值(parent_to/本地坐标覆盖)不刷新就不会进导出结果 ——
    # gl 膛体位置改了但 GLB 纹丝不动的根因。导出前强制求值一次。
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_apply=apply_mods,
        export_yup=True,
    )
    return path


def stats():
    """统计场景:对象数 / 总面数 —— 用来盯性能预算。"""
    verts = 0
    tris = 0
    objs = 0
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        objs += 1
        me = o.data
        verts += len(me.vertices)
        tris += len(me.polygons)
    return objs, verts, tris
