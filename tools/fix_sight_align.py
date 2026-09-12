# -*- coding: utf-8 -*-
"""把 weapons_data.gd 每把枪的 sight_y 对齐到 MOD_ANCHORS.optic.y(枪模实际照门高度)"""
import re

wm = open(r"E:\工作目录2\zero\steel_frontline_godot\src\models\weapon_models.gd", encoding="utf-8").read()
p = r"E:\工作目录2\zero\steel_frontline_godot\src\data\weapons_data.gd"

anchors = {}
for m in re.finditer(r'"(\w+)": \{[^}]*?"optic": Vector3\(0, ([\d.]+),', wm):
    anchors[m.group(1)] = float(m.group(2))

lines = open(p, encoding="utf-8").read().split("\n")
fixed = 0
for i, line in enumerate(lines):
    m = re.match(r'\s*WD\["(\w+)"\] = _w\(', line)
    if not m:
        continue
    gid = m.group(1)
    if gid not in anchors or i + 1 >= len(lines):
        continue
    oy = anchors[gid]
    # 下一行: rng 数组后的 sight_y, ads_z —— 精确替换 sight_y(第一个独立浮点)
    m2 = re.match(r'(\s*\[[^\]]+\], )([\d.]+)(, -?[\d.]+,.*)', lines[i + 1])
    if m2 and abs(float(m2.group(2)) - oy) > 0.0005:
        lines[i + 1] = m2.group(1) + ("%.4f" % oy) + m2.group(3)
        fixed += 1
        print("%-9s sight_y -> %.4f" % (gid, oy))

open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("共修正", fixed, "把")
