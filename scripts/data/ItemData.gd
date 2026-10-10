class_name ItemData
extends RefCounted

## 法宝（被动道具）数据库：独立于法器的被动物品，买即生效、无限持有、无栏位限制
## 档位 tier 1~4（凡品/良品/仙品/传说，仿土豆兄弟道具档位）：决定基准价与出现权重，
## 档位解锁波次与权重公式在 GameBalance.item_tier_weights，定价在 GameBalance.item_price。
##
## apply 复用加点字段白名单（GameBalance.upgrade_fields()），由 GameManager._apply_stat_fields 统一落地，
## 与悟道加点共用同一条属性链路——文案里的数值必须与 apply 同源一致。
## 独特机制走额外字段（由对应系统消费，不进 apply）：
##   wave_heal_pct —— 波末按气血上限百分比回血（GameManager.apply_harvest 结算）
##   revive        —— 致死一击时消耗本法宝免死并回半血（GameManager.try_revive）
## unique: true 时每局限购一件，买后即从货架池剔除

const TIER_LABELS := {1: "普通", 2: "稀有", 3: "史诗", 4: "传说"}
const TIER_COLORS := {
	1: GameStyle.RARITY_COMMON,
	2: GameStyle.RARITY_RARE,
	3: GameStyle.RARITY_EPIC,
	4: GameStyle.RARITY_LEGEND,
}

const DEFS: Dictionary = {
	# ==================== 凡品（tier 1 · 第 1 波起） ====================
	"jubaopen": {
		"name": "储蓄罐", "tier": 1, "price": 14,
		"icon": "res://assets/art/item_jubaopen.png",
		"desc": "每波结束白得金币与经验\n收益 +6",
		"apply": {"harvest": 6.0},
	},
	"mibao_luopan": {
		"name": "寻宝罗盘", "tier": 1, "price": 12,
		"icon": "res://assets/art/item_mibao_luopan.png",
		"desc": "幸运 +5（高稀有度升级与道具更易出现）",
		"apply": {"luck": 5.0},
	},
	"qiankun_dai": {
		"name": "拾取袋", "tier": 1, "price": 12,
		"icon": "res://assets/art/item_qiankun_dai.png",
		"desc": "金币拾取范围 +30%",
		"apply": {"pickup_range_mult": 0.3},
	},
		"jifeng_xue": {
			"name": "速跑靴", "tier": 1, "price": 13,
			"icon": "res://assets/art/item_jifeng_xue.png",
			"desc": "移动速度 +7%",
			"apply": {"move_speed_mult": 0.07},
		},
		"qingxin_cha": {
			"name": "速攻药", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_qingxin_cha.png",
			"desc": "攻击间隔 -8%",
			"apply": {"attack_speed_mult_mul": 0.92},
		},

		# ==================== 良品（tier 2 · 第 4 波起） ====================
	"zhekou_yufu": {
		"name": "折扣券", "tier": 2, "price": 26,
		"icon": "res://assets/art/item_zhekou_yufu.png",
		"desc": "商店物价 -8%（可叠加）",
		"apply": {"shop_price_mul": 0.92},
	},
	"kuangxue_dan": {
		"name": "狂暴药", "tier": 2, "price": 24,
		"icon": "res://assets/art/item_kuangxue_dan.png",
		"desc": "武器伤害 +18%，但护甲 -2",
		"apply": {"weapon_damage_mult": 0.18, "armor": -2.0},
	},
	"guijia_fu": {
		"name": "龟甲", "tier": 2, "price": 24,
		"icon": "res://assets/art/item_guijia_fu.png",
		"desc": "护甲 +4，但移速 -6%",
		"apply": {"armor": 4.0, "move_speed_mult": -0.06},
	},
	"tongxuan_ling": {
		"name": "重掷令", "tier": 2, "price": 22,
		"icon": "res://assets/art/item_tongxuan_ling.png",
		"desc": "每波免费重掷商店 +1 次",
		"apply": {"free_rerolls": 1.0},
	},
		"leiyin_zhen": {
			"name": "雷击针", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_leiyin_zhen.png",
			"desc": "武器击退力度 +35%",
			"apply": {"knockback_mult": 0.35},
		},
		"yinhun_deng": {
			"name": "引路灯", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_yinhun_deng.png",
			"desc": "金币拾取范围 +25%，攻击范围 +15%",
			"apply": {"pickup_range_mult": 0.25, "attack_range_mult": 0.15},
		},
		"suoling_jia": {
			"name": "狂战枷", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_suoling_jia.png",
			"desc": "武器伤害 +22%，但移速 -6%",
			"apply": {"weapon_damage_mult": 0.22, "move_speed_mult": -0.06},
		},

		# ==================== 仙品（tier 3 · 第 9 波起） ====================
		"wuxing_pei": {
			"name": "五行石", "tier": 3, "price": 45,
			"icon": "res://assets/art/item_wuxing_pei.png",
			"desc": "金木水火土全元素伤害 +6%",
			"apply": {"element_damage_all": 0.06},
		},
		"wujian_shi": {
			"name": "经验石", "tier": 3, "price": 42,
			"icon": "res://assets/art/item_wujian_shi.png",
			"desc": "经验获取 +12%",
			"apply": {"xp_gain_mult": 0.12},
		},
		"huichun_hulu": {
			"name": "回复葫芦", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_huichun_hulu.png",
			"desc": "生命回复 +0.5/秒，每波结束恢复15%生命",
			"apply": {"hp_regen": 0.5},
			"wave_heal_pct": 0.15,
		},
		"pojia_zhui": {
			"name": "破甲针", "tier": 3, "price": 40,
			"icon": "res://assets/art/item_pojia_zhui.png",
			"desc": "对精英与Boss伤害 +25%",
			"apply": {"elite_damage": 0.25},
		},
		"xiuluo_pei": {
			"name": "嗜血石", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_xiuluo_pei.png",
			"desc": "吸血 +4%，武器伤害 +12%，但护甲 -1",
			"apply": {"lifesteal": 0.04, "weapon_damage_mult": 0.12, "armor": -1.0},
		},

		# ==================== 传说（tier 4 · 第 14 波起） ====================
		"tisi_kuilei": {
			"name": "替身娃娃", "tier": 4, "price": 90,
			"icon": "res://assets/art/item_tisi_kuilei.png",
			"desc": "致死一击时娃娃碎裂：免死并恢复50%生命\n（每局限购一件，一次性消耗）",
			"apply": {},
			"revive": true,
			"unique": true,
		},
		"hunyuan_zhu": {
			"name": "万能珠", "tier": 4, "price": 85,
			"icon": "res://assets/art/item_hunyuan_zhu.png",
			"desc": "幸运 +8，收益 +8",
			"apply": {"luck": 8.0, "harvest": 8.0},
		},
		"taiyi_jindan": {
			"name": "极效药丸", "tier": 4, "price": 88,
			"icon": "res://assets/art/item_taiyi_jindan.png",
			"desc": "最大生命 +25 并回满，伤害 +15%，护甲 +2，移速 +5%",
			"apply": {"max_hp": 25.0, "hp_heal": 25.0, "weapon_damage_mult": 0.15, "armor": 2.0, "move_speed_mult": 0.05},
		},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

static func tier_label(tier: int) -> String:
	return TIER_LABELS.get(clampi(tier, 1, 4), "普通")

static func tier_color(tier: int) -> Color:
	return TIER_COLORS.get(clampi(tier, 1, 4), TIER_COLORS[1])

## 抽一件法宝上货架：按档位权重抽取（公式见 GameBalance.item_tier_weights），
## 已持有的 unique 法宝从池中剔除；若传入 unlocked_items，则未解锁法宝不入池；池空返回 ""，调用方落回法器位
static func pick_id(luck: float, wave: int, owned: Array, rng: RandomNumberGenerator, unlocked_items: Array = []) -> String:
	var tier_w: Array = GameBalance.item_tier_weights(luck, wave)
	var pool: Array = []
	var weights: Array = []
	for id in DEFS.keys():
		if not unlocked_items.is_empty() and not (id in unlocked_items):
			continue
		var d: Dictionary = DEFS[id]
		if bool(d.get("unique", false)) and id in owned:
			continue
		var tier := clampi(int(d.get("tier", 1)), 1, 4)
		var w := float(tier_w[tier - 1])
		if w <= 0.0:
			continue
		pool.append(id)
		weights.append(w)
	if pool.is_empty():
		return ""
	var active_rng: RandomNumberGenerator = rng if rng != null else GameManager.rng
	var roll: float = active_rng.randf()
	return String(pool[GameBalance.weighted_pick_index(weights, roll)])
