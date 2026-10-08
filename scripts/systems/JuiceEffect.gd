class_name JuiceEffect
extends Node2D

## 游戏手感核心视觉反馈池：受击火花、妖气爆散环、拾取流光与步伐轻尘
## 遵循 Godot 4.7 性能规范：纯轻量级 CanvasItem 动态绘制与 Tween 驱动，零额外贴图依赖

enum EffectType { HIT_SPARKS, DEATH_BURST, PICKUP_POP, STEP_DUST }

var effect_type: int = EffectType.HIT_SPARKS
var lifetime: float = 0.2
var elapsed: float = 0.0
var is_crit: bool = false
var is_elite: bool = false
var dir_angle: float = 0.0

# 粒子运动数组：[{pos: Vector2, vel: Vector2, len: float, color: Color, width: float}]
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []

func _ready() -> void:
	z_index = 35
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	if progress >= 1.0:
		queue_free()
		return

	# 物理演进
	for p in _particles:
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["vel"] = (p["vel"] as Vector2) * (1.0 - delta * 9.0)

	for r in _rings:
		var cur_r: float = lerpf(r["start_r"], r["max_r"], Tween.interpolate_value(0.0, 1.0, progress, 1.0, Tween.TRANS_QUAD, Tween.EASE_OUT))
		r["current_r"] = cur_r

	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	var alpha := 1.0 - progress

	# 1. 绘制冲击光环
	for r in _rings:
		var col: Color = r["color"]
		col.a *= alpha
		var width: float = maxf(1.0, (r["width"] as float) * (1.0 - progress * 0.6))
		draw_arc(Vector2.ZERO, r["current_r"], 0.0, TAU, 32, col, width, true)

	# 2. 绘制火花/剑气飞溅点
	for p in _particles:
		var col: Color = p["color"]
		col.a *= alpha
		var pos: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		var width: float = p.get("width", 2.0)
		if vel.length_squared() > 100.0:
			var tip: Vector2 = pos + vel.normalized() * (p["len"] as float) * (1.0 - progress * 0.5)
			draw_line(pos, tip, col, width, true)
		else:
			draw_circle(pos, width, col)

# ----------------- 静态生成接口 -----------------

## 受击灵芒火花：沿打击方向呈扇形爆开
static func spawn_hit_sparks(parent: Node, pos: Vector2, hit_dir: Vector2, crit: bool = false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx := JuiceEffect.new()
	fx.effect_type = EffectType.HIT_SPARKS
	fx.global_position = pos
	fx.is_crit = crit
	fx.lifetime = 0.22 if not crit else 0.28

	var count := 7 if not crit else 12
	var base_angle := hit_dir.angle() if hit_dir.length_squared() > 0.01 else randf() * TAU
	var cone := deg_to_rad(65.0)

	var core_col := Color(0.9, 0.98, 1.0, 1.0) if not crit else Color(1.0, 0.96, 0.65, 1.0)
	var glow_col := Color(0.3, 0.7, 1.0, 0.9) if not crit else Color(1.0, 0.65, 0.15, 0.95)

	for i in range(count):
		var a := base_angle + randf_range(-cone, cone)
		var spd := randf_range(160.0, 320.0) if not crit else randf_range(240.0, 480.0)
		var vel := Vector2(cos(a), sin(a)) * spd
		var col := core_col if randf() < 0.4 else glow_col
		fx._particles.append({
			"pos": Vector2.ZERO,
			"vel": vel,
			"len": randf_range(8.0, 16.0) if not crit else randf_range(12.0, 24.0),
			"color": col,
			"width": 2.2 if not crit else 3.2,
		})

	# 暴击追加一记微型扩散光斑环
	if crit:
		fx._rings.append({
			"start_r": 4.0,
			"max_r": 28.0,
			"current_r": 4.0,
			"color": Color(1.0, 0.88, 0.4, 0.85),
			"width": 3.0,
		})

	parent.add_child(fx)

## 妖物死灭爆散：灵气崩解环 + 散逸灵尘
static func spawn_death_burst(parent: Node, pos: Vector2, elite: bool = false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx := JuiceEffect.new()
	fx.effect_type = EffectType.DEATH_BURST
	fx.global_position = pos
	fx.is_elite = elite
	fx.lifetime = 0.32 if not elite else 0.45

	# 冲击扩散光环
	var ring_col := Color(0.45, 0.8, 1.0, 0.8) if not elite else Color(1.0, 0.85, 0.3, 0.95)
	fx._rings.append({
		"start_r": 6.0,
		"max_r": 36.0 if not elite else 64.0,
		"current_r": 6.0,
		"color": ring_col,
		"width": 3.5 if not elite else 5.0,
	})
	if elite:
		fx._rings.append({
			"start_r": 2.0,
			"max_r": 42.0,
			"current_r": 2.0,
			"color": Color(1.0, 1.0, 0.9, 0.9),
			"width": 2.5,
		})

	# 崩散灵气粒子
	var count := 10 if not elite else 22
	for i in range(count):
		var a := randf() * TAU
		var spd := randf_range(90.0, 220.0) if not elite else randf_range(140.0, 360.0)
		var col := Color(0.7, 0.9, 1.0, 0.9) if not elite else Color(1.0, 0.75 + randf() * 0.25, 0.3, 0.9)
		fx._particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(a), sin(a)) * spd,
			"len": randf_range(6.0, 14.0),
			"color": col,
			"width": 2.0 if not elite else 3.0,
		})

	parent.add_child(fx)

## 灵石入体微缩流光
static func spawn_pickup_pop(parent: Node, pos: Vector2, is_gold: bool = false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx := JuiceEffect.new()
	fx.effect_type = EffectType.PICKUP_POP
	fx.global_position = pos
	fx.lifetime = 0.18

	var c := Color(0.35, 0.8, 1.0, 0.85) if not is_gold else Color(1.0, 0.88, 0.35, 0.95)
	fx._rings.append({
		"start_r": 16.0,
		"max_r": 2.0,
		"current_r": 16.0,
		"color": c,
		"width": 2.0,
	})
	parent.add_child(fx)

## 步伐轻尘（奔跑时的脚底微尘）
static func spawn_step_dust(parent: Node, pos: Vector2, move_dir: Vector2) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx := JuiceEffect.new()
	fx.effect_type = EffectType.STEP_DUST
	fx.global_position = pos
	fx.lifetime = 0.20
	fx.z_index = 5  # 在角色阴影附近

	var puff_dir := -move_dir.normalized()
	for i in range(3):
		var a := puff_dir.angle() + randf_range(-0.5, 0.5)
		var spd := randf_range(20.0, 50.0)
		fx._particles.append({
			"pos": Vector2(randf_range(-4, 4), randf_range(-2, 2)),
			"vel": Vector2(cos(a), sin(a)) * spd,
			"len": 0.0,
			"color": Color(0.7, 0.8, 0.92, 0.35),
			"width": randf_range(1.8, 3.2),
		})

	parent.add_child(fx)
