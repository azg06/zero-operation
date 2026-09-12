# -*- coding: utf-8 -*-
"""对比 WeaponsData.sight_y(ADS 相机) 与 MOD_ANCHORS.optic.y(枪模照门/镜实际高度)"""
import re

wm = open(r"E:\工作目录2\zero\steel_frontline_godot\src\models\weapon_models.gd", encoding="utf-8").read()
wd = open(r"E:\工作目录2\zero\steel_frontline_godot\src\data\weapons_data.gd", encoding="utf-8").read()

anchors = {}
for m in re.finditer(r'"(\w+)": \{[^}]*?"optic": Vector3\(0, ([\d.]+),', wm):
    anchors[m.group(1)] = float(m.group(2))

sights = {}
for m in re.finditer(r'WD\["(\w+)"\] = _w\([^\n]*\n\s*\[[^\]]+\], ([\d.]+), (-?[\d.]+),', wd):
    sights[m.group(1)] = (float(m.group(2)), float(m.group(3)))

print("%-9s %8s %8s %8s  %s" % ("枪", "sight_y", "optic.y", "差(mm)", "判定"))
bad = []
for gid in sorted(sights):
    sy, az = sights[gid]
    oy = anchors.get(gid)
    if oy is None:
        continue
    diff = (oy - sy) * 1000
    if abs(diff) > 6:
        bad.append((gid, sy, oy, diff))
        print("%-9s %8.4f %8.4f %8.1f  错位(%s)" % (gid, sy, oy, diff, "枪模偏高" if diff > 0 else "枪模偏低"))
print("\n错位枪数: %d / 有锚点 %d" % (len(bad), len(anchors)))
print("无 optic 锚点(纯机瞄用默认):", sorted(set(sights) - set(anchors)))
