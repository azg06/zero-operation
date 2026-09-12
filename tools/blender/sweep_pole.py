"""
扫描左肘的鼓出方向(pole) —— 找一组让"左前臂与枪下方附件(两脚架/弹匣/前握把)"
相交最少的参数。

背景: 排除"手部区域"后, 55 把里只剩 8 把残留相交, 且**全部集中在枪身正下方的附件**上
(awm/l115/m40 两脚架腿, mg3/mg42 两脚架座, mp7/pp2000 弹匣, vector 前握把)。
左前臂要从下方伸到护木, 那片区域就挂着这些附件 —— 只能靠**调整肘的鼓出方向**
让前臂从更外侧/更后方绕过去。

用法: blender --background --python sweep_pole.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from mathutils import Vector  # noqa: E402
import check_hand_clip as C  # noqa: E402
import render_fp_hold as H  # noqa: E402

GUNS = ["awm", "l115", "m40", "mg3", "mg42", "mp7", "pp2000", "vector"]

def vm2bl(v):
    """vm(Godot 相机空间) → Blender: (x, y, z)_vm → (x, -z, y)_blender"""
    return Vector((v[0], -v[2], v[1]))


# ⚠ 下面写的是 **vm 坐标**(与 fp_arms.gd::POLE_L 一致), 用前必须经 vm2bl 转换 ——
#   上一版直接把它们当 Blender 坐标传进 H.POLE_L, 扫出来的是"肘往上鼓"的错姿势
#   (第一组即当前值的坐标却给出 288, 而真实值只有 9), 整轮扫描作废。
CANDS = [
    Vector((-0.30, -0.90, 0.10)),     # 当前值
    Vector((-0.50, -0.83, 0.10)),
    Vector((-0.70, -0.68, 0.10)),
    Vector((-0.85, -0.50, 0.10)),
    Vector((-0.50, -0.83, 0.45)),     # 更靠后
    Vector((-0.70, -0.68, 0.55)),
]


def main():
    anchors = H.load_anchors()
    orig = H.POLE_L
    print("[SWEEP-P] 对 %d 把[枪下方附件]问题枪扫描左肘方向" % len(GUNS))
    for pole_vm in CANDS:
        pole = vm2bl(pole_vm)
        H.POLE_L = pole
        tot = 0
        detail = []
        for g in GUNS:
            rep = C.check_one(g, anchors)
            if rep is None:
                continue
            n = max(rep["LF"][0], rep["RF"][0])
            tot += n
            detail.append("%s:%d" % (g, n))
        print("[SWEEP-P] pole_vm=%s → bl=%s  合计=%-5d  %s" % (
            tuple(round(v, 2) for v in pole_vm), tuple(round(v, 2) for v in pole), tot,
            " ".join(detail)))
    H.POLE_L = orig


if __name__ == "__main__":
    main()
