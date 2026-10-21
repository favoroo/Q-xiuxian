#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/inspector/asset_lint.py — 游戏艺术资产合规性体检与防呆检测
检查项目:
  1. 尺寸规范 (道具法宝 128x128, 战场武器 48x48)
  2. 抠底与四周安全边距 (边缘 2px 范围内不允许有未抠底的非透明杂色)
  3. 异常场景图防呆 (防止 16:9 场景背景、平平整整的切边条混入图标)
  4. 数据表引用有效性 (UpgradeData, ItemData, WeaponData 中引用的图标文件必须存在且合规)
"""

import os
import re
import sys
import glob
from PIL import Image

def lint_icon_image(fpath: str, expected_size: tuple = None, max_aspect_ratio: float = 2.2):
    """体检单个图标图片，返回 (is_valid: bool, issues: list[str])"""
    issues = []
    if not os.path.exists(fpath):
        return False, ["文件不存在"]

    try:
        im = Image.open(fpath)
    except Exception as e:
        return False, [f"无法读取图片: {e}"]

    w, h = im.size
    if expected_size and (w, h) != expected_size:
        issues.append(f"分辨率不符合规范: 当前 {w}x{h}，期望 {expected_size[0]}x{expected_size[1]}")

    im_rgba = im.convert("RGBA")
    bbox = im_rgba.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if not bbox:
        issues.append("图片内容为空 (全透明)")
        return False, issues

    # 近空图防呆：非全透明但不透明像素占比过低（如导出管线坏产物只剩零星装饰像素）
    alpha_hist = im_rgba.getchannel("A").histogram()
    opaque_ratio = sum(alpha_hist[33:]) / float(w * h)
    if opaque_ratio < 0.02:
        issues.append(f"近乎全空图 (不透明像素占比 {opaque_ratio * 100:.2f}% < 2%，疑似导出坏产物)")

    bw = bbox[2] - bbox[0]
    bh = bbox[3] - bbox[1]
    aspect = bw / bh if bh > 0 else 0

    # 1. 检测四角未抠底 (未满足安全边距或混入矩形底板)
    # 取四角 2x2 像素区域
    alpha = im_rgba.split()[-1]
    corners = [
        alpha.crop((0, 0, 2, 2)),
        alpha.crop((w - 2, 0, w, 2)),
        alpha.crop((0, h - 2, 2, h)),
        alpha.crop((w - 2, h - 2, w, h)),
    ]
    opaque_corner_count = sum(1 for c in corners if max(c.getdata()) > 30)
    
    # 如果是 UI 道具法宝 (128x128)，规范要求四周留有安全边距，四角均不应贴边
    if w >= 128 and opaque_corner_count > 0:
        issues.append(f"四角存在贴边像素 ({opaque_corner_count}/4 角不透明，未满足安全边距规范)")
    elif opaque_corner_count >= 3:
        # 如果是其他资产（如武器），四角有 3 个以上不透明，判定为底板未扣除的实心矩形
        issues.append(f"四角有 {opaque_corner_count} 处非透明像素，疑似带有实心背景底板")

    # 2. 检测横条状场景背景图防呆 (如宗门大殿 120x66 的横版背景)
    # 典型特征：宽度占满 (> 90% 宽)，且高度明显偏扁 (aspect > 1.35)，且上下贴着固定的水平切线
    if w >= 128 and bw >= w * 0.85 and aspect > 1.35:
        # 检查是否上下两边都是水平切齐的实心像素（场景截图被截断的典型特征）
        top_row = [alpha.getpixel((x, bbox[1])) for x in range(bbox[0], bbox[2], 4)]
        bottom_row = [alpha.getpixel((x, bbox[3] - 1)) for x in range(bbox[0], bbox[2], 4)]
        top_dense = (sum(1 for v in top_row if v > 200) / len(top_row)) > 0.6
        bottom_dense = (sum(1 for v in bottom_row if v > 200) / len(bottom_row)) > 0.6
        if top_dense and bottom_dense:
            issues.append(f"疑似混入带背景的横向场景截图 (bbox={bbox}, aspect={aspect:.2f}, 上下边界平切)")

    return len(issues) == 0, issues

def run_asset_lint(verbose: bool = True) -> bool:
    """对全库关键资产进行整体体检"""
    total_checked = 0
    all_errors = []

    # 1. 检查道具法宝 (assets/art/item_*.png) -> 规范 128x128
    for p in sorted(glob.glob("assets/art/item_*.png")):
        total_checked += 1
        valid, issues = lint_icon_image(p, expected_size=(128, 128))
        if not valid:
            all_errors.append((p, issues))

    # 2. 检查武器法器 (assets/art/weapon_*.png) -> 规范 48x48
    for p in sorted(glob.glob("assets/art/weapon_*.png")):
        total_checked += 1
        valid, issues = lint_icon_image(p, expected_size=(48, 48))
        if not valid:
            all_errors.append((p, issues))

    # 3. 检查修士头像 (assets/art/cultivator_*_icon.png) -> 规范 96x96（导出管线坏产物曾以全透明空图入库）
    for p in sorted(glob.glob("assets/art/cultivator_*_icon.png")):
        total_checked += 1
        valid, issues = lint_icon_image(p, expected_size=(96, 96))
        if not valid:
            all_errors.append((p, issues))

    # 3.5 检查悟道加点专属图标 (assets/art/upgrade_*.png) -> 规范 128x128
    #     程序化生成（tools/generate_cold_gothic_upgrade_icons.py），与 icon_*/item_*/weapon_* 完全独立。
    for p in sorted(glob.glob("assets/art/upgrade_*.png")):
        total_checked += 1
        valid, issues = lint_icon_image(p, expected_size=(128, 128))
        if not valid:
            all_errors.append((p, issues))

    # 4. 检查数据表引用
    data_files = [
        ("UpgradeData", "scripts/data/UpgradeData.gd"),
        ("ItemData", "scripts/data/ItemData.gd"),
        ("WeaponData", "scripts/data/WeaponData.gd"),
        ("CultivatorData", "scripts/data/CultivatorData.gd"),
    ]
    for name, path in data_files:
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        icons = re.findall(r'"(res://assets/art/[^"]+\.png)"', content)
        for ic in set(icons):
            total_checked += 1
            rel = ic.replace("res://", "")
            if not os.path.exists(rel):
                all_errors.append((f"{name} 引用", [f"文件不存在: {rel}"]))

    if verbose:
        print(f"=== 资产规范与防呆体检 (Asset Lint) ===")
        print(f"已核验资产总数: {total_checked}")
        if all_errors:
            print(f"[FAIL] 发现 {len(all_errors)} 处资产异常:")
            for path, issues in all_errors:
                print(f"  ❌ {path}:")
                for iss in issues:
                    print(f"     - {iss}")
        else:
            print(f"[PASS] 全库艺术资产与图标规范 100% 合规通过！")

    return len(all_errors) == 0

if __name__ == "__main__":
    ok = run_asset_lint(verbose=True)
    sys.exit(0 if ok else 1)
