"""提取全枪械安装点数据(改装件系统数据源):
每把枪输出:
  rail   顶部导轨 {y: 齿顶高, z0, z1}  —— 取名字含 TopRail/FrameRail/RailTop/SlideRail 的对象
  hg     护木 {x: 半宽, y0: 底面, y1: 顶面, z0, z1} —— Handguard*/Foregrip*/HandguardTop 底板 等
  recv   机匣 {rear_z: 后端面, y_mid} —— Receiver*/Body(无托)/UpperReceiver
输出 JSON → tools/blender/mount_data.json(GDScript 侧生成 OPTIC_RAILS 等表)。
用法: blender --background --python extract_mount_data.py
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gunforge import *  # noqa

OUT = os.path.join(HERE, "mount_data.json")

def build_all_funcs():
    funcs = {}
    for batch in ["build_ar_batch", "build_smg_batch", "build_lmg_batch",
                  "build_sniper_batch", "build_dmr_batch", "build_pistol_batch",
                  "build_special_batch"]:
        src = open(os.path.join(HERE, batch + ".py"), encoding="utf-8").read()
        src = src.replace('if __name__ == "__main__":\n    main()', '')
        ns = {"__file__": os.path.join(HERE, batch + ".py")}
        exec(src, ns)
        for k, v in ns.items():
            if k == "BUILDERS" and isinstance(v, dict):
                funcs.update(v)
    # m4 单文件
    src = open(os.path.join(HERE, "build_m4.py"), encoding="utf-8").read()
    src = src.replace('if __name__ == "__main__":', 'if False:')
    ns = {"__file__": os.path.join(HERE, "build_m4.py")}
    exec(src, ns)
    for k, v in ns.items():
        if k.lower() in ("build_m4", "build") and callable(v):
            funcs["m4"] = v
    return funcs

def bbox(ob):
    from mathutils import Vector
    cs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    # 返回 Godot 语义: x, y(上), z(前-为负)
    # Blender(x=左右, y=-godot_z=前后, z=godot_y=竖直) → Godot 语义
    return (min(c.x for c in cs), max(c.x for c in cs),
            -max(c.y for c in cs), -min(c.y for c in cs),
            min(c.z for c in cs), max(c.z for c in cs))  # x0,x1,z0,z1,y0,y1

def main():
    import bpy
    funcs = build_all_funcs()
    data = {}
    for wid, fn in sorted(funcs.items()):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        try:
            fn()
        except Exception as e:
            print("BUILD FAIL", wid, e)
            continue
        bpy.context.view_layer.update()
        entry = {}
        # ---- 顶轨:齿顶平面 = 对象最高点(顶轨齿朝 +Y);侧轨/底轨排除(有 rotation)
        rails = []
        for ob in bpy.data.objects:
            if ob.type != "MESH":
                continue
            if any(k in ob.name for k in ("TopRail", "FrameRail", "RailTop", "SlideRail")):
                if "Side" in ob.name or "Bottom" in ob.name or "RailL" in ob.name or "RailR" in ob.name:
                    continue
                x0, x1, z0, z1, y0, y1 = bbox(ob)
                rails.append((round(y1, 5), round(z0, 5), round(z1, 5)))
        if rails:
            # 取最靠后的主轨(齿顶最高者;同名 join 组已合并为一个)
            best = max(rails, key=lambda r: r[0])
            entry["rail"] = {"y": best[0], "z0": best[1], "z1": best[2]}
        # ---- 护木:底面/侧面(镭射/握把落点)
        hgs = []
        for ob in bpy.data.objects:
            if ob.type != "MESH":
                continue
            if ob.name.startswith(("Handguard", "Foregrip")) or ob.name in ("HandguardTop",):
                x0, x1, z0, z1, y0, y1 = bbox(ob)
                hgs.append([x0, x1, y0, y1, min(z0, z1), max(z0, z1)])
        if hgs:
            x1m = max(h[1] for h in hgs)
            y0m = min(h[2] for h in hgs)
            y1m = max(h[3] for h in hgs)
            z0m = min(h[4] for h in hgs)
            z1m = max(h[5] for h in hgs)
            entry["hg"] = {"x": round(x1m, 5), "y0": round(y0m, 5), "y1": round(y1m, 5),
                           "z0": round(z0m, 5), "z1": round(z1m, 5)}
        # ---- 机匣:后端面(枪托锚点)
        for ob in bpy.data.objects:
            if ob.type != "MESH":
                continue
            if ob.name.startswith(("Receiver", "UpperReceiver")):
                x0, x1, z0, z1, y0, y1 = bbox(ob)
                entry["recv"] = {"rear_z": round(max(z0, z1), 5),
                                 "y_mid": round((y0 + y1) * 0.5, 5)}
                break
        if entry:
            data[wid] = entry
            print("%-8s %s" % (wid, json.dumps(entry)))
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("WROTE", OUT, len(data), "weapons")

main()
