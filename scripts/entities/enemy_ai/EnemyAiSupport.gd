extends RefCounted

## 辅助支路（2026-11-02 自 EnemyBase 拆出，逐行平移零逻辑改动）：
## 金蟾逃窜（含落单遁逃） / 蛛母产卵 / 鼓妖光环 / 影魅闪现 / 灵医治疗。
##
## 纪律：首参 e 为宿主敌人（不标类型，鸭类型访问——反向硬类型引用 EnemyBase 会触发
## 循环类依赖，把场景 preload 打成空包，项目坑 12/16）。含宿主成员的声明用显式类型
## （无类型参数上 := 推断必炸）。同类判定用 "dying" in other 属性检查代替 is EnemyBase；
## 产卵/分裂工厂经 e.acquire_or_new(...) 实例访问，不写类名前缀。

const FLEE_WALL_BAND := 80.0       ## 金蟾软墙警告带（px）：带内背离墙外的逃离分量清零改沿墙滑行；贴墙滑行向锁存防角落抖振

## 金蟾系移动：视线内中距离环流风筝 + 避墙折返 + 挑逗得瑟停顿 + 落单仓皇遁逃（2026-10-27 机制重构）。
## 彻底摒弃贴外墙死磕滑行；保持在玩家屏幕视线内游走风筝，奔跑与歇步张弛有度，为近战/短手提供输出窗口。
static func tick_flee_slide(e, delta: float, player: Node2D, dir: Vector2, dist_sq: float, eff_speed: float) -> void:
	if not e.always_flee or e._pp_stun or e._flee_burrowing:
		return

	# 1. 落单仓皇遁逃推进（倒计时到期未伏诛，施展金光遁地离去并促成提前清场）
	if e._flee_panic:
		if e._flee_escape_timer > 0.0:
			e._flee_escape_timer -= delta
			if e._flee_escape_timer <= 0.0:
				e.escape_burrow()
				return

	var dist := sqrt(dist_sq)

	# 2. 挑逗得瑟停顿（落单仓皇逃跑时不歇步）
	if not e._flee_panic:
		if e._flee_pause_timer > 0.0:
			e._flee_pause_timer -= delta
			# 玩家近身（< 100px）受惊提前开溜
			if dist < 100.0:
				e._flee_pause_timer = 0.0
				e._flee_run_timer = 2.2
				e.play_squash(Vector2(0.85, 1.25), 0.18)
			else:
				e._pp_target_vel = Vector2.ZERO
				return
		else:
			e._flee_run_timer -= delta
			if e._flee_run_timer <= 0.0:
				if dist >= 140.0:
					var rng := GameManager.rng
					e._flee_pause_timer = rng.randf_range(0.5, 0.75) if rng != null else 0.6
					e._flee_run_timer = rng.randf_range(2.0, 2.5) if rng != null else 2.2
					if rng != null and rng.randf() < 0.5:
						e._flee_orbit_sign = -e._flee_orbit_sign
					e._pp_target_vel = Vector2.ZERO
					return
				else:
					e._flee_run_timer = 1.0

	# 3. 视线内环流与中距离风筝向量计算（dir 为指向玩家的单位向量，-dir 为纯背离玩家逃跑）
	var tangent: Vector2 = Vector2(-dir.y, dir.x) * e._flee_orbit_sign
	var raw_flee := Vector2.ZERO

	if dist < 160.0:
		# 近身警戒带（<160px）：以背离逃离为主（满足 unit test 背离点积 < 0），混合切向弧线摆脱
		raw_flee = (-dir * 0.75 + tangent * 0.45).normalized()
	elif dist <= 270.0:
		# 视线安全带（160~270px）：切向绕转戏耍为主，始终留在玩家屏幕视野内
		raw_flee = (tangent * 0.85 - dir * 0.15).normalized()
	else:
		# 过远/脱屏带（>270px）：向心折返，主动回游玩家视野
		raw_flee = (dir * 0.45 + tangent * 0.65).normalized()

	# 4. 内场边界避让（反推回内场，杜绝贴墙死磕滑行）
	var wall_lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	var safe_wall: float = wall_lim - 70.0
	var push_in := Vector2.ZERO
	if e.global_position.x > safe_wall:
		push_in.x = -1.0
	elif e.global_position.x < -safe_wall:
		push_in.x = 1.0
	if e.global_position.y > safe_wall:
		push_in.y = -1.0
	elif e.global_position.y < -safe_wall:
		push_in.y = 1.0

	if push_in != Vector2.ZERO:
		raw_flee = (raw_flee * 0.35 + push_in.normalized() * 0.75).normalized()

	if raw_flee.length_squared() < 0.0001:
		raw_flee = (-e.global_position).normalized() if e.global_position.length_squared() > 0.0001 else Vector2.UP

	var cur_speed := eff_speed * (1.15 if e._flee_panic else 1.0)
	e._pp_target_vel = raw_flee * cur_speed

## 金蟾进入落单仓皇遁逃（WaveSpawner 监测到常规敌潮清空时调用）
static func trigger_looter_panic(e) -> void:
	if not e.always_flee or e._flee_panic or e.dying or e._flee_burrowing:
		return
	e._flee_panic = true
	e._flee_escape_timer = 6.0
	e._flee_pause_timer = 0.0
	e._flee_run_timer = 6.0
	GameManager.announcement_triggered.emit("◆ 金蟾见势不妙，慌忙遁逃！◆")
	GameManager.shake_camera(3.0, 0.2)

## 金蟾遁地离开（限时未伏诛，施展金光遁地钻走，自动结算提前清场）
static func escape_burrow(e) -> void:
	if e.dying or e._flee_burrowing:
		return
	e._flee_burrowing = true
	e._pp_target_vel = Vector2.ZERO
	e.velocity = Vector2.ZERO
	if e.is_in_group("enemies"):
		e.remove_from_group("enemies")
	GameManager.unregister_enemy(e)
	DamageNumber.spawn(e.get_parent(), e.global_position, 0, false, "遁地离去！")
	FxParticlePool.burst(FxParticlePool.DEATH_BURST, e.global_position, "gold", 0.9)
	AudioManager.play_sfx("enemy_blink", 0.9)
	var tw: Tween = e.create_tween()
	tw.tween_property(e, "scale", Vector2.ZERO, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func():
		e.scale = Vector2.ONE
		e._recycle_or_free()
	)

## 蛛母系：周期性产卵（受同屏上限约束，不冲破刷怪口的上限）。
static func tick_minion_spawn(e, delta: float) -> void:
	# 蛛母系：周期性产卵（受同屏上限约束，不冲破刷怪口的上限）
	if e.spawn_minion_interval > 0.0 and e.minion_scene != null and e._fuse < 0.0:
		e._minion_timer -= delta
		if e._minion_timer <= 0.0:
			e._minion_timer = e.spawn_minion_interval
			if GameManager.enemy_count < GameBalance.ZHUMU_MINION_CAP:
				_spawn_minion(e)

## 鼓妖光环：每 0.25s 给范围内同伴刷新一次加速。
static func tick_buff_aura_pulse(e, delta: float) -> void:
	# 鼓妖光环：每 0.25s 给范围内同伴刷新一次加速
	if e.buff_radius > 0.0:
		e._buff_timer -= delta
		if e._buff_timer <= 0.0:
			e._buff_timer = 0.25
			pulse_buff_aura(e)

## 影魅系：周期性闪现到玩家侧翼（自爆引信点燃时不闪现，避免爆点漂移）。
## 2026-11-03 可读性：先锁落点、亮符环、钉地 0.32s，填满才落地；旧写法一帧硬切，
## 玩家只看到「突然消失 → 贴脸出现」。落点起手帧锁定，不追玩家，走得出去。
static func tick_teleport_step(e, delta: float, player: Node2D) -> void:
	# 前摇推进由 EnemyBase._tick_blink_windup 统一负责（前摇期 _tick_behaviors 整体让位）
	if e.teleport_interval > 0.0 and e._fuse < 0.0:
		e._teleport_timer -= delta
		if e._teleport_timer <= 0.0:
			e._teleport_timer = e.teleport_interval
			_begin_teleport(e, player)

## 灵医系：周期性治疗范围内同伴（土豆兄弟 Healer：制造优先击杀目标）。
static func tick_heal_pulse(e, delta: float) -> void:
	# 灵医系：周期性治疗范围内同伴（土豆兄弟 Healer：制造优先击杀目标）
	if e.heal_interval > 0.0 and e._fuse < 0.0:
		e._heal_timer -= delta
		if e._heal_timer <= 0.0:
			e._heal_timer = e.heal_interval
			e._pulse_heal()

## 鼓妖光环：范围内同伴获得短时加速（0.4s 有效期，光环脉冲每 0.25s 续期）
static func pulse_buff_aura(e) -> void:
	var radius_sq: float = e.buff_radius * e.buff_radius
	# 快照遍历照 _die 击杀链的 _explode_snap_pool 模式（2026-10-24）：receive_aura 今天只写
	# 字段不动登记表，但「对同伴生效」的循环一旦后续加入可致死效果，循环内 swap-remove 会
	# 静默跳过末尾同伴；钉死在快照上，验活口径也与击杀链对齐
	var snap: Array = e._explode_snap_pool.pop_back() if not e._explode_snap_pool.is_empty() else []
	snap.append_array(GameManager.live_enemies)
	for other in snap:
		if other == null or not is_instance_valid(other):
			continue
		if other == e or not ("dying" in other) or other.dying:
			continue
		if e.global_position.distance_squared_to(other.global_position) <= radius_sq:
			receive_aura(other, e.buff_speed_mult, 400)
	snap.clear()
	e._explode_snap_pool.push_back(snap)

## 被鼓妖光环覆盖：取最高倍率，过期待遇由宿主 _physics_process 自动清除。
## 首次被罩到（边沿）发一圈冲击波提示「它被加速了」；常驻脉冲只续期不再发，防刷屏。
static func receive_aura(e, mult: float, duration_ms: int) -> void:
	if e.dying:
		return
	e._aura_speed_mult = maxf(e._aura_speed_mult, mult)
	e._aura_until_ms = Time.get_ticks_msec() + duration_ms
	if not e._aura_shown:
		e._aura_shown = true
		if e.procedural_view != null:
			e.procedural_view.aura_level = 1.0
		JuiceEffect.spawn_shockwave(e.get_parent(), e.global_position, 22.0, GameStyle.JADE, 0.24)

## 蛛母产卵：幼体在自身周围落点，生命/伤害按当前回合 × 危险度缩放（与 WaveSpawner._scale_to_wave 同一把尺子）
static func _spawn_minion(e) -> void:
	if e.minion_scene == null:
		return
	var m = e.acquire_or_new(e.minion_scene)
	if m == null:
		return
	m.reset_for_reuse()
	var angle := GameManager.rng.randf() * TAU
	m.global_position = e.global_position + Vector2(cos(angle), sin(angle)) * GameBalance.MINION_SCATTER_RADIUS
	m.max_hp = ceilf(m.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level))
	m.contact_damage = ceilf(m.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level))
	m.add_to_group("enemies")
	m.activate()
	e.get_parent().call_deferred("add_child", m)
	if e.procedural_view != null:
		e.procedural_view.trigger_cast_pulse()
	e.play_squash(Vector2(1.22, 0.78), 0.2)
	# 产卵不是击杀：pitch_override 直传，绕开击杀连击阶梯（也不推层）
	AudioManager.play_sfx("enemy_death", 0.5, 1.3)

## 影魅闪现起手：锁定玩家侧翼 210px 落点（受界碑约束），先在地面亮符环再落地。
static func _begin_teleport(e, player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var angle := GameManager.rng.randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * GameBalance.BLINK_DISTANCE
	var lim: float = GameManager.MAP_HALF_EXTENT - GameBalance.BLINK_MAP_INSET
	pos = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	e._blink_kind = e.BLINK_KIND_TELEPORT
	e._begin_blink_telegraph(pos, GameBalance.BLINK_WINDUP, GameStyle.BAD, BlinkRift.RADIUS_NORMAL)

static func pulse_heal(e) -> void:
	var radius_sq: float = e.heal_radius * e.heal_radius
	var healed_any := false
	# 快照遍历同 pulse_buff_aura（2026-10-24）：receive_heal 不致死，钉死快照后
	# 后续加「过疗反噬」之类可致死效果不会再踩循环内 swap-remove 的坑
	var snap: Array = e._explode_snap_pool.pop_back() if not e._explode_snap_pool.is_empty() else []
	snap.append_array(GameManager.live_enemies)
	for other in snap:
		if other == null or not is_instance_valid(other):
			continue
		if other == e or not ("dying" in other) or other.dying:
			continue
		if e.global_position.distance_squared_to(other.global_position) > radius_sq:
			continue
		if other.current_hp >= other.max_hp:
			continue
		receive_heal(other, e.heal_amount)
		healed_any = true
	snap.clear()
	e._explode_snap_pool.push_back(snap)
	# 2026-10-16 演出去噪：演出环每跳只发一次（旧写法 if 缩进在 for 内，一跳奶到 N 个
	# 残血同伴就同帧叠 N 个 240px 大绿圈 + N 重音效——治疗环是全游戏最大的冲击环，群奶糊屏）。
	# 治疗本身照常逐个结算；「谁在被奶」的受者读数由 receive_heal 里的 heal_rise 逐个亮，不丢信息。
	if healed_any:
		if e.procedural_view != null:
			e.procedural_view.trigger_cast_pulse()
		JuiceEffect.spawn_shockwave(e.get_parent(), e.global_position, e.heal_radius, GameStyle.GOOD, 0.35)
		AudioManager.play_sfx("heal", 0.5)
		e.play_squash(Vector2(1.18, 0.84), 0.18)

static func receive_heal(e, amount: float) -> void:
	if e.dying:
		return
	# 入口闸：负治疗会静默扣血且不走 _die，血量与状态机错位（同 Player.heal 的 amount<=0 口径）
	if amount <= 0.0:
		return
	e.current_hp = minf(e.max_hp, e.current_hp + amount)
	if not e._offscreen:
		DamageNumber.spawn(e.get_parent(), e.global_position, int(amount), false, "+%d" % int(amount))
		# 治疗可视出口（2026-10-14 P1）：受者身上升起青绿灵光，满屏也能读出「谁在被奶」
		JuiceEffect.spawn_heal_rise(e.get_parent(), e.global_position)
	e.play_squash(Vector2(1.1, 0.9), 0.14)
