class_name ChainLightning
extends RefCounted

## 链电运行时（2026-10-25 超级悟道「三道」重构新增）。
##
## 供四路雷电共用：紫电（每 N 次攻击）、雷霆弹幕（弹丸命中）、雷劫（击杀）、天罚（暴击）、
## 反震电场（受击）。数值口径全在 BalanceChain，这里只管「找谁、打多少、怎么画」。
##
## 严禁类型化引用 EnemyBase（项目坑 12：武器脚本硬引用敌人基类会把
## preload(BladeProjectile.tscn) 打成空 PackedScene）。全部走 has_method 鸭类型 +
## GameManager.live_enemies 登记表（EnemyFilter 同一条口径，但这里要啃 untyped 数组且
## 需要「已打过的不重复」集合，故自持一份最小过滤）。
##
## 随机：落点抖动等纯表现随机走本模块本地 RNG，不碰 GameManager.rng（铁律 3/15）。

## 上一次链电事件的毫秒时间戳 + 深度：全局限流 + 递归闸
static var _last_event_ms: int = -999999
static var _depth: int = 0

## 短于此长度的电弧不画（弹丸贴脸命中时起点与目标重合，零长度折线只是噪点）
const MIN_BOLT_LEN := 18.0
## 逐跳演出的间隔（秒）：电一跳一跳传导的节拍。只延迟画图，伤害在 strike 当帧即时结算
const HOP_VISUAL_DELAY := 0.045
## 链电弧线宽倍率（LightningBolt 基准 ×1.15：0.85 的旧口径在混战里细得看不见）
const BOLT_WIDTH := 1.15

## 从 from_pos 向首个目标打一条链电，然后逐跳找最近未打过的敌人。
## first_target 传 null 表示「从 from_pos 就地找最近敌人起跳」。
## damage 是首跳伤害（后续跳按 BalanceChain.HOP_RATIO 折损）。
## max_hops 传 0 用 BalanceChain.MAX_HOPS。
## 返回实际命中的目标数。
static func strike(host: Node, from_pos: Vector2, first_target: Node2D, damage: float,
		max_hops: int = 0, tint: Color = Color(0, 0, 0, 0)) -> int:
	if host == null or not is_instance_valid(host):
		return 0
	if damage <= 0.0:
		return 0
	# 递归闸：链电打死的人会再触发雷劫，深度超限直接掐断（这一层不打，不报错）
	if _depth >= BalanceChain.MAX_DEPTH:
		return 0
	var hops: int = max_hops if max_hops > 0 else BalanceChain.MAX_HOPS
	var targets := _pick_chain(first_target, from_pos, hops)
	if targets.is_empty():
		return 0
	# 全局限流只掐「电弧演出」，伤害照常结算 —— 群杀时不该因为演出预算少打掉敌人
	var draw_bolt: bool = _try_consume_event_gate()
	var bolt_tint: Color = tint if tint.a > 0.0 else GameStyle.FX_HDR_LIGHTNING
	var cursor: Vector2 = from_pos
	# 演出折点：伤害循环里顺手记下每一段的起讫，结算完统一按节拍画（伤害绝不延迟）
	var segments: Array = []
	var hit_points: Array = []
	_depth += 1
	var hit_n := 0
	for i in targets.size():
		var enemy: Node2D = targets[i]
		if enemy == null or not is_instance_valid(enemy):
			continue
		if bool(enemy.get("dying")):
			continue
		var dmg := BalanceChain.chain_hop_damage(damage, i)
		if enemy.has_method("take_damage"):
			# 链电不吃击退（否则会把怪推散、下一跳找不到人），也不标暴击：
			# 暴击应该由天罚单点判定，链电每一跳都暴击等于全屏秒杀
			enemy.take_damage(dmg, Vector2.ZERO, false)
			hit_n += 1
		if draw_bolt:
			# 电弧长度过短时不画（弹丸在敌人身上命中时 from_pos 与首跳位置几乎重合，
			# 会退化成零长度折线，读起来像闪了一下噪点）；落点爆闪照放（打中了就该亮）
			if cursor.distance_to(enemy.global_position) > MIN_BOLT_LEN:
				segments.append([cursor, enemy.global_position])
			hit_points.append(enemy.global_position)
		cursor = enemy.global_position
	_depth = maxi(0, _depth - 1)
	if draw_bolt:
		AudioManager.play_sfx("thunder_strike", 0.55)
		_draw_staggered(host, segments, hit_points, bolt_tint)
	return hit_n

## 逐跳节拍演出：第 1 跳立刻画，后续每跳晚 HOP_VISUAL_DELAY —— 读「电在怪群间窜」，
## 而不是「一条折线同时糊在 N 个点上」。定时器回调只画图，宿主先没了就当无事发生。
static func _draw_staggered(host: Node, segments: Array, hit_points: Array, tint: Color) -> void:
	for i in segments.size():
		var seg: Array = segments[i]
		var pop_pos: Vector2 = seg[1]
		if i == 0:
			_draw_bolt(host, seg[0], seg[1], tint)
			JuiceEffect.spawn_bolt_pop(host, pop_pos, tint)
			continue
		var delay: float = HOP_VISUAL_DELAY * float(i)
		var from_p: Vector2 = seg[0]
		var to_p: Vector2 = seg[1]
		var tree := host.get_tree()
		if tree == null:
			_draw_bolt(host, from_p, to_p, tint)
			continue
		tree.create_timer(delay).timeout.connect(func() -> void:
			if host == null or not is_instance_valid(host):
				return
			_draw_bolt(host, from_p, to_p, tint)
			JuiceEffect.spawn_bolt_pop(host, pop_pos, tint))
	# 段被长度闸掐掉的目标（贴脸跳）没有线段，爆闪仍按节拍补上
	var drawn_ends: Array = []
	for seg in segments:
		drawn_ends.append(seg[1])
	for j in hit_points.size():
		var p: Vector2 = hit_points[j]
		if p in drawn_ends:
			continue
		var delay2: float = HOP_VISUAL_DELAY * float(j)
		var tree2 := host.get_tree()
		if tree2 == null:
			JuiceEffect.spawn_bolt_pop(host, p, tint)
			continue
		tree2.create_timer(delay2).timeout.connect(func() -> void:
			if host == null or not is_instance_valid(host):
				return
			JuiceEffect.spawn_bolt_pop(host, p, tint))

## 单点落雷（天罚用）：从上方劈到目标点，伤害 + 电弧。
## 二阶段演出：主电弧加宽到 1.4，补一道 30ms 后的副电弧（双闪读「天雷」而不是「细线」），
## 落点 HDR 爆闪 + 冲击环保留。
static func sky_bolt(host: Node, target_pos: Vector2, damage: float, tint: Color = Color(0, 0, 0, 0)) -> void:
	if host == null or not is_instance_valid(host) or damage <= 0.0:
		return
	if not _try_consume_event_gate():
		return
	var bolt_tint: Color = tint if tint.a > 0.0 else GameStyle.FX_HDR_LIGHTNING
	var sky := target_pos + Vector2(0.0, -260.0)
	_draw_bolt(host, sky, target_pos, bolt_tint, 1.4)
	JuiceEffect.spawn_bolt_pop(host, target_pos, bolt_tint)
	var tree := host.get_tree()
	if tree != null:
		tree.create_timer(0.03).timeout.connect(func() -> void:
			if host == null or not is_instance_valid(host):
				return
			_draw_bolt(host, sky + Vector2(6.0, 0.0), target_pos, bolt_tint, 0.9))
	AudioManager.play_sfx("thunder_strike", 0.7)
	JuiceEffect.spawn_shockwave(host, target_pos, 48.0, bolt_tint, 0.16)

## 挑一条链：首个目标（或从 origin 找最近的），之后每次找「离当前最近且没打过」的。
## 与 SpiritPet 连锁神雷同一条口径（60% 折损 / 最多 3 个），但这里允许玩家侧配置跳数。
static func _pick_chain(first_target: Node2D, origin: Vector2, hops: int) -> Array:
	var out: Array = []
	var used: Dictionary = {}
	var cursor_pos: Vector2 = origin
	var next_target: Node2D = first_target
	if next_target != null and is_instance_valid(next_target) and not bool(next_target.get("dying")):
		out.append(next_target)
		used[next_target.get_instance_id()] = true
		cursor_pos = next_target.global_position
	while out.size() < hops:
		var found: Node2D = _nearest_unhit(cursor_pos, used)
		if found == null:
			break
		out.append(found)
		used[found.get_instance_id()] = true
		cursor_pos = found.global_position
	# 首跳目标是 null 时上面循环已经补满；首跳有目标但已被打过则不重复
	return out

## 圈定半径内可伤害的敌人（供剑气冲击波这类「一次打一片」的机制复用）。
## 与 EnemyFilter.collect 同一条口径，但返回 untyped Node2D 数组，避免武器侧类型依赖。
static func collect_in_radius(origin: Vector2, radius: float) -> Array:
	var out: Array = []
	var live: Array = GameManager.live_enemies
	var r2: float = radius * radius
	for node in live:
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if bool(e.get("dying")):
			continue
		if not e.has_method("take_damage"):
			continue
		if origin.distance_squared_to(e.global_position) > r2:
			continue
		out.append(e)
	return out

static func _nearest_unhit(origin: Vector2, used: Dictionary) -> Node2D:
	var live: Array = GameManager.live_enemies
	var best: Node2D = null
	var best_d: float = BalanceChain.CHAIN_RADIUS
	for node in live:
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if bool(e.get("dying")):
			continue
		if used.has(e.get_instance_id()):
			continue
		if not e.has_method("take_damage"):
			continue
		var d: float = origin.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

## 事件闸：返回 true 表示这次允许画电弧 + 播音效（伤害不受影响）
static func _try_consume_event_gate() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_event_ms < BalanceChain.EVENT_GAP_MS:
		return false
	_last_event_ms = now
	return true

static func _draw_bolt(host: Node, from_pos: Vector2, to_pos: Vector2, tint: Color,
		width: float = BOLT_WIDTH) -> void:
	var bolt := LightningBolt.acquire(host)
	if bolt == null:
		return
	bolt.activate(from_pos, to_pos, tint, width)

## 供测试/重置用：清空限流与递归状态
static func reset_gate() -> void:
	_last_event_ms = -999999
	_depth = 0
