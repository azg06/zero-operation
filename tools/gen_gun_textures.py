"""
枪械专用 PBR 贴图生成器(程序化,零外部依赖,无版权问题)

为什么不用现成的 metal_plate:
  项目原来所有枪族共用 metal_plate_diff / plywood_diff,那是建筑用「压花钢板 + 胶合板」
  贴图 —— 花纹尺度是按几米大的墙面设计的,贴到 5cm 的机匣上,纹理被放大到荒谬的程度,
  加上强烈的轧制凹凸,看起来就是钢筋混凝土。真枪的表面是:阳极氧化铝的细密哑光、
  磷化钢的均匀微粒、聚合物的磨砂颗粒、木托的长纤维纹理 —— 尺度都在 0.1~1mm 量级。

做法:
  1. 高度图用「周期性正弦叠加」合成 fBm —— 频率取整数保证严格可平铺(无缝),
     各向异性控制拉丝方向。
  2. 颜色图 = 基色 × 高度调制 + 细微色斑(模拟氧化/磨损不均)。
  3. 法线图 = 高度图中心差分(Godot/OpenGL 约定,绿通道 +Y 朝上)。
"""

import os
import numpy as np
from PIL import Image

OUT = "E:/工作目录2/zero/steel_frontline_godot/textures"
SIZE = 1024


def periodic_fbm(size, freq_base, octaves, seed, aniso=(1.0, 1.0), waves=4):
    """
    可平铺的分形噪声。关键:所有方向频率取整数,sin 在 [0,2π] 上严格周期,
    所以贴图左右/上下边界天然接续,不会出现接缝。
    aniso: (x 方向倍率, y 方向倍率) —— 用来把噪声拉成各向异性的拉丝。
    """
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size * 2.0 * np.pi
    out = np.zeros((size, size), np.float32)
    amp_sum = 0.0
    amp = 1.0
    for o in range(octaves):
        f = int(freq_base * (2 ** o))
        fx = max(1, int(f * aniso[0]))
        fy = max(1, int(f * aniso[1]))
        layer = np.zeros_like(out)
        for _ in range(waves):
            dx = int(rng.integers(-fx, fx + 1))
            dy = int(rng.integers(-fy, fy + 1))
            ph = float(rng.uniform(0, 2 * np.pi))
            layer += np.sin(dx * xx + dy * yy + ph)
        out += layer * amp
        amp_sum += amp
        amp *= 0.5
    out /= amp_sum
    return out


def height_to_normal(h, strength=1.0):
    """高度图 -> 法线图(Godot/OpenGL 约定:绿通道 +Y 朝上)"""
    drow, dcol = np.gradient(h.astype(np.float32))
    nx = -dcol * strength
    ny = drow * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    r = np.clip(nx * 0.5 + 0.5, 0, 1)
    g = np.clip(ny * 0.5 + 0.5, 0, 1)
    b = np.clip(nz * 0.5 + 0.5, 0, 1)
    return np.stack([r, g, b], axis=-1)


def save_diff(arr, name):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), mode="RGB")
    p = os.path.join(OUT, name + "_diff.jpg")
    img.save(p, quality=92, subsampling=0)
    print("  diff", p, "%.0f KB" % (os.path.getsize(p) / 1024))


def save_nor(arr, name):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), mode="RGB")
    p = os.path.join(OUT, name + "_nor.jpg")
    img.save(p, quality=92, subsampling=0)
    print("  nor ", p, "%.0f KB" % (os.path.getsize(p) / 1024))


def build(name, base_rgb, h_layers, rough_layers, strength, seed=0):
    """
    h_layers:    [(高度图, 权重), ...] 合成最终高度
    rough_layers:[(噪声, 权重), ...] 用来调制明度(粗糙度视觉差异)
    """
    print("[%s]" % name)
    h = np.zeros((SIZE, SIZE), np.float32)
    for layer, w in h_layers:
        h += layer * w
    h = (h - h.min()) / max(1e-6, h.max() - h.min())

    r = np.zeros((SIZE, SIZE), np.float32)
    for layer, w in rough_layers:
        r += layer * w
    r = (r - r.min()) / max(1e-6, r.max() - r.min())

    # 颜色:基色 × 高度调制(凹处略暗)+ 大尺度色斑(氧化不均)
    base = np.array(base_rgb, np.float32)
    tint = 0.82 + 0.36 * h                      # 高度 -> 明暗
    patch = 0.94 + 0.12 * r                     # 低频色斑
    col = base[None, None, :] * tint[:, :, None] * patch[:, :, None]
    # 轻微色相抖动,避免死板的纯色
    jitter = (r - 0.5) * 0.05
    col = col + jitter[:, :, None] * base[None, None, :] * 0.5
    save_diff(col, name)
    save_nor(height_to_normal(h, strength), name)


def main():
    os.makedirs(OUT, exist_ok=True)
    S = SIZE

    # ---------- gun_metal:阳极氧化铝 / 机匣钢 ----------
    # 细密水平拉丝(x 方向拉长 -> aniso x 小 y 大)+ 极细颗粒
    brush = periodic_fbm(S, freq_base=10, octaves=5, seed=11, aniso=(0.12, 3.0), waves=6)
    grain = periodic_fbm(S, freq_base=90, octaves=3, seed=12, aniso=(1.0, 1.0), waves=4)
    patch = periodic_fbm(S, freq_base=3, octaves=3, seed=13, aniso=(1.0, 1.0), waves=3)
    build("gun_metal", (0.604, 0.627, 0.659),
          [(brush, 0.62), (grain, 0.38)],
          [(patch, 1.0), (grain, 0.25)], strength=1.6)

    # ---------- gun_dark:磷化 / 烤蓝深钢 ----------
    # 比 metal 更细更均匀的微粒,拉丝弱一些
    brush2 = periodic_fbm(S, freq_base=14, octaves=5, seed=21, aniso=(0.2, 2.4), waves=6)
    grain2 = periodic_fbm(S, freq_base=120, octaves=3, seed=22, aniso=(1.0, 1.0), waves=4)
    patch2 = periodic_fbm(S, freq_base=4, octaves=3, seed=23, aniso=(1.0, 1.0), waves=3)
    build("gun_dark", (0.353, 0.369, 0.392),
          [(brush2, 0.48), (grain2, 0.52)],
          [(patch2, 1.0), (grain2, 0.30)], strength=1.35)

    # ---------- gun_poly:聚合物(磨砂颗粒) ----------
    # 各向同性细颗粒 —— 聚合物没有拉丝,只有均匀的磨砂/橘皮
    fine = periodic_fbm(S, freq_base=150, octaves=4, seed=31, aniso=(1.0, 1.0), waves=5)
    mid = periodic_fbm(S, freq_base=40, octaves=3, seed=32, aniso=(1.0, 1.0), waves=4)
    patch3 = periodic_fbm(S, freq_base=3, octaves=3, seed=33, aniso=(1.0, 1.0), waves=3)
    build("gun_poly", (0.243, 0.259, 0.282),
          [(fine, 0.70), (mid, 0.30)],
          [(patch3, 1.0), (mid, 0.20)], strength=1.15)

    # ---------- gun_wood:枪托木纹 ----------
    # 沿 y 拉长的长纤维条纹 + 年轮扰动
    fiber = periodic_fbm(S, freq_base=6, octaves=5, seed=41, aniso=(3.5, 0.10), waves=6)
    ring = periodic_fbm(S, freq_base=2, octaves=3, seed=42, aniso=(1.2, 0.35), waves=3)
    pore = periodic_fbm(S, freq_base=180, octaves=2, seed=43, aniso=(1.0, 1.0), waves=4)
    h_wood = fiber * 0.66 + ring * 0.34
    # 木纹颜色:基色随纤维明暗在两种木色间过渡
    light = np.array([0.686, 0.494, 0.302], np.float32)
    darkc = np.array([0.404, 0.267, 0.145], np.float32)
    t = np.clip((h_wood - h_wood.min()) / max(1e-6, h_wood.max() - h_wood.min()), 0, 1)
    col = light[None, None, :] * t[:, :, None] + darkc[None, None, :] * (1 - t[:, :, None])
    col = col * (0.92 + 0.16 * (pore - pore.min()) / max(1e-6, pore.max() - pore.min()))[:, :, None]
    print("[gun_wood]")
    save_diff(col, "gun_wood")
    save_nor(height_to_normal(h_wood * 0.8 + pore * 0.2, 1.5), "gun_wood")

    # ---------- gun_brass:黄铜(弹壳/弹匣) ----------
    bb = periodic_fbm(S, freq_base=16, octaves=4, seed=51, aniso=(0.25, 2.0), waves=5)
    bg = periodic_fbm(S, freq_base=110, octaves=3, seed=52, aniso=(1.0, 1.0), waves=4)
    bp = periodic_fbm(S, freq_base=4, octaves=3, seed=53, aniso=(1.0, 1.0), waves=3)
    build("gun_brass", (0.816, 0.690, 0.439),
          [(bb, 0.55), (bg, 0.45)],
          [(bp, 1.0), (bg, 0.28)], strength=1.3)

    # ---------- gun_chrome:枪管/枪机镀铬(镜面 + 极轻拉丝) ----------
    cb = periodic_fbm(S, freq_base=20, octaves=4, seed=61, aniso=(0.1, 3.2), waves=5)
    cg = periodic_fbm(S, freq_base=140, octaves=2, seed=62, aniso=(1.0, 1.0), waves=4)
    cp = periodic_fbm(S, freq_base=3, octaves=3, seed=63, aniso=(1.0, 1.0), waves=3)
    build("gun_chrome", (0.847, 0.867, 0.886),
          [(cb, 0.40), (cg, 0.60)],
          [(cp, 1.0), (cg, 0.15)], strength=0.9)

    print("DONE")


if __name__ == "__main__":
    main()
