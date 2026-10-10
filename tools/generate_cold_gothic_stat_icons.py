#!/usr/bin/env python3
"""生成 8 大核心属性的空洞冷冽国风高精图标 (128x128 PNG)
风格标准：
- 色彩严格对齐 GameStyle (虚空黑 INK, 骨白 PAPER, 暗金 GOLD, 寒玉 JADE, 幽蓝 NAVY, 煞血 CRIMSON)
- 造型硬挺内敛，无杂乱色块，线条利落，高对比度
- 纯透明背景，中心饱满，尺寸 128x128
"""
import math
import os
from PIL import Image, ImageDraw

OUTPUT_DIR = "assets/art"

# 调色板定义
COL_INK = (15, 20, 30, 255)         # 虚空黑
COL_PAPER = (235, 240, 245, 255)    # 骨白
COL_PAPER_DIM = (180, 195, 210, 255)# 骨灰/阴影
COL_GOLD = (235, 195, 70, 255)      # 暗金
COL_GOLD_DIM = (160, 130, 45, 255)  # 沉金
COL_JADE = (90, 215, 165, 255)      # 寒玉碧绿
COL_JADE_DIM = (45, 130, 95, 255)   # 深墨玉
COL_NAVY = (45, 90, 165, 255)       # 幽蓝
COL_CRIMSON = (215, 65, 65, 255)    # 煞血朱砂
COL_WHITE = (255, 255, 255, 255)    # 纯白高光

def create_super_canvas(scale=4):
    size = 128 * scale
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    return img, draw, scale

def save_and_downscale(img, filename, scale=4):
    target = (128, 128)
    resampled = img.resize(target, Image.Resampling.LANCZOS)
    path = os.path.join(OUTPUT_DIR, filename)
    resampled.save(path, "PNG")
    print(f"[IconGen] 已生成: {path}")

# 1. 攻击 (icon_atk.png): 断空古剑意 —— 斜跨冷银双刃古剑 + 破空剑芒
def gen_atk():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s
    # 剑刃主轴 (从左下 (-38, 38) 刺向右上 (38, -38))
    # 骨白剑刃右半部
    blade_r = [
        (cx + 42*s, cy - 42*s), # 剑尖
        (cx - 18*s, cy + 18*s),
        (cx - 24*s, cy + 14*s),
        (cx - 20*s, cy + 20*s),
    ]
    # 完整对称双刃剑身
    blade_poly = [
        (cx + 44*s, cy - 44*s), # 锐利锋芒
        (cx + 14*s, cy - 34*s),
        (cx - 20*s, cy + 10*s),
        (cx - 24*s, cy + 24*s),
        (cx - 10*s, cy + 20*s),
        (cx + 34*s, cy - 14*s),
    ]
    # 剑气外晕 (暗金)
    d.polygon([(x*1.08 - cx*0.08, y*1.08 - cy*0.08) for x, y in blade_poly], fill=(235, 195, 70, 45))
    # 剑身主干 (虚空黑底)
    d.polygon(blade_poly, fill=COL_INK)
    # 阳面刃部 (骨白)
    blade_top = [
        (cx + 44*s, cy - 44*s),
        (cx + 14*s, cy - 34*s),
        (cx - 20*s, cy + 10*s),
        (cx + 12*s, cy - 12*s),
    ]
    d.polygon(blade_top, fill=COL_PAPER)
    # 阴面刃部 (沉灰)
    blade_bot = [
        (cx + 44*s, cy - 44*s),
        (cx + 12*s, cy - 12*s),
        (cx - 10*s, cy + 20*s),
        (cx + 34*s, cy - 14*s),
    ]
    d.polygon(blade_bot, fill=COL_PAPER_DIM)
    # 中脊金线
    d.line([(cx + 44*s, cy - 44*s), (cx - 20*s, cy + 20*s)], fill=COL_GOLD, width=int(1.8*s))
    # 剑格 (青铜横挡)
    d.line([(cx - 28*s, cy + 14*s), (cx - 14*s, cy + 28*s)], fill=COL_GOLD, width=int(4*s))
    # 剑柄与剑首
    d.line([(cx - 21*s, cy + 21*s), (cx - 36*s, cy + 36*s)], fill=COL_INK, width=int(3*s))
    d.ellipse([cx - 41*s, cy + 35*s, cx - 35*s, cy + 41*s], fill=COL_GOLD)
    # 剑尖高光闪芒
    d.line([(cx + 36*s, cy - 44*s), (cx + 52*s, cy - 44*s)], fill=COL_WHITE, width=int(1.5*s))
    d.line([(cx + 44*s, cy - 52*s), (cx + 44*s, cy - 36*s)], fill=COL_WHITE, width=int(1.5*s))
    save_and_downscale(img, "icon_atk.png")

# 2. 护甲 (icon_armor.png): 玄龟金刚甲 —— 重叠玄铁六角阵甲 + 金刚符印
def gen_armor():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    def hex_pts(center_x, center_y, r):
        pts = []
        for i in range(6):
            a = math.radians(60 * i + 30)
            pts.append((center_x + r * math.cos(a), center_y + r * math.sin(a)))
        return pts

    # 主六角盾面
    d.polygon(hex_pts(cx, cy, 42*s), fill=COL_INK)
    d.polygon(hex_pts(cx, cy, 39*s), fill=COL_NAVY)
    d.polygon(hex_pts(cx, cy, 34*s), fill=COL_INK)

    # 盾面骨白分割棱线
    for i in range(6):
        a = math.radians(60 * i + 30)
        px = cx + 34 * s * math.cos(a)
        py = cy + 34 * s * math.sin(a)
        d.line([(cx, cy), (px, py)], fill=COL_PAPER_DIM, width=int(1.5*s))

    # 中心金刚聚灵核 (小六角)
    d.polygon(hex_pts(cx, cy, 18*s), fill=COL_GOLD_DIM)
    d.polygon(hex_pts(cx, cy, 15*s), fill=COL_GOLD)
    d.polygon(hex_pts(cx, cy, 9*s), fill=COL_WHITE)
    # 外圈金色护符包角
    d.line(hex_pts(cx, cy, 42*s) + [hex_pts(cx, cy, 42*s)[0]], fill=COL_GOLD, width=int(2.5*s))

    save_and_downscale(img, "icon_armor.png")

# 3. 移速 (icon_boots.png): 御风神行羽 —— 青玉飞羽与御风残影
def gen_boots():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 踏云灵风弧线 (背景)
    d.arc([cx - 45*s, cy - 10*s, cx + 40*s, cy + 45*s], start=120, end=330, fill=(90, 215, 165, 80), width=int(3*s))
    d.arc([cx - 40*s, cy - 25*s, cx + 45*s, cy + 35*s], start=140, end=340, fill=(90, 215, 165, 120), width=int(2*s))

    # 主神行飞羽 (羽轴从左下至右上)
    feather_r = [
        (cx + 38*s, cy - 35*s), # 羽尖
        (cx + 15*s, cy - 20*s),
        (cx - 10*s, cy - 5*s),
        (cx - 30*s, cy + 18*s),
        (cx - 38*s, cy + 38*s), # 羽根
        (cx - 24*s, cy + 28*s),
        (cx - 2*s, cy + 10*s),
        (cx + 20*s, cy - 5*s),
    ]
    d.polygon(feather_r, fill=COL_INK)
    # 羽面青翠渐变感 (左右半羽)
    feather_top = [
        (cx + 38*s, cy - 35*s),
        (cx + 15*s, cy - 20*s),
        (cx - 10*s, cy - 5*s),
        (cx - 30*s, cy + 18*s),
        (cx - 38*s, cy + 38*s),
    ]
    d.polygon(feather_top + [(cx, cy)], fill=COL_JADE)
    feather_bot = [
        (cx - 38*s, cy + 38*s),
        (cx - 24*s, cy + 28*s),
        (cx - 2*s, cy + 10*s),
        (cx + 20*s, cy - 5*s),
        (cx + 38*s, cy - 35*s),
    ]
    d.polygon(feather_bot + [(cx, cy)], fill=COL_JADE_DIM)
    # 羽轴白金硬挺中脊
    d.line([(cx - 38*s, cy + 38*s), (cx + 38*s, cy - 35*s)], fill=COL_PAPER, width=int(2*s))
    # 羽片开衩分缕
    for step in [-15, 0, 15]:
        px = cx + step * s
        py = cy - step * s * 0.9
        d.line([(px, py), (px + 10*s, py - 6*s)], fill=COL_PAPER, width=int(1.2*s))

    save_and_downscale(img, "icon_boots.png")

# 4. 攻速 (icon_haste.png): 疾影双锋 —— 双刃急速回旋与疾风残影
def gen_haste():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 旋转弧光 (疾速圆环残影)
    d.arc([cx - 42*s, cy - 42*s, cx + 42*s, cy + 42*s], start=20, end=160, fill=COL_GOLD_DIM, width=int(2*s))
    d.arc([cx - 42*s, cy - 42*s, cx + 42*s, cy + 42*s], start=200, end=340, fill=COL_GOLD_DIM, width=int(2*s))

    # 双交错飞刃 (一正一反)
    def draw_blade(rot_deg):
        cos_r = math.cos(math.radians(rot_deg))
        sin_r = math.sin(math.radians(rot_deg))
        def tr(x, y):
            rx = x * cos_r - y * sin_r
            ry = x * sin_r + y * cos_r
            return (cx + rx, cy + ry)

        poly = [tr(35*s, 0), tr(10*s, -8*s), tr(-25*s, -4*s), tr(-30*s, 0), tr(-25*s, 4*s), tr(10*s, 8*s)]
        d.polygon(poly, fill=COL_INK)
        # 上半刃骨白
        d.polygon([tr(35*s, 0), tr(10*s, -8*s), tr(-25*s, -4*s), tr(0, 0)], fill=COL_PAPER)
        # 下半刃冷灰
        d.polygon([tr(35*s, 0), tr(0, 0), tr(-25*s, 4*s), tr(10*s, 8*s)], fill=COL_PAPER_DIM)
        # 中锋金线
        d.line([tr(35*s, 0), tr(-25*s, 0)], fill=COL_GOLD, width=int(1.5*s))

    draw_blade(-35)
    draw_blade(145)

    # 中心灵枢
    d.ellipse([cx - 5*s, cy - 5*s, cx + 5*s, cy + 5*s], fill=COL_GOLD)
    d.ellipse([cx - 2*s, cy - 2*s, cx + 2*s, cy + 2*s], fill=COL_WHITE)

    save_and_downscale(img, "icon_haste.png")

# 5. 气血 (icon_hp.png): 寿元灵玉 —— 纯透心形碧魄玉符 + 寿元灵火
def gen_hp():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 心形灵魄多边形
    pts = []
    for deg in range(0, 360, 5):
        t = math.radians(deg)
        # 心形参数方程
        x = 16 * (math.sin(t) ** 3)
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        pts.append((cx + x * 2.2 * s, cy + (y + 2) * 2.2 * s))

    # 外晕 (赤红煞血光华)
    d.polygon([(x*1.08 - cx*0.08, y*1.08 - cy*0.08) for x, y in pts], fill=(215, 65, 65, 50))
    # 墨黑玉底
    d.polygon(pts, fill=COL_INK)

    # 内嵌温润朱砂灵心
    inner_pts = []
    for deg in range(0, 360, 6):
        t = math.radians(deg)
        x = 16 * (math.sin(t) ** 3)
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        inner_pts.append((cx + x * 1.8 * s, cy + (y + 2) * 1.8 * s))
    d.polygon(inner_pts, fill=COL_CRIMSON)

    # 灵玉高光折面 (骨白月牙)
    hi_pts = []
    for deg in range(180, 320, 5):
        t = math.radians(deg)
        x = 16 * (math.sin(t) ** 3)
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        hi_pts.append((cx + x * 1.8 * s, cy + (y + 2) * 1.8 * s))
    if hi_pts:
        d.line(hi_pts, fill=COL_PAPER, width=int(2.5*s))

    # 中心金白太虚灵种
    d.ellipse([cx - 6*s, cy - 2*s, cx + 6*s, cy + 10*s], fill=COL_GOLD)
    d.ellipse([cx - 3*s, cy + 1*s, cx + 3*s, cy + 7*s], fill=COL_WHITE)

    save_and_downscale(img, "icon_hp.png")

# 6. 回血 (icon_regen.png): 生机回春草 —— 晶莹翡翠回春仙草与甘露
def gen_regen():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 左右两片舒展的仙草叶
    # 左叶
    left_leaf = [
        (cx - 35*s, cy - 25*s), # 左叶尖
        (cx - 15*s, cy - 30*s),
        (cx, cy + 15*s),
        (cx - 10*s, cy + 5*s),
        (cx - 28*s, cy - 5*s),
    ]
    d.polygon(left_leaf, fill=COL_INK)
    d.polygon([(x*0.95 + cx*0.05, y*0.95 + cy*0.05) for x, y in left_leaf], fill=COL_JADE)
    d.line([(cx, cy + 15*s), (cx - 35*s, cy - 25*s)], fill=COL_PAPER, width=int(1.5*s))

    # 右叶 (略大)
    right_leaf = [
        (cx + 38*s, cy - 30*s), # 右叶尖
        (cx + 30*s, cy - 10*s),
        (cx + 10*s, cy + 15*s),
        (cx, cy + 18*s),
        (cx + 15*s, cy - 15*s),
    ]
    d.polygon(right_leaf, fill=COL_INK)
    d.polygon([(x*0.95 + cx*0.05, y*0.95 + cy*0.05) for x, y in right_leaf], fill=COL_JADE)
    d.line([(cx, cy + 18*s), (cx + 38*s, cy - 30*s)], fill=COL_PAPER, width=int(1.5*s))

    # 灵根主茎
    d.line([(cx, cy + 35*s), (cx, cy + 15*s)], fill=COL_JADE_DIM, width=int(3*s))

    # 晶莹甘露灵滴 (位于草心)
    drop_pts = [
        (cx, cy - 12*s), # 水滴尖
        (cx + 9*s, cy + 2*s),
        (cx + 6*s, cy + 10*s),
        (cx, cy + 13*s),
        (cx - 6*s, cy + 10*s),
        (cx - 9*s, cy + 2*s),
    ]
    d.polygon(drop_pts, fill=COL_INK)
    d.polygon(drop_pts, fill=COL_JADE)
    d.ellipse([cx - 4*s, cy + 1*s, cx + 4*s, cy + 9*s], fill=COL_WHITE)

    save_and_downscale(img, "icon_regen.png")

# 7. 磁吸 (icon_magnet.png): 乾坤摄灵印 —— 纳灵阵轮与内收灵光
def gen_magnet():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 外围摄灵弧环 (向心内卷)
    for rot in [0, 90, 180, 270]:
        ang_start = rot + 15
        ang_end = rot + 75
        d.arc([cx - 40*s, cy - 40*s, cx + 40*s, cy + 40*s], start=ang_start, end=ang_end, fill=COL_NAVY, width=int(3*s))

    # 四方聚灵漏斗弧
    for rot in [45, 135, 225, 315]:
        rad = math.radians(rot)
        p1 = (cx + 38*s * math.cos(rad), cy + 38*s * math.sin(rad))
        p2 = (cx + 16*s * math.cos(rad), cy + 16*s * math.sin(rad))
        d.line([p1, p2], fill=COL_GOLD, width=int(2*s))
        # 箭头向心
        p_l = (cx + 22*s * math.cos(rad - 0.2), cy + 22*s * math.sin(rad - 0.2))
        p_r = (cx + 22*s * math.cos(rad + 0.2), cy + 22*s * math.sin(rad + 0.2))
        d.polygon([p2, p_l, p_r], fill=COL_GOLD)

    # 中心乾坤灵核 (八面菱形水晶)
    r = 14 * s
    gem_poly = [(cx, cy - r), (cx + r*0.7, cy), (cx, cy + r), (cx - r*0.7, cy)]
    d.polygon(gem_poly, fill=COL_INK)
    # 阳面
    d.polygon([(cx, cy - r), (cx + r*0.7, cy), (cx, cy)], fill=COL_PAPER)
    # 阴面
    d.polygon([(cx, cy - r), (cx, cy), (cx - r*0.7, cy)], fill=COL_PAPER_DIM)
    d.polygon([(cx - r*0.7, cy), (cx, cy), (cx, cy + r)], fill=COL_NAVY)
    d.polygon([(cx, cy), (cx + r*0.7, cy), (cx, cy + r)], fill=COL_GOLD)
    d.line([(cx, cy - r), (cx, cy + r)], fill=COL_WHITE, width=int(1.2*s))

    save_and_downscale(img, "icon_magnet.png")

# 8. 灵石 (icon_coin.png): 太元通宝 / 玄天灵贝 —— 玄铁方孔古钱 + 暗金饕餮符
def gen_coin():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 外圆 (玄金大钱)
    r_outer = 40 * s
    d.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], fill=COL_INK)
    d.ellipse([cx - r_outer + 2*s, cy - r_outer + 2*s, cx + r_outer - 2*s, cy + r_outer - 2*s], fill=COL_GOLD_DIM)
    d.ellipse([cx - r_outer + 5*s, cy - r_outer + 5*s, cx + r_outer - 5*s, cy + r_outer - 5*s], fill=COL_GOLD)

    # 钱肉平水 (暗金凹陷)
    r_meat = 32 * s
    d.ellipse([cx - r_meat, cy - r_meat, cx + r_meat, cy + r_meat], fill=COL_INK)

    # 内方孔 (方孔古钱象征地)
    sq = 12 * s
    hole = [
        (cx - sq, cy - sq),
        (cx + sq, cy - sq),
        (cx + sq, cy + sq),
        (cx - sq, cy + sq),
    ]
    # 方孔暗金框
    sq_frame = [
        (cx - sq - 2*s, cy - sq - 2*s),
        (cx + sq + 2*s, cy - sq - 2*s),
        (cx + sq + 2*s, cy + sq + 2*s),
        (cx - sq - 2*s, cy + sq + 2*s),
    ]
    d.polygon(sq_frame, fill=COL_GOLD)
    d.polygon(hole, fill=(0, 0, 0, 0)) # 挖空方孔透底

    # 四方古篆阵点 (暗金凸起)
    d.ellipse([cx - 2*s, cy - 24*s, cx + 2*s, cy - 20*s], fill=COL_PAPER)
    d.ellipse([cx - 2*s, cy + 20*s, cx + 2*s, cy + 24*s], fill=COL_PAPER)
    d.ellipse([cx - 24*s, cy - 2*s, cx - 20*s, cy + 2*s], fill=COL_PAPER)
    d.ellipse([cx + 20*s, cy - 2*s, cx + 24*s, cy + 2*s], fill=COL_PAPER)

    # 上沿骨白冷月高光弧
    d.arc([cx - r_outer + 3*s, cy - r_outer + 3*s, cx + r_outer - 3*s, cy + r_outer - 3*s],
          start=200, end=340, fill=COL_PAPER, width=int(2*s))

    save_and_downscale(img, "icon_coin.png")

if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    gen_atk()
    gen_armor()
    gen_boots()
    gen_haste()
    gen_hp()
    gen_regen()
    gen_magnet()
    gen_coin()
    print("8 大核心属性图标已全部生成完成！")
