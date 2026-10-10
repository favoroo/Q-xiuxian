#!/usr/bin/env python3
"""生成 5 大随行神通技能的极简纯白单色扁平矢量图标 (128x128 PNG)
严格美术与工程规范：
- 极简、单色 (纯白 #FFFFFF + 透明底)、扁平几何剪影
- 512x512 超采样绘制，计算 Alpha 包围盒后精确平移至 (256, 256) 绝对居中
- 通过 Lanczos 下采样至 128x128，达到视网膜级平滑抗锯齿
- 纯白单色天然支持 Godot modulate 动态状态着色 (GameStyle.PAPER, JADE, GOLD, GREY)
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageChops

OUTPUT_DIR = "assets/art"
os.makedirs(OUTPUT_DIR, exist_ok=True)

WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
SCALE = 4
SIZE_LOGICAL = 128
SIZE_SUPER = SIZE_LOGICAL * SCALE  # 512
CX = 256
CY = 256

def create_super_canvas():
    img = Image.new("RGBA", (SIZE_SUPER, SIZE_SUPER), CLEAR)
    draw = ImageDraw.Draw(img)
    return img, draw

def auto_center_and_export(img, filename, target_size=128, max_content_radius=42):
    """提取 alpha 通道，计算真实像素包围盒，将其几何中心平移对准 (256, 256)，并进行等比缩放适配"""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    y_indices, x_indices = np.where(alpha > 10)
    if len(x_indices) == 0:
        print(f"[Error] 图标 {filename} 无有效像素！")
        return

    min_x, max_x = int(np.min(x_indices)), int(np.max(x_indices))
    min_y, max_y = int(np.min(y_indices)), int(np.max(y_indices))

    content_w = max_x - min_x + 1
    content_h = max_y - min_y + 1

    # 目标最大跨度
    target_span = max_content_radius * 2 * SCALE
    curr_span = max(content_w, content_h)
    zoom = target_span / float(curr_span)

    # 提取内容切片
    cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1))
    new_w = max(1, int(round(content_w * zoom)))
    new_h = max(1, int(round(content_h * zoom)))
    rescaled_content = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)

    # 创建新的 512 居中画布贴入
    centered = Image.new("RGBA", (SIZE_SUPER, SIZE_SUPER), CLEAR)
    paste_x = int(round(CX - new_w / 2.0))
    paste_y = int(round(CY - new_h / 2.0))
    centered.paste(rescaled_content, (paste_x, paste_y), rescaled_content)

    # 最终降采样到 128x128
    final_img = centered.resize((target_size, target_size), Image.Resampling.LANCZOS)
    dst_path = os.path.join(OUTPUT_DIR, filename)
    final_img.save(dst_path, "PNG")
    print(f"[SkillIconGen] 成功导出并自动居中: {dst_path}")

def p(x, y):
    """逻辑坐标 (x, y) [-64, 64] -> 超采样绝对坐标"""
    return (CX + x * SCALE, CY + y * SCALE)

def bezier(p0, p1, p2, p3, steps=25):
    pts = []
    for i in range(steps + 1):
        t = i / float(steps)
        x = (1-t)**3 * p0[0] + 3*(1-t)**2*t * p1[0] + 3*(1-t)*t**2 * p2[0] + t**3 * p3[0]
        y = (1-t)**3 * p0[1] + 3*(1-t)**2*t * p1[1] + 3*(1-t)*t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts

# 1. 缩地成寸 (skill_dash.png): 破空飞芒 / 虚空掠影
def gen_dash():
    img, d = create_super_canvas()

    def rot(lx, ly, deg=45):
        rad = math.radians(deg)
        rx = lx * math.cos(rad) - ly * math.sin(rad)
        ry = lx * math.sin(rad) + ly * math.cos(rad)
        return p(rx, ry)

    # 锐利前锋主箭头
    arrow_pts = [
        rot(0, -38),      # 尖端
        rot(17, -12),     # 右翼尖
        rot(7, -15),      # 右内折
        rot(0, -23),      # 尾部中心
        rot(-7, -15),     # 左内折
        rot(-17, -12),    # 左翼尖
    ]
    d.polygon(arrow_pts, fill=WHITE)

    # 第 1 道破空残影切片
    slice1_pts = [
        rot(0, -15),
        rot(13, -3),
        rot(5, -5),
        rot(0, -10),
        rot(-5, -5),
        rot(-13, -3),
    ]
    d.polygon(slice1_pts, fill=WHITE)

    # 第 2 道破空残影切片
    slice2_pts = [
        rot(0, -2),
        rot(9, 8),
        rot(4, 6),
        rot(0, 2),
        rot(-4, 6),
        rot(-9, 8),
    ]
    d.polygon(slice2_pts, fill=WHITE)

    # 第 3 道尾部空间破开碎片 (菱星)
    tail1_pts = [
        rot(0, 14),
        rot(5, 21),
        rot(0, 28),
        rot(-5, 21),
    ]
    d.polygon(tail1_pts, fill=WHITE)

    # 极微小尾芒
    tail2_pts = [
        rot(0, 32),
        rot(2.5, 36),
        rot(0, 40),
        rot(-2.5, 36),
    ]
    d.polygon(tail2_pts, fill=WHITE)

    auto_center_and_export(img, "skill_dash.png", max_content_radius=42)

# 2. 神行术 (skill_gale.png): 极简仙风双羽 / 御风飞翼
def gen_gale():
    img, d = create_super_canvas()

    def draw_wing_half(sign=1):
        # 上翎
        f1_pts = bezier(p(0, 22), p(sign * 18, 12), p(sign * 36, -14), p(sign * 34, -40), steps=20)
        f1_in  = bezier(p(sign * 34, -40), p(sign * 22, -22), p(sign * 14, 0), p(0, 12), steps=20)
        d.polygon(f1_pts + f1_in, fill=WHITE)

        # 中翎
        f2_pts = bezier(p(0, 24), p(sign * 20, 16), p(sign * 42, 4), p(sign * 42, -18), steps=20)
        f2_in  = bezier(p(sign * 42, -18), p(sign * 30, -4), p(sign * 18, 12), p(0, 20), steps=20)
        d.polygon(f2_pts + f2_in, fill=WHITE)

        # 下翎
        f3_pts = bezier(p(0, 26), p(sign * 16, 24), p(sign * 36, 18), p(sign * 36, 2), steps=20)
        f3_in  = bezier(p(sign * 36, 2), p(sign * 26, 12), p(sign * 14, 20), p(0, 24), steps=20)
        d.polygon(f3_pts + f3_in, fill=WHITE)

    draw_wing_half(-1) # 左翼
    draw_wing_half(1)  # 右翼

    # 中心御风灵骨
    core_pts = [
        p(0, -32),
        p(4, -8),
        p(6, 18),
        p(0, 36),
        p(-4, 18),
        p(-4, -8),
    ]
    d.polygon(core_pts, fill=WHITE)

    # 中心镂空一根极细风线增加轻灵感
    mask = Image.new("L", img.size, 0)
    mdraw = ImageDraw.Draw(mask)
    hole_pts = [
        p(0, -22),
        p(1.5, 2),
        p(0, 26),
        p(-1.5, 2),
    ]
    mdraw.polygon(hole_pts, fill=255)
    inv_mask = ImageChops.invert(mask)
    img.putalpha(ImageChops.multiply(img.split()[3], inv_mask))

    auto_center_and_export(img, "skill_gale.png", max_content_radius=42)

# 3. 疾风咒 (skill_haste.png): 极速三联并排飞剑 (催动法器急速穿刺连击)
def gen_haste():
    img, d = create_super_canvas()

    def draw_slender_sword(ox, oy, scale_fac=1.0):
        # 飞剑沿右上 45° 方向破空穿刺
        def rot_s(lx, ly):
            rad = math.radians(45)
            rx = lx * scale_fac * math.cos(rad) - ly * scale_fac * math.sin(rad)
            ry = lx * scale_fac * math.sin(rad) + ly * scale_fac * math.cos(rad)
            return p(ox + rx, oy + ry)

        # 典雅锐利的双刃古飞剑
        pts = [
            rot_s(0, -38),      # 尖锐剑尖
            rot_s(3.5, -28),    # 剑刃破风折角
            rot_s(2.8, 8),      # 剑身根部
            rot_s(6.5, 9.5),    # 剑格右端
            rot_s(1.8, 11),     # 剑柄右侧
            rot_s(1.8, 20),     # 剑柄底部
            rot_s(3.6, 22),     # 剑首
            rot_s(0, 24),       # 剑首底尖
            rot_s(-3.6, 22),
            rot_s(-1.8, 20),
            rot_s(-1.8, 11),
            rot_s(-6.5, 9.5),   # 剑格左端
            rot_s(-2.8, 8),
            rot_s(-3.5, -28),
        ]
        d.polygon(pts, fill=WHITE)

    d_perp = 14.0
    # 1. 中央主飞剑 (居中、最大、最前锋)
    draw_slender_sword(0, 0, scale_fac=1.12)

    # 2. 上侧伴随飞剑
    draw_slender_sword(-d_perp, -d_perp, scale_fac=0.82)

    # 3. 下侧伴随飞剑
    draw_slender_sword(d_perp, d_perp, scale_fac=0.82)

    auto_center_and_export(img, "skill_haste.png", max_content_radius=42)

# 4. 金光护体 (skill_aegis.png): 六角金刚界 / 玄天晶盾
def gen_aegis():
    img, d = create_super_canvas()

    r_outer = 42.0
    r_inner = 33.0

    outer_pts = []
    inner_pts = []
    for i in range(6):
        ang = math.radians(60 * i - 30)
        outer_pts.append(p(r_outer * math.cos(ang), r_outer * math.sin(ang)))
        inner_pts.append(p(r_inner * math.cos(ang), r_inner * math.sin(ang)))

    # 外六角实心
    d.polygon(outer_pts, fill=WHITE)

    # 镂空内部
    mask = Image.new("L", img.size, 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.polygon(inner_pts, fill=255)
    inv_mask = ImageChops.invert(mask)
    img.putalpha(ImageChops.multiply(img.split()[3], inv_mask))
    d = ImageDraw.Draw(img)

    # 中央金刚八角星芒
    star_pts = []
    for i in range(8):
        ang = math.radians(45 * i)
        r = 23.0 if (i % 2 == 0) else 8.5
        star_pts.append(p(r * math.cos(ang), r * math.sin(ang)))
    d.polygon(star_pts, fill=WHITE)

    # 6 个顶角向外延伸的金刚阵眼卡榫
    for i in range(6):
        ang = math.radians(60 * i - 30)
        nx = r_outer * math.cos(ang)
        ny = r_outer * math.sin(ang)
        notch = [
            p(nx + 4.5 * math.cos(ang), ny + 4.5 * math.sin(ang)),
            p(nx - 2.5 * math.sin(ang), ny + 2.5 * math.cos(ang)),
            p(nx - 2.0 * math.cos(ang), ny - 2.0 * math.sin(ang)),
            p(nx + 2.5 * math.sin(ang), ny - 2.5 * math.cos(ang)),
        ]
        d.polygon(notch, fill=WHITE)

    auto_center_and_export(img, "skill_aegis.png", max_content_radius=42)

# 5. 回春术 (skill_renewal.png): 灵木仙叶 + 纯净玉露甘露
def gen_renewal():
    img, d = create_super_canvas()

    def draw_leaf(sign=1):
        out_pts = bezier(
            p(0, 36),
            p(sign * 32, 28),
            p(sign * 38, -10),
            p(sign * 14, -36),
            steps=20
        )
        in_pts = bezier(
            p(sign * 14, -36),
            p(sign * 26, -10),
            p(sign * 16, 20),
            p(0, 32),
            steps=20
        )
        d.polygon(out_pts + in_pts, fill=WHITE)

    draw_leaf(-1)
    draw_leaf(1)

    base_stem = [
        p(-5, 33),
        p(5, 33),
        p(0, 42)
    ]
    d.polygon(base_stem, fill=WHITE)

    drop_left = bezier(
        p(0, -16),
        p(-6, -6),
        p(-12, 4),
        p(0, 16),
        steps=20
    )
    drop_right = bezier(
        p(0, 16),
        p(12, 4),
        p(6, -6),
        p(0, -16),
        steps=20
    )
    d.polygon(drop_left + drop_right, fill=WHITE)

    auto_center_and_export(img, "skill_renewal.png", max_content_radius=42)

if __name__ == "__main__":
    gen_dash()
    gen_gale()
    gen_haste()
    gen_aegis()
    gen_renewal()
