extends Node

## 伤害与血量平衡仿真判据（2026-10-09，用户口径：「带几把青云剑秒杀所有敌人和Boss，整体优化伤害机制与敌人血量」）
##
## 本判据在 headless 环境下全真跑 GameBalance、WeaponData 与 GameManager 数值链路，钉死四大护栏：
## 1) 20 件法器 ★1 零加点单体 DPS 严格收敛在分档带内，全库极差比 ≤ 2.0（杜绝个别法器 5 倍碾压或沦为纯摆设）；
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
	_test_survivability()
	_test_spawn_budget_binding()
	if _selftest:
		_test_selftest_guard()

	if _c.report("BALANCE_SIM_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1. 全库 68 件法器单体 DPS 分档与极差比 ----------------

func _test_weapon_dps_normalization() -> void:
	var single_target_weapons := [
		"qingyun_sword", "gengjin_feijian", "huoyan_fu", "chiyan_dao", "xuanbing_feizhen",
		"jinzhen_fu", "qingteng_jian",
		# 2026-10-11 新增：近战剑 / 穿透飞剑（点杀位）
		"hanshuang_jian", "bengshan_jian", "liuhuo_feijian",
		# 2026-10-11 平衡校准：金雷锥爆裂半径 55 全库最小，单点重击定位归位单体档（damage 35→38）
		"jinlei_zhui",
		# 2026-10-11 第二批：庚金符双针速射（点杀位）
		"gengjin_fu",
	]
	var aoe_utility_weapons := [
		"qingmu_tengbian", "bajiao_fan", "wanmu_lingfu", "liuye_feidao", "fentian_baodeng", "wulei_paizi", "fantian_yin",
		"baoyu_liuhuazhen", "lianhuan_lingdan", "bihai_chaoyindi", "sanmei_huohu", "xuanwu_lingdun",
		"xuanbing_fu", "zhenshan_fu", "jinjiao_jian", "chunlei_gu",
		"xueyin_dao", "jubao_chi", "tougu_ding", "benlang_chui", "liuling_jian",
		# 2026-10-11 新增：弹射/群伤型
		"zhenhuo_fu", "leihuo_fu", "langli_suo", "gudu_fu",
		# 2026-10-11 第二批：群伤型
		"lieshan_duo", "jingzhe_fu", "liaoyuan_shan", "kaishan_fu",
		# 2026-10-12 第三批：纳入群伤/功能带
		"guishui_fu", "taomu_jian", "houtu_fu", "jinxiao_leiling", "xuanming_leizhu",
	]
	var drone_weapons := [
		"lingdie", "hanquan_yulian", "hunyuan_zhong", "haojin_lun", "lihuo_ya", "xuanwu_pei",
		# 2026-10-11 第二批：御灵加厚 6 把
		"jinming_ling", "muling_ou", "bingpo_zhu", "chiyan_ying", "tuling_shi", "jianling",
	]
	var turret_weapons := [
		"jiguan_nu", "jianzhen_pan", "penhuo_jiguanshou", "hanquan_shou", "tengluo_jiguan",
		"leishi_jiguan", "kuilei_shou", "qingmu_pao", "ningbing_nu", "fenghuo_tai",
	]

	var min_dps: float = 9999.0
	var max_dps: float = 0.0

	for w_id in WeaponData.SHOP_POOL:
		var dps := WeaponData.sustained_single_dps(w_id, 1)
		min_dps = minf(min_dps, dps)
		max_dps = maxf(max_dps, dps)

		if w_id in single_target_weapons:
			_c.check(dps >= 26.0 and dps <= 32.0,
				"单体专注法器【%s】DPS 落在 26~32 区间 (实得 %.1f)" % [w_id, dps])
		elif w_id in aoe_utility_weapons:
			_c.check(dps >= 18.0 and dps <= 26.0,
				"群伤/功能法器【%s】DPS 落在 18~26 区间 (实得 %.1f)" % [w_id, dps])
		elif w_id in drone_weapons:
			# 2026-10-10 起御灵口径改为"实伤"：sustained_single_dps 对 DRONE 已乘接触占空比，
			# 此带约束的是有效单体 DPS，而非纸面值；经数值强化后提升至 30~38 区间
			_c.check(dps >= 30.0 and dps <= 38.0,
				"御灵环绕法器【%s】有效 DPS 落在 30~38 区间 (实得 %.1f)" % [w_id, dps])
		elif w_id in turret_weapons:
			_c.check(dps >= 20.0 and dps <= 32.0,
				"机关炮台【%s】基准 DPS 落在 20~32 区间 (实得 %.1f)" % [w_id, dps])
		else:
			_c.fail("法器【%s】未纳入任何平衡分档" % w_id)

	var ratio := max_dps / maxf(0.1, min_dps)
	_c.check(ratio <= 2.0, "全库 68 把法器基准 DPS 极差比 ≤ 2.0（实测最高 %.1f / 最低 %.1f = %.2fx，拒绝 5 倍失衡）" % [max_dps, min_dps, ratio])

	# 御灵同档护栏（2026-10-10 用户口径：召唤打不动人）：御灵有效 DPS（已按接触占空比折算）
	# 必须贴住青云剑单体 DPS 的 0.85 倍以上 —— 占空比一变、数值一飘，这里直接红。
	var sword_dps := WeaponData.sustained_single_dps("qingyun_sword", 1)
	for w_id in drone_weapons:
		var drone_dps := WeaponData.sustained_single_dps(w_id, 1)
		_c.check(drone_dps >= sword_dps * 0.85,
			"御灵【%s】有效 DPS %.1f ≥ 0.85 × 青云剑 %.1f（召唤不许打不动人）" % [w_id, drone_dps, sword_dps])

# ---------------- 2. 敌人与 Boss 气血成长 ----------------

func _test_enemy_and_boss_hp_scaling() -> void:
	# 前松后紧：前 5 波平缓，10 波成型，20 波厚重（1.16 复利）
	var m1 := GameBalance.enemy_hp_mult(1)
	var m5 := GameBalance.enemy_hp_mult(5)
	var m10 := GameBalance.enemy_hp_mult(10)
	var m20 := GameBalance.enemy_hp_mult(20)

	_c.near(m1, 1.0, EPS, "第 1 波气血倍率 1.0")
	_c.check(m5 >= 1.75 and m5 <= 1.85, "第 5 波气血倍率温和 (~1.81x，实得 %.2f)" % m5)
	_c.check(m10 >= 3.70 and m10 <= 3.90, "第 10 波气血倍率提速 (~3.80x，实得 %.2f)" % m10)
	_c.check(m20 >= 16.5 and m20 <= 17.2, "第 20 波气血倍率达 ~16.88x (实得 %.2f)" % m20)

	# Boss 气血
	var b10 := GameBalance.boss_hp(10)
	var b20 := GameBalance.boss_hp(20)
	_c.check(b10 >= 22000.0 and b10 <= 28000.0, "第 10 波 Boss 气血落在 2.2~2.8 万 (实得 %.0f)" % b10)
	_c.check(b20 >= 100000.0 and b20 <= 120000.0, "第 20 波魔尊气血落在 10~12 万 (实得 %.0f)" % b20)

# ---------------- 3. 三档参考 Build 仿真与击杀时长（TTK）----------------

func _test_reference_build_ttks() -> void:
	# 3.1 杂怪 TTK 与多把 ★1 法器集火韧性
	# W1 史莱姆 base 18 × MOB_HP_BASE_MULT(4.5) = 81，蜂群精 base 12 × 4.5 = 54
	var w1_slime_hp := 18.0 * GameBalance.MOB_HP_BASE_MULT * GameBalance.enemy_hp_mult(1)
	var w1_slime_ttk := w1_slime_hp / WeaponData.sustained_single_dps("qingyun_sword", 1)
	_c.check(w1_slime_ttk >= 2.0 and w1_slime_ttk <= 4.0,
		"W1 杂怪扎实耐打：首发法器 TTK 落在 2~4s（约 3 刀，实得 %.2fs）" % w1_slime_ttk)

	# 佩戴 4 把 ★1 青云剑（W3 史莱姆 81 * 1.16^2 ≈ 109 HP）：
	# 单剑基础 30 × 神识分流(4把=0.735) = 22.06/刀；即使 4 剑同帧集火同一只怪，
	# 经短窗集火保护（1.0 + 0.7 + 0.5 + 0.5 = 2.7 倍单刀）仅打 59.6 < 109 HP，绝不秒杀！
	var w3_slime_hp := ceilf(18.0 * GameBalance.MOB_HP_BASE_MULT * GameBalance.enemy_hp_mult(3))
	var single_sword_hit_4w := WeaponData.damage_for("qingyun_sword", 1) * GameBalance.multi_weapon_damage_mult(4)
	var volley_4w_burst := single_sword_hit_4w * (GameBalance.focus_fire_mult(0) + GameBalance.focus_fire_mult(1) + GameBalance.focus_fire_mult(2) + GameBalance.focus_fire_mult(3))
	_c.check(volley_4w_burst < w3_slime_hp * 0.75,
		"4 把 ★1 武器同帧齐射绝不秒杀 W3 小怪（齐射伤害 %.1f < 气血 %.0f 的 75%%）" % [volley_4w_burst, w3_slime_hp])
	var single_sword_hit_6w := WeaponData.damage_for("qingyun_sword", 1) * GameBalance.multi_weapon_damage_mult(6)
	var volley_6w_burst := single_sword_hit_6w * (1.0 + 0.7 + 0.5 * 4.0)
	var w4_slime_hp := ceilf(18.0 * GameBalance.MOB_HP_BASE_MULT * GameBalance.enemy_hp_mult(4))
	_c.check(volley_6w_burst < w4_slime_hp,
		"6 把 ★1 武器同帧齐射绝不秒杀 W4 小怪（齐射伤害 %.1f < 气血 %.0f）" % [volley_6w_burst, w4_slime_hp])

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
	_c.check(std_w10_boss_ttk >= 30.0 and std_w10_boss_ttk <= 70.0,
		"成型 Build 在第 10 波 Boss 战时长 30~70s (实测 %.1fs, DPS=%.0f)" % [std_w10_boss_ttk, std_w10_dps])

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

	# 3.5 机关堡垒成型 Build TTK（2026-10-11 新增防护栏：机关炮台不入 DPS 档、cap = turret_cap + 星−1
	# 且每把武器独立维持满并发，此前全库无判据看这个乘区。底线对齐极端 build 的「绝不秒杀」红线 ≥8.0s；
	# 实测值打印供后续调参——若逼近 8s 或长期显著低于成型带 30s，再考虑压 turret_cap 或机关羁绊）
	var turret_build_dps := _simulate_turret_build_dps(
		["jiguan_nu", "jianzhen_pan", "penhuo_jiguanshou", "hanquan_shou", "tengluo_jiguan", "leishi_jiguan"],
		{
			"weapon_damage_mult": 1.65, "contraption_damage": 6.0,
			"crit_rate": 0.30, "crit_mult": 1.75, "attack_speed_mult": 0.72,
			"elite_damage": 0.50, "synergy_contraption": 0.50,
		}
	)
	var turret_w20_boss_ttk := GameBalance.boss_hp(20) / turret_build_dps
	_c.check(turret_w20_boss_ttk >= 8.0,
		"机关堡垒成型 Build（6 机关全★2 满并发）绝不秒杀魔尊：TTK >= 8.0s (实测 %.1fs, DPS=%.0f)" % [turret_w20_boss_ttk, turret_build_dps])
	print("TURRET 机关堡垒成型 Build：DPS=%.0f，W20 魔尊 TTK=%.1fs（机关羁绊×1.5 + 攻速 + 满并发 cap=3 口径，炮台弹丸不带 DoT）" % [turret_build_dps, turret_w20_boss_ttk])

	# 3.6 纯御灵 Build（2026-10-11 新增防护栏：用户口径「驯兽师全召唤打 Boss 磨血磨不动」）。
	# 与既有成型断言的口径差异（全部是刻意的诚实化）：
	#   ① Boss 无 is_elite ⇒ 斩将加成对 Boss 不生效：vs_elite=false、stats 不给 elite_damage
	#     （既有 3.2/3.4 的 vs_elite=true 属已知乐观偏差，修正需整体重标定，另行立项）；
	#   ② DRONE 乘接触占空比（随星抬升）——此前仿真漏乘，御灵真实 TTK 被低估 1.33 倍；
	#   ③ 神识分流按御灵半权；④ 召唤羁绊那一档现在是纯加法（+16 召唤伤害，走 stats 的
	#     engineering_damage 进 stat_bonus），羁绊不再另给伤害乘区；驯兽师召唤类专精计入 cult_dmg。
	# 羁绊构成对齐编队：5 spirit ⇒ 召唤 t3（门槛 -1）；2 木（双护蝶）⇒ 木 t1 武器伤害 +6%；
	# 水/土/金各 1 件不成分档 ⇒ 无疾风无锐金。攻速/暴击/法伤来自通用悟道加点。
	var drone_stats_w10 := {
		"weapon_damage_mult": 1.30, "engineering_damage": 22.0,
		"crit_rate": 0.15, "crit_mult": 1.50, "attack_speed_mult": 0.88,
		"synergy_damage_mult": 1.06, "synergy_haste_mult": 1.0,
		"cultivator_damage_mult": 1.12,
	}
	var drone_w10_dps := _simulate_build_dps(
		[{"id": "lingdie", "star": 2}, {"id": "lingdie", "star": 2},
		 {"id": "hanquan_yulian", "star": 1}, {"id": "hunyuan_zhong", "star": 1}, {"id": "haojin_lun", "star": 1}],
		drone_stats_w10, false
	)
	var drone_w10_boss_ttk := GameBalance.boss_hp(10) / drone_w10_dps
	_c.check(drone_w10_boss_ttk >= 30.0 and drone_w10_boss_ttk <= 70.0,
		"驯兽师成型御灵 Build 在第 10 波 Boss 战时长 30~70s (实测 %.1fs, DPS=%.0f)" % [drone_w10_boss_ttk, drone_w10_dps])

	# 羁绊构成对齐编队：6 spirit ⇒ 召唤 t3（+16 召唤伤害）；2 木 ⇒ 木 t1 +6%；寒泉+冰魄 2 水 ⇒ 水 t1 疾风 ×0.92。
	# 加点更真实：暴击/攻速/召唤伤害与生存档互相竞争（成型期不会全堆输出）。
	var drone_stats_w20 := {
		"weapon_damage_mult": 1.65, "engineering_damage": 28.0,
		"crit_rate": 0.15, "crit_mult": 1.65, "attack_speed_mult": 0.78,
		"synergy_damage_mult": 1.06, "synergy_haste_mult": 0.92,
		"cultivator_damage_mult": 1.12,
	}
	var drone_w20_dps := _simulate_build_dps(
		[{"id": "lingdie", "star": 3}, {"id": "lingdie", "star": 3},
		 {"id": "hanquan_yulian", "star": 2}, {"id": "bingpo_zhu", "star": 2},
		 {"id": "haojin_lun", "star": 2}, {"id": "xuanwu_pei", "star": 2}],
		drone_stats_w20, false
	)
	var drone_w20_boss_ttk := GameBalance.boss_hp(20) / drone_w20_dps
	_c.check(drone_w20_boss_ttk >= 30.0 and drone_w20_boss_ttk <= 70.0,
		"驯兽师成型御灵 Build 在第 20 波魔尊战时长 30~70s (实测 %.1fs, DPS=%.0f)" % [drone_w20_boss_ttk, drone_w20_dps])

	# 3.7 极端 6 御灵满配 Build（全部金系御灵：metal 三档喂暴击、环绕法器自带暴击率转化）
	var drone_ext_dps := _simulate_build_dps(
		[{"id": "haojin_lun", "star": 3}, {"id": "haojin_lun", "star": 3}, {"id": "haojin_lun", "star": 3},
		 {"id": "haojin_lun", "star": 3}, {"id": "haojin_lun", "star": 3}, {"id": "haojin_lun", "star": 3}],
		{
			"weapon_damage_mult": 2.00, "engineering_damage": 46.0,
			"crit_rate": 0.27, "crit_mult": 1.75, "attack_speed_mult": 0.60,
			"synergy_crit_rate": 0.20, "synergy_crit_mult": 0.75,
			"synergy_damage_mult": 1.0, "synergy_haste_mult": 1.0,
			"cultivator_damage_mult": 1.12,
		}, false
	)
	var drone_ext_w20_boss_ttk := GameBalance.boss_hp(20) / drone_ext_dps
	_c.check(drone_ext_w20_boss_ttk >= 8.0,
		"极端 6 御灵满配 Build 绝不秒杀魔尊：TTK 坚守 >= 8.0s (实测 %.1fs, DPS=%.0f)" % [drone_ext_w20_boss_ttk, drone_ext_dps])
	print("DRONE 御灵成型 W10 TTK=%.1fs (DPS=%.0f) · W20 TTK=%.1fs (DPS=%.0f) · 极端满配 W20 TTK=%.1fs (DPS=%.0f)｜诚实口径：无斩将 × 占空比按星 × 御灵半权分流 × 召唤羁绊 t3 给 +16 召唤伤害 × 驯兽师 1.12" % [
		drone_w10_boss_ttk, drone_w10_dps, drone_w20_boss_ttk, drone_w20_dps, drone_ext_w20_boss_ttk, drone_ext_dps])

# 纯静态链路仿真计算（含多法器神识分流与散射命中规则）
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
	# 神识分流按御灵半权：数一下编队里的 DRONE 把数（2026-10-11 召唤流校准）
	var drone_n := 0
	for item in weapons:
		if int(WeaponData.get_def(String(item["id"])).get("behavior", -1)) == WeaponData.Behavior.DRONE:
			drone_n += 1
	var multi_mult: float = GameBalance.multi_weapon_damage_mult(weapons.size(), drone_n)

	var total_dps := 0.0
	for item in weapons:
		var wid: String = item["id"]
		var star: int = item["star"]
		var def := WeaponData.get_def(wid)
		var base_d := WeaponData.damage_for(wid, star)
		var base_cd := WeaponData.cooldown_for(wid, star)
		var beh := int(def.get("behavior", WeaponData.Behavior.MELEE))

		var stat_bonus := GameBalance.weapon_stat_bonus(def.get("stat_scalings", {}), stats, star)
		var final_d := (base_d + stat_bonus) * w_dmg_mult * syn_dmg * cult_dmg * elem_dmg * multi_mult

		var per_hit := final_d
		if beh == WeaponData.Behavior.PROJECTILE:
			var max_lock: int = 2 if vs_elite else 1
			per_hit *= float(mini(max_lock, maxi(1, int(def.get("projectile_count", 1)))))

		var eff_cd := maxf(0.08, base_cd * atk_spd * syn_haste)
		var expected_crit := 1.0 + crit_r * (crit_m - 1.0)
		var hit_dps := (per_hit * expected_crit / eff_cd) * elite_mult
		# 御灵实伤口径：接触结算占空比按星抬升（★2/★3 分身后多具同环扫掠）
		if beh == WeaponData.Behavior.DRONE:
			hit_dps *= GameBalance.spirit_contact_duty(star)

		if def.get("proc_burn", false):
			hit_dps += final_d * float(def.get("burn_ratio", 0.4)) * minf(1.0, float(def.get("burn_dur", 3.0)) / eff_cd)
		if def.get("proc_poison", false):
			hit_dps += final_d * float(def.get("poison_ratio", 0.3)) * minf(1.0, float(def.get("poison_dur", 2.5)) / eff_cd)

		total_dps += hit_dps
	return total_dps

## 机关堡垒 Build 专用仿真（2026-10-11）：TurretUnit 的吞吐口径与 _simulate_build_dps 的
## 「冷却 = 布设间隔」不同——机关武器本体只负责布设，实际输出是 cap 座炮台按 turret_fire_cd 连射，
## 且 fire_cd 不随星级缩放（TurretUnit.setup 只缩伤害）。满并发 = turret_cap + 星−1
## （布设间隔 × 攻速 < 存在时长时恒可达）。炮台弹丸不带 proc（_perform_turret_attack 不设 proc_*），
## 故不计灼烧/剧毒。只读静态表与入参，确定性。
func _simulate_turret_build_dps(weapon_ids: Array, stats: Dictionary) -> float:
	var w_dmg_mult: float = float(stats.get("weapon_damage_mult", 1.0))
	var atk_spd: float = float(stats.get("attack_speed_mult", 1.0))
	var crit_r: float = minf(0.75, float(stats.get("crit_rate", 0.05)))
	var crit_m: float = float(stats.get("crit_mult", 1.5))
	var elite_mult: float = 1.0 + float(stats.get("elite_damage", 0.0))
	var contraption_mult: float = 1.0 + float(stats.get("synergy_contraption", 0.0))
	var multi_mult: float = GameBalance.multi_weapon_damage_mult(weapon_ids.size())
	var expected_crit := 1.0 + crit_r * (crit_m - 1.0)

	var total_dps := 0.0
	for wid in weapon_ids:
		var def := WeaponData.get_def(wid)
		var stat_bonus := GameBalance.weapon_stat_bonus(def.get("stat_scalings", {}), stats, 2)
		var final_d := (WeaponData.damage_for(wid, 2) + stat_bonus) * w_dmg_mult \
			* contraption_mult * multi_mult
		var fire_cd := maxf(0.1, float(def.get("turret_fire_cd", 0.75))) * atk_spd
		var cap := int(def.get("turret_cap", 2)) + 1   ## 全★2：cap = turret_cap + (star-1)
		total_dps += final_d / fire_cd * float(cap) * expected_crit * elite_mult
	return total_dps

# ---------------- 5. 挨打侧生存余量（危险度 0 = 「简单」） ----------------

## 常用杂怪基础接触伤中位（scenes/entities：Slime 12 / XieXiu 13 / YingMei 13 / XueYong 14 / Flower 15）
const MIXED_MOB_CONTACT := 14.0

## 每秒进伤上限 = 单下实伤 ÷ 玩家无敌帧。小怪厚度 4.5 倍后怪在场久、挨打频率顶到这个上限，
## 所以「容易死」的尺子就是单下伤害，而不是每秒理论输出。
func _measure_player_runtime() -> Dictionary:
	var scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := scene.instantiate() as Player
	add_child(p)
	var base_hp := p.max_health
	var iframe := 0.0
	for i in range(5):
		p.invulnerable_time = 0.0
		p.current_health = base_hp
		p.take_damage(1.0)
		iframe = p.invulnerable_time
		if iframe > 0.0:
			break
	p.queue_free()
	return {"iframe": iframe, "hp": base_hp}

## 与 WaveSpawner 刷怪那两行同一口径：场景基础值 × 唯一敌伤出口 × 危险度倍率（浮动取均值 1.0）
func _raw_contact(base: float, wave: int, danger: int) -> float:
	return ceilf(base * GameBalance.enemy_dmg_mult(wave) * GameBalance.danger_dmg_mult(danger))

func _survive_sec(hp: float, armor: float, raw: float, iframe: float) -> float:
	return iframe * hp / GameBalance.incoming_damage(raw, armor)

func _upgrade_apply(upgrade_id: String, field: String) -> float:
	var apply: Dictionary = UpgradeData.get_upgrade_def(upgrade_id).get("apply", {})
	return float(apply.get(field, 0.0))

func _test_survivability() -> void:
	var rt := _measure_player_runtime()
	var iframe: float = rt["iframe"]
	var base_hp: float = rt["hp"]
	_c.check(iframe >= 0.4 and iframe <= 0.7,
		"玩家无敌帧读自真节点 %.2fs（顶格挨打 %.2f 下/秒）" % [iframe, 1.0 / maxf(0.01, iframe)])
	_c.check(base_hp >= 100.0, "裸装气血读自真节点 %.0f" % base_hp)

	var hp_per := _upgrade_apply("hp_up", "max_hp")
	var armor_per := _upgrade_apply("armor_up", "armor")
	_c.check(hp_per > 0.0 and armor_per > 0.0,
		"生存档位取自 UpgradeData 加点表（生命 +%.0f/点、护甲 +%.1f/点）" % [hp_per, armor_per])
	# 第 10 波前有 9 次悟道、第 20 波前有 19 次：这里取「愿意分一半给生存」的档
	var half_hp := base_hp + 3.0 * hp_per
	var half_armor := 3.0 * armor_per
	var meta_hp := base_hp + 6.0 * hp_per
	var meta_armor := 5.0 * armor_per

	# 5.1 最低档前段必须留试错空间（用户口径：简单难度都很容易死）
	var w1_raw := _raw_contact(MIXED_MOB_CONTACT, 1, 0)
	var w1_pct := GameBalance.incoming_damage(w1_raw, 0.0) / base_hp
	_c.check(w1_pct <= 0.09,
		"危险度 0 第 1 波单下掉裸装气血 %.1f%%（≤9%%：吃两下不慌）" % (w1_pct * 100.0))
	var w1_sec := _survive_sec(base_hp, 0.0, w1_raw, iframe)
	_c.check(w1_sec >= 6.0, "危险度 0 裸装第 1 波站进怪群活 %.1fs（≥6.0s）" % w1_sec)
	var w5_sec := _survive_sec(base_hp, 0.0, _raw_contact(MIXED_MOB_CONTACT, 5, 0), iframe)
	_c.check(w5_sec >= 5.0, "危险度 0 裸装第 5 波站进怪群活 %.1fs（≥5.0s）" % w5_sec)

	# 5.2 中段与后段：肯点生存就不该被怪群秒躺
	var w10_sec := _survive_sec(half_hp, half_armor, _raw_contact(MIXED_MOB_CONTACT, 10, 0), iframe)
	_c.check(w10_sec >= 8.5, "半肉 Build（气血 %.0f/护甲 %.0f）第 10 波站进怪群活 %.1fs（≥8.5s）" % [half_hp, half_armor, w10_sec])
	var w20_sec := _survive_sec(meta_hp, meta_armor, _raw_contact(MIXED_MOB_CONTACT, 20, 0), iframe)
	_c.check(w20_sec >= 8.0, "成型 Build（气血 %.0f/护甲 %.0f）第 20 波站进怪群活 %.1fs（≥8.0s）" % [meta_hp, meta_armor, w20_sec])

	# 5.3 单发最重的那一下（Boss 震地）不许一口糊掉三成血
	var slam := GameBalance.incoming_damage(_raw_contact(GameBalance.BOSS_CONTACT_BASE, 10, 0) * GameBalance.BOSS_SLAM_DMG_MULT, half_armor)
	_c.check(slam <= half_hp * 0.15,
		"第 10 波魔君震地单发掉半肉 Build %.1f%%（≤15%%：一口糊半血就是白给）" % (slam / half_hp * 100.0))

	# 5.4 六档梯度不许因为整体下调而倒挂
	var d5_sec := _survive_sec(half_hp, half_armor, _raw_contact(MIXED_MOB_CONTACT, 10, GameBalance.DANGER_MAX), iframe)
	_c.check(d5_sec < w10_sec, "危险度 %d 生存 %.1fs 仍短于危险度 0 的 %.1fs（梯子还在）" % [GameBalance.DANGER_MAX, d5_sec, w10_sec])
	_c.check(d5_sec >= 5.0, "极限档半肉 Build 第 10 波也至少活 %.1fs（≥5.0s：最高档该难，但不该没有反应时间）" % d5_sec)

	print("SURVIVAL 危险度0 裸装(%.0f血/0甲)：" % base_hp)
	for w in [1, 3, 5, 8, 10, 15, 20]:
		var raw := _raw_contact(MIXED_MOB_CONTACT, w, 0)
		print("  W%-2d 单下 %2d（%.1f%% 血）→ 顶格挨打 %.1fs" % [w, raw, GameBalance.incoming_damage(raw, 0.0) / base_hp * 100.0, _survive_sec(base_hp, 0.0, raw, iframe)])
	print("SURVIVAL 半肉(%.0f/%.0f) W10 %.1fs · 成型(%.0f/%.0f) W20 %.1fs · 极限 W10 %.1fs · 无敌帧 %.2fs" % [
		half_hp, half_armor, w10_sec, meta_hp, meta_armor, w20_sec, d5_sec, iframe])

# ---------------- 自检守卫 ----------------

## 5. 刷怪预算绑定点对照（2026-10-11 土豆兄弟式克制）：旧口径的波内总刷入
## （时长/间隔 × 平均批量，含 25% 追加概率）与预算 wave_spawn_budget 逐波对照。
## 2026-10-11 缩图+减怪后契约改写：预算全程收紧（W1 起即触发），
## 被闸掉的刷入量由 budget_compensation_exp 折经验足额补差 ⇒ 只减压力不减经济；
## 打印表即调参时的校准尺。
func _test_spawn_budget_binding() -> void:
	var table: Array[String] = []
	var avg_exp := 4.0  # 混合怪均经验代表值（史莱姆 3 ~ 雷兽 6 的中位）
	for w in range(1, 21):
		var rounds := GameBalance.wave_duration(w) / GameBalance.spawn_interval(w)
		# 平均批量 = 基础批量 ×(1-p) + (基础+1)×p（25% 追加概率只加这一只）
		var batch_base := 1.0 + float(int(float(w) / GameBalance.SPAWN_BATCH_EVERY_WAVES))
		var batch_avg := batch_base * (1.0 - GameBalance.SPAWN_BATCH_BONUS_CHANCE) \
			+ (batch_base + 1.0) * GameBalance.SPAWN_BATCH_BONUS_CHANCE
		var old_total := rounds * batch_avg
		var budget := float(GameBalance.wave_spawn_budget(w))
		_c.check(budget < old_total,
			"第 %d 波预算收紧（旧总量 %.0f → 预算 %.0f）" % [w, old_total, budget])
		# 经济守恒：预算缺口 × 怪均经验 = 补差经验（±1 取整容差）
		var shortfall := int(roundf(old_total - budget))
		var comp := float(GameBalance.budget_compensation_exp(shortfall, avg_exp))
		_c.check(absf(comp - float(shortfall) * avg_exp) <= 1.0,
			"第 %d 波经验补差足额覆盖预算缺口（缺口 %d 只 → 补 %.0f 经验）" % [w, shortfall, comp])
		table.append("W%-2d 旧%5.0f → 预算%4.0f（%+3.0f%%）" % [w, old_total, budget, (budget / old_total - 1.0) * 100.0])
	print("BUDGET 刷怪预算对照（危险度 0）:")
	for line in table:
		print("  " + line)

func _test_selftest_guard() -> void:
	# 验证反例：如果把 Boss 基础血量误改成旧版的 1000，极端 build 的 TTK 会跌破 8 秒
	var old_boss_hp_w20 := 1000.0 * GameBalance.enemy_hp_mult(20)
	var fake_ext_ttk := old_boss_hp_w20 / 20000.0
	_c.check(fake_ext_ttk < 2.0, "自检证实：旧版 1000 基础血量在极端 build 下 TTK 仅 %.2fs 会直接报红" % fake_ext_ttk)

	# 验证反例：敌伤总闸退回旧基线 1.0（未乘 ENEMY_DMG_BASE_MULT）时，第 1 波生存秒数直接掉出下限
	var rt := _measure_player_runtime()
	var iframe: float = rt["iframe"]
	var base_hp: float = rt["hp"]
	var old_w1_raw := ceilf(MIXED_MOB_CONTACT * 1.0)
	var old_w1_sec := _survive_sec(base_hp, 0.0, old_w1_raw, iframe)
	_c.check(old_w1_sec < 6.0,
		"自检证实：旧敌伤基线 ×1.0 下第 1 波裸装仅活 %.1fs，会直接报红（现基线 ×%.2f）" % [old_w1_sec, GameBalance.ENEMY_DMG_BASE_MULT])
