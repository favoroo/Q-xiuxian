class_name SkinData
extends RefCounted

## 角色换色皮肤主题表（纯静态数据，唯一真话源）
## 每角色：默认「原色」+ 6 套全员共享主题皮肤。
## 2026-10-20 与难度解耦：tier 不再对应难度档位，改为「该角色累计通关次数」门槛（tier + 1 次，任意难度）。
## 解锁判定不走本表：GameManager.is_skin_unlocked() 读该角色记录里的 wins 累计。
## 皮肤只换配色（斗篷内/外/缘拼色 + 眼色 + 武器色 + 骨色微调），不改造型样式键。

## 主题数组下标即 skin_idx（0~5）；tier = 解锁所需的该角色通关次数 - 1（1~6 次）
const THEMES: Array[Dictionary] = [
	{   # 1 胜 —— 苍竹：青玉竹影，偏青的碧色与剑士本相墨绿拉开区分
		"name": "苍竹",
		"tier": 0,
		"cloak_outer": Color(0.07, 0.22, 0.21),   # 沉潭青
		"cloak_inner": Color(0.14, 0.42, 0.38),   # 青玉碧
		"cloak_edge": Color(0.46, 0.90, 0.74),    # 新竹翠芒
		"eye_color": Color(0.50, 0.95, 0.72, 0.55),
		"eye_core_color": Color(0.86, 1.0, 0.92),
		"weapon_main": Color(0.92, 0.97, 0.93),
		"weapon_shadow": Color(0.58, 0.75, 0.66),
		"weapon_accent": Color(0.48, 0.94, 0.70, 0.9),
	},
	{   # 2 胜 —— 赤霄：赤焰丹霞，暖意金边
		"name": "赤霄",
		"tier": 1,
		"cloak_outer": Color(0.27, 0.08, 0.09),   # 玄赤深红
		"cloak_inner": Color(0.52, 0.15, 0.13),   # 朱砂赤
		"cloak_edge": Color(0.96, 0.58, 0.22),    # 焰橙鎏光
		"eye_color": Color(1.0, 0.56, 0.24, 0.6),
		"eye_core_color": Color(1.0, 0.90, 0.68),
		"weapon_main": Color(0.98, 0.94, 0.87),   # 暖象牙
		"weapon_shadow": Color(0.78, 0.67, 0.58),
		"weapon_accent": Color(0.98, 0.62, 0.24, 0.9),
		"bone_white": Color(0.98, 0.95, 0.90),    # 骨色微暖，与赤袍相合
		"bone_shadow": Color(0.82, 0.76, 0.69),
	},
	{   # 3 胜 —— 霜华：冰川寒玉，清冷霜锋
		"name": "霜华",
		"tier": 2,
		"cloak_outer": Color(0.10, 0.16, 0.30),   # 玄冰深蓝
		"cloak_inner": Color(0.22, 0.38, 0.58),   # 冰川青蓝
		"cloak_edge": Color(0.56, 0.86, 1.0),     # 霜华寒芒
		"eye_color": Color(0.60, 0.88, 1.0, 0.6),
		"eye_core_color": Color(0.88, 0.96, 1.0),
		"weapon_main": Color(0.92, 0.97, 1.0),
		"weapon_shadow": Color(0.64, 0.77, 0.90),
		"weapon_accent": Color(0.60, 0.90, 1.0, 0.9),
		"bone_white": Color(0.94, 0.97, 1.0),     # 骨色偏冷，霜意统一
		"bone_shadow": Color(0.71, 0.79, 0.91),
	},
	{   # 4 胜 —— 紫府：紫气东来，华贵神秘
		"name": "紫府",
		"tier": 3,
		"cloak_outer": Color(0.19, 0.10, 0.30),   # 玄紫深檀
		"cloak_inner": Color(0.38, 0.20, 0.53),   # 紫府罗缎
		"cloak_edge": Color(0.86, 0.50, 1.0),     # 紫微流光
		"eye_color": Color(0.86, 0.55, 1.0, 0.6),
		"eye_core_color": Color(0.95, 0.86, 1.0),
		"weapon_main": Color(0.95, 0.92, 1.0),
		"weapon_shadow": Color(0.70, 0.62, 0.83),
		"weapon_accent": Color(0.86, 0.55, 1.0, 0.9),
	},
	{   # 5 胜 —— 鎏金：玄衣金缕，尊荣威仪
		"name": "鎏金",
		"tier": 4,
		"cloak_outer": Color(0.16, 0.12, 0.06),   # 玄铜墨褐
		"cloak_inner": Color(0.42, 0.30, 0.10),   # 沉金暗缎
		"cloak_edge": Color(1.0, 0.80, 0.30),     # 鎏金亮边
		"eye_color": Color(1.0, 0.85, 0.35, 0.65),
		"eye_core_color": Color(1.0, 0.95, 0.70),
		"weapon_main": Color(1.0, 0.93, 0.72),    # 鎏金刃
		"weapon_shadow": Color(0.75, 0.62, 0.35),
		"weapon_accent": Color(1.0, 0.85, 0.35, 0.9),
		"bone_white": Color(0.97, 0.95, 0.88),    # 骨色微暖含金
		"bone_shadow": Color(0.80, 0.75, 0.62),
	},
	{   # 6 胜 —— 幽冥：幽夜玄袍，磷火幽幽
		"name": "幽冥",
		"tier": 5,
		"cloak_outer": Color(0.08, 0.06, 0.14),   # 幽冥玄夜
		"cloak_inner": Color(0.17, 0.12, 0.30),   # 暗魅紫
		"cloak_edge": Color(0.36, 0.95, 0.74),    # 磷火幽绿
		"eye_color": Color(0.45, 1.0, 0.74, 0.65),
		"eye_core_color": Color(0.80, 1.0, 0.90),
		"weapon_main": Color(0.86, 0.92, 0.95),
		"weapon_shadow": Color(0.55, 0.63, 0.72),
		"weapon_accent": Color(0.40, 0.95, 0.74, 0.9),
		"bone_white": Color(0.90, 0.95, 0.97),    # 骨色微染幽青
		"bone_shadow": Color(0.66, 0.75, 0.84),
	},
]

## 主题总数
static func count() -> int:
	return THEMES.size()

## 取主题（越界返回空字典）
static func get_theme(skin_idx: int) -> Dictionary:
	if skin_idx < 0 or skin_idx >= THEMES.size():
		return {}
	return THEMES[skin_idx]

## 把主题配色覆写到角色视觉配置的副本上（绝不污染原配置）
## 只动颜色字段；mask/cloak/horn/weapon 等造型样式键保持角色本相。
static func apply_to_config(base: CultivatorVisualConfig, skin_idx: int) -> CultivatorVisualConfig:
	var t := get_theme(skin_idx)
	if t.is_empty() or base == null:
		return base
	var cfg: CultivatorVisualConfig = base.duplicate(true)
	# Resource.duplicate 对 Dictionary 属性只做浅拷，显式深拷防串改
	cfg.body = base.body.duplicate()
	cfg.face = base.face.duplicate()
	cfg.cloak = base.cloak.duplicate()
	cfg.weapon = base.weapon.duplicate()
	cfg.cloak["col_outer"] = t["cloak_outer"]
	cfg.cloak["col_inner"] = t["cloak_inner"]
	cfg.cloak["col_edge"] = t["cloak_edge"]
	cfg.face["eye_color"] = t["eye_color"]
	cfg.face["eye_core_color"] = t["eye_core_color"]
	cfg.weapon["col_main"] = t["weapon_main"]
	cfg.weapon["col_shadow"] = t["weapon_shadow"]
	cfg.weapon["col_accent"] = t["weapon_accent"]
	if t.has("bone_white"):
		cfg.bone_white = t["bone_white"]
	if t.has("bone_shadow"):
		cfg.bone_shadow = t["bone_shadow"]
	cfg._sync_palette()
	return cfg
