class_name LightningBolt
extends Node2D

## 五雷法牌引雷演出：从法器射向落雷点的锯齿闪电（细亮芯 + 宽光晕），短暂显示后自毁

var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var width_mult: float = 1.0   # 星级越高雷身越粗
## 光柱色由落雷法器决定（WeaponData 的 burst_tint）：三把落雷法器共用一条白蓝电柱，
## 玩家分不清"天降离火"与"玄石大印"，与弹丸那笔账是同一个毛病。
var tint: Color = GLOW_COLOR

const CORE_COLOR := Color(1.0, 0.98, 0.85, 1.0)
const GLOW_COLOR := Color(0.55, 0.85, 1.0, 0.42)

func _ready() -> void:
	global_position = from
	var points := _build_jagged_points()
	_add_line(points, 10.0 * width_mult, tint)
	_add_line(points, 3.2 * width_mult, CORE_COLOR if tint == GLOW_COLOR else Color(1.0, 0.97, 0.9, 1.0))
	modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _build_jagged_points() -> PackedVector2Array:
	var segs := maxi(int(from.distance_to(to) / 24.0), 6)
	var dir := to - from
	var side := dir.orthogonal().normalized()
	var points := PackedVector2Array()
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var p := dir * t
		if i > 0 and i < segs:
			var amp := 15.0 * sin(t * PI)
			p += side * randf_range(-amp, amp)
		points.append(p)
	return points

func _add_line(points: PackedVector2Array, width: float, color: Color) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 25
	add_child(line)
