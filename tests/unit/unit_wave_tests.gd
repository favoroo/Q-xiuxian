class_name UnitWaveTests
extends UnitTestsBase

## 单测模块：波次缩放 / Boss 波 / 刷怪量 / 怪物配比 / 危险度（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_wave_scaling() -> void:
	_c.near(GameBalance.enemy_hp_mult(1), 1.0, EPS, "第 1 波血量倍率 1.0")
	_c.near(GameBalance.enemy_hp_mult(10), pow(1.16, 9), EPS, "第 10 波血量复利 ×3.80")
	_c.near(GameBalance.enemy_hp_mult(20), pow(1.16, 19), EPS, "第 20 波血量复利 ×16.89")
	_c.near(GameBalance.enemy_dmg_mult(10), pow(1.06, 9), EPS, "第 10 波接触伤害复利 ×1.69")
	_c.near(GameBalance.wave_duration(1), 22.0, EPS, "第 1 波时长 22s")
	_c.near(GameBalance.wave_duration(20), 60.0, EPS, "第 20 波封顶 60s")
	_c.near(GameBalance.wave_duration(99), 60.0, EPS, "无尽波次也封顶 60s")
	_c.near(GameBalance.spawn_interval(1), 1.555, EPS, "第 1 波刷怪间隔 1.555s")
	_c.near(GameBalance.spawn_interval(40), GameBalance.SPAWN_INTERVAL_MIN, EPS, "刷怪间隔有下限")
	_c.near(GameBalance.enemy_hp_mult(0), GameBalance.enemy_hp_mult(1), EPS, "非法波次 0 被夹到 1")

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

func _test_spawn_shape() -> void:
	_c.equals(GameBalance.spawn_batch(1, 0.0), 2, "第 1 波 + 触发追加 → 2 只")
	_c.equals(GameBalance.spawn_batch(1, 0.9), 1, "第 1 波未触发追加 → 1 只")
	_c.equals(GameBalance.spawn_batch(8, 0.9), 2, "第 8 波 → 1+1=2 只")
	_c.equals(GameBalance.spawn_batch(8, 0.0), 3, "第 8 波追加 → 3 只")
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
