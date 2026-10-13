class_name EnemyFilter
extends RefCounted

## 敌人圈定查询的共享过滤口径：遍历 "enemies" 组 → 剔除无效/垂死/自体/藏宝匣/灵草 → 半径圈内。
## 全 static，不读 autoload 不碰节点（铁律 2）；scene_tree 由调用方传 get_tree() 进来。
##
## 为什么要有这一份：这段 12 行口径过去在 Player（影爆/盾势/落雷×2/蛮兵计数）、EnemyBase（裂魂铃）
## 各抄一份，注释互相指「与御灵感知圈同一份过滤口径」——本意就是一份规则。今后新增
## 「在 enemies 组里但不算敌人」的东西（召唤物、圈套等）只改这里。
##
## 口径明细（与被替换的各份逐条对齐，行为零变化）：
##   - `as EnemyBase` 为 null ⇒ 跳过（藏宝匣 extends Node2D 本就不在此列，物理查询版才需要防它）
##   - `not is_instance_valid(e)` / `e.dying` ⇒ 跳过（垂死的还有塌缩动画，不再吃伤害）
##   - `e == from_self` ⇒ 跳过（裂魂铃自爆不炸自己；Player 侧传 null）
##   - chests / herbs 组 ⇒ 跳过（herbs 是灵草前瞻位，全仓暂无写入方，保留成本为零）
##   - 距离：`origin 到 e 的距离 ≤ radius`；radius 传 INF 即「全场」（祭坛冲击波口径）
##
## 不收进来的：物理查询版（Player._scan_orb_enemies、武器统筹、TurretUnit、FloatingWeapon、
## BladeProjectile）各有最近目标/椭圆射程/同屏优先/方向锥等真实选取语义差异，不强行合并。

## 圈定 origin 半径 radius 内的可伤害敌人（dying/无效/自体/匣子/灵草一律不在列）。
## from_self：调用方自身（自身若是 EnemyBase 则被剔除；Player 等非敌人传 null）。
static func collect(scene_tree: SceneTree, origin: Vector2, radius: float, from_self: Node2D = null) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if scene_tree == null:
		return out
	for node in scene_tree.get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or not is_instance_valid(e) or e.dying or e == from_self:
			continue
		if e.is_in_group("chests") or e.is_in_group("herbs"):
			continue
		if origin.distance_to(e.global_position) > radius:
			continue
		out.append(e)
	return out

## 只数圈内的可伤害敌人（蛮兵计数用，不建数组省一截 GC）
static func count_in_range(scene_tree: SceneTree, origin: Vector2, radius: float) -> int:
	var n := 0
	if scene_tree == null:
		return n
	var r2 := radius * radius
	for node in scene_tree.get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or not is_instance_valid(e) or e.dying:
			continue
		if e.is_in_group("chests") or e.is_in_group("herbs"):
			continue
		if origin.distance_squared_to(e.global_position) <= r2:
			n += 1
	return n

## 圈内最近的敌人（天雷索敌用）；圈里没有返回 null。
## max_dist 传初始搜索半径，返回值即「距离 ≤ max_dist 里最近的那只」。
static func nearest(scene_tree: SceneTree, origin: Vector2, max_dist: float) -> EnemyBase:
	var best: EnemyBase = null
	var best_d := max_dist
	if scene_tree == null:
		return best
	for node in scene_tree.get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or not is_instance_valid(e) or e.dying:
			continue
		if e.is_in_group("chests") or e.is_in_group("herbs"):
			continue
		var d: float = origin.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best
