#!/usr/bin/env python3
## 生成横扫（SWEEP）专属的扇形刀光 assets/art/sweep_effect.png
##
## 与近战月牙 slash_effect.png（浅蓝细月牙、±70°、外缘 124px）的区分：
##   横扫是「扇面波」——从本体中心填满到判定半径的金色扇形，满亮到 ±80°、
##   羽化到 ±88°，外缘一圈白热刃口。判定半角 80° 与满亮张角同源（画多大==判多大），
##   外缘半径 124px 与近战月牙同画布约定（FloatingWeapon.SWEEP_ART_OUTER）。
##
## 用法: python3 tools/gen_sweep_fx.py
## 改完必须同步: FloatingWeapon.gd 的 SWEEP_HALF_ANGLE / SWEEP_ART_OUTER，
##               tests/weapon_aim_check.gd 的 SWEEP_ART_HALF_DEG / SWEEP_ART_OUTER。

import math
from PIL import Image

SIZE = 256
CENTER = SIZE / 2.0
R_OUT = 124.0          # 外缘画布半径（== FloatingWeapon.SWEEP_ART_OUTER）
FULL_DEG = 80.0        # 满亮半角（== FloatingWeapon.SWEEP_HALF_ANGLE）
FEATHER_DEG = 88.0     # 羽化截止半角
R_FADE_IN = 14.0       # 顶点附近alpha淡入（别让扇面中心一个硬点）
R_FULL = 88.0          # 径向满亮起点
R_RIM0, R_RIM1 = 106.0, 119.0  # 白热刃口带

# 琥珀金（与 GameStyle.SWEEP 同族）：本体暖金，刃口白热
BODY = (255, 188, 84)
RIM = (255, 240, 205)


def smoothstep(a: float, b: float, x: float) -> float:
    if a == b:
        return 1.0 if x >= b else 0.0
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def main() -> None:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x + 0.5 - CENTER, y + 0.5 - CENTER
            r = math.hypot(dx, dy)
            if r > R_OUT or r < 1.0:
                continue
            # 0° = +X（贴图右方），y 向下与 Godot 旋转方向一致
            ang = abs(math.degrees(math.atan2(dy, dx)))
            if ang > FEATHER_DEG:
                continue
            # 角度羽化：满亮到 ±80°，80→88° 平滑收边
            a_ang = 1.0 - smoothstep(FULL_DEG, FEATHER_DEG, ang)
            # 径向：顶点淡入 → 满亮平台 → 外缘收光
            a_rad = smoothstep(R_FADE_IN * 0.4, R_FADE_IN, r)
            a_rad *= smoothstep(0.0, 1.0, min(1.0, r / R_FULL))
            a_rad *= 1.0 - smoothstep(R_RIM1, R_OUT, r)
            # 刃口白热带：颜色向 RIM 混、alpha 加强
            rim = smoothstep(R_RIM0, R_RIM1, r) * (1.0 - smoothstep(R_RIM1, R_OUT, r))
            alpha = a_ang * a_rad * (0.66 + 0.34 * rim)
            if alpha <= 0.004:
                continue
            cr = int(BODY[0] + (RIM[0] - BODY[0]) * rim)
            cg = int(BODY[1] + (RIM[1] - BODY[1]) * rim)
            cb = int(BODY[2] + (RIM[2] - BODY[2]) * rim)
            px[x, y] = (cr, cg, cb, int(alpha * 255))
    img.save("assets/art/sweep_effect.png")
    print("sweep_effect.png 生成完毕：%dx%d，满亮 ±%.0f°、羽化 ±%.0f°、外缘 %.0fpx" % (
        SIZE, SIZE, FULL_DEG, FEATHER_DEG, R_OUT))


if __name__ == "__main__":
    main()
