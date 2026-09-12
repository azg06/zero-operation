"""生成日语标识贴图(秋津市沉浸感)。
产出 textures/jp_sign_*.png —— 4x4 图集(每格 256px),供 jp_common.sign_panel 按格取 UV。
字体:Windows YuGothic(黑体)/ MS Gothic。运行:
  python gen_jp_signs.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = "E:/工作目录2/zero/steel_frontline_godot/textures"
FONTS = ["C:/Windows/Fonts/YuGothB.ttc", "C:/Windows/Fonts/msgothic.ttc",
         "C:/Windows/Fonts/YuGothM.ttc", "C:/Windows/Fonts/meiryo.ttc"]
CELL = 256
GRID = 4

_font_cache = {}


def font(sz):
    if sz in _font_cache:
        return _font_cache[sz]
    for fp in FONTS:
        if os.path.exists(fp):
            try:
                _font_cache[sz] = ImageFont.truetype(fp, sz, index=0)
                return _font_cache[sz]
            except Exception:
                continue
    raise RuntimeError("无可用日文字体")


def draw_center(d, box, text, f, fill, vert=False, spacing=1.06):
    """居中绘制(vert=True 为縦書き,逐字竖排)。"""
    x0, y0, x1, y1 = box
    if not vert:
        bb = d.textbbox((0, 0), text, font=f)
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        d.text((x0 + (x1 - x0 - w) / 2 - bb[0], y0 + (y1 - y0 - h) / 2 - bb[1]),
               text, font=f, fill=fill)
        return
    # 縦書き
    n = len(text)
    sizes = []
    for ch in text:
        bb = d.textbbox((0, 0), ch, font=f)
        sizes.append((bb[2] - bb[0], bb[3] - bb[1], bb[0], bb[1]))
    lh = int(f.size * spacing)
    total = lh * n
    cy = y0 + ((y1 - y0) - total) / 2
    for i, ch in enumerate(text):
        w, h, ox, oy = sizes[i]
        d.text((x0 + (x1 - x0 - w) / 2 - ox, cy + i * lh + (lh - h) / 2 - oy),
               ch, font=f, fill=fill)


def make_sheet(fname, items, bg="#ffffff", title_dark=False):
    """items: [(text, fg, bg, vert), ...] 共 16 格。"""
    W = CELL * GRID
    im = Image.new("RGB", (W, W), bg)
    d = ImageDraw.Draw(im)
    for i, it in enumerate(items[:GRID * GRID]):
        text, fg, bgi = it[0], it[1], it[2]
        vert = it[3] if len(it) > 3 else True
        cx, cy = i % GRID, i // GRID
        x0, y0 = cx * CELL, cy * CELL
        d.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=bgi)
        # 边框(招牌外框)
        d.rectangle([x0 + 4, y0 + 4, x0 + CELL - 5, y0 + CELL - 5],
                    outline="#20242a", width=5)
        n = max(1, len(text))
        if vert:
            f = font(min(72, int(CELL * 0.78 / n)))
        else:
            f = font(min(60, int(CELL * 0.80 / max(1.0, n * 0.62))))
        draw_center(d, (x0 + 14, y0 + 14, x0 + CELL - 14, y0 + CELL - 14), text, f, fg, vert)
    im.save(os.path.join(OUT, fname))
    print("  %-24s %dx%d (%d 格)" % (fname, W, W, min(16, len(items))))


# ---------------- 店铺招牌(縦書き) ----------------
shop = [
    ("ラーメン", "#c8202a", "#f5f1e8"), ("居酒屋", "#f7f3ea", "#a8181f"),
    ("薬局", "#f7f7f2", "#1d7a3c"), ("コンビニ", "#ffffff", "#1b4fa0"),
    ("カラオケ", "#fdf3fa", "#b6208a"), ("パチンコ", "#f7d117", "#1a1a1a"),
    ("銀行", "#f7f7f2", "#123f8a"), ("郵便局", "#c8202a", "#f5f1e8"),
    ("カフェ", "#f7f2e6", "#5a3a22"), ("書店", "#f2f5fa", "#1a2a55"),
    ("花屋", "#1d7a3c", "#f6f2e2"), ("銭湯", "#fdf6ec", "#d4641a"),
    ("食堂", "#1a1a1a", "#f2c81e"), ("そば", "#f4f1e6", "#22502e"),
    ("寿司", "#f7f3ea", "#12305a"), ("理容室", "#123f8a", "#f5f1e8"),
]
# ---------------- 广告牌 ----------------
ad = [
    ("新発売\n秋津サイダー", "#0a2a4a", "#eaf3ff", False), ("大感謝祭\n全品20%OFF", "#ffffff", "#c8202a", False),
    ("引越しは\nお任せ", "#1a3a6a", "#ffe8c8", False), ("週末限定\n半額", "#ffffff", "#d4641a", False),
    ("お部屋探し\nは秋津不動産", "#20402a", "#f0f6e8", False), ("新規開店\nラーメン一番", "#f7d117", "#1a1a1a", False),
    ("スタッフ\n急募", "#0a2a4a", "#fefefe", False), ("車検\nお得", "#ffffff", "#123f8a", False),
    ("携帯電話\n新規0円", "#1a1a1a", "#7de0ff", False), ("沖縄ツアー\n3日間", "#1a4a8a", "#ffe9b0", False),
    ("保険の\n見直し", "#1a5a3a", "#f5fff5", False), ("英会話\n無料体験", "#3a1a6a", "#fdf3ff", False),
    ("24時間\n営業中", "#1a1a1a", "#f7c81e", False), ("生ビール\n半額", "#ffffff", "#c8202a", False),
    ("宅配ピザ\n30分", "#ffffff", "#1a7a3a", False), ("リフォーム\n相談無料", "#1a3a5a", "#f0f4f8", False),
]
# ---------------- 告示/警告 ----------------
notice = [
    ("立入禁止", "#ffffff", "#c8202a", True), ("工事中", "#1a1a1a", "#f2c81e", False),
    ("注意", "#1a1a1a", "#f7c81e", False), ("駐車禁止", "#ffffff", "#c8202a", True),
    ("禁煙", "#ffffff", "#c8202a", False), ("火気厳禁", "#ffffff", "#c8202a", True),
    ("足元注意", "#1a1a1a", "#f2c81e", False), ("危険", "#ffffff", "#d4641a", False),
    ("関係者以外\n立入禁止", "#ffffff", "#c8202a", False), ("求人", "#1a1a1a", "#f7d117", False),
    ("本日休業", "#1a1a1a", "#f2f2ee", True), ("閉店\nしました", "#f7f2e6", "#3a3a3a", False),
    ("清掃中", "#1a3a6a", "#f2f6fa", False), ("電気工事中", "#1a1a1a", "#f2c81e", False),
    ("ゴミ捨て\n禁止", "#ffffff", "#c8202a", False), ("開店\n準備中", "#5a3a22", "#f7f2e6", False),
]
# ---------------- 道路/交通标识 ----------------
road = [
    ("止まれ", "#ffffff", "#c8202a", False), ("一時停止", "#ffffff", "#c8202a", False),
    ("秋津駅", "#1a1a1a", "#e8eef4", False), ("国道\n246号", "#ffffff", "#1b4fa0", False),
    ("県道\n12号", "#1a1a1a", "#f2f2ee", False), ("歩行者\n天国", "#ffffff", "#1d7a3c", False),
    ("通学路", "#1a1a1a", "#f7c81e", False), ("踏切\n注意", "#1a1a1a", "#f2c81e", False),
    ("駐車場", "#ffffff", "#1b4fa0", False), ("バス停", "#1a1a1a", "#e8eef4", False),
    ("タクシー\n乗場", "#1a1a1a", "#f7d117", False), ("秋津神社", "#1a1a1a", "#f5efe2", False),
    ("西念寺", "#1a1a1a", "#f5efe2", False), ("汐見公園", "#1a1a1a", "#e8f2e4", False),
    ("中央商店街", "#ffffff", "#a8181f", False), ("この先\n工事中", "#1a1a1a", "#f2c81e", False),
]
# ---------------- 商店街横断幕(横長) ----------------
banner = [
    ("秋津本町 商店街", "#ffffff", "#a8181f", False), ("交通安全 運動中", "#ffffff", "#1b4fa0", False),
    ("第38回 秋津まつり", "#ffffff", "#c8202a", False), ("歓迎 新入生", "#1a1a1a", "#f7d117", False),
    ("節電にご協力ください", "#ffffff", "#1d7a3c", False), ("防災訓練 実施中", "#1a1a1a", "#f2c81e", False),
    ("商店街 大売出し", "#ffffff", "#d4641a", False), ("自転車は降りて通行", "#ffffff", "#20402a", False),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    print("生成日语标识贴图 →", OUT)
    make_sheet("jp_sign_shop.png", shop)
    make_sheet("jp_sign_ad.png", ad)
    make_sheet("jp_sign_notice.png", notice)
    make_sheet("jp_sign_road.png", road)
    make_sheet("jp_sign_banner.png", banner)

    # 地面散落物:报纸/传单页(细密文字栏)
    import random
    rnd = random.Random(20260910)
    W = 512
    im = Image.new("RGB", (W, W), "#d8d2c4")
    d = ImageDraw.Draw(im)
    f = font(9)
    fb = font(16)
    for page in range(4):
        px, py = (page % 2) * 256, (page // 2) * 256
        d.rectangle([px, py, px + 255, py + 255], fill="#e6e1d2", outline="#9a9486")
        d.text((px + 10, py + 8), rnd.choice(["秋津新聞", "毎日秋津", "読売夕刊", "朝日地域版"]),
               font=fb, fill="#22262c")
        d.line([px + 10, py + 32, px + 246, py + 32], fill="#5a5a52", width=2)
        for col in range(3):
            cx = px + 12 + col * 80
            for row in range(28):
                wid = rnd.randint(34, 66)
                d.rectangle([cx, py + 40 + row * 7, cx + wid, py + 44 + row * 7],
                            fill="#6e6a60" if rnd.random() > 0.12 else "#3a3a34")
    im.save(os.path.join(OUT, "jp_flyer.png"))
    print("  %-24s %dx%d (4 版报纸/传单)" % ("jp_flyer.png", W, W))
    print("完成")


if __name__ == "__main__":
    main()
