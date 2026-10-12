#!/usr/bin/env python3
"""生成 8 大核心属性的空洞冷冽国风高精图标 (128x128 PNG)
风格标准：
- 色彩严格对齐 GameStyle (虚空黑 INK, 骨白 PAPER, 暗金 GOLD, 寒玉 JADE, 幽蓝 NAVY, 煞血 CRIMSON)
- 造型硬挺内敛，无杂乱色块，线条利落，高对比度
- 纯透明背景，中心饱满，尺寸 128x128
"""
import math
import os
import sys
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

# 3. 移速 (icon_boots.png): 御风青玉靴 —— 一双踏风疾行的青玉神行靴
def gen_boots():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 御风残影弧线 (靴后拖出的疾行风痕)
    d.arc([cx - 52*s, cy - 6*s, cx + 8*s, cy + 34*s], start=95, end=260, fill=(90, 215, 165, 90), width=int(3*s))
    d.arc([cx - 48*s, cy - 20*s, cx + 12*s, cy + 20*s], start=105, end=250, fill=(90, 215, 165, 140), width=int(2*s))

    def draw_boot(bx, by):
        # 单只神行靴：竖筒 + 内勾靴头，朝左下踏步
        boot = [
            (bx - 9*s,  by - 26*s),  # 筒顶左
            (bx + 7*s,  by - 26*s),  # 筒顶右
            (bx + 7*s,  by + 2*s),   # 筒底右 (脚踝)
            (bx + 15*s, by + 8*s),   # 脚跟外缘
            (bx + 15*s, by + 16*s),  # 脚跟底
            (bx - 23*s, by + 16*s),  # 鞋头底
            (bx - 23*s, by + 7*s),   # 鞋头立沿
            (bx - 9*s,  by + 3*s),   # 脚踝内缘
        ]
        d.polygon(boot, fill=COL_JADE_DIM)
        # 靴筒阳面 (青玉面)
        d.polygon([
            (bx - 9*s, by - 26*s), (bx + 7*s, by - 26*s),
            (bx + 7*s, by + 2*s), (bx - 9*s, by + 3*s),
        ], fill=COL_JADE)
        # 靴底骨白厚边
        d.line([(bx - 23*s, by + 16*s), (bx + 15*s, by + 16*s)], fill=COL_PAPER, width=int(3*s))
        # 靴口暗金沿
        d.line([(bx - 9*s, by - 26*s), (bx + 7*s, by - 26*s)], fill=COL_GOLD, width=int(2*s))
        # 鞋头高光
        d.line([(bx - 23*s, by + 7*s), (bx - 9*s, by + 3*s)], fill=COL_PAPER, width=int(1.2*s))

    # 后靴 (右上，被前靴遮挡一半身位) + 前靴 (左下踏步)
    draw_boot(cx - 2*s, cy - 16*s)
    draw_boot(cx - 14*s, cy + 10*s)

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

# 9. 暴击率 (icon_crit.png): 会心贯的 —— 利刃刺中靶心
def gen_crit():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 同心靶环 (玄铁幽蓝)
    d.ellipse([cx - 36*s, cy - 36*s, cx + 36*s, cy + 36*s], fill=COL_INK)
    d.ellipse([cx - 32*s, cy - 32*s, cx + 32*s, cy + 32*s], fill=COL_NAVY)
    d.ellipse([cx - 25*s, cy - 25*s, cx + 25*s, cy + 25*s], fill=COL_INK)
    d.ellipse([cx - 21*s, cy - 21*s, cx + 21*s, cy + 21*s], fill=COL_NAVY)
    # 中心暗金靶核
    d.ellipse([cx - 13*s, cy - 13*s, cx + 13*s, cy + 13*s], fill=COL_GOLD_DIM)
    d.ellipse([cx - 10*s, cy - 10*s, cx + 10*s, cy + 10*s], fill=COL_GOLD)

    # 四向瞄准刻度线 (上下左右)
    for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
        d.line([(cx + dx*42*s, cy + dy*42*s), (cx + dx*28*s, cy + dy*28*s)],
               fill=COL_PAPER, width=int(2.5*s))

    # 一支利刃从右上刺入靶心
    blade = [
        (cx + 46*s, cy - 46*s),  # 刃尾
        (cx - 6*s,  cy + 6*s),   # 刺入点
        (cx + 4*s,  cy - 18*s),  # 刃背
    ]
    d.polygon(blade, fill=COL_PAPER)
    d.line([(cx + 46*s, cy - 46*s), (cx - 6*s, cy + 6*s)], fill=COL_GOLD, width=int(1.5*s))
    # 命中迸光
    d.line([(cx - 16*s, cy - 2*s), (cx - 26*s, cy - 2*s)], fill=COL_WHITE, width=int(1.5*s))
    d.line([(cx - 2*s, cy + 14*s), (cx - 2*s, cy + 24*s)], fill=COL_WHITE, width=int(1.5*s))

    save_and_downscale(img, "icon_crit.png")

# 10. 暴击伤害 (icon_critdmg.png): 迸裂星芒 —— 煞血爆裂四芒
def gen_critdmg():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    def four_star(r_long, r_short, rot_deg, color):
        """四芒星：两枚正交细菱形，rot 为整体旋转角"""
        cos_r = math.cos(math.radians(rot_deg))
        sin_r = math.sin(math.radians(rot_deg))
        def pt(lx, ly):
            return (cx + lx*cos_r - ly*sin_r, cy + lx*sin_r + ly*cos_r)
        d.polygon([pt(0, -r_short), pt(r_long, 0), pt(0, r_short), pt(-r_long, 0)], fill=color)
        d.polygon([pt(-r_short, 0), pt(0, r_long), pt(r_short, 0), pt(0, -r_long)], fill=color)

    # 外层斜置暗金芒 (残影)
    four_star(42*s, 11*s, 45, COL_GOLD_DIM)
    # 主层煞血大芒 (正置)
    four_star(46*s, 13*s, 0, COL_CRIMSON)
    # 内层骨白锐芒
    four_star(26*s, 7*s, 0, COL_PAPER)
    # 中心纯白核
    four_star(11*s, 4*s, 0, COL_WHITE)

    # 外围迸碎的小裂片
    for ang, dist in [(20, 48), (110, 46), (200, 47), (290, 45)]:
        rad = math.radians(ang)
        px, py = cx + dist*s*math.cos(rad), cy + dist*s*math.sin(rad)
        d.polygon([(px, py - 4*s), (px + 3.5*s, py + 3*s), (px - 3.5*s, py + 3*s)], fill=COL_PAPER_DIM)

    save_and_downscale(img, "icon_critdmg.png")

# 11. 闪避率 (icon_dodge.png): 弹道偏折 —— 煞矢中途拐弯遁开
def gen_dodge():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 煞血直刺弹道 (从右上直线下落至拐点)
    d.line([(cx + 40*s, cy - 40*s), (cx + 8*s, cy - 8*s)], fill=COL_CRIMSON, width=int(3.5*s))
    # 矢头 (拐点前的箭头)
    d.polygon([
        (cx + 14*s, cy - 14*s),
        (cx + 2*s,  cy - 14*s),
        (cx + 14*s, cy - 2*s),
    ], fill=COL_CRIMSON)
    # 拐点迸光 (弹道被拨开的短刺)
    for ang in [200, 250, 300]:
        rad = math.radians(ang)
        d.line([(cx + 4*s + 6*s*math.cos(rad), cy - 4*s + 6*s*math.sin(rad)),
                (cx + 4*s + 14*s*math.cos(rad), cy - 4*s + 14*s*math.sin(rad))],
               fill=COL_GOLD, width=int(1.8*s))

    # 拐弯后的遁开弧线 (青玉，弯向左下，末端箭头)
    d.arc([cx - 40*s, cy - 30*s, cx + 12*s, cy + 26*s], start=330, end=95, fill=COL_JADE, width=int(4*s))
    # 弧末端青玉箭头 (指向左下)
    d.polygon([
        (cx - 20*s, cy + 30*s),
        (cx - 8*s,  cy + 18*s),
        (cx - 4*s,  cy + 32*s),
    ], fill=COL_JADE)

    # 原弹道延长残迹 (淡红虚影，表示本应命中的路径)
    d.line([(cx + 4*s, cy), (cx - 8*s, cy + 12*s)], fill=(215, 65, 65, 110), width=int(2*s))

    save_and_downscale(img, "icon_dodge.png")

# 12. 吸血 (icon_lifesteal.png): 新月饮血 —— 弯刃承煞血灵珠
def gen_lifesteal():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 新月弯刃 (开口朝上，承血；双层：外玄铁描边 + 内幽蓝面)
    outer_r, inner_r = 34*s, 25*s
    def crescent_pts(r_out, r_in):
        pts = []
        for deg in range(200, 341, 6):
            rad = math.radians(deg)
            pts.append((cx + r_out*math.cos(rad), cy + r_out*math.sin(rad)))
        for deg in range(340, 199, -6):
            rad = math.radians(deg)
            pts.append((cx + r_in*math.cos(rad), cy + r_in*math.sin(rad)))
        return pts
    d.polygon(crescent_pts(outer_r, inner_r), fill=COL_INK)
    d.polygon(crescent_pts(outer_r - 2.5*s, inner_r + 2.5*s), fill=COL_NAVY)
    # 刃口骨白 (外缘)
    d.arc([cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r], start=205, end=335, fill=COL_PAPER, width=int(2.5*s))
    # 刃身暗金纹
    d.arc([cx - inner_r - 2*s, cy - inner_r - 2*s, cx + inner_r + 2*s, cy + inner_r + 2*s], start=215, end=325, fill=COL_GOLD_DIM, width=int(1.2*s))

    # 刃口上悬一颗大煞血灵珠 (尖上圆下水滴)
    drop = [
        (cx, cy - 36*s),
        (cx + 12*s, cy - 16*s),
        (cx + 8*s, cy - 6*s),
        (cx, cy - 2*s),
        (cx - 8*s, cy - 6*s),
        (cx - 12*s, cy - 16*s),
    ]
    d.polygon(drop, fill=COL_CRIMSON)
    d.ellipse([cx - 5*s, cy - 14*s, cx + 4*s, cy - 5*s], fill=COL_WHITE)

    # 溅落小血珠
    d.ellipse([cx + 14*s, cy - 6*s, cx + 19*s, cy - 1*s], fill=COL_CRIMSON)
    d.ellipse([cx - 18*s, cy - 10*s, cx - 14*s, cy - 6*s], fill=COL_CRIMSON)

    save_and_downscale(img, "icon_lifesteal.png")

# 13. 幸运 (icon_luck.png): 天佑星芒 —— 暗金天星与青玉祥云
def gen_luck():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    def four_star(r_long, r_short, color):
        d.polygon([(cx, cy - r_short), (cx + r_long, cy), (cx, cy + r_short), (cx - r_long, cy)], fill=color)
        d.polygon([(cx - r_short, cy), (cx, cy + r_long), (cx + r_short, cy), (cx, cy - r_long)], fill=color)

    # 底部青玉祥云 (双卷弧)
    d.arc([cx - 40*s, cy + 4*s, cx - 2*s, cy + 34*s], start=180, end=330, fill=COL_JADE, width=int(3*s))
    d.arc([cx + 2*s, cy + 4*s, cx + 40*s, cy + 34*s], start=210, end=360, fill=COL_JADE, width=int(3*s))

    # 中央暗金天星 (外晕+主体+白核)
    four_star(42*s, 13*s, (235, 195, 70, 60))
    four_star(38*s, 11*s, COL_INK)
    four_star(35*s, 10*s, COL_GOLD)
    four_star(14*s, 5*s, COL_WHITE)

    # 周缘三颗小福星
    for px, py in [(cx - 32*s, cy - 22*s), (cx + 30*s, cy - 26*s), (cx + 34*s, cy + 6*s)]:
        d.polygon([(px, py - 5*s), (px + 2*s, py), (px, py + 5*s), (px - 2*s, py)], fill=COL_PAPER)
        d.polygon([(px - 5*s, py), (px, py + 2*s), (px + 5*s, py), (px, py - 2*s)], fill=COL_PAPER)

    save_and_downscale(img, "icon_luck.png")

# 14. 收益 (icon_harvest.png): 灵穗丰收 —— 直茎垂头金穗与落珠
def gen_harvest():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 直立主茎 (青玉，自底部向上微弯)
    d.line([(cx - 6*s, cy + 36*s), (cx - 2*s, cy + 4*s)], fill=COL_JADE_DIM, width=int(3.5*s))
    # 茎顶向右弯垂 (稻穗垂头)
    d.arc([cx - 6*s, cy - 14*s, cx + 18*s, cy + 10*s], start=180, end=300, fill=COL_JADE_DIM, width=int(3*s))

    # 垂穗 (沿垂弧排列的暗金灵珠，向右下渐小)
    ear = [(20, -6, 9), (24, 2, 8), (25, 11, 7.5), (23, 20, 7), (18, 27, 6.5), (11, 32, 6)]
    for gx, gy, gr in ear:
        px, py = cx + gx*s, cy + gy*s
        d.ellipse([px - gr*s, py - gr*s, px + gr*s, py + gr*s], fill=COL_INK)
        d.ellipse([px - (gr-1)*s, py - (gr-1)*s, px + (gr-1)*s, py + (gr-1)*s], fill=COL_GOLD)
        d.ellipse([px - (gr-1)*s, py - (gr-1)*s, px, py], fill=(255, 235, 160, 255))

    # 茎上两片青玉叶 (向左舒展)
    d.polygon([
        (cx - 4*s, cy + 8*s), (cx - 26*s, cy - 4*s), (cx - 30*s, cy + 8*s), (cx - 8*s, cy + 18*s),
    ], fill=COL_JADE)
    d.polygon([
        (cx - 6*s, cy + 22*s), (cx - 24*s, cy + 16*s), (cx - 26*s, cy + 26*s), (cx - 10*s, cy + 32*s),
    ], fill=COL_JADE_DIM)

    # 底部落珠 (两枚小金珠)
    d.ellipse([cx + 6*s, cy + 30*s, cx + 14*s, cy + 38*s], fill=COL_GOLD)
    d.ellipse([cx - 16*s, cy + 34*s, cx - 10*s, cy + 40*s], fill=COL_GOLD_DIM)

    save_and_downscale(img, "icon_harvest.png")

# 15. 攻击范围 (icon_range.png): 锋芒及远 —— 灵枢发射与外扩锋弧
def gen_range():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s
    ox, oy = cx - 18*s, cy + 18*s  # 发射灵枢 (左下)

    # 外扩锋弧 (以灵枢为心的两道幽蓝扩散弧)
    for r, w in [(30, 3), (44, 2)]:
        d.arc([ox - r*s, oy - r*s, ox + r*s, oy + r*s], start=285, end=15, fill=COL_NAVY, width=int(w*s))

    # 灵枢核 (暗金)
    d.ellipse([ox - 8*s, oy - 8*s, ox + 8*s, oy + 8*s], fill=COL_INK)
    d.ellipse([ox - 6*s, oy - 6*s, ox + 6*s, oy + 6*s], fill=COL_GOLD)
    d.ellipse([ox - 2*s, oy - 2*s, ox + 2*s, oy + 2*s], fill=COL_WHITE)

    # 飞矢 (骨白，射向右上，越过锋弧之外)
    tip_x, tip_y = ox + 46*s, oy - 46*s
    d.line([(ox + 6*s, oy - 6*s), (tip_x, tip_y)], fill=COL_PAPER, width=int(2.5*s))
    d.polygon([(tip_x, tip_y), (tip_x - 12*s, tip_y + 2*s), (tip_x - 2*s, tip_y + 12*s)], fill=COL_PAPER)
    d.line([(tip_x - 14*s, tip_y + 2*s), (tip_x - 10*s, tip_y + 10*s)], fill=COL_GOLD, width=int(1.5*s))

    save_and_downscale(img, "icon_range.png")

# 16. 护体罡气 (icon_thorns.png): 罡刺反震 —— 六角甲片与放射罡刺
def gen_thorns():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    def hex_pts(center_x, center_y, r):
        pts = []
        for i in range(6):
            a = math.radians(60 * i + 30)
            pts.append((center_x + r * math.cos(a), center_y + r * math.sin(a)))
        return pts

    # 放射罡刺 (8 根暗金尖刺，先画被甲片压住根部)
    for i in range(8):
        rad = math.radians(45 * i)
        base = 18*s
        tip = 44*s
        bx1, by1 = cx + base*math.cos(rad + 0.14), cy + base*math.sin(rad + 0.14)
        bx2, by2 = cx + base*math.cos(rad - 0.14), cy + base*math.sin(rad - 0.14)
        tx, ty = cx + tip*math.cos(rad), cy + tip*math.sin(rad)
        d.polygon([(bx1, by1), (tx, ty), (bx2, by2)], fill=COL_GOLD)
        # 刺尖骨白锋
        mx, my = cx + (tip-8*s)*math.cos(rad), cy + (tip-8*s)*math.sin(rad)
        d.line([(mx, my), (tx, ty)], fill=COL_PAPER, width=int(1.5*s))

    # 中央六角甲片 (玄铁幽蓝，压住刺根)
    d.polygon(hex_pts(cx, cy, 24*s), fill=COL_INK)
    d.polygon(hex_pts(cx, cy, 21*s), fill=COL_NAVY)
    d.polygon(hex_pts(cx, cy, 21*s) + [hex_pts(cx, cy, 21*s)[0]], fill=COL_GOLD_DIM, outline=None)
    # 甲面骨白棱线
    for i in range(6):
        a = math.radians(60 * i + 30)
        px = cx + 21 * s * math.cos(a)
        py = cy + 21 * s * math.sin(a)
        d.line([(cx, cy), (px, py)], fill=COL_PAPER_DIM, width=int(1.2*s))
    # 中心罡气灵核
    d.ellipse([cx - 6*s, cy - 6*s, cx + 6*s, cy + 6*s], fill=COL_GOLD)
    d.ellipse([cx - 2.5*s, cy - 2.5*s, cx + 2.5*s, cy + 2.5*s], fill=COL_WHITE)

    save_and_downscale(img, "icon_thorns.png")

# 17. 破甲透劲 (icon_pierce.png): 锥透裂甲 —— 三棱破甲锥垂直贯穿甲片
def gen_pierce():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    # 横置大甲片 (玄铁菱块居中)
    plate = [(cx - 34*s, cy - 16*s), (cx + 34*s, cy - 16*s), (cx + 42*s, cy), (cx + 34*s, cy + 16*s), (cx - 34*s, cy + 16*s), (cx - 42*s, cy)]
    d.polygon(plate, fill=COL_INK)
    d.polygon([(cx - 30*s, cy - 12*s), (cx + 30*s, cy - 12*s), (cx + 36*s, cy), (cx + 30*s, cy + 12*s), (cx - 30*s, cy + 12*s), (cx - 36*s, cy)], fill=COL_NAVY)
    # 甲面上下棱线
    d.line([(cx - 30*s, cy - 12*s), (cx + 30*s, cy - 12*s)], fill=COL_PAPER_DIM, width=int(1.2*s))
    d.line([(cx - 30*s, cy + 12*s), (cx + 30*s, cy + 12*s)], fill=COL_PAPER_DIM, width=int(1.2*s))

    # 竖直贯穿的破甲锥 (细杆从上刺入，暗金锥尖透出甲底)
    d.polygon([
        (cx - 4*s, cy - 46*s),
        (cx + 4*s, cy - 46*s),
        (cx + 3*s, cy + 20*s),
        (cx - 3*s, cy + 20*s),
    ], fill=COL_PAPER)
    # 锥尖 (锐利三角，破出甲底)
    d.polygon([
        (cx - 3.5*s, cy + 18*s),
        (cx + 3.5*s, cy + 18*s),
        (cx, cy + 46*s),
    ], fill=COL_GOLD)
    # 锥顶柄头 (暗金箍)
    d.polygon([
        (cx - 6*s, cy - 50*s), (cx + 6*s, cy - 50*s), (cx + 4*s, cy - 44*s), (cx - 4*s, cy - 44*s),
    ], fill=COL_GOLD_DIM)

    # 甲面贯穿裂痕 (从贯穿点向两侧炸开)
    d.line([(cx - 30*s, cy - 2*s), (cx - 6*s, cy - 2*s)], fill=COL_PAPER, width=int(2.2*s))
    d.line([(cx + 6*s, cy - 2*s), (cx + 30*s, cy - 2*s)], fill=COL_PAPER, width=int(2.2*s))
    d.line([(cx - 16*s, cy - 2*s), (cx - 22*s, cy + 8*s)], fill=COL_PAPER, width=int(1.5*s))
    d.line([(cx + 16*s, cy - 2*s), (cx + 24*s, cy - 10*s)], fill=COL_PAPER, width=int(1.5*s))

    # 贯穿迸光 (锥尖破出处)
    d.line([(cx + 8*s, cy + 38*s), (cx + 16*s, cy + 44*s)], fill=COL_WHITE, width=int(1.5*s))
    d.line([(cx - 10*s, cy + 42*s), (cx - 4*s, cy + 48*s)], fill=COL_WHITE, width=int(1.2*s))

    save_and_downscale(img, "icon_pierce.png")

# 18. 灵兽节拍 (icon_speed.png): 疾兽三重爪痕 —— 灵狐前扑掠风撕出的斜向爪痕与疾行残影
#      供悟道加点「灵兽疾行」(pet_haste_up) 使用，与同组 icon_atk / icon_hp 同管线同尺寸
def gen_pet_haste():
    img, d, s = create_super_canvas()
    cx, cy = 64 * s, 64 * s

    def slash(sx, sy, dx, dy, bow, w0, color, edge=COL_WHITE):
        """一记爪痕：从 (sx,sy) 沿 (dx,dy) 撕出 hypot(dx,dy) 长，中段外弓 bow，尾宽 w0 → 尖端收束 0。
        入参一律是 128 逻辑像素（含位移向量），函数内部统一乘 s 超采样，别在外面先乘。"""
        n = math.hypot(dx, dy)
        ux, uy = dx / n, dy / n          # 前进方向
        px_, py_ = -uy, ux               # 左法线（外弓方向）
        steps = 34
        left, right = [], []
        for i in range(steps + 1):
            t = i / steps
            # 外弓用正弦拱形：两端不弯、中段最鼓，撕痕才有「甩出去」的弧度
            b = bow * math.sin(math.pi * t)
            hw = w0 * (1.0 - t) ** 1.35  # 幂次收束：钝尾 + 极锐尖
            bx = sx + ux * n * t + px_ * b
            by = sy + uy * n * t + py_ * b
            left.append(((bx + px_ * hw) * s, (by + py_ * hw) * s))
            right.append(((bx - px_ * hw) * s, (by - py_ * hw) * s))
        d.polygon(left + right[::-1], fill=color)
        d.line(left[:int(steps * 0.72)], fill=edge, width=int(1.1 * s))

    # 四道同一把尺子的平行斜撕：同方向、同弧、同长，只沿法线平移排布 ⇒ 读作一记耙痕而非四片草叶
    ux, uy = 86.0, -62.0
    n = math.hypot(ux, uy)
    ux, uy = ux / n, uy / n
    px_, py_ = -uy, ux                      # 法线（指向右下），沿它平移排爪距
    base_x, base_y = 30.0, 86.0
    # (爪距, 尾宽, 颜色, 刃口色)：最上一爪是领爪（骨白最宽），往下渐暗渐窄成叠影
    rake = [(-20.0, 11.0, COL_PAPER, COL_WHITE),
            (-7.0, 9.5, COL_JADE, COL_PAPER_DIM),
            (7.0, 8.0, COL_JADE_DIM, COL_JADE),
            (20.0, 6.5, (45, 130, 95, 165), COL_JADE_DIM)]
    for off, w0, col, edge in rake:
        slash(base_x + px_ * off, base_y + py_ * off, ux * 96, uy * 96, 13.0, w0, col, edge)

    # 破风灵息：领爪尖出处迸出的暗金菱形火星
    d.polygon([(cx + 44 * s, cy - 40 * s), (cx + 49 * s, cy - 35 * s),
               (cx + 44 * s, cy - 30 * s), (cx + 39 * s, cy - 35 * s)], fill=COL_GOLD)

    # 尾端御风横纹：左下两道短促疾风痕，说明这记爪痕是「冲过来的」
    d.line([(cx - 52 * s, cy + 44 * s), (cx - 28 * s, cy + 27 * s)], fill=(90, 215, 165, 130), width=int(2.4 * s))
    d.line([(cx - 46 * s, cy + 54 * s), (cx - 32 * s, cy + 44 * s)], fill=(90, 215, 165, 70), width=int(2.0 * s))

    save_and_downscale(img, "icon_speed.png")

def fit_from_raw(raw_path, target_art_name, target_size=128, margin=8):
    im = Image.open(raw_path).convert("RGBA")
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda v: 255 if v > 15 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    inner_max = target_size - margin * 2
    w, h = im.size
    scale = min(inner_max / w, inner_max / h)
    new_w = int(round(w * scale))
    new_h = int(round(h * scale))
    im_resized = im.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    ox = (target_size - new_w) // 2
    oy = (target_size - new_h) // 2
    canvas.paste(im_resized, (ox, oy), im_resized)
    dest_path = os.path.join(OUTPUT_DIR, target_art_name)
    canvas.save(dest_path, "PNG")
    print(f"[IconGen] 已从源图适配生成: {dest_path}")

GENERATORS = {
    "icon_atk": gen_atk,
    "icon_armor": gen_armor,
    "icon_boots": gen_boots,
    "icon_haste": gen_haste,
    "icon_hp": gen_hp,
    "icon_regen": gen_regen,
    "icon_magnet": gen_magnet,
    "icon_coin": gen_coin,
    "icon_crit": gen_crit,
    "icon_critdmg": gen_critdmg,
    "icon_dodge": gen_dodge,
    "icon_lifesteal": gen_lifesteal,
    "icon_luck": gen_luck,
    "icon_harvest": gen_harvest,
    "icon_range": gen_range,
    "icon_thorns": gen_thorns,
    "icon_pierce": gen_pierce,
    "icon_speed": gen_pet_haste,
}

if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    # --only icon_a,icon_b 只重生成指定图标，避免覆盖其余确定性输出
    only = None
    argv = sys.argv[1:]
    if "--only" in argv:
        idx = argv.index("--only")
        only = [x.strip() for x in argv[idx + 1].split(",") if x.strip()]
    targets = only if only else list(GENERATORS)
    for name in targets:
        raw_file = os.path.join("assets_raw/images", f"{name}.png")
        if os.path.exists(raw_file):
            fit_from_raw(raw_file, f"{name}.png")
        elif name in GENERATORS:
            GENERATORS[name]()
    print(f"属性图标生成完成：{len(targets)} 张 ({', '.join(targets)})")
