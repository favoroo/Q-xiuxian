class_name SmoothCamera
extends Camera2D

## 基于 game-feel Trauma（创伤度 0~1）模型的平滑相机
## - 指数平滑帧率无关跟随 + 移动微前瞻（Look-ahead）
## - 创伤平方衰减（shake = trauma^2）：小击轻颤、重击猛震、自动归零
## - 多频正弦连续采样（替代每帧 randf 白噪点抖动）+ 镜头旋转偏航（Roll）+ 缩放冲击（Zoom Punch）

@export var follow_speed: float = 8.5
@export var lookahead_factor: float = 0.065
@export var trauma_decay: float = 1.45
@export var max_offset: Vector2 = Vector2(14.0, 10.0)
@export var max_roll: float = 0.045

var trauma: float = 0.0
var _t: float = 0.0
var _base_zoom: Vector2 = Vector2(1.2, 1.2)
var _zoom_tween: Tween = null
var _lookahead: Vector2 = Vector2.ZERO

func _ready() -> void:
	GameManager.main_camera = self
	_base_zoom = zoom
	ignore_rotation = false

func _process(delta: float) -> void:
	var player = GameManager.player
	if player != null and is_instance_valid(player):
		var target_lookahead := Vector2.ZERO
		if player is CharacterBody2D:
			target_lookahead = (player as CharacterBody2D).velocity * lookahead_factor
		var look_weight := 1.0 - exp(-5.0 * delta)
		_lookahead = _lookahead.lerp(target_lookahead, look_weight)

		var target_pos: Vector2 = player.global_position + _lookahead
		var follow_weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target_pos, follow_weight)

	if trauma > 0.0:
		trauma = maxf(trauma - trauma_decay * delta, 0.0)
		var shake_amt := trauma * trauma
		_t += delta * 28.0
		offset = Vector2(
			max_offset.x * shake_amt * _shake_axis(1.3, _t),
			max_offset.y * shake_amt * _shake_axis(3.7, _t)
		)
		rotation = max_roll * shake_amt * _shake_axis(7.1, _t * 0.85)
	else:
		offset = Vector2.ZERO
		rotation = 0.0

## 多频无公倍正弦合成的连续伪随机波形（平滑不刺眼）
func _shake_axis(seed_val: float, t: float) -> float:
	return 0.6 * sin(t * 1.7 + seed_val) + 0.4 * sin(t * 3.1 + seed_val * 2.1)

## 叠加创伤值（0.0 ~ 1.0）：小命中 0.12，普通受击 0.35，暴击/重击 0.45，大招/首领 0.75
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

## 镜头瞬时缩放冲击（Zoom Punch），用于聚灵阵爆发、精英击杀、大招等高潮时刻
func zoom_punch(punch_scale: float = 0.05, duration: float = 0.18) -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	zoom = _base_zoom * (1.0 + punch_scale)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "zoom", _base_zoom, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 兼容旧接口：按强度折算为 trauma 叠加
func shake(intensity: float = 4.0, _duration: float = 0.15) -> void:
	var mapped := clampf(intensity / 10.0, 0.08, 0.85)
	add_trauma(mapped)
