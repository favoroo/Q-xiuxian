class_name WaveSpawner
extends Node2D

## 波次状态机：WAITING(选法器) → FIGHT → CLEARING(清场吸附) → ALLOC(波后悟道，有待加点才插队) → SHOP → 下一波
## 第 20 波通关「渡劫成功」（双精英心魔劫）；可继续无尽

enum Phase { WAITING, FIGHT, CLEARING, ALLOC, SHOP }

## 同屏上限：2026-10-10 打击感重塑由 55 下调至 35 —— 小怪加血 3.5 倍后单敌存活更久，
## 密度由「少而硬」维持，击杀成为低频但每下都有读数的事件
@export var max_enemies: int = 35

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
				GameManager.announcement_triggered.emit("⚠ 魔君未除 · 妖潮不退 ⚠")
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

	if wave_timer <= 0.0:
		end_wave()

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
	_spawn_chests()
	if _is_boss_wave(n):
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 魔君压境 ✦" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	elif _is_elite_wave(n):
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 妖潮来袭 ✦" % n)
		AudioManager.play_sfx("boss_raid", 0.9)
		AudioManager.play_bgm_key("trial")
	else:
		GameManager.announcement_triggered.emit("✦ 第 %d 波 · 妖潮来袭 ✦" % n)
		AudioManager.play_sfx("wave_start", 0.9)
		AudioManager.play_bgm_key("battle")

## 藏宝匣：每波在竞技场随机位置刷 2~4 只，诱导玩家为补给冒险走位
func _spawn_chests() -> void:
	var player = GameManager.player
	if player == null:
		return
	var count := mini(2 + int(wave_number / 6.0), 4)
	var lim := GameManager.MAP_HALF_EXTENT - 160.0
	for i in range(count):
		var chest := SpiritChest.new()
		var pos := Vector2(GameManager.rng.randf_range(-lim, lim), GameManager.rng.randf_range(-lim, lim))
		if pos.distance_to(player.global_position) < 150.0:
			pos += Vector2(220.0, 0.0)
		chest.global_position = pos
		get_parent().add_child(chest)

func end_wave() -> void:
	phase = Phase.CLEARING
	clear_timer = 1.0
	AudioManager.play_sfx("wave_clear", 0.9)
	GameManager.announcement_triggered.emit("第 %d 波妖潮平息" % wave_number)
	# 灵韵结算：无偿灵石+修为，随后复利增长
	GameManager.apply_harvest()
	# 余怪消散（不掉落）
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()
	# 没砸开的藏宝匣同一口径收走：每波重刷 2~4 只，不留档否则场地越打越满是箱子
	for chest in get_tree().get_nodes_in_group("chests"):
		if chest is SpiritChest:
			(chest as SpiritChest).dissolve()
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
	# 狂战蛮修等角色的 enemy_count_mult 与危险度的 danger_count_mult 同时放大同屏上限与每轮刷怪量
	var enemy_cap := int(round(float(max_enemies) * GameManager.enemy_count_mult * GameBalance.danger_count_mult(GameManager.danger_level)))
	var enemy_count = get_tree().get_nodes_in_group("enemies").size()
	if enemy_count >= enemy_cap:
		return

	var count := int(round(float(GameBalance.spawn_batch(wave_number, GameManager.rng.randf())) * GameManager.enemy_count_mult * GameBalance.danger_count_mult(GameManager.danger_level)))
	for i in range(count):
		var angle := GameManager.rng.randf() * TAU
		var spawn_dist := GameManager.rng.randf_range(380.0, 480.0)
		var pos = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_dist
		pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 40.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 40.0))

		var enemy = _pick_enemy_scene().instantiate() as EnemyBase
		enemy.global_position = pos
		enemy.add_to_group("enemies")
		_scale_to_wave(enemy)
		get_parent().add_child(enemy)

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
	var angle := GameManager.rng.randf() * TAU
	var pos = player.global_position + Vector2(cos(angle), sin(angle)) * 420.0
	pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 60.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 60.0))
	var pool: Array = [golem_scene, chilei_elite_scene, jiansha_elite_scene]
	var scene: PackedScene = pool[_elite_spawn_count % pool.size()]
	_elite_spawn_count += 1
	var elite = scene.instantiate() as EnemyBase
	elite.global_position = pos
	elite.add_to_group("enemies")
	_scale_to_wave(elite)
	get_parent().add_child(elite)

	var titles := {golem_scene: "铁甲魔傀", chilei_elite_scene: "赤雷兽", jiansha_elite_scene: "剑煞邪修"}
	GameManager.announcement_triggered.emit("⚠ %s破阵而入！" % titles.get(scene, "精英妖物"))
	GameManager.shake_camera(5.0, 0.25)

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
	var angle := GameManager.rng.randf() * TAU
	var pos = player.global_position + Vector2(cos(angle), sin(angle)) * 460.0
	pos = pos.clamp(Vector2.ONE * -(GameManager.MAP_HALF_EXTENT - 60.0), Vector2.ONE * (GameManager.MAP_HALF_EXTENT - 60.0))

	var boss := boss_scene.instantiate() as BossEnemy
	boss.global_position = pos
	boss.add_to_group("enemies")
	boss.add_to_group("boss")
	boss.max_hp = GameBalance.boss_hp(wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level)
	boss.contact_damage = GameBalance.boss_contact_damage(wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level)
	boss.attack_interval = GameBalance.BOSS_ATTACK_INTERVAL
	boss.final_boss = wave_number >= GameManager.VICTORY_WAVE
	boss.boss_title = _boss_title()
	_boss_ref = boss
	get_parent().add_child(boss)

	GameManager.announcement_triggered.emit(_boss_announcement())
	GameManager.shake_camera(7.0, 0.35)

## 本波魔君存活与否（Boss 波超时锁关的判据）
func _boss_still_alive() -> bool:
	return _boss_ref != null and is_instance_valid(_boss_ref) and not _boss_ref.dying

func _boss_title() -> String:
	if wave_number > GameManager.VICTORY_WAVE:
		return "妖皇回响"     ## 无尽波次的轮回魔君
	if wave_number >= GameManager.VICTORY_WAVE:
		return "心魔魔尊"     ## 第 20 波最终关
	return "赤炎魔将"         ## 第 10 波首个 Boss 关

func _boss_announcement() -> String:
	if wave_number == GameManager.VICTORY_WAVE:
		return "⚠ 心魔劫 · 心魔魔尊现世！"
	if wave_number > GameManager.VICTORY_WAVE:
		return "⚠ 妖皇回响 · 轮回魔君再临！"
	return "⚠ Boss 波 · 赤炎魔将破阵而入！"
