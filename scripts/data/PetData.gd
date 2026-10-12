class_name PetData
extends RefCounted

## 灵兽（随行伙伴）数据库：商店购买、永久随行、圆球光灵形象
## 获取渠道：灵石阁货架（offer kind: "pet"）
## 规则：每种灵兽同时限持一只，出售后可再次在商店刷出。
## 普通角色默认上限 1 只，御兽师默认上限 3 只。

const SELL_RATIO: float = 0.5  ## 出售回收比例（对齐 WeaponData.SELL_RATIO）

const ROLES := {
	"attack": "攻击",
	"defense": "防御",
	"support": "辅助",
	"economy": "经济",
	"control": "控制",
}

## 7 种灵兽定义
## role: attack / defense / support / economy / control
## base_price: 商店 1 波基准买价
## base_cooldown: 基础行为周期（秒）
## color: 主体光灵核心色（GameStyle 兼容风格）
## halo_color: 外晕颜色
## decor: 特征部件类型（fox_ears_tail / bird_crest_beak / turtle_shell / deer_horns / toad_coin / mink_tail / ape_brows）
const DEFS: Dictionary = {
	"yanhu": {
		"id": "yanhu",
		"name": "焰灵狐",
		"role": "attack",
		"base_price": 38,
		"base_cooldown": 2.2,
		"base_value": 18.0,  ## 基础火丹伤害
		"desc": "每 2.2 秒向最近敌人发射追踪火丹",
		"color": Color(0.98, 0.42, 0.16),      # 橙红
		"halo_color": Color(1.0, 0.55, 0.2, 0.35),
		"decor": "fox_ears_tail",
	},
	"leique": {
		"id": "leique",
		"name": "雷灵雀",
		"role": "attack",
		"base_price": 42,
		"base_cooldown": 3.0,
		"base_value": 36.0,  ## 单发高伤雷击
		"desc": "每 3.0 秒雷击最近敌人（单发高伤）",
		"color": Color(0.55, 0.45, 0.98),      # 蓝紫
		"halo_color": Color(0.68, 0.58, 1.0, 0.35),
		"decor": "bird_crest_beak",
	},
	"xuangui": {
		"id": "xuangui",
		"name": "玄甲龟",
		"role": "defense",
		"base_price": 46,
		"base_cooldown": 1.6,
		"base_value": 95.0,  ## 拦截半径 px
		"desc": "每 1.6 秒拦截周身 95px 内一发敌方飞行物",
		"color": Color(0.24, 0.62, 0.68),      # 青黛
		"halo_color": Color(0.35, 0.75, 0.82, 0.35),
		"decor": "turtle_shell",
	},
	"yulu": {
		"id": "yulu",
		"name": "玉露鹿",
		"role": "support",
		"base_price": 40,
		"base_cooldown": 2.0,
		"base_value": 0.012, ## 每跳回复 1.2% 最大生命
		"desc": "每 2.0 秒为主角回复 1.2% 最大生命",
		"color": Color(0.35, 0.85, 0.55),      # 玉绿
		"halo_color": Color(0.48, 0.95, 0.65, 0.35),
		"decor": "deer_horns",
	},
	"juchan": {
		"id": "juchan",
		"name": "聚宝蟾",
		"role": "economy",
		"base_price": 36,
		"base_cooldown": 0.0, ## 波末触发
		"base_value": 8.0,   ## 每波基准产出金币
		"desc": "每波结束献上金币（随波次成长）",
		"color": Color(0.96, 0.82, 0.22),      # 金黄
		"halo_color": Color(1.0, 0.88, 0.35, 0.4),
		"decor": "toad_coin",
	},
	"fengdiao": {
		"id": "fengdiao",
		"name": "灵风貂",
		"role": "support",
		"base_price": 34,
		"base_cooldown": 7.0,
		"base_value": 220.0, ## 磁吸半径 px
		"desc": "每 7 秒将周围 220px 内灵髓与回复珠吸附过来",
		"color": Color(0.85, 0.88, 0.95),      # 月白
		"halo_color": Color(0.92, 0.94, 1.0, 0.35),
		"decor": "mink_tail",
	},
	"shiyuan": {
		"id": "shiyuan",
		"name": "磐石猿",
		"role": "control",
		"base_price": 38,
		"base_cooldown": 5.0,
		"base_value": 110.0, ## 震退半径 px，伤害为基础 12.0
		"desc": "每 5 秒震退 110px 内敌人并造成伤害",
		"color": Color(0.65, 0.58, 0.52),      # 岩灰
		"halo_color": Color(0.78, 0.72, 0.66, 0.35),
		"decor": "ape_brows",
	},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

static func exists(id: String) -> bool:
	return DEFS.has(id)

static func role_label(role: String) -> String:
	return String(ROLES.get(role, "灵兽"))

## 出售回收价：基准买价 × 0.5（对齐武器出售）
static func sell_price(id: String) -> int:
	var def: Dictionary = get_def(id)
	if def.is_empty():
		return 0
	var base := int(def.get("base_price", 30))
	return maxi(1, int(ceil(float(base) * SELL_RATIO)))

## 商店候选抽取：从未拥有的灵兽池中等概率抽取 1 只，抽空返回 ""
static func pick_id(owned: Array, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for id in all_ids():
		if id not in owned:
			pool.append(id)
	if pool.is_empty():
		return ""
	if pool.size() == 1:
		return String(pool[0])
	var idx := rng.randi() % pool.size()
	return String(pool[idx])
