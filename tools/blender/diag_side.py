import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
tail = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
batch, wid = (tail + ["pistol", "m1911"])[:2]
src = open(os.path.join(HERE, "build_%s_batch.py" % batch), encoding="utf-8").read()
src = src.replace('if __name__ == "__main__":\n    main()', '')
exec(src)
BUILDERS[wid]()
rp = os.path.join(HERE, "render_preview.py")
exec(open(rp, encoding="utf-8").read().replace('if __name__ == "__main__":', 'if False:'))
D = 0.55 if batch == "pistol" else 2.0
setup_scene()
setup_camera(target=(0, 0, 0.0), dist=D, angle=(0, 0, 90), lens=50)
render("E:/工作目录2/models_probe/diag_side_%s.png" % wid, res=(1600, 400))
print("DONE")
