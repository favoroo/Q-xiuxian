#!/usr/bin/env python3
"""批量生成 20 件武器与 20 件道具的【空洞冷冽国风·纯矢量插画】高清透明底资产
以 tests/styles/cultivator_modular_gallery.png 为统一风格锚点 (-r 风格锁定)
Prompt 严守：
- 2D扁平矢量插画风格，空洞骑士艺术风格，极简纯色块几何切面，高对比度利落硬朗线条，粗黑外轮廓线，无写实材质无3D渲染，纯扁平
- 对齐 GameStyle 调色板 (骨白 PAPER, 虚空黑 INK, 暗金 GOLD, 寒玉 JADE, 幽蓝 NAVY, 煞血 CRIMSON)
"""
import os
import sys
import subprocess
import shutil
import numpy as np
from PIL import Image

REF_IMG = "tests/styles/cultivator_modular_gallery.png"
STYLE_BASE = (
    "2D扁平矢量插画风格，空洞骑士艺术风格，极简纯色块几何切面，高对比度利落硬朗线条，粗黑外轮廓线，"
    "无写实材质无3D渲染，纯扁平。单一主体居中饱满，无背景无文字。"
)

# 20 件法宝武器
WEAPONS = [
    # 金系
    ("weapon_sword", "修仙武器图标：青云剑，笔直双刃修长骨白青玉古剑，剑尖直指右上45度，剑柄在左下，剑格青钢，刃口锋锐纯矢量几何面"),
    ("weapon_gold_sword", "修仙武器图标：庚金飞剑，修长冷银双刃古剑，骨白剑身，暗金剑脊，剑柄在左下，剑尖直指右上45度，纯矢量几何切面"),
    ("weapon_dagger", "修仙武器图标：柳叶飞刀，双柄交错纤细冷银柳叶飞刀，骨白青金，刀尖直指右上45度，纯矢量几何面"),
    ("weapon_needle_pouch", "修仙武器图标：暴雨梨花针匣，斜切玄铁机括暗器匣，匣口朝向右方，寒钢骨白棱角，纯矢量几何面"),
    # 木系
    ("weapon_vine_whip", "修仙武器图标：青木藤鞭，青翠灵木节杖手柄，甩出带刺荆棘灵藤，垂直向上构图，纯矢量几何面"),
    ("weapon_wood_talisman", "修仙武器图标：万木灵符，竖向长方形碧翠灵木符纸，刻印青绿生机古篆符文，右上微倾，纯矢量几何面"),
    ("sun_orb", "修仙武器图标：碧翠灵蝶，舒展双翅的翡翠透光灵羽蝴蝶，正面俯视，骨白触角，纯矢量几何面"),
    ("weapon_sling", "修仙武器图标：连环灵弹弓，老藤古木精致弹弓，搭着一枚翠绿聚元灵珠，朝向右上，纯矢量几何面"),
    # 水系
    ("weapon_fan", "修仙武器图标：芭蕉扇，寒玉扇柄与展开的青蓝芭蕉古扇，扇骨清晰硬朗，朝向右上，纯矢量几何面"),
    ("weapon_ice_needle", "修仙武器图标：玄冰飞针，三枚并排的幽蓝多面体棱形冰晶飞针，针尖直指右上45度，纯矢量几何面"),
    ("weapon_ice_lotus", "修仙武器图标：寒泉玉莲，晶莹冰魄层叠八瓣莲台法宝，中心冷蓝莲蓬，正面俯视，纯矢量几何面"),
    ("weapon_flute", "修仙武器图标：碧海潮音笛，竖直放置的青玉古笛，挂着深蓝流苏，笛身孔位利落，纯矢量几何面"),
    # 火系
    ("weapon_staff", "修仙武器图标：火焰符，竖向长方形炽黄赤金符纸，朱砂勾勒爆燃符阵，右上微倾，纯矢量几何面"),
    ("weapon_fire_blade", "修仙武器图标：赤焰斩马刀，厚重霸道单刃阔面重刀，刀尖朝右上，赤红火煞几何切面，纯矢量几何面"),
    ("weapon_fire_lantern", "修仙武器图标：焚天宝灯，竖立单柄八角青铜古宫灯，灯芯燃烧白炽离火，垂直立姿，纯矢量几何面"),
    ("weapon_fire_calabash", "修仙武器图标：三昧真火葫，朱红朱砂温润药葫芦，葫口朝向右上方喷吐微小火苗，纯矢量几何面"),
    # 土系
    ("weapon_thunder", "修仙武器图标：五雷法牌，竖立雷击木长方形厚重法牌，刻印紫金五雷天心正法符篆，垂直立姿，纯矢量几何面"),
    ("weapon_earth_seal", "修仙武器图标：番天镇岳印，厚重玄铁四方古大印，印顶盘踞螭龙印纽，垂直立姿，纯矢量几何面"),
    ("weapon_earth_bell", "修仙武器图标：混元古钟，玄铁青铜古朴大钟，钟钮吊环在上方，钟身有暗金云雷纹，垂直立姿，纯矢量几何面"),
    ("weapon_earth_shield", "修仙武器图标：玄武镇山盾，重型六角玄铁大盾，盾面刻有骨白玄武龟蛇古阵纹，朝向右上，纯矢量几何面")
]

# 20 件法宝道具
ITEMS = [
    ("item_jubaopen", "修仙天材地宝道具图标：聚宝盆，青铜八角饕餮古铜盆，内盛幽蓝月华与古币灵光，纯矢量几何切面"),
    ("item_mibao_luopan", "修仙天材地宝道具图标：觅宝罗盘，暗金八角八卦铜罗盘，青玉天池指针，纯矢量几何面"),
    ("item_qiankun_dai", "修仙天材地宝道具图标：乾坤袋，骨白与虚空黑冷调小锦囊，玄青系绳与青玉佩，纯矢量几何面"),
    ("item_jifeng_xue", "修仙天材地宝道具图标：疾风靴，寒泉青玉飞云轻靴，单只侧面，流风折角羽翼，纯矢量几何面"),
    ("item_qingxin_cha", "修仙天材地宝道具图标：清心神行茶，青瓷六角茶盅，碧绿茶汤泛起仙雾清露，纯矢量几何面"),
    ("item_zhekou_yufu", "修仙天材地宝道具图标：折扣玉符，通透长方形寒玉令牌，雕琢暗金商会符印，纯矢量几何面"),
    ("item_kuangxue_dan", "修仙丹药符箓图标：狂血丹，煞血深赤古朴仙丹，周身缭绕丝缕赤黑煞气折角，纯矢量几何面"),
    ("item_guijia_fu", "修仙天材地宝道具图标：龟甲符，苍古六角玄龟背甲片，刻有暗金镇岳卦象，纯矢量几何面"),
    ("item_tongxuan_ling", "修仙天材地宝道具图标：通玄令，深蓝幽冥玄铁令牌，骨白通玄古篆，纯矢量几何面"),
    ("item_leiyin_zhen", "修仙天材地宝道具图标：雷引针，紫金八棱引雷古镇纸，微弱冷蓝折线电弧，纯矢量几何面"),
    ("item_yinhun_deng", "修仙天材地宝道具图标：引魂青铜灯，幽冥单柄八角古灯，灯芯燃烧碧绿幽火，纯矢量几何面"),
    ("item_suoling_jia", "修仙天材地宝道具图标：锁灵金刚枷，玄铁带刺重型封灵枷锁，冷钢断锁链，纯矢量几何面"),
    ("item_wuxing_pei", "修仙天材地宝道具图标：五行佩，环形太极五彩温润灵玉佩，金木水火土五行冷光交织，纯矢量几何面"),
    ("item_wujian_shi", "修仙天材地宝道具图标：悟剑石，斜切深渊黑曜古石，石面上留有一道极深纯白剑痕，纯矢量几何面"),
    ("item_huichun_hulu", "修仙天材地宝道具图标：回春葫芦，碧玉长生药葫芦，系着骨白丝绦，溢出灵药生机，纯矢量几何面"),
    ("item_pojia_zhui", "修仙天材地宝道具图标：破甲锥，寒钢八棱破甲重型金刚锥，锋尖冷月高光，纯矢量几何面"),
    ("item_xiuluo_pei", "修仙天材地宝道具图标：修罗嗜血佩，血玉雕琢鬼面獠牙玉佩，暗红血光流淌，纯矢量几何面"),
    ("item_tisi_kuilei", "修仙天材地宝道具图标：替死傀儡，古木与粗麻编织的镇魂替身稻草木偶，缠绕朱砂符带，纯矢量几何面"),
    ("item_hunyuan_zhu", "修仙天材地宝道具图标：混元珠，混元太虚混沌玄珠，半透明内蕴阴阳流云，纯矢量几何面"),
    ("item_taiyi_jindan", "修仙丹药符箓图标：九转太乙丹，灿金九转纯阳仙丹，祥云缭绕金霞内敛，纯矢量几何面")
]

def generate_asset(name, prompt_content):
    raw_path = f"assets_raw/images/{name}"
    png_path = f"{raw_path}.png"
    if os.path.exists(png_path):
        return png_path
    
    full_prompt = f"{STYLE_BASE} {prompt_content}"
    cmd = [
        ".agents/skills/media-gen/scripts/gen_image.sh",
        "-m", "gemini-3.1-flash-lite-image",
        "-r", REF_IMG,
        "-p", full_prompt,
        "--keyout", "256",
        "-o", raw_path
    ]
    print(f"--> [生成中] {name}...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[Error] {name} 失败:\n{res.stderr}")
        return None
    print(f"[Success] {name} 生成完成: {png_path}")
    return png_path

def fit_to_target(png_path, target_art_path, size=48):
    if not os.path.exists(png_path):
        return
    im = Image.open(png_path).convert("RGBA")
    # 去除四周透明空白
    bbox = im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    
    # 等比压缩至 size - 4
    inner_size = size - 4
    im.thumbnail((inner_size, inner_size), Image.Resampling.LANCZOS)
    
    # 居中放置到 size x size 画布
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ox = (size - im.size[0]) // 2
    oy = (size - im.size[1]) // 2
    canvas.paste(im, (ox, oy), im)
    canvas.save(target_art_path, "PNG")

def main():
    os.makedirs("assets_raw/images", exist_ok=True)
    os.makedirs("assets/art", exist_ok=True)
    
    # 预留已测试满意的优秀矢量素材
    if os.path.exists("assets_raw/images/test_vector_qiankun_dai.png"):
        shutil.copy("assets_raw/images/test_vector_qiankun_dai.png", "assets_raw/images/item_qiankun_dai.png")
    if os.path.exists("assets_raw/images/test_vector_gengjin_feijian.png"):
        shutil.copy("assets_raw/images/test_vector_gengjin_feijian.png", "assets_raw/images/weapon_gold_sword.png")
    if os.path.exists("assets_raw/images/test_vector_liuye_feidao.png"):
        shutil.copy("assets_raw/images/test_vector_liuye_feidao.png", "assets_raw/images/weapon_dagger.png")

    print("=== 开始批量生成冷冽国风纯矢量法宝道具 ===")
    for item_id, prompt in ITEMS:
        png = generate_asset(item_id, prompt)
        if png:
            fit_to_target(png, f"assets/art/{item_id}.png", 48)

    print("\n=== 开始批量生成冷冽国风纯矢量法器武器 ===")
    for wep_id, prompt in WEAPONS:
        png = generate_asset(wep_id, prompt)
        if png:
            fit_to_target(png, f"assets/art/{wep_id}.png", 48)

    print("\n=== 全部法器与法宝素材生成处理完毕！ ===")

if __name__ == "__main__":
    main()
