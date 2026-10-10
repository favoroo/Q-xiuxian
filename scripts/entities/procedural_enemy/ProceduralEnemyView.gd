class_name ProceduralEnemyView
extends Node2D

## 敌人程序化矢量视图容器节点
## 挂载于 EnemyBase 下，负责桥接宿主物理状态与 HollowKnightEnemyRenderer 渲染管线

@export var config: EnemyVisualConfig

var renderer: HollowKnightEnemyRenderer

var flip_h: bool = false:
	set(val):
		flip_h = val
		if renderer:
			renderer.flip_h = val

var facing: String = "s":
	set(val):
		facing = val
		if renderer:
			renderer.facing = val

var bank_angle: float = 0.0:
	set(val):
		bank_angle = val
		if renderer:
			renderer.bank_angle = val

var advance: float = 0.0:
	set(val):
		advance = val
		if renderer:
			renderer.advance = val

var speed_ratio: float = 1.0:
	set(val):
		speed_ratio = val
		if renderer:
			renderer.speed_ratio = val

var is_moving: bool = false:
	set(val):
		is_moving = val
		if renderer:
			renderer.is_moving = val

var special_state: float = 0.0:
	set(val):
		special_state = val
		if renderer:
			renderer.special_state = val

func _ready() -> void:
	if renderer == null:
		_init_renderer()

func _init_renderer() -> void:
	renderer = HollowKnightEnemyRenderer.new()
	renderer.use_parent_material = true
	if config:
		renderer.config = config
	renderer.flip_h = flip_h
	renderer.facing = facing
	add_child(renderer)

## 外部初始化敌种配置入口
func setup(eid: String, is_elite: bool = false, is_boss: bool = false, is_final: bool = false) -> void:
	config = EnemyVisualConfig.get_config(eid, is_elite, is_boss, is_final)
	if renderer == null:
		_init_renderer()
	else:
		renderer.config = config
