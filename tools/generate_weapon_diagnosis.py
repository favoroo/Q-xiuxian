#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成法器辨识度与相似度专项诊断对比看板 (tests/styles/weapon_similarity_diagnosis.png)
将容易混淆的双胞胎武器成对/成组排布，并在旁边标注问题与重构建议。
"""

import os
from PIL import Image, ImageDraw, ImageFont

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

def render_diagnosis():
    # 诊断分组数据
    groups = [
        {
            "category": "【类别 A：100% 相同复用（借用占位贴图）】",
            "pairs": [
                {
                    "item_a": {"name": "音笛", "id": "bihai_chaoyindi", "tag": "水·范围·笛", "icon": "assets/art/weapon_flute.png"},
                    "item_b": {"name": "玄冥雷珠", "id": "xuanming_leizhu", "tag": "水·雷法·珠", "icon": "assets/art/weapon_flute.png"},
                    "problem": "玄冥雷珠完全借用音笛贴图！雷珠显示为一根竹笛，既无雷也无珠，极度违和。",
                    "solution": "绘制悬浮的幽暗玄水雷珠，内蕴深蓝冰晶雷核，外环绕刺目冰电弧。"
                },
                {
                    "item_a": {"name": "青藤剑", "id": "qingteng_jian", "tag": "木·剑系·藤", "icon": "assets/art/weapon_qingteng_jian.png"},
                    "item_b": {"name": "桃木剑", "id": "taomu_jian", "tag": "木·剑系·辟邪", "icon": "assets/art/weapon_qingteng_jian.png"},
                    "problem": "桃木剑共用青藤剑贴图。两者皆为木剑，玩家在商店完全无法分辨谁是谁。",
                    "solution": "桃木剑改为古拙道门金丝雷击桃木剑，剑柄系朱砂红穗，剑身刻北斗七星与道符刻痕。"
                },
                {
                    "item_a": {"name": "金雷锥", "id": "jinlei_zhui", "tag": "金·雷法·锥", "icon": "assets/art/weapon_jinlei_zhui.png"},
                    "item_b": {"name": "金霄雷令", "id": "jinxiao_leiling", "tag": "金·雷法·令", "icon": "assets/art/weapon_jinlei_zhui.png"},
                    "problem": "金霄雷令共用金雷锥贴图。令法宝变成了金字塔形状的尖锥，名不符实。",
                    "solution": "绘制正统五雷天师金牌令牌，紫金冷冽切面，牌顶雷云兽首，牌面镂空金雷敕令。"
                },
                {
                    "item_a": {"name": "玄冰符", "id": "xuanbing_fu", "tag": "水·符箓·冰", "icon": "assets/art/weapon_xuanbing_fu.png"},
                    "item_b": {"name": "癸水符", "id": "guishui_fu", "tag": "水·符箓·水", "icon": "assets/art/weapon_xuanbing_fu.png"},
                    "problem": "癸水符共用玄冰符贴图。同一系别下两张符纸外观完全一样。",
                    "solution": "癸水符改为流动柔性水墨水龙卷符，周身有玄冥黑水环绕激荡，区别于硬质冰棱符。"
                },
                {
                    "item_a": {"name": "镇山符", "id": "zhenshan_fu", "tag": "土·符箓·山", "icon": "assets/art/weapon_zhenshan_fu.png"},
                    "item_b": {"name": "厚土符", "id": "houtu_fu", "tag": "土·符箓·土", "icon": "assets/art/weapon_zhenshan_fu.png"},
                    "problem": "厚土符共用镇山符贴图。同为土系符箓，贴图完全撞车。",
                    "solution": "厚土符绘制为三张土黄符纸扇形重叠排列，带厚实砂金土甲悬浮盾护符纹。"
                },
                {
                    "item_a": {"name": "喷火兽", "id": "penhuo_jiguanshou", "tag": "火·机关·兽", "icon": "assets/art/weapon_penhuo_jiguanshou.png"},
                    "item_b": {"name": "烽火台", "id": "fenghuo_tai", "tag": "火·机关·台", "icon": "assets/art/weapon_penhuo_jiguanshou.png"},
                    "problem": "烽火台共用喷火兽贴图。防御工事建筑变成了跑动的小铜兽机关。",
                    "solution": "烽火台绘制为古朴森严的石砌八角烽火防御高台，顶端狼烟赤炎升腾。"
                },
                {
                    "item_a": {"name": "寒泉兽", "id": "hanquan_shou", "tag": "水·机关·兽", "icon": "assets/art/weapon_hanquan_shou.png"},
                    "item_b": {"name": "凝冰机弩", "id": "ningbing_nu", "tag": "水·机关·弩", "icon": "assets/art/weapon_hanquan_shou.png"},
                    "problem": "凝冰机弩共用寒泉兽贴图。明明是重机弩，却画成了一只青铜兽。",
                    "solution": "绘制精钢冰蚕丝三联装重型机弩，弩臂凝结幽蓝冰晶刺，杀伐机械感明显。"
                },
                {
                    "item_a": {"name": "藤萝机关", "id": "tengluo_jiguan", "tag": "木·机关·藤", "icon": "assets/art/weapon_tengluo_jiguan.png"},
                    "item_b": {"name": "青木炮", "id": "qingmu_pao", "tag": "木·机关·炮", "icon": "assets/art/weapon_tengluo_jiguan.png"},
                    "problem": "青木炮共用藤萝机关贴图。火炮类杀器却显示为藤萝发射架。",
                    "solution": "绘制青铜铸造、覆有雷纹古木灵枢的重型青木臼炮，炮口深沉威严。"
                }
            ]
        },
        {
            "category": "【类别 B：构图剪影高度雷同（长剑 vs 飞剑 / 剑系双胞胎）】",
            "pairs": [
                {
                    "item_a": {"name": "长剑", "id": "qingyun_sword", "tag": "金·近战·剑", "icon": "assets/art/weapon_sword.png"},
                    "item_b": {"name": "飞剑", "id": "gengjin_feijian", "tag": "金·远程·剑", "icon": "assets/art/weapon_gold_sword.png"},
                    "problem": "两把剑均为 45 度白银双刃剑，剑柄与护手尺寸极度接近，小图标下肉眼极难区分！",
                    "solution": "长剑突出沉稳实体佩剑（厚重宽刃、八面汉剑格、宝蓝流苏剑穗）；飞剑突出御剑虚空态（无剑柄/极细剑茎，周围环绕3道微缩分光剑芒，剑尖拖曳流光）。"
                },
                {
                    "item_a": {"name": "寒霜剑", "id": "hanshuang_jian", "tag": "水·近战·剑", "icon": "assets/art/weapon_hanshuang_jian.png"},
                    "item_b": {"name": "崩山剑", "id": "bengshan_jian", "tag": "土·近战·剑", "icon": "assets/art/weapon_bengshan_jian.png"},
                    "problem": "与长剑/飞剑同样也是倾斜白刃剑，缺乏元素特色与武器重量感差异。",
                    "solution": "寒霜剑改为全透明不规则冰棱晶体剑，散落碎冰粒子；崩山剑改为厚重无锋破裂玄铁巨阙巨石剑。"
                }
            ]
        },
        {
            "category": "【类别 C：符箓类「千人一面」长条纸片（缺乏识别锚点）】",
            "pairs": [
                {
                    "item_a": {"name": "金针符", "id": "jinzhen_fu", "tag": "金·远程·符", "icon": "assets/art/weapon_jinzhen_fu.png"},
                    "item_b": {"name": "庚金符", "id": "gengjin_fu", "tag": "金·远程·符", "icon": "assets/art/weapon_gengjin_fu.png"},
                    "problem": "都是斜放白灰纸片符。金针符连射飞针、庚金符是飞剑符，但画面上看不出任何差异。",
                    "solution": "金针符外侧悬浮放射出 4 根锋锐金色长针刺，突出金针破甲；庚金符画为由无数细碎金芒剑气组成的符光。"
                },
                {
                    "item_a": {"name": "火符", "id": "huoyan_fu", "tag": "火·远程·符", "icon": "assets/art/weapon_staff.png"},
                    "item_b": {"name": "真火符", "id": "zhenhuo_fu", "tag": "火·远程·符", "icon": "assets/art/weapon_zhenhuo_fu.png"},
                    "problem": "火符和真火符都是红黄符纸，真火符只多了点微弱小火星，在小图标下几乎一模一样。",
                    "solution": "真火符改为正在猛烈自燃的残卷真火符箓，喷吐三昧真火火舌，火羽飞扬。"
                },
                {
                    "item_a": {"name": "万木灵符", "id": "wanmu_lingfu", "tag": "木·远程·符", "icon": "assets/art/weapon_wood_talisman.png"},
                    "item_b": {"name": "蛊毒符", "id": "gudu_fu", "tag": "木·远程·符", "icon": "assets/art/weapon_gudu_fu.png"},
                    "problem": "都是绿幽幽的长条符纸，缺乏生机 vs 剧毒的视觉对冲。",
                    "solution": "万木灵符画为碧玉树皮质感、嫩芽藤蔓缠绕生机；蛊毒符画为腐朽残破黑绿符，表面趴着赤眼凶蛊，滴落毒液。"
                }
            ]
        }
    ]

    # 画布大小
    total_w = 1760
    total_h = 2400
    img = Image.new("RGBA", (total_w, total_h), (12, 16, 24, 255))
    draw = ImageDraw.Draw(img)

    title_font = get_font(32)
    cat_font = get_font(22)
    name_font = get_font(18)
    text_font = get_font(14)
    sol_font = get_font(14)

    draw.text((40, 30), "渡个劫 · 武器辨识度与相似度专项诊断对比看板", fill=(245, 247, 250, 255), font=title_font)
    draw.text((40, 75), "诊断原则：① 严禁同名共用贴图 ② 剑系长剑与飞剑必须一眼可分 ③ 符箓类杜绝千人一面长条纸片", fill=(140, 160, 185, 255), font=text_font)

    curr_y = 120
    for cat in groups:
        # 分类大标题
        draw.rectangle([40, curr_y, total_w - 40, curr_y + 40], fill=(22, 32, 50, 255), outline=(50, 80, 120, 255))
        draw.text((55, curr_y + 8), cat["category"], fill=(255, 215, 110, 255), font=cat_font)
        curr_y += 55

        for pair in cat["pairs"]:
            card_h = 115
            # 卡片底板
            draw.rectangle([40, curr_y, total_w - 40, curr_y + card_h], fill=(18, 24, 34, 255), outline=(38, 50, 72, 255))

            # 物品 A
            item_a = pair["item_a"]
            draw.rectangle([55, curr_y + 12, 55 + 72, curr_y + 12 + 72], fill=(10, 12, 18, 255), outline=(60, 75, 100, 255))
            if os.path.exists(item_a["icon"]):
                icon_img = Image.open(item_a["icon"]).convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)
                img.alpha_composite(icon_img, (59, curr_y + 16))
            draw.text((138, curr_y + 18), item_a["name"], fill=(240, 245, 250, 255), font=name_font)
            draw.text((138, curr_y + 44), f"[{item_a['tag']}]", fill=(100, 190, 250, 255), font=text_font)
            draw.text((138, curr_y + 66), item_a["id"], fill=(120, 135, 155, 255), font=text_font)

            # VS 标志
            draw.text((320, curr_y + 36), "VS", fill=(240, 80, 80, 255), font=cat_font)

            # 物品 B
            item_b = pair["item_b"]
            draw.rectangle([390, curr_y + 12, 390 + 72, curr_y + 12 + 72], fill=(10, 12, 18, 255), outline=(60, 75, 100, 255))
            if os.path.exists(item_b["icon"]):
                icon_img = Image.open(item_b["icon"]).convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)
                img.alpha_composite(icon_img, (394, curr_y + 16))
            draw.text((475, curr_y + 18), item_b["name"], fill=(240, 245, 250, 255), font=name_font)
            draw.text((475, curr_y + 44), f"[{item_b['tag']}]", fill=(100, 190, 250, 255), font=text_font)
            draw.text((475, curr_y + 66), item_b["id"], fill=(120, 135, 155, 255), font=text_font)

            # 问题与优化方案说明
            diag_x = 680
            draw.rectangle([diag_x - 10, curr_y + 10, total_w - 55, curr_y + card_h - 10], fill=(14, 18, 26, 255), outline=(45, 55, 75, 255))
            draw.text((diag_x + 5, curr_y + 16), "【存在问题】 " + pair["problem"], fill=(250, 110, 110, 255), font=text_font)
            draw.text((diag_x + 5, curr_y + 48), "【优化方向】 " + pair["solution"], fill=(100, 225, 160, 255), font=sol_font)

            curr_y += card_h + 12
        curr_y += 15

    out_path = "tests/styles/weapon_similarity_diagnosis.png"
    img.save(out_path)
    print(f"成功导出武器辨识度专项诊断看板至: {out_path} ({total_w}x{total_h})")

if __name__ == "__main__":
    render_diagnosis()
