class_name AbyssFalloffLayer
extends Node2D

## 战台外九幽深渊虚空与坠崖平滑衰减层（消除生硬直角切线）
## 位于地砖之上，BeyondBoundaryLayer 之下。
## 纯静态一次性 _draw()，四段梯形顶点双线性插值实现自然坠落深渊感，零每帧 CPU 开销。

var half_extent: float = 480.0
var ground_extent: float = 2400.0
var falloff_width: float = 120.0

const VOID_COLOR := Color(0.015, 0.025, 0.04, 0.98)

func _ready() -> void:
	z_index = 0

func _draw() -> void:
	var h: float = half_extent
	var h_fade: float = h + falloff_width
	var g: float = ground_extent

	var col_inner := Color(VOID_COLOR.r, VOID_COLOR.g, VOID_COLOR.b, 0.0)
	var col_outer := VOID_COLOR

	# 1. 四段 45° 梯形渐变带（从 h 到 h + falloff_width）
	# 上梯形（内缘 -h 到外缘 -h_fade）
	draw_polygon(
		PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h_fade, -h_fade), Vector2(-h_fade, -h_fade)]),
		PackedColorArray([col_inner, col_inner, col_outer, col_outer])
	)
	# 右梯形
	draw_polygon(
		PackedVector2Array([Vector2(h, -h), Vector2(h, h), Vector2(h_fade, h_fade), Vector2(h_fade, -h_fade)]),
		PackedColorArray([col_inner, col_inner, col_outer, col_outer])
	)
	# 下梯形
	draw_polygon(
		PackedVector2Array([Vector2(h, h), Vector2(-h, h), Vector2(-h_fade, h_fade), Vector2(h_fade, h_fade)]),
		PackedColorArray([col_inner, col_inner, col_outer, col_outer])
	)
	# 左梯形
	draw_polygon(
		PackedVector2Array([Vector2(-h, h), Vector2(-h, -h), Vector2(-h_fade, -h_fade), Vector2(-h_fade, h_fade)]),
		PackedColorArray([col_inner, col_inner, col_outer, col_outer])
	)

	# 2. 梯形外缘到地砖边缘的外围实心深渊遮罩
	# 上外块
	draw_rect(Rect2(-g, -g, g * 2.0, g - h_fade), col_outer, true)
	# 下外块
	draw_rect(Rect2(-g, h_fade, g * 2.0, g - h_fade), col_outer, true)
	# 左外块
	draw_rect(Rect2(-g, -h_fade, g - h_fade, h_fade * 2.0), col_outer, true)
	# 右外块
	draw_rect(Rect2(h_fade, -h_fade, g - h_fade, h_fade * 2.0), col_outer, true)
