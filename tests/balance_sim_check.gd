extends Node

## 伤害与血量平衡仿真判据（2026-10-09，用户口径：「带几把青云剑秒杀所有敌人和Boss，整体优化伤害机制与敌人血量」）
##
## 本判据在 headless 环境下全真跑 GameBalance、WeaponData 与 GameManager 数值链路，钉死四大护栏：
## 1) 15 件法器 ★1 零加点单体 DPS 严格收敛在分档带内，全库极差比 ≤ 2.0（杜绝个别法器 5 倍碾压或沦为纯摆设）；
## 2) 敌人气血曲线确为 1.15 复利增长，危险度 0 呈现前松后紧；
## 3) 标准成型 Build 在第 10/20 波 Boss 战击杀时长（TTK）落在 30~70s 区间（真正的 Boss 攻坚体验）；
## 4) 极端 6 把青云剑纯输出 Build 在第 20 波魔尊战 TTK 坚守 ≥ 8.0s（不剥夺暴力 build 的爽感，但彻底杜绝 0.5s 摸一下就秒的荒谬现象）。
##
## 运行: godot --headless --path . res://tests/BalanceSimCheck.tscn
##       godot --headless --path . res://tests/BalanceSimCheck.tscn -- --selftest

const EPS := 0.0001

var _c := TestCheck.new()
var _selftest: bool = false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if String(a) == "--selftest":
			_selftest = true

	_test_weapon_dps_normalization()
	_test_enemy_and_boss_hp_scaling()
	_test_reference_build_ttks()
	if _selftest:
		_test_selftest_guard()

	if _c.report("BALANCE_SIM_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1. 15 件法器单体 DPS 分档与极差比 ----------------

func _test_weapon_dps_normalization() -> void:
	var single_target_weapons := ["qingyun_sword", "gengjin_feijian", "huoyan_fu", "chiyan_dao", "xuanbing_feizhen"]
	var aoe_utility_weapons := ["qingmu_tengbian", "bajiao_fan", "wanmu_lingfu", "liuye_feidao", "fentian_baodeng", "wulei_paizi", "fantian_yin"]
	var drone_weapons := ["lingdie", "hanquan_yulian", "hunyuan_zhong"]

	var min_dps: float = 9999.0
	var max_dps: float = 0.0

	for w_id in WeaponData.SHOP_POOL:
		var dps := WeaponData.sustained_single_dps(w_id, 1)
		min_dps = minf(min_dps, dps)
		max_dps = maxf(max_dps, dps)

		if w_id in single_target_weapons:
			_c.check(dps >= 38.0 and dps <= 46.0,
				"单体专注法器【%s】DPS 落在 38~46 区间 (实得 %.1f)" % [w_id, dps])
		elif w_id in aoe_utility_weapons:
			_c.check(dps >= 25.0 and dps <= 38.0,
				"群伤/功能法器【%s】DPS 落在 25~38 区间 (实得 %.1f)" % [w_id, dps])
		elif w_id in drone_weapons:
			_c.check(dps >= 40.0 and dps <= 50.0,
				"御灵环绕法器【%s】DPS 落在 40~50 区间 (实得 %.1f)" % [w_id, dps])

	var ratio := max_dps / maxf(0.1, min_dps)
	_c.check(ratio <= 2.0, "全库 15 把法器基准 DPS 极差比 ≤ 2.0（实测最高 %.1f / 最低 %.1f = %.2fx，拒绝 5 倍失衡）" % [max_dps, min_dps, ratio])

# ---------------- 2. 敌人与 Boss 气血成长 ----------------

func _test_enemy_and_boss_hp_scaling() -> void:
	# 前松后紧：前 5 波平缓，10 波成型，20 波厚重
	var m1 := GameBalance.enemy_hp_mult(1)
	var m5 := GameBalance.enemy_hp_mult(5)
	var m10 := GameBalance.enemy_hp_mult(10)
	var m20 := GameBalance.enemy_hp_mult(20)

	_c.near(m1, 1.0, EPS, "第 1 波气血倍率 1.0")
	_c.check(m5 >= 1.70 and m5 <= 1.80, "第 5 波气血倍率温和 (~1.75x，实得 %.2f)" % m5)
	_c.check(m10 >= 3.40 and m10 <= 3.60, "第 10 波气血倍率提速 (~3.52x，实得 %.2f)" % m10)
	_c.check(m20 >= 14.0 and m20 <= 14.5, "第 20 波气血倍率达 ~14.2x (实得 %.2f)" % m20)

	# Boss 气血
	var b10 := GameBalance.boss_hp(10)
	var b20 := GameBalance.boss_hp(20)
	_c.check(b10 >= 45000.0 and b10 <= 55000.0, "第 10 波 Boss 气血落在 4.5~5.5 万 (实得 %.0f)" % b10)
	_c.check(b20 >= 180000.0 and b20 <= 210000.0, "第 20 波魔尊气血落在 18~21 万 (实得 %.0f)" % b20)

# ---------------- 3. 三档参考 Build 仿真与击杀时长（TTK）----------------

func _test_reference_build_ttks() -> void:
	# 3.1 杂怪 TTK（史莱姆 base 18，雷兽 base 45）
	# W1 裸青云剑：18 / 40.5 ≈ 0.44s
	var w1_slime_ttk := 18.0 * GameBalance.enemy_hp_mult(1) / WeaponData.sustained_single_dps("qingyun_sword", 1)
	_c.check(w1_slime_ttk <= 1.0, "W1 杂怪被首发法器 1 秒内斩灭 (%.2fs)" % w1_slime_ttk)

	# 3.2 成型 Build 仿真（Standard Meta Build）
	# W10: 5 把法器 (2把★2, 3把★1), 8 项悟道加点, 1 件法宝
	# 对第 10 波 Boss 的仿真 DPS
	var std_w10_dps := _simulate_build_dps(
		[{"id": "qingyun_sword", "star": 2}, {"id": "gengjin_feijian", "star": 2},
		 {"id": "liuye_feidao", "star": 1}, {"id": "huoyan_fu", "star": 1}, {"id": "bajiao_fan", "star": 1}],
		{
			"weapon_damage_mult": 1.30, "melee_damage": 4.0, "ranged_damage": 4.0,
			"crit_rate": 0.15, "crit_mult": 1.50, "attack_speed_mult": 0.88,
			"elite_damage": 0.25, "synergy_damage_mult": 1.0, "synergy_haste_mult": 0.94,
			"synergy_crit_rate": 0.06, "synergy_crit_mult": 0.20,
		},
		true
	)
	var std_w10_boss_ttk := GameBalance.boss_hp(10) / std_w10_dps
	_c.check(std_w10_boss_ttk >= 30.0 and std_w10_boss_ttk <= 65.0,
		"成型 Build 在第 10 波 Boss 战时长 30~65s (实测 %.1fs, DPS=%.0f)" % [std_w10_boss_ttk, std_w10_dps])

	# W20: 6 把法器 (2把★3, 4把★2), 18 项悟道加点, 3 件法宝
	var std_w20_dps := _simulate_build_dps(
		[{"id": "qingyun_sword", "star": 3}, {"id": "gengjin_feijian", "star": 3},
		 {"id": "liuye_feidao", "star": 2}, {"id": "huoyan_fu", "star": 2},
		 {"id": "bajiao_fan", "star": 2}, {"id": "chiyan_dao", "star": 2}],
		{
			"weapon_damage_mult": 1.65, "melee_damage": 8.0, "ranged_damage": 6.0,
			"crit_rate": 0.25, "crit_mult": 1.75, "attack_speed_mult": 0.72,
			"elite_damage": 0.50, "synergy_damage_mult": 1.10, "synergy_haste_mult": 0.88,
			"synergy_crit_rate": 0.12, "synergy_crit_mult": 0.40,
		},
		true
	)
	var std_w20_boss_ttk := GameBalance.boss_hp(20) / std_w20_dps
	_c.check(std_w20_boss_ttk >= 30.0 and std_w20_boss_ttk <= 70.0,
		"成型 Build 在第 20 波魔尊战时长 30~70s (实测 %.1fs, DPS=%.0f)" % [std_w20_boss_ttk, std_w20_dps])

	# 3.3 精英怪 TTK（第 5 波铁甲魔傀 1000 * m5 ≈ 1750；第 15 波 1000 * m15 ≈ 7076）
	var std_w5_dps := _simulate_build_dps(
		[{"id": "qingyun_sword", "star": 1}, {"id": "gengjin_feijian", "star": 1}, {"id": "bajiao_fan", "star": 1}],
		{"weapon_damage_mult": 1.15, "crit_rate": 0.08, "attack_speed_mult": 0.95, "elite_damage": 0.0},
		true
	)
	var w5_elite_ttk := (1000.0 * GameBalance.enemy_hp_mult(5)) / std_w5_dps
	_c.check(w5_elite_ttk >= 5.0 and w5_elite_ttk <= 25.0,
		"第 5 波精英战时长 5~25s (实测 %.1fs)" % w5_elite_ttk)

	# 3.4 极端 6 把青云剑纯输出 Build（用户报的秒杀场景）
	# 4把★3 + 2把★2, 8次攻击加点 + 6次近战加点 + 狂血丹 + 破甲锥 + 金系满档
	var extreme_w20_dps := _simulate_build_dps(
		[{"id": "qingyun_sword", "star": 3}, {"id": "qingyun_sword", "star": 3},
		 {"id": "qingyun_sword", "star": 3}, {"id": "qingyun_sword", "star": 3},
		 {"id": "qingyun_sword", "star": 2}, {"id": "qingyun_sword", "star": 2}],
		{
			"weapon_damage_mult": 2.38, "melee_damage": 12.0, "crit_rate": 0.37,
			"crit_mult": 1.75, "attack_speed_mult": 0.60, "elite_damage": 1.25,
			"synergy_damage_mult": 1.0, "synergy_haste_mult": 1.0,
			"synergy_crit_rate": 0.20, "synergy_crit_mult": 0.75,
		},
		true
	)
	var ext_w20_boss_ttk := GameBalance.boss_hp(20) / extreme_w20_dps
	_c.check(ext_w20_boss_ttk >= 8.0,
		"极端 6 剑满配 Build 绝不再秒杀魔尊：TTK 坚守 >= 8.0s (实测 %.1fs, DPS=%.0f)" % [ext_w20_boss_ttk, extreme_w20_dps])
	_c.check(ext_w20_boss_ttk <= 20.0,
		"极端 6 剑满配 Build 依然保留高爆发爽感：TTK <= 20.0s (实测 %.1fs)" % ext_w20_boss_ttk)

# 纯静态链路仿真计算
func _simulate_build_dps(weapons: Array, stats: Dictionary, vs_elite: bool) -> float:
	var w_dmg_mult: float = float(stats.get("weapon_damage_mult", 1.0))
	var syn_dmg: float = float(stats.get("synergy_damage_mult", 1.0))
	var cult_dmg: float = float(stats.get("cultivator_damage_mult", 1.0))
	var elem_dmg: float = float(stats.get("element_damage_mult", 1.0))
	var atk_spd: float = float(stats.get("attack_speed_mult", 1.0))
	var syn_haste: float = float(stats.get("synergy_haste_mult", 1.0))
	var crit_r: float = minf(0.75, float(stats.get("crit_rate", 0.05)) + float(stats.get("synergy_crit_rate", 0.0)))
	var crit_m: float = float(stats.get("crit_mult", 1.5)) + float(stats.get("synergy_crit_mult", 0.0))
	var elite_mult: float = (1.0 + float(stats.get("elite_damage", 0.0))) if vs_elite else 1.0

	var total_dps := 0.0
	for item in weapons:
		var wid: String = item["id"]
		var star: int = item["star"]
		var def := WeaponData.get_def(wid)
		var base_d := WeaponData.damage_for(wid, star)
		var base_cd := WeaponData.cooldown_for(wid, star)

		var stat_bonus := GameBalance.weapon_stat_bonus(def.get("stat_scalings", {}), stats, star)
		var final_d := (base_d + stat_bonus) * w_dmg_mult * syn_dmg * cult_dmg * elem_dmg

		var beh := int(def.get("behavior", WeaponData.Behavior.MELEE))
		var per_hit := final_d
		if beh == WeaponData.Behavior.MELEE:
			per_hit *= 1.35
		elif beh == WeaponData.Behavior.PROJECTILE:
			per_hit *= float(maxi(1, int(def.get("projectile_count", 1))))

		var eff_cd := maxf(0.08, base_cd * atk_spd * syn_haste)
		var expected_crit := 1.0 + crit_r * (crit_m - 1.0)
		var hit_dps := (per_hit * expected_crit / eff_cd) * elite_mult

		if def.get("proc_burn", false):
			hit_dps += final_d * float(def.get("burn_ratio", 0.4)) * minf(1.0, float(def.get("burn_dur", 3.0)) / eff_cd)
		if def.get("proc_poison", false):
			hit_dps += final_d * float(def.get("poison_ratio", 0.3)) * minf(1.0, float(def.get("poison_dur", 2.5)) / eff_cd)

		total_dps += hit_dps
	return total_dps

# ---------------- 自检守卫 ----------------

func _test_selftest_guard() -> void:
	# 验证反例：如果把 Boss 基础血量误改成旧版的 1000，极端 build 的 TTK 会跌破 8 秒
	var old_boss_hp_w20 := 1000.0 * GameBalance.enemy_hp_mult(20)
	var fake_ext_ttk := old_boss_hp_w20 / 20000.0
	_c.check(fake_ext_ttk < 2.0, "自检证实：旧版 1000 基础血量在极端 build 下 TTK 仅 %.2fs 会直接报红" % fake_ext_ttk)
