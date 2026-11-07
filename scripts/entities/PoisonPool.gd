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
##
## 【2026-11-07 pixelfx 液面】潭体液面改由常驻子精灵承担（毒潭 toxic_puddle / 火池 ember_pool，
## loop 贴地），原「实心圆堆液面 + 多阶羽化底晕 + 暗流亮芯 + 暗斑」四段矢量绘制下线（_draw 留
## 回退注释）；矢量冒泡保留（液面活性）。贴图世界宽 = 液摊包围盒宽（画多大 == 判多大）。
## 子圆聚合形状与逐块碰撞（_blobs / _shape_nodes）一行未动，仍是外观与判定的唯一真话。

enum Kind { POISON, FIRE }

const RADIUS := 60.0                ## 基准包络半径（不含 scale_factor）：预警圈与 scale_factor 的同源锚
const MAX_BLOBS := 10               ## 液面子圆上限：碰撞形状槽按此数预建，激活时按下标复用
const GROUND_SQUASH := 0.62         ## 俯视透视压扁比（同 GroundDecal.FADE_GLOW 与实体软阴影，营造贴地感）

# 毒池调色板
const POOL_BODY := Color(0.18, 0.42, 0.26, 0.78)   ## 毒液本色：降饱和与亮度，偏深青苔绿，融入冷调地砖
const POOL_SHEEN := Color(0.40, 0.72, 0.48, 0.20)  ## 液面流动内光：低反差暗流感
const POOL_EDGE := Color(0.48, 0.85, 0.54, 0.65)   ## 冒泡亮沿：保留腐蚀动态读数，收敛泛光
const POOL_DARK := Color(0.04, 0.08, 0.07, 0.40)   ## 腐蚀浸润底晕：近黑深青，读「毒气浸透石砖」

# 火池调色板（Boss 烈焰吐息留在地面的余火）
const FIRE_BODY := Color(0.42, 0.15, 0.05, 0.80)   ## 暗红岩浆
const FIRE_SHEEN := Color(0.95, 0.55, 0.16, 0.22)  ## 流动橙光
const FIRE_EDGE := Color(1.00, 0.72, 0.28, 0.70)   ## 亮橙冒泡
const FIRE_DARK := Color(0.10, 0.03, 0.02, 0.42)   ## 焦黑浸润

const PALETTE_POISON := {
	"body": POOL_BODY,
	"sheen": POOL_SHEEN,
	"edge": POOL_EDGE,
	"dark": POOL_DARK,
}
const PALETTE_FIRE := {
	"body": FIRE_BODY,
	"sheen": FIRE_SHEEN,
	"edge": FIRE_EDGE,
	"dark": FIRE_DARK,
}

const FADE_TIME := 0.6              ## 末期渐隐时长（秒）：替代到点硬消失
const GROW_TIME := 0.22             ## 落地摊开生长时长（秒）：毒液从中心摊开，替代凭空满形态出现
const REDRAW_INTERVAL := 0.05       ## 冒泡/渐隐重绘节流（20Hz，照 ArenaVisualLayer 口径）
const DAMAGE_SCAN_INTERVAL := 0.0667 ## 伤害扫描节流（~15Hz，照 SunOrb 口径）：玩家受击无敌帧 ~0.5s，15Hz 必不漏跳
const GROUND_SORT_Y := -100000.0    ## 宿主 Y 排序钉死键：恒排在角色之前（永远画在角色脚下）

## pixelfx 液面贴图（2026-11-07 线条圈通刷接入）：替代原「实心圆堆液面 + 多阶羽化底晕」。
## 毒/火两套同画幅同基础缩放（176×100 / 0.90），由 set_kind 换帧。
const SURFACE_POISON := &"toxic_puddle"
const SURFACE_FIRE := &"ember_pool"

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
var pool_kind: int = Kind.POISON

## 只改调色板与视觉参数，可随时调用；activate 前调最稳
func set_kind(k: int) -> void:
	if pool_kind == k:
		return
	pool_kind = k
	_apply_surface_frames()
	queue_redraw()

func _palette(k: int = -1) -> Dictionary:
	var target_kind := pool_kind if k < 0 else k
	return PALETTE_FIRE if target_kind == Kind.FIRE else PALETTE_POISON

var _pooled: bool = false
var _shape_nodes: Array[CollisionShape2D] = []  ## 每块液面子圆一块碰撞圆（同源，激活时按下标覆写）
var _clock: float = 0.0             ## 视觉时钟（冒泡相位，不参与计时结算）
var _age: float = 0.0               ## 落地后经过时长（驱动摊开生长动画）
var _redraw_timer: float = 0.0      ## 重绘节流计时
var _dmg_scan_timer: float = 0.0    ## 伤害 overlap 扫描节流计时（15Hz + 错相）
var _blobs: Array[Vector3] = []     ## 液面子圆聚合：x/y = 偏移，z = 半径（外观与碰撞逐块同源）
var _bubbles: Array[Vector3] = []   ## 冒泡点：x/y = 偏移，z = 基准半径（相位由 _clock 驱动）
var _specks: Array[Vector3] = []    ## 液内暗斑：x/y = 偏移，z = 半径（静态质感，纯视觉无判定）
var _surface: AnimatedSprite2D = null  ## 液面贴图子精灵（loop 常驻，随宿主节点走；不占 FxFlipbookPool 池位）
var _surface_scale_base: float = 1.0   ## 液面精灵基础缩放（不含生长/渐隐系数）：世界宽 = 液摊包围盒宽

func _reset_defaults() -> void:
	pool_kind = Kind.POISON
	damage = 4.0
	duration = 5.0
	scale_factor = 1.0
	# 染色归白：毒妖投毒是本色，剑煞雷剑域靠 modulate 乘法染血煞色；
	# 池化复用必须回白，否则毒妖会捡到上一滩的红色（2026-10-22 精英双招式）
	modulate = Color.WHITE

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
	_build_surface()

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
	# 液面贴图与三件套同拍：换帧 → 显隐 → 缩放/透明度一次铺齐（池化复用不留上一滩的残影）
	_apply_surface_frames()
	if _surface != null:
		_surface.visible = _surface.sprite_frames != null
	_sync_surface()
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
	if _surface != null:
		_surface.visible = false
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
	# 冒泡点：火池略少（2~4 个），毒池 3~5 个，落在锚圆内的液面里层（保证「泡冒在液面上」而不是悬空在地面）
	var bubble_count := rng.randi_range(2, 4) if pool_kind == Kind.FIRE else rng.randi_range(3, 5)
	for _b in range(bubble_count):
		var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.28)
		_bubbles.append(Vector3(off.x, off.y, rng.randf_range(1.8, 3.2)))
	# 暗斑质感 3~5 点：液面层次更足，纯视觉无判定
	var speck_count := rng.randi_range(3, 5)
	for _i in range(speck_count):
		var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.26)
		_specks.append(Vector3(off.x, off.y, rng.randf_range(1.2, 2.6)))
	# 液面贴图缩放跟液摊走：贴图世界宽 = 液摊包围盒宽（画多大 == 判多大，不放大暗示范围）
	_surface_scale_base = _surface_scale_from_blobs()

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

## pixelfx 液面精灵（2026-11-07 接入）：替代原矢量实心圆堆液面 + 多阶羽化底晕。
## 为什么不走 FxFlipbookPool：毒潭是常驻 loop 件（同场最多 POOL_CAP 滩），进池会挤掉一次性
## 特效名额；子精灵随宿主节点走（activate 亮 / recycle 灭），不占池。
func _build_surface() -> void:
	if _surface != null:
		return
	var anim := AnimatedSprite2D.new()
	anim.name = "SurfaceFx"
	anim.centered = true
	# 贴地层：宿主 y 已钉 GROUND_SORT_Y（在开 y_sort 的战层里恒排最前），精灵必须留在宿主的
	# y-sort 分组内 —— 若照 FxFlipbookPool.Z_GROUND(=2) 给绝对 z 会跳出分组盖到角色身上；
	# 照 SpawnIndicator._build_portal_native 的配方：z=0（不用负 z，EntitiesLayer 全员 z=0，
	# 负 z 会整只沉到 MapLayer 地砖之下不可见）+ show_behind_parent（液面画在 _draw 的冒泡之下）。
	anim.z_as_relative = false
	anim.z_index = 0
	anim.show_behind_parent = true
	anim.visible = false   ## 未 activate 前先收起（显隐与三件套同拍：activate 亮 / recycle 灭）
	anim.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(anim)
	_surface = anim
	_apply_surface_frames()

## 按当前 kind 装帧（毒/火两套液面）；贴图缺失时精灵保持不可见，冒泡照旧兜底
func _apply_surface_frames() -> void:
	if _surface == null:
		return
	var id: StringName = SURFACE_FIRE if pool_kind == Kind.FIRE else SURFACE_POISON
	var frames := FxSheetData.get_sprite_frames(id)
	_surface.sprite_frames = frames
	if frames == null:
		_surface.visible = false
		return
	_surface.animation = &"default"
	_surface.offset = FxSheetData.get_offset(id)   ## center 锚点：offset 已把潭心对准节点原点
	_surface.play(&"default")

## 液面精灵基础缩放：贴图世界宽 = 液摊包围盒宽 D ⇒ scale = D / 画幅宽（不含生长/渐隐系数）
## 画幅世界宽 = frame_size.x × 基础 scale，故先算 mult = D /(frame_size.x × 基础 scale) 再乘回基础 scale。
func _surface_scale_from_blobs() -> float:
	if _blobs.is_empty():
		return 0.0
	var min_x := INF
	var max_x := -INF
	for b in _blobs:
		min_x = minf(min_x, b.x - b.z)
		max_x = maxf(max_x, b.x + b.z)
	var d: float = maxf(max_x - min_x, 1.0)
	var id: StringName = SURFACE_FIRE if pool_kind == Kind.FIRE else SURFACE_POISON
	var conf: Dictionary = FxSheetData.get_config(id)
	var fw: float = 176.0
	var base: float = 1.0
	if not conf.is_empty():
		var fs: Vector2 = conf.get("frame_size", Vector2(176.0, 100.0))
		fw = maxf(fs.x, 1.0)
		base = float(conf.get("scale", 1.0))
	return base * (d / (fw * base))

## 液面视觉因子：x = 末期渐隐系数(0~1)，y = 落地摊开系数(0.4→1)。
## 贴图液面与矢量冒泡共用同一口径（改一处两边同时跟手）。
func _surface_factors() -> Vector2:
	var fade := clampf(duration / FADE_TIME, 0.0, 1.0)
	var grow_t := clampf(_age / GROW_TIME, 0.0, 1.0)
	var g := (0.4 + 0.6 * (1.0 - pow(1.0 - grow_t, 3.0))) * lerpf(0.75, 1.0, fade)
	return Vector2(fade, g)

## 液面精灵跟生长/末期渐隐：缩放乘摊开系数 g（绕潭心收放，同矢量子圆的收缩口径），
## 透明度吃渐隐 fade（替代原来的到点硬消失）。
func _sync_surface() -> void:
	if _surface == null or _surface.sprite_frames == null:
		return
	var f := _surface_factors()
	_surface.scale = Vector2.ONE * (_surface_scale_base * f.y)
	_surface.modulate = Color(1.0, 1.0, 1.0, f.x)

func _draw() -> void:
	BatchDraw.flush(self)
	# 液面本体由常驻子精灵 _surface 承担（见 _build_surface）；这里只留矢量冒泡（液面活性）。
	var f := _surface_factors()
	var fade: float = f.x
	var g: float = f.y

	# 俯视透视压扁：与地面角度对齐，消除立面漂浮感（冒泡仍在节点空间里压扁绘制）
	BatchDraw.flush(self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))

	var pal := _palette()
	var c_edge: Color = pal["edge"]

	# pixelfx 接入点（回退：取消下面整段注释，用矢量液面顶替贴图液面）
	# 原「多阶羽化底晕 → 液面本体 → 液面暗流亮芯 → 暗斑」四段（已由 _surface 贴图承担）：
	# var c_dark: Color = pal["dark"]
	# var c_body: Color = pal["body"]
	# var c_sheen: Color = pal["sheen"]
	# for b in _blobs:
	# 	BatchDraw.native_circle(self, Vector2(b.x, b.y) * g, b.z * 1.22 * g, Color(c_dark.r, c_dark.g, c_dark.b, 0.16 * fade))
	# for b in _blobs:
	# 	BatchDraw.native_circle(self, Vector2(b.x, b.y) * g, b.z * 1.12 * g, Color(c_dark.r, c_dark.g, c_dark.b, 0.30 * fade))
	# for b in _blobs:
	# 	BatchDraw.native_circle(self, Vector2(b.x, b.y) * g, b.z * 1.04 * g, Color(c_dark.r, c_dark.g, c_dark.b, 0.45 * fade))
	# for b in _blobs:
	# 	BatchDraw.native_circle(self, Vector2(b.x, b.y) * g, b.z * g, Color(c_body.r, c_body.g, c_body.b, c_body.a * fade))
	# for b in _blobs:
	# 	if b.z >= radius * 0.30:
	# 		BatchDraw.native_circle(self, Vector2(b.x, b.y) * 0.45 * g, b.z * 0.52 * g, Color(c_sheen.r, c_sheen.g, c_sheen.b, c_sheen.a * fade))
	# for s in _specks:
	# 	BatchDraw.native_circle(self, Vector2(s.x, s.y) * g, s.z * g, Color(c_dark.r, c_dark.g, c_dark.b, 0.45 * fade))

	# 冒泡：逐泡独立相位「胀大→破掉」，破时挑一帧细亮环，读「这滩液面还活着」
	var clk: float = _clock * (1.6 if pool_kind == Kind.FIRE else 1.0)
	for i in range(_bubbles.size()):
		var b := _bubbles[i]
		var cycle := fposmod(clk * 0.9 + float(i) * 0.37, 1.0)
		var pulse := sin(cycle * PI)
		var br := b.z * pulse * g
		if br <= 0.2:
			continue
		BatchDraw.native_circle(self, Vector2(b.x, b.y) * g, br, Color(c_edge.r, c_edge.g, c_edge.b, c_edge.a * fade * pulse))
		if cycle > 0.8:
			BatchDraw.native_arc(self, Vector2(b.x, b.y) * g, br + 1.2, 0.0, TAU, 10, Color(c_edge.r, c_edge.g, c_edge.b, (1.0 - cycle) * 2.0 * fade), 1.0, true)

	# 恢复变换
	BatchDraw.flush(self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	BatchDraw.flush(self)
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
	_sync_surface()   # 贴图液面与矢量冒泡同口径：生长段逐帧、之后 60Hz 只是几次赋值，忽略不计
	_redraw_timer -= delta
	if _age < GROW_TIME:
		queue_redraw()
	elif _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()
