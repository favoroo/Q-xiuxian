extends RefCounted

## 范围伤害支路（2026-11-02 自 EnemyBase 拆出，逐行平移零逻辑改动）：
## 丹爆自爆引信与死亡弹幕 / 铁甲魔傀震地（含变异多段余波）与落石轰炸 / 剑煞雷剑域 / 毒妖投毒。
##
## 纪律：首参 e 为宿主敌人（不标类型，鸭类型访问——反向硬类型引用 EnemyBase 会触发
## 循环类依赖，把场景 preload 打成空包，项目坑 12/16）。含宿主成员的声明用显式类型
## （无类型参数上 := 推断必炸）。宿主保留同名一行转发器（判据测试直调 / _die / apply_vortex_pin 口径）。

const EXPLODE_FUSE := 0.8  ## 丹爆引信时长（秒）：预警圈填满 = 引信烧完 = 自爆结算

## 丹爆傀儡：贴近点燃引信，原地颤抖后自爆；返回 true = 已结算自爆，调用方立即结束本帧。
static func tick_explode_fuse(e, delta: float, player: Node2D, dist_sq: float) -> bool:
	# 丹爆傀儡：贴近点燃引信，原地颤抖后自爆
	if e.explode_radius > 0.0:
		if e._fuse < 0.0:
			if dist_sq < 1600.0:
				e._fuse = EXPLODE_FUSE
				e._hit_jiggle_offset = Vector2.ZERO  # 引信颤抖要独占位移抖动，受击微反冲残量先归位
				e.anim_sprite.modulate = Color(2.2, 0.9, 0.6)
				e.play_squash(Vector2(1.2, 0.82), 0.3)
				AudioManager.play_sfx("enemy_fuse", 1.0)   ## 引信是递进爆点的倒计时，不是灵宝触体的钟
				e._ignite_explode_ring()
		else:
			e._fuse -= delta
			e._pp_target_vel = Vector2.ZERO
			if e._explode_ring != null:
				e._explode_ring.progress = 1.0 - e._fuse / EXPLODE_FUSE
			# 引信颤抖：旧写法只抖 anim_sprite，程序化白模下它是隐藏节点（视图藏在 procedural_view），
			# 玩家看到的白模一动不动。两套载体同拍抖，哪套在用都读得到。
			var fuse_jitter := GameManager.rng.randf_range(-1.6, 1.6)
			e.anim_sprite.position.x = fuse_jitter
			if e.procedural_view != null:
				e.procedural_view.position.x = fuse_jitter
			if e._fuse <= 0.0:
				e.anim_sprite.position.x = 0.0
				if e.procedural_view != null:
					e.procedural_view.position.x = 0.0
				e._explode(player)
				return true
	return false

## 铁甲魔傀·震地：预警圈「填满式」倒计时 → 结算（与 Boss 震地同一套视觉语言）。
static func tick_elite_slam_step(e, delta: float, player: Node2D, dist_sq: float) -> void:
	# 铁甲魔傀·震地：预警圈「填满式」倒计时 → 结算（与 Boss 震地同一套视觉语言）
	if e.slam_interval > 0.0 and e._fuse < 0.0:
		if e._elite_slam_windup_t >= 0.0:
			e._elite_slam_windup_t -= delta
			e._pp_target_vel = Vector2.ZERO
			if e._elite_slam_ring != null:
				e._elite_slam_ring.progress = 1.0 - e._elite_slam_windup_t / maxf(e.slam_windup, 0.001)
			if e._elite_slam_windup_t <= 0.0:
				e._resolve_elite_slam(player)
		else:
			e._elite_slam_timer -= delta
			# 与落石互斥：同一时刻只亮一种预警，避免双圈叠读
			if e._elite_slam_timer <= 0.0 and e._rock_windup_t < 0.0 and dist_sq < e.slam_radius * e.slam_radius * 2.25:
				e._elite_slam_timer = e.slam_interval
				start_elite_slam(e)
	# 变异震地余波独立推进：预警段被硬直/其他支路打断也要把已承诺的段数结完
	tick_slam_echo(e, delta, player)

## 铁甲魔傀·落石轰炸：起手锁多个落点 → 每个落点亮填满式预警圈 → 逐个结算。首点锁玩家预判位
## （rock_lead），其余绕首点按 rock_spread 散布 —— 克制原地站桩与匀速跑位。
static func tick_rock_barrage_step(e, delta: float, player: Node2D, dist_sq: float) -> void:
	# 铁甲魔傀·落石轰炸：起手锁多个落点 → 每个落点亮填满式预警圈 → 逐个结算。
	# 首点锁玩家预判位（rock_lead），其余绕首点按 rock_spread 散布 —— 克制原地站桩与匀速跑位。
	if e.rock_interval > 0.0 and e._fuse < 0.0:
		if e._rock_windup_t >= 0.0:
			e._rock_windup_t -= delta
			e._pp_target_vel = Vector2.ZERO
			var rock_progress: float = 1.0 - e._rock_windup_t / maxf(e.rock_windup, 0.001)
			for ring in e._rock_rings:
				if ring != null and is_instance_valid(ring):
					ring.progress = rock_progress
			if e._rock_windup_t <= 0.0:
				e._resolve_rock_barrage(player)
		else:
			e._rock_timer -= delta
			# 与冲刺/震地互斥：冲刺锁定段不砸石（落点追不上自己），震地预警中不叠第二种圈
			if e._rock_timer <= 0.0 and dist_sq < 640000.0 and not e._pp_stun \
					and e._charge_windup < 0.0 and e._charge_active <= 0.0 and e._charge_brake <= 0.0 \
					and e._elite_slam_windup_t < 0.0:
				e._rock_timer = e.rock_interval
				e._start_rock_barrage(player)

## 剑煞邪修·雷剑域：在玩家脚下铺持续伤害领域（复用毒潭骨架，染血煞色）。
static func tick_field_cast(e, delta: float, player: Node2D, dist_sq: float) -> void:
	# 剑煞邪修·雷剑域：在玩家脚下铺持续伤害领域（复用毒潭骨架，染血煞色）
	if e.field_interval > 0.0 and e._fuse < 0.0:
		if e._field_windup_t >= 0.0:
			e._field_windup_t -= delta
			e._pp_target_vel = Vector2.ZERO
			if e._field_ring != null:
				e._field_ring.progress = 1.0 - e._field_windup_t / maxf(e.field_windup, 0.001)
				e._field_ring.global_position = e._field_target
			if e._field_windup_t <= 0.0:
				drop_field(e)
		else:
			e._field_timer -= delta
			if e._field_timer <= 0.0 and dist_sq < 640000.0 and not e._pp_stun:
				e._field_timer = e.field_interval
				# 首圈不压顶：沿速度侧向偏出半步（持续领域治理），站桩与直跑玩家都只需侧移脱圈
				e._field_target = player.global_position \
						+ e.aoe_zone_side_dir(player.velocity if player is CharacterBody2D else Vector2.ZERO) \
						* GameBalance.aoe_zone_edge_offset(e.field_radius)
				e._start_field_cast()

## 毒妖系：周期性朝玩家所在地投一片毒潭（持续伤害区域，进入即按周期掉血）。
static func tick_poison_cast(e, delta: float, player: Node2D, dist_sq: float) -> void:
	# 毒妖系：周期性朝玩家所在地投一片毒潭（持续伤害区域，进入即按周期掉血）
	if e.poison_interval > 0.0 and e._fuse < 0.0:
		if e._poison_windup_t >= 0.0:
			# 预警阶段：原地不动，落点圈填满 = 毒潭落下。
			# 落点在起手那一帧锁死、之后不追踪玩家 —— 0.6s 还追踪的话玩家永远躲不开（同短咬口径）
			e._poison_windup_t -= delta
			e._pp_target_vel = Vector2.ZERO
			if e._poison_ring != null:
				e._poison_ring.progress = 1.0 - e._poison_windup_t / maxf(e.poison_windup, 0.001)
				# 预警圈每帧钉回落点：预警期间被击退/位移也不把圈带跑（落点早已锁死）
				e._poison_ring.global_position = e._poison_target
			if e._poison_windup_t <= 0.0:
				e._drop_poison()
		else:
			e._poison_timer -= delta
			if e._poison_timer <= 0.0 and dist_sq < e.poison_radius * e.poison_radius * 6.25:
				e._poison_timer = e.poison_interval
				# 首潭不压顶：与雷剑域同一条持续领域治理，落点侧向偏出半步
				e._poison_target = player.global_position \
						+ e.aoe_zone_side_dir(player.velocity if player is CharacterBody2D else Vector2.ZERO) \
						* GameBalance.aoe_zone_edge_offset(e.poison_radius)
				e._start_poison_cast()

## 自爆结算：范围内伤玩家，不掉落、不计击杀奖励
static func explode(e, player: Node2D) -> void:
	if e.dying:
		return
	e._clear_explode_ring()
	# 冲击波扫到 explode_radius 为止：扫过的范围就是受伤的范围（与判定同源）
	JuiceEffect.spawn_shockwave(e.get_parent(), e.global_position, e.explode_radius, GameStyle.BAD)
	# 爆点留焦痕（纯视觉贴花，判定已在上方结算）。焦痕走全局共享闸（同 FloatingWeapon 裂痕
	# 同一治理口径）：成群丹爆接连自爆不再把地面糊满黑斑，屏上至多一块焦痕。
	if e._fx_gap_gate(e.GROUND_SCORCH_MIN_GAP_MS, "scorch"):
		GroundDecal.spawn(e.get_parent(), e.global_position, GroundDecal.Kind.SCORCH, e.explode_radius * 0.7)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	# 自爆也算战果：进击杀连击音阶（精英基准抬档同 _die 口径）
	AudioManager.register_kill_pitch(e.die_pitch_base * e.KILL_PITCH_ELITE_MULT)
	AudioManager.play_sfx("enemy_death_elite", 0.9)
	if player.global_position.distance_to(e.global_position) <= e.explode_radius:
		# 目标可能是被嘲讽改追的灵兽：Player 走两参受创链路，其余鸭子分派单参（同短咬口径）
		if player is Player:
			player.take_damage(e.contact_damage * 2.0, e.global_position)
		elif player.has_method("take_damage"):
			player.take_damage(e.contact_damage * 2.0)
	e._no_drop = true
	e._die()

## 死亡弹幕：引信中途被击杀时向四周环形溅射（伤害走 bolt_damage 同一把回合缩放尺，幅度软一档）
static func fire_death_bolts(e) -> void:
	for i in range(maxi(1, e.death_bolt_count)):
		var bolt := EnemyBolt.acquire(e.get_parent())
		bolt.global_position = e.global_position
		bolt.direction = Vector2.from_angle(TAU * float(i) / float(maxi(1, e.death_bolt_count)))
		bolt.speed = 300.0 * e.bolt_speed_mult
		bolt.damage = e.bolt_damage * e.death_bolt_dmg_mult * (e.contact_damage / GameBalance.BOLT_DMG_BASE_REF)
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.6, 0.8)

## 点燃丹爆引信预警圈：半径 = 判定半径（同源），引信烧完圈正好填满
static func ignite_explode_ring(e) -> void:
	if e._explode_ring == null:
		e._explode_ring = AoeTelegraph.new()
		e._explode_ring.radius = e.explode_radius
		e.add_child(e._explode_ring)
	e._explode_ring.progress = 0.0
	e._explode_ring.visible = true

## 清理丹爆预警圈（自爆结算 / 引信中途被杀时调用）
static func clear_explode_ring(e) -> void:
	if e._explode_ring != null and is_instance_valid(e._explode_ring):
		e._explode_ring.queue_free()
	e._explode_ring = null

static func start_elite_slam(e) -> void:
	e._elite_slam_windup_t = e.slam_windup
	if e._elite_slam_ring == null:
		e._elite_slam_ring = AoeTelegraph.new()
		e.add_child(e._elite_slam_ring)
	# 半径每帧按当前字段钉死：变异升档 / 池化复用后字段会变，圈必须与本次判定同源
	e._elite_slam_ring.radius = e.slam_radius
	e._elite_slam_ring.progress = 0.0
	e._elite_slam_ring.visible = true
	AudioManager.play_sfx("enemy_fuse", 0.6)
	e.play_squash(Vector2(0.82, 1.2), 0.4)

static func resolve_elite_slam(e, player: Node2D) -> void:
	e._elite_slam_windup_t = -1.0
	if e._elite_slam_ring != null:
		e._elite_slam_ring.visible = false
	if e.dying:
		return
	JuiceEffect.spawn_shockwave(e.get_parent(), e.global_position, e.slam_radius, GameStyle.BAD)
	# 落点留震裂（纯视觉贴花，判定已在下方结算）
	GroundDecal.spawn(e.get_parent(), e.global_position, GroundDecal.Kind.CRACK, e.slam_radius)
	AudioManager.play_sfx("enemy_slam", 0.8)
	if player != null and player.global_position.distance_to(e.global_position) <= e.slam_radius:
		var slam_dmg := maxf(1.0, e.contact_damage * e.slam_dmg_mult)
		if player is Player:
			player.take_damage(slam_dmg, e.global_position)
		elif player.has_method("take_damage"):
			player.take_damage(slam_dmg)
	# 变异多段震地：首段结算后按 slam_echo_gap 间隔追加余波，半径逐段 ×slam_radius_grow。
	# 余波不再亮预警圈（首段圈已给出「以本体为圆心」的读法），只靠冲击环 + 裂痕 + 音效读段。
	# 震屏/反馈只在首段发一次（坑6：同一次挨打只许一处发反馈）。
	if e.slam_hits > 1:
		e._slam_echo_left = e.slam_hits - 1
		e._slam_echo_t = e.slam_echo_gap
		e._slam_echo_radius = e.slam_radius * e.slam_radius_grow

## 变异震地余波：按段间隔结算，半径逐段扩张；每段独立判玩家是否在圈内
static func tick_slam_echo(e, delta: float, player: Node2D) -> void:
	if e._slam_echo_t < 0.0:
		return
	e._slam_echo_t -= delta
	if e._slam_echo_t > 0.0:
		return
	if e._slam_echo_left <= 0:
		e._slam_echo_t = -1.0
		return
	if e.dying or e.get_parent() == null:
		e._slam_echo_t = -1.0
		return
	JuiceEffect.spawn_shockwave(e.get_parent(), e.global_position, e._slam_echo_radius, GameStyle.BAD)
	GroundDecal.spawn(e.get_parent(), e.global_position, GroundDecal.Kind.CRACK, e._slam_echo_radius)
	AudioManager.play_sfx("enemy_slam", 0.65, 1.08)
	if player != null and is_instance_valid(player) and player.global_position.distance_to(e.global_position) <= e._slam_echo_radius:
		var slam_dmg := maxf(1.0, e.contact_damage * e.slam_dmg_mult)
		if player is Player:
			player.take_damage(slam_dmg, e.global_position)
		elif player.has_method("take_damage"):
			player.take_damage(slam_dmg)
	e._slam_echo_left -= 1
	e._slam_echo_radius *= e.slam_radius_grow
	e._slam_echo_t = e.slam_echo_gap if e._slam_echo_left > 0 else -1.0

## 起手落石：锁定 rock_count 个落点，每点挂一个填满式预警圈（半径 = rock_radius 同源）。
## 首点锁玩家预判位（rock_lead），其余绕玩家均布 + 抖动散布 —— 原地站桩必吃首点，
## 绕圈跑位则可能踩进散布点，逼迫玩家做「短距离变向」而不是无脑绕大圈。
static func start_rock_barrage(e, player: Node2D) -> void:
	e._rock_windup_t = e.rock_windup
	e._rock_points.clear()
	e._clear_rock_rings()
	var lead: Vector2 = player.velocity * e.rock_lead if player is CharacterBody2D else Vector2.ZERO
	var first: Vector2 = player.global_position + lead
	e._rock_points.append(first)
	var count: int = maxi(e.rock_count, 1)
	for i in range(1, count):
		# 均布角 + 随机相位抖动：多点不叠在同一方向，玩家读得出「这片区域都要躲」
		var ang: float = TAU * float(i) / float(maxi(count - 1, 1)) + GameManager.rng.randf_range(-0.35, 0.35)
		var dist: float = GameManager.rng.randf_range(e.rock_spread * 0.45, e.rock_spread)
		e._rock_points.append(first + Vector2(cos(ang), sin(ang)) * dist)
	var parent = e.get_parent()
	if parent == null:
		return
	for p in e._rock_points:
		var ring := AoeTelegraph.new()
		ring.radius = e.rock_radius
		ring.progress = 0.0
		parent.add_child(ring)
		ring.global_position = p
		e._rock_rings.append(ring)
	e.play_squash(Vector2(0.84, 1.18), 0.3)
	AudioManager.play_sfx("enemy_fuse", 0.6)

## 落石结算：逐点判玩家是否在半径内；每点留焦痕与冲击环（画多大判多大）。
## 音效只在首点发一次：多点同帧叠 3~4 重 enemy_slam 会糊成一片噪音。
static func resolve_rock_barrage(e, player: Node2D) -> void:
	e._rock_windup_t = -1.0
	e._clear_rock_rings()
	if e.dying or e.get_parent() == null:
		return
	var first := true
	for p in e._rock_points:
		JuiceEffect.spawn_shockwave(e.get_parent(), p, e.rock_radius, GameStyle.BAD, 0.3)
		GroundDecal.spawn(e.get_parent(), p, GroundDecal.Kind.SCORCH, e.rock_radius * 0.6)
		if first:
			AudioManager.play_sfx("enemy_slam", 0.85)
			first = false
		if player != null and is_instance_valid(player) and player.global_position.distance_to(p) <= e.rock_radius:
			var rock_dmg := maxf(1.0, e.contact_damage * e.rock_dmg_mult)
			if player is Player:
				player.take_damage(rock_dmg, p)
			elif player.has_method("take_damage"):
				player.take_damage(rock_dmg)
	e._rock_points.clear()

## 清理落石预警圈（结算 / 死亡 / 池化复用前调用）
static func clear_rock_rings(e) -> void:
	for ring in e._rock_rings:
		if ring != null and is_instance_valid(ring):
			ring.queue_free()
	e._rock_rings.clear()

## 落域起手：锁定玩家脚下，亮填满式预警圈（半径 = field_radius 同源）
static func start_field_cast(e) -> void:
	e._field_windup_t = maxf(e.field_windup, 0.05)
	if e._field_ring == null:
		e._field_ring = AoeTelegraph.new()
		e.add_child(e._field_ring)
	e._field_ring.radius = e.field_radius
	e._field_ring.progress = 0.0
	e._field_ring.visible = true
	e._field_ring.global_position = e._field_target
	e.play_squash(Vector2(0.86, 1.16), e.field_windup)
	AudioManager.play_sfx("enemy_fuse", 0.55, 0.9)

## 落域：在锁定点铺一片持续伤害领域（复用 PoisonPool 骨架，血煞染色走 modulate 乘法）
static func drop_field(e) -> void:
	e._field_windup_t = -1.0
	if e._field_ring != null:
		e._field_ring.visible = false
	if e.dying or e.get_parent() == null:
		return
	var pool := PoisonPool.acquire(e.get_parent())
	pool.global_position = e._field_target
	pool.damage = maxf(1.0, e.contact_damage * e.field_dmg_mult)
	pool.duration = e.field_duration
	# 预警圈半径 = field_radius ⇒ 领域判定必须同源：scale_factor 驱动外观与碰撞一起缩
	pool.scale_factor = e.field_radius / PoisonPool.RADIUS
	pool.activate()
	# 血煞染色：modulate 是乘法，复用同一套毒潭几何不新增绘制路径。
	# 必须在 activate 之后写（池化复用的 _reset_defaults 不管 modulate，毒妖路径会显式归白）
	pool.modulate = Color(1.55, 0.45, 0.55)
	JuiceEffect.spawn_shockwave(e.get_parent(), e._field_target, e.field_radius, GameStyle.BAD, 0.28)
	AudioManager.play_sfx("enemy_poison", 1.0, 0.85)
	e.play_squash(Vector2(1.2, 0.8), 0.16)

## 起手投毒：锁定落点、亮预警圈、发蓄力形变与音效。
## 预警圈（AoeTelegraph）半径 = poison_radius 本身 ⇒ 圈画多大，落下的毒潭就判多大。
static func start_poison_cast(e) -> void:
	e._poison_windup_t = e.poison_windup
	if e._poison_ring == null:
		e._poison_ring = AoeTelegraph.new()
		e._poison_ring.radius = e.poison_radius
		e.add_child(e._poison_ring)
	e._poison_ring.progress = 0.0
	e._poison_ring.global_position = e._poison_target  ## 预警圈挂在锁定落点（毒潭将落于此，而非施法者脚下）
	e._poison_ring.visible = true
	e.play_squash(Vector2(0.86, 1.18), e.poison_windup)
	AudioManager.play_sfx("enemy_fuse", 0.55)

## 落潭：预警结束，在锁定落点铺一片毒潭（走对象池，见 PoisonPool）。
## 伤害按回合 × 危险度缩放（与接触伤害同一条尺子：WaveSpawner 在 _scale_to_wave 里注入）。
static func drop_poison(e) -> void:
	e._poison_windup_t = -1.0
	if e._poison_ring != null:
		e._poison_ring.visible = false
	if e.dying or e.get_parent() == null:
		return
	var pool := PoisonPool.acquire(e.get_parent())
	pool.global_position = e._poison_target
	pool.damage = maxf(1.0, e.poison_damage)
	pool.duration = e.poison_duration
	# 预警圈半径 = poison_radius ⇒ 落潭判定必须同源：scale_factor 驱动外观与碰撞一起缩
	pool.scale_factor = e.poison_radius / PoisonPool.RADIUS
	pool.activate()
	JuiceEffect.spawn_shockwave(e.get_parent(), e._poison_target, e.poison_radius, GameStyle.POISON, 0.28)
	AudioManager.play_sfx("enemy_poison", 1.0, GameManager.rng.randf_range(0.92, 1.08))
	e.play_squash(Vector2(1.2, 0.8), 0.16)

## 清理投毒预警圈（死亡 / 池化复用前调用）
static func clear_poison_ring(e) -> void:
	if e._poison_ring != null and is_instance_valid(e._poison_ring):
		e._poison_ring.queue_free()
	e._poison_ring = null
