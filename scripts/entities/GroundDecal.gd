class_name GroundDecal
extends Node2D

## 地面贴花：震地落点的「震裂」与火焰/爆炸落点的「焦痕」。
## 纯视觉、无判定 —— 判定在持有者侧结算完毕后才调用本组件留痕（照 AoeTelegraph「只画不判」铁律）。
## 形态在 activate() 用本地 RNG 预生成（种子 = 位置哈希，不走 GameManager.rng，不污染玩法随机流），
## _draw() 只画不随机：裂纹折线算法复用 GroundDecorLayer §3.2，焦痕聚合复用 §3.1 青苔模式。
## 生命周期：HOLD 全亮 → FADE 渐隐 → 回收入池（对象池照 PoisonPool 范式）。

enum Kind { CRACK, SCORCH, FADE_GLOW }

const HOLD_TIME := 1.6   ## 全亮留存时长（秒）
const FADE_TIME := 0.7   ## 渐隐时长（秒）
const GROW_TIME := 0.12  ## 裂纹向外爆开生长时间（秒）
## 击杀残晕寿命（FADE_GLOW）：高频击杀事件的贴地余韵，整体压短防糊屏
const GLOW_HOLD_TIME := 0.15
const GLOW_FADE_TIME := 0.40
const GROUND_SORT_Y := -100000.0  ## 宿主 Y 排序钉死键：恒排在角色之前（同 PoisonPool.GROUND_SORT_Y）

## 重绘节流（遵守 20Hz VisualRate 约定，杜绝每帧无脑重绘）
const REDRAW_INTERVAL := 0.05
var _redraw_timer: float = 0.0

const CRACK_SHADOW := Color(0.02, 0.03, 0.05, 0.85)  ## 裂口深沉阴影底（线宽 2.8px）
const CRACK_CORE := Color(0.65, 0.82, 0.95, 0.60)    ## 裂缝冷月反光亮芯（线宽 1.2px，石质断层高光）
const CRACK_RIM := CRACK_CORE                         ## 兼容旧别名
const CRACK_DENT := Color(0.02, 0.04, 0.06, 0.42)    ## 落点中心凹痕（暗面扩展）
const CRACK_DEBRIS := Color(0.55, 0.68, 0.78, 0.70)  ## 迸溅微碎石亮面
const CRACK_DEBRIS_SHADOW := Color(0.02, 0.03, 0.05, 0.60) ## 碎石落影
const SCORCH_BODY := Color(0.05, 0.04, 0.04, 0.50)   ## 焦痕炭黑
const SCORCH_EMBER := Color(0.85, 0.35, 0.12, 0.28)  ## 余烬暗橙（渐隐时同步熄灭）
## 击杀残晕（FADE_GLOW）：冷灰灵烬为主调，敌种主色（_tint）只留一丝余温 ——
## 与出生预警的实心红圆+十字煞针彻底拉开色相与形态，不再误读为「又要刷怪」
const GLOW_ASH := Color(0.66, 0.78, 0.90, 1.0)   ## 灵烬冷灰主调（贴地残痕结构色）
const GLOW_SHADE := Color(0.03, 0.05, 0.08, 0.35) ## 残痕贴地暗影

var _tint: Color = Color.WHITE   ## FADE_GLOW 专用：敌种主色（spawn 时传入）

# —— 对象池（照 PoisonPool 范式）——
const POOL_CAP := 16
static var _pool: Array[GroundDecal] = []
static var _host: Node2D = null
static var created_count: int = 0   ## 累计 new 数（PoolCheck 断言用）
static var reused_count: int = 0
static var active_count: int = 0    ## 当前在场贴花数

## 取一枚贴花（优先复用）：调用方随后写 global_position / kind / radius，最后 activate()
static func acquire(parent: Node) -> GroundDecal:
	if _host == null or not is_instance_valid(_host):
		_pool.clear()
		_host = Node2D.new()
		_host.name = "GroundDecalHost"
		parent.add_child(_host)
		# 地面贴花层级钉（同 PoisonPoolHost）：开 Y 排序的战层里宿主恒排最前，
		# 震裂/焦痕无论落在哪都画在角色脚下，不会盖到玩家/敌人身上
		_host.position = Vector2(0.0, GROUND_SORT_Y)
	while not _pool.is_empty():
		var d: GroundDecal = _pool.pop_back()
		if is_instance_valid(d):
			reused_count += 1
			return d
	var nd := GroundDecal.new()
	created_count += 1
	_host.add_child(nd)
	return nd

## 一步出膛：持有者结算完伤害后在落点留痕
static func spawn(parent: Node, pos: Vector2, p_kind: int, p_radius: float) -> GroundDecal:
	var d := acquire(parent)
	d.global_position = pos
	d.kind = p_kind
	d.radius = p_radius
	d.activate()
	return d

## 带色出膛（FADE_GLOW 专用）：击杀余韵用敌种主色在原地留一记贴地淡出残晕。
## 高频事件（每秒多次击杀）：寿命压到 0.55s，比震裂/焦痕短一个量级，不让地面糊满。
static func spawn_tinted(parent: Node, pos: Vector2, p_radius: float, col: Color) -> GroundDecal:
	var d := acquire(parent)
	d.global_position = pos
	d.kind = Kind.FADE_GLOW
	d.radius = p_radius
	d._tint = col
	d.activate()
	return d

var kind: int = Kind.CRACK
var radius: float = 100.0   ## 视觉包络半径：贴花内容永不超出此圈

var _pooled: bool = false
var _age: float = 0.0
var _time_left: float = 0.0
var _hold_time: float = HOLD_TIME   ## 按 kind 在 activate() 落定（FADE_GLOW 走短寿命档）
var _fade_time: float = FADE_TIME
var _cracks: Array[PackedVector2Array] = []   ## 裂纹折线（震裂用）
var _debris: Array[Vector3] = []               ## 碎石颗粒：x/y = 偏移，z = 半径（震裂用）
var _blobs: Array[Vector3] = []               ## 子圆聚合：x/y = 偏移，z = 半径（焦痕用）
var _ring_segs: Array[Vector3] = []           ## 断环符纹：x = 起始角，y = 跨度，z = 半径系数（残晕用）
var _embers: Array[Vector3] = []              ## 烬点：x/y = 偏移，z = 半径（残晕用）
var _ember_phase: Array[float] = []           ## 烬点闪烁相位（与 _embers 一一对应）
var _wisps: Array[Vector3] = []               ## 烟缕基点：x/y = 偏移，z = 长度系数（残晕用）

## 出膛激活：按 kind 预生成形态，随后进入「留存→渐隐→回收」计时
func activate() -> void:
	_pooled = false
	active_count += 1
	# 池化复用是从回收点瞬移到新落点：不重置物理插值会渲染「从旧位置滑过来」（PoisonPool 同一条坑）
	reset_physics_interpolation()
	visible = true
	_age = 0.0
	# 寿命按 kind 分档：震裂/焦痕长留存，击杀残晕是高频事件走 0.55s 短档
	#（旧写法恒用 HOLD+FADE 2.3s，spawn_tinted 预设的短寿命被这里覆盖，红圆在地上赖 2.3s 才被读出撞脸出生预警）
	if kind == Kind.FADE_GLOW:
		_hold_time = GLOW_HOLD_TIME
		_fade_time = GLOW_FADE_TIME
	else:
		_hold_time = HOLD_TIME
		_fade_time = FADE_TIME
	_time_left = _hold_time + _fade_time
	_redraw_timer = 0.0
	_generate_shape()
	set_process(true)
	queue_redraw()

## 回收入池：休眠绘制与计时，池满或宿主失效才真释放
func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_process(false)
	visible = false
	if _host == null or not is_instance_valid(_host) or _pool.size() >= POOL_CAP:
		queue_free()
		return
	_pool.append(self)

## 释放池内全部休眠个体（Main._exit_tree 随场景清）
static func clear_pool() -> void:
	_pool.clear()
	_host = null
	created_count = 0

## 池内休眠体总数（探针/判据用）
static func pool_idle_count() -> int:
	return _pool.size()

## 形态预生成：种子取位置哈希 —— 同一落点形态可复现，且不消耗 GameManager.rng 的玩法随机流
func _generate_shape() -> void:
	_cracks.clear()
	_debris.clear()
	_blobs.clear()
	_ring_segs.clear()
	_embers.clear()
	_ember_phase.clear()
	_wisps.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x) * 738.5) ^ int(absf(global_position.y) * 1934.9) ^ (created_count + reused_count)
	match kind:
		Kind.CRACK:
			var branch_count := rng.randi_range(5, 7)
			for _i in range(branch_count):
				var pts := PackedVector2Array()
				pts.append(Vector2.ZERO)
				var curr := Vector2.ZERO
				# 主方向沿圆周均布 + 抖动，避免裂纹全挤向一侧
				var dir := Vector2.RIGHT.rotated(TAU * float(_i) / float(branch_count) + rng.randf_range(-0.4, 0.4))
				var traveled := 0.0
				var seg_count := rng.randi_range(3, 5)
				for _k in range(seg_count):
					dir = dir.rotated(rng.randf_range(-0.5, 0.5))
					var seg_len: float = minf(rng.randf_range(0.18, 0.30) * radius, radius * 0.95 - traveled)
					if seg_len <= 1.0:
						break
					curr += dir * seg_len
					traveled += seg_len
					pts.append(curr)
				if pts.size() >= 2:
					_cracks.append(pts)
			# 伴随碎石：沿裂口附近点缀 6~8 颗微碎石（均收在包络圈内）
			var debris_count := rng.randi_range(6, 8)
			for _d in range(debris_count):
				var d_dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
				var d_dist := rng.randf_range(radius * 0.15, radius * 0.75)
				var d_pos := d_dir * d_dist
				var d_size := rng.randf_range(1.2, 2.4)
				if d_pos.length() + d_size <= radius * 0.90:
					_debris.append(Vector3(d_pos.x, d_pos.y, d_size))
		Kind.SCORCH:
			var blob_count := rng.randi_range(7, 9)
			for _i in range(blob_count):
				var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.55)
				# 子圆边缘不超出包络圈：视觉永不超出名义半径（与判定同源铁律的贴花版）
				var sub_r: float = minf(rng.randf_range(0.28, 0.50) * radius, radius * 0.95 - off.length())
				if sub_r > 2.0:
					_blobs.append(Vector3(off.x, off.y, sub_r))
		Kind.FADE_GLOW:
			# 灵烬残痕：断环符纹 + 烬点 + 烟缕，全部预生成、绘制零随机
			var seg_count := rng.randi_range(3, 4)
			for i in range(seg_count):
				var start := TAU * float(i) / float(seg_count) + rng.randf_range(-0.3, 0.3)
				_ring_segs.append(Vector3(start, rng.randf_range(0.5, 1.0), rng.randf_range(0.72, 0.95)))
			var ember_count := rng.randi_range(5, 7)
			for _i in range(ember_count):
				var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
				var pos := dir * rng.randf_range(0.0, radius * 0.55)
				_embers.append(Vector3(pos.x, pos.y, rng.randf_range(0.9, 1.8)))
				_ember_phase.append(rng.randf_range(0.0, TAU))
			for _i in range(3):
				var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
				var pos := dir * rng.randf_range(0.0, radius * 0.25)
				_wisps.append(Vector3(pos.x, pos.y, rng.randf_range(0.55, 0.9)))

func _process(delta: float) -> void:
	_age += delta
	_time_left -= delta
	if _time_left <= 0.0:
		recycle()
		return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()

## 沿折线按生长进度截取子折线（0.12s 蔓延爆裂）
static func _sample_crack_growth(pts: PackedVector2Array, grow: float) -> PackedVector2Array:
	if grow >= 0.999 or pts.size() <= 1:
		return pts
	var total_len: float = 0.0
	for i in range(1, pts.size()):
		total_len += pts[i - 1].distance_to(pts[i])
	var target_len: float = total_len * grow
	var res := PackedVector2Array()
	res.append(pts[0])
	var cur_len: float = 0.0
	for i in range(1, pts.size()):
		var seg_len := pts[i - 1].distance_to(pts[i])
		if cur_len + seg_len <= target_len:
			res.append(pts[i])
			cur_len += seg_len
		else:
			var remain := target_len - cur_len
			var frac := remain / maxf(seg_len, 0.001)
			res.append(pts[i - 1].lerp(pts[i], frac))
			break
	if res.size() < 2 and pts.size() >= 2:
		res.append(pts[0].lerp(pts[1], maxf(grow, 0.08)))
	return res

func _draw() -> void:
	# 渐隐系数：留存期恒 1，末段线性降到 0（渐隐窗按 kind 分档，与 activate() 同源）
	var a := clampf(_time_left / _fade_time, 0.0, 1.0)
	match kind:
		Kind.CRACK:
			# 0~0.12s 快速爆裂展开（平滑开方缓动，第 1 帧即见雏形）
			var raw_grow := clampf(_age / GROW_TIME, 0.0, 1.0) if GROW_TIME > 0.0 else 1.0
			var grow := sqrt(raw_grow)
			var dent_r := radius * 0.42 * grow
			draw_circle(Vector2.ZERO, dent_r, Color(CRACK_DENT, CRACK_DENT.a * a))
			draw_circle(Vector2.ZERO, dent_r * 0.45, Color(CRACK_DENT, CRACK_DENT.a * a * 1.3))
			for pts in _cracks:
				var draw_pts := _sample_crack_growth(pts, grow)
				if draw_pts.size() >= 2:
					# 底层粗黑崩口阴影（2.8px，拉开与地砖缝隙的粗细反差）
					draw_polyline(draw_pts, Color(CRACK_SHADOW, CRACK_SHADOW.a * a), 2.8)
					# 表层断层冷光亮芯（1.2px，石质断层冷月高光）
					draw_polyline(draw_pts, Color(CRACK_CORE, CRACK_CORE.a * a), 1.2)
			# 伴随碎石随爆开向外就位并显现
			if grow > 0.35:
				var deb_a := a * clampf((grow - 0.35) / 0.65, 0.0, 1.0)
				for deb in _debris:
					var dpos := Vector2(deb.x, deb.y) * grow
					draw_circle(dpos + Vector2(0.8, 1.0), deb.z, Color(CRACK_DEBRIS_SHADOW, CRACK_DEBRIS_SHADOW.a * deb_a))
					draw_circle(dpos, deb.z, Color(CRACK_DEBRIS, CRACK_DEBRIS.a * deb_a))
		Kind.SCORCH:
			for b in _blobs:
				draw_circle(Vector2(b.x, b.y), b.z, Color(SCORCH_BODY, SCORCH_BODY.a * a))
			# 余烬核：比焦黑更快熄灭（×a²），读「火刚烧过」
			var ember := Color(SCORCH_EMBER, SCORCH_EMBER.a * a * a)
			for b in _blobs:
				draw_circle(Vector2(b.x, b.y), b.z * 0.45, ember)
		Kind.FADE_GLOW:
			# 击杀余韵「灵烬余痕」（2026-10-16 重设计）：冷灰断环符纹 + 闪烁烬点 + 升腾烟缕，
			# 敌种主色只留一丝余温。旧版实心敌色双圆与出生预警红圈撞脸（尤其血煞系小怪），
			# 现版以「压扁贴地 + 冷灰为主 + 零碎断笔」三个手段与预警的正圆红环拉开读数。
			# 出生即最大（尸体塌缩那一帧脚下亮起），不做生长动画——高频事件要的是轻。
			var total := _hold_time + _fade_time
			var life_t := clampf(_age / maxf(total, 0.01), 0.0, 1.0)
			var ring_col := GLOW_ASH.lerp(_tint, 0.30)
			var ember_col := _tint.lightened(0.4).lerp(Color.WHITE, 0.3)
			var wisp_col := GLOW_ASH.lerp(_tint, 0.45)
			# 贴地层统一压扁（俯视贴地感，形态上与正圆预警圈再拉开一档）
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.62))
			draw_circle(Vector2.ZERO, radius * (0.9 - 0.2 * life_t), Color(GLOW_SHADE, GLOW_SHADE.a * a))
			var ring_r := radius * (1.0 - 0.22 * life_t)
			for seg in _ring_segs:
				draw_arc(Vector2.ZERO, ring_r * seg.z, seg.x, seg.x + seg.y, 10,
					Color(ring_col.r, ring_col.g, ring_col.b, 0.7 * a), 1.5, true)
			# 内晕：极淡的敌色余温，随消散微缩
			draw_circle(Vector2.ZERO, radius * 0.46 * (1.0 - 0.35 * life_t),
				Color(_tint.r, _tint.g, _tint.b, 0.14 * a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# 烬点：微光闪烁上浮，熄灭比整体更快（×a²）
			for i in range(_embers.size()):
				var e := _embers[i]
				var tw := 0.55 + 0.45 * sin(_age * 9.0 + _ember_phase[i])
				var epos := Vector2(e.x, e.y * 0.62) + Vector2(0.0, -life_t * 3.0)
				draw_circle(epos, e.z, Color(ember_col.r, ember_col.g, ember_col.b, 0.65 * tw * a * a))
			# 烟缕：三缕残烟自烬痕升起，摇曳消散（顶端收在包络圈内）
			for i in range(_wisps.size()):
				var w := _wisps[i]
				var base := Vector2(w.x, w.y * 0.62)
				var rise := life_t * radius * 0.4 * w.z
				var sway := sin(_age * 2.4 + float(i) * 2.1) * 2.2
				var tip := base + Vector2(sway, -rise - radius * 0.25 * w.z)
				draw_line(base + Vector2(0.0, -rise * 0.3), tip,
					Color(wisp_col.r, wisp_col.g, wisp_col.b, 0.42 * a * a), 1.2, true)
