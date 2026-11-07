class_name ChainLightning
extends RefCounted

## 链电运行时（2026-10-25 超级悟道「三道」重构新增）。
##
## 供四路雷电共用：紫电（每 N 次攻击）、雷霆弹幕（弹丸命中）、雷劫（击杀）、天罚（暴击）、
## 反震电场（受击）。数值口径全在 BalanceChain，这里只管「找谁、打多少、怎么画」。
##
## 2026-10-27 电刀化（对标英雄联盟电刀）：旧写法每段都画「cursor → 敌人」的全长穿越线，
## 雷劫/反震/血海还从尸体/玩家坐标起跳，再叠 LightningBolt 的分支与空气余韵 ——
## 玩家看到的是一屏没有归属的乱线。
## 2026-11-07 电刀彻底重做（用户口径「紫电在空气里飞来飞去，空气里也有闪电，很乱」）：
## 2026-11-01 那版「头顶竖劈」的雷柱，顶端悬在敌人上方 78px 的空气里、下端才碰到怪 ——
## 它本身就是「空气里的闪电」。现在一律拴在敌人身上，只剩两种图形：
##   ① 落点缠身电：短弧两端都收在这只敌人的身体半径内（绕体闪，不出体）；
##   ② 敌人↔敌人连线：弧的两端钉在两只敌人的体缘上，且逐帧跟随
##      （LightningBolt.activate_tracked）—— 敌人被击退时电弧跟着走，敌人一死立刻收线，
##      绝不留残线悬在空中。
## 端点一律在画线当刻读敌人实时坐标，延时拍里敌人移动也不会把雷留在空气里。
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

## 逐跳演出的间隔（秒）：电一跳一跳传导的节拍。只延迟画图，伤害在 strike 当帧即时结算
const HOP_VISUAL_DELAY := 0.045
## 链电弧线宽倍率（LightningBolt 基准 ×1.15：0.85 的旧口径在混战里细得看不见）
const BOLT_WIDTH := 1.15
## 敌人↔敌人连线的体缘退让：连线两端各从身位中心退到这个距离，弧从体缘起、到体缘止。
## 取 12px ≈ 小怪身体半径量级 —— 弧不穿进身体，也不会缩到看不见。
const LINK_EDGE_TRIM := 12.0

## 从 from_pos 发起一次链电：首跳永远落在「触发的敌人」身上，之后逐跳找最近未打过的敌人。
## 电刀模式（2026-11-07 最终口径，对标 LOL 电刀）：
##   - 电只在两处出现：**敌人身上**（缠身电）与**敌人↔敌人的连线上**（体缘连线弧）。
##     空气里一条线都不许有 —— 天空竖雷柱（顶端悬空）与中段随机分支/余韵整段下线。
##   - first_target 有效 = 触发的敌人（紫电/雷霆弹幕/兽群）。玩家/武器/尸体绝不在空气里甩线。
##   - first_target 为 null（雷劫/反震/血海）：由 from_pos 就近锁定第一只敌人当首跳，
##     from_pos 不参与画线；半径内锁不到敌人时直接返回 0（宁可不画，也不画空气）。
##   - 连线弧两端拴在两只敌人身上（LightningBolt.activate_tracked）：敌人移动时弧跟着走，
##     敌人一死立刻收线，不会把线留在原地。
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
	# pixelfx 接入点（回退：注释下一行）
	# 雷劫＝击杀电结：尸体位置炸一小团电结（from_pos 就是尸体坐标）。
	# 只认 leijie 这一路：紫电/弹幕/兽群的 from_pos 是命中敌身位，电团已由首跳缠身电承担；
	# 反震/血海的 from_pos 是玩家身位，更不该在玩家脚下放「击杀电结」。
	# 与传导弧同吃演出闸：一次雷劫风暴只放一团，伤害结算不受影响。
	if draw_bolt and gate == &"leijie":
		FxFlipbookPool.play(&"zap_hit", from_pos)
	# 首跳：缠身电（电刀触发瞬间「电缠在这只怪身上」），没有上一跳 → 不画连线
	_apply_hop_hit(host, targets[0], null, damage, 0, bolt_tint, draw_bolt)
	# 后续逐跳：敌人↔敌人连线弧 + 落点缠身电。连线两端拴在两具身体上（activate_tracked），
	# 延时拍里敌人被击退/移动时弧跟着走，敌人一死立刻收线 —— 绝不留线在空气里。
	for i in range(1, targets.size()):
		var enemy: Node2D = targets[i]
		var prev_enemy: Node2D = targets[i - 1]
		var hop_idx: int = i
		var tree := host.get_tree()
		if tree == null:
			_apply_hop_hit(host, enemy, prev_enemy, damage, hop_idx, bolt_tint, draw_bolt)
			continue
		var delay: float = HOP_VISUAL_DELAY * float(hop_idx)
		tree.create_timer(delay).timeout.connect(func() -> void:
			if host == null or not is_instance_valid(host):
				return
			_apply_hop_hit(host, enemy, prev_enemy, damage, hop_idx, bolt_tint, draw_bolt))
	return targets.size()

## 敌人↔敌人连线弧（2026-11-07 电刀最终口径）：两端各从身位中心退到体缘，
## 弧从体缘起、到体缘止；两端都拴在敌人节点上逐帧跟随（LightningBolt.activate_tracked）。
## 这是全项目唯一允许「离开敌人身体」的链电图形 —— 它的两端仍然钉在两只敌人身上。
## 两只怪贴得比两边体缘之和还近时不画：这时体缘已经贴在一起，弧会退成反向/零长的小毛刺。
static func _draw_hop_link(host: Node, prev_enemy: Node2D, enemy: Node2D, tint: Color) -> void:
	var trim_a: float = _body_radius_of(prev_enemy)
	var trim_b: float = _body_radius_of(enemy)
	if prev_enemy.global_position.distance_to(enemy.global_position) < trim_a + trim_b + 6.0:
		return
	var bolt := LightningBolt.acquire(host)
	if bolt == null:
		return
	bolt.activate_tracked(prev_enemy, enemy, Vector2.ZERO, Vector2.ZERO,
		trim_a, trim_b, true, tint, BOLT_WIDTH)

## 敌人的身体半径（读 CollisionShape2D 的圆半径；拿不到时退回缠身电的默认半径）。
## 走鸭类型 + get_node_or_null：严禁类型化引用 EnemyBase（项目坑 12），
## 也兼容非 EnemyBase 的可受伤实体（交互物不进链电目标表，这里只是兜底）。
static func _body_radius_of(e: Node2D) -> float:
	if e == null or not is_instance_valid(e):
		return LINK_EDGE_TRIM
	var cs := e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius
	return LINK_EDGE_TRIM

## 一次链跳的落地结算：伤害（带链电身份色跳字）+ 缠身电 + 落点爆闪；
## prev_enemy 非空时再补一道「上一只 → 这一只」的体缘连线弧。
## 命中点读敌人实时坐标；目标已死则整跳跳过（伤害与画面一起跳过，不往空气里画）。
## 画面上「传导」由逐跳延时（HOP_VISUAL_DELAY）表达：电一跳一跳打到下一只怪身上。
static func _apply_hop_hit(host: Node, enemy: Node2D, prev_enemy: Node2D, base_damage: float,
		hop_idx: int, tint: Color, draw_bolt: bool) -> void:
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
		# 连线先画（在两只身体之间），再画落点缠身电（压在体表）
		if prev_enemy != null and is_instance_valid(prev_enemy) and not bool(prev_enemy.get("dying")):
			_draw_hop_link(host, prev_enemy, enemy, tint)
		JuiceEffect.spawn_body_arcs(host, pos, tint, JuiceEffect.BODY_ARC_RADIUS,
			JuiceEffect.BODY_ARC_COUNT, enemy)
		JuiceEffect.spawn_bolt_pop(host, pos, tint)

## 单点落雷（天罚用）：伤害锁死被暴击的目标，在它身位上亮一道贴身光柱。
## target_input 可为被暴击的敌人 Node2D 或坐标 Vector2。若提供实体，伤害必中。
## 2026-11-01 去线条化：旧写法自 target 上方 280px 拉一条锯齿雷柱（顶端悬在空气里），
## 每次暴击都来一条；目标被暴击打死/击退后更是只剩「凭空一道线」。整段已下线，
## 改由 JuiceEffect.spawn_sky_strike 在身位内画光柱 + 落点环（不生成任何 LightningBolt）。
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
	# 伤害必定精准落地：优先结算绑定的暴击目标，没有实体才就近认领。
	# landed_pos = 实际吃到这份伤害的那个身位；没打到任何人时整段演出跳过 ——
	# 天罚是单点伤害，光柱必须画在真挨打的那只怪身上，不往空地/尸体上放。
	var landed_pos: Vector2 = Vector2.INF
	if target_node != null and is_instance_valid(target_node) and not bool(target_node.get("dying")):
		if _is_chain_target(target_node):
			# 标暴击=true：暴击闪白+垂直微击退顿挫+暴击跳字；tint 让这条天罚伤害独立成条
			landed_pos = target_node.global_position
			target_node.take_damage(damage, Vector2.DOWN * 8.0, true, false, bolt_tint)
		elif target_node.has_method("take_damage"):
			# 宝箱/灵草是 3 参 take_damage（交互物不进链电 tint 通道）
			landed_pos = target_node.global_position
			target_node.take_damage(damage, Vector2.DOWN * 8.0, true)
	else:
		var claimed: Node2D = _apply_sky_bolt_damage(target_pos, damage, bolt_tint)
		if claimed != null and is_instance_valid(claimed):
			landed_pos = claimed.global_position
	if landed_pos == Vector2.INF:
		return

	# 落雷演出（2026-11-01 去线条化）：贴身光柱 + 落点环，不向天空拉任何折线。
	# 旧写法从 target_pos 上方 280px 拉一条锯齿雷柱，顶端没有锚点（悬在空气里），
	# 且每次暴击都来一条 —— 玩家读作「空气里凭空冒出的一道线」；目标被暴击打死/击退
	# 后更是只剩一条无归属的线。现在光柱底端钉在实际挨打的落点、顶端压在身位高度。
	JuiceEffect.spawn_sky_strike(host, landed_pos, bolt_tint)
	# pixelfx 接入点（回退：注释下一行）
	# 天罚落雷序列帧叠在贴身光柱同一落点：符阵贴地、主柱压身位（FxSheetData anchor=bottom），
	# 贴图自带雷电配色与 HDR 起辉，不再二次染色（tint 已由上方光柱与独立跳字表达）。
	FxFlipbookPool.play(&"lightning_strike", landed_pos)
	AudioManager.play_sfx("thunder_strike", 0.75)

## 天罚落点认领半径：落点附近这个距离内最近的那只敌人吃伤害。
## 取 28px 是敌人碰撞体量级 —— 暴击命中的目标必然在落点中心，够不着说明它刚被打死/击飞。
const SKY_BOLT_HIT_RADIUS := 28.0

## 天罚伤害落地：按位置就近认领（不靠对象引用，避免 host 侧硬类型依赖）。
## tint 透传给 take_damage 的 chain_tint 尾巴，让这份伤害独立显示（见 sky_bolt）。
## 返回实际挨打的那只（没认领到返回 null）—— 演出侧按它的实时身位画光柱。
static func _apply_sky_bolt_damage(target_pos: Vector2, damage: float, tint: Color) -> Node2D:
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
	return best

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

## 供测试/重置用：清空限流与递归状态
static func reset_gate() -> void:
	_last_event_ms = -999999
	_last_gate_ms.clear()
	_depth = 0
