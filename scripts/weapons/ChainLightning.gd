class_name ChainLightning
extends RefCounted

## 链电运行时（2026-10-25 超级悟道「三道」重构新增）。
##
## 供四路雷电共用：紫电（每 N 次攻击）、雷霆弹幕（弹丸命中）、雷劫（击杀）、天罚（暴击）、
## 反震电场（受击）。数值口径全在 BalanceChain，这里只管「找谁、打多少、怎么画」。
##
## 2026-10-27 电刀化（对标英雄联盟电刀）：旧写法每段都画「cursor → 敌人」的全长穿越线，
## 雷劫/反震/血海还从尸体/玩家坐标起跳，再叠 LightningBolt 的分支与空气余韵 ——
## 玩家看到的是一屏没有归属的乱线。现在：首跳只在触发敌身上炸缠身电（不画入站线），
## 后续只画敌人↔敌人传导弧（两端恒为敌人，专线禁分支/余韵），落点再炸缠身电。
## 连线端点一律在画线当刻读敌人实时坐标，延时拍里敌人移动也不会把线留在空气里。
## 命中跳字走 take_damage 的 chain_tint 通道（独立条 + 身份色），不并进武器主跳字。
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

## 从 from_pos 发起一次链电：首跳永远落在「触发的敌人」身上，之后逐跳找最近未打过的敌人。
## 电刀模式（2026-10-27 重做，对标 LOL 电刀）：
##   - first_target 有效 = 触发的敌人（紫电/雷霆弹幕/兽群）。首跳**不画入站线**，
##     只在它身体轮廓内炸一簇缠身电；玩家/武器/尸体绝不在空气里甩线。
##   - first_target 为 null（雷劫/反震/血海）：由 from_pos 就近锁定第一只敌人当首跳，
##     from_pos 不参与画线；半径内锁不到敌人时直接返回 0（宁可不画，也不画空气）。
##   - 后续每跳只画「敌人↔敌人」中心的传导弧（allow_branch=false：不甩中段分支/空气余韵），
##     弧落到的敌人身上再炸一簇缠身电。
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
	# 演出闸只掐画面与音效，伤害照常（命中读数由跳字承担）
	var draw_bolt: bool = _try_consume_event_gate(gate)
	var bolt_tint: Color = tint if tint.a > 0.0 else GameStyle.FX_HDR_LIGHTNING
	if not sfx.is_empty() and draw_bolt:
		AudioManager.play_sfx(sfx, 0.55)
	# 首跳：只缠身，不画线（电刀触发瞬间「电在这只怪身上炸」）
	_apply_hop_hit(host, targets[0], damage, 0, bolt_tint, draw_bolt)
	# 后续逐跳：一条敌人↔敌人传导弧 + 落点缠身电。位置在画线那一刻才读敌人实时坐标 ——
	# 延时拍里敌人被击退/移动，弧也不会留在空气里（旧写法用的是选目标时的快照坐标）。
	for i in range(1, targets.size()):
		var prev: Node2D = targets[i - 1]
		var enemy: Node2D = targets[i]
		var prev_snap: Vector2 = prev.global_position
		var to_snap: Vector2 = enemy.global_position
		var hop_idx: int = i
		var tree := host.get_tree()
		if tree == null:
			_draw_chain_segment(host, prev, prev_snap, enemy, to_snap, bolt_tint, draw_bolt)
			_apply_hop_hit(host, enemy, damage, hop_idx, bolt_tint, draw_bolt)
			continue
		var delay: float = HOP_VISUAL_DELAY * float(hop_idx)
		tree.create_timer(delay).timeout.connect(func() -> void:
			if host == null or not is_instance_valid(host):
				return
			_draw_chain_segment(host, prev, prev_snap, enemy, to_snap, bolt_tint, draw_bolt)
			_apply_hop_hit(host, enemy, damage, hop_idx, bolt_tint, draw_bolt))
	return targets.size()

## 单段传导弧：两端优先读敌人实时坐标（对象已失效才退回选目标时的快照），
## 两端都在敌人身上才画 —— 这是「空气里不许有电」的最后一道闸。
static func _draw_chain_segment(host: Node, prev: Node2D, prev_snap: Vector2,
		enemy: Node2D, to_snap: Vector2, tint: Color, draw_bolt: bool) -> void:
	if not draw_bolt:
		return
	var from_pos: Vector2 = prev.global_position if prev != null and is_instance_valid(prev) else prev_snap
	var to_pos: Vector2 = enemy.global_position if enemy != null and is_instance_valid(enemy) else to_snap
	if from_pos.distance_to(to_pos) <= MIN_BOLT_LEN:
		return
	_draw_bolt(host, from_pos, to_pos, tint, BOLT_WIDTH, false)

## 一次链跳的落地结算：伤害（带链电身份色跳字）+ 缠身电 + 落点爆闪。
## 命中点读敌人实时坐标；目标已死则整跳跳过（伤害与画面一起跳过，不往空气里画）。
static func _apply_hop_hit(host: Node, enemy: Node2D, base_damage: float, hop_idx: int,
		tint: Color, draw_bolt: bool) -> void:
	if enemy == null or not is_instance_valid(enemy) or bool(enemy.get("dying")):
		return
	if _depth >= BalanceChain.MAX_DEPTH:
		return
	var pos: Vector2 = enemy.global_position
	_depth += 1
	var dmg := BalanceChain.chain_hop_damage(base_damage, hop_idx)
	if enemy.has_method("take_damage"):
		# chain_tint 让这一跳走「独立跳字 + 身份色」通道（不并进武器主跳字），
		# 玩家才读得出紫电/雷劫各自打了多少（旧写法被 0.25s 同目标聚合窗吞成 ×N）。
		enemy.take_damage(dmg, Vector2.ZERO, false, false, tint)
	_depth = maxi(0, _depth - 1)
	if draw_bolt and host != null and is_instance_valid(host):
		JuiceEffect.spawn_body_arcs(host, pos, tint)
		JuiceEffect.spawn_bolt_pop(host, pos, tint)

## 单点落雷（天罚用）：自苍穹垂直贯穿劈下，目标明确、去繁就简、干净霸道。
## target_input 可为被暴击的敌人 Node2D 或坐标 Vector2。若提供实体，天雷锁死目标天灵盖，伤害必中。
## 2026-10-27 电刀化收尾：雷柱只留一条干净主干（allow_branch=false —— 不甩中段分支、
## 不出空气余韵微弧），落点补一簇缠身电，让「电落在敌人身上」这一下读得实。
## tint 同时透传给 take_damage：这份天罚伤害走独立跳字（combo_key=-1），
## 不再被并进武器暴击主跳字（旧写法读出来只有「64!」，看不出天罚还打了 100）。
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

	var bolt_tint: Color = tint if tint.a > 0.0 else GameStyle.FX_HDR_LIGHTNING
	# 伤害必定精准落地：优先结算绑定的暴击目标，没有实体才就近认领
	if target_node != null and is_instance_valid(target_node) and not bool(target_node.get("dying")):
		if _is_chain_target(target_node):
			# 标暴击=true：暴击闪白+垂直微击退顿挫+暴击跳字；tint 让这条天罚伤害独立成条
			target_node.take_damage(damage, Vector2.DOWN * 8.0, true, false, bolt_tint)
		elif target_node.has_method("take_damage"):
			# 宝箱/灵草是 3 参 take_damage（交互物不进链电 tint 通道）
			target_node.take_damage(damage, Vector2.DOWN * 8.0, true)
	else:
		_apply_sky_bolt_damage(target_pos, damage, bolt_tint)

	# 天顶纯粹雷柱（垂直直落 280px，粗度 2.0，雷霆贯顶）：单线贯顶，禁分支/余韵
	var sky := target_pos + Vector2(0.0, -280.0)
	_draw_bolt(host, sky, target_pos, bolt_tint, 2.0, false)
	# 落点：缠身电（电在敌人身上）+ 电离爆散
	JuiceEffect.spawn_body_arcs(host, target_pos, bolt_tint)
	JuiceEffect.spawn_bolt_pop(host, target_pos, bolt_tint)
	AudioManager.play_sfx("thunder_strike", 0.75)

## 天罚落点冲击环半径（px）。纯表现，不参与判定 —— 天罚是单点伤害，
## 环只是把「砸下来了」这件事画得有分量，别误读成 AOE 范围。
const SKY_BOLT_RING_RADIUS := 64.0
## 天罚落点认领半径：落点附近这个距离内最近的那只敌人吃伤害。
## 取 28px 是敌人碰撞体量级 —— 暴击命中的目标必然在落点中心，够不着说明它刚被打死/击飞。
const SKY_BOLT_HIT_RADIUS := 28.0

## 天罚伤害落地：按位置就近认领（不靠对象引用，避免 host 侧硬类型依赖）。
## tint 透传给 take_damage 的 chain_tint 尾巴，让这份伤害独立显示（见 sky_bolt）。
static func _apply_sky_bolt_damage(target_pos: Vector2, damage: float, tint: Color) -> void:
	var best: Node2D = null
	var best_d: float = SKY_BOLT_HIT_RADIUS
	var live: Array = GameManager.live_enemies
	for node in live:
		var e := node as Node2D
		if e == null or not _is_chain_target(e):
			continue
		var d: float = target_pos.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		best.take_damage(damage, Vector2.ZERO, true, false, tint)

## 挑一条链：首个目标（或从 origin 找最近的），之后每次找「离当前最近且没打过」的。
## 与 SpiritPet 连锁神雷同一条口径（60% 折损 / 最多 3 个），但这里允许玩家侧配置跳数。
## 首个目标也走 _is_chain_target 校验：宝箱/灵草即便被武器顺手砍到，也不当链电起跳点。
static func _pick_chain(first_target: Node2D, origin: Vector2, hops: int,
		radius: float = 0.0) -> Array:
	var out: Array = []
	var used: Dictionary = {}
	var cursor_pos: Vector2 = origin
	var next_target: Node2D = first_target
	if _is_chain_target(next_target):
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

## 链电可锁定的目标：存活、可受伤、且不是宝箱/灵草这类交互物。
## 交互物的 take_damage 是 3 参签名（只数命中次数），链电的 5 参调用会直接报错；
## 而且箱子/草本来就不该吃链电 —— 2026-10-27 电刀化时一并挡在选目标这层。
static func _is_chain_target(e: Node) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if bool(e.get("dying")):
		return false
	if e.is_in_group("chests") or e.is_in_group("herbs"):
		return false
	return e.has_method("take_damage")

static func _nearest_unhit(origin: Vector2, used: Dictionary, radius: float = 0.0) -> Node2D:
	var live: Array = GameManager.live_enemies
	var best: Node2D = null
	var best_d: float = radius if radius > 0.0 else BalanceChain.CHAIN_RADIUS
	for node in live:
		var e := node as Node2D
		if not _is_chain_target(e):
			continue
		if used.has(e.get_instance_id()):
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
		width: float = BOLT_WIDTH, allow_branch: bool = true) -> void:
	var bolt := LightningBolt.acquire(host)
	if bolt == null:
		return
	bolt.activate(from_pos, to_pos, tint, width, Color(0, 0, 0, 0), allow_branch)

## 供测试/重置用：清空限流与递归状态
static func reset_gate() -> void:
	_last_event_ms = -999999
	_last_gate_ms.clear()
	_depth = 0
