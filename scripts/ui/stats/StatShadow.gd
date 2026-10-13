class_name StatShadow
extends RefCounted

## 属性影子（2026-10-12）：把「属性面板读数」与「加点落地」要碰的字段整份抄进一个
## 不挂树、不发信号、不进存档的临时对象，用来在玩家按下「确认选择」之前先把这一条
## 悟道加完，再走同一份聚合算式读出加后的数。
##
## 为什么要有它：铁律 6 是「渲染层只读状态」，卡面不许为了预览去动 GameManager 真身；
## 但预读又必须与真实结算同式 —— 上限、地板、羁绊乘区、闪避转暴击这些算式只要抄第二份，
## 调一次参数卡面承诺就跟实际到账分家（历史上文案与数值分家改一项动两个文件，已经踩过）。
## 所以这里不写任何算式，只搬数：落地走 StatSystem.apply_stat_fields(影子, apply)，
## 读数走 StatBreakdown.breakdown(影子)，两条都是真身在用的那一份。
##
## 字段名与 GameManager 逐一同名（动态取值按名字来）。少抄一个不会报错，只会读出一个
## 0 —— 由 tests/StatForecastCheck 的「影子 == 面板逐键相等」那一枪钉成红灯，
## 并且专挑上限吃得住的状态量（闪避 0.9、暴击 0.9），免得夹顶的算式漂了也没人管。

## 与 GameManager 同名的读数输入：from_gm 按这张表逐项取，新增消费方要在这里补名字
const COPIED: Array[String] = [
	# —— 加点直接落的字段（StatSystem 白名单）——
	"weapon_damage_mult", "melee_damage", "ranged_damage", "elemental_damage",
	"engineering_damage", "contraption_damage", "attack_speed_mult", "armor", "move_speed_mult",
	"attack_range_mult", "pickup_range_mult", "hp_regen", "crit_rate", "crit_mult",
	"dodge", "lifesteal", "luck", "harvest", "xp_gain_mult", "knockback_mult",
	"elite_damage", "free_rerolls", "shop_price_mult", "stat_bonus_pierce",
	"bonus_pierce", "thorns_pct", "chest_count_bonus", "chest_quality",
		"chest_reward_mult", "spirit_stones",
		"pet_damage_mult", "pet_effect_mult", "pet_cooldown_mult", "pet_slots_bonus",
		# —— 羁绊与技能乘区：影子不改它们，但读数要按同一式子合起来算 ——
	"synergy_damage_mult", "synergy_range_mult", "synergy_haste_mult",
	"synergy_crit_rate", "synergy_crit_mult", "synergy_hp_regen", "synergy_lifesteal",
	"synergy_move_speed_mult", "synergy_armor", "synergy_knockback_mult",
	"synergy_bonus_pierce", "shadow_amp_mult",
	"buff_attack_speed_mult", "buff_move_speed_mult", "buff_dodge", "dodge_cap_bonus",
]

# —— 上限与地板：真身是 const，影子按 var 带一份（from_gm 从真身取，不在此写死数字）——
var DODGE_CAP: float = 0.0
var CRIT_RATE_CAP: float = 0.0
var ATTACK_SPEED_FLOOR: float = 0.3

# —— 加点直接落的字段 ——
var weapon_damage_mult: float = 1.0
var melee_damage: float = 0.0
var ranged_damage: float = 0.0
var elemental_damage: float = 0.0
var engineering_damage: float = 0.0
var contraption_damage: float = 0.0
var attack_speed_mult: float = 1.0
var armor: float = 0.0
var move_speed_mult: float = 1.0
var attack_range_mult: float = 1.0
var pickup_range_mult: float = 1.0
var hp_regen: float = 0.0
var crit_rate: float = 0.05
var crit_mult: float = 1.5
var dodge: float = 0.0
var lifesteal: float = 0.0
var luck: float = 0.0
var harvest: float = 0.0
var xp_gain_mult: float = 1.0
var knockback_mult: float = 1.0
var elite_damage: float = 0.0
var free_rerolls: int = 0
var shop_price_mult: float = 1.0
var stat_bonus_pierce: int = 0
var bonus_pierce: int = 0
var thorns_pct: float = 0.0
var chest_count_bonus: int = 0
var chest_quality: float = 0.0
var chest_reward_mult: float = 1.0
var spirit_stones: int = 0
var pet_damage_mult: float = 1.0
var pet_effect_mult: float = 1.0
var pet_cooldown_mult: float = 1.0
var pet_slots_bonus: int = 0

# —— 羁绊 / 技能层 ——
var synergy_damage_mult: float = 1.0
var synergy_range_mult: float = 1.0
var synergy_haste_mult: float = 1.0
var synergy_crit_rate: float = 0.0
var synergy_crit_mult: float = 0.0
var synergy_hp_regen: float = 0.0
var synergy_lifesteal: float = 0.0
var synergy_move_speed_mult: float = 0.0
var synergy_armor: float = 0.0
var synergy_knockback_mult: float = 1.0
var synergy_bonus_pierce: int = 0
var shadow_amp_mult: float = 1.0
var buff_attack_speed_mult: float = 1.0
var buff_move_speed_mult: float = 1.0
var buff_dodge: float = 0.0
var dodge_cap_bonus: float = 0.0

## 生命与基础移速的载体：真身是 Player 节点，影子换成替身（见 PlayerMirror）
var player: Object = null
## 五行真解：Dictionary 按引用抄会让影子改到真身头上，from_gm 里单独 duplicate
var element_damage: Dictionary = {}
## 真身引用：只为借「道具钩子」这一类不随悟道变化的读数，影子自己不改它
var _real: Object = null

## 生命替身：只被当数读（current_health / max_health / base_speed），
## 外加 increase_max_hp 这一枪 —— 算式与 Player.increase_max_hp 同两行，
## 但不发 player_hp_changed、不挤压形变、不 spawn 跳字（那些是真身的事）。
class PlayerMirror extends RefCounted:
	var current_health: float = 120.0
	var max_health: float = 120.0
	var base_speed: float = 210.0

	func increase_max_hp(amount: float, heal_amount: float) -> void:
		max_health += amount
		current_health = minf(max_health, current_health + heal_amount)

static func from_gm(gm: Object) -> StatShadow:
	var s := StatShadow.new()
	s._real = gm
	for key in COPIED:
		s.set(key, gm.get(key))
	s.element_damage = gm.element_damage.duplicate()
	# 上限与地板走成员取值（真身上它们是 const，Object.get 取不到常量）
	s.DODGE_CAP = gm.DODGE_CAP
	s.CRIT_RATE_CAP = gm.CRIT_RATE_CAP
	s.ATTACK_SPEED_FLOOR = gm.ATTACK_SPEED_FLOOR
	var mir := PlayerMirror.new()
	if gm.player != null and is_instance_valid(gm.player):
		mir.current_health = float(gm.player.current_health)
		mir.max_health = float(gm.player.max_health)
		mir.base_speed = float(gm.player.base_speed)
	s.player = mir
	return s

## 与真身同式：两条算式都在 BalanceCombat，卡面预读与实际结算共用一份
func get_effective_dodge() -> float:
	return BalanceCombat.effective_dodge(dodge, buff_dodge, DODGE_CAP, dodge_cap_bonus)

func get_crit_rate() -> float:
	return BalanceCombat.crit_rate(
		crit_rate, synergy_crit_rate, item_hook_sum("crit_per_dodge"),
		get_effective_dodge(), CRIT_RATE_CAP)

## 道具不会因为一条悟道而增减：这一项直接借真身读数，影子不另存一份清单
func item_hook_sum(hook: String) -> float:
	if _real == null:
		return 0.0
	return float(_real.item_hook_sum(hook))

## 金币补给这类当场到账的项：影子只加数，不发 stats_updated（真身那条才要刷 HUD）
func add_spirit_stones(amount: int) -> void:
	spirit_stones += amount
