class_name WeaponData
extends RefCounted

## 武器静态数据库：所有法器的数值/行为/价格唯一定义处
## 星级：集齐 3 把同名同星，在波间商店手动合成 +1 星，伤害 ×2.0/星，冷却 ×0.92/星，最高 ★3

enum Behavior { MELEE, PROJECTILE, BURST, DRONE }

const MAX_STAR: int = 3
const MAX_SLOTS: int = 6
const MAX_STASH_SLOTS: int = 9
const STAR_DAMAGE_MULT: float = 2.0
const STAR_COOLDOWN_MULT: float = 0.92
const SELL_RATIO: float = 0.5
const STAR_SELL_MULT: float = 1.6

const DEFS: Dictionary = {
	"qingyun_sword": {
		"name": "青云剑", "behavior": Behavior.MELEE,
		"damage": 30.0, "cooldown": 1.1, "range": 150.0,
		"price": 25, "icon": "res://assets/art/weapon_sword.png",
		"desc": "近身挥斩，剑气凌厉", "tag": "近战·剑系",
		"tags": ["sword"],
	},
	"bajiao_fan": {
		"name": "芭蕉扇", "behavior": Behavior.MELEE,
		"damage": 22.0, "cooldown": 1.3, "range": 185.0,
		"price": 20, "icon": "res://assets/art/weapon_fan.png",
		"desc": "扇出宽大罡风，范围极广", "tag": "近战·广域",
		"arc_scale": 1.5,
		"tags": ["wide"],
	},
	"huoyan_fu": {
		"name": "火焰符", "behavior": Behavior.PROJECTILE,
		"damage": 20.0, "cooldown": 0.9, "range": 420.0,
		"price": 30, "icon": "res://assets/art/weapon_staff.png",
		"desc": "掷出燃烧符箓，远程单体", "tag": "远程·符箓",
		"pierce": 1,
		"tags": ["talisman"],
	},
	"liuye_feidao": {
		"name": "柳叶飞刀", "behavior": Behavior.PROJECTILE,
		"damage": 16.0, "cooldown": 1.15, "range": 440.0,
		"price": 35, "icon": "res://assets/art/weapon_dagger.png",
		"desc": "细小飞刀，可贯穿三敌", "tag": "远程·符箓",
		"pierce": 3,
		"tags": ["talisman"],
	},
	"wulei_paizi": {
		"name": "五雷法牌", "behavior": Behavior.BURST,
		"damage": 35.0, "cooldown": 1.8, "range": 380.0,
		"price": 45, "icon": "res://assets/art/weapon_thunder.png",
		"desc": "引天雷轰击目标区域", "tag": "远程·雷法",
		"burst_radius": 80.0,
		"tags": ["thunder"],
	},
	"lingdie": {
		"name": "灵蝶", "behavior": Behavior.DRONE,
		"damage": 15.0, "cooldown": 0.35, "range": 78.0,
		"price": 40, "icon": "res://assets/art/sun_orb.png",
		"desc": "灵蝶萦绕周身，触敌即伤", "tag": "环绕·御灵",
		"tags": ["spirit"],
	},
}

## 流派羁绊：同 tag 法器持有多件时激活阶梯加成（重复同名法器也计数）
const SYNERGIES: Dictionary = {
	"sword": {
		"name": "剑系", "thresholds": [2, 4, 6],
		"values": [0.15, 0.30, 0.50],
		"desc": "攻击范围 +15/30/50%",
	},
	"talisman": {
		"name": "符箓", "thresholds": [2, 4, 6],
		"values": [1, 2, 3],
		"desc": "弹丸穿透 +1/2/3",
	},
	"thunder": {
		"name": "雷法", "thresholds": [2, 4, 6],
		"values": [0.92, 0.85, 0.75],
		"desc": "施法间隔 -8/15/25%",
	},
	"spirit": {
		"name": "御灵", "thresholds": [2, 4, 6],
		"values": [15, 30, 50],
		"desc": "气血上限 +15/30/50",
	},
	"wide": {
		"name": "广域", "thresholds": [2, 4, 6],
		"values": [0.10, 0.20, 0.30],
		"desc": "法器伤害 +10/20/30%",
	},
}

## 开局三选一
const STARTER_IDS: Array = ["qingyun_sword", "huoyan_fu", "bajiao_fan"]

## 商店武器池（全部法器）
const SHOP_POOL: Array = ["qingyun_sword", "bajiao_fan", "huoyan_fu", "liuye_feidao", "wulei_paizi", "lingdie"]

## 回血丹（商店消耗品）
const POTION_ID: String = "healing_pill"
const POTION_BASE_PRICE: int = 10

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func damage_for(id: String, star: int) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0.0
	return float(def.get("damage", 10.0)) * pow(STAR_DAMAGE_MULT, float(star - 1))

static func cooldown_for(id: String, star: int) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 1.0
	return float(def.get("cooldown", 1.0)) * pow(STAR_COOLDOWN_MULT, float(star - 1))

static func sell_price(id: String, star: int) -> int:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0
	var base := int(def.get("price", 10))
	return int(ceil(float(base) * SELL_RATIO * pow(STAR_SELL_MULT, float(star - 1))))

static func star_text(star: int) -> String:
	return "★".repeat(clampi(star, 1, MAX_STAR))

static func full_name(id: String, star: int) -> String:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return "未知法器"
	return "%s %s" % [star_text(star), def.get("name", "?")]

static func tags_of(id: String) -> Array:
	return DEFS.get(id, {}).get("tags", [])
