"""多角度预览渲染: blender --background --python preview_multi.py -- <batch> <id>
输出 4 视角拼图:左前45°(主) / 正侧 / 右后45° / 顶部俯视"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
tail = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
batch, wid = (tail + ["lmg", "m249"])[:2]
src = open(os.path.join(HERE, "build_%s_batch.py" % batch), encoding="utf-8").read()
src = src.replace('if __name__ == "__main__":\n    main()', '')
exec(src)
BUILDERS[wid]()
rp = os.path.join(HERE, "render_preview.py")
exec(open(rp, encoding="utf-8").read().replace('if __name__ == "__main__":', 'if False:'))

import math
# 手枪枪长 ~0.25m,远机位会让枪缩成一点(与 preview_any 同规则)
# 左轮枪长 ~0.45m,与半自动同机位会被截断
D = 0.55 if batch == "pistol" else 2.0
if batch == "pistol" and wid in ("python", "sw686", "sw500"):
	D = 0.78
VIEWS = [
    ("hero",  (0, 0, 0.02), D, (-58, 0, 38)),    # 主视角:左前上
    ("side",  (0, 0, 0.02), D, (0, 0, 90)),      # 正侧面(垂直向下看 y 轴)
    ("rear",  (0, 0, 0.02), D * 1.1, (-50, 0, 150)),   # 右后上
    ("top",   (0, 0, 0.0),  D * 1.1, (4, 0, 0)),       # 近顶俯视(看导轨/盖面)
]
tiles = []
for tag, tgt, dist, ang in VIEWS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    exec(src)
    BUILDERS[wid]()
    setup_scene()
    setup_camera(target=tgt, dist=dist, angle=ang, lens=50)
    out = "E:/工作目录2/models_probe/multi_%s_%s.png" % (wid, tag)
    render(out, res=(800, 450))
    tiles.append(out)
    print("SHOT", tag)
# 拼图
from PIL import Image
imgs = [Image.open(t).resize((800, 450)) for t in tiles]
sheet = Image.new("RGB", (1600, 900), (12, 12, 14))
for i, im in enumerate(imgs):
    r, c = divmod(i, 2)
    sheet.paste(im, (c * 800, r * 450))
sheet.save("E:/工作目录2/models_probe/multi_%s.png" % wid)
print("DONE", wid)
