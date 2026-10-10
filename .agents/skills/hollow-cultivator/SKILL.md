---
name: hollow-cultivator
description: 将修仙幸存者中的修士角色重塑/修改/绘制为「土豆兄弟式参数化·空洞冷冽仙侠风」高精程序化角色的操作指南与流水线规范。当用户要求修改/新增/扩展角色人物形象、按土豆兄弟模式调整体型/面孔/斗篷/背负武器、或将其他道统人物（如石岳、灵童、金算盘等）接入程序化形象时使用。
---

# 土豆兄弟式修仙素体 · 程序化角色极速拓展流水线

本技能定义了游戏内修士角色的通用程序化美术与动态渲染流水线。核心理念借鉴《土豆兄弟》（Brotato）：**全员共享统一的底层素体骨架与仙人御风动态，通过 4 个高辨识度的参数化插槽（体型比例、面部首饰、斗篷色彩款式、背负本命法器）实现极速派生与差异化**。

---

## 一、 核心架构：修仙素体与 4 大外观插槽 (Visual Slots)

所有角色共用统一的通用渲染器 `HollowKnightCultivatorRenderer.gd`，**严禁为每个角色复制编写数百行独立渲染脚本**。任何角色的外观完全由 `CultivatorVisualConfig.gd` 中的 4 大插槽字典定义：

```gdscript
@export var body: Dictionary = {
    "scale": 1.0,         # 整体缩放 (如石岳 1.18 魁梧, 灵童 0.85 娇小)
    "width_scale": 1.0,   # 肩宽与体宽 (如石岳 1.25 宽厚, 幽娘 0.88 纤细)
    "height_scale": 1.0,  # 纵向高矮
    "head_scale": 1.0     # 头身比 (如灵童 1.14 萌系大头, 刀圣 0.94 干练成熟)
}

@export var face: Dictionary = {
    "mask_style": "oval_chin",   # "oval_chin" 鹅蛋面 | "square_rock" 方阔岩面 | "round_petite" 娇小圆面 | "sharp_fox" 细长狐面 | "stout_brute" 霸气蛮面
    "horns_style": "butterfly",  # "butterfly" 蝶羽仙角 | "bull_horns" 蛮兽牛角 | "dao_bun" 发髻木簪 | "bamboo_hat" 竹斗笠 | "talisman" 镇煞黄符 | "gold_crown" 铜钱冠 | "fox_ears" 狐耳 | "none" 光洁
    "eye_style": "hollow_oval",  # "hollow_oval" 经典深渊月光眼 | "sharp_slit" 冷眸细线 | "round_pupil" 道童圆目 | "angry_slit" 怒目斜挑
    "eye_color": Color(...),     # 眼神辉光色
    "eye_core_color": Color(...) # 瞳仁高光核心色
}

@export var cloak: Dictionary = {
    "cloak_style": "split_flowing", # "split_flowing" 裂帛飞扬 | "heavy_overcoat" 厚重大氅 | "short_cape" 灵动短披 | "tattered_rags" 残破百衲袍 | "royal_shawl" 云肩霞帔
    "col_outer": Color(...),        # 外袍深色
    "col_inner": Color(...),        # 内衬底色
    "col_edge": Color(...),         # 边缘月辉/金边/冷玉色
    "chest_ornament": "pearl"       # "pearl" 灵玉珠 | "bagua" 八卦镜 | "coin" 铜钱扣 | "skull" 兽骨扣 | "none" 无
}

@export var weapon: Dictionary = {
    "weapon_type": "bone_nail",  # "bone_nail" 骨钉长剑 | "stone_pillar" 玄重石尺 | "peach_sword" 桃木符剑 | "golden_abacus" 乾坤金算盘 |
                                 # "shadow_daggers" 阴影双刺 | "broken_blade" 厚背断刀 | "bone_axe" 兽骨战斧 | "soul_banner" 招魂灵幡 | "treasure_chest" 乾坤百宝匣
    "col_main": Color(...),      # 武器主体色
    "col_shadow": Color(...),    # 武器明暗切面色
    "col_accent": Color(...),    # 符文流光/剑脊寒光/金丝边
    "strap_style": "diagonal"    # "diagonal" 单肩斜跨带 | "dual" 双肩背带 | "floating" 悬浮御物
}
```

---

## 二、 摄影机位与空间透视铁律 (Camera & Perspective Rules)

全员武器在 50°~60° 俯视角下，必须绝对遵循空间透视铁律，**杜绝任何穿模或穿帮**：

| 机位视角 | 武器呈现与图层 Z-order 铁律 | 姿态细节 |
| :--- | :--- | :--- |
| **正面 (Front View)** | **右手拔剑大角度斜贯背负**（倾角 152°）<br>（图层：武器 $\to$ 斗篷 $\to$ 胸饰 $\to$ 头部） | 武器紧凑小巧（约 26~28px）；手柄与剑首端正探出右肩轮廓外，武器下端妥帖收纳于斗篷后，**严禁从斗篷底部伸出**，保持正面轮廓干净整洁。 |
| **侧面 (Side View)** | **法器稳稳负于后背中上方**（倾角 -24°）<br>（图层：武器 $\to$ 侧面斗篷 $\to$ 侧面头部） | **严禁在待机和移动时将武器端在身前**，更**严禁从斗篷下沿戳出（避免看起来像长了只脚！）**。器械端部向后上方轻挑，下端收于斗篷内部（距下摆至少 18~20px）。 |
| **背面 (Back View)** | **法器绘制在斗篷最外层**（Z-order 最前！）<br>（图层：斗篷 $\to$ 背带 $\to$ 法器 $\to$ 后脑骨冠） | 斗篷作为深色底衬，法器端正横贯背部中上方，斜跨背带，明暗对比鲜明，器械尖端离斗篷下沿有充裕留白。 |

---

## 三、 动态手感标准：仙人御风飞行 (Harmonic Wave Dynamics)

全员通享纯正的修仙御风悬浮手感：
1. **1.6px 黄金长波浮沉 (Harmonic Wave)**：周期 `1.8Hz` 左右（`sin(time * 4.2) * 1.6`），平滑正弦波，如海浪推舟、凌波微步。
2. **7.5° 气动侧倾角 (Bank Roll)**：当摇杆产生横向速度分量时，身体随转向优雅侧倾最高 7.5°，消除纸片人生硬平移感。
3. **双频流体风阻斗篷**：移动时斗篷受风压向后拉伸 `clampf(speed_ratio, 0.4, 1.4) * 9.0px`，叠加长波翻浪与高频微风轻颤。
4. **气垫式地影呼吸**：随浮沉动态收放，体型宽阔者地影随之加宽。

---

## 四、 新增/修改角色 4 步极速拓展流程

当需要新增一个角色或调整某个角色形象时，按照以下 4 步快速完成：

### 步骤 1：在 `CultivatorVisualConfig.gd` 配置或调整参数
在 `CultivatorVisualConfig.gd` 中为新角色添加一个工厂方法（或直接修改对应字典）：
```gdscript
static func make_new_char() -> CultivatorVisualConfig:
    var cfg := CultivatorVisualConfig.new()
    cfg.body = { "scale": 1.1, "width_scale": 1.15, "height_scale": 1.0, "head_scale": 1.0 }
    cfg.face = { "mask_style": "round_petite", "horns_style": "dao_bun", "eye_style": "round_pupil", "eye_color": Color(...) }
    cfg.cloak = { "cloak_style": "short_cape", "col_outer": Color(...), "col_inner": Color(...), "col_edge": Color(...), "chest_ornament": "bagua" }
    cfg.weapon = { "weapon_type": "peach_sword", "col_main": Color(...), "col_shadow": Color(...), "col_accent": Color(...), "strap_style": "diagonal" }
    cfg._sync_palette()
    return cfg
```

### 步骤 2：若引入全新武器或头饰，在组件库中追加轻量分支
如果新角色拥有前所未见的新武器形制或头饰，在 `HollowKnightCultivatorRenderer.gd` 的 `_draw_modular_weapon` 或 `_draw_modular_headwear` 中追加一个 `match` 分支（仅需 10~15 行纯矢量几何描述）。

### 步骤 3：在 `CultivatorData.gd` 中启用程序化
在对应角色条目中设置：
```gdscript
"motion": "procedural",
"render_style": "hollow_knight",
```

### 步骤 4：运行矩阵画廊看板导出验收
运行窗口化画廊测试脚本：
```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/CultivatorGalleryPreview.tscn -- --export
```
检查生成的 `tests/styles/cultivator_modular_gallery.png`，确认该角色在正面、侧面（无长脚穿模）、背面均表现完美。

---

## 五、 全套测试门禁验证

执行核心基线测试，确保全绿退出码 0：
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/UnitRunner.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/SmokeRunner.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/PoolCheck.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/LayoutCheck.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/FontCoverageCheck.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/BalanceSimCheck.tscn
```
并在本地 `CHANGELOG.md` 记录变更。
