"""
批量渲染 8 把突击步枪预览图(WorkBench 材质色块,用于人工确认零件细节)。

    blender --background --python render_all.py
"""

import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy
from gunforge import stats
from render_preview import setup_scene, setup_camera, render
import build_m4
import build_ar_batch

OUT_DIR = "E:/工作目录2/models_probe"


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def shoot(wid, builder):
    reset_scene()
    setup_scene()
    builder()
    objs, verts, tris = stats()
    setup_camera(target=(0, 0, 0.02), dist=2.0, angle=(-64, 0, 38), lens=50)
    render(os.path.join(OUT_DIR, "preview_%s.png" % wid), res=(1400, 790))
    print("MODEL %-6s objs=%-4d tris=%-6d" % (wid, objs, tris))


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for wid, fn in build_ar_batch.BUILDERS.items():
        shoot(wid, fn)
    shoot("m4", build_m4.build)
    print("ALL_RENDERED")
