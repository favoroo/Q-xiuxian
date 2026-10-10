#!/usr/bin/env python3
"""生成虚拟摇杆、近战剑气弧光、菱形水晶及子弹底图的【冷冽国风·纯矢量】高清素材
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw

ART_DIR = "assets/art"

COL_INK = (15, 20, 28, 255)
COL_PAPER = (240, 245, 250, 255)
COL_GOLD = (235, 195, 70, 255)
COL_GOLD_DIM = (160, 130, 45, 255)
COL_JADE = (90, 215, 165, 255)
COL_NAVY = (45, 90, 165, 255)
COL_CYAN = (100, 200, 255, 255)
COL_WHITE = (255, 255, 255, 255)

def super_canvas(w, h, scale=4):
    sw, sh = w * scale, h * scale
    img = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    return img, d, scale

def downscale_save(img, dst_path, target_size, scale=4):
    res = img.resize(target_size, Image.Resampling.LANCZOS)
    res.save(dst_path, "PNG")
    print(f"[VectorGen] 导出: {dst_path} {target_size}")

# 1. 虚拟摇杆底座 joy_base.png (128x128)
def gen_joy_base():
    img, d, s = super_canvas(128, 128)
    cx, cy = 64 * s, 64 * s
    r_outer = 58 * s
    r_inner = 46 * s
    r_core = 36 * s

    # 半透明玄墨底盘
    d.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], fill=(15, 20, 30, 160))
    # 暗金外圈
    d.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], outline=COL_GOLD, width=int(2.5*s))

    # 四方罗盘阵眼刻度 (北南东西)
    for deg in [0, 90, 180, 270]:
        rad = math.radians(deg)
        p1 = (cx + (r_outer - 8*s) * math.cos(rad), cy + (r_outer - 8*s) * math.sin(rad))
        p2 = (cx + (r_outer + 3*s) * math.cos(rad), cy + (r_outer + 3*s) * math.sin(rad))
        d.line([p1, p2], fill=COL_PAPER, width=int(2.5*s))

    # 内圈幽蓝符阵线
    d.ellipse([cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner], outline=(90, 215, 165, 140), width=int(1.5*s))
    d.ellipse([cx - r_core, cy - r_core, cx + r_core, cy + r_core], outline=(45, 90, 165, 100), width=int(1.2*s))

    downscale_save(img, os.path.join(ART_DIR, "joy_base.png"), (128, 128))

# 2. 虚拟摇杆旋钮 joy_knob.png (64x64)
def gen_joy_knob():
    img, d, s = super_canvas(64, 64)
    cx, cy = 32 * s, 32 * s
    r_outer = 27 * s
    r_mid = 21 * s
    r_core = 11 * s

    # 玄墨基座
    d.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], fill=COL_INK)
    d.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], outline=COL_GOLD, width=int(2.2*s))

    # 中层骨白切面
    d.ellipse([cx - r_mid, cy - r_mid, cx + r_mid, cy + r_mid], fill=(45, 55, 75, 255))
    d.ellipse([cx - r_mid, cy - r_mid, cx + r_mid, cy + r_mid], outline=COL_PAPER, width=int(1.5*s))

    # 中心寒泉灵核
    d.ellipse([cx - r_core, cy - r_core, cx + r_core, cy + r_core], fill=COL_JADE)
    d.ellipse([cx - 4*s, cy - 4*s, cx + 4*s, cy + 4*s], fill=COL_WHITE)

    downscale_save(img, os.path.join(ART_DIR, "joy_knob.png"), (64, 64))

# 3. 近战挥斩剑气月牙 slash_effect.png (64x64)
# 必须严格符合：中心 (32, 32)，外径 ~31px，张角 -70° ~ +70°
def gen_slash_effect():
    img, d, s = super_canvas(64, 64)
    cx, cy = 32 * s, 32 * s
    r_outer_max = 30.8 * s
    r_inner_base = 22.0 * s

    outer_pts = []
    inner_pts = []
    segs = 40
    half_angle = math.radians(69.0)

    for i in range(segs + 1):
        t = -half_angle + (2 * half_angle) * (i / segs)
        # 尖端逐渐收细
        fade = 1.0 - (abs(t) / half_angle) ** 2
        r_out = r_outer_max - (1.0 - fade) * 2.0 * s
        r_in = r_inner_base + fade * 3.5 * s
        if r_in > r_out - 1.0*s:
            r_in = r_out - 1.0*s

        outer_pts.append((cx + r_out * math.cos(t), cy + r_out * math.sin(t)))
        inner_pts.append((cx + r_in * math.cos(t), cy + r_in * math.sin(t)))

    crescent = outer_pts + list(reversed(inner_pts))
    # 剑气外层幽蓝光晕
    d.polygon(crescent, fill=(100, 200, 255, 180))

    # 剑气核心纯白锋刃线 (外缘 1.5px 纯白如霜)
    d.line(outer_pts, fill=COL_PAPER, width=int(2.2*s))
    d.line(outer_pts[:10] + outer_pts[-10:], fill=COL_WHITE, width=int(1.5*s))

    downscale_save(img, os.path.join(ART_DIR, "slash_effect.png"), (64, 64))

# 4. 菱形水晶掉落物 gem_blue.png & gem_gold.png (48x48)
def gen_rhombus_gem(is_gold=False):
    img, d, s = super_canvas(48, 48)
    cx, cy = 24 * s, 24 * s
    rx, ry = 14 * s, 21 * s

    pts_top = [(cx, cy - ry), (cx + rx, cy), (cx, cy)]
    pts_bot = [(cx, cy + ry), (cx + rx, cy), (cx, cy)]
    pts_left_top = [(cx, cy - ry), (cx - rx, cy), (cx, cy)]
    pts_left_bot = [(cx, cy + ry), (cx - rx, cy), (cx, cy)]

    if is_gold:
        col_light = (255, 230, 110, 255)
        col_mid = (235, 195, 70, 255)
        col_dark = (165, 125, 35, 255)
        col_shadow = (95, 70, 20, 255)
        col_glow = (255, 215, 60, 60)
    else:
        col_light = (180, 235, 255, 255)
        col_mid = (90, 190, 255, 255)
        col_dark = (35, 115, 215, 255)
        col_shadow = (15, 45, 105, 255)
        col_glow = (80, 180, 255, 60)

    # 外晕
    d.polygon([(cx, cy - ry - 3*s), (cx + rx + 3*s, cy), (cx, cy + ry + 3*s), (cx - rx - 3*s, cy)], fill=col_glow)

    # 4 切面绘制
    d.polygon(pts_top, fill=col_light)
    d.polygon(pts_left_top, fill=col_mid)
    d.polygon(pts_bot, fill=col_dark)
    d.polygon(pts_left_bot, fill=col_shadow)

    # 黑色利落外框
    poly = [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]
    d.polygon(poly, outline=COL_INK, width=int(2*s))

    # 中脊骨白/金高光棱线
    d.line([(cx, cy - ry), (cx, cy + ry)], fill=COL_WHITE, width=int(1.8*s))
    d.line([(cx - rx, cy), (cx + rx, cy)], fill=col_light, width=int(1.2*s))

    name = "gem_gold.png" if is_gold else "gem_blue.png"
    downscale_save(img, os.path.join(ART_DIR, name), (48, 48))

if __name__ == "__main__":
    os.makedirs(ART_DIR, exist_ok=True)
    gen_joy_base()
    gen_joy_knob()
    gen_slash_effect()
    gen_rhombus_gem(False)
    gen_rhombus_gem(True)
    print("UI 与特效矢量素材生成完毕！")
