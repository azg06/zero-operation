"""解析 GLB:打印全部 node 层次 + 每个 mesh 的 AABB 对角线,定位超长"船桨"件"""
import json, struct, sys

path = r"E:\工作目录2\zero\steel_frontline_godot\models\vehicles\apc.glb"
data = open(path, "rb").read()
magic, ver, total = struct.unpack_from("<4sII", data, 0)
assert magic == b"glTF", "not glb"
off = 12
js = None
bin_chunk = None
while off < total:
    clen, ctype = struct.unpack_from("<I4s", data, off)
    chunk = data[off + 8 : off + 8 + clen]
    if ctype == b"JSON":
        js = json.loads(chunk)
    elif ctype == b"BIN\0":
        bin_chunk = chunk
    off += 8 + clen

g = js
nodes = g.get("nodes", [])
meshes = g.get("meshes", [])
accessors = g.get("accessors", [])

def aabb_of_mesh(mi):
    """mesh 所有 primitive position accessor 的 min/max 合并"""
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for prim in meshes[mi].get("primitives", []):
        ai = prim.get("attributes", {}).get("POSITION")
        if ai is None:
            continue
        acc = accessors[ai]
        for k in range(3):
            mn[k] = min(mn[k], acc["min"][k])
            mx[k] = max(mx[k], acc["max"][k])
    diag = sum((mx[k] - mn[k]) ** 2 for k in range(3)) ** 0.5
    return mn, mx, diag

print("=== 节点树(node: 网格AABB 对角线 / min / max) ===")
# 找根节点(未被任何节点 children 引用)
child_set = set()
for n in nodes:
    for c in n.get("children", []):
        child_set.add(c)
roots = [i for i in range(len(nodes)) if i not in child_set]

def walk(i, depth):
    n = nodes[i]
    label = n.get("name", "(unnamed)")
    extra = ""
    if "mesh" in n:
        mn, mx, diag = aabb_of_mesh(n["mesh"])
        flag = "  <<<< 超长!" if diag > 1.2 else ""
        extra = " diag=%.2f min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)%s" % (
            diag, mn[0], mn[1], mn[2], mx[0], mx[1], mx[2], flag)
    if "translation" in n:
        t = n["translation"]
        extra += " T=(%.2f,%.2f,%.2f)" % (t[0], t[1], t[2])
    print("  " * depth + "%s%s" % (label, extra))
    for c in n.get("children", []):
        walk(c, depth + 1)

for r in roots:
    walk(r, 0)
