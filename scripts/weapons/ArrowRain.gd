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
const TAIL := 34.0       ## 彗尾长度（纯表现；2026-10-26 由 26 加长，混战里读得出「有东西砸下来」）
const DUR_PAD := 0.08    ## 全部落地后滞留收尾
## 落点预告环：半径必须等于判定半径（画多大 == 判多大，项目铁律 7）。
## 旧写法画的是 10px 小圈，实际判定 55px —— 玩家以为只是「要落个点」，结果半屏都掉血。
const WARN_RADIUS := BalanceChain.ARROW_RAIN_HIT_RADIUS
## 箭体配色（金系灵箭：与落点冲击环同色系，不再用「白芯 + 古金环」两套语言）
const ARROW_TRAIL_COLOR := Color(2.5, 2.05, 0.75, 0.95)
const ARROW_HEAD_COLOR := Color(2.6, 2.3, 1.5)
const WARN_COLOR := Color(2.4, 1.9, 0.6, 0.4)

var _t: float = 0.0
var _arrows: Array = []  ## {to: Vector2（本地落点）, delay: float, tail: float, landed: bool}
var _damage: float = 0.0
var _total_dur: float = 0.0
var _land_sfx_played: bool = false  ## 本轮落地音只播一次（五支箭各播一遍会糊成噪音）

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
	JuiceEffect.spawn_impact_pop(self, world_pos, GameStyle.FX_HDR_GOLD)
	JuiceEffect.spawn_shockwave(self, world_pos, BalanceChain.ARROW_RAIN_HIT_RADIUS,
		GameStyle.FX_HDR_GOLD, 0.18)
	# 落地音（2026-10-26）：旧写法整轮只有起手一声 blade_shoot，五支箭砸下去全程无声，
	# 读起来像「多开了一枪」。落地补一记材质音，只在首支播（同轮其余支不叠音）。
	if not _land_sfx_played:
		_land_sfx_played = true
		AudioManager.play_sfx("impact_crack", 0.45, 0.92)

func _draw() -> void:
	for a in _arrows:
		var to: Vector2 = a.to
		var delay: float = float(a.delay)
		if bool(a.landed):
			continue
		if _t < delay:
			# 起落前的落点预告：淡入的判定圈（半径 == 判定半径，画多大就判多大）
			var warn_a: float = clampf(_t / maxf(delay, 0.01), 0.0, 1.0) * WARN_COLOR.a
			if warn_a > 0.02:
				draw_arc(to, WARN_RADIUS, 0.0, TAU, 28,
					Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, warn_a), 1.6, true)
				# 内圈靶心：落点中心再点一个小圈，一眼看出「砸这儿」
				draw_arc(to, WARN_RADIUS * 0.22, 0.0, TAU, 12,
					Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, warn_a * 1.4), 1.2, true)
			continue
		var k: float = clampf((_t - delay) / FALL_TIME, 0.0, 1.0)
		var from := to + Vector2(0.0, -BalanceChain.ARROW_RAIN_FALL_HEIGHT)
		var p: Vector2 = from.lerp(to, k * k)  # 加速下坠
		var tail: float = float(a.tail)
		# 彗尾：双层（宽半透明辉光 + 窄亮芯），与 LightningBolt 的成对画线范式同款
		draw_line(p + Vector2(0, -tail), p, Color(ARROW_TRAIL_COLOR.r, ARROW_TRAIL_COLOR.g,
			ARROW_TRAIL_COLOR.b, 0.32), 5.0, true)
		draw_line(p + Vector2(0, -tail), p, ARROW_TRAIL_COLOR, 2.6, true)
		# 箭头：加大的三角，落地那一瞬读得出「尖锐」
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, 6), p + Vector2(-4, -4), p + Vector2(4, -4)]), ARROW_HEAD_COLOR)
