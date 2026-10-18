class_name WaveSpawner
extends Node2D

## 回合状态机：WAITING(选武器) → FIGHT → CLEARING(清场吸附) → ALLOC(回合后悟道，有待加点才插队) → SHOP → 下一回合
## 第 20 波通关「渡劫成功」（双精英心魔劫）；可继续无尽
## FIGHT 的出口有两条（2026-10-12 起）：表走完，或「敌潮已尽」提前收尾 —— 判据见 _tide_spent()

enum Phase { WAITING, FIGHT, CLEARING, ALLOC, SHOP }

## 同屏上限：2026-10-10 打击感重塑由 55 下调至 35，2026-10-11 随「回合内总刷入预算」下调至 28，
## 2026-10-11 缩图后下调至 18（2026-10-15 扩图至 560，支持并发合围动态 cap）—— 密度与机动兼顾
@export var max_enemies: int = 18

# —— 回合内总刷入预算（2026-10-11 土豆兄弟式克制，曲线见 BalanceWave.wave_spawn_budget）——
## 预算只闸 _spawn_regular 的常规刷怪；精英/Boss 登场与分裂·产卵·召唤等衍生怪各有自己的上限，不占预算。
## 回合末把「预算 − 实际刷出」的差额交给灵韵结算折经验补差（BalanceEconomy.budget_compensation_exp），
## 击杀收入与旧口径基本持平 —— 只减压力不减经济。
var _budget_total: int = 0      ## 本回合预算总只数（已乘危险度/角色敌潮倍率）
var _budget_used: int = 0       ## 本回合已实际刷出只数
var _budget_exp_sum: float = 0.0  ## 已刷出敌人 exp_reward 累计（补差均值用）

# —— 提前清场（2026-10-12）——
## 「敌潮已尽」要连续满足这么久才收尾：分裂/产卵/召唤的幼体是 call_deferred 入树的，
## 留这一拍让下一只怪有机会落地，别让最后一只母体死亡的瞬间把整回合掐掉。
const EARLY_CLEAR_CONFIRM := 0.4
var _clear_hold: float = 0.0    ## 本回合已连续满足「敌潮已尽」的秒数

# —— 分批清剿制与并发推进（2026-10-15）——
var _batch_cooldown: float = 0.0    ## 清剿完一批后的喘息呼吸倒计时（秒）
var _batch_hold_time: float = 0.0    ## 当前批次在场对峙时长（秒，防挂机/中后期合围）
var _batch_in_combat: bool = false   ## 当前批次是否已进入交火对峙态（活跃敌数 > 1）

var phase: int = Phase.WAITING
## 回合号的唯一来源是 GameManager.wave_number。
## 这里只留一个只读访问器：以前本地也存了一份，只有 start_wave 会同步写，
## 「继续无尽」等路径只改单例那份，两边会悄悄漂移，所以改成同一份数据。
var wave_number: int:
	get:
		return GameManager.wave_number
var wave_timer: float = 0.0
var clear_timer: float = 0.0
var spawn_timer: float = 0.0
var elite_spawned: bool = false

# —— 敌人场景：怪种名单/配比/精英/金蟾的真话在 EnemyData（scripts/data/EnemyData.gd）——
## 这里只留按 scene_path 的运行时缓存（load 一次后复用），不再各自 preload 一份名单。
var _mob_scenes := {}            ## mob key -> PackedScene（_ready 时按 EnemyData.MOBS 构建）
var _elite_scenes: Array = []    ## 精英池场景，顺序 = EnemyData.ELITE_POOL 轮换顺序
var _boss_scene: PackedScene = preload("res://scenes/entities/BossEnemy.tscn")
var _looter_scene: PackedScene = preload("res://scenes/entities/JinChanEnemy.tscn")

var _boss_ref: BossEnemy = null  ## 本回合魔君引用（Boss 回合超时锁关轮询用）
var _overtime_noted: bool = false

# —— 性能基线采样（2026-10-17 性能优化专项阶段 0）——
## debug 构建 + 环境变量 PERF_BASELINE=1 时激活，FIGHT 期间每 2s 打一行 CSV 快照
## （波次/敌数/弹数/物理与逻辑耗时/draw call/图元/对象数），供优化前后真机对照归因。
## 只打 print 不改任何运行时行为；判据跑 headless（非 debug 或无环境变量）时零成本短路。
var _perf_sample_cd: float = 0.0
static var _perf_baseline_on: bool = false
static var _perf_baseline_checked: bool = false

# —— 拥挤档采样（2026-10-17 性能专项）——
## FIGHT 期间每 1s 采一次同屏敌数（含预警中的 SpawnIndicator），翻转 FxBudget.crowded。
## 1s 粒度足够（敌潮进出是秒级事件）：灯名额减半的生效/失效都由「下一次新掉落/新弹丸」
## 自然吃到，已有灯不强拆（避免画面灯忽明忽暗）。翻转沿才写静态 bool，零稳态成本。
var _crowd_tier_cd: float = 0.0

func _tick_crowd_tier(delta: float) -> void:
	_crowd_tier_cd -= delta
	if _crowd_tier_cd > 0.0:
		return
	_crowd_tier_cd = 1.0
	var count: int = GameManager.enemy_count + SpawnIndicator.active_count
	# 滞回判定（2026-10-17）：未拥挤 ≥24 进入，已拥挤 ≤20 退出，中间保持，
	# 敌量在阈值附近波动时 glow_intensity/灯名额不再每秒翻转（亮 UI 辉光脉冲 = UI 频闪观感）
	var want: bool
	if FxBudget.crowded:
		want = count > FxBudget.CROWDED_EXIT_THRESHOLD
	else:
		want = count >= FxBudget.CROWDED_ENEMY_THRESHOLD
	if want != FxBudget.crowded:
		FxBudget.crowded = want

func _perf_baseline_active() -> bool:
	if not _perf_baseline_checked:
		_perf_baseline_checked = true
		_perf_baseline_on = OS.is_debug_build() \
			and OS.get_environment("PERF_BASELINE") == "1" \
			and DisplayServer.get_name() != "headless"
	return _perf_baseline_on

## 2s 一次的快照打印：优化前后各采一份（W12 危险0 / W20 危险5 各 60s），
## TIME_*_PROCESS 是上一帧耗时（ms），draw/图元/对象为上一渲染帧渲染侧总量。
func _perf_sample(delta: float) -> void:
	_perf_sample_cd -= delta
	if _perf_sample_cd > 0.0:
		return
	_perf_sample_cd = 2.0
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var robjs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[PERF] w%02d fps=%d t=%.0f enemies=%d bolts=%d gems=%d proc=%.2fms phys=%.2fms draws=%d prims=%d robjs=%d nodes=%d" % [
		wave_number, Engine.get_frames_per_second(), wave_timer, GameManager.enemy_count,
		BladeProjectile.active_count + EnemyBolt.active_count,
		AstralGem.active_gem_count() + HealOrb.active_count,
		proc_ms, phys_ms, draws, prims, robjs, nodes,
	])

func _ready() -> void:
	GameManager.wave_spawner = self
	GameManager.shop_closed.connect(_on_shop_closed)
	GameManager.alloc_finished.connect(_on_alloc_finished)
	for key in EnemyData.mob_keys():
		_mob_scenes[key] = load(EnemyData.MOBS[key]["scene_path"])
	for elite_def in EnemyData.ELITE_POOL:
		_elite_scenes.append(load(elite_def["scene_path"]))

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	match phase:
		Phase.WAITING:
			if GameManager.run_started and GameManager.player != null:
				start_wave(1)
		Phase.FIGHT:
			_process_fight(delta)
			_tick_crowd_tier(delta)
			if _perf_baseline_active():
				_perf_sample(delta)
		Phase.CLEARING:
			clear_timer -= delta
			_drain_magnet_queue()
			if clear_timer <= 0.0:
				_open_shop()
		Phase.ALLOC:
			pass
		Phase.SHOP:
			pass


## 同屏敌人最终上限（2026-10-17 性能专项）：
## max_enemies（波次曲线）× 角色敌潮倍率 × 危险度倍率 × 无尽潮数倍率，
## 再夹 GameBalance.MAX_ENEMIES_HARD_CAP=48 绝对硬顶 —— 深层无尽极端构建
## （危险 5 × 潮数 2.0 可叠到 ~95）不再失控，常规 20 波（峰值 ~33）不受影响。
func _final_enemy_cap() -> int:
	var raw := int(round(float(max_enemies) * GameManager.enemy_count_mult
		* GameBalance.danger_count_mult(GameManager.danger_level)
		* GameBalance.endless_swarm_mult(wave_number)))
	return mini(raw, GameBalance.MAX_ENEMIES_HARD_CAP)

func _process_fight(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return

	wave_timer -= delta
	spawn_timer -= delta
	_batch_hold_time += delta
	if _batch_cooldown > 0.0:
		_batch_cooldown -= delta

	# Boss 回合超时锁关：魔君未死则敌潮不退（停表停刷，等 Boss 伏诛再进结算）
	if GameBalance.is_boss_wave(wave_number) and wave_timer <= 0.0:
		if _boss_still_alive():
			if not _overtime_noted:
				_overtime_noted = true
				GameManager.announcement_triggered.emit("◆ Boss未除 · 敌潮不退 ◆")
			return
		end_wave()
		return

	# 分批清剿制与并发合围刷新（2026-10-15；2026-10-16 阈值爬坡紧凑化）
	# 刷新阈值随波数爬坡（W1-3 ≤1 / W4-9 ≤2 / W10+ ≤3），不再全程死等「只剩一只」。
	# 进出呼吸间隙与清剿推进必须读同一个阈值，否则会出现「刚进间隙就判定可刷」的自激。
	if _budget_used < _budget_total:
		var refill_at := GameBalance.batch_refill_threshold(wave_number)
		var active_enemies: int = GameManager.enemy_count + SpawnIndicator.active_count
		if active_enemies > refill_at:
			_batch_in_combat = true
		elif _batch_in_combat and active_enemies <= refill_at:
			# 当前批次已基本清剿，进入呼吸喘息间隙（0.6s 供玩家拾取灵石与走位调整）
			_batch_in_combat = false
			_batch_cooldown = GameBalance.BATCH_CLEAR_COOLDOWN

		# 判定 1：清剿推进（主力路线）—— 场上存活 ≤ 阈值且呼吸间隙已过。
		# 阈值升到 3 后中后期会贴着同屏上限，故补 cap 闸（与判定 2 同款），超限时让判定 2 的
		# 对峙计时继续等，避免「刷出一批就顶破 cap」。
		if active_enemies <= refill_at and _batch_cooldown <= 0.0 and spawn_timer <= 0.0:
			var est_batch_clear := GameBalance.spawn_batch(wave_number, 0.5)
			var enemy_cap_clear := _final_enemy_cap()
			if active_enemies + est_batch_clear <= enemy_cap_clear:
				_spawn_regular(player)
				_batch_hold_time = 0.0
				spawn_timer = 0.2
		# 判定 2：并发合围（中后期路线）—— 第 6 波起对峙超时，且同屏未超上限时允许下一批合围
		elif wave_number >= GameBalance.CONCURRENT_BATCH_MIN_WAVE and _batch_hold_time >= GameBalance.BATCH_STALEMATE_TIMEOUT and spawn_timer <= 0.0:
			var enemy_cap := _final_enemy_cap()
			var est_batch := GameBalance.spawn_batch(wave_number, 0.5)
			if active_enemies + est_batch <= enemy_cap:
				_spawn_regular(player)
				_batch_hold_time = 0.0
				spawn_timer = 1.0

	# 精英回合：第 5/15 波；Boss 回合（第 10/20 波）改由魔君登场
	var is_elite_wave := _is_elite_wave(wave_number)
	if not _is_boss_wave(wave_number) and is_elite_wave and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_elite(player)

	# 固定 Boss 回合：开场 1.5s 后魔君破阵（血条同步上屏）
	if _is_boss_wave(wave_number) and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_boss(player)

	# 金蟾：回合中限时刷出的逃跑宝藏怪（土豆兄弟 Looter 对应位）
	if _looter_pending and not _looter_done and wave_timer <= wave_duration(wave_number) * EnemyData.LOOTER_DEF["at_pct"]:
		_looter_done = true
		_spawn_looter(player)

	# 提前清场：本回合敌潮已全部刷入、且场上再无活妖 ⇒ 不等表走完就收尾，余下秒数折成金币。
	# 闸只认「预算已尽」这一条：没刷完就提前收，等于把省下的那截时间对应的击杀进项一起收走，
	# 那是扣钱不是奖励。曲线见 BalanceEconomy.early_clear_stones。
	if _tide_spent():
		_clear_hold += delta
		if _clear_hold >= EARLY_CLEAR_CONFIRM:
			end_wave(wave_timer)
			return
	else:
		_clear_hold = 0.0

	if wave_timer <= 0.0:
		end_wave()

## 「敌潮已尽」：本回合刷怪预算全部刷入 + 场上一个活妖都没有（含尸体：dying 的还在登记表里，
## 所以要等塌缩动画落定才算清干净）。精英/魔君还没到场的头 1.5 秒一律不算，
## 且若场上还有正在凝聚的妖气指示器（SpawnIndicator）也不算清场。
func _tide_spent() -> bool:
	if _budget_used <= 0 or _budget_used < _budget_total:
		return false
	if not elite_spawned and (_is_elite_wave(wave_number) or _is_boss_wave(wave_number)):
		return false
	if _indicators_pending():
		return false
	return GameManager.enemy_count <= 0

func _indicators_pending() -> bool:
	return SpawnIndicator.active_count > 0

# ---------------- 本波剩余敌数读数（HUD「余妖 N/M」唯一数据源） ----------------
## 与 _tide_spent 逐枝同源的「还剩多少妖要对付」：还没刷入的预算 + 正在凝聚的预警 +
## 场上活妖（含 dying 尸体，登记表语义一致）+ 还没到场的精英/魔君 + 有档期未刷的金蟾。
## 只组合现成字段、不新增状态；判 N==0 与「敌潮已尽」永不错位（渲染层只读状态）。
func wave_left_count() -> int:
	var left: int = maxi(_budget_total - _budget_used, 0)
	left += SpawnIndicator.active_count
	left += GameManager.enemy_count
	if not elite_spawned and (_is_elite_wave(wave_number) or _is_boss_wave(wave_number)):
		left += 1
	if _looter_pending and not _looter_done:
		left += 1
	return left

## 本波敌数总额 M：预算只数 + 精英/Boss +1 + 金蟾档期 +1（与 wave_left_count 同一口径）。
func wave_total_count() -> int:
	var total: int = _budget_total
	if _is_elite_wave(wave_number) or _is_boss_wave(wave_number):
		total += 1
	if _looter_pending:
		total += 1
	return total

## 波长曲线只是 GameBalance 的一层转发，保留本方法是因为 UI/内部多处按它排程
func wave_duration(n: int) -> float:
	return GameBalance.wave_duration(n)

## 精英回合判定（曲线在 GameBalance）：第 5/15 波，无尽模式 20 回合后每 3 波（Boss 回合让位）
func _is_elite_wave(n: int) -> bool:
	return GameBalance.is_elite_wave(n, GameManager.endless_mode)

## Boss 回合判定（固定关卡）：第 10/20 波，无尽每 5 波
func _is_boss_wave(n: int) -> bool:
	return GameBalance.is_boss_wave(n)

func start_wave(n: int) -> void:
	GameManager.wave_number = n
	GameManager.wave_changed.emit(n)
	max_enemies = GameBalance.max_enemies_cap(n)
	elite_spawned = false
	_boss_ref = null
	_overtime_noted = false
	wave_timer = wave_duration(n)
	spawn_timer = 0.6
	_batch_cooldown = 0.0
	_batch_hold_time = 0.0
	_batch_in_combat = false
	phase = Phase.FIGHT
	# 本回合刷怪预算：危险度与角色敌潮倍率与同屏上限同源同乘
	_budget_total = int(round(float(GameBalance.wave_spawn_budget(n)) * GameBalance.danger_count_mult(GameManager.danger_level) * GameManager.enemy_count_mult))
	_budget_used = 0
	_budget_exp_sum = 0.0
	_clear_hold = 0.0
	# 金蟾档期：每回合开场抽定（EnemyData.LOOTER_DEF），回合中 60% 处登场
	_looter_pending = n >= EnemyData.LOOTER_DEF["min_wave"] and GameManager.rng.randf() < EnemyData.LOOTER_DEF["chance"]
	_looter_done = false
	_spawn_chests()
	if _is_boss_wave(n):
		GameManager.announcement_triggered.emit("◆ 第 %d 波 · Boss来袭 ◆" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	elif _is_elite_wave(n):
		GameManager.announcement_triggered.emit("◆ 第 %d 波 · 敌潮来袭 ◆" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	else:
		GameManager.announcement_triggered.emit("◆ 第 %d 波 · 敌潮来袭 ◆" % n)
		AudioManager.play_sfx("wave_start", 0.9)
		AudioManager.play_bgm_key("battle")
	# 中断续玩：波次边界快照（新开局第一波 + 商店关进下一波共用这条）
	RunSave.autosave_current(GameManager)

## 远离玩家出生点采样：全图随机抽一点，距玩家太近就沿径向推开再夹回场内。
## 五处刷怪口（常规怪/精英/金蟾/Boss/藏宝匣）共用这一份实现，参数（内缩/安全距离/推开）
## 在 BalanceWave 的「刷怪出生点几何」段分档登记 —— 调出生安全距离只改那里。
## 随机调用次数必须保持与原五份内联样板一致：每点 2 次 randf_range，方向退化时才多 1 次 randf
## （同种子下的刷怪分布是 BalanceSimCheck 的钉死对象，多一次调用整张分布就变了）。
## push_dir 传非零向量时走「固定方向推开」（藏宝匣：向右推开，不取径向）。
func _spawn_pos_away_from_player(player: Node2D, inset: float, min_dist: float, push: float,
		fixed_push_dir: Vector2 = Vector2.ZERO) -> Vector2:
	var lim: float = GameManager.MAP_HALF_EXTENT - inset
	var p_pos: Vector2 = player.global_position
	var pos := Vector2(
		GameManager.rng.randf_range(-lim, lim),
		GameManager.rng.randf_range(-lim, lim)
	)
	if pos.distance_to(p_pos) < min_dist:
		var push_dir := fixed_push_dir if not fixed_push_dir.is_zero_approx() else (pos - p_pos).normalized()
		if push_dir.is_zero_approx():
			push_dir = Vector2.RIGHT.rotated(GameManager.rng.randf() * TAU)
		pos = (p_pos + push_dir * push).clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	return pos

## 藏宝匣：每回合在竞技场随机位置刷一批，诱导玩家为补给冒险走位。
## 数量 = 基础曲线 + 「宝箱数量」（加点/道具同一字段，见 BalanceChest.chest_count），
## 每口匣子单独抽档（木/铜/玉），权重吃「宝箱品质」与已有的福缘 —— 抽档走 GameManager.rng，
## 全局 randf() 会让判据钉不住同一批匣子（铁律 3）。
func _spawn_chests() -> void:
	var player = GameManager.player
	if player == null:
		return
	var count := GameBalance.chest_count(wave_number, GameManager.chest_count_bonus)
	var tier_w: Array[float] = GameBalance.chest_tier_weights(GameManager.chest_quality, GameManager.luck)
	for i in range(count):
		var chest := SpiritChest.new()
		# tier 必须在 add_child 之前写好：_ready 靠它定贴图/体型/击数/配色
		chest.tier = GameBalance.weighted_pick_index(tier_w, GameManager.rng.randf())
		# 别贴脸刷：推开走固定向右（不取径向），再夹回场内，数量堆上去后不顶出竞技场边界
		var pos := _spawn_pos_away_from_player(player,
			GameBalance.SPAWN_INSET_CHEST, GameBalance.SPAWN_MIN_DIST_CHEST, GameBalance.SPAWN_PUSH_CHEST,
			Vector2(GameBalance.SPAWN_PUSH_CHEST, 0.0))
		chest.global_position = pos
		get_parent().add_child(chest)

func end_wave(early_secs: float = 0.0) -> void:
	phase = Phase.CLEARING
	# 拥挤档退出（2026-10-17）：波末清场后灯名额/glow 回满档，回合间商店照常亮堂
	FxBudget.crowded = false
	clear_timer = 1.0
	AudioManager.play_sfx("wave_clear", 0.9)
	GameManager.announcement_triggered.emit("第 %d 波敌潮平息" % wave_number)
	# 灵韵结算：无偿金币+经验，随后复利增长；刷怪预算没花完的部分折经验找平（击杀收入不因减潮缩水）
	var budget_shortfall := maxi(0, _budget_total - _budget_used)
	var avg_exp := (_budget_exp_sum / float(_budget_used)) if _budget_used > 0 else 0.0
	# 提前清场的余时赏与灵韵同一次到账、同一句播报：横幅只有一个 Label，同帧发两句只会留下
	# 后一句 —— 分成两条等于把「收益到账」那个数吞掉。early_secs 传 0（表走完/判据直接调
	# end_wave()）时这条一分不给，与改动前逐枚金币等价。
	var early_stones := GameBalance.early_clear_stones(early_secs)
	GameManager.apply_harvest(GameBalance.budget_compensation_exp(budget_shortfall, avg_exp), early_secs)
	if early_stones > 0:
		var p: Node2D = GameManager.player
		if p != null and is_instance_valid(p):
			DamageNumber.spawn(get_parent(), p.global_position + Vector2(0.0, -34.0),
				early_stones, false, "+%d 金币" % early_stones)
	# 余怪消散（不掉落）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	# 没砸开的藏宝匣同一口径收走：每回合重刷一批（数量曲线见 BalanceChest），不留档否则场地越打越满是箱子。
	# 必须与上面那个 for 平级：这两轮循环原先缩进了 enemies 循环的体内 ⇒ 场上没怪时
	# 匣子与炮台一个都不收（#24 刷怪预算把同屏顶满的旧口径改掉之后，回合末清空成了常态，
	# 这条静默路径才露出来：ChestTargetingCheck 第 5 组三条一起报红）。
	for chest in get_tree().get_nodes_in_group("chests"):
		if chest is SpiritChest:
			(chest as SpiritChest).dissolve()
	# 回合末收回场上机关炮台
	for turret in get_tree().get_nodes_in_group("turrets"):
		if turret is TurretUnit:
			turret.dismiss()
	# 地上金币全部吸进袖中；残丹/回春葫芦走结算（贴身才入口，没捡到的回不上的折金币）
	# 磁吸风暴分帧（2026-10-17 性能专项）：旧版同一帧把最多 140 颗宝石全部切进 60Hz
	# 物理回调 + 各挂 Line2D 拖尾，正是回合末清场瞬间的掉帧尖峰来源。
	# 改为进 CLEARING 后每物理帧放行 ≤16 颗（140 颗约 9 帧 ≈ 0.15s 摊完，肉眼不可辨），
	# 候选表按出生序（Dictionary 保插入序），最旧的先进磁吸。
	var player = GameManager.player
	if player != null:
		_collect_gems_batched(player)

# —— 回合末磁吸分帧（每物理帧 ≤ MAGNET_BATCH_PER_FRAME 颗）——
const MAGNET_BATCH_PER_FRAME := 16
var _magnet_queue: Array = []   ## 待磁吸宝石队列（出生序）；CLEARING 期间每帧消化一批

func _collect_gems_batched(player: Node2D) -> void:
	_magnet_queue.clear()
	for gem in get_tree().get_nodes_in_group("gems"):
		if gem is HealOrb:
			(gem as HealOrb).settle_for_wave_end(player)
		elif gem.has_method("magnet_to") and gem.target_player == null:
			_magnet_queue.append(gem)

## 每物理帧放行一批进磁吸态（≤16 颗）：把「同帧 140 颗齐开物理回调」摊成 9 帧，
# 队列里的宝石可能已被玩家顺手捡走（物理拾取先于本帧），进队列前逐颗验活。
func _drain_magnet_queue() -> void:
	if _magnet_queue.is_empty():
		return
	var player = GameManager.player
	if player == null or not is_instance_valid(player):
		_magnet_queue.clear()
		return
	var batch := mini(MAGNET_BATCH_PER_FRAME, _magnet_queue.size())
	for i in range(batch):
		var gem = _magnet_queue[i]
		if is_instance_valid(gem) and gem.target_player == null:
			gem.magnet_to(player)
	_magnet_queue = _magnet_queue.slice(batch)

func _open_shop() -> void:
	if wave_number >= GameManager.VICTORY_WAVE and not GameManager.endless_mode:
		phase = Phase.SHOP
		var player = GameManager.player
		if DisplayServer.get_name() != "headless" and player != null and is_instance_valid(player) and player.has_method("play_victory_sequence"):
			player.play_victory_sequence()
		else:
			GameManager.trigger_game_over(true)
		return
	_enter_wave_break()

func open_shop() -> void:
	## 结算界面「继续无尽」入口
	if phase == Phase.SHOP:
		_enter_wave_break()

## 回合间隙的唯一闸口：先清掉攒下的悟道点数，加完了才轮到金币阁。
## 战斗中的升级只攒点不弹面板（2026-10-09 用户指令：「在战斗过程中触发加点的体验不好」）。
func _enter_wave_break() -> void:
	if GameManager.has_pending_upgrades():
		phase = Phase.ALLOC
		GameManager.open_alloc_session()
		# 中断续玩：悟道面板开着时退出，恢复时原样重建候选卡（不重 roll）
		RunSave.autosave_current(GameManager)
		return
	phase = Phase.SHOP
	_open_shop_inner()

## 点数加完：接着开商店（alloc_finished 由 GameManager 发，UI 不直接指挥流程）
func _on_alloc_finished() -> void:
	if phase != Phase.ALLOC:
		return
	phase = Phase.SHOP
	_open_shop_inner()

func _open_shop_inner() -> void:
	AudioManager.play_bgm_key("shop")
	GameManager.roll_shop(true)
	# 中断续玩：货架 roll 定格后快照（含锁定项），商店开着退出恢复时原样重建
	RunSave.autosave_current(GameManager)
	GameManager.shop_opened.emit()

func _on_shop_closed() -> void:
	start_wave(wave_number + 1)

func _spawn_regular(player: Node2D) -> void:
	# 回合内总刷入预算：耗尽即停手（回合时长照常跑满，场上越打越空）
	if _budget_used >= _budget_total:
		return
	# 狂战蛮修等角色的 enemy_count_mult 与危险度的 danger_count_mult 同时放大同屏上限与每回合刷怪量；
	# 无尽深层（>20 波）再乘 endless_swarm_mult（曲线在 BalanceWave，正常局恒 1.0）
	var enemy_cap := _final_enemy_cap()
	if GameManager.enemy_count >= enemy_cap:
		return

	var count := int(round(float(GameBalance.spawn_batch(wave_number, GameManager.rng.randf())) * GameManager.enemy_count_mult * GameBalance.danger_count_mult(GameManager.danger_level)))
	# 最后一轮允许部分兑现：预算剩几只刷几只，且不超过同屏上限容限
	count = mini(count, _budget_total - _budget_used)
	count = mini(count, enemy_cap - GameManager.enemy_count)
	if count <= 0:
		return
	for i in range(count):
		# 土豆兄弟式全图随机出生 + 远离玩家安全区保护（参数见 BalanceWave 刷怪出生点几何）
		var pos := _spawn_pos_away_from_player(player,
			GameBalance.SPAWN_INSET_MOB, GameBalance.SPAWN_MIN_DIST_MOB, GameBalance.SPAWN_PUSH_MOB)

		var key := EnemyData.pick_scene_key(wave_number, GameManager.rng.randf())
		var enemy_scene: PackedScene = _mob_scenes.get(key, _mob_scenes["slime"])
		# 提前锁定预算名额与经验累计，防止 1.1s 预警延迟期间超额派发
		_budget_used += 1
		EnemyCodex.record_seen(key)
		_schedule_enemy_spawn(enemy_scene, pos, false)

func _schedule_enemy_spawn(scene: PackedScene, pos: Vector2, is_elite: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var indicator := SpawnIndicator.new()
	indicator.global_position = pos
	indicator.is_elite = is_elite
	indicator.spawn_callback = func():
		if phase != Phase.FIGHT:
			return
		# 敌人走对象池（2026-10-13）：死亡/清场出树休眠的个体优先复用，刷怪不再 instantiate
		var enemy := EnemyBase.acquire_or_new(scene)
		if enemy == null:
			return
		enemy.reset_for_reuse()
		enemy.global_position = pos
		enemy.add_to_group("enemies")
		_scale_to_wave(enemy)
		enemy.activate()
		parent.add_child(enemy)
		# 补差均值与实际掉落同口径：小怪 exp_reward 过 mob_kill_exp 补偿倍率（EnemyBase._die 同一出口），
		# 否则预算缺口 × 原值均值会少算玩家的实际单怪收入
		_budget_exp_sum += float(GameBalance.mob_kill_exp(enemy.exp_reward))
		# 出场弹性缩放动画 (0.4 -> 1.0)
		enemy.scale = Vector2.ONE * 0.4
		var tw := enemy.create_tween()
		tw.tween_property(enemy, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	parent.add_child(indicator)

## 敌人配比：真话在 EnemyData（怪种行 + 爬坡/闸门 + 金蟾档期），这里只留状态位与调度。
## 口径沿革（2026-10-08）：旧写法是「累计带 + 回合闸门」，闸门一开邪修直接吃掉整段
## （第 8 波突然 27% 刷火球怪），而闸门未开时下一格白捡（第 5~7 波雷兽 42%）；
## 现在火球怪从第 1 波就占自己那一格、按爬坡线涨到上沿，雷兽/花妖/史莱姆回到各自该有的份额。
var _looter_pending: bool = false  ## 本回合是否有金蟾档期（start_wave 抽定）
var _looter_done: bool = false     ## 本回合金蟾是否已刷

## 邪修在第 wave 波占到的累计带上沿（纯函数，单测直接钉这条爬坡线；转发 EnemyData）
static func xiexiu_edge(wave: int) -> float:
	return EnemyData.xiexiu_edge(wave)

## 毒妖在第 wave 波占到的累计带上沿（与花妖共段切走固定比例；转发 EnemyData）
static func duyao_edge(wave: int) -> float:
	return EnemyData.duyao_edge(wave)

## 配比判定：纯函数（给定回合与 roll ∈ [0,1) 返回怪种 key）；转发 EnemyData
static func pick_scene_key(wave: int, roll: float) -> String:
	return EnemyData.pick_scene_key(wave, roll)

## 分段带判定（不含登场/主打头部份额）；转发 EnemyData，供单测按带子口径钉线
static func pick_band_key(wave: int, roll: float) -> String:
	return EnemyData.pick_band_key(wave, roll)

## 精英池轮换：铁甲魔傀（坦克）→ 赤雷兽（突进）→ 剑煞邪修（三连剑气），依次登场
## （池顺序与称号都在 EnemyData.ELITE_POOL，这里只按出场次数取模）
var _elite_spawn_count: int = 0

func _spawn_elite(player: Node2D) -> void:
	var pos := _spawn_pos_away_from_player(player,
		GameBalance.SPAWN_INSET_ELITE, GameBalance.SPAWN_MIN_DIST_ELITE, GameBalance.SPAWN_PUSH_ELITE)

	var pool: Array = _elite_scenes
	var elite_idx := _elite_spawn_count % pool.size()
	var scene: PackedScene = pool[elite_idx]
	var elite_title: String = EnemyData.ELITE_POOL[elite_idx]["title"]
	_elite_spawn_count += 1
	EnemyCodex.record_seen(String(EnemyData.ELITE_POOL[elite_idx]["id"]))

	var parent := get_parent()
	if parent == null:
		return
	var indicator := SpawnIndicator.new()
	indicator.global_position = pos
	indicator.is_elite = true
	indicator.spawn_callback = func():
		if phase != Phase.FIGHT:
			return
		var elite := EnemyBase.acquire_or_new(scene)
		if elite == null:
			return
		elite.reset_for_reuse()
		elite.global_position = pos
		elite.add_to_group("enemies")
		_scale_to_wave(elite)
		elite.activate()
		parent.add_child(elite)
		GameManager.announcement_triggered.emit("◆ %s突入战场！" % elite_title)
		GameManager.shake_camera(5.0, 0.25)
	parent.add_child(indicator)

## 金蟾：在远离玩家的位置刷一只携宝金蟾（击杀爆金币，见 EnemyBase.stone_reward）。
## 不占刷怪预算、不吃同屏上限；它活着时「提前清场」会等它（它是活体敌人），
## 追不上也没关系——回合表走完照常收尾，金蟾只是中场彩蛋。
func _spawn_looter(player: Node2D) -> void:
	var pos := _spawn_pos_away_from_player(player,
		GameBalance.SPAWN_INSET_ELITE, GameBalance.SPAWN_MIN_DIST_ELITE, GameBalance.SPAWN_PUSH_ELITE)
	_schedule_enemy_spawn(_looter_scene, pos, false)
	EnemyCodex.record_seen("jinchan")
	GameManager.announcement_triggered.emit("◆ 金蟾携宝现身 · 击杀爆金币 ◆")

## 随波数成长敌人属性（曲线见 GameBalance），同种怪个体 ±10% 浮动；危险度再整体抬血/攻。
## 移速也吃 ±12% 方差（2026-10-12，土豆兄弟式快慢梯队：同屏同种怪不再整齐划一）。
func _scale_to_wave(enemy: EnemyBase) -> void:
	var variance: float = GameManager.rng.randf_range(
		1.0 - GameBalance.ENEMY_STAT_VARIANCE,
		1.0 + GameBalance.ENEMY_STAT_VARIANCE
	)
	enemy.max_hp = ceilf(enemy.max_hp * GameBalance.enemy_hp_mult(wave_number) * variance * GameBalance.danger_hp_mult(GameManager.danger_level))
	enemy.contact_damage = ceilf(enemy.contact_damage * GameBalance.enemy_dmg_mult(wave_number) * variance * GameBalance.danger_dmg_mult(GameManager.danger_level))
	enemy.move_speed *= GameManager.rng.randf_range(
		1.0 - GameBalance.ENEMY_SPEED_VARIANCE,
		1.0 + GameBalance.ENEMY_SPEED_VARIANCE
	)
	# 灵医奶量 / 金蟾金币与回合曲线同源（BalanceWave），场景里只占位
	if enemy.heal_interval > 0.0:
		enemy.heal_amount = GameBalance.healer_amount(wave_number)
	if enemy.stone_reward > 0:
		enemy.stone_reward = GameBalance.looter_stone_reward(wave_number)
		# 毒妖投毒：每跳伤害与半径跟着回合曲线走（场景里只占位）
		if enemy.poison_interval > 0.0:
			enemy.poison_damage = GameBalance.poison_area_damage(wave_number)
			enemy.poison_radius = GameBalance.poison_radius(wave_number)

## 固定 Boss 关：生命/伤害按 GameBalance 回合公式注入，称号与演出随关卡推进。
## 登场演出（2026-10-14）：2 秒魔轮凝聚异象 → 破阵弹入，血条随本体 _ready 上屏。
## 旧写法直接 add_child，只有横幅 + 震屏，连小怪的凝聚符印都没有。
func _spawn_boss(player: Node2D) -> void:
	var pos := _spawn_pos_away_from_player(player,
		GameBalance.SPAWN_INSET_BOSS, GameBalance.SPAWN_MIN_DIST_BOSS, GameBalance.SPAWN_PUSH_BOSS)
	EnemyCodex.record_seen("boss")

	var parent := get_parent()
	if parent == null:
		return

	var indicator := SpawnIndicator.new()
	indicator.global_position = pos
	indicator.is_boss = true
	indicator.spawn_callback = func():
		if phase != Phase.FIGHT:
			return
		var boss := _boss_scene.instantiate() as BossEnemy
		if boss == null:
			return
		boss.global_position = pos
		boss.add_to_group("enemies")
		boss.add_to_group("boss")
		boss.max_hp = GameBalance.boss_hp(wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level)
		boss.contact_damage = GameBalance.boss_contact_damage(wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level)
		boss.attack_interval = GameBalance.BOSS_ATTACK_INTERVAL
		boss.final_boss = wave_number >= GameManager.VICTORY_WAVE
		boss.boss_title = _boss_title()
		_boss_ref = boss
		parent.add_child(boss)
		# 登场演出（T-5.4）：地面魔印大阵预警落位后，dissolve 逆向凝聚成形，爆发冲击环与创伤短震
		boss.play_spawn_sequence(func():
			GameManager.announcement_triggered.emit(_boss_announcement())
		)
	parent.add_child(indicator)

## 本回合魔君存活与否（Boss 回合超时锁关的判据）
func _boss_still_alive() -> bool:
	return _boss_ref != null and is_instance_valid(_boss_ref) and not _boss_ref.dying

func _boss_title() -> String:
	if wave_number > GameManager.VICTORY_WAVE:
		return "回响Boss"     ## 无尽回合的轮回魔君
	if wave_number >= GameManager.VICTORY_WAVE:
		return "最终Boss"     ## 第 20 波最终关
	return "火焰Boss"         ## 第 10 回合首个 Boss 关

func _boss_announcement() -> String:
	if wave_number == GameManager.VICTORY_WAVE:
		return "◆ 最终Boss战 · 最终Boss出现！"
	if wave_number > GameManager.VICTORY_WAVE:
		return "◆ 回响Boss · 再次出现！"
	return "◆ Boss回合 · 火焰Boss突入战场！"
