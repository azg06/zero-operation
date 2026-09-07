# -*- coding: utf-8 -*-
"""三联对比图:参考游戏 | 修改前 x=0.17 | 修改后 x=0.05,画中心线+偏移标注"""
from PIL import Image, ImageDraw, ImageFont

H = 608
FONT = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 26)
FONT_S = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 20)

def load_fit(path):
    im = Image.open(path).convert("RGB")
    w = int(im.width * H / im.height)
    return im.resize((w, H), Image.LANCZOS)

def annotate(im, title, sub, offset_pct):
    d = ImageDraw.Draw(im)
    W = im.width
    cx = W // 2
    # 中心线(黄,虚线)
    for y in range(0, H, 18):
        d.line([(cx, y), (cx, y + 9)], fill=(255, 220, 0), width=2)
    # 枪中轴参考线(红,垂直标尺在标题栏下)
    bar_y = 86
    d.line([(cx, bar_y), (cx, bar_y + 26)], fill=(255, 220, 0), width=4)
    # 标题栏
    d.rectangle([0, 0, W, 64], fill=(0, 0, 0))
    d.text((12, 6), title, font=FONT, fill=(255, 255, 255))
    d.text((12, 36), sub, font=FONT_S, fill=(180, 220, 255))
    return im

ref = load_fit(r"C:\Users\gza\Downloads\1572225272_599283.jpg")
ref = annotate(ref, "参考(战地/全境系)", "枪中轴 ≈ 中心偏右 9%", 9)
bef = load_fit(r"E:\工作目录2\models_probe\qa_hip_before_x017.png")
bef = annotate(bef, "修改前 HIP x=0.17", "枪中轴 ≈ 中心偏右 31%", 31)
aft = load_fit(r"E:\工作目录2\models_probe\qa_hip_after_x005.png")
aft = annotate(aft, "修改后 HIP x=0.05", "枪中轴 ≈ 中心偏右 8%", 8)

gap = 8
W = ref.width + bef.width + aft.width + gap * 2
canvas = Image.new("RGB", (W, H + 8), (20, 20, 20))
x = 0
for im in (ref, bef, aft):
    canvas.paste(im, (x, 8))
    x += im.width + gap
canvas.save(r"E:\工作目录2\models_probe\qa_hip_compare.png")
print("saved", canvas.size)
