class_name SkinData
extends RefCounted

## 角色皮肤系列表（纯静态数据，唯一真话源）
## 每角色：默认「原色」+ 6 套全员共享系列皮肤。
## 2026-10-30 皮肤系列化重构：6 套不再是「同一配色的六档亮度」，而是 6 个各有专属动效的系列
## （苍竹青玉 / 赤霄杀气 / 霜华素白 / 墨煞全黑 / 鎏金金光 / 虹霓棱镜）。
##
## 解锁判定不走本表：GameManager.is_skin_unlocked() 读该角色记录里的 best_wave 与 wave 比较。
## 皮肤只换配色 + 叠效果，不改造型样式键（面壳/斗篷款式/头饰/武器仍是角色本相）。
##
## "fx" 键只写 kind + 需要偏离默认的参数；**族默认值住在 skin_fx/ 各模块的 defaults()**，
## 这样调一个系列的手感不用碰这张共享表（并行改皮肤互不冲突）。
## 渲染器消费链：apply_to_config → config.fx → SkinFxLibrary.params() → 族模块 5 个钩子。

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
		"fx": {"kind": "jade"},
		"chip": [Color(0.20, 0.52, 0.46), Color(0.46, 0.90, 0.74), Color(0.86, 1.0, 0.92)],
		"desc": "缘边有竹节亮带自下而上推移，周身两缕青屑上浮。",
	},
	{   # 第 10 波 —— 赤霄：赤焰丹霞，杀气最重的一套
		"name": "赤霄",
		"wave": 10,
		"cloak_outer": Color(0.13, 0.04, 0.05),   # 近黑赤（杀气底）
		"cloak_inner": Color(0.42, 0.09, 0.09),   # 暗朱
		"cloak_edge": Color(0.96, 0.30, 0.16),    # 赤金锋
		"eye_color": Color(1.0, 0.26, 0.16, 0.62),
		"eye_core_color": Color(1.0, 0.74, 0.52),
		"weapon_main": Color(0.96, 0.90, 0.86),   # 暖象牙
		"weapon_shadow": Color(0.70, 0.56, 0.52),
		"weapon_accent": Color(1.0, 0.34, 0.18, 0.9),
		"bone_white": Color(0.96, 0.90, 0.86),    # 骨色偏暖压暗，与赤袍相合
		"bone_shadow": Color(0.74, 0.66, 0.63),
		"fx": {"kind": "bloodlust"},
		"chip": [Color(0.42, 0.09, 0.09), Color(0.96, 0.30, 0.16), Color(1.0, 0.74, 0.52)],
		"desc": "缘边赤光高频脉动，眼瞳转为高对比血红，周身三缕血雾下沉。",
	},
	{   # 第 15 波 —— 霜华：冰川寒玉，素白清冷
		"name": "霜华",
		"wave": 15,
		"cloak_outer": Color(0.30, 0.35, 0.42),   # 素灰白（提亮保白袍感）
		"cloak_inner": Color(0.62, 0.69, 0.78),   # 雪白
		"cloak_edge": Color(0.72, 0.92, 1.0),     # 霜华寒芒
		"eye_color": Color(0.62, 0.90, 1.0, 0.55),
		"eye_core_color": Color(0.94, 0.98, 1.0),
		"weapon_main": Color(0.95, 0.98, 1.0),
		"weapon_shadow": Color(0.70, 0.80, 0.92),
		"weapon_accent": Color(0.66, 0.92, 1.0, 0.9),
		"bone_white": Color(0.98, 0.99, 1.0),     # 骨色近纯白，霜意统一
		"bone_shadow": Color(0.78, 0.85, 0.94),
		"fx": {"kind": "snow"},
		"chip": [Color(0.62, 0.69, 0.78), Color(0.72, 0.92, 1.0), Color(0.98, 0.99, 1.0)],
		"desc": "缘边冰蓝冷光横扫，周身三枚雪晶旋转下落，骨白面壳更近纯白。",
	},
	{   # 第 25 波 —— 墨煞：全身墨黑，只留极暗冷光勾轮廓（原「紫府」让位给黑色系列）
		# 撞色规避（2026-10-30 全矩阵巡检）：与第 50 波虹霓同为墨黑底，Δ≈0.06 肉眼难分。
		# 拉开手法：墨煞走**冷墨青**（b 通道最高、明度略抬），虹霓保持**暖墨紫**（r 通道最高）。
		"name": "墨煞",
		"wave": 25,
		"cloak_outer": Color(0.038, 0.052, 0.068), # 冷墨（青调，与虹霓的暖墨紫分开）
		"cloak_inner": Color(0.082, 0.112, 0.142), # 深冷墨青
		"cloak_edge": Color(0.22, 0.46, 0.58),     # 极暗冷青（唯一勾轮廓的光）
		"eye_color": Color(0.34, 0.66, 0.82, 0.30),
		"eye_core_color": Color(0.62, 0.88, 0.98),
		"weapon_main": Color(0.30, 0.36, 0.44),    # 刃身墨铁，不反白光
		"weapon_shadow": Color(0.16, 0.20, 0.25),
		"weapon_accent": Color(0.30, 0.70, 0.86, 0.85),
		"bone_white": Color(0.72, 0.79, 0.86),     # 骨面压成冷灰，别在黑袍上发白
		"bone_shadow": Color(0.48, 0.56, 0.64),
		"fx": {"kind": "ink"},
		"chip": [Color(0.082, 0.112, 0.142), Color(0.22, 0.46, 0.58), Color(0.62, 0.88, 0.98)],
		"desc": "袍身全黑，只有一段极暗冷光沿缘边缓慢游走，周身三缕墨烟上升。",
	},
	{   # 第 35 波 —— 鎏金：玄衣金缕，金光闪闪
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
		"fx": {"kind": "gold"},
		"chip": [Color(0.42, 0.30, 0.10), Color(1.0, 0.80, 0.30), Color(1.0, 0.95, 0.70)],
		"desc": "缘边金色扫光高速游走，刃身同步闪光，周身三颗金屑上浮。",
	},
	{   # 第 50 波 —— 虹霓：墨底油膜幻彩，缘边/眼瞳/武器流光沿色环流转（棱镜系列）
		# 撞色规避（2026-10-30）：与第 25 波墨煞同为墨黑底，本系列保持**暖墨紫**（r 通道最高）拉开。
		"name": "虹霓",
		"wave": 50,
		"cloak_outer": Color(0.072, 0.045, 0.095), # 暖墨紫（低明度保黑底，色相随时间流转）
		"cloak_inner": Color(0.110, 0.078, 0.165), # 暖墨靛紫
		"cloak_edge": Color(0.38, 0.93, 1.0),      # 基准冷青（炫彩相位锚点）
		"eye_color": Color(0.42, 0.95, 1.0, 0.32),
		"eye_core_color": Color(0.80, 1.0, 1.0),
		"weapon_main": Color(0.90, 0.93, 0.99),    # 刃身近白，微带冷调
		"weapon_shadow": Color(0.52, 0.57, 0.74),
		"weapon_accent": Color(0.18, 0.98, 1.0, 0.9),
		"bone_white": Color(0.95, 0.96, 1.0),      # 骨色中性冷白，不参与虹彩
		"bone_shadow": Color(0.72, 0.76, 0.88),
		"fx": {"kind": "chroma"},                  # 参数全在 SkinFxChroma.defaults()，行为与 2026-10-22 一致
		"chip": [Color(0.35, 0.95, 1.0), Color(0.55, 0.45, 1.0), Color(1.0, 0.45, 0.85), Color(1.0, 0.80, 0.35)],
		"desc": "袍身保持墨黑，缘边、眼瞳与武器流光随时间流转虹彩。",
	},
]

## 逐角色微调表：同一套系列在 21 个角色身上撞色时在这里补丁，不用改系列配方。
## 结构 {cid: {skin_idx: {颜色键... 或 "fx": {参数...}}}}；缺省 = 直接用系列配方。
## 条目由 tests/skin_preview.gd --all 全矩阵巡检实锤撞色后补入。
const CHAR_TUNING: Dictionary = {}

## 主题总数
static func count() -> int:
	return THEMES.size()

## 取主题（越界返回空字典）
static func get_theme(skin_idx: int) -> Dictionary:
	if skin_idx < 0 or skin_idx >= THEMES.size():
		return {}
	return THEMES[skin_idx]

## 取该角色该皮肤的主题描述（解锁浮卡正文；缺省回落通用句）
static func get_desc(cid: String, skin_idx: int) -> String:
	var t := get_theme(skin_idx)
	var d := String(t.get("desc", ""))
	var tune := _tuning(cid, skin_idx)
	if tune.has("desc"):
		d = String(tune["desc"])
	return d

## 取皮肤槽底部色标条（3~4 段硬边色块）
static func get_chip(skin_idx: int) -> Array:
	var t := get_theme(skin_idx)
	return t.get("chip", [])

static func _tuning(cid: String, skin_idx: int) -> Dictionary:
	if cid.is_empty():
		return {}
	var per_char: Dictionary = CHAR_TUNING.get(cid, {})
	return per_char.get(skin_idx, {})

## 把主题配色覆写到角色视觉配置的副本上（绝不污染原配置）
## 只动颜色字段；mask/cloak/horn/weapon 等造型样式键保持角色本相。
## cid 可空：给了就叠 CHAR_TUNING 的逐角色微调（缺省不叠，保持老调用点语义）。
static func apply_to_config(base: CultivatorVisualConfig, skin_idx: int, cid: String = "") -> CultivatorVisualConfig:
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

	# 逐角色微调：可覆盖任意颜色键与 fx 子参数
	var tune := _tuning(cid, skin_idx)
	for k in tune.keys():
		var key := String(k)
		if key == "fx":
			continue
		match key:
			"cloak_outer": cfg.cloak["col_outer"] = tune[k]
			"cloak_inner": cfg.cloak["col_inner"] = tune[k]
			"cloak_edge": cfg.cloak["col_edge"] = tune[k]
			"eye_color": cfg.face["eye_color"] = tune[k]
			"eye_core_color": cfg.face["eye_core_color"] = tune[k]
			"weapon_main": cfg.weapon["col_main"] = tune[k]
			"weapon_shadow": cfg.weapon["col_shadow"] = tune[k]
			"weapon_accent": cfg.weapon["col_accent"] = tune[k]
			"bone_white": cfg.bone_white = tune[k]
			"bone_shadow": cfg.bone_shadow = tune[k]
			_: pass

	# fx 参数：主题配方 + 逐角色覆盖（族默认值在 SkinFxLibrary.params() 里再兜一层）
	var fx: Dictionary = (t.get("fx", {}) as Dictionary).duplicate(true)
	var tune_fx: Dictionary = tune.get("fx", {})
	for k in tune_fx.keys():
		fx[k] = tune_fx[k]
	cfg.fx = fx

	cfg._sync_palette()
	return cfg
