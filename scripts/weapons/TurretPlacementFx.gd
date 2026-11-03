extends Node2D

## 机关布设 / 收回的地面法阵演出（2026-11-03）。
##
## 用户口径：布设与收回不能只是「忽然出现 / 忽然消失」，要有对应的过程动画。
## 分工：TurretDeployPreview 是布设前常驻读判定；本节点是一次性的落位/撤场演出：
##   布设 → 法阵从落点向外铺开、三重环错拍扩散、阵纹旋转、中心落点亮一下；
##   收回 → 法阵从外缘向机关脚下收拢、三重环反向收缩、阵纹反向旋转、中心光核收束。
##
## 纪律：纯表现层，不参与判定；宿主 TurretUnit 在 begin_life / dismiss(true) 时挂出，
## 播完自毁。不占对象池 —— 机关布设/收回是低频操作，同屏最多几朵。

const KIND_DEPLOY := 0
const KIND_RECALL := 1

## 演出时长：布设略长（法阵铺开），收回略短（撤场干脆）
const DEPLOY_SEC := 0.36
const RECALL_SEC := 0.30
## 法阵半径：内圈贴着机关阵盘（外缘 18），向外铺到 42，与落点预览的射程环区分开
const RING_BASE := 24.0
const RING_OUTER := 42.0
## 阵纹刻度数
const TICK_COUNT := 8

var _kind: int = KIND_DEPLOY
var _color: Color = GameStyle.GOLD_EDGE
var _elapsed: float = 0.0
var _duration: float = DEPLOY_SEC
var _mid_done: bool = false

## 宿主在 add_child 后调用：选布设/收回，颜色按机关元素取（法阵与机关本体同源）
func play(kind: int, elem: String) -> void:
	_kind = kind
	_color = GameStyle.ELEMENT_COLORS.get(elem, GameStyle.GOLD_EDGE)
	_duration = DEPLOY_SEC if kind == KIND_DEPLOY else RECALL_SEC
	_elapsed = 0.0
	_mid_done = false
	# 贴地：画在机关本体下面，别让法阵圈盖住机关与人物
	z_index = -1
	queue_redraw()
	# 起手碎屑：布设溅金属屑 / 收回先吸出一圈灵光点。
	# bypass_budget：低频动作，不挤占受击火花预算。
	var ldr := GameStyle.with_alpha(_color, 0.9)
	if kind == KIND_DEPLOY:
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position + Vector2(0, -2),
			ldr, 0.65, true)
	else:
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, global_position + Vector2(0, -6),
			ldr, 0.55, true)

func kind() -> int:
	return _kind

func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if not _mid_done and t >= 0.55:
		_mid_done = true
		# 中段的二次碎屑：让法阵最亮的一拍与机关本体的缩放/上浮对拍
		FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position + Vector2(0, 2),
			GameStyle.with_alpha(_color, 0.8), 0.45, true)
	queue_redraw()
	if _elapsed >= _duration:
		queue_free()

func _draw() -> void:
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if _kind == KIND_DEPLOY:
		_draw_deploy(t)
	else:
		_draw_recall(t)

## 布设：由内向外铺开。三重环错拍外扩，阵纹随之外旋，中心落点闪一下。
func _draw_deploy(t: float) -> void:
	var out := 1.0 - pow(1.0 - t, 3.0)
	# 1. 地面法阵底光：从落点铺开，亮度随收束衰减
	draw_circle(Vector2.ZERO, lerpf(6.0, RING_OUTER, out),
		GameStyle.with_alpha(_color, 0.14 * (1.0 - t)))
	# 2. 三重同心环：错拍外扩，最外环淡而细
	for i in 3:
		var lt := clampf((t - float(i) * 0.10) / 0.72, 0.0, 1.0)
		if lt <= 0.0:
			continue
		var e := 1.0 - pow(1.0 - lt, 3.0)
		var r := lerpf(RING_BASE * 0.35, RING_OUTER + float(i) * 7.0, e)
		var a := (1.0 - lt) * (0.95 - float(i) * 0.22)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48,
			GameStyle.with_alpha(_color, a), 2.4 - float(i) * 0.5, true)
	# 3. 阵纹刻度：随外扩旋转半圈，收尾淡出
	var spin := t * 0.7
	for k in TICK_COUNT:
		var ang := TAU * float(k) / float(TICK_COUNT) + spin
		var dir := Vector2(cos(ang), sin(ang))
		var r0 := lerpf(RING_BASE, RING_OUTER, out)
		draw_line(dir * r0, dir * (r0 + 6.0),
			GameStyle.with_alpha(_color, 0.75 * (1.0 - t)), 1.4)
	# 4. 中心落点闪：落地一瞬最亮，随后被机关本体盖住
	draw_circle(Vector2.ZERO, lerpf(7.0, 1.0, out),
		GameStyle.with_alpha(Color.WHITE, 0.85 * (1.0 - t)))

## 收回：由外向内收拢。三重环反向收缩，阵纹内旋，中心光核收成一点。
func _draw_recall(t: float) -> void:
	var inn := t * t
	# 1. 反向收拢底光：法阵从外缘吸向机关脚下
	draw_circle(Vector2.ZERO, lerpf(RING_OUTER, 2.0, inn),
		GameStyle.with_alpha(_color, 0.16 * (1.0 - t)))
	# 2. 三重同心环：由外向内收，错拍收束
	for i in 3:
		var lt := clampf((t - float(i) * 0.08) / 0.78, 0.0, 1.0)
		if lt <= 0.0:
			continue
		var e := lt * lt
		var r := lerpf(RING_OUTER + float(i) * 8.0, 5.0 + float(i) * 2.0, e)
		var a := (0.95 - float(i) * 0.20) * (1.0 - lt * 0.55)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48,
			GameStyle.with_alpha(_color, a), 2.2 - float(i) * 0.45, true)
	# 3. 阵纹刻度反向旋转，指向机关中心
	var spin := -t * 0.9
	for k in TICK_COUNT:
		var ang := TAU * float(k) / float(TICK_COUNT) + spin
		var dir := Vector2(cos(ang), sin(ang))
		var r0 := lerpf(RING_OUTER, 4.0, inn)
		draw_line(dir * r0, dir * (r0 + 5.0),
			GameStyle.with_alpha(_color, 0.8 * (1.0 - t)), 1.4)
	# 4. 中心光核：收束到最后缩成一点白
	draw_circle(Vector2.ZERO, lerpf(1.0, 7.0, t) * (1.0 - t * 0.6),
		GameStyle.with_alpha(Color.WHITE, 0.75 * t))
