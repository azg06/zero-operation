# -*- coding: utf-8 -*-
"""还原 weapons_data.gd 的 sight_y 到 HEAD 原值(保留本轮 ads_z=-0.34 手枪改动)"""
import re, subprocess

p = r"E:\工作目录2\zero\steel_frontline_godot\src\data\weapons_data.gd"
head = subprocess.run(
    ["git", "-C", r"E:\工作目录2\zero\steel_frontline_godot", "show", "HEAD:src/data/weapons_data.gd"],
    capture_output=True).stdout.decode("utf-8")

# HEAD 版本的原 sight_y 表
orig = {}
for m in re.finditer(r'WD\["(\w+)"\] = _w\([^\n]*\n\s*\[[^\]]+\], ([\d.]+), (-?[\d.]+),', head):
    orig[m.group(1)] = float(m.group(2))

lines = open(p, encoding="utf-8").read().split("\n")
fixed = 0
for i, line in enumerate(lines):
    m = re.match(r'\s*WD\["(\w+)"\] = _w\(', line)
    if not m or i + 1 >= len(lines):
        continue
    gid = m.group(1)
    if gid not in orig:
        continue
    oy = orig[gid]
    m2 = re.match(r'(\s*\[[^\]]+\], )([\d.]+)(, -?[\d.]+,.*)', lines[i + 1])
    if m2 and abs(float(m2.group(2)) - oy) > 0.0005:
        lines[i + 1] = m2.group(1) + ("%.4f" % oy) + m2.group(3)
        fixed += 1
        print("%-9s sight_y 还原 -> %.4f" % (gid, oy))

open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("共还原", fixed, "把")
