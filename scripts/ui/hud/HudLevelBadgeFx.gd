class_name HudLevelBadgeFx
extends Control

## Lv 徽记升级特效（一次性自毁）：斜切描边光环扩散 ×2 + 星屑碎片迸发。
## 为什么不用圆环/辉光：本项目 UI 无圆角无柔光，光环沿用 GameStyle 家族的斜切描边框，
## 碎片是微型平行四边形 —— 版画语言一致才不违和。
## 全程序化（Panel 描边 + _draw 多边形），零贴图；碎片角度/距离/转速按序号取确定性值，
## 不进随机源 ⇒ 判据可钉、连放多份也不重样（相位由序号错开）。

## 总时长：升级是攒点制不打断战斗，反馈必须一闪而过（< 0.6s）
const TOTAL_DUR := 0.5
## 光环：从徽记轮廓向外扩的倍率 / 错峰间隔 / 存活时长
const RING_EXPAND := 2.2
const RING_STAGGER := 0.09
const RING_DUR := 0.42
const RING_PEAK_ALPHA := 0.85
## 星屑：片数 / 半边长 / 起始半径与档距 / 自旋速率
const SHARD_COUNT := 10
const SHARD_HALF := 3.0
const SHARD_DIST_MIN := 26.0
const SHARD_DIST_STEP := 9.0
const SHARD_SPIN := 4.2

var _badge_size := Vector2.ZERO
var _shards: Array[Dictionary] = []
var _t := 0.0

## 在 host 上生成一次特效：以 badge 中心为原点扩散，放完自毁（重复调用即叠放多份）
static func burst(host: Control, badge: Control) -> void:
	if host == null or badge == null or not badge.is_inside_tree():
		return
	var fx := HudLevelBadgeFx.new()
	fx.name = "LevelBadgeFx"
	fx._badge_size = badge.size
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(fx)
	fx.global_position = badge.get_global_rect().get_center()
	fx._spawn_rings()
	fx._spawn_shards()
	var tw := fx.create_tween()
	tw.tween_method(fx._set_progress, 0.0, 1.0, TOTAL_DUR)
	tw.tween_callback(fx.queue_free)

func _spawn_rings() -> void:
	for i in 2:
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 起始轮廓略大于徽记，别让描边一出生就压在徽记边上
		var ring_size := _badge_size + Vector2(12, 10)
		ring.size = ring_size
		ring.position = -ring_size * 0.5
		ring.pivot_offset = ring_size * 0.5
		ring.add_theme_stylebox_override("panel", GameStyle.outlined_panel(
			GameStyle.with_alpha(GameStyle.INK, 0.0),
			GameStyle.JADE_EDGE if i == 0 else GameStyle.GOLD, 2, GameStyle.SLANT_BAND))
		ring.modulate.a = 0.0
		add_child(ring)
		var delay := i * RING_STAGGER
		# 淡入→淡出与扩散各走一条 tween：alpha 先到峰值再线性退场，scale 一路 EASE_OUT 扩出去
		var tw_a := ring.create_tween()
		tw_a.tween_interval(delay)
		tw_a.tween_property(ring, "modulate:a", RING_PEAK_ALPHA, 0.05)
		tw_a.tween_property(ring, "modulate:a", 0.0, RING_DUR - 0.05)
		var tw_s := ring.create_tween()
		tw_s.tween_interval(delay)
		tw_s.tween_property(ring, "scale", Vector2.ONE * RING_EXPAND, RING_DUR) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 碎片参数确定性生成：圆周均匀布角 + 序号奇偶错相，半径/转速按 i % 3 分档
func _spawn_shards() -> void:
	for i in SHARD_COUNT:
		var dir := Vector2.from_angle(TAU * float(i) / float(SHARD_COUNT) + 0.35 * float(i % 2))
		_shards.append({
			"dir": dir,
			"dist": SHARD_DIST_MIN + float(i % 3) * SHARD_DIST_STEP,
			"spin": (1.0 if i % 2 == 0 else -1.0) * SHARD_SPIN * (0.7 + 0.3 * float(i % 3)),
			"col": GameStyle.JADE if i % 2 == 0 else GameStyle.GOLD_EDGE,
		})

func _set_progress(v: float) -> void:
	_t = v
	queue_redraw()

func _draw() -> void:
	for s in _shards:
		var dir: Vector2 = s["dir"]
		var col: Color = s["col"]
		# 位移走 ease-out（迸出即减速），alpha 后半程加速消隐
		var ease_t := 1.0 - pow(1.0 - _t, 2.0)
		var half: float = SHARD_HALF * (1.0 - 0.4 * _t)
		col.a = (1.0 - _t) * 0.95
		draw_set_transform(dir * float(s["dist"]) * ease_t, dir.angle() + float(s["spin"]) * _t, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
		]), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
