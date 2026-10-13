#!/usr/bin/env python3
"""将 assets_raw/images/ 中的所有 item_*.png 与 weapon_*.png 高清矢量插画
按 128x128 高清规范（去除透明边界、保留四周 4px 安全边距）同步导出至 assets/art/
"""
import glob
import os
from PIL import Image

def fit_to_128(src_path: str, dst_path: str, size: int = 128) -> bool:
    if not os.path.exists(src_path):
        return False
    try:
        im = Image.open(src_path).convert("RGBA")
        # 去除四周全透明多余边距
        bbox = im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
        if bbox:
            im = im.crop(bbox)
        
        inner_size = size - 8  # 120x120，留出 4px 安全边距
        im.thumbnail((inner_size, inner_size), Image.Resampling.LANCZOS)
        
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ox = (size - im.size[0]) // 2
        oy = (size - im.size[1]) // 2
        canvas.paste(im, (ox, oy), im)
        canvas.save(dst_path, "PNG")
        return True
    except Exception as e:
        print(f"[Error] {src_path} -> {dst_path}: {e}")
        return False

def main():
    os.makedirs("assets/art", exist_ok=True)
    count = 0
    # 1. 道具法宝
    for p in sorted(glob.glob("assets_raw/images/item_*.png")):
        base = os.path.basename(p)
        if "_cold_v" in base: # 跳过中间版本命名
            continue
        dst = os.path.join("assets/art", base)
        if fit_to_128(p, dst, 128):
            count += 1
            
    # 2. 武器
    for p in sorted(glob.glob("assets_raw/images/weapon_*.png")):
        base = os.path.basename(p)
        if "_v2" in base or "_v3" in base:
            continue
        dst = os.path.join("assets/art", base)
        if fit_to_128(p, dst, 128):
            count += 1

    print(f"已成功将 {count} 个法宝与武器图标高清重烘焙至 assets/art/ (128x128)！")

if __name__ == "__main__":
    main()
