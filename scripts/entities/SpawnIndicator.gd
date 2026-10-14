class_name SpawnIndicator
extends Node2D

## 敌人生成预警指示器（仿土豆兄弟危险十字/预警标记，修仙妖煞凝聚包装）
## 敌人不会在玩家视野内突然凭空冒出，而是在目标落点先凝聚 1.1s 妖气符印，
## 随后破土现身。

const DURATION := 1.1
const REDRAW_INTERVAL := 0.033  ## 30Hz 节流，低开销

var progress: float = 0.0       ## 0.0 -> 1.0
var indicator_radius: float = 22.0
var is_elite: bool = false
var is_boss: bool = false       ## 魔君档：更长凝聚 + 双层魔轮异象，登场即焦点
var spawn_callback: Callable

var _time_left: float = DURATION
var _redraw_timer: float = 0.0
var _clock: float = 0.0

## 在树实例计数：WaveSpawner._tide_spent 每帧查「是否还有凝聚中的指示器」，
## 原来每帧全量遍历战斗层全部子节点（100+），改走 O(1) 计数
static var active_count: int = 0

func _enter_tree() -> void:
	active_count += 1

func _exit_tree() -> void:
	active_count -= 1

func _ready() -> void:
	# 保持 z_index = 0：在 EntitiesLayer 内，天然位于 MapLayer（地砖/地面装饰/结界）之上；
	# 绝不设 >0（实体与弹丸默认为 z=0，设 >0 会直接盖在角色表面）
	z_index = 0
	if is_boss:
		indicator_radius = 52.0
		_time_left = BOSS_DURATION
	elif is_elite:
		indicator_radius = 36.0

## 魔君凝聚时长：给玩家 2 秒看清落点跑位；WaveSpawner 在开场 1.5s 后才发起凝聚，
## 凝聚期内回合表早已走完但「Boss 未除敌潮不退」口径兜底，不影响节奏
const BOSS_DURATION := 2.0

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		queue_free()
		return

	_time_left -= delta
	_clock += delta
	progress = clampf(1.0 - (_time_left / _duration()), 0.0, 1.0)

	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()

	if _time_left <= 0.0:
		_finish_and_spawn()

func _finish_and_spawn() -> void:
	set_process(false)
	if spawn_callback.is_valid():
		spawn_callback.call()
	# 出生落地扬尘与微震微波
	if get_parent() != null:
		JuiceEffect.spawn_step_dust(get_parent(), global_position, Vector2.DOWN * 20.0)
		if is_boss:
			JuiceEffect.spawn_shockwave(get_parent(), global_position, indicator_radius * 1.8, GameStyle.BAD, 0.35)
		elif is_elite:
			JuiceEffect.spawn_shockwave(get_parent(), global_position, indicator_radius * 1.5, GameStyle.BAD, 0.25)
	queue_free()

## 凝聚总时长：魔君长版，普通/精英共用 1.1s
func _duration() -> float:
	return BOSS_DURATION if is_boss else DURATION

func _draw() -> void:
	var t := progress  # 0.0 -> 1.0
	var pulse := sin(_clock * 14.0) * 0.15 + 0.85
	var r := indicator_radius

	# 魔君异象（先画，垫底）：双层逆向旋转魔轮 + 斜向大十字，凝聚全程可见
	if is_boss:
		var wheel_col := Color(GameStyle.BAD.r, GameStyle.BAD.g, GameStyle.BAD.b, 0.55 + 0.35 * t)
		var wheel_r := r * (0.55 + 0.25 * t)
		var spokes: int = 8
		for ring in range(2):
			var rot := _clock * (1.6 if ring == 0 else -2.2) + float(ring) * 0.4
			var seg_r := wheel_r * (1.0 if ring == 0 else 0.7)
			for i in range(spokes):
				var a := rot + float(i) * TAU / float(spokes)
				var dir := Vector2(cos(a), sin(a) * 0.55)  # 俯视压扁成椭圆环，贴地感
				draw_line(dir * seg_r * 0.35, dir * seg_r, wheel_col, 2.0, true)
			draw_arc(Vector2.ZERO, seg_r, 0.0, TAU, 40, Color(wheel_col.r, wheel_col.g, wheel_col.b, 0.45), 1.5, true)

	# 1. 地面妖气暗符印（十字煞印 + 内核）
	var col_base := Color(GameStyle.BAD.r, GameStyle.BAD.g, GameStyle.BAD.b, 0.35 * pulse)
	var col_core := Color(GameStyle.BAD.r, GameStyle.BAD.g, GameStyle.BAD.b, 0.75 * pulse)
	var col_dark := Color(0.15, 0.04, 0.08, 0.6)

	# 底部暗阴影圆
	draw_circle(Vector2.ZERO, r * 0.6, col_dark)

	# 2. 交叉煞纹 / 妖气尖刺（土豆兄弟经典十字尖刺构型）
	var cross_len := r * (1.1 - t * 0.3)
	var cross_w := 2.5
	if is_boss:
		cross_w = 4.5
	elif is_elite:
		cross_w = 3.5
	# 四方煞针
	draw_line(Vector2(-cross_len, 0), Vector2(cross_len, 0), col_base, cross_w)
	draw_line(Vector2(0, -cross_len), Vector2(0, cross_len), col_base, cross_w)

	# 斜角四煞短针
	var diag_len := cross_len * 0.65
	draw_line(Vector2(-diag_len, -diag_len), Vector2(diag_len, diag_len), col_base * 0.8, cross_w * 0.75)
	draw_line(Vector2(diag_len, -diag_len), Vector2(-diag_len, diag_len), col_base * 0.8, cross_w * 0.75)

	# 3. 凝聚收缩环（前 0.65 脉动，后 0.35 加速向圆心坍缩）
	var ring_r: float
	var ring_alpha: float
	if t < 0.65:
		# 脉动期：光圈在外围呼吸
		ring_r = r * (0.8 + 0.2 * pulse)
		ring_alpha = 0.5 + 0.3 * t
	else:
		# 汇聚期：从外围加速收缩到中心点 (1.0 -> 0.0)
		var converge_t := (t - 0.65) / 0.35
		ring_r = lerpf(r, 2.0, ease(converge_t, 2.5))
		ring_alpha = 0.8 + 0.2 * converge_t

	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(GameStyle.BAD.r, GameStyle.BAD.g, GameStyle.BAD.b, ring_alpha), 2.0 if not is_boss else 3.5, true)

	# 4. 中心妖核红芒：随着进度由小变大并提亮
	var core_r := lerpf(2.0, r * 0.45, t)
	draw_circle(Vector2.ZERO, core_r, col_core)
	# 极小金白耀斑
	if t > 0.7:
		draw_circle(Vector2.ZERO, core_r * 0.4, Color(1.0, 0.9, 0.8, (t - 0.7) / 0.3))
	# 魔君末段：金白耀斑提前点亮成大光柱底，宣示大物将出
	if is_boss and t > 0.55:
		draw_circle(Vector2.ZERO, core_r * 0.55, Color(1.0, 0.85, 0.7, (t - 0.55) / 0.45 * 0.6))
