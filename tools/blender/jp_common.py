"""
秋津市地图公共库(tools/blender/jp_common.py)
基于 gunforge 的 Godot 语义坐标系 —— 所有 API 接受 Godot 系:
  位置 (x 东, y 高度, z 北) / 尺寸 (宽 w, 高 h, 深 d) / 旋转绕 Godot 轴。
GLB 导入 Godot 后逐轴自动对齐(枪械管线 55 把实证, 勿改轴向)。

zone 组织:
  * 视觉件 join 成单一多材质槽网格(Godot 按材质名重贴 PBR)
  * 碰撞 = col_* Empty 节点(scale 即尺寸, Godot 端读 transform 建 AABB, 零 mesh 开销)
  * 可行走面 = walk_* Empty 节点(同上; Godot 端烘进 floor_h 高度场)
  * Empty 的 scale 分量导出后在 Godot 端语义为 (x 宽, y 高, z 深)

硬性规则(jp_city_design.md §11):
  * 铺装 slab 厚 <=0.05m, 不倒角, 不出 col
  * 实心体一律走 solid()/wall_*() 自动出 col; 旋转装饰件手动 col 轴对齐盒
  * 楼梯每级出 walk Empty(高差 <=0.3m)
  * 材质名必须在 ZMAT 表内(Godot 端 PropModels 同名注册)
"""
import sys, os, math
import bpy
import bmesh          # 模块级:bmesh 建网函数(零 bpy.ops 构件)在闭包里也要用

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import (  # noqa
    reset, g2b, gsz, rot_g2b, add_bevel, add_box, add_cyl, add_torus,
    cut, union, join_parts, parent_to, add_empty, export_glb, stats,
)


# ============================================================ 零 bpy.ops 快速构件
# 2026-09-10 实测: bpy.ops 每次调用都触发全场景依赖图更新, 单件成本随场景物体数
# **线性增长** -> 数千件的 Z9(bpy.ops 建盒 3~4 次/件 + col/walk 各 1 次 empty_add)
# 实际是 O(n^2), 实测 15 分钟跑不完。以下用纯数据 API(bmesh / bpy.data)创建,
# 单件成本恒定(~0.1ms, 与场景规模无关)。倒角改为"留修改器", 由
# export_glb(apply_mods=True) 在导出时统一应用, 不再逐件 modifier_apply。
_BOX_UV4 = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))


def fastbox(name, size_g, pos_g, bevel=0.0, bevel_seg=2, rot_g=None):
    """盒子(零 bpy.ops)。Godot 尺寸直接烘进顶点, 免 transform_apply。
    与 gunforge.add_box 的几何/材质槽语义完全一致(仅创建方式不同)。"""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = float(size_g[0]), float(size_g[2]), float(size_g[1])
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    uvl = bm.loops.layers.uv.new("UVMap")           # primitive_cube_add 同样带 UVMap
    for f in bm.faces:
        for i, lp in enumerate(f.loops):
            lp[uvl].uv = _BOX_UV4[i % 4]
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = g2b(pos_g)
    if rot_g is not None:
        ob.rotation_euler = rot_g2b(rot_g)
    if bevel and bevel > 0.0:
        m = ob.modifiers.new(name="bevel", type='BEVEL')
        m.width = bevel
        m.segments = bevel_seg
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(60)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def fast_empty(name, size_g, pos_g):
    """Empty 节点(零 bpy.ops), scale=尺寸。col_/walk_ 用。"""
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = 'PLAIN_AXES'
    ob.location = g2b(pos_g)
    ob.scale = gsz(size_g)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# 覆盖 gunforge.add_box:本模块(含 build_jp_city 的 from jp_common import add_box)
# 所有调用点自动走快速路径。枪械管线不受影响(它直接 import gunforge)。
add_box = fastbox

# 全局倒角缩放。0 = 关闭倒角。批量填充楼(通用盒子, 航拍尺度看不到 2cm 倒角)会把
# 它设 0, 单区面数直接砍半 —— 倒角让每个盒子从 12 面变 108 面。
BEVEL_SCALE = 1.0

# ============================================================ 材质
# 材质名 -> Blender 预览 RGB(渲染验收用; Godot 端 PropModels 按名注册真 PBR)
ZMAT = {
    "asphalt":    (0.235, 0.243, 0.259, 1.0),   # 雨后沥青(rough 0.35)
    "asphalt_w":  (0.32, 0.33, 0.35, 1.0),      # 人行道沥青
    "paint_w":    (0.84, 0.84, 0.80, 1.0),      # 斑马线/标线
    "paint_y":    (0.78, 0.65, 0.16, 1.0),
    "vermilion":  (0.72, 0.20, 0.12, 1.0),      # 朱红(鸟居/社殿)
    "roof_tile":  (0.23, 0.26, 0.31, 1.0),      # 青灰和瓦
    "plaster":    (0.86, 0.85, 0.79, 1.0),      # 白灰墙
    "concrete":   (0.60, 0.59, 0.55, 1.0),
    "concrete_d": (0.47, 0.47, 0.44, 1.0),
    "stone":      (0.54, 0.53, 0.49, 1.0),
    "stone_d":    (0.37, 0.36, 0.33, 1.0),
    "brick":      (0.54, 0.29, 0.22, 1.0),
    "wood_b":     (0.42, 0.30, 0.19, 1.0),      # 木造棕
    "wood_d":     (0.29, 0.22, 0.15, 1.0),
    "glass":      (0.48, 0.60, 0.66, 0.45),     # 幕墙(半透)
    "metal":      (0.48, 0.50, 0.53, 1.0),
    "metal_d":    (0.24, 0.26, 0.28, 1.0),
    "rust":       (0.54, 0.35, 0.20, 1.0),
    "cherry":     (0.88, 0.62, 0.72, 1.0),      # 樱
    "leaf":       (0.29, 0.44, 0.22, 1.0),
    "leaf_pine":  (0.18, 0.31, 0.19, 1.0),
    "bark":       (0.29, 0.21, 0.13, 1.0),
    "water":      (0.16, 0.29, 0.37, 1.0),
    "sand":       (0.78, 0.72, 0.56, 1.0),
    "sandbag":    (0.60, 0.54, 0.38, 1.0),
    "grass":      (0.35, 0.47, 0.26, 1.0),
    "soda_red":   (0.75, 0.16, 0.16, 1.0),
    "soda_blue":  (0.16, 0.35, 0.75, 1.0),
    "sign_r":     (0.75, 0.19, 0.16, 1.0),
    "sign_b":     (0.16, 0.35, 0.66, 1.0),
    "sign_g":     (0.16, 0.47, 0.28, 1.0),
    "sign_o":     (0.82, 0.47, 0.16, 1.0),
    "taxi_y":     (0.85, 0.65, 0.10, 1.0),
    # 日语标识(UV 图集;引擎端 PropModels 同名注册真贴图)
    "sign_jp_shop":   (0.90, 0.88, 0.84, 1.0),
    "sign_jp_ad":     (0.86, 0.90, 0.96, 1.0),
    "sign_jp_notice": (0.94, 0.92, 0.86, 1.0),
    "sign_jp_road":   (0.90, 0.93, 0.90, 1.0),
    "sign_jp_banner": (0.92, 0.86, 0.82, 1.0),
    "jp_flyer":       (0.84, 0.82, 0.76, 1.0),
    "sign_back":      (0.30, 0.32, 0.35, 1.0),
    "sign_pole":      (0.50, 0.52, 0.55, 1.0),      # 出租车黄
    "dark_opening":   (0.045, 0.05, 0.06, 1.0),     # 洞口/隧道的纯暗面
    "lamp_warm":      (1.0, 0.86, 0.62, 1.0),       # 室内吊灯(自发光)
    "sign_w":     (0.88, 0.88, 0.85, 1.0),
    "tent":       (0.35, 0.38, 0.28, 1.0),
    "rubber":     (0.10, 0.11, 0.12, 1.0),
    "lamp":       (1.00, 0.91, 0.72, 1.0),      # 纸灯笼(暖)
    "banner":     (0.85, 0.82, 0.75, 1.0),      # 幡
    "gold":       (0.78, 0.66, 0.25, 1.0),
    "dark":       (0.12, 0.12, 0.13, 1.0),
    # 室内货架/柜台面板: 浅灰哑光。旧版货架走 metal_d(#3e4248 + 金属度 0.65),
    # 室内只有单点补光, 实拍整块发黑被读作"莫名其妙的黑箱子"(用户反馈)。
    "shelf":      (0.74, 0.755, 0.74, 1.0),
}


# 标识材质 -> 贴图(Blender 预览也显示真日文, 便于渲染验收;引擎端同名注册)
SIGN_TEX = {
    "sign_jp_shop": "jp_sign_shop.png",
    "sign_jp_ad": "jp_sign_ad.png",
    "sign_jp_notice": "jp_sign_notice.png",
    "sign_jp_road": "jp_sign_road.png",
    "sign_jp_banner": "jp_sign_banner.png",
    "jp_flyer": "jp_flyer.png",
}
TEX_DIR = "E:/工作目录2/zero/steel_frontline_godot/textures"


def zmat(ob, name):
    """zone 材质: 名称写进 GLB(Godot 重贴), 颜色仅 Blender 渲染预览。
    标识类材质额外挂真贴图(UV 取格)——不然 Blender 里全是灰板, 没法验收朝向/UV。"""
    if name not in ZMAT:
        print("  [warn] 未知 zone 材质 %s" % name)
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = None
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            bsdf = n
            break
    if bsdf is None:
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        out.location = (300, 0)
        nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    r, g, b, a = ZMAT.get(name, (0.5, 0.5, 0.5, 1.0))
    bsdf.inputs['Base Color'].default_value = (r, g, b, a)
    mat.diffuse_color = (r, g, b, a)
    if name == "lamp":
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = (r, g, b, 1.0)
            bsdf.inputs['Emission Strength'].default_value = 15.0
    if name == "lamp_warm":
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = (r, g, b, 1.0)
            bsdf.inputs['Emission Strength'].default_value = 6.0
    if name in SIGN_TEX and not mat.get("sign_tex", False):
        fp = os.path.join(TEX_DIR, SIGN_TEX[name])
        if os.path.exists(fp):
            img = bpy.data.images.get(SIGN_TEX[name])
            if img is None:
                img = bpy.data.images.load(fp)
            tn = nt.nodes.new('ShaderNodeTexImage')
            tn.image = img
            tn.interpolation = 'Closest'      # 图集防渗色
            tn.location = (-420, 60)
            nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
            mat["sign_tex"] = True
    if a < 1.0:
        bsdf.inputs['Alpha'].default_value = a
        mat.blend_method = 'BLEND'
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


# ============================================================ 碰撞 / 行走面 Empty
_zone_cols = []
_zone_walks = []
# ★ 可行驶面(桥面/引道): 与 walk_ 同几何语义, 但引擎侧**单独**收集成 G.drive_boxes。
#   载具只认 drive_ 面 —— 这样载具能上桥, 却不会爬屋顶/进室内(全部 walk_ 面)。
_zone_drives = []


def _empty(name, size_g, pos_g):
    """Empty 节点, scale=尺寸(gsz 语义)。Godot 端读出 scale=(x宽, y高, z深)。
    走 fast_empty(零 bpy.ops): col/walk 每区上千个, 用 empty_add 会 O(n^2)。"""
    return fast_empty(name, size_g, pos_g)


def col(name, size_g, pos_g):
    """注册碰撞 AABB(实心体)。"""
    _zone_cols.append(_empty("col_" + name, size_g, pos_g))


def walk(name, size_g, pos_g):
    """注册可行走面(顶面 = pos_g.y + h/2)。"""
    _zone_walks.append(_empty("walk_" + name, size_g, pos_g))


def drive(name, size_g, pos_g):
    """注册**可行驶面**(桥面/引道)。步兵照走;载具只认这一组面。"""
    _zone_drives.append(_empty("drive_" + name, size_g, pos_g))


def ramp_z(name, x, w, z0, z1, y0, y1, mat="concrete", t=0.4):
    """沿 z 的**平滑坡道**(载具可行驶)。z0→z1, 高度 y0→y1。
    视觉 = 斜置厚板;行驶面 = 每 1m 一格 drive_(级差 15cm 级, 载具悬挂可吸收)。
    ★ 2026-09-10: 旧跨线桥引道用 stairs_z(25 级台阶) → 载具根本上不去。"""
    parts = []
    L = abs(z1 - z0)
    rise = y1 - y0
    ang = math.atan2(abs(rise), L)
    cz = (z0 + z1) / 2.0
    # Godot 绕 +X 转 θ: 盒长轴(+Z)→(0,-sinθ,cosθ)。要 +z 端升高 → θ = -ang
    rot = (-ang if z1 > z0 else ang, 0, 0)
    p = add_box(name, (w, t, math.hypot(L, rise) + 0.3), (x, (y0 + y1) / 2.0, cz), rot_g=rot)
    zmat(p, mat)
    parts.append(p)
    n = max(2, int(L))
    for i in range(n):
        zz = z0 + (z1 - z0) * (i + 0.5) / n
        yy = y0 + rise * (i + 0.5) / n
        # 步兵走 walk_, 载具走 drive_ —— 两组都要有, 否则"车能上人不能上"(反之亦然)
        walk("%s_d%d" % (name, i), (w, 0.08, L / n + 0.06), (x, yy - 0.04, zz))
        drive("%s_d%d" % (name, i), (w, 0.08, L / n + 0.06), (x, yy - 0.04, zz))
    return parts


# ============================================================ 基础构件
def solid(name, size_g, pos_g, mat="concrete", bev=0.02, rot=None, barrier=True):
    """实心体: 视觉盒 + 碰撞。rot 为 Godot 欧拉(y 分量为 yaw)。
    碰撞按**旋转后的 XZ 包围盒**注册 —— 旧版直接用未旋转尺寸,斜置件(车/隔离墩/帐篷)
    外侧会多出一圈看不见的直角墙。"""
    if BEVEL_SCALE != 1.0:
        bev = bev * BEVEL_SCALE
    ob = add_box(name, size_g, pos_g, bevel=bev, rot_g=rot)
    zmat(ob, mat)
    if barrier:
        w, hh, d = size_g
        if rot is not None and abs(float(rot[1])) > 1e-4:
            ca, sa = abs(math.cos(float(rot[1]))), abs(math.sin(float(rot[1])))
            w, d = w * ca + d * sa, w * sa + d * ca
        col(name, (w, hh, d), pos_g)
    return ob


def deco(name, size_g, pos_g, mat="concrete", bev=0.02, rot=None):
    """纯装饰盒(无碰撞, 如檐口饰带在 col 体内)。"""
    if BEVEL_SCALE != 1.0:
        bev = bev * BEVEL_SCALE
    ob = add_box(name, size_g, pos_g, bevel=bev, rot_g=rot)
    zmat(ob, mat)
    return ob


def slab(name, x0, x1, z0, z1, y=0.0, t=0.04, mat="asphalt"):
    """铺装面(不倒角不碰撞; 顶面 = y)。"""
    ob = add_box(name, (x1 - x0, t, z1 - z0),
                 ((x0 + x1) / 2.0, y - t / 2.0, (z0 + z1) / 2.0))
    zmat(ob, mat)
    return ob


def _segs_x(x0, x1, openings):
    """沿 x 切段: openings=[(cx, w, kind, a, b)] -> [(xa, xb, holes)]。
    洞完全出墙域则忽略, 部分出域裁剪到域内(防 cx 传错产生幽灵墙段)。"""
    cuts = [x0, x1]
    ops2 = []
    for cx, w, kind, a, b in openings:
        ca, cb = cx - w / 2.0, cx + w / 2.0
        if cb <= x0 + 0.001 or ca >= x1 - 0.001:
            continue
        ca, cb = max(ca, x0), min(cb, x1)
        ops2.append(((ca + cb) / 2.0, cb - ca, kind, a, b))
        cuts += [ca, cb]
    cuts = sorted(set(round(c, 4) for c in cuts))
    out = []
    for i in range(len(cuts) - 1):
        xa, xb = cuts[i], cuts[i + 1]
        if xb - xa < 0.01:
            continue
        holes = []
        for cx, w, kind, a, b in ops2:
            # ★ 判据(2026-09-10 实拍修正): "洞**覆盖**本段"而不是"洞严格落在段内"。
            #   旧判据 `ca > xa and cb < xb` 在**门洞与窗洞重叠**时失效: 段的边界来自
            #   两个洞的交错切分, 门洞反而"不落在段内" → 该段被当实墙整段砌死。
            #   实测 Z9 有 13 处店面门洞被砌死(玩家: "门口被挡着过不去", 且门根本
            #   不存在)。改判"洞覆盖段(1cm 容差)"后, 重叠处也按门/窗正确开洞。
            ca2, cb2 = cx - w / 2.0, cx + w / 2.0
            if ca2 <= xa + 0.01 and cb2 >= xb - 0.01:
                holes.append((cx, w, kind, a, b))
        out.append((xa, xb, holes))
    return out


def wall_x(name, x0, x1, z, t, y0, y1, mat="concrete", doors=(), windows=(), bev=0.02):
    """沿 x 的墙(中心线 z, 厚 t)。doors=[(cx,w,h)] 门洞; windows=[(cx,w,sill,head)]。
    每段自动 col; 返回视觉件列表。"""
    parts = []
    ops = [(d[0], d[1], "door", y0, y0 + d[2]) for d in doors] + \
          [(w[0], w[1], "win", y0 + w[2], y0 + w[3]) for w in windows]
    cy = (y0 + y1) / 2.0
    ch = y1 - y0
    for i, (xa, xb, holes) in enumerate(_segs_x(x0, x1, ops)):
        seg_cx, seg_w = (xa + xb) / 2.0, xb - xa
        if not holes:
            parts.append(solid("%s_s%d" % (name, i), (seg_w, ch, t),
                               (seg_cx, cy, z), mat, bev))
        else:
            h = holes[0]
            cx, w, kind, ha, hb = h
            if kind == "door":
                if y1 - hb > 0.02:
                    parts.append(solid("%s_s%d_t" % (name, i), (seg_w, y1 - hb, t),
                                       (seg_cx, (hb + y1) / 2.0, z), mat, bev))
            else:  # win
                if ha - y0 > 0.02:
                    parts.append(solid("%s_s%d_b" % (name, i), (seg_w, ha - y0, t),
                                       (seg_cx, (y0 + ha) / 2.0, z), mat, bev))
                if y1 - hb > 0.02:
                    parts.append(solid("%s_s%d_t" % (name, i), (seg_w, y1 - hb, t),
                                       (seg_cx, (hb + y1) / 2.0, z), mat, bev))
    return parts


def wall_z(name, z0, z1, x, t, y0, y1, mat="concrete", doors=(), windows=(), bev=0.02):
    """沿 z 的墙(中心线 x)。参数语义同 wall_x。"""
    parts = []
    ops = [(d[0], d[1], "door", y0, y0 + d[2]) for d in doors] + \
          [(w[0], w[1], "win", y0 + w[2], y0 + w[3]) for w in windows]
    cy = (y0 + y1) / 2.0
    ch = y1 - y0
    for i, (za, zb, holes) in enumerate(_segs_x(z0, z1, ops)):
        seg_cz, seg_w = (za + zb) / 2.0, zb - za
        if not holes:
            parts.append(solid("%s_s%d" % (name, i), (t, ch, seg_w),
                               (x, cy, seg_cz), mat, bev))
        else:
            h = holes[0]
            cz, w, kind, ha, hb = h
            if kind == "door":
                if y1 - hb > 0.02:
                    parts.append(solid("%s_s%d_t" % (name, i), (t, y1 - hb, seg_w),
                                       (x, (hb + y1) / 2.0, seg_cz), mat, bev))
            else:
                if ha - y0 > 0.02:
                    parts.append(solid("%s_s%d_b" % (name, i), (t, ha - y0, seg_w),
                                       (x, (y0 + ha) / 2.0, seg_cz), mat, bev))
                if y1 - hb > 0.02:
                    parts.append(solid("%s_s%d_t" % (name, i), (t, y1 - hb, seg_w),
                                       (x, (hb + y1) / 2.0, seg_cz), mat, bev))
    return parts


def stairs_x(name, x0, x1, z, w, y0, y1, mat="concrete", up_dir="+x"):
    """沿 x 的台阶: 视觉台阶 + 每级 walk Empty。up_dir 指向高处。"""
    n = max(2, int(round(abs(y1 - y0) / 0.18)))
    sh = (y1 - y0) / n
    depth = abs(x1 - x0) / n
    parts = []
    for i in range(n):
        if up_dir == "+x":
            xi = x0 + depth * (i + 0.5)
        else:
            xi = x1 - depth * (i + 0.5)
        top = y0 + sh * (i + 1)
        parts.append(solid("%s_t%d" % (name, i), (depth, top - y0, w),
                           (xi, (y0 + top) / 2.0, z), mat, bev=0.0))
        walk("%s_t%d" % (name, i), (depth, 0.08, w), (xi, top - 0.04, z))
    return parts


def stairs_z(name, z0, z1, x, w, y0, y1, mat="concrete", up_dir="+z"):
    n = max(2, int(round(abs(y1 - y0) / 0.18)))
    sh = (y1 - y0) / n
    depth = abs(z1 - z0) / n
    parts = []
    for i in range(n):
        zi = z0 + depth * (i + 0.5) if up_dir == "+z" else z1 - depth * (i + 0.5)
        top = y0 + sh * (i + 1)
        parts.append(solid("%s_t%d" % (name, i), (w, top - y0, depth),
                           (x, (y0 + top) / 2.0, zi), mat, bev=0.0))
        walk("%s_t%d" % (name, i), (w, 0.08, depth), (x, top - 0.04, zi))
    return parts


def floor_slab(name, x0, x1, z0, z1, y, t=0.22, mat="concrete", walkable=True):
    """楼板/平台(结构厚板): 视觉 + col(挡子弹) + walk(顶面=y)。"""
    cx, cz = (x0 + x1) / 2.0, (z0 + z1) / 2.0
    parts = [solid(name, (x1 - x0, t, z1 - z0), (cx, y - t / 2.0, cz), mat, bev=0.01)]
    if walkable:
        walk(name, (x1 - x0, 0.08, z1 - z0), (cx, y - 0.04, cz))
    return parts


def parapet(name, x0, x1, z0, z1, y, h=0.9, t=0.18, mat="concrete", gap=None):
    """女儿墙(四边, 用于屋顶平台)。gap=(边'N'/'S'/'W'/'E', 中心坐标, 宽) 在该边留缺口。"""
    def _edge(tag, horiz, lo, hi, fix, along_z):
        """horiz=True 时该边沿 x 走(lo/hi 为 x)。返回该边的 1~2 段 solid。"""
        segs = [(lo, hi)]
        if gap is not None and str(gap[0]) == tag:
            gc, gw = float(gap[1]), float(gap[2])
            segs = [(lo, gc - gw / 2.0), (gc + gw / 2.0, hi)]
        out = []
        for si, (a, b) in enumerate(segs):
            if b - a <= 0.25:
                continue
            ln = b - a
            c = (a + b) / 2.0
            if horiz:
                out.append(solid("%s_%s%d" % (name, tag, si), (ln, h, t),
                                 (c, y + h / 2.0, fix), mat, bev=0.01))
            else:
                out.append(solid("%s_%s%d" % (name, tag, si), (t, h, ln),
                                 (fix, y + h / 2.0, c), mat, bev=0.01))
        return out

    parts = []
    if x1 - x0 > 0.4:
        parts += _edge("N", True, x0, x1, z0 + t / 2.0, False)
        parts += _edge("S", True, x0, x1, z1 - t / 2.0, False)
    if z1 - z0 > 0.4:
        parts += _edge("W", False, z0, z1, x0 + t / 2.0, True)
        parts += _edge("E", False, z0, z1, x1 - t / 2.0, True)
    return parts


def gable_roof(name, x0, x1, z0, z1, eave_y, ridge_h, mat="roof_tile",
               overhang=0.4, barrier=True):
    """双坡顶(脊沿 x, 即正面看是"人"字形)。视觉斜坡 x2 + 正脊; col = 整体罩盒(挡子弹)。

    ★ 坡向定标(2026-09-10 实拍修正):两坡必须**由檐口向中脊升起**(∧)。
      旧版 rot_g 用了 (-s*ang):Godot 绕 +X 转 θ 时板的长轴(+Z)朝 (0,-sinθ,cosθ) ——
      取 -ang 会让两坡"由中脊向檐口下降"变成 V 形谷, 正脊浮在谷底上方(用户: 所有屋顶
      都是 V 字形)。因两坡互为镜像, 符号整体取反即可把 V 翻成 ∧。
    """
    parts = []
    cx, cz = (x0 + x1) / 2.0, (z0 + z1) / 2.0
    W, D = x1 - x0 + overhang * 2, z1 - z0 + overhang * 2
    half = D / 2.0
    rise = ridge_h - eave_y
    slope_len = math.sqrt(half * half + rise * rise) + 0.1
    ang = math.atan2(rise, half)
    for s in (-1, 1):
        czp = cz + s * half / 2.0
        my = (eave_y + ridge_h) / 2.0
        p = add_box("%s_p%d" % (name, 1 if s > 0 else 0),
                    (W, 0.12, slope_len), (cx, my, czp), rot_g=(s * ang, 0, 0))
        zmat(p, mat)
        parts.append(p)
    parts.append(deco("%s_ridge" % name, (W + 0.2, 0.16, 0.3), (cx, ridge_h + 0.04, cz), mat))
    if barrier:
        col(name, (W, ridge_h - eave_y + 0.4, D), (cx, (eave_y + ridge_h) / 2.0, cz))
    return parts


def flat_roof(name, x0, x1, z0, z1, y, mat="concrete", walkable=False, parapet_h=0.9,
              gap=None):
    """平顶: 板 + 女儿墙; walkable 时顶面可行走。
    gap=(边, 中心坐标, 宽) 在女儿墙上留缺口 —— 外置钢梯落点必须留, 否则
    爬到顶被女儿墙挡死(2026-09-10 实拍: Z4 公寓屋顶爬梯上不去)。"""
    parts = []
    cx, cz = (x0 + x1) / 2.0, (z0 + z1) / 2.0
    t = 0.25
    parts.append(solid(name, (x1 - x0, t, z1 - z0), (cx, y - t / 2.0, cz), mat, bev=0.01))
    if walkable:
        walk(name, (x1 - x0, 0.08, z1 - z0), (cx, y - 0.04, cz))
    if parapet_h > 0:
        parts += parapet(name + "_pp", x0, x1, z0, z1, y, parapet_h, gap=gap)
    return parts


# ============================================================ 日本街道构件
def torii(name, x, z, h=8.0, span=6.0, rot90=False):
    """鸟居。rot90=False: 两柱沿 x 分布(行人沿 z 穿过); True: 两柱沿 z(行人沿 x 穿过)。"""
    parts = []
    r = max(0.28, h * 0.045)

    def P(dx, dz):
        return (x + dz, z + dx) if rot90 else (x + dx, z + dz)

    def S(nm, w, hh, d, px, py, pz, m="vermilion", bev=0.02, rot=None):
        """梁件:rot90 时交换 x/z 尺寸,使梁沿柱列方向延伸(否则梁横穿柱子)。"""
        if rot90:
            w, d = d, w
        ob = add_box(nm, (w, hh, d), (px, py, pz), bevel=bev, rot_g=rot)
        zmat(ob, m)
        return ob

    for s in (0, 1):
        sx = -1 if s == 0 else 1
        px, pz = P(sx * span / 2.0, 0)
        parts.append(solid("%s_p%d" % (name, s), (r * 2, h * 0.92, r * 2),
                           (px, h * 0.46, pz), "vermilion", bev=0.03))
        parts.append(deco("%s_k%d" % (name, s), (r * 2.5, h * 0.10, r * 2.5),
                          (px, h * 0.05, pz), "stone_d"))
    # 贯(下梁)
    px, pz = P(0, 0)
    parts.append(S("%s_nuki" % name, span + r * 2 + 0.6, 0.28, 0.24, px, h * 0.78, pz))
    # 额束(鸟居中央小方木)
    parts.append(S("%s_gaku" % name, 0.5, 0.5, 0.18, px, h * 0.895, pz, "wood_d"))
    # 笠木(上梁 + 两端上挑)
    top_y = h * 1.0
    parts.append(S("%s_kasagi" % name, span + r * 2 + 1.6, 0.34, 0.42, px, top_y, pz, bev=0.03))
    for s in (-1, 1):
        tx, tz = P(s * (span / 2.0 + r + 0.55), 0)
        tip = S("%s_tip%d" % (name, 1 if s > 0 else 0),
                span * 0.22, 0.30, 0.40, tx, top_y - 0.10, tz, bev=0.03)
        # 端部上挑:梁沿 z 时绕 Godot X 抬头,梁沿 x 时绕 Godot Z 抬头
        if rot90:
            tip.rotation_euler = rot_g2b((-s * 0.14, 0, 0))
        else:
            tip.rotation_euler = rot_g2b((0, 0, -s * 0.14))
        tip.location.z += 0.06
        parts.append(tip)
    parts.append(S("%s_shimaki" % name, span + r * 2 + 1.0, 0.16, 0.30, px, top_y - 0.22, pz))
    # 碰撞: 两柱(竖直罩盒) + 横梁高区(玩家从梁下穿过, 梁区罩盒挡子弹)
    for s in (0, 1):
        sx = -1 if s == 0 else 1
        cpx, cpz = P(sx * span / 2.0, 0)
        col("%s_c%d" % (name, s), (r * 2.6, h, r * 2.6), (cpx, h / 2.0, cpz))
    lw = span + r * 2 + 1.6
    lpx, lpz = P(0, 0)
    col("%s_beam" % name,
        (lw, h * 0.30, 0.6) if not rot90 else (0.6, h * 0.30, lw),
        (lpx, h * 0.85, lpz))
    return parts


def stone_lantern(name, x, z, h=1.7):
    """石灯笼(六段)。col 一个罩盒。"""
    parts = []
    parts.append(deco(name + "_base", (0.66, 0.16, 0.66), (x, 0.08, z), "stone_d"))
    parts.append(add_cyl(name + "_pole", 0.10, h * 0.32, (x, h * 0.30, z), axis="y", seg=8))
    zmat(parts[-1], "stone")
    parts.append(deco(name + "_mid", (0.42, 0.10, 0.42), (x, h * 0.48, z), "stone"))
    parts.append(deco(name + "_fire", (0.30, 0.30, 0.30), (x, h * 0.64, z), "stone_d"))
    hood = add_cyl(name + "_hood", 0.34, 0.16, (x, h * 0.83, z), axis="y", seg=8, taper=0.35)
    zmat(hood, "stone")
    parts.append(hood)
    ball = add_cyl(name + "_orb", 0.09, 0.16, (x, h * 0.95, z), axis="y", seg=8)
    zmat(ball, "stone")
    parts.append(ball)
    col(name, (0.62, h, 0.62), (x, h / 2.0, z))
    return parts


def tree_cherry(name, x, z, h=4.2, r=2.0):
    parts = []
    parts.append(add_cyl(name + "_trunk", 0.14, h * 0.55, (x, h * 0.28, z), axis="y", seg=8, taper=0.7))
    zmat(parts[-1], "bark")
    for i, (dx, dz, rr) in enumerate([(0.5, 0.3, r), (-0.6, -0.2, r * 0.8), (0.1, -0.6, r * 0.7)]):
        s = bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1, radius=rr, location=g2b((x + dx, h * 0.72 + i * 0.35, z + dz)))
        ob = bpy.context.active_object
        ob.name = "%s_c%d" % (name, i)
        ob.scale = gsz((1.0, 0.8, 1.0))
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        zmat(ob, "cherry")
        parts.append(ob)
    col(name, (r * 1.4, h, r * 1.4), (x, h / 2.0, z))
    return parts


def tree_pine(name, x, z, h=5.0):
    parts = []
    parts.append(add_cyl(name + "_trunk", 0.18, h * 0.45, (x, h * 0.22, z), axis="y", seg=8, taper=0.75))
    zmat(parts[-1], "bark")
    for i, (yy, rr) in enumerate([(h * 0.42, 1.9), (h * 0.62, 1.5), (h * 0.82, 1.0)]):
        s = bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1, radius=rr, location=g2b((x, yy, z)))
        ob = bpy.context.active_object
        ob.name = "%s_c%d" % (name, i)
        ob.scale = gsz((1.0, 0.42, 1.0))
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        zmat(ob, "leaf_pine")
        parts.append(ob)
    col(name, (1.2, h, 1.2), (x, h / 2.0, z))
    return parts


def tree_cedar(name, x, z, h=7.0):
    parts = []
    parts.append(add_cyl(name + "_trunk", 0.22, h * 0.4, (x, h * 0.2, z), axis="y", seg=8))
    zmat(parts[-1], "bark")
    cone = add_cyl(name + "_crown", 1.6, h * 0.75, (x, h * 0.55, z), axis="y", seg=8, taper=0.12)
    zmat(cone, "leaf_pine")
    parts.append(cone)
    col(name, (1.2, h, 1.2), (x, h / 2.0, z))
    return parts


# ============================================================ 行道树(零 bpy.ops)
# 上面三个 tree_* 走 bpy.ops.mesh.primitive_ico_sphere_add。bpy.ops 在已含数千物体的
# 场景里是超线性的(实测 1000+ 物体时 ~139ms/次),全图铺几百棵会把构建拖到十分钟级。
# 下列函数直接 bmesh 建网格 + bpy.data.objects.new(与 fastbox 同路子),故单独一套。
def _fast_geo(name, mat, pos_g, build, squash_y=1.0):
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    for v in bm.verts:
        v.co.z *= float(squash_y)          # 局部 z = Godot 高度(与 fastbox 同约定)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = g2b(pos_g)
    bpy.context.scene.collection.objects.link(ob)
    zmat(ob, mat)
    return ob


def _fast_ico(name, r, x, y, z, mat, squash_y=1.0, seg=1):
    """低模球冠。squash_y = 沿 Godot 高度方向压扁。"""
    def _b(bm):
        bmesh.ops.create_icosphere(bm, subdivisions=int(seg), radius=float(r))
    return _fast_geo(name, mat, (x, y, z), _b, squash_y)


def _fast_prism(name, r, h, x, y, z, mat, seg=8, taper=1.0):
    """竖直棱柱(轴 = Godot 高度)。"""
    def _b(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=int(seg),
                              radius1=float(r), radius2=float(r) * float(taper),
                              depth=float(h))
    return _fast_geo(name, mat, (x, y, z), _b, 1.0)


def fast_tree(name, x, z, kind="cherry", h=4.2, r=2.0, col_r=0.5):
    """行道树:树干棱柱 + 2~3 球冠。col_r = 碰撞半径(默认只挡树干,
    行道树用细碰撞箱才不会堵人行道/擦到车;园区树由 tree_cherry 等负责大碰撞)。"""
    P = []
    if kind == "pine":
        P.append(_fast_prism(name + "_trunk", 0.18, h * 0.45, x, h * 0.22, z, "bark", 8, 0.78))
        for i, (yy, rr) in enumerate(((h * 0.42, r * 0.95), (h * 0.62, r * 0.75),
                                      (h * 0.82, r * 0.50))):
            P.append(_fast_ico("%s_c%d" % (name, i), rr, x, yy, z, "leaf_pine", 0.42))
    elif kind == "cedar":
        P.append(_fast_prism(name + "_trunk", 0.22, h * 0.40, x, h * 0.20, z, "bark", 8, 1.0))
        P.append(_fast_prism(name + "_crown", r * 0.8, h * 0.78, x, h * 0.56, z,
                             "leaf_pine", 8, 0.12))
    else:                                       # cherry
        P.append(_fast_prism(name + "_trunk", 0.14, h * 0.55, x, h * 0.28, z, "bark", 8, 0.72))
        for i, (dx, dz, rr) in enumerate(((0.50, 0.30, r), (-0.60, -0.20, r * 0.80),
                                          (0.10, -0.60, r * 0.70))):
            P.append(_fast_ico("%s_c%d" % (name, i), rr, x + dx, h * 0.72 + i * 0.35,
                               z + dz, "cherry", 0.82))
    col(name, (col_r * 2.0, h, col_r * 2.0), (x, h * 0.5, z))
    return P


def vending_machine(name, x, z, rot=0.0, kind="soda_red"):
    """自动售货机(1.0 x 1.83 x 0.75)。rot= 绕竖直轴偏航(度)。col 罩盒按朝向放大。"""
    parts = []
    r = math.radians(rot)
    body = add_box(name + "_body", (1.0, 1.83, 0.75), (x, 0.915, z), bevel=0.03, rot_g=(0, r, 0))
    zmat(body, kind)
    parts.append(body)
    cw, cd = 1.0, 0.75
    rr = abs(math.sin(r)) * cw + abs(math.cos(r)) * cd
    rx = abs(math.cos(r)) * cw + abs(math.sin(r)) * cd
    col(name, (rx + 0.1, 1.83, rr + 0.1), (x, 0.915, z))
    return parts


def utility_pole(name, x, z, h=8.5, trafo=False):
    """电线杆(水泥锥形杆 + 横担 + 变压器)。col 杆。"""
    parts = []
    pole = add_cyl(name + "_pole", 0.17, h, (x, h / 2.0, z), axis="y", seg=8, taper=0.72)
    zmat(pole, "concrete")
    parts.append(pole)
    for i, yy in enumerate([h * 0.86, h * 0.93]):
        parts.append(solid("%s_arm%d" % (name, i), (0.10, 0.10, 2.4), (x, yy, z), "metal_d", bev=0.01))
    if trafo:
        parts.append(solid(name + "_trafo", (0.7, 0.9, 0.6), (x, h * 0.70, z + 0.5), "metal_d", bev=0.02))
    col(name, (0.36, h, 0.36), (x, h / 2.0, z))
    return parts


def wire_x(name, x0, x1, z, y, sag=0.35, segs=6):
    """电线(沿 x, 悬链近似折线, 细条 0.03)。纯视觉。"""
    parts = []
    for i in range(segs):
        xa = x0 + (x1 - x0) * i / segs
        xb = x0 + (x1 - x0) * (i + 1) / segs
        t0, t1 = i / segs, (i + 1) / segs
        y0 = y - sag * 4 * t0 * (1 - t0)
        y1 = y - sag * 4 * t1 * (1 - t1)
        ym = y - sag * 4 * ((t0 + t1) / 2.0) * (1 - (t0 + t1) / 2.0)
        mid = add_box("%s_%d" % (name, i), (abs(xb - xa), 0.03, 0.03),
                      ((xa + xb) / 2.0, (y0 + y1 + 2 * ym) / 4.0, z))
        ang = math.atan2(y1 - y0, xb - xa)
        mid.rotation_euler = rot_g2b((0, 0, ang))
        zmat(mid, "dark")
        parts.append(mid)
    return parts


def street_lamp(name, x, z, h=5.2, rot_z=0.0):
    parts = []
    pole = add_cyl(name + "_pole", 0.09, h, (x, h / 2.0, z), axis="y", seg=8, taper=0.8)
    zmat(pole, "metal_d")
    parts.append(pole)
    arm_len = 1.6
    arm = add_box(name + "_arm", (arm_len, 0.08, 0.08),
                  (x + math.cos(rot_z) * arm_len / 2.0, h - 0.1,
                   z - math.sin(rot_z) * arm_len / 2.0))
    arm.rotation_euler = rot_g2b((0, 0, rot_z))
    zmat(arm, "metal_d")
    parts.append(arm)
    head = add_box(name + "_head", (0.55, 0.14, 0.24),
                   (x + math.cos(rot_z) * arm_len, h - 0.2, z - math.sin(rot_z) * arm_len),
                   bevel=0.02)
    zmat(head, "lamp")
    parts.append(head)
    col(name, (0.24, h, 0.24), (x, h / 2.0, z))
    return parts


def guardrail_x(name, x0, x1, z, y=0.0):
    """波形护栏(沿 x)。col 低盒。"""
    parts = [solid(name + "_rail", (x1 - x0, 0.36, 0.06), ((x0 + x1) / 2.0, y + 0.55, z), "metal", bev=0.01)]
    n = max(2, int((x1 - x0) / 4.0))
    for i in range(n + 1):
        px = x0 + (x1 - x0) * i / n
        parts.append(add_cyl("%s_p%d" % (name, i), 0.06, 0.62, (px, y + 0.31, z), axis="y", seg=6))
        zmat(parts[-1], "metal_d")
    col(name, (x1 - x0, 0.75, 0.14), ((x0 + x1) / 2.0, y + 0.375, z))
    return parts


def jersey_barrier(name, x, z, length=2.0, rot=0.0):
    """水泥隔离墩(梯形简化)。"""
    parts = [solid(name, (length, 0.85, 0.55), (x, 0.425, z), "concrete", bev=0.04, rot=(0, 0, rot))]
    return parts


def sandbag_wall(name, x, z, length=3.0, rot=0.0, h=1.05):
    """沙袋垒(2 层错位)。col 罩盒。"""
    parts = []
    n = max(2, int(length / 0.55))
    for row in range(2):
        for i in range(n - row % 2):
            bx = x + (i - (n - 1) / 2.0 + 0.14 * row) * 0.55
            bag = add_box("%s_%d_%d" % (name, row, i), (0.52, 0.34, 0.42),
                          (bx, 0.19 + row * 0.36, z), bevel=0.04)
            bag.rotation_euler = rot_g2b((0, 0, rot))
            zmat(bag, "sand" if False else "sandbag")
            # sandbag 材质 Godot 端已有(sand_01 贴图)
            parts.append(bag)
    cw = abs(math.cos(rot)) * length + abs(math.sin(rot)) * 0.6
    cd = abs(math.sin(rot)) * length + abs(math.cos(rot)) * 0.6
    col(name, (cw, h, cd), (x, h / 2.0, z))
    return parts


def wreck_car(name, x, z, rot=0.0, mat="rust"):
    """废弃车(简化轿车, 缺轮)。col 罩盒。"""
    parts = []
    parts.append(solid(name + "_body", (4.4, 0.55, 1.75), (x, 0.55, z), mat, bev=0.12, rot=(0, 0, rot)))
    parts.append(solid(name + "_cabin", (2.2, 0.55, 1.6), (x - 0.2, 1.1, z), mat, bev=0.10, rot=(0, 0, rot)))
    # 瘪轮
    for sx, sy in ((1.45, 0.85), (1.45, -0.85), (-1.45, 0.85), (-1.45, -0.85)):
        w = add_cyl("%s_w%d_%d" % (name, sx, sy), 0.3, 0.22, (x, 0.3, z), axis="y", seg=10)
        w.location = g2b((x + math.cos(rot) * sx - math.sin(rot) * sy, 0.3,
                          z + math.sin(rot) * sx + math.cos(rot) * sy))
        zmat(w, "rubber")
        parts.append(w)
    return parts


def sign_board(name, x, z, y, w, h, rot=0.0, kind="sign_b"):
    """店铺招牌(立牌/壁牌)。纯视觉(col 由建筑承担)。"""
    b = add_box(name, (w, h, 0.12), (x, y, z), bevel=0.02, rot_g=(0, 0, rot))
    zmat(b, kind)
    return [b]


def noren(name, x, z, y, w, h=0.55, rot=0.0, kind="sign_b"):
    """暖帘(门帘横幅)。"""
    b = add_box(name, (w, h, 0.03), (x, y, z), rot_g=(0, 0, rot))
    zmat(b, kind)
    return [b]


# ============================================================ zone 导出 / 渲染
def bake_modifiers(objs):
    """把修改器(倒角)烘进网格。**join 会丢弃非活动对象的修改器**, 所以必须在 join
    前烘。用 depsgraph 求值 + new_from_object —— 纯数据 API, 一次性 O(场景),
    等价于逐个 modifier_apply 但快几个数量级(fastbox 建出的件全是修饰器倒角)。
    """
    pend = [o for o in objs if o is not None and getattr(o, "data", None) is not None
            and o.type == 'MESH' and len(o.modifiers) > 0]
    if not pend:
        return 0
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    for o in pend:
        ev = o.evaluated_get(deps)
        me_new = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=deps)
        me_old = o.data
        mats = [m for m in me_old.materials]
        o.modifiers.clear()
        o.data = me_new
        if len(me_new.materials) == 0 and mats:
            for m in mats:
                me_new.materials.append(m)
        if me_old.users == 0:
            bpy.data.meshes.remove(me_old)
    return len(pend)


def zone_export(zone_id, visual_parts, out_path):
    """合并视觉件 -> 打统计 -> 导出 GLB(col_/walk_ Empty 保留为独立节点)。"""
    parts = [p for p in visual_parts if p is not None]
    bake_modifiers(parts)                      # ★ join 前必须烘修饰器, 否则倒角丢失
    merged = join_parts("zone_" + zone_id, parts)
    if merged is None:
        print("[zone %s] 无视觉件!" % zone_id)
        return
    tris = 0
    for poly in merged.data.polygons:
        tris += max(1, len(poly.vertices) - 2)
    print("[zone %s] 视觉件=%d 三角面=%d col=%d walk=%d drive=%d" % (
        zone_id, len(visual_parts), tris, len(_zone_cols), len(_zone_walks), len(_zone_drives)))
    export_glb(out_path)
    print("[zone %s] 已导出 %s" % (zone_id, out_path))


# ---- 渲染(验收制) ----
def _look_at(cam, target_g):
    """相机指向 Godot 目标点(手动构造旋转, 避开 to_track_quat 的 ±Y 翻滚)。
    Blender 相机看局部 -Z: forward=指向目标, right=forward×world_up, 矩阵列=(right,up,back)。"""
    import mathutils
    tgt = mathutils.Vector(g2b(target_g))
    forward = (tgt - cam.location).normalized()
    back = -forward
    world_up = mathutils.Vector((0, 0, 1)) if abs(forward.z) < 0.98 else mathutils.Vector((0, 1, 0))
    right = forward.cross(world_up).normalized()
    up = right.cross(forward).normalized()
    m = mathutils.Matrix((right, up, back)).transposed().to_4x4()
    cam.rotation_euler = m.to_euler()


def zone_render(zone_id, center_g, radius, out_prefix, elevation=None, extra_shots=None):
    """三视图渲染: 等轴 / 俯视 / 街面(+extra_shots 附加机位)。CYCLES 48 采样。"""
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 960
    scene.render.image_settings.file_format = 'PNG'
    # 世界光
    world = bpy.data.worlds.get("zw") or bpy.data.worlds.new("zw")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.55, 0.58, 0.62, 1.0)
        bg.inputs[1].default_value = 0.9
    sun = bpy.data.lights.get("zsun") or bpy.data.lights.new("zsun", 'SUN')
    sun.energy = 2.5
    sun.angle = math.radians(12)
    sun_ob = bpy.data.objects.get("zsun_ob")
    if sun_ob is None:
        sun_ob = bpy.data.objects.new("zsun_ob", sun)
        scene.collection.objects.link(sun_ob)
    sun_ob.rotation_euler = (math.radians(50), 0, math.radians(35))
    cam_data = bpy.data.cameras.get("zcam") or bpy.data.cameras.new("zcam")
    cam_data.lens = 35
    cam_data.clip_start = 0.3
    cam_data.clip_end = 4000.0
    cam_ob = bpy.data.objects.get("zcam_ob")
    if cam_ob is None:
        cam_ob = bpy.data.objects.new("zcam_ob", cam_data)
        scene.collection.objects.link(cam_ob)
    scene.camera = cam_ob

    cx, cz = center_g[0], center_g[2]
    shots = [
        ("iso", (cx + radius * 1.25, radius * 1.05, cz - radius * 1.35), (cx, 2.0, cz)),
        ("top", (cx, radius * 2.1, cz - 0.5), (cx, 0.0, cz)),
        ("street", (cx + radius * 0.35, 1.8, cz - radius * 0.55), (cx - radius * 0.35, 2.5, cz)),
    ]
    if extra_shots:
        shots += list(extra_shots)
    for tag, pos, target in shots:
        cam_ob.location = mathutils.Vector(g2b(pos))
        _look_at(cam_ob, target)
        scene.render.filepath = "%s_%s.png" % (out_prefix, tag)
        bpy.ops.render.render(write_still=True)
        print("[render] %s_%s.png 完成" % (out_prefix, tag))



# ============================================================ 日语标识(UV 图集)
# 贴图 tools/blender/gen_jp_signs.py -> textures/jp_sign_*.png(4x4 图集,每格 256px)。
# ★ 这些面板必须走 UV 取格,引擎端材质是 uv1_triplanar=false 的专用材质。
def _sign_quad(name, w, h, cell, cols, rows):
    """直立面板:Godot 语义 宽 w(x) x 高 h(y),法线朝 +z(bt=yaw 后旋转)。UV 取图集格。"""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    hw, hh = w * 0.5, h * 0.5
    A = bm.verts.new((-hw, -hh, 0.0))
    B = bm.verts.new((hw, -hh, 0.0))
    C = bm.verts.new((hw, hh, 0.0))
    D = bm.verts.new((-hw, hh, 0.0))
    uvl = bm.loops.layers.uv.new("UVMap")
    c, r = int(cell) % cols, (int(cell) // cols) % rows
    u0, u1 = c / float(cols), (c + 1) / float(cols)
    # ★ 图集取格实测定标(_uvt3.py):Blender 的 v=0 对应 PIL 图像**底部**,
    #   故 PIL 第 r 行(v0..v1 为下缘..上缘)应取 v ∈ [(rows-1-r)/rows, (rows-r)/rows]。
    v0, v1 = (rows - 1 - r) / float(rows), (rows - r) / float(rows)
    # ★ 单面即可 —— 引擎端材质 cull_mode=CULL_DISABLED, 背面由背板(sign_back)遮挡。
    #   ★ UV 排列由 _uvt8.py 双向对照定标(明文"工事中"格, 无歧义):
    #     (A,B,C,D) = (u0,v1),(u1,v1),(u1,v0),(u0,v0) 时正读。
    #     历史坑: 试过 8 种朝向 + 双面镜像背面, 全因测试面板被画面裁切/格号数字旋转对称而误判,
    #     白排查多轮。定标必须用"明文 + 完整入画"的对照。
    # ★ V 轴定标(2026-09-10 引擎实测修正):A/B 在面板**下缘**、C/D 在上缘;
    #   原写法把 v1 给下缘、v0 给上缘,取到的"格"是对的但格内图像上下颠倒
    #   (引擎内像素相关判定:垂直翻 +0.205 ≫ 原图/水平翻/180° ≈0.12;实拍文字镜像)。
    #   改为下缘=v0、上缘=v1:v 区间不变(仍选同一格),只把格内方向摆正。
    #   ☆ 不能改在 Godot 材质端(uv1_scale/offset):那会连"格"一起换到相邻行。
    face = bm.faces.new((A, B, C, D))
    for i, lp in enumerate(face.loops):
        lp[uvl].uv = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))[i]
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)          # 立起(法线 -Y bt = +Z godot)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _panel(name, w, h, pos_g, yaw, cell, cols, rows, mat):
    ob = _sign_quad(name, w, h, cell, cols, rows)
    ob.location = g2b(pos_g)
    ob.rotation_euler = (math.pi * 0.5, 0.0, yaw)          # 绕 Blender Z(=Godot Y)偏航
    zmat(ob, mat)
    return ob


def billboard(name, x, z, y, w, h, yaw=0.0, cell=0, mat="sign_jp_ad", cols=4, rows=4,
              pole_h=None):
    """广告牌:双立柱 + 背板 + 正面贴图面板。pos 为面板中心(x, y, z)。"""
    P = []
    ph = pole_h if pole_h is not None else max(1.0, y - h * 0.5)
    for s2 in (-1, 1):
        P.append(solid("%s_p%d" % (name, s2), (0.26, ph, 0.26),
                       (x + math.cos(yaw) * s2 * (w * 0.5 - 0.4), ph * 0.5,
                        z - math.sin(yaw) * s2 * (w * 0.5 - 0.4)), "sign_pole", bev=0.02))
    back = solid("%s_back" % name, (w, h, 0.16), (x, y, z), "sign_back", bev=0.01,
                 rot=(0, yaw, 0))
    P.append(back)
    P.append(_panel(name + "_face", w * 0.97, h * 0.94,
                    (x + math.sin(yaw) * 0.10, y, z + math.cos(yaw) * 0.10),
                    yaw, cell, cols, rows, mat))
    return P


def vert_sign(name, x, z, y, w, h, yaw=0.0, cell=0, mat="sign_jp_shop", cols=4, rows=4,
              bracket=True):
    """竖招牌(挂在墙面上/悬挑)。面板法线朝 yaw 方向。"""
    P = [_panel(name + "_face", w, h, (x, y, z), yaw, cell, cols, rows, mat)]
    if bracket:
        P.append(solid(name + "_bkt", (0.14, 0.14, w * 0.8), (x, y + h * 0.42, z),
                       "sign_pole", bev=0.0))
    return P


def notice_board(name, x, z, y, w, h, yaw=0.0, cell=0, mat="sign_jp_notice",
                 cols=4, rows=4):
    """告示板:双短腿 + 板面。"""
    P = []
    for s2 in (-1, 1):
        P.append(solid("%s_l%d" % (name, s2), (0.12, y - h * 0.5, 0.12),
                       (x + math.cos(yaw) * s2 * (w * 0.5 - 0.3), (y - h * 0.5) * 0.5,
                        z - math.sin(yaw) * s2 * (w * 0.5 - 0.3)), "sign_pole", bev=0.0))
    P.append(solid(name + "_back", (w, h, 0.10), (x, y, z), "sign_back", bev=0.01,
                   rot=(0, yaw, 0)))
    P.append(_panel(name + "_face", w * 0.96, h * 0.92,
                    (x + math.sin(yaw) * 0.07, y, z + math.cos(yaw) * 0.07),
                    yaw, cell, cols, rows, mat))
    return P


def road_sign(name, x, z, h=3.2, yaw=0.0, cell=0, mat="sign_jp_road", cols=4, rows=4,
              w=1.5, ph=2.6):
    """路牌:立杆 + 面板(面板中心在杆顶)。"""
    P = [solid(name + "_pole", (0.16, ph, 0.16), (x, ph * 0.5, z), "sign_pole", bev=0.02)]
    P.append(_panel(name + "_face", w, h, (x, ph + h * 0.5, z), yaw, cell, cols, rows, mat))
    return P


def banner(name, x, z, y, w, yaw=0.0, cell=0, mat="sign_jp_banner", cols=4, rows=2,
           h=0.85):
    """横断幕(街道上空):双杆 + 布面(双面)。"""
    P = []
    for s2 in (-1, 1):
        P.append(solid("%s_p%d" % (name, s2), (0.18, y, 0.18),
                       (x + math.cos(yaw) * s2 * w * 0.5, y * 0.5,
                        z - math.sin(yaw) * s2 * w * 0.5), "sign_pole", bev=0.02))
    P.append(_panel(name + "_f", w, h, (x, y - h * 0.5, z), yaw, cell, cols, rows, mat))
    P.append(_panel(name + "_b", w, h, (x, y - h * 0.5, z), yaw + math.pi, cell, cols, rows, mat))
    return P


def litter(name, x, z, rot=0.0, cell=0, cols=2, rows=2, w=0.9, d=0.62):
    """地面散落物(报纸/传单):贴地薄面。"""
    ob = _sign_quad(name, w, d, cell, cols, rows)
    ob.rotation_euler = (0.0, 0.0, rot)                    # 平铺在地面
    ob.location = g2b((x, 0.07, z))
    zmat(ob, "jp_flyer")
    return [ob]



# ============================================================ 战后痕迹
# 2026-09-10:用户要"让人意识到这是战争中"—— 弹坑/废墟/残骸/路障。
def crater(name, x, z, r=4.0, depth=0.85, burnt=True):
    """弹坑:翻起的土环 + 焦黑坑底 + 溅射碎块。"""
    P = []
    P.append(deco(name + "_hole", (r * 1.15, 0.1, r * 1.15), (x, 0.05, z), "dark", bev=0.0))
    n = max(8, int(r * 3))
    for i in range(n):                                     # 周边翻土环
        a = 2 * math.pi * i / n
        rr = r * (0.72 + 0.12 * ((i * 7) % 5) / 4.0)
        P.append(deco("%s_rim%d" % (name, i), (r * 0.42, 0.30 + 0.1 * ((i * 3) % 3), r * 0.38),
                      (x + math.cos(a) * rr, 0.13, z + math.sin(a) * rr),
                      "stone_d" if i % 3 else "sand", bev=0.06,
                      rot=(0, a, 0)))
    for i in range(5):                                     # 溅射碎块
        a = 2 * math.pi * i / 5 + 0.4
        rr = r * (1.05 + 0.25 * (i % 3))
        P.append(deco("%s_sp%d" % (name, i), (0.6, 0.28, 0.5),
                      (x + math.cos(a) * rr, 0.14, z + math.sin(a) * rr), "stone_d", bev=0.05,
                      rot=(0, a * 1.7, 0)))
    if burnt:
        P.append(deco(name + "_scorch", (r * 2.0, 0.02, r * 2.0), (x, 0.06, z), "dark", bev=0.0))
    col(name, (r * 1.0, 0.12, r * 1.0), (x, 0.06, z))       # 浅坑:可踩(不挡人)
    return P


def rubble(name, x, z, rad=3.0, n=10, seed=1):
    """瓦砾堆:散落混凝土块/砖/钢筋。"""
    P = []
    rnd = __import__("random").Random(seed)
    for i in range(n):
        a = rnd.uniform(0, 6.2832)
        rr = rnd.uniform(0, rad)
        w = rnd.uniform(0.5, 1.6)
        P.append(deco("%s_%d" % (name, i),
                      (w, rnd.uniform(0.25, 0.7), rnd.uniform(0.5, 1.3)),
                      (x + math.cos(a) * rr, rnd.uniform(0.15, 0.4), z + math.sin(a) * rr),
                      "concrete_d" if i % 2 else "stone_d", bev=0.05,
                      rot=(0, rnd.uniform(0, 3.14), 0)))
        if i % 4 == 0:                                      # 露出的钢筋
            P.append(deco("%s_rebar%d" % (name, i), (0.06, rnd.uniform(0.6, 1.4), 0.06),
                          (x + math.cos(a) * rr, 1.0, z + math.sin(a) * rr), "rust", bev=0.0))
    col(name, (rad * 1.7, 0.7, rad * 1.7), (x, 0.35, z))
    return P


def ruin_bld(name, x, z, w, d, h, yaw=0.0, seed=3):
    """半毁建筑:残墙(高低不齐) + 外露楼板 + 塌落瓦砾 + 焦痕。
    残墙只留 2~3 面, 形成可穿行的废墟(也当掩体)。"""
    P = []
    rnd = __import__("random").Random(seed)
    hw, hd = w * 0.5, d * 0.5
    # 残墙:每面沿长度切成若干段, 段高随机衰减
    for wi, (wx, wz, along, ln) in enumerate((
            (x, z - hd, "x", w), (x, z + hd, "x", w),
            (x - hw, z, "z", d), (x + hw, z, "z", d))):
        if wi == rnd.randint(0, 3):                          # 随机留一面缺口(可穿行)
            continue
        segs = max(3, int(ln / 3.0))
        for k in range(segs):
            t0 = -ln * 0.5 + ln * k / segs
            seg_len = ln / segs
            hh = h * rnd.uniform(0.35, 1.0)
            if hh < 0.9:
                continue
            cx = wx + (t0 + seg_len * 0.5) if along == "x" else wx
            cz = wz if along == "x" else wz + (t0 + seg_len * 0.5)
            sx = seg_len if along == "x" else 0.3
            sz = 0.3 if along == "x" else seg_len
            if along == "x":
                P += wall_x("%s_w%d_%d" % (name, wi, k), cx - seg_len * 0.5, cx + seg_len * 0.5,
                            wz, 0.3, 0, hh, "concrete_d", windows=[(cx, seg_len * 0.5, 1.0, 1.6)]
                            if hh > 3.0 else [])
            else:
                P += wall_z("%s_w%d_%d" % (name, wi, k), cz - seg_len * 0.5, cz + seg_len * 0.5,
                            wx, 0.3, 0, hh, "concrete_d", windows=[(cz, seg_len * 0.5, 1.0, 1.6)]
                            if hh > 3.0 else [])
    # 外露楼板(塌了一半)
    P += floor_slab(name + "_slab", x - hw * 0.9, x + hw * 0.2, z - hd * 0.8, z + hd * 0.3,
                    h * 0.48, 0.24, "concrete", walkable=True)
    for i in range(3):                                       # 断裂的柱
        P.append(solid("%s_col%d" % (name, i), (0.5, h * rnd.uniform(0.3, 0.8), 0.5),
                       (x + hw * rnd.uniform(-0.8, 0.8), h * 0.2, z + hd * rnd.uniform(-0.8, 0.8)),
                       "concrete_d", bev=0.02))
    P += rubble(name + "_rub", x + hw * 0.4, z - hd * 0.3, min(w, d) * 0.42,
                n=max(6, int(w * d / 6)), seed=seed + 11)
    P.append(deco(name + "_burn", (w * 0.7, 0.03, d * 0.7), (x + hw * 0.25, 0.06, z + hd * 0.2),
                  "dark", bev=0.0))
    return P


def wreck_pile(name, x, z, n=3, yaw=0.0, seed=7):
    """连环相撞的报废车堆 + 焦痕 + 散落零件。"""
    P = []
    rnd = __import__("random").Random(seed)
    for i in range(n):
        a = yaw + rnd.uniform(-0.9, 0.9)
        ox = x + math.cos(a) * i * 3.4
        oz = z + math.sin(a) * i * 3.4
        P += wreck_car("%s_c%d" % (name, i), ox, oz, math.degrees(a) + rnd.uniform(-25, 25))
        P.append(deco("%s_tire%d" % (name, i), (0.7, 0.7, 0.34),
                      (ox + rnd.uniform(-1.6, 1.6), 0.35, oz + rnd.uniform(-1.6, 1.6)),
                      "rubber", bev=0.2))
    P.append(deco(name + "_scorch", (n * 4.2, 0.02, 5.0), (x, 0.06, z), "dark", bev=0.0))
    return P


# ============================================================ 室内家具(复用简单体块, 与世界道具同语言)
def _table(name, x, z, y=0.0, w=1.4, d=0.8, h=0.72, mat="wood_d"):
    P = [deco(name + "_top", (w, 0.07, d), (x, y + h, z), mat, bev=0.02)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            P.append(deco("%s_l%d%d" % (name, sx, sz), (0.07, h, 0.07),
                          (x + sx * (w * 0.5 - 0.09), y + h * 0.5, z + sz * (d * 0.5 - 0.09)),
                          mat, bev=0.0))
    return P


def _chair(name, x, z, y=0.0, yaw=0.0, mat="wood_d"):
    c, s2 = math.cos(yaw), math.sin(yaw)
    P = [deco(name + "_seat", (0.44, 0.06, 0.44), (x, y + 0.45, z), mat, bev=0.02,
              rot=(0, yaw, 0)),
         deco(name + "_back", (0.44, 0.45, 0.06),
              (x - s2 * 0.20, y + 0.68, z - c * 0.20), mat, bev=0.02, rot=(0, yaw, 0))]
    for sx in (-1, 1):
        for sz in (-1, 1):
            px = x + c * sx * 0.18 + s2 * sz * 0.18
            pz = z - s2 * sx * 0.18 + c * sz * 0.18
            P.append(deco("%s_l%d%d" % (name, sx, sz), (0.05, 0.45, 0.05), (px, y + 0.225, pz),
                          mat, bev=0.0))
    return P


def shelf_unit(name, x, z, y=0.0, w=2.0, h=1.9, d=0.5, yaw=0.0, levels=4, mat="shelf"):
    """货架/书柜:多层横板 + 立柱(商店/办公室通用)。
    默认浅灰 shelf —— 旧版 metal_d 在室内单点补光下整块发黑(用户读作"黑箱子")。"""
    c, s2 = math.cos(yaw), math.sin(yaw)
    P = []
    for lv in range(levels):
        yy = y + 0.28 + lv * (h - 0.3) / max(1, levels - 1)
        P.append(solid("%s_t%d" % (name, lv), (w, 0.06, d), (x, yy, z), mat, bev=0.01,
                       rot=(0, yaw, 0)))
    for sx in (-1, 1):
        P.append(solid("%s_p%d" % (name, sx), (0.09, h, d),
                       (x + c * sx * (w * 0.5 - 0.07), y + h * 0.5, z - s2 * sx * (w * 0.5 - 0.07)),
                       mat, bev=0.01, rot=(0, yaw, 0)))
    return P


def counter_run(name, x, z, w=4.0, yaw=0.0, h=1.0, mat="wood_b"):
    """吧台/收银台:长台 + 台面 + 背柜。"""
    c, s2 = math.cos(yaw), math.sin(yaw)
    P = [solid(name + "_body", (w, h, 0.66), (x, h * 0.5, z), mat, bev=0.02, rot=(0, yaw, 0)),
         deco(name + "_top", (w + 0.12, 0.08, 0.78), (x, h + 0.04, z), "wood_d", bev=0.02,
              rot=(0, yaw, 0))]
    P += shelf_unit(name + "_back", x - s2 * 1.5, z - c * (-1.5), 0.0, w * 0.8, 1.8, 0.4,
                    yaw + math.pi, 3, "wood_b")
    return P


def bed_unit(name, x, z, yaw=0.0):
    """床:床架 + 床垫 + 枕。"""
    c, s2 = math.cos(yaw), math.sin(yaw)
    P = [solid(name + "_f", (2.0, 0.34, 1.16), (x, 0.17, z), "wood_d", bev=0.03, rot=(0, yaw, 0)),
         deco(name + "_m", (1.9, 0.22, 1.06), (x, 0.45, z), "plaster", bev=0.08, rot=(0, yaw, 0)),
         deco(name + "_pil", (0.5, 0.14, 0.5), (x - s2 * 0.7, 0.63, z - c * 0.7), "plaster",
              bev=0.06, rot=(0, yaw, 0))]
    return P


def sofa_unit(name, x, z, yaw=0.0, mat="brick"):
    c, s2 = math.cos(yaw), math.sin(yaw)
    return [solid(name + "_b", (1.9, 0.42, 0.85), (x, 0.21, z), mat, bev=0.08, rot=(0, yaw, 0)),
            deco(name + "_k", (1.9, 0.55, 0.2), (x - s2 * 0.33, 0.62, z - c * 0.33), mat,
                 bev=0.08, rot=(0, yaw, 0)),
            deco(name + "_a0", (0.18, 0.5, 0.85), (x + c * 0.86, 0.5, z - s2 * 0.86), mat,
                 bev=0.06, rot=(0, yaw, 0)),
            deco(name + "_a1", (0.18, 0.5, 0.85), (x - c * 0.86, 0.5, z + s2 * 0.86), mat,
                 bev=0.06, rot=(0, yaw, 0))]


def interior(name, x0, x1, z0, z1, kind="shop", yaw=0.0, seed=5):
    """按房间类型快速布置家具。kind: shop 便利店 / izakaya 居酒屋 / office 办公 /
    home 住宅 / ramen 拉面店 / station 站厅。x0<x1, z0<z1 为地面范围(全局坐标)。"""
    P = []
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    w, d = x1 - x0, z1 - z0
    rnd = __import__("random").Random(seed)
    if w < 3.0 or d < 3.0:
        return P
    if kind == "shop":
        P += shelf_unit(name + "_sh0", x0 + 1.3, cz - d * 0.25, 0.0, d * 0.55, 1.9, 0.55, math.pi * 0.5, 4)
        P += shelf_unit(name + "_sh1", x0 + 1.3, cz + d * 0.25, 0.0, d * 0.55, 1.9, 0.55, math.pi * 0.5, 4)
        # ★ 背墙货架贴**北**墙(z1), 不放南墙(z0+1.0): _fillbld 的门就在南墙中线,
        #   旧版这块 1.8m 高的货架正好堵死在门口(用户: 家具建在门口被挡着过不去)。
        P += shelf_unit(name + "_sh2", cx, z1 - 1.0, 0.0, w * 0.6, 1.8, 0.5, 0.0, 3)
        P += counter_run(name + "_ct", x1 - 1.6, cz, min(3.2, d * 0.6), math.pi * 0.5)
        P.append(solid(name + "_frz", (0.9, 1.9, 1.6), (x0 + 0.8, 0.95, z0 + 1.2), "metal", bev=0.04))
        for i in range(3):                                   # 购物篮堆
            P.append(deco("%s_bk%d" % (name, i), (0.5, 0.28, 0.4),
                          (x1 - 1.2, 0.15 + i * 0.3, z0 + 0.9), "sign_b", bev=0.03))
    elif kind == "izakaya":
        P += counter_run(name + "_ct", x0 + 1.4, cz, min(d * 0.7, 6.0), math.pi * 0.5, 1.05)
        for i in range(3):
            zz = cz - d * 0.3 + i * d * 0.3
            P += _table(name + "_t%d" % i, x1 - 1.6, zz, 0.0, 0.9, 0.9, 0.70)
            P += _chair("%s_c%d0" % (name, i), x1 - 2.7, zz, 0.0, math.pi * 0.5)
            P += _chair("%s_c%d1" % (name, i), x1 - 0.5, zz, 0.0, -math.pi * 0.5)
        P.append(solid(name + "_lt", (0.5, 2.4, 1.0), (x0 + 0.5, 1.2, z0 + 1.0), "wood_d", bev=0.03))
    elif kind == "office":
        for i in range(max(1, int(w / 3.2))):
            for k in range(max(1, int(d / 3.2))):
                xx = x0 + 1.8 + i * 3.2
                zz = z0 + 1.8 + k * 3.2
                P += _table(name + "_d%d%d" % (i, k), xx, zz, 0.0, 1.6, 0.9, 0.74)
                P += _chair("%s_c%d%da" % (name, i, k), xx, zz - 1.0, 0.0, 0.0)
                P += _chair("%s_c%d%db" % (name, i, k), xx, zz + 1.0, 0.0, math.pi)
        P += shelf_unit(name + "_cab", x1 - 0.8, cz, 0.0, d * 0.7, 1.6, 0.45, math.pi * 0.5, 3)
        # 前台同样避开南墙门口 → 靠北墙
        P.append(solid(name + "_prt", (1.6, 1.5, 1.2), (cx, 0.75, z1 - 1.2), "metal_d", bev=0.03))
    elif kind == "home":
        P += bed_unit(name + "_bd", cx + w * 0.18, cz + d * 0.15, 0.0)
        P += shelf_unit(name + "_cl", x0 + 0.6, z0 + 1.4, 0.0, 1.6, 2.0, 0.6, math.pi * 0.5, 4, "wood_b")
        P += _table(name + "_tb", cx - w * 0.2, cz - d * 0.2, 0.0, 1.0, 0.7, 0.72)
        P += _chair("%s_ch" % name, cx - w * 0.2, cz - d * 0.2 - 0.9, 0.0, 0.0)
        P += sofa_unit(name + "_sf", x0 + 1.6, cz + d * 0.3, math.pi * 0.5, "sign_b")
        P.append(solid(name + "_tv", (0.9, 0.6, 0.35), (x1 - 1.0, 0.9, cz), "metal_d", bev=0.02))
    elif kind == "ramen":
        # 吧台从 z0+1.1 挪到 z0+3.6、凳子从 z0+2.2 挪到 z0+3.0: 旧值整条吧台横在门口
        P += counter_run(name + "_ct", cx, z0 + 3.6, w * 0.75, 0.0, 1.0)
        for i in range(max(1, int(w / 0.85))):
            P += _chair("%s_st%d" % (name, i), x0 + 0.7 + i * 0.85, z0 + 3.0, 0.0, 0.0)
        P.append(solid(name + "_pot", (0.7, 0.7, 0.7), (x0 + 0.9, 0.35, z0 + 0.5), "metal_d", bev=0.05))
    elif kind == "station":
        for i in range(max(1, int(w / 3.0))):
            P.append(solid("%s_bn%d" % (name, i), (1.8, 0.42, 0.55),
                           (x0 + 1.6 + i * 3.0, 0.21, cz), "wood_d", bev=0.05))
        P += shelf_unit(name + "_shp", x1 - 1.2, cz, 0.0, d * 0.5, 1.7, 0.5, math.pi * 0.5, 3)
        # 站厅导向牌避开门口中线(旧版挂在门洞正上方)
        P.append(deco(name + "_bd", (w * 0.5, 1.6, 0.12), (cx + w * 0.3, 2.0, z0 + 0.35), "sign_b", bev=0.0))
    # 室内照明:吊灯罩(自发光, 视觉) + light_ 标记(引擎侧实例化 OmniLight3D 真正照亮)
    # —— SDFGI 各画质档全部关闭, 自发光不照亮邻面, 不给实体光源室内就是全黑(实测)。
    ly = 2.4 if kind == "home" else 3.0
    P.append(deco(name + "_cl", (1.5, 0.14, 0.5), (cx, ly, cz), "lamp_warm", bev=0.0))
    P.append(fast_empty("light_" + name, (1.0, 1.0, 1.0), (cx, ly - 0.25, cz)))
    return P



def crate_stack(name, x, z, n=3, yaw=0.0, seed=11):
    """纸箱/木箱堆(街道杂物 + 掩体)。"""
    P = []
    rnd = __import__("random").Random(seed)
    layers = [(0.0, 0.62, 0.52, 0.58), (0.62, 0.5, 0.44, 0.46), (1.1, 0.42, 0.36, 0.4)]
    for i in range(min(n, 3)):
        yy, cw, ch, cd = layers[i]
        a = yaw + rnd.uniform(-0.5, 0.5)
        P.append(deco("%s_%d" % (name, i), (cw, ch, cd),
                      (x + rnd.uniform(-0.3, 0.3), yy + ch * 0.5, z + rnd.uniform(-0.3, 0.3)),
                      "wood_b" if i % 2 else "sand", bev=0.03, rot=(0, a, 0)))
    col(name, (1.1, 1.3, 1.1), (x, 0.65, z))
    return P
