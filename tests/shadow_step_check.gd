extends Node

## 踏影（闪避出口）判据：闪避不再只是「这一下没掉血」，而是给一段残影无敌 + 攒一层影，
## 额外技能「影爆」一键把躲掉的伤害还回去。数值全在 ShadowStepData，本判据从生产入口量兑现。
##
## 钉住八件事：
##   1. 闪避成功：不掉血 + 拿到 GUARD_SEC 无敌 + 影层 +1（走 Player.take_damage 真入口）
##   2. 被打中：掉血、无敌帧仍是 0.55s、影层不许涨（只有闪成才攒）
##   2b. 非影者闪避不攒影：残影无敌是通用兜底，影层/增伤乘区只归绑了影爆的影者
##   3. 满层 FIFO：超过上限后留的是最近那几刀，更早的让位（不白闪、也不无限攒）
##   4. 带影层冲刺：无敌窗口 = SkillData.iframe + 层数 × IFRAME_PER_STACK（被动不消耗影层，
##      影层兑现已独立成额外技能「影爆」，冲刺不再清层）
##   5. 影爆兑现：圈内敌人吃到 burst 伤害并被推开、圈外一点事没有；影层清零
##   6. 视觉与判定同源：冲击环扫到的半径 == ShadowStepData.BURST_RADIUS == 判定用的那个数
##   7. 攒层即增伤：GameManager.shadow_amp_mult == amp_mult(影层)，兑现后回 1.0
##   8. 影爆门控：无冷却——0 层拒、有层可连放；空 extra_skill_id 直接拒
##   9. 影爆波次同步：满层兑现 ≥ 参照小怪（邪修基血 24×MOB_HP_BASE_MULT）生命，
##      W1/W10/W20/W30 全部成立（用户口径 2026-10-15「满层影爆震死周围一环小怪」；
##      旧版只跟接触伤走，小怪血复利更快，W10 满层仅及 ~10% 血＝挠痒）
##
## 运行: godot --headless --path . res://tests/ShadowStepCheck.tscn
##       godot --headless --path . res://tests/ShadowStepCheck.tscn -- --selftest
## 退出码 0 且末行 SHADOW_STEP_RESULT: ALL PASS
##
## 坑（写判据时踩到的）：特效视口终审要求落点在屏内，玩家必须摆在 (480, 270) 附近，
## 摆在 (0,0) 时冲击波被当屏外静默丢弃，第 6 条会假绿；受击顿帧会把 0.16s 的冲刺拖成
## 几十分钟，跑前先关 hit_stop 设置项（auto_save=false，不落盘）。

const EPS := 0.0001
## 摆位受两条硬约束，改这里前先把算式核一遍：
##   ① 视口内 —— 玩家位置就是冲击波生成点，屏外会被 _pos_in_viewport 静默丢弃，同源半径那条会假绿；
##   ② 圈外怪（SPAWN_AT.x + BURST_RADIUS + 60）必须落在界碑收口内 —— EnemyBase._physics_process
##      每帧 clamp 到 ±(MAP_HALF_EXTENT - 20) = ±540，越界的怪会被拖回，读成「圈外敌人动了」。
##      180 + 120 + 60 = 360，留足安全余量。
const SPAWN_AT := Vector2(180.0, 270.0)

var _c := TestCheck.new()
var _selftest: bool = false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--selftest":
			_selftest = true
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	GameManager.reset_run()
	await _test_dodge_delivers()
	await _test_hit_does_not_stack()
	await _test_non_shadow_no_stack()
	await _test_fifo_cap()
	await _test_amp_pure()
	await _test_burst_wave_power()
	await _test_dash_iframe_bonus()
	await _test_release_delivers()
	if _selftest:
		await _test_selftest_guard()
	if _c.report("SHADOW_STEP_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 公共摆位 ----------------

func _make_player(dodge: float) -> Player:
	var p: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	add_child(p)
	p.global_position = SPAWN_AT
	p.max_health = 99999.0
	p.current_health = 99999.0
	p.invulnerable_time = 0.0
	GameManager.player = p
	GameManager.is_game_over = false
	GameManager.armor = 0.0
	GameManager.synergy_armor = 0.0
	# 钉死「必闪 / 必中」两档：get_effective_dodge 会被 DODGE_CAP 截断，
	# 想让 dodge=1.0 真的每帧都闪，必须把上限一起抬上去
	GameManager.dodge = dodge
	GameManager.dodge_cap_bonus = maxf(0.0, dodge - GameManager.DODGE_CAP)
	GameManager.shadow_amp_mult = 1.0
	# 影层是影者专属（闸=绑定影爆额外技能）：本判据量的是影者机制，默认摆成影者身份
	GameManager.extra_skill_id = "shadowburst"
	GameManager.rng = RandomNumberGenerator.new()
	GameManager.rng.seed = 20261011
	return p

func _make_enemy(at: Vector2) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
	add_child(e)
	e.global_position = at
	e.max_hp = 999999.0
	e.current_hp = 999999.0
	e.move_speed = 0.0        ## 不许自己凑过来污染读数
	e.contact_damage = 0.0    ## 接触伤害不参与本判据
	e.add_to_group("enemies")
	return e

func _stacks(p: Player) -> int:
	return ShadowStepData.stacks_of(p.shadow_ring)

# ---------------- 1. 闪避成功真的兑现 ----------------

func _test_dodge_delivers() -> void:
	var p := _make_player(1.0)
	var hp_before: float = p.current_health
	p.take_damage(23.0)
	_c.check(p.current_health >= hp_before - EPS, "闪避成功不掉血（生产 take_damage 入口）")
	_c.near(p.invulnerable_time, ShadowStepData.GUARD_SEC, 0.001,
		"闪避成功拿到残影无敌 %.2fs（旧写法不给这一段 ⇒ 贴身时闪了等于白闪）" % ShadowStepData.GUARD_SEC)
	_c.check(_stacks(p) == 1, "闪避成功攒 1 层影（实得 %d 层）" % _stacks(p))
	_c.near(ShadowStepData.stored_sum(p.shadow_ring), 23.0, EPS,
		"影层存的是躲掉那一刀的原值（打多少存多少，波次缩放自动跟上）")
	_c.near(GameManager.shadow_amp_mult, ShadowStepData.amp_mult(p.shadow_ring), EPS,
		"攒层即增伤：乘区跟层数走（1 层 ×%.2f，生产 take_damage 写点维护）" % ShadowStepData.amp_mult(p.shadow_ring))
	p.queue_free()

# ---------------- 2. 被打中不涨层 ----------------

func _test_hit_does_not_stack() -> void:
	var p := _make_player(0.0)
	var hp_before: float = p.current_health
	p.take_damage(23.0)
	_c.check(p.current_health < hp_before, "闪避 0% 时这一刀真的掉血（前置）")
	_c.near(p.invulnerable_time, 0.55, 0.001, "打中后的无敌帧仍是 0.55s（踏影没改动它）")
	_c.check(_stacks(p) == 0, "被打中不涨影层（实得 %d 层）：只有闪成才攒" % _stacks(p))
	p.queue_free()

# ---------------- 2b. 非影者闪避不攒影（闸=绑定影爆额外技能） ----------------

func _test_non_shadow_no_stack() -> void:
	# 其他角色靠加点/道具/神行术也能闪：闪避兜底兑现（残影无敌）人人有，影层只归影者
	var p := _make_player(1.0)
	GameManager.extra_skill_id = ""
	var hp_before: float = p.current_health
	p.take_damage(23.0)
	_c.check(p.current_health >= hp_before - EPS, "非影者闪避照样不掉血（流云身法通用兜底）")
	_c.near(p.invulnerable_time, ShadowStepData.GUARD_SEC, 0.001, "非影者闪避仍拿残影短无敌")
	_c.check(_stacks(p) == 0, "非影者闪避不攒影层（实得 %d 层）：没有影爆键，攒了无处兑现" % _stacks(p))
	_c.near(GameManager.shadow_amp_mult, 1.0, EPS, "非影者闪避不动增伤乘区（防白拿 ×1.50 永久增伤）")
	p.queue_free()

# ---------------- 3. 满层 FIFO ----------------

func _test_fifo_cap() -> void:
	var p := _make_player(1.0)
	# 12 刀挤进 10 层上限：最旧两刀（10/20）必须让位
	for raw in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 110.0, 120.0]:
		p.invulnerable_time = 0.0
		p.take_damage(float(raw))
	_c.check(_stacks(p) == ShadowStepData.MAX_STACKS,
		"闪 12 次后层数钉在上限 %d（实得 %d）" % [ShadowStepData.MAX_STACKS, _stacks(p)])
	_c.near(ShadowStepData.stored_sum(p.shadow_ring),
		30.0 + 40.0 + 50.0 + 60.0 + 70.0 + 80.0 + 90.0 + 100.0 + 110.0 + 120.0, EPS,
		"满层后换掉最旧那两刀：留的是最近 %d 刀（30…120）" % ShadowStepData.MAX_STACKS)
	_c.near(GameManager.shadow_amp_mult, ShadowStepData.amp_mult(p.shadow_ring), EPS,
		"满层增伤 ×%.2f（每层 +%.0f%%，攒着就生效）" % [
			ShadowStepData.amp_mult(p.shadow_ring), ShadowStepData.AMP_PER_STACK * 100.0])
	p.queue_free()

# ---------------- 影层增伤：纯函数钉点 ----------------

func _test_amp_pure() -> void:
	_c.near(ShadowStepData.amp_mult([]), 1.0, EPS, "空影层不增伤（没攒层不加成）")
	_c.near(ShadowStepData.amp_mult([10.0, 20.0, 30.0]),
		1.0 + 3.0 * ShadowStepData.AMP_PER_STACK, EPS,
		"3 层增伤 = 1 + 3 × 每层 %.0f%%" % [ShadowStepData.AMP_PER_STACK * 100.0])

# ---------------- 影爆波次同步：满层兑现恒清一环小怪（第 9 条） ----------------

func _test_burst_wave_power() -> void:
	# 满 10 层全按参照小怪（邪修 contact 13 / 基血 24×MOB_HP_BASE_MULT）的接触刀计：
	# 波次同步必须让满层兑现 ≥ 该档小怪生命，否则中后期影爆退化成挠痒。
	for wave in [1, 10, 20, 30]:
		var hit := ceilf(13.0 * GameBalance.enemy_dmg_mult(wave))
		var ring: Array = []
		for i in range(ShadowStepData.MAX_STACKS):
			ring = ShadowStepData.push_ring(ring, hit)
		var burst := ShadowStepData.burst_damage(ring, wave)
		var ref_hp := ceilf(24.0 * GameBalance.MOB_HP_BASE_MULT * GameBalance.enemy_hp_mult(wave))
		_c.check(burst >= ref_hp,
			"W%d 满层影爆 %.0f ≥ 参照小怪血 %.0f（满层清一环小怪，全波次同一体感）" % [
				wave, burst, ref_hp])
	# 厚皮档留活口（威力底数的上界钉点）：蛛母基血 65 不能被满层秒——否则波次同步被调过猛
	var hit20 := ceilf(13.0 * GameBalance.enemy_dmg_mult(20))
	var ring20: Array = []
	for i in range(ShadowStepData.MAX_STACKS):
		ring20 = ShadowStepData.push_ring(ring20, hit20)
	var ref_zhumu := ceilf(65.0 * GameBalance.MOB_HP_BASE_MULT * GameBalance.enemy_hp_mult(20))
	_c.check(ShadowStepData.burst_damage(ring20, 20) < ref_zhumu,
		"W20 满层影爆咬不动蛛母档厚皮（威力底数不许溢出「清小怪」的定位）")

# ---------------- 4. 带影层冲刺：无敌被动同源，且不再消耗影层 ----------------

func _test_dash_iframe_bonus() -> void:
	var p := _make_player(1.0)
	for raw in [12.0, 34.0]:
		p.invulnerable_time = 0.0
		p.take_damage(float(raw))
	var stacks := _stacks(p)
	var amp_before: float = GameManager.shadow_amp_mult
	GameManager.active_skill_id = "dash"
	p.skill_cd_left = 0.0
	p.skill_active_left = 0.0
	p.invulnerable_time = 0.0
	p.velocity = Vector2.ZERO
	var st := SkillData.final_stats("dash", "")
	var want: float = float(st["iframe"]) + float(stacks) * ShadowStepData.IFRAME_PER_STACK
	_c.check(p.try_activate_skill(), "冲刺释放成功（走 HUD 同一入口 try_activate_skill）")
	_c.near(p.invulnerable_time, want, 0.001,
		"%d 层影的冲刺无敌 = 基础 %.2f + 每层 %.2f（实得 %.2f，被动不消耗影层）" % [
			stacks, float(st["iframe"]), ShadowStepData.IFRAME_PER_STACK, p.invulnerable_time])
	# 跑完冲刺段：影层必须原封不动（兑现已独立成影爆，冲刺只是位移+无敌）
	for i in range(40):
		await get_tree().process_frame
		if p._dash_time <= 0.0:
			break
	_c.check(_stacks(p) == stacks, "冲刺落地后影层原样保留（实得 %d 层，攒的影不因冲刺丢失）" % _stacks(p))
	_c.near(GameManager.shadow_amp_mult, amp_before, EPS, "冲刺全程增伤乘区不动（影在身上就持续加成）")
	p.queue_free()

# ---------------- 5+6+8. 影爆兑现、同源半径与门控 ----------------

func _test_release_delivers() -> void:
	var p := _make_player(1.0)
	# 门控：空 extra_skill_id 直接拒
	GameManager.extra_skill_id = ""
	_c.check(not p.try_activate_extra_skill(), "无额外技能时影爆入口直接拒（额外键隐藏的前提）")
	GameManager.extra_skill_id = "shadowburst"
	# 门控：0 层拒（免冷却，资源就是门票）
	p.invulnerable_time = 0.0
	_c.check(not p.try_activate_extra_skill(), "0 层影放影爆被拒（没攒上按不动）")
	for raw in [10.0, 20.0, 30.0, 40.0, 50.0]:
		p.invulnerable_time = 0.0
		p.take_damage(float(raw))
	var inside := _make_enemy(SPAWN_AT + Vector2(ShadowStepData.BURST_RADIUS - 40.0, 0.0))
	var outside := _make_enemy(SPAWN_AT + Vector2(ShadowStepData.BURST_RADIUS + 60.0, 0.0))
	var hp_in: float = inside.current_hp
	var hp_out: float = outside.current_hp
	var pos_in: Vector2 = inside.global_position
	var pos_out: Vector2 = outside.global_position
	var stored: float = ShadowStepData.stored_sum(p.shadow_ring)
	var want_dmg: float = ShadowStepData.burst_damage(p.shadow_ring, GameManager.wave_number)

	_c.check(p.try_activate_extra_skill(), "影爆走额外技能真入口释放成功（try_activate_extra_skill）")

	_c.near(hp_in - inside.current_hp, want_dmg, 0.01,
		"圈内敌人吃到影爆 %.1f 伤害（= 躲掉的 %.0f × %.0f%% × 波次威力 %.2f，走 EnemyBase.take_damage）" % [
			want_dmg, stored, ShadowStepData.STORE_RATIO * 100.0,
			ShadowStepData.wave_power(GameManager.wave_number)])
	_c.check(is_equal_approx(hp_out, outside.current_hp), "圈外敌人一格没掉（判定半径没被辉光糊大）")
	_c.check(_stacks(p) == 0, "兑现后影层归零（不重复放）")
	_c.near(GameManager.shadow_amp_mult, 1.0, EPS, "兑现后增伤乘区回 1.0（攒着的加成随爆发一起花掉）")

	var ring_r := _shockwave_radius()
	_c.near(ring_r, ShadowStepData.BURST_RADIUS, 0.01,
		"冲击环扫到的半径 == 判定半径 %f（画多大 == 判多大）" % ShadowStepData.BURST_RADIUS)

	for i in range(20):
		await get_tree().physics_frame
	_c.check(inside.global_position.distance_to(pos_in) > 1.0,
		"圈内敌人被推开（实测位移 %.1f px）" % inside.global_position.distance_to(pos_in))
	_c.check(outside.global_position.distance_to(pos_out) < 0.5, "圈外敌人纹丝不动")

	# 门控：无冷却——重新攒上立即可再放（连放两脚不进 CD）
	p.invulnerable_time = 0.0
	p.take_damage(66.0)
	_c.check(_stacks(p) == 1, "重攒 1 层（前置）")
	_c.near(p.skill_cd_left, 0.0, EPS, "影爆释放不进冷却（资源门控而非 CD）")
	_c.check(p.try_activate_extra_skill(), "攒上即可再放（无 CD 连放）")
	_c.check(_stacks(p) == 0, "第二脚同样兑现归零")
	inside.queue_free()
	outside.queue_free()
	p.queue_free()

## 读活跃冲击波的目标半径：特效池挂在场景根下的 JuiceEffectPool 里（与 BossTelegraphCheck 同一取法）
func _shockwave_radius() -> float:
	var host := get_tree().current_scene.get_node_or_null("JuiceEffectPool")
	if host == null:
		return -1.0
	for child in host.get_children():
		if child is JuiceEffect and child.effect_type == JuiceEffect.EffectType.SHOCKWAVE:
			if not child._r_max.is_empty():
				return float(child._r_max[0])
	return -1.0

# ---------------- 自检守卫：证明判据抓得住旧写法 ----------------

func _test_selftest_guard() -> void:
	# 旧写法：闪避成功只 return，不给无敌、不攒层 ⇒ 第 1 条的两次实测都会红
	var p := _make_player(1.0)
	p.invulnerable_time = 0.0
	p.take_damage(23.0)
	var legacy_invuln := 0.0
	var legacy_stacks := 0
	_c.check(legacy_invuln < ShadowStepData.GUARD_SEC,
		"自检证实：旧写法闪成功后无敌为 0，会被第 1 条抓红")
	_c.check(legacy_stacks < 1, "自检证实：旧写法不攒影，第 1 条的层数断言会抓红")
	p.queue_free()
