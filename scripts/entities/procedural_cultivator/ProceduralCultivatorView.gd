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

# 技能外观动态修饰目标与平滑插值状态
var _target_aura_type: String = ""
var _target_eye_color: Color = Color.TRANSPARENT
var _target_eye_boost: float = 0.0
var _target_cloak_color: Color = Color.TRANSPARENT
var _target_cloak_shimmer: float = 0.0
var _target_sigil_boost: float = 0.0
var _target_motes_boost: float = 0.0

var _cur_eye_boost: float = 0.0
var _cur_cloak_shimmer: float = 0.0
var _cur_sigil_boost: float = 0.0
var _cur_motes_boost: float = 0.0

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
		if renderer is HollowKnightCultivatorRenderer:
			(renderer as HollowKnightCultivatorRenderer).set_visual_config(config)
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

	# 4. 技能动态外观平滑插值过渡（淡入淡出）
	var step: float = delta * 6.5
	_cur_eye_boost = move_toward(_cur_eye_boost, _target_eye_boost, step)
	_cur_cloak_shimmer = move_toward(_cur_cloak_shimmer, _target_cloak_shimmer, step)
	_cur_sigil_boost = move_toward(_cur_sigil_boost, _target_sigil_boost, step)
	_cur_motes_boost = move_toward(_cur_motes_boost, _target_motes_boost, step)

	renderer.skill_aura_type = _target_aura_type
	renderer.eye_override_color = _target_eye_color
	renderer.eye_glow_boost = _cur_eye_boost
	renderer.cloak_shimmer_color = _target_cloak_color
	renderer.cloak_shimmer_intensity = _cur_cloak_shimmer
	renderer.sigil_boost = _cur_sigil_boost
	renderer.motes_boost = _cur_motes_boost

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

## 快速按道统 ID 配置角色（全套插槽预设自动化装配）
func setup_character_id(cid: String) -> void:
	var cfg := CultivatorVisualConfig.get_config(cid)
	config = cfg
	if renderer is HollowKnightCultivatorRenderer:
		(renderer as HollowKnightCultivatorRenderer).set_visual_config(cfg)
	else:
		_init_renderer()

## 触发或更新技能法相视觉（眼睛变色、斗篷流光、道印激活、周天灵气）
func set_skill_visual(skill_id: String, active: bool, intensity: float = 1.0) -> void:
	if not active:
		if _target_aura_type == skill_id:
			_target_aura_type = ""
			_target_eye_color = Color.TRANSPARENT
			_target_eye_boost = 0.0
			_target_cloak_color = Color.TRANSPARENT
			_target_cloak_shimmer = 0.0
			_target_sigil_boost = 0.0
			_target_motes_boost = 0.0
		return

	_target_aura_type = skill_id
	var g_gold := GameStyle.GOLD_EDGE
	var g_jade := GameStyle.JADE_EDGE
	var g_good := GameStyle.GOOD
	match skill_id:
		"aegis": # 金光护体：神圣纯金白芒眼眸、极亮鎏金斗篷流光反光、额印全亮、周天金芒
			_target_eye_color = Color(1.0, 0.92, 0.55, 0.95)
			_target_eye_boost = 1.1 * intensity
			_target_cloak_color = Color(g_gold.r, g_gold.g, g_gold.b, 1.0)
			_target_cloak_shimmer = 1.1 * intensity
			_target_sigil_boost = 1.0 * intensity
			_target_motes_boost = 1.0 * intensity
		"haste": # 疾风咒：超频疾风青芒眼眸、疾风青金斗篷反光、高速风刃灵气
			_target_eye_color = Color(0.65, 0.95, 0.85, 0.90)
			_target_eye_boost = 0.85 * intensity
			_target_cloak_color = Color(g_gold.r, g_gold.g, g_gold.b, 0.9)
			_target_cloak_shimmer = 0.8 * intensity
			_target_sigil_boost = 0.75 * intensity
			_target_motes_boost = 0.85 * intensity
		"gale": # 神行术：灵动风灵青金眼眸、斗篷微风流光、御风灵气
			_target_eye_color = Color(0.55, 0.92, 0.78, 0.85)
			_target_eye_boost = 0.7 * intensity
			_target_cloak_color = Color(g_jade.r, g_jade.g, g_jade.b, 0.85)
			_target_cloak_shimmer = 0.7 * intensity
			_target_sigil_boost = 0.5 * intensity
			_target_motes_boost = 0.75 * intensity
		"dash": # 缩地成寸：瞬身纯白剑意锋芒爆闪、斗篷极速流光
			_target_eye_color = Color(1.0, 1.0, 1.0, 1.0)
			_target_eye_boost = 1.25 * intensity
			_target_cloak_color = Color(1.0, 0.95, 0.8, 1.0)
			_target_cloak_shimmer = 1.2 * intensity
			_target_sigil_boost = 0.85 * intensity
			_target_motes_boost = 0.95 * intensity
		"renewal": # 回春术：温润生机翠玉眼眸、斗篷甘露青碧灵波、生机道韵
			_target_eye_color = Color(g_good.r, g_good.g, g_good.b, 0.95)
			_target_eye_boost = 0.85 * intensity
			_target_cloak_color = Color(g_good.r, g_good.g, g_good.b, 0.9)
			_target_cloak_shimmer = 0.85 * intensity
			_target_sigil_boost = 0.95 * intensity
			_target_motes_boost = 0.95 * intensity
		_:
			_target_eye_color = Color.TRANSPARENT
			_target_eye_boost = 0.0
			_target_cloak_color = Color.TRANSPARENT
			_target_cloak_shimmer = 0.0
			_target_sigil_boost = 0.0
			_target_motes_boost = 0.0

