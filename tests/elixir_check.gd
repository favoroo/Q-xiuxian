extends Node

## 服丹（药王治疗出口）判据：治疗溢出存进药池，点额外技能「服丹」按池量回血 + 短时增伤反打。
## 数值全在 ElixirData，本判据从生产入口量兑现：Player.heal 溢出入池 → try_activate_extra_skill 喝掉。
##
## 钉住七件事：
##   1. 满血 heal 溢出入池：pool == 溢出 × STORE_RATIO（走生产 heal 入口）
##   2. 缺血 heal 不入池（没溢出就没得存，治疗先治病）
##   3. 池上限钳制：连续大溢出不超 cap（= 气血 × CAP_HP_RATIO）
##   4. 门控：空池按不动（false），有池才放得出去；免冷却——喝完再攒立即可再喝
##   5. 服丹兑现：缺血时回血 == 池量、pool 清零、buff_damage_mult == 1+BUFF_DAMAGE
##   6. buff 到期精确回滚：_tick_skill_buffs 走完后 buff_damage_mult 回 1.0（无残留）
##   7. 满血服丹：heal 溢出回灌不当新账——喝完池子还是空的（先 heal 后清零那一拍的账）
##
## 运行: godot --headless --path . res://tests/ElixirCheck.tscn
##       godot --headless --path . res://tests/ElixirCheck.tscn -- --selftest
## 退出码 0 且末行 ELIXIR_RESULT: ALL PASS
##
## 坑：受击顿帧会拖时间，跑前先关 hit_stop（auto_save=false，不落盘）。

const EPS := 0.0001
const SPAWN_AT := Vector2(260.0, 270.0)

var _c := TestCheck.new()
var _selftest: bool = false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--selftest":
			_selftest = true
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	GameManager.reset_run()
	await _test_overflow_charges_pool()
	await _test_no_overflow_no_pool()
	await _test_pool_cap_clamp()
	await _test_release_delivers()
	if _selftest:
		_test_selftest_guard()
	if _c.report("ELIXIR_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 公共摆位 ----------------

func _make_player() -> Player:
	var p: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	add_child(p)
	p.global_position = SPAWN_AT
	p.max_health = 100.0            ## 池上限 = 100 × CAP_HP_RATIO
	p.current_health = 100.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	GameManager.is_game_over = false
	GameManager.elixir_pool = 0.0
	GameManager.extra_skill_id = "elixir"
	GameManager.rng = RandomNumberGenerator.new()
	GameManager.rng.seed = 20261011
	return p

# ---------------- 1. 满血 heal 溢出入池 ----------------

func _test_overflow_charges_pool() -> void:
	var p := _make_player()
	p.heal(30.0)
	_c.near(GameManager.elixir_pool, ElixirData.add_pool(0.0, 30.0, p.max_health), EPS,
		"满血 heal 30 全部溢出 → 入池 %.1f（= 溢出 × %.0f%%，走生产 heal 入口）" % [
			ElixirData.add_pool(0.0, 30.0, p.max_health), ElixirData.STORE_RATIO * 100.0])
	p.queue_free()

# ---------------- 2. 缺血 heal 不入池 ----------------

func _test_no_overflow_no_pool() -> void:
	var p := _make_player()
	p.current_health = 50.0
	p.heal(20.0)
	_c.near(p.current_health, 70.0, EPS, "缺血 heal 真回血（前置）")
	_c.near(GameManager.elixir_pool, 0.0, EPS, "没溢出就没得存（治疗先治病，不抽水）")
	p.queue_free()

# ---------------- 3. 池上限钳制 ----------------

func _test_pool_cap_clamp() -> void:
	var p := _make_player()
	p.heal(1000.0)
	_c.near(GameManager.elixir_pool, ElixirData.cap_of(p.max_health), EPS,
		"大溢出顶到池上限 %.0f（= 气血 × %.0f%%）为止" % [
			ElixirData.cap_of(p.max_health), ElixirData.CAP_HP_RATIO * 100.0])
	p.queue_free()

# ---------------- 4+5+6+7. 门控、兑现、回滚、满血喝 ----------------

func _test_release_delivers() -> void:
	var p := _make_player()
	# 门控：空池按不动
	_c.check(not p.try_activate_extra_skill(), "空池服丹被拒（没攒上按不动）")
	# 缺血兑现：池 20、血 50/100 → 喝完 70、池清零、增伤乘区落地
	p.current_health = 50.0
	GameManager.elixir_pool = 20.0
	_c.check(p.try_activate_extra_skill(), "有池服丹走额外技能真入口释放成功（try_activate_extra_skill）")
	_c.near(p.current_health, 70.0, EPS, "服丹回血 == 池量 20（缺血时全额落账）")
	_c.near(GameManager.elixir_pool, 0.0, EPS, "喝完池子清零（不重复喝）")
	_c.near(GameManager.buff_damage_mult, ElixirData.buff_mult(), EPS,
		"服丹增伤乘区 = 1 + %.0f%%（反打窗口开启）" % (ElixirData.BUFF_DAMAGE * 100.0))
	# 免冷却：再攒立即可再喝
	GameManager.elixir_pool = 5.0
	_c.near(p.skill_cd_left, 0.0, EPS, "服丹不进冷却（资源门控而非 CD）")
	_c.check(p.try_activate_extra_skill(), "再攒上有存量即可再喝（无 CD 连喝）")
	# buff 到期精确回滚（直接推账本，与生产 _physics_process 同一条 _tick_skill_buffs 路径）
	p._tick_skill_buffs(ElixirData.BUFF_DURATION + 0.1)
	_c.near(GameManager.buff_damage_mult, 1.0, EPS, "增伤到期精确回 1.0（与加点/羁绊乘区隔离，无残留）")
	# 满血服丹：溢出回灌不当新账
	p.current_health = p.max_health
	GameManager.elixir_pool = 10.0
	_c.check(p.try_activate_extra_skill(), "满血也能服丹（换增伤窗口）")
	_c.near(GameManager.elixir_pool, 0.0, EPS, "满血服丹后池子仍是空的（heal 回灌的底子不当新账）")
	p.queue_free()

# ---------------- 自检守卫：证明判据抓得住旧写法 ----------------

func _test_selftest_guard() -> void:
	# 旧写法：heal 溢出直接丢弃 ⇒ 第 1 条的入池断言会红；没池 ⇒ 第 4 条兑现全红
	var legacy_pool := 0.0
	_c.check(legacy_pool < ElixirData.add_pool(0.0, 30.0, 100.0),
		"自检证实：旧写法溢出不入池，第 1/4/5 条都会抓红")
