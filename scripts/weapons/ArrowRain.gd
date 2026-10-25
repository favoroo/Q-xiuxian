class_name ArrowRain
extends Node2D

## 箭雨倾盆（2026-10-25 超级悟道二阶段·箭道大成）：远程武器每 N 次出手，朝目标区
## 落下一轮灵箭。照 SpiritPetBoulder 的落点 AOE 范式：无碰撞体，落地遍历
## GameManager.live_enemies 鸭类型结算（严禁 as EnemyBase，项目坑 12/16）。
##
## 随机纪律：落点散布决定谁被命中 ⇒ 玩法判定，走 GameManager.rng（铁律 3）；
## 彗尾长度等纯表现抖动走本地 RNG（instance_id 播种，铁律 15）。

const FALL_TIME := 0.30  ## 单支坠落耗时（秒）
const STAGGER := 0.06    ## 支与支之间的起落间隔（秒）
const TAIL := 26.0       ## 彗尾长度（纯表现）
const DUR_PAD := 0.08    ## 全部落地后滞留收尾

var _t: float = 0.0
var _arrows: Array = []  ## {to: Vector2（本地落点）, delay: float, tail: float, landed: bool}
var _damage: float = 0.0
var _total_dur: float = 0.0

## 武器侧在出手计数到闸时调用：center 为目标区中心（世界坐标），damage 为单支实伤。
static func play(weapon: Node, center: Vector2, damage: float) -> void:
	if weapon == null or not is_instance_valid(weapon) or damage <= 0.0:
		return
	var tree := weapon.get_tree()
	if tree == null or tree.current_scene == null:
		return
	var fx := ArrowRain.new()
	fx._damage = damage
	tree.current_scene.add_child(fx)
	fx.global_position = center
	var fx_rng := RandomNumberGenerator.new()
	fx_rng.seed = int(fx.get_instance_id() % 2147483647)
	for i in range(BalanceChain.ARROW_RAIN_COUNT):
		# 落点散布是命中判定的一部分 → 玩法 RNG（ GameManager.rng ）
		var ang := GameManager.rng.randf() * TAU
		var r := BalanceChain.ARROW_RAIN_SPREAD * sqrt(GameManager.rng.randf())
		fx._arrows.append({
			"to": Vector2.from_angle(ang) * r,
			"delay": float(i) * STAGGER,
			"tail": TAIL * fx_rng.randf_range(0.8, 1.25),
			"landed": false,
		})
	fx._total_dur = float(BalanceChain.ARROW_RAIN_COUNT - 1) * STAGGER + FALL_TIME + DUR_PAD
	AudioManager.play_sfx("blade_shoot", 0.5, 0.85)

func _process(delta: float) -> void:
	_t += delta
	for a in _arrows:
		if bool(a.landed) or _t < float(a.delay) + FALL_TIME:
			continue
		a.landed = true
		_land(to_global(a.to))
	if _t >= _total_dur:
		queue_free()
	queue_redraw()

func _land(world_pos: Vector2) -> void:
	# 落点 AOE：圈定半径内可伤害敌人（与 ChainLightning.collect_in_radius 同一条口径）
	var targets := ChainLightning.collect_in_radius(world_pos, BalanceChain.ARROW_RAIN_HIT_RADIUS)
	for enemy in targets:
		enemy.take_damage(_damage, Vector2.ZERO, false)
	JuiceEffect.spawn_impact_pop(self, world_pos, GameStyle.FX_HDR_CORE)
	JuiceEffect.spawn_shockwave(self, world_pos, BalanceChain.ARROW_RAIN_HIT_RADIUS,
		GameStyle.FX_HDR_METAL, 0.18)

func _draw() -> void:
	for a in _arrows:
		var to: Vector2 = a.to
		var delay: float = float(a.delay)
		if bool(a.landed):
			continue
		if _t < delay:
			# 起落前的落点预告：淡入的小环，读「箭雨要来了」
			var warn_a: float = clampf(_t / maxf(delay, 0.01), 0.0, 1.0) * 0.35
			if warn_a > 0.02:
				draw_arc(to, 10.0, 0.0, TAU, 12, Color(1.2, 1.0, 0.5, warn_a), 1.2, true)
			continue
		var k: float = clampf((_t - delay) / FALL_TIME, 0.0, 1.0)
		var from := to + Vector2(0.0, -BalanceChain.ARROW_RAIN_FALL_HEIGHT)
		var p: Vector2 = from.lerp(to, k * k)  # 加速下坠
		var tail: float = float(a.tail)
		draw_line(p + Vector2(0, -tail), p, Color(2.2, 1.9, 0.9, 0.9), 2.2, true)
		# 箭头小三角
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, 4), p + Vector2(-3, -3), p + Vector2(3, -3)]), Color(2.4, 2.2, 1.6))
