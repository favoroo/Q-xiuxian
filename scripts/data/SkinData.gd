class_name SkinData
extends RefCounted

## 角色换色皮肤主题表（纯静态数据，唯一真话源）
## 每角色：默认「原色」+ 6 套全员共享主题皮肤（第 6 套「虹霓」为动态炫彩）。
## 2026-10-28 无限闯关改造：tier 改为 wave —— 解锁看「该角色单局抵达过的最高波数」，
## 不再看通关次数（20 波只是破境波而非终点，攒通关次数的路子已失效）。
## 解锁判定不走本表：GameManager.is_skin_unlocked() 读该角色记录里的 best_wave 与 wave 比较。
## 皮肤只换配色（斗篷内/外/缘拼色 + 眼色 + 武器色 + 骨色微调），不改造型样式键。
## 炫彩主题额外带 "chroma" 参数：渲染器按时间沿色环流转缘边/眼瞳/武器流光，袍面保持黑底只叠油膜虹彩。

## 主题数组下标即 skin_idx（0~5）；wave = 解锁所需的该角色最高抵达波数（5 / 10 / 15 / 25 / 35 / 50）
const THEMES: Array[Dictionary] = [
	{   # 第 5 波 —— 苍竹：青玉竹影，偏青的碧色与剑士本相墨绿拉开区分
		"name": "苍竹",
		"wave": 5,
		"cloak_outer": Color(0.07, 0.22, 0.21),   # 沉潭青
		"cloak_inner": Color(0.14, 0.42, 0.38),   # 青玉碧
		"cloak_edge": Color(0.46, 0.90, 0.74),    # 新竹翠芒
		"eye_color": Color(0.50, 0.95, 0.72, 0.55),
		"eye_core_color": Color(0.86, 1.0, 0.92),
		"weapon_main": Color(0.92, 0.97, 0.93),
		"weapon_shadow": Color(0.58, 0.75, 0.66),
		"weapon_accent": Color(0.48, 0.94, 0.70, 0.9),
	},
	{   # 第 10 波 —— 赤霄：赤焰丹霞，暖意金边
		"name": "赤霄",
		"wave": 10,
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
	{   # 第 15 波 —— 霜华：冰川寒玉，清冷霜锋
		"name": "霜华",
		"wave": 15,
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
	{   # 第 25 波 —— 紫府：紫气东来，华贵神秘
		"name": "紫府",
		"wave": 25,
		"cloak_outer": Color(0.19, 0.10, 0.30),   # 玄紫深檀
		"cloak_inner": Color(0.38, 0.20, 0.53),   # 紫府罗缎
		"cloak_edge": Color(0.86, 0.50, 1.0),     # 紫微流光
		"eye_color": Color(0.86, 0.55, 1.0, 0.6),
		"eye_core_color": Color(0.95, 0.86, 1.0),
		"weapon_main": Color(0.95, 0.92, 1.0),
		"weapon_shadow": Color(0.70, 0.62, 0.83),
		"weapon_accent": Color(0.86, 0.55, 1.0, 0.9),
	},
	{   # 第 35 波 —— 鎏金：玄衣金缕，尊荣威仪
		"name": "鎏金",
		"wave": 35,
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
	{   # 第 50 波 —— 虹霓：墨底油膜幻彩，缘边/眼瞳/武器流光沿色环流转（炫彩皮肤）
		"name": "虹霓",
		"wave": 50,
		"cloak_outer": Color(0.063, 0.045, 0.100), # 墨底玄紫（低明度保黑底，色相随时间流转）
		"cloak_inner": Color(0.092, 0.085, 0.170), # 墨底靛青
		"cloak_edge": Color(0.38, 0.93, 1.0),      # 基准冷青（炫彩相位锚点）
		"eye_color": Color(0.42, 0.95, 1.0, 0.32),
		"eye_core_color": Color(0.80, 1.0, 1.0),
		"weapon_main": Color(0.90, 0.93, 0.99),    # 刃身近白，微带冷调
		"weapon_shadow": Color(0.52, 0.57, 0.74),
		"weapon_accent": Color(0.18, 0.98, 1.0, 0.9),
		"bone_white": Color(0.95, 0.96, 1.0),      # 骨色中性冷白，不参与虹彩
		"bone_shadow": Color(0.72, 0.76, 0.88),
		"chroma": {                                # 炫彩动画参数（渲染器消费）
			"cycle": 7.0,                          # 色相绕行一圈的秒数
			"hue_offsets": {                       # 各部位相对相位（圈，错开成棱镜散彩）
				"cloak_outer": 0.0,
				"cloak_inner": 0.0,
				"cloak_edge": 0.0,
				"eye_glow": 0.06,
				"eye_core": 0.02,
				"weapon_main": 0.22,
				"weapon_shadow": 0.16,
				"weapon_accent": 0.30,
				"slash_arc": 0.10,
				"gold": 0.34,
				"jade": 0.12,
				"tassel": 0.40,
			},
			"locked": ["cloak_outer", "cloak_inner"],  # 袍身色相锁死（黑底不跑色，虹彩交给油膜 sheen）
			"sheen": 0.075,                        # 袍面油膜虹彩混入强度（低=保黑底高级感）
			"sheen_dx": 0.010,                     # 油膜带沿衣褶的横向色相梯度
			"sheen_dy": 0.015,                     # 纵向色相梯度（斜向油膜纹）
			"rim_glow": 0.50,                      # 缘边常驻流光强度（无需技能也持续游走）
		},
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
	if t.has("chroma"):
		cfg.chroma = (t["chroma"] as Dictionary).duplicate(true)
	else:
		# 显式清空：duplicate(true) 会带出 base 的 chroma，若不覆盖，
		# 同一配置先套炫彩再套普通主题会残留动画参数
		cfg.chroma = {}
	cfg._sync_palette()
	return cfg
