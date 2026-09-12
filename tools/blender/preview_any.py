"""渲染任意批次的任意枪: blender --background --python preview_any.py -- <batch> <id>"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
argv = sys.argv
tail = argv[argv.index("--") + 1:] if "--" in argv else []
batch, wid = (tail + ["pistol", "m1911"])[:2]
src = open(os.path.join(HERE, "build_%s_batch.py" % batch), encoding="utf-8").read()
src = src.replace('if __name__ == "__main__":\n    main()', '')
exec(src)
BUILDERS[wid]()
names = sorted(o.name for o in bpy.data.objects)
# 材质上色已由 build 内完成;渲染
import importlib
rp = os.path.join(HERE, "render_preview.py")
exec(open(rp, encoding="utf-8").read().replace('if __name__ == "__main__":', 'if False:'))
setup_scene()
# 手枪枪长只有 ~0.25m,远机位会让枪缩成一个点
pd = 0.55 if batch == "pistol" else 2.0
if batch == "pistol" and wid in ("python", "sw686", "sw500"):
	pd = 0.78
setup_camera(target=(0, 0, 0.02), dist=pd, angle=(-58, 0, 34), lens=50)
render("E:/工作目录2/models_probe/preview_%s.png" % wid)
print("DONE", wid)
