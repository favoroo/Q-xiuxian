#!/usr/bin/env python3
"""生成所有 bullet_*.png 及 blade.png 的冷冽国风高精矢量底图
"""
import math
import os
from PIL import Image, ImageDraw

ART_DIR = "assets/art"

def canvas(w, h, s=4):
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    return img, d, s

def save(img, name, size):
    res = img.resize(size, Image.Resampling.LANCZOS)
    path = os.path.join(ART_DIR, name)
    res.save(path, "PNG")
    print(f"[BulletGen] 导出: {path} {size}")

# 1. bullet_gold_sword.png (40x10) - 确保 40 * 0.6 = 24.0px 不超过本体 26.4px
def gen_bullet_gold_sword():
    img, d, s = canvas(40, 10)
    # 剑刃朝右
    pts = [(38*s, 5*s), (10*s, 1*s), (4*s, 3*s), (4*s, 7*s), (10*s, 9*s)]
    d.polygon(pts, fill=(240, 245, 250, 255))
    d.polygon(pts, outline=(15, 20, 28, 255), width=int(1.2*s))
    # 金色剑脊
    d.line([(38*s, 5*s), (4*s, 5*s)], fill=(235, 195, 70, 255), width=int(1.5*s))
    save(img, "bullet_gold_sword.png", (40, 10))

# 2. bullet_leaf_dagger.png (42x10)
def gen_bullet_leaf_dagger():
    img, d, s = canvas(42, 10)
    pts = [(40*s, 5*s), (16*s, 1*s), (4*s, 2*s), (4*s, 8*s), (16*s, 9*s)]
    d.polygon(pts, fill=(240, 245, 250, 255))
    d.polygon(pts, outline=(15, 20, 28, 255), width=int(1.2*s))
    d.line([(40*s, 5*s), (4*s, 5*s)], fill=(90, 215, 165, 255), width=int(1.2*s))
    save(img, "bullet_leaf_dagger.png", (42, 10))

# 3. bullet_silver_needle.png (40x8)
def gen_bullet_silver_needle():
    img, d, s = canvas(40, 8)
    d.line([(38*s, 4*s), (2*s, 4*s)], fill=(255, 255, 255, 255), width=int(1.8*s))
    d.line([(38*s, 4*s), (6*s, 4*s)], fill=(180, 220, 255, 200), width=int(3.0*s))
    d.ellipse([36*s, 2*s, 40*s, 6*s], fill=(255, 255, 255, 255))
    save(img, "bullet_silver_needle.png", (40, 8))

# 4. bullet_ice_needle.png (40x8)
def gen_bullet_ice_needle():
    img, d, s = canvas(40, 8)
    pts = [(38*s, 4*s), (15*s, 1*s), (2*s, 2*s), (2*s, 6*s), (15*s, 7*s)]
    d.polygon(pts, fill=(180, 230, 255, 240))
    d.polygon(pts, outline=(25, 60, 110, 255), width=int(1.2*s))
    d.line([(38*s, 4*s), (2*s, 4*s)], fill=(255, 255, 255, 255), width=int(1.2*s))
    save(img, "bullet_ice_needle.png", (40, 8))

# 5. bullet_fire_talisman.png (36x40)
def gen_bullet_fire_talisman():
    img, d, s = canvas(36, 40)
    rect = [4*s, 4*s, 32*s, 36*s]
    d.rectangle(rect, fill=(240, 230, 200, 255), outline=(215, 65, 65, 255), width=int(2*s))
    d.ellipse([14*s, 8*s, 22*s, 16*s], fill=(215, 65, 65, 255))
    d.line([(18*s, 16*s), (18*s, 32*s)], fill=(235, 195, 70, 255), width=int(2*s))
    save(img, "bullet_fire_talisman.png", (36, 40))

# 6. bullet_wood_talisman.png (40x24)
def gen_bullet_wood_talisman():
    img, d, s = canvas(40, 24)
    rect = [4*s, 4*s, 36*s, 20*s]
    d.rectangle(rect, fill=(215, 240, 225, 255), outline=(45, 120, 85, 255), width=int(2*s))
    d.line([(10*s, 12*s), (30*s, 12*s)], fill=(90, 215, 165, 255), width=int(2*s))
    save(img, "bullet_wood_talisman.png", (40, 24))

# 7. bullet_spirit_pellet.png (24x24)
def gen_bullet_spirit_pellet():
    img, d, s = canvas(24, 24)
    d.ellipse([4*s, 4*s, 20*s, 20*s], fill=(90, 215, 165, 255), outline=(15, 20, 28, 255), width=int(1.5*s))
    d.ellipse([7*s, 7*s, 13*s, 13*s], fill=(255, 255, 255, 255))
    save(img, "bullet_spirit_pellet.png", (24, 24))

# 8. bullet_fire_flame.png (28x22)
def gen_bullet_fire_flame():
    img, d, s = canvas(28, 22)
    pts = [(24*s, 11*s), (10*s, 3*s), (3*s, 6*s), (2*s, 16*s), (12*s, 19*s)]
    d.polygon(pts, fill=(215, 65, 65, 240))
    d.polygon([(20*s, 11*s), (8*s, 6*s), (4*s, 14*s)], fill=(235, 195, 70, 255))
    save(img, "bullet_fire_flame.png", (28, 22))

# 9. blade.png (48x48)
def gen_blade():
    img, d, s = canvas(48, 48)
    pts = [(42*s, 24*s), (16*s, 12*s), (6*s, 18*s), (6*s, 30*s), (16*s, 36*s)]
    d.polygon(pts, fill=(240, 245, 250, 255), outline=(15, 20, 28, 255), width=int(2*s))
    d.line([(42*s, 24*s), (6*s, 24*s)], fill=(90, 215, 165, 255), width=int(2*s))
    save(img, "blade.png", (48, 48))

if __name__ == "__main__":
    gen_bullet_gold_sword()
    gen_bullet_leaf_dagger()
    gen_bullet_silver_needle()
    gen_bullet_ice_needle()
    gen_bullet_fire_talisman()
    gen_bullet_wood_talisman()
    gen_bullet_spirit_pellet()
    gen_bullet_fire_flame()
    gen_blade()
    print("全部子弹底图生成完毕！")
