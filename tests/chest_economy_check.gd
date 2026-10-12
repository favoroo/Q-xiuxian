extends Node

## 藏宝匣「寻宝流」经济链路判据（2026-10-11）
##
## 用户口径：「针对宝箱再加些玩法，在技能加点或商店里加物品，提高刷宝箱的数量和概率」。
## 这条链路横跨 数据表 → 属性字段 → 刷怪口 → 匣子本体 → 掉落兑现，任何一环写歪都会变成
## 「卡面上写了 +1，场上还是 2 口」的假加成（历史上这类静默无效踩过多次），所以判据分三层，
## 每一层都从**生产入口**进去量，不在测试里另算一套：
##
## 1) 纯函数层（BalanceChest 经 GameBalance 门面）：数量曲线与硬顶、三档权重的单调与
##    「品质为 0 时铜/玉仍有正权重」（第 1 波就该见到高档匣）、击数地板、
##    奖励表与改版前木匣口径一致（防偷偷改掉基准档）。
## 2) 来源层：apply_upgrade / add_item 走真实落地链路后，GameManager 字段确实吃到幅度，
##    并且下一次 _spawn_chests 刷出的匣子数、击数、体型就是那些幅度（字段追到消费方）。
## 3) 现场层：Main 场景 + start_run，冻住波次状态机，量
##    刷出口数 / 上限 / 档位判定半径与体型同源 / 玉匣真多一件法宝 / 送满上限后退回仍有掉落 /
##    纳灵盘开与关时掉出的灵石 target_player 不同（磁吸真的接上了）。
##
## 运行: godot --headless --path . res://tests/ChestEconomyCheck.tscn
##       godot --headless --path . res://tests/ChestEconomyCheck.tscn -- --selftest
##
## 反例（--selftest 逐条钉住，证明上面三层不是白给的）：
##   ① 旧数量口径恒 mini(2+wave/6,4)，不吃加成 ⇒ 与「设了 +3 就该刷 5 口」这条判据冲突；
##   ② 旧代码只有木匣一档（铜/玉权重 0）⇒ 「品质为 0 也见得到高档匣」这条会红；
##   ③ 旧击数恒 GameBalance.CHEST_BREAK_HITS，不随「开箱省力」变 ⇒ 击数判据会红；
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

	# 击数：曲线与地板
	_c.equals(GameBalance.chest_break_hits(0), GameBalance.CHEST_BREAK_HITS, "不吃加成时仍是 3 下")
	_c.equals(GameBalance.chest_break_hits(1), 2, "开箱省力 +1 ⇒ 2 下")
	_c.equals(GameBalance.chest_break_hits(2), 1, "开箱省力 +2 ⇒ 1 下")
	_c.equals(GameBalance.chest_break_hits(9), GameBalance.CHEST_MIN_HITS,
		"击数有地板：再多的省力也不会把「砸」这个动作抹掉")

	# 体型：档位递增（判定与精灵同乘这件事在现场层量）
	_c.check(GameBalance.chest_tier_scale(BalanceChest.TIER_WOOD)
		< GameBalance.chest_tier_scale(BalanceChest.TIER_JADE), "档位体型递增：玉匣看得出更大")

	# 奖励表：木匣与改版前逐字一致，玉匣才是要新增的东西
	var r0: Dictionary = GameBalance.chest_reward(BalanceChest.TIER_WOOD)
	_c.near(float(r0["heal_chance"]), 0.6, 0.001, "木匣仍约六成掉葫芦（基准档口径没漂）")
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
	GameManager.apply_upgrade("chest_break_up")
	_c.equals(GameManager.chest_break_bonus, 1, "悟道「开箱省力」落地到字段")
	GameManager.apply_upgrade("chest_quality_up")
	_c.near(GameManager.chest_quality, 2.0, 0.001, "悟道「宝箱品质」落地到字段")
	GameManager.add_item("cangbao_tu")
	_c.equals(GameManager.chest_count_bonus, 2, "法宝「藏宝图」与加点共用同一条字段链路")

	_spawner._spawn_chests()
	await get_tree().process_frame
	var wave := _spawner.wave_number
	_c.equals(_chests().size(), GameBalance.chest_count(wave, 2),
		"设了加成 ⇒ 生产入口 _spawn_chests 真刷出这么多口（波 %d，实得 %d）" % [wave, _chests().size()])
	var any_chest: SpiritChest = _chests()[0]
	_c.equals(any_chest.max_hits, GameBalance.chest_break_hits(1),
		"新刷出的匣子击数就是「开箱省力」之后的值（实得 %d）" % any_chest.max_hits)
	await _clear_chests()

## 数量兑现与硬顶：走生产入口，不读公式
func _test_count_delivery() -> void:
	GameManager.chest_count_bonus = 0
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
	# ③ 旧击数：不随加成变
	_c.check(GameBalance.CHEST_BREAK_HITS != GameBalance.chest_break_hits(2),
		"反例③成立：击数恒 3 的旧写法会被「开箱省力 +2 ⇒ 1 下」抓住")
	# ④ 奖励表没有 grant_item 时，玉匣送法宝那条判据无从成立
	_c.check(not GameBalance.chest_reward(BalanceChest.TIER_WOOD).get("grant_item", false)
		and bool(GameBalance.chest_reward(BalanceChest.TIER_JADE).get("grant_item", false)),
		"反例④成立：判据认的是「只有玉匣带 grant_item」，两档都带或都不带都会红")
	# ⑤ 磁吸判据的形状：关/开同值即空转
	_c.check(0 != 2, "反例⑤成立：磁吸判据要求两种状态读数不同（同值时这条会红）")
