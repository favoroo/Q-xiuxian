#!/usr/bin/env python3
"""生成「商店道具」专属纯色扁平矢量图标 (128x128 PNG)，一件一图（103 件）。

风格：与悟道图标同源的极简扁平几何，但道具允许更丰富的 2~4 色 + 细深色描边 + 更多细节
（天材地宝/符箓/法器需要靠细节辨识），与项目现有扁平矢量 UI 语言一致。

工程规范（照抄 generate_cold_gothic_upgrade_icons.py 骨架）：
- 512x512 超采样绘制，alpha 包围盒自动居中 + 等比缩放到 128（Lanczos）。
- 纯色块 + 细深色描边（小尺寸清晰），无渐变无柔光。
- 输出 assets/art/item_<id>.png（按 ItemData 的 id 命名，一件一图，消灭借图占位）。
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
SIZE_SUPER = SIZE_LOGICAL * SCALE
CX = 256
CY = 256

# ---- 调色板 ----
BONE = (242, 239, 228, 255)
DARK = (26, 24, 28, 255)
IRON = (154, 164, 184, 255); IRON_D = (96, 104, 124, 255)
GOLD = (240, 196, 72, 255); GOLD_D = (176, 132, 40, 255)
JADE = (92, 214, 166, 255); JADE_D = (44, 138, 100, 255)
GREEN = (112, 200, 112, 255); GREEN_D = (58, 138, 64, 255)
BLUE = (86, 150, 226, 255); BLUE_D = (44, 92, 168, 255)
RED = (214, 62, 62, 255); RED_D = (150, 34, 34, 255)
PURPLE = (176, 126, 232, 255); PURPLE_D = (112, 72, 168, 255)
ORANGE = (242, 132, 58, 255); ORANGE_D = (176, 78, 28, 255)
BROWN = (182, 130, 78, 255); BROWN_D = (120, 80, 44, 255)
WOOD = (204, 152, 92, 255); WOOD_D = (138, 96, 52, 255)
CLOTH = (214, 194, 156, 255); CLOTH_D = (150, 130, 96, 255)
PAPER = (240, 230, 198, 255); PAPER_D = (196, 182, 146, 255)
BRONZE = (198, 152, 88, 255); BRONZE_D = (136, 100, 52, 255)
CYAN = (92, 200, 220, 255); CYAN_D = (44, 132, 156, 255)
WHITE = (255, 255, 255, 255)
INKRED = (170, 32, 28, 255)   # 朱砂


# ---------------------------------------------------------------- 画布 / 导出
def create_super_canvas():
    img = Image.new("RGBA", (SIZE_SUPER, SIZE_SUPER), CLEAR)
    return img, ImageDraw.Draw(img)


def auto_center_and_export(img, filename, target_size=128, max_content_radius=42):
    arr = np.array(img); alpha = arr[:, :, 3]
    ys, xs = np.where(alpha > 10)
    if len(xs) == 0:
        print(f"[Error] {filename} 空图"); return
    min_x, max_x = int(xs.min()), int(xs.max()); min_y, max_y = int(ys.min()), int(ys.max())
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


def p(x, y):
    return (CX + x * SCALE, CY + y * SCALE)


def L(v):
    return v * SCALE


def bezier(p0, p1, p2, p3, steps=22):
    out = []
    for i in range(steps + 1):
        t = i / float(steps)
        out.append(((1-t)**3*p0[0]+3*(1-t)**2*t*p1[0]+3*(1-t)*t**2*p2[0]+t**3*p3[0],
                    (1-t)**3*p0[1]+3*(1-t)**2*t*p1[1]+3*(1-t)*t**2*p2[1]+t**3*p3[1]))
    return out


def rot(pts, deg):
    r = math.radians(deg); c, s = math.cos(r), math.sin(r)
    return [(x*c - y*s, x*s + y*c) for x, y in pts]


# ---------------------------------------------------------------- 图元（带细深色描边）
OW = 2.0  # 描边宽（逻辑像素）


def poly(d, pts, fill, ol=DARK, ow=OW):
    ap = [p(x, y) for x, y in pts]
    d.polygon(ap, fill=fill)
    if ow > 0 and ol is not None:
        d.line(ap + [ap[0]], fill=ol, width=max(1, int(round(ow*SCALE))), joint="curve")


def poly_abs(d, pts, fill, ol=DARK, ow=OW):
    d.polygon(pts, fill=fill)
    if ow > 0 and ol is not None:
        d.line(list(pts)+[pts[0]], fill=ol, width=max(1, int(round(ow*SCALE))), joint="curve")


def circ(d, cx, cy, r, fill, ol=DARK, ow=OW):
    X, Y = p(cx, cy)
    d.ellipse([X-L(r), Y-L(r), X+L(r), Y+L(r)], fill=fill)
    if ow > 0 and ol is not None:
        d.ellipse([X-L(r), Y-L(r), X+L(r), Y+L(r)], outline=ol, width=max(1, int(round(ow*SCALE))))


def ell(d, cx, cy, rx, ry, fill, ol=DARK, ow=OW):
    X, Y = p(cx, cy)
    d.ellipse([X-L(rx), Y-L(ry), X+L(rx), Y+L(ry)], fill=fill)
    if ow > 0 and ol is not None:
        d.ellipse([X-L(rx), Y-L(ry), X+L(rx), Y+L(ry)], outline=ol, width=max(1, int(round(ow*SCALE))))


def line(d, pts, color, w, cap=True):
    d.line([p(x, y) for x, y in pts], fill=color, width=max(1, int(round(w*SCALE))))


def ring(d, cx, cy, r_out, r_in, fill, ol=DARK, ow=OW):
    # 圆环（描边环）：用 arc 粗线画
    X, Y = p(cx, cy); rmid = (r_out + r_in) * 0.5; w = (r_out - r_in)
    d.ellipse([X-L(rmid), Y-L(rmid), X+L(rmid), Y+L(rmid)], outline=fill, width=max(1, int(round(w*SCALE))))
    if ol is not None:
        d.ellipse([X-L(r_out), Y-L(r_out), X+L(r_out), Y+L(r_out)], outline=ol, width=max(1, int(round(0.8*SCALE))))
        d.ellipse([X-L(r_in), Y-L(r_in), X+L(r_in), Y+L(r_in)], outline=ol, width=max(1, int(round(0.8*SCALE))))


def rrect(d, cx, cy, w, h, r, fill, ol=DARK, ow=OW):
    pts = []
    for (ax, ay, a0, a1) in [(cx+w/2-r, cy-h/2+r, -90, 0), (cx+w/2-r, cy+h/2-r, 0, 90),
                             (cx-w/2+r, cy+h/2-r, 90, 180), (cx-w/2+r, cy-h/2+r, 180, 270)]:
        for i in range(7):
            a = math.radians(a0 + (a1-a0)*i/6.0)
            pts.append((ax + r*math.cos(a), ay + r*math.sin(a)))
    poly(d, pts, fill, ol, ow)


def star(d, cx, cy, n, r_out, r_in, fill, rot_deg=-90, ol=DARK, ow=OW):
    pts = []
    for i in range(n*2):
        a = math.radians(180.0*i/n + rot_deg)
        rr = r_out if i % 2 == 0 else r_in
        pts.append((cx + math.cos(a)*rr, cy + math.sin(a)*rr))
    poly(d, pts, fill, ol, ow)


def droplet(d, cx, cy, r, fill, ol=DARK, ow=OW):
    pts = bezier((cx, cy-r*1.5), (cx-r*1.1, cy-r*0.1), (cx-r*1.0, cy+r*0.95), (cx, cy+r*0.95)) \
        + bezier((cx, cy+r*0.95), (cx+r*1.0, cy+r*0.95), (cx+r*1.1, cy-r*0.1), (cx, cy-r*1.5))
    poly_abs(d, [p(x, y) for x, y in pts], fill, ol, ow)


def flame(d, cx, cy, r, fill, ol=DARK, ow=OW):
    pts = bezier((cx, cy+r), (cx-r*1.15, cy+r*0.35), (cx-r*0.7, cy-r*0.55), (cx, cy-r*1.3)) \
        + bezier((cx, cy-r*1.3), (cx+r*0.55, cy-r*0.5), (cx+r*1.0, cy+r*0.5), (cx, cy+r))
    poly_abs(d, [p(x, y) for x, y in pts], fill, ol, ow)


def diamond(d, cx, cy, rx, ry, fill, ol=DARK, ow=OW):
    poly(d, [(cx, cy-ry), (cx+rx, cy), (cx, cy+ry), (cx-rx, cy)], fill, ol, ow)


def hexagon(d, cx, cy, r, fill, rot_deg=0, ol=DARK, ow=OW):
    poly(d, [(cx+r*math.cos(math.radians(60*i+rot_deg)), cy+r*math.sin(math.radians(60*i+rot_deg))) for i in range(6)], fill, ol, ow)


def tri(d, cx, cy, r, fill, rot_deg=-90, ol=DARK, ow=OW):
    poly(d, [(cx+r*math.cos(math.radians(120*i+rot_deg)), cy+r*math.sin(math.radians(120*i+rot_deg))) for i in range(3)], fill, ol, ow)


def shine(d, cx, cy, r, col=(255, 255, 255, 235)):
    """四芒高光星（点缀）"""
    star(d, cx, cy, 4, r, r*0.30, col, ol=None, ow=0)


# ================================================================ 母题库
# 每个函数签名 f(d, C)：C={"main","dark","accent","hi"}（均可为 RGB 元组）

def m_pot(d, C):
    # 聚宝盆 / 储蓄罐：敞口盆 + 内盛宝物
    poly(d, [(-38, 8), (-30, 34), (30, 34), (38, 8)], C["main"])
    ell(d, 0, 8, 38, 10, C["dark"])
    ell(d, 0, 8, 30, 7, (0, 0, 0, 0), ol=C["dark"], ow=1.4)
    for ox, oy, r in [(-16, 4, 7), (0, 0, 8), (16, 5, 7)]:
        circ(d, ox, oy, r, C["accent"])
    shine(d, -8, -8, 6)
    line(d, [(-30, 22), (30, 22)], C["dark"], 2)


def m_bag(d, C):
    # 钱袋 / 聚财袋
    body = bezier((-30, 10), (-40, 46), (40, 46), (30, 10))
    poly_abs(d, [p(x, y) for x, y in body] + [p(-30, 10)], C["main"])
    poly(d, [(-18, 10), (18, 10), (12, -2), (-12, -2)], C["main"])
    line(d, [(-16, 2), (16, 2)], C["dark"], 3)
    circ(d, 0, 24, 8, C["accent"])
    line(d, [(0, 20), (0, 28)], C["dark"], 1.6); line(d, [(-4, 24), (4, 24)], C["dark"], 1.6)


def m_compass(d, C):
    # 罗盘 / 星盘：外环 + 刻度 + 指针
    circ(d, 0, 0, 40, C["main"])
    circ(d, 0, 0, 32, C["dark"])
    circ(d, 0, 0, 26, C["main"])
    for i in range(8):
        a = math.radians(45*i)
        line(d, [(math.cos(a)*27, math.sin(a)*27), (math.cos(a)*33, math.sin(a)*33)], C["accent"], 2)
    diamond(d, 0, -14, 6, 18, C["accent"])
    diamond(d, 0, 14, 6, 12, C["dark"])
    circ(d, 0, 0, 4, C["accent"])


def m_boot(d, C):
    # 靴
    poly(d, [(-8, -34), (14, -34), (14, 8), (34, 14), (34, 26), (-18, 26), (-18, 4), (-8, -4)], C["main"])
    poly(d, [(-18, 20), (34, 20), (34, 28), (-18, 28)], C["dark"])
    line(d, [(-2, -20), (-2, 6)], C["accent"], 2.2)
    for oy in (0, 8):
        line(d, [(6, oy), (12, oy-4)], C["accent"], 1.6)


def m_vial(d, C):
    # 药瓶
    rrect(d, 0, 10, 34, 40, 8, C["main"])
    poly(d, [(-10, -30), (10, -30), (10, -12), (-10, -12)], C["main"])
    rrect(d, 0, -32, 24, 8, 3, C["accent"])
    rrect(d, 0, 14, 22, 20, 5, C["accent"])
    shine(d, -6, 2, 6)


def m_food(d, C):
    # 口粮袋（麻袋）
    poly(d, [(-26, -20), (26, -20), (32, 30), (-32, 30)], C["main"])
    poly(d, [(-20, -34), (20, -34), (26, -20), (-26, -20)], C["dark"])
    line(d, [(-20, -22), (20, -22)], C["accent"], 3)
    circ(d, 0, 6, 10, C["accent"])
    circ(d, 0, 6, 4, C["dark"])


def m_coupon(d, C):
    # 折扣券（票券 + 锯齿边 + 叉）
    poly(d, [(-38, -22), (38, -22), (38, 22), (-38, 22)], C["main"])
    for i in range(4):
        x = -38 + i*20
        poly(d, [(x, -22), (x+10, -22), (x+10, -14), (x, -14)], C["dark"], ol=None, ow=0)
        poly(d, [(x, 22), (x+10, 22), (x+10, 14), (x, 14)], C["dark"], ol=None, ow=0)
    circ(d, 16, 0, 12, C["accent"])
    line(d, [(10, -6), (22, 6)], C["dark"], 2.4); line(d, [(22, -6), (10, 6)], C["dark"], 2.4)


def m_armor(d, C):
    # 甲片 / 护甲（六边形甲片 + 铆钉）
    hexagon(d, 0, 0, 40, C["main"], rot_deg=0)
    hexagon(d, 0, 0, 26, C["dark"], rot_deg=0)
    circ(d, 0, 0, 10, C["accent"])
    for a in (0, 60, 120, 180, 240, 300):
        ang = math.radians(a)
        circ(d, math.cos(ang)*33, math.sin(ang)*33, 3, C["accent"])


def m_bell(d, C):
    # 铃铛
    dome = bezier((-26, 20), (-30, -30), (30, -30), (26, 20))
    poly_abs(d, [p(x, y) for x, y in dome] + [p(28, 20), p(28, 28), p(-28, 28), p(-28, 20)], C["main"])
    circ(d, 0, -34, 5, C["accent"])
    line(d, [(-26, 24), (26, 24)], C["dark"], 2)
    circ(d, 0, 34, 6, C["accent"])


def m_talisman(d, C):
    # 符纸：竖长符 + 符头 + 按 glyph 变体的朱砂符身 + 方印
    poly(d, [(-20, -40), (20, -40), (24, 34), (-24, 34)], C["main"])
    line(d, [(-18, -36), (18, -36)], C["accent"], 2)
    line(d, [(-12, -30), (-12, -22), (12, -22), (12, -30)], C["accent"], 2.2)  # 符头云勾
    g = C.get("glyph", "line")
    if g == "wind":
        line(d, [(-10,-10),(-2,-14),(8,-8)], C["accent"], 2.4)
        line(d, [(-10,2),(0,-2),(10,4)], C["accent"], 2.2)
        line(d, [(-8,14),(2,10),(10,16)], C["accent"], 2.0)
    elif g == "spiral":
        pts=[(math.cos(math.radians(20*i))* (16-i*0.9), math.sin(math.radians(20*i))*(16-i*0.9)) for i in range(10)]
        line(d, pts, C["accent"], 2.2)
    elif g == "blood":
        droplet(d, 0, 2, 12, C["accent"], ol=C["dark"], ow=1.4)
        line(d, [(-8,18),(8,18)], C["accent"], 2)
    elif g == "blade":
        poly(d, [(0,-16),(5,-2),(3,16),(0,22),(-3,16),(-5,-2)], C["accent"], ol=C["dark"], ow=1.2)
    elif g == "pierce":
        line(d, [(-10,14),(10,-14)], C["accent"], 2.6)
        line(d, [(10,-14),(4,-10)], C["accent"], 2.2); line(d, [(10,-14),(6,-6)], C["accent"], 2.2)
        line(d, [(-10,4),(-2,0)], C["accent"], 1.8)
    elif g == "yinyang":
        circ(d, 0, 2, 13, C["accent"], ol=C["dark"], ow=1.2)
        circ(d, 0, -4, 4, C["main"], ol=C["dark"], ow=1.0)
        circ(d, 0, 8, 4, C["dark"], ol=None, ow=0)
    elif g == "flame":
        flame(d, 0, 4, 14, C["accent"], ol=C["dark"], ow=1.2)
    elif g == "star":
        star(d, 0, 2, 5, 15, 6, C["accent"], ol=C["dark"], ow=1.2)
    elif g == "lotus":
        for a in (-55,0,55):
            ell(d, math.sin(math.radians(a))*8, 6, 5, 12, C["accent"], ol=C["dark"], ow=1.0)
    elif g == "wave":
        for oy in (-4,6,16):
            line(d, [(-10,oy),(-3,oy-4),(3,oy+4),(10,oy)], C["accent"], 2.2)
    elif g == "eye":
        ell(d, 0, 4, 15, 8, C["main"], ol=C["accent"], ow=2.0)
        circ(d, 0, 4, 5, C["accent"])
    else:
        line(d, [(0,-16),(0,20)], C["accent"], 2.4)
        line(d, [(-10,-6),(10,-6)], C["accent"], 2)
        line(d, [(-8,8),(8,8)], C["accent"], 2)
    poly(d, [(-9, 22), (9, 22), (9, 32), (-9, 32)], C["accent"])


def m_lock(d, C):
    # 枷锁 / 锁（环 + 锁体）
    ring(d, 0, -12, 20, 12, C["dark"])
    rrect(d, 0, 16, 40, 32, 6, C["main"])
    circ(d, 0, 14, 6, C["dark"])
    line(d, [(0, 14), (0, 24)], C["dark"], 3)


def m_jade(d, C):
    # 玉璧 / 玉佩（环形 + 云纹）
    circ(d, 0, 0, 40, C["main"])
    circ(d, 0, 0, 24, C["dark"])
    for i in range(4):
        a = math.radians(90*i)
        line(d, [(math.cos(a)*26, math.sin(a)*26), (math.cos(a)*38, math.sin(a)*38)], C["accent"], 2)
    circ(d, 0, -40, 5, C["accent"])  # 挂环


def m_ore(d, C):
    # 矿石 / 晶石（棱面多边块）
    poly(d, [(-34, 10), (-20, -26), (10, -34), (34, -8), (24, 28), (-16, 30)], C["main"])
    poly(d, [(-20, -26), (10, -34), (2, -6), (-14, -2)], C["accent"], ol=None, ow=0)
    poly(d, [(10, -34), (34, -8), (14, 4), (2, -6)], C["dark"], ol=None, ow=0)
    line(d, [(-16, 30), (2, -6)], C["dark"], 1.6)
    shine(d, -8, -12, 7)


def m_gourd(d, C):
    # 葫芦
    circ(d, 0, 16, 24, C["main"])
    circ(d, 0, -18, 16, C["main"])
    rrect(d, 0, -34, 12, 8, 3, C["accent"])
    line(d, [(-9, 0), (9, 0)], C["dark"], 3)
    shine(d, -7, -20, 5)


def m_needle(d, C):
    # 针 / 锥（细长 + 尾环）
    poly(d, [(0, -40), (6, -10), (4, 20), (0, 30), (-4, 20), (-6, -10)], C["main"])
    circ(d, 0, -34, 4, C["accent"])
    line(d, [(0, -26), (0, 12)], C["dark"], 1.4)
    circ(d, 0, 30, 4, C["accent"])


def m_cage(d, C):
    # 笼 / 兽笼
    rrect(d, 0, 4, 52, 52, 6, C["main"])
    for i in range(-1, 2):
        line(d, [(i*16, -20), (i*16, 28)], C["dark"], 2.2)
    poly(d, [(-30, -28), (30, -28), (24, -20), (-24, -20)], C["accent"])
    circ(d, 0, -24, 4, C["dark"])


def m_doll(d, C):
    # 替身娃娃（简易人形）
    circ(d, 0, -22, 13, C["main"])
    poly(d, [(-12, -10), (12, -10), (16, 26), (-16, 26)], C["main"])
    line(d, [(-12, 0), (-26, 14)], C["accent"], 5); line(d, [(12, 0), (26, 14)], C["accent"], 5)
    line(d, [(-6, 26), (-10, 40)], C["accent"], 5); line(d, [(6, 26), (10, 40)], C["accent"], 5)
    line(d, [(-6, -22), (6, -22)], C["dark"], 2)


def m_orb(d, C):
    # 宝珠 / 灵珠（多棱珠 + 内核）
    circ(d, 0, 0, 36, C["main"])
    poly(d, [(0, -26), (18, -6), (10, 20), (-10, 20), (-18, -6)], C["accent"], ol=None, ow=0)
    circ(d, 0, -2, 9, C["dark"])
    shine(d, -12, -12, 8)


def m_pill(d, C):
    # 丹药（圆丹 + 云纹）
    circ(d, 0, 4, 34, C["main"])
    circ(d, 0, 4, 34, (0, 0, 0, 0), ol=C["dark"], ow=2)
    for oy in (-8, 4, 16):
        line(d, [(-16, oy), (-6, oy-6), (4, oy), (14, oy-6)], C["accent"], 2)
    shine(d, -10, -8, 7)


def m_whetstone(d, C):
    # 砺石（磨刀石 + 刃光）
    poly(d, [(-40, 10), (40, 10), (34, 30), (-34, 30)], C["main"])
    poly(d, [(-40, 10), (40, 10), (30, -4), (-30, -4)], C["dark"])
    line(d, [(-20, 20), (20, 20)], C["accent"], 2)
    shine(d, 8, -8, 8)


def m_blade(d, C):
    # 刃（短刃 + 破空线）
    poly(d, [(0, -40), (8, -12), (6, 22), (0, 30), (-6, 22), (-8, -12)], C["main"])
    line(d, [(-20, 6), (-10, 2)], C["accent"], 2.4)
    line(d, [(-22, 16), (-12, 12)], C["accent"], 2)


def m_bracelet(d, C):
    # 金刚琢 / 手环
    ring(d, 0, 0, 38, 26, C["main"])
    for i in range(6):
        a = math.radians(60*i)
        circ(d, math.cos(a)*32, math.sin(a)*32, 4, C["accent"])


def m_cone(d, C):
    # 锥（长锥 + 箍环）
    poly(d, [(0, -42), (14, 18), (0, 30), (-14, 18)], C["main"])
    line(d, [(-11, 4), (11, 4)], C["accent"], 3)
    line(d, [(-8, 14), (8, 14)], C["accent"], 2.4)


def m_scroll(d, C):
    # 卷轴 / 阵图
    rrect(d, 0, 0, 56, 44, 4, C["main"])
    ell(d, -28, 0, 8, 24, C["dark"])
    ell(d, 28, 0, 8, 24, C["dark"])
    for oy in (-10, 0, 10):
        line(d, [(-14, oy), (14, oy)], C["accent"], 1.6)
    circ(d, 0, 0, 6, C["accent"])


def m_tassel(d, C):
    # 剑穗 / 流苏
    circ(d, 0, -34, 8, C["accent"])
    line(d, [(0, -26), (0, 0)], C["main"], 3)
    for i in range(-2, 3):
        line(d, [(0, 0), (i*7, 34)], C["main"], 3)


def m_seal(d, C):
    # 印 / 大印（方印身 + 拱钮）
    rrect(d, 0, 12, 46, 34, 4, C["main"])
    ring(d, 0, -18, 14, 8, C["accent"])
    rrect(d, 0, -6, 20, 10, 3, C["dark"])
    line(d, [(-16, 18), (16, 18)], C["dark"], 2)
    line(d, [(-16, 26), (16, 26)], C["dark"], 2)


def m_dial(d, C):
    # 天机盘 / 星盘（多重环 + 星）
    circ(d, 0, 0, 42, C["main"])
    circ(d, 0, 0, 34, C["dark"])
    for i in range(12):
        a = math.radians(30*i)
        line(d, [(math.cos(a)*34, math.sin(a)*34), (math.cos(a)*40, math.sin(a)*40)], C["accent"], 1.8)
    star(d, 0, 0, 5, 22, 9, C["accent"])
    circ(d, 0, 0, 5, C["dark"])


def m_gear(d, C):
    # 机关齿轮 / 核心
    for i in range(8):
        tooth = rot([(-7, -42), (7, -42), (7, -28), (-7, -28)], 45*i)
        poly(d, tooth, C["main"])
    circ(d, 0, 0, 30, C["main"])
    circ(d, 0, 0, 18, C["accent"])
    circ(d, 0, 0, 8, C["dark"])


def m_map(d, C):
    # 藏宝图 / 图谱（折页 + 路线 + X）
    poly(d, [(-38, -26), (-12, -32), (12, -24), (38, -30), (38, 26), (12, 32), (-12, 24), (-38, 30)], C["main"])
    line(d, [(-12, -32), (-12, 24)], C["dark"], 1.6); line(d, [(12, -24), (12, 32)], C["dark"], 1.6)
    line(d, [(-26, 4), (-6, -6), (8, 6), (22, -4)], C["accent"], 2)
    line(d, [(16, 6), (26, 16)], C["accent"], 2.6); line(d, [(26, 6), (16, 16)], C["accent"], 2.6)


def m_plate(d, C):
    # 牌 / 令牌
    rrect(d, 0, 0, 40, 62, 8, C["main"])
    circ(d, 0, -22, 5, C["dark"])
    line(d, [(-12, -8), (12, -8)], C["accent"], 2.2)
    line(d, [(-12, 4), (12, 4)], C["accent"], 2.2)
    line(d, [(-8, 16), (8, 16)], C["accent"], 2)


def m_formula(d, C):
    # 诀 / 书册（翻开的册页 + 符文）
    poly(d, [(-40, -22), (-4, -28), (-4, 28), (-40, 22)], C["main"])
    poly(d, [(40, -22), (4, -28), (4, 28), (40, 22)], C["main"])
    line(d, [(0, -28), (0, 28)], C["dark"], 2)
    for oy in (-8, 4, 16):
        line(d, [(-30, oy), (-10, oy-2)], C["accent"], 1.6)
        line(d, [(10, oy-2), (30, oy)], C["accent"], 1.6)


def m_robe(d, C):
    # 甲 / 衣（披甲形）
    poly(d, [(-30, -30), (30, -30), (38, 6), (24, 10), (24, 34), (-24, 34), (-24, 10), (-38, 6)], C["main"])
    line(d, [(-18, -30), (0, -10), (18, -30)], C["dark"], 2)
    line(d, [(0, -10), (0, 30)], C["dark"], 2)
    for oy in (0, 14):
        line(d, [(-16, oy), (16, oy)], C["accent"], 1.6)


def m_bracer(d, C):
    # 护腕 / 手套
    rrect(d, 0, 6, 34, 40, 8, C["main"])
    poly(d, [(-17, -14), (17, -14), (20, -30), (-20, -30)], C["dark"])
    for oy in (-2, 10):
        line(d, [(-14, oy), (14, oy)], C["accent"], 2)
    shine(d, 0, 18, 6)


def m_mirror(d, C):
    # 镜（圆镜 + 边框 + 柄）
    circ(d, 0, -8, 32, C["main"])
    circ(d, 0, -8, 24, C["accent"])
    for i in range(3):
        line(d, [(-14+i*8, -20), (10-i*4, 0)], (255, 255, 255, 200), 2)
    rrect(d, 0, 30, 8, 22, 3, C["dark"])


def m_arrow(d, C):
    # 箭 / 矢（箭杆 + 箭头 + 尾羽）
    line(d, [(-36, 0), (28, 0)], C["main"], 4)
    poly(d, [(36, 0), (18, -10), (18, 10)], C["accent"])
    poly(d, [(-36, 0), (-26, -8), (-22, 0), (-26, 8)], C["accent"])


def m_flag(d, C):
    # 旗 / 幡（旗杆 + 旗面）
    line(d, [(-26, -38), (-26, 38)], C["dark"], 4)
    poly(d, [(-24, -34), (34, -26), (26, -4), (34, 18), (-24, 26)], C["main"])
    line(d, [(-14, -18), (16, -12)], C["accent"], 2)
    line(d, [(-14, 0), (16, 6)], C["accent"], 2)


def m_statue(d, C):
    # 神像（端坐像 + 背光）
    circ(d, 0, -6, 34, C["accent"], ol=C["dark"], ow=1.4)
    circ(d, 0, -22, 10, C["main"])
    poly(d, [(-16, -10), (16, -10), (20, 30), (-20, 30)], C["main"])
    line(d, [(-12, 4), (12, 4)], C["dark"], 2)


def m_altar(d, C):
    # 法坛（层叠台 + 供）
    poly(d, [(-36, 30), (36, 30), (28, 18), (-28, 18)], C["main"])
    poly(d, [(-28, 18), (28, 18), (22, 4), (-22, 4)], C["dark"])
    rrect(d, 0, -6, 30, 14, 3, C["main"])
    circ(d, 0, -20, 8, C["accent"])


def m_cushion(d, C):
    # 蒲团（圆垫 + 束纹）
    ell(d, 0, 8, 38, 24, C["main"])
    ell(d, 0, 2, 30, 16, C["dark"])
    for i in range(6):
        a = math.radians(60*i)
        line(d, [(math.cos(a)*12, 2+math.sin(a)*7), (math.cos(a)*30, 8+math.sin(a)*18)], C["accent"], 1.4)


def m_incense(d, C):
    # 香（香炉 + 三炷香 + 烟）
    poly(d, [(-26, 8), (26, 8), (20, 30), (-20, 30)], C["main"])
    ell(d, 0, 8, 26, 7, C["dark"])
    for ox in (-10, 0, 10):
        line(d, [(ox, 6), (ox, -22)], C["accent"], 2.2)
        circ(d, ox, -24, 2.4, (255, 255, 255, 220))


def m_token(d, C):
    # 令 / 令牌（圆牌 + 云雷纹）
    circ(d, 0, 0, 38, C["main"])
    circ(d, 0, 0, 30, C["dark"])
    line(d, [(-14, -6), (-4, -14), (6, -6), (16, -14)], C["accent"], 2.2)
    line(d, [(0, 2), (0, 22)], C["accent"], 2.4)
    circ(d, 0, -34, 5, C["accent"])


def m_silk(d, C):
    # 幻纱（飘带 / 薄纱）
    pts = bezier((-34, -20), (-10, -34), (10, 20), (34, -6))
    d.line([p(x, y) for x, y in pts], fill=C["main"], width=int(6*SCALE))
    pts2 = bezier((-30, 6), (-8, -8), (12, 34), (32, 10))
    d.line([p(x, y) for x, y in pts2], fill=C["accent"], width=int(4*SCALE))
    shine(d, 20, -18, 6)


def m_herbbag(d, C):
    # 灵草袋（袋 + 露出的草）
    poly(d, [(-26, 0), (26, 0), (30, 32), (-30, 32)], C["main"])
    line(d, [(-24, 2), (24, 2)], C["dark"], 3)
    for ox in (-12, 0, 12):
        line(d, [(ox, 0), (ox*1.3, -24)], C["accent"], 2.4)
        circ(d, ox*1.3, -26, 4, C["accent"])


def m_bloodbead(d, C):
    # 嗜血珠 / 血纹（珠 + 血纹）
    circ(d, 0, 0, 34, C["main"])
    for i in range(3):
        a = math.radians(120*i-90)
        line(d, [(0, 0), (math.cos(a)*28, math.sin(a)*28)], C["accent"], 2.2)
    circ(d, 0, 0, 8, C["accent"])
    shine(d, -10, -10, 6)


def m_swordcharm(d, C):
    # 剑穗（剑 + 穗）
    poly(d, [(0, -40), (6, -14), (4, 14), (0, 20), (-4, 14), (-6, -14)], C["main"])
    line(d, [(-12, 12), (12, 12)], C["dark"], 3)
    circ(d, 0, 26, 6, C["accent"])
    for i in range(-1, 2):
        line(d, [(i*4, 30), (i*7, 40)], C["accent"], 2)


def m_crystal(d, C):
    # 晶（菱形晶体簇）
    diamond(d, 0, 2, 22, 38, C["main"])
    diamond(d, -22, 14, 12, 22, C["accent"])
    diamond(d, 20, 16, 10, 18, C["accent"])
    line(d, [(0, -36), (0, 40)], C["dark"], 1.2)
    shine(d, -6, -12, 7)


def m_feather(d, C):
    # 羽（灵羽）
    pts = bezier((0, 40), (-24, 16), (-24, -24), (0, -40)) + bezier((0, -40), (24, -24), (24, 16), (0, 40))
    poly_abs(d, [p(x, y) for x, y in pts], C["main"])
    line(d, [(0, 34), (0, -34)], C["dark"], 1.8)
    for oy in (-16, -2, 12):
        line(d, [(0, oy), (-10, oy-8)], C["accent"], 1.4)
        line(d, [(0, oy), (10, oy-8)], C["accent"], 1.4)


def m_cloak(d, C):
    # 披风 / 皮裙（衣摆）
    poly(d, [(-18, -30), (18, -30), (26, 30), (10, 22), (0, 32), (-10, 22), (-26, 30)], C["main"])
    line(d, [(-16, -20), (16, -20)], C["accent"], 2.4)
    line(d, [(-14, 6), (14, 6)], C["dark"], 1.6)


# ================================================================ 规格表：id -> (母题, 颜色)
def C(main, dark, accent, hi=WHITE, glyph="line"):
    return {"main": main, "dark": dark, "accent": accent, "hi": hi, "glyph": glyph, "tier": 1}

# 常用配色
GOLD_C = C(GOLD, GOLD_D, ORANGE)
JADE_C = C(JADE, JADE_D, GOLD)
IRON_C = C(IRON, IRON_D, GOLD)
WOOD_C = C(WOOD, WOOD_D, GREEN)
PAPER_C = C(PAPER, PAPER_D, INKRED)
BROWN_C = C(BROWN, BROWN_D, GOLD)
PURPLE_C = C(PURPLE, PURPLE_D, GOLD)
BLUE_C = C(BLUE, BLUE_D, CYAN)
RED_C = C(RED, RED_D, GOLD)
CLOTH_C = C(CLOTH, CLOTH_D, RED)
BRONZE_C = C(BRONZE, BRONZE_D, JADE)
CYAN_C = C(CYAN, CYAN_D, BLUE)
BONE_C = C(BONE, IRON_D, GOLD)
GREEN_C = C(GREEN, GREEN_D, GOLD)
ORANGE_C = C(ORANGE, ORANGE_D, GOLD)
# 五行
M_METAL_C = C(GOLD, GOLD_D, BONE)
M_WOOD_C = C(GREEN, GREEN_D, WOOD)
M_WATER_C = C(BLUE, BLUE_D, CYAN)
M_FIRE_C = C(ORANGE, ORANGE_D, RED)
M_EARTH_C = C(BROWN, BROWN_D, CLOTH)

SPEC = {
    # ---- 经济 / 杂项 ----
    "jubaopen": ("pot", GOLD_C),
    "jubao_pen": ("pot", JADE_C),
    "mibao_luopan": ("compass", GOLD_C),
    "dingxing_pan": ("compass", CYAN_C),
    "jifeng_xue": ("boot", GREEN_C),
    "lingbo_xue": ("boot", CYAN_C),
    "shenxing_xue": ("boot", BLUE_C),
    "qingxin_cha": ("vial", JADE_C),
    "kuangxue_dan": ("vial", RED_C),
    "lingshou_kouliang": ("food", BROWN_C),
    "zhekou_yufu": ("coupon", GOLD_C),
    "yushou_ling": ("bell", JADE_C),
    "tongling": ("bell", BRONZE_C),
    "huanying_ling": ("bell", PURPLE_C),
    "liehun_ling": ("bell", RED_C),
    "jifeng_shoufu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="wind")),
    "juling_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="lotus")),
    "xuewen_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="blood")),
    "liren_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="blade")),
    "poxu_lingfu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="pierce")),
    "hunyuan_yiqifu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="yinyang")),
    "lingyan_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="flame")),
    "pojun_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="star")),
    "jingxin_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="spiral")),
    "xuehai_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="wave")),
    "ranxue_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="blood")),
    "ningshen_fu": ("talisman", C(PAPER, PAPER_D, INKRED, glyph="eye")),
    "suoling_jia": ("lock", IRON_C),
    "tianji_suo": ("lock", BRONZE_C),
    "luban_suo": ("lock", WOOD_C),
    "wuxing_pei": ("jade", JADE_C),
    "hantan_yu": ("jade", BLUE_C),
    "tupo_guyu": ("jade", JADE_C),
    "xuepan_guyu": ("jade", RED_C),
    "liuyun_qianyin": ("jade", CYAN_C),
    "wujian_shi": ("ore", BLUE_C),
    "leiling_zhu": ("orb", PURPLE_C),
    "huichun_hulu": ("gourd", JADE_C),
    "pojia_zhui": ("needle", IRON_C),
    "wuji_tianchuan_zhen": ("needle", CYAN_C),
    "wanshou_long": ("cage", IRON_C),
    "tisi_kuilei": ("doll", CLOTH_C),
    "yinxue_zhu": ("bloodbead", RED_C),
    "hunyuan_zhu": ("orb", GOLD_C),
    "taiyi_jindan": ("pill", GOLD_C),
    "lijian_shi": ("whetstone", IRON_C),
    "feihuang_shi": ("ore", BROWN_C),
    "liannu_shi": ("ore", IRON_C),
    "wuxing_sha": ("ore", JADE_C),
    "jinjing_shi": ("ore", M_METAL_C),
    "taijin_jing": ("ore", M_METAL_C),
    "chenxiang_mu": ("ore", M_WOOD_C),
    "yimu_sui": ("ore", M_WOOD_C),
    "dihuo_jing": ("crystal", M_FIRE_C),
    "lihuo_shenjing": ("crystal", M_FIRE_C),
    "houtu_he": ("ore", M_EARTH_C),
    "houtu_shenyuan": ("ore", M_EARTH_C),
    "xuanshui_po": ("crystal", M_WATER_C),
    "jifeng_ren": ("blade", GREEN_C),
    "jingang_zhuo": ("bracelet", GOLD_C),
    "potian_zhui": ("cone", IRON_C),
    "juling_zhentu": ("scroll", CYAN_C),
    "zhuxian_sui": ("swordcharm", RED_C),
    "xuanwu_yin": ("seal", IRON_C),
    "budong_yin": ("seal", GOLD_C),
    "panshi_yin": ("seal", BROWN_C),
    "qianfu_lianhuan": ("seal", PAPER_C),
    "tianji_pan": ("dial", GOLD_C),
    "jiguan_hexin": ("gear", BRONZE_C),
    "tongji_chi": ("gear", WOOD_C),
    "tiangong_fatiao": ("gear", IRON_C),
    "cangbao_tu": ("map", PAPER_C),
    "cangzhen_juan": ("map", GOLD_C),
    "kaishan_jianyi": ("map", WOOD_C),
    "yuling_pai": ("plate", JADE_C),
    "naling_zhuo": ("plate", CYAN_C),
    "dianjin_jue": ("formula", GOLD_C),
    "hupi_qun": ("cloak", BROWN_C),
    "shanyue_jia": ("robe", BROWN_C),
    "bumie_jinshen": ("robe", GOLD_C),
    "manli_huwan": ("bracer", BROWN_C),
    "tieshou": ("bracer", IRON_C),
    "xiuluo_pei": ("bloodbead", RED_C),
    "jucai_dai": ("bag", GOLD_C),
    "daoyun_jing": ("mirror", CYAN_C),
    "wanshi_jian": ("arrow", IRON_C),
    "zhanqi": ("flag", RED_C),
    "wanling_fan": ("flag", PURPLE_C),
    "jingang_shenxiang": ("statue", GOLD_C),
    "xuanwu_fashan": ("altar", IRON_C),
    "dazuo_putuan": ("cushion", CLOTH_C),
    "ruding_xiang": ("incense", JADE_C),
    "tongxuan_ling": ("token", GOLD_C),
    "xuantie_ling": ("token", IRON_C),
    "jinmang_souhun": ("token", GOLD_C),
    "huansha": ("silk", PURPLE_C),
    "lingcao_dai": ("herbbag", GREEN_C),
    "lingsui_danqi": ("vial", JADE_C),
    "guijia_fu": ("armor", IRON_C),
    "fanzhen_tongjia": ("armor", BRONZE_C),
    "jingang_fumo_jia": ("armor", GOLD_C),
    "sanmei_guizhen": ("orb", M_FIRE_C),
    "tiangang_zhanyi": ("seal", GOLD_C),
}

# ---- 稀有度表（用于层级装饰：T1 无 / T2 双角标 / T3 底光弧+星点 / T4 金环+双星）----
TIER = {
    # T1
    "jubaopen":1,"mibao_luopan":1,"jifeng_xue":1,"qingxin_cha":1,"lingshou_kouliang":1,
    "lijian_shi":1,"feihuang_shi":1,"juling_fu":1,"yuling_pai":1,"hupi_qun":1,"manli_huwan":1,
    "xuewen_fu":1,"cangbao_tu":1,"dazuo_putuan":1,"tieshou":1,"lingyan_fu":1,"tongling":1,
    # T2
    "zhekou_yufu":2,"kuangxue_dan":2,"guijia_fu":2,"yushou_ling":2,"jifeng_shoufu":2,
    "tongxuan_ling":2,"suoling_jia":2,"lingbo_xue":2,"jinjing_shi":2,"chenxiang_mu":2,
    "hantan_yu":2,"dihuo_jing":2,"houtu_he":2,"liren_fu":2,"yinxue_zhu":2,"dingxing_pan":2,
    "jucai_dai":2,"poxu_lingfu":2,"fanzhen_tongjia":2,"luban_suo":2,"naling_zhuo":2,
    "tiangong_fatiao":2,"kaishan_jianyi":2,"ningshen_fu":2,"lingyan_fu":2,"pojun_fu":2,
    "liannu_shi":2,"wuxing_sha":2,"tongji_chi":2,"jingxin_fu":2,"huansha":2,"lingcao_dai":2,
    "lingsui_danqi":2,"ruding_xiang":2,
    # T3
    "wuxing_pei":3,"wujian_shi":3,"huichun_hulu":3,"pojia_zhui":3,"xiuluo_pei":3,
    "wanshou_long":3,"potian_zhui":3,"jingang_zhuo":3,"shenxing_xue":3,"leiling_zhu":3,
    "juling_zhentu":3,"hunyuan_yiqifu":3,"jingang_fumo_jia":3,"jiguan_hexin":3,"dianjin_jue":3,
    "jifeng_ren":3,"huanying_ling":3,"jubao_pen":3,"ranxue_fu":3,"budong_yin":3,"taijin_jing":3,
    "yimu_sui":3,"xuanshui_po":3,"lihuo_shenjing":3,"houtu_shenyuan":3,"xuanwu_fashan":3,
    "jingang_shenxiang":3,"liuyun_qianyin":3,"jinmang_souhun":3,"qianfu_lianhuan":3,
    "wanling_fan":3,"tianji_suo":3,"zhanqi":3,"cangzhen_juan":3,"xuehai_fu":3,"xuantie_ling":3,
    # T4
    "tisi_kuilei":4,"hunyuan_zhu":4,"taiyi_jindan":4,"zhuxian_sui":4,"xuanwu_yin":4,
    "tianji_pan":4,"wuji_tianchuan_zhen":4,"shanyue_jia":4,"xuepan_guyu":4,"liehun_ling":4,
    "panshi_yin":4,"sanmei_guizhen":4,"tupo_guyu":4,"bumie_jinshen":4,"tiangang_zhanyi":4,
    "daoyun_jing":4,"wanshi_jian":4,
}


def _tier_ornament(d, C, tier):
    """层级装饰：同材质不同档靠此区分，也让高稀有度更精致（不喧宾夺主）。"""
    if tier <= 1:
        return
    acc = C["accent"]; dark = C["dark"]
    if tier == 2:
        # 双角标：左右下各一点小菱形
        for sx in (-1, 1):
            diamond(d, sx*40, 30, 4.5, 6.5, acc, ol=dark, ow=1.0)
    elif tier == 3:
        # 底光弧 + 两点星
        arc = [(math.cos(math.radians(a))*46, 44+math.sin(math.radians(a))*8) for a in range(200, 341, 10)]
        line(d, arc, acc, 1.8)
        shine(d, -34, -34, 5, (255,255,255,220)); shine(d, 34, -30, 4, (255,255,255,200))
    else:
        # 传说：外金环（断口）+ 双星
        ring(d, 0, 0, 50, 47, GOLD, ol=GOLD_D, ow=0.8)
        shine(d, -38, -34, 7); shine(d, 38, -34, 6)


MOTIFS = {name[2:]: fn for name, fn in globals().items() if name.startswith("m_") and callable(fn)}


def generate_all(only=None):
    missing = []
    for iid, (motif, colors) in SPEC.items():
        if only and only not in ("all", iid):
            continue
        fn = MOTIFS.get(motif)
        if fn is None:
            missing.append((iid, motif)); continue
        colors["tier"] = TIER.get(iid, 1)
        img, d = create_super_canvas()
        fn(d, colors)
        _tier_ornament(d, colors, colors["tier"])
        auto_center_and_export(img, f"item_{iid}.png")
    if missing:
        print("[Missing motifs]", missing)
    print(f"[ItemIconGen] 生成 {len(SPEC)} 件")


if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else None
    generate_all(only)
