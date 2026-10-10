class_name BossEnemy
extends EnemyBase

## 关卡 Boss：固定 Boss 波（第 10/20 波、无尽每 10 波）登场，参考土豆兄弟的大 Boss 设计。
## 与普通妖物的区别：
##   1. 超厚血条，顶部 HUD 专设 Boss 血条（boss_hp_changed / boss_defeated 信号驱动）
##   2. 周期性特殊攻击轮换：环弹齐射 → 震地冲击 → 召唤妖群
##   3. 半血进入二阶段「魔焰滔天」：出招更频繁、环弹更密、移动更快
## 数值（血量/接触伤害/攻击周期/称号）由 WaveSpawner 按 GameBalance 公式注入，
## 波次缩放后直接覆盖 max_hp / contact_damage，本脚本不自带第二套曲线。

enum Pattern { RING, SLAM, SUMMON }

@export var boss_title: String = "敌潮Boss"
@export var final_boss: bool = false      ## 第 20 波魔尊：换紫皮、放大身形
@export var attack_interval: float = GameBalance.BOSS_ATTACK_INTERVAL  ## 特殊攻击循环间隔

var _attack_timer: float = 2.4    ## 开场缓冲，让玩家先看清魔君登场
var _pattern_idx: int = 0
var _phase2: bool = false
var _tint: Color = Color.WHITE    ## 常态染色（二阶段转红，环弹演出后回染）
var _slam_pending: bool = false
var _slam_timer: float = 0.0
var _slam_ring: Node2D = null

## 出招轮换表：保证三种特殊攻击都能见到，不靠纯随机
var _patterns: Array = [Pattern.RING, Pattern.SLAM, Pattern.SUMMON]

var _minion_scenes: Array = [
	preload("res://scenes/entities/SlimeEnemy.tscn"),
	preload("res://scenes/entities/FlowerEnemy.tscn"),
	preload("res://scenes/entities/FengQunEnemy.tscn"),
]

## 震地冲击预警圈：描边 + 半透明填充，alpha 由 Boss 每帧驱动闪烁
class SlamRing:
	extends Node2D
	var radius: float = GameBalance.BOSS_SLAM_RADIUS
	var alpha: float = 0.5
	func _draw() -> void:
		var c := Color(1.0, 0.32, 0.22, alpha)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, c, 3.0, true)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.32, 0.22, alpha * 0.16))

func _ready() -> void:
	if final_boss:
		spritesheet_path = "res://assets/art/warrior_purple_8dir.png"
		anim_sprite.scale *= 1.16
		var light := get_node_or_null("PointLight2D") as PointLight2D
		if light != null:
			light.color = Color(0.8, 0.45, 1.0)
			light.energy = 0.85
		hit_stun_resist = 0.25
		anim_sprite.modulate = _tint
	super._ready()
	# 登场即上屏：HUD 血条由此信号点亮
	GameManager.boss_hp_changed.emit(current_hp, max_hp, boss_title)

## Boss 出招大脑：与 EnemyBase._physics_process 的移动/接触伤害并行运行
func _process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return
	var player = GameManager.player
	if player == null:
		return

	# 震地冲击：预警圈闪烁倒计时 → 结算
	if _slam_pending:
		_slam_timer -= delta
		if _slam_ring != null:
			_slam_ring.alpha = 0.35 + 0.3 * sin(_slam_timer * 18.0)
			_slam_ring.queue_redraw()
		if _slam_timer <= 0.0:
			_resolve_slam(player)
		return  # 预警期间不开新招

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = attack_interval * (GameBalance.BOSS_PHASE2_INTERVAL_MULT if _phase2 else 1.0)
		_cast_next(player)

func _cast_next(player: Node2D) -> void:
	var pattern: int = _patterns[_pattern_idx % _patterns.size()]
	_pattern_idx += 1
	match pattern:
		Pattern.RING:
			_cast_ring()
		Pattern.SLAM:
			_cast_slam()
		Pattern.SUMMON:
			_cast_summon(player)

## 环弹齐射：短暂染红蓄力后向四周放出一圈大号火球（EnemyBolt，scale_factor 放大）
func _cast_ring() -> void:
	play_squash(Vector2(1.25, 0.78), 0.5)
	var tw := create_tween()
	tw.tween_property(anim_sprite, "modulate", Color(1.7, 0.5, 0.45), 0.4)
	tw.tween_callback(_fire_ring)
	tw.tween_property(anim_sprite, "modulate", _tint, 0.25)

func _fire_ring() -> void:
	if dying:
		return
	var count: int = GameBalance.BOSS_RING_COUNT + (GameBalance.BOSS_RING_COUNT_P2 if _phase2 else 0)
	var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_RING_DMG_MULT)
	for i in range(count):
		var ang := TAU * float(i) / float(count)
		var bolt := EnemyBolt.new()
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = GameBalance.BOSS_BOLT_SPEED
		bolt.damage = dmg
		bolt.scale_factor = GameBalance.BOSS_BOLT_SCALE
		get_parent().add_child(bolt)
	AudioManager.play_sfx("blade_shoot", 0.5)
	GameManager.add_trauma(0.12)

## 震地冲击：预警圈套在脚下，0.9s 后结算范围内伤害（预警期可跑出圈外躲避）
func _cast_slam() -> void:
	_slam_pending = true
	_slam_timer = GameBalance.BOSS_SLAM_WINDUP
	if _slam_ring == null:
		_slam_ring = SlamRing.new()
		_slam_ring.radius = GameBalance.BOSS_SLAM_RADIUS
		add_child(_slam_ring)
	_slam_ring.visible = true
	play_squash(Vector2(0.82, 1.2), 0.4)

func _resolve_slam(player: Node2D) -> void:
	_slam_pending = false
	if _slam_ring != null:
		_slam_ring.visible = false
	if dying:
		return
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
	# 震地 = 全场最该抖一下的时刻，但它自己就是一个事件：
	# 旧的 feedback(MEDIUM) + shake_camera(6.0) 是同一次落地发两遍，合为一记 HEAVY
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	AudioManager.play_sfx("orb_hit", 1.2)
	if player.global_position.distance_to(global_position) <= GameBalance.BOSS_SLAM_RADIUS:
		player.take_damage(maxf(1.0, contact_damage * GameBalance.BOSS_SLAM_DMG_MULT))

## 召唤妖群：Boss 战中持续供怪供经验，场面爆量时让位
func _cast_summon(player: Node2D) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	if enemies >= GameBalance.BOSS_SUMMON_CAP:
		return
	var count: int = GameBalance.BOSS_SUMMON_COUNT + (1 if _phase2 else 0)
	var hp_mult := GameBalance.enemy_hp_mult(GameManager.wave_number)
	var dmg_mult := GameBalance.enemy_dmg_mult(GameManager.wave_number)
	for i in range(count):
		var scene: PackedScene = _minion_scenes[i % _minion_scenes.size()]
		var minion := scene.instantiate() as EnemyBase
		var ang := GameManager.rng.randf() * TAU
		minion.global_position = global_position + Vector2(cos(ang), sin(ang)) * 110.0
		minion.add_to_group("enemies")
		minion.max_hp = ceilf(minion.max_hp * hp_mult)
		minion.contact_damage = ceilf(minion.contact_damage * dmg_mult)
		get_parent().add_child(minion)
	play_squash(Vector2(1.18, 0.85), 0.25)
	AudioManager.play_sfx("wave_start", 0.7)

## 半血二阶段「魔焰滔天」
func _enter_phase2() -> void:
	_phase2 = true
	_tint = Color(1.4, 0.6, 0.6)
	anim_sprite.modulate = _tint
	move_speed *= GameBalance.BOSS_PHASE2_SPEED_MULT
	play_squash(Vector2(1.3, 0.75), 0.35)
	GameManager.announcement_triggered.emit("⚠ %s · 狂暴形态 ⚠" % boss_title)
	AudioManager.play_sfx("boss_raid", 1.15)
	# 统一走 feedback() 分级体系（创伤 + 顿帧 + 缩放冲击一套齐），不再旧式 shake_camera 直调
	GameManager.feedback(GameManager.FeedbackTier.LARGE)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false, from_dot: bool = false) -> void:
	if dying:
		return
	# Boss 抗击退：几乎推不动，走位压力全靠技能
	super.take_damage(amount, knockback * GameBalance.BOSS_KNOCKBACK_RESIST, is_crit, from_dot)
	if dying:
		return  # 血条收起由 boss_defeated 信号负责
	if not _phase2 and current_hp <= max_hp * GameBalance.BOSS_PHASE2_AT:
		_enter_phase2()
	GameManager.boss_hp_changed.emit(current_hp, max_hp, boss_title)

func _die() -> void:
	if dying:
		return
	_slam_pending = false
	if _slam_ring != null:
		_slam_ring.visible = false
	GameManager.add_spirit_stones(GameBalance.BOSS_STONE_REWARD)
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	# shake_camera(9.0) 与 HEAVY 是同一件事发两遍（创伤叠到 1.0 直接顶格），去掉重复的那份
	AudioManager.play_sfx("enemy_death_elite", 0.75)
	GameManager.announcement_triggered.emit("✦ %s · 已击杀 ✦" % boss_title)
	GameManager.boss_defeated.emit(boss_title)
	super._die()
