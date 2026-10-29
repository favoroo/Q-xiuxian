class_name ProceduralEnemyView
extends Node2D

## 敌人程序化矢量视图容器节点
## 挂载于 EnemyBase 下，负责桥接宿主物理状态与 HollowKnightEnemyRenderer 渲染管线
## 2026-10-24 全量 setter 脏值短路：EnemyBase 每物理帧同步 12 项状态（35 敌 × 60Hz ≈ 2.5 万次
## setter/秒），绝大多数帧值未变；不判新旧会白穿透一层转发（口径同 renderer.flip_h 的
## 2026-10-13 掉帧根因注释）。阈值用精确相等 —— 只为拦「完全没变」的写，变了必然放行。

@export var config: EnemyVisualConfig

var renderer: HollowKnightEnemyRenderer

var flip_h: bool = false:
	set(val):
		if val == flip_h:
			return
		flip_h = val
		if renderer:
			renderer.flip_h = val

var facing: String = "s":
	set(val):
		if val == facing:
			return
		facing = val
		if renderer:
			renderer.facing = val

var bank_angle: float = 0.0:
	set(val):
		if val == bank_angle:
			return
		bank_angle = val
		if renderer:
			renderer.bank_angle = val

var advance: float = 0.0:
	set(val):
		if val == advance:
			return
		advance = val
		if renderer:
			renderer.advance = val

var speed_ratio: float = 1.0:
	set(val):
		if val == speed_ratio:
			return
		speed_ratio = val
		if renderer:
			renderer.speed_ratio = val

var is_moving: bool = false:
	set(val):
		if val == is_moving:
			return
		is_moving = val
		if renderer:
			renderer.is_moving = val

## 步态相位（弧度）：EnemyBase 按实际位移推进，渲染器摆翼/蠕波与之同相
var gait_phase: float = 0.0:
	set(val):
		if val == gait_phase:
			return
		gait_phase = val
		if renderer:
			renderer.gait_phase = val

var special_state: float = 0.0:
	set(val):
		if val == special_state:
			return
		special_state = val
		if renderer:
			renderer.special_state = val

var aim_dir: Vector2 = Vector2.ZERO:
	set(val):
		if val == aim_dir:
			return
		aim_dir = val
		if renderer:
			renderer.aim_dir = val

## 生命比例（0~1，1=满血）：渲染层据此加大喘息幅度/压低浮沉/加残血歪斜。
## 纯表现读数，不参与任何判定（分层铁律：渲染层只读状态）。
var hp_ratio: float = 1.0:
	set(val):
		if val == hp_ratio:
			return
		hp_ratio = val
		if renderer:
			renderer.hp_ratio = val

func trigger_recoil(dir: Vector2 = Vector2.ZERO) -> void:
	if renderer != null:
		renderer.trigger_recoil(dir)

## 机制事件脉冲（治疗/产卵等）：渲染器据此演一次动作，纯表现
func trigger_cast_pulse() -> void:
	if renderer != null:
		renderer.trigger_cast_pulse()

func get_weapon_tip_global_pos() -> Vector2:
	if renderer != null:
		return renderer.to_global(renderer.get_tip_local_pos())
	return global_position

## 鼓妖光环标记（0/1）：脚下琥珀细环，读出「这只怪被加速了、先杀鼓妖」（土豆兄弟 Buffer 红描边同思路）
var aura_level: float = 0.0:
	set(val):
		if aura_level == val:
			return
		aura_level = val
		queue_redraw()

func _draw() -> void:
	# 画在视图容器自身（y=0 是敌人身体中心），脚下偏移对齐 renderer 的地面阴影带（y≈14~16）
	if aura_level > 0.0:
		draw_arc(Vector2(0.0, 15.0), 18.0, 0.0, TAU, 24, GameStyle.JADE, 2.0, true)

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
