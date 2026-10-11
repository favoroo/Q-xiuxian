class_name UpgradeData
extends RefCounted

## 加点数据库：波后悟道结算一次给 5 个候选（GameManager.UPGRADE_OFFER_COUNT），武器一律从波间商店获取
## 稀有度权重：凡品/良品/仙品基础 60/30/10，福缘每点 +1 仙品权重（从凡品中扣，见 GameBalance.rarity_weights）
## 每项设 max_stacks 上限，叠满后从池中剔除，防数值线性失控
##
## "apply" 是该项的**实际生效幅度**（唯一事实来源）：悟道卡面的加成行由 BonusRows 从 apply
## 直接生成（正绿负红、名左值右），desc 只写 apply 之外的机制说明、不再手抄数值：
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
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 8,
	},
	{
		"id": "melee_up",
		"apply": {"melee_damage": 2.0},
		"title": "近战强化",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_sword.png",
		"max_stacks": 10,
	},
	{
		"id": "ranged_up",
		"apply": {"ranged_damage": 2.0},
		"title": "远程强化",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_gold_sword.png",
		"max_stacks": 10,
	},
	{
		"id": "elemental_up",
		"apply": {"elemental_damage": 2.0},
		"title": "元素强化",
		"desc": "并提升灼烧、中毒等持续伤害",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_fire_lantern.png",
		"max_stacks": 10,
	},
	{
		"id": "engineering_up",
		"apply": {"engineering_damage": 2.0},
		"title": "召唤强化",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/weapon_earth_bell.png",
		"max_stacks": 10,
	},
	{
		"id": "haste_up",
		"apply": {"attack_speed_mult_mul": 0.88},
		"title": "攻速提升",
		"desc": "",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_haste.png",
		"max_stacks": 6,
	},
	{
		"id": "armor_up",
		"apply": {"armor": 2.0},
		"title": "护甲提升",
		"desc": "按百分比减免每次受击伤害",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_armor.png",
		"max_stacks": 10,
	},
	{
		"id": "speed_up",
		"apply": {"move_speed_mult": 0.08},
		"title": "移速提升",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_boots.png",
		"max_stacks": 6,
	},
	{
		"id": "hp_up",
		"apply": {"max_hp": 25.0, "hp_heal": 30.0},
		"title": "生命提升",
		"desc": "",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_hp.png",
		"max_stacks": 10,
	},
	{
		"id": "pickup_up",
		"apply": {"pickup_range_mult": 0.4},
		"title": "拾取范围",
		"desc": "金币与经验的吸附范围",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_magnet.png",
		"max_stacks": 4,
	},
	{
		"id": "coins_up",
		"apply": {"spirit_stones": 12.0},
		"title": "金币补给",
		"desc": "波间灵石阁购物使用",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 99,
	},
	{
		"id": "regen_up",
		"apply": {"hp_regen": 1.2},
		"title": "生命回复",
		"desc": "每秒持续回复生命",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_regen.png",
		"max_stacks": 6,
	},
	{
		"id": "crit_up",
		"apply": {"crit_rate": 0.08},
		"title": "暴击率",
		"desc": "暴击概率上限 75%",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_crit.png",
		"max_stacks": 8,
	},
	{
		"id": "critdmg_up",
		"apply": {"crit_mult": 0.25},
		"title": "暴击伤害",
		"desc": "打出暴击时伤害额外提升",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_critdmg.png",
		"max_stacks": 6,
	},
	{
		"id": "dodge_up",
		"apply": {"dodge": 0.07},
		"title": "闪避率",
		"desc": "闪避率上限 60%",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_dodge.png",
		"max_stacks": 8,
	},
	{
		"id": "lifesteal_up",
		"apply": {"lifesteal": 0.04},
		"title": "吸血",
		"desc": "命中时吸取 1 点生命（每秒最多 3 次）",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_lifesteal.png",
		"max_stacks": 6,
	},
	{
		"id": "luck_up",
		"apply": {"luck": 6.0},
		"title": "幸运提升",
		"desc": "高稀有升级与道具更易出现",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_luck.png",
		"max_stacks": 8,
	},
	{
		"id": "harvest_up",
		"apply": {"harvest": 8.0},
		"title": "收益提升",
		"desc": "每波结束白得金币与经验",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_harvest.png",
		"max_stacks": 8,
	},
	{
		"id": "range_up",
		"apply": {"attack_range_mult": 0.12},
		"title": "攻击范围",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_range.png",
		"max_stacks": 5,
	},
	{
		"id": "knockback_up",
		"apply": {"knockback_mult": 0.25},
		"title": "击退提升",
		"desc": "击中时把敌人推得更远",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/item_leiyin_zhen.png",
		"max_stacks": 4,
	},
	{
		"id": "insight_up",
		"apply": {"xp_gain_mult": 0.15},
		"title": "经验加成",
		"desc": "吸收经验光球获得更多经验",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_wujian_shi.png",
		"max_stacks": 4,
	},
	{
		"id": "tongxuan_up",
		"apply": {"free_rerolls": 1.0},
		"title": "免费重掷",
		"desc": "波间灵石阁免费重掷次数",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_tongxuan_ling.png",
		"max_stacks": 2,
	},
	{
		"id": "elite_up",
		"apply": {"elite_damage": 0.25},
		"title": "精英伤害",
		"desc": "仅对精英与首领生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_pojia_zhui.png",
		"max_stacks": 4,
	},
	{
		"id": "wuxing_up",
		"apply": {"element_damage_all": 0.06},
		"title": "全元素强化",
		"desc": "提升全系武器的元素伤害",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/item_wuxing_pei.png",
		"max_stacks": 5,
	},
	# 2026-10-10 新增：单元素专精加点，与同名单元素法宝（金精石等）构成专精流双链路
	{
		"id": "metal_up",
		"apply": {"element_damage_metal": 0.10},
		"title": "锐金真解",
		"desc": "仅对金系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_jinjing_shi.png",
		"max_stacks": 4,
	},
	{
		"id": "wood_up",
		"apply": {"element_damage_wood": 0.10},
		"title": "青木真解",
		"desc": "仅对木系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_chenxiang_mu.png",
		"max_stacks": 4,
	},
	{
		"id": "water_up",
		"apply": {"element_damage_water": 0.10},
		"title": "玄水真解",
		"desc": "仅对水系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_hantan_yu.png",
		"max_stacks": 4,
	},
	{
		"id": "fire_up",
		"apply": {"element_damage_fire": 0.10},
		"title": "离火真解",
		"desc": "仅对火系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_dihuo_jing.png",
		"max_stacks": 4,
	},
	{
		"id": "earth_up",
		"apply": {"element_damage_earth": 0.10},
		"title": "厚土真解",
		"desc": "仅对土系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/item_houtu_he.png",
		"max_stacks": 4,
	},

	# 2026-10-10 新增：穿透与反伤体系 + 史诗级高阶加点（打破低阶上限）
	{
		"id": "pierce_up",
		"apply": {"bonus_pierce": 1.0},
		"title": "破甲透劲",
		"desc": "弹丸可多穿透 1 名敌人（近战不生效）",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/icon_pierce.png",
		"max_stacks": 2,
	},
	{
		"id": "thorns_up",
		"apply": {"thorns": 0.35},
		"title": "护体罡气",
		"desc": "受到近身碰撞时反震",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/icon_thorns.png",
		"max_stacks": 6,
	},
	{
		"id": "grand_thorns",
		"apply": {"thorns": 0.70, "armor": 2.0},
		"title": "九幽逆鳞",
		"desc": "受到近身碰撞时反震",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_thorns.png",
		"max_stacks": 3,
	},
	{
		"id": "grand_melee",
		"apply": {"melee_damage": 6.0},
		"title": "气冲霄汉",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/weapon_sword.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_ranged",
		"apply": {"ranged_damage": 6.0},
		"title": "百步穿杨",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/weapon_gold_sword.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_elemental",
		"apply": {"elemental_damage": 6.0},
		"title": "万法归宗",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/weapon_fire_lantern.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_engineering",
		"apply": {"engineering_damage": 6.0, "max_hp": 15.0, "hp_heal": 15.0},
		"title": "万灵朝元",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/weapon_earth_bell.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_haste",
		"apply": {"attack_speed_mult_mul": 0.82},
		"title": "雷厉风行",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/icon_haste.png",
		"max_stacks": 3,
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
