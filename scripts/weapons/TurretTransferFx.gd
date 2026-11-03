extends Node2D

## 机关布设 / 收回的「器核投送」演出（2026-11-03 二次打磨）。
##
## 用户口径：布设不能只在落点凭空冒出来，要看得见「从人物身上出去」；
## 收回也不能只在机关脚下收拢消失，要看得见「从机关回到人物身上」。
## 与 TurretPlacementFx 的分工：
##   TurretPlacementFx = 落点的地面法阵（铺开 / 收拢），挂在目标点；
##   本节点 = 空中飞行的那枚器核（抛物线 + 拖尾 + 沿途碎屑），挂在战场层。
##
## 纪律：纯表现层，不参与判定。机关落点坐标仍是判定真值（TurretHandler 当刻写入），
## 飞行只负责让本体延后显形；收回时器核追着玩家当前位置飞（follow）。
## 不占对象池 —— 机关布设/收回是低频操作，同屏最多几朵。

const KIND_DEPLOY := 0
const KIND_RECALL := 1

## 飞行时长：布设略长（器核展开），收回略短（收得干脆）
const DEPLOY_SEC := 0.24
const RECALL_SEC := 0.22
## 抛物线抬升量（垂直于起终点连线）
const ARC_LIFT := 26.0
## 拖尾采样点数
const TRAIL_SAMPLES := 6

var _kind: int = KIND_DEPLOY
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _color: Color = GameStyle.GOLD_EDGE
var _elapsed: float = 0.0
var _duration: float = DEPLOY_SEC
var _spark_timer: float = 0.0
## 收回时追着玩家飞（人物在走位也能收进手里）
var _follow: Node2D = null
var _done: bool = false

## 宿主在 add_child 后调用：from/to 都是世界坐标，follow 仅收回用
func play(from_pos: Vector2, to_pos: Vector2, kind: int, elem: String, follow: Node2D = null) -> void:
	_kind = kind
	_from = from_pos
	_to = to_pos
	_follow = follow
	_color = GameStyle.ELEMENT_COLORS.get(elem, GameStyle.GOLD_EDGE)
	_duration = DEPLOY_SEC if kind == KIND_DEPLOY else RECALL_SEC
	_elapsed = 0.0
	_spark_timer = 0.0
	_done = false
	# 器核飞在人物/机关之上，别被地面法阵盖住
	z_index = 6
	queue_redraw()
	# 起手：布设溅金属屑（机关是器，不是法术）；收回吸出一圈灵光点
	if kind == KIND_DEPLOY:
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, from_pos, _color, 0.45, true)
	else:
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, from_pos, _color, 0.5, true)

func kind() -> int:
	return _kind

## 判据用：起点 / 当前终点（收回时终点会追着玩家走）
func origin() -> Vector2:
	return _from

func destination() -> Vector2:
	return _to

func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _follow != null and is_instance_valid(_follow):
		var target := _follow.global_position + Vector2(0.0, -10.0)
		_to = _to.lerp(target, minf(delta * 14.0, 1.0))
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = 0.055
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, _point_at(_t()), _color, 0.28, true)
	queue_redraw()
	if _elapsed >= _duration:
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	# 落点/入手的最后一记：布设交给机关本体播 impact_blunt，这里只补碎屑；
	# 收回在人物身上补一记轻响，让「收进手里」有落点。
	if _kind == KIND_DEPLOY:
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, _to, _color, 0.6, true)
	else:
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, _to, _color, 0.65, true)
		AudioManager.play_sfx("equip", 0.45)
	queue_free()

func _t() -> float:
	return clampf(_elapsed / maxf(0.01, _duration), 0.0, 1.0)

## 二次贝塞尔：中点沿法线抬起，飞出一条弧线而不是直线
func _point_at(t: float) -> Vector2:
	var span := _to - _from
	if span.length_squared() < 0.0001:
		return _from
	var dir := span.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var lift := ARC_LIFT * (1.0 if _kind == KIND_DEPLOY else 0.8)
	var ctrl := (_from + _to) * 0.5 + perp * lift
	return _from.lerp(ctrl, t).lerp(ctrl.lerp(_to, t), t)

func _draw() -> void:
	var t := _t()
	var head := to_local(_point_at(t))
	# 1. 彗尾：越靠后越细越淡
	for i in TRAIL_SAMPLES:
		var tt := maxf(0.0, t - float(i) * 0.024)
		var p := to_local(_point_at(tt))
		var k := 1.0 - float(i) / float(TRAIL_SAMPLES)
		draw_circle(p, 5.2 * k, GameStyle.with_alpha(_color, 0.26 * k))
	# 2. 器核：白色内核 + 反向双弧环（机械感，不是单纯光球）
	draw_circle(head, 3.0, Color(1.0, 1.0, 1.0, 0.95))
	draw_circle(head, 6.2, GameStyle.with_alpha(_color, 0.30))
	var spin := _elapsed * 9.0
	draw_arc(head, 7.0, spin, spin + PI * 1.2, 14,
		GameStyle.with_alpha(_color, 0.9), 1.7, true)
	draw_arc(head, 7.0, spin + PI, spin + PI * 2.2, 14,
		GameStyle.with_alpha(_color, 0.9), 1.7, true)
	# 3. 航向小三角：一眼看出往哪飞
	var prev := to_local(_point_at(maxf(0.0, t - 0.03)))
	var motion := head - prev
	if motion.length_squared() > 0.01:
		var d := motion.normalized()
		var tan := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([
			head + d * 8.0,
			head - d * 2.0 + tan * 3.2,
			head - d * 2.0 - tan * 3.2]), GameStyle.with_alpha(_color, 0.55))
	# 4. 收回末段：人物身上的吸口微微亮起，器核有个明确的去处
	if _kind == KIND_RECALL and t > 0.72:
		var k := (t - 0.72) / 0.28
		var r := lerpf(16.0, 7.0, k)
		draw_arc(to_local(_to), r, 0.0, TAU, 20,
			GameStyle.with_alpha(_color, 0.5 * (1.0 - k) + 0.15), 1.6, true)
