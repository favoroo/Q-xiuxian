#!/usr/bin/env python3
"""生成「悟道加点」专属纯色扁平矢量图标 (128x128 PNG)

风格：参照 tools/generate_cold_gothic_skill_icons.py 的极简扁平几何剪影，
      但允许 1~4 个纯色（骨白骨架 + 一个语义强调色；传说/强化档可加金色环）。
严格规范：
- 纯色扁平、无渐变、无柔光、无描边柔边；硬边几何，对齐项目 UI 语言。
- 绝不使用深色填充（图标底为纯黑瓦片，深色会糊进背景）——只用亮色块。
- 512x512 超采样绘制，按 alpha 包围盒自动居中并等比缩放到 128x128（Lanczos）。
- 输出到 assets/art/upgrade_*.png（与既有 icon_*/item_*/weapon_* 完全独立，零共享）。

命名：upgrade_<语义>.png，一图一义；*_grand 为强化档（基础形 + 环饰）。
"""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

OUTPUT_DIR = "assets/art"
os.makedirs(OUTPUT_DIR, exist_ok=True)

CLEAR = (0, 0, 0, 0)
SCALE = 4
SIZE_LOGICAL = 128
SIZE_SUPER = SIZE_LOGICAL * SCALE  # 512
CX = 256
CY = 256

# ---- 调色板（亮色，全部可在纯黑底上清晰辨识）----
CHALK = (242, 239, 228, 255)   # 骨白骨架
CRIMSON = (214, 62, 62, 255)   # 攻击 / 伤害
JADE = (74, 200, 150, 255)     # 生存 / 身法
GOLD = (240, 196, 72, 255)     # 经济 / 收益
BLUE = (86, 150, 226, 255)     # 技能流
PURPLE = (176, 126, 232, 255)  # 灵兽
# 五行
M_METAL = (232, 216, 150, 255)
M_WOOD = (118, 198, 112, 255)
M_WATER = (92, 164, 232, 255)
M_FIRE = (240, 118, 58, 255)
M_EARTH = (204, 158, 96, 255)


# ---------------------------------------------------------------- 基础画布 / 导出
def create_super_canvas():
    img = Image.new("RGBA", (SIZE_SUPER, SIZE_SUPER), CLEAR)
    return img, ImageDraw.Draw(img)


def auto_center_and_export(img, filename, target_size=128, max_content_radius=42):
    """按 alpha 包围盒自动居中 + 等比缩放到 target_size，落盘 OUTPUT_DIR。"""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    ys, xs = np.where(alpha > 10)
    if len(xs) == 0:
        print(f"[Error] {filename} 无有效像素")
        return
    min_x, max_x = int(xs.min()), int(xs.max())
    min_y, max_y = int(ys.min()), int(ys.max())
    cw, ch = max_x - min_x + 1, max_y - min_y + 1
    target_span = max_content_radius * 2 * SCALE
    zoom = target_span / float(max(cw, ch))
    cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1))
    nw, nh = max(1, int(round(cw * zoom))), max(1, int(round(ch * zoom)))
    rescaled = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    centered = Image.new("RGBA", (SIZE_SUPER, SIZE_SUPER), CLEAR)
    centered.paste(rescaled, (int(round(CX - nw / 2.0)), int(round(CY - nh / 2.0))), rescaled)
    final = centered.resize((target_size, target_size), Image.Resampling.LANCZOS)
    final.save(os.path.join(OUTPUT_DIR, filename), "PNG")
    print(f"[UpgradeIcon] {filename}")


# ---------------------------------------------------------------- 坐标 / 图元
def p(x, y):
    """逻辑坐标 [-64,64] -> 超采样绝对坐标"""
    return (CX + x * SCALE, CY + y * SCALE)


def L(v):
    return v * SCALE


def rot_pts(pts, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return [(x * c - y * s, x * s + y * c) for x, y in pts]


def bezier(p0, p1, p2, p3, steps=24):
    out = []
    for i in range(steps + 1):
        t = i / float(steps)
        x = (1-t)**3*p0[0] + 3*(1-t)**2*t*p1[0] + 3*(1-t)*t**2*p2[0] + t**3*p3[0]
        y = (1-t)**3*p0[1] + 3*(1-t)**2*t*p1[1] + 3*(1-t)*t**2*p2[1] + t**3*p3[1]
        out.append((x, y))
    return out


def poly_l(d, pts, color):
    d.polygon([p(x, y) for x, y in pts], fill=color)


def poly_abs(d, pts, color):
    d.polygon(pts, fill=color)


def circ_l(d, cx, cy, r, color):
    X, Y = p(cx, cy)
    d.ellipse([X - L(r), Y - L(r), X + L(r), Y + L(r)], fill=color)


def ell_l(d, cx, cy, rx, ry, color):
    X, Y = p(cx, cy)
    d.ellipse([X - L(rx), Y - L(ry), X + L(rx), Y + L(ry)], fill=color)


def ring_l(img, cx, cy, r_out, r_in, color):
    """真正的圆环：独立图层画外圆->内圈打孔->合成，避免 PIL 用 CLEAR 直接替换像素把内部内容擦掉。"""
    layer = Image.new("RGBA", img.size, CLEAR)
    ld = ImageDraw.Draw(layer)
    X, Y = p(cx, cy)
    ld.ellipse([X - L(r_out), Y - L(r_out), X + L(r_out), Y + L(r_out)], fill=color)
    ld.ellipse([X - L(r_in), Y - L(r_in), X + L(r_in), Y + L(r_in)], fill=CLEAR)
    img.alpha_composite(layer)


def line_l(d, pts, color, w):
    d.line([p(x, y) for x, y in pts], fill=color, width=max(1, int(round(w * SCALE))))


def regular_poly_pts(n, r, rot_deg=0.0):
    return [(math.cos(math.radians(360.0 * i / n + rot_deg)) * r,
             math.sin(math.radians(360.0 * i / n + rot_deg)) * r) for i in range(n)]


def star_pts(n, r_out, r_in, rot_deg=0.0):
    pts = []
    for i in range(n * 2):
        ang = math.radians(180.0 * i / n + rot_deg)
        r = r_out if i % 2 == 0 else r_in
        pts.append((math.cos(ang) * r, math.sin(ang) * r))
    return pts


def droplet(d, cx, cy, r, color):
    """水滴：顶点在上，圆腹在下。"""
    pts = bezier(p(cx, cy - r * 1.55), p(cx - r * 1.15, cy - r * 0.1), p(cx - r * 1.0, cy + r * 0.95), p(cx, cy + r * 0.95)) \
        + bezier(p(cx, cy + r * 0.95), p(cx + r * 1.0, cy + r * 0.95), p(cx + r * 1.15, cy - r * 0.1), p(cx, cy - r * 1.55))
    poly_abs(d, pts, color)


def flame(d, cx, cy, r, color):
    """火焰：底宽顶尖，侧边微鼓。"""
    pts = bezier(p(cx, cy + r), p(cx - r * 1.15, cy + r * 0.35), p(cx - r * 0.7, cy - r * 0.55), p(cx, cy - r * 1.25)) \
        + bezier(p(cx, cy - r * 1.25), p(cx + r * 0.55, cy - r * 0.5), p(cx + r * 1.0, cy + r * 0.5), p(cx, cy + r))
    poly_abs(d, pts, color)


def ornate_ring(img, color, r_out=45, r_in=42):
    ring_l(img, 0, 0, r_out, r_in, color)


# ================================================================ 攻击 / 伤害（CRIMSON）
def gen_atk(ornate=False, ring=CRIMSON, out="upgrade_atk.png"):
    img, d = create_super_canvas()
    poly_l(d, [(0, -40), (8, -12), (8, 8), (-8, 8), (-8, -12)], CHALK)   # 剑身
    poly_l(d, [(-18, 8), (18, 8), (18, 13), (-18, 13)], CHALK)           # 剑格
    poly_l(d, [(-4, 13), (4, 13), (4, 28), (-4, 28)], CHALK)             # 剑柄
    circ_l(d, 0, 31, 4.5, CHALK)                                        # 剑首
    line_l(d, [(0, -34), (0, 4)], CRIMSON, 2.2)                          # 血槽
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, out)


def gen_melee(ornate=False, ring=CRIMSON, out="upgrade_melee.png"):
    img, d = create_super_canvas()
    def sword(deg):
        poly_l(d, rot_pts([(0, -40), (5, -6), (0, 18), (-5, -6)], deg), CHALK)
        poly_l(d, rot_pts([(-10, -4), (10, -4), (10, 0), (-10, 0)], deg), CHALK)
    sword(-38)
    sword(38)
    poly_l(d, rot_pts([(0, -9), (5, 0), (0, 9), (-5, 0)], 0), CRIMSON)   # 中心红菱
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, out)


def gen_ranged(ornate=False, ring=CRIMSON, out="upgrade_ranged.png"):
    img, d = create_super_canvas()
    X, Y = p(0, 0)
    d.arc([X - L(40), Y - L(40), X + L(40), Y + L(40)], 130, 230, fill=CHALK, width=int(7 * SCALE))
    line_l(d, [(-26, -30), (-26, 30)], CHALK, 1.5)                       # 弓弦
    line_l(d, [(-46, 0), (28, 0)], CHALK, 3)                             # 箭杆
    poly_l(d, [(28, 0), (13, -8), (13, 8)], CRIMSON)                     # 箭头
    poly_l(d, [(-46, 0), (-38, -7), (-34, 0), (-38, 7)], CRIMSON)        # 尾羽
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, out)


def gen_elemental(ornate=False, ring=CRIMSON, out="upgrade_elemental.png"):
    """元素强化：骨白三角框内嵌火/水/木三色小三角（三元素归一，区别于单系 fire 火焰剪影）。"""
    img, d = create_super_canvas()
    A, B, C = (0, -42), (-40, 32), (40, 32)          # 大三角顶点
    poly_l(d, [A, B, C], CHALK)
    def shrink(tri, f=0.80):
        cx = sum(x for x, _ in tri) / 3.0
        cy = sum(y for _, y in tri) / 3.0
        return [(cx + (x - cx) * f, cy + (y - cy) * f) for x, y in tri]
    mid_l, mid_r = ((-40 + 0) / 2.0, (32 + -42) / 2.0), ((40 + 0) / 2.0, (32 + -42) / 2.0)
    top = [A, mid_l, mid_r]
    bl = [mid_l, B, (0, 32)]
    br = [mid_r, (0, 32), C]
    poly_l(d, shrink(top), M_FIRE)
    poly_l(d, shrink(bl), M_WATER)
    poly_l(d, shrink(br), M_WOOD)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, out)


def gen_engineering(ornate=False, ring=CRIMSON, out="upgrade_engineering.png"):
    img, d = create_super_canvas()
    dome = bezier(p(-30, 20), p(-36, -34), p(36, -34), p(30, 20))
    rim = [p(38, 20), p(38, 28), p(-38, 28), p(-38, 20)]
    poly_abs(d, dome + rim, CHALK)
    circ_l(d, 0, -38, 5, CHALK)                                          # 钟钮
    line_l(d, [(-30, 24), (30, 24)], CRIMSON, 2)                         # 钟口饰线
    circ_l(d, 0, 33, 6, CRIMSON)                                         # 钟舌
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, out)


def gen_contraption(ornate=False, ring=CRIMSON, out="upgrade_contraption.png"):
    img, d = create_super_canvas()
    for i in range(8):
        tooth = [(-6, -41), (6, -41), (6, -28), (-6, -28)]
        poly_l(d, rot_pts(tooth, 45 * i), CHALK)
    circ_l(d, 0, 0, 30, CHALK)
    circ_l(d, 0, 0, 20, CRIMSON)                                         # 轮毂
    circ_l(d, 0, 0, 9, CLEAR)                                            # 中孔
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, out)


def gen_crit(ornate=False, ring=CRIMSON):
    img, d = create_super_canvas()
    ring_l(img, 0, 0, 38, 29, CHALK)
    circ_l(d, 0, 0, 15, CRIMSON)
    circ_l(d, 0, 0, 7, CHALK)
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        line_l(d, [(math.cos(a) * 38, math.sin(a) * 38), (math.cos(a) * 47, math.sin(a) * 47)], CHALK, 3)
    if ornate:
        ring_l(img, 0, 0, 53, 50, ring)
    auto_center_and_export(img, "upgrade_crit.png")


def gen_critdmg(ornate=False, ring=CRIMSON):
    img, d = create_super_canvas()
    poly_l(d, star_pts(4, 43, 12, 0), CHALK)
    poly_l(d, star_pts(4, 20, 6, 0), CRIMSON)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_critdmg.png")


def gen_pierce(ornate=False, ring=CRIMSON):
    img, d = create_super_canvas()
    line_l(d, [(-40, 0), (24, 0)], CHALK, 4)                             # 枪杆
    poly_l(d, [(26, 0), (8, -9), (8, 9)], CRIMSON)                       # 枪尖
    for ox in (-18, -2):                                                 # 穿透的两层
        line_l(d, [(ox - 6, -14), (ox + 6, 0)], CHALK, 3)
        line_l(d, [(ox + 6, 0), (ox - 6, 14)], CHALK, 3)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_pierce.png")


def gen_elite(ornate=False, ring=CRIMSON):
    img, d = create_super_canvas()
    poly_l(d, [(-38, 20), (38, 20), (30, -10), (16, 8), (0, -26), (-16, 8), (-30, -10)], CHALK)
    circ_l(d, 0, 8, 6, CRIMSON)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_elite.png")


def gen_bloodlust(ornate=False, ring=CRIMSON):
    img, d = create_super_canvas()
    poly_l(d, rot_pts([(0, -38), (6, -2), (0, 26), (-6, -2)], 28), CHALK)  # 斜剑
    droplet(d, -18, 18, 14, CRIMSON)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_bloodlust.png")


def gen_lifesteal(ornate=False, ring=CRIMSON):
    img, d = create_super_canvas()
    droplet(d, 0, -2, 26, CHALK)
    droplet(d, 0, 2, 15, CRIMSON)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_lifesteal.png")


def gen_thorns(ornate=False, ring=CRIMSON, n=6, spike_r=41, hex_r=26):
    img, d = create_super_canvas()
    poly_l(d, regular_poly_pts(n, hex_r, 0), CHALK)
    for i in range(n):
        a = math.radians(360.0 * i / n)
        bx, by = math.cos(a) * hex_r * 0.92, math.sin(a) * hex_r * 0.92
        tx, ty = math.cos(a) * spike_r, math.sin(a) * spike_r
        perp = a + math.pi / 2
        px, py = math.cos(perp) * 6.5, math.sin(perp) * 6.5
        poly_l(d, [(bx + px, by + py), (bx - px, by - py), (tx, ty)], CRIMSON)
    circ_l(d, 0, 0, 7, CRIMSON)
    if ornate:
        ornate_ring(img, ring, r_out=47, r_in=44)
    auto_center_and_export(img, "upgrade_thorns_grand.png" if ornate else "upgrade_thorns.png")


# ================================================================ 生存 / 身法（JADE）
def gen_armor(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    poly_l(d, regular_poly_pts(6, 40, 0), CHALK)
    poly_l(d, regular_poly_pts(6, 27, 0), JADE)
    poly_l(d, regular_poly_pts(6, 12, 0), CHALK)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_armor.png")


def gen_temper(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    poly_l(d, regular_poly_pts(6, 40, 0), CHALK)
    poly_l(d, regular_poly_pts(6, 27, 0), JADE)
    cross = [(-4, -16), (4, -16), (4, -4), (16, -4), (16, 4), (4, 4),
             (4, 16), (-4, 16), (-4, 4), (-16, 4), (-16, -4), (-4, -4)]
    poly_l(d, cross, CHALK)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_temper.png")


HEART = [(0, 34), (-30, 2), (-34, -14), (-24, -30), (-8, -32), (0, -20),
         (8, -32), (24, -30), (34, -14), (30, 2)]


def gen_hp(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    poly_l(d, HEART, CHALK)
    cross = [(-4, -14), (4, -14), (4, -3), (15, -3), (15, 5), (4, 5),
             (4, 16), (-4, 16), (-4, 5), (-15, 5), (-15, -3), (-4, -3)]
    poly_l(d, cross, JADE)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_hp.png")


def gen_regen(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    X, Y = p(0, 0)
    d.arc([X - L(40), Y - L(40), X + L(40), Y + L(40)], 30, 300, fill=CHALK, width=int(6 * SCALE))
    # 回环箭头
    a = math.radians(30)
    ex, ey = math.cos(a) * 40, math.sin(a) * 40
    nx, ny = math.cos(a), math.sin(a)
    tx, ty = -math.sin(a), math.cos(a)
    poly_l(d, [(ex + tx * 9, ey + ty * 9), (ex + nx * 8, ey + ny * 8), (ex - nx * 8, ey - ny * 8)], CHALK)
    # 中心小玉心
    s = 0.5
    poly_l(d, [(x * s, y * s - 2) for x, y in HEART], JADE)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_regen.png")


def gen_dodge(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    offs = [(-24, CHALK), (-4, CHALK), (16, JADE)] if not ornate else [(-30, CHALK), (-10, CHALK), (10, JADE), (28, JADE)]
    for ox, col in offs:
        line_l(d, [(ox - 10, -22), (ox + 8, 0)], col, 4)
        line_l(d, [(ox + 8, 0), (ox - 10, 22)], col, 4)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_dodge_grand.png" if ornate else "upgrade_dodge.png")


def gen_speed(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    poly_l(d, [(14, 0), (-22, -28), (-22, -10), (-50, -10), (-50, 10), (-22, 10), (-22, 28)], JADE)  # 残影
    poly_l(d, [(34, 0), (-2, -24), (-2, -8), (-30, -8), (-30, 8), (-2, 8), (-2, 24)], CHALK)         # 主箭头
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_speed.png")


def gen_haste(ornate=False, ring=JADE):
    img, d = create_super_canvas()
    line_l(d, [(-30, -38), (30, -38)], CHALK, 4)
    line_l(d, [(-30, 38), (30, 38)], CHALK, 4)
    poly_l(d, [(-26, -38), (26, -38), (4, -2), (-4, -2)], CHALK)   # 上漏斗
    poly_l(d, [(-26, 38), (26, 38), (4, 2), (-4, 2)], CHALK)       # 下漏斗
    poly_l(d, [(-22, 36), (22, 36), (2, 12), (-2, 12)], JADE)      # 下沙
    poly_l(d, [(-15, -34), (15, -34), (2, -24), (-2, -24)], JADE)  # 上沙
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_haste_grand.png" if ornate else "upgrade_haste.png")


# ================================================================ 经济 / 收益（GOLD）
def gen_greed(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    bag = bezier(p(-34, 10), p(-42, 44), p(42, 44), p(34, 10))
    poly_abs(d, bag + [p(-34, 10)], CHALK)
    poly_l(d, [(-20, 10), (20, 10), (14, -2), (-14, -2)], CHALK)   # 袋口
    line_l(d, [(-18, 0), (18, 0)], GOLD, 3)                        # 束口绳
    circ_l(d, -9, -15, 8, GOLD)
    circ_l(d, 10, -13, 7, GOLD)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_greed.png")


def gen_harvest(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    line_l(d, [(0, 36), (0, -12)], CHALK, 4)
    leaf_r = bezier(p(0, 12), p(-26, 8), p(-30, -16), p(-6, -14)) + bezier(p(-6, -14), p(-10, 2), p(-4, 10), p(0, 12))
    poly_abs(d, leaf_r, CHALK)
    leaf_l = bezier(p(0, 12), p(26, 8), p(30, -16), p(6, -14)) + bezier(p(6, -14), p(10, 2), p(4, 10), p(0, 12))
    poly_abs(d, leaf_l, CHALK)
    circ_l(d, 0, -30, 11, GOLD)
    circ_l(d, 0, -30, 5, CHALK)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_harvest.png")


def gen_luck(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    line_l(d, [(0, 14), (0, 38)], CHALK, 4)
    for dx, dy in [(-14, 0), (14, 0), (0, -14), (0, 14)]:
        circ_l(d, dx, dy, 13, CHALK)
    circ_l(d, 0, 0, 7, GOLD)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_luck.png")


def gen_merchant(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    poly_l(d, [(-30, -22), (4, -22), (34, 0), (4, 22), (-30, 22)], CHALK)
    circ_l(d, -20, 0, 5, CLEAR)                                    # 吊孔
    circ_l(d, 8, 0, 12, GOLD)                                      # 价签金币
    # ¥ 符号（省钱/议价）
    line_l(d, [(3, -7), (8, 0)], CHALK, 2)
    line_l(d, [(13, -7), (8, 0)], CHALK, 2)
    line_l(d, [(8, 0), (8, 7)], CHALK, 2)
    line_l(d, [(4, 1), (12, 1)], CHALK, 1.6)
    line_l(d, [(4, 4), (12, 4)], CHALK, 1.6)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_merchant.png")


def gen_insight(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    upper = bezier(p(-38, 0), p(-18, -26), p(18, -26), p(38, 0))
    lower = bezier(p(38, 0), p(18, 26), p(-18, 26), p(-38, 0))
    poly_abs(d, upper + lower, CHALK)
    circ_l(d, 0, 0, 15, GOLD)
    circ_l(d, 0, 0, 7, CLEAR)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_insight.png")


def gen_tongxuan(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    X, Y = p(0, 0)
    d.arc([X - L(36), Y - L(36), X + L(36), Y + L(36)], 205, 335, fill=CHALK, width=int(6 * SCALE))
    d.arc([X - L(36), Y - L(36), X + L(36), Y + L(36)], 25, 155, fill=CHALK, width=int(6 * SCALE))
    for deg in (335, 155):
        a = math.radians(deg)
        ex, ey = math.cos(a) * 36, math.sin(a) * 36
        nx, ny = math.cos(a), math.sin(a)
        tx, ty = -math.sin(a), math.cos(a)
        poly_l(d, [(ex + tx * 10, ey + ty * 10), (ex + nx * 7, ey + ny * 7), (ex - nx * 7, ey - ny * 7)], CHALK)
    circ_l(d, 0, 0, 8, GOLD)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_tongxuan.png")


def _chest_base(d):
    poly_l(d, [(-34, -4), (34, -4), (34, 34), (-34, 34)], CHALK)          # 箱体
    lid = bezier(p(-34, -4), p(-34, -36), p(34, -36), p(34, -4))          # 弧形盖
    poly_abs(d, lid + [p(34, -4), p(-34, -4)], CHALK)
    line_l(d, [(-35, -4), (35, -4)], GOLD, 3)                             # 盖缝
    line_l(d, [(-18, -4), (-18, 33)], GOLD, 2.5)                          # 竖带
    line_l(d, [(18, -4), (18, 33)], GOLD, 2.5)


def gen_chest(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    _chest_base(d)
    poly_l(d, [(-8, 2), (8, 2), (8, 14), (-8, 14)], GOLD)
    circ_l(d, 0, 8, 3, CLEAR)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_chest.png")


def gen_chest_quality(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    _chest_base(d)
    poly_l(d, [(0, -30), (13, -15), (0, 0), (-13, -15)], GOLD)     # 盖上宝石
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_chest_quality.png")


def gen_chest_reward(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    # 开盖：箱体 + 掀开的盖子
    poly_l(d, [(-34, 6), (34, 6), (34, 38), (-34, 38)], CHALK)
    poly_l(d, [(-38, -18), (38, -18), (30, 2), (-30, 2)], CHALK)   # 盖子
    line_l(d, [(-34, 22), (34, 22)], GOLD, 3)
    # 金币涌出
    for cx, cy, r in [(-16, -8, 8), (6, -14, 8), (20, -4, 7), (-2, -26, 6)]:
        circ_l(d, cx, cy, r, GOLD)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_chest_reward.png")


def gen_range(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    ring_l(img, 0, 0, 26, 21, CHALK)
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        bx, by = math.cos(a) * 30, math.sin(a) * 30
        tx, ty = math.cos(a) * 45, math.sin(a) * 45
        line_l(d, [(bx, by), (tx, ty)], GOLD, 3)
        perp = a + math.pi / 2
        px, py = math.cos(perp) * 6, math.sin(perp) * 6
        poly_l(d, [(tx, ty), (tx - math.cos(a) * 9 + px, ty - math.sin(a) * 9 + py),
                   (tx - math.cos(a) * 9 - px, ty - math.sin(a) * 9 - py)], GOLD)
    if ornate:
        ornate_ring(img, ring, r_out=52, r_in=49)
    auto_center_and_export(img, "upgrade_range.png")


# ================================================================ 五行（各元素色）
def gen_metal(ornate=False, ring=M_METAL):
    img, d = create_super_canvas()
    poly_l(d, [(0, -40), (34, 0), (0, 40), (-34, 0)], CHALK)
    poly_l(d, [(0, -22), (18, 0), (0, 22), (-18, 0)], M_METAL)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_metal.png")


def gen_wood(ornate=False, ring=M_WOOD):
    img, d = create_super_canvas()
    leaf = bezier(p(0, 38), p(-32, 20), p(-32, -24), p(0, -40)) + bezier(p(0, -40), p(32, -24), p(32, 20), p(0, 38))
    poly_abs(d, leaf, CHALK)
    line_l(d, [(0, 34), (0, -34)], M_WOOD, 3)
    for oy in (-14, 4):
        line_l(d, [(0, oy), (-13, oy - 10)], M_WOOD, 2)
        line_l(d, [(0, oy), (13, oy - 10)], M_WOOD, 2)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_wood.png")


def gen_water(ornate=False, ring=M_WATER):
    img, d = create_super_canvas()
    droplet(d, 0, 0, 34, CHALK)
    droplet(d, 0, 6, 19, M_WATER)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_water.png")


def gen_fire(ornate=False, ring=M_FIRE):
    img, d = create_super_canvas()
    flame(d, 0, 2, 40, CHALK)
    flame(d, 0, 10, 22, M_FIRE)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_fire.png")


def gen_earth(ornate=False, ring=M_EARTH):
    img, d = create_super_canvas()
    poly_l(d, [(-40, 34), (0, -36), (40, 34)], CHALK)
    poly_l(d, [(-15, 34), (0, 8), (15, 34)], M_EARTH)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_earth.png")


def gen_wuxing(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    poly_l(d, regular_poly_pts(5, 44, -90), CHALK)                 # 外框
    poly_l(d, regular_poly_pts(5, 34, -90), CLEAR)                 # 挖空（成粗环）
    poly_l(d, star_pts(5, 17, 7, -90), CHALK)                      # 中心五芒星
    cols = [M_METAL, M_WOOD, M_WATER, M_FIRE, M_EARTH]
    for i, c in enumerate(cols):
        a = math.radians(72 * i - 90)
        circ_l(d, math.cos(a) * 39, math.sin(a) * 39, 6.5, c)
    if ornate:
        ornate_ring(img, ring, r_out=52, r_in=49)
    auto_center_and_export(img, "upgrade_wuxing.png")


# ================================================================ 技能流（BLUE）
def gen_skill_cd(ornate=False, ring=BLUE):
    img, d = create_super_canvas()
    ring_l(img, 0, 0, 40, 33, CHALK)
    for ang in range(0, 360, 30):
        a = math.radians(ang)
        line_l(d, [(math.cos(a) * 29, math.sin(a) * 29), (math.cos(a) * 24, math.sin(a) * 24)], CHALK, 2)
    line_l(d, [(0, 0), (0, -23)], BLUE, 4)
    line_l(d, [(0, 0), (17, 7)], BLUE, 4)
    circ_l(d, 0, 0, 5, BLUE)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_skill_cd_grand.png" if ornate else "upgrade_skill_cd.png")


# ================================================================ 灵兽（PURPLE）
def gen_pet_damage(ornate=False, ring=PURPLE):
    img, d = create_super_canvas()
    for ox in (-18, 0, 18):
        poly_l(d, [(ox - 7, -32), (ox - 1, -32), (ox + 9, 28), (ox + 3, 28)], CHALK)
        poly_l(d, [(ox - 4, -30), (ox - 1, -30), (ox + 6, 26), (ox + 3, 26)], PURPLE)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_pet_damage.png")


def gen_pet_effect(ornate=False, ring=PURPLE):
    img, d = create_super_canvas()
    ring_l(img, 0, 0, 34, 28, CHALK)
    circ_l(d, 0, 0, 18, PURPLE)
    circ_l(d, 0, 0, 8, CHALK)
    for ang in (45, 135, 225, 315):
        a = math.radians(ang)
        line_l(d, [(math.cos(a) * 34, math.sin(a) * 34), (math.cos(a) * 45, math.sin(a) * 45)], PURPLE, 3)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_pet_effect.png")


def gen_pet_haste(ornate=False, ring=PURPLE):
    img, d = create_super_canvas()
    ell_l(d, 2, 12, 16, 13, CHALK)                                 # 掌垫
    circ_l(d, -16, -8, 7, CHALK)
    circ_l(d, 0, -14, 7, CHALK)
    circ_l(d, 16, -8, 7, CHALK)
    for oy in (-18, 2):
        line_l(d, [(-46, oy), (-30, oy)], PURPLE, 3)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_pet_haste.png")


def gen_pet_slots(ornate=False, ring=GOLD):
    img, d = create_super_canvas()
    X, Y = p(0, 0)
    d.arc([X - L(36), Y - L(24), X + L(36), Y + L(40)], 200, 340, fill=CHALK, width=int(8 * SCALE))
    for ox, oy in [(-20, 18), (0, 26), (20, 18)]:
        circ_l(d, ox, oy, 6, PURPLE)
    if ornate:
        ornate_ring(img, ring)
    auto_center_and_export(img, "upgrade_pet_slots.png")


# ---------------------------------------------------------------- 注册表
REGISTRY = {
    # 攻击 / 伤害
    "atk": gen_atk,
    "atk_grand": lambda: gen_atk(True, out="upgrade_atk_grand.png"),
    "melee": gen_melee,
    "melee_grand": lambda: gen_melee(True, out="upgrade_melee_grand.png"),
    "ranged": gen_ranged,
    "ranged_grand": lambda: gen_ranged(True, out="upgrade_ranged_grand.png"),
    "elemental": gen_elemental,
    "elemental_grand": lambda: gen_elemental(True, out="upgrade_elemental_grand.png"),
    "engineering": gen_engineering,
    "engineering_grand": lambda: gen_engineering(True, out="upgrade_engineering_grand.png"),
    "contraption": gen_contraption,
    "contraption_grand": lambda: gen_contraption(True, out="upgrade_contraption_grand.png"),
    "crit": gen_crit,
    "critdmg": gen_critdmg,
    "pierce": gen_pierce,
    "elite": gen_elite,
    "bloodlust": gen_bloodlust,
    "lifesteal": gen_lifesteal,
    "thorns": lambda: gen_thorns(False),
    "thorns_grand": lambda: gen_thorns(True, n=12, spike_r=38, hex_r=24),
    # 生存 / 身法
    "armor": gen_armor,
    "temper": gen_temper,
    "hp": gen_hp,
    "regen": gen_regen,
    "dodge": gen_dodge,
    "dodge_grand": lambda: gen_dodge(True),
    "speed": gen_speed,
    "haste": gen_haste,
    "haste_grand": lambda: gen_haste(True),
    # 经济 / 收益
    "greed": gen_greed,
    "harvest": gen_harvest,
    "luck": gen_luck,
    "merchant": gen_merchant,
    "insight": gen_insight,
    "tongxuan": gen_tongxuan,
    "chest": gen_chest,
    "chest_quality": gen_chest_quality,
    "chest_reward": gen_chest_reward,
    "range": gen_range,
    # 五行
    "metal": gen_metal,
    "wood": gen_wood,
    "water": gen_water,
    "fire": gen_fire,
    "earth": gen_earth,
    "wuxing": gen_wuxing,
    # 技能流
    "skill_cd": gen_skill_cd,
    "skill_cd_grand": lambda: gen_skill_cd(True),
    # 灵兽
    "pet_damage": gen_pet_damage,
    "pet_effect": gen_pet_effect,
    "pet_haste": gen_pet_haste,
    "pet_slots": gen_pet_slots,
}


def build_montage(out_path="tests/inspect/upgrade_icons_montage.png", cols=8, cell=150):
    from PIL import ImageFont
    names = sorted(REGISTRY.keys())
    rows = math.ceil(len(names) / cols)
    pad = 6
    W = cols * cell
    H = rows * cell
    sheet = Image.new("RGBA", (W, H), (18, 18, 22, 255))
    sd = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 13)
    except Exception:
        font = ImageFont.load_default()
    for idx, name in enumerate(names):
        r, c = divmod(idx, cols)
        icon = Image.open(os.path.join(OUTPUT_DIR, f"upgrade_{name}.png")).convert("RGBA")
        icon = icon.resize((cell - 2 * pad, cell - 2 * pad), Image.Resampling.LANCZOS)
        x0, y0 = c * cell, r * cell
        # 棋盘格底（便于看透明边）
        for gy in range(0, cell, 10):
            for gx in range(0, cell, 10):
                shade = (40, 40, 46, 255) if ((gx // 10 + gy // 10) % 2 == 0) else (30, 30, 35, 255)
                sd.rectangle([x0 + gx, y0 + gy, x0 + gx + 10, y0 + gy + 10], fill=shade)
        sheet.alpha_composite(icon, (x0 + pad, y0 + pad - 8))
        sd.text((x0 + 4, y0 + cell - 16), name, fill=(230, 230, 235, 255), font=font)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sheet.convert("RGB").save(out_path, "PNG")
    print(f"[Montage] {out_path}  ({len(names)} icons)")


if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for name, fn in REGISTRY.items():
        if only and only not in ("all", name):
            continue
        fn()
    if not only or only == "all":
        build_montage()
