class_name UnitWaveTests
extends UnitTestsBase

## 单测模块：波次缩放 / Boss 波 / 刷怪量 / 怪物配比 / 危险度（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_wave_scaling() -> void:
	_c.near(GameBalance.enemy_hp_mult(1), 1.0, EPS, "第 1 波血量倍率 1.0")
	_c.near(GameBalance.enemy_hp_mult(10), pow(1.16, 9), EPS, "第 10 波血量复利 ×3.80")
	_c.near(GameBalance.enemy_hp_mult(20), pow(1.16, 19), EPS, "第 20 波血量复利 ×16.89")
	# 敌伤总闸：基线倍率只许出现在 enemy_dmg_mult 这一处出口
	_c.near(GameBalance.enemy_dmg_mult(1), GameBalance.ENEMY_DMG_BASE_MULT, EPS, "第 1 波敌伤倍率 = 整体基线（2026-10-13 提至 0.80）")
	_c.near(GameBalance.enemy_dmg_mult(10), GameBalance.ENEMY_DMG_BASE_MULT * pow(1.06, 9), EPS, "第 10 波敌伤 = 基线 × 复利 1.69")
	_c.near(GameBalance.enemy_dmg_mult(20) / GameBalance.enemy_dmg_mult(10), pow(1.06, 10), EPS, "波间复利梯度不因基线下移而变")
	_c.near(GameBalance.boss_contact_damage(1), ceilf(24.0 * GameBalance.ENEMY_DMG_BASE_MULT), EPS, "Boss 接触伤害与杂怪同一个总闸")
	_c.near(GameBalance.wave_duration(1), 35.9, EPS, "第 1 波时长 35.9s（2026-10-16 表再放宽一档，预算不动）")
	_c.near(GameBalance.wave_duration(20), 80.0, EPS, "第 20 波封顶 80s")
	_c.near(GameBalance.wave_duration(99), 80.0, EPS, "无尽波次也封顶 80s")
	_c.near(GameBalance.spawn_interval(1), 1.555, EPS, "第 1 波刷怪间隔 1.555s")
	_c.near(GameBalance.spawn_interval(40), GameBalance.SPAWN_INTERVAL_MIN, EPS, "刷怪间隔有下限")
	_c.near(GameBalance.enemy_hp_mult(0), GameBalance.enemy_hp_mult(1), EPS, "非法波次 0 被夹到 1")
	# 刷怪预算（2026-10-11 土豆兄弟式克制）：波内总刷入封顶，预算耗尽即停手，场上越打越空。
	# 2026-10-11 缩图+减怪（半场 680→500）：预算全程再降约 1/3（14/3.6/90），
	# 单怪血量基数同步 +33% 补压力，预算缺口由经验补差兜底（见 balance_sim_check 绑定契约）。
	# 刷怪预算（2026-10-15 分批清剿制）：每回合总刷入预算收窄，单批集中推进 + 间歇呼吸。
	# 单怪掉落经验由 MOB_KILL_EXP_MULT ×1.75 反向找平（每波总经验收入完全持平）。
	_c.equals(GameBalance.wave_spawn_budget(1), 10, "第 1 波预算 10（分批清剿制收紧）")
	_c.equals(GameBalance.wave_spawn_budget(5), 19, "第 5 波预算 19")
	_c.equals(GameBalance.wave_spawn_budget(6), 21, "第 6 波预算 21")
	_c.equals(GameBalance.wave_spawn_budget(10), 30, "第 10 波预算 30")
	_c.equals(GameBalance.wave_spawn_budget(20), 52, "第 20 波预算 52")
	# 2026-10-15 深层续涨：>20 波预算自 W20=52 续 +4/波，封顶 DEEP_BUDGET_MAX（135）。
	_c.equals(GameBalance.wave_spawn_budget(21), 56, "深层第 21 波预算 56（续涨 +4）")
	_c.equals(GameBalance.wave_spawn_budget(30), 92, "深层第 30 波预算 92")
	_c.equals(GameBalance.wave_spawn_budget(99), GameBalance.DEEP_BUDGET_MAX, "无尽深层预算封顶 135")
	var budget_prev := 0
	var budget_nondecreasing := true
	for w in range(1, 61):
		var b := GameBalance.wave_spawn_budget(w)
		if b < budget_prev:
			budget_nondecreasing = false
		budget_prev = b
	_c.check(budget_nondecreasing, "预算曲线逐波不降（触顶后持平，不回落）")
	# 深层段在封顶前必须每波都真的多刷（否则「敌潮随深层涨」落空）
	var deep_rises := 0
	for w in range(21, 40):
		if GameBalance.wave_spawn_budget(w) > GameBalance.wave_spawn_budget(w - 1):
			deep_rises += 1
	_c.equals(deep_rises, 19, "深层 21~39 波逐波续涨（封顶前不提前持平）")

	# 2026-10-15 分批清剿制：动态同屏上限
	_c.equals(GameBalance.max_enemies_cap(1), 6, "第 1 波同屏上限 6 只")
	_c.equals(GameBalance.max_enemies_cap(5), 8, "第 5 波同屏上限 8 只")
	_c.equals(GameBalance.max_enemies_cap(10), 10, "第 10 波同屏上限 10 只")
	_c.equals(GameBalance.max_enemies_cap(20), 16, "第 20 波同屏上限 16 只")
	_c.check(GameBalance.max_enemies_cap(30) > 16, "深层同屏上限高于 20 波")
	# 2026-10-17 性能专项：绝对硬顶常量钉住（cap 基础值之外，最终同屏再乘危险/潮数后由它兜底）
	_c.equals(GameBalance.MAX_ENEMIES_HARD_CAP, 48, "同屏敌人绝对硬顶 48（任何乘区叠满后的兜底）")

	# 2026-10-15 分批清剿制：小怪掉落经验补偿倍率（预算 -26% 的倒数），掉落与补差均值同走一个出口
	_c.near(GameBalance.MOB_KILL_EXP_MULT, 1.75, EPS, "小怪经验补偿倍率 1.75（改预算必须同步改它）")
	_c.equals(GameBalance.mob_kill_exp(3), 5, "史莱姆 exp 3 → 实发 5（×1.75 取整）")
	_c.equals(GameBalance.mob_kill_exp(5), 9, "邪修 exp 5 → 实发 9")
	_c.equals(GameBalance.mob_kill_exp(0), 0, "非法 exp 0 不放大")

	# 2026-10-13 深层难度：伤害/生命复利在 >20 波提档，分段处连续，≤20 波零回归
	_c.near(GameBalance.enemy_dmg_mult(21) / GameBalance.enemy_dmg_mult(20), GameBalance.DEEP_DMG_GROWTH, EPS, "第 21 波敌伤梯度 = 深层复利 1.12")
	_c.near(GameBalance.enemy_dmg_mult(20) / GameBalance.enemy_dmg_mult(10), pow(1.06, 10), EPS, "20 波段梯度仍为 1.06 复利（正常局零回归）")
	_c.near(GameBalance.enemy_hp_mult(21) / GameBalance.enemy_hp_mult(20), GameBalance.DEEP_HP_GROWTH, EPS, "第 21 波血量梯度 = 深层复利 1.22")
	# 深层复利必须真的比旧梯子快，否则三涨名存实亡
	_c.check(GameBalance.enemy_dmg_mult(30) > GameBalance.ENEMY_DMG_BASE_MULT * pow(GameBalance.ENEMY_DMG_GROWTH, 29), "深层敌伤快于旧 1.06 外推")
	_c.check(GameBalance.enemy_hp_mult(30) > pow(GameBalance.ENEMY_HP_GROWTH, 29), "深层血量快于旧 1.16 外推")
	var dmg_prev := 0.0
	var hp_prev := 0.0
	var deep_monotonic := true
	for w in range(1, 61):
		var d := GameBalance.enemy_dmg_mult(w)
		var h := GameBalance.enemy_hp_mult(w)
		if d <= dmg_prev or h <= hp_prev:
			deep_monotonic = false
		dmg_prev = d
		hp_prev = h
	_c.check(deep_monotonic, "伤害/生命倍率全程严格递增（分段处无塌陷、不读 autoload 的纯函数单调）")
	# 深层同屏密度：≤20 波恒 1.0，此后 +8%/波、封顶 2.2
	_c.near(GameBalance.endless_swarm_mult(20), 1.0, EPS, "20 波前同屏密度不放大")
	_c.near(GameBalance.endless_swarm_mult(1), 1.0, EPS, "第 1 波同屏密度不放大（正常局零影响）")
	_c.near(GameBalance.endless_swarm_mult(21), 1.08, EPS, "深层第 21 波同屏密度 +8%")
	_c.near(GameBalance.endless_swarm_mult(99), GameBalance.DEEP_SWARM_MAX, EPS, "同屏密度放大封顶 ×2.2")

	# 弹速与攻击间隔缩放断言
	_c.near(GameBalance.enemy_bolt_speed_mult(1), 1.0, EPS, "第 1 波弹速基线 1.0")
	_c.check(GameBalance.enemy_bolt_speed_mult(20) > 1.20, "第 20 波弹速成长 > 1.20")
	_c.check(GameBalance.enemy_bolt_speed_mult(30) > GameBalance.enemy_bolt_speed_mult(20), "无尽深层弹速继续成长")
	_c.near(GameBalance.enemy_attack_cd_mult(1), 1.0, EPS, "第 1 波技能冷却基线 1.0")
	_c.check(GameBalance.enemy_attack_cd_mult(20) <= 0.86, "第 20 波技能冷却收紧 ≤ 0.86")
	_c.check(GameBalance.enemy_attack_cd_mult(35) < GameBalance.enemy_attack_cd_mult(20), "深层攻击冷却进一步加快")
	_c.equals(GameBalance.enemy_bonus_bolts(1), 0, "前期小怪无额外齐射")
	_c.equals(GameBalance.enemy_bonus_bolts(16), 1, "第 16 波起小怪额外 +1 发齐射")
	_c.equals(GameBalance.enemy_bonus_bolts(25), 2, "第 25 波起小怪额外 +2 发齐射")

func _test_boss_waves() -> void:
	_c.check(GameBalance.is_boss_wave(10), "第 10 波是固定 Boss 关")
	_c.check(GameBalance.is_boss_wave(20), "第 20 波是固定 Boss 关（心魔劫）")
	_c.check(not GameBalance.is_boss_wave(5), "第 5 波仍是精英不是 Boss")
	_c.check(not GameBalance.is_boss_wave(15), "第 15 波仍是精英不是 Boss")
	_c.check(not GameBalance.is_boss_wave(9), "非 Boss 波次不错判")
	_c.check(GameBalance.is_boss_wave(30), "无尽 30 波再逢魔君")
	# 2026-10-13 深层 Boss 加密：20 波后每 5 波一场（25/30/35…），非 5 倍数波次不是 Boss
	_c.check(GameBalance.is_boss_wave(25), "无尽 25 波起每 5 波逢魔君")
	_c.check(GameBalance.is_boss_wave(35), "无尽 35 波是 Boss")
	_c.check(GameBalance.is_boss_wave(45), "无尽 45 波是 Boss")
	_c.check(not GameBalance.is_boss_wave(26), "无尽 26 波不是 Boss")
	_c.check(not GameBalance.is_boss_wave(28), "无尽 28 波不是 Boss")

	# 10/20 波让位给魔君，无尽模式非 Boss 关每关逢精英（逢 5 关出 Boss）
	_c.check(GameBalance.is_elite_wave(5), "第 5 波精英保留")
	_c.check(GameBalance.is_elite_wave(15), "第 15 波精英保留")
	_c.check(not GameBalance.is_elite_wave(10), "第 10 波不再刷精英（Boss 关）")
	_c.check(not GameBalance.is_elite_wave(20), "第 20 波不再刷精英（Boss 关）")
	_c.check(not GameBalance.is_elite_wave(21), "非无尽模式 21 波不是精英")
	_c.check(GameBalance.is_elite_wave(21, true), "无尽 21 波每关精英")
	_c.check(GameBalance.is_elite_wave(22, true), "无尽 22 波每关精英")
	_c.check(not GameBalance.is_elite_wave(25, true), "无尽 25 波是 Boss 不是精英（逢 5 波逢魔君后让位）")
	_c.check(not GameBalance.is_elite_wave(30, true), "无尽 30 波是 Boss 不是精英")
	_c.equals(GameBalance.elite_spawn_count_for_wave(21, true), 1, "21 波单精英")
	_c.equals(GameBalance.elite_spawn_count_for_wave(31, true), 2, "31 波起双精英同场")

	# Boss 血条厚度：与普通敌人同曲线，靠基础值拉开 ~5~7 倍精英的差距
	_c.near(GameBalance.boss_hp(10) / GameBalance.boss_hp(1), GameBalance.enemy_hp_mult(10), EPS, "Boss 血量与敌人同一条成长曲线")
	var golem_w10 := 1000.0 * GameBalance.enemy_hp_mult(10)
	_c.check(GameBalance.boss_hp(10) >= golem_w10 * 5.0 - EPS, "第 10 波 Boss 血量至少精英 5 倍 (%.0f vs %.0f)" % [GameBalance.boss_hp(10), golem_w10])
	_c.check(GameBalance.boss_hp(20) > GameBalance.boss_hp(10), "第 20 波魔尊血更厚")
	_c.check(GameBalance.boss_contact_damage(20) > GameBalance.boss_contact_damage(1), "Boss 接触伤害随波次成长")

func _test_spawn_shape() -> void:
	_c.equals(GameBalance.spawn_batch(1, 0.0), 5, "第 1 波分批清剿 + 触发追加 → 5 只")
	_c.equals(GameBalance.spawn_batch(1, 0.9), 4, "第 1 波分批未触发追加 → 4 只")
	_c.equals(GameBalance.spawn_batch(8, 0.9), 5, "第 8 波分批 → 5 只")
	_c.equals(GameBalance.spawn_batch(8, 0.0), 6, "第 8 波分批追加 → 6 只")
	_c.equals(GameBalance.ELITE_STONE_BONUS, 25, "精英额外灵石 25")
	var count_at_cap := 0
	for i in range(200):
		count_at_cap += GameBalance.spawn_batch(20, 0.0)
	_c.check(count_at_cap > 200, "后期每轮必然多于 1 只")

func _test_enemy_mix() -> void:
	# 用户口径 2026-10-08：「这个放火球的敌人怎么要到七八波才出来？不一开始就应该有吗」
	# 旧配比是「累计带 + 波次闸门」，闸门一开邪修直接吃掉整段（第 8 波突然 27%），
	# 而闸门未开时下一格白捡（第 5~7 波雷兽 42%）。现在火球怪第 1 波就在场内、按占比爬坡。
	_c.near(WaveSpawner.xiexiu_edge(1), 0.06, EPS, "邪修第 1 波占比 6%（一开始就有，但只是零星）")
	_c.near(WaveSpawner.xiexiu_edge(8), EnemyData.MOBS["xiexiu"]["ramp_cap"], EPS, "邪修第 8 波爬到上沿 27%")
	_c.near(WaveSpawner.xiexiu_edge(20), EnemyData.MOBS["xiexiu"]["ramp_cap"], EPS, "上沿封顶，后期不再无限涨")
	var prev := 0.0
	var monotonic := true
	for w in range(1, 21):
		var edge := WaveSpawner.xiexiu_edge(w)
		if edge < prev - EPS:
			monotonic = false
		prev = edge
	_c.check(monotonic, "邪修占比逐波不降（难度阶梯单调）")
	# 2026-10-16 登场聚焦与每波主打怪：roll 头部切两块份额，尾部重标定回 [0,1) 走原分段带。
	# 带子口径断言一律走 pick_band_key（不含头部份额），与 pick_scene_key 的头部行为解耦。
	_c.equals(WaveSpawner.pick_band_key(1, 0.03), "xiexiu", "第 1 波 roll 落在邪修带内 → 邪修")
	_c.equals(WaveSpawner.pick_band_key(1, 0.06), "slime", "第 1 波邪修只占 6%，其余仍是史莱姆")
	_c.equals(WaveSpawner.pick_band_key(1, 0.5), "slime", "第 1 波仍不刷花妖（维持第 2 波解锁）")
	_c.equals(WaveSpawner.pick_band_key(3, 0.05), "danbao", "第 3 波丹爆傀儡已解锁，roll<0.12 → 丹爆傀儡")
	_c.equals(WaveSpawner.pick_band_key(3, 0.20), "flower", "第 3 波邪修带被丹爆整段吃掉（[0.12,0.12) 为空），roll 0.20 落在花妖带")
	_c.equals(WaveSpawner.pick_band_key(3, 0.70), "slime", "第 3 波高 roll 但未到蜂群带（0.70 < 0.78）仍是史莱姆")
	_c.equals(WaveSpawner.pick_band_key(5, 0.15), "xiexiu", "第 5 波邪修带为 [0.12, 0.18)，roll 0.15 落邪修")
	_c.equals(WaveSpawner.pick_band_key(5, 0.30), "leibeast", "第 5 波雷兽带为 [0.18, 0.42)")
	_c.equals(WaveSpawner.pick_band_key(12, 0.05), "danbao", "第 12 波 roll<0.12 → 丹爆傀儡")
	_c.equals(WaveSpawner.pick_band_key(12, 0.20), "xiexiu", "第 12 波 [0.12, 0.27) → 邪修")
	_c.equals(WaveSpawner.pick_band_key(12, 0.35), "leibeast", "第 12 波 [0.27, 0.42) → 雷兽")
	var seen := {}
	for w in range(1, 25):
		for i in range(100):
			seen[WaveSpawner.pick_scene_key(w, float(i) / 100.0)] = true
	_c.equals(seen.keys().size(), 14, "十四种怪在配比表里都真的会被选到（key 拼错=悄悄全刷史莱姆）")

	# 批三新敌种：高 roll 段从史莱姆的保底份额里切走，逐波解锁
	_c.equals(WaveSpawner.pick_band_key(1, 0.80), "slime", "第 1 波高 roll 仍是史莱姆（新敌种未解锁）")
	_c.equals(WaveSpawner.pick_band_key(3, 0.80), "fengqun", "第 3 波蜂群精解锁")
	_c.equals(WaveSpawner.pick_band_key(6, 0.90), "xueyong", "第 6 波血蛹解锁（死亡分裂，带 [0.88,0.92)）")
	_c.equals(WaveSpawner.pick_band_key(7, 0.93), "yingmei", "第 7 波影魅解锁（闪现侧翼）")
	_c.equals(WaveSpawner.pick_band_key(7, 0.85), "fengqun", "第 7 波灵医未解锁，roll 0.85 落回蜂群带（闸门让位）")
	_c.equals(WaveSpawner.pick_band_key(8, 0.85), "lingyi", "第 8 波灵医解锁（治疗同伴，带 [0.83,0.88)）")
	_c.equals(WaveSpawner.pick_band_key(9, 0.96), "guyao", "第 9 波鼓妖解锁（加速光环）")
	_c.equals(WaveSpawner.pick_band_key(13, 0.99), "guyao", "蛛母未解锁时其份额落回鼓妖带（闸门让位）")
	_c.equals(WaveSpawner.pick_band_key(14, 0.99), "zhumu", "第 14 波蛛母解锁（产卵孵化）")
	_c.equals(WaveSpawner.pick_band_key(16, 0.97), "hanpo", "第 16 波寒魄妖解锁（三发冰魄）")
	_c.equals(WaveSpawner.pick_band_key(19, 0.99), "mowei", "第 19 波血煞魔卫解锁（重装魔卫）")

	# 毒妖（2026-10-13 投毒）：与花妖共段 [0.42, flower_edge)，判序在前切走 35%。
	# 共段的代价是必须同时钉住「两边都还在」——只断言解锁会让花妖被悄悄整段吃掉而不被发现
	_c.equals(WaveSpawner.pick_band_key(6, 0.50), "duyao", "第 6 波毒妖解锁（投毒持续伤害区域，占 [0.42,0.54)）")
	_c.equals(WaveSpawner.pick_band_key(6, 0.60), "flower", "毒妖共段后花妖仍占自己的份额（不被整段吃掉）")
	_c.equals(WaveSpawner.pick_band_key(5, 0.50), "flower", "第 5 波毒妖未解锁，[0.42,0.54) 整段落回花妖")
	_c.near(WaveSpawner.duyao_edge(6), 0.5418, EPS, "毒妖第 6 波上沿 0.5418（0.42 + (0.768-0.42)×0.35）")
	_c.near(WaveSpawner.duyao_edge(14), WaveSpawner.duyao_edge(6), EPS, "花妖带封顶后毒妖份额不再增长（同一条曲线封顶）")

# 2026-10-16 登场聚焦 / 每波主打怪 / 批次刷新阈值爬坡（节奏紧凑化）
func _test_wave_theme() -> void:
	# 登场聚焦：本波新解锁的怪合吃头部 20% 份额（同波多只按序均分），先见识机制再回落混池
	_c.equals(EnemyData.debut_group(1), [], "第 1 波无新解锁（邪修走自己的爬坡格，不进登场组）")
	_c.equals(EnemyData.debut_group(2), ["flower"], "第 2 波登场组 = 花妖（unlock_wave 2）")
	_c.equals(EnemyData.debut_group(3), ["danbao", "fengqun"], "第 3 波登场组 = 丹爆 + 蜂群（同波两个解锁，表序）")
	_c.equals(EnemyData.debut_group(6), ["xueyong", "duyao"], "第 6 波登场组 = 血蛹 + 毒妖（同波两个解锁）")
	_c.equals(EnemyData.debut_group(7), ["yingmei"], "第 7 波登场组 = 影魅（unlock_wave 7）")
	_c.equals(EnemyData.debut_group(12), [], "第 12 波无新解锁（W9 之后到 W14 才有下一个）")
	_c.equals(EnemyData.debut_group(14), ["zhumu"], "第 14 波登场组 = 百目妖")
	_c.equals(EnemyData.debut_group(16), ["hanpo"], "第 16 波登场组 = 寒魄妖")
	_c.equals(EnemyData.debut_group(19), ["mowei"], "第 19 波登场组 = 血煞魔卫")
	# 登场段真的吃进 pick_scene_key 头部：roll < 0.20 必出登场组内的怪，且组内均分
	for w in range(1, 21):
		var group: Array = EnemyData.debut_group(w)
		if group.is_empty():
			continue
		var got0 := WaveSpawner.pick_scene_key(w, 0.0)
		var got19 := WaveSpawner.pick_scene_key(w, 0.19)
		_c.check(group.has(got0), "第 %d 波 roll 0 → 登场组 %s 之一（实得 %s）" % [w, str(group), got0])
		_c.check(group.has(got19), "第 %d 波 roll 0.19（登场段内）→ 登场组之一（实得 %s）" % [w, got19])
	_c.equals(WaveSpawner.pick_scene_key(3, 0.0), "danbao", "第 3 波登场段前半 → 丹爆")
	_c.equals(WaveSpawner.pick_scene_key(3, 0.19), "fengqun", "第 3 波登场段后半 → 蜂群（组内均分）")

	# 每波主打怪：第 1 波不出（纯教学），第 2 波起从已解锁怪轮换、不选保底史莱姆/未解锁/登场怪
	_c.equals(EnemyData.featured_mob(1), "", "第 1 波不出主打怪（史莱姆 + 零星邪修的教学波）")
	var feat_ok := true
	for w in range(2, 41):
		var feat := EnemyData.featured_mob(w)
		if feat == "" or feat == "slime":
			feat_ok = false
		var row: Dictionary = EnemyData.MOBS.get(feat, {})
		if row.is_empty() or (row.has("unlock_wave") and int(row["unlock_wave"]) > w):
			feat_ok = false
		if EnemyData.debut_group(w).has(feat):
			feat_ok = false
	_c.check(feat_ok, "第 2~40 波主打怪都有值、已解锁、非史莱姆、不与登场组撞车")
	# 轮换要真的换（不许常年同一只）：连续 12 波里至少出现 3 种
	var feat_seen := {}
	for w in range(2, 14):
		feat_seen[EnemyData.featured_mob(w)] = true
	_c.check(feat_seen.keys().size() >= 3, "主打怪 12 波内至少轮换出 3 种（实得 %d 种）" % feat_seen.keys().size())
	# 头部份额与重标定：roll 落在头部之外时，尾部仍能选到原带子里的怪（重标定不吞份额）
	_c.check(EnemyData.DEBUT_SHARE + EnemyData.FEATURED_SHARE < 0.5, "头部两块份额之和 < 50%（尾部分段带仍有主体份额）")
	var tail_seen := {}
	for w in range(1, 25):
		for i in range(100):
			var r := 0.35 + float(i) / 100.0 * 0.65
			tail_seen[WaveSpawner.pick_scene_key(w, r)] = true
	_c.check(tail_seen.keys().size() >= 10, "尾部区间仍能选到绝大多数怪种（实得 %d 种）" % tail_seen.keys().size())

	# 批次刷新阈值爬坡（2026-10-16 节奏紧凑化）：W1-3 → 1 / W4-9 → 2 / W10+ → 3
	_c.equals(GameBalance.batch_refill_threshold(1), 1, "第 1 波刷新阈值 1（保留前期单批清剿喘息）")
	_c.equals(GameBalance.batch_refill_threshold(3), 1, "第 3 波阈值仍为 1")
	_c.equals(GameBalance.batch_refill_threshold(4), 2, "第 4 波阈值升到 2")
	_c.equals(GameBalance.batch_refill_threshold(9), 2, "第 9 波阈值仍为 2")
	_c.equals(GameBalance.batch_refill_threshold(10), 3, "第 10 波阈值升到 3")
	_c.equals(GameBalance.batch_refill_threshold(99), 3, "无尽深层阈值封顶 3")
	_c.equals(GameBalance.batch_refill_threshold(0), 1, "非法波次 0 夹到第 1 波阈值")
	var thr_prev := 0
	var thr_monotonic := true
	for w in range(1, 41):
		var t := GameBalance.batch_refill_threshold(w)
		if t < thr_prev:
			thr_monotonic = false
		thr_prev = t
	_c.check(thr_monotonic, "刷新阈值逐波不降（爬坡单调）")
	_c.near(GameBalance.BATCH_CLEAR_COOLDOWN, 0.6, EPS, "呼吸间隙压缩到 0.6s（2026-10-16 紧凑化）")
	_c.near(GameBalance.BATCH_STALEMATE_TIMEOUT, 5.5, EPS, "对峙超时收紧到 5.5s（2026-10-16 紧凑化）")

func _test_danger_system() -> void:
	# 公式钉线（2026-10-20 收缩为 4 档，顶档维持原 D5 的封顶强度）
	_c.equals(GameBalance.DANGER_MAX, 3, "危险度共 4 档（D0~D3）")
	_c.near(GameBalance.danger_hp_mult(0), 1.08, EPS, "危险度 0 简单基线 ×1.08")
	_c.near(GameBalance.danger_hp_mult(3), 2.58, EPS, "危险度 3 噩梦血量 ×2.58（= 原 D5 封顶）")
	_c.near(GameBalance.danger_dmg_mult(3), 1.84, EPS, "危险度 3 噩梦伤害 ×1.84（= 原 D5 封顶）")
	_c.near(GameBalance.danger_count_mult(3), 2.08, EPS, "危险度 3 噩梦妖潮 ×2.08（= 原 D5 封顶）")
	_c.near(GameBalance.danger_hp_mult(99), GameBalance.danger_hp_mult(3), EPS, "超档夹到 3")
	_c.near(GameBalance.danger_hp_mult(-1), 1.08, EPS, "负档夹到 0")
	# 档间单调递增，不能因为压缩出现持平或倒挂
	for d in range(GameBalance.DANGER_MAX):
		_c.check(GameBalance.danger_hp_mult(d + 1) > GameBalance.danger_hp_mult(d), "血量档间严格递增 D%d→D%d" % [d, d + 1])
		_c.check(GameBalance.danger_dmg_mult(d + 1) > GameBalance.danger_dmg_mult(d), "伤害档间严格递增 D%d→D%d" % [d, d + 1])
		_c.check(GameBalance.danger_count_mult(d + 1) > GameBalance.danger_count_mult(d), "妖潮档间严格递增 D%d→D%d" % [d, d + 1])

	# 逐级通关解锁（2026-10-25）：可选上限 = 生涯最高通关难度 + 1，未通关只开 D0。
	# 备份/还原玩家的真实生涯档，避免测试把别人的进度压低。
	var orig_bdc := int(GameManager.career_stats.get("best_danger_cleared", -1))
	GameManager.career_stats["best_danger_cleared"] = -1
	_c.equals(GameManager.max_danger_unlocked(), 0, "从未通关时只开放「简单」")
	for d in range(GameBalance.DANGER_MAX + 1):
		GameManager.set_danger(d)
		_c.equals(GameManager.danger_level, 0, "未通关时点 D%d 被夹回 D0" % d)
	_c.check(GameManager.is_danger_unlocked(0), "D0 默认可用")
	_c.check(not GameManager.is_danger_unlocked(1), "D1 未通关前不可用")

	# 通关 Dk → D(k+1) 开放
	for cleared in range(GameBalance.DANGER_MAX):
		GameManager.career_stats["best_danger_cleared"] = cleared
		_c.equals(GameManager.max_danger_unlocked(), cleared + 1, "通关 D%d 后开放到 D%d" % [cleared, cleared + 1])
		_c.check(GameManager.is_danger_unlocked(cleared + 1), "通关 D%d 后 D%d 可选" % [cleared, cleared + 1])
		if cleared + 2 <= GameBalance.DANGER_MAX:
			_c.check(not GameManager.is_danger_unlocked(cleared + 2), "通关 D%d 后 D%d 仍锁着" % [cleared, cleared + 2])

	# 顶档通关后不再往上涨（越界夹到顶档）
	GameManager.career_stats["best_danger_cleared"] = GameBalance.DANGER_MAX
	_c.equals(GameManager.max_danger_unlocked(), GameBalance.DANGER_MAX, "顶档通关后上限仍是顶档")
	GameManager.set_danger(99)
	_c.equals(GameManager.danger_level, GameBalance.DANGER_MAX, "越界档位夹到顶档")
	GameManager.set_danger(-5)
	_c.equals(GameManager.danger_level, 0, "负档夹到简单")
	GameManager.career_stats["best_danger_cleared"] = orig_bdc
	GameManager.danger_level = 0

	# 名号与封印表长度与档数同步
	_c.equals(AchievementData.DANGER_NAMES.size(), GameBalance.DANGER_MAX + 1, "难度名号数与档数一致")
	_c.equals(AchievementData.REALM_TITLES.size(), GameBalance.DANGER_MAX + 1, "境界称号数与档数一致")
	_c.equals(AchievementData.danger_name(GameBalance.DANGER_MAX), "噩梦", "顶档名号为噩梦")
	_c.equals(AchievementData.realm_for_danger(GameBalance.DANGER_MAX), "元婴", "顶档境界为元婴")

# 2026-10-12 新机制数值钉线：精英变异阈值 / 灵医奶量曲线 / 金蟾金币曲线 / 移速方差
func _test_new_enemy_mechanics() -> void:
	_c.near(GameBalance.ELITE_MUTATION_HP_PCT, 0.6, EPS, "精英变异血线 60%")
	_c.near(GameBalance.ENEMY_SPEED_VARIANCE, 0.12, EPS, "个体移速方差 ±12%（快慢梯队）")
	_c.near(GameBalance.healer_amount(1), 6.0, EPS, "灵医第 1 波每跳奶 6")
	_c.near(GameBalance.healer_amount(10), 6.0 * pow(1.16, 9), EPS, "灵医奶量与敌人血量同一条复利曲线")
	_c.check(GameBalance.healer_amount(20) > GameBalance.healer_amount(10), "灵医奶量随波次递增")
	_c.equals(GameBalance.looter_stone_reward(3), 19, "金蟾第 3 波击杀金币 19")
	_c.check(GameBalance.looter_stone_reward(20) > GameBalance.looter_stone_reward(3), "金蟾金币随波次递增")
	# 变异倍率档位合理性：精英震地不许达到 Boss 档
	_c.check(GameBalance.MUT_GOLEM_SLAM_RADIUS < GameBalance.BOSS_SLAM_RADIUS, "精英震地半径小于 Boss 档")
	_c.check(GameBalance.MUT_JIANSHA_BOLT_COUNT > 3, "剑客亡灵变异后剑气更多")
	GameManager._save_progress()
	GameManager.danger_level = 0
	GameManager.reset_run()

# enemy_id 推导注册表（2026-10-13）：EnemyBase._deduce_enemy_id 的 16 分支 begins_with 链
# 已改为遍历 EnemyData.ID_PREFIXES。这条钉三件事，防新增怪种时漏登记：
# ① MOBS 每种普通怪都在 ID_PREFIXES 里有前缀（否则新怪会静默降级成史莱姆外观）；
# ② ID_PREFIXES 相对 MOBS 多出来的恰好是 chilei_elite / jiansha_elite 两个精英 id；
# ③ 前缀互不为前缀（否则遍历顺序会决定猜哪个，改表序就换结果）。
func _test_enemy_id_prefixes() -> void:
	var missing: Array = []
	for key in EnemyData.MOBS:
		if not EnemyData.ID_PREFIXES.has(String(key)):
			missing.append(String(key))
	_c.check(missing.is_empty(), "MOBS 每种怪都在 ID_PREFIXES 登记了前缀（漏登记会静默降级成史莱姆外观）：%s" % str(missing))

	# ID_PREFIXES 相对 MOBS 多出来的必须是「已知非 MOBS 来源」四类：Boss、精英池、金蟾（LOOTER_DEF）。
	var non_mobs: Array = []
	for id in EnemyData.ID_PREFIXES:
		if not EnemyData.MOBS.has(String(id)):
			non_mobs.append(String(id))
	non_mobs.sort()
	_c.equals(non_mobs, ["boss", "chilei_elite", "golem", "jiansha_elite", "jinchan", "wandu_elite", "xingpan_elite", "xuanming_elite"],
		"ID_PREFIXES 比 MOBS 多的恰好是 boss / 精英 ids / 金蟾（冒出别的就是漏登记）")
	# 反向：精英池与 Boss/金蟾的前缀也必须在表里，否则它们的怪会静默降级成史莱姆外观
	for row in EnemyData.ELITE_POOL:
		var eid := String(row.get("id", ""))
		_c.check(EnemyData.ID_PREFIXES.has(eid) or EnemyData.ID_PREFIXES.has(eid + "_elite"),
			"精英 %s 在前缀表里有登记（带或不带 _elite 后缀）" % eid)
	_c.check(EnemyData.ID_PREFIXES.has("boss") and EnemyData.ID_PREFIXES.has("jinchan"),
		"Boss 与金蟾在前缀表里有登记")
	_c.equals(EnemyData.ELITE_POOL.size(), 6, "精英池扩充为 6 种差异化原型")
	_c.equals(EnemyData.BOSS_POOL.size(), 6, "Boss 池覆盖 10~40 波 6 大魔君")
	_c.equals(GameBalance.boss_id_for_wave(10), "chiyan", "W10 Boss 为赤炎魔将")
	_c.equals(GameBalance.boss_id_for_wave(20), "xiuluo", "W20 Boss 为血煞修罗（冲刺狂战）")
	_c.equals(GameBalance.boss_id_for_wave(25), "qianji", "W25 Boss 为玄天千机尊（不动炮台）")
	_c.equals(GameBalance.boss_id_for_wave(30), "wangu", "W30 Boss 为万蛊蚀天母（禁区统御）")
	_c.equals(GameBalance.boss_id_for_wave(35), "jianpo", "W35 Boss 为幽冥剑魄尊（瞬身剑客）")
	_c.equals(GameBalance.boss_id_for_wave(40), "xinmo", "W40 Boss 为九幽心魔尊（终极全能）")
	_c.equals(GameBalance.boss_id_for_wave(45), "chiyan", "W45 起按序轮回循环首轮 chiyan")
	_c.equals(GameBalance.boss_id_for_wave(50), "xiuluo", "W50 轮回循环次轮 xiuluo")

	var overlapping: Array = []
	for a in EnemyData.ID_PREFIXES:
		for b in EnemyData.ID_PREFIXES:
			if String(a) == String(b):
				continue
			if String(b).begins_with(String(a)):
				overlapping.append("%s 是 %s 的前缀" % [String(a), String(b)])
	_c.check(overlapping.is_empty(), "前缀互不为前缀（否则遍历顺序决定猜哪个）：%s" % str(overlapping))
