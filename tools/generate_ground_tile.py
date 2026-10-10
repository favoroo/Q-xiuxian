#!/usr/bin/env python3
"""
生成高质量 1024x1024 无缝冷青玄岩石板地砖 (Cold Gothic Xianxia Slate Tile)
- 尺寸：1024x1024 RGBA
- 周期性无缝包裹 (Seamless Periodic Wrapping)
- 工字错位修仙青石板大板格局 + 细微岩石矿物纹理 + 水墨沉降风化痕
- 深沉低对比度，确保作为幸存者游戏地面时不抢前景角色与弹幕
"""

import math
import random
import numpy as np
from PIL import Image, ImageFilter

def generate_seamless_tile(width=1024, height=1024, output_path="assets/art/courtyard_tile.png"):
    np.random.seed(42)
    random.seed(42)

    # 1. 生成周期性多频噪声底板 (2D 快速傅里叶合成无缝平滑噪声)
    # 利用频域滤波生成严格无缝的 Perlin-like 连续岩石风化层
    kx = np.fft.fftfreq(width)[:, None]
    ky = np.fft.fftfreq(height)[None, :]
    dist = np.sqrt(kx**2 + ky**2)
    dist[0, 0] = 1.0  # 避免除以零

    # 1/f^alpha 频谱生成天然岩石粗糙度
    random_phases = np.exp(2j * np.pi * np.random.rand(width, height))
    spectrum_rough = random_phases / (dist ** 1.35)
    spectrum_rough[0, 0] = 0.0
    noise_rough = np.real(np.fft.ifft2(spectrum_rough))
    noise_rough = (noise_rough - noise_rough.min()) / (noise_rough.max() - noise_rough.min())

    spectrum_fine = np.exp(2j * np.pi * np.random.rand(width, height)) / (dist ** 0.85)
    spectrum_fine[0, 0] = 0.0
    noise_fine = np.real(np.fft.ifft2(spectrum_fine))
    noise_fine = (noise_fine - noise_fine.min()) / (noise_fine.max() - noise_fine.min())

    # 2. 构建 4x4 大块工字交错青石板 (每块高 256，宽 512，错位 256)
    # 这种大石板比琐碎小方砖大气质朴得多，具备宗门神殿大广场的庄严感
    tile_h = 256
    tile_w = 512

    # 初始化基础色图 (R, G, B)
    # 基础色：冷青玄黑 (R=20, G=27, B=38) ~ (28, 38, 52)
    base_r = 18.0 + noise_rough * 10.0 + noise_fine * 5.0
    base_g = 25.0 + noise_rough * 13.0 + noise_fine * 6.0
    base_b = 36.0 + noise_rough * 17.0 + noise_fine * 8.0

    # 3. 绘制石砖缝隙 (Grooves)
    # 纵横缝隙带微弱倒角阴影与高光边
    seam_mask = np.zeros((height, width), dtype=np.float32)
    edge_highlight = np.zeros((height, width), dtype=np.float32)

    for y in range(height):
        row_idx = y // tile_h
        y_in_tile = y % tile_h
        dist_y = min(y_in_tile, tile_h - y_in_tile)

        # 错位偏移量
        x_offset = (row_idx % 2) * (tile_w // 2)

        for x in range(width):
            x_shifted = (x + x_offset) % width
            x_in_tile = x_shifted % tile_w
            dist_x = min(x_in_tile, tile_w - x_in_tile)

            # 缝隙宽度：约 3~4 像素
            min_dist = min(dist_x, dist_y)

            if min_dist <= 2.2:
                # 缝心深渊
                seam_mask[y, x] = 1.0 - (min_dist / 2.2) * 0.4
            elif min_dist <= 4.5:
                # 倒角微亮棱角边 (模拟石块边缘的光折射)
                edge_highlight[y, x] = math.sin((min_dist - 2.2) / 2.3 * math.pi) * 0.15

    # 4. 石砖独立色差微调 (让每一整块石板有微妙不同的水墨冷青微差，避免死板)
    for r in range(4):
        for c in range(2):
            x_start = (c * tile_w - (r % 2) * (tile_w // 2)) % width
            y_start = r * tile_h
            
            # 每块砖有微小的色温漂移 (-3 ~ +3)
            tint_shift = (random.random() - 0.5) * 5.0
            
            # 在该砖块范围内微调
            y_indices = np.arange(y_start, y_start + tile_h) % height
            x_indices = np.arange(x_start, x_start + tile_w) % width
            grid_y, grid_x = np.meshgrid(y_indices, x_indices, indexing='ij')
            
            base_r[grid_y, grid_x] += tint_shift * 0.7
            base_g[grid_y, grid_x] += tint_shift * 1.0
            base_b[grid_y, grid_x] += tint_shift * 1.4

    # 5. 合成最终颜色并叠加暗缝与棱线
    final_r = base_r * (1.0 - seam_mask * 0.75) + edge_highlight * 25.0
    final_g = base_g * (1.0 - seam_mask * 0.75) + edge_highlight * 32.0
    final_b = base_b * (1.0 - seam_mask * 0.75) + edge_highlight * 42.0

    # 限制在 [0, 255]
    final_r = np.clip(final_r, 6, 68).astype(np.uint8)
    final_g = np.clip(final_g, 9, 85).astype(np.uint8)
    final_b = np.clip(final_b, 14, 110).astype(np.uint8)
    final_a = np.full((height, width), 255, dtype=np.uint8)

    # 堆叠为 RGBA
    img_data = np.stack([final_r, final_g, final_b, final_a], axis=-1)
    img = Image.fromarray(img_data, mode="RGBA")

    # 细微高斯柔化以抹去尖锐单像素噪点，确保任何视角下平滑舒适
    img = img.filter(ImageFilter.GaussianBlur(radius=0.4))
    img.save(output_path, "PNG")
    print(f"✅ 成功生成 1024x1024 无缝冷青玄岩石板地砖: {output_path}")

if __name__ == "__main__":
    generate_seamless_tile()
