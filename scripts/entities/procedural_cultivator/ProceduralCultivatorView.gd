class_name ProceduralCultivatorView
extends Node2D

## 程序化修仙角色动作视图节点
## 统一管理动作状态机（Idle/Run/Dash/Attack/Hit）、朝向解算、物理插值与打击感形变
## 为后续所有道统人物提供标准驱动容器

@export var config: CultivatorVisualConfig
@export var renderer_script: GDScript = HollowKnightCultivatorRenderer

var renderer: CultivatorRendererBase

# 动作计时器
var _dash_timer: float = 0.0
var _dash_duration: float = 0.22
var _attack_timer: float = 0.0
var _attack_duration: float = 0.26
var _hit_timer: float = 0.0
var _hit_duration: float = 0.15

# 朝向与翻转
var flip_h: bool = false:
	set(val):
		flip_h = val
		if renderer:
			renderer.flip_h = val
			renderer.scale.x = -absf(renderer.scale.x) if flip_h else absf(renderer.scale.x)

var facing: String = "s"

func _ready() -> void:
	_init_renderer()

func _init_renderer() -> void:
	if renderer != null:
		renderer.queue_free()

	if renderer_script:
		renderer = renderer_script.new() as CultivatorRendererBase
	else:
		renderer = HollowKnightCultivatorRenderer.new()

	if config:
		renderer.config = config
	add_child(renderer)

func _process(delta: float) -> void:
	if renderer == null:
		return

	# 1. 冲刺计时器更新
	if _dash_timer > 0.0:
		_dash_timer -= delta
		var prog := 1.0 - clampf(_dash_timer / _dash_duration, 0.0, 1.0)
		renderer.dash_progress = prog
		if _dash_timer <= 0.0:
			renderer.current_action = CultivatorRendererBase.Action.IDLE

	# 2. 攻击斩击计时器更新
	elif _attack_timer > 0.0:
		_attack_timer -= delta
		var prog := 1.0 - clampf(_attack_timer / _attack_duration, 0.0, 1.0)
		renderer.attack_progress = prog
		if _attack_timer <= 0.0:
			renderer.current_action = CultivatorRendererBase.Action.IDLE

	# 3. 受击硬直计时器更新
	if _hit_timer > 0.0:
		_hit_timer -= delta
		var prog := 1.0 - clampf(_hit_timer / _hit_duration, 0.0, 1.0)
		renderer.hit_progress = prog
		if _hit_timer <= 0.0 and renderer.current_action == CultivatorRendererBase.Action.HIT:
			renderer.current_action = CultivatorRendererBase.Action.IDLE

# ==================== 动作控制核心接口 ====================

## 触发待机
func play_idle() -> void:
	if _dash_timer > 0.0 or _attack_timer > 0.0:
		return
	if renderer:
		renderer.current_action = CultivatorRendererBase.Action.IDLE

## 触发奔跑（带步态相位与移速比率）
func play_run(phase: float, air: float, speed_ratio: float, lean: float = 0.0) -> void:
	if _dash_timer > 0.0 or _attack_timer > 0.0:
		return
	if renderer:
		renderer.current_action = CultivatorRendererBase.Action.RUN
		renderer.gait_phase = phase
		renderer.air = air
		renderer.speed_ratio = speed_ratio
		renderer.lean_angle = lean

## 触发冲刺
func play_dash(duration: float = 0.22) -> void:
	_dash_duration = maxf(duration, 0.05)
	_dash_timer = _dash_duration
	if renderer:
		renderer.current_action = CultivatorRendererBase.Action.DASH
		renderer.dash_progress = 0.0

## 触发攻击斩击
func play_attack(duration: float = 0.26) -> void:
	_attack_duration = maxf(duration, 0.08)
	_attack_timer = _attack_duration
	if renderer:
		renderer.current_action = CultivatorRendererBase.Action.ATTACK
		renderer.attack_progress = 0.0

## 触发受击
func play_hit(duration: float = 0.15) -> void:
	_hit_duration = maxf(duration, 0.05)
	_hit_timer = _hit_duration
	if renderer:
		renderer.current_action = CultivatorRendererBase.Action.HIT
		renderer.hit_progress = 0.0

## 8 方向平滑映射到 3 视界角度
func set_facing_dir(face_str: String, is_flip: bool) -> void:
	facing = face_str
	self.flip_h = is_flip

	if renderer == null:
		return

	match face_str:
		"s":
			renderer.current_angle = CultivatorRendererBase.Angle.FRONT
		"n":
			renderer.current_angle = CultivatorRendererBase.Angle.BACK
		_:
			renderer.current_angle = CultivatorRendererBase.Angle.SIDE

## 换装/切换角色渲染器工厂接口（为后续其他角色扩展定好标准）
func set_character(renderer_cls: GDScript, cfg: CultivatorVisualConfig = null) -> void:
	renderer_script = renderer_cls
	config = cfg
	_init_renderer()
