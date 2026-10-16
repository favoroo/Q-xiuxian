class_name BeyondBoundaryLayer
extends Node2D

## 结界外深渊远景剪影层（幽冥残峰 / 南侧断崖 / 古刹残柱），从 GroundDecorLayer 拆出。
## 纯静态一次性 _draw()，每帧只挪 position 做视差（不触发重绘，零绘制开销）。
## 视差用「反向跟相机」而非 ParallaxLayer：后者是 CanvasLayer 系，要和世界坐标系
## 的结界边界对齐得调 motion mirroring，弯道多；直接 position = cam * (1 - f) 一目了然。
## ⚠ T-4.2（2026-10-15）：剪影层之上加两层慢速飘雾（视差 0.3 / 0.6 相对主体反向错位）
##   与北侧山脊后 3-5 条竖直幽光柱（半透明梯形渐变，死亡细胞背景式）。
##   飘雾仍守「每帧只挪 position 零重绘」：雾团自身缓漂走常驻 tween 循环。

## 视差系数：0.45 = 远景以相机 45% 的速度移动，立刻出纵深但不穿帮
const PARALLAX_FACTOR := 0.45

# —— T-4.2 双层飘雾（大尺寸半透明雾团，modulate alpha ≤0.15）——
## 雾层视差系数：0.3 比主体（0.45）慢 = 更远；0.6 比主体快 = 更近；相对主体一正一负即「反向错位」。
## 子层挂在 self（0.45 层）下，position 补偿量 = cam * (PARALLAX_FACTOR - 层系数)。
const FOG_FACTOR_FAR := 0.30
const FOG_FACTOR_NEAR := 0.60
const FOG_ALPHA := 0.12            ## 雾团 alpha 上限内取值（任务卡 ≤0.15）
const FOG_COLOR := Color(0.10, 0.22, 0.32)  ## 深渊冷墨蓝雾
const FOG_DRIFT_AMPLITUDE := 90.0  ## 雾团自漂单程幅度（px，往返）
const FOG_DRIFT_DURATION := 26.0   ## 雾团自漂单程时长（s，慢速量）
## 光柱（竖直幽光，山脊后升起）：底亮顶消的半透明梯形，颜色压在 LDR（不起辉，氛围件不抢戏）
const PILLAR_COLOR := Color(0.50, 0.72, 0.92, 0.12)
const PILLAR_SEGMENTS := 10        ## 梯形垂直分段数（分段渐变足够平滑）

var half_extent: float = 560.0
var _fog_far: Node2D = null
var _fog_near: Node2D = null

func _ready() -> void:
	# 与 GroundDecorLayer 同档：地砖之上、ArenaVisualLayer 之下，不越过实体层
	z_index = 0
	_setup_fog_layers()

## 双层飘雾装配：远层雾团大而稀、近层稍小稍密；每层 3 团错位铺开。
## 自漂用常驻 tween 往返（EASE_IN_OUT），与 Main._setup_ambient_mist 同款手法；
## 层 position 每帧在 _process 里按视差补偿，雾团本身零 CPU 重绘。
func _setup_fog_layers() -> void:
	var fog_tex: Texture2D = preload("res://assets/art/light_radial.png")
	# 各层配置：[视差系数, 雾团数, 雾团横向拉伸, 位置锚样本（比例坐标，乘 half_extent）]
	var layer_cfgs := [
		[FOG_FACTOR_FAR, 3, Vector2(13.0, 4.5), [Vector2(0.0, -1.25), Vector2(-0.62, -0.72), Vector2(0.55, -0.55)]],
		[FOG_FACTOR_NEAR, 3, Vector2(9.0, 3.4), [Vector2(0.35, 1.18), Vector2(-0.5, 0.86), Vector2(0.1, 0.62)]],
	]
	for cfg in layer_cfgs:
		var layer := Node2D.new()
		layer.name = "Fog%s" % ("Far" if cfg[0] == FOG_FACTOR_FAR else "Near")
		var anchors: Array = cfg[3]
		for i in anchors.size():
			var puff := Sprite2D.new()
			puff.texture = fog_tex
			puff.scale = Vector2(cfg[2]) * (1.0 + 0.25 * float(i % 2))  # 同层两档尺寸错开
			puff.modulate = Color(FOG_COLOR, FOG_ALPHA)
			puff.position = anchors[i] * half_extent
			layer.add_child(puff)
			# 缓漂：横向往返 + 极慢时长，各团错相（按 instance_id 偏移，照 JuiceEffect 错相惯例）
			var phase := fposmod(float(puff.get_instance_id() % 100) * 0.01, 1.0)
			var tw := create_tween().set_loops()
			tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			var target := puff.position + Vector2(FOG_DRIFT_AMPLITUDE * (1.0 if i % 2 == 0 else -1.0), FOG_DRIFT_AMPLITUDE * 0.12)
			tw.tween_property(puff, "position", target, FOG_DRIFT_DURATION * (0.8 + 0.4 * phase))\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(puff, "position", anchors[i] * half_extent, FOG_DRIFT_DURATION * (0.8 + 0.4 * phase))\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		add_child(layer)
		if cfg[0] == FOG_FACTOR_FAR:
			_fog_far = layer
		else:
			_fog_near = layer

## 帧级相机查询缓存（2026-10-16，照 HollowKnightEnemyRenderer 范式）：
## get_viewport/get_camera_2d 的返回值在同一渲染帧内对全部节点相同，
## 全屏常显层没理由每帧付 4 次引擎查询——每渲染帧只查一次。
static var _cam_frame: int = -1
static var _cam_cache: Camera2D = null

func _process(_delta: float) -> void:
	var frame := Engine.get_frames_drawn()
	if frame != _cam_frame:
		_cam_frame = frame
		_cam_cache = get_viewport().get_camera_2d()
	var cam := _cam_cache
	if cam != null:
		var cam_pos := cam.global_position
		position = cam_pos * (1.0 - PARALLAX_FACTOR)
		# 雾层视差补偿（子层 world = self.position + child.position）：
		# 远层比主体慢 → 正补偿；近层比主体快 → 负补偿（反向错位）
		if _fog_far != null:
			_fog_far.position = cam_pos * (PARALLAX_FACTOR - FOG_FACTOR_FAR)
		if _fog_near != null:
			_fog_near.position = cam_pos * (PARALLAX_FACTOR - FOG_FACTOR_NEAR)

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4217  # 固定种子确保装饰确定性，不占用或污染 GameManager.rng 战斗流

	var h: float = half_extent
	var col_shadow := Color(0.015, 0.025, 0.04, 0.95)
	var col_stone := Color(0.025, 0.04, 0.06, 0.90)
	var col_faint_cyan := Color(0.18, 0.55, 0.75, 0.14)

	# T-4.2 远景竖直幽光柱（北侧山脊后升起，3-5 条）：先画柱再画山，
	# 山体剪影盖住柱底 → 天然「从山后透出」的层次。位置确定性用本层固定种子 rng。
	_draw_soul_pillars(rng, h)

	# 北侧远景：幽冥残峰奇石起伏（y 在 -(h+40) ~ -(h+160) 之间）。
	# 横向留足 ±(h+180) 余量：相机拉到战场边缘时视差回挪，剪影仍需盖住视口缺口。
	var north_pts := PackedVector2Array()
	north_pts.append(Vector2(-h - 180.0, -h - 20.0))
	var peak_x: float = -h - 180.0
	while peak_x < h + 180.0:
		var step: float = rng.randf_range(35.0, 75.0)
		peak_x += step
		var peak_y: float = -h - rng.randf_range(40.0, 160.0)
		north_pts.append(Vector2(peak_x, peak_y))
	north_pts.append(Vector2(h + 180.0, -h - 20.0))
	if north_pts.size() >= 3:
		draw_colored_polygon(north_pts, col_shadow)
		draw_polyline(north_pts, col_stone, 1.5)

		# 南侧断崖远影（y 在 +(h+30) ~ +(h+140) 之间）
	var south_pts := PackedVector2Array()
	south_pts.append(Vector2(-h - 180.0, h + 20.0))
	var s_x: float = -h - 180.0
	while s_x < h + 180.0:
		var step_s: float = rng.randf_range(40.0, 80.0)
		s_x += step_s
		var s_y: float = h + rng.randf_range(40.0, 140.0)
		south_pts.append(Vector2(s_x, s_y))
	south_pts.append(Vector2(h + 180.0, h + 20.0))
	if south_pts.size() >= 3:
		draw_colored_polygon(south_pts, col_shadow)
		draw_polyline(south_pts, col_stone, 1.5)

	# 东西两侧深渊中矗立的古刹残柱剪影
	var pillar_xs := [-h - 60.0, -h - 130.0, h + 60.0, h + 130.0]
	for px in pillar_xs:
		var py_base: float = rng.randf_range(-h + 60.0, h - 60.0)
		var p_w: float = rng.randf_range(20.0, 36.0)
		var p_h: float = rng.randf_range(60.0, 120.0)
		var sign_x: float = -1.0 if px < 0.0 else 1.0
		var pts := PackedVector2Array([
			Vector2(px, py_base),
			Vector2(px + sign_x * p_w * 0.4, py_base - p_h * 0.7),
			Vector2(px + sign_x * p_w * 0.8, py_base - p_h),
			Vector2(px + sign_x * p_w, py_base)
		])
		draw_colored_polygon(pts, col_stone)
		draw_polyline(pts, col_shadow, 1.5)
		# 柱顶微弱幽芒
		draw_circle(Vector2(px + sign_x * p_w * 0.8, py_base - p_h), 3.0, col_faint_cyan)

## T-4.2 远景竖直幽光柱：4 条（3-5 档取中），半透明梯形，底→顶分段渐隐。
## 只在北侧山脊带（y ≈ -h-40 ~ -h-190）分布，宽度 26-46px；纯 LDR 低透，氛围件不抢戏。
func _draw_soul_pillars(rng: RandomNumberGenerator, h: float) -> void:
	var count := 4
	var x_span := h + 140.0
	for i in count:
		# 锚位用序数比例 + rng 抖动，横跨战场北侧，避开正中（那里有中心碑）
		var t := (float(i) + 0.5) / float(count)
		var px := (-x_span + 2.0 * x_span * t) + rng.randf_range(-60.0, 60.0)
		if absf(px) < 90.0:
			px += 150.0 * (1.0 if px >= 0.0 else -1.0)  # 让开中心碑方位
		var p_top := -h - rng.randf_range(150.0, 210.0)
		var p_base := -h - rng.randf_range(30.0, 60.0)
		var w := rng.randf_range(26.0, 46.0)
		# 分段梯形：每段 alpha 线性衰减（底亮顶消），段数内插足够平滑
		var seg_h := (p_base - p_top) / float(PILLAR_SEGMENTS)
		for s in PILLAR_SEGMENTS:
			var a0 := PILLAR_COLOR.a * (1.0 - float(s) / float(PILLAR_SEGMENTS))
			var a1 := PILLAR_COLOR.a * (1.0 - float(s + 1) / float(PILLAR_SEGMENTS))
			var y0 := p_base - seg_h * float(s)
			var y1 := y0 - seg_h
			var w0 := w * (1.0 - 0.25 * float(s) / float(PILLAR_SEGMENTS))
			var w1 := w * (1.0 - 0.25 * float(s + 1) / float(PILLAR_SEGMENTS))
			var seg := PackedVector2Array([
				Vector2(px - w0 * 0.5, y0), Vector2(px + w0 * 0.5, y0),
				Vector2(px + w1 * 0.5, y1), Vector2(px - w1 * 0.5, y1),
			])
			var col := PILLAR_COLOR
			col.a = (a0 + a1) * 0.5
			draw_colored_polygon(seg, col)
