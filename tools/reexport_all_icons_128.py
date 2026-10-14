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
    # 1. 道具法宝（纯 UI 显示用途，保持 128x128 高清矢量插画）
    # 优先选取 _cold_v3 / _cold_v2 等无场景背景的高清修仙风格版本
    item_sources = {}
    for p in sorted(glob.glob("assets_raw/images/item_*.png")):
        base = os.path.basename(p)
        clean_name = base
        # 解析基础名
        for suffix in ["_cold_v3", "_cold_v2", "_cold_v1"]:
            if suffix in clean_name:
                clean_name = clean_name.replace(suffix, "")
                break
        
        # 优先级：cold_v3 > cold_v2 > cold_v1 > 基础名
        if clean_name not in item_sources:
            item_sources[clean_name] = p
        else:
            curr = item_sources[clean_name]
            if "_cold_v3" in p:
                item_sources[clean_name] = p
            elif "_cold_v2" in p and "_cold_v3" not in curr:
                item_sources[clean_name] = p

    for clean_name, src_path in sorted(item_sources.items()):
        dst = os.path.join("assets/art", clean_name)
        if fit_to_128(src_path, dst, 128):
            count += 1

    print(f"已成功将 {count} 个法宝道具图标高清重烘焙至 assets/art/ (128x128)！")

if __name__ == "__main__":
    main()
