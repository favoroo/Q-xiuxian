class_name CultivatorData
extends RefCounted

## 修士流派数据库：不对称设计——每名修士都是「超能力 + 严苛负面代偿」
## mods 支持的键：
##   crit_rate / armor / harvest / thorns       —— 直接加算
##   speed_mult / damage_mult / hp_mult / shop_price —— 乘算系数
##   tag_damage: {tag: bonus}                   —— 指定流派法器伤害加成
##   non_drone_damage                           —— 非灵蝶法器伤害修正（负值为惩罚）
##   start_drones                               —— 开局自带灵蝶数
##   spirit_threshold_adj                       —— 御灵羁绊门槛下移
## allowed_tags: 非空时商店只刷这些流派的法器；locked_upgrades: 锁死的加点项

const DEFS: Dictionary = {
	"jianchi": {
		"name": "剑痴·独孤",
		"epithet": "一人一剑，不问苍生",
		"icon": "res://assets/art/weapon_sword.png",
		"pros": ["剑系法器伤害 +60%", "暴击率 +15%"],
		"cons": ["此生只执剑：商店不出其他流派法器"],
		"mods": {
			"crit_rate": 0.15,
			"tag_damage": {"sword": 0.6},
		},
		"allowed_tags": ["sword"],
		"locked_upgrades": [],
	},
	"shiyue": {
		"name": "石岳·体修",
		"epithet": "肉身成圣，岿然如山",
		"icon": "res://assets/art/icon_armor.png",
		"pros": ["气血上限 ×1.8", "护甲 +5", "受击反震等同敌方攻击力的伤害"],
		"cons": ["无法领悟神行符（移速锁死）", "基础移速 -15%"],
		"mods": {
			"hp_mult": 1.8,
			"armor": 5.0,
			"thorns": 1.0,
			"speed_mult": 0.85,
		},
		"allowed_tags": [],
		"locked_upgrades": ["speed_up"],
	},
	"fuzhen": {
		"name": "符阵灵童",
		"epithet": "御灵驱蝶，以众凌寡",
		"icon": "res://assets/art/sun_orb.png",
		"pros": ["开局自带 2 只灵蝶", "御灵羁绊门槛 -1"],
		"cons": ["非灵蝶法器伤害 -30%"],
		"mods": {
			"start_drones": 2,
			"spirit_threshold_adj": 1,
			"non_drone_damage": -0.3,
		},
		"allowed_tags": [],
		"locked_upgrades": [],
	},
	"jinsuanpan": {
		"name": "散修·金算盘",
		"epithet": "灵田生金，以利证道",
		"icon": "res://assets/art/icon_coin.png",
		"pros": ["灵韵 +16 起步（波末白得灵石）", "灵石阁全场八折"],
		"cons": ["法器伤害 -25%", "气血上限 -25%"],
		"mods": {
			"harvest": 16.0,
			"shop_price": 0.8,
			"damage_mult": 0.75,
			"hp_mult": 0.75,
		},
		"allowed_tags": [],
		"locked_upgrades": [],
	},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()
