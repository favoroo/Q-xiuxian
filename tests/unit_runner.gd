extends Node

## 数值逻辑单元测试：纯函数 + 少量需要 GameManager 状态的商店断言
## 运行: godot --headless --path . res://tests/UnitRunner.tscn
## 这些公式以前埋在 autoload / 刷怪器里，必须起整棵场景树才能碰；
## 现在它们都在 GameBalance（static 纯函数）、随机源可由 GameManager.rng 注入，所以能直接断言。

const EPS := 0.0001

var _c := TestCheck.new()

func _ready() -> void:
	_test_exp_curve()
	_test_armor()
	_test_wave_scaling()
	_test_boss_waves()
	_test_spawn_shape()
	_test_enemy_mix()
	_test_enemy_bolt()
	_test_pricing()
	_test_harvest()
	_test_rarity_weights()
	_test_weighted_pick()
	_test_synergy_levels()
	_test_upgrade_table()
	_test_upgrade_roll_filters()
	_test_alloc_session()
	_test_shop_determinism()
	_test_main_tag_pity()
	_test_shop_tag_soft_bias()
	_test_weapon_targeting()
	_test_audio_wiring()
	_test_settings_manager()
	_test_screen_shake_budget()
	_test_five_elements_system()
	_test_ranged_focus_dps()
	_test_new_stat_fields()
	_test_item_system()
	_test_cultivator_system()
	_test_danger_system()
	_test_achievement_and_meta_save()
	_test_knock_direction()
	_test_spirit_orbit_dynamics()

	if _c.report("UNIT_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 经验 / 等级 ----------------

func _test_exp_curve() -> void:
	GameManager.reset_run()
	_c.equals(GameManager.experience_to_next, GameBalance.EXP_FIRST_LEVEL, "1 级起始修为取自 GameBalance")
	_c.equals(GameBalance.exp_to_next(10), 18, "exp_to_next(10)=int(13.5)+5")
	_c.equals(GameBalance.exp_to_next(18), 29, "exp_to_next(18)=int(24.3)+5")
	var prev := 1
	var monotonic := true
	for i in range(20):
		var nxt := GameBalance.exp_to_next(prev)
		if nxt <= prev:
			monotonic = false
		prev = nxt
	_c.check(monotonic, "经验曲线严格递增（20 级）")

	# 与 GameManager 的升级循环同源：喂满一次升级，检查下一级门槛就是公式值
	GameManager.add_experience(GameBalance.EXP_FIRST_LEVEL)
	_c.equals(GameManager.level, 2, "喂满初始修为后升到 2 级")
	_c.equals(GameManager.experience_to_next, GameBalance.exp_to_next(GameBalance.EXP_FIRST_LEVEL), "第 2 级门槛与公式一致")

# ---------------- 护甲 / 受伤 ----------------

func _test_armor() -> void:
	_c.near(GameBalance.armor_reduction(0.0), 0.0, EPS, "0 护甲无减伤")
	_c.near(GameBalance.armor_reduction(10.0), 1.0 - 1.0 / 1.8, EPS, "10 护甲减伤 44.4%")
	_c.near(GameBalance.incoming_damage(100.0, 10.0), 100.0 * (1.0 - GameBalance.armor_reduction(10.0)), 0.01, "面板减伤与实伤同源")
	_c.near(GameBalance.incoming_damage(1.0, 5000.0), GameBalance.DAMAGE_FLOOR, EPS, "极高护甲仍保底 1 点实伤")
	_c.near(GameBalance.incoming_damage(50.0, -20.0), 50.0, EPS, "负护甲不会被当成增益")
	var last := 999.0
	var decreasing := true
	for a in range(0, 60):
		var v := GameBalance.incoming_damage(100.0, float(a))
		if v > last + EPS:
			decreasing = false
		last = v
	_c.check(decreasing, "护甲越高实伤单调不增")
	_c.check(GameBalance.armor_reduction(100000.0) < 1.0, "减伤永远达不到 100%")

# ---------------- 波次缩放 ----------------

func _test_wave_scaling() -> void:
	_c.near(GameBalance.enemy_hp_mult(1), 1.0, EPS, "第 1 波血量倍率 1.0")
	_c.near(GameBalance.enemy_hp_mult(10), pow(1.15, 9), EPS, "第 10 波血量复利 ×3.52")
	_c.near(GameBalance.enemy_hp_mult(20), pow(1.15, 19), EPS, "第 20 波血量复利 ×14.23")
	_c.near(GameBalance.enemy_dmg_mult(10), pow(1.06, 9), EPS, "第 10 波接触伤害复利 ×1.69")
	_c.near(GameBalance.wave_duration(1), 22.0, EPS, "第 1 波时长 22s")
	_c.near(GameBalance.wave_duration(20), 60.0, EPS, "第 20 波封顶 60s")
	_c.near(GameBalance.wave_duration(99), 60.0, EPS, "无尽波次也封顶 60s")
	_c.near(GameBalance.spawn_interval(1), 1.295, EPS, "第 1 波刷怪间隔 1.295s")
	_c.near(GameBalance.spawn_interval(40), GameBalance.SPAWN_INTERVAL_MIN, EPS, "刷怪间隔有下限")
	_c.near(GameBalance.enemy_hp_mult(0), GameBalance.enemy_hp_mult(1), EPS, "非法波次 0 被夹到 1")

# ---------------- Boss 波（固定关卡） ----------------

func _test_boss_waves() -> void:
	_c.check(GameBalance.is_boss_wave(10), "第 10 波是固定 Boss 关")
	_c.check(GameBalance.is_boss_wave(20), "第 20 波是固定 Boss 关（心魔劫）")
	_c.check(not GameBalance.is_boss_wave(5), "第 5 波仍是精英不是 Boss")
	_c.check(not GameBalance.is_boss_wave(15), "第 15 波仍是精英不是 Boss")
	_c.check(not GameBalance.is_boss_wave(9), "非 Boss 波次不错判")
	_c.check(GameBalance.is_boss_wave(30), "无尽 30 波再逢魔君")
	_c.check(not GameBalance.is_boss_wave(25), "无尽 25 波不是 Boss")

	# 10/20 波让位给魔君，精英退守 5/15 与无尽每 3 波
	_c.check(GameBalance.is_elite_wave(5), "第 5 波精英保留")
	_c.check(GameBalance.is_elite_wave(15), "第 15 波精英保留")
	_c.check(not GameBalance.is_elite_wave(10), "第 10 波不再刷精英（Boss 关）")
	_c.check(not GameBalance.is_elite_wave(20), "第 20 波不再刷精英（Boss 关）")
	_c.check(not GameBalance.is_elite_wave(21), "非无尽模式 21 波不是精英")
	_c.check(GameBalance.is_elite_wave(21, true), "无尽 21 波恢复每 3 波精英")
	_c.check(not GameBalance.is_elite_wave(30, true), "无尽 30 波是 Boss 不是精英")

	# Boss 血条厚度：与普通敌人同曲线，靠基础值拉开 ~5~7 倍精英的差距
	_c.near(GameBalance.boss_hp(10) / GameBalance.boss_hp(1), GameBalance.enemy_hp_mult(10), EPS, "Boss 血量与敌人同一条成长曲线")
	var golem_w10 := 1000.0 * GameBalance.enemy_hp_mult(10)
	_c.check(GameBalance.boss_hp(10) >= golem_w10 * 5.0 - EPS, "第 10 波 Boss 血量至少精英 5 倍 (%.0f vs %.0f)" % [GameBalance.boss_hp(10), golem_w10])
	_c.check(GameBalance.boss_hp(20) > GameBalance.boss_hp(10), "第 20 波魔尊血更厚")
	_c.check(GameBalance.boss_contact_damage(20) > GameBalance.boss_contact_damage(1), "Boss 接触伤害随波次成长")

# ---------------- 一轮刷几只 ----------------

func _test_spawn_shape() -> void:
	_c.equals(GameBalance.spawn_batch(1, 0.0), 2, "第 1 波 + 触发追加 → 2 只")
	_c.equals(GameBalance.spawn_batch(1, 0.9), 1, "第 1 波未触发追加 → 1 只")
	_c.equals(GameBalance.spawn_batch(8, 0.9), 3, "第 8 波 → 1+2=3 只")
	_c.equals(GameBalance.spawn_batch(8, 0.0), 4, "第 8 波追加 → 4 只")
	_c.equals(GameBalance.ELITE_STONE_BONUS, 25, "精英额外灵石 25")
	var count_at_cap := 0
	for i in range(200):
		count_at_cap += GameBalance.spawn_batch(20, 0.0)
	_c.check(count_at_cap > 200, "后期每轮必然多于 1 只")

# ---------------- 怪物配比：谁在第几波出现、占多少 ----------------

func _test_enemy_mix() -> void:
	# 用户口径 2026-10-08：「这个放火球的敌人怎么要到七八波才出来？不一开始就应该有吗」
	# 旧配比是「累计带 + 波次闸门」，闸门一开邪修直接吃掉整段（第 8 波突然 27%），
	# 而闸门未开时下一格白捡（第 5~7 波雷兽 42%）。现在火球怪第 1 波就在场内、按占比爬坡。
	_c.near(WaveSpawner.xiexiu_edge(1), 0.06, EPS, "邪修第 1 波占比 6%（一开始就有，但只是零星）")
	_c.near(WaveSpawner.xiexiu_edge(8), WaveSpawner.MIX_XIEXIU_EDGE, EPS, "邪修第 8 波爬到上沿 27%")
	_c.near(WaveSpawner.xiexiu_edge(20), WaveSpawner.MIX_XIEXIU_EDGE, EPS, "上沿封顶，后期不再无限涨")
	var prev := 0.0
	var monotonic := true
	for w in range(1, 21):
		var edge := WaveSpawner.xiexiu_edge(w)
		if edge < prev - EPS:
			monotonic = false
		prev = edge
	_c.check(monotonic, "邪修占比逐波不降（难度阶梯单调）")
	_c.equals(WaveSpawner.pick_scene_key(1, 0.03), "xiexiu", "第 1 波 roll 落在邪修带内 → 邪修")
	_c.equals(WaveSpawner.pick_scene_key(1, 0.06), "slime", "第 1 波邪修只占 6%，其余仍是史莱姆")
	_c.equals(WaveSpawner.pick_scene_key(1, 0.5), "slime", "第 1 波仍不刷花妖（维持第 2 波解锁）")
	_c.equals(WaveSpawner.pick_scene_key(3, 0.05), "danbao", "第 3 波丹爆傀儡已解锁，roll<0.12 → 丹爆傀儡")
	_c.equals(WaveSpawner.pick_scene_key(3, 0.20), "flower", "第 3 波邪修带被丹爆整段吃掉（[0.12,0.12) 为空），roll 0.20 落在花妖带")
	_c.equals(WaveSpawner.pick_scene_key(3, 0.70), "slime", "第 3 波高 roll 但未到蜂群带（0.70 < 0.78）仍是史莱姆")
	_c.equals(WaveSpawner.pick_scene_key(5, 0.15), "xiexiu", "第 5 波邪修带为 [0.12, 0.18)，roll 0.15 落邪修")
	_c.equals(WaveSpawner.pick_scene_key(5, 0.30), "leibeast", "第 5 波雷兽带为 [0.18, 0.42)")
	_c.equals(WaveSpawner.pick_scene_key(12, 0.05), "danbao", "第 12 波 roll<0.12 → 丹爆傀儡")
	_c.equals(WaveSpawner.pick_scene_key(12, 0.20), "xiexiu", "第 12 波 [0.12, 0.27) → 邪修")
	_c.equals(WaveSpawner.pick_scene_key(12, 0.35), "leibeast", "第 12 波 [0.27, 0.42) → 雷兽")
	var seen := {}
	for w in range(1, 25):
		for i in range(100):
			seen[WaveSpawner.pick_scene_key(w, float(i) / 100.0)] = true
	_c.equals(seen.keys().size(), 10, "十种怪在配比表里都真的会被选到（key 拼错=悄悄全刷史莱姆）")

	# 批三新敌种：高 roll 段从史莱姆的保底份额里切走，逐波解锁
	_c.equals(WaveSpawner.pick_scene_key(1, 0.80), "slime", "第 1 波高 roll 仍是史莱姆（新敌种未解锁）")
	_c.equals(WaveSpawner.pick_scene_key(3, 0.80), "fengqun", "第 3 波蜂群精解锁")
	_c.equals(WaveSpawner.pick_scene_key(6, 0.88), "xueyong", "第 6 波血蛹解锁（死亡分裂）")
	_c.equals(WaveSpawner.pick_scene_key(7, 0.93), "yingmei", "第 7 波影魅解锁（闪现侧翼）")
	_c.equals(WaveSpawner.pick_scene_key(9, 0.96), "guyao", "第 9 波鼓妖解锁（加速光环）")
	_c.equals(WaveSpawner.pick_scene_key(13, 0.99), "guyao", "蛛母未解锁时其份额落回鼓妖带（闸门让位）")
	_c.equals(WaveSpawner.pick_scene_key(14, 0.99), "zhumu", "第 14 波蛛母解锁（产卵孵化）")

# ---------------- 敌方火球：外观 == 判定范围 ----------------

func _test_enemy_bolt() -> void:
	# 用户口径 2026-10-08：「火球怎么这么大…不要这种透明/虚化的效果，攻击范围多大就显示多大」
	# 旧写法把 128px 的 light_radial 当 additive 外焰套在核心外面，糊开约 70~100px，
	# 而判定半径只有 8px ⇒ 看到的威胁是真实的 4~8 倍。判据钉三件事：
	# 判定半径只由 RADIUS × scale_factor 决定；碰撞与外观共用同一份 radius；不再长出辉光子节点。
	var bolt := EnemyBolt.new()
	_c.near(bolt.radius, EnemyBolt.RADIUS, EPS, "普通火球判定半径 = RADIUS 常数")
	bolt.scale_factor = GameBalance.BOSS_BOLT_SCALE
	add_child(bolt)
	_c.near(bolt.radius, EnemyBolt.RADIUS * GameBalance.BOSS_BOLT_SCALE, EPS, "Boss 环弹按 scale_factor 同步放大")
	var shape := bolt.get_child(0) as CollisionShape2D
	_c.check(shape != null and shape.shape is CircleShape2D, "火球第一个子节点是碰撞体")
	if shape != null and shape.shape is CircleShape2D:
		_c.near((shape.shape as CircleShape2D).radius, bolt.radius, EPS, "判定圆半径 == 画出来的圆半径（同一份 radius）")
	_c.equals(bolt.get_child_count(), 1, "火球没有外焰/尾迹辉光子节点（外观不会超出判定范围）")
	bolt.free()

# ---------------- 商店定价 ----------------

func _test_pricing() -> void:
	_c.equals(GameBalance.weapon_price(25, 1, 1.0), 25, "首波原价")
	_c.equals(GameBalance.weapon_price(25, 5, 1.0), 33, "第 5 波 +8")
	_c.equals(GameBalance.weapon_price(25, 5, 0.8), 26, "散修 8 折取整")
	_c.equals(GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, 5, 1.0), 15, "回气丹随波加价")
	_c.equals(GameBalance.reroll_cost(5, 0, 1.0), 7, "首次重掷 = 2+波次")
	_c.equals(GameBalance.reroll_cost(5, 2, 1.0), 11, "本波第 3 次重掷再 +4")
	_c.equals(GameBalance.reroll_cost(5, 1, 1.0), 9, "第 2 次重掷 = 2+5+2")
	_c.equals(GameBalance.reroll_cost(5, 1, 0.8), 7, "重掷价也吃折扣（9×0.8 取整）")

	# GameManager 必须真的用这条公式，而不是自己再写一遍
	GameManager.reset_run()
	GameManager.wave_number = 3
	GameManager.reroll_count = 1
	GameManager.shop_price_mult = 1.0
	GameManager.roll_shop(false)
	_c.equals(GameManager.reroll_cost, GameBalance.reroll_cost(3, 1, 1.0), "roll_shop 的重掷价与公式一致")

	# 流派偏好软加权（替代旧版硬过滤）
	_c.near(GameBalance.tag_filter_mult(["sword"], []), 1.0, EPS, "无过滤时恒为 1（不改变权重）")
	_c.near(GameBalance.tag_filter_mult(["sword"], ["sword"]), GameBalance.TAG_FILTER_BONUS, EPS, "命中限定 tag → BONUS 倍率")
	_c.near(GameBalance.tag_filter_mult(["spirit"], ["sword"]), GameBalance.TAG_FILTER_LEAK, EPS, "未命中 → LEAK 漏出权重")
	_c.near(GameBalance.tag_filter_mult(["sword", "spirit"], ["sword"]), GameBalance.TAG_FILTER_BONUS, EPS, "多 tag 命中其一即 BONUS")

# ---------------- 灵韵复利 ----------------

func _test_harvest() -> void:
	_c.equals(GameBalance.harvest_gain(7.6), 8, "灵韵发放四舍五入")
	_c.equals(GameBalance.harvest_gain(0.4), 0, "不足 0.5 不发")
	_c.near(GameBalance.harvest_next(100.0, 5, 16), 105.0, EPS, "截止波前复利 ×1.05")
	_c.near(GameBalance.harvest_next(100.0, 16, 16), 100.0, EPS, "到截止波停止增长")
	_c.near(GameBalance.harvest_next(100.0, 40, 16), 100.0, EPS, "无尽也不暴涨")
	var h := 100.0
	for w in range(1, 16):
		h = GameBalance.harvest_next(h, w, 16)
	_c.near(h, 100.0 * pow(1.05, 15), 0.01, "15 次复利累计正确")

# ---------------- 稀有度权重 ----------------

func _test_rarity_weights() -> void:
	var base: Dictionary = GameBalance.rarity_weights(0.0)
	_c.near(base["epic"], 10.0, EPS, "无福缘时仙品权重 10")
	_c.near(base["common"], 60.0, EPS, "无福缘时凡品权重 60")
	_c.near(base["rare"], 30.0, EPS, "良品权重恒为 30")
	var lucky: Dictionary = GameBalance.rarity_weights(20.0)
	_c.near(lucky["epic"], 30.0, EPS, "20 点福缘把仙品抬到 30")
	_c.near(lucky["common"], 40.0, EPS, "差额从凡品扣")
	_c.near(float(lucky["common"]) + float(lucky["rare"]) + float(lucky["epic"]), 100.0, EPS, "三档之和仍是 100")
	var maxed: Dictionary = GameBalance.rarity_weights(999.0)
	_c.near(maxed["common"], GameBalance.RARITY_COMMON_FLOOR, EPS, "凡品有权重地板不会归零")
	_c.near(GameBalance.rarity_weights(-5.0)["epic"], 10.0, EPS, "负福缘不会倒扣仙品")

# ---------------- 权重抽奖 ----------------

func _test_weighted_pick() -> void:
	_c.equals(GameBalance.weighted_pick_index([1.0, 1.0], 0.25), 0, "前半段命中第 0 项")
	_c.equals(GameBalance.weighted_pick_index([1.0, 1.0], 0.75), 1, "后半段命中第 1 项")
	_c.equals(GameBalance.weighted_pick_index([0.0, 1.0], 0.0), 1, "零权重项不会被选中")
	_c.equals(GameBalance.weighted_pick_index([], 0.5), 0, "空表安全返回 0")
	_c.equals(GameBalance.weighted_pick_index([0.0, 0.0], 0.5), 0, "全零权重不除零")
	_c.equals(GameBalance.weighted_pick_index([1.0], 1.0), 0, "roll=1 边界仍落在最后一项")

	# 倍率与概率：亲和 ×2.5 应显著抬高被选中频率
	var hits := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	for i in range(2000):
		if GameBalance.weighted_pick_index([2.5, 1.0], rng.randf()) == 0:
			hits += 1
	_c.check(hits > 1200 and hits < 1800, "2.5 倍权重的命中率约 71%%（实测 %.1f%%）" % [float(hits) / 20.0])

# ---------------- 羁绊档位 ----------------

func _test_synergy_levels() -> void:
	var th: Array = [2, 4, 6]
	_c.equals(GameBalance.synergy_level(1, th), 0, "1 件未激活")
	_c.equals(GameBalance.synergy_level(2, th), 1, "2 件一档")
	_c.equals(GameBalance.synergy_level(3, th), 1, "3 件仍是一档")
	_c.equals(GameBalance.synergy_level(4, th), 2, "4 件二档")
	_c.equals(GameBalance.synergy_level(6, th), 3, "6 件满档")
	_c.equals(GameBalance.synergy_level(99, th), 3, "超过满档不会溢出")
	_c.equals(GameBalance.synergy_level(1, th, 1), 1, "门槛下移 1 后 1 件即激活")
	_c.equals(GameBalance.synergy_level(5, th, 1), 3, "门槛下移 1 后 5 件满档")
	_c.equals(GameBalance.synergy_level(0, th, 99), 0, "门槛再低也要至少 1 件")
	_c.equals(GameBalance.synergy_level(3, []), 0, "空阈值表安全")

	# 与 GameManager 的结算保持同一把尺子：两只灵蝶 → 御灵一档
	GameManager.reset_run()
	GameManager.drones = [1, 1]
	GameManager.recalc_synergies()
	_c.check(GameManager.active_synergies.has("spirit"), "御灵羁绊已进入结算表")
	_c.equals(int(GameManager.active_synergies["spirit"]["level"]), 1, "2 只灵蝶 = 御灵一档")
	_c.near(GameManager.synergy_max_hp_bonus, 15.0, EPS, "御灵一档 +15 气血上限")
	GameManager.spirit_threshold_adj = 1
	GameManager.recalc_synergies()
	_c.equals(int(GameManager.active_synergies["spirit"]["level"]), 1, "门槛下移后 2 只仍是一档")
	GameManager.reset_run()

# ---------------- 加点表 ----------------

func _test_upgrade_table() -> void:
	var fields: Array = GameBalance.upgrade_fields()
	var unknown: Array = []
	var missing: Array = []
	for u in UpgradeData.UPGRADES:
		var apply: Dictionary = u.get("apply", {})
		if apply.is_empty():
			missing.append(u.get("id", "?"))
		for key in apply.keys():
			if not (key in fields):
				unknown.append("%s.%s" % [u.get("id", "?"), key])
	_c.check(missing.is_empty(), "每个升级项都带 apply 幅度表（缺: %s）" % str(missing))
	_c.check(unknown.is_empty(), "apply 字段名都在白名单内（非法: %s）" % str(unknown))

	# 逐项落地：加点确实改到了对应属性，且幅度就是表里的数
	var deltas := {
		"atk_up": 0.15, "armor_up": 2.0, "speed_up": 0.08, "pickup_up": 0.4,
		"regen_up": 1.2, "critdmg_up": 0.25, "lifesteal_up": 0.04, "luck_up": 6.0,
		"harvest_up": 8.0, "range_up": 0.12,
	}
	var targets := {
		"atk_up": "weapon_damage_mult", "armor_up": "armor", "speed_up": "move_speed_mult",
		"pickup_up": "pickup_range_mult", "regen_up": "hp_regen", "critdmg_up": "crit_mult",
		"lifesteal_up": "lifesteal", "luck_up": "luck", "harvest_up": "harvest",
		"range_up": "attack_range_mult",
	}
	for uid in deltas.keys():
		GameManager.reset_run()
		var before: float = float(GameManager.get(targets[uid]))
		GameManager.apply_upgrade(uid)
		_c.near(float(GameManager.get(targets[uid])) - before, deltas[uid], EPS, "%s 幅度与表一致" % uid)

	# 特殊项：会心/流云有上限，法诀有地板，灵石补给直接发钱
	GameManager.reset_run()
	for i in range(30):
		GameManager.apply_upgrade("crit_up")
	_c.near(GameManager.get_crit_rate(), GameManager.CRIT_RATE_CAP, EPS, "暴击率叠满后卡在软上限")
	GameManager.reset_run()
	for i in range(30):
		GameManager.apply_upgrade("dodge_up")
	_c.near(GameManager.get_effective_dodge(), GameManager.DODGE_CAP, EPS, "身法叠满后卡在硬上限")
	GameManager.reset_run()
	for i in range(40):
		GameManager.apply_upgrade("haste_up")
	_c.near(GameManager.attack_speed_mult, GameManager.ATTACK_SPEED_FLOOR, EPS, "施法间隔不会低于地板")
	GameManager.reset_run()
	var stones := GameManager.spirit_stones
	GameManager.apply_upgrade("coins_up")
	_c.equals(GameManager.spirit_stones - stones, int(UpgradeData.get_upgrade_def("coins_up").get("apply", {})["spirit_stones"]), "灵石补给按表发钱")
	GameManager.reset_run()

	# 历史记录：同一项叠加两次要记下 count=2，供 max_stacks 过滤使用
	GameManager.apply_upgrade("atk_up")
	GameManager.apply_upgrade("atk_up")
	_c.equals(int(GameManager.upgrade_counts.get("atk_up", 0)), 2, "领悟次数被统计")
	_c.equals(GameManager.upgrade_history.size(), 2, "本局悟道记录有条目")
	_c.check(GameManager.upgrade_history[0].has("rarity_label"), "记录里带稀有度文案")

# ---------------- 悟道候选的过滤与确定性 ----------------

func _test_upgrade_roll_filters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var ctx := {"luck": 0.0, "locked_upgrades": [], "counts": {}, "rng": rng}
	var picks := UpgradeData.get_random_upgrades(3, ctx)
	_c.equals(picks.size(), 3, "默认池足够时抽满 3 项")
	var ids: Array = []
	for p in picks:
		ids.append(p.get("id", ""))
	var seen := {}
	for id in ids:
		seen[id] = true
	_c.equals(seen.size(), 3, "同屏候选无重复")
	_c.check(picks[0].has("border_color"), "抽到的项带稀有度边框色")

	# 同种子必须同结果（这条断言依赖 rng 注入，是以前做不到的一件事）
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4242
	var picks2 := UpgradeData.get_random_upgrades(3, {"rng": rng2})
	var ids2: Array = []
	for p in picks2:
		ids2.append(p.get("id", ""))
	_c.equals(ids2, ids, "同种子 → 同结果（可确定性回归）")

	# 锁死项与叠满项都不该出现
	var all_ids: Array = []
	for u in UpgradeData.UPGRADES:
		all_ids.append(u.get("id", ""))
	var locked := UpgradeData.get_random_upgrades(3, {"locked_upgrades": all_ids})
	_c.equals(locked.size(), 0, "全部锁死时抽不出任何项")
	var maxed_counts := {}
	for u in UpgradeData.UPGRADES:
		maxed_counts[u.get("id", "")] = int(u.get("max_stacks", 99))
	_c.equals(UpgradeData.get_random_upgrades(3, {"counts": maxed_counts}).size(), 0, "全部叠满时抽不出任何项")
	var one_left := {}
	for u in UpgradeData.UPGRADES:
		one_left[u.get("id", "")] = int(u.get("max_stacks", 99))
	one_left["atk_up"] = 0
	var rest := UpgradeData.get_random_upgrades(3, {"counts": one_left})
	_c.equals(rest.size(), 1, "只剩 1 项可选时不硬凑 3 项")
	_c.equals(rest[0].get("id", ""), "atk_up", "剩下的正是未叠满那项")

	# 福缘把仙品概率抬上去：固定样本量下仙品数量应随福缘增加
	var epic_low := _count_epic(0.0)
	var epic_high := _count_epic(40.0)
	_c.check(epic_high >= epic_low, "福缘 40 的仙品数量不少于福缘 0（%d → %d）" % [epic_low, epic_high])

func _count_epic(luck: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := 0
	for i in range(400):
		for p in UpgradeData.get_random_upgrades(1, {"luck": luck, "rng": rng}):
			if p.get("rarity", "") == "epic":
				n += 1
	return n

# ---------------- 波后悟道结算：攒点 / 5 候选 / 刷新 ----------------

## 战斗中的升级从此只攒点数，回合结束一次性加完（2026-10-09 用户指令）。
## 这条断言钉三件事：点数与等级一一对应、候选数是 5、刷新的免费额度与价格线同货架一个口径。
func _test_alloc_session() -> void:
	GameManager.reset_run()
	GameManager.wave_number = 4
	GameManager.rng.seed = 20261009
	var finished_calls := 0
	if not GameManager.alloc_finished.is_connected(_on_alloc_finished_probe):
		GameManager.alloc_finished.connect(_on_alloc_finished_probe)
	_alloc_probe_count = 0

	# 升级只记账，不当场结算
	GameManager.add_experience(GameBalance.EXP_FIRST_LEVEL)
	_c.equals(GameManager.level, 2, "喂满初始修为升到 2 级")
	_c.equals(GameManager.pending_upgrade_points, 1, "升 1 级攒 1 点待加点")
	GameManager.add_experience(GameBalance.exp_to_next(GameBalance.EXP_FIRST_LEVEL))
	_c.equals(GameManager.level, 3, "再喂满一级升到 3 级")
	_c.equals(GameManager.pending_upgrade_points, 2, "升几级攒几点（现在 2 点）")
	_c.check(GameManager.has_pending_upgrades(), "has_pending_upgrades 认这 2 点")

	# 候选数量：默认 5，且不重复
	var five := GameManager.roll_upgrades()
	_c.equals(five.size(), GameManager.UPGRADE_OFFER_COUNT, "默认一次给 %d 个候选" % GameManager.UPGRADE_OFFER_COUNT)
	var ids := {}
	for p in five:
		ids[p.get("id", "")] = true
	_c.equals(ids.size(), five.size(), "同一屏候选不重复")

	# 开局会话：额度、报价与点数总额
	GameManager.open_alloc_session()
	_c.equals(GameManager.alloc_points_total, 2, "面板记住本次结算共 2 点")
	_c.equals(GameManager.alloc_offers.size(), GameManager.UPGRADE_OFFER_COUNT, "面板一屏 %d 张卡" % GameManager.UPGRADE_OFFER_COUNT)
	_c.equals(GameManager.alloc_reroll_free_left, GameManager.ALLOC_FREE_REROLLS, "每回合 %d 次免费刷新" % GameManager.ALLOC_FREE_REROLLS)
	_c.equals(GameManager.alloc_reroll_cost, GameBalance.reroll_cost(4, 0, 1.0), "悟道报价与货架重掷同一公式（第 1 次价）")

	# 加 1 点：属性落地 + 点数 -1 + 换一屏新候选
	var lvl_recs := GameManager.upgrade_history.size()
	var picked_id: String = String(GameManager.alloc_offers[0].get("id", ""))
	_c.check(GameManager.take_alloc_upgrade(0), "确认领悟第 1 张卡")
	_c.equals(GameManager.upgrade_history.size(), lvl_recs + 1, "悟道记录 +1")
	_c.equals(int(GameManager.upgrade_counts.get(picked_id, 0)), 1, "该条层数 +1")
	_c.equals(GameManager.pending_upgrade_points, 1, "还剩 1 点")
	_c.equals(GameManager.alloc_offers.size(), GameManager.UPGRADE_OFFER_COUNT, "剩点还在 → 换一屏新候选")
	_c.equals(_alloc_probe_count, 0, "没加完不发 alloc_finished（商店不许提前开）")

	# 越界与空池护栏
	_c.check(not GameManager.take_alloc_upgrade(99), "越界下标不加点了")

	# 刷新：先吃免费，再扣灵石，报价跟着上涨
	var stones := GameManager.spirit_stones
	_c.check(GameManager.reroll_alloc(), "免费刷新一次")
	_c.equals(GameManager.spirit_stones, stones, "免费刷新不扣灵石")
	_c.equals(GameManager.alloc_reroll_free_left, 0, "免费额度用光")
	_c.check(GameManager.can_reroll_alloc(), "灵石够就能继续刷")
	var price1 := GameManager.alloc_reroll_cost
	_c.check(GameManager.reroll_alloc(), "第二次刷新付灵石")
	_c.equals(GameManager.spirit_stones, stones - price1, "按报价扣灵石（-%d）" % price1)
	_c.equals(GameManager.alloc_reroll_cost, GameBalance.reroll_cost(4, 1, 1.0), "再刷一档涨价（与货架同曲线）")

	# 加完最后 1 点：发 alloc_finished、清空候选
	_c.check(GameManager.take_alloc_upgrade(0), "确认领悟最后 1 点")
	_c.equals(GameManager.pending_upgrade_points, 0, "点数清零")
	_c.check(not GameManager.has_pending_upgrades(), "has_pending_upgrades 归零")
	_c.equals(_alloc_probe_count, 1, "加完点发一次 alloc_finished")
	_c.check(GameManager.alloc_offers.is_empty(), "结算结束后不留候选")
	_c.check(not GameManager.reroll_alloc(), "没点数时刷新被拒（不许白扣灵石）")

	# 没有点数时：会话直接不开
	GameManager.open_alloc_session()
	_c.equals(_alloc_probe_count, 1, "零点数时 open_alloc_session 不重开结算")

	# 池子抽空（全部叠满）不许把玩家扣在这一屏：点数作废、商店照常开
	GameManager.reset_run()
	GameManager.pending_upgrade_points = 2
	for u in UpgradeData.UPGRADES:
		GameManager.upgrade_counts[u.get("id", "")] = int(u.get("max_stacks", 99))
	_alloc_probe_count = 0
	GameManager.open_alloc_session()
	_c.equals(GameManager.pending_upgrade_points, 0, "悟道池抽空时点数作废（不锁屏）")
	_c.check(GameManager.alloc_offers.is_empty(), "池抽空时不留空一屏候选")
	_c.equals(_alloc_probe_count, 1, "池抽空也发 alloc_finished（灵石阁照常开）")

	# reset_run 把这条线也清干净
	GameManager.pending_upgrade_points = 3
	GameManager.reset_run()
	_c.equals(GameManager.pending_upgrade_points, 0, "reset_run 清待加点")
	_c.equals(GameManager.alloc_reroll_count, 0, "reset_run 清悟道刷新次数")
	_c.equals(GameManager.alloc_reroll_free_left, 0, "reset_run 清悟道免费额度")
	_c.check(GameManager.alloc_offers.is_empty(), "reset_run 清悟道候选")
	if GameManager.alloc_finished.is_connected(_on_alloc_finished_probe):
		GameManager.alloc_finished.disconnect(_on_alloc_finished_probe)

var _alloc_probe_count: int = 0

func _on_alloc_finished_probe() -> void:
	_alloc_probe_count += 1

# ---------------- 商店：确定性 + 主流派保底 ----------------

func _test_shop_determinism() -> void:
	GameManager.reset_run()
	GameManager.wave_number = 6
	GameManager.rng.seed = 1234567
	GameManager.roll_shop(true)
	var first: Array = GameManager.shop_offers.duplicate(true)
	_c.equals(GameManager.shop_offers.size(), GameManager.SHOP_BASE_SLOTS, "货架固定 %d 个位" % GameManager.SHOP_BASE_SLOTS)
	for offer in first:
		_c.check(offer.get("kind", "") in ["weapon", "potion", "item"], "货架项类型合法：%s" % str(offer.get("kind", "")))
		_c.check(int(offer.get("price", 0)) > 0, "货架项价格大于 0：%s" % str(offer.get("id", "")))

	# 价格必须等于公式值，不能有第二套算法
	for offer in first:
		match String(offer.get("kind", "")):
			"weapon":
				var base := int(WeaponData.get_def(offer["id"]).get("price", 20))
				_c.equals(int(offer["price"]), GameBalance.weapon_price(base, 6, GameManager.shop_price_mult), "法器价与 GameBalance 一致（%s）" % offer["id"])
			"item":
				var ibase := int(ItemData.get_def(offer["id"]).get("price", 20))
				_c.equals(int(offer["price"]), GameBalance.item_price(ibase, 6, GameManager.shop_price_mult), "法宝价与 GameBalance 一致（%s）" % offer["id"])
			_:
				_c.equals(int(offer["price"]), GameBalance.potion_price(WeaponData.POTION_BASE_PRICE, 6, GameManager.shop_price_mult), "回气丹价与 GameBalance 一致")

	GameManager.rng.seed = 1234567
	GameManager.roll_shop(true)
	_c.equals(str(GameManager.shop_offers), str(first), "同种子 → 同一副货架")

func _test_main_tag_pity() -> void:
	GameManager.reset_run()
	GameManager.drones = [1, 1]        # 御灵 2 件 → 主流派 = spirit
	GameManager.wave_number = 5
	# 手动构造无 spirit 的货架，直接驱动保底计数器，不再依赖旧版硬过滤
	GameManager.shop_offers = _make_all_non_spirit_offers(5)
	GameManager._no_main_tag_waves = 0
	GameManager._apply_main_tag_pity(5)
	_c.check(not _shelf_has_spirit(), "第 1 波无 spirit → 保底未触发（计数 1/2）")
	GameManager._apply_main_tag_pity(5)   # 计数 2/2 → 触发
	_c.check(_shelf_has_spirit(), "连续 2 波后保底强制塞入一件御灵法器")
	GameManager.reset_run()

func _make_all_non_spirit_offers(wave: int) -> Array:
	# 4 个全为青云剑（tags=["sword"]，不含 spirit）的货架，用于保底测试的确定输入
	var w_id := "qingyun_sword"
	var base := int(WeaponData.get_def(w_id).get("price", 20))
	var offers: Array = []
	for i in range(4):
		offers.append({
			"kind": "weapon", "id": w_id,
			"price": GameBalance.weapon_price(base, wave, GameManager.shop_price_mult),
			"sold": false, "locked": false,
		})
	return offers

func _shelf_has_spirit() -> bool:
	for offer in GameManager.shop_offers:
		if offer.get("kind", "") == "weapon" and "spirit" in WeaponData.tags_of(offer.get("id", "")):
			return true
	return false

## 剑痴（shop_tag_filter=["sword"]）软加权：旧版硬过滤会让货架坍缩成全是青云剑，
## 改为软加权后必定能在多次刷新中见到非剑系法器。
func _test_shop_tag_soft_bias() -> void:
	GameManager.reset_run()
	GameManager.shop_tag_filter = ["sword"]   # 剑痴流派偏好
	GameManager.wave_number = 1
	GameManager.rng.seed = 99991
	var saw_non_sword := false
	for i in range(30):
		GameManager.roll_shop(true)
		for offer in GameManager.shop_offers:
			if offer.get("kind", "") == "weapon":
				if not ("sword" in WeaponData.tags_of(offer.get("id", ""))):
					saw_non_sword = true
					break
		if saw_non_sword:
			break
	_c.check(saw_non_sword, "剑痴软加权下 30 次刷新内必出现非剑系法器（不再全是青云剑）")
	GameManager.reset_run()

# ---------------- 多武器智能多向索敌分配 ----------------

func _test_weapon_targeting() -> void:
	# 1. 空输入与无敌人
	var empty_res := GameBalance.assign_weapon_targets([], [])
	_c.equals(empty_res.size(), 0, "空武器表返回空数组")

	var w4 := [
		{"base_angle": 0.0, "range": 150.0, "prev_id": 0},
		{"base_angle": PI * 0.5, "range": 150.0, "prev_id": 0},
		{"base_angle": PI, "range": 150.0, "prev_id": 0},
		{"base_angle": -PI * 0.5, "range": 150.0, "prev_id": 0},
	]
	_c.equals(GameBalance.assign_weapon_targets(w4, []), [-1, -1, -1, -1], "无敌人时全部无目标")

	# 2. 单一敌人：射程内全部集火，超射程不打
	var single_enemy := [{"id": 101, "dist": 120.0, "angle": 0.0}]
	_c.equals(GameBalance.assign_weapon_targets(w4, single_enemy), [0, 0, 0, 0], "单一敌人时 4 把剑全部集火")

	var mixed_range := [
		{"base_angle": 0.0, "range": 100.0, "prev_id": 0},
		{"base_angle": PI, "range": 200.0, "prev_id": 0},
	]
	_c.equals(GameBalance.assign_weapon_targets(mixed_range, single_enemy), [-1, 0], "超出单把武器射程的不强行锁定")

	# 3. 四面来敌：4 把剑按各自槽位扇区一对一迎战 4 个方向的敌人
	var four_dirs := [
		{"id": 1, "dist": 110.0, "angle": 0.0},       # 右 (东)
		{"id": 2, "dist": 115.0, "angle": PI * 0.5},  # 下 (南)
		{"id": 3, "dist": 120.0, "angle": PI},        # 左 (西)
		{"id": 4, "dist": 125.0, "angle": -PI * 0.5}, # 上 (北)
	]
	var assigned4 := GameBalance.assign_weapon_targets(w4, four_dirs)
	_c.equals(assigned4, [0, 1, 2, 3], "四面受敌时 4 把剑按各自方位一对一分流迎击")

	# 4. 武器多于敌人（3 把剑 vs 2 个反方向敌人）：绝不漏掉任一方向敌人（防 Overkill 扎堆）
	var w3 := [
		{"base_angle": 0.0, "range": 150.0, "prev_id": 0},
		{"base_angle": 2.0 * PI / 3.0, "range": 150.0, "prev_id": 0},
		{"base_angle": -2.0 * PI / 3.0, "range": 150.0, "prev_id": 0},
	]
	var two_dirs := [
		{"id": 10, "dist": 95.0, "angle": 0.0},
		{"id": 20, "dist": 130.0, "angle": PI},
	]
	var assigned3 := GameBalance.assign_weapon_targets(w3, two_dirs)
	_c.check(0 in assigned3 and 1 in assigned3, "3 剑对 2 敌时两侧敌人均被覆盖（实际: %s）" % str(assigned3))

	# 5. 贴身危急敌人优先解围：40px 贴脸敌人必定优先获得防守
	var danger_case := [
		{"id": 99, "dist": 40.0, "angle": PI},
		{"id": 88, "dist": 110.0, "angle": 0.0},
	]
	var w_single := [{"base_angle": 0.0, "range": 150.0, "prev_id": 0}]
	_c.equals(GameBalance.assign_weapon_targets(w_single, danger_case), [0], "即使在背后，贴身危急敌人也优先保命迎击")

	# 6. 目标粘滞性：距离与角度相近的两个敌人，保持原锁定目标不来回抽搐
	var close_pair := [
		{"id": 501, "dist": 110.0, "angle": 0.05},
		{"id": 502, "dist": 108.0, "angle": -0.05},
	]
	var sticky_w := [{"base_angle": 0.0, "range": 150.0, "prev_id": 501}]
	_c.equals(GameBalance.assign_weapon_targets(sticky_w, close_pair), [0], "粘滞保护：已锁定目标微弱劣势时不跳变")

# ---------------- 音频接线完整性 ----------------
## 这一组断言专门挡三类「听起来正常其实哑了」的事故：
##   注册了 key 但素材没进包 / 没被导入（本项目踩过：新烘的 wav 未跑 editor import）
##   调用点写了文件名当 key（曾经的 play_sfx("powerUp2") 一直静默无效）
##   总线布局没加载（音量设置就会对着不存在的总线空转）

func _test_audio_wiring() -> void:
	var missing: Array = AudioManager.missing_paths()
	_c.check(missing.is_empty(), "注册表里的音效文件全部就位（缺: %s）" % str(missing))

	var needed := [
		"blade_shoot", "enemy_hit", "orb_hit", "gem_pickup", "level_up", "obelisk_blessing",
		"enemy_death", "enemy_death_elite", "sword_swing", "talisman_throw", "thunder_strike",
		"fan_gust", "shop_buy", "shop_reroll", "shop_lock", "sell", "equip", "unequip",
		"merge_success", "ui_click", "ui_back", "ui_error", "wave_start", "wave_clear",
		"boss_raid", "dodge", "heal", "victory", "defeat",
	]
	var silent: Array = []
	for k in needed:
		if not AudioManager.has_sfx(k):
			silent.append(k)
	_c.check(silent.is_empty(), "游戏会用到的 %d 个音效 key 都能播（哑的: %s）" % [needed.size(), str(silent)])

	# 数据表里配的 sfx 必须是已注册 key，否则 WeaponData 改了名而 AudioManager 没跟上
	var bad_table: Array = []
	for w_id in WeaponData.SHOP_POOL:
		var k: String = WeaponData.sfx_for(w_id)
		if not AudioManager.has_sfx(k):
			bad_table.append("%s→%s" % [w_id, k])
	_c.check(bad_table.is_empty(), "每件法器的开火音都注册过（异常: %s）" % str(bad_table))
	_c.equals(WeaponData.sfx_for("qingyun_sword"), "sword_swing", "青云剑开火音按流派走")
	_c.equals(WeaponData.sfx_for("不存在的法器"), "blade_shoot", "未知 id 回落到通用开火音")

	for bus in ["Master", "BGM", "SFX", "Voice"]:
		_c.check(AudioServer.get_bus_index(StringName(bus)) >= 0, "总线 %s 存在" % bus)

	# 音量读写往返 + 落盘（测完还原成原值，不弄脏用户的设置）
	var before := AudioManager.get_bus_linear(&"SFX")
	AudioManager.set_bus_linear(&"SFX", 0.5)
	_c.near(AudioManager.get_bus_linear(&"SFX"), 0.5, 0.01, "SFX 音量设 50% 后读回一致")
	AudioManager.set_bus_linear(&"SFX", 0.0)
	_c.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "拉到 0 真静音（不留 -inf 残响）")
	AudioManager.set_bus_linear(&"SFX", before)
	_c.near(AudioManager.get_bus_linear(&"SFX"), before, 0.01, "音量已还原为 %.2f" % before)

	# BGM 状态机：素材齐备 + 真能切换 + 未知 key 不打断当前播放
	for key in AudioManager.BGM_TABLE.keys():
		var path: String = AudioManager.BGM_TABLE[key].get("path", "")
		_c.check(ResourceLoader.exists(path), "BGM 素材就位：%s (%s)" % [key, path.get_file()])
	AudioManager.play_bgm_key("battle")
	_c.equals(String(AudioManager.bgm_key), "battle", "battle 在播")
	AudioManager.play_bgm_key("shop")
	_c.equals(String(AudioManager.bgm_key), "shop", "商店阶段切到 shop")
	AudioManager.play_bgm_key("shop")
	_c.equals(String(AudioManager.bgm_players[AudioManager.bgm_next].stream.resource_path),
		AudioManager.BGM_TABLE["shop"]["path"], "重复调同一 key 不会重头播")
	AudioManager.play_bgm_key("这个 key 不存在")
	_c.equals(String(AudioManager.bgm_key), "shop", "未知 BGM key 不影响当前播放")
	AudioManager.play_bgm_key("battle")

# ---------------- 游戏设置模块 ----------------

func _test_settings_manager() -> void:
	# 1. 保存当前用户状态以便测试后恢复
	var orig_master := SettingsManager.get_bus_volume(&"Master")
	var orig_master_mute := SettingsManager.is_bus_muted(&"Master")
	var orig_dmg_num := bool(SettingsManager.get_val(&"display", &"damage_numbers", true))
	var orig_shake := bool(SettingsManager.get_val(&"display", &"screen_shake", true))

	# 2. 音量与静音切换
	SettingsManager.set_bus_volume(&"Master", 0.65)
	_c.near(SettingsManager.get_bus_volume(&"Master"), 0.65, 0.01, "主音量设定 65% 读取一致")
	SettingsManager.set_bus_muted(&"Master", true)
	_c.check(SettingsManager.is_bus_muted(&"Master"), "主音量静音状态生效")
	_c.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "AudioServer Master 总线已同步静音")
	# 拖动音量大于 0 应自动解除静音
	SettingsManager.set_bus_volume(&"Master", 0.8)
	_c.check(not SettingsManager.is_bus_muted(&"Master"), "调高音量自动解除静音状态")

	# 3. 画面与战斗反馈开关读写
	SettingsManager.set_val(&"display", &"damage_numbers", false)
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", true)), false, "关闭伤害跳字配置生效")
	SettingsManager.set_val(&"display", &"screen_shake", false)
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", true)), false, "关闭屏幕震动配置生效")

	# 4. 恢复默认设置
	SettingsManager.reset_to_defaults()
	_c.near(SettingsManager.get_bus_volume(&"Master"), 1.0, 0.01, "重置默认后主音量恢复 100%")
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", false)), true, "重置默认后伤害跳字恢复开启")
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", false)), true, "重置默认后屏幕震动恢复开启")

	# 5. 还原测试前状态
	SettingsManager.set_bus_volume(&"Master", orig_master)
	SettingsManager.set_bus_muted(&"Master", orig_master_mute)
	SettingsManager.set_val(&"display", &"damage_numbers", orig_dmg_num)
	SettingsManager.set_val(&"display", &"screen_shake", orig_shake)

# ---------------- 震屏：创伤预算与强度档位 ----------------

## 判据的由来：镜头曾经整局在摇（普通命中与小怪死亡每次都发创伤，累加起来永远归不了零）。
## 修完之后靠两条钉住：① 创伤只发给"值得看的节点"（口径写在 GameBalance 段注释里）；
## ② 就算将来有人再拿高频事件乱发，每秒预算也把最坏震幅钉在轻颤级别。
func _test_screen_shake_budget() -> void:
	# 1. 纯函数层：预算夹制
	_c.near(GameBalance.trauma_grant(0.09, 0.75), 0.09, EPS, "预算充足时全额发放")
	_c.near(GameBalance.trauma_grant(0.90, 0.75), 0.75, EPS, "单笔被剩余预算夹住")
	_c.near(GameBalance.trauma_grant(0.30, 0.0), 0.0, EPS, "预算耗尽则一分不给")
	_c.near(GameBalance.trauma_grant(-0.2, 0.5), 0.0, EPS, "负数请求按 0 处理")
	_c.near(GameBalance.shake_amount(0.5), 0.25, EPS, "创伤 0.5 → 震幅 0.25（平方关系）")
	_c.near(GameBalance.shake_amount(0.2), 0.04, EPS, "创伤 0.2 → 震幅 0.04（小击只轻颤）")
	_c.near(GameBalance.shake_amount(1.4), 1.0, EPS, "创伤越界夹到 1.0")
	_c.near(GameBalance.shake_duration(0.7), 0.7 / GameBalance.TRAUMA_DECAY, EPS, "震停时长 = 创伤 / 衰减速率")

	# 2. 尸潮模拟：每秒 20 次「小怪死亡」级别的 0.09，一秒内最多只能叠到预算
	var left := GameBalance.TRAUMA_BUDGET
	var got := 0.0
	for i in range(20):
		var grant := GameBalance.trauma_grant(0.09, left)
		left -= grant
		got += grant
	_c.near(got, GameBalance.TRAUMA_BUDGET, 0.001, "高频击杀被夹到每秒 0.75 上限")
	_c.near(left, 0.0, 0.001, "一秒的预算已被刷光")

	# 3. 真相机：连打 3 秒（60 次/秒）也只能停在稳态轻颤，且停手后必定向零
	var orig_level := SettingsManager.shake_level()
	SettingsManager.set_val(&"display", &"shake_intensity", &"standard")
	var cam := SmoothCamera.new()
	add_child(cam)
	for i in range(180):
		cam.add_trauma(0.09)
		cam._physics_process(1.0 / 60.0)
	var steady := GameBalance.trauma_steady_state()
	_c.check(cam.trauma <= steady + 0.05, "刷满 3 秒创伤仍不超过稳态值 %.2f" % steady)
	_c.check(cam.offset.length() <= 1.6, "最坏稳态位移不超过 ±1.6px（不再整局猛摇）")
	for i in range(40):
		cam._physics_process(1.0 / 60.0)
	_c.near(cam.trauma, 0.0, EPS, "停手 0.66 秒后创伤归零")
	_c.near(cam.offset.length(), 0.0, EPS, "归零后相机不再偏移")
	# 预算按秒回血：过了窗口就又是满的
	for i in range(70):
		cam._physics_process(1.0 / 60.0)
	_c.near(cam.trauma_budget_left(), GameBalance.TRAUMA_BUDGET, EPS, "一秒窗口过后预算回满")
	cam.queue_free()

	# 4. 档位：关闭 / 轻 / 标准 / 强，且与历史布尔总开关同源
	SettingsManager.set_val(&"display", &"shake_intensity", &"off")
	_c.near(SettingsManager.shake_mult(), 0.0, EPS, "档位「关闭」= 完全不震")
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", true)), false, "关闭档位同步带动旧总开关")
	SettingsManager.set_val(&"display", &"shake_intensity", &"heavy")
	_c.near(SettingsManager.shake_mult(), 1.7, EPS, "档位「强」= 1.7 倍幅度")
	_c.equals(SettingsManager.shake_level_label(), "强", "档位读数是人话不是系数")
	_c.equals(SettingsManager.shake_level_next(), &"off", "「强」再点一次回到关闭")
	SettingsManager.set_val(&"display", &"screen_shake", false)
	_c.equals(SettingsManager.shake_level(), &"off", "直接关总开关时档位跟着变关闭")
	SettingsManager.set_val(&"display", &"screen_shake", true)
	_c.equals(SettingsManager.shake_level(), &"standard", "重新开启时落回有手感的默认档")
	SettingsManager.set_val(&"display", &"shake_intensity", orig_level)

# ---------------- 五行武器矩阵与属性转化 ----------------

func _test_five_elements_system() -> void:
	# 1. 武器表完整性校验：20 把法器（5 五行 × 4 把）且图标资源齐全
	_c.equals(WeaponData.DEFS.size(), 20, "全武器库扩充至 20 把法器")
	_c.equals(WeaponData.SHOP_POOL.size(), 20, "商店池覆盖全部 20 把法器")
	var missing_icons: Array = []
	var missing_dual_tags: Array = []
	var no_bullet: Array = []        ## 弹丸类法器没配外观（会退回公共的 blade.png ⇒ 五把法器打出同一张火符）
	var bad_bullet: Array = []       ## 配了路径但文件不在
	var elem_counts: Dictionary = {"metal": 0, "wood": 0, "water": 0, "fire": 0, "earth": 0}
	for w_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(w_id)
		var icon_path: String = def.get("icon", "")
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			missing_icons.append(w_id)
		var bullet_path: String = String(def.get("bullet", ""))
		if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
			if bullet_path.is_empty():
				no_bullet.append(w_id)
			elif not ResourceLoader.exists(bullet_path):
				bad_bullet.append(w_id)
		var c_tag := WeaponData.class_of(w_id)
		var e_tag := WeaponData.element_of(w_id)
		if c_tag.is_empty() or e_tag.is_empty():
			missing_dual_tags.append(w_id)
		else:
			elem_counts[e_tag] = int(elem_counts.get(e_tag, 0)) + 1
	_c.check(missing_icons.is_empty(), "20 把法器的图标文件全部就位（缺: %s）" % str(missing_icons))
	_c.check(missing_dual_tags.is_empty(), "每把法器均具备「器类+五行」双标签（缺: %s）" % str(missing_dual_tags))
	_c.check(no_bullet.is_empty(), "每把弹丸法器都配了自己的弹丸外观（缺: %s）" % str(no_bullet))
	_c.check(bad_bullet.is_empty(), "弹丸外观文件全部存在（缺文件: %s）" % str(bad_bullet))
	for e_key in elem_counts.keys():
		_c.equals(int(elem_counts[e_key]), 4, "五行【%s】恰好包含 4 把法器" % e_key)

	# 2. 土豆兄弟式属性受益折算（GameBalance.weapon_stat_bonus 纯函数）
	var earth_scalings := {"armor": 3.5}
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 0.0}, 1), 0.0, EPS, "0 护甲时无额外属性加成")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 1), 35.0, EPS, "10 护甲在 ★1 番天印下转化 +35 基础伤")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 2), 43.75, EPS, "★2 属性转化系数 ×1.25 (+43.75)")
	_c.near(GameBalance.weapon_stat_bonus(earth_scalings, {"armor": 10.0}, 3), 52.5, EPS, "★3 属性转化系数 ×1.50 (+52.5)")

	var wood_scalings := {"hp_regen": 4.5}
	_c.near(GameBalance.weapon_stat_bonus(wood_scalings, {"hp_regen": 2.0}, 1), 9.0, EPS, "2.0 气血回复在青木藤鞭下转化 +9 基础伤")

	# 3. 五行羁绊与多品类环绕灵宝在 GameManager 中的结算
	GameManager.reset_run()
	GameManager.drones = [
		{"id": "hunyuan_zhong", "star": 1},
		{"id": "hunyuan_zhong", "star": 1}
	]
	GameManager.recalc_synergies()
	_c.check(GameManager.active_synergies.has("spirit") and GameManager.active_synergies.has("earth"), "上阵 2 尊混元古钟同时触发【御灵】与【厚土】双羁绊")
	_c.near(GameManager.synergy_armor, 3.0, EPS, "厚土一档提供 +3 护甲")
	_c.near(GameManager.synergy_knockback_mult, 1.25, EPS, "厚土一档提供 +25% 震退力")
	_c.near(GameManager.get_effective_armor(), 3.0, EPS, "有效护甲已计入厚土羁绊")
	GameManager.reset_run()

# ---------------- 批一新属性：悟性 / 震退 / 斩将 / 免费重掷 / 五行真解 ----------------

func _test_new_stat_fields() -> void:
	# 字段落地：apply 幅度确实写进对应属性
	GameManager.reset_run()
	GameManager._apply_stat_fields({"xp_gain_mult": 0.15, "knockback_mult": 0.35, "elite_damage": 0.25, "free_rerolls": 1.0}, "test")
	_c.near(GameManager.xp_gain_mult, 1.15, EPS, "悟性 +15% 落地")
	_c.near(GameManager.knockback_mult, 1.35, EPS, "震退 +35% 落地")
	_c.near(GameManager.elite_damage, 0.25, EPS, "斩将 +25% 落地")
	_c.equals(GameManager.free_rerolls, 1, "免费重掷 +1 落地")

	# 悟性：只放大修为，灵石按原价入账（不双重受益）
	GameManager.reset_run()
	GameManager.xp_gain_mult = 1.5
	GameManager.add_experience(4)   # 4×1.5=6，低于 10 的升级门槛，不触发升级扣减
	_c.equals(GameManager.experience, 6, "悟性 1.5x：4 点来源 → 6 点修为")
	_c.equals(GameManager.spirit_stones, 4, "灵石不受悟性放大")

	# 五行真解：全元素加成摊到五行，单元素只加一格
	GameManager.reset_run()
	GameManager._apply_stat_fields({"element_damage_all": 0.06}, "test")
	for e in WeaponData.ELEMENTS:
		_c.near(float(GameManager.element_damage.get(e, 0.0)), 0.06, EPS, "element_damage_all 摊到【%s】" % e)
	_c.near(GameManager.element_damage_mult("huoyan_fu"), 1.06, EPS, "火焰符吃到全元素 +6%")
	_c.near(GameManager.element_damage_mult("qingyun_sword"), 1.06, EPS, "青云剑（金）也吃到 +6%")
	GameManager._apply_stat_fields({"element_damage_fire": 0.12}, "test")
	_c.near(GameManager.element_damage_mult("huoyan_fu"), 1.18, EPS, "离火单系再 +12% → 合计 1.18")
	_c.near(GameManager.element_damage_mult("qingyun_sword"), 1.06, EPS, "金系不受离火加成")

	# 震退：玩家属性 × 厚土羁绊同一条乘区
	GameManager.reset_run()
	GameManager.knockback_mult = 1.5
	GameManager.synergy_knockback_mult = 1.25
	_c.near(GameManager.knockback_force(100.0), 187.5, EPS, "震退 1.5 × 厚土 1.25 = 187.5")
	GameManager.reset_run()
	_c.near(GameManager.knockback_force(100.0), 100.0, EPS, "重置后击退回归基础值")

	# 斩将：只认 is_elite 标记（精英与魔君都带），普通怪不受影响
	GameManager.reset_run()
	GameManager.elite_damage = 0.25
	var elite_stub := EnemyBase.new()
	elite_stub.is_elite = true
	var grunt_stub := EnemyBase.new()
	grunt_stub.is_elite = false
	_c.near(GameManager.elite_damage_mult_for(elite_stub), 1.25, EPS, "精英吃到斩将 +25%")
	_c.near(GameManager.elite_damage_mult_for(grunt_stub), 1.0, EPS, "普通怪不吃斩将")
	elite_stub.free()
	grunt_stub.free()
	GameManager.reset_run()

	# 免费重掷：先消耗次数，用完才付灵石；roll_shop(new_wave) 重置
	GameManager.reset_run()
	GameManager.free_rerolls = 2
	GameManager.wave_number = 3
	GameManager.spirit_stones = 100
	GameManager.rng.seed = 555
	GameManager.roll_shop(true)
	_c.equals(GameManager.reroll_free_left, 2, "新一波货架重置免费重掷次数")
	var stones_before := GameManager.spirit_stones
	GameManager.reroll_shop()
	_c.equals(GameManager.reroll_free_left, 1, "第一次重掷消耗免费次数")
	_c.equals(GameManager.spirit_stones, stones_before, "免费重掷不扣灵石")
	GameManager.reroll_shop()
	GameManager.reroll_shop()
	_c.equals(GameManager.reroll_free_left, 0, "免费次数用完")
	_c.equals(GameManager.spirit_stones, stones_before - GameBalance.reroll_cost(3, 0, 1.0), "第三次重掷开始付灵石（按第 1 次付费价）")
	GameManager.reset_run()

# ---------------- 法宝（被动道具）系统 ----------------

func _test_item_system() -> void:
	# 数据表完整性：apply 键都在白名单内、档位合法、图标就位、定价为正
	var fields: Array = GameBalance.upgrade_fields()
	var bad_keys: Array = []
	var bad_meta: Array = []
	for item_id in ItemData.all_ids():
		var def := ItemData.get_def(item_id)
		for key in def.get("apply", {}).keys():
			if not (key in fields):
				bad_keys.append("%s.%s" % [item_id, key])
		var tier := int(def.get("tier", 0))
		if tier < 1 or tier > 4:
			bad_meta.append("%s.tier=%d" % [item_id, tier])
		if int(def.get("price", 0)) <= 0:
			bad_meta.append("%s.price" % item_id)
		var icon_path: String = def.get("icon", "")
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			bad_meta.append("%s.icon" % item_id)
	_c.check(bad_keys.is_empty(), "法宝 apply 字段都在白名单内（非法: %s）" % str(bad_keys))
	_c.check(bad_meta.is_empty(), "法宝 档位/价格/图标 元数据齐全（异常: %s）" % str(bad_meta))

	# 档位权重：第 1 波只有凡品，传说第 14 波才解锁；福缘抬高高档
	var w1: Array = GameBalance.item_tier_weights(0.0, 1)
	_c.check(float(w1[0]) > 0.0 and float(w1[1]) == 0.0 and float(w1[3]) == 0.0, "第 1 波只出凡品法宝")
	var w15: Array = GameBalance.item_tier_weights(0.0, 15)
	_c.check(float(w15[3]) > 0.0, "第 15 波传说法宝解锁")
	var w_luck: Array = GameBalance.item_tier_weights(40.0, 15)
	_c.check(float(w_luck[3]) > float(w15[3]), "福缘抬高传说权重")

	# 抽取确定性 + unique 剔除
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	var pick_a := ItemData.pick_id(0.0, 15, [], rng)
	rng.seed = 31415
	_c.equals(ItemData.pick_id(0.0, 15, [], rng), pick_a, "同种子 → 同法宝")
	_c.check(pick_a != "", "第 15 波池子非空")
	var no_unique := true
	rng.seed = 2718
	for i in range(50):
		if ItemData.pick_id(0.0, 15, ["tisi_kuilei"], rng) == "tisi_kuilei":
			no_unique = false
	_c.check(no_unique, "已持有的 unique 法宝不会再次上架")
	# 池抽空（unique 已持有）时仍有非 unique 法宝可抽
	_c.check(ItemData.pick_id(0.0, 15, ["tisi_kuilei"], null) != "", "仍有非 unique 法宝可抽")

	# 购买落地：属性加成走与悟道同一条链路
	GameManager.reset_run()
	_c.check(GameManager.add_item("jubaopen"), "聚宝盆购买成功")
	_c.near(GameManager.harvest, 6.0, EPS, "聚宝盆灵韵 +6 落地")
	_c.check(GameManager.has_item("jubaopen"), "已持有列表登记")
	# 取舍型：狂血丹 +伤害 -护甲
	GameManager.add_item("kuangxue_dan")
	_c.near(GameManager.weapon_damage_mult, 1.18, EPS, "狂血丹伤害 +18%")
	_c.near(GameManager.armor, -2.0, EPS, "狂血丹护甲 -2（负面代偿）")
	# unique 限购
	_c.check(GameManager.add_item("tisi_kuilei"), "替死傀儡首购成功")
	_c.check(not GameManager.add_item("tisi_kuilei"), "替死傀儡不可重复购买")
	_c.equals(GameManager.items.count("tisi_kuilei"), 1, "unique 法宝仅持一件")

	# 商店购买链路：item offer 扣灵石、生效、标记售出
	GameManager.reset_run()
	GameManager.wave_number = 5
	GameManager.spirit_stones = 100
	GameManager.shop_offers = [{
		"kind": "item", "id": "mibao_luopan",
		"price": GameBalance.item_price(int(ItemData.get_def("mibao_luopan").get("price", 12)), 5, 1.0),
		"sold": false, "locked": false,
	}]
	var stones0 := GameManager.spirit_stones
	_c.check(GameManager.buy_offer(0), "法宝货架位购买成功")
	_c.near(GameManager.luck, 5.0, EPS, "觅宝罗盘福缘 +5 落地")
	_c.check(GameManager.spirit_stones < stones0, "购买扣了灵石")
	_c.check(bool(GameManager.shop_offers[0].get("sold", false)), "售出标记已打")

	# 替死傀儡：致死时消耗并免死（UnitRunner 无玩家节点，验证消耗语义即可）
	GameManager.reset_run()
	_c.check(not GameManager.try_revive(), "没有傀儡时免死不触发")
	GameManager.add_item("tisi_kuilei")
	_c.check(GameManager.try_revive(), "傀儡挡下致死一击")
	_c.check(not GameManager.has_item("tisi_kuilei"), "傀儡挡劫后消耗")
	_c.check(not GameManager.try_revive(), "一次性：第二次致死不再免死")

	# 回春葫芦 hook 求和（两件叠加）
	GameManager.reset_run()
	GameManager.add_item("huichun_hulu")
	GameManager.add_item("huichun_hulu")
	_c.near(GameManager.item_hook_sum("wave_heal_pct"), 0.30, EPS, "两件回春葫芦波末回血叠加到 30%")
	GameManager.reset_run()

	# 法宝定价与公式同源
	_c.equals(GameBalance.item_price(45, 9, 1.0), 45 + 8 * 2, "仙品法宝第 9 波 +16")
	_c.equals(GameBalance.item_price(45, 9, 0.8), int((45.0 + 16.0) * 0.8), "法宝价吃商店折扣")

	# 残丹化灵：回不上的那截气血折灵石（汇率与藏宝匣金灵石那一路同档，单颗封顶）
	_c.equals(GameBalance.heal_overflow_stones(0.0), 0, "没溢出就不给钱")
	_c.equals(GameBalance.heal_overflow_stones(-5.0), 0, "负数按 0 收")
	_c.equals(GameBalance.heal_overflow_stones(18.0), 14, "满口 18 点溢出 → 14 灵石（≈3 颗金灵石）")
	_c.equals(GameBalance.heal_overflow_stones(13.0), 10, "缺血 5 吃 18：溢出 13 → 10 灵石")
	_c.equals(GameBalance.heal_overflow_stones(45.0), 15, "高气血上限的 45 点溢出仍封顶 15")
	_c.check(GameBalance.HEAL_OVERFLOW_STONE_CAP <= 15, "折灵石单颗封顶不超过 15（不滚成巨款）")




# ---------------- 修士流派（角色）系统：9 名修士与不对称代偿 ----------------

func _test_cultivator_system() -> void:
	# 数据表完整性：9 名修士，每名都有 名称/称号/图标/天赋/代价/独立形象 字段
	_c.equals(CultivatorData.all_ids().size(), 9, "修士扩充至 9 名")
	var bad: Array = []
	for cid in CultivatorData.all_ids():
		var d := CultivatorData.get_def(cid)
		for f in ["name", "epithet", "icon", "sprite", "pros", "cons", "mods", "start_equip"]:
			if not d.has(f):
				bad.append("%s.%s" % [cid, f])
		if not ResourceLoader.exists(String(d.get("icon", ""))):
			bad.append("%s.icon" % cid)
		# 独立形象字段非空即可（图集生成中由 Player 回退 pawn_blue 兜底）
		if String(d.get("sprite", "")).is_empty():
			bad.append("%s.sprite" % cid)
	_c.check(bad.is_empty(), "修士元数据齐全（缺: %s）" % str(bad))

	# 魅影（Ghost 原型）：闪避上限抬到 90%，锁死罡气护体
	GameManager.reset_run()
	GameManager.cultivator_id = "meiying"
	GameManager._apply_cultivator()
	_c.near(GameManager.dodge, 0.30, EPS, "魅影初始闪避 +30%")
	GameManager.dodge = 1.0
	_c.near(GameManager.get_effective_dodge(), 0.9, EPS, "魅影闪避上限 90%（其余人 60%）")
	_c.check("armor_up" in GameManager.locked_upgrades, "魅影锁死罡气护体")

	# 独臂刀圣（One Armed 原型）：上阵槽上限为 3，伤害翻倍、施法更快
	GameManager.reset_run()
	GameManager.cultivator_id = "dubi"
	GameManager._apply_cultivator()
	_c.equals(GameManager.max_weapon_slots(), 3, "独臂刀圣上阵槽上限为 3")
	_c.near(GameManager.weapon_damage_mult, 2.0, EPS, "独臂刀圣伤害 ×2.0")
	_c.near(GameManager.attack_speed_mult, 0.7, EPS, "独臂刀圣施法间隔 ×0.7")

	# 狂战蛮修（Loud 原型）：妖潮 +50%，灵韵每波流失 3 点再复利；流失下限为 0
	GameManager.reset_run()
	GameManager.cultivator_id = "kuangzhan"
	GameManager._apply_cultivator()
	_c.near(GameManager.enemy_count_mult, 1.5, EPS, "狂战蛮修妖潮 +50%")
	GameManager.harvest = 10.0
	GameManager.wave_number = 2
	GameManager.apply_harvest()
	_c.near(GameManager.harvest, (10.0 - 3.0) * GameBalance.HARVEST_GROWTH, EPS, "灵韵先流失 3 点再复利")
	GameManager.harvest = 1.0
	GameManager.apply_harvest()
	_c.check(GameManager.harvest >= 0.0, "灵韵流失不会扣成负数（负值会被复利放大）")

	# 夺舍散人（Mutant 原型）：修为需求 ×0.6，且倍率不逐层复利
	GameManager.reset_run()
	GameManager.cultivator_id = "duoshe"
	GameManager._apply_cultivator()
	_c.equals(GameManager.experience_to_next, int(round(GameBalance.EXP_FIRST_LEVEL * 0.6)), "夺舍散人首级门槛 10→6")
	GameManager.add_experience(GameManager.experience_to_next)
	_c.equals(GameManager.level, 2, "夺舍散人升到 2 级")
	_c.equals(GameManager.experience_to_next, int(round(float(GameBalance.exp_to_next(GameBalance.EXP_FIRST_LEVEL)) * 0.6)), "第 2 级门槛 = 原链 ×0.6（不复利）")

	# 多宝道人：货架 +1 格、法宝 75 折
	GameManager.reset_run()
	GameManager.cultivator_id = "duobao"
	GameManager._apply_cultivator()
	GameManager.wave_number = 2
	GameManager.rng.seed = 777
	GameManager.roll_shop(true)
	_c.equals(GameManager.shop_offers.size(), GameManager.SHOP_BASE_SLOTS + 1, "多宝道人货架 %d 格" % (GameManager.SHOP_BASE_SLOTS + 1))
	_c.near(GameManager.item_price_mult, 0.75, EPS, "多宝道人法宝 75 折")

	# 回归：常规修士不污染通用机制
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager._apply_cultivator()
	_c.equals(GameManager.max_weapon_slots(), WeaponData.MAX_SLOTS, "常规修士槽位 6")
	_c.near(GameManager.enemy_count_mult, 1.0, EPS, "常规修士妖潮规模不变")
	GameManager.dodge = 1.0
	_c.near(GameManager.get_effective_dodge(), GameManager.DODGE_CAP, EPS, "常规修士闪避上限仍 60%")

	# 道统选择界面上下分层与开局装备验证
	_c.check(not CultivatorData.get_start_equip("fuzhen").is_empty(), "符阵灵童明确说明开局额外自带装备")
	_c.check(CultivatorData.get_start_equip("jianchi").is_empty(), "无额外装备的角色不标注开局装备")
	var cs := CultivatorSelect.new()
	add_child(cs)
	cs.show_select()
	_c.equals(cs._roster_row.get_child_count(), 9, "道统选择界面下半部分展示 9 张形象小卡片")
	_c.check(cs._detail_panel.visible, "道统选择界面上半部分详解大卡片正常可见")
	cs._select_cultivator("fuzhen")
	_c.equals(cs._selected_id, "fuzhen", "点击小卡片即时切换至对应修士")
	cs.queue_free()

	GameManager.reset_run()

# ---------------- 震退方向 ----------------

## 法器震退的方向判据：以落点径向为主，但任何一次震退都不许带「朝玩家」的分量。
## 现场（用户 2026-10-08）：番天镇岳印的落点是按角度扇区分给各法器的，常常砸在玩家外侧的敌人上，
## 纯径向就把「落点与玩家之间」那一圈敌人一波一波拱到身上 —— 不崩不报错，只有真机挨打才发现。
func _test_knock_direction() -> void:
	var p := Vector2.ZERO
	var src := Vector2(300.0, 0.0)                 # 落点：玩家正东 300 的敌人（正是分配位，不是最近位）
	var e := Vector2(220.0, 0.0)                   # 夹在玩家与落点之间的那个敌人
	var d := GameBalance.knock_dir(src, e, p)
	_c.check(d.dot((e - p).normalized()) >= -EPS * 100.0, "共线对撞不往玩家身上推（得 %s）" % str(d))
	_c.near(d.length(), 1.0, EPS * 100.0, "输出恒为单位向量（各法器击退力度数值不受影响）")
	# 反例自证：旧写法此刻确实在往玩家推 ⇒ 上面那条判据不是空转
	var old_dir := (e - src).normalized()
	_c.check(old_dir.dot((e - p).normalized()) < 0.0, "反例成立：旧写法把落点内侧的敌人推向玩家")
	# 落点外侧维持径向（大印外扩的爽感不许丢）
	_c.check(GameBalance.knock_dir(src, Vector2(380.0, 0.0), p).is_equal_approx(Vector2.RIGHT), "落点外侧原样外炸")
	# 以落点为心、震退半径 95 一整圈，逐个方位都不朝玩家
	for i in range(12):
		var q: Vector2 = src + Vector2(95.0, 0.0).rotated(TAU * float(i) / 12.0)
		var dd := GameBalance.knock_dir(src, q, p)
		_c.check(dd.dot((q - p).normalized()) >= -EPS * 100.0, "落点周围第 %d/12 方位不推向玩家" % (i + 1))
	# 退化输入不许出 NaN / 零长度
	_c.check(GameBalance.knock_dir(e, e, p).is_equal_approx(Vector2.RIGHT), "施力点压在敌人身上→按远离玩家推")
	_c.check(GameBalance.knock_dir(src, p, p).is_equal_approx(Vector2.LEFT), "敌人正贴在玩家身上→维持径向")
	# 玩家位置退回施力点（局外预览、单测）时，方向与纯径向逐位相同
	_c.check(GameBalance.knock_dir(src, e, src).is_equal_approx(old_dir), "玩家位置退回施力点=旧行为")
	# 调用点不许再自己抄径向：那等于把「往玩家身上推」写回去
	for path in ["res://scripts/weapons/ThunderBurst.gd", "res://scripts/weapons/FloatingWeapon.gd", "res://scripts/weapons/SunOrb.gd", "res://scripts/entities/BlessingObelisk.gd"]:
		var text := ""
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
		_c.check(not text.contains("(enemy.global_position - global_position).normalized()"), "%s 的震退方向走统一出口" % path)

	# 15 把法器皆有定义合法击退力，且芭蕉扇与番天镇岳印击退力突出
	for w_id in WeaponData.SHOP_POOL:
		var kb := WeaponData.knockback_for(w_id, 0.0)
		_c.check(kb >= 80.0, "法器 %s 配置了有效击退力 (%.0f)" % [w_id, kb])
	_c.check(WeaponData.knockback_for("bajiao_fan") >= 350.0, "芭蕉扇击退力 >= 350（兑现文案‘击退极远’）")
	_c.check(WeaponData.knockback_for("fantian_yin") >= 350.0, "番天镇岳印击退力 >= 350（兑现文案‘强击退’）")

	# 敌人受击定向形变与受击硬直验证
	var test_enemy := EnemyBase.new()
	var squash_horiz := test_enemy._calculate_hit_squash(Vector2(200.0, 10.0), false)
	_c.check(squash_horiz.x < 1.0 and squash_horiz.y > 1.0, "横向受击水平压扁垂直拉伸")
	var squash_vert := test_enemy._calculate_hit_squash(Vector2(10.0, 200.0), false)
	_c.check(squash_vert.x > 1.0 and squash_vert.y < 1.0, "纵向受击垂直压扁水平拉伸")
	test_enemy.free()

# ---------------- 危险度（Danger 0~5）：公式、解锁与落盘 ----------------

func _test_danger_system() -> void:
	# 公式钉线
	_c.near(GameBalance.danger_hp_mult(0), 1.0, EPS, "危险度 0 血量不变")
	_c.near(GameBalance.danger_hp_mult(5), 2.1, EPS, "危险度 5 血量 ×2.1")
	_c.near(GameBalance.danger_dmg_mult(5), 1.6, EPS, "危险度 5 伤害 ×1.6")
	_c.near(GameBalance.danger_count_mult(5), 1.75, EPS, "危险度 5 妖潮 ×1.75")
	_c.near(GameBalance.danger_hp_mult(99), GameBalance.danger_hp_mult(5), EPS, "超档夹到 5")
	_c.near(GameBalance.danger_hp_mult(-1), 1.0, EPS, "负档夹到 0")

	# 选择器不许越权选未解锁档
	var orig_unlocked := GameManager.max_danger_unlocked
	GameManager.max_danger_unlocked = 0
	GameManager.danger_level = 0
	GameManager.set_danger(3)
	_c.equals(GameManager.danger_level, 0, "未解锁危险度 3 选不上")
	GameManager.set_danger(0)
	_c.equals(GameManager.danger_level, 0, "凡尘（0 档）总可选")

	# 通关当前最高档 → 解锁下一档；打旧档不重复解锁
	GameManager.reset_run()
	GameManager.danger_level = 0
	GameManager.trigger_game_over(true)
	_c.equals(GameManager.max_danger_unlocked, 1, "通关凡尘解锁危险度 1")
	GameManager.reset_run()
	GameManager.trigger_game_over(true)
	_c.equals(GameManager.max_danger_unlocked, 1, "重复通关同一档不再解锁")
	GameManager.reset_run()
	GameManager.danger_level = 1
	GameManager.trigger_game_over(true)
	_c.equals(GameManager.max_danger_unlocked, 2, "通关微澜解锁危险度 2")
	GameManager.reset_run()
	GameManager.trigger_game_over(false)
	_c.equals(GameManager.max_danger_unlocked, 2, "战败不解锁")

	# 落盘往返：改→存→改→读回
	GameManager.max_danger_unlocked = 3
	GameManager._save_progress()
	GameManager.max_danger_unlocked = 0
	GameManager._load_progress()
	_c.equals(GameManager.max_danger_unlocked, 3, "危险度解锁落盘后可读回")

	# 还原测试前的玩家进度，不弄脏真实存档
	GameManager.max_danger_unlocked = orig_unlocked
	GameManager._save_progress()
	GameManager.danger_level = 0
	GameManager.reset_run()

# ---------------- 成就里程碑、法宝过滤与生涯持久化存档 ----------------

func _test_achievement_and_meta_save() -> void:
	# 1. 数据表完整性与反查自洽
	_c.equals(AchievementData.ACHIEVEMENTS.size(), 9, "成就里程碑共配置 9 条")
	for aid in AchievementData.all_ids():
		var adef := AchievementData.get_def(aid)
		_c.check(not adef.is_empty(), "成就 %s 定义存在" % aid)
		var rtype := String(adef.get("reward_type", ""))
		var rid := String(adef.get("reward_id", ""))
		if rtype == "cultivator":
			_c.check(not CultivatorData.get_def(rid).is_empty(), "成就 %s 奖励修士 %s 在修士表中存在" % [aid, rid])
			_c.equals(AchievementData.cultivator_unlock_achievement(rid).get("id", ""), aid, "反查修士 %s 解锁成就一致" % rid)
		elif rtype == "item":
			_c.check(not ItemData.get_def(rid).is_empty(), "成就 %s 奖励法宝 %s 在法宝表中存在" % [aid, rid])
			_c.equals(AchievementData.item_unlock_achievement(rid).get("id", ""), aid, "反查法宝 %s 解锁成就一致" % rid)
	_c.equals(AchievementData.DEFAULT_CULTIVATORS.size(), 4, "初始默认开放 4 名基础修士")
	_c.equals(AchievementData.DEFAULT_ITEMS.size(), 16, "初始默认开放 16 件基础法宝")

	# 2. 法宝过滤入池：未解锁法宝绝不上架
	var rng := RandomNumberGenerator.new()
	rng.seed = 8888
	# 替死傀儡（tisi_kuilei）与混元珠（hunyuan_zhu）未在 unlocked 列表中
	var restricted_unlocked: Array = ["jubaopen", "mibao_luopan", "qiankun_dai", "wujian_shi"]
	for i in range(40):
		var picked := ItemData.pick_id(50.0, 16, [], rng, restricted_unlocked)
		_c.check(picked in restricted_unlocked, "抽出的法宝 %s 必在已解锁集合中" % picked)
	# 缺省空数组参数时保持向下兼容（全池开放）
	var fallback_picked := ItemData.pick_id(0.0, 1, [], rng)
	_c.check(not fallback_picked.is_empty(), "未传 unlocked_items 时全池开放向下兼容")

	# 备份当前玩家真实进度
	var orig_cults := GameManager.unlocked_cultivators.duplicate()
	var orig_items := GameManager.unlocked_items.duplicate()
	var orig_achs := GameManager.unlocked_achievements.duplicate()
	var orig_stats := GameManager.career_stats.duplicate()
	var orig_records := GameManager.cultivator_best_danger.duplicate()
	var orig_hist := GameManager.run_history.duplicate()

	# 3. 模拟结算与成就达成触发
	GameManager.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
	GameManager.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()
	GameManager.unlocked_achievements = []
	GameManager.career_stats = {
		"total_runs": 0, "total_wins": 0, "total_kills": 0,
		"best_wave": 0, "best_kills": 0, "total_stones": 0, "total_time": 0.0,
	}
	GameManager.cultivator_best_danger = {}
	GameManager.run_history = []

	# 模拟一局：斩妖 600 只，单局持有 260 灵石，第 16 波战败
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.danger_level = 0
	GameManager.kills = 600
	GameManager.spirit_stones = 260
	GameManager.wave_number = 16
	GameManager.game_time = 320.0
	GameManager.trigger_game_over(false)

	_c.check("ach_cult_meiying" in GameManager.unlocked_achievements, "累计斩妖达到 500 解锁【踏雪无痕】成就")
	_c.check("meiying" in GameManager.unlocked_cultivators, "魅影修士已解锁")
	_c.check("ach_cult_duobao" in GameManager.unlocked_achievements, "灵石达到 250 解锁【富甲一方】成就")
	_c.check("duobao" in GameManager.unlocked_cultivators, "多宝道人已解锁")
	_c.check("ach_item_pojia" in GameManager.unlocked_achievements, "抵御到第 16 波解锁【斩将夺旗】成就")
	_c.check("pojia_zhui" in GameManager.unlocked_items, "破甲锥法宝已入池")
	_c.equals(int(GameManager.career_stats["total_runs"]), 1, "生涯修行场次 +1")
	_c.equals(int(GameManager.career_stats["total_kills"]), 600, "生涯斩妖累计 600")
	_c.equals(int(GameManager.career_stats["best_wave"]), 16, "最高波次更新为 16")
	_c.equals(GameManager.run_history.size(), 1, "战报记录增加 1 条")
	_c.equals(GameManager.is_cultivator_unlocked("meiying"), true, "is_cultivator_unlocked 接口自洽")

	# 再模拟一局：独臂刀圣在 D1 渡劫成功
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.danger_level = 1
	GameManager.kills = 300
	GameManager.spirit_stones = 150
	GameManager.wave_number = 20
	GameManager.trigger_game_over(true)

	_c.check("ach_cult_dubi" in GameManager.unlocked_achievements, "通关 D1 解锁【孤峰问剑】成就")
	_c.check("dubi" in GameManager.unlocked_cultivators, "独臂刀圣已解锁")
	_c.check("ach_cult_duoshe" in GameManager.unlocked_achievements, "任意通关解锁【渡劫初成】成就")
	_c.check("duoshe" in GameManager.unlocked_cultivators, "夺舍散人已解锁")
	_c.equals(GameManager.get_cultivator_best_danger("jianchi"), 1, "剑痴通关印记更新为 D1")

	# 4. 存档往返恢复校验：修改 → 存盘 → 清内存 → 读回
	GameManager._save_progress()
	GameManager.unlocked_cultivators = []
	GameManager.unlocked_items = []
	GameManager.unlocked_achievements = []
	GameManager.career_stats = {}
	GameManager.cultivator_best_danger = {}
	GameManager.run_history = []
	GameManager._load_progress()

	_c.check("meiying" in GameManager.unlocked_cultivators and "dubi" in GameManager.unlocked_cultivators, "读档后解锁修士保持完整")
	_c.check("pojia_zhui" in GameManager.unlocked_items, "读档后解锁法宝保持完整")
	_c.equals(int(GameManager.career_stats.get("total_runs", 0)), 2, "读档后生涯局数恢复")
	_c.equals(int(GameManager.cultivator_best_danger.get("jianchi", -1)), 1, "读档后剑痴 D1 印记恢复")
	_c.equals(GameManager.run_history.size(), 2, "读档后战报恢复")

	# 还原测试前的玩家真实进度
	GameManager.unlocked_cultivators = orig_cults
	GameManager.unlocked_items = orig_items
	GameManager.unlocked_achievements = orig_achs
	GameManager.career_stats = orig_stats
	GameManager.cultivator_best_danger = orig_records
	GameManager.run_history = orig_hist
	GameManager._save_progress()
	GameManager.reset_run()

# ---------------- 远程「点杀位」档：单发咬不住几个敌人的法器必须啃得动硬目标 ----------------

## 背景（2026-10-08 用户口径：「一些远程且只能击中一个敌人的武器需要加强一下，火符比其他武器弱很多」）：
## 近战弧扫与环绕法宝是当帧结算 / 接触即伤，天生没有"打不中"这笔税；弹丸过去直线飞行，
## 远距对横移目标的实测命中率只有 11~33%（见 tests/ProjectileProbe.tscn）。
## 追踪上线后纸面 DPS 才等于真 DPS，于是这里把两类档位的相对关系钉死：
##   · 点杀位（单发最多结算 2 个敌人的弹丸）：单体 DPS 必须站上"非远程法器单体 DPS 中位数"；
##   · 全体弹丸：单体 DPS 不得低于该中位的 0.8 倍。
## 参照点是现算的，不做魔法数字 —— 以后近战/环绕改数值，这条下限跟着一起走。
func _test_ranged_focus_dps() -> void:
	var ranged: Array[String] = []
	var others: Array[float] = []
	for w_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(w_id)
		var dps := WeaponData.sustained_single_dps(w_id, 1)
		if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
			ranged.append(w_id)
		else:
			others.append(dps)
	others.sort()
	var med: float = others[int(others.size() / 2)] if not others.is_empty() else 0.0

	# 1. 尺子本身先自证：口径与运行时逐条对齐，估计算错这里就红
	_c.equals(WeaponData.targets_per_shot("huoyan_fu"), 2, "火焰符双符齐掷 = 单发最多结算 2 敌，仍属点杀位")
	_c.equals(WeaponData.targets_per_shot("gengjin_feijian"), 2, "庚金飞剑贯穿两敌")
	_c.equals(WeaponData.targets_per_shot("wanmu_lingfu"), 3, "万木灵符 1 穿透 + 2 弹射 = 单发 3 敌")
	_c.equals(WeaponData.targets_per_shot("liuye_feidao"), 9, "柳叶飞刀 3 发 × 3 穿透 = 单发 9 敌")
	_c.equals(WeaponData.targets_per_shot("bajiao_fan"), 6, "近战横扫天生群体，不进点杀位")
	# 火焰符 ★1：damage × 发数 ÷ 冷却 + 单张灼烧（冷却 < 灼烧时长 ⇒ 常驻）。数字全从表里取，
	# 这三条验的是"公式的语义"，不是某一次的数值快照 —— 以后调伤害不用回来改断言
	var hf := WeaponData.get_def("huoyan_fu")
	var hf_dmg: float = float(hf.get("damage", 0.0))
	var hf_cd: float = float(hf.get("cooldown", 1.0))
	var hf_n: float = float(hf.get("projectile_count", 1))
	_c.near(WeaponData.sustained_single_dps("huoyan_fu", 1),
		hf_dmg * hf_n / hf_cd + hf_dmg * float(hf.get("burn_ratio", 0.0)), 0.001,
		"单体 DPS = 逐发弹伤之和 + 常驻灼烧（与 BladeProjectile 的 burn_dps 同源）")
	# 青云剑 ★1：近战在 FloatingWeapon._deal_melee_damage 里有 ×1.35 加护
	var qy := WeaponData.get_def("qingyun_sword")
	_c.near(WeaponData.sustained_single_dps("qingyun_sword", 1),
		float(qy.get("damage", 0.0)) * 1.35 / float(qy.get("cooldown", 1.0)), 0.001,
		"近战单体 DPS 含 ×1.35 加护")
	# 玄冰飞针：三发齐射在"场上只剩一个敌人"时全部归它（追踪上线后的新口径）
	var xb := WeaponData.get_def("xuanbing_feizhen")
	_c.near(WeaponData.sustained_single_dps("xuanbing_feizhen", 1),
		float(xb.get("damage", 0.0)) * float(xb.get("projectile_count", 1)) / float(xb.get("cooldown", 1.0)), 0.001,
		"多发弹丸对孤立目标按发数求和")
	_c.check(WeaponData.sustained_single_dps("huoyan_fu", 3) > WeaponData.sustained_single_dps("huoyan_fu", 2),
		"星级越高单体 DPS 越高（尺子跟 damage_for/cooldown_for 同向）")

	# 2. 分类自洽：点杀位这一档不许空（空了就等于这条判据没人守着）
	var focus: Array[String] = []
	for w_id in ranged:
		if WeaponData.is_focus_ranged(w_id):
			focus.append(w_id)
	_c.check(focus.size() >= 2, "点杀位远程法器至少两把（实得 %d 把：%s）" % [focus.size(), str(focus)])

	# 3. 档位下限：点杀位 ≥ 中位，全体弹丸 ≥ 0.8 × 中位
	var worst_focus: float = 1e9
	for w_id in focus:
		worst_focus = minf(worst_focus, WeaponData.sustained_single_dps(w_id, 1))
	# 下限取 0.95× 而不是 1.0×：留一点余量，免得别人把近战/环绕往上抬 3% 就把远程表逼着跟着改
	_c.check(worst_focus >= med * 0.95,
		"点杀位单体 DPS %.1f ≥ 0.95×非远程中位 %.1f（贴脸与环绕必须被啃硬目标的速度反超）" % [worst_focus, med * 0.95])
	var worst_ranged: float = 1e9
	var worst_id: String = ""
	for w_id in ranged:
		var v := WeaponData.sustained_single_dps(w_id, 1)
		if v < worst_ranged:
			worst_ranged = v
			worst_id = w_id
	_c.check(worst_ranged >= med * 0.75,
		"最弱弹丸【%s】单体 DPS %.1f ≥ 0.75×中位 %.1f" % [worst_id, worst_ranged, med * 0.75])

	# 4. 群体档不许反过来吃掉单体档：弹丸单发结算的敌人越多，单价就该越便宜
	_c.check(int(WeaponData.get_def("huoyan_fu").get("price", 0)) <= int(WeaponData.get_def("liuye_feidao").get("price", 0)),
		"单发只咬 1 敌的火焰符不比单发咬 9 敌的柳叶飞刀贵")
	_c.check(WeaponData.sustained_single_dps("huoyan_fu", 1) > WeaponData.sustained_single_dps("liuye_feidao", 1),
		"火焰符对孤立目标的 DPS 高于群体弹丸（各档各有各的活）")
	_c.check(WeaponData.sustained_single_dps("gengjin_feijian", 1) > WeaponData.sustained_single_dps("liuye_feidao", 1),
		"庚金飞剑对孤立目标的 DPS 高于群体弹丸")

	# 5. 元素 DoT 叠层共鸣与元素伤害跳字加成校验
	_c.near(GameBalance.stack_burn_dps(0.0, 20.0), 20.0, EPS, "首次灼烧全额生效")
	_c.near(GameBalance.stack_burn_dps(20.0, 16.0), 24.0, EPS, "已灼烧目标再受灼烧时叠加 25% 共鸣伤害")
	_c.near(GameBalance.burn_tick_damage(20.0, 0.0, 1.0), 10.0, EPS, "0 元素伤害时灼烧每跳 0.5s 为 10 点")
	_c.near(GameBalance.burn_tick_damage(20.0, 10.0, 1.0), 14.0, EPS, "10 点元素伤害为灼烧每跳额外提供 +4 点伤害")
	_c.near(GameBalance.burn_tick_damage(20.0, 10.0, 1.5), 21.0, EPS, "离火羁绊倍率 1.5x 完整放大灼烧跳字")
	_c.near(GameBalance.poison_tick_damage(10.0, 10.0), 8.0, EPS, "10 点元素伤害为剧毒每跳额外提供 +3 点伤害")

# ---------------- 御灵（环绕法宝）动态轨道与伸缩扑击 ----------------

func _test_spirit_orbit_dynamics() -> void:
	# 1. 无敌情巡航：非战斗状态，所有灵宝平稳处于基准半径
	var empty_res := GameBalance.compute_spirit_orbit([0.0, PI], [], 58.0, 28.0, 135.0)
	_c.equals(bool(empty_res.get("in_combat", true)), false, "无敌情时不触发战斗激战状态")
	_c.near(float(empty_res["radii"][0]), 58.0, EPS, "空敌情下第 1 枚灵宝回归 58px 基准半径")
	_c.near(float(empty_res["radii"][1]), 58.0, EPS, "空敌情下第 2 枚灵宝回归 58px 基准半径")

	# 2. 贴身危急突破（32px）：正前方灵宝极限内收至 32px 护体解围，杜绝贴身盲区
	var danger_enemies := [{"dist": 32.0, "angle": 0.0}]
	var danger_res := GameBalance.compute_spirit_orbit([0.0, PI], danger_enemies, 58.0, 28.0, 135.0)
	_c.equals(bool(danger_res.get("in_combat", false)), true, "贴脸近敌触发战斗激战状态")
	_c.near(float(danger_res["radii"][0]), 32.0, EPS, "同侧灵宝迅速内收至 32px 贴身封堵")

	# 3. 极度贴身（10px）：内收半径被地板 min_radius(28px) 截断，不会坍缩进玩家中心
	var super_close := [{"dist": 10.0, "angle": 0.0}]
	var close_res := GameBalance.compute_spirit_orbit([0.0], super_close, 58.0, 28.0, 135.0)
	_c.near(float(close_res["radii"][0]), 28.0, EPS, "内收最低安全地板 28px 防止穿模倒扣")

	# 4. 扇区索敌扑击（105px）：朝向扇区内的敌人引发灵宝主动出圈扑杀
	var lunge_enemies := [{"dist": 105.0, "angle": 0.1}]
	var lunge_res := GameBalance.compute_spirit_orbit([0.0, PI], lunge_enemies, 58.0, 28.0, 135.0)
	_c.near(float(lunge_res["radii"][0]), 105.0, EPS, "正前方扇区灵宝主动扑击外扩至 105px")

	# 5. 超出最大射程（260px）：不触发激战加速，保持基准半径
	var far_enemies := [{"dist": 260.0, "angle": 0.0}]
	var far_res := GameBalance.compute_spirit_orbit([0.0, PI], far_enemies, 58.0, 28.0, 135.0)
	_c.equals(bool(far_res.get("in_combat", true)), false, "超远距离敌人不触发战斗状态")
	_c.near(float(far_res["radii"][0]), 58.0, EPS, "超远敌人下灵宝保持 58px")

	# 6. 转速测试：默认基础巡航角速度减小至平稳的 2.4 rad/s，且随攻速加点等比放大
	var base_spd := GameBalance.spirit_orbit_angular_speed(2.4, 1.0, 1.0, false, 1)
	_c.near(base_spd, 2.4, EPS, "默认无加点非战斗旋转角速度为 2.4 rad/s（平稳巡航）")
	var combat_spd := GameBalance.spirit_orbit_angular_speed(2.4, 1.0, 1.0, true, 1)
	_c.near(combat_spd, 2.4 * 1.18, EPS, "临战微幅加速 1.18x（~2.83 rad/s）")
	# 模拟技能加点 1 次 haste_up（施法间隔 ×0.88）
	var haste1_spd := GameBalance.spirit_orbit_angular_speed(2.4, 0.88, 1.0, false, 1)
	_c.near(haste1_spd, 2.4 * (1.0 / 0.88), EPS, "加点 1 次法诀迅捷攻速 +13.6%，转速等比提升")
	_c.check(haste1_spd > base_spd, "攻速加点后御灵旋转速度切实增加")
	# 模拟攻速堆叠（施法间隔 0.50）
	var haste_high_spd := GameBalance.spirit_orbit_angular_speed(2.4, 0.50, 1.0, false, 1)
	_c.near(haste_high_spd, 2.4 * 2.0, EPS, "攻速翻倍时御灵转速翻倍为 4.8 rad/s")

	# 7. 数据表三件御灵装备属性强化验证
	for sid in ["lingdie", "hanquan_yulian", "hunyuan_zhong"]:
		var sdef := WeaponData.get_def(sid)
		_c.check(float(sdef.get("range", 0.0)) >= 120.0, "御灵法器 %s 射程强化至 >= 120px（当前 %.0f）" % [sid, float(sdef.get("range", 0.0))])
		_c.check(float(sdef.get("damage", 0.0)) >= 24.0, "御灵法器 %s 基础伤害强化至 >= 24（当前 %.0f）" % [sid, float(sdef.get("damage", 0.0))])
		_c.check(float(sdef.get("knockback", 0.0)) >= 160.0, "御灵法器 %s 击退强化至 >= 160（当前 %.0f）" % [sid, float(sdef.get("knockback", 0.0))])


