class_name WeaponData
extends RefCounted

## 武器静态数据库：所有法器的数值/行为/价格/五行/属性受益唯一定义处
## 星级：集齐 3 把同名同星，在波间商店手动合成 +1 星，伤害 ×2.0/星，冷却 ×0.92/星，最高 ★3
## 双标签系统：器类（剑系/符箓/雷法/御灵/广域）+ 五行（锐金/青木/玄水/离火/厚土）

enum Behavior { MELEE, PROJECTILE, BURST, DRONE }

const MAX_STAR: int = 3
const MAX_SLOTS: int = 6
const MAX_STASH_SLOTS: int = 9
const STAR_DAMAGE_MULT: float = 2.0
const STAR_COOLDOWN_MULT: float = 0.92
const SELL_RATIO: float = 0.5
const STAR_SELL_MULT: float = 1.6

const CLASSES: Array[String] = ["sword", "talisman", "wide", "thunder", "spirit"]
const ELEMENTS: Array[String] = ["metal", "wood", "water", "fire", "earth"]

const DEFS: Dictionary = {
	# ==================== 金系 (Metal: 锋芒·暴击·破甲) ====================
	"qingyun_sword": {
		"name": "青云剑", "behavior": Behavior.MELEE,
		"sfx": "sword_swing",
		"damage": 30.0, "cooldown": 1.1, "range": 150.0,
		"price": 25, "icon": "res://assets/art/weapon_sword.png",
		"desc": "近身挥斩，剑气凌厉；伤害受暴击率加成", "tag": "近战·剑系·金",
		"tags": ["sword", "metal"],
		"stat_scalings": {"crit_rate": 40.0},
	},
	"gengjin_feijian": {
		"name": "庚金飞剑", "behavior": Behavior.PROJECTILE,
		"sfx": "sword_swing",
		"damage": 38.0, "cooldown": 0.90, "range": 460.0,
		"price": 35, "icon": "res://assets/art/weapon_gold_sword.png",
		"desc": "飞剑锁敌追击、凌空贯日，贯穿两敌；伤害受暴击伤害加成", "tag": "远程·剑系·金",
		"pierce": 2,
		"tags": ["sword", "metal"],
		"stat_scalings": {"crit_mult_bonus": 25.0},
	},
	"liuye_feidao": {
		"name": "柳叶飞刀", "behavior": Behavior.PROJECTILE,
		"sfx": "talisman_throw",
		"damage": 16.0, "cooldown": 1.15, "range": 440.0,
		"price": 35, "icon": "res://assets/art/weapon_dagger.png",
		"desc": "扇形疾射三把细小飞刀，各锁一敌、贯穿群敌", "tag": "远程·符箓·金",
		"pierce": 3, "projectile_count": 3, "spread_angle": 0.20,
		"tags": ["talisman", "metal"],
		"stat_scalings": {"crit_rate": 30.0},
	},

	# ==================== 木系 (Wood: 生机·回复·剧毒) ====================
	"qingmu_tengbian": {
		"name": "青木藤鞭", "behavior": Behavior.MELEE,
		"sfx": "fan_gust",
		"damage": 24.0, "cooldown": 1.25, "range": 175.0,
		"price": 28, "icon": "res://assets/art/weapon_vine_whip.png",
		"desc": "苍翠灵藤大范围横扫，附带剧毒；伤害受气血回复加成", "tag": "近战·广域·木",
		"arc_scale": 1.35, "proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
		"tags": ["wide", "wood"],
		"stat_scalings": {"hp_regen": 4.5},
	},
	"wanmu_lingfu": {
		"name": "万木灵符", "behavior": Behavior.PROJECTILE,
		"sfx": "talisman_throw",
		"damage": 26.0, "cooldown": 1.0, "range": 420.0,
		"price": 32, "icon": "res://assets/art/weapon_wood_talisman.png",
		"desc": "青绿木符追敌而去，击中后弹射连锁至邻近两名妖兽并叠毒", "tag": "远程·符箓·木",
		"pierce": 1, "bounce_count": 2, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
		"tags": ["talisman", "wood"],
		"stat_scalings": {"hp_regen": 3.5},
	},
	"lingdie": {
		"name": "灵蝶", "behavior": Behavior.DRONE,
		"sfx": "orb_hit",
		"damage": 15.0, "cooldown": 0.35, "range": 78.0,
		"price": 40, "icon": "res://assets/art/sun_orb.png",
		"desc": "灵蝶萦绕周身，触敌即伤；伤害受吸血率加成", "tag": "环绕·御灵·木",
		"tags": ["spirit", "wood"],
		"stat_scalings": {"lifesteal": 100.0},
	},

	# ==================== 水系 (Water: 极寒·缓速·迅捷) ====================
	"bajiao_fan": {
		"name": "芭蕉扇", "behavior": Behavior.MELEE,
		"sfx": "fan_gust",
		"damage": 22.0, "cooldown": 1.3, "range": 185.0,
		"price": 20, "icon": "res://assets/art/weapon_fan.png",
		"desc": "扇出宽大罡风，击退极远并冰缓敌人；伤害受移速加成", "tag": "近战·广域·水",
		"arc_scale": 1.5, "proc_chill": 0.35, "chill_dur": 2.5,
		"tags": ["wide", "water"],
		"stat_scalings": {"move_speed_bonus": 25.0},
	},
	"xuanbing_feizhen": {
		"name": "玄冰飞针", "behavior": Behavior.PROJECTILE,
		"sfx": "talisman_throw",
		"damage": 14.0, "cooldown": 0.92, "range": 430.0,
		"price": 30, "icon": "res://assets/art/weapon_ice_needle.png",
		"desc": "三枚玄冰飞针齐射，各追一敌，刺骨冰寒；伤害受移速与攻速加成", "tag": "远程·符箓·水",
		"pierce": 1, "projectile_count": 3, "spread_angle": 0.18, "proc_chill": 0.35, "chill_dur": 2.0,
		"tags": ["talisman", "water"],
		"stat_scalings": {"move_speed_bonus": 28.0},
	},
	"hanquan_yulian": {
		"name": "寒泉玉莲", "behavior": Behavior.DRONE,
		"sfx": "orb_hit",
		"damage": 16.0, "cooldown": 0.40, "range": 82.0,
		"price": 42, "icon": "res://assets/art/weapon_ice_lotus.png",
		"desc": "冰魄玉莲护体，触碰冰缓妖兽；伤害受冷却缩减加成", "tag": "环绕·御灵·水",
		"proc_chill": 0.40, "chill_dur": 2.5,
		"tags": ["spirit", "water"],
		"stat_scalings": {"cdr_bonus": 30.0},
	},

	# ==================== 火系 (Fire: 烈焰·灼烧·爆裂) ====================
	"huoyan_fu": {
		"name": "火焰符", "behavior": Behavior.PROJECTILE,
		"sfx": "talisman_throw",
		"damage": 28.0, "cooldown": 0.85, "range": 420.0,
		"price": 30, "icon": "res://assets/art/weapon_staff.png",
		"desc": "掷出爆燃符箓，符行追敌不放、命中引燃；伤害受全局法伤加成", "tag": "远程·符箓·火",
		"pierce": 1, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
		"tags": ["talisman", "fire"],
		"stat_scalings": {"damage_bonus": 20.0},
	},
	"chiyan_dao": {
		"name": "赤焰斩马刀", "behavior": Behavior.MELEE,
		"sfx": "sword_swing",
		"damage": 34.0, "cooldown": 1.28, "range": 165.0,
		"price": 36, "icon": "res://assets/art/weapon_fire_blade.png",
		"desc": "大开大合烈火重刀，引燃身前群妖；伤害受范围加成", "tag": "近战·剑系·火",
		"arc_scale": 1.25, "proc_burn": true, "burn_ratio": 0.45, "burn_dur": 3.0,
		"tags": ["sword", "fire"],
		"stat_scalings": {"range_bonus": 25.0},
	},
	"fentian_baodeng": {
		"name": "焚天宝灯", "behavior": Behavior.BURST,
		"sfx": "thunder_strike",
		"damage": 36.0, "cooldown": 1.75, "range": 390.0,
		"price": 46, "icon": "res://assets/art/weapon_fire_lantern.png",
		"desc": "引落离火天劫轰击区域，点燃火海并灼烧敌群", "tag": "远程·雷法·火",
		"burst_radius": 85.0, "proc_burn": true, "burn_ratio": 0.50, "burn_dur": 3.0,
		"tags": ["thunder", "fire"],
		"stat_scalings": {"damage_bonus": 25.0},
	},

	# ==================== 土系 (Earth: 厚重·护甲·震退) ====================
	"wulei_paizi": {
		"name": "五雷法牌", "behavior": Behavior.BURST,
		"sfx": "thunder_strike",
		"damage": 35.0, "cooldown": 1.8, "range": 380.0,
		"price": 45, "icon": "res://assets/art/weapon_thunder.png",
		"desc": "引天雷厚土之威轰击目标区域，大范围强击退", "tag": "远程·雷法·土",
		"burst_radius": 80.0,
		"tags": ["thunder", "earth"],
		"stat_scalings": {"armor": 2.0},
	},
	"fantian_yin": {
		"name": "番天镇岳印", "behavior": Behavior.BURST,
		"sfx": "thunder_strike",
		"damage": 38.0, "cooldown": 1.9, "range": 360.0,
		"price": 48, "icon": "res://assets/art/weapon_earth_seal.png",
		"desc": "番天玄石大印从天轰砸，受护甲极高加成！", "tag": "区域·广域·土",
		"burst_radius": 95.0,
		"tags": ["wide", "earth"],
		"stat_scalings": {"armor": 3.5},
	},
	"hunyuan_zhong": {
		"name": "混元古钟", "behavior": Behavior.DRONE,
		"sfx": "orb_hit",
		"damage": 18.0, "cooldown": 0.45, "range": 88.0,
		"price": 44, "icon": "res://assets/art/weapon_earth_bell.png",
		"desc": "混元古钟环绕周身，强力撞退敌群；伤害受气血上限加持", "tag": "环绕·御灵·土",
		"tags": ["spirit", "earth"],
		"stat_scalings": {"max_hp_bonus": 0.12},
	},
}

## 流派羁绊：同 tag 法器持有多件时激活阶梯加成（重复同名法器也计数）
## 涵盖器类 5 系 + 五行 5 系，共 10 种流派羁绊
const SYNERGIES: Dictionary = {
	# ---- 器类羁绊 ----
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

	# ---- 五行羁绊 ----
	"metal": {
		"name": "锐金", "thresholds": [2, 4, 6],
		"values": [0.06, 0.12, 0.20],
		"desc": "暴击率 +6/12/20%，暴击伤害 +20/40/75%",
	},
	"wood": {
		"name": "青木", "thresholds": [2, 4, 6],
		"values": [1.0, 2.0, 3.5],
		"desc": "气血回复 +1/2/3.5/秒，生命吸取 +2/4/7%",
	},
	"water": {
		"name": "玄水", "thresholds": [2, 4, 6],
		"values": [0.94, 0.88, 0.80],
		"desc": "施法间隔 -6/12/20%，移动速度 +8/16/25%",
	},
	"fire": {
		"name": "离火", "thresholds": [2, 4, 6],
		"values": [0.08, 0.16, 0.26],
		"desc": "法器伤害 +8/16/26%，灼烧伤害 +30/60/100%",
	},
	"earth": {
		"name": "厚土", "thresholds": [2, 4, 6],
		"values": [3.0, 6.0, 10.0],
		"desc": "护甲 +3/6/10，受击震退力 +25/50/80%",
	},
}

## 开局三选一（覆盖金木水火土五种代表性本命法器）
const STARTER_IDS: Array = ["qingyun_sword", "wanmu_lingfu", "bajiao_fan", "huoyan_fu", "fantian_yin"]

## 商店武器池（全部 15 把法器）
const SHOP_POOL: Array = [
	"qingyun_sword", "gengjin_feijian", "liuye_feidao",
	"qingmu_tengbian", "wanmu_lingfu", "lingdie",
	"bajiao_fan", "xuanbing_feizhen", "hanquan_yulian",
	"huoyan_fu", "chiyan_dao", "fentian_baodeng",
	"wulei_paizi", "fantian_yin", "hunyuan_zhong"
]

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

static func class_of(id: String) -> String:
	var t := tags_of(id)
	for tag in t:
		if tag in CLASSES:
			return tag
	return ""

static func element_of(id: String) -> String:
	var t := tags_of(id)
	for tag in t:
		if tag in ELEMENTS:
			return tag
	return ""

## 该法器的开火音 key（缺省回落到通用的 blade_shoot，保证老调用不会哑）
static func sfx_for(id: String) -> String:
	return String(DEFS.get(id, {}).get("sfx", "blade_shoot"))

## 弹丸从 2026-10-08 起带有限转向追踪（BladeProjectile.HOMING_TURN_RATE）：
## 场上只剩一个敌人时，一次三发的法器每一发最终都归它 ⇒ 单体口径按发数求和才与运行时一致。
## 下面两个纯函数是给"档位体检"当尺子用的（判据见 tests/unit_runner.gd::_test_ranged_focus_dps），
## 口径：★star、不吃玩家属性/羁绊/暴击/危险度，只比较法器自身的设计强度。
const FOCUS_RANGED_MAX_TARGETS := 2   ## 单发最多结算这么几个敌人的远程法器 = 「点杀位」

## 单发（一次开火）最多能结算几个敌人。近战横扫 / 区域落雷 / 环绕接触天生打一片，按"群体"给档；
## 弹丸按 发数 ×（穿透 + 弹射）计，穿透与弹射都各自吃一个独立敌人。
static func targets_per_shot(id: String) -> int:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0
	var behavior := int(def.get("behavior", Behavior.MELEE))
	if behavior == Behavior.PROJECTILE:
		var per_bullet := maxi(1, int(def.get("pierce", 1))) + maxi(0, int(def.get("bounce_count", 0)))
		return maxi(1, int(def.get("projectile_count", 1))) * per_bullet
	if behavior == Behavior.DRONE:
		return 3      ## 环绕接触：同时贴身的一般是两三尊
	return 6          ## 近战弧扫 / 落雷圆形：天生群体
## 「点杀位」远程法器：弹丸类里单发最多只结算 FOCUS_RANGED_MAX_TARGETS 个敌人的那些。
## 这一档必须在"啃硬目标"上赢过贴脸与环绕，否则就是纯下位（用户 2026-10-08 的火符投诉）。
static func is_focus_ranged(id: String) -> bool:
	var def: Dictionary = DEFS.get(id, {})
	return int(def.get("behavior", -1)) == Behavior.PROJECTILE \
		and targets_per_shot(id) <= FOCUS_RANGED_MAX_TARGETS

## 对一个孤立敌人的持续 DPS（不含玩家加成）。灼烧/剧毒按"单次施加的常驻量"折算：
## 冷却 < 异常时长 ⇒ 全程挂着（灼烧在 EnemyBase 里取 max 不叠层）；否则按占比折算。冰缓不加伤，不计。
static func sustained_single_dps(id: String, star: int = 1) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0.0
	var dmg := damage_for(id, star)
	var cd := maxf(0.05, cooldown_for(id, star))
	var per_hit: float = 1.0
	if int(def.get("behavior", Behavior.MELEE)) == Behavior.MELEE:
		per_hit = 1.35      # 近战在 FloatingWeapon._deal_melee_damage 里有 ×1.35 加护
	elif int(def.get("behavior", Behavior.MELEE)) == Behavior.PROJECTILE:
		per_hit = float(maxi(1, int(def.get("projectile_count", 1))))
	var dps: float = dmg * per_hit / cd
	if def.get("proc_burn", false):
		dps += dmg * float(def.get("burn_ratio", 0.4)) * minf(1.0, float(def.get("burn_dur", 3.0)) / cd)
	if def.get("proc_poison", false):
		dps += dmg * float(def.get("poison_ratio", 0.3)) * minf(1.0, float(def.get("poison_dur", 2.5)) / cd)
	return dps
