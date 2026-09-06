"""
渲染武器预览图 —— 用于人工确认模型细节。

用法:
    blender --background --python render_preview.py -- m4
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import math
from gunforge import stats, export_glb

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = "E:/工作目录2/models_probe"


def setup_scene():
    # 三点布光 + 顶部补光,降一档强度避免把暗色冲白
    bpy.ops.object.light_add(type='AREA', location=(0.6, -0.9, 0.8))
    k = bpy.context.active_object
    k.data.energy = 60
    k.data.size = 1.4
    k.data.color = (1.0, 0.97, 0.92)   # 暖色主光
    bpy.ops.object.light_add(type='AREA', location=(-0.9, 0.5, 0.4))
    f = bpy.context.active_object
    f.data.energy = 18
    f.data.size = 1.6
    f.data.color = (0.75, 0.82, 1.0)   # 冷色补光,带冷暖对比
    bpy.ops.object.light_add(type='AREA', location=(0.2, 1.1, 0.3))
    r = bpy.context.active_object
    r.data.energy = 25
    r.data.size = 0.8
    # 环境背景:Blender 5 默认没有 world,跳过避免崩溃
    try:
        if bpy.context.scene.world is None:
            bpy.context.scene.world = bpy.data.worlds.new("Preview")
        bpy.context.scene.world.use_nodes = True
        bg = bpy.context.scene.world.node_tree.nodes.get("Background")
        if bg is not None:
            bg.inputs['Color'].default_value = (0.04, 0.05, 0.06, 1.0)
            bg.inputs['Strength'].default_value = 0.2
    except Exception as e:
        print("  [warn] world setup skipped: %s" % e)


def setup_camera(target=(0, 0, 0), dist=1.25, angle=(-62, 0, 38), lens=85):
    bpy.ops.object.camera_add(location=(0, 0, 0))
    cam = bpy.context.active_object
    bpy.context.scene.camera = cam
    # 轨道机位:绕 X 轴俯仰 + 绕 Z 轴方位
    az = math.radians(angle[2])
    el = math.radians(angle[0])
    x = target[0] + dist * math.cos(el) * math.sin(az)
    y = target[1] - dist * math.cos(el) * math.cos(az)
    z = target[2] - dist * math.sin(el)
    cam.location = (x, y, z)
    # 看向目标
    import mathutils
    direction = mathutils.Vector(target) - mathutils.Vector((x, y, z))
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = lens
    cam.data.clip_start = 0.01
    return cam


def render(path, res=(1600, 900)):
    sc = bpy.context.scene
    # EEVEE 在 headless 下对 Principled BSDF 的 Base Color 着色不稳定(已踩),
    # 改用 WorkBench 引擎:它直接按 material.diffuse_color 渲,不靠节点图,
    # 颜色稳定,代价是没反射/阴影 —— 反正只是用来"看零件对不对",不需要 PBR 精度。
    sc.render.engine = 'BLENDER_WORKBENCH'
    try:
        sc.display.shading.light = 'STUDIO'
        sc.display.shading.color_type = 'MATERIAL'
    except Exception:
        pass
    sc.render.resolution_x = res[0]
    sc.render.resolution_y = res[1]
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDER", path)


def main():
    wid = "m4"
    args = sys.argv
    if "--" in args:
        tail = args[args.index("--") + 1:]
        if tail:
            wid = tail[0]

    # 导入构建脚本并建模
    mod = __import__("build_" + wid)
    mod.build()
    objs, verts, tris = stats()
    print("MODEL %s objects=%d verts=%d tris=%d" % (wid, objs, verts, tris))

    setup_scene()
    setup_camera(target=(0, 0, 0.02), dist=1.15, angle=(-70, 0, 42))
    out = os.path.join(OUT_DIR, "preview_%s.png" % wid)
    os.makedirs(OUT_DIR, exist_ok=True)
    render(out)

    # 再来一张近景特写,看抛壳窗/导轨/消焰器的细节
    setup_camera(target=(0, 0.02, -0.10), dist=0.42, angle=(-75, 0, 22))
    out2 = os.path.join(OUT_DIR, "preview_%s_detail.png" % wid)
    render(out2, res=(1500, 950))


if __name__ == "__main__":
    main()
