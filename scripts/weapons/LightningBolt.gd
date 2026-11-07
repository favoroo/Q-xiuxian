class_name LightningBolt
extends Node2D

## 五雷法牌引雷演出：从武器射向落雷点的锯齿闪电（细亮芯 + 柔光晕 + 单芯分支）
## 已接入静态对象池（POOL_CAP=16），零动态 new/queue_free 分配。
##
## 2026-10-18 视觉简化与性能优化：
## 1. 线宽与层数收拢：主光晕 7.0→4.5，主芯 2.4→1.8；分支电弧剔除光晕层只留 1.1px 单芯，常驻 4 线减为 3 线。
## 2. 几何更克制：锯齿折段间距 22→28px，抖幅 14→9px，折点减少约 25%，观感干净平直。
## 3. 电弧余韵减量：3 条→2 条、时长 0.2s→0.15s、长度 20→15px。
## 4. 降档联动：glow 关闭时隐藏主光晕层（无 bloom 时宽半透明线只耗填充），拥挤档（FxBudget.crowded）跳过分支电弧与余韵。

## HDR 超白核心：辉光阈值钉在 1.0，只有这条核心线溢出起辉，外层 alpha 假光晕保持 LDR 不双辉
const CORE_COLOR := GameStyle.FX_HDR_LIGHTNING
const GLOW_COLOR := Color(0.55, 0.85, 1.0, 0.38)
const LDR_CORE_COLOR := Color(0.82, 0.94, 1.0, 0.95)  ## glow 关闭时的备用清晰亮芯
## 池容量：2026-10-26 由 16 抬到 24 —— 七路雷电拆成各自独立的演出闸之后，
## 同一次团战里可能同时出现紫电链 + 雷劫链 + 天罚落雷 + 反震环，16 个池体不够周转
## （池满时 acquire 直接 new，回池时超出容量的 queue_free，高频下变成持续分配）。
const POOL_CAP := 24

# —— 基准线宽（配合 width_mult 等比缩放）——
const BASE_WIDTH_GLOW := 4.8
const BASE_WIDTH_CORE := 2.0
const BASE_WIDTH_BRANCH := 1.2

# —— 电弧余韵（T-2.5，微型电弧从命中点消散，短促收敛）——
const ARC_AFTERGLOW_COUNT := 2     ## 2 条微型电弧
const ARC_AFTERGLOW_LIFE := 0.08   ## 余韵窗口（s，迅捷消散，不拖泥带水）
const ARC_AFTERGLOW_LEN := 12.0    ## 单条微弧最大长度（px）
const ARC_AFTERGLOW_WIDTH := 1.0   ## 微弧线宽（细芯）

## 拴绳弧存活时长（s）：2026-11-07 电刀重做。电刀一闪即收，不留长残影，
## 也不能长到让玩家看清「这条线其实在空气里」。
const TRACKED_LIFE := 0.09
## 单帧寿命消耗上限（s）：卡顿帧/冷启动首帧 delta 可能一次超过整条寿命，
## 裸 delta 会让电弧「闪都没闪就消失」。
const MAX_TRACK_STEP := 0.033
## 光晕层透明度：tint 是不透明的 HDR 色，直接铺成宽线就是一条实心粗带（读起来像粉色绳子）。
## 光晕只负责边缘泛光，亮度感交给 HDR 芯线。
const GLOW_ALPHA := 0.38

static var _pool: Array[LightningBolt] = []
static var _host: Node2D = null

var _line_glow: Line2D
var _line_core: Line2D
var _line_branch_core: Line2D
var _afterglow: Array[Line2D] = []
var _tween: Tween = null
var _is_pooled: bool = false

# ----------------- 端点拴绳（2026-11-07 电刀重做）-----------------
## 链电的敌人↔敌人连线必须钉在两只敌人身上：端点每帧按节点实时坐标重算，
## 敌人被击退/移动时电弧跟着走，敌人一死立刻收线。
## 旧写法在 activate 当刻把两端坐标拍成快照，敌人一动电弧就留在原地 ——
## 这正是玩家看到「紫电在空气里飞」的本体。
## 折线形状只在激活时抽一次（存成「沿程比例 t + 法向偏移 d」），之后每帧按新端点重铺：
## 既跟着敌人走，又不会因为每帧重随机而糊成一片噪点。
var _track_a: Node2D = null
var _track_b: Node2D = null
var _track_off_a: Vector2 = Vector2.ZERO
var _track_off_b: Vector2 = Vector2.ZERO
var _track_trim_a: float = 0.0
var _track_trim_b: float = 0.0
## true = 两端沿 a→b 方向各退 trim 半径（体缘对体缘，用于敌人↔敌人连线）；
## false = 用固定偏移（用于缠身电这类绕体小弧）
var _track_radial: bool = false
var _shape_t: PackedFloat32Array = PackedFloat32Array()
var _shape_d: PackedFloat32Array = PackedFloat32Array()
var _track_life_left: float = 0.0
## 逐帧重铺用的工作数组（复用，避免每条拴绳弧每帧 resize 一次）
var _pts_work: PackedVector2Array = PackedVector2Array()
## 本帧折线两端的世界坐标（判据读它验证「端点钉在敌人身上」）
var _track_end_a: Vector2 = Vector2.ZERO
var _track_end_b: Vector2 = Vector2.ZERO

# ----------------- 池管理 -----------------

static func clear_cache() -> void:
	_pool.clear()
	_host = null

static func _ensure_host(scene: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	_pool.clear()
	_host = Node2D.new()
	_host.name = "LightningBoltPool"
	_host.z_index = 0
	scene.add_child(_host)

static func acquire(parent: Node) -> LightningBolt:
	_ensure_host(parent)

	while not _pool.is_empty():
		var reused: LightningBolt = _pool.pop_back()
		if is_instance_valid(reused):
			reused.visible = true
			return reused

	var bolt := LightningBolt.new()
	bolt._is_pooled = true
	_host.add_child(bolt)
	return bolt

func _recycle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_clear_tracking()
	visible = false
	if _pool.size() < POOL_CAP and is_instance_valid(_host):
		_pool.append(self)
	else:
		queue_free()

## 清空拴绳状态并停掉逐帧跟随（回池/收线共用）
func _clear_tracking() -> void:
	_track_a = null
	_track_b = null
	_track_off_a = Vector2.ZERO
	_track_off_b = Vector2.ZERO
	_track_trim_a = 0.0
	_track_trim_b = 0.0
	_track_radial = false
	_shape_t = PackedFloat32Array()
	_shape_d = PackedFloat32Array()
	_track_end_a = Vector2.ZERO
	_track_end_b = Vector2.ZERO
	_track_life_left = 0.0
	set_process(false)

# ----------------- 生命周期与构建 -----------------

func _ready() -> void:
	_setup_lines()
	# 脚本里定义了 _process，Godot 入树时会自动开启处理；拴绳弧才需要逐帧重铺，
	# 普通一次性电弧必须关掉（否则池里每个池体每帧空跑一次 _rebuild_tracked）。
	set_process(false)

func _setup_lines() -> void:
	if _line_glow != null:
		return
	# 2026-10-18 视觉简化：4 线收缩为 3 线（移除分支光晕，单芯足以表达折角），基准线宽缩细
	_line_glow = _create_line(BASE_WIDTH_GLOW, GLOW_COLOR)
	_line_core = _create_line(BASE_WIDTH_CORE, CORE_COLOR)
	_line_branch_core = _create_line(BASE_WIDTH_BRANCH, CORE_COLOR)
	for i in ARC_AFTERGLOW_COUNT:
		_afterglow.append(_create_line(ARC_AFTERGLOW_WIDTH, CORE_COLOR))

func _create_line(w: float, col: Color) -> Line2D:
	var line := Line2D.new()
	line.width = w
	line.default_color = col
	# 照 ProjectileTrail 同款治理（2026-10-16）：闪电 jagged 折点密集，ROUND joint
	# 每拐点扇形三角化是顶点爆炸源；折线细（1~3px）方关节接缝肉眼不可见
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	line.z_index = 0
	add_child(line)
	return line

## 芯线色由 tint 推导（2026-10-26 七路雷电分色）：
## 旧写法只有光晕层吃 tint，芯线永远是白 —— 紫电/雷劫/血海各自染了外圈，
## 中间仍是同一道白雷，远看还是一张卡。这里保住 tint 的色相把芯也染上：
##   HDR 档（glow 开）：把最亮分量抬到 CORE_HDR_PEAK，色相不变、亮度与白芯同档；
##   LDR 档（glow 关）：归一后向白提亮 —— 没有 bloom 时芯线仍要读得出「亮」。
const CORE_HDR_PEAK := 2.5     ## 芯线最亮分量（与 FX_HDR_CORE 的 2.6 同档）
const LDR_CORE_WHITEN := 0.55  ## LDR 芯向白提亮的比例（保住色相又不至于发灰）

static func _core_color_for(tint_col: Color, glow_active: bool) -> Color:
	var max_c := maxf(tint_col.r, maxf(tint_col.g, tint_col.b))
	if max_c <= 0.001:
		return CORE_COLOR if glow_active else LDR_CORE_COLOR
	if glow_active:
		var k: float = CORE_HDR_PEAK / max_c
		return Color(tint_col.r * k, tint_col.g * k, tint_col.b * k, 1.0)
	var base := Color(tint_col.r / max_c, tint_col.g / max_c, tint_col.b / max_c, 1.0)
	return base.lerp(Color(1.0, 1.0, 1.0, 1.0), LDR_CORE_WHITEN)

## 激活动画（出膛）：全量重置坐标、折线点与淡出 Tween
## core_tint：芯线色覆盖（alpha==0 = 不覆盖，走原逻辑）。★3/★4 追加雷用它把
## 白热芯也染上星级色相 —— 只染光晕层时追加雷读起来仍是「一道白雷套金边」。
## allow_branch=false：链电传导弧专用 —— 不甩中段分支、不出空气余韵微弧，
## 线端之外不许有电（电刀模式「电只在敌人身上与敌人之间的连线上」的演出闸口）。
func activate(from_pos: Vector2, to_pos: Vector2, tint_col: Color, width_mult: float = 1.0, core_tint: Color = Color(0, 0, 0, 0), allow_branch: bool = true) -> void:
	_setup_lines()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_clear_tracking()

	global_position = from_pos
	var main_points := _build_jagged_points(from_pos, to_pos)
	var is_crowded := FxBudget.crowded
	var glow_active := bool(SettingsManager.get_val(&"display", &"glow", true)) and not bool(SettingsManager.get_val(&"display", &"glow_auto_off", false))

	# 主干赋值：glow 关闭时隐藏光晕层（无 bloom 时宽半透明多边形只白耗带宽）
	# 线宽与配色无论开关都要写（2026-10-26 池复用卫生）：池体是复用的，
	# 上一次在 glow 开档写的 width/color 会留在节点上；只在开档写会让「关档期间
	# 复用到的池体」带着上一轮的旧线宽 —— PoolCheck 的「按 width_mult 重置线宽」
	# 断言正是踩到这个（关档后读到上一轮残留的 5.4）。
	_line_glow.width = BASE_WIDTH_GLOW * width_mult
	_line_glow.default_color = tint_col
	if glow_active:
		_line_glow.visible = true
		_line_glow.points = main_points
	else:
		_line_glow.visible = false

	var core_c: Color
	if core_tint.a > 0.0:
		core_c = core_tint
	elif glow_active:
		core_c = CORE_COLOR if tint_col == GLOW_COLOR else _core_color_for(tint_col, true)
	else:
		core_c = _core_color_for(tint_col, false)

	_line_core.visible = true
	_line_core.points = main_points
	_line_core.width = BASE_WIDTH_CORE * width_mult
	_line_core.default_color = core_c

	# 分支电弧赋值：拥挤档（同屏敌≥24）或链电传导弧（allow_branch=false）时跳过分支，专注主干
	var branch_points := _build_branch_points(main_points, to_pos - from_pos) if allow_branch and not is_crowded else PackedVector2Array()
	if branch_points.size() >= 2:
		_line_branch_core.points = branch_points
		_line_branch_core.width = BASE_WIDTH_BRANCH * width_mult
		_line_branch_core.default_color = core_c
		_line_branch_core.visible = true
	else:
		_line_branch_core.visible = false

	# 余韵跟着这次电弧的色相走（旧写法固定雷光白：紫电散场后留两条白弧，读起来像换了张卡）
	for arc_line in _afterglow:
		arc_line.default_color = core_c

	modulate.a = 1.0
	visible = true

	# 2026-10-26 视觉优化：电弧极速击穿收束（0.075s），告别贴图般漫长的渐隐
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.075).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 电弧余韵：拥挤档/链电传导弧跳过余韵直接回池（余韵是向随机方向甩的微型弧 ——
	# 链电模式下那正是「空气里也有电」的来源，电刀只在敌人身上炸，不往外散）
	if not is_crowded and allow_branch:
		_tween.tween_callback(_spawn_afterglow)
	else:
		_tween.tween_callback(_after_afterglow)

## 拴绳弧专用「白热芯」色（2026-11-07）：在 tint 色相基础上向白大幅提亮。
## 旧口径 _core_color_for 只把最亮分量抬到 CORE_HDR_PEAK、色相不变 —— 紫电得到的是
## 一条**饱和紫**的实心线，混战里读作「紫色绳子」而不是闪电。
## 闪电的读法是「白热芯 + 边缘泛色」，所以这里把芯色向白推 CORE_WHITEN_RATIO：
## 保留 tint 的色相倾向（紫电偏紫、雷劫偏绯），但主亮度靠白。
const CORE_WHITEN_RATIO := 0.62
static func _hot_core_color(tint_col: Color, glow_active: bool) -> Color:
	var max_c := maxf(tint_col.r, maxf(tint_col.g, tint_col.b))
	var base := Color(1.0, 1.0, 1.0, 1.0)
	if max_c > 0.001:
		base = Color(tint_col.r / max_c, tint_col.g / max_c, tint_col.b / max_c, 1.0)
	var hot := base.lerp(Color(1.0, 1.0, 1.0, 1.0), CORE_WHITEN_RATIO)
	if not glow_active:
		return hot
	# HDR 档：整体抬到超白区间，靠 bloom 起辉（色相随白化后仍带一点 tint 倾向）
	var peak := maxf(hot.r, maxf(hot.g, hot.b))
	if peak <= 0.001:
		return CORE_COLOR
	var k: float = CORE_HDR_PEAK / peak
	return Color(hot.r * k, hot.g * k, hot.b * k, 1.0)

## 拴绳激活（2026-11-07 紫电电刀重做）：电弧两端钉在两个节点上，逐帧按实时坐标重铺折线。
## 这是「电只在敌人身上 / 敌人之间」的唯一实现方式 —— 旧 activate 把两端坐标拍成快照，
## 敌人被击退或移动后电弧就悬在原地，玩家读作「紫电在空气里飞」。
##
## a / b：两端锚点节点，必须有效（可为同一只敌人 = 缠身电）。
##   不接受 null：Godot 在节点被释放后会把 Lambda/变量里的引用换成 null，
##   若把 null 当成「静态世界坐标」，敌人一死电弧反而永远不收（这正是「残线留在空气里」）。
## off_a / off_b：锚点偏移（节点坐标系内的常向量，缠身电用它把端点收在身体半径内）。
## trim_a / trim_b：沿 a→b 方向各退的像素（radial=true 时用，让连线从体缘起、到体缘止）。
## radial=true：偏移按「a→b 方向」解释为退让量（敌人↔敌人连线）；
## radial=false：偏移按固定常向量解释（缠身电绕体小弧）。
## 折线形状（沿程比例 + 法向偏移）只在激活时抽一次，之后每帧按新端点重铺 ——
## 既跟着敌人走，又不会每帧重随机糊成噪点。
## 端点任一失效（敌人被打死 / 出树）立刻收线回池，绝不留残线。
## 任一锚点为 null 时直接返回 false（调用方不必画）—— 宁可少画一道，也不画无主的线。
func activate_tracked(a: Node2D, b: Node2D, off_a: Vector2, off_b: Vector2,
		trim_a: float, trim_b: float, radial: bool, tint_col: Color,
		width_mult: float = 1.0, core_tint: Color = Color(0, 0, 0, 0)) -> bool:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	_setup_lines()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_clear_tracking()

	_track_a = a
	_track_b = b
	_track_off_a = off_a
	_track_off_b = off_b
	_track_trim_a = trim_a
	_track_trim_b = trim_b
	_track_radial = radial

	var pa := _anchor_world(a, off_a)
	var pb := _anchor_world(b, off_b)
	var dist := pa.distance_to(pb)
	# 折线形状：段长 10px（比旧 14px 更细碎，闪电的折点是密集的，不是一条波浪）。
	# 抖幅分两层：低频大摆（sin 包络压两端，保证端点点位不动）+ 高频小抖（每一折都变向）——
	# 只有低频会读成「粉色绳子」，只有高频会读成「毛刺」，两层叠起来才是电击穿轮廓。
	# 抖幅必须**随机正负**（旧写法 envelope*0.75 恒为正 ⇒ 整条线朝一侧鼓成平滑弧）。
	var amp := clampf(dist * 0.22, 4.0, 11.0)
	var segs := maxi(int(dist / 10.0), 6)
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var d := 0.0
		if i > 0 and i < segs:
			var envelope := sin(t * PI)
			d = (randf_range(-amp, amp) * envelope) + randf_range(-amp * 0.35, amp * 0.35)
		_shape_t.append(t)
		_shape_d.append(d)

	global_position = pa
	var glow_active := _glow_enabled()
	_line_glow.width = BASE_WIDTH_GLOW * width_mult
	# 光晕层必须是**低透明度**柔光（GLOW_ALPHA），不能直接用 tint ——
	# tint 是不透明的 HDR 色，直接铺上去就是一条实心粗带，读起来像粉色绳子而不是闪电。
	# 亮度感交给芯线（_hot_core_color 抬到 CORE_HDR_PEAK），光晕只负责边缘泛光。
	_line_glow.default_color = Color(tint_col.r, tint_col.g, tint_col.b, GLOW_ALPHA)
	_line_glow.visible = glow_active
	var core_c: Color
	if core_tint.a > 0.0:
		core_c = core_tint
	else:
		core_c = _hot_core_color(tint_col, glow_active)
	_line_core.visible = true
	_line_core.width = BASE_WIDTH_CORE * width_mult
	_line_core.default_color = core_c
	# 拴绳弧一律不甩分支与余韵（那是「空气里也有电」的来源）
	_line_branch_core.visible = false
	for arc_line in _afterglow:
		arc_line.visible = false
		arc_line.default_color = core_c

	_rebuild_tracked()
	modulate.a = 1.0
	visible = true
	_track_life_left = TRACKED_LIFE
	set_process(true)
	return true

func _process(delta: float) -> void:
	# 寿命自己累计，不用 Tween：拴绳弧本来就要逐帧重铺折线，顺手把淡出也算在这里。
	# 单帧 delta 钳到 MAX_TRACK_STEP —— 卡顿帧/首帧启动时 delta 可能一次就超过整条寿命，
	# 用裸 delta 会让电弧「闪都没闪就消失」（headless 与冷启动都踩到过）。
	_track_life_left -= minf(delta, MAX_TRACK_STEP)
	if _track_life_left <= 0.0:
		_after_afterglow()
		return
	_rebuild_tracked()
	modulate.a = clampf(_track_life_left / TRACKED_LIFE, 0.0, 1.0)

## 每帧按两端实时坐标重铺折线；任一端失效立刻收线（不留空气残线）
func _rebuild_tracked() -> void:
	if _shape_t.is_empty():
		set_process(false)
		return
	if not _anchor_alive(_track_a) or not _anchor_alive(_track_b):
		_after_afterglow()
		return
	var pa := _anchor_world(_track_a, _track_off_a)
	var pb := _anchor_world(_track_b, _track_off_b)
	var dir := pb - pa
	if _track_radial and dir.length_squared() > 0.0001:
		var n := dir.normalized()
		pa += n * _track_trim_a
		pb -= n * _track_trim_b
		dir = pb - pa
	var side := dir.orthogonal().normalized()
	var base := pa - global_position
	# 工作数组按需长到形状长度（拴绳弧存活 90ms，重铺十几次，别每帧 resize 一个新 PackedVector2Array）
	if _pts_work.size() != _shape_t.size():
		_pts_work.resize(_shape_t.size())
	for i in range(_shape_t.size()):
		_pts_work[i] = base + dir * _shape_t[i] + side * _shape_d[i]
	_line_core.points = _pts_work
	if _line_glow.visible:
		_line_glow.points = _pts_work
	# 两端实际落点读数（判据用：端点必须钉在锚点身上）。用成员变量而不是 set_meta ——
	# 每帧写 meta 会连带分配一个 Array，拴绳弧同屏十几条时就是纯垃圾。
	_track_end_a = pa
	_track_end_b = pb

## 锚点有效性：两端都必须是在树的有效节点。**参数不标类型** —— 已释放的实例传给
## `Node2D` 形参会直接抛 "previously freed is not a subclass of the expected argument class"，
## 而这个函数恰恰就是用来判定「锚点是否已释放」的（敌人被击杀出树时走到这里）。
## 注意 null 也必须判死：Lambda 捕获的节点被释放后，Godot 会把它换成 null 再传进来
## （"Lambda capture at index 1 was freed. Passed null instead."）——
## 旧写法把 null 当成「用固定世界坐标当锚点」，结果敌人一死电弧反而永远不收。
static func _anchor_alive(n) -> bool:
	return n != null and is_instance_valid(n) and (n as Node2D).is_inside_tree()

## 锚点世界坐标：调用前必须已过 _anchor_alive；参数同样不标类型
static func _anchor_world(n, off: Vector2) -> Vector2:
	if n == null or not is_instance_valid(n):
		return off
	return (n as Node2D).global_position + off

static func _glow_enabled() -> bool:
	return bool(SettingsManager.get_val(&"display", &"glow", true)) \
		and not bool(SettingsManager.get_val(&"display", &"glow_auto_off", false))

## 主干已淡出，从命中点向四周散 2 条微型电弧（细芯，0.15s 渐隐），演完回池。
## 微弧线与主干同为本节点子线、共享局部坐标系：origin 直接取主干折线末点（命中端）局部坐标。
func _spawn_afterglow() -> void:
	var pts := _line_core.points
	var origin := pts[pts.size() - 1] if pts.size() >= 2 else Vector2.ZERO
	for arc_line in _afterglow:
		var dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var tip := origin + dir.rotated(randf_range(-0.5, 0.5)) * randf_range(ARC_AFTERGLOW_LEN * 0.6, ARC_AFTERGLOW_LEN)
		arc_line.points = build_jagged_points(origin, tip, 8.0, 4.0)
		arc_line.visible = true
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, ARC_AFTERGLOW_LIFE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_after_afterglow)

## 余韵熄灯后把所有子线藏掉再回池：池体复用靠 activate 全量重铺，隐藏只是视觉兜底
func _after_afterglow() -> void:
	_line_glow.visible = false
	_line_core.visible = false
	_line_branch_core.visible = false
	for arc_line in _afterglow:
		arc_line.visible = false
	_recycle()

func _build_jagged_points(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	# 2026-10-26 视觉优化：段长 28→14，折点细腻，告别大折角塑料棍观感
	return build_jagged_points(from_pos, to_pos, 14.0, 7.5)

## 锯齿折线生成（主干/微弧共用一把尺，T-2.5 参数化）：seg_len 控制折段密度、
## amp_max 控制法向抖幅（双层正弦 + 高斯高频抖颤，形成真实电击穿轮廓）
static func build_jagged_points(from_pos: Vector2, to_pos: Vector2, seg_len: float, amp_max: float) -> PackedVector2Array:
	var dist := from_pos.distance_to(to_pos)
	var segs := maxi(int(dist / seg_len), 4)
	var dir := to_pos - from_pos
	var side := dir.orthogonal().normalized()
	var points := PackedVector2Array()
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var p := dir * t
		if i > 0 and i < segs:
			# 大体沿程包络 + 局部高频折颤，还原闪电跳跃电离感
			var envelope := sin(t * PI)
			var jitter := randf_range(-0.4, 0.4)
			var amp := amp_max * (envelope * 0.75 + jitter * 0.25)
			p += side * randf_range(-amp, amp)
		points.append(p)
	return points

func _build_branch_points(main_pts: PackedVector2Array, main_dir: Vector2) -> PackedVector2Array:
	if main_pts.size() < 4:
		return PackedVector2Array()
	# 从主干 35% ~ 65% 之间随机挑一个分叉点
	var fork_idx := randi_range(int(main_pts.size() * 0.35), int(main_pts.size() * 0.65))
	var fork_origin: Vector2 = main_pts[fork_idx]
	var side_sign := 1.0 if randf() > 0.5 else -1.0
	var branch_dir := main_dir.normalized().rotated(side_sign * randf_range(0.45, 0.85))

	var branch := PackedVector2Array()
	branch.append(fork_origin)
	var len1 := randf_range(16.0, 24.0)
	branch.append(fork_origin + branch_dir * len1)
	var branch_dir2 := branch_dir.rotated(side_sign * randf_range(-0.35, 0.35))
	var len2 := randf_range(10.0, 16.0)
	branch.append(fork_origin + branch_dir * len1 + branch_dir2 * len2)
	return branch
