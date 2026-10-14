#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
HTML 报告生成模块 (tools/inspector/html_report.py)
聚合修仙者、法器、法宝道具、妖魔怪物、武器特效、飞行物弹丸、界面规范 7 大视觉资产，
输出单文件离线交互式全景画廊看板 (tests/inspect/index.html)。
遵循 GameStyle 视觉规范（深蓝底 #07090e、纸白、主蓝、点缀金黄）。
"""

import os
import re
import base64

def get_base64_image(path):
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        data = f.read()
    ext = os.path.splitext(path)[1].lower().replace(".", "")
    if ext == "jpg":
        ext = "jpeg"
    return f"data:image/{ext};base64,{base64.b64encode(data).decode('ascii')}"

def parse_cultivators():
    cultivators = []
    defs_path = "scripts/data/CultivatorData.gd"
    if not os.path.exists(defs_path):
        return cultivators
    with open(defs_path, "r", encoding="utf-8") as f:
        text = f.read()

    blocks = re.findall(r'\"([a-zA-Z0-9_]+)\":\s*\{\s*\n\t+\"name\":\s*\"([^\"]+)\"', text)
    for cid, cname in blocks:
        m_ep = re.search(rf'\"{cid}\":\s*\{{[^}}]*\"epithet\":\s*\"([^\"]+)\"', text)
        epithet = m_ep.group(1) if m_ep else ""
        icon_path = f"assets/art/cultivator_{cid}_icon.png"
        closeup_path = f"tests/inspect/cultivator_{cid}_closeup.png"
        cultivators.append({
            "id": cid,
            "name": cname,
            "epithet": epithet,
            "icon": icon_path if os.path.exists(icon_path) else "",
            "closeup": closeup_path if os.path.exists(closeup_path) else ""
        })
    return cultivators

def parse_weapons():
    weapons = []
    path = "scripts/data/WeaponData.gd"
    if not os.path.exists(path):
        return weapons
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    defs_match = re.search(r"const DEFS: Dictionary = \{(.*?)\n\}\n", text, re.DOTALL)
    if not defs_match:
        return weapons
    entries = re.findall(r'\"([a-zA-Z0-9_]+)\":\s*\{([^}]+)\}', defs_match.group(1))
    for wid, body in entries:
        name_m = re.search(r'\"name\":\s*\"([^\"]+)\"', body)
        icon_m = re.search(r'\"icon\":\s*\"([^\"]+)\"', body)
        tag_m = re.search(r'\"tag\":\s*\"([^\"]+)\"', body)
        desc_m = re.search(r'\"desc\":\s*\"([^\"]+)\"', body)
        price_m = re.search(r'\"price\":\s*([0-9]+)', body)

        icon_file = icon_m.group(1).replace("res://", "") if icon_m else ""
        weapons.append({
            "id": wid,
            "name": name_m.group(1) if name_m else wid,
            "tag": tag_m.group(1) if tag_m else "",
            "desc": desc_m.group(1) if desc_m else "",
            "price": price_m.group(1) if price_m else "0",
            "icon": icon_file if os.path.exists(icon_file) else "",
            "closeup": f"tests/inspect/weapon_{wid}_closeup.png"
        })
    return weapons

def parse_items():
    items = []
    path = "scripts/data/ItemData.gd"
    if not os.path.exists(path):
        return items
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    entries = re.findall(r'\"([a-zA-Z0-9_]+)\":\s*\{([^}]+)\}', text)
    for iid, body in entries:
        name_m = re.search(r'\"name\":\s*\"([^\"]+)\"', body)
        icon_m = re.search(r'\"icon\":\s*\"([^\"]+)\"', body)
        desc_m = re.search(r'\"desc\":\s*\"([^\"]+)\"', body)
        tier_m = re.search(r'\"tier\":\s*([0-9]+)', body)

        if not name_m or not icon_m:
            continue

        icon_file = icon_m.group(1).replace("res://", "")
        tier = int(tier_m.group(1)) if tier_m else 1
        tier_names = {1: "普通", 2: "稀有", 3: "史诗", 4: "传说"}
        tier_colors = {1: "#96a0b2", 2: "#4a90e2", 3: "#9b51e0", 4: "#e88024"}

        items.append({
            "id": iid,
            "name": name_m.group(1),
            "tier_name": tier_names.get(tier, "普通"),
            "tier_color": tier_colors.get(tier, "#96a0b2"),
            "desc": desc_m.group(1) if desc_m else "",
            "icon": icon_file if os.path.exists(icon_file) else "",
            "closeup": f"tests/inspect/item_{iid}_closeup.png"
        })
    return items

def parse_enemies():
    enemies = []
    # 动态拉取 EnemyGuideData 的 17 种怪物列表
    path = "scripts/data/EnemyGuideData.gd"
    if not os.path.exists(path):
        return enemies
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    m = re.search(r'static func catalog_ids\(\) -> Array:\s*\n\t*return \[(.*?)\]', text, re.DOTALL)
    if not m:
        return enemies
    ids = [i.strip().strip('"').strip("'") for i in m.group(1).split(",") if i.strip()]

    # 扫描中文名
    for eid in ids:
        name_m = re.search(rf'\"{eid}\":\s*\{{[^}}]*\"desc\":\s*\"([^\"]+)\"', text)
        desc = name_m.group(1) if name_m else ""
        enemies.append({
            "id": eid,
            "name": eid,
            "desc": desc,
            "closeup": f"tests/inspect/enemy_{eid}_closeup.png"
        })
    return enemies

def generate_html_report(out_html_path="tests/inspect/index.html"):
    os.makedirs(os.path.dirname(out_html_path), exist_ok=True)

    cultivators = parse_cultivators()
    weapons = parse_weapons()
    items = parse_items()
    enemies = parse_enemies()

    # 7 大全景走廊图
    cultivator_gallery = "tests/inspect/cultivator_gallery_all.png"
    if not os.path.exists(cultivator_gallery):
        cultivator_gallery = "tests/styles/cultivator_modular_gallery.png"
    cultivator_gallery_b64 = get_base64_image(cultivator_gallery)

    weapon_gallery = "tests/inspect/weapon_gallery_all.png"
    if not os.path.exists(weapon_gallery):
        weapon_gallery = "tests/styles/weapon_hall_review_all68.png"
    weapon_gallery_b64 = get_base64_image(weapon_gallery)

    item_gallery = "tests/inspect/item_gallery_all.png"
    item_gallery_b64 = get_base64_image(item_gallery)

    enemy_gallery = "tests/inspect/enemy_gallery_all.png"
    enemy_gallery_b64 = get_base64_image(enemy_gallery)

    vfx_gallery = "tests/inspect/vfx_gallery_all.png"
    vfx_gallery_b64 = get_base64_image(vfx_gallery)

    projectile_gallery = "tests/inspect/projectile_gallery_all.png"
    projectile_gallery_b64 = get_base64_image(projectile_gallery)

    ui_gallery = "tests/inspect/ui_gallery_all.png"
    ui_gallery_b64 = get_base64_image(ui_gallery)

    # 8 大核心实景视口截图
    screens = [
        {"id": "battle", "name": "核心战斗与实时 HUD", "desc": "修士站位、背负神兵、环绕妖魔与顶栏血条状态"},
        {"id": "levelup", "name": "波后悟道结算加点", "desc": "五选一卡牌矩阵、稀有度边框与机制描述展示"},
        {"id": "shop", "name": "灵石阁商店交易货架", "desc": "货架商品锁定、售罄态、持有陈列与交互栏"},
        {"id": "cultivator_select", "name": "全道统修仙真身名册", "desc": "左右分栏角色详解、天赋代价与 3D 渲染头像框"},
        {"id": "start_menu", "name": "主界面与道途启航", "desc": "开局背景、道印徽记与主行动按钮阵列"},
    ]
    for sc in screens:
        sc["b64"] = get_base64_image(f"tests/inspect/screen_{sc['id']}.png")

    html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>剑士 · 游戏美术视觉检视全景看板 (Asset Inspector)</title>
<style>
  :root {{
    --bg-main: #07090e;
    --bg-card: #0d121c;
    --bg-card-hover: #131a28;
    --border-color: #1a2538;
    --border-highlight: #2f4366;
    --text-paper: #e6ecf5;
    --text-grey: #8a99ad;
    --accent-blue: #3b82f6;
    --accent-gold: #f59e0b;
    --accent-jade: #10b981;
    --tag-bg: #162032;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    background-color: var(--bg-main);
    color: var(--text-paper);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "MiSans", sans-serif;
    padding: 24px 32px;
    line-height: 1.5;
  }}
  header {{
    border-bottom: 1px solid var(--border-color);
    padding-bottom: 20px;
    margin-bottom: 24px;
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
  }}
  h1 {{ font-size: 24px; font-weight: 700; color: var(--text-paper); display: flex; align-items: center; gap: 12px; }}
  .badge {{ background: var(--tag-bg); color: var(--accent-gold); font-size: 12px; padding: 3px 8px; border: 1px solid var(--border-highlight); }}
  .tabs {{ display: flex; gap: 8px; margin-bottom: 24px; flex-wrap: wrap; }}
  .tab-btn {{
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    color: var(--text-grey);
    padding: 8px 18px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }}
  .tab-btn:hover {{ background: var(--bg-card-hover); color: var(--text-paper); }}
  .tab-btn.active {{ background: var(--accent-blue); border-color: var(--accent-blue); color: #fff; }}
  .content-section {{ display: none; }}
  .content-section.active {{ display: block; }}
  .gallery-banner {{
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    padding: 16px;
    margin-bottom: 24px;
  }}
  .gallery-banner h3 {{ font-size: 15px; margin-bottom: 10px; color: var(--accent-gold); }}
  .gallery-img {{ width: 100%; height: auto; border: 1px solid var(--border-highlight); background: #000; cursor: pointer; }}
  .grid {{
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 16px;
  }}
  .card {{
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    padding: 14px;
    transition: all 0.2s;
  }}
  .card:hover {{ border-color: var(--accent-blue); transform: translateY(-2px); }}
  .card-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }}
  .card-title {{ font-size: 15px; font-weight: 600; color: var(--text-paper); }}
  .card-id {{ font-size: 11px; color: var(--text-grey); }}
  .card-tag {{ font-size: 11px; color: var(--accent-jade); background: var(--tag-bg); padding: 2px 6px; }}
  .card-desc {{ font-size: 12px; color: var(--text-grey); margin-bottom: 10px; height: 36px; overflow: hidden; }}
  .img-wrap {{
    background: #000;
    border: 1px solid var(--border-color);
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 140px;
    overflow: hidden;
  }}
  .img-wrap img {{ max-width: 100%; height: auto; image-rendering: pixelated; }}
  .modal {{
    display: none; position: fixed; z-index: 999; left: 0; top: 0; width: 100%; height: 100%;
    background-color: rgba(0,0,0,0.85); justify-content: center; align-items: center;
  }}
  .modal.open {{ display: flex; }}
  .modal-content {{ max-width: 92%; max-height: 92%; border: 1px solid var(--accent-blue); box-shadow: 0 0 24px rgba(0,0,0,0.9); }}
</style>
</head>
<body>

<header>
  <div>
    <h1>剑士 · 游戏美术视觉检视全景看板 <span class="badge">Asset Inspector v2.0</span></h1>
    <p style="color: var(--text-grey); font-size: 13px; margin-top: 6px;">全道统修仙真身 · 69 法器 · 87 法宝道具 · 17 种妖魔 · 12 款攻击特效 · 21 种纯矢量弹丸 · UI 规范全链路视觉质量平台</p>
  </div>
</header>

<div class="tabs">
  <button class="tab-btn active" onclick="openTab('cultivators', this)">修仙真身 ({len(cultivators)})</button>
  <button class="tab-btn" onclick="openTab('weapons', this)">法器神兵 ({len(weapons)})</button>
  <button class="tab-btn" onclick="openTab('items', this)">法宝道具 ({len(items)})</button>
  <button class="tab-btn" onclick="openTab('enemies', this)">妖魔拟态 ({len(enemies)})</button>
  <button class="tab-btn" onclick="openTab('vfx', this)">武器攻击特效 (12刀光+光束+火锥+6法印)</button>
  <button class="tab-btn" onclick="openTab('projectiles', this)">飞行物弹道 (21纯矢量+飞弹)</button>
  <button class="tab-btn" onclick="openTab('ui', this)">界面规范组件 (GameStyle)</button>
  <button class="tab-btn" onclick="openTab('screens', this)">核心界面视口 (5大实景)</button>
</div>

<!-- 1. 修仙者 -->
<div id="tab-cultivators" class="content-section active">
  {"<div class='gallery-banner'><h3>◆ 全员动态走廊画廊看板 (点击放大)</h3><img class='gallery-img' src='" + cultivator_gallery_b64 + "' onclick='viewImage(this.src)' alt='全员走廊图'></div>" if cultivator_gallery_b64 else ""}
  <div class="grid">
"""

    for c in cultivators:
        img_src = get_base64_image(c["closeup"]) if c["closeup"] else get_base64_image(c["icon"])
        html += f"""
    <div class="card">
      <div class="card-header">
        <span class="card-title">{c['name']}</span>
        <span class="card-id">{c['id']}</span>
      </div>
      <div class="card-desc">「{c['epithet']}」</div>
      <div class="img-wrap">
        {"<img src='" + img_src + "' onclick='viewImage(this.src)' alt='" + c['name'] + "'>" if img_src else "<span style='color:var(--text-grey);font-size:12px;'>暂无特写</span>"}
      </div>
    </div>
"""

    html += """
  </div>
</div>

<!-- 2. 法器 -->
<div id="tab-weapons" class="content-section">
"""
    if weapon_gallery_b64:
        html += f"<div class='gallery-banner'><h3>◆ 69 把法器全景走廊看板 (点击放大)</h3><img class='gallery-img' src='{weapon_gallery_b64}' onclick='viewImage(this.src)' alt='法器走廊图'></div>"

    html += """
  <div class="grid">
"""
    for w in weapons:
        img_src = get_base64_image(w["closeup"]) if os.path.exists(w["closeup"]) else get_base64_image(w["icon"])
        html += f"""
    <div class="card">
      <div class="card-header">
        <span class="card-title">{w['name']}</span>
        <span class="card-tag">{w['tag']}</span>
      </div>
      <div class="card-desc">{w['desc']}</div>
      <div class="img-wrap">
        {"<img src='" + img_src + "' onclick='viewImage(this.src)' alt='" + w['name'] + "'>" if img_src else "<span style='color:var(--text-grey);font-size:12px;'>无图标</span>"}
      </div>
    </div>
"""

    html += """
  </div>
</div>

<!-- 3. 法宝道具 -->
<div id="tab-items" class="content-section">
"""
    if item_gallery_b64:
        html += f"<div class='gallery-banner'><h3>◆ 全量法宝道具画廊看板 (点击放大)</h3><img class='gallery-img' src='{item_gallery_b64}' onclick='viewImage(this.src)' alt='道具走廊图'></div>"

    html += """
  <div class="grid">
"""
    for it in items:
        img_src = get_base64_image(it["closeup"]) if os.path.exists(it["closeup"]) else get_base64_image(it["icon"])
        html += f"""
    <div class="card">
      <div class="card-header">
        <span class="card-title">{it['name']}</span>
        <span class="card-tag" style="color:{it['tier_color']}">{it['tier_name']}</span>
      </div>
      <div class="card-desc">{it['desc']}</div>
      <div class="img-wrap">
        {"<img src='" + img_src + "' onclick='viewImage(this.src)' alt='" + it['name'] + "'>" if img_src else "<span style='color:var(--text-grey);font-size:12px;'>无图标</span>"}
      </div>
    </div>
"""

    html += """
  </div>
</div>

<!-- 4. 妖魔拟态 -->
<div id="tab-enemies" class="content-section">
"""
    if enemy_gallery_b64:
        html += f"<div class='gallery-banner'><h3>◆ 妖魔万象动态全景画廊看板 (全量 17 种，点击放大)</h3><img class='gallery-img' src='{enemy_gallery_b64}' onclick='viewImage(this.src)' alt='妖魔走廊图'></div>"

    html += """
  <div class="grid">
"""
    for e in enemies:
        img_src = get_base64_image(e["closeup"]) if os.path.exists(e["closeup"]) else ""
        html += f"""
    <div class="card">
      <div class="card-header">
        <span class="card-title">{e['name']}</span>
        <span class="card-id">{e['id']}</span>
      </div>
      <div class="card-desc">{e['desc']}</div>
      <div class="img-wrap">
        {"<img src='" + img_src + "' onclick='viewImage(this.src)' alt='" + e['name'] + "'>" if img_src else "<span style='color:var(--text-grey);font-size:12px;'>运行 inspect enemy " + e['id'] + " 生成特写</span>"}
      </div>
    </div>
"""

    html += f"""
  </div>
</div>

<!-- 5. 武器攻击特效 -->
<div id="tab-vfx" class="content-section">
  {"<div class='gallery-banner'><h3>◆ 武器攻击特效与元素法相全景画廊 (点击放大)</h3><img class='gallery-img' src='" + vfx_gallery_b64 + "' onclick='viewImage(this.src)' alt='特效走廊图'></div>" if vfx_gallery_b64 else ""}
</div>

<!-- 6. 飞行物与弹道 -->
<div id="tab-projectiles" class="content-section">
  {"<div class='gallery-banner'><h3>◆ 全量法器飞行物与弹道纯矢量画廊 (点击放大)</h3><img class='gallery-img' src='" + projectile_gallery_b64 + "' onclick='viewImage(this.src)' alt='弹道画廊图'></div>" if projectile_gallery_b64 else ""}
</div>

<!-- 7. 界面组件规范 -->
<div id="tab-ui" class="content-section">
  {"<div class='gallery-banner'><h3>◆ UI 视觉设计与组件规范样张 (点击放大)</h3><img class='gallery-img' src='" + ui_gallery_b64 + "' onclick='viewImage(this.src)' alt='UI样张'></div>" if ui_gallery_b64 else ""}
</div>

<!-- 8. 核心界面视口 -->
<div id="tab-screens" class="content-section">
  <div class="grid" style="grid-template-columns: repeat(auto-fill, minmax(420px, 1fr));">
"""
    for sc in screens:
        img_src = sc["b64"]
        html += f"""
    <div class="card">
      <div class="card-header">
        <span class="card-title">{sc['name']}</span>
        <span class="card-id">{sc['id']}</span>
      </div>
      <div class="card-desc">{sc['desc']}</div>
      <div class="img-wrap" style="min-height: 236px;">
        {"<img src='" + img_src + "' onclick='viewImage(this.src)' alt='" + sc['name'] + "'>" if img_src else "<span style='color:var(--text-grey);font-size:12px;'>运行 inspect screen " + sc['id'] + " 生成截图</span>"}
      </div>
    </div>
"""
    html += """
  </div>
</div>

<div id="modal" class="modal" onclick="closeModal()">
  <img id="modal-img" class="modal-content" src="">
</div>

<script>
function openTab(tabName, el) {{
  document.querySelectorAll('.content-section').forEach(function(item) {{ item.classList.remove('active'); }});
  document.querySelectorAll('.tab-btn').forEach(function(item) {{ item.classList.remove('active'); }});
  document.getElementById('tab-' + tabName).classList.add('active');
  el.classList.add('active');
}}
function viewImage(src) {{
  var modal = document.getElementById('modal');
  var img = document.getElementById('modal-img');
  img.src = src;
  modal.classList.add('open');
}}
function closeModal() {{
  document.getElementById('modal').classList.remove('open');
}}
</script>

</body>
</html>
"""

    with open(out_html_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[HTML Report] 成功生成 7 大分类全景离线画廊至: {out_html_path}")
    return out_html_path

if __name__ == "__main__":
    generate_html_report()
