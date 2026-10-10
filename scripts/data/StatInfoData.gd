class_name StatInfoData
extends RefCounted

## 属性面板「点按看详解」的文案与字段对照表（纯数据 + 纯函数，不碰节点、不碰存档）。
##
## 为什么单独一个文件：面板那 14 行原本只有「名字 + 一个数字」，玩家看不出噬元和气血回复有什么区别、
## 灵韵涨到第几波为止、闪避为什么点满了不再动。这些规则散在 GameManager / GameBalance 的代码里，
## 抄一份进文案就会漂（调一次参数文案就变假话），所以本表只写「人话规则」：
## 凡是数字一律现读常量（GameManager.DODGE_CAP、GameBalance.ARMOR_COEF …），
## 来源拆解由 PlayerStatsDialog 现读 GameManager 字段，本表不参与任何结算。
##
## 三条口径：
## 1. INFO 的 key 与面板属性行一一对应，漏一条由 tests/StatsTipCheck 钉成红灯；
## 2. FIELDS 是「加点字段 → 人话名 + 单位」的唯一对照表，悟道/法宝卡片与详情里的幅度文案都走它，
##    新字段没登记就会在详情里露出原始 key（判据同样拦）；幅度数字仍只在 UpgradeData/ItemData 的 apply 里；
## 3. 单位换算规则（pct / pctmul / …）在这里定义，与 UpgradeData 各项 desc 里的手写百分号同源：
##    pct 是「增量 ×100」，pctmul 是「乘数 -1 再 ×100」（如攻速 ×0.88 → 攻击间隔 -12%）。

## 加点字段 → 人话名 + 单位（单位含义见文件头第 3 条）
const FIELDS: Dictionary = {
	"weapon_damage_mult": {"name": "武器伤害", "unit": "pct"},
	"attack_speed_mult_mul": {"name": "攻击间隔", "unit": "pctmul"},
	"armor": {"name": "护甲", "unit": "pt"},
	"move_speed_mult": {"name": "移动速度", "unit": "pct"},
	"attack_range_mult": {"name": "攻击范围", "unit": "pct"},
	"pickup_range_mult": {"name": "拾取范围", "unit": "pct"},
	"hp_regen": {"name": "生命回复", "unit": "rate"},
	"crit_rate": {"name": "暴击率", "unit": "pct"},
	"crit_mult": {"name": "暴击伤害", "unit": "pct"},
	"dodge": {"name": "闪避率", "unit": "pct"},
	"lifesteal": {"name": "吸血概率", "unit": "pct"},
	"luck": {"name": "幸运", "unit": "pt"},
	"harvest": {"name": "收益", "unit": "pt"},
	"spirit_stones": {"name": "金币", "unit": "stone"},
	"max_hp": {"name": "最大生命", "unit": "pt"},
	"hp_heal": {"name": "立即回复", "unit": "pt"},
	"xp_gain_mult": {"name": "经验获取", "unit": "pct"},
	"knockback_mult": {"name": "击退力度", "unit": "pct"},
	"free_rerolls": {"name": "免费重掷", "unit": "times"},
	"elite_damage": {"name": "对精英伤害", "unit": "pct"},
	"shop_price_mul": {"name": "商店物价", "unit": "pctmul"},
	"melee_damage": {"name": "近战伤害", "unit": "pt"},
	"ranged_damage": {"name": "远程伤害", "unit": "pt"},
	"elemental_damage": {"name": "元素伤害", "unit": "pt"},
	"engineering_damage": {"name": "召唤伤害", "unit": "pt"},
	"element_damage_all": {"name": "全元素伤害", "unit": "pct"},
}

## 五行名：element_damage_<key> 的人话名走它，与 WeaponData.ELEMENTS 同一批 key
const ELEMENT_NAMES: Dictionary = {
	"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土",
}

## 土豆兄弟式主要属性分组（核心战斗与经济属性）
const PRIMARY_IDS: Array[String] = [
	"hp", "regen", "lifesteal", "damage",
	"melee_dmg", "ranged_dmg", "elemental_dmg", "engineering_dmg",
	"haste", "crit", "range", "armor", "dodge", "speed", "luck", "harvest"
]

## 土豆兄弟式次要属性分组（辅助、特殊效果与统计）
const SECONDARY_IDS: Array[String] = [
	"pickup", "xp_gain", "shop_price", "bonus_pierce",
	"elite_dmg", "knockback", "free_rerolls", "kills", "stones"
]

## 面板每一行 → 它吃什么加点字段。空表 = 纯读数，不吃任何加成。
const STAT_FIELDS: Dictionary = {
	"hp": ["max_hp"],
	"regen": ["hp_regen"],
	"lifesteal": ["lifesteal"],
	"damage": ["weapon_damage_mult"],
	"melee_dmg": ["melee_damage"],
	"ranged_dmg": ["ranged_damage"],
	"elemental_dmg": ["elemental_damage"],
	"engineering_dmg": ["engineering_damage"],
	"haste": ["attack_speed_mult_mul"],
	"crit": ["crit_rate", "crit_mult"],
	"range": ["attack_range_mult"],
	"armor": ["armor"],
	"dodge": ["dodge"],
	"speed": ["move_speed_mult"],
	"luck": ["luck"],
	"harvest": ["harvest"],
	"pickup": ["pickup_range_mult"],
	"xp_gain": ["xp_gain_mult"],
	"shop_price": ["shop_price_mul"],
	"bonus_pierce": [],
	"elite_dmg": ["elite_damage"],
	"knockback": ["knockback_mult"],
	"free_rerolls": ["free_rerolls"],
	"kills": [],
	"stones": ["spirit_stones"],
}

## 面板每一行的标题（与 PlayerStatsDialog 的行名同源，判据比对用）
const STAT_TITLES: Dictionary = {
	"hp": "生命值",
	"regen": "生命回复",
	"armor": "护甲",
	"dodge": "闪避率",
	"lifesteal": "吸血",
	"damage": "武器伤害",
	"melee_dmg": "近战伤害",
	"ranged_dmg": "远程伤害",
	"elemental_dmg": "元素伤害",
	"engineering_dmg": "召唤伤害",
	"haste": "攻击间隔",
	"speed": "移动速度",
	"pickup": "拾取范围",
	"range": "攻击范围",
	"crit": "暴击",
	"luck": "幸运",
	"harvest": "收益",
	"xp_gain": "经验获取",
	"shop_price": "商店物价",
	"bonus_pierce": "贯穿",
	"elite_dmg": "对精英伤害",
	"knockback": "击退力度",
	"free_rerolls": "免费重掷",
	"kills": "累计击杀",
	"stones": "随身金币",
}

## 一句话「这是什么」；结算规则与上限走 rules()
const BRIEF: Dictionary = {
	"hp": "角色的命线：归零即阵亡，本局结束。",
	"regen": "每秒自动回复的生命值。",
	"armor": "按百分比减免每次受击的伤害。",
	"dodge": "有概率完全闪避一次攻击，不掉血。",
	"lifesteal": "命中时有概率吸取1点生命。",
	"damage": "所有武器伤害的总乘区。",
	"melee_dmg": "加成近战类武器的基础伤害。",
	"ranged_dmg": "加成远程类武器的基础伤害。",
	"elemental_dmg": "加成元素伤害与灼烧、中毒等持续伤害。",
	"engineering_dmg": "加成环绕类召唤武器的基础伤害。",
	"haste": "缩短每件武器的攻击间隔。",
	"speed": "角色的移动速度。",
	"pickup": "金币与经验自动拾取的范围。",
	"range": "武器索敌与攻击的距离。",
	"crit": "暴击的概率与倍率。",
	"luck": "提高高稀有度升级与道具的出现概率。",
	"harvest": "每波结束白得金币与经验，且有复利增长。",
	"xp_gain": "每颗经验光球提供的经验倍率。",
	"shop_price": "商店商品的物价折算。",
	"bonus_pierce": "远程弹丸类武器的额外穿透次数。",
	"elite_dmg": "对精英与Boss的额外伤害。",
	"knockback": "击中敌人时的击退距离与力度。",
	"free_rerolls": "每波商店开始时免费重掷的次数。",
	"kills": "本局击杀敌人的总数，含精英与Boss。",
	"stones": "本局货币：买武器、道具、重掷都花它。",
}

static func ids() -> Array:
	return STAT_FIELDS.keys()

static func has(id: String) -> bool:
	return STAT_FIELDS.has(id) and BRIEF.has(id) and STAT_TITLES.has(id)

static func title(id: String) -> String:
	return String(STAT_TITLES.get(id, id))

static func brief(id: String) -> String:
	return String(BRIEF.get(id, ""))

static func apply_fields(id: String) -> Array:
	return STAT_FIELDS.get(id, [])

## 反查：某个加点字段落在面板哪一行。
## 供悟道详情那句「这一条落在左侧哪一行」指路用 —— 字段对照只此一份，面板不许再写一遍。
static func stat_of_field(key: String) -> String:
	for id in STAT_FIELDS.keys():
		if key in STAT_FIELDS[id]:
			return String(id)
	return ""

## 结算规则与上限：数字全部现读常量，调参后这里跟着变，不需要改文案。
static func rules(id: String) -> Array[String]:
	var out: Array[String] = []
	match id:
		"hp":
			out.append("最大生命 = 角色基础 × 角色生命系数，再加升级与道具的增量、召唤羁绊的额外生命。")
			out.append("受击实伤 = 伤害 ÷ (1 + 护甲 × %s)，且保底 %d 点：护甲再高也抹不平最后一击。" % [
				_fmt(GameBalance.ARMOR_COEF), int(GameBalance.DAMAGE_FLOOR)])
			out.append("三条回血路：生命回复每秒持续回、吸血命中概率回、波末结算（收益与回春葫芦）。")
		"regen":
			out.append("每帧按「回复量 × 时间」累加，满血时不溢出、也不折抵成别的收益。")
			out.append("木系羁绊额外加在这一条上，详情里单列一行。")
			out.append("与吸血是两回事：这条是持续回，那条是命中掷概率、一次只回 1 点。")
		"armor":
			out.append("减伤 = 1 − 1 ÷ (1 + 护甲 × %s)：收益递减但没有上限，堆得越高每点越不值钱。" % _fmt(GameBalance.ARMOR_COEF))
			out.append("面板减伤不含「保底 %d 点」这一刀，所以高护甲挨小伤害时实际比面板略差。" % int(GameBalance.DAMAGE_FLOOR))
			out.append("土系羁绊与道具「龟甲符」加在这条上；「狂血丹」用护甲换伤害，会倒扣。")
		"dodge":
			out.append("硬上限 %d%%：到顶之后再点这一条不会继续涨，多余的额度是浪费。" % int(GameManager.DODGE_CAP * 100.0))
			out.append("判定在护甲之前：闪避成功等于这次攻击完全没发生，不减伤、也不触发反震。")
		"lifesteal":
			out.append("每次生效只回 1 点生命：概率越高越稳，不会一次回一大截。")
			out.append("每秒至多触发 %d 次：高频武器刷不出无限续航。" % GameManager.LIFESTEAL_MAX_PER_SEC)
			out.append("木系羁绊的加成与升级、道具合在一起算，共用同一个每秒闸。")
		"damage":
			out.append("面板 = 升级/道具/角色乘区 × 流派羁绊乘区，以 100% 为基准。")
			out.append("暴击是另一个乘区，与这一条相乘，不互相打折。")
			out.append("单件武器还能把别的属性折成伤害，点武器图标看它吃什么属性。")
		"melee_dmg":
			out.append("按点数直接增加所有挥砍横扫类近战武器的基础伤害。")
			out.append("长剑、烈焰刀、藤鞭、风扇等近战武器均直接享受本项加成。")
		"ranged_dmg":
			out.append("按点数直接增加所有飞剑飞针与飞射类远程武器的基础伤害。")
			out.append("飞剑、飞刀、冰针、毒符等远程武器直接享受本项加成。")
		"elemental_dmg":
			out.append("按点数直接增加符箓、雷法轰击以及异常状态的伤害。")
			out.append("直接提升火符灼烧与毒符中毒的每秒跳字伤害，火系与木系角色首选。")
		"engineering_dmg":
			out.append("按点数直接增加所有环绕类召唤武器的基础接触伤害。")
			out.append("护蝶、冰莲、古钟等召唤武器均享受全额加成，符阵灵童核心流派。")
		"haste":
			out.append("攻击间隔按乘算叠：每层各乘一次，越点越省，不是百分比相加。")
			out.append("下限 = 攻击间隔 ×%s：到下限后再点不再变快。" % _fmt(GameManager.ATTACK_SPEED_FLOOR))
			out.append("面板显示的是相对 1.00 的缩减量，所以 -12% 与 -14% 叠起来是 -23%，不是 -26%。")
		"speed":
			out.append("实际移速 = 角色基础移速 × (1 + 升级/道具加成 + 羁绊加成)。")
			out.append("角色的负面代偿直接乘在这一条上，所以读数可能是负的（如石岳·体修 -15%）。")
			out.append("个别角色会锁死某条升级（如石岳锁「神行符」），被锁的那条不再出现在候选里。")
		"pickup":
			out.append("半径 = 基础拾取半径 × 倍率，只管金币与经验的吸附，不影响攻击距离。")
			out.append("这条不够高时，金币会留在地上等人走过去捡，站得远就捡得慢。")
		"range":
			out.append("乘在每件武器的射程上；剑系羁绊额外加这一条。")
			out.append("近战武器同样吃它——挥斩的弧更长，不是只有远程受益。")
		"crit":
			out.append("概率与倍率是两件事：先按概率判定会不会心，命中后再按倍率放大那一刀。")
			out.append("暴击率有软上限 %d%%：到顶之后再加是白加。" % int(GameManager.CRIT_RATE_CAP * 100.0))
			out.append("暴击伤害按倍率相加，只影响会心那一刀，普通攻击完全不吃。")
			out.append("金系羁绊同时抬这两处；部分武器还会把暴击率直接折成额外伤害。")
		"luck":
			out.append("每点把史诗权重抬 %s，差额从普通里扣：三档之和恒定，不会整体变稀有。" % _fmt(GameBalance.LUCK_EPIC_PER_POINT))
			out.append("普通权重有地板 %s，所以幸运堆到极高之后边际收益会停住。" % _fmt(GameBalance.RARITY_COMMON_FLOOR))
			out.append("对商店货架是按权重微调，不是必出；幸运低也不至于刷不出货。")
		"harvest":
			out.append("波末按等额发放：收益 8 就是金币与经验各 +8，与击杀掉落另算。")
			out.append("每波自我复利 ×%s，涨到第 %d 波为止，之后持平。" % [
				_fmt(GameBalance.HARVEST_GROWTH), GameManager.HARVEST_GROWTH_WAVE_CAP])
			out.append("经验与金币同源，所以收益高 = 升级快 = 升级次数多。")
		"xp_gain":
			out.append("经验获取倍率：只放大吸收经验光球时的升级经验，不影响金币获取。")
			out.append("主要由稀有升级「悟性通明」与史诗道具「悟剑石」提供。")
		"shop_price":
			out.append("商店所有在售武器、道具及重掷费用的全局价格折算比例。")
			out.append("角色自带八折特权，道具「折扣玉符」可进一步叠加折让。")
		"bonus_pierce":
			out.append("飞剑飞符穿透敌人数量的额外增量。")
			out.append("弹射羁绊核心收益，可在敌潮阵线中反复洞穿造成海量伤害。")
		"elite_dmg":
			out.append("对精英与守关 Boss 的独立伤害乘区加成。")
			out.append("升级「对精英夺旗」与道具「破甲锥」生效，不影响寻常小怪。")
		"knockback":
			out.append("武器击退敌人的推力与距离加成倍率。")
			out.append("土系羁绊与道具「雷引针」加在这条上，防高密度敌潮近身。")
		"free_rerolls":
			out.append("每波进入商店时无需花费金币即可免费重掷货架的次数。")
			out.append("道具「重掷令」提供，用完后重掷费用才开始按正常递增结算。")
		"kills":
			out.append("只是读数：不吃任何加成，也不参与结算公式。")
			out.append("精英与 Boss 同样计入；它们多掉的金币走另一条账。")
		"stones":
			out.append("来源三条：击杀掉落、收益波末发放、升级「金币补给」当场给一笔。")
			out.append("只在局内有效，局末不结转下局；商店的重掷费用逐次递增。")
	return out

## 这一行能被哪些途径抬高：扫悟道表与法宝表的 apply，命中本行吃的字段就报名字。
## 只报名、不报数值——数值在各自卡片的详情里，避免同一个数字出现两处。
static func sources(id: String) -> Array[String]:
	var out: Array[String] = []
	var fields: Array = apply_fields(id)
	if fields.is_empty():
		return out
	for udef in UpgradeData.UPGRADES:
		var u: Dictionary = udef
		if _apply_hits(u.get("apply", {}), fields):
			out.append("升级·%s" % String(u.get("title", "?")))
	for key in ItemData.DEFS.keys():
		var idef: Dictionary = ItemData.DEFS[key]
		if _apply_hits(idef.get("apply", {}), fields):
			out.append("道具·%s" % String(idef.get("name", "?")))
	return out

static func _apply_hits(apply: Dictionary, fields: Array) -> bool:
	for key in apply.keys():
		if key in fields:
			return true
	return false

## 把一条 apply 字典翻成人话幅度：{"weapon_damage_mult":0.15,"armor":-2.0}
## → ["法器伤害 +15%", "护甲 -2"]。悟道、法宝、属性行详情共用这一把尺子。
static func format_apply(apply: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in apply.keys():
		var k := String(key)
		out.append("%s %s" % [field_name(k), format_amount(k, float(apply[key]))])
	return out

static func field_name(key: String) -> String:
	if FIELDS.has(key):
		return String(FIELDS[key]["name"])
	if key.begins_with("element_damage_"):
		var elem: String = key.trim_prefix("element_damage_")
		if ELEMENT_NAMES.has(elem):
			return "%s系伤害" % String(ELEMENT_NAMES[elem])
	return key

static func field_unit(key: String) -> String:
	if FIELDS.has(key):
		return String(FIELDS[key]["unit"])
	if key.begins_with("element_damage_"):
		return "pct"
	return "pt"

static func format_amount(key: String, v: float) -> String:
	var sgn: String = "+" if v >= 0.0 else "-"
	match field_unit(key):
		"pct":
			return "%s%.0f%%" % [sgn, absf(v) * 100.0]
		"pctmul":
			var d: float = v - 1.0
			return "%s%.0f%%" % ["+" if d >= 0.0 else "-", absf(d) * 100.0]
		"rate":
			return "%s%.1f/秒" % [sgn, absf(v)]
		"stone":
			return "%s%d 枚" % [sgn, int(absf(v))]
		"times":
			return "%s%d 次" % [sgn, int(absf(v))]
		_:
			return "%s%s" % [sgn, _fmt(absf(v))]

static func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.0001:
		return "%d" % int(roundf(v))
	return String.num(v, 3)

static func _c(v: float) -> Color:
	if v > 0.0001:
		return GameStyle.GOOD
	if v < -0.0001:
		return GameStyle.BAD
	return GameStyle.PAPER

static func _mul(v: float) -> String:
	return "×%.2f" % v

static func _cultivator_name() -> String:
	var def := CultivatorData.get_def(GameManager.cultivator_id)
	if def.is_empty():
		return "未选角色"
	return String(def.get("name", "未选角色"))

## 来源拆解：覆盖全部 25 项主要与次要属性（供 PlayerStatsDialog 详情卡调用）
static func stat_tip_rows(id: String) -> Array:
	var s := GameManager.get_stat_breakdown()
	var rows: Array = []
	match id:
		"hp":
			var mx: float = float(s.get("max_hp", 0.0))
			var cur: float = float(s.get("current_hp", 0.0))
			rows = [
				["当前生命", "%d / %d" % [int(cur), int(mx)]],
				["最大生命", "%.0f" % mx],
				["已损", "%d 点" % int(mx - cur), GameStyle.BAD if cur < mx else GameStyle.GREY],
				["召唤羁绊", "+%.0f" % GameManager.synergy_max_hp_bonus, _c(GameManager.synergy_max_hp_bonus)],
				["角色", _cultivator_name()],
			]
		"regen":
			var rate: float = float(s.get("hp_regen", 0.0))
			var need: float = float(s.get("max_hp", 0.0)) - float(s.get("current_hp", 0.0))
			rows = [
				["每秒回复", "%.1f / 秒" % rate],
				["升级·道具·角色", "%.1f" % GameManager.hp_regen, _c(GameManager.hp_regen)],
				["木系羁绊", "+%.1f" % GameManager.synergy_hp_regen, _c(GameManager.synergy_hp_regen)],
				["回满已损需要", "%.1f 秒" % (need / rate) if rate > 0.0 and need > 0.0 else "—"],
			]
		"armor":
			var arm: float = float(s.get("armor", 0.0))
			var nxt: float = GameBalance.armor_reduction(arm + 1.0) * 100.0
			rows = [
				["护甲合计", "%.0f 点" % arm],
				["升级·道具·角色", "%+.0f" % GameManager.armor, _c(GameManager.armor)],
				["土系羁绊", "%+.0f" % GameManager.synergy_armor, _c(GameManager.synergy_armor)],
				["当前减伤", "%.1f%%" % float(s.get("dmg_reduction_pct", 0.0)), _c(arm)],
				["再加 1 点", "+%.1f%%" % (nxt - float(s.get("dmg_reduction_pct", 0.0))), GameStyle.GOOD],
			]
		"dodge":
			var dg: float = float(s.get("dodge_pct", 0.0))
			var cap: float = (GameManager.DODGE_CAP + GameManager.dodge_cap_bonus) * 100.0
			rows = [
				["闪避率", "%.0f%%" % dg, _c(dg)],
				["升级·道具·角色", "%.0f%%" % (GameManager.dodge * 100.0), _c(GameManager.dodge)],
				["硬上限", "%.0f%%" % cap, GameStyle.GREY],
				["距上限", "%.0f%%" % maxf(0.0, cap - dg)],
			]
		"lifesteal":
			rows = [
				["触发概率", "%.0f%%" % float(s.get("lifesteal_pct", 0.0)), _c(float(s.get("lifesteal_pct", 0.0)))],
				["升级·道具·角色", "%.0f%%" % (GameManager.lifesteal * 100.0), _c(GameManager.lifesteal)],
				["木系羁绊", "+%.0f%%" % (GameManager.synergy_lifesteal * 100.0), _c(GameManager.synergy_lifesteal)],
				["每秒至多", "%d 次" % GameManager.LIFESTEAL_MAX_PER_SEC],
				["每次生效", "回复 1 点生命"],
			]
		"damage":
			rows = [
				["总乘区", "%d%%" % int(float(s.get("damage_mult", 1.0)) * 100.0)],
				["换算增伤", "%+.0f%%" % float(s.get("damage_bonus_pct", 0.0)), _c(float(s.get("damage_bonus_pct", 0.0)))],
				["升级·道具·角色", _mul(GameManager.weapon_damage_mult), _c(GameManager.weapon_damage_mult - 1.0)],
				["流派羁绊", _mul(GameManager.synergy_damage_mult), _c(GameManager.synergy_damage_mult - 1.0)],
				["暴击另算", "%.0f%% 概率 ×%.2f" % [float(s.get("crit_rate_pct", 0.0)), float(s.get("crit_dmg_pct", 150.0)) / 100.0]],
			]
		"melee_dmg":
			var mv: float = float(s.get("melee_damage", 0.0))
			rows = [
				["近战伤害加成", "%+.0f" % mv, _c(mv)],
				["受益武器", "长剑 / 烈焰刀 / 藤鞭 / 风扇"],
				["星级放大", "每升 1 星转化效率 +25%"],
			]
		"ranged_dmg":
			var rv: float = float(s.get("ranged_damage", 0.0))
			rows = [
				["远程伤害加成", "%+.0f" % rv, _c(rv)],
				["受益武器", "飞剑 / 飞刀 / 毒符 / 冰针 / 火符"],
				["星级放大", "每升 1 星转化效率 +25%"],
			]
		"elemental_dmg":
			var ev: float = float(s.get("elemental_damage", 0.0))
			rows = [
				["元素伤害加成", "%+.0f" % ev, _c(ev)],
				["火系灼烧倍率", _mul(GameManager.synergy_burn_mult), _c(GameManager.synergy_burn_mult - 1.0)],
				["受益武器", "火符 / 烈焰刀 / 天灯 / 雷牌 / 巨印等"],
			]
		"engineering_dmg":
			var gv: float = float(s.get("engineering_damage", 0.0))
			rows = [
				["召唤伤害加成", "%+.0f" % gv, _c(gv)],
				["当前召唤武器", "%d 尊" % GameManager.drones.size()],
				["受益武器", "护蝶 / 冰莲 / 古钟"],
			]
		"haste":
			rows = [
				["间隔缩减", "%.1f%%" % float(s.get("cdr_pct", 0.0)), _c(float(s.get("cdr_pct", 0.0)))],
				["实际攻击间隔", _mul(float(s.get("attack_speed_mult", 1.0)))],
				["升级·道具·角色", _mul(GameManager.attack_speed_mult), _c(1.0 - GameManager.attack_speed_mult)],
				["范围·水系羁绊", _mul(GameManager.synergy_haste_mult), _c(1.0 - GameManager.synergy_haste_mult)],
				["间隔下限", _mul(GameManager.ATTACK_SPEED_FLOOR), GameStyle.GREY],
			]
		"speed":
			var eff: float = GameManager.move_speed_mult + GameManager.synergy_move_speed_mult
			var spd: float = float(s.get("move_speed", 0.0))
			rows = [
				["实际移速", "%.0f" % spd],
				["角色基础", "%.0f" % (spd / eff if eff > 0.01 else spd)],
				["升级·道具·角色", "%+.0f%%" % ((GameManager.move_speed_mult - 1.0) * 100.0), _c(GameManager.move_speed_mult - 1.0)],
				["水系羁绊", "%+.0f%%" % (GameManager.synergy_move_speed_mult * 100.0), _c(GameManager.synergy_move_speed_mult)],
			]
		"pickup":
			var pkm: float = GameManager.pickup_range_mult
			var rad: float = float(s.get("pickup_radius", 0.0))
			rows = [
				["拾取半径", "%.0f 像素" % rad],
				["倍率", _mul(pkm), _c(pkm - 1.0)],
				["基础半径", "%.0f 像素" % (rad / pkm if pkm > 0.01 else rad)],
			]
		"range":
			rows = [
				["攻击范围", "%+.0f%%" % float(s.get("attack_range_pct", 0.0)), _c(float(s.get("attack_range_pct", 0.0)))],
				["升级·道具·角色", _mul(GameManager.attack_range_mult), _c(GameManager.attack_range_mult - 1.0)],
				["剑系羁绊", _mul(GameManager.synergy_range_mult), _c(GameManager.synergy_range_mult - 1.0)],
			]
		"crit":
			var cmul: float = GameManager.crit_mult + GameManager.synergy_crit_mult
			rows = [
				["面板暴击率", "%.0f%%" % float(s.get("crit_rate_pct", 0.0)), GameStyle.JADE],
				["升级·道具·角色", "%.0f%%（含基础）" % (GameManager.crit_rate * 100.0)],
				["金系羁绊", "+%.0f%%" % (GameManager.synergy_crit_rate * 100.0), _c(GameManager.synergy_crit_rate)],
				["暴击倍率", "%.2f×" % cmul, _c(cmul - 1.5)],
				["软上限", "%.0f%%" % (GameManager.CRIT_RATE_CAP * 100.0), GameStyle.GREY],
			]
		"luck":
			var rw: Dictionary = GameBalance.rarity_weights(GameManager.luck)
			rows = [
				["幸运", "%.0f" % float(s.get("luck", 0.0)), _c(GameManager.luck)],
				["史诗权重", "%.0f / %.0f" % [float(rw.get("epic", 0.0)), GameBalance.RARITY_TOTAL]],
				["稀有权重", "%.0f / %.0f" % [float(rw.get("rare", 0.0)), GameBalance.RARITY_TOTAL]],
				["普通权重", "%.0f / %.0f" % [float(rw.get("common", 0.0)), GameBalance.RARITY_TOTAL]],
			]
		"harvest":
			var hv: float = float(s.get("harvest", 0.0))
			var gain: int = GameBalance.harvest_gain(hv)
			rows = [
				["收益", "%.0f" % hv, _c(hv)],
				["本波末发放", "+%d 金币 / +%d 经验" % [gain, gain], GameStyle.JADE],
				["每波复利", _mul(GameBalance.HARVEST_GROWTH), GameStyle.GREY],
				["增长截止", "第 %d 波（当前第 %d 波）" % [GameManager.HARVEST_GROWTH_WAVE_CAP, maxi(GameManager.wave_number, 1)]],
			]
		"xp_gain":
			var xp_p: float = float(s.get("xp_gain_pct", 0.0))
			rows = [
				["经验获取倍率", _mul(GameManager.xp_gain_mult), _c(xp_p)],
				["折算加成", "%+.0f%%" % xp_p, _c(xp_p)],
				["当前升级门槛", "%d / %d" % [GameManager.experience, GameManager.experience_to_next]],
			]
		"shop_price":
			var sp_p: float = float(s.get("shop_price_pct", 0.0))
			rows = [
				["商店物价系数", _mul(GameManager.shop_price_mult), _c(-sp_p)],
				["折算幅度", "%+.0f%%" % sp_p, _c(-sp_p)],
			]
		"bonus_pierce":
			var bp: int = int(s.get("bonus_pierce", 0))
			rows = [
				["额外穿透人数", "+%d" % bp, _c(float(bp))],
				["来源", "弹射羁绊 (2/4/6 件分别 +1/+2/+3)"],
			]
		"elite_dmg":
			var ep: float = float(s.get("elite_damage_pct", 0.0))
			rows = [
				["对精英/Boss增伤", "%+.0f%%" % ep, _c(ep)],
				["独立乘区", _mul(1.0 + GameManager.elite_damage), _c(ep)],
			]
		"knockback":
			var kp: float = float(s.get("knockback_pct", 0.0))
			rows = [
				["击退总倍率", _mul(GameManager.knockback_mult * GameManager.synergy_knockback_mult), _c(kp)],
				["升级·道具", _mul(GameManager.knockback_mult), _c(GameManager.knockback_mult - 1.0)],
				["土系羁绊", _mul(GameManager.synergy_knockback_mult), _c(GameManager.synergy_knockback_mult - 1.0)],
			]
		"free_rerolls":
			var fr: int = int(s.get("free_rerolls", 0))
			rows = [
				["每波免费重掷", "%d 次" % fr, _c(float(fr))],
				["本波剩余免费", "%d 次" % GameManager.reroll_free_left],
			]
		"kills":
			var mins: float = maxf(GameManager.game_time, 1.0) / 60.0
			rows = [
				["本局击杀", "%d 个" % GameManager.kills],
				["平均", "%.1f 个/分钟" % (float(GameManager.kills) / mins)],
			]
		"stones":
			rows = [
				["随身金币", "%d 枚" % GameManager.spirit_stones, GameStyle.JADE],
				["下一波收益", "+%d 枚" % GameBalance.harvest_gain(float(s.get("harvest", 0.0)))],
			]
	return rows
