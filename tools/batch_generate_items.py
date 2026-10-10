#!/usr/bin/env python3
"""批量调用 media-gen 生图脚本生成 20 件法宝道具的高清透明底素材，并同步写入 assets/art/
"""
import os
import subprocess
import shutil
from PIL import Image

ITEMS = [
    ("item_jubaopen", "修仙天材地宝道具图标：聚宝盆，青铜饕餮古盆，内盛幽蓝月华与古币灵光，单一主体居中饱满，无文字"),
    ("item_mibao_luopan", "修仙天材地宝道具图标：觅宝罗盘，暗金八卦铜罗盘，青玉天池指针，灵磁星轨，单一主体居中饱满，无文字"),
    ("item_qiankun_dai", "修仙天材地宝道具图标：乾坤袋，玄铁束口灵锦小锦囊，骨白与墨青，单一主体居中饱满，无文字"),
    ("item_jifeng_xue", "修仙天材地宝道具图标：疾风靴，寒泉青玉飞云轻靴，单只侧面，流风羽翼纹理，单一主体居中饱满，无文字"),
    ("item_qingxin_cha", "修仙天材地宝道具图标：清心神行茶，青瓷灵茶杯，碧绿茶汤泛起仙雾清露，单一主体居中饱满，无文字"),
    ("item_zhekou_yufu", "修仙天材地宝道具图标：折扣玉符，通透长方形寒玉令牌，雕琢万界商会暗金符印，单一主体居中饱满，无文字"),
    ("item_kuangxue_dan", "修仙丹药符箓图标：狂血丹，煞血深赤古朴仙丹，周身缭绕丝缕赤黑煞气，单一主体居中饱满，无文字"),
    ("item_guijia_fu", "修仙天材地宝道具图标：龟甲符，苍古六角玄龟背甲片，刻有暗金镇岳卦象，单一主体居中饱满，无文字"),
    ("item_tongxuan_ling", "修仙天材地宝道具图标：通玄令，深蓝幽冥玄铁令牌，骨白通玄古篆，单一主体居中饱满，无文字"),
    ("item_leiyin_zhen", "修仙天材地宝道具图标：雷引针，紫金八棱引雷古镇纸，微弱冷蓝电弧流转，单一主体居中饱满，无文字"),
    ("item_yinhun_deng", "修仙天材地宝道具图标：引魂青铜灯，幽冥单柄八角古灯，灯芯燃烧碧绿幽火，单一主体居中饱满，无文字"),
    ("item_suoling_jia", "修仙天材地宝道具图标：锁灵金刚枷，玄铁带刺重型封灵枷锁，冷钢断锁链，单一主体居中饱满，无文字"),
    ("item_wuxing_pei", "修仙天材地宝道具图标：五行佩，环形太极五彩温润灵玉佩，金木水火土五行冷光交织，单一主体居中饱满，无文字"),
    ("item_wujian_shi", "修仙天材地宝道具图标：悟剑石，斜切深渊黑曜古石，石面上留有一道极深纯白剑痕，单一主体居中饱满，无文字"),
    ("item_huichun_hulu", "修仙天材地宝道具图标：回春葫芦，碧玉长生药葫芦，系着骨白丝绦，溢出灵药生机，单一主体居中饱满，无文字"),
    ("item_pojia_zhui", "修仙天材地宝道具图标：破甲锥，寒钢八棱破甲重型金刚锥，锋尖冷月高光，单一主体居中饱满，无文字"),
    ("item_xiuluo_pei", "修仙天材地宝道具图标：修罗嗜血佩，血玉雕琢鬼面獠牙玉佩，暗红血光流淌，单一主体居中饱满，无文字"),
    ("item_tisi_kuilei", "修仙天材地宝道具图标：替死傀儡，古木与粗麻编织的镇魂替身稻草木偶，缠绕朱砂符带，单一主体居中饱满，无文字"),
    ("item_hunyuan_zhu", "修仙天材地宝道具图标：混元珠，混元太虚混沌玄珠，半透明内蕴阴阳流云，单一主体居中饱满，无文字"),
    ("item_taiyi_jindan", "修仙丹药符箓图标：九转太乙丹，灿金九转纯阳仙丹，祥云缭绕金霞内敛，单一主体居中饱满，无文字"),
]

def main():
    os.makedirs("assets_raw/images", exist_ok=True)
    os.makedirs("assets/art", exist_ok=True)

    # 预置已生成的乾坤袋
    if os.path.exists("assets_raw/images/test_qiankun_dai.png"):
        shutil.copy("assets_raw/images/test_qiankun_dai.png", "assets_raw/images/item_qiankun_dai.png")

    for item_id, prompt in ITEMS:
        raw_out = f"assets_raw/images/{item_id}"
        png_out = f"{raw_out}.png"
        target_art = f"assets/art/{item_id}.png"

        if not os.path.exists(png_out):
            cmd = [
                ".agents/skills/media-gen/scripts/gen_image.sh",
                "-m", "gemini-3.1-flash-lite-image",
                "-p", prompt,
                "--keyout", "256",
                "-o", raw_out
            ]
            print(f"--> 正在生成: {item_id}...")
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                print(f"[Error] 生成失败: {item_id}\n{res.stderr}")
            else:
                print(f"[Success] {item_id} 生成完成")

        # 压制进 assets/art，等比缩放到 64x64/48x48 保持最佳分辨率与清晰度
        if os.path.exists(png_out):
            im = Image.open(png_out)
            # 保持 64x64 高清方正，四周留出安全边距
            im.thumbnail((48, 48), Image.Resampling.LANCZOS)
            # 贴在 48x48 画布中央
            canvas = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
            offset = ((48 - im.size[0]) // 2, (48 - im.size[1]) // 2)
            canvas.paste(im, offset, im)
            canvas.save(target_art, "PNG")
            print(f"    -> 部署至 {target_art} (48x48)")

if __name__ == "__main__":
    main()
