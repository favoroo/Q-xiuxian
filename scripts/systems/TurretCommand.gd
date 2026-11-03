class_name TurretCommand
extends RefCounted

## 机关指挥层（2026-11-03 手动布设改版）：把「玩家按了一下机关按钮」翻译成
## 具体的布设 / 收回 / 维修动作，并给 HUD 提供读数。
##
## 为什么单独一层：布设逻辑原先长在 TurretHandler.perform（武器侧），而它现在要读
## 玩家位置、槽位顺序、编制余额 —— 塞进 Player.gd（核心热区大文件）或 FloatingWeapon
## 都不合适；这里按项目「static 伪 autoload」的路子做纯静态协调层，宿主一律鸭类型访问，
## 不引入任何硬类型反向引用（项目坑 12）。
##
## 门控只在 HUD（战斗阶段/暂停态），本层只管规则本身，方便判据直接调。

# ---------------- 读数 ----------------

## 全部机关武器（按槽位顺序 = weapon_holder 子节点序），非机关武器被过滤掉。
## 返回 Array 而不是带类型的 Array[FloatingWeapon]：避免在本层硬引用武器类。
static func mechanism_weapons(player) -> Array:
	var out: Array = []
	if player == null or not is_instance_valid(player):
		return out
	var holder = player.get("weapon_holder")
	if holder == null:
		return out
	for child in holder.get_children():
		if child != null and child.has_method("is_mechanism") and child.is_mechanism():
			out.append(child)
	return out

## 待布设编制数（按钮右上角 ×N）：所有机关武器的空余编制之和
## （单编制武器各 1；飞升「双联神机」后每把 2）
static func ready_count(player) -> int:
	var n := 0
	for w in mechanism_weapons(player):
		n += int(w.free_charges())
	return n

## 收回后的整备倒数剩余秒数：多把机关武器取最长的那条（按钮「整备 N秒」读数）
static func cooldown_left(player) -> float:
	var left := 0.0
	for w in mechanism_weapons(player):
		left = maxf(left, float(w.redeploy_timer))
	return left

## 下一个该布设的机关武器（槽位序第一个「还有空余编制」的），没有则 null
static func next_ready(player):
	for w in mechanism_weapons(player):
		if w.free_charges() > 0:
			return w
	return null

## 场上全部自己的机关
static func deployed_turrets(player) -> Array[TurretUnit]:
	var out: Array[TurretUnit] = []
	for w in mechanism_weapons(player):
		for t in w.field_turrets():
			out.append(t)
	return out

## 需要维修（磨损或停摆）的机关数：HUD「N 座待修」芯片读它
static func service_count(player) -> int:
	var n := 0
	for t in deployed_turrets(player):
		if t.needs_service():
			n += 1
	return n

# ---------------- 靠近判定 / 落点 ----------------

## 离 pos 最近的一座自己的机关（超过 radius 返回 null）
static func nearest_turret(player, pos: Vector2, radius: float) -> TurretUnit:
	var best: TurretUnit = null
	var best_d := radius * radius
	for t in deployed_turrets(player):
		var d := t.global_position.distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = t
	return best

## 到最近一座自己的机关的距离（没有则返回一个大数）
static func nearest_turret_dist(player, pos: Vector2) -> float:
	var best := 1.0e9
	for t in deployed_turrets(player):
		best = minf(best, t.global_position.distance_to(pos))
	return best

## 收回的目标：全场离 pos 最近的一座自己的机关（RECALL_RADIUS <= 0 时无视距离）。
## HUD 的收回键显隐与 recall_nearest 都读它，保证「键亮着 == 按下去真能收」。
static func recall_candidate(player, pos: Vector2) -> TurretUnit:
	var radius := BalanceTurret.RECALL_RADIUS
	if radius <= 0.0:
		return nearest_turret(player, pos, 1.0e9)
	return nearest_turret(player, pos, radius)

## 布设落点：玩家脚下沿移动反方向外沿（静止时偏下），避开压在身上；
## 按 GameManager.MAP_HALF_EXTENT - 26.0 做 XY 钳制，避免贴边时落点出结界。
static func deploy_candidate_pos(player) -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if player is CharacterBody2D:
		dir = (player as CharacterBody2D).velocity
	var pos: Vector2 = player.global_position + BalanceTurret.deploy_offset(dir)
	var bound: float = GameManager.MAP_HALF_EXTENT - 26.0
	pos.x = clampf(pos.x, -bound, bound)
	pos.y = clampf(pos.y, -bound, bound)
	return pos

## 坐标 pos 是否为空地（tests/turret_check.gd 在用）：pos 是落点坐标，
## 与最近一座自己机关的距离必须 ≥ MIN_TURRET_SPACING。
static func is_open_ground(player, pos: Vector2) -> bool:
	return BalanceTurret.is_open_ground(nearest_turret_dist(player, pos))

## 预选落点是否为空地：deploy_candidate_pos(player) 到最近机关距离 ≥ MIN_TURRET_SPACING
static func is_landing_open(player) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return BalanceTurret.is_open_ground(nearest_turret_dist(player, deploy_candidate_pos(player)))

## 是否可布设：有待布设编制且落点为空地
static func can_deploy(player) -> bool:
	return next_ready(player) != null and is_landing_open(player)

## 现在能不能布设：先判 no_charge，再按落点判 occupied，空串 = 可布设
static func deny_reason(player) -> String:
	if player == null or not is_instance_valid(player):
		return "no_player"
	if next_ready(player) == null:
		return "no_charge"
	if not is_landing_open(player):
		return "occupied"
	return ""

# ---------------- 动作 ----------------

## 最近一次布设失败的原因码（"" = 没失败）："cap" 编制满 / "scene" 机关场景实例化不出来 /
## "internal" 其它。HUD 用它把「为什么布不了」说清 —— 以前无论哪一环掉了都只报一句
## 「现在不能布设机关」，玩家看不懂、排查也无从下手。
static var last_error: String = ""

## 布设一座：成功返回机关节点，失败返回 null。耐久沿用收回时带回的量（新机关 = 满耐久）。
static func deploy_at_player(player) -> TurretUnit:
	last_error = ""
	if not can_deploy(player):
		return null
	var w = next_ready(player)
	if w == null:
		return null
	var pos := deploy_candidate_pos(player)
	# 布设演出的起点：玩家身上（器核从人物飞向落点）。非 Node2D 宿主（判据桩）传 INF 直接落地。
	var from_pos := Vector2.INF
	if player is Node2D:
		from_pos = (player as Node2D).global_position
	var turret: TurretUnit = w.deploy_turret_at(pos, from_pos)
	if turret == null and TurretHandler.last_error == "scene":
		# 场景缓存可能是空的/坏的（导出包里 preload 退化成空 PackedScene，坑 12 同源）：
		# 丢掉缓存重读一次 —— 只重试这一回，不再让玩家对着按键点半天没反应。
		w.reload_turret_scene()
		turret = w.deploy_turret_at(pos, from_pos)
	if turret == null:
		last_error = TurretHandler.last_error
		if last_error.is_empty():
			last_error = "internal"
		push_warning("[TURRET] 布设失败：%s" % last_error)
		return null
	w.on_turret_deployed()
	return turret

## 收回最近的一座机关（2026-11-03：不再限距离、不再起整备倒数）。返回是否真的收回了。
## 多编制下一把武器可能站着两座，所以必须点名收回「最近的那一座」，
## 不能像单编制时代那样笼统地让武器自己挑第一座。
## 距离口径走 BalanceTurret.RECALL_RADIUS（当前 = 全场不限）：玩家在场边也能点收回，
## 机关打不到宝箱时不用先跑过去。
static func recall_nearest(player, pos: Vector2) -> bool:
	var t := recall_candidate(player, pos)
	if t == null:
		return false
	var owner = t._owner_weapon
	if owner == null or not is_instance_valid(owner) or not owner.has_method("recall_turret"):
		return false
	return owner.recall_turret(t)