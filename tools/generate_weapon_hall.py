#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成渡个劫全部 68 把法器的全景视觉走廊检视看板 (tests/styles/weapon_hall_review_all68.png)
按器类与五行清晰排列，标记 ID、名称、标签、行为以及是否占位复用。
"""

import os
import re
from PIL import Image, ImageDraw, ImageFont

def parse_weapons():
    with open("scripts/data/WeaponData.gd", "r", encoding="utf-8") as f:
        text = f.read()

    defs_match = re.search(r"const DEFS: Dictionary = \{(.*?)\n\}\n", text, re.DOTALL)
    defs_str = defs_match.group(1)
    entries = re.findall(r'\"([a-zA-Z0-9_]+)\":\s*\{([^}]+)\}', defs_str)

    weapons = []
    for wid, body in entries:
        name_m = re.search(r'\"name\":\s*\"([^\"]+)\"', body)
        icon_m = re.search(r'\"icon\":\s*\"([^\"]+)\"', body)
        tag_m = re.search(r'\"tag\":\s*\"([^\"]+)\"', body)
        tags_m = re.search(r'\"tags\":\s*\[([^\]]+)\]', body)
        behavior_m = re.search(r'\"behavior\":\s*Behavior\.([A-Z]+)', body)

        name = name_m.group(1) if name_m else ''
        icon = icon_m.group(1) if icon_m else ''
        tag = tag_m.group(1) if tag_m else ''
        tags = [t.strip().strip('\"') for t in tags_m.group(1).split(',')] if tags_m else []
        behavior = behavior_m.group(1) if behavior_m else ''
        weapons.append({
            'id': wid,
            'name': name,
            'icon': icon.replace("res://", ""),
            'tag': tag,
            'tags': tags,
            'behavior': behavior
        })
    return weapons

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

def render_weapon_hall():
    weapons = parse_weapons()
    
    # 统计图标复用
    icon_count = {}
    for w in weapons:
        icon_count[w['icon']] = icon_count.get(w['icon'], 0) + 1

    # 布局参数
    # 68 把法器，按每行 7 列，共 10 行 (最后一排 5 个)
    cols = 7
    rows = (len(weapons) + cols - 1) // cols
    
    card_w = 260
    card_h = 130
    pad_x = 16
    pad_y = 16
    margin_top = 110
    margin_left = 30
    margin_right = 30
    margin_bottom = 30

    total_w = margin_left + cols * card_w + (cols - 1) * pad_x + margin_right
    total_h = margin_top + rows * card_h + (rows - 1) * pad_y + margin_bottom

    img = Image.new("RGBA", (total_w, total_h), (12, 16, 24, 255))
    draw = ImageDraw.Draw(img)

    title_font = get_font(34)
    subtitle_font = get_font(16)
    name_font = get_font(18)
    info_font = get_font(12)
    tag_font = get_font(11)
    warn_font = get_font(11)

    # 绘制顶部标题
    draw.text((margin_left, 24), "渡个劫 · 全部 68 把法器全景视觉走廊检视看板", fill=(245, 247, 250, 255), font=title_font)
    sub_text = "核对对象：法器名 · 图标剪影 · 辨识度/重复占位诊断 · 五行(金木水火土)与器类(剑/符/扫/雷/灵/机)匹配度"
    draw.text((margin_left, 68), sub_text, fill=(138, 155, 180, 255), font=subtitle_font)

    # 五行与器类颜色
    elem_colors = {
        "metal": (240, 208, 120, 255), # 金黄
        "wood": (96, 212, 144, 255),   # 翠绿
        "water": (80, 180, 245, 255),  # 冰蓝
        "fire": (245, 100, 80, 255),   # 烈红
        "earth": (210, 160, 95, 255),  # 岩棕
    }

    for idx, w in enumerate(weapons):
        r = idx // cols
        c = idx % cols
        x = margin_left + c * (card_w + pad_x)
        y = margin_top + r * (card_h + pad_y)

        is_duplicate = icon_count[w['icon']] > 1
        
        # 判断主五行颜色
        main_elem = "metal"
        for t in w['tags']:
            if t in elem_colors:
                main_elem = t
                break
        elem_color = elem_colors.get(main_elem, (160, 170, 185, 255))

        # 卡片底板
        bg_col = (20, 26, 38, 255) if not is_duplicate else (32, 22, 26, 255)
        border_col = (45, 60, 85, 255) if not is_duplicate else (200, 60, 60, 255)
        
        draw.rectangle([x, y, x + card_w, y + card_h], fill=bg_col, outline=border_col, width=1)
        
        # 左侧五行装饰条
        draw.rectangle([x, y, x + 5, y + card_h], fill=elem_color)

        # 绘制武器图标
        icon_path = w['icon']
        icon_drawn = False
        if os.path.exists(icon_path):
            try:
                w_icon = Image.open(icon_path).convert("RGBA")
                w_icon = w_icon.resize((56, 56), Image.Resampling.LANCZOS)
                # 图标框背景
                draw.rectangle([x + 12, y + 14, x + 12 + 60, y + 14 + 60], fill=(12, 16, 22, 255), outline=(50, 65, 90, 255), width=1)
                img.alpha_composite(w_icon, (x + 14, y + 16))
                icon_drawn = True
            except Exception as e:
                pass

        if not icon_drawn:
            draw.rectangle([x + 12, y + 14, x + 12 + 60, y + 14 + 60], fill=(30, 30, 30, 255), outline=(100, 100, 100, 255))
            draw.text((x + 22, y + 36), "无图", fill=(180, 180, 180, 255), font=info_font)

        # 文本信息
        text_x = x + 80
        # 序号与名称
        num_str = f"#{idx+1:02d} "
        draw.text((text_x, y + 10), num_str, fill=(120, 140, 165, 255), font=name_font)
        name_x_offset = draw.textlength(num_str, font=name_font)
        draw.text((text_x + name_x_offset, y + 10), w['name'], fill=(240, 244, 250, 255), font=name_font)

        # 英文 ID
        draw.text((text_x, y + 34), w['id'], fill=(120, 138, 160, 255), font=info_font)

        # 标签与行为
        draw.text((text_x, y + 54), f"[{w['tag']}]", fill=elem_color, font=tag_font)
        draw.text((text_x, y + 72), f"形态: {w['behavior']}", fill=(150, 165, 185, 255), font=info_font)

        # 底部状态栏（若复用占位，标红警告）
        if is_duplicate:
            draw.rectangle([x + 6, y + card_h - 22, x + card_w - 1, y + card_h - 1], fill=(160, 35, 35, 200))
            draw.text((x + 14, y + card_h - 19), "⚠ 占位复用贴图 (完全相同)", fill=(255, 255, 255, 255), font=warn_font)
        else:
            # 显示对应图标文件名短名
            icon_basename = os.path.basename(icon_path)
            draw.text((x + 12, y + card_h - 20), f"贴图: {icon_basename}", fill=(85, 105, 130, 255), font=info_font)

    os.makedirs("tests/styles", exist_ok=True)
    out_path = "tests/styles/weapon_hall_review_all68.png"
    img.save(out_path)
    print(f"成功导出全 68 把法器全景走廊看板至: {out_path} ({total_w}x{total_h})")

if __name__ == "__main__":
    render_weapon_hall()
