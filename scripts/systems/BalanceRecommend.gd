class_name BalanceRecommend
extends RefCounted

## 推荐打分数值：悟道加点候选与商店货架的「荐」标判定。
## 全部 static 纯函数，与 GameBalance 同规约：不读 autoload、不碰节点、无随机
## （打分必须确定性，判据可复现；需要 GM 状态一律由 RecommendSystem 收集成 ctx 传进来）。
##
## 设计原则：不拍脑袋定「攻击好还是防御好」，而是把候选的 apply 增量按 StatSystem 同一套语义
## 模拟叠进玩家属性快照，再用与伤害结算同源的折算（weapon_stat_bonus_parts / sustained_single_dps /
## 五行乘区 / 神识分流）量化「这条加成对当前 build 的边际收益」，其余因子只做修正。
##
## 总分 = W_BUILD×B(构建边际收益) + W_FIT×A(角色契合) + W_SYN×C(流派协同) + W_TIMING×D(时机)
##   B 把候选拿手的轴（伤害/生存/经济/功能）取最大：混合加成不会重复计分，负代偿按半价折损。
##   A 从 CultivatorData 程序化推导（mods 正收益键 + 流派偏好武器吃的属性），不手抄 15 份角色表。
##   C 武器候选看羁绊档位进度与三合一；加点/道具候选看五行真解与上阵武器的元素契合。
##   D 货架候选买不起打 85 折（值得攒钱但不抢「现在能买」的推荐位）；回气丹按缺血程度单独计。
##
## ctx 契约（RecommendSystem.build_ctx 产出，判据测试手工构造同形字典）：
##   stats          Dictionary  玩家属性快照（get_player_stat_dict + dodge/luck/xp_gain_mult/thorns）
##   element_damage Dictionary  五行真解 {元素tag: 加成}
##   weapons        Array       上阵武器 [{id, star}]（含灵蝶，不含背包）
##   tag_counts     Dictionary  上阵武器 tag 计数（SynergySystem.tag_counts 口径）
##   cultivator     Dictionary  CultivatorData.get_def(cultivator_id)，可为 {}（单测/无角色）
##   cult_mults     Dictionary  {武器id: 角色特性单武器伤害系数}（CultivatorSystem.damage_mult）
##   slots_used     int         上阵槽位现况
##   slots_max      int         上阵槽位上限
##   copies1        Dictionary  {武器id: 手里 1 星同名件数}（★1 三合一判定）
##   copies2        Dictionary  {武器id: 手里 2 星同名件数}（★2 三合一判定；货架会卖 ★2 成品）
##   stones         int         金币现况（货架候选的买得起判定）
##   wave           int         当前波（≥1）
##   victory_wave   int         胜利波（GameManager.VICTORY_WAVE）
##   crit_cap       float       暴击率硬上限（GameManager.CRIT_RATE_CAP）
##   dodge_cap      float       闪避硬上限（DODGE_CAP + dodge_cap_bonus）
##   aspd_floor     float       攻速地板（ATTACK_SPEED_FLOOR）
##   contraption_mult float     机关羁绊伤害乘区（synergy_contraption_mult）

# ---------------- 权重与参照（调参只动这一段） ----------------

const W_BUILD := 0.45     ## 构建边际收益权重
const W_FIT := 0.25       ## 角色契合权重
const W_SYN := 0.20       ## 流派协同权重
const W_TIMING := 0.10    ## 时机修正权重（货架买不起 × UNAFFORDABLE_MULT 走这里）

const REL_THRESHOLD := 0.90  ## 其余候选达到最高分的 90% 也标「荐」（动态 1~3 个）
const MAX_RECOMMEND := 3     ## 一屏最多几颗「荐」
const MIN_ABS_SCORE := 0.12  ## 最高分低于此 = 这屏没有值得推荐的，不硬塞
const UNAFFORDABLE_MULT := 0.85  ## 买不起的货架候选折价

## 各轴「打满 1.0」的参照增量（超过即满分，不足按比例）
const REF_DMG := 0.35          ## 上阵总伤 +35% 打满
const REF_HP := 0.25           ## 生命上限 +25% 打满
const REF_ARMOR := 0.15        ## 实际承伤相对下降 15% 打满
const REF_REGEN := 0.02        ## 每秒回复达最大生命 2% 打满
const REF_DODGE := 0.10        ## 闪避 +10% 打满
const REF_LIFESTEAL := 0.05    ## 吸血 +5% 打满
const REF_SPEED := 0.12        ## 移速 +12% 打满
const REF_RANGE := 0.15        ## 攻击范围 +15% 打满
const REF_ELITE := 0.15        ## 对精英伤害 +15% 打满
const REF_PIERCE := 2.0        ## 穿透 +2 打满（上限 0.5 分）
const REF_THORNS := 0.30       ## 反震伤害 +30% 打满（上限 0.5 分）
const REF_HARVEST_WAVES := 60.0  ## Δ收益 × 剩余波数 ≥ 60 打满
const REF_LUCK := 10.0         ## 幸运 +10 打满（按剩余波数折价再 ×0.6）
const REF_XP := 0.25           ## 经验获取 +25% 打满（按剩余波数折价）
const REF_STONES := 40.0       ## 即时金币 +40 打满（即时收益天然弱）
const REF_REROLLS := 2.0       ## 免费刷新 +2 打满（上限 0.3 分）
## 寻宝流三项（2026-10-11）：一口匣子≈一次白拿补给，所以按「还能刷几波」折价，与收益同一把尺
const REF_CHEST_COUNT_WAVES := 6.0  ## Δ宝箱数量 × 剩余波数 ≥ 6 口打满
const REF_CHEST_QUALITY := 8.0      ## 宝箱品质 +8 打满（约两把点金诀，铜/玉占比明显抬起来）
const REF_CHEST_REWARD := 1.0       ## 宝箱掉落 +100% 打满（悟道叠 3 层 ≈ 1.05，再加一件满匣诀就顶到）

# ---------------- 属性模拟（镜像 StatSystem 落地语义） ----------------

## 把一条 apply 增量按 StatSystem 同一套语义叠进属性快照（原地改传入字典；
## 调用方传 duplicate() 的副本）。clamp 与 StatSystem 同源：暴击/闪避到帽、攻速到地板。
## 即时结算类（金币/免费刷新/价格乘区/穿透计数）不进属性轴，由各打分轴直接读 apply。
static func simulate_stats(stats: Dictionary, element_damage: Dictionary, apply: Dictionary,
		crit_cap: float, dodge_cap: float, aspd_floor: float) -> void:
	for key in apply.keys():
		var k := String(key)
		var v: float = float(apply[key])
		match k:
			"weapon_damage_mult":
				stats["weapon_damage_mult"] = float(stats.get("weapon_damage_mult", 1.0)) + v
			"melee_damage":
				stats["melee_damage"] = float(stats.get("melee_damage", 0.0)) + v
			"ranged_damage":
				stats["ranged_damage"] = float(stats.get("ranged_damage", 0.0)) + v
			"elemental_damage":
				stats["elemental_damage"] = float(stats.get("elemental_damage", 0.0)) + v
			"engineering_damage":
				stats["engineering_damage"] = float(stats.get("engineering_damage", 0.0)) + v
			"contraption_damage":
				stats["contraption_damage"] = float(stats.get("contraption_damage", 0.0)) + v
			"attack_speed_mult_mul":
				stats["attack_speed_mult"] = maxf(aspd_floor, float(stats.get("attack_speed_mult", 1.0)) * v)
			"armor":
				stats["armor"] = float(stats.get("armor", 0.0)) + v
			"move_speed_mult":
				stats["move_speed_mult"] = float(stats.get("move_speed_mult", 1.0)) + v
			"attack_range_mult":
				stats["attack_range_mult"] = float(stats.get("attack_range_mult", 1.0)) + v
			"hp_regen":
				stats["hp_regen"] = float(stats.get("hp_regen", 0.0)) + v
			"crit_rate":
				stats["crit_rate"] = minf(float(stats.get("crit_rate", 0.05)) + v, crit_cap)
			"crit_mult":
				stats["crit_mult"] = float(stats.get("crit_mult", 1.5)) + v
			"dodge":
				stats["dodge"] = minf(float(stats.get("dodge", 0.0)) + v, dodge_cap)
			"lifesteal":
				stats["lifesteal"] = float(stats.get("lifesteal", 0.0)) + v
			"luck":
				stats["luck"] = float(stats.get("luck", 0.0)) + v
			"harvest":
				stats["harvest"] = float(stats.get("harvest", 0.0)) + v
			"max_hp":
				stats["max_hp"] = float(stats.get("max_hp", Player.BASE_MAX_HEALTH)) + v
			"xp_gain_mult":
				stats["xp_gain_mult"] = float(stats.get("xp_gain_mult", 1.0)) + v
			"elite_damage":
				stats["elite_damage"] = float(stats.get("elite_damage", 0.0)) + v
			"thorns":
				stats["thorns"] = float(stats.get("thorns", 0.0)) + v
			"element_damage_all":
				for e in WeaponData.ELEMENTS:
					element_damage[e] = float(element_damage.get(e, 0.0)) + v
			_:
				if k.begins_with("element_damage_") and k.trim_prefix("element_damage_") in WeaponData.ELEMENTS:
					var elem: String = k.trim_prefix("element_damage_")
					element_damage[elem] = float(element_damage.get(elem, 0.0)) + v
				# 其余（hp_heal/spirit_stones/free_rerolls/shop_price_mul/bonus_pierce/宝箱三项）不进属性轴

# ---------------- 武器期望每秒伤害（与 WeaponDamageReadout 同源的纯函数版） ----------------

## 五行真解乘区（与 GameManager.element_damage_mult 同一条式子的纯函数版）
static func element_mult(element_damage: Dictionary, w_id: String) -> float:
	if element_damage.is_empty():
		return 1.0
	return 1.0 + float(element_damage.get(WeaponData.element_of(w_id), 0.0))

## 期望每秒伤害。乘区链与 WeaponDamageReadout.per_second 逐项同形，差异只有两处且都是刻意的：
## ① 显式含暴击期望（×(1 + 暴击率×(暴伤-1))）——卡面口径不含暴击，但推荐要量化暴击类加成的
##    边际收益，两边各守各的口径，不混用；② cult_mult 由 ctx 显式传入（纯函数不读 GM）。
static func weapon_expected_dps(w_id: String, star: int, stats: Dictionary, element_damage: Dictionary,
		cult_mult: float, slots: int, contraption_mult: float,
		drone_slots: int = -1) -> float:
	var def := WeaponData.get_def(w_id)
	if def.is_empty():
		return 0.0
	var s := clampi(star, 1, WeaponData.MAX_STAR)
	var base := WeaponData.damage_for(w_id, s)
	if base <= 0.0:
		return 0.0
	var haste := float(stats.get("attack_speed_mult", 1.0))
	if haste <= 0.0:
		return 0.0
	var bonus := GameBalance.weapon_stat_bonus(def.get("stat_scalings", {}), stats, s)
	# stats["weapon_damage_mult"] 已含羁绊的「武器伤害」乘区（get_player_stat_dict 里两者相乘），
	# 环绕类不再另有一档专属乘区 ⇒ 这一条链与 SunOrb 运行时逐项同形。
	var mult := float(stats.get("weapon_damage_mult", 1.0)) * cult_mult \
			* element_mult(element_damage, w_id) * GameBalance.multi_weapon_damage_mult(slots, maxi(0, drone_slots))
	if int(def.get("behavior", WeaponData.Behavior.MELEE)) == WeaponData.Behavior.TURRET:
		mult *= contraption_mult
	var per_hit := (base + bonus) * mult
	var crit_expect := 1.0 + maxf(0.0, float(stats.get("crit_rate", 0.05))) \
			* (float(stats.get("crit_mult", 1.5)) - 1.0)
	return WeaponData.sustained_single_dps(w_id, s) * (per_hit / base) / haste * crit_expect

## 上阵武器（含灵蝶）的期望每秒伤害合计。
## drone_slots 缺省自动数编队里的 DRONE 把数（御灵半权分流）；投影「买下之后」时显式传入。
static func total_dps(weapons: Array, stats: Dictionary, element_damage: Dictionary,
		cult_mults: Dictionary, slots: int, contraption_mult: float,
		drone_slots: int = -1) -> float:
	var drone_n := count_drones(weapons) if drone_slots < 0 else drone_slots
	var total := 0.0
	for w in weapons:
		var wid := String(w.get("id", ""))
		total += weapon_expected_dps(wid, int(w.get("star", 1)), stats, element_damage,
				float(cult_mults.get(wid, 1.0)), slots, contraption_mult, drone_n)
	return total

## 编队里 DRONE 武器的把数（御灵半权分流口径用）
static func count_drones(weapons: Array) -> int:
	var n := 0
	for w in weapons:
		if int(WeaponData.get_def(String(w.get("id", ""))).get("behavior", -1)) == WeaponData.Behavior.DRONE:
			n += 1
	return n

# ---------------- 打分入口 ----------------

## 悟道加点/道具类候选（apply 字典同链路，一套口径两处吃）。
## 返回 {score, b, a, c, reasons}：b/a/c 单列出来给判据与调参用。
static func score_apply(apply: Dictionary, ctx: Dictionary) -> Dictionary:
	var stats: Dictionary = ctx.get("stats", {})
	var elem: Dictionary = ctx.get("element_damage", {})
	var stats2: Dictionary = stats.duplicate()
	var elem2: Dictionary = elem.duplicate()
	simulate_stats(stats2, elem2, apply,
			float(ctx.get("crit_cap", 0.75)), float(ctx.get("dodge_cap", 0.6)), float(ctx.get("aspd_floor", 0.3)))

	var weapons: Array = ctx.get("weapons", [])
	var cult_mults: Dictionary = ctx.get("cult_mults", {})
	var contr: float = float(ctx.get("contraption_mult", 1.0))
	var slots := maxi(1, int(ctx.get("slots_used", 1)))
	var reasons: Array[String] = []

	# ---- B1 伤害轴：上阵总伤加成前后对比 ----
	var dps0 := total_dps(weapons, stats, elem, cult_mults, slots, contr, -1)
	var dps1 := total_dps(weapons, stats2, elem2, cult_mults, slots, contr, -1)
	var dmg_gain := (dps1 - dps0) / maxf(dps0, 1.0)
	var b_dmg := clampf(dmg_gain / REF_DMG, 0.0, 1.0)
	if b_dmg >= 0.04:
		reasons.append("上阵武器总伤约 +%d%%" % _pct(dmg_gain))

	# ---- B2 生存轴（各子项取最大，负代偿单独记罚） ----
	var hp0 := maxf(float(stats.get("max_hp", Player.BASE_MAX_HEALTH)), 1.0)
	var d_hp := (float(stats2.get("max_hp", hp0)) - hp0) / hp0
	var red0 := GameBalance.armor_reduction(float(stats.get("armor", 0.0)))
	var red1 := GameBalance.armor_reduction(float(stats2.get("armor", 0.0)))
	var d_armor := (red1 - red0) / maxf(1.0 - red0, 0.05)  ## 承伤相对降幅
	var d_regen := float(stats2.get("hp_regen", 0.0)) - float(stats.get("hp_regen", 0.0))
	var d_dodge := float(stats2.get("dodge", 0.0)) - float(stats.get("dodge", 0.0))
	var d_ls := float(stats2.get("lifesteal", 0.0)) - float(stats.get("lifesteal", 0.0))
	var d_thorns := float(stats2.get("thorns", 0.0)) - float(stats.get("thorns", 0.0))
	var def_subs: Array[float] = [
		clampf(d_hp / REF_HP, 0.0, 1.0),
		clampf(d_armor / REF_ARMOR, 0.0, 1.0),
		clampf(d_regen / maxf(hp0 * REF_REGEN, 0.1), 0.0, 1.0),
		clampf(d_dodge / REF_DODGE, 0.0, 1.0),
		clampf(d_ls / REF_LIFESTEAL, 0.0, 1.0),
		clampf(d_thorns / REF_THORNS, 0.0, 0.5),
	]
	var b_def := _max_of(def_subs)
	if b_def >= 0.04:
		reasons.append(_def_reason(hp0, d_hp, d_armor, d_regen, d_dodge, d_ls))
	var worst_neg := maxf(maxf(0.0, -d_hp) / REF_HP, maxf(0.0, -d_armor) / REF_ARMOR)
	if worst_neg >= 0.08:
		reasons.append("代价：生命或护甲有倒退")

	# ---- B3 经济轴（收益会复利，前期比后期值钱） ----
	var wave := maxi(1, int(ctx.get("wave", 1)))
	var victory := maxi(1, int(ctx.get("victory_wave", 20)))
	var remaining := clampi(victory - wave, 0, victory)
	var wave_ratio := float(remaining) / float(victory)
	var d_harvest := float(stats2.get("harvest", 0.0)) - float(stats.get("harvest", 0.0))
	var d_luck := float(stats2.get("luck", 0.0)) - float(stats.get("luck", 0.0))
	var d_xp := float(stats2.get("xp_gain_mult", 1.0)) - float(stats.get("xp_gain_mult", 1.0))
	# 寻宝流三项直接读 apply（与即时金币/免费刷新同一类：兑现的是场面上的东西，不是属性乘区）
	var d_chest_cnt := float(apply.get("chest_count", 0.0))
	var d_chest_q := float(apply.get("chest_quality", 0.0))
	var d_chest_reward := float(apply.get("chest_reward", 0.0))
	var eco_subs: Array[float] = [
		clampf(d_harvest * float(remaining) / REF_HARVEST_WAVES, 0.0, 1.0),
		clampf(d_luck / REF_LUCK, 0.0, 1.0) * (0.5 + 0.5 * wave_ratio) * 0.6,
		clampf(d_xp / REF_XP, 0.0, 1.0) * wave_ratio,
		clampf(float(apply.get("spirit_stones", 0.0)) / REF_STONES, 0.0, 1.0) * (0.4 + 0.6 * wave_ratio),
		clampf(absf(float(apply.get("free_rerolls", 0.0))) / REF_REROLLS, 0.0, 1.0) * 0.3,
		clampf(d_chest_cnt * float(remaining) / REF_CHEST_COUNT_WAVES, 0.0, 1.0) * (0.4 + 0.6 * wave_ratio),
		clampf(d_chest_q / REF_CHEST_QUALITY, 0.0, 1.0) * (0.5 + 0.5 * wave_ratio) * 0.8,
		clampf(d_chest_reward / REF_CHEST_REWARD, 0.0, 1.0) * (0.5 + 0.5 * wave_ratio) * 0.8,
	]
	var b_eco := _max_of(eco_subs)
	if b_eco >= 0.04:
		if d_harvest > 0.0:
			reasons.append("收益 +%s/波 · 余 %d 波" % [_num(d_harvest), remaining])
		elif d_luck > 0.0:
			reasons.append("幸运 +%s" % _num(d_luck))
		elif d_xp > 0.0:
			reasons.append("经验获取 +%d%%" % _pct(d_xp))
		elif d_chest_cnt > 0.0:
			reasons.append("宝箱 +%d 口/波 · 余 %d 波" % [int(d_chest_cnt), remaining])
		elif d_chest_q > 0.0:
			reasons.append("铜匣玉匣更易出现")
		elif d_chest_reward > 0.0:
			reasons.append("宝箱掉落 +%d%%" % _pct(d_chest_reward))

	# ---- B4 功能轴（移动/攻击范围/对精英伤害等，给小基线不压过主轴） ----
	var d_speed := float(stats2.get("move_speed_mult", 1.0)) - float(stats.get("move_speed_mult", 1.0))
	var d_range := float(stats2.get("attack_range_mult", 1.0)) - float(stats.get("attack_range_mult", 1.0))
	var d_elite := float(stats2.get("elite_damage", 0.0)) - float(stats.get("elite_damage", 0.0))
	var util_subs: Array[float] = [
		clampf(d_speed / REF_SPEED, 0.0, 1.0),
		clampf(d_range / REF_RANGE, 0.0, 1.0),
		clampf(d_elite / REF_ELITE, 0.0, 1.0),
		clampf(absf(float(apply.get("bonus_pierce", 0.0))) / REF_PIERCE, 0.0, 0.5),
	]
	var b_util := _max_of(util_subs)
	if b_util >= 0.04:
		if d_speed > 0.0:
			reasons.append("移速 +%d%%" % _pct(d_speed))
		elif d_range > 0.0:
			reasons.append("攻击范围 +%d%%" % _pct(d_range))
		elif d_elite > 0.0:
			reasons.append("对精英伤害 +%d%%" % _pct(d_elite))

	# ---- B 汇总：拿手的轴取最大，负代偿按半价折损 ----
	var b := clampf(maxf(maxf(b_dmg, b_def), maxf(b_eco, b_util)) - 0.5 * worst_neg, 0.0, 1.0)

	# ---- A 角色契合 / C 流派协同 ----
	var a := _apply_fit(apply, ctx, reasons)
	var c := _apply_element_syn(apply, ctx, reasons)

	var score := W_BUILD * b + W_FIT * a + W_SYN * c + W_TIMING * 1.0
	return {"score": score, "b": b, "a": a, "c": c, "reasons": reasons}

## 货架武器候选。star = 这一件的星级（缺省 ★1；货架从 2026-10-25 起会卖 ★2 成品）：
## 边际收益要按「买到手的那一件」算，三合一判定也要查同星件数 —— ★1 与 ★2 各算各的轨道。
static func score_weapon(w_id: String, ctx: Dictionary, star: int = 1) -> Dictionary:
	var stats: Dictionary = ctx.get("stats", {})
	var elem: Dictionary = ctx.get("element_damage", {})
	var cult_mults: Dictionary = ctx.get("cult_mults", {})
	var contr: float = float(ctx.get("contraption_mult", 1.0))
	var slots_used := int(ctx.get("slots_used", 1))
	var slots_max := maxi(1, int(ctx.get("slots_max", 6)))
	var reasons: Array[String] = []
	var s := clampi(star, 1, WeaponData.MAX_STAR)

	# ---- B 构建边际收益 ----
	var cult_mult := float(cult_mults.get(w_id, 1.0))
	var is_drone := int(WeaponData.get_def(w_id).get("behavior", -1)) == WeaponData.Behavior.DRONE
	var drone_now := count_drones(ctx.get("weapons", []))
	var total0 := total_dps(ctx.get("weapons", []), stats, elem, cult_mults, slots_used, contr, -1)
	# 三合一判定与卡面/合成角标同式：同星同名 % 3 == 2 才是「买下即凑满」。
	# 只有 ★1/★2 会出现在货架，★3 起没有对应的 copies 表（作者模式发放，不参与推荐）。
	var copies: Dictionary = {}
	if s == 1:
		copies = ctx.get("copies1", {})
	elif s == 2:
		copies = ctx.get("copies2", {})
	var merge_ready := s < WeaponData.MAX_STAR and (int(copies.get(w_id, 0)) % 3) == 2
	var full := slots_used >= slots_max
	var b := 0.0
	if merge_ready:
		# 三合一：3×★n 变 1×★(n+1)，净收益 = 升星单件增量（还腾 2 个槽位，协同因子另给满分）
		var drone_after_merge := maxi(0, drone_now - 2) if is_drone else drone_now
		var dps1 := weapon_expected_dps(w_id, s, stats, elem, cult_mult, slots_used, contr, drone_now)
		var dps2 := weapon_expected_dps(w_id, s + 1, stats, elem, cult_mult, maxi(1, slots_used - 1), contr, drone_after_merge)
		b = clampf((dps2 - dps1) / maxf(total0, 1.0) / REF_DMG, 0.0, 1.0)
		if dps1 > 0.0:
			reasons.append("买下即可三合一升至 ★%d（单件伤害 ×%.1f）" % [s + 1, dps2 / dps1])
	elif not full:
		# 直接入阵：现有武器按「买下之后」的槽位数重算分流税，新件按同口径投影
		var slots_after := mini(slots_used + 1, slots_max)
		var drone_after := drone_now + (1 if is_drone else 0)
		var total1 := total_dps(ctx.get("weapons", []), stats, elem, cult_mults, slots_after, contr, drone_after) \
				+ weapon_expected_dps(w_id, s, stats, elem, cult_mult, slots_after, contr, drone_after)
		var gain := total1 / maxf(total0, 1.0) - 1.0
		b = clampf(gain / REF_DMG, 0.0, 1.0)
		reasons.append("到手每秒约 %s（上阵总伤 %s%d%%）" % [
			_num(weapon_expected_dps(w_id, s, stats, elem, cult_mult, slots_after, contr, drone_after)),
			"+" if gain >= 0.0 else "-", _pct(absf(gain))])
	else:
		# 槽位满：只能进背包，不即时生效——给个「可替换」评估而不是零分
		var weakest := _weakest_dps(ctx.get("weapons", []), stats, elem, cult_mults, slots_used, contr, drone_now)
		var dps_new := weapon_expected_dps(w_id, s, stats, elem, cult_mult, slots_used, contr, drone_now)
		b = 0.20 if dps_new >= 0.8 * weakest else 0.05
		reasons.append("槽位已满 · 入背包（可替换现役最弱）")

	# ---- A 角色契合 / C 流派协同 ----
	var a := _weapon_fit(w_id, ctx, reasons)
	var c := _weapon_syn(w_id, ctx, merge_ready, full, reasons)

	var score := W_BUILD * b + W_FIT * a + W_SYN * c + W_TIMING * 1.0
	return {"score": score, "b": b, "a": a, "c": c, "reasons": reasons}

## 回气丹：按缺血程度单独计（满血就是不值钱，别花这个钱）
static func score_potion(offer: Dictionary, ctx: Dictionary) -> Dictionary:
	var stats: Dictionary = ctx.get("stats", {})
	var max_hp := maxf(float(stats.get("max_hp", Player.BASE_MAX_HEALTH)), 1.0)
	var cur := clampf(float(stats.get("current_hp", max_hp)), 0.0, max_hp)
	var ratio := cur / max_hp
	var need := clampf((0.80 - ratio) / 0.55, 0.0, 1.0)  ## ≤25% 血打满，≥80% 血为零
	var reasons: Array[String] = []
	if need >= 0.04:
		reasons.append("生命 %d%% · 回复约 %d" % [_pct(ratio),
				int(round(GameBalance.potion_effective_heal(max_hp, cur)))])
	return {"score": W_BUILD * need, "b": need, "a": 0.0, "c": 0.0, "reasons": reasons}

## 货架候选分流 + 时机修正 D（买不起折价：值得攒钱，但不抢「现在能买」的推荐位）
static func score_offer(offer: Dictionary, ctx: Dictionary) -> Dictionary:
	var out: Dictionary
	match String(offer.get("kind", "weapon")):
		"potion":
			out = score_potion(offer, ctx)
		"item":
			out = score_apply(ItemData.get_def(String(offer.get("id", ""))).get("apply", {}), ctx)
		_:
			out = score_weapon(String(offer.get("id", "")), ctx, int(offer.get("star", 1)))
	var price := int(offer.get("price", 0))
	if price > int(ctx.get("stones", 0)) and float(out["score"]) > 0.0:
		out["score"] = float(out["score"]) * UNAFFORDABLE_MULT
		var reasons: Array = out["reasons"]
		if reasons.size() < 3:
			reasons.append("金币不足 · 可先攒钱")
	return out

# ---------------- 标记（动态 1~3 颗「荐」） ----------------

## scored: [{index:int, score:float, reasons:Array}]（调用方逐候选生成）。
## 规则：最高分必标；其余 ≥ 最高分×REL_THRESHOLD 也标，至多 MAX_RECOMMEND 个；
## 最高分低于 MIN_ABS_SCORE 时一颗都不标（这屏没有好选择，不硬塞）。
## 先把所有 offer 的推荐字段清干净再标——锁定保留的旧标也会被刷新，幂等可重复调用。
static func mark_offers(offers: Array, scored: Array) -> void:
	for off in offers:
		off["recommended"] = false
		off["recommend_score"] = 0.0
		off["recommend_reasons"] = []
	if scored.is_empty():
		return
	var sorted: Array = scored.duplicate()
	sorted.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	var best := float(sorted[0]["score"])
	if best < MIN_ABS_SCORE:
		return
	var marked := 0
	for s in sorted:
		if marked >= MAX_RECOMMEND:
			break
		if float(s["score"]) < best * REL_THRESHOLD:
			continue
		var idx := int(s["index"])
		if idx < 0 or idx >= offers.size():
			continue
		var off: Dictionary = offers[idx]
		off["recommended"] = true
		off["recommend_score"] = float(s["score"])
		var reasons: Array[String] = []
		for r in s["reasons"]:
			reasons.append(String(r))
		if reasons.is_empty():
			reasons.append("综合契合当前构筑")
		off["recommend_reasons"] = reasons
		marked += 1

# ---------------- 角色契合（从 CultivatorData 程序化推导，不手抄角色表） ----------------

## 道统偏好 apply 键 → **「为什么偏好它」的一句话来源**（旧版只回 key→true，契合理由只能喊
## 「契合【剑客】护甲取向」却答不出剑客哪一点要护甲，玩家对着角色卡找不到这条，故来源必须随偏好一起出）。
## 两种来源，话术与角色卡的「初始X +N」同一套词：
##   ① mods 正收益键映射 →「他初始暴击率 +15%」（幅度现读 CultivatorData.mods）；
##   ② allowed_tags 流派偏好武器吃的属性（stat_scalings 键经 APPLY_WEAPON_STAT_MAP 反查回 apply 键）
##      →「剑系有 3 把按护甲加伤」（把数现数 SHOP_POOL，不手抄）。
## 空串 = 只登记偏好、给不出人话来源（如反震这类非面板字段）。
static func preferred_keys(mods: Dictionary, allowed_tags: Array) -> Dictionary:
	var pref := {}
	# ---- ① 角色自身就带的属性 ----
	if float(mods.get("crit_rate", 0.0)) > 0.0:
		var w_crit := _own_why("crit_rate", mods)
		pref["crit_rate"] = w_crit
		pref["crit_mult"] = w_crit
	if float(mods.get("armor", 0.0)) > 0.0 or float(mods.get("thorns", 0.0)) > 0.0:
		pref["armor"] = _own_why("armor", mods)
	if float(mods.get("thorns", 0.0)) > 0.0:
		pref["thorns"] = _own_why("thorns", mods)
	if float(mods.get("dodge", 0.0)) > 0.0:
		pref["dodge"] = _own_why("dodge", mods)
	if float(mods.get("harvest", 0.0)) > 0.0:
		var w_harvest := _own_why("harvest", mods)
		pref["harvest"] = w_harvest
		pref["luck"] = w_harvest
		pref["spirit_stones"] = w_harvest
		if float(mods.get("engineering", 0.0)) > 0.0:
			pref["engineering_damage"] = "他初始%s +%s" % [
				StatInfoData.field_name("engineering_damage"), _num(float(mods["engineering"]))]
		if float(mods.get("contraption", 0.0)) > 0.0:
			pref["contraption_damage"] = "他初始%s +%s" % [
				StatInfoData.field_name("contraption_damage"), _num(float(mods["contraption"]))]
	if float(mods.get("elemental", 0.0)) > 0.0:
		var w_elem := "他初始%s +%s" % [
			StatInfoData.field_name("elemental_damage"), _num(float(mods["elemental"]))]
		pref["elemental_damage"] = w_elem
		pref["element_damage_all"] = w_elem
	if float(mods.get("hp_regen", 0.0)) > 0.0:
		pref["hp_regen"] = _own_why("hp_regen", mods)
	if float(mods.get("hp_mult", 1.0)) > 1.0:
		pref["max_hp"] = "他最大生命 ×%s" % String.num(float(mods["hp_mult"]), 3)
	if float(mods.get("speed_mult", 1.0)) > 1.0:
		pref["move_speed_mult"] = "他移动速度 ×%s" % String.num(float(mods["speed_mult"]), 3)
	if float(mods.get("damage_mult", 1.0)) > 1.0:
		## 全域增伤道统：所有输出向键都算偏好，来源是同一条「全武器伤害」
		var w_all := "他全武器伤害 ×%s" % String.num(float(mods["damage_mult"]), 3)
		for k in ["weapon_damage_mult", "melee_damage", "ranged_damage", "elemental_damage",
				"engineering_damage", "attack_speed_mult_mul", "crit_rate", "crit_mult"]:
			pref[k] = w_all
	if float(mods.get("haste_mult", 1.0)) < 1.0:
		# 他自己就带攻击间隔缩减（狂战士），这条比「全武器伤害」更直接，写在它后面覆盖
		pref["attack_speed_mult_mul"] = "他攻击间隔 %s" % StatInfoData.format_amount(
				"attack_speed_mult_mul", float(mods["haste_mult"]))
	# ---- ② 流派偏好武器吃的那些属性 ----
	if not allowed_tags.is_empty():
		var rev := {}
		for k in GameBalance.APPLY_WEAPON_STAT_MAP:
			rev[GameBalance.APPLY_WEAPON_STAT_MAP[k]] = String(k)
		var counts := {}
		var from_tag := {}
		for w_id in WeaponData.SHOP_POOL:
			var hit_tag := ""
			for t in WeaponData.tags_of(w_id):
				if t in allowed_tags:
					hit_tag = String(t)
					break
			if hit_tag.is_empty():
				continue
			var scalings: Dictionary = WeaponData.get_def(w_id).get("stat_scalings", {})
			for sk in scalings.keys():
				if not rev.has(String(sk)) or float(scalings[sk]) <= 0.0:
					continue
				var ak := String(rev[sk])
				counts[ak] = int(counts.get(ak, 0)) + 1
				if not from_tag.has(ak):
					from_tag[ak] = hit_tag
		for ak in counts.keys():
			# 自身属性那条更直接，流派推导只补它没覆盖到的键（空串那条等于没覆盖）
			if pref.has(ak) and not String(pref[ak]).is_empty():
				continue
			pref[ak] = "%s有 %d 把按%s加伤" % [
				tag_display(String(from_tag[ak])), int(counts[ak]), StatInfoData.field_name(ak)]
	return pref

## 「他自己就有这条」话术：字段名与幅度都现读 mods（与角色卡同一份数，改数不改文案）
static func _own_why(key: String, mods: Dictionary) -> String:
	var v := float(mods.get(key, 0.0))
	if v <= 0.0:
		return ""
	return "他初始%s %s" % [StatInfoData.field_name(key), StatInfoData.format_amount(key, v)]

## 加点/道具候选的角色契合：正收益幅度里落在偏好键上的占比
static func _apply_fit(apply: Dictionary, ctx: Dictionary, reasons: Array[String]) -> float:
	var cult: Dictionary = ctx.get("cultivator", {})
	var mods: Dictionary = cult.get("mods", {})
	var pref := preferred_keys(mods, cult.get("allowed_tags", []))
	var pos_mass := 0.0
	var pref_mass := 0.0
	var hit_names: Array[String] = []
	var whys: Array[String] = []
	for key in apply.keys():
		var v := float(apply[key])
		if v <= 0.0:
			continue
		pos_mass += v
		if pref.has(String(key)):
			pref_mass += v
			if hit_names.size() < 2:
				var nm := StatInfoData.field_name(String(key))
				if not nm.is_empty() and not hit_names.has(nm):
					hit_names.append(nm)
			var wy := String(pref[key])
			if not wy.is_empty() and not whys.has(wy) and whys.size() < 2:
				whys.append(wy)
	if pos_mass <= 0.0 or pref.is_empty():
		return 0.5
	var a := 0.35 + 0.65 * (pref_mass / pos_mass)
	if a >= 0.7 and not cult.is_empty():
		reasons.append("契合【%s】%s取向" % [String(cult.get("name", "?")), "、".join(hit_names)])
		# 「契合」二字不能只喊结论：跟着写一句它是从角色哪条属性/哪个流派推出来的
		if not whys.is_empty():
			reasons.append("因为%s" % "，".join(whys))
	return clampf(a, 0.0, 1.0)

## 武器候选的角色契合：tag 专精/流派偏好 + 行为惩罚（非灵蝶/非机关代偿）
static func _weapon_fit(w_id: String, ctx: Dictionary, reasons: Array[String]) -> float:
	var cult: Dictionary = ctx.get("cultivator", {})
	if cult.is_empty():
		return 0.5
	var mods: Dictionary = cult.get("mods", {})
	var allowed: Array = cult.get("allowed_tags", [])
	var tags := WeaponData.tags_of(w_id)
	var a := 0.5
	var tag_hit := ""
	for t in tags:
		if t in allowed:
			tag_hit = t
			break
	var cname := String(cult.get("name", "?"))
	var tag_bonus := ""
	var tag_neg := ""
	var td: Dictionary = mods.get("tag_damage", {})
	for t in tags:
		var tb := float(td.get(t, 0.0))
		if tb >= 0.15:
			tag_bonus = t
		if tb <= -0.15:
			tag_neg = t
	# 「流派偏好」与「tag 专精」经常命中同一个签（剑客买长剑），两句只差两个字说的是同一件事；
	# 专精那句更强，只留它，别让详情卡看着像凑行数。
	if not tag_hit.is_empty():
		a = 0.9
		if tag_hit != tag_bonus:
			reasons.append("契合【%s】%s取向" % [cname, tag_display(tag_hit)])
	if not tag_bonus.is_empty():
		a = maxf(a, 0.95)
		reasons.append("契合【%s】%s专精" % [cname, tag_display(tag_bonus)])
	if not tag_neg.is_empty():
		a = minf(a, 0.15)
		reasons.append("%s系不被【%s】所容" % [tag_display(tag_neg), cname])
	var beh := int(WeaponData.get_def(w_id).get("behavior", WeaponData.Behavior.MELEE))
	if float(mods.get("non_drone_damage", 0.0)) < -0.05 and beh != WeaponData.Behavior.DRONE:
		a *= 0.6
		reasons.append("【%s】非召唤类武器伤害 %s" % [cname,
				StatInfoData.format_amount("weapon_damage_mult", float(mods["non_drone_damage"]))])
		if float(mods.get("non_contraption_damage", 0.0)) < -0.05 \
				and beh != WeaponData.Behavior.TURRET and beh != WeaponData.Behavior.DRONE:
			a *= 0.6
			reasons.append("【%s】非机关类武器伤害 %s" % [cname,
				StatInfoData.format_amount("weapon_damage_mult", float(mods["non_contraption_damage"]))])
	return clampf(a, 0.0, 1.0)

# ---------------- 流派协同 ----------------

## 加点/道具候选：五行真解与上阵武器的元素契合
static func _apply_element_syn(apply: Dictionary, ctx: Dictionary, reasons: Array[String]) -> float:
	var has_elem_key := false
	var hit := false
	for key in apply.keys():
		var k := String(key)
		if not k.begins_with("element_damage_"):
			continue
		has_elem_key = true
		for w in ctx.get("weapons", []):
			var wel := WeaponData.element_of(String(w.get("id", "")))
			if k == "element_damage_all":
				if not wel.is_empty():
					hit = true
			elif wel == k.trim_prefix("element_damage_"):
				hit = true
			if hit:
				break
		if hit:
			break
	if hit:
		reasons.append("五行真解契合上阵武器")
		return 0.85
	return 0.15 if has_elem_key else 0.35

## 武器候选：羁绊档位进度 + 三合一；槽位满时进背包不进羁绊计数，只给保底
static func _weapon_syn(w_id: String, ctx: Dictionary, merge_ready: bool, full: bool,
		reasons: Array[String]) -> float:
	if merge_ready:
		return 1.0  # 理由由 B 段写（带升星倍率更有说服力）
	if full:
		return 0.10
	var counts: Dictionary = ctx.get("tag_counts", {})
	var c := 0.20
	var near_tag := ""
	var near_n := 0
	for t in WeaponData.tags_of(w_id):
		var syn: Dictionary = WeaponData.SYNERGIES.get(t, {})
		if syn.is_empty():
			continue
		var n := int(counts.get(t, 0)) + 1
		var matched := false
		for th in syn.get("thresholds", []):
			if n == int(th):
				c = maxf(c, 1.0)
				reasons.append("【%s】羁绊 %d/%d 凑齐" % [String(syn.get("name", t)), n, int(th)])
				matched = true
				break
			elif n == int(th) - 1:
				c = maxf(c, 0.65)
				if near_tag.is_empty():
					near_tag = String(syn.get("name", t))
					near_n = int(th)
		if matched:
			break
	if c >= 0.65 and c < 1.0 and not near_tag.is_empty():
		reasons.append("【%s】只差 1 件凑齐 %d" % [near_tag, near_n])
	return c

# ---------------- 小工具 ----------------

static func _weakest_dps(weapons: Array, stats: Dictionary, element_damage: Dictionary,
		cult_mults: Dictionary, slots: int, contraption_mult: float,
		drone_slots: int = -1) -> float:
	var weakest := -1.0
	for w in weapons:
		var wid := String(w.get("id", ""))
		var d := weapon_expected_dps(wid, int(w.get("star", 1)), stats, element_damage,
				float(cult_mults.get(wid, 1.0)), slots, contraption_mult, drone_slots)
		weakest = d if weakest < 0.0 else minf(weakest, d)
	return maxf(weakest, 0.0)

static func _max_of(arr: Array[float]) -> float:
	var m := 0.0
	for v in arr:
		m = maxf(m, v)
	return m

## 生存轴理由：挑降幅最大的那一项写，别把四行小数全糊给玩家（比较基准与 def_subs 同源）
static func _def_reason(hp0: float, d_hp: float, d_armor: float, d_regen: float,
		d_dodge: float, d_ls: float) -> String:
	var regen_ref := maxf(hp0 * REF_REGEN, 0.1)
	var best := "生命上限 +%d%%" % _pct(d_hp)
	var best_v := d_hp / REF_HP
	if d_armor / REF_ARMOR > best_v:
		best = "承伤约 -%d%%" % _pct(d_armor)
		best_v = d_armor / REF_ARMOR
	if d_regen / regen_ref > best_v:
		best = "每秒回复 +%s" % _num(d_regen)
		best_v = d_regen / regen_ref
	if d_dodge / REF_DODGE > best_v:
		best = "闪避 +%d%%" % _pct(d_dodge)
		best_v = d_dodge / REF_DODGE
	if d_ls / REF_LIFESTEAL > best_v:
		best = "吸血 +%d%%" % _pct(d_ls)
	return best

static func tag_display(t: String) -> String:
	return String(WeaponData.SYNERGIES.get(t, {}).get("name", t))

static func _pct(v: float) -> int:
	return int(round(v * 100.0))

static func _num(v: float) -> String:
	return "%d" % int(round(v)) if absf(v - roundf(v)) < 0.05 else "%.1f" % v
