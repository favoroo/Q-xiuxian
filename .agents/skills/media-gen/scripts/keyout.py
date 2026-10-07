#!/usr/bin/env python3
"""品红底（#FF00FF）图 -> 透明底 PNG。

用法定义: keyout.py <输入图> <输出.png> [最长边像素]
针对网关生图的两个实际情况设计：
1. 模型常把品红背景画成"画面内的矩形"而非铺满画布 -> 先定位品红区域并裁剪
2. JPEG 压缩在边缘产生品红晕边 -> 软抠边（阈值渐变）+ 去溢色 + 最小值滤波腐蚀

流程: 定位品红矩形并裁剪 -> magentaness=min(R,B)-G 软抠 -> 半透明像素去品红溢色
      -> alpha 最小值滤波收边 -> 按不透明内容裁剪 bbox -> 可选缩放 -> 保存 PNG
"""
import sys
import numpy as np
from PIL import Image, ImageFilter


def keyout(src, dst, size=None):
    img = Image.open(src).convert('RGB')
    a = np.asarray(img).astype(np.int16)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    mag = np.minimum(R, B) - G  # 品红度量：越大越品红
    mask = (mag > 60) & (R > 140) & (B > 140)
    if mask.mean() > 0.04:  # 存在大面积品红背板 -> 裁剪到背板
        ys, xs = np.where(mask)
        img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        a = np.asarray(img).astype(np.int16)
        R, G, B = a[..., 0], a[..., 1], a[..., 2]
        mag = np.minimum(R, B) - G
    lo, hi = 30, 110  # magentaness 在 [lo,hi] 间线性过渡成半透明
    alpha = (np.clip((hi - mag) / (hi - lo), 0, 1) * 255).astype(np.uint8)
    semi = (alpha > 0) & (alpha < 255)
    g = G.astype(np.int16)
    R2 = np.where(semi, np.minimum(R, g + 60), R)  # 去品红溢色
    B2 = np.where(semi, np.minimum(B, g + 60), B)
    out = np.dstack([R2, G, B2, alpha]).astype(np.uint8)
    im = Image.fromarray(out)
    im.putalpha(im.getchannel('A').filter(ImageFilter.MinFilter(3)))  # 腐蚀 1px 去晕边
    bbox = im.getchannel('A').getbbox()
    if bbox:
        im = im.crop(bbox)
    if size:
        im.thumbnail((size, size), Image.LANCZOS)
    im.save(dst)
    print(dst, im.size)


if __name__ == '__main__':
    keyout(sys.argv[1], sys.argv[2],
           int(sys.argv[3]) if len(sys.argv) > 3 else None)
