class_name HealOrb
extends Area2D

## 残丹/回春葫芦：贴上去才入口的回复珠（2026-10-09 用户三条指令）
##   ①「不会靠近就被吸附拾取，要人物贴上去才会拾取」—— 本珠不实现 magnet_to，
##      96 px 摄灵圈（Player.PickupArea 只认 loot 层上的 magnet_to）拿它没办法；
##      入口靠自己的 Area2D 认玩家身体那一层，判定圆 = 画出来的那颗珠子（半径 10）；
##      画幅与晶石同档（≈24 px），两颗掉在地上的东西一般大（2026-10-09 用户指令「葫芦再小一点」）。
##   ②「满血不会被拾取」—— 顶满时贴上去也不入口，压成灰相留在原地；贴身这一路每帧读引擎的
##      接触名单，所以「压着葫芦挨一刀」不必重新踩上去也算数。
##   ③「回合结束时未拾取的葫芦，溢出生命值部分变成灵石」—— WaveSpawner.end_wave 把场上的
##      珠子请进袖中结算：按当前缺血回血，回不上的那一截走 GameBalance.heal_overflow_stones
##      折灵石并当场飘字。既不白丢治疗，也不留一颗永远躺在地上的珠子。
## 纯代码构建，无需场景文件；加入 gems 组（波末按组遍历结算）。

const FULL_HP_EPS := 0.01            ## 视为满血的容差（每秒回血顶到上限时的浮点毛刺）
const ARRIVE_DIST := 22.0            ## 波末结算飞抵距离
const SPRITE_SCALE := Vector2(0.375, 0.375)  ## 128 图源缩到 ≈48 px 画幅：与 AstralGem（48×48 图 ×1）同档大小
const JUDGE_RADIUS := 10.0           ## 判定圆跟着画幅一起收：与 AstralGem 那颗的半径 10 同一把尺子
const TINT_READY := Color(0.65, 1.35, 0.7)    ## 可入口
const TINT_WAITING := Color(0.50, 0.60, 0.53) ## 满血待命：看得见，但不催你

var heal_amount: float = 3.0
var heal_pct: float = 0.0   ## >0 时按玩家气血上限百分比恢复（回春葫芦用）

var target_player: Node2D = null   ## 仅波末结算的飞行途中非空
var waiting_full_hp: bool = false  ## true = 满血贴上去也没入口，留在原地等掉血
var current_speed: float = -40.0
var max_speed: float = 680.0
var acceleration: float = 850.0

var _sprite: Sprite2D
var _loot_renderer: ProceduralLootRenderer
var _bob_tween: Tween = null
var _settling: bool = false        ## 波末结算中（不再被满血闸拦下）

func _ready() -> void:
	add_to_group("gems")
	collision_layer = 16  # loot：灵石那一层的账，别处若要吸灵仍能看到本珠
	collision_mask = 2    # player：本珠只认身体，不吃隔空吸附
	monitoring = true
	monitorable = true

	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/art/icon_hp.png")
	_sprite.modulate = TINT_READY
	_sprite.scale = SPRITE_SCALE
	_sprite.visible = false
	add_child(_sprite)

	_loot_renderer = ProceduralLootRenderer.new()
	_loot_renderer.loot_type = ProceduralLootRenderer.LootType.HEAL_ORB
	add_child(_loot_renderer)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = JUDGE_RADIUS
	shape.shape = circle
	add_child(shape)

	_start_bob()

## 这一口下去有没有实效：满血（含容差）就是没实效，吃了等于白丢一份治疗
static func heal_is_useful(player: Node2D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not (player is Player):
		return true
	var p := player as Player
	return p.current_health + FULL_HP_EPS < p.max_health

func _physics_process(delta: float) -> void:
	if _settling:
		_fly_to_settle(delta)
		return
	# 贴身这一路每帧问引擎的接触名单，不自己存一份 body_entered 引用：
	# 存了就会过期 —— 玩家一步跨开、名单先清，才轮到「掉血那一拍」。
	var touching := _touching_player()
	if touching == null:
		return
	if not heal_is_useful(touching):
		_set_waiting(true)
		return
	_set_waiting(false)
	_collect(touching)

## 现在压着本珠的玩家身体（没有就 null）
func _touching_player() -> Player:
	for body in get_overlapping_bodies():
		if body is Player:
			return body as Player
	return null

## 波末结算：这一路不再等玩家走过来，请进袖中；回不上的那截折灵石
func settle_for_wave_end(player: Node2D) -> void:
	if _settling or is_queued_for_deletion() or not (player is Player):
		return
	_set_waiting(false)
	_settling = true
	target_player = player
	current_speed = -50.0
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()

func _fly_to_settle(delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		_settling = false
		_start_bob()
		return
	var p := target_player as Player
	if p == null:
		_settling = false
		return
	var dist := global_position.distance_to(p.global_position)
	var dir: Vector2 = (p.global_position - global_position).normalized()
	current_speed = minf(max_speed, current_speed + acceleration * delta)
	global_position += dir * current_speed * delta
	if dist < ARRIVE_DIST:
		_collect(p)

## 落袋：回得上的回血，回不上的溢出折灵石 —— 贴身与波末两条入口共用这一把尺子
func _collect(p: Player) -> void:
	var intended := heal_amount
	if heal_pct > 0.0:
		intended = p.max_health * heal_pct
	var missing := maxf(0.0, p.max_health - p.current_health)
	var landed := minf(intended, missing)
	var overflow := maxf(0.0, intended - landed)

	JuiceEffect.spawn_pickup_pop(get_parent(), global_position, false)
	if landed > 0.0 and p.has_method("heal"):
		p.heal(landed)
	var stones := GameBalance.heal_overflow_stones(overflow)
	if stones > 0:
		GameManager.add_spirit_stones(stones)
		DamageNumber.spawn(get_parent(), global_position, stones, false, "+%d 灵石" % stones)
		AudioManager.play_sfx("gem_pickup", 1.25)
	target_player = null
	queue_free()

func _set_waiting(value: bool) -> void:
	waiting_full_hp = value
	if _sprite != null:
		_sprite.modulate = TINT_WAITING if value else TINT_READY
	if _loot_renderer != null:
		_loot_renderer.is_waiting = value

func _start_bob() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	var target_node = _loot_renderer if _loot_renderer != null else _sprite
	if target_node == null:
		return
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(target_node, "position:y", -3.0, 0.45).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(target_node, "position:y", 3.0, 0.45).set_trans(Tween.TRANS_SINE)
