extends Node2D

## 磐石猿飞石：掷向远处的巨石弹体，走一段抛物弧后落点震击（范围伤害+击退+减速）并碎裂消散
## 纯代码绘制、无碰撞体：落点判定沿用灵兽行为口径（遍历 live_enemies 距离判定，鸭类型访问不硬引 EnemyBase）
## 由 SpiritPet 按路径 preload 创建，飞完即自毁，不入对象池（3.5s 一发，量级可忽略）

const BURST_SEC: float = 0.28          ## 落点碎裂演出时长（秒）
const ARC_H_MIN: float = 24.0          ## 抛物弧高下限（px）
const ARC_H_MAX: float = 90.0          ## 抛物弧高上限（px）
const ARC_H_DIST_RATIO: float = 0.35   ## 弧高随飞行距离的比例

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _dur: float = 1.0
var _arc_h: float = 40.0
var _spin: float = 0.0
var _verts := PackedVector2Array()     ## 石体不规则轮廓（出厂时以 instance_id 播种本地 RNG 生成）
var _bursting: bool = false
var _burst_t: float = 0.0

var flight_damage: float = 0.0         ## 落点震击单发伤害（已含乘区与波次成长）
var aoe_radius: float = 160.0          ## 落点震击半径（px）

func setup(from_pos: Vector2, to_pos: Vector2, dmg: float, radius: float) -> void:
	_from = from_pos
	position = from_pos
	_to = to_pos
	flight_damage = dmg
	aoe_radius = radius
	var dist := from_pos.distance_to(to_pos)
	_dur = maxf(0.12, dist / BalanceSpiritPet.BOULDER_SPEED)
	_arc_h = clampf(dist * ARC_H_DIST_RATIO, ARC_H_MIN, ARC_H_MAX)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var n := 8
	_verts.resize(n)
	for i in range(n):
		var ang := TAU * float(i) / float(n)
		var r := 9.0 + rng.randf() * 3.5
		_verts[i] = Vector2(cos(ang), sin(ang)) * r

func _physics_process(delta: float) -> void:
	if _bursting:
		_burst_t += delta
		queue_redraw()
		if _burst_t >= BURST_SEC:
			queue_free()
		return
	_t += delta / _dur
	if _t >= 1.0:
		_land()
		return
	_spin += delta * 9.0
	rotation = _spin
	global_position = _from.lerp(_to, _t) + Vector2(0.0, -_arc_h * 4.0 * _t * (1.0 - _t))
	queue_redraw()

## 石落轰击：以落点为心做一次范围结算，随后进入碎裂演出
func _land() -> void:
	_bursting = true
	_burst_t = 0.0
	rotation = 0.0
	global_position = _to
	var radius_sq := aoe_radius * aoe_radius
	var scene_parent := get_parent()
	for e in GameManager.live_enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.get(&"dying") == true:
			continue
		var n2d := e as Node2D
		var diff := n2d.global_position - _to
		if diff.length_squared() > radius_sq:
			continue
		var kb_dir := diff.normalized() if diff.length_squared() > 1.0 else Vector2.RIGHT
		if e.has_method("take_damage"):
			e.take_damage(flight_damage * GameManager.elite_damage_mult_for(e), kb_dir * BalanceSpiritPet.SMASH_KNOCKBACK, false)
		if e.has_method("apply_chill"):
			e.apply_chill(BalanceSpiritPet.SMASH_SLOW_PCT, BalanceSpiritPet.SMASH_SLOW_DURATION)
	if is_inside_tree() and scene_parent != null:
		JuiceEffect.spawn_shockwave(scene_parent, _to, aoe_radius * 0.38, Color(0.72, 0.62, 0.45, 0.65), 0.20)
		JuiceEffect.spawn_impact_pop(scene_parent, _to, Color(0.65, 0.58, 0.52), Vector2.UP)
	AudioManager.play_sfx("impact_crack", 0.5, 0.95)
	queue_redraw()

func _draw() -> void:
	if _bursting:
		var prog: float = clampf(_burst_t / BURST_SEC, 0.0, 1.0)
		var alpha: float = (1.0 - prog) * 0.85
		var out_r: float = aoe_radius * 0.38 * (0.5 + 0.5 * prog)
		# 地面放射状裂纹
		for k in range(8):
			var a: float = TAU * float(k) / 8.0 + 0.4
			var p_in := Vector2(cos(a), sin(a)) * (out_r * 0.2)
			var p_out := Vector2(cos(a), sin(a)) * out_r
			draw_line(p_in, p_out, Color(0.42, 0.34, 0.26, alpha), 2.2)
		# 碎石崩点
		for k in range(6):
			var ang: float = TAU * float(k) / 6.0 + 1.1
			var d: float = out_r * (0.7 + 0.3 * sin(float(k) * 2.3))
			draw_circle(Vector2(cos(ang), sin(ang)) * d, maxf(0.8, 3.5 * (1.0 - prog)), Color(0.55, 0.46, 0.36, alpha))
		return
	# 飞行中的石体：深岩底 + 亮面 + 高光点
	draw_colored_polygon(_verts, Color(0.44, 0.38, 0.33))
	var shard := PackedVector2Array()
	for v in _verts:
		shard.append(v * 0.52 + Vector2(-1.5, -2.0))
	draw_colored_polygon(shard, Color(0.68, 0.60, 0.50, 0.9))
	draw_circle(Vector2(-2.5, -3.5), 1.6, Color(1.0, 0.95, 0.85, 0.7))
