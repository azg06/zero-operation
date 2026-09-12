# -*- coding: utf-8 -*-
"""离线路网体检: 解析 build_jp_city.py 的 slab(..., mat=asphalt*) 路面,
按分区原点换算全局坐标, 栅格化后统计: 连通分量 / 断头点 / 交叉口 / 覆盖率。"""
import re, os, math, collections

SRC = "E:/工作目录2/zero/steel_frontline_godot/tools/blender/build_jp_city.py"
ORIG = {1: (-300.0, 60.0), 2: (-140.0, -120.0), 3: (50.0, 170.0), 4: (250.0, 340.0),
        5: (-270.0, 340.0), 6: (325.0, -160.0), 7: (-80.0, -360.0), 8: (200.0, -60.0),
        9: (0.0, 0.0), 10: (0.0, 0.0)}

txt = open(SRC, encoding="utf-8").read().split("\n")
# 定位每个 def build_zone_N 的行号
zlines = []
for i, ln in enumerate(txt):
    m = re.match(r"def build_zone_(\d+)\(", ln)
    if m:
        zlines.append((i, int(m.group(1))))
zlines.sort()

pat = re.compile(r'slab\(\s*"([^"]+)"\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)[^)]*?mat\s*=\s*"([^"]+)"')
roads = []
for i, ln in enumerate(txt):
    m = pat.search(ln)
    if not m:
        continue
    if "asphalt" not in m.group(6):
        continue
    zid = 0
    for (zl, zz) in zlines:
        if zl <= i:
            zid = zz
    if zid not in ORIG:
        continue
    ox, oz = ORIG[zid]
    x0, x1, z0, z1 = float(m.group(2)), float(m.group(3)), float(m.group(4)), float(m.group(5))
    # 站前大道路面用局部 x23..37 -> 全局 +50
    roads.append((m.group(1), min(x0, x1) + ox, max(x0, x1) + ox,
                  min(z0, z1) + oz, max(z0, z1) + oz, m.group(6)))

print("路面 slab 数 =", len(roads))

G = 5.0          # 5m 栅格
cell = set()
road_of = {}
for (nm, x0, x1, z0, z1, mat) in roads:
    if x1 - x0 > 400 or z1 - z0 > 400:
        continue
    ix0, ix1 = int(math.floor(x0 / G)), int(math.ceil(x1 / G))
    iz0, iz1 = int(math.floor(z0 / G)), int(math.ceil(z1 / G))
    for ix in range(ix0, ix1):
        for iz in range(iz0, iz1):
            cell.add((ix, iz))
            road_of.setdefault((ix, iz), nm)

print("占用栅格 =", len(cell), " 覆盖率(960x960) = %.1f%%" % (100.0 * len(cell) * G * G / (960.0 * 960.0)))

# 连通分量
comp = {}
cid = 0
for c in cell:
    if c in comp:
        continue
    cid += 1
    st = [c]
    comp[c] = cid
    while st:
        (cx, cz) = st.pop()
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cx + d[0], cz + d[1])
            if n in cell and n not in comp:
                comp[n] = cid
                st.append(n)
sizes = collections.Counter(comp.values())
print("连通分量 = %d, 最大分量 = %d 格 (%.0f%%)" % (cid, sizes.most_common(1)[0][1],
      100.0 * sizes.most_common(1)[0][1] / len(cell)))
print("分量规模前 6:", sizes.most_common(6))

# 断头点: 邻居数 == 1
tips = []
for c in cell:
    n = 0
    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if (c[0] + d[0], c[1] + d[1]) in cell:
            n += 1
    if n <= 1:
        tips.append(c)
# 聚类
tcl = {}
for t in tips:
    k = (t[0] // 8, t[1] // 8)
    tcl.setdefault(k, []).append(t)
print("断头点数 = %d, 聚类 = %d" % (len(tips), len(tcl)))
big = sorted(tcl.values(), key=len, reverse=True)[:22]
for grp in big:
    xs = [p[0] * G for p in grp]; zs = [p[1] * G for p in grp]
    print("   断头 (%6.0f,%6.0f) 规模%d  [%s]" % (sum(xs) / len(xs), sum(zs) / len(zs), len(grp),
        road_of.get(grp[0], "?")))

# 交叉口: 某格四向都有路面(十字)
cross = 0
cpts = []
for c in cell:
    if ((c[0]+1, c[1]) in cell and (c[0]-1, c[1]) in cell
            and (c[0], c[1]+1) in cell and (c[0], c[1]-1) in cell):
        cross += 1
        cpts.append(c)
print("十字格 = %d, 聚类 = %d" % (cross, len(set((p[0]//8, p[1]//8) for p in cpts))))
