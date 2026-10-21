#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
灵兽灵球抠图：把 tests/SpiritPetPreview.tscn 拍出的调形台整图，切成 7 张透明底灵球，
落到 site/dist/img/pet_<id>.png，供站点「灵兽」分区当图标用。

为什么不是 CSS 圆点：游戏内灵兽是 SpiritPet._draw 的程序化光灵（核心色 + 外晕 + decor
特征件：狐耳/雀冠/龟甲/鹿角/钱纹/貂尾/猿眉），CSS 只能画个圆，decor 全丢。
调形台本身不出透明底，所以这里按「加色合成」反解 alpha：
    原图 = 纯底 + 灵光 ⇒ RGB' = clamp(pix - bg)，A' = clamp(max(pix - bg) * gain)
贴回站点的纯黑卡底后合成结果 ≈ 原图，光晕的层次不丢。

跑法（两步，引擎那步必须有显示器，headless 出不了图）：
    G=/Applications/Godot.app/Contents/MacOS/Godot
    $G --path . res://tests/SpiritPetPreview.tscn -- --shot     # 产物 /tmp/spirit_pet_preview.png
    python3 tools/crop_site_pet_icons.py [可选：输入图路径]

上排 7 只（y≈190）是常态、下排是受激闪白态，只取上排。x 团簇靠掩码自动聚合，
不写死列距（改调形台布局也不用回来改这个脚本）。
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "dist" / "img"

# 上排灵球所在的高度带：躲开头顶标题（y<40）与下挂名字（y>=230），也别碰下排（y>360）
Y_TOP, Y_BOT = 90, 226
THR = 14          # 与底色的最小差值，算「有画东西」
GAIN = 1.55       # alpha 放大：光晕末端偏暗，不放大在纯黑上会直接看不见
PAD = 6           # 裁切留边
MIN_CLUSTER_W = 12


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/spirit_pet_preview.png")
    if not src.exists():
        print(f"✗ 找不到输入图 {src}（先跑 SpiritPetPreview.tscn -- --shot）", file=sys.stderr)
        return 1

    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    bg = px[4, h // 2]          # 左侧留白处取样即底色（调形台底色是平的）

    def diff(x: int, y: int) -> int:
        r, g, b = px[x, y]
        return max(r - bg[0], g - bg[1], b - bg[2], 0)

    # 1) 按列聚合出团簇（列内任一行过阈即算该列有内容）
    cols = []
    for x in range(w):
        hit = any(diff(x, y) > THR for y in range(Y_TOP, min(Y_BOT, h)))
        cols.append(hit)
    runs, start = [], None
    gap = 0
    for x, hit in enumerate(cols):
        if hit and start is None:
            start = x
        elif hit:
            gap = 0
        elif start is not None:
            gap += 1
            if gap > 18:                     # 连续 18 列空 ⇒ 这一只结束了
                runs.append((start, x - gap))
                start, gap = None, 0
    if start is not None:
        runs.append((start, w - 1))
    runs = [(a, b) for a, b in runs if b - a >= MIN_CLUSTER_W]

    # 灵兽顺序 = PetData.DEFS 表内顺序（x 从左到右天然同序）
    from export_site_data import build  # noqa: E402  复用同一份解析，顺序不另立真话源
    ids = [p["id"] for p in build()["pets"]]

    if len(runs) != len(ids):
        print(f"✗ 上排识别到 {len(runs)} 团，与 PetData 的 {len(ids)} 只不符，跳过不猜", file=sys.stderr)
        print(f"  团簇 x 区间：{runs}", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    for (x0, x1), pid in zip(runs, ids):
        y0, y1 = h, 0
        for x in range(max(0, x0 - PAD), min(w, x1 + PAD + 1)):
            for y in range(Y_TOP, min(Y_BOT, h)):
                if diff(x, y) > THR:
                    y0, y1 = min(y0, y), max(y1, y)
        if y1 <= y0:
            print(f"✗ {pid} 没找到内容", file=sys.stderr)
            return 1
        x0, x1 = max(0, x0 - PAD), min(w - 1, x1 + PAD)
        y0, y1 = max(Y_TOP, y0 - PAD), min(Y_BOT - 1, y1 + PAD)

        crop = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
        cp = crop.load()
        for cx in range(x0, x1 + 1):
            for cy in range(y0, y1 + 1):
                r, g, b = px[cx, cy]
                d = (max(r - bg[0], 0), max(g - bg[1], 0), max(b - bg[2], 0))
                a = min(255, int(max(d) * GAIN))
                cp[cx - x0, cy - y0] = (d[0], d[1], d[2], a)
        dest = OUT / f"pet_{pid}.png"
        crop.save(dest, "PNG", optimize=True)
        print(f"  pet_{pid}.png  {crop.size[0]}x{crop.size[1]}")

    print(f"灵兽图标已切出 {len(ids)} 张 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT / "tools"))
    sys.exit(main())
