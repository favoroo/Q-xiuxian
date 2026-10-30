class_name StatSystem
extends RefCounted

## 属性字段统一落地子系统（2026-10-11 从 GameManager._apply_stat_fields 抽离）：
## 悟道加点（apply_upgrade）与道具（add_item）共用同一条链路，这里只规定「往哪个字段加、有没有上限」，
## 幅度全部来自 UpgradeData/ItemData 每项的 "apply" 表（数值与文案同源，调参只改数据表一处）。
## 字段白名单见 GameBalance.upgrade_fields()，表上写了不认得的键会在这里 push_warning 暴露。
## 2026-10-15 追加读侧：item_hook_sum / has_still_mechanic / 属性投影三件套同步迁入，
## GameManager 侧保留单行转发（调用点零改动），缓存字段仍留 gm 身上。
##
## 参数收 Object：target 除了 GameManager 真身，还可以是 StatShadow（属性影子，不挂树、
## 不发信号的字段快照）。悟道卡面要在玩家点「确认选择」之前先算一遍「加后是多少」，
## 走的必须就是这里这一份落地算式 —— 另写一份预读算术，卡面承诺与结算迟早分家。
## 影子把 player 换成替身、add_spirit_stones 只加数不发信号，所以这一条链路对影子是安全的。

## 判「读数是不是正夹在顶/底上」的容差：属性是 float，夹顶那一步是 min/max 出来的，
## 差 1e-9 就判成没夹住 ⇒ 该原样留下的值被扣掉一份（白罚）。留一档比浮点误差大、
## 比任何一条加成幅度小得多的余量。
const CLAMP_EPS := 0.0001

## 代偿折扣比例（2026-10-21）：一份 apply 里带 `shop_price_mul` 时，物价腿会被
## `SHOP_PRICE_FLOOR` 夹住 —— 夹掉的那一份是玩家按下却没拿到的收益，照收整份代偿就是白罚。
## 口径：代偿只按「真省下来的那一份」扣 = 实际降幅 / 名义降幅（1.0 = 完整落地，0.0 = 一分没省）。
## 只压负值代偿腿；乘算腿（unit == "pctmul"，物价/攻击间隔/灵兽冷却）的"变差"写作 v > 1，不在这条闸里。
## ⚠ 卖出回退（revert_stat_fields）按名义值整份退，所以**限购/可卖道具不许在同一份 apply 里
##    既带 shop_price_mul 又带负代偿腿** —— tests/BalanceSimCheck 6.2 逐件钉着这条。
static func cost_scale(gm: Object, apply: Dictionary) -> float:
	if not apply.has("shop_price_mul"):
		return 1.0
	var old: float = float(gm.shop_price_mult)
	var v: float = float(apply["shop_price_mul"])
	var nominal: float = old * (1.0 - v)
	if nominal <= CLAMP_EPS:
		return 1.0
	var realized: float = old - maxf(gm.SHOP_PRICE_FLOOR, old * v)
	return clampf(realized / nominal, 0.0, 1.0)

static func apply_stat_fields(gm: Object, apply: Dictionary, source: String) -> void:
	var scale: float = cost_scale(gm, apply)
	for key in apply.keys():
		var v: float = float(apply[key])
		# 物价腿被地板夹了一部分 ⇒ 同一份里的负代偿腿按比例少扣（见 cost_scale）
		if scale < 1.0 - CLAMP_EPS and v < 0.0 and StatInfoData.field_unit(key) != "pctmul":
			v *= scale
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
			"fog_vision_bonus":
				gm.fog_vision_bonus += v
			"hp_regen":
				gm.hp_regen += v
			"crit_rate":
				gm.crit_rate = minf(gm.crit_rate + v, gm.CRIT_RATE_CAP)
			"crit_mult":
				gm.crit_mult = minf(gm.crit_mult + v, gm.CRIT_MULT_CAP)
			"dodge":
				gm.dodge = minf(gm.dodge + v, gm.DODGE_CAP + gm.dodge_cap_bonus)
			"lifesteal":
				gm.lifesteal = minf(gm.lifesteal + v, gm.LIFESTEAL_CAP)
			"luck":
				gm.luck += v
			"harvest":
				gm.harvest += v
			"spirit_stones":
				gm.add_spirit_stones(int(v))
			"max_hp":
				if gm.player and gm.player.has_method("increase_max_hp"):
					# 负上限（五行砂/幻纱）走缩上限，不要冒一条「+0 HP」的伤害数字。
					if v < 0.0 and gm.player.has_method("decrease_max_hp"):
						gm.player.decrease_max_hp(-v)
					else:
						gm.player.increase_max_hp(v, float(apply.get("hp_heal", 0.0)))
			"hp_heal":
				pass  # 已随 max_hp 一起结算
			"xp_gain_mult":
				gm.xp_gain_mult += v
			"knockback_mult":
				gm.knockback_mult += v
			"elite_damage":
				gm.elite_damage = minf(gm.elite_damage + v, gm.ELITE_DAMAGE_CAP)
			"free_rerolls":
				gm.free_rerolls += int(v)
			"revive_charges":
				gm.revive_charges += int(v)
			"shop_price_mul":
				# 道具折扣腿带地板（对标土豆 Coupon 叠顶）：角色价格乘区在别处结算、不夹
				gm.shop_price_mult = maxf(gm.SHOP_PRICE_FLOOR, gm.shop_price_mult * v)
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
			"skill_cooldown_mult":
				gm.skill_cooldown_mult = minf(gm.SKILL_CD_CAP, gm.skill_cooldown_mult + v)
			"element_damage_all":
				for e in WeaponData.ELEMENTS:
					gm.element_damage[e] = minf(float(gm.element_damage.get(e, 0.0)) + v, gm.ELEMENT_DAMAGE_CAP)
			_:
				# element_damage_metal / _wood / _water / _fire / _earth：单元素加成
				if key.begins_with("element_damage_") and key.trim_prefix("element_damage_") in WeaponData.ELEMENTS:
					var elem: String = key.trim_prefix("element_damage_")
					gm.element_damage[elem] = minf(float(gm.element_damage.get(elem, 0.0)) + v, gm.ELEMENT_DAMAGE_CAP)
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
			"fog_vision_bonus":
				gm.fog_vision_bonus -= v
			"hp_regen":
				gm.hp_regen -= v
			"crit_rate":
				gm.crit_rate = undo_capped_add(gm.crit_rate, v, gm.CRIT_RATE_CAP)
			"crit_mult":
				gm.crit_mult = undo_capped_add(gm.crit_mult, v, gm.CRIT_MULT_CAP)
			"dodge":
				gm.dodge = undo_capped_add(gm.dodge, v, gm.DODGE_CAP + gm.dodge_cap_bonus)
			"lifesteal":
				gm.lifesteal = undo_capped_add(gm.lifesteal, v, gm.LIFESTEAL_CAP)
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
				gm.elite_damage = undo_capped_add(gm.elite_damage, v, gm.ELITE_DAMAGE_CAP)
			"free_rerolls":
				gm.free_rerolls -= int(v)
			"revive_charges":
				gm.revive_charges = maxi(0, gm.revive_charges - int(v))
			"shop_price_mul":
				if v > 0.0:
					gm.shop_price_mult = undo_mult(gm.shop_price_mult, v, gm.SHOP_PRICE_FLOOR)
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
			"skill_cooldown_mult":
				gm.skill_cooldown_mult = maxf(0.0, undo_capped_add(gm.skill_cooldown_mult, v, gm.SKILL_CD_CAP))
			"element_damage_all":
				for e in WeaponData.ELEMENTS:
					gm.element_damage[e] = undo_capped_add(float(gm.element_damage.get(e, 0.0)), v, gm.ELEMENT_DAMAGE_CAP)
			_:
				# element_damage_metal / _wood / _water / _fire / _earth：单元素加成
				if key.begins_with("element_damage_") and key.trim_prefix("element_damage_") in WeaponData.ELEMENTS:
					var elem: String = key.trim_prefix("element_damage_")
					gm.element_damage[elem] = undo_capped_add(float(gm.element_damage.get(elem, 0.0)), v, gm.ELEMENT_DAMAGE_CAP)
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

# ---------------- 读侧：道具 hook 求和与属性投影（2026-10-15 从 GameManager 迁出） ----------------
## 写侧（上面的 apply/revert）与读侧（hook 求和、20 键属性字典）同住一文件：
## 悟道卡面「当前 X → 加后 Y」= 影子 StatShadow 在同一份落地算式上预读，读侧投影
## 与写侧落地共享字段名口径，拆开迟早漂移。缓存字段（_hook_cache / _stat_dict_frame）
## 仍留在 gm 身上（RunReset/gm 自身三处失效点不动），这里只按 gm 的字段读写。

## 同名字段 hook 的叠加求和（如多件回春葫芦的 wave_heal_pct 相加）。
## 走 _hook_cache 避免每次弹丸命中 3~4 次 O(items) 全表扫描。
## 失效判据用 Array.hash() 内容指纹（2026-10-24）：原先只比 items.size()，「卖出 A 买入 B」
## 数量不变会命中陈旧缓存读错数值（正确性 bug 兼性能问题）；指纹在 C++ 侧一次算完，
## 兼容测试里直接 items.clear() 的写法（空表指纹 ≠ 旧指纹照常失效）。
## 字段名 _hook_cache_items_size 沿用（gm 上已有、三处失效点不动），值语义从 size 改为指纹。
static func item_hook_sum(gm: Object, hook: String) -> float:
	var stamp: int = gm.items.hash()
	if stamp != gm._hook_cache_items_size:
		gm._hook_cache.clear()
		gm._hook_cache_items_size = stamp
	if gm._hook_cache.has(hook):
		return float(gm._hook_cache[hook])
	var total := 0.0
	for item_id in gm.items:
		total += float(ItemData.get_def(item_id).get(hook, 0.0))
	gm._hook_cache[hook] = total
	return total

## 超级悟道机制卡的 hook 快照（2026-10-25）：一次指纹校验取出全部机制读数。
## 为什么要这一层：命中路径（近战每目标、弹丸每发、束流每 tick）要读 3~4 个 hook，
## 逐个调 item_hook_sum 就是每命中一次算 3~4 遍 items.hash()。束流 tick 10+ 次/秒 ×
## 多目标时会被放大成每秒上千次指纹计算（PerfProbe 的 12ms 预算里是实打实的开销）。
## 这里按同一个指纹算一遍、整包缓存，命中路径只做字典查找。
## 返回字典的键与下面的读取清单一一对应；新增机制字段记得加到这里。
static func super_hook_snapshot(gm: Object) -> Dictionary:
	var stamp: int = gm.items.hash()
	if gm._super_hook_stamp == stamp and not gm._super_hook_snap.is_empty():
		return gm._super_hook_snap
	gm._super_hook_stamp = stamp
	# 统一走一次 items 遍历，避免每个字段各扫一遍
	var totals := {}
	for item_id in gm.items:
		var d := ItemData.get_def(String(item_id))
		if d.is_empty():
			continue
		for k in SUPER_HOOK_KEYS:
			if d.has(k):
				totals[k] = float(totals.get(k, 0.0)) + float(d[k])
	var snap := {}
	for k in SUPER_HOOK_KEYS:
		snap[k] = float(totals.get(k, 0.0))
	gm._super_hook_snap = snap
	return snap

## 超级悟道机制字段清单（super_hook_snapshot 的键）。
## 只收「命中/出手/受击高频路径」会读的字段；其余低频 hook 继续走 item_hook_sum。
const SUPER_HOOK_KEYS: Array[String] = [
	"wuxing_rotation_chance", "crit_sky_bolt", "projectile_chain_lightning",
	"sword_qi", "attack_chain_lightning", "kill_chain_lightning",
	"thorns_electric", "chain_hop_bonus", "melee_range_mult",
	"projectile_count_bonus", "projectile_bounce_bonus", "projectile_damage_mult",
	# 二阶段（2026-10-25）：箭雨 / 血盾 / 五行归一 / 兽群 / 灵蕴五行
	"arrow_rain_every", "lifesteal_overflow_shield", "wuxing_all",
	"pet_chain_lightning", "pet_wuxing_chance",
	# 伤害转化乘区（2026-10-28）：CultivatorSystem.damage_mult 原本逐字段调 item_hook_sum，
	# 一次伤害读数要算 14 遍 items.hash()（每次命中都在跑，束流/环绕灵宝多目标时被放大）。
	# 并进本快照后同一次伤害只做一次指纹校验 + 字典查找。
	"dmg_per_move_speed", "dmg_per_armor", "dmg_per_100_stones", "stone_dmg_cap",
	"still_damage", "still_seconds", "dmg_per_empty_slot",
	"dmg_per_max_hp", "dmg_per_missing_hp", "on_hit_damage_bonus",
	"dmg_per_unique_item", "dmg_per_unique_item_cap",
	"dmg_per_nearby_enemy", "dmg_per_nearby_enemy_cap",
]

## 站定流机制是否激活：苦行僧模式或任一站定流法宝在场。
## 结果只在道具变化时变，缓存随 item_hook_sum 同一套失效点。
static func has_still_mechanic(gm: Object) -> bool:
	if not gm._still_cache_valid:
		gm._still_cached = gm.kuxingseng_mode > 0.0 \
			or item_hook_sum(gm, "still_damage") > 0.0 or item_hook_sum(gm, "still_regen_pct") > 0.0 \
			or item_hook_sum(gm, "still_dodge") > 0.0 or item_hook_sum(gm, "still_armor") > 0.0 \
			or item_hook_sum(gm, "still_thorns") > 0.0 or item_hook_sum(gm, "still_knockback") > 0.0 \
			or item_hook_sum(gm, "still_attack_speed") > 0.0
		gm._still_cache_valid = true
	return gm._still_cached

## 20 键属性投影：武器折算与 UI 读数共用的快照（GameManager.get_player_stat_dict 转发到这里）。
## 玩家未生成时的兜底读数一律取 Player 的基础常量，不许再写一份字面量。
static func player_stat_dict(gm: Object) -> Dictionary:
	var cur_hp := Player.BASE_MAX_HEALTH
	var max_hp := Player.BASE_MAX_HEALTH
	if gm.player != null and is_instance_valid(gm.player):
		cur_hp = gm.player.current_health
		max_hp = gm.player.max_health
	return {
		"armor": gm.armor + gm.synergy_armor,
		"max_hp": max_hp,
		"current_hp": cur_hp,
		"hp_regen": gm.hp_regen + gm.synergy_hp_regen,
		"lifesteal": gm.lifesteal + gm.synergy_lifesteal,
		"crit_rate": gm.get_crit_rate(),
		"crit_mult": gm.crit_mult + gm.synergy_crit_mult,
		"attack_speed_mult": gm.attack_speed_mult * gm.synergy_haste_mult,
		"move_speed_mult": gm.move_speed_mult + gm.synergy_move_speed_mult,
		"weapon_damage_mult": gm.get_weapon_damage_mult() * gm.synergy_damage_mult,
		"attack_range_mult": gm.attack_range_mult * gm.synergy_range_mult,
		"melee_damage": gm.melee_damage,
		# 弹射羁绊的远程伤害加成并进同一键（武器 stat_scalings["ranged_damage"] 直接吃到）
		"ranged_damage": gm.ranged_damage + gm.synergy_ranged_damage,
		"elemental_damage": gm.elemental_damage,
		"engineering_damage": gm.engineering_damage + gm.synergy_engineering_damage,
		"contraption_damage": gm.contraption_damage,
		"harvest": gm.harvest,
		"pet_damage_mult": gm.pet_damage_mult,
		"pet_effect_mult": gm.pet_effect_mult,
		"pet_cooldown_mult": gm.pet_cooldown_mult,
	}

## 武器折算专用的属性快照（每物理帧重建一次，同帧共享）：
## FloatingWeapon/TurretUnit 每次开火都经 get_weapon_stat_bonus 构建 20 键字典，
## 多武器齐射时同一物理帧内重复构建，按物理帧号缓存一份。UI 直接调 player_stat_dict
## 的调用点不走 memo，保证 current_hp 永远实时。
static func stat_dict_for_weapons(gm: Object) -> Dictionary:
	var f := Engine.get_physics_frames()
	if f != gm._stat_dict_frame:
		gm._stat_dict_frame = f
		gm._stat_dict_memo = player_stat_dict(gm)
	return gm._stat_dict_memo

## 武器属性折算加成：weapon 表的 stat_scalings × 属性快照 × 星级（GameBalance 唯一算式）
static func weapon_stat_bonus(gm: Object, w_id: String, star: int = 1) -> float:
	var def := WeaponData.get_def(w_id)
	# 先判键存在再 get 默认值：默认值 {} 字面量每次调用都要分配一个空字典
	if not def.has("stat_scalings"):
		return 0.0
	var scalings: Dictionary = def["stat_scalings"]
	if scalings.is_empty():
		return 0.0
	return GameBalance.weapon_stat_bonus(scalings, stat_dict_for_weapons(gm), star)
