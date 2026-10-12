class_name SpiritHealer
extends Node2D

## 治疗灵兽（治疗技能附带召唤，2026-10-11 技能改版）：跟随玩家缓飘的光灵，每秒一拍把
## SkillData.renewal 的 pet_heal_pct 比例灌回玩家，pet_duration 秒后消散；重施治疗按组替换旧灵。
## 组别铁律对齐 SpiritBeast 头注：只挂自己的 spirit_healers 组（重施替换按组找旧灵），
## 绝不进 enemies/turrets/gems/chests 四个波末清场组，也无任何碰撞体积——纯跟随渲染体，
## 敌人打不到它、玩家的武器也索敌不到它。
## 视觉：程序化光灵（增益绿光核 + 呼吸光环 + 治疗脉冲扩散环），纯 _draw 不挂粒子（移动端零开销）。
## 满血一拍不空跳：回不上血就不飘假数字、不放空脉冲，光灵只是安静飘着等下一拍。

const PULSE_INTERVAL: float = 1.0  ## 治疗节拍（秒/拍）
const FOLLOW_DIST: float = 34.0    ## 跟随绕飘半径（px）
const HEIGHT_OFFSET: float = 30.0  ## 悬在玩家头顶上方（px，负 Y 向上）
const DISSOLVE_SEC: float = 0.35   ## 消散动画时长（秒）

var heal_pct: float = 0.02  ## 每拍回复玩家最大气血比例（Player._do_renewal 按 SkillData 写入）
var lifetime: float = 8.0   ## 存活时长（秒），耗尽即消散
var target: Player = null   ## 跟随与治疗目标（召唤者）

var _age: float = 0.0
var _pulse_timer: float = 1.0  ## 首拍延迟 1 秒：落地先飘半拍再开工，避免召出瞬间和治疗闪 frame 重叠
var _pulse_fx: float = -1.0    ## 治疗脉冲扩散动画进度（0~1，<0 = 无脉冲）
var _orbit_sign: float = 1.0   ## 绕飘方向（固定一边，避免临界抖动）
var _dying: bool = false

func _ready() -> void:
	add_to_group("spirit_healers")

func _physics_process(delta: float) -> void:
	if _dying:
		return
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	_age += delta
	# 跟随：绕玩家头顶缓飘的柔和轨迹（椭圆绕飘 + 悬浮起伏），指数趋近不硬贴
	var t := _age * 0.9
	var offset := Vector2(
		cos(t) * FOLLOW_DIST * _orbit_sign,
		sin(t * 1.3) * FOLLOW_DIST * 0.6 - HEIGHT_OFFSET + sin(_age * 2.1) * 5.0)
	global_position = global_position.lerp(target.global_position + offset, minf(1.0, 6.0 * delta))
	# 脉冲扩散动画推进
	if _pulse_fx >= 0.0:
		_pulse_fx += delta * 2.6
		if _pulse_fx > 1.0:
			_pulse_fx = -1.0
	# 治疗节拍（终局后停拍，光灵陪着玩家飘到结算）
	if not GameManager.is_game_over:
		_pulse_timer -= delta
		if _pulse_timer <= 0.0:
			_pulse_timer += PULSE_INTERVAL
			_heal_pulse()
	# 寿命
	lifetime -= delta
	if lifetime <= 0.0:
		_dissolve()
		return
	queue_redraw()

func _heal_pulse() -> void:
	if _dying or target == null:
		return
	var before: float = target.current_health
	target.heal(target.max_health * heal_pct, true)
	var gained: float = target.current_health - before
	if gained <= 0.01:
		return
	_pulse_fx = 0.0
	DamageNumber.spawn(get_parent(), target.global_position + Vector2(0, -22), int(gained), false, "+" + str(int(gained)))

## 消散：收拢淡出后自行释放（先出组，防止重施替换拿到正在消散的旧灵）
func _dissolve() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group("spirit_healers")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), DISSOLVE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, DISSOLVE_SEC)
	tw.chain().tween_callback(queue_free)

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 3.2)  # 呼吸相位
	var core_r := 7.0 + 1.5 * pulse
	# 外晕 → 中晕 → 光核 → 高光，全走 GameStyle 增益绿
	draw_circle(Vector2.ZERO, core_r * 2.6, Color(GameStyle.GOOD, 0.10 + 0.06 * pulse))
	draw_circle(Vector2.ZERO, core_r * 1.6, Color(GameStyle.GOOD, 0.22))
	draw_circle(Vector2.ZERO, core_r, GameStyle.GOOD)
	draw_circle(Vector2(0, -2.0), core_r * 0.45, Color(1.0, 1.0, 1.0, 0.85))
	if _pulse_fx >= 0.0:
		var r := lerpf(10.0, 32.0, _pulse_fx)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(GameStyle.GOOD, 1.0 - _pulse_fx), 2.0)
