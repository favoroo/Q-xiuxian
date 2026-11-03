extends Node2D

## 机关维修的持续演出（2026-11-03 二次打磨）。
##
## 用户口径：维修过程太短、一闪就没了，而且「没有动画」。本节点负责维修期间一直存在的画面：
##   人物 → 机关一道带流动光点的灵气索（证明「人在这儿修」）；
##   机关端一圈旋转维护环 + 反向短齿（证明「机关在被修」）；
## 耐久回填本身仍在 TurretUnit._process，这里纯表现层，不参与任何判定。
##
## 生命周期：TurretUnit.begin_repair 挂出，end_repair / 修满 / 波末 / 收回时收束。
## 宿主失效或自己发现机关已不在维修态时自动淡出，不会留在场上。

const FADE_SEC := 0.14
const LINK_SEGMENTS := 16

var _turret: Node2D = null
var _player: Node2D = null
var _color: Color = GameStyle.GOLD_EDGE
var _phase: float = 0.0
var _stopping: bool = false
var _fade: float = 1.0

## 宿主在 add_child 后调用：turret/player 都是世界里的实体，允许 null（只在机关端画环）
func play(turret, player) -> void:
	_turret = turret as Node2D
	_player = player as Node2D
	# 维修是「养护」不是元素攻击：统一走主题亮边色，和 HUD 维修态、头顶「维修中」同色
	_color = GameStyle.GOLD_EDGE
	_phase = 0.0
	_stopping = false
	_fade = 1.0
	z_index = 5
	queue_redraw()

## 宿主结束维修时调用；淡出后自毁
func stop() -> void:
	_stopping = true

## 判据用：已经进入收束淡出（不代表节点已释放）
func is_stopping() -> bool:
	return _stopping

func _process(delta: float) -> void:
	if _turret == null or not is_instance_valid(_turret):
		_stopping = true
	# 宿主可能忘了调 stop（例如被外部回收）：自己发现「已不在维修」就收束
	if not _stopping and _turret != null and is_instance_valid(_turret) \
			and _turret.has_method("is_repairing") and not bool(_turret.call("is_repairing")):
		_stopping = true
	if _stopping:
		_fade -= delta / FADE_SEC
		if _fade <= 0.0:
			queue_free()
			return
	_phase += delta
	queue_redraw()

func _draw() -> void:
	if _turret == null or not is_instance_valid(_turret):
		return
	var a := clampf(_fade, 0.0, 1.0)
	var end := to_local(_turret.global_position + Vector2(0.0, -10.0))
	var has_player := _player != null and is_instance_valid(_player)
	var start := to_local(_player.global_position + Vector2(0.0, -12.0)) if has_player else end + Vector2(0.0, 42.0)
	var span := end - start
	var dist := span.length()

	# 1. 灵气索：中段轻摆，粗底 + 细亮线两层
	if dist > 4.0:
		var normal := Vector2(-span.y, span.x) / dist
		var ctrl := (start + end) * 0.5 + normal * sin(_phase * 3.2) * 9.0
		var points := PackedVector2Array()
		for i in LINK_SEGMENTS + 1:
			var u := float(i) / float(LINK_SEGMENTS)
			var pt := start.lerp(ctrl, u).lerp(ctrl.lerp(end, u), u)
			pt += normal * sin(u * PI) * sin(_phase * 9.0 + u * 7.0) * 2.4
			points.append(pt)
		draw_polyline(points, GameStyle.with_alpha(_color, 0.16 * a), 4.6, true)
		draw_polyline(points, GameStyle.with_alpha(_color, 0.82 * a), 1.5, true)
		# 2. 沿索流向机关的灵光点：三颗循环，方向从人指向机关
		for i in 3:
			var u := fposmod(_phase * 0.75 + float(i) / 3.0, 1.0)
			var pt := _curve(start, ctrl, end, u)
			pt += normal * sin(u * PI) * sin(_phase * 9.0 + u * 7.0) * 2.4
			draw_circle(pt, 5.0, GameStyle.with_alpha(_color, 0.22 * a))
			draw_circle(pt, 2.2, Color(1.0, 1.0, 1.0, 0.9 * a))

	# 3. 机关端维护环：三段旋转弧 + 反向四枚短齿，像扳手在盘缘上走
	var spin := _phase * 2.8
	for i in 3:
		var a0 := spin + TAU * float(i) / 3.0
		draw_arc(end, 13.0, a0, a0 + 0.85, 12,
			GameStyle.with_alpha(_color, 0.9 * a), 2.0, true)
	for k in 4:
		var ang := -spin * 1.6 + TAU * float(k) / 4.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(end + d * 17.0, end + d * 21.0,
			GameStyle.with_alpha(_color, 0.65 * a), 1.5)

	# 4. 人物端起点微光：呼吸一下，维修的「出力方」在人物这边
	if has_player:
		draw_circle(start, 4.0 + sin(_phase * 8.0) * 1.0,
			GameStyle.with_alpha(_color, 0.32 * a))

func _curve(p0: Vector2, ctrl: Vector2, p1: Vector2, t: float) -> Vector2:
	return p0.lerp(ctrl, t).lerp(ctrl.lerp(p1, t), t)
