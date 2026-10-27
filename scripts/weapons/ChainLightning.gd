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
## 2026-10-26：由「一条全局 90ms 闸」拆成「按路径独立闸」。
## 旧写法七路雷电（紫电/雷劫/天罚/反震/盾碎/雷霆弹幕/兽群）抢同一条闸，一场团战里
## 只有第一条能画出来，其余全被吞成「没触发」——玩家读不到是哪张卡在动。
## 现在每路各持一条 BalanceChain.EVENT_GAP_MS 的闸：同一帧里紫电 + 雷劫 + 天罚
## 同时触发时三条都会画出来（各自的闸只压自己这一路的重复触发）。
## 总量兜底交给 LightningBolt 池容量（24）与 MAX_DEPTH 递归闸，不再设跨路径的全局闸
## —— 全局闸正是「明明拿了卡却看不见」的根因。
static var _last_event_ms: int = -999999
static var _last_gate_ms: Dictionary = {}
static var _depth: int = 0

## 短于此长度的电弧不画（弹丸贴脸命中时起点与目标重合，零长度折线只是噪点）
const MIN_BOLT_LEN := 18.0
## 逐跳演出的间隔（秒）：电一跳一跳传导的节拍。只延迟画图，伤害在 strike 当帧即时结算
const HOP_VISUAL_DELAY := 0.045
## 链电弧线宽倍率（LightningBolt 基准 ×1.15：0.85 的旧口径在混战里细得看不见）
const BOLT_WIDTH := 1.15

## 从 from_pos 向首个目标打一条链电，然后逐跳找最近未打过的敌人。
## first_target：触发链电的首个目标（电刀模式下为触发攻击命中的敌人）。
## 若 first_target 非空且 from_pos 在其身侧，首跳在此敌人身上爆发，电弧只在此敌人与周围敌人之间弹射连线。
## damage 是首跳伤害（后续跳按 BalanceChain.HOP_RATIO 折损）。
## max_hops 传 0 用 BalanceChain.MAX_HOPS。
## gate：演出闸的路径键（每路雷电各持一条，见文件头）；sfx 传空串用默认雷击音。
## radius：起跳搜索半径（传 0 用 BalanceChain.CHAIN_RADIUS；反震电场走 THORNS_RADIUS）。
## 返回实际命中的目标数。
static func strike(host: Node, from_pos: Vector2, first_target: Node2D, damage: float,
		max_hops: int = 0, tint: Color = Color(0, 0, 0, 0), gate: StringName = &"strike",
		sfx: String = "thunder_strike", radius: float = 0.0) -> int:
	if host == null or not is_instance_valid(host):
		return 0
	if damage <= 0.0:
		return 0
	# 递归闸：链电打死的人会再触发雷劫，深度超限直接掐断
	if _depth >= BalanceChain.MAX_DEPTH:
		return 0
	var hops: int = max_hops if max_hops > 0 else BalanceChain.MAX_HOPS
	var search_r: float = radius if radius > 0.0 else BalanceChain.CHAIN_RADIUS
	var targets := _pick_chain(first_target, from_pos, hops, search_r)
	if targets.is_empty():
		return 0
	var draw_bolt: bool = _try_consume_event_gate(gate)
	var bolt_tint: Color = tint if tint.a > 0.0 else GameStyle.FX_HDR_LIGHTNING
	var cursor: Vector2 = from_pos
	# 演出折点：记下每一跳的起讫段与目标
	var segments: Array = []
	var hop_targets: Array = []
	_depth += 1
	var hit_n := 0

	for i in targets.size():
		var enemy: Node2D = targets[i]
		if enemy == null or not is_instance_valid(enemy):
			continue
		if bool(enemy.get("dying")):
			continue
		hit_n += 1
		# 电弧段：从上一节点连向当前目标
		# 若首跳即为触发怪且 cursor 与其重合，则不产生向自身的零长连线，直接作为起点
		if cursor.distance_to(enemy.global_position) > MIN_BOLT_LEN:
			segments.append([cursor, enemy.global_position, enemy, i])
		else:
			# 首跳自身受击
			hop_targets.append([enemy, i, enemy.global_position])
		cursor = enemy.global_position

	_depth = maxi(0, _depth - 1)

	if not sfx.is_empty() and draw_bolt:
		AudioManager.play_sfx(sfx, 0.55)

	# 2026-10-26 LOL 电刀式同步结算：伤害与电弧逐跳精准同步，电窜到哪怪就抖到哪
	_play_chain_hops(host, segments, hop_targets, damage, bolt_tint, draw_bolt)
	return hit_n

## 逐跳同步结算与演出：首跳即刻击中，后续跳随电弧传导逐段爆发
static func _play_chain_hops(host: Node, segments: Array, direct_targets: Array,
		base_damage: float, tint: Color, draw_bolt: bool) -> void:
	# 1. 直接命中的首跳（自身起跳点）
	for dt in direct_targets:
		var enemy: Node2D = dt[0]
		var idx: int = dt[1]
		var pos: Vector2 = dt[2]
		_apply_hop_hit(host, enemy, base_damage, idx, pos, tint, draw_bolt)

	# 2. 逐段电弧弹射目标
	for k in segments.size():
		var seg: Array = segments[k]
		var from_p: Vector2 = seg[0]
		var to_p: Vector2 = seg[1]
		var enemy: Node2D = seg[2]
		var hop_idx: int = seg[3]

		if k == 0 and direct_targets.is_empty():
			# 无 direct 首跳时，第一段即刻结算
			if draw_bolt:
				_draw_bolt(host, from_p, to_p, tint)
			_apply_hop_hit(host, enemy, base_damage, hop_idx, to_p, tint, draw_bolt)
			continue

		var delay: float = HOP_VISUAL_DELAY * float(k if direct_targets.is_empty() else k + 1)
		var tree := host.get_tree()
		if tree == null:
			if draw_bolt:
				_draw_bolt(host, from_p, to_p, tint)
			_apply_hop_hit(host, enemy, base_damage, hop_idx, to_p, tint, draw_bolt)
			continue

		tree.create_timer(delay).timeout.connect(func() -> void:
			if host == null or not is_instance_valid(host):
				return
			if draw_bolt:
				_draw_bolt(host, from_p, to_p, tint)
			_apply_hop_hit(host, enemy, base_damage, hop_idx, to_p, tint, draw_bolt))

static func _apply_hop_hit(host: Node, enemy: Node2D, base_damage: float, hop_idx: int,
		pos: Vector2, tint: Color, draw_bolt: bool) -> void:
	if enemy != null and is_instance_valid(enemy) and not bool(enemy.get("dying")):
		var dmg := BalanceChain.chain_hop_damage(base_damage, hop_idx)
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg, Vector2.ZERO, false)
	if draw_bolt and host != null and is_instance_valid(host):
		JuiceEffect.spawn_bolt_pop(host, pos, tint)

## 单点落雷（天罚用）：自苍穹垂直贯穿劈下，目标明确、去繁就简、干净霸道。
## target_input 可为被暴击的敌人 Node2D 或坐标 Vector2。若提供实体，天雷锁死目标天灵盖，伤害必中。
static func sky_bolt(host: Node, target_input: Variant, damage: float,
		tint: Color = Color(0, 0, 0, 0), gate: StringName = &"tianfa",
		target_enemy: Node2D = null) -> void:
	if host == null or not is_instance_valid(host) or damage <= 0.0:
		return
	if not _try_consume_event_gate(gate):
		return

	var target_pos: Vector2
	var target_node: Node2D = null
	if target_input is Node2D:
		target_node = target_input as Node2D
		target_pos = target_node.global_position
	elif target_input is Vector2:
		target_pos = target_input
		target_node = target_enemy
	else:
		return

	# 伤害必定精准落地：优先结算绑定的暴击目标，没有实体才就近认领
	if target_node != null and is_instance_valid(target_node) and not bool(target_node.get("dying")):
		if target_node.has_method("take_damage"):
			# 标暴击=true：暴击闪白+垂直微击退顿挫+暴击跳字
			target_node.take_damage(damage, Vector2.DOWN * 8.0, true)
	else:
		_apply_sky_bolt_damage(target_pos, damage)

	var bolt_tint: Color = tint if tint.a > 0.0 else GameStyle.FX_HDR_LIGHTNING
	# 天顶纯粹雷柱（垂直直落 280px，粗度 2.0，雷霆贯顶）
	var sky := target_pos + Vector2(0.0, -280.0)
	_draw_bolt(host, sky, target_pos, bolt_tint, 2.0)
	# 命中点电离爆散
	JuiceEffect.spawn_bolt_pop(host, target_pos, bolt_tint)
	AudioManager.play_sfx("thunder_strike", 0.75)

## 天罚落点冲击环半径（px）。纯表现，不参与判定 —— 天罚是单点伤害，
## 环只是把「砸下来了」这件事画得有分量，别误读成 AOE 范围。
const SKY_BOLT_RING_RADIUS := 64.0
## 天罚落点认领半径：落点附近这个距离内最近的那只敌人吃伤害。
## 取 28px 是敌人碰撞体量级 —— 暴击命中的目标必然在落点中心，够不着说明它刚被打死/击飞。
const SKY_BOLT_HIT_RADIUS := 28.0

## 天罚伤害落地：按位置就近认领（不靠对象引用，避免 host 侧硬类型依赖）。
static func _apply_sky_bolt_damage(target_pos: Vector2, damage: float) -> void:
	var best: Node2D = null
	var best_d: float = SKY_BOLT_HIT_RADIUS
	var live: Array = GameManager.live_enemies
	for node in live:
		var e := node as Node2D
		if e == null or not is_instance_valid(e):
			continue
		if bool(e.get("dying")) or not e.has_method("take_damage"):
			continue
		var d: float = target_pos.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		best.take_damage(damage, Vector2.ZERO, true)

## 挑一条链：首个目标（或从 origin 找最近的），之后每次找「离当前最近且没打过」的。
## 与 SpiritPet 连锁神雷同一条口径（60% 折损 / 最多 3 个），但这里允许玩家侧配置跳数。
static func _pick_chain(first_target: Node2D, origin: Vector2, hops: int,
		radius: float = 0.0) -> Array:
	var out: Array = []
	var used: Dictionary = {}
	var cursor_pos: Vector2 = origin
	var next_target: Node2D = first_target
	if next_target != null and is_instance_valid(next_target) and not bool(next_target.get("dying")):
		out.append(next_target)
		used[next_target.get_instance_id()] = true
		cursor_pos = next_target.global_position
	while out.size() < hops:
		var found: Node2D = _nearest_unhit(cursor_pos, used, radius)
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

static func _nearest_unhit(origin: Vector2, used: Dictionary, radius: float = 0.0) -> Node2D:
	var live: Array = GameManager.live_enemies
	var best: Node2D = null
	var best_d: float = radius if radius > 0.0 else BalanceChain.CHAIN_RADIUS
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

## 事件闸：返回 true 表示这次允许画电弧 + 播音效（伤害不受影响）。
## gate 为路径键（&"zidian" / &"leijie" / &"tianfa" / &"fanzhen" / &"xuehai" / &"danmu" / &"shouqun"…）：
## 每路各持一条 BalanceChain.EVENT_GAP_MS 的闸，互不挤占。
static func _try_consume_event_gate(gate: StringName = &"strike") -> bool:
	var now := Time.get_ticks_msec()
	var last: int = int(_last_gate_ms.get(gate, -999999))
	if now - last < BalanceChain.EVENT_GAP_MS:
		return false
	_last_gate_ms[gate] = now
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
	_last_gate_ms.clear()
	_depth = 0
