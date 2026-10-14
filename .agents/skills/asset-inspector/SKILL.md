---
name: asset-inspector
description: 游戏美术与全域视觉资产（修仙真身角色、法器武器、法宝道具、妖魔拟态、攻击特效VFX、飞行物弹丸、UI设计组件、全景走廊图）的检视、高清特写抓拍、器尖标定、穿模核验与一键走廊图更新技能规范。当用户要求查看/检视角色外观、武器/道具图标、攻击特效/刀光/光束/火锥、飞行物子弹、UI样式组件、走廊图、画廊复查，或在新增/修改外观后进行视觉验收时使用。
---

# 游戏美术视觉检视与全景画廊工作流 (Asset Inspector)

本技能定义了《剑士》项目中所有美术与视觉资产的检视规范与自动化工具流。

针对项目中**程序化绘制无静态实体图**、**既有走廊图压缩过度看不清细节**、**Godot Headless 模式静默不出图**、**攻击特效与弹丸分散无法直观审视**等长期痛点，本规范统一了查看流程，配套了单体高清特写抓拍与 7 大全景走廊看板。

---

## 一、 核心痛点与避坑铁律

1. **绝对禁止带 `--headless` 运行预览场景出图**
   - Godot 在 headless 模式下不会创建渲染视口，`get_viewport().get_texture().get_image()` 返回空图。
   - 所有检视命令统一通过 `tools/inspect.py` 调度，严禁直接手写裸跑 Godot 预览导出命令。
2. **拒绝盲人摸象，单体改动必须跑特写**
   - 角色 4 大插槽参数（体型、面部、斗篷、背负法器）调整后，必须跑 `cultivator <id>` 查看 3.5x 四视角特写。
   - 绝不能仅依赖低分辨率缩略看板进行验收。
3. **法器图标「器尖 tip 标定」必须见线**
   - `WeaponData.gd` 中的 `tip` 是实弹与出膛方向的基准。
   - 检视法器时必须检查橙色标定线是否精确指向刀刃/剑锋尖端，严禁指向剑柄或中心空地。
4. **范围视觉与判定同源**
   - 武器刀光、光束、火锥与弹丸：画多大 == 判多大，杜绝用发光虚焦掩盖判定不符。

---

## 二、 统一 CLI 调度工具 (`tools/inspect.py`)

统一入口：`python3 tools/inspect.py <subcommand> [id|--all]`

### 1. 修仙真身角色 (Cultivator)
- **单体特写**：`python3 tools/inspect.py cultivator <id>`
  - 示例：`python3 tools/inspect.py cultivator kuxingseng`
  - 产物：`tests/inspect/cultivator_<id>_closeup.png` (960×540)
  - 内容：正面（拔剑斜背）、侧面（背剑无穿模）、背面（全貌背带）、御风（4.8°侧倾流体翻浪）4 视角 3.5x 高清特写 + 4 大插槽参数面板。
- **全员走廊图**：`python3 tools/inspect.py cultivator --all`
  - 产物：`tests/inspect/cultivator_gallery_all.png` (960×540)
  - 动态读取 `CultivatorData.gd` 全量 20+ 位角色，三重视角全对齐，杜绝硬编码遗漏。

### 2. 本命法器与神兵 (Weapon)
- **单体特写**：`python3 tools/inspect.py weapon <id>`
  - 示例：`python3 tools/inspect.py weapon gengjin_feijian`
  - 产物：`tests/inspect/weapon_<id>_closeup.png` (720×460)
  - 内容：8x 最近邻无模糊像素放大、透明抠底棋盘格、中心十字准星、真实器尖 tip 标定橙色指示线、流派五行与机制说明。
- **全景走廊图**：`python3 tools/inspect.py weapon --all`
  - 产物：`tests/inspect/weapon_gallery_all.png`
  - 涵盖全部 69 把法器，标定 ID、名称、标签、器类与是否占位复用。

### 3. 法宝道具 (Item)
- **单体特写**：`python3 tools/inspect.py item <id>`
  - 示例：`python3 tools/inspect.py item jubaopen`
  - 产物：`tests/inspect/item_<id>_closeup.png` (700×450)
  - 内容：8x 像素特写、品阶档位（普通/稀有/史诗/传说）专属品质色框、加成机制。
- **全景走廊图**：`python3 tools/inspect.py item --all`
  - 产物：`tests/inspect/item_gallery_all.png`
  - 全量 87 件法宝道具画廊矩阵。

### 4. 妖魔拟态 (Enemy)
- **单体特写**：`python3 tools/inspect.py enemy <id>`
  - 示例：`python3 tools/inspect.py enemy boss`
  - 产物：`tests/inspect/enemy_<id>_closeup.png` (960×540)
  - 内容：静止幽火呼吸、御风移动流体行波、水平转向镜像翻转 3 态特写 + 骨甲与灵核参数。
- **全景画廊**：`python3 tools/inspect.py enemy --all`
  - 产物：`tests/inspect/enemy_gallery_all.png` (960×540)
  - 动态拉取 `EnemyGuideData.catalog_ids()` 全量 17 种妖魔（常规 12 妖、3 大精英、赤炎魔将、衔宝金蟾无遗漏）。

### 5. 武器攻击特效与元素法相 (VFX)
- **单体特写**：`python3 tools/inspect.py vfx <kind>`
  - 示例：`python3 tools/inspect.py vfx fire_slash`、`python3 tools/inspect.py vfx beam`、`python3 tools/inspect.py vfx flame_cone`、`python3 tools/inspect.py vfx fire_rain`
  - 产物：`tests/inspect/vfx_<kind>_closeup.png`
- **全景画廊**：`python3 tools/inspect.py vfx --all`
  - 产物：`tests/inspect/vfx_gallery_all.png` (960×540)
  - 包含六元素近战刀光（金/火/水/木/土/雷）、六元素横扫大扇面、紫晶穿透光束、三昧真火锥、六道法阵落点形态（火雨/冰晶/音波/天鼓/地裂/镇印）。

### 6. 飞行物与弹道 (Projectile / Bullet)
- **单体特写**：`python3 tools/inspect.py projectile <id>` (或 `bullet <id>`)
  - 示例：`python3 tools/inspect.py projectile gengjin_feijian`
  - 产物：`tests/inspect/projectile_<id>_closeup.png`
- **全景画廊**：`python3 tools/inspect.py projectile --all`
  - 产物：`tests/inspect/projectile_gallery_all.png` (960×540)
  - 包含全量 21 种纯矢量神剑、飞刀、银针、金针、冰针、骨刺、8色神符、烈焰火煞与灵弹矩阵。

### 7. 界面组件规范 (UI Style)
- **规范样张画廊**：`python3 tools/inspect.py ui`
  - 产物：`tests/inspect/ui_gallery_all.png` (960×540)
  - 涵盖 GameStyle 标题大匾、五档色带卡（普通/稀有/史诗/传说/已选）、三大按钮体系（主行动/次要/危险）、侧签行与进度条。

### 8. 交互式 HTML 离线画廊与一键全量构建
- **生成 HTML 报告**：`python3 tools/inspect.py report`
  - 产物：`tests/inspect/index.html`（单文件自包含、内嵌 Base64 图、7 大分类 Tab、支持点击大图弹窗）。
- **一键全量更新**：`python3 tools/inspect.py all`
  - 自动重新生成所有 7 大画廊图并打包 HTML 报告。

---

## 三、 Agent 视觉检视验收 SOP

在新增角色、修改武器、调整图标、重构特效或用户要求「看一下/走走廊图」时，按以下流水线执行：

```
1. 明确目标资产类型与 ID (如 cultivator kuxingseng / vfx fire_slash / projectile gengjin_feijian)
                      │
                      ▼
2. 运行对应 CLI 导出高清特写或走廊图
   $ python3 tools/inspect.py <target> <id>
                      │
                      ▼
3. Agent 调用 Read 工具读取生成的 PNG 产物
   Read("tests/inspect/...")
                      │
                      ▼
4. 对照验收判据核验视觉质量 (见下表)
                      │
                      ▼
5. 如需提供给用户，告知生成路径并指引浏览器查看 tests/inspect/index.html
```

### 核心视觉验收判据

| 资产类别 | 检视重点 | 合格判据 |
|:---|:---|:---|
| **角色正面** | 武器与头部/斗篷关系 | 剑柄探出右肩轮廓外，剑身倾角适中，下端收于斗篷内部，**严禁从斗篷下沿伸出**。 |
| **角色侧面** | 武器背负与下摆穿模 | 武器稳负于后背，器尖微挑，下端与斗篷下沿保持至少 18px 留白，**严禁戳出变成「长脚」**。 |
| **角色背面** | 图层 Z-order 与背带 | 斗篷在底，背带清晰斜跨，法器在最外层（Z-order 最前），无反向遮挡。 |
| **角色色调** | 仙侠空洞风格 | 统一骨白/虚空黑/冷冽荧光，粗黑边干净利落无脏色。 |
| **武器图标** | 48×48 画布居中与标定 | 刃部铺满适度，橙色 tip 标定线精准击中器物顶端，透明抠底边缘无残留孤点杂色。 |
| **武器攻击特效** | 元素形态与判定几何 | 金亮刃/火卷舌/冰晶棱/藤叶刺/岩裂台/紫电弧，外缘严格贴合 OUTER(124px)，几何判定同源。 |
| **飞行物纯矢量** | 动态流光与形态 | 针细刃锐，神符印纹清晰，出膛姿态右上 45°，无模糊像素与锯齿拉伸。 |
| **道具图标** | 品阶色系匹配 | 档位色彩边框分明（白灰/蓝/紫/金橙），像素无拉伸模糊。 |
| **界面规范** | 无圆角无渐变 | 严格遵循斜切平行四边形、深蓝底、纸白字、灵金/翡翠点缀原则。 |
