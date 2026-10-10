class_name UpgradeData
extends RefCounted

## 加点数据库：波后悟道结算一次给 5 个候选（GameManager.UPGRADE_OFFER_COUNT），武器一律从波间商店获取
## 稀有度权重：凡品/良品/仙品基础 60/30/10，福缘每点 +1 仙品权重（从凡品中扣，见 GameBalance.rarity_weights）
## 每项设 max_stacks 上限，叠满后从池中剔除，防数值线性失控
##
## "apply" 是该项的**实际生效幅度**（唯一事实来源，文案里的 +8%/+25 必须与它一致）：
##   可加算的字段名直接写：weapon_damage_mult / armor / move_speed_mult / attack_range_mult /
##                         pickup_range_mult / hp_regen / crit_rate / crit_mult / dodge /
##                         lifesteal / luck / harvest / spirit_stones
##   特殊：attack_speed_mult_mul（乘算，地板见 GameManager.ATTACK_SPEED_FLOOR）、
##        max_hp + hp_heal（改的是玩家节点，需要 GameManager 代一手）
## 字段白名单在 GameManager.apply_upgrade()，写错会在运行时 push_warning 里暴露。

const RARITY_COLORS := {
	"common": GameStyle.RARITY_COMMON,
	"rare": GameStyle.RARITY_RARE,
	"epic": GameStyle.RARITY_EPIC,
}

const UPGRADES: Array[Dictionary] = [
	{
		"id": "atk_up",
		"apply": {"weapon_damage_mult": 0.15},
		"title": "武器强化",
		"desc": "[center]所有武器伤害提升\n• 武器总伤害 [color=#ffd24d][b]+15%[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 8,
	},
	{
		"id": "melee_up",
		"apply": {"melee_damage": 2.0},
		"title": "近战强化",
		"desc": "[center]近战伤害 [color=#ffd24d][b]+2[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_sword.png",
		"max_stacks": 10,
	},
	{
		"id": "ranged_up",
		"apply": {"ranged_damage": 2.0},
		"title": "远程强化",
		"desc": "[center]远程伤害 [color=#6fd6ff][b]+2[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_gold_sword.png",
		"max_stacks": 10,
	},
	{
		"id": "elemental_up",
		"apply": {"elemental_damage": 2.0},
		"title": "元素强化",
		"desc": "[center]元素伤害 [color=#ffd24d][b]+2[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_fire_lantern.png",
		"max_stacks": 10,
	},
	{
		"id": "engineering_up",
		"apply": {"engineering_damage": 2.0},
		"title": "召唤强化",
		"desc": "[center]召唤伤害 [color=#7ce860][b]+2[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_earth_bell.png",
		"max_stacks": 10,
	},
	{
		"id": "haste_up",
		"apply": {"attack_speed_mult_mul": 0.88},
		"title": "攻速提升",
		"desc": "[center]攻击间隔 [color=#6fd6ff][b]-12%[/b][/color][/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_haste.png",
		"max_stacks": 6,
	},
	{
		"id": "armor_up",
		"apply": {"armor": 2.0},
		"title": "护甲提升",
		"desc": "[center]护甲 [color=#7ce860][b]+2[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_armor.png",
		"max_stacks": 10,
	},
	{
		"id": "speed_up",
		"apply": {"move_speed_mult": 0.08},
		"title": "移速提升",
		"desc": "[center]移动速度 [color=#6fd6ff][b]+8%[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_boots.png",
		"max_stacks": 6,
	},
	{
		"id": "hp_up",
		"apply": {"max_hp": 25.0, "hp_heal": 30.0},
		"title": "生命提升",
		"desc": "[center]最大生命 [color=#7ce860][b]+25[/b][/color]，立即回复 [color=#7ce860][b]30[/b][/color] 点生命[/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_hp.png",
		"max_stacks": 10,
	},
	{
		"id": "pickup_up",
		"apply": {"pickup_range_mult": 0.4},
		"title": "拾取范围",
		"desc": "[center]金币拾取范围 [color=#6fd6ff][b]+40%[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_magnet.png",
		"max_stacks": 4,
	},
	{
		"id": "coins_up",
		"apply": {"spirit_stones": 12.0},
		"title": "金币补给",
		"desc": "[center]立刻获得 [color=#ffd24d][b]12[/b][/color] 枚金币[/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 99,
	},
	{
		"id": "regen_up",
		"apply": {"hp_regen": 1.2},
		"title": "生命回复",
		"desc": "[center][color=#35bfff][b]【史诗】[/b][/color] 每秒恢复 [color=#7ce860][b]1.2[/b][/color] 点生命[/center]",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_regen.png",
		"max_stacks": 6,
	},
	{
		"id": "crit_up",
		"apply": {"crit_rate": 0.08},
		"title": "暴击率",
		"desc": "[center]暴击率 [color=#ffd24d][b]+8%[/b][/color][/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 8,
	},
	{
		"id": "critdmg_up",
		"apply": {"crit_mult": 0.25},
		"title": "暴击伤害",
		"desc": "[center][color=#35bfff][b]【史诗】[/b][/color] 暴击伤害 [color=#ffd24d][b]+25%[/b][/color][/center]",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 6,
	},
	{
		"id": "dodge_up",
		"apply": {"dodge": 0.07},
		"title": "闪避率",
		"desc": "[center]闪避率 [color=#6fd6ff][b]+7%[/b][/color]（上限60%）[/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_boots.png",
		"max_stacks": 8,
	},
	{
		"id": "lifesteal_up",
		"apply": {"lifesteal": 0.04},
		"title": "吸血",
		"desc": "[center][color=#35bfff][b]【史诗】[/b][/color] 命中 [color=#7ce860][b]+4%[/b][/color] 概率吸取1点生命（每秒最多3次）[/center]",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_regen.png",
		"max_stacks": 6,
	},
	{
		"id": "luck_up",
		"apply": {"luck": 6.0},
		"title": "幸运提升",
		"desc": "[center]幸运 [color=#ffd24d][b]+6[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 8,
	},
	{
		"id": "harvest_up",
		"apply": {"harvest": 8.0},
		"title": "收益提升",
		"desc": "[center]收益 [color=#ffd24d][b]+8[/b][/color]（每波结束白得金币与经验）[/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 8,
	},
	{
		"id": "range_up",
		"apply": {"attack_range_mult": 0.12},
		"title": "攻击范围",
		"desc": "[center]攻击范围 [color=#6fd6ff][b]+12%[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_magnet.png",
		"max_stacks": 5,
	},
	{
		"id": "knockback_up",
		"apply": {"knockback_mult": 0.25},
		"title": "击退提升",
		"desc": "[center]武器击退力度 [color=#6fd6ff][b]+25%[/b][/color][/center]",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/item_leiyin_zhen.png",
		"max_stacks": 4,
	},
	{
		"id": "insight_up",
		"apply": {"xp_gain_mult": 0.15},
		"title": "经验加成",
		"desc": "[center]经验获取 [color=#ffd24d][b]+15%[/b][/color][/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_wujian_shi.png",
		"max_stacks": 4,
	},
	{
		"id": "tongxuan_up",
		"apply": {"free_rerolls": 1.0},
		"title": "免费重掷",
		"desc": "[center]每波免费重掷商店 [color=#ffd24d][b]+1[/b][/color] 次[/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_tongxuan_ling.png",
		"max_stacks": 2,
	},
	{
		"id": "elite_up",
		"apply": {"elite_damage": 0.25},
		"title": "精英伤害",
		"desc": "[center]对精英与Boss伤害 [color=#ffd24d][b]+25%[/b][/color][/center]",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_pojia_zhui.png",
		"max_stacks": 4,
	},
	{
		"id": "wuxing_up",
		"apply": {"element_damage_all": 0.06},
		"title": "全元素强化",
		"desc": "[center][color=#35bfff][b]【史诗】[/b][/color] 金木水火土全元素伤害 [color=#ffd24d][b]+6%[/b][/color][/center]",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/item_wuxing_pei.png",
		"max_stacks": 5,
	},
]

## 稀有度加权抽取：过滤叠满项与角色锁死项，福缘提升仙品权重。
## 纯函数：一切上下文由 ctx 传入（luck / locked_upgrades / counts / rng），不读 GameManager 单例，
## 因此可以在不启动场景、不建 autoload 的情况下被单元测试直接断言。
## ctx 约定：
##   luck: float                 福缘
##   locked_upgrades: Array      角色锁死的加点 id
##   counts: Dictionary          已领悟次数 {id: int}
##   rng: RandomNumberGenerator  随机源；缺省时用全局 randf()（单测里务必传入固定种子）
static func get_random_upgrades(count: int = 3, ctx: Dictionary = {}) -> Array[Dictionary]:
	var luck: float = float(ctx.get("luck", 0.0))
	var locked: Array = ctx.get("locked_upgrades", [])
	var owned_counts: Dictionary = ctx.get("counts", {})
	var rng: RandomNumberGenerator = ctx.get("rng", null)

	var weights := GameBalance.rarity_weights(luck)
	var epic_w: float = weights["epic"]
	var rare_w: float = weights["rare"]
	var common_w: float = weights["common"]

	var pool: Array = []
	var pool_weights: Array = []
	for u in UPGRADES:
		var uid: String = u.get("id", "")
		if uid in locked:
			continue
		if int(owned_counts.get(uid, 0)) >= int(u.get("max_stacks", 99)):
			continue
		var w: float = common_w
		match u.get("rarity", "common"):
			"rare":
				w = rare_w
			"epic":
				w = epic_w
		pool.append(u)
		pool_weights.append(w)

	var result: Array[Dictionary] = []
	var active_rng: RandomNumberGenerator = rng if rng != null else GameManager.rng
	for i in range(count):
		if pool.is_empty():
			break
		var roll: float = active_rng.randf()
		var chosen: int = GameBalance.weighted_pick_index(pool_weights, roll)
		var picked: Dictionary = pool[chosen].duplicate()
		picked["border_color"] = RARITY_COLORS.get(picked.get("rarity", "common"), Color.WHITE)
		result.append(picked)
		pool.remove_at(chosen)
		pool_weights.remove_at(chosen)
	return result

static func get_upgrade_def(upgrade_id: String) -> Dictionary:
	for u in UPGRADES:
		if u.get("id", "") == upgrade_id:
			var copy: Dictionary = u.duplicate()
			copy["border_color"] = RARITY_COLORS.get(copy.get("rarity", "common"), Color.WHITE)
			return copy
	return {}
