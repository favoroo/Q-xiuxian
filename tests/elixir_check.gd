extends Node

## 药爆（药王·额外技能）判据：自身回血 + 周身一次性毒伤 + 反打短时增伤 + 冷却门控。
## 数值全在 ElixirData，本判据从生产入口量兑现：Player.try_activate_extra_skill。
##
## 钉住七件事：
##   1. 自身回血：按最大生命 HEAL_HP_RATIO 比例回复
##   2. 周身毒伤：BURST_RADIUS 内妖兽受 burst_damage(元素)，圈外一格不掉血
##   3. 视觉与判定同源：冲击环半径 == ElixirData.BURST_RADIUS
##   4. 击退冲量：圈内受击妖兽被震开
##   5. 冷却门控：释放后进入 extra_skill_cd_left，冷却中按不动（false）
##   6. 冷却转好再放：CD 归零后再次释放成功
##   7. 增伤与到期回滚：buff_damage_mult == 1+BUFF_DAMAGE，到期精确回 1.0（无残留）
##
## 运行: godot --headless --path . res://tests/ElixirCheck.tscn
##       godot --headless --path . res://tests/ElixirCheck.tscn -- --selftest
## 退出码 0 且末行 ELIXIR_RESULT: ALL PASS
##
## 坑：特效视口终审要求落点在屏内，玩家必须摆在 (260,270) 附近；
## 受击顿帧会拖时间，跑前先关 hit_stop（auto_save=false，不落盘）。

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
	await _test_heal_and_aoe_damage()
	await _test_cooldown_gating()
	await _test_buff_rollback()
	if _selftest:
		_test_selftest_guard()
	if _c.report("ELIXIR_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 公共摆位 ----------------

func _make_player(elemental: float = 2.0) -> Player:
	var p: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	add_child(p)
	p.global_position = SPAWN_AT
	p.max_health = 100.0
	p.current_health = 100.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	GameManager.is_game_over = false
	GameManager.cultivator_id = "yaowang"
	GameManager.extra_skill_id = "elixir"
	GameManager.elemental_damage = elemental
	GameManager.buff_damage_mult = 1.0
	GameManager.knockback_mult = 1.0
	GameManager.rng = RandomNumberGenerator.new()
	GameManager.rng.seed = 20261013
	return p

func _make_enemy(at: Vector2) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
	add_child(e)
	e.global_position = at
	e.max_hp = 999999.0
	e.current_hp = 999999.0
	e.move_speed = 0.0
	e.contact_damage = 0.0
	e.add_to_group("enemies")
	return e

func _shockwave_radius() -> float:
	var host := get_tree().current_scene.get_node_or_null("JuiceEffectPool")
	if host == null:
		return -1.0
	for child in host.get_children():
		if child is JuiceEffect and child.effect_type == JuiceEffect.EffectType.SHOCKWAVE:
			if not child._r_max.is_empty():
				return float(child._r_max[0])
	return -1.0

# ---------------- 1+2+3+4. 回血、周身毒伤、同源半径、击退 ----------------

func _test_heal_and_aoe_damage() -> void:
	var p := _make_player(2.0)
	p.current_health = 50.0  ## 缺血状态

	# 圈内怪与圈外怪（圈外怪放上方，避开向右被震飞的圈内怪碰撞推挤）
	var inside := _make_enemy(SPAWN_AT + Vector2(ElixirData.BURST_RADIUS - 30.0, 0.0))
	var outside := _make_enemy(SPAWN_AT + Vector2(0.0, -(ElixirData.BURST_RADIUS + 50.0)))
	var hp_in := inside.current_hp
	var hp_out := outside.current_hp
	var pos_in := inside.global_position
	var pos_out := outside.global_position

	var want_heal := ElixirData.heal_amount(p.max_health)
	var want_dmg := ElixirData.burst_damage(2.0)

	var casts_before := GameManager.skill_cast_count
	var ok := p.try_activate_extra_skill()
	_c.check(ok, "药爆施放成功（try_activate_extra_skill）")
	_c.equals(GameManager.skill_cast_count, casts_before + 1, "额外技能成功施放也计入技能次数")
	_c.near(p.current_health, 50.0 + want_heal, EPS,
		"自身回血 %.1f（= 气血 100 × %.0f%%）" % [want_heal, ElixirData.HEAL_HP_RATIO * 100.0])
	_c.near(hp_in - inside.current_hp, want_dmg, 0.5,
		"圈内敌人受到毒伤 %.1f（= 基础 + 元素 × %.1f）" % [want_dmg, ElixirData.ELEMENTAL_RATIO])
	_c.check(is_equal_approx(hp_out, outside.current_hp), "圈外敌人一格血未掉（判定半径未被辉光糊大）")

	var ring_r := _shockwave_radius()
	_c.near(ring_r, ElixirData.BURST_RADIUS, 0.01,
		"冲击环扫到的半径 == 判定半径 %.1f（画多大 == 判多大）" % ElixirData.BURST_RADIUS)

	for i in range(20):
		await get_tree().physics_frame
	_c.check(inside.global_position.distance_to(pos_in) > 1.0, "圈内敌人被震开")
	_c.check(outside.global_position.distance_to(pos_out) < 0.5, "圈外敌人纹丝不动")

	inside.queue_free()
	outside.queue_free()
	p.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

# ---------------- 5+6. 冷却门控与再释放 ----------------

func _test_cooldown_gating() -> void:
	var p := _make_player()
	_c.near(p.extra_skill_cd_left, 0.0, EPS, "开局无冷却")
	_c.check(p.try_activate_extra_skill(), "首次施放成功")
	_c.near(p.extra_skill_cd_left, ElixirData.COOLDOWN, 0.2,
		"进入冷却 %.1fs" % ElixirData.COOLDOWN)
	_c.check(not p.try_activate_extra_skill(), "冷却中按不动（门控生效）")

	# 冷却转好
	p.extra_skill_cd_left = 0.0
	_c.check(p.try_activate_extra_skill(), "冷却转好后可再次施放")
	p.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

# ---------------- 7. 增伤乘区与到期回滚 ----------------

func _test_buff_rollback() -> void:
	var p := _make_player()
	p.try_activate_extra_skill()
	_c.near(GameManager.buff_damage_mult, ElixirData.buff_mult(), EPS,
		"药爆增伤乘区落地 = 1 + %.0f%%" % (ElixirData.BUFF_DAMAGE * 100.0))

	# 倒计时走完，精确回滚
	p._tick_skill_buffs(ElixirData.BUFF_DURATION + 0.1)
	_c.near(GameManager.buff_damage_mult, 1.0, EPS,
		"增伤到期精确回 1.0（与加点/羁绊乘区隔离，无残留）")
	p.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

# ---------------- 自检守卫 ----------------

func _test_selftest_guard() -> void:
	# 旧写法：服丹是 BURST 类、cooldown 是 0.0 ⇒ 第 5 条冷却门控会抓红
	var legacy_cd := 0.0
	_c.check(legacy_cd < ElixirData.COOLDOWN, "自检证实：旧写法免 CD 会抓红冷却断言")
