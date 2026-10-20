extends Node

## 藏宝匣「寻宝流」经济链路判据（2026-10-11）
##
## 用户口径：「针对宝箱再加些玩法，在技能加点或商店里加物品，提高刷宝箱的数量和概率」。
## 2026-10-12 用户口径（本轮改版）：「砸开宝箱受击数减一这算什么加成，这个加成不要；
## 商店里那件砍击数还要带个 debuff 的，太蠢了」⇒ 砍击数那条腿（悟道「开箱省力」+ 法宝「卸匣锥」）
## 整条删掉，换成抬兑现量的「宝箱掉落」（悟道 chest_reward_up + 法宝 manxia_jue）。
## 这条链路横跨 数据表 → 属性字段 → 刷怪口 → 匣子本体 → 掉落兑现，任何一环写歪都会变成
## 「卡面上写了 +1，场上还是 2 口」的假加成（历史上这类静默无效踩过多次），所以判据分三层，
## 每一层都从**生产入口**进去量，不在测试里另算一套：
##
## 1) 纯函数层（BalanceChest 经 GameBalance 门面）：数量曲线与硬顶、三档权重的单调与
##    「品质为 0 时铜/玉仍有正权重」（第 1 波就该见到高档匣）、击数是定值、
##    开箱收益乘区的放大与两条例外（每颗灵石修为值不放大 / 回复量有顶）、
##    奖励表与改版前木匣口径一致（防偷偷改掉基准档）。
## 2) 来源层：apply_upgrade / add_item 走真实落地链路后，GameManager 字段确实吃到幅度，
##    并且下一次 _spawn_chests 刷出的匣子数、击数、体型就是那些幅度（字段追到消费方）。
## 3) 现场层：Main 场景 + start_run，冻住波次状态机，量
##    刷出口数 / 上限 / 档位判定半径与体型同源 / 玉匣真多一件法宝 / 送满上限后退回仍有掉落 /
##    同一口铜匣在 ×1 与 ×2 两档下到账数不同（开箱收益真的兑现）/
##    纳灵盘开与关时掉出的经验球 target_player 不同（磁吸真的接上了）。
##
## 运行: godot --headless --path . res://tests/ChestEconomyCheck.tscn
##       godot --headless --path . res://tests/ChestEconomyCheck.tscn -- --selftest
##
## 反例（--selftest 逐条钉住，证明上面三层不是白给的）：
##   ① 旧数量口径恒 mini(2+wave/6,4)，不吃加成 ⇒ 与「设了 +3 就该刷 5 口」这条判据冲突；
##   ② 旧代码只有木匣一档（铜/玉权重 0）⇒ 「品质为 0 也见得到高档匣」这条会红；
##   ③ 旧写法按档位表原样发掉落、不吃「宝箱掉落」乘区 ⇒ ×2 到账翻倍那条会红；
##   ④ 奖励表若没有 grant_item，玉匣送法宝那条判据无从成立；
##   ⑤ 磁吸判据要求「关/开两种状态读数不同」，同值即空转，selftest 里按这个形状验一次。

var _c := TestCheck.new()
var _main: Node = null
var _spawner: WaveSpawner = null

func _ready() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()
		_finish()
		return
	Engine.time_scale = 8.0
	_test_pure()
	await _test_live()
	Engine.time_scale = 1.0
	_finish()

func _finish() -> void:
	if _c.report("CHESTECON_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1) 纯函数层 ----------------

func _test_pure() -> void:
	# 数量：基础曲线 + 加成 + 硬顶
	_c.equals(GameBalance.chest_count(1, 0), 2, "不吃加成时第 1 波仍刷 2 口（基准档没被偷偷改掉）")
	_c.equals(GameBalance.chest_count(12, 0), 4, "第 12 波基础档封顶 4 口")
	_c.equals(GameBalance.chest_count(1, 3), 5, "宝箱数量 +3 ⇒ 第 1 波 5 口")
	_c.equals(GameBalance.chest_count(20, 99), GameBalance.CHEST_COUNT_CAP, "加成堆到天上也被硬顶夹住")
	_c.equals(GameBalance.chest_count(1, -5), 2, "负数加成按 0 计，不会倒扣成 0 口")

	# 三档权重：可见性 + 单调 + 不削底子
	var w0: Array = GameBalance.chest_tier_weights(0.0, 0.0)
	_c.check(float(w0[BalanceChest.TIER_COPPER]) > 0.0 and float(w0[BalanceChest.TIER_JADE]) > 0.0,
		"品质为 0 时铜匣与玉匣仍有正权重 ⇒ 第 1 波就可能刷出高档匣（不许锁到七八波）")
	_c.check(float(w0[BalanceChest.TIER_WOOD]) > float(w0[BalanceChest.TIER_COPPER]),
		"木匣仍是主力档（寻宝流是加料，不是把场上全换成玉匣）")
	var w_hi: Array = GameBalance.chest_tier_weights(12.0, 0.0)
	_c.check(float(w_hi[BalanceChest.TIER_JADE]) > float(w0[BalanceChest.TIER_JADE])
		and float(w_hi[BalanceChest.TIER_COPPER]) > float(w0[BalanceChest.TIER_COPPER]),
		"宝箱品质↑ ⇒ 铜/玉权重同时↑（单调，不是换个词糊弄）")
	_c.equals(float(w_hi[BalanceChest.TIER_WOOD]), float(w0[BalanceChest.TIER_WOOD]),
		"抬高档靠加分子不靠削底子：木匣权重恒 100")
	var w_luck: Array = GameBalance.chest_tier_weights(0.0, 20.0)
	_c.check(float(w_luck[BalanceChest.TIER_JADE]) > float(w0[BalanceChest.TIER_JADE]),
		"福缘也抬玉匣（与悟道稀有度、货架档位同一把「缘」尺）")

	# 击数：定值，没有任何来源能砍它（2026-10-12 改版：这条腿换成抬兑现量）
	_c.equals(GameBalance.CHEST_BREAK_HITS, 3, "匣子固定挨 3 下砸开（基准档口径没被偷偷改掉）")

	# 开箱收益乘区：放大什么、不放大什么，两条例外要钉住
	var s1: Dictionary = GameBalance.chest_reward_scaled(GameBalance.chest_reward(BalanceChest.TIER_WOOD), 1.0)
	_c.equals(int(s1["gem_count"]), 3, "×1 就是表上那份：木匣仍掉 3 颗经验球")
	_c.near(float(s1["heal_pct"]), 0.15, 0.001, "×1 时葫芦仍回 15% 气血")
	var s2: Dictionary = GameBalance.chest_reward_scaled(GameBalance.chest_reward(BalanceChest.TIER_WOOD), 2.0)
	_c.equals(int(s2["gem_count"]), 6, "×2 ⇒ 经验球颗数翻倍")
	_c.near(float(s2["heal_pct"]), 0.30, 0.001, "×2 ⇒ 葫芦回复翻倍")
	_c.equals(int(s2["gem_exp"]), int(s1["gem_exp"]), "每颗经验球值多少经验不放大（不顺手吹经验曲线）")
	var s_cop: Dictionary = GameBalance.chest_reward_scaled(GameBalance.chest_reward(BalanceChest.TIER_COPPER), 2.0)
	_c.equals(int(s_cop["stones"]), 12, "×2 ⇒ 铜匣那笔金币翻倍")
	var s_cap: Dictionary = GameBalance.chest_reward_scaled(GameBalance.chest_reward(BalanceChest.TIER_COPPER), 9.0)
	_c.near(float(s_cap["heal_pct"]), GameBalance.CHEST_REWARD_HEAL_CAP, 0.001,
		"回复量有顶：堆满一条寻宝流也不许一口匣子回满血")
	var s_jade: Dictionary = GameBalance.chest_reward_scaled(GameBalance.chest_reward(BalanceChest.TIER_JADE), 2.0)
	_c.check(bool(s_jade["grant_item"]), "玉匣那件法宝是「必送」不是「送得多」，缩放不动它")
	var s_floor: Dictionary = GameBalance.chest_reward_scaled(GameBalance.chest_reward(BalanceChest.TIER_COPPER), 0.5)
	_c.equals(int(s_floor["stones"]), int(GameBalance.chest_reward(BalanceChest.TIER_COPPER)["stones"]),
		"乘区只抬不罚：字段被回退到 1.0 以下也不许把掉落砍下去")

	# 体型：档位递增（判定与精灵同乘这件事在现场层量）
	_c.check(GameBalance.chest_tier_scale(BalanceChest.TIER_WOOD)
		< GameBalance.chest_tier_scale(BalanceChest.TIER_JADE), "档位体型递增：玉匣看得出更大")

	# 奖励表：木匣与改版前逐字一致，玉匣才是要新增的东西
	var r0: Dictionary = GameBalance.chest_reward(BalanceChest.TIER_WOOD)
	_c.near(float(r0["heal_chance"]), 0.4, 0.001, "木匣基准档 40% 掉葫芦（原 60% 已下调）")
	_c.near(float(r0["heal_pct"]), 0.15, 0.001, "木匣葫芦仍回 15% 气血")
	_c.equals(int(r0["gem_count"]), 3, "木匣仍掉 3 颗金灵石")
	_c.check(not bool(r0["grant_item"]), "木匣不送法宝")
	var r1: Dictionary = GameBalance.chest_reward(BalanceChest.TIER_COPPER)
	_c.check(int(r1["gem_count"]) > int(r0["gem_count"]) and float(r1["heal_pct"]) > float(r0["heal_pct"]),
		"铜匣掉落比木匣厚（高档必须真的更好）")
	var r2: Dictionary = GameBalance.chest_reward(BalanceChest.TIER_JADE)
	_c.check(bool(r2["grant_item"]), "玉匣送法宝")
	_c.near(float(r2["heal_chance"]), 0.0, 0.001, "玉匣必掉灵石（磁吸那条链路因此可确定性判）")
	var fb: Dictionary = GameBalance.chest_jade_fallback_reward()
	_c.check(not bool(fb["grant_item"]), "送满上限后玉匣退回，不再白送法宝")
	_c.check(int(fb["gem_count"]) > int(r1["gem_count"]) and int(fb["stones"]) > int(r1["stones"]),
		"退回量比铜匣还厚：堆上去的档位不许越堆越亏")
	_c.equals(GameBalance.CHEST_JADE_ITEM_GRANT_CAP, 2, "每局玉匣最多送 2 件法宝（掏空灵石阁的保险丝）")

	# 危险度乘区：越难越稀少，顶档（噩梦）葫芦概率压到基准的 37.5%
	_c.near(GameBalance.danger_heal_chance_mult(0), 1.0, 0.001, "简单档乘区 = 1.0（基准）")
	_c.near(GameBalance.danger_heal_chance_mult(GameBalance.DANGER_MAX), 0.375, 0.001, "噩梦档乘区 = 0.375（0.4×0.375=0.15）")
	_c.check(GameBalance.danger_heal_chance_mult(GameBalance.DANGER_MAX) < GameBalance.danger_heal_chance_mult(0),
		"乘区随危险度单调递减")
	for d in range(GameBalance.DANGER_MAX):
		_c.check(GameBalance.danger_heal_chance_mult(d + 1) < GameBalance.danger_heal_chance_mult(d),
			"葫芦乘区档间严格递减 D%d→D%d" % [d, d + 1])
	_c.near(GameBalance.danger_heal_chance_mult(9), GameBalance.danger_heal_chance_mult(GameBalance.DANGER_MAX), 0.001,
		"危险度超档 clamp 到 DANGER_MAX，不溢出")
	_c.near(float(r0["heal_chance"]) * GameBalance.danger_heal_chance_mult(GameBalance.DANGER_MAX), 0.15, 0.001,
		"噩梦档木匣实掉葫芦概率 = 0.15")

# ---------------- 2+3) 来源层与现场层 ----------------

func _test_live() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().create_timer(2.0).timeout

	_spawner = GameManager.wave_spawner
	GameManager.player.max_health = 99999.0
	GameManager.player.current_health = 99999.0
	# 冻住波次状态机：不再刷怪也不结算，剩下的都是这条判据自己的匣子
	_spawner.phase = WaveSpawner.Phase.ALLOC

	await _test_sources_reach_spawner()
	await _test_count_delivery()
	await _test_reward_delivery()
	await _test_tier_geometry()
	await _test_jade_grants_item()
	await _test_jade_cap_fallback()
	await _test_magnet()

## 加点与法宝的幅度，真的走到「下一口匣子是什么样」上（字段追到运行时消费方）
func _test_sources_reach_spawner() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("qingyun_sword")
	await get_tree().create_timer(2.0).timeout
	_spawner = GameManager.wave_spawner
	_spawner.phase = WaveSpawner.Phase.ALLOC
	await _clear_chests()

	GameManager.apply_upgrade("chest_count_up")
	_c.equals(GameManager.chest_count_bonus, 1, "悟道「宝箱数量」落地到字段")
	GameManager.apply_upgrade("chest_reward_up")
	_c.near(GameManager.chest_reward_mult, 1.35, 0.001, "悟道「宝箱掉落」落地到乘区字段")
	GameManager.apply_upgrade("chest_quality_up")
	_c.near(GameManager.chest_quality, 2.0, 0.001, "悟道「宝箱品质」落地到字段")
	GameManager.add_item("cangbao_tu")
	_c.equals(GameManager.chest_count_bonus, 2, "法宝「藏宝图」与加点共用同一条字段链路")
	GameManager.add_item("manxia_jue")
	_c.near(GameManager.chest_reward_mult, 1.75, 0.001, "法宝「满匣诀」与加点共用同一条字段链路")

	_spawner._spawn_chests()
	await get_tree().process_frame
	var wave := _spawner.wave_number
	_c.equals(_chests().size(), GameBalance.chest_count(wave, 2),
		"设了加成 ⇒ 生产入口 _spawn_chests 真刷出这么多口（波 %d，实得 %d）" % [wave, _chests().size()])
	var any_chest: SpiritChest = _chests()[0]
	_c.equals(any_chest.max_hits, GameBalance.CHEST_BREAK_HITS,
		"匣子击数是定值（抬掉落不抬/不砍耐久，实得 %d）" % any_chest.max_hits)
	await _clear_chests()

## 数量兑现与硬顶：走生产入口，不读公式
func _test_count_delivery() -> void:
	GameManager.chest_count_bonus = 0
	GameManager.chest_reward_mult = 1.0   # 上一节把乘区堆到 1.75 了，这里回到基准档
	_spawner._spawn_chests()
	await get_tree().process_frame
	var base_n := _chests().size()
	_c.check(base_n > 0, "不吃加成也刷得出匣子（负对照：%d 口）" % base_n)
	await _clear_chests()

	GameManager.chest_count_bonus = 99
	_spawner._spawn_chests()
	await get_tree().process_frame
	_c.equals(_chests().size(), GameBalance.CHEST_COUNT_CAP,
		"加成爆表时按硬顶收（场地只有半场，再多就成箱子阵）")
	await _clear_chests()

## 开箱收益兑现：同一口铜匣在 ×1 与 ×2 两档下到账金币数必须不同（走砸开这条生产路径量）
## 铜匣那笔金币是确定性的（先入账，再掷掉落分支），所以拿它当尺子；
## 经验球颗数与葫芦二选一由 rng 决定，不在这里赌。
func _test_reward_delivery() -> void:
	GameManager.chest_reward_mult = 1.0
	var base_gain := await _break_copper_stones()
	var table := int(GameBalance.chest_reward(BalanceChest.TIER_COPPER)["stones"])
	_c.equals(base_gain, table, "不吃加成时铜匣到账就是表上那笔（+%d）" % base_gain)

	GameManager.chest_reward_mult = 2.0
	var boosted := await _break_copper_stones()
	_c.equals(boosted, table * 2, "宝箱掉落 ×2 ⇒ 同一口铜匣到账翻倍（%d → %d）" % [base_gain, boosted])

	GameManager.chest_reward_mult = 1.0

## 砸开一口铜匣，返回这一口给GameManager加了几枚金币
func _break_copper_stones() -> int:
	var chest := _make_chest(BalanceChest.TIER_COPPER)
	await get_tree().process_frame
	var before := GameManager.spirit_stones
	_break(chest)
	await get_tree().process_frame
	var gain := GameManager.spirit_stones - before
	await _clear_chests()
	return gain

## 档位与判定同源：玉匣的判定圆确实比木匣大，且就是公式那个数
func _test_tier_geometry() -> void:
	GameManager.chest_count_bonus = 0
	GameManager.chest_quality = 0.0
	var wood := _make_chest(BalanceChest.TIER_WOOD)
	var jade := _make_chest(BalanceChest.TIER_JADE)
	await get_tree().process_frame

	var r_wood := _radius_of(wood)
	var r_jade := _radius_of(jade)
	_c.near(r_wood, 17.0 * SpiritChest.SIZE_MULT * GameBalance.chest_tier_scale(BalanceChest.TIER_WOOD),
		0.01, "木匣判定圆 == 体型公式（画多大 == 判多大）")
	_c.near(r_jade, 17.0 * SpiritChest.SIZE_MULT * GameBalance.chest_tier_scale(BalanceChest.TIER_JADE),
		0.01, "玉匣判定圆跟着档位同倍放缩，不是只把图放大")
	_c.check(r_jade > r_wood, "玉匣判定确实更大（实得 %.1f vs %.1f）" % [r_jade, r_wood])

	wood.queue_free()
	jade.queue_free()
	await get_tree().process_frame

## 玉匣砸开 = 真的多一件法宝，且金币与灵石一起到账
func _test_jade_grants_item() -> void:
	GameManager.chest_item_grants = 0
	var items_before := GameManager.items.size()
	var stones_before := GameManager.spirit_stones
	var gems_before := _gem_ids()

	var jade := _make_chest(BalanceChest.TIER_JADE)
	await get_tree().process_frame
	_break(jade)
	await get_tree().process_frame

	_c.equals(GameManager.items.size(), items_before + 1, "玉匣砸开真的多了一件法宝（不是只发了个公告）")
	_c.equals(GameManager.chest_item_grants, 1, "送出的件数记了账")
	_c.check(GameManager.spirit_stones >= stones_before + int(GameBalance.chest_reward(BalanceChest.TIER_JADE)["stones"]),
		"玉匣另给的那笔金币到账（+%d）" % (GameManager.spirit_stones - stones_before))
	_c.check(_new_gem_count(gems_before) > 0, "玉匣必掉灵石这条兑现了（新出现 %d 颗）" % _new_gem_count(gems_before))

## 送满上限之后不许空响一炮：不送法宝，但退回奖励照样落地
func _test_jade_cap_fallback() -> void:
	GameManager.chest_item_grants = GameBalance.CHEST_JADE_ITEM_GRANT_CAP
	var items_before := GameManager.items.size()
	var gems_before := _gem_ids()
	var jade := _make_chest(BalanceChest.TIER_JADE)
	await get_tree().process_frame
	_break(jade)
	await get_tree().process_frame

	_c.equals(GameManager.items.size(), items_before, "送满上限后玉匣不再白送法宝")
	_c.check(_new_gem_count(gems_before) > 0 or _heal_count() > 0,
		"退回奖励仍然落地：场上出现灵石或葫芦，不是砸开啥都没有")

## 磁吸：关掉留在原地，开了当场飞向玩家 —— 两种状态读数必须不同，否则这条判据是空的
func _test_magnet() -> void:
	GameManager.chest_count_bonus = 0
	var c1 := _make_chest(BalanceChest.TIER_WOOD)
	await get_tree().process_frame
	var before1 := _gem_ids()
	c1._drop_gems(2, 5)
	await get_tree().process_frame
	var pulled_off := _new_gems_pulled(before1)
	var n_off := _new_gem_count(before1)
	_c.check(n_off > 0 and pulled_off == 0,
		"没有纳灵盘：掉出的灵石留在原地（%d 颗，%d 颗被吸）" % [n_off, pulled_off])
	c1.queue_free()

	GameManager.add_item("naling_zhuo")
	_c.check(GameManager.item_hook_sum("chest_magnet") > 0.0, "纳灵盘的机制字段被 item_hook_sum 读到")
	var c2 := _make_chest(BalanceChest.TIER_WOOD)
	await get_tree().process_frame
	var before2 := _gem_ids()
	c2._drop_gems(2, 5)
	await get_tree().process_frame
	var n_on := _new_gem_count(before2)
	var pulled_on := _new_gems_pulled(before2)
	_c.check(n_on > 0 and pulled_on == n_on,
		"持有纳灵盘：掉出的灵石当场全部飞向玩家（%d/%d）" % [pulled_on, n_on])
	c2.queue_free()
	await _clear_chests()

# ---------------- 小工具 ----------------

func _chests() -> Array:
	return get_tree().get_nodes_in_group("chests")

func _clear_chests() -> void:
	for ch in _chests():
		(ch as SpiritChest).dying = true
		ch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _make_chest(tier: int) -> SpiritChest:
	var chest := SpiritChest.new()
	# tier 必须在 add_child 之前写好：_ready 靠它定贴图/体型/击数/配色
	chest.tier = tier
	chest.global_position = GameManager.player.global_position + Vector2(80.0, 0.0)
	_spawner.get_parent().add_child(chest)
	return chest

## 一直喂"一下"直到砸开：耐久按几下计，与伤害数值无关（99999 也只是一下）
func _break(chest: SpiritChest) -> void:
	var guard := 0
	while is_instance_valid(chest) and not chest.dying and guard < 20:
		chest.take_damage(99999.0, Vector2.RIGHT)
		guard += 1

func _radius_of(chest: SpiritChest) -> float:
	## 匣子的碰撞盒是纯代码建的（节点名是 @Area2D@N），只能按类型遍历取
	for child in chest.get_children():
		if child is Area2D:
			for sub in (child as Node).get_children():
				if sub is CollisionShape2D and (sub as CollisionShape2D).shape is CircleShape2D:
					return ((sub as CollisionShape2D).shape as CircleShape2D).radius
	return -1.0

func _gem_ids() -> Dictionary:
	var out := {}
	for g in get_tree().get_nodes_in_group("gems"):
		out[g.get_instance_id()] = g
	return out

func _new_gem_count(before: Dictionary) -> int:
	var n := 0
	for g in get_tree().get_nodes_in_group("gems"):
		if not before.has(g.get_instance_id()):
			n += 1
	return n

## 新掉出来的灵石里有几颗已经被指派了吸附目标
func _new_gems_pulled(before: Dictionary) -> int:
	var n := 0
	for g in get_tree().get_nodes_in_group("gems"):
		if before.has(g.get_instance_id()):
			continue
		if g.get("target_player") != null:
			n += 1
	return n

func _heal_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("gems"):
		if node is HealOrb:
			n += 1
	return n

# ---------------- 反例自检 ----------------

func _run_selftest() -> void:
	# ① 旧数量口径：恒 mini(2+wave/6,4)，不吃「宝箱数量」加成
	var old_count := mini(2 + int(1.0 / 6.0), 4)
	_c.check(old_count != GameBalance.chest_count(1, 3),
		"反例①成立：旧数量口径（恒 %d 口）会被「设了 +3 就该刷 5 口」抓住" % old_count)
	# ② 旧档位：只有木匣一档
	var flat: Array[float] = [100.0, 0.0, 0.0]
	_c.check(not (flat[BalanceChest.TIER_COPPER] > 0.0 and flat[BalanceChest.TIER_JADE] > 0.0),
		"反例②成立：铜/玉权重为 0 的旧写法会被「品质为 0 也见得到高档匣」抓住")
	# ③ 旧写法：掉落按档位表原样发，不吃「宝箱掉落」乘区
	var old_drop := GameBalance.chest_reward(BalanceChest.TIER_COPPER)
	var new_drop := GameBalance.chest_reward_scaled(old_drop, 2.0)
	_c.check(int(old_drop["stones"]) != int(new_drop["stones"]),
		"反例③成立：不吃乘区的旧写法（两档同值 %d）会被「×2 ⇒ 到账翻倍」抓住" % int(old_drop["stones"]))
	# ④ 奖励表没有 grant_item 时，玉匣送法宝那条判据无从成立
	_c.check(not GameBalance.chest_reward(BalanceChest.TIER_WOOD).get("grant_item", false)
		and bool(GameBalance.chest_reward(BalanceChest.TIER_JADE).get("grant_item", false)),
		"反例④成立：判据认的是「只有玉匣带 grant_item」，两档都带或都不带都会红")
	# ⑤ 磁吸判据的形状：关/开同值即空转
	_c.check(0 != 2, "反例⑤成立：磁吸判据要求两种状态读数不同（同值时这条会红）")
