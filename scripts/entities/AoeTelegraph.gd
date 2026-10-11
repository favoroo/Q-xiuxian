class_name AoeTelegraph
extends Node2D

## 圆形 AoE 预警圈（Boss 震地冲击 / 丹爆傀儡自爆共用）。
## 「填满式」读法：半透明填充从圆心随进度扩张，填到外圈 = 伤害结算时刻，
## 玩家一眼读出「炸多大、还剩多久」，不再是一个只会闪的静圈。
## 铁律对齐：
##   - 范围视觉与判定同源：radius 必须由持有者赋成判定半径本身（同一常量/字段），
##     本组件不自算范围、不自判伤害，只画。
##   - progress 由持有者每帧驱动（计时真话源在持有者），组件只负责呈现。
##   - 取色走 GameStyle（唯一取色入口），不再散落硬编码橙红。

const EDGE_W_MIN := 3.0         ## 外圈描边起始线宽（对齐旧 SlamRing 的 3.0）
const EDGE_W_MAX := 5.0         ## 结算前外圈描边线宽（随进度加粗，越接近越醒目）
const FILL_ALPHA := 0.20        ## 填充峰值不透明度（半透明，不糊地面细节）
const EDGE_ALPHA_BASE := 0.55   ## 外圈描边基础不透明度
const PULSE_AMP := 0.10         ## 呼吸闪烁幅度（低幅提示"活着"，不抢进度可读性）
const PULSE_SPEED := 16.0       ## 呼吸频率（rad/s），末段加倍
const END_HIGHLIGHT_AT := 0.85  ## 进度超过此值视为"最后关头"：描边提亮、闪烁加急
const LEAD_EDGE_W := 2.0        ## 填充前沿亮边线宽

var radius: float = 100.0
var progress: float = 0.0   ## 0→1，由持有者每帧赋值；到 1 即结算时刻
var _clock: float = 0.0     ## 仅驱动呼吸闪烁的视觉时钟（不参与计时结算）

func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()

func _draw() -> void:
	var t := clampf(progress, 0.0, 1.0)
	var ending := t >= END_HIGHLIGHT_AT
	var pulse := sin(_clock * (PULSE_SPEED * (2.0 if ending else 1.0))) * PULSE_AMP
	var edge_alpha := clampf(EDGE_ALPHA_BASE + pulse + (0.25 if ending else 0.0), 0.0, 1.0)
	var c := GameStyle.BAD
	# 填充：从圆心长到判定半径，填满 = 炸
	if t > 0.01:
		draw_circle(Vector2.ZERO, radius * t, Color(c.r, c.g, c.b, FILL_ALPHA))
		# 填充前沿亮边：让「正在长大」这件事一眼可读
		if t < 1.0:
			draw_arc(Vector2.ZERO, radius * t, 0.0, TAU, 48, c.lightened(0.4), LEAD_EDGE_W, true)
	# 外描边：就是判定边界本身，随进度加粗、末段高亮
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, edge_alpha), lerpf(EDGE_W_MIN, EDGE_W_MAX, t), true)
