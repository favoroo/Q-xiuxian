extends Node

## 非判据量尺：把「每个回合大概能得到多少金币」这条曲线打出来给人看的数字版。
## 运行: $G --headless --path . res://tests/GoldCurveProbe.tscn
##
## 为什么要有它：金币收入散在六条腿（宝石金币腿/碎金档、金蟾、精英、Boss、匣子、
## 灵韵与提前清场），手算必漂，且任何一处改了平衡常量曲线就变。
## 这里**不另算一套**：每一腿都直接调生产入口的同一个纯函数（GameBalance 门面转发
## BalanceEconomy / BalanceWave / BalanceChest / EnemyData），复算的只有「敌种配比→平均 exp_reward」
## 这一步，因为那步本身是纯函数 pick_scene_key + 一份静态权表。
##
## 口径声明（与线上完全一致的部分）：
##   · 刷怪预算      = BalanceWave.wave_spawn_budget(wave) × 危险度规模乘区 × 角色敌潮乘区
##   · 单怪金币      = 宝石金币腿 = exp_reward × MOB_KILL_EXP_MULT（未中碎金档时）
##                     中碎金档（概率 gem_shard_chance）：金币腿折到 1 枚
##                     丹爆傀儡（heal_orb_drop > 0）：掉回血珠，**不掉宝石** ⇒ 金币腿为 0
##                   精英：ELITE_GEM_COUNT(5) 颗 × ELITE_GEM_EXP + ELITE_STONE_BONUS
##                   Boss：BOSS_STONE_REWARD(150) + 5 颗 × ELITE_GEM_EXP
##                   金蟾：looter_stone_reward(wave)
##   · 匣子          = chest_count(wave) 口 × 各档权重 → 各档 stones
##                     + 非葫芦腿撒出的 gem_count 颗宝石（每颗 gem_exp=5 金币，不是 1）
##   · 灵韵/补差     = harvest（复利）+ budget_compensation_exp（未刷出只数 × 均值经验，补差只给经验）
##   · 提前清场余时赏 = early_clear_stones(余秒)
##
## 已知未计入（会略微高估实际）：
##   · 灵韵（harvest）默认 0 —— 要玩家主动堆「收益」加点/道具才有
##   · 守财奴结息、回复珠溢出折币、暴击吸金币 —— 都要特定 build
##   · 血蛹分裂的 3 只史莱姆幼体、百目妖产的蜂群幼体（分裂/产卵怪不占刷怪预算，
##     但每只幼体照样掉金币 ⇒ 实际收入比本表高；本表把它们折进「派生腿」单列）
##
## 三种「清场口径」都打出来，因为实际发生哪种取决于玩家强度，结论要能分档看：
##   A 全清：预算全部刷出且全灭 ⇒ 击杀收入 = 预算只数 × 单怪金币
##   B 半清：只灭了一半预算 ⇒ 另一半走补差（补差只给经验，金币腿不受影响）
##   C 提前清场：预算刷尽且场上清空 ⇒ 额外白拿余时赏

const DANGER := 0          ## 普通档（危险度 0）为默认口径
const TRIALS := 6000      ## 配比采样次数

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n========== 金币掉落曲线量尺（危险度 %d） ==========" % DANGER)
	print("口径：预算只数 × 单怪金币腿 + 派生怪 + 匣子 + 精英/Boss/金蟾 + 灵韵\n")

	var danger_count_mult := GameBalance.danger_count_mult(DANGER)

	print("%-4s %-7s %-8s %-9s %-9s %-8s %-8s %-8s %-9s %-8s" % [
		"波", "预算只数", "平均exp", "击杀金币", "派生怪", "匣子金币", "金蟾", "精英/Boss", "回合总计", "累计"])
	print("".lpad(104, "-"))

	var total := 0
	var harvest_v := 0.0

	for wave in range(1, 21):
		var budget := int(round(float(GameBalance.wave_spawn_budget(wave)) * danger_count_mult))
		var mix_result := _wave_mix(wave)   ## {mix: Dictionary, avg: float}
		var mix: Dictionary = mix_result["mix"]
		var avg_exp: float = mix_result["avg"]
		var shard_chance := GameBalance.gem_shard_chance(wave)

		# —— 击杀腿：预算只数 × 各怪种金币腿（碎金档把金币腿折到 1 枚）——
		var kill_stones := 0.0
		for key in mix:
			var row: Dictionary = mix[key]
			var share: float = float(row["share"])
			var exp_v: float = float(row["exp"])
			var has_gem: bool = bool(row["has_gem"])
			if not has_gem:
				continue
			var per_mob := (1.0 - shard_chance) * exp_v * float(GameBalance.MOB_KILL_EXP_MULT) \
				+ shard_chance * float(GameBalance.GEM_SHARD_STONE_VALUE)
			kill_stones += float(budget) * share * per_mob

		# —— 派生腿：血蛹分裂的史莱姆幼体 + 百目妖产的蜂群幼体（不占预算，各掉各的）——
		var derived := _derived_stones(wave, mix)

		# —— 匣子 ——
		var chest_stones := _chest_stones(wave)

		# —— 金蟾（W3 起，每回合 35% 概率）——
		var looter := 0.0
		if wave >= int(EnemyData.LOOTER_DEF["min_wave"]):
			looter = float(EnemyData.LOOTER_DEF["chance"]) * float(GameBalance.looter_stone_reward(wave))

		# —— 精英（W5/W15）/ Boss（W10/W20）——
		var boss_stones := 0.0
		var elite_stones := 0.0
		if GameBalance.is_boss_wave(wave):
			boss_stones = float(GameBalance.BOSS_STONE_REWARD) \
				+ float(GameBalance.ELITE_GEM_COUNT) * float(GameBalance.ELITE_GEM_EXP)
		elif GameBalance.is_elite_wave(wave):
			elite_stones = float(GameBalance.ELITE_STONE_BONUS) \
				+ float(GameBalance.ELITE_GEM_COUNT) * float(GameBalance.ELITE_GEM_EXP)

		# —— 灵韵（harvest 复利）——
		var harvest_gain := int(round(harvest_v))

		var wave_total := int(round(kill_stones + derived + chest_stones + looter + elite_stones + boss_stones)) \
			+ harvest_gain
		total += wave_total

		print("%-4d %-7d %-8.1f %-9.0f %-9.0f %-8.0f %-8.0f %-8.0f %-9d %-8d" % [
			wave, budget, avg_exp, kill_stones, derived, chest_stones,
			looter, elite_stones + boss_stones, wave_total, total])

		harvest_v = GameBalance.harvest_next(harvest_v, wave, GameManager.HARVEST_GROWTH_WAVE_CAP)

	print("".lpad(104, "-"))
	print("20 波累计：%d 枚金币（裸装、无灵韵、无道具加成）" % total)
	print("")
	print("【提前清场余时赏】额外金币")
	for secs in [5.0, 10.0, 20.0, 40.0]:
		print("  提前 %2.0f 秒清场 ⇒ +%d 枚金币（封顶 %d）" % [
			secs, GameBalance.early_clear_stones(secs), 20])
	print("")
	print("【商店支出对照】同一回合的金币能买几件")
	for wave in [1, 5, 10, 15, 20]:
		print("  W%-2d 武器 %d~%d ｜ 道具 %d~%d ｜ 回复药 %d ｜ 重掷 %d" % [
			wave,
			GameBalance.weapon_price(25, wave, 1.0),
			GameBalance.weapon_price(46, wave, 1.0),
			GameBalance.item_price(12, wave, 1.0),
			GameBalance.item_price(90, wave, 1.0),
			GameBalance.potion_price(10, wave, 1.0),
			GameBalance.reroll_cost(wave, 0, 1.0)])

	get_tree().quit(0)

## 本波怪种配比 + 平均 exp_reward：按 EnemyData.pick_scene_key 真实采样。
## 返回 {"mix": {key: {share, exp, has_gem}}, "avg": 平均 exp}
func _wave_mix(wave: int) -> Dictionary:
	# exp_reward 与是否掉宝石都取自场景 .tscn 的真值（has_gem = 无 heal_orb_drop）
	var info := {
		"slime": {"exp": 3, "has_gem": true}, "danbao": {"exp": 3, "has_gem": false},
		"xiexiu": {"exp": 5, "has_gem": true}, "leibeast": {"exp": 6, "has_gem": true},
		"flower": {"exp": 4, "has_gem": true}, "fengqun": {"exp": 2, "has_gem": true},
		"xueyong": {"exp": 4, "has_gem": true}, "yingmei": {"exp": 5, "has_gem": true},
		"lingyi": {"exp": 6, "has_gem": true}, "guyao": {"exp": 6, "has_gem": true},
		"duyao": {"exp": 5, "has_gem": true}, "zhumu": {"exp": 7, "has_gem": true},
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + wave
	var hits := {}
	for i in range(TRIALS):
		var key := EnemyData.pick_scene_key(wave, rng.randf())
		hits[key] = int(hits.get(key, 0)) + 1
	var out: Dictionary = {}
	var exp_sum := 0.0
	for key in hits:
		var share := float(hits[key]) / float(TRIALS)
		var d: Dictionary = info[key]
		out[key] = {"share": share, "exp": float(d["exp"]), "has_gem": bool(d["has_gem"])}
		exp_sum += share * float(d["exp"])
	return {"mix": out, "avg": exp_sum}

## 派生腿：血蛹死亡分裂 3 只史莱姆幼体（每只掉 3exp×1.75 金币腿，
## 但中碎金档就只剩 1 枚）；百目妖每 3.5 秒产 1 只蜂群幼体（2exp）。
## 两者都不占刷怪预算 ⇒ 是「白赚」的那部分收入。
func _derived_stones(wave: int, mix: Dictionary) -> float:
	var shard_chance := GameBalance.gem_shard_chance(wave)
	var budget := float(GameBalance.wave_spawn_budget(wave))
	# 血蛹（W6 起）：每只裂出 3 只史莱姆（3exp）
	var xueyong_share: float = 0.0
	if mix.has("xueyong"):
		xueyong_share = float(mix["xueyong"]["share"])
	var per_slime := (1.0 - shard_chance) * 3.0 * float(GameBalance.MOB_KILL_EXP_MULT) \
		+ shard_chance * float(GameBalance.GEM_SHARD_STONE_VALUE)
	var out: float = budget * xueyong_share * 3.0 * per_slime
	# 百目妖（W14 起）：每 3.5 秒产 1 只蜂群（2exp），按 80s 回合上限估 ≈ 22 只/只
	var zhumu_share: float = 0.0
	if mix.has("zhumu"):
		zhumu_share = float(mix["zhumu"]["share"])
	var per_fengqun := (1.0 - shard_chance) * 2.0 * float(GameBalance.MOB_KILL_EXP_MULT) \
		+ shard_chance * float(GameBalance.GEM_SHARD_STONE_VALUE)
	out += budget * zhumu_share * 22.0 * per_fengqun
	return out

## 匣子金币：各档 stones 直接进账 + 非葫芦腿撒出的 gem_count 颗宝石（每颗 gem_exp=5 金币）。
## 档位权重吃品质与福缘，这里按品质 0、福缘 0（裸装）算。
func _chest_stones(wave: int) -> float:
	var count := GameBalance.chest_count(wave, 0)
	var w := GameBalance.chest_tier_weights(0.0, 0.0)
	var total_w := 0.0
	for x in w:
		total_w += x
	var out := 0.0
	for tier in range(3):
		var p := float(w[tier]) / total_w
		var reward: Dictionary = GameBalance.chest_reward(tier)
		var heal_chance := float(reward.get("heal_chance", 0.0)) * GameBalance.danger_heal_chance_mult(DANGER)
		var stones := float(reward.get("stones", 0))
		var gems := float(reward.get("gem_count", 0)) * (1.0 - heal_chance) * float(reward.get("gem_exp", 1))
		out += p * float(count) * (stones + gems)
	return out
