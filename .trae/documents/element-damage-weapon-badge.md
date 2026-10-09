# 给吃「元素伤害」加成的法器加角标

## 背景与现状

「元素伤害」（`elemental_damage`，面板属性，来自悟道「五行真火」+2/层）经 [GameBalance.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/GameBalance.gd#L441-L479) `weapon_stat_bonus()` 按 `stat_scalings.elemental_damage` 系数转化为该武器伤害，星级每 +1 效率 ×1.25。**15 把法器中仅 7 把在 [WeaponData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/WeaponData.gd) 的 `stat_scalings` 里配了该字段**：

| 武器 | id | 系数 | 定义处行号 |
|---|---|---|---|
| 焚天宝灯 | fentian_baodeng | 1.5 | L194 |
| 五雷法牌 | wulei_paizi | 1.2 | L208 |
| 火焰符 | huoyan_fu | 1.0 | L169 |
| 番天镇岳印 | fantian_yin | 1.0 | L221 |
| 赤焰斩马刀 | chiyan_dao | 0.8 | L181 |
| 万木灵符 | wanmu_lingfu | 0.8 | L105 |
| 青木藤鞭 | qingmu_tengbian | 0.6 | L92 |

其余 8 把（金系 3 把、水系 3 把、灵蝶、混元古钟）完全不吃。**注意区分**：另一条「全元素伤害」链路（`element_damage_all`，仙品「五行贯通」）走 `GameManager.element_damage_mult()` 按武器五行给所有武器加成，无需标记。

问题：各列表界面（开局选武器、灵石阁货架/槽位、人物属性面板、图鉴）均无标记，只有详情弹窗里 `scaling_desc()` 文案提到。用户要求：给吃元素加成的法器加**图标角标**（橙红小斜块写「元素」），覆盖全部界面，且悟道加点的「五行真火」卡提示当前上阵受益数。

## 用户已确认的决策

1. 样式：**图标角标**（不是色签、不是边框变色），大卡小槽统一
2. 覆盖：**全部界面**（开局选武器 / 灵石阁货架+上阵仓库槽 / 人物属性面板上阵+仓库槽 / 图鉴）
3. 悟道加点「五行真火」卡：**要**追加「当前上阵 N 把法器受此加成」

## 改动方案

### 1. 数据层 — [scripts/data/WeaponData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/WeaponData.gd)

在 `scaling_desc()`（L414 附近）旁新增静态纯函数：

```gdscript
## 该法器是否吃「元素伤害」属性加成：stat_scalings 里配了 elemental_damage 系数才算。
## 返回系数（0 = 不吃），供各界面挂角标与悟道加点提示共用。
static func elemental_scaling_coef(id: String) -> float:
	return float(get_def(id).get("stat_scalings", {}).get("elemental_damage", 0.0))
```

### 2. 样式层 — [scripts/ui/GameStyle.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/GameStyle.gd)

- 色板区（L26 GREY 附近）加：`const ELEMENT := Color("ff8a3d")`（元素橙红，与蓝/黄/绿/红都不撞）
- 新增角标工厂（`chip()` L284 附近）：

```gdscript
## 「元素」角标：挂在武器图标容器右上角的小斜块（吃元素伤害加成的法器专用）。
## 调用方 add_child 后靠 EXPAND_FILL + 对齐贴角（同 star_lbl 模式），字号小槽 8、大卡 11。
static func element_badge(font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = " 元素 "
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_stylebox_override("normal", chip(ELEMENT))
	label(lbl, font_size, INK_TEXT)
	return lbl
```

实现说明：图标容器多为 `PanelContainer`，其子节点被铺满内容区，所以照抄各界面现有 `star_lbl` 的「EXPAND_FILL + alignment 贴角」模式，不另用锚点。`chip()` 自带斜切与 2/3px content margin，符合斜切语言。

### 3. UI 接入 — 5 处

每处均为：**仅当 `WeaponData.elemental_scaling_coef(id) > 0.0` 时**，往图标容器（PanelContainer）`add_child(GameStyle.element_badge(字号))`。角标是覆盖层，不改容器 `custom_minimum_size`，不会顶动现有布局。

| # | 文件 | 位置 | 挂点 | 字号 |
|---|---|---|---|---|
| 3.1 | [PlayerStatsDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/PlayerStatsDialog.gd#L938) `_refresh_weapons()` | 上阵槽（L938 `if filled:` 分支，加在 `star_lbl` 之前）与仓库槽（L979 循环内） | slot / s_slot | 8 |
| 3.2 | [WaveShop.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/WaveShop.gd#L468) `_create_inv_slot()` | L509 `slot.add_child(icon_tex)` 之后、`star_lbl` 之前 | slot | 8 |
| 3.3 | [WaveShop.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/WaveShop.gd#L784) `_create_offer_card()` | weapon 分支（L784-818），L880 `vbox.add_child(head)` 前挂到 `icon_box`；仅 `kind == "weapon"`，丹药/法宝不挂 | icon_box | 9 |
| 3.4 | [StartWeaponSelect.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/StartWeaponSelect.gd#L148) `_create_card()` | L160 `icon_box.add_child(icon_tex)` 之后 | icon_box | 9 |
| 3.5 | [ManualDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/ManualDialog.gd#L381) 武器页构建循环 | L381-385 `grid.add_child(card)` 前挂到 `card.get_meta("icon_tex")` 的父容器（icon_box）；法宝页不挂 | icon_box | 8 |

### 4. 悟道加点提示 — [scripts/ui/LevelUpDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/LevelUpDialog.gd#L277) `_create_card_entry()`

- 不写死 `elemental_up` id，按 `"elemental_damage" in data.get("apply", {})` 判断（以后加同类升级自动带上）
- 在描述 `r_desc`（L387）之后追加一行小字：`"✦ 当前上阵 %d 把法器受此加成"`，N = 遍历 `GameManager.get_weapons_summary()` 数 `elemental_scaling_coef(id) > 0` 的件数（含重复同名武器，因为每把都吃）
- 样式：`GameStyle.label(lbl, 11, GameStyle.ELEMENT)` + `GameStyle.wrap_cjk` 不需要（短句），居中对齐；N == 0 时显示 `"✦ 当前上阵法器均不受此加成"` 并用 `GameStyle.GREY`

## 假设与边界

- 法宝（ItemData）与丹药不挂角标（它们不走 `elemental_damage` 链路）
- 详情弹窗（`DetailTip`）已含 `scaling_desc()` 系数文案，不改动
- 不新增测试文件；布局正确性靠现有 `LayoutCheck` + 编辑器可视预览验证

## 验证

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --editor --quit          # 无新 class_name/素材，保险起见跑一次扫描
$G --headless --path . res://tests/UnitRunner.tscn
$G --headless --path . res://tests/SmokeRunner.tscn
$G --headless --path . res://tests/PoolCheck.tscn
$G --headless --path . res://tests/LayoutCheck.tscn
$G --headless --path . res://tests/FontCoverageCheck.tscn   # 新文案「元素」需确认子集覆盖（「全元素伤害」已有，大概率已含）
$G --headless --path . res://tests/BalanceSimCheck.tscn
```

另在编辑器里可视确认：人物属性面板上阵/仓库槽、灵石阁货架与槽位、开局选武器、图鉴、悟道加点「五行真火」卡的角标与提示行。

## 收尾

- 追加 [CHANGELOG.md](file:///Users/a1/Documents/01Code/Godot/t-1/CHANGELOG.md)：`## 2026-10-09 #XX`（当日序号顺延）
- 不改 AGENTS.md，不自动 commit
