extends Node

## Boss 攻击身份化 + 三新招闸门（2026-11-04）：
##   1. 身份表：19 尊 Boss 的 (弹体形态, 主色, 预警样式) 三元组两两不重复；
##      六种弹体形态、五种预警样式全部有主且每种至少两尊 —— 「一眼认出是谁」是这张表的唯一目的。
##   2. 形态落位：EnemyBolt.set_style / AoeTelegraph.set_style 只改外观，不动判定半径/进度。
##   3. 三新招：激光「充能不出伤、出束才出伤、结束解锁」、吐息「前摇跟随 / 出火锁向 / 留火池」、
##      陨火「落点圈 == 爆炸判定、错时落地、伏诛清算」。
##   4. 伏诛清算：Boss 死亡时激光束与陨石必须归还池（否则下一尊复用池拿到残影）。
## 只验几何与状态机，不做视觉截图。
## 运行: godot --headless --path . res://tests/BossVarietyCheck.tscn

## 18 尊轮换 Boss（第 20 波破境魔尊 boss_id 为空串，单列验）
const BOSS_IDS := ["chiyan", "xiuluo", "qianji", "wangu", "jianpo", "xinmo",
	"zhaoying", "yinhun", "luding", "canglong", "jianzhong", "leijie",
	"kunwang", "kuijia", "fenghuang", "tianmo", "hundun", "wanjie"]

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.reset_run()
	# 身份表 19 项 × 4 条 + 形态/样式判据 + 三新招 ≈ 70 条；掉一半即中途炸了
	_c.set_min_checks(60)

	_test_profile_table()
	_test_for_boss_lookup()
	_test_bolt_styles()
	_test_telegraph_styles()

	var p := _make_player(Vector2.ZERO)
	await _test_boss_identity(p)
	await _test_laser_sweep(p)
	await _test_flame_cone(p)
	await _test_meteor_strike(p)
	await _test_death_cleanup(p)

	p.queue_free()
	GameManager.player = null
	_recycle_bolts()
	if _c.report("BOSS_VARIETY_CHECK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 1. 身份表 ----------------

func _test_profile_table() -> void:
	var keys: Array = BossAttackProfile.registered_keys()
	_c.equals(keys.size(), BOSS_IDS.size() + 1,
		"身份表覆盖 18 尊轮换 Boss + 破境魔尊（期望 %d，实得 %d）" % [BOSS_IDS.size() + 1, keys.size()])
	for bid in BOSS_IDS:
		if not _c.check(BossAttackProfile.has_profile(bid), "身份表登记了 %s" % bid):
			continue
		var prof: Dictionary = BossAttackProfile.for_boss(bid)
		var accent: Color = prof.get("accent", Color(0, 0, 0, 0))
		_c.check(accent.a > 0.0, "%s 主色带不透明 alpha（弹幕才看得见）" % bid)
		_c.check(int(prof.get("bolt", -1)) >= 0 and int(prof.get("bolt", -1)) < EnemyBolt.Style.size(),
			"%s 弹体形态在 EnemyBolt.Style 取值域内" % bid)
		_c.check(int(prof.get("telegraph", -1)) >= 0 and int(prof.get("telegraph", -1)) < AoeTelegraph.Style.size(),
			"%s 预警样式在 AoeTelegraph.Style 取值域内" % bid)
		var cast_fx: StringName = prof.get("cast_fx", &"")
		var impact_fx: StringName = prof.get("impact_fx", &"")
		_c.check(cast_fx == &"" or not FxSheetData.get_config(cast_fx).is_empty(),
			"%s 起手特效 id 已接线 FxSheetData：%s" % [bid, cast_fx])
		_c.check(impact_fx == &"" or not FxSheetData.get_config(impact_fx).is_empty(),
			"%s 命中特效 id 已接线 FxSheetData：%s" % [bid, impact_fx])

	# 三元组两两不重复 + 每种形态/样式至少两尊（保证「形态即身份」，不是唯一特例）
	var triples := {}
	var bolt_hist := {}
	var tele_hist := {}
	for key in keys:
		var prof: Dictionary = BossAttackProfile.PROFILES[key]
		var bolt_style: int = int(prof.bolt)
		var tele: int = int(prof.telegraph)
		var accent: Color = prof.accent
		var triple := "%d/%d/%s" % [bolt_style, tele, accent.to_html(false)]
		_c.check(not triples.has(triple),
			"三元组不重复：%s（%s 与 %s 撞了）" % [triple, str(key), str(triples.get(triple, ""))])
		triples[triple] = key
		bolt_hist[bolt_style] = int(bolt_hist.get(bolt_style, 0)) + 1
		tele_hist[tele] = int(tele_hist.get(tele, 0)) + 1
	_c.equals(triples.size(), keys.size(), "19 组三元组全部唯一")
	_c.equals(bolt_hist.size(), EnemyBolt.Style.size(), "六种弹体形态全部有主（没有闲置形态）")
	_c.equals(tele_hist.size(), AoeTelegraph.Style.size(), "五种预警样式全部有主（没有闲置样式）")
	for s in bolt_hist:
		_c.check(int(bolt_hist[s]) >= 2, "弹体形态 %d 至少两尊 Boss 使用（同形态才能形成「族」）" % int(s))
	for s in tele_hist:
		_c.check(int(tele_hist[s]) >= 2, "预警样式 %d 至少两尊 Boss 使用" % int(s))

func _test_for_boss_lookup() -> void:
	var fb := BossAttackProfile.for_boss("no_such_boss_id")
	_c.equals(int(fb.bolt), EnemyBolt.Style.ORB, "未登记 boss_id 退 ORB 兜底（不崩）")
	_c.equals(int(fb.telegraph), AoeTelegraph.Style.FILL, "未登记 boss_id 退 FILL 兜底（不崩）")
	var fin := BossAttackProfile.for_boss("", true)
	var fin2 := BossAttackProfile.for_boss(BossAttackProfile.FINAL_KEY)
	_c.equals(fin.accent, fin2.accent, "空 boss_id + final_boss 与 FINAL_KEY 查到同一份身份")
	_c.check(not fin.accent.is_equal_approx(BossAttackProfile.for_boss("chiyan").accent),
		"破境魔尊与首尊火 Boss 不同色（旧版两者都走同一刀切）")

# ---------------- 2. 形态落位 ----------------

func _test_bolt_styles() -> void:
	var bolt := EnemyBolt.acquire(self)
	if not _c.check(bolt != null, "弹体池可分配"):
		return
	bolt.scale_factor = 1.7
	var base_radius: float = bolt.radius
	for s in EnemyBolt.Style.values():
		bolt.set_style(s, Color(0.2, 0.9, 0.4), Color(1, 1, 1))
		_c.equals(bolt.style, s, "EnemyBolt 形态落位 == %d" % int(s))
		_c.near(bolt.radius, base_radius, 0.001, "set_style 不改判定半径（形态 %d）" % int(s))
		_c.near(bolt.scale_factor, 1.7, 0.001, "set_style 不改缩放（形态 %d）" % int(s))
	# 主色下发后同形态不同色必须可区分（身份表靠色差分工）
	bolt.set_style(EnemyBolt.Style.FLAME, Color(1.0, 0.5, 0.1), Color(1, 1, 1))
	var warm: Color = bolt.accent_color
	bolt.set_style(EnemyBolt.Style.FLAME, Color(0.2, 0.9, 0.8), Color(1, 1, 1))
	_c.check(not warm.is_equal_approx(bolt.accent_color), "同形态换主色后 accent 立即变化")
	bolt._recycle()

func _test_telegraph_styles() -> void:
	var tg := AoeTelegraph.new()
	add_child(tg)
	tg.radius = 137.0
	tg.progress = 0.42
	for s in AoeTelegraph.Style.values():
		tg.set_style(s, Color(0.9, 0.6, 0.2))
		_c.equals(tg.style, s, "AoeTelegraph 样式落位 == %d" % int(s))
		_c.near(tg.radius, 137.0, 0.001, "set_style 不改半径（样式 %d）" % int(s))
		_c.near(tg.progress, 0.42, 0.001, "set_style 不改进度（样式 %d）" % int(s))
	tg.queue_free()

# ---------------- 3. 身份接线 ----------------

func _test_boss_identity(p: Player) -> void:
	# 三尊代表：前期火 Boss / 深层雷 Boss / 破境魔尊
	for case in [["chiyan", false], ["leijie", false], ["", true]]:
		var bid: String = case[0]
		var is_final: bool = case[1]
		var boss := _make_boss(bid, Vector2(0, -300), is_final)
		await get_tree().process_frame
		var prof := BossAttackProfile.for_boss(bid, is_final)
		_c.equals(boss._profile.bolt, prof.bolt, "%s 实例读到身份表形态" % (bid if bid != "" else "FINAL"))
		_c.check(boss._fx_color.is_equal_approx(prof.accent),
			"%s 主题色 == 身份表主色（弹幕/预警/冲击环同源）" % (bid if bid != "" else "FINAL"))
		boss.queue_free()
		await get_tree().process_frame

# ---------------- 4. 玄光贯日 ----------------

func _test_laser_sweep(p: Player) -> void:
	var boss := _make_boss("qianji", Vector2(0, -160), false)
	await get_tree().process_frame
	p.invulnerable_time = 0.0
	p.current_health = 100000.0
	p.global_position = Vector2.ZERO

	boss._cast_laser_sweep(p)
	_c.check(boss._laser_pending, "激光起手进入站桩互斥锁")
	_c.equals(boss._laser_beams.size(), GameBalance.BOSS_LASER_BEAMS,
		"P1 齐射束数 == %d" % GameBalance.BOSS_LASER_BEAMS)
	_c.near(boss._laser_total,
		GameBalance.BOSS_LASER_CHARGE + GameBalance.BOSS_LASER_FIRE + GameBalance.BOSS_LASER_FADE,
		0.001, "激光总时长 == 充能 + 出束 + 淡出")
	var beam: BossBeam = boss._laser_beams[0] if boss._laser_beams.size() > 0 else null
	_c.check(beam != null and beam.visible, "光束实体已激活入池")
	if beam != null:
		_c.near(beam.width, GameBalance.BOSS_LASER_WIDTH, 0.001, "伤害走廊宽 == 配置束宽")
		_c.near(beam.length, GameBalance.BOSS_LASER_LENGTH, 0.001, "光束长度 == 配置")

	# 充能期：只画描边，不出伤（玩家站在正对走廊里也不掉血）
	await get_tree().create_timer(GameBalance.BOSS_LASER_CHARGE * 0.6).timeout
	_c.near(p.current_health, 100000.0, 0.01, "充能期激光不出伤（读招窗口，不是伤害窗口）")
	if beam != null:
		_c.check(not beam.firing, "充能期 firing == false（只画描边）")

	# 出束期：正对走廊必中（P1 无扫掠，玩家不动就吃）
	await get_tree().create_timer(GameBalance.BOSS_LASER_CHARGE * 0.4 + 0.16).timeout
	_c.check(p.current_health < 100000.0, "出束期站在走廊里掉血")
	var hp_after_laser: float = p.current_health
	if beam != null:
		_c.check(beam.firing, "出束期 firing == true")

	# 结束解锁
	await get_tree().create_timer(GameBalance.BOSS_LASER_FIRE + 0.4).timeout
	_c.check(not boss._laser_pending, "激光结束解除站桩锁")
	_c.check(p.current_health <= hp_after_laser, "激光结束后不再继续扣血（一次性窗口）")
	boss.queue_free()
	await get_tree().process_frame

func _test_flame_cone(p: Player) -> void:
	var boss := _make_boss("chiyan", Vector2(0, -160), false)
	await get_tree().process_frame
	p.invulnerable_time = 0.0
	p.current_health = 100000.0
	p.global_position = Vector2.ZERO
	var pools_before := _count_fire_pools()

	boss._cast_flame_cone(p)
	_c.check(boss._flame_pending, "吐息起手进入站桩互斥锁")
	_c.check(boss._flame_cone != null and boss._flame_cone.visible, "扇形预警实体可见")
	if boss._flame_cone != null:
		_c.near(boss._flame_cone.half_angle, GameBalance.BOSS_FLAME_HALF_ANGLE, 0.001, "扇形半角 == 判定半角")
		_c.near(boss._flame_cone.length, GameBalance.BOSS_FLAME_LENGTH, 0.001, "扇形半径 == 判定半径")
	_c.check(absf(angle_difference(boss._flame_dir,
		(p.global_position - boss.global_position).angle())) < 0.05, "起手扇形正对玩家")

	# 前摇期：扇形跟着玩家转（1.6 rad/s 上限），且不出伤
	p.global_position = boss.global_position + Vector2(260, 0)
	await get_tree().create_timer(GameBalance.BOSS_FLAME_WINDUP * 0.6).timeout
	_c.near(p.current_health, 100000.0, 0.01, "吐息前摇不出伤")
	_c.check(absf(angle_difference(boss._flame_dir, PI * 0.5)) > 0.3,
		"前摇期扇形跟随玩家转向（从 +Y 往 +X 偏）")

	# 出火：当帧锁向 → 站到锁定轴上必中（画多大判多大）
	await get_tree().create_timer(GameBalance.BOSS_FLAME_WINDUP * 0.45 + 0.1).timeout
	if not _c.check(boss._flame_breath_left > 0.0, "进入出火阶段"):
		return
	var dir_locked: float = boss._flame_dir
	p.global_position = boss.global_position + Vector2.from_angle(dir_locked) * 140.0
	await get_tree().create_timer(GameBalance.BOSS_FLAME_TICK + 0.08).timeout
	_c.check(p.current_health < 100000.0, "扇形锁定轴内必中（判定与预警同源）")
	var hp_in_cone: float = p.current_health

	# 绕到背面：锁向之后绕背是解，且不再吃伤害（清掉受击无敌帧，确保是「没判中」不是「无敌挡了」）
	p.global_position = boss.global_position - Vector2.from_angle(dir_locked) * 140.0
	p.invulnerable_time = 0.0
	await get_tree().create_timer(GameBalance.BOSS_FLAME_TICK * 1.6).timeout
	_c.near(p.current_health, hp_in_cone, 0.01, "出火后绕到扇形背面不吃伤害（锁向不追人）")
	_c.near(boss._flame_dir, dir_locked, 0.001, "出火当帧锁向，不再跟随玩家")

	await get_tree().create_timer(GameBalance.BOSS_FLAME_BREATH).timeout
	_c.check(not boss._flame_pending, "吐息收势解锁")
	_c.check(boss._flame_cone == null or not boss._flame_cone.visible, "收势后扇形预警隐藏")
	_c.check(_count_fire_pools() > pools_before, "收势沿吐息轴留下火池（地面余火）")
	boss.queue_free()
	await get_tree().process_frame

func _test_meteor_strike(p: Player) -> void:
	var boss := _make_boss("chiyan", Vector2(0, -160), false)
	boss._phase2 = true   # 狂暴档 5 颗，顺带验 _P2 常量接线
	await get_tree().process_frame
	p.invulnerable_time = 0.0
	p.current_health = 100000.0
	p.global_position = Vector2(0, 40)

	boss._cast_meteor_strike(p)
	_c.equals(boss._active_meteors.size(), GameBalance.BOSS_METEOR_COUNT_P2,
		"P2 陨火颗数 == %d" % GameBalance.BOSS_METEOR_COUNT_P2)
	var first: Dictionary = boss._active_meteors[0]
	_c.check(Vector2(first.pos).distance_to(p.global_position) <= GameBalance.BOSS_METEOR_RADIUS,
		"首颗落点压在玩家当前位置（站桩必吃）")
	var min_fall: float = 999.0
	for mt in boss._active_meteors:
		min_fall = minf(min_fall, float(mt.timer))
	_c.near(min_fall, GameBalance.BOSS_METEOR_FALL, 0.001, "首颗留满前摇（不是瞬爆）")

	# 落地：判定半径 == 阴影半径（站在圈内必吃，圈外不吃）
	await get_tree().create_timer(GameBalance.BOSS_METEOR_FALL + 0.1).timeout
	_c.check(p.current_health < 100000.0, "首颗陨火命中站桩玩家")
	var hp_after: float = p.current_health
	# 后续颗不追人：玩家跑开 400px 后不再掉血
	p.global_position = Vector2(600, 600)
	await get_tree().create_timer(GameBalance.BOSS_METEOR_INTERVAL * float(GameBalance.BOSS_METEOR_COUNT_P2) + 0.4).timeout
	_c.near(p.current_health, hp_after, 0.01, "离开落点圈后不再吃后续陨火")
	_c.check(boss._active_meteors.is_empty(), "全部落地后错时队列清空")
	boss.queue_free()
	await get_tree().process_frame

func _test_death_cleanup(p: Player) -> void:
	var boss := _make_boss("qianji", Vector2(0, -160), false)
	await get_tree().process_frame
	boss._cast_laser_sweep(p)
	boss._cast_meteor_strike(p)
	var beam_count := boss._laser_beams.size()
	_c.check(beam_count > 0, "伏诛前光束已入池")
	boss._die()
	_c.check(boss._laser_beams.is_empty(), "伏诛清空光束引用")
	_c.equals(_count_active_beams(), 0, "伏诛后池里没有残留激光（下一尊不会复用到残影）")
	_c.check(boss._active_meteors.is_empty(), "伏诛清空陨火错时队列")
	boss.queue_free()
	await get_tree().process_frame

# ---------------- helpers ----------------

func _make_player(pos: Vector2) -> Player:
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)
	p.global_position = pos
	p.max_health = 999999.0
	p.current_health = 999999.0
	GameManager.player = p
	return p

func _make_boss(bid: String, pos: Vector2, is_final: bool = false) -> BossEnemy:
	var boss_scene: PackedScene = load("res://scenes/entities/BossEnemy.tscn")
	var boss := boss_scene.instantiate() as BossEnemy
	boss.boss_id = bid
	boss.final_boss = is_final
	add_child(boss)
	boss.global_position = pos
	boss.attack_interval = 999.0
	boss._attack_timer = 999.0
	return boss

## 火池从 PoisonPoolHost 里取（acquire 把实例挂在 host 子节点上，不是测试节点直系）
func _count_fire_pools() -> int:
	var n := 0
	var host := PoisonPool._host
	if host == null or not is_instance_valid(host):
		return 0
	for ch in host.get_children():
		if ch is PoisonPool and ch.pool_kind == PoisonPool.Kind.FIRE and ch.visible:
			n += 1
	return n

func _count_active_beams() -> int:
	var n := 0
	for ch in get_children():
		if ch is BossBeam and ch.visible:
			n += 1
	return n

func _recycle_bolts() -> void:
	if EnemyBolt._host == null:
		return
	for b in EnemyBolt._host.get_children():
		if b is EnemyBolt and b.visible:
			b._recycle()
