# -*- coding: utf-8 -*-
"""探测 GLB 节点/骨骼的空间数据(摩托车契约件 + 士兵骨架 rest)。
用法: python tools/rig_probe.py
输出: 节点世界坐标(累乘 TRS), 供骑姿/手臂 IK 定标。"""
import json
import struct
import math
import sys


def load_glb(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'glTF', path
    off = 12
    js = None
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        off += 8
        if ty == 0x4E4F534A:
            js = json.loads(d[off:off + ln].decode('utf-8'))
        off += ln
    return js


def mat_mul(a, b):
    out = [0.0] * 16
    for i in range(4):
        for j in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + i] * b[j * 4 + k]
            out[j * 4 + i] = s
    return out


def trs(n):
    t = n.get('translation', [0.0, 0.0, 0.0])
    q = n.get('rotation', [0.0, 0.0, 0.0, 1.0])
    s = n.get('scale', [1.0, 1.0, 1.0])
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    m = [
        (1 - 2 * (yy + zz)) * s[0], (2 * (xy + wz)) * s[0], (2 * (xz - wy)) * s[0], 0.0,
        (2 * (xy - wz)) * s[1], (1 - 2 * (xx + zz)) * s[1], (2 * (yz + wx)) * s[1], 0.0,
        (2 * (xz + wy)) * s[2], (2 * (yz - wx)) * s[2], (1 - 2 * (xx + yy)) * s[2], 0.0,
        t[0], t[1], t[2], 1.0,
    ]
    return m


def walk(nodes, i, parent_m, out, prefix):
    m = mat_mul(parent_m, trs(nodes[i]))
    nm = nodes[i].get('name', '?')
    path = prefix + '/' + nm if prefix else nm
    out.append((path, m[12], m[13], m[14], nodes[i].get('mesh')))
    for c in nodes[i].get('children', []):
        walk(nodes, c, m, out, path)


def report(path, want=None):
    j = load_glb(path)
    nodes = j['nodes']
    par = {}
    for i, n in enumerate(nodes):
        for c in n.get('children', []):
            par[c] = i
    roots = [i for i in range(len(nodes)) if i not in par]
    out = []
    I = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    # 场景根
    for sc in j.get('scenes', []):
        for r in sc.get('nodes', []):
            walk(nodes, r, I, out, '')
    print('=== %s (%d nodes) ===' % (path, len(nodes)))
    for p, x, y, z, mesh in out:
        if want is not None and not any(w.lower() in p.lower() for w in want):
            continue
        print('%-58s world=(%7.3f,%7.3f,%7.3f) mesh=%s' % (p, x, y, z, mesh))
    return out


if __name__ == '__main__':
    base = 'models/vehicles/'
    keys = ['Grip', 'Peg', 'Seat', 'Steer_F', 'Handlebar', 'Wheel', 'Tank', 'Swingarm', 'Mirror', 'Lever']
    report(base + 'motorcycle.glb', keys)
    print()
    # 士兵骨架 rest
    j = load_glb('models/soldiers/soldier.glb')
    nodes = j['nodes']
    par = {}
    for i, n in enumerate(nodes):
        for c in n.get('children', []):
            par[c] = i
    out = []
    I = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for sc in j.get('scenes', []):
        for r in sc.get('nodes', []):
            walk(nodes, r, I, out, '')
    print('=== soldier.glb bones (rest world) ===')
    for p, x, y, z, mesh in out:
        print('%-58s world=(%7.3f,%7.3f,%7.3f)' % (p, x, y, z))
    skins = j.get('skins', [])
    print('skins=%d' % len(skins))
