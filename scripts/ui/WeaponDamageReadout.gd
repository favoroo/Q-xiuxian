class_name WeaponDamageReadout
extends RefCounted

## 武器伤害与节奏读数的唯一出口：回答玩家唯一关心的两个数 —— 这把武器本身多痛、我现在拿它多痛。
## 消费方：货架卡 ShopOfferCardFactory、商店详情 ShopWeaponTip、属性面板详情 StatsTipFactory。
## 三处必须同数，所以谁都不许自己再乘一遍乘区。
##
## 乘区链与运行时逐项同形（判据 tests/WeaponPerHitCheck 拿真武器节点的 _final_damage 对账）：
##   (基础 × 星级 + 属性加伤) × 全局法伤 × 流派羁绊 × 影层 [影者攒层时 >1] × 角色 × 五行 × 神识分流 [× 机关羁绊]
## 暴击按概率另算、斩将按目标另算，都不进这个数。
## 只读 GameManager 状态，不写任何状态。

## 神识分流口径：买下一把并上阵后所有武器的分流都会变差，货架卡要按「买下之后」的槽位数算，
## 否则卡上承诺的数在到手那一刻就兑现不了。槽位已满会进背包、不上阵，则维持现状。
static func slot_count_after_purchase() -> int:
	var used := GameManager.slots_used()
	return used + 1 if used < GameManager.max_weapon_slots() else used

## 单发真实伤害（不含暴击、不含斩将）。slot_count 传 -1 表示按当前上阵数。
## 御灵按半权计神识分流（与运行时 GameManager.get_multi_weapon_damage_mult 同口径）；
## 货架预览「买下之后」时若预览的是御灵，御灵把数同步 +1，卡面数才不会到手就缩水。
static func per_hit(w_id: String, star: int, slot_count: int = -1) -> float:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return 0.0
	var s := clampi(star, 1, WeaponData.MAX_STAR)
	var n := slot_count if slot_count > 0 else GameManager.slots_used()
	var drone_n := GameManager.drones.size()
	if slot_count > 0 and int(def.get("behavior", -1)) == WeaponData.Behavior.DRONE \
			and GameManager.slots_used() < GameManager.max_weapon_slots():
		drone_n += 1
	var raw: float = WeaponData.damage_for(w_id, s) + GameManager.get_weapon_stat_bonus(w_id, s)
	var mult: float = GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult \
			* GameManager.shadow_amp_mult \
			* GameManager.cultivator_damage_mult(w_id) * GameManager.element_damage_mult(w_id) \
			* GameBalance.multi_weapon_damage_mult(n, drone_n)
	if is_turret(def):
		mult *= GameManager.synergy_contraption_mult
	return raw * mult

## 攻速乘区：悟道/羁绊常驻、疾风咒短时施法间隔、站定神像。与 FloatingWeapon 的 cooldown_timer 同一条式子。
static func haste_product() -> float:
	return GameManager.get_effective_attack_speed_mult()

## 射程乘区：全局攻击范围 × 剑系羁绊 ×（近战/横扫专有范围乘区，如剑气凌霄、开山重刃谱）。
## 消费方：FloatingWeapon._range_mult、Player._update_weapon_targets、ShopWeaponTip、StatsTipFactory。
static func range_mult_for(w_id: String) -> float:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return GameManager.attack_range_mult * GameManager.synergy_range_mult
	var mult: float = GameManager.attack_range_mult * GameManager.synergy_range_mult
	var b := int(def.get("behavior", WeaponData.Behavior.MELEE))
	if b == WeaponData.Behavior.MELEE or b == WeaponData.Behavior.SWEEP:
		var qi_bonus: float = 1.0 + float(StatSystem.super_hook_snapshot(GameManager).get("melee_range_mult", 0.0))
		mult *= qi_bonus
		var tags: Array = def.get("tags", [])
		if tags.has("wide"):
			var wide_bonus: float = 1.0 + GameManager.item_hook_sum("wide_range_mult")
			mult *= wide_bonus
	return mult

## 某把武器当前形态下的有效射程（基础射程 × 射程乘区）。
static func effective_range(w_id: String) -> float:
	var def := WeaponData.get_def(w_id)
	return float(def.get("range", 0.0)) * range_mult_for(w_id)

## 你现在的实际攻击间隔（数据表值 × 攻速乘区）。与 FloatingWeapon 的 cooldown_timer 同一条式子。
static func effective_cd(w_id: String, star: int) -> float:
	return WeaponData.cooldown_for(w_id, clampi(star, 1, WeaponData.MAX_STAR)) * haste_product()

## 每秒伤害（对孤立目标的实伤口径）。
## 借用平衡判据 WeaponData.sustained_single_dps 的「形状」——它已经处理好了炮台自身的开火间隔、
## 多发弹丸对单目标的上限、环绕灵宝的接触占空比税与灼烧剧毒常驻量；那条函数每个分支都对
## 伤害一次齐次（各项都是 dmg × 常数），所以按 per_hit ÷ 基础伤害折算比例是精确值而非近似，
## 卡面与平衡判据因此共用同一把尺子。
static func per_second(w_id: String, star: int, slot_count: int = -1) -> float:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return 0.0
	var s := clampi(star, 1, WeaponData.MAX_STAR)
	var base: float = WeaponData.damage_for(w_id, s)
	var haste := haste_product()
	if base <= 0.0 or haste <= 0.0:
		return 0.0
	## sustained_single_dps 按数据表间隔算，攻速乘区把节奏整体提快 1/haste 倍
	## （机关武器同理：炮台开火间隔吃的是同一条攻速）
	return WeaponData.sustained_single_dps(w_id, s) * (per_hit(w_id, s, slot_count) / base) / haste

## 机关武器的炮台是「多座各自开火」，平衡判据本身就不给它进 DPS 档，这里也不替它聚合，
## 所以那一行必须叫「单座每秒伤害」，不能和别的武器的「每秒伤害」混成同一个词。
## 行名一律带「伤害」两字收尾（2026-10-11 用户：光写「每秒」没人知道是什么的每秒）：
## 卡面上「伤害 26 → 31.1」与「每秒伤害 31.6」是同一把武器的两个不同口径，
## 少了名词这两行看着像同一个数写了两遍。
static func per_second_label(w_id: String) -> String:
	return "单座每秒伤害" if is_turret(WeaponData.get_def(w_id)) else "每秒伤害"

## 「纸面 → 你现在」一行话。两数相同就只写纸面值，不多画一个箭头骗人。
## digits: -1 走 BonusRows 的整数不带小数口径；间隔这类要两位小数的传 2。
static func arrow_text(base: float, actual: float, digits: int = -1) -> String:
	if absf(actual - base) < 0.05:
		return _num(base, digits)
	return "%s → %s" % [_num(base, digits), _num(actual, digits)]

## 属性加伤账单：[["近战伤害", 6.0], ["元素伤害", 3.0], ...]，按贡献从大到小，只列真给了伤害的项。
## 单位是「伤害」，不是系数百分比 —— 系数按百分比印出来会把 armor 3.5 写成「护甲(+4%)」、
## 把 max_hp_bonus 0.12 四舍五入成「额外生命(+0%)」，玩家据此判断这把吃不吃生命，必错。
static func bonus_bill(w_id: String, star: int) -> Array:
	var def := WeaponData.get_def(w_id)
	var parts: Dictionary = GameBalance.weapon_stat_bonus_parts(
			def.get("stat_scalings", {}), GameManager.get_player_stat_dict(),
			clampi(star, 1, WeaponData.MAX_STAR))
	var rows: Array = []
	for key in parts.keys():
		var v := float(parts[key])
		if v > 0.05:
			rows.append([GameBalance.stat_scaling_label(String(key)), v])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return rows

## 神识分流系数（详情面板要把每个乘区逐行列出来，必须从这里取，别自己再算一遍）。
## w_id 传御灵 id 时按半权口径（运行时 SunOrb 吃的就是这个数）。
static func slot_split_mult(slot_count: int = -1, w_id: String = "") -> float:
	var n := GameManager.slots_used() if slot_count <= 0 else slot_count
	var drone_n := GameManager.drones.size()
	if slot_count > 0 and int(WeaponData.get_def(w_id).get("behavior", -1)) == WeaponData.Behavior.DRONE \
			and GameManager.slots_used() < GameManager.max_weapon_slots():
		drone_n += 1
	return GameBalance.multi_weapon_damage_mult(n, drone_n)

## 机关羁绊：只有机关类武器吃这一档，详情面板对别的武器不许列这一行
static func contraption_mult() -> float:
	return GameManager.synergy_contraption_mult

## 账单整句（两处详情弹窗共用一句，别各写一份）：
## 「你的属性让它每下多打 +10：近战伤害 +6、元素伤害 +3、范围加成 +1。」
static func bonus_bill_text(w_id: String, star: int) -> String:
	var bill := bonus_bill(w_id, star)
	if bill.is_empty():
		return "不吃任何属性加成，伤害只由基础值与星级决定。"
	var parts: Array[String] = []
	for r in bill:
		parts.append("%s +%s" % [String(r[0]), BonusRows.fmt_num(float(r[1]))])
	var total: float = GameManager.get_weapon_stat_bonus(w_id, star)
	return "每下多打 +%s：%s（★ 越高吃得越多，属性加伤每星 +25%%）" % [
		BonusRows.fmt_num(total), "、".join(parts)]

static func is_turret(def: Dictionary) -> bool:
	return int(def.get("behavior", WeaponData.Behavior.MELEE)) == WeaponData.Behavior.TURRET

static func _num(v: float, digits: int) -> String:
	if digits < 0:
		return BonusRows.fmt_num(v)
	return (("%%.%df" % digits) % v)
