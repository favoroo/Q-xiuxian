class_name EnemyFlock
extends RefCounted

## 敌群集行为数学（分离排斥 / 包围方位）。全部 static 纯计算，与 GameBalance 同一把尺子。
##
## 规约：只读邻居的 global_position 与 dying 标记（不写、不调其方法、不读 autoload、
## 不调全局 randf()）。输出 Vector2 交给调用方决定怎么用，本文件不碰任何节点状态。
##
## 2026-10-23 背景：旧版所有敌人一律直线插值追玩家（`_pp_target_vel = dir * eff_speed`），
## 同屏 3 只以上必然收束到同一点，叠成一坨读不出轮廓；合围阶段也看不出「包夹」的战术意图，
## 观感是「一群无脑靶子排队送死」而不是「一群妖物在围猎」。
## 两件事：
##   ① 分离排斥：半径内的同伴互推，把一坨摊开成可辨认的散兵线；
##   ② 包围方位：每只怪分配一个方位偏置，近距离时绕向自己的扇区，形成真正的合围。
## 两者都只做「转向」不改「步速」——合速度仍夹回 eff_speed，数值平衡零扰动。

const EPS := 0.0001
## 分离曲线幂次：1 = 线性；越大则重叠区越陡、外圈越缓。
## 取 1.4 是实测值 —— 线性曲线下 6 只围挤稳态只摊到 18px（仍叠一起），1.4 次幂下摊到 27px+。
const SEPARATION_FALLOFF := 1.4
## 合速度余量：分离推力可临时把速度顶到 1.15× 移速（横向分量要够才能摊开队形）。
const COMBINE_SLACK := 1.15

## 空间哈希桶（2026-10-23 性能）：O(n²) 全表扫描在 35 敌满载帧实测把物理帧从 9.8ms 顶到 13ms。
## 分桶后每只只查自己所在格 + 相邻 8 格（格边长 = 分离半径），邻居数从 35 降到 3~6，
## 复杂度 O(n)。桶容器是 static 复用（_draw 同款做法：主线程串行，无重入风险）。
static var _grid: Dictionary = {}
static var _grid_cell: float = 0.0

## 分离排斥：半径内同伴按「贴得越近推得越狠」累加，归一化后封顶 max_push。
## others 传 GameManager.live_enemies 本体（不复制数组，避免每帧分配）。
## 内部先做一次空间分桶：同一帧内多只怪调用本函数时桶已建好，只有首次调用付建桶成本。
static func separation_push(self_pos: Vector2, others: Array, self_id: int, radius: float, max_push: float) -> Vector2:
	if radius <= 0.0 or max_push <= 0.0:
		return Vector2.ZERO
	_ensure_grid(others, radius)
	var cx := int(floor(self_pos.x / radius))
	var cy := int(floor(self_pos.y / radius))
	var r_sq := radius * radius
	var acc := Vector2.ZERO
	# 只查 3×3 邻域（格边长 = 半径 ⇒ 半径内的邻居必在这 9 格里）
	for gx in range(cx - 1, cx + 2):
		for gy in range(cy - 1, cy + 2):
			var bucket: Array = _grid.get(Vector2i(gx, gy), [])
			if bucket == null:
				continue
			for o in bucket:
				if o == null or not is_instance_valid(o):
					continue
				if o.get_instance_id() == self_id:
					continue
				# 濒死个体不参与推挤的过滤在建桶时做（_ensure_grid 里 dying 的根本不入桶）。
				# 2026-10-24 移除原先此处的 o.get("dying") 反射复查：Object.get(name) 是字符串
				# 哈希查找，每怪每邻居一次 ≈ 千次/秒的纯开销；建桶排除 + 帧号自愈重建已覆盖
				# 常规路径，残余的同帧竞态（建桶后才标记 dying）最多让塌缩尸体多推同伴一帧，
				# 视觉不可辨。单测 unit_flock_tests 的 dying 用例走建桶路径，口径不变。
				var d: Vector2 = self_pos - o.global_position
				var d_sq: float = d.length_squared()
				if d_sq > r_sq or d_sq < EPS:
					continue
				var dist: float = sqrt(d_sq)
				acc += (d / dist) * pow(1.0 - dist / radius, SEPARATION_FALLOFF)
	var acc_len: float = acc.length()
	if acc_len < EPS:
		return Vector2.ZERO
	# 归一化后按「压满一只紧贴的邻居」封顶：多只挤在一处不会叠加成失控的推力
	return acc / acc_len * minf(acc_len, 1.0) * max_push

## 重建空间网格（每物理帧首只怪触发一次；cell = 分离半径 ⇒ 半径内邻居必在 3×3 邻域）。
## 代价 O(n)，比 O(n²) 低一个量级；桶数组复用 static 容器，稳态零分配。
## 有效性（2026-10-24 口径修正）：生产路径靠 Engine.get_physics_frames() 帧号自愈作废 ——
## 位置每帧都变，下一物理帧帧号不同自然触发重建，无需任何调用方手动 invalidate。
## invalidate_grid() 只作为测试接缝保留：headless 单测的多个用例跑在同一物理帧内，
## 需要它强制重建（见 unit_flock_tests 各用例前的调用）。
static func _ensure_grid(others: Array, radius: float) -> void:
	if _grid_frame == Engine.get_physics_frames():
		return
	_grid_frame = Engine.get_physics_frames()
	_grid.clear()
	_grid_cell = radius
	for o in others:
		if o == null or not is_instance_valid(o):
			continue
		if o.get("dying") == true:
			continue
		var gp: Vector2 = o.global_position
		var key := Vector2i(int(floor(gp.x / radius)), int(floor(gp.y / radius)))
		# Dictionary.get 返回 Variant，直接标 Array 会在缺键时把 Nil 塞进 Array 变量并抛错。
		# 先取 Variant 再判空，缺键时才建桶。
		var found = _grid.get(key)
		if found == null:
			var new_bucket: Array = []
			_grid[key] = new_bucket
			new_bucket.append(o)
		else:
			var bucket: Array = found
			bucket.append(o)

static var _grid_frame: int = -1

## 强制作废网格（测试接缝：同物理帧内多次用例间强制重建；生产路径靠帧号自愈，勿在游戏代码里调用）
static func invalidate_grid() -> void:
	_grid_frame = -1

## 包围方位：把追击方向旋转 orbit_bias 并混一丝切向分量，让近战怪绕向各自的扇区。
## bias 在 activate() 时按实例抽一次，正负决定顺时针/逆时针包抄。
static func orbit_dir(dir: Vector2, bias: float, blend: float) -> Vector2:
	if dir.length_squared() < EPS or absf(bias) < EPS:
		return dir
	var tangent: Vector2 = Vector2(-dir.y, dir.x) * signf(bias)
	return (dir.rotated(bias) + tangent * blend).normalized()

## 合速度夹回步速上限：转向只改方向、不加移速（否则分离会把怪推成「加速怪」，平衡失真）。
## 上限给 15% 余量：所有怪都朝玩家一个点挤，径向分量会被追引力吃掉，
## 只留横向分量根本摊不开（实测夹死 1.0× 时稳态仍 17px）。这点余量只在「重叠推开」瞬间出现，
## 稳态会自己回到 1.0× —— 判据按 1.15× 钉住，超了报红。
static func combine(target_vel: Vector2, push: Vector2, max_speed: float) -> Vector2:
	var v: Vector2 = target_vel + push
	var cap: float = max_speed * COMBINE_SLACK
	if max_speed > 0.0 and v.length_squared() > cap * cap:
		return v.normalized() * cap
	return v
