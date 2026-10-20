class_name StatForecast
extends RefCounted

## 悟道卡面的「当前 X → 加后 Y」（2026-10-12 用户指令：「加一条显示当前属性是多少，
## 增加后是多少」）。
##
## 一条预读怎么来的：抄一份属性影子（StatShadow）→ 在影子上走 StatSystem 那一份
## 落地算式 → 再走 StatBreakdown 那一份聚合算式读数。全程不碰 GameManager 真身
## （铁律 6：渲染层只读状态），也不写第二套公式：上限、地板、羁绊乘区、闪避转暴击
## 这些一旦在 UI 里另算一遍，调一次参数卡面就开始说假话。
##
## 只登记「属性面板有对应那一行」的字段：面板没有行的机制项（宝箱数量/品质、开箱省击、
## 单系元素伤）不硬凑一个玩家看不见的数字，卡面继续只写幅度 + desc 那句机制说明。
## 谁漏登记、谁多登记，由 tests/StatForecastCheck 逐条与面板对表钉住。

## apply 字段 → [StatBreakdown 读数键, 格式]。数字与属性面板那一行的主读数同源。
const BD_READINGS: Dictionary = {
	"weapon_damage_mult": ["damage_bonus_pct", "%+.0f%%"],
	"melee_damage": ["melee_damage", "%+.0f"],
	"ranged_damage": ["ranged_damage", "%+.0f"],
		"elemental_damage": ["elemental_damage", "%+.0f"],
		"engineering_damage": ["engineering_damage", "%+.0f"],
		"contraption_damage": ["contraption_damage", "%+.0f"],
		"attack_speed_mult_mul": ["cdr_pct", "%+.1f%%"],
	"armor": ["armor", "%.0f"],
	"move_speed_mult": ["move_speed", "%.0f"],
	"attack_range_mult": ["attack_range_pct", "%+.0f%%"],
	"hp_regen": ["hp_regen", "%.1f"],
	"crit_rate": ["crit_rate_pct", "%.0f%%"],
	"crit_mult": ["crit_dmg_pct", "%.0f%%"],
	"dodge": ["dodge_pct", "%.0f%%"],
	"lifesteal": ["lifesteal_pct", "%.0f%%"],
	"luck": ["luck", "%.0f"],
	"harvest": ["harvest", "%.0f"],
	"xp_gain_mult": ["xp_gain_pct", "%+.0f%%"],
	"elite_damage": ["elite_damage_pct", "%+.0f%%"],
	"free_rerolls": ["free_rerolls", "%d"],
	"shop_price_mul": ["shop_price_pct", "%+.0f%%"],
	"bonus_pierce": ["bonus_pierce", "%d"],
	"thorns": ["thorns_pct", "%.0f%%"],
	"max_hp": ["max_hp", "%.0f"],
	"hp_heal": ["current_hp", "%.0f"],
}

## 面板没有行、但当场就到账的账目：直接从影子读那个字段（金币走 add_spirit_stones）
const RAW_READINGS: Dictionary = {
	"spirit_stones": ["spirit_stones", "%d"],
}

## 一次开一屏候选只抄一份真身：before 读数与影子底版复用，逐条悟道再各复制一份影子
var _before: StatShadow = null
var _before_bd: Dictionary = {}

static func open() -> StatForecast:
	var f := StatForecast.new()
	f._before = StatShadow.from_gm(GameManager)
	f._before_bd = StatBreakdown.breakdown(f._before)
	return f

## 这条 apply 的预读行：按 apply 的键序返回 [{key, text, before, after, changed}]，
## 未登记的字段不出现（LevelUpDialog 据此在对应那条幅度行下面插一行小字）。
## before / after 是各自格式化后的读数：判据拿「到账前承诺的 after」去对「到账后重算的 before」，
## 链上任何一环（含 %d 取整、金币这类不走面板读数的字段）串不上就报红。
func lines_for(apply: Dictionary) -> Array[Dictionary]:
	var after := StatShadow.from_gm(GameManager)
	StatSystem.apply_stat_fields(after, apply, "forecast")
	var after_bd := StatBreakdown.breakdown(after)
	var out: Array[Dictionary] = []
	for key in apply.keys():
		var k := String(key)
		var src: Array = _reading_of(k)
		if src.is_empty():
			continue
		var kind := String(src[0])
		var fmt := String(src[2])
		var b := _txt(fmt, _read(k, kind, _before, _before_bd))
		var a := _txt(fmt, _read(k, kind, after, after_bd))
		out.append({
			"key": k,
			"text": "当前 %s → %s" % [b, a],
			"before": b,
			"after": a,
			"changed": b != a,
		})
	return out

## 这个字段有没有预读（判据用它核对「面板有行的字段都要登记」）
static func has_reading(key: String) -> bool:
	return BD_READINGS.has(key) or RAW_READINGS.has(key)

## 登记表：[读数源kind, 读数名, 格式]，未登记返回空表
static func _reading_of(key: String) -> Array:
	if BD_READINGS.has(key):
		return ["bd", BD_READINGS[key][0], BD_READINGS[key][1]]
	if RAW_READINGS.has(key):
		return ["raw", RAW_READINGS[key][0], RAW_READINGS[key][1]]
	return []

## 读数取哪一份：bd = 属性面板那个聚合键；raw = 影子上的原始字段（金币这类当场到账的账目）
static func _read(key: String, kind: String, shadow: StatShadow, bd: Dictionary):
	if kind == "raw":
		return shadow.get(String(RAW_READINGS[key][0]))
	return bd.get(String(BD_READINGS[key][0]), 0.0)

## 读数文本：%d 先取整（影子与 breakdown 里 int/float 混着，格式符不许吃错类型）
static func _txt(fmt: String, v) -> String:
	if fmt.contains("d"):
		return fmt % int(roundf(float(v)))
	return fmt % float(v)

## 判据入口：加完这一条之后的面板读数（与真身真实 apply 后的读数逐键对表用）
static func after_breakdown(apply: Dictionary) -> Dictionary:
	var after := StatShadow.from_gm(GameManager)
	StatSystem.apply_stat_fields(after, apply, "forecast")
	return StatBreakdown.breakdown(after)

## 判据入口：加这一条之前的面板读数（影子读的那一份，用来核对「影子 == 真身」）
func before_breakdown() -> Dictionary:
	return _before_bd
