## 载具 GLB 几何探针: 输出各节点子树的**世界坐标 AABB**(用于核对相机眼位/内饰高度)。
## 用法: python tools/veh_probe.py models/vehicles/tank.glb [more.glb ...]
import json, struct, sys


def glb(path):
    d = open(path, 'rb').read()
    off = 12
    js = None
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        off += 8
        chunk = d[off:off + ln]
        if ty == 0x4E4F534A:
            js = json.loads(chunk.decode('utf-8'))
        off += ln
    return js


def mul(a, b):
    r = [[0.0] * 4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            s = 0.0
            for k in range(4):
                s += a[k][i] * b[j][k]
            r[j][i] = s
    return r


def ident():
    return [[1 if i == j else 0 for j in range(4)] for i in range(4)]


def trs(node):
    if 'matrix' in node:
        m = node['matrix']
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get('translation', [0, 0, 0])
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    sx, sy, sz = node.get('scale', [1, 1, 1])
    R = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
        [0, 0, 0, 1]]
    for i in range(3):
        for j in range(3):
            R[i][j] *= (sx, sy, sz)[j]
    R[0][3] = t[0]
    R[1][3] = t[1]
    R[2][3] = t[2]
    return R


def xf(m, p):
    return [m[0][0] * p[0] + m[0][1] * p[1] + m[0][2] * p[2] + m[0][3],
            m[1][0] * p[0] + m[1][1] * p[1] + m[1][2] * p[2] + m[1][3],
            m[2][0] * p[0] + m[2][1] * p[1] + m[2][2] * p[2] + m[2][3]]


def report(path):
    js = glb(path)
    nodes = js['nodes']
    boxes = {}

    def add(key, w):
        if key not in boxes:
            boxes[key] = [list(w), list(w)]
        b = boxes[key]
        for k in range(3):
            b[0][k] = min(b[0][k], w[k])
            b[1][k] = max(b[1][k], w[k])
        add('ALL', w) if key != 'ALL' else None

    def walk(i, pm, top):
        n = nodes[i]
        m = mul(pm, trs(n))
        nm = str(n.get('name', '?'))
        cur = nm          # 逐节点自身 mesh 的 AABB(不含子节点) —— 便于分辨"炮塔壳顶"与"附件最高点"
        if 'mesh' in n:
            for pr in js['meshes'][n['mesh']].get('primitives', []):
                a = js['accessors'][pr['attributes']['POSITION']]
                mn, mx = a['min'], a['max']
                for cx in (mn[0], mx[0]):
                    for cy in (mn[1], mx[1]):
                        for cz in (mn[2], mx[2]):
                            w = xf(m, [cx, cy, cz])
                            if cur not in boxes:
                                boxes[cur] = [list(w), list(w)]
                            b = boxes[cur]
                            for k in range(3):
                                b[0][k] = min(b[0][k], w[k])
                                b[1][k] = max(b[1][k], w[k])
                            if 'ALL' not in boxes:
                                boxes['ALL'] = [list(w), list(w)]
                            ba = boxes['ALL']
                            for k in range(3):
                                ba[0][k] = min(ba[0][k], w[k])
                                ba[1][k] = max(ba[1][k], w[k])
        for c in n.get('children', []):
            walk(c, m, cur)

    for root in js['scenes'][js.get('scene', 0)]['nodes']:
        walk(root, ident(), None)
    print('=== %s ===' % path.split('/')[-1])
    for k in sorted(boxes):
        b = boxes[k]
        print('  %-16s x[%6.2f,%6.2f] y[%6.2f,%6.2f] z[%6.2f,%6.2f]' % (
            k, b[0][0], b[1][0], b[0][1], b[1][1], b[0][2], b[1][2]))
    print('  nodes:', ', '.join(str(n.get('name', '?')) for n in nodes)[:700])


for f in sys.argv[1:]:
    report(f)
