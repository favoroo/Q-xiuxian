class_name BeyondBoundaryLayer
extends Node2D

## 结界外深渊远景剪影层（幽冥残峰 / 南侧断崖 / 古刹残柱），从 GroundDecorLayer 拆出。
## 纯静态一次性 _draw()，每帧只挪 position 做视差（不触发重绘，零绘制开销）。
## 视差用「反向跟相机」而非 ParallaxLayer：后者是 CanvasLayer 系，要和世界坐标系
## 的结界边界对齐得调 motion mirroring，弯道多；直接 position = cam * (1 - f) 一目了然。

## 视差系数：0.45 = 远景以相机 45% 的速度移动，立刻出纵深但不穿帮
const PARALLAX_FACTOR := 0.45

var half_extent: float = 440.0

func _ready() -> void:
	# 与 GroundDecorLayer 同档：地砖之上、ArenaVisualLayer 之下，不越过实体层
	z_index = 0

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		position = cam.global_position * (1.0 - PARALLAX_FACTOR)

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4217  # 固定种子确保装饰确定性，不占用或污染 GameManager.rng 战斗流

	var h: float = half_extent
	var col_shadow := Color(0.015, 0.025, 0.04, 0.95)
	var col_stone := Color(0.025, 0.04, 0.06, 0.90)
	var col_faint_cyan := Color(0.18, 0.55, 0.75, 0.14)

	# 北侧远景：幽冥残峰奇石起伏（y 在 -450 ~ -680 之间）。
	# 横向留足 ±(h+180) 余量：相机拉到战场边缘时视差回挪，剪影仍需盖住视口缺口。
	var north_pts := PackedVector2Array()
	north_pts.append(Vector2(-h - 180.0, -h - 20.0))
	var peak_x: float = -h - 180.0
	while peak_x < h + 180.0:
		var step: float = rng.randf_range(35.0, 75.0)
		peak_x += step
		var peak_y: float = -h - rng.randf_range(40.0, 160.0)
		north_pts.append(Vector2(peak_x, peak_y))
	north_pts.append(Vector2(h + 180.0, -h - 20.0))
	if north_pts.size() >= 3:
		draw_colored_polygon(north_pts, col_shadow)
		draw_polyline(north_pts, col_stone, 1.5)

	# 南侧断崖远影（y 在 +450 ~ +640 之间）
	var south_pts := PackedVector2Array()
	south_pts.append(Vector2(-h - 180.0, h + 20.0))
	var s_x: float = -h - 180.0
	while s_x < h + 180.0:
		var step_s: float = rng.randf_range(40.0, 80.0)
		s_x += step_s
		var s_y: float = h + rng.randf_range(40.0, 140.0)
		south_pts.append(Vector2(s_x, s_y))
	south_pts.append(Vector2(h + 180.0, h + 20.0))
	if south_pts.size() >= 3:
		draw_colored_polygon(south_pts, col_shadow)
		draw_polyline(south_pts, col_stone, 1.5)

	# 东西两侧深渊中矗立的古刹残柱剪影
	var pillar_xs := [-h - 60.0, -h - 130.0, h + 60.0, h + 130.0]
	for px in pillar_xs:
		var py_base: float = rng.randf_range(-h + 60.0, h - 60.0)
		var p_w: float = rng.randf_range(20.0, 36.0)
		var p_h: float = rng.randf_range(60.0, 120.0)
		var sign_x: float = -1.0 if px < 0.0 else 1.0
		var pts := PackedVector2Array([
			Vector2(px, py_base),
			Vector2(px + sign_x * p_w * 0.4, py_base - p_h * 0.7),
			Vector2(px + sign_x * p_w * 0.8, py_base - p_h),
			Vector2(px + sign_x * p_w, py_base)
		])
		draw_colored_polygon(pts, col_stone)
		draw_polyline(pts, col_shadow, 1.5)
		# 柱顶微弱幽芒
		draw_circle(Vector2(px + sign_x * p_w * 0.8, py_base - p_h), 3.0, col_faint_cyan)
