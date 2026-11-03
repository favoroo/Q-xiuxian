extends Node2D

## 机关布设落点预览（2026-11-03，v0.1.20）。
##
## 用户反馈「布设是瞎放」：主键进入「布设 / 太近」态时，在战场地面画出
## 落点虚影（绿 = 可落位，红 = 离已有机关太近）与外圈射程环。
##
## 纪律：纯表现层，不参与判定；位置与射程全部由 HudMechanismButton 用
## TurretCommand / WeaponData 的同一口径算好传进来（画多大 == 判多大）。
## 节点编号/可见性由宿主管理，这里只负责画。

var open: bool = false
var range_radius: float = 0.0

## 落点虚影半径：与 TurretUnit 的地面阵盘外缘（18px）同档，略放大让玩家看得见
const GHOST_RADIUS := 20.0
## 射程环分段数：大圆用 96 段足够顺滑，单次 _draw 成本可忽略
const RANGE_SEGMENTS := 96

func set_state(pos: Vector2, is_open: bool, radius: float) -> void:
	var r := maxf(0.0, radius)
	# 站着不动时逐帧调用不必重画（每帧一次的 96 段射程环白白烧）
	if visible and global_position == pos and open == is_open and is_equal_approx(range_radius, r):
		return
	global_position = pos
	open = is_open
	range_radius = r
	visible = true
	queue_redraw()

func _draw() -> void:
	var col: Color = GameStyle.JADE if open else GameStyle.BAD
	var edge: Color = GameStyle.JADE_EDGE if open else GameStyle.BAD_DK

	# 1. 落点虚影：半透明内盘 + 实缘 + 中心点（与机关阵盘同尺寸感）
	draw_circle(Vector2.ZERO, GHOST_RADIUS, GameStyle.with_alpha(col, 0.13))
	draw_arc(Vector2.ZERO, GHOST_RADIUS, 0.0, TAU, 48, GameStyle.with_alpha(edge, 0.85), 2.0, true)
	draw_circle(Vector2.ZERO, 3.0, GameStyle.with_alpha(col, 0.90))

	# 2. 射程环：极淡的一圈，告诉玩家这座机关能覆盖多远
	if range_radius > 1.0:
		draw_arc(Vector2.ZERO, range_radius, 0.0, TAU, RANGE_SEGMENTS,
			GameStyle.with_alpha(col, 0.16), 1.5, true)

	# 3. 落点十字：压在地面纹上也能一眼找到落点
	var cross := GameStyle.with_alpha(edge, 0.55)
	draw_line(Vector2(-GHOST_RADIUS - 6.0, 0), Vector2(-GHOST_RADIUS + 2.0, 0), cross, 1.0)
	draw_line(Vector2(GHOST_RADIUS - 2.0, 0), Vector2(GHOST_RADIUS + 6.0, 0), cross, 1.0)
	draw_line(Vector2(0, -GHOST_RADIUS - 6.0), Vector2(0, -GHOST_RADIUS + 2.0), cross, 1.0)
	draw_line(Vector2(0, GHOST_RADIUS - 2.0), Vector2(0, GHOST_RADIUS + 6.0), cross, 1.0)
