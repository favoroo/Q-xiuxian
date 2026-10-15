class_name PoisonPool
extends Area2D

## 敌方投毒留下的「毒潭」：一片持续 N 秒的伤害区域，玩家踩在毒液上就按周期掉血。
## 2026-10-14 重塑：潭体是不规则液体摊（多子圆聚合），碰撞也拆成同一组子圆 ——
## 摊形与伤害面积逐子圆同源（画多大 == 判多大，精确到每一块）：踩在液面上掉血，
## 站在摊块之间的空隙不掉血。旧外圈判定虚线已删：威胁边界直接读液摊自身的形状，
## 起手预警圈（AoeTelegraph）仍然给出最大包络，预警只会多报不会少报。
## 铁律对齐（与 AoeTelegraph / EnemyBolt 同一套）：
##   - 范围视觉与判定同源：_blobs 是外观与碰撞的唯一真话，radius 是最大包络
##     （预警圈 / scale_factor 同源），本组件不自算范围。
##   - 伤害周期真话在持有者侧的口径：玩家走自己的受击无敌帧（BASE_INVULNERABLE_TIME）
##     ⇒ 结算间隔天然被钉住，这里只负责「人在液面上就每跳招呼一次」，不另造冷却。
##   - 持续时长真话在 EnemyBase（poison_duration 导出字段），池只认 duration 字段。
## 层级：地面贴花类 —— 宿主 Y 排序键钉在 GROUND_SORT_Y，在开 Y 排序的战层里
## 恒排在所有角色之前 ⇒ 永远渲染在角色脚下（与 GroundDecalHost 同一条修复）。

const RADIUS := 60.0                ## 基准包络半径（不含 scale_factor）：预警圈与 scale_factor 的同源锚
const MAX_BLOBS := 10               ## 液面子圆上限：碰撞形状槽按此数预建，激活时按下标复用
const POOL_BODY := Color(0.35, 0.75, 0.45)   ## 毒液本色（青木剧毒的绿）
const POOL_SHEEN := Color(0.62, 0.95, 0.66)  ## 液面亮芯（读「液体还在流动」）
const POOL_EDGE := Color(0.55, 0.95, 0.62)   ## 冒泡亮沿（读「正在腐噬」）
const POOL_DARK := Color(0.10, 0.28, 0.16)   ## 液面外暗晕
const FADE_TIME := 0.6              ## 末期渐隐时长（秒）：替代到点硬消失
const GROW_TIME := 0.22             ## 落地摊开生长时长（秒）：毒液从中心摊开，替代凭空满形态出现
const REDRAW_INTERVAL := 0.05       ## 冒泡/渐隐重绘节流（20Hz，照 ArenaVisualLayer 口径）
const DAMAGE_SCAN_INTERVAL := 0.0667 ## 伤害扫描节流（~15Hz，照 SunOrb 口径）：玩家受击无敌帧 ~0.5s，15Hz 必不漏跳
const GROUND_SORT_Y := -100000.0    ## 宿主 Y 排序钉死键：恒排在角色之前（永远画在角色脚下）

# —— 对象池（照 AstralGem / HealOrb / EnemyBolt 模式）——
## 投毒是周期技，一只怪 5 秒一发，同屏多只时 instantiate/free 的节点生命周期是实打实的分配热点。
const POOL_CAP := 24
static var _pool: Array[PoisonPool] = []
static var _host: Node2D = null
static var created_count: int = 0   ## 累计 instantiate 数（PoolCheck 断言用）
static var reused_count: int = 0
static var active_count: int = 0    ## 当前在场毒潭数：HUD 性能面板消费

## 取一滩毒（优先复用）：调用方随后写 global_position / damage / duration / scale_factor，最后 activate()
static func acquire(parent: Node) -> PoisonPool:
	if _host == null or not is_instance_valid(_host):
		_pool.clear()
		_host = Node2D.new()
		_host.name = "PoisonPoolHost"
		parent.add_child(_host)
		# 地面贴花层级钉（同 GroundDecalHost）：Y 排序键压到极小，毒潭无论落在哪
		# 都排在战层所有角色之前，永远画在角色脚下、地面细节之上
		_host.position = Vector2(0.0, GROUND_SORT_Y)
	while not _pool.is_empty():
		var p: PoisonPool = _pool.pop_back()
		if is_instance_valid(p):
			reused_count += 1
			p._reset_defaults()
			return p
	var np := PoisonPool.new()
	created_count += 1
	_host.add_child(np)
	return np

var damage: float = 4.0             ## 每跳伤害（跳的节奏由玩家受击无敌帧钉住）
var duration: float = 5.0           ## 持续时长（秒）
var scale_factor: float = 1.0       ## 整体缩放（外观与碰撞一起缩，同 EnemyBolt 口径）
var radius: float = RADIUS          ## 最大包络半径 = RADIUS × scale_factor（预警圈同源；摊形与碰撞都收在其内）

var _pooled: bool = false
var _shape_nodes: Array[CollisionShape2D] = []  ## 每块液面子圆一块碰撞圆（同源，激活时按下标覆写）
var _clock: float = 0.0             ## 视觉时钟（冒泡相位，不参与计时结算）
var _age: float = 0.0               ## 落地后经过时长（驱动摊开生长动画）
var _redraw_timer: float = 0.0      ## 重绘节流计时
var _dmg_scan_timer: float = 0.0    ## 伤害 overlap 扫描节流计时（15Hz + 错相）
var _blobs: Array[Vector3] = []     ## 液面子圆聚合：x/y = 偏移，z = 半径（外观与碰撞逐块同源）
var _bubbles: Array[Vector3] = []   ## 冒泡点：x/y = 偏移，z = 基准半径（相位由 _clock 驱动）
var _specks: Array[Vector3] = []    ## 液内暗斑：x/y = 偏移，z = 半径（静态质感，纯视觉无判定）

func _reset_defaults() -> void:
	damage = 4.0
	duration = 5.0
	scale_factor = 1.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	rotation = 0.0    # 毒潭是摊开的液面，不随节点旋转
	# 判定结算只走 _physics_process 的 overlap 扫描，不接 body_entered —— 原因见那里的注释
	# 碰撞与液摊拆成同一组子圆：预建 MAX_BLOBS 个形状槽，激活时逐块写偏移/半径并启用，
	# 余槽保持 disabled（不留幽灵判定圆）
	for _i in range(MAX_BLOBS):
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.disabled = true
		add_child(shape)
		_shape_nodes.append(shape)

## 出膛激活：池化后 _ready 只在首建时跑过，半径/寿命/摊形必须按当前字段重铺
func activate() -> void:
	_pooled = false
	active_count += 1
	# 池化复用是从回收点瞬移到新毒点：不重置物理插值，真机帧率抖动时首帧会渲染旧位置滑行
	reset_physics_interpolation()
	visible = true
	rotation = 0.0
	radius = RADIUS * maxf(scale_factor, 0.05)
	_clock = 0.0
	_age = 0.0
	_redraw_timer = 0.0
	# 错相初始化：多毒潭同屏时伤害扫描不在同一物理帧扎堆（照 SunOrb instance_id 错相）
	_dmg_scan_timer = fposmod(float(get_instance_id() % 97) * 0.001, DAMAGE_SCAN_INTERVAL)
	_generate_shape()
	_sync_collision()
	queue_redraw()
	# 碰撞恢复必须走 deferred：同帧「回收→复用」时回收的 disabled=true 会延迟到帧末 flush，
	# 直接赋 false 会被它覆盖（照 EnemyBolt.activate 同一条坑）
	set_deferred("monitoring", true)
	set_physics_process(true)

## 回收入池（替代 queue_free）：休眠物理与碰撞，池满或宿主失效才真释放
func recycle() -> void:
	if _pooled:
		return
	_pooled = true
	active_count = maxi(0, active_count - 1)
	set_physics_process(false)
	set_deferred("monitoring", false)
	for node in _shape_nodes:
		node.set_deferred("disabled", true)
	visible = false
	_reset_defaults()
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

## 摊形预生成：种子取位置哈希 —— 同一落点摊形可复现，且不消耗 GameManager.rng 的玩法随机流。
## 子圆中心偏移 + 半径严格收在包络 ×0.86 内（暗晕 ×1.08、暗渍 ×1.16 外扩后仍 ≤ 包络
## ×0.93 / ×0.998 —— 摊形再野，视觉也永不超出包络圈）。
func _generate_shape() -> void:
	_blobs.clear()
	_bubbles.clear()
	_specks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x) * 738.5) ^ int(absf(global_position.y) * 1934.9) ^ created_count
	# 锚子圆钉在中心附近：保证潭心有一块实打实的液面（怪朝玩家脚下投毒必中的那块）
	var anchor_r := radius * rng.randf_range(0.36, 0.44)
	_blobs.append(Vector3(rng.randf_range(-0.06, 0.06) * radius, rng.randf_range(-0.06, 0.06) * radius, anchor_r))
	# 卫星子圆把圆破成不规则摊：偏移越远半径越收，轮廓野而包络不破
	var blob_count := rng.randi_range(7, MAX_BLOBS)
	for _i in range(blob_count - 1):
		var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.60)
		var sub_r: float = minf(rng.randf_range(0.26, 0.46) * radius, radius * 0.86 - off.length())
		if sub_r > 3.0:
			_blobs.append(Vector3(off.x, off.y, sub_r))
	# 冒泡点 3~5 个，落在锚圆内的液面里层（保证「泡冒在毒液上」而不是悬空在地面）
	var bubble_count := rng.randi_range(3, 5)
	for _i in range(bubble_count):
		var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.28)
		_bubbles.append(Vector3(off.x, off.y, rng.randf_range(1.8, 3.2)))
	# 暗斑质感 3~5 点：液面层次更足，纯视觉无判定
	var speck_count := rng.randi_range(3, 5)
	for _i in range(speck_count):
		var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.26)
		_specks.append(Vector3(off.x, off.y, rng.randf_range(1.2, 2.6)))

## 液面子圆逐块写入碰撞形状槽（外观与碰撞逐块同源），余槽禁用
func _sync_collision() -> void:
	for i in range(_shape_nodes.size()):
		var node := _shape_nodes[i]
		if i < _blobs.size():
			var b := _blobs[i]
			node.position = Vector2(b.x, b.y)
			(node.shape as CircleShape2D).radius = b.z
			node.set_deferred("disabled", false)
		else:
			node.set_deferred("disabled", true)

func _draw() -> void:
	# 渐隐系数：末期 FADE_TIME 内线性降到 0，替代到点硬消失
	var fade := clampf(duration / FADE_TIME, 0.0, 1.0)
	# 落地摊开系数：0.4 → 1 ease-out（视觉「摊开」；期间碰撞已生效 —— 摊形只会画得
	# 比实际范围略小半拍，绝不画得比判定大）
	var grow_t := clampf(_age / GROW_TIME, 0.0, 1.0)
	var g := (0.4 + 0.6 * (1.0 - pow(1.0 - grow_t, 3.0))) * lerpf(0.75, 1.0, fade)
	# 液面：最外暗渍虚影 + 暗晕 + 毒液本体，三层同形不规则（暗渍压暗地面读「毒气熏地」）
	for b in _blobs:
		draw_circle(Vector2(b.x, b.y) * g, b.z * 1.16 * g, Color(POOL_DARK, 0.32 * fade))
	for b in _blobs:
		draw_circle(Vector2(b.x, b.y) * g, b.z * 1.08 * g, Color(POOL_DARK, POOL_DARK.a * fade))
	for b in _blobs:
		draw_circle(Vector2(b.x, b.y) * g, b.z * g, Color(POOL_BODY, POOL_BODY.a * fade))
	# 液面亮芯：较大子圆向中心收一圈的高光，读「液体还在流动」而非死贴片
	for b in _blobs:
		if b.z >= radius * 0.30:
			draw_circle(Vector2(b.x, b.y) * 0.45 * g, b.z * 0.52 * g, Color(POOL_SHEEN, 0.28 * fade))
	# 暗斑质感
	for s in _specks:
		draw_circle(Vector2(s.x, s.y) * g, s.z * g, Color(POOL_DARK, 0.55 * fade))
	# 冒泡：逐泡独立相位「胀大→破掉」，破时挑一帧细亮环，读「这滩毒还活着」
	for i in range(_bubbles.size()):
		var b := _bubbles[i]
		var cycle := fposmod(_clock * 0.9 + float(i) * 0.37, 1.0)
		var pulse := sin(cycle * PI)
		var br := b.z * pulse * g
		if br <= 0.2:
			continue
		draw_circle(Vector2(b.x, b.y) * g, br, Color(POOL_EDGE, 0.5 * fade * pulse))
		if cycle > 0.8:
			draw_arc(Vector2(b.x, b.y) * g, br + 1.5, 0.0, TAU, 10, Color(POOL_EDGE, (1.0 - cycle) * 2.5 * fade), 1.0, true)

func _physics_process(delta: float) -> void:
	# monitoring 是 deferred 开启的：activate 当帧还没 flush，overlap 扫描要等下一物理帧
	if not monitoring:
		return
	# 玩家踩在液面上就招呼：take_damage 自己按受击无敌帧节流 ⇒ 站毒里是稳定一跳一跳的掉血，
	# 而不是每帧一刀（伤害读数仍由玩家的护甲/闪避/免伤统一收口）。
	# 只走 overlap 扫描、不接 body_entered 信号：Area2D 的进入信号对「起手前就已经在毒里」
	## 的玩家不触发（毒潭多是砸在玩家脚下落成的），两条路径必须同一口径 —— 都在第一帧
	## 物理扫描里结算，先摆人后放潭与先放潭后摆人吃到的第一跳完全一致。
	# 伤害扫描节流 15Hz + 距离门控（照 SunOrb/HealOrb 先例）：玩家受击无敌帧 ~0.5s，
	# 15Hz 必不漏跳；玩家不在毒潭包络半径内时直接跳过 overlap 查询，省 get_overlapping_bodies。
	_dmg_scan_timer -= delta
	if _dmg_scan_timer <= 0.0:
		_dmg_scan_timer = DAMAGE_SCAN_INTERVAL
		var player := GameManager.player
		if player != null and is_instance_valid(player) and player.current_health > 0.0:
			# 距离门控：玩家中心超出毒潭包络半径 + 4px 容差就不可能踩在任何液面子圆里
			var d_sq := global_position.distance_squared_to(player.global_position)
			if d_sq <= (radius + 4.0) * (radius + 4.0):
				for body in get_overlapping_bodies():
					if body == player:
						body.take_damage(damage, global_position)
						break
	duration -= delta
	if duration <= 0.0:
		recycle()
		return
	# 视觉时钟：摊开生长段逐帧重绘（摊开要顺滑），之后只有冒泡相位与末段透明度在动，20Hz 节流
	_clock += delta
	_age += delta
	_redraw_timer -= delta
	if _age < GROW_TIME:
		queue_redraw()
	elif _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()
