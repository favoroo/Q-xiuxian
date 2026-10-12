class_name WaveSpawner
extends Node2D

## 波次状态机：WAITING(选法器) → FIGHT → CLEARING(清场吸附) → ALLOC(波后悟道，有待加点才插队) → SHOP → 下一波
## 第 20 波通关「渡劫成功」（双精英心魔劫）；可继续无尽
## FIGHT 的出口有两条（2026-10-12 起）：表走完，或「妖潮已尽」提前收尾 —— 判据见 _tide_spent()

enum Phase { WAITING, FIGHT, CLEARING, ALLOC, SHOP }

## 同屏上限：2026-10-10 打击感重塑由 55 下调至 35，2026-10-11 随「波内总刷入预算」下调至 28，
## 2026-10-11 缩图（半场 680→500）后再下调至 18 —— 地图更小、单怪更厚，密度由「少而硬」维持
@export var max_enemies: int = 18

# —— 波内总刷入预算（2026-10-11 土豆兄弟式克制，曲线见 BalanceWave.wave_spawn_budget）——
## 预算只闸 _spawn_regular 的常规刷怪；精英/Boss 登场与分裂·产卵·召唤等衍生怪各有自己的上限，不占预算。
## 波末把「预算 − 实际刷出」的差额交给灵韵结算折经验补差（BalanceEconomy.budget_compensation_exp），
## 击杀收入与旧口径基本持平 —— 只减压力不减经济。
var _budget_total: int = 0      ## 本波预算总只数（已乘危险度/角色妖潮倍率）
var _budget_used: int = 0       ## 本波已实际刷出只数
var _budget_exp_sum: float = 0.0  ## 已刷出敌人 exp_reward 累计（补差均值用）

# —— 提前清场（2026-10-12）——
## 「妖潮已尽」要连续满足这么久才收尾：分裂/产卵/召唤的幼体是 call_deferred 入树的，
## 留这一拍让下一只怪有机会落地，别让最后一只母体死亡的瞬间把整波掐掉。
const EARLY_CLEAR_CONFIRM := 0.4
var _clear_hold: float = 0.0    ## 本波已连续满足「妖潮已尽」的秒数

var phase: int = Phase.WAITING
## 波次号的唯一来源是 GameManager.wave_number。
## 这里只留一个只读访问器：以前本地也存了一份，只有 start_wave 会同步写，
## 「继续无尽」等路径只改单例那份，两边会悄悄漂移，所以改成同一份数据。
var wave_number: int:
	get:
		return GameManager.wave_number
var wave_timer: float = 0.0
var clear_timer: float = 0.0
var spawn_timer: float = 0.0
var elite_spawned: bool = false

var slime_scene: PackedScene = preload("res://scenes/entities/SlimeEnemy.tscn")
var flower_scene: PackedScene = preload("res://scenes/entities/FlowerEnemy.tscn")
var golem_scene: PackedScene = preload("res://scenes/entities/GolemEnemy.tscn")
var leibeast_scene: PackedScene = preload("res://scenes/entities/LeiBeastEnemy.tscn")
var xiexiu_scene: PackedScene = preload("res://scenes/entities/XieXiuEnemy.tscn")
var danbao_scene: PackedScene = preload("res://scenes/entities/DanBaoEnemy.tscn")
var boss_scene: PackedScene = preload("res://scenes/entities/BossEnemy.tscn")
var fengqun_scene: PackedScene = preload("res://scenes/entities/FengQunEnemy.tscn")
var xueyong_scene: PackedScene = preload("res://scenes/entities/XueYongEnemy.tscn")
var guyao_scene: PackedScene = preload("res://scenes/entities/GuYaoEnemy.tscn")
var yingmei_scene: PackedScene = preload("res://scenes/entities/YingMeiEnemy.tscn")
var zhumu_scene: PackedScene = preload("res://scenes/entities/ZhuMuEnemy.tscn")
var chilei_elite_scene: PackedScene = preload("res://scenes/entities/ChileiEliteEnemy.tscn")
var jiansha_elite_scene: PackedScene = preload("res://scenes/entities/JianshaEliteEnemy.tscn")

var _boss_ref: BossEnemy = null  ## 本波魔君引用（Boss 波超时锁关轮询用）
var _overtime_noted: bool = false

func _ready() -> void:
	GameManager.wave_spawner = self
	GameManager.shop_closed.connect(_on_shop_closed)
	GameManager.alloc_finished.connect(_on_alloc_finished)

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	match phase:
		Phase.WAITING:
			if GameManager.run_started and GameManager.player != null:
				start_wave(1)
		Phase.FIGHT:
			_process_fight(delta)
		Phase.CLEARING:
			clear_timer -= delta
			if clear_timer <= 0.0:
				_open_shop()
		Phase.ALLOC:
			pass
		Phase.SHOP:
			pass

func _process_fight(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return

	wave_timer -= delta
	spawn_timer -= delta

	# Boss 波超时锁关：魔君未死则妖潮不退（停表停刷，等 Boss 伏诛再进结算）
	if GameBalance.is_boss_wave(wave_number) and wave_timer <= 0.0:
		if _boss_still_alive():
			if not _overtime_noted:
				_overtime_noted = true
				GameManager.announcement_triggered.emit("⚠ Boss未除 · 敌潮不退 ⚠")
			return
		end_wave()
		return

	if spawn_timer <= 0.0:
		spawn_timer = GameBalance.spawn_interval(wave_number)
		_spawn_regular(player)

	# 精英波：第 5/15 波；Boss 波（第 10/20 波）改由魔君登场
	var is_elite_wave := _is_elite_wave(wave_number)
	if not _is_boss_wave(wave_number) and is_elite_wave and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_elite(player)

	# 固定 Boss 波：开场 1.5s 后魔君破阵（血条同步上屏）
	if _is_boss_wave(wave_number) and not elite_spawned and wave_timer < wave_duration(wave_number) - 1.5:
		elite_spawned = true
		_spawn_boss(player)

	# 提前清场：本波妖潮已全部刷入、且场上再无活妖 ⇒ 不等表走完就收尾，余下秒数折成金币。
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

## 「妖潮已尽」：本波刷怪预算全部刷入 + 场上一个活妖都没有（含尸体：dying 的还在登记表里，
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
	var p := get_parent()
	if p == null:
		return false
	for child in p.get_children():
		if child is SpawnIndicator:
			return true
	return false

## 波长曲线只是 GameBalance 的一层转发，保留本方法是因为 UI/内部多处按它排程
func wave_duration(n: int) -> float:
	return GameBalance.wave_duration(n)

## 精英波判定（曲线在 GameBalance）：第 5/15 波，无尽模式 20 波后每 3 波（Boss 波让位）
func _is_elite_wave(n: int) -> bool:
	return GameBalance.is_elite_wave(n, GameManager.endless_mode)

## Boss 波判定（固定关卡）：第 10/20 波，无尽每 10 波
func _is_boss_wave(n: int) -> bool:
	return GameBalance.is_boss_wave(n)

func start_wave(n: int) -> void:
	GameManager.wave_number = n
	GameManager.wave_changed.emit(n)
	elite_spawned = false
	_boss_ref = null
	_overtime_noted = false
	wave_timer = wave_duration(n)
	spawn_timer = 0.6
	phase = Phase.FIGHT
	# 本波刷怪预算：危险度与角色妖潮倍率与同屏上限同源同乘
	_budget_total = int(round(float(GameBalance.wave_spawn_budget(n)) * GameBalance.danger_count_mult(GameManager.danger_level) * GameManager.enemy_count_mult))
	_budget_used = 0
	_budget_exp_sum = 0.0
	_clear_hold = 0.0
	_spawn_chests()
	if _is_boss_wave(n):
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · Boss来袭 ✦" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	elif _is_elite_wave(n):
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 敌潮来袭 ✦" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	else:
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 敌潮来袭 ✦" % n)
		AudioManager.play_sfx("wave_start", 0.9)
		AudioManager.play_bgm_key("battle")

## 藏宝匣：每波在竞技场随机位置刷一批，诱导玩家为补给冒险走位。
## 数量 = 基础曲线 + 「宝箱数量」（加点/法宝同一字段，见 BalanceChest.chest_count），
## 每口匣子单独抽档（木/铜/玉），权重吃「宝箱品质」与已有的福缘 —— 抽档走 GameManager.rng，
## 全局 randf() 会让判据钉不住同一批匣子（铁律 3）。
func _spawn_chests() -> void:
	var player = GameManager.player
	if player == null:
		return
	var count := GameBalance.chest_count(wave_number, GameManager.chest_count_bonus)
	var tier_w: Array[float] = GameBalance.chest_tier_weights(GameManager.chest_quality, GameManager.luck)
	var lim := GameManager.MAP_HALF_EXTENT - 130.0
	for i in range(count):
		var chest := SpiritChest.new()
		# tier 必须在 add_child 之前写好：_ready 靠它定贴图/体型/击数/配色
		chest.tier = GameBalance.weighted_pick_index(tier_w, GameManager.rng.randf())
		var pos := Vector2(GameManager.rng.randf_range(-lim, lim), GameManager.rng.randf_range(-lim, lim))
		if pos.distance_to(player.global_position) < 130.0:
			# 别贴脸刷：推开一段再夹回场内，数量堆上去后不顶出竞技场边界
			pos = (pos + Vector2(180.0, 0.0)).clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		chest.global_position = pos
		get_parent().add_child(chest)

func end_wave(early_secs: float = 0.0) -> void:
	phase = Phase.CLEARING
	clear_timer = 1.0
	AudioManager.play_sfx("wave_clear", 0.9)
	GameManager.announcement_triggered.emit("第 %d 波敌潮平息" % wave_number)
	# 灵韵结算：无偿灵石+修为，随后复利增长；刷怪预算没花完的部分折经验找平（击杀收入不因减潮缩水）
	var budget_shortfall := maxi(0, _budget_total - _budget_used)
	var avg_exp := (_budget_exp_sum / float(_budget_used)) if _budget_used > 0 else 0.0
	# 提前清场的余时赏与灵韵同一次到账、同一句播报：横幅只有一个 Label，同帧发两句只会留下
	# 后一句 —— 分成两条等于把「收益到账」那个数吞掉。early_secs 传 0（表走完/判据直接调
	# end_wave()）时这条一分不给，与改动前逐枚灵石等价。
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
	# 没砸开的藏宝匣同一口径收走：每波重刷一批（数量曲线见 BalanceChest），不留档否则场地越打越满是箱子。
	# 必须与上面那个 for 平级：这两轮循环原先缩进了 enemies 循环的体内 ⇒ 场上没怪时
	# 匣子与炮台一个都不收（#24 刷怪预算把同屏顶满的旧口径改掉之后，波末清空成了常态，
	# 这条静默路径才露出来：ChestTargetingCheck 第 5 组三条一起报红）。
	for chest in get_tree().get_nodes_in_group("chests"):
		if chest is SpiritChest:
			(chest as SpiritChest).dissolve()
	# 波末收回场上机关炮台
	for turret in get_tree().get_nodes_in_group("turrets"):
		if turret is TurretUnit:
			turret.dismiss()
	# 地上灵石全部吸进袖中；残丹/回春葫芦走结算（贴身才入口，没捡到的回不上的折灵石）
	var player = GameManager.player
	if player != null:
		for gem in get_tree().get_nodes_in_group("gems"):
			if gem is HealOrb:
				(gem as HealOrb).settle_for_wave_end(player)
			elif gem.has_method("magnet_to"):
				gem.magnet_to(player)

func _open_shop() -> void:
	if wave_number >= GameManager.VICTORY_WAVE and not GameManager.endless_mode:
		phase = Phase.SHOP
		GameManager.trigger_game_over(true)
		return
	_enter_wave_break()

func open_shop() -> void:
	## 结算界面「继续无尽」入口
	if phase == Phase.SHOP:
		_enter_wave_break()

## 回合间隙的唯一闸口：先清掉攒下的悟道点数，加完了才轮到灵石阁。
## 战斗中的升级只攒点不弹面板（2026-10-09 用户指令：「在战斗过程中触发加点的体验不好」）。
func _enter_wave_break() -> void:
	if GameManager.has_pending_upgrades():
		phase = Phase.ALLOC
		GameManager.open_alloc_session()
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
	GameManager.shop_opened.emit()

func _on_shop_closed() -> void:
	start_wave(wave_number + 1)

func _spawn_regular(player: Node2D) -> void:
	# 波内总刷入预算：耗尽即停手（波次时长照常跑满，场上越打越空）
	if _budget_used >= _budget_total:
		return
	# 狂战蛮修等角色的 enemy_count_mult 与危险度的 danger_count_mult 同时放大同屏上限与每轮刷怪量
	var enemy_cap := int(round(float(max_enemies) * GameManager.enemy_count_mult * GameBalance.danger_count_mult(GameManager.danger_level)))
	if GameManager.enemy_count >= enemy_cap:
		return

	var count := int(round(float(GameBalance.spawn_batch(wave_number, GameManager.rng.randf())) * GameManager.enemy_count_mult * GameBalance.danger_count_mult(GameManager.danger_level)))
	# 最后一轮允许部分兑现：预算剩几只刷几只，不整轮丢弃
	count = mini(count, _budget_total - _budget_used)
	var lim := GameManager.MAP_HALF_EXTENT - 45.0
	var p_pos: Vector2 = player.global_position
	for i in range(count):
		# 土豆兄弟式全图随机出生 + 远离玩家安全区保护（≥130px）
		var pos := Vector2(
			GameManager.rng.randf_range(-lim, lim),
			GameManager.rng.randf_range(-lim, lim)
		)
		if pos.distance_to(p_pos) < 130.0:
			var push_dir := (pos - p_pos).normalized()
			if push_dir.is_zero_approx():
				push_dir = Vector2.RIGHT.rotated(GameManager.rng.randf() * TAU)
			pos = (p_pos + push_dir * 160.0).clamp(Vector2(-lim, -lim), Vector2(lim, lim))

		var enemy_scene: PackedScene = _pick_enemy_scene()
		# 提前锁定预算名额与经验累计，防止 1.1s 预警延迟期间超额派发
		_budget_used += 1
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
		var enemy = scene.instantiate() as EnemyBase
		if enemy == null:
			return
		enemy.global_position = pos
		enemy.add_to_group("enemies")
		_scale_to_wave(enemy)
		parent.add_child(enemy)
		_budget_exp_sum += float(enemy.exp_reward)
		# 出场弹性缩放动画 (0.4 -> 1.0)
		enemy.scale = Vector2.ONE * 0.4
		var tw := enemy.create_tween()
		tw.tween_property(enemy, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	parent.add_child(indicator)

## 怪物配比表：随波次引入新威胁（雷兽冲锋 → 丹爆傀儡）。
## 邪修（放火球那颗）不再靠解锁波次登场 —— 第 1 波就有，占比按 MIX_XIEXIU_RAMP 爬坡，
## 2026-10-08 用户指令：「这个放火球的敌人怎么要到七八波才出来？不一开始就应该有吗」。
## 旧写法是「累计带 + 波次闸门」：闸门一开，邪修直接把 [0, 0.27) 整段吃掉 = 第 8 波突然
## 27% 刷火球怪；而同一结构下雷兽在第 5~7 波也白捡了 42%（它上面那格是空的）。
## 现在火球怪从第 1 波就占自己那一格，雷兽/花妖/史莱姆回到各自该有的份额。
const MIX_DANBAO_EDGE := 0.12      ## 丹爆傀儡累计带上沿
const MIX_DANBAO_WAVE := 3         ## 丹爆傀儡最早出现波次
const MIX_XIEXIU_EDGE := 0.27      ## 邪修累计带上沿（第 8 波占满）
const MIX_XIEXIU_START := 0.06     ## 邪修第 1 波的占比
const MIX_XIEXIU_RAMP := 0.03      ## 邪修每波多刷 3%，到上沿为止
const MIX_LEIBEAST_EDGE := 0.42    ## 雷兽累计带上沿
const MIX_LEIBEAST_WAVE := 5       ## 雷兽最早出现波次
const MIX_FLOWER_BASE := 0.42      ## 花妖带下沿
const MIX_FLOWER_MIN_WAVE := 2     ## 花妖最早出现波次
const MIX_FLOWER_SLOPE := 0.06     ## 花妖占比随波次增长
const MIX_FLOWER_GROWTH := 0.25    ## 花妖占比基数
const MIX_FLOWER_CAP := 0.6        ## 花妖增长封顶
const MIX_FLOWER_STEP := 0.58      ## 花妖占比折算
# 新敌种占的是史莱姆的保底份额（高 roll 段，roll ≥ 下沿才命中；越晚解锁越稀有）
const MIX_FENGQUN_WAVE := 3        ## 蜂群精最早出现波次（廉价群怪，填充密度）
const MIX_FENGQUN_LO := 0.78
const MIX_XUEYONG_WAVE := 6        ## 血蛹（死亡分裂）
const MIX_XUEYONG_LO := 0.86
const MIX_YINGMEI_WAVE := 7        ## 影魅（闪现侧翼）
const MIX_YINGMEI_LO := 0.91
const MIX_GUYAO_WAVE := 9          ## 鼓妖（同伴加速光环）
const MIX_GUYAO_LO := 0.95
const MIX_ZHUMU_WAVE := 14         ## 百目妖（产卵孵化群怪，原蛛母换悬浮系怪种）
const MIX_ZHUMU_LO := 0.98

## 邪修在第 wave 波占到的累计带上沿（纯函数，单测直接钉这条爬坡线）
static func xiexiu_edge(wave: int) -> float:
	var w := maxi(wave, 1)
	return minf(MIX_XIEXIU_EDGE, MIX_XIEXIU_START + MIX_XIEXIU_RAMP * float(w - 1))

## 配比判定：纯函数（给定波次与 roll ∈ [0,1) 返回怪种 key），被闸门锁住的种把份额让给下一格
## 低 roll 段是 丹爆/邪修/雷兽/花妖 的累计带；高 roll 段（≥0.78）由新敌种从史莱姆的保底份额里切走
static func pick_scene_key(wave: int, roll: float) -> String:
	var w := maxi(wave, 1)
	if w >= MIX_DANBAO_WAVE and roll < MIX_DANBAO_EDGE:
		return "danbao"
	if roll < xiexiu_edge(w):
		return "xiexiu"
	if w >= MIX_LEIBEAST_WAVE and roll < MIX_LEIBEAST_EDGE:
		return "leibeast"
	if w >= MIX_FLOWER_MIN_WAVE and roll < MIX_FLOWER_BASE + minf(MIX_FLOWER_GROWTH + w * MIX_FLOWER_SLOPE, MIX_FLOWER_CAP) * MIX_FLOWER_STEP:
		return "flower"
	if w >= MIX_ZHUMU_WAVE and roll >= MIX_ZHUMU_LO:
		return "zhumu"
	if w >= MIX_GUYAO_WAVE and roll >= MIX_GUYAO_LO:
		return "guyao"
	if w >= MIX_YINGMEI_WAVE and roll >= MIX_YINGMEI_LO:
		return "yingmei"
	if w >= MIX_XUEYONG_WAVE and roll >= MIX_XUEYONG_LO:
		return "xueyong"
	if w >= MIX_FENGQUN_WAVE and roll >= MIX_FENGQUN_LO:
		return "fengqun"
	return "slime"

func _pick_enemy_scene() -> PackedScene:
	match pick_scene_key(wave_number, GameManager.rng.randf()):
		"danbao":
			return danbao_scene
		"xiexiu":
			return xiexiu_scene
		"leibeast":
			return leibeast_scene
		"flower":
			return flower_scene
		"zhumu":
			return zhumu_scene
		"guyao":
			return guyao_scene
		"yingmei":
			return yingmei_scene
		"xueyong":
			return xueyong_scene
		"fengqun":
			return fengqun_scene
		_:
			return slime_scene

## 精英池轮换：铁甲魔傀（坦克）→ 赤雷兽（突进）→ 剑煞邪修（三连剑气），依次登场
var _elite_spawn_count: int = 0

func _spawn_elite(player: Node2D) -> void:
	var lim := GameManager.MAP_HALF_EXTENT - 60.0
	var p_pos: Vector2 = player.global_position
	var pos := Vector2(
		GameManager.rng.randf_range(-lim, lim),
		GameManager.rng.randf_range(-lim, lim)
	)
	if pos.distance_to(p_pos) < 180.0:
		var push_dir := (pos - p_pos).normalized()
		if push_dir.is_zero_approx():
			push_dir = Vector2.RIGHT.rotated(GameManager.rng.randf() * TAU)
		pos = (p_pos + push_dir * 220.0).clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	var pool: Array = [golem_scene, chilei_elite_scene, jiansha_elite_scene]
	var scene: PackedScene = pool[_elite_spawn_count % pool.size()]
	_elite_spawn_count += 1

	var parent := get_parent()
	if parent == null:
		return
	var indicator := SpawnIndicator.new()
	indicator.global_position = pos
	indicator.is_elite = true
	indicator.spawn_callback = func():
		if phase != Phase.FIGHT:
			return
		var elite = scene.instantiate() as EnemyBase
		if elite == null:
			return
		elite.global_position = pos
		elite.add_to_group("enemies")
		_scale_to_wave(elite)
		parent.add_child(elite)
		var titles := {golem_scene: "铁甲巨怪", chilei_elite_scene: "烈雷兽", jiansha_elite_scene: "剑客亡灵"}
		GameManager.announcement_triggered.emit("⚠ %s突入战场！" % titles.get(scene, "精英敌人"))
		GameManager.shake_camera(5.0, 0.25)
	parent.add_child(indicator)

## 随波数成长敌人属性（曲线见 GameBalance），同种怪个体 ±10% 浮动；危险度再整体抬血/攻
func _scale_to_wave(enemy: EnemyBase) -> void:
	var variance: float = GameManager.rng.randf_range(
		1.0 - GameBalance.ENEMY_STAT_VARIANCE,
		1.0 + GameBalance.ENEMY_STAT_VARIANCE
	)
	enemy.max_hp = ceilf(enemy.max_hp * GameBalance.enemy_hp_mult(wave_number) * variance * GameBalance.danger_hp_mult(GameManager.danger_level))
	enemy.contact_damage = ceilf(enemy.contact_damage * GameBalance.enemy_dmg_mult(wave_number) * variance * GameBalance.danger_dmg_mult(GameManager.danger_level))

## 固定 Boss 关：血量/伤害按 GameBalance 波次公式注入，称号与演出随关卡推进
func _spawn_boss(player: Node2D) -> void:
	var lim := GameManager.MAP_HALF_EXTENT - 60.0
	var p_pos: Vector2 = player.global_position
	var pos := Vector2(
		GameManager.rng.randf_range(-lim, lim),
		GameManager.rng.randf_range(-lim, lim)
	)
	if pos.distance_to(p_pos) < 200.0:
		var push_dir := (pos - p_pos).normalized()
		if push_dir.is_zero_approx():
			push_dir = Vector2.RIGHT.rotated(GameManager.rng.randf() * TAU)
		pos = (p_pos + push_dir * 240.0).clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	var parent := get_parent()
	if parent == null:
		return
	var boss := boss_scene.instantiate() as BossEnemy
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
	GameManager.announcement_triggered.emit(_boss_announcement())
	GameManager.shake_camera(7.0, 0.35)

## 本波魔君存活与否（Boss 波超时锁关的判据）
func _boss_still_alive() -> bool:
	return _boss_ref != null and is_instance_valid(_boss_ref) and not _boss_ref.dying

func _boss_title() -> String:
	if wave_number > GameManager.VICTORY_WAVE:
		return "回响Boss"     ## 无尽波次的轮回魔君
	if wave_number >= GameManager.VICTORY_WAVE:
		return "最终Boss"     ## 第 20 波最终关
	return "火焰Boss"         ## 第 10 波首个 Boss 关

func _boss_announcement() -> String:
	if wave_number == GameManager.VICTORY_WAVE:
		return "⚠ 最终Boss战 · 最终Boss出现！"
	if wave_number > GameManager.VICTORY_WAVE:
		return "⚠ 回响Boss · 再次出现！"
	return "⚠ Boss波 · 火焰Boss突入战场！"
