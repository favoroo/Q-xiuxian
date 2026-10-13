#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/inspect_asset.py — 游戏美术视觉检视统一调度 CLI
用法:
    python3 tools/inspect.py cultivator <id>       # 单角色 4 视角 3.5x 高清特写
    python3 tools/inspect.py cultivator --all      # 全量修仙角色全景走廊图
    python3 tools/inspect.py weapon <id>           # 单法器 8x 像素特写 + 器尖标定线
    python3 tools/inspect.py weapon --all          # 68 把法器全景走廊图
    python3 tools/inspect.py item <id>             # 单道具 8x 像素特写 + 品质色框
    python3 tools/inspect.py item --all            # 全法宝道具走廊图
    python3 tools/inspect.py enemy <id>            # 单妖魔 3 态高清特写
    python3 tools/inspect.py enemy --all           # 全妖魔全景画廊
    python3 tools/inspect.py report                # 重新生成交互式 HTML 看板
    python3 tools/inspect.py all                   # 全量刷新走廊图并生成 HTML 看板
"""

import os
import sys
import re
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

# 确保导入同目录下的 html_report 模块
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inspector.html_report import generate_html_report

GODOT_CANDIDATES = [
    os.environ.get("GODOT_BIN", ""),
    "/Applications/Godot.app/Contents/MacOS/Godot",
    shutil.which("godot") or ""
]

def find_godot_bin():
    for p in GODOT_CANDIDATES:
        if p and os.path.exists(p) and os.access(p, os.X_OK):
            return p
    return None

def get_font(size):
    font_paths = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
    ]
    for p in font_paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()

def run_godot_inspector(target, target_id, out_path, is_gallery=False, scale=3.5, grid=True):
    godot = find_godot_bin()
    if not godot:
        print("[Error] 未找到可执行的 Godot 引擎路径！请设置 GODOT_BIN 环境变量或安装 Godot 至 /Applications/Godot.app。")
        sys.exit(1)

    cmd = [
        godot,
        "--path", ".",
        "res://tools/inspector/InspectorScene.tscn",
        "--",
        "--target", target,
        "--id", target_id,
        "--scale", str(scale),
        "--out", out_path
    ]
    if is_gallery:
        cmd.append("--gallery")
    if grid:
        cmd.append("--grid")

    print(f"[CLI] 启动 Godot 视口抓拍: {' '.join(cmd)}")
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"[Error] Godot 渲染失败 (code {res.returncode}):\n{res.stderr}\n{res.stdout}")
        sys.exit(res.returncode)
    
    print(f"✓ 成功导出视觉资产截图: {out_path}")
    return out_path

# ==============================================================================
# 位图类资产检视 (Weapon / Item)
# ==============================================================================

def inspect_single_weapon(wid):
    path = "scripts/data/WeaponData.gd"
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    m = re.search(rf'\"{wid}\":\s*\{{([^}}]+)\}}', text)
    if not m:
        print(f"[Error] 未在 WeaponData.gd 中找到法器: {wid}")
        return

    body = m.group(1)
    name_m = re.search(r'\"name\":\s*\"([^\"]+)\"', body)
    icon_m = re.search(r'\"icon\":\s*\"([^\"]+)\"', body)
    tag_m = re.search(r'\"tag\":\s*\"([^\"]+)\"', body)
    tip_m = re.search(r'\"tip\":\s*Vector2\(([-0-9.]+),\s*([-0-9.]+)\)', body)
    desc_m = re.search(r'\"desc\":\s*\"([^\"]+)\"', body)

    name = name_m.group(1) if name_m else wid
    tag = tag_m.group(1) if tag_m else ""
    desc = desc_m.group(1) if desc_m else ""
    icon_res = icon_m.group(1) if icon_m else ""
    icon_path = icon_res.replace("res://", "")

    if not os.path.exists(icon_path):
        print(f"[Error] 图标文件不存在: {icon_path}")
        return

    # 生成 8x 像素特写看板
    src_img = Image.open(icon_path).convert("RGBA")
    sw, sh = src_img.size # 48x48
    scale = 8
    target_w, target_h = sw * scale, sh * scale # 384x384

    # 48x48 像素按最近邻放大
    scaled = src_img.resize((target_w, target_h), Image.Resampling.NEAREST)

    # 复合看板画布: 宽 720, 高 460
    canvas_w, canvas_h = 720, 460
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (11, 15, 25, 255))
    draw = ImageDraw.Draw(canvas)

    # 棋盘格暗底 (用于清晰查看半透明/透明抠底)
    pad_left = 32
    pad_top = 40
    tile_size = 16
    for y in range(0, target_h, tile_size):
        for x in range(0, target_w, tile_size):
            col = (18, 24, 38, 255) if ((x // tile_size) + (y // tile_size)) % 2 == 0 else (14, 18, 28, 255)
            draw.rectangle([pad_left + x, pad_top + y, pad_left + x + tile_size, pad_top + y + tile_size], fill=col)

    # 贴上图标
    canvas.paste(scaled, (pad_left, pad_top), scaled)
    # 边框
    draw.rectangle([pad_left, pad_top, pad_left + target_w, pad_top + target_h], outline=(47, 67, 102, 255), width=2)

    # 绘制中心十字准星 (24, 24)
    cx = pad_left + (sw // 2) * scale
    cy = pad_top + (sh // 2) * scale
    draw.line([cx, pad_top, cx, pad_top + target_h], fill=(70, 100, 150, 180), width=1)
    draw.line([pad_left, cy, pad_left + target_w, cy], fill=(70, 100, 150, 180), width=1)

    # 标注器尖 tip 标定点
    tip_x, tip_y = None, None
    if tip_m:
        rx, ry = float(tip_m.group(1)), float(tip_m.group(2))
        tip_px = int(cx + rx * scale)
        tip_py = int(cy + ry * scale)
        tip_x, tip_y = rx, ry
        # 画红金准星圆圈与连线
        draw.line([cx, cy, tip_px, tip_py], fill=(245, 158, 11, 200), width=2)
        r = 6
        draw.ellipse([tip_px - r, tip_py - r, tip_px + r, tip_py + r], outline=(239, 68, 68, 255), width=2)
        draw.ellipse([tip_px - 2, tip_py - 2, tip_px + 2, tip_py + 2], fill=(245, 158, 11, 255))

    # 右侧参数栏
    info_x = pad_left + target_w + 32
    f_title = get_font(20)
    f_sub = get_font(13)
    f_body = get_font(12)

    draw.text((info_x, pad_top), f"【法器】{name} ({wid})", font=f_title, fill=(230, 236, 245, 255))
    draw.text((info_x, pad_top + 34), f"流派五行: {tag}", font=f_sub, fill=(16, 185, 129, 255))
    draw.text((info_x, pad_top + 60), f"像素规格: {sw}×{sh} (8x 放大显示)", font=f_body, fill=(138, 153, 173, 255))

    tip_desc = f"tip 标定: Vector2({tip_x}, {tip_y})" if tip_x is not None else "tip 标定: 未定义 (默认居中)"
    draw.text((info_x, pad_top + 85), tip_desc, font=f_body, fill=(245, 158, 11, 255))

    draw.line([info_x, pad_top + 120, canvas_w - 32, pad_top + 120], fill=(30, 42, 64, 255), width=1)

    draw.text((info_x, pad_top + 135), "机制说明:", font=f_sub, fill=(230, 236, 245, 255))
    # 折行
    words = desc
    line_y = pad_top + 160
    for i in range(0, len(words), 16):
        draw.text((info_x, line_y), words[i:i+16], font=f_body, fill=(180, 195, 215, 255))
        line_y += 20

    # 图标路径
    draw.text((info_x, pad_top + 280), "资产源路径:", font=f_sub, fill=(138, 153, 173, 255))
    draw.text((info_x, pad_top + 305), icon_path, font=f_body, fill=(90, 130, 180, 255))

    draw.text((info_x, pad_top + 345), "※ 橙色指示线指引法器真实器尖标定", font=f_body, fill=(245, 158, 11, 200))
    draw.text((info_x, pad_top + 368), "※ 蓝色十字为法器旋转旋转中心轴", font=f_body, fill=(100, 140, 200, 200))

    out_file = f"tests/inspect/weapon_{wid}_closeup.png"
    canvas.save(out_file)
    print(f"✓ 成功导出法器 8x 标定特写看板: {out_file}")
    return out_file

def inspect_single_item(iid):
    path = "scripts/data/ItemData.gd"
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    m = re.search(rf'\"{iid}\":\s*\{{([^}}]+)\}}', text)
    if not m:
        print(f"[Error] 未在 ItemData.gd 中找到道具: {iid}")
        return

    body = m.group(1)
    name_m = re.search(r'\"name\":\s*\"([^\"]+)\"', body)
    icon_m = re.search(r'\"icon\":\s*\"([^\"]+)\"', body)
    tier_m = re.search(r'\"tier\":\s*([0-9]+)', body)
    desc_m = re.search(r'\"desc\":\s*\"([^\"]+)\"', body)

    name = name_m.group(1) if name_m else iid
    tier = int(tier_m.group(1)) if tier_m else 1
    desc = desc_m.group(1) if desc_m else ""
    icon_path = icon_m.group(1).replace("res://", "") if icon_m else ""

    if not os.path.exists(icon_path):
        print(f"[Error] 道具图标不存在: {icon_path}")
        return

    src_img = Image.open(icon_path).convert("RGBA")
    sw, sh = src_img.size
    scale = 8
    target_w, target_h = sw * scale, sh * scale

    scaled = src_img.resize((target_w, target_h), Image.Resampling.NEAREST)

    canvas_w, canvas_h = 700, 450
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (11, 15, 25, 255))
    draw = ImageDraw.Draw(canvas)

    pad_left, pad_top = 32, 40
    tile_size = 16
    for y in range(0, target_h, tile_size):
        for x in range(0, target_w, tile_size):
            col = (18, 24, 38, 255) if ((x // tile_size) + (y // tile_size)) % 2 == 0 else (14, 18, 28, 255)
            draw.rectangle([pad_left + x, pad_top + y, pad_left + x + tile_size, pad_top + y + tile_size], fill=col)

    canvas.paste(scaled, (pad_left, pad_top), scaled)

    tier_colors = {
        1: (150, 160, 178, 255),
        2: (74, 144, 226, 255),
        3: (155, 81, 224, 255),
        4: (232, 128, 36, 255)
    }
    tier_names = {1: "普通 (Tier 1)", 2: "稀有 (Tier 2)", 3: "史诗 (Tier 3)", 4: "传说 (Tier 4)"}
    border_col = tier_colors.get(tier, (150, 160, 178, 255))
    draw.rectangle([pad_left, pad_top, pad_left + target_w, pad_top + target_h], outline=border_col, width=3)

    info_x = pad_left + target_w + 32
    f_title = get_font(20)
    f_sub = get_font(13)
    f_body = get_font(12)

    draw.text((info_x, pad_top), f"【法宝】{name} ({iid})", font=f_title, fill=(230, 236, 245, 255))
    draw.text((info_x, pad_top + 34), f"品阶档位: {tier_names.get(tier, '普通')}", font=f_sub, fill=border_col)
    draw.text((info_x, pad_top + 60), f"原始尺寸: {sw}×{sh} (8x 放大检视)", font=f_body, fill=(138, 153, 173, 255))

    draw.line([info_x, pad_top + 100, canvas_w - 32, pad_top + 100], fill=(30, 42, 64, 255), width=1)
    draw.text((info_x, pad_top + 115), "机制效果:", font=f_sub, fill=(230, 236, 245, 255))
    words = desc
    line_y = pad_top + 140
    for i in range(0, len(words), 16):
        draw.text((info_x, line_y), words[i:i+16], font=f_body, fill=(180, 195, 215, 255))
        line_y += 20

    draw.text((info_x, pad_top + 280), "资源文件:", font=f_sub, fill=(138, 153, 173, 255))
    draw.text((info_x, pad_top + 305), icon_path, font=f_body, fill=(90, 130, 180, 255))

    out_file = f"tests/inspect/item_{iid}_closeup.png"
    canvas.save(out_file)
    print(f"✓ 成功导出道具 8x 特写看板: {out_file}")
    return out_file

def generate_all_items_gallery():
    path = "scripts/data/ItemData.gd"
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    entries = re.findall(r'\"([a-zA-Z0-9_]+)\":\s*\{([^}]+)\}', text)
    items = []
    for iid, body in entries:
        name_m = re.search(r'\"name\":\s*\"([^\"]+)\"', body)
        icon_m = re.search(r'\"icon\":\s*\"([^\"]+)\"', body)
        tier_m = re.search(r'\"tier\":\s*([0-9]+)', body)
        if name_m and icon_m:
            items.append({
                "id": iid,
                "name": name_m.group(1),
                "icon": icon_m.group(1).replace("res://", ""),
                "tier": int(tier_m.group(1)) if tier_m else 1
            })

    cols = 8
    rows = (len(items) + cols - 1) // cols
    card_w, card_h = 130, 110
    pad = 12
    total_w = pad + cols * (card_w + pad)
    total_h = 70 + rows * (card_h + pad)

    canvas = Image.new("RGBA", (total_w, total_h), (11, 15, 25, 255))
    draw = ImageDraw.Draw(canvas)

    f_title = get_font(18)
    f_item = get_font(11)
    draw.text((pad, 20), f"剑士 · 全量法宝道具画廊矩阵 (共 {len(items)} 件)", font=f_title, fill=(230, 236, 245, 255))

    tier_colors = {
        1: (150, 160, 178, 255),
        2: (74, 144, 226, 255),
        3: (155, 81, 224, 255),
        4: (232, 128, 36, 255)
    }

    for idx, item in enumerate(items):
        r = idx // cols
        c = idx % cols
        x = pad + c * (card_w + pad)
        y = 70 + r * (card_h + pad)

        draw.rectangle([x, y, x + card_w, y + card_h], fill=(16, 22, 34, 255), outline=tier_colors.get(item["tier"], (60, 70, 90, 255)), width=1)
        if os.path.exists(item["icon"]):
            img = Image.open(item["icon"]).convert("RGBA")
            img = img.resize((48, 48), Image.Resampling.NEAREST)
            canvas.paste(img, (x + (card_w - 48) // 2, y + 12), img)

        draw.text((x + 8, y + 68), item["name"], font=f_item, fill=(230, 236, 245, 255))
        draw.text((x + 8, y + 86), item["id"], font=get_font(9), fill=(138, 153, 173, 255))

    out_path = "tests/inspect/item_gallery_all.png"
    canvas.save(out_path)
    print(f"✓ 成功导出道具全景画廊: {out_path}")
    return out_path

# ==============================================================================
# CLI 入口与调度
# ==============================================================================

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1].lower()

    if cmd == "cultivator":
        if len(sys.argv) < 3:
            print("用法: python3 tools/inspect.py cultivator <id|--all>")
            sys.exit(1)
        arg = sys.argv[2]
        if arg == "--all":
            run_godot_inspector("cultivator", "all", "tests/inspect/cultivator_gallery_all.png", is_gallery=True)
        else:
            run_godot_inspector("cultivator", arg, f"tests/inspect/cultivator_{arg}_closeup.png", is_gallery=False)

    elif cmd == "weapon":
        if len(sys.argv) < 3:
            print("用法: python3 tools/inspect.py weapon <id|--all>")
            sys.exit(1)
        arg = sys.argv[2]
        if arg == "--all":
            # 调用既有 generate_weapon_hall.py 生成 68 把法器
            hall_script = "tools/generate_weapon_hall.py"
            if os.path.exists(hall_script):
                subprocess.run(["python3", hall_script], check=True)
                # 软链接/拷贝至 tests/inspect/
                if os.path.exists("tests/styles/weapon_hall_review_all68.png"):
                    shutil.copy("tests/styles/weapon_hall_review_all68.png", "tests/inspect/weapon_gallery_all.png")
                    print("✓ 成功同步 68 把法器全景走廊图至 tests/inspect/weapon_gallery_all.png")
        else:
            inspect_single_weapon(arg)

    elif cmd == "item":
        if len(sys.argv) < 3:
            print("用法: python3 tools/inspect.py item <id|--all>")
            sys.exit(1)
        arg = sys.argv[2]
        if arg == "--all":
            generate_all_items_gallery()
        else:
            inspect_single_item(arg)

    elif cmd == "enemy":
        if len(sys.argv) < 3:
            print("用法: python3 tools/inspect.py enemy <id|--all>")
            sys.exit(1)
        arg = sys.argv[2]
        if arg == "--all":
            run_godot_inspector("enemy", "all", "tests/inspect/enemy_gallery_all.png", is_gallery=True)
        else:
            run_godot_inspector("enemy", arg, f"tests/inspect/enemy_{arg}_closeup.png", is_gallery=False)

    elif cmd == "report":
        generate_html_report()

    elif cmd == "all":
        print("[CLI] 开始执行全量走廊画廊矩阵更新...")
        run_godot_inspector("cultivator", "all", "tests/inspect/cultivator_gallery_all.png", is_gallery=True)
        hall_script = "tools/generate_weapon_hall.py"
        if os.path.exists(hall_script):
            subprocess.run(["python3", hall_script], check=True)
            if os.path.exists("tests/styles/weapon_hall_review_all68.png"):
                shutil.copy("tests/styles/weapon_hall_review_all68.png", "tests/inspect/weapon_gallery_all.png")
        generate_all_items_gallery()
        run_godot_inspector("enemy", "all", "tests/inspect/enemy_gallery_all.png", is_gallery=True)
        generate_html_report()
        print("★ 全部走廊图与 HTML 交互看板更新完毕！")

    else:
        print(f"[Error] 未知指令: {cmd}")
        print(__doc__)

if __name__ == "__main__":
    main()
