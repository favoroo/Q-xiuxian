class_name StatSystem
extends RefCounted

## 属性字段统一落地子系统（2026-10-11 从 GameManager._apply_stat_fields 抽离）：
## 悟道加点（apply_upgrade）与道具（add_item）共用同一条链路，这里只规定「往哪个字段加、有没有上限」，
## 幅度全部来自 UpgradeData/ItemData 每项的 "apply" 表（数值与文案同源，调参只改数据表一处）。
## 字段白名单见 GameBalance.upgrade_fields()，表上写了不认得的键会在这里 push_warning 暴露。
##
## 参数收 Object：target 除了 GameManager 真身，还可以是 StatShadow（属性影子，不挂树、
## 不发信号的字段快照）。悟道卡面要在玩家点「确认选择」之前先算一遍「加后是多少」，
## 走的必须就是这里这一份落地算式 —— 另写一份预读算术，卡面承诺与结算迟早分家。
## 影子把 player 换成替身、add_spirit_stones 只加数不发信号，所以这一条链路对影子是安全的。

## 判「读数是不是正夹在顶/底上」的容差：属性是 float，夹顶那一步是 min/max 出来的，
## 差 1e-9 就判成没夹住 ⇒ 该原样留下的值被扣掉一份（白罚）。留一档比浮点误差大、
## 比任何一条加成幅度小得多的余量。
const CLAMP_EPS := 0.0001

static func apply_stat_fields(gm: Object, apply: Dictionary, source: String) -> void:
	for key in apply.keys():
		var v: float = float(apply[key])
		match key:
			"weapon_damage_mult":
				gm.weapon_damage_mult += v
			"melee_damage":
				gm.melee_damage += v
			"ranged_damage":
				gm.ranged_damage += v
			"elemental_damage":
				gm.elemental_damage += v
			"engineering_damage":
				gm.engineering_damage += v
			"contraption_damage":
				gm.contraption_damage += v
			"attack_speed_mult_mul":
				gm.attack_speed_mult = maxf(gm.ATTACK_SPEED_FLOOR, gm.attack_speed_mult * v)
			"armor":
				gm.armor += v
			"move_speed_mult":
				gm.move_speed_mult += v
			"attack_range_mult":
				gm.attack_range_mult += v
			"pickup_range_mult":
				gm.pickup_range_mult += v
			"hp_regen":
				gm.hp_regen += v
			"crit_rate":
				gm.crit_rate = minf(gm.crit_rate + v, gm.CRIT_RATE_CAP)
			"crit_mult":
				gm.crit_mult += v
			"dodge":
				gm.dodge = minf(gm.dodge + v, gm.DODGE_CAP + gm.dodge_cap_bonus)
			"lifesteal":
				gm.lifesteal += v
			"luck":
				gm.luck += v
			"harvest":
				gm.harvest += v
			"spirit_stones":
				gm.add_spirit_stones(int(v))
			"max_hp":
				if gm.player and gm.player.has_method("increase_max_hp"):
					gm.player.increase_max_hp(v, float(apply.get("hp_heal", 0.0)))
			"hp_heal":
				pass  # 已随 max_hp 一起结算
			"xp_gain_mult":
				gm.xp_gain_mult += v
			"knockback_mult":
				gm.knockback_mult += v
			"elite_damage":
				gm.elite_damage += v
			"free_rerolls":
				gm.free_rerolls += int(v)
			"shop_price_mul":
				gm.shop_price_mult *= v
			"bonus_pierce":
				gm.stat_bonus_pierce += int(v)
				gm.bonus_pierce = gm.stat_bonus_pierce + gm.synergy_bonus_pierce
			"thorns":
				gm.thorns_pct += v
			"chest_count":
				gm.chest_count_bonus += int(v)
			"chest_quality":
				gm.chest_quality += v
			"chest_reward":
				gm.chest_reward_mult += v
			"pet_damage_mult":
				gm.pet_damage_mult += v
			"pet_effect_mult":
				gm.pet_effect_mult += v
			"pet_cooldown_mult_mul":
				gm.pet_cooldown_mult = maxf(0.2, gm.pet_cooldown_mult * v)
			"pet_slots":
				gm.pet_slots_bonus += int(v)
			"element_damage_all":
				for e in WeaponData.ELEMENTS:
					gm.element_damage[e] = float(gm.element_damage.get(e, 0.0)) + v
			_:
				# element_damage_metal / _wood / _water / _fire / _earth：单元素加成
				if key.begins_with("element_damage_") and key.trim_prefix("element_damage_") in WeaponData.ELEMENTS:
					var elem: String = key.trim_prefix("element_damage_")
					gm.element_damage[elem] = float(gm.element_damage.get(elem, 0.0)) + v
				else:
					push_warning("apply_stat_fields: 未知加点字段 %s（来自 %s）" % [key, source])

## 出售回退：把 add_item 落过的那一份 apply 表原样退回去（apply_stat_fields 的反向操作）。
## 三条口径：
## ① 加法项照减；乘法项（attack_speed_mult_mul / shop_price_mul / pet_cooldown_mult_mul）照除 ——
##    正向是乘，反向写成减法会把「折扣券可叠加」这类乘区算成两份。
## ② 被上限/地板夹过的项，只在「能证明这一份完整落地了」的时候才扣：正向 min(x+v, cap) 之后读数
##    还停在 cap 上，就说明这一份被上限吃掉过、吃掉多少无从得知 ⇒ 一分不扣。
##    宁可少扣，也不许把没兑现的加回去的东西再收回（按下没给到的，不该收代价）。
## ③ 新增 apply 字段必须在这里补一条反向分支：tests/ItemSellCheck 逐件道具「买入 → 卖出 →
##    全字段回到原值」，漏一条就报红，不靠人记得。
static func revert_stat_fields(gm: Object, apply: Dictionary, source: String) -> void:
	for key in apply.keys():
		var v: float = float(apply[key])
		match key:
			"weapon_damage_mult":
				gm.weapon_damage_mult -= v
			"melee_damage":
				gm.melee_damage -= v
			"ranged_damage":
				gm.ranged_damage -= v
			"elemental_damage":
				gm.elemental_damage -= v
			"engineering_damage":
				gm.engineering_damage -= v
			"contraption_damage":
				gm.contraption_damage -= v
			"attack_speed_mult_mul":
				gm.attack_speed_mult = undo_mult(gm.attack_speed_mult, v, gm.ATTACK_SPEED_FLOOR)
			"armor":
				gm.armor -= v
			"move_speed_mult":
				gm.move_speed_mult -= v
			"attack_range_mult":
				gm.attack_range_mult -= v
			"pickup_range_mult":
				gm.pickup_range_mult -= v
			"hp_regen":
				gm.hp_regen -= v
			"crit_rate":
				gm.crit_rate = undo_capped_add(gm.crit_rate, v, gm.CRIT_RATE_CAP)
			"crit_mult":
				gm.crit_mult -= v
			"dodge":
				gm.dodge = undo_capped_add(gm.dodge, v, gm.DODGE_CAP + gm.dodge_cap_bonus)
			"lifesteal":
				gm.lifesteal -= v
			"luck":
				gm.luck -= v
			"harvest":
				gm.harvest -= v
			"spirit_stones":
				gm.add_spirit_stones(-int(v))
			"max_hp":
				# 买时随 max_hp 一起结算的那一口治疗不退（血已经回了），只把上限缩回去并截平当前血
				if gm.player != null and is_instance_valid(gm.player) and gm.player.has_method("decrease_max_hp"):
					gm.player.decrease_max_hp(v)
			"hp_heal":
				pass  # 已随 max_hp 一起回退
			"xp_gain_mult":
				gm.xp_gain_mult -= v
			"knockback_mult":
				gm.knockback_mult -= v
			"elite_damage":
				gm.elite_damage -= v
			"free_rerolls":
				gm.free_rerolls -= int(v)
			"shop_price_mul":
				if v > 0.0:
					gm.shop_price_mult /= v
			"bonus_pierce":
				gm.stat_bonus_pierce -= int(v)
				gm.bonus_pierce = gm.stat_bonus_pierce + gm.synergy_bonus_pierce
			"thorns":
				gm.thorns_pct -= v
			"chest_count":
				gm.chest_count_bonus -= int(v)
			"chest_quality":
				gm.chest_quality -= v
			"chest_reward":
				gm.chest_reward_mult -= v
			"pet_damage_mult":
				gm.pet_damage_mult -= v
			"pet_effect_mult":
				gm.pet_effect_mult -= v
			"pet_cooldown_mult_mul":
				gm.pet_cooldown_mult = undo_mult(gm.pet_cooldown_mult, v, 0.2)
			"pet_slots":
				gm.pet_slots_bonus -= int(v)
			"element_damage_all":
				for e in WeaponData.ELEMENTS:
					gm.element_damage[e] = float(gm.element_damage.get(e, 0.0)) - v
			_:
				# element_damage_metal / _wood / _water / _fire / _earth：单元素加成
				if key.begins_with("element_damage_") and key.trim_prefix("element_damage_") in WeaponData.ELEMENTS:
					var elem: String = key.trim_prefix("element_damage_")
					gm.element_damage[elem] = float(gm.element_damage.get(elem, 0.0)) - v
				else:
					push_warning("revert_stat_fields: 未知字段 %s（来自 %s）—— 出售回退漏了这一项" % [key, source])

## 反向夹取（上限）：正向 after = min(before + v, cap)。after 还停在 cap 上 ⇒ before 落在
## [cap − v, +∞) 这一段里无从分辨，原样不动；after 低于 cap ⇒ 没被夹过，照减就是精确的 before。
static func undo_capped_add(cur: float, v: float, cap: float) -> float:
	if cur >= cap - CLAMP_EPS:
		return cur
	return cur - v

## 反向夹取（地板 + 乘法）：正向 after = max(floor, before × v)。after 落在地板上 ⇒ 这一份被
## 地板吃掉过，不动；否则照除还原。v ≤ 0 是脏数据，除法会炸，直接不动。
static func undo_mult(cur: float, v: float, floor: float) -> float:
	if v <= 0.0:
		return cur
	if cur <= floor + CLAMP_EPS:
		return cur
	return cur / v
