class_name SmoothCamera
extends Camera2D

## 基于 game-feel Trauma（创伤度 0~1）模型的平滑相机
## - 指数平滑帧率无关跟随 + 移动微前瞻（Look-ahead）
## - 创伤平方衰减（shake = trauma^2）：小击轻颤、重击猛震、自动归零
## - 多频正弦连续采样（替代每帧 randf 白噪点抖动）+ 镜头旋转偏航（Roll）+ 缩放冲击（Zoom Punch）
##
## 震屏的两条硬约束（口径来自 GameBalance「打击感：镜头创伤」段）：
##   1) 每秒累加有预算上限 ⇒ 哪怕调用方拿高频事件乱发创伤，最坏也只稳在
##      GameBalance.trauma_steady_state()（±1.4px 的轻颤），不会整局猛摇；
##   2) 幅度受设置档位倍率控制，档位「关闭」= 完全不动（含缩放冲击）。

@export var follow_speed: float = 9.0
@export var lookahead_factor: float = 0.04
@export var trauma_decay: float = GameBalance.TRAUMA_DECAY
@export var max_offset: Vector2 = Vector2(12.0, 9.0)
@export var max_roll: float = 0.018

var trauma: float = 0.0
var _t: float = 0.0
var _base_zoom: Vector2 = Vector2(1.2, 1.2)
var _zoom_tween: Tween = null
var _lookahead: Vector2 = Vector2.ZERO
var _kick_offset: Vector2 = Vector2.ZERO  ## 方向性冲击位移（顺受力方向猛推后快速高阻尼回弹）
## 档位幅度倍率（SettingsManager.shake_mult() 的缓存，随 setting_changed 刷新）
var _intensity: float = 1.0
## 本秒剩余可叠加的创伤预算
var _budget_left: float = GameBalance.TRAUMA_BUDGET
var _budget_timer: float = 1.0

func _ready() -> void:
	GameManager.main_camera = self
	_base_zoom = zoom
	ignore_rotation = false
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	SettingsManager.setting_changed.connect(_on_setting_changed)
	_refresh_intensity()

func _refresh_intensity() -> void:
	_intensity = SettingsManager.shake_mult()

func _on_setting_changed(section: StringName, key: StringName, _val: Variant) -> void:
	if section == &"display" and (key == &"shake_intensity" or key == &"screen_shake"):
		_refresh_intensity()

func _physics_process(delta: float) -> void:
	var player = GameManager.player
	if player != null and is_instance_valid(player):
		var target_lookahead := Vector2.ZERO
		if player is CharacterBody2D:
			target_lookahead = (player as CharacterBody2D).velocity * lookahead_factor
		var look_weight := 1.0 - exp(-6.0 * delta)
		_lookahead = _lookahead.lerp(target_lookahead, look_weight)

		var target_pos: Vector2 = player.global_position + _lookahead
		var follow_weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target_pos, follow_weight)

	# 预算按真实秒记账：一帧之内攒够的碎震叠不起来，只允许"每秒这么多"的量
	_budget_timer -= delta
	if _budget_timer <= 0.0:
		_budget_timer += 1.0
		_budget_left = GameBalance.TRAUMA_BUDGET

	# 方向性瞬时冲击衰减（高阻尼弹簧迅速回正）
	if _kick_offset.length_squared() > 0.01:
		_kick_offset = _kick_offset.lerp(Vector2.ZERO, minf(delta * 22.0, 1.0))
	else:
		_kick_offset = Vector2.ZERO

	if trauma > 0.0:
		trauma = maxf(trauma - trauma_decay * delta, 0.0)
		var shake_amt := GameBalance.shake_amount(trauma) * _intensity
		_t += delta * 28.0
		offset = Vector2(
			max_offset.x * shake_amt * _shake_axis(1.3, _t),
			max_offset.y * shake_amt * _shake_axis(3.7, _t)
		) + _kick_offset
		rotation = max_roll * shake_amt * _shake_axis(7.1, _t * 0.85)
	else:
		offset = _kick_offset
		rotation = 0.0

## 多频无公倍正弦合成的连续伪随机波形（平滑不刺眼）
func _shake_axis(seed_val: float, t: float) -> float:
	return 0.6 * sin(t * 1.7 + seed_val) + 0.4 * sin(t * 3.1 + seed_val * 2.1)

## 方向性冲击位移（Directional Kick）：沿受力方向猛推后迅速归零（受 shake_mult 约束）
func kick_directional(dir: Vector2, strength: float = 3.5) -> void:
	if _intensity <= 0.0 or dir.length_squared() < 0.001:
		return
	var norm_dir := dir.normalized()
	_kick_offset += norm_dir * minf(strength * _intensity, 9.0)
	offset += norm_dir * minf(strength * _intensity, 9.0)

## 叠加创伤值（0.0 ~ 1.0）：只在「值得看的节点」调用
## 精英/首领的登场·震地·伏诛、玩家受创、界碑聚灵阵、落雷命中 —— 普通命中与小怪死亡不给
func add_trauma(amount: float) -> void:
	if _intensity <= 0.0:
		return
	var grant := GameBalance.trauma_grant(amount, _budget_left)
	if grant <= 0.0:
		return
	_budget_left -= grant
	trauma = clampf(trauma + grant, 0.0, 1.0)

## 还剩多少预算（判据与调试读数用）
func trauma_budget_left() -> float:
	return _budget_left

## 镜头瞬时缩放冲击（Zoom Punch），用于聚灵阵爆发、精英击杀、大招等高潮时刻
func zoom_punch(punch_scale: float = 0.05, duration: float = 0.18) -> void:
	if _intensity <= 0.0:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	zoom = _base_zoom * (1.0 + punch_scale * _intensity)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "zoom", _base_zoom, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 兼容旧接口：按强度折算为 trauma 叠加
func shake(intensity: float = 4.0, _duration: float = 0.15) -> void:
	var mapped := clampf(intensity / 10.0, 0.08, 0.85)
	add_trauma(mapped)

