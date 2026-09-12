"""突击步枪批次一键生成 —— M4/AK/SCAR/AUG/G36C/AK74/FAMAS/G3

跑一次,8 把枪的 GLB 全产到 models/weapons/。
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy

import build_m4, build_ak, build_g36c, build_scar, build_aug, build_ak74, build_famas, build_g3
from gunforge import stats, export_glb

OUT_DIR = "E:/工作目录2/zero/steel_frontline_godot/models/weapons"

MODS = [
    ("m4", build_m4),
    ("ak", build_ak),
    ("g36c", build_g36c),
    ("scar", build_scar),
    ("aug", build_aug),
    ("ak74", build_ak74),
    ("famas", build_famas),
    ("g3", build_g3),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rows = []
    for wid, mod in MODS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        try:
            mod.build()
        except Exception as e:
            print("[%s] BUILD FAILED: %s" % (wid, e))
            continue
        objs, verts, tris = stats()
        out = os.path.join(OUT_DIR, wid + ".glb")
        export_glb(out)
        rows.append((wid, objs, verts, tris, os.path.getsize(out) // 1024))
        print("[%s] objects=%d verts=%d tris=%d size=%dKB" %
            (wid, objs, verts, tris, rows[-1][4]))
    print()
    print("====== 8 把突击步枪生成完毕 ======")
    print("%-8s %-8s %-8s %-8s %s" % ("id", "objects", "verts", "tris", "size"))
    for r in rows:
        print("%-8s %-8d %-8d %-8d %dKB" % r)


if __name__ == "__main__":
    main()
